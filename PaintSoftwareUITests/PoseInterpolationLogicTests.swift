import XCTest
import CoreGraphics

/// Pure-geometry tests for the transform channel's pose currency — KEYFRAMES.md §2.14, §2.15 and
/// §4.3, build-order stage 5.
///
/// **Why this file exists separately from `TransformTrackLogicTests`.** `PoseQuad` and
/// `PoseInterpolation` live in `Engine/Deform`, which is `CoreGraphics` + `Foundation` only and
/// compiles standalone under `swiftc` in about five seconds — so the arithmetic below can be
/// developed in that loop rather than in a ninety-second `xcodebuild test`. Nothing here touches a
/// document, a canvas or a pixel.
///
/// **The claim under test is a negative one and it is the whole of §4.3**: *"corner-lerp is not the
/// safe alternative to matrix-lerp — it fails the same way"*. That is easy to write down and easy to
/// disbelieve, so `testCornerLerpCollapsesAQuadTheFactoredBlendCarries` measures both.
final class PoseInterpolationLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let box = CGRect(x: 100, y: 200, width: 300, height: 150)

    private var centre: CGPoint { CGPoint(x: box.midX, y: box.midY) }

    /// A map about the box's own centre, which is how every Move the artist makes is expressed.
    private func about(_ inner: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(translationX: centre.x, y: centre.y)
            .concatenating(.identity)
            .concatenating(CGAffineTransform.identity)
            .concatenating(CGAffineTransform(translationX: -centre.x, y: -centre.y))
            .concatenating(inner)
    }

    private func rotation(_ degrees: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    private func scale(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: centre.x, y: centre.y)
            .scaledBy(x: x, y: y)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    /// The alternative §4.3 refuses: lerp the four corners independently.
    private func cornerLerp(_ a: PoseQuad, _ b: PoseQuad, _ t: CGFloat) -> Quad {
        Quad((0..<4).map { i in
            CGPoint(x: a.corners[i].x + (b.corners[i].x - a.corners[i].x) * t,
                    y: a.corners[i].y + (b.corners[i].y - a.corners[i].y) * t)
        })!
    }

    private func widthScale(_ t: CGAffineTransform) -> CGFloat {
        sqrt(abs(t.a * t.d - t.b * t.c))
    }

    // MARK: - The pose itself

    /// §2.14: a pose is a box and four corners, and a drawing nobody has moved is the box's own
    /// corners. `isIdentity` is what decides whether a cel has a derivation at all, so it is exact
    /// rather than tolerant.
    func testARestingPoseIsTheBoxsOwnCornersAndReportsItself() {
        let resting = PoseQuad(restingIn: box)
        XCTAssertTrue(resting.isIdentity)
        XCTAssertEqual(resting.corners, Quad.rect(box))
        XCTAssertTrue(resting.isValid)

        var nudged = resting
        nudged.corners.p0.x += 0.5
        XCTAssertFalse(nudged.isIdentity, "Half a point is a move; there is no epsilon here on purpose")
    }

    /// The map a pose *is*, recovered from the four corners it stores. §8's measured claim about the
    /// stored-quad chain — `Homography(boxSize:to:)` then `affine()` — restated on the shipped types
    /// and on the exact composition stage 5 uses.
    func testAStoredQuadReturnsTheAffineItWasBuiltFrom() {
        for map in [rotation(37), scale(x: 3, y: 1), scale(x: 0.4, y: 0.4),
                    rotation(20).concatenating(scale(x: 2, y: 0.5))] {
            let pose = PoseQuad(box: box, mappedBy: map)
            let recovered = try? XCTUnwrap(pose.affineOrLinearised)
            guard let recovered = recovered ?? nil else { return XCTFail("A parallelogram is affine") }
            XCTAssertEqual(recovered.a, map.a, accuracy: 1e-9)
            XCTAssertEqual(recovered.b, map.b, accuracy: 1e-9)
            XCTAssertEqual(recovered.c, map.c, accuracy: 1e-9)
            XCTAssertEqual(recovered.d, map.d, accuracy: 1e-9)
            XCTAssertEqual(recovered.tx, map.tx, accuracy: 1e-6)
            XCTAssertEqual(recovered.ty, map.ty, accuracy: 1e-6)
        }
    }

    /// §3.3: `Quad` is not `Codable` and is deliberately not made so — the sidecar's wire format is
    /// this type's own eight doubles. A pose has to survive the round trip exactly, because a
    /// keyframe the artist authored is not allowed to drift by a save.
    func testAPoseRoundTripsThroughItsSidecarFormatExactly() throws {
        let pose = PoseQuad(box: box, mappedBy: rotation(23).concatenating(scale(x: 1.7, y: 0.6)))
        let data = try JSONEncoder().encode(pose)
        XCTAssertEqual(try JSONDecoder().decode(PoseQuad.self, from: data), pose)
    }

    // MARK: - §4.3

    /// **The endpoints are the keys, bit for bit.** `Matrix2x2.interpolatedFromIdentity(t: 1)`
    /// reproduces its matrix only to floating point, so a pose read back at `t == 1` would otherwise
    /// differ from the one the artist authored in the last few bits — and the same is true of the
    /// whole chain at `t == 0`. Both are short-circuited, and this is what says so.
    func testTheEndpointsAreTheAuthoredPosesRatherThanTheBlendOfThem() {
        let a = PoseQuad(restingIn: box)
        let b = PoseQuad(box: box, mappedBy: rotation(90).concatenating(scale(x: 2, y: 0.5)))
        XCTAssertEqual(PoseInterpolation.blend(a, b, t: 0), a)
        XCTAssertEqual(PoseInterpolation.blend(a, b, t: 1), b)
        XCTAssertEqual(PoseInterpolation.blend(a, b, t: -0.4), a, "Before the first key is a hold")
        XCTAssertEqual(PoseInterpolation.blend(a, b, t: 3), b, "After the last key is a hold")
    }

    /// **§4.3's negative claim, measured.** A quarter turn between two keys: the factored blend keeps
    /// the drawing's area exactly, because a rotation is a rotation at every `t`. Lerping the corners
    /// instead shrinks it to half at the midpoint, and at a **half** turn it collapses the quad to
    /// zero area and to non-convex — an in-between that is invalid between two perfectly valid keys,
    /// which is the sentence §4.3 writes down.
    ///
    /// MEASURED at 180°: factored area 45000.0 and convex, corner-lerp area 0.0 and **not** convex.
    /// At 170° and 190° the corner lerp survives convexity and is still 341.8 — 0.76% of the drawing.
    func testCornerLerpCollapsesAQuadTheFactoredBlendCarries() throws {
        let rest = PoseQuad(restingIn: box)
        let area = rest.corners.area

        for degrees: CGFloat in [90, 170, 180] {
            let turned = PoseQuad(box: box, mappedBy: rotation(degrees))
            let factored = try XCTUnwrap(PoseInterpolation.blend(rest, turned, t: 0.5))
            XCTAssertEqual(factored.corners.area, area, accuracy: area * 1e-9,
                           "A rotation preserves area at every t, and the factored form knows it")
            XCTAssertTrue(factored.corners.isConvex)

            let lerped = cornerLerp(rest, turned, 0.5)
            XCTAssertLessThan(lerped.area, area * 0.51,
                              "\(degrees)°: the alternative loses at least half the drawing")
        }
        XCTAssertFalse(cornerLerp(rest, PoseQuad(box: box, mappedBy: rotation(180)), 0.5).isConvex,
                       "At a half turn corner-lerp produces an invalid quad from two valid keys")
    }

    /// A Freeform stretch blends through its symmetric part, so half way from 1:1 to 3:1 is 2:1 —
    /// the linear answer an artist expects of a scale, and the one `Matrix2x2.polar` produces by
    /// construction rather than by a special case.
    ///
    /// The width scale is asserted beside it because that is the number the ink actually takes:
    /// LASSO_MOVE.md §5.17's `sqrt(|det|)`, which at 2:1 in one axis is √2.
    func testAStretchBlendsLinearlyInItsScaleAndTheWidthRuleFollowsIt() throws {
        let rest = PoseQuad(restingIn: box)
        let stretched = PoseQuad(box: box, mappedBy: scale(x: 3, y: 1))
        let mid = try XCTUnwrap(PoseInterpolation.blend(rest, stretched, t: 0.5))
        let map = try XCTUnwrap(mid.affineOrLinearised)
        XCTAssertEqual(map.a, 2, accuracy: 1e-9)
        XCTAssertEqual(map.d, 1, accuracy: 1e-9)
        XCTAssertEqual(widthScale(map), sqrt(2), accuracy: 1e-9)
    }

    /// **A pose pair is blended the short way round, and that is worth pinning rather than
    /// discovering.** `Matrix2x2.polar` reads the angle through `atan2`, which is principal, so two
    /// keys 190° apart rotate −170° rather than +190°. There is no neighbour to reconcile against the
    /// way `ARAPInterpolation.unwrappedAngles` has for a mesh, and every 2D animation package answers
    /// this the same way: an artist who wants the long way round adds a key in the middle.
    func testAPosePairMoreThanAHalfTurnApartTakesTheShortWayRound() throws {
        let rest = PoseQuad(restingIn: box)
        let turned = PoseQuad(box: box, mappedBy: rotation(190))
        let mid = try XCTUnwrap(PoseInterpolation.blend(rest, turned, t: 0.5))
        let map = try XCTUnwrap(mid.affineOrLinearised)
        // −95°, not +95°: cos is the same either way, so the sign of `b` is what tells them apart.
        XCTAssertEqual(atan2(map.b, map.a) * 180 / .pi, -95, accuracy: 1e-6)
    }

    /// A translation blends as a translation, and the *box centre* is what carries it — which is why
    /// a pose about a far-away origin behaves like one about the box itself.
    func testAPureTranslationBlendsLinearlyAndKeepsTheShape() throws {
        let rest = PoseQuad(restingIn: box)
        let moved = PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 400, y: -120))
        let mid = try XCTUnwrap(PoseInterpolation.blend(rest, moved, t: 0.25))
        let map = try XCTUnwrap(mid.affineOrLinearised)
        XCTAssertEqual(map.tx, 100, accuracy: 1e-9)
        XCTAssertEqual(map.ty, -30, accuracy: 1e-9)
        XCTAssertEqual(widthScale(map), 1, accuracy: 1e-12, "A move must not change ink weight")
    }

    /// **§9.1's clamp, taken deliberately.** A mirror pair has no continuous path that does not
    /// degenerate — `Matrix2x2.polar` says so — so the blend runs through a squash, and a squashed
    /// quad fails `Homography.isValidQuad`'s area floor. The answer is the nearer authored key rather
    /// than a quad the renderer cannot use.
    func testAnInvalidInBetweenClampsToTheNearerKeyRatherThanDrawingSomethingBroken() throws {
        let rest = PoseQuad(restingIn: box)
        let mirrored = PoseQuad(box: box, mappedBy: scale(x: -1, y: 1))
        let mid = try XCTUnwrap(PoseInterpolation.blend(rest, mirrored, t: 0.5))
        XCTAssertTrue(mid.isValid, "Whatever comes back is drawable, which is the whole of the clamp")

        let early = try XCTUnwrap(PoseInterpolation.blend(rest, mirrored, t: 0.45))
        let late = try XCTUnwrap(PoseInterpolation.blend(rest, mirrored, t: 0.55))
        XCTAssertEqual(early, rest, "Below the midpoint the clamp holds the key it left")
        XCTAssertEqual(late, mirrored, "Above it, the key it is heading for")
    }

    /// A degenerate key has no map, so the blend has nothing to work from and says so rather than
    /// returning a quad full of NaN that would render as nothing with no explanation.
    func testADegenerateKeyBlendsToNothingRatherThanToNaN() {
        let flat = PoseQuad(box: CGRect(x: 0, y: 0, width: 300, height: 0), corners: Quad.rect(box))
        XCTAssertNil(PoseInterpolation.blend(flat, PoseQuad(restingIn: box), t: 0.5))
        XCTAssertNil(PoseInterpolation.blend(PoseQuad(restingIn: box), flat, t: 0.5))
    }

    /// The factorisation is exact algebra rather than a fit, and for an affine — every pose stage 5
    /// can author — the projective half is exactly zero and the affine half is the map itself.
    func testFactoringAnAffineLeavesNothingInThePerspectiveRow() throws {
        let map = rotation(31).concatenating(scale(x: 1.4, y: 0.7))
        let homography = try XCTUnwrap(PoseQuad(box: box, mappedBy: map).homography)
        let parts = try XCTUnwrap(PoseInterpolation.factored(homography))
        XCTAssertEqual(parts.g, 0)
        XCTAssertEqual(parts.h, 0)
        XCTAssertEqual(parts.linear.a, map.a, accuracy: 1e-9)
        XCTAssertEqual(parts.linear.b, map.c, accuracy: 1e-9,
                       "CGAffineTransform's c is this file's b — the one place the conventions meet")
    }
}
