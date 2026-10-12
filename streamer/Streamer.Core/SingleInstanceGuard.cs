using System.ComponentModel;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;

namespace Streamer.Core;

/// <summary>
/// One PaintStreamer per session, and a second launch is never a silent nothing (TODO (171)). The
/// Start Menu/desktop shortcut and the triggerless on-demand Scheduled Task both launch
/// <c>Streamer.Tray.exe</c> with no arguments, so a launch while an instance is running is the
/// ordinary case, and the instance is usually hidden in the tray.
///
/// The instance is the owner of a named pipe, created with <see cref="PipeOptions.FirstPipeInstance"/>:
/// the OS refuses a second creator, and the name disappears with the process however it ends, so
/// there is no stale claim for a crashed instance to leave behind. The same pipe is the hand-off
/// channel. A second launch connects, the running instance runs its callback (the app shows its
/// window) and writes one byte back, and the second launch exits. An instance that connects but never
/// answers is hung: the pipe still names its process, which the second launch evicts and replaces.
/// </summary>
public sealed class SingleInstanceGuard : IDisposable
{
    public const string AppPipeName = "PaintStreamer.SingleInstance";

    private const byte Shown = 1;
    private const int AllowAnyProcessToForeground = -1; // ASFW_ANY

    private static readonly TimeSpan EvictionWait = TimeSpan.FromSeconds(5);

    private readonly string _name;
    private NamedPipeServerStream? _listening;
    private CancellationTokenSource? _serving;
    private Task? _acceptLoop;

    public SingleInstanceGuard(string name)
    {
        _name = name;
    }

    /// <summary>True if this guard now is the instance — no other process holds the name. False means
    /// another instance is running; the caller's job is <see cref="HandOffOrEvictAsync"/>.</summary>
    public bool TryAcquire()
    {
        try
        {
            _listening = CreateServerPipe(PipeOptions.FirstPipeInstance);
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false; // the name is taken
        }
    }

    /// <summary>The instance's side: runs <paramref name="onSecondLaunch"/> for every launch that
    /// finds it running, and tells that launch once it has completed. Every launch is answered on its
    /// own, so a callback that never returns hangs that launch and no other.</summary>
    public void ServeHandoffs(Func<Task> onSecondLaunch)
    {
        if (_listening == null) throw new InvalidOperationException("ServeHandoffs needs TryAcquire to have succeeded");
        _serving = new CancellationTokenSource();
        _acceptLoop = AcceptLoopAsync(_listening, onSecondLaunch, _serving.Token);
    }

    /// <summary>A second launch's side. Asks the running instance to show itself and returns false once it
    /// has: this launch has nothing left to do. An instance that does not answer within
    /// <paramref name="timeout"/> is killed with its capture pipeline, and this launch takes its place:
    /// returns true, and <see cref="ServeHandoffs"/> is then this launch's to call. Throws when the name is
    /// taken by a process that cannot be reached — there is nothing to ask and nothing to name.</summary>
    public async Task<bool> HandOffOrEvictAsync(TimeSpan timeout)
    {
        using var pipe = new NamedPipeClientStream(".", _name, PipeDirection.InOut, PipeOptions.Asynchronous);
        try
        {
            await pipe.ConnectAsync((int)timeout.TotalMilliseconds).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            // The instance exited between this launch finding it and asking it: nothing is left to ask.
            if (TryAcquire()) return true;
            throw new InvalidOperationException($"PaintStreamer is running but not accepting launches ('{_name}' did not answer within {timeout.TotalSeconds:0.#} s)");
        }

        // The window the instance is about to show is only allowed to come to the front by the
        // process the artist just clicked, which is this one.
        AllowSetForegroundWindow(AllowAnyProcessToForeground);
        using var giveUp = new CancellationTokenSource(timeout);
        try
        {
            if (await pipe.ReadAsync(new byte[1], giveUp.Token).ConfigureAwait(false) == 1) return false;
        }
        catch (OperationCanceledException) { }

        Evict(ServerProcessId(pipe));
        // The name is released when the OS has closed the dead process's handles, which can trail its exit.
        for (var deadline = DateTime.UtcNow + EvictionWait; !TryAcquire(); await Task.Delay(50).ConfigureAwait(false))
        {
            if (DateTime.UtcNow > deadline)
                throw new InvalidOperationException("PaintStreamer's unresponsive instance was killed but its name is still taken");
        }
        return true;
    }

    public void Dispose()
    {
        _serving?.Cancel();
        _listening?.Dispose();
        _serving?.Dispose();
        _listening = null;
        _serving = null;
    }

    private NamedPipeServerStream CreateServerPipe(PipeOptions extra) =>
        new(_name, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous | extra);

    /// <summary>Each connection is handed to its own answer before the next listener is created, so the
    /// name is never without a free instance for the next launch to find.</summary>
    private async Task AcceptLoopAsync(NamedPipeServerStream listener, Func<Task> onSecondLaunch, CancellationToken ct)
    {
        try
        {
            while (true)
            {
                await listener.WaitForConnectionAsync(ct).ConfigureAwait(false);
                var launch = listener;
                listener = CreateServerPipe(PipeOptions.None);
                _ = AnswerAsync(launch, onSecondLaunch);
            }
        }
        catch (OperationCanceledException) { }
        finally
        {
            listener.Dispose();
        }
    }

    private static async Task AnswerAsync(NamedPipeServerStream launch, Func<Task> onSecondLaunch)
    {
        using (launch)
        {
            try
            {
                await onSecondLaunch().ConfigureAwait(false);
                await launch.WriteAsync(new[] { Shown }).ConfigureAwait(false);
            }
            catch (IOException) { /* the launch gave up waiting and left */ }
        }
    }

    private static int ServerProcessId(NamedPipeClientStream pipe) =>
        GetNamedPipeServerProcessId(pipe.SafePipeHandle, out uint pid)
            ? (int)pid
            : throw new Win32Exception(Marshal.GetLastWin32Error(), "could not tell which process owns the running instance's pipe");

    /// <summary>Kills the process and the capture pipeline under it, and waits for it to be gone.</summary>
    internal static void Evict(int processId)
    {
        try
        {
            using var holder = Process.GetProcessById(processId);
            holder.Kill(entireProcessTree: true);
            if (!holder.WaitForExit(EvictionWait))
                throw new InvalidOperationException($"process {processId} did not exit within {EvictionWait.TotalSeconds:0} s of being killed");
        }
        catch (ArgumentException) { /* already gone */ }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe, out uint serverProcessId);

    [DllImport("user32.dll")]
    private static extern bool AllowSetForegroundWindow(int processId);
}
