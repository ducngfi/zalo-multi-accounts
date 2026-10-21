using System.Windows;
using ZaloProfiles.Core;

namespace ZaloSwitcher;

public partial class App : Application
{
    public static new App Current => (App)Application.Current;

    AppModel? _model;
    MainWindow? _window;
    Tray? _tray;
    Mutex? _single;
    EventWaitHandle? _showSignal;
    bool _demoOpenAtLogin;
    bool _isDemo;

    public bool IsQuitting { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (Array.IndexOf(e.Args, "--render-screenshots") is var at and >= 0 && at + 1 < e.Args.Length)
        {
            try { Screenshots.Render(e.Args[at + 1]); }
            catch (Exception error) { Console.Error.WriteLine(error); }
            Shutdown();
            return;
        }
        _isDemo = e.Args.Contains("--demo");
        var atLogin = e.Args.Contains("--login");

        // One app per Windows user (the demo runs beside it): a second start shows the first one's window.
        var name = _isDemo ? "ZaloSwitcher.Demo" : "ZaloSwitcher";
        _single = new Mutex(true, $"Local\\{name}", out var first);
        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, $"Local\\{name}.Show");
        if (e.Args.Contains("--uninstall"))
        {
            Uninstall.Run(otherInstanceRunning: !first);
            Shutdown();
            return;
        }
        if (!first)
        {
            if (!atLogin) _showSignal.Set();
            Shutdown();
            return;
        }
        new Thread(() =>
        {
            while (_showSignal.WaitOne()) Dispatcher.InvokeAsync(ShowMainWindow);
        }) { IsBackground = true }.Start();

        ProfileManager manager;
        try
        {
            manager = _isDemo ? Demo.MakeManager() : ProfileManager.ForSystem();
        }
        catch (Exception error)
        {
            Dialogs.Error(error);
            Shutdown(1);
            return;
        }
        var settings = Settings.Load(_isDemo);
        _model = new AppModel(manager, settings, _isDemo);
        _window = new MainWindow(_model);
        MainWindow = _window;
        _tray = new Tray(_model, ShowMainWindow, () => Quit());
        UpdateTrayIcon();
        _model.Start();

        if (atLogin)
        {
            // Started by Windows at sign-in: stay in the notification area and open the accounts.
            if (settings.OpenAllAtLogin) _model.OpenAll(asking: false);
            if (!settings.ShowTrayIcon) ShowMainWindow();
        }
        else
        {
            ShowMainWindow();
        }
    }

    public void ShowMainWindow()
    {
        if (_window == null) return;
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        _window.Activate();
        _model?.Refresh();
    }

    public void UpdateTrayIcon()
    {
        if (_tray != null && _model != null) _tray.Visible = _model.Settings.ShowTrayIcon;
    }

    public bool OpenAtLogin => _isDemo ? _demoOpenAtLogin : Settings.OpenAtLogin;

    public void SetOpenAtLogin(bool on)
    {
        if (_isDemo) _demoOpenAtLogin = on;
        else Settings.SetOpenAtLogin(on, Environment.ProcessPath!);
    }

    /// <summary>Quits the app; Zalo windows keep running. Refuses while a backup or restore is copying.</summary>
    public bool Quit()
    {
        if (_model?.Copying != null)
        {
            Dialogs.Info("Đang sao chép", "Zalo Switcher đang sao lưu hoặc khôi phục. Hãy đợi xong, hoặc bấm “Hủy” rồi thoát.");
            ShowMainWindow();
            return false;
        }
        IsQuitting = true;
        _tray?.Dispose();
        _window?.Close();
        Shutdown();
        return true;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _single?.Dispose();
        base.OnExit(e);
    }
}
