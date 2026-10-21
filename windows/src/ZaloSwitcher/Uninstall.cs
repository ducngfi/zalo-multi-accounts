using System.Diagnostics;
using System.IO;
using Microsoft.Win32;
using ZaloSwitcher.Shared;

namespace ZaloSwitcher;

/// <summary>`ZaloSwitcher --uninstall`, run from Settings → Apps. Removes the program, its shortcuts and its
/// start-at-sign-in entry. Zalo, the main account and the saved accounts (Zalo Profiles) are left as they are.</summary>
static class Uninstall
{
    public static void Run(bool otherInstanceRunning)
    {
        if (otherInstanceRunning)
        {
            Dialogs.Info("Gỡ Zalo Switcher",
                "Zalo Switcher đang chạy. Hãy thoát nó (chuột phải biểu tượng Zalo Switcher ở khay hệ thống, chọn “Thoát Zalo Switcher”) rồi gỡ lại.");
            return;
        }
        if (!Dialogs.Confirm("Gỡ Zalo Switcher?",
                "Chương trình Zalo Switcher sẽ được gỡ khỏi máy. Zalo, tài khoản Zalo chính và các tài khoản đã lưu không bị xóa: Zalo tiếp tục mở tài khoản đang là Zalo chính, còn dữ liệu của các tài khoản khác vẫn nằm trong %LOCALAPPDATA%\\Zalo Profiles. Muốn dùng lại chúng, hãy cài lại Zalo Switcher.",
                "Gỡ cài đặt", destructive: true)) return;

        foreach (var shortcut in new[] { Installation.StartMenuShortcut, Installation.DesktopShortcut })
        {
            try { if (File.Exists(shortcut)) File.Delete(shortcut); } catch { }
        }
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(Installation.RunKey, writable: true);
            run?.DeleteValue(Installation.DisplayName, throwOnMissingValue: false);
        }
        catch { }
        try { Registry.CurrentUser.DeleteSubKeyTree(Installation.UninstallKey, throwOnMissingSubKey: false); } catch { }

        // This program is running from the folder, so a separate command removes it a moment after it exits.
        // Only the installer's own folder is ever removed.
        var folder = Path.GetDirectoryName(Environment.ProcessPath!)!;
        if (Installation.IsInstallFolder(folder) && File.Exists(Path.Combine(folder, Installation.AppExe)))
        {
            Process.Start(new ProcessStartInfo("cmd.exe",
                $"/d /c ping -n 3 127.0.0.1 >nul & rmdir /s /q \"{Installation.Folder}\"")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                WorkingDirectory = Path.GetTempPath(),
            });
        }
        Dialogs.Info("Đã gỡ Zalo Switcher", "Zalo Switcher đã được gỡ khỏi máy. Zalo và các tài khoản đã lưu vẫn còn nguyên.");
    }
}
