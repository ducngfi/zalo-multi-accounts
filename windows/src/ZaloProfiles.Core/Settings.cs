using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace ZaloProfiles.Core;

/// <summary>The person's choices, in %LOCALAPPDATA%\Zalo Switcher\settings.json. The app writes them;
/// zalo-profiles reads the free-space threshold too. The demo keeps its own copy.</summary>
public sealed class Settings
{
    [JsonPropertyName("lastBackupFolder")]
    public string? LastBackupFolder { get; set; }

    /// <summary>Below this many GB free, the app warns and asks before adding or opening accounts.</summary>
    [JsonPropertyName("lowSpaceGB")]
    public int LowSpaceGB { get; set; } = 5;

    /// <summary>When Windows starts the app at sign-in, it also opens every account that has been logged in.</summary>
    [JsonPropertyName("openAllAtLogin")]
    public bool OpenAllAtLogin { get; set; } = true;

    [JsonPropertyName("showTrayIcon")]
    public bool ShowTrayIcon { get; set; } = true;

    [JsonIgnore]
    public string? FilePath { get; private set; }

    public static string DefaultFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Zalo Switcher");

    public static Settings Load(bool demo = false)
    {
        var path = Path.Combine(DefaultFolder, demo ? "settings-demo.json" : "settings.json");
        var settings = Json.Read<Settings>(path) ?? new Settings();
        settings.LowSpaceGB = Math.Clamp(settings.LowSpaceGB, 1, 100);
        settings.FilePath = path;
        return settings;
    }

    public void Save()
    {
        if (FilePath == null) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            Json.Write(FilePath, this);
        }
        catch { }
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string RunValue = "Zalo Switcher";

    /// <summary>Whether Windows starts the app (with --login) when the person signs in.</summary>
    public static bool OpenAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunValue) is string;
        }
    }

    public static void SetOpenAtLogin(bool on, string exePath)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (on) key.SetValue(RunValue, $"\"{exePath}\" --login");
        else key.DeleteValue(RunValue, throwOnMissingValue: false);
    }
}
