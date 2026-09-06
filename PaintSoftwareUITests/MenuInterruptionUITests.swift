import XCTest

/// **The measurement `MENU_PRESENTATION_CENSUS.md` asks for**, and the only thing that separates its
/// twelve UNKNOWNs from twelve more BROKENs.
///
/// The census established that a `.popover` here does *not* swallow the touch that dismisses it: the
/// touch lands outside, the popover starts tearing down, and the same touch goes on to start a
/// stroke — so the teardown arrives in the middle of a live touch sequence. Seven popovers were
/// broken that way. Twelve other presentations (`Menu`, `.contextMenu`, the stock `ColorPicker`,
/// `ShareLink`) present through a different UIKit path — `UIContextMenuInteraction`/`UIMenu` rather
/// than `UIPopoverPresentationController` — and **nothing in this repo had ever verified which way
/// that path behaves.** Reading the source cannot answer it; only a touch can.
///
/// So this class does the one thing that answers it: opens a blend-mode `Menu` on the layer rail and
/// draws a stroke straight through it, in the shape of `CanvasTransformFreezeUITests`, which does the
/// same for the popover case.
///
/// **The discriminator is whether the stroke happens at all.** If the menu swallows the touch, no
/// stroke is drawn, no sequence is interrupted, and the twelve were never broken. If the touch passes
/// through, the twelve are the popover's family and were broken for the popover's reason.
///
/// **Read the marker, not the raster count.** A new canvas's one layer is a *vector* layer (PLAN §8),
/// so `readLayerStrokeCount` — which reads the raster tier — is 0 no matter what is drawn. An earlier
/// draft of this class used it, measured 0 through an open menu, and would have reported "menus are
/// safe" from a fixture that could not have said anything else. `testTheSameStrokeWithNoMenuOpen…`
/// below is the control that caught it, and is why it exists.
///
/// Its own class because `xcodebuild` distributes parallel work per test *class* (see CLAUDE.md), and
/// this one is short.
final class MenuInterruptionUITests: PaintUITestCase {

    /// Left of centre, clear of the trailing layer rail and the options panel that hangs off its left
    /// edge (`DrawingView` lays both out on the trailing edge), and vertically centred so it is never
    /// in the letterbox margin (`visibleCanvasBounds`).
    private let strokeStart = CGVector(dx: 0.28, dy: 0.45)
    private let strokeEnd = CGVector(dx: 0.42, dy: 0.55)
    private let secondStrokeStart = CGVector(dx: 0.28, dy: 0.62)
    private let secondStrokeEnd = CGVector(dx: 0.42, dy: 0.70)

    /// THE MEASUREMENT. Open the layer's blend-mode `Menu`, leave it alone, and draw through it.
    ///
    /// Four readings, each a separate finding:
    ///
    /// 1. **Does the menu even come down?** A `.popover` is dismissed *by* the outside touch. If a
    ///    `Menu` is not, the artist's touch never reaches the canvas and there is no interruption to
    ///    have.
    /// 2. **Did the stroke reach the canvas?** The layer row's `.vector` marker counts committed
    ///    `.paint` strokes.
    /// 3. **Did the next stroke destroy it?** "when the user then starts another stroke, the first
    ///    stroke disappears" — the symptom, in the owner's words.
    /// 4. **Is the canvas still alive?** The original freeze: all three transform recognizers wait on
    ///    the stroke recognizer failing, so one stranded without `reset()` kills pan/pinch/rotate for
    ///    the life of the drawing view.
    func testDrawingStraightThroughAnOpenBlendModeMenu() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        assertPinchMovesCanvas(app, canvas, "Setup: the canvas pinches before any of this")
        XCTAssertEqual(paintStrokes(app), 0, "PREMISE: nothing has been drawn yet")

