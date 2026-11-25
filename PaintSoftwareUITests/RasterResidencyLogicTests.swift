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

    func testTransientSourcesRetireTheirEvictionRegistrationsWithoutWaitingForPressure() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
        weak var retired: RasterSource?
        for _ in 0..<256 {
            try autoreleasepool {
                let surface = try surface(owner)
                let source = RasterSource.snapshot(of: surface, size: CGSize(width: width, height: height))
                retired = source
                XCTAssertEqual(owner.usage.registeredCandidateCount, 1)
                XCTAssertEqual(try pixel(XCTUnwrap(source.resolveImage().get().cgImage)), [255, 0, 0, 255])
            }
            XCTAssertNil(retired)
            XCTAssertEqual(owner.usage.registeredCandidateCount, 0,
                           "Dead source registrations must leave without an admission failure")
            XCTAssertEqual(owner.usage.chargedBytes, 0)
            XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        }
        XCTAssertEqual(owner.usage.allocations, 256)
        XCTAssertEqual(owner.usage.evictions, 0, "Retirement must not depend on a pressure pass")
    }

    func testTransientTexturesRetireTheirEvictionRegistrationsWithoutWaitingForPressure() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
        weak var retired: RasterLayerTexture?
        for _ in 0..<256 {
            try autoreleasepool {
                let texture = try RasterLayerTexture.rendered(size: CGSize(width: width, height: height), using: owner) { context in
                    context.setFillColor(UIColor.blue.cgColor)
                    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }.get()
                retired = texture
                XCTAssertTrue(texture.hasContent)
                XCTAssertEqual(owner.usage.registeredCandidateCount, 1)
                XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
            }
            XCTAssertNil(retired)
            XCTAssertEqual(owner.usage.registeredCandidateCount, 0,
                           "Dead texture registrations must leave without an admission failure")
            XCTAssertEqual(owner.usage.chargedBytes, 0)
            XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        }
        XCTAssertEqual(owner.usage.allocations, 256)
        XCTAssertEqual(owner.usage.evictions, 0, "Retirement must not depend on a pressure pass")
    }

    func testRetiringASourceRegistrationKeepsAnEscapedProviderCharged() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
        weak var retired: RasterSource?
        var escaped: CGImage?
        try autoreleasepool {
            let surface = try surface(owner)
            let source = RasterSource.snapshot(of: surface, size: CGSize(width: width, height: height))
            retired = source
            escaped = try XCTUnwrap(source.resolveImage().get().cgImage)
            XCTAssertEqual(owner.usage.registeredCandidateCount, 1)
        }
        XCTAssertNil(retired)
        XCTAssertEqual(owner.usage.registeredCandidateCount, 0,
                       "The source registration ends before its escaped pixel provider")
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
        XCTAssertEqual(try pixel(XCTUnwrap(escaped)), [255, 0, 0, 255])
        escaped = nil
        XCTAssertEqual(owner.usage.chargedBytes, 0)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
    }

    func testALiveColdSourceKeepsItsRegistrationForTheNextEviction() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
        var live: RasterSource?
        try autoreleasepool {
            let surface = try surface(owner)
            let source = RasterSource.snapshot(of: surface, size: CGSize(width: width, height: height))
            _ = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            XCTAssertTrue(source.releaseResidentPixels())
            live = source
        }
        XCTAssertEqual(owner.usage.chargedBytes, 0)
        XCTAssertEqual(owner.usage.registeredCandidateCount, 1, "A live cold version stays eligible")
        guard owner.usage.registeredCandidateCount == 1 else { return }
        for expectedEvictions in 1...2 {
            try autoreleasepool {
                XCTAssertEqual(try pixel(XCTUnwrap(live?.resolveImage().get().cgImage)), [255, 0, 0, 255])
            }
            XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
            let held = try owner.admitWorking(owner.budgetBytes).get()
            XCTAssertEqual(owner.usage.pixelBytes, 0, "The rehydrated live version must still be evictable")
            XCTAssertEqual(owner.usage.registeredCandidateCount, 1)
            XCTAssertEqual(owner.usage.evictions, expectedEvictions)
            withExtendedLifetime(held) {}
        }
        live = nil
        XCTAssertEqual(owner.usage.registeredCandidateCount, 0)
        XCTAssertEqual(owner.usage.chargedBytes, 0)
    }

    func testExtractedCGImageKeepsItsPixelsChargedAfterSurfaceAndUIImageAreReleased() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
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
        var onRelease: (() -> Bool)?
        init(image: UIImage? = nil, onRelease: (() -> Bool)? = nil) {
            self.image = image
            self.onRelease = onRelease
        }
        func releaseResidentPixels() -> Bool {
            if let onRelease { return onRelease() }
            image = nil
            return true
        }
    }

    func testAdmissionEvictsTheLeastRecentPictureAndKeepsColdRegistrationsEligible() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, makeRoom: { _ in true })
        let first = CachedPicture()
        let second = CachedPicture()
        try autoreleasepool {
            let red = try surface(owner)
            red.allocation.markDurable()
            first.image = try red.image().get()
            let blue = try surface(owner, color: .blue)
            blue.allocation.markDurable()
            second.image = try blue.image().get()
        }
        owner.register(first)
        owner.register(second)
        owner.touch(first.residencyID)
        var working: RasterResidency.Allocation? = try owner.admitWorking(pictureBytes * 3).get()
        XCTAssertNil(second.image, "A read makes the first picture more recent than the second")
        XCTAssertEqual(try pixel(XCTUnwrap(first.image?.cgImage)), [255, 0, 0, 255])
        XCTAssertEqual(owner.usage.pixelBytes, pictureBytes)
        XCTAssertEqual(owner.usage.workingBytes, pictureBytes * 3)
        withExtendedLifetime(working) {}
        working = nil
        try autoreleasepool {
            let blue = try surface(owner, color: .blue)
            blue.allocation.markDurable()
            second.image = try blue.image().get()
        }
        // Rehydration touches an existing registration; eviction must not have removed it.
        owner.touch(second.residencyID)
        working = try owner.admitWorking(pictureBytes * 3, excluding: [first.residencyID]).get()
        XCTAssertNil(second.image, "A cold registration must remain eligible after its pixels return")
        XCTAssertEqual(try pixel(XCTUnwrap(first.image?.cgImage)), [255, 0, 0, 255])
        XCTAssertEqual(owner.usage.evictions, 2)
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
        withExtendedLifetime(working) {}
    }

    func testAdmissionDefersACallbackRegistrationUntilTheNextRequest() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
        var held: RasterResidency.Allocation? = try owner.admitWorking(owner.budgetBytes).get()
        var visits: [String] = []
        let later = CachedPicture(onRelease: { visits.append("later"); held = nil; return true })
        var registered = false
        let first = CachedPicture(onRelease: {
            visits.append("first")
            if !registered { registered = true; owner.register(later) }
            return false
        })
        owner.register(first)
        XCTAssertThrowsError(try owner.admitWorking(pictureBytes).get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
        }
        XCTAssertEqual(visits, ["first"], "A callback cannot extend the captured population")
        XCTAssertNotNil(held)
        XCTAssertEqual(owner.usage.workingBytes, owner.budgetBytes)
        let admitted = try owner.admitWorking(pictureBytes).get()
        XCTAssertEqual(visits, ["first", "first", "later"])
        XCTAssertNil(held)
        XCTAssertEqual(owner.usage.workingBytes, pictureBytes)
        withExtendedLifetime(admitted) {}
    }

    func testAdmissionSkipsCandidatesTouchedOrReregisteredDuringItsPass() throws {
        for reregister in [false, true] {
            let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
            var held: RasterResidency.Allocation? = try owner.admitWorking(owner.budgetBytes).get()
            var visits: [String] = []
            let recent = CachedPicture(onRelease: { visits.append("recent"); held = nil; return true })
            var refreshed = false
            let first = CachedPicture(onRelease: {
                visits.append("first")
                if !refreshed {
                    refreshed = true
                    if reregister { owner.register(recent) } else { owner.touch(recent.residencyID) }
                }
                return false
            })
            owner.register(first)
            owner.register(recent)
            XCTAssertThrowsError(try owner.admitWorking(pictureBytes).get()) { error in
                XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
            }
            XCTAssertEqual(visits, ["first"], "A refreshed candidate belongs to the next pass")
            XCTAssertNotNil(held)
            let admitted = try owner.admitWorking(pictureBytes).get()
            XCTAssertEqual(visits, ["first", "first", "recent"])
            XCTAssertNil(held)
            XCTAssertEqual(owner.usage.workingBytes, pictureBytes)
            withExtendedLifetime(admitted) {}
        }
    }

    func testRefusedMutationPreservesPixelsAndDefersNewRegistrationsUntilRetry() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
        let current = try surface(owner)
        current.allocation.markDurable()
        var held: RasterResidency.Allocation? = try owner.admitWorking(pictureBytes).get()
        var visits: [String] = []
        let later = CachedPicture(onRelease: { visits.append("later"); held = nil; return true })
        var registered = false
        let first = CachedPicture(onRelease: {
            visits.append("first")
            if !registered { registered = true; owner.register(later) }
            return false
        })
        owner.register(first)
        XCTAssertThrowsError(try owner.prepareMutation(of: current.allocation).get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
        }
        XCTAssertEqual(visits, ["first"])
        XCTAssertFalse(current.allocation.isDirty)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
        XCTAssertThrowsError(try paint(current, color: .blue)) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .writeNotAdmitted)
        }
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(current.image().get().cgImage)), [255, 0, 0, 255])
        }
        try owner.prepareMutation(of: current.allocation).get()
        XCTAssertEqual(visits, ["first", "first", "later"])
        XCTAssertNil(held)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2)
        try paint(current, color: .blue)
        try autoreleasepool {
            XCTAssertEqual(try pixel(XCTUnwrap(current.image().get().cgImage)), [0, 0, 255, 255])
        }
        XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        XCTAssertEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    func testBusyAndColdCandidatesAreTriedOncePerPassAndRemainRegistered() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes, makeRoom: { _ in true })
        let held = try owner.admitWorking(pictureBytes).get()
        var visits: [Int] = []
        let cold = (0..<64).map { index in
            CachedPicture(onRelease: { visits.append(index); return false })
        }
        cold.forEach { owner.register($0) }
        for _ in 0..<2 {
            visits.removeAll()
            XCTAssertThrowsError(try owner.admitWorking(1).get()) { error in
                XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
            }
            XCTAssertEqual(visits, Array(0..<64))
            XCTAssertEqual(owner.usage.workingBytes, pictureBytes)
            XCTAssertEqual(owner.usage.evictions, 0)
        }
        withExtendedLifetime((held, cold)) {}
    }

    func testEvictingAWrapperCannotPretendAnEscapedCGImageGaveItsBytesBack() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in false })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 5, makeRoom: { _ in true })
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
        withExtendedLifetime(workspace) {}
        workspace = nil
        XCTAssertEqual(owner.usage.workingBytes, 0)
        XCTAssertEqual(owner.usage.reservedCheckpointBytes, pictureBytes * 2)
        withExtendedLifetime(pictures) {}
    }

    func testWritingACheckpointedBufferMustReadmitItsWorkspaceBeforeChangingPixels() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 3, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 8, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 4, storage: storage, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 8, makeRoom: { _ in true })
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
            let blankImage = try XCTUnwrap(blank.resolveImage().get().cgImage)
            let blankBytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(blankImage, width: width, height: height))
            XCTAssertTrue(stride(from: 3, to: blankBytes.count, by: 4).allSatisfy { blankBytes[$0] == 0 },
                          "PREMISE: the actual native decoded blank draws fully transparent")
            let image = try XCTUnwrap(painted.resolveImage().get().cgImage)
            let bytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height))
            XCTAssertEqual(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 0 }.count, 1)
        }
        XCTAssertTrue(blank.isCertainlyTransparent)
        XCTAssertFalse(painted.isCertainlyTransparent, "Exact alpha proof must retain even one painted texel")
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
    }

    func testPinnedBlankProofIsAdmittedOnceAndCannotCrossIntoANewPaintedVersion() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 8, makeRoom: { _ in true })
        let size = CGSize(width: width, height: height)
        var current = try RasterSurface.allocate(width: width, height: height, using: owner).get()
        let blank = RasterSource.snapshot(of: current, size: size)
        XCTAssertFalse(blank.isCertainlyTransparent, "Freezing and metadata reads must not scan pixels")
        let before = owner.usage
        var attempts = 0
        XCTAssertThrowsError(try blank.prepareTransparencyProof { count in
            attempts += 1
            XCTAssertEqual(count, self.width * self.height)
            return false
        }.get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
        }
        XCTAssertFalse(blank.isCertainlyTransparent, "Refused work cannot publish a blank proof")
        XCTAssertTrue(try blank.prepareTransparencyProof { count in
            attempts += 1
            XCTAssertEqual(count, self.width * self.height)
            return true
        }.get(), "A refusal must leave the immutable version eligible for a later admitted scan")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(owner.usage, before, "A lease proof creates no image or pixel allocation")
        _ = try blank.resolveImage().get()
        XCTAssertTrue(blank.isCertainlyTransparent, "Image resolution must preserve an earlier lease proof")

        current = try current.preparedForWrite().get()
        try current.mutate { context in
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: self.width - 1, y: self.height - 1, width: 1, height: 1))
        }.get()
        let painted = RasterSource.snapshot(of: current, size: size)
        var paintedScans = 0
        XCTAssertFalse(try painted.prepareTransparencyProof { count in
            paintedScans += 1
            XCTAssertEqual(count, self.width * self.height)
            return true
        }.get(), "Even one painted texel makes this new immutable version nonempty")
        for source in [blank, painted] {
            _ = try source.prepareTransparencyProof { _ in
                XCTFail("Both inspected true and false are cached per immutable version")
                return false
            }.get()
        }
        XCTAssertEqual(paintedScans, 1)
        XCTAssertTrue(blank.isCertainlyTransparent)
        XCTAssertFalse(painted.isCertainlyTransparent)
        let old = try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(blank.resolveImage().get().cgImage)))
        let new = try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(painted.resolveImage().get().cgImage)))
        XCTAssertTrue(stride(from: 3, to: old.count, by: 4).allSatisfy { old[$0] == 0 })
        XCTAssertEqual(stride(from: 3, to: new.count, by: 4).filter { new[$0] != 0 }.count, 1)
        XCTAssertEqual(owner.usage.pixelBufferCount, 2, "COW retains two charged, distinct versions")
        XCTAssertTrue(ProjectStore.serializingPackageMutation { blank.releaseResidentPixels() })
        XCTAssertTrue(try blank.prepareTransparencyProof { _ in
            XCTFail("Retiring resident pixels cannot invalidate an immutable inspected fact")
            return false
        }.get())

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uninspected-proof-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("blank.png")
        try XCTUnwrap(PixelOps.transparentImage(size: size).pngData()).write(to: url)
        let backing = try ProjectStore.RasterBacking.protect(url, using: owner).get()
        let deferred = RasterSource.backed(by: backing, using: owner)
        let cold = owner.usage
        XCTAssertFalse(try deferred.prepareTransparencyProof { _ in
            XCTFail("An unresolved backing cannot eagerly decode before draw admission")
            return true
        }.get())
        XCTAssertEqual(owner.usage, cold)
        XCTAssertFalse(deferred.isCertainlyTransparent, "Uninspected backing remains unknown")
        let deferredImage = try XCTUnwrap(deferred.resolveImage().get().cgImage)
        let deferredBytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(deferredImage, width: width, height: height))
        XCTAssertTrue(stride(from: 3, to: deferredBytes.count, by: 4).allSatisfy { deferredBytes[$0] == 0 },
                      "PREMISE: the ordinary native backed image draws fully transparent")
        XCTAssertTrue(deferred.isCertainlyTransparent, "Ordinary backed decode keeps its existing exact proof")
        let unreadable = RasterSource.backed(by: backing, using: owner)
        try FileManager.default.removeItem(at: backing.url)
        XCTAssertThrowsError(try unreadable.resolveImage().get()) { error in
            XCTAssertEqual(error as? RasterResidency.Failure, .unreadableBacking)
        }
        XCTAssertFalse(unreadable.isCertainlyTransparent, "Failure must never become an empty picture")
    }

    private func mendCoverage(_ prepared: CanvasManager.FillReference, width: Int, height: Int) throws -> [UInt8] {
        let source = stride(from: 3, to: prepared.rgba.count, by: 4).map { prepared.rgba[$0] == 0 ? UInt8(255) : 0 }
        let session = try XCTUnwrap(MetalFillEngine.shared?.makeMendSession(referenceRGBA: prepared.rgba,
            width: width, height: height, sourceMask: source).session)
        session.installVectorReference(prepared.support)
        return try XCTUnwrap(session.mendMask(sourceMask: source, threshold: 0, artworkRect: nil, reach: 40))
    }

    @MainActor
    private func assertFreshEmptyRasterizePreservesMendCoverage(size: CGSize, strokes: [VectorStroke],
                                                               target: CGPoint) throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = size
        manager.addVectorLayer()
        XCTAssertTrue(manager.rasterizeLayer(layerIndex: 0), "Use the artist's actual empty Rasterize operation")
        XCTAssertEqual(manager.layers[0].kind, .raster)
        XCTAssertTrue(manager.layers[0].isFillReference, "The ordinary visible reference stays selected")
        let raster = try XCTUnwrap(manager.layers[0].cels.first?.raster)
        let frozenBlank = try XCTUnwrap(raster.snapshot())
        XCTAssertFalse(frozenBlank.isCertainlyTransparent, "Fresh snapshot metadata must not perform an alpha scan")
        manager.addVectorLayer()
        try XCTUnwrap(manager.layers[1].cels.first?.vector).restoreElements(strokes.map(VectorElement.stroke), changedInk: nil)
        let references = manager.fillReferenceSources()
        XCTAssertEqual(references.count, 2)
        XCTAssertTrue(references[0].cel.raster.snapshot() === frozenBlank,
                      "Preparation must inspect the same live version selected by the artist")
        let width = Int(size.width), height = Int(size.height)
        let window = FillWindow.fitting(CGRect(origin: .zero, size: size), in: size, pixelBudget: width * height)
        let targetIndex = Int(target.y) * width + Int(target.x)
        let expected = try manager.onFillLane {
            let vectorOnly = try XCTUnwrap(CanvasManager.makeFillReference(references: Array(references.dropFirst()), window: window))
            let withFreshRaster = try XCTUnwrap(CanvasManager.makeFillReference(references: references, window: window))
            XCTAssertEqual(withFreshRaster.rgba, vectorOnly.rgba, "Clear reference pixels do not alter the drawn ink")
            let baseline = try self.mendCoverage(vectorOnly, width: width, height: height)
            let actual = try self.mendCoverage(withFreshRaster, width: width, height: height)
            XCTAssertEqual(baseline[targetIndex], 255, "PREMISE: this real vector body has useful admitted coverage")
            XCTAssertEqual(actual, baseline, "Every mended pixel survives the selected fresh clear raster reference")
            return baseline
        }
        XCTAssertTrue(frozenBlank.isCertainlyTransparent, "The factory worker must establish its selected lease proof")
        XCTAssertNil(raster.snapshot(), "A proven clear tier can now use the existing empty snapshot contract")
        let dot = CanvasFixture.solidImage(.black, rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                           size: CGSize(width: 1, height: 1))
        try raster.restore(patch: dot, at: .zero).get()
        let changed = manager.fillReferenceSources()
        try manager.onFillLane {
            let painted = try XCTUnwrap(CanvasManager.makeFillReference(references: changed, window: window))
            XCTAssertEqual(painted.rgba[3], 255, "PREMISE: the new raster version really contains opaque ink")
            let protected = try self.mendCoverage(painted, width: width, height: height)
            XCTAssertEqual(expected[targetIndex], 255)
            XCTAssertEqual(protected[targetIndex], 0, "A painted reference keeps the conservative unknown-contributor veto")
        }
        XCTAssertTrue(frozenBlank.isCertainlyTransparent, "Later raster edits cannot change the pinned old proof")
        XCTAssertFalse(try XCTUnwrap(raster.snapshot()).isCertainlyTransparent)
    }

    @MainActor
    func testFreshEmptyRasterizeReferencePreservesSmallVectorMendCoverage() throws {
        let brush = Brush(name: "clear reference control", tip: .round, size: 6,
                          dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1))
        let stroke = VectorStroke(brush: brush, color: CodableColor(UIColor.black), size: 6,
            opacity: 1, samples: StrokeSamples(points: [CGPoint(x: 24, y: 32), CGPoint(x: 48, y: 32)]), seed: 0x7354)
        try assertFreshEmptyRasterizePreservesMendCoverage(size: CGSize(width: 96, height: 96),
                                                          strokes: [stroke], target: CGPoint(x: 36, y: 32))
    }

    @MainActor
    func testFreshEmptyRasterizeReferencePreservesTheOwnerSixStrokeMendCoverage() throws {
        // The six 232-sample runs and seeds retained from the failed owner-sized cold UI scene.
        // Only geometry is decoded here; the raster is freshly created through Rasterize, never
        // loaded from that saved package (which could already have a decoded transparency proof).
        let runs: [(UInt64, String)] = [
            (6773026793075080920, "BAD4WPoAJfhY+qdV+Fj6IYj4WPohv/hY+iH6+Fj6ITX5WPohdPlY+iG0+Vj6IfT5WPohN/pY+iF7+lj6Ib/6WPohBvtY+iFL+1j6IZL7WPoh2vtY+iEl/Fj6IW38WPohufxY+iEB/Vj6IU39WPohmP1Y+iHk/Vj6ITD+WPohfP5Y+iHI/lj6IRT/WPohYP9Y+iGs/1j6Ifj/WPohRABY+iGQAFj6INwAWPoiKAFY+iF0AVj6IcABWPohDAJY+iFVAlj6IaECWPoh6QJY+iEyA1j6IX0DWPohxQNY+iEKBFj6IVIEWPohlwRY+iHbBFj6IR8FWPohYwVY+iGkBVj6IeQFWPohIQZY+iFdBlj6IZkGWPoh0gZY+iEHB1j6ITwHWPohbQdY+iGaB1j6IcMHWPoh6AdY+iEACFj6IQ=="),
            (8875885953873151058, "BAAIWPoAAAh9+qcACLD6IQAI7fohAAgs+yEACG/7IQAIs/shAAj6+yEACEL8IQAIjfwhAAjY/CEACCT9IQAIcP0iAAi8/SEACAj+IQAIVP4hAAig/iEACOz+IQAINf8hAAh+/yEACMb/IQAICwAhAAhMACEACIkAIQAIxQAhAAj7ACEACCoBIQAIUAEhAAhcAQA="),
            (3025619991251117483, "BAAIXAEA2wdcAaerB1wBIXgHXAEhQQdcASEGB1wBIcsGXAEhjAZcASFMBlwBIQwGXAEhyQVcASGFBVwBIUEFXAEh+gRcASG1BFwBIW4EXAEhJgRcASHbA1wBIZMDXAEhRwNcASH/AlwBIbMCXAEhaAJcASEcAlwBIdABXAEhhAFcASE4AVwBIewAXAEhoABcASFUAFwBIQgAXAEfvP9cASNw/1wBIST/XAEh2P5cASGM/lwBIUD+XAEh9P1cASGr/VwBIV/9XAEhF/1cASHO/FwBIYP8XAEhO/xcASH2+1wBIa77XAEhaftcASEl+1wBIeH6XAEhnfpcASFc+lwBIRz6XAEh3/lcASGj+VwBIWf5XAEhLvlcASH5+FwBIcT4XAEhk/hcASFm+FwBIT34XAEhGPhcASEA+FwBIQ=="),
            (17381031590244746548, "BAD4XAEAAPg3AacA+AQBIQD4xwAhAPiIACEA+EUAIQD4AQAhAPi6/yEA+HL/IQD4J/8hAPjc/iEA+JD+IQD4RP4hAPj4/SEA+Kz9IQD4YP0hAPgU/SEA+Mj8IQD4f/whAPg2/CEA+O77IQD4qfshAPho+yEA+Cv7IQD47/ohAPi5+iEA+Ir6IQD4ZPohAPhY+gA="),
            (15815243569150207091, "BDT/2P0AWf/Y/aeM/9j9IcP/2P0hAQDY/SFAANj9IYMA2P0hxwDY/SEOAdj9IVYB2P0hoQHY/SHpAdj9ITUC2P0hgALY/SHMAtj9IRgD2P0hZAPY/SGwA9j9IfwD2P0hSATY/SGUBNj9IeAE2P0hKQXY/SFyBdj9IboF2P0hAgbY/SFHBtj9IYsG2P0hzAbY/SEJB9j9IUIH2P0hegfY/SGsB9j9IdcH2P0hAAjY/SE="),
            (17010733379972411770, "BOD6mPwAC/uY/KdG+5j8IYv7mPwh1fuY/CEg/Jj8IWz8mPwhtfyY/CH+/Jj8IUP9mPwhgf2Y/CGx/Zj8IcT9mPwh")
        ]
        var brush = BrushLibrary.roundSoft
        brush.size = 4.999999957159162
        let strokes = try runs.map { seed, data in
            let json = "{\"o\":[1024,512],\"d\":\"\(data)\"}"
            let samples = try JSONDecoder().decode(PackedSampleRun.self, from: Data(json.utf8)).samples
            return VectorStroke(brush: brush, color: CodableColor(UIColor.black), size: brush.size,
                                opacity: 1, samples: samples, seed: seed)
        }
        XCTAssertEqual(strokes.count, 6)
        XCTAssertEqual(strokes.reduce(0) { $0 + $1.samples.count }, 232)
        try assertFreshEmptyRasterizePreservesMendCoverage(size: CGSize(width: 2048, height: 1024),
                                                          strokes: strokes, target: CGPoint(x: 780, y: 294))
    }

    func testTheRealOwnerAdmitsOldAndNew4096PicturesWithCheckpointHeadroom() throws {
        let side = 4096
        let bytes = side * side * 4
        let budget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024) * 2
        let owner = RasterResidency(budgetBytes: budget, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 12, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 6, storage: storage, makeRoom: { _ in true })
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 6, makeRoom: { _ in allowed })
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
        let owner = RasterResidency(budgetBytes: outputBytes * 6, makeRoom: { bytes in
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
        manager.history.removeAll()
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 40, makeRoom: { _ in true })
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
        let decision = ProjectStore.save(manager, to: url, completion: { landed in
            failed = landed == nil
            finished.fulfill()
        })
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
        let authoredOwner = RasterResidency(budgetBytes: pictureBytes * 24, makeRoom: { _ in true })
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

        let owner = RasterResidency(budgetBytes: pictureBytes * 24, makeRoom: { _ in true })
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
                let file = try ProjectPackageLayout.resolve(ProjectPackageLayout.writePath(named: name, role: role), in: renamed)
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
        let owner = RasterResidency(budgetBytes: pictureBytes * 12, makeRoom: { _ in true })
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
        let savedRaster = try ProjectPackageLayout.resolve(ProjectPackageLayout.writePath(
            named: "\(celID.uuidString)_raster.png", role: .raster), in: url)
        let savedPixels = try Data(contentsOf: savedRaster)
        let blocker = root.appendingPathComponent("not-a-source-directory")
        try Data([1, 2, 3]).write(to: blocker)
        let refusedOwner = RasterResidency(budgetBytes: pictureBytes * 12,
            storage: ProjectStore.RasterStorage(url: blocker), makeRoom: { _ in true })
        let red = RasterSource.snapshot(of: try surface(refusedOwner), size: size)
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, source: red, strokeCount: 4)
        let identity = CelContentIdentity(manager.layers[0].cels[0])
        XCTAssertEqual(manager.packageLedger.landedAt?.standardizedFileURL.path, url.standardizedFileURL.path,
                       "The first successful save must establish the reuse memo before refusal")
        XCTAssertNotNil(manager.packageLedger.entry(for: celID))
        let completed = expectation(description: "failed normal save completed")
        var failed = false
        XCTAssertEqual(ProjectStore.save(manager, to: url, completion: { landed in
            failed = landed == nil
            completed.fulfill()
        }), .write)
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertTrue(failed)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), manifest)
        XCTAssertEqual(try Data(contentsOf: savedRaster), savedPixels)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), identity)
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 4)
        XCTAssertNil(manager.packageLedger.landedAt, "An invalid stage clears the existing reuse memo")
        XCTAssertNil(manager.packageLedger.entry(for: celID))
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
        let owner = RasterResidency(budgetBytes: bytes * 12, makeRoom: { requested in
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
        let fill = CanvasManager.FillRenderResult(generation: manager.fillGeneration, documentFrame: manager.currentFrame,
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
        manager.shapeGestureSamples = [VectorSample(x: 4, y: 10), VectorSample(x: 18, y: 10)]
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
        manager.history.removeAll()
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
        let owner = RasterResidency(budgetBytes: bytes * 32, makeRoom: { _ in !refusing })
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
        let procedure = try XCTUnwrap(manager.requestedLiquifyEdit?.procedure)
        _ = procedure.resolve(session.elementsBefore)
        XCTAssertFalse(procedure.hasFailed)
        refusing = true
        manager.commitLiquify(session)
        XCTAssertTrue(procedure.isPending)
        let refusedBytes = owner.usage.chargedBytes
        for _ in 0..<3 {
            XCTAssertFalse(manager.beginCanvasEdit())
            XCTAssertTrue(procedure.isPending)
            XCTAssertTrue(manager.requestedLiquifyEdit?.procedure === procedure)
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

    @MainActor
    func testLiveMaskAdmissionUsesTheSameStagedFillAsTheNewStrokeWithoutLandingItEarly() throws {
        let size = CGSize(width: 64, height: 64)
        let owner = RasterResidency(budgetBytes: 64 * 64 * 4 * 16, makeRoom: { _ in true })
        let source = try RasterSource.render(size: size, using: owner) { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
            return true
        }.get()
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.canvasSize = size
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, source: source, strokeCount: 1)
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        let masks = try XCTUnwrap(RenderNode.masksClipping(leafAt: 1, in: manager.renderTree(atFrame: 0)))
        let recipe = try XCTUnwrap(manager.liveMaskRecipe(atFrame: 0))
        let old = try XCTUnwrap(MaskResolver.coverage(for: masks, of: recipe).get())
        XCTAssertEqual(old.coverage[32 * old.width + 48], 0)
        manager.fillGestureActive = true
        manager.fillFingerDown = false
        manager.fillGestureLayerID = manager.layers[0].id
        manager.fillGestureCelID = manager.layers[0].cels[0].id
        manager.fillGestureFillColor = CodableColor(.green)
        let fill = CanvasManager.FillRenderResult(generation: manager.fillGeneration, documentFrame: manager.currentFrame,
            bytes: Array(repeating: [UInt8(0), 255, 0, 255], count: 64 * 64).flatMap { $0 },
            window: FillWindow.fitting(CGRect(origin: .zero, size: size), in: size, pixelBudget: 64 * 64))
        manager.fillRenderedRegion = fill
        let identity = CelContentIdentity(manager.layers[0].cels[0])
        let history = manager.history.undoStack.count
        let prepared = try XCTUnwrap(manager.prepareCanvasEdit())
        let stagedRecipe = try XCTUnwrap(manager.liveMaskRecipe(atFrame: 0, preparing: prepared.cels))
        let staged = try XCTUnwrap(MaskResolver.coverage(for: masks, of: stagedRecipe).get())
        XCTAssertEqual(staged.coverage[32 * staged.width + 48], 255,
                       "The pending fill changes the source alpha used by this admitted stroke")
        XCTAssertNotEqual(staged.coverage, old.coverage)
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), identity)
        XCTAssertTrue(manager.fillGestureActive)
        XCTAssertTrue(manager.fillRenderedRegion === fill)
        XCTAssertEqual(manager.history.undoStack.count, history)
        XCTAssertTrue(prepared.commit())
        let landedRecipe = try XCTUnwrap(manager.liveMaskRecipe(atFrame: 0))
        let landed = try XCTUnwrap(MaskResolver.coverage(for: masks, of: landedRecipe).get())
        XCTAssertEqual(landed.coverage, staged.coverage)
        XCTAssertFalse(manager.fillGestureActive)
        XCTAssertEqual(manager.history.undoStack.count, history + 1)
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)
    }

    func testNormal4096PaintAndEraseAdmitTheirWindowAndExactBeforeAfterPatches() throws {
        let size = CGSize(width: 4096, height: 4096)
        let budget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024) * 2
        for erasing in [false, true] {
            try autoreleasepool {
                let owner = RasterResidency(budgetBytes: budget, makeRoom: { _ in true })
                let red = try RasterSource.render(size: size, using: owner) { context in
                    context.setFillColor(UIColor.red.cgColor)
                    context.fill(CGRect(origin: .zero, size: size))
                    return true
                }.get()
                let raster = RasterLayerTexture(size: size, source: red, strokeCount: 1)
                let backdrop = try red.resolveImage().get()
                let backdropPicture = CelContentPicture(size: size, window: CGRect(origin: .zero, size: size),
                    backing: nil, patch: nil, ink: .rendered(backdrop))
                let scratch = StrokeScratch(canvasSize: size,
                    role: erasing ? .subtractive(backdrop: backdropPicture) : .additive, residency: owner)
                scratch.stampCircle(at: CGPoint(x: 32, y: 32), radius: 4, color: .blue,
                                    alpha: 1, hardness: 1, blendMode: .normal)
                try scratch.lastMutationResult.get()
                XCTAssertLessThan(scratch.windowPixelCount, 256 * 256)
                let rect = try XCTUnwrap(scratch.dirtyRect).integral
                let before = try XCTUnwrap(raster.copiedPatch(in: rect).get())
                let after = try scratch.preparedPatch(over: before, in: rect).get()
                let image = try after.resolveImage().get()
                try raster.restore(patch: image, at: rect.origin).get()
                raster.setStrokeCount(2)
                let current = try XCTUnwrap(raster.snapshot())
                let spot = try current.cropped(to: CGRect(x: 31, y: 31, width: 2, height: 2)).get()
                let rgba = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
                    XCTUnwrap(spot.resolveImage().get().cgImage), width: 2, height: 2))
                let expected: [UInt8] = erasing ? [0, 0, 0, 0] : [0, 0, 255, 255]
                XCTAssertEqual(rgba, Array(repeating: expected, count: 4).flatMap { $0 })
                let old = try red.cropped(to: CGRect(x: 31, y: 31, width: 2, height: 2)).get()
                XCTAssertEqual(try CoreGraphicsCompositor.premultipliedBytes(
                    XCTUnwrap(old.resolveImage().get().cgImage), width: 2, height: 2),
                    Array(repeating: [UInt8(255), 0, 0, 255], count: 4).flatMap { $0 })
                XCTAssertEqual(raster.strokeCount, 2)
                XCTAssertLessThanOrEqual(owner.usage.admittedBytes, budget)
                XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, budget)
            }
        }
    }

    func testNormal4096MoveSplitAdmitsBothOwnedOutputsTogetherAndKeepsTheirExactPixels() throws {
        try autoreleasepool {
            let size = CGSize(width: 4096, height: 4096)
            let bytes = 4096 * 4096 * 4
            let budget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024) * 2
            let owner = RasterResidency(budgetBytes: budget, makeRoom: { _ in true })
            let red = try RasterSource.render(size: size, using: owner) { context in
                context.setFillColor(UIColor.red.cgColor)
                context.fill(CGRect(x: 20, y: 20, width: 12, height: 12))
                return true
            }.get()
            let path = CGPath(rect: CGRect(x: 20, y: 20, width: 6, height: 12), transform: nil)
            let split = try PixelOps.maskedPiece(image: red.resolveImage().get(), path: path, using: owner).get()
            XCTAssertEqual(owner.usage.pixelBufferCount, 3)
            XCTAssertEqual(owner.usage.pixelBytes, bytes * 3)
            XCTAssertEqual(owner.usage.reservedCheckpointBytes, bytes * 2)
            let piece = try split.piece.cropped(to: CGRect(x: 21, y: 21, width: 2, height: 2)).get()
            let hole = try split.remainder.cropped(to: CGRect(x: 21, y: 21, width: 2, height: 2)).get()
            let kept = try split.remainder.cropped(to: CGRect(x: 29, y: 21, width: 2, height: 2)).get()
            func rgba(_ source: RasterSource) throws -> [UInt8] {
                try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
                    XCTUnwrap(source.resolveImage().get().cgImage), width: 2, height: 2))
            }
            let fourRed = Array(repeating: [255, 0, 0, 255] as [UInt8], count: 4).flatMap { $0 }
            XCTAssertEqual(try rgba(piece), fourRed)
            XCTAssertEqual(try rgba(hole), Array(repeating: UInt8(0), count: 16))
            XCTAssertEqual(try rgba(kept), fourRed)
            XCTAssertLessThanOrEqual(owner.usage.admittedBytes, budget)
            XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, budget)
        }
    }

    func testNormal4096LiquifyKeepsWindowWorkAndFinalOwnedPictureWithinTheConfiguredEnvelope() throws {
        try autoreleasepool {
            let size = CGSize(width: 4096, height: 4096)
            let budget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024) * 2
            let owner = RasterResidency(budgetBytes: budget, makeRoom: { _ in true })
            let red = try RasterSource.render(size: size, using: owner) { context in
                context.setFillColor(UIColor.red.cgColor)
                context.fill(CGRect(x: 20, y: 18, width: 9, height: 12))
                return true
            }.get()
            let snapshot = CelPixelSnapshot(rasterSource: red, bakedSource: nil, size: size)
            let deformation = LiquifyDeformation(brush: TestBrushes.hardRound, size: 40, power: 1,
                mode: .push, seed: 7, samples: StrokeSamples([
                    VectorSample(x: 24, y: 24), VectorSample(x: 38, y: 24)], channels: .pressureOnly))
            let window = CGRect(x: 0, y: 0, width: 60, height: 48)
            let patch = try XCTUnwrap(snapshot.liquifiedPatch(in: window, using: LiquifyField(deformation)))
            XCTAssertTrue(patch.changed)
            let final = try XCTUnwrap(snapshot.committing(patch))
            let before = try red.cropped(to: window).get()
            let after = try final.cropped(to: window).get()
            let oldRGBA = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
                XCTUnwrap(before.resolveImage().get().cgImage), width: 60, height: 48))
            let newRGBA = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
                XCTUnwrap(after.resolveImage().get().cgImage), width: 60, height: 48))
            XCTAssertNotEqual(oldRGBA, newRGBA)
            XCTAssertGreaterThan(stride(from: 3, to: newRGBA.count, by: 4).filter { newRGBA[$0] > 0 }.count, 0)
            XCTAssertEqual(newRGBA, try CoreGraphicsCompositor.premultipliedBytes(
                XCTUnwrap(patch.image.cgImage), width: 60, height: 48))
            XCTAssertLessThanOrEqual(owner.usage.admittedBytes, budget)
            XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, budget)
            XCTAssertEqual(owner.usage.workingBytes, 0)
        }
    }

    @MainActor
    func testWholeCelUndoAndRedoRefuseBeforeStackOrPixelChangesThenReleasePreparedPinsOnRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-cel-history-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var allowed = true
        let owner = RasterResidency(budgetBytes: pictureBytes * 24, makeRoom: { _ in allowed })
        let size = CGSize(width: width, height: height)
        func backed(_ color: UIColor, name: String) throws -> RasterSource {
            let url = root.appendingPathComponent(name + ".png")
            try XCTUnwrap(CanvasFixture.solidImage(color, rect: CGRect(origin: .zero, size: size), size: size).pngData()).write(to: url)
            return RasterSource.backed(by: try ProjectStore.RasterBacking.protect(url, using: owner).get(), using: owner)
        }
        let red = try backed(.red, name: "red")
        let green = try backed(.green, name: "green")
        let blue = try backed(.blue, name: "blue")
        let oldRaster = RasterLayerTexture(size: size, source: red, strokeCount: 2)
        let newRaster = RasterLayerTexture(size: size, source: blue, strokeCount: 4)
        let manager = CanvasFixture.manager()
        manager.canvasSize = size
        let layerID = manager.layers[0].id, celID = manager.layers[0].cels[0].id
        manager.layers[0].cels[0].raster = oldRaster
        manager.layers[0].cels[0].bakedImage = green
        manager.history.removeAll()
        manager.registerUndoableCelChange(layerID: layerID, celID: celID,
            oldRaster: oldRaster, oldBaked: green, newRaster: newRaster, newBaked: nil, label: .fill)
        func pixels(_ raster: RasterLayerTexture) throws -> [UInt8] {
            try autoreleasepool { try pixel(XCTUnwrap(raster.renderToUIImage().get().cgImage)) }
        }
        // The first required target is resident; refusal must happen on the second tier and still
        // preserve the complete current picture and both stacks.
        XCTAssertEqual(try pixels(oldRaster), [255, 0, 0, 255])
        XCTAssertEqual(try pixels(newRaster), [0, 0, 255, 255])
        let newIdentity = CelContentIdentity(manager.layers[0].cels[0])
        let bytesBeforeUndo = owner.usage.pixelBytes
        allowed = false
        XCTAssertNil(manager.history.undo())
        XCTAssertEqual(manager.history.undoStack.map(\.label), [.fill])
        XCTAssertTrue(manager.history.redoStack.isEmpty)
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), newIdentity)
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 4)
        XCTAssertEqual(try pixels(manager.layers[0].cels[0].raster), [0, 0, 255, 255])
        XCTAssertEqual(owner.usage.pixelBytes, bytesBeforeUndo)
        XCTAssertEqual(manager.notice?.kind, .drawingSourceUnavailable)
        allowed = true
        XCTAssertEqual(manager.history.undo(), .fill)
        XCTAssertTrue(manager.history.undoStack.isEmpty)
        XCTAssertEqual(manager.history.redoStack.map(\.label), [.fill])
        XCTAssertTrue(manager.layers[0].cels[0].raster === oldRaster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === green)
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 2)
        XCTAssertEqual(try pixels(manager.layers[0].cels[0].raster), [255, 0, 0, 255])
        XCTAssertTrue(blue.releaseResidentPixels())
        let oldIdentity = CelContentIdentity(manager.layers[0].cels[0])
        let bytesBeforeRedo = owner.usage.pixelBytes
        allowed = false
        XCTAssertNil(manager.history.redo())
        XCTAssertTrue(manager.history.undoStack.isEmpty)
        XCTAssertEqual(manager.history.redoStack.map(\.label), [.fill])
        XCTAssertEqual(CelContentIdentity(manager.layers[0].cels[0]), oldIdentity)
        XCTAssertEqual(manager.layers[0].cels[0].raster.strokeCount, 2)
        XCTAssertEqual(try pixels(manager.layers[0].cels[0].raster), [255, 0, 0, 255])
        XCTAssertEqual(owner.usage.pixelBytes, bytesBeforeRedo)
        allowed = true
        XCTAssertEqual(manager.history.redo(), .fill)
        XCTAssertEqual(manager.history.undoStack.map(\.label), [.fill])
        XCTAssertTrue(manager.history.redoStack.isEmpty)
        XCTAssertTrue(manager.layers[0].cels[0].raster === newRaster)
        XCTAssertNil(manager.layers[0].cels[0].bakedImage)
        XCTAssertEqual(try pixels(manager.layers[0].cels[0].raster), [0, 0, 255, 255])
        XCTAssertNil(manager.history.redo(), "One successful retry consumes exactly one action")
        for source in [red, green, blue] { XCTAssertTrue(source.releaseResidentPixels()) }
        XCTAssertEqual(owner.usage.pixelBufferCount, 0, "Neither successful direction may retain its temporary provider pins")
        XCTAssertLessThanOrEqual(owner.usage.admittedBytes, owner.budgetBytes)

        // Empty successful preparation must remain different from the nil failure above.
        manager.history.removeAll()
        let emptyBefore = RasterLayerTexture(size: size, residency: owner)
        let emptyAfter = RasterLayerTexture(size: size, strokeCount: 3, residency: owner)
        manager.registerUndoableCelChange(layerID: layerID, celID: celID,
            oldRaster: emptyBefore, oldBaked: nil, newRaster: emptyAfter, newBaked: nil, label: .clearFrame)
        allowed = false
        XCTAssertEqual(manager.history.undo(), .clearFrame)
        XCTAssertTrue(manager.layers[0].cels[0].raster === emptyBefore)
        XCTAssertEqual(manager.history.redo(), .clearFrame)
        XCTAssertTrue(manager.layers[0].cels[0].raster === emptyAfter)
        XCTAssertEqual(owner.usage.pixelBufferCount, 0)
    }

}

