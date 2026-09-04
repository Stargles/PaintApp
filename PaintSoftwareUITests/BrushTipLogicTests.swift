import XCTest
import UIKit
import CoreGraphics

/// **BRUSH.md §12 stage 3 — the image dab primitive.**
///
/// `stampImage` replaced sixteen gradient-filled circles faking one square, so the assertions here
/// are deliberately about *pixels and angles* rather than about stored values: CLAUDE.md's newest
/// section exists because three features shipped with a green model-level suite behind them, and a
/// square brush that stamps the wrong pixels is exactly that shape. Every test below would still
/// pass against an implementation whose `BakedDab` fields were all correct and whose canvas was
/// blank, if it asserted on the model — so none of them does.
final class BrushTipLogicTests: XCTestCase {

    // MARK: - The asset exists, which every other test here silently assumes

    /// **The one test that stops the rest being vacuous.** `stampImage` draws nothing when its mask
    /// will not load, and a mask that is in the app bundle but not the *test* bundle would leave
    /// every pixel assertion below comparing transparent against transparent — the failure that
    /// reads as success. `BrushTextureStore.url(for:)` resolves through `Bundle(for:)` precisely so
    /// that both bundles answer, and this is where that is checked.
    func testTheBuiltInSquareTipLoadsAndIsAMaskWithABorderToAntialiasInto() throws {
        let mask = try XCTUnwrap(BrushTextureStore.mask(for: .builtIn(.square)),
                                 "The square tip's PNG must be readable from the bundle this code was compiled into")
        XCTAssertEqual(mask.width, 256)
        XCTAssertEqual(mask.height, 256)

        let pixels = try XCTUnwrap(Self.rgba(of: mask))
        XCTAssertEqual(Self.alpha(pixels, 128, 128), 255, "The tip's body is opaque")
        XCTAssertEqual(Self.alpha(pixels, 128, 4), 255, "…right up to two pixels from the edge")
        XCTAssertEqual(Self.alpha(pixels, 128, 0), 0,
                       "…and the outermost row is clear. That border is not padding: it is what a "
                       + "rotated or downscaled draw antialiases into, MEASURED as the difference "
                       + "between edge alphas of 142/237 and a flat aliased 255.")
        XCTAssertEqual(Self.alpha(pixels, 0, 0), 0)
    }

    /// The square brush is in the shipped picker, so an artist can reach it with no prior state —
    /// CLAUDE.md's cold-start reachability bar. Constructing a `Brush` in the fixture would prove
    /// only that the fixture works.
    func testTheSquareBrushInTheShippedLibraryDrawsSquareInkFromAColdStart() throws {
        let square = try XCTUnwrap(BrushLibrary.defaults.first { $0.shape == .square },
                                   "The brush picker must still offer a square brush")
        let texture = RasterLayerTexture(size: CGSize(width: 200, height: 200))
        BrushStamper.stampStroke(into: texture,
                                 samples: StrokeSamples((0..<10).map {
                                     VectorSample(point: CGPoint(x: 40 + CGFloat($0) * 12, y: 100),
                                                  pressure: 1)
                                 }, channels: .pressureOnly),
                                 brush: square, color: .black, brushSize: 40, brushOpacity: 1,
                                 random: DabRandom(seed: 99))
        let pixels = try XCTUnwrap(Self.rgba(of: texture))

        // A 40 pt square brush laid along y = 100 inks a band 40 tall and no taller. The corner is
        // the discriminating pixel: a round brush of the same size would leave it clear.
        XCTAssertGreaterThan(Self.alpha(pixels, 100, 100), 200, "the stroke is on the canvas at all")
        XCTAssertGreaterThan(Self.alpha(pixels, 100, 118), 200, "…and it is square to its top edge")
        XCTAssertEqual(Self.alpha(pixels, 100, 130), 0, "…and stops there")
    }

    // MARK: - A square dab is a square

