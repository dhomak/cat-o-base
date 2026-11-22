"""Pet-o-Base — a small self-hosted records app for cats.

Flask + SQLite. All data (database + uploaded media) lives in CATOBASE_DATA
(default ./data). Run with gunicorn: gunicorn -w 2 -b 0.0.0.0:8000 app:app
"""
import calendar
import datetime as dt
import io
import json
import os
import secrets
import shutil
import sqlite3
import tempfile
import uuid
import zipfile

from flask import (Flask, abort, after_this_request, flash, g, make_response, redirect,
                   render_template, request, send_file, send_from_directory,
                   url_for, Response)
from markupsafe import Markup, escape
from PIL import Image, ImageOps
from werkzeug.utils import secure_filename

from i18n import LANGUAGES, detect_language, format_age, format_date, gettext as _, ngettext as _n

try:  # optional: iPhone HEIC uploads
    from pillow_heif import register_heif_opener
    register_heif_opener()
except Exception:  # pragma: no cover
    pass

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("CATOBASE_DATA") or os.environ.get("CATDB_DATA") or os.path.join(BASE, "data")
MEDIA = os.path.join(DATA, "media")
DB_NAME = "catobase.sqlite3"
LEGACY_DB_NAMES = ("catdb.sqlite3",)  # pre-rename installs and backups
DB_PATH = os.path.join(DATA, DB_NAME)
os.makedirs(MEDIA, exist_ok=True)
for _old in LEGACY_DB_NAMES:
    if not os.path.exists(DB_PATH) and os.path.exists(os.path.join(DATA, _old)):
        os.rename(os.path.join(DATA, _old), DB_PATH)


def _secret():
    p = os.path.join(DATA, ".secret")
    if not os.path.exists(p):
        with open(p, "w") as f:
            f.write(secrets.token_hex(32))
    with open(p) as f:
        return f.read().strip()


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = int(os.environ.get("CATOBASE_MAX_UPLOAD_MB") or os.environ.get("CATDB_MAX_UPLOAD_MB") or "200") * 1024 * 1024
app.secret_key = os.environ.get("CATOBASE_SECRET") or _secret()


@app.before_request
def _choose_language():
    g.lang = detect_language()


@app.route("/lang/<code>")
def set_language(code):
    target = request.args.get("next") or url_for("index")
    if not target.startswith("/"):
        target = url_for("index")
    resp = redirect(target)
    if code in LANGUAGES:
        resp.set_cookie("lang", code, max_age=3600 * 24 * 365)
    return resp


def sex_label(sex):
    return {"female": _("female"), "male": _("male")}.get(sex or "", sex or "")


def kind_label(kind):
    return {"medication": _("medication"), "flea/tick": _("flea / tick"), "deworming": _("deworming"),
            "supplement": _("supplement"), "other": _("other")}.get(kind or "other", kind)


app.jinja_env.globals.update(_=_, _n=_n, LANGUAGES=LANGUAGES, sex_label=sex_label, kind_label=kind_label,
                             lang="en")


@app.context_processor
def _language_context():
    return {"lang": g.get("lang", "en")}

SCHEMA = """
CREATE TABLE IF NOT EXISTS cats(
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, sex TEXT, neutered INTEGER DEFAULT 0,
  breed TEXT, markings TEXT, birthday TEXT, birthday_approx INTEGER DEFAULT 0,
  adoption_date TEXT, microchip TEXT, special_needs TEXT, allergies TEXT,
  food_brand TEXT, food_portion TEXT, food_schedule TEXT, food_notes TEXT,
  notes TEXT, profile_photo_id INTEGER, archived INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  species TEXT DEFAULT 'cat', is_guest INTEGER DEFAULT 0, guest_from TEXT, guest_since TEXT,
  guest_contacts TEXT, share_id TEXT);
CREATE TABLE IF NOT EXISTS photos(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  filename TEXT NOT NULL, caption TEXT, taken_on TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS weights(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  date TEXT NOT NULL, kg REAL NOT NULL);
CREATE TABLE IF NOT EXISTS vaccinations(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  name TEXT NOT NULL, date_given TEXT, next_due TEXT, vet TEXT, notes TEXT);
CREATE TABLE IF NOT EXISTS treatments(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  kind TEXT, name TEXT NOT NULL, dose TEXT, schedule TEXT, interval_days INTEGER,
  last_given TEXT, next_due TEXT, end_date TEXT, active INTEGER DEFAULT 1, notes TEXT);
CREATE TABLE IF NOT EXISTS visits(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  date TEXT NOT NULL, clinic TEXT, reason TEXT, outcome TEXT, cost TEXT, notes TEXT);
CREATE TABLE IF NOT EXISTS documents(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  title TEXT, filename TEXT NOT NULL, original_name TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS logs(
  id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL REFERENCES cats(id) ON DELETE CASCADE,
  date TEXT NOT NULL, kind TEXT, text TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS contacts(
  id INTEGER PRIMARY KEY, role TEXT, name TEXT NOT NULL, phone TEXT, address TEXT, notes TEXT);
"""


# ---------------------------------------------------------------- database
def db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys=ON")
    return g.db


@app.teardown_appcontext
def _close_db(_exc):
    d = g.pop("db", None)
    if d is not None:
        d.close()


# Columns added after the first release: (table, column, definition).
MIGRATIONS = [
    ("cats", "species", "TEXT DEFAULT 'cat'"),
    ("cats", "is_guest", "INTEGER DEFAULT 0"),
    ("cats", "guest_from", "TEXT"),
    ("cats", "guest_since", "TEXT"),
    ("cats", "guest_contacts", "TEXT"),  # JSON list of {role, name, phone, address, notes}
    ("cats", "share_id", "TEXT"),        # matches the Apple app's shareID
]


def init_db():
    con = sqlite3.connect(DB_PATH)
    con.executescript(SCHEMA)
    for table, column, definition in MIGRATIONS:
        existing = {row[1] for row in con.execute(f"PRAGMA table_info({table})")}
        if column not in existing:
            con.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")
    con.commit()
    con.close()


init_db()


def q(sql, args=(), one=False):
    rows = db().execute(sql, args).fetchall()
    if one:
        return rows[0] if rows else None
    return rows


def x(sql, args=()):
    cur = db().execute(sql, args)
    db().commit()
    return cur.lastrowid


# ------------------------------------------------------------------- dates
def today():
    return dt.date.today()


def pdate(s):
    if not s:
        return None
    try:
        return dt.date.fromisoformat(str(s)[:10])
    except ValueError:
        return None


def add_months(d, n):
    y, m = divmod(d.month - 1 + n, 12)
    y += d.year
    m += 1
    return dt.date(y, m, min(d.day, calendar.monthrange(y, m)[1]))


