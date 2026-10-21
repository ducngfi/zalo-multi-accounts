import Foundation

/// What `backup.json` in a backup folder records.
public struct BackupInfo: Codable, Equatable, Sendable {
    public var format = 1
    public var profileID: String
    public var profileName: String
    public var zaloUserID: String?
    public var createdAt: Date
    /// Every file name, including the extra names of hard-linked files.
    public var files: Int
    /// The data stored, counting hard-linked files once.
    public var bytes: Int64
    /// How many file names were recreated as hard links (absent in backups made before links were kept).
    public var links: Int?
}

/// A frozen copy of a profile's data. It is an APFS clone, so it shares disk blocks with the
/// original and costs almost no space while the backup is copied from it.
public struct BackupSnapshot: Sendable {
    public let profile: Profile
    public let zaloUserID: String?
    let folder: URL
    /// Zalo stores much of its data under two names (hard links). A clone loses that, so the
    /// groups are read from the original while Zalo is closed: relative path → group.
    let linkGroups: [String: String]
}

/// A flag another thread can set to stop a long copy.
public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

extension ProfileManager {
    public static let backupsFolderName = "Zalo Backups"
    static let snapshotPrefix = ".snapshot-"
    static let restorePrefix = ".restore-"

    /// Backs up a profile to `<destination>/Zalo Backups/<id> <date>/`: takes a snapshot (closing
    /// Zalo for a few seconds if the profile is open), copies it, and checks every file.
    @discardableResult
    public func backup(_ id: String, to destination: URL, progress: @escaping (String) -> Void = { _ in },
                       cancel: CancelFlag = CancelFlag()) throws -> URL {
        try checkBackupDestination(id, destination: destination)
        let snapshot = try takeSnapshot(id, progress: progress)
        defer { discard(snapshot) }
        return try writeBackup(snapshot, to: destination, progress: progress, cancel: cancel)
    }

    /// Whether `url` is on the same disk as Zalo's data (so a backup there doesn't protect against
    /// the Mac's disk failing, and uses its free space).
    public func isOnThisMacsDisk(_ url: URL) -> Bool {
        Disk.sameVolume(url, layout.applicationSupport)
    }

    /// Checks that a profile can be backed up to `destination` and that there is room for it.
    public func checkBackupDestination(_ id: String, destination: URL) throws {
        guard let status = status(of: id) else { throw ProfileError.notFound(id) }
        guard let data = status.dataFolder else { throw ProfileError.nothingToBackUp(status.profile.name) }
        guard isDirectory(destination), fm.isWritableFile(atPath: destination.path) else {
            throw ProfileError.notAFolder(destination.path)
        }
        let target = destination.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        for inside in [layout.profilesRoot, layout.liveData] {
            if target.hasPrefix(inside.standardizedFileURL.resolvingSymlinksInPath().path + "/") {
                throw ProfileError.badBackupFolder
            }
        }
        let needed = (Disk.allocatedSize(of: data) ?? 0) + 100_000_000
        if let free = freeSpaceProvider(destination), free < needed {
            throw ProfileError.notEnoughSpace(place: destination.path, needed: needed, free: free)
        }
    }

    /// Takes a snapshot of a profile's data. If Zalo has the profile open, it is closed for the
    /// few seconds the snapshot takes, so the databases are complete, and then opened again.
    public func takeSnapshot(_ id: String, progress: (String) -> Void = { _ in }) throws -> BackupSnapshot {
        guard let status = status(of: id) else { throw ProfileError.notFound(id) }
        guard let data = status.dataFolder else { throw ProfileError.nothingToBackUp(status.profile.name) }
        removeStaleTemporaryFolders()
        try fm.createDirectory(at: layout.profilesRoot, withIntermediateDirectories: true)

        var reopen: (() throws -> Void)?
        if status.runningPID != nil {
            progress("Đang tạm đóng Zalo…")
            try zalo.quit(dataFolder: data, timeout: quitTimeout)
            if zalo.pidUsing(dataFolder: data) != nil { throw ProfileError.zaloDidNotQuit }
            let app = layout.zaloApp
            let home = layout.profileHome(id)
            reopen = status.place == .main
                ? { [zalo] in try zalo.launchMain(app: app) }
                : { [zalo] in try zalo.launchIsolated(app: app, home: home) }
        }
        defer {
            if let reopen {
                progress("Đang mở lại Zalo…")
                try? reopen()
            }
        }

        progress("Đang chụp nhanh dữ liệu của \(status.profile.name)…")
        let stamp = Int(Date().timeIntervalSince1970)
        let folder = layout.profilesRoot.appendingPathComponent("\(Self.snapshotPrefix)\(stamp)-\(UUID().uuidString)")
        guard clonefile(data.path, folder.path, 0) == 0 else {
            let reason = String(cString: strerror(errno))
            try? fm.removeItem(at: folder)
            throw ProfileError.snapshotFailed(reason)
        }
        // Read the hard links now, while Zalo is still closed and the original matches the clone.
        let groups = hardLinkGroups(in: data)
        return BackupSnapshot(profile: status.profile, zaloUserID: status.zaloUserID, folder: folder, linkGroups: groups)
    }

