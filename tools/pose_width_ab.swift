// pose_width_ab.swift — the measurement behind KEYFRAMES.md §8's width-rule paragraph.
//
// The question: under a non-uniform map, can the path that ships today give a stroke the width
// LASSO_MOVE.md §5.17's `sqrt(|det|)` rule asks for, and is it exact or only exact at the
// similarity limit? Answered for the two poses KEYFRAMES §3.3 stores from day one — a uniform /
// similarity pose and a Freeform stretch — and separately for the projective case stage 5b adds.
//
//   swiftc -O tools/pose_width_ab.swift PaintSoftware/Engine/Deform/Quad.swift \
//          PaintSoftware/Engine/Deform/Homography.swift -o /tmp/posewidth && /tmp/posewidth
//
// `Quad` and `Homography` are the app's own sources, compiled unmodified. Everything below is
// copied verbatim from the shipped function named above it, so the numbers are the app's own.

import CoreGraphics
import Foundation

// ObjectTransformFrame.axisScales(scale:aspect:)
func axisScales(scale: CGFloat, aspect: CGFloat) -> (x: CGFloat, y: CGFloat) {
    let half = sqrt(aspect)
    return (scale * half, scale / half)
}

// VectorCanvas.affine(from:aspect:stretchAxis:pivot:)
func affine(position: CGPoint, scale: CGFloat, rotation: CGFloat,
            aspect: CGFloat, stretchAxis: CGFloat, pivot: CGPoint) -> CGAffineTransform {
    let s = axisScales(scale: scale, aspect: aspect)
    let placed = CGAffineTransform.identity.translatedBy(x: position.x, y: position.y)
    let linear: CGAffineTransform
    if stretchAxis == 0 || aspect == 1 {
        linear = placed.rotated(by: rotation).scaledBy(x: s.x, y: s.y)
    } else {
        linear = placed.rotated(by: rotation + stretchAxis)
            .scaledBy(x: s.x, y: s.y)
            .rotated(by: -stretchAxis)
    }
    return linear.translatedBy(x: -pivot.x, y: -pivot.y)
}

// VectorCanvas.mapping(_:throughStretch:) — the scalar it multiplies `VectorStroke.size` by.
func stretchWidthScale(_ t: CGAffineTransform) -> CGFloat { sqrt(abs(t.a * t.d - t.b * t.c)) }
// VectorCanvas.mapping(_:throughSimilarity:) — the same number wherever the two overlap.
func similarityWidthScale(_ t: CGAffineTransform) -> CGFloat { hypot(t.a, t.b) }

// BrushStamper.stampSpacing, including the 1 pt floor.
func stampSpacing(brushSize: CGFloat, spacingFraction: CGFloat) -> CGFloat {
    max(brushSize * spacingFraction, 1)
}

// BrushStamper.advance's step count, summed over a whole sample list — the dab walk.
func dabCount(_ pts: [CGPoint], brushSize: CGFloat, spacingFraction: CGFloat) -> Int {
    let spacing = stampSpacing(brushSize: brushSize, spacingFraction: spacingFraction)
    var count = 1                       // the first sample always stamps
    var last = pts[0]
    for p in pts.dropFirst() {
        let dx = p.x - last.x, dy = p.y - last.y
        let d = hypot(dx, dy)
        guard spacing > 0, d >= spacing else { continue }
        let steps = Int(d / spacing)
        count += steps
        let covered = (CGFloat(steps) * spacing) / d
        last = CGPoint(x: last.x + dx * covered, y: last.y + dy * covered)
    }
    return count
}

struct Pose { let name: String; let scale: CGFloat; let rot: CGFloat; let aspect: CGFloat; let axis: CGFloat }

@main
struct PoseWidthAB {

    static let restSamples: [CGPoint] = (0...40).map {
        CGPoint(x: 100 + CGFloat($0) * 20, y: 150 + CGFloat($0) * 17)
    }
    static let pivot = CGPoint(x: 500, y: 500)

