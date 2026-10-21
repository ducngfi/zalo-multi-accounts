import Foundation

public enum ProfileError: LocalizedError, Equatable {
    case notFound(String)
    case ambiguous(String)
    case nameTaken(String)
    case emptyName
    case currentDataNotSaved
    case nothingToSave
    case alreadySaved(String)
    case isInMainZalo(String)
    case openSideBySide(String)
    case zaloDidNotQuit
    case zaloNotInstalled(String)
    case conflict(String)
    case moveFailed(from: String, to: String, reason: String)
    case launchFailed(String)
    case nothingToBackUp(String)
    case notAFolder(String)
    case badBackupFolder
    case notEnoughSpace(place: String, needed: Int64, free: Int64)
    case snapshotFailed(String)
    case copyFailed(String, reason: String)
    case copyMismatch(String)
    case notABackup(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notFound(let query):
            return "Không có tài khoản nào tên “\(query)”."
        case .ambiguous(let query):
            return "Có nhiều tài khoản cùng tên “\(query)”. Hãy dùng mã của tài khoản."
        case .nameTaken(let name):
            return "Đã có tài khoản tên “\(name)”."
        case .emptyName:
            return "Hãy đặt tên cho tài khoản."
        case .currentDataNotSaved:
            return "Tài khoản đang mở trong Zalo chưa được lưu. Hãy lưu tài khoản này trước, để tin nhắn và tệp của nó được giữ lại khi chuyển."
        case .nothingToSave:
            return "Zalo chưa có dữ liệu trên máy Mac này nên chưa có gì để lưu. Hãy thêm tài khoản mới."
        case .alreadySaved(let name):
            return "Tài khoản đang mở trong Zalo đã được lưu với tên “\(name)”."
        case .isInMainZalo(let name):
            return "“\(name)” đang mở trong Zalo chính. Hãy chuyển sang tài khoản khác trước."
        case .openSideBySide(let name):
            return "“\(name)” đang mở ở cửa sổ Zalo thứ hai. Hãy đóng cửa sổ đó trước."
        case .zaloDidNotQuit:
            return "Zalo không thoát kịp (có thể đang có cuộc gọi hoặc một hộp thoại đang mở). Hãy tự thoát Zalo rồi thử lại. Chưa có gì bị di chuyển."
        case .zaloNotInstalled(let path):
            return "Không tìm thấy Zalo tại \(path)."
        case .conflict(let detail):
            return "Đã dừng lại để giữ an toàn cho dữ liệu: \(detail)"
        case .moveFailed(let from, let to, let reason):
            return "Không thể chuyển \(from) sang \(to): \(reason)"
        case .launchFailed(let reason):
            return "Không thể mở Zalo: \(reason)"
        case .nothingToBackUp(let name):
            return "“\(name)” chưa có dữ liệu Zalo nên chưa có gì để sao lưu."
        case .notAFolder(let path):
            return "\(path) không phải là thư mục có thể ghi vào."
        case .badBackupFolder:
            return "Hãy chọn một thư mục nằm ngoài dữ liệu của Zalo và thư mục tài khoản, ví dụ trên ổ cứng ngoài."
        case .notEnoughSpace(let place, let needed, let free):
            return "Không đủ dung lượng trống trên \(place): cần khoảng \(Disk.format(needed)), hiện chỉ còn \(Disk.format(free))."
        case .snapshotFailed(let reason):
            return "Không thể chụp nhanh dữ liệu của tài khoản: \(reason). Chưa có gì thay đổi."
        case .copyFailed(let path, let reason):
            return "Không thể sao chép \(path): \(reason)"
        case .copyMismatch(let what):
            return "Bản sao của \(what) không khớp với bản gốc nên đã không được giữ lại."
        case .notABackup(let path):
            return "\(path) không phải là bản sao lưu của Zalo Switcher. Hãy chọn một thư mục bên trong “Zalo Backups” có chứa backup.json và ZaloData."
        case .cancelled:
            return "Đã hủy. Bản sao dở dang đã được xóa, không có gì khác thay đổi."
        }
    }
}
