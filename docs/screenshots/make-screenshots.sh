#!/bin/bash
# Makes the README images from synthetic data only; nothing here reads the real Zalo data.
#   1. Builds the app and lets it draw its own windows from the demo accounts
#      (cua-so-chinh.png, cua-so-chinh-toi.png, sao-luu.png, cai-dat.png).
#   2. Renders the illustrations in src/ with Google Chrome (song-song.png, cach-hoat-dong.png).
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"

../../macos/scripts/build.sh
# One launch per image: only an app's first window is likely to draw as active. macOS can still
# refuse to bring the app forward while you use another app, so try each image a few times.
for shot in cua-so-chinh cua-so-chinh-toi sao-luu cai-dat; do
    for attempt in 1 2 3 4 5; do
        if "../../macos/build/Zalo Switcher.app/Contents/MacOS/ZaloSwitcher" --render-screenshots "$HERE" --only "$shot" \
            2>&1 | tee /dev/stderr | grep -q "may look inactive"; then
            echo "Retrying $shot ($attempt)"
        else
            break
        fi
    done
done

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
render cach-hoat-dong 1400 820
