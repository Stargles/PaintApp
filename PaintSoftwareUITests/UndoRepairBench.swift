import XCTest
import UIKit

/// **What undoing an eraser cut costs, before and after it was given a rectangle.**
///
/// The owner: *"erasing in a vector layer with a lot of strokes is relatively good, but undo and redo
/// causes some lag."* PERFORMANCE.md §11.10 is why the cut is "relatively good": Modes 2 and 3 both
/// declare `VectorCanvas.Damage.region` now, so `repairableBase(quality:)` repairs only the rectangle
/// the cut touched instead of walking the whole display list. **Undo does not share that path.**
/// `StrokeCanvasView.registerVectorUndo` and `CanvasManager.registerVectorElementsUndo` both restore a
/// whole `elements` snapshot and call `VectorCanvas.bumpVersion()`, which declares `.everything` —
/// the one damage case `applyToRegionBase` cannot narrow, because a wholesale assignment can reuse an
/// id for content that is not the id's old content, so no measured footprint can be trusted (see the
/// comment on `applyToRegionBase`'s `.everything` case). So every undo of a cut, and every redo of one,
/// re-walked and re-stamped the entire cel — the cost the cut itself just avoided. That is the
/// **before** arm here, kept verbatim, and `VectorCanvas.restoreElements(_:changedInk:)` is the
/// **after** one: a wholesale list swap that declares the tightest damage it can prove, which is the
/// vacated ink it measures itself unioned with the rectangle the forward edit declared.
///
/// This is a measurement harness, not a regression suite, and it answers one question: **how much of
/// that gap closed**, in wall clock and in dabs, at the stroke counts PERFORMANCE.md §11.10 already
/// measured the cut at. **Both arms run in one process on one canvas**, alternating, so a busy
/// machine costs them equally — this file's own numbers are otherwise two measurements taken at two
/// times, which CLAUDE.md records as the trap that made a 28.5-minute suite look like a regression.
///
/// **Fixture is `StrokeDensityBench`'s, copied verbatim** — same canvas, same stroke shape, same RNG,
/// same four stroke counts as `testWhereACrossEraserDragSpendsItsTime` (PERFORMANCE.md §11.10) — so a
/// row here is directly comparable to that table's `dabs before`/`render before` columns rather than a
/// new, incompatible curve.
///
/// It is deliberately *not* named `…LogicTests`, so CLAUDE.md's fast-tier selector
/// (`LogicTests$|CharacterizationTests$|^PerfBaselineTests$`) does not pick it up. Run it by name:
/// ```
/// PAINTAPP_BENCH=1 xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
///   -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/UndoRepairBench -parallel-testing-enabled NO
/// ```
/// Note the plain (un-prefixed) `PAINTAPP_BENCH`: `xcodebuild` itself reads it to decide whether to
/// forward `TEST_RUNNER_PAINTAPP_BENCH` to the runner process — see `run.sh`/CI, or just set both if
/// unsure. `setUpWithError` below skips every test, reporting `** TEST SUCCEEDED **` with all-skipped,
/// if neither made it to the device — CLAUDE.md's banner-versus-count trap in this file's own clothes.
final class UndoRepairBench: XCTestCase {