extension RasterResidencyLogicTests {
    private final class NativeReleaseCount { var value = 0 }
    private final class NativeFixtureBytes {
        let pointer: UnsafeMutableRawPointer
        let count: Int
        let releases: NativeReleaseCount
        init(_ bytes: Data, releases: NativeReleaseCount) {
            count = bytes.count; self.releases = releases
            pointer = .allocate(byteCount: bytes.count, alignment: 16)
            bytes.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
        }
        func provider() throws -> CGDataProvider {
            let retained = Unmanaged.passRetained(self)
            guard let provider = CGDataProvider(dataInfo: retained.toOpaque(), data: pointer, size: count,
                releaseData: { info, _, _ in if let info { Unmanaged<NativeFixtureBytes>.fromOpaque(info).release() } })
            else { retained.release(); throw NSError(domain: "NativeFixture", code: 1) }
            return provider
        }
        deinit { pointer.deallocate(); releases.value += 1 }
    }

    private struct NativeImageFields: Equatable {
        let width: Int, height: Int, row: Int, bpc: Int, bpp: Int
        let bitmap: UInt32, alpha: UInt32
        let intent: Int32
        let interpolates: Bool
        let model: Int32
        let profile: Data?
        let decode: [CGFloat]?
        init(_ image: CGImage) throws {
            let space = try XCTUnwrap(image.colorSpace)
            width = image.width; height = image.height; row = image.bytesPerRow
            bpc = image.bitsPerComponent; bpp = image.bitsPerPixel
            bitmap = image.bitmapInfo.rawValue; alpha = image.alphaInfo.rawValue
            intent = image.renderingIntent.rawValue; interpolates = image.shouldInterpolate
            model = space.model.rawValue; profile = space.copyICCData().map { $0 as Data }
            decode = image.decode.map { Array(UnsafeBufferPointer(start: $0, count: space.numberOfComponents * 2)) }
        }
    }

