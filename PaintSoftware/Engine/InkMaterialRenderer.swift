import UIKit
import CoreGraphics
import os

/// One render tile's material work. The painter's list remains ordered; only inverse coordinates
/// are shared across ink with the same operation chain and transport. No scene/cel-global cache.
final class InkMaterialRenderer {
    static let tileSide = 256
    static let byteBudget = 24 * 1024 * 1024
    private let budget = Budget(limit: InkMaterialRenderer.byteBudget)
    let window: CGRect
    let scale: CGFloat
    private var maps: [CoordinateMap] = []
    enum Failure { case allocation, transport, inverse }
    private(set) var failure: Failure?
    var completed: Bool { failure == nil }
    private(set) var evaluations = 0
    private(set) var preparedFields = 0
    private(set) var coordinateHits = 0
    private(set) var sourceTiles = 0
    private(set) var peakFieldBytes = 0
    var peakBytes: Int { budget.peak + peakFieldBytes }

    init(window: CGRect, scale: CGFloat) { self.window = window; self.scale = scale }

    /// One bounded tile walk for ordered canvas rendering and standalone pixel preview groups.
    /// Every caller uses the same pixel grid and owns no cache beyond the current output tile.
    static func visitTiles(into context: CGContext, over bounds: CGRect? = nil,
                           draw: (InkMaterialRenderer) -> Bool) -> Bool {
        let visible = bounds.map { context.boundingBoxOfClipPath.intersection($0) } ?? context.boundingBoxOfClipPath
        if visible.isNull || visible.isEmpty { return true }
        let scale = max(hypot(context.ctm.a, context.ctm.b), hypot(context.ctm.c, context.ctm.d))
        guard !visible.isInfinite, scale.isFinite, scale > 0 else { return false }
        let side = CGFloat(tileSide)
        let coordinates = [floor(visible.minX * scale / side), ceil(visible.maxX * scale / side),
                           floor(visible.minY * scale / side), ceil(visible.maxY * scale / side)]
        guard coordinates.allSatisfy({ $0.isFinite && abs($0) < CGFloat(Int.max / 4) }) else { return false }
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        for y in Int(coordinates[2])..<Int(coordinates[3]) { for x in Int(coordinates[0])..<Int(coordinates[1]) {
            let window = CGRect(x: CGFloat(x) * side / scale, y: CGFloat(y) * side / scale,
                                width: side / scale, height: side / scale)
            let renderer = InkMaterialRenderer(window: window, scale: scale)
            context.saveGState(); context.clip(to: window)
            let completed = draw(renderer)
            context.restoreGState()
            InkMaterialRenderProbe.record(renderer)
            guard completed && renderer.completed else { return false }
        } }
        return true
    }

