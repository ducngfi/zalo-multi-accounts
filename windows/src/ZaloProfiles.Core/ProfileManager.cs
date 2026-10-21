using System.Globalization;
using System.Text;
using System.Text.Json;

namespace ZaloProfiles.Core;

/// <summary>
/// Saves and opens Zalo profiles, each in a Zalo window of its own, all at the same time. The profile
/// in the main slot opens in the normal Zalo; every other one opens in a separate Zalo whose home folder
/// (USERPROFILE) is the profile folder. Moving a profile into the main slot is a folder rename on the
/// same drive: nothing is copied, and nothing is deleted except by moving a whole profile to the
/// Recycle Bin.
/// </summary>
public sealed partial class ProfileManager
{
    public Layout Layout { get; }
    public TimeSpan QuitTimeout { get; set; } = TimeSpan.FromSeconds(60);
    /// <summary>Below this much free space on the drive with Zalo's data, Zalo risks failing to save messages.</summary>
    public long LowSpaceThreshold { get; set; } = 5_000_000_000;
    /// <summary>How removed profiles leave; tests replace it so they don't fill the real Recycle Bin.</summary>
    public Func<string, string?> MoveToTrash { get; set; } = path =>
    {
        if (!Native.MoveToRecycleBin(path) || Directory.Exists(path)) throw ProfileError.TrashFailed(path);
        return null;
    };
    /// <summary>Free space on the drive holding a path; tests replace it to fake a full drive.</summary>
    public Func<string, long?> FreeSpaceProvider { get; set; } = Disk.FreeBytes;
    /// <summary>The space a data folder takes; the demo replaces it to show realistic sizes.</summary>
    public Func<string, long?> SizeProvider { get; set; } = Disk.AllocatedSize;
    /// <summary>The usual user folders, linked into each profile folder so a Zalo of its own saves files
    /// where the person expects them: (name inside the home folder, real folder).</summary>
    public Func<IEnumerable<(string Name, string Target)>> UserFolders { get; set; }

    internal readonly IZaloControl Zalo;
    internal const string MarkerName = ".zalo-profile-id";
    readonly HashSet<string> _backingUp = [];

    public ProfileManager(Layout layout, IZaloControl zalo)
    {
        Layout = layout;
        Zalo = zalo;
        UserFolders = () => new[] { "Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos" }
            .Select(name => (name, Path.Combine(layout.RealHome, name)));
    }

    /// <summary>The manager for the real Zalo of the current Windows user.</summary>
    public static ProfileManager ForSystem()
    {
        var layout = Layout.System();
        var manager = new ProfileManager(layout, new SystemZaloControl(layout));
        manager.UserFolders = () => new[]
            {
                ("Desktop", Native.FolderDesktop), ("Documents", Native.FolderDocuments),
                ("Downloads", Native.FolderDownloads), ("Music", Native.FolderMusic),
                ("Pictures", Native.FolderPictures), ("Videos", Native.FolderVideos),
            }
            .Select(f => (f.Item1, Native.KnownFolder(f.Item2) ?? Path.Combine(layout.RealHome, f.Item1)));
        return manager;
    }

    // MARK: - Reading

    public List<Profile> Profiles()
    {
        if (!Directory.Exists(Layout.ProfilesRoot)) return [];
        return Directory.EnumerateDirectories(Layout.ProfilesRoot)
            .Select(path => LoadProfile(Path.GetFileName(path)))
            .OfType<Profile>()
            .OrderBy(p => p.Name, StringComparer.Create(CultureInfo.GetCultureInfo("vi-VN"), ignoreCase: true))
            .ToList();
    }

    public MainSlot GetMainSlot()
    {
        if (!Directory.Exists(Layout.LiveData)) return MainSlot.EmptySlot;
        if (ReadMarker(Layout.LiveData) is { } id && LoadProfile(id) != null) return new MainSlot.Saved(id);
        // Zalo may have removed the marker (for example after a log out); fall back to the last switch.
        if (LoadState().Main is { } last && LoadProfile(last) != null && !Exists(Layout.ParkedData(last)))
            return new MainSlot.Saved(last);
        return MainSlot.UnsavedSlot;
    }

