import CoreGraphics
import UIKit

/// Immutable native layout and UIKit presentation. It contains no image or provider, and stays
/// with a process-local version when its bytes are compressed. Public PNG metadata is unchanged.
struct RasterImageDescriptor {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bitsPerComponent: Int
    let bitsPerPixel: Int
    let bitmapInfo: CGBitmapInfo
    let colorSpace: CGColorSpace?
    let decode: [CGFloat]?
    let isMask: Bool
    let shouldInterpolate: Bool
    let intent: CGColorRenderingIntent
    let scale: CGFloat
    let orientation: UIImage.Orientation
    let size: CGSize

    var byteCount: Int? {
        let (count, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        return width > 0 && height > 0 && bytesPerRow > 0 && !overflow ? count : nil
    }

    init?(_ image: UIImage) {
        guard let cg = image.cgImage, image.scale.isFinite, image.scale > 0 else { return nil }
        width = cg.width; height = cg.height; bytesPerRow = cg.bytesPerRow
        bitsPerComponent = cg.bitsPerComponent; bitsPerPixel = cg.bitsPerPixel
        bitmapInfo = cg.bitmapInfo; colorSpace = cg.colorSpace; isMask = cg.isMask
        let channels = cg.isMask ? 1 : cg.colorSpace?.numberOfComponents ?? 0
        decode = cg.decode.map { Array(UnsafeBufferPointer(start: $0, count: channels * 2)) }
        shouldInterpolate = cg.shouldInterpolate; intent = cg.renderingIntent
        scale = image.scale; orientation = image.imageOrientation; size = image.size
        guard byteCount != nil, cg.isMask || colorSpace != nil else { return nil }
    }

    static func rgba8(width: Int, height: Int) -> RasterImageDescriptor {
        RasterImageDescriptor(width: width, height: height, bytesPerRow: width * 4)
    }

    private init(width: Int, height: Int, bytesPerRow: Int) {
        self.width = width; self.height = height; self.bytesPerRow = bytesPerRow
        bitsPerComponent = 8; bitsPerPixel = 32
        bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        colorSpace = PixelOps.deviceRGBColorSpace; decode = nil; isMask = false
        shouldInterpolate = true; intent = .defaultIntent; scale = 1; orientation = .up
        size = CGSize(width: width, height: height)
    }

    /// Exact eight-bit alpha location for the known native layouts. RGB keeps its existing
    /// first/last and 32-bit byte-order rules; monochrome supports only straight last alpha with
    /// default byte order. Masks, CMYK, indexed, float and other layouts carry no blank proof.
    var alpha8Layout: (pixelBytes: Int, alphaOffset: Int)? {
        guard !isMask, bitsPerComponent == 8, !bitmapInfo.contains(.floatComponents),
              let alpha = CGImageAlphaInfo(rawValue: bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue) else { return nil }
        if colorSpace?.model == .monochrome, bitsPerPixel == 16,
           bitmapInfo.rawValue == CGImageAlphaInfo.last.rawValue, bytesPerRow >= width * 2 {
            return (2, 1)
        }
        guard colorSpace?.model == .rgb, bitsPerPixel == 32, bytesPerRow >= width * 4 else { return nil }
        let first: Bool
        switch alpha {
        case .first, .premultipliedFirst: first = true
        case .last, .premultipliedLast: first = false
        default: return nil
        }
        let order = bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let offset = order == CGBitmapInfo.byteOrder32Little.rawValue ? (first ? 3 : 0) : (first ? 0 : 3)
        return (4, offset)
    }

    func image(provider: CGDataProvider) -> UIImage? {
        let cg: CGImage?
        func construct(_ ranges: UnsafePointer<CGFloat>?) -> CGImage? {
            if isMask {
                return CGImage(maskWidth: width, height: height, bitsPerComponent: bitsPerComponent,
                    bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, provider: provider,
                    decode: ranges, shouldInterpolate: shouldInterpolate)
            }
            guard let colorSpace else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: bitmapInfo, provider: provider, decode: ranges,
                shouldInterpolate: shouldInterpolate, intent: intent)
        }
        if let decode { cg = decode.withUnsafeBufferPointer { construct($0.baseAddress) } }
        else { cg = construct(nil) }
        return cg.map { UIImage(cgImage: $0, scale: scale, orientation: orientation) }
    }
}

/// Shared allocation/reader lifetime beneath mutable RGBA surfaces and immutable native sources.
/// The provider owns its lease, so an escaped CGImage continues to own its actual byte charge.
final class RasterPixelBuffer {
    let allocation: RasterResidency.Allocation
    let address: UnsafeMutableRawPointer
    private let lock = NSLock()
    private var readers = 0

