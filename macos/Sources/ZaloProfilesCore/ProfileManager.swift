import Foundation

public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var lastUsedAt: Date?
}

/// What the main `ZaloData` folder holds.
public enum MainSlot: Equatable, Sendable {
    /// There is no `ZaloData` folder; Zalo will start at the login screen.
    case empty
    /// It holds this profile's data.
    case profile(String)
    /// It holds data that isn't saved as a profile yet.
    case unsaved
}

/// Where a profile's data is.
public enum Place: Equatable, Sendable {
    /// In the main `ZaloData` folder, used by the normal Zalo app.
    case main
    /// In its own profile folder.
    case parked
    /// Nowhere yet: the profile has never been opened.
    case new
}

public struct ProfileStatus: Equatable, Sendable {
    public var profile: Profile
    public var place: Place
    /// The Zalo instance that has this profile's data open, if any.
    public var runningPID: pid_t?
    /// The Zalo account id used most recently in this profile's data.
    public var zaloUserID: String?
    /// Where its data is now, if it has any.
    public var dataFolder: URL?

    public var isOpenSideBySide: Bool { place != .main && runningPID != nil }
}

struct State: Codable {
    var main: String?
}

/// Saves, switches and opens Zalo profiles. Every change is a folder rename on the same disk:
/// nothing is copied, and nothing is deleted except by moving a whole profile to the Trash.
public final class ProfileManager {
    public let layout: Layout
    public var quitTimeout: TimeInterval = 60
    /// Below this much free space on the Mac's disk, Zalo risks failing to save messages.
    public var lowSpaceThreshold: Int64 = 5_000_000_000
    /// How removed profiles leave; tests replace it so they don't fill the real Trash.
    public var moveToTrash: (URL) throws -> URL? = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
    /// Free space on the disk holding a path; tests replace it to fake a full disk.
    public var freeSpaceProvider: (URL) -> Int64? = Disk.freeBytes(at:)
    /// The space a data folder takes; the demo replaces it to show realistic sizes.
    public var sizeProvider: (URL) -> Int64? = Disk.allocatedSize(of:)

    let zalo: ZaloControl
    let fm = FileManager.default
    static let markerName = ".zalo-profile-id"

    public init(layout: Layout = .system(), zalo: ZaloControl = SystemZaloControl()) {
        self.layout = layout
        self.zalo = zalo
    }

    // MARK: - Reading

