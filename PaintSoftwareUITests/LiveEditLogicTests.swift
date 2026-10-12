import XCTest
import SwiftUI
import UIKit

/// **One held slot for every live control** — `CanvasManager.liveEdit`, TODO (179).
///
/// The slot holds one gesture's value at a time. That is true by construction for the holds that live
/// under a finger, and made true for the two that outlive one — the adjustable fill and the open
/// gradient panel — where a gesture that holds a pose begins: they are settled there, which is what
/// that gesture's own write used to do to them at its lift.
final class LiveEditLogicTests: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    /// A 64² document whose second layer has an adjustable fill tapped into the black box on the
    /// first — the fill's picture held, nothing written.
    private func adjustableFill() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            for rect in [CGRect(x: 10, y: 10, width: 44, height: 3), CGRect(x: 10, y: 51, width: 44, height: 3),
                         CGRect(x: 10, y: 10, width: 3, height: 44), CGRect(x: 51, y: 10, width: 3, height: 44)] {
                ctx.fill(rect)
            }
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        manager.addLayer()
        manager.brushColor = Self.red
        manager.beginInteractiveFill(at: CGPoint(x: 30, y: 30))
        manager.endInteractiveFill()
        let done = expectation(description: "the render's hop to main has run")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done.fulfill() }
        wait(for: [done], timeout: 5)
        return manager
    }

    /// **A pose drag begun while a fill is adjustable lands the fill first**, as its own step, before
    /// the pose takes the slot — the fill's picture is never silently replaced by the pose's.
    @MainActor
    func testAPoseGestureBegunWhileAFillIsAdjustableLandsTheFillFirst() throws {
        let manager = adjustableFill()
        XCTAssertNotNil(manager.liveFill?.preview, "Fixture check: the fill is held")
        let steps = manager.history.undoStack.count

        manager.beginLiveTransformEdit(.container(layerID: manager.layers[0].id))

        XCTAssertNil(manager.liveEdit, "the fill's hold is over")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "it landed as its own step")
        manager.endLiveTransformEdit()
    }

    /// **A pose let go leaves a hold of another kind alone** — the two ends a pose has that are not its
    /// commit (`holdLivePose(nil)`, the finger back where it began; `endLiveTransformEdit`) take only a
    /// pose out of the slot.
    @MainActor
    func testLettingAPoseGoLeavesAHoldOfAnotherKindAlone() throws {
        let manager = adjustableFill()
        let held = try XCTUnwrap(manager.liveFill)
        var told = 0
        manager.onHeldPictureMoved = { told += 1 }

        manager.holdLivePose(nil)
        XCTAssertEqual(manager.liveFill?.layerID, held.layerID, "a nil pose tick is not the fill's end")
        XCTAssertEqual(told, 1, "and the canvas is still told, as it was for a pose")
        XCTAssertNil(manager.takeLivePose(), "there was no pose to take")
        XCTAssertNotNil(manager.liveFill, "and taking none took nothing")
    }

    /// **Every kind names the host it draws on, and a pose names none** — what keeps that host drawing
    /// whichever layer is active (`heldHostLayerIndices`).
    @MainActor
    func testTheHeldHostIsTheHoldsOwnLayerAndAPoseHasNone() throws {
        let manager = adjustableFill()
        XCTAssertEqual(manager.heldHostLayerIndices, [1])
        let pose = LivePose(layerID: manager.layers[0].id,
                            holding: LayerPose(pose: PoseQuad(restingIn: CGRect(origin: .zero, size: CanvasFixture.canvasSize))))
        manager.holdLiveEdit(.pose(pose))
        XCTAssertEqual(manager.heldHostLayerIndices, [], "a pose draws through the composite, not a host")
        XCTAssertNotNil(manager.livePose)
        XCTAssertNil(manager.liveFill, "one slot: the pose replaced the fill's picture")
    }
}
