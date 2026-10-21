using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ZaloProfiles.Core;

/// <summary>`profile.json`. Properties are declared in alphabetical order so the file matches the
/// macOS app's (sorted keys).</summary>
public sealed record Profile
{
    [JsonPropertyName("createdAt"), JsonConverter(typeof(IsoDateConverter))]
    public DateTime CreatedAt { get; init; }

    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("lastUsedAt"), JsonConverter(typeof(IsoDateConverter))]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTime? LastUsedAt { get; init; }

    [JsonPropertyName("name")]
    public string Name { get; init; } = "";
}

/// <summary>What the main `ZaloData` folder holds.</summary>
public abstract record MainSlot
{
    /// <summary>There is no `ZaloData` folder; Zalo will start at the login screen.</summary>
    public sealed record Empty : MainSlot;
    /// <summary>It holds this profile's data.</summary>
    public sealed record Saved(string Id) : MainSlot;
    /// <summary>It holds data that isn't saved as a profile yet.</summary>
    public sealed record Unsaved : MainSlot;

    public static readonly MainSlot EmptySlot = new Empty();
    public static readonly MainSlot UnsavedSlot = new Unsaved();

    public bool IsProfile(string id) => this is Saved s && s.Id == id;
}

/// <summary>Where a profile's data is.</summary>
public enum Place
{
    /// <summary>In the main `ZaloData` folder, used by the normal Zalo app.</summary>
    Main,
    /// <summary>In its own profile folder.</summary>
    Parked,
    /// <summary>Nowhere yet: the profile has never been opened.</summary>
    New,
}

public sealed record ProfileStatus(Profile Profile, Place Place, int? RunningPid = null,
                                   string? ZaloUserId = null, string? DataFolder = null)
{
    /// <summary>Whether a Zalo window has this profile open.</summary>
    public bool IsOpen => RunningPid != null;
}

/// <summary>`state.json`.</summary>
internal sealed record State
{
    [JsonPropertyName("main"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Main { get; init; }
}

/// <summary>What `backup.json` in a backup folder records.</summary>
public sealed record BackupInfo
{
    /// <summary>The data stored, counting hard-linked files once.</summary>
    [JsonPropertyName("bytes")]
    public long Bytes { get; init; }

    [JsonPropertyName("createdAt"), JsonConverter(typeof(IsoDateConverter))]
    public DateTime CreatedAt { get; init; }

    /// <summary>Every file name, including the extra names of hard-linked files.</summary>
    [JsonPropertyName("files")]
    public int Files { get; init; }

    [JsonPropertyName("format")]
    public int Format { get; init; } = 1;

    /// <summary>How many file names were recreated as hard links.</summary>
    [JsonPropertyName("links"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Links { get; init; }

    [JsonPropertyName("profileID")]
    public string ProfileId { get; init; } = "";

    [JsonPropertyName("profileName")]
    public string ProfileName { get; init; } = "";

    [JsonPropertyName("zaloUserID"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ZaloUserId { get; init; }
}

/// <summary>ISO 8601 in UTC without fractions, as Swift's `.iso8601` writes it: 2026-10-20T13:00:00Z.</summary>
internal sealed class IsoDateConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        DateTimeOffset.Parse(reader.GetString()!, System.Globalization.CultureInfo.InvariantCulture).UtcDateTime;

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture));
}

internal static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        // Keep Vietnamese names readable in the files, as on macOS.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static T? Read<T>(string path) where T : class
    {
        try { return JsonSerializer.Deserialize<T>(File.ReadAllBytes(path), Options); }
        catch { return null; }
    }

    /// <summary>Writes through a temporary file and a rename, so a crash never leaves half a file.</summary>
    public static void Write<T>(string path, T value)
    {
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, JsonSerializer.SerializeToUtf8Bytes(value, Options));
        File.Move(temp, path, overwrite: true);
    }
}
