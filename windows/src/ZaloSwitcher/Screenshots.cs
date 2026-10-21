using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ZaloProfiles.Core;

namespace ZaloSwitcher;

/// <summary>`ZaloSwitcher --render-screenshots &lt;folder&gt;`: draws the windows with the demo's synthetic
/// accounts into PNG files, for the README and for checking the layout. Never touches the real Zalo.</summary>
static class Screenshots
{
    public static void Render(string folder)
    {
        Directory.CreateDirectory(folder);
        var model = new AppModel(Demo.MakeManager(), new Settings(), isDemo: false);
        model.RefreshNow();

        var main = new MainWindow(model) { Left = -20000, Top = -20000, ShowActivated = false, ShowInTaskbar = false };
        main.Show();
        Save(main, Path.Combine(folder, "cua-so-chinh-windows.png"));

        model.ShowDemoProgress("Đang sao lưu Cửa hàng Hoa Mai… 42% (903 MB / 2,15 GB)", 0.42);
        Save(main, Path.Combine(folder, "sao-luu-windows.png"));

        var settings = new SettingsWindow(model) { Left = -20000, Top = -20000, ShowActivated = false, ShowInTaskbar = false };
        settings.Show();
        Save(settings, Path.Combine(folder, "cai-dat-windows.png"));
        settings.Close();
    }

    static void Save(Window window, string path)
    {
        window.UpdateLayout();
        window.Dispatcher.Invoke(() => { }, System.Windows.Threading.DispatcherPriority.Render);
        var content = (FrameworkElement)window.Content;
        var scale = 2.0;
        var bitmap = new RenderTargetBitmap((int)(content.ActualWidth * scale), (int)(content.ActualHeight * scale),
                                            96 * scale, 96 * scale, PixelFormats.Pbgra32);
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.DrawRectangle(window.Background, null, new Rect(0, 0, content.ActualWidth, content.ActualHeight));
            context.DrawRectangle(new VisualBrush(content), null, new Rect(0, 0, content.ActualWidth, content.ActualHeight));
        }
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(path);
        encoder.Save(file);
    }
}
