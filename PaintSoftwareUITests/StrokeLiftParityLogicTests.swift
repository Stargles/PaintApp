import XCTest
import UIKit
import CoreGraphics

/// **What changes between the stroke under the pen and the stroke the frame bakes** — TODO (84),
/// the owner's *"after a stroke is set, the stroke changes when it bakes"*.
///
/// The picture the artist watches is the live walk (`BrushStamper.LiveWalk`, every input sample,
/// a chord at a time) in the scratch; the picture that replaces it is the stored stroke — a
/// `StrokePathFit` refit of those samples — replayed by `stampStroke` along `StrokePath`'s curve
/// through the knots, and composited by the baker. This renders one hand-drawn stroke both ways
/// and diffs the two, then takes the difference apart so the number can be attributed rather than
/// guessed at: the replay of the **raw** samples sits between them, so *live vs raw replay* is the
/// walk's own contribution and *raw replay vs baked* is the refit's.
///
/// **What the walk contributed, MEASURED before the fix on this fixture and gone now:** a 48 pt
/// splatter read a mean channel delta of 0.082/255 over 1,402 pixels against the replay of its own
/// samples, and a 36 pt square nib 0.121/255 over 417 pixels at a worst channel delta of 240/255.
/// Two causes, both in `LiveWalk`'s header: the walk hopped from the last dab straight to the next
/// sample, cutting every corner a wide-spaced brush turned, and the first dab faced `+x` because a
/// stroke one point long has no direction. Both are closed — the walk marches the pen's own path by
/// arc length and holds its first sample until the second says which way the stroke goes — and
/// `testTheLiveWalkAndTheReplayOfItsOwnSamplesAreByteIdentical` is the pin.
///
/// **What is left is the refit, and it cannot be closed from the live side**: the stored stroke is a
/// curve through knots up to 12 pt apart that the live walk has not received yet when it stamps, so
/// its dabs sit within `StrokePathFit.tolerance` of the pen's path and, for a direction-following
/// tip, turn with the curve's tangent rather than the chord's. MEASURED on this fixture, live
/// against baked: every round-tip brush under 0.010/255 mean, and the widest-spaced sprite brushes
/// (grunge, stipple, streaky) 0.015–0.049/255 — the numbers the second test prints and bounds.
final class StrokeLiftParityLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 256, height: 128)
    private static let seed: UInt64 = 0x84

    /// A hand-drawn arc as the pen delivers it: input density, a pressure swell along it, and a
    /// pen that speeds up through the middle. `tremor` adds a deterministic hand wobble in points.
    private static func raw(count: Int = 240, tremor: CGFloat = 0) -> [VectorSample] {
        var noise: UInt64 = 0x9E37_79B9_7F4A_7C15
        func wobble() -> CGFloat {
            noise = noise &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (CGFloat(noise >> 40) / CGFloat(1 << 24) - 0.5) * 2 * tremor
        }
        return (0...count).map { i in
            let t = CGFloat(i) / CGFloat(count)
            // Ease in and out, so the samples bunch at the ends and spread through the middle.
            let s = t * t * (3 - 2 * t)
            return VectorSample(x: 20 + 216 * s + wobble(), y: 64 + 28 * sin(s * 3.2) + wobble(),
                                pressure: 0.35 + 0.5 * sin(t * .pi),
                                deltaTime: 1 / 120)
        }
    }

    private static func refit(_ raw: [VectorSample]) -> StrokeSamples {
        var fit = StrokePathFit()
        var stored = StrokeSamples(channels: .captured)
        for sample in raw { for knot in fit.offer(sample) { stored.append(knot) } }
        for knot in fit.finish(nil) { stored.append(knot) }
        return stored.compacted()
    }

    /// The live tier's picture: the walk the artist watches, committed at the stroke's opacity into
    /// a raster the way a raster layer commits it at lift.
    private static func live(_ raw: [VectorSample], brush: Brush, size: CGFloat, opacity: Double) -> UIImage {
        let scratch = StrokeScratch(canvasSize: canvasSize, role: .additive, opacity: CGFloat(opacity),
                                    blendMode: brush.stroke.blendMode.cgBlendMode, texture: brush.texture)
        var walk = BrushStamper.LiveWalk(seed: seed)
        for sample in raw {
            walk.stamp(to: sample, into: scratch, brush: brush, color: .black, brushSize: size)
        }
        walk.finish(into: scratch, brush: brush, color: .black, brushSize: size)
        let texture = RasterLayerTexture.empty(size: canvasSize)
        scratch.commit(into: texture)
        return texture.renderToUIImage()
    }

    /// The stored stroke's picture, as the cel renders it.
    private static func replay(_ samples: StrokeSamples, brush: Brush, size: CGFloat, opacity: Double) -> UIImage {
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: size, opacity: opacity, samples: samples, seed: seed)
        return VectorCanvas(size: canvasSize, elements: [.stroke(stroke)]).render()
    }

    private struct Delta: CustomStringConvertible {
        let mean: Double
        let max: Int
        let differing: Int
        var description: String { String(format: "mean %.4f/255, max %d/255, %d px", mean, max, differing) }
    }

    private static func delta(_ a: UIImage, _ b: UIImage) throws -> Delta {
        let report = try XCTUnwrap(RasterVectorParity.report(raster: a, vector: b, size: canvasSize),
                                   "both renders should be readable")
        return Delta(mean: report.meanChannelDelta, max: report.maxChannelDelta, differing: report.differingPixelCount)
    }

    /// Every shipped brush, so a change to the walk is measured against the tips it serves.
    private static let shipped: [(String, Brush)] = [
        ("roundSoft", BrushLibrary.roundSoft), ("opaqueRound", BrushLibrary.opaqueRound),
        ("roundHard", BrushLibrary.roundHard), ("square", BrushLibrary.square),
        ("messyFlat", BrushLibrary.messyFlat), ("pencilHard", BrushLibrary.pencilHard),
        ("pencilSoft", BrushLibrary.pencilSoft), ("pencilBlunt", BrushLibrary.pencilBlunt),
        ("pencilTextured", BrushLibrary.pencilTextured), ("technicalPenFine", BrushLibrary.technicalPenFine),
        ("brushPen", BrushLibrary.brushPen), ("roughInkBlotchy", BrushLibrary.roughInkBlotchy),
        ("roughInk", BrushLibrary.roughInk), ("painterly", BrushLibrary.painterly),
        ("bristle", BrushLibrary.bristle), ("streaky", BrushLibrary.streaky),
        ("grunge", BrushLibrary.grunge), ("splatter", BrushLibrary.splatter),
        ("stipple", BrushLibrary.stipple), ("chalk", BrushLibrary.chalk),
    ]

    /// Whether a brush's dab is placed or turned on the stroke's own frame — the one thing the chord
    /// and the curve disagree about at input density. A tip that follows the direction turns with
    /// it; a scatter is resolved onto it (BRUSH.md §2.30).
    private static func readsTheFrame(_ brush: Brush) -> Bool {
        brush.dab.angle.directionFollow > 0
            || brush.dab.scatterAcross > 0 || brush.dab.scatterAlong > 0
            || brush.modulations.drives(.scatterAcross) || brush.modulations.drives(.scatterAlong)
            || brush.modulations.rows.contains { $0.readInputs.contains(.direction) }
    }

    /// **The live walk and the replay of its own samples draw the same picture, to the byte**, for
    /// every brush whose dab does not turn with the stroke. The two operands are the two walks over
    /// one sample list, so nothing but the walk itself can separate them: a corner cut, a first dab
    /// facing the wrong way, a spacing carried differently — each was measured here before it was
    /// fixed, and each would red this again.
    ///
    /// A brush that reads the stroke's frame — a direction-following tip, a scatter — is held to
    /// the curve's angular error instead: the live chord and the curve through the *same* samples
    /// differ in tangent by well under a degree on this fixture, which on a 36 pt square nib is a
    /// few pixels of edge and on a scattered dab a hair of position.
    func testTheLiveWalkAndTheReplayOfItsOwnSamplesAreByteIdentical() throws {
        let raw = Self.raw()
        let rawRun = StrokeSamples(raw, channels: .captured)
        for (name, brush) in Self.shipped {
            let delta = try Self.delta(Self.live(raw, brush: brush, size: brush.size, opacity: 1),
                                       Self.replay(rawRun, brush: brush, size: brush.size, opacity: 1))
            if Self.readsTheFrame(brush) {
                XCTAssertLessThan(delta.mean, 0.05,
                                  "\(name): a frame-reading brush differs from the curve's tangent only: \(delta)")
            } else {
                XCTAssertEqual(delta.differing, 0, "\(name): the walk and the replay of its samples are one picture: \(delta)")
            }
        }
    }

    /// **What is left between the stroke under the pen and the baked one is the refit**, bounded and
    /// printed per brush so the next re-take reads the numbers rather than the pass. The straight
    /// line is the control: with the chord and the curve one line, nothing is left at all.
    func testWhatIsLeftBetweenTheLiveStrokeAndTheBakedOneIsTheRefit() throws {
        let raw = Self.raw()
        let stored = Self.refit(raw)
        XCTAssertLessThan(stored.count, raw.count / 3, "the refit must have thinned the path, or this measures nothing")
        var worstRound = 0.0, worstSprite = 0.0
        for (name, brush) in Self.shipped {
            let livePicture = Self.live(raw, brush: brush, size: brush.size, opacity: 1)
            let baked = Self.replay(stored, brush: brush, size: brush.size, opacity: 1)
            let rawReplay = Self.replay(StrokeSamples(raw, channels: .captured), brush: brush, size: brush.size, opacity: 1)
            let lift = try Self.delta(livePicture, baked)
            let refit = try Self.delta(rawReplay, baked)
            print("MEASURED (84) \(name): live vs baked \(lift) | of which the refit \(refit)")
            switch brush.tip {
            case .round: worstRound = max(worstRound, lift.mean)
            case .stamp: worstSprite = max(worstSprite, lift.mean)
            }
        }
        XCTAssertLessThan(worstRound, 0.01, "a round tip changes on lift by the refit's geometry alone")
        XCTAssertLessThan(worstSprite, 0.06, "a sprite tip by the refit's geometry and its tangent")

        let line = (0...240).map {
            VectorSample(x: 20 + CGFloat($0) * 0.9, y: 64, pressure: 0.35 + 0.5 * sin(CGFloat($0) / 240 * .pi), deltaTime: 1 / 120)
        }
        let brush = BrushLibrary.roundHard
        let control = try Self.delta(Self.live(line, brush: brush, size: 16, opacity: 1),
                                     Self.replay(Self.refit(line), brush: brush, size: 16, opacity: 1))
        XCTAssertEqual(control.differing, 0, "on a straight line the refit changes no pixel: \(control)")
    }

    /// The same measurement with a hand's wobble on every input sample — white noise of ±0.3 pt at
    /// 120 Hz, which is more than a stabilised pencil leaves, so this is the ceiling rather than
    /// the case.
    ///
    /// **This is the part that cannot be closed, and the reason is arc length.** A wobbly path is
    /// longer than the curve the refit draws through it, and the live walk marches the path the
    /// pen took while the replay marches the fit, so on a brush whose dabs are 22 pt apart every
    /// drop past the first lands a little earlier on the stored stroke than it did under the pen,
    /// and a whole drop fewer fit in. The only walk that would agree with the stored stroke is a
    /// walk of the stored stroke, and the fit commits a knot only once the sample after it proves
    /// it was needed — up to `StrokePathFit.maximumKnotSpacing` behind the pen — so the ink would
    /// trail the nib by up to 12 pt. The numbers are printed so a re-take reads them; the bounds
    /// are what was MEASURED, doubled.
    func testWithAHandsTremorTheDifferenceIsTheRefitsSmoothing() throws {
        let raw = Self.raw(tremor: 0.3)
        let stored = Self.refit(raw)
        for (name, brush, ceiling) in [("roundHard", BrushLibrary.roundHard, 0.15), ("square", BrushLibrary.square, 0.7),
                                       ("splatter", BrushLibrary.splatter, 2.5)] {
            let livePicture = Self.live(raw, brush: brush, size: brush.size, opacity: 1)
            let lift = try Self.delta(livePicture, Self.replay(stored, brush: brush, size: brush.size, opacity: 1))
            let walk = try Self.delta(livePicture, Self.replay(StrokeSamples(raw, channels: .captured),
                                                              brush: brush, size: brush.size, opacity: 1))
            print("MEASURED (84) tremor 0.3 pt \(name): live vs baked \(lift) | walk alone \(walk)")
            XCTAssertLessThan(lift.mean, ceiling, "\(name): \(lift)")
        }
    }
}
