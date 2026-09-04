import XCTest
import UIKit
import CoreGraphics

/// **KEYFRAMES.md stage 4 — the rest-space dab bake.**
///
/// The stage's whole content is one sentence: a posed stroke's dab walk happens where the artist
/// drew it, and the pose touches nothing but each finished dab's centre and radius. Everything
/// asserted here follows from that, and each test names which artifact it is the death of.
///
/// **What these tests compare, said out loud, because an obvious comparison measures nothing.**
///
/// The artifact is not "the walk looks different at two positions" in the abstract — the artifact is
/// that a walk re-derived at *posed* geometry can shift its own dab **count** or **phase** from frame
/// to frame, purely from floors in `stampSpacing`/`stampApproximateSquare` that do not scale linearly
/// with size. The only place that is expressible is the dab record.
///
/// And the dab record has to be the **renderer's**. `BrushStamper.DabPose.applied(to:)` copies
/// `alpha` verbatim and multiplies `radius` by a scale, so "the dab counts are equal" and "the radius
/// is `radius × scale`" are algebraic consequences of that one function and hold under an
/// implementation that walks in posed space and reintroduces the re-phase this stage exists to
/// remove. A test-local reimplementation of `VectorCanvas.stamp`'s dispatch has the same hole one
/// door over: it pins the copy. So every claim about *which walk runs* is asserted on `DabProbe`, the
/// seam on `CGContextDabTarget` that records what `VectorCanvas.renderLocalContent` stamped, or on
/// the rendered pixels themselves.
///
/// The tests that remain on `DabPose` and `BrushStamper` directly are the ones whose subject really
/// is that arithmetic — the area root under an affine, the per-dab scale under a homography, the
/// vanishing line, and the two targets agreeing.
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

    private let seed = DabRandom.seed(for: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)

    private func bake(_ samples: [BrushStamper.Sample], _ brush: Brush,
                      size: CGFloat = 24) -> [BrushStamper.BakedDab] {
        BrushStamper.bake(samples: samples, brush: brush, color: .black,
                          brushSize: size, brushOpacity: 1, random: DabRandom(seed: seed))
    }

    // MARK: - The shipped render path

    /// The canvas every render-path test draws into. Big enough that a 24-frame slide stays on it, so
    /// the byte pin below has pixels to compare; the probe itself sees every dab regardless, because
    /// `CGContextDabTarget.stampCircle` is called before CoreGraphics does any clipping.
    private let canvas = CGSize(width: 400, height: 400)

    /// The same run as `run()`, as a `VectorStroke` a `VectorCanvas` will draw.
    private func stroke(_ brush: Brush, size: CGFloat = 24,
                        count: Int = 12, dx: CGFloat = 10, y: CGFloat = 60) -> VectorStroke {
        VectorStroke(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, brush: brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: size, opacity: 1,
                     samples: (0..<count).map {
                         VectorSample(x: 20 + CGFloat($0) * dx, y: y, pressure: 1)
                     })
    }

    /// **The dabs the shipped render path actually stamped**, end to end: `VectorCanvas.render` →
    /// `renderLocalContent` → `draw(stroke:)` → `stamp` → `CGContextDabTarget`. `DabProbe` sits on the
    /// last of those, so nothing here re-derives `stamp`'s dispatch and a change to which walk it runs
    /// lands in this array.
    private func stamped(_ elements: [VectorElement]) -> [DabProbe.Dab] {
        DabProbe.begin()
        _ = VectorCanvas(size: canvas, elements: elements).render(quality: .full)
        return DabProbe.end()
    }

    /// One stroke posed by `t`, rendered, and the dabs read off the probe. `VectorCanvas.posing` is
    /// the model-layer seam a keyed transform channel goes through, so this is the whole path a posed
    /// frame takes.
    private func stampedPosed(_ stroke: VectorStroke, through t: CGAffineTransform) -> [DabProbe.Dab] {
        stamped([VectorCanvas.posing(.stroke(stroke), through: t)])
    }

    /// A crop's pixels, redrawn into a known 8-bit premultiplied buffer so two `UIImage`s from two
    /// renders are compared as bytes rather than as whatever backing each happened to get.
    private func rgbaBytes(of image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }

    override func tearDown() {
        // A probe left armed by a test that threw would collect another suite's dabs — the same
        // restore rule `Compositor.backend` gets, and `DabProbe` is process-wide in exactly that way.
        DabProbe.end()
        super.tearDown()
    }

    // MARK: - The walk itself

    /// **A Uniform shrink re-phases a posed-space walk, and that surprised §8 too.**
    ///
    /// `stampSpacing`'s 1 pt floor binds below `brushSize * spacingFraction == 1`, so a stroke walked
    /// at its *posed* size lands a different lattice on almost every frame of an animated scale even
    /// though the map is a similarity. The rest walk computes spacing from the rest size once, so the
    /// count is a constant and the pose scales the lattice as one piece.
    ///
    /// That is why §8 says *"pose through the similarity path and nothing re-phases"* is not available
    /// as a fallback. Asserted on the renderer's own dabs: the count is one number across 24 frames,
    /// and at the deepest frame every radius is the rest radius times that frame's scale, exactly.
    func testARenderedUniformShrinkWalksOneLatticeOnEveryFrame() throws {
        let ink = stroke(BrushLibrary.hardRound)
        let rest = stamped([.stroke(ink)])
        XCTAssertGreaterThan(rest.count, 80, "Setup: a walk long enough for a re-phase to show")

        var counts = Set<Int>()
        for frame in 0..<24 {
            let k = 1.0 - 0.7 * CGFloat(frame) / 23.0
            counts.insert(stampedPosed(ink, through: CGAffineTransform(scaleX: k, y: k)).count)
        }
        XCTAssertEqual(counts, [rest.count], "one walk, 24 frames")

        let k: CGFloat = 0.3
        let shrunk = stampedPosed(ink, through: CGAffineTransform(scaleX: k, y: k))
        for (index, dab) in rest.enumerated() {
            XCTAssertEqual(shrunk[index].radius, dab.radius * k, accuracy: 1e-12)
            XCTAssertEqual(shrunk[index].center.x, dab.center.x * k, accuracy: 1e-9)
        }
    }

    /// **The square brush is baked at rest and posed per frame, like everything else** — §4.2's
    /// second named artifact.
    ///
    /// **§4.2's framing of that artifact is now wrong twice over, and the second correction is this
    /// stage's.** It named Square's *sub-lattice* — sixteen gradient discs faking one square — as the
    /// non-round-dab case that can shimmer. The first correction was measurement: the sub-lattice did
    /// not shimmer under an ordinary shrink, because a uniform map scales its step and its sub-dab
    /// radius by the same number and a similar copy of itself has no gaps. The second is that
    /// **BRUSH.md §12 stage 3 deleted the sub-lattice**: a square dab is now one `stampImage` of a
    /// committed alpha mask, so there is no sub-grid left to shimmer and the count is one dab per
    /// stamp rather than sixteen.
    ///
    /// What survives is the claim that mattered — the walk happens **once, at rest**, and a frame is
    /// that walk posed — plus a new operand the sub-lattice never had: an image dab carries an
    /// **angle**, and a pose has to turn it. A pure scale turns nothing, which is what the angles
    /// below pin; `BrushTipLogicTests` pins the rotating case at the level of `DabPose` itself.
    func testTheRenderedSquareBrushIsWalkedOnceAtRestAndPosedPerFrame() throws {
        let brush = BrushLibrary.square
        XCTAssertEqual(brush.shape, .square, "Setup: the one built-in that is not a round dab")
        let ink = stroke(brush)
        let rest = stamped([.stroke(ink)])
        XCTAssertGreaterThan(rest.count, 5, "Setup: the stroke put down dabs at all")

        var counts = Set<Int>()
        for frame in 0..<24 {
            let k = 1.0 - 0.95 * CGFloat(frame) / 23.0
            counts.insert(stampedPosed(ink, through: CGAffineTransform(scaleX: k, y: k)).count)
        }
        XCTAssertEqual(counts, [rest.count], "one walk, scaled 24 ways")

        let k: CGFloat = 0.3
        let shrunk = stampedPosed(ink, through: CGAffineTransform(scaleX: k, y: k))
        XCTAssertEqual(shrunk.count, rest.count, "the walk is run once, at rest")
        for (index, dab) in rest.enumerated() {
            XCTAssertEqual(shrunk[index].radius, dab.radius * k, accuracy: 1e-12)
            XCTAssertEqual(shrunk[index].angle, dab.angle, accuracy: 1e-12,
                           "a uniform scale has no rotation in it, so the stamps do not turn")
        }

        // Spacing-to-size is the same number at rest and at 0.3x: the chain is one scaled copy, so
        // a shrink opens no gaps between consecutive stamps.
        let restGap = hypot(rest[1].center.x - rest[0].center.x, rest[1].center.y - rest[0].center.y)
        let movedGap = hypot(shrunk[1].center.x - shrunk[0].center.x,
                             shrunk[1].center.y - shrunk[0].center.y)
        XCTAssertGreaterThan(restGap, 0, "Setup: consecutive stamps are distinct points")
        XCTAssertEqual(movedGap / shrunk[0].radius, restGap / rest[0].radius, accuracy: 1e-9,
                       "the chain scales as one piece")
    }

    /// **A pure translation moves a posed-space walk's dab count too** — 110 dabs on some frames and
    /// 111 on others, because `Int(distance / spacing)` sits on a knife edge and a translated
    /// coordinate is not bit-identical arithmetic. Nothing about the ink changes; the lattice does.
    ///
    /// It is the smallest possible demonstration that a re-derived walk is not a stable object, and it
    /// is asserted here on the renderer rather than on a construction that ships nowhere: 24 slid
    /// frames, one dab count.
    func testARenderedPureTranslationDoesNotMoveTheDabCount() {
        let ink = stroke(BrushLibrary.pencil)
        var counts = Set<Int>()
        for frame in 0..<24 {
            let t = CGAffineTransform(translationX: CGFloat(frame) * 3.7, y: CGFloat(frame) * 1.3)
            counts.insert(stampedPosed(ink, through: t).count)
        }
        XCTAssertEqual(counts.count, 1, "the mildest map there is moves the ink and not the lattice")
        XCTAssertEqual(counts, [stamped([.stroke(ink)]).count])
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
            // The radius, not the ratio: `r * k` is exact and `r * k / r` is not — a 0.5/0.5/1.5
            // rotation-and-scale map came back one ULP off through the division alone.
            for dab in rest {
                XCTAssertEqual(try XCTUnwrap(pose.applied(to: dab)).radius, dab.radius * k, accuracy: 0)
            }
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
                                        alpha: 1, blendMode: .normal, tip: .round(hardness: 1))
        XCTAssertNil(pose.applied(to: dab))
        XCTAssertNotNil(pose.applied(to: BrushStamper.BakedDab(center: .zero, radius: 3, color: .black,
                                                               alpha: 1, blendMode: .normal,
                                                               tip: .round(hardness: 1))))
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
                                 brushOpacity: 1, random: DabRandom(seed: seed))

        let replayed = BrushStamper.CollectingDabTarget()
        BrushStamper.replay(bake(run(), brush), into: replayed, through: pose)

        XCTAssertEqual(streamed.dabs.count, replayed.dabs.count)
        XCTAssertEqual(streamed.dabs, replayed.dabs)
    }

    /// **Nothing changes for a stroke nobody has posed.** `VectorCanvas.stamp` has two arms and the
    /// unposed one has to be the shipped one to the last dab — every document that has never been
    /// keyframed takes it, on every render.
    ///
    /// The two operands are the renderer's own dabs and a plain `BrushStamper` walk of the stroke's
    /// stored geometry with the stroke's own seed. Nothing about a pose appears on either side, which
    /// is the claim: the arm a `restWalk` selects is unreachable here, and what is left is the call
    /// that shipped before this stage.
    func testAnUnposedStrokeStampsExactlyWhatItAlwaysDid() {
        let ink = stroke(BrushLibrary.pencil)
        let rendered = stamped([.stroke(ink)])
        let direct = BrushStamper.bake(
            samples: ink.samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) },
            brush: ink.brush, color: ink.uiColor, brushSize: ink.size, brushOpacity: ink.opacity,
            random: ink.dabRandom)

        XCTAssertGreaterThan(rendered.count, 100, "Setup: there are dabs to compare")
        XCTAssertEqual(rendered.count, direct.count)
        XCTAssertEqual(rendered, direct.map {
            DabProbe.Dab(center: $0.center, radius: $0.radius, alpha: $0.alpha)
        }, "the unposed arm is the walk it always was")
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
        let encoder = JSONEncoder()
        // Two encodes of one value do not agree on key order otherwise, and this test is about the
        // key *set*.
        encoder.outputFormatting = .sortedKeys
        let bare = try encoder.encode(stroke)
        stroke.restWalk = StrokeRestWalk(samples: stroke.samples, lattice: nil, size: 12,
                                         pose: BrushStamper.DabPose(CGAffineTransform(translationX: 9, y: 9)))
        let posed = try encoder.encode(stroke)
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
    /// to re-phase. Pinned so a later reader does not add one.
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

