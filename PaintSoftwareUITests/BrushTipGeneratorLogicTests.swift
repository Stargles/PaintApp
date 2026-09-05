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
        let shape = try XCTUnwrap(BrushTipGenerator.shapes.first { $0.name == "square-slab-4to1" })
        var reseeded = shape
        reseeded.seed = shape.seed &+ 1
        let original = BrushTipGenerator.render(shape).alpha
        let moved = BrushTipGenerator.render(reseeded).alpha
        XCTAssertNotEqual(original, moved,
                          "The slab's ragged edges are seeded noise; a different seed must tear it "
                          + "differently, or the seed is decoration and the determinism proves nothing")
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
            XCTAssertGreaterThan(fraction, 0.02,
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

    /// **§8.4's refutation, pinned in the candidate set.** *"The rough ink nib is generated from
    /// modulation on a clean round tip and needs no tip texture at all."* Three candidates are built
    /// on that, and if a later pass quietly gives one of them a picture this goes red and whoever did
    /// it has to argue with the measurement instead of with a reviewer.
    func testTheRoughInkCandidatesCarryNoTipTextureAtAll() {
        let candidates = BrushCandidates.all(tips: BrushTipGenerator.generateAll())
        let rough = candidates.filter { $0.name.hasPrefix("Rough Ink") }
        XCTAssertEqual(rough.count, 3, "PREMISE: the sheet shows three of them")
        for candidate in rough {
            XCTAssertEqual(candidate.brush.tip, .round,
                           "\(candidate.name): §8.4 MEASURED an eroded tip at 0.41% of a brush "
                           + "width against 3.6% for `random → size`. The nib is dynamics.")
            XCTAssertTrue(candidate.brush.modulations.drives(.density),
                          "\(candidate.name): §2.18's dropout is what makes it rough")
            XCTAssertGreaterThan(candidate.brush.dab.densityWavelength, 0,
                                 "\(candidate.name): §2.17 — λ is what separates a stipple from a "
                                 + "segmented line")
        }
    }

    /// **The rough nib does something, and it does it at the pressure §2.19 says.**
    ///
    /// The assertion is on *dabs laid down*, not on a stored `density`, because a `density` that
    /// resolves correctly and a walk that never consults it look identical from the model. The two
    /// strokes are the same geometry and the same seed and differ only in pressure, so the drop is
    /// attributable.
    func testARoughInkCandidateDropsDabsAtLowPressureAndNoneAtFull() throws {
        let candidates = BrushCandidates.all(tips: BrushTipGenerator.generateAll())
        let brush = try XCTUnwrap(candidates.first { $0.name == "Rough Ink — Dry" }?.brush)

        func dabs(atPressure pressure: CGFloat) -> Int {
            let samples = StrokeSamples((0..<80).map {
                VectorSample(point: CGPoint(x: 20 + CGFloat($0) * 6, y: 100), pressure: pressure)
            }, channels: .pressureOnly)
            let sink = BrushStamper.CollectingDabTarget()
            BrushStamper.stampStroke(into: sink, samples: samples, brush: brush, color: .black,
                                     brushSize: 12, brushOpacity: 1, random: DabRandom(seed: 4242))
            return sink.dabs.count
        }

        let full = dabs(atPressure: 1)
        let light = dabs(atPressure: 0.12)
        XCTAssertGreaterThan(full, 50, "PREMISE: a full-pressure stroke of this length lays dabs")
        XCTAssertEqual(full, dabs(atPressure: 0.9),
                       "§2.19: density holds flat above about a third of full pressure, so a firm "
                       + "stroke keeps its taper solid")
        XCTAssertLessThan(light, full * 3 / 4,
                          "§2.18: a stroke drawn genuinely light breaks up along its whole length")
        XCTAssertGreaterThan(light, 0, "…and does not vanish")
    }

    // MARK: - Helpers

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
