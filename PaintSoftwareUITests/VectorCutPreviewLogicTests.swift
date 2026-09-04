import XCTest
import CoreGraphics
import UIKit

/// Mode 2's **live preview** — `VectorCanvas.cutPreviewEdits` / `VectorCanvas.applyPreview`, and
/// promise they make: what the artist watches disappear under the eraser is what the lift actually
/// removes.
///
/// Mode 2 had no live feedback of any kind until 2026-08-22. The eraser could be dragged across a
/// line and nothing at all happened until the finger came up. The owner asked for it twice — *"the
/// to cut eraser does not have live feedback like the to cross eraser, it only applies when the
/// eraser is lifted"* — and this is the file that says the feedback is honest.
///
/// **The accuracy problem, which is the whole reason these tests are pixel tests.** The obvious
/// preview is to punch the eraser's own footprint into a copy of the layer, which is what Mode 1
/// does and is exactly right *for Mode 1*, because Mode 1 removes the footprint. Mode 2 does not: it
/// removes the parametric spans of a stroke's **centreline** that lie under the footprint, and then
/// the stroke's whole **width** over those spans goes with them. A 40pt line cut by an 8pt eraser
/// loses a 40pt-wide bite; a footprint preview would show an 8pt notch and then pop the other 32pt
/// away at the moment of lift. `testAStrokeThickerThanTheEraser…` measures both and is the test that
/// says the right one shipped.
///
/// Nothing here drives a simulator or a view: `VectorCanvas` and `BrushStamper` compile into this
/// target, and the preview was deliberately built as two `VectorCanvas` entry points — rather than
/// inside `StrokeCanvasView`, which is not in this target — so it could be asserted this way.
final class VectorCutPreviewLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 256, height: 256)

    /// Opaque, hard, unjittered, and `.fixed` dynamics: the punch is `.destinationOut` at the ink's
    /// own alpha, so full coverage is what makes "the preview removes what the cut removes" a
    /// statement about geometry rather than about alpha arithmetic. A semi-transparent stroke leaves
    /// a faint ghost under the preview — see the note on `testASemiTransparentStroke…`.
    private func opaqueBrush(size: CGFloat) -> Brush {
        Brush(name: "test", tip: .round, size: size, dab: BrushDabSettings(hardness: 1))
    }

    private func line(y: CGFloat, from x0: CGFloat, to x1: CGFloat, count: Int = 17) -> StrokeSamples {
        StrokeSamples((0..<count).map { i in
            VectorSample(x: x0 + (x1 - x0) * CGFloat(i) / CGFloat(count - 1), y: y, pressure: 1)
        }, channels: .pressureOnly)
    }

    private func stroke(_ samples: StrokeSamples, size: CGFloat, opacity: Double = 1) -> VectorStroke {
        VectorStroke(brush: opaqueBrush(size: size),
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: size, opacity: opacity, samples: samples)
    }

    /// A vertical eraser drag across the middle of the canvas, sampled the way a live gesture is.
    private func drag(x: CGFloat, from y0: CGFloat, to y1: CGFloat, count: Int = 24) -> StrokeSamples {
        StrokeSamples((0..<count).map { i in
            VectorSample(x: x, y: y0 + (y1 - y0) * CGFloat(i) / CGFloat(count - 1), pressure: 1)
        }, channels: .pressureOnly)
    }

    /// Replays `gesture` through the preview exactly as `StrokeCanvasView.previewCutSpans` does —
    /// one two-sample increment per touch sample — and hands back the scratch the artist would be
    /// looking at.
    private func previewed(_ canvas: VectorCanvas, gesture: StrokeSamples,
                           brush: Brush, size: CGFloat) -> RasterLayerTexture {
        let scratch = RasterLayerTexture.load(from: canvas.render(), size: Self.canvasSize)
        var previous: VectorSample?
        var accumulated: [UUID: [ClosedRange<CGFloat>]] = [:]
        for sample in gesture {
            let increment: StrokeSamples = previous.map { [$0, sample] } ?? [sample]
            previous = sample
            for edit in canvas.cutPreviewEdits(alongPath: increment, brush: brush, size: size,
                                               accumulating: &accumulated) {
                VectorCanvas.applyPreview(edit, into: scratch)
            }
        }
        return scratch
    }

    /// A footprint punch of the same gesture — the preview that was *not* shipped, built here so the
    /// difference between the two can be a number instead of an argument.
    private func footprintPunched(_ canvas: VectorCanvas, gesture: StrokeSamples,
                                  brush: Brush, size: CGFloat) -> RasterLayerTexture {
        let scratch = RasterLayerTexture.load(from: canvas.render(), size: Self.canvasSize)
        let samples = StrokeSamples(gesture, channels: .pressureOnly)
        BrushStamper.stampStroke(into: scratch, samples: samples, brush: brush, color: .black,
                                 brushSize: size, brushOpacity: 1, isEraser: true,
                                 random: DabRandom(seed: 0))
        return scratch
    }

    /// How many pixels differ between two renders of the same canvas — i.e. how much ink an
    /// operation took away. Uses `RasterVectorParity.report`, the same comparison the parity suite
    /// measures the eraser with, so a number here is readable against a number there.
    private func pixelsChanged(_ a: UIImage, _ b: UIImage) -> Int {
        guard let report = RasterVectorParity.report(raster: a, vector: b, size: Self.canvasSize) else {
            XCTFail("Both images should rasterize at the canvas size")
            return -1
        }
        return report.differingPixelCount
    }

    // MARK: - The preview is a preview

    /// **Nothing is mutated by looking.** The display list, its stroke ids, their samples and the
    /// canvas `version` all come out of a whole simulated drag exactly as they went in.
    ///
    /// This is the property that separates Mode 2's preview from Mode 3's mechanism. Mode 3 is live
    /// because it commits a real cut on every touch sample, and pays ~95 ms per cutting sample for
    /// it ([PERFORMANCE.md](PERFORMANCE.md) item 10) — every cut calls `invalidate()`, so the next
    /// `render()` runs cold over the whole layer. Mode 2 must not buy that: it reads geometry and
    /// draws into a scratch raster. If `version` ever moves here, it has.
    func testThePreviewNeverTouchesTheDisplayList() {
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: [
            stroke(line(y: 100, from: 40, to: 216), size: 24),
            stroke(line(y: 156, from: 40, to: 216), size: 24),
        ])
        _ = canvas.render()
        let elementsBefore = canvas.elements
        let versionBefore = canvas.version
        let idsBefore = canvas.strokes.map(\.id)
        let samplesBefore = canvas.strokes.map(\.samples)

        let gesture = drag(x: 128, from: 60, to: 200)
        _ = previewed(canvas, gesture: gesture, brush: opaqueBrush(size: 12), size: 12)

        XCTAssertEqual(canvas.elements.count, elementsBefore.count,
                       "A preview that adds or removes an element is not a preview")
        XCTAssertEqual(canvas.strokes.map(\.id), idsBefore,
                       "Splitting a stroke mints fresh ids — if these moved, the preview committed")
        XCTAssertEqual(canvas.strokes.map(\.samples), samplesBefore,
                       "The stored geometry must be untouched mid-drag")
        XCTAssertEqual(canvas.version, versionBefore,
                       "`version` moving means `invalidate()` ran, which throws away the render "
                       + "cache and the spatial index — the exact term that costs Mode 3 ~95 ms a "
                       + "sample. The preview must not buy it")

        // …and the gesture really was over ink, or the assertions above are about nothing.
        XCTAssertTrue(canvas.erase(alongPath: gesture, brush: opaqueBrush(size: 12), size: 12,
                                   mode: .cutPoints),
                      "Setup: this drag must actually cut, or the test above proves nothing")
    }

    /// **Previewing changes nothing about what the lift does.** The same gesture, committed on two
    /// identical canvases — one that was previewed through first and one that was not — leaves
    /// byte-identical display lists.
    ///
    /// This is also the "does not double-apply" test. The preview and the commit are two readings of
    /// one gesture; if the preview ever committed as well, the previewed canvas would arrive at the
    /// commit already cut and the second cut would land on different geometry.
    func testTheCutAppliedOnLiftIsUnchangedByHavingPreviewedIt() {
        let samples = [line(y: 100, from: 40, to: 216), line(y: 156, from: 40, to: 216)]
        let build = { VectorCanvas(size: Self.canvasSize, strokes: samples.map { self.stroke($0, size: 24) }) }
        let gesture = drag(x: 128, from: 60, to: 200)
        let brush = opaqueBrush(size: 12)

        let withPreview = build()
        _ = previewed(withPreview, gesture: gesture, brush: brush, size: 12)
        XCTAssertTrue(withPreview.erase(alongPath: gesture, brush: brush, size: 12, mode: .cutPoints))

        let without = build()
        XCTAssertTrue(without.erase(alongPath: gesture, brush: brush, size: 12, mode: .cutPoints))

        XCTAssertEqual(withPreview.strokes.count, without.strokes.count,
                       "The preview must not change how many pieces the cut produces")
        XCTAssertEqual(withPreview.strokes.map(\.samples), without.strokes.map(\.samples),
                       "…nor where a single cut boundary lands. A difference here means the preview "
                       + "committed too, and the lift cut an already-cut layer")
        XCTAssertEqual(pixelsChanged(withPreview.render(), without.render()), 0,
                       "The two committed layers must render identically, pixel for pixel")
    }

    // MARK: - The preview is accurate

    /// **The crux, and it is the opposite of what it looks like.** A stroke much thicker than the
    /// eraser loses *nothing visible at all* to a Mode 2 cut: the two pieces the cut leaves behind
    /// grow round end caps that meet across an 8pt gap in a 40pt line, so the display list gains an
    /// element and not one pixel changes. A preview that punched the eraser's footprint — Mode 1's
    /// preview, and the obvious thing to reach for — would open a nib-shaped notch and then hand it
    /// straight back at the moment of lift.
    ///
    /// Three images, one gesture: what the **lift** produces, what the shipped **span-and-caps
    /// preview** shows, and what a **footprint punch** would have shown. The first two have to agree
    /// and the third has to be badly wrong, or there was no accuracy problem to solve and the cheaper
    /// preview should have shipped.
    func testAStrokeThickerThanTheEraserPreviewsTheNothingThatTheCutActuallyTakes() {
        let thick = stroke(line(y: 128, from: 40, to: 216), size: 40)
        let build = { VectorCanvas(size: Self.canvasSize, strokes: [thick]) }
        let gesture = drag(x: 128, from: 96, to: 160)
        let nib = opaqueBrush(size: 8)

        let original = build().render()

        let cut = build()
        XCTAssertTrue(cut.erase(alongPath: gesture, brush: nib, size: 8, mode: .cutPoints),
                      "Setup: an 8pt eraser drawn across a 40pt line must still cut the geometry")
        XCTAssertEqual(cut.strokes.count, 2, "Setup: the line should end up in two pieces")
        let afterLift = cut.render()

        let preview = previewed(build(), gesture: gesture, brush: nib, size: 8).renderToUIImage()
        let footprint = footprintPunched(build(), gesture: gesture, brush: nib, size: 8).renderToUIImage()

        let removedByLift = pixelsChanged(original, afterLift)
        let removedByPreview = pixelsChanged(original, preview)
        let removedByFootprint = pixelsChanged(original, footprint)

        XCTAssertEqual(removedByLift, 0, """
            The premise of this whole test: cutting a 40pt line with an 8pt eraser removes geometry \
            and no ink, because the two surviving pieces' round caps close the 8pt gap. If this ever \
            becomes non-zero the caps have changed, and the preview's arithmetic has to change with \
            them. (This is Mode 2 as it has always behaved — the preview did not introduce it.)
            """)
        XCTAssertEqual(removedByPreview, 0, """
            …so the preview must show nothing going away either. It removed \(removedByPreview) \
            pixels, every one of which would reappear under the artist's hand the instant they \
            lifted off.
            """)
        XCTAssertGreaterThan(removedByFootprint, 250, """
            A footprint punch is supposed to be badly wrong here — if it is not, this scene is not \
            exercising the accuracy problem and the cheaper preview should have shipped. It opens a \
            \(removedByFootprint)-pixel notch in a line the cut does not visibly touch.
            """)
    }

    /// The same claim where the cut *does* take ink: an eraser wider than the line. Here the caps eat
    /// the stroke's own diameter out of the gap, so the footprint punch is wrong the other way — it
    /// shows the full nib-wide bite when only the middle of it survives as a hole.
    func testAnEraserWiderThanTheLinePreviewsTheGapMinusTheCapsThatGrowBack() {
        let thick = stroke(line(y: 128, from: 30, to: 226), size: 40)
        let build = { VectorCanvas(size: Self.canvasSize, strokes: [thick]) }
        let gesture = drag(x: 128, from: 80, to: 176)
        let nib = opaqueBrush(size: 72)

        let original = build().render()
        let cut = build()
        XCTAssertTrue(cut.erase(alongPath: gesture, brush: nib, size: 72, mode: .cutPoints))
        let afterLift = cut.render()

        let preview = previewed(build(), gesture: gesture, brush: nib, size: 72).renderToUIImage()
        let footprint = footprintPunched(build(), gesture: gesture, brush: nib, size: 72).renderToUIImage()

        let removedByLift = pixelsChanged(original, afterLift)
        let removedByFootprint = pixelsChanged(original, footprint)
        XCTAssertGreaterThan(removedByLift, 500, "Setup: a 72pt eraser must take a real bite")

        let previewPop = pixelsChanged(preview, afterLift)
        let footprintPop = pixelsChanged(footprint, afterLift)

        XCTAssertLessThan(Double(previewPop) / Double(removedByLift), 0.05, """
            The preview must show what the lift removes. \(previewPop) pixels change between the \
            preview and the committed cut against \(removedByLift) the cut removes — that is ink \
            appearing or vanishing at the moment the finger lifts. (Not required to be zero: Mode 2 \
            clears each surviving piece's `lattice`, so a piece re-anchors its dab phase at its own \
            first sample and its far end can move by up to one dab spacing. That is a property of \
            the commit, not of the preview.)
            """)
        XCTAssertGreaterThan(Double(footprintPop) / Double(removedByLift), 0.5, """
            A footprint punch removes the whole nib-wide swathe (\(removedByFootprint) pixels) where \
            the cut removes only what the two caps do not grow back over (\(removedByLift)), so \
            \(footprintPop) pixels would pop back on lift against the shipped preview's \(previewPop).
            """)
    }

    /// The same claim on the ordinary line-art case — a thin stroke and a middling eraser — so the
    /// two extreme scenes above are not carrying the whole file.
    func testAThinStrokePreviewsExactlyWhatTheCutTakes() {
        let thin = stroke(line(y: 128, from: 40, to: 216), size: 8)
        let build = { VectorCanvas(size: Self.canvasSize, strokes: [thin]) }
        let gesture = drag(x: 128, from: 96, to: 160)
        let nib = opaqueBrush(size: 24)

        let cut = build()
        XCTAssertTrue(cut.erase(alongPath: gesture, brush: nib, size: 24, mode: .cutPoints))
        let afterLift = cut.render()
        let preview = previewed(build(), gesture: gesture, brush: nib, size: 24).renderToUIImage()

        let removedByLift = pixelsChanged(build().render(), afterLift)
        XCTAssertGreaterThan(removedByLift, 100, "Setup: the cut should take a visible bite")
        XCTAssertLessThan(Double(pixelsChanged(preview, afterLift)) / Double(removedByLift), 0.05,
                          "The preview must agree with the lift on an ordinary thin line too")
    }

    /// **A stroke crossing the cut but not being cut keeps its ink — in the commit.** Stated here as
    /// the known limit of the preview rather than as a passing property, because the preview draws
    /// into a *flattened* copy of the layer: a stroke whose ink overlaps a doomed span, but whose
    /// centreline stays outside the eraser, has its overlapping pixels erased out of the preview and
    /// painted back on lift.
    ///
    /// The assertion is on the size of the effect, so it stays small rather than being forgotten:
    /// the region at risk is the overlap of two strokes inside one eraser footprint, and it is
    /// bounded by that. If a change ever makes this large, the preview needs to re-render the
    /// affected strokes rather than draw into a flat copy — and that is the term Mode 3 pays.
    func testInkThatSurvivesTheCutIsBrieflyErasedFromTheFlattenedPreview() {
        let horizontal = stroke(line(y: 128, from: 40, to: 216), size: 20)
        let vertical = stroke(StrokeSamples((0..<17).map { VectorSample(x: 128, y: 40 + CGFloat($0) * 11, pressure: 1) },
                                            channels: .pressureOnly), size: 20)
        // The nib travels along y = 128 well to the left of x = 128, so it reaches the horizontal
        // line's centreline and never the vertical one's: only the horizontal stroke is cut.
        let build = { VectorCanvas(size: Self.canvasSize, strokes: [horizontal, vertical]) }
        let gesture = StrokeSamples((0..<12).map { VectorSample(x: 60 + CGFloat($0) * 3, y: 128, pressure: 1) },
                                    channels: .pressureOnly)
        let nib = opaqueBrush(size: 30)

        let cut = build()
        XCTAssertTrue(cut.erase(alongPath: gesture, brush: nib, size: 30, mode: .cutPoints))
        XCTAssertEqual(cut.strokes.count, 3, "Setup: the horizontal line cut in two, the vertical intact")
        let afterLift = cut.render()
        let preview = previewed(build(), gesture: gesture, brush: nib, size: 30).renderToUIImage()

        let removedByLift = pixelsChanged(build().render(), afterLift)
        let pop = pixelsChanged(preview, afterLift)
        XCTAssertGreaterThan(removedByLift, 100, "Setup: the cut should take a visible bite")
        XCTAssertLessThan(Double(pop) / Double(removedByLift), 0.10, """
            The gesture does not reach the vertical stroke, so nothing of it should be missing from \
            the preview beyond dab-phase noise: \(pop) pixels differ against \(removedByLift) \
            removed. A large number here means the flattened-copy limit in this test's doc comment \
            has grown teeth and the preview needs re-rendering rather than drawing into a flat copy.
            """)
    }

    /// A semi-transparent stroke: the punch is `.destinationOut` at the stroke's own alpha, so it
    /// removes most of the ink rather than all of it and a faint ghost survives until lift. Recorded
    /// as a measurement rather than asserted tightly, because the direction is the safe one — the
    /// preview shows slightly *less* being removed than the cut will remove, never more — and
    /// tightening it would mean over-punching whatever sits underneath.
    func testASemiTransparentStrokeLeavesAFaintGhostUnderThePreview() {
        let translucent = stroke(line(y: 128, from: 40, to: 216), size: 24, opacity: 0.4)
        let build = { VectorCanvas(size: Self.canvasSize, strokes: [translucent]) }
        let gesture = drag(x: 128, from: 96, to: 160)
        let nib = opaqueBrush(size: 12)

        let cut = build()
        XCTAssertTrue(cut.erase(alongPath: gesture, brush: nib, size: 12, mode: .cutPoints))
        let afterLift = cut.render()
        let preview = previewed(build(), gesture: gesture, brush: nib, size: 12).renderToUIImage()

        let removedByLift = pixelsChanged(build().render(), afterLift)
        let removedByPreview = pixelsChanged(build().render(), preview)
        XCTAssertGreaterThan(Double(removedByPreview) / Double(removedByLift), 0.9,
                             "The preview should still take away nearly all of a 40%-opacity "
                             + "stroke's doomed span — \(removedByPreview) of \(removedByLift)")
    }
}
