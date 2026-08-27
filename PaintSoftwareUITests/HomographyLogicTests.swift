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

    /// **The `den` guard, on its own, on the only input that reaches it** — and the test above does
    /// not reach it, which is why this one exists.
    ///
    /// Delete `guard abs(den) > Quad.epsilon` and `testThreeCollinearCornersHaveNoSolution` stays
    /// green: both of its quads are *exactly* collinear, so `den` is exactly 0, `g` and `h` come out
    /// infinite, the determinant comes out `0` or `NaN`, and the determinant guard catches what the
    /// `den` guard was supposed to. Measured on the second of them: without the guard, `den = -12000`
    /// — it is not even the `den` branch that rejects it — and the first gives `det = 0.0`. The
    /// guard had zero coverage.
    ///
    /// What reaches it is a quad whose corners 1, 2 and 3 are *almost* collinear: `den` small but
    /// finite, so `g` and `h` are enormous but finite and the determinant is enormous rather than
    /// zero. **Measured on the quad below: `den = 9.9e-11`, inside the guard; with the guard deleted
    /// `g = h = -1.0e14` and `det = 2.0e32`, which sails past `abs(det) > Quad.epsilon` and returns a
    /// matrix.** That matrix is garbage, and it is *reachable on the drawing path*:
    /// `TextFrame.homography` calls this initialiser directly, without `isValidQuad` in front of it,
    /// so a decoded document with such a quad would be warped through it rather than refused.
    ///
    /// The fixture asserts its own `den` before asserting the refusal. A test that only said "nil"
    /// would still pass if the quad drifted into the determinant guard's territory, and would then
    /// be a second copy of the test above rather than this one.
    func testTheDenGuardRefusesAlmostCollinearCornersTheDeterminantWouldWaveThrough() {
        let nudge: CGFloat = 1e-12
        let quad = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
                        CGPoint(x: 100, y: 100), CGPoint(x: 100 + nudge, y: 200))

        // Heckbert's `den`, computed here rather than trusted: the cross product of (p1 − p2) and
        // (p3 − p2), i.e. twice the area of the triangle those three corners make.
        let den = (quad.p1.x - quad.p2.x) * (quad.p3.y - quad.p2.y)
                - (quad.p3.x - quad.p2.x) * (quad.p1.y - quad.p2.y)
        XCTAssertGreaterThan(abs(den), 0,
                             "Exactly collinear is the other test's case; this one must be merely nearly so.")
        XCTAssertLessThanOrEqual(abs(den), Quad.epsilon,
                                 "The fixture has to land inside the `den` guard, or it tests nothing.")

        XCTAssertNil(Homography(boxSize: box, to: quad),
                     "den ≈ 0 but not 0: without the guard this returns a matrix with g and h at 1e14.")
        XCTAssertNil(Homography(unitSquareTo: quad, parallelogramTolerance: 1e-6))
        XCTAssertFalse(Homography.isValidQuad(quad, boxSize: box))
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

    /// **The `w > 0` term inside `isValidQuad` is redundant, and this is the measurement that says
    /// so** rather than a claim taken from the doc comment above it.
    ///
    /// A reviewer's finding was that deleting `weightsAtBoxCorners(...).allSatisfy { $0 > 0 }` from
    /// `isValidQuad` leaves the whole suite green, and asked for the quad that distinguishes it. There
    /// is no such quad, and the reason is the theorem `isValidQuad`'s own comment states: a projective
    /// map carries the unit square to a convex quadrilateral exactly when the square stays on one side
    /// of the vanishing line. **MEASURED, 2026-08-26: over 2,000,000 random quads plus the systematic
    /// sweep below, 1,536,828 had a non-positive weight at some box corner and not one of them was
    /// convex.** So the term cannot be pinned by a fixture; what can be pinned is the theorem, which is
    /// what makes the term redundant in the first place.
    ///
    /// That is worth a test rather than a shrug, because the redundancy is exactly what a future change
    /// would break silently. Loosen `isConvex` — to weak convexity, or to drop `isSimple`, or to admit
    /// a quad whose turn is inside `Quad.epsilon` — and the weight term stops being redundant and
    /// starts being the only thing standing between a decoded document and ADD_TEXT.md §1's "silent
    /// visual garbage". This test fails the moment that happens, and names which side moved.
    ///
    /// The weights are computed from the *quad* here, through the solver, and not from the matrix the
    /// sweep built them with — otherwise the assertion would be about `Homography.map` rather than
    /// about the predicate.
    func testEveryQuadTheWeightTermRejectsIsAlreadyRejectedByConvexity() throws {
        var crossings = 0, convexCrossings = 0
        // g and h are the whole of the perspective. `g = -1` puts corner 1 exactly on the vanishing
        // line, so a sweep either side of it is a sweep across the failure this term exists for.
        for gStep in -30...10 {
            for hStep in -30...10 {
                let gTerm = CGFloat(gStep) / 10, hTerm = CGFloat(hStep) / 10
                let source = Homography(a: box.width, b: 0, c: 0, d: 0, e: box.height, f: 0,
                                        g: gTerm, h: hTerm, i: 1)
                let corners = Quad.unitSquare.points.compactMap { source.map($0) }
                guard corners.count == 4, let quad = Quad(corners),
                      let solved = Homography(boxSize: box, to: quad) else { continue }
                guard !solved.weightsAtBoxCorners(box).allSatisfy({ $0 > 0 }) else { continue }
                crossings += 1
                if quad.isConvex && quad.isSimple && quad.area >= Quad.minimumArea {
                    convexCrossings += 1
                }
                XCTAssertFalse(Homography.isValidQuad(quad, boxSize: box),
                               "g=\(gTerm) h=\(hTerm): a quad with a corner past the vanishing line is invalid.")
            }
        }
        XCTAssertGreaterThan(crossings, 100,
                             "The sweep never crossed the vanishing line, so it measured nothing.")
        XCTAssertEqual(convexCrossings, 0,
                       "\(convexCrossings) quads now fail `w > 0` while passing convexity — the term "
                       + "in `isValidQuad` has stopped being redundant and is now load-bearing on its own.")
    }

    /// And the weights themselves do not depend on the box, which is why the sweep above can use one.
    ///
    /// For a matrix from `init(boxSize:to:)` the third row is `[g/w, h/h, 1]`, so the weights at the
    /// box's own corners come out `1, 1+g, 1+g+h, 1+h` — the unit square's, whatever the box. A reader
    /// who assumed otherwise would think `isValidQuad` could accept a quad for one box size and refuse
    /// it for another, and would test the wrong thing.
    func testTheBoxCornerWeightsAreTheUnitSquaresWhateverTheBoxSize() throws {
        let reference = try XCTUnwrap(Homography(boxSize: box, to: perspective)).weightsAtBoxCorners(box)
        for size in [CGSize(width: 1, height: 1), CGSize(width: 4000, height: 17),
                     CGSize(width: 33, height: 2500)] {
            let other = try XCTUnwrap(Homography(boxSize: size, to: perspective)).weightsAtBoxCorners(size)
            for (got, want) in zip(other, reference) {
                XCTAssertEqual(got, want, accuracy: 1e-12, "box \(size)")
            }
        }
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

    /// **The four Jacobian entries against finite differences of the real map** — and the test above
    /// does not pin them, which is why this one exists.
    ///
    /// A reviewer's finding: replace `linearised`'s perspective-corrected entries with the naive
    /// `a/w, b/w, d/w, e/w` and the whole suite stays green. It does, because the translation is
    /// *solved* to put `point` on its own image whatever the linear part is — so the agreement
    /// assertion above holds for any Jacobian at all, and the "not the identity" assertion holds for
    /// the wrong one too. Only a derivative can tell the two apart, and only where `g` and `h` are
    /// non-zero, because the two forms are identical for an affine map.
    ///
    /// Central differences at a step of 0.01 canvas points. Their own truncation error is second
    /// order — **MEASURED: worst 2.7e-6 absolute on the strongest quad here, 1.3e-9 on the others** —
    /// so the tolerance sits about fifty times above the worst of them and still tens of thousands of
    /// times below the thing it is discriminating against.
    ///
    /// **The discrimination is asserted, not assumed.** The final claim measures how far the naive
    /// form actually is at these points, so a future step size or tolerance that quietly stopped
    /// separating them fails here rather than passing quietly. MEASURED: the naive entries are wrong
    /// by 0.78–7.05 absolute, up to 194× the true entry.
    ///
    /// Two shipped behaviours read these numbers: `TextLayout.warpSourceScale` sizes the glyph bitmap
    /// from them, and `TextOverlayView.warpMagnification` sizes the live overlay's backing store. Both
    /// come through `maximumCornerScale`, pinned in the test below this one.
    func testTheLinearisationIsTheRealJacobianAndNotTheMatrixOverTheWeight() throws {
        let step: CGFloat = 0.01
        for (name, quad) in [("perspective", perspective), ("trapezoid", trapezoid)] {
            let h = try XCTUnwrap(Homography(boxSize: box, to: quad))
            XCTAssertFalse(h.g == 0 && h.h == 0,
                           "\(name) has no perspective term, so it cannot separate the two forms.")
            var worstNaive: CGFloat = 0

            for x in stride(from: CGFloat(3), through: box.width - 3, by: 37) {
                for y in stride(from: CGFloat(3), through: box.height - 3, by: 23) {
                    let point = CGPoint(x: x, y: y)
                    let jacobian = try XCTUnwrap(h.linearised(at: point))
                    let plusX = try XCTUnwrap(h.map(CGPoint(x: x + step, y: y)))
                    let minusX = try XCTUnwrap(h.map(CGPoint(x: x - step, y: y)))
                    let plusY = try XCTUnwrap(h.map(CGPoint(x: x, y: y + step)))
                    let minusY = try XCTUnwrap(h.map(CGPoint(x: x, y: y - step)))

                    // `CGAffineTransform` maps (x,y) → (a·x + c·y + tx, b·x + d·y + ty), so `a` is
                    // ∂x′/∂x, `b` is ∂y′/∂x, `c` is ∂x′/∂y and `d` is ∂y′/∂y. Getting that pairing
                    // wrong is itself one of the things this catches.
                    let differences = [(jacobian.a, (plusX.x - minusX.x) / (2 * step), "∂x′/∂x"),
                                       (jacobian.b, (plusX.y - minusX.y) / (2 * step), "∂y′/∂x"),
                                       (jacobian.c, (plusY.x - minusY.x) / (2 * step), "∂x′/∂y"),
                                       (jacobian.d, (plusY.y - minusY.y) / (2 * step), "∂y′/∂y")]
                    for (got, want, label) in differences {
                        XCTAssertEqual(got, want, accuracy: 1e-5 * max(1, abs(want)),
                                       "\(name) at \(point): \(label)")
                    }

                    let w = h.weight(at: point)
                    for (got, naive) in [(jacobian.a, h.a / w), (jacobian.b, h.d / w),
                                         (jacobian.c, h.b / w), (jacobian.d, h.e / w)] {
                        worstNaive = max(worstNaive, abs(got - naive))
                    }
                }
            }
            XCTAssertGreaterThan(worstNaive, 0.1,
                                 "\(name): the naive `a/w` form is within 0.1 of the true Jacobian "
                                 + "everywhere sampled, so this fixture cannot discriminate.")
        }
    }

    /// `localScale` is the map's **real** area magnification, and `maximumCornerScale` is the largest
    /// of the four — which is the number `TextLayout.warpSourceScale` and `TextFrame.warpMagnification`
    /// both size a backing store from.
    ///
    /// The existing corner-scale test cannot separate the true Jacobian from the naive one: its rigid
    /// and doubled quads are affine, where the two forms agree exactly, and its trapezoid assertion is
    /// only `> 1`, which the naive form also satisfies. So this asks the question the shipped behaviour
    /// actually depends on — how much smaller is a source patch than its image — against finite
    /// differences of the map, at the four corners `maximumCornerScale` samples.
    ///
    /// MEASURED on the `perspective` quad: the true corner scales are 1.503, 1.974, 1.337 and 1.079,
    /// against the naive form's 1.503, 1.802, 1.390 and 1.205 — so the number that sizes the bitmap
    /// comes out 8.7% low at the near corner. The last assertion is that gap, stated as a fraction so
    /// it is a claim about the two formulas rather than about this quad's arithmetic.
    func testTheCornerScaleIsTheMapsRealAreaMagnification() throws {
        let h = try XCTUnwrap(Homography(boxSize: box, to: perspective))
        let step: CGFloat = 0.01
        var scales: [CGFloat] = [], naiveScales: [CGFloat] = []

        for corner in Quad.rect(CGRect(origin: .zero, size: box)).points {
            let got = try XCTUnwrap(h.localScale(at: corner))
            let plusX = try XCTUnwrap(h.map(CGPoint(x: corner.x + step, y: corner.y)))
            let minusX = try XCTUnwrap(h.map(CGPoint(x: corner.x - step, y: corner.y)))
            let plusY = try XCTUnwrap(h.map(CGPoint(x: corner.x, y: corner.y + step)))
            let minusY = try XCTUnwrap(h.map(CGPoint(x: corner.x, y: corner.y - step)))
            let dxdx = (plusX.x - minusX.x) / (2 * step), dydx = (plusX.y - minusX.y) / (2 * step)
            let dxdy = (plusY.x - minusY.x) / (2 * step), dydy = (plusY.y - minusY.y) / (2 * step)
            XCTAssertEqual(got, abs(dxdx * dydy - dxdy * dydx).squareRoot(), accuracy: 1e-6,
                           "corner \(corner): the local scale is √|det J| of the map itself.")
            scales.append(got)

            let w = h.weight(at: corner)
            naiveScales.append(abs((h.a / w) * (h.e / w) - (h.b / w) * (h.d / w)).squareRoot())
        }

        let largest = try XCTUnwrap(scales.max())
        XCTAssertEqual(h.maximumCornerScale(ofBox: box), largest, accuracy: 1e-12,
                       "`maximumCornerScale` is the largest of the four corner scales and nothing else.")
        let naiveLargest = try XCTUnwrap(naiveScales.max())
        XCTAssertGreaterThan(abs(largest - naiveLargest) / largest, 0.05,
                             "The naive Jacobian gives the same backing-store size here, so this "
                             + "fixture cannot tell a mis-sized bitmap from a correct one.")
    }
}
