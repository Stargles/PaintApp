import XCTest
import UIKit

/// **LASSO_MOVE.md §3 stage 3c — a placed image holding a stretched shape.**
///
/// Until this stage a `VectorImageElement`'s whole placement was a `LayerTransform`: position, one
/// scale, one rotation. That is a similarity, so the two Move controls that ask for anything else —
/// Mirror (a reflection) and Freeform (two axis scales) — refused any lassoed piece carrying a photo,
/// out loud, in the bar's caption. §5.18 recorded that a text box escaped the same refusal on
/// 2026-08-27 without a new field, *because a `TextFrame` already carries four free corners*, and
/// named the image as the one kind that still needed a stored one.
///
/// The stored shape is three fields beside `transform` — `aspect`, `stretchAxis` and `mirrored` — and
/// §5.20's own arithmetic is what says that is the right size and no larger: two translations, two
/// angles and two scales is six, which *is* a general affine, and the seventh value is a single bit
/// because the invertible affines have two connected components and the six-number `R·S·R` form spans
/// exactly the one with a positive determinant.
///
/// **What these tests are for, in one sentence each.** That an unstretched placement is bit-for-bit
/// the matrix the three `CGContext` calls used to build (so no drawing anybody already has changes);
/// that a stretch and a mirror actually reach the picture; that composing an arbitrary affine into the
/// placement and reading it back out is *exact*, which is the whole correctness claim of the
/// decomposition; that the payload gains no bytes for an image nobody stretched; and that the quad the
/// three membership rules test against follows the stretched rectangle rather than the old one.
final class PlacedImageShapeLogicTests: XCTestCase {

    // MARK: - The unstretched placement is the one that was there before

    /// **A placement nobody has stretched is the identical matrix, to the bit.**
    ///
    /// `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` spells `aspect == 1` and
    /// `stretchAxis == 0` as their shorter expressions rather than computing them, which is what makes
    /// this exact rather than merely close — and "close" is not good enough, because
    /// `CanvasManager.applyToVectorFloat` dispatches between the similarity and stretch arms on
    /// `aspect != 1` **exactly**, and `mapping(_:throughSimilarity:)` asserts the shape it is handed.
    ///
    /// Exact equality, not an accuracy: an `XCTAssertEqual` with a tolerance here would pass for an
    /// implementation that round-tripped every placement through two `sin`/`cos` pairs and left a
    /// similarity that is only nearly one.
    func testAnUnstretchedPlacementIsTheMatrixTheThreeContextCallsUsedToBuild() {
        for (scale, rotation) in [(CGFloat(1), CGFloat(0)), (2.5, 0), (1, 0.7), (0.4, -1.9)] {
            let element = image(at: CGPoint(x: 30, y: 26), scale: scale, rotation: rotation)
            let expected = CGAffineTransform(translationX: 30, y: 26)
                .rotated(by: rotation)
                .scaledBy(x: scale, y: scale)
            XCTAssertEqual(element.placement, expected,
                           "scale \(scale), rotation \(rotation): the stored shape must be free")
        }
    }

    // MARK: - A stretch reaches the picture

