import UIKit
import Accelerate

/// Rasterizes a reference layer's lineart, treats it as a set of "walls," and performs a bucket-style
/// flood fill that:
///  - bridges small breaks in the lineart before flood-filling, so an open contour (common in animation
///    lineart, whether accidental or left open on purpose for drawing speed) still contains the fill
///    instead of leaking out, and
///  - grows the filled region a couple of pixels past the hard alpha boundary so the fill color sits
///    underneath the lineart's antialiased edge pixels rather than stopping short of them, which is what
///    causes the pale seam between ink and fill in a naive "stop at alpha > 0" flood fill.
///
/// All pixel buffers in this file share one coordinate convention: index 0 is the top-left pixel, y
/// increases downward (matching UIKit view coordinates and standard image row order), 1 unit = 1 pixel.
///
/// ## Performance
/// The morphology (gap closing / edge expansion) runs through Accelerate's `vImageMax`/`vImageMin`
/// box operators, which are vectorized and O(pixels) regardless of radius — orders of magnitude faster
/// than a scalar sliding-window with per-pixel closures. The wall mask is rasterized in a single
/// `CGContext` pass (no intermediate `UIImage`). Together these bring a fill on a multi-megapixel canvas
/// down from seconds to a few milliseconds, fast enough to re-run live while a slider is dragged.
///
/// A `FillSession` holds the rasterized walls and caches the intermediate flood region so that the
/// interactive "drag to adjust gap closing / edge overlap" mode (see `CanvasManager`) can recompute a
/// fill on every touch move while only re-doing the stages whose inputs actually changed.
enum FloodFillEngine {

    /// Alpha (0-255) at/above which a reference-layer pixel counts as "ink" rather than open space.
    /// Kept low so faint pencil-style strokes still register as a wall; the antialiasing seam itself is
    /// handled separately by `expandRadius`, not by raising this threshold.
    static let wallAlphaThreshold: UInt8 = 24
}

/// One layer's contribution to the fill's boundary walls: the layer and the specific cel (frame) whose
/// content should be rasterized. Callers pass these bottom-to-top (canvas draw order) so overlapping ink
/// composites the same way it renders on screen.
struct FillReferenceSource {
    let layer: Layer
    let cel: Cel
}

/// A prepared flood-fill context. The expensive step — rasterizing the reference layer into a wall mask —
/// happens once in `init`; each `fill(...)` call then closes gaps, floods, expands, and composites. Both
/// the closed-wall/flood-region and the expanded-region results are memoized against the inputs that
/// produced them, so re-running with only `expandRadius` changed skips straight to the dilation, and
/// re-running with identical parameters is nearly free.
final class FillSession {
    let width: Int
    let height: Int

    /// Raw wall mask straight from the reference raster: 255 = ink, 0 = open. Never mutated after init.
    private let wall: [UInt8]

    // Memoization of the flood stage (seed + gap closing).
    private var cachedSeed: (x: Int, y: Int)?
    private var cachedGapRadius: Int = -1
    private var cachedRegion: [UInt8]?     // flood result before edge expansion; 255 = filled
    private var cachedRegionEmpty = false  // flood produced nothing (seed on ink / sealed shut)

    // Memoization of the expansion stage.
    private var cachedExpandRadius: Int = -1
    private var cachedExpandApplied = false
    private var cachedExpandedRegion: [UInt8]?

    /// Rasterizes `references` (bottom-to-top) into a single wall mask. An empty list yields an all-open
    /// canvas (a fill then floods everything) — the caller's choice when no layer is a fill reference.
    init?(references: [FillReferenceSource], canvasSize: CGSize) {
        let w = Int(canvasSize.width.rounded())
        let h = Int(canvasSize.height.rounded())
        guard w > 0, h > 0 else { return nil }
        guard let mask = Self.rasterizeWallMask(references: references, width: w, height: h) else {
            return nil
        }
        self.width = w
        self.height = h
        self.wall = mask
    }

    /// True when `seed` (canvas-pixel coords) lands directly on ink in the raw, un-closed mask. Lets a
    /// caller decide whether a tap should begin a fill at all before doing any of the heavy work.
    func seedIsOnInk(_ seed: CGPoint) -> Bool {
        let x = Int(seed.x.rounded(.down))
        let y = Int(seed.y.rounded(.down))
        guard x >= 0, x < width, y >= 0, y < height else { return true }
        return wall[y * width + x] != 0
    }

    /// Runs (or replays from cache) a full fill and returns the composited fill raster, or nil if the
    /// reachable region is empty. `existingFill` and `fillColor` only affect the final composite, so they
    /// never invalidate the flood/expand caches.
    func fill(
        seed: CGPoint,
        fillColor: UIColor,
        existingFill: UIImage?,
        gapClosingRadius: CGFloat,
        expandRadius: CGFloat,
        applyExpand: Bool
    ) -> UIImage? {
        let seedX = Int(seed.x.rounded(.down))
        let seedY = Int(seed.y.rounded(.down))
        guard seedX >= 0, seedX < width, seedY >= 0, seedY < height else { return nil }

        let gapRadius = max(0, Int(gapClosingRadius.rounded()))
        let expand = max(0, Int(expandRadius.rounded()))

        guard let region = floodRegion(seedX: seedX, seedY: seedY, gapRadius: gapRadius) else { return nil }
        let finalRegion = expandedRegion(base: region, expand: expand, apply: applyExpand)
        return composite(existingFill: existingFill, region: finalRegion, color: fillColor)
    }

