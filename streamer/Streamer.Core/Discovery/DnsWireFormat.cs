using System.Buffers.Binary;
using System.Text;

namespace Streamer.Core.Discovery;

/// <summary>The record types <see cref="MdnsAdvertiser"/> writes. Numeric values are the IANA
/// DNS RR type assignments — not an enum of our own devising.</summary>
public enum DnsRecordType : ushort
{
    A = 1,
    Ptr = 12,
    Txt = 16,
    Srv = 33,
}

/// <summary>Just enough hand-rolled DNS wire format (RFC 1035 names/records, no NuGet dependency
/// — see <see cref="MdnsAdvertiser"/>'s doc comment) to decode a question name out of an incoming
/// mDNS query and to write the handful of record types a DNS-SD announcement needs. Not a general
/// DNS library: no resource-record parsing beyond names, no writer-side name compression (our own
/// messages are a few records and a handful of bytes saved is not worth the bug surface).</summary>
internal static class DnsName
{
    /// <summary>Decodes one (possibly pointer-compressed) name starting at <paramref name="start"/>.
    /// Returns the dotted name and how many bytes the name occupied AT <paramref name="start"/> in
    /// the caller's stream — i.e. up to and including the terminating zero or the two-byte pointer
    /// that redirected elsewhere, never counting the bytes read after following a pointer, so a
    /// caller can find the next field (QTYPE/QCLASS) right after by simple addition.</summary>
    public static (string Name, int Consumed) Decode(byte[] buffer, int start)
    {
        var labels = new List<string>();
        int pos = start;
        int consumedAtStart = -1;
        int jumps = 0;
        while (true)
        {
            if (pos >= buffer.Length) throw new FormatException("DNS name runs past the end of the message");
            byte lengthByte = buffer[pos];
            if ((lengthByte & 0xC0) == 0xC0)
            {
                if (pos + 1 >= buffer.Length) throw new FormatException("truncated DNS name pointer");
                if (consumedAtStart == -1) consumedAtStart = (pos - start) + 2;
                if (++jumps > 20) throw new FormatException("too many DNS name pointer jumps");
                pos = ((lengthByte & 0x3F) << 8) | buffer[pos + 1];
                continue;
            }
            if (lengthByte == 0)
            {
                if (consumedAtStart == -1) consumedAtStart = (pos - start) + 1;
                break;
            }
            pos++;
            if (pos + lengthByte > buffer.Length) throw new FormatException("DNS label runs past the end of the message");
            labels.Add(Encoding.ASCII.GetString(buffer, pos, lengthByte));
            pos += lengthByte;
        }
        return (string.Join(".", labels), consumedAtStart);
    }
}

/// <summary>Appends a DNS message header plus a small number of resource records, patching each
/// record's RDLENGTH after its RDATA is written rather than requiring the caller to know the
/// length up front.</summary>
internal sealed class DnsMessageWriter
{
    private readonly List<byte> _bytes = new();

    /// <summary>ID 0, flags = response + authoritative (the conventional mDNS response header —
    /// RFC 6762 §18.1/§18.4), QDCOUNT 0 (this writer only ever emits answers, never questions).</summary>
    public void WriteHeader(ushort answerCount, ushort additionalCount)
    {
        WriteUInt16(0);      // ID
        WriteUInt16(0x8400); // flags: QR=1 (response), AA=1 (authoritative)
        WriteUInt16(0);      // QDCOUNT
        WriteUInt16(answerCount);
        WriteUInt16(0);      // NSCOUNT
        WriteUInt16(additionalCount);
    }

    /// <summary>One resource record: NAME, TYPE, CLASS (IN, with the mDNS cache-flush bit set for
    /// a unique record — SRV/TXT/A here — and clear for a shared one — PTR, which several
    /// instances may legitimately answer), TTL, then RDLENGTH/RDATA from <paramref name="writeRdata"/>.</summary>
    public void WriteRecord(string name, DnsRecordType type, bool flushCache, int ttlSeconds,
        Action<DnsMessageWriter> writeRdata)
    {
        WriteName(name);
        WriteUInt16((ushort)type);
        WriteUInt16((ushort)(0x0001 | (flushCache ? 0x8000 : 0)));
        WriteUInt32((uint)ttlSeconds);
        int lengthFieldAt = _bytes.Count;
        WriteUInt16(0); // RDLENGTH placeholder, patched below
        int rdataStart = _bytes.Count;
        writeRdata(this);
        ushort rdataLength = (ushort)(_bytes.Count - rdataStart);
        _bytes[lengthFieldAt] = (byte)(rdataLength >> 8);
        _bytes[lengthFieldAt + 1] = (byte)(rdataLength & 0xFF);
    }

    /// <summary>No compression — every name is written in full, labels then a zero terminator.</summary>
    public void WriteName(string name)
    {
        foreach (string label in name.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            byte[] bytes = Encoding.ASCII.GetBytes(label);
            if (bytes.Length > 63) throw new ArgumentException($"DNS label too long: '{label}'");
            _bytes.Add((byte)bytes.Length);
            _bytes.AddRange(bytes);
        }
        _bytes.Add(0);
    }

    public void WriteUInt16(int value)
    {
        Span<byte> b = stackalloc byte[2];
        BinaryPrimitives.WriteUInt16BigEndian(b, (ushort)value);
        _bytes.Add(b[0]);
        _bytes.Add(b[1]);
    }

    public void WriteUInt32(uint value)
    {
        Span<byte> b = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(b, value);
        _bytes.AddRange(b.ToArray());
    }

    public void WriteByte(byte value) => _bytes.Add(value);

    public void WriteBytes(byte[] bytes) => _bytes.AddRange(bytes);

    public byte[] ToArray() => _bytes.ToArray();
}
