import Combine
import Foundation
import OSLog
import UIKit

/// **Redrawing without an edit** — STREAM.md §5.3, the first thing in the app that repaints a cel
/// because time passed rather than because the artist did something.
///
/// Owned by `CanvasManager`, one per document. It keeps one `ScreenStreamClient` per endpoint the
/// open document's stream elements name, and turns the decoder's frame-arrived signal into a
/// **coalesced tick at most every `tickInterval`** on the main actor. The tick does exactly this:
///
/// 1. for each endpoint with a decoded frame, **write it into every unfrozen stream element that
///    names the endpoint — on every cel, displayed or not** — through
///    `VectorCanvas.setStreamFrame(id:image:index:)`: the element's picture, a `.region`
///    invalidation of the element's own footprint, `version` moved and `committedVersion` not. A
///    canvas already told about that frame index answers false, so a tick on an unchanged slot
///    writes nothing;
/// 2. for each of those elements on a visible layer whose cel is the one at the current frame,
///    **present it** through `onStreamFrame`, which `CanvasView` installs — the same shape as
///    `StrokeCanvasView.guideOverlayNeedsUpdate`: a per-tick signal that must not go through
///    `objectWillChange`, because a SwiftUI pass re-runs every view body observing the manager and
///    the tick is thirty a second. The host answers with `presentStreamFrame`, which draws the
///    element's window into a surface of its own off the main thread and coalesces on its own.
///
/// **Writing every cel is what TODO (96) needed.** The tick used to feed only the displayed cel, so
/// a stream cel on another frame, or on a hidden layer, kept the picture it last showed until a
/// frame arrived *after* it was shown again — and a laptop whose screen is not changing sends
/// nothing to arrive. Now the element holds the newest frame wherever it is, its `version` has
/// moved, and the host's ordinary repaint on a frame change or a layer coming back draws it.
///
/// **Presenting into a surface rather than repainting the host is what TODO (97) needed** — see
/// `StreamSurfaceView`. The old tick asked the host to `refreshDisplayIfStale`, which rasterized
/// the canvas and handed Core Animation a fresh canvas-sized image per frame; the render server on
/// the owner's iPad grew to its limit and was killed.
///
/// Once a second — not per tick — it also calls `celContentChangedOutsideStroke` for the displayed
/// cel, which is the ordinary publish: the layer-panel thumbnail catches up through its 400 ms
/// debounce (which a per-tick call would reset forever), and anything else observing the document
/// sees the frame.
///
/// ## When it does not tick
///
/// - while `isPlaying` — STREAM.md §2.9: a stream layer that is actively moving need not be
///   rendered, and playback reads the bake, which `committedVersion` keeps blind to the stream;
/// - while the app is in the background — the connection is paused from this end too, so the
///   laptop stops encoding for nobody.
///
/// An element the Move box holds is written like any other (`setStreamFrame` invalidates nothing
/// for a suppressed element) and presented inside the float: `CanvasView`'s closure hands the host
/// the lifted ids and their poses, and the surface rides the box.
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

    private var tickScheduled = false
    private var lastTick: CFAbsoluteTime = 0
    private var lastPublish: CFAbsoluteTime = 0
    private var isInBackground = false
    private var observers: [NSObjectProtocol] = []

    /// Installed by `CanvasView.Coordinator`: this element on this layer holds a new frame and is
    /// on screen — present it (`StrokeCanvasView.presentStreamFrame`).
    var onStreamFrame: ((_ layerID: UUID, _ elementID: UUID) -> Void)?

    /// How many ticks have run — for tests and the device measurement, nothing else reads it.
    private(set) var tickCount = 0
    /// Wall time the last tick took on the main actor, in seconds. MEASURED per tick so a device
    /// run can quote it; STREAM.md §5.3 asks for under 2 ms at 1080p.
    private(set) var lastTickDuration: TimeInterval = 0

    /// **The measurement's own outlet.** Every tick is an `OSSignposter` interval, and once a
    /// second — on the same cadence as the ordinary publish — one `Logger` line (at `.notice`, the
    /// level `log stream` shows without `--level info`) carries the ticks since the last one with
    /// their mean and worst main-actor cost. Read it on a device with
    /// `log stream --predicate 'subsystem == "PaintSoftware" && category == "ScreenStream"'`, or
    /// on the simulator through `xcrun simctl spawn <udid> log stream …`; a tick-per-second count
    /// is the frame rate the tick actually delivered to the canvas. Costs one string a second.
    private static let log = Logger(subsystem: "PaintSoftware", category: "ScreenStream")
    private static let signposter = OSSignposter(subsystem: "PaintSoftware", category: "ScreenStream")
    private var tickDurationsSincePublish: [TimeInterval] = []

    /// The last log line's numbers, published once a second on the same cadence, for the one reader
    /// that cannot open the unified log: an XCUITest on a device (`log collect --device` needs
    /// root). `StreamBar` puts it on a hidden marker, `streamBar.tickSummary`, the way
    /// `CanvasHostView` publishes the sandwich's state on `canvas.host` — none of it is otherwise
    /// visible from a test. Format: `<ticks>/<seconds>s mean:<ms> max:<ms>`.
    @Published private(set) var lastTickSummary = ""

    /// A test seam: a decoder image source per endpoint that stands in for a socket. Nil in the app.
    var frameSourceOverride: ((StreamEndpoint) -> (index: Int, image: CGImage)?)?

    /// A test seam for STREAM.md §6's document-level connection: overrides what `UserDefaults`
    /// would answer for "the last laptop connected to," so a logic test drives the ambient-connection
    /// rule with no real defaults touched. Outer nil (the default) means "ask `UserDefaults.standard`
    /// through `StreamEndpoint.lastUsed`"; `.some(nil)` means "nothing is recorded."
    var documentEndpointOverride: StreamEndpoint??

    /// **STREAM.md §6's new bullet**: the document keeps a connection to the last laptop connected
    /// to, even with no stream element naming it — so the drop box and Send to Computer work as soon
    /// as a document is open, not only after Stream Screen. Read fresh on every `sync()` pass rather
    /// than cached once at document open: `StreamConnectSheet.connect()` writes the defaults on
    /// every attempt, so connecting to a new laptop becomes "last used" on the very next
    /// reconciliation pass rather than only after the document is reopened.
    private var documentEndpoint: StreamEndpoint? {
        if let documentEndpointOverride { return documentEndpointOverride }
        return StreamEndpoint.lastUsed()
    }

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
        var wanted = referencedEndpoints
        // §6: the document's own ambient connection, wanted whether or not any element names it.
        if let documentEndpoint { wanted.insert(documentEndpoint) }
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
    ///
    /// **Registers the pending continuation even when `startsClients` is false** — bookkeeping
    /// only, `startClient` itself is what skips the real socket — so a logic test can drive the
    /// connect-to-insert window (`pendingConnects[endpoint] != nil`, `syncPauseState`'s guard
    /// against `b07984d`'s flap) by resolving it with `statusArrived`/`failureArrived` instead of a
    /// real HELLO. Nothing production reaches ever sees `startsClients == false` — only
    /// `CanvasFixture` sets it.
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
        // **Wired on every client, started or not** — unlike the callbacks below, which only ever
        // fire off a real socket. STREAM.md §5.8's tests feed a never-started client `.fileBegin`/
        // `.fileChunk`/`.fileEnd` directly (`ScreenStreamClient.handle`) and need the real routing
        // to run, exactly the way `stateChanged`/`statusArrived` being reachable with no socket lets
        // `StreamInsertLogicTests` and `StreamBarStateLogicTests` drive the bar.
        client.onFileReceived = { [weak self] file, reply in
            self?.routeReceivedFile(file, reply: reply)
        }
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

    // MARK: - Files, laptop → iPad (STREAM.md §5.8)

    /// **Exactly the picker's insert, kind for kind.** `insertImage`/`insertVideo` already do the
    /// layer choice, the fit and the Move-box lift — this function's whole job is picking which one
    /// to call and turning its refusal into a sentence. `consumingSource: true` for
    /// `ActionsMenu.insertVideo`'s own reason: the temp file is this transfer's own copy, ours to
    /// move rather than copy again. The temp file is deleted here regardless of outcome — a video
    /// that inserted has already had it *moved* out from under this path by `insertVideo` itself, so
    /// the `try?` below is a no-op in that case and a real cleanup in every other.
    @MainActor
    private func routeReceivedFile(_ file: StreamIncomingFile, reply: @escaping (StreamFileReceiveOutcome) -> Void) {
        defer { try? FileManager.default.removeItem(at: file.url) }
        guard let manager else {
            reply(.refused("No document is open on the iPad"))
            return
        }
        switch file.kind {
        case "image":
            guard let image = UIImage(contentsOfFile: file.url.path) else {
                reply(.refused("The image could not be read"))
                return
            }
            guard manager.insertImage(image) else {
                reply(.refused("The image could not be inserted"))
                return
            }
            reply(.ok)
        case "video":
            guard manager.insertVideo(at: file.url, consumingSource: true) else {
                reply(.refused("The video could not be read"))
                return
            }
            reply(.ok)
        default:
            reply(.refused("PaintApp can insert images and videos only"))
        }
    }

    /// The endpoint of a client currently answering `.connected` — for `ExportSheet`'s Send to
    /// Computer, which needs *some* connected laptop rather than a specific one. Nil when none is.
    var connectedEndpointForSending: StreamEndpoint? {
        connectionStates.first { $0.value == .connected }?.key
    }

    /// The connected laptop's own HELLO name — `"desktop-cbr0fl6"` — for "Saved on desktop-cbr0fl6".
    /// Nil when nothing is connected.
    var connectedRemoteName: String? {
        guard let endpoint = connectedEndpointForSending else { return nil }
        return clients[endpoint]?.remoteName
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

    /// **Whether every stream element naming an endpoint is frozen** — §5.4's condition for
    /// `pause`, asked of the document. Nil when *no* element names it: that is not "all frozen",
    /// it is the moment between the sheet's connect and its insert (or the moment before `sync()`
    /// stops a client nothing needs), and a pause there restarted the laptop's pipeline on every
    /// connect — MEASURED in the stage-2 drive as a `pause`/`resume` pair four milliseconds apart.
    /// A hidden layer's element still counts as wanting frames: the tick writes them into it, so the
    /// artist can show the layer again and see the newest picture without a round trip to the laptop.
    private func everyElementIsFrozen(at endpoint: StreamEndpoint) -> Bool? {
        guard let manager else { return nil }
        var sawOne = false
        for layer in manager.layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsStream else { continue }
                for stream in vector.streams where stream.host == endpoint.host && stream.port == endpoint.port {
                    sawOne = true
                    if !stream.isFrozen { return false }
                }
            }
        }
        return sawOne ? true : nil
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
    ///
    /// **STREAM.md §6, corrected by stage 4**: `b07984d` (stage 2) read "no element names this
    /// endpoint" as "leave it alone," to stop a pause/resume pair firing four milliseconds apart on
    /// every Stream Screen connect — between the sheet's own `connect()` and the element it goes on
    /// to insert, nothing names the endpoint yet. §6's new bullet asks for more than that stage 2
    /// ever needed: a document's *ambient* connection (`documentEndpoint`) can sit with no element
    /// naming it for the rest of a session, and that must read as **paused**, not as "leave alone."
    /// The two are told apart by `pendingConnects`: it holds a continuation only for the span between
    /// `connect(to:)` being called and its STATUS (or failure) resolving it, which is exactly stage
    /// 2's four-millisecond window and never true of the ambient connection, which nothing calls
    /// `connect(to:)` for. So the four-millisecond flap stays fixed and the ambient connection is now
    /// paused, by asking a narrower question of `everyElementIsFrozen`'s nil.
    private func syncPauseState() {
        for (endpoint, client) in clients {
            // Paused for the background, for the artist having frozen everything on it, or for
            // nothing naming it at all. The one exception is the moment between the connect sheet's
            // own `connect()` and the element it is about to insert — see the doc comment above.
            let wanted: Bool
            if isInBackground {
                wanted = false
            } else if let allFrozen = everyElementIsFrozen(at: endpoint) {
                wanted = !allFrozen
            } else if pendingConnects[endpoint] != nil {
                wanted = !pausedEndpoints.contains(endpoint)   // about to be claimed — do not flap
            } else {
                wanted = false                                  // §6: nothing names it, so: paused
            }
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

    /// One pass over the document's stream elements — the header's two steps. Public so a logic
    /// test can drive it with `frameSourceOverride` and no socket; the app reaches it only through
    /// `frameArrived`.
    func tick() {
        let started = CFAbsoluteTimeGetCurrent()
        lastTick = started
        guard let manager, !manager.isPlaying, !isInBackground else { return }
        tickCount += 1
        let signpost = Self.signposter.beginInterval("tick")
        defer { Self.signposter.endInterval("tick", signpost) }
        let shownFrames = manager.displayedFrames(atFrame: manager.currentFrame)
        let publishDue = started - lastPublish >= Self.publishInterval
        var published = false
        // One `UIImage` per endpoint per tick, shared by every element it lands on: the wrapper is
        // what a split's shared `StreamPicture` compares, and a wrapper per cel would defeat that.
        var frames: [StreamEndpoint: (index: Int, image: UIImage)?] = [:]

        for (layerIndex, layer) in manager.layers.enumerated() where layer.kind == .vector {
            let displayedCel = manager.isLayerEffectivelyVisible(layerIndex)
                ? manager.activeCelIndex(inLayer: layerIndex,
                                         atFrame: shownFrames[layerIndex] ?? manager.currentFrame)
                : nil
            for (celIndex, cel) in layer.cels.enumerated() {
                guard let vector = cel.vector, vector.holdsStream else { continue }
                var presented = false
                for stream in vector.streams where !stream.isFrozen {
                    let endpoint = StreamEndpoint(host: stream.host, port: stream.port)
                    let frame: (index: Int, image: UIImage)?
                    if let known = frames[endpoint] {
                        frame = known
                    } else {
                        frame = latestFrame(for: endpoint).map { ($0.index, UIImage(cgImage: $0.image)) }
                        frames[endpoint] = frame
                    }
                    guard let frame,
                          vector.setStreamFrame(id: stream.id, image: frame.image, index: frame.index),
                          celIndex == displayedCel else { continue }
                    onStreamFrame?(layer.id, stream.id)
                    presented = true
                }
                if presented, publishDue {
                    manager.celContentChangedOutsideStroke(layerID: layer.id, celID: cel.id)
                    published = true
                }
            }
        }
        lastTickDuration = CFAbsoluteTimeGetCurrent() - started
        tickDurationsSincePublish.append(lastTickDuration)
        if published {
            let elapsed = started - lastPublish
            let durations = tickDurationsSincePublish
            let mean = durations.reduce(0, +) / Double(max(durations.count, 1))
            let worst = durations.max() ?? 0
            if lastPublish > 0 {
                lastTickSummary = String(format: "%d/%.2fs mean:%.3f max:%.3f",
                                         durations.count, elapsed, mean * 1000, worst * 1000)
                Self.log.notice("tick \(durations.count) in \(elapsed, format: .fixed(precision: 2)) s (\(Double(durations.count) / max(elapsed, 0.001), format: .fixed(precision: 1)) /s): mean \(mean * 1000, format: .fixed(precision: 3)) ms, max \(worst * 1000, format: .fixed(precision: 3)) ms on the main actor")
            }
            tickDurationsSincePublish.removeAll(keepingCapacity: true)
            lastPublish = started
        }
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
