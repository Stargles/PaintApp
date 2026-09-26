using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>
/// TcpListener 0.0.0.0:47301 (STREAM.md §3/§4.1). One client at a time — a new
/// connection replaces the old, exactly like tools/stream/fake-streamer.py's Python
/// reference server. Every accepted socket is checked against <see cref="AdmissionPolicy"/>
/// before anything else runs (TODO (98)); a refused one is closed with no HELLO exchanged.
/// Owns the HELLO handshake and proto check, PING/PONG watchdog,
/// VIDEO mux (a single serialized writer per connection so GstProcess's background
/// thread and STATUS/PONG replies never interleave mid-frame), and CONTROL dispatch —
/// exposed as an event so StreamerSession decides what pause/resume/keyframe mean.
/// Implements <see cref="IFrameSink"/>: the socket is the "real" sink STREAM.md §4.6
/// describes, with an in-process sink as the future second implementation.
/// </summary>
public sealed class ProtocolServer : IFrameSink, IFileTransport, IAsyncDisposable
{
    private static readonly TimeSpan PingSilence = TimeSpan.FromSeconds(2);
    private const int PingMissedLimit = 3;
    private static readonly TimeSpan HelloTimeout = TimeSpan.FromSeconds(10);

    /// <summary>The ping-pong fix (STREAM.md §3/§6): the exact reason string sent to a client this
    /// server is about to evict, over an ordinary STATUS, before its socket closes — matched
    /// verbatim by the iPad's `ScreenStreamClient.replacedByAnotherConnectionReason` so it stops
    /// trying to reclaim a slot the server has already given to someone else, instead of
    /// discovering the close as an ordinary drop and fighting to reclaim it (which is the reported
    /// bug: two connections to the one laptop evicting each other every second, forever). Kept as
    /// an explicit constant on both sides rather than inferred from any other STATUS text, since
    /// STATUS's `reason` is otherwise free text a person reads, not a wire contract a client
    /// branches on.</summary>
    public const string ReplacedByAnotherConnectionReason = "Replaced by another connection";

    private readonly int _port;
    private readonly string _appName;
    private readonly string _version;
    private readonly string _hostName;
    private readonly string _machineId;
    private readonly FileInbox _fileInbox;
    private readonly Action<string> _log;

    private TcpListener? _listener;
    private CancellationTokenSource? _acceptCts;
    private Task? _acceptLoop;
    private ClientConnection? _current;
    private readonly object _clientGate = new();

    public event Action<ControlMessage>? ControlReceived;
    public event Action? ClientConnected;
    public event Action? ClientDisconnected;
    public event Action<FileResultMessage>? FileResultReceived;

    public bool HasClient
    {
        get { lock (_clientGate) { return _current != null; } }
    }

    /// <summary>The port actually bound, once `StartAsync` has run — tests ask for port 0 (an
    /// OS-assigned ephemeral port) so parallel runs never collide on 47301.</summary>
    public int BoundPort => (_listener?.LocalEndpoint as IPEndPoint)?.Port ?? _port;

    /// <summary>Test seam, false in the app always: a loopback `TcpClient` in a test is neither
    /// Tailscale nor an RFC1918 address, so the real `AdmissionPolicy` check would refuse it before
    /// HELLO, same shape as the iPad coordinator's `startsClients`.</summary>
    public bool SkipAdmissionCheckForTests { get; set; }

    /// <summary>IFileTransport: enqueues a frame to the current client, or does nothing
    /// and reports failure when there is none. FileOutbox is the caller.</summary>
    public bool TrySend(Frame frame)
    {
        lock (_clientGate)
        {
            return _current?.TryEnqueue(frame.Encode()) ?? false;
        }
    }

    internal void RaiseFileResultReceived(FileResultMessage result) => FileResultReceived?.Invoke(result);

    public ProtocolServer(int port, string appName, string version, string hostName, string machineId,
        FileInbox fileInbox, Action<string>? log = null)
    {
        _port = port;
        _appName = appName;
        _version = version;
        _hostName = hostName;
        _machineId = machineId;
        _fileInbox = fileInbox;
        _log = log ?? (_ => { });
    }

