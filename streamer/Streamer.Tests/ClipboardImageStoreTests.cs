using System.Drawing;
using System.Drawing.Imaging;
using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

/// <summary>
/// STREAM.md §7 stage 4 deliverable 1's Ctrl+V path only has this piece exercisable from
/// SSH — there is no interactive clipboard on the laptop over a remote session, so the
/// paste gesture itself is owner-verified (see the worker report). This pins the PNG
/// encoding in isolation: a synthetic BGRA32 buffer in, a real PNG round-tripped through
/// System.Drawing back to the same pixels out.
/// </summary>
public class ClipboardImageStoreTests : IDisposable
{
    private readonly string _tmpDir = Path.Combine(Path.GetTempPath(), $"paintstreamer-clipboard-test-{Guid.NewGuid():N}");
    public void Dispose() { try { Directory.Delete(_tmpDir, recursive: true); } catch { } }

    private static byte[] SolidBgra32(int width, int height, byte b, byte g, byte r, byte a)
    {
        var pixels = new byte[width * height * 4];
        for (int i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] = b; pixels[i + 1] = g; pixels[i + 2] = r; pixels[i + 3] = a;
        }
        return pixels;
    }

    [Fact]
    public void EncodePngProducesAValidPngWithTheRightPixels()
    {
        byte[] pixels = SolidBgra32(4, 3, b: 10, g: 20, r: 30, a: 255);
        byte[] png = ClipboardImageStore.EncodePng(pixels, width: 4, height: 3, strideBytes: 4 * 4);

        // PNG signature (RFC 2083).
        byte[] expectedSig = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        Assert.Equal(expectedSig, png[..8]);

        using var ms = new MemoryStream(png);
        using var decoded = new Bitmap(ms);
        Assert.Equal(4, decoded.Width);
        Assert.Equal(3, decoded.Height);
        Color pixel = decoded.GetPixel(1, 1);
        Assert.Equal(30, pixel.R);
        Assert.Equal(20, pixel.G);
        Assert.Equal(10, pixel.B);
    }

    [Fact]
    public void EncodePngHonoursAStrideWiderThanTheRowItself()
    {
        // A real BitmapSource.CopyPixels stride is often padded past width*4 — make sure
        // padding bytes never leak into the next row's pixels.
        int width = 2, height = 2, stride = 16; // row is 8 bytes of pixel data + 8 padding
        var pixels = new byte[stride * height];
        // Row 0: two red pixels (BGRA).
        for (int x = 0; x < width; x++)
        {
            int o = x * 4;
            pixels[o] = 0; pixels[o + 1] = 0; pixels[o + 2] = 255; pixels[o + 3] = 255;
        }
        // Row 1: two blue pixels, starting at the stride offset (past row 0's padding).
        for (int x = 0; x < width; x++)
        {
            int o = stride + x * 4;
            pixels[o] = 255; pixels[o + 1] = 0; pixels[o + 2] = 0; pixels[o + 3] = 255;
        }

        byte[] png = ClipboardImageStore.EncodePng(pixels, width, height, stride);
        using var decoded = new Bitmap(new MemoryStream(png));
        Assert.Equal(255, decoded.GetPixel(0, 0).R); // row 0 is red
        Assert.Equal(255, decoded.GetPixel(0, 1).B); // row 1 is blue
    }

    [Fact]
    public void SaveWritesUnderTheClipboardFolderAsATimestampedPng()
    {
        byte[] pixels = SolidBgra32(1, 1, 1, 2, 3, 255);
        var timestamp = new DateTimeOffset(2026, 9, 13, 10, 30, 0, 123, TimeSpan.Zero);

        string path = ClipboardImageStore.Save(_tmpDir, pixels, 1, 1, 4, timestamp);

        Assert.Equal(Path.Combine(_tmpDir, "20260913-103000-123.png"), path);
        Assert.True(File.Exists(path));
        using var decoded = new Bitmap(path);
        Assert.Equal(1, decoded.Width);
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(1, 0)]
    public void RejectsNonPositiveDimensions(int width, int height)
    {
        Assert.Throws<ArgumentException>(() => ClipboardImageStore.EncodePng(new byte[16], width, height, 16));
    }
}
