import Combine
import Foundation
import Network

/// TODO (98): "Nearby" — the Windows streamer advertises itself with DNS-SD
/// (`streamer/Streamer.Core/Discovery/MdnsAdvertiser.cs`: `_paintstream._tcp`, the laptop's own
/// name as the instance) on the LAN, and this browses for it so `StreamConnectSheet` can offer a
/// tap instead of a typed address. The typed-address path (Tailscale, or any address) is
/// unchanged — this is purely an alternate way to fill it in, wiring nothing new: the same port
/// and protocol (STREAM.md §3) once connected.
enum StreamDiscovery {
    /// Must match the Windows side's advertised service type verbatim.
    static let serviceType = "_paintstream._tcp"
}

/// One laptop found on the LAN. `host` is `"<name>.local"` — the streamer's mDNS hostname equals
/// its DNS-SD instance name (both are `Environment.MachineName` on the Windows side), so this
/// reuses `ScreenStreamClient`'s ordinary host-string connect path with no new code there:
/// `.local` resolution is the platform resolver's job, exactly as it already is for a typed
/// MagicDNS name. The port is always `StreamEndpoint.defaultPort` — discovery only ever
/// advertises the one streamer port there is.
nonisolated struct NearbyStreamer: Identifiable, Hashable {
    var name: String
    var host: String
    var port: UInt16 = StreamEndpoint.defaultPort
    var id: String { name }
}

extension NWEndpoint {
    /// Pulled out of `StreamDiscoveryBrowser`'s result handling so it is testable with no real
    /// `NWBrowser`: `NWEndpoint.service` has a public initializer; `NWBrowser.Result`, which is
    /// what a live browse actually hands back, does not.
    var asNearbyStreamer: NearbyStreamer? {
        guard case let .service(name, type, _, _) = self, type == StreamDiscovery.serviceType else { return nil }
        return NearbyStreamer(name: name, host: "\(name).local")
    }
}

extension StreamDiscovery {
    /// Endpoints → a sorted, de-duplicated Nearby list — the whole of "result handling" that
    /// is not `NWBrowser` plumbing, and the seam `StreamDiscoveryLogicTests` drives directly.
    /// De-duplicated by name because a laptop with more than one active NIC can be announced
    /// once per interface; sorted so the list does not reorder itself under the artist's thumb
    /// as `NWBrowser` reports results in whatever order they arrive.
    static func nearbyStreamers(from endpoints: some Sequence<NWEndpoint>) -> [NearbyStreamer] {
        var seenNames = Set<String>()
        var result: [NearbyStreamer] = []
        for endpoint in endpoints {
            guard let streamer = endpoint.asNearbyStreamer, seenNames.insert(streamer.name).inserted else { continue }
            result.append(streamer)
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Browses the LAN for `_paintstream._tcp` (TODO (98)) and publishes what it finds. One instance
/// owned by `StreamConnectSheet`'s presentation — started when the sheet appears, stopped when it
/// disappears — since Nearby is purely a way to fill in the address field, not a document- or
/// session-scoped concern like `ScreenStreamCoordinator`.
///
/// Not proved end to end in this build: the Mac and the laptop are not on the artist's Wi-Fi from
/// where this was built, so this class is proved by `StreamDiscovery.nearbyStreamers(from:)`'s own
/// logic test (no real network) plus the Windows side's `MdnsAdvertiserTests`, and is named here as
/// unverified live — `browseResultsChangedHandler` firing, and a real `NWBrowser.Result` actually
/// carrying a `.service` endpoint the way `asNearbyStreamer` assumes, is standard `NWBrowser`
/// behavior for a Bonjour descriptor but was not watched happen against the real streamer.
@MainActor
final class StreamDiscoveryBrowser: ObservableObject {
    @Published private(set) var nearby: [NearbyStreamer] = []

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: StreamDiscovery.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // browseResultsChangedHandler's closure type is @Sendable, so the actor hop has to
            // be explicit even though start(queue: .main) below already runs it on the main
            // queue — the same "hop once" shape ScreenStreamClient's own callbacks use via
            // DispatchQueue.main.async.
            let endpoints = results.map(\.endpoint)
            DispatchQueue.main.async {
                self?.nearby = StreamDiscovery.nearbyStreamers(from: endpoints)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        nearby = []
    }
}
