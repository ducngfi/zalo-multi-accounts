using System.Globalization;
using System.Text.Json;

namespace ZaloProfiles.Core;

/// <summary>A profile held for a backup (see <see cref="ProfileManager.PrepareBackup"/>). Disposing it lets
/// the profile be opened and moved again, and opens Zalo again if the backup closed it.</summary>
public sealed class BackupJob : IDisposable
{
    readonly ProfileManager _manager;
    readonly Action<string> _progress;
    bool _disposed;

    internal BackupJob(ProfileManager manager, ProfileStatus status, Action<string> progress)
    {
        _manager = manager;
        _progress = progress;
        Status = status;
        Data = status.DataFolder!;
    }

    public ProfileStatus Status { get; }
    internal string Data { get; }
    internal Action? Reopen { get; set; }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _manager.EndBackup(Status.Profile.Id);
        if (Reopen == null) return;
        _progress("Đang mở lại Zalo…");
        try { Reopen(); } catch { }
    }
}

/// <summary>A flag another thread can set to stop a long copy.</summary>
public sealed class CancelFlag
{
    volatile bool _cancelled;
    public bool IsCancelled => _cancelled;
    public void Cancel() => _cancelled = true;
}

public sealed partial class ProfileManager
{
    public const string BackupsFolderName = "Zalo Backups";
    internal const string RestorePrefix = ".restore-";

    /// <summary>Backs up a profile to `&lt;destination&gt;\Zalo Backups\&lt;id&gt; &lt;date&gt;\` and checks every file.
    /// Windows has no instant snapshot like APFS, so if Zalo has the profile open it is closed for the
    /// whole copy, so the databases are complete, and opened again afterwards.</summary>
    public string Backup(string id, string destination, Action<string>? progress = null, CancelFlag? cancel = null)
    {
        using var job = PrepareBackup(id, destination, progress);
        return WriteBackup(job, destination, progress, cancel);
    }

    /// <summary>The first, quick part of a backup: checks the destination, closes the profile's Zalo if it
    /// is open, and holds the profile so nothing opens or moves it until the job is disposed, which opens
    /// Zalo again. The app runs this with its other actions and the copy on its own.</summary>
    public BackupJob PrepareBackup(string id, string destination, Action<string>? progress = null)
    {
        progress ??= _ => { };
        CheckBackupDestination(id, destination);
        var status = Status(id)!;
        lock (_backingUp)
        {
            if (!_backingUp.Add(id)) throw ProfileError.BeingBackedUp(status.Profile.Name);
        }
        var job = new BackupJob(this, status, progress);
        try
        {
            if (status.RunningPid != null)
            {
                progress($"Đang tạm đóng Zalo của {status.Profile.Name}…");
                Zalo.Quit(job.Data, QuitTimeout);
                if (Zalo.PidUsing(job.Data) != null) throw ProfileError.ZaloDidNotQuit();
                var launcher = Layout.ZaloLauncher;
                var home = Layout.ProfileHome(id);
                job.Reopen = status.Place == Place.Main
                    ? () => Zalo.LaunchMain(launcher)
                    : () => Zalo.LaunchIsolated(launcher, home);
            }
            return job;
        }
        catch
        {
            job.Dispose();
            throw;
        }
    }

    internal void EndBackup(string id)
    {
        lock (_backingUp) _backingUp.Remove(id);
    }

    /// <summary>Whether <paramref name="path"/> is on the same drive as Zalo's data (so a backup there doesn't
    /// protect against that drive failing, and uses its free space).</summary>
    public bool IsOnZaloDrive(string path) => Disk.SameVolume(path, Layout.RoamingAppData);

    /// <summary>Checks that a profile can be backed up to <paramref name="destination"/> and that there is room for it.</summary>
    public void CheckBackupDestination(string id, string destination)
    {
        var status = Status(id) ?? throw ProfileError.NotFound(id);
        if (status.DataFolder is not { } data) throw ProfileError.NothingToBackUp(status.Profile.Name);
        if (ExternalMessagesFolder(data) is { } elsewhere) throw ProfileError.MessagesStoredElsewhere(status.Profile.Name, elsewhere);
        if (!Directory.Exists(destination) || !IsWritable(destination)) throw ProfileError.NotAFolder(destination);
        var target = SystemZaloControl.Normalize(destination) + "\\";
        foreach (var inside in new[] { Layout.ProfilesRoot, Layout.LiveData })
        {
            if (target.StartsWith(SystemZaloControl.Normalize(inside) + "\\", StringComparison.Ordinal))
                throw ProfileError.BadBackupFolder();
        }
        var needed = (Disk.AllocatedSize(data) ?? 0) + 100_000_000;
        if (FreeSpaceProvider(destination) is { } free && free < needed)
            throw ProfileError.NotEnoughSpace(destination, needed, free);
    }