    public List<ProfileStatus> Statuses()
    {
        var main = GetMainSlot();
        return Profiles().Select(profile =>
        {
            Place place;
            string? data;
            if (main.IsProfile(profile.Id)) (place, data) = (Place.Main, Layout.LiveData);
            else if (Directory.Exists(Layout.ParkedData(profile.Id))) (place, data) = (Place.Parked, Layout.ParkedData(profile.Id));
            else (place, data) = (Place.New, null);
            return new ProfileStatus(profile, place,
                                     data == null ? null : Zalo.PidUsing(data),
                                     data == null ? null : ZaloUserId(data),
                                     data);
        }).ToList();
    }

    /// <summary>Free space on the drive with Zalo's data and the profiles.</summary>
    public long? FreeSpace() => FreeSpaceProvider(Layout.RoamingAppData);

    /// <summary>A warning when that drive is nearly full, otherwise null.</summary>
    public string? LowSpaceWarning()
    {
        if (FreeSpace() is not { } free || free >= LowSpaceThreshold) return null;
        var drive = Path.GetPathRoot(Layout.RoamingAppData)?.TrimEnd('\\') ?? "";
        return $"Ổ {drive} chỉ còn trống {Disk.Format(free)}. Zalo cần chỗ để lưu tin nhắn và ảnh; hãy giải phóng dung lượng trước khi thêm hoặc mở thêm tài khoản.";
    }

    /// <summary>The space a profile's data takes on disk (null for a profile that has never been opened).</summary>
    public long? DataSize(ProfileStatus status) => status.DataFolder == null ? null : SizeProvider(status.DataFolder);

    public ProfileStatus? Status(string id) => Statuses().FirstOrDefault(s => s.Profile.Id == id);

    /// <summary>The pid of the normal Zalo app (the one using the main `ZaloData` folder), if it is running.</summary>
    public int? MainZaloPid() => Zalo.PidUsing(Layout.LiveData);

    /// <summary>The Zalo account id used most recently in the main `ZaloData` folder.</summary>
    public string? MainZaloUserId() => ZaloUserId(Layout.LiveData);

    /// <summary>Finds a profile by id, or by name ignoring case and accents.</summary>
    public Profile Find(string query)
    {
        var all = Profiles();
        if (all.FirstOrDefault(p => p.Id == query) is { } exact) return exact;
        var matches = all.Where(p => SameName(p.Name, query)).ToList();
        if (matches.Count == 0) throw ProfileError.NotFound(query);
        if (matches.Count > 1) throw ProfileError.Ambiguous(query);
        return matches[0];
    }

    // MARK: - Changing

    /// <summary>Saves the account that is in Zalo now as a profile. Zalo keeps running.</summary>
    public Profile SaveCurrent(string name)
    {
        switch (GetMainSlot())
        {
            case MainSlot.Empty: throw ProfileError.NothingToSave();
            case MainSlot.Saved saved: throw ProfileError.AlreadySaved(LoadProfile(saved.Id)?.Name ?? saved.Id);
        }
        var profile = CreateProfile(name);
        try { WriteMarker(profile.Id, Layout.LiveData); } catch { }
        SaveState(new State { Main = profile.Id });
        return profile;
    }

    /// <summary>Adds an empty profile. The first time it is opened, Zalo starts at the login screen.</summary>
    public Profile AddProfile(string name) => CreateProfile(name);

    public void Rename(string id, string name)
    {
        var profile = LoadProfile(id) ?? throw ProfileError.NotFound(id);
        SaveProfile(profile with { Name = ValidName(name, ignoring: id) });
    }

    /// <summary>Moves a profile and its Zalo data to the Recycle Bin, where it can still be restored.</summary>
    public string? Remove(string id)
    {
        var status = Status(id) ?? throw ProfileError.NotFound(id);
        if (status.Place == Place.Main) throw ProfileError.IsInMainZalo(status.Profile.Name);
        if (status.IsOpen) throw ProfileError.IsOpen(status.Profile.Name);
        RefuseIfBackingUp(status.Profile);
        var home = Layout.ProfileHome(id);
        // The links to the user's folders go first, so nothing can ever reach through them.
        RemoveLinks(home);
        return MoveToTrash(home);
    }

