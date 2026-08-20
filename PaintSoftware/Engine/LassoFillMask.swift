import CoreGraphics
import UIKit
import simd

/// The CPU half of a lasso fill: turning the loop the artist drew into the stencil the GPU works
/// inside, deriving the **ring** the collar flood seeds from, and deciding which colours that flood
/// should treat as "outside the drawing".
///
/// All pure functions of their inputs, which is why they live here rather than inside
/// `CanvasManager+Fill` — the orientation of the mask, the ring's treatment of the canvas edge and
/// the choice of reference colour are the three things that silently ruin a lasso fill, and all
/// three are cheap to pin down headlessly. `LassoFillLogicTests` does.
///
/// The algorithm these feed is specified in LASSO_FILL.md; §6 is the pixel-level statement and §1
/// names it in the literature (morphological hole filling, marked from the loop instead of the image
/// border — Krita ships it as *Enclose and Fill*).
enum LassoFillMask {

    /// Rasterizes `path` — canvas coordinates, top-left origin, y downwards, the space every
    /// on-screen path in this app is measured in — into one byte per pixel: 255 inside the loop, 0
    /// outside. Row-major, `y * width + x`, matching `MetalFillSession`'s buffers exactly.
    ///
    /// **Non-zero winding, deliberately, and it is not the default a reader would assume.** A lasso
    /// that crosses itself is the normal case, not the exception: an artist closing a loop overshoots
    /// their own start point constantly. Under the even-odd rule any patch the loop enclosed twice
    /// becomes a hole, so the artist gets an unfilled bite out of their fill exactly where they were
    /// most careful. Winding fills it solid.
    ///
    /// **Antialiasing off, also deliberately.** The mask is a stencil the GPU reads as a boolean —
    /// it bounds the collar flood (`lassoBarrier`) and it is one operand of the final intersect
    /// (`lassoInvert`); a half-covered edge pixel would be rounded to one side or the other anyway,
    /// and leaving it on would put a ring of ambiguous values around every loop for no benefit. The
    /// fill's own soft edge comes from the coverage ramp in `lassoInvert`, which reads the artwork's
    /// antialiasing rather than the loop's.
    static func rasterize(path: CGPath, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // A bare `CGContext`'s user space has its origin bottom-left with +y upwards, while row 0
            // of the buffer is the image's *top* row — so a path in top-left-origin canvas coordinates
            // lands upside down without this flip. (`PixelOps.fill` needs no equivalent because
            // `UIGraphicsImageRenderer` hands it a context UIKit has already flipped.)
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setShouldAntialias(false)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath(using: .winding)
            return true
        }
        return ok ? bytes : nil
    }

    /// The **ring**: the one-pixel collar just inside the fence — every `mask` pixel with at least one
    /// of its eight neighbours outside the mask. 255 for a ring pixel, 0 otherwise. This is the set
    /// the collar flood is seeded from (LASSO_FILL.md §6 step 2a / step 3).
    ///
    /// **A neighbour off the canvas counts as outside, and that one clause is `§4` case 10.** A loop
    /// the artist ran off the edge of the paper is clipped to the canvas by `rasterize`, which leaves
    /// a stretch of the fence that is a straight cut through the middle of the mask with nothing
    /// beyond it. Treating the clipped edge as part of the fence seeds along it, so the flood knows
    /// there is an outside there; without this the loop is *unbounded* along that stretch, nothing
    /// seeds it, and the off-canvas side wrongly fills solid. It is also what makes a loop covering
    /// the whole canvas behave — the mask's own border becomes the ring.
    ///
    /// One byte per pixel rather than a bitmask because that is what the GPU kernels read, and one
    /// pass over the mask because it runs once per gesture (the ring cannot change while the artist
    /// drags a slider), not once per re-render.
    static func ringMask(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        let count = width * height
        var ring = [UInt8](repeating: 0, count: max(count, 0))
        guard width > 0, height > 0, mask.count >= count else { return ring }
        mask.withUnsafeBufferPointer { m in
            ring.withUnsafeMutableBufferPointer { r in
                for y in 0..<height {
                    let row = y * width
                    for x in 0..<width where m[row + x] != 0 {
                        var edge = false
                        neighbours: for dy in -1...1 {
                            let ny = y + dy
                            for dx in -1...1 where dx != 0 || dy != 0 {
                                let nx = x + dx
                                if nx < 0 || ny < 0 || nx >= width || ny >= height { edge = true; break neighbours }
                                if m[ny * width + nx] == 0 { edge = true; break neighbours }
                            }
                        }
                        if edge { r[row + x] = 255 }
                    }
                }
            }
        }
        return ring
    }

    /// The colours the collar flood is allowed to walk through — LASSO_FILL.md §6 step 2a's set `C`,
    /// capped at two: **paper, plus the modal colour of the ring when that is not paper.**
    ///
    /// **A lasso has no tapped pixel, so this is the question a bucket fill never has to answer**, and
    /// getting it wrong inverts the tool. The flood calls a pixel a wall when it differs from a
    /// reference by more than the threshold, and the flood marks what must *not* be filled; hand it
    /// the ink colour alone and the paper becomes wall, so the collar runs *along* the line art and
    /// the tool holds out the drawing instead of the page.
    ///
    /// **Paper is always in the set**, so a ring that straddles a flat and the page still seeds on
    /// both sides. On this app's reference composite paper is transparent black exactly
    /// (`compositeReferenceRGBA` renders into `PixelOps.transparentFormat()`), so a clean-paper collar
    /// pixel has colour distance 0 and therefore coverage 0 — which is what keeps the ramp in
    /// `lassoInvert` from tinting the page. An opaque document whose ground is painted by a reference
    /// layer arrives here as that layer's colour and lands in the second slot instead.
    ///
    /// **The second slot is what saves §4 case 2** — a loop drawn entirely inside a solid. There the
    /// ring is all one flat colour, so that colour becomes a reference, the collar consumes the whole
    /// interior, and the tool fills nothing and says so (§7). Without it the ring would be all wall,
    /// nothing would seed, the intersect would hold out *everything*, and the gesture would dump a
    /// slab of colour over the artist's drawing — the fallback §4 case 6 explicitly refuses.
    ///
    /// **Modal, not per-pixel**, and that is what makes a loop traced along a line still work: the
    /// majority of a hand-drawn ring is paper, so ink never becomes a reference and therefore always
    /// ends up filled over. It is only when the ring is *predominantly* something else that the
    /// something else joins the set.
    ///
    /// The 4-bit-per-channel histogram is the approximation of the spec's "cluster under the
    /// tolerance metric", and `dominantColour` averages the winning bucket rather than returning its
    /// centre — which is not a refinement, it is load-bearing. See there.
    static func referenceColours(referenceRGBA: [UInt8], ring: [UInt8],
                                 width: Int, height: Int) -> (SIMD4<Float>, SIMD4<Float>?) {
        let paper = SIMD4<Float>.zero
        let modal = dominantColour(referenceRGBA: referenceRGBA, mask: ring, width: width, height: height)
        // An empty ring returns transparent black too, so this covers "no ring at all" without a
        // separate branch — and one reference is the right answer there anyway.
        return modal.w < paperAlphaEpsilon ? (paper, nil) : (paper, modal)
    }

    /// Alpha at or below which a reference colour counts as *paper* and so adds nothing to `C`.
    ///
    /// Generous on purpose: anything up to a tenth opaque is a fringe the threshold test already
    /// treats as page, and spending the second reference slot on it would cost a whole extra flood
    /// for nothing.
    static let paperAlphaEpsilon: Float = 0.1

    /// The most common colour among the pixels `mask` selects, as straight (non-premultiplied-aware)
    /// RGBA in 0…1: colours are bucketed 4 bits per channel to find the winning cluster, then **the
    /// mean of the pixels in that bucket** is returned.
    ///
    /// **The mean rather than the bucket's centre, and that is not tidiness — measured 2026-08-18, it
    /// is worth 20% opacity of wrong colour.** A bucket centre sits up to 1/32 per channel from the
    /// pixels it stands for, so opaque black comes back as (0.031, 0.031, 0.031, 0.973) rather than
    /// (0, 0, 0, 1). Under the old flood that was harmless: the error is a twentieth of the default
    /// 0.15 threshold and every pixel it mattered for was a wall either way. Under
    /// `lassoInvert`'s coverage ramp it is not, because the ramp reads the *distance itself* —
    /// `k = d / T` — so a flat that ought to be exactly on its reference scores `0.030 / 0.15 = 0.20`
    /// and the collar the tool is supposed to leave blank comes back tinted a fifth opaque across its
    /// whole area. Both of LASSO_FILL.md's fill-nothing cases were affected: a loop inside a solid
    /// (§4 case 2) painted a 20% wash over its whole interior instead of nothing.
    ///
    /// Two passes over the mask rather than one, and the second is over the ring only, which is a
    /// perimeter rather than an area.
    ///
    /// Called by `referenceColours` with the **ring**, which is the input that makes it correct — see
    /// there for why the ring and not the loop's whole interior. Returns transparent black for an
    /// empty mask, which reads as paper.
    static func dominantColour(referenceRGBA: [UInt8], mask: [UInt8], width: Int, height: Int) -> SIMD4<Float> {
        let count = width * height
        guard count > 0, referenceRGBA.count >= count * 4, mask.count >= count else { return .zero }
        func bucket(_ o: Int) -> Int {
            (Int(referenceRGBA[o] >> 4) << 12) | (Int(referenceRGBA[o + 1] >> 4) << 8)
                | (Int(referenceRGBA[o + 2] >> 4) << 4) | Int(referenceRGBA[o + 3] >> 4)
        }
        var histogram = [Int32](repeating: 0, count: 1 << 16)
        var any = false
        for i in 0..<count where mask[i] != 0 {
            histogram[bucket(i * 4)] += 1
            any = true
        }
        guard any, let best = histogram.indices.max(by: { histogram[$0] < histogram[$1] }) else { return .zero }
        var sum = SIMD4<Double>.zero
        var n = 0
        for i in 0..<count where mask[i] != 0 {
            let o = i * 4
            guard bucket(o) == best else { continue }
            sum += SIMD4<Double>(Double(referenceRGBA[o]), Double(referenceRGBA[o + 1]),
                                 Double(referenceRGBA[o + 2]), Double(referenceRGBA[o + 3]))
            n += 1
        }
        guard n > 0 else { return .zero }
        let mean = sum / (Double(n) * 255.0)
        return SIMD4<Float>(Float(mean.x), Float(mean.y), Float(mean.z), Float(mean.w))
    }

    // MARK: - The empty result's collar tint (LASSO_FILL.md §7.2)

    /// The warning hue the collar is tinted with when a loop encloses nothing, as straight
    /// (non-premultiplied) RGBA in 0…1.
    ///
    /// Orange rather than red: nothing has gone wrong with the app and the artist has not made an
    /// error, so the tint reads as *here is where the paint went* rather than as a failure. The
    /// nearest shipped analogue is OpenToonz's Gap Check, which highlights closeable gaps in magenta;
    /// orange sits further from the blue the selection overlay already owns, so a tint and a set of
    /// marching ants on screen together are never mistaken for each other.
    ///
    /// 40% is §7.2's figure, and it is the ceiling rather than a constant brightness — the overlay
    /// fades the whole layer out from there over `LassoFillDiagnostic.duration`.
    static let collarTintColour = SIMD4<Float>(1.0, 0.45, 0.10, 0.40)

    /// Turns a **reached** mask (`MetalFillSession.lastReachedMask`) into premultiplied-last RGBA at
    /// canvas resolution: `collarTintColour` wherever the collar walked, fully transparent elsewhere.
    ///
    /// **Flat rather than proportional to anything.** The artist's question on an empty result is
    /// binary — *did the paint get here?* — and a tint that varied with the coverage ramp would fade
    /// out exactly along the antialiased fringe of the line, which is the region where the leak is
    /// hardest to see and most needs showing. A pixel is either in the escape route or it is not.
    ///
    /// Premultiplied because that is what every other buffer in this pipeline is and what
    /// `CGImageAlphaInfo.premultipliedLast` wants; building it straight would show up as a dark
    /// halo around the tint the moment it composites.
    ///
    /// Returns an empty array for a degenerate size or a mask too short to be one, so a caller that
    /// got its mask from somewhere unexpected produces no tint rather than reading past the end.
    static func collarTintRGBA(reached: [UInt8], width: Int, height: Int) -> [UInt8] {
        let count = width * height
        guard width > 0, height > 0, reached.count >= count else { return [] }
        let c = collarTintColour
        let a = UInt8(clamping: Int((c.w * 255).rounded()))
        let r = UInt8(clamping: Int((c.x * c.w * 255).rounded()))
        let g = UInt8(clamping: Int((c.y * c.w * 255).rounded()))
        let b = UInt8(clamping: Int((c.z * c.w * 255).rounded()))
        var out = [UInt8](repeating: 0, count: count * 4)
        out.withUnsafeMutableBufferPointer { o in
            for i in 0..<count where reached[i] != 0 {
                let p = i * 4
                o[p] = r; o[p + 1] = g; o[p + 2] = b; o[p + 3] = a
            }
        }
        return out
    }
}

