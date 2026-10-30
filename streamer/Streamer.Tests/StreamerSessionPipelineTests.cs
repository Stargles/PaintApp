using Streamer.Core;
using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// TODO (172): the owner's stream dropped to "starting" and showed smeared, datamoshed frames whenever
/// the laptop's screen moved. The cause was a second capture pipeline that nothing referenced and
/// nothing could stop — built when a connect and the iPad's `resume` (or a second connection
/// replacing the first) overlapped inside <c>StreamerSession</c> — whose access units interleaved
/// with the live pipeline's. These tests raise overlapping transitions back to back and join them and count the pipelines alive afterwards: it must be one.
/// </summary>
public class StreamerSessionPipelineTests
{
    private static CaptureSource Source() =>
        new() { Kind = SourceKind.Monitor, Id = "0", Name = "Test display", Width = 1920, Height = 1080 };

    private static ControlMessage Control(string cmd) => new() { Cmd = cmd };

    private static async Task<(StreamerSession session, FakePipelineFactory factory)> SessionOnASourceAsync()
    {
        var factory = new FakePipelineFactory();
        var session = new StreamerSession(@"C:\nonexistent", _ => { }, factory.CreateAsync);
        session.AddSink(new FakeFrameSink());
        await session.SetSourceAsync(Source());   // no client yet: records the source, starts nothing
        return (session, factory);
    }

    [Fact]
    public async Task AConnectAndTheResumeThatFollowsItBuildOnePipeline()
    {
        var (session, factory) = await SessionOnASourceAsync();

        var connect = session.OnClientConnectedAsync();
        var resume = session.HandleControlAsync(Control(ControlMessage.Resume));
        await Task.WhenAll(connect, resume);

        Assert.Single(factory.Created);
        Assert.Equal(1, factory.Live);
    }

    [Fact]
    public async Task ASecondConnectionReplacingTheFirstLeavesOnePipeline()
    {
        var (session, factory) = await SessionOnASourceAsync();

        var first = session.OnClientConnectedAsync();
        var second = session.OnClientConnectedAsync();
        await Task.WhenAll(first, second);

        Assert.Equal(1, factory.Live);
        Assert.Single(factory.Created);   // the first was still starting: its IDR serves the second client
    }

    [Fact]
    public async Task ANewClientGetsAKeyframeFromARunningPipelineByRestartingIt()
    {
        var (session, factory) = await SessionOnASourceAsync();
        await session.OnClientConnectedAsync();
        factory.Created[0].Connect();

        await session.OnClientConnectedAsync();

        Assert.Equal(2, factory.Created.Count);
        Assert.True(factory.Created[0].Stopped);
        Assert.Equal(1, factory.Live);
    }

    [Fact]
    public async Task AKeyframeRequestRestartsARunningPipelineButNotOneStillStarting()
    {
        var (session, factory) = await SessionOnASourceAsync();
        await session.OnClientConnectedAsync();

        await session.HandleControlAsync(Control(ControlMessage.Keyframe));
        Assert.Single(factory.Created);

        factory.Created[0].Connect();
        await session.HandleControlAsync(Control(ControlMessage.Keyframe));

        Assert.Equal(2, factory.Created.Count);
        Assert.True(factory.Created[0].Stopped);
        Assert.Equal(1, factory.Live);
    }

    [Fact]
    public async Task ResumeWhilePipelineExistsRestartsNothing()
    {
        var (session, factory) = await SessionOnASourceAsync();
        await session.OnClientConnectedAsync();
        factory.Created[0].Connect();

        await session.HandleControlAsync(Control(ControlMessage.Resume));

        Assert.Single(factory.Created);
        Assert.False(factory.Created[0].Stopped);
    }

    [Fact]
    public async Task APauseAndTheResumeRaisedRightAfterItRunInThatOrder()
    {
        var (session, factory) = await SessionOnASourceAsync();
        await session.OnClientConnectedAsync();
        factory.Created[0].Connect();

        var pause = session.HandleControlAsync(Control(ControlMessage.Pause));
        var resume = session.HandleControlAsync(Control(ControlMessage.Resume));
        await Task.WhenAll(pause, resume);

        Assert.Equal(1, factory.Live);   // paused, then resumed: not left paused
    }

