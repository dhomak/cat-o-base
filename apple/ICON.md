# Replacing the app icon

The icon lives in `CatOBase/Assets.xcassets/AppIcon.appiconset/`: one
1024 × 1024 image for iPhone and iPad, and ten sizes for the Mac. You only make
one or two images; a script does the resizing.

## 1. Make your artwork

**iPhone and iPad:** a square PNG, **1024 × 1024**.

- Fill the whole square edge to edge. No rounded corners: iOS cuts the
  rounded shape itself, so anything in the corners is clipped.
- No transparency. Transparent areas turn black on iOS.
- Keep the important part (the cat's face, say) within the middle ~80%.

**Mac (optional but recommended):** a separate square PNG, **1024 × 1024**.

- macOS does *not* round icons for you. Draw the rounded-square shape
  yourself, on a transparent background, with a margin around it: about
  **824 × 824** for the shape, centred, leaving ~100 px on each side.
- If you skip this, the Mac uses the iPhone image, which shows as a plain
  square in the Dock.

Any editor that exports PNG works: Figma, Affinity, Pixelmator, Photoshop,
Sketch.

The current artwork is kept in `Artwork/`: `icon.png` (iPhone/iPad) and
`icon-mac.png` (rounded, with margin and shadow). Start from those to tweak it.

## 2. Install it

From the `apple` folder on your Mac:

```bash
tools/make-icons.sh ~/Desktop/icon.png
# or with separate Mac artwork:
tools/make-icons.sh ~/Desktop/icon.png ~/Desktop/icon-mac.png
```

The script checks the images are square and big enough, then writes every
size into the asset catalog, replacing the current ones. It also remakes
`LaunchIcon`, the faint rounded icon on the launch screen that zooms away when
the app starts.

## 3. See it

In Xcode: **Product → Clean Build Folder** (⇧⌘K), then **⌘R**.

iOS and macOS cache icons. If the old one lingers:

- **iPhone:** delete the app and run it again from Xcode. Export a backup
  first if you have data in it (Settings → Backup).
- **Mac:** quit the app, then run `killall Dock` in Terminal.

## Doing it by hand instead

Open `CatOBase/Assets.xcassets` in Xcode, select **AppIcon**, and drag images
onto the slots: the 1024 slot for iOS, and each Mac slot at its labelled size
(16pt @1x = 16 px, @2x = 32 px, up to 512pt @2x = 1024 px).

## Keeping it in git

The icon files are part of the repo, so commit them after replacing:

```bash
git add CatOBase/Assets.xcassets/AppIcon.appiconset
git commit -m "New app icon"
git push
```
