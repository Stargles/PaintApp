using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>
/// What <see cref="FileOutbox"/> needs from the connection in order to send FILE_* to
/// whichever client (if any) is currently connected — a narrow seam, the same shape as
/// <see cref="IFrameSink"/> (STREAM.md §4.6), so Streamer.Tests can drive FileOutbox
/// against a fake transport with no socket at all. ProtocolServer is the real
/// implementation.
/// </summary>
public interface IFileTransport
{
    /// <summary>True while a client is connected and past its HELLO handshake.</summary>
    bool HasClient { get; }

    /// <summary>Enqueues one frame to the current client's write queue. Returns false
    /// with nothing sent when there is no client — the caller (FileOutbox) is the one
    /// that waits for <see cref="ClientConnected"/> before trying again.</summary>
    bool TrySend(Frame frame);

    /// <summary>Fires once a client has completed HELLO and is ready to receive frames —
    /// FileOutbox's cue to resume a queue that was waiting with no iPad connected.</summary>
    event Action? ClientConnected;

    /// <summary>Fires when a FILE_RESULT arrives from the client, for FileOutbox to
    /// correlate against the id it sent in FILE_BEGIN.</summary>
    event Action<FileResultMessage>? FileResultReceived;
}
