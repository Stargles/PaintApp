using System.Diagnostics;
using System.Text;

namespace Streamer.Core;

/// <summary>
/// Runs a process to completion (or a timeout) while actually draining its redirected
/// stdout/stderr concurrently with waiting for exit. Every "smoke test a gst-launch/
/// gst-inspect pipeline" spot in this codebase used to redirect both streams and never
/// read them — which works fine for a short, quiet command, and deadlocks solid the
/// moment the child writes more than one pipe-buffer's worth of output before anyone
/// reads it. Hit this for real on the laptop: gst-inspect-1.0.exe building kevin's
/// GStreamer plugin registry cache for the first time writes far more than that, and
/// EncoderProbe.ElementExistsAsync hung the whole app on first launch — CPU flat,
/// process "Responding: True", never returning. Centralized here once so no future
/// Process.Start callsite re-introduces the same deadlock.
/// </summary>
public static class ProcessRunner
{
    public sealed record Result(int ExitCode, string StdOut, string StdErr, bool TimedOut);

    public static async Task<Result> RunAsync(ProcessStartInfo psi, TimeSpan? timeout, CancellationToken ct)
    {
        psi.UseShellExecute = false;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.CreateNoWindow = true;

        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.Start();

        var stdOut = new StringBuilder();
        var stdErr = new StringBuilder();
        var stdOutTask = DrainAsync(proc.StandardOutput, stdOut);
        var stdErrTask = DrainAsync(proc.StandardError, stdErr);

        bool timedOut = false;
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        if (timeout.HasValue) timeoutCts.CancelAfter(timeout.Value);
        try
        {
            await proc.WaitForExitAsync(timeoutCts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            timedOut = true;
            try { proc.Kill(entireProcessTree: true); } catch { /* already gone */ }
        }

        await Task.WhenAll(stdOutTask, stdErrTask).ConfigureAwait(false);

        int exitCode = -1;
        try { exitCode = timedOut ? -1 : proc.ExitCode; } catch { /* leave -1 */ }
        return new Result(exitCode, stdOut.ToString(), stdErr.ToString(), timedOut);
    }

    private static async Task DrainAsync(StreamReader reader, StringBuilder into)
    {
        try
        {
            var buf = new char[4096];
            int n;
            while ((n = await reader.ReadAsync(buf.AsMemory()).ConfigureAwait(false)) > 0)
            {
                into.Append(buf, 0, n);
            }
        }
        catch
        {
            // A killed process tears down its pipes under us — nothing useful to do
            // beyond keeping whatever was captured before that happened.
        }
    }
}
