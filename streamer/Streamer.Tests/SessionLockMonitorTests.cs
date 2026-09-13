using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// STREAM.md §4.5: SessionLockMonitor's state machine, exercised with no window handle
/// and no P/Invoke at all — every Handle* method is just two booleans and an event, which
/// is exactly what makes it testable without a real desktop station (the type's own doc
/// comment explains why the Win32 plumbing was kept out of it).
/// </summary>
public class SessionLockMonitorTests
{
    [Fact]
    public void StartsUnblocked()
    {
        var monitor = new SessionLockMonitor();
        Assert.False(monitor.IsBlocked);
        Assert.Null(monitor.Reason);
    }

    [Fact]
    public void LockBlocksWithTheSentence()
    {
        var monitor = new SessionLockMonitor();
        int changes = 0;
        monitor.Changed += _ => changes++;

        monitor.HandleSessionLock();

        Assert.True(monitor.IsBlocked);
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);
        Assert.Equal(1, changes);
    }

    [Fact]
    public void UnlockAfterLockClearsIt()
    {
        var monitor = new SessionLockMonitor();
        monitor.HandleSessionLock();
        int changes = 0;
        monitor.Changed += _ => changes++;

        monitor.HandleSessionUnlock();

        Assert.False(monitor.IsBlocked);
        Assert.Null(monitor.Reason);
        Assert.Equal(1, changes);
    }

    [Fact]
    public void RedundantLockDoesNotRefireChanged()
    {
        var monitor = new SessionLockMonitor();
        monitor.HandleSessionLock();
        int changes = 0;
        monitor.Changed += _ => changes++;

        monitor.HandleSessionLock(); // already locked

        Assert.Equal(0, changes);
        Assert.True(monitor.IsBlocked);
    }

    [Fact]
    public void ConsoleDisconnectBlocksTheSameAsALock()
    {
        var monitor = new SessionLockMonitor();
        monitor.HandleConsoleDisconnect();
        Assert.True(monitor.IsBlocked);
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);

        monitor.HandleConsoleConnect();
        Assert.False(monitor.IsBlocked);
    }

    [Fact]
    public void DisplayOffBlocksWithItsOwnSentence()
    {
        var monitor = new SessionLockMonitor();
        monitor.HandleDisplayOff();

        Assert.True(monitor.IsBlocked);
        Assert.Equal(SessionLockMonitor.DisplayOffReason, monitor.Reason);

        monitor.HandleDisplayOn();
        Assert.False(monitor.IsBlocked);
    }

    [Fact]
    public void ALockTakesPrecedenceOverAnAlreadyDarkDisplay()
    {
        // The pipeline holds the display awake while running (§4.2), so a lock should
        // rarely coincide with a display already off — but if it does (or the two race),
        // the reported reason is the lock, per SessionLockMonitor's own doc comment on
        // why a lock is "the expected, unremarkable cause".
        var monitor = new SessionLockMonitor();
        monitor.HandleDisplayOff();
        Assert.Equal(SessionLockMonitor.DisplayOffReason, monitor.Reason);

        monitor.HandleSessionLock();
        Assert.True(monitor.IsBlocked);
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);

        // Clearing the display state while still locked changes nothing observable.
        int changes = 0;
        monitor.Changed += _ => changes++;
        monitor.HandleDisplayOn();
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);
        Assert.True(monitor.IsBlocked);

        // Unlocking now falls through to the display state, which is already "on" —
        // so this is the transition back to fully unblocked.
        monitor.HandleSessionUnlock();
        Assert.False(monitor.IsBlocked);
        Assert.Null(monitor.Reason);
    }

    [Fact]
    public void UnlockingWhileTheDisplayIsStillOffFallsThroughToTheDisplayReason()
    {
        var monitor = new SessionLockMonitor();
        monitor.HandleDisplayOff();
        monitor.HandleSessionLock();
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);

        int changes = 0;
        monitor.Changed += _ => changes++;
        monitor.HandleSessionUnlock();

        Assert.True(monitor.IsBlocked); // still blocked -- the display is still off
        Assert.Equal(SessionLockMonitor.DisplayOffReason, monitor.Reason);
        Assert.Equal(1, changes); // the reason changed even though IsBlocked did not
    }

    [Fact]
    public void PollResultFoldsIntoTheSameLockedFlagAsTheWtsMessages()
    {
        var monitor = new SessionLockMonitor();
        monitor.HandlePollResult(sessionAccessible: false);
        Assert.True(monitor.IsBlocked);
        Assert.Equal(SessionLockMonitor.LockedReason, monitor.Reason);

        // A WTS message clearing it works interchangeably with a poll result clearing it —
        // the two mechanisms share one flag by design (STREAM.md §4.5: "both feed the same
        // SessionLockMonitor").
        monitor.HandleSessionUnlock();
        Assert.False(monitor.IsBlocked);

        monitor.HandlePollResult(sessionAccessible: true);
        Assert.False(monitor.IsBlocked);
    }
}
