using Streamer.Core.Protocol;

namespace Streamer.Core;

/// <summary>
/// Stage-4 stub (STREAM.md §7 build order — files both ways are NOT this stage).
/// Answers every FILE_BEGIN with a clean refusal so ProtocolServer has a real seam to
/// call into today, and the stage-4 worker only has to fill in <see cref="BeginFileAsync"/>
/// (save-folder writes, FILE_CHUNK/FILE_END plumbing, the outbound "Send to Computer"
/// direction) without touching ProtocolServer's dispatch at all.
/// </summary>
public sealed class FileInbox
{
    public Task<FileResultMessage> BeginFileAsync(FileBeginMessage begin)
    {
        return Task.FromResult(new FileResultMessage
        {
            Id = begin.Id,
            Ok = false,
            Reason = "Not supported yet",
        });
    }
}
