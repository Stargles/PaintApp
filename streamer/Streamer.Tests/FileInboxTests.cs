using Streamer.Core;
using Streamer.Core.Protocol;
using Xunit;

namespace Streamer.Tests;

/// <summary>Real (stage 4) FileInbox behaviour — STREAM.md §3/§7 stage 4 deliverable 1's
/// "incoming" half. Each test gets its own temp save folder via a real Settings file
/// pointed at it, since FileInbox re-reads Settings.ResolveSaveFolder() on every BEGIN
/// (the live-folder-change requirement) rather than taking a bare path.</summary>
public class FileInboxTests : IDisposable
{
    private readonly string _root;
    private readonly Settings _settings;

    public FileInboxTests()
    {
        _root = Path.Combine(Path.GetTempPath(), $"paintstreamer-inbox-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_root);
        _settings = new Settings(Path.Combine(_root, "settings.json"));
        _settings.Save(new SettingsData { SaveFolder = Path.Combine(_root, "save") });
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private string SaveFolder => _settings.ResolveSaveFolder();

    private static void SendWhole(FileInbox inbox, int id, string name, byte[] content, int chunkSize = 64 * 1024)
    {
        var beginResult = inbox.BeginFile(new FileBeginMessage { Id = id, Name = name, Size = content.Length, Kind = "other" });
        Assert.Null(beginResult); // accepted: no reply until END, per §3
        for (int offset = 0; offset < content.Length; offset += chunkSize)
        {
            int n = Math.Min(chunkSize, content.Length - offset);
            inbox.WriteChunk(id, content.AsMemory(offset, n));
        }
    }

    [Fact]
    public void FullReceiveWritesTheExactBytes()
    {
        var inbox = new FileInbox(_settings);
        byte[] content = new byte[50_000];
        new Random(42).NextBytes(content);

        SendWhole(inbox, id: 1, "photo.png", content);
        var result = inbox.EndFile(new FileEndMessage { Id = 1 });

        Assert.NotNull(result);
        Assert.True(result!.Ok);
        Assert.Null(result.Reason);
        string path = Path.Combine(SaveFolder, "photo.png");
        Assert.True(File.Exists(path));
        Assert.Equal(content, File.ReadAllBytes(path));
    }

    [Fact]
    public void SecondBeginWhileOneIsActiveIsRefused()
    {
        var inbox = new FileInbox(_settings);
        var first = inbox.BeginFile(new FileBeginMessage { Id = 1, Name = "a.png", Size = 10, Kind = "image" });
        Assert.Null(first);

        var second = inbox.BeginFile(new FileBeginMessage { Id = 2, Name = "b.png", Size = 10, Kind = "image" });
        Assert.NotNull(second);
        Assert.Equal(2, second!.Id);
        Assert.False(second.Ok);
        Assert.Equal("A transfer is already in progress", second.Reason);

        // The first transfer is untouched by the refused second BEGIN.
        inbox.WriteChunk(1, new byte[10]);
        var firstEnd = inbox.EndFile(new FileEndMessage { Id = 1 });
        Assert.True(firstEnd!.Ok);
    }

    [Fact]
    public void SizeMismatchAtEndIsRefusedAndThePartialIsDeleted()
    {
        var inbox = new FileInbox(_settings);
        inbox.BeginFile(new FileBeginMessage { Id = 1, Name = "short.bin", Size = 100, Kind = "other" });
        inbox.WriteChunk(1, new byte[40]); // fewer bytes than declared

        var result = inbox.EndFile(new FileEndMessage { Id = 1 });

        Assert.NotNull(result);
        Assert.False(result!.Ok);
        Assert.Equal("The file arrived incomplete", result.Reason);
        Assert.False(File.Exists(Path.Combine(SaveFolder, "short.bin")));
    }

    [Fact]
    public void NameCollisionIsSuffixedRatherThanOverwritten()
    {
        Directory.CreateDirectory(SaveFolder);
        string existingPath = Path.Combine(SaveFolder, "dup.png");
        File.WriteAllBytes(existingPath, new byte[] { 1, 2, 3 });

        var inbox = new FileInbox(_settings);
        byte[] content = { 9, 9, 9, 9 };
        SendWhole(inbox, id: 1, "dup.png", content);
        var result = inbox.EndFile(new FileEndMessage { Id = 1 });

        Assert.True(result!.Ok);
        // The pre-existing file is untouched...
        Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(existingPath));
        // ...and the new one landed beside it, suffixed.
        string suffixedPath = Path.Combine(SaveFolder, "dup (2).png");
        Assert.True(File.Exists(suffixedPath));
        Assert.Equal(content, File.ReadAllBytes(suffixedPath));

        // A third arrival with the same name goes to " (3)".
        SendWhole(inbox, id: 2, "dup.png", content);
        var result2 = inbox.EndFile(new FileEndMessage { Id = 2 });
        Assert.True(result2!.Ok);
        Assert.True(File.Exists(Path.Combine(SaveFolder, "dup (3).png")));
    }

    [Fact]
    public void DisconnectMidTransferDeletesThePartialAndFreesTheSlot()
    {
        var inbox = new FileInbox(_settings);
        inbox.BeginFile(new FileBeginMessage { Id = 1, Name = "abandoned.bin", Size = 1000, Kind = "other" });
        inbox.WriteChunk(1, new byte[200]);

        inbox.AbortActiveTransfer();

        Assert.False(File.Exists(Path.Combine(SaveFolder, "abandoned.bin")));

        // The slot is free — a fresh transfer works right away, exactly as STREAM.md §7
        // stage 4 deliverable 5 requires ("the next transfer works").
        SendWhole(inbox, id: 2, "next.bin", new byte[] { 7, 7 });
        var result = inbox.EndFile(new FileEndMessage { Id = 2 });
        Assert.True(result!.Ok);
    }

    [Fact]
    public void AbortWithNoActiveTransferIsANoOp()
    {
        var inbox = new FileInbox(_settings);
        inbox.AbortActiveTransfer(); // must not throw
        SendWhole(inbox, id: 1, "fine.bin", new byte[] { 1 });
        Assert.True(inbox.EndFile(new FileEndMessage { Id = 1 })!.Ok);
    }

    [Fact]
    public void UnmatchedChunkAndEndAreIgnoredNotErrors()
    {
        var inbox = new FileInbox(_settings);
        inbox.WriteChunk(99, new byte[10]); // no BEGIN ever sent for id 99 — must not throw
        var result = inbox.EndFile(new FileEndMessage { Id = 99 });
        Assert.Null(result); // nothing to correlate a reply to
    }

    [Fact]
    public void OpenFailureIsReportedInThePlainExceptionMessage()
    {
        // A directory already occupies the destination name, so FileStream's CreateNew
        // throws something other than the "already exists" case CreateUniqueFile
        // specifically retries on (File.Exists is false for a directory) — this is the
        // same catch path a real write failure reports through, exercised here via a
        // failure that is reliable to reproduce without faking a full disk.
        Directory.CreateDirectory(SaveFolder);
        Directory.CreateDirectory(Path.Combine(SaveFolder, "blocked.bin"));

        var inbox = new FileInbox(_settings);
        var result = inbox.BeginFile(new FileBeginMessage { Id = 1, Name = "blocked.bin", Size = 5, Kind = "other" });

        Assert.NotNull(result);
        Assert.False(result!.Ok);
        Assert.False(string.IsNullOrWhiteSpace(result.Reason));
    }

    [Fact]
    public void ReceivingAFileRaisesFileReceivedWithTheSavedPath()
    {
        var inbox = new FileInbox(_settings);
        FileReceivedEventArgs? seen = null;
        inbox.FileReceived += (_, e) => seen = e;

        SendWhole(inbox, id: 1, "notify-me.png", new byte[] { 1, 2, 3, 4 });
        inbox.EndFile(new FileEndMessage { Id = 1 });

        Assert.NotNull(seen);
        Assert.Equal("notify-me.png", seen!.Name);
        Assert.Equal(4, seen.Size);
        Assert.Equal(Path.Combine(SaveFolder, "notify-me.png"), seen.Path);
    }

    [Fact]
    public void ChangingTheSaveFolderTakesEffectOnTheNextTransferWithNoRestart()
    {
        var inbox = new FileInbox(_settings);
        SendWhole(inbox, id: 1, "before.bin", new byte[] { 1 });
        inbox.EndFile(new FileEndMessage { Id = 1 });
        Assert.True(File.Exists(Path.Combine(_root, "save", "before.bin")));

        // Simulate the Tray window's "Change..." dialog writing a new folder mid-run.
        string newFolder = Path.Combine(_root, "save2");
        _settings.Save(new SettingsData { SaveFolder = newFolder });

        SendWhole(inbox, id: 2, "after.bin", new byte[] { 2 });
        inbox.EndFile(new FileEndMessage { Id = 2 });
        Assert.True(File.Exists(Path.Combine(newFolder, "after.bin")));
    }
}
