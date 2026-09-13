using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

public class FrameTests
{
    [Fact]
    public async Task RoundTrip_Hello()
    {
        var hello = new HelloMessage { Proto = 1, App = "PaintStreamer", Version = "1.2.3", Name = "desktop-cbr0fl6" };
        var frame = Frame.Of(MessageType.Hello, Json.Encode(hello));
        var decoded = await RoundTripAsync(frame);
        Assert.Equal((byte)MessageType.Hello, decoded.Type);
        var back = Json.Decode<HelloMessage>(decoded.Payload);
        Assert.Equal(hello.Proto, back.Proto);
        Assert.Equal(hello.App, back.App);
        Assert.Equal(hello.Version, back.Version);
        Assert.Equal(hello.Name, back.Name);
    }

    [Fact]
    public async Task RoundTrip_Status_WithReason()
    {
        var status = new StatusMessage
        {
            Source = new SourceDescriptor { Kind = "window", Name = "Blender", Id = "12345" },
            Width = 1920, Height = 1080, Fps = 30, Codec = "h264",
            Streaming = false, Reason = "The window was closed",
        };
        var decoded = await RoundTripAsync(Frame.Of(MessageType.Status, Json.Encode(status)));
        var back = Json.Decode<StatusMessage>(decoded.Payload);
        Assert.Equal("window", back.Source.Kind);
        Assert.Equal("Blender", back.Source.Name);
        Assert.Equal(1920, back.Width);
        Assert.False(back.Streaming);
        Assert.Equal("The window was closed", back.Reason);
    }

    [Fact]
    public async Task RoundTrip_Status_StreamingTrue_HasNoReasonField()
    {
        var status = new StatusMessage
        {
            Source = new SourceDescriptor { Kind = "monitor", Name = "Monitor 0", Id = "0" },
            Width = 1920, Height = 1080, Streaming = true,
        };
        var bytes = Json.Encode(status);
        Assert.DoesNotContain("reason", System.Text.Encoding.UTF8.GetString(bytes));
    }

    [Fact]
    public async Task RoundTrip_Control_AllCommands()
    {
        foreach (var cmd in new[] { ControlMessage.Pause, ControlMessage.Resume, ControlMessage.Keyframe })
        {
            var decoded = await RoundTripAsync(Frame.Of(MessageType.Control, Json.Encode(new ControlMessage { Cmd = cmd })));
            Assert.Equal(cmd, Json.Decode<ControlMessage>(decoded.Payload).Cmd);
        }
    }

    [Fact]
    public async Task RoundTrip_FileMessages()
    {
        var begin = new FileBeginMessage { Id = 7, Name = "ref.mp4", Size = 1234567, Kind = "video" };
        var beginBack = Json.Decode<FileBeginMessage>((await RoundTripAsync(Frame.Of(MessageType.FileBegin, Json.Encode(begin)))).Payload);
        Assert.Equal(7, beginBack.Id);
        Assert.Equal("ref.mp4", beginBack.Name);
        Assert.Equal(1234567, beginBack.Size);
        Assert.Equal("video", beginBack.Kind);

        var end = new FileEndMessage { Id = 7 };
        Assert.Equal(7, Json.Decode<FileEndMessage>((await RoundTripAsync(Frame.Of(MessageType.FileEnd, Json.Encode(end)))).Payload).Id);

        var okResult = new FileResultMessage { Id = 7, Ok = true };
        var okBack = Json.Decode<FileResultMessage>((await RoundTripAsync(Frame.Of(MessageType.FileResult, Json.Encode(okResult)))).Payload);
        Assert.True(okBack.Ok);
        Assert.Null(okBack.Reason);

        var failResult = new FileResultMessage { Id = 7, Ok = false, Reason = "No document is open on the iPad" };
        var failBack = Json.Decode<FileResultMessage>((await RoundTripAsync(Frame.Of(MessageType.FileResult, Json.Encode(failResult)))).Payload);
        Assert.False(failBack.Ok);
        Assert.Equal("No document is open on the iPad", failBack.Reason);
    }

    [Fact]
    public async Task RoundTrip_FileChunk_RawIdPrefixPlusBytes()
    {
        uint id = 42;
        byte[] bytes = { 1, 2, 3, 4, 5 };
        var payload = new byte[4 + bytes.Length];
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(payload, id);
        bytes.CopyTo(payload, 4);
        var decoded = await RoundTripAsync(Frame.Of(MessageType.FileChunk, payload));
        Assert.Equal((byte)MessageType.FileChunk, decoded.Type);
        Assert.Equal(id, System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(decoded.Payload.Span[..4]));
        Assert.Equal(bytes, decoded.Payload.Span[4..].ToArray());
    }

    [Fact]
    public async Task RoundTrip_PingPong_EmptyPayload()
    {
        var ping = await RoundTripAsync(Frame.Of(MessageType.Ping));
        Assert.Equal((byte)MessageType.Ping, ping.Type);
        Assert.Equal(0, ping.Payload.Length);

        var pong = await RoundTripAsync(Frame.Of(MessageType.Pong));
        Assert.Equal((byte)MessageType.Pong, pong.Type);
        Assert.Equal(0, pong.Payload.Length);
    }

