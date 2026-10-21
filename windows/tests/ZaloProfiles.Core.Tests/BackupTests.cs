using ZaloProfiles.Core;

namespace ZaloProfiles.Core.Tests;

public partial class ProfileManagerTests
{
    /// <summary>A folder standing in for the external drive.</summary>
    string MakeDrive()
    {
        var drive = Path.Combine(Root, "Drive");
        Directory.CreateDirectory(drive);
        return drive;
    }

    /// <summary>Personal in the main Zalo (running) and Work parked, each with a few files.</summary>
    void MakeTwoProfiles()
    {
        MakeLiveData("111111");
        var media = Path.Combine(Layout.LiveData, "media", "111111");
        Directory.CreateDirectory(media);
        File.WriteAllBytes(Path.Combine(media, "photo.jpg"), Enumerable.Repeat((byte)7, 200_000).ToArray());
        Manager.SaveCurrent("Personal");
        Manager.SwitchTo(Manager.AddProfile("Work").Id);
        MakeLiveData("222222");
        Manager.SwitchTo("personal");
        Zalo.Launches.Clear();
    }

    static Dictionary<string, byte[]> Contents(string folder) =>
        Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories)
            .ToDictionary(path => Path.GetRelativePath(folder, path), File.ReadAllBytes);

    List<string> Leftovers() =>
        Directory.Exists(Layout.ProfilesRoot)
            ? Directory.GetFileSystemEntries(Layout.ProfilesRoot).Select(Path.GetFileName).Where(n => n!.StartsWith('.')).ToList()!
            : [];

    static void AssertSameContents(Dictionary<string, byte[]> expected, Dictionary<string, byte[]> actual)
    {
        Assert.Equal(expected.Keys.Order(), actual.Keys.Order());
        foreach (var (path, bytes) in expected) Assert.Equal(bytes, actual[path]);
    }

    [Fact]
    public void StatusesSayWhereDataIsAndHowBigItIs()
    {
        MakeTwoProfiles();
        var personal = Manager.Status("personal")!;
        var work = Manager.Status("work")!;
        Assert.Equal(Layout.LiveData, personal.DataFolder);
        Assert.Equal(Layout.ParkedData("work"), work.DataFolder);
        Assert.True(Manager.DataSize(personal) >= 200_000);
        Assert.Null(Manager.DataSize(new ProfileStatus(personal.Profile, Place.New)));
    }

    [Fact]
    public void LowSpaceWarningBelowTheThreshold()
    {
        Manager.FreeSpaceProvider = _ => 6_000_000_000;
        Assert.Null(Manager.LowSpaceWarning());
        Manager.FreeSpaceProvider = _ => 3_000_000_000;
        Assert.NotNull(Manager.LowSpaceWarning());
    }

    [Fact]
    public void BackupOfAParkedProfileCopiesEverythingWithoutTouchingZalo()
    {
        MakeTwoProfiles();
        var drive = MakeDrive();

        var backup = Manager.Backup("work", drive);

        Assert.Equal("Zalo Backups", Path.GetFileName(Path.GetDirectoryName(backup)));
        Assert.StartsWith("work ", Path.GetFileName(backup));
        AssertSameContents(Contents(Layout.ParkedData("work")), Contents(Path.Combine(backup, "ZaloData")));
        var info = Manager.ReadBackup(backup);
        Assert.Equal("Work", info.ProfileName);
        Assert.Equal("222222", info.ZaloUserId);
        Assert.Equal(Contents(Layout.ParkedData("work")).Count, info.Files);
        Assert.Empty(Zalo.Launches);
        Assert.Empty(Leftovers());
        Assert.Empty(Directory.GetDirectories(Path.Combine(drive, "Zalo Backups"), "*.partial"));
    }

    [Fact]
    public void BackupOfTheOpenMainProfileClosesZaloForTheCopyAndReopensIt()
    {
        MakeTwoProfiles();

        var backup = Manager.Backup("personal", MakeDrive());

        Assert.Equal(["quit:ZaloData", "main"], Zalo.Launches);
        Assert.NotNull(Manager.MainZaloPid());
        Assert.Equal(200_000, Contents(Path.Combine(backup, "ZaloData"))[Path.Combine("media", "111111", "photo.jpg")].Length);
        Assert.Equal("session of 111111", LiveSession());
    }

    [Fact]
    public void BackupOfAProfileOpenInItsOwnWindowReopensItThere()
    {
        MakeTwoProfiles();
        Manager.Open("work");
        Zalo.Launches.Clear();

        Manager.Backup("work", MakeDrive());

        Assert.Equal(["quit:ZaloData", "isolated:work"], Zalo.Launches);
        Assert.True(Manager.Status("work")!.IsOpen);
    }

    [Fact]
    public void AProfileBeingBackedUpCannotBeOpenedOrMoved()
    {
        MakeTwoProfiles();
        var drive = MakeDrive();
        string? openError = null;

        Manager.Backup("personal", drive, progress: message =>
        {
            if (!message.Contains('%') || openError != null) return;
            try { Manager.Open("personal"); }
            catch (ProfileError error) { openError = error.Kind.ToString(); }
            AssertError(ProfileErrorKind.BeingBackedUp, () => Manager.MakeMain("work"));
        });

        Assert.Equal(nameof(ProfileErrorKind.BeingBackedUp), openError);
        Assert.Equal(new MainSlot.Saved("personal"), Manager.GetMainSlot());
    }

    [Fact]
    public void BackupRefusalsLeaveNothingBehind()
    {
        MakeTwoProfiles();
        var drive = MakeDrive();
        var empty = Manager.AddProfile("Empty");

        AssertError(ProfileErrorKind.NothingToBackUp, () => Manager.Backup(empty.Id, drive), "Empty");
        AssertError(ProfileErrorKind.BadBackupFolder, () => Manager.Backup("work", Layout.ProfileHome("personal")));
        AssertError(ProfileErrorKind.NotAFolder, () => Manager.Backup("work", Path.Combine(Root, "missing")));
        Manager.FreeSpaceProvider = _ => 1000;
        AssertError(ProfileErrorKind.NotEnoughSpace, () => Manager.Backup("work", drive));
        Assert.False(Directory.Exists(Path.Combine(drive, "Zalo Backups")));
        Assert.Empty(Zalo.Launches);
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void CancelledBackupRemovesTheUnfinishedCopy()
    {
        MakeTwoProfiles();
        var drive = MakeDrive();
        var cancel = new CancelFlag();
        cancel.Cancel();

        AssertError(ProfileErrorKind.Cancelled, () => Manager.Backup("personal", drive, cancel: cancel));
        Assert.Empty(Directory.GetFileSystemEntries(Path.Combine(drive, "Zalo Backups")));
        Assert.Empty(Leftovers());
        Assert.NotNull(Manager.MainZaloPid());
    }

    [Fact]
    public void RestoreAddsANewProfileAndNeverReplacesOne()
    {
        MakeTwoProfiles();
        var backup = Manager.Backup("work", MakeDrive());

        var restored = Manager.Restore(backup, "Work (restored)");

        Assert.Equal("work-restored", restored.Id);
        var status = Manager.Status(restored.Id)!;
        Assert.Equal(Place.Parked, status.Place);
        Assert.Equal("222222", status.ZaloUserId);
        var original = Contents(Layout.ParkedData("work"));
        var copy = Contents(Layout.ParkedData(restored.Id));
        Assert.Equal("work-restored\n"u8.ToArray(), copy[ProfileManager.MarkerName]);
        copy.Remove(ProfileManager.MarkerName);
        original.Remove(ProfileManager.MarkerName);
        AssertSameContents(original, copy);
        Assert.Equal(3, Manager.Profiles().Count);
        AssertError(ProfileErrorKind.NameTaken, () => Manager.Restore(backup, "Work"), "Work");
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void RestoreRejectsDamagedBackupsAndFullDisks()
    {
        MakeTwoProfiles();
        var backup = Manager.Backup("work", MakeDrive());

        Manager.FreeSpaceProvider = _ => 4_000_000_000;
        AssertError(ProfileErrorKind.NotEnoughSpace, () => Manager.Restore(backup, "Copy"));
        Manager.FreeSpaceProvider = _ => 100_000_000_000;

        File.Delete(Path.Combine(backup, "ZaloData", "Cookies"));
        AssertError(ProfileErrorKind.CopyMismatch, () => Manager.Restore(backup, "Copy"));
        AssertError(ProfileErrorKind.NotABackup, () => Manager.Restore(MakeDrive(), "Copy"));
        Assert.Equal(["personal", "work"], Manager.Profiles().Select(p => p.Id));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void HardLinkedFilesAreBackedUpAndRestoredOnceAndStayLinked()
    {
        MakeTwoProfiles();
        var big = Path.Combine(Layout.LiveData, "media", "111111", "video.mp4");
        File.WriteAllBytes(big, Enumerable.Repeat((byte)9, 1_000_000).ToArray());
        var other = Path.Combine(Layout.LiveData, "Database", "_production", "111111", "video-link.mp4");
        Assert.True(Native.CreateHardLink(other, big));

        var backup = Manager.Backup("personal", MakeDrive());

        var info = Manager.ReadBackup(backup);
        Assert.Equal(1, info.Links);
        var copy = Path.Combine(backup, "ZaloData");
        var a = Native.HardLinkGroup(Path.Combine(copy, "media", "111111", "video.mp4"));
        var b = Native.HardLinkGroup(Path.Combine(copy, "Database", "_production", "111111", "video-link.mp4"));
        Assert.NotNull(a);
        Assert.Equal(a, b);
        var all = Contents(copy);
        Assert.Equal(all.Values.Sum(v => (long)v.Length) - 1_000_000, info.Bytes);
        Assert.Equal(all.Count, info.Files);

        var restored = Manager.Restore(backup, "Personal copy");
        var data = Layout.ParkedData(restored.Id);
        var c = Native.HardLinkGroup(Path.Combine(data, "media", "111111", "video.mp4"));
        Assert.NotNull(c);
        Assert.Equal(c, Native.HardLinkGroup(Path.Combine(data, "Database", "_production", "111111", "video-link.mp4")));
        Assert.Equal(1_000_000, new FileInfo(Path.Combine(data, "media", "111111", "video.mp4")).Length);
    }

    [Fact]
    public void CloseQuitsOnlyThatProfilesWindow()
    {
        MakeTwoProfiles();
        Manager.Open("work");

        Manager.Close("work");

        Assert.False(Manager.Status("work")!.IsOpen);
        Assert.NotNull(Manager.MainZaloPid());
        Manager.Close("work");
    }

    [Fact]
    public void StaleTemporaryFoldersAreCleanedUpButRecentOnesKept()
    {
        Directory.CreateDirectory(Layout.ProfilesRoot);
        var old = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 13 * 3600;
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        foreach (var name in new[] { $".restore-{old}-b", $".restore-{now}-c" })
            Directory.CreateDirectory(Path.Combine(Layout.ProfilesRoot, name));
        Manager.RemoveStaleTemporaryFolders();
        Assert.Equal([$".restore-{now}-c"], Leftovers());
    }

    [Fact]
    public void SizesAreFormattedLikeTheMacApp()
    {
        Assert.Equal("640 MB", Disk.Format(640_000_000));
        Assert.Equal("8,42 GB", Disk.Format(8_420_000_000));
        Assert.Equal("64 KB", Disk.Format(64_000));
    }
}
