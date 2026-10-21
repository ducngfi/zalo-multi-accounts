import Foundation
import ZaloProfilesCore

let usage = """
zalo-profiles: giữ nhiều tài khoản Zalo trên một máy Mac và chuyển qua lại mà không cần đăng xuất.

Cách dùng:
  zalo-profiles status                 Xem tài khoản đang mở trong Zalo, mọi tài khoản và dung lượng
  zalo-profiles save <tên>             Lưu tài khoản đang mở trong Zalo
  zalo-profiles add <tên>              Thêm tài khoản mới và chuyển sang (đăng nhập một lần)
  zalo-profiles switch <tài khoản>     Thoát Zalo, đổi sang dữ liệu của <tài khoản>, mở lại Zalo
        [--no-launch]                  ...và không mở lại Zalo
  zalo-profiles open <tài khoản>       Mở <tài khoản> ở cửa sổ Zalo thứ hai (thử nghiệm)
  zalo-profiles close <tài khoản>      Đóng cửa sổ Zalo đang mở <tài khoản>
  zalo-profiles backup <tài khoản> <thư mục>
                                       Sao lưu tài khoản vào <thư mục>/Zalo Backups/
  zalo-profiles restore <thư mục sao lưu> <tên>
                                       Khôi phục bản sao lưu thành tài khoản mới tên <tên>
  zalo-profiles rename <tài khoản> <tên mới>
  zalo-profiles remove <tài khoản>     Chuyển tài khoản và dữ liệu của nó vào Thùng rác
  zalo-profiles paths                  Xem nơi lưu dữ liệu

<tài khoản> là tên hoặc mã của tài khoản. Khi ổ đĩa của máy Mac sắp đầy, lệnh add và open
sẽ từ chối chạy, trừ khi bạn thêm --force.
"""

let manager = ProfileManager()
// The app's setting for when to warn about free space applies here too.
if let gigabytes = UserDefaults(suiteName: "local.zalo-switcher")?.object(forKey: "lowSpaceGB") as? Int {
    manager.lowSpaceThreshold = Int64(gigabytes) * 1_000_000_000
}

func describe(_ status: ProfileStatus) -> String {
    var parts: [String] = []
    switch status.place {
    case .main: parts.append(status.runningPID == nil ? "trong Zalo chính (chưa mở)" : "trong Zalo chính, đang chạy")
    case .parked: parts.append(status.runningPID == nil ? "đã lưu" : "đang mở ở cửa sổ thứ hai")
    case .new: parts.append("mới, chưa đăng nhập")
    }
    if let size = manager.dataSize(of: status) { parts.append(Disk.format(size)) }
    if let uid = status.zaloUserID { parts.append("ID Zalo \(uid)") }
    return parts.joined(separator: ", ")
}

