#!/bin/bash
# Builds "Zalo Switcher.app" (menu-bar app) and the zalo-profiles command into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ZaloSwitcher
swift build -c release --product zalo-profiles
BIN="$(swift build -c release --show-bin-path)"

APP="build/Zalo Switcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ZaloSwitcher" "$APP/Contents/MacOS/ZaloSwitcher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/zalo-profiles" build/zalo-profiles

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Zalo Switcher</string>
    <key>CFBundleDisplayName</key>
    <string>Zalo Switcher</string>
    <key>CFBundleIdentifier</key>
    <string>local.zalo-switcher</string>
    <key>CFBundleExecutable</key>
    <string>ZaloSwitcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature, so macOS runs it on this Mac.
codesign --force --sign - "$APP"
codesign --force --sign - build/zalo-profiles

echo "Built: $APP"
echo "Built: build/zalo-profiles"
