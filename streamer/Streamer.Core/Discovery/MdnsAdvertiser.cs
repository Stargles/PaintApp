using System.Buffers.Binary;
using System.Net;
using System.Net.NetworkInformation;
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
        // **Found live on the laptop, 2026-09-25: Windows already runs its own mDNS responder
        // (Dnscache) bound to UDP 5353.** `ExclusiveAddressUse` must be false *before* `Bind()` —
        // setting it after throws — or that bind can fail outright, or (worse, and observed)
        // silently succeed while `SO_EXCLUSIVEADDRUSE` still blocks this socket from ever seeing
        // multicast datagrams another socket on the same port already claimed. Both this and
        // `ReuseAddress` are needed; Windows treats them as a pair, not either-or.
        _socket.ExclusiveAddressUse = false;
        _socket.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        _socket.Client.Bind(new IPEndPoint(IPAddress.Any, MulticastEndPoint.Port));
        JoinMulticastOnEveryInterface();
        _cts = new CancellationTokenSource();
        _receiveLoop = Task.Run(() => ReceiveLoopAsync(_cts.Token));
        _log($"MdnsAdvertiser: advertising {_instanceName}.{ServiceType}.{ServiceDomain} on port {_port}");

        await AnnounceAsync().ConfigureAwait(false);
    }

    /// <summary>**Found live on the laptop, 2026-09-25.** `JoinMulticastGroup(IPAddress)` — the
    /// single-argument overload this used to call — joins on whichever interface the OS treats as
    /// the *default route* for that address family, which is not necessarily the Wi-Fi/Ethernet NIC
    /// the iPad's query actually arrives on: a laptop running the Tailscale client has at least one
    /// extra virtual adapter, and either it or an unrelated one can hold the lower route metric.
    /// Joining on every "Up" IPv4-capable interface, by its own local address, is what makes this
    /// socket receive a multicast query regardless of which physical or virtual NIC it lands on —
    /// an interface that cannot join (some virtual adapters refuse `IP_ADD_MEMBERSHIP` outright)
    /// just logs and is skipped, since one NIC's own limitation must not stop advertising on every
    /// other one.
    ///
    /// **`JoinMulticastGroup(int ifindex, IPAddress)` — tried first and reverted — is IPv6-only**:
    /// against this laptop's own two live NICs (Wi-Fi, Tailscale) it failed both with "The attempted
    /// operation is not supported for the type of object referenced," on an IPv4 `UdpClient`, every
    /// time, which is .NET's own message for calling an IPv6-shaped socket option on an IPv4 socket.
    /// `JoinMulticastGroup(IPAddress multicastAddr, IPAddress localAddress)` is the IPv4 overload
    /// that names a specific interface — by its local address, not an index.</summary>
    private void JoinMulticastOnEveryInterface()
    {
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            if (!nic.Supports(NetworkInterfaceComponent.IPv4)) continue;
            foreach (var unicast in SafeUnicastAddresses(nic))
            {
                if (unicast.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                try
                {
                    _socket!.JoinMulticastGroup(MulticastEndPoint.Address, unicast.Address);
                }
                catch (Exception e)
                {
                    _log($"MdnsAdvertiser: could not join the multicast group on '{nic.Name}' " +
                         $"({unicast.Address}): {e.Message}");
                }
            }
        }
    }

    private static IEnumerable<UnicastIPAddressInformation> SafeUnicastAddresses(NetworkInterface nic)
    {
        try
        {
            return nic.GetIPProperties().UnicastAddresses;
        }
        catch (Exception)
        {
            // Some virtual adapters throw reading IP properties at all rather than answering an
            // empty list — same as an interface with nothing to offer, just discovered the hard way.
            return Array.Empty<UnicastIPAddressInformation>();
        }
    }

    /// <summary>Sends the announcement to <paramref name="unicastTo"/> when given — RFC 6762 §5.4's
    /// "QU" reply, for a querier that asked for one directly rather than waiting on the multicast
    /// group — or to the multicast group otherwise (an unsolicited announcement, or an ordinary
    /// query that did not request unicast).</summary>
    private bool _loggedChosenAddress;

    private async Task AnnounceAsync(IPEndPoint? unicastTo = null)
    {
        var ipv4 = LocalIPv4Address();
        if (ipv4 == null)
        {
            _log("MdnsAdvertiser: no local IPv4 address to advertise yet — skipping announcement");
            return;
        }
        if (!_loggedChosenAddress)
        {
            // Once, not per-announcement: this is exactly the fact 2026-09-25's LAN investigation
            // needed and could not previously read off anything — which address this laptop is
            // telling the iPad to connect to, distinct from the port-listening log line above,
            // which never named it.
            _log($"MdnsAdvertiser: A record will carry {ipv4}");
            _loggedChosenAddress = true;
        }
        byte[] announcement = BuildAnnouncement(_instanceName, ServiceType, ServiceDomain,
            Environment.MachineName, _port, ipv4);
        await SendAsync(announcement, unicastTo).ConfigureAwait(false);
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

            if (!IsPaintstreamQuery(result.Buffer, ServiceType, ServiceDomain, out bool requestedUnicast)) continue;
            try
            {
                // RFC 6762 §5.4: a "QU" question asks to be answered directly, unicast, rather than
                // through the multicast group — `NWBrowser`'s first query after a browse starts is
                // commonly one, wanting a fast answer rather than whatever suppression/aggregation
                // delay a multicast responder might apply.
                await AnnounceAsync(requestedUnicast ? result.RemoteEndPoint : null).ConfigureAwait(false);
            }
            catch (Exception e)
            {
                _log($"MdnsAdvertiser: failed to answer a query: {e.Message}");
            }
        }
    }

    private Task SendAsync(byte[] datagram, IPEndPoint? unicastTo = null) =>
        _socket!.SendAsync(datagram, datagram.Length, unicastTo ?? MulticastEndPoint);

    /// <summary>**Found live on the laptop, 2026-09-25: the address that used to land in the A
    /// record was whichever NIC `AdmissionPolicy.LocalIPv4Subnets()` happened to enumerate first**
    /// — deliberately unordered there, because that method exists to check a *remote* address
    /// against every subnet the laptop might be reached on, Tailscale-adjacent adapters included.
    /// Here the requirement is the opposite: one specific address a plain-Wi-Fi iPad, with no
    /// Tailscale involved, can actually route to. Prefers a private (RFC1918) address on a real
    /// Ethernet/Wi-Fi adapter, explicitly skipping Tailscale's own virtual adapter by name — advertising
    /// its address would hand back the one address this LAN-only discovery path is not using
    /// Tailscale to reach in the first place — and falls back to whatever is left rather than
    /// advertising nothing, the same tolerance the admission check gives itself.</summary>
    internal static IPAddress? LocalIPv4Address()
    {
        IPAddress? fallback = null;
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            if (nic.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
            if (nic.Name.Contains("Tailscale", StringComparison.OrdinalIgnoreCase)) continue;
            if (nic.Description.Contains("Tailscale", StringComparison.OrdinalIgnoreCase)) continue;
            bool isOrdinaryLanAdapter = nic.NetworkInterfaceType is NetworkInterfaceType.Ethernet
                or NetworkInterfaceType.Wireless80211 or NetworkInterfaceType.GigabitEthernet
                or NetworkInterfaceType.FastEthernetT or NetworkInterfaceType.FastEthernetFx;
            foreach (var unicast in SafeUnicastAddresses(nic))
            {
                if (unicast.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                if (isOrdinaryLanAdapter && AdmissionPolicy.IsRfc1918(unicast.Address))
                {
                    return unicast.Address; // exactly what a Wi-Fi-only iPad needs
                }
                fallback ??= unicast.Address;
            }
        }
        return fallback;
    }

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
    public static bool IsPaintstreamQuery(byte[] datagram, string serviceType, string serviceDomain) =>
        IsPaintstreamQuery(datagram, serviceType, serviceDomain, out _);

    /// <summary>As above, and also reports whether the matching question requested a unicast
    /// reply — RFC 6762 §5.4's "QU" bit, the top bit of the QCLASS field. `NWBrowser`'s first query
    /// after starting a browse is commonly QU, wanting one fast direct answer rather than whatever
    /// timing a multicast responder applies. A second overload rather than changing the existing
    /// signature, since <c>MdnsAdvertiserTests</c> and every other caller ask only the yes/no
    /// question.</summary>
    public static bool IsPaintstreamQuery(byte[] datagram, string serviceType, string serviceDomain,
        out bool requestedUnicastResponse)
    {
        requestedUnicastResponse = false;
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
                offset += consumed;
                ushort qclass = BinaryPrimitives.ReadUInt16BigEndian(datagram.AsSpan(offset + 2, 2));
                offset += 4; // QTYPE(2) + QCLASS(2)
                if (name.Equals(wanted, StringComparison.OrdinalIgnoreCase))
                {
                    requestedUnicastResponse = (qclass & 0x8000) != 0;
                    return true;
                }
            }
            return false;
        }
        catch (Exception)
        {
            // Any malformed shape (a truncated packet, a bad pointer, a corrupt length byte) is
            // "not a query we recognize", not this class's problem to throw about.
            requestedUnicastResponse = false;
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
