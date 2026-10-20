import Foundation
import ZaloProfilesCore

let usage = """
zalo-profiles: keep several Zalo accounts on this Mac and switch between them without logging out.

Usage:
  zalo-profiles status                 Show what is in Zalo now, every profile and its size
  zalo-profiles save <name>            Save the account that is in Zalo now as a profile
  zalo-profiles add <name>             Add an empty profile and switch to it (log in once)
  zalo-profiles switch <profile>       Quit Zalo, swap in <profile>'s data, start Zalo again
        [--no-launch]                  ...and don't start Zalo afterwards
  zalo-profiles open <profile>         Open <profile> in a second Zalo window (experimental)
  zalo-profiles close <profile>        Quit the Zalo window that has <profile> open
  zalo-profiles backup <profile> <folder>
                                       Back up a profile into <folder>/Zalo Backups/
  zalo-profiles restore <backup folder> <name>
                                       Restore a backup as a new profile called <name>
  zalo-profiles rename <profile> <new name>
  zalo-profiles remove <profile>       Move a profile and its data to the Trash
  zalo-profiles paths                  Show where the data lives

<profile> is a profile's name or id. When the Mac's disk is nearly full, add and open
refuse to run unless you add --force.
"""

let manager = ProfileManager()

func describe(_ status: ProfileStatus) -> String {
    var parts: [String] = []
    switch status.place {
    case .main: parts.append(status.runningPID == nil ? "in Zalo (not running)" : "in Zalo, running")
    case .parked: parts.append(status.runningPID == nil ? "saved" : "open side by side")
    case .new: parts.append("new, not logged in yet")
    }
    if let size = manager.dataSize(of: status) { parts.append(Disk.format(size)) }
    if let uid = status.zaloUserID { parts.append("Zalo id \(uid)") }
    return parts.joined(separator: ", ")
}

func printStatus() {
    switch manager.mainSlot() {
    case .empty:
        print("Zalo: no data yet (it will start at the login screen)")
    case .unsaved:
        let uid = manager.mainZaloUserID().map { " (Zalo id \($0))" } ?? ""
        print("Zalo: an account that isn't saved as a profile yet\(uid)")
        print("      Save it first:  zalo-profiles save \"<name>\"")
    case .profile(let id):
        let name = manager.profiles().first { $0.id == id }?.name ?? id
        print("Zalo: \(name)")
    }
    if let pid = manager.mainZaloPID() { print("      running (pid \(pid))") }
    if let free = manager.freeSpace() { print("Disk: \(Disk.format(free)) free on this Mac") }
    if let warning = manager.lowSpaceWarning() { print("Warning: \(warning)") }
    let statuses = manager.statuses()
    print("")
    if statuses.isEmpty {
        print("No profiles yet.")
        return
    }
    print("Profiles:")
    var seen: [String: String] = [:]
    for status in statuses {
        let mark = status.place == .main ? "*" : " "
        print(" \(mark) \(status.profile.name)  [\(status.profile.id)]  \(describe(status))")
        if let uid = status.zaloUserID {
            if let other = seen[uid] {
                print("     note: same Zalo account as “\(other)”; don't open both at the same time")
            }
            seen[uid] = status.profile.name
        }
    }
}

/// Prints progress; percentage updates rewrite the same line.
func report(_ message: String) {
    if message.contains("%") {
        print("\r\(message)\u{1B}[K", terminator: "")
        fflush(stdout)
    } else {
        print(message)
    }
}

/// Lets Ctrl-C stop a backup or restore cleanly instead of leaving half a copy behind.
func cancelOnInterrupt() -> CancelFlag {
    let flag = CancelFlag()
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    source.setEventHandler {
        print("\nStopping…")
        flag.cancel()
    }
    source.resume()
    interruptSource = source
    return flag
}

var interruptSource: DispatchSourceSignal?

