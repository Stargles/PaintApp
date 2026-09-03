import XCTest

/// **The graph editor band exists, and is laid out where it says it is** — KEYFRAMES.md §11.3,
/// stage D2. D3's gestures are `GraphEditorGestureUITests`, further down this same file.
///
/// Deliberately its own class rather than a few methods added to `TimelineAndUndoUITests` or
/// `LayerPanelUITests`. `xcodebuild` distributes parallel work per test **class**, so a class is
/// indivisible and the longest one sets the whole suite's critical path (CLAUDE.md's cost model).
/// Tests hung off one of the heavy classes cost the suite their whole runtime; the same tests in a
/// class of their own cost it nothing, because a spare clone runs them beside the long one. The class
/// this sentence used to name as the 515 s floor, `LayerPanelUITests`, was split into three on
/// 2026-08-29 for exactly that reason — so re-take the table rather than quoting a number from here.
///
/// **The same argument then applied to this class and it was split in two on 2026-08-30**, D3 having
/// taken it from ~40 s to a MEASURED 271 s over ten tests and made it the suite's second-longest.
/// The seam is what a test is *about*: here, that the band opens, closes, follows the selected layer
/// and stays in register with the pinned name column; there, what a finger does to a curve once it
/// is drawn. Balanced on seconds and not on tests — 7 tests / 133 s here against 3 / 136 s there.
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

    /// **The channel list is a control of the editor, so it comes and goes with it** —
    /// KEYFRAMES.md §11.5, stage D4.
    ///
    /// The one thing about D4 no logic test can see, and the reason it is here rather than only in
    /// `TimelineGraphChannelListLogicTests`: the list hangs off a **second** button rather than off
    /// the graph editor's own, because a control that both toggles and raises a menu has no good
    /// gesture for its second tap. That is a fact about two SwiftUI views in a file this target does
    /// not compile, so what is assertable is exactly this — the second button does not exist until
    /// the band does, and it goes away with it.
    ///
    /// **Asserted on a fresh document, which animates nothing**, so the popup comes up saying so.
    /// That is the state being pinned rather than a shortcoming of the fixture: authoring a curve
    /// through the settings bar costs minutes of gestures, and everything the boxes *do* once there
    /// is one is pinned headlessly against `CanvasManager` in the fast tier.
    func testTheChannelListButtonExistsOnlyWhileTheBandIsOpen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let editor = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let channels = app.buttons["timeline.graphChannelsButton"]
        XCTAssertFalse(channels.exists,
                       "There is no graph editor yet, so there is no option in one")

        editor.tap()
        XCTAssertTrue(channels.waitForExistence(timeout: 5),
                      "Opening the band puts its channel list button beside the toggle")

        channels.tap()
        let empty = app.staticTexts["timeline.graphChannels.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5),
                      "A popup that came up holding nothing says so rather than being blank")

        // The popover has to come down before the toggle can be tapped again: a tap outside a
        // `.popover` is spent dismissing it and does not reach what it landed on, which is the whole
        // reason `CanvasPresentation` exists.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        let popupGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: empty)
        XCTAssertEqual(XCTWaiter().wait(for: [popupGone], timeout: 5), .completed)

        editor.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: channels)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed,
                       "Closing the band takes the option with it — it is not a timeline control")
    }

    /// **What D2's repurposed button had to leave behind, and did not.**
    ///
    /// §2.22's keyframe button became the graph editor toggle on the reasoning that Add / Remove /
    /// Clear Keyframes had moved to the cel menu. True, and incomplete: they had moved to the
    /// `.block` arm of `timelineMenuContent` only, and §2.4 and §2.26 put marks on the *layer* in
    /// absolute document frames — `TimelineKeyMarkers` says they "exist perfectly well at frames the
    /// layer has no cel at", which is why the marker band spans the whole track. So a layer whose one
    /// block covers frames 0–9 had no gesture anywhere in the app that could give it a mark at
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
        let cel = try XCTUnwrap(readCel(app, layerIndex: 1, celIndex: 0))
        XCTAssertEqual(cel.start, 0, "PREMISE: it starts at 0")
        XCTAssertFalse(app.otherElements["timeline.cel.0.1"].exists,
                       "PREMISE: the bottom layer has exactly one block")

        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.otherElements["timeline.graphBand"].waitForExistence(timeout: 5),
                      "PREMISE: the band is open on layer 2 — the row above the one being grabbed")

        // **Absolute screen coordinates, not the element.** An `XCUIElement` is re-resolved at every
        // touch, so a drag expressed against the block would follow the block as the track reflowed
        // and hide the very thing being tested. A finger does not do that.
        //
        // A frame's width is measured rather than assumed: the block spans its cel's whole length
        // and is inset 2 pt inside it, so one frame is `(width + 4) / length` whatever the timeline's
        // zoom happens to be. Two frames, so the far end of the drag is still comfortably on screen.
        let block = grabbed.frame
        let frameWidth = (block.width + 4) / CGFloat(cel.length)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let down = origin.withOffset(CGVector(dx: block.midX, dy: block.midY))
        let across = origin.withOffset(CGVector(dx: block.midX + 2 * frameWidth, dy: block.midY))
        down.press(forDuration: 0.9, thenDragTo: across)

        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.start, 2,
                       "The block re-timed two frames along the layer it was picked up from "
                       + "(block \(block), \(cel.length) frames, one frame \(frameWidth) pt)")
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

