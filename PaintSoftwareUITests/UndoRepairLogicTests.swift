import XCTest
import UIKit
import CoreGraphics

/// **Putting an eraser cut back costs the rectangle, not the cel** — `VectorCanvas.restoreElements(_:changedInk:)`.
///
/// The owner, 2026-09-05: *"erasing in a vector layer with a lot of strokes is relatively good, but
/// undo and redo causes some lag."* Both halves of that sentence are TODO (41): the cut declares
/// `Damage.region` and gets `repairableBase(quality:)`'s clipped repair, which is the "relatively
/// good" half — and its **undo** went through `elements = snapshot` + `bumpVersion()`, which declares
/// `.everything`, so pressing undo paid the whole-cel re-walk the cut had just avoided.
///
/// `RegionRepairLogicTests` is the sibling and pins the forward edit. What is different on the way
/// back, and is what this file is about:
///
/// 1. **The rectangle is the caller's, not the canvas's.** A cut derives its own rectangle from the
///    footprints of the strokes it is replacing, which are in the list and measured. A restore is
///    handed a list from the past: what *arrives* has never been drawn, so nothing in the canvas can
///    bound it and the gesture that recorded the step has to say. What *departs* is still in the list
///    and still measured, so that half is derived here exactly as a cut's is — which is why an undone
///    append is bounded with no rectangle from anybody.
/// 2. **The footprints dropped are chosen by id difference**, so the two ways a same-id list can
///    still draw differently are the two things that have to be caught rather than assumed: an
///    element rewritten in place under its own id (which is why `detachedPiece` minting a fresh id is
///    pinned here as a property of the *cut*, not left as a remark), and survivors re-ordered.
/// 3. **An under-declared rectangle is not a wrong picture, it is a second walk.** `renderLocalContent`
///    measures every element it draws that it has no footprint for and widens the clip when one
///    escapes. So the picture assertions below cannot fail for a rectangle that is merely too small —
///    `regionRepairsWidened` is the operand that can, and it is asserted alongside every one of them.
///    Without it these tests would be green against a caller that declared `.null`.
final class UndoRepairLogicTests: XCTestCase {

    // MARK: - The scene
    //
    // `RegionRepairLogicTests`' grid, and deliberately this file's own copy for that file's own
    // stated reason: the fixtures are what make "the bound binds" expressible, a shared one would be
    // tuned for whichever suite complained last, and a fixture nobody owns is how three of that
    // file's own tests came to be blind.

    private static let canvasSize = CGSize(width: 160, height: 120)

    private static func brush() -> Brush {
        Brush(name: "Undo", tip: .round, size: 5, dab: BrushDabSettings(spacing: 0.3),
              stroke: BrushStrokeSettings(blendMode: .normal))
    }

