using System.Runtime.InteropServices;

namespace Streamer.Tray;

/// <summary>
/// P/Invoke surface for the two window-message notifications MainWindow forwards into a
/// <see cref="Streamer.Core.SessionLockMonitor"/> (STREAM.md §4.5). Kept in Streamer.Tray
/// rather than Streamer.Core's own NativeMethods because both APIs are inherently
/// window-bound — registration takes an HWND and delivery is a WndProc message — so this
/// is exactly the "WPF layer only forwards the window message" plumbing the design calls
/// for; SessionLockMonitor itself never references a window handle or either DLL.
/// </summary>
internal static class NativeInterop
{
    // ---- WTSRegisterSessionNotification / WM_WTSSESSION_CHANGE ----

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSRegisterSessionNotification(IntPtr hWnd, uint dwFlags);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSUnRegisterSessionNotification(IntPtr hWnd);

    public const uint NOTIFY_FOR_THIS_SESSION = 0;
    public const int WM_WTSSESSION_CHANGE = 0x02B1;
    public const int WTS_CONSOLE_CONNECT = 0x1;
    public const int WTS_CONSOLE_DISCONNECT = 0x2;
    public const int WTS_SESSION_LOCK = 0x7;
    public const int WTS_SESSION_UNLOCK = 0x8;

    // ---- RegisterPowerSettingNotification / WM_POWERBROADCAST, GUID_CONSOLE_DISPLAY_STATE ----

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid powerSettingGuid, int flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterPowerSettingNotification(IntPtr handle);

    public const int DEVICE_NOTIFY_WINDOW_HANDLE = 0x00000000;
    public const int WM_POWERBROADCAST = 0x0218;
    public const int PBT_POWERSETTINGCHANGE = 0x8013;

    /// <summary>Data is 0 (off), 1 (on) or 2 (dimmed — still capturable, treated as on).</summary>
    public static readonly Guid GUID_CONSOLE_DISPLAY_STATE = new("6FE69556-704A-47A0-8F24-C28D936FDA47");

    [StructLayout(LayoutKind.Sequential)]
    public struct POWERBROADCAST_SETTING
    {
        public Guid PowerSetting;
        public int DataLength;
        public byte Data; // first byte of a variable-length trailing array; DataLength is 1 for this GUID
    }
}