    /// Opt-in for the same reason `StrokeDensityBench` is: this renders full 2,000-stroke cels
    /// repeatedly and is minutes of wall clock, not something the fast tier should ever see.
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "UndoRepairBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
    }

    // MARK: - The scene — `StrokeDensityBench`'s fixture, copied verbatim for comparability

    /// The owner's canvas (PERFORMANCE.md §1).
    private static let canvasSize = CGSize(width: 2048, height: 1024)

    /// A realistic line-art stroke: a gentle arc ~400 pt long, sampled 40 times. Identical to
    /// `StrokeDensityBench.benchStroke(_:canvas:composite:)` — same RNG, same constants — so the two
    /// files build byte-identical scenes at the same `n`.
    private static let strokeLengthPoints: CGFloat = 400
    private static let samplesPerStroke = 40
    private static let brushSize: CGFloat = 18
    private static let benchBrush = Brush(name: "Bench", tip: .round, size: brushSize)

    private static func benchStroke(_ index: Int, canvas: CGSize = canvasSize,
                                    composite: StrokeComposite = .paint) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 48
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length = strokeLengthPoints
        var ux = cos(angle), uy = sin(angle)
        if x0 + ux * length < inset || x0 + ux * length > canvas.width - inset { ux = -ux }
        if y0 + uy * length < inset || y0 + uy * length > canvas.height - inset { uy = -uy }
        var samples = StrokeSamples(channels: .pressureOnly)
        samples.reserveCapacity(samplesPerStroke)
        for step in 0..<samplesPerStroke {
            let t = CGFloat(step) / CGFloat(samplesPerStroke - 1)
            let bend = sin(t * .pi) * length * 0.16
            let dx = ux * t * length - uy * bend
            let dy = uy * t * length + ux * bend
            samples.append(VectorSample(x: x0 + dx, y: y0 + dy,
                                        pressure: 0.25 + 0.75 * sin(t * .pi)))
        }
        return VectorStroke(brush: benchBrush,
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: brushSize, opacity: 1, samples: samples, composite: composite)
    }

    private static func scene(_ n: Int) -> [VectorStroke] { (0..<n).map { benchStroke($0) } }

    /// The stroke counts `testWhereACrossEraserDragSpendsItsTime` uses (PERFORMANCE.md §11.10,
    /// commit `05db81c`), so this bench's rows line up with that table's.
    private static let strokeCounts = [200, 500, 1000, 2000]

    // MARK: - The eraser — also copied verbatim from `StrokeDensityBench`

    /// Mode 3's footprint is a selection radius fixed at the brush size — `cutToIntersection` takes no
    /// pressure — so this is the whole of the nib, matching §11.10.
    private static let eraserSize: CGFloat = 40
    private static let eraserBrush = Brush(name: "BenchEraser", tip: .round, size: eraserSize)

    // MARK: - Measurement plumbing (`StrokeDensityBench`'s, verbatim)

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "UNDO BENCH | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "UNDO BENCH — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.2f ms", seconds * 1000) }

    /// Median of `runs` timings of `body`, matching `StrokeDensityBench`'s own idiom — a figure taken
    /// beside three other agents' work should be quoted at the median, not the mean.
    private func medianSeconds(runs: Int, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            autoreleasepool {
                let start = CFAbsoluteTimeGetCurrent()
                body()
                samples.append(CFAbsoluteTimeGetCurrent() - start)
            }
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// **Undo and redo timed alternately, the way an artist presses them**, each returning the dabs
    /// its render stamped.
    ///
    /// `medianSeconds` running one restore three times over is right for `bumpVersion()` — it
    /// declares `.everything` whatever the list already holds, so all three runs are the same full
    /// walk — and **wrong for the region path**, where the second of two identical restores finds
    /// nothing arriving and nothing departing and has nothing to declare. Alternating makes every
    /// timed step a real transition, and it is what the artist does anyway.
    ///
    /// The canvas must be holding the *post-edit* list when this is called, so the first timed step
    /// is a genuine undo.
    private func alternatingUndoRedo(runs: Int, undo: () -> Int, redo: () -> Int)
    -> (undoSeconds: Double, redoSeconds: Double, undoDabs: Int, redoDabs: Int) {
        var undoSamples: [Double] = [], redoSamples: [Double] = []
        var undoDabs = 0, redoDabs = 0
        for _ in 0..<runs {
            autoreleasepool {
                var start = CFAbsoluteTimeGetCurrent()
                undoDabs = undo()
                undoSamples.append(CFAbsoluteTimeGetCurrent() - start)
                start = CFAbsoluteTimeGetCurrent()
                redoDabs = redo()
                redoSamples.append(CFAbsoluteTimeGetCurrent() - start)
            }
        }
        undoSamples.sort(); redoSamples.sort()
        return (undoSamples[runs / 2], redoSamples[runs / 2], undoDabs, redoDabs)
    }

    /// What fraction of the canvas the last repair actually clipped to — §11.10's "rectangle" column.
    private func rectangleShare(_ canvas: VectorCanvas) -> String {
        let region = canvas.lastRepairedRegion
        guard !region.isNull, !region.isInfinite else { return "n/a" }
        let share = (region.width * region.height)
            / (Self.canvasSize.width * Self.canvasSize.height)
        return String(format: "%.1f%%", share * 100)
    }

    // MARK: - Mode 2 (Cut) — one commit, one region repair, then undo and redo of it

    /// **The ordinary edit** — PERFORMANCE.md §11.10 calls this exact fixture "a short flick through
    /// one or two lines… the honest common case", as against the canvas-spanning sweep that forces a
    /// full walk on its own. `cutAlongFootprint` (mode `.cutPoints`) declares `.region`, so the cut and
    /// its render are cheap; `elements = before; bumpVersion()` was not, because `bumpVersion()`
    /// always declares `.everything`. Both are measured below on the same canvas.
    func testUndoAndRedoAfterAModeTwoCut() {
        // Warm the allocator so the first row is not charged a first-touch fault.
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.strokeCounts {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                // Render once so `paintedBounds` is populated — a cold cel has no measured footprints
                // and every edit would fall back to `.everything` regardless of what it declares, which
                // would measure the cold-cel case instead of the one the owner reported.
                _ = canvas.render()
                let wholeLayerDabs = canvas.lastRenderDabCount

                let before = canvas.elements

                // The short flick through the canvas centre — `StrokeDensityBench`'s "cut (Mode 2)
                // short flick" fixture, verbatim.
                var samples = StrokeSamples(channels: .pressureOnly)
                let mid = CGPoint(x: Self.canvasSize.width * 0.5, y: Self.canvasSize.height * 0.5)
                for step in 0...6 {
                    let t = CGFloat(step) / 6
                    samples.append(VectorSample(x: mid.x - 30 + t * 60, y: mid.y - 30 + t * 60,
                                                pressure: 1))
                }
                let cutStart = CFAbsoluteTimeGetCurrent()
                let changed = canvas.erase(alongPath: samples, brush: Self.eraserBrush,
                                           size: Self.eraserSize, mode: .cutPoints)
                // What the cut declared, read before the render so nothing can have invalidated in
                // between. This is exactly what `StrokeCanvasView.foldGestureDamage` accumulates and
                // hands to both closures: Mode 2 commits once, so the gesture's union is this one
                // rectangle.
                let cutDamage = canvas.lastDamage
                _ = canvas.render()
                let cutSeconds = CFAbsoluteTimeGetCurrent() - cutStart
                let cutDabs = canvas.lastRenderDabCount
                let cutRegionRepairs = canvas.regionRepairs
                XCTAssertTrue(changed, "the flick at n=\(n) must actually cut something")
                XCTAssertGreaterThan(cutRegionRepairs, 0,
                                     "the cut at n=\(n) must take the region-repair path, or this is "
                                     + "not measuring the gap the owner reported")

                let after = canvas.elements
                guard case .region(let cutRegion) = cutDamage else {
                    XCTFail("the Mode 2 cut at n=\(n) must declare a rectangle, or the after arm "
                            + "has nothing to carry back")
                    return
                }

                let old = measureBumpVersionArm(canvas, before: before, after: after)
                let new = measureRestoreElementsArm(canvas, before: before, after: after,
                                                    changedInk: cutRegion)

                report("Mode 2 cut + undo + redo — n=\(n)", [
                    ("strokes", "\(n)"),
                    ("wholeLayerDabs", "\(wholeLayerDabs)"),
                    ("cutOnce", ms(cutSeconds)),
                    ("cutDabs", "\(cutDabs)"),
                    ("cutRegionRepairs", "\(cutRegionRepairs)"),
                    ("undoBefore", ms(old.undoSeconds)),
                    ("undoDabsBefore", "\(old.undoDabs)"),
                    ("redoBefore", ms(old.redoSeconds)),
                    ("redoDabsBefore", "\(old.redoDabs)"),
                    ("undoAfter", ms(new.undoSeconds)),
                    ("undoDabsAfter", "\(new.undoDabs)"),
                    ("redoAfter", ms(new.redoSeconds)),
                    ("redoDabsAfter", "\(new.redoDabs)"),
                    ("rectangle", new.rectangle),
                    ("repairsWidened", "\(new.widened)"),
                    ("repairsAbandoned", "\(new.abandoned)"),
                    ("undoSpeedup", String(format: "%.1fx",
                                           old.undoSeconds / max(new.undoSeconds, 1e-9))),
                    ("undoVsCutAfter", String(format: "%.1fx",
                                              new.undoSeconds / max(cutSeconds, 1e-9))),
                ])

                // The before arm is the shipped `.everything` path: it re-stamps the whole restored
                // list, which is the cost the cut itself had just avoided.
                XCTAssertEqual(Double(old.undoDabs), Double(wholeLayerDabs), accuracy: 1,
                              "the before arm at n=\(n) must re-stamp the pre-cut list in full")
                XCTAssertEqual(old.repairs, 0,
                               "the before arm at n=\(n) must not take the region-repair path at all")
                // The after arm must actually repair — six presses, six repairs — and must stamp
                // fewer dabs for it. `regionRepairsAbandoned` is the operand that says the rectangle
                // bound rather than merely ran.
                XCTAssertEqual(new.repairs, 6,
                               "the after arm at n=\(n) is three undo/redo pairs and every one of "
                               + "them must have repaired a rectangle")
                XCTAssertEqual(new.abandoned, 0,
                               "an abandoned repair at n=\(n) pays both walks and hides a bad bound")
                XCTAssertLessThan(new.undoDabs, old.undoDabs,
                                  "the after arm at n=\(n) stamped \(new.undoDabs) dabs against the "
                                  + "before arm's \(old.undoDabs) — the bound is not binding")
            }
        }
    }

    // MARK: - The two arms

    /// **Before** — `elements = snapshot` plus `bumpVersion()`, which is what
    /// `StrokeCanvasView.registerVectorUndo` and `CanvasManager.registerVectorElementsUndo` both did.
    /// `bumpVersion()` declares `.everything`, so each press drops the memo, the region base *and*
    /// every measured footprint, and the render walks the cel whole.
    ///
    /// Leaves the canvas holding `after`, which is the state the after arm needs to start from.
    private func measureBumpVersionArm(_ canvas: VectorCanvas,
                                       before: [VectorElement], after: [VectorElement])
    -> (undoSeconds: Double, redoSeconds: Double, undoDabs: Int, redoDabs: Int, repairs: Int) {
        canvas.elements = after
        canvas.bumpVersion()
        _ = canvas.render()
        let repairsBefore = canvas.regionRepairs
        let timed = alternatingUndoRedo(runs: 3, undo: {
            canvas.elements = before
            canvas.bumpVersion()
            _ = canvas.render()
            return canvas.lastRenderDabCount
        }, redo: {
            canvas.elements = after
            canvas.bumpVersion()
            _ = canvas.render()
            return canvas.lastRenderDabCount
        })
        return (timed.undoSeconds, timed.redoSeconds, timed.undoDabs, timed.redoDabs,
                canvas.regionRepairs - repairsBefore)
    }

    /// **After** — `restoreElements(_:changedInk:)`, the seam this session added, with the rectangle
    /// the cut itself declared. One rectangle serves both directions because it bounds every pixel
    /// where the two lists differ, and that reads the same way forwards and backwards.
    ///
    /// The full render up front is not ceremony: the before arm's last `bumpVersion()` declared
    /// `.everything`, which clears `paintedBounds` outright, and without measured footprints a
    /// restore has nothing to derive its vacated half from. One walk puts the canvas back in the
    /// state an artist's is actually in — the cut drawn and its ink measured.
    ///
    /// **`changedInk` is optional here because the case that matters most does not have one.** A
    /// drawn stroke's gesture declares `.appended`, so both closures are handed nil, and the arriving
    /// half is bounded by `VectorCanvas.vacatedInk` — what the walk measured before the id left.
    private func measureRestoreElementsArm(_ canvas: VectorCanvas,
                                           before: [VectorElement], after: [VectorElement],
                                           changedInk: CGRect?)
    -> (undoSeconds: Double, redoSeconds: Double, undoDabs: Int, redoDabs: Int,
        repairs: Int, widened: Int, abandoned: Int, rectangle: String) {
        canvas.elements = after
        canvas.bumpVersion()
        _ = canvas.render()
        let repairsBefore = canvas.regionRepairs
        let widenedBefore = canvas.regionRepairsWidened
        let abandonedBefore = canvas.regionRepairsAbandoned
        let timed = alternatingUndoRedo(runs: 3, undo: {
            canvas.restoreElements(before, changedInk: changedInk)
            _ = canvas.render()
            return canvas.lastRenderDabCount
        }, redo: {
            canvas.restoreElements(after, changedInk: changedInk)
            _ = canvas.render()
            return canvas.lastRenderDabCount
        })
        return (timed.undoSeconds, timed.redoSeconds, timed.undoDabs, timed.redoDabs,
                canvas.regionRepairs - repairsBefore,
                canvas.regionRepairsWidened - widenedBefore,
                canvas.regionRepairsAbandoned - abandonedBefore,
                rectangleShare(canvas))
    }

    // MARK: - A fill — the press TODO (41)'s first box was about

    /// **Fill, undo, redo**, at the four stroke counts the rest of this file uses.
    ///
    /// The **before** arm is `bumpVersion()`, and here that is not merely a stand-in for the old code
    /// — it *is* what the old code did. `restoreDamage`'s departing loop refused anything that was not
    /// a stroke, so a departing fill returned `.everything` whatever rectangle the caller passed, and
    /// `.everything` is exactly what `bumpVersion()` declares. So both arms measure the same two
    /// presses on the same canvas in one process, alternating, which is this file's whole method.
    ///
    /// **`changedInk` is nil on purpose, and it is not the same nil as the drawn stroke's.** The fill
    /// commit does pass `addFill`'s rectangle in the shipped app, and passing it here would measure
    /// the *caller's* answer rather than the canvas's. Nil is what isolates the change: the arriving
    /// half is bounded by `derivedFootprint(of:)` reading the fill's own path, as the departing half
    /// now is, so the row below is about the mechanism rather than about `CanvasManager+Fill`.
    ///
    /// The fill is a 300 × 200 pt ellipse — the shape of a lasso fill on the owner's canvas, and 2.9%
    /// of it, so the rectangle share column should read about that.
    func testUndoAndRedoAfterAFill() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.strokeCounts {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let wholeLayerDabs = canvas.lastRenderDabCount

                let before = canvas.elements
                let ellipse = CGPath(ellipseIn: CGRect(x: 700, y: 380, width: 300, height: 200),
                                     transform: nil)
                canvas.addFill(VectorFillElement(path: ellipse,
                                                 color: CodableColor(red: 0.85, green: 0.3,
                                                                     blue: 0.1, alpha: 1),
                                                 opacity: 1))
                _ = canvas.render()
                let after = canvas.elements

                let old = measureBumpVersionArm(canvas, before: before, after: after)
                let new = measureRestoreElementsArm(canvas, before: before, after: after,
                                                    changedInk: nil)

                report("fill + undo + redo — n=\(n)", [
                    ("strokes", "\(n)"),
                    ("wholeLayerDabs", "\(wholeLayerDabs)"),
                    ("undoBefore", ms(old.undoSeconds)),
                    ("undoDabsBefore", "\(old.undoDabs)"),
                    ("redoBefore", ms(old.redoSeconds)),
                    ("redoDabsBefore", "\(old.redoDabs)"),
                    ("undoAfter", ms(new.undoSeconds)),
                    ("undoDabsAfter", "\(new.undoDabs)"),
                    ("redoAfter", ms(new.redoSeconds)),
                    ("redoDabsAfter", "\(new.redoDabs)"),
                    ("rectangle", new.rectangle),
                    ("repairsWidened", "\(new.widened)"),
                    ("repairsAbandoned", "\(new.abandoned)"),
                    ("undoSpeedup", String(format: "%.1fx",
                                           old.undoSeconds / max(new.undoSeconds, 1e-9))),
                    ("redoSpeedup", String(format: "%.1fx",
                                           old.redoSeconds / max(new.redoSeconds, 1e-9))),
                ])

                XCTAssertEqual(Double(old.undoDabs), Double(wholeLayerDabs), accuracy: 300,
                               "the before arm at n=\(n) must re-stamp the whole cel on the undo — "
                               + "that is the press this row exists to price")
                XCTAssertEqual(new.repairs, 6,
                               "three pairs, six presses, and every one must have repaired a "
                               + "rectangle rather than declared one and walked the cel anyway")
                XCTAssertEqual(new.abandoned, 0,
                               "an abandoned repair at n=\(n) pays both walks and hides a bad bound")
                XCTAssertLessThan(new.undoDabs * 2, old.undoDabs,
                                  "the after arm at n=\(n) re-stamped \(new.undoDabs) dabs on the "
                                  + "undo against the before arm's \(old.undoDabs)")
            }
        }
    }

    /// **What the press itself now costs, because the fill arm added work to it.**
    ///
    /// `derivedFootprint(of:)`'s fill arm reads `VectorFillElement.cgPath`, which is an
    /// `NSKeyedUnarchiver` round trip of a `UIBezierPath` — the path is stored as archiver `Data`, so
    /// asking where a fill is means decoding it. That runs **on the main thread, inside the canvas's
    /// lock**, during an undo press that §11.11a measured at 0.44–7.84 ms across 200–4,000 strokes. A
    /// lasso fill's path is not four points; it is the traced contour of a flood fill, so this is
    /// worth a number rather than an assumption.
    ///
    /// Times `restoreElements` **alone**, with no render, alternating so every step is a real
    /// transition. The stroke arm is the control: it reaches the same method and does no unarchiving.
    func testWhatTheFillArmAddsToThePressItself() {
        let n = 2000
        for points in [4, 250, 1500] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let before = canvas.elements
                canvas.addFill(VectorFillElement(path: Self.contour(points: points),
                                                 color: CodableColor(red: 0.8, green: 0.3,
                                                                     blue: 0.1, alpha: 1),
                                                 opacity: 1))
                let after = canvas.elements

                var undo: [Double] = [], redo: [Double] = []
                for _ in 0..<5 {
                    autoreleasepool {
                        var start = CFAbsoluteTimeGetCurrent()
                        canvas.restoreElements(before, changedInk: nil)
                        undo.append(CFAbsoluteTimeGetCurrent() - start)
                        start = CFAbsoluteTimeGetCurrent()
                        canvas.restoreElements(after, changedInk: nil)
                        redo.append(CFAbsoluteTimeGetCurrent() - start)
                    }
                }
                undo.sort(); redo.sort()
                report("press alone, fill of \(points) points — n=\(n)", [
                    ("pathPoints", "\(points)"),
                    ("undoPress", ms(undo[2])),
                    ("redoPress", ms(redo[2])),
                ])
            }
        }

        // The control: the same two presses over a stroke, which unarchives nothing.
        autoreleasepool {
            let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
            _ = canvas.render()
            let before = canvas.elements
            canvas.addStroke(Self.benchStroke(n))
            let after = canvas.elements
            _ = canvas.render()

            var undo: [Double] = [], redo: [Double] = []
            for _ in 0..<5 {
                autoreleasepool {
                    var start = CFAbsoluteTimeGetCurrent()
                    canvas.restoreElements(before, changedInk: nil)
                    undo.append(CFAbsoluteTimeGetCurrent() - start)
                    start = CFAbsoluteTimeGetCurrent()
                    canvas.restoreElements(after, changedInk: nil)
                    redo.append(CFAbsoluteTimeGetCurrent() - start)
                }
            }
            undo.sort(); redo.sort()
            report("press alone, one stroke (control) — n=\(n)", [
                ("undoPress", ms(undo[2])),
                ("redoPress", ms(redo[2])),
            ])
        }
    }

    /// A closed contour of `points` vertices around a 300 × 200 ellipse — the shape and the vertex
    /// count of a traced flood fill, so the archived path is the size a real one is.
    private static func contour(points: Int) -> CGPath {
        let box = CGRect(x: 700, y: 380, width: 300, height: 200)
        guard points > 4 else { return CGPath(ellipseIn: box, transform: nil) }
        let path = CGMutablePath()
        for step in 0..<points {
            let t = CGFloat(step) / CGFloat(points) * 2 * .pi
            // A wobble on the radius, so the vertices are not co-linear and the archive is not
            // compressible into something unrepresentative.
            let r = 1 + 0.04 * sin(t * 9)
            let p = CGPoint(x: box.midX + cos(t) * box.width / 2 * r,
                            y: box.midY + sin(t) * box.height / 2 * r)
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - A pristine text object — the press TODO (41)'s second box was about

    /// A title the way an artist places one: the system face, bold, 96 pt, in a box nobody has
    /// resized (`autoSize`), so the glyphs are clipped by nothing. Measured by
    /// `TextLayout.autoSize` exactly as `regrowTextFrameIfAutoSizing` measures it.
    private static func title(at origin: CGPoint) -> VectorTextElement {
        let recipe = TextRecipe(string: "Scene 12 — take three",
                                font: FontDescriptor(familyName: FontDescriptor.systemFamilyName, isBold: true),
                                typography: Typography(pointSize: 96))
        let font = TextLayout.resolvedFont(for: recipe).font
        return VectorTextElement(recipe: recipe,
                                 frame: TextFrame(origin: origin, size: TextLayout.autoSize(for: recipe, font: font),
                                                  autoSize: true))
    }

    /// **Text, undo, redo**, at the four stroke counts the rest of this file uses.
    ///
    /// The **before** arm is `bumpVersion()`, and here as for the fill it *is* what the old code did:
    /// `derivedFootprint`'s text arm answered nil for a pristine box, so a departing one returned
    /// `.everything` whatever the caller passed, and `commitTextToVector` passes nil anyway. The
    /// **after** arm is the measured glyph-ink rectangle, `TextMeasure.glyphOutlineBounds` plus the
    /// raster overshoot, read for both directions with `changedInk` nil — which is what the shipped
    /// text commit passes, so this row is the mechanism *and* the shipped press.
    ///
    /// The title is ~900 × 115 pt on the 2048 × 1024 canvas, about 5% of it, so the rectangle share
    /// column should read about that.
    func testUndoAndRedoAfterAnAutoSizeTextObject() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.strokeCounts {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let wholeLayerDabs = canvas.lastRenderDabCount

                let before = canvas.elements
                let title = Self.title(at: CGPoint(x: 560, y: 420))
                canvas.commitTextEdit(editingID: nil, element: title)
                _ = canvas.render()
                let after = canvas.elements

                let old = measureBumpVersionArm(canvas, before: before, after: after)
                let new = measureRestoreElementsArm(canvas, before: before, after: after,
                                                    changedInk: nil)

                report("autoSize text + undo + redo — n=\(n)", [
                    ("strokes", "\(n)"),
                    ("wholeLayerDabs", "\(wholeLayerDabs)"),
                    ("undoBefore", ms(old.undoSeconds)),
                    ("undoDabsBefore", "\(old.undoDabs)"),
                    ("redoBefore", ms(old.redoSeconds)),
                    ("redoDabsBefore", "\(old.redoDabs)"),
                    ("undoAfter", ms(new.undoSeconds)),
                    ("undoDabsAfter", "\(new.undoDabs)"),
                    ("redoAfter", ms(new.redoSeconds)),
                    ("redoDabsAfter", "\(new.redoDabs)"),
                    ("rectangle", new.rectangle),
                    ("repairsWidened", "\(new.widened)"),
                    ("repairsAbandoned", "\(new.abandoned)"),
                    ("undoSpeedup", String(format: "%.1fx",
                                           old.undoSeconds / max(new.undoSeconds, 1e-9))),
                    ("redoSpeedup", String(format: "%.1fx",
                                           old.redoSeconds / max(new.redoSeconds, 1e-9))),
                ])

                XCTAssertEqual(Double(old.undoDabs), Double(wholeLayerDabs), accuracy: 300,
                               "the before arm at n=\(n) must re-stamp the whole cel on the undo — "
                               + "that is the press this row exists to price")
                XCTAssertEqual(new.repairs, 6,
                               "three pairs, six presses, and every one must have repaired a "
                               + "rectangle rather than declared one and walked the cel anyway")
                XCTAssertEqual(new.abandoned, 0,
                               "an abandoned repair at n=\(n) pays both walks and hides a bad bound")
                XCTAssertLessThan(new.undoDabs * 2, old.undoDabs,
                                  "the after arm at n=\(n) re-stamped \(new.undoDabs) dabs on the "
                                  + "undo against the before arm's \(old.undoDabs)")
            }
        }
    }

    /// **What the press itself now costs for a text object**, the sibling of
    /// `testWhatTheFillArmAddsToThePressItself` and the number the fill row promised would not
    /// survive an arm that *measured*: `derivedFootprint`'s text arm resolves the font and runs one
    /// CoreText framesetter pass plus one image-bounds query per line, on the main thread, inside the
    /// canvas's lock, during a press §11.11a measured at 0.44–7.84 ms. Timed alone with no render,
    /// alternating, over a one-word label, the title above, and a paragraph of eight lines, against
    /// the one-stroke control that measures nothing.
    func testWhatTheTextArmAddsToThePressItself() {
        let n = 2000
        let paragraph = (1...8).map { "Line \($0) of a caption that wraps across the shot" }
            .joined(separator: "\n")
        let cases: [(label: String, element: VectorTextElement)] = [
            ("one word", VectorTextElement(recipe: TextRecipe(string: "Bang", typography: Typography(pointSize: 64)),
                                           frame: TextFrame(origin: CGPoint(x: 600, y: 400),
                                                            size: CGSize(width: 160, height: 80), autoSize: true))),
            ("title", Self.title(at: CGPoint(x: 560, y: 420))),
            ("eight lines", VectorTextElement(recipe: TextRecipe(string: paragraph, typography: Typography(pointSize: 40)),
                                              frame: TextFrame(origin: CGPoint(x: 300, y: 200),
                                                               size: CGSize(width: 900, height: 420), autoSize: true))),
        ]
        for entry in cases {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let before = canvas.elements
                canvas.commitTextEdit(editingID: nil, element: entry.element)
                let after = canvas.elements

                var undo: [Double] = [], redo: [Double] = []
                for _ in 0..<5 {
                    autoreleasepool {
                        var start = CFAbsoluteTimeGetCurrent()
                        canvas.restoreElements(before, changedInk: nil)
                        undo.append(CFAbsoluteTimeGetCurrent() - start)
                        start = CFAbsoluteTimeGetCurrent()
                        canvas.restoreElements(after, changedInk: nil)
                        redo.append(CFAbsoluteTimeGetCurrent() - start)
                    }
                }
                undo.sort(); redo.sort()
                report("press alone, autoSize text (\(entry.label)) — n=\(n)", [
                    ("undoPress", ms(undo[2])),
                    ("redoPress", ms(redo[2])),
                ])
            }
        }

        // The control, in the same run: the same two presses over a stroke, which measures nothing.
        autoreleasepool {
            let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
            _ = canvas.render()
            let before = canvas.elements
            canvas.addStroke(Self.benchStroke(n))
            let after = canvas.elements
            _ = canvas.render()

            var undo: [Double] = [], redo: [Double] = []
            for _ in 0..<5 {
                autoreleasepool {
                    var start = CFAbsoluteTimeGetCurrent()
                    canvas.restoreElements(before, changedInk: nil)
                    undo.append(CFAbsoluteTimeGetCurrent() - start)
                    start = CFAbsoluteTimeGetCurrent()
                    canvas.restoreElements(after, changedInk: nil)
                    redo.append(CFAbsoluteTimeGetCurrent() - start)
                }
            }
            undo.sort(); redo.sort()
            report("press alone, one stroke (control for the text rows) — n=\(n)", [
                ("undoPress", ms(undo[2])),
                ("redoPress", ms(redo[2])),
            ])
        }
    }

    // MARK: - A rewrite in place — the press TODO (41)'s last box was about, and TODO (42)'s tick

    /// **A selection of `count` of the scene's strokes, clustered rather than scattered**: the
    /// strokes nearest the canvas's centre, which is the shape of a lasso — a loop around one part
    /// of the drawing — rather than fifty strokes chosen at random across the whole canvas, whose
    /// union would be the canvas. The rectangle column says which it measured.
    private static func selection(of count: Int, in elements: [VectorElement]) -> Set<UUID> {
        let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let ranked = elements.compactMap { element -> (UUID, CGFloat)? in
            guard let stroke = element.stroke, let box = StrokeGeometry.bounds(of: stroke.samples)
            else { return nil }
            return (element.id, hypot(box.midX - centre.x, box.midY - centre.y))
        }.sorted { $0.1 < $1.1 }
        return Set(ranked.prefix(count).map(\.0))
    }

    /// `elements` with every stroke in `ids` rewritten under its own id by `rewrite`.
    private static func rewriting(_ elements: [VectorElement], _ ids: Set<UUID>,
                                  _ rewrite: (inout VectorStroke) -> Void) -> [VectorElement] {
        elements.map { element in
            guard case .stroke(var stroke) = element, ids.contains(stroke.id) else { return element }
            rewrite(&stroke)
            return .stroke(stroke)
        }
    }

    /// **The after arm for a rewrite** — `restoreElements(_:changedInk:rewriting:)` with the ids the
    /// selection verbs pass, alternating for `measureRestoreElementsArm`'s reason.
    private func measureRewriteArm(_ canvas: VectorCanvas, before: [VectorElement],
                                   after: [VectorElement], rewritten: Set<UUID>)
    -> (undoSeconds: Double, redoSeconds: Double, undoDabs: Int, redoDabs: Int,
        repairs: Int, widened: Int, abandoned: Int, rectangle: String) {
        canvas.elements = after
        canvas.bumpVersion()
        _ = canvas.render()
        let repairsBefore = canvas.regionRepairs
        let widenedBefore = canvas.regionRepairsWidened
        let abandonedBefore = canvas.regionRepairsAbandoned
        let timed = alternatingUndoRedo(runs: 3, undo: {
            canvas.restoreElements(before, changedInk: nil, rewriting: rewritten)
            _ = canvas.render()
            return canvas.lastRenderDabCount
        }, redo: {
            canvas.restoreElements(after, changedInk: nil, rewriting: rewritten)
            _ = canvas.render()
            return canvas.lastRenderDabCount
        })
        return (timed.undoSeconds, timed.redoSeconds, timed.undoDabs, timed.redoDabs,
                canvas.regionRepairs - repairsBefore,
                canvas.regionRepairsWidened - widenedBefore,
                canvas.regionRepairsAbandoned - abandonedBefore,
                rectangleShare(canvas))
    }

    /// **Recolour fifty strokes, undo, redo** and **Apply Brush to fifty strokes, undo, redo**, at
    /// the four stroke counts. Fifty is a lasso around one part of a drawing at the owner's density.
    ///
    /// The **before** arm is `bumpVersion()`, and as with the fill row that *is* what the old code
    /// did: both verbs answered `.rewritesInPlace` and `registerVectorElementsUndo` put that through
    /// `elements =` plus `bumpVersion()` in both closures, so every press was the whole-cel walk.
    /// The after arm is the shipped seam with the shipped ids — the selection's own membership.
    ///
    /// Two rewrites rather than one because they bound their new half differently. A recolour moves
    /// no dab, so the old measurement *is* the new footprint and the rectangle is exact; an Apply
    /// Brush to a wider tip changes every dab's radius, so the new half is `strokeInkHint(of:)` at
    /// the new brush's reach, and `repairsWidened` is the column that says whether the hint held.
    func testUndoAndRedoAfterARecolourAndAnApplyBrush() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }
        var wider = Self.benchBrush
        wider.name = "Bench x2"
        wider.dab.size = 2
        let widerRef = BrushPool.intern(wider)
        let red = CodableColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)

        for (verb, rewrite) in [("recolour", { (stroke: inout VectorStroke) in stroke.color = red }),
                                ("applyBrush", { (stroke: inout VectorStroke) in stroke.brushRef = widerRef })] {
            for n in Self.strokeCounts {
                autoreleasepool {
                    let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                    _ = canvas.render()
                    let wholeLayerDabs = canvas.lastRenderDabCount

                    let before = canvas.elements
                    let selected = Self.selection(of: 50, in: before)
                    let after = Self.rewriting(before, selected, rewrite)

                    let old = measureBumpVersionArm(canvas, before: before, after: after)
                    let new = measureRewriteArm(canvas, before: before, after: after,
                                                rewritten: selected)

                    report("\(verb) of 50 + undo + redo — n=\(n)", [
                        ("strokes", "\(n)"),
                        ("wholeLayerDabs", "\(wholeLayerDabs)"),
                        ("undoBefore", ms(old.undoSeconds)),
                        ("undoDabsBefore", "\(old.undoDabs)"),
                        ("redoBefore", ms(old.redoSeconds)),
                        ("redoDabsBefore", "\(old.redoDabs)"),
                        ("undoAfter", ms(new.undoSeconds)),
                        ("undoDabsAfter", "\(new.undoDabs)"),
                        ("redoAfter", ms(new.redoSeconds)),
                        ("redoDabsAfter", "\(new.redoDabs)"),
                        ("rectangle", new.rectangle),
                        ("repairsWidened", "\(new.widened)"),
                        ("repairsAbandoned", "\(new.abandoned)"),
                        ("undoSpeedup", String(format: "%.1fx",
                                               old.undoSeconds / max(new.undoSeconds, 1e-9))),
                        ("redoSpeedup", String(format: "%.1fx",
                                               old.redoSeconds / max(new.redoSeconds, 1e-9))),
                    ])

                    XCTAssertEqual(Double(old.undoDabs), Double(wholeLayerDabs), accuracy: 300,
                                   "\(verb): the before arm at n=\(n) must re-stamp the whole cel")
                    XCTAssertEqual(new.repairs, 6,
                                   "\(verb): three pairs, six presses, every one a repair")
                    XCTAssertEqual(new.abandoned, 0,
                                   "\(verb): an abandoned repair at n=\(n) hides a bad bound")
                    // **The rectangle here shrinks with density, which is the fill's curve turned
                    // round rather than the cut's.** Fifty strokes is a quarter of a 200-stroke
                    // scene and the fifty nearest the centre span ~38% of the canvas; at 2,000 the
                    // same fifty are a tight cluster at ~16%. So the saving *grows* with density —
                    // MEASURED 1.9x at 200, 3.6x at 2,000 — and "half the dabs" is only a claim
                    // worth making from 1,000 up. Below that the claim is "fewer", which is what a
                    // bound proportional to a selection covering a third of the canvas can buy.
                    XCTAssertLessThan(new.undoDabs, old.undoDabs,
                                      "\(verb): the after arm at n=\(n) re-stamped \(new.undoDabs) "
                                      + "against the before arm's \(old.undoDabs)")
                    if n >= 1000 {
                        XCTAssertLessThan(new.undoDabs * 2, old.undoDabs,
                                          "\(verb): at n=\(n) a 50-stroke selection is a sixth of "
                                          + "the canvas and its repair should be under half the cel")
                    }
                }
            }
        }
    }

    /// **What one tick of TODO (42)'s slider costs before the render** — `restoreElements` alone
    /// for a rewrite of fifty strokes at 2,000, no walk, alternating. The number the item asks for:
    /// the hook must not itself walk the cel, and this is the press it adds to.
    ///
    /// Three shapes of tick, because the hint has two arms: a recolour (same geometry, the old
    /// measurement is reused, the comparison is a buffer-identity check), an Apply Brush (same
    /// geometry, a different brush, `strokeInkHint` walks each stroke's forty samples once), and a
    /// size change (the same). The control is one stroke arriving, which is the press §11.11a
    /// measured at ~2 µs an element.
    func testWhatARewriteTickCostsBeforeTheRender() {
        let n = 2000
        var wider = Self.benchBrush
        wider.name = "Bench x2"
        wider.dab.size = 2
        let widerRef = BrushPool.intern(wider)
        let red = CodableColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        for (verb, rewrite) in [("recolour", { (stroke: inout VectorStroke) in stroke.color = red }),
                                ("applyBrush", { (stroke: inout VectorStroke) in stroke.brushRef = widerRef }),
                                ("size", { (stroke: inout VectorStroke) in stroke.size *= 1.5 })] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let before = canvas.elements
                let selected = Self.selection(of: 50, in: before)
                let after = Self.rewriting(before, selected, rewrite)

                var undo: [Double] = [], redo: [Double] = []
                for _ in 0..<5 {
                    autoreleasepool {
                        var start = CFAbsoluteTimeGetCurrent()
                        canvas.restoreElements(before, changedInk: nil, rewriting: selected)
                        undo.append(CFAbsoluteTimeGetCurrent() - start)
                        start = CFAbsoluteTimeGetCurrent()
                        canvas.restoreElements(after, changedInk: nil, rewriting: selected)
                        redo.append(CFAbsoluteTimeGetCurrent() - start)
                    }
                }
                undo.sort(); redo.sort()
                report("tick alone, \(verb) of 50 — n=\(n)", [
                    ("undoPress", ms(undo[2])),
                    ("redoPress", ms(redo[2])),
                ])
            }
        }

        autoreleasepool {
            let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
            _ = canvas.render()
            let before = canvas.elements
            canvas.addStroke(Self.benchStroke(n))
            let after = canvas.elements
            _ = canvas.render()
            var undo: [Double] = [], redo: [Double] = []
            for _ in 0..<5 {
                autoreleasepool {
                    var start = CFAbsoluteTimeGetCurrent()
                    canvas.restoreElements(before, changedInk: nil)
                    undo.append(CFAbsoluteTimeGetCurrent() - start)
                    start = CFAbsoluteTimeGetCurrent()
                    canvas.restoreElements(after, changedInk: nil)
                    redo.append(CFAbsoluteTimeGetCurrent() - start)
                }
            }
            undo.sort(); redo.sort()
            report("tick alone, one stroke (control) — n=\(n)", [
                ("undoPress", ms(undo[2])),
                ("redoPress", ms(redo[2])),
            ])
        }
    }

    // MARK: - A drawn stroke — the commonest undo/redo pair there is

    /// **Draw, undo, redo.** Not an eraser at all, which is the correction the owner had to make
    /// twice: *"My bit about the undo/redo being slow was just it being slow in general, not
    /// specifically tied to an undo/redo of an erase."*
    ///
    /// It is the pair `testWhatAnUndoPressSpendsOnTheMainThreadAgainstWhatTheRenderCosts` measures the
    /// wait of, and its two halves were wildly asymmetric: the undo declared a rectangle from the
    /// departing stroke's own measured footprint, and the redo declared `.everything` because nothing
    /// could bound ink arriving from a snapshot. MEASURED before this pass at 60.5 ms against 571.2 ms
    /// at 1,000 strokes — the redo was 9.4x the undo, on the same one stroke.
    func testUndoAndRedoAfterADrawnStroke() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.strokeCounts {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let wholeLayerDabs = canvas.lastRenderDabCount

                let before = canvas.elements
                canvas.addStroke(Self.benchStroke(n))
                _ = canvas.render()
                let after = canvas.elements

                let old = measureBumpVersionArm(canvas, before: before, after: after)
                // Nil, and that is the whole point: `foldGestureDamage` drops the gesture's rectangle
                // on an append, so this is exactly what `registerVectorUndo` hands both closures.
                let new = measureRestoreElementsArm(canvas, before: before, after: after,
                                                    changedInk: nil)

                report("drawn stroke + undo + redo — n=\(n)", [
                    ("strokes", "\(n)"),
                    ("wholeLayerDabs", "\(wholeLayerDabs)"),
                    ("undoBefore", ms(old.undoSeconds)),
                    ("undoDabsBefore", "\(old.undoDabs)"),
                    ("redoBefore", ms(old.redoSeconds)),
                    ("redoDabsBefore", "\(old.redoDabs)"),
                    ("undoAfter", ms(new.undoSeconds)),
                    ("undoDabsAfter", "\(new.undoDabs)"),
                    ("redoAfter", ms(new.redoSeconds)),
                    ("redoDabsAfter", "\(new.redoDabs)"),
                    ("rectangle", new.rectangle),
                    ("repairsWidened", "\(new.widened)"),
                    ("repairsAbandoned", "\(new.abandoned)"),
                    ("redoSpeedup", String(format: "%.1fx",
                                           old.redoSeconds / max(new.redoSeconds, 1e-9))),
                    ("undoSpeedup", String(format: "%.1fx",
                                           old.undoSeconds / max(new.undoSeconds, 1e-9))),
                ])

                XCTAssertEqual(Double(old.redoDabs), Double(wholeLayerDabs), accuracy: 300,
                              "the before arm at n=\(n) must re-stamp the whole list plus the one "
                              + "stroke coming back")
                XCTAssertEqual(new.repairs, 6,
                               "three pairs, six presses, and every one of them must have repaired "
                               + "a rectangle — the redo included, which is what this pass added")
                XCTAssertEqual(new.widened, 0,
                               "a redone stroke is the same value that left, so its remembered "
                               + "rectangle must not need widening the way a cut piece's does")
                XCTAssertEqual(new.abandoned, 0,
                               "an abandoned repair at n=\(n) pays both walks and hides a bad bound")
                XCTAssertLessThan(new.redoDabs * 2, old.redoDabs,
                                  "the after arm at n=\(n) re-stamped \(new.redoDabs) dabs on the redo "
                                  + "against the before arm's \(old.redoDabs)")
            }
        }
    }

    // MARK: - Mode 3 (To Cross) — a single per-sample cut, then undo and redo of it

    /// **The eraser the owner named** ("cross eraser" is `VectorEraserMode.cutToIntersection`, Mode
    /// 3). One touch sample, not the whole 40-sample drag §11.10 already profiled: this bench is about
    /// what undoing *one* commit costs, and Mode 3 commits once per sample, so a single call to
    /// `cutToIntersection(atCanvasPoint:)` is one of those commits in isolation — the same instrument
    /// `testWhereACrossEraserDragSpendsItsTime`'s "Mode 3 resolve split" row uses.
    func testUndoAndRedoAfterAModeThreeCut() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.strokeCounts {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                let wholeLayerDabs = canvas.lastRenderDabCount

                let before = canvas.elements

                // The densest part of the canvas — the same point `dragPath` sweeps through the
                // middle of, so the tip has strokes under it to cut.
                let point = CGPoint(x: Self.canvasSize.width * 0.5, y: Self.canvasSize.height * 0.5)
                let cutStart = CFAbsoluteTimeGetCurrent()
                let resolved = canvas.cutToIntersection(atCanvasPoint: point, brush: Self.eraserBrush,
                                                        size: Self.eraserSize)
                let cutDamage = canvas.lastDamage
                _ = canvas.render()
                let cutSeconds = CFAbsoluteTimeGetCurrent() - cutStart
                let cutDabs = canvas.lastRenderDabCount
                let cutRegionRepairs = canvas.regionRepairs
                XCTAssertEqual(resolved.outcome, .cut, "the tip at n=\(n) must land on a stroke")
                XCTAssertGreaterThan(cutRegionRepairs, 0,
                                     "the cut at n=\(n) must take the region-repair path")

                let after = canvas.elements
                guard case .region(let cutRegion) = cutDamage else {
                    XCTFail("the Mode 3 cut at n=\(n) must declare a rectangle")
                    return
                }

                let old = measureBumpVersionArm(canvas, before: before, after: after)
                let new = measureRestoreElementsArm(canvas, before: before, after: after,
                                                    changedInk: cutRegion)

                report("Mode 3 cut + undo + redo — n=\(n)", [
                    ("strokes", "\(n)"),
                    ("wholeLayerDabs", "\(wholeLayerDabs)"),
                    ("cutOnce", ms(cutSeconds)),
                    ("cutDabs", "\(cutDabs)"),
                    ("cutRegionRepairs", "\(cutRegionRepairs)"),
                    ("undoBefore", ms(old.undoSeconds)),
                    ("undoDabsBefore", "\(old.undoDabs)"),
                    ("redoBefore", ms(old.redoSeconds)),
                    ("redoDabsBefore", "\(old.redoDabs)"),
                    ("undoAfter", ms(new.undoSeconds)),
                    ("undoDabsAfter", "\(new.undoDabs)"),
                    ("redoAfter", ms(new.redoSeconds)),
                    ("redoDabsAfter", "\(new.redoDabs)"),
                    ("rectangle", new.rectangle),
                    ("repairsWidened", "\(new.widened)"),
                    ("repairsAbandoned", "\(new.abandoned)"),
                    ("undoSpeedup", String(format: "%.1fx",
                                           old.undoSeconds / max(new.undoSeconds, 1e-9))),
                ])

                XCTAssertEqual(Double(old.undoDabs), Double(wholeLayerDabs), accuracy: 1,
                              "the before arm at n=\(n) must re-stamp the pre-cut list in full")
                XCTAssertEqual(new.repairs, 6,
                               "the after arm at n=\(n) is three undo/redo pairs and every one of "
                               + "them must have repaired a rectangle")
                XCTAssertEqual(new.abandoned, 0,
                               "an abandoned repair at n=\(n) pays both walks and hides a bad bound")
                XCTAssertLessThan(new.undoDabs, old.undoDabs,
                                  "the after arm at n=\(n) stamped \(new.undoDabs) dabs against the "
                                  + "before arm's \(old.undoDabs)")
            }
        }
    }

    // MARK: - What the artist is actually waiting for
    //
    // The owner: *"Undoing and redoing while there are a lot of strokes can be laggy, a few hundred
    // milliseconds sluggish."* A few hundred milliseconds is either a **frozen** app or a **late
    // picture**, and which one it is decides whether the work below is worth anything: the render an
    // undo triggers is dispatched off the main thread (`StrokeCanvasView.refreshDisplay`, RENDER.md
    // §2.13), so if the model half of a press is sub-millisecond the app never stops responding and
    // what the artist sees is the *previous* frame standing there while the rasterize runs.
    //
    // These two tests separate the press from the picture and time both.

    /// A `CanvasManager` holding one vector layer whose only cel is `canvas`, with the history
    /// cleared (`addVectorLayer` records a structural step of its own) and one full render already
    /// paid so `paintedBounds` is populated — a cold cel has no measured footprints and every restore
    /// would fall back to `.everything` regardless of what it declared.
    private func benchManager(_ canvas: VectorCanvas)
    -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasManager()
        // Never the shared store — `CanvasFixture.isolatedBrushLibrary`'s doc has the reason.
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.canvasSize
        manager.addVectorLayer()
        manager.layers[0].cels[0].vector = canvas
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        _ = canvas.render()
        return (manager, manager.layers[0].id, manager.layers[0].cels[0].id)
    }

    /// **A press and the render it causes, timed apart, alternating.** `press(false)` is undo and
    /// `press(true)` is redo; `render()` returns the dabs its walk stamped.
    ///
    /// The render runs *between* the timed presses rather than being skipped, because skipping it
    /// would measure a canvas the app never has: `restoreDamage` derives the vacated half from
    /// footprints the last walk measured, so two restores with no walk between them are the second
    /// one falling through to `.everything` for want of a table.
    private func alternatingPressAndRender(runs: Int, press: (Bool) -> Void, render: () -> Int)
    -> (undoPress: Double, redoPress: Double, undoRender: Double, redoRender: Double,
        undoDabs: Int, redoDabs: Int) {
        var undoPresses: [Double] = [], redoPresses: [Double] = []
        var undoRenders: [Double] = [], redoRenders: [Double] = []
        var undoDabs = 0, redoDabs = 0
        for _ in 0..<runs {
            autoreleasepool {
                var start = CFAbsoluteTimeGetCurrent()
                press(false)
                undoPresses.append(CFAbsoluteTimeGetCurrent() - start)
                start = CFAbsoluteTimeGetCurrent()
                undoDabs = render()
                undoRenders.append(CFAbsoluteTimeGetCurrent() - start)
                start = CFAbsoluteTimeGetCurrent()
                press(true)
                redoPresses.append(CFAbsoluteTimeGetCurrent() - start)
                start = CFAbsoluteTimeGetCurrent()
                redoDabs = render()
                redoRenders.append(CFAbsoluteTimeGetCurrent() - start)
            }
        }
        undoPresses.sort(); redoPresses.sort(); undoRenders.sort(); redoRenders.sort()
        return (undoPresses[runs / 2], redoPresses[runs / 2],
                undoRenders[runs / 2], redoRenders[runs / 2], undoDabs, redoDabs)
    }

    /// **The main-thread span of an undo press, held apart from the render that follows it** — the
    /// question the owner's "laggy" is ambiguous about and the one that decides whether a cheaper
    /// render is the right fix at all.
    ///
    /// The step timed is a **drawn stroke**, which is the commonest undo there is: an append, undone
    /// and redone. `manager.undo()` here runs the whole production press —
    /// `finalizePendingGesturesForHistoryAction`, the closure `registerVectorUndo` records,
    /// `raise(.historyUndo(…))`, `refreshUndoRedoState` — with only the two lines that live on a
    /// `UIView` left out: `refreshDisplay()`, which is what dispatches the rasterize off main and is
    /// exactly what this test exists to hold separate, and `onStrokeEnded?()`, whose model half
    /// (`refreshUndoRedoState` + `strokeEnded`'s thumbnail schedule) is kept.
    ///
    /// `canvas.rasterizations` across the press is the operand that says the split is real rather
    /// than assumed: a press that rendered would move it.
    func testWhatAnUndoPressSpendsOnTheMainThreadAgainstWhatTheRenderCosts() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in [200, 1000, 2000, 4000] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                let fixture = benchManager(canvas)
                let manager = fixture.manager
                let layerID = fixture.layerID, celID = fixture.celID
                let wholeLayerDabs = canvas.lastRenderDabCount

                let before = canvas.elements
                canvas.addStroke(Self.benchStroke(n))
                let after = canvas.elements
                _ = canvas.render()

                // `StrokeCanvasView.registerVectorUndo`'s closures. `changedInk` is nil because
                // `foldGestureDamage` drops the gesture's rectangle on an append — `addStroke`
                // declares `.appended`, not `.region` — which is the honest state of the shipped
                // code and the thing task (a) is about.
                manager.recordUndo(label: .brushStroke, cost: (before.count + after.count) * 512,
                                   undo: { [weak manager] in
                    canvas.restoreElements(before, changedInk: nil)
                    manager?.refreshUndoRedoState()
                    manager?.scheduleThumbnailRegen(layerID: layerID, celID: celID)
                }, redo: { [weak manager] in
                    canvas.restoreElements(after, changedInk: nil)
                    manager?.refreshUndoRedoState()
                    manager?.scheduleThumbnailRegen(layerID: layerID, celID: celID)
                })

                let rasterizationsBefore = canvas.rasterizations
                let timed = alternatingPressAndRender(runs: 5, press: { isRedo in
                    if isRedo { manager.redo() } else { manager.undo() }
                }, render: {
                    _ = canvas.render()
                    return canvas.lastRenderDabCount
                })
                // Five pairs, one render each side of each press: ten rasterizations and not one more.
                let pressRasterizations = canvas.rasterizations - rasterizationsBefore - 10

                // What the debounced thumbnail regen the press queued costs when it fires, 400 ms
                // later and on main. Not part of the press, but it is main-thread work an undo
                // causes and would not be fixed by anything cheaper in the render.
                let thumbnailStart = CFAbsoluteTimeGetCurrent()
                manager.flushPendingThumbnailRegens()
                let thumbnailSeconds = CFAbsoluteTimeGetCurrent() - thumbnailStart

                report("undo press vs render — n=\(n)", [
                    ("strokes", "\(n)"),
                    ("wholeLayerDabs", "\(wholeLayerDabs)"),
                    ("undoPress", ms(timed.undoPress)),
                    ("redoPress", ms(timed.redoPress)),
                    ("undoRender", ms(timed.undoRender)),
                    ("redoRender", ms(timed.redoRender)),
                    ("undoDabs", "\(timed.undoDabs)"),
                    ("redoDabs", "\(timed.redoDabs)"),
                    ("pressShareOfUndo", String(format: "%.2f%%",
                                                100 * timed.undoPress
                                                / max(timed.undoPress + timed.undoRender, 1e-9))),
                    ("pressShareOfRedo", String(format: "%.2f%%",
                                                100 * timed.redoPress
                                                / max(timed.redoPress + timed.redoRender, 1e-9))),
                    ("thumbnailFlush", ms(thumbnailSeconds)),
                    ("extraRasterizationsInPresses", "\(pressRasterizations)"),
                ])

                XCTAssertEqual(pressRasterizations, 0,
                               "a press at n=\(n) rasterized \(pressRasterizations) times beyond the "
                               + "renders this harness asked for — the model half is not separable "
                               + "from the picture and this test's whole premise is wrong")
                // **50 ms, and the number is chosen against the claim rather than against the
                // measurement.** What this pins is that the press is not where the owner's *few
                // hundred milliseconds* live; anything under a tenth of that says so. A bound tight
                // to the measurement would be configuration-dependent, which this bench is not — it
                // ran at 7.8 ms in Release and 13.2 ms in Debug at n=4000, and a 10 ms bound written
                // against the first reddened on the second while nothing had changed.
                XCTAssertLessThan(timed.undoPress, 0.050,
                                  "the model half of an undo press at n=\(n) took "
                                  + "\(ms(timed.undoPress)) — if this is where the owner's few "
                                  + "hundred milliseconds live, the app is freezing and the render "
                                  + "is not the bug")
                XCTAssertLessThan(timed.redoPress, 0.050,
                                  "the model half of a redo press at n=\(n) took \(ms(timed.redoPress))")
            }
        }
    }

    /// **The raster arm, which none of this work touches** — an undo there swaps a
    /// `RasterLayerTexture` reference rather than re-walking a display list
    /// (`SelectionModels.registerCelReversal` → `applyCelChange`), so it should be flat in canvas
    /// size and independent of everything above. If it is not, that is a separate finding.
    ///
    /// The raster half of `refreshDisplay` is timed alongside, because it is the one display path
    /// that rasterizes **on the main thread** — `raster?.renderIfNonEmpty()` is called inline, with no
    /// `DeferredVectorRender` hop. Whether that costs anything is the question; a texture built from
    /// an image memoizes it, so the expectation is that it does not.
    func testWhatARasterUndoPressSpendsOnTheMainThread() {
        for size in [CGSize(width: 2048, height: 1024), CGSize(width: 4096, height: 4096)] {
            autoreleasepool {
                let manager = CanvasManager()
                manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
                manager.canvasSize = size
                manager.addLayer()
                let whole = CGRect(origin: .zero, size: size)
                let old = RasterLayerTexture(size: size,
                                             image: CanvasFixture.solidImage(.red, rect: whole, size: size))
                let new = RasterLayerTexture(size: size,
                                             image: CanvasFixture.solidImage(.blue, rect: whole, size: size))
                manager.layers[0].cels[0].raster = old
                manager.history.removeAll()
                manager.registerUndoableCelChange(layerID: manager.layers[0].id,
                                                  celID: manager.layers[0].cels[0].id,
                                                  oldRaster: old, oldBaked: nil, oldFill: nil,
                                                  newRaster: new, newBaked: nil, newFill: nil,
                                                  label: .clearSelection)

                let timed = alternatingPressAndRender(runs: 5, press: { isRedo in
                    if isRedo { manager.redo() } else { manager.undo() }
                }, render: {
                    // What `refreshDisplay` does for a raster layer, on the main thread, inline.
                    _ = manager.layers[0].cels[0].raster.renderIfNonEmpty()
                    return 0
                })

                let thumbnailStart = CFAbsoluteTimeGetCurrent()
                manager.flushPendingThumbnailRegens()
                let thumbnailSeconds = CFAbsoluteTimeGetCurrent() - thumbnailStart

                report("raster undo press — \(Int(size.width))x\(Int(size.height))", [
                    ("undoPress", ms(timed.undoPress)),
                    ("redoPress", ms(timed.redoPress)),
                    ("undoDisplay", ms(timed.undoRender)),
                    ("redoDisplay", ms(timed.redoRender)),
                    ("thumbnailFlush", ms(thumbnailSeconds)),
                ])

                XCTAssertLessThan(timed.undoPress, 0.010,
                                  "a raster undo at \(size) took \(ms(timed.undoPress)) on main — it "
                                  + "swaps one reference and should be flat in canvas size")
            }
        }
    }
}
