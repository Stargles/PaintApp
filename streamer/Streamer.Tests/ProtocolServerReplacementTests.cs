using System.Net;
using System.Net.Sockets;
using Streamer.Core;
using Streamer.Core.Protocol;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// The ping-pong fix (STREAM.md §3/§6, 2026-09-25): <see cref="ProtocolServer"/> allows one client
/// only and, on a new connection, evicts whichever one it already had — until this fix, silently,
/// which is exactly what let two connections to the same laptop (or two genuinely different
/// devices) evict each other forever, each discovering the close only as an ordinary drop and
/// reconnecting to reclaim the slot. This pins the server's own half of the fix: the evicted
/// client's socket receives a STATUS naming the reason *before* it actually closes, and every HELLO
/// reply carries the server's own stable machine id.
///
/// Loopback sockets, a real `ProtocolServer` and real `TcpClient`s — the first live-socket test of
/// this class. `SkipAdmissionCheckForTests` is required: a loopback address is neither Tailscale
/// nor RFC1918, so the real `AdmissionPolicy` check (correctly) refuses it before HELLO, same shape
/// as the iPad coordinator's own `startsClients` test seam.
/// </summary>
public sealed class ProtocolServerReplacementTests : IDisposable
{
    private readonly string _root;
    private readonly FileInbox _fileInbox;
    private ProtocolServer? _server;

    public ProtocolServerReplacementTests()
    {
        _root = Path.Combine(Path.GetTempPath(), $"paintstreamer-replace-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_root);
        var settings = new Settings(Path.Combine(_root, "settings.json"));
        _fileInbox = new FileInbox(settings);
    }

    public void Dispose()
    {
        if (_server != null)
        {
            _server.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private async Task<ProtocolServer> StartServerAsync(string machineId = "MACHINE-TEST-1")
    {
        var server = new ProtocolServer(0, "PaintStreamer", "1.0.0-test", "test-host", machineId, _fileInbox)
        {
            SkipAdmissionCheckForTests = true,
        };
        await server.StartAsync();
        _server = server;
        return server;
    }

    /// <summary>Connects a loopback `TcpClient`, sends HELLO, and reads the server's HELLO reply —
    /// every real client's first exchange (STREAM.md §3).</summary>
    private static async Task<(TcpClient Tcp, FrameReader Reader, HelloMessage Reply)> ConnectAndHelloAsync(int port)
    {
        var tcp = new TcpClient();
        await tcp.ConnectAsync(IPAddress.Loopback, port);
        var stream = tcp.GetStream();
        var hello = new HelloMessage { Proto = 1, App = "PaintApp", Version = "1.0", Name = "test-ipad" };
        await stream.WriteAsync(Frame.Of(MessageType.Hello, Json.Encode(hello)).Encode());
        var reader = new FrameReader(stream);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var replyFrame = await reader.ReadFrameAsync(cts.Token);
        Assert.Equal((byte)MessageType.Hello, replyFrame.Type);
        var reply = Json.Decode<HelloMessage>(replyFrame.Payload);
        return (tcp, reader, reply);
    }

    [Fact]
    public async Task HelloReply_CarriesTheServersMachineId()
    {
        var server = await StartServerAsync("MACHINE-ABC-123");
        var (tcp, _, reply) = await ConnectAndHelloAsync(server.BoundPort);
        Assert.Equal("MACHINE-ABC-123", reply.MachineId);
        Assert.Equal("test-host", reply.Name);
        tcp.Dispose();
    }

    /// <summary>The reported bug's server-side half: a second connection replaces the first, and
    /// the first must be told why — over a frame it can actually read — before the socket closes,
    /// not merely logged where only a person watching the laptop would see it.</summary>
    [Fact]
    public async Task SecondConnectionReplacesFirst_FirstReceivesReasonBeforeSocketCloses()
    {
        var server = await StartServerAsync();
        int port = server.BoundPort;

        var (firstTcp, firstReader, _) = await ConnectAndHelloAsync(port);

        // The second connection evicts the first — exactly the shape a stream element and the
        // document's ambient connection take when they name the same laptop under two spellings.
        var (secondTcp, secondReader, _) = await ConnectAndHelloAsync(port);

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var frame = await firstReader.ReadFrameAsync(cts.Token);
        Assert.Equal((byte)MessageType.Status, frame.Type);
        var status = Json.Decode<StatusMessage>(frame.Payload);
        Assert.False(status.Streaming);
        Assert.Equal(ProtocolServer.ReplacedByAnotherConnectionReason, status.Reason);

        // And the socket really does close afterward — reading again reaches EOF, not more data
        // the evicted client might mistake for something to act on.
        using var eofCts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await Assert.ThrowsAsync<EndOfStreamException>(
            () => firstReader.ReadFrameAsync(eofCts.Token));

        firstTcp.Dispose();
        secondTcp.Dispose();
    }

    /// <summary>Three connections in a row: each of the first two is told it was replaced, in
    /// order, before the third is ever accepted — the fix does not merely work for one eviction.</summary>
    [Fact]
    public async Task EachReplacedConnectionInAChainReceivesItsOwnReason()
    {
        var server = await StartServerAsync();
        int port = server.BoundPort;

        var (firstTcp, firstReader, _) = await ConnectAndHelloAsync(port);
        var (secondTcp, secondReader, _) = await ConnectAndHelloAsync(port);
        var (thirdTcp, _, _) = await ConnectAndHelloAsync(port);

        using var cts1 = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var firstFrame = await firstReader.ReadFrameAsync(cts1.Token);
        var firstStatus = Json.Decode<StatusMessage>(firstFrame.Payload);
        Assert.Equal(ProtocolServer.ReplacedByAnotherConnectionReason, firstStatus.Reason);

        using var cts2 = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var secondFrame = await secondReader.ReadFrameAsync(cts2.Token);
        var secondStatus = Json.Decode<StatusMessage>(secondFrame.Payload);
        Assert.Equal(ProtocolServer.ReplacedByAnotherConnectionReason, secondStatus.Reason);

        firstTcp.Dispose();
        secondTcp.Dispose();
        thirdTcp.Dispose();
    }
}