func printStatus() {
    switch manager.mainSlot() {
    case .empty:
        print("Zalo: chưa có dữ liệu (Zalo sẽ mở ở màn hình đăng nhập)")
    case .unsaved:
        let uid = manager.mainZaloUserID().map { " (ID Zalo \($0))" } ?? ""
        print("Zalo: một tài khoản chưa được lưu\(uid)")
        print("      Hãy lưu trước:  zalo-profiles save \"<tên>\"")
    case .profile(let id):
        let name = manager.profiles().first { $0.id == id }?.name ?? id
        print("Zalo: \(name)")
    }
    if let pid = manager.mainZaloPID() { print("      đang chạy (pid \(pid))") }
    if let free = manager.freeSpace() { print("Ổ đĩa: còn trống \(Disk.format(free))") }
    if let warning = manager.lowSpaceWarning() { print("Cảnh báo: \(warning)") }
    let statuses = manager.statuses()
    print("")
    if statuses.isEmpty {
        print("Chưa có tài khoản nào.")
        return
    }
    print("Tài khoản:")
    var seen: [String: String] = [:]
    for status in statuses {
        let mark = status.place == .main ? "*" : " "
        print(" \(mark) \(status.profile.name)  [\(status.profile.id)]  \(describe(status))")
        if let uid = status.zaloUserID {
            if let other = seen[uid] {
                print("     lưu ý: cùng tài khoản Zalo với “\(other)”; đừng mở cả hai cùng lúc")
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
        print("\nĐang dừng…")
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
        guard force else { throw LowSpace(message: warning + " Thêm --force để vẫn tiếp tục.") }
        print("Cảnh báo: \(warning)")
    }

    do {
        switch command {
        case "status", "list", "ls":
            printStatus()
        case "save":
            try need(1)
            let profile = try manager.saveCurrent(as: rest[0])
            print("Đã lưu tài khoản đang mở trong Zalo với tên “\(profile.name)” [\(profile.id)].")
        case "add":
            try need(1)
            if manager.mainSlot() == .unsaved { throw ProfileError.currentDataNotSaved }
            try checkSpace()
            let profile = try manager.addProfile(named: rest[0])
            print("Đã thêm “\(profile.name)” [\(profile.id)].")
            try manager.switchTo(profile.id, launch: !noLaunch) { print($0) }
            if !noLaunch { print("Hãy đăng nhập tài khoản mới trong Zalo. Lần sau chuyển lại không cần đăng nhập nữa.") }
        case "switch", "use":
            try need(1)
            let profile = try manager.find(rest[0])
            try manager.switchTo(profile.id, launch: !noLaunch) { print($0) }
            print("Zalo đang dùng “\(profile.name)”.")
            if let warning = manager.lowSpaceWarning() { print("Cảnh báo: \(warning)") }
        case "open":
            try need(1)
            let profile = try manager.find(rest[0])
            try checkSpace()
            try manager.openSideBySide(profile.id)
            print("Đã mở “\(profile.name)” ở cửa sổ Zalo riêng.")
            print("Lưu ý: gọi thoại và gọi video chỉ ổn định ở một cửa sổ Zalo tại một thời điểm.")
        case "close":
            try need(1)
            let profile = try manager.find(rest[0])
            try manager.close(profile.id)
            print("Đã đóng “\(profile.name)”.")
        case "backup":
            try need(2)
            let profile = try manager.find(rest[0])
            let destination = URL(fileURLWithPath: (rest[1] as NSString).expandingTildeInPath, isDirectory: true)
            if manager.isOnThisMacsDisk(destination) {
                print("Lưu ý: \(destination.path) nằm trên ổ đĩa của chính máy Mac này. Bản sao lưu sẽ dùng dung lượng trống của ổ và không còn nếu ổ hỏng; ổ cứng ngoài an toàn hơn.")
            }
            let cancel = cancelOnInterrupt()
            let folder = try manager.backup(profile.id, to: destination, progress: report, cancel: cancel)
            let info = try manager.readBackup(folder)
            let links = (info.links ?? 0) > 0 ? " (\(info.links!) tệp là liên kết cứng, giữ nguyên như trong thư mục của Zalo)" : ""
            print("\nĐã sao lưu “\(profile.name)”: \(info.files) tệp\(links), \(Disk.format(info.bytes)), đã kiểm tra từng tệp.")
            print("Lưu tại \(folder.path)")
        case "restore":
            try need(2)
            let folder = URL(fileURLWithPath: (rest[0] as NSString).expandingTildeInPath, isDirectory: true)
            let info = try manager.readBackup(folder)
            let date = info.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "vi_VN")))
            print("Bản sao lưu “\(info.profileName)” lúc \(date): \(info.files) tệp, \(Disk.format(info.bytes)).")
            let cancel = cancelOnInterrupt()
            let profile = try manager.restore(from: folder, as: rest[1], progress: report, cancel: cancel)
            print("\nĐã khôi phục thành “\(profile.name)” [\(profile.id)]. Chuyển sang hoặc mở song song để dùng.")
            if let original = manager.statuses().first(where: { $0.profile.id != profile.id && $0.zaloUserID == info.zaloUserID && info.zaloUserID != nil }) {
                print("Lưu ý: “\(original.profile.name)” là cùng một tài khoản Zalo. Đừng mở cả hai cùng lúc.")
            }
        case "rename":
            try need(2)
            let profile = try manager.find(rest[0])
            try manager.rename(profile.id, to: rest[1])
            print("Đã đổi tên “\(profile.name)” thành “\(rest[1])”.")
        case "remove", "rm":
            try need(1)
            let profile = try manager.find(rest[0])
            let trashed = try manager.remove(profile.id)
            print("Đã chuyển “\(profile.name)” vào Thùng rác\(trashed.map { " (\($0.path))" } ?? ""). Lấy lại từ Thùng rác nếu cần.")
        case "paths":
            print("Ứng dụng Zalo:   \(manager.layout.zaloApp.path)")
            print("Dữ liệu Zalo:    \(manager.layout.liveData.path)")
            print("Các tài khoản:   \(manager.layout.profilesRoot.path)")
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
        FileHandle.standardError.write(Data("Lỗi: \(error.message)\n".utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data("\nLỗi: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

struct UsageError: Error {}

struct LowSpace: Error {
    var message: String
}

exit(main())
