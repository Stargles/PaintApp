import UIKit
import PencilKit

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
enum FloodFillEngine {

    /// Alpha (0-255) at/above which a reference-layer pixel counts as "ink" rather than open space.
    /// Kept low so faint pencil-style strokes still register as a wall; the antialiasing seam itself is
    /// handled separately by `expandRadius`, not by raising this threshold.
    private static let wallAlphaThreshold: UInt8 = 24

    /// Attempts a flood fill seeded at `seed` (canvas-pixel coordinates). Returns the destination cel's
    /// new fill raster, or nil if nothing should change (seed landed directly on ink, gap-closing sealed
    /// the seed's own pixel shut, or the reachable region was empty).
    static func fill(
        referenceLayer: Layer,
        referenceCel: Cel,
        existingFill: UIImage?,
        canvasSize: CGSize,
        seed: CGPoint,
        fillColor: UIColor,
        gapClosingRadius: CGFloat,
        expandRadius: CGFloat,
        applyExpand: Bool
    ) -> UIImage? {
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        let seedX = Int(seed.x.rounded(.down))
        let seedY = Int(seed.y.rounded(.down))
        guard seedX >= 0, seedX < width, seedY >= 0, seedY < height else { return nil }

        let reference = rasterizeReferenceComposite(layer: referenceLayer, cel: referenceCel, width: width, height: height)
        guard let originalWall = alphaMask(from: reference, width: width, height: height, threshold: wallAlphaThreshold) else { return nil }

        let seedIndex = seedY * width + seedX
        guard !originalWall[seedIndex] else { return nil } // tapped directly on ink

        var wall = originalWall
        let closeRadius = Int(gapClosingRadius.rounded())
        if closeRadius > 0 {
            wall = morphologicalClose(originalWall, width: width, height: height, radius: closeRadius)
        }

        var region = ContiguousArray<Bool>(repeating: false, count: width * height)
        let filledAny = scanlineFloodFill(wall: wall, region: &region, width: width, height: height, seedX: seedX, seedY: seedY)
        guard filledAny else { return nil }

        if applyExpand, expandRadius > 0 {
            region = dilate(region, width: width, height: height, radius: Int(expandRadius.rounded()))
        }

        return composite(existingFill: existingFill, region: region, width: width, height: height, color: fillColor)
    }

    // MARK: - Rasterizing the reference mask