    /// Eight actual native layouts; every raw row includes deliberately nonzero padding.
    private func nativeFixture(_ family: Int, releases: NativeReleaseCount) throws -> (image: CGImage, bytes: Data) {
        let components = family == 4 || family == 7 ? 1 : (family == 5 ? 2 : 4)
        let depth = family == 2 || family == 3 || family == 5 ? 16 : 8
        let row = components * 3 * (depth / 8) + 4
        let space: CGColorSpace
        switch family {
        case 0: space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        case 1, 2: space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        case 3: space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        case 4, 5: space = CGColorSpaceCreateDeviceGray()
        case 6: space = CGColorSpaceCreateDeviceCMYK()
        default:
            let palette: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]
            space = try XCTUnwrap(palette.withUnsafeBufferPointer {
                CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 3, colorTable: $0.baseAddress!)
            })
        }
        let alpha: CGImageAlphaInfo = family == 4 || family == 6 || family == 7 ? .none : (family == 2 ? .last : .premultipliedLast)
        let order: UInt32 = depth == 16 ? CGBitmapInfo.byteOrder16Little.rawValue
            : (components == 4 && family != 6 ? CGBitmapInfo.byteOrder32Big.rawValue : 0)
        let bitmap = CGBitmapInfo(rawValue: alpha.rawValue | order | (family == 3 ? CGBitmapInfo.floatComponents.rawValue : 0))
        var bytes = Data(repeating: 0xA7, count: row * 2)
        let coverage: [Double] = [1, 0, 1.0 / 255, 0.25, 0.5, 1]
        let colours: [[Double]] = [[1, 0, 0.125], [0.37, 0.79, 0.19], [0.01, 0.29, 0.93],
                                   [0.83, 0.02, 0.41], [0.14, 0.91, 0.07], [0.61, 0.23, 0.87]]
        for pixel in 0..<6 {
            let a = coverage[pixel]
            var channels: [Double]
            switch family {
            case 4: channels = [colours[pixel][0]]
            case 5: channels = [colours[pixel][0] * a, a]
            case 6: channels = [colours[pixel][0], colours[pixel][1], colours[pixel][2], 0] // K=0 is opaque.
            case 7: channels = [Double(pixel % 4) / 255]
            default:
                channels = family == 3 && pixel == 0 ? [1.375, -0.125, 0.625] : colours[pixel]
                if family != 2 { channels = channels.map { $0 * a } }
                channels.append(a)
            }
            let offset = (pixel / 3) * row + (pixel % 3) * components * (depth / 8)
            for component in 0..<components {
                if depth == 8 { bytes[offset + component] = UInt8((channels[component] * 255).rounded()) }
                else {
                    let value = family == 3 ? Float16(channels[component]).bitPattern : UInt16((channels[component] * 65535).rounded())
                    bytes[offset + component * 2] = UInt8(truncatingIfNeeded: value)
                    bytes[offset + component * 2 + 1] = UInt8(truncatingIfNeeded: value >> 8)
                }
            }
        }
        let storage = NativeFixtureBytes(bytes, releases: releases), provider = try storage.provider()
        let decode: [CGFloat]? = family == 0 ? [0.125, 0.875, 0, 1, 0, 1] : nil
        func make(_ ranges: UnsafePointer<CGFloat>?) -> CGImage? {
            CGImage(width: 3, height: 2, bitsPerComponent: depth, bitsPerPixel: depth * components,
                bytesPerRow: row, space: space, bitmapInfo: bitmap, provider: provider, decode: ranges,
                shouldInterpolate: false, intent: .relativeColorimetric)
        }
        let made: CGImage?
        if let decode { made = decode.withUnsafeBufferPointer { make($0.baseAddress) } }
        else { made = make(nil) }
        let image = try XCTUnwrap(made, "PREMISE: family\(family) has its explicit native representation")
        XCTAssertEqual(image.bitsPerComponent, depth); XCTAssertEqual(image.bitsPerPixel, depth * components)
        XCTAssertEqual(image.bitmapInfo, bitmap); XCTAssertEqual(image.alphaInfo, alpha)
        XCTAssertEqual(image.bytesPerRow, row)
        XCTAssertEqual(try NativeImageFields(image).decode, decode)
        return (image, bytes)
    }

    private func nativeSamples(_ image: CGImage) throws -> Data {
        let data = try XCTUnwrap(image.dataProvider?.data)
        return Data(bytes: try XCTUnwrap(CFDataGetBytePtr(data)), count: CFDataGetLength(data))
    }

    /// Explicit high-depth P3 destination, always drawn into the SAME original-presentation rect.
    /// A PNG reader resetting UIImage.scale to1 must not change the codec comparison's geometry.
    private func nativeDrawing(_ image: UIImage, rect: CGRect) throws -> Data {
        let side = 16, row = 16 * 4 * MemoryLayout<Float>.size
        var bytes = Data(count: row * side)
        try bytes.withUnsafeMutableBytes { data in
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
            let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            let cg = try XCTUnwrap(CGContext(data: data.baseAddress, width: side, height: side, bitsPerComponent: 32,
                bytesPerRow: row, space: space, bitmapInfo: info), "PREMISE: explicit Float32 P3 destination")
            cg.interpolationQuality = .none
            cg.translateBy(x: 0, y: CGFloat(side)); cg.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(cg); defer { UIGraphicsPopContext() }
            image.draw(in: rect)
        }
        let samples = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertTrue(stride(from: 3, to: samples.count, by: 4).contains { samples[$0] > 0 }, "PREMISE: the picture really draws")
        return bytes
    }

    func testNativePlacedSourcesKeepOneHundredTwentyEightPresentationsExactThroughPrivateEvictionAndPublicPNG() throws {
        let orientations: [UIImage.Orientation] = [.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored]
        let referenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("native-png-reference-\(UUID())")
        try FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: referenceDirectory) }
        var checked = 0, normalizedPNGEqual = 0
        for family in 0..<8 {
            for orientation in orientations {
                for scale in [CGFloat(1), 2] {
                    let owner = RasterResidency(budgetBytes: 4096, makeRoom: { _ in true })
                    let original = NativeReleaseCount()
                    var source: RasterSource?, escaped: CGImage?
                    var fields: NativeImageFields?, samples = Data(), drawing = Data()
                    var rect = CGRect.zero, pointSize = CGSize.zero
                    try autoreleasepool {
                        let fixture = try nativeFixture(family, releases: original)
                        let input = UIImage(cgImage: fixture.image, scale: scale, orientation: orientation)
                        fields = try NativeImageFields(fixture.image)
                        samples = fixture.bytes; pointSize = input.size
                        rect = CGRect(x: 2, y: 2, width: input.size.width * 4, height: input.size.height * 4)
                        drawing = try nativeDrawing(input, rect: rect)
                        source = try RasterSource.capturePlaced(input, using: owner).get()
                        let captured = try XCTUnwrap(source)
                        XCTAssertEqual(captured.size, input.size)
                        XCTAssertEqual(captured.descriptor.scale, scale); XCTAssertEqual(captured.descriptor.orientation, orientation)
                        XCTAssertEqual(captured.logicalPayloadBytes, samples.count)
                        let owned = try captured.resolveImage().get()
                        XCTAssertEqual(try NativeImageFields(try XCTUnwrap(owned.cgImage)), fields)
                        XCTAssertEqual(try nativeSamples(XCTUnwrap(owned.cgImage)), samples)
                        XCTAssertEqual(try nativeDrawing(owned, rect: rect), drawing)
                        if family >= 4 {
                            var scans = 0
                            XCTAssertFalse(try captured.prepareTransparencyProof { _ in scans += 1; return false }.get())
                            XCTAssertEqual(scans, 0, "Unknown alpha layouts never charge or refuse a nonexistent RGBA scan")
                            XCTAssertFalse(captured.isCertainlyTransparent, "CMYK K=0 and opaque gray/indexed pictures remain ink")
                        }
                        let native = try ProjectStore.serializingPackageMutation { try captured.checkpointForEviction().get() }
                        XCTAssertFalse(native.isPNG); XCTAssertEqual(native.url.pathExtension, "raster")
                        if family < 4 {
                            let first = try ProjectStore.serializingPackageMutation { try captured.prepareForSave().get() }
                            let second = try ProjectStore.serializingPackageMutation { try captured.prepareForSave().get() }
                            XCTAssertTrue(first.encoded); XCTAssertFalse(second.encoded)
                            XCTAssertEqual(first.backing.url, second.backing.url, "One PNG export per immutable version")
                            let oldURL = referenceDirectory.appendingPathComponent("\(family)-\(orientation.rawValue)-\(scale).png")
                            try XCTUnwrap(ProjectStore.encodeRasterPNG(input)).write(to: oldURL)
                            let oldRead = try XCTUnwrap(UIImage(contentsOfFile: oldURL.path))
                            let newRead = try XCTUnwrap(UIImage(contentsOfFile: first.backing.url.path))
                            XCTAssertEqual(oldRead.imageOrientation, newRead.imageOrientation)
                            XCTAssertEqual(oldRead.size, newRead.size)
                            XCTAssertEqual(try nativeDrawing(oldRead, rect: rect), try nativeDrawing(newRead, rect: rect),
                                           "Public output keeps the actual old PNG codec's picture")
                            if try nativeDrawing(oldRead, rect: rect) == drawing { normalizedPNGEqual += 1 }
                            XCTAssertEqual(try nativeDrawing(try captured.resolveImage().get(), rect: rect), drawing,
                                           "Public PNG export cannot replace the live native picture")
                        }
                        XCTAssertTrue(captured.releaseResidentPixels())
                    }
                    XCTAssertEqual(original.value, 1, "The source must not keep its original UIImage/CGImage/provider alive")
                    XCTAssertEqual(owner.usage.pixelBufferCount, 0)
                    let beforeMetadata = owner.usage.allocations
                    try autoreleasepool {
                        let value = try XCTUnwrap(source)
                        let element = VectorImageElement(source: value, transform: .identity)
                        XCTAssertEqual(element.naturalSize, pointSize)
                        XCTAssertEqual(element.pixelSize, CGSize(width: pointSize.width * scale, height: pointSize.height * scale))
                        _ = element.corners
                        XCTAssertEqual(VectorUndoCost.bytes(from: [.image(element)], to: [.image(element)]), MemoryLayout<VectorElement>.stride)
                        XCTAssertEqual(owner.usage.allocations, beforeMetadata, "Bounds/geometry/history metadata never decode")
                        let reloaded = try value.resolveImage().get()
                        escaped = try XCTUnwrap(reloaded.cgImage)
                        XCTAssertEqual(try NativeImageFields(XCTUnwrap(escaped)), fields)
                        XCTAssertEqual(try nativeSamples(XCTUnwrap(escaped)), samples)
                        XCTAssertEqual(reloaded.size, pointSize); XCTAssertEqual(reloaded.scale, scale)
                        XCTAssertEqual(reloaded.imageOrientation, orientation)
                        XCTAssertEqual(try nativeDrawing(reloaded, rect: rect), drawing)
                        XCTAssertTrue(value.releaseResidentPixels())
                    }
                    source = nil
                    XCTAssertEqual(owner.usage.pixelBufferCount, 1, "Escaping provider keeps its real charge after source retirement")
                    XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: owner.storage.url, includingPropertiesForKeys: nil).count, 0,
                                   "Last source/backing ref removes both native and derived PNG resources")
                    try autoreleasepool {
                        XCTAssertEqual(try nativeDrawing(UIImage(cgImage: XCTUnwrap(escaped), scale: scale, orientation: orientation), rect: rect), drawing)
                    }
                    escaped = nil
                    XCTAssertEqual(owner.usage.chargedBytes, 0)
                    XCTAssertEqual(owner.usage.reservedCheckpointBytes, 0)
                    XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 128)
        print("NATIVE_SOURCE matrix=\(checked) normalizedPNGEqual=\(normalizedPNGEqual)/64 exactNativeBytes=true")
    }
}

