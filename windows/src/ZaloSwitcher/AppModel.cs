using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Threading;
using ZaloProfiles.Core;

namespace ZaloSwitcher;

/// <summary>
/// The app's state and actions. The manager is only touched off the UI thread: anything that moves or
/// opens profiles runs one at a time under <see cref="_work"/>; the long backup and restore copies run on
/// their own, so opening and closing stay available meanwhile.
/// </summary>
public sealed class AppModel : Observable
{
    public ProfileManager Manager { get; }
    public Settings Settings { get; }
    public bool IsDemo { get; }
    public ObservableCollection<AccountRow> Rows { get; } = [];

    readonly SemaphoreSlim _work = new(1, 1);
    readonly Dispatcher _ui = Application.Current.Dispatcher;
    readonly List<DispatcherTimer> _timers = [];
    CancelFlag? _copyCancel;
    bool _refreshing;

    public AppModel(ProfileManager manager, Settings settings, bool isDemo)
    {
        Manager = manager;
        Settings = settings;
        IsDemo = isDemo;
        Manager.LowSpaceThreshold = settings.LowSpaceGB * 1_000_000_000L;
    }

    // MARK: - State

    List<ProfileStatus> _statuses = [];
    MainSlot _mainSlot = MainSlot.EmptySlot;
    bool _mainRunning;
    string? _busy;
    Dictionary<string, long> _sizes = [];
    long? _freeSpace;
    bool _lowSpace;
    string? _copying;
    double _copyProgress;

    public IReadOnlyList<ProfileStatus> Statuses => _statuses;
    public MainSlot MainSlot => _mainSlot;
    public string? Busy { get => _busy; private set { if (Set(ref _busy, value)) StateChanged(); } }
    public string? Copying { get => _copying; private set { if (Set(ref _copying, value)) StateChanged(); } }
    public double CopyProgress { get => _copyProgress; private set => Set(ref _copyProgress, value); }
    public long? FreeSpace => _freeSpace;
    public bool LowSpace => _lowSpace;
    public bool IsIdle => Busy == null;
    public bool IsUnsaved => _mainSlot is MainSlot.Unsaved;
    public bool HasNoAccounts => _statuses.Count == 0;
    public IReadOnlyDictionary<string, long> Sizes => _sizes;

    /// <summary>The name of the account the normal Zalo app opens.</summary>
    public string? MainName => _mainSlot is MainSlot.Saved saved ? _statuses.FirstOrDefault(s => s.Profile.Id == saved.Id)?.Profile.Name : null;

    /// <summary>How many Zalo windows are open, counting a normal Zalo holding an unsaved account.</summary>
    public int OpenCount => _statuses.Count(s => s.IsOpen) + (IsUnsaved && _mainRunning ? 1 : 0);

    /// <summary>Saved accounts that have been logged in and aren't open.</summary>
    public int ClosedCount => _statuses.Count(s => !s.IsOpen && s.Place != Place.New);

    public string Headline => _statuses.Count == 0 ? "Chưa có tài khoản nào" : $"{OpenCount} trong {_statuses.Count} tài khoản đang mở";
    public string Subheadline => _freeSpace is { } free ? $"Ổ đĩa còn trống {Disk.Format(free)}" : "";
    public string LowSpaceText => _freeSpace is { } free
        ? $"Ổ đĩa chỉ còn trống {Disk.Format(free)}. Zalo cần chỗ để lưu tin nhắn và ảnh; hãy giải phóng dung lượng trước khi thêm hoặc mở thêm tài khoản."
        : "";

    /// <summary>Raised whenever anything the tray menu shows may have changed.</summary>
    public event Action? Changed;

    void StateChanged()
    {
        Raise(nameof(IsIdle));
        foreach (var row in Rows) row.Update(row.Status, _sizes.TryGetValue(row.Id, out var s) ? s : null);
        System.Windows.Input.CommandManager.InvalidateRequerySuggested();
        Changed?.Invoke();
    }

