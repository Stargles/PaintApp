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
public sealed class OutboxFolderWatcher : IAsyncDisposable
{
    private readonly string _root;
    private readonly FileOutbox _outbox;
    private readonly Action<string> _log;
    private readonly FileSystemWatcher _watcher;
    private readonly object _gate = new();
    private readonly HashSet<string> _queued = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<Task> _readiness = new();
    private readonly CancellationTokenSource _lifetime = new();
    private Task? _disposeTask;

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
        _watcher.Created += (_, e) => QueueWhenReady(e.FullPath);
        _watcher.Renamed += (_, e) => QueueWhenReady(e.FullPath);
        _watcher.Error += (_, e) =>
        {
            lock (_gate)
                if (_disposeTask == null) _log($"OutboxFolderWatcher: watcher error: {e.GetException().Message}");
        };
        _watcher.EnableRaisingEvents = true;

        // Anything already sitting there from before this process started (e.g. the app
        // was not running when a Copy-Item landed a file).
        foreach (var existing in SafeTopLevelFiles(_root))
        {
            QueueWhenReady(existing);
        }
    }

    private IEnumerable<string> SafeTopLevelFiles(string root)
    {
        try { return Directory.EnumerateFiles(root).ToArray(); }
        catch (Exception e) { _log($"OutboxFolderWatcher: could not list {root}: {e.Message}"); return Array.Empty<string>(); }
    }

    private void QueueWhenReady(string path)
    {
        if (Directory.Exists(path)) return; // defensive; IncludeSubdirectories is off
        string name = Path.GetFileName(path);
        lock (_gate)
        {
            if (_disposeTask != null || !_queued.Add(name)) return;
            var task = Task.Run(() => TryQueueAsync(path, name, _lifetime.Token));
            _readiness.Add(task);
            _ = task.ContinueWith(completed =>
            {
                // TryQueueAsync reports failures. Observing here also retires a faulting log callback.
                _ = completed.Exception;
                lock (_gate) _readiness.Remove(completed);
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        }
    }

    private async Task TryQueueAsync(string path, string name, CancellationToken ct)
    {
        try
        {
            if (!await WaitUntilStableAsync(path, ct).ConfigureAwait(false))
            {
                lock (_gate) _queued.Remove(name);
                return;
            }
            ct.ThrowIfCancellationRequested();
            _log($"OutboxFolderWatcher: queuing {path}");
            _outbox.Enqueue(path);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            lock (_gate) _queued.Remove(name);
        }
        catch (Exception error)
        {
            lock (_gate) _queued.Remove(name);
            _log($"OutboxFolderWatcher: could not prepare {path}: {error.Message}");
        }
    }

    /// <summary>SSH's Copy-Item and a plain drag both write bytes into the destination
    /// path directly rather than renaming a temp file in, so "Created" can fire before
    /// the file is complete. Poll size-stable-and-openable instead of racing FileOutbox's
    /// own read against an in-progress writer.</summary>
    private async Task<bool> WaitUntilStableAsync(string path, CancellationToken ct)
    {
        long lastSize = -1;
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            if (!File.Exists(path)) return false;
            long size;
            try { size = new FileInfo(path).Length; }
            catch (IOException) { await Task.Delay(100, ct).ConfigureAwait(false); continue; }
            if (size == lastSize)
            {
                try
                {
                    using var probe = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                    return true;
                }
                catch (IOException) { /* still held open by the writer */ }
            }
            lastSize = size;
            await Task.Delay(100, ct).ConfigureAwait(false);
        }
    }

    private void OnTransferUpdated(object? sender, OutboundFileEventArgs e)
    {
        lock (_gate)
        {
            if (_disposeTask != null) return;
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

            if (!_queued.Remove(name)) return; // already handled, or not ours

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

    public ValueTask DisposeAsync()
    {
        lock (_gate) return new(_disposeTask ??= Task.Run(DisposeCoreAsync));
    }

    private async Task DisposeCoreAsync()
    {
        _watcher.Dispose();
        _outbox.TransferUpdated -= OnTransferUpdated;
        _lifetime.Cancel();
        Task[] pending;
        lock (_gate) pending = _readiness.ToArray();
        try { await Task.WhenAll(pending).ConfigureAwait(false); }
        finally
        {
            _lifetime.Dispose();
            lock (_gate) _queued.Clear();
        }
    }
}
