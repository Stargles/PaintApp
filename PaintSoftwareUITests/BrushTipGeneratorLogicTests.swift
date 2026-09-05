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
        // §2.32: λ is on the randomiser that crosses the gate, not on the output — so the question
        // is whether the density chain carries one at all.
        let lambdas = blotchy.brush.modulations.rows(for: .density)
            .flatMap(\.readInputs).compactMap(\.randomiser?.wavelength)
        XCTAssertFalse(lambdas.isEmpty, "§2.32 — the dropout's randomness is a chain now")
        XCTAssertGreaterThan(lambdas.max() ?? 0, 0,
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

    // MARK: - §12 stage 11's Texture group

    /// **Every Texture nib has to carry one of §8.4's two mechanisms, and this measures *which*.**
    ///
    /// §8.4 names two ways a tip can contribute roughness and they are different mechanisms rather
    /// than degrees of one:
    ///
    /// - a **silhouette** that changes under rotation, measured by the support-function ratio the
    ///   Rough Ink test above uses;
    /// - **interior holes**, which §8.4 exempts from the union argument because *a pit mid-dab is not
    ///   filled by a neighbour's boundary*.
    ///
    /// **Writing this test refuted the brief it was written from.** The expectation was that every
    /// Texture nib would be grossly asymmetric like Rough Ink's triangle. MEASURED, `grunge-crust`
    /// is **1.33** — *below* the 1.35 ceiling `rough-ink-eroded-round` has to stay under to be a
    /// valid control. Its silhouette is very nearly a disc. What makes it grunge is that **42.7%** of
    /// its interior is hole, and `angle.jitter` moves that hole field's phase from dab to dab; it is
    /// `pencil-textured`'s mechanism (support **1.11**, holes 31.4%) at a much wider spacing, not
    /// `rough-ink-triangle`'s (support 1.61, holes **1.4%**).
    ///
    /// So the table below names the mechanism each nib is claimed to work by, and **the last row is
    /// the calibration**: the triangle has to come out the *other* way round on both numbers, or
    /// these two metrics are both measuring "the mask is not a filled square" and neither says
    /// anything.
    func testEveryTextureNibCarriesOneOfTheTwoMechanismsAndTheSheetSaysWhich() throws {
        var support: [String: Double] = [:]
        var holes: [String: Double] = [:]
        for tip in BrushTipGenerator.generateAll() {
            support[tip.name] = Self.supportRatio(of: tip.alpha)
            holes[tip.name] = Self.interiorHoleShare(of: tip.alpha)
        }

        // name, minimum support ratio, minimum interior-hole share, why
        let claims: [(String, Double, Double, String)] = [
            ("grunge-crust", 0, 0.30,
             "a lobed crust whose silhouette is nearly round — it works by its holes"),
            ("chalk-block", 1.40, 0.12,
             "a torn stick: both mechanisms, which is why it is the one nib that also wants paper"),
            ("splatter-drops", 1.40, 0.35,
             "a cluster: the gaps between drops are what make it a spray rather than a blot"),
            ("stipple-specks", 1.40, 0.35,
             "the same, and the gaps are the whole picture")
        ]
        for (name, minimumSupport, minimumHoles, why) in claims {
            let ratio = try XCTUnwrap(support[name])
            let hole = try XCTUnwrap(holes[name])
            XCTAssertGreaterThan(ratio, minimumSupport,
                                 "\(name) support \(String(format: "%.2f", ratio)) — \(why)")
            XCTAssertGreaterThan(hole, minimumHoles,
                                 "\(name) is \(String(format: "%.1f", hole * 100))% interior hole "
                                 + "— \(why). §8.4: a union fills a dimming but not a hole.")
        }

        let triangle = try XCTUnwrap(holes["rough-ink-triangle"])
        XCTAssertLessThan(triangle, 0.05,
                          "CALIBRATION: rough-ink-triangle is \(String(format: "%.1f", triangle * 100))% "
                          + "interior hole. It is supposed to be a solid blob that works by its "
                          + "outline — if the hole metric calls it holed, it is measuring "
                          + "\"the mask is not a filled square\" and the four claims above say nothing.")
        XCTAssertGreaterThan(try XCTUnwrap(support["rough-ink-triangle"]),
                             try XCTUnwrap(support["grunge-crust"]),
                             "CALIBRATION: and the triangle has to be the *more* anisotropic of the "
                             + "two, which is the half of §8.4 grunge does not use")
    }

    /// **§12 stage 11's whole claim, measured on the pixels: the Texture group's wide spacing is
    /// what keeps its holes open.**
    ///
    /// §8.4 says *"anything whose character is in its pixels needs the dabs far enough apart to be
    /// seen one at a time"* and the first sheet's blender died of it. The Texture group is that
    /// finding read the other way: Grunge walks at **0.30**, three times anything else this app
    /// ships, and the contact sheet carries a CONTROL row of the same picture at 0.05 that renders
    /// as a plain black band with a hairy edge.
    ///
    /// So this is that control as an assertion. Same brush, same seed, same path, same picture —
    /// only `spacing` differs, and both the clear share of the stroke's own bounding box and its
    /// mean tone have to move. **The texture is removed from both arms**, because a canvas-anchored
    /// sheet punches holes at any spacing and would make this pass for the wrong reason.
    func testGrungesHolesSurviveAtItsOwnSpacingAndNotAtAShippedOne() throws {
        func measure(spacing: Double) throws -> (clear: Double, mean: Double) {
            var brush = BrushLibrary.grunge
            brush.texture = nil
            brush.dab.spacing = spacing
            let texture = RasterLayerTexture(size: CGSize(width: 420, height: 160))
            let samples = StrokeSamples((0..<70).map {
                VectorSample(point: CGPoint(x: 40 + CGFloat($0) * 5, y: 80), pressure: 0.95)
            }, channels: .pressureOnly)
            BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                     brushSize: brush.size, brushOpacity: brush.opacity,
                                     random: DabRandom(seed: 0x7E_5100))
            let image = try XCTUnwrap(Self.alphaImage(of: texture))
            // The ink's own bounding box, so the two arms are compared over the stroke each of them
            // actually drew rather than over a window guessed from the brush's size.
            var minX = image.width, maxX = -1, minY = image.height, maxY = -1
            for y in 0..<image.height {
                for x in 0..<image.width where image.bytes[y * image.width + x] > 8 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            XCTAssertGreaterThan(maxX, minX, "PREMISE: the stroke inked something")
            var clear = 0, total = 0, sum = 0
            for y in minY...maxY {
                for x in minX...maxX {
                    total += 1
                    let alpha = Int(image.bytes[y * image.width + x])
                    sum += alpha
                    if alpha < 8 { clear += 1 }
                }
            }
            return (Double(clear) / Double(total), Double(sum) / Double(total))
        }

        let wide = try measure(spacing: 0.30)
        let tight = try measure(spacing: 0.05)
        XCTAssertGreaterThan(wide.clear, 0.15,
                             "at its shipped 0.30 the crust leaves only "
                             + "\(String(format: "%.1f", wide.clear * 100))% of its own box clear, "
                             + "which is not a crust")
        XCTAssertGreaterThan(wide.clear, tight.clear * 1.6,
                             "0.30 leaves \(String(format: "%.1f", wide.clear * 100))% clear and "
                             + "0.05 leaves \(String(format: "%.1f", tight.clear * 100))% — §8.4's "
                             + "minimum-spacing finding is what this group is built on, and if the "
                             + "two are close the spacing is not what is doing the work")
        XCTAssertLessThan(wide.mean, tight.mean * 0.75,
                          "the tone has to move as well as the holes: 0.30 means "
                          + "\(String(format: "%.0f", wide.mean)) against 0.05's "
                          + "\(String(format: "%.0f", tight.mean)), out of 255")
    }

    /// **The Chalk A/B on the sheet claims the three rows differ in exactly one field, and this is
    /// what makes that true.**
    ///
    /// The sheet's finding is that Chalk's nib alone draws a dark stroke with a grainy edge and only
    /// becomes chalk through §2.25's canvas-anchored sheet. That is a claim about the *fixtures* —
    /// one row at a different spacing or flow would leave the sheet looking the same and meaning
    /// nothing. CLAUDE.md's *"mutate one fixture cumulatively, so a row's difference is attributable
    /// to the row"*, one level up, exactly as `testTheRoughInkRowsDifferOnlyInTheirPictureAnd…` does.
    func testTheChalkRowsDifferOnlyInTheirPaper() throws {
        let rows = BrushCandidates.all(tips: BrushTipGenerator.generateAll())
            .filter { $0.slot == "Chalk" && $0.name.hasPrefix("Chalk — Block") }
        XCTAssertEqual(rows.count, 4, "PREMISE: the A/B is four rows of one nib")

        let reference = try XCTUnwrap(rows.first).brush
        XCTAssertNil(reference.texture, "PREMISE: the first row is the leg with no paper on it")
        for candidate in rows {
            let brush = candidate.brush
            XCTAssertEqual(brush.tip, reference.tip, candidate.name)
            XCTAssertEqual(brush.size, reference.size, candidate.name)
            XCTAssertEqual(brush.opacity, reference.opacity, candidate.name)
            XCTAssertEqual(brush.dab, reference.dab, candidate.name)
            XCTAssertEqual(brush.stroke, reference.stroke, candidate.name)
            XCTAssertEqual(brush.modulations.rows, reference.modulations.rows, candidate.name)
        }
        XCTAssertEqual(Set(rows.compactMap { $0.brush.texture }).count, 3,
                       "three of the four carry a paper and no two are the same one — the field "
                       + "the sheet says is the only difference has to actually differ")
    }

    /// **And the paper has to reach the ink, not only the model.**
    ///
    /// A `BrushTextureSettings` that resolved to nothing — a mask the bundle does not carry, a depth
    /// quantised to zero — leaves a perfectly well-formed value on the brush and paints the
    /// untextured stroke. `BrushTextureMaskCache` answers nil for a missing sheet and the merge
    /// *skips*, which is the safe direction and therefore the silent one. So: the shipped Chalk and
    /// the same brush with its texture removed are walked over the same path with the same seed, and
    /// the paper has to take a real share of the ink away.
    func testTheShippedChalkActuallyLaysItsInkThroughPaper() throws {
        func inkSum(_ brush: Brush) throws -> Int {
            let texture = RasterLayerTexture(size: CGSize(width: 320, height: 120))
            let samples = StrokeSamples((0..<60).map {
                VectorSample(point: CGPoint(x: 30 + CGFloat($0) * 4, y: 60), pressure: 0.95)
            }, channels: .pressureOnly)
            BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                     brushSize: brush.size, brushOpacity: brush.opacity,
                                     random: DabRandom(seed: 0x7E_5101))
            let image = try XCTUnwrap(Self.alphaImage(of: texture))
            return image.bytes.reduce(0) { $0 + Int($1) }
        }

        let shipped = BrushLibrary.chalk
        XCTAssertNotNil(shipped.texture, "PREMISE: Chalk is the brush that carries a sheet")
        var bare = shipped
        bare.texture = nil

        let withPaper = try inkSum(shipped)
        let withoutPaper = try inkSum(bare)
        XCTAssertGreaterThan(withoutPaper, 0, "PREMISE: the bare nib inks something")
        XCTAssertLessThan(Double(withPaper), Double(withoutPaper) * 0.75,
                          "the paper took \(String(format: "%.0f", (1 - Double(withPaper) / Double(withoutPaper)) * 100))% "
                          + "of the ink away. §2.25's sheet is the whole of what makes this brush "
                          + "chalk rather than a dark stroke with a grainy edge — a merge that "
                          + "skipped would leave these two equal and every model assertion green.")
    }

    /// **And it has to reach the ink on the tier the artist actually draws on.**
    ///
    /// The test above walks `stampStroke` into a `RasterLayerTexture` directly. The app's default
    /// layer is a **vector** one: the pen's ink is a `VectorStroke` carrying a `BrushRef` into
    /// `BrushPool`, re-rendered from that pool on every invalidation. Every link in that chain is a
    /// place a `texture` can be dropped while the model stays perfectly correct — CLAUDE.md's own
    /// *"a correct value drawn in the wrong place"*, and the reason this is a second test rather
    /// than a second assertion in the first.
    func testTheShippedChalkLaysItsInkThroughPaperOnTheVectorTierToo() throws {
        func inkSum(_ brush: Brush) throws -> Int {
            let size = CGSize(width: 320, height: 120)
            let stroke = VectorStroke(brush: brush,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: brush.size, opacity: brush.opacity,
                                      samples: StrokeSamples((0..<60).map {
                                          VectorSample(point: CGPoint(x: 30 + CGFloat($0) * 4, y: 60),
                                                       pressure: 0.95)
                                      }, channels: .pressureOnly))
            let canvas = VectorCanvas(size: size, strokes: [stroke], fills: [])
            let image = canvas.render()
            let cg = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            bytes.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                                          bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                          space: PixelOps.deviceRGBColorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
        }

        let shipped = BrushLibrary.chalk
        var bare = shipped
        bare.texture = nil
        let withPaper = try inkSum(shipped)
        let withoutPaper = try inkSum(bare)
        XCTAssertGreaterThan(withoutPaper, 0, "PREMISE: the bare nib inks something on this tier")
        XCTAssertLessThan(Double(withPaper), Double(withoutPaper) * 0.75,
                          "on the vector tier the paper took "
                          + "\(String(format: "%.0f", (1 - Double(withPaper) / Double(withoutPaper)) * 100))% "
                          + "of the ink away. The artist draws here, and a texture that reaches the "
                          + "raster tier and not this one is a brush that looks right in every test "
                          + "and solid black on the canvas.")
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

    /// **§8.4's *other* operand: how much of the mask's own interior is a hole.**
    ///
    /// Per row, the pixels strictly between the leftmost and rightmost ink that carry no ink at all,
    /// over the width of that span. A solid blob answers ~0 however ragged its outline; a nib whose
    /// grain punches through answers a third or more. The support ratio above cannot see this at all
    /// — `pencil-textured` measures **1.11** on it, which is a disc — and §8.4 is explicit that the
    /// two are different mechanisms rather than degrees of one: an outline is filled in by the next
    /// dab's outline, and a pit mid-dab is not.
    ///
    /// A *hole*, not a dimming, for the reason §8.4's second sheet found: twenty overlapping dabs
    /// turn 0.2 of coverage into 0.92, so the threshold is "no ink" rather than "less ink".
    private static func interiorHoleShare(of alpha: [UInt8]) -> Double {
        let n = BrushTipGenerator.side
        var holes = 0, span = 0
        for y in 0..<n {
            var first = -1, last = -1
            for x in 0..<n where alpha[y * n + x] > 24 {
                if first < 0 { first = x }
                last = x
            }
            guard first >= 0, last > first else { continue }
            span += last - first + 1
            for x in first...last where alpha[y * n + x] < 8 { holes += 1 }
        }
        return span > 0 ? Double(holes) / Double(span) : 0
    }

    /// The same read as `alphaBytes` with the rendered image's own dimensions kept, because
    /// `renderToUIImage` answers at the device's scale and a test that indexed a row by an assumed
    /// width would be reading the wrong pixels while still passing.
    private static func alphaImage(of texture: RasterLayerTexture)
        -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = texture.renderToUIImage().cgImage, let bytes = alphaBytes(of: texture) else {
            return nil
        }
        return (bytes, cg.width, cg.height)
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
