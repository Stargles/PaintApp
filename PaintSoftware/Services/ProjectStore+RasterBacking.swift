import Foundation
import CryptoKit
import ImageIO
import UIKit

extension ProjectStore {
    /// Temporary source resources, not another project format or backup policy. Files are immutable;
    /// each handle removes its own file and the last handle removes the session directory.
    final class RasterStorage {
        private static let liveLock = NSLock()
        private static var livePaths = Set<URL>()
        private static let launchCleanup: Void = { cleanupStaleSessions(in: FileManager.default.temporaryDirectory) }()
        let url: URL
        private let lock = NSLock()
        private var created = false

        init(url: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaintRasterSources-\(UUID().uuidString)", isDirectory: true)) {
            self.url = url
        }

        static func cleanupStaleSessionsOnLaunch() { _ = launchCleanup }

        /// Only this source owner's temporary namespace. A process crash skips deinits; startup
        /// maintenance removes those abandoned directories while all current owners remain pinned.
        static func cleanupStaleSessions(in temporaryRoot: URL) {
            ProjectStore.serializingPackageMutation {
                liveLock.lock()
                let live = livePaths
                liveLock.unlock()
                guard let children = try? FileManager.default.contentsOfDirectory(at: temporaryRoot,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
                let prefix = "PaintRasterSources-"
                for child in children {
                    let name = child.lastPathComponent
                    guard name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
                          !live.contains(child.standardizedFileURL),
                          let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          values.isDirectory == true, values.isSymbolicLink != true else { continue }
                    try? FileManager.default.removeItem(at: child)
                }
            }
        }

        enum ResourceKind: String { case png, native = "raster" }
        func newResourceURL(kind: ResourceKind = .png) -> URL? {
            ProjectStore.serializingPackageMutation {
                lock.lock(); defer { lock.unlock() }
                if !created {
                    // Exclusive directory creation gives this path exactly one owner. The same
                    // serializer excludes a concurrent stale sweep before it enters the live set.
                    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
                    catch { return nil }
                    Self.liveLock.lock()
                    Self.livePaths.insert(url.standardizedFileURL)
                    Self.liveLock.unlock()
                    created = true
                }
                return url.appendingPathComponent("\(UUID().uuidString).\(kind.rawValue)")
            }
        }

        deinit {
            if created {
                try? FileManager.default.removeItem(at: url)
                Self.liveLock.lock()
                Self.livePaths.remove(url.standardizedFileURL)
                Self.liveLock.unlock()
            }
        }
    }

    final class RasterBacking {
        enum Payload {
            case png
            case native(rawCount: Int, storedCount: Int, compressed: Bool, digest: Data)
        }
        let url: URL
        let descriptor: RasterImageDescriptor
        let payload: Payload
        var size: CGSize { descriptor.size }
        private let storage: RasterStorage

        private init(url: URL, descriptor: RasterImageDescriptor, payload: Payload, storage: RasterStorage) {
            self.url = url; self.descriptor = descriptor; self.payload = payload; self.storage = storage
        }
        var isPNG: Bool { if case .png = payload { return true }; return false }

        static func protect(_ source: URL, using residency: RasterResidency)
            -> Result<RasterBacking, RasterResidency.Failure> {
            ProjectStore.serializingPackageMutation {
                guard let descriptor = imageDescriptor(at: source), let destination = residency.storage.newResourceURL(),
                      ProjectStore.cloneRasterResource(from: source, to: destination) else { return .failure(.unreadableBacking) }
                return .success(RasterBacking(url: destination, descriptor: descriptor, payload: .png, storage: residency.storage))
            }
        }

        // Cache-disabled ImageIO creates a metadata-bearing image here. No provider bytes or
        // CGContext are requested, but ImageIO is opaque: owner allocation counters alone cannot
        // establish that its implementation did no internal decoding.
        private static func imageDescriptor(at url: URL) -> RasterImageDescriptor? {
            autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL,
                        [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let image = CGImageSourceCreateImageAtIndex(source, 0,
                        [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: true] as CFDictionary) else { return nil }
                let orientations: [Int: UIImage.Orientation] = [1: .up, 2: .upMirrored, 3: .down, 4: .downMirrored,
                    5: .leftMirrored, 6: .right, 7: .rightMirrored, 8: .left]
                let value = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                guard let orientation = orientations[value] else { return nil }
                return RasterImageDescriptor(UIImage(cgImage: image, scale: 1, orientation: orientation))
            }
        }