@app.template_filter("age")
def age_filter(b):
    b = pdate(b)
    if not b:
        return "—"
    t = today()
    months = (t.year - b.year) * 12 + t.month - b.month - (t.day < b.day)
    if months < 0:
        return "—"
    y, m = divmod(months, 12)
    if y == 0:
        return format_age(0, m)
    return format_age(y, m)


@app.template_filter("d")
def date_filter(s):
    d = pdate(s)
    return format_date(d) if d else (s or "—")


def due_status(s):
    d = pdate(s)
    if not d:
        return ("none", "")
    n = (d - today()).days
    if n < 0:
        return ("overdue", _("{n} d overdue", n=-n))
    if n == 0:
        return ("soon", _("today"))
    if n <= 14:
        return ("soon", _("in {n} d", n=n))
    return ("ok", _("in {n} d", n=n))


app.jinja_env.globals.update(due_status=due_status, today=lambda: today().isoformat())


# ------------------------------------------------------------------- media
def save_image(fs):
    try:
        im = Image.open(fs.stream)
        im = ImageOps.exif_transpose(im).convert("RGB")
    except Exception:
        return None
    name = uuid.uuid4().hex + ".jpg"
    big = im.copy()
    big.thumbnail((2000, 2000))
    big.save(os.path.join(MEDIA, name), "JPEG", quality=88)
    ImageOps.fit(im, (600, 600)).save(os.path.join(MEDIA, "t_" + name), "JPEG", quality=82)
    return name


def rm_media(name):
    if not name:
        return
    for n in (name, "t_" + name):
        p = os.path.join(MEDIA, os.path.basename(n))
        if os.path.exists(p):
            os.remove(p)


@app.route("/media/<path:name>")
def media(name):
    return send_from_directory(MEDIA, name, max_age=86400 * 30)


# --------------------------------------------------------------- due items
def due_items(cat_id=None):
    flt = " AND c.id=?" if cat_id else ""
    args = (cat_id, cat_id) if cat_id else ()
    rows = q(f"""
      SELECT 'vaccine' kind, v.id, v.cat_id, c.name cat, v.name item, v.next_due due
        FROM vaccinations v JOIN cats c ON c.id=v.cat_id
       WHERE v.next_due IS NOT NULL AND c.archived=0 {flt}
         AND NOT EXISTS (SELECT 1 FROM vaccinations v2 WHERE v2.cat_id=v.cat_id
                         AND lower(v2.name)=lower(v.name)
                         AND COALESCE(v2.date_given,'') > COALESCE(v.date_given,''))
      UNION ALL
      SELECT 'treatment', t.id, t.cat_id, c.name, t.name, t.next_due
        FROM treatments t JOIN cats c ON c.id=t.cat_id
       WHERE t.active=1 AND t.next_due IS NOT NULL AND c.archived=0 {flt}
         AND (t.end_date IS NULL OR t.end_date >= t.next_due)
      ORDER BY due""", args)
    return [dict(r) for r in rows]


# ------------------------------------------------------------ weight chart
def weight_trend(ws):
    """ws: newest first."""
    if not ws:
        return None
    cur = ws[0]
    out = {"kg": cur["kg"]}
    if len(ws) > 1:
        out["delta"] = round(cur["kg"] - ws[1]["kg"], 2)
    cutoff = (pdate(cur["date"]) or today()) - dt.timedelta(days=183)
    older = [w for w in ws if pdate(w["date"]) and pdate(w["date"]) <= cutoff]
    ref = older[0] if older else (ws[-1] if len(ws) > 1 else None)
    if ref and ref["kg"]:
        pct = (cur["kg"] - ref["kg"]) / ref["kg"] * 100
        out["pct"] = round(pct, 1)
        out["since"] = ref["date"]
        out["warn"] = pct <= -10
    return out


def weight_chart(ws):
    """ws: oldest first."""
    pts = [(pdate(w["date"]), w["kg"]) for w in ws if pdate(w["date"])]
    if len(pts) < 2:
        return None
    W, H, PL, PR, PT, PB = 640, 190, 44, 16, 14, 28
    d0, d1 = pts[0][0], pts[-1][0]
    span = max((d1 - d0).days, 1)
    lo, hi = min(k for _, k in pts), max(k for _, k in pts)
    pad = max((hi - lo) * 0.2, 0.2)
    lo, hi = lo - pad, hi + pad

    def X(d):
        return PL + (d - d0).days / span * (W - PL - PR)

    def Y(k):
        return PT + (hi - k) / (hi - lo) * (H - PT - PB)

    parts = [f'<svg viewBox="0 0 {W} {H}" class="chart" role="img" aria-label="Weight over time">']
    for i in range(4):
        k = lo + (hi - lo) * i / 3
        y = Y(k)
        parts.append(f'<line x1="{PL}" x2="{W-PR}" y1="{y:.1f}" y2="{y:.1f}" class="grid"/>'
                     f'<text x="{PL-6}" y="{y+4:.1f}" class="lbl" text-anchor="end">{k:.1f}</text>')
    poly = " ".join(f"{X(d):.1f},{Y(k):.1f}" for d, k in pts)
    area = f"{X(pts[0][0]):.1f},{H-PB} {poly} {X(pts[-1][0]):.1f},{H-PB}"
    parts.append(f'<polygon points="{area}" class="area"/>')
    parts.append(f'<polyline points="{poly}" class="line"/>')
    for d, k in pts:
        parts.append(f'<circle cx="{X(d):.1f}" cy="{Y(k):.1f}" r="3.5" class="pt">'
                     f'<title>{format_date(d)}: ' + _("{kg} kg", kg=f"{k:g}") + '</title></circle>')
    parts.append(f'<text x="{PL}" y="{H-8}" class="lbl">{d0.strftime("%b %Y")}</text>'
                 f'<text x="{W-PR}" y="{H-8}" class="lbl" text-anchor="end">{d1.strftime("%b %Y")}</text>')
    parts.append("</svg>")
    return Markup("".join(parts))


# ----------------------------------------------------------------- species
SPECIES = {
    # key: (label, emoji, breed hint, vaccine suggestions)
    "cat": ("Cat", "🐈", "domestic shorthair", ["Rabies", "FVRCP (tricat)", "FeLV", "Chlamydia", "FIP"]),
    "dog": ("Dog", "🐕", "beagle", ["Rabies", "DHPP", "Leptospirosis", "Bordetella", "Lyme"]),
    "rabbit": ("Rabbit", "🐇", "Holland Lop", ["RHDV1", "RHDV2", "Myxomatosis"]),
    "bird": ("Bird", "🐦", "budgie", ["Polyomavirus"]),
    "rat": ("Rat", "🐀", "fancy rat", []),
    "other": ("Other", "🐾", "breed or kind", ["Rabies"]),
}