/// **Stage D3's gestures through a real finger** — KEYFRAMES.md §11.4.
///
/// **Split out of `GraphEditorUITests` on 2026-08-30, and the reason is the whole of CLAUDE.md's
/// cost model rather than tidiness.** `xcodebuild` distributes parallel work per test *class*, so a
/// class is indivisible and the longest one sets the suite's critical path. D3 took that class from
/// ~40 s to a MEASURED **271 s over ten tests**, which made it the suite's second-longest — behind
/// `SelectionAndMoveUITests` at 327 s and ahead of everything else. Two classes of ~135 s each
/// distribute onto two clones and the floor falls back under `PerfBaselineTests`.
///
/// **The seam is the band's existence against the band's gestures**, and the balance is on measured
/// seconds rather than on test count: three tests here against seven there, 136 s against 133 s.
/// That asymmetry is the point — the three gesture tests each spend ~45 s, and nearly all of it is
/// `authorAnAnimatedBrightnessCurve` rather than the gesture, because the graph editor edits curves
/// and cannot be the thing that makes the first one. A split on test count would have put 3 s of
/// work in one class and 268 in the other. It is `LayerPanelUITests`' lesson, where one test was a
/// seventh of the class.
///
/// Everything these gestures *decide* is `TimelineGraphBandLogicTests`, headless and free: the hit
/// radius, the neighbour clamp, the two axes, the tap predicate and the undo arithmetic. What only
/// this tier can see is that a touch on a `UIView` inside a horizontally scrolling `UIScrollView`
/// reaches the band at all — without `scrollView.panGestureRecognizer.require(toFail:)` every drag
/// here is eaten by the scroll view and the band is a picture, which is exactly what D2 shipped.
final class GraphEditorGestureUITests: PaintUITestCase {

    /// **A key travels under a finger, and the keyframe travels with it.**
    ///
    /// **The assertion that a moved key moves its keyframe is the one this feature could get wrong
    /// invisibly**, and until 2026-09-03 it got it half wrong on purpose: §2.28 left the artist's
    /// mark behind on the frame the key vacated, and the band drew a hollow diamond there with no
    /// node under it. The owner reported that three times, and the rule now is theirs — a node on the
    /// graph editor and an indicator on the cel are the same thing, in both directions. So the marker
    /// band a row up follows the curve edit exactly, and the frame the key left carries nothing.
    func testDraggingAKeyMovesItAndTheKeyframeUnderneathItFollows() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let authored = try authorAnAnimatedBrightnessCurve(app, from: 0, to: 6)