    private static func rasterizeReferenceComposite(layer: Layer, cel: Cel, width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            // Lineart (strokes), select/move's baked raster content, and (for photo/image layers) the
            // inserted image count as walls — deliberately excludes the layer's own `fillImage` so
            // re-tapping an already-filled, fully enclosed region floods the whole thing with the new
            // color instead of stopping at the leftover edge of a previous fill.
            if layer.isObjectLayer, let objectImage = layer.objectImage {
                objectImage.draw(in: rect)
            }
            cel.bakedImage?.draw(in: rect)
            cel.drawing.image(from: rect, scale: 1.0).draw(in: rect)
        }
    }

    /// Extracts the alpha channel of `image` as a boolean wall mask. Goes through a standard RGBA8
    /// context rather than an alpha-only one so the bitmap format is unambiguously valid.
    private static func alphaMask(from image: UIImage, width: Int, height: Int, threshold: UInt8) -> ContiguousArray<Bool>? {
        guard let cgImage = image.cgImage else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        // Flip so row 0 of the raw buffer is the top of the image — CGContext's own coordinate space is
        // bottom-up by default, but every other buffer in this file (and the seed point) is top-down.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        var result = ContiguousArray<Bool>(repeating: false, count: width * height)
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            let outRowStart = y * width
            for x in 0..<width {
                result[outRowStart + x] = buffer[rowStart + x * bytesPerPixel + 3] >= threshold
            }
        }
        return result
    }

    // MARK: - Morphology (gap closing / edge expansion)

    private static func morphologicalClose(_ input: ContiguousArray<Bool>, width: Int, height: Int, radius: Int) -> ContiguousArray<Bool> {
        erode(dilate(input, width: width, height: height, radius: radius), width: width, height: height, radius: radius)
    }

    private static func dilate(_ input: ContiguousArray<Bool>, width: Int, height: Int, radius: Int) -> ContiguousArray<Bool> {
        guard radius > 0 else { return input }
        let h = boxFilter(input, width: width, height: height, radius: radius, horizontal: true, useMax: true)
        return boxFilter(h, width: width, height: height, radius: radius, horizontal: false, useMax: true)
    }

    private static func erode(_ input: ContiguousArray<Bool>, width: Int, height: Int, radius: Int) -> ContiguousArray<Bool> {
        guard radius > 0 else { return input }
        let h = boxFilter(input, width: width, height: height, radius: radius, horizontal: true, useMax: false)
        return boxFilter(h, width: width, height: height, radius: radius, horizontal: false, useMax: false)
    }

    /// Separable box min/max filter: a `(2*radius+1)`-square structuring element decomposed into one
    /// horizontal and one vertical 1-D pass (a valid decomposition for a square SE — 2-D box dilation/
    /// erosion is the composition of two 1-D box passes). Each 1-D pass is an O(line length)
    /// sliding-window extremum via `slidingExtremum` below, independent of `radius` — needed because
    /// gap-closing radius can be dozens of pixels on a canvas up to 8192px per side, where a naive
    /// O(length * radius) scan would be far too slow.
    private static func boxFilter(_ input: ContiguousArray<Bool>, width: Int, height: Int, radius: Int, horizontal: Bool, useMax: Bool) -> ContiguousArray<Bool> {
        var output = ContiguousArray<Bool>(repeating: false, count: width * height)
        input.withUnsafeBufferPointer { buf in
            if horizontal {
                for row in 0..<height {
                    let base = row * width
                    slidingExtremum(buf, n: width, radius: radius, useMax: useMax, index: { base + $0 }, output: &output, outputIndex: { base + $0 })
                }
            } else {
                for col in 0..<width {
                    slidingExtremum(buf, n: height, radius: radius, useMax: useMax, index: { $0 * width + col }, output: &output, outputIndex: { $0 * width + col })
                }
            }
        }
        return output
    }

    /// Sliding-window maximum (`useMax`) or minimum (`useMax == false`) over `n` boolean samples reached
    /// via `index`, written back via `outputIndex`. Classic monotonic-deque streaming extremum: each
    /// position is pushed and popped from the deque at most once, so the whole pass is O(n) regardless
    /// of `radius`. The deque is backed by a plain array with head/tail cursors rather than a true ring
    /// buffer — safe here because every index 0..<n is appended exactly once, in increasing order, and
    /// only ever popped from the front or back, so the cursors never need to wrap.
    private static func slidingExtremum(
        _ values: UnsafeBufferPointer<Bool>,
        n: Int,
        radius: Int,
        useMax: Bool,
        index: (Int) -> Int,
        output: inout ContiguousArray<Bool>,
        outputIndex: (Int) -> Int
    ) {
        guard n > 0 else { return }
        var dequeBuffer = [Int](repeating: 0, count: n)
        var head = 0
        var tail = 0
        var pushIdx = 0

        for c in 0..<n {
            let windowEnd = min(n - 1, c + radius)
            while pushIdx <= windowEnd {
                let v = values[index(pushIdx)]
                while tail > head {
                    let lastV = values[index(dequeBuffer[tail - 1])]
                    // For max: pop while lastV <= v  ⟺  !lastV || v.
                    // For min: pop while lastV >= v  ⟺  lastV || !v.
                    let shouldPop = useMax ? (!lastV || v) : (lastV || !v)
                    guard shouldPop else { break }
                    tail -= 1
                }
                dequeBuffer[tail] = pushIdx
                tail += 1
                pushIdx += 1
            }
            let windowStart = c - radius
            while head < tail, dequeBuffer[head] < windowStart {
                head += 1
            }
            if head < tail {
                output[outputIndex(c)] = values[index(dequeBuffer[head])]
            }
        }
    }

    // MARK: - Flood fill

    /// Stack-based scanline flood fill: fills whole contiguous horizontal spans at a time instead of
    /// visiting every pixel individually, so it stays fast even across large open regions.
    private static func scanlineFloodFill(wall: ContiguousArray<Bool>, region: inout ContiguousArray<Bool>, width: Int, height: Int, seedX: Int, seedY: Int) -> Bool {
        guard !wall[seedY * width + seedX] else { return false }
        var stack: [(x: Int, y: Int)] = [(seedX, seedY)]
        var filledAny = false

        wall.withUnsafeBufferPointer { wallBuf in
            region.withUnsafeMutableBufferPointer { regionBuf in
                while let (x0, y0) = stack.popLast() {
                    let rowBase = y0 * width
                    if regionBuf[rowBase + x0] || wallBuf[rowBase + x0] { continue }

                    var left = x0
                    while left > 0, !wallBuf[rowBase + left - 1], !regionBuf[rowBase + left - 1] { left -= 1 }
                    var right = x0
                    while right < width - 1, !wallBuf[rowBase + right + 1], !regionBuf[rowBase + right + 1] { right += 1 }
                    for x in left...right {
                        regionBuf[rowBase + x] = true
                    }
                    filledAny = true

                    if y0 > 0 { queueSpan(row: y0 - 1, left: left, right: right, width: width, wallBuf: wallBuf, regionBuf: regionBuf, stack: &stack) }
                    if y0 < height - 1 { queueSpan(row: y0 + 1, left: left, right: right, width: width, wallBuf: wallBuf, regionBuf: regionBuf, stack: &stack) }
                }
            }
        }
        return filledAny
    }

    private static func queueSpan(row: Int, left: Int, right: Int, width: Int, wallBuf: UnsafeBufferPointer<Bool>, regionBuf: UnsafeMutableBufferPointer<Bool>, stack: inout [(x: Int, y: Int)]) {
        let rowBase = row * width
        var x = left
        while x <= right {
            if wallBuf[rowBase + x] || regionBuf[rowBase + x] {
                x += 1
                continue
            }
            stack.append((x, row))
            while x <= right, !wallBuf[rowBase + x], !regionBuf[rowBase + x] { x += 1 }
        }
    }

    // MARK: - Compositing the result

    private static func composite(existingFill: UIImage?, region: ContiguousArray<Bool>, width: Int, height: Int, color: UIColor) -> UIImage? {
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
        region.withUnsafeBufferPointer { regionBuf in
            for y in 0..<height {
                let rowStart = y * bytesPerRow
                let regionRowStart = y * width
                for x in 0..<width where regionBuf[regionRowStart + x] {
                    let offset = rowStart + x * bytesPerPixel
                    buffer[offset] = rIn
                    buffer[offset + 1] = gIn
                    buffer[offset + 2] = bIn
                    buffer[offset + 3] = aIn
                }
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
