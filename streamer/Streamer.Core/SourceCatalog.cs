using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace Streamer.Core;

public enum SourceKind
{
    Monitor,
    Window,
}

/// <summary>
/// One capturable source. <see cref="Id"/> is what <c>d3d11screencapturesrc</c> needs:
/// the zero-based monitor index (as a string) for a monitor, the HWND (as a decimal
/// string) for a window — STREAM.md §4 requires the monitor list's ordering to agree
/// with <c>monitor-index</c>, which is why <see cref="SourceCatalog.EnumerateMonitors"/>
/// walks <c>EnumDisplayMonitors</c> in callback order and numbers them 0..N in that
/// same order rather than sorting by position or device name.
/// </summary>
public sealed class CaptureSource
{
    public required SourceKind Kind { get; init; }
    public required string Id { get; init; }
    public required string Name { get; init; }
    public int Width { get; init; }
    public int Height { get; init; }
    public bool IsPrimary { get; init; }
    public string? ProcessName { get; init; }
    public IntPtr WindowHandle { get; init; }

    public string SourceKindWire => Kind == SourceKind.Monitor ? "monitor" : "window";
}

/// <summary>
/// Enumerates monitors (EnumDisplayMonitors/GetMonitorInfo) and windows (EnumWindows,
/// filtered to visible + titled + not a tool window + not DWM-cloaked), per STREAM.md
/// §4's SourceCatalog description. Thumbnails via PrintWindow for the picker.
/// </summary>
public static class SourceCatalog
{
    public static List<CaptureSource> EnumerateMonitors()
    {
        var result = new List<CaptureSource>();
        int index = 0;
        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
            (IntPtr hMonitor, IntPtr _, ref NativeMethods.Rect rect, IntPtr _) =>
            {
                var mi = new NativeMethods.MonitorInfoEx
                {
                    cbSize = Marshal.SizeOf<NativeMethods.MonitorInfoEx>(),
                };
                bool isPrimary = false;
                string device = $"Monitor {index}";
                if (NativeMethods.GetMonitorInfo(hMonitor, ref mi))
                {
                    isPrimary = (mi.dwFlags & NativeMethods.MONITORINFOF_PRIMARY) != 0;
                    device = mi.szDevice;
                }
                int width = rect.Right - rect.Left;
                int height = rect.Bottom - rect.Top;
                result.Add(new CaptureSource
                {
                    Kind = SourceKind.Monitor,
                    Id = index.ToString(),
                    // A name a person recognizes; the wire id is always the numeric index.
                    Name = isPrimary ? $"{device} (Primary, {width}x{height})" : $"{device} ({width}x{height})",
                    Width = width,
                    Height = height,
                    IsPrimary = isPrimary,
                });
                index++;
                return true;
            }, IntPtr.Zero);
        return result;
    }

    public static List<CaptureSource> EnumerateWindows()
    {
        var result = new List<CaptureSource>();
        IntPtr shellWindow = NativeMethods.GetShellWindow();

        NativeMethods.EnumWindows((IntPtr hWnd, IntPtr _) =>
        {
            if (hWnd == shellWindow) return true;
            if (!NativeMethods.IsWindowVisible(hWnd)) return true;
            // Only top-level, non-owned windows — a child/owned window enumerates too
            // under EnumWindows in some shell configurations and is never a sensible
            // capture target on its own.
            if (NativeMethods.GetAncestor(hWnd, NativeMethods.GA_ROOT) != hWnd) return true;

            int titleLen = NativeMethods.GetWindowTextLength(hWnd);
            if (titleLen == 0) return true;
            var sb = new StringBuilder(titleLen + 1);
            NativeMethods.GetWindowText(hWnd, sb, sb.Capacity);
            string title = sb.ToString();
            if (string.IsNullOrWhiteSpace(title)) return true;

            int exStyle = NativeMethods.GetWindowLong(hWnd, NativeMethods.GWL_EXSTYLE);
            bool isToolWindow = (exStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0
                                 && (exStyle & NativeMethods.WS_EX_APPWINDOW) == 0;
            if (isToolWindow) return true;

            // DWM-cloaked: a UWP suspended in the background, or a virtual-desktop window
            // not on the current one — visible to EnumWindows but not actually on screen,
            // so d3d11screencapturesrc would capture nothing.
            if (NativeMethods.DwmGetWindowAttribute(hWnd, NativeMethods.DWMWA_CLOAKED,
                    out int cloaked, sizeof(int)) == 0 && cloaked != 0)
            {
                return true;
            }

            NativeMethods.GetWindowRect(hWnd, out var rect);
            string? processName = null;
            try
            {
                NativeMethods.GetWindowThreadProcessId(hWnd, out uint pid);
                if (pid != 0)
                {
                    using var proc = Process.GetProcessById((int)pid);
                    processName = proc.ProcessName;
                }
            }
            catch
            {
                // Process may have exited between the enum callback and here, or be
                // access-restricted (elevated process from our non-elevated context) —
                // neither is worth failing enumeration over.
            }

            result.Add(new CaptureSource
            {
                Kind = SourceKind.Window,
                Id = hWnd.ToString(),
                Name = processName != null ? $"{title} — {processName}" : title,
                Width = rect.Right - rect.Left,
                Height = rect.Bottom - rect.Top,
                ProcessName = processName,
                WindowHandle = hWnd,
            });
            return true;
        }, IntPtr.Zero);

        return result;
    }

    public static List<CaptureSource> EnumerateAll()
    {
        var list = new List<CaptureSource>();
        list.AddRange(EnumerateMonitors());
        list.AddRange(EnumerateWindows());
        return list;
    }

    /// <summary>
    /// A small PNG thumbnail of a window via PrintWindow (works for a background/occluded
    /// window, unlike BitBlt off the screen DC) for the Tray picker. Returns null rather
    /// than throwing — a failed thumbnail should not remove the source from the picker.
    /// </summary>
    [SupportedOSPlatform("windows")]
    public static byte[]? CaptureWindowThumbnail(IntPtr hWnd, int maxWidth = 240)
    {
        try
        {
            if (!NativeMethods.GetWindowRect(hWnd, out var rect)) return null;
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0) return null;

            using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bitmap))
            {
                IntPtr hdc = g.GetHdc();
                try
                {
                    bool ok = NativeMethods.PrintWindow(hWnd, hdc, NativeMethods.PW_RENDERFULLCONTENT);
                    if (!ok) return null;
                }
                finally
                {
                    g.ReleaseHdc(hdc);
                }
            }

            float scale = Math.Min(1f, (float)maxWidth / width);
            int thumbW = Math.Max(1, (int)(width * scale));
            int thumbH = Math.Max(1, (int)(height * scale));
            using var thumb = new Bitmap(bitmap, thumbW, thumbH);
            using var ms = new MemoryStream();
            thumb.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }
        catch
        {
            return null;
        }
    }
}
