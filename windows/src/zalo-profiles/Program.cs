using System.Globalization;
using System.Text;
using ZaloProfiles.Core;

Console.OutputEncoding = Encoding.UTF8;

const string Usage = """
zalo-profiles: dùng nhiều tài khoản Zalo cùng lúc trên một máy tính Windows, mỗi tài khoản một cửa sổ Zalo riêng.

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
                                       Sao lưu tài khoản vào <thư mục>\Zalo Backups\
  zalo-profiles restore <thư mục sao lưu> <tên>
                                       Khôi phục bản sao lưu thành tài khoản mới tên <tên>
  zalo-profiles rename <tài khoản> <tên mới>
  zalo-profiles remove <tài khoản>     Chuyển tài khoản và dữ liệu của nó vào Thùng rác
  zalo-profiles paths                  Xem nơi lưu dữ liệu

<tài khoản> là tên hoặc mã của tài khoản. Tên có dấu cách thì đặt trong ngoặc kép.
Khi ổ đĩa chứa dữ liệu Zalo sắp đầy, lệnh add và open sẽ từ chối chạy, trừ khi bạn thêm --force.
""";

var manager = ProfileManager.ForSystem();
// The app's setting for when to warn about free space applies here too.
manager.LowSpaceThreshold = Settings.Load().LowSpaceGB * 1_000_000_000L;
return Run(args);

