namespace ZaloProfiles.Core;

public enum ProfileErrorKind
{
    NotFound,
    Ambiguous,
    NameTaken,
    EmptyName,
    CurrentDataNotSaved,
    NothingToSave,
    AlreadySaved,
    IsInMainZalo,
    IsOpen,
    SameAccountOpen,
    SharedStorageOpen,
    BeingBackedUp,
    ZaloDidNotQuit,
    ZaloNotInstalled,
    IsolationUnsupported,
    Conflict,
    MoveFailed,
    LaunchFailed,
    TrashFailed,
    NothingToBackUp,
    MessagesStoredElsewhere,
    NotAFolder,
    BadBackupFolder,
    NotEnoughSpace,
    CopyFailed,
    CopyMismatch,
    NotABackup,
    Cancelled,
}

/// <summary>Every refusal and failure, with the message shown to the person (in Vietnamese).</summary>
public sealed class ProfileError : Exception
{
    public ProfileErrorKind Kind { get; }
    public string[] Args { get; }

    ProfileError(ProfileErrorKind kind, string message, params string[] args) : base(message)
    {
        Kind = kind;
        Args = args;
    }

    public static ProfileError NotFound(string query) =>
        new(ProfileErrorKind.NotFound, $"Không có tài khoản nào tên “{query}”.", query);

    public static ProfileError Ambiguous(string query) =>
        new(ProfileErrorKind.Ambiguous, $"Có nhiều tài khoản cùng tên “{query}”. Hãy dùng mã của tài khoản.", query);

    public static ProfileError NameTaken(string name) =>
        new(ProfileErrorKind.NameTaken, $"Đã có tài khoản tên “{name}”.", name);

    public static ProfileError EmptyName() =>
        new(ProfileErrorKind.EmptyName, "Hãy đặt tên cho tài khoản.");

    public static ProfileError CurrentDataNotSaved() =>
        new(ProfileErrorKind.CurrentDataNotSaved, "Zalo chính đang giữ một tài khoản chưa được lưu. Hãy lưu tài khoản đó trước, để tin nhắn và tệp của nó được giữ lại.");

    public static ProfileError NothingToSave() =>
        new(ProfileErrorKind.NothingToSave, "Zalo chưa có dữ liệu trên máy tính này nên chưa có gì để lưu. Hãy thêm tài khoản mới.");

    public static ProfileError AlreadySaved(string name) =>
        new(ProfileErrorKind.AlreadySaved, $"Tài khoản đang mở trong Zalo đã được lưu với tên “{name}”.", name);

    public static ProfileError IsInMainZalo(string name) =>
        new(ProfileErrorKind.IsInMainZalo, $"“{name}” là tài khoản Zalo chính. Hãy đặt một tài khoản khác làm Zalo chính trước.", name);

    public static ProfileError IsOpen(string name) =>
        new(ProfileErrorKind.IsOpen, $"“{name}” đang mở. Hãy đóng cửa sổ Zalo của nó trước.", name);

    public static ProfileError SameAccountOpen(string name, string other) =>
        new(ProfileErrorKind.SameAccountOpen, $"“{name}” và “{other}” là cùng một tài khoản Zalo, và “{other}” đang mở. Mở một tài khoản ở hai cửa sổ cùng lúc có thể khiến Zalo đăng xuất hoặc đánh dấu tài khoản có hoạt động bất thường. Hãy đóng “{other}” trước.", name, other);

    public static ProfileError SharedStorageOpen(string name, string other, string folder) =>
        new(ProfileErrorKind.SharedStorageOpen, $"Tin nhắn của “{name}” và “{other}” được Zalo lưu chung một chỗ ({folder}), và “{other}” đang mở. Hai cửa sổ Zalo không nên cùng ghi vào một chỗ. Hãy đóng “{other}” trước.", name, other, folder);

    public static ProfileError BeingBackedUp(string name) =>
        new(ProfileErrorKind.BeingBackedUp, $"“{name}” đang được sao lưu. Hãy đợi sao lưu xong, hoặc hủy sao lưu.", name);