    /// <summary>Starts keeping the state up to date: every 3 seconds, and sizes every 10 minutes.</summary>
    public void Start()
    {
        Refresh();
        RefreshSizes();
        _timers.Add(Every(TimeSpan.FromSeconds(3), Refresh));
        _timers.Add(Every(TimeSpan.FromMinutes(10), RefreshSizes));
    }

    static DispatcherTimer Every(TimeSpan interval, Action action)
    {
        var timer = new DispatcherTimer { Interval = interval };
        timer.Tick += (_, _) => action();
        timer.Start();
        return timer;
    }

    public void SetLowSpaceThreshold(int gigabytes)
    {
        Settings.LowSpaceGB = gigabytes;
        Settings.Save();
        Manager.LowSpaceThreshold = gigabytes * 1_000_000_000L;
        Refresh();
    }

    public void Refresh()
    {
        if (_refreshing) return;
        _refreshing = true;
        Task.Run(async () =>
        {
            await _work.WaitAsync();
            Snapshot snapshot;
            try { snapshot = Read(); }
            catch { snapshot = new([], MainSlot.EmptySlot, false, null, false); }
            finally { _work.Release(); }
            await _ui.InvokeAsync(() =>
            {
                Apply(snapshot);
                _refreshing = false;
            });
        });
    }

    /// <summary>Reads everything at once and waits for it; used before drawing screenshots.</summary>
    public void RefreshNow()
    {
        _sizes = Manager.Statuses().Where(s => Manager.DataSize(s) != null)
            .ToDictionary(s => s.Profile.Id, s => Manager.DataSize(s)!.Value);
        Apply(Read());
    }

    /// <summary>Shows a copy in progress for the screenshots without running anything.</summary>
    public void ShowDemoProgress(string label, double fraction)
    {
        Copying = label;
        CopyProgress = fraction;
    }

    /// <summary>Measuring takes a moment per few GB, so it runs every 10 minutes and after changes.</summary>
    public void RefreshSizes()
    {
        Task.Run(() =>
        {
            var sizes = new Dictionary<string, long>();
            try
            {
                foreach (var status in Manager.Statuses())
                    if (Manager.DataSize(status) is { } size) sizes[status.Profile.Id] = size;
            }
            catch { }
            _ui.InvokeAsync(() =>
            {
                _sizes = sizes;
                StateChanged();
            });
        });
    }

    sealed record Snapshot(List<ProfileStatus> Statuses, MainSlot Slot, bool Running, long? Free, bool Low);

    Snapshot Read() => new(Manager.Statuses(), Manager.GetMainSlot(), Manager.MainZaloPid() != null,
                           Manager.FreeSpace(), Manager.LowSpaceWarning() != null);

    void Apply(Snapshot snapshot)
    {
        _statuses = snapshot.Statuses;
        _mainSlot = snapshot.Slot;
        _mainRunning = snapshot.Running;
        _freeSpace = snapshot.Free;
        _lowSpace = snapshot.Low;

        // Update rows in place, so open menus and focus survive a refresh.
        var ids = _statuses.Select(s => s.Profile.Id).ToList();
        for (var i = Rows.Count - 1; i >= 0; i--)
            if (!ids.Contains(Rows[i].Id)) Rows.RemoveAt(i);
        for (var i = 0; i < _statuses.Count; i++)
        {
            var status = _statuses[i];
            var size = _sizes.TryGetValue(status.Profile.Id, out var s) ? s : (long?)null;
            var existing = Rows.FirstOrDefault(r => r.Id == status.Profile.Id);
            if (existing == null)
            {
                existing = new AccountRow(this, status);
                Rows.Insert(i, existing);
            }
            else if (Rows.IndexOf(existing) != i)
            {
                Rows.Move(Rows.IndexOf(existing), i);
            }
            existing.Update(status, size);
        }
        RaiseAll();
        StateChanged();
    }

    // MARK: - Actions