    /// **The shape, at the level it is visible.** A round dab and an image dab of the same diameter
    /// agree at their centre and disagree at the corner, which is the whole difference between a
    /// disc and a square and the only place an implementation that quietly kept stamping circles
    /// could hide.
    func testASquareDabInksTheCornersARoundDabLeavesClear() throws {
        let d: CGFloat = 40
        let c = CGPoint(x: 64, y: 64)
        let square = RasterLayerTexture(size: CGSize(width: 128, height: 128))
        square.stampImage(.builtIn(.square), at: c, diameter: d, angle: 0,
                          color: .black, alpha: 1, blendMode: .normal)
        let round = RasterLayerTexture(size: CGSize(width: 128, height: 128))
        round.stampCircle(at: c, radius: d / 2, color: .black, alpha: 1, hardness: 1)

        let sq = try XCTUnwrap(Self.rgba(of: square)), rd = try XCTUnwrap(Self.rgba(of: round))
        XCTAssertGreaterThan(Self.alpha(sq, 64, 64), 250, "both are solid at the centre")
        XCTAssertGreaterThan(Self.alpha(rd, 64, 64), 250)
        // (18, 18) from the centre: inside a 40-square, 25.5 out from a 20-radius disc.
        XCTAssertGreaterThan(Self.alpha(sq, 82, 82), 250, "the square inks its corner")
        XCTAssertEqual(Self.alpha(rd, 82, 82), 0, "the disc does not — which is what makes this a shape test")
    }

    /// **The visible change this stage makes, named.** `stampApproximateSquare` scattered discs of
    /// radius `0.21·d` over a lattice reaching `±0.5·d`, so a "40 pt square brush" painted a lumpy
    /// blob **57 pt** across. The dab now fills its nominal size and stops: 25 px out from the centre
    /// of a 40 pt dab was ink before this change and is clear after it.
    func testASquareDabFillsItsNominalSizeInsteadOfOverflowingIt() throws {
        let texture = RasterLayerTexture(size: CGSize(width: 128, height: 128))
        texture.stampImage(.builtIn(.square), at: CGPoint(x: 64, y: 64), diameter: 40, angle: 0,
                           color: .black, alpha: 1, blendMode: .normal)
        let pixels = try XCTUnwrap(Self.rgba(of: texture))

        XCTAssertGreaterThan(Self.alpha(pixels, 82, 64), 250,
                             "18 px out of a 40 pt dab is inside it")
        XCTAssertEqual(Self.alpha(pixels, 89, 64), 0,
                       "25 px out is outside it. The old sixteen-circle approximation reached "
                       + "0.71·d = 28 px, so this pixel is the change — intended, and 1.42x smaller.")
    }

    /// **The angle reaches the pixels.** At 45° the square's corners point along the axes and its
    /// edges along the diagonals, so the two probe pixels swap roles exactly. An implementation that
    /// accepted `angle` and dropped it fails the first pair; one that turned the dab by a fixed
    /// amount fails the second.
    func testARotatedSquareDabTurnsItsCorners() throws {
        func stamped(_ angle: CGFloat) throws -> (bytes: [UInt8], width: Int, height: Int) {
            let texture = RasterLayerTexture(size: CGSize(width: 128, height: 128))
            texture.stampImage(.builtIn(.square), at: CGPoint(x: 64, y: 64), diameter: 40,
                               angle: angle, color: .black, alpha: 1, blendMode: .normal)
            return try XCTUnwrap(Self.rgba(of: texture))
        }
        let upright = try stamped(0), turned = try stamped(.pi / 4)

        XCTAssertEqual(Self.alpha(upright, 89, 64), 0, "upright: 25 px along the axis is past the edge")
        XCTAssertGreaterThan(Self.alpha(turned, 89, 64), 250,
                             "turned 45°: the corner now points that way, and reaches 28 px")

        XCTAssertGreaterThan(Self.alpha(upright, 82, 82), 250, "upright: the diagonal probe is a corner")
        XCTAssertEqual(Self.alpha(turned, 82, 82), 0,
                       "turned 45°: that diagonal is now the middle of an edge, 25 px out of 20")
    }

    // MARK: - The cache — RENDER.md §3.8's trap, and the two terms that are in the key