def species_of(row):
    key = (row["species"] if row is not None and "species" in row.keys() else None) or "cat"
    return key if key in SPECIES else "other"


app.jinja_env.globals.update(SPECIES=SPECIES, species_of=species_of)


# ------------------------------------------------------------------ phones
COUNTRY_CODE = os.environ.get("CATOBASE_COUNTRY_CODE", "972")  # for local numbers starting with 0


def phone_links(phone):
    """tel/sms/WhatsApp/Telegram links for a number, or None."""
    cleaned = "".join(ch for ch in (phone or "") if ch in "+0123456789")
    if sum(ch.isdigit() for ch in cleaned) < 3:
        return None
    if cleaned.startswith("+"):
        intl = cleaned[1:]
    elif cleaned.startswith("00"):
        intl = cleaned[2:]
    elif cleaned.startswith("0") and COUNTRY_CODE:
        intl = COUNTRY_CODE + cleaned[1:]
    else:
        intl = cleaned
    return {"tel": f"tel:{cleaned}", "sms": f"sms:{cleaned}",
            "whatsapp": f"https://wa.me/{intl}", "telegram": f"https://t.me/+{intl}"}


app.jinja_env.globals.update(phone_links=phone_links)


# -------------------------------------------------------------------- pets
CAT_FIELDS = ["name", "species", "sex", "breed", "markings", "birthday", "adoption_date", "microchip",
              "special_needs", "allergies", "food_brand", "food_portion", "food_schedule",
              "food_notes", "notes", "guest_from", "guest_since"]
CAT_BOOLS = ["neutered", "birthday_approx", "archived", "is_guest"]
SORTS = {"name": "Name", "oldest": "Age, oldest first", "youngest": "Age, youngest first"}


def guest_contacts(row):
    try:
        return json.loads(row["guest_contacts"] or "[]")
    except (ValueError, TypeError, KeyError, IndexError):
        return []


app.jinja_env.globals.update(guest_contacts=guest_contacts)


def contacts_from_form():
    """Owner's contacts typed into the guest section of the pet form."""
    rows = zip(request.form.getlist("gc_role"), request.form.getlist("gc_name"), request.form.getlist("gc_phone"))
    out = [{"role": r.strip(), "name": n.strip(), "phone": ph.strip(), "address": "", "notes": ""}
           for r, n, ph in rows if n.strip() or ph.strip()]
    return json.dumps(out, ensure_ascii=False) if out else None


def sort_cats(cats, sort):
    by_name = sorted(cats, key=lambda c: (c["name"] or "").lower())
    if sort not in ("oldest", "youngest"):
        return by_name
    with_bday = [c for c in by_name if pdate(c["birthday"])]
    without = [c for c in by_name if not pdate(c["birthday"])]
    with_bday.sort(key=lambda c: pdate(c["birthday"]), reverse=(sort == "youngest"))
    return with_bday + without


def form_vals(fields):
    return {f: (request.form.get(f, "").strip() or None) for f in fields}


def get_cat(cid):
    c = q("SELECT * FROM cats WHERE id=?", (cid,), one=True)
    if not c:
        abort(404)
    return c


@app.route("/")
def index():
    arch = request.args.get("archived") == "1"
    sort = request.args.get("sort") or request.cookies.get("sort") or "name"
    search = (request.args.get("q") or "").strip().lower()
    cats = q("""
      SELECT c.*,
        COALESCE(p.filename,(SELECT filename FROM photos WHERE cat_id=c.id ORDER BY id DESC LIMIT 1)) photo,
        (SELECT kg FROM weights w WHERE w.cat_id=c.id ORDER BY date DESC, id DESC LIMIT 1) kg
      FROM cats c LEFT JOIN photos p ON p.id=c.profile_photo_id
      WHERE c.archived=? ORDER BY c.name COLLATE NOCASE""", (1 if arch else 0,))
    due = due_items()
    alerts = {}
    for d in due:
        st = due_status(d["due"])[0]
        if st in ("overdue", "soon"):
            alerts.setdefault(d["cat_id"], set()).add(st)
    upcoming = [d for d in due if (pdate(d["due"]) - today()).days <= 60]
    n_arch = q("SELECT count(*) n FROM cats WHERE archived=1", one=True)["n"]
    if search:
        cats = [c for c in cats if any(search in (v or "").lower() for v in (
            c["name"], c["breed"], c["markings"], c["guest_from"], c["microchip"],
            SPECIES[species_of(c)][0], _(SPECIES[species_of(c)][0])))]
    cats = sort_cats(cats, sort)
    resp = make_response(render_template(
        "index.html", mine=[c for c in cats if not c["is_guest"]], guests=[c for c in cats if c["is_guest"]],
        due=upcoming, alerts=alerts, arch=arch, n_arch=n_arch, sort=sort, sorts=SORTS, search=search))
    if request.args.get("sort") in SORTS:
        resp.set_cookie("sort", request.args["sort"], max_age=3600 * 24 * 365)
    return resp


@app.route("/due")
def due_page():
    return render_template("due.html", due=due_items())


@app.route("/cat/new", methods=["GET", "POST"])
@app.route("/cat/<int:cid>/edit", methods=["GET", "POST"])
def cat_form(cid=None):
    cat = get_cat(cid) if cid else None
    if request.method == "POST":
        v = form_vals(CAT_FIELDS)
        if not v["name"]:
            flash(_("A pet needs a name."))
            return render_template("cat_form.html", cat=request.form, cid=cid)
        for b in CAT_BOOLS:
            v[b] = 1 if request.form.get(b) else 0
        v["species"] = v["species"] if v["species"] in SPECIES else "cat"
        if v["is_guest"]:
            v["guest_contacts"] = contacts_from_form()
            v["guest_since"] = v["guest_since"] or today().isoformat()
        else:
            v["guest_from"] = v["guest_since"] = v["guest_contacts"] = None
        if cid:
            x(f"UPDATE cats SET {', '.join(k + '=?' for k in v)} WHERE id=?", (*v.values(), cid))
        else:
            cid = x(f"INSERT INTO cats({', '.join(v)}) VALUES({', '.join('?' * len(v))})",
                    tuple(v.values()))
            f = request.files.get("photo")
            if f and f.filename:
                name = save_image(f)
                if name:
                    pid = x("INSERT INTO photos(cat_id, filename) VALUES(?,?)", (cid, name))
                    x("UPDATE cats SET profile_photo_id=? WHERE id=?", (pid, cid))
        return redirect(url_for("cat", cid=cid))
    if cat is None and request.args.get("guest") == "1":
        cat = {"is_guest": 1, "guest_since": today().isoformat(), "species": "cat",
               "guest_contacts": json.dumps([{"role": "Owner", "name": "", "phone": ""}])}
    return render_template("cat_form.html", cat=cat, cid=cid)


