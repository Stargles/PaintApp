using Streamer.Core;
using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

/// <summary>Outgoing (laptop → iPad) FILE_* — STREAM.md §3/§7 stage 4 deliverable 1's
/// "outgoing" half, driven against <see cref="FakeFileTransport"/> so no socket or WPF
/// is involved.</summary>
public class FileOutboxTests : IDisposable
{
    private readonly string _tmpDir = Path.Combine(Path.GetTempPath(), $"paintstreamer-outbox-test-{Guid.NewGuid():N}");

    public FileOutboxTests() => Directory.CreateDirectory(_tmpDir);
    public void Dispose() { try { Directory.Delete(_tmpDir, recursive: true); } catch { } }

    private string WriteTempFile(string name, int size)
    {
        string path = Path.Combine(_tmpDir, name);
        var bytes = new byte[size];
        new Random(1).NextBytes(bytes);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    // events is appended to under `lock (events)` by the TransferUpdated handler on the
    // outbox's pump thread; every read from the test thread must snapshot under the same
    // lock rather than enumerate the live list, or a read racing an append throws
    // "Collection was modified; enumeration operation may not execute" (BUGS.md,
    // FileOutboxTests.NoClientQueuesWithAWaitingReasonThenSendsOnceOneConnects).
    private static List<OutboundFileEventArgs> Snapshot(List<OutboundFileEventArgs> events)
    {
        lock (events) return events.ToList();
    }

    private static async Task<OutboundFileEventArgs> WaitForState(
        List<OutboundFileEventArgs> events, OutboundFileState state, TimeSpan? timeout = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(5));
        while (DateTime.UtcNow < deadline)
        {
            var match = Snapshot(events).LastOrDefault(e => e.State == state);
            if (match != null) return match;
            await Task.Delay(10);
        }
        throw new TimeoutException($"never reached state {state}; saw: {string.Join(", ", Snapshot(events).Select(e => e.State))}");
    }

    [Theory]
    [InlineData("a.jpg", "image")]
    [InlineData("a.jpeg", "image")]
    [InlineData("a.png", "image")]
    [InlineData("a.HEIC", "image")]
    [InlineData("a.gif", "image")]
    [InlineData("a.webp", "image")]
    [InlineData("a.bmp", "image")]
    [InlineData("a.mp4", "video")]
    [InlineData("a.MOV", "video")]
    [InlineData("a.m4v", "video")]
    [InlineData("a.txt", "other")]
    [InlineData("a.pdf", "other")]
    [InlineData("noextension", "other")]
    public void ClassifiesKindFromExtension(string name, string expectedKind)
    {
        Assert.Equal(expectedKind, FileOutbox.ClassifyKind(name));
    }

    [Fact]
    public async Task ChunksA700KbFileInto256_256_188Kib()
    {
        const int oneKb = 1024;
        string path = WriteTempFile("big.bin", 700 * oneKb);
        var transport = new FakeFileTransport { HasClient = true };
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromMilliseconds(500));