    init?(allocation: RasterResidency.Allocation) {
        guard allocation.byteCount > 0, let address = calloc(1, allocation.byteCount) else { return nil }
        self.allocation = allocation; self.address = address
    }
    var readLeaseCount: Int { lock.lock(); defer { lock.unlock() }; return readers }
    private func beginReading() { lock.lock(); readers += 1; lock.unlock() }
    private func endReading() { lock.lock(); readers -= 1; precondition(readers >= 0); lock.unlock() }
    deinit { free(address) }

    func isFullyTransparent(_ descriptor: RasterImageDescriptor) -> Bool {
        guard let layout = descriptor.alpha8Layout else { return false }
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        for y in 0..<descriptor.height {
            for x in 0..<descriptor.width where bytes[y * descriptor.bytesPerRow + x * layout.pixelBytes + layout.alphaOffset] != 0 { return false }
        }
        return true
    }

    final class ReadLease {
        fileprivate let buffer: RasterPixelBuffer
        let descriptor: RasterImageDescriptor
        let residency: RasterResidency
        var allocation: RasterResidency.Allocation { buffer.allocation }
        var isFullyTransparent: Bool { buffer.isFullyTransparent(descriptor) }
        init(buffer: RasterPixelBuffer, descriptor: RasterImageDescriptor, residency: RasterResidency) {
            self.buffer = buffer; self.descriptor = descriptor; self.residency = residency
            buffer.beginReading()
        }
        func withBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
            try body(UnsafeRawBufferPointer(start: buffer.address, count: allocation.byteCount))
        }
        func image() -> Result<UIImage, RasterResidency.Failure> {
            autoreleasepool {
                let retained = Unmanaged.passRetained(self)
                guard let provider = CGDataProvider(dataInfo: retained.toOpaque(), data: buffer.address,
                    size: allocation.byteCount, releaseData: { info, _, _ in
                        if let info { Unmanaged<ReadLease>.fromOpaque(info).release() }
                    }) else { retained.release(); return .failure(.allocationRefused) }
                guard let image = descriptor.image(provider: provider) else { return .failure(.unreadableBacking) }
                return .success(image)
            }
        }
        deinit { buffer.endReading() }
    }

    /// CopyData can force a lazy foreign provider. Reserve its header extent before requesting it;
    /// oversized opaque providers are charged/refused immediately, never accepted under that estimate.
    static func capture(_ image: UIImage, using residency: RasterResidency, durable: Bool = false,
                        excluding: Set<UUID> = []) -> Result<ReadLease, RasterResidency.Failure> {
        guard let descriptor = RasterImageDescriptor(image), let extent = descriptor.byteCount,
              let provider = image.cgImage?.dataProvider else { return .failure(.invalidSize) }
        let (workingBytes, overflow) = extent.multipliedReportingOverflow(by: 2)
        guard !overflow else { return .failure(.invalidSize) }
        return residency.admitWorking(workingBytes, excluding: excluding).flatMap { working in
            autoreleasepool {
                defer { withExtendedLifetime(working) {} }
                guard let data = provider.data else { return .failure(.unreadableBacking) }
                let count = CFDataGetLength(data)
                // The supported native-provider contract includes every declared row. In
                // particular we do not guess that a platform accepts absent final-row padding.
                guard count >= extent, let input = CFDataGetBytePtr(data) else { return .failure(.unreadableBacking) }
                var extra: RasterResidency.Allocation?
                if count > extent {
                    let (additional, overflow) = (count - extent).multipliedReportingOverflow(by: 2)
                    guard !overflow else { return .failure(.invalidSize) }
                    switch residency.admitWorking(additional, excluding: excluding) {
                    case .success(let charge): extra = charge
                    case .failure(let failure): return .failure(failure)
                    }
                }
                defer { withExtendedLifetime((data, extra)) {} }
                return residency.admitPixels(count, durable: durable, excluding: excluding).flatMap { allocation in
                    guard let buffer = RasterPixelBuffer(allocation: allocation) else { return .failure(.allocationRefused) }
                    buffer.address.copyMemory(from: input, byteCount: count)
                    let lease = ReadLease(buffer: buffer, descriptor: descriptor, residency: residency)
                    // Refuse unsupported descriptors before publishing an immutable source.
                    return lease.image().map { _ in lease }
                }
            }
        }
    }
}
