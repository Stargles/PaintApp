import SwiftUI
import Combine
import QuartzCore

/// Tracks instantaneous frame rate via `CADisplayLink`. Deliberately does nothing at all while
/// stopped (the HUD's default state) — `start()`/`stop()` add/remove the display link itself, so
/// there's no per-frame work (and therefore no way this counter could itself be "the reason it's
/// slow") when the HUD is hidden. See `PerfHUD` below, which starts and stops it.
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

/// **The HUD's state: whether it is showing, and the monitor that runs only while it is.** Held by
/// `DrawingView`, which hands it to the two places the HUD appears — the toggle at the head of the side
/// rail and the readout over the canvas — so neither owns the other's lifetime.
///
/// Default OFF; while hidden `PerfMonitor` is fully stopped (no `CADisplayLink`, no per-frame work
/// whatsoever) — see `PerfMonitor.start`/`stop`. So "don't make it slow and intensive" can actually be
/// checked while drawing instead of just assumed.
final class PerfHUD: ObservableObject {
    @Published var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            if isVisible { monitor.start() } else { monitor.stop() }
        }
    }
    let monitor = PerfMonitor()
}

/// The HUD's switch. **It lives in the side rail's empty head, not over the canvas**: it used to be
/// an overlay on the canvas area's top-leading corner, which is exactly where every leading dropdown
/// (Actions, Select, …) opens — so it sat on the dropdown's title corner and covered the "A" of
/// "Actions" at every window size. A control that is a child of the rail has no coordinates in common
/// with a panel that opens over the canvas.
struct PerfHUDToggle: View {
    @ObservedObject var hud: PerfHUD

    var body: some View {
        Button(action: { hud.isVisible.toggle() }) {
            Image(systemName: "speedometer")
                .font(.footnote)
                .foregroundColor(hud.isVisible ? .green : .white.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityIdentifier("perfHUD.toggle")
        .accessibilityLabel(hud.isVisible ? "Performance HUD: on" : "Performance HUD: off")
    }
}

/// The HUD's numbers, tucked below the top toolbar on the leading side. Drawn **under** the dropdowns
/// (`DrawingView` orders it) and never taking a touch, so a panel that opens here covers it rather
/// than the reverse, and the switch that turns it off is never beneath anything.
struct PerfHUDReadout: View {
    @ObservedObject var hud: PerfHUD
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        if hud.isVisible {
            PerfHUDStats(monitor: hud.monitor, canvasManager: canvasManager)
        }
    }
}

private struct PerfHUDStats: View {
    @ObservedObject var monitor: PerfMonitor
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
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
