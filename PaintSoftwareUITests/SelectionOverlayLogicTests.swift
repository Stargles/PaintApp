import XCTest
import UIKit

/// Pure-logic coverage for the pencil-only-mode fix to `SelectionOverlayView`'s lasso/rectangle/
/// automatic-selection gestures (the third hole `CanvasView`'s gesture doc comment references —
/// after `fillPress` and `catchAll`). The touch-routing itself needs a live `UITouch`, which nothing
/// outside UIKit can construct (see `StrokePathFitLogicTests`'s doc comment for the same limit),
/// so this exercises the one piece of that fix which *is* plain logic:
/// `resolvedLastTouchType(from:)`, the pencil-wins tie-break `TouchTypePanGestureRecognizer` and
/// `TouchTypeTapGestureRecognizer` use in `touchesBegan` to decide whether a gesture sequence counts
/// as a pencil touch. The end-to-end behavior — a one-finger lasso drag doing nothing while pencil-
/// only mode is on — is covered by `SelectionPencilOnlyUITests` instead.
///
/// No `@testable import PaintSoftware`: `resolvedLastTouchType` lives in
/// `PaintSoftware/Utilities/TouchTypeResolution.swift`, which — like `StrokeGeometry.swift` and
/// `VectorEraser.swift` — is compiled a second time directly into this target (see the project
/// file's "App sources shared with PaintSoftwareUITests" group) rather than imported, because a
/// `bundle.ui-testing` product type-checks against `@testable import` but does not link against the
/// app binary — see `BrushEngineLogicTests`'s doc comment.
final class SelectionOverlayLogicTests: XCTestCase {

    func testEmptySequenceResolvesToNil() {
        XCTAssertNil(resolvedLastTouchType(from: [UITouch.TouchType]()))
    }

    func testSingleFingerTouchResolvesToDirect() {
        XCTAssertEqual(resolvedLastTouchType(from: [.direct]), .direct)
    }

    func testSinglePencilTouchResolvesToPencil() {
        XCTAssertEqual(resolvedLastTouchType(from: [.pencil]), .pencil)
    }

    func testPencilAmongFingersWinsRegardlessOfOrder() {
        // `Set<UITouch>` iterates in no defined order, so the tie-break has to hold whichever
        // position the pencil lands at — an artist's off-hand resting on the glass alongside the
        // pencil must not flip `lastTouchType` to `.direct`.
        XCTAssertEqual(resolvedLastTouchType(from: [.direct, .pencil]), .pencil)
        XCTAssertEqual(resolvedLastTouchType(from: [.pencil, .direct]), .pencil)
        XCTAssertEqual(resolvedLastTouchType(from: [.direct, .direct, .pencil, .direct]), .pencil)
    }

    func testAllFingersWithNoPencilResolvesToDirect() {
        XCTAssertEqual(resolvedLastTouchType(from: [.direct, .direct, .direct]), .direct)
    }

    /// Mirrors the actual call site in `TouchTypePanGestureRecognizer.touchesBegan`/
    /// `TouchTypeTapGestureRecognizer.touchesBegan`: `if let type = resolvedLastTouchType(...) {
    /// lastTouchType = type }` — an empty result must leave a prior value alone rather than
    /// resetting it, matching `TouchTypePressRecognizer`'s same "only overwrite on non-empty" rule.
    func testResolvedNilLeavesAPriorValueUntouchedAtTheCallSite() {
        var lastTouchType: UITouch.TouchType = .pencil
        if let type = resolvedLastTouchType(from: [UITouch.TouchType]()) {
            lastTouchType = type
        }
        XCTAssertEqual(lastTouchType, .pencil)
    }

    // MARK: - Gating guard, mirrored from `handlePan`/`handleTap`

    /// The exact boolean `guard !pencilOnlyDrawing || recognizer.lastTouchType == .pencil else {
    /// return }` uses in `SelectionOverlayView.handlePan`/`handleTap`, pulled out so its four
    /// combinations are pinned independently of the view/recognizer plumbing around it.
    private func admits(pencilOnlyDrawing: Bool, lastTouchType: UITouch.TouchType) -> Bool {
        !pencilOnlyDrawing || lastTouchType == .pencil
    }

    func testPencilOnlyModeRejectsAFingerDrivenSelectionGesture() {
        XCTAssertFalse(admits(pencilOnlyDrawing: true, lastTouchType: .direct),
                       "this is the reported bug: a finger must not be able to start a lasso/rectangle/automatic selection")
    }

    func testPencilOnlyModeAdmitsAPencilDrivenSelectionGesture() {
        XCTAssertTrue(admits(pencilOnlyDrawing: true, lastTouchType: .pencil))
    }

    func testFingerIsAdmittedWhenPencilOnlyModeIsOff() {
        XCTAssertTrue(admits(pencilOnlyDrawing: false, lastTouchType: .direct))
        XCTAssertTrue(admits(pencilOnlyDrawing: false, lastTouchType: .pencil))
    }
}
