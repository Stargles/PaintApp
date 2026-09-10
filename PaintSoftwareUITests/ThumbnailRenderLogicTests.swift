import Combine
import XCTest
import UIKit

/// **A cel thumbnail never asks a vector cel for a canvas-sized picture** — the structural half of
/// BUGS.md's *"the debounced thumbnail regen renders the whole canvas on the main thread"*, plus the
/// pin that says the picture it gets instead still looks like the cel.
///
/// The owner:
///
/// > *"When I try to lay strokes down and undo it, I am met with a lot of lagspikes and stutter when
/// > the brush is lifted. … the canvas size should not ever impede on main thread lag."*
///
/// **The assertion that protects this is a count, not a duration.** `CanvasManager.init` debounces the
/// regen onto `RunLoop.main`, so the work lands on the main thread 400 ms after every stroke and every
/// undo; what made it expensive was `PixelOps.rasterizeUncached` fetching the vector tier at the
/// *canvas's* resolution and resampling it into a 480-point box. A wall-clock bound would say that on
/// this machine and nothing at all on the owner's iPad 9, and CLAUDE.md forbids one in the fast tier
/// besides. `VectorCanvas.rasterizations` counts canvas-sized walks and `reducedRasterizations`
/// counts the small ones, so "which size was asked for" is a number — `localContentBoundsRasterizations`'
/// idiom, one seam along. The timings live in `ThumbnailRenderBench`.
final class ThumbnailRenderLogicTests: XCTestCase {

    /// **`CanvasManager.maxCanvasExtent`, which is what the owner's `Test1` is** — 36 megapixels, and
    /// the size at which the resample this file is about was MEASURED at 34.1–35.1 ms in Release.
    private static let ownersCanvas = CGSize(width: 6000, height: 6000)

    /// The 480-point box `CanvasManager.celThumbnailRasterBound` fits a cel into on the way to the
    /// 120-point tile. Named here so the arithmetic below is the shipped arithmetic and not a
    /// second copy of it.
    private static var thumbnailFlattenSize: CGSize {
        RenderRequest.renderSize(fitting: ownersCanvas, within: CanvasManager.celThumbnailRasterBound)
    }

    private static let brush = Brush(name: "ThumbnailPin", tip: .round, size: 42,
                                     dab: BrushDabSettings(spacing: 0.3))

    /// A stroke long enough to be visible in a 120-point tile of a 6000-point canvas, which is a
    /// 50:1 reduction — anything thinner than this vanishes and the pixel assertions below would be
    /// comparing two empty tiles.
    private static func stroke(_ index: Int, canvas: CGSize, seedOffset: Int = 0) -> VectorStroke {
        var state = UInt64(bitPattern: Int64((index &+ seedOffset) &* 2_654_435_761 &+ 1))
            &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset = canvas.width * 0.1
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length = canvas.width * 0.35
        var samples = StrokeSamples(channels: .pressureOnly)
        for step in 0..<24 {
            let t = CGFloat(step) / 23
            samples.append(VectorSample(x: x0 + cos(angle) * t * length,
                                        y: y0 + sin(angle) * t * length,
                                        pressure: 0.5 + 0.5 * t))
        }
        return VectorStroke(brush: brush,
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: canvas.width * 0.012, opacity: 1, samples: samples,
                            composite: .paint, seed: UInt64(index &+ seedOffset &+ 1))
    }

    private func canvas(_ size: CGSize, strokes: Int, seedOffset: Int = 0) -> VectorCanvas {
        VectorCanvas(size: size,
                     strokes: (0..<strokes).map { Self.stroke($0, canvas: size, seedOffset: seedOffset) })
    }

