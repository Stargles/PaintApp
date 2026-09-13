using System.IO;
using System.Windows;
using Streamer.Core;

namespace Streamer.Tray;

public partial class App : System.Windows.Application
{
    public const string AppName = "PaintStreamer";
    public const string AppVersion = "0.1.0";
    public const int Port = 47301;

    private RollingLogger? _logger;
    private StreamerSession? _session;
    private ProtocolServer? _server;
    private Settings? _settings;
    private FileInbox? _fileInbox;
    private FileOutbox? _fileOutbox;
    private OutboxFolderWatcher? _outboxWatcher;
    private System.Windows.Forms.NotifyIcon? _trayIcon;
    private MainWindow? _mainWindow;
    private SessionLockMonitor? _lockMonitor;
    private SessionLockPoller? _lockPoller;

    /// <summary>STREAM.md §7 stage 4 deliverable 3: the CLI's remote hand, since a
    /// second process (an SSH session) cannot reach the running app's own drop box.</summary>
    public static string OutboxDir => Path.Combine(AppDataDir, "outbox");

    /// <summary>Where a pasted bitmap is saved as PNG before being sent (§4.4).</summary>
    public static string ClipboardDir => Path.Combine(AppDataDir, "clipboard");

    /// <summary>
    /// %LOCALAPPDATA%\PaintStreamer, resolved by the OS for whoever this PROCESS runs
    /// as. That is correct here because by the time this code runs interactively (double
    /// -clicked, or launched by the Scheduled Task "as kevin, interactive"), the process
    /// really is kevin's. The one place that is NOT true is install-streamer.ps1, which
    /// runs as PC over SSH and would resolve %LOCALAPPDATA% to PC's own profile — which
    /// is exactly why that script uses an explicit C:\Users\kevin\AppData\Local\PaintStreamer
    /// path instead of trusting the environment variable. See its header comment.
    /// </summary>
    public static string AppDataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PaintStreamer");

    private static string GstBinDir =>
        Environment.GetEnvironmentVariable("GSTREAMER_1_0_ROOT_MSVC_X86_64") is { Length: > 0 } root
            ? Path.Combine(root, "bin")
            : @"C:\Program Files\gstreamer\1.0\msvc_x86_64\bin";

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _logger = new RollingLogger(Path.Combine(AppDataDir, "log.txt"));
        void Log(string msg) => _logger!.Log(msg);
        Log($"=== {AppName} {AppVersion} starting, args=[{string.Join(" ", e.Args)}] " +
            $"user={Environment.UserName} session={GetSessionId()} interactive={Environment.UserInteractive} ===");

        _settings = new Settings(Path.Combine(AppDataDir, "settings.json"));
        _session = new StreamerSession(GstBinDir, Log);

        string? listSourcesArg = e.Args.FirstOrDefault(a => a == "--list-sources");
        string? checkLockArg = e.Args.FirstOrDefault(a => a == "--check-lock");
        string? streamArg = e.Args.FirstOrDefault(a => a.StartsWith("--stream", StringComparison.OrdinalIgnoreCase));

        if (listSourcesArg != null)
        {
            RunListSources(Log);
            Shutdown(0);
            return;
        }

        if (checkLockArg != null)
        {
            // STREAM.md §4.5 diagnostic: prints the OpenInputDesktop poll's own verdict,
            // independent of whichever WM_WTSSESSION_CHANGE/WM_POWERBROADCAST messages
            // this same process's MainWindow may or may not have received (those go to
            // log.txt with their own "MainWindow: WM_..." / "SessionLockMonitor: ..."
            // lines; this is a one-shot answer from the poll path alone, since a session
            // one-off task has no window of its own for the message path anyway).
            var checkMonitor = new SessionLockMonitor();
            using (var checkPoller = new SessionLockPoller(checkMonitor, interval: TimeSpan.Zero))
            {
                checkPoller.Poll();
            }
            string line = $"--check-lock: IsBlocked={checkMonitor.IsBlocked} Reason={checkMonitor.Reason ?? "(none)"}";
            Console.WriteLine(line);
            Log(line);
            Shutdown(0);
            return;
        }

