import XCTest
import QuartzCore

/// The projective solver, on its own — ADD_TEXT.md §3 stage 5.
///
/// **Nothing in this file touches a `TextFrame`, a `CanvasManager` or a pixel**, and that is a
/// property worth keeping rather than an accident of what was convenient. `Quad` and `Homography`
/// live in `Engine/Deform` precisely so the whole distort maths compiles standalone with `swiftc` in
/// about five seconds instead of a 90 s `xcodebuild test` (§1), and a test file that reached for an
/// app type would take that loop away from whoever changes the solver next. The text side of stage 5
/// — the seam with stage 4's `affineTransform`, the distort drag, the flat editing box — is pinned in
/// `TextTransformLogicTests`, beside the stage-4 identities it has to leave standing.
///
/// Every claim here is an **identity**, in `TextLayoutLogicTests`' sense: the corners land on the
/// corners, the inverse undoes the forward, a parallelogram has an affine matrix and a trapezoid does
/// not. None of them is a measured constant about a particular quad, because a constant is a claim
/// about the fixture and an identity is a claim about the code.
final class HomographyLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A box wide enough that a perspective divide has somewhere to act, and asymmetric so a
    /// transposed matrix cannot pass by symmetry.
    private let box = CGSize(width: 300, height: 120)

    /// A genuinely projective quad: no two edges parallel, wound clockwise on screen the way a
    /// `TextFrame`'s corners are.
    private let perspective = Quad(CGPoint(x: 100, y: 50), CGPoint(x: 520, y: 90),
                                   CGPoint(x: 470, y: 300), CGPoint(x: 140, y: 240))

    /// The same box turned and sheared but still a parallelogram — everything stage 4 could make.
    private let parallelogram = Quad(CGPoint(x: 10, y: 20), CGPoint(x: 310, y: 70),
                                     CGPoint(x: 290, y: 190), CGPoint(x: -10, y: 140))

    /// A symmetric trapezoid: the classic "wall going away from you". Not a parallelogram, so it has
    /// no affine map at all.
    private let trapezoid = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0),
                                 CGPoint(x: 260, y: 120), CGPoint(x: 40, y: 120))

    private func assertPoint(_ got: CGPoint, _ want: CGPoint, accuracy: CGFloat = 1e-9,
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.x, want.x, accuracy: accuracy, "\(message) x", file: file, line: line)
        XCTAssertEqual(got.y, want.y, accuracy: accuracy, "\(message) y", file: file, line: line)
    }

    // MARK: - The solve

    /// The defining property: the box's four corners land exactly on the quad's four corners, in
    /// order. If this is wrong nothing else in the file means anything, so it is first.
    func testTheBoxsCornersLandOnTheQuadsCorners() throws {
        let h = try XCTUnwrap(Homography(boxSize: box, to: perspective))
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: box.width, y: 0),
                       CGPoint(x: box.width, y: box.height), CGPoint(x: 0, y: box.height)]
        for (index, corner) in corners.enumerated() {
            let mapped = try XCTUnwrap(h.map(corner))
            assertPoint(mapped, perspective[index], "corner \(index)")
        }
    }

    /// **forward ∘ inverse ≈ I to 1e-9**, the tolerance ADD_TEXT.md §3 stage 5 names.
    ///
    /// Over a grid rather than at the corners: the corners are where the solve is exact by
    /// construction, and the interior is where a wrong adjugate or a dropped `1/w` actually shows.
    /// The strides are coprime with the box's extents so the samples do not all land on round
    /// numbers.
    func testForwardThenInverseIsTheIdentity() throws {
        let h = try XCTUnwrap(Homography(boxSize: box, to: perspective))
        let inverse = try XCTUnwrap(h.inverse)
        var worst: CGFloat = 0
        for x in stride(from: CGFloat(0), through: box.width, by: 17) {
            for y in stride(from: CGFloat(0), through: box.height, by: 11) {
                let point = CGPoint(x: x, y: y)
                let round = try XCTUnwrap(inverse.map(XCTUnwrap(h.map(point))))
                worst = max(worst, max(abs(round.x - point.x), abs(round.y - point.y)))
            }
        }
        XCTAssertLessThan(worst, 1e-9, "A round trip through H and H⁻¹ must return the point it started from.")
    }

    /// And the matrix product itself, which is the same claim without the sampling: `H · H⁻¹` is the
    /// identity up to the overall scale a homography is defined to within.
    func testTheMatrixProductWithItsInverseIsTheIdentityUpToScale() throws {
        let h = try XCTUnwrap(Homography(boxSize: box, to: perspective))
        let product = h * (try XCTUnwrap(h.inverse))
        let scale = product.i
        XCTAssertGreaterThan(abs(scale), 1e-12, "A product with an inverse cannot be singular.")
        let normalised = (1 / scale) * product
        for (got, want) in zip([normalised.a, normalised.b, normalised.c,
                                normalised.d, normalised.e, normalised.f,
                                normalised.g, normalised.h, normalised.i],
                               [1, 0, 0, 0, 1, 0, 0, 0, 1] as [CGFloat]) {
            XCTAssertEqual(got, want, accuracy: 1e-12)
        }
    }

    // MARK: - Affine or not

    /// `affine()` is non-nil for a parallelogram and **nil for a trapezoid** — ADD_TEXT.md §3 stage
    /// 5's own wording, and the branch that decides whether text draws as glyphs through one matrix
    /// or as a resampled bitmap.
    ///
    /// The parallelogram's matrix is checked against the map itself rather than against written-down
    /// numbers: the affine transform must send the box's corners where the homography sends them, or
    /// it is a fast path to somewhere else.
    func testAParallelogramHasAnAffineMatrixAndATrapezoidHasNone() throws {
        let flat = try XCTUnwrap(Homography(boxSize: box, to: parallelogram))
        let affine = try XCTUnwrap(flat.affine(), "A parallelogram is an affine image of the box.")
        for (index, corner) in [CGPoint(x: 0, y: 0), CGPoint(x: box.width, y: 0),
                                CGPoint(x: box.width, y: box.height),
                                CGPoint(x: 0, y: box.height)].enumerated() {
            assertPoint(corner.applying(affine), parallelogram[index], accuracy: 1e-9,
                        "affine corner \(index)")
        }

        let skewed = try XCTUnwrap(Homography(boxSize: box, to: trapezoid))
        XCTAssertNil(skewed.affine(),
                     "A trapezoid has a perspective term; calling it affine is how interior lines bow.")
        XCTAssertNotEqual(skewed.g == 0 && skewed.h == 0, true,
                          "The refusal must come from a real perspective term, not from a nil solve.")
    }

    /// The affine branch is taken from the *quad*, not from the mode a caller declares, and the
    /// perspective term it produces is exactly zero rather than merely small — which is what lets
    /// `affine()` default to a zero tolerance instead of carrying an epsilon to every call site.
    func testAParallelogramsPerspectiveTermIsExactlyZero() throws {
        let flat = try XCTUnwrap(Homography(boxSize: box, to: parallelogram))
        XCTAssertEqual(flat.g, 0)
        XCTAssertEqual(flat.h, 0)
    }

    // MARK: - Degeneracy

    /// Three collinear corners have no solution — and the two ways they can be collinear are caught
    /// by two *different* guards, which is why both are here.
    ///
    /// Corners 1, 2 and 3 are what Heckbert's `den` sees. Corners 0, 1 and 2 are invisible to it and
    /// fall out of the determinant check instead; a solver carrying only the published `den` guard
    /// passes the first of these and returns a singular matrix for the second.
    func testThreeCollinearCornersHaveNoSolution() {
        let corners123 = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100),
                              CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 120))
        XCTAssertNil(Homography(boxSize: box, to: corners123),
                     "den ≈ 0: corners 1, 2 and 3 are on one line.")

        let corners012 = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
                              CGPoint(x: 200, y: 0), CGPoint(x: 90, y: 140))
        XCTAssertNil(Homography(boxSize: box, to: corners012),
                     "determinant ≈ 0: corners 0, 1 and 2 are on one line, which `den` cannot see.")

        XCTAssertFalse(Homography.isValidQuad(corners123, boxSize: box))
        XCTAssertFalse(Homography.isValidQuad(corners012, boxSize: box))
    }

    /// A box with no extent has no map onto anything.
    func testACollapsedBoxHasNoSolution() {
        XCTAssertNil(Homography(boxSize: CGSize(width: 0, height: 120), to: perspective))
        XCTAssertNil(Homography(boxSize: CGSize(width: 300, height: 0), to: perspective))
    }

    // MARK: - The vanishing line

    /// **A corner past the vanishing line is rejected by `w > 0`** — ADD_TEXT.md §1's specific
    /// failure mode, "the specific way a homography produces silent visual garbage rather than a
    /// crash".
    ///
    /// The quad is built *from* a chosen perspective term rather than typed in, because "past the
    /// vanishing line" is a statement about the map and not about coordinates: `g = −1.5` puts the
    /// weight at the box's top-right corner at `1 + g = −0.5`, and the assertion below is that the
    /// solver recovers exactly that rather than an innocent-looking positive one.
    ///
    /// **The `w > 0` term is not independent of convexity, and this test says so out loud.** A
    /// projective map carries the unit square to a convex quad exactly when the whole square stays on
    /// one side of the vanishing line, so any quad failing `w > 0` also fails `isConvex` — as this one
    /// does, and the test asserts both. What the weight assertion buys is that the *reason* is pinned:
    /// a future change that loosened convexity would still be caught here, and a reader is told the
    /// two checks overlap rather than being left to discover it.
    func testACornerPastTheVanishingLineIsRejected() throws {
        let projected = Homography(a: box.width, b: 0, c: 0, d: 0, e: box.height, f: 0,
                                   g: -1.5, h: 0, i: 1)
        let corners = try [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                           CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)].map { try XCTUnwrap(projected.map($0)) }
        let quad = try XCTUnwrap(Quad(corners))

        let solved = try XCTUnwrap(Homography(boxSize: box, to: quad))
        let weights = solved.weightsAtBoxCorners(box)
        XCTAssertEqual(weights[1], -0.5, accuracy: 1e-9,
                       "The solve must recover the perspective term the quad was built from.")
        XCTAssertTrue(weights.contains { $0 <= 0 }, "Two corners are behind the vanishing line.")
        XCTAssertFalse(Homography.isValidQuad(quad, boxSize: box))
        XCTAssertFalse(quad.isConvex, "Convexity catches the same quad — the two terms overlap by theorem.")
    }

    /// The predicate's other three terms, each isolated: a bowtie, a quad squeezed below the area
    /// floor, and a good quad that must pass so the test above is not passing vacuously.
    func testTheValidityPredicatesOtherTermsEachRejectOnTheirOwn() {
        XCTAssertTrue(Homography.isValidQuad(perspective, boxSize: box),
                      "A sane quad has to pass, or every rejection below proves nothing.")

        // Corners 2 and 3 exchanged: the edges cross.
        let bowtie = Quad(perspective.p0, perspective.p1, perspective.p3, perspective.p2)
        XCTAssertFalse(bowtie.isSimple)
        XCTAssertFalse(Homography.isValidQuad(bowtie, boxSize: box))

        // A sliver a fraction of a square point in area.
        let sliver = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
                          CGPoint(x: 10, y: 0.01), CGPoint(x: 0, y: 0.02))
        XCTAssertLessThan(sliver.area, Quad.minimumArea)
        XCTAssertFalse(Homography.isValidQuad(sliver, boxSize: box))
    }

    // MARK: - Clamping

    /// **Clamping holds the last valid quad** — ADD_TEXT.md §1's rule, expressed at the level the
    /// solver actually decides it: a caller that writes only on acceptance keeps whatever it last
    /// accepted, and the run of rejections in the middle of a drag leaves no trace.
    ///
    /// The path walks the bottom-right corner straight through the opposite corner and out the far
    /// side. Every step past the crossing is refused, so the quad the loop ends holding is the last
    /// one before it — **not** the starting quad, which is the distinction between clamping and
    /// cancelling, and not the finger's position, which is the distinction between clamping and
    /// rendering garbage.
    func testClampingHoldsTheLastValidQuadRatherThanTheFirstOrTheFingers() throws {
        let start = Quad.rect(CGRect(x: 0, y: 0, width: box.width, height: box.height))
        var held = start
        var lastAccepted: CGPoint?
        var rejections = 0
        // From well outside the box, through the opposite corner at (0,0), and beyond it.
        for step in 0...60 {
            let t = CGFloat(step) / 60
            let target = CGPoint(x: 400 - 500 * t, y: 220 - 300 * t)
            var candidate = held
            candidate[2] = target
            if Homography.isValidQuad(candidate, boxSize: box) {
                held = candidate
                lastAccepted = target
            } else {
                rejections += 1
            }
        }
        XCTAssertGreaterThan(rejections, 0, "The path has to cross the opposite corner, or nothing was clamped.")
        let accepted = try XCTUnwrap(lastAccepted)
        assertPoint(held[2], accepted, accuracy: 1e-12,
                    "The held quad is the last one that passed, not the one under the finger.")
        XCTAssertNotEqual(held[2], start[2], "And not the quad the drag started from either.")
        XCTAssertTrue(Homography.isValidQuad(held, boxSize: box), "What is held must itself be valid.")
    }

    // MARK: - Core Animation

    /// **The nine `CATransform3D` elements, asserted as numbers rather than compared as pixels** —
    /// ADD_TEXT.md §3 stage 5 asks for exactly this test, and the reason is that the embedding is a
    /// transposition: Core Animation is row-vector (`p' = p · M`), so `b` lands on `m21` and not on
    /// `m12`. Written the naive way round the artwork shears instead of foreshortening, which looks
    /// like a plausible bug in the solver and is not.
    ///
    /// The other seven elements are asserted too. A stray non-zero in the third row or column is a
    /// z-term on a flat layer, and it survives every corner test because the corners have `z = 0`.
    func testTheCATransform3DIsTheTransposedEmbeddingCoreAnimationWants() throws {
        let h = try XCTUnwrap(Homography(boxSize: box, to: perspective))
        let t = h.catransform3D

        XCTAssertEqual(t.m11, h.a, accuracy: 1e-15)
        XCTAssertEqual(t.m21, h.b, accuracy: 1e-15)
        XCTAssertEqual(t.m41, h.c, accuracy: 1e-15)
        XCTAssertEqual(t.m12, h.d, accuracy: 1e-15)
        XCTAssertEqual(t.m22, h.e, accuracy: 1e-15)
        XCTAssertEqual(t.m42, h.f, accuracy: 1e-15)
        XCTAssertEqual(t.m14, h.g, accuracy: 1e-15)
        XCTAssertEqual(t.m24, h.h, accuracy: 1e-15)
        XCTAssertEqual(t.m44, h.i, accuracy: 1e-15)

        XCTAssertEqual(t.m33, 1, accuracy: 1e-15, "A flat layer keeps the identity in z.")
        for zero in [t.m13, t.m23, t.m31, t.m32, t.m34, t.m43] {
            XCTAssertEqual(zero, 0, accuracy: 1e-15, "Nothing else may be non-zero on a flat layer.")
        }

        // And the transposition itself, stated as the thing it exists for: pushing a row vector
        // through the matrix must reproduce the homography's own answer.
        let point = CGPoint(x: 91, y: 37)
        let x = t.m11 * point.x + t.m21 * point.y + t.m41
        let y = t.m12 * point.x + t.m22 * point.y + t.m42
        let w = t.m14 * point.x + t.m24 * point.y + t.m44
        assertPoint(CGPoint(x: x / w, y: y / w), try XCTUnwrap(h.map(point)), accuracy: 1e-9,
                    "row-vector product")
    }

    // MARK: - Magnification

    /// `maximumCornerScale` is 1 for a map that changes no size, and is the near corner's
    /// magnification for one that does — the number that sizes a backing store, so an answer that
    /// silently stayed at 1 would show up as a soft warp rather than as a failure.
    func testTheCornerScaleIsOneForARigidMapAndLargerForAForeshortenedOne() throws {
        let rigid = try XCTUnwrap(Homography(boxSize: box,
                                             to: Quad.rect(CGRect(x: 40, y: 90,
                                                                  width: box.width, height: box.height))))
        XCTAssertEqual(rigid.maximumCornerScale(ofBox: box), 1, accuracy: 1e-9)

        let doubled = try XCTUnwrap(Homography(boxSize: box,
                                               to: Quad.rect(CGRect(x: 0, y: 0,
                                                                    width: box.width * 2,
                                                                    height: box.height * 2))))
        XCTAssertEqual(doubled.maximumCornerScale(ofBox: box), 2, accuracy: 1e-9)

        let foreshortened = try XCTUnwrap(Homography(boxSize: box, to: trapezoid))
        XCTAssertGreaterThan(foreshortened.maximumCornerScale(ofBox: box), 1,
                             "The near edge of a trapezoid is magnified relative to the far one.")
    }

    /// `linearised` keeps the map's rotation and scale and drops the divide: at the point it is taken,
    /// it agrees with the homography exactly, and it has no perspective term of its own.
    func testTheLinearisedMapAgreesAtItsOwnPointAndHasNoPerspective() throws {
        let h = try XCTUnwrap(Homography(boxSize: box, to: perspective))
        let centre = CGPoint(x: box.width / 2, y: box.height / 2)
        let flat = try XCTUnwrap(h.linearised(at: centre))
        assertPoint(centre.applying(flat), try XCTUnwrap(h.map(centre)), accuracy: 1e-9,
                    "the point it was taken at")
        // An affine transform has no perspective by construction; the claim worth checking is that it
        // is not merely the identity or a translation — it carries the map's actual linear part.
        let rotationless = abs(flat.b) < 1e-12 && abs(flat.c) < 1e-12
        XCTAssertFalse(rotationless && abs(flat.a - 1) < 1e-12 && abs(flat.d - 1) < 1e-12,
                       "The linearisation has to carry the map's scale and shear, not just its position.")
    }
}
