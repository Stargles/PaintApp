using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>One current connection, with HELLO-ready ownership, bounded serialized writes and
/// joined session/callback tasks. A replacement retires the previous run before it can publish.</summary>
public sealed class ProtocolServer : IFrameSink, IFileTransport, IAsyncDisposable
{
    private static readonly TimeSpan HelloTimeout = TimeSpan.FromSeconds(10);
    public const string ReplacedByAnotherConnectionReason = "Replaced by another connection";
    private readonly int _port;
    private readonly string _appName, _version, _hostName, _machineId;
    private readonly FileInbox _fileInbox;
    private readonly Action<string> _log;
    private readonly Func<Stream, Stream> _stream;
    private readonly object _clientGate = new();
    private readonly Dictionary<ClientConnection, Task> _sessions = new();
    private TcpListener? _listener;
    private CancellationTokenSource? _acceptCts;
    private Task? _acceptLoop;
    private Task? _stopTask;
    private ClientConnection? _current;
    private Action? _fileClientConnected;

    public event Func<ControlMessage, CancellationToken, Task>? ControlReceived;
    public event Func<CancellationToken, Task>? ClientConnected;
    public event Func<CancellationToken, Task>? ClientDisconnected;
    event Action? IFileTransport.ClientConnected { add { _fileClientConnected += value; } remove { _fileClientConnected -= value; } }
    public bool HasClient { get { lock (_clientGate) return _current is { IsReady: true }; } }
    public IFileConnection? CaptureConnection() { lock (_clientGate) return _current is { IsReady: true } ? _current : null; }
    public int BoundPort => (_listener?.LocalEndpoint as IPEndPoint)?.Port ?? _port;
    public bool SkipAdmissionCheckForTests { get; set; }
    internal int OwnedSessionCount { get { lock (_clientGate) return _sessions.Count; } }

    public ProtocolServer(int port, string appName, string version, string hostName, string machineId,
        FileInbox fileInbox, Action<string>? log = null, Func<Stream, Stream>? connectionStream = null)
    {
        _port = port; _appName = appName; _version = version; _hostName = hostName; _machineId = machineId;
        _fileInbox = fileInbox; _log = log ?? (_ => { }); _stream = connectionStream ?? (stream => stream);
    }

