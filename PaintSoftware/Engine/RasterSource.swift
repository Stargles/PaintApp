import Foundation
import UIKit

/// One immutable version of a cel's raster or baked tier. A snapshot retains this small handle;
/// pixels are acquired only when a consumer actually draws or encodes this version.
final class RasterSource: RasterResidencyCandidate {
    let residencyID = UUID()
    let size: CGSize
    let residency: RasterResidency
    private let condition = NSCondition()
    private var image: UIImage?
    private var backing: ProjectStore.RasterBacking?
    private var isLoading = false
    private var isCheckpointing = false

    private init(size: CGSize, residency: RasterResidency, image: UIImage?, backing: ProjectStore.RasterBacking?) {
        self.size = size
        self.residency = residency
        self.image = image
        self.backing = backing
        residency.register(self)
    }

    static func snapshot(of surface: RasterSurface, size: CGSize) -> Result<RasterSource, RasterResidency.Failure> {
        surface.image().map { image in
            RasterSource(size: size, residency: surface.residency, image: image, backing: nil)
        }
    }

    static func backed(by backing: ProjectStore.RasterBacking, using residency: RasterResidency) -> RasterSource {
        RasterSource(size: backing.size, residency: residency, image: nil, backing: backing)
    }

    /// A foreign renderer's output is copied into the source owner's provider-backed allocation.
    /// Its existing picture is a borrowed working input during that copy, never an uncharged source.
    static func capture(_ image: UIImage, using residency: RasterResidency = .shared)
        -> Result<RasterSource, RasterResidency.Failure> {
        guard let cg = image.cgImage,
              RasterSurface.byteCount(width: cg.width, height: cg.height) != nil else {
            return .failure(.invalidSize)
        }
        return residency.admitWorking(cg.bytesPerRow * cg.height).flatMap { borrowed in
            defer { withExtendedLifetime(borrowed) {} }
            return RasterSurface.allocate(width: cg.width, height: cg.height, using: residency).flatMap { surface in
                surface.mutate { context in
                    UIGraphicsPushContext(context)
                    image.draw(in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                    UIGraphicsPopContext()
                }.flatMap { snapshot(of: surface, size: CGSize(width: cg.width, height: cg.height)) }
            }
        }
    }

    func resolveImage() -> Result<UIImage, RasterResidency.Failure> {
        condition.lock()
        while isLoading { condition.wait() }
        if let image {
            condition.unlock()
            residency.touch(residencyID)
            return .success(image)
        }
        guard let backing else {
            condition.unlock()
            return .failure(.unreadableBacking)
        }
        isLoading = true
        condition.unlock()
        // No source/owner lock crosses decoding or admission. Another worker shares the result.
        let result = backing.decode(using: residency, excluding: [residencyID])
        condition.lock()
        if case .success(let image) = result { self.image = image }
        isLoading = false
        condition.broadcast()
        condition.unlock()
        residency.touch(residencyID)
        return result
    }

    /// A durable version clones without decoding. A dirty version uses the same PNG serializer and
    /// serial queue as normal saving; its backing is owned by this resource's lifetime.
    func copyPNG(to destination: URL) -> Result<Void, RasterResidency.Failure> {
        checkpoint().flatMap { backing in
            ProjectStore.serializingPackageMutation {
                ProjectStore.cloneRasterResource(from: backing.url, to: destination)
                    ? .success(()) : .failure(.checkpointFailed)
            }
        }
    }

    private func checkpoint(mayWait: Bool = true) -> Result<ProjectStore.RasterBacking, RasterResidency.Failure> {
        condition.lock()
        while isCheckpointing {
            guard mayWait else { condition.unlock(); return .failure(.budgetExceeded) }
            condition.wait()
        }
        if let backing { condition.unlock(); return .success(backing) }
        guard let image else { condition.unlock(); return .failure(.unreadableBacking) }
        isCheckpointing = true
        condition.unlock()
        let result = ProjectStore.RasterBacking.checkpoint(image, using: residency, excluding: [residencyID])
        condition.lock()
        if case .success(let backing) = result { self.backing = backing }
        isCheckpointing = false
        condition.broadcast()
        condition.unlock()
        return result
    }

    func releaseResidentPixels() -> Bool {
        // An eviction never waits for a source whose worker may itself be requesting admission.
        guard condition.try() else { return false }
        guard image != nil, !isLoading, !isCheckpointing else { condition.unlock(); return false }
        let needsCheckpoint = backing == nil
        condition.unlock()
        if needsCheckpoint {
            guard case .success = checkpoint(mayWait: false) else { return false }
        }
        condition.lock()
        guard backing != nil, !isLoading, !isCheckpointing else { condition.unlock(); return false }
        image = nil
        condition.unlock()
        // An escaping CGImage can still hold these pixels. Its provider retains the allocation;
        // admission reads the remaining charge rather than assuming this dropped the last reader.
        return true
    }
}
