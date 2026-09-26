using System.Text.Json;
using System.Text.Json.Serialization;

namespace Streamer.Core;

public sealed class SettingsData
{
    /// <summary>"monitor:0" or "window:12345" — the same spelling as the --stream CLI switch,
    /// so a saved setting and a CLI argument are interchangeable (StreamerSession.ParseSourceRef).</summary>
    [JsonPropertyName("lastSource")] public string? LastSource { get; set; }

    [JsonPropertyName("saveFolder")] public string? SaveFolder { get; set; }

    /// <summary>The ping-pong fix (STREAM.md §3/§6): a GUID minted once, the first time this
    /// laptop's HELLO reply needs one, and kept from then on — <see cref="Settings.GetOrCreateMachineId"/>
    /// is the only writer.</summary>
    [JsonPropertyName("machineId")] public string? MachineId { get; set; }
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

    /// <summary>
    /// **The ping-pong fix.** The laptop is one physical machine reachable under several
    /// `StreamEndpoint` spellings on the iPad's side (its Tailscale IP, its MagicDNS name, its
    /// `.ts.net` FQDN, its mDNS `.local` name) — this id is how the iPad recognizes that two of
    /// them are the same laptop rather than opening a second, redundant connection under each one
    /// (which the single-client `ProtocolServer` used to answer by evicting whichever it already
    /// had, forever). Minted once, on first use, and persisted — a fresh id on every launch would
    /// defeat the whole point, since the iPad compares HELLO to HELLO across reconnects.
    /// </summary>
    public string GetOrCreateMachineId()
    {
        var data = Load();
        if (!string.IsNullOrWhiteSpace(data.MachineId)) return data.MachineId;
        var id = Guid.NewGuid().ToString();
        data.MachineId = id;
        Save(data);
        return id;
    }

    /// <summary>%USERPROFILE%\Pictures\PaintApp (STREAM.md §4.4's default, chosen once).</summary>
    public static string DefaultSaveFolder() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "PaintApp");

    /// <summary>
    /// The save folder to use right now — re-reads the settings file every call (Load()
    /// does no caching), which is what makes "changing it takes effect without restart"
    /// (STREAM.md §7 stage 4 deliverable 2) true for free: FileInbox calls this on every
    /// FILE_BEGIN rather than capturing a folder path once at construction.
    /// </summary>
    public string ResolveSaveFolder()
    {
        var folder = Load().SaveFolder;
        return string.IsNullOrWhiteSpace(folder) ? DefaultSaveFolder() : folder;
    }
}
