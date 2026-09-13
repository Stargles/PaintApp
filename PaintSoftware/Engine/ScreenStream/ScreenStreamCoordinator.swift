import Foundation
import UIKit

/// **Redrawing without an edit** — STREAM.md §5.3, the first thing in the app that repaints a cel
/// because time passed rather than because the artist did something.
///
/// Owned by `CanvasManager`, one per document. It keeps one `ScreenStreamClient` per endpoint the
/// open document's stream elements name, and turns the decoder's frame-arrived signal into a
/// **coalesced tick at most every `tickInterval`** on the main actor. The tick does exactly this,
/// for each stream element on a visible vector layer whose cel is the one at the current frame and
/// which is not frozen:
///
/// 1. read the client's latest frame index; skip the element if it has drawn that frame already;
/// 2. `VectorCanvas.setStreamFrame(id:image:)` — the element's `displayFrame`, a `.region`
///    invalidation of the element's own footprint, `version` moved and `committedVersion` not;
/// 3. **repaint the layer host directly** through `onLayerNeedsRepaint`, which `CanvasView`
///    installs — the same shape as `StrokeCanvasView.guideOverlayNeedsUpdate`: a per-tick signal
///    that must not go through `objectWillChange`, because a SwiftUI pass re-runs every view body
///    observing the manager and the tick is thirty a second. The host answers with
///    `refreshDisplayIfStale`, whose rasterize is off the main thread and coalesces on its own.
///
/// Once a second — not per tick — it also calls `celContentChangedOutsideStroke`, which is the
/// ordinary publish: the layer-panel thumbnail catches up through its 400 ms debounce (which a
/// per-tick call would reset forever), and anything else observing the document sees the frame.
///
/// ## When it does not tick
///
/// - while `isPlaying` — STREAM.md §2.9: a stream layer that is actively moving need not be
///   rendered, and playback reads the bake, which `committedVersion` keeps blind to the stream;
/// - while the app is in the background — the connection is paused from this end too, so the
///   laptop stops encoding for nobody;
/// - for an element the Move box holds: the host's float is a latched bitmap (`beginVectorFloat`),
///   so the tick re-mints that bitmap instead through `onFloatNeedsRepaint`, which is a render of
///   the lifted ids alone. STREAM.md's *"the box's own redraw covers it"* was wrong — nothing
///   re-rendered the float per nudge, and without this the artist would connect and see the
///   placeholder in the box until they committed it.
///
/// ## What it does not do
///
/// It never bumps `committedVersion`, so the frame bake, the dirty sweep and the sandwich key are
/// blind to it by construction. The consequence is stated rather than hidden: a document whose
/// canvas is on the sandwich at rest — a blend mode, a mask, an effect, a container pose — shows
/// the stream at whatever picture the bake froze, until something else re-bakes that frame. Stage 2
/// measures the tick and decides what the engaged sandwich should do; stage 1 keeps the flat row
/// live and the disk quiet.
@MainActor
final class ScreenStreamCoordinator {

    /// The most often the tick runs — STREAM.md §5.3's 33 ms.
    static let tickInterval: TimeInterval = 1.0 / 30.0
    /// How often the ordinary publish (`celContentChangedOutsideStroke`) runs while frames flow.
    static let publishInterval: TimeInterval = 1.0

    private(set) weak var manager: CanvasManager?

    private var clients: [StreamEndpoint: ScreenStreamClient] = [:]
    /// The status each endpoint last reported, so a newly inserted element can be sized from it.
    private var statuses: [StreamEndpoint: StreamStatus] = [:]
    /// The connect sheet's pending question, one per endpoint: resolved by the first STATUS after
    /// HELLO, or by the first failure.
    private var pendingConnects: [StreamEndpoint: [CheckedContinuation<StreamStatus, Error>]] = [:]

    /// Which frame index each element last drew, so a tick on an unchanged slot costs nothing.
    private var drawnFrameIndex: [UUID: Int] = [:]
    private var tickScheduled = false
    private var lastTick: CFAbsoluteTime = 0
    private var lastPublish: CFAbsoluteTime = 0
    private var isInBackground = false
    private var observers: [NSObjectProtocol] = []

    /// Installed by `CanvasView.Coordinator`: repaint the host of this layer from its canvas.
    var onLayerNeedsRepaint: ((_ layerID: UUID) -> Void)?
    /// Installed by `CanvasView.Coordinator`: re-mint the Move box's latched bitmap for this layer,
    /// because the element it holds has a new frame.
    var onFloatNeedsRepaint: ((_ layerID: UUID) -> Void)?