        app.buttons["timeline.graphEditorButton"].tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        XCTAssertEqual(band.value as? String, "brightnessContrast.brightness:0,6",
                       "PREMISE: the band is drawing the curve the settings bar just authored")
        let markers = app.otherElements["timeline.keyMarkers.1"]
        XCTAssertEqual(markers.value as? String, "0|6",
                       "PREMISE: two keyframes, both carrying a node on the channel")

        // The key at frame 0 holds Brightness / Contrast's default of 1.0, which is the middle of its
        // 0…2 `uiRange` — so its y is computable without knowing what the slider drag produced at the
        // other key. Both mappings come from `TimelineGraphBand` rather than from literals.
        let bandFrame = band.frame
        let key = band.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: TimelineGraphBand.x(ofFrame: 0, pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame),
            dy: TimelineGraphBand.y(ofValue: authored.start, in: 0...2, bandHeight: bandFrame.height)))
        // Three frames right at the default zoom. Well short of the neighbour at 6, so the clamp is
        // not what this test is measuring, and XCUITest's synthetic drags undershoot by a
        // timing-dependent amount — hence the assertion below is a range.
        key.press(forDuration: 0.2,
                  thenDragTo: key.withOffset(CGVector(dx: TimelineKeyMarkers.basePixelsPerFrame * 3, dy: 0)),
                  withVelocity: .slow, thenHoldForDuration: 0.3)

        let moved = try XCTUnwrap(band.value as? String)
        let landed = try XCTUnwrap(Int(moved.split(separator: ":")[1].split(separator: ",")[0]),
                                   "Could not read the moved key's frame out of \(moved)")
        XCTAssertTrue((1...5).contains(landed),
                      "The key should have travelled toward frame 3 and stopped short of its neighbour: \(moved)")
        XCTAssertEqual(moved, "brightnessContrast.brightness:\(landed),6",
                       "…and the key at 6 did not move")
        XCTAssertEqual(markers.value as? String, "\(landed)|6", """
            The keyframe did not follow the key. A node on the graph editor and an indicator on the \
            cel are one thing — so moving a key moves the diamond, and the frame it left has neither.
            """)

        app.buttons["sideToolbar.undoButton"].tap()
        let back = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "brightnessContrast.brightness:0,6"),
            object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed, """
            One drag is one press of Undo. The drag writes the whole curve on every `.changed` tick, \
            and `setEffectParameterTrack` records a step per call — the gesture bracket is what \
            collapses them, and without it this needs one press per tick.
            """)
        XCTAssertEqual(markers.value as? String, "0|6", "…and the union came back with it")
    }

    /// **A tap on the band is the other half of the same gesture** — `CurveEditor`'s rule, which
    /// §11.4 nominates: on a key it removes, on empty graph it adds. Both are one press of Undo,
    /// being one write each.
    func testATapAddsAKeyToTheCurveItLandsOnAndRemovesOneItLandsOn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let authored = try authorAnAnimatedBrightnessCurve(app, from: 0, to: 6)

        app.buttons["timeline.graphEditorButton"].tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        XCTAssertEqual(band.value as? String, "brightnessContrast.brightness:0,6")

        // Frame 3 is the middle of the only segment, so the line there is halfway between the two
        // keys' values whatever the tangents do with the ends — an aim well inside `hitRadius` of the
        // curve and nowhere near either key's own column.
        let bandFrame = band.frame
        let onTheLine = band.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: TimelineGraphBand.x(ofFrame: 3, pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame),
            dy: TimelineGraphBand.y(ofValue: (authored.start + authored.end) / 2, in: 0...2,
                                    bandHeight: bandFrame.height)))
        onTheLine.tap()

        let added = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "brightnessContrast.brightness:0,3,6"),
            object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [added], timeout: 5), .completed,
                       "A tap near a curve adds a key to it, at the tapped frame — got \(band.value ?? "nil")")
        XCTAssertEqual(app.otherElements["timeline.keyMarkers.1"].value as? String, "0|3|6",
                       "…and the new key is a keyframe, with no mark written for it")

        onTheLine.tap()
        let removed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "brightnessContrast.brightness:0,6"),
            object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [removed], timeout: 5), .completed,
                       "…and a second tap, now on the key it just made, takes it away again")

        // **And that removal is recoverable, which is not a free consequence of removing it.** A
        // tap's write is a bare `setEffectParameterTrack`, and that records a step only while no
        // gesture bracket is open — so the coordinator has to close the touch's drag *before* the
        // write rather than after it in a `defer`. Get that ordering wrong and the key is deleted
        // from the document with nothing on the undo stack; the app looks correct and one press of
        // Undo takes back the wrong edit, or none.
        app.buttons["sideToolbar.undoButton"].tap()
        let back = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "brightnessContrast.brightness:0,3,6"),
            object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed, """
            One press of Undo brings a tapped-away key back. If this fails having removed the key, \
            the removal was written inside an open gesture bracket and recorded nothing.
            """)
        XCTAssertEqual(app.otherElements["timeline.keyMarkers.1"].value as? String, "0|3|6",
                       "…and the union came back with it")
    }


    /// **Ask 6, through a finger: a rubber band in empty space picks keys up, and grabbing any member
    /// of that set then moves the whole of it.**
    ///
    /// Two gestures, and the second is the one no logic test can see — the standing selection has to
    /// survive the first drag ending, the layout passes in between, and the second drag's touch-down
    /// resolving to a key that is already in it. What the fast tier covers is which keys a rect
    /// encloses and where the group lands; what this covers is that the band's own drag-in-empty-space
    /// exists at all, which it does not without `require(toFail:)` — the enclosing scroll view eats it.
    func testAMarqueeSelectsKeysAndDraggingOneOfThemMovesThemTogether() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let authored = try authorAnAnimatedBrightnessCurve(app, from: 0, to: 6)

        app.buttons["timeline.graphEditorButton"].tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        XCTAssertEqual(band.value as? String, "brightnessContrast.brightness:0,6")

        let height = band.frame.height
        let origin = band.coordinate(withNormalizedOffset: .zero)
        let ppf = TimelineKeyMarkers.basePixelsPerFrame
        func point(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: dx, dy: dy))
        }
        // A box round both keys' columns, begun in a corner further than `hitRadius` from either dot
        // — otherwise the touch is a grab and there is no marquee to test.
        let corner = point(2, height - 4)
        corner.press(forDuration: 0.2,
                     thenDragTo: point(TimelineGraphBand.x(ofFrame: 6, pixelsPerFrame: ppf) + 14, 4),
                     withVelocity: .slow, thenHoldForDuration: 0.3)

        // Now take the pair by the key at frame 0 and carry both two frames right.
        let key = point(TimelineGraphBand.x(ofFrame: 0, pixelsPerFrame: ppf),
                        TimelineGraphBand.y(ofValue: authored.start, in: 0...2, bandHeight: height))
        key.press(forDuration: 0.2, thenDragTo: key.withOffset(CGVector(dx: ppf * 2, dy: 0)),
                  withVelocity: .slow, thenHoldForDuration: 0.3)

        let moved = try XCTUnwrap(band.value as? String)
        let frames = moved.split(separator: ":")[1].split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(frames.count, 2, "Both keys should still be there: \(moved)")
        XCTAssertTrue((1...3).contains(frames[0]),
                      "The pair should have travelled toward frame 2: \(moved)")
        XCTAssertEqual(frames[1] - frames[0], 6, """
            The selection moved as a rigid body, so its two keys keep the six frames between them —             got \(moved). A per-key clamp, or a marquee that only picked up the key under the             finger, is what this looks like when it is wrong.
            """)

        app.buttons["sideToolbar.undoButton"].tap()
        let back = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "brightnessContrast.brightness:0,6"),
            object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed,
                       "A marquee move of two keys is still one press of Undo")
    }
}