        if (streamArg != null)
        {
            string? reference = ExtractStreamRef(e.Args);
            if (reference == null)
            {
                Console.Error.WriteLine("--stream requires a value, e.g. --stream monitor:0 or --stream window:12345");
                Log("--stream given with no value; exiting");
                Shutdown(1);
                return;
            }
            await RunHeadlessStreamAsync(reference, Log).ConfigureAwait(true);
            return; // RunHeadlessStreamAsync only returns after being asked to shut down
        }

        // Normal windowed mode: probe the encoder, start the server, restore the last
        // source (§2.8/§6 — the laptop may reboot mid-session and should resume on its
        // own), show the tray icon and the window.
        try
        {
            await _session.ProbeEncoderAsync().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            Log($"FATAL: encoder probe failed: {ex.Message}");
            System.Windows.MessageBox.Show($"No usable H.264 encoder was found:\n{ex.Message}", AppName,
                MessageBoxButton.OK, MessageBoxImage.Error);
        }

        _fileInbox = new FileInbox(_settings, Log);
        _server = new ProtocolServer(Port, AppName, AppVersion, Environment.MachineName, _fileInbox, Log);
        _session.AddSink(_server);
        _server.ClientConnected += () => _ = _session.OnClientConnectedAsync();
        _server.ClientDisconnected += () => _ = _session.OnClientDisconnectedAsync();
        _server.ControlReceived += control => _ = _session.HandleControlAsync(control);
        await _server.StartAsync().ConfigureAwait(true);

        // STREAM.md §4.5: lock/display-off detection. The window-message half
        // (WTSRegisterSessionNotification, RegisterPowerSettingNotification) is wired up
        // in MainWindow.OnSourceInitialized once the HWND exists; the poller runs
        // regardless, from the moment the session starts, as the belt-and-suspenders
        // fallback for a process the Scheduled Task launched (§8 — the window message may
        // never arrive there) and for the startup case a message-only design cannot cover
        // (the laptop is very likely already locked when this process starts, and a
        // message only fires on the next *transition*).
        _lockMonitor = new SessionLockMonitor();
        _lockMonitor.Changed += monitor =>
        {
            Log($"SessionLockMonitor: {(monitor.IsBlocked ? "blocked" : "unblocked")}" +
                (monitor.Reason != null ? $" — {monitor.Reason}" : ""));
            _ = _session.SetEnvironmentBlockedAsync(monitor.IsBlocked, monitor.Reason);
        };
        _lockPoller = new SessionLockPoller(_lockMonitor);

        _fileOutbox = new FileOutbox(_server, Log);
        _outboxWatcher = new OutboxFolderWatcher(OutboxDir, _fileOutbox, Log);

        var lastSource = _settings.Load().LastSource;
        if (lastSource != null)
        {
            var resolved = StreamerSession.ResolveSourceRef(lastSource);
            if (resolved != null)
            {
                Log($"Resuming last source: {lastSource} -> {resolved.Name}");
                await _session.SetSourceAsync(resolved).ConfigureAwait(true);
            }
            else
            {
                Log($"Last source '{lastSource}' no longer resolves (monitor unplugged / window closed)");
            }
        }

