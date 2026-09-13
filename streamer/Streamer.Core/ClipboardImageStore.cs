using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Streamer.Core;

/// <summary>
/// Turns a pasted bitmap into a PNG file under %LOCALAPPDATA%\PaintStreamer\clipboard\
/// (STREAM.md §4.4/§7 stage 4 deliverable 1: "A pasted bitmap is saved to
/// %LOCALAPPDATA%\PaintStreamer\clipboard\&lt;timestamp&gt;.png first and sent from
/// there"), so Ctrl+V feeds <see cref="FileOutbox"/> exactly the way a dropped file does
/// — a path on disk. Takes raw top-down BGRA32 pixel bytes plus dimensions rather than a
/// WPF BitmapSource, so the PNG encoding is testable from Streamer.Tests with no WPF, no
/// STA thread and no real clipboard involved; Streamer.Tray's MainWindow does the one-line
/// BitmapSource → byte[] copy (FormatConvertedBitmap + CopyPixels) before calling in —
/// "the WPF layer only binds" (STREAM.md §7 stage 4's instruction for every new control).
/// </summary>
public static class ClipboardImageStore
{
    /// <summary>Encodes and writes the PNG, returning its path.</summary>
    public static string Save(string clipboardFolder, byte[] bgra32Pixels, int width, int height, int strideBytes,
        DateTimeOffset? timestamp = null)
    {
        Directory.CreateDirectory(clipboardFolder);
        string name = $"{(timestamp ?? DateTimeOffset.Now):yyyyMMdd-HHmmss-fff}.png";
        string path = Path.Combine(clipboardFolder, name);
        byte[] png = EncodePng(bgra32Pixels, width, height, strideBytes);
        File.WriteAllBytes(path, png);
        return path;
    }

    /// <summary>The conversion itself, split out so a test can assert on the bytes
    /// without touching disk.</summary>
    public static byte[] EncodePng(byte[] bgra32Pixels, int width, int height, int strideBytes)
    {
        if (width <= 0 || height <= 0) throw new ArgumentException("width and height must be positive");
        if (strideBytes < width * 4) throw new ArgumentException("strideBytes is narrower than one BGRA32 row");
        if (bgra32Pixels.Length < strideBytes * height)
            throw new ArgumentException("bgra32Pixels is shorter than strideBytes * height");

        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        var rect = new Rectangle(0, 0, width, height);
        BitmapData data = bitmap.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        try
        {
            for (int y = 0; y < height; y++)
            {
                Marshal.Copy(bgra32Pixels, y * strideBytes, data.Scan0 + y * data.Stride, width * 4);
            }
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
        using var ms = new MemoryStream();
        bitmap.Save(ms, ImageFormat.Png);
        return ms.ToArray();
    }
}
