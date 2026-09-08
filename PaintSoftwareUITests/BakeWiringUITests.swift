import XCTest

/// RENDER.md §5 stage 4d in the running app — the half `BakeWiringLogicTests` cannot reach.
///
/// **What is only visible here.** A logic test will agree happily with a canvas that never comes
/// back from the mid-stroke picture, with a frame that stays stale forever, and with a playhead that
/// advances over a document showing nothing: all three are properties of the *view* reacting to the
/// baker, and the view is a `UIViewRepresentable` coordinator that is not reachable headlessly.
///
/// **`sandwichState` is the whole instrument, and stage 4d changed what it means.** It used to say
/// which of three images `startSandwichRebuild` had produced; it now says whether the **bake for
/// this frame has landed** — `updateSandwich`'s trap 2 holds the mid-stroke pair until
/// `sandwichFullKey` names the frame the artist is on, so "rest" is exactly "the baker got there".
/// A canvas stuck on "stroke" after lift is a bake that never arrived, and nothing else looks wrong.
final class BakeWiringUITests: PaintUITestCase {

    /// Polls until the canvas reports `state`, and returns how long that took.
    ///
    /// **A deadline rather than an instant assertion, and that is §2.13 rather than laxity**: the
    /// owner ruled that *"a canvas that shows the previous composite for a split second after pen-up
    /// is acceptable, provided the main thread never freezes"*. So the assertion this suite can make
    /// is that the canvas gets there, not that it is there on the next line. The elapsed time is
    /// attached rather than asserted on, because a simulator's seconds are not a device's.
    @discardableResult
    private func waitForSandwich(_ app: XCUIApplication, _ state: String,
                                 timeout: TimeInterval = 30) -> TimeInterval? {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if sandwichState(app) == state { return Date().timeIntervalSince(started) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    /// `.keepAlways`, as `VideoBakeUITests` does and for its reason: CLAUDE.md's *"drive it in the
    /// simulator and look at it"* wants the picture kept whether or not the assertion failed.
    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func report(_ name: String, _ seconds: TimeInterval?) {
        XCTContext.runActivity(named: name) { activity in
            activity.add(XCTAttachment(string: seconds.map { "\($0) s" } ?? "never"))
        }
    }

    /// **The bake reaches the canvas the artist is drawing on.**
    ///
    /// Until this stage the picture at rest was composited by `startSandwichRebuild` on the canvas's
    /// own queue, so it arrived a few tens of milliseconds after lift and no test had to wait for it.
    /// It is now a file that a serial `.utility` worker has to write and the canvas has to read back,
    /// which is the whole point (§2.2: *"the main thread never composites"*) and is also the one way
    /// this stage can fail silently — every existing assertion about the canvas samples a pixel, and
    /// the mid-stroke picture has the artist's ink in it too.
    func testTheCanvasComesBackToTheBakedFrameAfterAStroke() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBlendMode(app, layerIndex: 0, to: "multiply")
        XCTAssertEqual(sandwichState(app), "rest",
                       "Setup: a blending leaf is the document Core Animation cannot draw")

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.55, dy: 0.5))
        let afterFirst = waitForSandwich(app, "rest")
        report("rest after the first stroke", afterFirst)
        XCTAssertNotNil(afterFirst,
                        "The canvas is stuck on the mid-stroke pair, which means the frame the stroke "
                        + "landed on was never baked — trap 2 in `updateSandwich` holds until it is")