@app.route("/cat/<int:cid>")
def cat(cid):
    c = get_cat(cid)
    photos = q("SELECT * FROM photos WHERE cat_id=? ORDER BY COALESCE(taken_on, created_at) DESC, id DESC", (cid,))
    profile = next((p for p in photos if p["id"] == c["profile_photo_id"]), photos[0] if photos else None)
    weights = q("SELECT * FROM weights WHERE cat_id=? ORDER BY date DESC, id DESC", (cid,))
    return render_template(
        "cat.html", c=c, photos=photos, profile=profile, weights=weights,
        chart=weight_chart(list(reversed(weights))), trend=weight_trend(weights),
        vaccines=q("SELECT * FROM vaccinations WHERE cat_id=? ORDER BY COALESCE(date_given,'') DESC, id DESC", (cid,)),
        treatments=q("SELECT * FROM treatments WHERE cat_id=? ORDER BY active DESC, COALESCE(next_due,'9999'), id DESC", (cid,)),
        visits=q("SELECT * FROM visits WHERE cat_id=? ORDER BY date DESC, id DESC", (cid,)),
        documents=q("SELECT * FROM documents WHERE cat_id=? ORDER BY id DESC", (cid,)),
        logs=q("SELECT * FROM logs WHERE cat_id=? ORDER BY date DESC, id DESC", (cid,)),
        due=due_items(cid))


@app.post("/cat/<int:cid>/delete")
def cat_delete(cid):
    c = get_cat(cid)
    if request.form.get("confirm", "").strip() != c["name"]:
        flash(_("Type the pet's name exactly to delete the whole record."))
        return redirect(url_for("cat_form", cid=cid))
    _delete_pet(cid)
    flash(_("{name} deleted.", name=c["name"]))
    return redirect(url_for("index"))


# ------------------------------------------------------------- sub records
SUB = {
    "weight": ("weights", ["date", "kg"]),
    "vaccine": ("vaccinations", ["name", "date_given", "next_due", "vet", "notes"]),
    "treatment": ("treatments", ["kind", "name", "dose", "schedule", "interval_days",
                                 "last_given", "next_due", "end_date", "notes"]),
    "visit": ("visits", ["date", "clinic", "reason", "outcome", "cost", "notes"]),
    "log": ("logs", ["date", "kind", "text"]),
}
REQUIRED = {"weight": "kg", "vaccine": "name", "treatment": "name", "log": "text"}


@app.post("/cat/<int:cid>/add/<kind>")
def add_sub(cid, kind):
    get_cat(cid)
    if kind not in SUB:
        abort(404)
    table, fields = SUB[kind]
    v = form_vals(fields)
    back = url_for("cat", cid=cid) + "#" + kind
    req = REQUIRED.get(kind)
    if req and not v[req]:
        flash(_("{field} is required.", field=_(req.replace('_', ' ').capitalize())))
        return redirect(back)
    if "date" in v and not v["date"]:
        v["date"] = today().isoformat()
    if kind == "weight":
        try:
            kg = float(v["kg"].replace(",", "."))
            if request.form.get("unit") == "lb":
                kg = round(kg * 0.45359237, 2)
            v["kg"] = kg
        except ValueError:
            flash(_("Weight must be a number."))
            return redirect(back)
    if kind == "vaccine":
        rep = request.form.get("repeat_months")
        given = pdate(v["date_given"])
        if not v["next_due"] and rep and given:
            v["next_due"] = add_months(given, int(rep)).isoformat()
    if kind == "treatment":
        try:
            v["interval_days"] = int(v["interval_days"]) if v["interval_days"] else None
        except ValueError:
            v["interval_days"] = None
        last = pdate(v["last_given"])
        if not v["next_due"] and v["interval_days"] and last:
            v["next_due"] = (last + dt.timedelta(days=v["interval_days"])).isoformat()
    x(f"INSERT INTO {table}(cat_id, {', '.join(v)}) VALUES(?, {', '.join('?' * len(v))})",
      (cid, *v.values()))
    return redirect(back)


@app.post("/treatment/<int:tid>/done")
def treatment_done(tid):
    t = q("SELECT * FROM treatments WHERE id=?", (tid,), one=True) or abort(404)
    d = pdate(request.form.get("date")) or today()
    nxt = (d + dt.timedelta(days=t["interval_days"])).isoformat() if t["interval_days"] else None
    x("UPDATE treatments SET last_given=?, next_due=? WHERE id=?", (d.isoformat(), nxt, tid))
    if request.form.get("back") == "index":
        return redirect(url_for("index"))
    return redirect(url_for("cat", cid=t["cat_id"]) + "#treatment")


@app.post("/treatment/<int:tid>/toggle")
def treatment_toggle(tid):
    t = q("SELECT * FROM treatments WHERE id=?", (tid,), one=True) or abort(404)
    x("UPDATE treatments SET active=? WHERE id=?", (0 if t["active"] else 1, tid))
    return redirect(url_for("cat", cid=t["cat_id"]) + "#treatment")


@app.post("/cat/<int:cid>/photos")
def add_photos(cid):
    c = get_cat(cid)
    n = 0
    caption = request.form.get("caption", "").strip() or None
    taken = request.form.get("taken_on") or None
    for f in request.files.getlist("photos"):
        if not f or not f.filename:
            continue
        name = save_image(f)
        if not name:
            flash(_("Couldn't read {file} as an image.", file=f.filename))
            continue
        pid = x("INSERT INTO photos(cat_id, filename, caption, taken_on) VALUES(?,?,?,?)",
                (cid, name, caption, taken))
        if not c["profile_photo_id"] and n == 0:
            x("UPDATE cats SET profile_photo_id=? WHERE id=?", (pid, cid))
        n += 1
    if n:
        flash(_n("{n} photos added", n))
    return redirect(url_for("cat", cid=cid) + "#photo")


@app.post("/photo/<int:pid>/profile")
def photo_profile(pid):
    p = q("SELECT * FROM photos WHERE id=?", (pid,), one=True) or abort(404)
    x("UPDATE cats SET profile_photo_id=? WHERE id=?", (pid, p["cat_id"]))
    return redirect(url_for("cat", cid=p["cat_id"]) + "#photo")


@app.post("/cat/<int:cid>/documents")
def add_document(cid):
    get_cat(cid)
    f = request.files.get("file")
    if not f or not f.filename:
        flash(_("Choose a file to upload."))
        return redirect(url_for("cat", cid=cid) + "#document")
    ext = os.path.splitext(secure_filename(f.filename))[1].lower()[:10]
    name = "d_" + uuid.uuid4().hex + ext
    f.save(os.path.join(MEDIA, name))
    title = request.form.get("title", "").strip() or f.filename
    x("INSERT INTO documents(cat_id, title, filename, original_name) VALUES(?,?,?,?)",
      (cid, title, name, f.filename))
    return redirect(url_for("cat", cid=cid) + "#document")