extension RasterResidencyLogicTests {
    func testPlacedSourceWindowAndLogicalHistoryStayBoundedAfterEviction() throws {
        let extent = width * height * 4
        let owner = RasterResidency(budgetBytes: extent * 5, makeRoom: { _ in true })
        let ring = DecodedFrameRing(byteBudget: extent)
        var versions: [RasterSource] = []
        for index in 0..<4 {
            try autoreleasepool {
                let colour: [UInt8] = [UInt8(30 + index * 40), 20, 10, 255]
                var data = Data()
                for _ in 0..<(width * height) { data.append(contentsOf: colour) }
                let frame = DecodedFrame(width: width, height: height, pixels: data)
                XCTAssertTrue(ring.insert(frame, for: "source-\(index)"))
                let source = try RasterSource.capturePlaced(UIImage(cgImage: XCTUnwrap(frame.makeImage())), using: owner).get()
                _ = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
                XCTAssertTrue(source.releaseResidentPixels())
                versions.append(source)
            }
            XCTAssertEqual(owner.usage.pixelBytes, 0)
            XCTAssertEqual(ring.byteCount, extent)
        }
        ring.removeAll()
        for source in versions {
            try autoreleasepool {
                let resolved = try source.resolveImage().get()
                XCTAssertEqual(resolved.size, CGSize(width: width, height: height))
                XCTAssertEqual(owner.usage.pixelBufferCount, 1)
                XCTAssertTrue(source.releaseResidentPixels())
            }
            XCTAssertEqual(owner.usage.pixelBytes, 0)
        }
        let a = VectorImageElement(source: versions[0], transform: .identity)
        var translated = a; translated.transform.position.x = 4
        XCTAssertEqual(VectorUndoCost.bytes(from: [.image(a)], to: [.image(translated)]), MemoryLayout<VectorElement>.stride)
        let shared = RasterUndoCost.sources(baked: [versions[0]], elements: [[.image(a)], [.image(a)]])
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(RasterUndoCost.bytes(from: [:], to: shared), extent,
                       "One source shared by placed/baked tiers is one action-local retention price")
        versions.removeAll()
        XCTAssertLessThanOrEqual(owner.usage.highWaterBytes, owner.budgetBytes)
    }

