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
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        await using var watcher = new OutboxFolderWatcher(_root, outbox);

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
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        await using var watcher = new OutboxFolderWatcher(_root, outbox);

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
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromMilliseconds(200));
        await using var watcher = new OutboxFolderWatcher(_root, outbox);

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
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        await using var watcher = new OutboxFolderWatcher(_root, outbox);

        await WaitUntil(() => transport.Sent.Any(f => f.Type == (byte)MessageType.FileBegin));
        var begin = transport.DecodeBegin(transport.Sent.First(f => f.Type == (byte)MessageType.FileBegin));
        Assert.Equal("already-there.bin", begin.Name);
        transport.Reply(begin.Id, ok: true);
        await WaitUntil(() => File.Exists(Path.Combine(watcher.SentFolder, "already-there.bin")));
    }

    [Fact]
    public async Task ConstructorCreatesSentAndRefusedSubfolders()
    {
        var transport = new FakeFileTransport();
        await using var outbox = new FileOutbox(transport);
        await using var watcher = new OutboxFolderWatcher(_root, outbox);
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
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        await using var watcher = new OutboxFolderWatcher(_root, outbox);
        File.WriteAllBytes(Path.Combine(watcher.SentFolder, "old.png"), new byte[] { 1 });

        await Task.Delay(500);
        Assert.Empty(transport.Sent);
    }

    [Fact]
    public async Task ACopyHeldOpenPastTheOldCeilingSendsOnlyItsFinalBytesOnce()
    {
        Directory.CreateDirectory(_root);
        string path = Path.Combine(_root, "still-copying.bin");
        var transport = new FakeFileTransport { HasClient = true };
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        using var writer = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        writer.Write(new byte[] { 1, 2 });
        writer.Flush();
        var prematureQueue = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var watcher = new OutboxFolderWatcher(_root, outbox, message =>
        {
            if (message.Contains(": queuing ")) prematureQueue.TrySetResult();
        });
        // Observe the actual readiness decision, with slack beyond the old 100-poll boundary.
        Assert.NotSame(prematureQueue.Task,
            await Task.WhenAny(prematureQueue.Task, Task.Delay(TimeSpan.FromSeconds(20))));
        Assert.Empty(transport.Sent);
        byte[] final = { 1, 2, 3, 4, 5, 6 };
        writer.Write(final.AsSpan(2));
        writer.Flush();
        writer.Dispose();
        await WaitUntil(() => transport.Sent.Any(frame => frame.Type == (byte)MessageType.FileEnd));
        var begin = transport.DecodeBegin(Assert.Single(transport.Sent.Where(frame => frame.Type == (byte)MessageType.FileBegin)));
        Assert.Equal(final.Length, begin.Size);
        Assert.Equal(final, transport.Sent.Where(frame => frame.Type == (byte)MessageType.FileChunk)
            .SelectMany(frame => frame.Payload[4..].ToArray()).ToArray());
        transport.Reply(begin.Id, ok: true);
        await WaitUntil(() => File.Exists(Path.Combine(watcher.SentFolder, "still-copying.bin")));
        Assert.Equal(final, File.ReadAllBytes(Path.Combine(watcher.SentFolder, "still-copying.bin")));
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task DisposingWhileACopyIsLockedRetiresItsWaitBeforeTheWriterCloses()
    {
        Directory.CreateDirectory(_root);
        string path = Path.Combine(_root, "cancelled-copy.bin");
        var transport = new FakeFileTransport { HasClient = true };
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromMilliseconds(200));
        using var writer = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        writer.Write(new byte[] { 7, 8 });
        writer.Flush();
        var lateQueue = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var watcher = new OutboxFolderWatcher(_root, outbox, message =>
        {
            if (message.Contains(": queuing ")) lateQueue.TrySetResult();
        });
        try
        {
            Task dispose = watcher.DisposeAsync().AsTask();
            Assert.Same(dispose, await Task.WhenAny(dispose, Task.Delay(TimeSpan.FromSeconds(3))));
            await dispose;
            writer.Dispose();
            Assert.NotSame(lateQueue.Task, await Task.WhenAny(lateQueue.Task, Task.Delay(500)));
            Assert.Empty(transport.Sent);
            Assert.Equal(new byte[] { 7, 8 }, File.ReadAllBytes(path));
        }
        finally
        {
            writer.Dispose();
            await watcher.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10));
        }
    }

    [Fact]
    public async Task AStableReadableEmptyFileStillTransfersAndMovesToSent()
    {
        var beginReady = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var transport = new FakeFileTransport { HasClient = true };
        transport.BeforeSendAsync = (frame, _) =>
        {
            if (frame.Type == (byte)MessageType.FileBegin) beginReady.TrySetResult();
            return Task.CompletedTask;
        };
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromSeconds(3));
        await using var watcher = new OutboxFolderWatcher(_root, outbox);
        string path = Path.Combine(_root, "empty.txt");
        File.WriteAllBytes(path, Array.Empty<byte>());
        Assert.Same(beginReady.Task, await Task.WhenAny(beginReady.Task, Task.Delay(TimeSpan.FromSeconds(3))));
        await WaitUntil(() => transport.Sent.Any(frame => frame.Type == (byte)MessageType.FileEnd));
        var begin = transport.DecodeBegin(Assert.Single(transport.Sent.Where(frame => frame.Type == (byte)MessageType.FileBegin)));
        Assert.Equal(0, begin.Size);
        Assert.DoesNotContain(transport.Sent, frame => frame.Type == (byte)MessageType.FileChunk);
        transport.Reply(begin.Id, ok: true);
        await WaitUntil(() => File.Exists(Path.Combine(watcher.SentFolder, "empty.txt")));
        Assert.Equal(0, new FileInfo(Path.Combine(watcher.SentFolder, "empty.txt")).Length);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task DisposalJoinsAReadinessWorkItemAlreadyAtItsQueueBoundary()
    {
        Directory.CreateDirectory(_root);
        File.WriteAllBytes(Path.Combine(_root, "owned-wait.bin"), new byte[] { 3 });
        var transport = new FakeFileTransport { HasClient = true };
        await using var outbox = new FileOutbox(transport, resultTimeout: TimeSpan.FromMilliseconds(200));
        var atQueue = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var releaseQueue = new ManualResetEventSlim();
        var watcher = new OutboxFolderWatcher(_root, outbox, message =>
        {
            if (!message.Contains(": queuing ")) return;
            atQueue.TrySetResult();
            if (!releaseQueue.Wait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Owned readiness gate was not released");
        });
        Task[] ownedWaits = Array.Empty<Task>();
        try
        {
            await atQueue.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var gate = typeof(OutboxFolderWatcher).GetField("_gate", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.GetValue(watcher)!;
            lock (gate)
                ownedWaits = ((HashSet<Task>)typeof(OutboxFolderWatcher).GetField("_readiness", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.GetValue(watcher)!).ToArray();
            Task dispose = watcher.DisposeAsync().AsTask();
            Assert.NotSame(dispose, await Task.WhenAny(dispose, Task.Delay(200)));
            releaseQueue.Set();
            await dispose.WaitAsync(TimeSpan.FromSeconds(3));
        }
        finally
        {
            releaseQueue.Set();
            await watcher.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10));
            await Task.WhenAll(ownedWaits).WaitAsync(TimeSpan.FromSeconds(10));
        }
    }
}
