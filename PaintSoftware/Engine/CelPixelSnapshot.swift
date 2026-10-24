import CoreGraphics
import UIKit

/// Immutable pixel tiers of the active cel, captured once. Editable vector objects never enter
/// this source. Only the active window is normalized and sampled while the brush moves.
struct CelPixelSnapshot {
    let raster: RasterSource?
    let baked: RasterSource?
    let size: CGSize
    var residency: RasterResidency { raster?.residency ?? baked?.residency ?? .shared }

    init(rasterSource: RasterSource?, bakedSource: RasterSource?, size: CGSize) {
        raster = rasterSource
        baked = bakedSource
        self.size = size
    }

    init?(capturing raster: UIImage?, baked: UIImage?, size: CGSize, residency: RasterResidency = .shared) {
        do {
            self.raster = try raster.map { try RasterSource.capture($0, using: residency).get() }
            self.baked = try baked.map { try RasterSource.capture($0, using: residency).get() }
        } catch { return nil }
        self.size = size
    }

    init?(cel: Cel) {
        raster = cel.raster.snapshot()
        baked = cel.bakedImage
        size = cel.raster.size
        if raster == nil && baked == nil { return nil }
    }

    struct Patch {
        let image: UIImage
        let rect: CGRect
        let changed: Bool
    }

    func replacementRect(in requested: CGRect, through bridge: PoseMap?) -> CGRect? {
        let rect: CGRect
        if let bridge {
            guard let inverse = bridge.inverse,
                  let path = inverse.mapped(CGPath(rect: requested, transform: nil)) else { return nil }
            rect = path.boundingBoxOfPath
        } else { rect = requested }
        return rect.integral.intersection(CGRect(origin: .zero, size: size))
    }

    static func liquifyWorkingBytes(sourceSize: CGSize, destinationSize: CGSize) -> Int {
        let width = Int(destinationSize.width), height = Int(destinationSize.height)
        let rows = max(1, LiquifyField.inverseBatchSize / max(1, width))
        let batches = (height + rows - 1) / rows
        // Two source surfaces at up to RGBA16 also cover the later image + normalized RGBA8;
        // all strip outputs coexist with their joined copy.
        // The strip scope ends before makeImage creates its provider copy. parallelMap briefly
        // owns two arrays of optional strip headers, never two copies of their pixel payloads.
        return Int(sourceSize.width) * Int(sourceSize.height) * 16 + width * height * 8
            + batches * MemoryLayout<[UInt8]?>.stride * 2
    }

