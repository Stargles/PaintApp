import Foundation
import Network

/// **An in-process stand-in for the Windows laptop** — `Streamer.Core`'s `ProtocolServer` and
/// `StreamerSession`, as far as the iPad can tell them apart, listening on an ephemeral loopback port
/// inside the simulator so a UI test can hand the app a real `paintstream/1` peer with no ffmpeg, no
/// Python and no Mac-side process to start (`tools/stream/fake-streamer.py` is the same peer for a
/// person at a terminal; `StreamLiveUITests` takes this one so the suite owns its own streamer).
///
/// **The laptop's screen is the test's to change**, which is the point: the real streamer's capture
/// is damage-driven (STREAM.md §3), so a still screen sends *nothing*, and "the iPad shows what the
/// computer shows" can only be asserted against a screen whose every change the test chose. The
/// screen is one of three solid colours, each a one-IDR access unit (`libx264`, baseline, 320x180,
/// 245 bytes) that the app's own `H264StreamDecoder` decodes like any capture — so the pixels the
/// test reads off the canvas went through the real framing, decode, tick and present.
///
/// **What it models of `StreamerSession`**, because the bugs this exists to catch live there: a
/// capture session that starts on connect, on `resume` and on `keyframe` and delivers a first frame
/// of the screen as it is *now*; a `pause` that stops it; a lock that stops it and a unlock that
/// restarts it; one client at a time, the newest winning; and `leaksPauseAcrossConnections`, the
/// pre-fix `_pausedByClient` that outlived the connection which asked for it.
final class FakeLaptopStreamer {

    /// What the laptop's screen shows.
    enum Screen: Int, CaseIterable {
        case red, green, blue

        /// Two IDR access units per colour — consecutive IDRs of one picture carry different
        /// `idr_pic_id`s, which `libx264` alternates and a decoder is entitled to expect.
        fileprivate var accessUnits: [Data] {
            let encoded: [String]
            switch self {
            case .red:
                encoded = [
                    "AAAAAWdCwA3cFBn58BEAAAMAAQAAAwA8DxQrgAAAAAFozg8sgAAAAAFliIQEvEYoAAqLxwABKNjgAC+tJycnJycnJycnJycnJycnJycnJ11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111114A=",
            "AAAAAWdCwA3cFBn58BEAAAMAAQAAAwA8DxQrgAAAAAFozg8sgAAAAAFliIIBHxGKAAKSccAASOY4AAtrScnJycnJycnJycnJycnJycnJyddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddeA="
                ]
            case .green:
                encoded = [
                    "AAAAAWdCwA3cFBn58BEAAAMAAQAAAwA8DxQrgAAAAAFozg8sgAAAAAFliIQEvEYoAAqLxwABJ7jgACZnJycnJycnJycnJycnJycnJycnJ11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111114A=",
            "AAAAAWdCwA3cFBn58BEAAAMAAQAAAwA8DxQrgAAAAAFozg8sgAAAAAFliIIBHxGKAAKSccAASKY4AAlkycnJycnJycnJycnJycnJycnJyddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddeA="
                ]
            case .blue:
                encoded = [
                    "AAAAAWdCwA3cFBn58BEAAAMAAQAAAwA8DxQrgAAAAAFozg8sgAAAAAFliIQEvEYoAAzExwABfWjgACJDJycnJycnJycnJycnJycnJycnJ11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111114A=",
            "AAAAAWdCwA3cFBn58BEAAAMAAQAAAwA8DxQrgAAAAAFozg8sgAAAAAFliIIBHxGKAAMSMcAAW1o4AAh8ycnJycnJycnJycnJycnJycnJyddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddeA="
                ]
            }
            return encoded.compactMap { Data(base64Encoded: $0) }
        }
    }

    private let queue = DispatchQueue(label: "FakeLaptopStreamer")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var parser = StreamFraming.Parser()
    private var generation = 0
    private var variant = 0
    private let clock = DispatchTime.now()
    private let machineID = UUID().uuidString

    // The laptop's session state — queue-confined, like `StreamerSession`'s own, `_gate`-confined.
    private var screen: Screen = .red
    private var pausedByClient = false
    private var locked = false
    private var capturing = false
    private var controlLog: [String] = []
    private var connectionCount = 0
    private var frameCount = 0

    /// The pre-fix `StreamerSession`: `_pausedByClient` is the process's, so a pause the iPad asked
    /// for on one connection is still in force when the next one opens.
    private let leaksPauseAcrossConnections: Bool

    /// The ephemeral port the app is pointed at (`127.0.0.1`).
    private(set) var port: UInt16 = 0

    init(leaksPauseAcrossConnections: Bool = false) throws {
        self.leaksPauseAcrossConnections = leaksPauseAcrossConnections
        let listener = try NWListener(using: .tcp)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] incoming in self?.accept(incoming) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success, let bound = listener.port?.rawValue else {
            listener.cancel()
            throw NSError(domain: "FakeLaptopStreamer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "the listener never became ready"])
        }
        port = bound
    }

    deinit { stop() }

    func stop() {
        queue.sync {
            connection?.cancel()
            connection = nil
            listener?.cancel()
            listener = nil
        }
    }

    // MARK: - The laptop, as the test drives it

