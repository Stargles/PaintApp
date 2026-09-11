import XCTest

/// **Can an artist actually place a keyframe on a folder?** — TODO (21)'s entry point, driven from a
/// new document the way the owner drove the three features that shipped unusable on 2026-09-03.
///
/// **Why this file exists at all, given `FolderKeyframeEntryLogicTests`.** Every assertion in that
/// file reaches `CanvasManager` directly, and `addKeyframe(.folder(…))` already worked before this
/// pass — the gap was that nothing on screen called it. So the fast tier was blind to this defect *by
/// construction*, which is the exact failure CLAUDE.md's "a feature is not finished because its model
/// is correct" section records. The assertions below are therefore only ever on **values controls
/// expose**: the keyframe summary the panel draws, the frame the Add row says it will write, and the
/// folder row's own opacity slider, which reads `LayerFolder.opacity(atFrame: currentFrame)` and so
/// reports the *resolved* value rather than the stored one.
///
/// **`exists` is not used as an assertion about behaviour anywhere here.** A hidden element still
/// resolves, which is how a test in this repo passed with a whole feature deleted; the two places
/// presence *is* the fact — Remove Keyframe being offered or not — are paired with a value assertion
/// on the same surface so a build that drew the row unconditionally still goes red.
final class FolderKeyframeEntryUITests: PaintUITestCase {

    // MARK: - Helpers

    /// The keyframe summary the folder's options panel draws — §2.28's union, as the panel exposes it.
    /// "none", or the frames comma-separated.
    private func keyframeSummary(_ app: XCUIApplication) -> String {
        app.staticTexts["layerOptions.folderKeyframes"].value as? String ?? "?"
    }

    /// Opens the group's options panel and waits for the Add Keyframe row to be tappable.
    private func openFolderOptions(_ app: XCUIApplication, named name: String) {
        XCTAssertTrue(tapWhenHittable(app.buttons["layerPanel.folder.\(name).options"],
                                      "The folder row's options button"),
                      "Without the options panel there is no keyframe row to reach")
        XCTAssertTrue(app.buttons["layerOptions.addKeyframe"].waitForExistence(timeout: 5), """
            `layerOptions.addKeyframe` never appeared in the folder's options panel. That row is the \
            only entry point a folder has — the timeline has no folder menu — so its absence means \
            an artist cannot place a keyframe on a group at all, which is the defect this pass fixes.
            """)
    }

    private func closeFolderOptions(_ app: XCUIApplication) {
        XCTAssertTrue(tapWhenHittable(app.buttons["layerOptions.close"],
                                      "The options panel's close button"),
                      "The panel has to close before the centred transport controls are reachable")
    }

    /// Walks the playhead forward `count` frames with the transport button, asserting it arrived.
    /// `timeline.frameLabel` is 1-based as displayed, so frame N reads "Frame N+1/…".
    private func stepForward(_ app: XCUIApplication, _ count: Int, toFrame frame: Int) {
        let next = app.buttons["timeline.stepForwardButton"]
        for _ in 0..<count {
            XCTAssertTrue(tapWhenHittable(next, "The timeline's step-forward button"),
                          "The playhead has to be movable for a keyframe at a second frame to exist")
        }
        XCTAssertEqual(readFrameLabel(app)?.current, frame + 1,
                       "The playhead must be on frame \(frame); every keyframe assertion below is "
                       + "about which frame the panel wrote to")
    }

