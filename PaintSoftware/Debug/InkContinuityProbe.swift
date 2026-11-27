import UIKit

/// **Whether a stroke ever leaves the screen on its way into the layer's picture** — SCHEDULER.md
/// rule 10 read off the committed layer tree rather than off a screenshot.
///
/// A screenshot is one frame in several, taken hundreds of milliseconds apart, and the owner's flicker
/// is one frame or two (TODO item 7). So this samples **every main-thread turn**: a run-loop observer
/// ordered after Core Animation's own commit observer reads a few pixels of the window's layer tree,
/// which is the state that commit just handed the render server.
///
/// The pixel is the middle of the stroke's own path, read just before the lift is processed — what the
/// pen laid down and the screen was showing. From the lift to `settleSeconds` after it, a sample that
/// has lost that ink, or shows it twice, is a committed state with the stroke wrong: a dip. (A stroke
/// whose middle was bare paper at the lift says nothing and is not counted.)
///
/// Armed by `-uiTestInkProbe` on the simulator only, and published on `canvas.host` as
/// `ink:<strokes watched>,<dips>` plus the series of the first dip.
@MainActor
enum InkContinuityProbe {

    /// How long after the lift a stroke is still watched: past the longest pen-up render the staged
    /// tests ask for (`-uiTestSlowVectorRenderMillis`) and the bake that follows it.
    static let settleSeconds: CFTimeInterval = 3

    /// How far the stroke's grey may move between the lift and the end: a dip is ink gone, a rise is
    /// ink drawn twice — a translucent stroke shows both.
    static let tolerance = 24

    static let isOn = ProjectBackupManager.isSimulator
        && ProcessInfo.processInfo.arguments.contains("-uiTestInkProbe")

    /// Told when a watched stroke is settled, so the published field is current without another pass.
    static var onChange: (() -> Void)?

    private struct Run {
        var path: [CGPoint] = []
        weak var window: UIWindow?
        var point: CGPoint?
        /// What the middle of the stroke read at the lift.
        var baseline = 0
        /// A point of bare paper well clear of the stroke, white at the lift: it must stay white.
        var paper: CGPoint?
        var lifted: CFTimeInterval = 0
        var dipped = false
        var series: [(ms: Int, gray: Int)] = []
    }

    private static var run: Run?
    private static var observer: CFRunLoopObserver?
    private static var watched = 0
    private static var dips = 0
    private static var firstDip = ""

    /// A stroke's first touch, in `window`'s coordinates.
    static func strokeBegan(at point: CGPoint, in window: UIWindow?) {
        guard isOn, let window else { return }
        settle()
        run = Run(path: [point], window: window)
    }

    static func strokeMoved(to point: CGPoint) {
        guard isOn, run?.point == nil else { return }
        run?.path.append(point)
    }

    /// The lift, before anything is done about it: what the screen shows now is the stroke.
    static func strokeLifting() {
        guard isOn, var current = run, current.point == nil, let window = current.window else { return }
        let point = current.path[current.path.count / 2]
        let baseline = pixel(at: point, in: window)
        guard baseline < 200 else { run = nil; return }
        current.baseline = baseline
        current.point = point
        let clear = CGPoint(x: point.x, y: point.y + 140)
        if pixel(at: clear, in: window) > 240 { current.paper = clear }
        current.lifted = CACurrentMediaTime()
        run = current
        watched += 1
        // Idle after the settle there is no turn to end the run, so one is made.
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds + 0.1) { settleIfDue() }
        guard observer == nil else { return }
        // After Core Animation's commit observer (order 2,000,000), so what is read is what was committed.
        let created = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 2_100_000) { _, _ in
            MainActor.assumeIsolated { sample() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
    }

    /// The `ink:` field.
    static var field: String {
        "\(watched),\(dips)" + (firstDip.isEmpty ? "" : " inkdip:\(firstDip)")
    }

    private static func sample() {
        guard var current = run, let point = current.point, let window = current.window else { return }
        let gray = pixel(at: point, in: window)
        current.series.append((Int((CACurrentMediaTime() - current.lifted) * 1000), gray))
        if abs(gray - current.baseline) > Self.tolerance { current.dipped = true }
        if let paper = current.paper, pixel(at: paper, in: window) < 200 { current.dipped = true }
        run = current
        settleIfDue()
    }

    private static func settleIfDue() {
        guard let current = run, current.point != nil,
              CACurrentMediaTime() - current.lifted > settleSeconds else { return }
        settle()
    }

    private static func settle() {
        guard let current = run else { return }
        run = nil
        guard current.point != nil else { return }
        defer { DispatchQueue.main.async { onChange?() } }
        guard current.dipped else { return }
        dips += 1
        if firstDip.isEmpty {
            firstDip = current.series.map { "\($0.ms):\($0.gray)" }.joined(separator: ",")
        }
    }

    /// The window's layer tree, drawn at `point`: a grey value, white where nothing is drawn — the
    /// mean of a 3×3 patch, so one texture pixel of a rough edge is not a verdict.
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
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 255 }
        let bpp = cg.bitsPerPixel / 8
        var sum = 0
        for y in 0..<3 { for x in 0..<3 {
            let o = y * cg.bytesPerRow + x * bpp
            sum += Int(bytes[o]) + Int(bytes[o + 1]) + Int(bytes[o + 2])
        } }
        return sum / 27
    }
}
