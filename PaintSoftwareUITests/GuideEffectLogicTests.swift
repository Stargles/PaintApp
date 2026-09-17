import XCTest
import UIKit

/// TODO (88)'s Guide, headlessly: where a line lands, in bytes, for each of the three modes; the
/// tent a wider line makes; that it is a grade (alpha untouched, transparency untouched); both
/// backends; a strip against the whole frame; persistence; and what the kernels are handed.
///
/// **The specification is `Effect.Guide`'s doc and every expected byte below is computed from it
/// by hand** — a line is a pixel-centred tent `lineWidth/2 + ½` wide on the distance to the nearest
/// line of a family, families combine by `max`, and the colour is mixed in by `opacity · coverage`.
/// `EffectParameterCharacterizationTests`, `FrameBakeKeyLogicTests`, `EffectLayerLogicTests`,
/// `EffectParameterTrackLogicTests` and `MergeBakeLogicTests` own the hand-typed all-effects sweeps
/// this shipped a twentieth row into; `GuideUITests` drives the same effect from an empty document
/// and asserts what the canvas draws.
final class GuideEffectLogicTests: XCTestCase {

    private static let side = 64

    // MARK: - Fixtures

    private func whiteBytes(side: Int = GuideEffectLogicTests.side) -> [UInt8] {
        [UInt8](repeating: 255, count: side * side * 4)
    }

    /// `EffectParityLogicTests.spectrumBytes`, restated at this file's side.
    private func spectrumBytes() -> [UInt8] {
        let side = Self.side
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let colour = [x * 4, y * 4, ((x + y) * 2) % 256]
                let alpha = min(255, (x / 8) * 36 + (y / 16) * 3)
                let offset = (x + y * side) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    private static let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)

