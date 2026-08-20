import SwiftUI   // `Color`, for the toolbar-swatch routing test
import UIKit
import XCTest

/// What a text session leaves behind when it bakes — `ADD_TEXT.md` stage 1's "it bakes", asserted on
/// the composited bytes rather than on "did not throw".
///
/// **Characterization, in `CanvasManagerTestSupport`'s sense**: these pin what stage 1 does *today*,
/// at exactly the boundary stage 3 is going to move. Stage 3 makes a vector layer keep the object
/// editable instead of baking it, and the branch for that belongs in `commitInteractiveText` and
/// nowhere else — so every test here that says "raster" says it on purpose, and the one that will
/// legitimately change says so in its name.
///
/// Three claims are load-bearing and each has a bug behind it:
///
///   1. **The pixels land in `Cel.raster`, never in `bakedImage`.** That is the ghost-layer bug
///      `registerUndoableCelChange`'s own doc records: the eraser only ever stamps `raster`, so
///      content left in `bakedImage` is permanently uneraseable and every reader that reasons about
///      "the raster tier" disagrees with what is on screen.
///   2. **One undo step per session, never one per keystroke.** `UndoHistory`'s `cost` accounting
///      was never sized for two hundred entries out of one sentence (§2).
///   3. **`beginCanvasEdit()` is the trigger, and it is one line.** Every existing caller — a stroke,
///      a fill, a layer switch, a save — inherits the bake with no per-tool retrofit, and a test
///      that only ever committed by calling `commitInteractiveText()` directly would not notice if
///      that line went missing.
final class TextBakeCharacterizationTests: XCTestCase {

    private static let canvas = CGSize(width: 200, height: 120)

