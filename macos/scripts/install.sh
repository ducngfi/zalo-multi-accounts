#!/bin/bash
# Builds and installs Zalo Switcher into ~/Applications and zalo-profiles into ~/.local/bin, then opens the app.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

mkdir -p "$HOME/Applications" "$HOME/.local/bin"

# Ask a running copy to quit, and wait until it has: opening the new copy while the old one is
# still shutting down fails (LaunchServices error -600). Never force-quit it.
running() { pgrep -x -u "$(id -u)" ZaloSwitcher >/dev/null; }
if running; then
    osascript -e 'ignoring application responses' \
              -e 'tell application id "local.zalo-switcher" to quit' \
              -e 'end ignoring' 2>/dev/null || true
    for _ in {1..100}; do
        running || break
        sleep 0.2
    done
    if running; then
        echo "Zalo Switcher didn't quit (a dialog may be open). Quit it from its menu, then run this again." >&2
        exit 1
    fi
fi

rm -rf "$HOME/Applications/Zalo Switcher.app"
cp -R "build/Zalo Switcher.app" "$HOME/Applications/"
cp build/zalo-profiles "$HOME/.local/bin/zalo-profiles"

open "$HOME/Applications/Zalo Switcher.app"
echo "Installed ~/Applications/Zalo Switcher.app (look for the two-person icon in the menu bar)"
echo "Installed ~/.local/bin/zalo-profiles"
