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
    private func measureRestoreElementsArm(_ canvas: VectorCanvas,
                                           before: [VectorElement], after: [VectorElement],
                                           changedInk: CGRect)
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
}
