using ZaloProfiles.Core;

namespace ZaloProfiles.Core.Tests;

/// <summary>Runs only with ZALO_INTEGRATION=1 on a computer with Zalo installed. Starts a real Zalo in a
/// separate, empty home folder (it shows the login screen), finds it, brings it forward and asks it to quit.
/// The person's own Zalo and its data are never touched.</summary>
public sealed class RealZaloFactAttribute : FactAttribute
{
    public RealZaloFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("ZALO_INTEGRATION") != "1")
            Skip = "Đặt ZALO_INTEGRATION=1 để chạy với Zalo thật.";
    }
}

public sealed class RealZaloTests : IDisposable
{
    readonly string _home = Path.Combine(Path.GetTempPath(), $"zalo-switcher-real-{Guid.NewGuid():N}");

    public void Dispose()
    {
        try { Directory.Delete(_home, recursive: true); } catch { }
    }

    [RealZaloFact]
    public void ASeparateZaloStartsOnItsOwnDataAndQuitsCleanly()
    {
        var layout = Layout.System();
        Assert.True(File.Exists(layout.ZaloLauncher), $"Zalo is not installed at {layout.ZaloLauncher}");
        Assert.Null(SystemZaloControl.IsolationProblem());
        var zalo = new SystemZaloControl(layout);
        var data = Layout.DataInHome(_home);
        var mainBefore = zalo.PidUsing(layout.LiveData);

        zalo.LaunchIsolated(layout.ZaloLauncher, _home);
        var pid = WaitFor(() => zalo.PidUsing(data), TimeSpan.FromSeconds(40));
        Assert.NotNull(pid);
        Assert.True(Directory.Exists(data), "Zalo made its data folder inside the separate home");
        Assert.NotEqual(mainBefore, pid);

        // A second start only brings the same Zalo forward.
        zalo.Activate(data, pid!.Value);
        Thread.Sleep(5000);
        Assert.Equal(pid, zalo.PidUsing(data));

        zalo.Quit(data, TimeSpan.FromSeconds(60));
        Assert.Null(zalo.PidUsing(data));
        Assert.Equal(mainBefore, zalo.PidUsing(layout.LiveData));
    }

    /// <summary>Leaves one small folder in the Recycle Bin.</summary>
    [RealZaloFact]
    public void RemovedProfilesGoToTheRecycleBin()
    {
        var profile = Path.Combine(_home, "zalo-switcher-recycle-bin-test");
        Directory.CreateDirectory(Path.Combine(profile, "AppData", "Roaming", "ZaloData"));
        File.WriteAllText(Path.Combine(profile, "profile.json"), "{}");

        Assert.True(Native.MoveToRecycleBin(profile));
        Assert.False(Directory.Exists(profile));
    }

    static int? WaitFor(Func<int?> probe, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (probe() is { } value) return value;
            Thread.Sleep(500);
        }
        return null;
    }
}
