import Foundation
import CoreGraphics

// `HANDOFF.md` §8 item 28: Generate froze for ~1 minute on a two-stroke drawing. A stroke drawn on
// an iPad carries hundreds of samples, so the number that matters is how the fit scales with sample
// count — not how it does on a two-dozen-point fixture.

func polyline(_ a: CGPoint, _ b: CGPoint, n: Int) -> [CGPoint] {
    (0...n).map { i in
        let u = CGFloat(i) / CGFloat(n)
        return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }
}

func cShape(centre c: CGPoint, radius r: CGFloat, n: Int) -> [CGPoint] {
    (0...n).map { i in
        let angle = (130 - 260 * CGFloat(i) / CGFloat(n)) * .pi / 180
        return CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
    }
}

/// Mirrors `CanvasManager.latticeCellSize(covering:)`.
func cellSize(_ p: [CGPoint]) -> CGFloat {
    max(max(p.map(\.x).max()! - p.map(\.x).min()!,
            p.map(\.y).max()! - p.map(\.y).min()!) / 10, 8)
}

print("Registration cost — a vertical line fitted to a C that encompasses it (§8 item 28).")
print("Before the ring-walk fix:  24=34ms  100=1.3s  250=12s  500=45s  1000=94s  2000=285s")
print("After it, same residuals:  24= 9ms  100=93ms  250=412ms  500=1.2s  1000=2.9s  2000=7.6s")
print("")
print("  samples      fit time     mean residual")
for n in [24, 100, 250, 500, 1000, 2000] {
    let source = polyline(CGPoint(x: 400, y: 320), CGPoint(x: 400, y: 480), n: n)
    let target = cShape(centre: CGPoint(x: 400, y: 400), radius: 200, n: n * 2)
    let rest = Lattice(covering: source, targetCellSize: cellSize(source), padding: 1)

    let started = Date()
    let fit = ARAPRegistration.fit(lattice: rest, source: source,
                                   target: PointCloudIndex(target))
    let ms = Date().timeIntervalSince(started) * 1000

    print(String(format: "  %7d   %9.0f ms   %13.3f", n, ms, Double(fit.meanResidual)))
}
print("")
print("Note the residual stops improving past ~250 samples: everything above that is paid for")
print("nothing, so subsampling the registration cloud is free accuracy-wise. The lattice is ~56")
print("vertices whatever the sample count — it is the point cloud that grows, not the solve.")
