namespace Streamer.Core;

/// <summary>
/// One capture-and-encode pipeline as <see cref="StreamerSession"/> sees it: started once, stopped
/// once, replaced wholesale rather than reconfigured. <see cref="GstProcess"/> is the real one; the
/// interface exists so a test can count how many of them a session lets live at once.
/// </summary>
public interface ICapturePipeline : IAsyncDisposable
{
    /// <summary>True from the moment the pipeline has connected until it ends; false while it is
    /// still launching, so a pipeline that is not <see cref="IsRunning"/> has produced no access unit
    /// yet and its first one will be an IDR.</summary>
    bool IsRunning { get; }

    event EventHandler<AccessUnitEventArgs>? AccessUnitReady;
    event EventHandler<string>? UnexpectedExit;
    event EventHandler? Started;

    Task StartAsync();
    Task StopAsync();
}
