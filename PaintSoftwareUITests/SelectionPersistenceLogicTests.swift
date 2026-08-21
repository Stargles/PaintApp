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

    /// Decision: leaving the layer a selection was made on clears it —
    /// `handleActiveContextChanged` (SelectionModels.swift, "leaving the layer/frame ends any
    /// in-progress..." doc comment), deliberate and unchanged by this branch.
    func testChangingToADifferentLayerClearsSelection() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.currentLayerIndex = 0
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.currentLayerIndex = 1

        XCTAssertNil(manager.selection, "a selection stamped to layer 0's cel must not silently apply to layer 1")
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

    /// Decision: Move consumes the selection into the floating piece it lifts — `beginMove` reads
    /// `selection` for its path/bounds and then clears it (SelectionModels.swift), because the
    /// selection's job is done once its region is what got lifted. Not a regression to guard against;
    /// a pre-existing rule this branch must leave alone. (Scope note: this pins that the *state*
    /// transition is unchanged — it does not touch the move-transform overlay itself.)
    func testBeginMoveClearsSelectionAfterLiftingIt() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: rectSelectionPath())
        XCTAssertNotNil(manager.selection, "fixture precondition")

        manager.beginMove()

        XCTAssertNotNil(manager.floatingPiece, "fixture check: Move should have actually lifted something")
        XCTAssertNil(manager.selection, "the selection's region became the floating piece; the selection itself is spent")
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
