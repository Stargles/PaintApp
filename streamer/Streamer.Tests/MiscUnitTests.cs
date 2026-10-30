using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

public class SourceRefParsingTests
{
    [Theory]
    [InlineData("monitor:0", SourceKind.Monitor, "0")]
    [InlineData("monitor:2", SourceKind.Monitor, "2")]
    [InlineData("window:789456", SourceKind.Window, "789456")]
    public void ParsesTheCliAndSettingsSpelling(string reference, SourceKind expectedKind, string expectedId)
    {
        Assert.True(StreamerSession.TryParseSourceRef(reference, out var kind, out var id));
        Assert.Equal(expectedKind, kind);
        Assert.Equal(expectedId, id);
    }

    [Theory]
    [InlineData("")]
    [InlineData("monitor")]
    [InlineData("bogus:0")]
    [InlineData(":0")]
    public void RejectsAnythingElse(string reference)
    {
        Assert.False(StreamerSession.TryParseSourceRef(reference, out _, out _));
    }
}

public class SettingsTests
{
    [Fact]
    public void RoundTripsLastSourceAndSaveFolder()
    {
        string path = Path.Combine(Path.GetTempPath(), $"paintstreamer-settings-test-{Guid.NewGuid():N}.json");
        try
        {
            var settings = new Settings(path);
            var loaded = settings.Load();
            Assert.Null(loaded.LastSource);
            Assert.Null(loaded.SaveFolder);

            settings.Save(new SettingsData { LastSource = "window:42", SaveFolder = @"C:\Users\kevin\Pictures\PaintApp" });
            var reloaded = new Settings(path).Load();
            Assert.Equal("window:42", reloaded.LastSource);
            Assert.Equal(@"C:\Users\kevin\Pictures\PaintApp", reloaded.SaveFolder);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void MissingFileLoadsAsEmptyDefaults()
    {
        string path = Path.Combine(Path.GetTempPath(), $"paintstreamer-settings-missing-{Guid.NewGuid():N}.json");
        var loaded = new Settings(path).Load();
        Assert.Null(loaded.LastSource);
        Assert.Null(loaded.SaveFolder);
    }

    [Fact]
    public void CorruptFileLoadsAsEmptyDefaultsRatherThanThrowing()
    {
        string path = Path.Combine(Path.GetTempPath(), $"paintstreamer-settings-corrupt-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, "{ not valid json");
        try
        {
            var loaded = new Settings(path).Load();
            Assert.Null(loaded.LastSource);
        }
        finally
        {
            File.Delete(path);
        }
    }
}

// FileInbox's real (stage 4) behaviour is covered by FileInboxTests.cs — it stopped
// being a stub that always refuses "Not supported yet" once ProtocolServer got a real
// save folder to write into.

/// <summary>Real owned Windows power handles; injected exceptions happen before/after the
/// indicated native call, and do not claim the operating system itself failed that call.</summary>
public class PowerRequestTests
{
    [Fact]
    public void ReasonContextContainsTheFullNativeUnion()
    {
        Assert.Equal((IntPtr.Size == 8 ? 32 : 24, 8),
            (System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.ReasonContext>(),
             System.Runtime.InteropServices.Marshal.OffsetOf<NativeMethods.ReasonContext>("Reason").ToInt32()));
    }

    [Fact]
    public void CreateFailureDoesNotInvokeSetOrClear()
    {
        var failure = new System.ComponentModel.Win32Exception(5, "test-local create failure");
        var calls = new List<string>();
        NativeMethods.SafePowerRequestHandle? unexpected = null;
        try
        {
            var error = Record.Exception(() => unexpected = NativeMethods.AcquirePowerRequest("test",
                _ => throw failure, (_, _) => calls.Add("set"), (_, _) => calls.Add("clear")));
            Assert.Same(failure, error);
            Assert.Empty(calls);
        }
        finally { unexpected?.Dispose(); }
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ASetFailureClearsOnlyTheSuccessfullyAcquiredTypesAndClosesTheHandle(bool failSecond)
    {
        var failure = new System.ComponentModel.Win32Exception(5, "test-local set failure");
        var calls = new List<string>();
        NativeMethods.SafePowerRequestHandle? owned = null;
        try
        {
            var error = Record.Exception(() => NativeMethods.AcquirePowerRequest("test",
                reason => owned = NativeMethods.CreatePowerRequest(reason),
                (handle, type) =>
                {
                    calls.Add($"set:{type}");
                    if (!failSecond || type == NativeMethods.PowerRequestType.DisplayRequired) throw failure;
                    NativeMethods.SetPowerRequest(handle, type);
                },
                (handle, type) => { NativeMethods.ClearPowerRequest(handle, type); calls.Add($"clear:{type}"); }));
            Assert.Same(failure, error);
            Assert.Equal(failSecond
                ? new[] { "set:SystemRequired", "set:DisplayRequired", "clear:SystemRequired" }
                : new[] { "set:SystemRequired" }, calls);
            Assert.True(owned is { IsClosed: true });
        }
        finally { owned?.Dispose(); }
    }

    [Fact]
    public void ARealRequestSetsAndClearsBothTypesOnTheSameOwnedHandle()
    {
        var calls = new List<string>();
        NativeMethods.SafePowerRequestHandle? created = null;
        var owned = NativeMethods.AcquirePowerRequest("PaintStreamer native ownership test",
            reason => created = NativeMethods.CreatePowerRequest(reason),
            (handle, type) =>
            {
                NativeMethods.SetPowerRequest(handle, type);
                calls.Add($"{ReferenceEquals(created, handle)}:set:{type}");
            }, NativeMethods.ClearPowerRequest);
        try
        {
            Assert.False(owned.IsClosed || owned.IsInvalid);
            Assert.Equal(new[] { "True:set:SystemRequired", "True:set:DisplayRequired" }, calls);
            calls.Clear();
            NativeMethods.ReleasePowerRequest(owned, (handle, type) =>
            {
                NativeMethods.ClearPowerRequest(handle, type);
                calls.Add($"{ReferenceEquals(owned, handle)}:clear:{type}");
            });
            Assert.Equal(new[] { "True:clear:SystemRequired", "True:clear:DisplayRequired" }, calls);
            Assert.True(owned.IsClosed);
        }
        finally { owned.Dispose(); }
    }

    [Theory]
    [InlineData(1)]
    [InlineData(0)]
    public void AReportedClearFailureStillAttemptsTheOtherTypeAndClosesTheHandle(int failTypeValue)
    {
        var failType = (NativeMethods.PowerRequestType)failTypeValue;
        var failure = new System.ComponentModel.Win32Exception(5, "test-local failure after a real clear");
        var calls = new List<NativeMethods.PowerRequestType>();
        var owned = NativeMethods.AcquirePowerRequest("PaintStreamer clear ownership test");
        try
        {
            var error = Record.Exception(() => NativeMethods.ReleasePowerRequest(owned, (handle, type) =>
            {
                NativeMethods.ClearPowerRequest(handle, type);
                calls.Add(type);
                if (type == failType) throw failure;
            }));
            Assert.Same(failure, error);
            Assert.Equal(new[] { NativeMethods.PowerRequestType.SystemRequired, NativeMethods.PowerRequestType.DisplayRequired }, calls);
            Assert.True(owned.IsClosed);
        }
        finally { owned.Dispose(); }
    }
}
