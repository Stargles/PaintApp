import XCTest

/// **BRUSH.md §2.25 — the canvas-anchored brush texture**, which reverses §2.4's deletion of grain
/// in a different place and by a different mechanism.
///
/// The owner: *"its a texture that gets applied over your brush ... Texture is applied relative to
/// canvas, and uses the untextured brush as a transparency mask, then is scaled with opacity."*
///
/// Four claims are worth pinning and they are not equally easy to pin.
///
/// 1. *A textured stroke differs from an untextured one.* Nearly free, and nearly worthless on its
///    own — it is green against a stroke-anchored implementation, a per-dab one, and a bug that
///    tints the whole canvas.
/// 2. *It differs **in the ink only**.* The second operand for (1), and the one that says the
///    texture is masked by the stroke rather than painted beside it.
/// 3. **The anchoring**, which is the claim the feature exists for and the only one a wrong
///    implementation fails. The same stroke drawn at two canvas positions must sample **different**
///    texture, and — the operand that makes that mean something — the same stroke drawn twice at the
///    same position must sample the *same*. A stroke-anchored texture passes (1) and (2) and fails
///    exactly this, so it is where the discrimination lives. CLAUDE.md's *"a green assertion is only
///    as good as its two operands"* is about precisely this shape.
/// 4. **That the two tiers agree.** The live scratch accumulates a stroke in a window whose origin
///    moves as the pen travels, and the replay accumulates it in the cel. A texture anchored to
///    either buffer instead of to the canvas would look right in isolation on both and disagree
///    between them, which is the defect an artist sees as ink changing at pen-up.
@MainActor
final class BrushTextureLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brush-texture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    override func tearDown() {
        // The mask cache is process-wide and holds a *negative* entry for a file that was missing,
        // so a suite that wrote one file and then read another under a name it had already probed
        // would be served the earlier answer. Every fixture here mints a fresh file name, and this
        // is the belt to that's braces — CLAUDE.md has a section on a static outliving its test.
        BrushTextureMaskCache.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// The canvas every render in this file happens on. Big enough to hold a stroke and its
    /// translated twin with clear margin, small enough that a byte-for-byte compare is instant.
    private static let canvas = CGSize(width: 192, height: 192)

