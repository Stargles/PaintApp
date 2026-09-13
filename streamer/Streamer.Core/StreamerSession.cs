using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>
/// Glue (STREAM.md §4.1): current source, pipeline lifecycle, pause when no client.
/// Owns exactly one <see cref="GstProcess"/> at a time and pushes STATUS/VIDEO to
/// every registered <see cref="IFrameSink"/> — ProtocolServer's socket today, an
/// in-process consumer tomorrow (§4.6). Nothing here is a static; a second
/// StreamerSession in the same process is legal and independent, which is what makes
/// hosting this inside the paint app later (rather than a second executable) possible.
/// </summary>
public sealed class StreamerSession : IAsyncDisposable
{
    private readonly string _gstBinDir;
    private readonly Action<string> _log;
    private readonly List<IFrameSink> _sinks = new();
    private readonly object _gate = new();

    private GstProcess? _pipeline;
    private CaptureSource? _currentSource;
    private bool _pausedByClient;
    private bool _hasClient;
    private readonly RateTracker _rate = new();
    private bool? _downloadConvertWorks; // null = not yet measured on this box (STREAM.md §8)

    public EncoderChoice? Encoder { get; private set; }
    public CaptureSource? CurrentSource
    {
        get { lock (_gate) return _currentSource; }
    }

    public bool IsStreaming
    {
        get { lock (_gate) return _pipeline != null && _pipeline.IsRunning; }
    }

    public (double fps, double kbps) CurrentRate => _rate.Snapshot();

    public StreamerSession(string gstBinDir, Action<string>? log = null)
    {
        _gstBinDir = gstBinDir;
        _log = log ?? (_ => { });
    }

    public void AddSink(IFrameSink sink)
    {
        lock (_gate) _sinks.Add(sink);
    }

    public async Task ProbeEncoderAsync(CancellationToken ct = default)
    {
        var probe = new EncoderProbe(_gstBinDir, _log);
        Encoder = await probe.ProbeAsync(ct).ConfigureAwait(false);
        _log($"StreamerSession: encoder = {Encoder.ElementName} ({Encoder.Reason})");
    }

    /// <summary>Called by ProtocolServer.ClientConnected. Starts the pipeline (unless
    /// explicitly paused) and always sends a fresh STATUS to the new client.</summary>
    public async Task OnClientConnectedAsync()
    {
        lock (_gate) _hasClient = true;
        if (_currentSource != null && !_pausedByClient)
        {
            await StartPipelineLockedAsync().ConfigureAwait(false);
        }
        BroadcastStatus();
    }

    public async Task OnClientDisconnectedAsync()
    {
        lock (_gate) _hasClient = false;
        await StopPipelineAsync().ConfigureAwait(false);
    }

    public async Task HandleControlAsync(ControlMessage control)
    {
        switch (control.Cmd)
        {
            case ControlMessage.Pause:
                _pausedByClient = true;
                await StopPipelineAsync().ConfigureAwait(false);
                BroadcastStatus("Paused by client");
                break;
            case ControlMessage.Resume:
                _pausedByClient = false;
                if (_currentSource != null) await StartPipelineLockedAsync().ConfigureAwait(false);
                BroadcastStatus();
                break;
            case ControlMessage.Keyframe:
                if (_pipeline != null)
                {
                    // Kill+relaunch is the cheapest way to force a fresh IDR (matches
                    // tools/stream/fake-streamer.py's VideoEngine.restart()).
                    await _pipeline.StopAsync().ConfigureAwait(false);
                    await _pipeline.StartAsync().ConfigureAwait(false);
                }
                BroadcastStatus();
                break;
            default:
                _log($"StreamerSession: unrecognized CONTROL cmd '{control.Cmd}', ignored");
                break;
        }
    }

    /// <summary>Restarts the pipeline on this source (STREAM.md §4.5: "picking a source
    /// restarts the pipeline and sends STATUS then a keyframe").</summary>
    public async Task SetSourceAsync(CaptureSource source)
    {
        lock (_gate) { _currentSource = source; _pausedByClient = false; }
        if (_hasClient)
        {
            await StartPipelineLockedAsync().ConfigureAwait(false);
        }
        BroadcastStatus();
    }

    private async Task StartPipelineLockedAsync()
    {
        if (Encoder == null) throw new InvalidOperationException("ProbeEncoderAsync must run before streaming");
        CaptureSource source;
        lock (_gate)
        {
            if (_currentSource == null) return;
            source = _currentSource;
        }
        await StopPipelineAsync().ConfigureAwait(false);

        bool downloadConvert = await ResolveConvertShapeAsync(source).ConfigureAwait(false);
        var pipeline = new GstProcess(
            Path.Combine(_gstBinDir, "gst-launch-1.0.exe"),
            port => PipelineBuilder.BuildCaptureArgs(source, Encoder.ElementName, port, downloadAndConvert: downloadConvert),
            _log);
        pipeline.AccessUnitReady += (_, e) =>
        {
            _rate.Note(e.Unit.Bytes.Length);
            lock (_gate)
            {
                foreach (var sink in _sinks) sink.OnVideoFrame(e.Unit.Keyframe, e.PtsUs, e.Unit.Bytes);
            }
        };
        pipeline.UnexpectedExit += (_, reason) => BroadcastStatus(reason);
        lock (_gate) _pipeline = pipeline;
        await pipeline.StartAsync().ConfigureAwait(false);
    }