    func liquifiedPatch(in requested: CGRect, using field: LiquifyField, through bridge: PoseMap? = nil) -> Patch? {
        let canvas = CGRect(origin: .zero, size: size)
        guard let rect = replacementRect(in: requested, through: bridge) else { return nil }
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let sourceRect = rect.insetBy(dx: -1, dy: -1).intersection(canvas)
        let workingBytes = Self.liquifyWorkingBytes(sourceSize: sourceRect.size, destinationSize: rect.size)
        guard workingBytes <= CompositorBudget.textureBudgetBytes,
              CompositorBudget.hasHeadroom(for: workingBytes) else { return nil }
        guard case .success(let working) = residency.admitWorking(workingBytes) else { return nil }
        defer { withExtendedLifetime(working) {} }
        guard let source = replacementWindow(in: sourceRect) else { return nil }
        let sw = Int(sourceRect.width), sh = Int(sourceRect.height)
        guard let cg = source.cgImage,
              let bytes = CoreGraphicsCompositor.premultipliedBytes(cg, width: sw, height: sh) else { return nil }
        let inverseBridge = bridge?.inverse
        if bridge != nil, inverseBridge == nil { return nil }
        let width = Int(rect.width), height = Int(rect.height)
        let warped: [UInt8]? = {
            let rows = max(1, LiquifyField.inverseBatchSize / width)
            let strips = PixelOps.parallelMap((height + rows - 1) / rows) { batch -> [UInt8]? in
                let startRow = batch * rows
                var failed = false
                let pixels = ImageWarp.warp(source: bytes, sourceWidth: sw, sourceHeight: sh,
                    destinationWidth: width, destinationHeight: min(rows, height - startRow), inverseTexelMap: { local in
                        let destination = CGPoint(x: rect.minX + local.x, y: rect.minY + (CGFloat(startRow + Int(local.y)) + 0.5))
                        let fieldPoint: CGPoint
                        if let bridge {
                            guard let mapped = bridge.applied(to: destination) else { failed = true; return nil }
                            fieldPoint = mapped
                        } else { fieldPoint = destination }
                        let solution = field.inverseSolution(fieldPoint)
                        guard solution.converged else { failed = true; return nil }
                        let point: CGPoint
                        if let inverseBridge {
                            guard let mapped = inverseBridge.applied(to: solution.point) else { failed = true; return nil }
                            point = mapped
                        } else { point = solution.point }
                        // An in-canvas source outside the captured support is a failed window, never a
                        // transparent sample that could silently delete pixels at commit.
                        if canvas.contains(point), !sourceRect.contains(point) { failed = true; return nil }
                        return CGPoint(x: point.x - sourceRect.minX, y: point.y - sourceRect.minY)
                })
                return failed ? nil : pixels
            }
            guard strips.allSatisfy({ $0 != nil }) else { return nil }
            var joined = [UInt8](repeating: 0, count: width * height * 4)
            joined.withUnsafeMutableBytes { output in
                var offset = 0
                for case let strip? in strips {
                    strip.withUnsafeBytes { input in
                        output.baseAddress!.advanced(by: offset).copyMemory(from: input.baseAddress!, byteCount: input.count)
                    }
                    offset += strip.count
                }
            }
            return joined
        }()
        guard let warped,
              case .success(let output) = RasterSurface.allocate(width: width, height: height, using: residency),
              case .success = output.replacePixels(with: warped),
              case .success(let image) = output.image() else { return nil }
        var changed = false
        let dx = Int(rect.minX - sourceRect.minX), dy = Int(rect.minY - sourceRect.minY)
        for y in 0..<Int(rect.height) {
            let a = (y * width) * 4, b = ((y + dy) * sw + dx) * 4
            if !warped[a..<(a + width * 4)].elementsEqual(bytes[b..<(b + width * 4)]) { changed = true; break }
        }
        return Patch(image: image, rect: rect, changed: changed)
    }

    /// One canvas allocation at lift; every preview before it held only its window.
    func committing(_ patch: Patch) -> RasterSource? {
        guard let surface = render(in: CGRect(origin: .zero, size: size), applying: patch) else { return nil }
        return RasterSource.snapshot(of: surface, size: size)
    }

    func replacementWindow(in rect: CGRect, applying patch: Patch? = nil) -> UIImage? {
        guard let surface = render(in: rect, applying: patch),
              case .success(let image) = surface.image() else { return nil }
        return image
    }

    private func render(in rect: CGRect, applying patch: Patch?) -> RasterSurface? {
        // Resolve every required tier before drawing. An unavailable tier refuses the whole window;
        // nil input is logical absence and remains different from a failed read.
        let rasterImage: UIImage?
        let bakedImage: UIImage?
        do {
            rasterImage = try raster?.resolveImage().get()
            bakedImage = try baked?.resolveImage().get()
        } catch { return nil }
        guard case .success(let output) = RasterSurface.allocate(width: Int(rect.width), height: Int(rect.height),
                                                                  using: residency) else { return nil }
        guard case .success = output.mutate({ context in
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }
            let content = CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: size)
            bakedImage?.draw(in: content)
            rasterImage?.draw(in: content)
            if let patch {
                let local = patch.rect.offsetBy(dx: -rect.minX, dy: -rect.minY)
                context.clear(local)
                patch.image.draw(in: local)
            }
        }) else { return nil }
        return output
    }
}
