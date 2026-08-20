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
///
/// **The second half of the file is `Tool.text`'s entry, for the same reason the first half exists.**
/// Text is entered from a menu row rather than a toolbar icon, and both rules that entry obeys are
/// rules of omission — a commit that is deliberately not made, and a list of layer kinds that is
/// deliberately not written. Omission is the failure mode this file was created for, so it is where
/// the two belong rather than in a file of their own.
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
        // Text is on the fill's side, and the smart shapes are why that needs saying. A shape *is* a
        // brush stroke — it comes out of holding a pen/pencil stroke still — so it reaches the layer
        // host like any stroke. Text's touch never becomes a stroke: it places a box for an overlay
        // that lives above the layers, so the host must decline it or the same touch paints a stroke
        // *and* opens a text box, which is the eyedropper's bug wearing a different name.
        .text: false,
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

    /// The same named-defect test the eyedropper got, for the tool added after it. The sweep says the
    /// table is complete; this says what the table has to contain, so an edit that rewrites the table
    /// cannot take the decision with it.
    ///
    /// The smart shapes are why `false` is worth pinning rather than obvious. A shape is not a tool
    /// at all — it comes out of holding a `.pen`/`.pencil` stroke still, so its touch reaches the
    /// layer host because it genuinely *is* a stroke. Text's touch places a box for an overlay that
    /// lives above the layers, so if the host stayed interactive the one touch would paint a stroke
    /// and open a text box together: the eyedropper's report, verbatim, with a different tool in it.
    func testTextDoesNotPaintOnTheCanvas() {
        XCTAssertFalse(Tool.text.paintsOnCanvas,
                       "A canvas touch in text mode places a text box; it must not also start a stroke")
    }

    // MARK: - Entering the mode
    //
    // `Tool.text` is the first tool whose way in is a menu row rather than a toolbar icon, so the two
    // rules that entry has to obey have nowhere else to be checked. Both are rules of *omission* —
    // one thing not committed, one list not written — which is the class of change that ships green.

    /// **Entering text mode must not bake still-adjustable content**, which is a rule about a call
    /// that is *absent* from `CanvasManager.enterTextMode`. Nothing about the app looks different
    /// when somebody adds it back, and every symptom appears a stage later as text that freezes the
    /// moment its own panel opens — so the absence is asserted here rather than trusted.
    ///
    /// A floating Move piece is the pending state used because it is the one `commitAllInteractiveState`
    /// settles and `beginCanvasEdit` deliberately does not, and because it is observable from a plain
    /// `@Published` property with no rasterization to inspect.
    func testEnteringTextModeDoesNotBakePendingInteractiveState() {
        let manager = CanvasFixture.manager()
        manager.beginMove()
        XCTAssertNotNil(manager.floatingPiece,
                        "fixture precondition: Move has to actually be engaged for this to measure anything")

        manager.enterTextMode()

        XCTAssertEqual(manager.selectedTool, .text, "the row's whole job is entering the mode")
        XCTAssertNotNil(manager.floatingPiece, """
            Entering text mode committed pending interactive state. It must not: the text panel is a \
            settings panel, and `Binding<ActivePanel>.toggleSettingsPanel` bakes nothing for the same \
            reason the fill's panel does not — a panel whose controls exist to re-run the thing in \
            front of you is a panel of no-ops if opening it freezes that thing.
            """)
    }

    /// …and the assertion that stops the test above passing because nothing was ever pending. Without
    /// it, a `floatingPiece` that had failed to engage, or a field that no commit clears, would read
    /// as a green "did not bake" — a green sweep proves its two operands are equal, not that they are
    /// the two things claimed.
    func testTheBakeThisMeasuresIsRealWhenSomethingActuallyAsksForIt() {
        let manager = CanvasFixture.manager()
        manager.beginMove()
        XCTAssertNotNil(manager.floatingPiece)

        manager.commitAllInteractiveState()

        XCTAssertNil(manager.floatingPiece,
                     "`commitAllInteractiveState` settles a floating piece — if it did not, the test above measures nothing")
    }

    /// **"Add Text" is offered or refused by asking the layer what kind it is**, not by a list of
    /// kinds someone remembered to write. That is the same defect shape `paintsOnCanvas` exists for,
    /// one level up: any later `LayerKind` must state its own answer rather than inherit "text is
    /// fine here".
    ///
    /// Driven through a real `CanvasManager` rather than by calling the predicate with three
    /// literals, because "keyed off the *active layer's* kind" is the half a literal cannot show:
    /// what moves the answer here is selecting a different layer and nothing else.
    func testAddTextIsOfferedByActiveLayerKindRatherThanByAList() {
        let manager = CanvasFixture.manager()          // one raster layer, and it is active
        XCTAssertEqual(manager.activeLayerKind, .raster)
        XCTAssertNil(Tool.textUnavailableReason(onLayerOfKind: manager.activeLayerKind),
                     "Raster is where text bakes to pixels")

        manager.addVectorLayer()
        XCTAssertEqual(manager.activeLayerKind, .vector, "fixture precondition: the new layer is active")
        XCTAssertNil(Tool.textUnavailableReason(onLayerOfKind: manager.activeLayerKind), """
            `ADD_TEXT.md` stage 3 turned this arm on, and deleting the "not available yet" string was \
            the whole of that stage's UI change — stage 1 shipped nothing it would have to un-ship, \
            and this is the un-shipping it planned for. On a vector layer text stays a real, \
            re-editable element instead of baking.
            """)

        manager.addValueLayer()
        XCTAssertEqual(manager.activeLayerKind, .value)
        XCTAssertNotNil(Tool.textUnavailableReason(onLayerOfKind: manager.activeLayerKind),
                        "A value layer holds no pixels for the bake to land in")

        // No layer at all — `activeLayerKind` is nil here legitimately, mid-`deleteLayer` as well as
        // on an empty document, and a nil that fell through to "available" would offer a row with
        // nowhere to put its result.
        XCTAssertNotNil(Tool.textUnavailableReason(onLayerOfKind: nil),
                        "With no active layer there is nothing to add text to")
    }

    /// The reasons are shown to the artist under a row they cannot tap, so they have to be sentences
    /// rather than nil-vs-non-nil. Pinned because a disabled control with an empty explanation is
    /// indistinguishable from a broken one.
    ///
    /// `.vector` left this list at stage 3, when the row stopped being disabled there. The two that
    /// remain are not "yet"s: a value layer holds no pixels for text to mean anything against, and
    /// with no layer selected there is nothing to add text to.
    func testEveryUnavailableReasonSaysSomething() {
        for kind: LayerKind? in [.value, nil] {
            let reason = Tool.textUnavailableReason(onLayerOfKind: kind)
            XCTAssertFalse(reason?.isEmpty ?? true,
                           "\(String(describing: kind)) is unavailable and must say why")
        }
    }
}