    /// A short mark in cell `index` of an 8x6 grid — short and spread out, so a cut through one
    /// names a rectangle that is a few percent of the canvas and a restore that failed to bound
    /// itself is visible in the dab count.
    private static func mark(_ index: Int) -> VectorStroke {
        let col = index % 8, row = (index / 8) % 6
        let x = 10 + CGFloat(col) * 19, y = 10 + CGFloat(row) * 19
        let samples = StrokeSamples((0..<5).map { step -> VectorSample in
            let t = CGFloat(step) / 4
            return VectorSample(x: x + t * 12, y: y + t * 8, pressure: 0.5 + 0.5 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(),
                            color: CodableColor(red: Double(index % 5) / 5, green: 0.3,
                                                blue: 0.8, alpha: 1),
                            size: 5, opacity: 1, samples: samples, composite: .paint,
                            seed: UInt64(index &+ 1))
    }

    /// A mark long enough that a flick through its middle leaves a piece either side.
    ///
    /// **The grid's own marks are shorter than the eraser nib**, which `RegionRepairLogicTests`
    /// records as the fixture trap that made three of its tests blind — a cut through one *deletes*
    /// it rather than splitting it. Both shapes are needed here and they exercise different arms:
    /// a deletion leaves nothing behind, so the whole rectangle has to come from the caller, and a
    /// split leaves two measured pieces that bound most of it themselves.
    private static func longMark(_ index: Int) -> VectorStroke {
        let row = index % 6
        let y = 12 + CGFloat(row) * 19
        let samples = StrokeSamples((0..<13).map { step -> VectorSample in
            let t = CGFloat(step) / 12
            return VectorSample(x: 8 + t * 144, y: y + sin(t * 3) * 3, pressure: 1)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(),
                            color: CodableColor(red: 0.1, green: 0.6, blue: 0.4, alpha: 1),
                            size: 5, opacity: 1, samples: samples, composite: .paint,
                            seed: UInt64(index &+ 900))
    }

    /// Six long marks, drawn once. A flick over the middle of one splits it.
    private static func drawnStripes() -> VectorCanvas {
        let canvas = VectorCanvas(size: canvasSize, elements: (0..<6).map { .stroke(longMark($0)) })
        _ = canvas.render()
        return canvas
    }

    /// A long near-vertical mark down the canvas, for Mode 3 to have something to cut *to*.
    private static func crossingMark() -> VectorStroke {
        let samples = StrokeSamples((0..<13).map { step -> VectorSample in
            let t = CGFloat(step) / 12
            return VectorSample(x: 40 + t * 20, y: 6 + t * 108, pressure: 1)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(),
                            color: CodableColor(red: 0.7, green: 0.2, blue: 0.2, alpha: 1),
                            size: 5, opacity: 1, samples: samples, composite: .paint, seed: 4242)
    }

    /// Two stripes far apart and one mark crossing both — **Mode 3's fixture, and it has to have a
    /// real crossing in it.** MEASURED: with nothing under the tip to cut to, `cutToIntersection`
    /// falls back to its own footprint and removes the whole run, so on parallel stripes it *deletes*
    /// (6 elements → 5) and mints no piece at all. The two stripes are 57 pt apart so the tip lands
    /// on the crossing mark alone, and the span it cuts leaves a piece either side.
    private static func drawnCrossedStripes() -> VectorCanvas {
        let canvas = VectorCanvas(size: canvasSize,
                                  elements: [.stroke(longMark(1)), .stroke(longMark(4)),
                                             .stroke(crossingMark())])
        _ = canvas.render()
        return canvas
    }

    /// One long stripe, the short mark that shares its row, and a second short mark three rows away
    /// — **the only fixture here in which one gesture both splits a stroke and deletes another far
    /// from it**, which is the shape that makes the caller's rectangle irreducible. See
    /// `testUndoingAGestureThatSplitOneStrokeAndDeletedAnotherFarAwayNeedsBothHalves`.
    private static func drawnStripeAndDistantMark() -> VectorCanvas {
        let canvas = VectorCanvas(size: canvasSize,
                                  elements: [.stroke(longMark(1)), .stroke(mark(12)), .stroke(mark(36))])
        _ = canvas.render()
        return canvas
    }

    private static func cellCentre(_ index: Int) -> CGPoint {
        let col = index % 8, row = (index / 8) % 6
        return CGPoint(x: 10 + CGFloat(col) * 19 + 6, y: 10 + CGFloat(row) * 19 + 4)
    }

    /// A short eraser gesture across one cell — the ordinary cut, not a sweep.
    private static func flick(over index: Int) -> StrokeSamples {
        let centre = cellCentre(index)
        return StrokeSamples((0..<5).map { step -> VectorSample in
            let t = CGFloat(step) / 4
            return VectorSample(x: centre.x - 7 + t * 14, y: centre.y - 5 + t * 10, pressure: 1)
        }, channels: .pressureOnly)
    }

    private static func canvas(_ n: Int) -> VectorCanvas {
        VectorCanvas(size: canvasSize, elements: (0..<n).map { .stroke(mark($0)) })
    }

    /// A canvas that has already drawn itself once — the only state in which any of this is
    /// possible, because the base a repair starts from *is* the standing render and the footprints
    /// it skips on are measured by the walk that made it.
    private static func drawnCanvas(_ n: Int) -> VectorCanvas {
        let canvas = canvas(n)
        _ = canvas.render()
        return canvas
    }

    // MARK: - Comparing two renders
    //
    // `RegionRepairLogicTests`' helpers, and its own comment explains why the comparison is of the
    // two bitmaps' own bytes rather than of two images normalised through a third context.

    private func rawPixels(_ image: UIImage, _ label: String) -> (layout: String, bytes: Data) {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data as Data? else {
            XCTFail("\(label): no backing bytes")
            return ("", Data())
        }
        let layout = "\(cg.width)x\(cg.height) bpr=\(cg.bytesPerRow) bpp=\(cg.bitsPerPixel) "
            + "alpha=\(cg.alphaInfo.rawValue) order=\(cg.bitmapInfo.rawValue)"
        return (layout, data)
    }

    /// The two bitmaps' disagreement: how many bytes differ, by how much at worst, and the box the
    /// differences live in.
    private func diff(_ a: UIImage, _ b: UIImage, _ what: String,
                      file: StaticString = #filePath, line: UInt = #line)
    -> (bytes: Int, worst: Int, box: CGRect, summary: String)? {
        let left = rawPixels(a, "\(what) left"), right = rawPixels(b, "\(what) right")
        guard left.layout == right.layout else {
            XCTFail("\(what): different bitmap layouts — \(left.layout) against \(right.layout)",
                    file: file, line: line)
            return nil
        }
        guard let cg = a.cgImage else { return nil }
        var differing = 0, worst = 0
        var box = CGRect.null
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        left.bytes.withUnsafeBytes { l in
            right.bytes.withUnsafeBytes { r in
                for y in 0..<cg.height {
                    for x in 0..<cg.width {
                        let base = y * bpr + x * bpp
                        var pixelDiffers = false
                        for channel in 0..<bpp {
                            let delta = abs(Int(l[base + channel]) - Int(r[base + channel]))
                            if delta > 0 { differing += 1; pixelDiffers = true }
                            worst = Swift.max(worst, delta)
                        }
                        if pixelDiffers {
                            box = box.union(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                        }
                    }
                }
            }
        }
        return (differing, worst, box,
                "\(differing) bytes differ, worst by \(worst), inside \(box)")
    }

    /// The bound `RegionRepairLogicTests` established and its §11.10 write-up records: a repair whose
    /// rectangle cuts a transparency layer disagrees with the full walk by one or two units out of
    /// 255 along that edge, and nowhere else.
    private func assertMatchesToWithinARoundingUnit(_ repaired: UIImage, _ full: UIImage,
                                                    inside region: CGRect, _ what: String,
                                                    file: StaticString = #filePath,
                                                    line: UInt = #line) {
        guard let d = diff(repaired, full, what, file: file, line: line), d.bytes > 0 else { return }
        XCTAssertLessThanOrEqual(d.worst, 2,
                                 "\(what): \(d.summary) — more than a rounding unit is a wrong picture",
                                 file: file, line: line)
        XCTAssertTrue(region.insetBy(dx: -1, dy: -1).contains(d.box),
                      "\(what): \(d.summary) — a difference outside the repaired rectangle \(region) "
                      + "is a base the caller under-declared, not a seam", file: file, line: line)
    }

    /// The full re-walk of `canvas`'s display list, guaranteed cold: a freshly constructed canvas has
    /// no memo, no base and no measured footprints, so it cannot take any fast path.
    private func fullReWalk(of canvas: VectorCanvas) -> (image: UIImage, dabs: Int) {
        let cold = VectorCanvas(size: canvas.size, elements: canvas.elements)
        let image = cold.render()
        XCTAssertEqual(cold.rasterizations, 1, "the reference arm must have rasterized exactly once")
        XCTAssertEqual(cold.regionRepairs, 0, "the reference arm must not have repaired anything")
        return (image, cold.lastRenderDabCount)
    }

    private func isRegion(_ damage: VectorCanvas.Damage) -> Bool {
        if case .region = damage { return true }
        return false
    }

    /// Enough of a stroke to notice it being rewritten under its own id: what it is made of and
    /// where it starts and stops. `VectorStroke` is not `Equatable` and making it so would drag
    /// `Brush`, `StrokeSamples` and a `UIImage` payload in behind it, which is a wide change to buy
    /// one comparison.
    private func fingerprint(_ stroke: VectorStroke) -> String {
        let first = stroke.samples.first?.point ?? .zero
        let last = stroke.samples.last?.point ?? .zero
        return "\(stroke.samples.count)|\(stroke.size)|\(stroke.opacity)|\(stroke.composite)"
            + "|\(first.x),\(first.y)|\(last.x),\(last.y)|\(stroke.color.red),\(stroke.color.alpha)"
    }

    private func fingerprints(_ elements: [VectorElement]) -> [UUID: String] {
        var out: [UUID: String] = [:]
        for case .stroke(let stroke) in elements { out[stroke.id] = fingerprint(stroke) }
        return out
    }

    /// The box the sample *points* of `elements` live in — not a footprint, which only the canvas
    /// measures, but enough for a fixture to assert that two strokes are nowhere near each other.
    /// Deliberately smaller than what they paint, so a fixture guard built on it is conservative in
    /// the direction that matters: if these boxes are far apart the painted ones may still be, and
    /// the guard below adds the brush width back before concluding anything.
    private func sampleBox(_ elements: [VectorElement]) -> CGRect {
        var box = CGRect.null
        for case .stroke(let stroke) in elements {
            for sample in stroke.samples {
                box = box.union(CGRect(x: sample.x, y: sample.y, width: 0, height: 0))
            }
        }
        return box
    }

    private func strokeIDs(_ elements: [VectorElement]) -> Set<UUID> {
        var out: Set<UUID> = []
        for case .stroke(let stroke) in elements { out.insert(stroke.id) }
        return out
    }

    // MARK: - (1) What a restore declares

    /// **The headline: undoing a cut declares a rectangle, and redoing it declares one too.**
    ///
    /// One rectangle serves both directions, because it bounds every pixel where the two lists differ
    /// and that is a symmetric statement. Mutation that reddens it: put `elements = snapshot` +
    /// `bumpVersion()` back in either closure.
    func testUndoingAndRedoingACutBothDeclareARectangle() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself, or there is nothing to carry back")
        }
        let after = canvas.elements
        XCTAssertNotEqual(before.count, after.count, "the cut must have changed the list")
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: cutRegion)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the undo carries the cut's own rectangle and must not fall back to .everything")
        _ = canvas.render()

        canvas.restoreElements(after, changedInk: cutRegion)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the redo is the same swap read the other way and must bound itself too")
    }

    /// **What departs is measured here, so an undone append needs no rectangle from anybody.**
    ///
    /// This is the case a caller genuinely cannot bound: a brush stroke's gesture declares
    /// `.appended`, never a region, so `StrokeCanvasView` hands `nil` — and the restore is still
    /// cheap, because the stroke going away is in the list with its footprint measured.
    /// Mutation that reddens it: return `.everything` whenever `changedInk` is nil.
    func testUndoingAnAppendIsBoundedWithNoRectangleFromItsCaller() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        canvas.addStroke(Self.mark(50))
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: nil)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "nothing arrives, so the vacated ink is the whole of the difference and it is measured")
    }

