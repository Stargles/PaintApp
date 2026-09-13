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
/// ## Files
///
/// FILE_* is stage 4. This build parses FILE_BEGIN only far enough to answer
/// `FILE_RESULT ok:false reason:"Not supported yet"`, so a drop on the laptop gets a sentence and
/// not a hang, and ignores FILE_CHUNK and FILE_END.
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

    /// STREAM.md §3: the greeting this build sends first.
    private let hello: StreamHello

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

    private func handle(_ frame: StreamFrame) {
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
            // Stage 4. Answer so the laptop's drop box shows a sentence instead of a spinner.
            let id = StreamJSON.decode(StreamFileBegin.self, from: frame.payload)?.id ?? 0
            send(.fileResult, payload: StreamJSON.encode(StreamFileResult.notSupportedYet(id: id)))
        case .fileChunk, .fileEnd, .fileResult:
            break
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
