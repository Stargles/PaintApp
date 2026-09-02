// distort_seam_ab.swift — the three measurements behind LASSO_MOVE.md §0's Distort section.
//
// All three are claims a logic test can only assert at some tolerance, and all three came out
// *exact*, which is worth being able to re-take rather than re-trusting:
//
//   1. **The seam is free.** A raster float that nobody has distorted solves through the projective
//      path to `g == h == 0` and lands its corners on the affine it has always been drawn by at
//      exactly zero error — so keeping the affine draw for it is a choice about resampling, not a
//      hedge against the solver.
//   2. **The preview is the bake.** `Homography.catransform3D`, evaluated the way Core Animation
//      evaluates it (row vectors, then the perspective divide), agrees with `Homography.map` over
//      the box interior. §5.17 accepted a *bounded* preview one stage back; this one has no gap.
//   3. **Validity is pose-independent.** `Homography.isValidQuad` asked of the piece's local quad
//      and of that quad carried through its affine pose never disagree, which is what lets
//      `FloatingDistortDrag` work in local space and a distort survive a later rotate or mirror.
//
//   swiftc -O tools/distort_seam_ab.swift PaintSoftware/Engine/Deform/Quad.swift \
//          PaintSoftware/Engine/Deform/Homography.swift -o /tmp/distortseam && /tmp/distortseam
//
// `Quad` and `Homography` are the app's own sources, compiled unmodified. `affine` and `localBox`
// below are copied verbatim from `FloatingTransform.affineTransform` and `FloatingPiece.localBox`,
// so the numbers are the app's own.

import CoreGraphics
import Foundation
import QuartzCore

let box = CGSize(width: 200, height: 120)
let boxRect = CGRect(origin: .zero, size: box)
// FloatingPiece.localBox
let centred = CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height)

// FloatingTransform.affineTransform
func affine(position: CGPoint, sx: CGFloat, sy: CGFloat, r: CGFloat,
            flipH: Bool = false, flipV: Bool = false) -> CGAffineTransform {
    CGAffineTransform.identity
        .translatedBy(x: position.x, y: position.y)
        .rotated(by: r)
        .scaledBy(x: sx * (flipH ? -1 : 1), y: sy * (flipV ? -1 : 1))
}

@main
enum DistortSeam {
    static func main() {
        seamIsFree()
        previewIsTheBake()
        validityIsPoseIndependent()
    }

// MARK: - 1. An undistorted quad is its own affine, exactly

static func seamIsFree() {
    var worst: CGFloat = 0, worstG: CGFloat = 0
    for r in stride(from: CGFloat(-3), through: 3, by: 0.25) {
        for (sx, sy) in [(CGFloat(1), CGFloat(1)), (1.4, 0.7), (0.05, 0.05), (8, 3)] {
            for (fh, fv) in [(false, false), (true, false), (false, true), (true, true)] {
                let t = affine(position: CGPoint(x: 300, y: 220), sx: sx, sy: sy, r: r,
                               flipH: fh, flipV: fv)
                let quad = Quad.rect(centred).mapped(by: t)
                guard let h = Homography(rect: boxRect, to: quad) else {
                    print("FAIL: no homography for a plain affine pose"); exit(1)
                }
                worstG = max(worstG, max(abs(h.g), abs(h.h)))
                for (index, corner) in Quad.rect(boxRect).points.enumerated() {
                    guard let mapped = h.map(corner) else {
                        print("FAIL: no image for box corner \(index)"); exit(1)
                    }
                    let direct = Quad.rect(centred)[index].applying(t)
                    worst = max(worst, hypot(mapped.x - direct.x, mapped.y - direct.y))
                }
            }
        }
    }
    print(String(format: "1. undistorted seam: worst corner error %.3e, worst |g|,|h| %.3e", worst, worstG))
}

// MARK: - 2. The CATransform3D preview is the bake's own matrix

static func previewIsTheBake() {
    var local = Quad.rect(centred)
    local.p1 = CGPoint(x: 60, y: -20)          // one corner pulled in: a real keystone
    var worst: CGFloat = 0
    for r in stride(from: CGFloat(-3), through: 3, by: 0.5) {
        for mirror in [false, true] {
            let t = affine(position: CGPoint(x: 400, y: 300), sx: 1.3, sy: 0.9, r: r, flipH: mirror)
            guard let h = Homography(rect: boxRect, to: local.mapped(by: t)) else { continue }
            let m = h.catransform3D
            for u in stride(from: CGFloat(0), through: 1, by: 0.05) {
                for v in stride(from: CGFloat(0), through: 1, by: 0.05) {
                    let p = CGPoint(x: u * box.width, y: v * box.height)
                    guard let bake = h.map(p) else { continue }
                    // Core Animation: row vectors, p' = p · M, then the divide.
                    let x = p.x * m.m11 + p.y * m.m21 + m.m41
                    let y = p.x * m.m12 + p.y * m.m22 + m.m42
                    let w = p.x * m.m14 + p.y * m.m24 + m.m44
                    guard abs(w) > 1e-12 else { continue }
                    worst = max(worst, hypot(x / w - bake.x, y / w - bake.y))
                }
            }
        }
    }
    print(String(format: "2. preview vs bake: worst disagreement over the box interior %.3e", worst))
}

// MARK: - 3. Validity does not depend on the pose

static func validityIsPoseIndependent() {
    var disagreements = 0, samples = 0
    for pull in stride(from: CGFloat(-140), through: 140, by: 7) {
        var local = Quad.rect(centred)
        local.p1 = CGPoint(x: 100 + pull, y: -60 + pull * 0.3)
        for r in stride(from: CGFloat(-3), through: 3, by: 0.5) {
            for (fh, fv) in [(false, false), (true, false), (false, true), (true, true)] {
                for s in [CGFloat(0.05), 1.0, 8.0] {
                    let t = affine(position: CGPoint(x: 10, y: 20), sx: s, sy: s * 0.6, r: r,
                                   flipH: fh, flipV: fv)
                    samples += 1
                    if Homography.isValidQuad(local, boxSize: box)
                        != Homography.isValidQuad(local.mapped(by: t), boxSize: box) {
                        disagreements += 1
                    }
                }
            }
        }
    }
    print("3. local vs canvas validity: \(disagreements) disagreements out of \(samples)")
}
}