    /// **RENDER.md §3.8 records three memos in this repo keyed on a buffer's *size*, so two contents
    /// at one size collide and the second silently gets the first's pixels. This is the pin nobody
    /// wrote for those three.**
    ///
    /// Two tips, same dimensions, same colour, same dab size, stamped **through one cache** — which
    /// is the only arrangement in which a size-keyed implementation can be caught. Stamping them
    /// into two separate textures would give each its own cache and pass under the bug.
    func testTwoDifferentTipsAtTheSameSizeDoNotShareOneCacheEntry() throws {
        let wide = try Self.writeTestTip(inset: 2)   // fills its 64² mask
        let narrow = try Self.writeTestTip(inset: 22) // a small centred square in the same 64²

        let texture = RasterLayerTexture(size: CGSize(width: 256, height: 128))
        texture.stampImage(wide, at: CGPoint(x: 64, y: 64), diameter: 60, angle: 0,
                           color: .black, alpha: 1, blendMode: .normal)
        texture.stampImage(narrow, at: CGPoint(x: 192, y: 64), diameter: 60, angle: 0,
                           color: .black, alpha: 1, blendMode: .normal)
        let pixels = try XCTUnwrap(Self.rgba(of: texture))

        // 24 px out of a 60 pt dab: inside the wide tip's body, well outside the narrow one's.
        XCTAssertGreaterThan(Self.alpha(pixels, 64 + 24, 64), 250, "the wide tip covers 24 px out")
        XCTAssertEqual(Self.alpha(pixels, 192 + 24, 64), 0,
                       "the narrow tip does not — if it did, it got the wide tip's entry, which is "
                       + "exactly RENDER.md §3.8's silent wrong-pixels bug in a fourth cache")
        XCTAssertGreaterThan(Self.alpha(pixels, 192, 64), 250, "…and the narrow tip did stamp something")
        XCTAssertEqual(texture.dabImageCacheMisses, 2, "two tips are two entries, not one")
    }

    /// Colour is the cache's other key term, for `DabGradientCache`'s reason. A second colour that
    /// came back as the first's pixels is the same failure as a second tip doing so.
    func testASecondColourIsNotTheFirstColoursPixels() throws {
        let texture = RasterLayerTexture(size: CGSize(width: 128, height: 64))
        texture.stampImage(.builtIn(.square), at: CGPoint(x: 32, y: 32), diameter: 30, angle: 0,
                           color: .red, alpha: 1, blendMode: .normal)
        texture.stampImage(.builtIn(.square), at: CGPoint(x: 96, y: 32), diameter: 30, angle: 0,
                           color: .blue, alpha: 1, blendMode: .normal)
        let pixels = try XCTUnwrap(Self.rgba(of: texture))

        XCTAssertEqual(Self.channel(pixels, 32, 32, 0), 255, "the first dab is red")
        XCTAssertEqual(Self.channel(pixels, 32, 32, 2), 0)
        XCTAssertEqual(Self.channel(pixels, 96, 32, 2), 255, "the second dab is blue")
        XCTAssertEqual(Self.channel(pixels, 96, 32, 0), 0)
        XCTAssertEqual(texture.dabImageCacheMisses, 2)
    }

    /// **Alpha is deliberately *out* of the key**, exactly as it is out of `DabGradientCache`'s: it
    /// is `brushOpacity × flow × opacityFraction(pressure)` and varies per dab, so keying on it
    /// would hit approximately never. The entry is built at full alpha and `CGContext.setAlpha`
    /// scales it — so the second dab here shares the first's entry, and must not share its opacity.
    func testACacheHitDoesNotReuseThePreviousDabsAlpha() throws {
        let texture = RasterLayerTexture(size: CGSize(width: 128, height: 64))
        texture.stampImage(.builtIn(.square), at: CGPoint(x: 32, y: 32), diameter: 24, angle: 0,
                           color: .black, alpha: 0.1, blendMode: .normal)
        texture.stampImage(.builtIn(.square), at: CGPoint(x: 96, y: 32), diameter: 24, angle: 0,
                           color: .black, alpha: 1.0, blendMode: .normal)
        let pixels = try XCTUnwrap(Self.rgba(of: texture))

        XCTAssertEqual(CGFloat(Self.alpha(pixels, 32, 32)) / 255, 0.1, accuracy: 0.02)
        XCTAssertEqual(CGFloat(Self.alpha(pixels, 96, 32)) / 255, 1.0, accuracy: 0.02)
        XCTAssertEqual(texture.dabImageCacheMisses, 1, "one tip at one colour is one entry")
        XCTAssertEqual(texture.dabImageCacheHits, 1, "…and the second dab hit it")
    }

