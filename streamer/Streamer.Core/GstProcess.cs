using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.ExceptionServices;
using Streamer.Core.Protocol;

namespace Streamer.Core;

public sealed class AccessUnitEventArgs : EventArgs
{
    public required AccessUnit Unit { get; init; }
    public required ulong PtsUs { get; init; }
}

/// <summary>
/// Spawns <c>gst-launch-1.0.exe -q</c> with a PipelineBuilder command line, owns the
/// ephemeral loopback TCP listener the pipeline's <c>tcpclientsink</c> connects to
/// (STREAM.md §4.1: "not stdout, which Windows may text-mode"), splits the resulting
/// Annex-B byte stream into access units with <see cref="AccessUnitSplitter"/>, and
/// restarts the pipeline with backoff if it exits while still expected to be running.
/// One GstProcess instance is one running pipeline; StreamerSession replaces it wholesale
/// on a source or encoder change rather than trying to reconfigure gst-launch in place.
/// </summary>
public sealed class GstProcess : ICapturePipeline
{
    private static readonly TimeSpan[] RestartBackoff =
    {
        TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5),
    };

    private readonly string _gstLaunchExe;
    private readonly Func<int, string> _buildArgs; // takes the bound loopback port, returns full args
    private readonly Action<string> _log;
    private readonly Func<Process, Task> _waitForExit;

    private TcpListener? _listener;
    private Process? _process;
    private CancellationTokenSource? _cts;
    private Task? _runLoop;
    private Task _readers = Task.CompletedTask;
    private CancellationTokenSource? _readerLifetime;
    private volatile bool _wantRunning;

    public event Func<AccessUnitEventArgs, CancellationToken, Task>? AccessUnitReady;
    public event EventHandler<string>? UnexpectedExit;
    // Fired once the pipeline actually connects and starts producing frames — distinct
    // from StartAsync() returning, which happens immediately and before any of that has
    // occurred. StreamerSession uses this to re-broadcast STATUS once streaming:true is
    // actually true, rather than only at the moment the client connected (when the
    // convert-shape probe or first-launch negotiation may still be running).
    public event EventHandler? Started;

    private volatile bool _isRunning;
    public bool IsRunning => _isRunning;

    public GstProcess(string gstLaunchExe, Func<int, string> buildArgs, Action<string>? log = null)
        : this(gstLaunchExe, buildArgs, log, process => process.WaitForExitAsync()) { }

    internal GstProcess(string gstLaunchExe, Func<int, string> buildArgs, Action<string>? log,
        Func<Process, Task> waitForExit)
    {
        _gstLaunchExe = gstLaunchExe;
        _buildArgs = buildArgs;
        _log = log ?? (_ => { });
        _waitForExit = waitForExit;
    }

    public Task StartAsync()
    {
        if (_wantRunning) return Task.CompletedTask;
        _wantRunning = true;
        _cts = new CancellationTokenSource();
        _runLoop = Task.Run(() => RunLoopAsync(_cts.Token));
        return Task.CompletedTask;
    }

    public async Task StopAsync()
    {
        _wantRunning = false;
        _cts?.Cancel();
        if (_runLoop != null)
        {
            try { await _runLoop.ConfigureAwait(false); } catch (OperationCanceledException) { }
        }
        _listener?.Stop();
        _listener = null;
        _isRunning = false;
    }

    private async Task RunLoopAsync(CancellationToken ct)
    {
        int attempt = 0;
        while (_wantRunning && !ct.IsCancellationRequested)
        {
            try
            {
                await RunOnceAsync(ct).ConfigureAwait(false);
                attempt = 0; // a clean run (client disconnected / we stopped it) resets backoff
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception e)
            {
                _log($"GstProcess: pipeline run failed: {e.Message}");
            }

            if (!_wantRunning || ct.IsCancellationRequested) break;

            _isRunning = false;
            UnexpectedExit?.Invoke(this, "The capture pipeline exited unexpectedly");
            var wait = RestartBackoff[Math.Min(attempt, RestartBackoff.Length - 1)];
            attempt++;
            _log($"GstProcess: restarting in {wait.TotalSeconds:0}s (attempt {attempt})");
            try { await Task.Delay(wait, ct).ConfigureAwait(false); } catch (OperationCanceledException) { throw; }
        }
    }

    /// <summary>One pipeline's life. However it ends — the client closed, the pipeline died, a read
    /// threw, we were cancelled — its process and its listener end with it: the next run replaces the
    /// fields, and a pipeline left running would keep capturing the screen for as long as the app lives.</summary>
    private async Task RunOnceAsync(CancellationToken ct)
    {
        Exception? failure = null;
        try
        {
            await StreamOnceAsync(ct).ConfigureAwait(false);
        }
        catch (Exception error) { failure = error; }
        try { await StopOwnedProcessAsync().ConfigureAwait(false); }
        catch (Exception cleanup)
        {
            failure = failure == null ? cleanup
                : new AggregateException("Capture attempt and process cleanup failed", failure, cleanup);
        }
        var listener = _listener;
        _listener = null;
        try { listener?.Stop(); }
        catch (Exception cleanup)
        {
            failure = failure == null ? cleanup
                : new AggregateException("Capture attempt and listener cleanup failed", failure, cleanup);
        }
        if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

    private async Task StreamOnceAsync(CancellationToken ct)
    {
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        int port = ((IPEndPoint)_listener.LocalEndpoint).Port;

        string args = _buildArgs(port);
        var psi = new ProcessStartInfo
        {
            FileName = _gstLaunchExe,
            Arguments = $"-q {args}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        _log($"GstProcess: launching: {_gstLaunchExe} {psi.Arguments}");

        var processExited = new TaskCompletionSource();
        // Built and wired up before Start() (rather than via the Process.Start(psi)
        // convenience overload) so there is no window between the process actually
        // starting and EnableRaisingEvents/Exited being armed — a pipeline that fails
        // to launch at all (bad gst-launch path, malformed pipeline string) can exit
        // within microseconds.
        var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.Exited += (_, _) => processExited.TrySetResult();
        try
        {
            if (!process.Start()) throw new InvalidOperationException("The capture process did not start");
        }
        catch (Exception original)
        {
            try { process.Dispose(); }
            catch (Exception cleanup) { throw new AggregateException("Capture launch and cleanup failed", original, cleanup); }
            throw;
        }
        _process = process;
        _readerLifetime = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _readers = Task.WhenAll(
            DrainStreamAsync(_process.StandardError, isError: true, _readerLifetime.Token),
            DrainStreamAsync(_process.StandardOutput, isError: false, _readerLifetime.Token));

        using var acceptCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        var acceptTask = _listener.AcceptTcpClientAsync(acceptCts.Token).AsTask();

        var first = await Task.WhenAny(acceptTask, processExited.Task).ConfigureAwait(false);
        if (first == processExited.Task)
        {
            acceptCts.Cancel();
            try { using var unused = await acceptTask.ConfigureAwait(false); } catch (OperationCanceledException) { }
            throw new InvalidOperationException(
                $"gst-launch-1.0 exited before connecting (exit code {SafeExitCode(_process)}) — " +
                "see log for its stderr");
        }

        using TcpClient client = await acceptTask.ConfigureAwait(false);
        _isRunning = true;
        var startedAt = DateTime.UtcNow;
        _log("GstProcess: pipeline connected, streaming");
        Started?.Invoke(this, EventArgs.Empty);

        var splitter = new AccessUnitSplitter();
        var buffer = new byte[65536];
        using NetworkStream ns = client.GetStream();
        while (!ct.IsCancellationRequested)
        {
            var readTask = ns.ReadAsync(buffer, ct).AsTask();
            var done = await Task.WhenAny(readTask, processExited.Task).ConfigureAwait(false);
            if (done == processExited.Task)
            {
                client.Close();
                try { await readTask.ConfigureAwait(false); } catch (Exception) { }
                throw new InvalidOperationException(
                    $"gst-launch-1.0 exited mid-stream (exit code {SafeExitCode(_process)})");
            }
            int n = await readTask.ConfigureAwait(false);
            if (n == 0) break; // pipeline closed the socket cleanly (e.g. EOS)

            foreach (var au in splitter.Feed(buffer.AsSpan(0, n)))
            {
                ct.ThrowIfCancellationRequested();
                ulong ptsUs = (ulong)(DateTime.UtcNow - startedAt).TotalMicroseconds;
                if (AccessUnitReady is { } deliver)
                    foreach (Func<AccessUnitEventArgs, CancellationToken, Task> sink in deliver.GetInvocationList())
                        await sink(new AccessUnitEventArgs { Unit = au, PtsUs = ptsUs }, ct).ConfigureAwait(false);
            }
        }
    }

    private static int SafeExitCode(Process p)
    {
        try { return p.HasExited ? p.ExitCode : -1; } catch { return -1; }
    }

    private async Task DrainStreamAsync(StreamReader reader, bool isError, CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                string? line = await reader.ReadLineAsync(ct).ConfigureAwait(false);
                if (line == null) break;
                _log($"[gst-launch{(isError ? " stderr" : "")}] {line}");
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
        catch (Exception e)
        {
            _log($"GstProcess: output drain failed: {e.Message}");
        }
    }

    private async Task StopOwnedProcessAsync()
    {
        var process = _process;
        if (process == null) return;
        _process = null;
        Exception? failure = null;
        try
        {
            try
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch (InvalidOperationException) { /* already exited */ }
                await _waitForExit(process).ConfigureAwait(false);
            }
            catch (Exception error) { failure = error; }
            try
            {
                if (await Task.WhenAny(_readers, Task.Delay(TimeSpan.FromSeconds(2))).ConfigureAwait(false) != _readers)
                {
                    _readerLifetime?.Cancel();
                    process.StandardOutput.Close(); process.StandardError.Close();
                }
                await _readers.ConfigureAwait(false);
            }
            catch (Exception cleanup)
            {
                failure = failure == null ? cleanup
                    : new AggregateException("Process exit and output cleanup failed", failure, cleanup);
            }
        }
        finally
        {
            _readerLifetime?.Dispose(); _readerLifetime = null;
            process.Dispose();
        }
        if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        _cts?.Dispose();
    }
}
