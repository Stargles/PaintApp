using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

public class PipelineBuilderTests
{
    private static CaptureSource Monitor(string id = "0") => new()
    {
        Kind = SourceKind.Monitor, Id = id, Name = "Monitor 0", Width = 1920, Height = 1080, IsPrimary = true,
    };

    private static CaptureSource Window(string hwnd = "789456") => new()
    {
        Kind = SourceKind.Window, Id = hwnd, Name = "Blender", Width = 1280, Height = 720,
        WindowHandle = new IntPtr(789456),
    };

    [Theory]
    [InlineData("qsvh264enc")]
    [InlineData("mfh264enc")]
    [InlineData("nvh264enc")]
    [InlineData("amfh264enc")]
    [InlineData("openh264enc")]
    [InlineData("x264enc")]
    public void EveryKnownEncoderProducesNonEmptyProperties(string encoder)
    {
        string props = PipelineBuilder.EncoderPropertiesFor(encoder);
        Assert.False(string.IsNullOrWhiteSpace(props));
        Assert.Contains("bitrate", props);
    }

    [Fact]
    public void UnknownEncoderThrows()
    {
        Assert.Throws<ArgumentException>(() => PipelineBuilder.EncoderPropertiesFor("madeUpEncoder"));
    }

    [Fact]
    public void MonitorPipeline_UsesMonitorIndexAndTcpClientSinkToGivenPort()
    {
        string args = PipelineBuilder.BuildCaptureArgs(Monitor("2"), "qsvh264enc", loopbackPort: 54321);
        Assert.Contains("monitor-index=2", args);
        Assert.DoesNotContain("window-handle", args);
        Assert.Contains("tcpclientsink host=127.0.0.1 port=54321", args);
        Assert.Contains("h264parse config-interval=-1", args);
        Assert.Contains("stream-format=byte-stream,alignment=au", args);
        Assert.Contains("qsvh264enc low-latency=true", args);
        Assert.Contains("d3d11convert", args); // cheap shape by default
        Assert.DoesNotContain("d3d11download", args);
    }

    [Fact]
    public void WindowPipeline_UsesWindowHandleNotMonitorIndex()
    {
        string args = PipelineBuilder.BuildCaptureArgs(Window("789456"), "mfh264enc", loopbackPort: 1);
        Assert.Contains("window-handle=789456", args);
        Assert.DoesNotContain("monitor-index", args);
        Assert.Contains("mfh264enc low-latency=true", args);
        Assert.Contains("rc-mode=cbr", args);
    }

    [Fact]
    public void DownloadAndConvertFlagSwitchesTheConvertChain()
    {
        string args = PipelineBuilder.BuildCaptureArgs(Monitor(), "qsvh264enc", 1, downloadAndConvert: true);
        Assert.Contains("d3d11download ! videoconvert", args);
        Assert.DoesNotContain("! d3d11convert", args);
    }

    [Fact]
    public void ShowBorderAndShowCursorAreWired()
    {
        string args = PipelineBuilder.BuildCaptureArgs(Monitor(), "x264enc", 1, showCursor: false, showBorder: true);
        Assert.Contains("show-cursor=false", args);
        Assert.Contains("show-border=true", args);
    }

    [Fact]
    public void GopSizeIsTwoSecondsAtTargetFps()
    {
        Assert.Equal(PipelineBuilder.TargetFps * 2, PipelineBuilder.GopSizeFrames);
        Assert.Contains($"gop-size={PipelineBuilder.GopSizeFrames}", PipelineBuilder.EncoderPropertiesFor("qsvh264enc"));
    }

    [Fact]
    public void OpenH264BitrateIsBitsPerSecondNotKbit()
    {
        // openh264enc's own gst-inspect-1.0 output (read on the laptop) says bitrate is
        // "in bits per second", unlike every other encoder here which takes kbit/s —
        // this is the one PipelineBuilder must not get by copy-paste.
        string props = PipelineBuilder.EncoderPropertiesFor("openh264enc");
        Assert.Contains($"bitrate={PipelineBuilder.BitrateKbps * 1000}", props);
    }

    [Fact]
    public void TestPipelineEndsAtFakesinkNotTcpClientSink()
    {
        string args = PipelineBuilder.BuildCaptureTestArgs(Monitor(), "qsvh264enc", downloadAndConvert: false);
        Assert.Contains("fakesink", args);
        Assert.DoesNotContain("tcpclientsink", args);
        // No num-buffers: MEASURED on the laptop that d3d11screencapturesrc does not
        // reach EOS from it the way videotestsrc does (both convert-shape probes "timed
        // out" identically at the same ceiling on first real use, while the real
        // num-buffers-free capture pipeline connected and streamed within a second) —
        // see StreamerSession.RunsCleanAsync, which now bounds this probe by killing the
        // process after a fixed window instead of waiting for a natural exit.
        Assert.DoesNotContain("num-buffers", args);
    }
}