    /// **The computer's screen changed.** Sent at once if a capture session is running; a paused,
    /// locked or client-less laptop encodes nothing, exactly as the real one.
    func show(_ next: Screen) {
        queue.async { [self] in
            screen = next
            if capturing { sendFrame() }
        }
    }

    /// The laptop locks or unlocks: a lock stops the capture and says so, an unlock restarts it for a
    /// client that is there and has not paused (`SetEnvironmentBlockedAsync`).
    func setLocked(_ isLocked: Bool) {
        queue.async { [self] in
            guard locked != isLocked else { return }
            locked = isLocked
            if isLocked {
                capturing = false
            } else if connection != nil, !pausedByClient {
                startCapture()
            }
            sendStatus()
        }
    }

    /// The network drops the iPad's connection (the socket closes, the capture stops).
    func dropClient() {
        queue.async { [self] in
            connection?.cancel()
            connection = nil
            capturing = false
        }
    }

    /// What the iPad has asked for, in order — `"pause"`, `"resume"`, `"keyframe"`.
    var receivedControls: [String] { queue.sync { controlLog } }
    /// How many HELLOs the laptop has answered.
    var connections: Int { queue.sync { connectionCount } }
    /// Whether a client is connected right now.
    var hasClient: Bool { queue.sync { connection != nil } }
    /// Whether a capture session is running — the laptop is sending when the screen changes.
    var isCapturing: Bool { queue.sync { capturing } }
    /// Whether the laptop holds a pause some client asked for.
    var isPausedByClient: Bool { queue.sync { pausedByClient } }
    /// How many VIDEO frames have gone out.
    var framesSent: Int { queue.sync { frameCount } }

    // MARK: - Connection

    private func accept(_ incoming: NWConnection) {
        // One client at a time, the newest winning (`ProtocolServer.AcceptLoopAsync`).
        connection?.cancel()
        connection = incoming
        capturing = false
        generation += 1
        parser = StreamFraming.Parser()
        let thisGeneration = generation
        incoming.stateUpdateHandler = { _ in }
        incoming.start(queue: queue)
        receive(on: incoming, generation: thisGeneration)
    }

    private func receive(on incoming: NWConnection, generation thisGeneration: Int) {
        incoming.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [weak self] data, _, complete, error in
            guard let self, self.generation == thisGeneration else { return }
            if let data, !data.isEmpty {
                self.parser.append(data)
                while let frame = try? self.parser.next() { self.handle(frame) }
            }
            if error != nil || complete {
                if self.connection === incoming {
                    self.connection = nil
                    self.capturing = false
                }
                return
            }
            self.receive(on: incoming, generation: thisGeneration)
        }
    }

    private func handle(_ frame: StreamFrame) {
        switch frame.messageType {
        case .hello:
            clientConnected()
        case .control:
            guard let command = StreamControlCommand(payload: frame.payload) else { return }
            controlLog.append(command.rawValue)
            switch command {
            case .pause:
                pausedByClient = true
                capturing = false
                sendStatus(reason: "Paused by client")
            case .resume:
                pausedByClient = false
                if !capturing, !locked, connection != nil { startCapture() }
                sendStatus()
            case .keyframe:
                if capturing { startCapture() }
                sendStatus()
            }
        case .ping:
            send(StreamFraming.encode(.pong))
        default:
            break
        }
    }

    /// `OnClientConnectedAsync`: the HELLO answer, a capture session unless paused or locked, STATUS.
    private func clientConnected() {
        connectionCount += 1
        if !leaksPauseAcrossConnections { pausedByClient = false }
        send(StreamFraming.encode(.hello, payload: StreamJSON.encode(
            StreamHello(proto: StreamHello.protocolVersion, app: "PaintStreamer", version: "test",
                        name: "fake-laptop", machineID: machineID))))
        if !pausedByClient, !locked { startCapture() }
        sendStatus()
    }

    // MARK: - Sending

    /// A fresh capture session, which delivers a first frame of the screen as it is now.
    private func startCapture() {
        capturing = true
        sendFrame()
    }

    private func sendFrame() {
        let units = screen.accessUnits
        guard !units.isEmpty else { return }
        let pts = (DispatchTime.now().uptimeNanoseconds - clock.uptimeNanoseconds) / 1_000
        variant += 1
        frameCount += 1
        let payload = StreamVideoPayload(isKeyframe: true, presentationTimeMicroseconds: pts,
                                         accessUnit: units[variant % units.count])
        send(StreamFraming.encode(.video, payload: payload.encoded))
    }

    private func sendStatus(reason explicit: String? = nil) {
        let streaming = capturing
        let reason: String?
        if streaming {
            reason = nil
        } else if let explicit {
            reason = explicit
        } else if locked {
            reason = "The laptop is locked"
        } else {
            reason = pausedByClient ? "Paused" : "Starting"
        }
        let status = StreamStatus(source: StreamStatus.Source(kind: "monitor", name: "Fake screen"),
                                  width: 1280, height: 720, fps: 30, streaming: streaming, reason: reason)
        send(StreamFraming.encode(.status, payload: StreamJSON.encode(status)))
    }

    private func send(_ bytes: Data) {
        connection?.send(content: bytes, completion: .contentProcessed { _ in })
    }
}