    [Fact]
    public async Task AccessUnitsOfTheLivePipelineReachTheSinks()
    {
        var factory = new FakePipelineFactory();
        var sink = new FakeFrameSink();
        var session = new StreamerSession(@"C:\nonexistent", _ => { }, factory.CreateAsync);
        session.AddSink(sink);
        await session.SetSourceAsync(Source());
        await session.OnClientConnectedAsync();
        factory.Created[0].Connect();

        await factory.Created[0].EmitAsync(keyframe: true);
        await factory.Created[0].EmitAsync(keyframe: false);

        Assert.Equal(new[] { true, false }, sink.VideoFrames.Select(f => f.Keyframe));
    }

    [Fact]
    public async Task APipelineThatExitsUnexpectedlyIsReportedAsNotStreaming()
    {
        var factory = new FakePipelineFactory();
        var sink = new FakeFrameSink();
        var session = new StreamerSession(@"C:\nonexistent", _ => { }, factory.CreateAsync);
        session.AddSink(sink);
        await session.SetSourceAsync(Source());
        await session.OnClientConnectedAsync();
        factory.Created[0].Connect();
        Assert.True(sink.LastStatus!.Streaming);

        factory.Created[0].Fail("The capture pipeline exited unexpectedly");

        Assert.False(sink.LastStatus!.Streaming);
        Assert.Equal("The capture pipeline exited unexpectedly", sink.LastStatus.Reason);
    }

