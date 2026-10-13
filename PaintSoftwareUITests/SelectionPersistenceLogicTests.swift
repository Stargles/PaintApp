import XCTest

/// Pure-logic coverage for the owner's 2026-08-21 ask: "When you click the lasso icon, lasso, then
/// pick eraser or brush or fill, the lasso icon should still stay blue... Blue means the lasso is
/// currently on." A live selection is a state that outlives the tool that made it, and the toolbar
/// has to show that — not the fact that the Select panel happens to be open.
///
/// Two things had to be established before touching anything, per the branch's task description:
///
/// 1. Does `selection` already survive picking another tool? It does — nothing on the
///    `selectedTool`/`commitAllInteractiveState` path ever touches it. So this is a pure UI-state
///    bug: the highlight was bound to `activePanel == .select` (which tool panel is open) instead of
///    to whether a selection exists. `CanvasManager.selectIconIsActive` is the fix, and the first
///    group of tests below pins it.
/// 2. What already clears `selection`, and should each keep doing so? Every write site
///    (`handleActiveContextChanged`, `deselect`, `beginMove`, `beginDuplicate`,
///    `setCanvasPadding`) is enumerated in the second group, one test per decision, alongside the
///    one thing that must join neither list: switching tools.
///
/// `TopToolbar.swift` is a `View` file and, per the project's "App sources shared with
/// PaintSoftwareUITests" group (see `CanvasManagerTestSupport.swift`'s doc comment), View files are
/// not compiled a second time into this target — `@testable import PaintSoftware` type-checks there
/// but does not link. That is why the toolbar's own predicate had to move to `CanvasManager` as a
/// static function before a headless test could reach it at all.
final class SelectionPersistenceLogicTests: XCTestCase {

