using Streamer.Core.Protocol;

namespace Streamer.Core;

public sealed class FileReceivedEventArgs : EventArgs
{
    public required string Path { get; init; }
    public required string Name { get; init; }
    public required long Size { get; init; }
}

/// <summary>
/// Incoming (iPad → laptop) FILE_* (STREAM.md §3, §7 stage 4). One transfer in flight —
/// a second BEGIN while one is active is refused, never queued (that queueing is the
/// outbound-direction's job, <see cref="FileOutbox"/>). A BEGIN that is accepted gets NO
/// reply here: §3 says "the laptop answers after the file is closed in the save folder",
/// so <see cref="BeginFile"/> only ever returns non-null for a refusal, and the real
/// answer comes back from <see cref="EndFile"/>. A name already in the folder is never
/// overwritten — "name (2).ext", "name (3).ext", ... A short count (declared size at
/// BEGIN vs. bytes actually written) at END, any write failure, or the connection
/// dying mid-transfer (<see cref="AbortActiveTransfer"/>, called by ProtocolServer on
/// disconnect) all delete the partial file — nothing half-written is ever left behind.
/// </summary>
public sealed class FileInbox
{
    private readonly Settings _settings;
    private readonly Action<string> _log;
    private readonly object _gate = new();
    private ActiveTransfer? _active;

    public event EventHandler<FileReceivedEventArgs>? FileReceived;

    private sealed class ActiveTransfer
    {
        public required int Id;
        public required string Path;
        public required long DeclaredSize;
        public required FileStream Stream;
        public long Received;
        public string? WriteFailed;
    }

    public FileInbox(Settings settings, Action<string>? log = null)
    {
        _settings = settings;
        _log = log ?? (_ => { });
    }

    /// <summary>Called on FILE_BEGIN. Returns the refusal to send immediately, or null
    /// if accepted (no reply until the matching FILE_END).</summary>
    public FileResultMessage? BeginFile(FileBeginMessage begin)
    {
        lock (_gate)
        {
            if (_active != null)
            {
                _log($"FileInbox: FILE_BEGIN id={begin.Id} while id={_active.Id} is active, refusing");
                return Refuse(begin.Id, "A transfer is already in progress");
            }

            string folder;
            try
            {
                folder = _settings.ResolveSaveFolder();
                Directory.CreateDirectory(folder);
            }
            catch (Exception e)
            {
                _log($"FileInbox: FILE_BEGIN id={begin.Id}: cannot prepare the save folder: {e.Message}");
                return Refuse(begin.Id, e.Message);
            }

            string name = SanitizeName(begin.Name);
            FileStream stream;
            string path;
            try
            {
                stream = CreateUniqueFile(folder, name, out path);
            }
            catch (Exception e)
            {
                _log($"FileInbox: FILE_BEGIN id={begin.Id}: cannot open a file for '{name}' in {folder}: {e.Message}");
                return Refuse(begin.Id, e.Message);
            }

            _active = new ActiveTransfer { Id = begin.Id, Path = path, DeclaredSize = begin.Size, Stream = stream };
            _log($"FileInbox: FILE_BEGIN id={begin.Id} name={begin.Name} size={begin.Size} -> {path}");
            return null;
        }
    }

    /// <summary>Called on FILE_CHUNK. Bytes for an id with no active transfer (already
    /// ended, or never began) are ignored — matches tools/stream/fake-streamer.py's
    /// reference behaviour for the same case.</summary>
    public void WriteChunk(int id, ReadOnlyMemory<byte> data)
    {
        lock (_gate)
        {
            if (_active == null || _active.Id != id)
            {
                _log($"FileInbox: FILE_CHUNK id={id} with no matching active transfer, ignored");
                return;
            }
            if (_active.WriteFailed != null) return; // already broken; EndFile will report it once
            try
            {
                _active.Stream.Write(data.Span);
                _active.Received += data.Length;
            }
            catch (Exception e)
            {
                _log($"FileInbox: FILE_CHUNK id={id}: write failed: {e.Message}");
                _active.WriteFailed = e.Message;
            }
        }
    }

    /// <summary>Called on FILE_END. Returns the FileResultMessage to send, or null when
    /// the id matches no active transfer (nothing to correlate a reply to).</summary>
    public FileResultMessage? EndFile(FileEndMessage end)
    {
        ActiveTransfer finished;
        lock (_gate)
        {
            if (_active == null || _active.Id != end.Id)
            {
                _log($"FileInbox: FILE_END id={end.Id} with no matching active transfer, ignored");
                return null;
            }
            finished = _active;
            _active = null;
        }

        try { finished.Stream.Dispose(); }
        catch (Exception e) { finished.WriteFailed ??= e.Message; }

        if (finished.WriteFailed != null)
        {
            DeleteQuiet(finished.Path);
            _log($"FileInbox: FILE_END id={end.Id}: {finished.WriteFailed}; deleted the partial file");
            return new FileResultMessage { Id = end.Id, Ok = false, Reason = finished.WriteFailed };
        }

        if (finished.Received != finished.DeclaredSize)
        {
            DeleteQuiet(finished.Path);
            _log($"FileInbox: FILE_END id={end.Id}: received {finished.Received} of {finished.DeclaredSize} " +
                 "declared bytes; deleted the partial file");
            return new FileResultMessage { Id = end.Id, Ok = false, Reason = "The file arrived incomplete" };
        }

        _log($"FileInbox: FILE_END id={end.Id}: saved {finished.Received} bytes -> {finished.Path}");
        FileReceived?.Invoke(this, new FileReceivedEventArgs
        {
            Path = finished.Path,
            Name = Path.GetFileName(finished.Path),
            Size = finished.Received,
        });
        return new FileResultMessage { Id = end.Id, Ok = true };
    }

    /// <summary>Called by ProtocolServer when the connection that owned the active
    /// transfer (if any) drops before FILE_END arrives — deletes the partial file.
    /// A no-op when nothing is in flight.</summary>
    public void AbortActiveTransfer()
    {
        ActiveTransfer? aborted;
        lock (_gate) { aborted = _active; _active = null; }
        if (aborted == null) return;
        try { aborted.Stream.Dispose(); } catch { /* already broken */ }
        DeleteQuiet(aborted.Path);
        _log($"FileInbox: connection dropped mid-transfer (id={aborted.Id}); deleted the partial file {aborted.Path}");
    }

    private static FileResultMessage Refuse(int id, string reason) =>
        new() { Id = id, Ok = false, Reason = reason };

    private static void DeleteQuiet(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { /* best effort — a lingering partial is a lesser problem than throwing here */ }
    }

    private static string SanitizeName(string name)
    {
        string bare = Path.GetFileName(name); // strips any directory components, ".." included
        return string.IsNullOrWhiteSpace(bare) ? "unnamed" : bare;
    }

    /// <summary>"name.ext", "name (2).ext", "name (3).ext", ... — FileMode.CreateNew makes
    /// the exists-check-then-create race safe: if another writer wins it, this only
    /// retries on the specific "it already exists" failure, not on e.g. a full disk.</summary>
    private static FileStream CreateUniqueFile(string folder, string requestedName, out string path)
    {
        string stem = Path.GetFileNameWithoutExtension(requestedName);
        string ext = Path.GetExtension(requestedName);
        string candidateName = requestedName;
        for (int n = 2; ; n++)
        {
            path = Path.Combine(folder, candidateName);
            try
            {
                return new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
            }
            catch (IOException) when (File.Exists(path))
            {
                candidateName = $"{stem} ({n}){ext}";
            }
        }
    }
}
