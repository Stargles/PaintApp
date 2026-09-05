import XCTest
import UIKit
import CoreGraphics

/// **BRUSH.md §12 stage 9 — what has to be true of a generated tip before its bytes are committed.**
///
/// Two claims carry the whole feature and neither is provable by reading the generator.
///
/// **Determinism**, because §12 stage 9 rules the generator is a *build-time tool whose output is
/// committed*. A committed PNG is only trustworthy if it can be shown to be the one this source
/// draws; a generator with a clock, a `Double.random` or a dictionary iteration order in it makes
/// every committed byte unfalsifiable. So: generate twice, compare every byte.
///
/// **A discriminating silhouette**, because §12 stage 5 already recorded this exact trap in this
/// repo — *"a tip that fills its mask is indistinguishable from the committed square, so an
/// assertion built on that arm alone would be green against a stamper that ignored the tip"*. A
/// generated tip that filled its mask would draw identical pixels to `.builtIn(.square)` and every
/// row of the contact sheet would be a lie the owner rules from. So each one is **stamped** against
/// the committed square and the pixels are required to differ.
///
/// The third group is smaller and just as load-bearing: the candidate set has to actually *reach*
/// the tips. `BrushCandidates` resolves a tip by name and falls back to `.round` when the name does
/// not match — which is a silent failure that renders a plausible sheet showing the wrong brushes.
final class BrushTipGeneratorLogicTests: XCTestCase {