/// What the canvas shows the artist when a lasso fill encloses nothing — LASSO_FILL.md §7 items 2
/// and 4, the two halves that are pictures rather than words.
///
/// **The banner says what happened; this says where.** §7's opening finding is that neither Krita nor
/// Clip Studio Paint gives any diagnostic when an enclosure yields nothing, and that Krita's users
/// consequently report the tool as simply not working. A sentence alone would leave this app in the
/// same place for the case that actually matters: the artist cannot tell a loop around blank paper
/// from a loop whose fill escaped through a two-pixel break in their line, and those want opposite
/// remedies. So:
///
///  * `collar` is the reached set, tinted — *the paint went everywhere shaded*. On the empty result
///    that raises this, that is the fence's whole interior, and the statement it makes is "every
///    pixel in here counted as background". See `MetalFillSession.lastReachedMask` for why it cannot
///    also be the picture of a leak, which was §7.2's original hope.
///  * `loop` is the fence the artist actually drew, redrawn (§7.4). A stylus loop closes somewhere
///    other than where its owner believed more often than one would guess, and a fence that shut
///    early explains an empty result all on its own.
///
/// Both are transient and neither is undoable, because neither is a document change: this type is
/// carried on `CanvasManager` only as far as `SelectionOverlayView`, which draws it and fades it.
///
/// **Not a `CanvasNotice`.** That is a sentence in a pill at the top of the screen; this is pixels
/// registered to the artwork, and it has to live inside the canvas's transformed container to stay
/// registered when the artist zooms. They are raised together and they are different things.
struct LassoFillDiagnostic: Identifiable {
    /// Fresh per raise, for `CanvasNotice.raise`'s reason exactly: the presenter drives its fade off
    /// this, so two consecutive empty results have to be distinguishable or the second shows nothing.
    let id: UUID
    /// The collar, at canvas resolution, already tinted — nil if the mask could not be turned into an
    /// image, in which case the loop is still worth redrawing on its own.
    let collar: UIImage?
    /// The closed loop, in canvas coordinates: the same path `beginInteractiveLassoFill` rasterised,
    /// so what is redrawn is the fence the algorithm actually used rather than a re-derivation of it.
    let loop: CGPath

    init(collar: UIImage?, loop: CGPath) {
        self.id = UUID()
        self.collar = collar
        self.loop = loop
    }

    /// How long the whole diagnostic stays on screen, in seconds — §7.2's "held for ~0.8 s and
    /// fading", and §7.4's "the same 0.8 s" for the loop.
    ///
    /// Advice to the presenter, not behaviour, for the reason `CanvasNotice.duration` is: a model
    /// that schedules its own wall-clock teardown cannot be tested without sleeping. Deliberately
    /// much shorter than the banner's 2.6 s — the sentence is there to be read, while this is there
    /// to be *glanced at* in the moment the fill failed, and a tint that outstays that reads as a
    /// rendering glitch rather than as an answer.
    static let duration: TimeInterval = 0.8

    /// The fraction of `duration` the tint holds at full strength before it starts fading. The
    /// remainder is the fade.
    ///
    /// It holds first and fades second rather than fading throughout, because the artist's eye has to
    /// *arrive* at the canvas before the information is gone — a linear fade from the first frame
    /// spends its most legible moment on a screen nobody is looking at yet.
    static let holdFraction: Double = 0.65
}
