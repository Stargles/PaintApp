import Foundation
import Network
import UIKit

/// Where a streamer is: a MagicDNS name or an IP, and the `paintstream/1` port. One client per
/// endpoint per document (STREAM.md §6), shared by every stream element that names it.
nonisolated struct StreamEndpoint: Hashable, Codable {
    var host: String
    var port: UInt16

    /// STREAM.md §3's port.
    static let defaultPort: UInt16 = 47301

    /// `UserDefaults` keys for "the last laptop connected to" — `StreamConnectSheet` writes these on
    /// every connect attempt, success or not (its own prefill), and STREAM.md §6's document-level
    /// connection reads them back on document open. One shared pair rather than two copies, so the
    /// sheet and the coordinator cannot drift on the key string.
    static let lastHostDefaultsKey = "streamScreen.lastHost"
    static let lastPortDefaultsKey = "streamScreen.lastPort"

    /// The last endpoint recorded, or nil when nothing has been recorded or what is there is not a
    /// usable port.
    static func lastUsed(in defaults: UserDefaults = .standard) -> StreamEndpoint? {
        guard let host = defaults.string(forKey: lastHostDefaultsKey), !host.isEmpty else { return nil }
        let port = defaults.integer(forKey: lastPortDefaultsKey)
        guard port > 0, port <= 65535 else { return nil }
        return StreamEndpoint(host: host, port: UInt16(port))
    }
}

/// Where an inbound transfer's bytes land while they arrive, and where an outbound one is read
/// from — STREAM.md §5.8: **never memory**, a video can be hundreds of MB. Application Support for
/// `VideoImportStore`'s own reason: not evictable like `Caches`, not user-visible like `Documents`.
enum StreamTransferStore {
    /// Overridable so a test stages into its own directory — `VideoImportStore.directoryOverride`'s
    /// shape.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("StreamTransfers", isDirectory: true)
    }

    /// A fresh path for one inbound transfer, named after the sender's own file so a glance at the
    /// directory is legible, and unique so two transfers cannot collide mid-flight.
    static func makeIncomingFileURL(id: Int, name: String) -> URL {
        let root = directory
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suffix = (name as NSString).pathExtension
        let stem = "incoming-\(id)-\(UUID().uuidString)"
        return root.appendingPathComponent(suffix.isEmpty ? stem : "\(stem).\(suffix)")
    }
}

