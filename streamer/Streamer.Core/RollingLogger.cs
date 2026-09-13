namespace Streamer.Core;

/// <summary>
/// Appends timestamped lines to %LOCALAPPDATA%\PaintStreamer\log.txt (or wherever
/// <paramref name="path"/> points — install-streamer.ps1 uses an explicit path since
/// %LOCALAPPDATA% over an admin SSH session resolves to the wrong user's profile),
/// rotating to <c>log.txt.1</c> at 5 MB (STREAM.md §4.1/§4.3). One process writes to
/// one logger; access is serialized with a lock rather than assuming single-threaded use,
/// since GstProcess's output-drain task and the main session both log concurrently.
/// </summary>
public sealed class RollingLogger : IDisposable
{
    private const long MaxBytes = 5 * 1024 * 1024;
    private readonly string _path;
    private readonly object _gate = new();
    private StreamWriter _writer;

    public RollingLogger(string path)
    {
        _path = path;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        _writer = OpenAppend(path);
    }

    private static StreamWriter OpenAppend(string path) =>
        new(new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) { AutoFlush = true };

    public void Log(string message)
    {
        lock (_gate)
        {
            RotateIfNeededLocked();
            _writer.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}");
        }
    }

    private void RotateIfNeededLocked()
    {
        try
        {
            if (new FileInfo(_path).Length < MaxBytes) return;
        }
        catch (FileNotFoundException)
        {
            return;
        }
        _writer.Dispose();
        string rolled = _path + ".1";
        try
        {
            if (File.Exists(rolled)) File.Delete(rolled);
            File.Move(_path, rolled);
        }
        catch
        {
            // Best effort — if the rotate itself fails (e.g. sharing violation), keep
            // appending to the existing file rather than losing the ability to log at all.
        }
        _writer = OpenAppend(_path);
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _writer.Dispose();
        }
    }
}
