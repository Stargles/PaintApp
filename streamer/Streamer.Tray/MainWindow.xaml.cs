using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Streamer.Core;
using Streamer.Core.Protocol;

namespace Streamer.Tray;

public sealed class SourceItemViewModel
{
    public required CaptureSource Source { get; init; }
    public required string DisplayName { get; init; }
    public required string SubText { get; init; }
    public BitmapImage? Thumbnail { get; init; }
}

/// <summary>One row in the drop box's transfer list. The window updates StatusText in
/// place as a file moves Queued -> Sending -> Inserted/Refused/Failed, rather than
/// appending a new row per state (STREAM.md §7 stage 4 deliverable 2: "a list ... shows
/// each file with its state").</summary>
public sealed class TransferRowViewModel : System.ComponentModel.INotifyPropertyChanged
{
    public string Name { get; }
    public bool Terminal { get; set; }

    private string _statusText = "Queued";
    public string StatusText
    {
        get => _statusText;
        set
        {
            if (_statusText == value) return;
            _statusText = value;
            PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(StatusText)));
        }
    }

    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;

    public TransferRowViewModel(string name) => Name = name;
}

public partial class MainWindow : Window, IFrameSink
{
    private readonly StreamerSession _session;
    private readonly ProtocolServer _server;
    private readonly Settings _settings;
    private readonly FileOutbox _fileOutbox;
    private readonly Action<string> _log;
    private readonly DispatcherTimer _rateTimer;

    private readonly System.Collections.ObjectModel.ObservableCollection<TransferRowViewModel> _transfers = new();
    private readonly Dictionary<string, TransferRowViewModel> _rowsByPath = new();

    public MainWindow(StreamerSession session, ProtocolServer server, Settings settings, FileOutbox fileOutbox,
        Action<string> log)
    {
        InitializeComponent();
        _session = session;
        _server = server;
        _settings = settings;
        _fileOutbox = fileOutbox;
        _log = log;

        _session.AddSink(this); // a second IFrameSink, purely for this window's own status/rate labels
        _fileOutbox.TransferUpdated += FileOutbox_TransferUpdated;
        TransferList.ItemsSource = _transfers;
        OutboxPathText.Text = App.OutboxDir;

        var data = _settings.Load();
        SaveFolderText.Text = data.SaveFolder ?? DefaultSaveFolder();
        EncoderText.Text = _session.Encoder != null
            ? $"Encoder: {_session.Encoder.ElementName}"
            : "Encoder: (not yet probed)";
        AddressText.Text = $"{Environment.MachineName} · {LocalTailscaleHint()}  (port {App.Port})";

        RefreshSources();

        _rateTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _rateTimer.Tick += (_, _) =>
        {
            var (fps, kbps) = _session.CurrentRate;
            RateText.Text = _session.IsStreaming ? $"{fps:0.#} fps · {kbps:0} kbit/s" : "";
        };
        _rateTimer.Start();
    }

    private static string DefaultSaveFolder() => Settings.DefaultSaveFolder();

    // ---- Drop box: drag-and-drop, Ctrl+V, and the transfer list (STREAM.md §7 stage 4
    // deliverable 2). All queueing logic lives in FileOutbox/ClipboardImageStore (Core,
    // testable); this class only translates WPF events into calls on them. ----

