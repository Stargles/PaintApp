import SwiftUI
import Combine
import QuartzCore

/// Tracks instantaneous frame rate via `CADisplayLink`. Deliberately does nothing at all while
/// stopped (the HUD's default state) — `start()`/`stop()` add/remove the display link itself, so
/// there's no per-frame work (and therefore no way this counter could itself be "the reason it's
/// slow") when the HUD is hidden. See `PerfHUDOverlay` below for the toggle that drives this.
final class PerfMonitor: ObservableObject {
    @Published private(set) var fps: Double = 0
    @Published private(set) var frameTimeMS: Double = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    // Exponential moving average so the HUD reads as a stable number instead of visibly jittering
    // every single frame (raw per-frame deltas are noisy even when drawing is perfectly smooth).
    private var smoothedFPS: Double?

    var isRunning: Bool { displayLink != nil }

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        smoothedFPS = nil
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        smoothedFPS = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }
        let delta = link.timestamp - last
        guard delta > 0 else { return }
        let instantaneous = 1.0 / delta
        let smoothed = smoothedFPS.map { $0 * 0.9 + instantaneous * 0.1 } ?? instantaneous
        smoothedFPS = smoothed
        fps = smoothed
        frameTimeMS = delta * 1000
    }

    deinit { stop() }
}

/// Toggleable, discreet FPS/frame-time HUD, so "don't make it slow and intensive" can actually be
/// checked while drawing instead of just assumed. Default OFF; while hidden `PerfMonitor` is fully
/// stopped (no `CADisplayLink`, no per-frame work whatsoever) — see `PerfMonitor.start`/`stop`.
struct PerfHUDOverlay: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var isVisible: Bool
    @StateObject private var monitor = PerfMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                toggleButton
                if isVisible {
                    hudBody
                }
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(true)
        .padding(.top, 8)
        .padding(.leading, 8)
        .onChange(of: isVisible) { _, visible in
            if visible {
                monitor.start()
            } else {
                monitor.stop()
            }
        }
    }

    private var toggleButton: some View {
        Button(action: { isVisible.toggle() }) {
            Image(systemName: "speedometer")
                .font(.footnote)
                .foregroundColor(isVisible ? .green : .white.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityIdentifier("perfHUD.toggle")
        .accessibilityLabel(isVisible ? "Performance HUD: on" : "Performance HUD: off")
    }

    private var hudBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f fps", monitor.fps))
                .font(.system(.caption, design: .monospaced).bold())
            Text(String(format: "%.1f ms/frame", monitor.frameTimeMS))
                .font(.system(.caption2, design: .monospaced))
            Text("\(canvasManager.layers.count) layers, \(totalCelCount) cels")
                .font(.system(.caption2, design: .monospaced))
        }
        .foregroundColor(.white)
        .padding(6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(6)
        .fixedSize()
        .accessibilityIdentifier("perfHUD.stats")
        .accessibilityValue(String(format: "%.0f", monitor.fps))
    }

    private var totalCelCount: Int {
        canvasManager.layers.reduce(0) { $0 + $1.cels.count }
    }
}
