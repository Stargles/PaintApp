import Combine
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
/// the stream at whatever picture the bake froze, until something else re-bakes that frame.
/// **Stage 2 measured the alternative and left it** — a per-tick in-memory composite of the frame
/// is a canvas-sized composite of every layer, MEASURED at tens of milliseconds at 2048²
/// (`StreamSandwichBench`), an order of magnitude over the ~4 ms the tick could carry — so the
/// bar says so in words instead (`StreamBarState.sandwichNote`), and a stroke on the layer, which
/// puts the sandwich mid-stroke, is the one time the live picture reaches an engaged canvas.
///
/// ## What the bar reads — STREAM.md §5.6, §5.7
///
/// `connectionStates` and `statuses` are `@Published`, so `StreamBar` observes this object and
/// re-renders on a connection coming or going and on a STATUS — events, never frames. The word it
/// shows is `barState(for:)`'s.
///
/// ## Freeze — STREAM.md §5.4
///
/// `elementFrozenStateChanged(endpoint:)` runs after `CanvasManager.setStreamFrozen` writes the
/// flag: when every stream element on a connection is frozen the client sends CONTROL `pause`, and
/// the first unfreeze sends `resume` (whose keyframe §3 guarantees); an unfreeze on a connection
/// that was not paused asks for a keyframe. The same reconciliation (`syncPauseState`) runs on
/// backgrounding, on foregrounding and on every `.connected` transition — a laptop that has just
/// been reconnected to knows nothing about the pause the previous connection carried.
@MainActor
final class ScreenStreamCoordinator: ObservableObject {

    /// The most often the tick runs — STREAM.md §5.3's 33 ms.
    static let tickInterval: TimeInterval = 1.0 / 30.0
    /// How often the ordinary publish (`celContentChangedOutsideStroke`) runs while frames flow.
    static let publishInterval: TimeInterval = 1.0

    private(set) weak var manager: CanvasManager?

    private var clients: [StreamEndpoint: ScreenStreamClient] = [:]
    /// The status each endpoint last reported, so a newly inserted element can be sized from it and
    /// the bar can say what the laptop is sending. Published: a STATUS is an event, not a frame.
    @Published private(set) var statuses: [StreamEndpoint: StreamStatus] = [:]
    /// Each live client's connection state as of its last transition. Published for the bar.
    @Published private(set) var connectionStates: [StreamEndpoint: ScreenStreamClient.State] = [:]
    /// The endpoints this coordinator has told to `pause` and not yet to `resume`.
    private var pausedEndpoints: Set<StreamEndpoint> = []
    /// The connect sheet's pending question, one per endpoint: resolved by the first STATUS after
    /// HELLO, or by the first failure.
    private var pendingConnects: [StreamEndpoint: [CheckedContinuation<StreamStatus, Error>]] = [:]

    /// Which frame index each element last drew, so a tick on an unchanged slot costs nothing.
    ///
    /// **Keyed by cel as well as by element**, because element ids are unique within a cel and not
    /// within a document: a split (Bake Frame, Split Drawing) copies the stream element — id and
    /// all — into the new cel, and a key on the element alone would let the cel at frame 3 skip the
    /// frame the cel at frame 1 had already drawn, leaving it on the older picture it was copied
    /// with until the next frame arrived.
    private struct DrawnKey: Hashable {
        let celID: UUID
        let elementID: UUID
    }
    private var drawnFrameIndex: [DrawnKey: Int] = [:]
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