        SetUpTrayIcon(Log);
        _fileInbox.FileReceived += (_, e) =>
        {
            // STREAM.md §7 stage 4 deliverable 2: a toast naming the file and the folder
            // it landed in, whenever an export arrives from the iPad.
            _trayIcon?.ShowBalloonTip(4000, AppName,
                $"{e.Name} saved to {Path.GetDirectoryName(e.Path)}",
                System.Windows.Forms.ToolTipIcon.Info);
        };
        _mainWindow = new MainWindow(_session, _server, _settings, _fileOutbox!, _lockMonitor, Log);
        _mainWindow.Closing += (_, args) =>
        {
            args.Cancel = true;
            _mainWindow!.Hide();
        };
        _mainWindow.Show();
    }

    private void RunListSources(Action<string> log)
    {
        var monitors = SourceCatalog.EnumerateMonitors();
        var windows = SourceCatalog.EnumerateWindows();
        log($"--list-sources: {monitors.Count} monitor(s), {windows.Count} window(s)");
        Console.WriteLine($"monitors ({monitors.Count}):");
        foreach (var m in monitors)
        {
            var line = $"  monitor:{m.Id}  {m.Name}  {m.Width}x{m.Height}{(m.IsPrimary ? "  [primary]" : "")}";
            Console.WriteLine(line);
            log(line);
        }
        Console.WriteLine($"windows ({windows.Count}):");
        foreach (var w in windows)
        {
            var line = $"  window:{w.Id}  \"{w.Name}\"  {w.Width}x{w.Height}  process={w.ProcessName}";
            Console.WriteLine(line);
            log(line);
        }
    }

    private async Task RunHeadlessStreamAsync(string reference, Action<string> log)
    {
        var source = StreamerSession.ResolveSourceRef(reference);
        if (source == null)
        {
            Console.Error.WriteLine($"--stream {reference}: source not found in the current catalog");
            log($"--stream {reference}: not found");
            Shutdown(1);
            return;
        }

        try
        {
            await _session!.ProbeEncoderAsync().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"No usable encoder: {ex.Message}");
            log($"FATAL: encoder probe failed: {ex.Message}");
            Shutdown(1);
            return;
        }

        _fileInbox = new FileInbox(_settings!, log);
        _server = new ProtocolServer(Port, AppName, AppVersion, Environment.MachineName, _fileInbox, log);
        _session.AddSink(_server);
        _server.ClientConnected += () => _ = _session.OnClientConnectedAsync();
        _server.ClientDisconnected += () => _ = _session.OnClientDisconnectedAsync();
        _server.ControlReceived += control => _ = _session.HandleControlAsync(control);
        await _server.StartAsync().ConfigureAwait(true);
        await _session.SetSourceAsync(source).ConfigureAwait(true);

        Console.WriteLine($"streaming {reference} ({source.Name}) on port {Port} — Ctrl+C or kill this process to stop");
        log($"--stream {reference}: streaming {source.Name}, no window (headless CLI mode)");

        // Headless: run forever, exactly like the windowed app's server, until the
        // process is killed (task stop / Ctrl+C). No console-reading loop — this exe is
        // a WinExe with no allocated console, so Console.ReadLine over an SSH-redirected
        // pipe would just block on EOF forever, which is what we want anyway.
        await Task.Delay(Timeout.Infinite).ConfigureAwait(true);
    }

    private static string? ExtractStreamRef(string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i].Equals("--stream", StringComparison.OrdinalIgnoreCase))
            {
                return i + 1 < args.Length ? args[i + 1] : null;
            }
            if (args[i].StartsWith("--stream=", StringComparison.OrdinalIgnoreCase))
            {
                return args[i]["--stream=".Length..];
            }
        }
        return null;
    }

    private void SetUpTrayIcon(Action<string> log)
    {
        _trayIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = AppName,
        };
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Open", null, (_, _) => { _mainWindow?.Show(); _mainWindow?.Activate(); });
        menu.Items.Add("Quit", null, (_, _) =>
        {
            log("Quit from tray menu");
            Shutdown(0);
        });
        _trayIcon.ContextMenuStrip = menu;
        _trayIcon.DoubleClick += (_, _) => { _mainWindow?.Show(); _mainWindow?.Activate(); };
    }

    private static int GetSessionId()
    {
        try { return System.Diagnostics.Process.GetCurrentProcess().SessionId; }
        catch { return -1; }
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        _lockPoller?.Dispose();
        _outboxWatcher?.Dispose();
        _fileOutbox?.Dispose();
        if (_server != null) await _server.StopAsync().ConfigureAwait(false);
        if (_session != null) await _session.DisposeAsync().ConfigureAwait(false);
        _logger?.Dispose();
        base.OnExit(e);
    }
}
