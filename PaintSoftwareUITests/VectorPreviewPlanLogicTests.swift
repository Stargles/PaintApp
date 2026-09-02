import XCTest

/// The three vector-preview roles, pinned headlessly.
///
/// **Why these are worth a file.** `VectorPreviewPlan` is the decision
/// `StrokeCanvasView.refreshDisplay` makes on every touch-move of every vector stroke, and
/// [PERFORMANCE.md](PERFORMANCE.md) item 11 rewrote it — deleting a per-dab canvas-sized allocation
/// and two blits that cost 53.8 ms a dab at 4096² on the owner's iPad. [BUGS.md](BUGS.md) calls the
/// code it lives in the most gesture-sensitive in the app, and the other two roles were **already**
/// one-operation paths that the change must not have touched. "It still works" is not observable
/// from a raster comparison here: `.replacement` regressing does not draw the wrong pixels, it draws
/// the *right* pixels at the wrong time — the artist erases and sees nothing until they lift.
///
/// `StrokeCanvasView.swift` is not a member of this target, so none of that is reachable from a
/// headless test while the decision lives inside the view. It does not, which is the point of the
/// extraction: the ~250 s fast tier now covers what previously needed the 22-minute vector-eraser UI
/// suite. That suite still runs — it is the only thing that can prove the *view* honours the plan —
/// but it is no longer the first place a mistake here shows up.
final class VectorPreviewPlanLogicTests: XCTestCase {

    /// Every combination of the three inputs, so a claim about "the general case" is checked over
    /// the whole domain rather than at the two points that happened to come to mind. Twelve is small
    /// enough to be exhaustive, and being exhaustive is what lets `forVectorLayer` fold the old
    /// interpolation early-return into the general path with an argument instead of a hope.
    private func forEveryCombination(
        _ body: (_ role: VectorScratchRole, _ hasScratch: Bool, _ hasInterpolation: Bool,
                 _ plan: VectorPreviewPlan) -> Void
    ) {
        for role in [VectorScratchRole.overlay, .replacement, .none] {
            for hasScratch in [false, true] {
                for hasInterpolation in [false, true] {
                    body(role, hasScratch, hasInterpolation,
                         .forVectorLayer(role: role,
                                         hasScratch: hasScratch,
                                         hasInterpolationImage: hasInterpolation))
                }
            }
        }
    }

    // MARK: - Role 1 of 3: .overlay, the one item 11 changed

    /// A paint stroke's ink goes in the **scratch layer**, over an untouched committed render.
    ///
    /// The assertion that matters is `base == .committedRender` *together with*
    /// `showsScratchLayer == true`. Before item 11 the base slot received a freshly allocated bitmap
    /// holding both images flattened; a plan that put the flattened result in the base slot would
    /// look identical on screen and cost exactly what the bug cost. Two slots, two images, is the
    /// change — and `VectorPreviewPlan.Base` has no case that could say otherwise.
    func testAPaintStrokeShowsItsInkInItsOwnLayerOverTheCommittedRender() {
        let plan = VectorPreviewPlan.forVectorLayer(role: .overlay,
                                                    hasScratch: true,
                                                    hasInterpolationImage: false)
        XCTAssertEqual(plan.base, .committedRender,
                       "The base slot holds the canvas's own render, unmodified — an `.overlay` "
                       + "stroke does not touch the canvas until lift")
        XCTAssertTrue(plan.showsScratchLayer,
                      "The live ink must reach the screen through its own layer. False here is the "
                      + "regression that puts the per-dab canvas-sized composite back — and it is "
                      + "also the published-frame count VectorEraserUITests reads to tell a live "
                      + "scratch layer from a stuck one")
    }

    /// Drawing at an in-between keeps its stroke preview: the derived frame takes the base slot and
    /// the scratch still gets its own layer. This is the combination the old code reached by an
    /// early return that no longer exists, so it is the one most worth naming.
    func testAPaintStrokeAtAnInBetweenPreviewsOverTheDerivedFrame() {
        let plan = VectorPreviewPlan.forVectorLayer(role: .overlay,
                                                    hasScratch: true,
                                                    hasInterpolationImage: true)
        XCTAssertEqual(plan.base, .interpolation,
                       "At an in-between the cel's own canvas is empty, so the derived frame is the "
                       + "base — rendering the canvas instead would show nothing under the stroke")
        XCTAssertTrue(plan.showsScratchLayer, "…and the stroke still previews over it")
    }

    // MARK: - Role 2 of 3: .replacement, which must not regress

