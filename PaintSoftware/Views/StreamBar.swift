import SwiftUI

/// **The stream bar** — STREAM.md §2.3 and §5.7: the bottom-docked options bar the artist gets by
/// standing on a layer whose cel at the current frame holds a screen stream. The source's label
/// and a state word (**Live** / **Frozen** / **Reconnecting…** / **Not streaming — reason**),
/// **Freeze ⇄ Unfreeze**, **Bake Frame**, and the address the layer is pointed at, which reopens
/// `StreamConnectSheet` to point it at a different laptop.
///
/// **Shown by state, not by `activePanel`** — `DrawingView.bottomDock` reads
/// `CanvasManager.activeStreamCel`, so `canvasInteractionBegan`'s `activePanel = .none` cannot
/// close it and a two-finger pan keeps it up; the Move bar wins while a piece floats. It is the
/// first bar in the app that appears because of *what layer the artist is on*; the Move bar's
/// state-driven show (`isAnyPieceFloating`) is its model.
///
/// **It observes the coordinator, not frames.** `ScreenStreamCoordinator` publishes its connection
/// states and STATUSes — events — and never a decoded frame, so the bar re-renders on a laptop
/// coming or going and not thirty times a second.
///
/// **No control here is allowed to be pressed and do nothing.** Bake Frame with no picture yet
/// raises `CanvasNotice.streamBakeRefused` and says why; while the canvas is on the baked
/// composite the bar says in words that the live picture is held (`StreamBarState.sandwichNote`),
/// rather than leaving the artist to wonder why a Live stream is not moving.
struct StreamBar: View {
    @ObservedObject var canvasManager: CanvasManager
    @ObservedObject var coordinator: ScreenStreamCoordinator
    let layerIndex: Int
    let celIndex: Int
    let element: VectorStreamElement

    @State private var showingConnectSheet = false

    private var state: StreamBarState { coordinator.barState(for: element) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Image(systemName: "display")
                    .foregroundColor(.white.opacity(0.8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(element.sourceLabel.isEmpty ? "Screen" : element.sourceLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .accessibilityIdentifier("streamBar.sourceLabel")
                    Text(state.word)
                        .font(.caption)
                        .foregroundColor(stateColor)
                        .lineLimit(1)
                        .accessibilityIdentifier("streamBar.stateLabel")
                        .accessibilityValue(stateCode)
                }
                .frame(minWidth: 140, alignment: .leading)

                divider

                Button {
                    canvasManager.setStreamFrozen(layerIndex: layerIndex, celIndex: celIndex,
                                                  elementID: element.id, !element.isFrozen)
                } label: {
                    Label(element.isFrozen ? "Unfreeze" : "Freeze",
                          systemImage: element.isFrozen ? "play.fill" : "pause.fill")
                        .font(.subheadline)
                }
                .foregroundColor(.white)
                .accessibilityIdentifier("streamBar.freezeButton")
                .accessibilityValue(element.isFrozen ? "frozen" : "live")

                Button {
                    let outcome = canvasManager.bakeStreamFrame(layerIndex: layerIndex, celIndex: celIndex,
                                                                atFrame: canvasManager.currentFrame)
                    if case .refused(let reason) = outcome {
                        canvasManager.raise(.streamBakeRefused(reason))
                    }
                } label: {
                    Label("Bake Frame", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                }
                .foregroundColor(.white)
                .accessibilityIdentifier("streamBar.bakeFrameButton")

                divider

                Button {
                    showingConnectSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                        Text("\(element.host):\(String(element.port))")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                }
                .foregroundColor(.white.opacity(0.85))
                .accessibilityLabel("Computer address")
                .accessibilityValue("\(element.host):\(String(element.port))")
                .accessibilityIdentifier("streamBar.addressButton")

                Spacer(minLength: 0)
            }

            if canvasManager.streamPictureIsHeldByTheSandwich {
                Text(StreamBarState.sandwichNote)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("streamBar.sandwichNote")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The tick's once-a-second numbers, for a device XCUITest — see
        // `ScreenStreamCoordinator.lastTickSummary`. Invisible, never takes a touch.
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("streamBar.tickSummary")
                .accessibilityValue(coordinator.lastTickSummary)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingConnectSheet) {
            StreamConnectSheet(canvasManager: canvasManager,
                               retargeting: StreamRetarget(layerIndex: layerIndex, celIndex: celIndex,
                                                           elementID: element.id))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 24)
    }

    private var stateColor: Color {
        switch state {
        case .live: return .green
        case .frozen: return .cyan
        case .connecting, .reconnecting: return .yellow
        case .notStreaming: return .orange
        // The ping-pong fix: not retrying, and not the artist's own doing either — distinct from
        // both the yellow "trying" states and the orange "connected but told not now" one.
        case .pausedByOther: return .red
        }
    }

    /// A stable code for an XCUITest to read, beside a word that may be reworded.
    private var stateCode: String {
        switch state {
        case .live: return "live"
        case .frozen: return "frozen"
        case .connecting: return "connecting"
        case .reconnecting: return "reconnecting"
        case .notStreaming: return "notStreaming"
        case .pausedByOther: return "pausedByOther"
        }
    }
}