    func testPlacedSourceHistoryTrimsLogicalVersionsAndDeletesOnlyTheirLastBackingReferences() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 5, makeRoom: { _ in true })
        var urls: [URL] = []
        func version(_ colour: UIColor) throws -> RasterSource {
            let pixels = try surface(owner, color: colour)
            let source = RasterSource.snapshot(of: pixels, size: CGSize(width: width, height: height))
            let backing = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            urls.append(backing.url)
            XCTAssertTrue(source.releaseResidentPixels())
            return source
        }
        var current: RasterSource? = try autoreleasepool { try version(.red) }
        let bytes = try XCTUnwrap(current).logicalPayloadBytes
        let stepCost = UndoBudget.addingCost(MemoryLayout<VectorElement>.stride, bytes * 2)
        let history = UndoHistory(maxCost: stepCost * 2)
        for colour in [UIColor.green, .blue, .yellow] {
            try autoreleasepool {
                let before = try XCTUnwrap(current), after = try version(colour)
                let old = VectorImageElement(source: before, transform: .identity)
                let new = VectorImageElement(source: after, transform: .identity)
                let cost = VectorUndoCost.bytes(from: [.image(old)], to: [.image(new)])
                XCTAssertEqual(cost, stepCost)
                history.record(.init(label: .insertImage, cost: cost,
                    undo: { current = before }, redo: { current = after }))
                current = after
            }
        }
        XCTAssertEqual(history.undoStack.count, 2)
        XCTAssertEqual(history.currentCost, stepCost * 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path), "Trimming releases the oldest history-only source")
        let finalID = current?.residencyID
        XCTAssertEqual(history.undo(), .insertImage)
        XCTAssertNotEqual(current?.residencyID, finalID)
        XCTAssertEqual(history.currentCost, stepCost * 2, "Redo retains the same logical source versions")
        XCTAssertEqual(history.redo(), .insertImage)
        XCTAssertEqual(current?.residencyID, finalID, "Redo shares the immutable source handle")
        XCTAssertEqual(history.trimUnderMemoryPressure(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[1].path))
        history.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[2].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[3].path), "The live source still owns its backing")
        current = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[3].path))
        XCTAssertEqual(owner.usage.chargedBytes, 0)
    }

    func testNativeCheckpointWriteFailureAndCorruptionNeverReplacePixelsWithBlank() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("native-failure-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("blocked")
        try Data([9]).write(to: blocked)
        let owner = RasterResidency(budgetBytes: 4096, storage: ProjectStore.RasterStorage(url: blocked), makeRoom: { _ in true })
        let released = NativeReleaseCount()
        let fixture = try nativeFixture(2, releases: released)
        let source = try RasterSource.capturePlaced(UIImage(cgImage: fixture.image), using: owner).get()
        try autoreleasepool {
            let failure = ProjectStore.serializingPackageMutation { source.checkpointForEviction() }
            guard case .failure = failure else { return XCTFail("A file occupying the source directory must refuse checkpointing") }
            XCTAssertEqual(try nativeSamples(XCTUnwrap(source.resolveImage().get().cgImage)), fixture.bytes,
                           "Failed checkpoint keeps the original native samples")
            XCTAssertEqual(owner.usage.pixelBufferCount, 1)
        }
        try FileManager.default.removeItem(at: blocked)
        let backing = try autoreleasepool {
            let backing = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            XCTAssertTrue(source.releaseResidentPixels())
            return backing
        }
        let valid = try Data(contentsOf: backing.url)
        XCTAssertEqual(owner.usage.pixelBytes, 0)
        for damaged in [Data(valid.dropLast()), Data(valid.enumerated().map { $0.offset == 0 ? $0.element ^ 1 : $0.element })] {
            try damaged.write(to: backing.url, options: .atomic)
            XCTAssertThrowsError(try source.resolveImage().get(), "Length and native-byte digest must reject damaged private payload")
            XCTAssertEqual(owner.usage.chargedBytes, 0, "Failed reads drop every private decode allocation")
        }
        try valid.write(to: backing.url, options: .atomic)
        try autoreleasepool {
            XCTAssertEqual(try nativeSamples(XCTUnwrap(source.resolveImage().get().cgImage)), fixture.bytes)
            XCTAssertTrue(source.releaseResidentPixels())
        }
        XCTAssertEqual(owner.usage.chargedBytes, 0)
    }

    private final class NativeReadProbe {
        weak var owner: RasterResidency?
        let bytes: NativeFixtureBytes
        var capturing = false
        var observedWorking: [Int] = []
        init(owner: RasterResidency, count: Int) {
            self.owner = owner
            bytes = NativeFixtureBytes(Data(repeating: 255, count: count), releases: NativeReleaseCount())
        }
    }
    private func readProbe(_ owner: RasterResidency, providerBytes: Int) throws -> (UIImage, NativeReadProbe) {
        let probe = NativeReadProbe(owner: owner, count: providerBytes)
        let retained = Unmanaged.passRetained(probe)
        var callbacks = CGDataProviderDirectCallbacks(version: 0, getBytePointer: { info in
            guard let info else { return nil }
            let value = Unmanaged<NativeReadProbe>.fromOpaque(info).takeUnretainedValue()
            if value.capturing { value.observedWorking.append(value.owner?.usage.workingBytes ?? 0) }
            return UnsafeRawPointer(value.bytes.pointer)
        }, releaseBytePointer: nil, getBytesAtPosition: nil, releaseInfo: { info in
            if let info { Unmanaged<NativeReadProbe>.fromOpaque(info).release() }
        })
        guard let provider = CGDataProvider(directInfo: retained.toOpaque(), size: Int64(providerBytes), callbacks: &callbacks) else {
            retained.release(); throw NSError(domain: "NativeReadProbe", code: 1)
        }
        let cg = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        probe.observedWorking.removeAll(); probe.capturing = true
        return (UIImage(cgImage: cg), probe)
    }

    func testNativeProviderExtractionIsPreAdmittedAndOversizedProvidersAreHonestlyChargedOrRefused() throws {
        let owner = RasterResidency(budgetBytes: pictureBytes * 10, makeRoom: { _ in true })
        let (image, probe) = try readProbe(owner, providerBytes: pictureBytes * 2)
        try autoreleasepool {
            let source = try RasterSource.capturePlaced(image, using: owner).get()
            XCTAssertFalse(probe.observedWorking.isEmpty, "PREMISE: the actual opaque provider was read")
            XCTAssertTrue(probe.observedWorking.allSatisfy { $0 >= pictureBytes * 2 }, "Header-based input/extraction reservation precedes CopyData")
            XCTAssertEqual(source.logicalPayloadBytes, pictureBytes * 2)
            XCTAssertEqual(owner.usage.pixelBytes, pictureBytes * 2, "Returned provider bytes, including excess ownership, are actually priced")
        }
        XCTAssertEqual(owner.usage.chargedBytes, 0)
        let refused = RasterResidency(budgetBytes: pictureBytes * 2 - 1, makeRoom: { _ in true })
        let (unread, refusedProbe) = try readProbe(refused, providerBytes: pictureBytes)
        XCTAssertThrowsError(try RasterSource.capturePlaced(unread, using: refused).get())
        XCTAssertTrue(refusedProbe.observedWorking.isEmpty, "Insufficient header workspace refuses before forcing opaque data")
        XCTAssertEqual(refused.usage.allocations, 0)
    }

    func testCommonPNGAlphaProofAndCroppedNativePictureUseTheirActualLayouts() throws {
        let owner = RasterResidency(budgetBytes: 4096, makeRoom: { _ in true })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("native-layout-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appendingPathComponent("clear.png")
        try autoreleasepool {
            let clear = try RasterSurface.allocate(width: width, height: height, using: owner).get()
            try XCTUnwrap(ProjectStore.encodeRasterPNG(try clear.image().get())).write(to: png)
        }
        let backing = try ProjectStore.RasterBacking.protect(png, using: owner).get()
        let cold = RasterSource.backed(by: backing, using: owner)
        XCTAssertEqual(owner.usage.pixelBytes, 0, "Protection retains metadata/files, not an owner pixel buffer")
        try autoreleasepool {
            let decoded = try cold.resolveImage().get()
            let fields = try NativeImageFields(XCTUnwrap(decoded.cgImage))
            XCTAssertEqual(fields.bpc, 8); XCTAssertEqual(fields.bpp, 32)
            XCTAssertTrue(cold.isCertainlyTransparent, "Common PNG8 straight/first/row layout keeps its exact transparent-cel proof")
            XCTAssertTrue(cold.releaseResidentPixels())
        }
        let fixture = try nativeFixture(1, releases: NativeReleaseCount())
        let cropped = try XCTUnwrap(fixture.image.cropping(to: CGRect(x: 1, y: 1, width: 2, height: 1)))
        let input = UIImage(cgImage: cropped, scale: 2, orientation: .rightMirrored)
        let actualProviderCount = CFDataGetLength(try XCTUnwrap(cropped.dataProvider?.data))
        let extent = cropped.bytesPerRow * cropped.height
        let result = RasterSource.capturePlaced(input, using: owner)
        if actualProviderCount < extent {
            XCTAssertThrowsError(try result.get(), "Missing declared final-row bytes are explicitly unsupported, never guessed")
        } else {
            let source = try result.get()
            let rect = CGRect(x: 2, y: 2, width: input.size.width * 4, height: input.size.height * 4)
            let expected = try nativeDrawing(input, rect: rect)
            _ = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            XCTAssertTrue(source.releaseResidentPixels())
            XCTAssertEqual(try nativeDrawing(source.resolveImage().get(), rect: rect), expected,
                           "An admitted cropped view preserves its actual drawn pixels, not merely its header")
        }
    }
}


