import Foundation
import UIKit

/// One immutable version of a cel raster, baked tier or placed picture. A snapshot retains this small handle;
/// pixels are acquired only when a consumer actually draws or encodes this version.
final class RasterSource: RasterResidencyCandidate {
    let residencyID = UUID()
    let size: CGSize
    let descriptor: RasterImageDescriptor
    let logicalPayloadBytes: Int
    let residency: RasterResidency
    private let lock = NSLock()
    private var image: UIImage?
    private var lease: RasterSurface.ReadLease?
    private var backing: ProjectStore.RasterBacking?
    private var exportedPNG: ProjectStore.RasterBacking?
    private var loading: DispatchGroup?
    private var isCheckpointing = false
    private var transparencyProven: Bool?
    private weak var originalAllocation: RasterResidency.Allocation?

    private init(size: CGSize, residency: RasterResidency, backing: ProjectStore.RasterBacking?,
                 lease: RasterSurface.ReadLease? = nil) {
        self.size = size
        guard let descriptor = lease?.descriptor ?? backing?.descriptor else { preconditionFailure("A source requires immutable native pixels or backing") }
        self.descriptor = descriptor
        self.logicalPayloadBytes = lease?.allocation.byteCount ?? descriptor.byteCount ?? Int.max
        self.residency = residency
        self.backing = backing
        self.lease = lease
        self.originalAllocation = lease?.allocation
        residency.register(self)
    }

    deinit { residency.unregister(residencyID) }

    static func snapshot(of surface: RasterSurface, size: CGSize) -> RasterSource {
        RasterSource(size: size, residency: surface.residency, backing: nil,
                     lease: surface.readLease())
    }

    static func backed(by backing: ProjectStore.RasterBacking, using residency: RasterResidency) -> RasterSource {
        RasterSource(size: backing.size, residency: residency, backing: backing)
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
        guard let lease, lease.descriptor.alpha8Layout != nil else { lock.unlock(); return .success(false) }
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
        // Row padding is ignored; this is the exact maximum number of native alpha-cell visits.
        guard admittingScan(lease.descriptor.width * lease.descriptor.height) else { return .failure(.budgetExceeded) }
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

    /// Placed pictures retain their native samples, profile, decode table and presentation.
    /// The foreign wrapper is borrowed only while an independently owned provider is prepared.
    static func capturePlaced(_ image: UIImage, using residency: RasterResidency = .shared)
        -> Result<RasterSource, RasterResidency.Failure> {
        RasterPixelBuffer.capture(image, using: residency).map { lease in
            RasterSource(size: image.size, residency: residency, backing: nil, lease: lease)
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
        var decodedLease: RasterPixelBuffer.ReadLease?
        if let lease { result = lease.image() }
        else if let backing {
            result = backing.decode(using: residency, excluding: [residencyID]).flatMap {
                transparent = $0.isTransparent
                decodedLease = $0.lease
                return $0.lease.image()
            }
        } else { result = .failure(.unreadableBacking) }
        lock.lock()
        if case .success(let image) = result {
            self.image = image
            if let decodedLease { self.lease = decodedLease; originalAllocation = decodedLease.allocation }
            if let transparent { transparencyProven = transparent }
        }
        self.loading = nil
        lock.unlock()
        loading.leave()
        residency.touch(residencyID)
        return result
    }

    /// Public files are derived once per immutable version and cloned by every later save.
    func copyPNG(to destination: URL) -> Result<Void, RasterResidency.Failure> {
        prepareForSave().flatMap { checkpoint in
            ProjectStore.cloneRasterResource(from: checkpoint.backing.url, to: destination)
                ? .success(()) : .failure(.checkpointFailed)
        }
    }

    func prepareForSave() -> Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure> {
        prepareBacking(exportPNG: true)
    }

    /// Authoritative eviction never passes through the public PNG encoder.
    func checkpointForEviction() -> Result<ProjectStore.RasterBacking, RasterResidency.Failure> {
        prepareBacking(exportPNG: false).map(\.backing)
    }

    private func prepareBacking(exportPNG: Bool) -> Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure> {
        lock.lock()
        let ready = exportPNG ? (exportedPNG ?? (backing?.isPNG == true ? backing : nil)) : backing
        if let ready { lock.unlock(); return .success(.init(backing: ready)) }
        guard !isCheckpointing, loading == nil else { lock.unlock(); return .failure(.checkpointPending) }
        isCheckpointing = true
        lock.unlock()
        let work = { [self] () -> Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure> in
            let result = performPreparation(exportPNG: exportPNG)
            lock.lock(); isCheckpointing = false; lock.unlock()
            return result
        }
        if ProjectStore.isPerformingPackageMutation { return work() }
        ProjectStore.enqueueRasterCheckpoint { [self] in
            if case .success = work() {
                lock.lock(); image = nil; lease = nil; lock.unlock()
            }
        }
        return .failure(.checkpointPending)
    }

    private func performPreparation(exportPNG: Bool) -> Result<ProjectStore.RasterBacking.Checkpoint, RasterResidency.Failure> {
        precondition(ProjectStore.isPerformingPackageMutation)
        lock.lock(); let native = backing; lock.unlock()
        if native == nil {
            // resolveImage only borrows our own charged provider; never a foreign UIImage alias.
            if case .failure(let failure) = resolveImage() { return .failure(failure) }
            lock.lock(); let pixels = lease; lock.unlock()
            guard let pixels else { return .failure(.unreadableBacking) }
            switch ProjectStore.RasterBacking.checkpointNative(pixels) {
            case .failure(let failure): return .failure(failure)
            case .success(let prepared):
                lock.lock(); backing = prepared; originalAllocation?.markDurable(); lock.unlock()
            }
        }
        lock.lock(); let authoritative = backing; lock.unlock()
        guard let authoritative else { return .failure(.checkpointFailed) }
        guard exportPNG else { return .success(.init(backing: authoritative)) }
        if authoritative.isPNG { return .success(.init(backing: authoritative)) }
        return resolveImage().flatMap { image in
            ProjectStore.RasterBacking.admitCheckpoint(image, using: residency, excluding: [residencyID]).flatMap { encoder in
                ProjectStore.RasterBacking.checkpoint(image, using: residency, encoder: encoder).map { checkpoint in
                    lock.lock(); exportedPNG = checkpoint.backing; lock.unlock()
                    return checkpoint
                }
            }
        }
    }

    func releaseResidentPixels() -> Bool {
        guard lock.try() else { return false }
        guard image != nil || lease != nil, loading == nil, !isCheckpointing else { lock.unlock(); return false }
        let needsCheckpoint = backing == nil
        lock.unlock()
        if needsCheckpoint {
            guard case .success = checkpointForEviction() else { return false }
        }
        lock.lock()
        guard backing != nil, loading == nil, !isCheckpointing else { lock.unlock(); return false }
        image = nil; lease = nil
        lock.unlock()
        return true
    }
}
