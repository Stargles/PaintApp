using System.Buffers.Binary;
using System.Net;
using Streamer.Core.Discovery;
using Xunit;

namespace Streamer.Tests;

/// <summary>TODO (98): the pure wire-format half of <see cref="MdnsAdvertiser"/> — no socket, so
/// these run in the fast xunit tier same as everything else here. The live half (join the
/// multicast group, actually answer a query on the wire) is proved from the Mac over SSH; see
/// STREAM.md's discovery section for what that did and did not reach end to end.</summary>
public class MdnsAdvertiserTests
{
    private static byte[] Announcement() =>
        MdnsAdvertiser.BuildAnnouncement("desktop-cbr0fl6", MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain,
            "desktop-cbr0fl6", 47301, IPAddress.Parse("192.168.1.42"));

    [Fact]
    public void AnnouncementHeaderReportsOnePtrAnswerAndThreeAdditionalRecords()
    {
        byte[] msg = Announcement();
        Assert.Equal(0, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(0, 2)));      // ID
        Assert.Equal(0x8400, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(2, 2))); // response, authoritative
        Assert.Equal(0, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(4, 2)));      // QDCOUNT
        Assert.Equal(1, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(6, 2)));      // ANCOUNT: the PTR
        Assert.Equal(0, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(8, 2)));      // NSCOUNT
        Assert.Equal(3, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(10, 2)));     // ARCOUNT: SRV, TXT, A
    }

    [Fact]
    public void WithNoIPv4AddressTheAnnouncementDropsTheARecordButKeepsTheRest()
    {
        byte[] msg = MdnsAdvertiser.BuildAnnouncement("desktop-cbr0fl6", MdnsAdvertiser.ServiceType,
            MdnsAdvertiser.ServiceDomain, "desktop-cbr0fl6", 47301, ipv4: null);
        Assert.Equal(1, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(6, 2)));  // ANCOUNT
        Assert.Equal(2, BinaryPrimitives.ReadUInt16BigEndian(msg.AsSpan(10, 2))); // ARCOUNT: SRV, TXT only
    }

    [Fact]
    public void AnnouncementNamesCarryTheServiceTypeInstanceAndHostAsAsciiLabels()
    {
        byte[] msg = Announcement();
        string text = System.Text.Encoding.ASCII.GetString(msg);
        Assert.Contains("_paintstream", text);
        Assert.Contains("_tcp", text);
        Assert.Contains("desktop-cbr0fl6", text);
        Assert.Contains("local", text);
    }

    [Fact]
    public void AnnouncementCarriesThePortInTheSrvRecordAndTheAddressInTheARecord()
    {
        byte[] msg = Announcement();
        // 47301 = 0xB8C5, big-endian.
        byte[] portBytes = { (byte)(47301 >> 8), (byte)(47301 & 0xFF) };
        Assert.True(ContainsSubsequence(msg, portBytes), "expected the SRV record's big-endian port bytes");
        byte[] ip = IPAddress.Parse("192.168.1.42").GetAddressBytes();
        Assert.True(ContainsSubsequence(msg, ip), "expected the A record's address bytes");
    }

    private static bool ContainsSubsequence(byte[] haystack, byte[] needle)
    {
        for (int i = 0; i + needle.Length <= haystack.Length; i++)
        {
            bool match = true;
            for (int j = 0; j < needle.Length; j++)
            {
                if (haystack[i + j] != needle[j]) { match = false; break; }
            }
            if (match) return true;
        }
        return false;
    }

    [Fact]
    public void APtrQueryForOurServiceIsRecognized()
    {
        byte[] query = BuildQuery("_paintstream._tcp.local", qtype: 12 /* PTR */);
        Assert.True(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    [Fact]
    public void AnyQtypeForOurServiceIsRecognized_NotOnlyPtr()
    {
        byte[] query = BuildQuery("_paintstream._tcp.local", qtype: 255 /* ANY */);
        Assert.True(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    [Fact]
    public void AQueryForAnUnrelatedServiceIsNotRecognized()
    {
        byte[] query = BuildQuery("_airplay._tcp.local", qtype: 12);
        Assert.False(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    [Fact]
    public void ASecondQuestionMatchingOurServiceIsStillFound()
    {
        byte[] query = BuildQuery(new[]
        {
            ("_airplay._tcp.local", (ushort)12),
            ("_paintstream._tcp.local", (ushort)12),
        });
        Assert.True(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    // ---- The ping-pong fix's LAN half: RFC 6762 §5.4's "QU" bit (STREAM.md §6) ----

    [Fact]
    public void AnOrdinaryQuestionDoesNotRequestUnicastResponse()
    {
        byte[] query = BuildQuery("_paintstream._tcp.local", qtype: 12, unicastResponseRequested: false);
        Assert.True(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain,
            out bool requestedUnicast));
        Assert.False(requestedUnicast);
    }

    [Fact]
    public void AQuQuestionSetsTheTopBitOfQclassAndIsReportedAsRequestingUnicast()
    {
        byte[] query = BuildQuery("_paintstream._tcp.local", qtype: 12, unicastResponseRequested: true);
        Assert.True(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain,
            out bool requestedUnicast));
        Assert.True(requestedUnicast);
    }

    [Fact]
    public void TheThreeArgOverloadStillAnswersTheYesNoQuestionForAQuQuery()
    {
        // The additive overload must not change what every existing caller (this class's own
        // fixtures included) already asks.
        byte[] query = BuildQuery("_paintstream._tcp.local", qtype: 12, unicastResponseRequested: true);
        Assert.True(MdnsAdvertiser.IsPaintstreamQuery(query, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    [Theory]
    [InlineData(new byte[0])]
    [InlineData(new byte[] { 1, 2, 3 })]
    public void MalformedOrTruncatedDatagramsAreRefusedNotThrown(byte[] garbage)
    {
        Assert.False(MdnsAdvertiser.IsPaintstreamQuery(garbage, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    [Fact]
    public void ATruncatedQuestionSectionIsRefusedNotThrown()
    {
        // A well-formed 12-byte header claiming one question, but no question bytes follow.
        byte[] header = new byte[12];
        BinaryPrimitives.WriteUInt16BigEndian(header.AsSpan(4, 2), 1);
        Assert.False(MdnsAdvertiser.IsPaintstreamQuery(header, MdnsAdvertiser.ServiceType, MdnsAdvertiser.ServiceDomain));
    }

    /// <summary>A minimal DNS query datagram: header (QDCOUNT = questions.Length) then each
    /// question's name/QTYPE/QCLASS. Hand-built rather than reusing <c>DnsMessageWriter</c> (an
    /// answer writer, not a query writer) so this test fixture does not depend on the very code
    /// under test to construct its own input.</summary>
    private static byte[] BuildQuery(string name, ushort qtype, bool unicastResponseRequested = false) =>
        BuildQuery(new[] { (name, qtype) }, unicastResponseRequested);

    private static byte[] BuildQuery((string Name, ushort QType)[] questions, bool unicastResponseRequested = false)
    {
        var bytes = new List<byte>();
        void U16(int v) { bytes.Add((byte)(v >> 8)); bytes.Add((byte)(v & 0xFF)); }
        U16(0);                     // ID
        U16(0);                     // flags
        U16(questions.Length);      // QDCOUNT
        U16(0); U16(0); U16(0);     // ANCOUNT, NSCOUNT, ARCOUNT
        // RFC 6762 §5.4: the top bit of QCLASS is the "QU" unicast-response request, on top of
        // the ordinary QCLASS IN (1) below every other test here already used.
        int qclass = 1 | (unicastResponseRequested ? 0x8000 : 0);
        foreach (var (name, qtype) in questions)
        {
            foreach (string label in name.Split('.'))
            {
                var labelBytes = System.Text.Encoding.ASCII.GetBytes(label);
                bytes.Add((byte)labelBytes.Length);
                bytes.AddRange(labelBytes);
            }
            bytes.Add(0);
            U16(qtype);
            U16(qclass);
        }
        return bytes.ToArray();
    }
}
