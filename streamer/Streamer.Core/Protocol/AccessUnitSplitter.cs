namespace Streamer.Core.Protocol;

/// <summary>One completed H.264 access unit, Annex-B byte stream (start codes kept as-is).</summary>
public sealed class AccessUnit
{
    public required byte[] Bytes { get; init; }
    public required bool Keyframe { get; init; }
    public required IReadOnlyList<int> NalTypes { get; init; }
}

/// <summary>
/// Groups Annex-B NAL units into access units, the exact rule tools/stream/fake-streamer.py's
/// Python <c>AUSplitter</c> implements (STREAM.md §3's "simpler and sufficient" version):
/// SPS/PPS/SEI/AUD attach to the FOLLOWING access unit; each VCL NAL (type 1 or 5) ends the
/// access unit it is in; every AU containing an IDR (type 5) is emitted with the last-seen
/// SPS and PPS prepended if the encoder did not already put them there.
///
/// This is a second, from-scratch port of that rule (not a shared library with the Python),
/// on purpose — Streamer.Tests/AccessUnitSplitterTests pins it against the same fixture file
/// the iPad side's logic tests already use, so a divergence between the two implementations
/// of one written rule shows up as a test failure rather than as a decode error on a real
/// device months later.
///
/// Stateful across Feed() calls, so it works identically against a live GStreamer stdout-style
/// byte stream (arbitrary chunk boundaries) and a whole file read at once.
/// </summary>
public sealed class AccessUnitSplitter
{
    private const int NalSps = 7;
    private const int NalPps = 8;
    private const int NalIdr = 5;
    private static readonly int[] NalVcl = { 1, 5 };

    private readonly List<byte> _buf = new();
    private readonly List<(int NalType, byte[] Bytes)> _pending = new();
    private readonly int _maximumAccessUnitBytes;
    private int _pendingBytes;
    public AccessUnitSplitter() : this(Frame.MaximumPayloadLength - VideoPayload.HeaderLength) { }
    internal AccessUnitSplitter(int maximumAccessUnitBytes)
    {
        if (maximumAccessUnitBytes < 1) throw new ArgumentOutOfRangeException(nameof(maximumAccessUnitBytes));
        _maximumAccessUnitBytes = maximumAccessUnitBytes;
    }

    private byte[]? _lastSps;
    private byte[]? _lastPps;

    /// <summary>Feed more bytes (or, with end:true, signal EOF) and return newly closed AUs.</summary>
    public List<AccessUnit> Feed(ReadOnlySpan<byte> data, bool end = false)
    {
        // One unfinished AU and one production read block, before making carry/parse copies.
        int batchBudget = checked(_maximumAccessUnitBytes + 65536);
        if (data.Length > batchBudget || _buf.Count > batchBudget - data.Length)
            throw new InvalidDataException("Annex-B carry exceeds the wire access-unit budget.");
        if (!data.IsEmpty)
        {
            _buf.AddRange(data.ToArray());
        }

        byte[] buf = _buf.ToArray();
        List<(int Start, int PayloadStart)> positions = FindStartCodes(buf);
        if (end)
        {
            positions.Add((buf.Length, buf.Length));
        }

        var aus = new List<AccessUnit>();
        int completedBytes = 0;
        if (positions.Count < 2)
        {
            if (end)
            {
                _buf.Clear();
            }
            return aus;
        }

        int limit = positions.Count - 1;
        for (int i = 0; i < limit; i++)
        {
            var (startIdx, payloadStart) = positions[i];
            var (nextStartIdx, _) = positions[i + 1];
            if (payloadStart >= nextStartIdx)
            {
                continue; // empty payload between two adjacent start codes
            }
            var nalBytes = buf[startIdx..nextStartIdx];
            int nalType = buf[payloadStart] & 0x1F;
            HandleNal(nalType, nalBytes, aus, ref completedBytes, batchBudget);
        }

        if (end)
        {
            _buf.Clear();
        }
        else
        {
            int keepFrom = positions[limit].Start;
            var remainder = buf[keepFrom..];
            _buf.Clear();
            _buf.AddRange(remainder);
        }

        return aus;
    }

    private void HandleNal(int nalType, byte[] nalBytes, List<AccessUnit> ausOut, ref int completedBytes, int batchBudget)
    {
        if (nalBytes.Length > _maximumAccessUnitBytes - _pendingBytes)
            throw new InvalidDataException("Annex-B assembly exceeds the wire access-unit budget.");
        if (nalType == NalSps && nalBytes.Length > _maximumAccessUnitBytes - (_lastPps?.Length ?? 0) ||
            nalType == NalPps && nalBytes.Length > _maximumAccessUnitBytes - (_lastSps?.Length ?? 0))
            throw new InvalidDataException("H.264 parameter sets exceed the wire access-unit budget.");
        _pendingBytes += nalBytes.Length;
        if (nalType == NalSps)
        {
            _lastSps = nalBytes;
        }
        else if (nalType == NalPps)
        {
            _lastPps = nalBytes;
        }
        _pending.Add((nalType, nalBytes));

        if (Array.IndexOf(NalVcl, nalType) >= 0)
        {
            var types = _pending.Select(p => p.NalType).ToList();
            bool isIdr = types.Contains(NalIdr);
            int prefixBytes = isIdr && !(types.Contains(NalSps) && types.Contains(NalPps))
                ? (_lastSps?.Length ?? 0) + (_lastPps?.Length ?? 0) : 0;
            if (prefixBytes > _maximumAccessUnitBytes - _pendingBytes)
                throw new InvalidDataException("H.264 access unit exceeds the wire payload budget.");
            int bytes = prefixBytes + _pendingBytes;
            if (bytes > batchBudget - completedBytes)
                throw new InvalidDataException("Completed access-unit batch exceeds the bounded read/carry allowance.");
            completedBytes += bytes;
            byte[] auBytes;
            if (isIdr && !(types.Contains(NalSps) && types.Contains(NalPps)))
            {
                var prefix = (_lastSps ?? Array.Empty<byte>()).Concat(_lastPps ?? Array.Empty<byte>());
                auBytes = prefix.Concat(_pending.SelectMany(p => p.Bytes)).ToArray();
            }
            else
            {
                auBytes = _pending.SelectMany(p => p.Bytes).ToArray();
            }
            ausOut.Add(new AccessUnit { Bytes = auBytes, Keyframe = isIdr, NalTypes = types });
            _pending.Clear();
            _pendingBytes = 0;
        }
    }

    /// <summary>
    /// Finds Annex-B start codes (3-byte 00 00 01, or 4-byte 00 00 00 01 folded into the
    /// same entry by stepping the start index back one byte). Returns (startIdx, payloadStart)
    /// pairs where payloadStart is the index of the NAL header byte just after the code.
    /// </summary>
    private static List<(int Start, int PayloadStart)> FindStartCodes(byte[] buf)
    {
        var positions = new List<(int, int)>();
        for (int i = 0; i + 2 < buf.Length; i++)
        {
            if (buf[i] == 0 && buf[i + 1] == 0 && buf[i + 2] == 1)
            {
                int start = i;
                if (start > 0 && buf[start - 1] == 0)
                {
                    start -= 1;
                }
                positions.Add((start, i + 3));
            }
        }
        return positions;
    }
}