    private func goToStart(_ app: XCUIApplication) {
        XCTAssertTrue(tapWhenHittable(app.buttons["timeline.toStartButton"],
                                      "The timeline's to-start button"),
                      "Frame 0 has to be reachable to read the first keyframe's value")
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

    /// **The owner's four steps on a group, from a brand-new document**: make a folder, place a key on
    /// it, change something, place another, and see the animation. Every step's answer is read off the
    /// screen.
    ///
    /// The operands, in order:
    ///
    ///  * **`layerOptions.folderKeyframes`' value against the keyframes placed so far.** It is
    ///    `keyframeFrames(of:)`' output — §2.28's one accessor — so this is the panel and the model
    ///    being asked to agree, on a surface the artist reads. **It is a read-back of the same
    ///    expression the press wrote through**, so it catches a press that did nothing and not one
    ///    that went to the wrong target. Which is which was settled by mutation, not by reading.
    ///  * **The timeline's per-row marker bands** — `timeline.folderTrack.<name>.keys` against
    ///    `timeline.keyMarkers.<layerIndex>`. Which *row* grew a diamond is a fact the panel does
    ///    not compute, so this is the operand that distinguishes "the group was keyed" from "the
    ///    current layer was keyed", and the one that kills that mutation. **These bands have existed
    ///    since stage 3b and nothing had ever read them**; they were assumed unreachable, because the
    ///    row views they sit inside are themselves accessibility elements. They are reachable.
    ///  * **`layerOptions.addKeyframe`' value against the playhead.** The row says which frame a press
    ///    writes to. A build that captured the frame when the panel opened, or that keyed frame 0
    ///    always, fails at step 3 with no other symptom.
    ///  * **Remove Keyframe's presence against whether the playhead is on a keyframe** — checked in
    ///    both directions, on frame 0 where there is one and frame 4 where there is not, so an
    ///    unconditional row fails the second half.
    ///  * **The folder row's opacity slider at three frames against the two values the artist set.**
    ///    That slider reads `folder.opacity(atFrame: currentFrame)`, so the reading at frame 2 — which
    ///    is neither value — can only be right if a curve exists *and* is resolved. It is the
    ///    assertion that distinguishes "the animation is there" from "two numbers were stored".
    ///
    /// **Step 5 is the one that makes the rest attributable.** Before the second mark, the drag has
    /// only *held* its previous value (§2.27), so the slider reads the faded number at frame 0 too —
    /// there is no animation yet. Asserting that first is what makes the difference after the second
    /// mark the second mark's doing rather than the drag's.
    func testAGroupsFirstKeyframeCanBePlacedFromItsOptionsAndTheAnimationIsExposed() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "The editor has to open before anything can be keyed")