    /// Payload allocations reserve before allocating, including scratch and failure paths. Raw
    /// pixel leases follow their CGDataProvider lifetime, rather than ending at draw() return.
    private final class Budget {
        let limit: Int
        var current = 0
        var peak = 0
        init(limit: Int) { self.limit = limit }
        func reserve(_ bytes: Int) -> Lease? {
            let rounded = ((max(0, bytes) + 4095) / 4096) * 4096
            guard rounded <= limit - current else { return nil }
            current += rounded; peak = max(peak, current)
            return Lease(owner: self, bytes: rounded)
        }
    }
    private final class Lease {
        let owner: Budget
        let bytes: Int
        init(owner: Budget, bytes: Int) { self.owner = owner; self.bytes = bytes }
        deinit { owner.current -= bytes }
    }
    private final class Pixels {
        let raw: UnsafeMutableRawPointer
        let side: Int
        let lease: Lease
        init(side: Int, lease: Lease) {
            self.side = side; self.lease = lease
            raw = .allocate(byteCount: side * side * 4, alignment: 64)
            raw.initializeMemory(as: UInt8.self, repeating: 0, count: side * side * 4)
        }
        deinit { raw.deallocate() }
        var bytes: UnsafeMutablePointer<UInt8> { raw.assumingMemoryBound(to: UInt8.self) }
        func image() -> CGImage? {
            let info = Unmanaged.passRetained(self).toOpaque()
            guard let provider = CGDataProvider(dataInfo: info, data: raw, size: side * side * 4,
                releaseData: { info, _, _ in if let info { Unmanaged<Pixels>.fromOpaque(info).release() } }) else {
                Unmanaged<Pixels>.fromOpaque(info).release(); return nil
            }
            return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
    private final class CoordinateMap {
        let bindings: [InkMaterialBinding]
        let transport: InkMaterialBridge
        let points: [CGPoint]
        let lease: Lease
        init(bindings: [InkMaterialBinding], transport: InkMaterialBridge,
             coordinates: [CGPoint], lease: Lease) {
            self.bindings = bindings; self.transport = transport; self.points = coordinates
            self.lease = lease
        }
    }

    private func refuse(_ reason: Failure = .allocation) {
        guard failure == nil else { return }
        failure = reason
        if case .allocation = reason { MemoryPressure.signal(.allocationRefused) }
        else { VectorStroke.log.error("Native material picture refused an unusable transport or inverse") }
    }

    func rejectTransport() { refuse(.transport) }

    private func allocatePixels() -> Pixels? {
        guard let lease = budget.reserve(Self.tileSide * Self.tileSide * 4) else { refuse(); return nil }
        return Pixels(side: Self.tileSide, lease: lease)
    }

    /// Native geometry preparation shares the render tile's budget and can evict only its
    /// disposable inverse maps. Standalone scratch/hit callers use the same owner before mapping.
    func withGeometryScratch<T>(transport: InkMaterialBridge, pointCount: Int, _ body: () -> T?) -> T? {
        let extra = transport.mappingScratchByteUpperBound
        let (points, overflow) = pointCount.multipliedReportingOverflow(by: 160)
        guard !overflow, extra <= budget.limit, points <= budget.limit - extra else { refuse(); return nil }
        let bytes = points + extra
        while budget.limit - budget.current < bytes, !maps.isEmpty { maps.removeFirst() }
        guard let lease = budget.reserve(bytes) else { refuse(); return nil }
        return withExtendedLifetime(lease, body)
    }

    private func inverse(_ points: [CGPoint], program: InkMaterialProgram,
                         transport: InkMaterialBridge) -> [CGPoint]? {
        var work = InkMaterialProgram.MappingWork()
        defer {
            peakFieldBytes = max(peakFieldBytes, work.peakFieldBytes)
            preparedFields += work.fields; evaluations += work.evaluations
        }
        do {
            let coordinates = try program.inverse(points, transport: transport, work: &work)
            guard coordinates.allSatisfy({ ImageWarp.supportsSampling(at: CGPoint(x: $0.x * scale, y: $0.y * scale)) }) else {
                refuse(.transport); return nil
            }
            return coordinates
        } catch InkMaterialProgram.MappingFailure.inverse { refuse(.inverse); return nil }
        catch { refuse(.transport); return nil }
    }

    /// All native groups in this output tile reuse the exact inverse points. Fields stream one at
    /// a time; original material is sampled once after the whole chain has been reversed.
    private func coordinates(bindings: [InkMaterialBinding], transport: InkMaterialBridge) -> CoordinateMap? {
        if let hit = maps.first(where: { $0.bindings == bindings && $0.transport == transport }) {
            coordinateHits += 1; return hit
        }
        let side = Self.tileSide, count = side * side
        // At most two geometry maps, their three-array embeddings and their outputs coexist. The
        // lattice's temporary rest vertices are also reserved; sequences execute one part at a time.
        let largest = max(transport.mappingScratchByteUpperBound, bindings.map { $0.bridge.mappingScratchByteUpperBound }.max() ?? 0)
        guard largest < budget.limit else { refuse(); return nil }
        let scratchBytes = count * 160 + largest
        let coordinateBytes = count * MemoryLayout<CGPoint>.stride
        while budget.limit - budget.current < scratchBytes + coordinateBytes, !maps.isEmpty {
            maps.removeFirst()
        }
        guard let scratch = budget.reserve(scratchBytes), let retained = budget.reserve(coordinateBytes) else { refuse(); return nil }
        let coordinates = withExtendedLifetime(scratch) { () -> [CGPoint]? in
            let points = (0..<count).map { i in
                CGPoint(x: window.minX + (CGFloat(i % side) + 0.5) / scale,
                        y: window.minY + (CGFloat(i / side) + 0.5) / scale)
            }
            return inverse(points, program: InkMaterialProgram(bindings: bindings), transport: transport)
        }
        guard let coordinates else { return nil }
        let result = CoordinateMap(bindings: bindings, transport: transport, coordinates: coordinates, lease: retained)
        maps.append(result)
        return result
    }

    private struct SourceKey: Hashable { let x: Int; let y: Int }

    /// Native ink and chronological clip masks use the same bounded source-tile sampler. Missing
    /// tiles refuse the picture; only points genuinely outside the native footprint sample zero.
    private final class SourceTiles {
        unowned let renderer: InkMaterialRenderer
        let bounds: CGRect
        let paint: (CGContext, CGRect) -> Void
        var pixels: [SourceKey: Pixels] = [:]
        var order: [SourceKey] = []
        init(renderer: InkMaterialRenderer, bounds: CGRect,
             paint: @escaping (CGContext, CGRect) -> Void) {
            self.renderer = renderer; self.bounds = bounds.insetBy(dx: -1 / renderer.scale, dy: -1 / renderer.scale)
            self.paint = paint
        }
        private func pixel(_ x: Int, _ y: Int) -> (Pixels, Int)? {
            let scale = renderer.scale, side = InkMaterialRenderer.tileSide
            let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
            guard bounds.contains(point) else { return nil }
            // Integer taps beyond 2^53 cannot round-trip through CGFloat. Choosing the tile in
            // floating point could put its exact local coordinate at -1 before pointer access.
            func tile(_ value: Int) -> Int {
                let quotient = value / side
                return value % side < 0 ? quotient - 1 : quotient
            }
            let key = SourceKey(x: tile(x), y: tile(y))
            let tile: Pixels
            if let existing = pixels[key] { tile = existing }
            else {
                while order.count >= 8 { pixels.removeValue(forKey: order.removeFirst()) }
                guard let allocated = renderer.allocatePixels() else { return nil }
                let rect = CGRect(x: CGFloat(key.x * side) / scale, y: CGFloat(key.y * side) / scale,
                                  width: CGFloat(side) / scale, height: CGFloat(side) / scale)
                guard let context = CGContext(data: allocated.raw, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { renderer.refuse(); return nil }
                context.translateBy(x: 0, y: CGFloat(side)); context.scaleBy(x: scale, y: -scale)
                context.translateBy(x: -rect.minX, y: -rect.minY)
                guard let transparency = renderer.budget.reserve(side * side * 4 + 4096) else { renderer.refuse(); return nil }
                withExtendedLifetime(transparency) {
                    UIGraphicsPushContext(context); paint(context, rect); UIGraphicsPopContext()
                }
                pixels[key] = allocated; order.append(key); tile = allocated; renderer.sourceTiles += 1
            }
            let index = ((y - key.y * side) * side + x - key.x * side) * 4
            return (tile, index)
        }
        func texel(_ x: Int, _ y: Int) -> ImageWarp.PremultipliedPixel {
            guard let (tile, index) = pixel(x, y) else { return (0, 0, 0, 0) }
            return (tile.bytes[index], tile.bytes[index + 1], tile.bytes[index + 2], tile.bytes[index + 3])
        }
    }

    /// A bounded query of the same native pixels and inverse used for painting. Used for material
    /// tap/retag and eraser candidacy; the centreline still owns lasso membership. Nil refuses the
    /// query rather than silently substituting the moved spine or accepting a loose bounds overlap.
    func hasInk(at points: [CGPoint], nativeBounds: CGRect, program: InkMaterialProgram,
                transport: InkMaterialBridge,
                paint: @escaping (CGContext, CGRect) -> Void) -> Bool? {
        guard !points.isEmpty else { return false }
        let largest = max(transport.mappingScratchByteUpperBound, program.bindings.map { $0.bridge.mappingScratchByteUpperBound }.max() ?? 0)
        guard points.count <= Self.tileSide * Self.tileSide, largest < budget.limit,
              let scratch = budget.reserve(points.count * 192 + largest) else { refuse(); return nil }
        return withExtendedLifetime(scratch) {
            guard let coordinates = inverse(points, program: program, transport: transport) else { return nil }
            let source = SourceTiles(renderer: self, bounds: nativeBounds, paint: paint)
            for at in coordinates {
                let alpha = ImageWarp.samplePremultiplied(at: CGPoint(x: at.x * scale, y: at.y * scale), texel: source.texel).3
                guard completed else { return nil }
                if alpha > 0 { return true }
            }
            return false
        }
    }

    /// Draw native coverage into bounded source tiles. `paint` reuses the existing native group or
    /// fill renderer; it does not reinterpret spacing, sensors, random values, opacity or paper.
    func draw(into destination: CGContext, nativeBounds: CGRect,
              program: InkMaterialProgram, transport: InkMaterialBridge,
              coverage: [InkMaterialCoverage] = [], evenOdd: Bool = false,
              blendMode: CGBlendMode,
              paint: @escaping (CGContext, CGRect) -> Void) {
        guard completed, !nativeBounds.isNull, !nativeBounds.isEmpty,
              let inverse = coordinates(bindings: program.bindings, transport: transport),
              let output = allocatePixels() else { return }
        let side = Self.tileSide
        guard let maskLease = budget.reserve(side * side) else { refuse(); return }
        var alpha = [UInt8](repeating: 255, count: side * side)
        for clip in coverage {
            guard let path = VectorFillElement.decodePath(clip.pathData),
                  let stage = program.bindings.firstIndex(where: { $0.operation.id == clip.afterOperation }),
                  let points = coordinates(bindings: Array(program.bindings.dropFirst(stage + 1)), transport: .identity) else { refuse(.transport); return }
            let extra = clip.bridge.mappingScratchByteUpperBound
            guard extra < budget.limit, let scratch = budget.reserve(side * side * 160 + extra) else { refuse(); return }
            let valid = withExtendedLifetime(scratch) { () -> Bool in
                guard let local = clip.bridge.map(points.points, inverse: true),
                      local.allSatisfy({ ImageWarp.supportsSampling(at: CGPoint(x: $0.x * scale, y: $0.y * scale)) }) else { return false }
                let mask = SourceTiles(renderer: self, bounds: path.boundingBoxOfPath) { context, _ in
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.addPath(path); context.fillPath(using: evenOdd ? .evenOdd : .winding)
                }
                for index in alpha.indices where alpha[index] > 0 {
                    let sample = ImageWarp.samplePremultiplied(at: CGPoint(x: local[index].x * scale, y: local[index].y * scale),
                        texel: mask.texel).3
                    let value = clip.inverted ? 255 - Int(sample) : Int(sample)
                    alpha[index] = UInt8((Int(alpha[index]) * value + 127) / 255)
                    guard completed else { return false }
                }
                return completed
            }
            guard valid else { refuse(.transport); return }
        }
        // Source pixels are stroke-specific; coordinate tiles above are shared. Eviction never
        // replaces missing pixels with zero: a refused tile refuses the whole output picture.
        let source = SourceTiles(renderer: self, bounds: nativeBounds, paint: paint)
        for index in inverse.points.indices {
            guard alpha[index] > 0 else { continue }
            let point = inverse.points[index]
            let pixel = ImageWarp.samplePremultiplied(at: CGPoint(x: point.x * scale, y: point.y * scale), texel: source.texel)
            func covered(_ channel: UInt8) -> UInt8 { UInt8((Int(channel) * Int(alpha[index]) + 127) / 255) }
            output.bytes[index * 4] = covered(pixel.0); output.bytes[index * 4 + 1] = covered(pixel.1)
            output.bytes[index * 4 + 2] = covered(pixel.2); output.bytes[index * 4 + 3] = covered(pixel.3)
            guard completed else { return }
        }
        withExtendedLifetime(maskLease) {}
        autoreleasepool {
            guard let image = output.image() else { refuse(); return }
            destination.saveGState()
            // Drain UIKit's temporary image after this group, so its provider releases the counted
            // output tile before the next group reserves one. The coordinate tile stays shared.
            UIImage(cgImage: image, scale: scale, orientation: .up).draw(in: window, blendMode: blendMode, alpha: 1)
            destination.restoreGState()
        }
    }
}

/// Opt-in native work census, matching DabProbe's test-only observation seam. Recording occurs once
/// per output tile, never per sample. It cannot change the renderer's cache or scheduling decisions.
enum InkMaterialRenderProbe {
    struct Sample {
        let evaluations: Int
        let fields: Int
        let hits: Int
        let sourceTiles: Int
        let peakBytes: Int
        let peakFieldBytes: Int
        let completed: Bool
    }
    private static let lock = NSLock()
    private static var armed = false
    private static var samples: [Sample] = []
    private static var boundsWalks = 0
    static var nativeBoundsWalkCount: Int { lock.lock(); defer { lock.unlock() }; return boundsWalks }
    static func begin() { lock.lock(); defer { lock.unlock() }; samples = []; boundsWalks = 0; armed = true }
    static func end() -> [Sample] { lock.lock(); defer { lock.unlock() }; armed = false; let result = samples; samples = []; return result }
    static func record(_ renderer: InkMaterialRenderer) {
        guard armed else { return }
        lock.lock(); defer { lock.unlock() }
        guard armed else { return }
        samples.append(Sample(evaluations: renderer.evaluations, fields: renderer.preparedFields,
            hits: renderer.coordinateHits, sourceTiles: renderer.sourceTiles, peakBytes: renderer.peakBytes,
            peakFieldBytes: renderer.peakFieldBytes, completed: renderer.completed))
    }
    static func recordNativeBoundsWalk() {
        guard armed else { return }
        lock.lock(); defer { lock.unlock() }
        if armed { boundsWalks += 1 }
    }
}
