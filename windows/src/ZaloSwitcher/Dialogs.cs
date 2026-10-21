using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;

namespace ZaloSwitcher;

/// <summary>Small Vietnamese dialogs: questions with a named button, text input, notices and errors.
/// (MessageBox can't name its buttons, and would show English "Yes/No" on many computers.)</summary>
public static class Dialogs
{
    /// <summary>The window dialogs belong to, or none when the app is only in the notification area.</summary>
    static Window? Owner => Application.Current.MainWindow is { IsVisible: true } window ? window : null;

    public static bool Confirm(string title, string message, string button, bool destructive = false) =>
        Show(title, message, button, "Hủy", input: null, destructive) != null;

    public static string? Text(string title, string message, string placeholder, string initial = "")
    {
        var result = Show(title, message, "OK", "Hủy", input: (placeholder, initial), destructive: false);
        return string.IsNullOrWhiteSpace(result) ? null : result.Trim();
    }

    public static void Info(string title, string message) => Show(title, message, "OK", cancel: null, input: null, false);

    public static void Error(Exception error) =>
        Show("Không thực hiện được", error.Message, "OK", cancel: null, input: null, false, isError: true);

    public static string? ChooseFolder(string title, string? start)
    {
        var dialog = new OpenFolderDialog { Title = title };
        if (start != null && System.IO.Directory.Exists(start)) dialog.InitialDirectory = start;
        return dialog.ShowDialog(Owner) == true ? dialog.FolderName : null;
    }

    /// <summary>Returns the text typed (or "" without a text box) when the main button is pressed, null otherwise.</summary>
    static string? Show(string title, string message, string ok, string? cancel, (string Placeholder, string Initial)? input,
                        bool destructive, bool isError = false)
    {
        var window = new Window
        {
            Title = title,
            Owner = Owner,
            WindowStartupLocation = Owner == null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner,
            SizeToContent = SizeToContent.Height,
            Width = 460,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = Owner == null,
            Background = (Brush)Application.Current.Resources["WindowBrush"],
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 14,
        };
        if (Owner == null) window.Topmost = true;

        var panel = new StackPanel { Margin = new Thickness(24, 20, 24, 20) };
        panel.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 17,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            Foreground = isError ? new SolidColorBrush(Color.FromRgb(0xC4, 0x2B, 0x1C)) : (Brush)Application.Current.Resources["TextBrush"],
            Margin = new Thickness(0, 0, 0, 10),
        });
        panel.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.Resources["SecondaryTextBrush"],
            LineHeight = 21,
        });

        TextBox? box = null;
        if (input is { } field)
        {
            box = new TextBox { Text = field.Initial, Margin = new Thickness(0, 14, 0, 0), Style = (Style)Application.Current.Resources["InputBox"] };
            box.Tag = field.Placeholder;
            box.SelectAll();
            panel.Children.Add(box);
        }

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 22, 0, 0) };
        string? result = null;
        if (cancel != null)
        {
            var no = new Button { Content = cancel, IsCancel = true, Style = (Style)Application.Current.Resources["SecondaryButton"], Margin = new Thickness(0, 0, 8, 0) };
            buttons.Children.Add(no);
        }
        var yes = new Button
        {
            Content = ok,
            IsDefault = true,
            IsCancel = cancel == null,
            Style = (Style)Application.Current.Resources[destructive ? "DangerButton" : "PrimaryButton"],
        };
        yes.Click += (_, _) =>
        {
            result = box?.Text ?? "";
            window.DialogResult = true;
        };
        buttons.Children.Add(yes);
        panel.Children.Add(buttons);
        window.Content = panel;
        window.Loaded += (_, _) =>
        {
            if (box != null) { box.Focus(); Keyboard.Focus(box); }
            else yes.Focus();
        };
        window.ShowDialog();
        return result;
    }
}