    /// **A 64×64 checkerboard alpha mask**, written fresh under `BrushLibrary.customBrushesDirectory`
    /// so no two tests can be served one another's pixels.
    ///
    /// A checker rather than a smooth grain, and hard 0/255 rather than a gradient, because every
    /// assertion below is about *where* a texel landed: a soft field would let a stroke-anchored
    /// implementation pass the anchoring test on a lucky offset, and a low-contrast one would make
    /// "differs" a question about tolerance. `cell` is the mask's own pixel size of one square; with
    /// `tileSize` equal to the mask's side, one square is `cell` canvas points.
    ///
    /// It goes in as an **already-alpha** PNG rather than through `BrushTipImport`: the import's
    /// letterbox and 2 px transparent border are right for a *tip* and wrong for a sheet that has to
    /// tile — a border would carve a grid of seams out of every stroke.
    private static func writeTestTexture(cell: Int = 16, side: Int = 64) throws -> BrushTextureRef {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(UIColor.black.cgColor)
        for row in 0..<(side / cell) {
            for column in 0..<(side / cell) where (row + column) % 2 == 0 {
                ctx.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
            }
        }
        let data = try XCTUnwrap(UIImage(cgImage: try XCTUnwrap(ctx.makeImage())).pngData())
        let fileName = "test-texture-\(UUID().uuidString).png"
        try data.write(to: BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName))
        return .imported(fileName: fileName)
    }

    /// A brush that lays solid, full-coverage ink at any pressure, so every difference a test below
    /// measures is the texture's and not the matrix's. `texture` nil is the untextured control.
    private static func brush(_ texture: BrushTextureSettings?) -> Brush {
        Brush(name: "texture fixture", tip: .round, size: 12,
              // Bases at 1 with no rows: a preset's own `1 - amount` bases would stamp a 60% dab and
              // make every comparison here a comparison of two faint things.
              dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.08, hardness: 1),
              modulations: BrushModulations(),
              texture: texture)
    }

    /// A horizontal stroke of `length` points starting at `origin`, three samples at full pressure.
    private static func samples(from origin: CGPoint, length: CGFloat = 96) -> StrokeSamples {
        StrokeSamples(points: [origin,
                               CGPoint(x: origin.x + length / 2, y: origin.y),
                               CGPoint(x: origin.x + length, y: origin.y)])
    }

    // MARK: - The three tiers, each rendering one stroke

    /// **The vector replay tier**, which is what `VectorLayer.stamp(stroke:into:isEraser:)` runs.
    private static func replayTier(_ brush: Brush, at origin: CGPoint, opacity: Double = 1,
                                   isEraser: Bool = false, over base: UIImage? = nil) -> RasterLayerTexture {
        let texture = RasterLayerTexture(size: canvas, image: base)
        BrushStamper.stampStroke(into: texture, samples: samples(from: origin), brush: brush,
                                 color: .black, brushSize: brush.size, brushOpacity: opacity,
                                 isEraser: isEraser, random: DabRandom(seed: 0x51A7))
        return texture
    }

    /// **The render-local tier**, `VectorCanvas.renderLocalContent`'s own `CGContextDabTarget` into a
    /// `UIGraphicsImageRenderer` context — a second buffer kind, so a texture that had been anchored
    /// to `RasterLayerTexture`'s bitmap rather than to the canvas would part company here.
    private static func renderLocalTier(_ brush: Brush, at origin: CGPoint, opacity: Double = 1) -> UIImage {
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let target = CGContextDabTarget(ctx.cgContext)
            BrushStamper.stampStroke(into: target, samples: samples(from: origin), brush: brush,
                                     color: .black, brushSize: brush.size, brushOpacity: opacity,
                                     random: DabRandom(seed: 0x51A7))
        }
    }

    /// **The live tier**, driven the way `StrokeCanvasView.stampPath` drives it: dabs straight into
    /// the scratch with **no group open at all**, and the merge is `commit`. That is not a detail —
    /// it is why `StrokeScratch` has to carry the texture itself, and why this tier can disagree with
    /// the other two if the window's own origin is not accounted for.
    private static func liveTier(_ brush: Brush, at origin: CGPoint, opacity: Double = 1,
                                 role: StrokeScratch.Role = .additive,
                                 into cel: RasterLayerTexture? = nil) -> RasterLayerTexture {
        let target = cel ?? RasterLayerTexture(size: canvas)
        let scratch = StrokeScratch(canvasSize: canvas, role: role, opacity: CGFloat(opacity),
                                    texture: brush.texture)
        let walk = samples(from: origin)
        let path = StrokePath(points: walk.positions)
        let sensors = StrokeSensors(samples: walk, path: path, random: DabRandom(seed: 0x51A7),
                                    brushSize: brush.size)
        var arcWidths: CGFloat = 0
        var resolved = brush.dabValues { sensors.value(of: $0, at: DabSite(parameter: 0, arcWidths: 0)) }
        BrushStamper.stampDab(into: scratch, at: walk.positions[0], brush: brush, values: resolved,
                              color: .black, brushSize: brush.size,
                              random: DabRandom(seed: 0x51A7), arcWidths: 0)
        var carry = WalkCarry(
            spacing: BrushStamper.stampSpacing(brushSize: brush.size, fraction: resolved.spacing))
        for index in 0..<max(walk.count - 1, 0) {
            carry = path.advance(segment: index, carry: carry) { dab, u, walked in
                arcWidths += walked / brush.size
                let site = DabSite(parameter: CGFloat(index) + u, arcWidths: arcWidths)
                resolved = brush.dabValues { sensors.value(of: $0, at: site) }
                BrushStamper.stampDab(into: scratch, at: dab, brush: brush, values: resolved,
                                      color: .black, brushSize: brush.size,
                                      random: DabRandom(seed: 0x51A7), arcWidths: arcWidths)
                return BrushStamper.stampSpacing(brushSize: brush.size, fraction: resolved.spacing)
            }
        }
        scratch.commit(into: target)
        return target
    }

    // MARK: - Reading pixels

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        func alpha(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4 + 3]) }
        var isBlank: Bool { !stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 } }
        /// The bytes of one rectangle, so two strokes at different canvas positions can be compared
        /// as *pictures of a stroke* rather than as pictures of a canvas.
        func crop(_ rect: CGRect) -> [UInt8] {
            var out: [UInt8] = []
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    out.append(contentsOf: bytes[(y * width + x) * 4..<((y * width + x) * 4 + 4)])
                }
            }
            return out
        }
    }

    private static func pixels(_ image: UIImage) throws -> Pixels {
        let cg = try XCTUnwrap(image.cgImage)
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
        XCTAssertTrue(ok, "the read-back context could not be built")
        return Pixels(bytes: bytes, width: width, height: height)
    }

    private static func pixels(_ texture: RasterLayerTexture) throws -> Pixels {
        try pixels(texture.renderToUIImage())
    }

    // MARK: - 1. A textured stroke differs, and only where the ink is

    /// **Both operands, and neither alone is worth having.** "The pixels changed" is green against an
    /// implementation that tints the whole canvas or draws the paper as a rectangle over the ink;
    /// "nothing outside changed" is green against one that does nothing at all. Together they say the
    /// texture is multiplied *into* the stroke — which is exactly the owner's *"uses the untextured
    /// brush as a transparency mask"* — and nothing else.
    func testATexturedStrokeDiffersFromAnUntexturedOneAndOnlyWhereTheInkIs() throws {
        let sheet = try Self.writeTestTexture()
        let origin = CGPoint(x: 48, y: 96)
        let plain = try Self.pixels(Self.replayTier(Self.brush(nil), at: origin))
        let textured = try Self.pixels(
            Self.replayTier(Self.brush(BrushTextureSettings(mask: sheet, tileSize: 64)), at: origin))

        XCTAssertFalse(plain.isBlank, "fixture precondition: the untextured stroke drew something")
        XCTAssertFalse(textured.isBlank,
                       "a textured stroke still draws — the texture masks the ink, it does not delete it")

        var differing = 0, outsideTheInk = 0
        for y in 0..<plain.height {
            for x in 0..<plain.width {
                let i = (y * plain.width + x) * 4
                let same = plain.bytes[i..<i + 4].elementsEqual(textured.bytes[i..<i + 4])
                if !same { differing += 1 }
                // "Outside the ink" is judged by the **untextured** render, which is the only honest
                // reading of it: the textured one is short of ink precisely where the paper rejected
                // it, so using it would exempt every pixel the bug would have to touch.
                if plain.alpha(x, y) == 0 && !same { outsideTheInk += 1 }
            }
        }
        XCTAssertGreaterThan(differing, 200,
                             "the texture has to reach the ink — \(differing) pixels moved")
        XCTAssertEqual(outsideTheInk, 0,
                       "the texture may not appear outside the stroke; \(outsideTheInk) pixels the "
                       + "untextured stroke never reached were changed")
    }

    // MARK: - 2. The anchoring — the assertion the feature exists for

    /// **The discriminating test.** A stroke-anchored texture — the alternative the owner was offered
    /// and declined — passes every other assertion in this file and fails this one, because it would
    /// give the two crops below identical pixels.
    ///
    /// The control is what makes it an argument rather than an observation: **with no texture the two
    /// crops are byte-identical**, because a translation moves the dabs and changes nothing else
    /// (BRUSH.md §4's random field is hashed by arc length, so the pattern travels with the stroke).
    /// So the difference the textured pair shows is the texture's, by elimination, and not an
    /// artefact of drawing at a different place.
    ///
    /// The offset is one checker cell, which flips the phase outright rather than nudging it, and it
    /// is integral so no sub-pixel resampling can be mistaken for the effect.
    func testTheSameStrokeAtTwoCanvasPositionsSamplesDifferentTextureAndTheSameAtTheSameOne() throws {
        let sheet = try Self.writeTestTexture(cell: 16)
        let settings = BrushTextureSettings(mask: sheet, tileSize: 64)
        let a = CGPoint(x: 48, y: 64)
        let b = CGPoint(x: 48, y: 80)                   // one cell down: the opposite checker phase
        let box = CGRect(x: 32, y: -16, width: 128, height: 32)  // the stroke's own neighbourhood
        func crop(_ brush: Brush, _ origin: CGPoint) throws -> [UInt8] {
            try Self.pixels(Self.replayTier(brush, at: origin))
                .crop(box.offsetBy(dx: 0, dy: origin.y))
        }

        let plainA = try crop(Self.brush(nil), a), plainB = try crop(Self.brush(nil), b)
        XCTAssertFalse(plainA.allSatisfy { $0 == 0 }, "fixture precondition: the crop holds the stroke")
        XCTAssertEqual(plainA, plainB,
                       "control: with no texture, one stroke drawn at two places is the same picture "
                       + "of a stroke — without this the textured comparison below proves nothing")

        let inkedA = try crop(Self.brush(settings), a), inkedB = try crop(Self.brush(settings), b)
        XCTAssertNotEqual(inkedA, inkedB,
                          "the texture is anchored to the canvas, so the same stroke drawn a cell "
                          + "further down lies on different paper. Equal crops here is a "
                          + "stroke-anchored texture — the thing BRUSH.md §2.25 declined.")
        XCTAssertEqual(inkedA, try crop(Self.brush(settings), a),
                       "and it is a function of the canvas point and nothing else: the same stroke "
                       + "at the same place is the same pixels twice")
    }

    /// The other half of anchoring, at the level a whole canvas can see it: a stroke moved by a
    /// **whole tile** lands on the same phase again, so its crop comes back identical. That is the
    /// property a canvas-anchored sheet has and an arbitrary position-dependent noise field does
    /// not, and it is what distinguishes a tiled paper from *"the pixels changed when I moved"*.
    func testAStrokeMovedByAWholeTileLandsOnTheSamePaperAgain() throws {
        let sheet = try Self.writeTestTexture(cell: 16)
        let settings = BrushTextureSettings(mask: sheet, tileSize: 64)
        let box = CGRect(x: 32, y: -16, width: 128, height: 32)
        func crop(_ origin: CGPoint) throws -> [UInt8] {
            try Self.pixels(Self.replayTier(Self.brush(settings), at: origin))
                .crop(box.offsetBy(dx: 0, dy: origin.y))
        }
        let atSixtyFour = try crop(CGPoint(x: 48, y: 64))
        XCTAssertFalse(atSixtyFour.allSatisfy { $0 == 0 }, "fixture precondition: there is a stroke")
        XCTAssertEqual(atSixtyFour, try crop(CGPoint(x: 48, y: 128)),
                       "one whole tile down is the same phase of the same sheet")
        XCTAssertNotEqual(atSixtyFour, try crop(CGPoint(x: 48, y: 112)),
                          "and most of a tile down is not — otherwise the first assertion is passing "
                          + "because the texture reached nothing")
    }

    // MARK: - 3. Opacity scales the textured result

    /// *"...then is scaled with opacity."*
    ///
    /// **The order is the claim.** The texture multiplies into the accumulated stroke and the
    /// stroke's opacity then scales *that*, which means a half-opacity textured stroke is exactly
    /// half of a full-opacity one at every pixel. An implementation that applied the paper after the
    /// cap, or that folded it into each dab's flow, would be short of this where the stroke crosses
    /// its own dabs — which is the whole reason BRUSH.md §2.11's buffer exists.
    func testTheStrokesOpacityScalesTheTexturedInkAtEveryPixel() throws {
        let sheet = try Self.writeTestTexture()
        let brush = Self.brush(BrushTextureSettings(mask: sheet, tileSize: 64))
        let full = try Self.pixels(Self.replayTier(brush, at: CGPoint(x: 48, y: 96), opacity: 1))
        let half = try Self.pixels(Self.replayTier(brush, at: CGPoint(x: 48, y: 96), opacity: 0.5))
        XCTAssertFalse(full.isBlank, "fixture precondition: the full-opacity stroke drew something")

        var inked = 0, worst = 0
        for y in 0..<full.height {
            for x in 0..<full.width where full.alpha(x, y) > 0 {
                inked += 1
                worst = max(worst, abs(half.alpha(x, y) * 2 - full.alpha(x, y)))
            }
        }
        XCTAssertGreaterThan(inked, 200, "fixture precondition: there is textured ink to halve")
        // One byte of slack, and one only: `.destinationIn` and the 0.5 draw each round once.
        XCTAssertLessThanOrEqual(worst, 2,
                                 "every pixel of a half-opacity textured stroke is half of the "
                                 + "full-opacity one — worst was off by \(worst)")
    }

    // MARK: - 4. The tiers agree, which is where a mis-anchored buffer shows up

    /// **The live tier's window moves and the paper must not move with it.**
    ///
    /// `StrokeScratch` accumulates a stroke in a window sized and positioned to the stroke, and grows
    /// it as the pen travels; the replay accumulates the same stroke in the cel, whose origin is the
    /// canvas's. A texture anchored to whatever buffer it happens to be merging into would look
    /// perfectly plausible on each tier alone and put the paper in two different places — which the
    /// artist sees as the ink changing at pen-up, and which no single-tier test can catch.
    ///
    /// Zero tolerance, because `BrushTipLogicTests` already pins that the two agree byte for byte
    /// with no texture; anything less here would be conceding the very thing being measured.
    func testTheLiveScratchAndTheReplayTierPutTheTextureOnTheSameCanvasPixels() throws {
        let sheet = try Self.writeTestTexture()
        let brush = Self.brush(BrushTextureSettings(mask: sheet, tileSize: 64))
        // Deliberately not on a tile boundary and not at the canvas origin, so a window anchored to
        // itself lands the paper somewhere else rather than coincidentally in the same place.
        let origin = CGPoint(x: 53, y: 91)
        let live = try Self.pixels(Self.liveTier(brush, at: origin))
        let replay = try Self.pixels(Self.replayTier(brush, at: origin))
        XCTAssertFalse(live.isBlank, "fixture precondition: the live tier drew something")

        var differing = 0
        for i in 0..<min(live.bytes.count, replay.bytes.count) where live.bytes[i] != replay.bytes[i] {
            differing += 1
        }
        XCTAssertEqual(differing, 0,
                       "the live window and the cel have to put the paper on the same canvas pixels "
                       + "— \(differing) bytes differ")
    }

    /// And the third buffer kind: `CGContextDabTarget`, which is what a vector cel's own render draws
    /// through. Same stroke, same paper, same pixels — so the anchoring is a property of the canvas
    /// and not of `RasterLayerTexture`.
    func testTheRenderLocalTierPutsTheTextureWhereTheCelTierDoes() throws {
        let sheet = try Self.writeTestTexture()
        let brush = Self.brush(BrushTextureSettings(mask: sheet, tileSize: 64))
        let origin = CGPoint(x: 53, y: 91)
        let viaContext = try Self.pixels(Self.renderLocalTier(brush, at: origin))
        let viaTexture = try Self.pixels(Self.replayTier(brush, at: origin))
        XCTAssertFalse(viaContext.isBlank, "fixture precondition: the render-local tier drew something")
        XCTAssertEqual(viaContext.bytes, viaTexture.bytes,
                       "one stroke, two buffer kinds, one canvas — the paper is in the same place")
    }

    // MARK: - 5. No texture is byte-identical to before the feature

    /// **The pin that says this change is additive**, and the number in it was measured on the tree
    /// that did not have the feature.
    ///
    /// MEASURED at `origin/main` `b4dffeb` — *"Texture returns canvas-anchored, and stretch is
    /// scheduled with the set"*, the commit before any of §2.25 existed — by running this fixture
    /// there under a probe whose bytes are these lines verbatim. Both digests below are of the same
    /// stroke on the two tiers a brush actually reaches, which is why there are two: a change that
    /// moved only the buffered merge would leave one of them alone.
    ///
    /// If this goes red, the untextured render moved. That is a regression whatever else is green —
    /// every document in the app is drawn with brushes that have no texture.
    func testABrushWithNoTextureRendersTheBytesItRenderedBeforeTexturesExisted() throws {
        let plain = Self.brush(nil)
        let origin = CGPoint(x: 53, y: 91)
        let replay = try Self.pixels(Self.replayTier(plain, at: origin))
        let renderLocal = try Self.pixels(Self.renderLocalTier(plain, at: origin))
        XCTAssertFalse(replay.isBlank, "fixture precondition: the untextured stroke drew something")

        XCTAssertEqual(Self.digest(replay.bytes), Self.replayDigestBeforeTextures,
                       "an untextured stroke's cel-tier pixels moved")
        XCTAssertEqual(Self.digest(renderLocal.bytes), Self.renderLocalDigestBeforeTextures,
                       "an untextured stroke's render-local pixels moved")
    }

    /// FNV-1a over the whole render. A digest rather than a stored image because the operand is
    /// *"identical"* and nothing weaker — there is no tolerance to express, so there is nothing a
    /// picture would add beyond four million bytes in the repository.
    private static func digest(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// MEASURED at `b4dffeb` on the dedicated simulator, and **the two came back equal**, which is
    /// not a copy-paste: it is `RasterVectorParityLogicTests`' claim showing up here as a number —
    /// one stroke into a `RasterLayerTexture` and into a `UIGraphicsImageRenderer` context is the
    /// same picture. They stay two constants so a change that moved one tier alone cannot hide.
    ///
    /// **What would red this other than a regression**: a CoreGraphics change under a new simulator
    /// runtime. Every other zero-tolerance test in this repo compares two renders made in one
    /// process, so this is the only one exposed to that; if it goes red alone and the untextured
    /// render is visibly unchanged, re-measure on the new runtime and say in the commit that it was
    /// re-measured rather than adjusting the number quietly.
    private static let replayDigestBeforeTextures: UInt64 = 16_765_771_397_875_139_493
    private static let renderLocalDigestBeforeTextures: UInt64 = 16_765_771_397_875_139_493

    // MARK: - 6. The eraser textures its removal, and cannot cleanly cut

    /// **BRUSH.md §11: the eraser is a stroke, so it inherits the paper with no eraser work** — and
    /// this is the test that says the inheritance is real rather than incidental. A textured eraser
    /// takes away less than an untextured one, and specifically it leaves ink where the paper
    /// rejected the removal, which is what erasing *through* paper means.
    func testATexturedEraserLeavesInkWhereThePaperRejectsTheRemoval() throws {
        let sheet = try Self.writeTestTexture()
        // A filled cel to erase out of, so "what is left" is a number rather than a hope.
        let filled = UIGraphicsImageRenderer(size: Self.canvas, format: PixelOps.transparentFormat())
            .image { ctx in
                ctx.cgContext.setFillColor(UIColor.black.cgColor)
                ctx.cgContext.fill(CGRect(origin: .zero, size: Self.canvas))
            }
        func remaining(_ texture: BrushTextureSettings?) throws -> Int {
            let cel = Self.replayTier(Self.brush(texture), at: CGPoint(x: 48, y: 96),
                                      isEraser: true, over: filled)
            let p = try Self.pixels(cel)
            // **The core of the eraser's own band and nothing else.** The stroke runs from x 48 to
            // x 144 at y 96 with a 12 pt brush, so this box is strictly inside what an untextured
            // eraser clears — counting a wider one would mostly count fill the eraser never reached,
            // which is a constant in both arms and would drown the difference being measured.
            var kept = 0
            for y in 92..<100 {
                for x in 60..<140 where p.alpha(x, y) > 128 { kept += 1 }
            }
            return kept
        }
        let area = (100 - 92) * (140 - 60)
        let plainKept = try remaining(nil)
        let texturedKept = try remaining(BrushTextureSettings(mask: sheet, tileSize: 64))
        XCTAssertEqual(plainKept, 0,
                       "fixture precondition: an untextured eraser clears its own core outright")
        XCTAssertGreaterThan(texturedKept, area / 5,
                             "a textured eraser removes through the paper, so the ink the paper "
                             + "rejected survives — \(texturedKept) of \(area) pixels did")
        XCTAssertLessThan(texturedKept, area,
                          "and it still erases where the paper let it through, or the eraser has "
                          + "simply stopped working rather than acquired a texture")
    }

    /// **And the gate that has to know about it.** `VectorEraser.supportsCleanCut` asserts the ink it
    /// deletes was going to be removed completely anyway; a textured eraser removes less than its
    /// footprint claims at every point the paper is short of 1, so the ink a clean cut would delete
    /// is ink the punch would have left behind — the asymmetric direction that gate is written
    /// around. The untextured arm is the operand: the same brush, the same numbers, one field apart.
    func testATexturedEraserIsRefusedACleanCutTheSameBrushWouldOtherwiseGet() throws {
        let sheet = try Self.writeTestTexture()
        var clean = Self.brush(nil)
        clean.dab.hardness = 1
        XCTAssertTrue(VectorEraser.supportsCleanCut(brush: clean, opacity: 1, minPressure: 1),
                      "fixture precondition: this brush is otherwise cleanly cuttable")
        var papered = clean
        papered.texture = BrushTextureSettings(mask: sheet, tileSize: 64)
        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: papered, opacity: 1, minPressure: 1),
                       "a textured eraser leaves ink inside its own footprint, so it may not claim "
                       + "the ink was going to be removed completely")
    }

    // MARK: - 7. Depth, and the format

    /// **Depth 0 is the identity, byte for byte.** Not a nicety: it is what lets one arithmetic serve
    /// the whole range, and the reason `Brush.texture` is optional rather than a `depth: 0` default is
    /// that the optional says the same thing without a code path. Both halves are here — the identity
    /// at 0, and that depth is doing something at all in between, since an implementation that
    /// ignored `depth` entirely would pass the first alone.
    func testDepthZeroIsExactlyNoTextureAndDepthInBetweenIsInBetween() throws {
        let sheet = try Self.writeTestTexture()
        let origin = CGPoint(x: 48, y: 96)
        func alphaSum(_ texture: BrushTextureSettings?) throws -> Int {
            let p = try Self.pixels(Self.replayTier(Self.brush(texture), at: origin))
            return stride(from: 3, to: p.bytes.count, by: 4).reduce(0) { $0 + Int(p.bytes[$1]) }
        }
        let none = try Self.pixels(Self.replayTier(Self.brush(nil), at: origin))
        let atZero = try Self.pixels(
            Self.replayTier(Self.brush(BrushTextureSettings(mask: sheet, tileSize: 64, depth: 0)), at: origin))
        XCTAssertFalse(none.isBlank, "fixture precondition: the stroke drew something")
        XCTAssertEqual(none.bytes, atZero.bytes, "depth 0 is no texture, byte for byte")

        let full = try alphaSum(BrushTextureSettings(mask: sheet, tileSize: 64, depth: 1))
        let part = try alphaSum(BrushTextureSettings(mask: sheet, tileSize: 64, depth: 0.5))
        let plain = try alphaSum(nil)
        XCTAssertLessThan(full, part, "a deeper texture takes more ink away")
        XCTAssertLessThan(part, plain, "and a half-depth one still takes some")
    }

    /// The format. A brush with no texture writes **no key**, which is what makes the field additive
    /// on disk as well as in the renderer; a brush with one round-trips whole.
    func testATexturedBrushRoundTripsAndAnUntexturedOneWritesNoKey() throws {
        let sheet = try Self.writeTestTexture()
        let plain = Self.brush(nil)
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(json.contains("\"texture\""),
                       "a brush with no texture writes no texture key: \(json)")

        var papered = plain
        papered.texture = BrushTextureSettings(mask: sheet, tileSize: 37, depth: 0.25)
        let back = try JSONDecoder().decode(Brush.self, from: try JSONEncoder().encode(papered))
        XCTAssertEqual(back.texture, papered.texture, "all three fields come back")
        XCTAssertEqual(back, papered, "and the brush is the same value, which is what `BrushRef` keys on")
    }

    // MARK: - 8. The sheet travels with the document

    /// **BUGS.md's *"copied by the palette, not by what is drawn"*, one field along.** A brush's tip
    /// already had to be copied into the package or a document opened on another device drew with a
    /// brush that draws nothing; §2.25 gives a brush a *second* file, and the same defect is one
    /// missed union away.
    ///
    /// **The operands are separated on purpose.** The file inside the package, and the file put back
    /// into the shared library by a load, are what say it *travelled*. The render is what says the
    /// travelling was worth something. The render alone would not do: `BrushTextureStore` memoizes a
    /// mask for the life of the process, so a reopened document in *this* process would draw the
    /// right ink off the cache even if nothing had been copied anywhere. That is exactly the shape of
    /// assertion this repo has a section about, and it is why the filesystem is checked directly.
    func testATexturedBrushesSheetTravelsWithTheDocumentAndTheReopenedInkIsIdentical() throws {
        let sheet = try Self.writeTestTexture()
        let fileName = try XCTUnwrap(sheet.importedFileName)
        let settings = BrushTextureSettings(mask: sheet, tileSize: 64)

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        let papered = Self.brush(settings)
        vector.addStroke(VectorStroke(id: UUID(), brush: papered,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: 12, opacity: 1,
                                      samples: [VectorSample(x: 6, y: 30, pressure: 1),
                                                VectorSample(x: 30, y: 30, pressure: 1),
                                                VectorSample(x: 56, y: 30, pressure: 1)]))
        let expected = try Self.pixels(vector.render())
        XCTAssertFalse(expected.isBlank, "fixture precondition: the textured stroke drew something")

        let url = ProjectStore.createNewProjectURL(name: "Papered")
        let saved = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        wait(for: [saved], timeout: 30)

        let inPackage = url.appendingPathComponent("brushes").appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inPackage.path),
                      "the sheet the document's ink is laid through has to travel with it — without "
                      + "this the document opens on another device with the paper missing")

        // The shared library forgets it, which is what moving the package to another device looks
        // like from the document's point of view.
        let shared = BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName)
        try FileManager.default.removeItem(at: shared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path), "fixture precondition")

        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.path),
                      "and a load puts it back, so the next stroke drawn with that brush has paper too")
        let canvas = try XCTUnwrap(reopened.layers.compactMap { $0.cels.first?.vector }
                                                  .first { !$0.strokes.isEmpty })
        XCTAssertEqual(try Self.pixels(canvas.render()).bytes, expected.bytes,
                       "the ink is unchanged by a save and reopen")

        // And what was compared is textured ink, not two pictures of a plain stroke.
        var plain = papered
        plain.texture = nil
        let control = VectorCanvas(size: vector.size)
        control.addStroke(VectorStroke(id: UUID(), brush: plain,
                                       color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                       size: 12, opacity: 1,
                                       samples: [VectorSample(x: 6, y: 30, pressure: 1),
                                                 VectorSample(x: 30, y: 30, pressure: 1),
                                                 VectorSample(x: 56, y: 30, pressure: 1)]))
        XCTAssertNotEqual(try Self.pixels(control.render()).bytes, expected.bytes,
                          "the round trip preserved *textured* pixels — an implementation that lost "
                          + "the texture on both sides would have passed the comparison above")
    }
}
