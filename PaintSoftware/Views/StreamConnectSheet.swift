import SwiftUI
import UIKit

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

    /// Non-nil when the bar's address row opened this sheet: the connect re-points that element
    /// (`CanvasManager.retargetStream`) instead of inserting a new layer.
    var retargeting: StreamRetarget? = nil

    /// `UserDefaults` keys for the prefill — `StreamEndpoint.lastHostDefaultsKey`/
    /// `lastPortDefaultsKey`, so this sheet and `ScreenStreamCoordinator`'s document-level
    /// connection (STREAM.md §6) cannot drift onto two spellings of "the last laptop."
    static let lastHostKey = StreamEndpoint.lastHostDefaultsKey
    static let lastPortKey = StreamEndpoint.lastPortDefaultsKey

    @State private var host: String
    @State private var portText: String
    @State private var isConnecting = false
    @State private var failure: FailureDisplay?

    /// TODO.md item (101): what the failure banner shows — a sentence, classified or not, and
    /// whether it is worth a direct button to this app's Settings page. A local type rather than
    /// `ScreenStreamCoordinator.ConnectFailure` itself, because one failure shown here
    /// (`insertStream` reporting no picture size) is not a connection failure at all and has no
    /// `StreamConnectFailure` to classify.
    private struct FailureDisplay {
        let sentence: String
        let offersLocalNetworkSettingsButton: Bool

        init(sentence: String, offersLocalNetworkSettingsButton: Bool = false) {
            self.sentence = sentence
            self.offersLocalNetworkSettingsButton = offersLocalNetworkSettingsButton
        }

        init(_ failure: ScreenStreamCoordinator.ConnectFailure) {
            self.sentence = failure.sentence
            self.offersLocalNetworkSettingsButton = failure.offersLocalNetworkSettingsButton
        }
    }

    /// TODO (98): "Nearby" — a laptop on the same Wi-Fi as the iPad, found by DNS-SD, so the
    /// artist can tap it instead of typing an address. The typed-address path below is unchanged
    /// and is still how a Tailscale-only laptop (not on this Wi-Fi) gets connected to.
    @StateObject private var discovery = StreamDiscoveryBrowser()

    init(canvasManager: CanvasManager, retargeting: StreamRetarget? = nil) {
        self.canvasManager = canvasManager
        self.retargeting = retargeting
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
                    if discovery.nearby.isEmpty {
                        Text("No computers found nearby")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("streamConnect.nearbyEmpty")
                    } else {
                        ForEach(discovery.nearby) { streamer in
                            Button {
                                connect(to: streamer)
                            } label: {
                                Label(streamer.name, systemImage: "desktopcomputer")
                            }
                            .accessibilityIdentifier("streamConnect.nearbyRow.\(streamer.name)")
                        }
                    }
                } header: {
                    Text("Nearby")
                        .accessibilityIdentifier("streamConnect.nearbyHeader")
                } footer: {
                    Text("Computers on this Wi-Fi network that are running the streamer.")
                }

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
                        Label(failure.sentence, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            // Without `.combine`, the icon (labelled "Warning" by the system) and the
                            // sentence are two separate accessibility elements that happen to share
                            // this identifier, so VoiceOver — and an XCUITest reading `.label` — can
                            // land on either one. One element, one label: the whole sentence.
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("streamConnect.failureMessage")
                        // TODO.md item (101): Local Network permission is an iPad setting, not
                        // something retyping the address or waking the computer fixes — send the
                        // artist straight to this app's page in Settings rather than just naming it.
                        if failure.offersLocalNetworkSettingsButton {
                            Button("Open Settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                            .accessibilityIdentifier("streamConnect.openSettingsButton")
                        }
                    }
                }
            }
            .navigationTitle(retargeting == nil ? "Stream Screen" : "Change Computer")
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
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    /// A tap on a Nearby row: fill the fields from what was found and connect exactly as if the
    /// artist had typed them and pressed Connect — Nearby is a shortcut onto the same path, not a
    /// second one.
    private func connect(to streamer: NearbyStreamer) {
        host = streamer.host
        portText = String(streamer.port)
        connect()
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
                let placed: Bool
                if let retargeting {
                    placed = canvasManager.retargetStream(retargeting, host: host, port: port, status: status)
                } else {
                    placed = canvasManager.insertStream(host: host, port: port, status: status) != nil
                }
                if placed {
                    dismiss()
                } else {
                    failure = FailureDisplay(sentence: "The computer answered, but reported no picture size — pick a "
                        + "monitor or a window in the streamer and try again.")
                }
            } catch let error as ScreenStreamCoordinator.ConnectFailure {
                isConnecting = false
                failure = FailureDisplay(error)
            } catch {
                isConnecting = false
                failure = FailureDisplay(sentence: "Could not connect.")
            }
        }
    }
}
