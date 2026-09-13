using Streamer.Core;
using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

/// <summary>STREAM.md §7 stage 4 deliverable 3 — the outbox folder watcher, the CLI's
/// remote hand since a second process cannot drive the running app's own drop box
/// directly. Real FileSystemWatcher + real disk, so these poll rather than assume an
/// exact latency.</summary>
public class OutboxFolderWatcherTests : IDisposable
{
    private readonly string _root =
        Path.Combine(Path.GetTempPath(), $"paintstreamer-outboxwatcher-test-{Guid.NewGuid():N}");

    public void Dispose() { try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ } }

    private static async Task WaitUntil(Func<bool> condition, TimeSpan? timeout = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(8));
        while (!condition())
        {
            if (DateTime.UtcNow > deadline) throw new TimeoutException("condition never became true");
            await Task.Delay(50);
        }
    }

    [Fact]
    public async Task DroppedFileIsQueuedAndMovedToSentOnSuccess()
    {
        var transport = new FakeFileTransport { HasClient = true };
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        using var watcher = new OutboxFolderWatcher(_root, outbox);

        string dropped = Path.Combine(_root, "photo.png");
        File.WriteAllBytes(dropped, new byte[] { 1, 2, 3, 4, 5 });

        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var begin = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        Assert.Equal("photo.png", begin.Name);
        Assert.Equal("image", begin.Kind);
        transport.Reply(begin.Id, ok: true);

        await WaitUntil(() => File.Exists(Path.Combine(watcher.SentFolder, "photo.png")));
        Assert.False(File.Exists(dropped));
    }

    [Fact]
    public async Task RefusedTransferIsMovedToRefused()
    {
        var transport = new FakeFileTransport { HasClient = true };
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        using var watcher = new OutboxFolderWatcher(_root, outbox);

        string dropped = Path.Combine(_root, "note.txt");
        File.WriteAllText(dropped, "hello");

        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var begin = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        Assert.Equal("other", begin.Kind);
        transport.Reply(begin.Id, ok: false, reason: "No document is open on the iPad");

        await WaitUntil(() => File.Exists(Path.Combine(watcher.RefusedFolder, "note.txt")));
        Assert.False(File.Exists(dropped));
    }

    [Fact]
    public async Task FailedTransferIsAlsoMovedToRefused()
    {
        // No FILE_RESULT is ever sent, so this times out to Failed rather than being
        // refused by the iPad — STREAM.md §7 stage 4 names only sent\/refused\, so
        // Failed is filed under refused\ too (see OutboxFolderWatcher's doc comment).
        var transport = new FakeFileTransport { HasClient = true };
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromMilliseconds(200));
        using var watcher = new OutboxFolderWatcher(_root, outbox);

        string dropped = Path.Combine(_root, "clip.mp4");
        File.WriteAllBytes(dropped, new byte[] { 9, 9 });

        await WaitUntil(() => File.Exists(Path.Combine(watcher.RefusedFolder, "clip.mp4")), TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task PreExistingFileAtStartupIsPickedUp()
    {
        Directory.CreateDirectory(_root);
        string dropped = Path.Combine(_root, "already-there.bin");
        File.WriteAllBytes(dropped, new byte[] { 1 });

        var transport = new FakeFileTransport { HasClient = true };
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        using var watcher = new OutboxFolderWatcher(_root, outbox);

        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var begin = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        Assert.Equal("already-there.bin", begin.Name);
        transport.Reply(begin.Id, ok: true);
        await WaitUntil(() => File.Exists(Path.Combine(watcher.SentFolder, "already-there.bin")));
    }

    [Fact]
    public void ConstructorCreatesSentAndRefusedSubfolders()
    {
        var transport = new FakeFileTransport();
        using var outbox = new FileOutbox(transport);
        using var watcher = new OutboxFolderWatcher(_root, outbox);
        Assert.True(Directory.Exists(watcher.SentFolder));
        Assert.True(Directory.Exists(watcher.RefusedFolder));
    }

    [Fact]
    public async Task FilesAlreadyInsideSentOrRefusedAreNeverRequeued()
    {
        // sent\ and refused\ are subdirectories of the watched root; IncludeSubdirectories
        // is off, but the startup scan only lists the root's own top-level files, so
        // nothing here should be watched twice.
        var transport = new FakeFileTransport { HasClient = true };
        using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        using var watcher = new OutboxFolderWatcher(_root, outbox);
        File.WriteAllBytes(Path.Combine(watcher.SentFolder, "old.png"), new byte[] { 1 });

        await Task.Delay(500);
        Assert.Empty(transport.Sent);
    }
}
