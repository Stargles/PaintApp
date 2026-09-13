import XCTest

/// **Can an artist open a folder's curves in the graph editor, and does dragging one reach the
/// canvas?** — TODO (21)'s folder band, driven from a new document.
///
/// **Why this file exists beside `FolderGraphBandLogicTests`.** That file proves the model resolves
/// a folder row, lists the folder's channels and writes to the folder's stores. None of it says
/// whether an artist can *get there*: the two controls that make a folder pickable — its name in the
/// timeline's name column and the "Show in Graph Editor" row of its options panel — live in view
/// files the fast tier does not compile, and the curve is drawn by a `UIView` the fast tier never
/// lays out. This is the class of defect the owner found three of in one minute on 2026-09-03, so
/// every assertion here is on something the screen exposes: the band's own value (what it draws),
/// the folder name's selected trait, the marker bands per row, the folder row's opacity slider (a
/// resolved value) and the ink on the canvas (a composite).
///
/// **The whole workflow is one test, on purpose**: the point is the *chain* from a blank document
/// to a moved curve, and a launch is the expensive part.
final class FolderGraphBandUITests: PaintUITestCase {

    // MARK: - Helpers

    private func keyframeSummary(_ app: XCUIApplication) -> String {
        app.staticTexts["layerOptions.folderKeyframes"].value as? String ?? "?"
    }

    private func openFolderOptions(_ app: XCUIApplication, named name: String) {
        XCTAssertTrue(tapWhenHittable(app.buttons["layerPanel.folder.\(name).options"],
                                      "The folder row's options button"),
                      "Without the options panel there is no keyframe row and no graph editor row")
        XCTAssertTrue(app.buttons["layerOptions.addKeyframe"].waitForExistence(timeout: 5),
                      "The folder's options panel must show its keyframe row")
    }

    private func closeFolderOptions(_ app: XCUIApplication) {
        XCTAssertTrue(tapWhenHittable(app.buttons["layerOptions.close"], "The options panel's close"),
                      "The panel has to close before the transport is reachable")
    }

    private func stepForward(_ app: XCUIApplication, _ count: Int, toFrame frame: Int) {
        let next = app.buttons["timeline.stepForwardButton"]
        for _ in 0..<count {
            XCTAssertTrue(tapWhenHittable(next, "The timeline's step-forward button"))
        }
        XCTAssertEqual(readFrameLabel(app)?.current, frame + 1,
                       "The playhead must be on frame \(frame)")
    }

    private func goToStart(_ app: XCUIApplication) {
        XCTAssertTrue(tapWhenHittable(app.buttons["timeline.toStartButton"], "The to-start button"))
        XCTAssertEqual(readFrameLabel(app)?.current, 1, "To-start must land on frame 0")
    }

