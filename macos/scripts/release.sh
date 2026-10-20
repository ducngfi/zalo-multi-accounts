#!/bin/bash
# Builds the app and the command and packs them for a GitHub release into build/release:
#   Zalo-Switcher-<version>-macOS.zip    the app
#   zalo-profiles-<version>-macOS.zip    the command
#   SHA256SUMS.txt
# Publish with: gh release create v<version> build/release/* --notes-file <notes>
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

APP="build/Zalo Switcher.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"
OUT="build/release"
rm -rf "$OUT"
mkdir -p "$OUT"

# ditto keeps the bundle intact, as Finder's Compress does. The signatures are inside the files,
# so the extended attributes (only this Mac's provenance tags) are left out.
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$OUT/Zalo-Switcher-$VERSION-macOS.zip"
ditto -c -k --norsrc --noextattr build/zalo-profiles "$OUT/zalo-profiles-$VERSION-macOS.zip"
(cd "$OUT" && shasum -a 256 *.zip > SHA256SUMS.txt)

echo "Packed version $VERSION into $OUT:"
ls -lh "$OUT"