    /// <summary>Opens a profile in a Zalo window of its own, next to any that are already open, or brings
    /// its window forward. A new profile opens at the login screen; while the main slot is empty, it goes
    /// there, so the normal Zalo app has an account.</summary>
    public void Open(string id)
    {
        var status = Status(id) ?? throw ProfileError.NotFound(id);
        RequireZaloInstalled();
        RefuseIfBackingUp(status.Profile);
        if (status.RunningPid is { } pid)
        {
            Zalo.Activate(status.DataFolder!, pid);
            return;
        }
        RefuseConflicts(status);
        switch (status.Place)
        {
            case Place.Main:
                Zalo.LaunchMain(Layout.ZaloLauncher);
                break;
            case Place.New when GetMainSlot() is MainSlot.Empty:
                SwitchTo(id);
                break;
            default:
                PrepareHome(id);
                Zalo.LaunchIsolated(Layout.ZaloLauncher, Layout.ProfileHome(id));
                break;
        }
        Touch(status.Profile);
    }

    /// <summary>Opens every profile that has been logged in and isn't open yet. Skips a profile holding
    /// the same Zalo account as one that is open. The normal Zalo opens last. Returns the names opened.</summary>
    public List<string> OpenAll(Action<string>? progress = null)
    {
        var all = Statuses();
        var openAccounts = all.Where(s => s.IsOpen).Select(s => s.ZaloUserId).OfType<string>().ToHashSet();
        if (GetMainSlot() is MainSlot.Unsaved && MainZaloPid() != null && MainZaloUserId() is { } uid) openAccounts.Add(uid);
        var closed = all.Where(s => !s.IsOpen && s.Place != Place.New).ToList();
        var opened = new List<string>();
        Exception? firstError = null;
        foreach (var status in closed.Where(s => s.Place != Place.Main).Concat(closed.Where(s => s.Place == Place.Main)))
        {
            if (status.ZaloUserId is { } account && !openAccounts.Add(account)) continue;
            progress?.Invoke($"Đang mở {status.Profile.Name}…");
            try
            {
                Open(status.Profile.Id);
                opened.Add(status.Profile.Name);
            }
            catch (Exception error)
            {
                firstError ??= error;
            }
        }
        if (firstError != null) throw firstError;
        return opened;
    }

    /// <summary>Quits the Zalo window that has this profile open, like choosing Thoát in Zalo.</summary>
    public void Close(string id)
    {
        var status = Status(id) ?? throw ProfileError.NotFound(id);
        if (status.DataFolder is not { } data || !status.IsOpen) return;
        Zalo.Quit(data, QuitTimeout);
    }

    /// <summary>Quits every Zalo window, including a normal Zalo holding an account that isn't saved.</summary>
    public void CloseAll(Action<string>? progress = null)
    {
        foreach (var status in Statuses().Where(s => s.IsOpen))
        {
            progress?.Invoke($"Đang đóng {status.Profile.Name}…");
            Close(status.Profile.Id);
        }
        if (MainZaloPid() != null)
        {
            progress?.Invoke("Đang đóng Zalo…");
            Zalo.Quit(Layout.LiveData, QuitTimeout);
        }
    }

    /// <summary>Makes <paramref name="id"/> the profile the normal Zalo app opens, from its shortcuts or
    /// when Windows starts. The windows of <paramref name="id"/> and of the current main profile close for
    /// a few seconds while their folders swap places, then open again; every other window keeps running.</summary>
    public void MakeMain(string id, Action<string>? progress = null)
    {
        var target = Status(id) ?? throw ProfileError.NotFound(id);
        if (target.Place == Place.Main) return;
        RequireZaloInstalled();
        var slot = GetMainSlot();
        if (slot is MainSlot.Unsaved) throw ProfileError.CurrentDataNotSaved();
        var previous = (slot as MainSlot.Saved)?.Id;
        var previousWasOpen = previous != null && MainZaloPid() != null;

        try
        {
            if (target.IsOpen && target.DataFolder is { } data)
            {
                progress?.Invoke($"Đang đóng {target.Profile.Name}…");
                Zalo.Quit(data, QuitTimeout);
                if (Zalo.PidUsing(data) != null) throw ProfileError.ZaloDidNotQuit();
            }
            SwitchTo(id, progress: progress);
        }
        catch
        {
            // Open again whatever was open, wherever its data is now.
            if (target.IsOpen) { try { Open(id); } catch { } }
            if (previousWasOpen) { try { Open(previous!); } catch { } }
            throw;
        }
        if (previousWasOpen)
        {
            progress?.Invoke($"Đang mở lại {LoadProfile(previous!)?.Name ?? previous}…");
            Open(previous!);
        }
    }