    private func rectSelectionPath() -> CGPath {
        CGPath(rect: CGRect(x: 10, y: 10, width: 20, height: 20), transform: nil)
    }

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    private func stroke(from a: CGPoint, to b: CGPoint) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    /// Two vector layers over the fixture's raster layer. The loop (`rectSelectionPath`, 10…30 square)
    /// is round one stroke on each, and each layer also holds a stroke far from it.
    private func twoInkedVectorLayers() -> (manager: CanvasManager, lower: Int, upper: Int,
                                            lowerVector: VectorCanvas, upperVector: VectorCanvas,
                                            lowerInside: UUID, upperInside: UUID, upperOutside: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let lower = manager.currentLayerIndex
        manager.addVectorLayer()
        let upper = manager.currentLayerIndex
        guard let lowerVector = manager.layers[lower].cels[0].vector,
              let upperVector = manager.layers[upper].cels[0].vector else {
            fatalError("fixture precondition: a vector layer's cel has a canvas")
        }
        lowerVector.addStroke(stroke(from: CGPoint(x: 14, y: 20), to: CGPoint(x: 26, y: 20)))
        upperVector.addStroke(stroke(from: CGPoint(x: 14, y: 22), to: CGPoint(x: 26, y: 22)))
        upperVector.addStroke(stroke(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 56, y: 50)))
        return (manager, lower, upper, lowerVector, upperVector,
                lowerVector.elements[0].id, upperVector.elements[0].id, upperVector.elements[1].id)
    }

    // MARK: - The toolbar's active-lasso state

    /// The owner's report, verbatim: make a selection, then pick brush, eraser, and fill in turn —
    /// the selection must still be there, and the toolbar's active-lasso state must read true, every
    /// time.
    func testSelectionSurvivesSwitchingToBrushEraserAndFillAndTheIconStaysActive() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition: the selection must actually be made")

        for tool: Tool in [.pen, .eraser, .fill] {
            manager.selectedTool = tool
            XCTAssertNotNil(manager.selection, "\(tool) must not clear a live selection")
            XCTAssertTrue(CanvasManager.selectIconIsActive(selectPanelOpen: false, selection: manager.selection),
                          "the toolbar's lasso icon must read active while \(tool) is current and a selection is live")
        }
    }

    /// Before anything has been selected, the icon must read inactive — otherwise the sweep above
    /// could pass with a predicate that is simply always `true`.
    func testSelectIconIsInactiveBeforeAnySelectionExists() {
        let manager = CanvasFixture.manager()
        XCTAssertNil(manager.selection, "fixture precondition: nothing has been selected yet")
        XCTAssertFalse(CanvasManager.selectIconIsActive(selectPanelOpen: false, selection: manager.selection),
                       "control: the highlight must not be on before there is anything to show")
    }

    /// …and after a live selection is cleared, the icon must drop again — the marching ants and the
    /// toolbar highlight are two different readouts of the same state and must agree.
    func testSelectIconIsInactiveAfterTheSelectionIsCleared() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.deselect()

        XCTAssertNil(manager.selection)
        XCTAssertFalse(CanvasManager.selectIconIsActive(selectPanelOpen: false, selection: manager.selection),
                       "deselecting must drop the highlight, the same way it always dropped the marching ants")
    }

    /// The control the task asks for by name: with no selection at all, the Select panel merely being
    /// open must still light the icon on its own — today's pre-existing, unchanged driver. Without
    /// this, a passing suite above could be explained by the highlight simply always being on rather
    /// than by the new `selection != nil` path actually working.
    func testSelectIconIsActiveWhilePanelOpenEvenWithoutASelection() {
        XCTAssertTrue(CanvasManager.selectIconIsActive(selectPanelOpen: true, selection: nil),
                      "opening the Select panel must still highlight the icon on its own, exactly as before this branch")
    }

    // MARK: - Enumerated: what clears `selection`, and what must not

    /// Decision: switching the active tool must NOT clear it — the behaviour this whole branch turns
    /// on. Exercised end-to-end above; stated again here, alone, as its own pinned decision so a
    /// future edit to the sweep above cannot quietly take this one with it.
    func testSwitchingSelectedToolDoesNotClearSelection() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        manager.selectedTool = .pen
        manager.selectedTool = .eraser
        manager.selectedTool = .fill
        XCTAssertNotNil(manager.selection, "picking a paint tool must never be one of the things that clears a selection")
    }

    /// **Decision, revised 2026-10-12 (TODO (185)): a drawn region follows the artist to another
    /// layer.** The owner: *"make the select stay when switching layers. Right now it disappears if
    /// you switch."* It used to be stamped with the cel it was drawn on and put down the moment the
    /// active layer changed; a region carries no cel now, so there is nothing for the switch to
    /// invalidate. Both directions, and the same path object — kept, not redrawn.
    func testChangingToADifferentLayerKeepsARegionSelection() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.currentLayerIndex = 0
        manager.finishSelection(path: rectSelectionPath())
        let drawn = manager.selection
        XCTAssertNotNil(drawn, "fixture precondition")

        manager.currentLayerIndex = 1
        XCTAssertNotNil(manager.selection, "a region drawn on layer 0 is still up on layer 1")
        XCTAssertTrue(manager.selection?.path === drawn?.path, "…the very selection the artist drew")
        XCTAssertTrue(CanvasManager.selectIconIsActive(selectPanelOpen: false, selection: manager.selection),
                      "…and the toolbar still reads a live selection")

        manager.currentLayerIndex = 0
        XCTAssertTrue(manager.selection?.path === drawn?.path, "…and back again")
    }

    /// **The region is the canvas's, so what a verb does with it is the new layer's business**: the
    /// ink on layer 2 inside the loop is cleared and the ink on layer 1, which the loop was drawn
    /// round, is left alone. Both operands — *and* the stroke on layer 2 outside the loop, which is
    /// the one a Clear of the whole layer would also take.
    func testClearActsOnTheLayerTheRegionWasCarriedToAndOnNoOther() {
        let f = twoInkedVectorLayers()
        f.manager.currentLayerIndex = f.lower
        f.manager.finishSelection(path: rectSelectionPath())

        f.manager.currentLayerIndex = f.upper
        f.manager.clearSelectionPixels()

        XCTAssertEqual(Set(f.upperVector.elements.map(\.id)), [f.upperOutside],
                       "layer 2 lost the stroke inside the region and kept the one outside it")
        XCTAssertEqual(Set(f.lowerVector.elements.map(\.id)), [f.lowerInside],
                       "layer 1, where the loop was drawn, is untouched: the verb acts on the active layer")
        XCTAssertNotNil(f.manager.selection, "a region outlives what it cleared")
    }

    /// **Move lifts the new layer's ink inside the region**: the float `beginVectorLassoMove` raises is
    /// layer 2's and holds the stroke inside the loop and not the one outside it.
    func testMoveLiftsTheInkOfTheLayerTheRegionWasCarriedTo() {
        let f = twoInkedVectorLayers()
        f.manager.currentLayerIndex = f.lower
        f.manager.finishSelection(path: rectSelectionPath())
        f.manager.currentLayerIndex = f.upper

        XCTAssertTrue(f.manager.beginVectorLassoMove(), "a region carried to a vector layer lifts what it holds there")
        XCTAssertEqual(f.manager.vectorFloat?.parts[0].layerID, f.manager.layers[f.upper].id,
                       "the float is layer 2's")
        XCTAssertEqual(f.manager.vectorFloat?.parts[0].insideIDs, [f.upperInside],
                       "…and holds the stroke inside the loop only")
        f.manager.cancelVectorFloat()
    }

    /// **A region on a layer with no drawing at the playhead acts on nothing and stays up** — the
    /// artist walks on to a layer that has something, and finds the loop where they left it. Move says
    /// nothing and lifts nothing rather than falling back to the whole layer (LASSO_MOVE.md §5.9).
    func testARegionOnALayerWithNothingAtThePlayheadStaysUpAndActsOnNothing() {
        let f = twoInkedVectorLayers()
        CanvasFixture.setCelLayout(f.manager, layerIndex: f.upper, [(start: 6, length: 6)])
        f.manager.currentFrame = 0
        f.manager.currentLayerIndex = f.lower
        f.manager.finishSelection(path: rectSelectionPath())

        f.manager.currentLayerIndex = f.upper
        XCTAssertNotNil(f.manager.selection, "the region is still up over a layer that is empty here")
        XCTAssertFalse(f.manager.beginVectorLassoMove(), "…and Move has nothing to lift")
        XCTAssertNil(f.manager.vectorFloat)
        f.manager.clearSelectionPixels()
        XCTAssertEqual(f.upperVector.elements.count, 2, "…and Clear cleared nothing")
    }

    /// **The playhead's rule is unchanged for a region that has been carried**: stepping onto another
    /// drawing of the layer the artist is now on puts it down, exactly as it did before regions could
    /// follow a layer switch — the owner was told frames keep today's behaviour.
    func testAFrameStepOntoAnotherCelPutsDownARegionThatWasCarriedToThisLayer() {
        let manager = CanvasFixture.manager(layerCount: 2)
        for layer in 0...1 {
            CanvasFixture.setCelLayout(manager, layerIndex: layer, [(start: 0, length: 6), (start: 6, length: 6)])
        }
        manager.currentFrame = 0
        manager.currentLayerIndex = 0
        manager.finishSelection(path: rectSelectionPath())
        manager.currentLayerIndex = 1
        XCTAssertNotNil(manager.selection, "PREMISE: carried to layer 1")

        manager.currentFrame = 3
        XCTAssertNotNil(manager.selection, "a tick within layer 1's first cel leaves it alone")
        manager.currentFrame = 6
        XCTAssertNil(manager.selection, "layer 1's second cel is another drawing: the region is put down")
    }

    /// **A drag on the selection ends with the cel it was opened on**, as it did when the layer switch
    /// itself cleared the selection: a region that outlives the switch must not leave a colour or size
    /// session writing to the layer the artist walked away from.
    func testALayerChangeEndsASelectionEditOpenOnTheOldLayer() {
        let f = twoInkedVectorLayers()
        f.manager.currentLayerIndex = f.lower
        f.manager.finishSelection(path: rectSelectionPath())
        let sizeBefore = f.lowerVector.elements.compactMap { $0.stroke?.size }
        XCTAssertTrue(f.manager.beginSelectionEdit(.size), "PREMISE: a session is open on layer 1")
        f.manager.previewSelectionEdit(.size(30))

        f.manager.currentLayerIndex = f.upper

        XCTAssertNil(f.manager.selectionEdit, "the session ended with the cel it was opened on")
        XCTAssertEqual(f.lowerVector.elements.compactMap { $0.stroke?.size }, sizeBefore,
                       "…and layer 1's ink is what it was before the drag")
        XCTAssertNotNil(f.manager.selection, "…while the region itself came along")
    }

    /// `Selection.acts(onLayer:cel:)` is the one answer every consumer asks: a region everywhere —
    /// an empty frame included, where a stroke makes the cel and must still be clipped — and a tapped
    /// set on its own cel only.
    func testARegionActsEverywhereAndATappedSetOnItsOwnCelOnly() {
        let path = rectSelectionPath()
        let layer = UUID(), cel = UUID()
        let region = Selection(path: path, bounds: path.boundingBoxOfPath)
        XCTAssertTrue(region.acts(onLayer: layer, cel: cel))
        XCTAssertTrue(region.acts(onLayer: layer, cel: nil), "a layer with no drawing here is still clipped")

        let tapped = Selection(path: path, bounds: path.boundingBoxOfPath,
                               objects: SelectedObjects(layerID: layer, celID: cel, elements: [UUID()]))
        XCTAssertTrue(tapped.acts(onLayer: layer, cel: cel))
        XCTAssertFalse(tapped.acts(onLayer: layer, cel: UUID()), "another cel of the same layer")
        XCTAssertFalse(tapped.acts(onLayer: UUID(), cel: cel), "the same cel id under another layer")
        XCTAssertFalse(tapped.acts(onLayer: layer, cel: nil), "a gap")
    }

    /// Decision: moving the playhead onto a *different cel* clears it — same mechanism as the layer
    /// case, keyed on `celID` rather than `layerID`.
    func testChangingFrameToADifferentCelClearsSelection() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 6), (start: 6, length: 6)])
        manager.currentFrame = 0
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.currentFrame = 6 // the second cel

        XCTAssertNil(manager.selection, "the selection belonged to the first cel and must not carry over to the second")
    }

    /// Decision: scrubbing *within* the cel a selection belongs to must NOT clear it — called out
    /// explicitly at `handleActiveContextChanged`'s doc comment ("Same-cel frame ticks... intentionally
    /// leave both alone"). The near-miss twin of the test above, so the ruling on each side of the
    /// boundary is pinned rather than left implied by checking only one of them.
    func testScrubbingWithinTheSameCelDoesNotClearSelection() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 6), (start: 6, length: 6)])
        manager.currentFrame = 0
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.currentFrame = 3 // still the first cel, frames [0, 6)

        XCTAssertNotNil(manager.selection, "a frame tick that stays on the same cel must leave a live selection alone")
    }

    /// Decision: explicit Deselect clears it — the whole point of the Select panel's button.
    func testDeselectClearsSelection() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.deselect()

        XCTAssertNil(manager.selection)
    }

    /// **Decision, revised 2026-08-22: Move keeps the selection until the piece bakes.**
    ///
    /// It used to clear at the lift, and this test pinned that. The owner overruled it when the
    /// vector lasso move was built (LASSO_MOVE.md §5.6): the outline stays up and travels with the
    /// piece, so the artist can see what they are holding, and it clears when the piece lands. The
    /// two Move tools now behave the same way on the same gesture, which was the point of the ruling.
    ///
    /// `.duplicate` is deliberately not part of it — see the test below, unchanged: a copy is not a
    /// region the artist is still holding.
    func testBeginMoveKeepsTheSelectionUntilTheBake() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.beginMove()

        XCTAssertNotNil(manager.floatingPiece, "fixture check: Move should have actually lifted something")
        XCTAssertNotNil(manager.selection, "the outline stays up while the piece is in the air")

        manager.commitFloatingPieceIfNeeded()

        XCTAssertNil(manager.selection, "and is spent once the piece has landed")
    }

    /// Decision: Duplicate consumes the selection the same way Move does — it copies the selected
    /// region into a new floating piece on a new layer.
    func testBeginDuplicateClearsSelectionAfterLiftingIt() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.beginDuplicate()

        XCTAssertNotNil(manager.floatingPiece, "fixture check: Duplicate should have actually lifted a copy")
        XCTAssertNil(manager.selection)
    }

    /// Decision: resizing the canvas clears it — every stored path is in canvas-point space, and a
    /// dimension change invalidates it (`CanvasManager+Document.swift`, `setCanvasPadding`).
    func testSetCanvasPaddingClearsSelection() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.setCanvasPadding(20)

        XCTAssertNil(manager.selection, "the selection's path is in canvas-point space and stale once the canvas is resized")
    }
}
