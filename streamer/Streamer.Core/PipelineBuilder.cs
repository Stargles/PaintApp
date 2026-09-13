namespace Streamer.Core;

/// <summary>
/// Builds the GStreamer command line for a source + encoder (STREAM.md §4.2).
/// Low-latency knobs per encoder were read off <c>gst-inspect-1.0</c> on the laptop
/// itself (Iris Xe, GStreamer 1.26.8 MSVC): qsvh264enc and mfh264enc both confirmed
/// present with the properties used below; openh264enc and x264enc's properties were
/// also read from gst-inspect but never smoke-tested on this laptop since qsvh264enc
/// wins the preference order here.
/// </summary>
public static class PipelineBuilder
{
    public const int TargetFps = 30;
    public const int BitrateKbps = 6000; // STREAM.md §3 bandwidth target, ~6 Mbit/s CBR-ish
    public const int GopSizeFrames = TargetFps * 2; // GOP 2s per §3/§6

    /// <summary>
    /// Encoder-specific low-latency properties, gst-launch syntax (no leading/trailing space).
    /// </summary>
    public static string EncoderPropertiesFor(string element) => element switch
    {
        "qsvh264enc" => $"low-latency=true bitrate={BitrateKbps} gop-size={GopSizeFrames} rate-control=cbr",
        "mfh264enc" => $"low-latency=true bitrate={BitrateKbps} gop-size={GopSizeFrames} rc-mode=cbr",
        "nvh264enc" => $"zerolatency=true bitrate={BitrateKbps} gop-size={GopSizeFrames} rc-mode=cbr-ld-hq",
        "amfh264enc" => $"usage=low-latency bitrate={BitrateKbps} gop-size={GopSizeFrames} rate-control=cbr",
        // openh264enc's bitrate/max-bitrate are bits/sec, not kbit/s like the others.
        "openh264enc" => $"bitrate={BitrateKbps * 1000} gop-size={GopSizeFrames} rate-control=bitrate",
        // x264enc has no "low-latency" toggle; tune=zerolatency + speed-preset=ultrafast is
        // the standard low-latency recipe, and key-int-max is its GOP-size equivalent.
        "x264enc" => $"bitrate={BitrateKbps} key-int-max={GopSizeFrames} speed-preset=ultrafast tune=zerolatency",
        _ => throw new ArgumentException($"unrecognized encoder element: {element}", nameof(element)),
    };

    /// <summary>
    /// The full capture-to-loopback-TCP pipeline for a monitor or window source.
    /// <paramref name="downloadAndConvert"/> switches between the cheap
    /// <c>d3d11convert</c>-only shape and the <c>d3d11download ! videoconvert</c> shape —
    /// STREAM.md §8 flags that WGC's D3D11Memory output may not negotiate directly with
    /// every encoder; try the cheap shape first (GstProcess does), fall back if it fails.
    /// </summary>
    public static string BuildCaptureArgs(
        CaptureSource source,
        string encoderElement,
        int loopbackPort,
        bool showCursor = true,
        bool showBorder = false,
        bool downloadAndConvert = false)
    {
        string src = source.Kind == SourceKind.Monitor
            ? $"d3d11screencapturesrc capture-api=wgc monitor-index={source.Id} " +
              $"show-cursor={Bool(showCursor)} show-border={Bool(showBorder)}"
            : $"d3d11screencapturesrc capture-api=wgc window-handle={source.Id} " +
              $"show-cursor={Bool(showCursor)} show-border={Bool(showBorder)}";

        string convertChain = downloadAndConvert
            ? "d3d11download ! videoconvert"
            : "d3d11convert";

        string encoderArgs = EncoderPropertiesFor(encoderElement);

        return
            $"{src} " +
            $"! video/x-raw(memory:D3D11Memory),framerate={TargetFps}/1 ! {convertChain} " +
            $"! {encoderElement} {encoderArgs} " +
            $"! h264parse config-interval=-1 ! video/x-h264,stream-format=byte-stream,alignment=au " +
            $"! tcpclientsink host=127.0.0.1 port={loopbackPort}";
    }

    private static string Bool(bool b) => b ? "true" : "false";

    /// <summary>
    /// A short capture+encode smoke pipeline ending at fakesink, used to measure whether
    /// this laptop's WGC output needs <c>d3d11download ! videoconvert</c> before the
    /// encoder will negotiate, or accepts D3D11Memory straight into <c>d3d11convert</c>
    /// (STREAM.md §8). Runs a bounded number of buffers with <c>-e</c> so it EOSes on its
    /// own rather than needing to be killed.
    /// </summary>
    public static string BuildCaptureTestArgs(
        CaptureSource source, string encoderElement, bool downloadAndConvert)
    {
        // No num-buffers here (an earlier version had it, matching EncoderProbe's
        // videotestsrc smoke test): videotestsrc honors num-buffers and reaches a clean
        // EOS on its own, but d3d11screencapturesrc measurably does not on this laptop —
        // both convert shapes "timed out" identically at the same 10s ceiling on first
        // real use, which is the signature of a probe that never self-terminates rather
        // than two genuine negotiation failures (the real, num-buffers-free capture
        // pipeline connected and streamed within a second once StreamerSession fell
        // through to trying it anyway). So this probe is bounded by the CALLER killing
        // the process after a fixed window instead — see StreamerSession.RunsCleanAsync.
        string src = source.Kind == SourceKind.Monitor
            ? $"d3d11screencapturesrc capture-api=wgc monitor-index={source.Id}"
            : $"d3d11screencapturesrc capture-api=wgc window-handle={source.Id}";
        string convertChain = downloadAndConvert ? "d3d11download ! videoconvert" : "d3d11convert";
        string encoderArgs = EncoderPropertiesFor(encoderElement);
        return $"{src} ! video/x-raw(memory:D3D11Memory),framerate={TargetFps}/1 ! {convertChain} " +
               $"! {encoderElement} {encoderArgs} ! h264parse ! fakesink";
    }
}
