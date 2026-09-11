import XCTest

/// The live take, driven — KEYFRAMES.md §5, stage 7, rebuilt to the owner's ruling of 2026-09-09.
///
/// **`RecordingLogicTests` is the model half and it is complete; this class exists because the model
/// being right is not the bar.** Three features shipped to the owner's iPad in one pass that could
/// not be used at all, each with a green fast tier, and the common cause was structural: every
/// assertion reached the model directly and asserted a stored value, so the suite was blind by
/// construction to whether an artist could *reach* the feature.
///
/// So each test here starts from a **cold launch into a new document**, and driving it is what
/// corrected the model half rather than merely confirming it: a new document turned out to be a
/// **twelve**-frame scene, not the one-frame scene a fixture had implied, which moved
/// `RecordingRefusal.noScene` from "the case an artist meets first" to "a case an artist can
/// shorten a document into". A test that builds its own scene cannot notice how long the scene is
/// when nobody built one.
///
/// **The ruling this class was rewritten for is that arming and starting are two acts**, and the
/// owner's complaint was about the first one doing the second's job: *"Currently when you press
/// record it instantly plays the playback, giving you no time to adjust the sliders or move box."*
/// So the assertion that matters most here is a **negative** one — press record, wait, and find the
/// playhead exactly where it was — and it is a negative assertion this suite could not have made
/// before, because the old behaviour was over in half a second.
///
/// **XCUITest cannot synthesise an Apple Pencil, only a finger**, so "put your pencil on a slider"
/// is driven here as a finger on a slider. That is not a downgrade of the thing under test: the
/// trigger is `Slider`'s own `onEditingChanged(true)`, which SwiftUI raises for any touch-down and
/// which the app does not gate on `UITouch.type` anywhere on this path. Nothing in this feature asks
/// what kind of point it is.
final class RecordingUITests: PaintUITestCase {

    /// **Where the record button lives, which the owner rejected outright and which is therefore a
    /// thing to pin rather than a detail.**
    ///
    /// *"Right now I dont like where the record button is… You open up graph editor and it displays
    /// the record button option."* It used to sit in `transportControls` beside play, on the
    /// argument that recording is a transport state; it is a control of the graph editor now, and
    /// the two halves of that are both asserted here — it is **not** on screen with the band closed,
    /// and it **is** with the band open, in both timeline states (§2.22's both-bars rule, which this
    /// very strip has already broken once).
    func testTheRecordButtonBelongsToTheGraphEditorAndIsDrawnInBothTimelineStates() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document, no prior state")

        let graphEditor = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(graphEditor.waitForExistence(timeout: 5),
                      "The way in is on screen from a cold start, with nothing made first")

        let record = app.buttons["timeline.recordButton"]
        XCTAssertFalse(record.exists,
                       "The recorder is a control of the graph editor, so it is not on the transport bar")

