using System.Globalization;

namespace ZaloProfiles.Core;

public static class Disk
{
    /// <summary>Free space on the drive that holds <paramref name="path"/>.</summary>
    public static long? FreeBytes(string path) => Native.FreeBytes(ExistingAncestor(path));

    /// <summary>The space a folder's files take. Junctions and symbolic links aren't followed.</summary>
    public static long? AllocatedSize(string folder)
    {
        if (!Directory.Exists(folder)) return null;
        long total = 0;
        foreach (var file in Files(folder))
        {
            // Files a running Zalo removes mid-scan are skipped; the total is still about right.
            try { total += new FileInfo(file).Length; }
            catch { }
        }
        return total;
    }

    /// <summary>Every file under a folder, without descending into junctions or symbolic links.</summary>
    internal static IEnumerable<string> Files(string folder)
    {
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
            ReturnSpecialDirectories = false,
        };
        return Directory.EnumerateFiles(folder, "*", options);
    }

    /// <summary>Whether two paths are on the same drive.</summary>
    public static bool SameVolume(string a, string b)
    {
        var x = Native.VolumeId(ExistingAncestor(a));
        var y = Native.VolumeId(ExistingAncestor(b));
        return x != null && string.Equals(x, y, StringComparison.OrdinalIgnoreCase);
    }

    static readonly CultureInfo Vietnamese = CultureInfo.GetCultureInfo("vi-VN");

    /// <summary>Like Finder and macOS: decimal units, so 1 GB is 1 000 000 000 bytes.</summary>
    public static string Format(long bytes)
    {
        if (bytes < 1000) return $"{bytes} byte";
        string[] units = ["KB", "MB", "GB", "TB"];
        double value = bytes;
        var unit = -1;
        while (value >= 1000 && unit < units.Length - 1)
        {
            value /= 1000;
            unit++;
        }
        var format = unit switch { 0 => "0", 1 => "0.#", _ => "0.##" };
        return value.ToString(format, Vietnamese) + " " + units[unit];
    }

    internal static string ExistingAncestor(string path)
    {
        var probe = Path.GetFullPath(path);
        while (!Directory.Exists(probe))
        {
            var parent = Path.GetDirectoryName(probe);
            if (parent == null) break;
            probe = parent;
        }
        return probe;
    }
}