    /// Where `BrushStorage.shared` pointed before this class ran. **Restored in `tearDown`**, which
    /// is CLAUDE.md's rule about a process-wide static reached through a new door: these tests write
    /// thirteen PNGs, and leaving them in the app's own library would change what
    /// `BrushStorage.fileNames()` answers for every suite that runs after this one in the same
    /// process.
    private var originalRoot: URL!
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalRoot = BrushStorage.shared.root
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tipgen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        BrushStorage.shared.relocate(to: scratch)
    }

    override func tearDownWithError() throws {
        BrushStorage.shared.relocate(to: originalRoot)
        try? FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    // MARK: - Determinism, which is what makes committing the output safe

    /// **Generate the whole catalogue twice and compare every byte.**
    ///
    /// Both halves are asserted deliberately. The **alpha buffer** is the generator's real output and
    /// the claim this file makes about it — nothing in the drawing path reads a clock, an address, an
    /// uninitialised byte or an unordered collection. The **PNG** is that buffer through ImageIO,
    /// which is the one component here nobody in this repo controls; asserting on it too is what
    /// turns "a PNG encoder that stamped a timestamp" from a mystery into a red line.
    func testGeneratingTwiceProducesByteIdenticalOutput() {
        let first = BrushTipGenerator.generateAll()
        let second = BrushTipGenerator.generateAll()

        XCTAssertEqual(first.count, BrushTipGenerator.shapes.count)
        XCTAssertEqual(first.map(\.name), second.map(\.name),
                       "The catalogue is an array, not a dictionary, so its order is a property of "
                       + "the source rather than of a hash seed")
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.alpha, b.alpha, "\(a.name): the coverage buffer must be reproducible")
            XCTAssertEqual(a.png, b.png, "\(a.name): and so must the encoded file")
        }
    }

    /// The seed is what the determinism rests on, so a tip drawn from a different one has to differ.
    /// Without this, `testGeneratingTwiceProducesByteIdenticalOutput` would pass just as happily
    /// against a generator that ignored its seed entirely and drew the same picture every time —
    /// CLAUDE.md's *"an assertion can be true of mathematics rather than of your code"*.
    func testTheSeedIsReadAtAllSoDeterminismIsNotJustAConstantPicture() throws {
        let shape = try XCTUnwrap(BrushTipGenerator.shapes.first { $0.name == "rough-ink-triangle" })
        var reseeded = shape
        reseeded.seed = shape.seed &+ 1
        let original = BrushTipGenerator.render(shape).alpha
        let moved = BrushTipGenerator.render(reseeded).alpha
        XCTAssertNotEqual(original, moved,
                          "The triangle's three edges are displaced by seeded noise; a different "
                          + "seed must tear them differently, or the seed is decoration and the "
                          + "determinism proves nothing")
    }

    // MARK: - The mask itself

    /// Every tip is a mask in the sense `BuiltInBrushTexture.square`'s own description defines: 256²,
    /// a 2 px clear border to antialias into, something drawn inside it, and not everything.
    ///
    /// **The upper bound is the one that matters.** A tip that filled its mask would be the committed
    /// square, and §12 stage 5 is a note about exactly that arm being green for the wrong reason.
    func testEveryGeneratedTipIsABorderedMaskThatIsNeitherBlankNorFull() {
        let n = BrushTipGenerator.side
        for tip in BrushTipGenerator.generateAll() {
            XCTAssertEqual(tip.alpha.count, n * n, tip.name)

            for x in 0..<n {
                XCTAssertEqual(tip.alpha[x], 0, "\(tip.name): the top row is inside the border")
                XCTAssertEqual(tip.alpha[(n - 1) * n + x], 0, "\(tip.name): and the bottom")
                XCTAssertEqual(tip.alpha[x * n], 0, "\(tip.name): and the left column")
                XCTAssertEqual(tip.alpha[x * n + n - 1], 0, "\(tip.name): and the right")
            }

            let inked = tip.alpha.reduce(into: 0) { $0 += $1 > 8 ? 1 : 0 }
            let fraction = Double(inked) / Double(n * n)
            // **The floor was 0.02 and is 0.01, re-derived at round three rather than relaxed to get
            // green.** The owner asked for Streaky's dots at *"at least half the radius"*, and six
            // discs at a quarter of their old area is a sparse mask by construction: MEASURED at
            // 0.0165 of the tip, against 0.0525 before. So 0.02 was a floor on the old radius and
            // not on emptiness. 0.01 still catches what this assertion is for — a shape that
            // silently draws nothing — because the emptiest legitimate mask on the sheet is now
            // 1.65× it, and a genuinely blank one is zero rather than marginal.
            XCTAssertGreaterThan(fraction, 0.01,
                                 "\(tip.name) draws almost nothing — `BrushTipImport.Failure"
                                 + ".blankMask` is the shape of this failure and it looks exactly "
                                 + "like a broken renderer")
            XCTAssertLessThan(fraction, 0.92,
                              "\(tip.name) all but fills its mask, which makes it the committed "
                              + "square with extra steps — §12 stage 5's own trap")
        }
    }

    /// No two tips are the same picture. Cheap, and it catches the one generator bug that a per-tip
    /// assertion cannot: two catalogue entries that collapse onto one drawing because a parameter
    /// was copied and not edited.
    func testTheGeneratedTipsAreAllDifferentPictures() {
        let tips = BrushTipGenerator.generateAll()
        for i in 0..<tips.count {
            for j in (i + 1)..<tips.count {
                XCTAssertNotEqual(tips[i].alpha, tips[j].alpha,
                                  "\(tips[i].name) and \(tips[j].name) are the same mask")
            }
        }
    }

    // MARK: - The discriminating operand: it has to stamp differently

    /// **§12 stage 5's named test, one level up.** Each generated tip is stamped through the real
    /// `stampImage` primitive beside the committed square at the same size and angle, and the two
    /// have to disagree over a real share of the dab.
    ///
    /// Asserting on the *mask* is not enough and that is the whole point of this being here: a mask
    /// can be perfectly discriminating and still never reach the canvas — a mis-written file, a
    /// negative cache entry held from an earlier ask, a ref that resolved to the wrong name. The
    /// pixels are the only operand that answers all of those at once.
    func testEveryGeneratedTipStampsDifferentPixelsFromTheCommittedSquare() throws {
        let tips = BrushTipGenerator.writeAll()
        let side = 160
        let diameter: CGFloat = 120
        let centre = CGPoint(x: 80, y: 80)

        let square = RasterLayerTexture(size: CGSize(width: side, height: side))
        square.stampImage(.builtIn(.square), at: centre, diameter: diameter, angle: 0,
                          color: .black, alpha: 1, blendMode: .normal)
        let reference = try XCTUnwrap(Self.alphaBytes(of: square))
        XCTAssertGreaterThan(reference.reduce(0) { $0 + Int($1) }, 0,
                             "PREMISE: the committed square inks something. If it does not, every "
                             + "comparison below is transparent against transparent — the failure "
                             + "that reads as success.")

        for tip in tips {
            let texture = RasterLayerTexture(size: CGSize(width: side, height: side))
            texture.stampImage(tip.textureRef, at: centre, diameter: diameter, angle: 0,
                               color: .black, alpha: 1, blendMode: .normal)
            let drawn = try XCTUnwrap(Self.alphaBytes(of: texture))

            XCTAssertGreaterThan(drawn.reduce(0) { $0 + Int($1) }, 0,
                                 "\(tip.name) stamped nothing at all — the mask did not resolve")

            var differing = 0
            for i in 0..<drawn.count where abs(Int(drawn[i]) - Int(reference[i])) > 32 {
                differing += 1
            }
            let share = Double(differing) / Double(diameter * diameter)
            XCTAssertGreaterThan(share, 0.05,
                                 "\(tip.name) stamps within \(String(format: "%.1f", share * 100))% "
                                 + "of the committed square. A tip that fills its mask is "
                                 + "indistinguishable from it, and a sheet built on one is a "
                                 + "picture of the wrong brush.")
        }
    }

    // MARK: - The candidate set has to reach the tips

    /// **The silent failure `BrushCandidates` can have.** It resolves a tip by name and falls back
    /// to `.round` when the name misses, so a typo does not crash, does not warn, and renders a
    /// perfectly plausible contact sheet in which several rows are secretly the same round brush.
    ///
    /// So: every candidate marked `.generatedTip` must carry a `.stamp` tip, that tip's file must be
    /// in the library, and `BrushTextureStore` must actually hand back a mask for it.
    func testEveryGeneratedTipCandidateResolvesToARealMaskRatherThanFallingBackToTheRoundTip() throws {
        let tips = BrushTipGenerator.writeAll()
        let candidates = BrushCandidates.all(tips: tips)
        let named = candidates.filter { $0.kind.tipName != nil }
        XCTAssertGreaterThanOrEqual(named.count, 8, "PREMISE: the sheet shows generated tips at all")

        for candidate in named {
            let name = try XCTUnwrap(candidate.kind.tipName)
            guard case .stamp(let ref) = candidate.brush.tip else {
                return XCTFail("\(candidate.name) is marked as a generated tip and carries "
                               + "\(candidate.brush.tip) — the name '\(name)' did not resolve")
            }
            XCTAssertEqual(ref, .imported(fileName: "gen-\(name).png"), candidate.name)
            XCTAssertNotNil(BrushTextureStore.mask(for: ref),
                            "\(candidate.name): '\(name)' names no readable file in the library")
        }
    }

    /// **§8.4's refutation is still on the sheet, and it is still tipless.** *"The rough ink nib is
    /// generated from modulation on a clean round tip and needs no tip texture at all."* Round two
    /// keeps exactly one candidate built that way — the one the owner chose, Rough Ink Blotchy — and
    /// if a later pass quietly gives it a picture this goes red and whoever did it has to argue with
    /// the measurement instead of with a reviewer.
    ///
    /// **What round two adds beside it is not a contradiction of that.** §8.4's boundary paragraph
    /// rules that an *asymmetric* nib under rotation is a second mechanism, not the refuted one; the
    /// tests below are what hold that claim to its two operands.
    func testTheChosenRoughInkBlotchyStillCarriesNoTipTextureAtAll() throws {
        let candidates = BrushCandidates.all(tips: BrushTipGenerator.generateAll())
        let blotchy = try XCTUnwrap(candidates.first { $0.name == "Rough Ink — Blotchy" })
        XCTAssertEqual(blotchy.standing, .chosen, "PREMISE: the owner picked this one")
        XCTAssertEqual(blotchy.brush.tip, .round,
                       "§8.4 MEASURED an eroded tip at 0.41% of a brush width against 3.6% for "
                       + "`random → size`. This nib is dynamics.")
        XCTAssertTrue(blotchy.brush.modulations.drives(.density),
                      "§2.18's dropout is what makes it rough")
        XCTAssertGreaterThan(blotchy.brush.dab.densityWavelength, 0,
                             "§2.17 — λ is what separates a stipple from a segmented line")
    }

    /// **The Rough Ink family is a factorial on §8.4's two terms, and this is what makes it one.**
    ///
    /// The sheet's claim is that the five tipped rows differ *only* in their picture and their
    /// rotation jitter, so a difference the owner sees between two of them is attributable to one of
    /// those two things. That claim is about the fixtures rather than about the engine, and a
    /// fixture that quietly drifted — one row at a different size, another at a different spacing —
    /// would leave the sheet looking exactly the same and meaning nothing. CLAUDE.md's own
    /// *"mutate one fixture cumulatively, so a row's difference is attributable to the row"*, one
    /// level up.
    func testTheRoughInkRowsDifferOnlyInTheirPictureAndTheirRotation() throws {
        let all = BrushCandidates.all(tips: BrushTipGenerator.generateAll())
        let rough = all.filter { BrushCandidates.roughInkFactorial.contains($0.name) }
        XCTAssertEqual(rough.count, BrushCandidates.roughInkFactorial.count,
                       "PREMISE: every name in the factorial list is on the sheet")
        XCTAssertEqual(rough.count, 5, "PREMISE: the factorial has five cells")
        XCTAssertGreaterThan(all.filter { $0.slot == "Rough Ink" }.count, rough.count,
                             "PREMISE: the slot carries more than the factorial — the combined row "
                             + "is why this test filters by name rather than by slot")

        let reference = try XCTUnwrap(rough.first).brush
        for candidate in rough {
            let brush = candidate.brush
            XCTAssertEqual(brush.size, reference.size, candidate.name)
            XCTAssertEqual(brush.opacity, reference.opacity, candidate.name)
            XCTAssertEqual(brush.dab.size, reference.dab.size, candidate.name)
            XCTAssertEqual(brush.dab.flow, reference.dab.flow, candidate.name)
            XCTAssertEqual(brush.dab.spacing, reference.dab.spacing, candidate.name)
            XCTAssertEqual(brush.dab.density, 1,
                           "\(candidate.name): §2.18's dropout is deliberately off on these rows — "
                           + "with it on, the sheet could not say whether the picture or the "
                           + "dropout did the roughening")
            XCTAssertEqual(brush.dab.angle.base, 0, candidate.name)
            XCTAssertEqual(brush.dab.angle.directionFollow, 0,
                           "\(candidate.name): §8.6 asks for *isotropic* randomisation, which a "
                           + "direction-follow would replace with a fixed relationship to travel")
            XCTAssertEqual(brush.modulations.rows, reference.modulations.rows, candidate.name)
            guard case .stamp = brush.tip else {
                return XCTFail("\(candidate.name) carries \(brush.tip): the tipped rows are the "
                               + "whole point of this family")
            }
        }

        // The two halves of the A/B are one picture at two jitters, which is the cell structure the
        // sheet's CONTROL pill claims.
        let turned = try XCTUnwrap(rough.first { $0.name == "Rough Ink — Triangle" })
        let held = try XCTUnwrap(rough.first { $0.name == "Rough Ink — Triangle, No Turn" })
        XCTAssertEqual(turned.brush.tip, held.brush.tip, "the same picture in both cells")
        XCTAssertGreaterThan(turned.brush.dab.angle.jitter, 0.5)
        XCTAssertLessThan(held.brush.dab.angle.jitter, 0.05)
        XCTAssertEqual(held.standing, .control)
    }

    /// **And the A/B has to reach the ink, not only the model.**
    ///
    /// A jitter that resolved correctly and a stamper that never turned the mask look identical from
    /// the value. So both rows are walked through the real `BrushStamper` over the same geometry
    /// with the same seed, and the dabs' angles are required to disagree — CLAUDE.md's *"assert what
    /// is drawn, not only what is stored"*.
    func testTheStamperActuallyTurnsTheMaskSoTheJitterAbIsARealAb() throws {
        let rough = BrushCandidates.all(tips: BrushTipGenerator.generateAll())
            .filter { BrushCandidates.roughInkFactorial.contains($0.name) }
        let turned = try XCTUnwrap(rough.first { $0.name == "Rough Ink — Triangle" }?.brush)
        let held = try XCTUnwrap(rough.first { $0.name == "Rough Ink — Triangle, No Turn" }?.brush)

        func angles(_ brush: Brush) -> [CGFloat] {
            let samples = StrokeSamples((0..<60).map {
                VectorSample(point: CGPoint(x: 20 + CGFloat($0) * 5, y: 100), pressure: 0.8)
            }, channels: .pressureOnly)
            let sink = BrushStamper.CollectingDabTarget()
            BrushStamper.stampStroke(into: sink, samples: samples, brush: brush, color: .black,
                                     brushSize: 12, brushOpacity: 1, random: DabRandom(seed: 99))
            return sink.dabs.compactMap { dab in
                if case .image(_, let angle) = dab.tip { return angle }
                return nil
            }
        }

        let turnedAngles = angles(turned)
        let heldAngles = angles(held)
        XCTAssertGreaterThan(turnedAngles.count, 30,
                             "PREMISE: both walks lay image dabs at all")
        XCTAssertEqual(turnedAngles.count, heldAngles.count,
                       "the two rows are the same geometry at the same spacing")

        let turnedSpread = (turnedAngles.max() ?? 0) - (turnedAngles.min() ?? 0)
        let heldSpread = (heldAngles.max() ?? 0) - (heldAngles.min() ?? 0)
        XCTAssertGreaterThan(turnedSpread, .pi,
                             "jitter 1 is ±half a turn: the dabs must span most of a circle")
        XCTAssertLessThan(heldSpread, 0.4,
                          "jitter 0.03 is ±5°: the control's dabs must all but agree, or it is not "
                          + "a control")
    }

    /// **The asymmetry operand, measured on the pictures rather than asserted about them.**
    ///
    /// §8.4's boundary paragraph turns on one distinction: *"rotating an uneven shape changes its
    /// outline while rotating a disc changes nothing at all."* The measurable form of "uneven" here
    /// is the **support function** — the farthest the mask reaches in each direction. A disc's is
    /// flat whatever noise its edge carries; a triangle's swings between its inradius and its
    /// circumradius.
    ///
    /// So the three named candidates must be grossly anisotropic and `rough-ink-eroded-round` — the
    /// nib §8.4 measured and refuted — must not be. **If this went red on the control, the sheet's
    /// factorial would have no empty cell and the whole family would be one mechanism.**
    func testTheRoughInkContendersAreGrosslyAsymmetricAndTheControlIsNot() throws {
        var ratios: [String: Double] = [:]
        for tip in BrushTipGenerator.generateAll() where tip.name.hasPrefix("rough-ink-") {
            ratios[tip.name] = Self.supportRatio(of: tip.alpha)
        }
        XCTAssertEqual(ratios.count, 4, "PREMISE: four rough ink masks are drawn")

        for name in ["rough-ink-triangle", "rough-ink-square", "rough-ink-halfflat"] {
            let ratio = try XCTUnwrap(ratios[name])
            XCTAssertGreaterThan(ratio, 1.5,
                                 "\(name) reaches only \(String(format: "%.2f", ratio))× as far in "
                                 + "its longest direction as in its shortest. §8.4's boundary "
                                 + "paragraph needs an uneven silhouette for the rotation to have "
                                 + "anything to turn.")
        }
        let control = try XCTUnwrap(ratios["rough-ink-eroded-round"])
        XCTAssertLessThan(control, 1.35,
                          "rough-ink-eroded-round is the CONTROL — §8.4's own refuted nib. At "
                          + "\(String(format: "%.2f", control))× it is no longer a disc with a "
                          + "noisy edge, and the sheet's factorial has lost the cell that is "
                          + "supposed to fail.")
    }

    /// **§8.6's Messy Flat says *the ends*, and this is the pin that it is the ends.**
    ///
    /// *"Still square, but the sprite gives it a unique non monolithic look for the ends."* §8.4's
    /// fourth finding is the reason: with `base 0.25` and `directionFollow 1` the nib's long sides
    /// sweep *along* the travel and never reach the silhouette, so roughness authored there is
    /// invisible by construction and roughness authored at the ends is the only kind that can be
    /// seen. A generator that roughened all four edges would draw a plausible mask and waste every
    /// pixel of it.
    ///
    /// Measured as the wander of each boundary: the top edge's row varies by less than a pixel or
    /// two across the nib, and the left end's column wanders by many.
    func testMessyFlatRoughensItsEndsAndLeavesItsLongSidesStraight() throws {
        let tip = try XCTUnwrap(BrushTipGenerator.generateAll()
            .first { $0.name == "flat-messy-ends" })
        let n = BrushTipGenerator.side
        let inked: (Int, Int) -> Bool = { x, y in tip.alpha[y * n + x] > 24 }

        var topRows: [Int] = []
        for x in stride(from: n / 2 - 90, through: n / 2 + 90, by: 3) {
            if let y = (0..<n).first(where: { inked(x, $0) }) { topRows.append(y) }
        }
        var leftColumns: [Int] = []
        for y in stride(from: n / 2 - 24, through: n / 2 + 24, by: 2) {
            if let x = (0..<n).first(where: { inked($0, y) }) { leftColumns.append(x) }
        }
        XCTAssertGreaterThan(topRows.count, 40, "PREMISE: the nib has a long top edge")
        XCTAssertGreaterThan(leftColumns.count, 15, "PREMISE: and a left end")

        let sideWander = (topRows.max() ?? 0) - (topRows.min() ?? 0)
        let endWander = (leftColumns.max() ?? 0) - (leftColumns.min() ?? 0)
        XCTAssertLessThan(sideWander, 4,
                          "the long side wanders \(sideWander) px — it is supposed to be straight, "
                          + "and §8.4 says roughness there reaches no silhouette anyway")
        XCTAssertGreaterThan(endWander, 8,
                             "the end wanders only \(endWander) px, which is not \"messier ends\"")
        XCTAssertGreaterThan(endWander, sideWander * 3,
                             "the whole design is that the ends are rough *relative to* the sides")
    }

    // MARK: - Helpers

    /// **The support function's extremes, as a ratio.** For each of 180 directions, how far the
    /// mask's ink reaches from the mask's centre; the answer is `max / min` over those directions.
    ///
    /// A disc answers ~1 however noisy its edge is, because a radial displacement of ±11% moves
    /// every direction by the same amount. An equilateral triangle answers ~2, because its
    /// circumradius is twice its inradius. That is exactly the distinction §8.4's boundary
    /// paragraph rests on, and it is the reason this is a support function rather than, say, a
    /// rotated-difference count: a rotated *noisy disc* differs from itself in a large share of its
    /// pixels while still being, in the sense that matters to a stroke's silhouette, a disc.
    private static func supportRatio(of alpha: [UInt8]) -> Double {
        let n = BrushTipGenerator.side
        let centre = Double(n / 2)
        var points: [(Double, Double)] = []
        for y in 0..<n {
            for x in 0..<n where alpha[y * n + x] > 24 {
                points.append((Double(x) + 0.5 - centre, Double(y) + 0.5 - centre))
            }
        }
        guard points.count > 64 else { return 1 }
        var lowest = Double.greatestFiniteMagnitude
        var highest = 0.0
        for step in 0..<180 {
            let angle = Double(step) * .pi / 90
            let dx = cos(angle), dy = sin(angle)
            var reach = -Double.greatestFiniteMagnitude
            for point in points { reach = max(reach, point.0 * dx + point.1 * dy) }
            lowest = min(lowest, reach)
            highest = max(highest, reach)
        }
        return lowest > 1 ? highest / lowest : Double.greatestFiniteMagnitude
    }

    private static func alphaBytes(of texture: RasterLayerTexture) -> [UInt8]? {
        guard let cg = texture.renderToUIImage().cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    }
}
