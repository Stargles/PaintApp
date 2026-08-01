import Foundation
import CoreGraphics

// `HANDOFF.md` §8 item 28: Generate froze for ~1 minute on a two-stroke drawing. A stroke drawn on
// an iPad carries hundreds of samples, so the number that matters is how the fit scales with sample
// count — not how it does on a two-dozen-point fixture.
//
// Three separate changes landed against that number and this measures all of them together:
//   - `PointCloudIndex.nearest` walks the ring instead of the (2·ring+1)² block;
//   - `Options.maxRegistrationSamples` caps what drives the fit at 250 (§8 item 35);
//   - the 1:1 arc-length correspondence, which is about quality rather than cost but is on the
//     same path and has to be measured on it (§8 item 31).

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

/// Fraction of the target with some part of the warped *polyline* within `tolerance`.
///
/// Coverage and not mean residual, because mean residual lies: the fit that piles the source onto
/// the middle of the target scores 3.6 points while covering a quarter of it (`HANDOFF.md` §5).
/// Segments and not samples, because a stroke stretched five times over carries its samples far
/// enough apart that sampling would score continuous ink as a dotted line.
func coverage(of target: [CGPoint], by warped: [CGPoint], tolerance: CGFloat) -> CGFloat {
    guard !target.isEmpty, warped.count > 1 else { return 0 }
    func distance(_ q: CGPoint) -> CGFloat {
        var best = CGFloat.infinity
        for (a, b) in zip(warped, warped.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let squared = dx * dx + dy * dy
            let u = squared > 1e-12 ? max(0, min(1, ((q.x - a.x) * dx + (q.y - a.y) * dy) / squared)) : 0
            let ex = a.x + dx * u - q.x, ey = a.y + dy * u - q.y
            best = min(best, ex * ex + ey * ey)
        }
        return best.squareRoot()
    }
    return CGFloat(target.filter { distance($0) <= tolerance }.count) / CGFloat(target.count)
}

print("Registration — a vertical line fitted to a C that encompasses it (§8 items 28/29/35).")
print("")
print("Before Phase 4.7:  24=34ms  100=1.3s  250=12s  500=45s  1000=94s  2000=285s,")
print("and the fit it spent that on covered a quarter of the target.")
print("")
print("  samples      fit time     coverage     bend      (the C's own bend is 1.072)")

for n in [24, 100, 250, 500, 1000, 2000] {
    let source = polyline(CGPoint(x: 400, y: 320), CGPoint(x: 400, y: 480), n: n)
    let target = cShape(centre: CGPoint(x: 400, y: 400), radius: 200, n: n * 2)
    let rest = Lattice(covering: source, targetCellSize: cellSize(source), padding: 1)
    // Exactly what `CanvasManager.registerWholeFrameGroup` builds.
    let cloud = PointCloudIndex(ARAPRegistration.subsampled(
        target, to: ARAPRegistration.Options().maxRegistrationSamples))
    let correspondence = ARAPRegistration.StrokeCorrespondence(source: [source], target: [target])

    let started = Date()
    let fit = ARAPRegistration.fit(lattice: rest, source: source, target: cloud,
                                   correspondence: correspondence)
    let ms = Date().timeIntervalSince(started) * 1000

    let warped = fit.lattice.warp(rest.restConfiguration.embedInRest(source))
    print(String(format: "  %7d   %9.0f ms   %10.2f   %6.3f", n, ms,
                 Double(coverage(of: target, by: warped, tolerance: 12)), Double(bendRatio(warped))))
}

func bendRatio(_ points: [CGPoint]) -> CGFloat {
    guard let a = points.first, let b = points.last else { return 0 }
    let cx = b.x - a.x, cy = b.y - a.y
    let chord = hypot(cx, cy)
    guard chord > 1e-9 else { return 0 }
    return points.map { abs(cx * (a.y - $0.y) - (a.x - $0.x) * cy) / chord }.max()! / chord
}

print("")
print("Cost is now flat in the sample count, because the cap is what the fit sees. The lattice is")
print("~56 vertices whatever the drawing brings — it was never the solve that grew, only the cloud.")
