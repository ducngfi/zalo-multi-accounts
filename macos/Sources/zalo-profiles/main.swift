import Foundation
import ZaloProfilesCore

let usage = """
zalo-profiles: dùng nhiều tài khoản Zalo cùng lúc trên một máy Mac, mỗi tài khoản một cửa sổ Zalo riêng.

Cách dùng:
  zalo-profiles status                 Xem mọi tài khoản, tài khoản nào đang mở, và dung lượng
  zalo-profiles open <tài khoản>       Mở <tài khoản> trong cửa sổ Zalo riêng, cùng lúc với các tài khoản khác
  zalo-profiles open --all             Mở mọi tài khoản đã đăng nhập
  zalo-profiles close <tài khoản>      Đóng cửa sổ Zalo của <tài khoản>
  zalo-profiles close --all            Đóng mọi cửa sổ Zalo
  zalo-profiles add <tên>              Thêm tài khoản mới và mở nó ở cửa sổ mới để đăng nhập
        [--no-launch]                  ...và chưa mở
  zalo-profiles save <tên>             Lưu tài khoản đang có trong Zalo chính
  zalo-profiles main <tài khoản>       Đặt <tài khoản> làm Zalo chính, tài khoản mở ra khi bấm biểu tượng Zalo
        [--no-launch]                  ...chỉ đổi chỗ thư mục, không mở lại cửa sổ nào
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
    if status.place == .main { parts.append("Zalo chính") }
    if let pid = status.runningPID {
        parts.append("đang mở (pid \(pid))")
    } else {
        parts.append(status.place == .new ? "mới, chưa đăng nhập" : "đã đóng")
    }
    if let size = manager.dataSize(of: status) { parts.append(Disk.format(size)) }
    if let uid = status.zaloUserID { parts.append("ID Zalo \(uid)") }
    return parts.joined(separator: ", ")
}

func printStatus() {
    switch manager.mainSlot() {
    case .empty:
        print("Zalo chính: chưa có tài khoản (tài khoản mở đầu tiên sẽ thành Zalo chính)")
    case .unsaved:
        let uid = manager.mainZaloUserID().map { " (ID Zalo \($0))" } ?? ""
        let running = manager.mainZaloPID().map { ", đang mở (pid \($0))" } ?? ""
        print("Zalo chính: một tài khoản chưa được lưu\(uid)\(running)")
        print("            Hãy lưu:  zalo-profiles save \"<tên>\"")
    case .profile(let id):
        let name = manager.profiles().first { $0.id == id }?.name ?? id
        print("Zalo chính: \(name)")
    }
    if let free = manager.freeSpace() { print("Ổ đĩa: còn trống \(Disk.format(free))") }
    if let warning = manager.lowSpaceWarning() { print("Cảnh báo: \(warning)") }
    let statuses = manager.statuses()
    print("")
    if statuses.isEmpty {
        print("Chưa có tài khoản nào.")
        return
    }
    print("Tài khoản (\(statuses.filter(\.isOpen).count) đang mở):")
    var seen: [String: String] = [:]
    for status in statuses {
        let mark = status.isOpen ? "●" : "○"
        print(" \(mark) \(status.profile.name)  [\(status.profile.id)]  \(describe(status))")
        if let uid = status.zaloUserID {
            if let other = seen[uid] {
                print("     lưu ý: cùng tài khoản Zalo với “\(other)”; không mở được cả hai cùng lúc")
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
    let all = args.contains("--all")
    args.removeAll { $0 == "--no-launch" || $0 == "--force" || $0 == "--all" }
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
            if !noLaunch { try checkSpace() }
            let profile = try manager.addProfile(named: rest[0])
            print("Đã thêm “\(profile.name)” [\(profile.id)].")
            if !noLaunch {
                try manager.open(profile.id)
                print("Hãy đăng nhập tài khoản mới trong cửa sổ Zalo vừa mở. Lần sau mở lại không cần đăng nhập nữa.")
            }
        case "open":
            try checkSpace()
            if all {
                try need(0)
                let opened = try manager.openAll { print($0) }
                print(opened.isEmpty ? "Mọi tài khoản đã đăng nhập đều đang mở." : "Đã mở \(opened.count) tài khoản.")
            } else {
                try need(1)
                let profile = try manager.find(rest[0])
                try manager.open(profile.id)
                print("Đã mở “\(profile.name)” trong cửa sổ Zalo riêng.")
            }
            print("Lưu ý: gọi thoại và gọi video chỉ ổn định ở một cửa sổ Zalo tại một thời điểm.")
        case "close":
            if all {
                try need(0)
                try manager.closeAll { print($0) }
                print("Đã đóng mọi cửa sổ Zalo.")
            } else {
                try need(1)
                let profile = try manager.find(rest[0])
                try manager.close(profile.id)
                print("Đã đóng “\(profile.name)”.")
            }
        case "main", "switch", "use":
            try need(1)
            let profile = try manager.find(rest[0])
            if noLaunch {
                try manager.switchTo(profile.id, launch: false) { print($0) }
            } else {
                try manager.makeMain(profile.id) { print($0) }
            }
            print("Zalo chính giờ là “\(profile.name)”.")
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
            print("\nĐã khôi phục thành “\(profile.name)” [\(profile.id)]. Mở bằng:  zalo-profiles open \(profile.id)")
            if let original = manager.statuses().first(where: { $0.profile.id != profile.id && $0.zaloUserID == info.zaloUserID && info.zaloUserID != nil }) {
                print("Lưu ý: “\(original.profile.name)” là cùng một tài khoản Zalo, nên không mở được cả hai cùng lúc.")
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
            print("Zalo chính:      \(manager.layout.liveData.path)")
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
