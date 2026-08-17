import XCTest

/// `Tool` as a closed set of answers, and the one answer that matters outside the enum itself:
/// whether a canvas touch made with a tool selected belongs to the active layer's drawing surface.
///
/// **This file is the regression guard for a bug of omission, so it is written to fail on omission.**
/// The owner reported on 2026-08-17 that the newly-shipped eyedropper picked the colour under the tap
/// *and* painted a brush stroke with the same touch. Nothing about the eyedropper was wrong — the
/// pick was correct, including under canvas rotation. What was wrong lived in `CanvasView`'s
/// `shouldInteract`, which decided whether the active layer's host view accepts touches at all and
/// spelled its tool clause as a hand-maintained exclusion, `selectedTool != .fill`. A new
/// non-drawing tool was added to the enum; the exclusion list did not grow to match; the host stayed
/// interactive, so the touch reached the layer's `StrokeGestureRecognizer` as well as the
/// eyedropper's own recognizer, and did both things at once.
///
/// The fix moves the question onto `Tool.paintsOnCanvas`, an exhaustive `switch` with no `default:`,
/// so a tool added later cannot compile without answering. That closes the *implementation* half.
/// This file closes the other half: the compiler will accept any answer, and a new tool quietly
/// answered `true` is the same bug again. `testEveryToolStatesWhetherItPaintsOnTheCanvas` walks
/// `Tool.allCases` against a table written here by hand, so a case added without an entry fails
/// rather than defaults.
///
/// Headless and instant — `Tool` is a plain enum over no dependencies, which is exactly why the
/// answer belongs on it rather than inside a SwiftUI coordinator where nothing can reach it.
final class ToolLogicTests: XCTestCase {

    /// Every case's answer, stated once, here.
    ///
    /// Adding a case to `Tool` without adding it below fails the count assertion, and the message is
    /// addressed to whoever is reading it in that moment: decide which side the new tool is on, and
    /// say so in both places.
    private let expectedPaintsOnCanvas: [Tool: Bool] = [
        // The two brushes and the eraser draw through `StrokeCanvasView.strokeRecognizer`, which
        // lives inside the layer host. The host must accept touches or there is no stroke.
        .pen: true,
        .pencil: true,
        // The eraser is a stroke like any other — `.destinationOut` on a raster layer, a real
        // gesture on a vector one — and goes through the same recognizer.
        .eraser: true,
        // The fill and the eyedropper act on a canvas touch too, but through their own
        // `TouchTypePressRecognizer` mounted on the *container*. The layer host declining the touch
        // is a precondition for either of theirs ever seeing it: the host fully covers the
        // container, so an interactive one swallows the touch at hit-test time.
        .fill: false,
        .eyedropper: false,
    ]

    func testEveryToolStatesWhetherItPaintsOnTheCanvas() {
        XCTAssertEqual(Tool.allCases.count, expectedPaintsOnCanvas.count, """
            A case has been added to `Tool` without an entry in `expectedPaintsOnCanvas`. \
            Decide whether a canvas touch with the new tool selected belongs to the active layer's \
            drawing surface (`true`) or to a recognizer of its own on the container (`false`), then \
            say so in `Tool.paintsOnCanvas` and in the table above. Defaulting to `true` is how the \
            eyedropper shipped painting a stroke with every pick.
            """)

        for tool in Tool.allCases {
            guard let expected = expectedPaintsOnCanvas[tool] else {
                XCTFail("\(tool) has no stated answer — see the message on the count assertion")
                continue
            }
            XCTAssertEqual(tool.paintsOnCanvas, expected,
                           "\(tool).paintsOnCanvas must be \(expected)")
        }
    }

    /// The owner's bug, named. Redundant against the sweep above by design: the sweep says the table
    /// is complete, and this says what the table has to contain for the reported defect to stay
    /// fixed, so a future edit that rewrites the table cannot quietly take this with it.
    func testTheEyedropperDoesNotPaintOnTheCanvas() {
        XCTAssertFalse(Tool.eyedropper.paintsOnCanvas,
                       "A tap with the eyedropper picks a colour; it must not also start a stroke")
        XCTAssertFalse(Tool.fill.paintsOnCanvas,
                       "The fill's exclusion is the one the eyedropper was missing the twin of")
    }

    /// …and the other direction, which is the assertion that stops the fix being "return false".
    /// A predicate that excluded everything would pass the two tests above and leave the app unable
    /// to draw at all.
    func testTheStrokeToolsStillPaint() {
        XCTAssertTrue(Tool.pen.paintsOnCanvas)
        XCTAssertTrue(Tool.pencil.paintsOnCanvas)
        XCTAssertTrue(Tool.eraser.paintsOnCanvas,
                      "Erasing is a stroke — same recognizer, same host, opposite blend")
        XCTAssertTrue(Tool.allCases.contains(where: { $0.paintsOnCanvas }),
                      "At least one tool has to reach the layer host or nothing can be drawn")
    }
}