func main() -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    let noLaunch = args.contains("--no-launch")
    let force = args.contains("--force")
    args.removeAll { $0 == "--no-launch" || $0 == "--force" }
    guard let command = args.first else {
        printStatus()
        return 0
    }
    let rest = Array(args.dropFirst())

    func need(_ count: Int) throws {
        guard rest.count == count else { throw UsageError() }
    }

    func checkSpace() throws {
        guard let warning = manager.lowSpaceWarning() else { return }
        guard force else { throw LowSpace(message: warning + " Add --force to go ahead anyway.") }
        print("Warning: \(warning)")
    }

    do {
        switch command {
        case "status", "list", "ls":
            printStatus()
        case "save":
            try need(1)
            let profile = try manager.saveCurrent(as: rest[0])
            print("Saved the account in Zalo as “\(profile.name)” [\(profile.id)].")
        case "add":
            try need(1)
            if manager.mainSlot() == .unsaved { throw ProfileError.currentDataNotSaved }
            try checkSpace()
            let profile = try manager.addProfile(named: rest[0])
            print("Added “\(profile.name)” [\(profile.id)].")
            try manager.switchTo(profile.id, launch: !noLaunch) { print($0) }
            if !noLaunch { print("Log in to the new account in Zalo. Next time, switching back needs no login.") }
        case "switch", "use":
            try need(1)
            let profile = try manager.find(rest[0])
            try manager.switchTo(profile.id, launch: !noLaunch) { print($0) }
            print("Zalo now uses “\(profile.name)”.")
            if let warning = manager.lowSpaceWarning() { print("Warning: \(warning)") }
        case "open":
            try need(1)
            let profile = try manager.find(rest[0])
            try checkSpace()
            try manager.openSideBySide(profile.id)
            print("Opened “\(profile.name)” in its own Zalo window.")
            print("Note: voice and video calls only work reliably in one Zalo window at a time.")
        case "close":
            try need(1)
            let profile = try manager.find(rest[0])
            try manager.close(profile.id)
            print("Closed “\(profile.name)”.")
        case "backup":
            try need(2)
            let profile = try manager.find(rest[0])
            let destination = URL(fileURLWithPath: (rest[1] as NSString).expandingTildeInPath, isDirectory: true)
            if manager.isOnThisMacsDisk(destination) {
                print("Note: \(destination.path) is on this Mac's own disk. The backup uses its free space and won't survive the disk failing; an external drive is safer.")
            }
            let cancel = cancelOnInterrupt()
            let folder = try manager.backup(profile.id, to: destination, progress: report, cancel: cancel)
            let info = try manager.readBackup(folder)
            let links = (info.links ?? 0) > 0 ? " (\(info.links!) of them hard links, kept as in Zalo's folder)" : ""
            print("\nBacked up “\(profile.name)”: \(info.files) files\(links), \(Disk.format(info.bytes)), every file checked.")
            print("Saved in \(folder.path)")
        case "restore":
            try need(2)
            let folder = URL(fileURLWithPath: (rest[0] as NSString).expandingTildeInPath, isDirectory: true)
            let info = try manager.readBackup(folder)
            print("Backup of “\(info.profileName)” from \(info.createdAt.formatted(date: .abbreviated, time: .shortened)): \(info.files) files, \(Disk.format(info.bytes)).")
            let cancel = cancelOnInterrupt()
            let profile = try manager.restore(from: folder, as: rest[1], progress: report, cancel: cancel)
            print("\nRestored as “\(profile.name)” [\(profile.id)]. Switch to it or open it side by side to use it.")
            if let original = manager.statuses().first(where: { $0.profile.id != profile.id && $0.zaloUserID == info.zaloUserID && info.zaloUserID != nil }) {
                print("Note: “\(original.profile.name)” is the same Zalo account. Don't have both open at the same time.")
            }
        case "rename":
            try need(2)
            let profile = try manager.find(rest[0])
            try manager.rename(profile.id, to: rest[1])
            print("Renamed “\(profile.name)” to “\(rest[1])”.")
        case "remove", "rm":
            try need(1)
            let profile = try manager.find(rest[0])
            let trashed = try manager.remove(profile.id)
            print("Moved “\(profile.name)” to the Trash\(trashed.map { " (\($0.path))" } ?? ""). Put it back from the Trash to restore it.")
        case "paths":
            print("Zalo app:       \(manager.layout.zaloApp.path)")
            print("Zalo data:      \(manager.layout.liveData.path)")
            print("Profiles:       \(manager.layout.profilesRoot.path)")
        case "help", "-h", "--help":
            print(usage)
        default:
            throw UsageError()
        }
        return 0
    } catch is UsageError {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        return 2
    } catch let error as LowSpace {
        FileHandle.standardError.write(Data("Error: \(error.message)\n".utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data("\nError: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

struct UsageError: Error {}

struct LowSpace: Error {
    var message: String
}

exit(main())
