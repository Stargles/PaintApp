import XCTest
import Network

/// TODO (98): `StreamDiscovery.nearbyStreamers(from:)` — the whole of "Nearby" result handling
/// that is not `NWBrowser` plumbing, and the seam this drives with no real network and no real
/// `NWBrowser`. `NWBrowser.Result` has no public initializer, so a live browse cannot be
/// constructed in a test; `NWEndpoint.service(name:type:domain:interface:)` does, which is why
/// `StreamDiscoveryBrowser` is built to hand this function endpoints rather than results.
@MainActor
final class StreamDiscoveryLogicTests: XCTestCase {

    private func service(_ name: String, type: String = StreamDiscovery.serviceType, domain: String = "local")
        -> NWEndpoint {
        .service(name: name, type: type, domain: domain, interface: nil)
    }

    func testAPaintstreamServiceEndpointBecomesANearbyStreamerNamedForItWithTheDefaultPort() throws {
        let result = StreamDiscovery.nearbyStreamers(from: [service("desktop-cbr0fl6")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "desktop-cbr0fl6")
        XCTAssertEqual(result[0].host, "desktop-cbr0fl6.local", "host resolution reuses the ordinary .local path")
        XCTAssertEqual(result[0].port, StreamEndpoint.defaultPort)
    }

    func testAnEndpointOfADifferentServiceTypeIsIgnored() throws {
        let result = StreamDiscovery.nearbyStreamers(from: [service("some-printer", type: "_airplay._tcp")])
        XCTAssertTrue(result.isEmpty)
    }

    func testAHostPortEndpointIsNotAService() throws {
        let notAService = NWEndpoint.hostPort(host: "100.104.85.111", port: 47301)
        let result = StreamDiscovery.nearbyStreamers(from: [notAService])
        XCTAssertTrue(result.isEmpty)
    }

    func testTwoDifferentLaptopsBothAppearSortedByName() throws {
        let result = StreamDiscovery.nearbyStreamers(from: [service("zeta-laptop"), service("alpha-laptop")])
        XCTAssertEqual(result.map(\.name), ["alpha-laptop", "zeta-laptop"])
    }

    func testTheSameLaptopAnnouncedTwiceIsDeduplicatedByName() throws {
        // A laptop with more than one active NIC can be announced once per interface.
        let result = StreamDiscovery.nearbyStreamers(from: [service("desktop-cbr0fl6"), service("desktop-cbr0fl6")])
        XCTAssertEqual(result.count, 1)
    }

    func testNoEndpointsIsTheEmptyNearbyList() throws {
        // STREAM.md TODO (98): "empty state is fine off-network" — this is what the connect
        // sheet's Nearby section renders from when nothing has been found yet.
        XCTAssertEqual(StreamDiscovery.nearbyStreamers(from: []), [])
    }
}