    /// <summary>Opens the account in a Zalo window of its own, or brings its window forward.</summary>
    public void Open(ProfileStatus status)
    {
        if (!status.IsOpen && !ConfirmDespiteLowSpace()) return;
        Perform(status.IsOpen ? null : $"Đang mở {status.Profile.Name}…", (m, _) => m.Open(status.Profile.Id));
    }

    public void Close(ProfileStatus status) =>
        Perform($"Đang đóng {status.Profile.Name}…", (m, _) => m.Close(status.Profile.Id));

    /// <summary>Opens every account that has been logged in. At sign-in it doesn't ask about low space:
    /// it opens the accounts the person uses anyway.</summary>
    public void OpenAll(bool asking = true)
    {
        if (asking && !ConfirmDespiteLowSpace()) return;
        Perform("Đang mở các tài khoản…", (m, progress) => m.OpenAll(progress));
    }

    public void CloseAll()
    {
        if (!Dialogs.Confirm("Đóng mọi cửa sổ Zalo?",
                "Mọi tài khoản đang mở sẽ thoát như khi chọn Thoát trong Zalo. Tin nhắn mới sẽ về khi bạn mở lại.",
                "Đóng tất cả")) return;
        Perform("Đang đóng các tài khoản…", (m, progress) => m.CloseAll(progress));
    }

    /// <summary>Adds an account and opens it in a new Zalo window at the login screen; the others keep running.</summary>
    public void AddAccount()
    {
        if (!ConfirmDespiteLowSpace()) return;
        if (Dialogs.Text("Thêm tài khoản Zalo",
                "Đặt tên cho tài khoản mới. Một cửa sổ Zalo mới sẽ mở ở màn hình đăng nhập, còn các tài khoản đang mở vẫn chạy bình thường. Bạn chỉ cần đăng nhập một lần; sau này mở lại không cần đăng nhập nữa.",
                "Ví dụ: Cửa hàng") is not { } name) return;
        Perform($"Đang thêm {name}…", (m, _) =>
        {
            var profile = m.AddProfile(name);
            m.Open(profile.Id);
        });
    }

    /// <summary>Makes the account the one the normal Zalo app opens, from its shortcuts or when Windows starts.</summary>
    public void MakeMain(ProfileStatus status)
    {
        if (!EnsureMainIsSaved()) return;
        var current = MainName is { } name ? $"“{name}”" : "tài khoản Zalo chính hiện tại";
        if (!Dialogs.Confirm($"Đặt “{status.Profile.Name}” làm Zalo chính?",
                $"Zalo chính là tài khoản mở ra khi bạn bấm biểu tượng Zalo trên màn hình nền, thanh tác vụ hoặc menu Start, hoặc khi Zalo tự mở cùng Windows. Cửa sổ của “{status.Profile.Name}” và của {current} sẽ đóng vài giây để đổi chỗ thư mục dữ liệu, rồi tự mở lại. Các cửa sổ khác vẫn chạy.",
                "Đặt làm Zalo chính")) return;
        Perform($"Đang đặt {status.Profile.Name} làm Zalo chính…", (m, progress) => m.MakeMain(status.Profile.Id, progress));
    }

    public void SaveCurrent() => EnsureMainIsSaved(asking: false);

    public void Rename(ProfileStatus status)
    {
        if (Dialogs.Text($"Đổi tên “{status.Profile.Name}”", "Tên mới:", status.Profile.Name, status.Profile.Name) is not { } name) return;
        Perform(null, (m, _) => m.Rename(status.Profile.Id, name));
    }

    public void Remove(ProfileStatus status)
    {
        if (!Dialogs.Confirm($"Xóa “{status.Profile.Name}” khỏi máy?",
                "Tài khoản này cùng tin nhắn, ảnh và tệp Zalo của nó trên máy tính sẽ được chuyển vào Thùng rác. Bạn vẫn lấy lại được từ Thùng rác cho đến khi dọn sạch Thùng rác. Bản thân tài khoản Zalo và tin nhắn trên máy chủ của Zalo không bị ảnh hưởng.",
                "Chuyển vào Thùng rác", destructive: true)) return;
        Perform(null, (m, _) => m.Remove(status.Profile.Id));
    }

