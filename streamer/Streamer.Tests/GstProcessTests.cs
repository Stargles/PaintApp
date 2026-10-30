using System.Net;
using System.Net.Sockets;
using Streamer.Core;
using Microsoft.Win32.SafeHandles;
using Xunit;

namespace Streamer.Tests;

public class GstProcessTests
{
    [Fact]
    public Task AFailedLaunchRetiresItsListenerBeforeTheFailureIsReported() =>
        ObserveFailedLaunch(assertListener: true);

    [Fact]
    public Task AFailedLaunchReportsTheOriginalMissingExecutable() =>
        ObserveFailedLaunch(assertListener: false);

    [Fact]
    public Task ACleanupFailureStillRetiresTheListenerAndReportsBothErrors() =>
        ObserveFailedLaunch(assertListener: true, failCleanup: true);

    private static async Task ObserveFailedLaunch(bool assertListener, bool failCleanup = false)
    {
        string missing = Path.Combine(Path.GetTempPath(), $"paintstreamer-missing-{Guid.NewGuid():N}.exe");
        int port = 0;
        var failure = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var releaseFailure = new ManualResetEventSlim();
        const string cleanupReason = "owned process cleanup failure";
        SafeProcessHandle? processHandle = null;
        string executable = failCleanup ? Path.Combine(Environment.SystemDirectory, "cmd.exe") : missing;
        var pipeline = new GstProcess(executable,
            value => { Volatile.Write(ref port, value); return failCleanup ? "/c exit 0" : ""; }, message =>
        {
            if (!message.StartsWith("GstProcess: pipeline run failed: ")) return;
            failure.TrySetResult(message);
            if (!releaseFailure.Wait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Owned failure gate was not released");
        }, async process =>
        {
            processHandle = process.SafeHandle;
            await process.WaitForExitAsync();
            if (failCleanup) throw new InvalidOperationException(cleanupReason);
        });
        try
        {
            await pipeline.StartAsync();
            string diagnostic = await failure.Task.WaitAsync(TimeSpan.FromSeconds(10));
            if (assertListener)
            {
                Assert.NotEqual(0, Volatile.Read(ref port));
                var probe = new TcpListener(IPAddress.Loopback, port);
                try { Assert.Null(Record.Exception(probe.Start)); }
                finally { probe.Stop(); }
            }
            else Assert.Contains(Path.GetFileName(missing), diagnostic);
            if (failCleanup)
            {
                Assert.Contains("exited before connecting", diagnostic);
                Assert.Contains(cleanupReason, diagnostic);
                Assert.True(processHandle is { IsClosed: true });
            }
        }
        finally
        {
            // Cancel while the first failure is held, then release it: no retry can launch.
            Task stop = pipeline.StopAsync();
            releaseFailure.Set();
            try
            {
                await stop.WaitAsync(TimeSpan.FromSeconds(10));
                await pipeline.DisposeAsync();
            }
            finally { processHandle?.Dispose(); }
        }
    }
}
