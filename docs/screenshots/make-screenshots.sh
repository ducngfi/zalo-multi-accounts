#!/bin/bash
# Makes the README images from synthetic data only; nothing here reads the real Zalo data.
#   1. Builds the app and lets it draw its own windows from the demo accounts
#      (cua-so-chinh.png, cua-so-chinh-toi.png, sao-luu.png, cai-dat.png).
#   2. Renders the illustrations in src/ with Google Chrome (song-song.png, cach-hoat-dong.png).
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"

../../macos/scripts/build.sh
"../../macos/build/Zalo Switcher.app/Contents/MacOS/ZaloSwitcher" --render-screenshots "$HERE"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() {   # render <page> <width> <height>
    local profile
    profile="$(mktemp -d)"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$profile" \
        --force-device-scale-factor=2 --window-size="$2,$3" --virtual-time-budget=6000 \
        --screenshot="$HERE/$1.png" "file://$HERE/src/$1.html" 2>/dev/null
    rm -rf "$profile"
    echo "Wrote $HERE/$1.png"
}
render song-song 1600 1040
render cach-hoat-dong 1400 900