    /// <summary>Moves <paramref name="id"/> into the main slot: quits the normal Zalo, moves the current
    /// profile's data into its profile folder, moves <paramref name="id"/>'s data into `ZaloData`, and starts
    /// Zalo again. Refuses while <paramref name="id"/> is open in a window of its own; <see cref="MakeMain"/>
    /// closes and reopens windows around this.</summary>
    public void SwitchTo(string id, bool launch = true, Action<string>? progress = null)
    {
        var target = LoadProfile(id) ?? throw ProfileError.NotFound(id);
        if (launch) RequireZaloInstalled();
        RefuseIfBackingUp(target);
        var slot = GetMainSlot();

        if (slot.IsProfile(id))
        {
            if (launch)
            {
                if (MainZaloPid() is { } pid) Zalo.Activate(Layout.LiveData, pid);
                else Zalo.LaunchMain(Layout.ZaloLauncher);
            }
            return;
        }
        if (slot is MainSlot.Unsaved) throw ProfileError.CurrentDataNotSaved();
        if (Zalo.PidUsing(Layout.ParkedData(id)) != null) throw ProfileError.IsOpen(target.Name);
        if (slot is MainSlot.Saved current && LoadProfile(current.Id) is { } currentProfile) RefuseIfBackingUp(currentProfile);

        if (MainZaloPid() != null)
        {
            progress?.Invoke("Đang thoát Zalo…");
            Zalo.Quit(Layout.LiveData, QuitTimeout);
            if (MainZaloPid() != null) throw ProfileError.ZaloDidNotQuit();
        }

        string? parked = null;
        if (slot is MainSlot.Saved saved)
        {
            progress?.Invoke($"Đang cất dữ liệu của {LoadProfile(saved.Id)?.Name ?? saved.Id}…");
            var destination = Layout.ParkedData(saved.Id);
            if (ExistsOrLink(destination))
                throw ProfileError.Conflict($"{destination} đã tồn tại, nên {Layout.LiveData} được giữ nguyên.");
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            Move(Layout.LiveData, destination);
            parked = saved.Id;
        }

        progress?.Invoke($"Đang đưa {target.Name} vào Zalo…");
        var source = Layout.ParkedData(id);
        if (Directory.Exists(source))
        {
            try
            {
                Move(source, Layout.LiveData);
            }
            catch
            {
                // Put the previous profile back, so Zalo opens as it was.
                if (parked != null) { try { Move(Layout.ParkedData(parked), Layout.LiveData); } catch { } }
                throw;
            }
        }
        else
        {
            // A new profile: an empty folder makes Zalo start at the login screen.
            Directory.CreateDirectory(Layout.LiveData);
        }
        try { WriteMarker(id, Layout.LiveData); } catch { }
        SaveState(new State { Main = id });
        Touch(target);

        if (launch)
        {
            progress?.Invoke("Đang mở Zalo…");
            Zalo.LaunchMain(Layout.ZaloLauncher);
        }
    }

    // MARK: - Helpers

    /// <summary>Two windows on one Zalo account would share one login session, which Zalo may end or
    /// flag; this happens with a restored backup of an account that is still in the list. On Windows, Zalo
    /// can also keep messages outside the data folder (Cài đặt → Dữ liệu); two Zalos must not share that.</summary>
    internal void RefuseConflicts(ProfileStatus status)
    {
        var open = Statuses().Where(s => s.Profile.Id != status.Profile.Id && s.IsOpen).ToList();
        var mainUnsavedOpen = GetMainSlot() is MainSlot.Unsaved && MainZaloPid() != null;
        // Checked first: profiles sharing a messages folder also look like the same account, since the
        // account is read from that folder.
        if (status.DataFolder != null && ExternalMessagesFolder(status.DataFolder) is { } folder)
        {
            var key = SystemZaloControl.Normalize(folder);
            foreach (var other in open)
            {
                if (ExternalMessagesFolder(other.DataFolder!) is { } theirs && SystemZaloControl.Normalize(theirs) == key)
                    throw ProfileError.SharedStorageOpen(status.Profile.Name, other.Profile.Name, folder);
            }
            if (mainUnsavedOpen && ExternalMessagesFolder(Layout.LiveData) is { } mainFolder
                && SystemZaloControl.Normalize(mainFolder) == key)
                throw ProfileError.SharedStorageOpen(status.Profile.Name, "Zalo chính", folder);
        }
        if (status.ZaloUserId is { } uid)
        {
            if (open.FirstOrDefault(s => s.ZaloUserId == uid) is { } other)
                throw ProfileError.SameAccountOpen(status.Profile.Name, other.Profile.Name);
            if (mainUnsavedOpen && MainZaloUserId() == uid)
                throw ProfileError.SameAccountOpen(status.Profile.Name, "Zalo chính");
        }
    }

