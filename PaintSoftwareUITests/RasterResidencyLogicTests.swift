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
        var old: CGImage? = try current.image().get().cgImage
        XCTAssertEqual(current.readProviderCount, 1)
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
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
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
        try autoreleasepool { source = try RasterSource.snapshot(of: surface(owner), size: CGSize(width: width, height: height)).get() }
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
        try autoreleasepool { source = try RasterSource.snapshot(of: surface(owner), size: CGSize(width: width, height: height)).get() }
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
}
