using System.Collections;
using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace ZaloProfiles.Core;

/// <summary>Everything the profile manager needs from the running system. Tests swap in a fake.</summary>
public interface IZaloControl
{
    /// <summary>The pid of the Zalo instance that has <paramref name="dataFolder"/> open, if any.</summary>
    int? PidUsing(string dataFolder);
    /// <summary>Whether any Zalo instance is running (main or side by side).</summary>
    bool AnyInstanceRunning();
    /// <summary>Asks the Zalo instance using <paramref name="dataFolder"/> to quit, and waits until it and its helpers are gone.</summary>
    void Quit(string dataFolder, TimeSpan timeout);
    /// <summary>Starts Zalo normally, so it uses the main `ZaloData` folder.</summary>
    void LaunchMain(string launcher);
    /// <summary>Starts another Zalo instance whose home folder (USERPROFILE) is <paramref name="home"/>.</summary>
    void LaunchIsolated(string launcher, string home);
    /// <summary>Brings an already running instance to the front, out of the notification area if it hid there.</summary>
    void Activate(string dataFolder, int pid);
}

public sealed partial class SystemZaloControl(Layout layout) : IZaloControl
{
    /// <summary>The argument Zalo's own updater sends to make a running Zalo go through its normal quit.</summary>
    const string QuitArgument = "--z-update-force-quit";
    static readonly string[] ZaloProcessNames = ["Zalo.exe", "ZaloCall.exe", "ZaloCap.exe"];

    public int? PidUsing(string dataFolder)
    {
        // Electron passes the data folder to every helper as --user-data-dir; the main process is their parent.
        var processes = Native.ListProcesses();
        var byPid = processes.ToDictionary(p => p.Pid);
        var folder = Normalize(dataFolder);
        foreach (var process in processes.Where(p => IsName(p.Name, "Zalo.exe")))
        {
            var commandLine = Native.CommandLine(process.Pid);
            if (commandLine == null || UserDataDir(commandLine) is not { } used || Normalize(used) != folder) continue;
            if (byPid.TryGetValue(process.ParentPid, out var parent) && IsName(parent.Name, "Zalo.exe")
                && Native.IsAlive(parent.Pid))
                return parent.Pid;
            // A helper whose main process is gone still has the folder open.
            return process.Pid;
        }
        return null;
    }

    public bool AnyInstanceRunning() => Native.ListProcesses().Any(p => IsName(p.Name, "Zalo.exe"));