    /// A canvas with one raster layer and **an empty undo stack**.
    ///
    /// The `removeAll()` is not tidying: `addLayer()` registers a structural step of its own, so
    /// without it every "no step was registered" assertion below would be reading the fixture's own
    /// step, and `undo()` in the three-way-branch tests would delete the layer out from under the
    /// cel it was about to read.
    private func manager() -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = Self.canvas
        manager.addLayer()
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return manager
    }

    /// A session placed at `origin` with `string` typed into it, left adjustable (nothing committed).
    @discardableResult
    private func placeText(_ manager: CanvasManager, _ string: String,
                           at origin: CGPoint = CGPoint(x: 20, y: 20),
                           pointSize: CGFloat = 40) -> CGRect {
        manager.textRecipe.typography.pointSize = pointSize
        manager.textRecipe.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        manager.beginTextSession(at: origin)
        manager.updateTextString(string)
        return manager.textFrame.boundingBox
    }

    private func celPixels(_ manager: CanvasManager, layerIndex: Int = 0) -> [UInt8] {
        guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: manager.currentFrame) else {
            XCTFail("No cel to read")
            return []
        }
        let cel = manager.layers[layerIndex].cels[celIndex]
        let image = PixelOps.rasterize(cel: cel, canvasSize: Self.canvas, memoize: false)
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else {
            XCTFail("Could not read the cel's bytes")
            return []
        }
        return bytes
    }

    /// Alpha at a canvas pixel, straight out of the composited bytes.
    private func alpha(_ bytes: [UInt8], _ x: Int, _ y: Int) -> UInt8 {
        let index = (y * Int(Self.canvas.width) + x) * 4 + 3
        guard bytes.indices.contains(index) else { return 0 }
        return bytes[index]
    }

    private func coveredPixelCount(_ bytes: [UInt8]) -> Int {
        stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 0 ? 1 : 0) }
    }

    // MARK: - The bake puts pixels down

    func testCommittingASessionPutsInkInsideTheBoxAndNowhereElse() {
        let manager = manager()
        let box = placeText(manager, "Hi")
        XCTAssertEqual(coveredPixelCount(celPixels(manager)), 0,
                       "Nothing is on the layer while the session is live — the overlay is the "
                       + "editor, and the model owns nothing but a draft.")

        manager.commitInteractiveText()
        let bytes = celPixels(manager)
        XCTAssertGreaterThan(coveredPixelCount(bytes), 0, "The commit put no ink down at all.")

        for y in 0..<Int(Self.canvas.height) {
            for x in 0..<Int(Self.canvas.width) {
                guard alpha(bytes, x, y) > 0 else { continue }
                XCTAssertTrue(box.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)),
                              "Ink landed at (\(x), \(y)), outside the box \(box). The bake's "
                              + "destination is the frame, not the canvas.")
            }
        }
    }

    func testTheColourThatLandsIsTheRecipesColour() {
        let manager = manager()
        manager.textRecipe.color = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        manager.beginTextSession(at: CGPoint(x: 10, y: 10))
        manager.textRecipe.typography.pointSize = 60
        manager.updateTextString("I")
        manager.commitInteractiveText()

        let bytes = celPixels(manager)
        var sawFullyOpaqueBlue = false
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] == 255 {
            XCTAssertEqual(bytes[i], 0, "Red channel on an opaque glyph pixel")
            XCTAssertEqual(bytes[i + 1], 0, "Green channel on an opaque glyph pixel")
            XCTAssertEqual(bytes[i + 2], 255, "Blue channel on an opaque glyph pixel")
            sawFullyOpaqueBlue = true
        }
        XCTAssertTrue(sawFullyOpaqueBlue, "A 60 pt capital has interior pixels at full coverage; "
                      + "none were found, so nothing was really drawn.")
    }

    func testMovingTheBoxMovesThePixels() {
        let left = manager()
        placeText(left, "M", at: CGPoint(x: 10, y: 10))
        left.commitInteractiveText()
        let leftBytes = celPixels(left)

        let right = manager()
        placeText(right, "M", at: CGPoint(x: 10, y: 10))
        right.beginTextFrameDrag()
        right.dragTextFrame(toOrigin: CGPoint(x: 90, y: 10))
        right.endTextFrameDrag()
        right.commitInteractiveText()
        let rightBytes = celPixels(right)

        XCTAssertEqual(coveredPixelCount(leftBytes), coveredPixelCount(rightBytes),
                       "The same glyphs, moved — a translation changes where the ink is, not how "
                       + "much of it there is.")
        XCTAssertNotEqual(leftBytes, rightBytes)
        // The row through the middle of the glyph: ink on the left in one, on the right in the other.
        let midY = Int(left.textFrame.boundingBox.midY)
        let leftHalf = (0..<80).contains { alpha(leftBytes, $0, midY) > 0 }
        let rightHalf = (90..<170).contains { alpha(rightBytes, $0, midY) > 0 }
        XCTAssertTrue(leftHalf && rightHalf)
    }

    // MARK: - Where the pixels land (claim 1)

    func testTheBakeLandsInTheRasterTierAndClearsTheScratchTiers() {
        let manager = manager()
        placeText(manager, "ab")
        manager.commitInteractiveText()

        let celIndex = manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame)!
        let cel = manager.layers[0].cels[celIndex]
        XCTAssertNil(cel.bakedImage,
                     "Landing a commit in `bakedImage` is the ghost-layer bug: the eraser only ever "
                     + "stamps `Cel.raster`, so text left there could never be erased.")
        XCTAssertNil(cel.fillImage)
        XCTAssertGreaterThan(cel.raster.strokeCount, 0,
                             "`bakedRasterTexture` carries the count forward and floors it at 1, "
                             + "which is the cel's \"has content\" heuristic.")
    }

    // MARK: - Undo (claim 2)

    func testASessionIsExactlyOneUndoStepHoweverMuchWasTyped() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 8, y: 8))
        manager.textRecipe.typography.pointSize = 24
        for character in "a sentence with a good number of keystrokes in it" {
            manager.updateTextString(manager.textRecipe.string + String(character))
        }
        manager.commitInteractiveText()

        XCTAssertTrue(manager.canUndo)
        XCTAssertEqual(manager.history.undo(), .addText)
        XCTAssertFalse(manager.history.canUndo,
                       "Fifty keystrokes, one step. One entry per keystroke is what `UndoHistory`'s "
                       + "cost accounting was never sized for.")
    }

    func testUndoRestoresTheExactBytesTheCelHadBeforeAndRedoPutsThemBack() {
        let manager = manager()
        let before = celPixels(manager)
        placeText(manager, "Wm")
        manager.commitInteractiveText()
        let baked = celPixels(manager)
        XCTAssertNotEqual(before, baked)

        manager.undo()
        XCTAssertEqual(celPixels(manager), before,
                       "Undoing a bake has to restore the cel byte for byte, not approximately.")
        manager.redo()
        XCTAssertEqual(celPixels(manager), baked)
    }

    func testTwoSessionsAreTwoStepsAndUndoPeelsThemInOrder() {
        let manager = manager()
        placeText(manager, "one", at: CGPoint(x: 5, y: 5), pointSize: 24)
        manager.commitInteractiveText()
        let afterFirst = celPixels(manager)

        placeText(manager, "two", at: CGPoint(x: 5, y: 60), pointSize: 24)
        manager.commitInteractiveText()
        XCTAssertNotEqual(celPixels(manager), afterFirst)

        manager.undo()
        XCTAssertEqual(celPixels(manager), afterFirst)
        XCTAssertTrue(manager.canUndo, "The first session's step is still there underneath.")
    }

    // MARK: - Nothing typed

    /// Placing a box and tapping away without typing has changed nothing about the drawing, so it
    /// leaves no step for the artist to press through.
    func testAnEmptyBoxCommitsNothingAndRegistersNoStep() {
        let manager = manager()
        let before = celPixels(manager)
        manager.beginTextSession(at: CGPoint(x: 30, y: 30))
        XCTAssertTrue(manager.textGestureActive)
        manager.commitInteractiveText()

        XCTAssertFalse(manager.textGestureActive)
        XCTAssertEqual(celPixels(manager), before)
        XCTAssertFalse(manager.history.canUndo)
    }

    func testABoxHoldingOnlyWhitespaceAlsoCommitsNothing() {
        let manager = manager()
        placeText(manager, "   \n  ")
        manager.commitInteractiveText()
        XCTAssertFalse(manager.history.canUndo)
        XCTAssertEqual(coveredPixelCount(celPixels(manager)), 0)
    }

    // MARK: - The chokepoint (claim 3)

    /// `beginCanvasEdit()` is what every mutating operation in the app calls first, and
    /// `commitInteractiveText()` is the line in it that gives text its bake for free. Asserted
    /// through `beginCanvasEdit` rather than through the commit directly, so deleting that line
    /// fails a test instead of quietly reverting the feature to "text disappears when you draw".
    func testBeginCanvasEditBakesALiveTextSession() {
        let manager = manager()
        placeText(manager, "x")
        manager.beginCanvasEdit()
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertGreaterThan(coveredPixelCount(celPixels(manager)), 0)
        XCTAssertTrue(manager.history.canUndo)
    }

    /// The same line, reached the way an artist reaches it: a layer switch is a canvas edit.
    func testSwitchingLayersBakesALiveTextSession() {
        let manager = manager()
        placeText(manager, "x")
        manager.addLayer()
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertGreaterThan(coveredPixelCount(celPixels(manager, layerIndex: 0)), 0,
                             "The text belongs to the layer it was placed on, resolved by ID, not to "
                             + "whichever layer is active when it bakes.")
    }

    /// **A live session makes Undo live**, even with an empty committed stack — the fill's and the
    /// shape's rule, extended to text, and the reason `refreshUndoRedoState` had to grow a third
    /// term.
    func testALiveSessionMakesUndoAvailableBeforeAnythingHasCommitted() {
        let manager = manager()
        XCTAssertFalse(manager.canUndo)
        placeText(manager, "x")
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
    }

    // MARK: - The three-way branch

    /// Second arm: lifted but still adjustable. Undo finalizes it into a real step and then reverts
    /// that step, so one press removes the text — rather than silently hitting the *previous* action
    /// while the box lingers on screen.
    func testUndoOnALiftedBoxCommitsItAndThenRevertsIt() {
        let manager = manager()
        placeText(manager, "Q")
        let before = celPixels(manager)
        manager.undo()
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertEqual(celPixels(manager), before, "One press, and the text is gone.")
    }

    /// First arm: a box under the finger is discarded outright, exactly as a fill or a shape under
    /// the finger is. Nothing bakes and no step is registered.
    func testUndoWhileTheBoxIsBeingDraggedDiscardsIt() {
        let manager = manager()
        placeText(manager, "Q")
        manager.beginTextFrameDrag()
        manager.undo()
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertEqual(coveredPixelCount(celPixels(manager)), 0)
        XCTAssertFalse(manager.history.canUndo)
    }

    /// Third arm — the one fill and shape do not have. With the caret live and the keyboard's own
    /// undo stack exhausted, undo resigns first responder *before* it commits, so the editor is not
    /// left floating over a bitmap that already has the text baked into it.
    func testUndoWhileFocusedResignsFirstResponderBeforeCommitting() {
        let manager = manager()
        placeText(manager, "Q")
        manager.textIsFocused = true
        var resignedBeforeCommit: Bool?
        manager.textFocusResigner = { [weak manager] in
            // Read at the moment of resigning: the session must still be live, or the resign came
            // after the commit and the editor was floating over baked pixels in between.
            resignedBeforeCommit = manager?.textGestureActive
        }
        manager.undo()
        XCTAssertEqual(resignedBeforeCommit, true)
        XCTAssertFalse(manager.textGestureActive)
    }

    /// `ADD_TEXT.md` §5.1: with the caret live, undo belongs to the keyboard's own stack, and the
    /// drawing history is not touched at all.
    func testUndoIsHandedToTheKeyboardWhileItSaysItWantsIt() {
        let manager = manager()
        placeText(manager, "one", pointSize: 24)
        manager.commitInteractiveText()
        XCTAssertTrue(manager.history.canUndo)

        placeText(manager, "two", at: CGPoint(x: 5, y: 70), pointSize: 24)
        var asked = 0
        manager.textEditUndoHandler = { _ in
            asked += 1
            return true                      // "the keyboard consumed it"
        }
        manager.undo()
        XCTAssertEqual(asked, 1)
        XCTAssertTrue(manager.textGestureActive,
                      "The session is untouched: the keystroke was undone, not the object.")
        XCTAssertTrue(manager.history.canUndo,
                      "And the drawing history still holds the first session's step, unmoved.")
    }

    // MARK: - Auto-size

    func testTypingGrowsAPristineBoxAndTheBakeFollowsIt() {
        let manager = manager()
        placeText(manager, "i", pointSize: 30)
        let narrow = manager.textFrame.boundingBox
        manager.updateTextString("iiiiiiiiii")
        let wide = manager.textFrame.boundingBox
        XCTAssertGreaterThan(wide.width, narrow.width,
                             "`TextFrame.autoSize` is set on a fresh box, so `size` tracks the "
                             + "measured layout — adding a character extends the text to the right.")
        XCTAssertEqual(wide.origin, narrow.origin, "Growth is rightward and downward; the point the "
                       + "artist tapped holds still.")

        manager.commitInteractiveText()
        let bytes = celPixels(manager)
        XCTAssertTrue((Int(narrow.maxX)..<Int(wide.maxX)).contains { x in
            (Int(wide.minY)..<Int(wide.maxY)).contains { y in alpha(bytes, x, y) > 0 }
        }, "Ink landed past where the box ended before it grew, so the bake used the grown frame.")
    }

    // MARK: - The colour panel routing

    /// `CanvasManager.activeEditColor` is the brush's colour, except while a text session is live —
    /// which is what makes `TopToolbar.toggle`'s no-bake conditional mean something. Without it the
    /// guard buys a panel that no longer bakes and still edits the wrong colour.
    func testTheActiveEditColourFollowsTheTextSessionAndThenGoesBackToTheBrush() {
        let manager = manager()
        manager.brushColor = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
        placeText(manager, "x")
        manager.textRecipe.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(manager.activeEditColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.01)
        XCTAssertEqual(g, 0, accuracy: 0.01)

        manager.activeEditColor = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)
        XCTAssertEqual(manager.textRecipe.color.blue, 1, accuracy: 0.01)

        manager.commitInteractiveText()
        UIColor(manager.activeEditColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(g, 1, accuracy: 0.01, "With no session live it is the brush's colour again.")
    }

    // MARK: - The other destination: a vector layer keeps the object
    //
    // This block replaced `testTextIsRefusedOnAVectorLayerForNow`, which pinned stage 1's refusal and
    // said in its own comment that stage 3 would rewrite it. It is the same three claims as above,
    // asked of the other branch of `commitInteractiveText`: where the result lands, how many undo
    // steps it costs, and that `beginCanvasEdit()` is what triggers it.

    /// The cel's vector display list after `manager` has been driven, or a failure.
    private func vectorElements(_ manager: CanvasManager, layerIndex: Int = 1) -> [VectorElement] {
        guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: manager.currentFrame),
              let canvas = manager.layers[layerIndex].cels[celIndex].vector else {
            XCTFail("No vector canvas on the active cel")
            return []
        }
        return canvas.elements
    }

    private func vectorManager() -> CanvasManager {
        let manager = manager()
        manager.addVectorLayer()
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        XCTAssertEqual(manager.activeLayerKind, .vector, "fixture precondition")
        return manager
    }

    /// Alpha coverage of the cel's **raster tier alone** — the one `registerUndoableCelChange` writes
    /// and the eraser stamps. `celPixels` above is the whole flatten, which on a vector cel includes
    /// `VectorCanvas.render()`, so it cannot tell "the element drew" from "the bake ran".
    private func rasterTierPixelCount(_ manager: CanvasManager, layerIndex: Int = 1) -> Int {
        guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: manager.currentFrame),
              let cg = manager.layers[layerIndex].cels[celIndex].raster.renderToUIImage().cgImage,
              let bytes = CanvasFixture.rgbaBytes(cg) else {
            XCTFail("Could not read the cel's raster tier")
            return -1
        }
        return coveredPixelCount(bytes)
    }

    /// **Stage 3's headline, at the model level**: on a vector layer the commit produces an element
    /// that *renders*, and no pixels in the raster tier.
    ///
    /// Both halves are load-bearing. Ink in `Cel.raster` as well would be uneraseable duplicate
    /// content that doubles on the next re-edit; an element that renders nothing would be an object
    /// the artist cannot see, which is the same bug the vector fill's own commit path warns about
    /// ("the vector twin of the raster ghost-layer bug").
    func testAVectorCommitLandsAnElementThatRendersAndNoRasterPixels() {
        let manager = vectorManager()
        placeText(manager, "Label")
        manager.commitInteractiveText()

        let elements = vectorElements(manager)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements.first?.text?.recipe.string, "Label")
        XCTAssertEqual(rasterTierPixelCount(manager), 0,
                       "A vector layer's text must not also bake into the cel's raster tier.")
        XCTAssertGreaterThan(coveredPixelCount(celPixels(manager, layerIndex: 1)), 0,
                             "…and the element has to actually draw, or it is an invisible object.")
    }

    /// The suppression is visible in the pixels, which is what it is for: while the editor is open
    /// the flatten must not also show the committed glyphs underneath it, or the artist sees their
    /// text twice.
    func testAnOpenEditRemovesTheGlyphsFromTheFlatten() {
        let manager = vectorManager()
        let box = placeText(manager, "Label")
        manager.commitInteractiveText()
        let committed = coveredPixelCount(celPixels(manager, layerIndex: 1))
        XCTAssertGreaterThan(committed, 0)

        manager.beginTextSession(at: CGPoint(x: box.midX, y: box.midY))
        XCTAssertEqual(coveredPixelCount(celPixels(manager, layerIndex: 1)), 0,
                       "The object being edited is skipped by the flatten for the life of the session.")

        manager.commitInteractiveText()
        XCTAssertEqual(coveredPixelCount(celPixels(manager, layerIndex: 1)), committed,
                       "…and comes back exactly as it was when the session commits unchanged.")
    }

    /// The whole point of the stage: tap the object again and the *same* object comes back, with the
    /// recipe it was committed with, ready to retype.
    func testTappingCommittedTextReopensTheSameObject() {
        let manager = vectorManager()
        let box = placeText(manager, "before")
        manager.commitInteractiveText()
        let committedID = vectorElements(manager).first?.id

        manager.beginTextSession(at: CGPoint(x: box.midX, y: box.midY))
        XCTAssertTrue(manager.textGestureActive, "A tap on the object opens an edit session.")
        XCTAssertEqual(manager.textRecipe.string, "before",
                       "The draft is loaded from the element, not reset to empty.")
        XCTAssertEqual(manager.textEditingElementID, committedID)
        XCTAssertTrue(manager.isTextEditLive)

        manager.updateTextString("after")
        manager.commitInteractiveText()

        let elements = vectorElements(manager)
        XCTAssertEqual(elements.count, 1, "Re-editing must not leave a second copy behind.")
        XCTAssertEqual(elements.first?.id, committedID, "Same object, not a replacement.")
        XCTAssertEqual(elements.first?.text?.recipe.string, "after")
    }

    /// Suppressed from the flatten, never lifted out of the array — `ADD_TEXT.md` §1, and the reason
    /// is a data-loss window on a device documented to be killed by jetsam rather than to fail
    /// gracefully. A save taken mid-edit must still contain the object.
    func testAnOpenEditSuppressesWithoutRemoving() {
        let manager = vectorManager()
        let box = placeText(manager, "still here")
        manager.commitInteractiveText()

        manager.beginTextSession(at: CGPoint(x: box.midX, y: box.midY))
        let celIndex = manager.activeCelIndex(inLayer: 1, atFrame: manager.currentFrame)
        let canvas = manager.layers[1].cels[celIndex ?? 0].vector
        XCTAssertEqual(canvas?.elements.count, 1)
        XCTAssertNotNil(canvas?.editingElementID)
        XCTAssertEqual(canvas?.texts.first?.recipe.string, "still here")
    }

    /// One step for the whole session, whatever happened inside it — claim 2 above, on the other
    /// branch. Undo takes the object back out; redo puts it back.
    func testAVectorSessionIsOneUndoStep() {
        let manager = vectorManager()
        placeText(manager, "typed one character at a time")
        manager.commitInteractiveText()

        XCTAssertEqual(manager.history.undo(), .addText)
        XCTAssertFalse(manager.history.canUndo,
                       "One step for the whole session, not one per keystroke.")
        XCTAssertTrue(vectorElements(manager).isEmpty)
        manager.redo()
        XCTAssertEqual(vectorElements(manager).count, 1)
    }

    /// Emptying the box deletes the object, and that is its own single step.
    func testEmptyingAReopenedBoxDeletesTheObject() {
        let manager = vectorManager()
        let box = placeText(manager, "delete me")
        manager.commitInteractiveText()

        manager.beginTextSession(at: CGPoint(x: box.midX, y: box.midY))
        manager.updateTextString("")
        manager.commitInteractiveText()

        XCTAssertTrue(vectorElements(manager).isEmpty)
        manager.undo()
        XCTAssertEqual(vectorElements(manager).first?.text?.recipe.string, "delete me",
                       "Undo of a delete restores the object it removed.")
    }

    /// A box placed on a vector layer and never typed into changes nothing, so it registers nothing —
    /// the same rule the raster bake follows, and for the same reason.
    func testAnEmptyVectorSessionRegistersNothing() {
        let manager = vectorManager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.commitInteractiveText()
        XCTAssertFalse(manager.history.canUndo)
    }

    /// Claim 3 on the other branch: `beginCanvasEdit()` is the trigger, so anything that edits the
    /// canvas commits the session without the text tool being told about it.
    func testAnUnrelatedCanvasEditCommitsTheVectorSession() {
        let manager = vectorManager()
        placeText(manager, "committed by something else")
        manager.beginCanvasEdit()
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertEqual(vectorElements(manager).count, 1)
    }
}
