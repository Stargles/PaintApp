namespace Streamer.Core;

/// <summary>
/// STREAM.md §4.5: tracks whether kevin's interactive session is in a state where
/// Windows Graphics Capture cannot see the desktop — locked, disconnected, or (rarely,
/// since a running pipeline holds the display awake — §4.2) the display powered off —
/// and exposes one sentence for STATUS's `reason` field and the tray window's status
/// area. Pure state machine, no P/Invoke and no window handle: the Win32 plumbing
/// (WTSRegisterSessionNotification / WM_WTSSESSION_CHANGE, RegisterPowerSettingNotification
/// / WM_POWERBROADCAST) lives in Streamer.Tray/MainWindow, which forwards the two or three
/// integers a window message carries into the Handle* methods below — nothing here
/// references a window at all, which is what makes the state machine unit-testable
/// (Streamer.Tests/SessionLockMonitorTests.cs) without a real desktop station.
///
/// A locked session and a dark display are tracked independently because they can
/// coincide or diverge (a lock eventually dims the display too; a display can go dark
/// on its own if <c>ES_DISPLAY_REQUIRED</c> ever lapses) but only one reason is ever
/// reported: a lock wins, because it is the expected, unremarkable cause (any idle
/// laptop locks) while an unlocked session losing its display is the surprising one
/// worth naming on its own.
/// </summary>
public sealed class SessionLockMonitor
{
    public const string LockedReason = "The laptop is locked";
    public const string DisplayOffReason = "The laptop's display is off";

    private readonly object _gate = new();
    private bool _sessionLocked;
    private bool _displayOff;

    /// <summary>True while the pipeline must not run — the capture would see nothing
    /// (locked) or the artist could not see a black stream be worth watching anyway
    /// (display off).</summary>
    public bool IsBlocked
    {
        get { lock (_gate) return _sessionLocked || _displayOff; }
    }

    /// <summary>The sentence to show, or null while unblocked. See the type doc comment
    /// for why a lock takes precedence over a dark display.</summary>
    public string? Reason
    {
        get { lock (_gate) return _sessionLocked ? LockedReason : _displayOff ? DisplayOffReason : null; }
    }

    /// <summary>Raised whenever <see cref="IsBlocked"/> or <see cref="Reason"/> actually
    /// changes (never on a redundant lock-while-locked, etc.) — StreamerSession's
    /// <c>SetEnvironmentBlockedAsync</c> is the one consumer, stopping the pipeline and
    /// broadcasting the reason on block, restarting it on unblock.</summary>
    public event Action<SessionLockMonitor>? Changed;

    /// <summary>WTS_SESSION_LOCK.</summary>
    public void HandleSessionLock() => Set(locked: true);

    /// <summary>WTS_SESSION_UNLOCK.</summary>
    public void HandleSessionUnlock() => Set(locked: false);

    /// <summary>WTS_CONSOLE_DISCONNECT — session 1 disconnected (fast user switch, or
    /// an RDP takeover of the console). Treated the same as a lock: WGC sees nothing
    /// either way, and STREAM.md never promised a distinct sentence for it.</summary>
    public void HandleConsoleDisconnect() => Set(locked: true);

    /// <summary>WTS_CONSOLE_CONNECT.</summary>
    public void HandleConsoleConnect() => Set(locked: false);

    /// <summary>The result of an OpenInputDesktop poll (SessionLockPoller) — folded into
    /// the same _sessionLocked flag as the WTS messages, since both name the same
    /// condition and the poller exists only because the messages might not arrive in a
    /// task-launched process (STREAM.md §4.5, §8).</summary>
    public void HandlePollResult(bool sessionAccessible) => Set(locked: !sessionAccessible);

    /// <summary>GUID_CONSOLE_DISPLAY_STATE data == 0 (off).</summary>
    public void HandleDisplayOff() => SetDisplay(off: true);

    /// <summary>GUID_CONSOLE_DISPLAY_STATE data == 1 (on) or == 2 (dimmed — still
    /// capturable, so treated as on).</summary>
    public void HandleDisplayOn() => SetDisplay(off: false);

    private void Set(bool locked)
    {
        bool changed;
        lock (_gate)
        {
            changed = _sessionLocked != locked;
            _sessionLocked = locked;
        }
        if (changed) Changed?.Invoke(this);
    }

    private void SetDisplay(bool off)
    {
        // Same shape as Set(bool locked): fires whenever the underlying flag itself
        // flips. That can be a false-positive event when a lock already dominates the
        // reported reason (display flag flips underneath an unaffected LockedReason) —
        // harmless, since the one consumer (StreamerSession.SetEnvironmentBlockedAsync)
        // compares the effective (blocked, reason) pair before doing anything and no-ops
        // on a redundant call. Simplicity here over exactness costs nothing.
        bool changed;
        lock (_gate)
        {
            changed = _displayOff != off;
            _displayOff = off;
        }
        if (changed) Changed?.Invoke(this);
    }
}