    [Fact]
    public async Task RoundTrip_Video_KeyframeFlagAndMonotonicPts()
    {
        byte[] au = { 0, 0, 0, 1, 0x67, 0xAA, 0, 0, 0, 1, 0x65, 0xBB };
        var payload = new VideoPayload(keyframe: true, ptsUs: 123456789UL, au);
        var decoded = await RoundTripAsync(Frame.Of(MessageType.Video, payload.Encode()));
        var back = VideoPayload.Decode(decoded.Payload);
        Assert.True(back.Keyframe);
        Assert.Equal(123456789UL, back.PtsUs);
        Assert.Equal(au, back.AccessUnit.ToArray());

        var nonKey = new VideoPayload(keyframe: false, ptsUs: 987UL, new byte[] { 9, 9 });
        Assert.False(VideoPayload.Decode(nonKey.Encode()).Keyframe);
    }

    [Fact]
    public async Task UnknownType_IsSkippedByLength_NeverFatal()
    {
        var unknown = Frame.Of(0xEE, new byte[] { 1, 2, 3, 4 });
        var known = Frame.Of(MessageType.Hello, Json.Encode(new HelloMessage { Name = "after-unknown" }));

        var ms = new MemoryStream();
        ms.Write(unknown.Encode());
        ms.Write(known.Encode());
        ms.Position = 0;
        var reader = new FrameReader(ms);

        var first = await reader.ReadFrameAsync();
        Assert.Equal(0xEE, first.Type);
        Assert.False(first.TryGetKnownType(out _));
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, first.Payload.ToArray());

        // The unknown frame did not desynchronize the stream — the next real frame
        // reads cleanly right behind it.
        var second = await reader.ReadFrameAsync();
        Assert.True(second.TryGetKnownType(out var type));
        Assert.Equal(MessageType.Hello, type);
        Assert.Equal("after-unknown", Json.Decode<HelloMessage>(second.Payload).Name);
    }

    [Fact]
    public async Task PayloadSplitAcrossArbitraryChunkBoundaries()
    {
        var frames = new List<Frame>
        {
            Frame.Of(MessageType.Hello, Json.Encode(new HelloMessage { Name = "a" })),
            Frame.Of(MessageType.Status, Json.Encode(new StatusMessage { Streaming = true })),
            Frame.Of(MessageType.Ping),
            Frame.Of(MessageType.Video, new VideoPayload(true, 42, new byte[300]).Encode()),
        };
        byte[] all = frames.SelectMany(f => f.Encode()).ToArray();

        var rng = new Random(1234);
        foreach (int maxChunk in new[] { 1, 2, 3, 7, 64 })
        {
            var stream = new ChunkFeedStream();
            var pushTask = Task.Run(async () =>
            {
                int offset = 0;
                while (offset < all.Length)
                {
                    int size = Math.Min(1 + rng.Next(maxChunk), all.Length - offset);
                    stream.Push(all[offset..(offset + size)]);
                    offset += size;
                    await Task.Yield();
                }
                stream.Complete();
            });

            var reader = new FrameReader(stream);
            var decodedTypes = new List<byte>();
            for (int i = 0; i < frames.Count; i++)
            {
                var f = await reader.ReadFrameAsync();
                decodedTypes.Add(f.Type);
                Assert.Equal(frames[i].Payload.ToArray(), f.Payload.ToArray());
            }
            await pushTask;
            Assert.Equal(frames.Select(f => f.Type), decodedTypes);
        }
    }

    [Fact]
    public async Task TruncatedFrame_WaitsRatherThanThrowing()
    {
        var full = Frame.Of(MessageType.Hello, Json.Encode(new HelloMessage { Name = "waiter" })).Encode();
        var stream = new ChunkFeedStream();
        // Header plus only part of the payload.
        stream.Push(full[..(5 + 3)]);

        var reader = new FrameReader(stream);
        var readTask = reader.ReadFrameAsync();

        var finishedEarly = await Task.WhenAny(readTask, Task.Delay(200));
        Assert.NotEqual(readTask, finishedEarly); // still waiting, not thrown, not returned early

        stream.Push(full[(5 + 3)..]);
        stream.Complete();

        var frame = await readTask; // now completes
        Assert.Equal("waiter", Json.Decode<HelloMessage>(frame.Payload).Name);
    }

    [Fact]
    public async Task TruncatedFrame_RealEofThrowsEndOfStream()
    {
        var full = Frame.Of(MessageType.Hello, Json.Encode(new HelloMessage { Name = "x" })).Encode();
        var stream = new ChunkFeedStream();
        stream.Push(full[..3]); // not even a full header
        stream.Complete(); // real EOF now — this IS a truncation, not a wait

        var reader = new FrameReader(stream);
        await Assert.ThrowsAsync<EndOfStreamException>(() => reader.ReadFrameAsync());
    }

    private static async Task<Frame> RoundTripAsync(Frame frame)
    {
        var ms = new MemoryStream(frame.Encode());
        var reader = new FrameReader(ms);
        return await reader.ReadFrameAsync();
    }
}
