import AppKit
import ZaloProfilesCore

// The model only touches the manager on its serial queues: `work` for anything that moves or
// opens profiles, `copying` for the long backup and restore copies, which never move profiles.
extension ProfileManager: @unchecked Sendable {}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statuses: [ProfileStatus] = []
    @Published private(set) var mainSlot: MainSlot = .empty
    @Published private(set) var mainRunning = false
    @Published private(set) var busy: String?
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var freeSpace: Int64?
    @Published private(set) var lowSpace = false
    @Published private(set) var copying: String?
    @Published private(set) var copyProgress: Double?
    @Published var showingSettings = false

    let isDemo: Bool
    let manager: ProfileManager
    private let work = DispatchQueue(label: "zalo-switcher.work")
    private let copyQueue = DispatchQueue(label: "zalo-switcher.copy")
    private let sizeQueue = DispatchQueue(label: "zalo-switcher.sizes")
    private var copyCancel: CancelFlag?
    private var timers: [Timer] = []

    init(manager: ProfileManager, isDemo: Bool) {
        self.manager = manager
        self.isDemo = isDemo
    }

    /// Starts keeping the state up to date: every 3 seconds, and sizes every 10 minutes.
    func start() {
        refresh()
        refreshSizes()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
            Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshSizes() }
            },
        ]
    }

    func setLowSpaceThreshold(gigabytes: Int) {
        work.async { [manager] in manager.lowSpaceThreshold = Int64(gigabytes) * 1_000_000_000 }
        refresh()
    }

    /// The name of the account the normal Zalo app opens.
    var mainName: String? {
        guard case .profile(let id) = mainSlot else { return nil }
        return statuses.first { $0.profile.id == id }?.profile.name
    }

    /// How many Zalo windows are open, counting a normal Zalo holding an unsaved account.
    var openCount: Int {
        statuses.filter(\.isOpen).count + (mainSlot == .unsaved && mainRunning ? 1 : 0)
    }

    /// Saved accounts that have been logged in and aren't open.
    var closedCount: Int {
        statuses.filter { !$0.isOpen && $0.place != .new }.count
    }

    var headline: String {
        if statuses.isEmpty { return "Chưa có tài khoản nào" }
        return "\(openCount) trong \(statuses.count) tài khoản đang mở"
    }

    var subheadline: String {
        freeSpace.map { "Ổ đĩa còn trống \(Disk.format($0))" } ?? ""
    }

    func refresh() {
        work.async { [manager] in
            let snapshot = Self.read(manager)
            Task { @MainActor in self.apply(snapshot) }
        }
    }

    /// Reads everything at once and waits for it; used before drawing screenshots.
    func refreshNow() {
        let snapshot = work.sync { Self.read(manager) }
        apply(snapshot)
        sizes = sizeQueue.sync { Self.readSizes(manager) }
    }

    /// Measuring takes about a second per 10 GB, so it runs every 10 minutes and after changes.
    func refreshSizes() {
        sizeQueue.async { [manager] in
            let sizes = Self.readSizes(manager)
            Task { @MainActor in self.sizes = sizes }
        }
    }

    private struct Snapshot {
        var statuses: [ProfileStatus]
        var slot: MainSlot
        var running: Bool
        var free: Int64?
        var low: Bool
    }

    private nonisolated static func read(_ manager: ProfileManager) -> Snapshot {
        Snapshot(statuses: manager.statuses(), slot: manager.mainSlot(), running: manager.mainZaloPID() != nil,
                 free: manager.freeSpace(), low: manager.lowSpaceWarning() != nil)
    }

    private nonisolated static func readSizes(_ manager: ProfileManager) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for status in manager.statuses() {
            sizes[status.profile.id] = manager.dataSize(of: status)
        }
        return sizes
    }

    private func apply(_ snapshot: Snapshot) {
        statuses = snapshot.statuses
        mainSlot = snapshot.slot
        mainRunning = snapshot.running
        freeSpace = snapshot.free
        lowSpace = snapshot.low
    }

    // MARK: - Actions

    /// Opens the account in a Zalo window of its own, or brings its window forward.
    func open(_ status: ProfileStatus) {
        guard status.isOpen || confirmDespiteLowSpace() else { return }
        perform(status.isOpen ? nil : "Đang mở \(status.profile.name)…") { manager, _ in
            try manager.open(status.profile.id)
        }
    }

    func close(_ status: ProfileStatus) {
        perform("Đang đóng \(status.profile.name)…") { manager, _ in
            try manager.close(status.profile.id)
        }
    }

    /// Opens every account that has been logged in. At login it doesn't ask about low space: it
    /// opens the accounts the person uses anyway.
    func openAll(asking: Bool = true) {
        guard !asking || confirmDespiteLowSpace() else { return }
        perform("Đang mở các tài khoản…") { manager, progress in
            try manager.openAll(progress: progress)
        }
    }

    func closeAll() {
        guard Prompt.confirm(
            title: "Đóng mọi cửa sổ Zalo?",
            message: "Mọi tài khoản đang mở sẽ thoát như khi bấm ⌘Q. Tin nhắn mới sẽ về khi bạn mở lại.",
            button: "Đóng tất cả"
        ) else { return }
        perform("Đang đóng các tài khoản…") { manager, progress in
            try manager.closeAll(progress: progress)
        }
    }

    /// Adds an account and opens it in a new Zalo window at the login screen; the others keep running.
    func addAccount() {
        guard confirmDespiteLowSpace() else { return }
        guard let name = Prompt.text(
            title: "Thêm tài khoản Zalo",
            message: "Đặt tên cho tài khoản mới. Một cửa sổ Zalo mới sẽ mở ở màn hình đăng nhập, còn các tài khoản đang mở vẫn chạy bình thường. Bạn chỉ cần đăng nhập một lần; sau này mở lại không cần đăng nhập nữa.",
            placeholder: "Ví dụ: Cửa hàng"
        ) else { return }
        perform("Đang thêm \(name)…") { manager, _ in
            let profile = try manager.addProfile(named: name)
            try manager.open(profile.id)
        }
    }

    /// Makes the account the one the normal Zalo app opens, from the Dock, Launchpad or at login.
    func makeMain(_ status: ProfileStatus) {
        guard ensureMainIsSaved() else { return }
        let current = mainName.map { "“\($0)”" } ?? "tài khoản Zalo chính hiện tại"
        guard Prompt.confirm(
            title: "Đặt “\(status.profile.name)” làm Zalo chính?",
            message: "Zalo chính là tài khoản mở ra khi bạn bấm biểu tượng Zalo trong Dock, Launchpad hoặc khi Zalo tự mở cùng máy Mac. Cửa sổ của “\(status.profile.name)” và của \(current) sẽ đóng vài giây để đổi chỗ thư mục dữ liệu, rồi tự mở lại. Các cửa sổ khác vẫn chạy.",
            button: "Đặt làm Zalo chính"
        ) else { return }
        perform("Đang đặt \(status.profile.name) làm Zalo chính…") { manager, progress in
            try manager.makeMain(status.profile.id, progress: progress)
        }
    }

    func saveCurrent() {
        _ = ensureMainIsSaved(asking: false)
    }

    func rename(_ status: ProfileStatus) {
        guard let name = Prompt.text(title: "Đổi tên “\(status.profile.name)”", message: "Tên mới:",
                                     placeholder: status.profile.name, initial: status.profile.name)
        else { return }
        perform(nil) { manager, _ in try manager.rename(status.profile.id, to: name) }
    }

    func remove(_ status: ProfileStatus) {
        guard Prompt.confirm(
            title: "Xóa “\(status.profile.name)” khỏi máy?",
            message: "Tài khoản này cùng tin nhắn, ảnh và tệp Zalo của nó trên máy Mac sẽ được chuyển vào Thùng rác. Bạn vẫn lấy lại được từ Thùng rác cho đến khi dọn sạch Thùng rác. Bản thân tài khoản Zalo và tin nhắn trên máy chủ của Zalo không bị ảnh hưởng.",
            button: "Chuyển vào Thùng rác"
        ) else { return }
        perform(nil) { manager, _ in try manager.remove(status.profile.id) }
    }

    func backUp(_ status: ProfileStatus) {
        guard copying == nil, let destination = Prompt.chooseFolder(
            message: "Chọn nơi lưu bản sao lưu của “\(status.profile.name)”, ví dụ một ổ cứng ngoài. Bản sao lưu sẽ nằm trong thư mục “Zalo Backups” ở đó.",
            button: "Sao lưu vào đây",
            start: UserDefaults.standard.url(forKey: "lastBackupFolder") ?? URL(fileURLWithPath: "/Volumes")
        ) else { return }
        UserDefaults.standard.set(destination, forKey: "lastBackupFolder")
        if manager.isOnThisMacsDisk(destination) && !isDemo {
            guard Prompt.confirm(
                title: "Sao lưu vào ổ đĩa của chính máy Mac này?",
                message: "\(destination.path) nằm trên cùng ổ đĩa với Zalo. Bản sao lưu sẽ dùng dung lượng trống của ổ và sẽ mất nếu ổ đĩa hỏng. Ổ cứng ngoài an toàn hơn.",
                button: "Vẫn sao lưu"
            ) else { return }
        }
        if status.runningPID != nil {
            guard Prompt.confirm(
                title: "Sao lưu “\(status.profile.name)”?",
                message: "Cửa sổ Zalo của “\(status.profile.name)” sẽ tạm đóng vài giây để chụp nhanh dữ liệu, rồi tự mở lại; các tài khoản khác vẫn chạy. Việc sao chép sang ổ đĩa chạy ngầm sau đó, trong lúc đó bạn vẫn dùng Zalo bình thường.",
                button: "Sao lưu"
            ) else { return }
        }

        let cancel = CancelFlag()
        busy = "Đang chuẩn bị sao lưu \(status.profile.name)…"
        work.async { [manager] in
            let progress = Self.progressSink { self.busy = $0 }
            let snapshot: BackupSnapshot
            do {
                try manager.checkBackupDestination(status.profile.id, destination: destination)
                snapshot = try manager.takeSnapshot(status.profile.id, progress: progress)
            } catch {
                Task { @MainActor in
                    self.busy = nil
                    self.refresh()
                    Prompt.error(error)
                }
                return
            }
            Task { @MainActor in
                self.busy = nil
                self.refresh()
                self.startCopy("Đang sao lưu \(status.profile.name)…", cancel: cancel) { manager, progress in
                    defer { manager.discard(snapshot) }
                    let folder = try manager.writeBackup(snapshot, to: destination, progress: progress, cancel: cancel)
                    let info = try manager.readBackup(folder)
                    return "Đã sao lưu “\(status.profile.name)”: \(info.files) tệp, \(Disk.format(info.bytes)) dữ liệu, đã kiểm tra từng tệp.\n\nLưu tại \(folder.path)"
                }
            }
        }
    }

    func restore() {
        guard copying == nil, let folder = Prompt.chooseFolder(
            message: "Chọn một bản sao lưu: một thư mục bên trong “Zalo Backups” trên ổ sao lưu của bạn.",
            button: "Khôi phục",
            start: UserDefaults.standard.url(forKey: "lastBackupFolder")
                .map { $0.appendingPathComponent(ProfileManager.backupsFolderName) } ?? URL(fileURLWithPath: "/Volumes")
        ) else { return }
        let info: BackupInfo
        do { info = try manager.readBackup(folder) } catch { Prompt.error(error); return }
        let date = info.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Self.vietnamese))
        guard let name = Prompt.text(
            title: "Khôi phục “\(info.profileName)” (\(date))",
            message: "Bản sao lưu sẽ được khôi phục thành một tài khoản mới (\(Disk.format(info.bytes))); không tài khoản nào bị thay thế. Nếu tài khoản gốc vẫn còn trong danh sách, ứng dụng sẽ không cho mở cả hai cùng lúc.\n\nTên cho tài khoản khôi phục:",
            placeholder: "\(info.profileName) (khôi phục)", initial: "\(info.profileName) (khôi phục)"
        ) else { return }
        let cancel = CancelFlag()
        startCopy("Đang khôi phục \(name)…", cancel: cancel) { manager, progress in
            let profile = try manager.restore(from: folder, as: name, progress: progress, cancel: cancel)
            return "Đã khôi phục thành “\(profile.name)”. Bấm “Mở” để dùng tài khoản này."
        }
    }

    func cancelCopy() {
        copyCancel?.cancel()
        copying = "Đang dừng…"
    }

    func showProfilesFolder() {
        let url = manager.layout.profilesRoot
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showZaloDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([manager.layout.liveData])
    }

    /// Shows a state for the screenshots without running anything.
    func showDemoProgress(_ label: String, fraction: Double) {
        copying = label
        copyProgress = fraction
    }

    static let vietnamese = Locale(identifier: "vi_VN")

    // MARK: - Helpers

    /// When the normal Zalo holds an account that isn't saved yet, asks for a name and saves it, so
    /// it is kept when another account moves into the main slot. Returns false if the person cancels
    /// or saving fails.
    private func ensureMainIsSaved(asking: Bool = true) -> Bool {
        guard mainSlot == .unsaved else { return true }
        let message = asking
            ? "Zalo chính đang giữ một tài khoản chưa được lưu. Hãy đặt tên cho nó, để tin nhắn và tệp của nó được giữ lại."
            : "Đặt tên cho tài khoản đang có trong Zalo chính. Zalo vẫn chạy bình thường."
        guard let name = Prompt.text(title: "Lưu tài khoản trong Zalo chính", message: message,
                                     placeholder: "Ví dụ: Cá nhân")
        else { return false }
        do {
            try manager.saveCurrent(as: name)
            refresh()
            return true
        } catch {
            Prompt.error(error)
            return false
        }
    }

    /// Asks before adding or opening an account while the disk is nearly full.
    private func confirmDespiteLowSpace() -> Bool {
        guard let warning = manager.lowSpaceWarning() else { return true }
        return Prompt.confirm(title: "Ổ đĩa sắp đầy", message: warning, button: "Vẫn tiếp tục")
    }

    private func perform(_ label: String?,
                         _ action: @escaping (ProfileManager, @escaping (String) -> Void) throws -> Void) {
        guard busy == nil else { return }
        busy = label ?? "Đang xử lý…"
        work.async { [manager] in
            let progress = Self.progressSink { self.busy = $0 }
            var failure: Error?
            do { try action(manager, progress) } catch { failure = error }
            Task { @MainActor in
                self.busy = nil
                self.refresh()
                self.refreshSizes()
                if let failure { Prompt.error(failure) }
            }
        }
    }

    /// Runs a long copy (backup or restore) in the background; opening and closing stay available meanwhile.
    private func startCopy(_ label: String, cancel: CancelFlag,
                           _ action: @escaping (ProfileManager, @escaping (String) -> Void) throws -> String) {
        copying = label
        copyProgress = 0
        copyCancel = cancel
        copyQueue.async { [manager] in
            let progress = Self.progressSink { message in
                self.copying = message
                if let percent = message.firstMatch(of: #/(\d+)%/#)?.1, let value = Double(percent) {
                    self.copyProgress = value / 100
                }
            }
            let result = Result { try action(manager, progress) }
            Task { @MainActor in
                self.copying = nil
                self.copyProgress = nil
                self.copyCancel = nil
                self.refresh()
                self.refreshSizes()
                switch result {
                case .success(let message): Prompt.info(title: "Zalo Switcher", message: message)
                case .failure(let error): Prompt.error(error)
                }
            }
        }
    }

    private nonisolated static func progressSink(_ update: @escaping @MainActor (String) -> Void) -> (String) -> Void {
        { message in Task { @MainActor in update(message) } }
    }
}
