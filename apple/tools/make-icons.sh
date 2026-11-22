#!/bin/bash
# Makes every app icon size from your own artwork, using macOS's built-in `sips`.
#
#   tools/make-icons.sh my-icon.png                 same image for iPhone/iPad and Mac
#   tools/make-icons.sh my-icon.png my-mac-icon.png separate Mac artwork (recommended)
#
# Images must be square PNGs, at least 1024 × 1024. See ICON.md.
set -euo pipefail

IOS_SRC="${1:-}"
MAC_SRC="${2:-${1:-}}"
if [[ -z "$IOS_SRC" ]]; then
  echo "Usage: tools/make-icons.sh icon.png [mac-icon.png]"
  exit 1
fi

DEST="$(cd "$(dirname "$0")/.." && pwd)/CatOBase/Assets.xcassets/AppIcon.appiconset"

check() {
  local file="$1"
  [[ -f "$file" ]] || { echo "Not found: $file"; exit 1; }
  local w h
  w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')
  if [[ "$w" != "$h" ]]; then echo "$file is ${w}×${h}; it must be square."; exit 1; fi
  if (( w < 1024 )); then echo "$file is ${w}×${h}; it must be at least 1024×1024."; exit 1; fi
}

check "$IOS_SRC"
check "$MAC_SRC"

echo "iPhone/iPad icon from $IOS_SRC"
sips -s format png -z 1024 1024 "$IOS_SRC" --out "$DEST/icon-ios-1024.png" >/dev/null

echo "Mac icons from $MAC_SRC"
for pt in 16 32 128 256 512; do
  for scale in 1 2; do
    px=$((pt * scale))
    sips -s format png -z "$px" "$px" "$MAC_SRC" --out "$DEST/icon-mac-${pt}@${scale}x.png" >/dev/null
  done
done

echo "Launch animation icon from $IOS_SRC"
# Faint and rounded, so it needs more than sips: a small Swift script does it.
swift "$(dirname "$0")/make-launch-icon.swift" "$DEST/icon-ios-1024.png" "$(dirname "$DEST")/LaunchIcon.imageset"

echo "Done. In Xcode: Product → Clean Build Folder (⇧⌘K), then run (⌘R)."
