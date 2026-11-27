import UIKit

/// **Whether a stroke ever leaves the screen on its way into the layer's picture** — SCHEDULER.md
/// rule 10 read off the committed layer tree rather than off a screenshot.
///
/// A screenshot is one frame in several, taken hundreds of milliseconds apart, and the owner's flicker
/// is one frame or two (TODO item 7). So this samples **every main-thread turn**: a run-loop observer
/// ordered after Core Animation's own commit observer reads one pixel of the window's layer tree,
/// which is the state that commit just handed the render server. The pixel is the stroke's first
/// point — ink is laid there by the first dab and nothing the app does afterwards removes it — so the
/// stroke's own ink is always the expected value, and a *light* sample after a dark one, between
/// touch-down and `settleSeconds` after the lift, is a committed state with the stroke missing.
///
/// Armed by `-uiTestInkProbe` on the simulator only (`UITestSeeds`), and published on `canvas.host`
/// as `ink:<strokes>,<dips>` plus the series of the first dip.
@MainActor
enum InkContinuityProbe {

    /// How long after the lift a stroke is still watched: past the longest pen-up render the staged
    /// tests ask for (`-uiTestSlowVectorRenderMillis`) and the bake that follows it.
    static let settleSeconds: CFTimeInterval = 3

    static let isOn = ProjectBackupManager.isSimulator
        && ProcessInfo.processInfo.arguments.contains("-uiTestInkProbe")

    private struct Run {
        let point: CGPoint
        weak var window: UIWindow?
        let began = CACurrentMediaTime()
        var lifted: CFTimeInterval?
        var sawInk = false
        var dipped = false
        var series: [(t: Double, gray: Int)] = []
    }

    /// Told when a watched stroke is settled, so the published field is current without another pass.
    static var onChange: (() -> Void)?

    private static var run: Run?
    private static var observer: CFRunLoopObserver?
    private static var strokes = 0
    private static var dips = 0
    private static var firstDip = ""

    /// A stroke's first touch, in `window`'s coordinates.
    static func strokeBegan(at point: CGPoint, in window: UIWindow?) {
        guard isOn, let window else { return }
        finish()
        run = Run(point: point, window: window)
        strokes += 1
        guard observer == nil else { return }
        // After Core Animation's commit observer (order 2,000,000), so what is read is what was committed.
        let created = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 2_100_000) { _, _ in
            MainActor.assumeIsolated { sample() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
    }

    static func strokeEnded() {
        guard isOn, run != nil else { return }
        run?.lifted = CACurrentMediaTime()
        // Idle after the settle there is no turn to end the run, so one is made.
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds + 0.1) { finishIfSettled() }
    }

    /// The `ink:` field.
    static var field: String {
        return "\(strokes),\(dips)" + (firstDip.isEmpty ? "" : " inkdip:\(firstDip)")
    }

    private static func sample() {
        guard var current = run, let window = current.window else { return }
        let now = CACurrentMediaTime()
        let gray = pixel(at: current.point, in: window)
        let t = now - (current.lifted ?? current.began)
        current.series.append((t, gray))
        if gray < 100 { current.sawInk = true }
        else if gray > 180, current.sawInk, !current.dipped { current.dipped = true }
        run = current
        finishIfSettled()
    }

    private static func finishIfSettled() {
        guard let current = run, let lifted = current.lifted,
              CACurrentMediaTime() - lifted > settleSeconds else { return }
        finish()
    }

    private static func finish() {
        guard let current = run else { return }
        run = nil
        defer { DispatchQueue.main.async { onChange?() } }
        guard current.dipped else { return }
        dips += 1
        if firstDip.isEmpty {
            firstDip = current.series.map { String(format: "%.0f:%d", $0.t * 1000, $0.gray) }.joined(separator: ",")
        }
    }

    /// The window's layer tree, drawn at `point`: one grey value, white where nothing is drawn.
    private static func pixel(at point: CGPoint, in window: UIWindow) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 3))
            context.cgContext.translateBy(x: 1.5 - point.x, y: 1.5 - point.y)
            window.layer.render(in: context.cgContext)
        }
        guard let data = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              let cg = image.cgImage else { return 255 }
        let row = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        let offset = row + bpp
        return (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
    }
}