        struct Decoded {
            let lease: RasterPixelBuffer.ReadLease
            var isTransparent: Bool { lease.isFullyTransparent }
        }
        struct Checkpoint {
            let backing: RasterBacking
            var encodeSeconds = 0.0
            var writeSeconds = 0.0
            var bytesWritten = 0
            var encoded = false
        }

        func decode(using residency: RasterResidency, excluding: Set<UUID>)
            -> Result<Decoded, RasterResidency.Failure> {
            switch payload {
            case .png:
                return autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,
                            [kCGImageSourceShouldCache: false] as CFDictionary),
                          let cg = CGImageSourceCreateImageAtIndex(source, 0,
                            [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: true] as CFDictionary),
                          cg.width == descriptor.width, cg.height == descriptor.height else { return .failure(.unreadableBacking) }
                    let image = UIImage(cgImage: cg, scale: descriptor.scale, orientation: descriptor.orientation)
                    return RasterPixelBuffer.capture(image, using: residency, durable: true, excluding: excluding)
                        .map { Decoded(lease: $0) }
                }
            case .native(let rawCount, let storedCount, let compressed, let digest):
                let (workingCount, overflow) = storedCount.addingReportingOverflow(compressed ? LZ4Block.decodingScratchBytes : 0)
                guard !overflow else { return .failure(.invalidSize) }
                return residency.admitWorking(workingCount, excluding: excluding).flatMap { working in
                    defer { withExtendedLifetime(working) {} }
                    return residency.admitPixels(rawCount, durable: true, excluding: excluding).flatMap { allocation in
                        guard let buffer = RasterPixelBuffer(allocation: allocation) else { return .failure(.allocationRefused) }
                        let data: Data
                        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
                        catch { return .failure(.unreadableBacking) }
                        guard data.count == storedCount else { return .failure(.unreadableBacking) }
                        let scratchSize = compressed ? LZ4Block.decodingScratchBytes : 0
                        let scratch = scratchSize > 0 ? malloc(scratchSize) : nil
                        guard scratchSize == 0 || scratch != nil else { return .failure(.allocationRefused) }
                        defer { free(scratch) }
                        let decoded = data.withUnsafeBytes { bytes -> Bool in
                            if compressed {
                                return LZ4Block.decode(bytes, into: UnsafeMutableRawBufferPointer(start: buffer.address, count: rawCount), scratch: scratch)
                            }
                            guard storedCount == rawCount, let input = bytes.baseAddress else { return false }
                            buffer.address.copyMemory(from: input, byteCount: rawCount)
                            return true
                        }
                        let lease = RasterPixelBuffer.ReadLease(buffer: buffer, descriptor: descriptor, residency: residency)
                        guard decoded, lease.withBytes({ Self.digest($0) }) == digest else { return .failure(.unreadableBacking) }
                        return .success(Decoded(lease: lease))
                    }
                }
            }
        }

