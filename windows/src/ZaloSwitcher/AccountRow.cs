using System.Windows.Input;
using System.Windows.Media;
using ZaloProfiles.Core;

namespace ZaloSwitcher;

/// <summary>One saved account in the main window.</summary>
public sealed class AccountRow : Observable
{
    readonly AppModel _model;

    public AccountRow(AppModel model, ProfileStatus status)
    {
        _model = model;
        Status = status;
        Open = new Command(() => _model.Open(Status), () => _model.IsIdle);
        Close = new Command(() => _model.Close(Status), () => _model.IsIdle);
        BackUp = new Command(() => _model.BackUp(Status), () => _model.IsIdle && CanBackUp);
        Rename = new Command(() => _model.Rename(Status), () => _model.IsIdle);
        MakeMain = new Command(() => _model.MakeMain(Status), () => _model.IsIdle && !IsMain);
        Remove = new Command(() => _model.Remove(Status), () => _model.IsIdle && CanRemove);
    }

    public ProfileStatus Status { get; private set; }
    long? _size;

    public void Update(ProfileStatus status, long? size)
    {
        Status = status;
        _size = size;
        RaiseAll();
    }

    public string Id => Status.Profile.Id;
    public string Name => Status.Profile.Name;
    public bool IsOpen => Status.IsOpen;
    public bool IsClosed => !Status.IsOpen;
    public bool IsMain => Status.Place == Place.Main;
    public bool IsNew => Status.Place == Place.New;
    public bool CanBackUp => !IsNew && _model.Copying == null;
    public bool CanRemove => !IsMain && !IsOpen;

    public string StateText => IsOpen ? "Đang mở" : IsNew ? "Chưa đăng nhập" : "Đã đóng";
    public Brush StateBrush => IsOpen ? Palette.Green : IsNew ? Palette.Orange : Palette.Gray;
    public string PrimaryText => IsNew ? "Mở để đăng nhập" : "Mở";

    public string Details
    {
        get
        {
            var parts = new List<string>();
            if (_size is { } size) parts.Add(Disk.Format(size));
            if (Status.ZaloUserId is { } uid) parts.Add($"ID Zalo …{uid[^4..]}");
            if (IsNew) parts.Add("Đăng nhập một lần khi mở lần đầu");
            if (Status.Profile.LastUsedAt is { } used && !IsOpen && !IsNew) parts.Add($"Mở gần nhất {Relative(used)}");
            return string.Join(" · ", parts);
        }
    }

    public string Initials
    {
        get
        {
            var words = Name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (words.Length == 0) return "?";
            var first = words[0][..1];
            var last = words.Length > 1 ? words[^1][..1] : "";
            return (first + last).ToUpperInvariant();
        }
    }

    /// <summary>A colour that stays the same for a name.</summary>
    public Brush AvatarBrush
    {
        get
        {
            var index = Name.Aggregate(0, (sum, c) => (sum + c) % 997) % Palette.Avatars.Length;
            return Palette.Avatars[index];
        }
    }

    public ICommand Open { get; }
    public ICommand Close { get; }
    public ICommand BackUp { get; }
    public ICommand Rename { get; }
    public ICommand MakeMain { get; }
    public ICommand Remove { get; }

    static string Relative(DateTime utc)
    {
        var span = DateTime.UtcNow - utc;
        if (span.TotalMinutes < 1) return "vừa xong";
        if (span.TotalHours < 1) return $"{(int)span.TotalMinutes} phút trước";
        if (span.TotalDays < 1) return $"{(int)span.TotalHours} giờ trước";
        if (span.TotalDays < 7) return $"{(int)span.TotalDays} ngày trước";
        if (span.TotalDays < 30) return $"{(int)(span.TotalDays / 7)} tuần trước";
        if (span.TotalDays < 365) return $"{(int)(span.TotalDays / 30)} tháng trước";
        return $"{(int)(span.TotalDays / 365)} năm trước";
    }
}

static class Palette
{
    static SolidColorBrush Make(uint rgb)
    {
        var brush = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
        brush.Freeze();
        return brush;
    }

    public static readonly Brush Green = Make(0x1E9E50);
    public static readonly Brush Orange = Make(0xD9730D);
    public static readonly Brush Gray = Make(0x6B7280);
    public static readonly Brush Blue = Make(0x0068FF);

    public static readonly Brush[] Avatars =
    [
        Make(0x0A84FF), Make(0x30B0C7), Make(0xFF9F0A), Make(0xFF375F),
        Make(0xBF5AF2), Make(0x30D158), Make(0x5E5CE6), Make(0xFF453A),
    ];
}
