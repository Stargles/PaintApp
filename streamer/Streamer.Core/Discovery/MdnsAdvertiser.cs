using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;

namespace Streamer.Core.Discovery;

/// <summary>
/// TODO (98): a minimal, hand-rolled mDNS/DNS-SD responder — deliberately no NuGet package.
/// Streamer.Core's only third-party reference is System.Drawing.Common, for thumbnails alone;
/// Streamer.Tray's own doc comment already turned down a WPF tray-icon package in favour of
/// WinForms's built-in one for "fewer dependencies wins," and a laptop reachable only by SSH is
/// exactly the machine where an internet-dependent NuGet restore is least welcome to become a new
/// failure mode of `dotnet publish`.
///
/// Advertises `_paintstream._tcp` on the LAN (mDNS multicast 224.0.0.251:5353) under the laptop's
/// own name as the DNS-SD instance, so the iPad's `StreamDiscoveryBrowser` (`NWBrowser`) can find
/// it without the artist typing an address. The wire protocol and port are unchanged (STREAM.md
/// §3) — this only helps fill in the connect sheet's address field.
///
/// <see cref="BuildAnnouncement"/> and <see cref="IsPaintstreamQuery"/> are pure byte functions —
/// no socket, and what <c>MdnsAdvertiserTests</c> drives directly. <see cref="StartAsync"/> is the
/// live half: joins the multicast group, answers a matching query, and also sends one unsolicited
/// announcement on start (RFC 6762 §8.3), so a browser already listening sees the laptop appear
/// without waiting for its own next query.
/// </summary>
public sealed class MdnsAdvertiser : IAsyncDisposable
{
    public const string ServiceType = "_paintstream._tcp";
    public const string ServiceDomain = "local";
    private const int RecordTtlSeconds = 120;
    private static readonly IPEndPoint MulticastEndPoint = new(IPAddress.Parse("224.0.0.251"), 5353);

    private readonly string _instanceName;
    private readonly ushort _port;
    private readonly Action<string> _log;

    private UdpClient? _socket;
    private CancellationTokenSource? _cts;
    private Task? _receiveLoop;

    public MdnsAdvertiser(string instanceName, ushort port, Action<string>? log = null)
    {
        _instanceName = instanceName;
        _port = port;
        _log = log ?? (_ => { });
    }

    public async Task StartAsync()
    {
        _socket = new UdpClient();
        _socket.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        _socket.Client.Bind(new IPEndPoint(IPAddress.Any, MulticastEndPoint.Port));
        _socket.JoinMulticastGroup(MulticastEndPoint.Address);
        _cts = new CancellationTokenSource();
        _receiveLoop = Task.Run(() => ReceiveLoopAsync(_cts.Token));
        _log($"MdnsAdvertiser: advertising {_instanceName}.{ServiceType}.{ServiceDomain} on port {_port}");

        await AnnounceAsync().ConfigureAwait(false);
    }

    private async Task AnnounceAsync()
    {
        var ipv4 = LocalIPv4Address();
        if (ipv4 == null)
        {
            _log("MdnsAdvertiser: no local IPv4 address to advertise yet — skipping announcement");
            return;
        }
        byte[] announcement = BuildAnnouncement(_instanceName, ServiceType, ServiceDomain,
            Environment.MachineName, _port, ipv4);
        await SendAsync(announcement).ConfigureAwait(false);
    }

