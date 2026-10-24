using Streamer.Core;
using Streamer.Core.Protocol;

namespace Streamer.Tests.TestSupport;

/// <summary>
/// A no-socket stand-in for ProtocolServer's <see cref="IFileTransport"/> so
/// FileOutbox's queueing, chunking and timeout logic can be driven directly. Every
/// FILE_BEGIN/FILE_CHUNK/FILE_END frame FileOutbox sends is captured in <see cref="Sent"/>
/// in order; the test plays the iPad's part by calling <see cref="SetHasClient"/> and
/// <see cref="Reply"/>.
/// </summary>
public sealed class FakeFileTransport : IFileTransport
{
    private readonly object _gate = new();
    private readonly List<Frame> _sent = new();
    // The sender appends on the pump thread while tests poll/enumerate from another thread.
    public IReadOnlyList<Frame> Sent { get { lock (_gate) return _sent.ToArray(); } }
    private bool _failNextSend;
    public bool FailNextSend { get { lock (_gate) return _failNextSend; } set { lock (_gate) _failNextSend = value; } }
    private bool _hasClient;
    private Connection? _connection;
    private Func<Frame, CancellationToken, Task>? _beforeSendAsync;
    public Func<Frame, CancellationToken, Task>? BeforeSendAsync
    { get { lock (_gate) return _beforeSendAsync; } set { lock (_gate) _beforeSendAsync = value; } }

    private bool Record(Frame frame)
    {
        lock (_gate)
        {
            if (_failNextSend) { _failNextSend = false; return false; }
            _sent.Add(frame);
            return true;
        }
    }

    private sealed class Connection : IFileConnection
    {
        private readonly FakeFileTransport _owner;
        private readonly CancellationTokenSource _closed = new();
        public Connection(FakeFileTransport owner) { _owner = owner; }
        public CancellationToken Closed => _closed.Token;
        public event Action<FileResultMessage>? FileResultReceived;
        public void Close() => _closed.Cancel();
        public void Reply(FileResultMessage result) => FileResultReceived?.Invoke(result);
        public async Task<bool> SendAsync(Frame frame, CancellationToken ct)
        {
            if (Closed.IsCancellationRequested) return false;
            if (_owner.BeforeSendAsync is { } gate) await gate(frame, ct);
            if (ct.IsCancellationRequested || Closed.IsCancellationRequested) return false;
            return _owner.Record(frame);
        }
    }

    public IFileConnection? CaptureConnection() { lock (_gate) return _hasClient ? _connection : null; }
    public bool HasClient
    {
        get { lock (_gate) return _hasClient; }
        set => SetHasClient(value);
    }

    public event Action? ClientConnected;

    public void SetHasClient(bool value)
    {
        Connection? retired = null;
        bool notify;
        lock (_gate)
        {
            notify = value && !_hasClient;
            _hasClient = value;
            if (!value) { retired = _connection; _connection = null; }
            else if (notify) _connection = new Connection(this);
        }
        retired?.Close();
        if (notify) ClientConnected?.Invoke();
    }

    /// <summary>Simulates the iPad answering a FILE_BEGIN/FILE_END with FILE_RESULT.</summary>
    public void Reply(int id, bool ok, string? reason = null)
    {
        Connection? connection;
        lock (_gate) connection = _connection;
        connection?.Reply(new FileResultMessage { Id = id, Ok = ok, Reason = reason });
    }

    public FileBeginMessage DecodeBegin(Frame frame) => Json.Decode<FileBeginMessage>(frame.Payload);
    public FileEndMessage DecodeEnd(Frame frame) => Json.Decode<FileEndMessage>(frame.Payload);
}