        // 1. Make a folder.
        openLayerPanel(app)
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5),
                      "A group has to exist before it can carry a keyframe")

        // 2. Place a key on it — and before pressing, read what the row promises.
        openFolderOptions(app, named: "Folder 1")
        XCTAssertEqual(keyframeSummary(app), "none",
                       "A fresh group carries no keyframes, and the panel says so")
        XCTAssertEqual(app.buttons["layerOptions.addKeyframe"].value as? String, "0",
                       "The row names the playhead's frame, which is 0 on a new document")
        XCTAssertEqual(app.staticTexts["layerOptions.folderKeyframes"].label, "Frame 1 · no keyframes yet",
                       "The caption is shown 1-based, like the ruler's own 'Frame 1/…' — since "
                       + "2026-09-11, the model's frame 0 reads as 'Frame 1' here too")
        XCTAssertFalse(app.buttons["layerOptions.removeKeyframe"].exists,
                       "Nothing to remove yet, so the row is absent — the half of this pair that a "
                       + "build drawing it unconditionally still passes")
        attach(app, "folder-keyframe-row-before")

        app.buttons["layerOptions.addKeyframe"].tap()

        XCTAssertEqual(keyframeSummary(app), "0", """
            The panel's keyframe summary must name frame 0 after the press — a press that wrote \
            nothing leaves this at "none".

            **It cannot catch a press that wrote to the wrong target, and that was mutation-tested \
            rather than assumed.** The summary and the press read the *same* `KeyframeTarget` \
            expression, so aiming both at the current layer makes this row report the layer's \
            keyframes and agree with itself; the mutation survived exactly this assertion. The two \
            operands below are the ones that catch it.
            """)
        XCTAssertEqual(app.staticTexts["layerOptions.folderKeyframes"].label, "Frame 1 · keyframes at 1",
                       "the caption's own list is 1-based too, once there is a keyframe to name")
        XCTAssertTrue(app.buttons["layerOptions.removeKeyframe"].waitForExistence(timeout: 5),
                      "With a keyframe under the playhead the panel offers to take it back")
        XCTAssertEqual(app.buttons["layerOptions.removeKeyframe"].value as? String, "0",
                       "…and it names the frame it would take back, which is the playhead's — a row "
                       + "that said anything else would remove a keyframe the artist is not looking at")

        // **The one operand in this test that the panel does not also compute.** The summary above is
        // read through the *same* `KeyframeTarget` expression the press wrote through, so a build
        // that aimed both of them at the wrong target reads back its own write and agrees with
        // itself — mutation-tested, and it survived. The timeline's marker bands are per row, so
        // "which row grew a diamond" is a fact neither the panel nor the press can fake.
        XCTAssertEqual(app.otherElements["timeline.folderTrack.Folder 1.keys"].value as? String, "0",
                       """
                       The group's timeline row must draw one diamond, at frame 0. This band is \
                       `TimelineKeyMarkers.encode` over `keyframeFrames(of: .folder(…))`, fed \
                       through `TimelineLayoutKey` — so it is the same union the panel reports, \
                       reached by a different path and attributed to a named row.
                       """)
        XCTAssertFalse(app.otherElements["timeline.keyMarkers.0"].exists, """
            The *layer* inside the document must not have grown a keyframe. Its marker band is \
            hidden outright when it has none, so its absence is the assertion — and it is the half \
            that goes red if the panel's row addressed `keyframeTarget` (the current layer) rather \
            than the folder it was opened on, which is the likeliest way to write this wrong.
            """)
        attach(app, "folder-keyframe-row-after-first")

        // 3. Move the playhead **with the panel still open**. The row has to follow it live: the
        // transport sits below this panel, so an artist can scrub while it is up, and a row that had
        // captured its frame when the panel opened would quietly write to the wrong one.
        stepForward(app, 4, toFrame: 4)
        XCTAssertEqual(app.buttons["layerOptions.addKeyframe"].value as? String, "4", """
            The Add row must read the playhead as it moves, not the frame the panel was opened on. \
            This is the assertion that distinguishes reading `currentFrame` in the body from \
            capturing it — and capturing is what the timeline's own cel menu deliberately does, so \
            it is a plausible thing to copy across.
            """)
        XCTAssertEqual(keyframeSummary(app), "0",
                       "…and the group still carries exactly the one keyframe, moving the playhead "
                       + "being a look rather than an edit")
        XCTAssertFalse(app.buttons["layerOptions.removeKeyframe"].exists,
                       "Frame 4 has no keyframe, so Remove is not offered there — the negative half "
                       + "of the pair asserted positively at frame 0 above")
        closeFolderOptions(app)

        // 4. Change something — the group's own opacity, the second channel kind.
        let slider = app.sliders["layerPanel.folder.Folder 1.opacity"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5),
                      "The folder row's opacity slider is the thing being animated")
        XCTAssertEqual(folderOpacity(app, named: "Folder 1"), 100, accuracy: 1,
                       "Premise: the group starts fully opaque")
        slider.adjust(toNormalizedSliderPosition: 0.25)
        let faded = folderOpacity(app, named: "Folder 1")
        XCTAssertLessThan(faded, 60,
                          "Premise: the drag actually lowered the group's opacity")

        // 5. Not an animation yet — §2.27's hold. The same number at frame 0.
        goToStart(app)
        XCTAssertEqual(folderOpacity(app, named: "Folder 1"), faded, accuracy: 2, """
            With one keyframe the drag holds its previous value rather than keying (§2.27), so the \
            group shows the new opacity at every frame. Asserting this first is what makes the \
            difference after the next press attributable to that press.
            """)

        // 6. Place the second key, which commits the held value onto frame 0.
        stepForward(app, 4, toFrame: 4)
        openFolderOptions(app, named: "Folder 1")
        app.buttons["layerOptions.addKeyframe"].tap()
        XCTAssertEqual(keyframeSummary(app), "0,4", """
            Both frames must now be keyframes of the group. This is the union the timeline draws \
            diamonds from, so a value of "4" alone would mean the first mark was lost and a value of \
            "0" alone that the second press did nothing.
            """)
        XCTAssertEqual(app.staticTexts["layerOptions.folderKeyframes"].label, "Frame 5 · keyframes at 1, 5",
                       "both the playhead (now frame 4, shown 5) and the list (0 and 4, shown 1 and 5) "
                       + "are the ruler's numbers, not the model's")
        attach(app, "folder-keyframe-row-after-second")
        closeFolderOptions(app)

        // 7. See the animation: three frames, three readings.
        goToStart(app)
        XCTAssertEqual(folderOpacity(app, named: "Folder 1"), 100, accuracy: 2,
                       "The held value landed on keyframe A, so the group is fully opaque at frame 0 "
                       + "again — which it was not a moment ago")
        stepForward(app, 4, toFrame: 4)
        XCTAssertEqual(folderOpacity(app, named: "Folder 1"), faded, accuracy: 2,
                       "…and the dragged value is on keyframe B")

        XCTAssertTrue(tapWhenHittable(app.buttons["timeline.stepBackButton"], "Step back"))
        XCTAssertTrue(tapWhenHittable(app.buttons["timeline.stepBackButton"], "Step back"))
        XCTAssertEqual(readFrameLabel(app)?.current, 3, "Premise: the playhead is on frame 2")
        let between = folderOpacity(app, named: "Folder 1")
        attach(app, "folder-keyframe-midway")
        XCTAssertTrue(between > faded + 2 && between < 98, """
            At frame 2 the group's opacity must be strictly between the two keys — \
            \(faded) at frame 4 and 100 at frame 0 — and it read \(between). This is the assertion \
            that separates an animation from two stored numbers: it fails both under a build that \
            keyed nothing and under one that keyed without the render path resolving the curve.
            """)
    }

    /// **The fade reaches the canvas**, which is the one reading that is about pixels rather than
    /// about a control.
    ///
    /// Operands: the colour of one point of the ink inside the group, at frame 0 against frame 4, with
    /// the group's opacity keyed 1 → 0 across them. At frame 0 that point is ink; at frame 4 the group
    /// draws at zero alpha so the same point is paper. Nothing here reads the model, the panel or the
    /// slider.
    ///
    /// It is a separate test from the workflow above deliberately: that one proves the entry point is
    /// reachable and the values are exposed, this one proves the result is *visible*, and a failure in
    /// either says something different about where the feature broke.
    func testAnAnimatedGroupOpacityFadesWhatTheCanvasDraws() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "There is no canvas to read pixels from")

        // A band rather than a hairline, so a probe at its centre cannot fall between passes —
        // `testFolderTransformMoveRowPosesTheInkInsideIt`'s own fixture rule.
        let probe = (dx: 0.42, dy: 0.50)
        for i in 0..<9 {
            let x = 0.40 + Double(i) * 0.005
            drawLine(on: canvas, from: CGVector(dx: x, dy: 0.42), to: CGVector(dx: x, dy: 0.58))
        }
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: probe.dx, dy: probe.dy)),
                       "Premise: the probe point lands on ink. A white reading here means the band "
                       + "missed and every assertion below would be about blank paper")

        openLayerPanel(app)
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5))
        dragRow(layerCell(app, layerIndex: 0), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        XCTAssertEqual(rowFolder(app, layerIndex: 0), "Folder 1", """
            The ink has to live *inside* the group, or animating the group's opacity changes nothing \
            on the canvas and this test would pass against a folder that animates an empty subtree.
            """)

        // Keyframe A at frame 0, through the row this pass added.
        openFolderOptions(app, named: "Folder 1")
        app.buttons["layerOptions.addKeyframe"].tap()
        XCTAssertEqual(keyframeSummary(app), "0", "Premise: the first keyframe landed on the group")
        closeFolderOptions(app)

        // Fade the group right out at frame 4, then commit it with keyframe B.
        stepForward(app, 4, toFrame: 4)
        app.sliders["layerPanel.folder.Folder 1.opacity"].adjust(toNormalizedSliderPosition: 0.0)
        openFolderOptions(app, named: "Folder 1")
        app.buttons["layerOptions.addKeyframe"].tap()
        XCTAssertEqual(keyframeSummary(app), "0,4",
                       "Premise: the group is keyed on both frames before the canvas is read")
        closeFolderOptions(app)

        XCTAssertTrue(waitUntilBlank(canvas, dx: probe.dx, dy: probe.dy, timeout: 15), """
            At frame 4 the group resolves to zero opacity, so the ink inside it must not be drawn — \
            the probe point should read as paper. It did not, which means the keyed opacity never \
            reached the render path for the *folder* node.
            """)
        attach(app, "folder-opacity-faded-at-frame-4")

        goToStart(app)
        XCTAssertTrue(waitUntilFilled(canvas, dx: probe.dx, dy: probe.dy, timeout: 15), """
            At frame 0 the group resolves to full opacity, so the same point must be ink again. A \
            white reading here means the fade was applied to the stored value rather than keyed, so \
            it is showing at every frame.
            """)
        attach(app, "folder-opacity-opaque-at-frame-0")
    }
}
