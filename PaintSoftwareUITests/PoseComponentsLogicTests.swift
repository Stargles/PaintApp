import XCTest
import CoreGraphics

/// **The six curves a pose is read as, and the round trip back into it** — KEYFRAMES.md §11.7's
/// first ruling, the owner's one word: *"decomposed"*.
///
/// This is the file the transform band's honesty rests on. The band itself does nothing new — it
/// draws six ordinary `AnimationCurve`s — so every way the feature can be *wrong* is in here: a
/// decomposition that names the wrong quantity, a recomposition that is not its inverse, an edit to
/// one component that moves another, or a projective pose flattened into an affine one without
/// saying so.
///
/// **Three of the tests below could each be written in a vacuous form and are deliberately not.**
/// "Decomposition returns six numbers" is true of any implementation whatever and measures a
/// definition rather than the code (CLAUDE.md's rule, and this repo has lost a pass to it four
/// times). So the assertions here are: the numbers equal ones computed *independently* of the
/// function under test, the round trip returns the pose it was given, and an edit to one component
/// is visible in that component and invisible in the other five.
@MainActor
final class PoseComponentsLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A box that is neither at the origin nor square, so a decomposition that quietly assumes
    /// either has somewhere to go wrong.
    private var box: CGRect { CGRect(x: 12, y: -7, width: 40, height: 24) }

    private func pose(_ transform: CGAffineTransform) -> PoseQuad {
        PoseQuad(box: box, mappedBy: transform)
    }

    /// Rotation about the box's own centre, which is where an artist's Move box turns.
    private func rotation(_ degrees: CGFloat) -> CGAffineTransform {
        let centre = CGPoint(x: box.midX, y: box.midY)
        return CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    /// Every kind of affine pose the app can author, plus two it cannot yet — named, so a failure
    /// says which one broke.
    private var poses: [(String, PoseQuad)] {
        [("rest", PoseQuad(restingIn: box)),
         ("translate", pose(CGAffineTransform(translationX: 31, y: -12))),
         ("uniform scale", pose(CGAffineTransform(scaleX: 2.5, y: 2.5))),
         ("non-uniform scale", pose(CGAffineTransform(scaleX: 0.4, y: 3))),
         ("rotate", pose(rotation(37))),
         ("rotate past a right angle", pose(rotation(154))),
         ("mirror", pose(CGAffineTransform(scaleX: -1, y: 1))),
         ("shear", pose(CGAffineTransform(a: 1, b: 0, c: 0.6, d: 1, tx: 0, ty: 0))),
         ("everything at once", pose(rotation(23)
             .concatenating(CGAffineTransform(a: 1, b: 0, c: -0.35, d: 1, tx: 0, ty: 0))
             .concatenating(CGAffineTransform(scaleX: 1.7, y: 0.6))
             .concatenating(CGAffineTransform(translationX: -18, y: 44))))]
    }

    private func assertQuad(_ actual: Quad, _ expected: Quad, accuracy: CGFloat = 1e-8,
                            _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in [(actual.p0, expected.p0), (actual.p1, expected.p1),
                       (actual.p2, expected.p2), (actual.p3, expected.p3)] {
            XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
            XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        }
    }

    // MARK: - The numbers are the right numbers

    /// **A resting pose decomposes to the neutral six, and the expectation is not the function under
    /// test.** `Values.resting(in:)` is written out separately for exactly this reason: comparing
    /// `decompose(rest)` against `decompose(rest)` would be an equality anyone could pass.
    func testARestingPoseDecomposesToTheNeutralSix() throws {
        let values = try XCTUnwrap(PoseComponents.decompose(PoseQuad(restingIn: box)))
        XCTAssertEqual(values, PoseComponents.Values.resting(in: box),
                       "Position at the box's own centre, scales 1, no rotation and no skew")
    }

    /// **Each component names the quantity it claims to name**, checked against a number derived by
    /// hand from the transform rather than from the decomposition.
    ///
    /// This is the assertion that would go red if two components were transposed, if degrees and
    /// radians were confused, or if position were reported as an offset rather than as a place — none
    /// of which a round-trip test can see, because every one of them round-trips perfectly.
    func testEachComponentNamesTheQuantityItClaimsTo() throws {
        let slid = try XCTUnwrap(PoseComponents.decompose(pose(CGAffineTransform(translationX: 31, y: -12))))
        XCTAssertEqual(slid.x, Double(box.midX) + 31, accuracy: 1e-9, "X is where the centre went")
        XCTAssertEqual(slid.y, Double(box.midY) - 12, accuracy: 1e-9)
        XCTAssertEqual(slid.scaleX, 1, accuracy: 1e-9, "…and a slide scales nothing")
        XCTAssertEqual(slid.rotation, 0, accuracy: 1e-9)

        let scaled = try XCTUnwrap(PoseComponents.decompose(pose(CGAffineTransform(scaleX: 0.4, y: 3))))
        XCTAssertEqual(scaled.scaleX, 0.4, accuracy: 1e-9)
        XCTAssertEqual(scaled.scaleY, 3, accuracy: 1e-9)
        XCTAssertEqual(scaled.skew, 0, accuracy: 1e-9, "a non-uniform scale is not a skew")

        let turned = try XCTUnwrap(PoseComponents.decompose(pose(rotation(37))))
        XCTAssertEqual(turned.rotation, 37, accuracy: 1e-7, "degrees, not radians")
        XCTAssertEqual(turned.scaleX, 1, accuracy: 1e-9, "…and a turn stretches nothing")
        XCTAssertEqual(turned.scaleY, 1, accuracy: 1e-9)
        XCTAssertEqual(turned.x, Double(box.midX), accuracy: 1e-7,
                       "a turn about the box's own centre leaves the centre where it is")

        let mirrored = try XCTUnwrap(PoseComponents.decompose(pose(CGAffineTransform(scaleX: -1, y: 1))))
        XCTAssertGreaterThan(mirrored.scaleX, 0,
                             "`scaleX` is a length, so a mirror is never spelled here")
        XCTAssertEqual(abs(mirrored.scaleY), 1, accuracy: 1e-9)
        XCTAssertLessThan(mirrored.scaleY, 0, "…the reflection is carried by the signed `scaleY`")
    }

    /// **The refutation this feature was built on: `Matrix2x2.polar` is the wrong factorisation for
    /// naming a pose, and the failure is visible to an artist.**
    ///
    /// KEYFRAMES §4.3 blends poses through `polar`, so reusing it for the band is the obvious move
    /// and was the brief's own hypothesis. `polar` factors as rotation × **symmetric** remainder,
    /// which is right for interpolation and wrong for naming: it reports a **rotation for a pose that
    /// was never rotated**. This test states the disagreement with numbers, so that a later session
    /// reaching for the shared primitive finds the reason it was not used rather than an opinion.
    func testPolarReportsARotationForAPureSkewAndTheQRDecompositionDoesNot() throws {
        let sheared = pose(CGAffineTransform(a: 1, b: 0, c: 0.6, d: 1, tx: 0, ty: 0))
        // `Matrix2x2` is row-major and CoreGraphics is column-major, so `c` crosses to `b`.
        let polar = Matrix2x2(a: 1, b: 0.6, c: 0, d: 1).polar
        XCTAssertEqual(polar.angle * 180 / .pi, -16.699, accuracy: 0.01,
                       "Fixture: polar puts nearly 17 degrees of turn into a pose with no turn in it")

        let values = try XCTUnwrap(PoseComponents.decompose(sheared))
        XCTAssertEqual(values.rotation, 0, accuracy: 1e-9,
                       "The band reports no rotation, which is what the artist did")
        XCTAssertEqual(values.scaleX, 1, accuracy: 1e-9)
        XCTAssertEqual(values.scaleY, 1, accuracy: 1e-9)
        XCTAssertEqual(tan(values.skew * .pi / 180), 0.6, accuracy: 1e-9,
                       "…and puts the whole of it in Skew, where the artist put it")
    }

    // MARK: - The round trip

    /// **Decompose then recompose returns the pose it was given**, for every kind of affine pose the
    /// app can author and two it cannot.
    ///
    /// The tolerance is stated rather than left to `==`: both directions go through `atan2`, `hypot`
    /// and `tan`, so this is a floating-point guarantee and not a bitwise one. **1e-8 of a canvas
    /// point** on a box 40 points across — five orders of magnitude below anything that could move a
    /// pixel — which is also why `PoseInterpolation.blend` short-circuits its endpoints rather than
    /// round-tripping a key through its own factorisation.
    func testEveryPoseRoundTripsThroughItsSixNumbers() throws {
        for (name, original) in poses {
            let values = try XCTUnwrap(PoseComponents.decompose(original), name)
            let rebuilt = try XCTUnwrap(PoseComponents.recompose(values, box: original.box), name)
            XCTAssertEqual(rebuilt.box, original.box, "\(name): the box is carried, not re-derived")
            assertQuad(rebuilt.corners, original.corners, "\(name) did not round-trip")
        }
    }

    /// **Editing one component moves that component and leaves the other five exactly where they
    /// were** — the property the write-back would stand on, and the one an implementation gets wrong
    /// by recomposing from a *fresh* decomposition of the edited pose.
    ///
    /// Written as a loop over all six against a pose that has a non-neutral value in every one of
    /// them, which is the fixture half that matters: on a resting pose, "the others did not move"
    /// is true of an implementation that resets them all to neutral.
    func testEditingOneComponentLeavesTheOtherFiveAlone() throws {
        let start = pose(rotation(23)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: -0.35, d: 1, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(scaleX: 1.7, y: 0.6))
            .concatenating(CGAffineTransform(translationX: -18, y: 44)))
        let before = try XCTUnwrap(PoseComponents.decompose(start))
        for component in PoseComponents.Component.allCases {
            let target: Double
            switch component {
            case .x, .y: target = before[component] + 25
            case .scaleX, .scaleY: target = before[component] * 1.6
            case .rotation: target = before[component] + 18
            case .skew: target = before[component] - 11
            }
            XCTAssertNotEqual(target, before[component], accuracy: 1e-6,
                              "Fixture: \(component) is actually being changed")

            let edited = try XCTUnwrap(PoseComponents.setting(component, to: target, of: start),
                                       "\(component)")
            let after = try XCTUnwrap(PoseComponents.decompose(edited), "\(component)")
            XCTAssertEqual(after[component], target, accuracy: 1e-7,
                           "\(component) did not take the value it was set to")
            for other in PoseComponents.Component.allCases where other != component {
                XCTAssertEqual(after[other], before[other], accuracy: 1e-7,
                               "setting \(component) moved \(other)")
            }
        }
    }

    /// **Setting a component to the value it already holds returns the pose unchanged** — the
    /// zero-travel property `testTakingAHandleAtZeroTravelChangesNothingAboutTheCurve` pins one file
    /// over, and the one that would catch a recomposition that quietly normalises.
    func testSettingAComponentToItsOwnValueChangesNothing() throws {
        for (name, original) in poses {
            let values = try XCTUnwrap(PoseComponents.decompose(original), name)
            for component in PoseComponents.Component.allCases {
                let same = try XCTUnwrap(
                    PoseComponents.setting(component, to: values[component], of: original), name)
                assertQuad(same.corners, original.corners,
                           "\(name): re-setting \(component) to its own value moved the pose")
            }
        }
    }

    // MARK: - What is refused

    /// **A projective pose is declined rather than linearised** — §11.7's ruling, and the whole
    /// reason `decompose` asks `Homography.affine()` instead of `PoseQuad.affineOrLinearised`.
    ///
    /// The second half is the one that makes this a test rather than a tautology: the same pose
    /// **does** answer `affineOrLinearised`, so the refusal is a deliberate narrowing and not the
    /// absence of an answer. Swap `affine()` for `affineOrLinearised` in `decompose` and this goes
    /// red while every other test in the file stays green.
    func testAProjectivePoseIsDeclinedRatherThanLinearised() {
        let keystone = PoseQuad(box: box,
                                corners: Quad(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
                                              CGPoint(x: 80, y: 100), CGPoint(x: 20, y: 100)))
        XCTAssertNotNil(keystone.affineOrLinearised,
                        "Fixture: rendering has an answer for this pose, so the refusal is a choice")
        XCTAssertNil(PoseComponents.decompose(keystone),
                     "…and the six curves do not, because a homography has eight freedoms")
    }

    /// A pose that has collapsed its drawing to a line has no rotation to report and no inverse to
    /// write back through, so it is declined too — for the same reason `TransformTrack.mapping`
    /// drops a degenerate quad rather than rendering it.
    func testACollapsedPoseIsDeclined() {
        XCTAssertNil(PoseComponents.decompose(pose(CGAffineTransform(scaleX: 1, y: 0))))
    }

    /// `recompose` refuses the values `Component.skew`'s domain exists to keep it away from, so a
    /// caller that did not clamp gets nil rather than an infinity in a corner coordinate.
    func testRecomposeRefusesASkewAtTheRightAngle() {
        var values = PoseComponents.Values.resting(in: box)
        values.skew = 90
        XCTAssertNil(PoseComponents.recompose(values, box: box))
        XCTAssertTrue(PoseComponents.Component.skew.modelDomain.upperBound < 90,
                      "…and the domain a drag would clamp to never reaches it")
    }

    // MARK: - The ids

    /// **Every pose group's prefix is free of dots**, which is the premise
    /// `TimelineGraphChannelList.groupID(ofParameterID:)` needs and the one
    /// `TransformChannelID.id` does not supply.
    ///
    /// That doc says its own id doubles as the grouping key. It does for `.cel` and does not for
    /// `.group`, whose id is `"group.<uuid>"` — already containing a dot — so a component appended
    /// to it would group every animation group on a cel under `"group"` and one tap on that header
    /// would switch off channels belonging to drawings the artist never picked. This is the check
    /// that the repair holds.
    func testEveryPoseGroupPrefixIsDotFree() {
        let ids: [PoseChannelID] = [.cel(.cel), .cel(.group(UUID())), .container]
        for id in ids {
            XCTAssertFalse(id.groupID.contains("."), "\(id.groupID) would split in the wrong place")
            for component in PoseComponents.Component.allCases {
                let parameterID = id.parameterID(component)
                XCTAssertEqual(TimelineGraphChannelList.groupID(ofParameterID: parameterID),
                               id.groupID)
                let resolved = PoseChannelID.resolve(parameterID: parameterID)
                XCTAssertEqual(resolved?.channel, id)
                XCTAssertEqual(resolved?.component, component)
            }
        }
        XCTAssertTrue(TransformChannelID.group(UUID()).id.contains("."),
                      "Fixture: the id this replaces really does carry a dot")
    }

    /// **Two animation groups are two list groups**, which is the failure the spelling above exists
    /// to prevent stated as a behaviour rather than as a property of a string.
    func testTwoAnimationGroupsAreTwoListGroups() {
        let a = PoseChannelID.cel(.group(UUID()))
        let b = PoseChannelID.cel(.group(UUID()))
        XCTAssertNotEqual(TimelineGraphChannelList.groupID(ofParameterID: a.parameterID(.x)),
                          TimelineGraphChannelList.groupID(ofParameterID: b.parameterID(.x)))
    }

    /// A grade's parameter id is not a pose channel's, so the one predicate every read-only gate and
    /// every navigation target asks cannot mistake one for the other.
    func testAGradesParameterIDIsNotAPoseChannel() {
        XCTAssertFalse(PoseChannelID.isPose(parameterID: "brightnessContrast.brightness"))
        XCTAssertFalse(PoseChannelID.isPose(parameterID: "blur.radius"))
        XCTAssertTrue(PoseChannelID.isPose(parameterID: PoseChannelID.cel(.cel).parameterID(.x)))
    }

    /// **A container pose raises no Move box, and says so rather than offering a dead tap** — the
    /// gap is in the app (there is no Move on a transformation layer yet), and this is where it is
    /// recorded so that the day it closes there is one line to change.
    func testAContainerPoseOffersNoMoveBoxAndACelChannelDoes() {
        XCTAssertFalse(PoseChannelID.container.raisesMoveBox)
        XCTAssertTrue(PoseChannelID.cel(.cel).raisesMoveBox)
        XCTAssertTrue(PoseChannelID.cel(.group(UUID())).raisesMoveBox)
    }
}
