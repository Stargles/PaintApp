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
    public List<Frame> Sent { get; } = new();
    public bool FailNextSend;

    private bool _hasClient;
    private Connection? _connection;
    public Func<Frame, CancellationToken, Task>? BeforeSendAsync;

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
            if (_owner.FailNextSend) { _owner.FailNextSend = false; return false; }
            _owner.Sent.Add(frame);
            return true;
        }
    }

    public IFileConnection? CaptureConnection() => _hasClient ? _connection : null;
    public bool HasClient
    {
        get => _hasClient;
        set => SetHasClient(value);
    }

    public event Action? ClientConnected;

    public void SetHasClient(bool value)
    {
        bool wasFalse = !_hasClient;
        _hasClient = value;
        if (!value) { _connection?.Close(); _connection = null; }
        if (value && wasFalse) { _connection = new Connection(this); ClientConnected?.Invoke(); }
    }

    /// <summary>Simulates the iPad answering a FILE_BEGIN/FILE_END with FILE_RESULT.</summary>
    public void Reply(int id, bool ok, string? reason = null) =>
        _connection?.Reply(new FileResultMessage { Id = id, Ok = ok, Reason = reason });

    public FileBeginMessage DecodeBegin(Frame frame) => Json.Decode<FileBeginMessage>(frame.Payload);
    public FileEndMessage DecodeEnd(Frame frame) => Json.Decode<FileEndMessage>(frame.Payload);
}