    public static ProfileError ZaloDidNotQuit() =>
        new(ProfileErrorKind.ZaloDidNotQuit, "Zalo không thoát kịp (có thể đang có cuộc gọi hoặc một hộp thoại đang mở). Hãy tự thoát Zalo (chuột phải biểu tượng Zalo ở khay hệ thống, chọn Thoát) rồi thử lại. Chưa có gì bị di chuyển.");

    public static ProfileError ZaloNotInstalled(string path) =>
        new(ProfileErrorKind.ZaloNotInstalled, $"Không tìm thấy Zalo tại {path}. Hãy cài Zalo cho máy tính trước.", path);

    public static ProfileError IsolationUnsupported(string detail) =>
        new(ProfileErrorKind.IsolationUnsupported, $"Máy tính này không cho mở Zalo trong cửa sổ riêng: {detail} Bạn vẫn có thể đổi qua lại từng tài khoản bằng “Đặt làm Zalo chính”.", detail);

    public static ProfileError Conflict(string detail) =>
        new(ProfileErrorKind.Conflict, $"Đã dừng lại để giữ an toàn cho dữ liệu: {detail}", detail);

    public static ProfileError MoveFailed(string from, string to, string reason) =>
        new(ProfileErrorKind.MoveFailed, $"Không thể chuyển {from} sang {to}: {reason}", from, to, reason);

    public static ProfileError LaunchFailed(string reason) =>
        new(ProfileErrorKind.LaunchFailed, $"Không thể mở Zalo: {reason}", reason);

    public static ProfileError TrashFailed(string path) =>
        new(ProfileErrorKind.TrashFailed, $"Không thể chuyển {path} vào Thùng rác. Chưa có gì bị xóa.", path);

    public static ProfileError NothingToBackUp(string name) =>
        new(ProfileErrorKind.NothingToBackUp, $"“{name}” chưa có dữ liệu Zalo nên chưa có gì để sao lưu.", name);

    public static ProfileError MessagesStoredElsewhere(string name, string folder) =>
        new(ProfileErrorKind.MessagesStoredElsewhere, $"Zalo lưu tin nhắn của “{name}” ở {folder}, ngoài thư mục dữ liệu của tài khoản, nên Zalo Switcher chưa sao lưu được tài khoản này. Bạn có thể chuyển nơi lưu tin nhắn về ổ C trong Cài đặt của Zalo (Dữ liệu), hoặc tự sao chép thư mục đó khi Zalo đã thoát.", name, folder);

    public static ProfileError NotAFolder(string path) =>
        new(ProfileErrorKind.NotAFolder, $"{path} không phải là thư mục có thể ghi vào.", path);

    public static ProfileError BadBackupFolder() =>
        new(ProfileErrorKind.BadBackupFolder, "Hãy chọn một thư mục nằm ngoài dữ liệu của Zalo và thư mục tài khoản, ví dụ trên ổ cứng ngoài.");

    public static ProfileError NotEnoughSpace(string place, long needed, long free) =>
        new(ProfileErrorKind.NotEnoughSpace, $"Không đủ dung lượng trống trên {place}: cần khoảng {Disk.Format(needed)}, hiện chỉ còn {Disk.Format(free)}.", place);

    public static ProfileError CopyFailed(string path, string reason) =>
        new(ProfileErrorKind.CopyFailed, $"Không thể sao chép {path}: {reason}", path, reason);

    public static ProfileError CopyMismatch(string what) =>
        new(ProfileErrorKind.CopyMismatch, $"Bản sao của {what} không khớp với bản gốc nên đã không được giữ lại.", what);

    public static ProfileError NotABackup(string path) =>
        new(ProfileErrorKind.NotABackup, $"{path} không phải là bản sao lưu của Zalo Switcher. Hãy chọn một thư mục bên trong “Zalo Backups” có chứa backup.json và ZaloData.", path);

    public static ProfileError Cancelled() =>
        new(ProfileErrorKind.Cancelled, "Đã hủy. Bản sao dở dang đã được xóa, không có gì khác thay đổi.");
}