    /// <summary>
    /// Measures once per process whether this laptop's WGC capture needs
    /// <c>d3d11download ! videoconvert</c> before the chosen encoder will negotiate, or
    /// takes D3D11Memory straight into <c>d3d11convert</c> (STREAM.md §8, cheaper shape
    /// preferred). Cached after the first real measurement — this is a property of the
    /// GPU/driver/encoder combination, not of which window or monitor is picked, and a
    /// smoke test costs real wall-clock time (a few seconds) that a live stream should not
    /// pay on every source switch.
    /// </summary>
    private async Task<bool> ResolveConvertShapeAsync(CaptureSource source)
    {
        if (_downloadConvertWorks.HasValue) return _downloadConvertWorks.Value;
        bool cheapWorks = await RunsCleanAsync(source, downloadAndConvert: false).ConfigureAwait(false);
        if (cheapWorks)
        {
            _log("StreamerSession: d3d11convert alone negotiates with the encoder — using the cheap shape");
            _downloadConvertWorks = false;
            return false;
        }
        bool fallbackWorks = await RunsCleanAsync(source, downloadAndConvert: true).ConfigureAwait(false);
        _log(fallbackWorks
            ? "StreamerSession: d3d11convert alone failed to negotiate; d3d11download ! videoconvert works — using that"
            : "StreamerSession: neither d3d11convert nor d3d11download ! videoconvert negotiated cleanly; " +
              "defaulting to d3d11download ! videoconvert anyway (more likely of the two to be right)");
        _downloadConvertWorks = true; // whichever branch, this is now decided for the rest of the process
        return true;
    }

    private async Task<bool> RunsCleanAsync(CaptureSource source, bool downloadAndConvert)
    {
        string args = PipelineBuilder.BuildCaptureTestArgs(source, Encoder!.ElementName, downloadAndConvert);
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = Path.Combine(_gstBinDir, "gst-launch-1.0.exe"),
                Arguments = $"-q -e {args}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            using var proc = System.Diagnostics.Process.Start(psi)!;
            bool completed = await Task.Run(() => proc.WaitForExit(8000)).ConfigureAwait(false);
            if (!completed)
            {
                try { proc.Kill(entireProcessTree: true); } catch { }
                return false;
            }
            return proc.ExitCode == 0;
        }
        catch (Exception e)
        {
            _log($"StreamerSession: convert-shape probe failed ({(downloadAndConvert ? "d3d11download+videoconvert" : "d3d11convert")}): {e.Message}");
            return false;
        }
    }

    private async Task StopPipelineAsync()
    {
        GstProcess? old;
        lock (_gate) { old = _pipeline; _pipeline = null; }
        if (old != null) await old.DisposeAsync().ConfigureAwait(false);
    }

    public void BroadcastStatus(string? reason = null)
    {
        CaptureSource? source;
        bool paused, hasClient;
        lock (_gate) { source = _currentSource; paused = _pausedByClient; hasClient = _hasClient; }
        bool streaming = source != null && !paused && IsStreaming;
        var status = new StatusMessage
        {
            Source = source == null
                ? new SourceDescriptor { Kind = "none", Name = "", Id = "" }
                : new SourceDescriptor { Kind = source.SourceKindWire, Name = source.Name, Id = source.Id },
            Width = source?.Width ?? 0,
            Height = source?.Height ?? 0,
            Fps = PipelineBuilder.TargetFps,
            Codec = "h264",
            Streaming = streaming,
            Reason = streaming ? null : (reason ?? (source == null ? "No source selected" : "Paused")),
        };
        lock (_gate)
        {
            foreach (var sink in _sinks) sink.OnStatus(status);
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopPipelineAsync().ConfigureAwait(false);
    }

    /// <summary>Parses "monitor:0" / "window:12345" — the --stream CLI switch and
    /// settings.json's lastSource spelling (STREAM.md's Streamer.Tray deliverable).</summary>
    public static bool TryParseSourceRef(string reference, out SourceKind kind, out string id)
    {
        kind = default;
        id = "";
        var parts = reference.Split(':', 2);
        if (parts.Length != 2) return false;
        switch (parts[0].ToLowerInvariant())
        {
            case "monitor": kind = SourceKind.Monitor; id = parts[1]; return true;
            case "window": kind = SourceKind.Window; id = parts[1]; return true;
            default: return false;
        }
    }

    public static CaptureSource? ResolveSourceRef(string reference)
    {
        if (!TryParseSourceRef(reference, out var kind, out var id)) return null;
        if (kind == SourceKind.Monitor)
        {
            return SourceCatalog.EnumerateMonitors().FirstOrDefault(m => m.Id == id);
        }
        return SourceCatalog.EnumerateWindows().FirstOrDefault(w => w.Id == id);
    }
}

/// <summary>fps/kbit-s over a trailing ~1s window, for the Tray status line.</summary>
internal sealed class RateTracker
{
    private readonly object _gate = new();
    private DateTime _windowStart = DateTime.UtcNow;
    private int _frames;
    private long _bytes;
    private double _lastFps;
    private double _lastKbps;

    public void Note(int byteCount)
    {
        lock (_gate)
        {
            _frames++;
            _bytes += byteCount;
            var elapsed = DateTime.UtcNow - _windowStart;
            if (elapsed.TotalSeconds >= 1.0)
            {
                _lastFps = _frames / elapsed.TotalSeconds;
                _lastKbps = (_bytes * 8 / 1000.0) / elapsed.TotalSeconds;
                _frames = 0;
                _bytes = 0;
                _windowStart = DateTime.UtcNow;
            }
        }
    }

    public (double fps, double kbps) Snapshot()
    {
        lock (_gate) return (_lastFps, _lastKbps);
    }
}