/// **The fixture both graph-editor classes share**, on `PaintUITestCase` rather than on either of
/// them because the split of 2026-08-30 left it needed on both sides — a layout test authors a curve
/// for the band to draw and a gesture test authors one to edit. `fileprivate`, so it stays this
/// file's business and does not become a third thing to keep in step.
private extension PaintUITestCase {

    /// The two values `authorAnAnimatedBrightnessCurve` left on the track.
    struct AuthoredCurve {
        /// The grade's stored default, keyed onto the earlier mark by the seed arm.
        let start: Double
        /// What the slider drag left, keyed onto the later one.
        let end: Double
    }

    /// **A layer with one genuinely animated effect channel, authored the only way the app can author
    /// one: two keyframe marks and one slider drag.**
    ///
    /// This is the `.seedAndKey` arm of `KeyframeControl.write` — marks at both frames, the playhead
    /// on the later one, and a channel with no curve yet — so one drag puts the *old* value on the
    /// mark below and the new one under the finger, which is two keys of different values and
    /// therefore an animation by `AnimationCurve.isAnimated`, the predicate the band's channel list
    /// uses. There is no shorter route: the graph editor needs a curve to edit and cannot be the thing
    /// that creates the first one.
    ///
    /// - Returns: the two values the two keys hold, read off the slider rather than assumed, so a
    ///   test can compute where on the band each of them is drawn.
    func authorAnAnimatedBrightnessCurve(_ app: XCUIApplication,
                                         from: Int, to: Int) throws -> AuthoredCurve {
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        // The helper leaves the layer's options open inside the rail, and the rail covers the
        // timeline — so the panel is toggled shut before any of the taps below.
        app.buttons["toolbar.layersButton"].tap()

        let block = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "The effect layer should have a track")
        let cel = try XCTUnwrap(readCel(app, layerIndex: 1, celIndex: 0))
        func mark(_ frame: Int) {
            // A frame's column as a fraction of the block, which reaches past its right edge for a
            // frame the block does not cover — the only handle a test has on an empty slot, and
            // `testAnEmptySlotCanStillBeGivenAKeyframe`'s technique.
            let slot = block.coordinate(withNormalizedOffset:
                CGVector(dx: (Double(frame) + 0.5) / Double(cel.length), dy: 0.5))
            let add = app.buttons["timeline.menu.Add Keyframe"]
            // **One tap or two, decided by what happened rather than assumed.**
            // `handleTapOnCel`/`handleTapOnGap` are a two-stage contract: a tap on a frame that is
            // *not* already selected only selects it, and the menu comes up on the next one. So a
            // frame the playhead is already sitting on — frame 0 on a fresh document — needs a
            // single tap, and tapping twice there opens the menu and dismisses it again, which is
            // indistinguishable from the menu never having opened.
            slot.tap()
            if !add.waitForExistence(timeout: 2) {
                slot.tap()
                XCTAssertTrue(add.waitForExistence(timeout: 5),
                              "No Add Keyframe on frame \(frame)'s menu")
            }
            add.tap()
        }
        mark(from)
        mark(to)
        XCTAssertEqual(app.otherElements["timeline.keyMarkers.1"].value as? String,
                       "\(from)|\(to)",
                       "PREMISE: two marks carrying no channel, which is what puts the next slider edit in seedAndKey")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.effectSettings"].tap()
        let slider = app.sliders["effectSettings.brightness"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(Double(try XCTUnwrap(slider.value as? String)))
        // Far from the middle, so the new value cannot land on the old one and leave a flat curve —
        // which `AnimationCurve.isAnimated` would refuse to call an animation and the band would not
        // draw at all.
        slider.adjust(toNormalizedSliderPosition: 0.9)
        let after = try XCTUnwrap(Double(try XCTUnwrap(slider.value as? String)))
        XCTAssertNotEqual(after, before, accuracy: 0.05,
                          "The slider did not move, so no key was written")

        app.buttons["layerOptions.subMenuBack"].tap()
        app.buttons["toolbar.layersButton"].tap()
        return AuthoredCurve(start: before, end: after)
    }
}