    public void BackUp(ProfileStatus status)
    {
        if (Copying != null) return;
        if (Dialogs.ChooseFolder($"Chọn nơi lưu bản sao lưu của “{status.Profile.Name}”, ví dụ một ổ cứng ngoài",
                Settings.LastBackupFolder) is not { } destination) return;
        Settings.LastBackupFolder = destination;
        Settings.Save();
        if (Manager.IsOnZaloDrive(destination) && !IsDemo
            && !Dialogs.Confirm("Sao lưu vào cùng ổ đĩa với Zalo?",
                $"{destination} nằm trên cùng ổ đĩa với dữ liệu Zalo. Bản sao lưu sẽ dùng dung lượng trống của ổ và sẽ mất nếu ổ đĩa hỏng. Ổ cứng ngoài an toàn hơn.",
                "Vẫn sao lưu")) return;
        if (status.RunningPid != null
            && !Dialogs.Confirm($"Sao lưu “{status.Profile.Name}”?",
                $"Cửa sổ Zalo của “{status.Profile.Name}” sẽ đóng trong lúc sao chép (có thể vài phút với tài khoản nhiều dữ liệu), rồi tự mở lại. Các tài khoản khác vẫn chạy bình thường.",
                "Sao lưu")) return;

        var cancel = new CancelFlag();
        Busy = $"Đang chuẩn bị sao lưu {status.Profile.Name}…";
        Task.Run(async () =>
        {
            await _work.WaitAsync();
            BackupJob job;
            try
            {
                job = Manager.PrepareBackup(status.Profile.Id, destination, ProgressSink(m => Busy = m));
            }
            catch (Exception error)
            {
                await _ui.InvokeAsync(() =>
                {
                    Busy = null;
                    Refresh();
                    Dialogs.Error(error);
                });
                return;
            }
            finally { _work.Release(); }
            await _ui.InvokeAsync(() =>
            {
                Busy = null;
                Refresh();
                StartCopy($"Đang sao lưu {status.Profile.Name}…", cancel, (m, progress) =>
                {
                    string folder;
                    using (job) folder = m.WriteBackup(job, destination, progress, cancel);
                    var info = m.ReadBackup(folder);
                    var message = $"Đã sao lưu “{status.Profile.Name}”: {info.Files} tệp, {Disk.Format(info.Bytes)} dữ liệu, đã kiểm tra từng tệp.\n\nLưu tại {folder}";
                    if (ProfileManager.ExternalFilesFolder(job.Status.DataFolder!) is { } files)
                        message += $"\n\nLưu ý: ảnh và tệp Zalo của tài khoản này lưu ở {files}, không nằm trong bản sao lưu.";
                    return message;
                });
            });
        });
    }

    public void Restore()
    {
        if (Copying != null) return;
        var start = Settings.LastBackupFolder is { } last ? Path.Combine(last, ProfileManager.BackupsFolderName) : null;
        if (Dialogs.ChooseFolder("Chọn một bản sao lưu: một thư mục bên trong “Zalo Backups” trên ổ sao lưu của bạn", start) is not { } folder) return;
        BackupInfo info;
        try { info = Manager.ReadBackup(folder); }
        catch (Exception error) { Dialogs.Error(error); return; }
        var date = info.CreatedAt.ToLocalTime().ToString("d MMM yyyy, HH:mm", CultureInfo.GetCultureInfo("vi-VN"));
        if (Dialogs.Text($"Khôi phục “{info.ProfileName}” ({date})",
                $"Bản sao lưu sẽ được khôi phục thành một tài khoản mới ({Disk.Format(info.Bytes)}); không tài khoản nào bị thay thế. Nếu tài khoản gốc vẫn còn trong danh sách, ứng dụng sẽ không cho mở cả hai cùng lúc.\n\nTên cho tài khoản khôi phục:",
                $"{info.ProfileName} (khôi phục)", $"{info.ProfileName} (khôi phục)") is not { } name) return;
        var cancel = new CancelFlag();
        StartCopy($"Đang khôi phục {name}…", cancel, (m, progress) =>
        {
            var profile = m.Restore(folder, name, progress, cancel);
            return $"Đã khôi phục thành “{profile.Name}”. Bấm “Mở” để dùng tài khoản này.";
        });
    }

