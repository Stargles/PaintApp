import XCTest
import UIKit
import SwiftUI
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
/// 3. **For a stroke, an under-declared rectangle is not a wrong picture, it is a second walk.**
///    `renderLocalContent` measures every element it draws that it has no footprint for and widens the
///    clip when one escapes. So the picture assertions in sections (1) and (2) cannot fail for a
///    rectangle that is merely too small — `regionRepairsWidened` is the operand that can, and it is
///    asserted alongside every one of them. Without it those tests would be green against a caller
///    that declared `.null`.
/// 4. **For the other four kinds it *is* a wrong picture, and section (1b) is where that matters.**
///    The walk takes no measurement of a fill, an image, a text object or a video, so nothing widens
///    a clip on their account; and a **departure**'s damage is stale pixels *outside* the clip, where
///    by construction nothing draws and so no escape could be detected even for a stroke. The bound
///    for those is therefore a containment proof rather than a retry, and section (1b)'s picture
///    assertions are load-bearing rather than belt-and-braces.
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

    /// **And redoing that append is bounded by what it painted before it left.**
    ///
    /// This test said the opposite until the general pass, and the sentence it was written to defend
    /// was true of the canvas and false of the *history*: the ink coming back has never been drawn
    /// *in this list*, but it was drawn immediately before, by the walk that measured it, and
    /// `restoreElements` keeps that measurement in `vacatedInk` when the id leaves. Guessing a box
    /// from the stroke's geometry is still what BRUSH.md §12 stage 8 refuted and is still not what
    /// happens here — this is the measurement, not a derivation from the brush.
    ///
    /// Mutation that reddens it: return nil from `inkOfArrivals(in:standing:)`, or stop calling
    /// `rememberVacatedInk`.
    func testRedoingAnAppendIsBoundedByWhatItPaintedBeforeItLeft() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        canvas.addStroke(Self.mark(50))
        let after = canvas.elements
        _ = canvas.render()
        canvas.restoreElements(before, changedInk: nil)
        _ = canvas.render()

        canvas.restoreElements(after, changedInk: nil)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the stroke coming back is the one that just left, and what it painted was "
                      + "measured on the way out — declaring .everything here is the whole-cel walk "
                      + "the owner reported")
    }

    /// **A fill's rectangle never goes through the hint table**, whichever way the press goes.
    ///
    /// `vacatedInk` is a *hint*: it says where an id last painted, and it is safe only because the
    /// walk re-measures a returning stroke and widens the clip if it escaped. Nothing measures a fill,
    /// an image, a text object or a video, so nothing could correct a hint about one — which is why
    /// those four are bounded by `derivedFootprint(of:)`, off geometry the element carries with it,
    /// and why `inkOfArrivals(in:standing:)` reads `vacatedInk` in its stroke arm and nowhere else.
    ///
    /// **Two operands, and the second is the one that makes it a test rather than a restatement.**
    /// `rememberedInkCount` is 0 across the whole round trip — nothing about the fill ever enters the
    /// table — *and* both presses are still bounded, so the rectangle demonstrably came from
    /// somewhere else. Either half alone is green under an implementation that is wrong in the other
    /// direction. Mutation that reddens it: measure fills into `paintedBounds` in
    /// `renderLocalContent`, which is the change that would put one in the table.
    ///
    /// This replaces `testRedoingAFillIsNotBoundedByAHintBecauseAFillIsNeverMeasured`, whose
    /// assertion was that the redo said `.everything`. TODO (41) is the reason it no longer does; the
    /// invariant that test was really protecting is the one above, and it is unchanged.
    func testAFillIsNeverPutInTheHintTableAndIsBoundedAnyway() {
        let canvas = Self.drawnCanvas(12)
        let withoutFill = canvas.elements
        canvas.addFill(Self.fillElement(CGRect(x: 20, y: 20, width: 40, height: 30)))
        let withFill = canvas.elements
        _ = canvas.render()
        XCTAssertEqual(canvas.rememberedInkCount, 0, "control: nothing has left the list yet")

        canvas.restoreElements(withoutFill, changedInk: nil)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the undo of a fill must be bounded by the fill's own path, which is exact")
        XCTAssertEqual(canvas.rememberedInkCount, 0,
                       "a departing fill must leave no hint behind: the walk never measured it, so a "
                       + "rectangle under its id would be one nothing could correct")
        _ = canvas.render()

        canvas.restoreElements(withFill, changedInk: nil)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the fill coming back is bounded by the same path it departed with, and no "
                      + "caller rectangle was passed either way")
        XCTAssertEqual(canvas.rememberedInkCount, 0,
                       "and it must not be put in the table on the way back in either")
    }

    /// **A run of undos followed by a run of redos: every redo is bounded, not just the first.**
    ///
    /// This is the owner's own sentence — *"undoing and redoing while there are a lot of strokes"* —
    /// and it is a run of presses rather than one round trip. A `vacatedInk` that held only the last
    /// restore's departures would make redo #1 cheap and leave #2, #3 and #4 at `.everything`, which
    /// is three quarters of the case still broken. Mutation that reddens it: `removeAll` before the
    /// insert in `rememberVacatedInk` instead of pruning the arrivals.
    func testARunOfRedosIsBoundedAllTheWayBackNotJustTheFirstPress() {
        let canvas = Self.drawnCanvas(24)
        var lists: [[VectorElement]] = [canvas.elements]
        for step in 0..<4 {
            canvas.addStroke(Self.mark(30 + step))
            _ = canvas.render()
            lists.append(canvas.elements)
        }

        for step in stride(from: 3, through: 0, by: -1) {
            canvas.restoreElements(lists[step], changedInk: nil)
            XCTAssertTrue(isRegion(canvas.lastDamage), "undo #\(4 - step) must be bounded")
            _ = canvas.render()
        }
        for step in 1...4 {
            canvas.restoreElements(lists[step], changedInk: nil)
            XCTAssertTrue(isRegion(canvas.lastDamage),
                          "redo #\(step) fell back to .everything — the run is the case, not the pair")
            _ = canvas.render()
        }
    }

    /// **The redone append draws what a full re-walk draws** — the assertion the hint's safety is
    /// really made of, since everything above is about what the canvas *says*.
    ///
    /// `regionRepairsWidened` and `regionRepairsAbandoned` are asserted beside the picture for
    /// `RegionRepairLogicTests`' reason: the escape check keeps the picture right whatever rectangle
    /// is declared, so a picture assertion alone would be green against a hint that was nonsense and
    /// merely expensive. Widened at 0 is also the operand that says the remembered rectangle needs no
    /// margin — a redone stroke does not re-anchor its dab walk the way a cut piece does.
    ///
    /// **The region asserted against is the union of both presses' rectangles, and finding out why is
    /// what this test was worth.** Every sibling of this test repairs *once*, from a base that a full
    /// walk produced, so a rounding difference can only live along the one clip that cut a
    /// transparency layer. A redo repairs from the base the *undo's* repair produced, so it inherits
    /// that press's seam wherever it is not redrawing — pixels the undo's clip cut and this one does
    /// not reach. MEASURED here: 15 bytes, worst by 1 out of 255, in a 3x5 box two points outside the
    /// redo's clip and inside the undo's. So **repairs compose and their seams do too**, which is a
    /// property of chaining them rather than of this rectangle, and the honest bound on a chain is
    /// the union of its clips. It cannot grow past a rounding unit: each press redraws its own clip
    /// from the bottom of the stack.
    func testTheRedoneAppendDrawsWhatAFullReWalkDraws() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        canvas.addStroke(Self.mark(50))
        let after = canvas.elements
        _ = canvas.render()

        canvas.restoreElements(before, changedInk: nil)
        let undone = canvas.render()
        let undoRegion = canvas.lastRepairedRegion
        // The control, and the operand that says the seam below is the undo's rather than the redo's:
        // this press repairs from a full walk's base, so its own picture is right inside its own clip.
        assertMatchesToWithinARoundingUnit(undone, fullReWalk(of: canvas).image,
                                           inside: undoRegion, "the undone append")

        let widenedBefore = canvas.regionRepairsWidened
        let abandonedBefore = canvas.regionRepairsAbandoned
        canvas.restoreElements(after, changedInk: nil)
        let repaired = canvas.render()

        XCTAssertEqual(canvas.regionRepairsWidened, widenedBefore,
                       "the remembered rectangle is a measurement of the same stroke value and must "
                       + "not need widening")
        XCTAssertEqual(canvas.regionRepairsAbandoned, abandonedBefore,
                       "an abandoned repair costs both walks and hides a bad bound behind a good picture")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: undoRegion.union(canvas.lastRepairedRegion),
                                           "a redone append")
    }

    /// **A fill says where it landed, which is the only rectangle its undo step can carry.**
    ///
    /// A stroke's extent is a dab walk and has to be measured; a fill's is the path being filled, and
    /// `draw(fill:into:)` adds that very path and fills it — so `addFill(canvasSpacePath:…)` returns
    /// an exact bound, widened by the one point of antialiased fringe. `CanvasManager`'s two fill
    /// commits pass it straight to `registerVectorElementsUndo`, which is what makes redoing a fill on
    /// a dense cel cost the fill rather than the cel.
    ///
    /// The picture assertion is the half that matters: a rectangle that missed part of the fill would
    /// clip it, and unlike a stroke there is no escape check to catch that. Mutation that reddens it:
    /// return `.null` from `addFill`, or drop the `insetBy`.
    ///
    /// **The fixture is an ellipse on fractional coordinates, and the sweep is what made it one.**
    /// Written against an axis-aligned rectangle on integers, dropping the `insetBy` changed nothing
    /// and the mutation came back green — and chasing that down refuted the reason the inset had been
    /// given. It is not an antialiasing margin: a fill's antialiasing is per-pixel coverage of the
    /// path, so it never reaches a pixel the path does not, and `repairClip` rounds out to integral
    /// besides. What the inset actually covers is that this box is measured from the **stored** path,
    /// whose coordinates are float32 — MEASURED, 20.3 comes back as 20.299999237, so without the
    /// slack the rectangle does not contain the one the caller asked to fill.
    func testAddingAFillReportsWhereItLandedSoItsRedoCanBeBounded() {
        let canvas = Self.drawnCanvas(48)
        let withoutFill = canvas.elements
        let rect = CGRect(x: 20.3, y: 20.7, width: 40.4, height: 30.2)
        let landed = canvas.addFill(canvasSpacePath: CGPath(ellipseIn: rect, transform: nil),
                                    color: CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        XCTAssertTrue(landed.contains(rect),
                      "\(landed) does not contain the path it was told to fill")
        XCTAssertLessThan(landed.width * landed.height, rect.width * rect.height * 1.5,
                          "\(landed) is a great deal larger than the \(rect) it bounds — a rectangle "
                          + "that loose buys nothing")
        let withFill = canvas.elements
        _ = canvas.render()

        canvas.restoreElements(withoutFill, changedInk: landed)
        _ = canvas.render()
        let repairsBefore = canvas.regionRepairs
        canvas.restoreElements(withFill, changedInk: landed)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the fill coming back is bounded by where it landed, and nothing else could "
                      + "bound it")
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1,
                       "the redo must actually repair rather than declare a rectangle and walk anyway")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "a redone fill")
    }

    /// **The payoff on the redo side, counted in dabs.** The sibling of
    /// `testUndoingACutStampsFarFewerDabsThanTheCelHolds`, on the press that was still paying the
    /// whole cel after that one stopped.
    ///
    /// Mutation that reddens it: return nil from `inkOfArrivals(in:standing:)`, which makes the two counts equal.
    func testRedoingAnAppendStampsFarFewerDabsThanTheCelHolds() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        canvas.addStroke(Self.mark(50))
        let after = canvas.elements
        _ = canvas.render()
        canvas.restoreElements(before, changedInk: nil)
        _ = canvas.render()

        canvas.restoreElements(after, changedInk: nil)
        _ = canvas.render()
        let repairDabs = canvas.lastRenderDabCount
        let fullDabs = fullReWalk(of: canvas).dabs
        XCTAssertGreaterThan(fullDabs, 0, "the reference walk must have stamped something")
        XCTAssertLessThan(repairDabs * 4, fullDabs,
                          "redoing one mark on a 49-mark grid re-stamped \(repairDabs) dabs against "
                          + "the cel's \(fullDabs) — the bound is not binding")
    }

    // MARK: - (1b) The four kinds the walk never measures — TODO (41)
    //
    // `renderLocalContent` measures footprints for strokes only: a fill, a placed image, a text
    // object and a video are always drawn and never measured, on the stated grounds that they are a
    // handful per cel and a bound for them would be a second thing that can be wrong. That left a
    // **departing** one of the four forcing `.everything` whatever rectangle the caller passed, so
    // the undo of a fill and the undo of a text commit paid the whole cel while their redos did not.
    //
    // **The correctness bar here is higher than anywhere else in this file, and paragraph 3 of the
    // header is why.** An under-declared rectangle for a *stroke* is a second walk, because the walk
    // measures what it draws and widens the clip when something escapes. Neither half of that reaches
    // these four: the walk takes no measurement of them, and a departure's damage is stale pixels
    // *outside* the clip, where by construction nothing draws and so nothing can notice. So every
    // test below asserts the **picture** against a cold full re-walk, and asserts `regionRepairs`
    // moved as well — without that second operand the picture assertion is green under `.everything`,
    // which draws the right picture by walking the whole cel.

    /// A fill the whole of whose ink is inside its own path, which is every fill.
    private static func fillElement(_ rect: CGRect, evenOdd: Bool = false) -> VectorFillElement {
        VectorFillElement(path: CGPath(ellipseIn: rect, transform: nil),
                          color: CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1),
                          opacity: 1, evenOddFill: evenOdd)
    }

    private static func solidImage(_ color: UIColor, side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private static func imageElement(at position: CGPoint, side: CGFloat = 24,
                                     scale: CGFloat = 1, rotation: CGFloat = 0) -> VectorImageElement {
        VectorImageElement(image: solidImage(.systemTeal, side: side),
                           transform: LayerTransform(position: position, scale: scale,
                                                     rotation: rotation))
    }

    /// **The placeholder branch by default**, because it is the harder one to bound: `draw(video:)`
    /// strokes a border whose width is floored at 0.5 *local* units, so above a placement scale of 4
    /// its outer edge stands proud of the natural rectangle. A decoded frame stands none — pass one
    /// to exercise that arm.
    private static func videoElement(at position: CGPoint, natural: CGSize = CGSize(width: 32, height: 18),
                                     scale: CGFloat = 1, rotation: CGFloat = 0,
                                     frame: UIImage? = nil) -> VectorVideoElement {
        var element = VectorVideoElement(assetURL: URL(fileURLWithPath: "/dev/null"),
                                         assetFileName: "null", naturalSize: natural,
                                         sourceStart: .zero,
                                         sourceEnd: SourceTime(value: 1, timescale: 1), speed: 1,
                                         transform: LayerTransform(position: position, scale: scale,
                                                                   rotation: rotation))
        element.displayFrame = frame
        return element
    }

    private static func textElement(_ string: String = "Words", at origin: CGPoint,
                                    size: CGSize = CGSize(width: 70, height: 30),
                                    autoSize: Bool) -> VectorTextElement {
        VectorTextElement(recipe: TextRecipe(string: string, font: .system,
                                             typography: Typography(pointSize: 20)),
                          frame: TextFrame(origin: origin, size: size, autoSize: autoSize))
    }

    /// **Drops `element` off a drawn canvas and puts it back, asserting both presses bounded
    /// themselves and both drew what a cold full re-walk draws.**
    ///
    /// The undo is the case TODO (41) names — the element departs, and no caller rectangle exists for
    /// it — and the redo is its mirror, with `changedInk` nil so the arriving half has to come from
    /// the same geometry. Every assertion names the element and what it is about, because the line
    /// number here says only "the shared helper".
    ///
    /// **`bumpVersion()` after the assignment, and the `diff` guard after that, are both there
    /// because this fixture measured nothing the first time it was written.** The `elements` setter
    /// deliberately does not invalidate — its callers follow with `bumpVersion()` — so without it the
    /// canvas hands back its standing memo, the new element is never drawn, its footprint is never
    /// measured, and every assertion below passes against a picture the element is not in. Four of
    /// these tests were green that way. The guard is the operand that says the fixture is real: with
    /// the element in the list the canvas draws *something different*.
    private func assertARoundTripIsBoundedAndDrawsRight(
        _ element: VectorElement, _ what: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let canvas = Self.drawnCanvas(24)
        let without = canvas.elements
        let bare = canvas.render()
        canvas.elements = without + [element]
        canvas.bumpVersion()
        let standing = canvas.render()
        if let d = diff(bare, standing, "\(what) fixture", file: file, line: line) {
            XCTAssertGreaterThan(d.bytes, 0,
                                 "\(what): fixture precondition — adding it to the display list "
                                 + "changed no pixel, so nothing below is about a \(what) at all",
                                 file: file, line: line)
        }
        let with = canvas.elements

        for (press, target) in [("undo", without), ("redo", with)] {
            let repairsBefore = canvas.regionRepairs
            let abandonedBefore = canvas.regionRepairsAbandoned
            canvas.restoreElements(target, changedInk: nil)
            XCTAssertTrue(isRegion(canvas.lastDamage),
                          "\(what): the \(press) declared \(canvas.lastDamage) — a \(what) carries "
                          + "its own extent in its stored geometry, so neither direction has to pay "
                          + "the cel", file: file, line: line)
            let repaired = canvas.render()
            XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1,
                           "\(what): the \(press) declared a rectangle and then walked the cel "
                           + "anyway, so nothing below is testing a bound", file: file, line: line)
            XCTAssertEqual(canvas.regionRepairsAbandoned, abandonedBefore,
                           "\(what): the \(press)'s repair was abandoned, which pays both walks and "
                           + "hides a rectangle that did not hold", file: file, line: line)
            assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                               inside: canvas.lastRepairedRegion,
                                               "a \(press)ne \(what)", file: file, line: line)
        }
    }

    /// **The headline: undoing a fill costs the fill's own path, not the cel.**
    ///
    /// A fill is `addPath` + `fillPath` and nothing else, and antialiasing is per-pixel coverage *of
    /// the path* — a pixel the path does not reach gets none — so `boundingBoxOfPath` contains every
    /// pixel it can touch. That is the one kind of the four whose bound is exact by construction
    /// rather than by a clip.
    ///
    /// Mutation that reddens it: restore the `guard let stroke = element.stroke else { return
    /// .everything }` in `restoreDamage`'s departing loop.
    func testUndoingAndRedoingAFillBothDeclareARectangleAndDrawTheRightPicture() {
        assertARoundTripIsBoundedAndDrawsRight(.fill(Self.fillElement(CGRect(x: 22.3, y: 18.7,
                                                                            width: 44.4, height: 33.2))),
                                               "fill")
    }

    /// An even-odd fill with a hole in it — the same path rule, and the arm `evenOddFill` selects.
    func testUndoingAndRedoingAFillWithAHoleIsBoundedTheSameWay() {
        let outer = CGPath(rect: CGRect(x: 20, y: 20, width: 60, height: 50), transform: nil)
        let ring = CGMutablePath()
        ring.addPath(outer)
        ring.addEllipse(in: CGRect(x: 35, y: 32, width: 30, height: 26))
        assertARoundTripIsBoundedAndDrawsRight(
            .fill(VectorFillElement(path: ring,
                                    color: CodableColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1),
                                    opacity: 0.8, evenOddFill: true)),
            "even-odd fill")
    }

    /// **A placed image is bounded by the quad `draw(image:into:)` itself maps.**
    ///
    /// Both read `PlacedRectangle.placement` applied to the natural-size rect, through the *same*
    /// `quad(of:)`, so the bound and the picture cannot drift apart the way two spellings of one
    /// matrix can. The rotation is what makes it a real test: an axis-aligned box would be green
    /// against a bound that ignored `placement` entirely.
    func testUndoingAndRedoingAPlacedImageIsBoundedByItsOwnQuad() {
        assertARoundTripIsBoundedAndDrawsRight(
            .image(Self.imageElement(at: CGPoint(x: 60, y: 55), side: 28, scale: 1.4,
                                     rotation: .pi / 7)),
            "rotated placed image")
    }

    /// **A video's placeholder is the branch that reaches outside its own rectangle**, by up to a
    /// quarter of a local unit once the 0.5-unit line-width floor bites. That is what the
    /// one-local-unit inflation in `placedFootprint` covers, and **the scale here is chosen so that
    /// the inflation is the only thing covering it**: `draw(video:)` strokes at `max(2/s, 0.5)` local
    /// units about a line inset `1/s`, so the border stands `0.25 − 1/s` local units — `0.25·s − 1`
    /// canvas points — proud of the natural rectangle. At `s = 12` that is **2 points**, which the one
    /// point of float slack cannot absorb and the 12 points the inflation contributes can. MEASURED
    /// by mutation: drop the inflation and this test reddens on the picture, not on the rectangle.
    ///
    /// A gentler scale would leave the mutation alive — at `s = 6` the overhang is half a point and
    /// the slack hides it — which is the shape of a fixture that pins nothing.
    func testUndoingAndRedoingAVideoPlaceholderIsBoundedIncludingItsBorder() {
        assertARoundTripIsBoundedAndDrawsRight(
            .video(Self.videoElement(at: CGPoint(x: 70, y: 60),
                                     natural: CGSize(width: 6, height: 4), scale: 12)),
            "video placeholder")
    }

    /// The decoded arm of the same element — one `UIImage.draw(in:)` inside the placement, exactly
    /// as a placed image, so it must bound the same way.
    func testUndoingAndRedoingAVideoShowingAFrameIsBoundedTheSameWay() {
        assertARoundTripIsBoundedAndDrawsRight(
            .video(Self.videoElement(at: CGPoint(x: 65, y: 58),
                                     natural: CGSize(width: 32, height: 18), scale: 1.5,
                                     rotation: .pi / 9,
                                     frame: Self.solidImage(.systemPink, side: 32))),
            "video showing a frame")
    }

    /// **A text object whose box clips is bounded by the box, and that is a proof rather than an
    /// estimate.** All three arms of `draw(text:into:quality:)` pass `clip: !frame.autoSize` down to
    /// `TextLayout.draw`, which turns it into a `CGContext.clip` on the layout box — so with the bit
    /// clear, no glyph can put a pixel outside the box quad whatever the font does.
    func testUndoingAndRedoingASizedTextObjectIsBoundedByTheBoxThatClipsIt() {
        assertARoundTripIsBoundedAndDrawsRight(
            .text(Self.textElement("Hello there", at: CGPoint(x: 24, y: 30),
                                   size: CGSize(width: 90, height: 34), autoSize: false)),
            "sized text object")
    }

    /// **A pristine (`autoSize`) text object is bounded by a measurement of its glyph ink, and
    /// draws the right picture on both presses.** The second box of TODO (41).
    ///
    /// An `autoSize` box was grown by `CTFramesetterSuggestFrameSizeWithConstraints`, a
    /// *typographic* extent; glyph ink runs past it by however much a font's italic overhang, swashes
    /// or accents care to, and `TextLayout.draw` is handed `clip: false` for exactly that box, so the
    /// box is no bound. `TextMeasure.glyphOutlineBounds(of:)` measures the outlines the flatten
    /// rasterises, and `derivedFootprint` pads them by the rasteriser's overshoot;
    /// `TextInkFootprintLogicTests` is the pixel sweep that says the pad holds. This is the round
    /// trip on a drawn cel: Zapfino, whose swashes reach well outside their line box, in a size that
    /// makes the reach several points. Mutation that reddens it: `guard !text.frame.autoSize else
    /// { return nil }` back in `derivedFootprint`'s text arm — the `.region` assertion goes first.
    func testUndoingAndRedoingAnAutoSizeTextObjectIsBoundedByItsMeasuredGlyphInk() {
        assertARoundTripIsBoundedAndDrawsRight(
            .text(VectorTextElement(
                recipe: TextRecipe(string: "Qfj", font: FontDescriptor(familyName: "Zapfino", faceName: "Zapfino"),
                                   typography: Typography(pointSize: 22)),
                frame: TextFrame(origin: CGPoint(x: 40, y: 30), size: CGSize(width: 60, height: 40),
                                 autoSize: true))),
            "autoSize text object")
    }

    /// **Both kinds of text box declare a rectangle now, and the two rectangles are different
    /// things** — which is the operand that says the `autoSize` arm measures glyphs rather than
    /// reading the box the sized arm reads. A sized box's rectangle is its frame plus a point of
    /// slack; a pristine box's is its glyph outline plus the raster overshoot, and for a string whose
    /// ink does not fill its box the two disagree.
    ///
    /// Mutation that reddens it: route `autoSize` back to `.everything` (the first assertion), or
    /// return `box.insetBy(-slack)` for both arms (the second).
    func testADepartingTextObjectDeclaresARectangleWhetherOrNotItsBoxClipsAndNotTheSameOne() {
        var declared: [Bool: CGRect] = [:]
        for autoSize in [true, false] {
            let canvas = Self.drawnCanvas(12)
            let without = canvas.elements
            let bare = canvas.render()
            let text = Self.textElement("Overhang", at: CGPoint(x: 30, y: 40), autoSize: autoSize)
            canvas.elements = without + [.text(text)]
            canvas.bumpVersion()
            let standing = canvas.render()
            if let d = diff(bare, standing, "autoSize=\(autoSize) fixture") {
                XCTAssertGreaterThan(d.bytes, 0,
                                     "fixture precondition: the text object with autoSize="
                                     + "\(autoSize) must actually put glyphs on the canvas")
            }

            canvas.restoreElements(without, changedInk: nil)
            guard case .region(let rect) = canvas.lastDamage else {
                XCTFail("a text object with autoSize=\(autoSize) declared \(canvas.lastDamage): a "
                        + "sized box is bounded by its clip and a pristine one by its measured glyph "
                        + "ink, so neither may pay the cel")
                continue
            }
            declared[autoSize] = rect
            let box = text.frame.boundingBox.insetBy(dx: -1, dy: -1)
            if autoSize {
                let outline = TextMeasure.glyphOutlineBounds(of: text)
                let pad = TextMeasure.glyphRasterOvershoot
                XCTAssertEqual(rect, outline.insetBy(dx: -pad, dy: -pad),
                               "a pristine box's rectangle is its glyph outline plus the overshoot")
            } else {
                XCTAssertEqual(rect, box, "a sized box's rectangle is the box that clips it, plus slack")
            }
        }
        if let pristine = declared[true], let sized = declared[false] {
            XCTAssertNotEqual(pristine, sized,
                              "the pristine and the sized rectangle came out identical (\(pristine)), "
                              + "so the autoSize arm is reading the box rather than the glyphs")
        }
    }

    /// **The payoff for a text object, counted in dabs** — the sibling of
    /// `testUndoingAFillStampsFarFewerDabsThanTheCelHolds`, for the press the second box was about.
    /// Mutation that reddens it: return `CGRect(origin: .zero, size: size)` from the text arm — a
    /// correct picture, worth nothing.
    func testUndoingAnAutoSizeTextObjectStampsFarFewerDabsThanTheCelHolds() {
        let canvas = Self.drawnCanvas(48)
        let without = canvas.elements
        canvas.elements = without + [.text(Self.textElement("Hi", at: CGPoint(x: 30, y: 40),
                                                            size: CGSize(width: 30, height: 24),
                                                            autoSize: true))]
        canvas.bumpVersion()
        _ = canvas.render()

        canvas.restoreElements(without, changedInk: nil)
        _ = canvas.render()
        let repairDabs = canvas.lastRenderDabCount
        let fullDabs = fullReWalk(of: canvas).dabs
        XCTAssertGreaterThan(fullDabs, 0, "the reference walk must have stamped something")
        XCTAssertLessThan(repairDabs * 3, fullDabs,
                          "undoing a pristine text object on a 48-mark grid re-stamped \(repairDabs) "
                          + "dabs against the cel's \(fullDabs) — the bound is not binding")
    }

    /// **One gesture that drops a fill and a stroke together**, which is the shape that exercises the
    /// union of the two halves rather than either alone: the stroke's rectangle comes from
    /// `paintedBounds` and the fill's from its path, and a restore that used one and forgot the other
    /// would leave a ghost of whichever it dropped.
    ///
    /// The fixture puts them in opposite corners on purpose, so a rectangle that covers only one is
    /// nowhere near the other.
    func testARestoreThatDropsAFillAndAStrokeTogetherBoundsBothOfThem() {
        let canvas = Self.drawnCanvas(24)
        let base = canvas.elements
        let bare = canvas.render()
        canvas.elements = base + [.stroke(Self.mark(41)),
                                  .fill(Self.fillElement(CGRect(x: 8, y: 8, width: 26, height: 22)))]
        // See `assertARoundTripIsBoundedAndDrawsRight`: the setter does not invalidate, so without
        // this the canvas hands back its memo and neither of the two is ever drawn or measured.
        canvas.bumpVersion()
        let standing = canvas.render()
        if let d = diff(bare, standing, "mixed fixture") {
            XCTAssertGreaterThan(d.bytes, 0, "fixture precondition: the added stroke and fill paint")
        }

        let repairsBefore = canvas.regionRepairs
        canvas.restoreElements(base, changedInk: nil)
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "a mixed departure must union the measured half with the derived one, not "
                      + "give up because one of the two is not a stroke")
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1,
                       "the mixed undo must repair rather than declare a rectangle and walk anyway")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a fill and a stroke leaving together")
    }

    /// **The payoff, counted in dabs** — the sibling of
    /// `testUndoingACutStampsFarFewerDabsThanTheCelHolds`, on the press this box was about.
    ///
    /// `.everything` and a canvas-sized rectangle draw the same right picture, so a picture assertion
    /// cannot tell them apart; this is the operand that can. Mutation that reddens it: return
    /// `CGRect(origin: .zero, size: size)` from `derivedFootprint`'s fill arm — still a correct
    /// picture, and worth nothing.
    func testUndoingAFillStampsFarFewerDabsThanTheCelHolds() {
        let canvas = Self.drawnCanvas(48)
        let without = canvas.elements
        canvas.addFill(Self.fillElement(CGRect(x: 20, y: 20, width: 34, height: 26)))
        _ = canvas.render()

        canvas.restoreElements(without, changedInk: nil)
        _ = canvas.render()
        let repairDabs = canvas.lastRenderDabCount
        let fullDabs = fullReWalk(of: canvas).dabs
        XCTAssertGreaterThan(fullDabs, 0, "the reference walk must have stamped something")
        XCTAssertLessThan(repairDabs * 3, fullDabs,
                          "undoing a fill on a 48-mark grid re-stamped \(repairDabs) dabs against "
                          + "the cel's \(fullDabs) — the bound is not binding")
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

    /// **And a round trip must not grow the remembered ones either** — `vacatedInk`'s counterpart to
    /// the test above, and the one thing about that table that no picture assertion can see.
    ///
    /// The rule is that an entry exists only while its id is *out* of the display list, so the count
    /// is a function of the document's state and not of how many presses have happened. Four round
    /// trips must therefore leave exactly what one does. Without the prune each trip adds the cut's
    /// parent *and* its two pieces, and the count climbs by three a press.
    ///
    /// **It is one rather than zero, and that is the rule rather than a slack bound**: the loop ends
    /// on the post-cut list, where the parent stroke has been replaced by two pieces and is genuinely
    /// out of the display list. Mutation that reddens it: delete the `for id in vacatedInk.keys` loop
    /// in `rememberVacatedInk`.
    func testARoundTripDoesNotGrowTheRememberedFootprints() {
        let canvas = Self.drawnStripes()
        let before = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 12), brush: Self.brush(),
                                   size: 8, opacity: 1, mode: .cutPoints))
        guard case .region(let cutRegion) = canvas.lastDamage else {
            return XCTFail("the fixture must cut and bound itself")
        }
        let after = canvas.elements
        _ = canvas.render()

        var afterOneTrip = 0
        for trip in 0..<4 {
            canvas.restoreElements(before, changedInk: cutRegion)
            _ = canvas.render()
            canvas.restoreElements(after, changedInk: cutRegion)
            _ = canvas.render()
            if trip == 0 { afterOneTrip = canvas.rememberedInkCount }
        }
        XCTAssertEqual(canvas.rememberedInkCount, afterOneTrip,
                       "four round trips left \(canvas.rememberedInkCount) remembered rectangles "
                       + "where one left \(afterOneTrip) — the table is counting presses, not the "
                       + "ids that are out of the list")
        XCTAssertEqual(afterOneTrip, strokeIDs(before).subtracting(strokeIDs(after)).count,
                       "one trip ends on the post-cut list, so exactly the ids that list has lost — "
                       + "the parent the cut replaced — are out of it")
    }

    /// **An undo that is never redone keeps its hint, and that is the shape the cap is for.**
    ///
    /// The prune above takes an entry out when its id comes back. Nothing takes one out when it does
    /// not, which is exactly the state a run of undos leaves — so this pins the count as a function of
    /// what is out of the list rather than of how many presses have happened, and it is the operand a
    /// future leak would move. Mutation that reddens it: keep only the last restore's departures.
    func testARunOfUndosRemembersOneRectanglePerStrokeStillOutOfTheList() {
        let canvas = Self.drawnCanvas(24)
        var lists: [[VectorElement]] = [canvas.elements]
        for step in 0..<4 {
            canvas.addStroke(Self.mark(30 + step))
            _ = canvas.render()
            lists.append(canvas.elements)
        }
        XCTAssertEqual(canvas.rememberedInkCount, 0, "control: nothing has left the list yet")

        for step in stride(from: 3, through: 0, by: -1) {
            canvas.restoreElements(lists[step], changedInk: nil)
            _ = canvas.render()
            XCTAssertEqual(canvas.rememberedInkCount, 4 - step,
                           "after \(4 - step) undo(s) exactly that many strokes are out of the list")
        }
        for step in 1...4 {
            canvas.restoreElements(lists[step], changedInk: nil)
            _ = canvas.render()
            XCTAssertEqual(canvas.rememberedInkCount, 4 - step,
                           "each redo puts one id back and takes its hint with it")
        }
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

    // MARK: - (6) The other seam — every vector undo that is not a drawing gesture

    /// A manager holding one vector layer whose only cel is `canvas`, with the history cleared
    /// (`addVectorLayer` records a structural step of its own).
    private func manager(around canvas: VectorCanvas) -> CanvasManager {
        let manager = CanvasManager()
        // Never the shared store — `CanvasFixture.isolatedBrushLibrary`'s doc has the reason.
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = canvas.size
        manager.addVectorLayer()
        manager.layers[0].cels[0].vector = canvas
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return manager
    }

    /// **`registerVectorElementsUndo` bounds a swap when its caller says nothing was rewritten**, and
    /// this drives it through `CanvasManager.undo()`/`redo()` rather than calling the closures, so the
    /// press is the artist's press.
    ///
    /// The fill commits, the text commit, Clear-on-selection and the shape bake all come through here;
    /// before this pass every one of them declared `.everything` in both directions, which is the
    /// whole-cel walk PERFORMANCE.md §11.11 measures at 1.1 s a press on a 2,000-stroke cel. Mutation
    /// that reddens it: hand `.rewritesInPlace` instead.
    func testAnElementsUndoThatOnlyAddsAndRemovesIsBoundedInBothDirections() {
        let canvas = Self.drawnCanvas(24)
        let before = canvas.elements
        canvas.addStroke(Self.mark(30))
        let after = canvas.elements
        _ = canvas.render()

        let manager = manager(around: canvas)
        manager.registerVectorElementsUndo(vectorCanvas: canvas, oldElements: before,
                                           newElements: after, layerID: manager.layers[0].id,
                                           celID: manager.layers[0].cels[0].id, label: .shape,
                                           swap: .addsAndRemoves(ink: nil))
        manager.undo()
        XCTAssertTrue(isRegion(canvas.lastDamage), "the undo must bound itself off what departs")
        _ = canvas.render()
        manager.redo()
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "and the redo off what the undo remembered that stroke had painted")
    }

    /// **And bounds it when the caller says an element came back under its own id with different
    /// content, once the caller says which** — TODO (41)'s last box. A recolour and an Apply Brush
    /// are that case, and until this pass it was the one that stayed at `.everything`: the footprints
    /// `restoreElements` drops are chosen by id difference, so a rewritten element it was not told
    /// about would keep a measurement no longer true of it. Told, it forgets that element's
    /// footprint and bounds the swap by where the element was and where it will be.
    ///
    /// Both directions are driven through `CanvasManager.undo()`/`redo()` and both pictures are
    /// checked against a cold full re-walk. Mutations that redden it, each named beside the operand
    /// it reaches: route `.rewritesInPlace` back to `bumpVersion()` — the `.region` assertions;
    /// ignore `rewrites` inside `restoreDamage` (treat the set as empty) — the swap then declares a
    /// null region, the memo stands, and the *picture* assertion fails with the old colour still
    /// showing.
    func testAnElementsUndoThatRewritesInPlaceIsBoundedInBothDirectionsAndDrawsRight() {
        let canvas = Self.drawnCanvas(24)
        let before = canvas.elements
        // A recolour's shape: the same ids, one of them carrying different content.
        var recoloured = before
        guard case .stroke(var stroke) = recoloured[3] else {
            return XCTFail("the fixture must hold strokes")
        }
        stroke.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        recoloured[3] = .stroke(stroke)
        canvas.restoreElements(recoloured, changedInk: nil, rewriting: [stroke.id])
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the forward rewrite declared \(canvas.lastDamage) — it knows the id")
        _ = canvas.render()

        let manager = manager(around: canvas)
        manager.registerVectorElementsUndo(vectorCanvas: canvas, oldElements: before,
                                           newElements: recoloured, layerID: manager.layers[0].id,
                                           celID: manager.layers[0].cels[0].id,
                                           label: .recolorSelection,
                                           swap: .rewritesInPlace([stroke.id]))
        for (press, expected) in [("undo", before), ("redo", recoloured)] {
            let repairsBefore = canvas.regionRepairs
            let widenedBefore = canvas.regionRepairsWidened
            if press == "undo" { manager.undo() } else { manager.redo() }
            XCTAssertTrue(isRegion(canvas.lastDamage),
                          "the \(press) declared \(canvas.lastDamage) — a rewrite whose ids are known "
                          + "is bounded by where the element was and where it will be")
            XCTAssertNotEqual(canvas.lastDamage, .region(.null),
                              "the \(press) declared a null region, which means the rewrite was not "
                              + "seen at all and the stale picture would stand")
            let repaired = canvas.render()
            XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1,
                           "the \(press) declared a rectangle and then walked the cel anyway")
            XCTAssertEqual(canvas.regionRepairsWidened, widenedBefore,
                           "a recolour leaves the geometry alone, so the old measurement is the new "
                           + "footprint exactly and nothing should have escaped")
            XCTAssertEqual(fingerprints(canvas.elements), fingerprints(expected),
                           "the \(press) did not put the expected list back")
            assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                               inside: canvas.lastRepairedRegion,
                                               "the \(press)ne recolour")
        }
    }

    /// **The text commit's three answers, driven through the real session** — `beginTextSession`,
    /// `updateTextString`, `commitInteractiveText`, then `undo()`. Placing a label is an add and its
    /// undo is bounded; emptying a reopened label *removes* its id and its undo is bounded too; and
    /// since TODO (41)'s last box retyping a reopened label — the same id with different content —
    /// is bounded as well, by the union of the old glyph ink and the new. Mutation that reddens the
    /// third: `swap: … .rewritesInPlace([])` (an empty set) in `commitTextToVector`, which makes the
    /// undo declare a null region and leave "Relabel" standing in the picture.
    ///
    /// All three are pristine boxes, so every bounded answer here is the measured glyph-ink
    /// rectangle rather than the box.
    func testTheTextCommitBoundsAnAddADeletionAndARetype() {
        let canvas = Self.drawnCanvas(24)
        _ = canvas.render()
        let manager = manager(around: canvas)
        manager.textRecipe.typography.pointSize = 24

        // Add.
        manager.beginTextSession(at: CGPoint(x: 40, y: 30))
        manager.updateTextString("Label")
        manager.commitInteractiveText()
        guard case .text(let placed)? = canvas.elements.last else {
            return XCTFail("the commit must put a text object on top of the list")
        }
        XCTAssertTrue(placed.frame.autoSize, "fixture: a box nobody resized is pristine")
        _ = canvas.render()
        manager.undo()
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "undoing the add declared \(canvas.lastDamage) — a departing pristine text "
                      + "object is bounded by its measured glyph ink")
        _ = canvas.render()
        manager.redo()
        XCTAssertTrue(isRegion(canvas.lastDamage), "and redoing it is bounded the same way")
        _ = canvas.render()

        // Delete by emptying — the id leaves the list, which is a removal and not a rewrite.
        let centre = CGPoint(x: placed.frame.boundingBox.midX, y: placed.frame.boundingBox.midY)
        manager.beginTextSession(at: centre)
        XCTAssertEqual(manager.textEditingElementID, placed.id, "fixture: the tap reopened the label")
        manager.updateTextString("")
        manager.commitInteractiveText()
        XCTAssertFalse(canvas.elements.contains { $0.id == placed.id }, "fixture: the label is gone")
        XCTAssertTrue(manager.canUndo, "fixture: the deletion registered a step")
        _ = canvas.render()
        manager.undo()
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "undoing the deletion declared \(canvas.lastDamage) — the label's id left the "
                      + "list and comes back, which is an add/remove swap, not a rewrite")
        XCTAssertTrue(canvas.elements.contains { $0.id == placed.id }, "the label is back")
        _ = canvas.render()

        // Retype — the same id with different content, bounded by both glyph-ink rectangles.
        manager.beginTextSession(at: centre)
        XCTAssertEqual(manager.textEditingElementID, placed.id, "fixture: the tap reopened the label")
        manager.updateTextString("Relabel")
        manager.commitInteractiveText()
        _ = canvas.render()
        let repairsBefore = canvas.regionRepairs
        manager.undo()
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "undoing the retype declared \(canvas.lastDamage) — a retyped label keeps its "
                      + "id with different content, and both contents carry their own glyph ink")
        XCTAssertNotEqual(canvas.lastDamage, .region(.null), "the retype was not seen as a rewrite")
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1, "the retype's undo walked the cel anyway")
        XCTAssertEqual(canvas.elements.first { $0.id == placed.id }?.text?.recipe.string, "Label",
                       "the undo did not put the old string back")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "the undone retype")
    }

    /// **The measured footprint of the element a rewrite rewrote must not survive it, and every
    /// other element's must** — which is the promise the answer above keeps rather than the
    /// declaration it makes, and it is invisible to `lastDamage`.
    ///
    /// An entry is a promise the element has not changed, and `renderLocalContent` reads it twice:
    /// to skip an element whose entry misses the clip, and to decide whether a drawn element's
    /// footprint is escape-checked at all (`known == nil`). A rewritten stroke with a surviving entry
    /// would be drawn clipped to whatever its site declared and never widened, so a hint that came
    /// out too small would cut its ink off at the clip edge for good. Forgetting *everything*
    /// instead — which is what `.everything` did — throws away the measurements that make the
    /// repair a repair. Mutation that reddens it either way: drop the
    /// `forgetPaintedBounds(rewrites…)` line (count stays 24), or put `bumpVersion()` back (count 0).
    func testARewriteInPlaceDropsTheFootprintOfTheElementItRewroteAndNoOther() {
        let canvas = Self.drawnCanvas(24)
        let before = canvas.elements
        var recoloured = before
        guard case .stroke(var stroke) = recoloured[3] else {
            return XCTFail("the fixture must hold strokes")
        }
        stroke.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        recoloured[3] = .stroke(stroke)
        canvas.restoreElements(recoloured, changedInk: nil, rewriting: [stroke.id])
        _ = canvas.render()
        XCTAssertEqual(canvas.measuredFootprintCount, canvas.elements.count,
                       "control: the walk above measured every stroke")

        let manager = manager(around: canvas)
        manager.registerVectorElementsUndo(vectorCanvas: canvas, oldElements: before,
                                           newElements: recoloured, layerID: manager.layers[0].id,
                                           celID: manager.layers[0].cels[0].id,
                                           label: .recolorSelection,
                                           swap: .rewritesInPlace([stroke.id]))
        manager.undo()
        XCTAssertEqual(canvas.measuredFootprintCount, before.count - 1,
                       "the press left \(canvas.measuredFootprintCount) footprints standing out of "
                       + "\(before.count) — exactly one element changed, so exactly one promise is gone")
    }

    // MARK: - (7) A rewrite in place, driven through the verbs the artist has — TODO (41)'s last box
    //
    // Section (6) drives `registerVectorElementsUndo` by hand. These drive `recolorSelection`,
    // `applyBrushToSelection`, the lasso move and the video speed row through the manager, so the
    // ids each site declares are the ids it really rewrites, and every picture is checked against a
    // cold full re-walk of the list the canvas ends up holding.

    /// A manager whose active vector layer's first cel is `canvas`, the way `LassoMoveLogicTests`'
    /// fixture is built, with a selection over `loop`.
    private func manager(around canvas: VectorCanvas, selecting loop: CGRect,
                         membership: LassoMembership) -> CanvasManager {
        let manager = manager(around: canvas)
        manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop,
                                      layerID: manager.layers[0].id,
                                      celID: manager.layers[0].cels[0].id)
        manager.setSelectionMembership(membership)
        return manager
    }

    /// The grid's cells 9, 10, 17 and 18 — a 2x2 block of short marks — with a margin that catches
    /// each whole. Under Cut nothing straddles this loop, so Cut and Touching agree about it.
    private static let blockLoop = CGRect(x: 26, y: 26, width: 40, height: 28)

    /// A loop through the *middle* of cells 9 and 10, so under Cut both are split and the inside
    /// halves arrive as fresh pieces — the arrival `inkOfArrivals` had no rectangle for.
    private static let straddlingLoop = CGRect(x: 32, y: 24, width: 22, height: 14)

    /// **The headline: recolouring a selection costs the selection, not the cel, and it draws the
    /// right picture in all three directions.**
    ///
    /// Under Touching every caught stroke is a same-id rewrite; under Cut two of them are split as
    /// well, so the swap adds and removes on top of rewriting, and the pieces that arrive are strokes
    /// this canvas has never walked — bounded by `strokeInkHint(of:)`, which is the arm that made a
    /// Cut recolour boundable at all. Both are driven, and each picture is checked.
    ///
    /// Mutations that redden it: `swap: .rewritesInPlace([])` at the site — the undo declares a null
    /// region, the memo stands, and the picture keeps the picked colour; `bumpVersion()` back in
    /// `recolorSelection` — the forward `.region` assertion; drop the `strokeInkHint` fallback in
    /// `inkOfArrivals` — the Cut arm's forward and redo assertions say `.everything`.
    func testARecolourOfASelectionIsBoundedAndDrawsRightForwardsUndoneAndRedone() {
        for (membership, loop) in [(LassoMembership.touching, Self.blockLoop),
                                   (LassoMembership.cutting, Self.straddlingLoop)] {
            let what = "recolour under \(membership)"
            let canvas = Self.drawnCanvas(48)
            let before = canvas.elements
            let manager = manager(around: canvas, selecting: loop, membership: membership)
            manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

            let repairsBefore = canvas.regionRepairs
            manager.recolorSelection()
            XCTAssertNotEqual(fingerprints(canvas.elements), fingerprints(before),
                              "\(what): fixture — the loop caught nothing, so nothing below is about "
                              + "a recolour at all")
            XCTAssertTrue(isRegion(canvas.lastDamage),
                          "\(what): the forward edit declared \(canvas.lastDamage)")
            var repaired = canvas.render()
            XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1,
                           "\(what): the forward edit declared a rectangle and walked the cel anyway")
            assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                               inside: canvas.lastRepairedRegion, "\(what), applied")
            let after = canvas.elements

            for (press, expected) in [("undo", before), ("redo", after)] {
                let repairs = canvas.regionRepairs
                let abandoned = canvas.regionRepairsAbandoned
                if press == "undo" { manager.undo() } else { manager.redo() }
                XCTAssertTrue(isRegion(canvas.lastDamage),
                              "\(what): the \(press) declared \(canvas.lastDamage)")
                XCTAssertNotEqual(canvas.lastDamage, .region(.null),
                                  "\(what): the \(press) saw no rewrite and would leave the picture")
                XCTAssertEqual(fingerprints(canvas.elements), fingerprints(expected),
                               "\(what): the \(press) put the wrong list back")
                repaired = canvas.render()
                XCTAssertEqual(canvas.regionRepairs, repairs + 1,
                               "\(what): the \(press) declared a rectangle and walked the cel anyway")
                XCTAssertEqual(canvas.regionRepairsAbandoned, abandoned,
                               "\(what): the \(press)'s repair was abandoned")
                assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                                   inside: canvas.lastRepairedRegion,
                                                   "\(what), \(press)ne")
            }
        }
    }

    /// **Apply Brush to a brush with twice the reach bounds by the *new* width, and the escape
    /// check is what stands behind the number.**
    ///
    /// A re-pointed brush moves no sample, but `dab.size` is a fraction of the stroke's width and
    /// `stampRadius` multiplies them, so a brush at 200% paints a stroke twice as wide as the one
    /// the walk measured. The new half of the rectangle is therefore `strokeInkHint(of:)` at the new
    /// brush's reach, not the old measurement, and `regionRepairsWidened` staying at 0 is the
    /// operand that says the hint held. Mutation that reddens it: pad by the old brush — hand
    /// `strokeInkHint(of: old)` from `rewrittenInk` — and `widened` goes to 1 while the picture stays
    /// right, which is the whole point: for a stroke, too small is a second walk, not a ghost. The
    /// picture assertion is what reddens if that retry is *also* taken away (a surviving
    /// `paintedBounds` entry, which `testARewriteInPlaceDropsTheFootprint…` pins separately).
    func testAnApplyBrushToAWiderBrushBoundsByTheNewWidth() {
        let canvas = Self.drawnCanvas(48)
        let before = canvas.elements
        let manager = manager(around: canvas, selecting: Self.blockLoop, membership: .touching)
        var wider = Self.brush()
        wider.name = "Twice"
        wider.dab.size = 2
        manager.selectedBrush = wider

        let repairsBefore = canvas.regionRepairs
        let widenedBefore = canvas.regionRepairsWidened
        manager.applyBrushToSelection()
        XCTAssertNotEqual(fingerprints(canvas.elements).count, 0, "fixture: strokes present")
        XCTAssertTrue(canvas.elements.contains { $0.stroke?.brushRef == BrushPool.intern(wider) },
                      "fixture: the loop caught nothing, so nothing below is about Apply Brush")
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the forward Apply Brush declared \(canvas.lastDamage)")
        var repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1, "declared a rectangle, walked the cel")
        XCTAssertEqual(canvas.regionRepairsWidened, widenedBefore,
                       "the new brush's ink escaped the rectangle its site declared — the hint was "
                       + "padded by the old reach, not the new one")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "Apply Brush, applied")
        let after = canvas.elements

        for (press, expected) in [("undo", before), ("redo", after)] {
            let repairs = canvas.regionRepairs
            let widened = canvas.regionRepairsWidened
            if press == "undo" { manager.undo() } else { manager.redo() }
            XCTAssertTrue(isRegion(canvas.lastDamage), "the \(press) declared \(canvas.lastDamage)")
            XCTAssertEqual(fingerprints(canvas.elements), fingerprints(expected),
                           "the \(press) put the wrong list back")
            repaired = canvas.render()
            XCTAssertEqual(canvas.regionRepairs, repairs + 1, "the \(press) walked the cel anyway")
            XCTAssertEqual(canvas.regionRepairsWidened, widened,
                           "the \(press)'s arriving width escaped the rectangle")
            assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                               inside: canvas.lastRepairedRegion,
                                               "Apply Brush, \(press)ne")
        }
    }

    /// **A lasso nudge with the latch armed changes no pixel of the canvas's own picture and costs
    /// it no walk** — the case among the four `bumpVersion()` sites that turns out to be free.
    ///
    /// While a float is up its pieces are suppressed and the latch draws them, so the canvas's
    /// picture is of everything else; a nudge moves suppressed geometry only. `restoreDamage` skips
    /// a suppressed rewritten element on both halves and declares a null region, which
    /// `invalidateRenderOnly` reads as "every memo stands". Until this pass each nudge paid a full
    /// walk for the picture it already had. The commit is then the one `.everything` that draws the
    /// moved ink, and the *undo* of the nudge after it — nothing suppressed, the pieces measured by
    /// that walk, the parent returning under an id the canvas never measured — is bounded.
    ///
    /// Mutations that redden it: drop the `_suppressedElementIDs.contains` skip in `restoreDamage`
    /// — the nudge declares a hint, `applyToRegionBase` refuses a base under suppression, and
    /// `rasterizations` moves; drop the null-region arm in `invalidateRenderOnly` — the same
    /// operand, since a null region then falls to a full walk.
    func testALassoNudgeWithTheLatchArmedChangesNoPixelAndCostsNoWalk() {
        let canvas = Self.drawnCanvas(48)
        let manager = manager(around: canvas, selecting: Self.straddlingLoop, membership: .cutting)
        XCTAssertTrue(manager.beginVectorLassoMove(), "fixture: the lift must take")
        guard let float = manager.vectorFloat else { return XCTFail("fixture: no float") }
        XCTAssertFalse(float.insideIDs.isEmpty, "fixture: the loop caught nothing")
        XCTAssertEqual(canvas.suppressedElementIDs, float.insideIDs,
                       "fixture: the lifted pieces are suppressed while the latch is armed")
        // The lift itself is `.everything` (the suppression changed). Settle it.
        let settled = canvas.render()
        let rasterizations = canvas.rasterizations

        var transform = float.frame.transform
        transform.position = CGPoint(x: transform.position.x + 30, y: transform.position.y + 20)
        manager.nudgeVectorFloat(to: transform)
        XCTAssertEqual(canvas.lastDamage, .region(.null),
                       "the nudge declared \(canvas.lastDamage) — every element it rewrote is "
                       + "suppressed, so no pixel of this canvas's picture changed")
        let afterNudge = canvas.render()
        XCTAssertEqual(canvas.rasterizations, rasterizations,
                       "the nudge cost a walk for a picture the canvas already had")
        if let d = diff(settled, afterNudge, "nudge") {
            XCTAssertEqual(d.bytes, 0, "the standing picture changed under a nudge of suppressed ink")
        }

        // Commit: un-suppressing is the one `.everything`, and the moved ink is drawn there.
        manager.commitVectorFloatIfNeeded()
        XCTAssertTrue(canvas.suppressedElementIDs.isEmpty, "the commit clears the suppression")
        let committed = canvas.render()
        let cold = VectorCanvas(size: canvas.size, elements: canvas.elements)
        if let d = diff(committed, cold.render(), "committed nudge") {
            XCTAssertEqual(d.bytes, 0, "the committed picture is not the moved list's: \(d.summary)")
        }
        let moved = canvas.elements

        // Undo the nudge: the pieces (measured by the commit's walk) depart, the parents (never
        // measured under their ids — the lift went through the plain setter) arrive by hint.
        let repairsBefore = canvas.regionRepairs
        manager.undo()
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "the undo of a committed nudge declared \(canvas.lastDamage)")
        XCTAssertNotEqual(canvas.lastDamage, .region(.null), "the undo saw nothing to do")
        let undone = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1, "the undo walked the cel anyway")
        assertMatchesToWithinARoundingUnit(undone, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "the undone nudge")
        XCTAssertNotEqual(fingerprints(canvas.elements), fingerprints(moved),
                          "the undo did not move the geometry back")
        if let d = diff(committed, undone, "undone nudge against committed") {
            XCTAssertGreaterThan(d.bytes, 0, "the ink did not move back on screen")
        }
    }

    /// **A video's speed is a same-id rewrite that moves no rectangle, and the row bounds it by the
    /// placeholder's own quad in both directions** — driven through `setVideoSpeed`, whose undo is
    /// the structure snapshot's `restoreVideoCrops`, the fourth `bumpVersion()` site.
    ///
    /// The placeholder is what this canvas draws — the decoded frame is `videoCelContent`'s, keyed
    /// on the version — so the repair redraws a rectangle the size of the clip and nothing else.
    /// Mutation that reddens it: `bumpVersion()` back in either `setVideoSpeed` or
    /// `restoreVideoCrops` — the `.region` assertion on that side.
    func testAVideoSpeedChangeIsBoundedByTheVideosOwnRectangleInBothDirections() {
        let canvas = Self.drawnCanvas(24)
        let video = Self.videoElement(at: CGPoint(x: 100, y: 70))
        canvas.elements = canvas.elements + [.video(video)]
        canvas.bumpVersion()
        _ = canvas.render()
        let manager = manager(around: canvas)
        XCTAssertTrue(canvas.holdsVideo, "fixture: the cel holds a video")

        let repairsBefore = canvas.regionRepairs
        manager.setVideoSpeed(layerIndex: 0, celIndex: 0, to: 2)
        XCTAssertEqual(canvas.elements.last?.video?.speed, 2, "fixture: the speed was written")
        XCTAssertTrue(isRegion(canvas.lastDamage), "the speed row declared \(canvas.lastDamage)")
        if case .region(let rect) = canvas.lastDamage {
            XCTAssertTrue(rect.width < canvas.size.width / 2 && rect.height < canvas.size.height / 2,
                          "the rectangle \(rect) is not the clip's own quad")
        }
        var repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1, "declared a rectangle, walked the cel")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "speed, applied")

        let repairs = canvas.regionRepairs
        manager.undo()
        XCTAssertEqual(canvas.elements.last?.video?.speed, 1, "the undo did not put the speed back")
        XCTAssertTrue(isRegion(canvas.lastDamage), "the undo declared \(canvas.lastDamage)")
        repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairs + 1, "the undo walked the cel anyway")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "speed, undone")
    }

    /// **A second rewrite before the first has rendered is still bounded — TODO (42)'s slider, one
    /// level down.** The second tick finds the stroke with no measured footprint: the first tick
    /// forgot it and no walk has run since. `.everything` there would be a full walk on every tick
    /// but the first, and it is not needed: an entry is only ever removed by `.everything`, which
    /// drops every base, or by a region site that declared a rectangle containing the ink — which
    /// every base then carries in its pending region. So the stroke's old ink is either in no base
    /// or inside a region the next repair redraws, and the second tick declares only where the
    /// stroke goes.
    ///
    /// The fixture moves the stroke twice, A → B → C, so the three rectangles are disjoint and the
    /// argument is load-bearing rather than incidental: the picture is right only if the repair
    /// covers A (tick one's declaration) *and* C (tick two's). Mutations that redden it: return
    /// `.everything` for a rewritten stroke with no entry — the `.region` assertion on tick two;
    /// take `rect` instead of `standing.region.union(rect)` in `applyToRegionBase` — the picture,
    /// with the stroke's ink at A left standing as a ghost.
    func testASecondRewriteBeforeTheFirstHasRenderedIsStillBounded() {
        let canvas = Self.drawnCanvas(24)
        guard case .stroke(let stroke) = canvas.elements[3] else {
            return XCTFail("the fixture must hold strokes")
        }
        func moved(_ dx: CGFloat, _ dy: CGFloat) -> [VectorElement] {
            var list = canvas.elements
            var copy = stroke
            copy.samples = StrokeSamples(stroke.samples.map {
                VectorSample(x: $0.x + dx, y: $0.y + dy, pressure: $0.pressure)
            }, channels: .pressureOnly)
            list[3] = .stroke(copy)
            return list
        }
        let repairsBefore = canvas.regionRepairs
        canvas.restoreElements(moved(60, 0), changedInk: nil, rewriting: [stroke.id])
        XCTAssertTrue(isRegion(canvas.lastDamage), "tick one declared \(canvas.lastDamage)")
        XCTAssertEqual(canvas.measuredFootprintCount, 23, "tick one forgot the stroke's entry")
        // No render between the ticks — that is the whole fixture.
        canvas.restoreElements(moved(60, 60), changedInk: nil, rewriting: [stroke.id])
        XCTAssertTrue(isRegion(canvas.lastDamage),
                      "tick two declared \(canvas.lastDamage) — a rewritten stroke with no measured "
                      + "footprint has its old ink inside the pending region already")
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, repairsBefore + 1, "the ticks declared and then walked")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion, "two ticks, one render")
    }

    /// **A departing stroke that was never measured still says `.everything`, rewrite or not** —
    /// the fallback the item asks for, pinned as the contract it is. A Cut recolour on a canvas that
    /// has never walked splits a parent nobody measured, and `regionDamage(replacing:)` refuses.
    ///
    /// **The picture cannot go red here, and saying so is the honest half.** A canvas with no
    /// measured footprints has no base either, so a guessed rectangle and `.everything` walk the same
    /// list whole; the declaration is what this pins, and it reddens if `regionDamage` guesses.
    func testAnUnmeasuredDepartureUnderARewriteStillSaysEverything() {
        let canvas = Self.canvas(48)
        let manager = manager(around: canvas, selecting: Self.straddlingLoop, membership: .cutting)
        manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        manager.recolorSelection()
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "a cel with no measured footprints cannot bound the parents a Cut replaces")
        XCTAssertEqual(canvas.rasterizations, 0, "fixture: nothing has walked")
        _ = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 0, "there was no base to repair")
    }

    /// **Two identical restores in a row cost one walk, not two** — the trap PERFORMANCE.md §11.11
    /// records in the bench, closed: the second finds nothing departing, nothing arriving and
    /// nothing rewritten, declares a null region, and every memo stands. Mutation that reddens it:
    /// drop the null-region arm in `invalidateRenderOnly`.
    func testARestoreThatChangesNothingKeepsTheMemo() {
        let canvas = Self.drawnCanvas(24)
        let list = canvas.elements
        canvas.restoreElements(list, changedInk: nil)
        XCTAssertEqual(canvas.lastDamage, .region(.null), "an identical list changes no pixel")
        let rasterizations = canvas.rasterizations
        _ = canvas.render()
        XCTAssertEqual(canvas.rasterizations, rasterizations, "the memo should have answered")
        XCTAssertGreaterThan(canvas.version, 0, "the version still moves, for its consumers' memos")
    }
}
