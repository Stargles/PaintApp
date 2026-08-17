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
        Brush(name: "Test", shape: .hardRound, size: 20, opacity: 1, flow: 1,
              spacingFraction: 0.1, hardness: 1, stabilization: 0, scatter: 0,
              rotationJitter: 0, dynamics: .fixed, grain: .disabled, blendMode: .normal)
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
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    private func kinds(_ elements: [VectorElement]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
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
            case .image(let ref): return ref.fileName
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
                         transform: [1, 0, 0, 1, 0, 0])
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
    /// writing a new element type produces. `ADD_TEXT.md` ships exactly this.
    private var futureElement: [String: Any] {
        ["kind": "text", "text": ["string": "hello", "fontName": "Helvetica", "pointSize": 24]]
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
        let elements = decoded.elements { _ in placed }
        let canvas = VectorCanvas(size: Self.canvasSize, elements: elements, transform: decoded.affineTransform)

        XCTAssertEqual(kinds(canvas.elements), ["fill", "image", "erase"])
        XCTAssertFalse(canvas.isEmpty, "A cel that lost one element is not an empty cel")
        XCTAssertTrue(canvas.transform.isIdentity)
    }

    // MARK: - Unknown kind vs corrupt known kind

    /// The case this fix exists ahead of: an older build opening a project that contains an element
    /// type it has never heard of. Expected, benign, and it must cost that element only.
    func testAnUnknownKindCostsOnlyThatElement() throws {
        let payload = healthyPayload()
        let expected = ids(payload.elements)
        let data = try payloadJSON(payload, replacingElementAt: 1, with: futureElement)

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(ids(decoded.elements), [expected[0], expected[2], expected[3]])
        XCTAssertEqual(kinds(decoded.elements), ["fill", "stroke", "erase"])
        XCTAssertEqual(decoded.decodeReport.unknownKinds, ["text"],
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
        XCTAssertEqual(decoded.decodeReport.unknownKinds, ["text"])
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
    /// elements, same identities, same order, same transform, clean report — and re-encoding produces
    /// byte-identical JSON, so the tolerant decode did not quietly rewrite anyone's project.
    func testAWellFormedPayloadRoundTripsUnchanged() throws {
        let payload = healthyPayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)

        XCTAssertEqual(ids(decoded.elements), ids(payload.elements))
        XCTAssertEqual(kinds(decoded.elements), ["fill", "image", "stroke", "erase"])
        XCTAssertEqual(decoded.transform, payload.transform)
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

    /// A missing transform costs the transform, not the drawing — `affineTransform` has always
    /// answered `.identity` for anything that is not six numbers, and now the decode agrees with it.
    func testAMissingTransformLoadsAsIdentityRatherThanCostingTheElements() throws {
        var object = try jsonObject(healthyPayload())
        object.removeValue(forKey: "transform")

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: try jsonData(object))

        XCTAssertEqual(decoded.elements.count, 4, "Every element survives a transform that would not read")
        XCTAssertTrue(decoded.affineTransform.isIdentity)
        XCTAssertTrue(decoded.decodeReport.isClean, "A defaulted transform is not a dropped element")
    }
}
