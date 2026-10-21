using System.Reflection;
using System.Windows;
using ZaloProfiles.Core;

namespace ZaloSwitcher;

public partial class SettingsWindow : Window
{
    readonly AppModel _model;

    public SettingsWindow(AppModel model)
    {
        InitializeComponent();
        _model = model;
        TrayIcon.IsChecked = model.Settings.ShowTrayIcon;
        OpenAtLogin.IsChecked = App.Current.OpenAtLogin;
        OpenAllAtLogin.IsChecked = model.Settings.OpenAllAtLogin;
        OpenAllAtLogin.IsEnabled = App.Current.OpenAtLogin;
        VersionLabel.Text = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "–";
        UpdateSpace();
    }

    void UpdateSpace() => SpaceLabel.Text = $"Cảnh báo khi ổ đĩa còn trống dưới {_model.Settings.LowSpaceGB} GB";

    void TrayIconChanged(object sender, RoutedEventArgs e)
    {
        _model.Settings.ShowTrayIcon = TrayIcon.IsChecked == true;
        _model.Settings.Save();
        App.Current.UpdateTrayIcon();
    }

    void OpenAtLoginChanged(object sender, RoutedEventArgs e)
    {
        try { App.Current.SetOpenAtLogin(OpenAtLogin.IsChecked == true); }
        catch (Exception error) { Dialogs.Error(error); }
        OpenAtLogin.IsChecked = App.Current.OpenAtLogin;
        OpenAllAtLogin.IsEnabled = App.Current.OpenAtLogin;
    }

    void OpenAllAtLoginChanged(object sender, RoutedEventArgs e)
    {
        _model.Settings.OpenAllAtLogin = OpenAllAtLogin.IsChecked == true;
        _model.Settings.Save();
    }

    void LessSpace(object sender, RoutedEventArgs e) => ChangeSpace(-1);
    void MoreSpace(object sender, RoutedEventArgs e) => ChangeSpace(+1);

    void ChangeSpace(int delta)
    {
        _model.SetLowSpaceThreshold(Math.Clamp(_model.Settings.LowSpaceGB + delta, 1, 100));
        UpdateSpace();
    }

    void ShowProfiles(object sender, RoutedEventArgs e) => _model.ShowProfilesFolder();
    void ShowZaloData(object sender, RoutedEventArgs e) => _model.ShowZaloDataFolder();
    void Done(object sender, RoutedEventArgs e) => Close();
}
