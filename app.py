"""Pet-o-Base — a small self-hosted records app for cats.

Flask + SQLite. All data (database + uploaded media) lives in CATOBASE_DATA
(default ./data). Run with gunicorn: gunicorn -w 2 -b 0.0.0.0:8000 app:app
"""
import calendar
import datetime as dt
import json
import os
import secrets
import shutil
import sqlite3
import tempfile
import uuid
import zipfile

from flask import (Flask, abort, after_this_request, flash, g, redirect,
                   render_template, request, send_file, send_from_directory,
                   url_for, Response)
from markupsafe import Markup, escape
from PIL import Image, ImageOps
from werkzeug.utils import secure_filename

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

SCHEMA = """
CREATE TABLE IF NOT EXISTS cats(
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, sex TEXT, neutered INTEGER DEFAULT 0,
  breed TEXT, markings TEXT, birthday TEXT, birthday_approx INTEGER DEFAULT 0,
  adoption_date TEXT, microchip TEXT, special_needs TEXT, allergies TEXT,
  food_brand TEXT, food_portion TEXT, food_schedule TEXT, food_notes TEXT,
  notes TEXT, profile_photo_id INTEGER, archived INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP);
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


def init_db():
    con = sqlite3.connect(DB_PATH)
    con.executescript(SCHEMA)
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
        return f"{m} mo"
    return f"{y} y {m} mo" if m else f"{y} y"


@app.template_filter("d")
def date_filter(s):
    d = pdate(s)
    return d.strftime("%d %b %Y") if d else (s or "—")


def due_status(s):
    d = pdate(s)
    if not d:
        return ("none", "")
    n = (d - today()).days
    if n < 0:
        return ("overdue", f"{-n} d overdue")
    if n == 0:
        return ("soon", "today")
    if n <= 14:
        return ("soon", f"in {n} d")
    return ("ok", f"in {n} d")


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
                     f'<title>{d.strftime("%d %b %Y")}: {k:g} kg</title></circle>')
    parts.append(f'<text x="{PL}" y="{H-8}" class="lbl">{d0.strftime("%b %Y")}</text>'
                 f'<text x="{W-PR}" y="{H-8}" class="lbl" text-anchor="end">{d1.strftime("%b %Y")}</text>')
    parts.append("</svg>")
    return Markup("".join(parts))


# -------------------------------------------------------------------- cats
CAT_FIELDS = ["name", "sex", "breed", "markings", "birthday", "adoption_date", "microchip",
              "special_needs", "allergies", "food_brand", "food_portion", "food_schedule",
              "food_notes", "notes"]
CAT_BOOLS = ["neutered", "birthday_approx", "archived"]


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
    return render_template("index.html", cats=cats, due=upcoming, alerts=alerts,
                           arch=arch, n_arch=n_arch)


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
            flash("A cat needs a name.")
            return render_template("cat_form.html", cat=request.form, cid=cid)
        for b in CAT_BOOLS:
            v[b] = 1 if request.form.get(b) else 0
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
        flash("Type the cat's name exactly to delete the whole record.")
        return redirect(url_for("cat_form", cid=cid))
    for p in q("SELECT filename FROM photos WHERE cat_id=?", (cid,)):
        rm_media(p["filename"])
    for d in q("SELECT filename FROM documents WHERE cat_id=?", (cid,)):
        rm_media(d["filename"])
    x("DELETE FROM cats WHERE id=?", (cid,))
    flash(f"{c['name']} deleted.")
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
        flash(f"{req.replace('_', ' ').capitalize()} is required.")
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
            flash("Weight must be a number.")
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
            flash(f"Couldn't read {f.filename} as an image.")
            continue
        pid = x("INSERT INTO photos(cat_id, filename, caption, taken_on) VALUES(?,?,?,?)",
                (cid, name, caption, taken))
        if not c["profile_photo_id"] and n == 0:
            x("UPDATE cats SET profile_photo_id=? WHERE id=?", (pid, cid))
        n += 1
    if n:
        flash(f"{n} photo{'s' if n > 1 else ''} added.")
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
        flash("Choose a file to upload.")
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
            flash("Name is required.")
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
    return render_template("sitter.html", cats=cats, meds=meds,
                           contacts=q("SELECT * FROM contacts ORDER BY role, name"),
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
            event(f"bday-{c['id']}@cat-o-base", b, f"{c['name']}'s birthday", rrule="FREQ=YEARLY")
        a = pdate(c["adoption_date"])
        if a:
            event(f"gotcha-{c['id']}@cat-o-base", a, f"{c['name']} — gotcha day", rrule="FREQ=YEARLY")
    L.append("END:VCALENDAR")
    return Response("\r\n".join(L) + "\r\n", mimetype="text/calendar",
                    headers={"Content-Disposition": "inline; filename=cats.ics"})


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
                    headers={"Content-Disposition": f"attachment; filename=cat-o-base-{today()}.json"})


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
    resp = send_file(path, as_attachment=True, download_name=f"cat-o-base-backup-{today()}.zip")

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
        flash("Type RESTORE to confirm — this replaces everything.")
        return redirect(url_for("backup_page"))
    f = request.files.get("file")
    if not f or not f.filename:
        flash("Choose a backup .zip first.")
        return redirect(url_for("backup_page"))
    tmp = tempfile.mkdtemp(dir=DATA, prefix=".restore-")
    try:
        with zipfile.ZipFile(f.stream) as z:
            names = z.namelist()
            db_name = next((n for n in (DB_NAME, *LEGACY_DB_NAMES) if n in names), None)
            if not db_name:
                raise ValueError(f"not a Pet-o-Base backup (no {DB_NAME} inside)")
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
        flash(f"Restore failed: {e}")
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
    flash("Backup restored.")
    return redirect(url_for("index"))


@app.errorhandler(413)
def too_large(_e):
    flash("That upload is too big.")
    return redirect(request.referrer or url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("CATOBASE_PORT", 8000)), debug=True)
