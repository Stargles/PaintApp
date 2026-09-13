using Streamer.Core;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// STREAM.md §4.5: StreamerSession.SetEnvironmentBlockedAsync, the one method a
/// SessionLockMonitor.Changed event drives. Covers everything reachable without a real
/// GstProcess — no test here calls ProbeEncoderAsync or SetSourceAsync, so _currentSource
/// stays null and StartPipelineLockedAsync's first line (which throws if Encoder is still
/// null) is never actually exercised; the case that matters, "does a call path reach that
/// throw when it should not", is what RegressionUnblockingWithAConnectedClientButNoSourceDoesNotThrow
/// pins. A real pipeline actually starting and reaching streaming:true is confirmed by
/// driving the deployed app on the laptop (STREAM.md's Verify step) instead: GstProcess
/// spawns a real gst-launch-1.0 process against a real capturable desktop, which a
/// `dotnet test` run over PC's own non-interactive SSH window station cannot reliably
/// provide (§4.3 — EnumWindows there sees the fake "WinDisc" placeholder).
/// </summary>
public class StreamerSessionEnvironmentBlockTests
{
    private static StreamerSession NewSession(out FakeFrameSink sink)
    {
        var session = new StreamerSession(@"C:\nonexistent", _ => { });
        sink = new FakeFrameSink();
        session.AddSink(sink);
        return session;
    }

    [Fact]
    public async Task BlockingReportsStreamingFalseWithTheGivenReason()
    {
        var session = NewSession(out var sink);

        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.LockedReason);

        var status = Assert.Single(sink.StatusMessages);
        Assert.False(status.Streaming);
        Assert.Equal(SessionLockMonitor.LockedReason, status.Reason);
    }

    [Fact]
    public async Task BlockingOverridesNoSourceSelectedAsTheReportedReason()
    {
        var session = NewSession(out var sink);
        await session.OnClientConnectedAsync(); // hasClient=true, no source -> "No source selected"
        Assert.Equal("No source selected", sink.LastStatus!.Reason);

        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.DisplayOffReason);

        Assert.Equal(SessionLockMonitor.DisplayOffReason, sink.LastStatus!.Reason);
        Assert.False(sink.LastStatus!.Streaming);
    }

    [Fact]
    public async Task UnblockingWithNoClientConnectedNeverThrowsAndFallsBackToNoSourceSelected()
    {
        var session = NewSession(out var sink);
        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.LockedReason);

        await session.SetEnvironmentBlockedAsync(false, null);

        Assert.False(sink.LastStatus!.Streaming);
        Assert.Equal("No source selected", sink.LastStatus!.Reason);
    }

    /// <summary>
    /// StartPipelineLockedAsync's very first line throws InvalidOperationException if
    /// Encoder is still null (ProbeEncoderAsync must run first) — every existing caller
    /// (OnClientConnectedAsync, HandleControlAsync's Resume, SetSourceAsync) only reaches
    /// that method when _currentSource is already non-null, so the throw cannot fire from
    /// them in practice. SetEnvironmentBlockedAsync's unblock branch did not have that
    /// same guard when first written — a client connecting while locked, then the laptop
    /// unlocking with no source ever picked, would have called StartPipelineLockedAsync
    /// with Encoder still null and crashed the unlock handler. Fixed by checking
    /// `source != null` alongside `hasClient`/`!pausedByClient`, mirroring
    /// OnClientConnectedAsync's own guard; this test is what would have caught it.
    /// </summary>
    [Fact]
    public async Task RegressionUnblockingWithAConnectedClientButNoSourceDoesNotThrow()
    {
        var session = NewSession(out var sink);
        await session.OnClientConnectedAsync(); // hasClient=true, _currentSource stays null
        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.LockedReason);

        var exception = await Record.ExceptionAsync(() => session.SetEnvironmentBlockedAsync(false, null));

        Assert.Null(exception);
        Assert.False(sink.LastStatus!.Streaming);
        Assert.Equal("No source selected", sink.LastStatus!.Reason);
    }

    [Fact]
    public async Task RedundantBlockCallWithTheSameReasonDoesNotReBroadcast()
    {
        var session = NewSession(out var sink);

        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.LockedReason);
        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.LockedReason);

        Assert.Single(sink.StatusMessages);
    }

    [Fact]
    public async Task ADifferentReasonWhileAlreadyBlockedDoesReBroadcast()
    {
        // E.g. the laptop was locked, and then (rare, since a running pipeline holds the
        // display awake) the display also went dark before it unlocked — SessionLockMonitor
        // itself would not surface this (lock wins, §4.5), but SetEnvironmentBlockedAsync's
        // own guard is reason-sensitive on its own terms, independent of the monitor.
        var session = NewSession(out var sink);

        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.LockedReason);
        await session.SetEnvironmentBlockedAsync(true, SessionLockMonitor.DisplayOffReason);

        Assert.Equal(2, sink.StatusMessages.Count);
        Assert.Equal(SessionLockMonitor.DisplayOffReason, sink.LastStatus!.Reason);
    }
}
