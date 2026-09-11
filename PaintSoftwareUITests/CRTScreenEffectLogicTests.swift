import XCTest
import UIKit

/// TODO (60)'s Computer Screen, headlessly: each of the six ingredients alone in bytes, all six at
/// zero as the identity, the two backends against each other — on a whole frame and on one strip
/// window of one — the presets, and persistence.
///
/// **Each ingredient is pinned on a fixture where its arithmetic is exact.** Scanlines and the mask
/// are tents that read exactly 0 or 1 on integer pixel centres with no curvature, so "every
/// `period`-th row and no other" is a byte-for-byte claim rather than a threshold. Curvature and the
/// vignette are pinned at the centre pixel, where both are the identity to well inside a channel
/// step, and at the corner, where one is transparent and the other is dark. Every number a test
/// compares against is computed inside the test from the fixture, never eyeballed from a render.
///
/// `CRTScreenUITests` drives the same effect from an empty document and asserts what the canvas
/// draws; `StripedCompositeLogicTests` pins the curvature's apron under the strip driver itself.
final class CRTScreenEffectLogicTests: XCTestCase {

    private static let side = 32

    // MARK: - Fixtures

    /// One flat opaque colour, repeated.
    private func flatBytes(_ r: Int, _ g: Int, _ b: Int, side: Int = CRTScreenEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = UInt8(r); bytes[pixel + 1] = UInt8(g); bytes[pixel + 2] = UInt8(b)
            bytes[pixel + 3] = 255
        }
        return bytes
    }

    /// `EffectParityLogicTests.spectrumBytes`, restated at this file's side: every pixel a different
    /// (colour, alpha) combination, with a fully transparent band and a fully opaque one.
    private func spectrumBytes(width: Int = CRTScreenEffectLogicTests.side,
                               height: Int = CRTScreenEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let colour = [x * 8, y * 8, ((x + y) * 4) % 256]
                let alpha = min(255, (x / 4) * 36 + (y / 8) * 3)
                let offset = (x + y * width) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8],
                     width: Int = CRTScreenEffectLogicTests.side,
                     height: Int = CRTScreenEffectLogicTests.side) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: width, height: height)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int, width: Int = CRTScreenEffectLogicTests.side) -> [Int] {
        let offset = (x + y * width) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    private func screen(_ configure: (inout Effect.CRTScreen) -> Void) -> Effect {
        var params = Effect.CRTScreen()
        configure(&params)
        return .crtScreen(params)
    }

    // MARK: - The identity

    /// **Every strength at zero is the identity, byte for byte, on both backends** — the property the
    /// brief asks pinned, and the one that says each ingredient is gated by its own knob rather than
    /// leaking a little at zero. The period is left at its default rather than zeroed, because a
    /// period is not a strength: at `scanlines == 0` it must not matter what it says.
    ///
    /// MEASURED by mutation: with the scanline tent no longer multiplied by `params.scanlines`, the
    /// CPU half reports the dark rows; with the `abs(w) <= 1` guard removed, nothing here moves — the
    /// identity has no pixel outside the frame — which is why the curvature test below pins the
    /// corner separately.
    func testAllZeroIsTheIdentityByteForByte() throws {
        let bytes = spectrumBytes()
        let identity = Effect.crtScreen(Effect.CRTScreen())
        XCTAssertTrue(Effect.CRTScreen().isIdentity, "The type's default is every strength at zero")
        XCTAssertEqual(cpu(identity, bytes), bytes, "All-zero must be the identity on the CPU")

        // And with a period that is not the default, and a fringe of zero on a fixture with alpha
        // edges — the bilinear taps land exactly on their own texel and must read it exactly.
        let oddPeriod = screen { $0.scanlinePeriod = 7 }
        XCTAssertEqual(cpu(oddPeriod, bytes), bytes, "A period with no scanline strength is inert")

        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared,
              let gpu = engine.apply(identity, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined the identity screen")
        }
        XCTAssertEqual(gpu, bytes, "All-zero must be the identity on the GPU")
    }

    /// A screen with no curvature never moves coverage — the fringe is in colour and never in
    /// alpha, and lines, mask and vignette are multipliers on colour — and `reshapesCoverage` says
    /// true anyway, for the curvature it may carry. The flag is a *may*, pinned in both directions
    /// by the curvature test below.
    func testWithoutCurvatureTheScreenLeavesAlphaByteForByte() {
        let bytes = spectrumBytes()
        let flat = screen { $0.scanlines = 0.8; $0.apertureMask = 0.7; $0.vignette = 0.9; $0.aberration = 3 }
        let out = cpu(flat, bytes)
        let moved = stride(from: 3, to: bytes.count, by: 4).first { out[$0] != bytes[$0] }
        XCTAssertNil(moved, "Lines, mask, vignette and fringe are colour-only; alpha moved at byte \(moved ?? -1)")
        XCTAssertNotEqual(out, bytes, "…and the fixture is not vacuous: the colour did move")
        XCTAssertTrue(flat.reshapesCoverage, "The flag is about what the effect *may* do, which is bend")
    }

    // MARK: - Scanlines

    /// **Scanlines alone darken every `period`-th row and no other.** On a flat grey, the dark row of
    /// each period — the last one, `y % period == period − 1` — reads `grey · (1 − strength)` and
    /// every other row reads `grey` unchanged, byte for byte. Two periods, so the rule is the rule
    /// and not a coincidence of 3.
    ///
    /// MEASURED by mutation: with the tent's centre moved from `period − 0.5` to `period − 1` — onto
    /// the boundary between two rows — every pixel centre sits half a row from it and no row is dark
    /// at all; this reports each dark row at 200 where 100 was expected, and the parity sweep reports
    /// the shader 126 levels away.
    func testScanlinesAloneDarkenEveryPeriodThRowAndNoOther() {
        for period in [3, 4] {
            let bytes = flatBytes(200, 200, 200)
            let out = cpu(screen { $0.scanlines = 0.5; $0.scanlinePeriod = Double(period) }, bytes)
            for y in 0..<Self.side {
                let dark = y % period == period - 1
                let want = dark ? 100 : 200
                for x in [0, 7, Self.side - 1] {
                    XCTAssertEqual(pixel(out, x, y), [want, want, want, 255],
                                   "Period \(period), row \(y) is \(dark ? "the dark row" : "a bright row")")
                }
            }
        }
    }

    // MARK: - The RGB mask

    /// **The mask alone keeps one channel per column and attenuates the other two.** Column `x % 3`
    /// passes channel `x % 3` in full — red, then green, then blue — and the other two at
    /// `1 − apertureMask`, so on white the three columns read red-, green- and blue-tinted in turn
    /// and nothing else moves. Every row, because the mask is about columns only.
    ///
    /// MEASURED by mutation: with the column centres at `0, 1, 2` instead of `0.5, 1.5, 2.5`, every
    /// pixel centre sits between two columns and column 1 reads `(128, 191, 191)` where
    /// `(128, 255, 128)` was expected.
    func testTheMaskAloneKeepsOneChannelPerColumnAndAttenuatesTheOtherTwo() {
        let bytes = flatBytes(255, 255, 255)
        let out = cpu(screen { $0.apertureMask = 0.5 }, bytes)
        let attenuated = Int((255.0 * 0.5).rounded())
        for y in [0, 13, Self.side - 1] {
            for x in 0..<Self.side {
                var want = [attenuated, attenuated, attenuated, 255]
                want[x % 3] = 255
                XCTAssertEqual(pixel(out, x, y), want, "Column \(x) passes channel \(x % 3) and dims the others")
            }
        }
    }

    // MARK: - Curvature

    /// **Curvature alone leaves the centre pixel unchanged and the corner transparent.** At full
    /// curvature `k` is `maxCurvature`, so the corner's source lands outside the unit square and the
    /// pixel is transparent — coverage moved, which is what `reshapesCoverage` declares — while the
    /// pixel nearest the centre bends by `k/side²` of a pixel and reads its own texel to well inside
    /// a channel step. Pinned on the spectrum so "unchanged" is about a pixel with neighbours that
    /// differ from it.
    ///
    /// MEASURED by mutation: with the `abs(w) <= 1` guard returning the clamped edge texel instead of
    /// transparent, the corner reads opaque and the alpha sweep finds nothing moved.
    func testCurvatureAloneLeavesTheCentreUnchangedAndTheCornerTransparent() {
        let bent = screen { $0.curvature = 1 }

        // The centre, on the spectrum, so "unchanged" is about a pixel whose neighbours differ.
        let spectrum = spectrumBytes()
        let out = cpu(bent, spectrum)
        let centre = Self.side / 2
        for (x, y) in [(centre, centre), (centre - 1, centre - 1), (centre, centre - 1)] {
            XCTAssertEqual(pixel(out, x, y), pixel(spectrum, x, y), "The pixel at (\(x), \(y)) is on the axis of the bend")
        }

        // The corners, on an opaque flat — the spectrum's top-left is transparent to begin with.
        let flat = flatBytes(200, 200, 200)
        let bentFlat = cpu(bent, flat)
        for (x, y) in [(0, 0), (Self.side - 1, 0), (0, Self.side - 1), (Self.side - 1, Self.side - 1)] {
            XCTAssertEqual(pixel(bentFlat, x, y), [0, 0, 0, 0], "The corner at (\(x), \(y)) is off the tube")
        }
        XCTAssertEqual(pixel(bentFlat, centre, centre), [200, 200, 200, 255], "The centre of the flat is untouched")
        XCTAssertTrue(bent.reshapesCoverage, "A bent picture that lost its corners has reshaped coverage")

        // And the corner pixel is not the only one: the whole corner region is off the tube, and a
        // full-curvature bend clears a real fraction of the frame rather than one pixel — while the
        // middle of every edge, where the bend is flat, is still on it.
        let cleared = stride(from: 3, to: flat.count, by: 4).filter { bentFlat[$0] == 0 }.count
        XCTAssertGreaterThan(cleared, 8, "Full curvature clears more than a pixel per corner, got \(cleared)")
        XCTAssertLessThan(cleared, Self.side * Self.side / 4, "…and not a quarter of the picture, got \(cleared)")
        XCTAssertEqual(pixel(bentFlat, 0, centre)[3], 255, "The middle of the left edge is on the tube")
        XCTAssertEqual(pixel(bentFlat, centre, 0)[3], 255, "The middle of the top edge is on the tube")

        // Curvature 0 clears nothing — the other direction of the same flag.
        XCTAssertEqual(cpu(screen { $0.curvature = 0 }, spectrum), spectrum, "No curvature is the identity")
    }

    // MARK: - Vignette

    /// **The vignette alone leaves the centre unchanged and darkens the corner.** `smoothstep` of
    /// `|n|²/2` is `~3 · 10⁻⁶` at the pixel nearest the centre — no channel step — and `~0.99` at the
    /// corner, so at strength 0.5 the corner reads about half of what it was.
    ///
    /// MEASURED by mutation: with `r` no longer halved, the centre still holds and the corner still
    /// reads about half — `saturate` catches it at 1 — but the middle of an edge, at `|n|² ≈ 0.94`,
    /// darkens as much as the corner does; the edge-against-corner margin is what goes red, and the
    /// first version of this test, which asked only that an edge be lighter than a corner at all,
    /// passed that mutation by a single channel step.
    func testVignetteAloneLeavesTheCentreUnchangedAndDarkensTheCorner() {
        let bytes = flatBytes(200, 200, 200)
        let out = cpu(screen { $0.vignette = 0.5 }, bytes)
        let centre = Self.side / 2
        XCTAssertEqual(pixel(out, centre, centre), [200, 200, 200, 255], "The centre is where the glass is lit")
        XCTAssertEqual(pixel(out, centre - 1, centre - 1), [200, 200, 200, 255])

        let corner = pixel(out, 0, 0)
        XCTAssertLessThan(corner[0], 110, "The corner darkens by about half at strength 0.5, got \(corner)")
        XCTAssertGreaterThan(corner[0], 90, "…and not to black, got \(corner)")
        XCTAssertEqual(corner[3], 255, "A vignette is a multiplier on colour; coverage stays")
        XCTAssertEqual(pixel(out, Self.side - 1, Self.side - 1), corner, "Symmetric about the centre")

        // The middle of an edge is half the corner's darkening: `|n|²/2` is 0.5 there, so it reads
        // about three quarters of the grey where the corner reads about half — a margin of fifty
        // levels, not one.
        let edge = pixel(out, 0, centre)
        XCTAssertLessThan(edge[0], 200, "An edge is darkened too")
        XCTAssertGreaterThanOrEqual(edge[0] - corner[0], 30,
                                    "An edge is lit markedly better than a corner: edge \(edge), corner \(corner)")
        XCTAssertEqual(pixel(out, centre, 0), edge, "The four edge middles are alike")
    }

    // MARK: - Colour fringe

    /// **The fringe alone splits a colour edge in colour and not in coverage.** Red is sampled
    /// outward and blue inward by `aberration · w` pixels, so across a black-to-white edge left of
    /// the centre — where "outward" is leftward — the first white pixel takes its red from the black
    /// side and reads cyan-ish, and the last black pixel takes its blue from the white side and
    /// reads blue-ish. Green, sampled where it is, is the edge itself. And on the axis of the frame
    /// `w` is ~0, so a pixel at the centre column does not move at all.
    ///
    /// MEASURED by mutation: with `fringe` dropped from the red and blue taps, every pixel reads its
    /// own texel and both fringe assertions fail at once.
    func testTheFringeAloneSplitsAnEdgeInColourAndNotInCoverage() {
        // Black left of column 8, white from it, opaque throughout.
        var bytes = flatBytes(0, 0, 0)
        for y in 0..<Self.side {
            for x in 8..<Self.side {
                let offset = (x + y * Self.side) * 4
                bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255
            }
        }
        let out = cpu(screen { $0.aberration = 4 }, bytes)
        let y = Self.side / 2

        let firstWhite = pixel(out, 8, y)
        XCTAssertEqual(firstWhite[1], 255, "Green is sampled where it is: the edge stays where it was")
        XCTAssertLessThan(firstWhite[0], 128, "Red is sampled outward — leftward here — into the black, got \(firstWhite)")
        XCTAssertEqual(firstWhite[3], 255, "The fringe is in colour, never in coverage")

        let lastBlack = pixel(out, 7, y)
        XCTAssertEqual(lastBlack[1], 0, "Green: still black")
        XCTAssertGreaterThan(lastBlack[2], 128, "Blue is sampled inward — rightward here — into the white, got \(lastBlack)")

        let moved = stride(from: 3, to: bytes.count, by: 4).first { out[$0] != bytes[$0] }
        XCTAssertNil(moved, "Alpha moved at byte \(moved ?? -1)")

        // A flat colour has no edge to fringe, whatever the offset — the taps read the same value.
        XCTAssertEqual(cpu(screen { $0.aberration = 6 }, flatBytes(90, 150, 210)), flatBytes(90, 150, 210),
                       "A fringe needs an edge; flat colour is left alone")
    }

    // MARK: - The two backends

    /// **Both backends over 1024 (colour, alpha) pairs at the Arcade preset** — the non-default one
    /// with every ingredient live, curvature included — and at LCD and CRT for the two other mixes,
    /// at the same one-channel-step tolerance `EffectParityLogicTests` holds every grade to.
    ///
    /// **One premise is checked rather than hoped.** The curvature's "outside the tube" test is a
    /// hard edge, and a source pixel within a float ulp of `|w| == 1` could fall on either side of it
    /// on the two backends — a whole pixel's worth of disagreement that is a property of any
    /// threshold, not of this kernel (the recolour's parity test makes the same point about its
    /// softness-0 ring). So the fixture is checked, on the CPU's own arithmetic, to have no pixel
    /// within `1e-3` of the boundary; a fixture that had one would be a bad fixture, not a bad kernel.
    ///
    /// **33 a side, not 32, because of exactly that**: at 32 the Arcade bend puts a pixel `2.9e-5`
    /// from the edge and the premise fails; at 33 every preset clears `1.8e-3` — MEASURED over
    /// 30…48 before the side was chosen.
    func testTheComputerScreenAgreesBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let side = 33
        let bytes = spectrumBytes(width: side, height: side)
        for preset in [Effect.CRTScreen.Preset.arcade, .crt, .lcd] {
            let params = Effect.CRTScreen.preset(preset)
            let effect = Effect.crtScreen(params)
            assertNoPixelSitsOnTheCurvatureBoundary(params, width: side, height: side, preset.rawValue)

            guard let gpu = engine.apply(effect, to: bytes, width: side, height: side) else {
                return XCTFail("The GPU declined the \(preset.rawValue) screen")
            }
            let reference = cpu(effect, bytes, width: side, height: side)
            let delta = maxChannelDelta(gpu, reference)
            XCTContext.runActivity(named: "[screen \(preset.rawValue)] Metal-vs-Swift max channel delta: \(delta)") { _ in }
            XCTAssertLessThanOrEqual(delta, 1,
                                     "The \(preset.rawValue) screen differs by \(delta) between the shader and the Swift reference")
            XCTAssertNotEqual(reference, bytes, "The fixture is not vacuous: \(preset.rawValue) moved something")
        }
    }

    /// **Both backends stamp the same frame onto one strip window.** A 32×32 buffer that is rows
    /// 16…47 of a 32×64 frame, at the CRT preset: the vignette's centre and the scanlines' phase are
    /// the frame's, not the buffer's, and the two backends have to agree about that as well as about
    /// the arithmetic. Held to the same channel step.
    ///
    /// MEASURED by mutation: with the shader reading the texture's size in place of
    /// `frameWidth/frameHeight`, the vignette centres on the strip and the curvature bends it as its
    /// own frame; this reports a delta of 255.
    func testBothBackendsStampTheSameFrameOntoAStripWindow() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let params = Effect.CRTScreen.preset(.crt)
        let effect = Effect.crtScreen(params)
        let origin: (x: UInt32, y: UInt32) = (0, 16)
        let frame: (width: UInt32, height: UInt32) = (32, 64)
        guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side,
                                     origin: origin, frameSize: frame) else {
            return XCTFail("The GPU declined the windowed screen")
        }
        let reference = EffectReference.apply(effect, to: bytes, width: Self.side, height: Self.side,
                                              origin: origin, frameSize: frame)
        let delta = maxChannelDelta(gpu, reference)
        XCTContext.runActivity(named: "[screen strip window] Metal-vs-Swift max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, 1, "The two backends stamp the strip's frame differently: delta \(delta)")

        // And the window is not the whole frame: the same buffer composited as its own frame is a
        // different picture, or the stamp is not being read.
        XCTAssertNotEqual(reference, cpu(effect, bytes),
                          "A strip must be windowed onto the frame, not treated as a smaller frame")
    }

    /// **A strip of a position-only screen is exactly the rows of the whole.** With no curvature and
    /// no fringe nothing reads a neighbour, so a 32-row window at rows 16…47 of a 32×64 frame must
    /// come out byte-identical to those rows of the whole frame — which pins `originX/originY` *and*
    /// `frameWidth/frameHeight` on the CPU reference at once: the origin phases the scanlines, the
    /// frame size centres the vignette.
    ///
    /// MEASURED by mutation: with `passes(inFrameAt:frameSize:)` stamping a zero frame and both
    /// kernels falling back to the buffer's size, the strip's vignette centres 16 rows too high and
    /// the first bytes differ; the same mutation seams `StripedCompositeLogicTests`' driver pin.
    func testAStripOfAPositionOnlyScreenIsTheRowsOfTheWhole() {
        let width = Self.side, frameHeight = 64, stripHeight = 32, top = 16
        let frameBytes = spectrumBytes(width: width, height: frameHeight)
        let effect = screen { $0.scanlines = 0.6; $0.scanlinePeriod = 5; $0.apertureMask = 0.4; $0.vignette = 0.7 }
        let whole = EffectReference.apply(effect, to: frameBytes, width: width, height: frameHeight)

        let stripBytes = Array(frameBytes[(top * width * 4)..<((top + stripHeight) * width * 4)])
        let strip = EffectReference.apply(effect, to: stripBytes, width: width, height: stripHeight,
                                          origin: (0, UInt32(top)),
                                          frameSize: (UInt32(width), UInt32(frameHeight)))
        let wholeRows = Array(whole[(top * width * 4)..<((top + stripHeight) * width * 4)])
        XCTAssertEqual(strip, wholeRows, "A strip must be the frame's own rows, phase and centre included")
        XCTAssertNotEqual(strip, EffectReference.apply(effect, to: stripBytes, width: width, height: stripHeight),
                          "…and not the same buffer treated as a whole frame")
    }

    /// The premise `testTheComputerScreenAgreesBetweenTheBackends` states: no pixel of the fixture
    /// sits within `margin` of the curvature boundary, on the CPU's own `Float` arithmetic.
    private func assertNoPixelSitsOnTheCurvatureBoundary(_ params: Effect.CRTScreen, width: Int, height: Int,
                                                        _ name: String, margin: Float = 1e-3,
                                                        file: StaticString = #filePath, line: UInt = #line) {
        let k = Float(params.curvature * Effect.CRTScreen.maxCurvature)
        let frame = SIMD2<Float>(Float(width), Float(height))
        var nearest: Float = .infinity
        for y in 0..<height {
            for x in 0..<width {
                let n = (SIMD2<Float>(Float(x), Float(y)) + 0.5) / frame * 2 - 1
                let w = n * (1 + k * SIMD2<Float>(n.y * n.y, n.x * n.x))
                nearest = min(nearest, abs(abs(w.x) - 1), abs(abs(w.y) - 1))
            }
        }
        XCTAssertGreaterThan(nearest, margin, "PREMISE (\(name)): a pixel sits \(nearest) from the tube's edge, "
                             + "where the two backends may legitimately disagree", file: file, line: line)
    }

    // MARK: - Presets

    /// **A preset writes the fields and reads back by name, and a drifted field reads "Custom".**
    /// Nothing is stored for the name: `preset` is a comparison against `preset(_:)`'s table, so the
    /// bar can never claim a look the sliders have left.
    ///
    /// MEASURED by mutation: with `preset` comparing only `scanlines`, the drifted-vignette case
    /// still reads CRT and the last assertion catches it.
    func testAPresetWritesTheFieldsAndReadsBackByNameAndADriftedFieldReadsCustom() {
        for preset in Effect.CRTScreen.Preset.allCases {
            let written = Effect.CRTScreen.preset(preset)
            XCTAssertEqual(written.preset, preset, "\(preset.rawValue) reads back as itself")
            XCTAssertFalse(written.isIdentity, "\(preset.rawValue) is a visible look, not the identity")
        }
        let looks = Effect.CRTScreen.Preset.allCases.map(Effect.CRTScreen.preset)
        for i in looks.indices {
            for j in looks.indices where j > i {
                XCTAssertNotEqual(looks[i], looks[j], "Four presets, four different sets of knobs")
            }
        }

        XCTAssertNil(Effect.CRTScreen().preset, "The identity is no preset: it reads Custom")

        var drifted = Effect.CRTScreen.preset(.crt)
        drifted.vignette += 0.01
        XCTAssertNil(drifted.preset, "One knob one tick off the CRT is Custom, not CRT")
        var swapped = Effect.CRTScreen.preset(.lcd)
        swapped.curvature = Effect.CRTScreen.preset(.arcade).curvature
        XCTAssertNil(swapped.preset, "A mix of two presets is neither")

        // And the parameter table addresses every field a preset writes, so a channel can drive
        // each of them: writing a preset's values through the table lands on the preset.
        var rebuilt = Effect.crtScreen(Effect.CRTScreen())
        for parameter in rebuilt.parameters {
            guard let value = parameter.read(.crtScreen(Effect.CRTScreen.preset(.portable))) else {
                return XCTFail("\(parameter.id) has no scalar read")
            }
            rebuilt = parameter.write(rebuilt, value)
        }
        guard case .crtScreen(let assembled) = rebuilt else { return XCTFail("Not a screen") }
        XCTAssertEqual(assembled.preset, .portable, "Six scalar writes through the table rebuild the preset")
    }

    /// The four presets are four different pictures — the brief's *"pick four or five that look
    /// distinct"* as bytes rather than as an adjective: pairwise, on the spectrum, they differ by
    /// more than a channel step somewhere.
    func testTheFourPresetsRenderFourDifferentPictures() {
        let bytes = spectrumBytes()
        let rendered = Effect.CRTScreen.Preset.allCases.map { (name: $0.rawValue, out: cpu(.crtScreen(Effect.CRTScreen.preset($0)), bytes)) }
        for i in rendered.indices {
            for j in rendered.indices where j > i {
                XCTAssertGreaterThan(maxChannelDelta(rendered[i].out, rendered[j].out), 16,
                                     "\(rendered[i].name) and \(rendered[j].name) look the same")
            }
        }
    }

    // MARK: - Persistence

    /// `{"kind":"crtScreen","params":{…}}` round-trips every preset, and what an older document lacks
    /// decodes to the identity — `Sharpen`'s recipe. A stored `"preset"` key, which no version writes,
    /// is ignored rather than read: the name is not persisted.
    func testTheScreenSurvivesAJSONRoundTripAndAnOldDocumentDecodesToTheIdentity() throws {
        for preset in Effect.CRTScreen.Preset.allCases {
            let effect = Effect.crtScreen(Effect.CRTScreen.preset(preset))
            let data = try JSONEncoder().encode(effect)
            XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), effect,
                           "\(preset.rawValue) did not survive encode/decode")
            let json = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(json.contains(#""kind":"crtScreen""#), "The kind is the case's stable name")
            XCTAssertFalse(json.contains("preset"), "The preset name is not stored: \(json)")
        }

        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"crtScreen"}"#.utf8))
        XCTAssertEqual(bare, .crtScreen(Effect.CRTScreen()), "No params at all is the identity")

        let partial = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"crtScreen","params":{"scanlines":0.5,"preset":"Arcade"}}"#.utf8))
        XCTAssertEqual(partial, .crtScreen(Effect.CRTScreen(scanlines: 0.5)),
                       "One knob written, the rest at their identity, and a preset key ignored")

        // A document written before the case existed names other kinds and decodes exactly as it did.
        let older = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"chromaticAberration","params":{"offsetX":2,"offsetY":0}}"#.utf8))
        XCTAssertEqual(older, .chromaticAberration(Effect.ChromaticAberration(offsetX: 2, offsetY: 0)))
    }

    // MARK: - What the kernels are handed

    /// `params` resolves the knobs once: strengths clamped to the slider, the period floored at 1,
    /// the curvature already `k`, and a non-finite value its identity — so both backends receive the
    /// same numbers whatever a channel evaluates to.
    func testParamsResolveTheKnobsOnceForBothBackends() {
        let p = Effect.crtScreen(Effect.CRTScreen(scanlines: 1.7, scanlinePeriod: 0.2, apertureMask: -3,
                                                  curvature: 1, vignette: 0.25, aberration: -2.5)).params
        XCTAssertEqual(p.scanlines, 1, "Clamped to the slider's top")
        XCTAssertEqual(p.scanlinePeriod, 1, "Floored at one row")
        XCTAssertEqual(p.apertureMask, 0, "Clamped to the slider's bottom")
        XCTAssertEqual(p.curvature, Float(Effect.CRTScreen.maxCurvature), "The kernel is handed k, not the slider")
        XCTAssertEqual(p.vignette, 0.25)
        XCTAssertEqual(p.aberration, -2.5, "Signed, and not clamped")

        let broken = Effect.crtScreen(Effect.CRTScreen(scanlines: .nan, scanlinePeriod: .infinity,
                                                       curvature: .nan, aberration: .nan)).params
        XCTAssertEqual(broken.scanlines, 0); XCTAssertEqual(broken.scanlinePeriod, 1)
        XCTAssertEqual(broken.curvature, 0); XCTAssertEqual(broken.aberration, 0)

        // The screen is one pass, a gather with no weights, and the stub bindings every one-pass
        // effect carries.
        let effect = Effect.crtScreen(Effect.CRTScreen.preset(.arcade))
        XCTAssertEqual(effect.passes.count, 1)
        XCTAssertEqual(effect.kindCode, 14)
        XCTAssertEqual(effect.weights, [1])
        XCTAssertEqual(effect.recolorTable, [RecolorTableEntry()])
        XCTAssertEqual(effect.input, .backdrop, "A screen look over paper is the point")
        XCTAssertTrue(effect.readsAbsolutePosition, "Lines, centre and corners are about the frame")
    }
}

