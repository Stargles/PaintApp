import SwiftUI

/// **Actions → Stream Screen** — STREAM.md §5.7's sheet: the laptop's address, the port, Connect.
///
/// On the laptop's first HELLO+STATUS it calls `CanvasManager.insertStream(host:port:status:)` —
/// its own vector layer from the current frame to the end of the scene, fitted to the canvas,
/// lifted into the Move box — and dismisses. If the connection fails the sheet says so in one
/// sentence and stays open, with the fields as the artist typed them.
///
/// The last address used is prefilled from `UserDefaults` (`lastHostKey` / `lastPortKey`), because
/// the laptop's MagicDNS name does not change between sessions and typing `100.104.85.111` on
/// glass is the kind of thing that makes a feature go unused.
struct StreamConnectSheet: View {
    @ObservedObject var canvasManager: CanvasManager
    @Environment(\.dismiss) private var dismiss

    /// `UserDefaults` keys for the prefill.
    static let lastHostKey = "streamScreen.lastHost"
    static let lastPortKey = "streamScreen.lastPort"

    @State private var host: String
    @State private var portText: String
    @State private var isConnecting = false
    @State private var failure: String?

    init(canvasManager: CanvasManager) {
        self.canvasManager = canvasManager
        let defaults = UserDefaults.standard
        _host = State(initialValue: defaults.string(forKey: Self.lastHostKey) ?? "")
        let storedPort = defaults.integer(forKey: Self.lastPortKey)
        _portText = State(initialValue: String(storedPort > 0 ? storedPort : Int(StreamEndpoint.defaultPort)))
    }

    /// The port as typed, or nil when it is not a port.
    private var port: UInt16? {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(value) else { return nil }
        return UInt16(value)
    }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canConnect: Bool { !trimmedHost.isEmpty && port != nil && !isConnecting }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Computer's address", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { if canConnect { connect() } }
                        .accessibilityIdentifier("streamConnect.addressField")
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("streamConnect.portField")
                } header: {
                    Text("Computer")
                } footer: {
                    Text("The name or Tailscale address the streamer on the computer shows, "
                         + "for example desktop-cbr0fl6 or 100.104.85.111. The picture arrives as a new "
                         + "layer you can move like a video.")
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("streamConnect.failureMessage")
                    }
                }
            }
            .navigationTitle("Stream Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("streamConnect.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        connect()
                    } label: {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(!canConnect)
                    .accessibilityIdentifier("streamConnect.connectButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func connect() {
        guard let port, !trimmedHost.isEmpty else { return }
        let host = trimmedHost
        failure = nil
        isConnecting = true
        let defaults = UserDefaults.standard
        defaults.set(host, forKey: Self.lastHostKey)
        defaults.set(Int(port), forKey: Self.lastPortKey)
        Task { @MainActor in
            do {
                let status = try await canvasManager.streamCoordinator.connect(
                    to: StreamEndpoint(host: host, port: port))
                isConnecting = false
                if canvasManager.insertStream(host: host, port: port, status: status) != nil {
                    dismiss()
                } else {
                    failure = "The computer answered, but reported no picture size — pick a "
                        + "monitor or a window in the streamer and try again."
                }
            } catch let error as ScreenStreamCoordinator.ConnectFailure {
                isConnecting = false
                failure = error.sentence
            } catch {
                isConnecting = false
                failure = "Could not connect."
            }
        }
    }
}
