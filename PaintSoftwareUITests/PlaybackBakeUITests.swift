import XCTest

/// **Playing an ordinary document reads the bake, and pays for nothing else** — the owner's report
/// of 2026-09-08, in the running app.
///
/// > *"What I got was it considerably lagging, making the main thread stutter like wild, getting
/// > worse as time went on, and eventually crashing the app after a few seconds... I was noticing
/// > that when it is doing the frame switching, some layers would render but not others due to how
/// > laggy it was, which is very weird as every layer should all be prebaked."*
///
/// **This is the arm `PlaybackEngagementLogicTests` cannot reach**, and the distinction matters more
/// here than usual. That suite asserts a *predicate* and a *pure step*; what actually decides
/// whether a host is blanked, and therefore whether the step is ever asked the question, is
/// `CanvasView.updateSandwich` — a `UIViewRepresentable` coordinator, headless-unreachable, and the
/// place TODO (53)'s twin defect lived undetected behind a green logic tier for a fortnight.
///
/// **The instruments are three fields of `canvas.host`'s accessibility label**, which is the only
/// window this app has into which rendering path the canvas is on:
///
/// - `sandwich:` — `off` is Core Animation's flat row, `rest` is the baked frame on screen.
/// - `rebuilds:` — canvas-sized *composites* the canvas has queued for the mid-stroke pair.
/// - `rasterizes:` — canvas-sized *vector walks* any cel in the process has performed.
///
/// The last two are what "regardless of what is on the canvas" means in a number: a frame flip that
/// moves either of them is paying a per-layer cost, and per-layer is exactly the term the owner's
/// requirement excludes.
final class PlaybackBakeUITests: PaintUITestCase {

    /// The seed's shape — `UITestSeeds.seedPlainAnimationIfRequested`.
    private let layerCount = 3
    private let frameCount = 2

    /// **The launch this suite makes, and the second argument is what makes it a test at all.**
    ///
    /// A simulator reports the *Mac's* memory, so `CompositorBudget.textureBudgetBytes` comes out at
    /// its 768 MiB cap — and at that budget the flat row's six canvas-sized renders all fit, the memo
    /// converges after two laps, and *"a frame flip costs no canvas-sized render"* is true whether or
    /// not anything refuses one. MEASURED 2026-09-09: with the fix's own refusal deleted, every
    /// assertion below stayed green until this argument was added.
    ///
    /// `-uiTestTextureBudgetBytes` pins it to two renders of the app's default 2048² canvas, which is
    /// an iPad 9 at 4096² to the entry: 183.7 MB against 67.1 MB a render.
    private var launchArguments: [String] {
        ["-resetGallery", "-uiTestSeedPlainAnimation",
         "-uiTestTextureBudgetBytes", String(2048 * 2048 * 4 * 2)]
    }

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func field(_ app: XCUIApplication, _ name: String) -> Int? {
        app.otherElements["canvas.host"].label
            .split(separator: " ")
            .first { $0.hasPrefix(name + ":") }
            .flatMap { Int($0.dropFirst(name.count + 1)) }
    }

    /// **A document with nothing special about it plays off the bake.**
    ///
    /// Before 2026-09-09 the first assertion below was the whole bug: `sandwichEngagesOnCanvas`
    /// asked only whether the *tree* needed a compositor, so a plain stack of Normal-mode layers
    /// answered false while playing exactly as it does at rest — the canvas stayed on Core
    /// Animation's flat row and the baked frames on disk went unread. Each flip then cost one
    /// canvas-sized vector render per layer, against a memo that on the owner's iPad 9 holds two of
    /// them at 4096², so it never converged: ~5 fps, worsening, and a crash at six seconds.
    ///
    /// **`rest` is a statement about what is on screen**, not a stored value: `updateSandwich`'s
    /// trap 2 reaches it only once `sandwichFullKey` names the frame the artist is on, and trap 1
    /// refuses to blank a single host until there is a baked picture to blank it in favour of. So
    /// `rest` means the baked frame *is* the picture being displayed — which is also why an unbaked
    /// scene cannot be frozen by this change: it simply stays at `off`.
    func testPlayingAPlainDocumentPutsTheCanvasOnTheBakedFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        XCTAssertEqual(sandwichState(app), "off",
                       "Setup, and the containment: at rest a plain stack must stay on Core "
                       + "Animation's flat row. Engaging everywhere would be a different change")
        XCTAssertEqual(readFrameLabel(app)?.total, frameCount,
                       "Setup: the seed has to have laid \(frameCount) frames down")
        attachScreen("01-at-rest-on-the-flat-row")

