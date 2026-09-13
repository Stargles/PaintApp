using System.Buffers.Binary;

namespace Streamer.Core.Protocol;

/// <summary>
/// Reads §3 frames off any <see cref="Stream"/>, one at a time, regardless of how the
/// underlying transport chooses to chunk its bytes. A frame that has not fully arrived
/// yet is not a truncation — it is exactly what "wait" means over a live TCP socket —
/// so this only throws <see cref="EndOfStreamException"/> when the stream reaches a
/// real EOF partway through a frame; short of that it keeps awaiting more reads.
/// </summary>
public sealed class FrameReader
{
    private readonly Stream _stream;
    private readonly byte[] _headerBuf = new byte[5];

    public FrameReader(Stream stream)
    {
        _stream = stream;
    }

    public async Task<Frame> ReadFrameAsync(CancellationToken ct = default)
    {
        await ReadExactAsync(_headerBuf, 5, ct).ConfigureAwait(false);
        byte type = _headerBuf[0];
        uint length = BinaryPrimitives.ReadUInt32BigEndian(_headerBuf.AsSpan(1, 4));
        if (length == 0)
        {
            return new Frame(type, ReadOnlyMemory<byte>.Empty);
        }
        var payload = new byte[length];
        await ReadExactAsync(payload, (int)length, ct).ConfigureAwait(false);
        return new Frame(type, payload);
    }

    private async Task ReadExactAsync(byte[] buffer, int count, CancellationToken ct)
    {
        int offset = 0;
        while (offset < count)
        {
            int n = await _stream.ReadAsync(buffer.AsMemory(offset, count - offset), ct).ConfigureAwait(false);
            if (n == 0)
            {
                throw new EndOfStreamException(
                    $"stream closed after {offset} of {count} bytes — a frame truncated by real EOF, " +
                    "not merely a slow arrival");
            }
            offset += n;
        }
    }
}
