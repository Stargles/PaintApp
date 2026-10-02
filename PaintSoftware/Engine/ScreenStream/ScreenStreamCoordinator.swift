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
/// Both are `tickIsSuppressed`, and the tick is armed by a frame's arrival alone — so the edge out of
/// either arms one (`tickSuppressionMayHaveEnded`), or a frame that landed meanwhile would wait for a
/// next one a still screen never sends.
///
/// An element the Move box holds is written like any other (`setStreamFrame` invalidates nothing
/// for a suppressed element) and presented inside the float: `CanvasView`'s closure hands the host
/// the lifted ids and their poses, and the surface rides the box.
///
/// ## What it does not do
///
/// It never bumps `committedVersion`, so the frame bake, the dirty sweep and the sandwich key are
/// blind to a frame by construction — which is why a frame cannot reach the canvas through the baked
/// composite, and why a document the compositor draws (a blend mode, a mask, an effect, a container
/// pose) shows its stream the way an edit's near picture is shown: the canvas stands on the live
/// pair, cut around the stream's layer, whose own host presents the frames
/// (`CanvasManager.liveHostRun`, `SandwichPresentation.live`). A per-tick composite of the frame was
/// the alternative and MEASURED tens of milliseconds at 2048² (`StreamSandwichBench`), an order of
/// magnitude over the ~4 ms the tick could carry.
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
    /// **What this end last asked each endpoint's laptop to do on the connection it holds now** —
    /// `true` for `pause`, `false` for `resume`. **Absent means nothing has been asked yet, which is
    /// not the same as "not paused"**: a pause belongs to the connection that asked for it, but a
    /// laptop that outlived that connection (an iPad locked in the background, a Wi-Fi drop) may still
    /// hold it, and the new connection cannot tell. So the first reconcile after a connect says the
    /// wish outright, either way, instead of assuming the laptop starts where this end expects it.
    /// Cleared by every transition out of `.connected`.
    private var askedPause: [StreamEndpoint: Bool] = [:]
    /// The connect sheet's pending question, one per endpoint: resolved by the first STATUS after
    /// HELLO, or by the first failure.
    private var pendingConnects: [StreamEndpoint: [CheckedContinuation<StreamStatus, Error>]] = [:]

    private var tickScheduled = false
    private var lastTick: CFAbsoluteTime = 0
    private var lastPublish: CFAbsoluteTime = 0
    private var isInBackground = false
    /// Whether the tick was held off (`tickIsSuppressed`) the last time anything looked — so the edge
    /// out of it can arm one.
    private var tickWasSuppressed = false
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
            clients.removeValue(forKey: endpoint)
            connectionStates.removeValue(forKey: endpoint)
            askedPause.removeValue(forKey: endpoint)
            // The ping-pong fix's collapse can leave two keys pointing at one client; stop the
            // socket only once nothing wanted still shares it, or an ambient connection and a
            // stream element naming the same laptop differently would have one of them silently
            // kill the other's only live connection.
            let stillWanted = wanted.contains { clients[$0] === client }
            if !stillWanted { client.stop() }
        }
        syncPauseState()
        tickSuppressionMayHaveEnded()
    }

    /// Stops every client and forgets every status. The document is closing.
    func stopAll() {
        for client in clients.values { client.stop() }
        clients.removeAll()
        statuses.removeAll()
        connectionStates.removeAll()
        askedPause.removeAll()
        for (endpoint, continuations) in pendingConnects {
            for continuation in continuations {
                continuation.resume(throwing: ConnectFailure(reason: .other("The document was closed."),
                                                              host: endpoint.host))
            }
            pendingConnects.removeValue(forKey: endpoint)
        }
    }

    // MARK: - The connect sheet's question

    /// TODO.md item (101): the sheet's own answer when a connect attempt fails, carrying the
    /// classification rather than a pre-rendered string — `sentence` renders it against the host the
    /// artist typed, and `offersLocalNetworkSettingsButton` is what tells the sheet to show the
    /// Settings button rather than reasoning about the failure a second time.
    struct ConnectFailure: Error, Equatable {
        let reason: StreamConnectFailure
        let host: String
        var sentence: String { reason.sentence(host: host) }
        var offersLocalNetworkSettingsButton: Bool { reason.offersLocalNetworkSettingsButton }
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
            if let client = clients[endpoint] {
                // Revives a client parked in `.replaced` (the ping-pong fix's "an evicted client
                // does not fight back" state) or `.stopped` — a no-op on anything already trying or
                // live. Without this, tapping the address button to reconnect an endpoint the
                // server had evicted would register a continuation nothing ever resolves.
                // `startsClients` gate matches `startClient(for:)`'s own: nothing here opens a real
                // socket under `CanvasFixture`, which drives this same window with
                // `stateChanged`/`statusArrived` instead (see that property's own doc comment).
                if startsClients { client.start() }
            } else {
                startClient(for: endpoint)
            }
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
        client.onFailure = { [weak self] reason in
            self?.failureArrived(reason, from: endpoint)
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
    /// `AddMenu.insertVideo`'s own reason: the temp file is this transfer's own copy, ours to
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
        // Broadcast to every spelling collapsed onto the same client (the ping-pong fix): the
        // client's own callback always reports under whichever endpoint it was originally started
        // for, so without this an element naming the *other* spelling would read this connection's
        // last STATUS forever once the two folded together.
        for alias in aliasedEndpoints(sharing: endpoint) {
            statuses[alias] = status
            applyStatusToElements(status, endpoint: alias)
        }
        if let continuations = pendingConnects.removeValue(forKey: endpoint) {
            for continuation in continuations { continuation.resume(returning: status) }
        }
    }

    /// Every endpoint spelling currently sharing `endpoint`'s client — always at least `[endpoint]`
    /// itself. **The ping-pong fix's bookkeeping seam**: once `collapseIfSameMachine` folds a second
    /// spelling of one laptop onto the first client that reached it (§6: the document's ambient
    /// connection and a stream element naming the same machine differently), `clients` holds two
    /// keys pointing at one `ScreenStreamClient` instance — every reader keyed by endpoint
    /// (`statusArrived`, `stateChanged`, `syncPauseState`) must resolve through every alias, not
    /// just the one the client's own callback happens to report under, or the *other* spelling's
    /// bar/pause state would freeze at whatever it last was the moment before the fold.
    private func aliasedEndpoints(sharing endpoint: StreamEndpoint) -> [StreamEndpoint] {
        guard let client = clients[endpoint] else { return [endpoint] }
        let aliases = clients.compactMap { $0.value === client ? $0.key : nil }
        return aliases.isEmpty ? [endpoint] : aliases
    }

    /// **The ping-pong fix's root cause, STREAM.md §3/§6.** The laptop is one machine reachable
    /// under several `StreamEndpoint` spellings (its Tailscale IP, its MagicDNS name, its `.ts.net`
    /// FQDN, its mDNS `.local` name) that the model cannot tell apart before a HELLO answers — so a
    /// document naming two of them (its ambient last-used connection and a stream element spelled
    /// differently, say) used to open two sockets to the one laptop, and a single-client server
    /// (`ProtocolServer`) answers that by evicting whichever it already had, forever: each eviction
    /// is an ordinary-looking disconnect to the loser, which reconnects and evicts the winner right
    /// back. Run every time a client reaches `.connected` (so a HELLO's `machineID` is known):
    /// if another live client already claims the same id under a different spelling, that other
    /// spelling is folded onto *this* one — the client that just connected survives, matching what
    /// the server itself just did (`ProtocolServer.AcceptLoopAsync`: "new connection replaces
    /// previous client", the newest always wins) — and the older socket is stopped outright, not
    /// merely marked unwanted, so its own reconnect loop cannot fire on the close the server is
    /// about to send it anyway.
    ///
    /// Endpoints that fail to collapse pre-connect (no way to know two spellings are one machine
    /// before *something* answers) still converge here within one HELLO round trip — the defect
    /// this fixes is a forever loop, not a single extra connection attempt.
    private func collapseIfSameMachine(newEndpoint: StreamEndpoint) {
        guard let newClient = clients[newEndpoint], let machineID = newClient.remoteMachineID else { return }
        for (otherEndpoint, otherClient) in clients {
            guard otherEndpoint != newEndpoint, otherClient !== newClient,
                  otherClient.remoteMachineID == machineID else { continue }
            otherClient.stop()
            clients[otherEndpoint] = newClient
            connectionStates[otherEndpoint] = connectionStates[newEndpoint]
            statuses[otherEndpoint] = statuses[newEndpoint]
            askedPause.removeValue(forKey: otherEndpoint)
            // A `connect(to: otherEndpoint)` in flight (the sheet's own narrow window, §6) would
            // otherwise wait on a continuation nothing can ever resolve: `otherClient` is stopped
            // and will not call back again, and `newClient`'s own callbacks only ever report under
            // `newEndpoint`. Migrating it here means the very next STATUS answers it, exactly as
            // if it had been registered under `newEndpoint` from the start.
            if let migrated = pendingConnects.removeValue(forKey: otherEndpoint) {
                pendingConnects[newEndpoint, default: []].append(contentsOf: migrated)
            }
        }
    }

    private func failureArrived(_ reason: StreamConnectFailure, from endpoint: StreamEndpoint) {
        guard let continuations = pendingConnects.removeValue(forKey: endpoint) else { return }
        for continuation in continuations {
            continuation.resume(throwing: ConnectFailure(reason: reason, host: endpoint.host))
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
        // Broadcast before collapsing: pre-collapse, `endpoint` is its own only alias, so this sets
        // exactly the one entry the transition is actually about. `collapseIfSameMachine` below
        // handles copying `.connected` onto whatever it folds in.
        for alias in aliasedEndpoints(sharing: endpoint) {
            if state == .stopped {
                connectionStates.removeValue(forKey: alias)
            } else {
                connectionStates[alias] = state
            }
        }
        switch state {
        case .connected:
            collapseIfSameMachine(newEndpoint: endpoint)
            syncPauseState()
        case .reconnecting, .connecting, .stopped, .replaced:
            for alias in aliasedEndpoints(sharing: endpoint) { askedPause.removeValue(forKey: alias) }
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
        everyElementIsFrozen(atAnyOf: [endpoint])
    }

    /// As above, but true of an element naming *any* of `endpoints` — the ping-pong fix's
    /// `syncPauseState` calls this with every alias of one client, because a stream element can
    /// name the machine under a different spelling than the client's own endpoint (the one its
    /// callback happens to report under) once two spellings have collapsed onto it; asking only
    /// about the client's own spelling would silently miss that element's own frozen flag.
    private func everyElementIsFrozen(atAnyOf endpoints: [StreamEndpoint]) -> Bool? {
        guard let manager else { return nil }
        var sawOne = false
        for layer in manager.layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsStream else { continue }
                for stream in vector.streams
                where endpoints.contains(StreamEndpoint(host: stream.host, port: stream.port)) {
                    sawOne = true
                    if !stream.isFrozen { return false }
                }
            }
        }
        return sawOne ? true : nil
    }

    /// **Says to every connected laptop what this end wants from it — `pause` when nothing needs its
    /// pictures, `resume` when something does — and says it again only when the wish changes.**
    /// Idempotent: it compares against `askedPause`, so calling it on every event that could change
    /// the answer costs nothing when nothing did. `.connected` calls back in here, so the first
    /// reconcile of every connection states the wish outright (`askedPause`'s note: a laptop's pause
    /// can outlive the connection that asked for it, and a connection cannot see that).
    ///
    /// The decoder is reset when a `resume` lifts a pause this end asked for, rather than on the
    /// `pause`: §3 has the laptop restart with a keyframe, and a reset here makes that keyframe the
    /// first thing decoded — where a reset on `pause` would turn any access unit still in flight into
    /// a keyframe *request*, which the fake streamer answers by restarting the very pipeline the
    /// pause just stopped. A first `resume` on a connection resets nothing: `connect()` already did.
    ///
    /// **A connection nothing names is paused, and the one exception is the sheet's own window.**
    /// Between `connect(to:)` being called and the element the sheet goes on to insert, nothing
    /// names the endpoint yet, and a `pause` there was a `pause`/`resume` pair four milliseconds apart
    /// on every Stream Screen connect — each a pipeline restart on the laptop. `pendingConnects`
    /// holds a continuation only for that span (STATUS or failure resolves it), and is never true of
    /// a document's ambient connection (`documentEndpoint`), which nothing calls `connect(to:)` for
    /// and which therefore reads as paused, so the laptop does not encode for a canvas nobody shows.
    private func syncPauseState() {
        // **Per unique client, not per dictionary key.** Once the ping-pong fix's
        // `collapseIfSameMachine` has folded two spellings of one laptop onto one client, `clients`
        // holds two keys for that one instance — iterating keys directly would ask
        // `everyElementIsFrozen` two different (and possibly contradictory) questions about the
        // very same socket and could send it a `pause` immediately followed by a `resume` in the
        // same pass. Ask once per client, over the union of every endpoint naming it.
        var handled = Set<ObjectIdentifier>()
        for (endpoint, client) in clients {
            let id = ObjectIdentifier(client)
            guard !handled.contains(id) else { continue }
            handled.insert(id)
            let aliases = aliasedEndpoints(sharing: endpoint)
            // **Nothing can be said to a laptop this end is not connected to, and nothing is recorded
            // as said.** `ScreenStreamClient.send` drops a command with no live connection, so a
            // wish noted down here while reconnecting would stand in for one the laptop never heard —
            // MEASURED in `StreamLiveUITests`: backgrounded (pause), socket dropped, one canvas pass
            // while reconnecting wrote "paused" into the mirror, the foreground wrote "resumed", and
            // the new connection found its wish already "asked" and sent nothing to a laptop that
            // still held the old pause. `.connected` comes back through here once there is one.
            guard aliases.contains(where: { connectionStates[$0] == .connected }) else { continue }

            // Paused for the background, for the artist having frozen everything on it, or for
            // nothing naming it at all.
            let wantsPaused: Bool
            if isInBackground {
                wantsPaused = true
            } else if let allFrozen = everyElementIsFrozen(atAnyOf: aliases) {
                wantsPaused = allFrozen
            } else if aliases.contains(where: { pendingConnects[$0] != nil }) {
                continue    // about to be claimed by the sheet's own insert: say nothing, do not flap
            } else {
                wantsPaused = true
            }
            let asked = aliases.lazy.compactMap { self.askedPause[$0] }.first
            guard asked != wantsPaused else { continue }
            for alias in aliases { askedPause[alias] = wantsPaused }

            if wantsPaused {
                client.pause()
                sentControlCommands.append((endpoint, .pause))
                continue
            }
            if asked == true { client.decoder.reset() }
            client.resume()
            sentControlCommands.append((endpoint, .resume))
            // The laptop's STATUS after `resume` is on its way; until it lands the stored one still
            // says "Paused by client", which is a pause this end has just lifted. Say so.
            if asked == true, var status = statuses[endpoint], !status.streaming {
                status.streaming = true
                status.reason = nil
                for alias in aliases { statuses[alias] = status }
            }
        }
    }

    /// Runs after `CanvasManager.setStreamFrozen` has written the flag. `unfroze` is whether the
    /// change was a Freeze → Unfreeze: §5.4 asks for a keyframe on unfreeze, and `resume` carries
    /// one by §3, so the explicit request goes out only when the connection was not paused.
    func elementFrozenStateChanged(endpoint: StreamEndpoint, unfroze: Bool) {
        let wasPaused = askedPause[endpoint] == true
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
        case .none, .connecting?, .stopped?:
            return .connecting
        case .reconnecting(let reason)?:
            // TODO.md item (101): the bar reads the same classification the sheet does, rather than
            // a bare "Reconnecting…" that says nothing about why.
            return .reconnecting(detail: reason.sentence(host: element.host))
        case .replaced?:
            // The ping-pong fix: the server evicted this connection for another one and said so —
            // the artist did not do this, and unlike `.reconnecting` nothing here is retrying on
            // its own, so the word must not read like an ordinary drop.
            return .pausedByOther
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
        guard let manager, !tickIsSuppressed else { return }
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

    /// STREAM.md §2.9's playback and the background: the two states the tick stands down in.
    private var tickIsSuppressed: Bool { manager?.isPlaying == true || isInBackground }

    /// **Arms a tick on every edge out of `tickIsSuppressed`.** The tick is armed by a frame's arrival
    /// and by nothing else, and a frame that lands while it stands down is held in the decoder's slot
    /// with no tick to carry it — a laptop whose screen then stays still sends no further frame to
    /// arrive, so the picture on the canvas would stay one the computer no longer shows until the
    /// screen next changed. Run from `sync()`, which a canvas pass makes when playback stops, and from
    /// the foreground notification.
    private func tickSuppressionMayHaveEnded() {
        let suppressed = tickIsSuppressed
        defer { tickWasSuppressed = suppressed }
        if tickWasSuppressed, !suppressed { frameArrived() }
    }

    private func latestFrame(for endpoint: StreamEndpoint) -> (index: Int, image: CGImage)? {
        if let frameSourceOverride { return frameSourceOverride(endpoint) }
        return clients[endpoint]?.decoder.latestImage()
    }

    // MARK: - Background

    private func appDidEnterBackground() {
        isInBackground = true
        syncPauseState()
        tickSuppressionMayHaveEnded()
    }

    private func appWillEnterForeground() {
        isInBackground = false
        // `resume` carries a keyframe by §3, so nothing here asks for a second one; an endpoint
        // every element of which is frozen stays paused, which is what the artist left it as.
        syncPauseState()
        tickSuppressionMayHaveEnded()
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
    /// `detail` is `StreamConnectFailure.sentence(host:)` — TODO.md item (101): the bar says *why*,
    /// the same classification `StreamConnectSheet`'s own banner reads, rather than a bare ellipsis.
    case reconnecting(detail: String)
    /// Connected, but STATUS says `streaming:false` — nothing picked, paused, or the window closed.
    case notStreaming(reason: String)
    /// **The ping-pong fix.** The server evicted this connection for another one — a different
    /// device, or (before `collapseIfSameMachine` catches it) this same document's own other
    /// spelling of the laptop — and said so before closing the socket. Unlike `.reconnecting`, this
    /// is not retrying: the artist must reconnect deliberately (the address button), or the two
    /// would just trade the eviction back and forth forever, which is the bug this fixes.
    case pausedByOther

    var word: String {
        switch self {
        case .live: return "Live"
        case .frozen: return "Frozen"
        case .connecting: return "Connecting…"
        case .reconnecting(let detail): return "Reconnecting… \(detail)"
        case .notStreaming(let reason): return "Not streaming — \(reason)"
        case .pausedByOther: return "Paused — another connection took the stream"
        }
    }
}

/// **What the bar adds beneath the state word when the picture on the canvas is not the whole of what
/// the computer shows** — never silent. Computed by `CanvasManager.activeStreamPictureNote` and read
/// by `StreamBar`; the bar says nothing while the canvas is exactly the computer's picture.
enum StreamPictureNote: Equatable {
    /// A blend mode, mask, effect or transformation layer is in the document, so the canvas is the
    /// compositor's, and a live frame cannot go through it per frame (MEASURED at 45.8 ms a
    /// composite on CoreGraphics and 72.7 ms on Metal, Debug, 2048²: `StreamSandwichBench`). The
    /// stream is drawn live between the composite of everything below it and of everything above, by
    /// its own layer host — the picture an edit shows while its bake is on the way
    /// (`SandwichPresentation.live`) — and **Freeze is the exact picture**: the frozen frame is
    /// baked with the rest.
    case drawnPlain

    /// A transformation layer or a Move channel of the stream's own moves it, and a moved picture is
    /// drawn from a derived image the live surface cannot sit over: the stream updates when something
    /// else on the canvas is edited.
    case heldByAPose

    var sentence: String {
        switch self {
        case .drawnPlain:
            return "While live, blend modes, masks and effects are not applied. Freeze for the exact picture."
        case .heldByAPose:
            return "A pose moves this screen, so it updates only when something else on the canvas changes."
        }
    }
}
