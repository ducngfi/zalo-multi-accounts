using Microsoft.Win32;

namespace ZaloProfiles.Core;

/// <summary>
/// Where Zalo and the saved profiles live on disk.
///
/// Zalo for Windows keeps its data in <c>%APPDATA%\ZaloData</c>. Each profile is a folder under
/// <c>%LOCALAPPDATA%\Zalo Profiles\&lt;id&gt;\</c> shaped like a home folder, so a parked profile's
/// data sits at <c>&lt;id&gt;\AppData\Roaming\ZaloData</c>. That shape lets the same folder be used as
/// a separate home (USERPROFILE) when a profile is opened side by side.
/// </summary>
public sealed record Layout(string RealHome, string RoamingAppData, string LocalAppData, string ZaloLauncher)
{
    /// <summary>The folder the normal Zalo app reads and writes.</summary>
    public string LiveData => Path.Combine(RoamingAppData, "ZaloData");

    public string ProfilesRoot => Path.Combine(LocalAppData, "Zalo Profiles");

    internal string StateFile => Path.Combine(ProfilesRoot, "state.json");

    public string ProfileHome(string id) => Path.Combine(ProfilesRoot, id);

    internal string ProfileFile(string id) => Path.Combine(ProfileHome(id), "profile.json");

    /// <summary>Where a profile's Zalo data is kept while it is not in the main slot.</summary>
    public string ParkedData(string id) => DataInHome(ProfileHome(id));

    /// <summary>The data folder Zalo uses when <paramref name="home"/> is its USERPROFILE.</summary>
    public static string DataInHome(string home) => Path.Combine(home, "AppData", "Roaming", "ZaloData");

    /// <summary>A layout inside one folder, for tests and the demo.</summary>
    public static Layout InFolder(string root)
    {
        var home = Path.Combine(root, "home");
        return new Layout(home, Path.Combine(home, "AppData", "Roaming"), Path.Combine(home, "AppData", "Local"),
                          Path.Combine(root, "Zalo", "Zalo.exe"));
    }

    /// <summary>The real layout of the current user. The home folder comes from Windows rather than
    /// %USERPROFILE%, so a stray override can't point the tool at the wrong folder.</summary>
    public static Layout System()
    {
        var home = Native.KnownFolder(Native.FolderProfile)
                   ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        // AppData is defined relative to %USERPROFILE%; make sure this process has the real one before asking.
        Environment.SetEnvironmentVariable("USERPROFILE", home);
        var roaming = Native.KnownFolder(Native.FolderRoamingAppData) ?? Path.Combine(home, "AppData", "Roaming");
        var local = Native.KnownFolder(Native.FolderLocalAppData) ?? Path.Combine(home, "AppData", "Local");
        return new Layout(home, roaming, local, FindZalo(local));
    }

    /// <summary>Zalo's launcher, the program its shortcuts start.</summary>
    static string FindZalo(string localAppData)
    {
        var standard = Path.Combine(localAppData, "Programs", "Zalo", "Zalo.exe");
        if (File.Exists(standard)) return standard;
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            using var uninstall = hive.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall");
            if (uninstall == null) continue;
            foreach (var name in uninstall.GetSubKeyNames())
            {
                using var key = uninstall.OpenSubKey(name);
                if (key?.GetValue("DisplayName") is not string display || !display.Equals("Zalo", StringComparison.OrdinalIgnoreCase)) continue;
                if (key.GetValue("InstallLocation") is string folder && File.Exists(Path.Combine(folder, "Zalo.exe")))
                    return Path.Combine(folder, "Zalo.exe");
            }
        }
        return standard;
    }
}
