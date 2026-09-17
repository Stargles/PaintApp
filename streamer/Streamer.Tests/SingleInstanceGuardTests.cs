using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

/// <summary>TODO (99): the double-click-while-the-task-instance-is-running guard. A named
/// <see cref="Mutex"/>'s ownership is per-THREAD, not per-process, so a single test process can
/// still exercise real cross-instance exclusion by acquiring on a background thread and probing
/// from the test's own thread (mirroring two separate processes, which is what the shortcut launch
/// and the task launch actually are) rather than acquiring twice on the same thread, which a named
/// mutex always allows (recursive ownership) and would prove nothing.</summary>
public class SingleInstanceGuardTests
{
    private static string UniqueName() => $"PaintStreamer.Tests.{Guid.NewGuid():N}";

    [Fact]
    public void TheFirstGuardToAskAcquiresIt()
    {
        using var guard = new SingleInstanceGuard(UniqueName());
        Assert.True(guard.TryAcquire());
    }

    [Fact]
    public void ASecondGuardOnAnotherThreadCannotAcquireWhileTheFirstHoldsIt()
    {
        string name = UniqueName();
        using var first = new SingleInstanceGuard(name);
        Assert.True(first.TryAcquire());

        bool secondAcquired = true; // start true so a thread-launch failure cannot masquerade as "correctly refused"
        var thread = new Thread(() =>
        {
            using var second = new SingleInstanceGuard(name);
            secondAcquired = second.TryAcquire();
        });
        thread.Start();
        thread.Join();

        Assert.False(secondAcquired, "a second instance must not acquire the mutex while the first holds it");
    }

    [Fact]
    public void ReleasingLetsTheNextGuardAcquireIt()
    {
        string name = UniqueName();
        var first = new SingleInstanceGuard(name);
        Assert.True(first.TryAcquire());
        first.Dispose(); // the app's equivalent: the first instance exits

        bool secondAcquired = false;
        var thread = new Thread(() =>
        {
            using var second = new SingleInstanceGuard(name);
            secondAcquired = second.TryAcquire();
        });
        thread.Start();
        thread.Join();

        Assert.True(secondAcquired, "once the first instance releases (exits), the next launch must succeed");
    }

    [Fact]
    public void TwoDifferentNamesNeverContend()
    {
        using var a = new SingleInstanceGuard(UniqueName());
        using var b = new SingleInstanceGuard(UniqueName());
        Assert.True(a.TryAcquire());
        Assert.True(b.TryAcquire());
    }
}