    /// How many ticks have run — for tests and the device measurement, nothing else reads it.
    private(set) var tickCount = 0
    /// Wall time the last tick took on the main actor, in seconds. MEASURED per tick so a device
    /// run can quote it; STREAM.md §5.3 asks for under 2 ms at 1080p.
    private(set) var lastTickDuration: TimeInterval = 0

    /// A test seam: a decoder image source per endpoint that stands in for a socket. Nil in the app.
    var frameSourceOverride: ((StreamEndpoint) -> (index: Int, image: CGImage)?)?

    init(manager: CanvasManager) {
        self.manager = manager
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appDidEnterBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appWillEnterForeground() }
        })
    }

    deinit {
        // Clients cancel their own sockets in `deinit`; dropping the dictionary is enough, but the
        // observers hold closures that would otherwise outlive this object.
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Endpoints the document names

    /// Every endpoint a stream element in `manager.layers` names.
    var referencedEndpoints: Set<StreamEndpoint> {
        guard let manager else { return [] }
        var endpoints = Set<StreamEndpoint>()
        for layer in manager.layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsStream else { continue }
                for stream in vector.streams {
                    endpoints.insert(StreamEndpoint(host: stream.host, port: stream.port))
                }
            }
        }
        return endpoints
    }

    /// The endpoints with a live client right now.
    var activeEndpoints: Set<StreamEndpoint> { Set(clients.keys) }

    /// The client for an endpoint, if one is running.
    func client(for endpoint: StreamEndpoint) -> ScreenStreamClient? { clients[endpoint] }

    /// The last STATUS an endpoint reported.
    func status(for endpoint: StreamEndpoint) -> StreamStatus? { statuses[endpoint] }

    /// **Starts a client for every endpoint the document names and stops every one it no longer
    /// does.** Called once per canvas reconciliation pass beside `syncFrameBake`, which is the
    /// document's own clock for "something may have changed" — so a document opened with stream
    /// elements connects on its first pass, an undone insert stops its client on the next, and a
    /// redo starts it again. O(cels) of one memoized `Bool` each.
    func sync() {
        guard manager != nil else { return }
        let wanted = referencedEndpoints
        for endpoint in wanted where clients[endpoint] == nil {
            startClient(for: endpoint)
        }
        for (endpoint, client) in clients where !wanted.contains(endpoint) && pendingConnects[endpoint] == nil {
            client.stop()
            clients.removeValue(forKey: endpoint)
        }
    }

    /// Stops every client and forgets every status. The document is closing.
    func stopAll() {
        for client in clients.values { client.stop() }
        clients.removeAll()
        statuses.removeAll()
        drawnFrameIndex.removeAll()
        for (endpoint, continuations) in pendingConnects {
            for continuation in continuations {
                continuation.resume(throwing: ConnectFailure(sentence: "The document was closed."))
            }
            pendingConnects.removeValue(forKey: endpoint)
        }
    }

    // MARK: - The connect sheet's question

    struct ConnectFailure: Error, Equatable {
        let sentence: String
    }

    /// **Connect, and answer with the laptop's first STATUS or the first failure's sentence.** The
    /// sheet awaits this; on success it inserts the layer, on failure it shows the sentence and
    /// stays open. A client this call started is left running only if something in the document
    /// ends up naming it — the next `sync()` stops one nothing names, so a refused address does not
    /// keep reconnecting in the background forever.
    func connect(to endpoint: StreamEndpoint) async throws -> StreamStatus {
        if let status = statuses[endpoint], clients[endpoint]?.state == .connected {
            return status
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingConnects[endpoint, default: []].append(continuation)
            if clients[endpoint] == nil { startClient(for: endpoint) }
        }
    }

    private func startClient(for endpoint: StreamEndpoint) {
        let client = ScreenStreamClient(endpoint: endpoint)
        clients[endpoint] = client
        client.onStatus = { [weak self] status in
            self?.statusArrived(status, from: endpoint)
        }
        client.onFailure = { [weak self] sentence in
            self?.failureArrived(sentence, from: endpoint)
        }
        client.decoder.onFrame = { [weak self] in
            // Decode queue. Hop once; the tick coalesces from there.
            DispatchQueue.main.async { self?.frameArrived() }
        }
        client.decoder.onNeedsKeyframe = { [weak client] in
            client?.requestKeyframe()
        }
        client.start()
    }

    private func statusArrived(_ status: StreamStatus, from endpoint: StreamEndpoint) {
        statuses[endpoint] = status
        applyStatusToElements(status, endpoint: endpoint)
        if let continuations = pendingConnects.removeValue(forKey: endpoint) {
            for continuation in continuations { continuation.resume(returning: status) }
        }
    }

    private func failureArrived(_ sentence: String, from endpoint: StreamEndpoint) {
        guard let continuations = pendingConnects.removeValue(forKey: endpoint) else { return }
        for continuation in continuations {
            continuation.resume(throwing: ConnectFailure(sentence: sentence))
        }
        // Nothing may name this endpoint yet — the insert happens after a successful connect — so
        // stop the client here rather than leaving it to a `sync()` that would find no element
        // and stop it anyway, one pass later.
        if !referencedEndpoints.contains(endpoint) {
            clients[endpoint]?.stop()
            clients.removeValue(forKey: endpoint)
        }
    }

    /// STATUS carries the laptop's picture size and source name, and both are stored on the
    /// element — **a document change, and charged as one**: the elements are rewritten through
    /// `elements =` with `bumpVersion()`, so `committedVersion` moves, the bake re-keys, and a save
    /// writes the new size. The placement is left exactly where it is (the brief's default): a
    /// source switch from a 1080p monitor to a 720p window shrinks the rectangle on canvas rather
    /// than re-fitting it. Not an undo step — nobody in the room did it.
    private func applyStatusToElements(_ status: StreamStatus, endpoint: StreamEndpoint) {
        guard let manager, status.width > 0, status.height > 0 else { return }
        let size = CGSize(width: status.width, height: status.height)
        let label = status.sourceLabel
        for layer in manager.layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsStream else { continue }
                var changed = false
                let rewritten = vector.elements.map { element -> VectorElement in
                    guard case .stream(var stream) = element,
                          stream.host == endpoint.host, stream.port == endpoint.port,
                          stream.naturalSize != size || stream.sourceLabel != label else { return element }
                    stream.naturalSize = size
                    stream.sourceLabel = label
                    changed = true
                    return .stream(stream)
                }
                guard changed else { continue }
                vector.elements = rewritten
                vector.bumpVersion()
                manager.celContentChangedOutsideStroke(layerID: layer.id, celID: cel.id)
            }
        }
    }

    // MARK: - The tick

    private func frameArrived() {
        guard !tickScheduled else { return }
        tickScheduled = true
        let elapsed = CFAbsoluteTimeGetCurrent() - lastTick
        let delay = max(0, Self.tickInterval - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.tickScheduled = false
            self?.tick()
        }
    }

    /// One pass over the stream elements at the current frame. Public so a logic test can drive it
    /// with `frameSourceOverride` and no socket; the app reaches it only through `frameArrived`.
    func tick() {
        let started = CFAbsoluteTimeGetCurrent()
        lastTick = started
        guard let manager, !manager.isPlaying, !isInBackground else { return }
        tickCount += 1
        let shownFrames = manager.displayedFrames(atFrame: manager.currentFrame)
        let float = manager.vectorFloat
        let publishDue = started - lastPublish >= Self.publishInterval
        var published = false

        for (layerIndex, layer) in manager.layers.enumerated() where layer.kind == .vector {
            guard manager.isLayerEffectivelyVisible(layerIndex) else { continue }
            let frame = shownFrames[layerIndex] ?? manager.currentFrame
            guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: frame) else { continue }
            let cel = layer.cels[celIndex]
            guard let vector = cel.vector, vector.holdsStream else { continue }

            var hostNeedsRepaint = false
            var floatNeedsRepaint = false
            for stream in vector.streams where !stream.isFrozen {
                let endpoint = StreamEndpoint(host: stream.host, port: stream.port)
                guard let latest = latestFrame(for: endpoint),
                      drawnFrameIndex[stream.id] != latest.index else { continue }
                drawnFrameIndex[stream.id] = latest.index
                vector.setStreamFrame(id: stream.id, image: UIImage(cgImage: latest.image))
                if let float, float.layerID == layer.id, float.insideIDs.contains(stream.id) {
                    floatNeedsRepaint = true
                } else {
                    hostNeedsRepaint = true
                }
            }
            if hostNeedsRepaint {
                onLayerNeedsRepaint?(layer.id)
                if publishDue {
                    manager.celContentChangedOutsideStroke(layerID: layer.id, celID: cel.id)
                    published = true
                }
            }
            if floatNeedsRepaint { onFloatNeedsRepaint?(layer.id) }
        }
        if published { lastPublish = started }
        lastTickDuration = CFAbsoluteTimeGetCurrent() - started
    }

    private func latestFrame(for endpoint: StreamEndpoint) -> (index: Int, image: CGImage)? {
        if let frameSourceOverride { return frameSourceOverride(endpoint) }
        return clients[endpoint]?.decoder.latestImage()
    }

    // MARK: - Background

    private func appDidEnterBackground() {
        isInBackground = true
        for client in clients.values { client.pause() }
    }

    private func appWillEnterForeground() {
        isInBackground = false
        for client in clients.values {
            client.resume()
            client.requestKeyframe()
        }
    }
}
