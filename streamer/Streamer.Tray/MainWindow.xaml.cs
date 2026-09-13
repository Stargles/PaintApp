using System.ComponentModel;
using System.IO;
using System.Windows;
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

public partial class MainWindow : Window, IFrameSink
{
    private readonly StreamerSession _session;
    private readonly ProtocolServer _server;
    private readonly Settings _settings;
    private readonly Action<string> _log;
    private readonly DispatcherTimer _rateTimer;

    public MainWindow(StreamerSession session, ProtocolServer server, Settings settings, Action<string> log)
    {
        InitializeComponent();
        _session = session;
        _server = server;
        _settings = settings;
        _log = log;

        _session.AddSink(this); // a second IFrameSink, purely for this window's own status/rate labels

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

    private static string DefaultSaveFolder() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "PaintApp");

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