    private func folderOpacity(_ app: XCUIApplication, named name: String) -> Double {
        sliderNumericValue(app.sliders["layerPanel.folder.\(name).opacity"])
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The cold-start path

    /// **From a blank document: ink, a group around it, two keyframes on the group's opacity, then
    /// both doors into the group's band, a node drag, and the canvas.** Every step's answer is read
    /// off the screen; the operands, in order:
    ///
    ///  * **`timeline.graphBand`'s value** — `TimelineGraphBand.encode` over the `Content` the band
    ///    view was last laid out with, so it is what is *drawn*. `"opacity:0,4"` is the folder's
    ///    curve; `"empty"` is the layer's band. The two doors are asserted by this value moving,
    ///    which a build that picked the folder in the model but never re-laid-out the track would
    ///    fail.
    ///  * **`timeline.folderName.Folder 1`'s selected trait** — the name column's own signal that
    ///    the folder is the picked row, with the band closed as well as open.
    ///  * **The folder row's opacity slider at frame 4 after the drag** — it reads
    ///    `folder.opacity(atFrame:)`, the resolved value, so it moves only if the drag wrote a curve
    ///    the folder resolves.
    ///  * **The canvas at frame 4** — paper before the drag (the group at zero opacity), ink after
    ///    it. This is the composite, and the assertion that separates "a number was stored on the
    ///    folder" from "the group draws differently".
    ///  * **The two marker bands** — the folder's row keeps `0|4` and the layer's row never grows a
    ///    band, which is what says the drag wrote the folder and not the current layer. Both share
    ///    the `opacity` id, so nothing else on screen distinguishes them.
    func testAGroupsCurvesOpenInTheGraphEditorFromAColdStartAndADragReachesTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "The editor has to open before anything can be keyed")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "There is no canvas to read pixels from")

        // 1. Ink — a band rather than a hairline, so the probe cannot fall between passes.
        let probe = (dx: 0.42, dy: 0.50)
        for i in 0..<9 {
            let x = 0.40 + Double(i) * 0.005
            drawLine(on: canvas, from: CGVector(dx: x, dy: 0.42), to: CGVector(dx: x, dy: 0.58))
        }
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: probe.dx, dy: probe.dy)),
                       "Premise: the probe point lands on ink")

        // 2. A group, with the ink inside it.
        openLayerPanel(app)
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5))
        dragRow(layerCell(app, layerIndex: 0), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        XCTAssertEqual(rowFolder(app, layerIndex: 0), "Folder 1",
                       "The ink has to live inside the group, or the group's opacity changes nothing")

        // 3. Two keyframes on the group's opacity: 100% at frame 0, 0% at frame 4.
        openFolderOptions(app, named: "Folder 1")
        app.buttons["layerOptions.addKeyframe"].tap()
        XCTAssertEqual(keyframeSummary(app), "0", "Premise: the first keyframe landed on the group")
        closeFolderOptions(app)
        stepForward(app, 4, toFrame: 4)
        app.sliders["layerPanel.folder.Folder 1.opacity"].adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertLessThan(folderOpacity(app, named: "Folder 1"), 5, "Premise: the group is faded out")
        openFolderOptions(app, named: "Folder 1")
        app.buttons["layerOptions.addKeyframe"].tap()
        XCTAssertEqual(keyframeSummary(app), "0,4", "Premise: the group is keyed on both frames")
        XCTAssertTrue(waitUntilBlank(canvas, dx: probe.dx, dy: probe.dy, timeout: 15),
                      "Premise: at frame 4 the group draws at zero opacity, so the probe is paper")

        // 4. Door one: the options panel's row. The artist has just placed a keyframe from here and
        //    the next thing they want is to see the curve — this row is the one they can see.
        let graphRow = app.buttons["layerOptions.folderGraphEditor"]
        XCTAssertTrue(graphRow.waitForExistence(timeout: 5), """
            `layerOptions.folderGraphEditor` never appeared in the folder's options panel. Without \
            it the only way into a group's band is a tap on the group's name in the timeline, which \
            nothing on this panel points at.
            """)
        graphRow.tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5),
                      "The row opens the graph editor — the band has to come up")
        XCTAssertFalse(app.buttons["layerOptions.addKeyframe"].exists,
                       "…and closes the panel, so the band is not under the rail that raised it")
        XCTAssertEqual(band.value as? String, "opacity:0,4", """
            The band must be drawing the *group's* opacity curve, keyed at 0 and 4. "empty" means \
            it opened on the layer inside the group (which animates nothing); anything else means \
            the wrong row.
            """)
        let folderName = app.staticTexts["timeline.folderName.Folder 1"]
        XCTAssertTrue(folderName.waitForExistence(timeout: 5))
        XCTAssertTrue(folderName.isSelected,
                      "The name column marks the group as the picked row while the band is on it")
        attach(app, "folder-band-open-from-panel")

        // 5. Picking the layer's row takes the band back to the layer — a tap on its cel, which is
        //    how a layer has always been picked in the timeline.
        let block = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        let onLayer = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "empty"),
                                                object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [onLayer], timeout: 5), .completed, """
            Tapping a cel picks that layer's row, and the band follows the selection (the owner's \
            2026-08-29 ruling) — the layer animates nothing, so the band reads "empty". A band that \
            stayed on the group here is a pick that nothing can undo.
            """)
        XCTAssertFalse(folderName.isSelected, "…and the group is no longer the picked row")
        // The cel tap moved the playhead to the tapped frame; every reading below is at frame 4.
        goToStart(app)
        stepForward(app, 4, toFrame: 4)

        // 6. Door two: the group's name in the timeline's name column, the row's own control.
        folderName.tap()
        let onFolder = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "opacity:0,4"),
                                                 object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [onFolder], timeout: 5), .completed, """
            A tap on the group's name must move the band to the group and draw its curve. This is \
            the door an artist finds without opening any panel — the name is the row, and tapping \
            it is choosing it, exactly as tapping a cel chooses a layer's row. The band read \
            "\(band.value as? String ?? "?")".
            """)
        XCTAssertTrue(folderName.isSelected, "…and the name column says the group is the picked row")
        attach(app, "folder-band-open-from-name")

        // 7. Drag the node at frame 4 from 0% to the top of the band. Vertical only, so the frame
        //    stays 4 and what changes is the value — which is what the canvas can show.
        let bandFrame = band.frame
        let origin = band.coordinate(withNormalizedOffset: .zero)
        let x = TimelineGraphBand.x(ofFrame: 4, pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame)
        let node = origin.withOffset(CGVector(
            dx: x, dy: TimelineGraphBand.y(ofValue: 0, in: 0...1, bandHeight: bandFrame.height)))
        let top = origin.withOffset(CGVector(
            dx: x, dy: TimelineGraphBand.y(ofValue: 1, in: 0...1, bandHeight: bandFrame.height)))
        node.press(forDuration: 0.2, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)

        XCTAssertEqual(band.value as? String, "opacity:0,4",
                       "A vertical drag retimes nothing: both nodes are still at 0 and 4")
        let lifted = folderOpacity(app, named: "Folder 1")
        XCTAssertGreaterThan(lifted, 60, """
            The group's opacity at frame 4 must have risen well above the 0% it was keyed at — the \
            row's slider reads the *resolved* value, so this is the curve the group resolves and not \
            a stored number. It read \(lifted).
            """)
        XCTAssertTrue(waitUntilFilled(canvas, dx: probe.dx, dy: probe.dy, timeout: 15), """
            At frame 4 the ink inside the group must be visible again after the drag: the probe was \
            paper a moment ago and the node it depends on has been dragged to full opacity. Paper \
            here means the drag wrote somewhere the compositor does not read for the *folder* node.
            """)
        attach(app, "folder-band-node-dragged")

        // 8. Which row took the write — the operand the band's value cannot supply, since the layer
        //    inside the group shares the `opacity` id.
        XCTAssertEqual(app.otherElements["timeline.folderTrack.Folder 1.keys"].value as? String, "0|4",
                       "The group's row still carries both diamonds — the drag moved a value, not a frame")
        XCTAssertFalse(app.otherElements["timeline.keyMarkers.0"].exists, """
            The layer inside the group must not have grown a keyframe. Its marker band is hidden \
            when it has none, so its absence is the assertion — and it is the half that goes red if \
            the band's write resolved the folder target back to the current layer.
            """)

        // 9. One drag is one press of Undo, and the band stays on the group through it.
        app.buttons["sideToolbar.undoButton"].tap()
        let undone = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.folderOpacity(app, named: "Folder 1") < 5 },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [undone], timeout: 5), .completed,
                       "One press of Undo puts the node back at 0%")
        XCTAssertEqual(band.value as? String, "opacity:0,4", """
            The band must still be on the group after Undo. The undo restores a structure snapshot \
            that writes `currentLayerIndex` back to the value it already holds; a folder pick \
            cleared on every write rather than on a change would move the band to the layer here.
            """)

        // 10. Closing and reopening the editor keeps the pick: the band opens on the group again.
        let editor = app.buttons["timeline.graphEditorButton"]
        editor.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "The button closes the band")
        XCTAssertTrue(folderName.isSelected,
                      "…and the group stays the picked row: a pick is a selection, not a property "
                      + "of an open band")
        editor.tap()
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        XCTAssertEqual(band.value as? String, "opacity:0,4",
                       "Reopened, the band is on the picked group — the same button an artist opens "
                       + "a layer's band with, with the group picked instead of a layer")
    }
}
