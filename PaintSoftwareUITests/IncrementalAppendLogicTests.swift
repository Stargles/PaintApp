import XCTest
import UIKit
import CoreGraphics

/// **A vector cel's render, made incremental for the case the artist is actually in.**
///
/// PERFORMANCE.md §11 measured the problem on the owner's own iPad: committing one stroke to a cel
/// re-stamps *every dab the cel holds*, at 3.16 µs a dab, so their current 190-stroke density is
/// already ~142 ms behind the pen and a thousand strokes is 0.74 s. `VectorCanvas.Damage` is what
/// each mutation now says about itself, and `appendableBase(quality:)` is what the render does with
/// it.
///
/// **Two families of test here, and the second is the one that matters.** The first pins that an
/// append draws the same picture the full walk would; the second pins that everything else **falls
/// back to the full walk** — because a new element kind added later must be slow-and-correct, and
/// the only thing that can say so is a test that goes red when it is fast-and-wrong.
///
/// **Every equivalence assertion has two operands, and both are produced by shipped code from the
/// same display list**: one canvas built cold from the elements (guaranteed full walk, since a fresh
/// canvas has no base) and one that got there by appending. Comparing an incremental result against
/// a picture the test drew itself would only pin the test's own arithmetic.
final class IncrementalAppendLogicTests: XCTestCase {

    // MARK: - The scene
    //
    // Small (128×96) on purpose: these are logic-tier tests run constantly, and the byte comparison
    // is over every pixel. The behaviours under test are all about *order*, not about area.

    private static let canvasSize = CGSize(width: 128, height: 96)

    private static func brush(_ blend: BrushBlendMode = .normal) -> Brush {
        Brush(name: "Append", shape: .softRound, size: 6, spacingFraction: 0.3, blendMode: blend)
    }

    /// A short deterministic arc, placed so that strokes overlap each other — overlap is what makes
    /// a blend mode and an eraser visible at all, so a fixture of disjoint marks would pass every
    /// isolation test by accident.
    private static func stroke(_ index: Int, blend: BrushBlendMode = .normal,
                               composite: StrokeComposite = .paint) -> VectorStroke {
        let x = 16 + CGFloat((index * 13) % 84)
        let y = 20 + CGFloat((index * 29) % 52)
        let samples = (0..<6).map { step -> VectorSample in
            let t = CGFloat(step) / 5
            return VectorSample(x: x + t * 26, y: y + sin(t * .pi) * 14,
                                pressure: 0.4 + 0.6 * t)
        }
        return VectorStroke(brush: brush(blend),
                            color: CodableColor(red: Double((index % 3)) / 3,
                                                green: 0.2, blue: 0.7, alpha: 1),
                            size: 6, opacity: 0.9, samples: samples,
                            composite: composite,
                            seed: UInt64(index &+ 1))
    }

    private static func eraserStroke() -> VectorStroke {
        let samples = (0..<8).map { step -> VectorSample in
            let t = CGFloat(step) / 7
            return VectorSample(x: 12 + t * 104, y: 48, pressure: 1)
        }
        return VectorStroke(brush: brush(),
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 10, opacity: 1, samples: samples, composite: .erase)
    }