@app.route("/doc/<int:did>")
def document(did):
    d = q("SELECT * FROM documents WHERE id=?", (did,), one=True) or abort(404)
    return send_from_directory(MEDIA, d["filename"], download_name=d["original_name"] or d["filename"],
                               as_attachment=request.args.get("dl") == "1")


DELETABLE = {"weight": "weights", "vaccine": "vaccinations", "treatment": "treatments",
             "visit": "visits", "log": "logs", "photo": "photos", "document": "documents"}


@app.post("/del/<kind>/<int:rid>")
def delete(kind, rid):
    table = DELETABLE.get(kind) or abort(404)
    row = q(f"SELECT * FROM {table} WHERE id=?", (rid,), one=True) or abort(404)
    if kind == "photo":
        rm_media(row["filename"])
        x("UPDATE cats SET profile_photo_id=NULL WHERE profile_photo_id=?", (rid,))
    elif kind == "document":
        rm_media(row["filename"])
    x(f"DELETE FROM {table} WHERE id=?", (rid,))
    return redirect(url_for("cat", cid=row["cat_id"]) + "#" + kind)


# ---------------------------------------------------------------- contacts
@app.route("/contacts", methods=["GET", "POST"])
def contacts():
    if request.method == "POST":
        v = form_vals(["role", "name", "phone", "address", "notes"])
        if not v["name"]:
            flash(_("Name is required."))
        else:
            x("INSERT INTO contacts(role, name, phone, address, notes) VALUES(?,?,?,?,?)", tuple(v.values()))
        return redirect(url_for("contacts"))
    return render_template("contacts.html", contacts=q("SELECT * FROM contacts ORDER BY role, name"))


@app.post("/contacts/<int:rid>/delete")
def contact_delete(rid):
    x("DELETE FROM contacts WHERE id=?", (rid,))
    return redirect(url_for("contacts"))


# ------------------------------------------------------------ sitter sheet
@app.route("/sitter")
def sitter():
    cid = request.args.get("cat", type=int)
    cats = q("SELECT c.*, COALESCE(p.filename,(SELECT filename FROM photos WHERE cat_id=c.id ORDER BY id DESC LIMIT 1)) photo "
             "FROM cats c LEFT JOIN photos p ON p.id=c.profile_photo_id WHERE c.archived=0"
             + (" AND c.id=?" if cid else "") + " ORDER BY c.name COLLATE NOCASE", (cid,) if cid else ())
    meds = {}
    for t in q("SELECT * FROM treatments WHERE active=1 ORDER BY name"):
        if t["end_date"] and pdate(t["end_date"]) and pdate(t["end_date"]) < today():
            continue
        meds.setdefault(t["cat_id"], []).append(t)
    # Your contacts head the sheet unless every pet on it is a guest (their owner's
    # contacts are listed with each guest pet).
    own = q("SELECT * FROM contacts ORDER BY role, name") if any(not c["is_guest"] for c in cats) else []
    return render_template("sitter.html", cats=cats, meds=meds, contacts=own,
                           generated=today().isoformat())


# ---------------------------------------------------------------- calendar
def _ics_text(s):
    return (s or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


@app.route("/calendar.ics")
def calendar_ics():
    stamp = dt.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    L = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Pet-o-Base//EN", "CALSCALE:GREGORIAN",
         "METHOD:PUBLISH", "X-WR-CALNAME:Pet-o-Base", "REFRESH-INTERVAL;VALUE=DURATION:PT6H"]

    def event(uid, d, summary, rrule=None, alarm=False):
        L.extend(["BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{stamp}",
                  f"DTSTART;VALUE=DATE:{d.strftime('%Y%m%d')}",
                  f"DTEND;VALUE=DATE:{(d + dt.timedelta(days=1)).strftime('%Y%m%d')}",
                  f"SUMMARY:{_ics_text(summary)}"])
        if rrule:
            L.append(f"RRULE:{rrule}")
        if alarm:
            L.extend(["BEGIN:VALARM", "ACTION:DISPLAY", f"DESCRIPTION:{_ics_text(summary)}",
                      "TRIGGER:PT9H", "END:VALARM"])
        L.append("END:VEVENT")

    for d in due_items():
        dd = pdate(d["due"])
        if dd:
            event(f"{d['kind']}-{d['id']}-{dd.isoformat()}@cat-o-base", dd, f"{d['cat']}: {d['item']}", alarm=True)
    for c in q("SELECT * FROM cats WHERE archived=0"):
        b = pdate(c["birthday"])
        if b and not c["birthday_approx"]:
            event(f"bday-{c['id']}@cat-o-base", b, _("{name}'s birthday", name=c["name"]), rrule="FREQ=YEARLY")
        a = pdate(c["adoption_date"])
        if a:
            event(f"gotcha-{c['id']}@cat-o-base", a, _("{name} — gotcha day", name=c["name"]), rrule="FREQ=YEARLY")
    L.append("END:VCALENDAR")
    return Response("\r\n".join(L) + "\r\n", mimetype="text/calendar",
                    headers={"Content-Disposition": "inline; filename=pets.ics"})


# ------------------------------------------------------------------ backup
TABLES = ["cats", "photos", "weights", "vaccinations", "treatments", "visits", "documents", "logs", "contacts"]


@app.route("/backup")
def backup_page():
    size = sum(os.path.getsize(os.path.join(MEDIA, n)) for n in os.listdir(MEDIA))
    counts = {t: q(f"SELECT count(*) n FROM {t}", one=True)["n"] for t in TABLES}
    return render_template("backup.html", media_mb=size / 1048576, counts=counts, data_dir=DATA)


@app.route("/export.json")
def export_json():
    out = {"app": "cat-o-base", "exported": dt.datetime.now().isoformat(timespec="seconds"),
           **{t: [dict(r) for r in q(f"SELECT * FROM {t}")] for t in TABLES}}
    return Response(json.dumps(out, ensure_ascii=False, indent=2), mimetype="application/json",
                    headers={"Content-Disposition": f"attachment; filename=pet-o-base-{today()}.json"})


@app.route("/backup.zip")
def backup_zip():
    fd, path = tempfile.mkstemp(suffix=".zip")
    os.close(fd)
    snap = path + ".sqlite3"
    src, dst = sqlite3.connect(DB_PATH), sqlite3.connect(snap)
    src.backup(dst)
    dst.close()
    src.close()
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(snap, DB_NAME)
        for n in sorted(os.listdir(MEDIA)):
            z.write(os.path.join(MEDIA, n), "media/" + n, compress_type=zipfile.ZIP_STORED)
    os.remove(snap)
    resp = send_file(path, as_attachment=True, download_name=f"pet-o-base-backup-{today()}.zip")

    @after_this_request
    def _cleanup(r):
        try:
            os.remove(path)
        except OSError:
            pass
        return r

    return resp


