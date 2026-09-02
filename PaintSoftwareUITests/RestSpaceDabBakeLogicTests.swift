import XCTest
import UIKit
import CoreGraphics

/// **KEYFRAMES.md stage 4 — the rest-space dab bake, and §2.16's grain.**
///
/// The stage's whole content is one sentence: a posed stroke's dab walk happens where the artist
/// drew it, and the pose touches nothing but each finished dab's centre and radius. Everything
/// asserted here follows from that, and each test names which artifact it is the death of.
///
/// **What these tests compare, said out loud, because the obvious comparison measures nothing.**
/// The artifact is not "the noise field differs at two positions" — it always does, that is what a
/// noise field is. The artifact is that *the ink's own alphas change from frame to frame*, and the
/// only place that is expressible is the dab record. So every grain assertion here reads
/// `BakedDab.alpha`, which is what `stampCircle` actually receives and therefore what the pixels
/// actually are, and never the field. `TransformChannelLogicTests` carried the field version until
/// this stage and its rewrite says the same thing.
///
/// **The `swiftc` loop, not `xcodebuild`.** Every number in these comments was taken from a
/// standalone build of `BrushStamper` + `Brush` + `Deform` at ~4 s a cycle, as CLAUDE.md's engine
/// note asks, and then re-asserted here.
final class RestSpaceDabBakeLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A twelve-sample horizontal run, 110 pt long — long enough that the dab count is in the
    /// hundreds and a re-phase cannot hide in rounding.
    private func run(_ count: Int = 12, dx: CGFloat = 10, y: CGFloat = 40) -> [BrushStamper.Sample] {
        (0..<count).map { BrushStamper.Sample(point: CGPoint(x: CGFloat($0) * dx, y: y), pressure: 1) }
    }

    /// A diagonal run, for the projective case: a horizontal line lies along a contour of constant
    /// magnification in a symmetric keystone, so a horizontal stroke would measure a *ratio of 1.000*
    /// and read as proof that per-dab width buys nothing. It was the first thing this file measured
    /// and it was wrong for exactly that reason.
    private func diagonal(_ count: Int = 12) -> [BrushStamper.Sample] {
        (0..<count).map {
            BrushStamper.Sample(point: CGPoint(x: CGFloat($0) * 10, y: CGFloat($0) * 6.5), pressure: 1)
        }
    }

    private let seed = BrushStamper.seed(for: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)

    private func bake(_ samples: [BrushStamper.Sample], _ brush: Brush,
                      size: CGFloat = 24) -> [BrushStamper.BakedDab] {
        BrushStamper.bake(samples: samples, brush: brush, color: .black,
                          brushSize: size, brushOpacity: 1, seed: seed)
    }

    /// **The construction that shipped before this stage**: pose the samples, scale the size by the
    /// map's area root, then walk. Written out here rather than referenced so the two are visibly the
    /// same call with the transform applied at different ends of it.
    private func walkedAfterPosing(_ samples: [BrushStamper.Sample], _ brush: Brush,
                                   size: CGFloat, through t: CGAffineTransform) -> [BrushStamper.BakedDab] {
        let moved = samples.map {
            BrushStamper.Sample(point: $0.point.applying(t), pressure: $0.pressure)
        }
        return BrushStamper.bake(moved, sizedFor: t, brush: brush, size: size, seed: seed)
    }

    private func alphas(_ dabs: [BrushStamper.BakedDab]) -> [String] {
        dabs.map { String(format: "%.9f", $0.alpha) }
    }

    // MARK: - §2.16 — grain travels with the ink

    /// **The stage's headline, and the one the artist can see.**
    ///
    /// `grainAlphaMultiplier` reads an absolute canvas-position noise field. Under the shipped path a
    /// posed stroke's samples were moved *before* the walk, so every dab landed on different tooth on
    /// every frame: MEASURED on a pure translation animated over 24 frames, **24 distinct alpha
    /// sequences** — the texture crawling across the ink at 24 fps, which is §4.2's *"grain is the
    /// real one"*. Baking in rest space gives **one**.
    ///
    /// Both halves are asserted. A test that only pinned the new invariance would pass just as well
    /// against a build with grain deleted, so the old path is walked here too and required to be
    /// unstable — the operand check CLAUDE.md asks for, in the one place where the *absence* of an
    /// effect is what is being claimed.
    func testGrainTravelsWithTheInkAcrossEveryFrameOfAPose() {
        let brush = BrushLibrary.pencil
        XCTAssertTrue(brush.grain.isEnabled, "Setup: the pencil is the one built-in that grains")

        let rest = bake(run(), brush)
        XCTAssertGreaterThan(rest.count, 100, "Setup: a walk long enough for a re-phase to show")

        var baked = Set<[String]>(), shipped = Set<[String]>()
        for frame in 0..<24 {
            let t = CGAffineTransform(translationX: CGFloat(frame) * 3.7, y: CGFloat(frame) * 1.3)
            let pose = BrushStamper.DabPose(t)
            baked.insert(alphas(rest.compactMap { pose.applied(to: $0) }))
            shipped.insert(alphas(walkedAfterPosing(run(), brush, size: 24, through: t)))
        }
        XCTAssertEqual(baked.count, 1,
                       "The grain is baked at the rest stamp point, so 24 frames are one texture")
        XCTAssertEqual(shipped.count, 24,
                       "and the path this replaces re-sampled the field on every one of them")
    }

    /// Grain travels **with** the ink rather than merely being stable: the dabs move, and their
    /// alphas do not. Without the second half a pose that moved nothing would satisfy the first.
    func testAPosedGrainDabKeepsItsAlphaAndChangesItsPlace() throws {
        let rest = bake(run(), BrushLibrary.pencil)
        let pose = BrushStamper.DabPose(CGAffineTransform(translationX: 61, y: -23))
        let moved = rest.compactMap { pose.applied(to: $0) }

        XCTAssertEqual(moved.count, rest.count)
        XCTAssertEqual(alphas(moved), alphas(rest), "the texture is part of the mark")
        // Not all equal, and not equal anywhere: a translation moves every dab.
        XCTAssertTrue(zip(rest, moved).allSatisfy { $0.center != $1.center })
        XCTAssertEqual(try XCTUnwrap(moved.first).center.x - (try XCTUnwrap(rest.first).center.x), 61,
                       accuracy: 1e-9)
        // The grain has to be *doing* something, or the first assertion is vacuous.
        XCTAssertGreaterThan(Set(alphas(rest)).count, 10,
                             "Setup: the pencil's grain varies dab to dab")
    }

    // MARK: - The walk itself

    /// **A Uniform shrink re-phases the walk, and that surprised §8 too.**
    ///
    /// `stampSpacing`'s 1 pt floor binds below `brushSize * spacingFraction == 1`, so a stroke
    /// animated from scale 1.0 to 0.3 walks a *different lattice* on almost every frame even though
    /// the map is a similarity. MEASURED over 24 frames of a 24 pt Hard Round: the shipped path
    /// produces **24 distinct dab counts, 34 through 111**; the rest-space bake produces **one**.
    ///
    /// That is why §8 says *"pose through the similarity path and nothing re-phases"* is not
    /// available as a fallback, and it is the strongest single number in this file.
    func testAUniformShrinkNoLongerRePhasesTheWalk() {
        let brush = BrushLibrary.hardRound
        let rest = bake(run(), brush)

        var baked = Set<Int>(), shipped = Set<Int>()
        for frame in 0..<24 {
            let k = 1.0 - 0.7 * CGFloat(frame) / 23.0
            let t = CGAffineTransform(scaleX: k, y: k)
            let pose = BrushStamper.DabPose(t)
            baked.insert(rest.compactMap { pose.applied(to: $0) }.count)
            shipped.insert(walkedAfterPosing(run(), brush, size: 24, through: t).count)
        }
        XCTAssertEqual(baked, [rest.count], "one walk, 24 frames")
        XCTAssertEqual(shipped.count, 24, "and 24 walks before this stage")
        XCTAssertEqual(shipped.min(), 34)
        XCTAssertEqual(shipped.max(), rest.count)
    }

    /// **The square brush's sub-lattice is baked with everything else** — §4.2's second named
    /// artifact, and it comes free because `stampApproximateSquare` runs inside the rest-space walk
    /// and emits ordinary `stampCircle` calls that the pose maps like any other.
    ///
    /// MEASURED over the same 24-frame shrink: **19 distinct sub-dab counts** before, one after.
    ///
    /// **Coverage is preserved under a uniform scale and this is why**: the grid's step and its
    /// sub-dab radius are both rest-space numbers and both are multiplied by the same local scale, so
    /// the overlap ratio is invariant and no gaps open. Under a strongly *non*-uniform map they can,
    /// because a round dab at the local area root is not the ellipse the map really wants — the
    /// approximation §4.2 names in its own third bullet, and `TextLayout.warpSourceScale`'s.
    func testTheSquareBrushSubLatticeIsBakedToo() {
        let brush = BrushLibrary.square
        XCTAssertEqual(brush.shape, .square, "Setup: the one built-in that is not a round dab")
        let rest = bake(run(), brush)

        var baked = Set<Int>(), shipped = Set<Int>()
        for frame in 0..<24 {
            let k = 1.0 - 0.7 * CGFloat(frame) / 23.0
            let t = CGAffineTransform(scaleX: k, y: k)
            let pose = BrushStamper.DabPose(t)
            baked.insert(rest.compactMap { pose.applied(to: $0) }.count)
            shipped.insert(walkedAfterPosing(run(), brush, size: 24, through: t).count)
        }
        XCTAssertEqual(baked, [rest.count])
        XCTAssertEqual(shipped.count, 19)

        // Coverage: step-to-radius is the same number at rest and at 0.3x.
        let shrunk = BrushStamper.DabPose(CGAffineTransform(scaleX: 0.3, y: 0.3))
        let moved = rest.compactMap { shrunk.applied(to: $0) }
        let restGap = hypot(rest[1].center.x - rest[0].center.x, rest[1].center.y - rest[0].center.y)
        let movedGap = hypot(moved[1].center.x - moved[0].center.x, moved[1].center.y - moved[0].center.y)
        XCTAssertEqual(movedGap / moved[0].radius, restGap / rest[0].radius, accuracy: 1e-9,
                       "the sub-lattice scales as one piece, so a shrink opens no gaps")
    }

    /// A pure translation is the mildest map there is, and even it moved the dab count — 110 on some
    /// frames and 111 on others — because `Int(distance / spacing)` sits on a knife edge and a
    /// translated coordinate is not bit-identical arithmetic. Nothing about the ink changed; the
    /// lattice did. It is the smallest possible demonstration that a re-derived walk is not a stable
    /// object, and the reason this stage does not derive it twice.
    func testEvenAPureTranslationMovedTheDabCountBeforeThisStage() {
        var shipped = Set<Int>()
        for frame in 0..<24 {
            let t = CGAffineTransform(translationX: CGFloat(frame) * 3.7, y: CGFloat(frame) * 1.3)
            shipped.insert(walkedAfterPosing(run(), BrushLibrary.pencil, size: 24, through: t).count)
        }
        XCTAssertEqual(shipped, [110, 111])
    }

    // MARK: - Width

    /// **Under an affine the per-dab width is exactly `sqrt(|det|)`** — LASSO_MOVE.md §5.17's rule,
    /// which stage 5 writes into `VectorStroke.size` and which this stage must not move.
    ///
    /// It is exact rather than close because an affine's Jacobian determinant does not vary with
    /// position, so `DabPose` resolves the scale once and multiplies every radius by the same number.
    /// MEASURED across four maps at zero tolerance: min ratio == max ratio == `sqrt(|det|)` to twelve
    /// digits, and `constantScale` holds that number rather than nil.
    func testWidthUnderAnAffineIsExactlyTheAreaRoot() throws {
        let rest = bake(run(), BrushLibrary.hardRound)
        let maps: [CGAffineTransform] = [
            CGAffineTransform(scaleX: 2, y: 2),
            CGAffineTransform(scaleX: 4, y: 1),
            CGAffineTransform(rotationAngle: 0.7).scaledBy(x: 1.5, y: 0.5),
            CGAffineTransform(translationX: 9, y: -4)
        ]
        for t in maps {
            let pose = BrushStamper.DabPose(t)
            let k = sqrt(abs(t.a * t.d - t.b * t.c))
            XCTAssertEqual(try XCTUnwrap(pose.constantScale), k, accuracy: 0,
                           "an affine's area root is a constant, so it is resolved once")
            let ratios = rest.compactMap { pose.applied(to: $0) }
                .enumerated().map { $0.element.radius / rest[$0.offset].radius }
            XCTAssertEqual(ratios.min(), k, accuracy: 0)
            XCTAssertEqual(ratios.max(), k, accuracy: 0)
        }
    }

    /// **The width scale this stage applies is the number the shipped stretch mapping writes**, so an
    /// affine pose lands the same ink weight it landed before. Asserted against
    /// `VectorCanvas.mapping(_:throughStretch:)` itself rather than against a second copy of the
    /// formula — the two operands must be the shipped one and the new one, or this pins nothing.
    func testTheAffineWidthAgreesWithTheShippedStretchMapping() throws {
        let t = CGAffineTransform(rotationAngle: 0.4).scaledBy(x: 3, y: 0.75)
        let stroke = VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 24, opacity: 1,
                                  samples: [VectorSample(x: 0, y: 0, pressure: 1),
                                            VectorSample(x: 40, y: 0, pressure: 1)])
        let mapped = try XCTUnwrap(VectorCanvas.mapping(.stroke(stroke), throughStretch: t).stroke)
        XCTAssertEqual(try XCTUnwrap(BrushStamper.DabPose(t).constantScale),
                       mapped.size / stroke.size, accuracy: 1e-12)
    }

    /// **The case a scalar cannot answer, which is the whole of what this stage unblocks** —
    /// KEYFRAMES.md §8 and `SelectionModels`' Distort refusal.
    ///
    /// A homography's `|det J|` varies across the plane, so there is no single number to put in
    /// `VectorStroke.size`. MEASURED here on the same diagonal stroke: the local scale spans a
    /// **1.3x** ratio on a mild keystone, and the best single scalar — the linearisation at the
    /// stroke's own midpoint, which is the most favourable scalar available — is wrong at the ends by
    /// a margin this asserts. `DabPose` answers per dab, so it is right at every one.
    func testAProjectivePoseHasPerDabWidthWhereAScalarCannot() throws {
        let rest = bake(diagonal(), BrushLibrary.hardRound)
        let box = CGSize(width: 120, height: 80)
        let keystone = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0),
                            CGPoint(x: 96, y: 80), CGPoint(x: 24, y: 80))
        let map = try XCTUnwrap(Homography(boxSize: box, to: keystone))
        let pose = BrushStamper.DabPose(map)

        XCTAssertNil(map.affine(), "Setup: a keystone is projective, not affine")
        XCTAssertNil(pose.constantScale, "so there is no constant to resolve and every dab pays")

        let scales = rest.compactMap { pose.scale(at: $0.center) }
        XCTAssertEqual(scales.count, rest.count)
        let span = try XCTUnwrap(scales.max()) / (try XCTUnwrap(scales.min()))
        XCTAssertGreaterThan(span, 1.25, "the local scale genuinely varies along one stroke")

        // The most favourable scalar there is: the linearisation at the stroke's own midpoint.
        let mid = rest[rest.count / 2].center
        let best = try XCTUnwrap(map.localScale(at: mid))
        let worstError = scales.map { abs($0 - best) / $0 }.max() ?? 0
        XCTAssertGreaterThan(worstError, 0.1,
                             "and the best scalar is more than 10% wrong at the far end")

        // Per-dab, by construction, there is no error at all: the radius each dab lands with is the
        // rest radius times the map's own local scale *at that dab*.
        for (index, dab) in rest.enumerated() {
            let moved = try XCTUnwrap(pose.applied(to: dab))
            XCTAssertEqual(moved.radius, dab.radius * scales[index], accuracy: 0)
        }
    }

    /// A dab past the vanishing line has no image, and is dropped rather than drawn somewhere
    /// arbitrary. `Homography.map` already answers nil there; this pins that the pose does not
    /// paper over it with a clamp.
    func testADabWithNoImageIsDroppedRatherThanClamped() {
        // w = g·x + h·y + i, zero at x = 1/0.01 = 100.
        let vanishing = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: -0.01, h: 0, i: 1)
        let pose = BrushStamper.DabPose(vanishing)
        let dab = BrushStamper.BakedDab(center: CGPoint(x: 100, y: 0), radius: 3, color: .black,
                                        alpha: 1, hardness: 1, blendMode: .normal)
        XCTAssertNil(pose.applied(to: dab))
        XCTAssertNotNil(pose.applied(to: BrushStamper.BakedDab(center: .zero, radius: 3, color: .black,
                                                               alpha: 1, hardness: 1, blendMode: .normal)))
    }

    // MARK: - The two targets agree, and the unposed path is untouched

    /// `PosedDabTarget` and `bake` + `replay` are the streaming and stored forms of one arithmetic,
    /// and they share `DabPose.applied(to:)` so they cannot drift. Pinned anyway, because "they share
    /// a function" is a claim about today's source and this is a claim about the answer.
    func testStreamingAPoseAndReplayingABakeGiveTheSameDabs() {
        let brush = BrushLibrary.pencil
        let t = CGAffineTransform(rotationAngle: 0.3).scaledBy(x: 1.7, y: 0.6)
        let pose = BrushStamper.DabPose(t)

        let streamed = BrushStamper.CollectingDabTarget()
        BrushStamper.stampStroke(into: BrushStamper.PosedDabTarget(streamed, pose: pose),
                                 samples: run(), brush: brush, color: .black, brushSize: 24,
                                 brushOpacity: 1, seed: seed)

        let replayed = BrushStamper.CollectingDabTarget()
        BrushStamper.replay(bake(run(), brush), into: replayed, through: pose)

        XCTAssertEqual(streamed.dabs.count, replayed.dabs.count)
        XCTAssertEqual(streamed.dabs, replayed.dabs)
    }

    /// **Nothing changes for a stroke nobody has posed.** `VectorCanvas.stamp` now has two arms and
    /// the unposed one has to be the shipped one to the last dab — every document that has never been
    /// keyframed takes it, on every render.
    func testAnUnposedStrokeStampsExactlyWhatItAlwaysDid() {
        let identity = BrushStamper.DabPose(.identity)
        XCTAssertTrue(identity.isIdentity)
        let rest = bake(run(), BrushLibrary.pencil)
        let through = rest.compactMap { identity.applied(to: $0) }
        XCTAssertEqual(through, rest, "the identity pose is a no-op dab for dab")
    }

    // MARK: - The record does not reach the disk

    /// **A posed stroke is a render-time value and `restWalk` must never round-trip.** Encoding one
    /// has to produce the bytes the same stroke produced before this field existed — which is what
    /// makes "no migration" a fact about the encoder rather than a hope.
    ///
    /// The two operands are the *same* stroke with and without the field, not two similar ones, so a
    /// difference can only be the field.
    func testTheRestWalkIsNotPersistedAndOwesNoMigration() throws {
        var stroke = VectorStroke(id: UUID(), brush: BrushLibrary.pencil,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 12, opacity: 1,
                                  samples: [VectorSample(x: 1, y: 2, pressure: 1),
                                            VectorSample(x: 30, y: 44, pressure: 0.5)])
        let bare = try JSONEncoder().encode(stroke)
        stroke.restWalk = StrokeRestWalk(samples: stroke.samples, lattice: nil, size: 12,
                                         pose: BrushStamper.DabPose(CGAffineTransform(translationX: 9, y: 9)))
        let posed = try JSONEncoder().encode(stroke)
        XCTAssertEqual(bare, posed, "the field is absent from CodingKeys, so it is absent from the wire")

        let decoded = try JSONDecoder().decode(VectorStroke.self, from: posed)
        XCTAssertNil(decoded.restWalk, "and a decoded stroke is at rest, as every stored stroke is")
        XCTAssertEqual(decoded.samples.count, 2)
    }

    // MARK: - The seam

    /// **`VectorCanvas.posing` attaches the walk and `mapping(_:throughStretch:)` does not**, which is
    /// the distinction between a *view* of a stroke and a *commit* of one. A Move that bakes its map
    /// into the artist's geometry must leave no record claiming the stroke is a posed copy of
    /// somewhere else — the next render would draw its dabs back at the pre-move position.
    func testOnlyAPoseAttachesARestWalkAndACommitDoesNot() throws {
        let stroke = VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 8, opacity: 1,
                                  samples: [VectorSample(x: 0, y: 0, pressure: 1),
                                            VectorSample(x: 20, y: 0, pressure: 1)])
        let t = CGAffineTransform(translationX: 15, y: 3)

        let committed = try XCTUnwrap(VectorCanvas.mapping(.stroke(stroke), throughStretch: t).stroke)
        XCTAssertNil(committed.restWalk)

        let viewed = try XCTUnwrap(VectorCanvas.posing(.stroke(stroke), through: t).stroke)
        let walk = try XCTUnwrap(viewed.restWalk)
        XCTAssertEqual(walk.size, stroke.size, "the rest size, not the posed one")
        XCTAssertEqual(walk.samples.first?.point, .zero, "and the rest samples")
        XCTAssertEqual(viewed.samples.first?.point, CGPoint(x: 15, y: 3),
                       "while the display list itself is posed, as §4.2 says resolveSources hands it on")
    }

    /// A fill carries no dab walk because it has none — one `CGPath` through one map, with no lattice
    /// to re-phase and no grain field to re-sample. Pinned so a later reader does not add one.
    func testAFillIsPosedWithNoWalkBecauseItHasNone() throws {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        let fill = VectorFillElement(path: path, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                                     opacity: 1, evenOddFill: false)
        let posed = VectorCanvas.posing(.fill(fill), through: CGAffineTransform(translationX: 5, y: 0))
        XCTAssertNil(posed.stroke)
        XCTAssertEqual(try XCTUnwrap(posed.fill).cgPath?.boundingBox.minX, 5)
    }

    /// **The pixels, because the claim above is about pixels.** A posed cel's ink has to land where
    /// the pose puts it — the rest-space walk is an implementation of *where the dabs are computed*,
    /// not of where they are drawn, and wiring it to the wrong end would show up exactly here.
    func testPosedInkIsDrawnAtThePosedPositionAndNotAtRest() throws {
        let size = CGSize(width: 120, height: 120)
        let stroke = VectorStroke(id: UUID(), brush: BrushLibrary.pencil,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 8, opacity: 1,
                                  samples: (0..<6).map { VectorSample(x: 10 + CGFloat($0) * 4, y: 20,
                                                                      pressure: 1) })
        let restImage = VectorCanvas(size: size, elements: [.stroke(stroke)]).render(quality: .full)
        let posed = VectorCanvas.posing(.stroke(stroke), through: CGAffineTransform(translationX: 60, y: 0))
        let posedImage = VectorCanvas(size: size, elements: [posed]).render(quality: .full)

        let restBounds = try XCTUnwrap(PixelOps.opaqueContentBounds(restImage))
        let posedBounds = try XCTUnwrap(PixelOps.opaqueContentBounds(posedImage))
        XCTAssertEqual(posedBounds.midX - restBounds.midX, 60, accuracy: 2,
                       "the ink moved by the pose, not by nothing and not by twice")
        XCTAssertEqual(posedBounds.width, restBounds.width, accuracy: 2)
        XCTAssertEqual(posedBounds.midY, restBounds.midY, accuracy: 2)
    }
}

private extension BrushStamper {
    /// `bake` with the shipped stage-5 width rule folded in, so `walkedAfterPosing` reads as the one
    /// call it is.
    static func bake(_ samples: [Sample], sizedFor t: CGAffineTransform, brush: Brush,
                     size: CGFloat, seed: UInt64) -> [BakedDab] {
        let k = sqrt(abs(t.a * t.d - t.b * t.c))
        return bake(samples: samples, brush: brush, color: .black, brushSize: size * k,
                    brushOpacity: 1, seed: seed)
    }
}
