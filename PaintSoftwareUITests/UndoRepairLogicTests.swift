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

    /// **And redoing that append is bounded by what it painted before it left.**
    ///
    /// This test said the opposite until the general pass, and the sentence it was written to defend
    /// was true of the canvas and false of the *history*: the ink coming back has never been drawn
    /// *in this list*, but it was drawn immediately before, by the walk that measured it, and
    /// `restoreElements` keeps that measurement in `vacatedInk` when the id leaves. Guessing a box
    /// from the stroke's geometry is still what BRUSH.md §12 stage 8 refuted and is still not what
    /// happens here — this is the measurement, not a derivation from the brush.
    ///
    /// Mutation that reddens it: return nil from `rememberedInk(of:)`, or stop calling
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

    /// **A hint only exists for ink the walk measures, so a returning fill still says `.everything`.**
    ///
    /// `renderLocalContent` measures footprints for strokes alone, on its own stated grounds, and a
    /// fill is therefore never in `paintedBounds` and never in `vacatedInk`. It is also the kind that
    /// *cannot* be caught by the escape check — it is always drawn and never measured — so bounding
    /// one on a hint would be a wrong picture rather than a retry. `rememberedInk(ofArrivalsIn:
    /// standing:)` asks each arrival for its `stroke` rather than looking the id up and hoping.
    ///
    /// **Reddening this took two mutations, and finding that out is what the sweep is for.** Dropping
    /// the `element.stroke` guard on its own leaves it green, because nothing puts a fill in the table
    /// to be found — the guard is protecting an invariant that holds one level down. It is
    /// load-bearing rather than dead, and the pair that shows it is: record a fallback rectangle for
    /// a departing element with no measured footprint (`vacatedInk[element.id] = CGRect(origin: .zero,
    /// size: size)` in `rememberVacatedInk`) **and** drop the guard, and this goes red; record the
    /// fallback with the guard in place and it stays green. So the guard is what stands between a
    /// future measurement of some other kind and a rectangle no escape check can correct.
    func testRedoingAFillIsNotBoundedByAHintBecauseAFillIsNeverMeasured() {
        let canvas = Self.drawnCanvas(12)
        let withoutFill = canvas.elements
        canvas.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 20, y: 20, width: 40, height: 30),
                                                      transform: nil),
                                         color: CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1),
                                         opacity: 1))
        let withFill = canvas.elements
        _ = canvas.render()

        canvas.restoreElements(withoutFill, changedInk: nil)
        _ = canvas.render()
        canvas.restoreElements(withFill, changedInk: nil)
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "a fill arriving with no rectangle from its caller has nothing that could "
                       + "bound it, and no escape check to catch a guess")
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
    /// Mutation that reddens it: return nil from `rememberedInk(of:)`, which makes the two counts equal.
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

    /// **And refuses to, when the caller says an element came back under its own id with different
    /// content.** A recolour and an Apply Brush are that case, and it is the one where a bound would
    /// be a wrong picture rather than a slow one: the footprints `restoreElements` drops are chosen by
    /// id difference, so a rewritten element keeps a measurement that is no longer true of it, and a
    /// later region edit may skip it on that measurement.
    ///
    /// Mutation that reddens it: hand `.addsAndRemoves(ink: nil)` at either of those two call sites,
    /// or make `registerVectorElementsUndo` route both cases the same way.
    func testAnElementsUndoThatRewritesInPlaceStaysAtEverything() {
        let canvas = Self.drawnCanvas(24)
        let before = canvas.elements
        // A recolour's shape: the same ids, one of them carrying different content.
        var recoloured = before
        guard case .stroke(var stroke) = recoloured[3] else {
            return XCTFail("the fixture must hold strokes")
        }
        stroke.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        recoloured[3] = .stroke(stroke)
        canvas.elements = recoloured
        canvas.bumpVersion()
        _ = canvas.render()

        let manager = manager(around: canvas)
        manager.registerVectorElementsUndo(vectorCanvas: canvas, oldElements: before,
                                           newElements: recoloured, layerID: manager.layers[0].id,
                                           celID: manager.layers[0].cels[0].id,
                                           label: .recolorSelection, swap: .rewritesInPlace)
        manager.undo()
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "a rewritten element keeps a measured footprint that is no longer true of it, "
                       + "so nothing about this swap can be bounded")
        _ = canvas.render()
        manager.redo()
        XCTAssertEqual(canvas.lastDamage, .everything, "and the same reading the other way")
    }

    /// **The measured footprints must not survive a rewrite**, which is the damage the answer above
    /// prevents rather than the declaration it makes — and it is invisible to `lastDamage`.
    ///
    /// `.everything` clears `paintedBounds` wholesale; `.region` does not. So a swap that rewrote an
    /// element in place and declared a rectangle would leave that element's old footprint standing,
    /// and the *next* region edit could skip it on a rectangle it no longer reaches. Mutation that
    /// reddens it: route `.rewritesInPlace` through `restoreElements` too.
    func testARewriteInPlaceDropsTheFootprintOfTheElementItRewrote() {
        let canvas = Self.drawnCanvas(24)
        let before = canvas.elements
        var recoloured = before
        guard case .stroke(var stroke) = recoloured[3] else {
            return XCTFail("the fixture must hold strokes")
        }
        stroke.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        recoloured[3] = .stroke(stroke)
        canvas.elements = recoloured
        canvas.bumpVersion()
        _ = canvas.render()
        XCTAssertEqual(canvas.measuredFootprintCount, canvas.elements.count,
                       "control: the walk above measured every stroke")

        let manager = manager(around: canvas)
        manager.registerVectorElementsUndo(vectorCanvas: canvas, oldElements: before,
                                           newElements: recoloured, layerID: manager.layers[0].id,
                                           celID: manager.layers[0].cels[0].id,
                                           label: .recolorSelection, swap: .rewritesInPlace)
        manager.undo()
        XCTAssertEqual(canvas.measuredFootprintCount, 0,
                       "the press left \(canvas.measuredFootprintCount) footprints standing for "
                       + "elements it may have changed — an entry is a promise, and this swap "
                       + "cannot keep it")
    }
}
