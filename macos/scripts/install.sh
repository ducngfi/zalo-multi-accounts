#!/bin/bash
# Builds and installs Zalo Switcher into ~/Applications and zalo-profiles into ~/.local/bin, then opens the app.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

mkdir -p "$HOME/Applications" "$HOME/.local/bin"
osascript -e 'tell application id "local.zalo-switcher" to quit' 2>/dev/null || true
rm -rf "$HOME/Applications/Zalo Switcher.app"
cp -R "build/Zalo Switcher.app" "$HOME/Applications/"
cp build/zalo-profiles "$HOME/.local/bin/zalo-profiles"

open "$HOME/Applications/Zalo Switcher.app"
echo "Installed ~/Applications/Zalo Switcher.app (look for the two-person icon in the menu bar)"
echo "Installed ~/.local/bin/zalo-profiles"