    /// Mode 1 previews by punching into a copy of the layer's own render — a copy of the **window**
    /// the stroke has reached, since `StrokeScratch`, so the copy cannot be the whole display any
    /// more. The committed render is the base and the punched window sits over it, with the base
    /// punched out underneath (`StrokeCanvasView.showScratch`).
    ///
    /// `showsScratchLayer == true` is the assertion that matters. False is the regression that
    /// leaves the erasure in a buffer nothing shows: the artist drags the eraser across their line
    /// and sees nothing happen until they lift.
    func testMode1ShowsItsPunchedWindowOverTheCommittedRender() {
        let plan = VectorPreviewPlan.forVectorLayer(role: .replacement,
                                                    hasScratch: true,
                                                    hasInterpolationImage: false)
        XCTAssertEqual(plan.base, .committedRender,
                       "The window is the size of the stroke, so the layer's own render is what "
                       + "covers the rest of the canvas")
        XCTAssertTrue(plan.showsScratchLayer,
                      "The punched window has to reach the screen, and its own layer is now the "
                      + "only slot that can carry it")
    }

    /// Mode 1 at an in-between is still Mode 1, and now takes the same base as every other role:
    /// `beginVectorStroke` seeds the scratch's backdrop from the evaluated frame, so the frame is
    /// both what the window was copied from and what surrounds it.
    func testMode1AtAnInBetweenPunchesTheDerivedFrame() {
        let plan = VectorPreviewPlan.forVectorLayer(role: .replacement,
                                                    hasScratch: true,
                                                    hasInterpolationImage: true)
        XCTAssertEqual(plan.base, .interpolation)
        XCTAssertTrue(plan.showsScratchLayer)
    }

    // MARK: - Role 3 of 3: .none, which must not regress either

    /// Mode 3 previews nothing at all: it commits real cuts during the drag, so the canvas render
    /// alone is truth. One render, no scratch layer, no frames — and **regardless of whether a
    /// scratch texture exists**, which it does: `beginVectorStroke` allocates an empty one for every
    /// role. The role is what suppresses the preview, not the absence of a texture, and a plan that
    /// keyed off the texture would light up a layer full of nothing on every touch sample.
    ///
    /// **Mode 2 used to be here too, and moved to `.replacement` on 2026-08-22** — it commits on
    /// lift, so before then it showed the artist nothing for the whole drag. `.none` is now Mode 3
    /// alone. See `VectorScratchRole`.
    func testMode3PreviewsNothingEvenThoughAScratchExists() {
        for hasScratch in [false, true] {
            let plan = VectorPreviewPlan.forVectorLayer(role: .none,
                                                        hasScratch: hasScratch,
                                                        hasInterpolationImage: false)
            XCTAssertEqual(plan.base, .committedRender, "hasScratch=\(hasScratch)")
            XCTAssertFalse(plan.showsScratchLayer,
                           "'.none' must add no layer, and so publish no frames — which "
                           + "VectorEraserUITests asserts as 0. hasScratch=\(hasScratch)")
        }
    }

    // MARK: - The properties that hold across every input

    /// **The scratch layer appears for exactly the roles that draw.** Stated over the whole domain
    /// rather than role by role. It was "only `.overlay`" until `StrokeScratch` made the scratch a
    /// window: a window cannot fill the base slot, so `.replacement` joined the layer rather than
    /// replacing the display, and `.none` — which draws nothing at all — is the one that stays out.
    func testEveryRoleThatDrawsShowsItsScratchLayer() {
        forEveryCombination { role, hasScratch, hasInterpolation, plan in
            let expected = role != .none && hasScratch
            XCTAssertEqual(plan.showsScratchLayer, expected,
                           "role=\(role.traceName) scratch=\(hasScratch) interp=\(hasInterpolation)")
        }
    }

    /// **No scratch, no preview, ever** — the plan cannot ask for an image that does not exist.
    /// `refreshDisplay` reads `scratch?` optionally, so a plan that said otherwise would not
    /// crash; it would quietly hand the scratch layer nil and hide it, and the bug would surface as
    /// a stroke that previews on some gestures and not others.
    func testNoPlanAsksForAScratchThatIsNotThere() {
        forEveryCombination { role, hasScratch, _, plan in
            guard !hasScratch else { return }
            XCTAssertFalse(plan.showsScratchLayer, "role=\(role.traceName)")
        }
    }

