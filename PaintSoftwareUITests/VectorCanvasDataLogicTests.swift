import XCTest

/// Pure-logic tests for `VectorCanvasData`'s **per-element** decode — the fix for a permanent
/// data-loss path, not a tidying.
///
/// `ProjectStore`'s load used to wrap the whole payload decode in `try?` and fall back to
/// `VectorCanvas.empty`, so one unreadable field discarded every stroke, fill, image and erase
/// element on the cel, silently, and the next save wrote that loss to disk. These tests pin the
/// replacement contract: **a broken element costs that element; a broken payload still throws**, and
/// the two reasons an element can be broken are reported apart, because an unknown discriminator is a
/// newer file in an older build (expected, benign) while a malformed *known* element is a defect.
///
/// Assertions are on element counts *and identities* throughout. "Did not throw" is exactly the
/// signal the old code gave while destroying the drawing.
///
/// Lives in `PaintSoftwareUITests` with the other `*LogicTests` and needs no simulator gesture —
/// `Engine/VectorLayer.swift` is compiled into this target directly (see `BrushEngineLogicTests`'s
/// header for why `@testable import` cannot work here).
final class VectorCanvasDataLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 64, height: 64)

    // MARK: - Fixtures

    private static func testBrush() -> Brush {
        Brush(name: "Test", tip: .round, size: 20, opacity: 1, dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1, angle: BrushAngleSettings(jitter: 0)), stroke: BrushStrokeSettings(stabilization: 0, blendMode: .normal))
    }

    private func stroke(_ red: Double, composite: StrokeComposite = .paint) -> VectorStroke {
        VectorStroke(brush: Self.testBrush(),
                     color: CodableColor(red: red, green: 0, blue: 1, alpha: 1),
                     size: 20, opacity: 1,
                     samples: [VectorSample(x: 32, y: 32, pressure: 1),
                               VectorSample(x: 32, y: 32, pressure: 1)],
                     composite: composite)
    }

    private func fill(_ green: Double) -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: Self.canvasSize), transform: nil),
                          color: CodableColor(red: 0, green: green, blue: 0, alpha: 1))
    }

    private func imageRef(_ name: String) -> VectorCanvasData.ImageRef {
        VectorCanvasData.ImageRef(fileName: name, x: 32, y: 32, scale: 1, rotation: 0)
    }

    private func videoRef(_ name: String) -> VectorCanvasData.VideoRef {
        VectorCanvasData.VideoRef(fileName: name, width: 16, height: 9,
                                  sourceStart: SourceTime(value: 0, timescale: 30),
                                  sourceEnd: SourceTime(value: 90, timescale: 30), speed: 1,
                                  x: 32, y: 32, scale: 1, rotation: 0,
                                  aspect: 1, stretchAxis: 0, mirrored: false)
    }

    private func solidImage(_ color: UIColor, side: CGFloat = 16) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// One-word tag per kind, so an expected z-order reads as a literal in the assertions.
    private func kinds(_ elements: [VectorCanvasData.ElementData]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .text: return "text"
            case .video: return "video"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    private func kinds(_ elements: [VectorElement]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .text: return "text"
            case .video: return "video"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    /// Stable identity per element, so an assertion says *which* elements survived rather than how
    /// many. Images have no `id` on disk, so their file name is the identity.
    private func ids(_ elements: [VectorCanvasData.ElementData]) -> [String] {
        elements.map {
            switch $0 {
            case .stroke(let stroke): return stroke.id.uuidString
            case .fill(let fill): return fill.id.uuidString
            case .text(let text): return text.id.uuidString
            case .image(let ref): return ref.fileName
            case .video(let ref): return ref.fileName
            }
        }
    }

    // MARK: - JSON surgery

    /// `value` encoded, then handed back as a mutable JSON object — the way to build an authentic
    /// "written by a build that isn't this one" payload without checking a blob into the suite.
    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "VectorCanvasDataLogicTests", code: 1)
        }
        return object
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    /// The four-element payload every damage test starts from: fill, image, stroke, erase — one of
    /// each thing a cel can hold, in a deliberate z-order.
    private func healthyPayload() -> VectorCanvasData {
        VectorCanvasData(elements: [.fill(fill(1)), .image(imageRef("a.png")),
                                    .stroke(stroke(1)), .stroke(stroke(0.5, composite: .erase))],
                         // Empty, which is what this build writes: the key is decode-only since TODO
                         // item (12) stage 3, and a payload carrying `[1,0,0,1,0,0]` would no longer
                         // round-trip through `encode(to:)`.
                         transform: [])
    }

    /// Encodes `payload` and replaces the element at `index` with `replacement`, so the *rest* of the
    /// file is byte-for-byte what the app itself would have written.
    private func payloadJSON(_ payload: VectorCanvasData, replacingElementAt index: Int,
                             with replacement: Any) throws -> Data {
        var object = try jsonObject(payload)
        guard var elements = object["elements"] as? [Any] else {
            throw NSError(domain: "VectorCanvasDataLogicTests", code: 2)
        }
        elements[index] = replacement
        object["elements"] = elements
        return try jsonData(object)
    }

    /// A well-formed element of a kind this build has no case for — literally what a newer build
    /// writing a new element type produces.
    ///
    /// **This is the third string to hold the job and the first one that cannot silently lose it.**
    /// It was `"text"` until `ADD_TEXT.md` stage 3 implemented text, and `"video"` until VIDEO.md
    /// stage 2 implemented video; each time, the sentinel quietly stopped testing the unknown-kind
    /// branch and started asserting that a shipped feature was missing — a green test measuring
    /// nothing. `testTheSentinelIsNotAKindThisBuildImplements` closes that door mechanically, by
    /// asking the *encoder* which discriminators exist rather than trusting this comment.
    ///
    /// `"nurbsPatch"` is chosen to be un-implementable rather than plausible: this app's vector model
    /// is polylines and `CGPath`s, there is no spline surface anywhere in it, and nothing on
    /// VIDEO.md's or KEYFRAMES.md's build orders goes near one. The decoder cannot tell a realistic
    /// noun from an unrealistic one anyway — all it sees is a string it has no case for.
    static let unimplementedKind = "nurbsPatch"

    private var futureElement: [String: Any] {
        [
            "kind": Self.unimplementedKind,
            Self.unimplementedKind: ["fileName": "surface.iges", "x": 32, "y": 32],
        ]
    }

    /// Every discriminator this build actually writes, **read out of the encoder** rather than listed
    /// by hand — one `ElementData` of each case, encoded, and its `kind` key read back. A hand-kept
    /// list would go stale exactly when the sentinel does, which is the failure this exists to catch.
    private func implementedKinds() throws -> Set<String> {
        let samples: [VectorCanvasData.ElementData] = [
            .stroke(stroke(1)), .fill(fill(1)), .image(imageRef("a.png")),
            .text(VectorTextElement(recipe: TextRecipe(string: "a"),
                                    frame: TextFrame(origin: CGPoint(x: 8, y: 8),
                                                     size: CGSize(width: 8, height: 8)))),
            .video(videoRef("clip.mov")),
        ]
        return Set(try samples.map { try XCTUnwrap(try jsonObject($0)["kind"] as? String) })
    }

    /// A `stroke` element whose payload is missing a required key. The discriminator is one this
    /// build knows, so this is a defect rather than a version gap.
    private func brokenStrokeElement() throws -> [String: Any] {
        var strokeObject = try jsonObject(stroke(0.25))
        strokeObject.removeValue(forKey: "samples")
        return ["kind": "stroke", "stroke": strokeObject]
    }

    // MARK: - One bad element costs one element

    /// The headline. Four elements, one of them unreadable — the other three, and every kind of
    /// content a cel can hold, must come back.
    func testOneBogusElementInFourLeavesTheOtherThreeIntact() throws {
        let payload = healthyPayload()
        let expected = ids(payload.elements)
        let data = try payloadJSON(payload, replacingElementAt: 2, with: brokenStrokeElement())

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(decoded.elements.count, 3,
                       "One unreadable element must cost one element — the whole cel is what the try? used to cost")
        XCTAssertEqual(ids(decoded.elements), [expected[0], expected[1], expected[3]],
                       "The survivors must be the three that were readable, in their saved order")
        XCTAssertEqual(kinds(decoded.elements), ["fill", "image", "erase"],
                       "The fill, the placed image and the erase stroke all survive a broken paint stroke")
        XCTAssertEqual(decoded.decodeReport.droppedCount, 1)
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
        XCTAssertTrue(decoded.decodeReport.unknownKinds.isEmpty,
                      "A kind this build knows, with a payload it cannot read, is a defect and not a version gap")
    }

    /// The same file, taken all the way to a `VectorCanvas` the way `ProjectStore` does it — because
    /// "three `ElementData`" is not yet "three things on the artist's cel".
    func testTheSurvivingElementsReachTheCanvasInOrder() throws {
        let payload = healthyPayload()
        let data = try payloadJSON(payload, replacingElementAt: 2, with: brokenStrokeElement())
        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        let placed = solidImage(.green)
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: decoded.canvasSpaceElements(resolvingImages: { _ in placed },
                                                                        resolvingVideos: { _ in nil }))

        XCTAssertEqual(kinds(canvas.elements), ["fill", "image", "erase"])
        XCTAssertFalse(canvas.isEmpty, "A cel that lost one element is not an empty cel")
        XCTAssertTrue(canvas.transform.isIdentity)
    }

    // MARK: - Unknown kind vs corrupt known kind

    /// **The guard on every other test in this section.** Twice now a sentinel has been implemented
    /// out from under these tests — `"text"` by `ADD_TEXT.md` stage 3, `"video"` by VIDEO.md stage 2
    /// — and on both occasions the tests below went on passing while measuring something else
    /// entirely: not "an unknown kind costs one element" but "a feature this build ships is absent".
    /// Nothing said so, because the decoder's answer is identical either way.
    ///
    /// If this goes red, the code is wrong in the precise sense that matters here: a discriminator
    /// the encoder now writes is being used as one it does not, and every unknown-kind assertion in
    /// this file has silently stopped testing its branch. The fix is to pick a new sentinel, not to
    /// relax this.
    func testTheSentinelIsNotAKindThisBuildImplements() throws {
        let implemented = try implementedKinds()
        XCTAssertEqual(implemented, ["stroke", "fill", "image", "text", "video"],
                       "fixture precondition: the encoder writes exactly these five discriminators")
        XCTAssertFalse(implemented.contains(Self.unimplementedKind),
                       "'\(Self.unimplementedKind)' is a kind this build now writes, so every "
                       + "unknown-kind test in this file has stopped testing the unknown-kind branch")
    }

    /// The case this fix exists ahead of: an older build opening a project that contains an element
    /// type it has never heard of. Expected, benign, and it must cost that element only.
    func testAnUnknownKindCostsOnlyThatElement() throws {
        let payload = healthyPayload()
        let expected = ids(payload.elements)
        let data = try payloadJSON(payload, replacingElementAt: 1, with: futureElement)

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(ids(decoded.elements), [expected[0], expected[2], expected[3]])
        XCTAssertEqual(kinds(decoded.elements), ["fill", "stroke", "erase"])
        XCTAssertEqual(decoded.decodeReport.unknownKinds, [Self.unimplementedKind],
                       "An unrecognised discriminator is reported by name, so a log line can say which feature is missing")
        XCTAssertEqual(decoded.decodeReport.malformedCount, 0,
                       "A newer build's element is not a malformed one — that distinction is the whole point of the report")
    }

    /// The two failures are counted apart in one file, which is what lets the load path log a benign
    /// version gap differently from a real defect.
    func testUnknownKindAndMalformedElementAreReportedSeparately() throws {
        var object = try jsonObject(healthyPayload())
        var elements = try XCTUnwrap(object["elements"] as? [Any])
        elements[1] = futureElement
        elements[2] = try brokenStrokeElement()
        object["elements"] = elements

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: try jsonData(object))

        XCTAssertEqual(kinds(decoded.elements), ["fill", "erase"])
        XCTAssertEqual(decoded.decodeReport.unknownKinds, [Self.unimplementedKind])
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
        XCTAssertEqual(decoded.decodeReport.droppedCount, 2)
        XCTAssertFalse(decoded.decodeReport.isClean)
    }

    /// A *missing* or non-string `kind` is not a version gap — nothing wrote it deliberately — so it
    /// must be counted as malformed rather than as an unknown kind.
    func testAnElementWithNoKindAtAllIsMalformedRatherThanUnknown() throws {
        let payload = healthyPayload()
        let data = try payloadJSON(payload, replacingElementAt: 0, with: ["stroke": ["nonsense": 1]])

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(decoded.elements.count, 3)
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
        XCTAssertTrue(decoded.decodeReport.unknownKinds.isEmpty)
    }

    /// A slot that is not an object at all — the decoder must not stall on it. `JSONDecoder`'s
    /// unkeyed container only advances past a value it decoded *successfully*, so a hand-rolled
    /// try/catch/continue loop would re-read this slot forever; `LossySlot` is what stops that.
    func testANonObjectSlotIsSkippedRatherThanStallingTheDecoder() throws {
        let payload = healthyPayload()
        let data = try payloadJSON(payload, replacingElementAt: 3, with: 42)

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(kinds(decoded.elements), ["fill", "image", "stroke"])
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
    }

    // MARK: - The happy path is unchanged

    /// Characterization guard: per-element tolerance must be invisible to a well-formed file. Same
    /// elements, same identities, same order, clean report — and re-encoding produces
    /// byte-identical JSON, so the tolerant decode did not quietly rewrite anyone's project.
    func testAWellFormedPayloadRoundTripsUnchanged() throws {
        let payload = healthyPayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(ids(decoded.elements), ids(payload.elements))
        XCTAssertEqual(kinds(decoded.elements), ["fill", "image", "stroke", "erase"])
        XCTAssertEqual(decoded.transform, payload.transform, "both empty, and the key is not written")
        XCTAssertTrue(decoded.decodeReport.isClean, "Nothing was dropped, so the report says nothing was dropped")
        XCTAssertEqual(decoded.decodeReport.droppedCount, 0)
        XCTAssertEqual(try encoder.encode(decoded), data,
                       "A healthy payload re-encodes byte-for-byte — the decode report is not written to disk")
    }

    /// The kind-filtered reads still work on a payload that dropped something, since ~30 call sites
    /// use them.
    func testKindFilteredReadsSeeOnlyTheSurvivors() throws {
        let payload = healthyPayload()
        let data = try payloadJSON(payload, replacingElementAt: 2, with: futureElement)
        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(decoded.strokes.map(\.composite), [.erase])
        XCTAssertEqual(decoded.fills.count, 1)
        XCTAssertEqual(decoded.images.map(\.fileName), ["a.png"])
    }

    // MARK: - The legacy path

    /// Builds a pre-display-list payload: three parallel arrays, no `elements` key.
    private func legacyJSON(strokes: [Any], fills: [Any], images: [Any],
                            transform: [Double]? = [1, 0, 0, 1, 0, 0]) throws -> Data {
        var root: [String: Any] = ["strokes": strokes, "fills": fills, "images": images]
        if let transform { root["transform"] = transform }
        return try jsonData(root)
    }

    /// A legacy file carries no z-order, so decoding *reconstructs* the one the old renderer hard-coded
    /// — fills, then images, then strokes. Per-element tolerance must not disturb that: a dropped
    /// entry leaves a gap in its own bucket and the buckets are still concatenated in that order.
    func testALegacyPayloadWithOneBrokenStrokeKeepsTheRestAndTheOrder() throws {
        let keptStroke = stroke(1)
        let keptFill = fill(1)
        var broken = try jsonObject(stroke(0.25))
        broken.removeValue(forKey: "brush")

        let data = try legacyJSON(strokes: [broken, try jsonObject(keptStroke)],
                                  fills: [try jsonObject(keptFill)],
                                  images: [try jsonObject(imageRef("a.png"))])

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(kinds(decoded.elements), ["fill", "image", "stroke"],
                       "Fills, then images, then strokes — the reconstruction the old renderer's order depends on")
        XCTAssertEqual(ids(decoded.elements),
                       [keptFill.id.uuidString, "a.png", keptStroke.id.uuidString])
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
        XCTAssertTrue(decoded.decodeReport.unknownKinds.isEmpty,
                      "A legacy payload predates the discriminator, so it cannot express an unknown kind")
    }

    /// The reconstruction itself, undamaged — the guard that the tolerance did not change what an
    /// existing project looks like when it opens.
    func testAnIntactLegacyPayloadStillDecodesAsFillsThenImagesThenStrokes() throws {
        let strokes = [stroke(1), stroke(0.5)]
        let fills = [fill(1), fill(0.5)]
        let data = try legacyJSON(strokes: try strokes.map { try jsonObject($0) },
                                  fills: try fills.map { try jsonObject($0) },
                                  images: [try jsonObject(imageRef("a.png"))])

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(kinds(decoded.elements), ["fill", "fill", "image", "stroke", "stroke"])
        XCTAssertEqual(ids(decoded.elements),
                       [fills[0].id.uuidString, fills[1].id.uuidString, "a.png",
                        strokes[0].id.uuidString, strokes[1].id.uuidString])
        XCTAssertTrue(decoded.decodeReport.isClean)
        XCTAssertTrue(decoded.affineTransform.isIdentity)
    }

    // MARK: - The blast radius stays where it is

    /// **A broken payload is not a broken element**, and the load path needs them apart: "this file is
    /// not a vector payload at all" is unsalvageable and worth shouting about, and turning it into a
    /// silently empty cel is the very thing being fixed. So the container-level decode still throws.
    func testAPayloadThatIsNotAVectorPayloadStillThrows() throws {
        let notAPayload = try jsonData(["something": "else"])
        XCTAssertThrowsError(try JSONDecoder().decode(VectorCanvasData.self, from: notAPayload),
                             "Neither an ordered nor a legacy payload — there is nothing to salvage, so this must not decode")

        let elementsNotAnArray = try jsonData(["elements": "nope", "transform": [1, 0, 0, 1, 0, 0]])
        XCTAssertThrowsError(try JSONDecoder().decode(VectorCanvasData.self, from: elementsNotAnArray),
                             "A structurally broken elements key is a broken file, not a file with a broken element")
    }

    /// A transform that will not read costs the transform, not the drawing — `affineTransform` has
    /// always answered `.identity` for anything that is not six numbers, and the decode agrees with
    /// it. **Both ways it can fail to read**, since TODO item (12) stage 3 made the absent case the
    /// ordinary one: this build writes no key at all, so a file that *does* carry one was written by
    /// an older build and is exactly the file most likely to be damaged as well.
    func testATransformThatWillNotReadLoadsAsIdentityRatherThanCostingTheElements() throws {
        var absent = try jsonObject(healthyPayload())
        XCTAssertNil(absent["transform"], "fixture precondition: this build writes no transform")
        absent.removeValue(forKey: "transform")

        for (name, object) in [("absent", absent),
                               ("unreadable", { var o = absent; o["transform"] = "not six numbers"; return o }()),
                               ("too short", { var o = absent; o["transform"] = [1, 0, 0]; return o }())] {
            let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: try jsonData(object))
            XCTAssertEqual(decoded.elements.count, 4, "\(name): every element survives")
            XCTAssertTrue(decoded.affineTransform.isIdentity, "\(name)")
            XCTAssertTrue(decoded.decodeReport.isClean, "\(name): a defaulted transform is not a dropped element")
        }
    }

    // MARK: - The stored transform is advisory (TODO item (12) stage 3)

    /// **A stored transform is baked into the geometry on the way in, and the cel loads at identity.**
    ///
    /// Every document on the owner's iPad that has ever touched the Canvas Padding slider carries a
    /// non-identity entry on *every* cel of *every* layer, because `setCanvasPadding` walks the whole
    /// document — so this is not a hypothetical shape of file. Baking it is what makes a persisted
    /// sample a canvas coordinate, which is the precondition TODO item (8) is blocked on.
    ///
    /// The fixture is the shape `resized(to:offset:)` used to write: a pure translation.
    func testAStoredTransformIsBakedIntoTheGeometryAndTheCelLoadsAtIdentity() throws {
        var object = try jsonObject(healthyPayload())
        object["transform"] = [1, 0, 0, 1, 12, -7]

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: try jsonData(object))
        XCTAssertEqual(decoded.affineTransform.tx, 12, "fixture precondition: the file says +12")

        let placed = solidImage(.green)
        let baked = decoded.canvasSpaceElements(resolvingImages: { _ in placed },
                                                resolvingVideos: { _ in nil })
        let canvas = VectorCanvas(size: Self.canvasSize, elements: baked)

        XCTAssertTrue(canvas.transform.isIdentity, "the cel itself must carry nothing")
        XCTAssertEqual(kinds(baked), ["fill", "image", "stroke", "erase"], "and nothing is lost to the bake")

        // The stroke's samples sat at (32, 32); +12/-7 in canvas space puts them at (44, 25).
        let sample = try XCTUnwrap(baked.compactMap(\.stroke).first?.samples.first)
        XCTAssertEqual(sample.x, 44, accuracy: 1e-9)
        XCTAssertEqual(sample.y, 25, accuracy: 1e-9)
        // A placed image is a pose, and it travels whole.
        let image = try XCTUnwrap(baked.compactMap(\.image).first)
        XCTAssertEqual(image.transform.position.x, 44, accuracy: 1e-9)
        XCTAssertEqual(image.transform.position.y, 25, accuracy: 1e-9)
        XCTAssertEqual(image.transform.scale, 1, accuracy: 1e-9, "a translation changes no size")

        // Local geometry, un-baked, would have left the samples where the file put them. Stated so a
        // future reader can see the assertion above is about the bake and not about the fixture.
        let unbaked = VectorCanvas(size: Self.canvasSize, elements: baked, transform: decoded.affineTransform)
        XCTAssertFalse(unbaked.transform.isIdentity, "control: this is the shape the load path no longer builds")
    }

    /// **Nothing writes the key any more**, so a build that predates stage 3 opening a file this one
    /// wrote finds no transform, defaults to identity, and draws the baked geometry — the correct
    /// picture, with no version gap in either direction. Written as the absence it is rather than as
    /// `[1,0,0,1,0,0]`: `affineTransform` has always answered identity for a key that is not six
    /// numbers, so leaving it out costs 48 bytes a cel less and means the same thing.
    func testEncodingWritesNoTransformKeyAtAll() throws {
        let written = try jsonObject(healthyPayload())
        XCTAssertNil(written["transform"], "the field is decode-only now")
        XCTAssertNotNil(written["elements"], "fixture precondition: this is still a real payload")

        let round = try JSONDecoder().decode(VectorCanvasData.self,
                                             from: try JSONEncoder().encode(healthyPayload()))
        XCTAssertTrue(round.affineTransform.isIdentity)
        XCTAssertEqual(kinds(round.elements), ["fill", "image", "stroke", "erase"])
    }

    /// **A canvas handed to the payload still carrying a transform has it baked, not dropped.** Only
    /// a test can build one now — no app path writes `_transform` — but "the encoder silently lost
    /// geometry the canvas was holding" is exactly the failure this whole file exists about, so the
    /// encode half asserts the same identity as the decode half.
    func testEncodingBakesATransformTheCanvasWasStillCarrying() throws {
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: [stroke(1)],
                                  transform: CGAffineTransform(translationX: 5, y: 9))
        let payload = VectorCanvasData(from: canvas, imageFileNames: [:])

        XCTAssertTrue(payload.affineTransform.isIdentity, "the payload records no transform")
        let sample = try XCTUnwrap(payload.elements.compactMap {
            if case .stroke(let s) = $0 { return s } else { return nil }
        }.first?.samples.first)
        XCTAssertEqual(sample.x, 37, accuracy: 1e-9, "the geometry carries it instead")
        XCTAssertEqual(sample.y, 41, accuracy: 1e-9)
    }

    /// **`resized(to:placing:)` bakes its shift, so `setCanvasPadding` stops being a producer of
    /// non-identity cel transforms** — the other half of stage 3, and the one that makes the claim
    /// "no path in this app writes a cel transform" true rather than nearly true.
    ///
    /// Exact by construction: a translation moves no sample onto a different sub-pixel and re-stamps
    /// nothing, so none of `mapping`'s three floors can bind.
    func testResizingBakesTheShiftIntoTheGeometryInsteadOfCarryingIt() throws {
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: [stroke(1)], fills: [fill(1)])
        let grown = canvas.resized(to: CGSize(width: 128, height: 128),
                                   placing: CGRect(origin: CGPoint(x: 32, y: 32), size: Self.canvasSize))

        XCTAssertTrue(grown.transform.isIdentity,
                      "a padded cel must not carry a translation — that is what clipped later ink")
        XCTAssertEqual(grown.size, CGSize(width: 128, height: 128))
        XCTAssertEqual(kinds(grown.elements), ["fill", "stroke"], "z-order survives the map")

        let sample = try XCTUnwrap(grown.elements.compactMap(\.stroke).first?.samples.first)
        XCTAssertEqual(sample.x, 64, accuracy: 1e-9)
        XCTAssertEqual(sample.y, 64, accuracy: 1e-9)
        XCTAssertEqual(sample.pressure, 1, accuracy: 1e-9, "pressure is not geometry")

        let fillBox = try XCTUnwrap(grown.elements.compactMap(\.fill).first?.cgPath?.boundingBoxOfPath)
        XCTAssertEqual(fillBox.minX, 32, accuracy: 1e-6)
        XCTAssertEqual(fillBox.minY, 32, accuracy: 1e-6)

        // The stroke's own width is untouched: this is a translation, so `mapping`'s width scale is 1.
        XCTAssertEqual(try XCTUnwrap(grown.elements.compactMap(\.stroke).first).size, 20, accuracy: 1e-9)
    }
}
