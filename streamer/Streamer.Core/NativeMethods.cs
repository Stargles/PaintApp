using System.Runtime.InteropServices;

namespace Streamer.Core;

/// <summary>P/Invoke surface for monitor and window enumeration (SourceCatalog) and window thumbnails.</summary>
internal static class NativeMethods
{
    public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref Rect lprcMonitor, IntPtr dwData);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MonitorInfoEx
    {
        public int cbSize;
        public Rect rcMonitor;
        public Rect rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    public const uint MONITORINFOF_PRIMARY = 0x1;
    public const int DWMWA_CLOAKED = 14;
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_APPWINDOW = 0x00040000;

    [DllImport("user32.dll")]
    public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MonitorInfoEx lpmi);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern IntPtr GetShellWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);
    public const uint GA_ROOT = 2;

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X, Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WindowPlacement
    {
        public int length;
        public int flags;
        public int showCmd;
        public Point ptMinPosition;
        public Point ptMaxPosition;
        public Rect rcNormalPosition;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowPlacement(IntPtr hWnd, ref WindowPlacement lpwndpl);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

    public const uint PW_RENDERFULLCONTENT = 0x00000002;

    // SetThreadExecutionState (STREAM.md doesn't mention this, but it has to exist:
    // this laptop's display timeout is 60s on AC power (powercfg /Q ... VIDEOIDLE),
    // and a synthetic SetCursorPos does NOT reset it the way real hardware input does
    // -- confirmed by capturing a frame with a correctly-rendered cursor over a
    // completely black desktop, minutes into a still-"streaming" session. Without
    // this, the feature's own use case ("leave the laptop running Blender and
    // rotoscope from the iPad") guarantees a black stream within a minute of the
    // artist's last physical touch on the laptop.
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);

    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_DISPLAY_REQUIRED = 0x00000002;

    // ---- STREAM.md §4.5: session-lock detection (the poll fallback) ----
    //
    // WTSRegisterSessionNotification / WM_WTSSESSION_CHANGE and
    // RegisterPowerSettingNotification / WM_POWERBROADCAST are declared in
    // Streamer.Tray/NativeInterop.cs instead of here: both need an HWND and a WndProc
    // hook, which only the WPF window has, so that plumbing belongs entirely on that side
    // of the assembly boundary (SessionLockMonitor, the thing both sides call into, stays
    // in Core and touches neither). The poll probe is different — SessionLockPoller, the
    // process that calls it, is itself Core-testable logic, so it lives here beside it.

    /// <summary>SessionLockPoller's fallback probe (STREAM.md §4.5 — "poll every 2s" for a
    /// task-launched process WM_WTSSESSION_CHANGE might never reach). True when this
    /// session's own interactive desktop is reachable, i.e. unlocked.
    ///
    /// MEASURED wrong on the laptop's real Windows 11 25H2 (2026-09-13): the commonly
    /// cited OpenInputDesktop technique (open the input desktop, fail or find a name
    /// other than "Default" means locked) reported <c>true</c> — accessible — while
    /// LogonUI.exe was confirmed running in the same session and the session confirmed
    /// locked over SSH (`query user` / `Get-Process LogonUI`), caught by
    /// App.xaml.cs's <c>--check-lock</c> diagnostic. Replaced with checking for
    /// LogonUI.exe in this process's own session instead: that is literally the process
    /// Winlogon runs to render the secure desktop for a lock, a UAC elevation prompt, or
    /// Ctrl+Alt+Del, so its presence is a direct signal rather than an inference from a
    /// desktop handle's name — simpler (no P/Invoke, no struct to get wrong) and,
    /// empirically, correct where the "official" API was not.</summary>
    public static bool IsInputDesktopAccessible()
    {
        int sessionId;
        try
        {
            sessionId = System.Diagnostics.Process.GetCurrentProcess().SessionId;
        }
        catch
        {
            return true; // can't tell -- default to accessible rather than block streaming on a read failure
        }
        foreach (var process in System.Diagnostics.Process.GetProcessesByName("LogonUI"))
        {
            using (process)
            {
                try
                {
                    if (process.SessionId == sessionId) return false;
                }
                catch
                {
                    // Exited between enumeration and the SessionId read -- not locked by it.
                }
            }
        }
        return true;
    }
}
