# Zalo Switcher for Windows

Not started. Zalo Switcher runs on macOS only for now; this folder is where a native Windows app will go.

A Windows version should:

- live entirely in this folder, with its own code, build scripts and tests (for example a .NET solution);
- follow the behaviour, safety rules and file formats in [docs/how-it-works.md](../docs/how-it-works.md), so profiles and backups work the same way as on the Mac;
- use the icon in [assets/icon](../assets/icon): `AppIcon.ico` is ready to use, and `make-icons.sh` renders it again from `AppIcon.svg`.

## To find out first

None of this has been checked on Windows yet.

- Where Zalo for Windows keeps its data, and whether everything (session, messages, photos, files) is in one folder, as on the Mac.
- Whether Zalo can be started with another data folder, which would make switching or a second window simpler.
- How to tell whether Zalo has a data folder open, and how to make it quit cleanly. Closing the window may only hide it in the notification area, and Windows won't rename a folder while files in it are open.
- Renames: `MoveFileEx` without `MOVEFILE_REPLACE_EXISTING` and without `MOVEFILE_COPY_ALLOWED` fails instead of replacing something or copying across disks, which matches the "only renames" rule.
- Where profiles should live (for example `%LOCALAPPDATA%\Zalo Profiles`), on the same disk as Zalo's data.
