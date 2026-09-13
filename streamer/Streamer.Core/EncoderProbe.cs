using System.Diagnostics;

namespace Streamer.Core;

public sealed class EncoderChoice
{
    public required string ElementName { get; init; }
    public required string Reason { get; init; }
}

/// <summary>
/// Picks the encoder GStreamer element once at startup (STREAM.md §4.1/§4.2): existence
/// via <c>gst-inspect-1.0</c>, then an actual smoke pipeline, in preference order
/// nvh264enc → qsvh264enc → amfh264enc → mfh264enc → openh264enc → x264enc, falling
/// through on either check failing. The smoke test uses <c>videotestsrc</c>, not the
/// real capture source — capture negotiation (WGC, window station, D3D11 memory) is a
/// separate concern from "does this encoder run at all on this box", and conflating
/// them would misdiagnose a session problem as a missing encoder (see GstProcess and
/// the note in the stage-3 report about SSH's non-interactive window station).
/// </summary>
public sealed class EncoderProbe
{
    public static readonly string[] PreferenceOrder =
    {
        "nvh264enc", "qsvh264enc", "amfh264enc", "mfh264enc", "openh264enc", "x264enc",
    };

    private readonly string _gstBinDir;
    private readonly Action<string> _log;

    public EncoderProbe(string gstBinDir, Action<string>? log = null)
    {
        _gstBinDir = gstBinDir;
        _log = log ?? (_ => { });
    }

    public async Task<EncoderChoice> ProbeAsync(CancellationToken ct = default)
    {
        var reasons = new List<string>();
        foreach (var name in PreferenceOrder)
        {
            if (!await ElementExistsAsync(name, ct).ConfigureAwait(false))
            {
                reasons.Add($"{name}: not installed (gst-inspect-1.0 could not find it)");
                continue;
            }
            var (ok, why) = await SmokeTestAsync(name, ct).ConfigureAwait(false);
            if (ok)
            {
                _log($"EncoderProbe: chose {name} (installed; smoke pipeline ran clean). " +
                     $"Skipped: {string.Join(" | ", reasons)}");
                return new EncoderChoice
                {
                    ElementName = name,
                    Reason = reasons.Count == 0
                        ? $"first in preference order and available"
                        : $"first available and working after: {string.Join("; ", reasons)}",
                };
            }
            reasons.Add($"{name}: installed but smoke pipeline failed — {why}");
        }
        throw new InvalidOperationException(
            "EncoderProbe: no usable H.264 encoder found. " + string.Join(" | ", reasons));
    }

    private async Task<bool> ElementExistsAsync(string element, CancellationToken ct)
    {
        try
        {
            var psi = MakePsi("gst-inspect-1.0.exe", element);
            using var proc = Process.Start(psi)!;
            await proc.WaitForExitAsync(ct).ConfigureAwait(false);
            return proc.ExitCode == 0;
        }
        catch (Exception e)
        {
            _log($"EncoderProbe: gst-inspect-1.0 failed for {element}: {e.Message}");
            return false;
        }
    }

    private async Task<(bool ok, string why)> SmokeTestAsync(string element, CancellationToken ct)
    {
        string encoderArgs = PipelineBuilder.EncoderPropertiesFor(element);
        string pipeline =
            $"videotestsrc num-buffers=30 ! video/x-raw,width=640,height=360,framerate=30/1 " +
            $"! {element} {encoderArgs} ! h264parse ! fakesink";
        try
        {
            var psi = MakePsi("gst-launch-1.0.exe", $"-q {pipeline}");
            using var proc = Process.Start(psi)!;
            var completed = await Task.Run(() => proc.WaitForExit(5000), ct).ConfigureAwait(false);
            if (!completed)
            {
                try { proc.Kill(entireProcessTree: true); } catch { /* best effort */ }
                return (false, "smoke pipeline did not finish within 5s");
            }
            return proc.ExitCode == 0 ? (true, "") : (false, $"gst-launch-1.0 exited {proc.ExitCode}");
        }
        catch (Exception e)
        {
            return (false, e.Message);
        }
    }

    private ProcessStartInfo MakePsi(string exe, string args) => new()
    {
        FileName = Path.Combine(_gstBinDir, exe),
        Arguments = args,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true,
    };
}
