# How Zalo Switcher works

This is the behaviour every version of Zalo Switcher follows, whatever the platform. The macOS version implements it in [`macos/Sources/ZaloProfilesCore`](../macos/Sources/ZaloProfilesCore). A Windows version should follow the same rules and use the same file formats, so that both behave the same way and are explained by the same README.

Paths below are for macOS. Where a platform needs its own answer, the section says so.

## The idea

The Zalo desktop app keeps everything for the logged-in account (session, message database, photos, files, settings) in one data folder. On macOS that is `~/Library/Application Support/ZaloData`, and Zalo can't be pointed at another folder: it ignores `--user-data-dir`.

So the switcher keeps one complete data folder per account, called a **profile**, and while Zalo is closed it renames the right one into the place where Zalo looks. The folder Zalo uses is the **main slot**. A profile whose data is in its own folder is **parked**.

## The profile store

```
<profiles root>/
    state.json                  which profile was last put in the main slot
    <id>/profile.json           the profile's name and dates
    <id>/<parked data path>     the profile's Zalo data while it is parked
```

On macOS the profiles root is `~/Library/Application Support/Zalo Profiles`, and the parked data path is `Library/Application Support/ZaloData`. Each profile folder is shaped like a home folder so that it can also be used as the home of a second Zalo (see [Side by side](#side-by-side-macos-only)).

`profile.json`:

```json
{
  "createdAt" : "2026-10-20T13:00:00Z",
  "id" : "work",
  "lastUsedAt" : "2026-10-20T14:30:00Z",
  "name" : "Work"
}
```

`lastUsedAt` is absent until the profile is first opened. `state.json` is `{ "main" : "<id>" }`. Dates are ISO 8601.

- **id**: the folder name, made from the name: accents removed and "đ" becomes "d", lowercase ASCII letters and digits kept, everything else turned into single dashes. If the id is taken, `-2`, `-3` and so on are added. An empty result becomes `profile`. Example: "Đức – Work" → `duc-work`.
- **name**: free text, unique ignoring case and accents. A profile can be found by id or by name.
- **marker**: a file `.zalo-profile-id` inside a data folder holds the id of the profile it belongs to, on one line.

## Which profile is in the main slot

1. There is no main data folder: the slot is **empty**, and Zalo will start at the login screen.
2. The marker in the main data folder names an existing profile: that profile is in the slot.
3. Otherwise, if `state.json` names an existing profile and that profile has no parked folder: that profile is in the slot. (Zalo can remove the marker, for example after logging out.)
4. Otherwise the slot holds **unsaved** data that belongs to no profile. Nothing may be switched until it is saved as a profile.

Each profile is then in the **main** slot, **parked** (it has a parked data folder), or **new** (it has never been opened).

## Switching to a profile

1. If the target is already in the main slot, start Zalo or bring it to the front. Done.
2. Refuse if the main slot holds unsaved data, or if the target is open in a second window.
3. If Zalo is running on the main data folder, ask it to quit the normal way (like ⌘Q) and wait up to 60 seconds for it and its helper processes to exit. Never force-quit. If it is still running, stop: nothing has been moved yet.
4. If a profile is in the main slot, rename the main data folder to that profile's parked path.
5. Rename the target's parked folder to the main data folder. If this fails, rename the previous profile's folder back, so Zalo opens as it was. If the target is new, create an empty main data folder (readable only by the user) instead, so Zalo starts at the login screen.
6. Write the marker, save `state.json` and set the target's `lastUsedAt`.
7. Start Zalo.

## Safety rules

These are what make switching safe. Every version must keep them.

- **Only renames.** Every change of place is a rename within one disk. It is instant, needs no free space and can't be left half done. A rename that would replace something at the destination, or that would have to copy because the destination is on another disk, must fail instead. (macOS: `renamex_np` with `RENAME_EXCL`.)
- **Never delete Zalo data.** Removing a profile moves its whole folder to the Trash (Recycle Bin), where it can be put back. The profile in the main slot, and one open in a second window, can't be removed.
- **Never force-quit Zalo.** A forced quit can leave its databases halfway through a write.
- **Stop when unsure.** Anything unexpected (a folder in the way, Zalo still running, a missing profile) stops the operation before anything moves, with a message that says why.
- **Watch the free space.** Below 5 GB free on the disk with Zalo's data, warn, and ask before adding an account or opening one in a second window (`--force` on the command line). Zalo writes messages as they arrive, and a full disk is the main way its data gets damaged.

## Telling whether Zalo has a folder open

The Zalo desktop app is built on Electron (Chromium). On macOS, while a data folder is open, Chromium keeps a `SingletonLock` symbolic link in it that points to `<host>-<pid>`. The switcher reads the pid and checks that the process is alive and is Zalo (bundle id `com.vng.zalo`). Each platform needs its own way to find this.

## The Zalo account in a data folder

The Zalo account id is the name of the most recently modified folder made only of digits (at least six) in `<data folder>/Database/_production/`. It is used to point out two profiles that hold the same account, for example after restoring a backup.

## Backups

A backup is a folder `<destination>/Zalo Backups/<id> <yyyy-MM-dd HH.mm>/` containing `ZaloData/` and `backup.json`:

```json
{
  "bytes" : 455000000,
  "createdAt" : "2026-10-20T14:00:00Z",
  "files" : 508,
  "format" : 1,
  "links" : 0,
  "profileID" : "work",
  "profileName" : "Work",
  "zaloUserID" : "123456789"
}
```

- `files` counts every file name, including the extra names of hard-linked files. `bytes` counts hard-linked data once. `links` is how many names were recreated as hard links.
- Making one: close Zalo for that profile only while a consistent copy is taken (macOS: an APFS clone, a few seconds), reopen Zalo, then copy to the destination in the background, checking every file's size. The copy is written under the name `<name>.partial` and gets its final name and `backup.json` only when everything checks out. A failed or cancelled copy is removed.
- Restoring one: copy `ZaloData/` into a staging folder inside the profiles root, check it against `backup.json`, and only then make it a **new** profile. A restore never replaces an existing profile.

## Side by side (macOS only)

Experimental. A parked profile can be opened in a second Zalo while the main one keeps running: Zalo is started with `CFFIXED_USER_HOME` set to the profile folder, so its Application Support folder, and with it its data folder, is the profile's own. The profile folder gets symbolic links to the real Keychain, Downloads, Desktop, Documents, Pictures, Movies and Music. Calls only work reliably in one window, because Zalo's call helper uses fixed socket paths.

Other platforms would need a different way to give a second Zalo its own data folder, or may not support this at all.