    // Several WPF types below (DragEventArgs, KeyEventArgs, DataFormats,
    // DragDropEffects, Key, Keyboard, ModifierKeys, Clipboard) have same-named
    // counterparts in System.Windows.Forms — UseWindowsForms=true (for
    // NotifyIcon/FolderBrowserDialog) and UseWPF=true together make the bare names
    // ambiguous (CS0104), so every one of them is spelled out in full below rather than
    // relying on which "using" wins.
    private void DropBox_DragEnter(object sender, System.Windows.DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)
            ? System.Windows.DragDropEffects.Copy
            : System.Windows.DragDropEffects.None;
        e.Handled = true;
    }

    private void DropBox_Drop(object sender, System.Windows.DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)) return;
        if (e.Data.GetData(System.Windows.DataFormats.FileDrop) is not string[] paths) return;
        foreach (var path in paths)
        {
            if (File.Exists(path)) _fileOutbox.Enqueue(path);
        }
    }

    private void Window_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != System.Windows.Input.Key.V ||
            System.Windows.Input.Keyboard.Modifiers != System.Windows.Input.ModifierKeys.Control)
        {
            return;
        }

        if (System.Windows.Clipboard.ContainsFileDropList())
        {
            var list = System.Windows.Clipboard.GetFileDropList();
            foreach (string? path in list)
            {
                if (!string.IsNullOrEmpty(path) && File.Exists(path)) _fileOutbox.Enqueue(path);
            }
            e.Handled = true;
            return;
        }

        if (System.Windows.Clipboard.ContainsImage())
        {
            BitmapSource? src = System.Windows.Clipboard.GetImage();
            if (src == null) return;
            var converted = new FormatConvertedBitmap(src, PixelFormats.Bgra32, null, 0);
            int width = converted.PixelWidth, height = converted.PixelHeight;
            if (width <= 0 || height <= 0) return;
            int stride = width * 4;
            var pixels = new byte[stride * height];
            converted.CopyPixels(pixels, stride, 0);
            string path = ClipboardImageStore.Save(App.ClipboardDir, pixels, width, height, stride);
            _log($"Tray: pasted bitmap saved to {path}");
            _fileOutbox.Enqueue(path);
            e.Handled = true;
        }
    }

    private void ClearTransfersButton_Click(object sender, RoutedEventArgs e)
    {
        _transfers.Clear();
        _rowsByPath.Clear();
    }

    private void FileOutbox_TransferUpdated(object? sender, OutboundFileEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            _rowsByPath.TryGetValue(e.Path, out var row);
            bool startingOver = e.State == OutboundFileState.Queued && e.BytesSent == 0 && (row == null || row.Terminal);
            if (startingOver)
            {
                row = new TransferRowViewModel(Path.GetFileName(e.Path));
                _rowsByPath[e.Path] = row;
                _transfers.Insert(0, row); // most recent first
            }
            if (row == null) return; // shouldn't happen — an update with no matching row and no fresh Queued
            row.StatusText = DescribeState(e);
            row.Terminal = e.State is OutboundFileState.Inserted or OutboundFileState.Refused or OutboundFileState.Failed;
        });
    }

    private static string DescribeState(OutboundFileEventArgs e) => e.State switch
    {
        OutboundFileState.Queued => e.Reason ?? "Queued",
        OutboundFileState.Sending => $"Sending… {FormatBytes(e.BytesSent)} / {FormatBytes(e.TotalBytes)}",
        OutboundFileState.Inserted => "Inserted on the iPad",
        OutboundFileState.Refused => $"Refused — {e.Reason}",
        OutboundFileState.Failed => $"Failed — {e.Reason}",
        _ => "",
    };

    private static string FormatBytes(long bytes) =>
        bytes >= 1024 * 1024 ? $"{bytes / (1024.0 * 1024.0):0.#} MB" : $"{Math.Max(0, bytes) / 1024.0:0.#} KB";

    private static string LocalTailscaleHint()
    {
        // Best-effort only — the window shows a hint, but STREAM.md's authoritative
        // address is the Tailscale IP/MagicDNS name already known at the call site
        // (100.104.85.111 / desktop-cbr0fl6); this just avoids hardcoding it twice.
        return "100.104.85.111";
    }

    private void RefreshSources()
    {
        var items = new List<SourceItemViewModel>();
        foreach (var m in SourceCatalog.EnumerateMonitors())
        {
            items.Add(new SourceItemViewModel
            {
                Source = m,
                DisplayName = m.Name,
                SubText = m.IsPrimary ? "Monitor · Primary" : "Monitor",
            });
        }
        foreach (var w in SourceCatalog.EnumerateWindows())
        {
            BitmapImage? thumb = null;
            var pngBytes = SourceCatalog.CaptureWindowThumbnail(w.WindowHandle);
            if (pngBytes != null)
            {
                thumb = new BitmapImage();
                using var ms = new MemoryStream(pngBytes);
                thumb.BeginInit();
                thumb.CacheOption = BitmapCacheOption.OnLoad;
                thumb.StreamSource = ms;
                thumb.EndInit();
                thumb.Freeze();
            }
            items.Add(new SourceItemViewModel
            {
                Source = w,
                DisplayName = w.Name,
                SubText = $"Window · {w.ProcessName ?? "unknown process"}",
                Thumbnail = thumb,
            });
        }
        SourceList.ItemsSource = items;

        var current = _session.CurrentSource;
        if (current != null)
        {
            foreach (var item in items)
            {
                if (item.Source.Kind == current.Kind && item.Source.Id == current.Id)
                {
                    SourceList.SelectedItem = item;
                    break;
                }
            }
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e) => RefreshSources();

    private async void StreamButton_Click(object sender, RoutedEventArgs e)
    {
        if (SourceList.SelectedItem is not SourceItemViewModel item) return;
        await _session.SetSourceAsync(item.Source).ConfigureAwait(true);
        var data = _settings.Load();
        data.LastSource = $"{item.Source.SourceKindWire}:{item.Source.Id}";
        _settings.Save(data);
        _log($"Tray: picked source {data.LastSource} ({item.Source.Name})");
        RefreshSources();
    }

    private void ChangeFolder_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Choose where files exported from the iPad are saved",
            SelectedPath = SaveFolderText.Text,
        };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            SaveFolderText.Text = dialog.SelectedPath;
            var data = _settings.Load();
            data.SaveFolder = dialog.SelectedPath;
            _settings.Save(data);
        }
    }

    // ---- IFrameSink: only used to keep this window's own labels current; the
    // network-facing IFrameSink is ProtocolServer, registered separately. ----

    public void OnStatus(StatusMessage status)
    {
        Dispatcher.Invoke(() =>
        {
            EncoderText.Text = _session.Encoder != null ? $"Encoder: {_session.Encoder.ElementName}" : "Encoder: (none)";
            string client = _server.HasClient ? "iPad connected" : "no client connected";
            StatusText.Text = status.Streaming
                ? $"Live — {status.Source.Name} ({status.Width}x{status.Height}) — {client}"
                : $"Not streaming — {status.Reason ?? "no reason given"} — {client}";
        });
    }

    public void OnVideoFrame(bool keyframe, ulong ptsUs, ReadOnlyMemory<byte> accessUnit)
    {
        // Rate is polled from _session.CurrentRate on the DispatcherTimer instead of
        // updated per-frame here, so a 30fps stream does not dispatch 30 UI updates/sec.
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        // App.xaml.cs's Closing handler already cancels + hides; this override exists
        // only so the rate timer does not keep firing needlessly while hidden — it's
        // cheap either way, so left running is fine. No-op override kept for clarity.
        base.OnClosing(e);
    }
}
