import XCTest

/// Three tests around one symptom: the canvas stops panning / pinching / rotating, and stays stopped
/// until the project is closed and reopened.
///
/// The owner isolated the trigger by hand: **a stroke that begins while the timeline's empty-slot
/// popover is still open.** Tap an empty cel slot until its "Add Drawing" / "Paste" menu raises
/// (one tap selects it, a second tap on the now-selected slot opens the menu — see CHANGE 1 of the
/// owner's later "add drawing" pass), do not touch the menu, and draw straight through it — the
/// canvas is dead afterwards. Dismiss the menu first and draw, and it is fine. Everything the
/// original report carried around that (two layers, two-frame blocks, a layer switch) is scenery:
/// the layer switch was performed by tapping a cel slot, which is what raises the popover.
///
/// So `testCanvasFreezesWhenAStrokeBeginsWhileTheSlotPopoverIsOpen` is the bug and
/// `testCanvasStillTransformsWhenTheSlotPopoverIsDismissedFirst` is the control that must keep
/// passing. Neither means anything alone — the pair is what pins the trigger on the popover rather
/// than on drawing, on the empty frame, or on the timeline tap.
///
/// **Never press "Add Drawing".** The block has to be spawned by the stroke itself
/// (`CanvasView.Coordinator.attachSpawnedCelIfFrameIsEmpty`); creating it from the menu would make
/// the stroke an ordinary one and test nothing.
///
/// **Why it reads an accessibility label.** XCUITest can read neither a `UIGestureRecognizer`'s
/// state nor a view's `transform`, so `CanvasView.Coordinator.publishCanvasState` publishes the
/// canvas's effective scale/rotation/offset on `canvas.host`'s label — the trick
/// `SandwichPresentation` already documents there, and it shares the label with it.
///
/// **Why a pinch and not a pan.** XCUITest has no two-finger drag primitive; `pinch` and `rotate`
/// are the only real multi-touch gestures it synthesises. Pinch is enough: all three transform
/// recognizers carry the identical failure dependency from
/// `Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)`, so a pinch that cannot start is a
/// pan that cannot start. (Measured: `pinch` delivers both touches in a *single* `touchesBegan` with
/// `touches.count == 2`, so it takes `StrokeGestureRecognizer`'s legal `.possible → .failed` guard
/// and never reaches `failTrackedStroke`. No test here reaches that function — see its doc comment.)
///
/// Its own class because xcodebuild distributes parallel work per test *class* (see CLAUDE.md).
final class CanvasTransformFreezeUITests: PaintUITestCase {

    /// The timeline lays a frame out this wide (`TimelineTrackView.Coordinator.pixelsPerFrame`) and
    /// insets each block 2pt inside its slot (`TimelineRowView.update(cels:displayedFrameCount:)`).
    /// Both are needed to point at a slot that holds no block and therefore has no element.
    private let pixelsPerFrame: CGFloat = 30
    private let blockInset: CGFloat = 2

    // MARK: - The bug, and its control

    /// THE BUG. Tap an empty cel slot, leave the menu it raises alone, and draw straight through it.
    func testCanvasFreezesWhenAStrokeBeginsWhileTheSlotPopoverIsOpen() throws {
        let app = XCUIApplication()
        let canvas = try launchWithAnEmptySlot(app)

        assertPinchMovesCanvas(app, canvas, "Setup: the canvas pinches before any of this")

        let slot = try emptySlotCoordinate(app)
        // Two taps, not one: the empty slot's menu is gated the same way a block's is (tap once to
        // select the frame, tap the now-selected frame again to open its menu) since CHANGE 1 of the
        // owner's "add drawing" pass — a single tap used to raise it directly, which was the other
        // half of that same report ("shows up just when I click on an empty cel"). The bug this test
        // pins is about the *popover*, not about how many taps raise it, so the fixture just needs to
        // land on the new contract.
        slot.tap()
        slot.tap()
        XCTAssertTrue(app.buttons["Add Drawing"].waitForExistence(timeout: 5),
                      "PREMISE: a second tap on the already-selected empty slot has to raise the slot menu")

        // Straight into the stroke, with the menu still up and untouched. This one touch both
        // dismisses the popover and starts the stroke, which is the whole trigger.
        drawShortStroke(on: canvas)

        // Diagnostics, not assertions: which of the popover's pieces are still in the hierarchy
        // afterwards is what separates "the stroke recognizer is stranded" from "the presentation
        // is still installed and eating touches".
        NSLog("FREEZEDIAG TEST after-stroke: addDrawing=\(app.buttons["Add Drawing"].exists) "
              + "dismissRegion=\(app.otherElements["PopoverDismissRegion"].exists) "
              + "canvasHittable=\(canvas.isHittable) popovers=\(app.descendants(matching: .popover).count)")

        assertPinchMovesCanvas(app, canvas,
                               "THE BUG: the canvas stopped transforming after a stroke that began while the slot popover was open")
    }