    // MARK: - Flood stage (memoized on seed + gap radius)

    private func floodRegion(seedX: Int, seedY: Int, gapRadius: Int) -> [UInt8]? {
        if let cached = cachedRegion, cachedSeed?.x == seedX, cachedSeed?.y == seedY, cachedGapRadius == gapRadius {
            return cachedRegionEmpty ? nil : cached
        }

        // Close small gaps in the lineart (dilate then erode) so an open contour still contains the fill.
        var closedWall = wall
        if gapRadius > 0 {
            Self.boxMorphology(&closedWall, width: width, height: height, radius: gapRadius, dilate: true)
            Self.boxMorphology(&closedWall, width: width, height: height, radius: gapRadius, dilate: false)
        }

        var region = [UInt8](repeating: 0, count: width * height)
        let filledAny: Bool
        if closedWall[seedY * width + seedX] != 0 {
            filledAny = false // gap-closing (or the raw ink) sealed the seed's own pixel shut
        } else {
            filledAny = Self.scanlineFloodFill(wall: closedWall, region: &region, width: width, height: height, seedX: seedX, seedY: seedY)
        }

        cachedSeed = (seedX, seedY)
        cachedGapRadius = gapRadius
        cachedRegion = region
        cachedRegionEmpty = !filledAny
        // The flood inputs changed, so any previously expanded region is stale.
        cachedExpandRadius = -1
        cachedExpandedRegion = nil

        return filledAny ? region : nil
    }

    // MARK: - Expansion stage (memoized on the base region + expand radius)

    private func expandedRegion(base: [UInt8], expand: Int, apply: Bool) -> [UInt8] {
        let effectiveExpand = apply ? expand : 0
        if let cached = cachedExpandedRegion, cachedExpandRadius == effectiveExpand, cachedExpandApplied == apply {
            return cached
        }

        var result = base
        if effectiveExpand > 0 {
            Self.boxMorphology(&result, width: width, height: height, radius: effectiveExpand, dilate: true)
        }

        cachedExpandRadius = effectiveExpand
        cachedExpandApplied = apply
        cachedExpandedRegion = result
        return result
    }

    // MARK: - Rasterizing the reference mask

    /// Draws every "wall" source of each reference cel into a single RGBA8 context (references composited
    /// bottom-to-top, matching on-screen draw order) and thresholds the alpha channel into a 0/255 mask.
    /// Deliberately excludes every layer's own `fillImage` so re-tapping an already-filled, fully enclosed
    /// region floods the whole thing with the new color instead of stopping at the leftover edge of a
    /// previous fill — flat color fills are regions, not boundaries.
    private static func rasterizeWallMask(references: [FillReferenceSource], width: Int, height: Int) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none