    /// **And redoing that append cannot be bounded by anybody, so it says so.**
    ///
    /// The ink coming back has never been drawn on this canvas: no footprint exists for it and the
    /// gesture declared no rectangle. Guessing a box from the stroke's geometry is what BRUSH.md §12
    /// stage 8 refuted — `ResponseCurve` does not clamp, so no size-derived number bounds what a dab
    /// paints. Mutation that reddens it: treat a nil `changedInk` as `.null`.
    func testRedoingAnAppendCannotBeBoundedAndSaysEverything() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        canvas.addStroke(Self.mark(50))
        let after = canvas.elements
        _ = canvas.render()
        canvas.restoreElements(before, changedInk: nil)
        _ = canvas.render()

        canvas.restoreElements(after, changedInk: nil)
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "an arrival nobody can bound is the case that must pay, not the case that guesses")
    }

    /// **A departing fill cannot be bounded, because the walk deliberately never measured it.**
    ///
    /// `renderLocalContent` measures footprints for strokes only — fills, images, text and video are
    /// always drawn, on the stated grounds that they are a handful per cel and a bound for them would
    /// be a second thing that can be wrong. So a restore that drops one has no rectangle for it.
    /// Mutation that reddens it: skip the non-stroke guard in `restoreDamage`.
    func testARestoreThatDropsAFillSaysEverything() {
        let canvas = Self.drawnCanvas(12)
        canvas.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 20, y: 20, width: 40, height: 30),
                                                      transform: nil),
                                         color: CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1),
                                         opacity: 1))
        _ = canvas.render()
        let withFill = canvas.elements
        let withoutFill = withFill.filter { if case .fill = $0 { return false } else { return true } }
        XCTAssertEqual(withoutFill.count, withFill.count - 1, "the fixture must actually hold a fill")

        canvas.restoreElements(withoutFill, changedInk: CGRect(x: 20, y: 20, width: 40, height: 30))
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "an unmeasured departure is exactly the case Damage's own rule says to pay for")
    }

    // MARK: - (2) The two ways a same-id list still draws differently

    /// **Re-ordering the survivors draws a different picture and neither an arrival nor a departure
    /// says so** — z-position is what a display list means.
    ///
    /// The fixture drops one mark *and* swaps two others, so the id-difference analysis finds a real
    /// departure and would happily declare that stroke's rectangle — which says nothing whatever
    /// about the two that changed places. Mutation that reddens it: delete the survivor-order check.
    func testRestoringAReorderedListSaysEverything() {
        let canvas = Self.drawnCanvas(12)
        _ = canvas.render()
        var reordered = canvas.elements
        reordered.remove(at: 11)
        reordered.swapAt(0, 1)

        canvas.restoreElements(reordered, changedInk: CGRect(x: 0, y: 0, width: 30, height: 30))
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "two lists holding the same ids in a different order differ everywhere those "
                       + "ids are, not inside the rectangle a departure names")
    }

    /// **The contract `restoreElements` names, pinned as a property of the cut rather than left as a
    /// remark**: a cut adds and removes, it never rewrites an element in place under its own id.
    ///
    /// That is what makes choosing footprints by id difference sound. Mutation that reddens it: drop
    /// `piece.id = UUID()` from `detachedPiece` so a piece inherits its parent's id.
    ///
    /// **The fixture has to be one that *splits*, and this test did not have one until 2026-09-05.**
    /// MEASURED: on the grid — whose marks are shorter than the nib — a cut *deletes*, so the parent's
    /// id leaves the list altogether and the "survivors" are the marks nobody touched, whose
    /// fingerprints are equal under any implementation whatever. `piece.id = UUID()` could be
    /// commented out and this test stayed green; only `testARoundTripDoesNotGrowTheMeasuredFootprints`
    /// caught it, which is not the test that claims to. The stripes split, and a split parent's id is
    /// exactly the one a rewrite-in-place would keep.
    func testACutMintsFreshIdsRatherThanRewritingInPlace() {
        for mode in [VectorEraserMode.cutPoints, .erase] {
            let canvas = Self.drawnStripes()
            let originalCount = canvas.elements.count
            let before = fingerprints(canvas.elements)
            XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 12), brush: Self.brush(),
                                       size: 8, opacity: 1, mode: mode),
                          "\(mode): the fixture must actually change the list")
            XCTAssertGreaterThan(canvas.elements.count, originalCount,
                                 "\(mode): the fixture must *add* elements — a cut that only deletes "
                                 + "leaves no piece that could have inherited an id, and this test "
                                 + "then pins nothing")
            let after = fingerprints(canvas.elements)
            let survivors = Set(before.keys).intersection(after.keys)
            XCTAssertFalse(survivors.isEmpty, "\(mode): a cut that replaced everything pins nothing")
            for id in survivors {
                XCTAssertEqual(before[id], after[id],
                               "\(mode): id \(id) carries different content after the cut — a restore "
                               + "keeps its measured footprint and would skip it")
            }
        }

        // Mode 3 needs a crossing under the tip — see `drawnCrossedStripes` for what it does without
        // one, which is delete the whole run and mint nothing.
        let toCross = Self.drawnCrossedStripes()
        let originalCount = toCross.elements.count
        let before = fingerprints(toCross.elements)
        XCTAssertEqual(toCross.cutToIntersection(atCanvasPoint: CGPoint(x: 50, y: 60),
                                                 brush: Self.brush(), size: 14).outcome, .cut,
                       "Mode 3 must actually cut, or its half of this pins nothing")
        XCTAssertGreaterThan(toCross.elements.count, originalCount,
                             "To Cross: the fixture must split rather than delete")
        let after = fingerprints(toCross.elements)
        for id in Set(before.keys).intersection(after.keys) {
            XCTAssertEqual(before[id], after[id],
                           "To Cross: id \(id) carries different content after the cut")
        }
    }

    // MARK: - (3) The picture, and the bound that binds

    /// **The repaired undo draws what a full re-walk draws.**
    ///
    /// `regionRepairsWidened` is the operand that makes this test able to fail. The escape check
    /// means an under-declared rectangle costs a second walk rather than a wrong picture, so the byte
    /// comparison alone would be green against a caller that declared `.null` — it would simply have
    /// paid twice. Mutation that reddens it: pass `.null` as `changedInk` from the undo closure.
    func testTheUndoneCutDrawsWhatAFullReWalkDraws() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself")
        }
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: cutRegion)
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 2,
                       "both the cut and its undo must have repaired, or this pins one of them")
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0,
                       "an abandoned repair costs both walks and hides a bad bound behind a good picture")
        XCTAssertEqual(canvas.regionRepairsWidened, 0,
                       "a widened repair is the caller's rectangle being too small — the picture would "
                       + "still be right and the press would still be slow, which is the whole bug")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a Mode 2 cut, undone")
    }

    /// **And the redo draws what a full re-walk draws**, on the same rectangle read the other way.
    func testTheRedoneCutDrawsWhatAFullReWalkDraws() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself")
        }
        let after = canvas.elements
        _ = canvas.render()
        canvas.restoreElements(before, changedInk: cutRegion)
        _ = canvas.render()

        canvas.restoreElements(after, changedInk: cutRegion)
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairsWidened, 0,
                       "the redo's arrivals are the cut pieces, which cannot reach past what their "
                       + "parents painted — a widening here means the rectangle is not symmetric")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a Mode 2 cut, redone")
    }

    /// **A cut that splits rather than deletes** — the arm where `departing` is non-empty *and*
    /// something arrives, which is the only way to reach `.region(vacated.union(arrivingInk))`.
    ///
    /// The grid's marks are shorter than the nib, so every other test here cuts by *deleting*: the
    /// arm where nothing departs and the caller's rectangle is the whole answer. This one reaches the
    /// union line and pins the picture across it.
    ///
    /// **It does not, on its own, pin the union**, and saying so is the point of the test below.
    /// MEASURED by mutation: `return .region(vacated)` leaves this test green, because a stroke split
    /// through its middle leaves a piece either side and the union of the two pieces' boxes is the
    /// parent's box — the gap between them is inside it by construction, so the vacated half already
    /// covers everything the parent paints and the caller's rectangle adds nothing *here*.
    func testUndoingACutThatSplitAStrokeIsBoundedByBothHalvesOfTheRectangle() {
        let canvas = Self.drawnStripes()
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 12), brush: Self.brush(),
                                   size: 8, opacity: 1, mode: .cutPoints))
        XCTAssertGreaterThan(canvas.elements.count, before.count,
                             "the fixture must split a stroke into pieces, not delete it — a deletion "
                             + "shortens the list and exercises the other arm entirely")
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself")
        }
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: cutRegion)
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairsWidened, 0,
                       "the pieces departing bound their own ink and the caller's rectangle bounds "
                       + "the parent's — a widening means one of the two halves is missing")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a split stroke, put back")
    }

    /// **The union is not redundant, and this is the gesture that proves it** — one eraser drag that
    /// *splits* one stroke and *deletes* another somewhere else.
    ///
    /// A split alone cannot pin `vacated.union(arrivingInk)`, and the test above records the
    /// experiment: two pieces either side of a cut have their parent's box between them, so
    /// `vacated` already covers the parent and the caller's rectangle is genuinely redundant on that
    /// input. **The mistake in that reasoning is that `departing` is not per-stroke.** A gesture
    /// crosses several strokes — PERFORMANCE.md §11.10's cross-eraser drag is nothing else — and one
    /// list swap puts all of them back at once. A stroke *deleted* outright leaves no piece, so
    /// nothing in the standing list remembers where it was; a stroke *split* elsewhere leaves pieces,
    /// so `departing` is non-empty and the union line is the one taken. The vacated half then bounds
    /// the split and says nothing whatever about the deletion, and only the caller's rectangle covers
    /// it.
    ///
    /// So the answer to "is the union reachable" is not about one stroke's shape at all — it is that
    /// **the two halves of the difference are unions over different sets**, and a gesture only has to
    /// touch two strokes for them to come apart.
    ///
    /// Mutation that reddens it: `return .region(vacated)`. MEASURED: with it, the deleted mark
    /// arrives outside the clip, `renderLocalContent`'s escape check catches it and widens, so
    /// `regionRepairsWidened` is 1 rather than 0 — the picture stays right and the press pays two
    /// walks, which is exactly the bug this whole item is about.
    func testUndoingAGestureThatSplitOneStrokeAndDeletedAnotherFarAwayNeedsBothHalves() {
        let canvas = Self.drawnStripeAndDistantMark()
        let before = canvas.elements
        let originalIDs = strokeIDs(before)

        // Cut one, through the stripe's middle: splits it, and deletes the short mark on that row.
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 12), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        guard case .region(let firstCut) = canvas.lastDamage else {
            return XCTFail("the fixture's first cut must bound itself")
        }
        let pieces = canvas.elements.filter {
            if case .stroke(let stroke) = $0 { return !originalIDs.contains(stroke.id) }
            return false
        }
        XCTAssertEqual(pieces.count, 2, "the first cut must split the stripe into two pieces, or the "
                       + "restore below takes the nothing-departs arm and pins the other line")

        // Cut two, three rows down, over a mark shorter than the nib: deletes it outright. It leaves
        // no piece, so after this gesture nothing in the standing list is anywhere near where it was.
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 36), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        guard case .region(let secondCut) = canvas.lastDamage else {
            return XCTFail("the fixture's second cut must bound itself")
        }
        XCTAssertEqual(canvas.elements.filter {
            if case .stroke(let stroke) = $0 { return !originalIDs.contains(stroke.id) }
            return false
        }.count, 2, "the second cut must delete rather than split, or its ink is in `vacated` too "
            + "and the union is redundant again")

        // The fixture property the whole test turns on, asserted rather than assumed: what the second
        // cut removed is not inside what the first cut left behind, even after the brush width and
        // `regionDamage(replacing:)`'s margin are added back to the pieces.
        let deleted = before.filter {
            if case .stroke(let stroke) = $0 { return !strokeIDs(canvas.elements).contains(stroke.id) }
            return false
        }
        let deletedFar = deleted.filter { element in
            guard case .stroke(let stroke) = element else { return false }
            return !sampleBox(pieces).insetBy(dx: -10, dy: -10).intersects(sampleBox([.stroke(stroke)]))
        }
        XCTAssertFalse(deletedFar.isEmpty,
                       "every stroke this gesture removed sits inside the surviving pieces' box "
                       + "\(sampleBox(pieces)) — the fixture does not separate the two halves")

        // One gesture, one undo step, and `StrokeCanvasView.foldGestureDamage` is what makes its
        // rectangle the union of what the two cuts each declared.
        let gestureDamage = firstCut.union(secondCut)
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: gestureDamage)
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairsWidened, 0,
                       "the deleted mark arrives where nothing departed, so only the caller's "
                       + "rectangle can bound it — a widening here is the union having been dropped")
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0,
                       "an abandoned repair costs both walks and hides a bad bound behind a good picture")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a gesture that split one stroke and deleted another")
    }

    /// **A round trip must not grow the measured footprints**, which is what the forget in
    /// `restoreElements` is for and is the one thing no picture assertion can see.
    ///
    /// An id that has left the display list is never consulted by the walk again, so keeping its
    /// rectangle draws nothing wrong — it accumulates, one entry per stroke ever erased, for as long
    /// as the artist keeps working. MEASURED by mutation: dropping the forget left every other test
    /// in this file green. Mutation that reddens this one: the same.
    func testARoundTripDoesNotGrowTheMeasuredFootprints() {
        let canvas = Self.drawnStripes()
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 12), brush: Self.brush(),
                                   size: 8, opacity: 1, mode: .cutPoints))
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself")
        }
        let after = canvas.elements
        _ = canvas.render()

        for _ in 0..<4 {
            canvas.restoreElements(before, changedInk: cutRegion)
            _ = canvas.render()
            canvas.restoreElements(after, changedInk: cutRegion)
            _ = canvas.render()
        }
        XCTAssertEqual(canvas.measuredFootprintCount, canvas.elements.count,
                       "four undo/redo round trips left \(canvas.measuredFootprintCount) footprints "
                       + "for \(canvas.elements.count) elements — the ones that left are still held")
    }

    /// **The payoff, counted in dabs rather than in milliseconds** — the claim is about the algorithm
    /// and the milliseconds are the machine's.
    ///
    /// Mutation that reddens it: `bumpVersion()` in the undo closure, which makes the two counts
    /// equal.
    func testUndoingACutStampsFarFewerDabsThanTheCelHolds() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself")
        }
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: cutRegion)
        _ = canvas.render()
        let repairDabs = canvas.lastRenderDabCount
        let fullDabs = fullReWalk(of: canvas).dabs
        XCTAssertGreaterThan(fullDabs, 0, "the reference walk must have stamped something")
        XCTAssertLessThan(repairDabs * 4, fullDabs,
                          "undoing a cut through one cell of a 48-mark grid re-stamped \(repairDabs) "
                          + "dabs against the cel's \(fullDabs) — the bound is not binding")
    }

    /// **A restore whose rectangle covers the canvas costs the full walk, and that is the honest half
    /// of the guarantee**: cost scales with the area touched.
    ///
    /// `repairClip` refuses a rectangle that is not smaller than the canvas outright, because taking
    /// the slow path through a clip and a skip test that rejects nothing is dearer than taking it
    /// directly. Mutation that reddens the second half: drop that area test.
    ///
    /// **The first half is the one this test was written wrong about, so it is pinned too.** An
    /// undone append was expected to pay for a canvas-sized rectangle and does not, because nothing
    /// arrives: `changedInk` bounds arriving ink and there is none, so it is ignored and the departing
    /// stroke's own measured footprint is the whole of the damage. A caller passing a pessimistic
    /// rectangle therefore cannot make a restore *slower* than what leaves it — which is worth having
    /// in a test rather than in a comment. Mutation that reddens it: union `changedInk` in
    /// unconditionally instead of only when something arrives.
    func testACanvasSizedRectangleIsIgnoredWhenNothingArrivesAndPaidForWhenSomethingDoes() {
        let undone = Self.drawnCanvas(24)
        let before = undone.elements
        undone.addStroke(Self.mark(50))
        _ = undone.render()
        undone.restoreElements(before, changedInk: CGRect(origin: .zero, size: Self.canvasSize))
        _ = undone.render()
        XCTAssertEqual(undone.regionRepairs, 1,
                       "nothing arrives, so a caller's rectangle says nothing and the vacated stroke "
                       + "is the whole of the damage")

        let redone = Self.drawnCanvas(48)
        let intact = redone.elements
        XCTAssertTrue(redone.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        _ = redone.render()
        let repairsAfterTheCut = redone.regionRepairs
        redone.restoreElements(intact, changedInk: CGRect(origin: .zero, size: Self.canvasSize))
        _ = redone.render()
        XCTAssertEqual(redone.regionRepairs, repairsAfterTheCut,
                       "the parents arriving are bounded only by what the caller said, and a "
                       + "canvas-sized rectangle is a full walk with extra bookkeeping")
    }
}