    /// THE CONTROL. Identical, except the menu is dismissed before the stroke. Must keep passing —
    /// if this one ever fails, the trigger is not the popover and the test above is measuring
    /// something else.
    func testCanvasStillTransformsWhenTheSlotPopoverIsDismissedFirst() throws {
        let app = XCUIApplication()
        let canvas = try launchWithAnEmptySlot(app)

        assertPinchMovesCanvas(app, canvas, "Setup: the canvas pinches before any of this")

        let slot = try emptySlotCoordinate(app)
        // See the matching comment in the test above: two taps to open the slot menu, not one.
        slot.tap()
        slot.tap()
        let addDrawing = app.buttons["Add Drawing"]
        XCTAssertTrue(addDrawing.waitForExistence(timeout: 5),
                      "PREMISE: a second tap on the already-selected empty slot has to raise the slot menu")
        dismissPopover(app)
        XCTAssertFalse(addDrawing.exists, "PREMISE: the menu has to be closed before this stroke")

        drawShortStroke(on: canvas)

        assertPinchMovesCanvas(app, canvas,
                               "The canvas should still transform after a stroke drawn with no popover open")
    }

    /// The second instance the owner reported, reached with no popover and no timeline at all: with
    /// the Fill tool selected, `reconcileLayers` disables the active layer's host (`shouldInteract`)
    /// while `shouldRequireFailureOf` goes on naming that host's stroke recognizer.
    func testCanvasStillTransformsWithTheFillToolSelected() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        assertPinchMovesCanvas(app, canvas, "Setup: the canvas should pinch before any tool switch")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // First tap selects the fill tool; its menu stays closed.
        XCTAssertTrue(fillButton.isSelected, "PREMISE: the Fill tool has to actually be selected")
        XCTAssertFalse(brushIsSelected(app), "PREMISE: and the brush deselected with it")