extension RasterResidencyLogicTests {
    func testPlacedImageEditMeasurementUsesColdMetadataWhileActualDrawRefusesTheWholePicture() throws {
        var allowPixels = true
        let owner = RasterResidency(budgetBytes: 4096, makeRoom: { _ in allowPixels })
        let fixture = try nativeFixture(1, releases: NativeReleaseCount())
        let source = try RasterSource.capturePlaced(UIImage(cgImage: fixture.image), using: owner).get()
        try autoreleasepool {
            _ = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            XCTAssertTrue(source.releaseResidentPixels())
        }
        XCTAssertEqual(owner.usage.pixelBytes, 0)
        allowPixels = false
        let original = VectorImageElement(source: source,
            transform: LayerTransform(position: CGPoint(x: 20, y: 20), scale: 1, rotation: 0))
        var replacement = original
        replacement.transform.position.x += 4
        let size = CGSize(width: 64, height: 64)
        let canvas = VectorCanvas(size: size, elements: [.image(original)])
        let allocations = owner.usage.allocations
        let window = canvas.editWindow(replacingWith: [.image(replacement)], rewriting: [original.id])
        XCTAssertEqual(window, CGRect(x: 16, y: 17, width: 12, height: 6),
                       "The old/new placed rectangles determine the bounded edit window with no pixel reads")
        XCTAssertEqual(owner.usage.allocations, allocations)
        XCTAssertEqual(owner.usage.pixelBytes, 0, "Cold source metadata never resolves a picture")
        var drawnWindow: CGRect?
        _ = UIGraphicsImageRenderer(size: window.size, format: PixelOps.transparentFormat()).image { context in
            drawnWindow = canvas.drawEditWindow(of: [.image(replacement)], in: window,
                into: context.cgContext, rewriting: [original.id])
        }
        XCTAssertNil(drawnWindow, "An unavailable picture refuses the entire prepared window")
        let frozen = canvas.freeze(quality: .full)
        var drawn: Int?
        _ = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            drawn = frozen.draw(into: context.cgContext, frameRect: CGRect(origin: .zero, size: size), quality: .full)
        }
        XCTAssertNil(drawn, "A frozen draw cannot publish a picture with the placed source omitted")
        XCTAssertNil(canvas.render(), "The canvas render also discards its whole unavailable picture")
        XCTAssertEqual(owner.usage.allocations, allocations, "Refused drawing leaves no admitted pixel allocation")
        XCTAssertEqual(canvas.elements.map(\.id), [original.id])
    }
}


