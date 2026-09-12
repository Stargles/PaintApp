import XCTest
import SwiftUI

/// **TODO (42) — Colour, Size and Opacity on a selection, live, as one undo step.** The session in
/// `CanvasManager+SelectionEdit.swift`: `beginSelectionEdit` resolves the loop, `previewSelectionEdit`
/// rewrites the caught elements in place on every tick, `commitSelectionEdit` records the one step,
/// `cancelSelectionEdit` puts the pre-drag list back.
///
/// Every assertion here is on a stored field, and the file says so: what is *drawn* is
/// `SelectionEditUITests`' business, from a fresh document, off the screen. What these pin is the
/// arithmetic a drag has to get right whatever the picture looks like — which ids a tick may touch,
/// what "one step" means across ten ticks, what a cancel puts back, and which kinds each control
/// reaches. The mutation each test caught is in its doc comment.
final class SelectionEditLogicTests: XCTestCase {

    // MARK: - Fixtures (`LassoMoveLogicTests`' shape)

    private func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CodableColor {
        CodableColor(red: r, green: g, blue: b, alpha: a)
    }

    /// A manager with a raster layer at 0 and an **active vector layer at 1**.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    /// A horizontal three-sample stroke at `y`, from x = 10 to x = 54 — well inside a 64-point canvas.
    private func stroke(y: CGFloat, size: CGFloat = 4, opacity: Double = 1,
                        colour: CodableColor? = nil, composite: StrokeComposite = .paint,
                        from x0: CGFloat = 10, to x1: CGFloat = 54) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: colour ?? self.colour(0, 0, 0),
                     size: size, opacity: opacity,
                     samples: [VectorSample(x: x0, y: y, pressure: 1),
                               VectorSample(x: (x0 + x1) / 2, y: y, pressure: 1),
                               VectorSample(x: x1, y: y, pressure: 1)],
                     composite: composite)
    }

    private func loop(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ path: CGPath) {
        manager.selection = Selection(path: path, bounds: path.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    /// Undo steps recorded since the fixture was built — `LassoMoveLogicTests.stepsSince`'s reason:
    /// `fixture()` records two structural steps of its own.
    private func stepsSince(_ baseline: Int, _ manager: CanvasManager) -> Int {
        manager.history.undoStack.count - baseline
    }

    private func sizes(_ vector: VectorCanvas) -> [CGFloat] { vector.elements.compactMap { $0.stroke?.size } }
    private func opacities(_ vector: VectorCanvas) -> [Double] { vector.elements.compactMap { $0.stroke?.opacity } }

    /// Three strokes at y = 10, 20 and 50, sizes 4, 6 and 8; a loop that catches the first two whole.
    private func threeStrokes() -> (CanvasManager, Int, VectorCanvas, Set<UUID>, UUID) {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 10, size: 4, opacity: 0.4))
        vector.addStroke(stroke(y: 20, size: 6, opacity: 0.6))
        vector.addStroke(stroke(y: 50, size: 8, opacity: 0.8))
        let caught = Set(vector.elements.prefix(2).map(\.id))
        let outside = vector.elements[2].id
        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 28)))
        return (manager, layerIndex, vector, caught, outside)
    }

    // MARK: - Scope: only the selected ids

    /// **Each control rewrites only what the loop caught.** Two strokes inside, one outside; after each
    /// one-shot the two carry the value and the third carries what it had.
    ///
    /// Mutation caught: dropping `session.caught.contains(element.id)` from `previewSelectionEdit`'s
    /// loop rewrites every element in the cel — the third stroke takes the value and all three
    /// assertions on it go red.
    func testColourSizeAndOpacityEachRewriteOnlyTheSelectedIds() {
        let (manager, _, vector, caught, outside) = threeStrokes()
        let baseline = manager.history.undoStack.count

        XCTAssertTrue(manager.applySelectionEdit(.color(colour(1, 0, 0))), "the recolour changed something")
        for element in vector.elements {
            let stroke = element.stroke!
            if caught.contains(stroke.id) {
                XCTAssertEqual(stroke.color, colour(1, 0, 0), "a caught stroke takes the colour")
            } else {
                XCTAssertEqual(stroke.id, outside)
                XCTAssertEqual(stroke.color, colour(0, 0, 0), "the stroke outside the loop keeps its colour")
            }
        }

        XCTAssertTrue(manager.applySelectionEdit(.size(12)))
        XCTAssertEqual(sizes(vector), [12, 12, 8], "size reaches the two caught strokes and not the third")

        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.25)))
        XCTAssertEqual(opacities(vector), [0.25, 0.25, 0.8], "opacity reaches the two and not the third")

        XCTAssertEqual(stepsSince(baseline, manager), 3, "three one-shots, three steps")
    }

    // MARK: - The readout

    /// **The swatch defaults to the selection's colour, and a mixed loop opens on the most common.**
    /// Two black strokes and a red one: black, and Mixed. The red one alone: red, and not mixed. A
    /// loop around a photograph: no colour at all.
    ///
    /// Mutation caught: returning `order.first` from `SelectionStyle.of`'s `mode` instead of the
    /// most common turns the two-black-one-red loop red when the red stroke is first in the list —
    /// the fixture below puts it first for exactly that reason.
    func testTheSwatchDefaultsToTheSelectionsColourAndAMixedLoopOpensOnTheMostCommon() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 10, size: 9, opacity: 0.5, colour: colour(1, 0, 0)))
        vector.addStroke(stroke(y: 20, size: 4, opacity: 1))
        vector.addStroke(stroke(y: 30, size: 4, opacity: 1))

        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 36)))
        var style = manager.selectionStyle
        XCTAssertEqual(style.color, colour(0, 0, 0), "two of three are black, so the swatch opens on black")
        XCTAssertTrue(style.colorIsMixed, "and says the loop holds more than one colour")
        XCTAssertEqual(style.size, 4, "two of three are 4 pt")
        XCTAssertTrue(style.sizeIsMixed)
        XCTAssertEqual(style.opacity, 1)
        XCTAssertTrue(style.opacityIsMixed)

        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 14)))
        style = manager.selectionStyle
        XCTAssertEqual(style.color, colour(1, 0, 0), "the red stroke alone: red")
        XCTAssertFalse(style.colorIsMixed, "and not mixed")
        XCTAssertEqual(style.size, 9)
        XCTAssertFalse(style.sizeIsMixed)
        XCTAssertEqual(style.opacity, 0.5)

        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 52),
                                                                     scale: 1, rotation: 0)))
        select(manager, layerIndex, loop(CGRect(x: 20, y: 44, width: 24, height: 18)))
        style = manager.selectionStyle
        XCTAssertNil(style.color, "a loop around a photograph has no colour to default to")
        XCTAssertNil(style.size)
        XCTAssertNil(style.opacity)

        manager.selection = nil
        XCTAssertEqual(manager.selectionStyle, .unavailable, "no selection, nothing to show")
    }

    /// **Mid-drag the readout is the live value, and it touches no geometry**: the tally is over the
    /// session's own list, so it is the value every caught element already holds.
    func testTheReadoutDuringADragIsTheLiveValueAndIsNoLongerMixed() {
        let (manager, _, _, _, _) = threeStrokes()
        XCTAssertTrue(manager.selectionStyle.sizeIsMixed, "4 and 6 pt: mixed before the drag")
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(20))
        let style = manager.selectionStyle
        XCTAssertEqual(style.size, 20, "the slider shows what the finger set")
        XCTAssertFalse(style.sizeIsMixed, "and the first tick made the loop agree")
        XCTAssertTrue(style.opacityIsMixed, "the other control's readout is untouched by this drag")
        manager.cancelSelectionEdit()
        XCTAssertTrue(manager.selectionStyle.sizeIsMixed, "cancelled: mixed again")
    }

    // MARK: - One drag, one step

    /// **A ten-tick drag is one undo step, and one `undo()` puts every stroke's own width back.**
    /// The two caught strokes start at *different* sizes, so "restores the original" is a claim about
    /// each rather than about a shared number.
    ///
    /// Mutation caught: registering a step per tick (calling `commitSelectionEdit()` then
    /// `beginSelectionEdit` inside `previewSelectionEdit`) makes `stepsSince` read 10 and one undo
    /// restore only the ninth tick's sizes.
    func testATenTickDragIsOneUndoStepAndOneUndoRestoresEveryStrokesOwnSize() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        let before = sizes(vector)
        XCTAssertEqual(before, [4, 6, 8])

        XCTAssertTrue(manager.beginSelectionEdit(.size))
        for tick in 1...10 {
            manager.previewSelectionEdit(.size(CGFloat(10 + tick)))
            XCTAssertEqual(stepsSince(baseline, manager), 0, "tick \(tick) recorded a step")
            XCTAssertEqual(sizes(vector), [CGFloat(10 + tick), CGFloat(10 + tick), 8],
                           "tick \(tick) is on the canvas — the preview is live, not deferred")
        }
        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 1, "ten ticks, one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .resizeSelectionStrokes)
        XCTAssertEqual(sizes(vector), [20, 20, 8])

        manager.undo()
        XCTAssertEqual(sizes(vector), before, "one undo puts 4 and 6 back — each its own, not one shared width")
        manager.redo()
        XCTAssertEqual(sizes(vector), [20, 20, 8], "and one redo brings the drag's end back")
    }

    /// **A slider grabbed without a session open still previews and still commits once**: the first
    /// value write can land before `onEditingChanged(true)`, so `previewSelectionEdit` opens the
    /// session and the touch-down's `beginSelectionEdit` finds it open for the same control.
    func testAPreviewWithNoSessionOpenBeginsOneAndTheTouchDownReusesIt() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        manager.previewSelectionEdit(.opacity(0.3))
        XCTAssertTrue(manager.beginSelectionEdit(.opacity), "the touch-down lands on the open session")
        manager.previewSelectionEdit(.opacity(0.2))
        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 1)
        XCTAssertEqual(manager.history.undoStack.last?.label, .changeSelectionOpacity)
        XCTAssertEqual(opacities(vector), [0.2, 0.2, 0.8])
    }

    /// **Switching controls mid-drag commits the first drag and opens the second** — two steps, in
    /// order, rather than one step that mixes a size with an opacity.
    func testASecondControlMidSessionCommitsTheFirstAsItsOwnStep() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(15))
        manager.previewSelectionEdit(.opacity(0.5))
        XCTAssertEqual(stepsSince(baseline, manager), 1, "the size drag closed when the opacity one began")
        XCTAssertEqual(manager.history.undoStack.last?.label, .resizeSelectionStrokes)
        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 2)
        XCTAssertEqual(manager.history.undoStack.last?.label, .changeSelectionOpacity)
        XCTAssertEqual(sizes(vector), [15, 15, 8])
        XCTAssertEqual(opacities(vector), [0.5, 0.5, 0.8])
    }

    // MARK: - Nothing changed, nothing recorded

    /// **A drag that ends where it began records nothing**, and under Cut it throws the split away:
    /// the list the artist is left with is the list they started with, element for element.
    ///
    /// Mutation caught: comparing the *lists* rather than the fields in `commitSelectionEdit` — under
    /// Cut they always differ by the split, so a drag back to the start value would record a step
    /// whose only content is a cut the artist never asked for.
    func testADragThatEndsWhereItBeganRecordsNothingAndUnderCutThrowsTheSplitAway() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 20, size: 6))
        let originalID = vector.elements[0].id
        let baseline = manager.history.undoStack.count
        // x ≥ 30: the stroke straddles the loop, so Cut splits it into two.
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertEqual(manager.selectionMembership, .cutting, "fixture: the default rule cuts")

        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(20))
        XCTAssertEqual(vector.elements.count, 2, "mid-drag the stroke is split and the inside piece is 20 pt")
        XCTAssertEqual(Set(sizes(vector)), [6, 20])
        manager.previewSelectionEdit(.size(6))
        XCTAssertFalse(manager.commitSelectionEdit(), "back at 6 pt: nothing to record")
        XCTAssertEqual(stepsSince(baseline, manager), 0)
        XCTAssertEqual(vector.elements.count, 1, "and the split is gone")
        XCTAssertEqual(vector.elements[0].id, originalID, "the stroke is the artist's own again")
        XCTAssertEqual(sizes(vector), [6])
    }

    /// **A picker opened and closed untouched leaves no trace** — no step, no render, no version bump.
    func testASessionOpenedAndClosedWithoutATickLeavesNoTrace() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        let version = vector.version
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        XCTAssertFalse(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 0)
        XCTAssertEqual(vector.version, version, "nothing was assigned, so nothing has to redraw")

        // And a first tick that changes nothing — the picker opened on the selection's own colour —
        // assigns nothing either.
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        manager.previewSelectionEdit(.color(colour(0, 0, 0)))
        XCTAssertEqual(vector.version, version, "a tick at the current value is not an edit")
        XCTAssertFalse(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 0)
    }

    // MARK: - Cancel

    /// **Cancel puts the pre-drag list back with no entry** — by the call, by the selection being
    /// cleared mid-drag, and by undo pressed mid-drag, which then undoes the *previous* step.
    ///
    /// Mutation caught: `cancelSelectionEdit` dropping the session without restoring
    /// `elementsBefore` leaves the last tick's sizes on the canvas — the first assertion after each
    /// cancel goes red.
    func testCancelRestoresThePreDragStateWithNoEntryHoweverItIsReached() {
        let (manager, _, vector, _, _) = threeStrokes()
        // One real step to undo past, so the mid-drag undo below has something to land on.
        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.9)))
        let baseline = manager.history.undoStack.count
        let before = sizes(vector)

        // 1. The call.
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(30))
        XCTAssertEqual(sizes(vector), [30, 30, 8])
        manager.cancelSelectionEdit()
        XCTAssertEqual(sizes(vector), before, "cancel: the sizes the artist started with")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and no step")
        XCTAssertNil(manager.selectionEdit)

        // 2. The selection cleared under the finger.
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(31))
        manager.deselect()
        XCTAssertEqual(sizes(vector), before, "deselect mid-drag: the sizes the artist started with")
        XCTAssertEqual(stepsSince(baseline, manager), 0)
        XCTAssertNil(manager.selectionEdit, "the session is closed, not merely detached from its loop")
        manager.previewSelectionEdit(.size(32))
        XCTAssertEqual(sizes(vector), before, "a tick with no selection has nothing to be about")

        // 3. Undo under the finger: the drag is discarded and the press undoes the opacity step.
        let (manager2, _, vector2, _, _) = threeStrokes()
        XCTAssertTrue(manager2.applySelectionEdit(.opacity(0.9)))
        XCTAssertEqual(opacities(vector2), [0.9, 0.9, 0.8])
        XCTAssertTrue(manager2.beginSelectionEdit(.size))
        manager2.previewSelectionEdit(.size(33))
        manager2.undo()
        XCTAssertEqual(sizes(vector2), [4, 6, 8], "undo mid-drag: the drag is thrown away")
        XCTAssertEqual(opacities(vector2), [0.4, 0.6, 0.8], "and the press undid the step before it")
        XCTAssertNil(manager2.selectionEdit)
    }

    // MARK: - Per kind

    /// **Fills and text take colour and opacity; images and videos take nothing; size reaches only
    /// strokes.** `SelectionEditKind`'s table, pinned row by row. Under Touching so that no kind is
    /// cut and each element keeps its id through all three edits.
    ///
    /// Mutation caught: adding a `(.size, .fill)` arm to `rewritten` that wrote `fill.opacity` (the
    /// nearest field a fill has) reddens the fill's size row; dropping the `.paint` guard from the
    /// colour arm reddens the eraser row.
    func testFillsAndTextTakeColourAndOpacityImagesAndVideosTakeNothingAndSizeReachesOnlyStrokes() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 8, size: 4, opacity: 0.5))
        vector.addStroke(stroke(y: 14, size: 5, opacity: 0.5, composite: .erase))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 12, y: 20, width: 20, height: 6), transform: nil),
                                         color: colour(0, 0, 1, 0.25), opacity: 0.5))
        var recipe = TextRecipe(string: "hi")
        recipe.opacity = 0.7
        recipe.color = colour(0, 0, 0, 0.4)
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 22, y: 30),
                                                             size: CGSize(width: 12, height: 8))))
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 44),
                                                                     scale: 1, rotation: 0)))
        var video = VectorVideoElement(assetURL: URL(fileURLWithPath: "/dev/null"),
                                       assetFileName: "null", naturalSize: CGSize(width: 8, height: 4),
                                       sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1),
                                       speed: 1,
                                       transform: LayerTransform(position: CGPoint(x: 30, y: 54),
                                                                 scale: 1, rotation: 0))
        video.displayFrame = CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: 8, height: 4),
                                                      size: CGSize(width: 8, height: 4))
        vector.elements.append(.video(video))
        vector.bumpVersion()
        let ids = vector.elements.map(\.id)

        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 60)))
        manager.setSelectionMembership(.touching)
        let baseline = manager.history.undoStack.count

        XCTAssertTrue(manager.applySelectionEdit(.color(colour(1, 0, 0))))
        XCTAssertTrue(manager.applySelectionEdit(.size(11)))
        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.3)))
        XCTAssertEqual(stepsSince(baseline, manager), 3)
        XCTAssertEqual(vector.elements.map(\.id), ids, "Touching: every element keeps its id and its place")

        // Looked up by kind rather than by index: `addImage` and `addFill` place their elements by
        // their own rules, and this test is about what each kind takes, not where it sits.
        let strokes = vector.elements.compactMap(\.stroke)
        guard let paint = strokes.first(where: { $0.composite == .paint }),
              let eraser = strokes.first(where: { $0.composite == .erase }),
              let fill = vector.elements.compactMap(\.fill).first,
              let text = vector.elements.compactMap(\.text).first,
              let image = vector.elements.compactMap(\.image).first,
              let placedVideo = vector.elements.compactMap(\.video).first else {
            return XCTFail("fixture: one element of every kind")
        }
        XCTAssertEqual(paint.color, colour(1, 0, 0), "paint stroke: colour")
        XCTAssertEqual(paint.size, 11, "paint stroke: size")
        XCTAssertEqual(paint.opacity, 0.3, "paint stroke: opacity")

        XCTAssertEqual(eraser.color, colour(0, 0, 0), "eraser: no colour — a punch reads only alpha")
        XCTAssertEqual(eraser.size, 11, "eraser: size, because the hole's width is visible")
        XCTAssertEqual(eraser.opacity, 0.3, "eraser: opacity, because how much it removes is visible")

        XCTAssertEqual(fill.color, colour(1, 0, 0, 0.25), "fill: the hue, keeping its own alpha")
        XCTAssertEqual(fill.opacity, 0.3, "fill: opacity")

        XCTAssertEqual(text.recipe.color, colour(1, 0, 0, 0.4), "text: the hue, keeping its own alpha")
        XCTAssertEqual(text.recipe.opacity, 0.3, "text: opacity")
        XCTAssertEqual(text.recipe.typography.pointSize, recipe.typography.pointSize,
                       "text: size is the strokes' width, not the type size — untouched")

        XCTAssertEqual(image.transform, LayerTransform(position: CGPoint(x: 30, y: 44), scale: 1, rotation: 0),
                       "image: nothing, from any of the three")
        XCTAssertEqual(placedVideo.transform, LayerTransform(position: CGPoint(x: 30, y: 54), scale: 1, rotation: 0),
                       "video: nothing, from any of the three")

        // And a loop that catches only the two kinds that take nothing is refused as "nothing to do":
        // no step, and the one-shot says so.
        select(manager, layerIndex, loop(CGRect(x: 20, y: 40, width: 24, height: 20)))
        XCTAssertFalse(manager.applySelectionEdit(.color(colour(0, 1, 0))), "a photo and a video: nothing changed")
        XCTAssertFalse(manager.applySelectionEdit(.size(3)))
        XCTAssertFalse(manager.applySelectionEdit(.opacity(0.1)))
        XCTAssertEqual(stepsSince(baseline, manager), 3, "and nothing recorded")
    }

    /// **Under Cut only the inside piece takes the size, and one undo puts the whole stroke back.**
    /// The split and the rewrite go through one seam and one step, as a recolour under Cut already does.
    func testUnderCutOnlyTheInsidePieceTakesTheSizeAndUndoRestoresTheWholeStroke() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 20, size: 6))
        let originalID = vector.elements[0].id
        let baseline = manager.history.undoStack.count
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))

        XCTAssertTrue(manager.applySelectionEdit(.size(20)))
        XCTAssertEqual(vector.elements.count, 2, "Cut: the straddling stroke is two strokes")
        let inside = vector.elements.compactMap(\.stroke).first { $0.size == 20 }
        let outside = vector.elements.compactMap(\.stroke).first { $0.size == 6 }
        XCTAssertNotNil(inside, "the inside piece is 20 pt")
        XCTAssertNotNil(outside, "the outside piece keeps 6 pt")
        XCTAssertTrue(inside!.samples.positions.allSatisfy { $0.x >= 29.5 }, "and the 20 pt piece is the one inside the loop")
        XCTAssertEqual(stepsSince(baseline, manager), 1)

        manager.undo()
        XCTAssertEqual(vector.elements.count, 1, "undo: one stroke again")
        XCTAssertEqual(vector.elements[0].id, originalID)
        XCTAssertEqual(sizes(vector), [6])
    }

    // MARK: - Refusals

    /// The band refuses on a pixel cel and on an in-between, and says which control it is about.
    func testTheBandRefusesOnAPixelCelAndSaysWhy() {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertEqual(manager.layers[manager.currentLayerIndex].kind, .raster, "fixture: a pixel layer")
        manager.selection = Selection(path: loop(CGRect(x: 2, y: 2, width: 20, height: 20)),
                                      bounds: CGRect(x: 2, y: 2, width: 20, height: 20),
                                      layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)
        let reason = manager.selectionEditUnavailableReason
        XCTAssertNotNil(reason, "a pixel cel must say why")
        XCTAssertTrue(reason?.contains("vector layers only") == true, "…in the artist's terms: \(reason ?? "")")
        XCTAssertTrue(reason?.contains("Colour") == true && reason?.contains("Size") == true
                      && reason?.contains("Opacity") == true,
                      "…naming the controls it is about, not a feature name nobody can see: \(reason ?? "")")
        XCTAssertFalse(manager.beginSelectionEdit(.size), "and the session refuses")
        XCTAssertEqual(manager.selectionStyle, .unavailable)
    }
}