        assertPinchMovesCanvas(app, canvas,
                               "THE BUG: two-finger pinch/pan/rotate is dead while the Fill tool is selected")
    }

    // MARK: - The text path (owner report (6), 2026-08-27)

    /// The owner's freeze report, once they corrected what *"try to resize the canvas"* meant:
    /// *"by 'try to resize the canvas' I meant moving the canvas with two fingers if I recall
    /// correctly"* — so the symptom is this class's symptom, and their trigger is
    /// *"in the edit text keyboard menu, then select pencil brush"*.
    ///
    /// **Text is the `.fill` case's twin, and that is why these two tests exist.**
    /// `Tool.paintsOnCanvas` is false for exactly `.fill`, `.eyedropper` and `.text`, and it is what
    /// `shouldRequireFailure` reads (through `activeHostIsInteractive`) before it stakes pan / pinch
    /// / rotate on the active layer's stroke recognizer. So `.text` sits in the same state
    /// `testCanvasStillTransformsWithTheFillToolSelected` covers, and BUGS.md's still-open
    /// *"two-finger pan/pinch/rotate is dead while the Fill tool is selected, on device"* is the
    /// other member of that pair. These are the `.text` half of that net.
    ///
    /// This one is text mode with a box actually on screen — the state the owner describes being in
    /// when it locks. `TextOverlayView` is above every layer host and claims the box and its move
    /// band in `hitTest`, so this is also the only test in the suite where a transform gesture has to
    /// start with chrome sitting over the canvas.
    func testCanvasStillTransformsWithATextBoxOpen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        assertPinchMovesCanvas(app, canvas, "Setup: the canvas should pinch before any of this")

        placeATextBox(app, on: canvas)

        assertPinchMovesCanvas(app, canvas,
                               "THE BUG: two-finger pinch/pan/rotate is dead with a text box open")
    }

    /// The owner's sequence to its end: leave the text keyboard by picking the brush, then try to
    /// move the canvas.
    ///
    /// **What it pins is the commit on the way out.** `TopToolbar.selectBrushToolAndTogglePanel`
    /// runs `commitAllInteractiveState()` before it assigns `.pen`, and that call — through
    /// `beginCanvasEdit()` — is the only thing that ends the text session. Skip it and the tool goes
    /// to a painting tool while `textGestureActive` stays true, which turns
    /// `activeHostIsInteractive` on underneath an overlay that is still claiming touches:
    /// `CanvasTouchInputs.transformDependencyIsUnresolvable`, a stroke recognizer that is never
    /// handed a touch, and three transform recognizers waiting on it. `CanvasManager.selectBrush`
    /// was one such exit until `Tool.followsBrushPresetSelection` (`ToolLogicTests`); this is the
    /// route the artist actually has, held to the same standard.
    func testCanvasStillTransformsAfterLeavingTextForTheBrush() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        assertPinchMovesCanvas(app, canvas, "Setup: the canvas should pinch before any of this")

        placeATextBox(app, on: canvas)

        let brushButton = app.buttons["toolbar.brushButton"]
        XCTAssertTrue(brushButton.waitForExistence(timeout: 5))
        brushButton.tap()
        XCTAssertTrue(brushIsSelected(app),
                      "PREMISE: the first tap from text mode has to select the brush, not merely open its panel")

        // The mechanism, asserted directly rather than only through its symptom. A brush selected
        // with `text:` still reading "box" is the unresolvable pair itself — an overlay claiming
        // touches above a layer host that has just gone interactive — and it would be a defect even
        // on a build where the pinch below happened to survive it.
        XCTAssertTrue(waitForTextState(app, "none"), """
            Leaving text mode for the brush left the text session live (text:\(readTextState(app))). \
            `TopToolbar.selectBrushToolAndTogglePanel` runs `commitAllInteractiveState()` first for \
            exactly this reason: the overlay goes on claiming touches in its `hitTest` while \
            `activeHostIsInteractive` turns true underneath it, which is \
            `CanvasTouchInputs.transformDependencyIsUnresolvable`.
            """)

        assertPinchMovesCanvas(app, canvas,
                               "THE BUG: the canvas stopped transforming after leaving text mode for the brush")
    }

    /// Actions -> Add Text, then a tap on the canvas to put a box down. Leaves the text settings
    /// panel open, which is where the owner is when they report the freeze.
    ///
    /// **The tap is right of centre, and the first draft had it left of centre and placed nothing.**
    /// A settings panel drops down under the toolbar aligned to *its own icon's* side
    /// (`DrawingView`'s `panelAlignment`), and Add Text is reached from Actions, a leading tool — so
    /// the text panel is a 300pt-wide, 420pt-tall box over the **left** of the canvas. A tap at
    /// (0.35, 0.35) lands on the panel, no box appears, and both tests then pass while measuring an
    /// ordinary canvas. That is what the `canvas.textEditor` premise below exists to catch.
    ///
    /// `textPanel.fontButton` is the probe for the panel itself because the panel's own container is
    /// a plain SwiftUI view that UIKit surfaces as no queryable element at all (see
    /// `ToolsAndSelectionUITests.testEnteringTextModeClosesTheSelectPanel…`).
    private func placeATextBox(_ app: XCUIApplication, on canvas: XCUIElement) {
        app.buttons["toolbar.actionsButton"].tap()
        let addText = app.buttons["actions.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        XCTAssertTrue(addText.isEnabled, "PREMISE: Add Text is available on the default layer")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5),
                      "PREMISE: Add Text opens the text settings panel")

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.55)).tap()

        // **Not optional politeness — without it both tests pass having placed nothing, which is what
        // the first draft of this class did.** The whole premise is a live text session on screen
        // while the canvas is asked to move; a tap that lands on the settings panel, or a
        // `textTapRecognizer` that was disabled, leaves a green test measuring an ordinary canvas.
        //
        // Read off `canvas.host`'s label rather than by querying `canvas.textEditor`: that identifier
        // is real (`TextOverlayView.swift:91`) and unreachable, because `canvas.host` is an
        // accessibility element in its own right and hides its entire subtree. See
        // `publishCanvasState`, which is where every other invisible piece of canvas state already
        // lives for the same reason.
        // **"editing", not merely "box".** The owner's report names the state precisely — *"in the
        // edit text keyboard menu"* — so a box placed without the editor taking first responder
        // would be a weaker fixture than the one being reasoned about. `handleTextPress` calls
        // `focusEditor()` after `updateTextOverlay` for exactly that reason, and this is what says
        // the call still lands.
        XCTAssertTrue(waitForTextState(app, "editing"),
                      "PREMISE: the canvas tap has to put a live, focused text box on screen "
                      + "(text:\(readTextState(app)))")
    }

    /// The `text:` field of `canvas.host`'s label — "none" / "box" / "editing".
    private func readTextState(_ app: XCUIApplication) -> String {
        readField(app, "text:")
    }

    /// Polls `text:` rather than reading it once: placing a box is a SwiftUI state change and the
    /// label is republished on the pass that follows it, so a single read straight after the tap can
    /// legitimately still say "none".
    private func waitForTextState(_ app: XCUIApplication, _ accepted: String...) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if accepted.contains(readTextState(app)) { return true }
        } while Date() < deadline
        return false
    }

    /// The owner's third report, and the direct net under two changes made together.
    ///
    /// "If I then try to zoom in and out of the screen or even pan it, it for some reason zooms in
    /// and out from the center of the canvas, not your fingers" — said while a smart shape was
    /// pending. `beginAnchorIfNeeded` used to early-return whenever `shapeGestureActive`, on the rule
    /// that two fingers over a pending shape meant "snap it, not pan it"; the only thing that then
    /// seeded the anchor was `commitSnappedShapeIfTransforming`, which also **baked** the shape. So a
    /// pending shape gave you a pinch with no anchor, which is a pinch about the container's own
    /// centre — the canvas centre — and a shape that vanished into the layer as the price of getting
    /// the anchor back.
    ///
    /// Both halves are asserted here, because fixing either alone ships a bug: delete the bake
    /// without seeding the anchor and the canvas refuses to move at all while a shape is pending
    /// (`updateLiveOffset` bails on a nil anchor), which looks nothing like the change that caused it.
    ///
    /// The offset half of `xform:` is what carries the anchoring: a pinch about the canvas centre
    /// changes only the scale, while an anchored pinch also translates so the content under the
    /// fingers stays put.
    ///
    /// **Skipped: XCUITest cannot reach this test's premise.** It needs a pending shape, which needs
    /// `drawAndHoldShape` to complete a hold, and a synthetic touch cannot hold — `thenHoldForDuration`
    /// emits no touch events at all, so `ShapeHoldClock` never accumulates a millisecond of stillness.
    /// Measured, not inferred; see BUGS.md for the numbers. The assertions below are correct and are
    /// what to run the moment the harness can drive a hold.
    func testPinchingWithAPendingShapeMovesTheCanvasAndLeavesTheShapeAlone() throws {
        throw XCTSkip("XCUITest cannot synthesise a stationary hold — see BUGS.md")

        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(readShapeState(app), "none", "PREMISE: nothing pending before the gesture")

        drawAndHoldShape(on: canvas, from: CGVector(dx: 0.30, dy: 0.35), to: CGVector(dx: 0.70, dy: 0.65))
        XCTAssertEqual(readShapeState(app), "adjustable",
                       "PREMISE: holding a stroke has to leave a shape in the adjustable state — "
                       + "'following' here would mean the pen lift never reached the shape at all")

        let before = readTransform(app)
        canvas.pinch(withScale: 2.0, velocity: 1.5)
        let after = readTransform(app)

        XCTAssertNotEqual(before, after,
                          "THE BUG (half 1): a pinch has to move the canvas while a shape is pending "
                          + "(xform \(before) -> \(after))")
        XCTAssertNotEqual(offsetFields(of: before), offsetFields(of: after),
                          "THE BUG (half 1): the pinch has to anchor on the fingers, which moves the "
                          + "canvas offset. Only the scale changing means it zoomed about the canvas "
                          + "centre (xform \(before) -> \(after))")
        XCTAssertEqual(readShapeState(app), "adjustable",
                       "THE BUG (half 2): moving the viewport is not editing the canvas, so the "
                       + "pending shape has to survive a pinch instead of baking into the layer")
    }

    // MARK: - Fixture

    /// Launches into the editor and shortens the one layer's block so the track has an empty slot
    /// after it. Returns `canvas.host`.
    ///
    /// Deliberately does *not* aim at a particular block length. A single layer's block spans the
    /// whole 12-frame scene by default, so there is no gap segment at all to tap; all this fixture
    /// needs is for one to exist, and `emptySlotCoordinate` reads the length back and aims at the
    /// first frame past it. Asking for an exact width would put the fixture at the mercy of
    /// XCUITest's undershooting drags for no benefit — which is how an earlier version of this test
    /// ran against a block that still covered the frame it meant to leave empty.
    private func launchWithAnEmptySlot(_ app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let before = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0), "Could not read the starting block")
        XCTAssertEqual(before.length, 12, "PREMISE: a new scene's block spans all 12 frames")

        performDrag(app, identifier: "timeline.cel.0.0.rightHandle", totalDelta: -250)

        let after = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0), "Could not read the block after shrinking it")
        XCTAssertEqual(after.start, 0, "PREMISE: shrinking the right edge must not move the start frame")
        XCTAssertLessThan(after.length, 12, "PREMISE: the block has to leave a gap to tap")
        return canvas
    }

    /// A screen point in the middle of the first empty slot after the layer's block.
    ///
    /// An empty slot is not an element, so there is nothing to query for it — but the block is, it
    /// starts at frame 0, and its leading edge sits `blockInset` points into the track, so the
    /// centre of the frame just past its end is a fixed point offset from there. Also asserts, as a
    /// premise, that the frame being aimed at really is uncovered.
    private func emptySlotCoordinate(_ app: XCUIApplication) throws -> XCUICoordinate {
        let blocks = celExtents(app, layerIndex: 0)
        XCTAssertEqual(blocks.count, 1, "PREMISE: the layer should still have exactly one block, has \(blocks)")
        let block = try XCTUnwrap(blocks.first)
        let targetFrame = block.start + block.length
        XCTAssertFalse(blocks.contains { targetFrame >= $0.start && targetFrame < $0.start + $0.length },
                       "PREMISE FAILED: frame \(targetFrame + 1) is covered by \(blocks), so it is not an empty slot")

        let element = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let leadingEdge = element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        let centre = CGFloat(targetFrame) * pixelsPerFrame + pixelsPerFrame / 2 - blockInset
        return leadingEdge.withOffset(CGVector(dx: centre, dy: 0))
    }

    /// Every block on a layer's timeline row, as (startFrame, frameCount) — parsed from each cel
    /// element's accessibilityValue, the same "start,length" string `readCel` reads. The two
    /// invisible edge-handle markers share the identifier prefix and carry no value, so they drop
    /// out at the parse.
    private func celExtents(_ app: XCUIApplication, layerIndex: Int) -> [(start: Int, length: Int)] {
        let prefix = "timeline.cel.\(layerIndex)."
        let query = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        var blocks: [(start: Int, length: Int)] = []
        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            guard !element.identifier.hasSuffix("Handle"), let value = element.value as? String else { continue }
            let parts = value.split(separator: ",")
            guard parts.count >= 2, let start = Int(parts[0]), let length = Int(parts[1]) else { continue }
            blocks.append((start, length))
        }
        return blocks.sorted { $0.start < $1.start }
    }

    // MARK: - The gesture under test

    /// Pinches the canvas and asserts its published transform actually moved. Returns the state
    /// after the gesture so a caller can compare two of them.
    @discardableResult
    private func assertPinchMovesCanvas(_ app: XCUIApplication, _ canvas: XCUIElement, _ message: String) -> String {
        let before = readTransform(app)
        canvas.pinch(withScale: 2.0, velocity: 1.5)
        let after = readTransform(app)
        XCTAssertNotEqual(before, after, "\(message) (xform \(before) -> \(after))")
        return after
    }

    /// The `xform:` field of `canvas.host`'s accessibility label — "scale,rotation,dx,dy".
    private func readTransform(_ app: XCUIApplication) -> String {
        readField(app, "xform:")
    }

    /// The `shape:` field — "none" / "following" / "adjustable". See `publishCanvasState`.
    private func readShapeState(_ app: XCUIApplication) -> String {
        readField(app, "shape:")
    }

    private func readField(_ app: XCUIApplication, _ prefix: String) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let field = label.split(separator: " ").first(where: { $0.hasPrefix(prefix) }) else {
            return "?(\(label))"
        }
        return String(field.dropFirst(prefix.count))
    }

    /// Just the dx,dy half of an `xform:` value — the part that only moves when the gesture anchored
    /// on the fingers rather than on the canvas centre.
    private func offsetFields(of xform: String) -> String {
        let parts = xform.split(separator: ",")
        guard parts.count == 4 else { return xform }
        return "\(parts[2]),\(parts[3])"
    }

    /// Closes an open popover without activating anything in it. UIKit puts a full-screen dismiss
    /// region behind every popover; tapping it is the only way to decline the menu, since any tap
    /// aimed at the app itself would land on whatever is underneath once the popover goes away.
    private func dismissPopover(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.waitForExistence(timeout: 2) {
            dismissRegion.tap()
        } else {
            app.otherElements["timeline.ruler"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }

    /// A short stroke across the middle of the canvas — short and quick, so the smart-shape hold
    /// timer never fires and what lands is an ordinary stroke.
    private func drawShortStroke(on canvas: XCUIElement) {
        drawLine(on: canvas, from: CGVector(dx: 0.40, dy: 0.50), to: CGVector(dx: 0.55, dy: 0.55))
    }
}
