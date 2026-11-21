import XCTest
import UIKit

/// **A move, warp or transform the memory budget declines must be said, not swallowed** —
/// AUDIT-2026-11-16 §2. `ImageWarp.rasterImage` refuses when `CompositorBudget.hasHeadroom` declines
/// (and `forEachRasterPlan` when even one texel is over the allowance), and every caller
/// (`PixelOps.posed`, `drawPosedRaster`, the floating-piece raster) answers nil, which the artist saw
/// as a tap that did nothing. The refusal now raises `MemoryPressure.Level.workRefused`, which
/// `CanvasManager` turns into `CanvasNotice.Kind.workNeedsMoreMemory`.
///
/// The seam is `MemoryBudget.shared.availableOverrideBytes` (the valve's reading, imposed): on the
/// simulator the real reading is 0 and the valve is inert.
final class WorkRefusalNoticeLogicTests: XCTestCase {

    override func tearDown() {
        MemoryBudget.shared.availableOverrideBytes = nil
        super.tearDown()
    }

    private func solid(_ side: Int) -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: PixelOps.transparentFormat())
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }.cgImage!
    }

    @MainActor
    private func settle() {
        let settled = expectation(description: "the responder's hop to main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }

    private func plan(side: Int) throws -> ImageWarp.RasterPlan {
        try XCTUnwrap(ImageWarp.RasterPlan(sourceSize: CGSize(width: side, height: side),
            destination: CGRect(x: 0, y: 0, width: side, height: side),
            inverseTexelMap: Homography(CGAffineTransform.identity)))
    }

    /// Family 1: the headroom valve declines a warp.
    @MainActor
    func testAWarpTheValveDeclinesRaisesTheNotice() throws {
        let manager = CanvasFixture.manager(layerCount: 1)   // registers the notice's responder
        let image = solid(64)
        let plan = try plan(side: 64)
        MemoryBudget.shared.availableOverrideBytes = 1

        manager.notice = nil
        XCTAssertNil(ImageWarp.rasterImage(plan: plan, source: { image.cropping(to: $0) }),
                     "a declined warp makes no picture")
        settle()
        XCTAssertEqual(manager.notice?.code, "workNeedsMoreMemory",
                       "the declined action is said — got \(manager.notice?.code ?? "nothing")")
        XCTAssertTrue(manager.notice?.message.contains("Not enough memory") == true)
        withExtendedLifetime(manager) {}
    }

    /// The control: the same warp with room says nothing.
    @MainActor
    func testAWarpWithRoomRaisesNoNotice() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let image = solid(64)
        let plan = try plan(side: 64)
        MemoryBudget.shared.availableOverrideBytes = Int.max / 4

        manager.notice = nil
        _ = ImageWarp.rasterImage(plan: plan, source: { image.cropping(to: $0) })
        settle()
        XCTAssertNil(manager.notice, "room to work is not news — got \(manager.notice?.code ?? "nothing")")
        withExtendedLifetime(manager) {}
    }

    /// Family 2: a window split down to one texel and still over the allowance.
    @MainActor
    func testAWindowThatCannotBeSplitSmallEnoughRaisesTheNotice() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let image = solid(16)
        manager.notice = nil
        let drawn = ImageWarp.drawRaster(sourceSize: CGSize(width: 16, height: 16),
            destination: CGRect(x: 0, y: 0, width: 16, height: 16),
            inverseTexelMap: Homography(CGAffineTransform.identity), maximumWorkingBytes: 1,
            source: { image.cropping(to: $0) }, consume: { _, _ in })
        XCTAssertFalse(drawn)
        settle()
        XCTAssertEqual(manager.notice?.code, "workNeedsMoreMemory",
                       "got \(manager.notice?.code ?? "nothing")")
        withExtendedLifetime(manager) {}
    }

    /// Family 3, end to end: the shown picture a lasso Move needs from a posed cel
    /// (`SelectionModels` `PixelOps.rasterize(cel:pose:)`, whose caller just returns on nil) is
    /// declined by the valve and the artist is told; undo history is not trimmed for it.
    @MainActor
    func testAPosedCelPictureTheValveDeclinesIsSaidAndKeepsUndo() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
            CanvasFixture.solidImage(.red, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        let cel = manager.layers[0].cels[0]
        let size = CanvasFixture.canvasSize
        let pose = PoseMap(CGAffineTransform(translationX: 7, y: 3).rotated(by: 0.2))
        XCTAssertNotNil(PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false, pose: pose),
                        "control: with room the posed picture exists")
        MemoryBudget.shared.availableOverrideBytes = 1
        let undoBefore = manager.history.undoStack.count

        manager.notice = nil
        XCTAssertNil(PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false, pose: pose),
                     "the declined pose draws nothing")
        settle()
        XCTAssertEqual(manager.notice?.code, "workNeedsMoreMemory",
                       "got \(manager.notice?.code ?? "nothing")")
        XCTAssertEqual(manager.history.undoStack.count, undoBefore, "a refusal does not cost undo steps")
        withExtendedLifetime(manager) {}
    }
}