    public Task StartAsync()
    {
        _listener = new TcpListener(IPAddress.Any, _port);
        _listener.Start();
        _acceptCts = new CancellationTokenSource();
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_acceptCts.Token));
        _log($"ProtocolServer: listening on 0.0.0.0:{_port}");
        return Task.CompletedTask;
    }

    public async Task StopAsync()
    {
        _acceptCts?.Cancel();
        _listener?.Stop();
        ClientConnection? current;
        lock (_clientGate) { current = _current; _current = null; }
        if (current != null) await current.DisposeAsync().ConfigureAwait(false);
        if (_acceptLoop != null)
        {
            try { await _acceptLoop.ConfigureAwait(false); } catch (OperationCanceledException) { }
        }
    }

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient tcp;
            try
            {
                tcp = await _listener!.AcceptTcpClientAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) { break; }

            var endpoint = tcp.Client.RemoteEndPoint;

            // TODO (98): the app-level half of AdmissionPolicy's rule — the firewall rule
            // installed by install-streamer.ps1 is now a coarse Tailscale-or-any-RFC1918
            // allow-list (it cannot know which subnet this NIC is actually on), so this is
            // where the precise "is it actually on one of MY subnets right now" check lives.
            // Refused before HELLO, so a non-admitted caller gets nothing but a closed socket.
            bool admitted = SkipAdmissionCheckForTests || (endpoint is IPEndPoint remote &&
                AdmissionPolicy.IsAdmitted(remote.Address, AdmissionPolicy.LocalIPv4Subnets()));
            if (!admitted)
            {
                _log($"ProtocolServer: refused connection from {endpoint} — not Tailscale or a local subnet");
                tcp.Close();
                continue;
            }

            _log($"ProtocolServer: connection from {endpoint}");

            ClientConnection? previous;
            var conn = new ClientConnection(tcp, this, _log);
            lock (_clientGate)
            {
                previous = _current;
                _current = conn;
            }
            if (previous != null)
            {
                _log($"ProtocolServer: new connection replaces previous client");
                // The ping-pong fix: tell the old client *why* before its socket closes, over an
                // ordinary STATUS its own writer queue already carries — so it can park itself
                // instead of discovering the close as an unexplained drop and reconnecting to
                // reclaim the slot, which used to evict whichever connection came next, forever.
                previous.EnqueueStatus(new StatusMessage
                {
                    Streaming = false,
                    Reason = ReplacedByAnotherConnectionReason,
                });
                _ = previous.DisposeAsync().AsTask();
            }

            _ = RunClientAsync(conn, endpoint);
        }
    }

    private async Task RunClientAsync(ClientConnection conn, EndPoint? endpoint)
    {
        try
        {
            bool ok = await conn.HandshakeAsync(_appName, _version, _hostName, HelloTimeout).ConfigureAwait(false);
            if (!ok)
            {
                await conn.DisposeAsync().ConfigureAwait(false);
                return;
            }
            ClientConnected?.Invoke();
            await conn.RunAsync(PingSilence, PingMissedLimit, _fileInbox, ControlReceived).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            _log($"ProtocolServer: client session for {endpoint} ended: {e.Message}");
        }
        finally
        {
            bool wasCurrent;
            lock (_clientGate)
            {
                wasCurrent = ReferenceEquals(_current, conn);
                if (wasCurrent) _current = null;
            }
            await conn.DisposeAsync().ConfigureAwait(false);
            if (wasCurrent)
            {
                ClientDisconnected?.Invoke();
                // A transfer mid-flight belongs to whichever connection was actually
                // current — a stale, already-replaced connection's own cleanup running
                // late must never abort a new connection's in-progress transfer, hence
                // gating this on wasCurrent exactly like ClientDisconnected above.
                _fileInbox.AbortActiveTransfer();
            }
            _log($"ProtocolServer: disconnect {endpoint}");
        }
    }

    public void OnStatus(StatusMessage status)
    {
        lock (_clientGate) { _current?.EnqueueStatus(status); }
    }

    public void OnVideoFrame(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit)
    {
        lock (_clientGate) { _current?.EnqueueVideo(keyframe, ptsUs, accessUnit); }
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);

    /// <summary>One connected peer: framing, a serialized write queue, and the read loop.</summary>
    private sealed class ClientConnection : IAsyncDisposable
    {
        private readonly TcpClient _tcp;
        private readonly ProtocolServer _owner;
        private readonly Action<string> _log;
        private readonly NetworkStream _stream;
        private readonly FrameReader _reader;
        private readonly Channel<byte[]> _writeQueue = Channel.CreateUnbounded<byte[]>();
        private readonly CancellationTokenSource _cts = new();
        private Task? _writerTask;
        private DateTime _lastRx = DateTime.UtcNow;

        public ClientConnection(TcpClient tcp, ProtocolServer owner, Action<string> log)
        {
            _tcp = tcp;
            _tcp.NoDelay = true;
            _owner = owner;
            _log = log;
            _stream = tcp.GetStream();
            _reader = new FrameReader(_stream);
        }

        public async Task<bool> HandshakeAsync(string appName, string version, string hostName, TimeSpan timeout)
        {
            using var timeoutCts = new CancellationTokenSource(timeout);
            Frame frame;
            try
            {
                frame = await _reader.ReadFrameAsync(timeoutCts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                _log("ProtocolServer: timed out waiting for HELLO");
                return false;
            }
            if (frame.Type != (byte)MessageType.Hello)
            {
                _log($"ProtocolServer: expected HELLO first, got type 0x{frame.Type:x2}; closing");
                return false;
            }
            var hello = Json.Decode<HelloMessage>(frame.Payload);
            _log($"ProtocolServer: HELLO from {hello.Name} ({hello.App} {hello.Version}, proto {hello.Proto})");
            if (hello.Proto != 1)
            {
                _log($"ProtocolServer: proto mismatch ({hello.Proto} != 1); closing");
                // STREAM.md §3: "a mismatch is reported in words on both screens" — the words are
                // this reply's version string, which the iPad shows verbatim on a proto mismatch.
                await WriteFrameAsync(Frame.Of(MessageType.Hello, Json.Encode(new HelloMessage
                {
                    Proto = 1, App = appName, Version = $"{version} (rejected proto {hello.Proto})", Name = hostName,
                    MachineId = _owner._machineId,
                }))).ConfigureAwait(false);
                return false;
            }
            await WriteFrameAsync(Frame.Of(MessageType.Hello, Json.Encode(new HelloMessage
            {
                Proto = 1, App = appName, Version = version, Name = hostName, MachineId = _owner._machineId,
            }))).ConfigureAwait(false);
            _writerTask = Task.Run(() => WriterLoopAsync());
            return true;
        }

        public async Task RunAsync(TimeSpan pingSilence, int pingMissedLimit, FileInbox fileInbox,
            Action<ControlMessage>? onControl)
        {
            var watchdog = Task.Run(() => WatchdogAsync(pingSilence, pingMissedLimit, _cts.Token));
            try
            {
                while (!_cts.IsCancellationRequested)
                {
                    Frame frame = await _reader.ReadFrameAsync(_cts.Token).ConfigureAwait(false);
                    _lastRx = DateTime.UtcNow;
                    Dispatch(frame, fileInbox, onControl);
                }
            }
            finally
            {
                _cts.Cancel();
                try { await watchdog.ConfigureAwait(false); } catch { /* cancelled */ }
            }
        }

        // FileInbox's BeginFile/WriteChunk/EndFile are all synchronous (fast local disk
        // I/O under a lock), so once BeginFile stopped being the stub's Task-returning
        // BeginFileAsync (stage 4), nothing here awaits anything any more — sync, not
        // async-with-no-await (which is what CS1998 was warning about).
        private void Dispatch(Frame frame, FileInbox fileInbox, Action<ControlMessage>? onControl)
        {
            if (!frame.TryGetKnownType(out var type))
            {
                _log($"ProtocolServer: unknown message type 0x{frame.Type:x2}, len={frame.Payload.Length}, skipped");
                return;
            }
            switch (type)
            {
                case MessageType.Ping:
                    EnqueueRaw(Frame.Of(MessageType.Pong).Encode());
                    break;
                case MessageType.Pong:
                    break; // _lastRx already updated by the caller
                case MessageType.Control:
                    onControl?.Invoke(Json.Decode<ControlMessage>(frame.Payload));
                    break;
                case MessageType.FileBegin:
                {
                    var begin = Json.Decode<FileBeginMessage>(frame.Payload);
                    // Accepted means no reply yet — §3: "the laptop answers after the
                    // file is closed in the save folder" — so only a refusal writes back
                    // here; the real answer comes from FileEnd below.
                    var refusal = fileInbox.BeginFile(begin);
                    if (refusal != null)
                        EnqueueRaw(Frame.Of(MessageType.FileResult, Json.Encode(refusal)).Encode());
                    break;
                }
                case MessageType.FileChunk:
                {
                    if (frame.Payload.Length < 4)
                    {
                        _log($"ProtocolServer: FILE_CHUNK payload too short ({frame.Payload.Length} bytes), skipped");
                        break;
                    }
                    uint id = BinaryPrimitives.ReadUInt32BigEndian(frame.Payload.Span[..4]);
                    fileInbox.WriteChunk((int)id, frame.Payload[4..]);
                    break;
                }
                case MessageType.FileEnd:
                {
                    var end = Json.Decode<FileEndMessage>(frame.Payload);
                    var result = fileInbox.EndFile(end);
                    if (result != null)
                        EnqueueRaw(Frame.Of(MessageType.FileResult, Json.Encode(result)).Encode());
                    break;
                }
                case MessageType.FileResult:
                    _owner.RaiseFileResultReceived(Json.Decode<FileResultMessage>(frame.Payload));
                    break;
                case MessageType.Hello:
                    _log("ProtocolServer: duplicate HELLO, ignored");
                    break;
                default:
                    break;
            }
        }

        private async Task WatchdogAsync(TimeSpan pingSilence, int pingMissedLimit, CancellationToken ct)
        {
            int missed = 0;
            DateTime? lastPingSent = null;
            try
            {
                while (!ct.IsCancellationRequested)
                {
                    await Task.Delay(TimeSpan.FromMilliseconds(500), ct).ConfigureAwait(false);
                    var silence = DateTime.UtcNow - _lastRx;
                    if (silence >= pingSilence)
                    {
                        if (lastPingSent == null || DateTime.UtcNow - lastPingSent.Value >= pingSilence)
                        {
                            EnqueueRaw(Frame.Of(MessageType.Ping).Encode());
                            lastPingSent = DateTime.UtcNow;
                            missed++;
                            if (missed >= pingMissedLimit)
                            {
                                _log($"ProtocolServer: {pingMissedLimit} missed PINGs, closing dead connection");
                                _cts.Cancel();
                                return;
                            }
                        }
                    }
                    else
                    {
                        missed = 0;
                    }
                }
            }
            catch (OperationCanceledException) { }
        }

        public void EnqueueStatus(StatusMessage status) =>
            EnqueueRaw(Frame.Of(MessageType.Status, Json.Encode(status)).Encode());

        public void EnqueueVideo(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit)
        {
            var payload = new VideoPayload(keyframe, ptsUs, accessUnit).Encode();
            EnqueueRaw(Frame.Of(MessageType.Video, payload).Encode());
        }

        private void EnqueueRaw(byte[] bytes) => _writeQueue.Writer.TryWrite(bytes);

        /// <summary>Public seam for ProtocolServer.TrySend (IFileTransport) — everything
        /// inside this class already reaches the same queue through EnqueueRaw.</summary>
        public bool TryEnqueue(byte[] bytes) => _writeQueue.Writer.TryWrite(bytes);

        // **Not keyed to `_cts` any more — the ping-pong fix needs this.** The old version passed
        // `_cts.Token` to `ReadAllAsync`/`WriteAsync`, so `DisposeAsync`'s `_cts.Cancel()` aborted
        // this loop immediately, dropping whatever was already queued but not yet on the wire —
        // in particular `AcceptLoopAsync`'s own "you have been replaced" STATUS, enqueued a moment
        // before disposal. This loop now ends only when the channel completes *and* drains
        // (`_writeQueue.Writer.TryComplete()`, called first in `DisposeAsync` below), so anything
        // enqueued before disposal begins is guaranteed to reach the wire.
        private async Task WriterLoopAsync()
        {
            try
            {
                await foreach (var bytes in _writeQueue.Reader.ReadAllAsync().ConfigureAwait(false))
                {
                    await _stream.WriteAsync(bytes).ConfigureAwait(false);
                }
            }
            catch (Exception e)
            {
                _log($"ProtocolServer: write failed, dropping connection: {e.Message}");
                _cts.Cancel();
            }
        }

        private async Task WriteFrameAsync(Frame frame)
        {
            await _stream.WriteAsync(frame.Encode()).ConfigureAwait(false);
        }

        public async ValueTask DisposeAsync()
        {
            _writeQueue.Writer.TryComplete();
            if (_writerTask != null)
            {
                // Bounded, not unconditional: a genuinely dead peer whose TCP send buffer never
                // drains must not hang a disposal forever. In the overwhelmingly common case (a
                // STATUS is a few dozen bytes) this resolves in microseconds; if it does not, the
                // socket close just below aborts the stuck write anyway.
                await Task.WhenAny(_writerTask, Task.Delay(TimeSpan.FromSeconds(2))).ConfigureAwait(false);
            }
            _cts.Cancel();
            try { _stream.Close(); } catch { }
            try { _tcp.Close(); } catch { }
        }
    }
}
