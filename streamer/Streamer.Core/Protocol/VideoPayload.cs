using System.Buffers.Binary;

namespace Streamer.Core.Protocol;

/// <summary>
/// The non-JSON VIDEO payload: u8 flags (bit0 = keyframe), u64 big-endian pts_us, then
/// one Annex-B H.264 access unit (STREAM.md §3).
/// </summary>
public readonly struct VideoPayload
{
    public const int HeaderLength = 9; // 1 (flags) + 8 (pts_us)
    private const byte KeyframeBit = 0x01;

    public bool Keyframe { get; }
    public ulong PtsUs { get; }
    public ReadOnlyMemory<byte> AccessUnit { get; }

    public VideoPayload(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit)
    {
        Keyframe = keyframe;
        PtsUs = ptsUs;
        AccessUnit = accessUnit;
    }

    public byte[] Encode()
    {
        var buf = new byte[HeaderLength + AccessUnit.Length];
        buf[0] = (byte)(Keyframe ? KeyframeBit : 0);
        BinaryPrimitives.WriteUInt64BigEndian(buf.AsSpan(1, 8), PtsUs);
        AccessUnit.Span.CopyTo(buf.AsSpan(HeaderLength));
        return buf;
    }

    public static VideoPayload Decode(ReadOnlyMemory<byte> payload)
    {
        if (payload.Length < HeaderLength)
        {
            throw new ArgumentException($"VIDEO payload too short: {payload.Length} bytes", nameof(payload));
        }
        var span = payload.Span;
        bool keyframe = (span[0] & KeyframeBit) != 0;
        ulong pts = BinaryPrimitives.ReadUInt64BigEndian(span.Slice(1, 8));
        return new VideoPayload(keyframe, pts, payload[HeaderLength..]);
    }
}
