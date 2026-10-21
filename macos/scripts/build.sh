#!/bin/bash
# Builds "Zalo Switcher.app" and the zalo-profiles command into ./build,
# as universal binaries that run on both Apple silicon and Intel Macs.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.1.0"   # shown in Finder; raise it, and BUILD, for every release
BUILD="2"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product ZaloSwitcher
swift build -c release "${ARCHS[@]}" --product zalo-profiles
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/Zalo Switcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/vi.lproj"
cp "$BIN/ZaloSwitcher" "$APP/Contents/MacOS/ZaloSwitcher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/zalo-profiles" build/zalo-profiles
# The app is in Vietnamese only; this makes system dialogs (folder pickers, About) Vietnamese too.
printf '"CFBundleDisplayName" = "Zalo Switcher";\n' > "$APP/Contents/Resources/vi.lproj/InfoPlist.strings"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Zalo Switcher</string>
    <key>CFBundleDisplayName</key>
    <string>Zalo Switcher</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>vi</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>vi</string>
    </array>
    <key>CFBundleIdentifier</key>
    <string>local.zalo-switcher</string>
    <key>CFBundleExecutable</key>
    <string>ZaloSwitcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature, so macOS runs it on this Mac. It isn't notarized, so a downloaded copy gets
# a security warning the first time it opens (the README explains how to open it).
codesign --force --sign - "$APP"
codesign --force --sign - build/zalo-profiles

echo "Built: $APP"
echo "Built: build/zalo-profiles"
