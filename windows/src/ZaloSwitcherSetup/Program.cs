using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using ZaloSwitcher.Shared;

namespace ZaloSwitcherSetup
{
    /// <summary>The installer: puts Zalo Switcher in %LOCALAPPDATA%\Programs\Zalo Switcher, adds it to the
    /// Start menu (and optionally the desktop) and to Settings → Apps, where it can be uninstalled. It never
    /// touches Zalo or the saved accounts.</summary>
    static class Program
    {
        /// <summary>`/S` installs without asking anything (Start menu shortcut only) and exits with 0 on success.</summary>
        [STAThread]
        static int Main(string[] args)
        {
            if (args.Any(a => a.Equals("/S", StringComparison.OrdinalIgnoreCase)))
            {
                try
                {
                    SetupForm.InstallSilently();
                    return 0;
                }
                catch (Exception error)
                {
                    Console.Error.WriteLine(error.Message);
                    return 1;
                }
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
            return 0;
        }
    }

    sealed class SetupForm : Form
    {
        static readonly string Version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
        readonly CheckBox _desktop = new CheckBox { Text = "Tạo lối tắt trên màn hình nền", Checked = true, AutoSize = true };
        readonly CheckBox _launch = new CheckBox { Text = "Mở Zalo Switcher khi cài xong", Checked = true, AutoSize = true };
        readonly Button _install = new Button { AutoSize = true, Padding = new Padding(14, 4, 14, 4) };
        readonly Button _cancel = new Button { Text = "Hủy", AutoSize = true, Padding = new Padding(10, 4, 10, 4) };
        readonly Label _status = new Label { AutoSize = false, Height = 22, ForeColor = Color.FromArgb(0x5F, 0x66, 0x70) };
        readonly ProgressBar _progress = new ProgressBar { Height = 6, Style = ProgressBarStyle.Marquee, Visible = false };

        public SetupForm()
        {
            var installed = Installation.InstalledVersion();
            Text = $"Cài đặt Zalo Switcher {Version}";
            Font = new Font("Segoe UI", 10f);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;
            BackColor = Color.White;
            ClientSize = new Size(520, 330);
            using (var icon = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppIcon.ico"))
                Icon = new Icon(icon);

            var picture = new PictureBox { Image = new Icon(Icon, 64, 64).ToBitmap(), SizeMode = PictureBoxSizeMode.Zoom, Size = new Size(56, 56), Location = new Point(24, 24) };
            var title = new Label
            {
                Text = installed == null ? "Cài đặt Zalo Switcher" : $"Cập nhật Zalo Switcher {installed} lên {Version}",
                Font = new Font("Segoe UI Semibold", 14f),
                AutoSize = true,
                Location = new Point(96, 26),
            };
            var body = new Label
            {
                Text = "Dùng nhiều tài khoản Zalo cùng lúc, mỗi tài khoản một cửa sổ Zalo riêng.\n\n" +
                       $"Ứng dụng được cài cho riêng tài khoản Windows này, vào:\n{Installation.Folder}\n\n" +
                       "Việc cài đặt không đụng tới Zalo, tin nhắn hay các tài khoản đã lưu.",
                Location = new Point(96, 64),
                Size = new Size(400, 140),
            };
            _desktop.Location = new Point(96, 208);
            _launch.Location = new Point(96, 236);
            _status.Location = new Point(24, 276);
            _status.Width = 260;
            _progress.Location = new Point(24, 300);
            _progress.Width = 260;

            _install.Text = installed == null ? "Cài đặt" : "Cập nhật";
            _install.BackColor = Color.FromArgb(0x00, 0x68, 0xFF);
            _install.ForeColor = Color.White;
            _install.FlatStyle = FlatStyle.Flat;
            _install.FlatAppearance.BorderSize = 0;
            _install.Click += async (s, e) => await Install();
            _cancel.Click += (s, e) => Close();
            var buttons = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.RightToLeft,
                Location = new Point(290, 276),
                Size = new Size(210, 44),
            };
            buttons.Controls.Add(_install);
            buttons.Controls.Add(_cancel);
            AcceptButton = _install;
            CancelButton = _cancel;
            Controls.AddRange(new Control[] { picture, title, body, _desktop, _launch, _status, _progress, buttons });
        }

