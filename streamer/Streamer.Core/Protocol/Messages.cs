using System.Text.Json;
using System.Text.Json.Serialization;

namespace Streamer.Core.Protocol;

// JSON payload shapes, keyed exactly as STREAM.md §3's table spells them — field
// names are the wire contract, so every property carries an explicit JsonPropertyName
// rather than relying on casing conventions that could drift under a refactor.

public sealed class HelloMessage
{
    [JsonPropertyName("proto")] public int Proto { get; set; } = 1;
    [JsonPropertyName("app")] public string App { get; set; } = "";
    [JsonPropertyName("version")] public string Version { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";

    /// <summary>The ping-pong fix (STREAM.md §3/§6): this machine's stable identity, independent of
    /// which address a connection reached it through — see <see cref="Settings.GetOrCreateMachineId"/>.
    /// Additive: a HELLO from a build that predates this field simply omits the key, and the iPad's
    /// own JSON decoder (Swift's synthesized `Decodable`, which uses `decodeIfPresent` for an
    /// `Optional` property) reads that as nil rather than failing to parse. Only <c>ProtocolServer</c>
    /// populates this; the iPad's own HELLO to the laptop does not need one.</summary>
    [JsonPropertyName("machineId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? MachineId { get; set; }
}

public sealed class SourceDescriptor
{
    [JsonPropertyName("kind")] public string Kind { get; set; } = "none"; // "monitor" | "window" | "none"
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("id")] public string Id { get; set; } = "";
}

public sealed class StatusMessage
{
    [JsonPropertyName("source")] public SourceDescriptor Source { get; set; } = new();
    [JsonPropertyName("width")] public int Width { get; set; }
    [JsonPropertyName("height")] public int Height { get; set; }
    [JsonPropertyName("fps")] public int Fps { get; set; } = 30;
    [JsonPropertyName("codec")] public string Codec { get; set; } = "h264";
    [JsonPropertyName("streaming")] public bool Streaming { get; set; }

    [JsonPropertyName("reason")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Reason { get; set; }
}

public sealed class ControlMessage
{
    [JsonPropertyName("cmd")] public string Cmd { get; set; } = "";

    public const string Pause = "pause";
    public const string Resume = "resume";
    public const string Keyframe = "keyframe";
}

public sealed class FileBeginMessage
{
    [JsonPropertyName("id")] public int Id { get; set; }
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("size")] public long Size { get; set; }
    [JsonPropertyName("kind")] public string Kind { get; set; } = "other"; // "image" | "video" | "other"
}

public sealed class FileEndMessage
{
    [JsonPropertyName("id")] public int Id { get; set; }
}

public sealed class FileResultMessage
{
    [JsonPropertyName("id")] public int Id { get; set; }
    [JsonPropertyName("ok")] public bool Ok { get; set; }

    [JsonPropertyName("reason")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Reason { get; set; }
}

/// <summary>Encode/decode helpers so call sites never touch Utf8Json directly.</summary>
public static class Json
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = null, // explicit JsonPropertyName on every property above
    };

    public static byte[] Encode<T>(T value) => JsonSerializer.SerializeToUtf8Bytes(value, Options);

    public static T Decode<T>(ReadOnlyMemory<byte> payload) =>
        JsonSerializer.Deserialize<T>(payload.Span, Options)
        ?? throw new JsonException($"payload decoded to null for {typeof(T).Name}");
}