    public func profiles() -> [Profile] {
        let ids = (try? fm.contentsOfDirectory(atPath: layout.profilesRoot.path)) ?? []
        return ids.compactMap(loadProfile)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func mainSlot() -> MainSlot {
        guard isDirectory(layout.liveData) else { return .empty }
        if let id = readMarker(in: layout.liveData), loadProfile(id) != nil { return .profile(id) }
        // Zalo may have removed the marker (for example after a log out); fall back to the last switch.
        if let id = loadState().main, loadProfile(id) != nil, !exists(layout.parkedData(id)) {
            return .profile(id)
        }
        return .unsaved
    }

    public func statuses() -> [ProfileStatus] {
        let main = mainSlot()
        return profiles().map { profile in
            let place: Place
            let data: URL?
            if main == .profile(profile.id) {
                (place, data) = (.main, layout.liveData)
            } else if isDirectory(layout.parkedData(profile.id)) {
                (place, data) = (.parked, layout.parkedData(profile.id))
            } else {
                (place, data) = (.new, nil)
            }
            return ProfileStatus(profile: profile, place: place,
                                 runningPID: data.flatMap { zalo.pidUsing(dataFolder: $0) },
                                 zaloUserID: data.flatMap(zaloUserID(in:)),
                                 dataFolder: data)
        }
    }

    /// Free space on the Mac's disk, where Zalo and the profiles live.
    public func freeSpace() -> Int64? {
        freeSpaceProvider(layout.applicationSupport)
    }

    /// A warning when the Mac's disk is nearly full, otherwise nil.
    public func lowSpaceWarning() -> String? {
        guard let free = freeSpace(), free < lowSpaceThreshold else { return nil }
        return "Máy Mac chỉ còn trống \(Disk.format(free)). Zalo cần chỗ để lưu tin nhắn và ảnh; hãy giải phóng dung lượng trước khi thêm hoặc mở thêm tài khoản."
    }

    /// The space a profile's data takes on disk (nil for a profile that has never been opened).
    public func dataSize(of status: ProfileStatus) -> Int64? {
        status.dataFolder.flatMap(sizeProvider)
    }

    public func status(of id: String) -> ProfileStatus? {
        statuses().first { $0.profile.id == id }
    }

    /// The pid of the normal Zalo app (the one using the main `ZaloData` folder), if it is running.
    public func mainZaloPID() -> pid_t? {
        zalo.pidUsing(dataFolder: layout.liveData)
    }

    /// The Zalo account id used most recently in the main `ZaloData` folder.
    public func mainZaloUserID() -> String? {
        zaloUserID(in: layout.liveData)
    }

    /// Finds a profile by id, or by name ignoring case and accents.
    public func find(_ query: String) throws -> Profile {
        let all = profiles()
        if let exact = all.first(where: { $0.id == query }) { return exact }
        let matches = all.filter { sameName($0.name, query) }
        guard let first = matches.first else { throw ProfileError.notFound(query) }
        guard matches.count == 1 else { throw ProfileError.ambiguous(query) }
        return first
    }

    // MARK: - Changing

    /// Saves the account that is in Zalo now as a profile. Zalo keeps running.
    @discardableResult
    public func saveCurrent(as name: String) throws -> Profile {
        switch mainSlot() {
        case .empty: throw ProfileError.nothingToSave
        case .profile(let id): throw ProfileError.alreadySaved(loadProfile(id)?.name ?? id)
        case .unsaved: break
        }
        let profile = try createProfile(named: name)
        try? writeMarker(profile.id, in: layout.liveData)
        try saveState(State(main: profile.id))
        return profile
    }

    /// Adds an empty profile. The first time it is opened, Zalo starts at the login screen.
    @discardableResult
    public func addProfile(named name: String) throws -> Profile {
        try createProfile(named: name)
    }

    public func rename(_ id: String, to name: String) throws {
        guard var profile = loadProfile(id) else { throw ProfileError.notFound(id) }
        profile.name = try validName(name, ignoring: id)
        try saveProfile(profile)
    }

    /// Moves a profile and its Zalo data to the Trash, where it can still be put back.
    @discardableResult
    public func remove(_ id: String) throws -> URL? {
        guard let status = status(of: id) else { throw ProfileError.notFound(id) }
        if status.place == .main { throw ProfileError.isInMainZalo(status.profile.name) }
        if status.runningPID != nil { throw ProfileError.openSideBySide(status.profile.name) }
        return try moveToTrash(layout.profileHome(id))
    }

    /// Makes `id` the profile of the normal Zalo app: quits Zalo, moves the current profile's data
    /// into its profile folder, moves `id`'s data into `ZaloData`, and starts Zalo again.
    public func switchTo(_ id: String, launch: Bool = true, progress: (String) -> Void = { _ in }) throws {
        guard let target = loadProfile(id) else { throw ProfileError.notFound(id) }
        if launch { try requireZaloInstalled() }
        let slot = mainSlot()

        if slot == .profile(id) {
            if launch {
                if let pid = mainZaloPID() { zalo.activate(pid: pid) } else { try zalo.launchMain(app: layout.zaloApp) }
            }
            return
        }
        if slot == .unsaved { throw ProfileError.currentDataNotSaved }
        if zalo.pidUsing(dataFolder: layout.parkedData(id)) != nil { throw ProfileError.openSideBySide(target.name) }

        if mainZaloPID() != nil {
            progress("Đang thoát Zalo…")
            try zalo.quit(dataFolder: layout.liveData, timeout: quitTimeout)
            if mainZaloPID() != nil { throw ProfileError.zaloDidNotQuit }
        }

        var parked: String?
        if case .profile(let current) = slot {
            progress("Đang cất dữ liệu của \(loadProfile(current)?.name ?? current)…")
            let destination = layout.parkedData(current)
            if exists(destination) {
                throw ProfileError.conflict("\(destination.path) đã tồn tại, nên \(layout.liveData.path) được giữ nguyên.")
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try move(layout.liveData, to: destination)
            parked = current
        }

        progress("Đang đưa \(target.name) vào Zalo…")
        let source = layout.parkedData(id)
        if isDirectory(source) {
            do {
                try move(source, to: layout.liveData)
            } catch {
                // Put the previous profile back, so Zalo opens as it was.
                if let parked { try? move(layout.parkedData(parked), to: layout.liveData) }
                throw error
            }
        } else {
            // A new profile: an empty folder makes Zalo start at the login screen.
            try? fm.createDirectory(at: layout.liveData, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        }
        try? writeMarker(id, in: layout.liveData)
        try saveState(State(main: id))
        touch(target)

        if launch {
            progress("Đang mở Zalo…")
            try zalo.launchMain(app: layout.zaloApp)
        }
    }

    /// Opens a profile in a separate Zalo window, next to the normal one. Experimental: Zalo's call
    /// helper uses fixed socket paths, so calls only work reliably in one window at a time.
    public func openSideBySide(_ id: String) throws {
        guard let status = status(of: id) else { throw ProfileError.notFound(id) }
        try requireZaloInstalled()
        if let pid = status.runningPID {
            zalo.activate(pid: pid)
            return
        }
        if status.place == .main {
            try zalo.launchMain(app: layout.zaloApp)
            return
        }
        try prepareHome(id)
        try zalo.launchIsolated(app: layout.zaloApp, home: layout.profileHome(id))
        touch(status.profile)
    }

    /// Quits the Zalo window that has this profile open, like ⌘Q in that window.
    public func close(_ id: String) throws {
        guard let status = status(of: id) else { throw ProfileError.notFound(id) }
        guard let data = status.dataFolder, status.runningPID != nil else { return }
        try zalo.quit(dataFolder: data, timeout: quitTimeout)
    }

    /// Starts the normal Zalo app, or brings it forward.
    public func openMain() throws {
        try requireZaloInstalled()
        if let pid = mainZaloPID() { zalo.activate(pid: pid) } else { try zalo.launchMain(app: layout.zaloApp) }
    }

    // MARK: - Helpers

    /// Gets a profile folder ready to be used as a home folder by a side-by-side Zalo.
    func prepareHome(_ id: String) throws {
        let data = layout.parkedData(id)
        if !exists(data) {
            try fm.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? writeMarker(id, in: data)
        }
        // Share the keychain (Zalo keeps its encryption key there) and the usual user folders.
        let home = layout.profileHome(id)
        for path in ["Library/Keychains", "Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"] {
            let link = home.appendingPathComponent(path)
            let target = layout.realHome.appendingPathComponent(path)
            guard exists(target), !existsOrLink(link) else { continue }
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
        }
    }

    func createProfile(named name: String) throws -> Profile {
        let clean = try validName(name, ignoring: nil)
        let id = uniqueID(for: clean)
        try fm.createDirectory(at: layout.profileHome(id), withIntermediateDirectories: true)
        let profile = Profile(id: id, name: clean, createdAt: Date(), lastUsedAt: nil)
        try saveProfile(profile)
        return profile
    }

    func validName(_ name: String, ignoring id: String?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ProfileError.emptyName }
        if profiles().contains(where: { $0.id != id && sameName($0.name, clean) }) {
            throw ProfileError.nameTaken(clean)
        }
        return clean
    }

    func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// A folder name made from the profile name, for example "Đức – Work" → "duc-work".
    func uniqueID(for name: String) -> String {
        let folded = name.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let slug = folded.unicodeScalars
            .map { ("a"..."z").contains($0) || ("0"..."9").contains($0) ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        let base = slug.isEmpty ? "profile" : slug
        var id = base
        var n = 2
        while existsOrLink(layout.profileHome(id)) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    func zaloUserID(in data: URL) -> String? {
        let db = data.appendingPathComponent("Database/_production", isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: db, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return items
            .filter { $0.lastPathComponent.count >= 6 && $0.lastPathComponent.allSatisfy(\.isNumber) }
            .max { modified($0) < modified($1) }?
            .lastPathComponent
    }

    func requireZaloInstalled() throws {
        guard exists(layout.zaloApp) else { throw ProfileError.zaloNotInstalled(layout.zaloApp.path) }
    }

    /// Renames a folder. Refuses to replace anything at the destination, and refuses to copy across
    /// disks (rename(2) fails instead), so a half-finished move can't happen.
    func move(_ from: URL, to: URL) throws {
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else {
            let reason = errno == EEXIST ? "đã có thư mục khác ở đó" : String(cString: strerror(errno))
            throw ProfileError.moveFailed(from: from.path, to: to.path, reason: reason)
        }
    }

    func touch(_ profile: Profile) {
        var updated = profile
        updated.lastUsedAt = Date()
        try? saveProfile(updated)
    }

    func loadProfile(_ id: String) -> Profile? {
        guard let data = try? Data(contentsOf: layout.profileFile(id)) else { return nil }
        return try? Self.decoder.decode(Profile.self, from: data)
    }

    func saveProfile(_ profile: Profile) throws {
        try Self.encoder.encode(profile).write(to: layout.profileFile(profile.id), options: .atomic)
    }

    func loadState() -> State {
        guard let data = try? Data(contentsOf: layout.stateFile),
              let state = try? Self.decoder.decode(State.self, from: data) else { return State() }
        return state
    }

    func saveState(_ state: State) throws {
        try fm.createDirectory(at: layout.profilesRoot, withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: layout.stateFile, options: .atomic)
    }

    func readMarker(in data: URL) -> String? {
        guard let text = try? String(contentsOf: data.appendingPathComponent(Self.markerName), encoding: .utf8)
        else { return nil }
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    func writeMarker(_ id: String, in data: URL) throws {
        try Data((id + "\n").utf8).write(to: data.appendingPathComponent(Self.markerName), options: .atomic)
    }

    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    func existsOrLink(_ url: URL) -> Bool {
        exists(url) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
