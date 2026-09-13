using System.Buffers.Binary;
using System.Threading.Channels;
using Streamer.Core.Protocol;

namespace Streamer.Core;

public enum OutboundFileState
{
    /// <summary>Waiting its turn in the queue — either behind another transfer, or
    /// (see <see cref="OutboundFileEventArgs.Reason"/>) because no iPad is connected.</summary>
    Queued,
    Sending,
    /// <summary>FILE_RESULT ok:true — "inserted", per §3: "ok from the iPad means
    /// inserted, not received".</summary>
    Inserted,
    /// <summary>FILE_RESULT ok:false — the iPad's own reason is in
    /// <see cref="OutboundFileEventArgs.Reason"/>.</summary>
    Refused,
    /// <summary>Never got a FILE_RESULT at all — no connection, the connection dropped
    /// mid-transfer, or the 60s wait for a reply ran out.</summary>
    Failed,
}

public sealed class OutboundFileEventArgs : EventArgs
{
    public required string Path { get; init; }
    public required OutboundFileState State { get; init; }
    public string? Reason { get; init; }
    public long BytesSent { get; init; }
    public long TotalBytes { get; init; }
}

/// <summary>
/// Outgoing (laptop → iPad) FILE_* (STREAM.md §3, §4.4's drop box / Ctrl+V / the outbox
/// folder, §7 stage 4). One shared queue behind every source that can hand this a path —
/// the window's drop target, a pasted bitmap already saved as PNG, and
/// <see cref="OutboxFolderWatcher"/> — so "one file in flight, the queue drains in
/// order" is true across all three rather than per-source. A file is read and chunked
/// (≤ <see cref="ChunkSize"/> at a time) straight off disk, never held whole in memory.
/// References only <see cref="IFileTransport"/>, never WPF or a socket (STREAM.md §4.6).
/// </summary>
public sealed class FileOutbox : IDisposable
{
    public const int ChunkSize = 256 * 1024;
    private static readonly TimeSpan DefaultResultTimeout = TimeSpan.FromSeconds(60);

    private readonly IFileTransport _transport;
    private readonly Action<string> _log;
    private readonly TimeSpan _resultTimeout;
    private readonly Channel<string> _queue = Channel.CreateUnbounded<string>();
    private readonly object _gate = new();
    private readonly Dictionary<int, TaskCompletionSource<FileResultMessage>> _pending = new();
    private readonly SemaphoreSlim _clientSignal = new(0, 1);
    private int _nextId = 1;
    private readonly CancellationTokenSource _cts = new();
    private readonly Task _pump;

    public event EventHandler<OutboundFileEventArgs>? TransferUpdated;

    public FileOutbox(IFileTransport transport, Action<string>? log = null, TimeSpan? resultTimeout = null)
    {
        _transport = transport;
        _log = log ?? (_ => { });
        _resultTimeout = resultTimeout ?? DefaultResultTimeout;
        _transport.FileResultReceived += OnFileResultReceived;
        _transport.ClientConnected += OnClientConnected;
        _pump = Task.Run(() => PumpAsync(_cts.Token));
    }

    /// <summary>Queues a file for sending. Safe to call from any thread — the window's
    /// UI thread (drop, Ctrl+V) or <see cref="OutboxFolderWatcher"/>'s watcher thread.</summary>
    public void Enqueue(string path)
    {
        Raise(path, OutboundFileState.Queued, null, 0, SafeLength(path));
        _queue.Writer.TryWrite(path);
    }

    /// <summary>jpg/jpeg/png/heic/gif/webp/bmp → image; mp4/mov/m4v → video; else other
    /// (STREAM.md §7 stage 4 deliverable 1 — extends tools/stream's classify_kind, which
    /// only ever needed the narrower table it was testing outbound-from-the-check with,
    /// by webp/bmp).</summary>
    public static string ClassifyKind(string path)
    {
        string ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        return ext switch
        {
            "jpg" or "jpeg" or "png" or "heic" or "gif" or "webp" or "bmp" => "image",
            "mp4" or "mov" or "m4v" => "video",
            _ => "other",
        };
    }

    private void OnClientConnected()
    {
        try { _clientSignal.Release(); } catch (SemaphoreFullException) { /* already signalled */ }
    }