        // The second stroke is the interesting one: the first spawns a cel, which publishes, so it
        // gets a SwiftUI pass for free. A dab publishes nothing (§5.2), so the second stroke's bake
        // has to be started by the pass that lift itself causes and finished by
        // `FrameBaker.onFrameFinished` — which is the callback this stage installs, and the only
        // thing that brings a pass when the artist has stopped touching the screen.
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.62), to: CGVector(dx: 0.55, dy: 0.62))
        let afterSecond = waitForSandwich(app, "rest")
        report("rest after the second stroke", afterSecond)
        XCTAssertNotNil(afterSecond,
                        "A stroke that publishes nothing still has to reach the bake. A canvas stuck "
                        + "here is `onFrameFinished` not arriving, or arriving on a baker nothing is "
                        + "listening to")
        XCTAssertNotNil(waitForPixelOnCanvas(canvas, at: CGVector(dx: 0.45, dy: 0.62)),
                        "…and the picture it came back to contains the stroke")
    }

    /// **A scrub reaches a baked frame, and the main thread is not what composites it.**
    ///
    /// Stepping the playhead moves `SandwichKey`, so the canvas asks the baker for a different
    /// frame; §2.10 says it keeps the previous picture until that one lands, and §3.3 says stepping
    /// *back* into a frame already visited costs no composite at all because the key has not moved.
    /// The canvas has to be at rest at both ends, and the app has to still be answering — a frozen
    /// main thread would fail the taps rather than the assertion.
    func testSteppingTheFrameLandsOnABakedPictureAtBothEnds() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBlendMode(app, layerIndex: 0, to: "multiply")
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.55, dy: 0.5))
        XCTAssertNotNil(waitForSandwich(app, "rest"), "Setup: frame 0 is baked")

        let next = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let forward = waitForSandwich(app, "rest")
        report("rest on the next frame", forward)
        XCTAssertNotNil(forward, "The frame stepped onto has to bake too — it is the frame the artist is on")

        let previous = app.buttons["timeline.stepBackButton"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        previous.tap()
        let back = waitForSandwich(app, "rest")
        report("rest back on frame 0", back)
        XCTAssertNotNil(back,
                        "Stepping back is §3.3's free clean: the key has not moved, so the file is "
                        + "already there and the canvas should be at rest immediately")
    }

    /// **A keyframed move is served off the bake, and until TODO (53) it was not.**
    ///
    /// The owner, 2026-09-06: *"I then put a move transformation layer on top, and set it to move via
    /// keyframes. When I play the animation, the FPS drops to 8fps. This really shouldnt happen
    /// because from my recollection, it should automatically bake and store frames in disk."*
    ///
    /// They were right, and the reason was one clause. `sandwichEngagesOnCanvas` asked only
    /// `needsCompositorOnCanvas`, which is about blend modes, masks, effects and nodes — a document
    /// whose only unusual feature is a transformation layer answered **false**, so the canvas stayed
    /// on Core Animation's flat row of hosts and never read the bake at all. The pose still appeared,
    /// because `updateInterpolationPreviews` rasterized the posed ink into the host's own slot: a
    /// canvas-sized render on the main actor, MEASURED at **71.9 ms a frame** against **3.7 ms** to
    /// read the same frame back off the store (PERFORMANCE.md §14).
    ///
    /// **`sandwich:rest` is the whole assertion and it is a statement about what is on screen**, not
    /// about a stored value: `updateSandwich`'s trap 2 reaches `rest` only once `sandwichFullKey`
    /// names the frame the artist is on, so it means "the baked frame for *this* frame is the picture
    /// being displayed". Before the fix this test's canvas reported `disengaged` forever. The pixel
    /// probe is the second operand — it is what says the picture reached is the *posed* one rather
    /// than merely a composite.
    func testAKeyframedTransformationLayerPutsTheCanvasOnTheBakedFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-uiTestSeedKeyframedMove"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let engaged = waitForSandwich(app, "rest")
        report("rest on a keyframed transformation layer", engaged)
        XCTAssertNotNil(engaged,
                        "A document whose only compositor-worthy feature is a keyframed "
                        + "transformation layer must engage the sandwich, or the canvas never reads "
                        + "the bake and pays a canvas-sized posed render on the main actor per tick")
        attachScreen("01-frame-0-off-the-bake")

        // The seed's stroke runs from 0.2 to 0.5 of the width at mid-height and the move translates
        // by 0.4 of the width, so this point is ink at frame 0 and has to stay ink: what is being
        // asserted is that the *baked* picture the canvas switched to still contains the artwork.
        XCTAssertNotNil(waitForPixelOnCanvas(canvas, at: CGVector(dx: 0.35, dy: 0.5)),
                        "The baked frame the canvas came to rest on has to contain the ink — a "
                        + "composite of an elided transformation layer over nothing would be blank")

        // Where the ink is at the move's resting key, for the comparison six frames from now.
        let atRest = try XCTUnwrap(inkSpanOnPaper(canvas),
                                   "The ruler has to find white paper with a dark span inside it "
                                   + "before anything it measures means anything")

        // **The cost, as a count** — item (53)'s third checkbox. `derived:` is how many
        // canvas-sized posed or interpolated pictures this canvas has rasterized on the main actor
        // (`CanvasView.derivedRenderCount`). Every frame of a keyframed move is a distinct
        // derivation, so before the fix walking six frames added six of them at 71.9 ms each; with
        // the composite carrying the layer instead, the number must not move at all.
        let before = try XCTUnwrap(derivedRenderCount(app), "the canvas publishes `derived:`")
        let next = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            next.tap()
            XCTAssertNotNil(waitForSandwich(app, "rest"),
                            "Every frame of a move is its own bake key and its own file, and the "
                            + "canvas has to come to rest on each of them")
        }
        attachScreen("02-six-frames-into-the-move")

        let after = try XCTUnwrap(derivedRenderCount(app))
        XCTAssertEqual(after, before,
                       "Walking six frames of a baked move must rasterize no posed ink at all: the "
                       + "picture is on disk and the composite is what puts it on screen. A count "
                       + "that climbed by one per frame is TODO (53) exactly — MEASURED at 71.9 ms "
                       + "a frame against 3.7 ms to read the baked frame instead")

        // **And the move itself, on screen, which is the assertion the rest of this test cannot
        // make.** The probe above says the picture has ink in it; it cannot say the ink is *posed*,
        // because frame 0 is the move's resting key and every implementation whatever agrees there.
        // MEASURED: with `renderNodes` no longer recording a leaf's pose — one line, `poses[index] =
        // pose` — the composite draws the resting ink at every frame, the artist's move is invisible,
        // and **every other assertion in this test stays green**: `derived:` is still 0 (there is no
        // derivation to render), the sandwich still engages (`hasContainerPoseInForce` asks the
        // document, not the tree) and frame 0 still has ink at the probe point.
        //
        // Polled rather than read once, for `waitForSandwich`'s reason: §2.13 lets the canvas show
        // the previous composite for a moment, so what can be asserted is that the ink gets there.
        var travelled: (left: Int, right: Int, paperWidth: Int)?
        let inkDeadline = Date().addingTimeInterval(10)
        repeat {
            travelled = inkSpanOnPaper(canvas)
            if let span = travelled, span.left - atRest.left > span.paperWidth / 20 { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < inkDeadline
        let moved = try XCTUnwrap(travelled, "The ruler lost the paper or the ink six frames in")
        XCTAssertGreaterThan(moved.left - atRest.left, moved.paperWidth / 20, """
            The ink did not travel. Six frames into a keyframed move the drawing beneath the             transformation layer has to be visibly further right — the seed translates by 0.4 of the             canvas — and it is the *composite* that has to carry it now, because the posed render this             test has just asserted never happened is the only other thing that could.
            """)
        XCTAssertGreaterThan(moved.right - atRest.right, moved.paperWidth / 20,
                             "…both edges, so this is the drawing moving rather than growing")

        // **And the owner's own gesture, which is the one the report is about.** Three seconds of a
        // twelve-frame loop at 24 fps is six laps, so the pre-fix canvas would have rasterized posed
        // ink dozens of times over; there is nothing left to count.
        //
        // **The frame counter is deliberately not the instrument.** `PlaybackClock` derives the
        // playhead from elapsed time and *"a late tick skips rather than stretches"* — so an app
        // playing at 8 fps still reaches the right frame at the right second and the label looks
        // perfect. That is exactly why the cost had to be published as a count.
        let play = app.buttons["timeline.playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        Thread.sleep(forTimeInterval: 3)
        play.tap()
        XCTAssertEqual(derivedRenderCount(app), before,
                       "Three seconds of playback — six laps of the loop — must rasterize no posed "
                       + "ink either. This is the owner's report in one line: \"when I play the "
                       + "animation, the FPS drops to 8fps\"")
        attachScreen("03-after-three-seconds-of-playback")
    }

    /// **A held frame is composited once for the whole hold, on the live canvas as well as in the
    /// bake** — TODO (54).
    ///
    /// The owner, 2026-09-07: *"Lets say a frame in the animation is held for a couple cels where
    /// nothing changes. The bake and cache seems to re-render each frame even though they are the
    /// same."*
    ///
    /// The **bake** half of that is answered headlessly and was already pinned:
    /// `FrameBakerLogicTests.testANineFrameHoldIsOneFileAndOneComposite` counts
    /// `Compositor.composite` with `CompositeProbe` and finds one composite and eight `stat`s, and
    /// MEASURED with the dedupe branch mutated off it finds nine. The **cache** half is this
    /// coordinator's pair of half-composites, which no logic test can reach — hence
    /// `CanvasView.sandwichRebuildCount`, published as `rebuilds:` beside `derived:`.
    ///
    /// **The control is the first half of the same scene, and it is what makes the second half mean
    /// anything.** `-uiTestSeedHoldAfterMove` keys a move at frames 0 and 4 of a twelve-frame scene,
    /// so 0→4 is four distinct pictures and 5→11 is seven identical ones, in one document and against
    /// one instrument. A count asserted only over the hold would pass against a counter that was never
    /// incremented, never published, or wired to the wrong thing.
    func testSteppingThroughAHoldDoesNotRecompositeTheLiveCanvasPerFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-uiTestSeedHoldAfterMove"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertNotNil(waitForSandwich(app, "rest"),
                        "A transformation layer engages the sandwich, so the canvas has to come to "
                        + "rest on the baked frame before any of this is measurable")
        attachScreen("01-hold-fixture-frame-0")

        let next = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let start = try XCTUnwrap(readFrameLabel(app), "the timeline publishes the playhead")
        XCTAssertGreaterThanOrEqual(start.total, 12,
                                    "The fixture needs twelve frames: four of move and seven of hold "
                                    + "after them. A scene that stops early would make the hold half "
                                    + "of this test a walk that never moves the playhead, which "
                                    + "passes for the wrong reason")

        /// One step forward, waiting for the canvas to settle on the new frame's baked picture.
        func step() {
            next.tap()
            XCTAssertNotNil(waitForSandwich(app, "rest"),
                            "Every frame of this scene is baked, so the canvas has to reach rest on "
                            + "each of them before the next step is taken")
        }

        // **The control.** Frames 0→4 are the move: four distinct poses, so four distinct render
        // trees, four distinct bake keys and four rebuilds at the very least.
        let beforeMove = try XCTUnwrap(sandwichRebuildCount(app), "the canvas publishes `rebuilds:`")
        for _ in 0..<4 { step() }
        let afterMove = try XCTUnwrap(sandwichRebuildCount(app))
        XCTAssertEqual(readFrameLabel(app)?.current, start.current + 4, "…and the playhead moved")
        XCTAssertGreaterThanOrEqual(afterMove - beforeMove, 4,
                                    "Four frames of a move are four different pictures, so the live "
                                    + "composite has to be rebuilt for each. A count that did not "
                                    + "move here is a broken instrument, and would make the "
                                    + "assertion below meaningless")
        attachScreen("02-end-of-the-move")

        // **The case under test.** Frames 5→11 are past the last pose key, so `AnimationCurve` clamps
        // and every one of them resolves to the frame-4 pose: the same tree, the same leaf versions,
        // the same paper, the same active layer — the same two half-composites, seven times over.
        for _ in 0..<7 { step() }
        XCTAssertEqual(readFrameLabel(app)?.current, start.current + 11,
                       "The playhead has to have walked the whole hold; a step that saturated at the "
                       + "end of the scene would make the count below true of nothing")
        XCTAssertEqual(sandwichRebuildCount(app), afterMove, """
            Seven held frames must cost no live composite at all. Every input to the picture is \
            byte-identical across them — that is what a hold is — and the bake proves it from the \
            other side of the seam by resolving all seven to one file. A count that climbed by one \
            per frame is fourteen canvas-sized composites (`FrameRecipe.compositeHalves` is two) \
            spent to produce the picture already on screen, which is TODO (54) exactly.
            """)
        attachScreen("03-end-of-the-hold")
    }

    /// **Where the seeded stroke's ink begins and ends across the paper, in `canvas.host`'s own
    /// pixels**, with the paper's width beside them so a caller can state a margin as a fraction of
    /// the canvas rather than of a device.
    ///
    /// **Bounded by the paper's own white, and that bound is the whole of it.** `CanvasView` paints
    /// `canvas.host` **black** and the seeded stroke is black on white paper, so a ruler that looked
    /// for dark pixels across the whole element would spend most of its weight on the letterbox
    /// either side of a square canvas in a landscape host — CLAUDE.md records exactly that ruler
    /// reporting that ink which travelled 260 px to the right had moved *left*. So the paper is
    /// found first and the ink is only ever looked for strictly inside it.
    ///
    /// **The paper is the white runs long enough to be paper.** A bare "first and last whitish
    /// pixel" would be extended leftward by the Size and Opacity slider knobs, which are white, sit
    /// inside this element and are separated from the paper by black — and the first dark pixel
    /// after such a start is that black gap rather than any ink. Requiring a run of at least a
    /// twentieth of the scan excludes a knob and a glyph and keeps the paper, whose two runs either
    /// side of the ink are each far longer than that.
    ///
    /// One screenshot for both scans, down the middle column for the paper's vertical span and then
    /// across the row at the centre of it: `rgbaPixel` captures once per sample, which is far too
    /// slow to sweep with and steps clean over anything thin.
    private func inkSpanOnPaper(_ canvas: XCUIElement) -> (left: Int, right: Int, paperWidth: Int)? {
        guard let cg = canvas.screenshot().image.cgImage else { return nil }
        let width = cg.width, height = cg.height, bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &buffer, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        func isPaper(_ x: Int, _ y: Int) -> Bool {
            let offset = y * bytesPerRow + x * 4
            return buffer[offset] > 240 && buffer[offset + 1] > 240 && buffer[offset + 2] > 240
        }
        /// The runs of `isSet` over `0..<count` that are at least a twentieth of it — see above.
        func runs(_ count: Int, _ isSet: (Int) -> Bool) -> [(first: Int, last: Int)] {
            var found: [(first: Int, last: Int)] = []
            var start: Int?
            for i in 0..<count {
                if isSet(i) {
                    if start == nil { start = i }
                } else if let s = start {
                    found.append((s, i - 1)); start = nil
                }
            }
            if let s = start { found.append((s, count - 1)) }
            return found.filter { $0.last - $0.first >= count / 20 }
        }
        let down = runs(height) { isPaper(width / 2, $0) }
        guard let top = down.first?.first, let bottom = down.last?.last else { return nil }
        let row = (top + bottom) / 2
        let across = runs(width) { isPaper($0, row) }
        guard let paperLeft = across.first?.first, let paperRight = across.last?.last,
              paperRight - paperLeft > width / 4 else { return nil }
        var left: Int?, right: Int?
        for x in paperLeft...paperRight where !isPaper(x, row) {
            if left == nil { left = x }
            right = x
        }
        guard let left, let right, left < right else { return nil }
        return (left, right, paperRight - paperLeft)
    }

    /// The `rebuilds:` field of the canvas's published state — see
    /// `CanvasView.sandwichRebuildCount`.
    private func sandwichRebuildCount(_ app: XCUIApplication) -> Int? {
        app.otherElements["canvas.host"].label
            .split(separator: " ")
            .first { $0.hasPrefix("rebuilds:") }
            .flatMap { Int($0.dropFirst("rebuilds:".count)) }
    }

    /// The `derived:` field of the canvas's published state — see `CanvasView.derivedRenderCount`.
    private func derivedRenderCount(_ app: XCUIApplication) -> Int? {
        app.otherElements["canvas.host"].label
            .split(separator: " ")
            .first { $0.hasPrefix("derived:") }
            .flatMap { Int($0.dropFirst("derived:".count)) }
    }

    /// Polls a canvas pixel until it is not the paper. `waitForPixel` in `SandwichCompositingUITests`
    /// is the same idea; this is the one-liner form, kept local because it is the only probe here.
    private func waitForPixelOnCanvas(_ canvas: XCUIElement, at point: CGVector,
                                      timeout: TimeInterval = 10) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let pixel = rgbaPixel(of: canvas, dx: Double(point.dx), dy: Double(point.dy))
            if let pixel, !isWhitish(pixel) { return pixel }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }
}