    private async Task ReceiveLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _socket!.ReceiveAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) { break; }
            catch (Exception e)
            {
                _log($"MdnsAdvertiser: receive failed: {e.Message}");
                continue;
            }

            if (!IsPaintstreamQuery(result.Buffer, ServiceType, ServiceDomain)) continue;
            try
            {
                await AnnounceAsync().ConfigureAwait(false);
            }
            catch (Exception e)
            {
                _log($"MdnsAdvertiser: failed to answer a query: {e.Message}");
            }
        }
    }

    private Task SendAsync(byte[] datagram) =>
        _socket!.SendAsync(datagram, datagram.Length, MulticastEndPoint);

    /// <summary>The laptop's first live IPv4 address — <see cref="AdmissionPolicy.LocalIPv4Subnets"/>
    /// is the one place that already enumerates NICs (TODO (98)'s other half); reusing it here
    /// keeps "what counts as a usable local address" answered in one place too.</summary>
    private static IPAddress? LocalIPv4Address() =>
        AdmissionPolicy.LocalIPv4Subnets().Select(s => s.Address).FirstOrDefault();

    public async ValueTask DisposeAsync()
    {
        _cts?.Cancel();
        _socket?.Dispose();
        if (_receiveLoop != null)
        {
            try { await _receiveLoop.ConfigureAwait(false); }
            catch { /* the receive loop's own catches already logged whatever went wrong */ }
        }
    }

    // ---- Pure wire-format functions — no socket, unit-tested directly. ----

    /// <summary>True if <paramref name="datagram"/> is a DNS message carrying a question for
    /// <c><paramref name="serviceType"/>.<paramref name="serviceDomain"/></c> (any QTYPE — a PTR
    /// browse is what NWBrowser actually sends, but matching regardless of QTYPE costs nothing
    /// and keeps this from silently going quiet against a slightly different query shape, e.g. a
    /// resolver's own TXT/SRV probe of an instance it already found). Malformed or unrelated
    /// input answers false rather than throwing — a stray multicast packet on this socket, of
    /// which there are many on a real LAN, is not this class's problem.</summary>
    public static bool IsPaintstreamQuery(byte[] datagram, string serviceType, string serviceDomain)
    {
        try
        {
            if (datagram.Length < 12) return false;
            ushort questionCount = BinaryPrimitives.ReadUInt16BigEndian(datagram.AsSpan(4, 2));
            if (questionCount == 0) return false;
            string wanted = $"{serviceType}.{serviceDomain}";
            int offset = 12;
            for (int i = 0; i < questionCount; i++)
            {
                var (name, consumed) = DnsName.Decode(datagram, offset);
                offset += consumed + 4; // + QTYPE(2) + QCLASS(2)
                if (name.Equals(wanted, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }
        catch (Exception)
        {
            // Any malformed shape (a truncated packet, a bad pointer, a corrupt length byte) is
            // "not a query we recognize", not this class's problem to throw about.
            return false;
        }
    }

    /// <summary>The full announcement: one PTR answer (<c>service.domain</c> →
    /// <c>instance.service.domain</c>) plus SRV, TXT and — when <paramref name="ipv4"/> is known
    /// — A as additional records, the conventional DNS-SD shape (RFC 6763 §4/§6.1), so a real
    /// resolver can use them without a second round trip.</summary>
    public static byte[] BuildAnnouncement(string instanceName, string serviceType, string serviceDomain,
        string hostName, ushort port, IPAddress? ipv4)
    {
        string serviceFqn = $"{serviceType}.{serviceDomain}";
        string instanceFqn = $"{instanceName}.{serviceFqn}";
        string hostFqn = $"{hostName}.{serviceDomain}";

        var writer = new DnsMessageWriter();
        writer.WriteHeader(answerCount: 1, additionalCount: (ushort)(ipv4 != null ? 3 : 2));

        writer.WriteRecord(serviceFqn, DnsRecordType.Ptr, flushCache: false, ttlSeconds: RecordTtlSeconds,
            writeRdata: rdata => rdata.WriteName(instanceFqn));

        writer.WriteRecord(instanceFqn, DnsRecordType.Srv, flushCache: true, ttlSeconds: RecordTtlSeconds,
            writeRdata: rdata =>
        {
            rdata.WriteUInt16(0); // priority
            rdata.WriteUInt16(0); // weight
            rdata.WriteUInt16(port);
            rdata.WriteName(hostFqn);
        });

        writer.WriteRecord(instanceFqn, DnsRecordType.Txt, flushCache: true, ttlSeconds: RecordTtlSeconds,
            writeRdata: rdata => rdata.WriteByte(0)); // one zero-length string: no key/value pairs to carry yet

        if (ipv4 != null)
        {
            writer.WriteRecord(hostFqn, DnsRecordType.A, flushCache: true, ttlSeconds: RecordTtlSeconds,
                writeRdata: rdata => rdata.WriteBytes(ipv4.GetAddressBytes()));
        }

        return writer.ToArray();
    }
}
