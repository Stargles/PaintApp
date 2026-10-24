import Foundation
import ImageIO
import UIKit

extension ProjectStore {
    /// Temporary source resources, not another project format or backup policy. Files are immutable;
    /// each handle removes its own file and the last handle removes the session directory.
    final class RasterStorage {
        let url: URL
        private let lock = NSLock()
        private var created = false

        init(url: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaintRasterSources-\(UUID().uuidString)", isDirectory: true)) {
            self.url = url
        }

        func newResourceURL() -> URL? {
            lock.lock(); defer { lock.unlock() }
            if !created {
                do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
                catch { return nil }
                created = true
            }
            return url.appendingPathComponent("\(UUID().uuidString).png")
        }

        deinit { if created { try? FileManager.default.removeItem(at: url) } }
    }

    final class RasterBacking {
        let url: URL
        let size: CGSize
        private let storage: RasterStorage

        private init(url: URL, size: CGSize, storage: RasterStorage) {
            self.url = url
            self.size = size
            self.storage = storage
        }

        /// The current document's compressed resource is protected once, before its package can be
        /// swapped or renamed. No image/context is created and no persistent file descriptor is held.
        static func protect(_ source: URL, using residency: RasterResidency)
            -> Result<RasterBacking, RasterResidency.Failure> {
            ProjectStore.serializingPackageMutation {
                guard let size = imageSize(at: source), let destination = residency.storage.newResourceURL(),
                      ProjectStore.cloneRasterResource(from: source, to: destination) else {
                    return .failure(.unreadableBacking)
                }
                return .success(RasterBacking(url: destination, size: size, storage: residency.storage))
            }
        }

        private static func imageSize(at url: URL) -> CGSize? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  RasterSurface.byteCount(width: width, height: height) != nil else { return nil }
            return CGSize(width: width, height: height)
        }

        struct Decoded {
            let image: UIImage
            let isTransparent: Bool
        }

        func decode(using residency: RasterResidency, excluding: Set<UUID>)
            -> Result<Decoded, RasterResidency.Failure> {
            var decodedInput: RasterResidency.Allocation?
            let result: Result<Decoded, RasterResidency.Failure> = autoreleasepool {
                // Creating this uncached CGImage exposes its exact decoded row size before the
                // decoder is asked to draw it. Input decoding is charged as operation working bytes.
                guard let source = CGImageSourceCreateWithURL(url as CFURL,
                        [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateImageAtIndex(source, 0,
                        [kCGImageSourceShouldCache: false] as CFDictionary),
                      image.width == Int(size.width), image.height == Int(size.height) else {
                    return .failure(.unreadableBacking)
                }
                let (inputBytes, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
                guard !overflow else { return .failure(.invalidSize) }
                return residency.admitWorking(inputBytes, excluding: excluding).flatMap { reservation in
                    decodedInput = reservation
                    // Force complete decoding while charged. A corrupt resource must fail here,
                    // rather than a later lazy draw quietly leaving a transparent output behind.
                    guard let decoded = CGImageSourceCreateImageAtIndex(source, 0,
                        [kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceShouldAllowFloat: false] as CFDictionary),
                          decoded.width == image.width, decoded.height == image.height,
                          decoded.bytesPerRow <= image.bytesPerRow else { return .failure(.unreadableBacking) }
                    return RasterSurface.allocate(width: decoded.width, height: decoded.height,
                            using: residency, excluding: excluding).flatMap { surface in
                        surface.mutate { context in
                            UIGraphicsPushContext(context)
                            UIImage(cgImage: decoded).draw(in: CGRect(origin: .zero, size: size))
                            UIGraphicsPopContext()
                        }.flatMap {
                            surface.allocation.markDurable()
                            let transparent = surface.isFullyTransparent
                            return surface.image().map { Decoded(image: $0, isTransparent: transparent) }
                        }
                    }
                }
            }
            // The decoder's autoreleased/native objects have drained before its charge is released.
            withExtendedLifetime(decodedInput) {}
            return result
        }

        static func admitCheckpoint(_ image: UIImage, using residency: RasterResidency, excluding: Set<UUID>)
            -> Result<RasterResidency.Allocation, RasterResidency.Failure> {
            guard let cg = image.cgImage else { return .failure(.unreadableBacking) }
            let (bytes, overflow) = cg.bytesPerRow.multipliedReportingOverflow(by: cg.height)
            let (working, workingOverflow) = bytes.multipliedReportingOverflow(by: 2)
            guard !overflow, !workingOverflow else { return .failure(.invalidSize) }
            // One encoded output plus encoder working headroom is reserved before entering the
            // normal save queue. Failure retains the resident original and refuses eviction/save.
            return residency.admitCheckpointWorking(working, excluding: excluding)
        }

        static func checkpoint(_ image: UIImage, using residency: RasterResidency,
                               encoder: RasterResidency.Allocation) -> Result<RasterBacking, RasterResidency.Failure> {
            precondition(ProjectStore.isPerformingPackageMutation)
            defer { withExtendedLifetime(encoder) {} }
            return autoreleasepool {
                guard let cg = image.cgImage else { return .failure(.unreadableBacking) }
                guard let destination = residency.storage.newResourceURL(),
                      let data = ProjectStore.encodeRasterPNG(image) else { return .failure(.checkpointFailed) }
                do { try data.write(to: destination, options: .atomic) }
                catch { try? FileManager.default.removeItem(at: destination); return .failure(.checkpointFailed) }
                return .success(RasterBacking(url: destination,
                    size: CGSize(width: cg.width, height: cg.height), storage: residency.storage))
            }
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }
}
