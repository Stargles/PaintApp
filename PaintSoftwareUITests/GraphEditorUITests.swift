import XCTest

/// **The graph editor band, from a real tap** — KEYFRAMES.md §11.3, stage D2.
///
/// Deliberately one small class of its own rather than a few methods added to `TimelineAndUndoUITests`
/// or `LayerPanelUITests`. `xcodebuild` distributes parallel work per test **class**, so a class is
/// indivisible and the longest one sets the whole suite's critical path — which today is
/// `LayerPanelUITests` at 515 s against a 22.3 min run (CLAUDE.md's cost model). Two tests hung off
/// one of those classes cost the suite their whole runtime; the same two in a class of their own cost
/// it nothing, because a spare clone runs them beside the long one.
///
/// **What is left for this tier and what is not.** Everything the band *draws* — the axis, the
/// clipping, the colours, the sampling density — is `TimelineGraphBandLogicTests`, run headlessly
/// against `TimelineGraphBand`, because XCUITest can see neither a `CGContext` nor a colour. This
/// file exists to prove the one thing the logic tier cannot: that the wiring from a real finger on a
/// real button through `CanvasManager`, `TimelineRowLayout`, `TimelineLayoutKey` and the UIKit
/// coordinator puts a band on the screen and takes it away again.
final class GraphEditorUITests: PaintUITestCase {

