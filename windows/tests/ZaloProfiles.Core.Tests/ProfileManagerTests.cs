using System.Text;
using ZaloProfiles.Core;

namespace ZaloProfiles.Core.Tests;

/// <summary>Pretends to be Zalo: tracks which data folders are "open", and like the real app creates
/// `ZaloData` when it starts without one.</summary>
public sealed class FakeZalo(Layout layout) : IZaloControl
{
    public readonly Dictionary<string, int> Open = new(StringComparer.OrdinalIgnoreCase);
    public List<string> Launches = [];
    public bool RefusesToQuit;
    int _nextPid = 1000;

    public void MarkOpen(string folder) => Open[Path.GetFullPath(folder)] = _nextPid++;

    public int? PidUsing(string dataFolder) => Open.TryGetValue(Path.GetFullPath(dataFolder), out var pid) ? pid : null;
    public bool AnyInstanceRunning() => Open.Count > 0;

    public void Quit(string dataFolder, TimeSpan timeout)
    {
        if (RefusesToQuit) throw ProfileError.ZaloDidNotQuit();
        Open.Remove(Path.GetFullPath(dataFolder));
        Launches.Add($"quit:{Path.GetFileName(dataFolder)}");
    }

    public void LaunchMain(string launcher)
    {
        Launches.Add("main");
        Directory.CreateDirectory(layout.LiveData);
        MarkOpen(layout.LiveData);
    }

    public void LaunchIsolated(string launcher, string home)
    {
        Launches.Add($"isolated:{Path.GetFileName(home)}");
        MarkOpen(Layout.DataInHome(home));
    }

    public void Activate(string dataFolder, int pid) => Launches.Add($"activate:{pid}");
}

public partial class ProfileManagerTests : IDisposable
{
    protected readonly string Root;
    protected readonly Layout Layout;
    protected readonly FakeZalo Zalo;
    protected readonly ProfileManager Manager;
    protected readonly List<string> Trashed = [];

    public ProfileManagerTests()
    {
        Root = Path.Combine(Path.GetTempPath(), $"zalo-profiles-tests-{Guid.NewGuid():N}");
        Layout = Layout.InFolder(Root);
        Directory.CreateDirectory(Layout.RoamingAppData);
        Directory.CreateDirectory(Layout.LocalAppData);
        Directory.CreateDirectory(Path.GetDirectoryName(Layout.ZaloLauncher)!);
        File.WriteAllText(Layout.ZaloLauncher, "");
        Zalo = new FakeZalo(Layout);
        Manager = new ProfileManager(Layout, Zalo) { FreeSpaceProvider = _ => 100_000_000_000 };
        Manager.MoveToTrash = path =>
        {
            var destination = Path.Combine(Root, $"Trash-{Path.GetFileName(path)}");
            Directory.Move(path, destination);
            Trashed.Add(destination);
            return destination;
        };
    }

    public void Dispose()
    {
        try
        {
            // Remove junctions first so a failed test can never reach through them.
            foreach (var home in Directory.Exists(Layout.ProfilesRoot) ? Directory.GetDirectories(Layout.ProfilesRoot) : [])
                ProfileManager.RemoveLinks(home);
            Directory.Delete(Root, recursive: true);
        }
        catch { }
    }

    /// <summary>Puts an account's data in the main ZaloData folder, as a logged-in Zalo would leave it.</summary>
    protected void MakeLiveData(string account, bool running = true)
    {
        var db = Path.Combine(Layout.LiveData, "Database", "_production", account);
        Directory.CreateDirectory(db);
        File.WriteAllText(Path.Combine(db, "Message.db"), $"messages of {account}");
        File.WriteAllText(Path.Combine(Layout.LiveData, "Cookies"), $"session of {account}");
        if (running) Zalo.MarkOpen(Layout.LiveData);
    }