    [Fact]
    public async Task NoOrderOfOverlappingTransitionsLeavesMoreThanOnePipeline()
    {
        var (session, factory) = await SessionOnASourceAsync();
        var random = new Random(172);
        var raised = new List<Task>();
        for (int i = 0; i < 60; i++)
        {
            raised.Add(random.Next(6) switch
            {
                0 => session.OnClientConnectedAsync(),
                1 => session.OnClientDisconnectedAsync(),
                2 => session.HandleControlAsync(Control(ControlMessage.Pause)),
                3 => session.HandleControlAsync(Control(ControlMessage.Resume)),
                4 => session.HandleControlAsync(Control(ControlMessage.Keyframe)),
                _ => session.SetSourceAsync(Source()),
            });
            if (i % 7 == 0) await Task.Delay(random.Next(25));
            foreach (var pipeline in factory.Created) if (!pipeline.Stopped) pipeline.Connect();
        }
        await Task.WhenAll(raised);

        Assert.True(factory.Live <= 1, $"{factory.Live} pipelines alive after {factory.Created.Count} were built");
    }
    [Fact]
    public async Task RetiredConnectControlAndDisconnectCannotChangeTheCurrentRun()
    {
        var (session, factory) = await SessionOnASourceAsync();
        using var old = new CancellationTokenSource();
        old.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => session.OnClientConnectedAsync(old.Token));
        Assert.Empty(factory.Created);
        using var current = new CancellationTokenSource();
        await session.OnClientConnectedAsync(current.Token);
        factory.Created[0].Connect();
        await session.OnClientDisconnectedAsync(old.Token);
        await session.HandleControlAsync(Control(ControlMessage.Pause), old.Token);
        Assert.True(session.IsStreaming);
        Assert.False(factory.Created[0].Stopped);
        current.Cancel();
        await session.OnClientDisconnectedAsync(current.Token);
        Assert.True(factory.Created[0].Stopped);
        using var reopened = new CancellationTokenSource();
        await session.OnClientConnectedAsync(reopened.Token);
        await session.OnClientDisconnectedAsync(current.Token);
        Assert.Equal(1, factory.Live);
        await session.DisposeAsync();
    }

    [Fact]
    public void DisconnectOnAnotherThreadReleasesTheStartingThreadsKeepAwakeState()
    {
        // The API returns the calling thread's previous state; ES_CONTINUOUS alone clears it.
        // Keep this probe test-local so retiring the production thread API does not retire the witness.
        [System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint = "SetThreadExecutionState", SetLastError = true)]
        static extern uint ProbeExecutionState(uint flags);
        const uint continuous = 0x80000000, required = 0x00000001 | 0x00000002;
        var timeout = TimeSpan.FromSeconds(10);
        using var started = new ManualResetEventSlim();
        using var stopped = new ManualResetEventSlim();
        var pipeline = new FakePipeline();
        var session = new StreamerSession(@"C:\nonexistent", _ => { },
            (_, _) => Task.FromResult<ICapturePipeline>(pipeline));
        Exception? startError = null, stopError = null;
        uint initialClear = 0, afterDisconnect = 0, finalClear = 0;
        bool startInline = false, stopInline = false;
        var startingThread = new Thread(() =>
        {
            try
            {
                initialClear = ProbeExecutionState(continuous);
                session.SetSourceAsync(Source()).WaitAsync(timeout).GetAwaiter().GetResult();
                var connect = session.OnClientConnectedAsync();
                startInline = connect.IsCompleted;
                connect.WaitAsync(timeout).GetAwaiter().GetResult();
                started.Set();
                if (!stopped.Wait(timeout)) throw new TimeoutException("The disconnect did not finish");
                afterDisconnect = ProbeExecutionState(continuous);
            }
            catch (Exception error) { startError = error; }
            finally
            {
                try { finalClear = ProbeExecutionState(continuous); }
                catch (Exception error) { startError ??= error; }
                started.Set();
            }
        }) { IsBackground = true };
        var stoppingThread = new Thread(() =>
        {
            try
            {
                var disconnect = session.OnClientDisconnectedAsync();
                stopInline = disconnect.IsCompleted;
                disconnect.WaitAsync(timeout).GetAwaiter().GetResult();
            }
            catch (Exception error) { stopError = error; }
            finally { stopped.Set(); }
        }) { IsBackground = true };
        bool startReady = false, stopLaunched = false, startJoined = false, stopJoined = false;
        startingThread.Start();
        try
        {
            startReady = started.Wait(timeout);
            if (startReady && startError == null)
            {
                stoppingThread.Start();
                stopLaunched = true;
                stopJoined = stoppingThread.Join(timeout);
            }
        }
        finally
        {
            stopped.Set();
            startJoined = startingThread.Join(timeout);
            if (stopLaunched && !stopJoined) stopJoined = stoppingThread.Join(timeout);
            session.DisposeAsync().AsTask().WaitAsync(timeout).GetAwaiter().GetResult();
        }
        Assert.True(startReady && startJoined && stopJoined, "Both owned threads must finish");
        Assert.Null(startError);
        Assert.Null(stopError);
        Assert.True(startInline && stopInline, "Completed fake transitions must stay on their calling threads");
        Assert.True(pipeline.Stopped);
        Assert.NotEqual(0u, initialClear);
        Assert.NotEqual(0u, afterDisconnect);
        Assert.NotEqual(0u, finalClear);
        Assert.Equal(0u, afterDisconnect & required);
    }

}

public class StreamerSessionPowerOwnershipTests
{
    private sealed class GatedPipeline : ICapturePipeline
    {
        public readonly TaskCompletionSource StartedGate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource AllowStart = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource StoppingGate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource AllowStop = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Exception? StartError, StopError;
        public bool IsRunning => true;
        public int DisposeCount;
        public event Func<AccessUnitEventArgs, CancellationToken, Task>? AccessUnitReady { add { } remove { } }
        public event EventHandler<string>? UnexpectedExit { add { } remove { } }
        public event EventHandler? Started { add { } remove { } }
        public async Task StartAsync()
        {
            StartedGate.TrySetResult();
            await AllowStart.Task;
            if (StartError != null) throw StartError;
        }
        public async Task StopAsync()
        {
            StoppingGate.TrySetResult();
            await AllowStop.Task;
            if (StopError != null) throw StopError;
        }
        public async ValueTask DisposeAsync() { DisposeCount++; await StopAsync(); }
    }