        let play = app.buttons["timeline.playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30,
                                           "Playing a plain document never reached the baked frame. "
                                           + "That is the owner's report exactly: the bake is on "
                                           + "disk and the canvas is drawing the layers itself"))
        attachScreen("02-playing-off-the-bake")

        // **The picture on screen is the artwork, asked while the bake is what is drawing it.** With
        // the sandwich engaged every host is blanked, so the only thing that can put ink on the
        // canvas is the baked frame — a composite that had elided the layers, or a bake that never
        // contained them, would leave the paper showing and every count below just as green. Asked
        // as a band rather than as one point because the playhead is moving: each frame of the seed
        // shows a different three of its six strokes.
        XCTAssertTrue(waitForInkBand(canvas),
                      "The canvas is at rest on the baked frame and there is no ink anywhere on it")

        // `publishCanvasState` runs at the end of every `reconcileLayers` and writes only when the
        // string moved, so these are current rather than whenever the presentation last changed —
        // which it had to become before any of these comparisons meant anything.
        let rebuildsAtEngage = try XCTUnwrap(field(app, "rebuilds"), "the canvas publishes `rebuilds:`")
        let rasterizesAtEngage = try XCTUnwrap(field(app, "rasterizes"), "the canvas publishes `rasterizes:`")

        // ~96 frame flips at 24 fps — a fifth of the owner's own recording, and forty-eight laps of
        // a two-frame loop, so a per-flip cost of any kind is three orders of magnitude above the
        // allowance below.
        Thread.sleep(forTimeInterval: 4)

        play.tap()
        XCTAssertEqual(sandwichState(app), "off",
                       "Stopping puts the canvas back on the flat row — disengaging is a branch, not "
                       + "a composite, so it is immediate")
        attachScreen("03-stopped-and-back-on-the-flat-row")

        let rebuildsAfter = try XCTUnwrap(field(app, "rebuilds"))
        let rasterizesAfter = try XCTUnwrap(field(app, "rasterizes"))

        XCTAssertEqual(rebuildsAfter, rebuildsAtEngage,
                       "Four seconds of playback queued \(rebuildsAfter - rebuildsAtEngage) sandwich "
                       + "rebuilds. Every flip moves `SandwichKey`, so this used to be two "
                       + "canvas-sized composites a tick for a mid-stroke pair nothing displays — a "
                       + "stroke cannot begin without stopping playback first")

        // **An allowance rather than equality, and it is `layerCount` for a reason that is visible in
        // the number.** Disengaging un-blanks every host, and an un-blanked host repaints — so
        // stopping legitimately costs one render per layer. Playing costs none. Before the fix this
        // difference was ~3 a flip over ~96 flips, so the two answers are 3 and ~288 and the
        // allowance cannot hide a regression.
        XCTAssertLessThanOrEqual(rasterizesAfter - rasterizesAtEngage, layerCount,
                                 "Four seconds of playback cost \(rasterizesAfter - rasterizesAtEngage) "
                                 + "canvas-sized vector renders. A blanked host draws nothing, so it "
                                 + "must ask for nothing: at 4096² each of these is 67.1 MB against a "
                                 + "memo that holds two, which is the thrash *and* the crash")

    }

    /// **Every layer comes back to the cel under the playhead the moment the composite lets go**,
    /// which is the correctness half of "a blanked host does not rasterize".
    ///
    /// Declining a render leaves the base slot holding the *previous* cel's picture, and
    /// `refreshDisplayIfStale` compares version numbers that are **per canvas** — the seed's six cels
    /// each carry one stroke, so all six sit at the same version, and a host that recorded its
    /// declined version as displayed would answer "already showing that" about a completely
    /// different cel. Two things stop that and both are exercised here: `refreshDisplay` records
    /// `nothingDisplayed` when it declines, and `LayerHostView.setBlanked` asks for a repaint on the
    /// un-blanking edge — which nothing else would, because `updateSandwich`'s disengage branch
    /// un-blanks every host and returns.
    ///
    /// **The assertion is against the same app's own answer for that frame**, measured before any
    /// playback, rather than against a coordinate this test would have to derive from the canvas's
    /// fit transform. And it is taken **without stepping the playhead afterwards**, because a step
    /// changes the cel and `vectorCanvas`'s `didSet` repaints unconditionally — which would hide
    /// exactly the defect this test is for.
    func testStoppingPlaybackLeavesEveryLayerShowingTheFrameItStoppedOn() throws {
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // The truth for each frame, from the app itself, before anything is engaged.
        app.buttons["timeline.toStartButton"].tap()
        let first = waitForRowSignature(canvas)
        app.buttons["timeline.stepForwardButton"].tap()
        let second = waitForRowSignature(canvas, differingFrom: first)
        XCTAssertNotEqual(first, second,
                          "Setup: the seed's two frames have to draw different rows (\(first)), or "
                          + "nothing below can tell a stale picture from a correct one")
        attachScreen("01-the-two-frames-before-playback")

        let play = app.buttons["timeline.playButton"]
        play.tap()
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "Setup: the canvas has to engage"))
        Thread.sleep(forTimeInterval: 2)
        play.tap()
        XCTAssertEqual(sandwichState(app), "off", "Setup: stopping disengages")

        let stopped = try XCTUnwrap(readFrameLabel(app)?.current, "the timeline publishes the frame")
        let expected = stopped == 1 ? first : second
        let settled = waitForRowSignature(canvas, matching: expected)
        attachScreen("02-stopped-on-frame-\(stopped)")
        XCTAssertEqual(settled, expected,
                       "Playback stopped on frame \(stopped) and the canvas is drawing \(settled) "
                       + "where that frame is \(expected). Every host was blanked a moment ago and "
                       + "declined its render; coming back it has to repaint, and it cannot decide "
                       + "that by comparing a version number it recorded against another cel's")
    }

    /// **A hidden layer costs nothing to step past** — TODO (58), reported by the owner 2026-09-08:
    ///
    /// > *"currently, pressing the playback button of Test1 does not run at 24FPS, sometimes taking
    /// > 313ms per frame. This is even after hiding all layers so that the canvas is pretty much a
    /// > blank white sheet."*
    ///
    /// Their reading was that the cost must be per-frame work scaling with the canvas rather than
    /// with what is on it, and it is: `reconcileLayers` sets `host.isHidden` from
    /// `isLayerEffectivelyVisible` and then, a few lines later in the same pass, hands that same host
    /// the cel covering the new frame — so the view rasterized the whole canvas for pixels
    /// `isHidden` throws away. `LayerHostView.isHidden`'s observer is what refuses it now.
    ///
    /// **Stepping rather than playing, deliberately.** Playing puts the canvas on the composite,
    /// which blanks every host and would make this pass for the other reason; a *step* leaves the
    /// canvas on the flat row, so hidden-ness is the only thing under test.
    func testSteppingPastHiddenLayersCostsNoCanvasSizedRender() throws {
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        app.buttons["toolbar.layersButton"].tap()
        for index in 0..<layerCount {
            let eye = app.buttons["layerPanel.row.\(index).visibility"]
            XCTAssertTrue(eye.waitForExistence(timeout: 5), "layer \(index)'s visibility toggle")
            eye.tap()
        }
        app.buttons["toolbar.layersButton"].tap()
        attachScreen("01-every-layer-hidden")

        // After the hiding, so the renders the hiding itself provoked are behind the baseline.
        Thread.sleep(forTimeInterval: 1)
        let before = try XCTUnwrap(field(app, "rasterizes"), "the canvas publishes `rasterizes:`")

        let next = app.buttons["timeline.stepForwardButton"]
        let previous = app.buttons["timeline.stepBackButton"]
        for _ in 0..<6 {
            next.tap()
            previous.tap()
        }
        Thread.sleep(forTimeInterval: 1)

        let after = try XCTUnwrap(field(app, "rasterizes"))
        XCTAssertEqual(after, before,
                       "Twelve frame steps over three hidden layers cost \(after - before) "
                       + "canvas-sized vector renders. A hidden host draws nothing, so it must ask "
                       + "for nothing — at 6000² each of these is 137 MB, which is the owner's 313 ms "
                       + "a frame on a blank white sheet")
    }

    /// **The flat row is still what an ordinary edit uses**, which is the containment half and the
    /// thing a one-sided fix would quietly break: `sandwichEngagesOnCanvas` gained a clause, and a
    /// clause that leaked outside playback would put every plain document on the compositor for the
    /// whole session — RENDER.md §5.2's *"a document with no blend modes anywhere cannot regress"*.
    func testAnOrdinaryStrokeOnAPlainDocumentNeverEngagesTheCompositor() throws {
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        XCTAssertEqual(sandwichState(app), "off", "Setup")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.6), to: CGVector(dx: 0.7, dy: 0.6))
        XCTAssertEqual(sandwichState(app), "off",
                       "A stroke on a plain document must leave the canvas exactly where it was")
        XCTAssertNotNil(waitForPixel(canvas, at: CGVector(dx: 0.5, dy: 0.6)),
                        "…and the ink is on screen, which is what says the flat row is still drawing")
        attachScreen("01-stroke-on-the-flat-row")
    }

    /// Polls a canvas pixel until it is not the paper — `BakeWiringUITests`' probe, local for its
    /// reason.
    @discardableResult
    private func waitForPixel(_ canvas: XCUIElement, at point: CGVector,
                              timeout: TimeInterval = 10) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let pixel = rgbaPixel(of: canvas, dx: Double(point.dx), dy: Double(point.dy))
            if let pixel, !isWhitish(pixel) { return pixel }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    /// Which of the seed's six rows currently carry ink, as a string — the canvas's picture reduced
    /// to the one property this fixture varies per frame.
    ///
    /// Waits for it to be non-empty first, for `waitForSandwichState`'s reason: a repaint after a
    /// frame step is a background rasterize landing (RENDER.md §2.13), so an instant read is a race
    /// that reads as a blank canvas.
    /// **Returns whatever it has when the deadline passes rather than failing**, deliberately: an
    /// all-paper canvas is `......`, both frames answer the same, and the caller's `XCTAssertNotEqual`
    /// reddens with the signatures printed. A `XCTFail` here would report the symptom one level away
    /// from the comparison that gives it meaning, and an `XCTSkip` would report it as nothing at all.
    private func waitForRowSignature(_ canvas: XCUIElement, timeout: TimeInterval = 10,
                                     matching wanted: String? = nil,
                                     differingFrom previous: String? = nil) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var signature = ""
        repeat {
            signature = Self.rows
                .map { isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: $0)) ? "." : "#" }
                .joined()
            if let wanted {
                if signature == wanted { return signature }
            } else if let previous {
                if signature.contains("#"), signature != previous { return signature }
            } else if signature.contains("#") {
                return signature
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return signature
    }

    /// The six heights `UITestSeeds.seedPlainAnimationIfRequested` puts its strokes at.
    private static let rows: [Double] = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7]

    /// The same probe over the band the seed's six strokes lie in, because **the playhead does not
    /// hold still**: each frame shows a different three of them, so any single row is ink on one
    /// frame and paper on the other and a point probe is a coin toss.
    private func waitForInkBand(_ canvas: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for row in Self.rows where !isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: row)) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