    /// <summary>Gives a saved profile its own data, as if it had been logged in before.</summary>
    protected Profile MakeParkedProfile(string name, string account)
    {
        var profile = Manager.AddProfile(name);
        var data = Layout.ParkedData(profile.Id);
        Directory.CreateDirectory(Path.Combine(data, "Database", "_production", account));
        File.WriteAllText(Path.Combine(data, "Cookies"), $"session of {account}");
        ProfileManager.WriteMarker(profile.Id, data);
        return profile;
    }

    protected string? LiveSession()
    {
        var path = Path.Combine(Layout.LiveData, "Cookies");
        return File.Exists(path) ? File.ReadAllText(path) : null;
    }

    protected static void AssertError(ProfileErrorKind kind, Action action, params string[] args)
    {
        var error = Assert.Throws<ProfileError>(action);
        Assert.Equal(kind, error.Kind);
        if (args.Length > 0) Assert.Equal(args, error.Args);
    }

    [Fact]
    public void SaveCurrent_RegistersTheDataThatIsInZalo()
    {
        MakeLiveData("111111");
        Assert.IsType<MainSlot.Unsaved>(Manager.GetMainSlot());

        var profile = Manager.SaveCurrent("Personal");

        Assert.Equal("personal", profile.Id);
        Assert.Equal(new MainSlot.Saved("personal"), Manager.GetMainSlot());
        var status = Manager.Status("personal")!;
        Assert.Equal(Place.Main, status.Place);
        Assert.Equal("111111", status.ZaloUserId);
        Assert.NotNull(status.RunningPid);
        Assert.Equal("session of 111111", LiveSession());
    }

    [Fact]
    public void SaveCurrent_RefusesWhenThereIsNothingOrItIsAlreadySaved()
    {
        AssertError(ProfileErrorKind.NothingToSave, () => Manager.SaveCurrent("X"));
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        AssertError(ProfileErrorKind.AlreadySaved, () => Manager.SaveCurrent("Other"), "Personal");
    }