extension RasterResidencyLogicTests {
    private func grayAlpha8Fixture(painted: Bool) throws -> (image: UIImage, bytes: Data) {
        // Three two-byte pixels and two padding bytes per row. Nonzero luminance and padding
        // cannot be mistaken for alpha; the only painted sample is the middle of the last row.
        let bytes = Data([255, 0, 96, 0, 32, 0, 255, 255,
                          192, 0, 128, painted ? 255 : 0, 64, 0, 255, 255])
        let provider = try NativeFixtureBytes(bytes, releases: NativeReleaseCount()).provider()
        let cg = try XCTUnwrap(CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 16,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        XCTAssertEqual(cg.bitsPerComponent, 8); XCTAssertEqual(cg.bitsPerPixel, 16)
        XCTAssertEqual(cg.bytesPerRow, 8); XCTAssertEqual(cg.alphaInfo, .last)
        XCTAssertEqual(cg.bitmapInfo.rawValue, CGImageAlphaInfo.last.rawValue)
        XCTAssertEqual(cg.colorSpace?.model, .monochrome)
        XCTAssertFalse(cg.isMask); XCTAssertNil(cg.decode)
        return (UIImage(cgImage: cg), bytes)
    }

    func testNativeGrayAlpha8BlankProofIgnoresLuminanceAndPaddingAndKeepsNativeBytes() throws {
        let fixture = try grayAlpha8Fixture(painted: false)
        let drawn = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
            XCTUnwrap(fixture.image.cgImage), width: 3, height: 2))
        XCTAssertTrue(stride(from: 3, to: drawn.count, by: 4).allSatisfy { drawn[$0] == 0 },
                      "PREMISE: the actual explicit monochrome-alpha fixture draws fully transparent")
        let owner = RasterResidency(budgetBytes: 4096, makeRoom: { _ in true })
        let source = try RasterSource.capturePlaced(fixture.image, using: owner).get()
        let before = owner.usage
        var scans = 0
        XCTAssertTrue(try source.prepareTransparencyProof { count in
            scans += 1; XCTAssertEqual(count, 6); return true
        }.get(), "Exact two-byte alpha scan must ignore nonzero color samples and row padding")
        XCTAssertTrue(source.isCertainlyTransparent)
        XCTAssertEqual(scans, 1); XCTAssertEqual(owner.usage, before)
        _ = try source.prepareTransparencyProof { _ in XCTFail("Proof is cached per immutable version"); return false }.get()
        try autoreleasepool {
            XCTAssertEqual(try nativeSamples(XCTUnwrap(source.resolveImage().get().cgImage)), fixture.bytes)
            _ = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            XCTAssertTrue(source.releaseResidentPixels())
        }
        try autoreleasepool {
            let reloaded = try XCTUnwrap(source.resolveImage().get().cgImage)
            XCTAssertEqual(reloaded.bitsPerPixel, 16); XCTAssertEqual(reloaded.colorSpace?.model, .monochrome)
            XCTAssertEqual(try nativeSamples(reloaded), fixture.bytes, "Blank proof cannot normalize native gray-alpha samples")
            XCTAssertTrue(source.isCertainlyTransparent)
        }
    }

    func testNativeGrayAlpha8ProofPreservesOnePaintedSampleAtItsActualPixelStride() throws {
        let fixture = try grayAlpha8Fixture(painted: true)
        let drawn = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(
            XCTUnwrap(fixture.image.cgImage), width: 3, height: 2))
        let painted = stride(from: 3, to: drawn.count, by: 4).filter { drawn[$0] != 0 }
        XCTAssertEqual(painted.count, 1, "PREMISE: the actual native fixture draws exactly one painted sample")
        XCTAssertEqual(drawn[(1 * 3 + 1) * 4 + 3], 255)
        let owner = RasterResidency(budgetBytes: 4096, makeRoom: { _ in true })
        let source = try RasterSource.capturePlaced(fixture.image, using: owner).get()
        var scans = 0
        XCTAssertFalse(try source.prepareTransparencyProof { count in
            scans += 1; XCTAssertEqual(count, 6); return true
        }.get(), "A single alpha sample in the second two-byte pixel must retain the whole picture")
        XCTAssertEqual(scans, 1, "A supported known layout must actually inspect alpha")
        XCTAssertFalse(source.isCertainlyTransparent)
        _ = try source.prepareTransparencyProof { _ in XCTFail("Nonblank proof is cached too"); return false }.get()
        try autoreleasepool {
            let owned = try XCTUnwrap(source.resolveImage().get().cgImage)
            XCTAssertEqual(try nativeSamples(owned), fixture.bytes)
            XCTAssertEqual(try CoreGraphicsCompositor.premultipliedBytes(owned, width: 3, height: 2), drawn)
        }
    }
}


extension RasterResidencyLogicTests {
    private struct NativeCheckpointCase {
        let source: RasterSource
        let backing: ProjectStore.RasterBacking
        let bytes: Data
        let fields: NativeImageFields
        let pointSize: CGSize
        var owner: RasterResidency { source.residency }
    }