    /// <summary>Gets a profile folder ready to be used as the home folder of a Zalo of its own.</summary>
    internal void PrepareHome(string id)
    {
        var data = Layout.ParkedData(id);
        if (!Exists(data))
        {
            Directory.CreateDirectory(data);
            try { WriteMarker(id, data); } catch { }
        }
        var home = Layout.ProfileHome(id);
        Directory.CreateDirectory(Path.Combine(home, "AppData", "Local", "Temp"));
        // Share the usual user folders, so files Zalo saves land where the person looks for them.
        foreach (var (name, target) in UserFolders())
        {
            var link = Path.Combine(home, name);
            if (!Directory.Exists(target) || ExistsOrLink(link)) continue;
            Native.CreateJunction(link, target);
        }
    }

    /// <summary>Removes the junctions in a profile folder (only the links, never what they point to).</summary>
    internal static void RemoveLinks(string home)
    {
        if (!Directory.Exists(home)) return;
        var pending = new Stack<string>([home]);
        while (pending.TryPop(out var folder))
        {
            IEnumerable<string> children;
            try { children = Directory.EnumerateDirectories(folder).ToList(); }
            catch { continue; }
            foreach (var child in children)
            {
                if (new DirectoryInfo(child).Attributes.HasFlag(FileAttributes.ReparsePoint))
                    Directory.Delete(child, recursive: false);
                else
                    pending.Push(child);
            }
        }
    }

    internal Profile CreateProfile(string name)
    {
        var clean = ValidName(name, ignoring: null);
        var id = UniqueId(clean);
        Directory.CreateDirectory(Layout.ProfileHome(id));
        var profile = new Profile { Id = id, Name = clean, CreatedAt = DateTime.UtcNow };
        SaveProfile(profile);
        return profile;
    }

    internal string ValidName(string name, string? ignoring)
    {
        var clean = name.Trim();
        if (clean.Length == 0) throw ProfileError.EmptyName();
        if (Profiles().Any(p => p.Id != ignoring && SameName(p.Name, clean))) throw ProfileError.NameTaken(clean);
        return clean;
    }

    internal static bool SameName(string a, string b) => Fold(a) == Fold(b);