int Run(string[] arguments)
{
    var list = arguments.ToList();
    var noLaunch = list.Remove("--no-launch");
    var force = list.Remove("--force");
    var all = list.Remove("--all");
    if (list.Count == 0)
    {
        PrintStatus();
        return 0;
    }
    var command = list[0];
    var rest = list.Skip(1).ToList();

    void Need(int count)
    {
        if (rest.Count != count) throw new UsageError();
    }

    void CheckSpace()
    {
        if (manager.LowSpaceWarning() is not { } warning) return;
        if (!force) throw new LowSpace(warning + " Thêm --force để vẫn tiếp tục.");
        Console.WriteLine($"Cảnh báo: {warning}");
    }

    try
    {
        switch (command)
        {
            case "status" or "list" or "ls":
                PrintStatus();
                break;
            case "save":
            {
                Need(1);
                var profile = manager.SaveCurrent(rest[0]);
                Console.WriteLine($"Đã lưu tài khoản đang mở trong Zalo với tên “{profile.Name}” [{profile.Id}].");
                break;
            }
            case "add":
            {
                Need(1);
                if (!noLaunch) CheckSpace();
                var profile = manager.AddProfile(rest[0]);
                Console.WriteLine($"Đã thêm “{profile.Name}” [{profile.Id}].");
                if (!noLaunch)
                {
                    manager.Open(profile.Id);
                    Console.WriteLine("Hãy đăng nhập tài khoản mới trong cửa sổ Zalo vừa mở. Lần sau mở lại không cần đăng nhập nữa.");
                }
                break;
            }
            case "open":
                CheckSpace();
                if (all)
                {
                    Need(0);
                    var opened = manager.OpenAll(Console.WriteLine);
                    Console.WriteLine(opened.Count == 0 ? "Mọi tài khoản đã đăng nhập đều đang mở." : $"Đã mở {opened.Count} tài khoản.");
                }
                else
                {
                    Need(1);
                    var profile = manager.Find(rest[0]);
                    manager.Open(profile.Id);
                    Console.WriteLine($"Đã mở “{profile.Name}” trong cửa sổ Zalo riêng.");
                }
                Console.WriteLine("Lưu ý: gọi thoại và gọi video chỉ ổn định ở một cửa sổ Zalo tại một thời điểm.");
                break;
            case "close":
                if (all)
                {
                    Need(0);
                    manager.CloseAll(Console.WriteLine);
                    Console.WriteLine("Đã đóng mọi cửa sổ Zalo.");
                }
                else
                {
                    Need(1);
                    var profile = manager.Find(rest[0]);
                    manager.Close(profile.Id);
                    Console.WriteLine($"Đã đóng “{profile.Name}”.");
                }
                break;
            case "main" or "switch" or "use":
            {
                Need(1);
                var profile = manager.Find(rest[0]);
                if (noLaunch) manager.SwitchTo(profile.Id, launch: false, progress: Console.WriteLine);
                else manager.MakeMain(profile.Id, Console.WriteLine);
                Console.WriteLine($"Zalo chính giờ là “{profile.Name}”.");
                break;
            }
            case "backup":
            {
                Need(2);
                var profile = manager.Find(rest[0]);
                var destination = Path.GetFullPath(rest[1]);
                if (manager.IsOnZaloDrive(destination))
                    Console.WriteLine($"Lưu ý: {destination} nằm trên cùng ổ đĩa với dữ liệu Zalo. Bản sao lưu sẽ dùng dung lượng trống của ổ và không còn nếu ổ hỏng; ổ cứng ngoài an toàn hơn.");
                if (manager.Status(profile.Id)?.IsOpen == true)
                    Console.WriteLine($"Cửa sổ Zalo của “{profile.Name}” sẽ đóng trong lúc sao chép, rồi tự mở lại.");
                var cancel = CancelOnInterrupt();
                var folder = manager.Backup(profile.Id, destination, Report, cancel);
                var info = manager.ReadBackup(folder);
                var links = info.Links > 0 ? $" ({info.Links} tệp là liên kết cứng, giữ nguyên như trong thư mục của Zalo)" : "";
                Console.WriteLine($"\nĐã sao lưu “{profile.Name}”: {info.Files} tệp{links}, {Disk.Format(info.Bytes)}, đã kiểm tra từng tệp.");
                Console.WriteLine($"Lưu tại {folder}");
                if (manager.Status(profile.Id)?.DataFolder is { } data && ProfileManager.ExternalFilesFolder(data) is { } files)
                    Console.WriteLine($"Lưu ý: ảnh và tệp Zalo của tài khoản này lưu ở {files}, không nằm trong bản sao lưu.");
                break;
            }
            case "restore":
            {
                Need(2);
                var folder = Path.GetFullPath(rest[0]);
                var info = manager.ReadBackup(folder);
                var date = info.CreatedAt.ToLocalTime().ToString("g", CultureInfo.GetCultureInfo("vi-VN"));
                Console.WriteLine($"Bản sao lưu “{info.ProfileName}” lúc {date}: {info.Files} tệp, {Disk.Format(info.Bytes)}.");
                var cancel = CancelOnInterrupt();
                var profile = manager.Restore(folder, rest[1], Report, cancel);
                Console.WriteLine($"\nĐã khôi phục thành “{profile.Name}” [{profile.Id}]. Mở bằng:  zalo-profiles open {profile.Id}");
                if (info.ZaloUserId != null && manager.Statuses().FirstOrDefault(s => s.Profile.Id != profile.Id && s.ZaloUserId == info.ZaloUserId) is { } original)
                    Console.WriteLine($"Lưu ý: “{original.Profile.Name}” là cùng một tài khoản Zalo, nên không mở được cả hai cùng lúc.");
                break;
            }
            case "rename":
            {
                Need(2);
                var profile = manager.Find(rest[0]);
                manager.Rename(profile.Id, rest[1]);
                Console.WriteLine($"Đã đổi tên “{profile.Name}” thành “{rest[1]}”.");
                break;
            }
            case "remove" or "rm":
            {
                Need(1);
                var profile = manager.Find(rest[0]);
                manager.Remove(profile.Id);
                Console.WriteLine($"Đã chuyển “{profile.Name}” vào Thùng rác. Lấy lại từ Thùng rác nếu cần.");
                break;
            }
            case "paths":
                Console.WriteLine($"Ứng dụng Zalo:   {manager.Layout.ZaloLauncher}");
                Console.WriteLine($"Zalo chính:      {manager.Layout.LiveData}");
                Console.WriteLine($"Các tài khoản:   {manager.Layout.ProfilesRoot}");
                if (ProfileManager.ExternalMessagesFolder(manager.Layout.LiveData) is { } messages)
                    Console.WriteLine($"Tin nhắn của Zalo chính: {messages}");
                break;
            case "help" or "-h" or "--help" or "/?":
                Console.WriteLine(Usage);
                break;
            default:
                throw new UsageError();
        }
        return 0;
    }
    catch (UsageError)
    {
        Console.Error.WriteLine(Usage);
        return 2;
    }
    catch (LowSpace error)
    {
        Console.Error.WriteLine($"Lỗi: {error.Message}");
        return 1;
    }
    catch (Exception error)
    {
        Console.Error.WriteLine($"\nLỗi: {error.Message}");
        return 1;
    }
}