    private static func fill() -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 60, width: 60, height: 24),
                                       transform: nil),
                          color: CodableColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1),
                          opacity: 0.7)
    }

    private static func canvas(_ n: Int, blend: BrushBlendMode = .normal) -> VectorCanvas {
        VectorCanvas(size: canvasSize, elements: (0..<n).map { .stroke(stroke($0, blend: blend)) })
    }

    // MARK: - Comparing two renders

    /// The raw pixels of a `UIImage`'s own backing bitmap, plus a description of its layout.
    ///
    /// **Deliberately not `RasterVectorParity.premultipliedBytes`, which re-draws through a
    /// normalising context.** That is right for comparing two *tiers* whose producers chose
    /// different bit layouts; here both images come out of the same `UIGraphicsImageRenderer` with
    /// the same format, and the whole risk being tested is that copying one bitmap into another
    /// context is not lossless. Normalising both through a third context would hide exactly that.
    private func rawPixels(_ image: UIImage, _ label: String) -> (layout: String, bytes: Data) {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data else {
            XCTFail("\(label): no bitmap to read")
            return ("none", Data())
        }
        let layout = "\(cg.width)x\(cg.height) bpr=\(cg.bytesPerRow) bpc=\(cg.bitsPerComponent)"
            + " bpp=\(cg.bitsPerPixel) info=\(cg.bitmapInfo.rawValue) alpha=\(cg.alphaInfo.rawValue)"
        return (layout, data as Data)
    }

    /// Asserts two renders are the *same bytes*, at zero tolerance, and says how they differ if not.
    private func assertIdentical(_ incremental: UIImage, _ full: UIImage, _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let a = rawPixels(incremental, "incremental")
        let b = rawPixels(full, "full re-walk")
        XCTAssertEqual(a.layout, b.layout, "\(what): the two arms produced different bitmap layouts",
                       file: file, line: line)
        guard a.bytes.count == b.bytes.count, !a.bytes.isEmpty else {
            XCTFail("\(what): byte counts differ (\(a.bytes.count) vs \(b.bytes.count))",
                    file: file, line: line)
            return
        }
        if a.bytes == b.bytes { return }
        // Not equal: report the worst channel and where, so a failure is actionable rather than
        // "the images differ".
        var worst = 0, worstIndex = -1, differing = 0
        a.bytes.withUnsafeBytes { ra in
            b.bytes.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self), pb = rb.bindMemory(to: UInt8.self)
                for i in 0..<pa.count {
                    let delta = abs(Int(pa[i]) - Int(pb[i]))
                    if delta > 0 { differing += 1 }
                    if delta > worst { worst = delta; worstIndex = i }
                }
            }
        }
        XCTFail("\(what): \(differing) of \(a.bytes.count) bytes differ, worst \(worst)/255 "
                + "at byte \(worstIndex) — the incremental arm is not the picture the walk makes",
                file: file, line: line)
    }

    /// The full re-walk of `canvas`'s display list, guaranteed cold: a freshly constructed canvas
    /// has no memo and no base, so it *cannot* take the fast path. The `dabs` it reports is the
    /// whole layer's dab count, which is what the fast path must not be spending.
    private func fullReWalk(of canvas: VectorCanvas,
                            transform: CGAffineTransform = .identity) -> (image: UIImage, dabs: Int) {
        let cold = VectorCanvas(size: canvas.size, elements: canvas.elements, transform: transform)
        let image = cold.render()
        XCTAssertEqual(cold.rasterizations, 1, "the reference arm must have rasterized exactly once")
        return (image, cold.lastRenderDabCount)
    }

    /// Dabs one element stamps on its own — the number a fast-path append must land on.
    private func soloDabs(_ element: VectorElement) -> Int {
        let solo = VectorCanvas(size: Self.canvasSize, elements: [element])
        _ = solo.render()
        return solo.lastRenderDabCount
    }

    // MARK: - (1) What each mutation site declares

    /// **Every mutation site, and what it now says about itself.** The seam is `lastDamage`, read
    /// without rendering anything, so this pins the declarations rather than their consequences —
    /// which is what makes it useful when one of them is later changed by someone who has not read
    /// `appendPreservesTheWalk`.
    ///
    /// **The fixture is mutated cumulatively rather than rebuilt per row**, which CLAUDE.md's
    /// "green assertion" section is specifically about: a table that constructs a fresh canvas per
    /// row would be comparing something other than the effect of the row.
    func testWhatEveryMutationSiteDeclares() {
        let canvas = Self.canvas(3)
        XCTAssertEqual(canvas.lastDamage, .everything, "a canvas nobody has edited assumes nothing")

        canvas.addStroke(Self.stroke(3))
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addStroke")

        canvas.addStroke(canvasSpaceStroke: Self.stroke(4))
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addStroke(canvasSpaceStroke:)")

        canvas.addFill(Self.fill())
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addFill — LASSO_FILL.md §2a appends")

        canvas.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 2, y: 2, width: 9, height: 9),
                                               transform: nil),
                       color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addFill(canvasSpacePath:)")

        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 10
        let text = VectorTextElement(id: UUID(), recipe: recipe,
                                     frame: TextFrame(origin: CGPoint(x: 10, y: 70),
                                                      size: CGSize(width: 30, height: 12)))
        canvas.upsertText(text)
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "a brand-new text object appends")

        var retyped = text
        retyped.recipe.string = "hello"
        canvas.upsertText(retyped)
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "re-editing text replaces it at its own z-position, which is not an append")

        // An image goes *below* the first stroke, so on this cel it is a middle insert.
        let photo = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                             size: CGSize(width: 8, height: 8))
        canvas.addImage(VectorImageElement(image: photo,
                                           transform: LayerTransform(position: CGPoint(x: 40, y: 40),
                                                                     scale: 1, rotation: 0)))
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "an image inserted under the line art is not an append")

        canvas.removeText(id: text.id)
        XCTAssertEqual(canvas.lastDamage, .everything, "removeText")

        canvas.suppressedElementIDs = [canvas.elements[0].id]
        XCTAssertEqual(canvas.lastDamage, .everything, "suppression hides an element in the middle")
        canvas.suppressedElementIDs = []

        canvas.setTransform(CGAffineTransform(translationX: 3, y: 4))
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "a layer transform resamples the whole picture; there is nothing to append to")
        canvas.setTransform(.identity)

        canvas.bumpVersion()
        XCTAssertEqual(canvas.lastDamage, .everything, "bumpVersion is undo's seam and knows nothing")
    }

    /// **An image imported onto a cel with no line art on it *is* an append**, and the declaration
    /// is derived from where the element landed rather than argued from the kind order — so this row
    /// and the `.everything` row above are the same call site answering two different lists.
    func testAnImageOntoAnEmptyCelIsAnAppendAndOntoLineArtIsNot() {
        let photo = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                             size: CGSize(width: 8, height: 8))
        func element() -> VectorImageElement {
            VectorImageElement(image: photo,
                               transform: LayerTransform(position: CGPoint(x: 40, y: 40),
                                                         scale: 1, rotation: 0))
        }

        let blank = VectorCanvas(size: Self.canvasSize, elements: [])
        blank.addImage(element())
        XCTAssertEqual(blank.lastDamage, .appended(count: 1))
        blank.addImage(element())
        XCTAssertEqual(blank.lastDamage, .appended(count: 1), "a second image goes above the first")

        let inked = Self.canvas(2)
        inked.addImage(element())
        XCTAssertEqual(inked.lastDamage, .everything)
    }

    /// **The eraser's two halves declare differently, and that is the whole reason `eraseHybrid`
    /// returns a `Damage`.** A soft-brush punch appends one `.erase` element; a hard-brush clean cut
    /// deletes and splits strokes in the middle of the list first.
    func testTheEraserDeclaresAnAppendOnlyWhenItMerelyPunches() {
        let soft = Self.canvas(4)
        let path = (0..<6).map { VectorSample(x: 12 + CGFloat($0) * 18, y: 44, pressure: 0.5) }
        // Opacity below 1 forbids the clean cut (`VectorEraser.supportsCleanCut`), so this gesture
        // can only punch.
        XCTAssertTrue(soft.erase(alongPath: path, brush: Self.brush(), size: 12, opacity: 0.5,
                                 mode: .erase))
        XCTAssertEqual(soft.lastDamage, .appended(count: 1),
                       "a punch is one `.erase` element on the end of the list")

        let cut = Self.canvas(4)
        XCTAssertTrue(cut.erase(alongPath: path, brush: Self.brush(), size: 40, opacity: 1,
                                mode: .cutPoints))
        XCTAssertEqual(cut.lastDamage, .everything,
                       "Mode 2 replaces strokes with the pieces it cut them into")
    }

    // MARK: - (2) The fast path draws the picture the walk would

    /// **The headline pin: appending a stroke is byte-for-byte the full re-walk, and costs only the
    /// new stroke's own dabs.**
    ///
    /// Both halves are needed and neither implies the other. Without the dab count, an
    /// implementation that quietly re-walked would pass — which is exactly the shape of a change
    /// that is "correct" and buys nothing. Without the byte comparison, an implementation that drew
    /// the wrong picture cheaply would pass.
    func testAppendingAStrokeIsByteIdenticalAndStampsOnlyItsOwnDabs() {
        let canvas = Self.canvas(12)
        let warm = canvas.render()
        XCTAssertEqual(canvas.rasterizations, 1)
        let wholeLayerDabs = canvas.lastRenderDabCount
        XCTAssertGreaterThan(wholeLayerDabs, 0, "setup: the fixture must actually stamp something")

        let newStroke = Self.stroke(12)
        let expectedNewDabs = soloDabs(.stroke(newStroke))
        XCTAssertGreaterThan(expectedNewDabs, 0)

        canvas.addStroke(newStroke)
        let incremental = canvas.render()
        XCTAssertNotIdentical(incremental, warm, "setup: the append must have produced a new picture")

        XCTAssertEqual(canvas.lastRenderDabCount, expectedNewDabs,
                       "the append must stamp the new stroke and nothing else — \(wholeLayerDabs) "
                       + "would mean the fast path was not taken")
        assertIdentical(incremental, fullReWalk(of: canvas).image, "appending one paint stroke")
    }

    /// **Consecutive appends, which is what inking actually is.** Each one must chain onto the last
    /// one's result rather than re-establishing a base by walking.
    func testEachOfARunOfAppendsCostsOnlyItsOwnDabs() {
        let canvas = Self.canvas(8)
        _ = canvas.render()

        for index in 8..<14 {
            let element = VectorElement.stroke(Self.stroke(index))
            let expected = soloDabs(element)
            canvas.addStroke(Self.stroke(index))
            _ = canvas.render()
            XCTAssertEqual(canvas.lastRenderDabCount, expected,
                           "append \(index - 7) of 6 fell back to the full walk")
        }
        assertIdentical(canvas.render(), fullReWalk(of: canvas).image, "six appends in a row")
    }

    /// **The eraser question, settled by experiment rather than by argument.**
    ///
    /// An `.erase` stroke composites `destinationOut` against everything beneath it and is
    /// deliberately never inside a transparency layer (`renderLocalContent` rule 3). The claim is
    /// that this makes it *the easiest* append rather than the hardest: it ends the paint run before
    /// it, so the run's transparency layer is already composited down in the base exactly as it
    /// would be in the walk, and `destinationOut` against the base is `destinationOut` against the
    /// accumulated context.
    ///
    /// **The hostile case is the one that decides it** — a prefix whose trailing run *does* carry a
    /// non-`.normal` blend mode, so the full walk really does open and close a transparency layer
    /// before the eraser. If the base blit or the layer boundary lost anything, this is where it
    /// shows.
    func testAnAppendedEraserOverAnIsolatedRunIsByteIdentical() {
        let canvas = Self.canvas(6, blend: .multiply)
        _ = canvas.render()
        let wholeLayerDabs = canvas.lastRenderDabCount

        let punch = Self.eraserStroke()
        let expected = soloDabs(.stroke(punch))
        canvas.addStroke(punch)
        let incremental = canvas.render()

        XCTAssertEqual(canvas.lastRenderDabCount, expected,
                       "an eraser appended after an isolated run must still take the fast path "
                       + "(\(wholeLayerDabs) dabs would mean it fell back)")
        assertIdentical(incremental, fullReWalk(of: canvas).image,
                        "an eraser appended after a multiply run")
    }

    /// The ordinary eraser, over an all-`.normal` layer.
    func testAnAppendedEraserOverPlainInkIsByteIdentical() {
        let canvas = Self.canvas(10)
        _ = canvas.render()
        let punch = Self.eraserStroke()
        let expected = soloDabs(.stroke(punch))
        canvas.addStroke(punch)
        let incremental = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, expected)
        assertIdentical(incremental, fullReWalk(of: canvas).image, "an eraser appended over plain ink")
    }

    /// **A stroke appended *after* an eraser**, which is the other side of rule 3: the new stroke
    /// starts a fresh paint run, because an `.erase` element ended the last one.
    func testAStrokeAppendedAfterAnEraserIsByteIdentical() {
        let canvas = Self.canvas(6)
        canvas.addStroke(Self.eraserStroke())
        _ = canvas.render()

        let newStroke = Self.stroke(20)
        let expected = soloDabs(.stroke(newStroke))
        canvas.addStroke(newStroke)
        let incremental = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, expected)
        assertIdentical(incremental, fullReWalk(of: canvas).image, "a stroke appended after an eraser")
    }

    /// A fill appended over line art — LASSO_FILL.md §2a's "cover everything". It ends the paint run
    /// beneath it, so like the eraser it needs no condition; it stamps no dabs at all, which is what
    /// makes the fallback distinguishable here.
    func testAnAppendedFillIsByteIdenticalAndStampsNothing() {
        let canvas = Self.canvas(10, blend: .multiply)
        _ = canvas.render()
        let wholeLayerDabs = canvas.lastRenderDabCount
        XCTAssertGreaterThan(wholeLayerDabs, 0)

        canvas.addFill(Self.fill())
        let incremental = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, 0,
                       "a fill stamps no dabs; \(wholeLayerDabs) would be the layer re-walked")
        assertIdentical(incremental, fullReWalk(of: canvas).image, "a fill appended over a multiply run")
    }

    /// A stroke appended after a fill: the fill ended the previous run, so the new stroke opens one
    /// of its own and cannot merge with anything the base already flattened.
    func testAStrokeAppendedAfterAFillIsByteIdentical() {
        let canvas = Self.canvas(6, blend: .multiply)
        canvas.addFill(Self.fill())
        _ = canvas.render()

        let newStroke = Self.stroke(21)
        let expected = soloDabs(.stroke(newStroke))
        canvas.addStroke(newStroke)
        let incremental = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, expected)
        assertIdentical(incremental, fullReWalk(of: canvas).image, "a stroke appended after a fill")
    }

    /// **A punch appended by the shipped eraser gesture**, rather than by `addStroke` with an
    /// `.erase` composite. Reaching the fast path through `erase(alongPath:…)` is what says the
    /// declaration `eraseHybrid` returns actually arrives at the render.
    func testTheEraserGesturesOwnPunchTakesTheFastPath() {
        let canvas = Self.canvas(10)
        _ = canvas.render()
        let wholeLayerDabs = canvas.lastRenderDabCount

        let path = (0..<6).map { VectorSample(x: 12 + CGFloat($0) * 18, y: 44, pressure: 0.5) }
        XCTAssertTrue(canvas.erase(alongPath: path, brush: Self.brush(), size: 12, opacity: 0.5,
                                   mode: .erase))
        let incremental = canvas.render()
        XCTAssertLessThan(canvas.lastRenderDabCount, wholeLayerDabs / 2,
                          "an eraser gesture that only punches must not re-stamp the layer")
        assertIdentical(incremental, fullReWalk(of: canvas).image, "the eraser gesture's own punch")
    }

    // MARK: - (3) Everything else falls back
    //
    // These are the tests that catch a future element kind, or a future mutation site, taking the
    // fast path where it is not equivalent. Each asserts *both* that the picture is right and that
    // it was reached by re-walking — because a wrong picture and a slow-but-right one fail in very
    // different ways and only one of them is a corruption.

    /// **An appended stroke carrying a blend mode isolates the run it joins**, which pulls the
    /// prefix's own strokes inside a transparency layer the base has already flattened. Not
    /// equivalent; must re-walk.
    func testAnAppendedBlendModeStrokeFallsBackToTheFullWalk() {
        let canvas = Self.canvas(10)
        _ = canvas.render()
        let beforeTheAppend = canvas.lastRenderDabCount

        let tinted = Self.stroke(30, blend: .multiply)
        canvas.addStroke(tinted)
        let incremental = canvas.render()

        let reference = fullReWalk(of: canvas)
        XCTAssertGreaterThan(reference.dabs, beforeTheAppend,
                             "setup: the reference must be the layer plus the new stroke")
        XCTAssertEqual(canvas.lastRenderDabCount, reference.dabs,
                       "a multiply stroke joins the run before it and must re-walk the whole layer")
        assertIdentical(incremental, reference.image, "a multiply stroke appended onto normal ink")
    }

    /// The mirror image: the appended stroke is `.normal`, but the run it joins is not. One
    /// non-`.normal` stroke anywhere in the merged run isolates all of it, the base's strokes
    /// included — so scanning only the new element would be exactly wrong.
    func testANormalStrokeAppendedOntoABlendModeRunFallsBackToTheFullWalk() {
        let canvas = Self.canvas(8, blend: .multiply)
        _ = canvas.render()

        canvas.addStroke(Self.stroke(31))
        let incremental = canvas.render()

        let reference = fullReWalk(of: canvas)
        XCTAssertEqual(canvas.lastRenderDabCount, reference.dabs,
                       "the prefix's own run carries a blend mode; appending into it is not the same "
                       + "picture, and taking the fast path here would corrupt the artwork")
        assertIdentical(incremental, reference.image, "a normal stroke appended onto a multiply run")
    }

    /// **A layer transform means the memo is the *resampled* picture**, and resampling a composite
    /// is not compositing two resampled halves. The base is therefore not available and the append
    /// re-walks.
    func testAnAppendOntoATransformedLayerFallsBackToTheFullWalk() {
        let transform = CGAffineTransform(rotationAngle: 0.3).translatedBy(x: 5, y: 7)
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: (0..<8).map { .stroke(Self.stroke($0)) },
                                  transform: transform)
        _ = canvas.render()

        canvas.addStroke(Self.stroke(32))
        let incremental = canvas.render()

        let reference = fullReWalk(of: canvas, transform: transform)
        XCTAssertEqual(canvas.lastRenderDabCount, reference.dabs,
                       "a transformed layer has no pre-transform picture to append to")
        assertIdentical(incremental, reference.image, "an append onto a rotated layer")
    }

    /// An element inserted anywhere but the end is the whole of TODO's dirty-rect item, and until
    /// that exists it must re-walk. An image goes under the line art, so it is the shipped mutation
    /// that does this.
    func testAMiddleInsertFallsBackToTheFullWalk() {
        let canvas = Self.canvas(8)
        _ = canvas.render()

        let photo = CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 12, height: 12),
                                             size: CGSize(width: 12, height: 12))
        canvas.addImage(VectorImageElement(image: photo,
                                           transform: LayerTransform(position: CGPoint(x: 50, y: 40),
                                                                     scale: 1, rotation: 0)))
        let incremental = canvas.render()
        let reference = fullReWalk(of: canvas)
        XCTAssertEqual(canvas.lastRenderDabCount, reference.dabs)
        assertIdentical(incremental, reference.image, "an image inserted under the line art")
    }

    /// **Undo.** `bumpVersion()` is the seam every wholesale `elements =` assignment comes through
    /// and it cannot say what moved, so a restored snapshot re-walks — including the case that would
    /// be silently wrong, where the list happens to be *longer* than the base.
    func testUndoAndRedoBothFallBackToTheFullWalk() {
        let canvas = Self.canvas(8)
        _ = canvas.render()
        let snapshot = canvas.elements

        canvas.addStroke(Self.stroke(40))
        canvas.addStroke(Self.stroke(41))
        _ = canvas.render()

        // Undo: shorter list, wholesale assignment.
        canvas.elements = snapshot
        canvas.bumpVersion()
        _ = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, fullReWalk(of: canvas).dabs, "undo")

        // Redo to a *longer* list than the base — the shape a count check alone would let through
        // if `bumpVersion` claimed an append.
        canvas.elements = snapshot + [.stroke(Self.stroke(42)), .stroke(Self.stroke(43))]
        canvas.bumpVersion()
        let incremental = canvas.render()
        let reference = fullReWalk(of: canvas)
        XCTAssertEqual(canvas.lastRenderDabCount, reference.dabs, "redo")
        assertIdentical(incremental, reference.image, "a restored snapshot")
    }

    /// **Assigning `elements` without a `bumpVersion()` must not leave an appendable base standing.**
    /// The five kind-filtered setters deliberately do not invalidate — their callers follow with
    /// `bumpVersion()` — but a base whose prefix claim has quietly stopped being true is the one
    /// failure that draws a *wrong* picture rather than a stale one.
    func testAWholesaleAssignmentDropsTheBaseEvenWithoutAVersionBump() {
        let canvas = Self.canvas(8)
        _ = canvas.render()
        var replaced = canvas.elements
        replaced[0] = .stroke(Self.stroke(50))
        replaced.append(.stroke(Self.stroke(51)))

        canvas.elements = replaced
        canvas.bumpVersion()
        let incremental = canvas.render()
        let reference = fullReWalk(of: canvas)
        XCTAssertEqual(canvas.lastRenderDabCount, reference.dabs,
                       "the first element was replaced; the base is not a picture of this list")
        assertIdentical(incremental, reference.image, "a spliced display list")
    }

    /// A text edit session hides its element while the overlay draws it, which removes something
    /// from the *middle* of the walk. Neither the suppression nor the un-suppression is an append.
    func testSuppressingAndUnsuppressingBothFallBackToTheFullWalk() {
        let canvas = Self.canvas(8)
        _ = canvas.render()

        canvas.suppressedElementIDs = [canvas.elements[2].id]
        _ = canvas.render()
        XCTAssertEqual(canvas.lastDamage, .everything)

        canvas.addStroke(Self.stroke(60))
        let duringEdit = canvas.render()
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1),
                       "the site still declares what it did; the render is what declines to use it")
        let visible = canvas.elements.filter { $0.id != canvas.suppressedElementIDs.first }
        let reference = VectorCanvas(size: Self.canvasSize, elements: visible)
        let referenceImage = reference.render()
        XCTAssertEqual(canvas.lastRenderDabCount, reference.lastRenderDabCount,
                       "a cel with something suppressed must re-walk: the base would count elements "
                       + "the walk skips")
        assertIdentical(duringEdit, referenceImage, "an append while an element is suppressed")

        canvas.suppressedElementIDs = []
        _ = canvas.render()
        assertIdentical(canvas.render(), fullReWalk(of: canvas).image, "un-suppressing")
    }

    /// **Cache eviction really frees the pixels.** `incrementalBase` is a second reference to a
    /// canvas-sized bitmap, so a `dropCachedImage()` that left it standing would make eviction a
    /// no-op on exactly the cels it is trying to free, and `hasCachedImage` would report nothing
    /// cached while 8 MB was held.
    func testEvictionFreesTheAppendableBaseAndIsHonestAboutHoldingIt() {
        let canvas = Self.canvas(8)
        _ = canvas.render()
        XCTAssertTrue(canvas.hasCachedImage)

        canvas.addStroke(Self.stroke(70))
        XCTAssertTrue(canvas.hasCachedImage,
                      "between an append and its render the base is the only reference to a "
                      + "canvas-sized bitmap, and eviction has to be able to see it")

        canvas.dropCachedImage()
        XCTAssertFalse(canvas.hasCachedImage)
        _ = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, fullReWalk(of: canvas).dabs,
                       "an evicted cel has nothing to append to")
    }

    // MARK: - (4) The ordinary case, cold

    /// **From a document nobody has set up: does the fast path get taken?**
    ///
    /// CLAUDE.md's newest section is about features that are correct and unreachable, and the render
    /// equivalent is a condition that quietly forces the slow path in the shipped build — which
    /// would leave every measurement in PERFORMANCE.md §11.6 unspent. So this starts from a blank
    /// cel, draws the way an artist draws with the brushes the app ships, and asserts on the dab
    /// count of the *last* stroke rather than on anything the test arranged.
    func testAFreshCelDrawnOnWithShippedBrushesTakesTheFastPathOnEveryStroke() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [])
        // All five shipped brushes, so this goes red the day one of them stops being `.normal`.
        let library = BrushLibrary.defaults
        XCTAssertFalse(library.isEmpty, "setup: the app must ship brushes")
        for brush in library {
            XCTAssertEqual(brush.blendMode, .normal,
                           "\(brush.name) is not `.normal`, so strokes made with it can no longer "
                           + "append incrementally — see appendPreservesTheWalk")
        }

        var fellBack: [Int] = []
        for index in 0..<20 {
            var stroke = Self.stroke(index)
            stroke.brush = library[index % library.count]
            stroke.brush.size = 6
            stroke.size = 6
            let expected = soloDabs(.stroke(stroke))
            canvas.addStroke(canvasSpaceStroke: stroke)
            _ = canvas.render()
            // The first stroke on a blank cel is the whole layer, so it cannot be a fast path and
            // must not be counted as one.
            if index > 0, canvas.lastRenderDabCount != expected { fellBack.append(index) }
        }
        XCTAssertEqual(fellBack, [],
                       "strokes \(fellBack) re-walked the layer — the fast path is not reachable "
                       + "by drawing, which is the only way it is reached")
        assertIdentical(canvas.render(), fullReWalk(of: canvas).image, "twenty strokes drawn in order")
    }

    /// **The same claim at the owner's own canvas, because 128×96 is not the size that ships.**
    ///
    /// Everything above renders small so the byte comparison is cheap, and that is a hazard this
    /// repo has recorded from the other direction: PERFORMANCE.md §1 is about a shelf of correct
    /// measurements taken at a canvas nobody uses. Bitmap row padding, the renderer's format
    /// negotiation and the 1:1 blit are all functions of the size, so the equality is re-taken once
    /// at 2048×1024 — the owner's canvas — rather than extrapolated from a small one.
    func testTheAppendIsByteIdenticalAtTheOwnersCanvasSizeToo() {
        let size = CGSize(width: 2048, height: 1024)
        func placed(_ index: Int) -> VectorStroke {
            var stroke = Self.stroke(index)
            stroke.samples = stroke.samples.map {
                VectorSample(x: $0.x * 14, y: $0.y * 9, pressure: $0.pressure)
            }
            stroke.size = 24
            stroke.brush.size = 24
            return stroke
        }
        let canvas = VectorCanvas(size: size, elements: (0..<8).map { .stroke(placed($0)) })
        _ = canvas.render()

        let newStroke = placed(80)
        let solo = VectorCanvas(size: size, elements: [.stroke(newStroke)])
        _ = solo.render()

        canvas.addStroke(newStroke)
        let incremental = canvas.render()
        XCTAssertEqual(canvas.lastRenderDabCount, solo.lastRenderDabCount)

        let cold = VectorCanvas(size: size, elements: canvas.elements)
        assertIdentical(incremental, cold.render(), "an append at 2048×1024")
    }

    /// **The cost model, stated as a countable rather than as milliseconds.** PERFORMANCE.md §11.2
    /// measures the machine; this pins the *shape* — that appending to a big cel and appending to a
    /// small one stamp the same number of dabs — which is the claim the milliseconds are evidence
    /// for and the one that would silently stop being true.
    func testTheCostOfAnAppendDoesNotDependOnWhatIsAlreadyOnTheLayer() {
        func dabsForOneMoreStroke(onto n: Int) -> Int {
            let canvas = Self.canvas(n)
            _ = canvas.render()
            canvas.addStroke(Self.stroke(500))
            _ = canvas.render()
            return canvas.lastRenderDabCount
        }
        let small = dabsForOneMoreStroke(onto: 4)
        let large = dabsForOneMoreStroke(onto: 60)
        XCTAssertEqual(small, large,
                       "the append cost moved with the layer's size, which is the whole defect this "
                       + "change exists to remove")
        XCTAssertGreaterThan(small, 0)
    }
}
