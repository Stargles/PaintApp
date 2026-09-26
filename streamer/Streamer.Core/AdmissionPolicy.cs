using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace Streamer.Core;

/// <summary>
/// TODO (98): the one place that answers "is this remote address allowed to connect" — Tailscale,
/// widened to also admit the laptop's own local (RFC1918) subnets, exactly as STREAM.md §6 now
/// records. <see cref="ProtocolServer"/> calls <see cref="IsAdmitted"/> per connection, computing
/// <see cref="LocalIPv4Subnets"/> fresh each time rather than caching it, so a laptop that joins a
/// different Wi-Fi network mid-session is admitted on its new subnet with no reinstall — the same
/// tolerance §2.12's Tailscale half already had for free (Tailscale addresses don't depend on
/// which physical network the laptop is on).
///
/// The Windows firewall rule (<c>install-streamer.ps1</c>) is a coarser, static allow-list — it
/// cannot know which subnet the laptop's NIC is actually on at any given moment, only the fixed
/// set of ranges "Tailscale or *some* RFC1918 network" spans — so it is widened to that fixed
/// superset and this class is what narrows a connection down to "actually on one of them right
/// now". Two layers, one rule: this is the only place the rule itself is spelled out; the firewall
/// only has to be at least as permissive as it needs to be for this class to ever get a chance to
/// run.
/// </summary>
public static class AdmissionPolicy
{
    /// <summary>Tailscale's CGNAT range (STREAM.md §2.12) — always admitted, wherever the laptop's
    /// own NICs currently are.</summary>
    private static readonly (uint Network, int PrefixLength) TailscaleRange =
        (ToUInt32(IPAddress.Parse("100.64.0.0")), 10);

    /// <summary>True if <paramref name="remote"/> is a Tailscale address, or shares a subnet with
    /// one of <paramref name="localSubnets"/> and that subnet is RFC1918 (STREAM.md §6: "the
    /// laptop's own local subnets (RFC1918 ranges on interfaces it has)" — a local address that
    /// happens not to be RFC1918, e.g. a routable public IP briefly bound to a NIC, is not treated
    /// as "the LAN" by this rule).</summary>
    public static bool IsAdmitted(IPAddress remote, IEnumerable<(IPAddress Address, int PrefixLength)> localSubnets)
    {
        if (remote.IsIPv4MappedToIPv6) remote = remote.MapToIPv4();
        if (remote.AddressFamily != AddressFamily.InterNetwork) return false;

        uint remoteBits = ToUInt32(remote);
        if (InRange(remoteBits, TailscaleRange)) return true;

        foreach (var (address, prefixLength) in localSubnets)
        {
            if (address.AddressFamily != AddressFamily.InterNetwork) continue;
            if (!IsRfc1918(address)) continue;
            if (InRange(remoteBits, (ToUInt32(address), prefixLength))) return true;
        }
        return false;
    }

    /// <summary>The laptop's own IPv4 unicast addresses and their subnet prefix lengths, read
    /// fresh from live NIC data — deliberately not cached, so <see cref="IsAdmitted"/> always
    /// judges against wherever the laptop is connected right now.</summary>
    public static IEnumerable<(IPAddress Address, int PrefixLength)> LocalIPv4Subnets()
    {
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var unicast in nic.GetIPProperties().UnicastAddresses)
            {
                if (unicast.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                if (unicast.PrefixLength is <= 0 or > 32) continue;
                yield return (unicast.Address, unicast.PrefixLength);
            }
        }
    }

    /// <summary>Internal rather than private: <see cref="Discovery.MdnsAdvertiser"/> needs the same
    /// "is this a private LAN address" test when picking which of the laptop's several addresses to
    /// put in its mDNS A record, rather than duplicating the byte-pattern check a second place.</summary>
    internal static bool IsRfc1918(IPAddress address)
    {
        byte[] b = address.GetAddressBytes();
        if (b[0] == 10) return true;
        if (b[0] == 172 && b[1] is >= 16 and <= 31) return true;
        if (b[0] == 192 && b[1] == 168) return true;
        return false;
    }

    private static uint ToUInt32(IPAddress address)
    {
        // GetAddressBytes is network (big-endian) order regardless of this machine's own
        // endianness — build the uint by hand rather than trusting BitConverter's host order.
        byte[] b = address.GetAddressBytes();
        return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | b[3];
    }

    private static bool InRange(uint address, (uint Network, int PrefixLength) range)
    {
        if (range.PrefixLength <= 0) return true;
        uint mask = range.PrefixLength >= 32 ? 0xFFFFFFFFu : ~(0xFFFFFFFFu >> range.PrefixLength);
        return (address & mask) == (range.Network & mask);
    }
}
