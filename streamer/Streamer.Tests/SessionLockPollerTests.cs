using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// STREAM.md §4.5's OpenInputDesktop fallback. The probe is injected (same DI shape as
/// FakeFileTransport standing in for a real socket) so the 2s-poll logic is testable
/// without a real desktop station — every test here passes <c>interval: TimeSpan.Zero</c>
/// to skip the live <see cref="System.Threading.Timer"/> entirely and calls
/// <see cref="SessionLockPoller.Poll"/> directly, so nothing waits on real time.
/// </summary>
public class SessionLockPollerTests
{
    [Fact]
    public void AnInaccessibleDesktopLocksTheMonitor()
    {
        var monitor = new SessionLockMonitor();
        using var poller = new SessionLockPoller(monitor, () => false, TimeSpan.Zero);

        poller.Poll();

        Assert.True(monitor.IsBlocked);
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);
    }

    [Fact]
    public void AnAccessibleDesktopReportsUnlockedEvenIfNeverLockedBefore()
    {
        var monitor = new SessionLockMonitor();
        using var poller = new SessionLockPoller(monitor, () => true, TimeSpan.Zero);

        poller.Poll();

        Assert.False(monitor.IsBlocked);
    }

    [Fact]
    public void TogglingTheProbeTogglesTheMonitorAcrossPolls()
    {
        bool accessible = true;
        var monitor = new SessionLockMonitor();
        using var poller = new SessionLockPoller(monitor, () => accessible, TimeSpan.Zero);

        poller.Poll();
        Assert.False(monitor.IsBlocked);

        accessible = false;
        poller.Poll();
        Assert.True(monitor.IsBlocked);

        accessible = true;
        poller.Poll();
        Assert.False(monitor.IsBlocked);
    }

    [Fact]
    public void RepeatedIdenticalPollsDoNotRefireTheMonitorsChangedEvent()
    {
        // SessionLockMonitor.Set is idempotent (SessionLockMonitorTests pins this
        // directly); this test pins that the poller relies on exactly that rather than
        // deduplicating on its own side, since STREAM.md §4.5 has the poller running
        // unconditionally alongside the WM_WTSSESSION_CHANGE hook rather than instead of
        // it, and a poll landing on an already-current state (the common case, every 2s)
        // must cost nothing.
        var monitor = new SessionLockMonitor();
        using var poller = new SessionLockPoller(monitor, () => false, TimeSpan.Zero);
        int changes = 0;
        monitor.Changed += _ => changes++;

        poller.Poll();
        poller.Poll();
        poller.Poll();

        Assert.Equal(1, changes);
        Assert.True(monitor.IsBlocked);
    }

    [Fact]
    public void DisposeStopsTheTimerWithoutThrowing()
    {
        var monitor = new SessionLockMonitor();
        var poller = new SessionLockPoller(monitor, () => true, TimeSpan.FromMilliseconds(50));
        poller.Dispose();
        poller.Dispose(); // idempotent, matching Timer.Dispose's own contract
    }
}