    private func vectorCel(_ canvas: VectorCanvas) -> Cel {
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas.size))
        cel.vector = canvas
        return cel
    }

    override func setUp() {
        super.setUp()
        // The flatten memo is keyed on the cel's identity and size, so a leftover entry from another
        // suite could serve this one and every counter below would read zero for the wrong reason.
        PixelOps.clearRasterizeCache()
    }

    // MARK: - Which size the thumbnail asked for

    /// **The defect, as a count.** A cold cel on the owner's canvas, one thumbnail: the vector tier
    /// must be walked at the thumbnail's resolution and not at the canvas's.
    ///
    /// Both counters are asserted, and that pairing is the point rather than belt-and-braces: a
    /// thumbnail that rendered nothing at all would leave `rasterizations` at zero too, and the
    /// second assertion is what separates "asked for the small one" from "asked for nothing".
    func testAThumbnailWalksTheCelAtTheThumbnailsResolutionAndNotTheCanvass() {
        let canvas = canvas(Self.ownersCanvas, strokes: 6)
        let cel = vectorCel(canvas)
        XCTAssertEqual(canvas.rasterizations, 0, "the fixture rendered before the test did")

        let tile = CanvasManager.celThumbnailImage(for: cel, canvasSize: Self.ownersCanvas)

        XCTAssertEqual(canvas.rasterizations, 0,
                       "a cel thumbnail rasterized the vector tier at the canvas's own resolution "
                       + "\(canvas.rasterizations) time(s). On the owner's 6000x6000 document that is "
                       + "a 36-megapixel walk and a 34 ms resample, on the main thread, 400 ms after "
                       + "every stroke — BUGS.md's debounced-thumbnail entry")
        XCTAssertEqual(canvas.reducedRasterizations, 1,
                       "the thumbnail performed \(canvas.reducedRasterizations) reduced-resolution "
                       + "walks where exactly one was wanted; zero means it produced its picture some "
                       + "other way and the assertion above is passing for the wrong reason")
        XCTAssertEqual(tile.size, CanvasManager.celThumbnailSize,
                       "the tile came back at \(tile.size) rather than the 120-point box the "
                       + "timeline and layer panel draw")
    }

    /// **The same question asked of the shipped entry point**, so the count is about the app rather
    /// than about `celThumbnailImage` being called directly — `regenerateThumbnail` is what the
    /// debounced flush calls, and it resolves the cel and the derivation itself.
    func testRegeneratingACelThumbnailNeverRasterizesTheCanvas() {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.ownersCanvas
        manager.addVectorLayer()
        let canvas = canvas(Self.ownersCanvas, strokes: 6)
        manager.layers[0].cels[0].vector = canvas

        manager.regenerateThumbnail(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(canvas.rasterizations, 0,
                       "`regenerateThumbnail` drove \(canvas.rasterizations) canvas-sized "
                       + "rasterizations of a 6000x6000 cel on the main thread")
        XCTAssertEqual(canvas.reducedRasterizations, 1,
                       "`regenerateThumbnail` performed \(canvas.reducedRasterizations) "
                       + "reduced-resolution walks where one was wanted")
        XCTAssertNotNil(manager.layers[0].cels[0].thumbnail,
                        "no thumbnail was installed, so the counters above are about a regen that "
                        + "did not happen")
    }

    /// **The other direction, which is the one a careless clamp breaks silently.** A native flatten —
    /// every export, every parity test, the live canvas at the resolution the artist chose — must
    /// still get the canvas's own resolution. A request may only ask for *less*.
    func testANativeFlattenStillRendersTheCelAtTheCanvassOwnResolution() {
        let size = CGSize(width: 1024, height: 512)
        let canvas = canvas(size, strokes: 6)
        let cel = vectorCel(canvas)

        let flat = PixelOps.rasterize(cel: cel, canvasSize: size)

        XCTAssertEqual(canvas.rasterizations, 1,
                       "a native flatten performed \(canvas.rasterizations) canvas-sized walks; if "
                       + "this is zero the reduced path has swallowed the native one and every "
                       + "export is now a downsample")
        XCTAssertEqual(canvas.reducedRasterizations, 0,
                       "a native flatten took the reduced path \(canvas.reducedRasterizations) times")
        XCTAssertEqual(flat.cgImage?.width, Int(size.width),
                       "the native flatten came back \(flat.cgImage?.width ?? -1) pixels wide "
                       + "against a canvas of \(Int(size.width))")
    }

    /// **A request may only ask for *less*, in pixels** — the clamp itself, at the seam that owns it.
    ///
    /// Asserted on the returned image's **pixel width**, because that is the only place the clamp is
    /// observable. `PixelOps.rasterize`'s own buffer is whatever the caller asked for either way, and
    /// both counters read the same whether the vector tier came back at 512 pixels or 2048 — so the
    /// test one seam up (below) cannot see this, and it was measured not seeing it: with the clamp
    /// deleted and the branch relaxed, that test stayed green and this one goes red.
    ///
    /// Rendering above native invents no detail and costs four times the raster —
    /// `RenderRequest.renderSize(fitting:within:)`'s own rule, at the other end of the same seam.
    func testFittingIntoAnOversizedBufferDoesNotRenderAboveNative() {
        let size = CGSize(width: 512, height: 512)
        let canvas = canvas(size, strokes: 4)
        let frozen = canvas.freeze(quality: .full)

        let image = frozen.render(quality: .full, fittingInto: CGSize(width: 2048, height: 2048))

        XCTAssertEqual(image.cgImage?.width, 512,
                       "a cel asked to fill a buffer four times its own size came back "
                       + "\(image.cgImage?.width ?? -1) pixels wide — it rendered above native, which "
                       + "is four times the raster for no more detail")
        XCTAssertEqual(canvas.reducedRasterizations, 0,
                       "an oversized request took the reduced path \(canvas.reducedRasterizations) "
                       + "times")
    }

    /// **The same contract one seam up, in counters** — a *flatten* into an oversized buffer is a
    /// native render. Kept alongside the pixel assertion above rather than instead of it: this one
    /// says which path `PixelOps` took and that one says what came back, and only the pair covers
    /// both ways the clamp can be lost.
    func testAFlattenIntoABufferLargerThanTheCelDoesNotAskForMoreResolution() {
        let size = CGSize(width: 512, height: 512)
        let canvas = canvas(size, strokes: 4)
        let cel = vectorCel(canvas)

        let flat = PixelOps.rasterize(cel: cel, canvasSize: CGSize(width: 2048, height: 2048))

        XCTAssertEqual(canvas.rasterizations, 1,
                       "a flatten into an oversized buffer took \(canvas.rasterizations) native "
                       + "walks rather than one")
        XCTAssertEqual(canvas.reducedRasterizations, 0,
                       "a flatten into an oversized buffer took the reduced path "
                       + "\(canvas.reducedRasterizations) times")
        XCTAssertEqual(flat.cgImage?.width, 2048,
                       "the oversized flatten came back \(flat.cgImage?.width ?? -1) pixels wide")
    }

    /// **The pen-up case, which is the one the owner is describing** — at pen-up the display renders
    /// the cel, so `cachedImage` is warm by the time the debounced flush fires 400 ms later. A
    /// thumbnail that took that memo would be resampling 36 megapixels, which is **MEASURED at
    /// 34.1–35.1 ms** and is most of the cost this change removes: the memo is not the cheap answer here, it is the
    /// expensive one.
    ///
    /// The counter is read *across* the thumbnail rather than after it, so the fixture's own warming
    /// render is not being counted as the thumbnail's.
    func testAThumbnailStillWalksSmallWhenTheCelAlreadyHoldsACanvasSizedMemo() {
        let canvas = canvas(Self.ownersCanvas, strokes: 6)
        let cel = vectorCel(canvas)
        _ = canvas.render()                       // what `StrokeCanvasView.refreshDisplay` leaves
        let warmedBy = canvas.rasterizations
        XCTAssertEqual(warmedBy, 1, "the fixture did not warm the memo, so this test is the cold one")

        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: Self.ownersCanvas)

        XCTAssertEqual(canvas.rasterizations, warmedBy,
                       "the thumbnail drove \(canvas.rasterizations - warmedBy) further canvas-sized "
                       + "walks")
        XCTAssertEqual(canvas.reducedRasterizations, 1,
                       "the thumbnail performed \(canvas.reducedRasterizations) reduced walks with a "
                       + "warm canvas-sized memo standing — zero means it took the memo and paid the "
                       + "34 ms resample this change exists to remove")
    }

    // MARK: - What the reduced walk leaves behind

    /// **A reduced walk must memoize nothing**, or the next native render is served a picture at a
    /// twelfth of its resolution and the artist's canvas goes soft with no error anywhere.
    ///
    /// The operand that makes this mean something is the *pixel width* of the second render, not the
    /// counter: a memo poisoned by the reduced walk would still count as a hit and still hand back an
    /// image whose `size` is the canvas's, because a `UIImage` carries its scale.
    func testAThumbnailLeavesNoMemoForTheNativeRenderToInherit() {
        let size = CGSize(width: 1200, height: 1200)
        let canvas = canvas(size, strokes: 6)
        let cel = vectorCel(canvas)

        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)
        XCTAssertEqual(canvas.rasterizations, 0, "the thumbnail took the native path")

        let native = canvas.render()

        XCTAssertEqual(native.cgImage?.width, Int(size.width),
                       "the native render after a thumbnail came back "
                       + "\(native.cgImage?.width ?? -1) pixels wide against a canvas of "
                       + "\(Int(size.width)) — the reduced walk installed its picture as the memo")
        XCTAssertEqual(canvas.rasterizations, 1,
                       "the native render after a thumbnail performed \(canvas.rasterizations) "
                       + "canvas-sized walks; zero means it read a memo the reduced walk left")
    }

    /// **The primitive underneath all of the above: fewer pixels, the same extent in points.**
    ///
    /// Both halves are asserted because only the pair distinguishes the change from a no-op. The
    /// counters cannot see the raster's size, so a walk that took the reduced *route* into a
    /// canvas-sized *format* would satisfy every other test in this file while costing exactly what
    /// it did before. And the point size has to stay the canvas's, because that is what makes
    /// `UIImage.draw(in:)` place the picture correctly for every caller downstream.
    func testAReducedRenderIsFewerPixelsOverTheSameExtentInPoints() {
        let size = CGSize(width: 2400, height: 1200)
        let canvas = canvas(size, strokes: 4)

        let reduced = canvas.render(quality: .full, resolution: 0.1)

        XCTAssertEqual(reduced.cgImage?.width, 240,
                       "the reduced render came back \(reduced.cgImage?.width ?? -1) pixels wide at a "
                       + "resolution of 0.1 over a 2400-point canvas")
        XCTAssertEqual(reduced.cgImage?.height, 120,
                       "the reduced render came back \(reduced.cgImage?.height ?? -1) pixels tall")
        XCTAssertEqual(reduced.size, size,
                       "the reduced render reports \(reduced.size) points where the canvas is "
                       + "\(size) — every caller draws this into a rect sized in the canvas's own "
                       + "points, so a picture that has forgotten its extent lands in the wrong place")
    }

    /// **A thumbnail after a stroke costs the stroke** — the reduced path's own incremental append,
    /// and the assertion that says the cost is O(what changed) rather than O(the cel).
    ///
    /// **This is the arm that had to be measured into existence.** A reduced walk with no base of its
    /// own is O(every dab), which is fine on the owner's four strokes and **59.2 ms on a thousand**
    /// (PERFORMANCE.md §11.11c) — worse than the 3.5 ms resample it replaced. `lastRenderDabCount` is
    /// the operand, and it is a count rather than a clock: a full walk reports the whole cel's dabs
    /// and an append reports one stroke's, and here those differ by more than an order of magnitude.
    func testASecondThumbnailAfterAStrokeStampsOnlyThatStroke() {
        let size = CGSize(width: 2048, height: 1024)
        let canvas = canvas(size, strokes: 24)
        let cel = vectorCel(canvas)

        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)
        let wholeCelDabs = canvas.lastRenderDabCount
        XCTAssertGreaterThan(wholeCelDabs, 24, "the fixture stamped \(wholeCelDabs) dabs over 24 "
                             + "strokes, so there is nothing here to be incremental about")

        // The same `Cel` value: `FrozenCel.Identity` reads the canvas's live `version`, so appending
        // is already a fresh memo key and re-minting the cel would only change its id.
        canvas.addStroke(Self.stroke(24, canvas: size))
        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        XCTAssertLessThan(canvas.lastRenderDabCount, wholeCelDabs / 4,
                          "the thumbnail after an append stamped \(canvas.lastRenderDabCount) dabs "
                          + "against \(wholeCelDabs) for the twenty-four strokes before it — it "
                          + "walked the whole list rather than appending to the reduced picture it "
                          + "already had, which is O(the cel) where O(the stroke) was available")
        XCTAssertEqual(canvas.rasterizations, 0,
                       "the incremental thumbnail took \(canvas.rasterizations) canvas-sized walks; "
                       + "the base it appended to must be the reduced one, never `incrementalBase`")
    }

    /// **A thumbnail after an undo costs the rectangle the undo touched** — the reduced path's own
    /// region repair, which is the other half of O(what changed) and the half the owner's sentence is
    /// actually about ("*lay strokes down and undo it*").
    ///
    /// `restoreElements(_:changedInk:)` is the seam undo comes through and it declares `.region` when
    /// it can prove one, which for an undone append it always can — the departing stroke's footprint
    /// was measured by the walk that drew it.
    func testAThumbnailAfterAnUndoStampsOnlyWhatTheUndoTouched() {
        let size = CGSize(width: 2048, height: 1024)
        let canvas = canvas(size, strokes: 24)
        let before = canvas.elements
        canvas.addStroke(Self.stroke(24, canvas: size))
        let cel = vectorCel(canvas)

        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)
        let wholeCelDabs = canvas.lastRenderDabCount
        XCTAssertGreaterThan(wholeCelDabs, 25, "the fixture stamped \(wholeCelDabs) dabs")

        canvas.restoreElements(before, changedInk: nil)
        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        // **Not `< wholeCelDabs`, which was the first version of this line and could not fail.** A
        // full re-walk after an undo stamps *twenty-four* strokes where the reference stamped
        // twenty-five, so a bare "fewer than before" passes against the very code this is written to
        // catch — MEASURED by mutation: with the reduced bases removed, that spelling stayed green.
        // The fraction is what separates "repaired a rectangle" from "walked the list again".
        XCTAssertLessThan(canvas.lastRenderDabCount, wholeCelDabs / 2,
                          "the thumbnail after an undo stamped \(canvas.lastRenderDabCount) dabs "
                          + "against \(wholeCelDabs) for the whole cel — it re-walked the list "
                          + "instead of repairing the rectangle the undo declared")
        XCTAssertEqual(canvas.rasterizations, 0,
                       "the repaired thumbnail took \(canvas.rasterizations) canvas-sized walks")
    }

    /// **The incremental tile is the tile a cold walk would have drawn** —
    /// `IncrementalAppendLogicTests`' claim, one resolution down, and the thing that makes the two
    /// tests above a speed-up rather than a corner cut.
    ///
    /// Both operands are drawn by shipped code from the same display list: the left is the append
    /// path (a thumbnail, a stroke, a thumbnail), the right is a cold canvas holding exactly the
    /// elements the left one ended with. Byte-for-byte, because a source-over copy of the base
    /// followed by the tail's dabs *is* the walk — that equivalence is `renderLocalContent`'s own
    /// contract and it does not become approximate at a smaller scale.
    func testAnIncrementalThumbnailIsTheThumbnailAColdWalkWouldDraw() {
        let size = CGSize(width: 2048, height: 1024)
        let canvas = canvas(size, strokes: 24)
        let cel = vectorCel(canvas)
        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        canvas.addStroke(Self.stroke(24, canvas: size))
        let incremental = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        let cold = VectorCanvas(size: size, elements: canvas.elements)
        let fresh = CanvasManager.celThumbnailImage(for: vectorCel(cold), canvasSize: size)

        XCTAssertEqual(Self.maxChannelDelta(incremental, fresh), 0,
                       "a thumbnail reached by appending to the previous one differs from a thumbnail "
                       + "of the same list drawn cold by \(Self.maxChannelDelta(incremental, fresh) ?? -1) "
                       + "of 255 — the reduced append is not reproducing the walk")
    }

    /// **And the repaired tile is the tile a cold walk would draw**, which is the same claim for the
    /// undo path and is the one with a real hazard behind it.
    ///
    /// A repair *clears a rectangle out of the standing picture* and redraws inside it, so the clip's
    /// edge cuts through the base. `repairClip` rounds outward to whole raster pixels for exactly that
    /// reason — a fractional clip is antialiased and the outermost row comes back part-cleared and
    /// part-redrawn. **At a reduced resolution "whole pixel" is no longer "whole point"**: one raster
    /// pixel is `1 / resolution` points, and rounding to points would leave the seam this test looks
    /// for. Both operands are shipped code over one display list.
    ///
    /// **The tolerance is one rounding unit and it is not slack** — PERFORMANCE.md §11.11 measures a
    /// *native* repair against a cold full walk at worst **1 of 255** along the clip's own seam, so a
    /// zero here would be asserting something the native path does not manage either. MEASURED at
    /// exactly that: **1** with the clip snapped to raster pixels and **11** with it snapped to
    /// points, which is what says the snapping is load-bearing rather than tidy.
    func testARepairedThumbnailIsTheThumbnailAColdWalkWouldDraw() {
        let size = CGSize(width: 2048, height: 1024)
        let canvas = canvas(size, strokes: 24)
        let before = canvas.elements
        canvas.addStroke(Self.stroke(24, canvas: size))
        let cel = vectorCel(canvas)
        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        // `restoreElements` is undo's own seam and declares the rectangle, which is what puts the
        // reduced slot's `regionBase` in play — a `bumpVersion()` here would declare `.everything`
        // and this test would silently be about the full walk instead.
        canvas.restoreElements(before, changedInk: nil)
        let repaired = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        let cold = VectorCanvas(size: size, elements: before)
        let fresh = CanvasManager.celThumbnailImage(for: vectorCel(cold), canvasSize: size)

        XCTAssertLessThanOrEqual(Self.maxChannelDelta(repaired, fresh) ?? 255, 1,
                                 "a thumbnail reached by repairing the rectangle an undo declared "
                                 + "differs from a cold thumbnail of the same list by "
                                 + "\(Self.maxChannelDelta(repaired, fresh) ?? -1) of 255, where one "
                                 + "rounding unit is what §11.11 measures for the native repair. A "
                                 + "seam along the clip is what a repair clip snapped to whole "
                                 + "*points* rather than whole raster pixels produces — that scores 11")
    }

    /// **The reduced picture is memory, and it is charged and freed like every other memo.** ~0.9 MiB
    /// a cel is nothing next to a 64 MiB canvas render and it is not nothing across the 300-1000 cels
    /// a real scene holds, so `VectorRenderCache` has to be able to see and drop it.
    func testTheReducedPictureIsChargedToTheRenderCacheAndFreedWithIt() {
        let size = CGSize(width: 2048, height: 1024)
        let canvas = canvas(size, strokes: 6)
        let cel = vectorCel(canvas)
        XCTAssertFalse(canvas.hasCachedImage, "the fixture is holding a picture before the test drew one")

        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)

        XCTAssertTrue(canvas.hasCachedImage,
                      "a cel holding a reduced thumbnail picture reports no cached image, so eviction "
                      + "would read `nothing here` off a canvas holding a bitmap")
        let charged = canvas.cachedImageBytes
        XCTAssertGreaterThan(charged, 0,
                             "the reduced picture is charged \(charged) bytes")
        XCTAssertLessThan(charged, Int(size.width * size.height * 4) / 4,
                          "the reduced picture is charged \(charged) bytes against a canvas-sized "
                          + "image's \(Int(size.width * size.height * 4)) — it is supposed to be the "
                          + "thumbnail box, so a figure near the canvas's means the walk did not "
                          + "actually shrink")

        canvas.dropCachedImage()
        XCTAssertFalse(canvas.hasCachedImage,
                       "eviction left the reduced picture behind, which is pixels it did not free")
        XCTAssertEqual(canvas.cachedImageBytes, 0,
                       "eviction left \(canvas.cachedImageBytes) bytes charged")
    }

    // MARK: - What is drawn

    /// **The tile still looks like the cel** — the route changed, so the picture has to be pinned
    /// against the route it replaced rather than only counted.
    ///
    /// **Both operands come off one `VectorCanvas`**, and that is deliberate: a per-arm fixture would
    /// be comparing two allocations before it compared any pixels (CLAUDE.md's *"a table that builds
    /// a fresh fixture per row is comparing allocation addresses"*). The reference arm is
    /// `rasterizeUncached`'s old three lines for a vector-only cel — render the tier at the canvas's
    /// own resolution, draw it into the 480-point box, hand that to `ThumbnailRenderer` — so it is the
    /// shipped code as it stood, not a re-derivation of what it ought to have produced.
    ///
    /// **Bounded rather than byte-for-byte, and both the bound and its headroom are measured.**
    /// Source-over of overlapping dabs is not linear, so resolving coverage at 480 points is not
    /// identical to resolving it at 6000 and averaging down. MEASURED on this fixture's finished
    /// 120-point tile: **27 of 255** at worst, and the control arm below — the same route over an
    /// entirely different drawing — scores **255**. The bound is 64, which is 2.4x the difference the
    /// resampling actually produces and a quarter of what a wrong picture produces.
    func testTheReducedTileMatchesTheTileTheCanvasSizedRouteProduced() {
        let canvas = canvas(Self.ownersCanvas, strokes: 8)
        let cel = vectorCel(canvas)

        let reduced = CanvasManager.celThumbnailImage(for: cel, canvasSize: Self.ownersCanvas)
        let reference = Self.canvasSizedRouteTile(canvas)

        let delta = Self.maxChannelDelta(reduced, reference)
        XCTAssertNotNil(delta, "the two tiles are not the same dimensions, so nothing below compares "
                        + "anything")
        XCTAssertLessThanOrEqual(delta ?? 255, 64,
                                 "the thumbnail drawn at thumbnail resolution differs from the one "
                                 + "drawn at canvas resolution by \(delta ?? -1) of 255 at worst. "
                                 + "The two are allowed to differ — coverage resolved at 480 points "
                                 + "is not coverage resolved at 6000 and averaged — but not by this "
                                 + "much: at this magnitude it is ink in the wrong place, not "
                                 + "resampling")

        // **The control, and it is what makes the bound above an assertion rather than a hope.** A
        // tile of a *different* drawing on the same canvas has to score far worse than the bound, or
        // the bound is loose enough to accept anything.
        let other = self.canvas(Self.ownersCanvas, strokes: 8, seedOffset: 4096)
        let wrong = Self.canvasSizedRouteTile(other)
        let controlDelta = Self.maxChannelDelta(reduced, wrong) ?? 0
        XCTAssertGreaterThan(controlDelta, 128,
                             "a tile of an entirely different drawing scored \(controlDelta) against "
                             + "this one, which is inside the tolerance the assertion above uses — "
                             + "so that assertion cannot distinguish a faithful thumbnail from any "
                             + "other picture and the fixture needs more contrast")
    }

    /// **And it is not blank**, which is the failure the bounded compare above cannot see on its own:
    /// two mostly-empty tiles are within any tolerance of each other.
    ///
    /// Coverage rather than a pixel probe, because where a stroke lands is the RNG's business and an
    /// assertion on one coordinate would be an assertion on the seed. MEASURED: **488 inked pixels
    /// against the canvas-sized route's 490**, so the bounds below are ±25% around a difference that
    /// is in practice 0.4%.
    func testTheReducedTileCarriesTheSameAmountOfInkAsTheCanvasSizedRoute() {
        let canvas = canvas(Self.ownersCanvas, strokes: 8)
        let cel = vectorCel(canvas)

        let reduced = CanvasManager.celThumbnailImage(for: cel, canvasSize: Self.ownersCanvas)
        let reference = Self.canvasSizedRouteTile(canvas)

        let inked = Self.inkedPixels(reduced), referenceInked = Self.inkedPixels(reference)
        XCTAssertGreaterThan(referenceInked, 40,
                             "the reference tile carries only \(referenceInked) inked pixels, so the "
                             + "fixture's strokes are too thin to survive a 50:1 reduction and this "
                             + "test is comparing two empty tiles")
        XCTAssertGreaterThan(inked, referenceInked * 3 / 4,
                             "the reduced tile carries \(inked) inked pixels against the "
                             + "canvas-sized route's \(referenceInked) — ink went missing")
        XCTAssertLessThan(inked, referenceInked * 5 / 4,
                          "the reduced tile carries \(inked) inked pixels against the canvas-sized "
                          + "route's \(referenceInked) — repeated partial coverage composites darker "
                          + "than its own average, which is expected and is supposed to be a few "
                          + "percent rather than a third")
    }

    // MARK: - Helpers

    /// **`PixelOps.rasterizeUncached` as it stood for a vector-only cel**, followed by the tile
    /// downscale — the route this change replaced, kept here as the pin's other operand.
    private static func canvasSizedRouteTile(_ canvas: VectorCanvas) -> UIImage {
        let box = thumbnailFlattenSize
        let native = canvas.render(quality: .full)
        let flattened = UIGraphicsImageRenderer(size: box, format: PixelOps.transparentFormat())
            .image { _ in native.draw(in: CGRect(origin: .zero, size: box)) }
        return ThumbnailRenderer.render(flattened, canvasSize: canvas.size,
                                        thumbnailSize: CanvasManager.celThumbnailSize)
    }

    /// Nil when the two images are not the same pixel dimensions, so a caller cannot read a
    /// comparison out of two byte arrays of different lengths.
    private static func maxChannelDelta(_ a: UIImage, _ b: UIImage) -> Int? {
        guard let left = a.cgImage, let right = b.cgImage,
              left.width == right.width, left.height == right.height,
              let lhs = CanvasFixture.rgbaBytes(left), let rhs = CanvasFixture.rgbaBytes(right),
              lhs.count == rhs.count else { return nil }
        var worst = 0
        for i in 0..<lhs.count { worst = max(worst, abs(Int(lhs[i]) - Int(rhs[i]))) }
        return worst
    }

    /// Pixels whose alpha is past a quarter — "there is ink here", counted rather than located.
    private static func inkedPixels(_ image: UIImage) -> Int {
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return 0 }
        var count = 0
        for index in stride(from: 3, to: bytes.count, by: 4) where bytes[index] > 64 { count += 1 }
        return count
    }

    // MARK: - The debounced flush renders off the main actor (PERFORMANCE.md §18)
    //
    // §11.11c bounded the *tile* at 480² whatever the canvas is, and the flatten that fills it still
    // walked every element the cel holds — MEASURED on the owner's iPad 9 in Release at **25.4 ms per
    // edit at 2048² with one stroke on the cel and 73.7 ms at forty**, on the main thread, 400 ms
    // after every stroke and every undo. It was the largest single term of an edit and the only one
    // that grew with the drawing. The pixels moved to `CanvasManager.thumbnailRegenQueue`; what has
    // to be pinned here is that they still *arrive*, and that a tile rendered against content the
    // artist has since changed is refused rather than installed stale.

    /// A canvas small enough that these tests are about ordering rather than about pixels, with ink
    /// that is genuinely visible in a 120-point tile.
    private static let deferredCanvas = CGSize(width: 512, height: 512)

    private func deferredManager() -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.deferredCanvas
        manager.addVectorLayer()
        manager.layers[0].cels[0].vector = canvas(Self.deferredCanvas, strokes: 4)
        // The fixture's own thumbnail is cleared so "a tile arrived" is observable at all. Without
        // this every assertion below would be reading whatever `addVectorLayer` happened to install.
        manager.layers[0].cels[0].thumbnail = nil
        return manager
    }

    /// Spins the main run loop for `seconds`. The install hops back through `Task { @MainActor }`,
    /// which cannot run while a synchronous test body holds the main actor, so nothing lands until
    /// this is called — which is exactly what makes the "not yet" assertions below deterministic
    /// rather than racy.
    private func pumpMainRunLoop(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// **The whole of the fix, as an ordering.** After the deferred flush returns, the queue is
    /// drained but no tile has been drawn; after the run loop turns, the tile is there and has ink in
    /// it.
    ///
    /// **The first assertion is the one that would redden a revert**, and it is not a timing race: a
    /// synchronous flush installs before the call returns, and the deferred one cannot install until
    /// the main actor is free. The second is what stops the first passing for the wrong reason — a
    /// flush that rendered nothing at all would also leave the tile nil.
    func testTheDebouncedFlushDrawsNoPixelsBeforeItReturnsAndStillInstallsTheTile() {
        let manager = deferredManager()
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)

        manager.flushPendingThumbnailRegensDeferred()

        XCTAssertNil(manager.layers[0].cels[0].thumbnail,
                     "the deferred flush installed a tile before it returned, which means the cel "
                     + "was flattened on the main thread — the 25.4-73.7 ms per edit PERFORMANCE.md "
                     + "§18 moved off it")
        XCTAssertTrue(manager.takePendingThumbnailRegens().isEmpty,
                      "the deferred flush left its own job in the pending queue, so the next "
                      + "debounce would render the same cel a second time")

        pumpMainRunLoop(0.4)

        guard let tile = manager.layers[0].cels[0].thumbnail else {
            return XCTFail("no tile ever arrived: the render was deferred and then lost, which is "
                           + "the failure a careless queue introduces and the one nothing else here "
                           + "would catch")
        }
        XCTAssertEqual(tile.size, CanvasManager.celThumbnailSize,
                       "the tile arrived at \(tile.size) rather than the 120-point box the timeline "
                       + "and the layer panel draw")
        XCTAssertGreaterThan(Self.inkedPixels(tile), 0,
                             "the tile that arrived is blank, so the cel's four strokes did not "
                             + "reach it and the assertion above is about an empty picture")
    }

    /// **A tile rendered against content the artist has since changed is refused, and the cel is
    /// re-queued so it is not left showing the previous drawing.**
    ///
    /// The mutation lands *after* the flush and *before* the run loop turns, which is precisely the
    /// window the version guard exists for and the one a synchronous flush never had. Both halves are
    /// asserted: the tile finally on the cel is the picture of what the cel holds **now**, and it is
    /// not the picture of what it held when the render started.
    ///
    /// **Deleting the guard reddens this**, and it is worth saying which assertion: the installed
    /// tile would be the stale one, so the equality against the fresh render fails and the
    /// inequality against the stale one fails with it.
    func testATileRenderedAgainstContentThatHasChangedIsRefusedAndTheCelIsRepainted() {
        let manager = deferredManager()
        let staleTile = CanvasManager.celThumbnailImage(for: manager.layers[0].cels[0],
                                                        canvasSize: Self.deferredCanvas)
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)

        manager.flushPendingThumbnailRegensDeferred()
        // The artist draws again while the tile is still being drawn. `addStroke` bumps the vector
        // tier's version, which is a field of the `LayerContentVersion` the render was captured at.
        manager.layers[0].cels[0].vector?.addStroke(Self.stroke(99, canvas: Self.deferredCanvas,
                                                                seedOffset: 500))

        // Long enough for the refused landing, the re-queue, the 400 ms debounce and the repaint.
        pumpMainRunLoop(1.2)

        let freshTile = CanvasManager.celThumbnailImage(for: manager.layers[0].cels[0],
                                                        canvasSize: Self.deferredCanvas)
        // Premise: the extra stroke really did change the picture. Without this the two comparisons
        // below would both hold under any implementation whatever.
        XCTAssertNotEqual(staleTile.pngData(), freshTile.pngData(),
                          "the fixture's extra stroke changed nothing in the tile, so this test "
                          + "cannot tell a refused stale tile from an installed one")
        guard let installed = manager.layers[0].cels[0].thumbnail else {
            return XCTFail("the cel was left with no tile at all: the stale render was refused and "
                           + "nothing repainted it, which is the failure the re-queue exists for")
        }
        XCTAssertEqual(installed.pngData(), freshTile.pngData(),
                       "the tile on the cel is not the picture the cel holds now")
        XCTAssertNotEqual(installed.pngData(), staleTile.pngData(),
                          "the tile on the cel is the picture the cel held before the artist's last "
                          + "stroke — the version guard in `installRegeneratedThumbnails` let a "
                          + "stale render through")
    }

    /// A layer deleted while its tile is in flight installs nothing and does not trap. The indices
    /// the render was resolved from are gone by the time it lands, which is why the install
    /// re-resolves by **id** rather than carrying an index across the queue.
    func testALayerDeletedWhileItsTileRendersInstallsNothing() {
        let manager = deferredManager()
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)

        manager.flushPendingThumbnailRegensDeferred()
        manager.layers.removeAll()

        pumpMainRunLoop(0.4)

        XCTAssertTrue(manager.layers.isEmpty,
                      "the landing put a layer back, which means it wrote through an index rather "
                      + "than resolving the layer by id")
    }

    // MARK: - The install itself: PERFORMANCE.md §18.6, the tile leaves `@Published layers`
    //
    // §18 took the thumbnail's *pixels* off the main thread and left the *install* writing
    // `CanvasManager.layers`. `Layer` and `Cel` are structs inside an `@Published` array, so putting
    // a 120x120 image on one block republished the document and every `ObservedObject` in the editor
    // rebuilt — MEASURED on the owner's iPad 9 in Release at ~43 ms of main-thread busy per edit,
    // 400 ms after every stroke and every undo, to deliver a picture that costs a fraction of a
    // millisecond to store.
    //
    // The tile is a `ThumbnailTile` reference cell now, so the write reaches a class and `layers` is
    // only read on the way to it. **That makes the install silent, which is the whole point and also
    // the whole hazard**: the two views that draw a tile can no longer find out by being rebuilt, so
    // `thumbnailInstalled` is what tells them and the tests below are as much about the send as
    // about the silence.

    /// Fresh pixels for a cel, through the shipped renderer so the tile under test is the tile the
    /// app would install.
    private func tile(_ manager: CanvasManager, layer: Int = 0, cel: Int = 0) -> UIImage {
        CanvasManager.celThumbnailImage(for: manager.layers[layer].cels[cel],
                                        canvasSize: Self.deferredCanvas)
    }

    /// **The measurement this pass exists for, as a count.**
    ///
    /// The two operands are the number of `objectWillChange` emissions `CanvasManager` makes across
    /// one `installThumbnail`, and zero. **The second half of the test is what makes the first half
    /// mean anything**: an ordinary stored-property write to the same cel, through the same array,
    /// with the same counter still attached — so a subscription that had quietly stopped working
    /// would fail here rather than pass above. Without it this is the classic green assertion whose
    /// operands are both nothing.
    func testInstallingATileRepublishesNothingWhileAnOrdinaryCelEditStillDoes() {
        let manager = deferredManager()
        let image = tile(manager)
        var publishes = 0
        let token = manager.objectWillChange.sink { _ in publishes += 1 }
        defer { token.cancel() }

        manager.installThumbnail(image, layerIndex: 0, celIndex: 0)

        XCTAssertEqual(publishes, 0,
                       "installing a cel tile republished `CanvasManager` \(publishes) time(s). "
                       + "That is a SwiftUI pass over the whole editor — MEASURED at ~43 ms on the "
                       + "owner's iPad 9 — raised to move a 120-point picture onto one timeline "
                       + "block. The tile must be written through `ThumbnailTile`, not through a "
                       + "stored property of `Cel`.")

        let before = publishes
        manager.layers[0].cels[0].startFrame += 1

        XCTAssertEqual(publishes, before + 1,
                       "an ordinary stored write to `layers[0].cels[0]` republished \(publishes - before) "
                       + "time(s) rather than once, so the counter above was not watching anything "
                       + "and the zero it reported is meaningless")
    }

    /// The silence is worth nothing if the tile does not arrive. Operands: the object on the cel
    /// afterwards, and the object handed to `installThumbnail` — identity, because a tile is
    /// replaced wholesale rather than edited.
    func testAnInstalledTileIsTheObjectTheCelReportsAfterwards() {
        let manager = deferredManager()
        let image = tile(manager)

        manager.installThumbnail(image, layerIndex: 0, celIndex: 0)

        XCTAssertTrue(manager.layers[0].cels[0].thumbnail === image,
                      "the cel is not carrying the image that was installed on it, so the write "
                      + "went somewhere the readers do not look")
        XCTAssertTrue(manager.layers[0].thumbnail === image,
                      "the layer rail's tile did not follow the cel under the playhead, which is "
                      + "the second of `installThumbnail`'s two writes")
    }

    /// **The send is the replacement for the SwiftUI pass, so it is pinned by the same test that
    /// pins the silence.** Operands: the locations `thumbnailInstalled` published, and the
    /// `(layerID, celID)` the document says was written.
    func testInstallingATileAnnouncesExactlyTheCelItLandedOn() {
        let manager = deferredManager()
        manager.addVectorLayer()
        var announced: [CanvasManager.CelLocation] = []
        let token = manager.thumbnailInstalled.sink { announced.append($0) }
        defer { token.cancel() }

        manager.installThumbnail(tile(manager, layer: 1), layerIndex: 1, celIndex: 0)

        let expected = CanvasManager.CelLocation(layerID: manager.layers[1].id,
                                                 celID: manager.layers[1].cels[0].id)
        XCTAssertEqual(announced, [expected],
                       "an install announced \(announced.count) location(s), \(announced). The "
                       + "timeline and the layer rail hear about a tile here and nowhere else since "
                       + "§18.6, so a missing or misaddressed send is a block that never repaints.")
    }

    /// A cleared tile has to be announced too, and it is the half a reader would not think to check.
    ///
    /// Operands: what the cel reads afterwards (nil), and the location the subject carried. The
    /// second is what would go red if `clearThumbnail` were flattened back into
    /// `layers[i].cels[j].thumbnail = nil` — which now writes the cell silently and leaves the old
    /// picture on the block.
    func testClearingATileAnnouncesItAsWellAsDroppingIt() {
        let manager = deferredManager()
        manager.installThumbnail(tile(manager), layerIndex: 0, celIndex: 0)
        var announced: [CanvasManager.CelLocation] = []
        let token = manager.thumbnailInstalled.sink { announced.append($0) }
        defer { token.cancel() }

        manager.clearThumbnail(layerIndex: 0, celIndex: 0)

        XCTAssertNil(manager.layers[0].cels[0].thumbnail,
                     "the cel still carries a tile after `clearThumbnail`")
        XCTAssertNil(manager.layers[0].thumbnail,
                     "the layer rail still carries the tile of a cel that has none")
        XCTAssertEqual(announced,
                       [CanvasManager.CelLocation(layerID: manager.layers[0].id,
                                                  celID: manager.layers[0].cels[0].id)],
                       "clearing a tile announced \(announced.count) location(s) rather than one, so "
                       + "the timeline block would keep drawing a picture the document has thrown "
                       + "away")
    }

    /// **A canvas resize is the operation that made `clearThumbnail` necessary**, because it moves
    /// the artwork inside the frame: a block left holding its old tile is drawing the wrong picture
    /// rather than a late one.
    ///
    /// Operands: the set of `(layerID, celID)` the resize announced, and the set of every cel in the
    /// document. Reverting the funnel to a bare assignment empties the first and reddens this.
    func testAResizeAnnouncesEveryCelWhoseTileItDropped() {
        let manager = deferredManager()
        manager.addVectorLayer()
        // **Placed past the end of the layer's existing block, and asserted.** `addCel` refuses a
        // frame another cel already covers and says so only in its return value; a fixture that let
        // that pass would leave one cel per layer, and this test would then be unable to tell a
        // per-cel announcement from a per-*layer* one.
        let free = manager.layers[0].cels.map(\.endFrame).max() ?? 1
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: free, frameCount: 1),
                      "the fixture could not give layer 0 a second cel at frame \(free), so the "
                      + "document under test has one cel per layer")
        for layerIndex in manager.layers.indices {
            for celIndex in manager.layers[layerIndex].cels.indices {
                manager.installThumbnail(tile(manager, layer: layerIndex, cel: celIndex),
                                         layerIndex: layerIndex, celIndex: celIndex)
            }
        }
        let everyCel = Set(manager.layers.flatMap { layer in
            layer.cels.map { CanvasManager.CelLocation(layerID: layer.id, celID: $0.id) }
        })
        XCTAssertEqual(everyCel.count, 3,
                       "the fixture has \(everyCel.count) cels rather than three — two on one layer "
                       + "and one on another, which is the shape that tells a per-cel announcement "
                       + "apart from a per-layer or a document-wide one")
        var announced: Set<CanvasManager.CelLocation> = []
        let token = manager.thumbnailInstalled.sink { announced.insert($0) }
        defer { token.cancel() }

        manager.setCanvasPadding(12)

        XCTAssertTrue(manager.layers.allSatisfy { $0.cels.allSatisfy { $0.thumbnail == nil } },
                      "a cel kept a tile of the old extent across a resize")
        XCTAssertEqual(announced, everyCel,
                       "the resize announced \(announced.count) of \(everyCel.count) cels, so the "
                       + "blocks it did not name are still drawing the artwork at its old position "
                       + "in the frame")
    }

    /// **The semantics the reference cell changes, stated rather than left to be discovered.**
    ///
    /// Two `Cel` values with the same `id` are the same cel at two moments, and they share one tile:
    /// a copy taken for an undo snapshot or an off-actor render batch reads the picture the live cel
    /// has *now*. That is deliberate — a copy carrying a stale tile is the failure this arrangement
    /// cannot have — and it is the one place a reader of `Cel` could be surprised, so it is pinned.
    ///
    /// Operands: what the copy reports, and the image written through the live cel afterwards. Under
    /// a stored `UIImage?` the copy would report the older one, so this is a real fork and not a
    /// truth of value semantics.
    func testTwoValuesOfTheSameCelShareOneTile() {
        let manager = deferredManager()
        let copyTakenFirst = manager.layers[0].cels[0]
        let image = tile(manager)

        manager.installThumbnail(image, layerIndex: 0, celIndex: 0)

        XCTAssertTrue(copyTakenFirst.thumbnail === image,
                      "a `Cel` value copied out of the document before the install is reporting a "
                      + "different tile from the live cel of the same id, so the tile is stored per "
                      + "*copy* rather than per cel — which is how an off-actor render batch or an "
                      + "undo snapshot comes to hold a picture nobody can invalidate")
    }

    /// **And the boundary of that sharing: a duplicate is a different cel.**
    ///
    /// `duplicateLayer` mints new `id`s, so each copied cel gets a `ThumbnailTile` of its own and the
    /// picture is copied into it. Operands: what the duplicate's cel reads after the *original* is
    /// repainted, and the tile the duplicate was made with. They must differ from the original's new
    /// one — sharing here would repaint both blocks from one drawing and neither artist-visible
    /// symptom would point back at this line.
    func testADuplicatedCelGetsATileOfItsOwnRatherThanAShareOfTheOriginals() {
        let manager = deferredManager()
        let original = tile(manager)
        manager.installThumbnail(original, layerIndex: 0, celIndex: 0)

        manager.duplicateLayer(at: 0)
        guard let duplicateIndex = manager.layers.indices.first(where: { $0 != 0 })
        else { return XCTFail("duplicateLayer produced no second layer to compare against") }
        XCTAssertTrue(manager.layers[duplicateIndex].cels[0].thumbnail === original,
                      "the duplicate did not start out carrying the original's picture")

        let repainted = tile(manager)
        manager.installThumbnail(repainted, layerIndex: 0, celIndex: 0)

        XCTAssertTrue(manager.layers[duplicateIndex].cels[0].thumbnail === original,
                      "repainting the original's tile changed the duplicate's as well, so the two "
                      + "cels share one `ThumbnailTile` — `duplicateLayer` must assign the image "
                      + "into the new cel's own cell rather than carrying the field across")
        XCTAssertFalse(repainted === original,
                       "the fixture rendered the same object twice, so the assertion above would "
                       + "hold whether the cells were shared or not")
    }

    /// **End to end through the shipped flush**, so the silence is pinned at the seam the artist's
    /// edit actually reaches rather than only at `installThumbnail`.
    ///
    /// `flushPendingThumbnailRegens()` is the synchronous spelling — the deferred one is pinned two
    /// tests up — and it is used here precisely because it installs before it returns, which makes
    /// the publish count deterministic instead of a function of what else turned the run loop.
    func testAWholeThumbnailFlushRepublishesNothingAndStillLandsTheTile() {
        let manager = deferredManager()
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        var publishes = 0
        let token = manager.objectWillChange.sink { _ in publishes += 1 }
        defer { token.cancel() }

        manager.flushPendingThumbnailRegens()

        XCTAssertEqual(publishes, 0,
                       "a thumbnail flush republished the document \(publishes) time(s), which is the "
                       + "whole-editor SwiftUI pass PERFORMANCE.md §18.6 set out to stop raising")
        guard let landed = manager.layers[0].cels[0].thumbnail else {
            return XCTFail("the flush published nothing and installed nothing, so the zero above is "
                           + "the cost of doing no work rather than of doing it quietly")
        }
        XCTAssertEqual(landed.size, CanvasManager.celThumbnailSize,
                       "the flush installed a \(landed.size) image rather than the 120-point tile "
                       + "the timeline draws")
    }

    /// **Undo has to leave a correct tile, and it is the case the owner would find first.**
    ///
    /// Operands: the tile on the cel after undoing a stroke, and a cold render of what the cel holds
    /// at that point. They must match; and the tile must differ from the one that was on the cel
    /// while the stroke existed, or the block is showing a drawing the document no longer has.
    func testUndoingAStrokeLeavesTheTileShowingWhatTheCelHoldsAfterwards() throws {
        let manager = deferredManager()
        // The fixture starts with no tile on purpose (see `deferredManager`), so the flush needs a
        // job: without this the "before" tile is nil and the comparison below has one operand.
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        manager.flushPendingThumbnailRegens()
        let beforeStroke = try XCTUnwrap(manager.layers[0].cels[0].thumbnail,
                                         "the fixture never got a starting tile to compare against")
        let vector = try XCTUnwrap(manager.layers[0].cels[0].vector, "the fixture cel has no vector tier")
        let elementsBefore = vector.elements
        vector.addStroke(Self.stroke(77, canvas: Self.deferredCanvas, seedOffset: 900))
        manager.registerVectorElementsUndo(
            vectorCanvas: vector, oldElements: elementsBefore, newElements: vector.elements,
            layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id,
            label: .brushStroke, swap: .addsAndRemoves(ink: nil))
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        manager.flushPendingThumbnailRegens()
        let withStroke = try XCTUnwrap(manager.layers[0].cels[0].thumbnail)
        // Premise: the stroke changed the picture at all. Without it the comparison after the undo
        // would hold under any implementation, including one that never repaints.
        XCTAssertNotEqual(beforeStroke.pngData(), withStroke.pngData(),
                          "the extra stroke did not change the tile, so this test cannot tell a "
                          + "repainted block from a frozen one")

        manager.undo()
        manager.flushPendingThumbnailRegens()

        let after = try XCTUnwrap(manager.layers[0].cels[0].thumbnail,
                                  "the cel has no tile at all after an undo")
        let cold = tile(manager)
        XCTAssertEqual(after.pngData(), cold.pngData(),
                       "the tile after the undo is not a picture of what the cel now holds")
        XCTAssertNotEqual(after.pngData(), withStroke.pngData(),
                          "the block is still showing the stroke the artist undid")
    }
}
