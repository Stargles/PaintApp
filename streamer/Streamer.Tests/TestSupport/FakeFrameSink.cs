using Streamer.Core;
using Streamer.Core.Protocol;

namespace Streamer.Tests.TestSupport;

/// <summary>
/// A no-socket stand-in for <see cref="IFrameSink"/>, same shape as
/// <see cref="FakeFileTransport"/>: captures every STATUS StreamerSession broadcasts so a
/// test can assert on `streaming`/`reason` without a real ProtocolServer connection.
/// </summary>
public sealed class FakeFrameSink : IFrameSink
{
    public List<StatusMessage> StatusMessages { get; } = new();

    public StatusMessage? LastStatus => StatusMessages.Count == 0 ? null : StatusMessages[^1];

    public void OnStatus(StatusMessage status) => StatusMessages.Add(status);

    public void OnVideoFrame(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit)
    {
        // Not needed by any test using this fake today — StreamerSession's pipeline
        // never actually starts in those tests (StreamerSessionEnvironmentBlockTests'
        // doc comment says why), so no VIDEO frame is ever produced to capture.
    }
}