    public void CancelCopy()
    {
        _copyCancel?.Cancel();
        Copying = "Đang dừng…";
    }

    public void ShowProfilesFolder()
    {
        Directory.CreateDirectory(Manager.Layout.ProfilesRoot);
        Process.Start("explorer.exe", $"\"{Manager.Layout.ProfilesRoot}\"");
    }

    public void ShowZaloDataFolder()
    {
        var data = Manager.Layout.LiveData;
        Process.Start("explorer.exe", Directory.Exists(data) ? $"/select,\"{data}\"" : $"\"{Manager.Layout.RoamingAppData}\"");
    }

    // MARK: - Helpers

    /// <summary>When the normal Zalo holds an account that isn't saved yet, asks for a name and saves it,
    /// so it is kept when another account moves into the main slot. Returns false if the person cancels or
    /// saving fails.</summary>
    bool EnsureMainIsSaved(bool asking = true)
    {
        if (!IsUnsaved) return true;
        var message = asking
            ? "Zalo chính đang giữ một tài khoản chưa được lưu. Hãy đặt tên cho nó, để tin nhắn và tệp của nó được giữ lại."
            : "Đặt tên cho tài khoản đang có trong Zalo chính. Zalo vẫn chạy bình thường.";
        if (Dialogs.Text("Lưu tài khoản trong Zalo chính", message, "Ví dụ: Cá nhân") is not { } name) return false;
        try
        {
            Manager.SaveCurrent(name);
            Refresh();
            return true;
        }
        catch (Exception error)
        {
            Dialogs.Error(error);
            return false;
        }
    }

    /// <summary>Asks before adding or opening an account while the drive is nearly full.</summary>
    bool ConfirmDespiteLowSpace() =>
        Manager.LowSpaceWarning() is not { } warning || Dialogs.Confirm("Ổ đĩa sắp đầy", warning, "Vẫn tiếp tục");

    void Perform(string? label, Action<ProfileManager, Action<string>> action)
    {
        if (Busy != null) return;
        Busy = label ?? "Đang xử lý…";
        Task.Run(async () =>
        {
            await _work.WaitAsync();
            Exception? failure = null;
            try { action(Manager, ProgressSink(m => Busy = m)); }
            catch (Exception error) { failure = error; }
            finally { _work.Release(); }
            await _ui.InvokeAsync(() =>
            {
                Busy = null;
                Refresh();
                RefreshSizes();
                if (failure != null) Dialogs.Error(failure);
            });
        });
    }

    /// <summary>Runs a long copy (backup or restore) in the background.</summary>
    void StartCopy(string label, CancelFlag cancel, Func<ProfileManager, Action<string>, string> action)
    {
        Copying = label;
        CopyProgress = 0;
        _copyCancel = cancel;
        Task.Run(async () =>
        {
            var progress = ProgressSink(message =>
            {
                Copying = message;
                if (Regex.Match(message, @"(\d+)%") is { Success: true } match) CopyProgress = int.Parse(match.Groups[1].Value) / 100.0;
            });
            string? result = null;
            Exception? failure = null;
            try { result = action(Manager, progress); }
            catch (Exception error) { failure = error; }
            await _ui.InvokeAsync(() =>
            {
                Copying = null;
                CopyProgress = 0;
                _copyCancel = null;
                Refresh();
                RefreshSizes();
                if (failure != null) Dialogs.Error(failure);
                else Dialogs.Info("Zalo Switcher", result!);
            });
        });
    }

    Action<string> ProgressSink(Action<string> update) => message => _ui.InvokeAsync(() => update(message));
}