        async Task Install()
        {
            if (!WaitForAppToQuit()) return;
            _install.Enabled = _cancel.Enabled = _desktop.Enabled = _launch.Enabled = false;
            _progress.Visible = true;
            _status.Text = "Đang cài đặt…";
            var desktop = _desktop.Checked;
            try
            {
                await Task.Run(() => CopyFiles());
                CreateShortcut(Installation.StartMenuShortcut);
                if (desktop) CreateShortcut(Installation.DesktopShortcut);
                else if (File.Exists(Installation.DesktopShortcut)) File.Delete(Installation.DesktopShortcut);
                Register();
            }
            catch (Exception error)
            {
                _progress.Visible = false;
                _status.Text = "";
                MessageBox.Show(this, $"Không cài đặt được: {error.Message}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                _install.Enabled = _cancel.Enabled = _desktop.Enabled = _launch.Enabled = true;
                return;
            }
            if (_launch.Checked)
                Process.Start(new ProcessStartInfo(Path.Combine(Installation.Folder, Installation.AppExe)) { UseShellExecute = true });
            else
                MessageBox.Show(this, "Đã cài đặt xong. Mở Zalo Switcher từ menu Start.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            Close();
        }

        public static void InstallSilently()
        {
            CopyFiles();
            CreateShortcut(Installation.StartMenuShortcut);
            Register();
        }

        /// <summary>An installed copy that is running would keep its files locked.</summary>
        bool WaitForAppToQuit()
        {
            while (true)
            {
                var running = Process.GetProcessesByName("ZaloSwitcher").Concat(Process.GetProcessesByName("zalo-profiles"))
                    .Where(p => PathOf(p)?.StartsWith(Installation.Folder + "\\", StringComparison.OrdinalIgnoreCase) == true)
                    .ToList();
                if (running.Count == 0) return true;
                var answer = MessageBox.Show(this,
                    "Zalo Switcher đang chạy. Hãy thoát nó (chuột phải biểu tượng Zalo Switcher ở khay hệ thống, chọn “Thoát Zalo Switcher”) rồi bấm Thử lại. Các cửa sổ Zalo vẫn chạy bình thường.",
                    Text, MessageBoxButtons.RetryCancel, MessageBoxIcon.Information);
                if (answer != DialogResult.Retry) return false;
            }
        }

        static string PathOf(Process process)
        {
            try { return process.MainModule?.FileName; }
            catch { return null; }
        }

        /// <summary>Unpacks into a new folder next to the install folder, then swaps the two by renaming, so
        /// an interrupted install never leaves half a program.</summary>
        static void CopyFiles()
        {
            var folder = Installation.Folder;
            var parent = Path.GetDirectoryName(folder);
            Directory.CreateDirectory(parent);
            var fresh = folder + ".new";
            var old = folder + ".old";
            foreach (var leftover in new[] { fresh, old })
                if (Directory.Exists(leftover)) Directory.Delete(leftover, recursive: true);

            using (var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (payload == null) throw new InvalidOperationException("tệp cài đặt bị thiếu dữ liệu. Hãy tải lại.");
                using (var zip = new ZipArchive(payload, ZipArchiveMode.Read))
                    zip.ExtractToDirectory(fresh);
            }
            if (!File.Exists(Path.Combine(fresh, Installation.AppExe)))
                throw new InvalidOperationException("tệp cài đặt bị hỏng. Hãy tải lại.");

            if (Directory.Exists(folder)) Directory.Move(folder, old);
            Directory.Move(fresh, folder);
            if (Directory.Exists(old)) Directory.Delete(old, recursive: true);
        }

        static void CreateShortcut(string path)
        {
            var shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
            dynamic link = ((dynamic)shell).CreateShortcut(path);
            link.TargetPath = Path.Combine(Installation.Folder, Installation.AppExe);
            link.WorkingDirectory = Installation.Folder;
            link.IconLocation = Path.Combine(Installation.Folder, Installation.AppExe) + ",0";
            link.Description = "Dùng nhiều tài khoản Zalo cùng lúc";
            link.Save();
        }

        /// <summary>Adds the app to Settings → Apps; its uninstall runs the app's own --uninstall.</summary>
        static void Register()
        {
            var exe = Path.Combine(Installation.Folder, Installation.AppExe);
            using (var key = Registry.CurrentUser.CreateSubKey(Installation.UninstallKey))
            {
                key.SetValue("DisplayName", Installation.DisplayName);
                key.SetValue("DisplayVersion", Version);
                key.SetValue("Publisher", "Zalo Switcher (dự án độc lập)");
                key.SetValue("DisplayIcon", exe + ",0");
                key.SetValue("InstallLocation", Installation.Folder);
                key.SetValue("UninstallString", $"\"{exe}\" --uninstall");
                key.SetValue("URLInfoAbout", "https://github.com/ducngfi/zalo-multi-accounts");
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                key.SetValue("EstimatedSize", (int)(DirectorySize(Installation.Folder) / 1024), RegistryValueKind.DWord);
            }
            // "Open at sign-in" points at the exe; keep it pointing at this copy.
            using (var run = Registry.CurrentUser.OpenSubKey(Installation.RunKey, writable: true))
            {
                if (run?.GetValue(Installation.DisplayName) is string)
                    run.SetValue(Installation.DisplayName, $"\"{exe}\" --login");
            }
        }

        static long DirectorySize(string folder) =>
            new DirectoryInfo(folder).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
    }
}
