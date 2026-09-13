using System.Buffers.Binary;

namespace Streamer.Core.Protocol;

/// <summary>
/// One wire frame: u8 type, u32 big-endian length, payload bytes (STREAM.md §3).
/// <see cref="Type"/> is a raw byte, not the closed <see cref="MessageType"/> enum,
/// so an unrecognized type still decodes cleanly — the framing has to be skippable
/// before anything downstream gets a chance to recognize it.
/// </summary>
public readonly struct Frame
{
    public byte Type { get; }
    public ReadOnlyMemory<byte> Payload { get; }

    public Frame(byte type, ReadOnlyMemory<byte> payload = default)
    {
        Type = type;
        Payload = payload;
    }

    public Frame(MessageType type, ReadOnlyMemory<byte> payload = default) : this((byte)type, payload)
    {
    }

    public bool TryGetKnownType(out MessageType known)
    {
        if (Enum.IsDefined(typeof(MessageType), Type))
        {
            known = (MessageType)Type;
            return true;
        }
        known = default;
        return false;
    }

    public byte[] Encode()
    {
        var buf = new byte[5 + Payload.Length];
        buf[0] = Type;
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(1, 4), (uint)Payload.Length);
        Payload.Span.CopyTo(buf.AsSpan(5));
        return buf;
    }

    public static Frame Of(MessageType type) => new(type);
    public static Frame Of(MessageType type, byte[] payload) => new(type, payload);
    public static Frame Of(byte type, byte[] payload) => new(type, payload);
}
