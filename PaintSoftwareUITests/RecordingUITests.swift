import XCTest

/// The live take, driven — KEYFRAMES.md §5, stage 7.
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
final class RecordingUITests: PaintUITestCase {

    /// **Cold-start reachability, and §2.22's both-bars rule in the same test.**
    ///
    /// The record button lives in `transportControls`, which `collapsedBar` and `miniToolbar` both
    /// render — the arrangement that section exists to warn about, since a control added to one is
    /// invisible in the other. The frame-rate readout was in one bar only until this stage, so the
    /// warning is not hypothetical on this very strip.
    func testTheRecordButtonIsReachableFromAColdStartInBothTimelineStates() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document, no prior state")

        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "A new document offers the recorder without the artist making anything first")
        XCTAssertEqual(record.value as? String, "idle", "…and nothing is armed until it is pressed")

        let collapse = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()

        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "…and it is still there once the timeline is collapsed (§2.22)")
    }

    /// **The first press an artist ever makes, and what it tells them.**
    ///
    /// A new document is a twelve-frame scene, so the take an untouched document can hold is half a
    /// second at 24 fps and it ends having caught nothing. **That is by design and not a defect** —
    /// §5's take runs over the scene, and `tickPlayback` ends it at the last frame deliberately —
    /// but it does mean the artist's very first press is answered by a refusal, so the two things
    /// worth pinning are that the refusal is *said* and that the recorder is left in a state they
    /// can act from rather than armed against a transport that has already stopped.
    ///
    /// **Which refusal it is belongs to the model, not here**, and that is the banner's own design
    /// rather than a gap: it exposes `CanvasNotice.code` and not the sentence, because the wording
    /// is the half most likely to be revised, and all five recording refusals share one code.
    /// `RecordingLogicTests` is where each case is pinned. What this test owns is that *something
    /// is said* and that the button is left somewhere the artist can go on from.
    func testTheFirstPressOnANewDocumentRefusesVisiblyAndLeavesTheRecorderIdle() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()

        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "A take that caught nothing says so — the artist has pressed a button and "
                      + "must not be left guessing whether the feature is broken")
        XCTAssertEqual(notice.value as? String, "recordingRefused",
                       "The banner names the kind by `CanvasNotice.code`, not by its wording")
        XCTAssertEqual(record.value as? String, "idle",
                       "…and the recorder is idle rather than armed against a stopped transport")
    }

    /// **A take on a real scene arms visibly, and ends itself rather than stranding the artist.**
    ///
    /// The armed state is a red dot the artist can see, which is §2.1's surviving finding: a mode
    /// that is not advertised is undiscoverable. The second half is the one a model test cannot
    /// reach — the take ends at `playbackEndFrame` on a clock this test does not drive, and what
    /// must be true afterwards is that the *button* went back to idle.
    ///
    /// **The frame-rate panel's mid-take hold is deliberately not asserted here.** A scene an
    /// XCUITest can build by tapping is a handful of frames, so the take is over in under half a
    /// second and any assertion about what the panel looks like *during* it is a race — the shape
    /// this repo has already filed once, where an expectation whose window closes before the
    /// behaviour can occur measures the harness. `RecordingLogicTests` holds that rule on the model.
    /// The drawn half was confirmed by driving it and looking: at 8 fps over a 29-frame scene the
    /// panel showed both arrows dimmed, every preset but the current one dimmed, and the caption
    /// reading "Held while recording — a take is timed at one rate." What is checked here is that
    /// caption's *idle* wording, which fails if the control is removed.
    func testATakeOnARealSceneArmsVisiblyAndReturnsTheRecorderToIdleWhenItEnds() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // A scene to record over. Two taps on an empty slot for the reason a block's menu needs two:
        // the first selects the frame, the second raises the menu on the frame already selected.
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

        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertEqual(record.value as? String, "recording",
                       "A mode the artist is in must be a mode they can see they are in")

        let idleAgain = expectation(for: NSPredicate(format: "value == 'idle'"),
                                    evaluatedWith: record)
        wait(for: [idleAgain], timeout: 15)
        XCTAssertEqual(record.value as? String, "idle",
                       "The take ends with the scene and the button says so — an artist is never "
                       + "left holding a recorder that is armed against a stopped transport")

        app.buttons["timeline.frameRateButton"].tap()
        XCTAssertEqual(app.staticTexts["frameRate.caption"].label, "frames per second",
                       "…and the panel's caption is back to its idle wording")
    }
}
