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
                      + "regression that puts the per-dab canvas-sized composite back")
        XCTAssertTrue(plan.publishesLivePreviewFrame,
                      "Each overlay refresh is a published preview frame — the only signal "
                      + "VectorEraserUITests can read to tell a live scratch layer from a stuck one")
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

    /// Mode 1 previews by **replacing** the display with a punched copy of the layer's own render.
    /// One canvas-sized render, no second layer, and that is what it cost before item 11 too.
    func testMode1ReplacesTheDisplayAndAddsNoSecondLayer() {
        let plan = VectorPreviewPlan.forVectorLayer(role: .replacement,
                                                    hasScratch: true,
                                                    hasInterpolationImage: false)
        XCTAssertEqual(plan.base, .scratch,
                       "The punched copy *is* the display. Anything else means the artist sees no "
                       + "erasure until they lift")
        XCTAssertFalse(plan.showsScratchLayer,
                       "…and it must not *also* be layered over itself, which would show the "
                       + "un-punched render through the holes it just made")
        XCTAssertTrue(plan.publishesLivePreviewFrame)
    }

    /// Mode 1 at an in-between is still Mode 1: `beginVectorStroke` seeds the scratch from the
    /// evaluated frame rather than from the (empty) canvas, so the role — not the presence of an
    /// interpolated image — decides the base slot. An interpolation image winning here would show
    /// the derived frame with no holes in it for the whole drag.
    func testMode1AtAnInBetweenStillShowsThePunchedCopy() {
        let plan = VectorPreviewPlan.forVectorLayer(role: .replacement,
                                                    hasScratch: true,
                                                    hasInterpolationImage: true)
        XCTAssertEqual(plan.base, .scratch)
        XCTAssertFalse(plan.showsScratchLayer)
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
                           "'.none' must add no layer — hasScratch=\(hasScratch)")
            XCTAssertFalse(plan.publishesLivePreviewFrame,
                           "…and publish no frames, which VectorEraserUITests asserts as 0 "
                           + "— hasScratch=\(hasScratch)")
        }
    }

    // MARK: - The properties that hold across every input

    /// **The scratch layer appears for exactly one role.** Stated over the whole domain rather than
    /// role by role, because the cost item 11 removed is paid by whoever shows a second canvas-sized
    /// image, and "only `.overlay` does" is the invariant that keeps the other two at one operation.
    func testOnlyTheOverlayRoleEverShowsASecondLayer() {
        forEveryCombination { role, hasScratch, hasInterpolation, plan in
            let expected = role == .overlay && hasScratch
            XCTAssertEqual(plan.showsScratchLayer, expected,
                           "role=\(role.traceName) scratch=\(hasScratch) interp=\(hasInterpolation)")
        }
    }

    /// **No scratch, no preview, ever** — the plan cannot ask for an image that does not exist.
    /// `refreshDisplay` reads `vectorScratch?` optionally, so a plan that said otherwise would not
    /// crash; it would quietly hand the scratch layer nil and hide it, and the bug would surface as
    /// a stroke that previews on some gestures and not others.
    func testNoPlanAsksForAScratchThatIsNotThere() {
        forEveryCombination { role, hasScratch, _, plan in
            guard !hasScratch else { return }
            XCTAssertFalse(plan.showsScratchLayer, "role=\(role.traceName)")
            XCTAssertNotEqual(plan.base, .scratch, "role=\(role.traceName)")
            XCTAssertFalse(plan.publishesLivePreviewFrame, "role=\(role.traceName)")
        }
    }

    /// **A published frame means something was published.** The counter is the one number
    /// `lastVectorGestureTrace` carries, and `VectorEraserUITests` reads it to decide whether a live
    /// path ran at all — so it has to track the preview rather than the refresh. A refresh that
    /// shows only the committed render has previewed nothing, whatever role is set.
    func testAFrameIsPublishedExactlyWhenSomethingOtherThanTheCommittedContentIsShown() {
        forEveryCombination { role, hasScratch, hasInterpolation, plan in
            let previewed = plan.base == .scratch || plan.showsScratchLayer
            XCTAssertEqual(plan.publishesLivePreviewFrame, previewed,
                           "role=\(role.traceName) scratch=\(hasScratch) interp=\(hasInterpolation)")
        }
    }

    /// The interpolated frame wins the base slot wherever it exists **except** under `.replacement`,
    /// whose scratch was itself seeded from that frame. This is the folded-in early return stated as
    /// a property, and it is why the fold is safe.
    func testTheDerivedFrameWinsTheBaseSlotExceptWhereTheScratchAlreadyContainsIt() {
        forEveryCombination { role, hasScratch, hasInterpolation, plan in
            guard hasInterpolation else { return }
            let expected: VectorPreviewPlan.Base = (role == .replacement && hasScratch)
                ? .scratch : .interpolation
            XCTAssertEqual(plan.base, expected,
                           "role=\(role.traceName) scratch=\(hasScratch)")
        }
    }
}
