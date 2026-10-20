#!/bin/bash
# Renders AppIcon.svg into the icon files each app uses. Run it again after editing the SVG.
#   assets/icon/AppIcon-1024.png    preview, used in the README
#   assets/icon/AppIcon.ico         Windows, 16–256 px, drawn edge to edge without the macOS shadow
#   macos/Resources/AppIcon.icns    macOS, 16–1024 px
# Needs rsvg-convert (brew install librsvg) and Python with Pillow (pip install pillow);
# iconutil comes with macOS.
set -euo pipefail
cd "$(dirname "$0")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rsvg-convert -w 1024 -h 1024 AppIcon.svg -o AppIcon-1024.png

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    rsvg-convert -w $size -h $size AppIcon.svg -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) AppIcon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o ../../macos/Resources/AppIcon.icns

# Windows draws no shadow and leaves little margin, so crop to the body and drop the shadow.
sed -e 's/ filter="url(#iconShadow)"//' -e 's/viewBox="0 0 1024 1024"/viewBox="84 84 856 856"/' \
    AppIcon.svg > "$TMP/windows.svg"
SIZES=(256 96 64 48 40 32 24 20 16)
for size in "${SIZES[@]}"; do
    rsvg-convert -w $size -h $size "$TMP/windows.svg" -o "$TMP/win-$size.png"
done
# Pillow stores each size as PNG (ImageMagick would store the 256 px one uncompressed).
python3 - "$TMP" "${SIZES[@]}" <<'PY'
import sys
from PIL import Image
folder, sizes = sys.argv[1], [int(s) for s in sys.argv[2:]]
images = [Image.open(f"{folder}/win-{s}.png") for s in sizes]
images[0].save("AppIcon.ico", format="ICO", sizes=[(s, s) for s in sizes], append_images=images[1:])
PY

echo "Rendered AppIcon-1024.png, AppIcon.ico and macos/Resources/AppIcon.icns"