    /// A tip whose file is gone draws nothing rather than substituting some other shape. The honest
    /// failure for a deleted import, and the one that cannot quietly turn one brush into another.
    func testATipWithNoFileDrawsNothingRatherThanSomethingElse() throws {
        let texture = RasterLayerTexture(size: CGSize(width: 64, height: 64))
        texture.stampImage(.imported(fileName: "no-such-tip-\(UUID().uuidString).png"),
                           at: CGPoint(x: 32, y: 32), diameter: 40, angle: 0,
                           color: .black, alpha: 1, blendMode: .normal)
        let pixels = try XCTUnwrap(Self.rgba(of: texture))
        XCTAssertFalse(pixels.bytes.contains { $0 != 0 }, "A missing tip leaves the canvas alone")
        // Neither a hit nor a miss: the entry's size term comes from the mask's own resolution, so
        // the cache cannot form a key for a tip it could not load, and a broken import therefore
        // does not enter the counters at all. `BrushTextureStore` caches the failed read.
        XCTAssertEqual(texture.dabImageCacheMisses, 0)
        XCTAssertEqual(texture.dabImageCacheHits, 0)
    }

    // MARK: - `BakedDab`'s angle, and what a pose does to it

    /// **BRUSH.md §3.5: *"a sprite brush under a rotating keyframe keeps its stamps upright while
    /// the stroke turns"* is the failure the angle exists to prevent.** A pose that turns the stroke
    /// by 0.7 rad turns each of its picture stamps by 0.7 rad too, on top of whatever jitter the
    /// walk already gave them.
    func testAPoseTurnsAnImageDabsOwnAngleAndLeavesARoundDabAlone() throws {
        let pose = BrushStamper.DabPose(CGAffineTransform(rotationAngle: 0.7))
        let picture = BrushStamper.BakedDab(center: CGPoint(x: 10, y: 20), radius: 6, color: .black,
                                            alpha: 1, blendMode: .normal,
                                            tip: .image(.builtIn(.square), angle: 0.2))
        let moved = try XCTUnwrap(pose.applied(to: picture))
        guard case .image(let texture, let angle) = moved.tip else {
            return XCTFail("a picture dab stays a picture dab")
        }
        XCTAssertEqual(texture, .builtIn(.square))
        XCTAssertEqual(angle, 0.9, accuracy: 1e-12, "the pose's turn composes onto the dab's own")

        let disc = BrushStamper.BakedDab(center: CGPoint(x: 10, y: 20), radius: 6, color: .black,
                                         alpha: 1, blendMode: .normal, tip: .round(hardness: 0.5))
        XCTAssertEqual(try XCTUnwrap(pose.applied(to: disc)).tip, .round(hardness: 0.5),
                       "a disc has no orientation to change")
    }

    /// **A pose's turn is its Jacobian's polar rotation, and a shear is what says so.** The obvious
    /// alternative — the angle of the *mapped x-axis*, `atan2(b, a)` — agrees on every rotation and
    /// every uniform scale, and disagrees here: under `[[1, 0.6], [0, 1]]` it reports no turn at all
    /// while the tip's body is visibly leaning. Polar is the rotation closest to the Jacobian, which
    /// is what makes the square this primitive can draw the closest one to the parallelogram the
    /// pose actually makes of the dab.
    func testAShearTurnsADabByItsPolarRotationRatherThanByItsMappedAxis() throws {
        let shear = CGAffineTransform(a: 1, b: 0, c: 0.6, d: 1, tx: 0, ty: 0)
        let pose = BrushStamper.DabPose(shear)
        let turn = try XCTUnwrap(pose.rotation(at: CGPoint(x: 30, y: 40)))

        XCTAssertEqual(turn, atan2(0 - 0.6, 1 + 1), accuracy: 1e-12)
        XCTAssertEqual(turn, -0.2914567944778671, accuracy: 1e-9)
        XCTAssertNotEqual(turn, atan2(shear.b, shear.a), accuracy: 0.2,
                          "the mapped x-axis is unmoved by this shear; the tip is not")
    }

