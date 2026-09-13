using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
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
public sealed class GstProcess : IAsyncDisposable
{
    private static readonly TimeSpan[] RestartBackoff =
    {
        TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5),
    };

    private readonly string _gstLaunchExe;
    private readonly Func<int, string> _buildArgs; // takes the bound loopback port, returns full args
    private readonly Action<string> _log;

    private TcpListener? _listener;
    private Process? _process;
    private CancellationTokenSource? _cts;
    private Task? _runLoop;
    private volatile bool _wantRunning;

    public event EventHandler<AccessUnitEventArgs>? AccessUnitReady;
    public event EventHandler<string>? UnexpectedExit;

    public bool IsRunning { get; private set; }

    public GstProcess(string gstLaunchExe, Func<int, string> buildArgs, Action<string>? log = null)
    {
        _gstLaunchExe = gstLaunchExe;
        _buildArgs = buildArgs;
        _log = log ?? (_ => { });
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
        KillProcessQuiet();
        _listener?.Stop();
        _listener = null;
        IsRunning = false;
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

            IsRunning = false;
            UnexpectedExit?.Invoke(this, "The capture pipeline exited unexpectedly");
            var wait = RestartBackoff[Math.Min(attempt, RestartBackoff.Length - 1)];
            attempt++;
            _log($"GstProcess: restarting in {wait.TotalSeconds:0}s (attempt {attempt})");
            try { await Task.Delay(wait, ct).ConfigureAwait(false); } catch (OperationCanceledException) { throw; }
        }
    }

    private async Task RunOnceAsync(CancellationToken ct)
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
        _process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        _process.Exited += (_, _) => processExited.TrySetResult();
        _process.Start();
        _ = DrainStreamAsync(_process.StandardError, isError: true, ct);
        _ = DrainStreamAsync(_process.StandardOutput, isError: false, ct);

        using var acceptCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        var acceptTask = _listener.AcceptTcpClientAsync(acceptCts.Token).AsTask();

        var first = await Task.WhenAny(acceptTask, processExited.Task).ConfigureAwait(false);
        if (first == processExited.Task)
        {
            acceptCts.Cancel();
            throw new InvalidOperationException(
                $"gst-launch-1.0 exited before connecting (exit code {SafeExitCode(_process)}) — " +
                "see log for its stderr");
        }

        using TcpClient client = await acceptTask.ConfigureAwait(false);
        IsRunning = true;
        var startedAt = DateTime.UtcNow;
        _log("GstProcess: pipeline connected, streaming");

        var splitter = new AccessUnitSplitter();
        var buffer = new byte[65536];
        using NetworkStream ns = client.GetStream();
        while (!ct.IsCancellationRequested)
        {
            var readTask = ns.ReadAsync(buffer, ct).AsTask();
            var done = await Task.WhenAny(readTask, processExited.Task).ConfigureAwait(false);
            if (done == processExited.Task)
            {
                throw new InvalidOperationException(
                    $"gst-launch-1.0 exited mid-stream (exit code {SafeExitCode(_process)})");
            }
            int n = await readTask.ConfigureAwait(false);
            if (n == 0) break; // pipeline closed the socket cleanly (e.g. EOS)

            foreach (var au in splitter.Feed(buffer.AsSpan(0, n)))
            {
                ulong ptsUs = (ulong)(DateTime.UtcNow - startedAt).TotalMicroseconds;
                AccessUnitReady?.Invoke(this, new AccessUnitEventArgs { Unit = au, PtsUs = ptsUs });
            }
        }

        KillProcessQuiet();
        _listener.Stop();
        _listener = null;
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

    private void KillProcessQuiet()
    {
        if (_process == null) return;
        try
        {
            if (!_process.HasExited)
            {
                _process.Kill(entireProcessTree: true);
            }
        }
        catch { /* already gone */ }
        finally
        {
            _process.Dispose();
            _process = null;
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        _cts?.Dispose();
    }
}