    /// The interpolated frame wins the base slot wherever it exists, in **every** role. It used to
    /// lose to `.replacement`, whose canvas-sized scratch held its own copy of that frame; the
    /// window holds a copy of only the part it has reached, so the frame has to surround it.
    func testTheDerivedFrameWinsTheBaseSlotWhereverItExists() {
        forEveryCombination { role, hasScratch, hasInterpolation, plan in
            guard hasInterpolation else { return }
            XCTAssertEqual(plan.base, .interpolation,
                           "role=\(role.traceName) scratch=\(hasScratch)")
        }
    }
}

/// `DeferredVectorRender`'s two ordering rules — RENDER.md stage 2's second half, pinned here for
/// exactly `VectorPreviewPlanLogicTests`' reason: the decision lives outside `StrokeCanvasView` so
/// that a headless test can reach it, and what it decides is not a picture but *when* a picture may
/// be claimed to be on screen.
///
/// **The failure these guard against is a frozen canvas, not a wrong pixel.**
/// `StrokeCanvasView.refreshDisplayIfStale` repaints exactly when `displayedVectorVersion` differs
/// from the canvas's, so a step that records a version as displayed before its rasterize has landed
/// leaves the artist looking at the previous picture until some unrelated edit happens to move the
/// version again. There is no wrong colour anywhere; the canvas simply stops updating.
final class DeferredVectorRenderLogicTests: XCTestCase {

    private func canvas(withInk: Bool) -> VectorCanvas {
        let canvas = VectorCanvas(size: CGSize(width: 32, height: 32), elements: [])
        guard withInk else { return canvas }
        canvas.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: 4, opacity: 1,
                                      samples: [VectorSample(x: 4, y: 16, pressure: 1),
                                                VectorSample(x: 28, y: 16, pressure: 1)]))
        return canvas
    }

    /// An empty canvas and a memoized one both answer immediately — the first because there is
    /// nothing to draw, the second because it is already drawn. Between them they are every refresh
    /// during a stroke, which is what keeps a paint gesture exactly as cheap as it was: `.overlay`
    /// does not touch the display list until lift.
    func testAnAlreadyAnsweredCanvasIsShownWithoutLeavingTheMainThread() {
        let empty = canvas(withInk: false)
        XCTAssertEqual(DeferredVectorRender.step(for: empty.cachedRender(), pending: nil),
                       .showNow(version: empty.version))

        let inked = canvas(withInk: true)
        _ = inked.render()
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil),
                       .showNow(version: inked.version))
        XCTAssertEqual(inked.rasterizations, 1, "Asking the question must not answer it")
    }

    /// A canvas whose render was invalidated — which is a cel one instant after a stroke commits —
    /// goes off the main thread, and a second refresh while that is running does not start another.
    func testACommittedStrokeRasterizesElsewhereAndOnlyOnce() {
        let inked = canvas(withInk: true)
        let version = inked.version
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil),
                       .rasterize(version: version))
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: version), .wait,
                       "A second refresh while the same version is rasterizing must not queue a second one")
    }

    /// **A rasterize running for an older version does not stop a newer one starting**, which is the
    /// case a `pending != nil` test would get wrong: the older result can never be shown, so treating
    /// it as "something is already running" would leave the canvas waiting on a render that is
    /// destined to be thrown away. The vector eraser's Mode 3 commits per touch sample and is where
    /// this happens on every drag.
    func testAnInvalidationDuringARasterizeStartsTheNewerOne() {
        let inked = canvas(withInk: true)
        let stale = inked.version
        inked.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                     size: 4, opacity: 1,
                                     samples: [VectorSample(x: 16, y: 4, pressure: 1),
                                               VectorSample(x: 16, y: 28, pressure: 1)]))
        XCTAssertNotEqual(inked.version, stale, "Setup: the edit must move the version")
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: stale),
                       .rasterize(version: inked.version))
    }

    /// The completion rule, both clauses. Either one alone lets a wrong thing through — a stale
    /// render landing over the one that replaced it, or a version being recorded as displayed after
    /// the canvas has left it.
    func testAFinishedRasterizeIsShownOnlyWhenItIsBothCurrentAndAwaited() {
        XCTAssertTrue(DeferredVectorRender.mayShow(rendered: 7, current: 7, pending: 7))
        XCTAssertFalse(DeferredVectorRender.mayShow(rendered: 7, current: 8, pending: 7),
                       "The artist has drawn again; these pixels are of a version that is no longer the canvas")
        XCTAssertFalse(DeferredVectorRender.mayShow(rendered: 7, current: 7, pending: 8),
                       "A newer rasterize of the same canvas superseded this one")
        XCTAssertFalse(DeferredVectorRender.mayShow(rendered: 7, current: 7, pending: nil),
                       "Nothing is waiting on this result")
    }
}