        graphEditor.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "Opening the graph editor is what displays the record button — the owner's own words")
        XCTAssertEqual(record.value as? String, "idle", "…and nothing is armed until it is pressed")

        let collapse = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "…and it is still there once the timeline is collapsed (§2.22)")

        graphEditor.tap()
        XCTAssertFalse(record.exists,
                       "Closing the band takes the button with it — an armed mode with nothing on "
                       + "screen to say so is the trap §2.1 was withdrawn over")
    }

    /// **The whole of the owner's ruling, as one negative assertion.**
    ///
    /// *"You press the record button and it turns blue, but nothing happens."* The operand is the
    /// frame counter, read before the press and again a full second and a half afterwards — which is
    /// three times as long as the entire take a new twelve-frame document could hold at 24 fps under
    /// the old behaviour. **If arming still started playback this assertion could not pass**, and
    /// that is what makes it worth its seconds: it is the exact defect the ruling is about.
    ///
    /// The other half is that the artist can *see* the arm and is told what to do with it. The blue
    /// is exposed as the button's value; the instruction is the banner, because the surface that
    /// starts a take is in another panel and no wording on this button could reach it.
    func testPressingRecordArmsVisiblyAndMovesNothing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["timeline.graphEditorButton"].tap()

        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(readFrameLabel(app), "Setup: the frame counter is readable")

        record.tap()

        XCTAssertEqual(record.value as? String, "armed",
                       "A mode the artist is in must be a mode they can see they are in")

        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "Arming says what to do next — the trigger is a slider in another panel and "
                      + "nothing on this button could have said so")
        XCTAssertEqual(notice.value as? String, "recordingArmed",
                       "…and it is the armed notice, not a refusal")

        // Long enough that the old behaviour's entire take — twelve frames at 24 fps, 0.46 s — would
        // have run three times over and parked the playhead at the end of the scene.
        Thread.sleep(forTimeInterval: 1.5)

        let after = try XCTUnwrap(readFrameLabel(app))
        XCTAssertEqual(after.current, before.current,
                       "Nothing happened: the playhead is exactly where the artist left it")
        XCTAssertEqual(record.value as? String, "armed", "…and it is still waiting for them")

        record.tap()
        XCTAssertEqual(record.value as? String, "idle", "A second press is the way back out")
    }

    /// **The feature end to end, from a document with nothing in it: arm, land, and read the curve
    /// off the timeline.**
    ///
    /// This is the test the three unusable features of 2026-09-08 did not have. Every step is one an
    /// artist performs, in the order they perform it, from a cold start — and the closing assertions
    /// are on what is **drawn**: the key markers under the layer's track (a curve arrived), the
    /// slider's own value (the take's base was a scratch pad and was put back), and the frame
    /// counter (playback ran, which is the half the owner said was missing from the *timing*).
    ///
    /// **The scene is lengthened and the rate dropped to 8 fps first, and both are the artist's own
    /// controls rather than a test hook.** A new document at 24 fps holds a take of 0.46 s, which is
    /// shorter than a slider drag — so a test that skipped this would be asserting about a take that
    /// ended before the finger moved, and would report `.noMotion` for reasons that have nothing to
    /// do with the feature.
    func testArmingThenLandingOnASliderRunsATakeAndLeavesACurveOnTheTimeline() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // A longer scene, made the way an artist makes one: two taps on an empty slot past the end
        // of the first block, then Add Drawing. The first tap selects the frame, the second raises
        // the menu on the frame already selected.
        let block = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let cel = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0))
        let slot = block.coordinate(withNormalizedOffset:
            CGVector(dx: (Double(cel.length) + 6.0) / Double(cel.length), dy: 0.5))
        slot.tap()
        slot.tap()
        let addDrawing = app.buttons["timeline.menu.Add Drawing"]
        XCTAssertTrue(addDrawing.waitForExistence(timeout: 5), "PREMISE: this is an empty slot's menu")
        addDrawing.tap()

        // 8 fps, one tap on a preset — §2.7's editable rate, used here for what it is for.
        app.buttons["timeline.frameRateButton"].tap()
        let preset = app.buttons["frameRate.preset.8"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        app.buttons["timeline.frameRateButton"].tap()   // close the panel

        // A graded layer to record onto. This is also the only way to *get* a recordable channel: a
        // fresh document has none, which is the closed loop this feature has to open rather than sit
        // behind.
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        app.buttons["toolbar.layersButton"].tap()       // the rail covers the timeline

        app.buttons["timeline.graphEditorButton"].tap()
        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "The graph editor displays the record button — this is the artist's entry")

        // **The marker band hides itself when a layer has no keys** (`isHidden = runs.isEmpty`), so
        // its absence here is a real signal rather than the "asserting `exists` on a hidden view"
        // trap: the band is genuinely out of the accessibility tree until something puts a key on
        // this track.
        let markers = app.otherElements["timeline.keyMarkers.1"]
        XCTAssertFalse(markers.exists,
                       "PREMISE: this layer animates nothing yet, so anything below is the take's doing")

        // **Park the playhead at the top before arming**, so that "playback ran" has somewhere to be
        // read from. Adding a drawing left the playhead on the scene's *last* frame, and a take
        // replays from the entry frame and ends on that same last frame — so the counter would read
        // 18 before and 18 after, and an assertion on it would say nothing while looking as though
        // it said everything.
        app.buttons["timeline.toStartButton"].tap()
        let framesBeforeTheTake = try XCTUnwrap(readFrameLabel(app))
        XCTAssertEqual(framesBeforeTheTake.current, 1, "PREMISE: the playhead is at the top")

        record.tap()
        XCTAssertEqual(record.value as? String, "armed", "Setup: armed, and nothing has moved")

        // Now the artist walks to the surface. The arm has to survive the walk, or the feature is
        // unusable for the reason it was rebuilt: the slider is two menus away from the button.
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.effectSettings"].tap()
        let slider = app.sliders["effectSettings.brightness"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertEqual(record.value as? String, "armed",
                       "The arm survived opening two panels — an arm that dropped on the way to the "
                       + "surface would make the feature unreachable")
        // **The landing.** One drag, which is touch-down, motion and lift — the take begins on the
        // first of those and playback starts with it.
        slider.adjust(toNormalizedSliderPosition: 0.9)

        // The take ends itself at the end of the scene, and the button going back to white is how the
        // artist knows — the same control they armed, in the same place, which is the argument for
        // it carrying all three states rather than only two.
        let idleAgain = expectation(for: NSPredicate(format: "value == 'idle'"), evaluatedWith: record)
        wait(for: [idleAgain], timeout: 30)

        XCTAssertTrue(markers.waitForExistence(timeout: 5),
                      "The key-marker band is drawn on this track now, where it was not before")
        let landed = (markers.value as? String) ?? ""
        XCTAssertTrue(landed.contains("|"),
                      "A curve landed on the timeline with at least two keys — the take's whole "
                      + "output, read off what is drawn rather than off the model. Got \"\(landed)\"")

        // **"…then putting it on the graph"** — the owner's own last clause, asserted where the
        // artist would look for it. The row's *value* is the second half of it, because a row can
        // exist over a curve that animates nothing and says so with a `,flat` suffix — so the
        // existence of a row is not by itself the claim being made.
        //
        // **The slider's value is deliberately not the assertion here, and that is a correction
        // rather than an omission.** It was, and it read 1.8003 against the 1.0 the base was
        // restored to — because the knobs show the value *resolved at the playhead*, so after a
        // successful take the slider correctly shows the curve. The base restore is a model fact
        // with a model operand, and `RecordingLogicTests` is where it is pinned; asserting it
        // through a control that displays something else would have been a test of the wrong two
        // operands.
        app.buttons["timeline.graphChannelsButton"].tap()
        let channelRow = app.buttons["timeline.graphChannels.brightnessContrast.brightness"]
        XCTAssertTrue(channelRow.waitForExistence(timeout: 5),
                      "The graph editor lists the channel the take wrote — it listed nothing before")
        XCTAssertEqual(channelRow.value as? String, "on",
                       "…and it is animated rather than a flat curve wearing a row (a flat one "
                       + "would read \"on,flat\")")

        let framesAfter = try XCTUnwrap(readFrameLabel(app))
        XCTAssertGreaterThan(framesAfter.current, framesBeforeTheTake.current,
                             "Playback ran with the take, which is the half the owner said arming "
                             + "was stealing the time for")
    }

    /// **§5's second surface, end to end from a document with nothing in it: arm, put a finger on the
    /// Move box, and read the curve off the graph** — KEYFRAMES.md §5, the last unbuilt half of §8
    /// stage 7.
    ///
    /// Every step is one an artist performs, in the order they perform it, and the question *"what does
    /// the artist do next?"* has an on-screen answer at each one: the Add menu makes the layer, the
    /// layer's own mode picker makes it a transformation layer, **its Move row raises the box**, the
    /// graph editor's record button arms, and the banner says a Move box is one of the things to put a
    /// finger on. Nothing here is a fixture.
    ///
    /// **The closing assertions are on what is drawn, not on what is stored.** The graph band publishes
    /// its own content — `containerPose.x:0,3,9` means *this channel is animated and these are its
    /// keyed frames* — and the key-marker band under the track is hidden outright when a layer has no
    /// keys, so its presence is a queryable fact rather than a value to parse. Both would go red if the
    /// model stayed right and the affordance disappeared, which is the assertion this repo's three
    /// unusable features were missing.
    ///
    /// **The rate is dropped to 8 fps**, the artist's own control: a new document at 24 fps holds a take
    /// of 0.46 s, which is shorter than a box drag, so the take would end before the finger moved.
    func testArmingThenLandingOnTheMoveBoxRunsATakeAndLeavesAPoseCurveOnTheGraph() throws {
        let app = XCUIApplication()
        // The notice is read below, and `CanvasNotice.duration` is 2.6 s — a self-dismissing banner is
        // a race no `waitForExistence` can win.
        app.launchArguments += ["-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document, no prior state")

        // 8 fps, one tap on a preset — §2.7's editable rate, used here for what it is for.
        app.buttons["timeline.frameRateButton"].tap()
        let preset = app.buttons["frameRate.preset.8"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        app.buttons["timeline.frameRateButton"].tap()   // close the panel

        // A transformation layer, made the only way an artist can make one: the + menu's own entry.
        // This is also the only way to *get* a recordable pose channel — a fresh document has none,
        // which is the closed loop this surface has to open rather than sit behind.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        app.buttons["toolbar.layersButton"].tap()       // the rail covers the timeline

        // **The marker band hides itself when a layer has no keys**, so its absence here is a real
        // signal rather than the "asserting `exists` on a hidden view" trap.
        let markers = app.otherElements["timeline.keyMarkers.1"]
        XCTAssertFalse(markers.exists,
                       "PREMISE: this layer animates nothing yet, so anything below is the take's doing")

        app.buttons["timeline.toStartButton"].tap()
        let framesBefore = try XCTUnwrap(readFrameLabel(app))
        XCTAssertEqual(framesBefore.current, 1, "PREMISE: the playhead is at the top")

        app.buttons["timeline.graphEditorButton"].tap()
        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "The graph editor displays the record button — this is the artist's entry")
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        XCTAssertEqual(band.value as? String, "empty",
                       "PREMISE: the band has no curve on it before the take")

        record.tap()
        XCTAssertEqual(record.value as? String, "armed", "Setup: armed, and nothing has moved")
        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "Arming says what to do next — the surface is in another panel and nothing on "
                      + "this button could have said so")
        // The code rather than the sentence, which is `CanvasNoticeBanner`'s own rule: the wording is
        // the half most likely to be revised. That it *names the Move box* is a model fact with a model
        // operand, and `MoveBoxRecordingLogicTests` is where it is pinned.
        XCTAssertEqual(notice.value as? String, "recordingArmed")

        // **Now the artist raises the box, from the toolbar's own Move glyph.**
        // `CanvasManager.beginMove` routes a transformation layer straight to `beginContainerPoseMove`,
        // so this button and Transform mode's `layerOptions.transformMove` row are the same control —
        // `transformMoveRow`'s own doc says so, and the artist who learns either has learned the other.
        //
        // **This route rather than the panel row, and that is a finding rather than a convenience.**
        // MEASURED while driving this: **closing the layer rail commits a floating Move box.** The box
        // is raised from inside the layer options panel, so an artist who tidies the screen before
        // dragging has already settled it. That is pre-existing behaviour, identical for an unrecorded
        // Move, and nothing in this pass touches it — but it cost this test two runs, both of which
        // failed 30 s later pointing at the record button, a mile from the cause. The toolbar glyph
        // needs no panel open and is the route to drive.
        app.buttons["toolbar.moveButton"].tap()
        let moveBar = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(moveBar.waitForExistence(timeout: 5),
                      "The box is up, which the Move bar is how an artist can tell")
        XCTAssertEqual(record.value as? String, "armed",
                       "The arm survived the walk to the surface — two panels, a mode change and a "
                       + "tool button. An arm that dropped on the way would make this unreachable")
        XCTAssertEqual(try XCTUnwrap(readFrameLabel(app)).current, 1,
                       "…and still nothing has moved: arming is not starting")

        // **The landing.** One gesture — touch-down, motion, lift. The take begins on the first of
        // those and playback starts with it; the box is the document rect, so a drag anywhere inside
        // the canvas is a drag of the box.
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // **Both ends are computed from `visibleCanvasBounds`, not guessed**, and that is not
        // fastidiousness either. `canvas.host` is the whole host *including the black surround*, so a
        // flat fraction of it lands in the letterbox on some frame proportions — and a touch out there
        // is a touch *outside* the box, which `handleTapOutside` correctly reads as the tap-away that
        // commits it. Same symptom, second cause.
        let inside = visibleCanvasBounds(canvas)
        let span = inside.maxX - inside.minX
        let vspan = inside.maxY - inside.minY
        let start = canvas.coordinate(withNormalizedOffset:
            CGVector(dx: inside.minX + span * 0.3, dy: inside.minY + vspan * 0.35))
        let end = canvas.coordinate(withNormalizedOffset:
            CGVector(dx: inside.minX + span * 0.75, dy: inside.minY + vspan * 0.5))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)

        // **The take ends itself at the end of the scene and takes the box with it**, which is the first
        // thing the artist sees: the Move bar goes. A box left up would have had its own commit replace
        // the whole recorded track with a single key the moment they tapped away.
        let boxGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: moveBar)
        wait(for: [boxGone], timeout: 30)

        XCTAssertEqual(record.value as? String, "idle",
                       "The take is over and the button says so — the same control they armed")
        XCTAssertGreaterThan(try XCTUnwrap(readFrameLabel(app)).current, framesBefore.current,
                             "Playback ran with the take — the owner's *\"playback automatically "
                             + "starts\"*")

        // **\"…then putting it on the graph\"** — the owner's own last clause, read off the band's own
        // published content rather than off the model. `channel:frames` means animated; `channel~frames`
        // would mean a flat curve wearing a row, which is the state this assertion has to exclude.
        let drawn = (band.value as? String) ?? ""
        XCTAssertTrue(drawn.contains("containerPose."),
                      "The graph editor draws the pose channel the take wrote. Got \"\(drawn)\"")
        let animated = drawn.split(separator: "|").first { $0.contains(":") }
        let keyed = try XCTUnwrap(animated, "At least one pose channel is animated, not flat. "
                                  + "Got \"\(drawn)\"")
        XCTAssertTrue(keyed.contains(","),
                      "…and it carries more than one key, which is what makes it an animation rather "
                      + "than a pose. Got \"\(keyed)\"")

        XCTAssertTrue(markers.waitForExistence(timeout: 5),
                      "The key-marker band is drawn on this track now, where it was not before")
        XCTAssertFalse(((markers.value as? String) ?? "").isEmpty,
                       "…and it names the frames it is drawing markers on")
    }
}
