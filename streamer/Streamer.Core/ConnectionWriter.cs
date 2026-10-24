using System.Buffers.Binary;
using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>One connection's serialized wire owner. Bulk admission precedes encoding; metadata
/// coalesces in bounded slots. A caller may stop waiting, but an admitted wire frame belongs to
/// this writer until it finishes or this connection closes. No producer token truncates a frame.</summary>
internal sealed class ConnectionWriter
{
    private sealed class Bulk
    {
        public Frame? Frame;
        public VideoPayload? Video;
        public CancellationToken Producer;
        public readonly TaskCompletionSource<bool> Finished = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }

    private readonly Stream _stream;
    private readonly object _gate = new();
    private readonly SemaphoreSlim _credit = new(1, 1);
    private readonly SemaphoreSlim _wake = new(0, 1);
    private readonly CancellationTokenSource _closed = new();
    private readonly CancellationTokenSource _wire = new();
    private readonly Queue<Frame> _replies = new();
    private readonly Task _loop;
    private Bulk? _bulk;
    private Frame? _status;
    private Frame? _terminal;
    private bool _ping, _pong, _closing;
    private Task? _close;
    private int _waiting, _active;
    private const int MaximumReplies = 4;

    public ConnectionWriter(Stream stream) { _stream = stream; _loop = Task.Run(RunAsync); }
    public CancellationToken Closed => _closed.Token;
    public int WaitingBulkProducers => Volatile.Read(ref _waiting);
    public int RetainedBulkCount { get { lock (_gate) return (_bulk == null ? 0 : 1) + _active; } }
    public int PendingControlCount { get { lock (_gate) return _replies.Count + (_status == null ? 0 : 1) + (_ping ? 1 : 0) + (_pong ? 1 : 0); } }

    public Task<bool> SendAsync(Frame frame, CancellationToken ct) => SubmitAsync(new Bulk { Frame = frame, Producer = ct }, ct);
    public Task<bool> SendVideoAsync(bool keyframe, ulong pts, ReadOnlyMemory<byte> au, CancellationToken ct)
    {
        if (au.Length > Frame.MaximumPayloadLength - VideoPayload.HeaderLength)
            throw new InvalidDataException("VIDEO exceeds the wire payload limit.");
        return SubmitAsync(new Bulk { Video = new VideoPayload(keyframe, pts, au), Producer = ct }, ct);
    }

