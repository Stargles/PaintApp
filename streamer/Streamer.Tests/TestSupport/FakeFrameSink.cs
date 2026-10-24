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
    private readonly object _gate = new();
    private readonly List<StatusMessage> _statusMessages = new();
    private readonly List<(bool Keyframe, ulong PtsUs)> _videoFrames = new();
    public IReadOnlyList<StatusMessage> StatusMessages { get { lock (_gate) return _statusMessages.ToArray(); } }
    public StatusMessage? LastStatus { get { lock (_gate) return _statusMessages.Count == 0 ? null : _statusMessages[^1]; } }
    public void OnStatus(StatusMessage status) { lock (_gate) _statusMessages.Add(status); }
    public IReadOnlyList<(bool Keyframe, ulong PtsUs)> VideoFrames { get { lock (_gate) return _videoFrames.ToArray(); } }

    public Task OnVideoFrameAsync(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit, CancellationToken ct)
    {
        lock (_gate) _videoFrames.Add((keyframe, ptsUs));
        return Task.CompletedTask;
    }
}
