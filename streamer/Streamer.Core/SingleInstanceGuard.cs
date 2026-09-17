namespace Streamer.Core;

/// <summary>
/// TODO (99): the Start Menu/desktop shortcut and the triggerless on-demand Scheduled Task both
/// launch <c>Streamer.Tray.exe</c> with no arguments — the shortcut when the artist double-clicks
/// it, the task when <c>streamer-remote.sh start</c> reaches into kevin's session over SSH — so
/// double-clicking the shortcut while the task's own instance is already running must not start a
/// second one. Wraps a named <see cref="Mutex"/>: a named mutex's ownership is per-thread (in this
/// app, per-process, since each launch is its own process with its own main thread), which is
/// exactly the cross-process exclusion a singleton-app guard needs and exactly what the tests
/// below exercise from a second thread rather than a second process.
/// </summary>
public sealed class SingleInstanceGuard : IDisposable
{
    /// <summary>Session-local (no <c>Global\</c> prefix) is enough: every launch — shortcut or
    /// task — runs in kevin's own interactive session (STREAM.md §4.3), never across sessions.</summary>
    public const string AppMutexName = "PaintStreamer.SingleInstance";

    private readonly Mutex _mutex;
    private bool _owned;

    public SingleInstanceGuard(string name)
    {
        _mutex = new Mutex(initiallyOwned: false, name: name);
    }

    /// <summary>True if this guard now owns the mutex — no other instance holds it. False means
    /// another instance is already running; the caller's job is to say so and exit, not to wait.</summary>
    public bool TryAcquire()
    {
        try
        {
            _owned = _mutex.WaitOne(TimeSpan.Zero);
        }
        catch (AbandonedMutexException)
        {
            // The previous owner exited without releasing it (killed, crashed) — by definition
            // that instance is not running any more, so this is a successful acquire, not a
            // failure to report.
            _owned = true;
        }
        return _owned;
    }

    public void Dispose()
    {
        if (_owned)
        {
            try { _mutex.ReleaseMutex(); }
            catch (ApplicationException) { /* already released or never owned — nothing to undo */ }
            _owned = false;
        }
        _mutex.Dispose();
    }
}
