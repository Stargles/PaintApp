using System.Threading.Channels;

namespace Streamer.Tests.TestSupport;

/// <summary>
/// A Stream whose bytes arrive exactly when the test pushes them, in whatever chunk
/// sizes the test chooses — the tool for proving FrameReader handles "a payload split
/// across arbitrary chunk boundaries" and "a truncated frame waits" rather than
/// throwing. ReadAsync blocks on a real await until a chunk is queued or Complete() is
/// called with nothing left, which is what "waits" needs to mean: indistinguishable
/// from a slow real socket, never from a broken one.
/// </summary>
public sealed class ChunkFeedStream : Stream
{
    private readonly Channel<byte[]> _channel = Channel.CreateUnbounded<byte[]>();
    private ReadOnlyMemory<byte> _carry;

    public void Push(byte[] chunk) => _channel.Writer.TryWrite(chunk);
    public void Complete() => _channel.Writer.TryComplete();

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        if (_carry.IsEmpty)
        {
            bool more = await _channel.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false);
            if (!more) return 0; // channel completed and drained: real EOF
            if (!_channel.Reader.TryRead(out var chunk)) return 0;
            _carry = chunk;
        }
        int n = Math.Min(buffer.Length, _carry.Length);
        _carry.Span[..n].CopyTo(buffer.Span);
        _carry = _carry[n..];
        return n;
    }

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }
    public override void Flush() { }
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
