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
    public bool HasClient
    {
        get => _hasClient;
        set => SetHasClient(value);
    }

    public event Action? ClientConnected;
    public event Action<FileResultMessage>? FileResultReceived;

    public void SetHasClient(bool value)
    {
        bool wasFalse = !_hasClient;
        _hasClient = value;
        if (value && wasFalse) ClientConnected?.Invoke();
    }

    public bool TrySend(Frame frame)
    {
        if (FailNextSend) { FailNextSend = false; return false; }
        if (!_hasClient) return false;
        Sent.Add(frame);
        return true;
    }

    /// <summary>Simulates the iPad answering a FILE_BEGIN/FILE_END with FILE_RESULT.</summary>
    public void Reply(int id, bool ok, string? reason = null) =>
        FileResultReceived?.Invoke(new FileResultMessage { Id = id, Ok = ok, Reason = reason });

    public FileBeginMessage DecodeBegin(Frame frame) => Json.Decode<FileBeginMessage>(frame.Payload);
    public FileEndMessage DecodeEnd(Frame frame) => Json.Decode<FileEndMessage>(frame.Payload);
}
