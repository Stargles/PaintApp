using Streamer.Core;
using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// STREAM.md §3: a pause belongs to the connection that asked for it. TODO (112) — the owner's
/// stream sat on "Paused" until they touched something: the iPad pauses the laptop when it goes to the
/// background, the socket then dies with the iPad asleep (or a new connection replaces it, which
/// ProtocolServer never reports as a disconnect), and the pause outlived it — the next connection
/// opened onto a laptop that sent nothing, and the iPad, which keeps no pause across a reconnect,
/// never said resume.
///
/// Observed through the one thing a test can see without a capturable desktop: whether a new
/// connection tries to start the pipeline. No encoder is probed here, so an attempt to start one
/// throws — which is the proof it was attempted (StartPipelineLockedAsync's first line). A session
/// that still held the old pause never reaches that line.
/// </summary>
public class StreamerSessionPauseTests
{
    private static CaptureSource Source() =>
        new() { Kind = SourceKind.Monitor, Id = "0", Name = "Test display", Width = 1920, Height = 1080 };

    [Fact]
    public async Task ANewConnectionDoesNotInheritThePreviousClientsPause()
    {
        var session = new StreamerSession(@"C:\nonexistent", _ => { });
        session.AddSink(new FakeFrameSink());
        await session.SetSourceAsync(Source());   // no client yet: records the source, starts nothing
        await session.HandleControlAsync(new ControlMessage { Cmd = ControlMessage.Pause });

        // The previous client is gone without anything having lifted its pause (a replaced
        // connection is never reported as a disconnect). The next one connects:
        await Assert.ThrowsAsync<InvalidOperationException>(() => session.OnClientConnectedAsync());
    }
}
