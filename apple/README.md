# Pet-o-Base for iPhone, iPad and Mac

A native SwiftUI app. One app target runs on iOS, iPadOS and macOS 27.
Data is stored on the device with SwiftData; the model is ready for iCloud
sync later.

**Status:** phase 7 of 8, plus cat sharing. Share a cat (choosing what to
include) through Messages, Telegram and the rest; received cats appear under
Guest Cats. Camera and document scanner. Sitter sheet PDF, backup and import (including
from the web app), due-date reminders, cats (sortable by name or age), round profile
photos with a crop editor and automatic cat detection, photo galleries,
documents, contacts, vaccinations, medications and treatments, the Due tab,
and weight tracking with a chart. See [the roadmap](#roadmap).

## First-time setup

You need a Mac with Xcode 27 and [Homebrew](https://brew.sh).

### 1. Get the code and install XcodeGen

The Xcode project file isn't stored in git. It's generated from
`project.yml` by XcodeGen, which avoids merge conflicts in the project file.

```bash
git clone https://github.com/dhomak/cat-o-base.git
cd cat-o-base/apple
brew install xcodegen
```

### 2. Tell it your signing team

Find your team ID. This command prints it from the development certificate
Xcode already created for you:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | grep -o 'OU=[A-Z0-9]*' | cut -d= -f2
```

It's a 10-character code like `AB12CD34EF`. Save it in a file that git
ignores:

```bash
echo 'DEVELOPMENT_TEAM = AB12CD34EF' > Config/Local.xcconfig
```

Use your own code, not the example. If the command prints nothing, build any
project to your phone once (like the Hello World test) so Xcode creates the
certificate, then try again.

### 3. Generate and open the project

```bash
xcodegen
open CatOBase.xcodeproj
```

### 4. Run it

Pick your iPhone (or **My Mac**, or an iPad simulator) in the device menu at
the top of Xcode and press **⌘R**.

## After pulling new code

```bash
cd cat-o-base/apple
git pull
xcodegen          # picks up new or renamed files
```

Then press ⌘R in Xcode. If Xcode was open, it reloads the project
automatically.

## Sharing a cat

On a cat's page, tap **Share**. Choose what to include, then send it with the
standard share sheet. The recipient gets a readable summary plus a
`Name.catobase` file; opening that file in Pet-o-Base (from Messages,
Telegram, Mail, Files or Finder) adds the cat under **Guest Cats**. Sharing
the same cat again lets them update their copy. Shares are snapshots: there's
no live sync, which would need iCloud.

## Keyboard shortcuts (Mac, and iPad with a keyboard)

| | |
|---|---|
| ⌘N / ⇧⌘N | New cat / new guest cat |
| ⌥⌘N | New window |
| ⌘E | Edit the cat |
| ⌥⌘L | Log weight |
| ⌥⌘V / ⌥⌘M | Add vaccination / medication |
| ⇧⌘S | Share the cat |
| ⌘P | Sitter sheet |
| ⇧⌘O | Open the cat in a new window |
| ← → | Previous / next photo in the viewer |
| ⌘, | Settings (Mac) |

Drag photos or PDFs onto a cat's page to add them. On the Mac, **File → Import
from iPhone** takes a photo or scans a document with your phone.

## App icon

See [ICON.md](ICON.md): make a 1024 × 1024 PNG and run `tools/make-icons.sh`.

## Free Apple account notes

- The app runs for **7 days**, then needs re-installing from Xcode (⌘R).
  Your data is kept.
- If you get "maximum number of apps", delete the old Hello World test app
  from the phone.
- iCloud sync needs the paid Developer Program. The app is built so that
  switching it on later is a small change (see `CatOBaseApp.swift`).

## Project layout

```
project.yml                 XcodeGen project definition (iOS + macOS, version 27)
Config/Base.xcconfig        shared settings; includes your Local.xcconfig
CatOBase/
  CatOBaseApp.swift         app entry, database setup
  Models/Models.swift       SwiftData models (CloudKit-compatible)
  Views/                    screens
  Support/                  image handling, formatting, preview sample data
  Assets.xcassets           app icon, accent colour
```

## Roadmap

1. **Skeleton** ✅: models, cat grid, cat page, add/edit/archive/delete, contacts
2. **Health** ✅: vaccinations, treatments with "✓ given", the Due tab
3. **Weight** ✅: logging in kg or lb, Swift Charts graph, weight-loss warning
4. **Media** ✅: photo gallery, documents with QuickLook, round-avatar crop
   editor with automatic cat detection
5. **Reminders** ✅: local notifications for due dates, app icon badge
6. **Sharing and backup** ✅: sitter sheet PDF, export/import, import from the
   Pet-o-Base web app
7. **iPad and Mac polish** ✅: menus, shortcuts, drag and drop, multiple windows,
   Continuity Camera, search
8. **Later:** iCloud sync, widget, Siri/Shortcuts
