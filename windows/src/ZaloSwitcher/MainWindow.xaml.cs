using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace ZaloSwitcher;

/// <summary>The main window: every saved account, which ones are open, and what can be done with each.</summary>
public partial class MainWindow : Window
{
    readonly AppModel _model;

    public MainWindow(AppModel model)
    {
        InitializeComponent();
        _model = model;
        DataContext = model;
        model.PropertyChanged += (_, _) => UpdateBanners();
        UpdateBanners();
    }

    void UpdateBanners()
    {
        BusyBanner.Visibility = _model.Busy != null ? Visibility.Visible : Visibility.Collapsed;
        CopyBanner.Visibility = _model.Copying != null ? Visibility.Visible : Visibility.Collapsed;
        OpenAllItem.IsEnabled = _model.ClosedCount > 0;
        CloseAllItem.IsEnabled = _model.OpenCount > 0;
    }

    /// <summary>Closing the window keeps the app in the notification area, like the macOS app in the
    /// menu bar; without the icon there, closing quits.</summary>
    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (((App)Application.Current).IsQuitting) return;
        if (_model.Settings.ShowTrayIcon)
        {
            e.Cancel = true;
            Hide();
        }
        else
        {
            e.Cancel = !((App)Application.Current).Quit();
        }
    }

    static void ShowMenu(object sender)
    {
        if (sender is not Button { ContextMenu: { } menu } button) return;
        menu.PlacementTarget = button;
        menu.Placement = PlacementMode.Bottom;
        menu.DataContext = button.DataContext;
        menu.IsOpen = true;
    }

    void ShowAddMenu(object sender, RoutedEventArgs e) => ShowMenu(sender);
    void ShowAllMenu(object sender, RoutedEventArgs e) => ShowMenu(sender);
    void ShowRowMenu(object sender, RoutedEventArgs e) => ShowMenu(sender);

    void AddAccount(object sender, RoutedEventArgs e) => _model.AddAccount();
    void Restore(object sender, RoutedEventArgs e) => _model.Restore();
    void OpenAll(object sender, RoutedEventArgs e) => _model.OpenAll();
    void CloseAll(object sender, RoutedEventArgs e) => _model.CloseAll();
    void SaveCurrent(object sender, RoutedEventArgs e) => _model.SaveCurrent();
    void CancelCopy(object sender, RoutedEventArgs e) => _model.CancelCopy();
    void ShowSettings(object sender, RoutedEventArgs e) => new SettingsWindow(_model) { Owner = this }.ShowDialog();
}
