using Streamer.Core;
using Streamer.Core.Protocol;
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

public class FileInboxStubTests
{
    [Fact]
    public async Task AlwaysRefusesWithNotSupportedYet()
    {
        var inbox = new FileInbox();
        var result = await inbox.BeginFileAsync(new FileBeginMessage { Id = 3, Name = "x.png", Size = 10, Kind = "image" });
        Assert.Equal(3, result.Id);
        Assert.False(result.Ok);
        Assert.Equal("Not supported yet", result.Reason);
    }
}
