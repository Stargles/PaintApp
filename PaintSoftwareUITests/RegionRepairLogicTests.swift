import XCTest
import UIKit
import CoreGraphics

/// **A middle-of-list edit repairs the rectangle it touched instead of re-walking the cel** —
/// TODO (41), `VectorCanvas.Damage.region` and `repairableBase(quality:)`.
///
/// `IncrementalAppendLogicTests` is the sibling and the two split cleanly: an *append* draws new
/// elements over a picture of the old ones, and everything hard about it is whether cutting the
/// display list in two changes how a paint run isolates. A *repair* never cuts the list — it walks
/// every element in order and merely declines to stamp the ones whose ink cannot reach the clip.
/// So the risk is different, and so is what has to be pinned:
///
/// 1. **Byte identity, three ways**, because there are three separate ways to be wrong and no
///    single fixture sees all of them: an eraser needs the rectangle redrawn from the *bottom* of
///    the stack, a run of non-`.normal` strokes needs its isolation decided over the whole run
///    whether or not its members are stamped, and a stroke straddling the rectangle's edge needs
///    BRUSH.md §12 stage 8's group to merge at its own opacity.
/// 2. **The bound actually binds** — counted in dabs, never in milliseconds, because the claim is
///    about the algorithm and the milliseconds are the machine's.
/// 3. **A canvas-crossing edit still costs the full walk**, which is the honest half of the
///    guarantee: cost scales with the area touched, and a sweep across the canvas touches all of it.
/// 4. **A cel that cannot bound its own damage says `.everything`** and pays, rather than guessing.
///
/// **Every equivalence assertion has two operands and both come from shipped code**, in
/// `IncrementalAppendLogicTests`' idiom: one canvas that reached the state by editing and one built
/// cold from the elements it ended up with, which has no memo and therefore *cannot* take the fast
/// path. A picture the test drew itself would only pin the test's own arithmetic.
final class RegionRepairLogicTests: XCTestCase {

    // MARK: - The scene

    /// Small on purpose — the byte comparison is over every pixel and these run on the fast tier.
    /// Big enough to hold a grid whose cells are a small fraction of it, which is what makes "the
    /// bound binds" expressible at all.
    private static let canvasSize = CGSize(width: 160, height: 120)

    private static func brush(_ blend: BrushBlendMode = .normal) -> Brush {
        Brush(name: "Region", tip: .round, size: 5, dab: BrushDabSettings(spacing: 0.3),
              stroke: BrushStrokeSettings(blendMode: blend))
    }

