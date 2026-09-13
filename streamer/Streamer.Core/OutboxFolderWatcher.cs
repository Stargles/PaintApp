namespace Streamer.Core;

/// <summary>
/// Watches %LOCALAPPDATA%\PaintStreamer\outbox\ (STREAM.md §7 stage 4 deliverable 3 —
/// a CLI switch on the exe cannot reach a second, already-running process, so this
/// folder is the remote hand instead: `Copy-Item` over SSH drops a file in and it is
/// queued exactly as a window drop would be). Anything dropped at the TOP LEVEL of the
/// folder is handed to the shared <see cref="FileOutbox"/> once its size has stopped
/// changing (a copy-in-progress is not yet a file), then moved to <c>outbox\sent\</c> on
/// FILE_RESULT ok:true or <c>outbox\refused\</c> otherwise — a refusal from the iPad and
/// a Failed transfer (no connection, a dropped connection, a 60s timeout) are not the
/// same thing, but STREAM.md §7 names only these two destinations, so Failed lands in
/// refused\ too; see STREAM.md's note on this default.
/// </summary>
public sealed class OutboxFolderWatcher : IDisposable
{
    private readonly string _root;
    private readonly FileOutbox _outbox;
    private readonly Action<string> _log;
    private readonly FileSystemWatcher _watcher;
    private readonly object _gate = new();
    private readonly HashSet<string> _queued = new(StringComparer.OrdinalIgnoreCase);

    public string SentFolder { get; }
    public string RefusedFolder { get; }

    public OutboxFolderWatcher(string root, FileOutbox outbox, Action<string>? log = null)
    {
        _root = Path.GetFullPath(root);
        _outbox = outbox;
        _log = log ?? (_ => { });
        SentFolder = Path.Combine(_root, "sent");
        RefusedFolder = Path.Combine(_root, "refused");
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(SentFolder);
        Directory.CreateDirectory(RefusedFolder);

        _outbox.TransferUpdated += OnTransferUpdated;

        _watcher = new FileSystemWatcher(_root)
        {
            IncludeSubdirectories = false,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
        };
        _watcher.Created += (_, e) => _ = TryQueueAsync(e.FullPath);
        _watcher.Renamed += (_, e) => _ = TryQueueAsync(e.FullPath);
        _watcher.Error += (_, e) => _log($"OutboxFolderWatcher: watcher error: {e.GetException().Message}");
        _watcher.EnableRaisingEvents = true;

        // Anything already sitting there from before this process started (e.g. the app
        // was not running when a Copy-Item landed a file).
        foreach (var existing in SafeTopLevelFiles(_root))
        {
            _ = TryQueueAsync(existing);
        }
    }

    private IEnumerable<string> SafeTopLevelFiles(string root)
    {
        try { return Directory.EnumerateFiles(root).ToArray(); }
        catch (Exception e) { _log($"OutboxFolderWatcher: could not list {root}: {e.Message}"); return Array.Empty<string>(); }
    }

    private async Task TryQueueAsync(string path)
    {
        if (Directory.Exists(path)) return; // defensive; IncludeSubdirectories is off
        string name = Path.GetFileName(path);
        lock (_gate)
        {
            if (!_queued.Add(name)) return; // already in flight through this watcher
        }
        if (!await WaitUntilStableAsync(path).ConfigureAwait(false))
        {
            lock (_gate) { _queued.Remove(name); }
            return; // vanished before it settled, or never became readable
        }
        _log($"OutboxFolderWatcher: queuing {path}");
        _outbox.Enqueue(path);
    }

    /// <summary>SSH's Copy-Item and a plain drag both write bytes into the destination
    /// path directly rather than renaming a temp file in, so "Created" can fire before
    /// the file is complete. Poll size-stable-and-openable instead of racing FileOutbox's
    /// own read against an in-progress writer.</summary>
    private async Task<bool> WaitUntilStableAsync(string path)
    {
        long lastSize = -1;
        for (int i = 0; i < 100; i++) // ~10s ceiling
        {
            if (!File.Exists(path)) return false;
            long size;
            try { size = new FileInfo(path).Length; }
            catch (IOException) { await Task.Delay(100).ConfigureAwait(false); continue; }
            if (size == lastSize && size > 0)
            {
                try
                {
                    using var probe = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                    return true;
                }
                catch (IOException) { /* still held open by the writer */ }
            }
            lastSize = size;
            await Task.Delay(100).ConfigureAwait(false);
        }
        return File.Exists(path); // give up waiting for stability but still try
    }

    private void OnTransferUpdated(object? sender, OutboundFileEventArgs e)
    {
        if (!IsDirectlyInWatchedRoot(e.Path)) return; // not one of ours (drop box / Ctrl+V path)

        string name = Path.GetFileName(e.Path);
        string destFolder;
        switch (e.State)
        {
            case OutboundFileState.Inserted: destFolder = SentFolder; break;
            case OutboundFileState.Refused: destFolder = RefusedFolder; break;
            case OutboundFileState.Failed: destFolder = RefusedFolder; break;
            default: return; // Queued / Sending — not terminal yet
        }

        lock (_gate) { if (!_queued.Remove(name)) return; } // already handled, or not ours

        try
        {
            string dest = UniqueDestination(destFolder, name);
            if (File.Exists(e.Path)) File.Move(e.Path, dest);
            _log($"OutboxFolderWatcher: {name} -> {dest} ({e.State})");
        }
        catch (Exception ex)
        {
            _log($"OutboxFolderWatcher: could not move {e.Path} to {destFolder}: {ex.Message}");
        }
    }

    private bool IsDirectlyInWatchedRoot(string path)
    {
        try
        {
            string dir = Path.GetFullPath(Path.GetDirectoryName(Path.GetFullPath(path)) ?? "");
            return string.Equals(dir.TrimEnd(Path.DirectorySeparatorChar),
                                  _root.TrimEnd(Path.DirectorySeparatorChar),
                                  StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    private static string UniqueDestination(string folder, string name)
    {
        string path = Path.Combine(folder, name);
        if (!File.Exists(path)) return path;
        string stem = Path.GetFileNameWithoutExtension(name);
        string ext = Path.GetExtension(name);
        for (int n = 2; ; n++)
        {
            string candidate = Path.Combine(folder, $"{stem} ({n}){ext}");
            if (!File.Exists(candidate)) return candidate;
        }
    }

    public void Dispose()
    {
        _watcher.Dispose();
        _outbox.TransferUpdated -= OnTransferUpdated;
    }
}
