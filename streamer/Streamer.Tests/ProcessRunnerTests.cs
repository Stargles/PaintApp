using System.Diagnostics;
using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

public sealed class ProcessRunnerTests
{
    private static ProcessStartInfo Child(string pidFile)
    {
        // The Windows test target already requires Windows. This bounded owned child uses no
        // network or installed GStreamer. The PID file is readiness, not a guessed sleep.
        var path = pidFile.Replace("'", "''");
        return new ProcessStartInfo("powershell.exe",
            $"-NoProfile -NonInteractive -Command \"$PID | Set-Content -LiteralPath '{path}'; Start-Sleep -Seconds 20\"");
    }

    private static bool IsAlive(int pid)
    {
        try { using var process = Process.GetProcessById(pid); return !process.HasExited; }
        catch (ArgumentException) { return false; }
    }

    private static void Cleanup(int pid)
    {
        if (pid == 0) return;
        try { using var process = Process.GetProcessById(pid); if (!process.HasExited) { process.Kill(entireProcessTree: true); process.WaitForExit(); } }
        catch (ArgumentException) { }
    }

    [Fact]
    public async Task CallerCancellationJoinsOnlyItsChildAndPreservesCancellation()
    {
        string path = Path.Combine(Path.GetTempPath(), $"stream-probe-{Guid.NewGuid():N}.pid");
        int pid = 0;
        using var cancelled = new CancellationTokenSource();
        Task<ProcessRunner.Result>? run = null;
        try
        {
            run = ProcessRunner.RunAsync(Child(path), TimeSpan.FromSeconds(15), cancelled.Token);
            var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(5);
            while (DateTime.UtcNow < deadline)
            {
                try { if (File.Exists(path) && int.TryParse((await File.ReadAllTextAsync(path)).Trim(), out pid)) break; }
                catch (IOException) { }
                await Task.Delay(10);
            }
            Assert.True(pid > 0, "Owned child must reach readiness before testing cancellation.");
            Assert.True(IsAlive(pid));
            cancelled.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => run.WaitAsync(TimeSpan.FromSeconds(5)));
            Assert.False(IsAlive(pid), "Cancellation completion must mean its owned child has exited.");
        }
        finally
        {
            cancelled.Cancel();
            if (run != null) { try { await run.WaitAsync(TimeSpan.FromSeconds(5)); } catch { } }
            Cleanup(pid);
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task TimeoutJoinsItsChildAndRemainsATimeoutResult()
    {
        string path = Path.Combine(Path.GetTempPath(), $"stream-timeout-{Guid.NewGuid():N}.pid");
        int pid = 0;
        try
        {
            var result = await ProcessRunner.RunAsync(Child(path), TimeSpan.FromSeconds(3), CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(8));
            Assert.True(File.Exists(path), "The bounded child started before its timeout.");
            pid = int.Parse((await File.ReadAllTextAsync(path)).Trim());
            Assert.True(result.TimedOut);
            Assert.Equal(-1, result.ExitCode);
            Assert.False(IsAlive(pid));
        }
        finally { Cleanup(pid); if (File.Exists(path)) File.Delete(path); }
    }
}
