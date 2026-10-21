using System.Windows;
using ZaloProfiles.Core;
using Forms = System.Windows.Forms;

namespace ZaloSwitcher;

/// <summary>The notification-area icon and its menu, the Windows counterpart of the macOS menu-bar item.
/// The menu is rebuilt from the model each time it opens.</summary>
public sealed class Tray : IDisposable
{
    readonly AppModel _model;
    readonly Action _showWindow;
    readonly Action _quit;
    readonly Forms.NotifyIcon _icon;
    readonly Forms.ContextMenuStrip _menu = new();

    public Tray(AppModel model, Action showWindow, Action quit)
    {
        _model = model;
        _showWindow = showWindow;
        _quit = quit;
        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/AppIcon.ico"))!.Stream;
        _icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            ContextMenuStrip = _menu,
        };
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) _showWindow();
        };
        _menu.Opening += (_, _) =>
        {
            _model.Refresh();
            Build();
        };
        // Something to show even before the first opening.
        _menu.Items.Add("…");
        _model.Changed += UpdateText;
        UpdateText();
    }

    public bool Visible
    {
        get => _icon.Visible;
        set => _icon.Visible = value;
    }

    void UpdateText()
    {
        var text = _model.Busy ?? (_model.Copying != null ? "Đang sao chép…" : _model.Headline);
        if (_model.IsDemo) text = "Demo · " + text;
        text = "Zalo Switcher\n" + text;
        _icon.Text = text.Length > 127 ? text[..127] : text;
    }

    void Build()
    {
        var items = _menu.Items;
        items.Clear();
        items.Add(Disabled(_model.Busy ?? _model.Headline));
        if (_model.FreeSpace is { } free)
            items.Add(Disabled(_model.LowSpace ? $"⚠ Ổ đĩa sắp đầy: còn trống {Disk.Format(free)}" : $"Ổ đĩa còn trống {Disk.Format(free)}"));
        if (_model.Copying is { } copying)
        {
            items.Add(Disabled(copying));
            items.Add(Item("Hủy sao chép", _model.CancelCopy));
        }
        items.Add(new Forms.ToolStripSeparator());
        items.Add(Item("Mở cửa sổ Zalo Switcher…", _showWindow, bold: true));
        items.Add(new Forms.ToolStripSeparator());

        var idle = _model.IsIdle;
        if (_model.Statuses.Count == 0) items.Add(Disabled("Chưa có tài khoản nào"));
        foreach (var status in _model.Statuses)
        {
            var title = status.Profile.Name;
            if (_model.Sizes.TryGetValue(status.Profile.Id, out var size)) title += $"  —  {Disk.Format(size)}";
            if (status.Place == Place.Main) title += "  (Zalo chính)";
            if (status.Place == Place.New) title += "  (chưa đăng nhập)";
            var item = Item(title, () => _model.Open(status), enabled: idle);
            item.Checked = status.IsOpen;
            items.Add(item);
        }
        items.Add(new Forms.ToolStripSeparator());
        items.Add(Item("Mở tất cả", () => _model.OpenAll(), enabled: idle && _model.ClosedCount > 0));

        var close = new Forms.ToolStripMenuItem("Đóng") { Enabled = idle && _model.OpenCount > 0 };
        foreach (var status in _model.Statuses.Where(s => s.IsOpen))
            close.DropDownItems.Add(Item(status.Profile.Name, () => _model.Close(status)));
        close.DropDownItems.Add(new Forms.ToolStripSeparator());
        close.DropDownItems.Add(Item("Đóng mọi cửa sổ Zalo…", _model.CloseAll));
        items.Add(close);
        items.Add(Item("Thêm tài khoản…", _model.AddAccount, enabled: idle));
        items.Add(new Forms.ToolStripSeparator());
        items.Add(Item("Thoát Zalo Switcher", _quit));
    }

    static Forms.ToolStripMenuItem Disabled(string text) => new(text) { Enabled = false };

    static Forms.ToolStripMenuItem Item(string text, Action action, bool enabled = true, bool bold = false)
    {
        var item = new Forms.ToolStripMenuItem(text) { Enabled = enabled };
        if (bold) item.Font = new System.Drawing.Font(item.Font, System.Drawing.FontStyle.Bold);
        // Let the menu close before a dialog opens.
        item.Click += (_, _) => Application.Current.Dispatcher.InvokeAsync(action);
        return item;
    }

    public void Dispose()
    {
        _model.Changed -= UpdateText;
        _icon.Visible = false;
        _icon.Dispose();
        _menu.Dispose();
    }
}