    private func nativeCheckpointCase(compressible: Bool) throws -> NativeCheckpointCase {
        let row = 256, width = 64
        let encodingScratch = LZ4Block.encodingScratchBytes
        let decodingScratch = LZ4Block.decodingScratchBytes
        XCTAssertLessThanOrEqual(encodingScratch, 256 * 1024, "PREMISE: finite fixture supports this codec workspace")
        XCTAssertLessThanOrEqual(decodingScratch, 256 * 1024, "PREMISE: finite fixture supports this codec workspace")
        guard encodingScratch <= 256 * 1024, decodingScratch <= 256 * 1024 else {
            throw NSError(domain: "NativeCheckpointFixture", code: 1)
        }
        let height = (max(16 * 1024, encodingScratch) + row - 1) / row
        let count = row * height
        var bytes = Data(count: count)
        bytes.withUnsafeMutableBytes { storage in
            let samples = storage.bindMemory(to: UInt8.self)
            var state: UInt32 = 0x6D2B_79F5
            for index in 0..<samples.count {
                if compressible { samples[index] = [UInt8(64), 128, 192, 255][index % 4] }
                else {
                    state ^= state << 13; state ^= state >> 17; state ^= state << 5
                    samples[index] = UInt8(truncatingIfNeeded: state)
                }
            }
        }
        XCTAssertTrue(LZ4Block.compressesWithinCheckpoint(count), "PREMISE: both payloads enter the real compression attempt")
        let owner = RasterResidency(budgetBytes: max(count * 5, count * 2 + decodingScratch), makeRoom: { _ in true })
        let result = try autoreleasepool {
            let provider = try NativeFixtureBytes(bytes, releases: NativeReleaseCount()).provider()
            let cg = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: row, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .relativeColorimetric))
            let image = UIImage(cgImage: cg, scale: 2, orientation: .leftMirrored)
            let source = try RasterSource.capturePlaced(image, using: owner).get()
            let backing = try ProjectStore.serializingPackageMutation { try source.checkpointForEviction().get() }
            XCTAssertTrue(source.releaseResidentPixels())
            return NativeCheckpointCase(source: source, backing: backing, bytes: bytes,
                fields: try NativeImageFields(cg), pointSize: image.size)
        }
        XCTAssertEqual(owner.usage.chargedBytes, 0)
        return result
    }

    private func nativeCheckpointFileBytes(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? NSNumber).intValue
    }

    private func assertNativeCheckpointReload(_ fixture: NativeCheckpointCase) throws {
        try autoreleasepool {
            let reloaded = try fixture.source.resolveImage().get()
            let cg = try XCTUnwrap(reloaded.cgImage)
            XCTAssertEqual(try NativeImageFields(cg), fixture.fields)
            XCTAssertEqual(try nativeSamples(cg), fixture.bytes)
            XCTAssertEqual(reloaded.size, fixture.pointSize)
            XCTAssertEqual(reloaded.scale, 2); XCTAssertEqual(reloaded.imageOrientation, .leftMirrored)
            XCTAssertTrue(fixture.source.releaseResidentPixels())
        }
        XCTAssertEqual(fixture.owner.usage.chargedBytes, 0)
        XCTAssertEqual(fixture.owner.usage.reservedCheckpointBytes, 0)
        XCTAssertLessThanOrEqual(fixture.owner.usage.highWaterBytes, fixture.owner.budgetBytes)
    }

    func testNativeCheckpointCompressesRepeatedSamplesAndReloadsTheirExactNativeLayout() throws {
        let fixture = try nativeCheckpointCase(compressible: true)
        let fileBytes = try nativeCheckpointFileBytes(fixture.backing.url)
        XCTAssertGreaterThan(fileBytes, 0)
        XCTAssertLessThan(fileBytes, fixture.bytes.count, "Actual headerless checkpoint file proves the compressed branch")
        guard case .native(let rawCount, let storedCount, let compressed, _) = fixture.backing.payload else {
            return XCTFail("A private checkpoint must retain its native payload contract")
        }
        XCTAssertTrue(compressed); XCTAssertEqual(rawCount, fixture.bytes.count); XCTAssertEqual(storedCount, fileBytes)
        try assertNativeCheckpointReload(fixture)
        print("NATIVE_CHECKPOINT compressed raw=\(rawCount) stored=\(fileBytes) encodeScratch=\(LZ4Block.encodingScratchBytes) decodeScratch=\(LZ4Block.decodingScratchBytes)")
    }

    func testNativeCheckpointStoresIncompressibleSamplesRawAndReloadsTheirExactNativeLayout() throws {
        let fixture = try nativeCheckpointCase(compressible: false)
        let fileBytes = try nativeCheckpointFileBytes(fixture.backing.url)
        XCTAssertEqual(fileBytes, fixture.bytes.count, "Actual headerless file proves raw fallback after a real compression attempt")
        XCTAssertEqual(try Data(contentsOf: fixture.backing.url), fixture.bytes)
        guard case .native(let rawCount, let storedCount, let compressed, _) = fixture.backing.payload else {
            return XCTFail("A private checkpoint must retain its native payload contract")
        }
        XCTAssertFalse(compressed); XCTAssertEqual(rawCount, fixture.bytes.count); XCTAssertEqual(storedCount, fileBytes)
        try assertNativeCheckpointReload(fixture)
        print("NATIVE_CHECKPOINT raw raw=\(rawCount) stored=\(fileBytes) encodeScratch=\(LZ4Block.encodingScratchBytes) decodeScratch=\(LZ4Block.decodingScratchBytes)")
    }

    func testNativeCheckpointReadPreadmitsStoredBytesAndScratchAndRefusesOneByteTooTightWithoutLeaks() throws {
        for compressible in [true, false] {
            let fixture = try nativeCheckpointCase(compressible: compressible)
            let fileBytes = try nativeCheckpointFileBytes(fixture.backing.url)
            let expectedWorkspace = fileBytes + (compressible ? LZ4Block.decodingScratchBytes : 0)
            let exactBudget = fixture.bytes.count + expectedWorkspace
            var requests: [(bytes: Int, working: Int, pixels: Int)] = []
            weak var observed: RasterResidency?
            let tight = RasterResidency(budgetBytes: exactBudget - 1, makeRoom: { count in
                let usage = observed?.usage
                requests.append((count, usage?.workingBytes ?? -1, usage?.pixelBytes ?? -1))
                return true
            })
            observed = tight
            let source = RasterSource.backed(by: fixture.backing, using: tight)
            XCTAssertThrowsError(try source.resolveImage().get()) { error in
                XCTAssertEqual(error as? RasterResidency.Failure, .budgetExceeded)
            }
            XCTAssertEqual(requests.map { $0.bytes }, [expectedWorkspace, fixture.bytes.count])
            XCTAssertEqual(requests.map { $0.working }, [0, expectedWorkspace],
                           "The real stored payload and decode scratch are charged before requesting output pixels")
            XCTAssertEqual(requests.map { $0.pixels }, [0, 0])
            XCTAssertEqual(tight.usage.allocations, 0)
            XCTAssertEqual(tight.usage.chargedBytes, 0, "A refused read releases its preadmitted workspace")
            XCTAssertEqual(tight.usage.reservedCheckpointBytes, 0)
            XCTAssertEqual(tight.usage.highWaterBytes, expectedWorkspace)
            let exact = RasterResidency(budgetBytes: exactBudget, makeRoom: { _ in true })
            let admitted = RasterSource.backed(by: fixture.backing, using: exact)
            try autoreleasepool {
                let image = try admitted.resolveImage().get()
                let cg = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(try nativeSamples(cg), fixture.bytes)
                XCTAssertEqual(try NativeImageFields(cg), fixture.fields)
                XCTAssertTrue(admitted.releaseResidentPixels())
            }
            XCTAssertEqual(exact.usage.highWaterBytes, exactBudget, "Exactly the declared workspace plus output is sufficient")
            XCTAssertEqual(exact.usage.chargedBytes, 0)
            XCTAssertEqual(fixture.owner.usage.chargedBytes, 0)
        }
    }

    // MARK: - Thumbnails are made at thumbnail size

    /// The Nov 16 audit's item 7: a raster cel's thumbnail used to be a canvas-sized decode that the
    /// source then kept (`self.image`), charged against the residency, drawn down afterwards. What is
    /// asserted is the residency's own charge — a thumbnail of a cel that is only a file must leave
    /// nothing canvas-sized resident — and the thumbnail's own backing bytes.
    private func thumbnailFixture(_ owner: RasterResidency) throws -> (texture: RasterLayerTexture, size: CGSize) {
        let size = CGSize(width: 512, height: 256)
        let texture = try RasterLayerTexture.rendered(size: size, using: owner) { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            return true
        }.get()
        return (texture, size)
    }

    private func assertSmallRed(_ image: UIImage?, file: StaticString = #filePath, line: UInt = #line) throws {
        let cg = try XCTUnwrap(image?.cgImage, file: file, line: line)
        XCTAssertEqual(cg.width, 64, file: file, line: line)
        XCTAssertEqual(cg.height, 32, file: file, line: line)
        XCTAssertLessThanOrEqual(cg.bytesPerRow * cg.height, 64 * 32 * 4 + 4096,
                                 "the thumbnail's own backing bytes are thumbnail-sized", file: file, line: line)
        let bytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(cg, width: 64, height: 32))
        XCTAssertEqual(Array(bytes.prefix(4)), [255, 0, 0, 255], file: file, line: line)
    }

    func testThumbnailOfANativeBackedCelLeavesNothingCanvasSizedResident() throws {
        let canvas = 512 * 256 * 4
        let owner = RasterResidency(budgetBytes: canvas * 8, makeRoom: { _ in true })
        let (texture, size) = try thumbnailFixture(owner)
        XCTAssertTrue(ProjectStore.serializingPackageMutation { texture.releaseResidentPixels() })
        XCTAssertEqual(owner.usage.pixelBytes, 0, "PREMISE: the cel is now only a native file")
        let thumbnail = ThumbnailRenderer.render(texture, canvasSize: size, thumbnailSize: CGSize(width: 64, height: 64))
        try assertSmallRed(thumbnail)
        XCTAssertEqual(owner.usage.pixelBytes, 0,
                       "a thumbnail must not leave a canvas-sized decode resident on the cel")
    }

    func testThumbnailOfAPNGBackedCelDecodesNothingAtCanvasSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raster-thumb-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let size = CGSize(width: 512, height: 256)
        let url = root.appendingPathComponent("cel.png")
        try XCTUnwrap(CanvasFixture.solidImage(.red, rect: CGRect(origin: .zero, size: size), size: size).pngData()).write(to: url)
        let owner = RasterResidency(budgetBytes: 512 * 256 * 4 * 8, makeRoom: { _ in true })
        let source = RasterSource.backed(by: try ProjectStore.RasterBacking.protect(url, using: owner).get(), using: owner)
        // Unproven blankness: one transient decode, because that is what proves (and heals) a legacy
        // package's transparent PNG. It is not kept.
        _ = try source.thumbnailImage(size: CGSize(width: 64, height: 32), format: PixelOps.transparentFormat()).get()
        XCTAssertFalse(source.isCertainlyTransparent)
        XCTAssertEqual(owner.usage.allocations, 1, "PREMISE: the first thumbnail of an unproven file decodes it once")
        XCTAssertEqual(owner.usage.pixelBytes, 0, "…and that decode is not kept")
        let before = owner.usage
        let thumbnail = try source.thumbnailImage(size: CGSize(width: 64, height: 32),
                                                  format: PixelOps.transparentFormat()).get()
        try assertSmallRed(thumbnail)
        XCTAssertEqual(owner.usage.allocations, before.allocations,
                       "ImageIO downsamples from the file; no pixel buffer is admitted")
        XCTAssertEqual(owner.usage.pixelBytes, 0)
        XCTAssertEqual(owner.usage.highWaterBytes, before.highWaterBytes)
    }
}

extension CanvasManager {
    /// Runs `body` on the fill lane, as the gesture's own work does, and returns what it answers —
    /// the thread the fill reference's factory is made for.
    func onFillLane<T>(_ body: @escaping () throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<T, Error>?
        fillWork {
            outcome = Result { try body() }
            done.signal()
        }
        done.wait()
        return try outcome!.get()
    }
}
