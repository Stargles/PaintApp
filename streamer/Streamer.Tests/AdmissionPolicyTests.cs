using System.Net;
using Streamer.Core;
using Xunit;

namespace Streamer.Tests;

/// <summary>TODO (98): the widened admission rule — Tailscale stays admitted unconditionally,
/// and a same-subnet RFC1918 address is now admitted too. <see cref="AdmissionPolicy.LocalIPv4Subnets"/>
/// reads live NIC data, so these tests drive <see cref="AdmissionPolicy.IsAdmitted"/> directly
/// against hand-built subnet lists instead — the rule under test, not this machine's network.</summary>
public class AdmissionPolicyTests
{
    private static (IPAddress Address, int PrefixLength) Subnet(string address, int prefixLength) =>
        (IPAddress.Parse(address), prefixLength);

    [Theory]
    [InlineData("100.64.0.1")]
    [InlineData("100.100.50.7")]
    [InlineData("100.127.255.254")]
    public void TailscaleAddressesAreAlwaysAdmitted_EvenWithNoLocalSubnets(string remote)
    {
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse(remote), Array.Empty<(IPAddress, int)>()));
    }

    [Theory]
    [InlineData("100.63.255.255")] // just below 100.64.0.0/10
    [InlineData("100.128.0.0")]    // just above it
    [InlineData("8.8.8.8")]        // an ordinary public address
    public void AddressesOutsideTailscaleAndAnyLocalSubnetAreRefused(string remote)
    {
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse(remote), Array.Empty<(IPAddress, int)>()));
    }

    [Fact]
    public void ASameSubnetRfc1918AddressIsAdmitted()
    {
        var localSubnets = new[] { Subnet("192.168.1.50", 24) };
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse("192.168.1.200"), localSubnets));
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse("192.168.1.50"), localSubnets)); // the laptop itself
    }

    [Fact]
    public void ADifferentSubnetInTheSameRfc1918BlockIsRefused()
    {
        // The laptop is on 192.168.1.0/24; 192.168.2.x is a different subnet in the same
        // private /16 — STREAM.md §6 says "RFC1918 ranges on interfaces it has", the laptop's
        // OWN subnet, not the whole private address space.
        var localSubnets = new[] { Subnet("192.168.1.50", 24) };
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse("192.168.2.200"), localSubnets));
    }

    [Fact]
    public void A10SlashEightLaptopAdmitsItsOwnSlash24ButNotAnUnrelated10Address()
    {
        var localSubnets = new[] { Subnet("10.20.30.1", 24) };
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse("10.20.30.99"), localSubnets));
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse("10.99.0.1"), localSubnets));
    }

    [Fact]
    public void A172Block16To31IsRfc1918ButOutsideThatRangeIsNot()
    {
        // 172.32.x.x looks similar to 172.16-31/12 but is NOT RFC1918 — a local NIC address
        // there (unusual, but not impossible with an odd DHCP setup) must not widen admission
        // to the whole 172.x space.
        var inRange = new[] { Subnet("172.20.5.1", 16) };
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse("172.20.9.9"), inRange));

        var outOfRfc1918 = new[] { Subnet("172.32.5.1", 16) };
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse("172.32.9.9"), outOfRfc1918));
    }

    [Fact]
    public void ANonRfc1918LocalAddressGrantsNoLanAdmission()
    {
        // A NIC briefly holding a routable public address (e.g. a bridged/public-facing
        // adapter) must not turn "shares that /24" into LAN trust.
        var localSubnets = new[] { Subnet("8.8.8.0", 24) };
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse("8.8.8.8"), localSubnets));
    }

    [Fact]
    public void MultipleNicsAreAllConsidered()
    {
        var localSubnets = new[] { Subnet("192.168.1.1", 24), Subnet("10.0.0.1", 8) };
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse("192.168.1.77"), localSubnets));
        Assert.True(AdmissionPolicy.IsAdmitted(IPAddress.Parse("10.55.66.77"), localSubnets));
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse("172.16.0.1"), localSubnets));
    }

    [Fact]
    public void AnIPv6RemoteIsRefusedEvenWithAMatchingIPv4LocalSubnet()
    {
        // ProtocolServer's listener is IPv4 in practice (STREAM.md §3), but IsAdmitted should
        // not silently admit an IPv6 caller just because some IPv4 local subnet exists.
        var localSubnets = new[] { Subnet("192.168.1.1", 24) };
        Assert.False(AdmissionPolicy.IsAdmitted(IPAddress.Parse("::1"), localSubnets));
    }
}
