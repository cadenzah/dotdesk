#!/bin/sh
# Regenerates Resources/AppIcon.icns from the built-in pixel art.
set -e
cd "$(dirname "$0")/.."
swift build
TMP=$(mktemp -d)
.build/debug/DotDesk --render-icon "$TMP/icon-1024.png"
mkdir -p "$TMP/AppIcon.iconset" Resources
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon-1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
