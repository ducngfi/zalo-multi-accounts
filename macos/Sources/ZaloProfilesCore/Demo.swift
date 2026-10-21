import Foundation

/// A pretend Zalo for the demo: it remembers which data folders are "open" and starts nothing.
public final class DemoZaloControl: ZaloControl, @unchecked Sendable {
    private let lock = NSLock()
    private var open: [String: pid_t] = [:]
    private var nextPID: pid_t = 40_001
    private let liveData: URL

    public init(layout: Layout) {
        liveData = layout.liveData
    }

    public func pidUsing(dataFolder: URL) -> pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return open[dataFolder.path]
    }

    public func anyInstanceRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !open.isEmpty
    }

    public func quit(dataFolder: URL, timeout: TimeInterval) throws {
        Thread.sleep(forTimeInterval: 0.6)
        lock.lock()
        open[dataFolder.path] = nil
        lock.unlock()
    }

    public func launchMain(app: URL) throws {
        // Like Zalo, create the data folder when starting without one.
        try FileManager.default.createDirectory(at: liveData, withIntermediateDirectories: true)
        markOpen(liveData)
    }

    public func launchIsolated(app: URL, home: URL) throws {
        markOpen(home.appendingPathComponent("Library/Application Support/ZaloData", isDirectory: true))
    }

    public func activate(pid: pid_t) {}

    private func markOpen(_ folder: URL) {
        lock.lock()
        open[folder.path] = nextPID
        nextPID += 1
        lock.unlock()
    }
}

/// Synthetic accounts for the demo and the README screenshots. Nothing here touches the real
/// Zalo or its data: everything lives in a temporary folder, and Zalo is never started.
public enum Demo {
    struct Account {
        var name: String
        var zaloUserID: String?
        var size: Int64
    }

    static let accounts = [
        Account(name: "Cá nhân", zaloUserID: "8401927365510293847", size: 8_420_000_000),
        Account(name: "Cửa hàng Hoa Mai", zaloUserID: "7310528846192037465", size: 2_150_000_000),
        Account(name: "Công ty An Phát", zaloUserID: "5528103746629104837", size: 640_000_000),
        Account(name: "Shop mới", zaloUserID: nil, size: 0),
    ]

    /// Where the demo keeps its pretend Mac home folder.
    public static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ZaloSwitcherDemo", isDirectory: true)
    }

    /// Builds a fresh pretend home with four synthetic accounts and returns a manager working on it:
    /// "Cá nhân" in the main Zalo, "Cửa hàng Hoa Mai" open side by side, "Công ty An Phát" saved,
    /// and "Shop mới" not logged in yet.
    public static func makeManager(freeSpace: Int64 = 42_700_000_000) throws -> ProfileManager {
        let fm = FileManager.default
        let root = Self.root
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Zalo.app", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)

        let layout = Layout(realHome: home, zaloApp: app)
        let zalo = DemoZaloControl(layout: layout)
        let manager = ProfileManager(layout: layout, zalo: zalo)
        manager.freeSpaceProvider = { _ in freeSpace }
        let sizes = Dictionary(uniqueKeysWithValues: accounts.compactMap { a in a.zaloUserID.map { ($0, a.size) } })
        manager.sizeProvider = { [unowned manager] folder in
            manager.zaloUserID(in: folder).flatMap { sizes[$0] } ?? 48_000_000
        }

        // "Cá nhân": logged in and running in the main Zalo.
        try writeData(for: accounts[0], in: layout.liveData)
        try zalo.launchMain(app: app)
        try manager.saveCurrent(as: accounts[0].name)

        // "Cửa hàng Hoa Mai" and "Công ty An Phát": saved, with their own data.
        var ids: [String] = []
        for account in accounts[1...2] {
            let profile = try manager.addProfile(named: account.name)
            try writeData(for: account, in: layout.parkedData(profile.id))
            try manager.writeMarker(profile.id, in: layout.parkedData(profile.id))
            ids.append(profile.id)
        }
        try manager.openSideBySide(ids[0])
        if var company = manager.loadProfile(ids[1]) {
            company.lastUsedAt = Date().addingTimeInterval(-3 * 86_400)
            try manager.saveProfile(company)
        }

        // "Shop mới": added, never logged in.
        try manager.addProfile(named: accounts[3].name)

        // Removing a profile in the demo moves it into the demo folder, not the real Trash.
        manager.moveToTrash = { url in
            let trash = root.appendingPathComponent("Trash", isDirectory: true)
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            let destination = trash.appendingPathComponent("\(url.lastPathComponent)-\(UUID().uuidString)")
            try fm.moveItem(at: url, to: destination)
            return destination
        }
        return manager
    }

    private static func writeData(for account: Account, in folder: URL) throws {
        let fm = FileManager.default
        guard let uid = account.zaloUserID else { return }
        let db = folder.appendingPathComponent("Database/_production/\(uid)", isDirectory: true)
        let media = folder.appendingPathComponent("media/\(uid)", isDirectory: true)
        try fm.createDirectory(at: db, withIntermediateDirectories: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("Dữ liệu giả lập của \(account.name)\n".utf8).write(to: db.appendingPathComponent("Message.db"))
        try Data(repeating: 0x5A, count: 64_000).write(to: media.appendingPathComponent("anh-gia-lap.jpg"))
        try Data("phiên đăng nhập giả lập\n".utf8).write(to: folder.appendingPathComponent("Cookies"))
    }
}