    /// <summary>Copies a closed profile's data to `&lt;destination&gt;\Zalo Backups\&lt;id&gt; &lt;date&gt;\` and records it in
    /// backup.json. The copy is written under a `.partial` name and only gets its final name once every
    /// file has been checked; if anything fails or is cancelled, the unfinished copy is removed.</summary>
    public string WriteBackup(BackupJob job, string destination, Action<string>? progress = null, CancelFlag? cancel = null)
    {
        progress ??= _ => { };
        cancel ??= new CancelFlag();
        var (status, data) = (job.Status, job.Data);
        var root = Path.Combine(destination, BackupsFolderName);
        Directory.CreateDirectory(root);
        var stamp = DateTime.Now.ToString("yyyy-MM-dd HH.mm", CultureInfo.InvariantCulture);
        var baseName = $"{status.Profile.Id} {stamp}";
        var name = baseName;
        for (var n = 2; ExistsOrLink(Path.Combine(root, name)) || ExistsOrLink(Path.Combine(root, name + ".partial")); n++)
            name = $"{baseName} {n}";
        var final = Path.Combine(root, name);
        var partial = final + ".partial";
        Directory.CreateDirectory(partial);
        try
        {
            var copied = CopyTree(data, Path.Combine(partial, "ZaloData"), $"Đang sao lưu {status.Profile.Name}",
                                  progress, cancel);
            // Nothing may have written to the data while it was copied.
            if (Zalo.PidUsing(data) != null)
                throw ProfileError.Conflict($"Zalo của “{status.Profile.Name}” đã được mở trong lúc sao lưu, nên bản sao lưu đã không được giữ lại. Hãy thử lại.");
            var info = new BackupInfo
            {
                ProfileId = status.Profile.Id,
                ProfileName = status.Profile.Name,
                ZaloUserId = status.ZaloUserId,
                CreatedAt = DateTime.UtcNow,
                Files = copied.Files,
                Bytes = copied.Bytes,
                Links = copied.Links,
            };
            File.WriteAllBytes(Path.Combine(partial, "backup.json"), JsonSerializer.SerializeToUtf8Bytes(info, Json.Options));
            Directory.Move(partial, final);
            return final;
        }
        catch
        {
            try { Directory.Delete(partial, recursive: true); } catch { }
            throw;
        }
    }

    /// <summary>Reads the record of a backup folder, or throws if the folder isn't a backup.</summary>
    public BackupInfo ReadBackup(string folder)
    {
        if (Json.Read<BackupInfo>(Path.Combine(folder, "backup.json")) is not { } info
            || !Directory.Exists(Path.Combine(folder, "ZaloData")))
            throw ProfileError.NotABackup(folder);
        return info;
    }