    static let poses: [Pose] = [
        Pose(name: "Uniform  k=1",                   scale: 1.0, rot: 0.0,  aspect: 1.0,     axis: 0.0),
        Pose(name: "Uniform  k=2.5, rot 0.7",        scale: 2.5, rot: 0.7,  aspect: 1.0,     axis: 0.0),
        Pose(name: "Uniform  k=0.3, rot -1.9",       scale: 0.3, rot: -1.9, aspect: 1.0,     axis: 0.0),
        Pose(name: "Freeform axis-aligned 3:1",      scale: 1.0, rot: 0.0,  aspect: 3.0,     axis: 0.0),
        Pose(name: "Freeform axis-aligned 1:3",      scale: 1.0, rot: 0.0,  aspect: 1.0 / 3, axis: 0.0),
        Pose(name: "Freeform 4:1 + scale 1.7 + rot", scale: 1.7, rot: 0.9,  aspect: 4.0,     axis: 0.0),
        Pose(name: "Freeform hand-turned axis 0.6",  scale: 1.7, rot: 0.9,  aspect: 4.0,     axis: 0.6),
        Pose(name: "Freeform hand-turned axis -1.2", scale: 0.8, rot: -0.4, aspect: 6.0,     axis: -1.2),
    ]

    /// What each dab would want if the width were resolved per dab: the map's local area root there.
    static func perDabIdealWidths(_ h: Homography, at points: [CGPoint]) -> [CGFloat] {
        points.compactMap { h.localScale(at: $0) }
    }

    static func spread(_ xs: [CGFloat]) -> (min: CGFloat, max: CGFloat, ratio: CGFloat) {
        let lo = xs.min() ?? 0, hi = xs.max() ?? 0
        return (lo, hi, lo == 0 ? .infinity : hi / lo)
    }

    static func main() {
        affineCase()
        projectiveCase()
        theDabWalk()
        anAnimatedPose()
        throughAStoredQuad()
    }

    // MARK: - The affine case: one scalar is not an approximation, it is the whole answer

    static func affineCase() {
        print("=== affine poses: sqrt(|det|) against the per-dab local area root ===\n")
        for p in poses {
            let t = affine(position: pivot, scale: p.scale, rotation: p.rot,
                           aspect: p.aspect, stretchAxis: p.axis, pivot: pivot)
            let shipped = stretchWidthScale(t)
            let ideal = perDabIdealWidths(Homography(t), at: restSamples)
            let s = spread(ideal)
            let worst = ideal.map { abs($0 - shipped) }.max() ?? 0
            print(String(format: "%-30@ sqrt|det| %.15f  == pose.scale? %@", p.name as NSString,
                         shipped, abs(shipped - p.scale) <= 1e-15 * max(1, p.scale) ? "YES" : "no"))
            print(String(format: "   per-dab local scale over %d samples: max/min %.17f, worst |ideal - scalar| %.3e",
                         restSamples.count, s.ratio, worst))
            if p.aspect == 1 {
                print(String(format: "   hypot(a,b) [similarity arm] differs by %.3e",
                             abs(similarityWidthScale(t) - shipped)))
            }
        }
        print("")
    }

    // MARK: - The projective case: no scalar can be right

