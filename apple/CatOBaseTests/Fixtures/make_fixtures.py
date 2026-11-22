"""Builds the test fixtures from the real web app, so the Swift tests check what the
web app actually produces.

    cd apple/CatOBaseTests/Fixtures && python3 make_fixtures.py

Needs the web app's requirements (Flask, Pillow). Writes:
  web-backup.zip      Full backup: SQLite database + media
  web-export.json     Data-only export
  web-share.petobase  A pet shared from the web app (Murka, everything included)
  stored.zip, deflated.zip, comment.zip, truncated.zip   small archives for the zip reader
  tiny.jpg            a real JPEG for photo imports
"""
import io
import os
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
os.environ["CATOBASE_DATA"] = tempfile.mkdtemp()
sys.path.insert(0, REPO)

import app as web  # noqa: E402
from PIL import Image  # noqa: E402


def jpeg(color, size=(64, 48)):
    out = io.BytesIO()
    Image.new("RGB", size, color).save(out, "JPEG", quality=80)
    return out.getvalue()


def write(name, data):
    with open(os.path.join(HERE, name), "wb") as f:
        f.write(data)
    print(f"{name}: {len(data)} bytes")


client = web.app.test_client()
client.set_cookie("lang", "en")

# Murka: a cat with everything.
client.post("/cat/new", content_type="multipart/form-data", data={
    "name": "Murka", "species": "cat", "sex": "female", "neutered": "on",
    "breed": "Domestic shorthair", "markings": "Tabby, white socks", "microchip": "972000123456789",
    "birthday": "2015-03-10", "adoption_date": "2016-05-01",
    "special_needs": "Kidney diet", "allergies": "Chicken",
    "food_brand": "Royal Canin Renal", "food_portion": "½ pouch", "food_schedule": "08:00 and 20:00",
    "notes": "Hides under the bed", "photo": (io.BytesIO(jpeg("orange")), "murka.jpg"),
})
client.post("/cat/1/photos", content_type="multipart/form-data",
            data={"photos": [(io.BytesIO(jpeg("gray")), "second.jpg")]})
client.post("/cat/1/add/vaccine", data={"name": "Rabies", "date_given": "2025-11-10", "next_due": "2026-11-10"})
client.post("/cat/1/add/treatment", data={"kind": "flea/tick", "name": "Bravecto", "dose": "1 pipette",
                                          "interval_days": "90", "last_given": "2026-10-01"})
client.post("/cat/1/add/weight", data={"date": "2026-05-01", "kg": "4.6"})
client.post("/cat/1/add/weight", data={"date": "2026-11-01", "kg": "4.1"})
client.post("/cat/1/add/visit", data={"date": "2026-06-15", "clinic": "Steisneider", "reason": "Check-up",
                                      "cost": "350"})
client.post("/cat/1/add/log", data={"date": "2026-11-20", "kind": "nails", "text": "Trimmed"})
client.post("/cat/1/documents", content_type="multipart/form-data",
            data={"title": "Bloodwork", "file": (io.BytesIO(b"%PDF-1.4\n% test\n"), "bloodwork.pdf")})

# Rex: a dog, no birthday.
client.post("/cat/new", data={"name": "Rex", "species": "dog", "sex": "male"})

# Splinter: a guest rat with the owner's contacts.
client.post("/cat/new", data={"name": "Splinter", "species": "rat", "is_guest": "on", "guest_from": "Anna",
                              "guest_since": "2026-11-15",
                              "gc_role": ["Owner"], "gc_name": ["Anna"], "gc_phone": ["+972541234567"]})

client.post("/contacts", data={"role": "vet", "name": "Steisneider", "phone": "037307333"})

write("web-backup.zip", client.get("/backup.zip").data)
write("web-export.json", client.get("/export.json").data)
write("web-share.petobase", client.get("/cat/1/share.petobase?photos=all&sender=David&visits=1&documents=1&journal=1").data)

# Small archives for the zip reader.
for name, method in (("stored.zip", zipfile.ZIP_STORED), ("deflated.zip", zipfile.ZIP_DEFLATED)):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", method) as z:
        z.writestr("hello.txt", "Hello, Pet-o-Base! " * 20)
        z.writestr("folder/empty.txt", "")
    write(name, buffer.getvalue())
buffer = io.BytesIO()
with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as z:
    z.comment = b"A comment after the central directory"
    z.writestr("hello.txt", "Hello, Pet-o-Base! " * 20)
write("comment.zip", buffer.getvalue())
deflated = open(os.path.join(HERE, "deflated.zip"), "rb").read()
write("truncated.zip", deflated[: len(deflated) // 2])

write("tiny.jpg", jpeg("teal", (40, 30)))
