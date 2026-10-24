using Streamer.Core;
using Streamer.Core.Protocol;

namespace Streamer.Tests.TestSupport;

/// <summary>An <see cref="ICapturePipeline"/> that records what the session did to it. Like the real
/// one it is "running" only once it has connected, which a test decides with <see cref="Connect"/>.</summary>
public sealed class FakePipeline : ICapturePipeline
{
    public bool IsRunning { get; private set; }
    public bool Stopped { get; private set; }
    private readonly CancellationTokenSource _lifetime = new();

    public event Func<AccessUnitEventArgs, CancellationToken, Task>? AccessUnitReady;
    public event EventHandler<string>? UnexpectedExit;
    public event EventHandler? Started;

    public Task StartAsync() => Task.CompletedTask;

    public Task StopAsync()
    {
        Stopped = true;
        _lifetime.Cancel();
        IsRunning = false;
        return Task.CompletedTask;
    }

    public ValueTask DisposeAsync() => new(StopAsync());

    /// <summary>The pipeline reaching its sink: from here on it is running.</summary>
    public void Connect()
    {
        IsRunning = true;
        Started?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>The pipeline dying on its own: it stops being "running" and says why.</summary>
    public void Fail(string reason)
    {
        IsRunning = false;
        UnexpectedExit?.Invoke(this, reason);
    }

    public async Task EmitAsync(bool keyframe, CancellationToken ct = default)
    {
        if (AccessUnitReady is not { } deliver) return;
        using var delivery = CancellationTokenSource.CreateLinkedTokenSource(ct, _lifetime.Token);
        foreach (Func<AccessUnitEventArgs, CancellationToken, Task> sink in deliver.GetInvocationList())
            await sink(new AccessUnitEventArgs
            {
                Unit = new AccessUnit { Bytes = new byte[] { 0, 0, 0, 1, 0x65 }, Keyframe = keyframe, NalTypes = new[] { 5 } },
                PtsUs = 0,
            }, delivery.Token);
    }
}

/// <summary>Builds <see cref="FakePipeline"/>s for a session and counts how many are alive. The real
/// factory spends a moment before returning (the convert-shape probe, the encoder lookup), and that
/// moment is what lets two transitions overlap — so this one yields before returning too.</summary>
public sealed class FakePipelineFactory
{
    private readonly object _gate = new();
    private readonly List<FakePipeline> _created = new();

    public IReadOnlyList<FakePipeline> Created
    {
        get { lock (_gate) return _created.ToArray(); }
    }

    /// <summary>Pipelines built and not yet stopped — the number that must never exceed one.</summary>
    public int Live => Created.Count(p => !p.Stopped);

    public async Task<ICapturePipeline> CreateAsync(CaptureSource source, CancellationToken ct = default)
    {
        await Task.Delay(15, ct).ConfigureAwait(false);
        var pipeline = new FakePipeline();
        lock (_gate) _created.Add(pipeline);
        return pipeline;
    }
}