    public void Quit(string dataFolder, TimeSpan timeout)
    {
        if (PidUsing(dataFolder) is not { } pid) return;
        // Wait for the helpers too: the call and screenshot helpers write into the data folder.
        var related = RelatedProcesses(pid, dataFolder);
        var exe = Native.ImagePath(pid) ?? layout.ZaloLauncher;
        // Starting Zalo again on the same data folder hands the argument to the running Zalo, which then
        // quits the way it does before installing an update: it tells its window to save and closes.
        // Zalo is never killed.
        Signal(exe, dataFolder);
        var lastSignal = DateTime.UtcNow;
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            Thread.Sleep(500);
            if (related.All(p => !Native.IsAlive(p)) && PidUsing(dataFolder) == null) return;
            // If Zalo quit on its own just before the signal, the signal itself started a new Zalo on
            // the folder; send it the same request.
            if (PidUsing(dataFolder) is { } current && !related.Contains(current))
            {
                related.UnionWith(RelatedProcesses(current, dataFolder));
                if (DateTime.UtcNow - lastSignal > TimeSpan.FromSeconds(5))
                {
                    Signal(Native.ImagePath(current) ?? exe, dataFolder);
                    lastSignal = DateTime.UtcNow;
                }
            }
        }
        throw ProfileError.ZaloDidNotQuit();
    }

    public void LaunchMain(string launcher) => Start(launcher, "", MainEnvironment());

    public void LaunchIsolated(string launcher, string home)
    {
        if (IsolationProblem() is { } problem) throw ProfileError.IsolationUnsupported(problem);
        Start(launcher, "", IsolatedEnvironment(home));
    }

    public void Activate(string dataFolder, int pid)
    {
        // A second start on the same data folder makes the running Zalo show its window and exits.
        try { Start(Native.ImagePath(pid) ?? layout.ZaloLauncher, "", EnvironmentFor(dataFolder)); }
        catch { }
    }

    /// <summary>Why this computer can't give a Zalo its own data folder, or null if it can. Zalo finds its
    /// data through the AppData folder, which Windows defines relative to %USERPROFILE% unless it has
    /// been redirected (for example to a network drive).</summary>
    public static string? IsolationProblem()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders");
        var value = key?.GetValue("AppData", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
        if (value == null || value.TrimEnd('\\').Equals(@"%USERPROFILE%\AppData\Roaming", StringComparison.OrdinalIgnoreCase))
            return null;
        return $"thư mục AppData của Windows đã được chuyển tới {value}.";
    }

    void Signal(string exe, string dataFolder)
    {
        using var process = Start(exe, QuitArgument, EnvironmentFor(dataFolder));
        // It hands over the argument and exits within a second or two.
        process.WaitForExit(15_000);
    }

    // MARK: Environments

    IDictionary<string, string> EnvironmentFor(string dataFolder)
    {
        if (Normalize(dataFolder) == Normalize(layout.LiveData)) return MainEnvironment();
        var home = Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(Path.GetFullPath(dataFolder))))!;
        return IsolatedEnvironment(home);
    }

    Dictionary<string, string> MainEnvironment()
    {
        var env = CurrentEnvironment();
        env["USERPROFILE"] = layout.RealHome;
        env["APPDATA"] = layout.RoamingAppData;
        env["LOCALAPPDATA"] = layout.LocalAppData;
        return env;
    }

    /// <summary>With USERPROFILE pointing at the profile folder, Windows reports its AppData\Roaming as
    /// Zalo's AppData, so Electron's user data folder becomes the profile's own ZaloData. TEMP moves too,
    /// because Zalo also derives a home folder from it.</summary>
    static Dictionary<string, string> IsolatedEnvironment(string home)
    {
        var env = CurrentEnvironment();
        var temp = Path.Combine(home, "AppData", "Local", "Temp");
        Directory.CreateDirectory(temp);
        Directory.CreateDirectory(Path.Combine(home, "AppData", "Roaming"));
        env["USERPROFILE"] = home;
        env["APPDATA"] = Path.Combine(home, "AppData", "Roaming");
        env["LOCALAPPDATA"] = Path.Combine(home, "AppData", "Local");
        env["TEMP"] = temp;
        env["TMP"] = temp;
        return env;
    }

    static Dictionary<string, string> CurrentEnvironment()
    {
        var env = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
            env[(string)entry.Key] = (string?)entry.Value ?? "";
        return env;
    }

    static Process Start(string exe, string arguments, IDictionary<string, string> env)
    {
        if (!File.Exists(exe)) throw ProfileError.ZaloNotInstalled(exe);
        var info = new ProcessStartInfo(exe, arguments)
        {
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(exe)!,
        };
        info.Environment.Clear();
        foreach (var (key, value) in env) info.Environment[key] = value;
        try
        {
            return Process.Start(info) ?? throw ProfileError.LaunchFailed(exe);
        }
        catch (Exception error) when (error is not ProfileError)
        {
            throw ProfileError.LaunchFailed(error.Message);
        }
    }

    // MARK: Processes

    /// <summary>The main process, its descendants, and any of Zalo's own processes whose command line
    /// names the data folder (helpers that outlive their parent).</summary>
    static HashSet<int> RelatedProcesses(int root, string dataFolder)
    {
        var result = new HashSet<int> { root };
        // Only Zalo's own programs count: Windows reuses pids, so an unrelated process can name a long-gone
        // process as its parent.
        var processes = Native.ListProcesses().Where(p => ZaloProcessNames.Any(n => IsName(p.Name, n))).ToList();
        var children = processes.ToLookup(p => p.ParentPid, p => p.Pid);
        var folder = Normalize(dataFolder) + "\\";
        foreach (var process in processes)
        {
            var commandLine = Native.CommandLine(process.Pid);
            if (commandLine != null && (commandLine + "\\").Contains(folder, StringComparison.OrdinalIgnoreCase))
                result.Add(process.Pid);
        }
        var queue = new Stack<int>([root]);
        var seen = new HashSet<int> { root };
        while (queue.TryPop(out var next))
        {
            foreach (var child in children[next])
            {
                if (seen.Add(child)) queue.Push(child);
            }
        }
        result.UnionWith(seen);
        return result;
    }

    [GeneratedRegex("--user-data-dir=(?:\"([^\"]+)\"|(\\S+))", RegexOptions.IgnoreCase)]
    private static partial Regex UserDataDirPattern();

    internal static string? UserDataDir(string commandLine)
    {
        var match = UserDataDirPattern().Match(commandLine);
        if (!match.Success) return null;
        return match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value;
    }

    static bool IsName(string name, string expected) => name.Equals(expected, StringComparison.OrdinalIgnoreCase);

    internal static string Normalize(string path) =>
        Path.GetFullPath(path).TrimEnd('\\').ToUpperInvariant();
}