    /// **A Freeform stretch is carried as the image's own aspect, and the rendered photo follows it.**
    ///
    /// Two halves, and both are needed. The stored one says the map landed in the element rather than
    /// being swallowed: before this stage `mapping(_:throughStretch:)`'s `.image` arm was an
    /// `assertionFailure` that returned the element **unchanged**, so a test that only looked at the
    /// model would have to assert on a value that did not exist. The rendered one says `draw(image:)`
    /// reads the new fields: a stretch that reached the model and not the renderer is a photo that
    /// moves when you undo it and never while you drag it.
    ///
    /// A 4:1 stretch of a square is 2× wide and 0.5× tall, because the area factor stays in
    /// `transform.scale` and `aspect` holds only the shape — `ObjectTransformFrame.axisScales`'
    /// split, applied to the document.
    func testAStretchIsCarriedAsTheImagesOwnAspectAndTheRenderedPictureFollowsIt() throws {
        let element = image(at: CGPoint(x: 32, y: 32), scale: 1, rotation: 0)
        // About the photo's own centre, which is the shape a Move nudge builds about `float.pivot`.
        // A stretch about the *origin* would move the centre to (64, 16) as well as reshaping it, and
        // the render below would then be measuring a photo half off the canvas.
        let stretch = CGAffineTransform(translationX: 32, y: 32)
            .scaledBy(x: 2, y: 0.5)
            .translatedBy(x: -32, y: -32)

        guard case .image(let stretched) = VectorCanvas.mapping(.image(element), throughStretch: stretch)
        else { return XCTFail("the stretch arm dropped the element") }

        XCTAssertEqual(stretched.aspect, 4, accuracy: 1e-9, "four times as wide as it is tall")
        XCTAssertEqual(stretched.transform.scale, 1, accuracy: 1e-9,
                       "a pure shape change leaves the area factor alone — the two axis scales "
                       + "multiply to one, which is what makes a stretch and a stretch back free")
        XCTAssertEqual(stretched.stretchAxis, 0, accuracy: 1e-9, "made about the box's own x axis")
        XCTAssertFalse(stretched.mirrored, "and a positive determinant is not a reflection")

        let drawn = try XCTUnwrap(renderedInk(of: stretched), "the stretched photo renders somewhere")
        XCTAssertEqual(drawn.width, 12, accuracy: 1.5,
                       "a 6 pt square stretched 4:1 is 12 pt across: \(drawn)")
        XCTAssertEqual(drawn.height, 3, accuracy: 1.5, "and 3 pt tall: \(drawn)")
        XCTAssertEqual(drawn.midX, 32, accuracy: 1, "about the centre it was placed at: \(drawn)")
    }

    /// **A stretch whose two axes grow by the same factor is the Uniform drag, exactly** — §5.17's
    /// *"Freeform contains Uniform"* one level down, on the kind that could not stretch at all before.
    ///
    /// It matters because `applyToVectorFloat` picks the arm on `aspect != 1`: if the stretch arm did
    /// not reduce to the similarity arm here, the same visible gesture would write two different
    /// documents on the two tabs of the picker, with the seam at `aspect == 1 ± ε`.
    func testAStretchAlongTheBoxsOwnDiagonalIsTheUniformScale() {
        let element = image(at: CGPoint(x: 30, y: 26), scale: 1.5, rotation: 0.4)
        let uniform = CGAffineTransform(scaleX: 2, y: 2)

        guard case .image(let a) = VectorCanvas.mapping(.image(element), throughStretch: uniform),
              case .image(let b) = VectorCanvas.mapping(.image(element), throughSimilarity: uniform)
        else { return XCTFail("both arms carry a placed image") }

        XCTAssertEqual(a.aspect, 1, accuracy: 1e-9, "no shape change")
        XCTAssertEqual(a.transform.scale, b.transform.scale, accuracy: 1e-9)
        XCTAssertEqual(a.transform.rotation, b.transform.rotation, accuracy: 1e-9)
        assertMatchesMatrix(a.placement, b.placement, "the two arms write the same placement")
    }

    // MARK: - The mirror bit

    /// **Mirror sets the bit, the picture reflects, and mirroring back is the placement that was
    /// lifted.**
    ///
    /// The load-bearing assertion is the **sign of the determinant**, and nothing else here can stand
    /// in for it: a placement rotated a half turn instead of reflected puts the four corners in
    /// plausible places, keeps the same bounding box, and draws the photo the right way round. That
    /// is precisely the failure `mapping(_:throughSimilarity:)`'s `.image` arm used to assert against
    /// — `theta = atan2(t.b, t.a)` reads a map that turns the plane over as an *angle* — and the
    /// branch that peels the sign into `mirrored` is what replaced the assert.
    func testMirroringAPlacedImageReflectsItAndMirroringBackIsTheOriginalPlacement() {
        let element = image(at: CGPoint(x: 30, y: 26), scale: 1.5, rotation: 0.4)
        // Mirror about the piece's own vertical centre line, which is the shape
        // `CanvasManager.mirrorFloating` builds about the float's pivot.
        let flip = CGAffineTransform(translationX: 30, y: 26)
            .scaledBy(x: -1, y: 1)
            .translatedBy(x: -30, y: -26)

        guard case .image(let mirrored) = VectorCanvas.mapping(.image(element), throughSimilarity: flip)
        else { return XCTFail("the similarity arm carries a reflection now") }

        XCTAssertTrue(mirrored.mirrored, "the bit is the only place a reflection can live")
        XCTAssertLessThan(determinant(mirrored.placement), 0,
                          "the plane is turned over — a half turn would leave this positive")
        XCTAssertEqual(mirrored.transform.position.x, 30, accuracy: 1e-9,
                       "and a mirror about its own centre does not move the photo")
        XCTAssertEqual(hypot(mirrored.placement.a, mirrored.placement.b), 1.5, accuracy: 1e-9,
                       "a reflection preserves length, so the scale is untouched")

        guard case .image(let back) = VectorCanvas.mapping(.image(mirrored), throughSimilarity: flip)
        else { return XCTFail("and back again") }
        XCTAssertFalse(back.mirrored)
        assertMatchesMatrix(back.placement, element.placement,
                            "mirror and mirror back is the placement that was lifted")
    }