@app.post("/restore")
def restore():
    if request.form.get("confirm") != "RESTORE":
        flash(_("Type RESTORE to confirm — this replaces everything."))
        return redirect(url_for("backup_page"))
    f = request.files.get("file")
    if not f or not f.filename:
        flash(_("Choose a backup .zip first."))
        return redirect(url_for("backup_page"))
    tmp = tempfile.mkdtemp(dir=DATA, prefix=".restore-")
    try:
        with zipfile.ZipFile(f.stream) as z:
            names = z.namelist()
            db_name = next((n for n in (DB_NAME, *LEGACY_DB_NAMES) if n in names), None)
            if not db_name:
                raise ValueError(_("not a Pet-o-Base backup (no {file} inside)", file=DB_NAME))
            for n in names:
                base = n[6:] if n.startswith("media/") else None
                if n == db_name or (base and "/" not in base and not base.startswith(".")
                                    and base == os.path.basename(base)):
                    z.extract(n, tmp)
        con = sqlite3.connect(os.path.join(tmp, db_name))
        con.execute("SELECT count(*) FROM cats").fetchone()
        con.close()
    except Exception as e:  # noqa: BLE001
        shutil.rmtree(tmp, ignore_errors=True)
        flash(_("Restore failed: {error}", error=e))
        return redirect(url_for("backup_page"))
    _close_db(None)
    shutil.rmtree(MEDIA, ignore_errors=True)
    new_media = os.path.join(tmp, "media")
    if os.path.isdir(new_media):
        shutil.move(new_media, MEDIA)
    else:
        os.makedirs(MEDIA)
    os.replace(os.path.join(tmp, db_name), DB_PATH)
    shutil.rmtree(tmp, ignore_errors=True)
    init_db()
    flash(_("Backup restored."))
    return redirect(url_for("index"))


# ----------------------------------------------------------------- sharing
# A shared pet is a `.petobase` file: the Apple app's JSON backup format with
# one pet and kind "cat-share". Files go both ways between the apps.

SHARE_FORMAT = "cat-o-base-apple"
SHARE_KIND = "cat-share"
SHARE_DEFAULTS = {"photos": "profile", "details": True, "special": True, "food": True, "health": True,
                  "weight": True, "visits": False, "documents": False, "journal": False,
                  "notes": True, "contacts": True}
WEB_TO_APP_KIND = {"medication": "medication", "flea/tick": "fleaTick", "deworming": "deworming",
                   "supplement": "supplement", "other": "other"}
APP_TO_WEB_KIND = {v: k for k, v in WEB_TO_APP_KIND.items()}
DOC_TYPES = {"pdf": "com.adobe.pdf", "jpg": "public.jpeg", "jpeg": "public.jpeg", "png": "public.png",
             "heic": "public.heic", "txt": "public.plain-text", "gif": "com.compuserve.gif"}


def share_options(args):
    opts = dict(SHARE_DEFAULTS)
    if "photos" in args and args["photos"] in ("none", "profile", "all"):
        opts["photos"] = args["photos"]
    for key, default in SHARE_DEFAULTS.items():
        if key != "photos" and key in args:
            opts[key] = args.get(key) in ("1", "on", "true")
    return opts


def _iso_day(value):
    """'2026-11-22' -> noon UTC, which shows as the same day in any time zone."""
    d = pdate(value)
    return f"{d.isoformat()}T12:00:00Z" if d else None