    [Fact]
    public void ProfileFilesUseTheSharedFormat()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Cửa hàng");
        var json = File.ReadAllText(Path.Combine(Layout.ProfileHome("cua-hang"), "profile.json"), Encoding.UTF8);
        Assert.Matches("\"createdAt\": \"\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ\"", json);
        Assert.Contains("\"name\": \"Cửa hàng\"", json);
        Assert.DoesNotContain("lastUsedAt", json);
        Assert.Equal("{\n  \"main\": \"cua-hang\"\n}", File.ReadAllText(Path.Combine(Layout.ProfilesRoot, "state.json")).ReplaceLineEndings("\n"));
        Assert.Equal("cua-hang\n", File.ReadAllText(Path.Combine(Layout.LiveData, ".zalo-profile-id")));
    }

    [Fact]
    public void SwitchingToANewProfileParksTheCurrentOneAndStartsFresh()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = Manager.AddProfile("Work");
        Assert.Equal(Place.New, Manager.Status("work")!.Place);

        Manager.SwitchTo(work.Id);

        Assert.Equal(new MainSlot.Saved("work"), Manager.GetMainSlot());
        Assert.Null(LiveSession());
        Assert.Equal("session of 111111", File.ReadAllText(Path.Combine(Layout.ParkedData("personal"), "Cookies")));
        Assert.Equal(Place.Parked, Manager.Status("personal")!.Place);
        Assert.Equal(["quit:ZaloData", "main"], Zalo.Launches);
    }

    [Fact]
    public void SwitchingBackRestoresEachAccountsOwnDataUntouched()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        Manager.SwitchTo(Manager.AddProfile("Work").Id);
        // Log in to the second account in the fresh Zalo.
        MakeLiveData("222222");

        Manager.SwitchTo("personal");
        Assert.Equal("session of 111111", LiveSession());
        Assert.Equal("111111", Manager.Status("personal")!.ZaloUserId);
        Assert.Equal("222222", Manager.Status("work")!.ZaloUserId);

        Manager.SwitchTo("work");
        Assert.Equal("session of 222222", LiveSession());
        Assert.Equal("messages of 222222", File.ReadAllText(Path.Combine(Layout.LiveData, "Database", "_production", "222222", "Message.db")));
        Assert.False(Directory.Exists(Path.Combine(Layout.LiveData, "Database", "_production", "111111")), "accounts' data must not mix");
    }

    [Fact]
    public void SwitchRefusesWhileTheCurrentAccountIsUnsaved()
    {
        MakeLiveData("111111");
        var work = Manager.AddProfile("Work");
        AssertError(ProfileErrorKind.CurrentDataNotSaved, () => Manager.SwitchTo(work.Id));
        Assert.Equal("session of 111111", LiveSession());
        Assert.Empty(Zalo.Launches);
    }

    [Fact]
    public void NothingMovesWhenZaloWontQuit()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = Manager.AddProfile("Work");
        Zalo.RefusesToQuit = true;

        AssertError(ProfileErrorKind.ZaloDidNotQuit, () => Manager.SwitchTo(work.Id));

        Assert.Equal(new MainSlot.Saved("personal"), Manager.GetMainSlot());
        Assert.Equal("session of 111111", LiveSession());
        Assert.False(Directory.Exists(Layout.ParkedData("personal")));
    }

    [Fact]
    public void SwitchStopsIfTheParkingPlaceIsTaken()
    {
        MakeLiveData("111111", running: false);
        Manager.SaveCurrent("Personal");
        var work = Manager.AddProfile("Work");
        Directory.CreateDirectory(Layout.ParkedData("personal"));

        AssertError(ProfileErrorKind.Conflict, () => Manager.SwitchTo(work.Id));
        Assert.Equal("session of 111111", LiveSession());
    }

    [Fact]
    public void RenameNeverReplacesAFolder()
    {
        var from = Path.Combine(Root, "a");
        var to = Path.Combine(Root, "b");
        Directory.CreateDirectory(from);
        Directory.CreateDirectory(to);
        File.WriteAllText(Path.Combine(to, "keep"), "x");

        var error = Assert.Throws<ProfileError>(() => ProfileManager.Move(from, to));
        Assert.Equal(ProfileErrorKind.MoveFailed, error.Kind);
        Assert.True(File.Exists(Path.Combine(to, "keep")));
        Assert.True(Directory.Exists(from));
    }

    [Fact]
    public void SwitchToAProfileOpenInItsOwnWindowIsRefused()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var shop = Manager.AddProfile("Shop");
        Manager.Open(shop.Id);

        AssertError(ProfileErrorKind.IsOpen, () => Manager.SwitchTo(shop.Id), "Shop");
        Assert.Equal("session of 111111", LiveSession());
    }

    [Fact]
    public void MarkerLossFallsBackToTheLastSwitch()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        File.Delete(Path.Combine(Layout.LiveData, ProfileManager.MarkerName));
        Assert.Equal(new MainSlot.Saved("personal"), Manager.GetMainSlot());
    }

    [Fact]
    public void OpenPreparesASeparateHome()
    {
        var downloads = Path.Combine(Layout.RealHome, "Downloads");
        Directory.CreateDirectory(downloads);
        File.WriteAllText(Path.Combine(downloads, "file.txt"), "real");
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var shop = Manager.AddProfile("Shop");

        Manager.Open(shop.Id);

        var home = Layout.ProfileHome(shop.Id);
        Assert.True(Directory.Exists(Layout.ParkedData(shop.Id)));
        Assert.True(Directory.Exists(Path.Combine(home, "AppData", "Local", "Temp")));
        var link = new DirectoryInfo(Path.Combine(home, "Downloads"));
        Assert.True(link.Attributes.HasFlag(FileAttributes.ReparsePoint), "Downloads is a junction to the real folder");
        Assert.Equal("real", File.ReadAllText(Path.Combine(link.FullName, "file.txt")));
        Assert.False(Directory.Exists(Path.Combine(home, "Desktop")), "folders the real home doesn't have are not linked");
        Assert.Equal(["isolated:shop"], Zalo.Launches);
        Assert.True(Manager.Status(shop.Id)!.IsOpen);

        // Opening it again only brings it forward.
        Manager.Open(shop.Id);
        Assert.Equal(2, Zalo.Launches.Count);
        Assert.StartsWith("activate:", Zalo.Launches[1]);
    }

    [Fact]
    public void AccountsOpenAtTheSameTimeWithoutClosingTheMainZalo()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = MakeParkedProfile("Work", "222222");
        var shop = Manager.AddProfile("Shop");

        Manager.Open(work.Id);
        Manager.Open(shop.Id);

        Assert.Equal(["isolated:work", "isolated:shop"], Zalo.Launches);
        Assert.Equal(["personal", "shop", "work"], Manager.Statuses().Where(s => s.IsOpen).Select(s => s.Profile.Id));
        Assert.Equal("session of 111111", LiveSession());
        Assert.Equal(Place.Parked, Manager.Status("work")!.Place);
    }

    [Fact]
    public void TheFirstNewAccountGoesIntoTheEmptyMainSlot()
    {
        var personal = Manager.AddProfile("Personal");
        Manager.Open(personal.Id);
        Assert.Equal(new MainSlot.Saved("personal"), Manager.GetMainSlot());
        Assert.Equal(["main"], Zalo.Launches);

        // Once the main slot has an account, new ones open in windows of their own.
        var work = Manager.AddProfile("Work");
        Manager.Open(work.Id);
        Assert.Equal(["main", "isolated:work"], Zalo.Launches);
        Assert.Equal(new MainSlot.Saved("personal"), Manager.GetMainSlot());
    }

    [Fact]
    public void OpenAllOpensLoggedInAccountsWithTheMainZaloLast()
    {
        MakeLiveData("111111", running: false);
        Manager.SaveCurrent("Personal");
        MakeParkedProfile("Work", "222222");
        MakeParkedProfile("Work copy", "222222");
        Manager.AddProfile("Shop");

        var opened = Manager.OpenAll();

        Assert.Equal(["Work", "Personal"], opened);
        Assert.Equal(["isolated:work", "main"], Zalo.Launches);
        Assert.Empty(Manager.OpenAll());
    }

    [Fact]
    public void AZaloAccountOpensInOneWindowOnly()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = MakeParkedProfile("Work", "222222");
        var copy = MakeParkedProfile("Work copy", "222222");
        Manager.Open(work.Id);

        AssertError(ProfileErrorKind.SameAccountOpen, () => Manager.Open(copy.Id), "Work copy", "Work");
        Assert.Equal(["isolated:work"], Zalo.Launches);
    }

    [Fact]
    public void TwoZalosNeverShareMessagesStoredOnAnotherDrive()
    {
        var shared = Path.Combine(Root, "G", "Zalo Data", "message");
        Directory.CreateDirectory(Path.Combine(shared, "Database", "_production", "222222"));
        var config = $"{{ \"db_path\": {{ \"location\": \"{shared.Replace("\\", "\\\\")}\" }} }}";
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = MakeParkedProfile("Work", "222222");
        var shop = MakeParkedProfile("Shop", "333333");
        File.WriteAllText(Path.Combine(Layout.ParkedData(work.Id), "config.json"), config);
        File.WriteAllText(Path.Combine(Layout.ParkedData(shop.Id), "config.json"), config);
        Assert.Equal(shared, ProfileManager.ExternalMessagesFolder(Layout.ParkedData(work.Id)));
        Assert.Equal("222222", Manager.Status(work.Id)!.ZaloUserId);

        Manager.Open(work.Id);
        AssertError(ProfileErrorKind.SharedStorageOpen, () => Manager.Open(shop.Id));
        AssertError(ProfileErrorKind.MessagesStoredElsewhere, () => Manager.Backup(work.Id, Root));
    }

    [Fact]
    public void MakeMainSwapsTheFoldersAndKeepsBothAccountsOpen()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = MakeParkedProfile("Work", "222222");
        var shop = MakeParkedProfile("Shop", "333333");
        Manager.Open(work.Id);
        Manager.Open(shop.Id);
        Zalo.Launches = [];

        Manager.MakeMain(work.Id);

        Assert.Equal(new MainSlot.Saved("work"), Manager.GetMainSlot());
        Assert.Equal("session of 222222", LiveSession());
        Assert.Equal(Place.Parked, Manager.Status("personal")!.Place);
        Assert.Equal(["quit:ZaloData", "quit:ZaloData", "main", "isolated:personal"], Zalo.Launches);
        Assert.Equal(["personal", "shop", "work"], Manager.Statuses().Where(s => s.IsOpen).Select(s => s.Profile.Id));
    }

    [Fact]
    public void MakeMainRefusesWhileTheMainZaloHoldsAnUnsavedAccount()
    {
        MakeLiveData("111111");
        var work = MakeParkedProfile("Work", "222222");
        AssertError(ProfileErrorKind.CurrentDataNotSaved, () => Manager.MakeMain(work.Id));
        Assert.Equal("session of 111111", LiveSession());
        Assert.Empty(Zalo.Launches);
    }

    [Fact]
    public void CloseAllQuitsEveryWindow()
    {
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        Manager.Open(MakeParkedProfile("Work", "222222").Id);

        Manager.CloseAll();

        Assert.All(Manager.Statuses(), s => Assert.False(s.IsOpen));
        Assert.Null(Manager.MainZaloPid());
    }

    [Fact]
    public void RemoveMovesParkedProfilesToTheTrashOnlyAndKeepsTheLinkedFolders()
    {
        var downloads = Path.Combine(Layout.RealHome, "Downloads");
        Directory.CreateDirectory(downloads);
        File.WriteAllText(Path.Combine(downloads, "file.txt"), "real");
        MakeLiveData("111111");
        Manager.SaveCurrent("Personal");
        var work = Manager.AddProfile("Work");
        Manager.Open(work.Id);
        Manager.Close(work.Id);

        AssertError(ProfileErrorKind.IsInMainZalo, () => Manager.Remove("personal"), "Personal");
        Manager.Remove(work.Id);

        Assert.Equal(["personal"], Manager.Profiles().Select(p => p.Id));
        Assert.Single(Trashed);
        Assert.True(File.Exists(Path.Combine(Trashed[0], "profile.json")));
        Assert.False(Directory.Exists(Path.Combine(Trashed[0], "Downloads")), "the junction is removed, not moved");
        Assert.Equal("real", File.ReadAllText(Path.Combine(downloads, "file.txt")));
    }

    [Fact]
    public void NamesAndIds()
    {
        var p = Manager.AddProfile("  Đức – Work ");
        Assert.Equal("duc-work", p.Id);
        Assert.Equal("Đức – Work", p.Name);
        Assert.Equal("duc-work", Manager.Find("đức – work").Id);
        Assert.Equal("duc-work", Manager.Find("duc-work").Id);
        AssertError(ProfileErrorKind.NameTaken, () => Manager.AddProfile("ĐỨC – WORK"), "ĐỨC – WORK");
        AssertError(ProfileErrorKind.EmptyName, () => Manager.AddProfile("   "));
        Assert.Equal("duc-work-2", Manager.AddProfile("Duc Work!").Id);
        Assert.Equal("cua-hang", Manager.AddProfile("Cửa hàng").Id);
        AssertError(ProfileErrorKind.NotFound, () => Manager.Find("nobody"), "nobody");

        Manager.Rename("cua-hang", "Shop");
        Assert.Equal("cua-hang", Manager.Find("shop").Id);
    }

    [Fact]
    public void UserDataDirIsReadFromHelperCommandLines()
    {
        Assert.Equal(@"C:\Users\a\AppData\Roaming\ZaloData", SystemZaloControl.UserDataDir(
            "\"C:\\Zalo\\Zalo.exe\" --type=renderer --user-data-dir=\"C:\\Users\\a\\AppData\\Roaming\\ZaloData\" --no-sandbox"));
        Assert.Null(SystemZaloControl.UserDataDir("\"C:\\Zalo\\Zalo.exe\""));
    }
}