    // MARK: - The decomposition itself

    /// **Any invertible affine composes into the placement and comes back out of it.** This is the
    /// whole correctness claim of stage 3c, and every other test in this file is a consequence of it.
    ///
    /// The assertion is against the **directly multiplied matrix** — the same claim
    /// `ObjectTransformLogicTests.testTwoStretchesAboutDifferentAxesComposeIntoTheProductMatrix`
    /// makes for the Move box — because that is the only statement worth making about a
    /// decomposition: the six numbers and the bit are a *representation*, and what the artist sees is
    /// the matrix they rebuild. Any test that instead asserted the individual fields would be pinning
    /// one of the two equally valid branches `ObjectTransformFrame.decompose` can return, a quarter
    /// turn apart, which describe the same map with the axes named the other way round.
    ///
    /// The bases include an already-stretched and an already-mirrored placement on purpose: the
    /// interesting failure is not the first application but the second, where the old shape has to be
    /// composed rather than overwritten.
    func testAnyAffineComposesIntoThePlacementAndComesBackOutOfIt() {
        let bases: [(String, VectorImageElement)] = [
            ("at rest", image(at: CGPoint(x: 30, y: 26), scale: 1, rotation: 0)),
            ("turned", image(at: CGPoint(x: 30, y: 26), scale: 1.3, rotation: 0.4)),
            ("already stretched on axis", image(at: CGPoint(x: 22, y: 40), scale: 1.1, rotation: 0,
                                                aspect: 2.5)),
            ("already stretched off axis", image(at: CGPoint(x: 22, y: 40), scale: 1.1, rotation: -0.3,
                                                 aspect: 2.5, stretchAxis: 0.9)),
            ("already mirrored", image(at: CGPoint(x: 18, y: 18), scale: 0.8, rotation: 1.2,
                                       mirrored: true)),
            ("mirrored and stretched", image(at: CGPoint(x: 18, y: 18), scale: 0.8, rotation: 1.2,
                                             aspect: 0.4, stretchAxis: -0.6, mirrored: true)),
        ]
        let deltas: [(String, CGAffineTransform)] = [
            ("translation", CGAffineTransform(translationX: 7, y: -3)),
            ("rotation", CGAffineTransform(rotationAngle: 0.9)),
            ("uniform scale", CGAffineTransform(scaleX: 1.7, y: 1.7)),
            ("axis-aligned stretch", CGAffineTransform(scaleX: 3, y: 0.5)),
            ("off-axis stretch", CGAffineTransform.identity
                .rotated(by: 0.7).scaledBy(x: 2.2, y: 0.6).rotated(by: -0.7)),
            ("reflection", CGAffineTransform(scaleX: -1, y: 1)),
            ("reflection then stretch", CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(scaleX: 1.4, y: 0.8))),
            ("everything at once", CGAffineTransform(translationX: 4, y: 9)
                .rotated(by: -1.1).scaledBy(x: 1.9, y: -0.7)),
        ]