    /// <summary>Restores a backup as a new profile called <paramref name="name"/>. It never replaces an
    /// existing profile. The copy is checked against backup.json before the profile appears.</summary>
    public Profile Restore(string folder, string name, Action<string>? progress = null, CancelFlag? cancel = null)
    {
        progress ??= _ => { };
        cancel ??= new CancelFlag();
        var info = ReadBackup(folder);
        var clean = ValidName(name, ignoring: null);
        // Leave Zalo the usual spare room after the restored data is in.
        var needed = info.Bytes + LowSpaceThreshold;
        if (FreeSpace() is { } free && free < needed)
            throw ProfileError.NotEnoughSpace($"ổ {Path.GetPathRoot(Layout.RoamingAppData)?.TrimEnd('\\')}", needed, free);
        RemoveStaleTemporaryFolders();
        Directory.CreateDirectory(Layout.ProfilesRoot);
        var staging = Path.Combine(Layout.ProfilesRoot,
            $"{RestorePrefix}{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}-{Guid.NewGuid():N}");
        try
        {
            var copied = CopyTree(Path.Combine(folder, "ZaloData"), staging, $"Đang khôi phục {clean}", progress, cancel);
            if (copied.Files != info.Files || copied.Bytes != info.Bytes)
                throw ProfileError.CopyMismatch($"bản sao lưu ({copied.Files} tệp, {Disk.Format(copied.Bytes)}; backup.json ghi {info.Files} tệp, {Disk.Format(info.Bytes)})");
            var profile = CreateProfile(clean);
            var target = Layout.ParkedData(profile.Id);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            Move(staging, target);
            try { WriteMarker(profile.Id, target); } catch { }
            return profile;
        }
        catch
        {
            try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); } catch { }
            throw;
        }
    }

    /// <summary>Copies a folder file by file, checking that each copy has the original's size. Files that
    /// are hard links to the same data are copied once and linked again, as in the original. Skips
    /// junctions, symbolic links and the "._" files some external drives add.</summary>
    internal static (int Files, long Bytes, int Links) CopyTree(string source, string destination, string label,
                                                                Action<string> progress, CancelFlag cancel)
    {
        if (!Directory.Exists(source)) throw ProfileError.CopyFailed(source, "không đọc được");
        var items = new List<(string Path, bool IsDirectory, long Size)>();
        var groups = new Dictionary<string, string>();
        var counted = new HashSet<string>();
        long total = 0;
        foreach (var (path, isDirectory, size) in Walk(source))
        {
            items.Add((path, isDirectory, size));
            if (isDirectory) continue;
            if (Native.HardLinkGroup(Path.Combine(source, path)) is { } group)
            {
                groups[path] = group;
                if (!counted.Add(group)) continue;
            }
            total += size;
        }

        Directory.CreateDirectory(destination);
        int files = 0, links = 0;
        long copied = 0;
        var firstCopy = new Dictionary<string, string>();
        var reported = -1;
        foreach (var item in items)
        {
            if (cancel.IsCancelled) throw ProfileError.Cancelled();
            var from = Path.Combine(source, item.Path);
            var to = Path.Combine(destination, item.Path);
            if (item.IsDirectory)
            {
                Directory.CreateDirectory(to);
                continue;
            }
            groups.TryGetValue(item.Path, out var group);
            try
            {
                if (group != null && firstCopy.TryGetValue(group, out var first) && Native.CreateHardLink(to, first))
                {
                    links++;
                }
                else
                {
                    // A drive that can't hard-link (exFAT, FAT32) gets a separate copy instead.
                    File.Copy(from, to, overwrite: false);
                    copied += item.Size;
                    if (group != null) firstCopy.TryAdd(group, to);
                }
            }
            catch (Exception error)
            {
                throw ProfileError.CopyFailed(item.Path, error.Message);
            }
            long? written = null;
            try { written = new FileInfo(to).Length; } catch { }
            if (written != item.Size) throw ProfileError.CopyMismatch(item.Path);
            files++;
            var percent = total > 0 ? (int)Math.Min(100, copied * 100 / total) : 100;
            if (percent != reported)
            {
                reported = percent;
                progress($"{label}… {percent}% ({Disk.Format(copied)} / {Disk.Format(total)})");
            }
        }
        return (files, copied, links);
    }

    /// <summary>Every folder and file under <paramref name="root"/>, folders before what they contain, as
    /// relative paths. Doesn't enter junctions or symbolic links.</summary>
    static IEnumerable<(string Path, bool IsDirectory, long Size)> Walk(string root)
    {
        var pending = new Stack<string>([""]);
        while (pending.TryPop(out var relative))
        {
            var folder = new DirectoryInfo(Path.Combine(root, relative));
            FileSystemInfo[] entries;
            try { entries = folder.GetFileSystemInfos(); }
            catch (Exception error) { throw ProfileError.CopyFailed(folder.FullName, error.Message); }
            var subfolders = new List<string>();
            foreach (var entry in entries.OrderBy(e => e.Name, StringComparer.Ordinal))
            {
                if (entry.Name.StartsWith("._", StringComparison.Ordinal)) continue;
                if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                var path = relative.Length == 0 ? entry.Name : Path.Combine(relative, entry.Name);
                if (entry is DirectoryInfo)
                {
                    yield return (path, true, 0);
                    subfolders.Add(path);
                }
                else if (entry is FileInfo file)
                {
                    yield return (path, false, file.Length);
                }
            }
            for (var i = subfolders.Count - 1; i >= 0; i--) pending.Push(subfolders[i]);
        }
    }

    /// <summary>Where Zalo keeps a data folder's received photos and files when that is outside it (Zalo's
    /// settings can put them on another drive). Backups don't include them.</summary>
    public static string? ExternalFilesFolder(string data)
    {
        try
        {
            using var config = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(data, "config.json")));
            if (config.RootElement.TryGetProperty("resource", out var resource)
                && resource.TryGetProperty("location", out var location)
                && location.TryGetProperty("path", out var pathValue)
                && pathValue.GetString() is { } path && Path.IsPathFullyQualified(path))
            {
                var inside = SystemZaloControl.Normalize(data) + "\\";
                return (SystemZaloControl.Normalize(path) + "\\").StartsWith(inside, StringComparison.Ordinal) ? null : path;
            }
        }
        catch { }
        return null;
    }

    /// <summary>Removes unfinished restores left behind by a crash more than 12 hours ago.</summary>
    internal void RemoveStaleTemporaryFolders()
    {
        if (!Directory.Exists(Layout.ProfilesRoot)) return;
        var cutoff = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 12 * 3600;
        foreach (var path in Directory.EnumerateDirectories(Layout.ProfilesRoot, RestorePrefix + "*"))
        {
            var name = Path.GetFileName(path);
            var stamp = name[RestorePrefix.Length..].Split('-')[0];
            if (long.TryParse(stamp, out var seconds) && seconds < cutoff)
            {
                try { Directory.Delete(path, recursive: true); } catch { }
            }
        }
    }

    static bool IsWritable(string folder)
    {
        try
        {
            var probe = Path.Combine(folder, $".zalo-switcher-{Guid.NewGuid():N}");
            File.WriteAllText(probe, "");
            File.Delete(probe);
            return true;
        }
        catch { return false; }
    }
}
