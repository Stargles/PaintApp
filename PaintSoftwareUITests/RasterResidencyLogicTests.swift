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
        let owner = RasterResidency(budgetBytes: pictureBytes, hasHeadroom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes, hasHeadroom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 2, hasHeadroom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes, hasHeadroom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes, hasHeadroom: { _ in true })
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
}
