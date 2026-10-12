using Streamer.Core;
using Streamer.Core.Protocol;

namespace Streamer.Tests.TestSupport;

/// <summary>
/// A no-socket stand-in for <see cref="IFrameSink"/>, same shape as
/// <see cref="FakeFileTransport"/>: captures every STATUS StreamerSession broadcasts so a
/// test can assert on `streaming`/`reason` — and every VIDEO frame — without a real
/// ProtocolServer connection.
/// </summary>
public sealed class FakeFrameSink : IFrameSink
{
    public List<StatusMessage> StatusMessages { get; } = new();

    public StatusMessage? LastStatus => StatusMessages.Count == 0 ? null : StatusMessages[^1];

    public void OnStatus(StatusMessage status) => StatusMessages.Add(status);

    public List<(bool Keyframe, ulong PtsUs)> VideoFrames { get; } = new();

    public void OnVideoFrame(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit) =>
        VideoFrames.Add((keyframe, ptsUs));
}
