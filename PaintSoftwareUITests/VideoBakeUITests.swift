import XCTest

/// **XCUITest coverage for VIDEO.md §8 stage 8 — real, synthetic touches through the "Bake to
/// Images" row**, on a video seeded via `-uiTestSeedVideo` (see `PaintSoftware/Debug/UITestSeeds.swift`).
///
/// Getting a video onto the canvas through the real system `PhotosPicker` is not something any test
/// in this suite does for *any* feature — `VideoImportLogicTests`'s own header explains why, and
/// `UITestSeeds`'s doc comment carries the argument one step further for this stage specifically.
/// That is this test's one non-organic step. Everything after it — opening the video block's own
/// menu, reading and tapping "Bake to Images", answering the cost-disclosure alert, and counting
/// what the timeline shows afterward — is driven by the same synthetic touches every other timeline
/// UI test in this suite uses, which is what makes this a genuine reachability test rather than a
/// second copy of the logic tier's assertions.
final class VideoBakeUITests: PaintUITestCase {

    /// `.keepAlways` rather than the `.deleteOnSuccess` this suite's other `attachScreen` copies
    /// use — this stage's own bar asks for the screenshots to actually be looked at, not just kept
    /// on hand for a failure that did not happen.
    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Two-stage tap: the first only selects the block/frame, the second (landing on what is
    /// already selected) opens its menu — `TimelineTrackView.Coordinator.handleTapOnCel`'s own
    /// documented contract, and `TimelineAndUndoUITests`'s gap-menu test uses the identical
    /// double-tap for the sibling `.gap` case.
    private func openBlockMenu(_ app: XCUIApplication, layerIndex: Int, celIndex: Int) {
        let block = app.otherElements["timeline.cel.\(layerIndex).\(celIndex)"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        block.tap()
    }

    /// **Cold start to a baked timeline, with nothing skipped.** From a fresh document: a plain
    /// block offers no Bake row at all (the row must not leak onto ordinary drawings); the seeded
    /// video's own block offers it; tapping it, answering the confirmation, and reading the
    /// timeline afterward are the whole of "what does the artist do next" for this feature.
    func testBakeToImagesIsReachableOnlyOnAVideoBlockAndBakingSplitsTheTimeline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-uiTestSeedVideo"]
        XCTAssertTrue(launchIntoEditor(app))

        // Setup: `UITestSeeds.seedVideoIfRequested` ran inside `createCanvas`, after
        // `addVectorLayer` already put a plain drawing on layer 0 — so the video is layer 1's own
        // new layer, exactly as `insertVideo` always creates one.
        guard let seeded = readCel(app, layerIndex: 1, celIndex: 0) else {
            return XCTFail("Setup: -uiTestSeedVideo should have put a video block on layer 1.")
        }
        XCTAssertEqual(seeded.start, 0)
        XCTAssertGreaterThan(seeded.length, 1, "Setup: a one-frame block would make the split moot to look at.")
        attachScreen("01-seeded-video-block-on-a-fresh-document")

        // An ordinary drawing has nothing to bake, and the row must say so by not existing —
        // `celHoldsVideo`'s own gate in `AnimationTimeline`.
        openBlockMenu(app, layerIndex: 0, celIndex: 0)
        XCTAssertFalse(app.buttons["timeline.menu.Bake to Images"].exists,
                       "An ordinary drawing block must not offer Bake to Images.")
        // Every anchored timeline menu in this app closes on a canvas touch.
        app.otherElements["canvas.host"].tap()

        // The video's own block offers it — this is the row an artist taps next.
        openBlockMenu(app, layerIndex: 1, celIndex: 0)
        let bakeRow = app.buttons["timeline.menu.Bake to Images"]
        XCTAssertTrue(bakeRow.waitForExistence(timeout: 5),
                     "The video block's menu should offer \"Bake to Images\".")
        attachScreen("02-video-blocks-menu-offers-bake-to-images")
        bakeRow.tap()

        // KEYFRAMES §6's cost disclosure — Cancel first, to prove the alert genuinely gates the
        // bake rather than the tap having already run it.
        let confirm = app.alerts["Bake to Images?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                     "Bake is destructive-but-undoable and KEYFRAMES §6 asks for a cost disclosure before it runs.")
        attachScreen("03-cost-disclosure-confirmation")
        confirm.buttons["Cancel"].tap()
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.length, seeded.length,
                      "Cancel must leave the block exactly as it was.")

        openBlockMenu(app, layerIndex: 1, celIndex: 0)
        app.buttons["timeline.menu.Bake to Images"].tap()
        let confirmAgain = app.alerts["Bake to Images?"]
        XCTAssertTrue(confirmAgain.waitForExistence(timeout: 5))
        confirmAgain.buttons["Bake"].tap()

        // What the artist sees afterward: one cel per document frame the block covered, each
        // findable at its own index and one frame long — the drawing's own timeline, not merely a
        // model that says so underneath it.
        for frame in 0..<seeded.length {
            guard let cel = readCel(app, layerIndex: 1, celIndex: frame) else {
                return XCTFail("Expected a baked cel at index \(frame) after Bake to Images.")
            }
            XCTAssertEqual(cel.start, frame, "Baked cel \(frame) should start at document frame \(frame).")
            XCTAssertEqual(cel.length, 1, "Baked cel \(frame) should be exactly one document frame.")
        }
        XCTAssertFalse(app.otherElements["timeline.cel.1.\(seeded.length)"].exists,
                       "There should be exactly \(seeded.length) resulting cels, no more.")
        attachScreen("04-timeline-after-bake-one-cel-per-frame")

        // And the artist's very next move — undo — takes back the *whole* bake in one press,
        // exactly as it took one menu tap to make. `readCel` answers nil once the array shrinks
        // back to one entry at index 0's own slot reappearing as the sole block.
        app.buttons["sideToolbar.undoButton"].tap()
        let restored = try XCTUnwrap(readCel(app, layerIndex: 1, celIndex: 0),
                                     "Undo should restore the single video block in one press.")
        XCTAssertEqual(restored.length, seeded.length)
        XCTAssertFalse(app.otherElements["timeline.cel.1.1"].exists,
                       "A single undo press must collapse every baked cel back to one block.")
        attachScreen("05-one-undo-press-restores-the-single-video-block")
    }
}
