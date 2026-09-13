using System.Text.Json;
using System.Text.Json.Serialization;

namespace Streamer.Core;

public sealed class SettingsData
{
    /// <summary>"monitor:0" or "window:12345" — the same spelling as the --stream CLI switch,
    /// so a saved setting and a CLI argument are interchangeable (StreamerSession.ParseSourceRef).</summary>
    [JsonPropertyName("lastSource")] public string? LastSource { get; set; }

    [JsonPropertyName("saveFolder")] public string? SaveFolder { get; set; }
}

/// <summary>
/// Reads/writes %LOCALAPPDATA%\PaintStreamer\settings.json (STREAM.md §4.4: the save
/// folder is "chosen once, remembered"; §2.8/§6: the last picked source is remembered
/// and auto-resumed on launch, since the laptop may reboot mid-session).
/// </summary>
public sealed class Settings
{
    private readonly string _path;
    private readonly object _gate = new();

    public Settings(string path)
    {
        _path = path;
    }

    public SettingsData Load()
    {
        lock (_gate)
        {
            try
            {
                if (!File.Exists(_path)) return new SettingsData();
                string json = File.ReadAllText(_path);
                return JsonSerializer.Deserialize<SettingsData>(json) ?? new SettingsData();
            }
            catch
            {
                // A corrupt settings file should not stop the streamer from starting —
                // just start with no last source and no chosen save folder.
                return new SettingsData();
            }
        }
    }

    public void Save(SettingsData data)
    {
        lock (_gate)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            string tmp = _path + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _path, overwrite: true);
        }
    }
}