    private void OnFileResultReceived(FileResultMessage result)
    {
        TaskCompletionSource<FileResultMessage>? tcs;
        lock (_gate) { _pending.TryGetValue(result.Id, out tcs); }
        tcs?.TrySetResult(result);
    }

    private async Task PumpAsync(CancellationToken ct)
    {
        try
        {
            await foreach (var path in _queue.Reader.ReadAllAsync(ct).ConfigureAwait(false))
            {
                await SendOneAsync(path, ct).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
    }

    private async Task SendOneAsync(string path, CancellationToken ct)
    {
        while (!_transport.HasClient)
        {
            Raise(path, OutboundFileState.Queued, "Waiting for the iPad…", 0, SafeLength(path));
            await _clientSignal.WaitAsync(ct).ConfigureAwait(false);
        }

        long total;
        try
        {
            total = new FileInfo(path).Length;
        }
        catch (Exception e)
        {
            Raise(path, OutboundFileState.Failed, e.Message, 0, 0);
            return;
        }

        int id;
        lock (_gate) { id = _nextId++; }
        var tcs = new TaskCompletionSource<FileResultMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gate) { _pending[id] = tcs; }

        try
        {
            string kind = ClassifyKind(path);
            string name = Path.GetFileName(path);
            Raise(path, OutboundFileState.Sending, null, 0, total);

            if (!_transport.TrySend(Frame.Of(MessageType.FileBegin, Json.Encode(
                    new FileBeginMessage { Id = id, Name = name, Size = total, Kind = kind }))))
            {
                Raise(path, OutboundFileState.Failed, "The iPad disconnected before this could be sent", 0, total);
                return;
            }

            long sent = 0;
            using (var stream = File.OpenRead(path))
            {
                byte[] buffer = new byte[ChunkSize];
                int n;
                while ((n = await stream.ReadAsync(buffer, ct).ConfigureAwait(false)) > 0)
                {
                    var chunkPayload = new byte[4 + n];
                    BinaryPrimitives.WriteUInt32BigEndian(chunkPayload.AsSpan(0, 4), (uint)id);
                    Buffer.BlockCopy(buffer, 0, chunkPayload, 4, n);
                    if (!_transport.TrySend(Frame.Of(MessageType.FileChunk, chunkPayload)))
                    {
                        Raise(path, OutboundFileState.Failed, "The connection to the iPad was lost mid-transfer", sent, total);
                        return;
                    }
                    sent += n;
                    Raise(path, OutboundFileState.Sending, null, sent, total);
                }
            }

            if (!_transport.TrySend(Frame.Of(MessageType.FileEnd, Json.Encode(new FileEndMessage { Id = id }))))
            {
                Raise(path, OutboundFileState.Failed, "The connection to the iPad was lost mid-transfer", sent, total);
                return;
            }

            FileResultMessage result;
            try
            {
                result = await tcs.Task.WaitAsync(_resultTimeout, ct).ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                Raise(path, OutboundFileState.Failed, "Timed out waiting for the iPad to answer", total, total);
                return;
            }

            if (result.Ok)
            {
                Raise(path, OutboundFileState.Inserted, null, total, total);
            }
            else
            {
                Raise(path, OutboundFileState.Refused, result.Reason ?? "The iPad refused the file", total, total);
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception e)
        {
            Raise(path, OutboundFileState.Failed, e.Message, 0, total);
        }
        finally
        {
            lock (_gate) { _pending.Remove(id); }
        }
    }

    private static long SafeLength(string path)
    {
        try { return new FileInfo(path).Length; }
        catch { return 0; }
    }

    private void Raise(string path, OutboundFileState state, string? reason, long sent, long total)
    {
        _log($"FileOutbox: {path}: {state}{(reason != null ? $" ({reason})" : "")}");
        TransferUpdated?.Invoke(this, new OutboundFileEventArgs
        {
            Path = path, State = state, Reason = reason, BytesSent = sent, TotalBytes = total,
        });
    }

    public void Dispose()
    {
        _transport.FileResultReceived -= OnFileResultReceived;
        _transport.ClientConnected -= OnClientConnected;
        _cts.Cancel();
        try { _pump.Wait(TimeSpan.FromSeconds(2)); } catch { /* best effort on shutdown */ }
        _cts.Dispose();
        _clientSignal.Dispose();
    }
}