    /// **A projective pose turns every dab by its own amount, and that is the answer rather than a
    /// cost.** A homography's local rotation genuinely varies across the plane — it is what makes a
    /// receding checkerboard's squares lean differently near and far — so one angle for a whole
    /// stroke is wrong somewhere along it, and wrong by more the longer the stroke. `constantScale`
    /// records the same fact about the same case for the scale; this is its twin, not an analogy.
    func testAProjectivePoseTurnsEachDabByItsOwnLocalRotationWhileAnAffineAsksOnce() throws {
        let keystone = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: 0.002, h: 0.001, i: 1)
        let projective = BrushStamper.DabPose(keystone)
        XCTAssertNil(projective.constantRotation, "a projective map has no one answer")
        XCTAssertNil(projective.constantScale, "…and the existing scale says the same of itself")

        let near = try XCTUnwrap(projective.rotation(at: CGPoint(x: 10, y: 10)))
        let far = try XCTUnwrap(projective.rotation(at: CGPoint(x: 240, y: 180)))
        XCTAssertGreaterThan(abs(near - far), 1e-3,
                             "the same stroke's ends do not lean the same way under perspective")

        let affine = BrushStamper.DabPose(CGAffineTransform(rotationAngle: 0.4).scaledBy(x: 2, y: 2))
        XCTAssertEqual(try XCTUnwrap(affine.constantRotation), 0.4, accuracy: 1e-12,
                       "an affine's Jacobian is one matrix everywhere, so its turn is one number — "
                       + "and a uniform scale contributes none of it")
        XCTAssertEqual(try XCTUnwrap(affine.rotation(at: CGPoint(x: 900, y: -300))), 0.4, accuracy: 1e-12,
                       "…the same number wherever it is asked")
    }

    /// The streamed and stored forms of the bake share `DabPose.applied(to:)`, so they cannot drift —
    /// but "they share a function" is a claim about today's source and this is a claim about the
    /// answer. `RestSpaceDabBakeLogicTests` makes it for round dabs; the image arm is new code in
    /// both `PosedDabTarget` and `replay`, and this is the operand that catches one of them alone.
    func testAPosedImageWalkStreamsAndReplaysToTheSameDabs() {
        var jittering = BrushLibrary.square
        jittering.rotationJitter = 0.8
        let samples = StrokeSamples((0..<14).map {
            VectorSample(point: CGPoint(x: CGFloat($0) * 9, y: CGFloat($0) * 5), pressure: 0.4 + CGFloat($0) * 0.04)
        }, channels: .pressureOnly)
        let pose = BrushStamper.DabPose(CGAffineTransform(rotationAngle: 0.3).scaledBy(x: 1.7, y: 0.6))

        let streamed = BrushStamper.CollectingDabTarget()
        BrushStamper.stampStroke(into: BrushStamper.PosedDabTarget(streamed, pose: pose),
                                 samples: samples, brush: jittering, color: .black, brushSize: 24,
                                 brushOpacity: 1, random: DabRandom(seed: 4242))
        let replayed = BrushStamper.CollectingDabTarget()
        BrushStamper.replay(BrushStamper.bake(samples: samples, brush: jittering, color: .black,
                                              brushSize: 24, brushOpacity: 1, random: DabRandom(seed: 4242)),
                            into: replayed, through: pose)

        XCTAssertGreaterThan(streamed.dabs.count, 10, "Setup: there are dabs to compare")
        XCTAssertEqual(streamed.dabs, replayed.dabs)
        XCTAssertTrue(streamed.dabs.allSatisfy {
            if case .image = $0.tip { return true } else { return false }
        }, "Setup: a square brush's dabs are image dabs, or this compares the wrong arm")
        // The jitter is real, so a pose that dropped the angle would still make these two lists
        // agree — they would just both be wrong. Pin that the angles are not all one value.
        let angles = streamed.dabs.compactMap { dab -> CGFloat? in
            if case .image(_, let angle) = dab.tip { return angle } else { return nil }
        }
        XCTAssertGreaterThan(Set(angles.map { ($0 * 1000).rounded() }).count, 3,
                             "Setup: the jitter actually varies, so the equality above has content")
    }

    // MARK: - The window a live stroke draws into has to contain the dab

    /// **`StrokeScratch` clips a live stroke to its window, so a bound that is a pixel short deletes
    /// that pixel of ink outright.** An image dab makes this newly hard: `.high` interpolation
    /// reconstructs from a kernel wider than one texel, so CoreGraphics paints past the quad's own
    /// edge — MEASURED at up to 2.39 px, worst at exactly the downscales an artist draws at, which
    /// is why `dabImageBounds` carries a spill allowance rather than the geometry alone.
    ///
    /// The operand is the same one the round-dab commit tests use: stamping through the window must
    /// land the bytes stamping straight into the cel would have, at **zero** tolerance.
    func testAnImageDabThroughAStrokeScratchCommitsExactlyWhatDirectStampingWouldHave() throws {
        let size = CGSize(width: 256, height: 256)
        let dabs: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: 90, y: 100), 26, 0), (CGPoint(x: 104, y: 108), 30, .pi / 4),
            (CGPoint(x: 120, y: 116), 22, 0.9), (CGPoint(x: 133, y: 130), 34, -1.3)
        ]
        let direct = RasterLayerTexture(size: size)
        let viaScratch = RasterLayerTexture(size: size)
        let scratch = StrokeScratch(canvasSize: size, role: .additive)
        for (point, diameter, angle) in dabs {
            direct.stampImage(.builtIn(.square), at: point, diameter: diameter, angle: angle,
                              color: .blue, alpha: 0.7, blendMode: .normal)
            scratch.stampImage(.builtIn(.square), at: point, diameter: diameter, angle: angle,
                               color: .blue, alpha: 0.7, blendMode: .normal)
        }
        scratch.commit(into: viaScratch)

        let a = try XCTUnwrap(Self.rgba(of: viaScratch)), b = try XCTUnwrap(Self.rgba(of: direct))
        XCTAssertTrue(b.bytes.contains { $0 != 0 }, "Setup: something was drawn at all")
        var offending = 0, worst = 0
        for i in 0..<min(a.bytes.count, b.bytes.count) {
            let delta = abs(Int(a.bytes[i]) - Int(b.bytes[i]))
            worst = max(worst, delta)
            if delta != 0 { offending += 1 }
        }
        XCTAssertEqual(offending, 0,
                       "An image dab through the window must land the pixels stamping straight into "
                       + "the cel would have — \(offending) bytes differ, worst by \(worst)")
    }

    /// **The dirty rect sizes the undo patch, so a bound that misses the dab's resampled edge leaves
    /// that edge on the canvas after undo — and `StrokeScratch` clips a live stroke to a window built
    /// from the same function, so it loses that edge outright.**
    ///
    /// **This is a sweep and not one dab, and it has no slack, because the first version of it had
    /// both faults and caught nothing.** It stamped a single 36 pt dab at 0.6 rad and compared
    /// against the bound inset by a forgiving pixel, and it stayed green with `dabImageBounds`'
    /// allowance set to **zero** — i.e. it was green against the defect it is named for. Six sizes ×
    /// five angles, at a fractional centre, compared exactly.
    ///
    /// The last assertion is the one that makes the rest mean something: **the geometry alone is not
    /// enough**. CoreGraphics reconstructs a resampled image from a kernel wider than one texel and
    /// then covers whole pixels, so the painted box escapes the exact rotated square, and a bound
    /// built from `(d/2)(|cos θ| + |sin θ|)` and nothing else is short. If that ever stopped being
    /// true the allowance could shrink — but it would be a measurement saying so, not an assumption.
    func testTheDabBoundContainsEveryPixelAnImageDabPaintsAtEverySizeAndAngle() throws {
        let side = 256
        let centre = CGPoint(x: 128.3, y: 128.7)
        var geometryAloneWasShort = false
        var worstShortfall: CGFloat = 0
        for diameter in [CGFloat(9), 16, 24, 36, 64, 129] {
            for angle in [CGFloat(0), CGFloat.pi / 8, CGFloat.pi / 4, 0.6, 1.1] {
                let texture = RasterLayerTexture(size: CGSize(width: side, height: side))
                texture.beginStroke()
                texture.stampImage(.builtIn(.square), at: centre, diameter: diameter, angle: angle,
                                   color: .black, alpha: 1, blendMode: .normal)
                let dirty = try XCTUnwrap(texture.strokeDirtyRect,
                                          "a dab that painted must report a dirty rect")
                let pixels = try XCTUnwrap(Self.rgba(of: texture))

                var painted = CGRect.null
                for y in 0..<pixels.height {
                    for x in 0..<pixels.width where Self.alpha(pixels, x, y) != 0 {
                        painted = painted.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                let label = "diameter \(diameter) at \(angle) rad"
                XCTAssertFalse(painted.isNull, "Setup: \(label) painted something")
                // `rgba` reads back through a bottom-left context, so the dirty rect's y has to be
                // flipped before the two can be compared at all.
                let flipped = CGRect(x: dirty.minX, y: CGFloat(side) - dirty.maxY,
                                     width: dirty.width, height: dirty.height)
                XCTAssertTrue(flipped.contains(painted),
                              "\(label): the dirty rect \(flipped) must contain every painted pixel \(painted)")

                let half = diameter / 2 * (abs(cos(angle)) + abs(sin(angle)))
                let geometryOnly = CGRect(x: centre.x - half, y: CGFloat(side) - centre.y - half,
                                          width: half * 2, height: half * 2)
                if !geometryOnly.contains(painted) {
                    geometryAloneWasShort = true
                    worstShortfall = max(worstShortfall,
                                         max(geometryOnly.minX - painted.minX,
                                             painted.maxX - geometryOnly.maxX))
                }
            }
        }
        XCTAssertTrue(geometryAloneWasShort,
                      "The exact rotated square is not a bound on the pixels a resampled draw "
                      + "touches — that is the whole reason `dabImageBounds` carries an allowance, "
                      + "and a sweep that could not see it would be green against a bound of zero, "
                      + "which is exactly how the first version of this test failed to catch one.")
        print("DAB BOUND | geometry alone falls short by up to \(worstShortfall) px")
    }

    // MARK: - Helpers

    private static func rgba(of texture: RasterLayerTexture) -> (bytes: [UInt8], width: Int, height: Int)? {
        rgba(of: texture.renderToUIImage().cgImage)
    }

    private static func rgba(of cg: CGImage?) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (bytes, width, height) : nil
    }

    private static func alpha(_ p: (bytes: [UInt8], width: Int, height: Int), _ x: Int, _ y: Int) -> Int {
        channel(p, x, y, 3)
    }

    private static func channel(_ p: (bytes: [UInt8], width: Int, height: Int),
                                _ x: Int, _ y: Int, _ index: Int) -> Int {
        Int(p.bytes[(y * p.width + x) * 4 + index])
    }

    /// Writes a 64×64 alpha mask whose opaque square is inset by `inset`, and hands back a ref to
    /// it. A fresh file name each time, so no test can be served a mask another test loaded.
    private static func writeTestTip(inset: CGFloat) throws -> BrushTextureRef {
        let n = 64
        let ctx = try XCTUnwrap(CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: PixelOps.deviceRGBColorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: inset, y: inset, width: CGFloat(n) - 2 * inset, height: CGFloat(n) - 2 * inset))
        let data = try XCTUnwrap(UIImage(cgImage: try XCTUnwrap(ctx.makeImage())).pngData())
        let fileName = "test-tip-\(UUID().uuidString).png"
        try data.write(to: BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName))
        return .imported(fileName: fileName)
    }
}
