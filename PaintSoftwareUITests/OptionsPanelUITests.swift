import XCTest

/// **The bottom options panels, on screen** — TODO item (49). `BottomDockLogicTests` owns the
/// arithmetic; what only a running app can say is whether the dock and the timeline, which are
/// sibling layers of a `ZStack` that were never told about each other, actually end up where the
/// arithmetic says.
///
/// > *"the options panel that pops up on the bottom of the screen in lasso, move, add text, effect
/// > settings for compositor effects (that type of options panel UI) is too tall and obstructs your
/// > view. Make all of them wider and flatter. Additionally, make it move with the timeline
/// > expansion … the move menu for example blocks my timeline graphs when I want to edit the move's
/// > keyframe."*
///
/// `bottomDock.floor` is a one-point invisible marker on the dock's bottom edge — SwiftUI containers
/// are not accessibility elements, so the column's own frame is not otherwise queryable. Its
/// counterpart is `timeline.collapseButton`, which lives in the timeline's mini toolbar at the top
/// of the panel and so is the highest thing the timeline draws.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class OptionsPanelUITests: PaintUITestCase {

    /// Raises the Move menu the owner named, on a document with something to move.
    private func openMovePanel(_ app: XCUIApplication) {
        dragOnCanvas(app, from: CGVector(dx: 0.35, dy: 0.40), to: CGVector(dx: 0.65, dy: 0.55))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised no menu")
    }

    /// Drags the timeline's grab handle up by `points`, and answers how far the timeline's own top
    /// edge actually travelled — which is not `points`, because XCUITest's synthetic drags undershoot
    /// (`PaintUITestCase.performDrag`'s note) and because the height is clamped.
    @discardableResult
    private func growTimeline(_ app: XCUIApplication, by points: CGFloat) -> CGFloat {
        let handle = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let before = handle.frame.minY
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: -1.6, dy: 0.5))
        start.press(forDuration: 0.2,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -points)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        return before - app.buttons["timeline.collapseButton"].frame.minY
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **The dock rides on the timeline's top edge, and moves with it one-for-one.**
    ///
    /// Two heights, three assertions: the panel clears the timeline at the resting height, it clears
    /// it again once the timeline has been dragged taller, and the distance it moved is the distance
    /// the timeline grew. Before this the dock was pinned 100 points off the bottom of the canvas
    /// area against a 250-point timeline, so the first assertion failed by 150 points and the third
    /// by the whole of the drag.
    func testTheMovePanelRidesTheTimelineRatherThanSittingInIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openMovePanel(app)

        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        let timelineTop = { app.buttons["timeline.collapseButton"].frame.minY }

        attach(app, "01-move-panel-timeline-resting")
        let restingFloor = floor.frame.maxY
        let restingTop = timelineTop()
        XCTAssertLessThanOrEqual(restingFloor, restingTop,
                                 String(format: "the Move menu is inside the timeline by %.0f points",
                                        restingFloor - restingTop))

        let grew = growTimeline(app, by: 220)
        XCTAssertGreaterThan(grew, 60, "the grab handle drag did not grow the timeline")
        attach(app, "02-move-panel-timeline-expanded")

        let raisedFloor = floor.frame.maxY
        XCTAssertLessThanOrEqual(raisedFloor, timelineTop(),
                                 String(format: "the taller timeline slid under the Move menu by %.0f points",
                                        raisedFloor - timelineTop()))
        XCTAssertEqual(restingFloor - raisedFloor, grew, accuracy: 2,
                       String(format: "the timeline rose %.0f and the menu rose %.0f",
                              grew, restingFloor - raisedFloor))
    }

    /// **The same anchor with the graph editor open**, which is the case that motivated the ask —
    /// *"the move menu for example blocks my timeline graphs when I want to edit the move's
    /// keyframe."* The graph band grows the row it opens under rather than the panel, so what has to
    /// hold is that the band is *reachable*: the timeline is dragged to full height with the band
    /// open, and the menu still sits above every point of it.
    func testTheMovePanelStaysAboveTheTimelineWithTheGraphEditorOpen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let graphButton = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(graphButton.waitForExistence(timeout: 5), "no graph editor button to open")
        graphButton.tap()
        openMovePanel(app)

        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        growTimeline(app, by: 400)
        attach(app, "03-move-panel-graph-editor-full-height")

        let top = app.buttons["timeline.collapseButton"].frame.minY
        XCTAssertLessThanOrEqual(floor.frame.maxY, top,
                                 String(format: "the Move menu covers the graph band by %.0f points",
                                        floor.frame.maxY - top))
    }

    /// **Flatter is a reflow, not a smaller font** — the Move menu's mode picker used to be a line of
    /// its own beneath the icon row and is beside it now, which is what took a row out of the panel.
    /// Asserted as an overlap of the two frames' vertical extents, so it reds if anything re-stacks
    /// them and cannot be satisfied by a constant.
    func testTheMoveMenusModePickerSharesARowWithItsButtons() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openMovePanel(app)

        let done = app.buttons["moveBar.doneButton"]
        let uniform = app.buttons["Uniform"]
        XCTAssertTrue(uniform.waitForExistence(timeout: 5))
        XCTAssertLessThan(uniform.frame.minY, done.frame.maxY,
                          "the mode picker is stacked under the button row rather than beside it")
        XCTAssertGreaterThan(uniform.frame.maxY, done.frame.minY)
        // And wider than it is tall by a good margin, which is what the whole panel now is.
        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        let panelHeight = floor.frame.maxY - done.frame.minY
        XCTAssertLessThan(panelHeight, done.frame.maxX - uniform.frame.minX,
                          String(format: "the Move menu is %.0f points tall", panelHeight))
    }

    /// The Select panel's own reflow: the mode tabs and the membership picker used to be two bands
    /// separated by a divider and share a row now.
    func testTheSelectPanelsModeTabsShareARowWithTheMembershipPicker() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.selectButton"].tap()

        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        let membership = app.segmentedControls["selectPanel.membershipPicker"]
        XCTAssertTrue(membership.waitForExistence(timeout: 5))
        attach(app, "04-select-panel")
        XCTAssertLessThan(membership.frame.minY, rectangle.frame.maxY,
                          "the membership picker is stacked under the mode tabs rather than beside them")
        XCTAssertGreaterThan(membership.frame.minX, rectangle.frame.maxX,
                             "the two are on the same row but not side by side")
        assertPanelIsDockedAndFlat(app, topControl: rectangle, "the Select panel")
    }

    /// **The anchor is the dock's, so all four panels take it** — asserted on the other two rather
    /// than assumed, because the four are four separate views and only the column they sit in is
    /// shared. The text panel, which is the one with a fixed height ceiling of its own.
    func testTheTextPanelRidesTheTimelineToo() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.actionsButton"].tap()
        let addText = app.buttons["actions.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        XCTAssertTrue(app.otherElements["panel.textSettings"].waitForExistence(timeout: 5)
                      || app.scrollViews["panel.textSettings"].waitForExistence(timeout: 5),
                      "Add Text raised no panel")
        attach(app, "05-text-panel")
        assertPanelIsDockedAndFlat(app, topControl: app.sliders["textPanel.sizeSlider"], "the text panel")
    }

    /// And the compositor effect settings, which is the one the owner asked to be shortened first.
    func testTheEffectSettingsBarRidesTheTimelineToo() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5))
        openKnobs.tap()
        XCTAssertTrue(app.sliders["effectSettings.contrast"].waitForExistence(timeout: 5),
                      "the knobs did not open")
        attach(app, "06-effect-settings-bar")
        assertPanelIsDockedAndFlat(app, topControl: app.staticTexts["layerOptions.subMenuTitle"],
                                   "the effect settings bar")
    }

    /// The two things every docked panel owes: it clears the timeline, and it is **wider than it is
    /// tall**.
    ///
    /// **The second assertion exists because its absence let a broken panel through.** The Select
    /// panel's new first row put a `Rectangle` divider between two columns with a width and no
    /// height; a shape given one dimension is greedy in the other, so the card grew to 1,580 points
    /// — floor to ceiling over the artwork — and every assertion about where its *bottom* edge sat
    /// stayed green, because the bottom edge was exactly where it belonged. Height is measured from
    /// the panel's topmost control to the dock's floor, and compared against the card's own shipped
    /// width, which is the literal reading of *"wider and flatter"*.
    private func assertPanelIsDockedAndFlat(_ app: XCUIApplication, topControl: XCUIElement,
                                            _ what: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5), "\(what) is not in the dock", file: file, line: line)
        let top = app.buttons["timeline.collapseButton"].frame.minY
        XCTAssertLessThanOrEqual(floor.frame.maxY, top,
                                 String(format: "%@ is inside the timeline by %.0f points",
                                        what, floor.frame.maxY - top),
                                 file: file, line: line)

        XCTAssertTrue(topControl.waitForExistence(timeout: 5), "\(what)'s top control", file: file, line: line)
        let height = floor.frame.maxY - topControl.frame.minY
        XCTAssertGreaterThan(height, 0, "\(what) measured no height at all", file: file, line: line)
        XCTAssertLessThan(height, BottomDock.preferredWidth,
                          String(format: "%@ is %.0f points tall against a card %.0f wide",
                                 what, height, BottomDock.preferredWidth),
                          file: file, line: line)
    }
}
