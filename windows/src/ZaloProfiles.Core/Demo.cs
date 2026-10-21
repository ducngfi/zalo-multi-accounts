using System.Text;

namespace ZaloProfiles.Core;

/// <summary>A pretend Zalo for the demo: it remembers which data folders are "open" and starts nothing.</summary>
public sealed class DemoZaloControl(Layout layout) : IZaloControl
{
    readonly object _lock = new();
    readonly Dictionary<string, int> _open = new(StringComparer.OrdinalIgnoreCase);
    int _nextPid = 40_001;

    public int? PidUsing(string dataFolder)
    {
        lock (_lock) return _open.TryGetValue(Path.GetFullPath(dataFolder), out var pid) ? pid : null;
    }

    public bool AnyInstanceRunning()
    {
        lock (_lock) return _open.Count > 0;
    }

    public void Quit(string dataFolder, TimeSpan timeout)
    {
        Thread.Sleep(600);
        lock (_lock) _open.Remove(Path.GetFullPath(dataFolder));
    }

    public void LaunchMain(string launcher)
    {
        // Like Zalo, create the data folder when starting without one.
        Directory.CreateDirectory(layout.LiveData);
        MarkOpen(layout.LiveData);
    }

    public void LaunchIsolated(string launcher, string home) => MarkOpen(Layout.DataInHome(home));

    public void Activate(string dataFolder, int pid) { }

    void MarkOpen(string folder)
    {
        lock (_lock) _open[Path.GetFullPath(folder)] = _nextPid++;
    }
}

/// <summary>Synthetic accounts for the demo. Nothing here touches the real Zalo or its data: everything
/// lives in a temporary folder, and Zalo is never started.</summary>
public static class Demo
{
    record Account(string Name, string? ZaloUserId, long Size);

    static readonly Account[] Accounts =
    [
        new("Cá nhân", "8401927365510293847", 8_420_000_000),
        new("Cửa hàng Hoa Mai", "7310528846192037465", 2_150_000_000),
        new("Công ty An Phát", "5528103746629104837", 640_000_000),
        new("Shop mới", null, 0),
    ];

    /// <summary>Where the demo keeps its pretend Windows user folder.</summary>
    public static string Root => Path.Combine(Path.GetTempPath(), "ZaloSwitcherDemo");

    /// <summary>Builds a fresh pretend user folder with four synthetic accounts and returns a manager working
    /// on it: "Cá nhân" open in the main Zalo, "Cửa hàng Hoa Mai" open in a window of its own,
    /// "Công ty An Phát" closed, and "Shop mới" not logged in yet.</summary>
    public static ProfileManager MakeManager(long freeSpace = 42_700_000_000)
    {
        var root = Root;
        if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        var layout = Layout.InFolder(root);
        Directory.CreateDirectory(layout.RoamingAppData);
        Directory.CreateDirectory(Path.GetDirectoryName(layout.ZaloLauncher)!);
        File.WriteAllText(layout.ZaloLauncher, "");

        var zalo = new DemoZaloControl(layout);
        var manager = new ProfileManager(layout, zalo) { FreeSpaceProvider = _ => freeSpace };
        var sizes = Accounts.Where(a => a.ZaloUserId != null).ToDictionary(a => a.ZaloUserId!, a => a.Size);
        manager.SizeProvider = folder =>
            ProfileManager.ZaloUserId(folder) is { } uid && sizes.TryGetValue(uid, out var size) ? size : 48_000_000;
        // The demo's accounts link to no real folders.
        manager.UserFolders = () => [];

        // "Cá nhân": logged in and running in the main Zalo.
        WriteData(Accounts[0], layout.LiveData);
        zalo.LaunchMain(layout.ZaloLauncher);
        manager.SaveCurrent(Accounts[0].Name);

        // "Cửa hàng Hoa Mai" and "Công ty An Phát": saved, with their own data.
        var ids = new List<string>();
        foreach (var account in Accounts[1..3])
        {
            var profile = manager.AddProfile(account.Name);
            WriteData(account, layout.ParkedData(profile.Id));
            ProfileManager.WriteMarker(profile.Id, layout.ParkedData(profile.Id));
            ids.Add(profile.Id);
        }
        manager.Open(ids[0]);
        if (manager.LoadProfile(ids[1]) is { } company)
            manager.SaveProfile(company with { LastUsedAt = DateTime.UtcNow.AddDays(-3) });

        // "Shop mới": added, never logged in.
        manager.AddProfile(Accounts[3].Name);

        // Removing a profile in the demo moves it into the demo folder, not the real Recycle Bin.
        manager.MoveToTrash = path =>
        {
            var trash = Path.Combine(root, "Trash");
            Directory.CreateDirectory(trash);
            var destination = Path.Combine(trash, $"{Path.GetFileName(path)}-{Guid.NewGuid():N}");
            Directory.Move(path, destination);
            return destination;
        };
        return manager;
    }

    static void WriteData(Account account, string folder)
    {
        if (account.ZaloUserId is not { } uid) return;
        var db = Path.Combine(folder, "Database", "_production", uid);
        var media = Path.Combine(folder, "media", uid);
        Directory.CreateDirectory(db);
        Directory.CreateDirectory(media);
        File.WriteAllText(Path.Combine(db, "Message.db"), $"Dữ liệu giả lập của {account.Name}\n", Encoding.UTF8);
        File.WriteAllBytes(Path.Combine(media, "anh-gia-lap.jpg"), Enumerable.Repeat((byte)0x5A, 64_000).ToArray());
        File.WriteAllText(Path.Combine(folder, "Cookies"), "phiên đăng nhập giả lập\n", Encoding.UTF8);
    }
}
