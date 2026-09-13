using Streamer.Core.Protocol;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// Pins AccessUnitSplitter against the fixture tools/stream/fake-streamer.py's Python
/// AUSplitter already established the ground truth for (verified directly against that
/// script while writing this test: 60 AUs total, keyframes at index 0 and 30, each
/// keyframe AU's NAL types [7,8,6,5] = SPS,PPS,SEI,IDR-slice, every other AU [1] = a
/// single non-IDR slice). A C# port that disagrees with the Python one here would mean
/// the two from-scratch implementations of STREAM.md §3's "simpler and sufficient" rule
/// read it differently — exactly the divergence this test exists to catch before a real
/// device sees it as a decode error.
/// </summary>
public class AccessUnitSplitterTests
{
    private static byte[] LoadFixture() =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Fixtures", "stream-testsrc-640x360.h264"));

    [Fact]
    public void FixtureSplitsIntoExactly60AccessUnits()
    {
        var splitter = new AccessUnitSplitter();
        var data = LoadFixture();
        var aus = splitter.Feed(data);
        aus.AddRange(splitter.Feed(ReadOnlySpan<byte>.Empty, end: true));
        Assert.Equal(60, aus.Count);
    }

    [Fact]
    public void KeyframesAreExactlyAtIndex0And30()
    {
        var splitter = new AccessUnitSplitter();
        var aus = splitter.Feed(LoadFixture());
        aus.AddRange(splitter.Feed(ReadOnlySpan<byte>.Empty, end: true));
        var keyframeIndices = aus.Select((au, i) => (au, i)).Where(t => t.au.Keyframe).Select(t => t.i).ToList();
        Assert.Equal(new[] { 0, 30 }, keyframeIndices);
    }

    [Fact]
    public void EveryKeyframeAuStartsWithSpsThenPps()
    {
        var splitter = new AccessUnitSplitter();
        var aus = splitter.Feed(LoadFixture());
        aus.AddRange(splitter.Feed(ReadOnlySpan<byte>.Empty, end: true));
        foreach (var au in aus.Where(a => a.Keyframe))
        {
            Assert.True(au.NalTypes.Count >= 2);
            Assert.Equal(7, au.NalTypes[0]); // SPS
            Assert.Equal(8, au.NalTypes[1]); // PPS
        }
    }

    [Fact]
    public void NonKeyframeAusAreASingleNonIdrSlice()
    {
        var splitter = new AccessUnitSplitter();
        var aus = splitter.Feed(LoadFixture());
        aus.AddRange(splitter.Feed(ReadOnlySpan<byte>.Empty, end: true));
        foreach (var au in aus.Where(a => !a.Keyframe))
        {
            Assert.Equal(new[] { 1 }, au.NalTypes);
        }
    }

    [Fact]
    public void FeedingByteByByteProducesTheSameResultAsOneShot()
    {
        var data = LoadFixture();
        var streaming = new AccessUnitSplitter();
        var aus = new List<AccessUnit>();
        foreach (byte b in data)
        {
            aus.AddRange(streaming.Feed(new[] { b }));
        }
        aus.AddRange(streaming.Feed(ReadOnlySpan<byte>.Empty, end: true));

        Assert.Equal(60, aus.Count);
        Assert.Equal(new[] { 0, 30 }, aus.Select((au, i) => (au, i)).Where(t => t.au.Keyframe).Select(t => t.i));
    }

    [Fact]
    public void FeedingInArbitraryChunkSizesMatchesOneShot()
    {
        var data = LoadFixture();
        var oneShotSplitter = new AccessUnitSplitter();
        var oneShot = oneShotSplitter.Feed(data);
        oneShot.AddRange(oneShotSplitter.Feed(ReadOnlySpan<byte>.Empty, end: true));

        var rng = new Random(99);
        var chunkedSplitter = new AccessUnitSplitter();
        var chunked = new List<AccessUnit>();
        int offset = 0;
        while (offset < data.Length)
        {
            int size = Math.Min(1 + rng.Next(777), data.Length - offset);
            chunked.AddRange(chunkedSplitter.Feed(data.AsSpan(offset, size)));
            offset += size;
        }
        chunked.AddRange(chunkedSplitter.Feed(ReadOnlySpan<byte>.Empty, end: true));

        Assert.Equal(oneShot.Count, chunked.Count);
        for (int i = 0; i < oneShot.Count; i++)
        {
            Assert.Equal(oneShot[i].Keyframe, chunked[i].Keyframe);
            Assert.Equal(oneShot[i].Bytes, chunked[i].Bytes);
        }
    }

    [Fact]
    public void IdrAuGetsSpsPpsPrependedWhenEncoderOmittedThem()
    {
        // Two access units: AU0 = SPS,PPS,non-IDR-slice (caches last_sps/last_pps and
        // closes on its own VCL NAL); AU1 = a BARE IDR slice with no SPS/PPS of its own
        // immediately before it — the shape GstProcess must cope with if an encoder
        // ever omits them on a keyframe. The splitter must prepend the cached SPS/PPS
        // from AU0 onto AU1's emitted bytes even though AU1's own NAL list never
        // contained them.
        byte[] StartCode(byte nalTypeAndHeader) => new byte[] { 0, 0, 0, 1, nalTypeAndHeader };
        var sps = StartCode(0x67).Concat(new byte[] { 0xAA }).ToArray();
        var pps = StartCode(0x68).Concat(new byte[] { 0xBB }).ToArray();
        var nonIdrSlice = StartCode(0x41).Concat(new byte[] { 0xDD }).ToArray(); // type 1, closes AU0
        var bareIdr = StartCode(0x65).Concat(new byte[] { 0xCC }).ToArray(); // type 5, closes AU1, alone

        var splitter = new AccessUnitSplitter();
        var closed = splitter.Feed(sps.Concat(pps).Concat(nonIdrSlice).Concat(bareIdr).ToArray());
        closed.AddRange(splitter.Feed(ReadOnlySpan<byte>.Empty, end: true));

        Assert.Equal(2, closed.Count);

        Assert.False(closed[0].Keyframe);
        Assert.Equal(new[] { 7, 8, 1 }, closed[0].NalTypes);
        Assert.Equal(sps.Concat(pps).Concat(nonIdrSlice).ToArray(), closed[0].Bytes);

        Assert.True(closed[1].Keyframe);
        Assert.Equal(new[] { 5 }, closed[1].NalTypes); // AU1's own NALs never included SPS/PPS
        Assert.Equal(sps.Concat(pps).Concat(bareIdr).ToArray(), closed[1].Bytes); // but the bytes got them prepended
    }
}
