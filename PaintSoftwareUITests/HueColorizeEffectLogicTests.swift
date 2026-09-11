import XCTest
import UIKit

/// **TODO (60)'s Hue Colorize, headlessly** — the mode `HSVShift.colorize` adds rather than a new
/// case (`Effect.HSVShift.colorize`'s doc has the full argument, the Blur precedent). This file pins
/// the two claims that make it Photoshop's Colorize rather than a plain hue rotation dressed up: the
/// target hue actually lands, and a pixel's own lightness survives the trip. Backend agreement lives
/// in `EffectParityLogicTests.sweep`'s `"hueColorize"` row, the same place `"dither"`/`"halftone"`
/// already cover TODO (60)'s other half; `OptionsPanelUITests` drives the real menu and settings bar.
final class HueColorizeEffectLogicTests: XCTestCase {

    private static let side = 16

    // MARK: - Fixtures

    private func flatBytes(_ r: Int, _ g: Int, _ b: Int, side: Int = HueColorizeEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = UInt8(r); bytes[pixel + 1] = UInt8(g); bytes[pixel + 2] = UInt8(b)
            bytes[pixel + 3] = 255
        }
        return bytes
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8]) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: Self.side, height: Self.side)
    }

    /// W3C `Lum`, the same weighting `Effect.GradientMap` and this effect's own colorize branch use,
    /// on one pixel's first three bytes (0...255 scale, unpremultiplied — every fixture here is opaque).
    private func lum(_ bytes: [UInt8], at offset: Int = 0) -> Double {
        0.3 * Double(bytes[offset]) + 0.59 * Double(bytes[offset + 1]) + 0.11 * Double(bytes[offset + 2])
    }

    private func colorize(hue: Double, saturation: Double, value: Double = 1) -> Effect {
        .hsvShift(Effect.HSVShift(hueDegrees: hue, saturation: saturation, value: value, colorize: true))
    }

    // MARK: - Lightness is preserved

    /// **The claim the whole feature exists for**: a mid-grey pixel's `Lum` survives colorizing to
    /// any hue, at the catalogue's own saturation (0.5) — chosen there, and reused here, because it
    /// keeps every hue's own ceiling (`Effect.HSVShift.colorize`'s `k(H,S)`) above 0.5, so the solve
    /// never clamps and the claim is exact rather than "as close as gamut allows".
    ///
    /// **Mutation-tested, and the result corrected this comment rather than the other way round.**
    /// Replacing the solved `v = targetLum / k` with the naive `hsb.v * value` (the shift branch's own
    /// formula, applied to the *target* hue/saturation instead of the pixel's) moves every row here by
    /// 7 to 57 bytes — MEASURED from the same closed form this file computes with, since `hsb.v` of a
    /// grey pixel is a constant `0.502` and `k(H, 0.5)` ranges `0.555…0.945` over the swept hues, so
    /// `Lum_out = 0.502 · k` never lands near `0.502` itself. **But reverting the colorize branch
    /// entirely — falling through to the shift formula unconditionally — does NOT move this test at
    /// all**, and that is not a gap in the arithmetic above, it is a property of grey itself: a grey
    /// pixel's own saturation is already 0, so a *shift*, which multiplies saturation rather than
    /// replacing it, cannot add any chroma either and grey passes through both formulas unchanged.
    /// `testHueLandsOnTheConstantEvenStartingFromAnUnrelatedHue` and
    /// `testHueSweepsTheWholeWheelUnderColorize` are what catch the full-fallback mutation instead —
    /// both use a saturated, non-zero-hue fixture for exactly this reason, stated in their own doc.
    func testLumOfAMidGreyPixelIsUnchangedUnderColorizeAtAnyHue() {
        let grey = flatBytes(128, 128, 128)
        let inputLum = lum(grey)
        for hue in stride(from: 0.0, to: 360.0, by: 30.0) {
            let out = cpu(colorize(hue: hue, saturation: 0.5), grey)
            XCTAssertEqual(lum(out), inputLum, accuracy: 2,
                           "Lum drifted at hue \(hue)°: \(lum(out)) vs \(inputLum). Pixel: \(Array(out[0...3]))")
        }
    }

    /// **The multiplier half of the same claim.** `value` is still "the multiplier it already is"
    /// (`Effect.HSVShift.colorize`'s doc) — just applied to the target `Lum` rather than to the
    /// pixel's own `V`, so halving it should halve the output `Lum` too, not merely dim `V`.
    func testValueMultipliesTheTargetLumRatherThanTheRawBrightness() {
        let grey = flatBytes(128, 128, 128)
        let inputLum = lum(grey)
        let out = cpu(colorize(hue: 200, saturation: 0.5, value: 0.5), grey)
        XCTAssertEqual(lum(out), inputLum * 0.5, accuracy: 2,
                       "Halving Value should halve the output Lum. Got \(lum(out)), wanted \(inputLum * 0.5)")
    }

    /// **The gamut edge, named rather than left as an unexplained tolerance elsewhere.** A fully
    /// saturated target hue's own ceiling can sit below a bright pixel's `Lum` (a pure blue's ceiling
    /// is `Lum ≈ 0.11`, far under a near-white pixel's own `Lum`), and the solve is documented to
    /// clamp there rather than overshoot. This is that clamp, pinned rather than merely claimed: at
    /// `saturation: 1` a near-white pixel colorized toward blue must not exceed blue's own ceiling.
    func testAtFullSaturationTheSolveClampsToTheHuesOwnCeilingRatherThanOvershooting() {
        let brightGrey = flatBytes(230, 230, 230)
        let blueFull = cpu(colorize(hue: 240, saturation: 1), brightGrey)
        // Pure blue at V=1 is (0,0,255) unpremultiplied, Lum = 0.11*255 ≈ 28.
        XCTAssertEqual(lum(blueFull), 0.11 * 255, accuracy: 3,
                       "A saturation-1 blue colorize of a bright pixel must hold at blue's own ceiling, "
                       + "not the input's Lum: got \(lum(blueFull))")
        XCTAssertLessThan(lum(blueFull), lum(brightGrey), "The clamp must not exceed the ceiling")
    }

    // MARK: - The hue actually lands

    /// **On a fixture that already has a hue of its own**, so a bug that left the *shift* branch's
    /// `hsb.h + hueTurns` running instead of the colorize branch's absolute `hue` would show up as
    /// the wrong hue rather than coincidentally the right one — a pure-red input's own hue (0°) is
    /// the one value that shift and colorize could agree on, so this fixture avoids it on purpose.
    func testHueLandsOnTheConstantEvenStartingFromAnUnrelatedHue() {
        let purpleIsh = flatBytes(180, 40, 200)   // hue ≈ 295°, nowhere near the 90° target below
        let out = cpu(colorize(hue: 90, saturation: 0.8), purpleIsh)
        let hsb = ColorMath.rgbToHSB(r: Double(out[0]) / 255, g: Double(out[1]) / 255, b: Double(out[2]) / 255)
        XCTAssertEqual(hsb.h * 360, 90, accuracy: 2, "The output hue must be the target, not the input's own")
    }

    /// **Swept across the wheel, on a fixture whose own hue is not a multiple of the 45° step** —
    /// mutation-caught, not merely careful: a `flatBytes(255, 0, 0)` fixture (hue 0°) first shipped
    /// here, and reverting the colorize branch to the plain shift formula (`hsb.h + hueTurns` instead
    /// of the absolute `hue`) still passed every row, because "rotate hue-0 by `target`" and "set hue
    /// to `target`" are the same output whenever the start is hue 0 — the identical trap the same
    /// mutation exposed in `testLumOfAMidGreyPixelIsUnchangedUnderColorizeAtAnyHue` from the other
    /// side (an achromatic pixel's saturation is already 0, so a shift can't add any either). A
    /// saturated input on **295°**, not on the swept grid at all, cannot coincide with any target.
    func testHueSweepsTheWholeWheelUnderColorize() {
        let purpleIsh = flatBytes(180, 40, 200)
        for target in stride(from: 0.0, to: 360.0, by: 45.0) {
            let out = cpu(colorize(hue: target, saturation: 0.8), purpleIsh)
            let hsb = ColorMath.rgbToHSB(r: Double(out[0]) / 255, g: Double(out[1]) / 255, b: Double(out[2]) / 255)
            let wrapped = (hsb.h * 360).truncatingRemainder(dividingBy: 360)
            let delta = min(abs(wrapped - target), 360 - abs(wrapped - target))
            XCTAssertLessThanOrEqual(delta, 2, "Target \(target)°, got \(wrapped)°")
        }
    }

    // MARK: - `colorize == false` is untouched

    /// **The non-colorize path must render exactly what the shift formula it always was computes** —
    /// reimplemented here independently of `EffectReference`, from `ColorMath` directly, so this test
    /// cannot pass by sharing a bug with the code it is checking. Mutation: routing `isColorize == 0`
    /// through the colorize branch by mistake moves every row here, since the two formulas agree only
    /// at the identity.
    func testColorizeFalseIsByteIdenticalToTheShiftFormula() {
        let fixtures: [(Int, Int, Int)] = [(220, 40, 90), (10, 200, 60), (128, 128, 128), (30, 30, 220)]
        let configs: [(hue: Double, sat: Double, value: Double)] = [
            (37, 1.4, 0.8), (0, 1, 1), (200, 0.3, 1.6), (-90, 0.6, 0.4),
        ]
        for (r, g, b) in fixtures {
            for config in configs {
                let bytes = flatBytes(r, g, b)
                let effect = Effect.hsvShift(Effect.HSVShift(hueDegrees: config.hue, saturation: config.sat,
                                                              value: config.value, colorize: false))
                let out = cpu(effect, bytes)

                let hsb = ColorMath.rgbToHSB(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
                let saturation = min(max(hsb.s * config.sat, 0), 1)
                let value = min(max(hsb.v * config.value, 0), 1)
                let expectedRGB = ColorMath.hsbToRGB(h: hsb.h + config.hue / 360, s: saturation, v: value)
                let expected = [UInt8((expectedRGB.r * 255).rounded()), UInt8((expectedRGB.g * 255).rounded()),
                                UInt8((expectedRGB.b * 255).rounded())]
                assertBytesEqual(Array(out[0...2]), expected, accuracy: 1,
                                 "\((r, g, b)) at \(config) must match the independently computed shift")
            }
        }
    }

    // MARK: - Persistence

    /// Absent `colorize` decodes to `false` — the guarantee every field in this file's payload makes,
    /// restated for the newest one. `Sharpen`'s recipe: an older document names other kinds and
    /// decodes exactly as it always did.
    func testAnOldHSVShiftDocumentDecodesToTheShiftItAlwaysWas() throws {
        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"hsvShift"}"#.utf8))
        XCTAssertEqual(bare, .hsvShift(Effect.HSVShift()), "No params at all is the identity")

        let partial = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"hsvShift","params":{"hueDegrees":30}}"#.utf8))
        XCTAssertEqual(partial, .hsvShift(Effect.HSVShift(hueDegrees: 30)),
                       "One knob written before colorize existed; colorize must default false")
        XCTAssertFalse({ if case .hsvShift(let p) = partial { return p.colorize }; return true }(),
                       "An older document must not silently become a colorize")

        let colourful = Effect.hsvShift(Effect.HSVShift(hueDegrees: 90, saturation: 0.6, colorize: true))
        let data = try JSONEncoder().encode(colourful)
        XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), colourful,
                       "A colorize round-trips its own flag")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""colorize":true"#),
                      "The flag is stored under its own name")
    }

    /// A document written before this case even had a `colorize` key at all — the general
    /// `Effect`-level guarantee, not a colorize-specific one, restated at the one new field.
    func testAVeryOldHSVShiftWithNoColorizeKeyAtAllDecodesToTheShift() throws {
        let older = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"hsvShift","params":{"hueDegrees":120,"saturation":1,"value":1}}"#.utf8))
        guard case .hsvShift(let p) = older else { return XCTFail("not an hsvShift") }
        XCTAssertEqual(p.hueDegrees, 120)
        XCTAssertFalse(p.colorize)
    }
}

private extension XCTestCase {
    /// `[UInt8]` has no built-in accuracy-tolerant comparison; this states it once for this file
    /// rather than unrolling three `XCTAssertEqual(_, accuracy:)` calls per row. Named apart from
    /// `XCTAssertEqual` on purpose: an extension method sharing that exact base name would shadow
    /// every *other* overload of the global function for the rest of this file's unqualified calls,
    /// which is a real Swift lookup trap and not a hypothetical one.
    func assertBytesEqual(_ a: @autoclosure () -> [UInt8], _ b: @autoclosure () -> [UInt8], accuracy: Int,
                          _ message: @autoclosure () -> String,
                          file: StaticString = #filePath, line: UInt = #line) {
        let (av, bv) = (a(), b())
        guard av.count == bv.count else {
            return XCTFail("count mismatch: \(av) vs \(bv). \(message())", file: file, line: line)
        }
        for (x, y) in zip(av, bv) {
            if abs(Int(x) - Int(y)) > accuracy {
                return XCTFail("\(av) vs \(bv), past accuracy \(accuracy). \(message())", file: file, line: line)
            }
        }
    }
}
