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

    // MARK: - Overshoot

    /// **`blend` extrapolates outside `0...1`; it does not clamp to the keys.** KEYFRAMES.md §3.2
    /// decision 1 and this file's own header both say so, `TransformTrack`'s header says *"a move can
    /// overshoot its mark and settle back"*, and `TransformTrack.pose(atCelLocalTime:)` says the
    /// fraction is *"deliberately left unclamped"* because this function *"extrapolates correctly for
    /// it"*.
    ///
    /// **It did not, from stage 5 until 2026-09-02**, because the two endpoint shortcuts were spelled
    /// `t <= 0` and `t >= 1` rather than `t == 0` and `t == 1` — so every overshoot an authored handle
    /// produced was flattened onto the key it was meant to sail past, with four prose statements of
    /// the opposite standing over it and nothing red.
    ///
    /// A translation is the operand, because it extrapolates without limit in both directions and so
    /// nothing here can be satisfied by the §9.1 validity clamp instead.
    func testABlendPastEitherKeyExtrapolatesRatherThanClampingToIt() throws {
        let a = PoseQuad(restingIn: box)
        let b = PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 100, y: 0))

        let over = try XCTUnwrap(PoseInterpolation.blend(a, b, t: 1.25))
        XCTAssertEqual(over.corners.p0.x - box.minX, 125, accuracy: 1e-6,
                       "t = 1.25 is a quarter past the second key, not the second key")
        let under = try XCTUnwrap(PoseInterpolation.blend(a, b, t: -0.25))
        XCTAssertEqual(under.corners.p0.x - box.minX, -25, accuracy: 1e-6,
                       "and the same in the other direction, which a `0...1` range clamp would hide")

        // The whole width of the box travels, so this is the map extrapolating rather than one corner
        // drifting — a clamp on one axis would leave the other corners on the key.
        XCTAssertEqual(over.corners.p2.x - box.maxX, 125, accuracy: 1e-6)
        XCTAssertEqual(over.box, a.box, "and the rest box is unchanged by a pure translation")
    }

    /// **Where the extrapolation stops, and it is §9.1 rather than a limit of the arithmetic.**
    /// `interpolatedFromIdentity` blends the symmetric part linearly, so extrapolating a `k`× scale
    /// passes through a singular map at `t = k / (k - 1)` — `t = 2` for the 2× shrink below. The
    /// `isValid` guard catches that and returns the nearer key, which is §9.1's *"clamp to the last
    /// valid pose"* doing its job. Pinned so a later reader does not mistake it for the clamp this
    /// file has just removed.
    func testAScaleExtrapolatesUntilItGoesSingularAndThenTakesTheNearerKey() throws {
        let big = PoseQuad(box: box, mappedBy: scale(x: 2, y: 2))
        let rest = PoseQuad(restingIn: box)

        let mild = try XCTUnwrap(PoseInterpolation.blend(big, rest, t: 1.5))
        let width = mild.corners.p1.x - mild.corners.p0.x
        XCTAssertLessThan(width, box.width, "past the rest pose the shrink keeps shrinking")
        XCTAssertGreaterThan(width, 0)

        XCTAssertEqual(try XCTUnwrap(PoseInterpolation.blend(big, rest, t: 2)), rest,
                       "at the singular point the nearer key stands in")
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
            let recovered = try? XCTUnwrap(pose.affine)
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
    ///
    /// **It used to assert two more lines than that, and they were wrong** — `blend(a, b, t: -0.4) ==
    /// a` and `blend(a, b, t: 3) == b`, captioned *"before the first key is a hold"* and *"after the
    /// last key is a hold"*. The **hold is real and lives one level up**: `AnimationCurve`'s decision
    /// 2 holds the *timing* curve flat outside its first and last key and
    /// `TransformTrack.pose(atCelLocalTime:)` clamps the segment index, so a frame off either end of a
    /// channel never reaches this function with a `t` outside `0...1` at all
    /// (`TransformTrackLogicTests.testOutsideTheKeysThePoseIsHeldRatherThanExtrapolated` is where that
    /// belongs). What *does* arrive here outside `0...1` is an overshooting handle **inside** a
    /// segment, which §3.2 decision 1 exists to allow — so those two lines pinned a hold the caller
    /// already guarantees and, with it, the `t <= 0` / `t >= 1` clamp that flattened every overshoot.
    /// A green test held the defect in place for the length of stage 5.
    func testTheEndpointsAreTheAuthoredPosesRatherThanTheBlendOfThem() {
        let a = PoseQuad(restingIn: box)
        let b = PoseQuad(box: box, mappedBy: rotation(90).concatenating(scale(x: 2, y: 0.5)))
        XCTAssertEqual(PoseInterpolation.blend(a, b, t: 0), a)
        XCTAssertEqual(PoseInterpolation.blend(a, b, t: 1), b)
        XCTAssertNil(PoseInterpolation.blend(a, b, t: .nan), "and a non-finite t is refused outright")
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
        let map = try XCTUnwrap(mid.affine)
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
        let map = try XCTUnwrap(mid.affine)
        // 190° reads as −170° through `atan2`, so the midpoint is **−85°** rather than +95°. Written
        // out as the arithmetic rather than as a number, because the number on its own reads like a
        // typo for +95 and is the whole point of the test.
        XCTAssertEqual(atan2(map.b, map.a) * 180 / .pi, -170 / 2, accuracy: 1e-6)
    }

    /// A translation blends as a translation, and the *box centre* is what carries it — which is why
    /// a pose about a far-away origin behaves like one about the box itself.
    func testAPureTranslationBlendsLinearlyAndKeepsTheShape() throws {
        let rest = PoseQuad(restingIn: box)
        let moved = PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 400, y: -120))
        let mid = try XCTUnwrap(PoseInterpolation.blend(rest, moved, t: 0.25))
        let map = try XCTUnwrap(mid.affine)
        XCTAssertEqual(map.tx, 100, accuracy: 1e-9)
        XCTAssertEqual(map.ty, -30, accuracy: 1e-9)
        XCTAssertEqual(widthScale(map), 1, accuracy: 1e-12, "A move must not change ink weight")
    }

    /// **§9.1's clamp, taken deliberately.** A mirror pair has no continuous path that does not
    /// degenerate — `Matrix2x2.polar` says so — so the blend runs through a squash, and a squashed
    /// quad fails `Homography.isValidQuad`'s area floor. The answer is the nearer authored key rather
    /// than a quad the renderer cannot use.
    ///
    /// **The invalid band is narrower than it looks and the first draft of this test was wrong about
    /// it.** `Matrix2x2.polar` of `diag(-1, 1)` is `(I, diag(-1, 1))`, so the blended linear part is
    /// `diag(1 - 2t, 1)` — singular at exactly `t = 0.5` and a perfectly drawable narrow quad either
    /// side of it. So the assertion worth making is not "the middle of the span is clamped" but
    /// **every sample is drawable**, with the one degenerate `t` answering with an authored key.
    func testAnInvalidInBetweenClampsToTheNearerKeyRatherThanDrawingSomethingBroken() throws {
        let rest = PoseQuad(restingIn: box)
        let mirrored = PoseQuad(box: box, mappedBy: scale(x: -1, y: 1))

        for step in 0...20 {
            let t = CGFloat(step) / 20
            let pose = try XCTUnwrap(PoseInterpolation.blend(rest, mirrored, t: t),
                                     "t = \(t) must answer with something")
            XCTAssertTrue(pose.isValid, "t = \(t) must be drawable")
        }
        XCTAssertEqual(PoseInterpolation.blend(rest, mirrored, t: 0.5), mirrored,
                       "The one t whose blend is singular answers with the key it is heading for")
        let nearby = try XCTUnwrap(PoseInterpolation.blend(rest, mirrored, t: 0.4))
        XCTAssertNotEqual(nearby, rest)
        XCTAssertNotEqual(nearby, mirrored, "Either side of it the blend is a real in-between")
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
