import AppKit
import ServiceManagement
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

    private let manager = ProfileManager()
    private let work = DispatchQueue(label: "zalo-switcher.work")
    private let copyQueue = DispatchQueue(label: "zalo-switcher.copy")
    private let sizeQueue = DispatchQueue(label: "zalo-switcher.sizes")
    private var copyCancel: CancelFlag?
    private var timer: Timer?
    private var sizeTimer: Timer?

    init() {
        refresh()
        refreshSizes()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        sizeTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSizes() }
        }
    }

    var currentName: String? {
        guard case .profile(let id) = mainSlot else { return nil }
        return statuses.first { $0.profile.id == id }?.profile.name
    }

    var headline: String {
        switch mainSlot {
        case .empty: return "Zalo: no account yet"
        case .unsaved: return "Zalo: current account not saved yet"
        case .profile: return "Zalo: \(currentName ?? "?")" + (mainRunning ? "" : " (not running)")
        }
    }

    var diskLine: String? {
        guard let freeSpace else { return nil }
        return lowSpace
            ? "⚠︎ Low disk space: \(Disk.format(freeSpace)) free"
            : "Disk: \(Disk.format(freeSpace)) free"
    }

    func refresh() {
        work.async { [manager] in
            let statuses = manager.statuses()
            let slot = manager.mainSlot()
            let running = manager.mainZaloPID() != nil
            let free = manager.freeSpace()
            let low = manager.lowSpaceWarning() != nil
            Task { @MainActor in
                self.statuses = statuses
                self.mainSlot = slot
                self.mainRunning = running
                self.freeSpace = free
                self.lowSpace = low
            }
        }
    }

    /// Measuring takes about a second per 10 GB, so it runs every 10 minutes and after changes.
    func refreshSizes() {
        sizeQueue.async { [manager] in
            var sizes: [String: Int64] = [:]
            for status in manager.statuses() {
                sizes[status.profile.id] = manager.dataSize(of: status)
            }
            Task { @MainActor in self.sizes = sizes }
        }
    }

    // MARK: - Actions

    func switchTo(_ status: ProfileStatus) {
        guard ensureCurrentIsSaved() else { return }
        perform("Switching to \(status.profile.name)…") { manager, progress in
            try manager.switchTo(status.profile.id, progress: progress)
        }
    }

    func openSideBySide(_ status: ProfileStatus) {
        guard status.isOpenSideBySide || confirmDespiteLowSpace() else { return }
        perform("Opening \(status.profile.name)…") { manager, _ in
            try manager.openSideBySide(status.profile.id)
        }
    }

    func close(_ status: ProfileStatus) {
        perform("Closing \(status.profile.name)…") { manager, _ in
            try manager.close(status.profile.id)
        }
    }

    func addAccount() {
        guard ensureCurrentIsSaved(), confirmDespiteLowSpace() else { return }
        guard let name = Prompt.text(
            title: "Add a Zalo account",
            message: "Name the new profile. Zalo will restart at the login screen; log in once, and switching back later needs no login.",
            placeholder: "For example: Work"
        ) else { return }
        perform("Adding \(name)…") { manager, progress in
            let profile = try manager.addProfile(named: name)
            try manager.switchTo(profile.id, progress: progress)
        }
    }

    func addAccountSideBySide() {
        guard confirmDespiteLowSpace() else { return }
        guard let name = Prompt.text(
            title: "Add a Zalo account in a second window",
            message: "Name the new profile. A second Zalo window opens at the login screen, and the current one keeps running.\n\nExperimental: voice and video calls only work reliably in one Zalo window at a time.",
            placeholder: "For example: Shop"
        ) else { return }
        perform("Adding \(name)…") { manager, _ in
            let profile = try manager.addProfile(named: name)
            try manager.openSideBySide(profile.id)
        }
    }

    func saveCurrent() {
        _ = ensureCurrentIsSaved(asking: false)
    }

    func rename(_ status: ProfileStatus) {
        guard let name = Prompt.text(title: "Rename “\(status.profile.name)”", message: "New name:",
                                     placeholder: status.profile.name, initial: status.profile.name)
        else { return }
        perform(nil) { manager, _ in try manager.rename(status.profile.id, to: name) }
    }

    func remove(_ status: ProfileStatus) {
        guard Prompt.confirm(
            title: "Remove “\(status.profile.name)”?",
            message: "The profile and its Zalo messages, photos and files on this Mac move to the Trash. You can put the folder back from the Trash until you empty it. The account itself and its messages on Zalo's servers are not affected.",
            button: "Move to Trash"
        ) else { return }
        perform(nil) { manager, _ in try manager.remove(status.profile.id) }
    }

    func backUp(_ status: ProfileStatus) {
        guard copying == nil, let destination = Prompt.chooseFolder(
            message: "Choose where to save the backup of “\(status.profile.name)”, for example an external drive. It goes into a “Zalo Backups” folder there.",
            button: "Back Up Here",
            start: UserDefaults.standard.url(forKey: "lastBackupFolder") ?? URL(fileURLWithPath: "/Volumes")
        ) else { return }
        UserDefaults.standard.set(destination, forKey: "lastBackupFolder")
        if manager.isOnThisMacsDisk(destination) {
            guard Prompt.confirm(
                title: "Back up to this Mac's own disk?",
                message: "\(destination.path) is on the same disk as Zalo. The backup will use its free space and won't survive the disk failing. An external drive is safer.",
                button: "Back Up Anyway"
            ) else { return }
        }
        if status.runningPID != nil {
            guard Prompt.confirm(
                title: "Back up “\(status.profile.name)”?",
                message: "Zalo closes for a few seconds while a snapshot is taken, then opens again by itself. The copy to the drive continues in the background, and you can keep using Zalo meanwhile.",
                button: "Back Up"
            ) else { return }
        }

        let cancel = CancelFlag()
        busy = "Preparing backup of \(status.profile.name)…"
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
                self.startCopy("Backing up \(status.profile.name)…", cancel: cancel) { manager, progress in
                    defer { manager.discard(snapshot) }
                    let folder = try manager.writeBackup(snapshot, to: destination, progress: progress, cancel: cancel)
                    let info = try manager.readBackup(folder)
                    return "Backed up “\(status.profile.name)”: \(info.files) files, \(Disk.format(info.bytes)) of data, every file checked.\n\nSaved in \(folder.path)"
                }
            }
        }
    }

    func restore() {
        guard copying == nil, let folder = Prompt.chooseFolder(
            message: "Choose a backup: a folder inside “Zalo Backups” on your backup drive.",
            button: "Restore",
            start: UserDefaults.standard.url(forKey: "lastBackupFolder")
                .map { $0.appendingPathComponent(ProfileManager.backupsFolderName) } ?? URL(fileURLWithPath: "/Volumes")
        ) else { return }
        let info: BackupInfo
        do { info = try manager.readBackup(folder) } catch { Prompt.error(error); return }
        let date = info.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard let name = Prompt.text(
            title: "Restore “\(info.profileName)” from \(date)",
            message: "It's restored as a new profile (\(Disk.format(info.bytes))); no existing profile is replaced. If the same account is still in another profile, don't open both at the same time.\n\nName for the restored profile:",
            placeholder: "\(info.profileName) (restored)", initial: "\(info.profileName) (restored)"
        ) else { return }
        let cancel = CancelFlag()
        startCopy("Restoring \(name)…", cancel: cancel) { manager, progress in
            let profile = try manager.restore(from: folder, as: name, progress: progress, cancel: cancel)
            return "Restored as “\(profile.name)”. Click it in the menu to switch to it."
        }
    }

    func cancelCopy() {
        copyCancel?.cancel()
        copying = "Stopping…"
    }

    func openZalo() {
        perform(nil) { manager, _ in try manager.openMain() }
    }

    func showProfilesFolder() {
        let url = manager.layout.profilesRoot
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Prompt.error(error)
            }
            objectWillChange.send()
        }
    }

    // MARK: - Helpers

    /// When Zalo holds an account that isn't saved yet, asks for a name and saves it, so it is kept
    /// when switching. Returns false if the person cancels or saving fails.
    private func ensureCurrentIsSaved(asking: Bool = true) -> Bool {
        guard mainSlot == .unsaved else { return true }
        let message = asking
            ? "The account that is in Zalo now isn't saved as a profile yet. Name it, so its messages and files are kept when you switch."
            : "Name the account that is in Zalo now. Zalo keeps running."
        guard let name = Prompt.text(title: "Save the current Zalo account", message: message,
                                     placeholder: "For example: Personal")
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
        return Prompt.confirm(title: "Your disk is nearly full", message: warning, button: "Continue Anyway")
    }

    private func perform(_ label: String?,
                         _ action: @escaping (ProfileManager, @escaping (String) -> Void) throws -> Void) {
        guard busy == nil else { return }
        busy = label ?? "Working…"
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

    /// Runs a long copy (backup or restore) in the background; switching stays available meanwhile.
    private func startCopy(_ label: String, cancel: CancelFlag,
                           _ action: @escaping (ProfileManager, @escaping (String) -> Void) throws -> String) {
        copying = label
        copyCancel = cancel
        copyQueue.async { [manager] in
            let progress = Self.progressSink { self.copying = $0 }
            let result = Result { try action(manager, progress) }
            Task { @MainActor in
                self.copying = nil
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