    /// Whether `sync()` and `connect(to:)` open sockets. **False in every `CanvasFixture` manager**,
    /// so a logic test that inserts a stream does not start a client resolving `laptop:47301` in
    /// the background for the rest of the run. True in the app.
    ///
    /// When false the client objects still exist — made and never started — so a logic test can
    /// read `sentControlCommands` and drive `stateChanged`/`statusArrived` against a real endpoint
    /// entry; `ScreenStreamClient.send` on a client with no connection is a no-op.
    var startsClients = true

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
            connectionStates.removeValue(forKey: endpoint)
            pausedEndpoints.remove(endpoint)
        }
        syncPauseState()
    }

    /// Stops every client and forgets every status. The document is closing.
    func stopAll() {
        for client in clients.values { client.stop() }
        clients.removeAll()
        statuses.removeAll()
        connectionStates.removeAll()
        pausedEndpoints.removeAll()
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
        guard startsClients else {
            throw ConnectFailure(sentence: "This document does not open connections.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingConnects[endpoint, default: []].append(continuation)
            if clients[endpoint] == nil { startClient(for: endpoint) }
        }
    }

    private func startClient(for endpoint: StreamEndpoint) {
        let client = ScreenStreamClient(endpoint: endpoint)
        clients[endpoint] = client
        guard startsClients else { return }
        connectionStates[endpoint] = .connecting
        client.onStateChange = { [weak self] state in
            self?.stateChanged(state, at: endpoint)
        }
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

    /// Internal rather than private so `StreamInsertLogicTests` can hand the coordinator a STATUS
    /// with no socket; the app reaches it only through a client's `onStatus`.
    func statusArrived(_ status: StreamStatus, from endpoint: StreamEndpoint) {
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

    /// A client's transition. `.reconnecting` is STREAM.md §5.6's disconnect: the picture on the
    /// element stays exactly where it is (nothing here touches `displayFrame`, and the next save
    /// writes it), the bar changes its word, and the pause this end had asked for is forgotten
    /// because the connection that carried it is gone — `.connected` re-derives it.
    ///
    /// Internal rather than private so a logic test can drive the bar's state with no socket.
    func stateChanged(_ state: ScreenStreamClient.State, at endpoint: StreamEndpoint) {
        if state == .stopped {
            connectionStates.removeValue(forKey: endpoint)
        } else {
            connectionStates[endpoint] = state
        }
        switch state {
        case .connected:
            syncPauseState()
        case .reconnecting, .connecting, .stopped:
            pausedEndpoints.remove(endpoint)
        }
    }

    // MARK: - Freeze (STREAM.md §5.4)

    /// Whether an endpoint has anything to send frames *for*: the app in the foreground and at
    /// least one unfrozen stream element naming it. A hidden layer's element still counts — the tick
    /// skips it, but the artist can show the layer again without a round trip to the laptop.
    private func wantsFrames(from endpoint: StreamEndpoint) -> Bool {
        guard let manager, !isInBackground else { return false }
        for layer in manager.layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsStream else { continue }
                for stream in vector.streams where !stream.isFrozen
                    && stream.host == endpoint.host && stream.port == endpoint.port {
                    return true
                }
            }
        }
        return false
    }

    /// **Sends `pause` to every connected laptop nothing wants frames from, and `resume` to every
    /// one something wants them from again.** Idempotent: it compares against `pausedEndpoints`,
    /// so calling it on every event that could change the answer costs nothing when nothing did.
    /// `send` is a no-op on a client that is not connected, and `.connected` calls back in here, so
    /// a pause a reconnect lost is re-sent the moment the laptop answers.
    ///
    /// The decoder is reset on `resume` rather than on `pause`: §3 has the laptop restart with a
    /// keyframe, and a reset here makes that keyframe the first thing decoded — where a reset on
    /// `pause` would turn any access unit still in flight into a keyframe *request*, which the
    /// fake streamer answers by restarting the very pipeline the pause just stopped.
    private func syncPauseState() {
        for (endpoint, client) in clients {
            let wanted = wantsFrames(from: endpoint)
            let paused = pausedEndpoints.contains(endpoint)
            if !wanted, !paused {
                client.pause()
                pausedEndpoints.insert(endpoint)
                sentControlCommands.append((endpoint, .pause))
            } else if wanted, paused {
                client.decoder.reset()
                client.resume()
                pausedEndpoints.remove(endpoint)
                sentControlCommands.append((endpoint, .resume))
                // The laptop's STATUS after `resume` is on its way; until it lands the stored one
                // still says "Paused by client", which is a pause this end has just lifted. Say so.
                if var status = statuses[endpoint], !status.streaming {
                    status.streaming = true
                    status.reason = nil
                    statuses[endpoint] = status
                }
            }
        }
    }

    /// Runs after `CanvasManager.setStreamFrozen` has written the flag. `unfroze` is whether the
    /// change was a Freeze → Unfreeze: §5.4 asks for a keyframe on unfreeze, and `resume` carries
    /// one by §3, so the explicit request goes out only when the connection was not paused.
    func elementFrozenStateChanged(endpoint: StreamEndpoint, unfroze: Bool) {
        let wasPaused = pausedEndpoints.contains(endpoint)
        syncPauseState()
        if unfroze, !wasPaused, let client = clients[endpoint] {
            client.requestKeyframe()
            sentControlCommands.append((endpoint, .keyframe))
        }
        objectWillChange.send()
    }

    /// Every CONTROL this coordinator has asked a client to send, in order — for tests, which have
    /// no socket to read the wire from. Bounded: the last 64.
    private(set) var sentControlCommands: [(endpoint: StreamEndpoint, command: StreamControlCommand)] = [] {
        didSet { if sentControlCommands.count > 64 { sentControlCommands.removeFirst() } }
    }

    // MARK: - The bar's word (STREAM.md §5.6, §5.7)

    /// The state word `StreamBar` shows for one element — see `StreamBarState`.
    ///
    /// Frozen wins over everything: it is the artist's own doing and the picture is held whatever
    /// the laptop does. Then the connection, then what the laptop said it is sending.
    func barState(for element: VectorStreamElement) -> StreamBarState {
        if element.isFrozen { return .frozen }
        let endpoint = StreamEndpoint(host: element.host, port: element.port)
        switch connectionStates[endpoint] {
        case .none, .connecting?:
            return .connecting
        case .reconnecting?, .stopped?:
            return .reconnecting
        case .connected?:
            guard let status = statuses[endpoint] else { return .connecting }
            return status.streaming ? .live : .notStreaming(reason: status.reason ?? "no source is picked")
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
                let key = DrawnKey(celID: cel.id, elementID: stream.id)
                guard let latest = latestFrame(for: endpoint),
                      drawnFrameIndex[key] != latest.index else { continue }
                drawnFrameIndex[key] = latest.index
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
        syncPauseState()
    }

    private func appWillEnterForeground() {
        isInBackground = false
        // `resume` carries a keyframe by §3, so nothing here asks for a second one; an endpoint
        // every element of which is frozen stays paused, which is what the artist left it as.
        syncPauseState()
    }
}

/// **The word the stream bar shows** — STREAM.md §5.6's four, plus the first connection's own.
/// Computed by `ScreenStreamCoordinator.barState(for:)` and pinned by `StreamBarStateLogicTests`;
/// in the test target so the bar's one decision is not made in a SwiftUI body.
enum StreamBarState: Equatable {
    /// Connected, and the laptop says it is sending.
    case live
    /// The element's own `isFrozen` — the picture is held whatever the laptop does.
    case frozen
    /// The first attempt, before any answer: a fresh insert, or a document just opened.
    case connecting
    /// The connection dropped and the client is retrying on §3's backoff. The last picture stays.
    case reconnecting
    /// Connected, but STATUS says `streaming:false` — nothing picked, paused, or the window closed.
    case notStreaming(reason: String)

    var word: String {
        switch self {
        case .live: return "Live"
        case .frozen: return "Frozen"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .notStreaming(let reason): return "Not streaming — \(reason)"
        }
    }

    /// The sentence the bar adds while the layer sits in an engaged sandwich at rest — a blend
    /// mode, a mask, an effect or a transformation layer anywhere in the document puts the whole
    /// canvas on the baked composite, which `committedVersion` keeps blind to a live frame by
    /// design (see `ScreenStreamCoordinator`'s header). Never silent staleness.
    static let sandwichNote = "Live picture pauses while a blend mode, mask, effect or transformation layer is in the document"
}
