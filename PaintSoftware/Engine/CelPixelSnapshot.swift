import CoreGraphics
import UIKit

/// Immutable pixel tiers of the active cel, captured once. Editable vector objects never enter
/// this source. Only the active window is normalized and sampled while the brush moves.
struct CelPixelSnapshot {
    let raster: UIImage?
    let baked: UIImage?
    let size: CGSize

    init?(cel: Cel) {
        raster = cel.raster.hasContent ? cel.raster.renderToUIImage() : nil
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

    func liquifiedPatch(in requested: CGRect, using field: LiquifyField, through bridge: PoseMap? = nil) -> Patch? {
        let canvas = CGRect(origin: .zero, size: size)
        guard let rect = replacementRect(in: requested, through: bridge) else { return nil }
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let sourceRect = rect.insetBy(dx: -1, dy: -1).intersection(canvas)
        let source = UIGraphicsImageRenderer(size: sourceRect.size, format: PixelOps.transparentFormat()).image { _ in
            draw(at: CGPoint(x: -sourceRect.minX, y: -sourceRect.minY))
        }
        let sw = Int(sourceRect.width), sh = Int(sourceRect.height)
        guard let cg = source.cgImage,
              let bytes = CoreGraphicsCompositor.premultipliedBytes(cg, width: sw, height: sh) else { return nil }
        let inverseBridge = bridge?.inverse
        if bridge != nil, inverseBridge == nil { return nil }
        var failed = false
        guard let warped = ImageWarp.warp(source: bytes, sourceWidth: sw, sourceHeight: sh,
            destinationWidth: Int(rect.width), destinationHeight: Int(rect.height), inverseTexelMap: { local in
                let destination = CGPoint(x: rect.minX + local.x, y: rect.minY + local.y)
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
            }), !failed,
            let image = CoreGraphicsCompositor.makeImage(fromPremultiplied: warped,
                width: Int(rect.width), height: Int(rect.height)) else { return nil }
        var changed = false
        let dx = Int(rect.minX - sourceRect.minX), dy = Int(rect.minY - sourceRect.minY), width = Int(rect.width)
        for y in 0..<Int(rect.height) {
            let a = (y * width) * 4, b = ((y + dy) * sw + dx) * 4
            if !warped[a..<(a + width * 4)].elementsEqual(bytes[b..<(b + width * 4)]) { changed = true; break }
        }
        return Patch(image: UIImage(cgImage: image), rect: rect, changed: changed)
    }

    /// One canvas allocation at lift; every preview before it held only its window.
    func committing(_ patch: Patch) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            draw(at: .zero)
            context.cgContext.clear(patch.rect)
            patch.image.draw(in: patch.rect)
        }
    }

    func replacementWindow(in rect: CGRect, applying patch: Patch? = nil) -> UIImage {
        UIGraphicsImageRenderer(size: rect.size, format: PixelOps.transparentFormat()).image { context in
            draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
            if let patch {
                let local = patch.rect.offsetBy(dx: -rect.minX, dy: -rect.minY)
                context.cgContext.clear(local)
                patch.image.draw(in: local)
            }
        }
    }

    private func draw(at origin: CGPoint) {
        let rect = CGRect(origin: origin, size: size)
        baked?.draw(in: rect)
        raster?.draw(in: rect)
    }
}