    /// <summary>Lower case without accents; "đ" counts as "d".</summary>
    static string Fold(string text)
    {
        var decomposed = text.Replace('đ', 'd').Replace('Đ', 'D').Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) builder.Append(c);
        }
        return builder.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    /// <summary>A folder name made from the profile name, for example "Đức – Work" → "duc-work".</summary>
    internal string UniqueId(string name)
    {
        var folded = Fold(name);
        var slug = string.Join("-", new string(folded.Select(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' ? c : '-').ToArray())
            .Split('-', StringSplitOptions.RemoveEmptyEntries));
        var baseId = slug.Length == 0 ? "profile" : slug;
        var id = baseId;
        for (var n = 2; ExistsOrLink(Layout.ProfileHome(id)); n++) id = $"{baseId}-{n}";
        return id;
    }

    /// <summary>Where Zalo keeps the message databases of a data folder: the folder itself, or the place
    /// chosen in Zalo's settings (config.json → db_path.location), for example on another drive.</summary>
    internal static string MessagesRoot(string data)
    {
        try
        {
            using var config = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(data, "config.json")));
            if (config.RootElement.TryGetProperty("db_path", out var dbPath)
                && dbPath.TryGetProperty("location", out var location)
                && location.GetString() is { } path && Path.IsPathFullyQualified(path))
                return path;
        }
        catch { }
        return data;
    }

    /// <summary>The folder with a data folder's messages when it is outside the data folder, else null.</summary>
    public static string? ExternalMessagesFolder(string data)
    {
        var root = MessagesRoot(data);
        var inside = SystemZaloControl.Normalize(data) + "\\";
        return (SystemZaloControl.Normalize(root) + "\\").StartsWith(inside, StringComparison.Ordinal) ? null : root;
    }

    internal static string? ZaloUserId(string data)
    {
        var db = Path.Combine(MessagesRoot(data), "Database", "_production");
        if (!Directory.Exists(db)) return null;
        try
        {
            return new DirectoryInfo(db).EnumerateDirectories()
                .Where(d => d.Name.Length >= 6 && d.Name.All(char.IsAsciiDigit))
                .MaxBy(d => d.LastWriteTimeUtc)?.Name;
        }
        catch { return null; }
    }

    void RequireZaloInstalled()
    {
        if (!File.Exists(Layout.ZaloLauncher)) throw ProfileError.ZaloNotInstalled(Layout.ZaloLauncher);
    }

    internal void RefuseIfBackingUp(Profile profile)
    {
        lock (_backingUp)
        {
            if (_backingUp.Contains(profile.Id)) throw ProfileError.BeingBackedUp(profile.Name);
        }
    }

    /// <summary>Renames a folder. Refuses to replace anything at the destination, and refuses to copy
    /// across drives (MoveFileEx fails instead), so a half-finished move can't happen. Retries for a few
    /// seconds while another program (an antivirus scan, a closing Zalo helper) still has a file open.</summary>
    internal static void Move(string from, string to)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (true)
        {
            var error = Native.RenameExclusive(from, to);
            if (error == 0) return;
            var busy = error is Native.ERROR_ACCESS_DENIED or Native.ERROR_SHARING_VIOLATION;
            if (busy && DateTime.UtcNow < deadline && !ExistsOrLink(to))
            {
                Thread.Sleep(500);
                continue;
            }
            var reason = error switch
            {
                Native.ERROR_ALREADY_EXISTS or Native.ERROR_FILE_EXISTS => "đã có thư mục khác ở đó",
                Native.ERROR_NOT_SAME_DEVICE => "hai nơi nằm trên hai ổ đĩa khác nhau",
                Native.ERROR_ACCESS_DENIED or Native.ERROR_SHARING_VIOLATION =>
                    "một chương trình khác đang mở tệp trong thư mục (ví dụ File Explorer, phần mềm diệt virus hoặc Zalo)",
                _ => Native.Describe(error),
            };
            throw ProfileError.MoveFailed(from, to, reason);
        }
    }

    void Touch(Profile profile)
    {
        try { SaveProfile(profile with { LastUsedAt = DateTime.UtcNow }); } catch { }
    }

    internal Profile? LoadProfile(string id)
    {
        var profile = Json.Read<Profile>(Layout.ProfileFile(id));
        return profile?.Id == id ? profile : null;
    }

    internal void SaveProfile(Profile profile) => Json.Write(Layout.ProfileFile(profile.Id), profile);

    State LoadState() => Json.Read<State>(Layout.StateFile) ?? new State();

    void SaveState(State state)
    {
        Directory.CreateDirectory(Layout.ProfilesRoot);
        Json.Write(Layout.StateFile, state);
    }

    internal static string? ReadMarker(string data)
    {
        try
        {
            var id = File.ReadAllText(Path.Combine(data, MarkerName), Encoding.UTF8).Trim();
            return id.Length == 0 ? null : id;
        }
        catch { return null; }
    }

    internal static void WriteMarker(string id, string data)
    {
        var path = Path.Combine(data, MarkerName);
        File.WriteAllText(path + ".tmp", id + "\n", new UTF8Encoding(false));
        File.Move(path + ".tmp", path, overwrite: true);
    }

    internal static bool Exists(string path) => File.Exists(path) || Directory.Exists(path);

    internal static bool ExistsOrLink(string path)
    {
        if (Exists(path)) return true;
        // FileInfo reports -1 (every flag) for a path with nothing at it.
        var attributes = new FileInfo(path).Attributes;
        return (int)attributes != -1 && attributes.HasFlag(FileAttributes.ReparsePoint);
    }
}
