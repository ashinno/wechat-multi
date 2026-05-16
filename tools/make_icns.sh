#!/bin/bash
# Generate Resources/AppIcon.icns from the programmatically-rendered master PNG.
# Run from the project root.
set -euo pipefail

MASTER="/tmp/wcm-icon-master.png"
ICONSET="/tmp/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

# Render the master PNG with our Swift drawing script (yields 2048×2048 — high
# enough that downscales to every required size look crisp).
swift tools/make_icon.swift "$MASTER" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Each .iconset filename baked into iconutil's expected naming convention.
sips -z 16   16   "$MASTER" --out "$ICONSET/icon_16x16.png"        >/dev/null
sips -z 32   32   "$MASTER" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null
sips -z 32   32   "$MASTER" --out "$ICONSET/icon_32x32.png"        >/dev/null
sips -z 64   64   "$MASTER" --out "$ICONSET/icon_32x32@2x.png"     >/dev/null
sips -z 128  128  "$MASTER" --out "$ICONSET/icon_128x128.png"      >/dev/null
sips -z 256  256  "$MASTER" --out "$ICONSET/icon_128x128@2x.png"   >/dev/null
sips -z 256  256  "$MASTER" --out "$ICONSET/icon_256x256.png"      >/dev/null
sips -z 512  512  "$MASTER" --out "$ICONSET/icon_256x256@2x.png"   >/dev/null
sips -z 512  512  "$MASTER" --out "$ICONSET/icon_512x512.png"      >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png"   >/dev/null

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT ($(stat -f%z "$OUT") bytes)"
