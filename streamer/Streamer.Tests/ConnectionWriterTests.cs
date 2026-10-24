using Streamer.Core;
using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

public sealed class ConnectionWriterTests
{
    private sealed class GatedStream : Stream
    {
        private readonly MemoryStream _bytes = new();
        private readonly TaskCompletionSource _release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource HeaderWritten = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly byte _type;
        private bool _header, _blocked;
        public GatedStream(MessageType type) { _type = (byte)type; }
        public byte[] Bytes { get { lock (_bytes) return _bytes.ToArray(); } }
        public void Release() => _release.TrySetResult();
        public override async ValueTask WriteAsync(ReadOnlyMemory<byte> data, CancellationToken ct = default)
        {
            if (_header && !_blocked) { _blocked = true; await _release.Task.WaitAsync(ct); }
            lock (_bytes) _bytes.Write(data.Span);
            if (!_header && data.Length >= 5 && data.Span[0] == _type)
            { _header = true; HeaderWritten.TrySetResult(); }
        }
        public override void Close() { _release.TrySetCanceled(); base.Close(); }
        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => Bytes.Length;
        public override long Position { get => Length; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    [Fact]
    public async Task CancelledProducerDoesNotTruncateAnAdmittedFrameAndNextFrameStillParses()
    {
        using var stream = new GatedStream(MessageType.FileChunk);
        var writer = new ConnectionWriter(stream);
        using var firstProducer = new CancellationTokenSource();
        var original = new byte[] { 0, 0, 0, 7, 31, 41, 59 };
        var first = writer.SendAsync(Frame.Of(MessageType.FileChunk, original), firstProducer.Token);
        await stream.HeaderWritten.Task.WaitAsync(TimeSpan.FromSeconds(3));
        firstProducer.Cancel();
        Assert.False(await first.WaitAsync(TimeSpan.FromSeconds(3)));
        var next = writer.SendAsync(Frame.Of(MessageType.Ping), CancellationToken.None);
        Assert.Equal(1, writer.RetainedBulkCount);
        Assert.Equal(1, writer.WaitingBulkProducers);
        Assert.Equal(5, stream.Bytes.Length);
        for (int i = 0; i < 100; i++) writer.Status(new StatusMessage { Streaming = false, Reason = $"status{i}" });
        writer.Ping(false); writer.Ping(true);
        Assert.Equal(3, writer.PendingControlCount);
        stream.Release();
        Assert.True(await next.WaitAsync(TimeSpan.FromSeconds(3)));
        await writer.BeginClose();
        var reader = new FrameReader(new MemoryStream(stream.Bytes));
        Assert.Equal(original, (await reader.ReadFrameAsync()).Payload.ToArray());
        var frames = new List<Frame>();
        while (frames.Count < 4) frames.Add(await reader.ReadFrameAsync());
        Assert.Contains(frames, frame => frame.Type == (byte)MessageType.Ping);
        Assert.Contains(frames, frame => frame.Type == (byte)MessageType.Pong);
        var status = Assert.Single(frames.Where(frame => frame.Type == (byte)MessageType.Status));
        Assert.Equal("status99", Json.Decode<StatusMessage>(status.Payload).Reason);
        Assert.Equal(0, writer.RetainedBulkCount);
        Assert.Equal(0, writer.WaitingBulkProducers);
    }

    [Fact]
    public async Task CloseUnblocksAndJoinsStalledWriteAndAllCreditWaiters()
    {
        using var stream = new GatedStream(MessageType.Video);
        var writer = new ConnectionWriter(stream);
        var active = writer.SendVideoAsync(true, 1, new byte[] { 0, 0, 0, 1, 0x65 }, CancellationToken.None);
        await stream.HeaderWritten.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var waiting = writer.SendAsync(Frame.Of(MessageType.Ping), CancellationToken.None);
        Assert.Equal(1, writer.RetainedBulkCount);
        Assert.Equal(1, writer.WaitingBulkProducers);
        await writer.BeginClose().WaitAsync(TimeSpan.FromSeconds(5));
        Assert.False(await active);
        Assert.False(await waiting);
        Assert.Equal(0, writer.RetainedBulkCount);
        Assert.Equal(0, writer.WaitingBulkProducers);
        Assert.True(writer.Closed.IsCancellationRequested);
        Assert.False(await writer.SendAsync(Frame.Of(MessageType.Ping), CancellationToken.None));
    }

    [Fact]
    public async Task TerminalReplacementDrainsAcceptedFileResultsBeforeStatusAndClose()
    {
        using var stream = new GatedStream(MessageType.FileChunk);
        var writer = new ConnectionWriter(stream);
        var active = writer.SendAsync(Frame.Of(MessageType.FileChunk, new byte[] { 0, 0, 0, 7, 42 }), CancellationToken.None);
        await stream.HeaderWritten.Task.WaitAsync(TimeSpan.FromSeconds(3));
        writer.Reply(Frame.Of(MessageType.FileResult, Json.Encode(new FileResultMessage { Id = 7, Ok = true })));
        var close = writer.BeginClose(new StatusMessage { Streaming = false, Reason = ProtocolServer.ReplacedByAnotherConnectionReason });
        stream.Release();
        await close;
        Assert.False(await active, "Retirement settles the caller while wire owner still finishes the admitted bytes.");
        var bytes = new MemoryStream(stream.Bytes);
        var reader = new FrameReader(bytes);
        Assert.Equal((byte)MessageType.FileChunk, (await reader.ReadFrameAsync()).Type);
        var result = await reader.ReadFrameAsync();
        Assert.Equal((byte)MessageType.FileResult, result.Type);
        Assert.True(Json.Decode<FileResultMessage>(result.Payload).Ok);
        var terminal = await reader.ReadFrameAsync();
        Assert.Equal(ProtocolServer.ReplacedByAnotherConnectionReason, Json.Decode<StatusMessage>(terminal.Payload).Reason);
        Assert.Equal(bytes.Length, bytes.Position);
        Assert.Equal(0, writer.RetainedBulkCount);
    }

    private sealed class WriterSink : IFrameSink
    {
        private readonly ConnectionWriter _writer;
        public WriterSink(ConnectionWriter writer) { _writer = writer; }
        public void OnStatus(StatusMessage status) => _writer.Status(status);
        public async Task OnVideoFrameAsync(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit, CancellationToken ct)
        { await _writer.SendVideoAsync(keyframe, ptsUs, accessUnit, ct); }
    }

    [Fact]
    public async Task SourceSwitchStopsItsStalledProducerWhileConnectionStillOwnsTheWholeFrame()
    {
        using var stream = new GatedStream(MessageType.Video);
        var writer = new ConnectionWriter(stream);
        var factory = new FakePipelineFactory();
        await using var session = new StreamerSession(@"C:\unused", createPipeline: factory.CreateAsync);
        session.AddSink(new WriterSink(writer));
        var source = new CaptureSource { Kind = SourceKind.Monitor, Id = "0", Name = "first", Width = 64, Height = 64 };
        await session.SetSourceAsync(source);
        await session.OnClientConnectedAsync();
        factory.Created[0].Connect();
        var oldDelivery = factory.Created[0].EmitAsync(true);
        await stream.HeaderWritten.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await session.SetSourceAsync(new CaptureSource { Kind = SourceKind.Monitor, Id = "1", Name = "next", Width = 64, Height = 64 })
            .WaitAsync(TimeSpan.FromSeconds(3));
        Assert.True(factory.Created[0].Stopped);
        await oldDelivery.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Equal(2, factory.Created.Count);
        Assert.Equal(1, factory.Live);
        Assert.Equal(1, writer.RetainedBulkCount);
        Assert.Equal(0, writer.WaitingBulkProducers);
        stream.Release();
        await writer.BeginClose();
        var reader = new FrameReader(new MemoryStream(stream.Bytes));
        Frame frame;
        do { frame = await reader.ReadFrameAsync(); } while (frame.Type != (byte)MessageType.Video);
        Assert.Equal(new byte[] { 0, 0, 0, 1, 0x65 }, VideoPayload.Decode(frame.Payload).AccessUnit.ToArray());
    }
}