    private async Task<bool> SubmitAsync(Bulk bulk, CancellationToken producer)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(producer, Closed);
        Interlocked.Increment(ref _waiting);
        try { await _credit.WaitAsync(linked.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) { return false; }
        finally { Interlocked.Decrement(ref _waiting); }
        lock (_gate)
        {
            if (_closing) { _credit.Release(); return false; }
            _bulk = bulk;
        }
        Signal();
        try { return await bulk.Finished.Task.WaitAsync(linked.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) { return false; }
    }

    public void Status(StatusMessage status)
    {
        var frame = StatusFrame(status);
        lock (_gate) { if (_closing) return; _status = frame; }
        Signal();
    }

    public void Ping(bool pong)
    {
        lock (_gate) { if (_closing) return; if (pong) _pong = true; else _ping = true; }
        Signal();
    }

    public void Reply(Frame frame)
    {
        Frame.ValidatePayloadLength(frame.Type, (uint)frame.Payload.Length);
        bool overflow;
        lock (_gate)
        {
            if (_closing) return;
            overflow = _replies.Count == MaximumReplies;
            if (!overflow) _replies.Enqueue(frame);
        }
        if (overflow) BeginClose(); // A peer flooding replies cannot make an unbounded metadata queue.
        else Signal();
    }

    private void Signal() { try { _wake.Release(); } catch (SemaphoreFullException) { } }

    private static Frame StatusFrame(StatusMessage status)
    {
        var frame = Frame.Of(MessageType.Status, Json.Encode(status));
        Frame.ValidatePayloadLength(frame.Type, (uint)frame.Payload.Length);
        return frame;
    }

    public Task BeginClose(StatusMessage? terminal = null)
    {
        Frame? terminalFrame = terminal == null ? null : StatusFrame(terminal);
        Task close;
        lock (_gate)
        {
            if (_close == null)
            {
                _closing = true;
                _terminal = terminalFrame;
                _status = null; _ping = false; _pong = false;
                _close = Task.Run(CloseAsync);
            }
            close = _close;
        }
        // Retire immediately, outside the state lock, before another run can become current.
        _closed.Cancel();
        Signal();
        return close;
    }

    private async Task CloseAsync()
    {
        _closed.Cancel();
        Signal();
        if (await Task.WhenAny(_loop, Task.Delay(TimeSpan.FromSeconds(2))).ConfigureAwait(false) != _loop)
        {
            _wire.Cancel();
            _stream.Close(); // Release an actual blocked write before joining its owner.
        }
        await _loop.ConfigureAwait(false);
    }

    private async Task RunAsync()
    {
        Bulk? current = null;
        try
        {
            while (true)
            {
                Frame? control = null;
                bool ending;
                lock (_gate)
                {
                    ending = _closing;
                    if (_replies.Count != 0) control = _replies.Dequeue();
                    else if (_terminal != null) { control = _terminal; _terminal = null; }
                    else if (ending) break;
                    else if (_pong) { control = Frame.Of(MessageType.Pong); _pong = false; }
                    else if (_ping) { control = Frame.Of(MessageType.Ping); _ping = false; }
                    else if (_status != null) { control = _status; _status = null; }
                    else if (_bulk != null) { current = _bulk; _bulk = null; _active = 1; }
                }
                if (control is Frame frame) await WriteAsync(frame).ConfigureAwait(false);
                else if (current != null)
                {
                    // The only cancellation boundary is BEFORE the header. After it, wire owns it.
                    if (current.Producer.IsCancellationRequested) current.Finished.TrySetResult(false);
                    else
                    {
                        if (current.Video is VideoPayload video) await WriteVideoAsync(video).ConfigureAwait(false);
                        else await WriteAsync(current.Frame!.Value).ConfigureAwait(false);
                        current.Finished.TrySetResult(true);
                    }
                    lock (_gate) _active = 0;
                    current = null;
                    _credit.Release();
                }
                else await _wake.WaitAsync(_wire.Token).ConfigureAwait(false);
            }
        }
        catch (Exception)
        {
            // A failed/partial frame terminates this whole connection; it is never resumed later.
            _closed.Cancel();
            _stream.Close();
        }
        finally
        {
            current?.Finished.TrySetResult(false);
            Bulk? queued;
            lock (_gate) { queued = _bulk; _bulk = null; _active = 0; _closing = true; }
            queued?.Finished.TrySetResult(false);
            if (current != null || queued != null) _credit.Release();
            _closed.Cancel();
        }
    }

    private async Task WriteAsync(Frame frame)
    {
        Frame.ValidatePayloadLength(frame.Type, (uint)frame.Payload.Length);
        var header = new byte[5]; header[0] = frame.Type;
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(1), (uint)frame.Payload.Length);
        await _stream.WriteAsync(header, _wire.Token).ConfigureAwait(false);
        await _stream.WriteAsync(frame.Payload, _wire.Token).ConfigureAwait(false);
    }

    private async Task WriteVideoAsync(VideoPayload video)
    {
        var header = new byte[5 + VideoPayload.HeaderLength]; header[0] = (byte)MessageType.Video;
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(1), (uint)(VideoPayload.HeaderLength + video.AccessUnit.Length));
        header[5] = video.Keyframe ? (byte)1 : (byte)0;
        BinaryPrimitives.WriteUInt64BigEndian(header.AsSpan(6), video.PtsUs);
        await _stream.WriteAsync(header, _wire.Token).ConfigureAwait(false);
        await _stream.WriteAsync(video.AccessUnit, _wire.Token).ConfigureAwait(false);
    }
}