        for (baseName, base) in bases {
            for (deltaName, delta) in deltas {
                let note = "\(baseName) · \(deltaName)"
                // Both public arms are exercised: `applyToVectorFloat` picks between them on the
                // *float's* aspect, so either can be handed either kind of delta.
                for (arm, mapped) in [("stretch", VectorCanvas.mapping(.image(base), throughStretch: delta)),
                                      ("similarity", similarityMapped(base, delta))] {
                    guard let mapped, case .image(let moved) = mapped else { continue }
                    assertMatchesMatrix(moved.placement, base.placement.concatenating(delta),
                                        "\(note) through the \(arm) arm")
                    XCTAssertGreaterThan(moved.aspect, 0,
                                         "\(note): a non-positive aspect makes `axisScales` NaN")
                    XCTAssertGreaterThan(moved.transform.scale, 0, note)
                }
            }
        }
    }

    // MARK: - What the file holds

    /// **An image nobody has stretched writes no new keys, and a stretched one round-trips.**
    ///
    /// The first half is why `ImageRef`'s three stage-3c keys are `Optional`: absent *means* the
    /// unstretched value, so the payload for every drawing that exists is byte-for-byte the payload it
    /// was, and no migration is owed in either direction. It is the same idea `VectorCanvasData`
    /// already applies to its own `transform` key, which is left out of `encode(to:)` rather than
    /// written as the identity.
    func testAnUnstretchedImageWritesNoNewKeysAndAStretchedOneRoundTrips() throws {
        let plain = image(at: CGPoint(x: 30, y: 26), scale: 1.5, rotation: 0.4)
        let shaped = image(at: CGPoint(x: 20, y: 44), scale: 0.9, rotation: -0.2,
                           aspect: 2.5, stretchAxis: 0.8, mirrored: true)

        let plainJSON = try String(decoding: JSONEncoder().encode(payload(for: plain)), as: UTF8.self)
        for key in ["aspect", "stretchAxis", "mirrored"] {
            XCTAssertFalse(plainJSON.contains(key),
                           "an unstretched placement must cost the file nothing: \(plainJSON)")
        }

        let reloaded = try XCTUnwrap(decodedImage(from: payload(for: shaped)))
        XCTAssertEqual(reloaded.aspect, shaped.aspect, accuracy: 1e-9)
        XCTAssertEqual(reloaded.stretchAxis, shaped.stretchAxis, accuracy: 1e-9)
        XCTAssertTrue(reloaded.mirrored)
        assertMatchesMatrix(reloaded.placement, shaped.placement, "the placement survives the file")

        // And a payload written before the three keys existed still opens, unstretched, rather than
        // costing the drawing its photo — the `LossySlot` decode drops an element it cannot read, so
        // a required key here would have been silent artwork loss.
        let legacy = Data("""
        {"fileName":"a.png","x":12,"y":13,"scale":2,"rotation":0.5}
        """.utf8)
        let old = try JSONDecoder().decode(VectorCanvasData.ImageRef.self, from: legacy)
        XCTAssertNil(old.aspect)
        XCTAssertNil(old.stretchAxis)
        XCTAssertNil(old.mirrored)
    }

    // MARK: - What the loop catches

    /// **The membership quad follows the stretched rectangle**, which is §5.23: in Touching and
    /// Enclosed a placed image is asked by *its own quad*, and that quad is now four corners of a
    /// general affine rather than of a rotated square.
    ///
    /// The test is built so the two answers disagree: a loop that encloses the photo at rest fails to
    /// enclose it once it is stretched three ways across, and the *Touching* rule still catches it.
    /// A quad built from the old `translate·rotate·scale` expression would answer "enclosed" for a
    /// rectangle sticking a long way out of the loop.
    func testTheMembershipQuadFollowsTheStretchedRectangle() {
        let (_, _, vector) = fixture()
        let element = image(at: CGPoint(x: 32, y: 32), scale: 1, rotation: 0, aspect: 9)
        vector.addImage(element)
        let loop = CGPath(rect: CGRect(x: 24, y: 24, width: 16, height: 16), transform: nil)

        let quad = VectorCanvas.quad(of: element).boundingBoxOfPath
        XCTAssertEqual(quad.width, 18, accuracy: 1e-6, "6 pt across, stretched 9:1 → ×3")
        XCTAssertEqual(quad.height, 2, accuracy: 1e-6, "and ÷3 the other way")

        XCTAssertTrue(vector.elementIDs(insideLocalPath: loop, membership: .touching).contains(element.id),
                      "the loop still touches the middle of the stretched photo")
        XCTAssertFalse(vector.elementIDs(insideLocalPath: loop, membership: .enclosed).contains(element.id),
                       "but it no longer contains it — the quad is 18 pt wide and the loop is 16")
        XCTAssertTrue(vector.elementIDs(insideLocalPath: loop, membership: .cutting).contains(element.id),
                      "and Cut is still the centre rule, which is unchanged by the shape (§5.23)")
    }

    /// **The Move box still encloses a photo the artist has stretched.**
    ///
    /// `MoveBoxInk` reduces a placed image to a *disc* — `hypot(w, h)/2` about its centre — rather
    /// than to its four corners, so that its contribution stays invariant as the yellow knob turns the
    /// box. The radius has to take the **larger** of the two axis scales for that to keep enclosing
    /// the picture: the operator norm of `R·S·R` is `max(sx, sy)`, so a 9:1 photo reaches three times
    /// its unstretched half-diagonal along one axis whatever axis it was stretched about.
    ///
    /// Stage 3b phase 3's own note predicted this exact spot as the one stage 3c would break, and it
    /// is half right: the *reach* is fixed here, and the axis-aligned `padScale` that pads it is now
    /// conservative rather than exact — a loose box, which is the safe direction and the same
    /// approximation a stroke's own reach already takes under a stretched box.
    func testTheMoveBoxsInkStillEnclosesAPhotoTheArtistHasStretched() throws {
        let (manager, layerIndex, vector) = fixture()
        let element = image(at: CGPoint(x: 32, y: 32), scale: 1, rotation: 0, aspect: 9)
        vector.addImage(element)
        let loop = CGRect(x: 4, y: 4, width: 56, height: 56)
        manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
        XCTAssertTrue(manager.beginVectorLassoMove())

        let measured = try XCTUnwrap(manager.vectorFloat?.ink.bounds(), "the lift measured the photo")
        let picture = VectorCanvas.quad(of: element).boundingBoxOfPath
        XCTAssertTrue(measured.contains(picture),
                      "the box has to hold the photo it is around: \(measured) vs \(picture)")
    }

    // MARK: - Through the Move bar

    /// **A lassoed placed image stretches through the Move bar, in one undo step, and Undo puts the
    /// photo back where it was.**
    ///
    /// The end-to-end half: the two guards that used to refuse this are gone, `vectorFloatIsFreeform`
    /// is true with a photo in the piece, one drag is one step (§5.5), and the step restores the
    /// element rather than a rasterized approximation of it.
    func testAFreeformStretchOfALassoedPlacedImageIsOneUndoStepAndUndoPutsItBack() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addImage(image(at: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
        manager.selection = Selection(path: CGPath(rect: CGRect(x: 18, y: 18, width: 28, height: 28),
                                                   transform: nil),
                                      bounds: CGRect(x: 18, y: 18, width: 28, height: 28),
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
        XCTAssertTrue(manager.beginVectorLassoMove(), "the lift catches the photo")
        manager.setTransformMode(.freeform)
        XCTAssertTrue(manager.vectorFloatIsFreeform,
                      "a piece carrying a photo stretches as of stage 3c")

        let steps = manager.history.undoStack.count
        let pose = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        manager.nudgeVectorFloat(to: pose, aspect: 4)

        let stretched = try XCTUnwrap(vector.elements.compactMap(\.image).first)
        XCTAssertEqual(stretched.aspect, 4, accuracy: 1e-6, "the photo took the box's own shape")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "one drag, one step (§5.5)")

        manager.undo()
        let restored = try XCTUnwrap(vector.elements.compactMap(\.image).first)
        XCTAssertEqual(restored.aspect, 1, accuracy: 1e-9, "and Undo gives the square photo back")
        XCTAssertFalse(restored.mirrored)
    }

    /// **Mirror is offered on a lassoed placed image, and the bar has nothing left to refuse.**
    ///
    /// The counterpart of the test above for the other control. Both of these used to be *refusal*
    /// tests in `LassoMoveLogicTests`, asserting a caption; §3 stage 3c deleted the captions along
    /// with the two properties that raised them, because no kind can answer no any more.
    func testMirrorIsOfferedOnALassoedPlacedImageAndSurvivesALaterDrag() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addImage(image(at: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
        manager.selection = Selection(path: CGPath(rect: CGRect(x: 18, y: 18, width: 28, height: 28),
                                                   transform: nil),
                                      bounds: CGRect(x: 18, y: 18, width: 28, height: 28),
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
        XCTAssertTrue(manager.beginVectorLassoMove())

        manager.mirrorFloating(horizontal: true)
        let mirrored = try XCTUnwrap(vector.elements.compactMap(\.image).first)
        XCTAssertTrue(mirrored.mirrored, "the press reached the photo")
        XCTAssertLessThan(determinant(mirrored.placement), 0)

        // The flip has to ride the *next* drag rather than being undone by it: a nudge re-derives from
        // the lift geometry, so a mirror the map does not carry would evaporate here.
        let pose = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        var moved = pose
        moved.position.x += 5
        manager.nudgeVectorFloat(to: moved)
        let after = try XCTUnwrap(vector.elements.compactMap(\.image).first)
        XCTAssertTrue(after.mirrored, "still mirrored, and now five points along")
        XCTAssertEqual(after.transform.position.x, mirrored.transform.position.x + 5, accuracy: 1e-6)
    }

    // MARK: - Fixtures

    private func image(at position: CGPoint, scale: CGFloat, rotation: CGFloat,
                       aspect: CGFloat = 1, stretchAxis: CGFloat = 0,
                       mirrored: Bool = false) -> VectorImageElement {
        VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                           rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                           size: CGSize(width: 6, height: 6)),
                           transform: LayerTransform(position: position, scale: scale,
                                                     rotation: rotation),
                           aspect: aspect, stretchAxis: stretchAxis, mirrored: mirrored)
    }

    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    /// The element drawn alone on a canvas, reduced to the box its opaque pixels occupy.
    private func renderedInk(of element: VectorImageElement) -> CGRect? {
        let (_, _, vector) = fixture()
        vector.addImage(element)
        return PixelOps.opaqueContentBounds(vector.render())
    }

    /// `mapping(_:throughSimilarity:)`, skipped for a delta it is not allowed to be handed. Its own
    /// doc is the contract: `t` must scale its two axes alike, so the off-axis and per-axis deltas in
    /// the battery above go through the stretch arm only.
    private func similarityMapped(_ element: VectorImageElement,
                                  _ t: CGAffineTransform) -> VectorElement? {
        let k = hypot(t.a, t.b)
        guard abs(k - hypot(t.c, t.d)) <= 1e-9 * max(1, k),
              abs(t.a * t.c + t.b * t.d) <= 1e-9 * max(1, k * k) else { return nil }
        return VectorCanvas.mapping(.image(element), throughSimilarity: t)
    }

    private func payload(for element: VectorImageElement) -> VectorCanvasData.ImageRef {
        let canvas = VectorCanvas(size: CanvasFixture.canvasSize)
        canvas.addImage(element)
        let data = VectorCanvasData(from: canvas, imageFileNames: [element.id: "a.png"])
        guard case .image(let ref) = data.elements.first else {
            fatalError("fixture precondition: one image in, one ref out")
        }
        return ref
    }

    private func decodedImage(from ref: VectorCanvasData.ImageRef) -> VectorImageElement? {
        let data = VectorCanvasData(elements: [.image(ref)], transform: [])
        let rebuilt = data.canvasSpaceElements(resolvingImages: { _ in
            CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                     size: CGSize(width: 6, height: 6))
        }, resolvingVideos: { _ in nil })
        return rebuilt.compactMap(\.image).first
    }

    /// `a·d − b·c`. Its **sign** is the whole question a mirror asks, and `CGAffineTransform` has no
    /// accessor of its own for it.
    private func determinant(_ t: CGAffineTransform) -> CGFloat { t.a * t.d - t.b * t.c }

    /// The six numbers, each within a tolerance sized for what it holds: the linear part is order 1
    /// and the translation is order 40, so one absolute accuracy for both would be either too loose
    /// for `a` or too tight for `tx`.
    private func assertMatchesMatrix(_ actual: CGAffineTransform, _ expected: CGAffineTransform,
                                     _ note: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.a, expected.a, accuracy: 1e-9, "\(note) — a", file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: 1e-9, "\(note) — b", file: file, line: line)
        XCTAssertEqual(actual.c, expected.c, accuracy: 1e-9, "\(note) — c", file: file, line: line)
        XCTAssertEqual(actual.d, expected.d, accuracy: 1e-9, "\(note) — d", file: file, line: line)
        XCTAssertEqual(actual.tx, expected.tx, accuracy: 1e-7, "\(note) — tx", file: file, line: line)
        XCTAssertEqual(actual.ty, expected.ty, accuracy: 1e-7, "\(note) — ty", file: file, line: line)
    }
}
