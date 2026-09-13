using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>
/// STREAM.md §4.6: "Core exposes IFrameSink — the socket is one implementation, and an
/// in-process consumer is another." StreamerSession pushes STATUS/VIDEO to every
/// registered sink; it never talks to a socket directly. A future in-process host (the
/// paint app itself, per the brief's point 9) implements this with no networking at all.
/// </summary>
public interface IFrameSink
{
    void OnStatus(StatusMessage status);
    void OnVideoFrame(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit);
}
