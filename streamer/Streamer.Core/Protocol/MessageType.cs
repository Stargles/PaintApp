namespace Streamer.Core.Protocol;

/// <summary>
/// paintstream/1 message type byte (STREAM.md §3). Kept as a plain byte enum rather
/// than a closed switch anywhere in the framing path — "unknown types are skipped by
/// length, never fatal" means the codec must round-trip a value that isn't in this
/// list at all.
/// </summary>
public enum MessageType : byte
{
    Hello = 0x01,
    Status = 0x02,
    Video = 0x03,
    Control = 0x04,
    FileBegin = 0x10,
    FileChunk = 0x11,
    FileEnd = 0x12,
    FileResult = 0x13,
    Ping = 0x20,
    Pong = 0x21,
}