        // Flip into UIKit's top-left origin so UIImage.draw(in:) composites the sources the right way up,
        // matching the top-down convention every other buffer (and the seed point) uses.
        UIGraphicsPushContext(context)
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Lineart (strokes), select/move's baked raster content, and (for photo/image layers) the
        // inserted image all count as walls. Vector layers keep their strokes/images in `vector`; include
        // them so a vector layer can be filled, and can serve as a wall reference for a fill on another
        // layer (and vice versa) — a reference's kind is transparent to the flood fill this way.
        for source in references {
            let layer = source.layer
            let cel = source.cel
            if layer.isObjectLayer, let objectImage = layer.objectImage {
                objectImage.draw(in: rect)
            }
            cel.bakedImage?.draw(in: rect)
            cel.raster.renderToUIImage().draw(in: rect)
            cel.vector?.render().draw(in: rect)
        }
        context.restoreGState()
        UIGraphicsPopContext()

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        var mask = [UInt8](repeating: 0, count: width * height)
        let threshold = FloodFillEngine.wallAlphaThreshold
        // Raw-pointer stride (no bounds checks) so the per-pixel alpha threshold stays fast even in an
        // unoptimized Debug build — this runs once per fill gesture over every canvas pixel.
        mask.withUnsafeMutableBufferPointer { outBuf in
            let out = outBuf.baseAddress!
            for y in 0..<height {
                var srcOffset = y * bytesPerRow + 3   // alpha byte of column 0
                var dstOffset = y * width
                for _ in 0..<width {
                    out[dstOffset] = buffer[srcOffset] >= threshold ? 255 : 0
                    srcOffset += bytesPerPixel
                    dstOffset += 1
                }
            }
        }
        return mask
    }

    // MARK: - Morphology (gap closing / edge expansion)

    /// In-place box dilation (`dilate == true`, max) or erosion (min) with a `(2*radius+1)`-square
    /// structuring element, via Accelerate's separable, vectorized `vImageMax`/`vImageMin_Planar8`.
    /// Their O(pixels) cost is independent of radius, which matters because gap-closing radius can be
    /// dozens of pixels on a canvas up to 8192px per side. Edge pixels use whatever part of the window
    /// falls inside the image — the standard shrinking-window behavior, harmless for gap closing.
    private static func boxMorphology(_ buffer: inout [UInt8], width: Int, height: Int, radius: Int, dilate: Bool) {
        guard radius > 0, width > 0, height > 0 else { return }
        let kernel = vImagePixelCount(radius * 2 + 1)
        var scratch = [UInt8](repeating: 0, count: width * height)
        buffer.withUnsafeMutableBufferPointer { srcPtr in
            scratch.withUnsafeMutableBufferPointer { dstPtr in
                var src = vImage_Buffer(
                    data: srcPtr.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                var dst = vImage_Buffer(
                    data: dstPtr.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                let flags = vImage_Flags(kvImageNoFlags)
                if dilate {
                    vImageMax_Planar8(&src, &dst, nil, 0, 0, kernel, kernel, flags)
                } else {
                    vImageMin_Planar8(&src, &dst, nil, 0, 0, kernel, kernel, flags)
                }
                memcpy(srcPtr.baseAddress, dstPtr.baseAddress, width * height)
            }
        }
    }

    // MARK: - Flood fill

    /// Stack-based scanline flood fill: fills whole contiguous horizontal spans at a time instead of
    /// visiting every pixel individually, so it stays fast even across large open regions. `wall != 0`
    /// blocks; `region` is written 255 for filled pixels.
    private static func scanlineFloodFill(wall: [UInt8], region: inout [UInt8], width: Int, height: Int, seedX: Int, seedY: Int) -> Bool {
        guard wall[seedY * width + seedX] == 0 else { return false }
        var stack: [(x: Int, y: Int)] = [(seedX, seedY)]
        var filledAny = false

        wall.withUnsafeBufferPointer { wallBuf in
            region.withUnsafeMutableBufferPointer { regionBuf in
                while let (x0, y0) = stack.popLast() {
                    let rowBase = y0 * width
                    if regionBuf[rowBase + x0] != 0 || wallBuf[rowBase + x0] != 0 { continue }

                    var left = x0
                    while left > 0, wallBuf[rowBase + left - 1] == 0, regionBuf[rowBase + left - 1] == 0 { left -= 1 }
                    var right = x0
                    while right < width - 1, wallBuf[rowBase + right + 1] == 0, regionBuf[rowBase + right + 1] == 0 { right += 1 }
                    for x in left...right {
                        regionBuf[rowBase + x] = 255
                    }
                    filledAny = true

                    if y0 > 0 { queueSpan(row: y0 - 1, left: left, right: right, width: width, wallBuf: wallBuf, regionBuf: regionBuf, stack: &stack) }
                    if y0 < height - 1 { queueSpan(row: y0 + 1, left: left, right: right, width: width, wallBuf: wallBuf, regionBuf: regionBuf, stack: &stack) }
                }
            }
        }
        return filledAny
    }

    private static func queueSpan(row: Int, left: Int, right: Int, width: Int, wallBuf: UnsafeBufferPointer<UInt8>, regionBuf: UnsafeMutableBufferPointer<UInt8>, stack: inout [(x: Int, y: Int)]) {
        let rowBase = row * width
        var x = left
        while x <= right {
            if wallBuf[rowBase + x] != 0 || regionBuf[rowBase + x] != 0 {
                x += 1
                continue
            }
            stack.append((x, row))
            while x <= right, wallBuf[rowBase + x] == 0, regionBuf[rowBase + x] == 0 { x += 1 }
        }
    }

    // MARK: - Compositing the result

    private func composite(existingFill: UIImage?, region: [UInt8], color: UIColor) -> UIImage? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Clamped defensively: components are expected in 0...1, but floating-point round-trip through
        // color space conversions could in principle land a hair outside it, and UInt8(_:) traps on
        // out-of-range Doubles rather than clamping.
        func byte(_ value: CGFloat) -> UInt8 {
            UInt8(min(255, max(0, (value * 255).rounded())))
        }
        let rIn = byte(r * a)
        let gIn = byte(g * a)
        let bIn = byte(b * a)
        let aIn = byte(a)

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none

        if let existingFill, let cgExisting = existingFill.cgImage {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgExisting, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        // Raw-pointer stride (no bounds checks) — the same Debug-speed rationale as the rasterize loop.
        region.withUnsafeBufferPointer { regionBuf in
            let regionPtr = regionBuf.baseAddress!
            for y in 0..<height {
                var offset = y * bytesPerRow
                var regionOffset = y * width
                for _ in 0..<width {
                    if regionPtr[regionOffset] != 0 {
                        buffer[offset] = rIn
                        buffer[offset + 1] = gIn
                        buffer[offset + 2] = bIn
                        buffer[offset + 3] = aIn
                    }
                    offset += bytesPerPixel
                    regionOffset += 1
                }
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
