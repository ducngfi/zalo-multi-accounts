<p align="center"><img src="assets/icon/AppIcon-1024.png" width="160" alt="Zalo Switcher icon"></p>

# Zalo Switcher

Keep several Zalo accounts on one Mac and switch between them without logging out, typing a password or scanning a QR code again, and without losing messages, photos or files.

**macOS only** (macOS 13 or later). There is no Windows version yet; the project is laid out so one can be added later (see [Project layout](#project-layout)).

It comes in two forms that share the same code:

- **Zalo Switcher.app**, a menu-bar app.
- **`zalo-profiles`**, a command-line tool.

> [!IMPORTANT]
> **Not affiliated with Zalo.** Zalo Switcher is an independent, unofficial project. It is not made, endorsed or supported by Zalo or VNG, and its author has nothing to do with the Zalo brand. "Zalo" is a trademark of its owner and is used here only to say which app this tool works with. For help with Zalo itself, contact Zalo, not this project.

> [!WARNING]
> **Use at your own risk.** Zalo Switcher moves the folder that holds all of your Zalo messages, photos and files. It is written to be careful (it only renames folders, never deletes Zalo data, and stops when anything looks wrong), but it comes with no warranty of any kind. **The author takes no responsibility if you lose data, lose access to an account, or run into any other problem from using it.** Back up your Zalo data before you start, and keep backups of anything you can't afford to lose. See [LICENSE](LICENSE).

## Limitations, and why they exist

Some things this tool can't do. Most of them come from how Zalo works, not from this app, and no app on your computer can change them.

**One account can't be logged in on two phones, two computers or two Zalo Web sessions at the same time.** Zalo's servers allow each account one session of each kind at a time: one phone, one desktop app and one web session ([chat.zalo.me](https://chat.zalo.me)). Logging in to a second phone logs out the first. Logging in to the desktop app on a second computer ends the desktop session on the first, and the same happens with a second browser. This rule is enforced on Zalo's servers, so Zalo Switcher can't lift it, and neither can any other app on your computer. Zalo publishes no official numbers and articles online disagree; what is described here matches what you see on your own account.

What does work is using the different kinds of session at once, for example:

- your phone,
- the Zalo desktop app on computer A,
- [chat.zalo.me](https://chat.zalo.me) in a browser on computer B (log in with a QR code from your phone).

All three stay logged in at the same time. Check this once on your account: log in on computer B's browser while A's app is open, and confirm that A stays logged in.

What Zalo Switcher does is different: it keeps **several different accounts** on **one** Mac and lets you change which one the Zalo app has open.

**It won't copy a logged-in session to another computer.** Copying a logged-in Zalo data folder to a second Mac so that both run "the same" desktop session doesn't get around the rule above. Zalo's server would see one session connecting from two places. At best one copy gets logged out; at worst the account is flagged for unusual activity. That risk isn't worth taking with your main account, so this project doesn't do it.

**Only the account that is open in Zalo gets notifications.** The other accounts stay logged in on Zalo's servers, but nothing on the Mac is listening for them. Their messages arrive when you switch back, the same as when the Mac has been switched off for that time.

**Switching restarts Zalo.** It takes a few seconds. If Zalo won't quit (during a call, or while a dialog is open), the switch stops and nothing is moved.

**Every account takes its own disk space.** Each account keeps its own complete copy of Zalo's data, often several GB or more, because that is how Zalo stores it.

**It depends on where Zalo keeps its data.** Zalo has no official way to run several accounts, so this tool works with the folder Zalo uses today. If a Zalo update moves that folder, the tool stops finding it and moves nothing, until it is updated.

**Two windows at once is experimental.** See [Side by side](#side-by-side-experimental): voice and video calls only work reliably in one window.

**The download isn't notarized by Apple.** macOS shows a security warning the first time you open it. [The security warning](#the-security-warning-the-first-time) explains why and how to open it anyway.

## How switching works

Zalo stores everything (login session, message database, photos, files, settings) in one folder:

```
~/Library/Application Support/ZaloData        ← the folder the Zalo app uses
```

Zalo ignores the usual `--user-data-dir` option and always uses that path, so the switcher keeps one complete copy of that folder per account and puts the right one in place:

```
~/Library/Application Support/Zalo Profiles/
    personal/profile.json
    personal/Library/Application Support/ZaloData   ← parked while another account is in Zalo
    work/profile.json
    work/Library/Application Support/ZaloData
```

Switching to another account:

1. Asks Zalo to quit (like ⌘Q) and waits until it and its helper processes have exited. It never force-quits. If Zalo doesn't quit, it stops and nothing is moved.
2. Renames `ZaloData` into the current profile's folder.
3. Renames the target profile's folder to `ZaloData`.
4. Starts Zalo, which opens already logged in to that account.

Every step is a rename on the same disk: it takes a fraction of a second whatever the folder's size, uses no extra disk space, and never copies or deletes anything. The tool also refuses to:

- switch while the account in Zalo isn't saved as a profile yet, so its data can't be lost;
- replace anything at a destination (if a folder is unexpectedly in the way, it stops);
- move data across disks (that would be a copy).

Removing a profile moves its folder to the Trash, where you can still put it back.

The full rules, including the file formats, are in [docs/how-it-works.md](docs/how-it-works.md).

## Install

You need macOS 13 or later and the Zalo desktop app. Zalo Switcher runs on Apple silicon and Intel Macs.

1. Download **Zalo-Switcher-1.0.0-macOS.zip** from the [latest release](https://github.com/ducngfi/zalo-multi-accounts/releases/latest).
2. Open the zip (Safari opens it for you) and drag **Zalo Switcher.app** into your **Applications** folder.
3. Open Zalo Switcher. The first time, macOS shows a security warning: see the next section.
4. Look for the two-person icon at the top of the screen, and [save your first account](#use-it-from-the-menu-bar).

### The security warning the first time

macOS warns about any app that Apple hasn't checked (notarized). Notarizing needs a paid Apple Developer membership, which this free project doesn't have, so you see the warning once. It doesn't mean macOS found a problem in the app. All of its source code is in this repository; if you'd rather not trust a download, [build it yourself](#build-it-yourself).

**macOS 15 Sequoia and later, including macOS 26 Tahoe:**

1. Open the app. macOS says it can't verify that "Zalo Switcher" is free of malware. Click **Done**, not Move to Trash.
2. Open **System Settings → Privacy & Security** and scroll down to **Security**. Next to the line saying "Zalo Switcher" was blocked, click **Open Anyway**.
3. Click **Open Anyway** again in the dialog that appears, and confirm with your password or Touch ID.

**macOS 13 Ventura and 14 Sonoma:**

1. In Finder, open **Applications**, Control-click (or right-click) **Zalo Switcher** and choose **Open**.
2. Click **Open** in the dialog that appears.

**Any version, in Terminal:** this removes the "downloaded from the internet" mark that makes macOS check the app. Then open the app normally.

```bash
xattr -dr com.apple.quarantine "/Applications/Zalo Switcher.app"
```

You only do this once. macOS may ask again after you install a new version.

### The command-line tool (optional)

Download **zalo-profiles-1.0.0-macOS.zip** from the same release and open it, so that `zalo-profiles` is in your Downloads folder. Then, in Terminal:

```bash
mkdir -p ~/.local/bin
mv ~/Downloads/zalo-profiles ~/.local/bin/
xattr -c ~/.local/bin/zalo-profiles
```

The last line removes the download mark, which would otherwise make macOS block the command. If Terminal then says `command not found: zalo-profiles`, add the folder to your path and open a new Terminal window:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

To check a download, run `shasum -a 256 -c SHA256SUMS.txt` in the folder with the zips and the `SHA256SUMS.txt` from the release.

### Build it yourself

You need Apple's developer tools for `swift`: either Xcode, or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ducngfi/zalo-multi-accounts.git
```

```bash
zalo-multi-accounts/macos/scripts/install.sh
```

This builds the app and the command, installs `~/Applications/Zalo Switcher.app` and `~/.local/bin/zalo-profiles`, and opens the app. An app built on your own Mac opens without the security warning. To build without installing, run `macos/scripts/build.sh` (output in `macos/build/`).

## Use it from the menu bar

1. Click the two-person icon at the top of the screen. The first time, choose **Save Current Account as Profile…** and name the account that's in Zalo now, for example "Personal". Zalo keeps running.
2. Choose **Add Account…** and name the next account, for example "Work". Zalo restarts at the login screen; log in once with that account (QR code or password).
3. From then on, click a profile name in the menu to switch. The check mark shows which account is in Zalo, and its name appears next to the icon.

The menu also shows each profile's size and how much space is free on the Mac.

Other menu items:

- **Back Up:** back up a profile to an external drive, or restore a backup (see below).
- **Manage Profiles:** rename profiles, move one to the Trash, or show the profiles folder in Finder.
- **Open at Login:** starts the switcher when you log in to the Mac.
- **Side by Side (Experimental):** see below.

## Use it from the command line

```bash
zalo-profiles status                 # what's in Zalo now, every profile, sizes, free space
zalo-profiles save "Personal"        # save the account that's in Zalo now
zalo-profiles add "Work"             # add a profile, restart Zalo at the login screen
zalo-profiles switch personal        # switch (by name or id)
zalo-profiles switch work --no-launch
zalo-profiles rename work "Shop"
zalo-profiles remove shop            # moves it to the Trash
zalo-profiles open shop              # side by side (experimental)
zalo-profiles close shop             # quit the window that has "shop" open
zalo-profiles backup personal /Volumes/MyDrive
zalo-profiles restore "/Volumes/MyDrive/Zalo Backups/personal 2026-10-20 21.00" "Personal (restored)"
zalo-profiles paths
```

## Disk space

Each profile's size and the Mac's free space show in the menu and in `zalo-profiles status`. Below 5 GB free:

- the menu-bar icon turns into a warning triangle;
- adding an account or opening one side by side asks first. On the command line, `add` and `open` refuse unless you add `--force`.

Zalo writes messages and photos as they arrive, so a full disk is the main way its data could get damaged. Switching itself needs no free space, because it only renames folders.

## Backups

**Back Up → Back Up <profile>…** (or `zalo-profiles backup <profile> <folder>`) copies a profile's complete Zalo data to a folder you choose, normally an external drive. It goes into `Zalo Backups/<profile> <date and time>/` on that drive:

1. If Zalo has the profile open, it closes that window for a few seconds. The databases must be complete, not halfway through a write.
2. It takes an APFS snapshot of the data: an instant copy that shares disk space with the original, so it costs almost nothing.
3. It reopens Zalo. Every other Zalo window keeps running throughout.
4. It copies the snapshot to the drive in the background and checks that every copied file has the original's size. You can keep using and switching Zalo meanwhile.

   Zalo stores much of its media under two names that share the same data (hard links), often several GB. The backup copies that data once and recreates the second name as a link, so it is the same size as the original. A snapshot loses these links, so they are read from the original while Zalo is still closed. On a drive that can't hold hard links (exFAT, FAT), each name gets its own copy instead, which makes the backup bigger.
5. Only when every file checks out does the folder get its final name and a `backup.json` record. A failed or cancelled backup is removed rather than left half-written, and the snapshot is always removed at the end.

Before starting, the tool checks that the drive has room. It refuses folders inside Zalo's own data, and it warns if the folder is on the Mac's own disk, because a backup there doesn't protect against that disk failing.

**Back Up → Restore from Backup…** (or `zalo-profiles restore <backup folder> <name>`) brings a backup back as a **new** profile. It never replaces an existing one. The copy is checked against `backup.json` before the profile appears. The Mac must have room for the backup plus the 5 GB spare.

A restored profile is the same Zalo account as the one that was backed up. While the original profile still exists, don't open both at the same time; `status` points this out. If the account was logged in somewhere else since the backup, Zalo may ask you to log in again.

Tested on 2026-10-20 with an external APFS drive:

| Profile | Files | Data | Zalo closed for | Total time |
|---|---|---|---|---|
| Open in a second window | 508 | 455 MB | under 2 s | 1.9 s |
| Open in the main Zalo | 48,056 (13,799 of them hard links) | 13.75 GB | about 15 s | 75 s |

- In both cases Zalo reopened logged in by itself, and the other window was never interrupted.
- The smaller backup was restored as a test profile, with the original closed meanwhile, and it opened logged in.

## Side by side (experimental)

**Side by Side → Open …** starts a second Zalo window for a parked profile while the main one keeps running, so two accounts are online at the same time. The second Zalo is started with `CFFIXED_USER_HOME` set to the profile's folder. macOS then gives it its own Application Support folder, so it reads and writes that profile's `ZaloData` and never touches the main one. The profile folder gets links to your real Keychain (where Zalo keeps its encryption key), Downloads, Desktop, Documents, Pictures, Movies and Music.

**Side by Side → Close …** quits that window, the same way as ⌘Q in it.

Known limits:

- **Calls.** Zalo's call helper talks to the app through fixed socket files (`/tmp/socketzalosend2021`, `/tmp/socketzalorecv2021`). Each Zalo that starts takes them over, so voice and video calls only work reliably in one window, and the main Zalo may need a restart before calls work again. Quit side-by-side windows and restart Zalo before an important call.
- Both windows show the same Zalo icon in the Dock. Tell them apart by the account avatar.
- A profile open side by side can't be switched to or removed until you quit its window.

Tested on 2026-10-20 with Zalo 26.8.20 on macOS 26.1, with one account in the main Zalo and another side by side:

- The second account opened already logged in.
- Each Zalo had only its own account's data. The second window held 163 open files, all inside its profile folder and none in the main `ZaloData`.
- The main Zalo kept running without a restart.
- The second Zalo did take over the call sockets, as expected. Calls weren't tested.

## Good to know

- Received files go to your normal Downloads folder for every account.
- If a Zalo update ever moves its data folder, `zalo-profiles status` will stop finding it. Nothing is moved in that case.
- To stop using the switcher, switch to the account you want to keep in Zalo, quit the switcher and delete the app. Zalo carries on with that account. The other accounts' data stays in `~/Library/Application Support/Zalo Profiles/<id>/Library/Application Support/ZaloData`.

## Project layout

```
macos/          the macOS app and command-line tool (Swift package)
windows/        reserved for a native Windows app (not started)
docs/           how profiles and switching work, the same on every platform
assets/icon/    the app icon: SVG master, and the rendered macOS and Windows icons
```

Each platform keeps its own code, build scripts and tests in its own folder. What they share is the behaviour and the file formats in [docs/how-it-works.md](docs/how-it-works.md) and the icon in `assets/icon/`. Building and testing the macOS version is described in [macos/README.md](macos/README.md).

## License

[MIT](LICENSE). The software is provided "as is", without warranty of any kind.