    /// Finds the files in `folder` that are hard links to the same data: relative path → group.
    func hardLinkGroups(in folder: URL) -> [String: String] {
        guard let scan = fm.enumerator(atPath: folder.path) else { return [:] }
        var groups: [String: String] = [:]
        while let path = scan.nextObject() as? String {
            guard let attributes = scan.fileAttributes,
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let count = (attributes[.referenceCount] as? NSNumber)?.intValue, count > 1,
                  let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                  let device = (attributes[.systemNumber] as? NSNumber)?.int64Value
            else { continue }
            groups[path] = "\(device)-\(inode)"
        }
        return groups
    }

    /// Copies a snapshot to `<destination>/Zalo Backups/<id> <date>/` and records it in backup.json.
    /// The copy is written under a `.partial` name and only gets its final name once every file has
    /// been checked; if anything fails or is cancelled, the unfinished copy is removed.
    public func writeBackup(_ snapshot: BackupSnapshot, to destination: URL,
                            progress: @escaping (String) -> Void = { _ in },
                            cancel: CancelFlag = CancelFlag()) throws -> URL {
        let root = destination.appendingPathComponent(Self.backupsFolderName, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let base = "\(snapshot.profile.id) \(Self.stampFormatter.string(from: Date()))"
        var name = base
        var n = 2
        while existsOrLink(root.appendingPathComponent(name)) || existsOrLink(root.appendingPathComponent(name + ".partial")) {
            name = "\(base) \(n)"
            n += 1
        }
        let final = root.appendingPathComponent(name, isDirectory: true)
        let partial = root.appendingPathComponent(name + ".partial", isDirectory: true)
        try fm.createDirectory(at: partial, withIntermediateDirectories: false)
        do {
            let copied = try copyTree(from: snapshot.folder, to: partial.appendingPathComponent("ZaloData"),
                                      label: "Đang sao lưu \(snapshot.profile.name)", linkGroups: snapshot.linkGroups,
                                      progress: progress, cancel: cancel)
            let info = BackupInfo(profileID: snapshot.profile.id, profileName: snapshot.profile.name,
                                  zaloUserID: snapshot.zaloUserID, createdAt: Date(),
                                  files: copied.files, bytes: copied.bytes, links: copied.links)
            try Self.encoder.encode(info).write(to: partial.appendingPathComponent("backup.json"))
            try fm.moveItem(at: partial, to: final)
            return final
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
    }

    /// Removes a snapshot once its backup is written. The profile's own data is not touched.
    public func discard(_ snapshot: BackupSnapshot) {
        let folder = snapshot.folder
        guard folder.deletingLastPathComponent().standardizedFileURL == layout.profilesRoot.standardizedFileURL,
              folder.lastPathComponent.hasPrefix(Self.snapshotPrefix) else { return }
        try? fm.removeItem(at: folder)
    }

    /// Reads the record of a backup folder, or throws if the folder isn't a backup.
    public func readBackup(_ folder: URL) throws -> BackupInfo {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("backup.json")),
              let info = try? Self.decoder.decode(BackupInfo.self, from: data),
              isDirectory(folder.appendingPathComponent("ZaloData"))
        else { throw ProfileError.notABackup(folder.path) }
        return info
    }

    /// Restores a backup as a new profile called `name`. It never replaces an existing profile.
    /// The copy is checked against backup.json before the profile appears.
    @discardableResult
    public func restore(from folder: URL, as name: String, progress: @escaping (String) -> Void = { _ in },
                        cancel: CancelFlag = CancelFlag()) throws -> Profile {
        let info = try readBackup(folder)
        let clean = try validName(name, ignoring: nil)
        // Leave Zalo the usual spare room after the restored data is in.
        let needed = info.bytes + lowSpaceThreshold
        if let free = freeSpace(), free < needed {
            throw ProfileError.notEnoughSpace(place: "máy Mac này", needed: needed, free: free)
        }
        removeStaleTemporaryFolders()
        try fm.createDirectory(at: layout.profilesRoot, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let staging = layout.profilesRoot.appendingPathComponent("\(Self.restorePrefix)\(stamp)-\(UUID().uuidString)")
        do {
            let copied = try copyTree(from: folder.appendingPathComponent("ZaloData"), to: staging,
                                      label: "Đang khôi phục \(clean)", progress: progress, cancel: cancel)
            guard copied.files == info.files, copied.bytes == info.bytes else {
                throw ProfileError.copyMismatch("bản sao lưu (\(copied.files) tệp, \(Disk.format(copied.bytes)); backup.json ghi \(info.files) tệp, \(Disk.format(info.bytes)))")
            }
            let profile = try createProfile(named: clean)
            let target = layout.parkedData(profile.id)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try move(staging, to: target)
            try? writeMarker(profile.id, in: target)
            return profile
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Copies a folder file by file, checking that each copy has the original's size. Files that
    /// are hard links to the same data are copied once and linked again, as in the original
    /// (`linkGroups` overrides the groups read from `source`). Skips symbolic links, sockets and
    /// "._" files that some external drives add.
    func copyTree(from source: URL, to destination: URL, label: String, linkGroups: [String: String]? = nil,
                  progress: (String) -> Void, cancel: CancelFlag) throws -> (files: Int, bytes: Int64, links: Int) {
        let groups = linkGroups ?? hardLinkGroups(in: source)
        guard let scan = fm.enumerator(atPath: source.path) else {
            throw ProfileError.copyFailed(source.path, reason: "không đọc được")
        }
        var items: [(path: String, isDirectory: Bool, size: Int64)] = []
        var total: Int64 = 0
        var counted: Set<String> = []
        while let path = scan.nextObject() as? String {
            if (path as NSString).lastPathComponent.hasPrefix("._") { continue }
            switch scan.fileAttributes?[.type] as? FileAttributeType {
            case .typeDirectory?:
                items.append((path, true, 0))
            case .typeRegular?:
                let size = (scan.fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
                items.append((path, false, size))
                if let group = groups[path], !counted.insert(group).inserted { continue }
                total += size
            default:
                continue
            }
        }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var files = 0
        var links = 0
        var copied: Int64 = 0
        var firstCopy: [String: URL] = [:]
        var reported = -1
        for item in items {
            if cancel.isCancelled { throw ProfileError.cancelled }
            let from = source.appendingPathComponent(item.path)
            let to = destination.appendingPathComponent(item.path)
            if item.isDirectory {
                try fm.createDirectory(at: to, withIntermediateDirectories: true)
                continue
            }
            let group = groups[item.path]
            do {
                if let group, let first = firstCopy[group], (try? fm.linkItem(at: first, to: to)) != nil {
                    links += 1
                } else {
                    // A drive that can't hard-link (exFAT, FAT) gets a separate copy instead.
                    try fm.copyItem(at: from, to: to)
                    copied += item.size
                    if let group, firstCopy[group] == nil { firstCopy[group] = to }
                }
            } catch {
                throw ProfileError.copyFailed(item.path, reason: error.localizedDescription)
            }
            let written = (try? fm.attributesOfItem(atPath: to.path)[.size] as? NSNumber)?.int64Value
            guard written == item.size else { throw ProfileError.copyMismatch(item.path) }
            files += 1
            let percent = total > 0 ? min(100, Int(copied * 100 / total)) : 100
            if percent != reported {
                reported = percent
                progress("\(label)… \(percent)% (\(Disk.format(copied)) / \(Disk.format(total)))")
            }
        }
        return (files, copied, links)
    }

    /// Removes snapshots and unfinished restores left behind by a crash more than 12 hours ago.
    /// A leftover snapshot would slowly take more space as Zalo changes the original files.
    func removeStaleTemporaryFolders() {
        let names = (try? fm.contentsOfDirectory(atPath: layout.profilesRoot.path)) ?? []
        let cutoff = Int(Date().timeIntervalSince1970) - 12 * 3600
        for name in names {
            guard let prefix = [Self.snapshotPrefix, Self.restorePrefix].first(where: { name.hasPrefix($0) }),
                  let stamp = Int(name.dropFirst(prefix.count).prefix { $0 != "-" }),
                  stamp < cutoff else { continue }
            try? fm.removeItem(at: layout.profilesRoot.appendingPathComponent(name))
        }
    }

    static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()
}