        outbox.Enqueue(path);
        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileEnd));

        var chunkFrames = transport.Sent.Where(f => f.Type == (byte)MessageType.FileChunk).ToList();
        var chunkSizes = chunkFrames.Select(f => f.Payload.Length - 4).ToList(); // minus the 4-byte id prefix
        Assert.Equal(new[] { 256 * oneKb, 256 * oneKb, 188 * oneKb }, chunkSizes);
    }

    [Fact]
    public async Task OneFileInFlightAtATimeDrainsInOrder()
    {
        string a = WriteTempFile("a.bin", 10);
        string b = WriteTempFile("b.bin", 10);
        var transport = new FakeFileTransport { HasClient = true };
        var events = new List<OutboundFileEventArgs>();
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(5));
        outbox.TransferUpdated += (_, e) => { lock (events) events.Add(e); };

        outbox.Enqueue(a);
        outbox.Enqueue(b);

        // Wait until a's FILE_BEGIN has gone out.
        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var beginA = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        Assert.Equal("a.bin", beginA.Name);

        // b must not have started yet — only one BEGIN so far.
        await Task.Delay(100);
        Assert.Single(transport.Sent, f => f.Type == (byte)MessageType.FileBegin);

        transport.Reply(beginA.Id, ok: true);
        await WaitForState(events, OutboundFileState.Inserted);

        await WaitUntil(() => transport.Sent.Count(f => f.Type == (byte)MessageType.FileBegin) == 2);
        var beginB = transport.DecodeBegin(transport.Sent.Last(f => f.Type == (byte)MessageType.FileBegin));
        Assert.Equal("b.bin", beginB.Name);
        transport.Reply(beginB.Id, ok: true);
        await WaitForState(events, OutboundFileState.Inserted, TimeSpan.FromSeconds(3));
    }

    private static async Task WaitUntil(Func<bool> condition, TimeSpan? timeout = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(5));
        while (!condition())
        {
            if (DateTime.UtcNow > deadline) throw new TimeoutException("condition never became true");
            await Task.Delay(10);
        }
    }

    [Fact]
    public async Task ResultEventCarriesOkAndReason()
    {
        string path = WriteTempFile("x.bin", 5);
        var transport = new FakeFileTransport { HasClient = true };
        var events = new List<OutboundFileEventArgs>();
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(2));
        outbox.TransferUpdated += (_, e) => { lock (events) events.Add(e); };

        outbox.Enqueue(path);
        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var begin = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        transport.Reply(begin.Id, ok: false, reason: "No document is open on the iPad");

        var refused = await WaitForState(events, OutboundFileState.Refused);
        Assert.Equal("No document is open on the iPad", refused.Reason);
    }

    [Fact]
    public async Task NoClientQueuesWithAWaitingReasonThenSendsOnceOneConnects()
    {
        string path = WriteTempFile("y.bin", 5);
        var transport = new FakeFileTransport(); // HasClient starts false
        var events = new List<OutboundFileEventArgs>();
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        outbox.TransferUpdated += (_, e) => { lock (events) events.Add(e); };

        outbox.Enqueue(path);
        // Enqueue() itself raises an immediate Queued (Reason: null) synchronously,
        // before the pump task — on another thread — gets to the front of the queue and
        // discovers there is no client; wait for THAT specific follow-up event rather
        // than "any Queued", or this can observe the first one and return early.
        await WaitUntil(() => Snapshot(events).Any(e => e.State == OutboundFileState.Queued && e.Reason == "Waiting for the iPad…"));
        Assert.Empty(transport.Sent);

        transport.HasClient = true;
        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var begin = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        transport.Reply(begin.Id, ok: true);
        await WaitForState(events, OutboundFileState.Inserted);
    }

    [Fact]
    public async Task TimingOutWaitingForFileResultIsReportedAsFailed()
    {
        string path = WriteTempFile("z.bin", 5);
        var transport = new FakeFileTransport { HasClient = true };
        var events = new List<OutboundFileEventArgs>();
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromMilliseconds(150));
        outbox.TransferUpdated += (_, e) => { lock (events) events.Add(e); };

        outbox.Enqueue(path); // transport never replies
        var failed = await WaitForState(events, OutboundFileState.Failed, TimeSpan.FromSeconds(2));
        Assert.Contains("Timed out", failed.Reason);
    }

    [Fact]
    public async Task ConnectionLostMidSendIsReportedAsFailed()
    {
        string path = WriteTempFile("w.bin", 5);
        var transport = new FakeFileTransport { HasClient = true };
        var events = new List<OutboundFileEventArgs>();
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(2));
        outbox.TransferUpdated += (_, e) => { lock (events) events.Add(e); };

        transport.FailNextSend = true; // the FILE_BEGIN itself fails to send
        outbox.Enqueue(path);
        var failed = await WaitForState(events, OutboundFileState.Failed);
        Assert.False(string.IsNullOrEmpty(failed.Reason));
        Assert.Empty(transport.Sent);
    }
}