string Describe(ProfileStatus status)
{
    var parts = new List<string>();
    if (status.Place == Place.Main) parts.Add("Zalo chính");
    parts.Add(status.RunningPid is { } pid ? $"đang mở (pid {pid})" : status.Place == Place.New ? "mới, chưa đăng nhập" : "đã đóng");
    if (manager.DataSize(status) is { } size) parts.Add(Disk.Format(size));
    if (status.ZaloUserId is { } uid) parts.Add($"ID Zalo {uid}");
    return string.Join(", ", parts);
}

void PrintStatus()
{
    switch (manager.GetMainSlot())
    {
        case MainSlot.Empty:
            Console.WriteLine("Zalo chính: chưa có tài khoản (tài khoản mở đầu tiên sẽ thành Zalo chính)");
            break;
        case MainSlot.Unsaved:
            var uid = manager.MainZaloUserId() is { } id ? $" (ID Zalo {id})" : "";
            var running = manager.MainZaloPid() is { } pid ? $", đang mở (pid {pid})" : "";
            Console.WriteLine($"Zalo chính: một tài khoản chưa được lưu{uid}{running}");
            Console.WriteLine("            Hãy lưu:  zalo-profiles save \"<tên>\"");
            break;
        case MainSlot.Saved saved:
            Console.WriteLine($"Zalo chính: {manager.Profiles().FirstOrDefault(p => p.Id == saved.Id)?.Name ?? saved.Id}");
            break;
    }
    if (manager.FreeSpace() is { } free) Console.WriteLine($"Ổ đĩa: còn trống {Disk.Format(free)}");
    if (manager.LowSpaceWarning() is { } warning) Console.WriteLine($"Cảnh báo: {warning}");
    var statuses = manager.Statuses();
    Console.WriteLine();
    if (statuses.Count == 0)
    {
        Console.WriteLine("Chưa có tài khoản nào.");
        return;
    }
    Console.WriteLine($"Tài khoản ({statuses.Count(s => s.IsOpen)} đang mở):");
    var seen = new Dictionary<string, string>();
    foreach (var status in statuses)
    {
        var mark = status.IsOpen ? "●" : "○";
        Console.WriteLine($" {mark} {status.Profile.Name}  [{status.Profile.Id}]  {Describe(status)}");
        if (status.ZaloUserId is not { } account) continue;
        if (seen.TryGetValue(account, out var other))
            Console.WriteLine($"     lưu ý: cùng tài khoản Zalo với “{other}”; không mở được cả hai cùng lúc");
        seen[account] = status.Profile.Name;
    }
}

/// <summary>Prints progress; percentage updates rewrite the same line.</summary>
void Report(string message)
{
    if (message.Contains('%')) Console.Write($"\r{message}\u001b[K");
    else Console.WriteLine(message);
}

/// <summary>Lets Ctrl+C stop a backup or restore cleanly instead of leaving half a copy behind.</summary>
CancelFlag CancelOnInterrupt()
{
    var flag = new CancelFlag();
    Console.CancelKeyPress += (_, e) =>
    {
        e.Cancel = true;
        Console.WriteLine("\nĐang dừng…");
        flag.Cancel();
    };
    return flag;
}

sealed class UsageError : Exception;

sealed class LowSpace(string message) : Exception(message);
