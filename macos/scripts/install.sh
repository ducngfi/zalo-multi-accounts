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
        echo "Zalo Switcher chưa thoát (có thể đang mở một hộp thoại). Hãy thoát nó rồi chạy lại lệnh này." >&2
        exit 1
    fi
fi

rm -rf "$HOME/Applications/Zalo Switcher.app"
cp -R "build/Zalo Switcher.app" "$HOME/Applications/"
cp build/zalo-profiles "$HOME/.local/bin/zalo-profiles"

open "$HOME/Applications/Zalo Switcher.app"
echo "Đã cài ~/Applications/Zalo Switcher.app (cửa sổ của ứng dụng sẽ tự mở)"
echo "Đã cài ~/.local/bin/zalo-profiles"