    /// The band opens on the selected layer, is visible, and closes.
    ///
    /// It is asserted on a *fresh* document, which animates nothing — so the band comes up reading
    /// `"empty"`, and that is the state being pinned rather than a shortcoming of the fixture. A
    /// band that opened on a layer with no animation and came up blank would leave the artist
    /// looking for a curve that was never there; saying `empty` is the answer, and it is also what
    /// makes this test independent of the several minutes of gestures it would take to author a
    /// curve through the settings bar.
    func testTheGraphEditorButtonOpensAndClosesTheBand() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let button = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "The keyframe button became the graph editor toggle — §11.3, ask 3's tail")

        let band = app.otherElements["timeline.graphBand"]
        XCTAssertFalse(band.exists, "Closed until it is asked for")

        button.tap()
        XCTAssertTrue(band.waitForExistence(timeout: 5),
                      "A tap opens the band under the selected layer")
        XCTAssertEqual(band.value as? String, "empty",
                       "A band on a layer that animates nothing says so rather than coming up blank")

        button.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed,
                       "The same button closes it — it is a toggle, not a one-way door")
    }

    /// **The band grows the row it opens under, and the pinned name column takes the same growth.**
    ///
    /// This is the failure `TimelineRowLayout` exists to make impossible and the one thing about it
    /// no logic test can see: the two columns are laid out by two different files, one SwiftUI and
    /// one UIKit, and a band only one of them knows about shifts every track down while the names
    /// stay put — so a name labels the layer above the one it belongs to.
    ///
    /// **Measured on the row *cells*, which is what XCUITest can actually see.** A SwiftUI `Text`
    /// carrying an accessibility identifier inside a row that also carries `.contentShape` and a
    /// gesture reports the **cell's** frame, not the glyph's — which is why the assertions below are
    /// about tops and heights rather than about centres. So the name being pinned to the *top* of an
    /// expanded cell rather than floating down beside the middle of the curves is **not assertable
    /// from this tier at all**, and was checked by eye instead; what is assertable, and is the
    /// failure that actually loses the artist their place, is that the two columns agree about where
    /// each row starts and which one grew.
    func testOpeningTheBandKeepsEveryNameLinedUpWithItsTrack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // A second layer, so there is a row *below* the expanded one to be pushed down. It lands on
        // top of the stack and selected, so the band opens on row 0 and layer 0 is the row beneath.
        addVectorLayer(app)

        let openName = app.staticTexts["timeline.layerName.1"]
        let openTrack = app.otherElements["timeline.cel.1.0"]
        let lowerName = app.staticTexts["timeline.layerName.0"]
        let lowerTrack = app.otherElements["timeline.cel.0.0"]
        for element in [openName, openTrack, lowerName, lowerTrack] {
            XCTAssertTrue(element.waitForExistence(timeout: 5))
        }

        /// The two columns are 2 pt out of register by inheritance — the name column's ruler spacer
        /// plus one `VStack` step is `rulerHeight + 6` where the track's row 0 is `rulerHeight + 4`,
        /// and the cel block is inset 2 pt inside its row, which happens to cancel it. 6 pt of
        /// tolerance covers both without admitting a row's worth of drift.
        func startsTogether(_ name: XCUIElement, _ track: XCUIElement, _ what: String) {
            XCTAssertEqual(name.frame.minY, track.frame.minY, accuracy: 6,
                           "\(what): name at \(name.frame.minY), track at \(track.frame.minY)")
        }
        startsTogether(openName, openTrack, "Fixture: the two columns start in register")
        startsTogether(lowerName, lowerTrack, "Fixture: and so does the row below")
        XCTAssertEqual(openName.frame.height, lowerName.frame.height, accuracy: 1,
                       "Fixture: every row is the same height until the band opens")
        let before = lowerTrack.frame.minY

        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.otherElements["timeline.graphBand"].waitForExistence(timeout: 5))

        XCTAssertEqual(openName.frame.height - lowerName.frame.height, TimelineGraphBand.height,
                       accuracy: 1,
                       "The name column took the band's height, on the row the band opened under")
        XCTAssertEqual(lowerTrack.frame.minY - before, TimelineGraphBand.height, accuracy: 2,
                       "…and the track pushed the row below down by exactly the same amount")
        startsTogether(openName, openTrack,
                       "The expanded row's blocks stay at the top of it, under its name")
        startsTogether(lowerName, lowerTrack,
                       "…and the row below is still in register — one TimelineRowLayout, two columns")
    }

    /// **What D2's repurposed button had to leave behind, and did not.**
    ///
    /// §2.22's keyframe button became the graph editor toggle on the reasoning that Add / Remove /
    /// Clear Keyframes had moved to the cel menu. True, and incomplete: they had moved to the
    /// `.block` arm of `timelineMenuContent` only, and §2.4 and §2.26 put marks on the *layer* in
    /// absolute document frames — `TimelineKeyMarkers` says they "exist perfectly well at frames the
    /// layer has no cel at", which is why the marker band spans the whole track. So a layer whose one
    /// block covers frames 0–9 had no gesture anywhere in the app that could give it a bare mark at
    /// frame 20. This is the test that a slot with no drawing on it is still a place a keyframe can
    /// go, and it lives here rather than with the other keyframe UI tests because it is D2's debt.
    func testAnEmptySlotCanStillBeGivenAKeyframe() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let block = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let cel = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0),
                                "Could not read the starting block")
        let markers = app.otherElements["timeline.keyMarkers.0"]
        XCTAssertFalse(markers.exists, "PREMISE: an untouched document has no marks and hides the band")

        // Two frames past the block's own right edge — an offset outside the element's bounds is the
        // only handle a test has on an empty slot. Two taps for the reason a block's menu needs two:
        // the first selects the frame, the second raises the menu on the frame already selected.
        let slot = block.coordinate(withNormalizedOffset:
            CGVector(dx: (Double(cel.length) + 2.0) / Double(cel.length), dy: 0.5))
        slot.tap()
        slot.tap()

        XCTAssertTrue(app.buttons["Add Drawing"].waitForExistence(timeout: 5),
                      "PREMISE: this is the empty slot's menu, not a block's")
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.exists, "A frame with no drawing on it is still a frame a mark can sit at")
        add.tap()

        XCTAssertTrue(markers.waitForExistence(timeout: 5),
                      "…and the mark landed: the marker band spans the track, cels or no cels")
    }

    // MARK: - Nothing reflows under a moving finger

    /// **The defect this stage's second pass existed to fix, in the form that changes the document.**
    ///
    /// Picking a block up selects the layer it came from (`beginBlockDrag` writes
    /// `currentLayerIndex`), and the band is part of its row's *height* — so with the band open on a
    /// row above, that write used to move the grabbed row 96 pt up **inside the touch**. The finger
    /// does not move with it, so `layerIndex(atY:)` resolves it against the rows' new positions and
    /// the drop lands one row further down than the finger is: the artist re-times a block and it
    /// changes layer instead. Not a cosmetic detachment, and not recoverable by looking, because the
    /// ghost is drawn at the wrong place too.
    ///
    /// **Only XCUITest can see this.** The whole failure lives in the ordering of a
    /// `currentLayerIndex` write, a `relayout()` and a `layerIndex(atY:)` inside
    /// `TimelineTrackView.swift`, which is not compiled into this target at all; the logic tier can
    /// pin that the band is held (`TimelineGraphBandLogicTests`) but not that the coordinator asks
    /// for the held value at the moment it matters.
    func testABandOnAnotherRowDoesNotDropABlockOnTheWrongLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        // Three rows, so the row below the grabbed one is a real drop target rather than the end of
        // the stack that `layerIndex(atY:)` clamps back to. Top to bottom: layer 2, layer 1, layer 0.
        addVectorLayer(app)
        addVectorLayer(app)

        let grabbed = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(grabbed.waitForExistence(timeout: 5))
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.start, 0, "PREMISE: it starts at 0")
        XCTAssertFalse(app.otherElements["timeline.cel.0.1"].exists,
                       "PREMISE: the bottom layer has exactly one block")

        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.otherElements["timeline.graphBand"].waitForExistence(timeout: 5),
                      "PREMISE: the band is open on layer 2 — the row above the one being grabbed")

        // **Absolute screen coordinates, not the element.** An `XCUIElement` is re-resolved at every
        // touch, so a drag expressed against the block would follow the block as the track reflowed
        // and hide the very thing being tested. A finger does not do that.
        let block = grabbed.frame
        let pixelsPerFrame = block.width + 4          // the block is inset 2 pt inside its slot
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let down = origin.withOffset(CGVector(dx: block.midX, dy: block.midY))
        let across = origin.withOffset(CGVector(dx: block.midX + 5 * pixelsPerFrame, dy: block.midY))
        down.press(forDuration: 0.9, thenDragTo: across)

        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.start, 5,
                       "The block re-timed five frames along the layer it was picked up from")
        XCTAssertEqual(readCel(app, layerIndex: 0, celIndex: 0)?.start, 0,
                       "…and the layer below is untouched")
        XCTAssertFalse(app.otherElements["timeline.cel.0.1"].exists,
                       "…in particular it did not receive the block, which is what the reflow did")
    }

    /// **What a tap inside the band does: nothing, deliberately.**
    ///
    /// The band is a sibling of the row pool with `isUserInteractionEnabled = false`, and the row
    /// view above it is sized to its *block* half — so the band's own rectangle is covered by no row
    /// and a touch there falls through to the scroll view, which pans and nothing else. That is the
    /// right answer for D2: §11.4 claims this area for curve gestures, and a stage that wired it to
    /// the row underneath would be building something D3 has to take out again.
    ///
    /// **It is worth a test because the failure is silent and plausible.** Sizing the row view to
    /// the full expanded height — the obvious simplification, and the one §11.2 warns about — would
    /// make the band read as that row's cel body: a tap in it would select a frame, and a second one
    /// would raise a block menu over the curves.
    func testATapInsideTheBandDoesNothing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let block = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.otherElements["timeline.graphBand"].waitForExistence(timeout: 5))

        let frameBefore = readFrameLabel(app)?.current
        let rect = block.frame
        // Half a band below the block's bottom edge: inside the curves, well clear of both the
        // blocks above and the row below.
        let inBand = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: rect.midX, dy: rect.maxY + TimelineGraphBand.height / 2))
        inBand.tap()
        inBand.tap()

        XCTAssertFalse(app.buttons["Add Drawing"].waitForExistence(timeout: 1),
                       "Two taps in the band must not raise an empty slot's menu")
        XCTAssertFalse(app.buttons["Extend to End"].exists,
                       "…nor a block's")
        XCTAssertEqual(readFrameLabel(app)?.current, frameBefore,
                       "…nor move the playhead")
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.start, 0,
                       "…nor touch the block above it")
    }

    /// **The two-stage tap survives the band moving to the layer it tapped — and the row travels.**
    ///
    /// Both halves are the point. The armed state is a *cel identity* (`handleTapOnCel` compares the
    /// tapped layer and frame against `currentLayerIndex` and `currentFrame`), not a screen position,
    /// so the menu still opens on the second tap after the reflow. But the reflow is real and is
    /// exactly one band: with the band open above it, the row the artist tapped is 96 pt higher when
    /// they go to tap it again, and the point they first touched is now inside the band. That is
    /// inherent to the owner's ruling that the band follows the selected layer — the band is part of
    /// a row's height, so a band arriving above a row moves it — and this test states the cost rather
    /// than hiding it. The fixture assertion in the middle is what stops the last tap being a tap on
    /// a row that never moved.
    func testTheTwoStageTapSurvivesTheBandMovingToTheLayerItTapped() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)                 // layer 1 lands on top and selected; layer 0 is below it

        let lower = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(lower.waitForExistence(timeout: 5))
        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.otherElements["timeline.graphBand"].waitForExistence(timeout: 5),
                      "PREMISE: the band is open on layer 1, the row above the one being tapped")

        let before = lower.frame.minY
        lower.tap()                         // stage one: select that layer and frame

        var travelled: CGFloat = 0
        let deadline = Date().addingTimeInterval(5)
        repeat { travelled = before - lower.frame.minY } while travelled < TimelineGraphBand.height - 2
            && Date() < deadline
        XCTAssertEqual(travelled, TimelineGraphBand.height, accuracy: 2,
                       "The band left the row above and opened here, so this row rose by one band")

        lower.tap()                         // stage two, on the row where it now is
        XCTAssertTrue(app.buttons["Extend to End"].waitForExistence(timeout: 5),
                      "The arm is a cel identity, so the second tap still reaches the block's menu")
    }
}
