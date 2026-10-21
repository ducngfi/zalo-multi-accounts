#nullable disable
using System;
using System.IO;
using Microsoft.Win32;

namespace ZaloSwitcher.Shared
{
    /// <summary>Where the installer puts the app, shared by the installer (net48) and the app's own
    /// uninstall (net8). Everything is per user: no administrator rights, nothing outside the user's folders.</summary>
    internal static class Installation
    {
        public const string DisplayName = "Zalo Switcher";
        public const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ZaloSwitcher";
        public const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public const string AppExe = "ZaloSwitcher.exe";

        public static string Folder =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", DisplayName);

        public static string StartMenuShortcut =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), DisplayName + ".lnk");

        public static string DesktopShortcut =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), DisplayName + ".lnk");

        /// <summary>The installed version, or null when the installer has not installed the app.</summary>
        public static string InstalledVersion()
        {
            using (var key = Registry.CurrentUser.OpenSubKey(UninstallKey))
                return key?.GetValue("DisplayVersion") as string;
        }

        /// <summary>Whether <paramref name="folder"/> is the installer's folder: the only folder the installer
        /// and the uninstaller ever replace or remove.</summary>
        public static bool IsInstallFolder(string folder) =>
            string.Equals(Path.GetFullPath(folder).TrimEnd('\\'), Path.GetFullPath(Folder).TrimEnd('\\'),
                          StringComparison.OrdinalIgnoreCase);
    }
}
