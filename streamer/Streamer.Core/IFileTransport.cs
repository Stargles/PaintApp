using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>One HELLO-ready connection captured for the entire file. It never redirects to a
/// newer peer. Send completion means the frame was written, not queued.</summary>
public interface IFileConnection
{
    CancellationToken Closed { get; }
    Task<bool> SendAsync(Frame frame, CancellationToken ct);
    event Action<FileResultMessage>? FileResultReceived;
}

public interface IFileTransport
{
    IFileConnection? CaptureConnection();
    event Action? ClientConnected;
}
