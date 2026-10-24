import CoreGraphics
import UIKit
import XCTest

final class RasterResidencyLogicTests: XCTestCase {
    private let width = 8
    private let height = 4
    private var pictureBytes: Int { width * height * 4 }

    private func surface(_ owner: RasterResidency, color: UIColor = .red) throws -> RasterSurface {
        let surface = try RasterSurface.allocate(width: width, height: height, using: owner).get()
        try paint(surface, color: color)
        return surface
    }

    private func paint(_ surface: RasterSurface, color: UIColor) throws {
        try surface.mutate { context in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.get()
    }

    private func pixel(_ image: CGImage) throws -> [UInt8] {
        let bytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height))
        return Array(bytes.prefix(4))
    }

    func testExtractedCGImageKeepsItsPixelsChargedAfterSurfaceAndUIImageAreReleased() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, hasHeadroom: { _ in true })
        var escaped: CGImage?
        try autoreleasepool {
            let surface = try surface(owner)
            let image = try surface.image().get()
            escaped = try XCTUnwrap(image.cgImage)
        }
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes,
                       "A CGImage escape must retain the allocation after its UIImage has gone")
        XCTAssertEqual(try pixel(XCTUnwrap(escaped)), [255, 0, 0, 255])
        escaped = nil
        XCTAssertEqual(owner.usage.pixelBufferCount, 0)
        XCTAssertEqual(owner.usage.chargedBytes, 0)
    }

    func testRenderingModeAliasKeepsItsPixelsChargedAfterTheOriginalWrapperIsReleased() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, hasHeadroom: { _ in true })
        var alias: UIImage?
        try autoreleasepool {
            let surface = try surface(owner)
            let image = try surface.image().get()
            alias = image.withRenderingMode(.alwaysOriginal)
        }
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
        XCTAssertEqual(try pixel(XCTUnwrap(alias?.cgImage)), [255, 0, 0, 255])
        alias = nil
        XCTAssertEqual(owner.usage.chargedBytes, 0)
    }

    func testEditingAnEscapedVersionCopiesBeforeWritingAndChargesBothExactPictures() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, hasHeadroom: { _ in true })
        var current = try surface(owner)
        weak var oldWrapper: UIImage?
        try autoreleasepool {
            let oldImage = try current.image().get()
            oldWrapper = oldImage
            var old: CGImage? = oldImage.cgImage
            XCTAssertEqual(current.readLeaseCount, 1)
            XCTAssertThrowsError(try paint(current, color: .blue)) { error in
                XCTAssertEqual(error as? RasterResidency.Failure, .writeRequiresCopy)
            }
            current = try current.preparedForWrite().get()
            try paint(current, color: .blue)
            XCTAssertEqual(owner.usage.pixelBufferCount, 2)
            XCTAssertEqual(owner.usage.pixelBytes, pictureBytes * 2)
            XCTAssertEqual(try pixel(XCTUnwrap(old)), [255, 0, 0, 255])
            let new = try current.image().get()
            XCTAssertEqual(try pixel(XCTUnwrap(new.cgImage)), [0, 0, 255, 255])
            old = nil
        }
        // UIKit can autorelease the temporary wrapper used to extract old.cgImage. A real lifetime
        // boundary drains it; dropping one Swift variable cannot revoke a still-live native alias.
        XCTAssertNil(oldWrapper)
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
    }

    func testAnUnresolvedImmutableSourcePinsItsOldPixelsBeforeEditingBegins() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, hasHeadroom: { _ in true })
        var current = try surface(owner)
        var frozen: RasterSource? = RasterSource.snapshot(of: current,
            size: CGSize(width: width, height: height))
        XCTAssertEqual(current.readLeaseCount, 1,
                       "Freezing must pin old pixels before any UIImage or CGImage is requested")
        XCTAssertEqual(owner.usage.allocations, 1)
        current = try current.preparedForWrite().get()
        try paint(current, color: .blue)
        XCTAssertEqual(owner.usage.pixelBufferCount, 2)
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(frozen?.resolveImage().get().cgImage)), [255, 0, 0, 255])
            XCTAssertEqual(try pixel(XCTUnwrap(current.image().get().cgImage)), [0, 0, 255, 255])
        }
        frozen = nil
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
    }

    func testRefusedCopyPreservesThePreviousDrawnPictureAndItsOnlyAllocation() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, hasHeadroom: { _ in true })
        let current = try surface(owner)
        let old = try current.image().get()
        XCTAssertThrowsError(try current.preparedForWrite().get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
        }
        XCTAssertEqual(try pixel(XCTUnwrap(old.cgImage)), [255, 0, 0, 255])
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.highWaterBytes, pictureBytes)
    }

    private final class CachedPicture: RasterResidencyCandidate {
        let residencyID = UUID()
        var image: UIImage?
        init(image: UIImage) { self.image = image }
        func releaseResidentPixels() -> Bool { image = nil; return true }
    }

    func testEvictingAWrapperCannotPretendAnEscapedCGImageGaveItsBytesBack() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, hasHeadroom: { _ in true })
        var escaped: CGImage?
        var cached: CachedPicture!
        try autoreleasepool {
            let surface = try surface(owner)
            let image = try surface.image().get()
            escaped = image.cgImage
            cached = CachedPicture(image: image)
            owner.register(cached)
        }
        XCTAssertThrowsError(try RasterSurface.allocate(width: width, height: height, using: owner).get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
        }
        XCTAssertNil(cached.image)
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
        XCTAssertEqual(try pixel(XCTUnwrap(escaped)), [255, 0, 0, 255])
        escaped = nil
        let replacement = try surface(owner, color: .blue)
        XCTAssertEqual(try pixel(XCTUnwrap(replacement.image().get().cgImage)), [0, 0, 255, 255])
        XCTAssertEqual(owner.usage.highWaterBytes, pictureBytes)
    }

    func testHeadroomRefusalAndOverflowNeverAdmitAnAllocation() {
        let owner = RasterResidency(budgetBytes: pictureBytes, hasHeadroom: { _ in false })
        XCTAssertThrowsError(try RasterSurface.allocate(width: width, height: height, using: owner).get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .allocationRefused)
        }
        XCTAssertThrowsError(try RasterSurface.allocate(width: Int.max, height: 2, using: owner).get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .invalidSize)
        }
        XCTAssertEqual(owner.usage.allocations, 0)
        XCTAssertEqual(owner.usage.chargedBytes, 0)
    }

    func testDirtyPicturesKeepOneCheckpointWorkspaceBeforeTheyCanFillTheBudget() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 5, hasHeadroom: { _ in true })
        let pictures = try (0..<3).map { _ in try surface(owner) }
        XCTAssertEqual(owner.usage.pixelBufferCount, 3)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2,
                       "The largest checkpoint needs one workspace, shared across the serial queue")
        XCTAssertEqual(owner.usage.admittedBytes, pictureBytes * 5)
        XCTAssertThrowsError(try surface(owner)) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
        }
        var workspace: RasterResidency.Allocation? = try owner.admitCheckpointWorking(pictureBytes * 2).get()
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        XCTAssertEqual(owner.usage.workingBytes, pictureBytes * 2)
        XCTAssertEqual(owner.usage.admittedBytes, pictureBytes * 5)
        XCTAssertEqual(try pixel(XCTUnwrap(pictures[2].image().get().cgImage)), [255, 0, 0, 255])
        workspace = nil
        XCTAssertEqual(owner.usage.workingBytes, 0)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2)
    }

    func testWritingACheckpointedBufferMustReadmitItsWorkspaceBeforeChangingPixels() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, hasHeadroom: { _ in true })
        var current = try surface(owner)
        current.allocation.markDurable()
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        XCTAssertThrowsError(try paint(current, color: .blue)) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .writeNotAdmitted)
        }
        current = try current.preparedForWrite().get()
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2)
        try paint(current, color: .blue)
        XCTAssertEqual(try pixel(XCTUnwrap(current.image().get().cgImage)), [0, 0, 255, 255])
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
    }

    func testProtectedPNGClonesWithoutPixelsAndSurvivesItsOriginalPackageReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-backed-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.png")
        let red = CanvasFixture.solidImage(.red,
            rect: CGRect(x: 0, y: 0, width: width, height: height), size: CGSize(width: width, height: height))
        let bytes = try XCTUnwrap(red.pngData())
        try bytes.write(to: original)
        let owner = RasterResidency(budgetBytes: pictureBytes * 8, hasHeadroom: { _ in true })
        let source = RasterSource.backed(by: try ProjectStore.RasterBacking.protect(original, using: owner).get(),
                                         using: owner)
        XCTAssertEqual(owner.usage.allocations, 0, "Protecting a PNG must not decode an editable bitmap")
        let copied = root.appendingPathComponent("cloned.png")
        try source.copyPNG(to: copied).get()
        XCTAssertEqual(try Data(contentsOf: copied), bytes)
        XCTAssertEqual(owner.usage.allocations, 0, "An unchanged save must clone its resource without hydration")
        try FileManager.default.removeItem(at: original)
        let blue = CanvasFixture.solidImage(.blue,
            rect: CGRect(x: 0, y: 0, width: width, height: height), size: CGSize(width: width, height: height))
        try XCTUnwrap(blue.pngData()).write(to: original)
        try autoreleasepool {
            let image = try source.resolveImage().get()
            XCTAssertEqual(try pixel(XCTUnwrap(image.cgImage)), [255, 0, 0, 255])
        }
        XCTAssertTrue(source.releaseResidentPixels())
        XCTAssertEqual(owner.usage.chargedBytes, 0)
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
    }

    func testDirtyVersionCheckpointsOnTheSaveQueueThenReloadsItsExactPixels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-checkpoint-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, hasHeadroom: { _ in true })
        var source: RasterSource!
        try autoreleasepool { source = RasterSource.snapshot(of: try surface(owner), size: CGSize(width: width, height: height)) }
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2)
        let destination = root.appendingPathComponent("saved.png")
        try ProjectStore.serializingPackageMutation { try source.copyPNG(to: destination).get() }
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        XCTAssertEqual(owner.usage.workingBytes, 0)
        XCTAssertTrue(source.releaseResidentPixels())
        XCTAssertEqual(owner.usage.pixelBufferCount, 0)
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(source.resolveImage().get().cgImage)), [255, 0, 0, 255])
        }
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
    }

    func testFailedCheckpointRetainsDirtyPixelsAndRefusesTheCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-refused-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-directory")
        let sentinel = Data([1, 3, 5, 7])
        try sentinel.write(to: blocked)
        let storage = ProjectStore.RasterStorage(url: blocked)
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, storage: storage, hasHeadroom: { _ in true })
        var source: RasterSource!
        try autoreleasepool { source = RasterSource.snapshot(of: try surface(owner), size: CGSize(width: width, height: height)) }
        let destination = root.appendingPathComponent("must-not-appear.png")
        XCTAssertThrowsError(try ProjectStore.serializingPackageMutation { try source.copyPNG(to: destination).get() }) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .checkpointFailed)
        }
        XCTAssertEqual(try Data(contentsOf: blocked), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2)
        XCTAssertEqual(owner.usage.workingBytes, 0)
        XCTAssertEqual(try pixel(XCTUnwrap(source.resolveImage().get().cgImage)), [255, 0, 0, 255])
    }

    func testDeferredBlankProofPreservesASinglePaintedPixel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-blank-proof-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = RasterResidency(budgetBytes: pictureBytes * 8, hasHeadroom: { _ in true })
        let size = CGSize(width: width, height: height)
        let blankURL = root.appendingPathComponent("blank.png")
        try XCTUnwrap(PixelOps.transparentImage(size: size).pngData()).write(to: blankURL)
        let blank = RasterSource.backed(by: try ProjectStore.RasterBacking.protect(blankURL, using: owner).get(), using: owner)
        let cornerURL = root.appendingPathComponent("corner.png")
        let corner = CanvasFixture.solidImage(.red,
            rect: CGRect(x: width - 1, y: height - 1, width: 1, height: 1), size: size)
        try XCTUnwrap(corner.pngData()).write(to: cornerURL)
        let painted = RasterSource.backed(by: try ProjectStore.RasterBacking.protect(cornerURL, using: owner).get(), using: owner)
        XCTAssertEqual(owner.usage.allocations, 0)
        XCTAssertFalse(blank.isCertainlyTransparent, "Unvisited content is never assumed empty")
        try autoreleasepool {
            _ = try blank.resolveImage().get()
            let image = try XCTUnwrap(painted.resolveImage().get().cgImage)
            let bytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height))
            XCTAssertEqual(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 0 }.count, 1)
        }
        XCTAssertTrue(blank.isCertainlyTransparent)
        XCTAssertFalse(painted.isCertainlyTransparent, "Exact alpha proof must retain even one painted texel")
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
    }

    func testTheRealOwnerAdmitsOldAndNew4096PicturesWithCheckpointHeadroom() throws {
        let side = 4096
        let bytes = side * side * 4
        let budget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024) * 2
        let owner = RasterResidency(budgetBytes: budget, hasHeadroom: { _ in true })
        var current = try RasterSurface.allocate(width: side, height: side, using: owner).get()
        try current.mutate { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }.get()
        let old = RasterSource.snapshot(of: current, size: CGSize(width: side, height: side))
        current = try current.preparedForWrite().get()
        try current.mutate { context in
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }.get()
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(old.resolveImage().get().cgImage)), [255, 0, 0, 255])
            XCTAssertEqual(try pixel(XCTUnwrap(current.image().get().cgImage)), [0, 0, 255, 255])
        }
        XCTAssertEqual(owner.usage.pixelBufferCount, 2)
        XCTAssertEqual(owner.usage.pixelBytes, bytes * 2)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, bytes * 2)
        XCTAssertEqual(owner.usage.admittedBytes, bytes * 4)
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, budget)
    }

    func testOwnedEditDrawingKeepsAsymmetricRowsThroughCropAndFlip() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 12, hasHeadroom: { _ in true })
        let input = try RasterSource.render(size: CGSize(width: width, height: height), using: owner) { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(x: 4, y: 3, width: 3, height: 1))
            return true
        }.get()
        let flipped = try input.flipped(horizontal: false).get()
        let cropped = try flipped.cropped(to: CGRect(x: 4, y: 0, width: 3, height: 1)).get()
        try autoreleasepool {
            let image = try XCTUnwrap(cropped.resolveImage().get().cgImage)
            let bytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(image, width: 3, height: 1))
            XCTAssertEqual(bytes, Array(repeating: [UInt8(0), 0, 255, 255], count: 3).flatMap { $0 })
            let original = try XCTUnwrap(input.resolveImage().get().cgImage)
            let originalBytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(original, width: width, height: height))
            XCTAssertEqual(Array(originalBytes.prefix(4)), [255, 0, 0, 255])
            XCTAssertEqual(Array(originalBytes.suffix(4)), [0, 0, 0, 0])
        }
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    func testStartupPrunesOnlyStaleOwnedSessionsAndProtectsLiveBackingsAndUnknownPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-sweep-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = root.appendingPathComponent("PaintRasterSources-\(UUID().uuidString)")
        let unknown = root.appendingPathComponent("PaintRasterSources-unknown")
        let other = root.appendingPathComponent("Projects")
        for directory in [stale, unknown, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([7, 9]).write(to: directory.appendingPathComponent("keep"))
        }
        let liveURL = root.appendingPathComponent("PaintRasterSources-\(UUID().uuidString)")
        let storage = ProjectStore.RasterStorage(url: liveURL)
        let owner = RasterResidency(budgetBytes: pictureBytes * 6, storage: storage, hasHeadroom: { _ in true })
        let original = root.appendingPathComponent("original.png")
        let originalBytes = try XCTUnwrap(CanvasFixture.solidImage(.red,
            rect: CGRect(x: 0, y: 0, width: width, height: height), size: CGSize(width: width, height: height)).pngData())
        try originalBytes.write(to: original)
        let backing = try ProjectStore.RasterBacking.protect(original, using: owner).get()
        let symbolic = root.appendingPathComponent("PaintRasterSources-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: other)
        ProjectStore.RasterStorage.cleanupStaleSessions(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try Data(contentsOf: backing.url), originalBytes)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertEqual(try Data(contentsOf: unknown.appendingPathComponent("keep")), Data([7, 9]))
        XCTAssertEqual(try Data(contentsOf: other.appendingPathComponent("keep")), Data([7, 9]))
        XCTAssertTrue(try symbolic.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(owner.usage.allocations, 0)
        withExtendedLifetime(storage) {}
    }

    @MainActor
    func testRasterUndoRefusalPreservesBothStacksPixelsAndCountsAndRepeatedLandingsReleaseTheirPreparedVersions() throws {
        var allowed = true
        let owner = RasterResidency(budgetBytes: pictureBytes * 6, hasHeadroom: { _ in allowed })
        let before = RasterSource.snapshot(of: try surface(owner), size: CGSize(width: width, height: height))
        let after = RasterSource.snapshot(of: try surface(owner, color: .blue), size: CGSize(width: width, height: height))
        let raster = RasterLayerTexture(size: before.size, source: after, strokeCount: 4)
        let history = UndoHistory(maxCost: pictureBytes * 12)
        var preparedUndo: RasterSource?
        var preparedRedo: RasterSource?
        var bodies: [String] = []
        history.record(.init(label: .brushStroke, cost: pictureBytes * 2,
            prepareUndo: {
                guard case .success(let source) = raster.replacingPatch(with: before, at: .zero) else { return false }
                preparedUndo = source; return true
            }, prepareRedo: {
                guard case .success(let source) = raster.replacingPatch(with: after, at: .zero) else { return false }
                preparedRedo = source; return true
            }, undo: {
                raster.reset(toSource: preparedUndo, strokeCount: 3); preparedUndo = nil; bodies.append("undo")
            }, redo: {
                raster.reset(toSource: preparedRedo, strokeCount: 4); preparedRedo = nil; bodies.append("redo")
            }))
        XCTAssertTrue(history.extendLast(undo: { bodies.append("extension undo") }, redo: { bodies.append("extension redo") }))
        allowed = false
        let version = raster.version
        let usage = owner.usage
        XCTAssertNil(history.undo())
        XCTAssertEqual(history.undoStack.count, 1)
        XCTAssertEqual(history.redoStack.count, 0)
        XCTAssertEqual(bodies, [])
        XCTAssertEqual(raster.version, version)
        XCTAssertEqual(raster.strokeCount, 4)
        XCTAssertEqual(owner.usage.pixelBytes, usage.pixelBytes)
        try autoreleasepool { XCTAssertEqual(try pixel(XCTUnwrap(raster.renderToUIImage().get().cgImage)), [0, 0, 255, 255]) }
        allowed = true
        for _ in 0..<3 {
            XCTAssertEqual(history.undo(), .brushStroke)
            XCTAssertNil(preparedUndo)
            XCTAssertEqual(raster.strokeCount, 3)
            try autoreleasepool { XCTAssertEqual(try pixel(XCTUnwrap(raster.renderToUIImage().get().cgImage)), [255, 0, 0, 255]) }
            allowed = false
            let failedVersion = raster.version
            let failedBytes = owner.usage.pixelBytes
            let previousBodies = bodies
            XCTAssertNil(history.redo())
            XCTAssertEqual(history.undoStack.count, 0)
            XCTAssertEqual(history.redoStack.count, 1)
            XCTAssertEqual(bodies, previousBodies)
            XCTAssertEqual(raster.version, failedVersion)
            XCTAssertEqual(raster.strokeCount, 3)
            XCTAssertEqual(owner.usage.pixelBytes, failedBytes)
            allowed = true
            XCTAssertEqual(history.redo(), .brushStroke)
            XCTAssertNil(preparedRedo)
            XCTAssertEqual(raster.strokeCount, 4)
            try autoreleasepool { XCTAssertEqual(try pixel(XCTUnwrap(raster.renderToUIImage().get().cgImage)), [0, 0, 255, 255]) }
            XCTAssertEqual(owner.usage.pixelBufferCount, 3)
            XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
        }
        XCTAssertEqual(Array(bodies.suffix(4)), ["extension undo", "undo", "redo", "extension redo"])
    }

    @MainActor
    func testALateCelResizeRefusalKeepsEveryEarlierCelGeometrySizeAndHistoryUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-resize-refusal-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var outputs = 0
        let destination = CGSize(width: 32, height: 16)
        let outputBytes = 32 * 16 * 4
        let owner = RasterResidency(budgetBytes: outputBytes * 6, hasHeadroom: { bytes in
            if bytes == outputBytes { outputs += 1; return outputs < 3 }
            return true
        })
        let manager = CanvasFixture.manager()
        let size = CGSize(width: width, height: height)
        manager.canvasSize = size
        var cels: [Cel] = []
        for (index, color) in [UIColor.red, .green, .blue].enumerated() {
            let url = root.appendingPathComponent("source-\(index).png")
            try XCTUnwrap(CanvasFixture.solidImage(color, rect: CGRect(origin: .zero, size: size), size: size).pngData()).write(to: url)
            let source = RasterSource.backed(by: try ProjectStore.RasterBacking.protect(url, using: owner).get(), using: owner)
            let vector = VectorCanvas(size: size, elements: [.stroke(VectorStroke(brush: manager.toolProfiles.brush.preset,
                color: CodableColor(color), size: 1, opacity: 1,
                samples: [VectorSample(x: 1, y: 1), VectorSample(x: 5, y: 2)]))])
            cels.append(Cel(id: UUID(), startFrame: index, frameCount: 1,
                raster: RasterLayerTexture(size: size, source: source, strokeCount: index + 2), vector: vector))
        }
        manager.layers[0].cels = cels
        manager.recordUndo(label: .brushStroke, undo: {}, redo: {})
        let identities = cels.map(CelContentIdentity.init)
        let ledgerBefore = manager.packageLedger.landedAt
        let plan = CanvasResizePlan(map: CanvasResizeMap(from: size, to: destination, mode: .cropExpand),
                                    audit: CanvasResizeAudit(blankCels: 0, inkedCels: 3), padding: 0)
        XCTAssertFalse(manager.commitResize(plan))
        XCTAssertEqual(outputs, 3, "The failure must occur after earlier output versions have been prepared")
        XCTAssertEqual(manager.canvasSize, size)
        XCTAssertEqual(manager.layers[0].cels.map(CelContentIdentity.init), identities)
        XCTAssertEqual(manager.layers[0].cels.map { $0.raster.size }, [size, size, size])
        XCTAssertEqual(manager.layers[0].cels.map { $0.raster.strokeCount }, [2, 3, 4])
        XCTAssertEqual(manager.layers[0].cels.map { $0.vector?.size }, [size, size, size])
        XCTAssertEqual(manager.history.undoStack.count, 1)
        XCTAssertEqual(manager.history.redoStack.count, 0)
        XCTAssertEqual(manager.packageLedger.landedAt, ledgerBefore)
        XCTAssertEqual(manager.notice?.kind, .drawingSourceUnavailable)
        for (index, expected) in [[UInt8(255), 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]].enumerated() {
            try autoreleasepool { XCTAssertEqual(try pixel(XCTUnwrap(manager.layers[0].cels[index].raster.renderToUIImage().get().cgImage)), expected) }
        }
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    @MainActor
    func testAThousandPreparedVersionsUseABoundedDecodedWindow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-thousand-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = RasterResidency(budgetBytes: pictureBytes * 40, hasHeadroom: { _ in true })
        let size = CGSize(width: width, height: height)
        let png = root.appendingPathComponent("source.png")
        try XCTUnwrap(CanvasFixture.solidImage(.red, rect: CGRect(origin: .zero, size: size), size: size).pngData()).write(to: png)
        let source = RasterSource.backed(by: try ProjectStore.RasterBacking.protect(png, using: owner).get(), using: owner)
        let manager = CanvasFixture.manager()
        manager.canvasSize = size
        manager.layers[0].cels = (0..<1000).map {
            Cel(id: UUID(), startFrame: $0, frameCount: 1, raster: RasterLayerTexture(size: size, source: source, strokeCount: 1))
        }
        let input = CanvasPixelTransformInput(manager)
        XCTAssertEqual(owner.usage.allocations, 0)
        let newSize = CGSize(width: 16, height: 8)
        let prepared = try input.prepare(.resize(size: newSize, content: CGRect(origin: .zero, size: newSize))).get()
        XCTAssertEqual(prepared.cels.count, 1000)
        XCTAssertTrue(prepared.cels.allSatisfy { $0.raster != nil && $0.raster?.size == newSize })
        XCTAssertTrue(input.stillMatches(manager), "Preparation must leave all live identities and dimensions unchanged")
        XCTAssertGreaterThanOrEqual(owner.usage.allocations, 1001, "Every output must actually be drawn before checkpointing")
        XCTAssertLessThanOrEqual(owner.usage.pixelBufferCount, 8)
        for at in [0, 499, 999] {
            let rendered = try XCTUnwrap(prepared.cels[at].raster)
            try autoreleasepool { XCTAssertEqual(try pixel(XCTUnwrap(rendered.resolveImage().get().cgImage)), [255, 0, 0, 255]) }
        }
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    @MainActor
    func testThreeHundredCelLoadAndSaveFreezeKeepSourcesColdAndReuseExactPNGsAcrossReplacementAndRename() async throws {
        try await assertColdPackageRoundTrip(celCount: 300)
    }

    @MainActor
    func testAThousandCelLoadAndSaveFreezeKeepSourcesColdAndReuseExactPNGsAcrossReplacementAndRename() async throws {
        try await assertColdPackageRoundTrip(celCount: 1000)
    }

    @MainActor
    private func save(_ manager: CanvasManager, to url: URL, freezing owner: RasterResidency) async throws {
        // Hold the existing writer so the synchronous save freeze can be observed independently
        // of its later thumbnail/render/checkpoint consumers. The hold is always released.
        let entered = expectation(description: "existing save serializer entered")
        let release = DispatchSemaphore(value: 0)
        ProjectStore.enqueueRasterCheckpoint { entered.fulfill(); release.wait() }
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 30)
        let finished = expectation(description: "normal save completed")
        let allocations = owner.usage.allocations
        var failed = false
        let decision = ProjectStore.save(manager, to: url, onSaveFailed: { failed = true },
                                         completion: { finished.fulfill() })
        XCTAssertEqual(decision, .write)
        XCTAssertEqual(owner.usage.allocations, allocations,
                       "Freezing every saved tier and the thumbnail recipe must not resolve their pixels")
        release.signal()
        await fulfillment(of: [finished], timeout: 30)
        XCTAssertFalse(failed)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: manager.projectURL ?? url))
    }

    @MainActor
    private func assertColdPackageRoundTrip(celCount: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-package-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previousRoot = ProjectBackupManager.rootDirectoryOverride
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = previousRoot
            try? FileManager.default.removeItem(at: root)
        }
        let size = CGSize(width: width, height: height)
        let original = root.appendingPathComponent("input.png")
        let png = try XCTUnwrap(CanvasFixture.solidImage(.red,
            rect: CGRect(origin: .zero, size: size), size: size).pngData())
        try png.write(to: original)
        let authoredOwner = RasterResidency(budgetBytes: pictureBytes * 24, hasHeadroom: { _ in true })
        let protected = try ProjectStore.RasterBacking.protect(original, using: authoredOwner).get()
        let source = RasterSource.backed(by: protected, using: authoredOwner)
        let authored = CanvasFixture.manager()
        authored.projectName = "Cold \(celCount)"
        authored.canvasSize = size
        authored.layers[0].cels = (0..<celCount).map {
            Cel(id: UUID(), startFrame: $0, frameCount: 1,
                raster: RasterLayerTexture(size: size, source: source, strokeCount: 2), bakedImage: source)
        }
        let url = ProjectStore.createNewProjectURL(name: authored.projectName)
        authored.projectURL = url
        XCTAssertEqual(authoredOwner.usage.allocations, 0)
        try await save(authored, to: url, freezing: authoredOwner)
        XCTAssertEqual(ProjectStore.lastSaveProfile?.pngsEncoded, 0)
        XCTAssertEqual(ProjectStore.lastSaveProfile?.pngsReused, celCount * 2)
        try FileManager.default.removeItem(at: original)

        let owner = RasterResidency(budgetBytes: pictureBytes * 24, hasHeadroom: { _ in true })
        let loaded = await ProjectStore.loadInBackground(from: url, residency: owner)
        let opened = try XCTUnwrap(loaded)
        defer { opened.closeFrameBaker(); authored.closeFrameBaker() }
        let profile = try XCTUnwrap(ProjectStore.lastLoadProfile)
        XCTAssertEqual(profile.celCount, celCount)
        XCTAssertEqual(profile.ownedRasterPicturesAfterSourceLoad, 0)
        XCTAssertEqual(profile.ownedRasterBytesAfterSourceLoad, 0)
        opened.thumbnailBackfillTask?.cancel()
        await opened.thumbnailBackfillTask?.value
        XCTAssertEqual(opened.layers[0].cels.count, celCount)
        XCTAssertTrue(opened.layers[0].cels.allSatisfy { $0.raster.hasContent && $0.bakedImage != nil })
        let identities = opened.layers[0].cels.map(CelContentIdentity.init)
        let recipeAllocations = owner.usage.allocations
        let frozen = opened.makeFrameRecipe(atFrame: celCount / 2, includeBackground: false)
        XCTAssertNotNil(frozen)
        XCTAssertEqual(owner.usage.allocations, recipeAllocations)

        try await save(opened, to: url, freezing: owner)
        XCTAssertEqual(ProjectStore.lastSaveProfile?.pngsEncoded, 0,
                       "A reopened document's first save must clone immutable PNGs without reencoding")
        XCTAssertEqual(ProjectStore.lastSaveProfile?.pngsReused, celCount * 2)
        opened.projectName = "Renamed \(celCount)"
        try await save(opened, to: url, freezing: owner)
        let renamed = try XCTUnwrap(opened.projectURL)
        XCTAssertNotEqual(renamed, url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(ProjectStore.lastSaveProfile?.pngsEncoded, 0)
        XCTAssertEqual(ProjectStore.lastSaveProfile?.pngsReused, celCount * 2)
        XCTAssertEqual(opened.layers[0].cels.map(CelContentIdentity.init), identities)
        for at in [0, celCount / 2, celCount - 1] {
            let cel = opened.layers[0].cels[at]
            for (suffix, role) in [("raster", ProjectPackageLayout.Role.raster), ("baked", .baked)] {
                let name = "\(cel.id.uuidString)_\(suffix).png"
                let file = ProjectPackageLayout.resolve(ProjectPackageLayout.writePath(named: name, role: role), in: renamed)
                XCTAssertEqual(try Data(contentsOf: file), png, "Unchanged resources must retain their exact compressed bytes")
            }
            try autoreleasepool {
                XCTAssertEqual(try pixel(XCTUnwrap(cel.raster.renderToUIImage().get().cgImage)), [255, 0, 0, 255])
                XCTAssertEqual(try pixel(XCTUnwrap(cel.bakedImage?.resolveImage().get().cgImage)), [255, 0, 0, 255])
            }
        }
        XCTAssertLessThanOrEqual(owner.usage.pixelBufferCount, 24,
                                 "The native provider count must remain a window, independent of cel count")
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
        withExtendedLifetime(frozen) {}
    }

    @MainActor
    func testDirtyCheckpointFailurePreservesTheSavedPackageAndTheUnsavedLiveVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-save-refusal-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previousRoot = ProjectBackupManager.rootDirectoryOverride
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = previousRoot
            try? FileManager.default.removeItem(at: root)
        }
        let size = CGSize(width: width, height: height)
        let owner = RasterResidency(budgetBytes: pictureBytes * 12, hasHeadroom: { _ in true })
        let manager = CanvasFixture.manager()
        manager.projectName = "Checkpoint refusal"
        manager.canvasSize = size
        let blue = RasterSource.snapshot(of: try surface(owner, color: .blue), size: size)
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, source: blue, strokeCount: 3)
        let url = ProjectStore.createNewProjectURL(name: manager.projectName)
        manager.projectURL = url
        defer { manager.closeFrameBaker() }
        try await save(manager, to: url, freezing: owner)
        let manifest = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let celID = manager.layers[0].cels[0].id
        let savedRaster = ProjectPackageLayout.resolve(ProjectPackageLayout.writePath(
            named: "\(celID.uuidString)_raster.png", role: .raster), in: url)
        let savedPixels = try Data(contentsOf: savedRaster)
        let blocker = root.appendingPathComponent("not-a-source-directory")
        try Data([1, 2, 3]).write(to: blocker)
        let refusedOwner = RasterResidency(budgetBytes: pictureBytes * 12,
            storage: ProjectStore.RasterStorage(url: blocker), hasHeadroom: { _ in true })
        let red = RasterSource.snapshot(of: try surface(refusedOwner), size: size)
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, source: red, strokeCount: 4)
        let identity = CelContentIdentity(manager.layers[0].cels[0])
        let ledger = manager.packageLedger.landedAt
        let completed = expectation(description: "failed normal save completed")
        var failed = false
        XCTAssertEqual(ProjectStore.save(manager, to: url, onSaveFailed: { failed = true },
                                         completion: { completed.fulfill() }), .write)
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertTrue(failed)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), manifest)
        XCTAssertEqual(try Data(contentsOf: savedRaster), savedPixels)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), identity)
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 4)
        XCTAssertEqual(manager.packageLedger.landedAt, ledger)
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), [255, 0, 0, 255])
        }
        XCTAssertLessThanOrEqual(refusedOwner.usage.admittedBytes, refusedOwner.budgetBytes)
    }

    @MainActor
    func testALaterTextRefusalKeepsCoexistingFillShapeAndQueuedTextThenOneSettlementPreservesTheirDrawnOrder() throws {
        let size = CGSize(width: 64, height: 32)
        let bytes = 64 * 32 * 4
        var counting = false
        var outputs = 0
        var refuseThird = true
        let owner = RasterResidency(budgetBytes: bytes * 12, hasHeadroom: { requested in
            if counting, requested == bytes {
                outputs += 1
                if refuseThird, outputs == 3 { return false }
            }
            return true
        })
        let red = try RasterSource.render(size: size, using: owner) { context in
            context.setFillColor(UIColor.red.cgColor); context.fill(CGRect(origin: .zero, size: size)); return true
        }.get()
        let manager = CanvasFixture.manager()
        manager.canvasSize = size
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, source: red, strokeCount: 2)
        let layerID = manager.layers[0].id
        let celID = manager.layers[0].cels[0].id
        manager.fillGestureActive = true
        manager.fillFingerDown = false
        manager.fillGestureLayerID = layerID
        manager.fillGestureCelID = celID
        manager.fillGestureFillColor = CodableColor(.green)
        let fill = CanvasManager.FillRenderResult(generation: manager.fillGeneration,
            bytes: Array(repeating: [UInt8(0), 255, 0, 255], count: 64 * 32).flatMap { $0 },
            window: FillWindow.fitting(CGRect(origin: .zero, size: size), in: size, pixelBudget: 64 * 32))
        manager.fillRenderedRegion = fill
        manager.shapeGestureActive = true
        manager.shapeFingerDown = false
        manager.shapeGestureLayerID = layerID
        manager.shapeGestureCelID = celID
        manager.shapeGeometry = ShapeGeometry(kind: .line,
            startPoint: CGPoint(x: 4, y: 10), endPoint: CGPoint(x: 18, y: 10))
        manager.shapeGestureBrush = TestBrushes.hardRound
        manager.shapeGestureStrokeWidth = 4
        manager.shapeGestureColor = CodableColor(.blue)
        manager.shapeGestureSamples = StrokeSamples([VectorSample(x: 4, y: 10), VectorSample(x: 18, y: 10)])
        manager.textGestureActive = true
        manager.textFingerDown = false
        manager.textIsFocused = true
        manager.textGestureLayerID = layerID
        manager.textGestureCelID = celID
        manager.textRecipe = TextRecipe(string: "A", typography: Typography(pointSize: 12))
        manager.textFrame = TextFrame(origin: CGPoint(x: 30, y: 5), size: CGSize(width: 20, height: 22), autoSize: false)
        var reads = 0
        var resigns = 0
        manager.textDraftReader = { reads += 1; return "Z" }
        manager.textFocusResigner = { [weak manager] in
            resigns += 1
            manager?.updateTextString("Z") // UIKit's synchronous final delivery, after admission.
            manager?.textIsFocused = false
        }
        manager.recordUndo(label: .brushStroke, undo: {}, redo: {})
        let before = CelContentIdentity(manager.layers[0].cels[0])
        let generation = manager.fillGeneration
        counting = true
        autoreleasepool { XCTAssertNil(manager.prepareCanvasEdit()) }
        XCTAssertEqual(outputs, 3, "Refuse the final tool after fill and shape have prepared their private outputs")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(resigns, 0)
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), before)
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 2)
        XCTAssertTrue(manager.fillGestureActive && manager.shapeGestureActive && manager.textGestureActive)
        XCTAssertTrue(manager.textIsFocused)
        XCTAssertEqual(manager.textRecipe.string, "A", "Preparation must not flush or replace the draft")
        XCTAssertTrue(manager.fillRenderedRegion === fill)
        XCTAssertEqual(manager.fillGeneration, generation)
        XCTAssertEqual(manager.history.undoStack.count, 1)
        XCTAssertTrue(manager.history.redoStack.isEmpty)
        XCTAssertEqual(manager.notice?.kind, .drawingSourceUnavailable)
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), [255, 0, 0, 255])
        }

        refuseThird = false
        outputs = 0
        let prepared = try XCTUnwrap(manager.prepareCanvasEdit())
        XCTAssertEqual(prepared.cels.count, 1, "Only the affected cel may be staged")
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), before)
        XCTAssertEqual(resigns, 0)
        XCTAssertTrue(prepared.commit())
        XCTAssertFalse(manager.fillGestureActive || manager.shapeGestureActive || manager.textGestureActive)
        XCTAssertFalse(manager.textIsFocused)
        XCTAssertEqual(resigns, 1)
        XCTAssertEqual(manager.textRecipe.string, "Z")
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 3)
        XCTAssertEqual(manager.history.undoStack.map(\.label), [.brushStroke, .fill, .shape, .addText])
        let drawn = try manager.layers[0].cels[0].raster.renderToUIImage().get()
        let rgba = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(XCTUnwrap(drawn.cgImage), width: 64, height: 32))
        let colors = stride(from: 0, to: rgba.count, by: 4).map { Array(rgba[$0..<($0 + 4)]) }
        XCTAssertTrue(colors.contains([0, 255, 0, 255]), "Fill must remain underneath the later tools")
        XCTAssertTrue(colors.contains([0, 0, 255, 255]), "Shape must survive the text's flatten")
        XCTAssertFalse(colors.contains([255, 0, 0, 255]), "Text must prepare against the staged fill/shape, not the old red cel")
        let glyphs = try XCTUnwrap(TextLayout.render(recipe: manager.textRecipe, frame: manager.textFrame, canvasSize: size))
        let expected = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            UIColor.green.setFill(); context.fill(CGRect(origin: .zero, size: size)); glyphs.draw(at: .zero)
        }
        let expectedBytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(XCTUnwrap(expected.cgImage), width: 64, height: 32))
        for row in 0..<32 {
            let range = ((row * 64 + 24) * 4)..<((row + 1) * 64 * 4)
            XCTAssertEqual(Array(rgba[range]), Array(expectedBytes[range]), "The queued final Z must be the glyph actually drawn")
        }
        XCTAssertEqual(manager.history.undo(), .addText)
        XCTAssertEqual(manager.history.undo(), .shape)
        XCTAssertEqual(manager.history.undo(), .fill)
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), [255, 0, 0, 255])
        }
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    @MainActor
    func testStableOwnerKeysReuseOneOwnerButKeepReleasedAndNewEqualVersionVectorPicturesDistinct() throws {
        let size = CGSize(width: width, height: height)
        let manager = CanvasFixture.manager()
        manager.canvasSize = size
        manager.addVectorLayer()
        let index = manager.layers.count - 1
        manager.layers[index].cels[0].raster = RasterLayerTexture(size: size)
        weak var oldOwner: VectorCanvas?
        let first: (version: LayerContentVersion, frozen: PixelOps.FrozenCel.Identity, bake: FrameBakeKey) = try autoreleasepool {
            let vector = VectorCanvas(size: size, elements: [.fill(VectorFillElement(
                path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), color: CodableColor(.red)))])
            oldOwner = vector
            manager.layers[index].cels[0].vector = vector
            let cel = manager.layers[index].cels[0]
            let frozen = PixelOps.FrozenCel.Identity(cel: cel, derived: nil)
            XCTAssertEqual(frozen.vector, vector.residencyID)
            XCTAssertEqual(frozen, PixelOps.FrozenCel(cel: cel, derived: nil, quality: .full).identity)
            let version = LayerContentVersion(cel: cel)
            let same = LayerContentVersion(cel: cel)
            XCTAssertEqual(version, same)
            XCTAssertEqual(version.vector, vector.residencyID)
            XCTAssertEqual(version.raster, cel.raster.residencyID)
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false))
            let bake = FrameBakeKey(recipe: recipe, renderResolution: .full, backend: .coreGraphics)
            XCTAssertEqual(bake, FrameBakeKey(recipe: recipe, renderResolution: .full, backend: .coreGraphics))
            let image = try XCTUnwrap(PixelOps.rasterize(cel: cel, canvasSize: size))
            XCTAssertEqual(try pixel(XCTUnwrap(image.cgImage)), [255, 0, 0, 255])
            return (version, frozen, bake)
        }
        manager.layers[index].cels[0].vector = nil
        XCTAssertNil(oldOwner, "Keeping keys and cached pixels must not retain the released owner's geometry")
        let blue = VectorCanvas(size: size, elements: [.fill(VectorFillElement(
            path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), color: CodableColor(.blue)))])
        manager.layers[index].cels[0].vector = blue
        let cel = manager.layers[index].cels[0]
        let version = LayerContentVersion(cel: cel)
        XCTAssertEqual(version.vectorVersion, first.version.vectorVersion)
        XCTAssertNotEqual(version.vector, first.version.vector)
        XCTAssertNotEqual(version, first.version)
        XCTAssertNotEqual(PixelOps.FrozenCel.Identity(cel: cel, derived: nil), first.frozen)
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false))
        XCTAssertNotEqual(FrameBakeKey(recipe: recipe, renderResolution: .full, backend: .coreGraphics), first.bake)
        let image = try XCTUnwrap(PixelOps.rasterize(cel: cel, canvasSize: size))
        XCTAssertEqual(try pixel(XCTUnwrap(image.cgImage)), [0, 0, 255, 255])
    }

    @MainActor
    func testAStagedReferencedOwnerAtTheSameVersionChangesActualDerivedRecipePixelsWithoutTouchingTheDocument() throws {
        let size = CGSize(width: 64, height: 64)
        let manager = CanvasFixture.manager()
        manager.canvasSize = size
        manager.addVectorLayer()
        let layer = manager.layers.count - 1
        let layerID = manager.layers[layer].id
        let cels = (0..<3).map { offset in
            Cel(id: UUID(), startFrame: offset * 4, frameCount: 4,
                raster: RasterLayerTexture(size: size), vector: VectorCanvas.empty(size: size))
        }
        manager.layers[layer].cels = cels
        let stroke = VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(.red), size: 6, opacity: 1,
                                  samples: [VectorSample(x: 10, y: 20), VectorSample(x: 30, y: 20), VectorSample(x: 30, y: 40)])
        cels[0].vector?.addStroke(stroke)
        cels[2].vector?.addStroke(stroke)
        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] { manager.toggleInterpolationReference(celID: cel.id, inLayer: layerID) }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: layer, celIndex: 1))
        manager.layers[layer].cels[1].interpolation?.t = 0
        manager.exitInterpolateMode()
        let beforeIdentity = manager.layers[layer].cels.map(CelContentIdentity.init)
        let generated = manager.layers[layer].cels[1]
        let original = try XCTUnwrap(manager.celContentProvider(atFrame: 4).content(for: generated))
        let oldRecipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 4, includeBackground: false))
        let previousBackend = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previousBackend }
        let before = try XCTUnwrap(oldRecipe.composite(budgetBytes: 1024 * 1024))
        var blueStroke = stroke
        blueStroke.color = CodableColor(.blue)
        let replacement = VectorCanvas.empty(size: size)
        replacement.addStroke(blueStroke)
        XCTAssertEqual(replacement.version, cels[0].vector?.version,
                       "Owner identity, not a bumped counter, must distinguish this staged replacement")
        var staged = manager.layers[layer].cels[0]
        staged.vector = replacement
        let overrides = [staged.id: staged]
        let derived = try XCTUnwrap(manager.celContentProvider(atFrame: 4, preparing: overrides).content(for: generated))
        XCTAssertNotEqual(derived.identity, original.identity)
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 4, includeBackground: false, preparing: overrides))
        let after = try XCTUnwrap(recipe.composite(budgetBytes: 1024 * 1024))
        let red = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(before, width: 64, height: 64))
        let blue = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(after, width: 64, height: 64))
        XCTAssertNotEqual(red, blue)
        XCTAssertGreaterThan(stride(from: 0, to: red.count, by: 4).reduce(0) { $0 + Int(red[$1]) }, 0)
        XCTAssertEqual(stride(from: 0, to: red.count, by: 4).reduce(0) { $0 + Int(red[$1 + 2]) }, 0)
        XCTAssertGreaterThan(stride(from: 0, to: blue.count, by: 4).reduce(0) { $0 + Int(blue[$1 + 2]) }, 0)
        XCTAssertEqual(stride(from: 0, to: blue.count, by: 4).reduce(0) { $0 + Int(blue[$1]) }, 0)
        XCTAssertEqual(manager.layers[layer].cels.map(CelContentIdentity.init), beforeIdentity)
    }

    @MainActor
    func testRefusedLiquifyFinalSourceKeepsItsFinishAndPictureUntilOneSuccessfulRetry() throws {
        let size = CGSize(width: 64, height: 64)
        let bytes = 64 * 64 * 4
        var refusing = false
        let owner = RasterResidency(budgetBytes: bytes * 32, hasHeadroom: { _ in !refusing })
        let source = try RasterSource.render(size: size, using: owner) { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 20, y: 18, width: 9, height: 12))
            return true
        }.get()
        let manager = CanvasFixture.manager()
        manager.canvasSize = size
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, source: source, strokeCount: 1)
        manager.history.removeAll()
        let original = CelContentIdentity(manager.layers[0].cels[0])
        let before = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
            XCTUnwrap(source.resolveImage().get().cgImage), width: 64, height: 64))
        let profile = ToolProfile(preset: TestBrushes.hardRound, size: 40, opacity: 1)
        var session = try XCTUnwrap(manager.beginLiquify(layerID: manager.layers[0].id,
            profile: profile, size: 40, seed: 7))
        session.samples = StrokeSamples([VectorSample(x: 24, y: 24), VectorSample(x: 38, y: 24)], channels: .pressureOnly)
        session.window = CGRect(x: 0, y: 0, width: 60, height: 48)
        manager.holdLiquify(&session)
        let procedure = try XCTUnwrap(manager.liveCelContentEdit?.procedure)
        _ = procedure.resolve(session.elementsBefore)
        XCTAssertFalse(procedure.hasFailed)
        refusing = true
        manager.commitLiquify(session)
        XCTAssertTrue(procedure.isPending)
        let refusedBytes = owner.usage.chargedBytes
        for _ in 0..<3 {
            XCTAssertFalse(manager.beginCanvasEdit())
            XCTAssertTrue(procedure.isPending)
            XCTAssertTrue(manager.liveCelContentEdit?.procedure === procedure)
            XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), original)
            XCTAssertTrue(manager.history.undoStack.isEmpty && manager.history.redoStack.isEmpty)
            XCTAssertEqual(owner.usage.chargedBytes, refusedBytes)
        }
        XCTAssertEqual(procedure.resolutionCount, 1, "Refusal must retain the same completed picture")
        XCTAssertEqual(manager.notice?.kind, .drawingSourceUnavailable)
        refusing = false
        let prepared = try XCTUnwrap(manager.prepareCanvasEdit())
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), original)
        XCTAssertTrue(procedure.isPending)
        XCTAssertTrue(prepared.commit())
        XCTAssertFalse(procedure.isPending)
        XCTAssertNil(manager.liveCelContentEdit)
        XCTAssertEqual(manager.history.undoStack.map(\.label), [.liquify])
        let after = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
            XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage), width: 64, height: 64))
        XCTAssertNotEqual(after, before, "The successful retry must land the actual moved red picture")
        procedure.didPresent()
        procedure.didPresent()
        XCTAssertEqual(manager.history.undoStack.count, 1)
        XCTAssertEqual(manager.history.undo(), .liquify)
        XCTAssertEqual(try CoreGraphicsCompositor.premultipliedBytes(
            XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage), width: 64, height: 64), before)
        XCTAssertEqual(manager.history.redo(), .liquify)
        XCTAssertEqual(try CoreGraphicsCompositor.premultipliedBytes(
            XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage), width: 64, height: 64), after)
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    func testUnchangedLiquifyFinishesOnceAndCancelledPreparedGenerationCannotLand() throws {
        let deformation = LiquifyDeformation(brush: TestBrushes.hardRound, size: 16, power: 0,
            mode: .push, seed: 1, samples: StrokeSamples(channels: .captured))
        let procedure = LiquifyProcedure(deformation: deformation, selectedIDs: nil, poses: [:])
        var finishes = 0
        procedure.finishWhenPresented { resolved, _ in
            XCTAssertTrue(resolved.changed.isEmpty)
            XCTAssertTrue(resolved.fieldIsEmpty)
            return { finishes += 1 }
        }
        XCTAssertTrue(procedure.settlePending([]))
        XCTAssertFalse(procedure.isPending, "An unchanged gesture still releases its finish owner")
        XCTAssertEqual(finishes, 1)
        procedure.didPresent()
        XCTAssertEqual(finishes, 1)
        let cancelled = LiquifyProcedure(deformation: deformation, selectedIDs: nil, poses: [:])
        cancelled.finishWhenPresented { _, _ in { finishes += 10 } }
        var staged: [UUID: Cel] = [:]
        let prepared = try XCTUnwrap(cancelled.preparePending([], staging: &staged))
        XCTAssertTrue(prepared.isCurrent())
        cancelled.cancel()
        XCTAssertFalse(prepared.isCurrent())
        prepared.commit()
        cancelled.didPresent()
        XCTAssertEqual(finishes, 1, "A prepared finish cannot land after cancellation changes its generation")
        XCTAssertFalse(cancelled.isPending)
    }

}
