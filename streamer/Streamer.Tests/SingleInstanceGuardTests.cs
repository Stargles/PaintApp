using System.Diagnostics;
using System.IO.Pipes;
using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

/// <summary>TODO (99)/(171): one instance per session, and a second launch is never a silent nothing —
/// the running instance shows itself, or, if it does not answer, is replaced.</summary>
public class SingleInstanceGuardTests
{
    private static readonly TimeSpan Patient = TimeSpan.FromSeconds(10);

    private static string UniqueName() => $"PaintStreamer.Tests.{Guid.NewGuid():N}";

    private static SingleInstanceGuard RunningInstance(string name, Func<Task> onSecondLaunch)
    {
        var instance = new SingleInstanceGuard(name);
        Assert.True(instance.TryAcquire());
        instance.ServeHandoffs(onSecondLaunch);
        return instance;
    }

    [Fact]
    public void TheFirstGuardToAskAcquiresIt()
    {
        using var guard = new SingleInstanceGuard(UniqueName());
        Assert.True(guard.TryAcquire());
    }

    [Fact]
    public void ASecondGuardCannotAcquireWhileTheFirstHoldsIt()
    {
        string name = UniqueName();
        using var first = new SingleInstanceGuard(name);
        Assert.True(first.TryAcquire());

        using var second = new SingleInstanceGuard(name);
        Assert.False(second.TryAcquire(), "a second instance must not acquire the name while the first holds it");
    }

    [Fact]
    public void DisposingTheInstanceLetsTheNextLaunchAcquireIt()
    {
        string name = UniqueName();
        var first = new SingleInstanceGuard(name);
        Assert.True(first.TryAcquire());
        first.Dispose(); // the app's equivalent: the first instance exits

        using var second = new SingleInstanceGuard(name);
        Assert.True(second.TryAcquire(), "once the first instance exits, the next launch must succeed");
    }

    [Fact]
    public void TwoDifferentNamesNeverContend()
    {
        using var a = new SingleInstanceGuard(UniqueName());
        using var b = new SingleInstanceGuard(UniqueName());
        Assert.True(a.TryAcquire());
        Assert.True(b.TryAcquire());
    }

    [Fact]
    public async Task ASecondLaunchMakesTheRunningInstanceShowItselfAndLeavesIt()
    {
        string name = UniqueName();
        int shown = 0;
        using var instance = RunningInstance(name, () => { Interlocked.Increment(ref shown); return Task.CompletedTask; });

        using var launch = new SingleInstanceGuard(name);
        Assert.False(launch.TryAcquire());
        bool tookOver = await launch.HandOffOrEvictAsync(Patient);

        Assert.False(tookOver, "an instance that showed itself is left running; the launch has nothing to take over");
        Assert.Equal(1, shown);
        using var another = new SingleInstanceGuard(name);
        Assert.False(another.TryAcquire(), "the instance still holds the name");
    }

    [Fact]
    public async Task ALaunchIsAnsweredOnlyOnceTheInstanceHasShownItself()
    {
        string name = UniqueName();
        var showing = new TaskCompletionSource();
        using var instance = RunningInstance(name, () => showing.Task);

        using var launch = new SingleInstanceGuard(name);
        var handOff = launch.HandOffOrEvictAsync(Patient);

        await Task.Delay(300);
        Assert.False(handOff.IsCompleted, "the launch must not be told 'shown' before the window is");
        showing.SetResult();
        Assert.False(await handOff);
    }

    [Fact]
    public async Task EveryLaunchIsAnsweredOnItsOwnWhileAnotherIsStillWaiting()
    {
        string name = UniqueName();
        int reached = 0;
        var showing = new TaskCompletionSource();
        using var instance = RunningInstance(name, () => { Interlocked.Increment(ref reached); return showing.Task; });

        using var first = new SingleInstanceGuard(name);
        using var second = new SingleInstanceGuard(name);
        var firstHandOff = first.HandOffOrEvictAsync(Patient);
        var secondHandOff = second.HandOffOrEvictAsync(Patient);

        for (int i = 0; i < 100 && Volatile.Read(ref reached) < 2; i++) await Task.Delay(50);
        Assert.Equal(2, reached);
        showing.SetResult();
        Assert.False(await firstHandOff);
        Assert.False(await secondHandOff);
    }

    [Fact]
    public async Task ALaunchThatFindsTheInstanceGoneTakesItsPlace()
    {
        using var launch = new SingleInstanceGuard(UniqueName());
        Assert.True(await launch.HandOffOrEvictAsync(TimeSpan.FromMilliseconds(300)));
        using var another = new SingleInstanceGuard(UniqueName());
        Assert.True(another.TryAcquire());
    }

    [Fact]
    public async Task ANameHeldByAProcessThatAcceptsNoOneIsAnError()
    {
        string name = UniqueName();
        // Every instance of the pipe is already connected to someone else: nothing for a launch to ask.
        using var squatter = new NamedPipeServerStream(name, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
        using var occupant = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        await Task.WhenAll(squatter.WaitForConnectionAsync(), occupant.ConnectAsync());

        using var launch = new SingleInstanceGuard(name);
        await Assert.ThrowsAsync<InvalidOperationException>(() => launch.HandOffOrEvictAsync(TimeSpan.FromMilliseconds(300)));
    }

    [Fact]
    public async Task AnInstanceThatNeverAnswersIsKilledAndReplaced()
    {
        string name = UniqueName();
        // A real second process, since eviction kills one: it owns the pipe and never reads from it.
        using var hung = Process.Start(new ProcessStartInfo("powershell.exe",
            "-NoProfile -Command \"$ErrorActionPreference = 'Stop'; $p = New-Object System.IO.Pipes.NamedPipeServerStream('" + name +
            "','InOut',-1,'Byte','Asynchronous'); [Console]::Out.WriteLine('ready'); Start-Sleep 120\"")
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        })!;
        try
        {
            var ready = hung.StandardOutput.ReadLineAsync();
            Assert.Same(ready, await Task.WhenAny(ready, Task.Delay(Patient * 2)));
            Assert.Equal("ready", await ready);

            using var launch = new SingleInstanceGuard(name);
            Assert.False(launch.TryAcquire());
            Assert.True(await launch.HandOffOrEvictAsync(TimeSpan.FromSeconds(1)), "the launch takes the hung instance's place");

            Assert.True(hung.HasExited, "the hung instance is killed, not left beside the new one");
            using var another = new SingleInstanceGuard(name);
            Assert.False(another.TryAcquire(), "the replacement holds the name");
        }
        finally
        {
            if (!hung.HasExited) hung.Kill(entireProcessTree: true);
        }
    }
}