    /// A fully opaque, full-strength, one-pixel red line — the settings under which a pixel on a
    /// line is exactly `(255, 0, 0, 255)` and one off it exactly white.
    private func guide(_ mode: Effect.Guide.Mode, spacing: Double = 16, subdivisions: Int = 0,
                       angle: Double = 30, lineWidth: Double = 1, opacity: Double = 1,
                       density: Int = 24, horizon: Double = 0.5,
                       point1: (Double, Double) = (0.5, 0.5), point2: (Double, Double) = (0.25, 0.5),
                       twoPoint: Bool = false) -> Effect {
        .guide(Effect.Guide(mode: mode, spacing: spacing, subdivisions: subdivisions,
                            angleDegrees: angle, lineWidth: lineWidth, color: Self.red, opacity: opacity,
                            density: density, horizon: horizon,
                            vanishingPoint1X: point1.0, vanishingPoint1Y: point1.1,
                            vanishingPoint2X: point2.0, vanishingPoint2Y: point2.1, twoPoint: twoPoint))
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8], width: Int = GuideEffectLogicTests.side,
                     height: Int = GuideEffectLogicTests.side,
                     origin: (x: UInt32, y: UInt32) = (0, 0),
                     frameSize: (width: UInt32, height: UInt32)? = nil) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: width, height: height, origin: origin, frameSize: frameSize)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int, width: Int = GuideEffectLogicTests.side) -> [Int] {
        let offset = (x + y * width) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private let lineRed = [255, 0, 0, 255]
    private let white = [255, 255, 255, 255]

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    // MARK: - Grid

    /// **A grid line lands on the column and the row the spacing says, and nowhere beside them.**
    /// Spacing 16 from the frame's top-left: columns 0, 16, 32, 48 and the same rows are the line
    /// and every other pixel is untouched. Pinned on the pixel to either side of a line as well as
    /// on the line, since a line one column off would still be "a grid".
    ///
    /// MEASURED by mutation: with `guidePixel` reading `x + 1` for `q.x`, column 15 goes red and
    /// column 16 goes white, and the first two assertions go red.
    func testAGridLineLandsOnTheColumnAndRowTheSpacingSays() {
        let out = cpu(guide(.grid), whiteBytes())
        XCTAssertEqual(pixel(out, 16, 5), lineRed, "Column 16 is the second vertical")
        XCTAssertEqual(pixel(out, 15, 5), white, "…and column 15 is beside it")
        XCTAssertEqual(pixel(out, 17, 5), white, "…as is column 17")
        XCTAssertEqual(pixel(out, 5, 32), lineRed, "Row 32 is the third horizontal")
        XCTAssertEqual(pixel(out, 5, 33), white, "…and row 33 is beside it")
        XCTAssertEqual(pixel(out, 0, 0), lineRed, "The lines start at the frame's corner")
        XCTAssertEqual(pixel(out, 48, 48), lineRed, "…and a crossing is one line's colour, not two")
        XCTAssertEqual(pixel(out, 5, 5), white, "A cell's interior is untouched")
    }

    /// **Subdivisions draw fainter lines between the majors** — one subdivision halves the spacing
    /// and the minor line sits at half the opacity, so on white it is `(255, 128, 128)`: the colour
    /// mixed in by `0.5`, quantized to nearest-even. The majors stay full red.
    func testSubdivisionsDrawFainterLinesBetweenTheMajors() {
        let out = cpu(guide(.grid, subdivisions: 1), whiteBytes())
        XCTAssertEqual(pixel(out, 8, 5), [255, 128, 128, 255], "The minor line at column 8, at half the opacity")
        XCTAssertEqual(pixel(out, 16, 5), lineRed, "The major at column 16 is still full")
        XCTAssertEqual(pixel(out, 9, 5), white, "…and nothing beside the minor")
        XCTAssertEqual(pixel(out, 5, 8), [255, 128, 128, 255], "The minor row too")
    }

    /// **A wider line covers its neighbours by the tent** — width 3 is `half = 2`, so the columns at
    /// distance 0 and 1 are full and the column at distance 2 is exactly not: three columns of red,
    /// and the fourth white. A fractional width reads through the same tent: width 2 leaves the
    /// neighbours at exactly half.
    func testAWiderLineCoversItsNeighboursByTheTent() {
        let three = cpu(guide(.grid, lineWidth: 3), whiteBytes())
        for x in 15...17 { XCTAssertEqual(pixel(three, x, 5), lineRed, "Width 3 covers column \(x)") }
        XCTAssertEqual(pixel(three, 14, 5), white, "…and stops at column 14")
        XCTAssertEqual(pixel(three, 18, 5), white, "…and at column 18")
        let two = cpu(guide(.grid, lineWidth: 2), whiteBytes())
        XCTAssertEqual(pixel(two, 16, 5), lineRed)
        XCTAssertEqual(pixel(two, 15, 5), [255, 128, 128, 255], "Width 2 reaches half a column each side")
        XCTAssertEqual(pixel(two, 17, 5), [255, 128, 128, 255])
    }

    /// **Opacity scales the whole line, and a zero width or a zero opacity is the identity** —
    /// byte for byte, because the mix's amount is exactly 0.
    func testOpacityScalesTheLineAndZeroIsTheIdentity() {
        let bytes = spectrumBytes()
        XCTAssertEqual(cpu(guide(.grid, opacity: 0), bytes), bytes, "Opacity 0 draws nothing")
        XCTAssertEqual(cpu(guide(.isometric, lineWidth: 0), bytes), bytes, "Width 0 draws nothing")
        let faint = cpu(guide(.grid, opacity: 0.25), whiteBytes())
        XCTAssertEqual(pixel(faint, 16, 5), [255, 191, 191, 255], "A quarter of the way to red: 255 − 0.25·255 = 191.25")
    }

    // MARK: - Isometric

    /// **Isometric draws verticals and two slanted families.** At 30° and spacing 16 the rising
    /// family's normal is `(−½, √3/2)`: the frame's corner is on its zero line, and `(32, 0)` is on
    /// its next one (`−16` folds to 0). A pixel off all three families — `(5, 5)`: 5 from the
    /// vertical, 1.8 from the rising line, 6.8 from the falling — is white.
    ///
    /// MEASURED by mutation: with the rising family's normal spelled `(sin a, cos a)` (the falling
    /// family's), `(32, 0)` is 27.7 from the nearest line and goes white.
    func testIsometricDrawsVerticalsAndTwoSlantedFamilies() {
        let out = cpu(guide(.isometric), whiteBytes())
        XCTAssertEqual(pixel(out, 16, 5), lineRed, "The vertical at column 16")
        XCTAssertEqual(pixel(out, 0, 0), lineRed, "The corner is on every family's zero line")
        XCTAssertEqual(pixel(out, 32, 0), lineRed, "…and (32, 0) on the rising family's next line")
        XCTAssertEqual(pixel(out, 5, 5), white, "A pixel off all three families")
        // Angle 45°: the rising family is the anti-diagonal, `x + y = k·16·√2` — (11, 11)·(−1, 1)/√2 = 0.
        let diagonal = cpu(guide(.isometric, angle: 45), whiteBytes())
        XCTAssertEqual(pixel(diagonal, 11, 11), lineRed, "At 45° the main diagonal is a rising line")
        XCTAssertEqual(pixel(diagonal, 11, 5), white)
    }

    // MARK: - Perspective

    /// **Perspective draws the horizon and rays from the vanishing point.** On a 64-frame the horizon
    /// at 0.5 is row 32; the point at `(0.5, 0.5)` is pixel (32, 32) and with a density of 4 the rays
    /// are every 45°, so the column above the point and the diagonal through it are lines, and a pixel
    /// 18° off a ray at radius 12.6 — 4 pixels from it — is not. A second point draws only when asked.
    ///
    /// MEASURED by mutation: with the pitch left at `π` (one ray), (40, 40) on the 45° ray goes white.
    func testPerspectiveDrawsTheHorizonAndRaysFromEachVanishingPoint() {
        let one = cpu(guide(.perspective, density: 4), whiteBytes())
        XCTAssertEqual(pixel(one, 5, 32), lineRed, "The horizon at row 32")
        XCTAssertEqual(pixel(one, 5, 31), white, "…and not row 31")
        XCTAssertEqual(pixel(one, 32, 10), lineRed, "The vertical ray above the point")
        XCTAssertEqual(pixel(one, 40, 40), lineRed, "The 45° ray through it")
        XCTAssertEqual(pixel(one, 44, 36), white, "18° off the nearest ray, four pixels away")
        XCTAssertEqual(pixel(one, 16, 10), white, "PREMISE: the second point's vertical is not drawn with one point")

        let two = cpu(guide(.perspective, density: 4, twoPoint: true), whiteBytes())
        XCTAssertEqual(pixel(two, 16, 10), lineRed, "With two points the second's vertical ray is drawn")
        XCTAssertEqual(pixel(two, 32, 10), lineRed, "…and the first's still is")
    }

    // MARK: - A grade

    /// **The guide is a grade: alpha is untouched everywhere and a transparent pixel stays so** —
    /// the paper's margin, which the accumulator holds as transparency, stays bare under a guide.
    func testTheGuideLeavesAlphaAndTransparencyAlone() {
        let bytes = spectrumBytes()
        for mode in Effect.Guide.Mode.allCases {
            let out = cpu(guide(mode, spacing: 5, lineWidth: 2, density: 8, twoPoint: true), bytes)
            XCTAssertNotEqual(out, bytes, "\(mode): the fixture is not vacuous")
            for pixel in 0..<(Self.side * Self.side) {
                XCTAssertEqual(out[pixel * 4 + 3], bytes[pixel * 4 + 3], "\(mode): alpha moved at pixel \(pixel)")
                if bytes[pixel * 4 + 3] == 0 {
                    XCTAssertEqual(Array(out[(pixel * 4)..<(pixel * 4 + 4)]), [0, 0, 0, 0],
                                   "\(mode): a transparent pixel drew a line")
                }
            }
        }
        XCTAssertFalse(guide(.grid).reshapesCoverage)
        XCTAssertTrue(guide(.grid).readsAbsolutePosition)
        XCTAssertEqual(guide(.grid).input, .backdrop)
        XCTAssertEqual(guide(.grid).passes.count, 1)
    }

    // MARK: - Both backends

    /// **Every mode through both backends on the spectrum**, at settings with fractional spacings and
    /// widths so the tents and the folds are exercised off the integer grid, held to the one channel
    /// step every effect holds to. Perspective's `atan2` and `sin` are the two transcendentals the
    /// GPU evaluates with fast math on; a step is what that costs.
    func testEveryModeAgreesBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let configurations: [(String, Effect)] = [
            ("grid", guide(.grid, spacing: 7.5, subdivisions: 2, lineWidth: 1.5, opacity: 0.8)),
            ("isometric", guide(.isometric, spacing: 11, angle: 30, lineWidth: 1.25, opacity: 0.6)),
            ("perspective", guide(.perspective, lineWidth: 1.5, opacity: 0.7, density: 10,
                                  horizon: 0.4, point1: (0.3, 0.4), point2: (0.9, 0.4), twoPoint: true)),
        ]
        var deltas: [(String, Int)] = []
        for (name, effect) in configurations {
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            let reference = cpu(effect, bytes)
            XCTAssertNotEqual(reference, bytes, "\(name): the fixture is not vacuous")
            deltas.append((name, maxChannelDelta(gpu, reference)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        XCTContext.runActivity(named: "[guide] Metal-vs-Swift max channel delta: \(table)") { _ in }
        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, 1, "\(name) differs by \(delta) between the shader and the Swift reference. Table: \(table)")
        }
    }

    // MARK: - A strip

    /// **A strip draws the lines the whole frame would, byte for byte** — the guide is a function of
    /// the *frame* coordinate (`readsAbsolutePosition`), so a window at rows 20…39 stamped with its
    /// origin and the frame's size draws exactly rows 20…39 of the whole: the grid's phase, the
    /// slant's fold and the perspective's point are all measured on the frame, not the buffer.
    ///
    /// MEASURED by mutation: with the origin left out of the wrapper's `x + originX`, the window's
    /// grid restarts at its own top row and the comparison goes red on every mode.
    func testAStripDrawsTheLinesTheWholeFrameWould() {
        let width = Self.side, height = Self.side
        let bytes = whiteBytes()
        for mode in Effect.Guide.Mode.allCases {
            let effect = guide(mode, spacing: 6, subdivisions: 1, lineWidth: 1.5, density: 8, twoPoint: true)
            let whole = cpu(effect, bytes)
            let top = 20, rows = 20
            let window = Array(bytes[(top * width * 4)..<((top + rows) * width * 4)])
            let strip = cpu(effect, window, width: width, height: rows,
                            origin: (0, UInt32(top)), frameSize: (UInt32(width), UInt32(height)))
            XCTAssertEqual(strip, Array(whole[(top * width * 4)..<((top + rows) * width * 4)]),
                           "\(mode): the strip must draw the whole frame's own rows")
        }
    }

    // MARK: - Persistence

    /// `{"kind":"guide","params":{…}}` round-trips every mode; a bare kind or a partial `params`
    /// decodes to the type's own defaults, and a document written before the case existed decodes
    /// exactly as it did.
    func testGuideSurvivesAJSONRoundTripAndAnOldDocumentDecodesToTheDefaults() throws {
        for mode in Effect.Guide.Mode.allCases {
            let effect = guide(mode, spacing: 24.5, subdivisions: 3, angle: 35, lineWidth: 2.5, opacity: 0.4,
                               density: 18, horizon: 0.45, point1: (0.2, 0.3), point2: (1.1, 0.3), twoPoint: true)
            let data = try JSONEncoder().encode(effect)
            XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), effect, "\(mode) did not survive encode/decode")
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""kind":"guide""#))
        }
        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"guide"}"#.utf8))
        XCTAssertEqual(bare, .guide(Effect.Guide()), "No params at all is the type's default")
        let partial = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"guide","params":{"mode":"isometric","spacing":40}}"#.utf8))
        XCTAssertEqual(partial, .guide(Effect.Guide(mode: .isometric, spacing: 40)), "Two knobs written, the rest defaulted")
        let older = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"noise","params":{"amount":0.2}}"#.utf8))
        XCTAssertEqual(older, .noise(Effect.Noise(amount: 0.2)))
    }

    // MARK: - What the kernels are handed

    /// `params` resolves the knobs once: the spacing floors at 2, the density at 1 with the pitch
    /// `π / density`, a non-finite knob is its default, the colour rides the trailing triple and
    /// the opacity `mix`, and the mode's code is `Mode.code`.
    func testParamsResolveTheKnobsOnceForBothBackends() {
        let p = guide(.perspective, spacing: 1, opacity: 0.3, density: 0).params
        XCTAssertEqual(p.guideSpacing, 2, "Floored at 2")
        XCTAssertEqual(Double(p.guidePitch), Double.pi, accuracy: 1e-6, "Density floors at 1: one ray, a pitch of π")
        XCTAssertEqual(p.guideMode, Effect.Guide.Mode.perspective.code)
        XCTAssertEqual(p.mix, 0.3, accuracy: 1e-6)
        XCTAssertEqual(p.colorR, 1); XCTAssertEqual(p.colorG, 0); XCTAssertEqual(p.colorB, 0)
        XCTAssertEqual(p.guideVanishingCount, 1)
        XCTAssertEqual(guide(.grid, twoPoint: true).params.guideVanishingCount, 2)
        XCTAssertEqual(Double(guide(.grid, density: 8).params.guidePitch), Double.pi / 8, accuracy: 1e-6)
        let broken = Effect.guide(Effect.Guide(spacing: .nan, horizon: .infinity)).params
        XCTAssertEqual(broken.guideSpacing, 64, "A non-finite spacing is the default")
        XCTAssertEqual(broken.guideHorizon, 0.5, "A non-finite horizon is the default")
        XCTAssertEqual(Set(Effect.Guide.Mode.allCases.map(\.code)).count, 3, "The three codes are distinct")
    }
}
