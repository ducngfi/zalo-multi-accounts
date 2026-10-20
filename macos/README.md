# Zalo Switcher for macOS

The macOS app and command-line tool, as one Swift package. How to install and use them is in the [main README](../README.md); the rules they follow are in [docs/how-it-works.md](../docs/how-it-works.md).

## Build and test

You need macOS 13 or later and Xcode or the Command Line Tools. Run these from this folder:

```bash
swift build
swift test      # runs the profile logic against a fake Zalo in a temporary folder
scripts/build.sh      # builds "Zalo Switcher.app" and zalo-profiles into build/
scripts/install.sh    # builds, installs into ~/Applications and ~/.local/bin, and opens the app
```

The app gets an ad-hoc signature, so it runs on the Mac that built it. It isn't signed with a Developer ID or notarized.

## Code

- `Sources/ZaloProfilesCore`: profile storage, switching, backups and Zalo process control.
- `Sources/zalo-profiles`: the command-line tool.
- `Sources/ZaloSwitcher`: the SwiftUI menu-bar app.
- `Tests/ZaloProfilesCoreTests`: tests for the core.
- `Resources/AppIcon.icns`: the app icon, rendered from [`assets/icon/AppIcon.svg`](../assets/icon/AppIcon.svg) by `assets/icon/make-icons.sh`. Edit the SVG, not this file.