        openBlendModeMenu(app)
        let menuItem = app.buttons["layerOptions.blendMode.multiply"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5),
                      "PREMISE: the blend-mode Menu has to actually be open, or this measures nothing")

        // The one touch that both dismisses the menu and would start the stroke.
        dragOnCanvas(app, from: strokeStart, to: strokeEnd)

        let menuSurvived = menuItem.exists
        NSLog("MENUDIAG after-first-stroke: menuStillUp=\(menuSurvived) canvasHittable=\(canvas.isHittable)")
        closeChrome(app)

        let afterFirst = paintStrokes(app)
        NSLog("MENUDIAG strokes after first: \(String(describing: afterFirst))")

        // Reading 3: the reported symptom is that the *next* stroke is what makes the first vanish.
        dragOnCanvas(app, from: secondStrokeStart, to: secondStrokeEnd)
        let afterSecond = paintStrokes(app)
        NSLog("MENUDIAG strokes after second: \(String(describing: afterSecond))")

        // Reading 4, and the one contract that has to hold whichever way the others come out: a menu
        // may legitimately swallow its own dismiss touch, but nothing may leave the canvas dead.
        assertPinchMovesCanvas(app, canvas, """
            THE FREEZE: two-finger pinch/pan/rotate stopped working after a stroke drawn through an \
            open blend-mode Menu — see MENU_PRESENTATION_CENSUS.md
            """)

        // MEASURED 2026-08-20 on iPad Pro 13" (M4), iOS 26.5. A SwiftUI `Menu` is **not** the
        // popover's family: its dismiss region absorbs the whole touch sequence, so the drag neither
        // reaches the canvas nor even closes the menu. The stroke that would have been interrupted
        // never begins. If any of these three ever changes, MENU_PRESENTATION_CENSUS.md's counts are
        // the other place to update — the twelve UNKNOWNs are resolved SAFE on the strength of this.
        XCTAssertTrue(menuSurvived, """
            The blend-mode `Menu` came down when the artist drew beneath it. That makes it behave the \
            way this app's `.popover`s do — the outside touch is not swallowed — and the census's \
            twelve UNKNOWNs are twelve more of the same defect. `CanvasPresentation` cannot cover \
            them: a `Menu` exposes no `isPresented` binding for the modifier to observe, so the fix \
            would have to be a different mechanism.
            """)
        XCTAssertEqual(afterFirst, 0, """
            A stroke drawn through an open `Menu` reached the canvas. The menu is therefore not \
            swallowing the touch, and the census's twelve UNKNOWNs are BROKEN — update its counts.
            """)
        XCTAssertEqual(afterSecond, 1, """
            The stroke drawn after the menu was gone did not commit. Whatever a menu does to the \
            touch that lands beneath it, the *next* touch has to draw normally — a menu that left \
            the canvas refusing strokes would be the owner's onion-skin symptom in a new place.
            """)
    }

    /// The control, and it is what stops the test above passing for the wrong reason. Identical,
    /// except the menu is dismissed first — so "the menu ate the touch" means something only if the
    /// very same stroke, through the very same fixture, commits when no menu is open.
    ///
    /// **It has already earned its keep once**: the first draft of this class counted raster strokes
    /// on a vector layer, so it measured 0 either way, and this test is what said so.
    func testTheSameStrokeWithNoMenuOpenCommitsNormally() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(paintStrokes(app), 0, "PREMISE: nothing drawn yet")

        openBlendModeMenu(app)
        let item = app.buttons["layerOptions.blendMode.multiply"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "PREMISE: the menu has to open")
        dismissMenu(app)
        XCTAssertTrue(item.waitForNonExistence(timeout: 5), "PREMISE: and be closed again before this stroke")
        closeChrome(app)

        dragOnCanvas(app, from: strokeStart, to: strokeEnd)

        XCTAssertEqual(paintStrokes(app), 1, """
            The identical stroke has to commit with no menu open. If it does not, the fixture is not \
            drawing on the canvas at all and the measurement above means nothing.
            """)
    }

    /// **TODO (39), the timeline freeze — this is the regression test, and it was inverted on
    /// 2026-09-06 when the defect was fixed.**
    ///
    /// It used to be a *characterization* of the bug: it asserted `cel.frame.minX == parked` and
    /// `copy.exists`, i.e. that the drag did nothing and the menu survived, and its own doc comment
    /// said "it goes red when somebody fixes it". So it was **green against the broken app**, which
    /// is worth stating because a brief that calls it "the regression test" gets the polarity
    /// backwards — MEASURED green at `7006e72` with the defect fully present.
    ///
    /// The defect: `.popover` presents behind a screen-covering
    /// `_UIPassthroughGateGestureRecognizer`. `hitTest` still returned the timeline row — the
    /// hierarchy was intact — but `touchesBegan` never fired, so every drag on the timeline was
    /// swallowed whole and only a tap dismissed the menu. MEASURED then: menu up, the drag moved the
    /// cel block 0.0 pt; menu gone, the same drag moved it 369 pt.
    ///
    /// The owner ruled on 2026-09-06 that these menus stop being `.popover`s rather than that the
    /// gate get a hole punched in it, so what this now pins is the whole point of that ruling: **one
    /// drag both dismisses the menu and scrolls the track.** Two gestures where one should do is the
    /// bug being fixed, not an acceptable outcome.
    func testADragOnTheTimelineWhileABlockMenuIsUpDismissesItAndScrollsTheTrack() {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 10))
        let trackY = cel.frame.midY
        let copy = app.buttons["Copy"]

        let spot = cel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        spot.tap()
        _ = app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 2)
        spot.tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 5),
                      "PREMISE: a second tap where the playhead already is raises the block menu")

        // **Drawn, not merely stored.** The menu is a view in the app's own hierarchy now, and this
        // is the assertion that fails if it stops being on screen while `timelineMenu` stays set.
        XCTAssertTrue(anchoredMenu(app, "timelineSlotMenu").exists, """
            The block menu has to be an `AnchoredMenu` in the app's hierarchy. If this is missing \
            while `Copy` is present, the menu is being presented some other way again.
            """)
        // And the mechanism itself is gone: a popover always installs one of these behind it, and
        // it is the thing that ate the drag.
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists, """
            A `PopoverDismissRegion` is up while a timeline menu is open, so the menu is a \
            `.popover` again and the passthrough gate is back with it — which is TODO (39) exactly.
            """)

        let parked = cel.frame.minX
        dragTimelineLeft(app, y: trackY)

        XCTAssertLessThan(cel.frame.minX, parked - 50, """
            THE FIX: one drag on the track has to scroll it even with a menu up. With the popover \
            this measured 0.0 pt of movement.
            """)
        XCTAssertFalse(copy.exists, """
            …and the same drag has to dismiss the menu. Letting the gesture through but leaving the \
            menu standing is the `passthroughViews` outcome the owner ruled against on 2026-09-06: \
            a cel menu names a specific block, and the track has just scrolled out from under it.
            """)
    }

    /// The other half of the requirement, and the half the popover already did: a **tap** outside
    /// closes the menu. Kept separate from the drag because they are different gestures and the
    /// popover got one of them right — a single test covering both would pass on a fix that only
    /// restored the half that already worked.
    func testATapOutsideAnAnchoredTimelineMenuDismissesIt() {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 10))
        let copy = app.buttons["Copy"]

        let spot = cel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        spot.tap()
        _ = app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 2)
        spot.tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "PREMISE: the block menu has to be up")

        app.staticTexts["timeline.frameLabel"].tap()

        XCTAssertTrue(copy.waitForNonExistence(timeout: 5),
                      "a tap on chrome away from the menu closes it")
        XCTAssertFalse(anchoredMenu(app, "timelineSlotMenu").exists,
                       "and the anchored view goes with it, rather than lingering empty")
    }

    /// **All four of them — TODO (39) says "there are four; find them all", and this is the list.**
    ///
    /// `timelineSlotMenu` (a cel block), `onionSkinOptions`, `interpolateOptions` and
    /// `graphChannelList`. Every one was a `.popover` and carried the same defect; three were never
    /// reported only because they are opened less often than the block menu.
    ///
    /// Driven from a **cold start** rather than from constructed state: each menu is opened the way
    /// an artist opens it, from a document that has just been created. That is the reachability
    /// check this repo added to its bar on 2026-09-05, after three features shipped whose models
    /// were correct and whose entry points could not be reached.
    func testAllFourTimelineMenusAreAnchoredViewsRatherThanPopovers() {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        XCTAssertTrue(app.otherElements["timeline.cel.0.0"].waitForExistence(timeout: 10))

        // 1 — the cel block's menu, which is the one the owner's trace caught.
        let cel = app.otherElements["timeline.cel.0.0"]
        let spot = cel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        spot.tap()
        _ = app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 2)
        spot.tap()
        assertAnchored(app, "timelineSlotMenu", opener: "a second tap on a cel block")

        // 2, 3 — the two-stage buttons. The first tap turns the mode on; the tap that follows opens
        // the panel, and `openTwoStage` does not assume which state the button started in.
        openTwoStage(app, button: "timeline.onionSkinToggle", menu: "onionSkinOptions")
        assertAnchored(app, "onionSkinOptions", opener: "the onion-skin button")

        openTwoStage(app, button: "timeline.interpolateButton", menu: "interpolateOptions")
        assertAnchored(app, "interpolateOptions", opener: "the interpolate button")

        // 4 — the graph editor's channel list, which only exists while the band is open, so this
        // also proves the button that raises it is reachable from a fresh document.
        app.buttons["timeline.graphEditorButton"].tap()
        let channels = app.buttons["timeline.graphChannelsButton"]
        XCTAssertTrue(channels.waitForExistence(timeout: 5),
                      "PREMISE: opening the graph band puts the channel-list button beside its toggle")
        openTwoStage(app, button: "timeline.graphChannelsButton", menu: "graphChannelList")
        assertAnchored(app, "graphChannelList", opener: "the graph channels button")
    }

    // MARK: - Fixture

    /// An `AnchoredMenu` by the case it carries. Queried across every element type rather than as
    /// `otherElements`, because what XCUITest calls an accessibility container is SwiftUI's business
    /// and not something this test should be pinning.
    private func anchoredMenu(_ app: XCUIApplication, _ presentation: String) -> XCUIElement {
        app.descendants(matching: .any)["timeline.anchoredMenu.\(presentation)"].firstMatch
    }

    /// One menu's two findings: it is on screen **as an anchored view**, and there is no popover
    /// dismiss region behind it. The second is the one that matters — `PopoverDismissRegion` is the
    /// tell for `UIPopoverPresentationController`, whose passthrough gate is what swallowed the
    /// drags in the owner's trace.
    private func assertAnchored(_ app: XCUIApplication, _ presentation: String, opener: String) {
        XCTAssertTrue(anchoredMenu(app, presentation).waitForExistence(timeout: 5), """
            \(opener) did not put `timeline.anchoredMenu.\(presentation)` on screen. Either the menu \
            is unreachable from a fresh document, or it is being presented some way other than \
            `AnchoredMenu` — both of which are TODO (39).
            """)
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists, """
            `\(presentation)` is up with a `PopoverDismissRegion` behind it, so it is a `.popover` \
            again — and with it comes the screen-covering gate that eats every drag on the timeline.
            """)
    }

    /// Opens a menu hung off a two-stage button — onion skin and interpolate each turn their mode on
    /// with the first tap and open their panel with the next — without assuming which state the
    /// button starts in. `graphChannelsButton` is single-stage and takes the first branch.
    private func openTwoStage(_ app: XCUIApplication, button id: String, menu presentation: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "PREMISE: \(id) has to be on screen")
        button.tap()
        if anchoredMenu(app, presentation).waitForExistence(timeout: 2) { return }
        button.tap()
    }

    /// A 200 pt leftward drag across the cel row, well clear of the block itself. `press(forDuration:
    /// thenDragTo:)` rather than `swipeLeft()` because a swipe needs an element and the point of this
    /// is to touch the track wherever the popover is not.
    private func dragTimelineLeft(_ app: XCUIApplication, y: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 700, dy: y))
        start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Opens the layer rail, the first layer's options panel, and its blend-mode `Menu` — the pull-down
    /// `LayerUITests.testSettingLayerBlendModeShowsOnRowAndPersists` already drives, stopped one tap
    /// earlier so the menu is left standing.
    private func openBlendModeMenu(_ app: XCUIApplication) {
        showLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()   // select
        row.tap()   // open options
        let picker = app.buttons["layerOptions.blendModeButton"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
    }

    /// Closes an open `Menu` without activating anything in it. UIKit puts a full-screen dismiss
    /// region behind it, the same as it does behind a popover; tapping it is the only way to decline
    /// the menu, since any tap aimed at the app would land on whatever is underneath once it goes.
    private func dismissMenu(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.waitForExistence(timeout: 2) {
            dismissRegion.tap()
        } else {
            app.otherElements["timeline.ruler"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }

    /// Everything the fixture opened, shut again, so a reading is taken against a bare canvas. The
    /// rail and its options panel overlay the canvas, which is why `vectorMarkerViaPanel` exists in
    /// the base class with the same warning; a pinch or a stroke aimed through open chrome measures
    /// the chrome.
    private func closeChrome(_ app: XCUIApplication) {
        if app.buttons["layerOptions.blendMode.multiply"].exists { dismissMenu(app) }
        let close = app.buttons["layerOptions.close"]
        if close.exists { close.tap() }
        hideLayerPanel(app)
    }

    /// Committed `.paint` strokes on layer 0, read off the row's `.vector` marker with the rail
    /// opened for the read and shut again afterwards.
    private func paintStrokes(_ app: XCUIApplication) -> Int? {
        showLayerPanel(app)
        let marker = readVectorMarker(app, layerIndex: 0)
        XCTAssertEqual(marker?.isVector, true,
                       "PREMISE: a new canvas's layer is a vector layer, so this is the tier its strokes land in")
        hideLayerPanel(app)
        return marker?.strokes
    }

    /// Idempotent, unlike `openLayerPanel`, which toggles.
    private func showLayerPanel(_ app: XCUIApplication) {
        if app.staticTexts["layerPanel.row.0"].exists { return }
        openLayerPanel(app)
        _ = app.staticTexts["layerPanel.row.0"].waitForExistence(timeout: 5)
    }

    private func hideLayerPanel(_ app: XCUIApplication) {
        guard app.staticTexts["layerPanel.row.0"].exists else { return }
        app.buttons["toolbar.layersButton"].tap()
        _ = app.staticTexts["layerPanel.row.0"].waitForNonExistence(timeout: 5)
    }

    /// Pinches the canvas and asserts its published transform actually moved —
    /// `CanvasTransformFreezeUITests`'s helper, which explains why it is a pinch and not a pan and
    /// why the reading comes off an accessibility label.
    private func assertPinchMovesCanvas(_ app: XCUIApplication, _ canvas: XCUIElement, _ message: String) {
        let before = readTransform(app)
        canvas.pinch(withScale: 2.0, velocity: 1.5)
        let after = readTransform(app)
        XCTAssertNotEqual(before, after, "\(message) (xform \(before) -> \(after))")
    }

    /// The `xform:` field of `canvas.host`'s accessibility label — "scale,rotation,dx,dy".
    private func readTransform(_ app: XCUIApplication) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let field = label.split(separator: " ").first(where: { $0.hasPrefix("xform:") }) else {
            return "?(\(label))"
        }
        return String(field.dropFirst("xform:".count))
    }
}