def _iso_ts(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(str(value)[:19]).strftime("%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return _iso_day(value)


def _parse_iso(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _day_from_iso(value):
    """The calendar day an Apple-app date means. Days the web app wrote are noon UTC;
    days the Apple app wrote are local midnight, so round to the nearest midnight."""
    moment = _parse_iso(value)
    if not moment:
        return None
    moment = moment.astimezone(dt.timezone.utc)
    if (moment.hour, moment.minute, moment.second) == (12, 0, 0):
        return moment.date().isoformat()
    return (moment + dt.timedelta(hours=12)).date().isoformat()


def _media_b64(name):
    import base64
    path = os.path.join(MEDIA, os.path.basename(name or ""))
    if not name or not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def pet_contacts_for_share(c):
    if c["is_guest"]:
        return guest_contacts(c)
    return [{"role": k["role"] or "", "name": k["name"], "phone": k["phone"] or "",
             "address": k["address"] or "", "notes": k["notes"] or ""}
            for k in q("SELECT * FROM contacts ORDER BY role, name")]


def build_share(c, opts, sender):
    cid = c["id"]
    if not c["share_id"]:
        x("UPDATE cats SET share_id=? WHERE id=?", (str(uuid.uuid4()).upper(), cid))
        c = get_cat(cid)
    s = lambda v: v or ""
    pet = {
        "name": c["name"], "species": species_of(c),
        "sex": c["sex"] if c["sex"] in ("female", "male") else "unknown",
        "neutered": bool(c["neutered"]),
        "breed": s(c["breed"]) if opts["details"] else "",
        "markings": s(c["markings"]) if opts["details"] else "",
        "microchip": s(c["microchip"]) if opts["details"] else "",
        "birthdayApprox": bool(c["birthday_approx"]),
        "specialNeeds": s(c["special_needs"]) if opts["special"] else "",
        "allergies": s(c["allergies"]) if opts["special"] else "",
        "foodBrand": s(c["food_brand"]) if opts["food"] else "",
        "foodPortion": s(c["food_portion"]) if opts["food"] else "",
        "foodSchedule": s(c["food_schedule"]) if opts["food"] else "",
        "foodNotes": s(c["food_notes"]) if opts["food"] else "",
        "notes": s(c["notes"]) if opts["notes"] else "",
        "archived": False,
        "createdAt": _iso_ts(c["created_at"]) or dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "shareID": c["share_id"],
        "photos": [], "vaccinations": [], "treatments": [], "weights": [], "visits": [],
        "documents": [], "journal": [],
    }
    if c["birthday"]:
        pet["birthday"] = _iso_day(c["birthday"])
    if opts["details"] and c["adoption_date"]:
        pet["adoptionDate"] = _iso_day(c["adoption_date"])

    photos = q("SELECT * FROM photos WHERE cat_id=? ORDER BY id", (cid,))
    if opts["photos"] == "profile":
        profile = [p for p in photos if p["id"] == c["profile_photo_id"]] or photos[-1:]
        photos = profile
    elif opts["photos"] == "none":
        photos = []
    for p in photos:
        data = _media_b64(p["filename"])
        if not data:
            continue
        photo_uuid = str(uuid.uuid4()).upper()
        entry = {"uuid": photo_uuid, "image": data, "caption": s(p["caption"]),
                 "addedAt": _iso_ts(p["created_at"]) or _iso_day(today().isoformat())}
        if p["taken_on"]:
            entry["takenOn"] = _iso_day(p["taken_on"])
        pet["photos"].append(entry)
        if p["id"] == c["profile_photo_id"] or len(photos) == 1:
            pet["profilePhotoID"] = photo_uuid

    if opts["health"]:
        for v in q("SELECT * FROM vaccinations WHERE cat_id=?", (cid,)):
            entry = {"name": v["name"], "vet": s(v["vet"]), "notes": s(v["notes"])}
            if v["date_given"]: entry["dateGiven"] = _iso_day(v["date_given"])
            if v["next_due"]: entry["nextDue"] = _iso_day(v["next_due"])
            pet["vaccinations"].append(entry)
        for t in q("SELECT * FROM treatments WHERE cat_id=?", (cid,)):
            entry = {"kind": WEB_TO_APP_KIND.get(t["kind"] or "other", "other"), "name": t["name"],
                     "dose": s(t["dose"]), "schedule": s(t["schedule"]), "active": bool(t["active"]),
                     "notes": s(t["notes"])}
            if t["interval_days"]: entry["intervalDays"] = int(t["interval_days"])
            for web_key, app_key in (("last_given", "lastGiven"), ("next_due", "nextDue"), ("end_date", "endDate")):
                if t[web_key]: entry[app_key] = _iso_day(t[web_key])
            pet["treatments"].append(entry)
    if opts["weight"]:
        pet["weights"] = [{"date": _iso_day(w["date"]), "kg": w["kg"]}
                          for w in q("SELECT * FROM weights WHERE cat_id=?", (cid,)) if pdate(w["date"])]
    if opts["visits"]:
        pet["visits"] = [{"date": _iso_day(v["date"]) or _iso_day(today().isoformat()), "clinic": s(v["clinic"]),
                          "reason": s(v["reason"]), "outcome": s(v["outcome"]), "cost": s(v["cost"]),
                          "notes": s(v["notes"])} for v in q("SELECT * FROM visits WHERE cat_id=?", (cid,))]
    if opts["documents"]:
        for d in q("SELECT * FROM documents WHERE cat_id=?", (cid,)):
            data = _media_b64(d["filename"])
            if not data:
                continue
            name = d["original_name"] or d["filename"]
            ext = os.path.splitext(name)[1].lstrip(".").lower()
            pet["documents"].append({"title": d["title"] or name, "filename": name,
                                     "typeIdentifier": DOC_TYPES.get(ext, "public.data"), "data": data,
                                     "addedAt": _iso_ts(d["created_at"]) or _iso_day(today().isoformat())})
    if opts["journal"]:
        pet["journal"] = [{"date": _iso_day(l["date"]) or _iso_day(today().isoformat()), "kind": l["kind"] or "note",
                           "text": l["text"]} for l in q("SELECT * FROM logs WHERE cat_id=?", (cid,))]

    file = {"format": SHARE_FORMAT, "version": 1, "kind": SHARE_KIND,
            "exported": dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "cats": [pet], "contacts": pet_contacts_for_share(c) if opts["contacts"] else []}
    if sender:
        file["sharedBy"] = sender
    return file


def share_summary(c, opts, sender):
    """Readable message for people without the app, in the viewer's language."""
    label, emoji, _hint, _vaccines = SPECIES[species_of(c)]
    lines = [f"{emoji} {c['name']}"]
    facts = [_(label).lower()]
    age = age_filter(c["birthday"])
    if age != "—":
        facts.append(_("about {age}", age=age) if c["birthday_approx"] else age)
    if c["sex"] in ("female", "male"):
        facts.append(sex_label(c["sex"]) + (", " + _("neutered") if c["neutered"] else ""))
    if opts["details"]:
        facts += [v for v in (c["breed"], c["markings"]) if v]
    lines.append(" · ".join(facts))
    if opts["details"] and c["microchip"]:
        lines.append(_("Microchip: {chip}", chip=c["microchip"]))
    if opts["special"]:
        if c["special_needs"]:
            lines.append("\n⚠️ " + _("Special needs: {text}", text=c["special_needs"]))
        if c["allergies"]:
            lines.append(_("Allergies: {text}", text=c["allergies"]))
    if opts["food"]:
        food = [v for v in (c["food_brand"], c["food_portion"], c["food_schedule"]) if v]
        if food or c["food_notes"]:
            lines.append("\n🍽 " + _("Food: {text}", text=", ".join(food)))
            if c["food_notes"]:
                lines.append(c["food_notes"])
    if opts["health"]:
        meds = q("SELECT * FROM treatments WHERE cat_id=? AND active=1 ORDER BY name", (c["id"],))
        if meds:
            lines.append("\n💊 " + _("Medication & treatments:"))
            for t in meds:
                extra = ", ".join(v for v in (t["dose"], t["schedule"],
                                              _n("every {n} days", t["interval_days"]) if t["interval_days"] else None) if v)
                line = f"• {t['name']}" + (f" ({extra})" if extra else "")
                if t["next_due"]:
                    line += ", " + _("next {date}", date=date_filter(t["next_due"]))
                lines.append(line)
        vaccines = [d for d in due_items(c["id"]) if d["kind"] == "vaccine"]
        if vaccines:
            lines.append("\n💉 " + _("Vaccinations:"))
            lines += ["• " + _("{name}, next due {date}", name=d["item"], date=date_filter(d["due"])) for d in vaccines]
    if opts["weight"]:
        w = q("SELECT * FROM weights WHERE cat_id=? ORDER BY date DESC, id DESC LIMIT 1", (c["id"],), one=True)
        if w:
            lines.append("\n⚖️ " + _("Weight: {kg} kg ({date})", kg=f"{w['kg']:g}", date=date_filter(w["date"])))
    if opts["notes"] and c["notes"]:
        lines.append(f"\n📝 {c['notes']}")
    if opts["contacts"]:
        contacts = pet_contacts_for_share(c)
        if contacts:
            lines.append("\n📞 " + _("Contacts:"))
            for k in contacts:
                role = f"{k['role']}: " if k.get("role") else ""
                phone = f", {k['phone']}" if k.get("phone") else ""
                lines.append(f"{role}{k['name']}{phone}")
    lines.append("\n— " + (_("Shared from Pet-o-Base by {name}", name=sender) if sender else _("Shared from Pet-o-Base")))
    return "\n".join(lines)


@app.route("/cat/<int:cid>/summary.txt")
def share_summary_text(cid):
    c = get_cat(cid)
    sender = (request.args.get("sender") or "").strip()
    return Response(share_summary(c, share_options(request.args), sender), mimetype="text/plain")


@app.route("/cat/<int:cid>/share.petobase")
def share_file(cid):
    c = get_cat(cid)
    sender = (request.args.get("sender") or "").strip()
    body = json.dumps(build_share(c, share_options(request.args), sender), ensure_ascii=False)
    safe = "".join(ch for ch in c["name"] if ch not in '/\\:*?"<>|') or "Pet"
    resp = Response(body, mimetype="application/x-catobase")
    from urllib.parse import quote
    resp.headers["Content-Disposition"] = f"attachment; filename*=UTF-8''{quote(safe)}.petobase"
    if sender:
        resp.set_cookie("sender", sender, max_age=3600 * 24 * 365)
    return resp


def save_image_bytes(data):
    class _Upload:
        def __init__(self, raw):
            self.stream = io.BytesIO(raw)
    return save_image(_Upload(data))


def import_share(raw, replace):
    """Adds a shared pet (from either app) as a guest. Returns the new pet's id."""
    import base64
    obj = json.loads(raw)
    if obj.get("format") != SHARE_FORMAT or obj.get("kind") != SHARE_KIND or not obj.get("cats"):
        raise ValueError(_("this isn't a shared pet file"))
    pet = obj["cats"][0]
    share_id = pet.get("shareID")
    if share_id and replace:
        for old in q("SELECT id FROM cats WHERE is_guest=1 AND share_id=?", (share_id,)):
            _delete_pet(old["id"])

    species = pet.get("species") or "cat"
    cid = x("""INSERT INTO cats(name, species, sex, neutered, breed, markings, birthday, birthday_approx,
               adoption_date, microchip, special_needs, allergies, food_brand, food_portion, food_schedule,
               food_notes, notes, is_guest, guest_from, guest_since, guest_contacts, share_id)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?,?,?)""",
            (pet.get("name") or "Unnamed pet", species if species in SPECIES else "other",
             pet.get("sex") if pet.get("sex") in ("female", "male") else None, 1 if pet.get("neutered") else 0,
             pet.get("breed") or None, pet.get("markings") or None, _day_from_iso(pet.get("birthday")),
             1 if pet.get("birthdayApprox") else 0, _day_from_iso(pet.get("adoptionDate")),
             pet.get("microchip") or None, pet.get("specialNeeds") or None, pet.get("allergies") or None,
             pet.get("foodBrand") or None, pet.get("foodPortion") or None, pet.get("foodSchedule") or None,
             pet.get("foodNotes") or None, pet.get("notes") or None, obj.get("sharedBy") or None,
             today().isoformat(), json.dumps(obj.get("contacts") or [], ensure_ascii=False), share_id))

    for photo in pet.get("photos", []):
        try:
            name = save_image_bytes(base64.b64decode(photo.get("image", "")))
        except (ValueError, TypeError):
            name = None
        if not name:
            continue
        pid = x("INSERT INTO photos(cat_id, filename, caption, taken_on) VALUES(?,?,?,?)",
                (cid, name, photo.get("caption") or None, _day_from_iso(photo.get("takenOn"))))
        if photo.get("uuid") and photo.get("uuid") == pet.get("profilePhotoID"):
            x("UPDATE cats SET profile_photo_id=? WHERE id=?", (pid, cid))
    for v in pet.get("vaccinations", []):
        x("INSERT INTO vaccinations(cat_id, name, date_given, next_due, vet, notes) VALUES(?,?,?,?,?,?)",
          (cid, v.get("name") or "Vaccine", _day_from_iso(v.get("dateGiven")), _day_from_iso(v.get("nextDue")),
           v.get("vet") or None, v.get("notes") or None))
    for t in pet.get("treatments", []):
        x("""INSERT INTO treatments(cat_id, kind, name, dose, schedule, interval_days, last_given, next_due,
             end_date, active, notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
          (cid, APP_TO_WEB_KIND.get(t.get("kind"), "other"), t.get("name") or "Treatment", t.get("dose") or None,
           t.get("schedule") or None, t.get("intervalDays"), _day_from_iso(t.get("lastGiven")),
           _day_from_iso(t.get("nextDue")), _day_from_iso(t.get("endDate")), 1 if t.get("active", True) else 0,
           t.get("notes") or None))
    for w in pet.get("weights", []):
        day = _day_from_iso(w.get("date"))
        if day and w.get("kg"):
            x("INSERT INTO weights(cat_id, date, kg) VALUES(?,?,?)", (cid, day, float(w["kg"])))
    for v in pet.get("visits", []):
        x("INSERT INTO visits(cat_id, date, clinic, reason, outcome, cost, notes) VALUES(?,?,?,?,?,?,?)",
          (cid, _day_from_iso(v.get("date")) or today().isoformat(), v.get("clinic") or None,
           v.get("reason") or None, v.get("outcome") or None, v.get("cost") or None, v.get("notes") or None))
    for d in pet.get("documents", []):
        try:
            data = base64.b64decode(d.get("data", ""))
        except (ValueError, TypeError):
            continue
        original = d.get("filename") or "document"
        ext = os.path.splitext(secure_filename(original))[1].lower()[:10]
        stored = "d_" + uuid.uuid4().hex + ext
        with open(os.path.join(MEDIA, stored), "wb") as f:
            f.write(data)
        x("INSERT INTO documents(cat_id, title, filename, original_name) VALUES(?,?,?,?)",
          (cid, d.get("title") or original, stored, original))
    for j in pet.get("journal", []):
        x("INSERT INTO logs(cat_id, date, kind, text) VALUES(?,?,?,?)",
          (cid, _day_from_iso(j.get("date")) or today().isoformat(), j.get("kind") or "note", j.get("text") or ""))
    return cid


def _delete_pet(cid):
    for p in q("SELECT filename FROM photos WHERE cat_id=?", (cid,)):
        rm_media(p["filename"])
    for d in q("SELECT filename FROM documents WHERE cat_id=?", (cid,)):
        rm_media(d["filename"])
    x("DELETE FROM cats WHERE id=?", (cid,))


@app.post("/import-pet")
def import_pet():
    f = request.files.get("file")
    if not f or not f.filename:
        flash(_("Choose a .petobase file first."))
        return redirect(request.referrer or url_for("index"))
    try:
        cid = import_share(f.read(), replace=request.form.get("replace") == "1")
    except (ValueError, KeyError, TypeError) as e:
        flash(_("Couldn't import: {error}", error=e))
        return redirect(request.referrer or url_for("index"))
    flash(_("Added to Guest Pets."))
    return redirect(url_for("cat", cid=cid))


@app.errorhandler(413)
def too_large(_e):
    flash(_("That upload is too big."))
    return redirect(request.referrer or url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("CATOBASE_PORT", 8000)), debug=True)
