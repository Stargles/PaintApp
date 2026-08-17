import CoreGraphics
import UIKit
import simd

/// The CPU half of a lasso flood fill: turning the loop the artist drew into the seed mask the GPU
/// floods from, and deciding which colour that flood should treat as "the region I am filling".
///
/// Both are pure functions of their inputs, which is why they live here rather than inside
/// `CanvasManager+Fill` — the orientation of the mask and the choice of seed colour are the two
/// things that silently ruin a lasso fill, and both are cheap to pin down headlessly.
/// `LassoFillLogicTests` does.
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
    /// **Antialiasing off, also deliberately.** The mask is a seed for a flood and a stencil for the
    /// union that follows, both of which read it as a boolean; a half-covered edge pixel would be
    /// rounded to one side or the other anyway, and leaving it on would put a ring of ambiguous
    /// values around every loop for no benefit. The fill's own soft edge comes from `edgeOverlap`.
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

    /// The colour the flood should treat as the region — the most common colour among the reference
    /// pixels the loop encircles, as straight (non-premultiplied-aware) RGBA in 0…1.
    ///
    /// **A lasso has no tapped pixel, so this is the question a bucket fill never has to answer**, and
    /// getting it wrong inverts the tool. The flood calls a pixel a wall when it differs from the seed
    /// colour by more than the threshold; hand it the ink colour instead of the paper colour and the
    /// walls become the paper, so the fill runs along the line art and stops at the drawing. Taking
    /// the colour at the loop's centre would do exactly that whenever the artist centres their loop on
    /// a line, which is a normal thing to do when filling across one.
    ///
    /// The most common colour is the paper in every case that matters: line art is by definition a
    /// minority of the pixels in a region an artist wants filled. Colours are bucketed 4 bits per
    /// channel and the winning bucket's centre is returned, so the answer can be off by up to 1/32
    /// per channel — against a default threshold of 0.15 on a metric where ink-versus-blank-paper
    /// reads 0.5, that is not close to mattering, and it buys a single pass over the pixels.
    ///
    /// Returns transparent black for an empty mask, which is what a tap on blank paper samples.
    static func dominantColour(referenceRGBA: [UInt8], mask: [UInt8], width: Int, height: Int) -> SIMD4<Float> {
        let count = width * height
        guard count > 0, referenceRGBA.count >= count * 4, mask.count >= count else { return .zero }
        var histogram = [Int32](repeating: 0, count: 1 << 16)
        var any = false
        for i in 0..<count where mask[i] != 0 {
            let o = i * 4
            let key = (Int(referenceRGBA[o] >> 4) << 12) | (Int(referenceRGBA[o + 1] >> 4) << 8)
                | (Int(referenceRGBA[o + 2] >> 4) << 4) | Int(referenceRGBA[o + 3] >> 4)
            histogram[key] += 1
            any = true
        }
        guard any, let best = histogram.indices.max(by: { histogram[$0] < histogram[$1] }) else { return .zero }
        func channel(_ shift: Int) -> Float { (Float((best >> shift) & 0xF) * 16 + 8) / 255 }
        return SIMD4<Float>(channel(12), channel(8), channel(4), channel(0))
    }
}
