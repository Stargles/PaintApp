using System.Diagnostics;
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
    // Owns pts_us for the WHOLE connection lifetime, not per-pipeline-instance.
    // GstProcess computes its own pts relative to when ITS process started, which
    // resets to ~0 every time the pipeline is restarted (pause/resume, keyframe
    // request, source change) — found for real via stream-client-check.py's
    // --pause-after test: "pts_us went backwards: 172254 < 3262942" the instant
    // resume spun up a fresh GstProcess. STREAM.md §3 requires pts_us monotonic for
    // the connection, so StreamerSession re-stamps every access unit against this
    // Stopwatch (started once, here) instead of trusting GstProcess's own value.
    private readonly Stopwatch _sessionClock = Stopwatch.StartNew();

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
            ulong ptsUs = (ulong)_sessionClock.Elapsed.TotalMicroseconds; // see _sessionClock's doc comment
            lock (_gate)
            {
                foreach (var sink in _sinks) sink.OnVideoFrame(e.Unit.Keyframe, ptsUs, e.Unit.Bytes);
            }
        };
        pipeline.UnexpectedExit += (_, reason) => BroadcastStatus(reason);
        pipeline.Started += (_, _) => BroadcastStatus();
        lock (_gate) _pipeline = pipeline;
        await pipeline.StartAsync().ConfigureAwait(false);
        // Keep the display (and system) awake for as long as a pipeline is meant to be
        // running -- see NativeMethods.SetThreadExecutionState's doc comment for the
        // MEASURED reason this exists: a 60s AC display timeout on the laptop, and
        // SetCursorPos (unlike real hardware input) does not reset it, so the capture
        // stayed "live" while the physical display went black underneath it.
        NativeMethods.SetThreadExecutionState(
            NativeMethods.ES_CONTINUOUS | NativeMethods.ES_SYSTEM_REQUIRED | NativeMethods.ES_DISPLAY_REQUIRED);
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

    private static readonly TimeSpan ConvertShapeProbeWindow = TimeSpan.FromSeconds(3);

    private async Task<bool> RunsCleanAsync(CaptureSource source, bool downloadAndConvert)
    {
        // Unlike EncoderProbe's videotestsrc smoke test (which self-terminates cleanly
        // via num-buffers), this probe captures a LIVE, indefinite source with no
        // num-buffers (PipelineBuilder.BuildCaptureTestArgs's doc comment has the
        // measurement) — so it never exits on its own, by design. "Success" here means
        // "still alive and healthy after a few seconds", and WE kill it once that window
        // passes; ProcessRunner's TimedOut is therefore the SUCCESS path for this one
        // caller, inverted from what it means for a bounded pipeline. An early exit
        // (before the window closes) means gst-launch itself gave up — always a failure.
        string args = PipelineBuilder.BuildCaptureTestArgs(source, Encoder!.ElementName, downloadAndConvert);
        try
        {
            // Goes through ProcessRunner (not a bare Process.Start) so stdout/stderr are
            // actually drained while waiting — see its doc comment for the deadlock this
            // fixed in EncoderProbe, which used the exact same redirect-and-never-read
            // shape this probe originally copied.
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = Path.Combine(_gstBinDir, "gst-launch-1.0.exe"),
                Arguments = $"-q {args}",
            };
            var result = await ProcessRunner.RunAsync(psi, ConvertShapeProbeWindow, CancellationToken.None)
                .ConfigureAwait(false);
            if (result.TimedOut)
            {
                _log($"StreamerSession: convert-shape probe ({ShapeLabel(downloadAndConvert)}) " +
                     $"still running after {ConvertShapeProbeWindow.TotalSeconds:0}s — treating as negotiated");
                return true;
            }
            string tail = result.StdErr.Length > 300 ? result.StdErr[^300..] : result.StdErr;
            _log($"StreamerSession: convert-shape probe ({ShapeLabel(downloadAndConvert)}) exited early " +
                 $"({result.ExitCode}) within {ConvertShapeProbeWindow.TotalSeconds:0}s — treating as a negotiation failure: {tail.Trim()}");
            return false;
        }
        catch (Exception e)
        {
            _log($"StreamerSession: convert-shape probe failed ({ShapeLabel(downloadAndConvert)}): {e.Message}");
            return false;
        }
    }

    private static string ShapeLabel(bool downloadAndConvert) =>
        downloadAndConvert ? "d3d11download+videoconvert" : "d3d11convert";

    private async Task StopPipelineAsync()
    {
        GstProcess? old;
        lock (_gate) { old = _pipeline; _pipeline = null; }
        if (old != null) await old.DisposeAsync().ConfigureAwait(false);
        // Release the keep-awake request set in StartPipelineLockedAsync -- ES_CONTINUOUS
        // alone (no ES_SYSTEM_REQUIRED / ES_DISPLAY_REQUIRED) clears this thread's own
        // prior request without touching any other process's. Safe to call even if no
        // pipeline was actually running (pause with nothing picked, etc).
        NativeMethods.SetThreadExecutionState(NativeMethods.ES_CONTINUOUS);
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
            // "Paused" is reserved for an actual client-initiated pause (HandleControlAsync
            // passes that reason explicitly). The gap between a client connecting and the
            // pipeline actually producing frames — encoder negotiation, the convert-shape
            // probe on a source's first use — is a real, different, transient state and
            // reporting it as "Paused" would tell the iPad the user asked for this. Found by
            // watching a live STATUS say reason:"Paused" a full 20s into a fresh connection
            // while nothing had been paused by anyone.
            Reason = streaming ? null : (reason ?? (source == null ? "No source selected" : (paused ? "Paused" : "Starting"))),
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
