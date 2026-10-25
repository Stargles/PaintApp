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
    private var lease: RasterSurface.ReadLease?
    private var backing: ProjectStore.RasterBacking?
    private var loading: DispatchGroup?
    private var isCheckpointing = false
    private var transparencyProven: Bool?
    private weak var originalAllocation: RasterResidency.Allocation?

    private init(size: CGSize, residency: RasterResidency, image: UIImage?, backing: ProjectStore.RasterBacking?,
                 lease: RasterSurface.ReadLease? = nil) {
        self.size = size
        self.residency = residency
        self.image = image
        self.backing = backing
        self.lease = lease
        self.originalAllocation = lease?.allocation
        residency.register(self)
    }

    static func snapshot(of surface: RasterSurface, size: CGSize) -> RasterSource {
        RasterSource(size: size, residency: surface.residency, image: nil, backing: nil,
                     lease: surface.readLease())
    }

    static func backed(by backing: ProjectStore.RasterBacking, using residency: RasterResidency) -> RasterSource {
        RasterSource(size: backing.size, residency: residency, image: nil, backing: backing)
    }

    /// Persistent pixel operations share this admitted drawing seam. The drawing must complete in
    /// private storage before an immutable handle is published or a live cel can be replaced.
    static func render(size: CGSize, using residency: RasterResidency = .shared,
                       drawing: (CGContext) -> Bool) -> Result<RasterSource, RasterResidency.Failure> {
        RasterSurface.render(size: size, using: residency, drawing: drawing).map { snapshot(of: $0, size: size) }
    }

    func resized(to size: CGSize, placing content: CGRect) -> Result<RasterSource, RasterResidency.Failure> {
        resolveImage().flatMap { image in
            Self.render(size: size, using: residency) { context in
                if content.size != self.size { context.interpolationQuality = .high }
                image.draw(in: content)
                return true
            }
        }
    }

    func cropped(to rect: CGRect) -> Result<RasterSource, RasterResidency.Failure> {
        resolveImage().flatMap { image in
            Self.render(size: rect.size, using: residency) { _ in
                image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
                return true
            }
        }
    }

    func flipped(horizontal: Bool) -> Result<RasterSource, RasterResidency.Failure> {
        resolveImage().flatMap { image in
            Self.render(size: size, using: residency) { context in
                if horizontal { context.translateBy(x: size.width, y: 0); context.scaleBy(x: -1, y: 1) }
                else { context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1) }
                image.draw(in: CGRect(origin: .zero, size: size))
                return true
            }
        }
    }

    var isCertainlyTransparent: Bool {
        lock.lock(); defer { lock.unlock() }
        return transparencyProven == true
    }

    /// Called on a preparation worker before contributor classification. A pinned version needs
    /// no image, decode or pixel allocation. Metadata reads never initiate this exact alpha scan.
    func prepareTransparencyProof(admittingScan: (Int) -> Bool) -> Result<Bool, RasterResidency.Failure> {
        lock.lock()
        while let loading {
            lock.unlock()
            loading.wait()
            lock.lock()
        }
        if let transparencyProven { lock.unlock(); return .success(transparencyProven) }
        // Unresolved backing is unknown. Its ordinary admitted decode supplies the same proof;
        // preparation must not accumulate decoded images before the selected draw is admitted.
        guard let lease else { lock.unlock(); return .success(false) }
        let loading = DispatchGroup()
        loading.enter()
        self.loading = loading
        lock.unlock()
        var inspected: Bool?
        defer {
            lock.lock()
            if let inspected { transparencyProven = inspected }
            self.loading = nil
            lock.unlock()
            loading.leave()
        }
        // This is the existing tightly packed RGBA buffer's exact maximum alpha-cell visits.
        guard admittingScan(lease.allocation.byteCount / 4) else { return .failure(.budgetExceeded) }
        let transparent = lease.isFullyTransparent
        inspected = transparent
        return .success(transparent)
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
                }.map { snapshot(of: surface, size: CGSize(width: cg.width, height: cg.height)) }
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
        let lease = self.lease
        let backing = self.backing
        guard lease != nil || backing != nil else {
            lock.unlock()
            return .failure(.unreadableBacking)
        }
        let loading = DispatchGroup()
        loading.enter()
        self.loading = loading
        lock.unlock()
        // No source/owner lock crosses decoding or admission. Another worker shares the result.
        let result: Result<UIImage, RasterResidency.Failure>
        var transparent: Bool?
        if let lease { result = lease.image() }
        else if let backing {
            result = backing.decode(using: residency, excluding: [residencyID]).map {
                transparent = $0.isTransparent
                return $0.image
            }
        } else { result = .failure(.unreadableBacking) }
        lock.lock()
        if case .success(let image) = result {
            self.image = image
            if let transparent { transparencyProven = transparent }
        }
        self.loading = nil
        lock.unlock()
        loading.leave()
        residency.touch(residencyID)
        return result
    }

    /// A durable version clones without decoding. A dirty version uses the same PNG serializer and
    /// serial queue as normal saving; its backing is owned by this resource's lifetime.
    func copyPNG(to destination: URL) -> Result<Void, RasterResidency.Failure> {
        checkpoint().flatMap { checkpoint in
            ProjectStore.cloneRasterResource(from: checkpoint.backing.url, to: destination)
                ? .success(()) : .failure(.checkpointFailed)
        }
    }

    /// Called serially before the package's parallel file walk. Dirty versions encode one at a
    /// time; unchanged versions require no decode and contribute no new encode cost.
    func prepareForSave() -> Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure> { checkpoint() }

    private func checkpoint() -> Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure> {
        lock.lock()
        if let backing { lock.unlock(); return .success(.init(backing: backing)) }
        // A package writer can be ahead of this version's already queued checkpoint. Waiting here
        // would block the only queue capable of finishing it, so save/render admission must retry.
        guard !isCheckpointing else { lock.unlock(); return .failure(.checkpointPending) }
        let heldImage = image
        let lease = self.lease
        guard heldImage != nil || lease != nil else { lock.unlock(); return .failure(.unreadableBacking) }
        isCheckpointing = true
        lock.unlock()
        let resolvedImage = heldImage.map(Result<UIImage, RasterResidency.Failure>.success)
            ?? lease.map { $0.image() } ?? .failure(.unreadableBacking)
        let image: UIImage
        switch resolvedImage {
        case .success(let resolved): image = resolved
        case .failure(let failure):
            lock.lock(); isCheckpointing = false; lock.unlock()
            return .failure(failure)
        }
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

    private func finishCheckpoint(_ result: Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure>,
                                  releasingImage: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if case .success(let checkpoint) = result {
            self.backing = checkpoint.backing
            originalAllocation?.markDurable()
            if releasingImage { image = nil; lease = nil }
        }
        isCheckpointing = false
    }

    func releaseResidentPixels() -> Bool {
        // An eviction never waits for a source whose worker may itself be requesting admission.
        guard lock.try() else { return false }
        guard image != nil || lease != nil, loading == nil, !isCheckpointing else { lock.unlock(); return false }
        let needsCheckpoint = backing == nil
        lock.unlock()
        if needsCheckpoint {
            guard case .success = checkpoint() else { return false }
        }
        lock.lock()
        guard backing != nil, loading == nil, !isCheckpointing else { lock.unlock(); return false }
        image = nil
        lease = nil
        lock.unlock()
        // An escaping CGImage can still hold these pixels. Its provider retains the allocation;
        // admission reads the remaining charge rather than assuming this dropped the last reader.
        return true
    }
}