    /// A short mark in cell `index` of an 8x6 grid.
    ///
    /// Short and spread out **on purpose**: a cut through one of these names a rectangle that is a
    /// few percent of the canvas, so a repair that failed to skip anything would be visible in the
    /// dab count. A fixture of canvas-spanning strokes would make every rectangle canvas-sized and
    /// every one of these tests pass by taking the slow path.
    private static func mark(_ index: Int, blend: BrushBlendMode = .normal,
                             opacity: Double = 1) -> VectorStroke {
        let col = index % 8, row = (index / 8) % 6
        let x = 10 + CGFloat(col) * 19, y = 10 + CGFloat(row) * 19
        let samples = StrokeSamples((0..<5).map { step -> VectorSample in
            let t = CGFloat(step) / 4
            return VectorSample(x: x + t * 12, y: y + t * 8, pressure: 0.5 + 0.5 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(blend),
                            color: CodableColor(red: Double(index % 5) / 5, green: 0.3,
                                                blue: 0.8, alpha: 1),
                            size: 5, opacity: opacity, samples: samples, composite: .paint,
                            seed: UInt64(index &+ 1))
    }

    /// The centre of cell `index`, which is where a flick aimed at that mark goes.
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

    /// A gesture from corner to corner — the case that legitimately costs a full re-walk.
    private static func sweep() -> StrokeSamples {
        StrokeSamples((0..<9).map { step -> VectorSample in
            let t = CGFloat(step) / 8
            return VectorSample(x: 6 + t * (canvasSize.width - 12),
                                y: 6 + t * (canvasSize.height - 12), pressure: 1)
        }, channels: .pressureOnly)
    }

    private static func canvas(_ n: Int, blend: BrushBlendMode = .normal,
                               opacity: Double = 1) -> VectorCanvas {
        VectorCanvas(size: canvasSize,
                     elements: (0..<n).map { .stroke(mark($0, blend: blend, opacity: opacity)) })
    }

    /// A canvas that has already drawn itself once, which is the state every artist's layer is in
    /// and the only state in which a repair is possible: the base a repair starts from *is* the
    /// standing render, and the footprints it skips on are measured by the walk that made it.
    private static func drawnCanvas(_ n: Int, blend: BrushBlendMode = .normal,
                                    opacity: Double = 1) -> VectorCanvas {
        let canvas = canvas(n, blend: blend, opacity: opacity)
        _ = canvas.render()
        return canvas
    }

    // MARK: - Comparing two renders
    //
    // `IncrementalAppendLogicTests`' helpers, and deliberately its own copies rather than shared:
    // that file's comment explains why the comparison must be of the two bitmaps' own bytes and not
    // of two images normalised through a third context, and a shared helper across two suites is
    // the sort of thing that gets "tidied" into exactly that.

    private func rawPixels(_ image: UIImage, _ label: String) -> (layout: String, bytes: Data) {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data else {
            XCTFail("\(label): no bitmap to read")
            return ("none", Data())
        }
        let layout = "\(cg.width)x\(cg.height) bpr=\(cg.bytesPerRow) bpc=\(cg.bitsPerComponent)"
            + " bpp=\(cg.bitsPerPixel) info=\(cg.bitmapInfo.rawValue) alpha=\(cg.alphaInfo.rawValue)"
        return (layout, data as Data)
    }

    /// Where two renders disagree, **in pixels rather than byte offsets**.
    ///
    /// A byte index says nothing about *where* the two arms differ, and where is the whole
    /// diagnosis: a disagreement along the repaired rectangle's edge is a seam, one in its interior
    /// is a walk that drew different elements, and one outside it is a base whose site
    /// under-declared. Working that out by hand from a byte offset cost this suite a cycle.
    private struct PixelDiff {
        var bytes = 0, worst = 0, total = 0
        var box = CGRect.null
        var samples: [String] = []
        var summary: String {
            "\(bytes) of \(total) bytes differ, worst \(worst)/255; differing pixels lie in "
                + "\(box) — \(samples.joined(separator: ", "))"
        }
    }

    private func diff(_ repaired: UIImage, _ full: UIImage, _ what: String,
                      file: StaticString, line: UInt) -> PixelDiff? {
        let a = rawPixels(repaired, "repaired")
        let b = rawPixels(full, "full re-walk")
        XCTAssertEqual(a.layout, b.layout, "\(what): the two arms produced different bitmap layouts",
                       file: file, line: line)
        guard a.bytes.count == b.bytes.count, !a.bytes.isEmpty else {
            XCTFail("\(what): byte counts differ (\(a.bytes.count) vs \(b.bytes.count))",
                    file: file, line: line)
            return nil
        }
        var d = PixelDiff()
        d.total = a.bytes.count
        if a.bytes == b.bytes { return d }
        let bpr = repaired.cgImage?.bytesPerRow ?? 0
        let bpp = max((repaired.cgImage?.bitsPerPixel ?? 32) / 8, 1)
        a.bytes.withUnsafeBytes { ra in
            b.bytes.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self), pb = rb.bindMemory(to: UInt8.self)
                for i in 0..<pa.count {
                    let delta = abs(Int(pa[i]) - Int(pb[i]))
                    guard delta > 0 else { continue }
                    d.bytes += 1
                    d.worst = max(d.worst, delta)
                    guard bpr > 0 else { continue }
                    let x = (i % bpr) / bpp, y = i / bpr
                    d.box = d.box.union(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                    if d.samples.count < 8 {
                        d.samples.append("(\(x),\(y))ch\((i % bpr) % bpp) \(pa[i])≠\(pb[i])")
                    }
                }
            }
        }
        return d
    }

    private func assertIdentical(_ repaired: UIImage, _ full: UIImage, _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let d = diff(repaired, full, what, file: file, line: line), d.bytes > 0 else { return }
        XCTFail("\(what): \(d.summary) — the repair is not the picture the walk makes",
                file: file, line: line)
    }

    /// **The one place byte identity does not hold, stated as what was measured rather than
    /// assumed.**
    ///
    /// A repair whose rectangle **truncates a transparency layer** disagrees with the full walk by
    /// one or two units out of 255, on pixels along the rectangle's edge, in both directions —
    /// MEASURED 2026-09-05 at four bytes of 76,800 with an eraser's group cut by the rectangle, and
    /// at fifty-two with a `.multiply` run's isolation layer cut by it. CoreGraphics composites a
    /// transparency layer through a buffer sized by the clip in force, and a layer given a smaller
    /// buffer does not round identically.
    ///
    /// **It is rounding at the clip, not a walk that drew the wrong thing**, and three experiments
    /// say so. Disabling the skip test entirely reproduces the eraser fixture's four bytes *to the
    /// value*, so it is not an element wrongly left out. Shortening the punch until its group no
    /// longer straddles the rectangle moves the bytes rather than removing them. And a walk with no
    /// transparency layer in it at all is byte-exact — the seven tests that use `assertIdentical`,
    /// including a `.normal` stroke straddling the same edge at opacity 0.55, whose own per-stroke
    /// group merges source-over.
    ///
    /// So the guarantee this suite pins is: **identical everywhere, except at most a rounding unit
    /// inside the rectangle, on no more pixels than its boundary has.** Each of those three is
    /// falsifiable and each failure is a different real defect — a bigger delta is a wrong picture,
    /// a difference outside the rectangle is a base whose site under-declared, and a count that
    /// scales with the rectangle's *area* rather than its perimeter is a region drawn differently
    /// rather than a seam.
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
                      + "is a base the site under-declared, not a seam", file: file, line: line)
        // A seam is a **perimeter**; a region drawn differently is an area. Four channels on every
        // boundary pixel is the generous form of that, and it is what separates the two.
        let perimeter = 4 * Int(2 * (region.width + region.height))
        XCTAssertLessThanOrEqual(d.bytes, perimeter,
                                 "\(what): \(d.summary) — more bytes than the rectangle has boundary "
                                 + "pixels (\(perimeter)) is an area, not a seam", file: file, line: line)
    }

    private func differs(_ a: UIImage, _ b: UIImage) -> Bool {
        rawPixels(a, "a").bytes != rawPixels(b, "b").bytes
    }

    /// The full re-walk of `canvas`'s display list, guaranteed cold: a freshly constructed canvas
    /// has no memo, no base and no measured footprints, so it cannot take any fast path.
    private func fullReWalk(of canvas: VectorCanvas) -> (image: UIImage, dabs: Int) {
        let cold = VectorCanvas(size: canvas.size, elements: canvas.elements)
        let image = cold.render()
        XCTAssertEqual(cold.rasterizations, 1, "the reference arm must have rasterized exactly once")
        XCTAssertEqual(cold.regionRepairs, 0, "the reference arm must not have repaired anything")
        return (image, cold.lastRenderDabCount)
    }

    /// The declared rectangle as a fraction of the canvas, for the tests that are about *how much*
    /// was declared rather than about what was drawn.
    private func regionFraction(_ canvas: VectorCanvas) -> Double {
        let region = canvas.lastRepairedRegion
        guard !region.isNull else { return 1 }
        return Double(region.width * region.height)
            / Double(Self.canvasSize.width * Self.canvasSize.height)
    }

    private func isRegion(_ damage: VectorCanvas.Damage) -> Bool {
        if case .region = damage { return true }
        return false
    }

    // MARK: - (1) What a cut declares

    /// **The two eraser cuts declare a rectangle now, and only when they can measure one.**
    ///
    /// The second half is the load-bearing one and it is not a technicality: a rectangle is derived
    /// from what the strokes being replaced last *painted*, and a cel that has never rendered has
    /// painted nothing, so there is nothing to derive it from. `Damage`'s own rule — a mutation that
    /// is not certain what it changed says `.everything` — is what that case falls back to.
    func testACutDeclaresARectangleOnlyWhenItCanMeasureOne() {
        let neverDrawn = Self.canvas(12)
        XCTAssertTrue(neverDrawn.erase(alongPath: Self.flick(over: 0), brush: Self.brush(),
                                       size: 14, opacity: 1, mode: .cutPoints))
        XCTAssertEqual(neverDrawn.lastDamage, .everything,
                       "a cel with no measured footprints cannot bound its own damage")

        let drawn = Self.drawnCanvas(12)
        XCTAssertTrue(drawn.erase(alongPath: Self.flick(over: 0), brush: Self.brush(),
                                  size: 14, opacity: 1, mode: .cutPoints))
        XCTAssertTrue(isRegion(drawn.lastDamage),
                      "Mode 2 replaces strokes in place and knows where they were")

        let toCross = Self.drawnCanvas(12)
        let cut = toCross.cutToIntersection(atCanvasPoint: Self.cellCentre(0),
                                            brush: Self.brush(), size: 14)
        XCTAssertEqual(cut.outcome, .cut, "the fixture must actually cut something")
        XCTAssertTrue(isRegion(toCross.lastDamage),
                      "Mode 3 — the owner's *To Cross* eraser — is the one that pays this per touch sample")
    }

    // MARK: - (2) Byte identity, three ways

    /// **The headline pin, on the ordinary cut.**
    func testACutRepairedInPlaceIsByteIdenticalToTheFullWalk() {
        let canvas = Self.drawnCanvas(48)
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 1, "the repair must have run, or this pins nothing")
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0,
                       "an abandoned repair costs both walks and would hide a bad bound behind a good picture")
        assertIdentical(repaired, fullReWalk(of: canvas).image, "a Mode 2 cut, repaired in place")
    }

    /// **Constraint one: inside the rectangle the redraw starts at the bottom of the stack.**
    ///
    /// An `.erase` element composites `destinationOut` against everything accumulated beneath it, so
    /// a repair that started at the edited element would punch against an empty rectangle and leave
    /// the ink *under* the punch standing.
    ///
    /// **The operand check is taken after the cut, and that is the whole of what this test is.** It
    /// was written against the *uncut* list and was green with the eraser skipped entirely from
    /// every clipped walk — MEASURED by mutation, and the reason is the fixture rather than the
    /// code. `cutAlongFootprint` leaves `.erase` elements alone but deletes every `.paint` stroke
    /// its footprint covers, and the marks it covered were shorter than the nib: after the cut
    /// there was no ink left in the cell for the punch to remove, so the arm that skipped it and
    /// the arm that drew it agreed. A setup assertion on the state *before* the mutation under test
    /// is not an operand check — it is the fixture measuring itself.
    ///
    /// So the ink here is two **bars** long enough that the flick cuts their middles and leaves
    /// pieces standing at both ends, inside the rectangle the cut declares; and the punch runs the
    /// bars' whole length, so those surviving pieces are exactly what it eats.
    func testACutUnderAnEraserRedrawsTheRectangleFromTheBottomOfTheStack() {
        let cell = 27
        let centre = Self.cellCentre(cell)
        var elements: [VectorElement] = (0..<48).map { .stroke(Self.mark($0)) }
        // Two bars through the target cell, far longer than the nib that cuts them.
        for offset in 0..<2 {
            var extra = Self.mark(cell + 100 + offset)
            extra.samples = StrokeSamples((0..<24).map { step -> VectorSample in
                let t = CGFloat(step) / 23
                return VectorSample(x: centre.x - 34 + t * 68,
                                    y: centre.y - 2 + CGFloat(offset) * 4, pressure: 1)
            }, channels: .pressureOnly)
            elements.append(.stroke(extra))
        }
        var punch = Self.mark(999)
        punch.composite = .erase
        punch.size = 9
        punch.samples = StrokeSamples((0..<24).map { step -> VectorSample in
            let t = CGFloat(step) / 23
            return VectorSample(x: centre.x - 25 + t * 50, y: centre.y, pressure: 1)
        }, channels: .pressureOnly)
        elements.append(.stroke(punch))

        let canvas = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = canvas.render()
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: cell), brush: Self.brush(),
                                   size: 12, opacity: 1, mode: .cutPoints))

        // **The operand check, on the list the repair is about to draw.** Two cold canvases over
        // the post-cut elements, one of them with the punch removed: if they agree, the punch has
        // nothing left to remove and the byte comparison below has no subject.
        let survived = canvas.elements
        let withoutPunch = VectorCanvas(size: Self.canvasSize,
                                        elements: survived.filter { $0.stroke?.composite != .erase })
        let withPunch = VectorCanvas(size: Self.canvasSize, elements: survived)
        XCTAssertTrue(differs(withoutPunch.render(), withPunch.render()),
                      "setup: after the cut the eraser must still remove pixels, or this test has no subject")

        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 1)
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0)
        XCTAssertLessThan(regionFraction(canvas), 0.5,
                          "setup: the rectangle must be a fraction of the canvas, or nothing is skipped")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a cut inside a rectangle an `.erase` element punches")
    }

    /// **Constraint two: a run of non-`.normal` strokes is isolated as a whole.**
    ///
    /// The run spans the canvas and the rectangle does not, so a repair sees a run most of whose
    /// members it will not stamp. If the run scan were narrowed to the stamped elements the run
    /// would be split, and a split run composites differently — that is the same non-associativity
    /// `appendPreservesTheWalk` exists for, met from the other side.
    ///
    /// **Two things the fixture must have, and the first version had neither.** Rule 2 isolates a
    /// run so its strokes "blend against each other but not what's beneath them", so a run with
    /// *nothing beneath it* and *no overlaps within it* composites the same isolated or not — and a
    /// canvas of 48 spread-out `.multiply` marks is exactly that. MEASURED: it was green with the
    /// transparency layer removed from every clipped walk. So there is a fill underneath now, and
    /// two short bars that cross each other inside the repaired rectangle without being cut by the
    /// nib that declares it.
    func testABlendModeRunStraddlingTheRectangleIsByteIdentical() {
        let page = CGRect(origin: .zero, size: Self.canvasSize)
        // The backdrop the run is isolated *from*. A fill is the cheapest one that is not itself a
        // stroke, so it cannot join the run it sits under (rule 1).
        var elements: [VectorElement] = [
            .fill(VectorFillElement(path: CGPath(rect: page, transform: nil),
                                    color: CodableColor(red: 0.92, green: 0.86, blue: 0.35, alpha: 1)))
        ]
        elements += (0..<48).map { .stroke(Self.mark($0, blend: .multiply)) }
        // A long bar through cell 11, which is what the flick cuts — so the rectangle is this bar's
        // footprint: long, thin, and a few percent of the canvas.
        var bar = Self.mark(400, blend: .multiply)
        bar.size = 8
        bar.samples = StrokeSamples((0..<32).map { step -> VectorSample in
            let t = CGFloat(step) / 31
            return VectorSample(x: 8 + t * (Self.canvasSize.width - 16), y: 33, pressure: 1)
        }, channels: .pressureOnly)
        elements.append(.stroke(bar))
        // Two more members of the same run, crossing **each other** inside that rectangle and far
        // enough along it that the nib does not reach them. Without these the run has no internal
        // overlap and isolating it changes nothing.
        for flip in 0..<2 {
            var cross = Self.mark(401 + flip, blend: .multiply)
            cross.size = 8
            cross.samples = StrokeSamples((0..<12).map { step -> VectorSample in
                let t = CGFloat(step) / 11
                return VectorSample(x: 110 + t * 22,
                                    y: flip == 0 ? 29 + t * 8 : 37 - t * 8, pressure: 1)
            }, channels: .pressureOnly)
            elements.append(.stroke(cross))
        }

        let canvas = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = canvas.render()
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 11), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 1)
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0)
        XCTAssertLessThan(regionFraction(canvas), 0.5,
                          "setup: the rectangle must be smaller than the run, or nothing straddles it")
        // The crossing pair has to be *inside* the rectangle, or the overlap the isolation is about
        // is never redrawn and this fixture is the blind one again.
        XCTAssertTrue(canvas.lastRepairedRegion.contains(CGPoint(x: 121, y: 33)),
                      "setup: the run's internal overlap must fall inside the repaired rectangle")
        assertMatchesToWithinARoundingUnit(repaired, fullReWalk(of: canvas).image,
                                           inside: canvas.lastRepairedRegion,
                                           "a cut inside a `.multiply` run that reaches past the rectangle")
    }

    /// **Constraint three: a stroke crossing the rectangle's edge merges at its own opacity.**
    ///
    /// BRUSH.md §12 stage 8 gave every stroke its own transparency layer, clipped to the union of
    /// the rectangles its dabs painted and merged once at the stroke's opacity. A stroke that
    /// straddles the repair's clip has part of that group inside and part outside; if the merge
    /// picked up the clip wrongly the straddling stroke would come out at a different alpha on one
    /// side of the seam.
    ///
    /// Opacity is 0.55 and the marks self-overlap, so the group is doing visible work: at opacity 1
    /// a group merges to the same pixels as ungrouped dabs and this fixture would be blind.
    func testAStrokeCrossingTheRectanglesEdgeMergesAtItsOwnOpacity() {
        var elements: [VectorElement] = (0..<48).map { .stroke(Self.mark($0, opacity: 0.55)) }
        // One long, self-crossing stroke laid across the whole canvas, so it necessarily straddles
        // whatever rectangle a single-cell cut declares.
        var straddler = Self.mark(500, opacity: 0.55)
        straddler.size = 9
        straddler.samples = StrokeSamples((0..<40).map { step -> VectorSample in
            let t = CGFloat(step) / 39
            return VectorSample(x: 8 + t * (Self.canvasSize.width - 16),
                                y: 60 + sin(t * .pi * 3) * 34, pressure: 0.6 + 0.4 * t)
        }, channels: .pressureOnly)
        elements.append(.stroke(straddler))

        let canvas = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = canvas.render()
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 3), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        let repaired = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 1)
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0)
        XCTAssertLessThan(regionFraction(canvas), 0.5,
                          "setup: the rectangle must not swallow the straddling stroke")
        assertIdentical(repaired, fullReWalk(of: canvas).image,
                        "a stroke crossing the repaired rectangle's edge")
    }

    /// **The owner's own gesture**: *"when I draw a bunch of brushstrokes and then use the cross
    /// eraser on them, I get a lagspike."* *To Cross* is `VectorEraserMode.cutToIntersection`, and
    /// it resolves and invalidates **once per touch sample**, so it pays whatever a cut costs
    /// forty times in one drag. Ten samples here, each one repaired, each one still the picture the
    /// walk makes.
    func testAToCrossDragRepairsEverySampleAndStaysByteIdentical() {
        let canvas = Self.drawnCanvas(48)
        var driver = VectorEraser.IntersectionDriver()
        var cuts = 0
        for step in 0..<10 {
            let t = CGFloat(step) / 9
            let point = CGPoint(x: 16 + t * (Self.canvasSize.width - 32),
                                y: 16 + t * (Self.canvasSize.height - 32))
            let resolved = canvas.cutToIntersection(atCanvasPoint: point, brush: Self.brush(),
                                                    size: 12, suppressing: driver.suppressed)
            driver.accept(resolved.outcome, underTip: resolved.underTip)
            if resolved.outcome == .cut { cuts += 1 }
            _ = canvas.render()
        }
        XCTAssertGreaterThan(cuts, 2, "setup: the drag must actually cut, or this pins nothing")
        XCTAssertGreaterThan(canvas.regionRepairs, 2,
                             "every cutting sample should have repaired rather than re-walked")
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0)
        assertIdentical(canvas.render(), fullReWalk(of: canvas).image, "a whole To Cross drag")
    }

    // MARK: - (3) The bound binds

    /// **Counted in dabs, never in wall clock.** "Cost scales with the area touched" is a claim
    /// about the algorithm; a timing assertion on a shared machine would be noise, and would pass
    /// on a fast day against a repair that skipped nothing.
    ///
    /// The two operands are the repair's own `lastRenderDabCount` and a cold canvas's, over the
    /// *same* display list — so the ratio is exactly what the bound bought.
    func testASmallCutStampsFarFewerDabsThanTheFullWalk() {
        // **A long bar rather than one of the grid marks, and the reason is a measurement.** A 14 pt
        // mark under any usable nib is covered end to end, so `cutAlongFootprint` deletes it whole
        // and the repair stamps **0 dabs** — the cheapest possible outcome, and a fixture that
        // cannot tell a working bound from a walk that drew nothing at all. A 64 pt bar cut through
        // the middle leaves two pieces, which is the case worth counting.
        var elements: [VectorElement] = (0..<48).map { .stroke(Self.mark($0)) }
        var bar = Self.mark(800)
        bar.samples = StrokeSamples((0..<24).map { step -> VectorSample in
            let t = CGFloat(step) / 23
            return VectorSample(x: 48 + t * 64, y: 100, pressure: 1)
        }, channels: .pressureOnly)
        elements.append(.stroke(bar))
        let canvas = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = canvas.render()

        let nib = StrokeSamples([VectorSample(x: 80, y: 100, pressure: 1),
                                 VectorSample(x: 80, y: 101, pressure: 1)], channels: .pressureOnly)
        XCTAssertTrue(canvas.erase(alongPath: nib, brush: Self.brush(),
                                   size: 6, opacity: 1, mode: .cutPoints))
        _ = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 1, "the repair must have run, or the count below is a full walk")
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0)
        let repairDabs = canvas.lastRenderDabCount
        let full = fullReWalk(of: canvas)
        XCTAssertGreaterThan(repairDabs, 0, "the fixture must leave pieces to re-stamp")
        XCTAssertLessThan(repairDabs, full.dabs / 3,
                          "the repair stamped \(repairDabs) of the layer's \(full.dabs) dabs — "
                          + "a bound that does not bind is machinery with no consumer")
        XCTAssertLessThan(regionFraction(canvas), 0.2,
                          "and the rectangle it bound to is a fraction of the canvas")
    }

    // MARK: - (4) The honest half: a canvas-crossing edit costs the full walk

    /// **And is correct, which is the half that matters.** A gesture from corner to corner unions
    /// the footprints of every stroke it cuts into a rectangle the size of the canvas, and
    /// `repairClip` refuses it: a clip that rejects nothing is a full walk with extra bookkeeping.
    /// TODO (41) says this in so many words — the guarantee is that cost scales with the area
    /// touched, not that it is always small.
    func testACutAcrossTheWholeCanvasFallsBackToTheFullWalk() {
        // **A corner-to-corner sweep across the grid is not enough**, and finding that out is worth
        // more than the assertion was: the union of forty-eight inset marks' footprints comes to
        // about 80% of the canvas, which `repairClip` accepts. It is a bad deal rather than a wrong
        // one — a repair at that size skips almost nothing and pays one extra canvas-sized blit,
        // MEASURED at ~1.5 ms on the owner's iPad against a full walk of hundreds
        // (PERFORMANCE.md §11.9) — so the rule stays "smaller than the canvas" with no threshold to
        // tune. What genuinely covers the canvas is a stroke that runs off its edges, which is an
        // ordinary thing for an artist to draw.
        var elements: [VectorElement] = (0..<48).map { .stroke(Self.mark($0)) }
        var overrun = Self.mark(600)
        overrun.size = 10
        overrun.samples = StrokeSamples((0..<24).map { step -> VectorSample in
            let t = CGFloat(step) / 23
            return VectorSample(x: -8 + t * (Self.canvasSize.width + 16),
                                y: -8 + t * (Self.canvasSize.height + 16), pressure: 1)
        }, channels: .pressureOnly)
        elements.append(.stroke(overrun))
        let canvas = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = canvas.render()

        XCTAssertTrue(canvas.erase(alongPath: Self.sweep(), brush: Self.brush(),
                                   size: 16, opacity: 1, mode: .cutPoints))
        let drawn = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 0,
                       "a canvas-sized rectangle must take the slow path outright, not through a clip")
        let full = fullReWalk(of: canvas)
        assertIdentical(drawn, full.image, "a cut across the whole canvas")
        XCTAssertEqual(canvas.lastRenderDabCount, full.dabs,
                       "and it stamped the whole layer, which is what falling back means")
    }

    // MARK: - (5) The conditions the repair shares with the append

    /// A moved or partly-hidden cel falls back, for `appendableBase`'s two reasons: the overall
    /// transform is applied by resampling the finished content, and a resample of a repair is not a
    /// repair of a resample; and a suppressed element is not in the picture the base holds.
    func testATransformedOrSuppressedCelFallsBackToTheFullWalk() {
        let moved = Self.drawnCanvas(24)
        moved.setTransform(CGAffineTransform(translationX: 5, y: 3))
        _ = moved.render()
        XCTAssertTrue(moved.erase(alongPath: Self.flick(over: 9), brush: Self.brush(),
                                  size: 14, opacity: 1, mode: .cutPoints))
        _ = moved.render()
        XCTAssertEqual(moved.regionRepairs, 0, "a transformed cel cannot repair in place")

        let hidden = Self.drawnCanvas(24)
        hidden.suppressedElementIDs = [hidden.elements[0].id]
        _ = hidden.render()
        XCTAssertTrue(hidden.erase(alongPath: Self.flick(over: 9), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        _ = hidden.render()
        XCTAssertEqual(hidden.regionRepairs, 0, "a cel with something suppressed cannot repair in place")
    }

    /// **A repaired cel still appends incrementally**, which is the check that the two bases have
    /// not started fighting over the same memo: a cut, a repair, then a new stroke that must stamp
    /// only its own dabs and land on the picture the walk would make.
    func testAnAppendAfterARepairIsStillIncrementalAndStillByteIdentical() {
        let canvas = Self.drawnCanvas(48)
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 19), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        _ = canvas.render()

        let added = Self.mark(700)
        let solo = VectorCanvas(size: Self.canvasSize, elements: [.stroke(added)])
        _ = solo.render()
        let soloDabs = solo.lastRenderDabCount

        canvas.addStroke(added)
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1))
        let appended = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, soloDabs,
                       "the append after a repair must still stamp only the new stroke's dabs")
        assertIdentical(appended, fullReWalk(of: canvas).image, "an append onto a repaired cel")
    }

    /// **Undo clears the measured footprints, and it has to.** A wholesale `elements =` can put
    /// different content under an id that already has an entry, and an entry is a promise that the
    /// element has not changed — so a stale one would let a *changed* element be skipped, which is
    /// the one way this design draws a wrong picture rather than a slow one.
    func testAWholesaleReplacementDropsTheMeasuredFootprints() {
        let canvas = Self.drawnCanvas(24)
        let snapshot = canvas.elements
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 9), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        _ = canvas.render()

        canvas.elements = snapshot
        canvas.bumpVersion()
        XCTAssertEqual(canvas.lastDamage, .everything)
        let restored = canvas.render()
        XCTAssertEqual(canvas.regionRepairs, 1, "the restore must not have repaired anything")
        assertIdentical(restored, fullReWalk(of: canvas).image, "the cel restored by undo")

        // And the next cut cannot use anything the walk before the restore measured.
        XCTAssertTrue(canvas.erase(alongPath: Self.flick(over: 9), brush: Self.brush(),
                                   size: 14, opacity: 1, mode: .cutPoints))
        _ = canvas.render()
        XCTAssertEqual(canvas.regionRepairsAbandoned, 0)
        assertIdentical(canvas.render(), fullReWalk(of: canvas).image, "a cut after an undo")
    }
}