        /// **This version's pixels at thumbnail size, without a canvas-sized bitmap being kept.**
        /// When the version's blankness is already known and the file is a PNG, ImageIO downsamples
        /// it straight from the file and no canvas-sized image is ever decoded. Otherwise the file is
        /// decoded into a lease that lives only for the one draw — never stored on the source, which
        /// would hold it charged against the residency until the next eviction pass — and what that
        /// decode proves about blankness is handed back (`transparent`), because that proof is what
        /// heals a legacy package's transparent PNG on load.
        func thumbnail(fitting size: CGSize, format: UIGraphicsImageRendererFormat, blanknessKnown: Bool,
                       using residency: RasterResidency, excluding: Set<UUID>)
            -> Result<(image: UIImage, transparent: Bool?), RasterResidency.Failure> {
            if blanknessKnown, case .png = payload {
                let longSide = max(size.width, size.height) * format.scale
                let small: UIImage? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,
                            [kCGImageSourceShouldCache: false] as CFDictionary),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCache: false,
                            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(longSide.rounded(.up)))] as CFDictionary)
                    else { return nil }
                    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
                    }
                }
                return small.map { .success(($0, nil)) } ?? .failure(.unreadableBacking)
            }
            return decode(using: residency, excluding: excluding).flatMap { decoded in
                autoreleasepool {
                    decoded.lease.image().map { image in
                        (UIGraphicsImageRenderer(size: size, format: format).image { _ in
                            image.draw(in: CGRect(origin: .zero, size: size))
                        }, decoded.isTransparent)
                    }
                }
            }
        }

        private static func digest(_ bytes: UnsafeRawBufferPointer) -> Data {
            Data(SHA256.hash(data: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                count: bytes.count, deallocator: .none)))
        }

        /// Authoritative process-local backing: only bytes are persisted; native layout stays in
        /// this immutable handle. The existing serializer and storage lifetime own every resource.
        static func checkpointNative(_ lease: RasterPixelBuffer.ReadLease)
            -> Result<RasterBacking, RasterResidency.Failure> {
            precondition(ProjectStore.isPerformingPackageMutation)
            let residency = lease.residency, count = lease.allocation.byteCount
            guard let workspace = LZ4Block.checkpointWorkingBytes(count) else { return .failure(.invalidSize) }
            return residency.admitCheckpointWorking(workspace).flatMap { working in
                defer { withExtendedLifetime(working) {} }
                return lease.withBytes { bytes in
                    let compress = LZ4Block.compressesWithinCheckpoint(count)
                    let scratch = compress && LZ4Block.encodingScratchBytes > 0 ? malloc(LZ4Block.encodingScratchBytes) : nil
                    let output = compress ? malloc(count) : nil
                    guard !compress || (output != nil && (LZ4Block.encodingScratchBytes == 0 || scratch != nil)) else {
                        free(scratch); free(output); return .failure(.allocationRefused)
                    }
                    defer { free(scratch); free(output) }
                    let written = output.map { LZ4Block.encode(bytes, into: UnsafeMutableRawBufferPointer(start: $0, count: count), scratch: scratch) } ?? 0
                    let compressed = written > 0 && written < count
                    let storedCount = compressed ? written : count
                    let pointer = compressed ? output! : UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
                    let data = Data(bytesNoCopy: pointer, count: storedCount, deallocator: .none)
                    guard let destination = residency.storage.newResourceURL(kind: .native) else { return .failure(.checkpointFailed) }
                    do { try data.write(to: destination, options: .atomic) }
                    catch { try? FileManager.default.removeItem(at: destination); return .failure(.checkpointFailed) }
                    return .success(RasterBacking(url: destination, descriptor: lease.descriptor,
                        payload: .native(rawCount: count, storedCount: storedCount, compressed: compressed, digest: digest(bytes)),
                        storage: residency.storage))
                }
            }
        }

        static func admitCheckpoint(_ image: UIImage, using residency: RasterResidency, excluding: Set<UUID>)
            -> Result<RasterResidency.Allocation, RasterResidency.Failure> {
            guard let cg = image.cgImage else { return .failure(.unreadableBacking) }
            let (bytes, overflow) = cg.bytesPerRow.multipliedReportingOverflow(by: cg.height)
            let (working, workingOverflow) = bytes.multipliedReportingOverflow(by: 2)
            guard !overflow, !workingOverflow else { return .failure(.invalidSize) }
            return residency.admitCheckpointWorking(working, excluding: excluding)
        }

        /// Public PNG is derived once per immutable version. It must never become the native
        /// checkpoint of a source whose current pixels carry a richer layout or decode table.
        static func checkpoint(_ image: UIImage, using residency: RasterResidency,
                               encoder: RasterResidency.Allocation) -> Result<Checkpoint, RasterResidency.Failure> {
            precondition(ProjectStore.isPerformingPackageMutation)
            defer { withExtendedLifetime(encoder) {} }
            return autoreleasepool {
                guard image.cgImage != nil,
                      let destination = residency.storage.newResourceURL() else { return .failure(.checkpointFailed) }
                let started = CFAbsoluteTimeGetCurrent()
                guard let data = ProjectStore.encodeRasterPNG(image) else { return .failure(.checkpointFailed) }
                let encoded = CFAbsoluteTimeGetCurrent() - started, writeStarted = CFAbsoluteTimeGetCurrent()
                do { try data.write(to: destination, options: .atomic) }
                catch { try? FileManager.default.removeItem(at: destination); return .failure(.checkpointFailed) }
                guard let descriptor = imageDescriptor(at: destination) else {
                    try? FileManager.default.removeItem(at: destination); return .failure(.checkpointFailed)
                }
                return .success(Checkpoint(backing: RasterBacking(url: destination, descriptor: descriptor,
                    payload: .png, storage: residency.storage), encodeSeconds: encoded,
                    writeSeconds: CFAbsoluteTimeGetCurrent() - writeStarted, bytesWritten: data.count, encoded: true))
            }
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }
}
