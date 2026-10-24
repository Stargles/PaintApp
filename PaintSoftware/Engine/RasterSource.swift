import Foundation
import UIKit

/// One immutable version of a cel's raster or baked tier. A snapshot retains this small handle;
/// pixels are acquired only when a consumer actually draws or encodes this version.
final class RasterSource: RasterResidencyCandidate {
    let residencyID = UUID()
    let size: CGSize
    let residency: RasterResidency
    private let lock = NSLock()
    private var image: UIImage?
    private var backing: ProjectStore.RasterBacking?
    private var loading: DispatchGroup?
    private var isCheckpointing = false
    private weak var originalAllocation: RasterResidency.Allocation?

    private init(size: CGSize, residency: RasterResidency, image: UIImage?, backing: ProjectStore.RasterBacking?,
                 allocation: RasterResidency.Allocation? = nil) {
        self.size = size
        self.residency = residency
        self.image = image
        self.backing = backing
        self.originalAllocation = allocation
        residency.register(self)
    }

    static func snapshot(of surface: RasterSurface, size: CGSize) -> Result<RasterSource, RasterResidency.Failure> {
        surface.image().map { image in
            RasterSource(size: size, residency: surface.residency, image: image, backing: nil,
                         allocation: surface.allocation)
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
        let (inputBytes, overflow) = cg.bytesPerRow.multipliedReportingOverflow(by: cg.height)
        guard !overflow else { return .failure(.invalidSize) }
        return residency.admitWorking(inputBytes).flatMap { borrowed in
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
        lock.lock()
        while let loading {
            lock.unlock()
            loading.wait()
            lock.lock()
        }
        if let image {
            lock.unlock()
            residency.touch(residencyID)
            return .success(image)
        }
        guard let backing else {
            lock.unlock()
            return .failure(.unreadableBacking)
        }
        let loading = DispatchGroup()
        loading.enter()
        self.loading = loading
        lock.unlock()
        // No source/owner lock crosses decoding or admission. Another worker shares the result.
        let result = backing.decode(using: residency, excluding: [residencyID])
        lock.lock()
        if case .success(let image) = result { self.image = image }
        self.loading = nil
        lock.unlock()
        loading.leave()
        residency.touch(residencyID)
        return result
    }

    /// A durable version clones without decoding. A dirty version uses the same PNG serializer and
    /// serial queue as normal saving; its backing is owned by this resource's lifetime.
    func copyPNG(to destination: URL) -> Result<Void, RasterResidency.Failure> {
        checkpoint().flatMap { backing in
            ProjectStore.cloneRasterResource(from: backing.url, to: destination)
                ? .success(()) : .failure(.checkpointFailed)
        }
    }

    private func checkpoint() -> Result<ProjectStore.RasterBacking, RasterResidency.Failure> {
        lock.lock()
        if let backing { lock.unlock(); return .success(backing) }
        // A package writer can be ahead of this version's already queued checkpoint. Waiting here
        // would block the only queue capable of finishing it, so save/render admission must retry.
        guard !isCheckpointing else { lock.unlock(); return .failure(.checkpointPending) }
        guard let image else { lock.unlock(); return .failure(.unreadableBacking) }
        isCheckpointing = true
        lock.unlock()
        let admission = ProjectStore.RasterBacking.admitCheckpoint(image, using: residency, excluding: [residencyID])
        let encoder: RasterResidency.Allocation
        switch admission {
        case .success(let allocation): encoder = allocation
        case .failure(let failure):
            lock.lock(); isCheckpointing = false; lock.unlock()
            return .failure(failure)
        }
        if ProjectStore.isPerformingPackageMutation {
            let result = ProjectStore.RasterBacking.checkpoint(image, using: residency, encoder: encoder)
            finishCheckpoint(result)
            return result
        }
        ProjectStore.enqueueRasterCheckpoint { [self] in
            let result = ProjectStore.RasterBacking.checkpoint(image, using: residency, encoder: encoder)
            finishCheckpoint(result, releasingImage: true)
        }
        return .failure(.checkpointPending)
    }

    private func finishCheckpoint(_ result: Result<ProjectStore.RasterBacking, RasterResidency.Failure>,
                                  releasingImage: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if case .success(let backing) = result {
            self.backing = backing
            originalAllocation?.markDurable()
            if releasingImage { image = nil }
        }
        isCheckpointing = false
    }

    func releaseResidentPixels() -> Bool {
        // An eviction never waits for a source whose worker may itself be requesting admission.
        guard lock.try() else { return false }
        guard image != nil, loading == nil, !isCheckpointing else { lock.unlock(); return false }
        let needsCheckpoint = backing == nil
        lock.unlock()
        if needsCheckpoint {
            guard case .success = checkpoint() else { return false }
        }
        lock.lock()
        guard backing != nil, loading == nil, !isCheckpointing else { lock.unlock(); return false }
        image = nil
        lock.unlock()
        // An escaping CGImage can still hold these pixels. Its provider retains the allocation;
        // admission reads the remaining charge rather than assuming this dropped the last reader.
        return true
    }
}