/// **The iPad's end of `paintstream/1`** — STREAM.md §5.2: one `NWConnection` per laptop, the §3
/// framing, HELLO, STATUS, PING/PONG, the reconnect loop, and the video payloads handed to an
/// `H264StreamDecoder`. Nothing in this type runs on the main thread except the four callbacks it
/// hops there for the coordinator.
///
/// ## Lifecycle
///
/// `start()` connects and keeps reconnecting — 1 s, 2 s, then 5 s forever — until `stop()`. A
/// dead connection is three missed PINGs (6 s of silence) or the transport failing; either way the
/// decoder is reset (no session state survives a reconnect, §3), the state goes to `.reconnecting`
/// and the backoff starts. `stop()` cancels everything and the client cannot be started again —
/// make a new one.
///
/// ## What the coordinator hears
///
/// - `onStateChange` on every transition — `connecting`, `connected` (HELLO exchanged),
///   `reconnecting` (with the last failure's sentence) and `stopped`.
/// - `onStatus` on every STATUS, which is where the element's `naturalSize` and label come from.
/// - `onFailure` once per failed attempt, with a sentence for the connect sheet to show.
/// - `decoder.onFrame`, on the decode queue, per decoded frame.
///
/// ## Files — STREAM.md §5.8
///
/// One transfer in flight **per direction**: an inbound FILE_BEGIN while one is already being
/// received is refused (`"A transfer is already in progress"`) without disturbing the one under
/// way, and `sendFile` refuses the same way when one send is already going out. Inbound bytes are
/// appended straight to a temp file in `StreamTransferStore`'s directory — never held in memory — and
/// FILE_END's declared size is checked against what actually arrived before anything is handed
/// onward; a mismatch is `"The file arrived incomplete"` and the temp file is deleted. A whole file
/// then goes to `onFileReceived` **on the main queue**, because inserting it means calling into
/// `CanvasManager`; the delegate's reply becomes this client's FILE_RESULT, sent back on `queue`.
nonisolated final class ScreenStreamClient {

    enum State: Equatable {
        case connecting
        case connected
        case reconnecting(lastFailure: String)
        case stopped
    }

    let endpoint: StreamEndpoint
    let decoder = H264StreamDecoder()

    /// Delivered on the main queue.
    var onStateChange: ((State) -> Void)?
    /// Delivered on the main queue.
    var onStatus: ((StreamStatus) -> Void)?
    /// Delivered on the main queue, once per failed connection attempt or dropped connection.
    var onFailure: ((String) -> Void)?

    /// STREAM.md §5.8: a whole inbound file, delivered on the main queue because routing it means
    /// calling into `CanvasManager`. Call `reply` with the outcome — it becomes FILE_RESULT, sent
    /// back on `queue`. Installed by `ScreenStreamCoordinator.startClient` on every client, started
    /// or not, so a logic test can feed frames with no socket and see the real routing run.
    var onFileReceived: ((StreamIncomingFile, @escaping (StreamFileReceiveOutcome) -> Void) -> Void)?

    /// The answer this client gave to an inbound transfer, after sending it (or after would-have,
    /// with no connection) — main queue, for a logic test with no socket to read FILE_RESULT off the
    /// wire (`StreamFileTransferLogicTests`).
    var onFileResultSent: ((StreamFileResult) -> Void)?

    /// STREAM.md §3: the greeting this build sends first.
    private let hello: StreamHello

    /// The name the *other* side's own HELLO carried — `"desktop-cbr0fl6"`, for "Saved on
    /// desktop-cbr0fl6" after a Send to Computer.
    private(set) var remoteName: String?

    private let queue = DispatchQueue(label: "PaintSoftware.ScreenStream.client", qos: .userInitiated)
    private var connection: NWConnection?
    private var parser = StreamFraming.Parser()
    private var pingTimer: DispatchSourceTimer?
    private var reconnectTimer: DispatchSourceTimer?
    private var lastReceived = DispatchTime.now()
    private var missedPings = 0
    private var attempt = 0
    private var stopped = false
    private var helloReceived = false
    private var generation = 0

    /// One inbound transfer, laptop → iPad — queue-confined, like everything else FILE_* touches.
    private struct IncomingTransfer {
        let id: Int
        let name: String
        let size: Int
        let kind: String
        let url: URL
        let handle: FileHandle
        var bytesReceived = 0
    }
    private var incomingTransfer: IncomingTransfer?

    /// One outbound transfer, iPad → laptop.
    private struct OutgoingTransfer {
        let id: Int
        let onProgress: (Int, Int) -> Void
        let completion: (StreamFileReceiveOutcome) -> Void
    }
    private var outgoingTransfer: OutgoingTransfer?
    private var nextOutgoingFileID = 1
    /// FILE_CHUNK's own cap, §3.
    static let fileChunkSize = 256 << 10

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            let state = state
            DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
        }
    }

    /// The last STATUS this connection carried, for a consumer that attaches after it arrived.
    private(set) var lastStatus: StreamStatus?

    /// Silence for this long sends a PING (§3).
    static let pingInterval: TimeInterval = 2
    /// This many unanswered PINGs is a dead connection (§3).
    static let missedPingsBeforeDead = 3
    /// The backoff, §3: 1 s, 2 s, then 5 s forever.
    static let reconnectBackoff: [TimeInterval] = [1, 2, 5]
    /// How long a single TCP connect may take before it is a failure. A Tailscale peer that is off
    /// answers nothing, and the sheet must not wait a minute to say so.
    static let connectTimeoutSeconds = 5

    init(endpoint: StreamEndpoint, appVersion: String, deviceName: String) {
        self.endpoint = endpoint
        self.hello = .fromThisApp(version: appVersion, deviceName: deviceName)
    }

    /// The app's own version string and the device's name, for the greeting. Main-actor because
    /// `UIDevice.current` is; the coordinator is the only caller.
    @MainActor
    convenience init(endpoint: StreamEndpoint) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        self.init(endpoint: endpoint, appVersion: version, deviceName: UIDevice.current.name)
    }

    deinit {
        // A client dropped without `stop()` must not keep a socket open on its own: the queue
        // holds the connection, and cancelling here is what lets the whole object go.
        connection?.cancel()
        pingTimer?.cancel()
        reconnectTimer?.cancel()
    }

    // MARK: - Control

    func start() {
        queue.async { [weak self] in
            guard let self, self.state == .stopped, !self.stopped else { return }
            self.attempt = 0
            self.connect()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.tearDownConnection()
            self.reconnectTimer?.cancel()
            self.reconnectTimer = nil
            self.state = .stopped
        }
    }

    /// Discards whatever FILE_* was in flight when the connection went away — closed, failed, or
    /// stopped. An inbound transfer's temp file is deleted (nobody is going to finish writing it);
    /// an outbound one's caller is told why rather than left waiting forever.
    private func abandonTransfers(reason: String) {
        if let transfer = incomingTransfer {
            try? transfer.handle.close()
            try? FileManager.default.removeItem(at: transfer.url)
            incomingTransfer = nil
        }
        if let transfer = outgoingTransfer {
            outgoingTransfer = nil
            let completion = transfer.completion
            DispatchQueue.main.async { completion(.refused(reason)) }
        }
    }

    func send(_ command: StreamControlCommand) {
        queue.async { [weak self] in
            self?.send(.control, payload: command.encoded)
        }
    }

    func requestKeyframe() { send(.keyframe) }
    func pause() { send(.pause) }
    func resume() { send(.resume) }

    // MARK: - Connecting (queue-confined)

    private func connect() {
        guard !stopped else { return }
        tearDownConnection()
        generation += 1
        let thisGeneration = generation
        state = attempt == 0 ? .connecting : state

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = Self.connectTimeoutSeconds
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            fail("Port \(endpoint.port) is not a valid port.")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: parameters)
        self.connection = connection
        parser = StreamFraming.Parser()
        helloReceived = false
        missedPings = 0
        lastReceived = .now()
        decoder.reset()

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self, self.generation == thisGeneration else { return }
            switch newState {
            case .ready:
                self.attempt = 0
                self.send(.hello, payload: StreamJSON.encode(self.hello))
                self.startPinging()
                self.receive(on: connection, generation: thisGeneration)
            case .failed(let error):
                self.fail(Self.sentence(for: error))
            case .waiting(let error):
                // `.waiting` is "no route yet" — Tailscale down, the laptop asleep. NWConnection
                // would sit here indefinitely; treat it as this attempt failing so the backoff
                // decides when to look again.
                self.fail(Self.sentence(for: error))
            case .cancelled:
                break
            case .setup, .preparing:
                break
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, generation thisGeneration: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 << 10) { [weak self] data, _, isComplete, error in
            guard let self, self.generation == thisGeneration else { return }
            if let data, !data.isEmpty {
                self.lastReceived = .now()
                self.missedPings = 0
                self.parser.append(data)
                do {
                    while let frame = try self.parser.next() { self.handle(frame) }
                } catch {
                    self.fail("The computer sent something this app could not read.")
                    return
                }
            }
            if let error {
                self.fail(Self.sentence(for: error))
                return
            }
            if isComplete {
                self.fail("The computer closed the connection.")
                return
            }
            self.receive(on: connection, generation: thisGeneration)
        }
    }

    /// **Exposed rather than `private`, on purpose** — STREAM.md §7 stage 4's *"the client must
    /// expose its frame handler so tests feed frames directly"*, the same shape stage 1 took for
    /// `H264StreamDecoder.feed`. A logic test builds a `StreamFrame` with `StreamFraming.encode` and
    /// calls this directly, with no `NWConnection` anywhere; production reaches it only through
    /// `receive(on:generation:)`, off a real socket.
    func handle(_ frame: StreamFrame) {
        guard let type = frame.messageType else { return }   // unknown: skipped by length
        switch type {
        case .hello:
            guard let hello = StreamJSON.decode(StreamHello.self, from: frame.payload) else {
                fail("The computer's greeting could not be read.")
                return
            }
            guard hello.proto == StreamHello.protocolVersion else {
                fail("The computer speaks paintstream version \(hello.proto); this app speaks "
                     + "\(StreamHello.protocolVersion). Update whichever is older.")
                return
            }
            helloReceived = true
            remoteName = hello.name
            state = .connected
        case .status:
            guard let status = StreamJSON.decode(StreamStatus.self, from: frame.payload) else { return }
            lastStatus = status
            DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
        case .video:
            guard let video = StreamVideoPayload(payload: frame.payload) else { return }
            decoder.feed(video)
        case .ping:
            send(.pong)
        case .pong:
            break
        case .control:
            // Laptop → iPad control is not in the protocol; ignored rather than fatal.
            break
        case .fileBegin:
            handleFileBegin(frame.payload)
        case .fileChunk:
            handleFileChunk(frame.payload)
        case .fileEnd:
            handleFileEnd(frame.payload)
        case .fileResult:
            handleFileResult(frame.payload)
        }
    }

    // MARK: - Files, laptop → iPad (queue-confined) — STREAM.md §5.8

    private func handleFileBegin(_ payload: Data) {
        guard let begin = StreamJSON.decode(StreamFileBegin.self, from: payload) else { return }
        guard incomingTransfer == nil else {
            answerFileTransfer(StreamFileResult(id: begin.id, ok: false,
                                                reason: "A transfer is already in progress"))
            return
        }
        let url = StreamTransferStore.makeIncomingFileURL(id: begin.id, name: begin.name)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            answerFileTransfer(StreamFileResult(id: begin.id, ok: false,
                                                reason: "The file could not be received."))
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? FileManager.default.removeItem(at: url)
            answerFileTransfer(StreamFileResult(id: begin.id, ok: false,
                                                reason: "The file could not be received."))
            return
        }
        incomingTransfer = IncomingTransfer(id: begin.id, name: begin.name, size: begin.size,
                                            kind: begin.kind, url: url, handle: handle)
    }

    private func handleFileChunk(_ payload: Data) {
        guard let chunk = StreamFileChunk(payload: payload),
              var transfer = incomingTransfer, chunk.id == transfer.id else { return }
        transfer.handle.write(chunk.bytes)
        transfer.bytesReceived += chunk.bytes.count
        incomingTransfer = transfer
    }

    private func handleFileEnd(_ payload: Data) {
        guard let end = StreamJSON.decode(StreamFileEnd.self, from: payload),
              let transfer = incomingTransfer, transfer.id == end.id else { return }
        incomingTransfer = nil
        try? transfer.handle.close()
        guard transfer.bytesReceived == transfer.size else {
            try? FileManager.default.removeItem(at: transfer.url)
            answerFileTransfer(StreamFileResult(id: transfer.id, ok: false,
                                                reason: "The file arrived incomplete"))
            return
        }
        let incoming = StreamIncomingFile(id: transfer.id, name: transfer.name,
                                          kind: transfer.kind, url: transfer.url)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let onFileReceived = self.onFileReceived else {
                // Unreachable in the app — the coordinator installs this on every client it makes,
                // started or not. Refuse rather than leave the laptop waiting.
                self.queue.async { self.finishIncoming(incoming, outcome: .refused(
                    "PaintApp can insert images and videos only")) }
                return
            }
            onFileReceived(incoming) { outcome in
                self.queue.async { self.finishIncoming(incoming, outcome: outcome) }
            }
        }
    }

    /// Deletes the temp file whether it was inserted or refused, and sends the answer.
    private func finishIncoming(_ file: StreamIncomingFile, outcome: StreamFileReceiveOutcome) {
        try? FileManager.default.removeItem(at: file.url)
        answerFileTransfer(StreamFileResult(id: file.id, ok: outcome.ok, reason: outcome.reason))
    }

    private func answerFileTransfer(_ result: StreamFileResult) {
        send(.fileResult, payload: StreamJSON.encode(result))
        DispatchQueue.main.async { [weak self] in self?.onFileResultSent?(result) }
    }

    // MARK: - Files, iPad → laptop (queue-confined) — STREAM.md §5.8

    /// Sends `url` as a FILE_BEGIN/CHUNK*/END, `kind` exactly as the caller names it (the extension
    /// is the export's, not this file's business). `onProgress` is called after each chunk with
    /// bytes sent so far and the total, on the main queue; `completion` carries the laptop's
    /// FILE_RESULT, or a local refusal when there is no connection, a send is already running, or
    /// the file cannot be read — all on the main queue, none of them touching the wire.
    func sendFile(url: URL, kind: String,
                  onProgress: @escaping (Int, Int) -> Void,
                  completion: @escaping (StreamFileReceiveOutcome) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.connection?.state == .ready else {
                DispatchQueue.main.async { completion(.refused("Not connected to a computer.")) }
                return
            }
            guard self.outgoingTransfer == nil else {
                DispatchQueue.main.async { completion(.refused("A transfer is already in progress")) }
                return
            }
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? Int else {
                DispatchQueue.main.async { completion(.refused("The file could not be read.")) }
                return
            }
            let id = self.nextOutgoingFileID
            self.nextOutgoingFileID += 1
            self.outgoingTransfer = OutgoingTransfer(id: id, onProgress: onProgress, completion: completion)
            self.send(.fileBegin, payload: StreamJSON.encode(
                StreamFileBegin(id: id, name: url.lastPathComponent, size: size, kind: kind)))
            var sent = 0
            while true {
                let chunk = handle.readData(ofLength: Self.fileChunkSize)
                if chunk.isEmpty { break }
                self.send(.fileChunk, payload: StreamFileChunk(id: id, bytes: chunk).encoded)
                sent += chunk.count
                DispatchQueue.main.async { onProgress(sent, size) }
            }
            try? handle.close()
            self.send(.fileEnd, payload: StreamJSON.encode(StreamFileEnd(id: id)))
        }
    }

    private func handleFileResult(_ payload: Data) {
        guard let result = StreamJSON.decode(StreamFileResult.self, from: payload),
              let transfer = outgoingTransfer, transfer.id == result.id else { return }
        outgoingTransfer = nil
        let completion = transfer.completion
        DispatchQueue.main.async {
            completion(StreamFileReceiveOutcome(ok: result.ok, reason: result.reason))
        }
    }

    private func send(_ type: StreamMessageType, payload: Data = Data()) {
        guard let connection, connection.state == .ready else { return }
        connection.send(content: StreamFraming.encode(type, payload: payload),
                        completion: .contentProcessed { _ in })
    }

    // MARK: - Keepalive (queue-confined)

    private func startPinging() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in self?.pingTick() }
        timer.resume()
        pingTimer = timer
    }

    private func pingTick() {
        guard connection?.state == .ready else { return }
        let silence = Double(DispatchTime.now().uptimeNanoseconds - lastReceived.uptimeNanoseconds) / 1e9
        guard silence >= Self.pingInterval else { return }
        if missedPings >= Self.missedPingsBeforeDead {
            fail("The computer stopped answering.")
            return
        }
        missedPings += 1
        send(.ping)
    }

    // MARK: - Failure and reconnect (queue-confined)

    private func fail(_ sentence: String) {
        guard !stopped else { return }
        tearDownConnection()
        DispatchQueue.main.async { [weak self] in self?.onFailure?(sentence) }
        state = .reconnecting(lastFailure: sentence)
        let delay = Self.reconnectBackoff[min(attempt, Self.reconnectBackoff.count - 1)]
        attempt += 1
        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.reconnectTimer = nil
            self.connect()
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func tearDownConnection() {
        pingTimer?.cancel()
        pingTimer = nil
        if let connection {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connection = nil
        generation += 1
        // §3: no session state survives a reconnect, and that includes a transfer mid-flight —
        // nobody on the other end of a torn-down socket is still writing or reading it.
        abandonTransfers(reason: "The connection was lost.")
    }

    /// A sentence for the sheet, from whatever the transport said.
    private static func sentence(for error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return "Nothing is listening at that address — is the streamer running?"
            case .ETIMEDOUT: return "The computer did not answer. Check the address and that Tailscale is up."
            case .EHOSTUNREACH, .ENETUNREACH: return "That address cannot be reached from this iPad."
            case .ECONNRESET, .EPIPE: return "The connection was dropped."
            default: return "Could not connect: \(code)."
            }
        case .dns:
            return "That name could not be looked up. Check the address."
        case .tls:
            return "Could not connect."
        @unknown default:
            return "Could not connect."
        }
    }
}