    public async Task StartAsync()
    {
        Task? stopping;
        lock (_clientGate) stopping = _stopTask;
        if (stopping != null) await stopping.ConfigureAwait(false);
        if (_acceptLoop is { IsCompleted: false }) return;
        _listener = new TcpListener(IPAddress.Any, _port); _listener.Start();
        _acceptCts = new CancellationTokenSource();
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_acceptCts.Token));
        _stopTask = null;
        _log($"ProtocolServer: listening on 0.0.0.0:{BoundPort}");
    }

    public Task StopAsync()
    {
        lock (_clientGate) return _stopTask ??= Task.Run(StopCoreAsync);
    }

    private async Task StopCoreAsync()
    {
        _acceptCts?.Cancel(); _listener?.Stop();
        ClientConnection[] connections;
        lock (_clientGate) { _current = null; connections = _sessions.Keys.ToArray(); }
        foreach (var connection in connections) connection.Retire();
        if (_acceptLoop != null) await _acceptLoop.ConfigureAwait(false);
        Task[] tasks;
        lock (_clientGate) tasks = _sessions.Values.ToArray();
        await Task.WhenAll(tasks).ConfigureAwait(false);
        lock (_clientGate) _sessions.Clear();
        _acceptCts?.Dispose(); _acceptCts = null; _acceptLoop = null;
    }

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient tcp;
            try { tcp = await _listener!.AcceptTcpClientAsync(ct).ConfigureAwait(false); }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) { break; }
            catch (SocketException) when (ct.IsCancellationRequested) { break; }
            var endpoint = tcp.Client.RemoteEndPoint;
            if (!(SkipAdmissionCheckForTests || endpoint is IPEndPoint remote &&
                  AdmissionPolicy.IsAdmitted(remote.Address, AdmissionPolicy.LocalIPv4Subnets())))
            { tcp.Close(); continue; }
            var next = new ClientConnection(tcp, this, _stream(tcp.GetStream()));
            ClientConnection? previous;
            Task? previousTask;
            lock (_clientGate)
            {
                foreach (var done in _sessions.Where(pair => pair.Value.IsCompleted).Select(pair => pair.Key).ToArray())
                    _sessions.Remove(done);
                previous = _current;
                previousTask = previous == null ? null : _sessions.GetValueOrDefault(previous);
            }
            previous?.Retire(new StatusMessage { Streaming = false, Reason = ReplacedByAnotherConnectionReason });
            bool rejected;
            lock (_clientGate)
            {
                rejected = ct.IsCancellationRequested;
                if (!rejected)
                {
                    _current = next;
                    _sessions[next] = Task.Run(() => RunClientAsync(next, endpoint));
                }
            }
            if (rejected) { await next.DisposeAsync().ConfigureAwait(false); break; }
            // A pending newest HELLO can proceed while the single old run drains. Do not accept
            // an unbounded population of retiring connections/tasks/payloads behind stalled peers.
            if (previousTask != null) await previousTask.ConfigureAwait(false);
        }
    }

    private async Task RunClientAsync(ClientConnection connection, EndPoint? endpoint)
    {
        try
        {
            if (!await connection.HandshakeAsync().ConfigureAwait(false)) return;
            lock (_clientGate)
            {
                if (!ReferenceEquals(_current, connection) || connection.Closed.IsCancellationRequested) return;
                connection.Ready = true;
            }
            _fileClientConnected?.Invoke();
            if (ClientConnected is { } connected)
                foreach (Func<CancellationToken, Task> callback in connected.GetInvocationList())
                    await callback(connection.Closed).ConfigureAwait(false);
            if (!connection.Closed.IsCancellationRequested) await connection.RunAsync().ConfigureAwait(false);
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { _log($"ProtocolServer: session {endpoint}: {error.Message}"); }
        finally
        {
            connection.Retire();
            if (connection.Ready && ClientDisconnected is { } disconnected)
                foreach (Func<CancellationToken, Task> callback in disconnected.GetInvocationList())
                    try { await callback(connection.Closed).ConfigureAwait(false); }
                    catch (Exception error) { _log($"ProtocolServer: disconnect callback: {error.Message}"); }
            await connection.DisposeAsync().ConfigureAwait(false);
            lock (_clientGate) { if (ReferenceEquals(_current, connection)) _current = null; }
        }
    }

    private async Task DispatchControlAsync(ControlMessage control, CancellationToken run)
    {
        if (ControlReceived is { } controls)
            foreach (Func<ControlMessage, CancellationToken, Task> callback in controls.GetInvocationList())
                await callback(control, run).ConfigureAwait(false);
    }

    public void OnStatus(StatusMessage status)
    { lock (_clientGate) { if (_current is { IsReady: true } current) current.Writer.Status(status); } }

    public async Task OnVideoFrameAsync(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit, CancellationToken ct)
    {
        ClientConnection? connection;
        lock (_clientGate) connection = _current is { IsReady: true } current ? current : null;
        if (connection != null) await connection.Writer.SendVideoAsync(keyframe, ptsUs, accessUnit, ct).ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);

    private sealed class ClientConnection : IFileConnection, IAsyncDisposable
    {
        private readonly TcpClient _tcp;
        private readonly ProtocolServer _owner;
        private readonly FrameReader _reader;
        private readonly FileInbox.Receiver _inbox;
        public readonly ConnectionWriter Writer;
        public bool Ready;
        public bool IsReady => Ready && !Closed.IsCancellationRequested;
        public CancellationToken Closed => Writer.Closed;
        public event Action<FileResultMessage>? FileResultReceived;
        private DateTime _lastRx = DateTime.UtcNow;

        public ClientConnection(TcpClient tcp, ProtocolServer owner, Stream stream)
        {
            _tcp = tcp; _tcp.NoDelay = true; _owner = owner;
            Writer = new ConnectionWriter(stream); _reader = new FrameReader(stream);
            _inbox = owner._fileInbox.OpenConnection(Closed);
        }

        public Task<bool> SendAsync(Frame frame, CancellationToken ct) => Writer.SendAsync(frame, ct);
        public void Retire(StatusMessage? terminal = null) { _ = Writer.BeginClose(terminal); }

        public async Task<bool> HandshakeAsync()
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(Closed);
            timeout.CancelAfter(HelloTimeout);
            var frame = await _reader.ReadFrameAsync(timeout.Token).ConfigureAwait(false);
            if (frame.Type != (byte)MessageType.Hello) return false;
            var hello = Json.Decode<HelloMessage>(frame.Payload);
            bool accepted = hello.Proto == 1;
            var reply = new HelloMessage
            {
                Proto = 1, App = _owner._appName, Name = _owner._hostName, MachineId = _owner._machineId,
                Version = accepted ? _owner._version : $"{_owner._version} (rejected proto {hello.Proto})",
            };
            return await Writer.SendAsync(Frame.Of(MessageType.Hello, Json.Encode(reply)), timeout.Token).ConfigureAwait(false) && accepted;
        }

        public async Task RunAsync()
        {
            var watchdog = WatchdogAsync();
            try
            {
                while (!Closed.IsCancellationRequested)
                {
                    var frame = await _reader.ReadFrameAsync(Closed).ConfigureAwait(false);
                    _lastRx = DateTime.UtcNow;
                    if (!Closed.IsCancellationRequested) await DispatchAsync(frame).ConfigureAwait(false);
                }
            }
            finally { Retire(); await watchdog.ConfigureAwait(false); }
        }

        private async Task DispatchAsync(Frame frame)
        {
            if (!frame.TryGetKnownType(out var type)) return;
            switch (type)
            {
                case MessageType.Ping: Writer.Ping(pong: true); break;
                case MessageType.Pong: break;
                case MessageType.Control:
                    await _owner.DispatchControlAsync(Json.Decode<ControlMessage>(frame.Payload), Closed).ConfigureAwait(false);
                    break;
                case MessageType.FileBegin:
                    Reply(_inbox.BeginFile(Json.Decode<FileBeginMessage>(frame.Payload))); break;
                case MessageType.FileChunk:
                    if (frame.Payload.Length >= 4)
                        Reply(_inbox.WriteChunk((int)BinaryPrimitives.ReadUInt32BigEndian(frame.Payload.Span[..4]), frame.Payload[4..]));
                    break;
                case MessageType.FileEnd: Reply(_inbox.EndFile(Json.Decode<FileEndMessage>(frame.Payload))); break;
                case MessageType.FileResult:
                    if (!Closed.IsCancellationRequested) FileResultReceived?.Invoke(Json.Decode<FileResultMessage>(frame.Payload));
                    break;
            }
        }

        private void Reply(FileResultMessage? result)
        { if (result != null) Writer.Reply(Frame.Of(MessageType.FileResult, Json.Encode(result))); }

        private async Task WatchdogAsync()
        {
            int missed = 0; DateTime? lastPing = null;
            try
            {
                while (!Closed.IsCancellationRequested)
                {
                    await Task.Delay(500, Closed).ConfigureAwait(false);
                    if (DateTime.UtcNow - _lastRx < TimeSpan.FromSeconds(2)) { missed = 0; continue; }
                    if (lastPing != null && DateTime.UtcNow - lastPing.Value < TimeSpan.FromSeconds(2)) continue;
                    lastPing = DateTime.UtcNow;
                    if (++missed >= 3) { Retire(); return; }
                    Writer.Ping(pong: false);
                }
            }
            catch (OperationCanceledException) { }
        }

        public async ValueTask DisposeAsync()
        {
            await Writer.BeginClose().ConfigureAwait(false);
            _inbox.AbortActiveTransfer();
            _tcp.Close();
        }
    }
}