    private static NativeMethods.SafePowerRequestHandle? Request(StreamerSession session) =>
        (NativeMethods.SafePowerRequestHandle?)typeof(StreamerSession)
            .GetField("_powerRequest", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!
            .GetValue(session);
    private static CaptureSource Source(string id) =>
        new() { Kind = SourceKind.Monitor, Id = id, Name = "Owned test source", Width = 64, Height = 64 };

    [Theory]
    [InlineData("disconnect")]
    [InlineData("pause")]
    [InlineData("source")]
    [InlineData("blocked")]
    [InlineData("dispose")]
    [InlineData("stop-failure")]
    public async Task TheRequestLivesThroughStartingAndStopThenClosesForEveryPipelineExit(string exit)
    {
        var pipeline = new GatedPipeline();
        var stopFailure = new InvalidOperationException("test-local stop failure");
        if (exit == "stop-failure") pipeline.StopError = stopFailure;
        int creates = 0;
        var session = new StreamerSession(@"C:\unused", createPipeline: (_, _) =>
            Task.FromResult<ICapturePipeline>(creates++ == 0 ? pipeline : new FakePipeline()));
        Task? connect = null, stop = null;
        NativeMethods.SafePowerRequestHandle? request = null;
        try
        {
            await session.SetSourceAsync(Source("first"));
            connect = session.OnClientConnectedAsync();
            await pipeline.StartedGate.Task.WaitAsync(TimeSpan.FromSeconds(10));
            request = Request(session);
            Assert.True(request is { IsClosed: false, IsInvalid: false });
            pipeline.AllowStart.TrySetResult();
            await connect.WaitAsync(TimeSpan.FromSeconds(10));
            stop = exit switch
            {
                "pause" => session.HandleControlAsync(new ControlMessage { Cmd = ControlMessage.Pause }),
                "source" => session.SetSourceAsync(Source("second")),
                "blocked" => session.SetEnvironmentBlockedAsync(true, "test-local locked state"),
                "dispose" => session.DisposeAsync().AsTask(),
                _ => session.OnClientDisconnectedAsync(),
            };
            await pipeline.StoppingGate.Task.WaitAsync(TimeSpan.FromSeconds(10));
            Assert.False(request!.IsClosed);
            pipeline.AllowStop.TrySetResult();
            var error = await Record.ExceptionAsync(() => stop.WaitAsync(TimeSpan.FromSeconds(10)));
            Assert.Same(exit == "stop-failure" ? stopFailure : null, error);
            Assert.True(request.IsClosed);
            Assert.Equal(1, pipeline.DisposeCount);
        }
        finally
        {
            pipeline.AllowStart.TrySetResult(); pipeline.AllowStop.TrySetResult();
            if (connect != null) { try { await connect; } catch { } }
            if (stop != null) { try { await stop; } catch { } }
            try { await session.DisposeAsync(); }
            catch (Exception error) when (ReferenceEquals(error, stopFailure)) { }
            request?.Dispose();
        }
    }

    [Fact]
    public async Task AFailedStartDisposesThePipelineAndItsAcquiredRequest()
    {
        var failure = new InvalidOperationException("test-local start failure");
        var pipeline = new GatedPipeline { StartError = failure };
        var session = new StreamerSession(@"C:\unused", createPipeline: (_, _) => Task.FromResult<ICapturePipeline>(pipeline));
        Task? connect = null;
        NativeMethods.SafePowerRequestHandle? request = null;
        try
        {
            await session.SetSourceAsync(Source("first"));
            connect = session.OnClientConnectedAsync();
            await pipeline.StartedGate.Task.WaitAsync(TimeSpan.FromSeconds(10));
            request = Request(session);
            pipeline.AllowStop.TrySetResult(); pipeline.AllowStart.TrySetResult();
            var error = await Record.ExceptionAsync(() => connect.WaitAsync(TimeSpan.FromSeconds(10)));
            Assert.Same(failure, error);
            Assert.True(request is { IsClosed: true });
            Assert.Null(Request(session));
            Assert.Equal(1, pipeline.DisposeCount);
        }
        finally
        {
            pipeline.AllowStart.TrySetResult(); pipeline.AllowStop.TrySetResult();
            if (connect != null) { try { await connect; } catch { } }
            await session.DisposeAsync();
            request?.Dispose();
        }
    }
}