    static func projectiveCase() {
        print("=== projective poses (stage 5b's Distort) — the same question ===\n")
        let box = CGSize(width: 1000, height: 1000)
        let distorts: [(String, Quad)] = [
            ("mild keystone",   Quad(CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 180),
                                     CGPoint(x: 900, y: 820), CGPoint(x: 100, y: 900))),
            ("strong keystone", Quad(CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 400),
                                     CGPoint(x: 900, y: 600), CGPoint(x: 100, y: 900))),
            ("one corner in",   Quad(CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 100),
                                     CGPoint(x: 560, y: 520), CGPoint(x: 100, y: 900))),
        ]
        for (name, q) in distorts {
            guard let h = Homography(boxSize: box, to: q) else { print("\(name): unsolvable"); continue }
            let ideal = perDabIdealWidths(h, at: restSamples)
            let s = spread(ideal)
            // There is no |det| for a homography. The nearest thing a single scalar could be is the
            // linearisation at one point; take the stroke's midpoint, which is the kindest choice.
            let single = h.localScale(at: restSamples[restSamples.count / 2]) ?? .nan
            let worst = ideal.map { abs($0 - single) / single }.max() ?? 0
            print(String(format: "%-16@ affine() %@  local scale %.4f...%.4f (max/min %.2f)  best scalar off by %.0f%%",
                         name as NSString, h.affine() == nil ? "nil" : "yes",
                         s.min, s.max, s.ratio, worst * 100))
        }
        print("")
    }

    // MARK: - What a stretch does lose: the dab walk, not the width

    static let restSize: CGFloat = 24
    static let hardRound: CGFloat = 0.05        // BrushLibrary.hardRound.spacingFraction

    static func theDabWalk() {
        print("=== the dab walk under one pose, Hard Round spacing ===\n")
        let rest = dabCount(restSamples, brushSize: restSize, spacingFraction: hardRound)
        print("rest stroke: \(restSize) pt, \(rest) dabs")
        for p in poses.dropFirst() {
            let t = affine(position: pivot, scale: p.scale, rotation: p.rot,
                           aspect: p.aspect, stretchAxis: p.axis, pivot: pivot)
            let k = stretchWidthScale(t)
            let n = dabCount(restSamples.map { $0.applying(t) },
                             brushSize: restSize * k, spacingFraction: hardRound)
            print(String(format: "%-30@ k %.4f  dabs %4d  (%+d)", p.name as NSString, k, n, n - rest))
        }
        print("")
    }

    static func anAnimatedPose() {
        print("=== the same walk over 24 frames of an animated pose ===\n")
        for uniform in [true, false] {
            var counts: [Int] = []
            for f in 0...24 {
                let u = CGFloat(f) / 24
                let t = affine(position: pivot, scale: uniform ? 1 - 0.7 * u : 1, rotation: 0,
                               aspect: uniform ? 1 : 1 + 3 * u, stretchAxis: 0, pivot: pivot)
                counts.append(dabCount(restSamples.map { $0.applying(t) },
                                       brushSize: restSize * stretchWidthScale(t),
                                       spacingFraction: hardRound))
            }
            let changed = zip(counts, counts.dropFirst()).filter { $0 != $1 }.count
            print(uniform ? "Uniform  scale 1.0 -> 0.3" : "Freeform aspect 1:1 -> 4:1, scale held")
            print("   \(counts.first!) -> \(counts.last!) dabs, count moves on \(changed) of 24 frames")
        }
        print("")
    }

    // MARK: - Through the storage KEYFRAMES §3.3 specifies

    static func throughAStoredQuad() {
        print("=== pose stored as a quad: quad -> Homography -> affine() -> sqrt(|det|) ===\n")
        let restBox = CGRect(x: 0, y: 0, width: 800, height: 600)
        for p in poses {
            let t = affine(position: pivot, scale: p.scale, rotation: p.rot,
                           aspect: p.aspect, stretchAxis: p.axis, pivot: pivot)
            let q = Quad.rect(restBox).mapped(by: t)
            guard let h = Homography(boxSize: restBox.size, to: q), let back = h.affine() else {
                print("\(p.name): the round trip refused the quad"); continue
            }
            print(String(format: "%-30@ parallelogram %@  width scale recovered to %.3e",
                         p.name as NSString, q.isParallelogram(tolerance: Quad.epsilon) ? "yes" : "NO ",
                         abs(stretchWidthScale(back) - stretchWidthScale(t))))
        }
    }
}
