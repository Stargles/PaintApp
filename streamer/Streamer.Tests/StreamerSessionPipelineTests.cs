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
/// with the live pipeline's. These tests raise transitions the way ProtocolServer's events do
/// (fire-and-forget, back to back) and count the pipelines alive afterwards: it must be one.
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

        factory.Created[0].Emit(keyframe: true);
        factory.Created[0].Emit(keyframe: false);

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
}
