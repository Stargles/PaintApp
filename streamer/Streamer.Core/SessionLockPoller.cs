namespace Streamer.Core;

/// <summary>
/// STREAM.md §4.5's fallback: polls <c>OpenInputDesktop</c> every 2s and feeds the
/// result into a <see cref="SessionLockMonitor"/>, for the case
/// <c>WM_WTSSESSION_CHANGE</c> never reaches a process the Scheduled Task launched
/// (unconfirmed until this stage tested it against the real task — §8). Also covers the
/// startup case the window-message path cannot: a message only fires on a *transition*,
/// so a process that starts already locked (the laptop's default state, most of the
/// time) would otherwise report unblocked until the next lock/unlock. Runs alongside
/// the WM_WTSSESSION_CHANGE hook rather than instead of it — both feed the same
/// <see cref="SessionLockMonitor"/>, whose <c>HandlePollResult</c>/<c>HandleSessionLock</c>
/// etc. are idempotent, so double-reporting the same state costs nothing and there is no
/// need to pick a winner between the two mechanisms.
///
/// The probe is injected so the 2s-interval polling logic is testable without a real
/// desktop station (Streamer.Tests/SessionLockPollerTests.cs calls <see cref="Poll"/>
/// directly against a fake probe rather than waiting on the timer).
/// </summary>
public sealed class SessionLockPoller : IDisposable
{
    public static readonly TimeSpan DefaultInterval = TimeSpan.FromSeconds(2);

    private readonly SessionLockMonitor _monitor;
    private readonly Func<bool> _isSessionAccessible;
    private readonly Timer? _timer;

    /// <param name="monitor">Fed via <see cref="SessionLockMonitor.HandlePollResult"/> on every poll.</param>
    /// <param name="isSessionAccessible">True when the input desktop opens and is named
    /// "Default" — i.e. unlocked. Defaults to the real <c>OpenInputDesktop</c> probe;
    /// tests inject a fake.</param>
    /// <param name="interval">Defaults to 2s (STREAM.md §4.5). Pass <see cref="TimeSpan.Zero"/>
    /// to skip starting the timer altogether and call <see cref="Poll"/> directly instead —
    /// what the tests do, so nothing here waits on real time.</param>
    public SessionLockPoller(SessionLockMonitor monitor, Func<bool>? isSessionAccessible = null, TimeSpan? interval = null)
    {
        _monitor = monitor;
        _isSessionAccessible = isSessionAccessible ?? NativeMethods.IsInputDesktopAccessible;
        if (interval != TimeSpan.Zero)
        {
            _timer = new Timer(_ => Poll(), null, TimeSpan.Zero, interval ?? DefaultInterval);
        }
    }

    /// <summary>Runs one probe and reports it to the monitor. Public so a test (or the
    /// first synchronous check at startup, ahead of the timer's first tick) can call it
    /// without waiting.</summary>
    public void Poll() => _monitor.HandlePollResult(_isSessionAccessible());

    public void Dispose() => _timer?.Dispose();
}
