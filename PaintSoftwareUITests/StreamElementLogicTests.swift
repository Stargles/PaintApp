import XCTest
import UIKit

/// Pure-logic tests for `VectorStreamElement` — STREAM.md stage 1, the sixth `VectorElement`.
///
/// **The model and the picture, no socket.** The element persists and round-trips through real
/// JSON bytes; `displayFrame` does not; a document with no stream decodes to the bytes it had; and
/// what is *drawn* — the placeholder in the element's own rectangle, then the frame in the identical
/// rectangle once one arrives — is asserted on pixels rather than on stored fields, because CLAUDE.md
/// has three cases of a correct model behind an unusable feature.
///
/// The frame path is the interesting one. `VectorCanvas.setStreamFrame(id:image:)` is the one seam a
/// live frame comes through, and it makes two claims a test can check without a network: the render
/// changes (the tick must repaint) and `committedVersion` does not (the bake must not). Both are
/// pinned here, the second by mutation — the version is compared before and after, and a
/// `setStreamFrame` that reached `invalidate(.everything)` would move it.
@MainActor
final class StreamElementLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 64, height: 64)

    // MARK: - Fixtures

    /// Every field at its default, so a round-trip row passing on a default is impossible once the
    /// mutation table has moved each one.
    private func defaultElement() -> VectorStreamElement {
        VectorStreamElement(naturalSize: CGSize(width: 32, height: 18),
                            host: "laptop", port: 47301, sourceLabel: "monitor",
                            transform: LayerTransform(position: .zero, scale: 1, rotation: 0))
    }

    /// One row per persisted field: a mutation off the default, and a reader for the comparison.
    private struct StoredField {
        let name: String
        let mutate: (inout VectorStreamElement) -> Void
        let read: (VectorStreamElement) -> String
    }

    private var storedFields: [StoredField] {
        [
            StoredField(name: "naturalSize", mutate: { $0.naturalSize = CGSize(width: 1920, height: 1080) },
                        read: { "\($0.naturalSize)" }),
            StoredField(name: "host", mutate: { $0.host = "desktop-cbr0fl6" }, read: \.host),
            StoredField(name: "port", mutate: { $0.port = 5000 }, read: { "\($0.port)" }),
            StoredField(name: "sourceLabel", mutate: { $0.sourceLabel = "Blender" }, read: \.sourceLabel),
            StoredField(name: "isFrozen", mutate: { $0.isFrozen = true }, read: { "\($0.isFrozen)" }),
            StoredField(name: "lastFrameFileName", mutate: { $0.lastFrameFileName = "last.jpg" },
                        read: { $0.lastFrameFileName ?? "nil" }),
            StoredField(name: "position", mutate: { $0.transform.position = CGPoint(x: 12.5, y: -3.25) },
                        read: { "\($0.transform.position)" }),
            StoredField(name: "scale", mutate: { $0.transform.scale = 0.375 }, read: { "\($0.transform.scale)" }),
            StoredField(name: "rotation", mutate: { $0.transform.rotation = 0.75 }, read: { "\($0.transform.rotation)" }),
            StoredField(name: "aspect", mutate: { $0.aspect = 1.5 }, read: { "\($0.aspect)" }),
            StoredField(name: "stretchAxis", mutate: { $0.stretchAxis = 0.25 }, read: { "\($0.stretchAxis)" }),
            StoredField(name: "mirrored", mutate: { $0.mirrored = true }, read: { "\($0.mirrored)" }),
            StoredField(name: "animationGroupID", mutate: { $0.animationGroupID = UUID() },
                        read: { $0.animationGroupID?.uuidString ?? "nil" }),
        ]
    }

    /// Encode through the real payload type and real JSON bytes, decode, rebuild — `ProjectStore`'s
    /// exact path minus the file system.
    private func roundTrip(_ element: VectorStreamElement) throws -> (VectorStreamElement, Data) {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(element)])
        let payload = VectorCanvasData(from: canvas, imageFileNames: [:])
        let data = try JSONEncoder().encode(payload)
        let reloaded = try JSONDecoder().decode(VectorCanvasData.self, from: data)
        XCTAssertTrue(reloaded.decodeReport.isClean,
                      "The payload must decode clean: \(reloaded.decodeReport)")
        XCTAssertEqual(reloaded.streams.count, 1,
                       "It has to come back under the `stream` discriminator, not as an unknown kind")
        let rebuilt = reloaded.canvasSpaceElements(resolvingImages: { _ in nil },
                                                   resolvingVideos: { _ in nil })
        return (try XCTUnwrap(rebuilt.compactMap(\.stream).first,
                              "The stream did not come back as a stream element"), data)
    }

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// A closure answering the RGBA at a canvas point, so a pixel assertion reads as a coordinate.
    private func pixels(_ image: UIImage) -> ((Int, Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8))? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / Self.canvasSize.width
        return { x, y in
            let px = Int(CGFloat(x) * scale), py = Int(CGFloat(y) * scale)
            guard px >= 0, px < width, py >= 0, py < height else { return (0, 0, 0, 0) }
            let i = (py * width + px) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }
    }

    // MARK: - Persistence

    /// **Every persisted field, non-default, through real JSON bytes** — one fixture mutated
    /// cumulatively, `VideoElementLogicTests`' reason.
    func testEveryStoredFieldSurvivesEncodeAndDecode() throws {
        var element = defaultElement()
        for field in storedFields { field.mutate(&element) }

        let (decoded, _) = try roundTrip(element)

        for field in storedFields {
            XCTAssertEqual(field.read(decoded), field.read(element),
                           "\(field.name) did not survive the round trip")
        }
    }

    /// The complement: at least one row must be capable of failing.
    func testTheRoundTripFixtureDiffersFromADefaultElementInEveryField() {
        let plain = defaultElement()
        var mutated = plain
        for field in storedFields { field.mutate(&mutated) }
        for field in storedFields {
            XCTAssertNotEqual(field.read(mutated), field.read(plain),
                              "\(field.name) is at its default in the round-trip fixture")
        }
    }

    /// `displayFrame` is runtime-only. The bytes must not carry it, and the decoded element must
    /// come back with none — a stream opens on the placeholder until the laptop answers.
    func testTheDisplayFrameIsNotPersisted() throws {
        var element = defaultElement()
        element.displayFrame = solidImage(.red, size: CGSize(width: 4, height: 4))
        let (decoded, data) = try roundTrip(element)
        XCTAssertNil(decoded.displayFrame, "A decoded stream must start with no frame")
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("displayFrame"), "The frame must not reach the bytes")
        XCTAssertTrue(json.contains("\"kind\":\"stream\""), "The discriminator is `stream`: \(json)")
    }

    /// The id is a session handle, not a property of the source — `ImageRef` and `VideoRef` both
    /// leave it out and `localElements` mints a fresh one.
    func testTheElementIdIsNotPersisted() throws {
        let element = defaultElement()
        let (decoded, _) = try roundTrip(element)
        XCTAssertNotEqual(decoded.id, element.id)
    }

    /// A document with no stream in it writes exactly the bytes it wrote before this element
    /// existed — the `stream` key appears nowhere, and the payload decodes to the same elements.
    func testADocumentWithNoStreamDecodesUnchanged() throws {
        let stroke = VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 4, opacity: 1,
                                  samples: [VectorSample(x: 2, y: 2, pressure: 1),
                                            VectorSample(x: 6, y: 6, pressure: 1)],
                                  composite: .paint)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stroke(stroke)])
        let data = try JSONEncoder().encode(VectorCanvasData(from: canvas, imageFileNames: [:]))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("stream"), "No stream key on a document with no stream: \(json)")
        let reloaded = try JSONDecoder().decode(VectorCanvasData.self, from: data)
        XCTAssertTrue(reloaded.decodeReport.isClean)
        XCTAssertEqual(reloaded.streams.count, 0)
        XCTAssertEqual(reloaded.strokes.count, 1)
        XCTAssertFalse(canvas.holdsStream)
    }

    // MARK: - What is drawn

    /// **The placeholder fills the element's own rectangle and nothing else.** Inside the placed
    /// rect there is ink; outside it there is none — the assertion that distinguishes "drawn where
    /// the element says" from "something was drawn".
    func testThePlaceholderFillsTheElementsOwnRectangleAndNothingElse() throws {
        var stream = defaultElement()
        stream.naturalSize = CGSize(width: 20, height: 10)
        stream.transform = LayerTransform(position: CGPoint(x: 20, y: 20), scale: 1, rotation: 0)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])

        let at = try XCTUnwrap(pixels(canvas.render()))
        XCTAssertGreaterThan(at(20, 20).a, 0, "the placeholder's own centre")
        XCTAssertGreaterThan(at(12, 17).a, 0, "inside the rectangle, off centre")
        XCTAssertEqual(at(20, 34).a, 0, "below the rectangle")
        XCTAssertEqual(at(50, 20).a, 0, "beside the rectangle")
        XCTAssertEqual(at(2, 2).a, 0, "the corner of the canvas")
    }

    /// **A frame arriving is drawn in the identical rectangle, and the picture changes.** The
    /// placeholder is grey; the frame is solid green; the same pixel reads grey before and green
    /// after, and a pixel outside the rectangle stays clear both times. This is the assertion that
    /// would go red if `setStreamFrame` wrote the frame and nothing redrew it.
    func testAFrameArrivingReplacesThePlaceholderInTheSameRectangle() throws {
        var stream = defaultElement()
        stream.naturalSize = CGSize(width: 20, height: 10)
        stream.transform = LayerTransform(position: CGPoint(x: 20, y: 20), scale: 1, rotation: 0)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])

        let before = try XCTUnwrap(pixels(canvas.render()))
        let placeholder = before(20, 20)
        XCTAssertGreaterThan(placeholder.a, 0)
        XCTAssertEqual(placeholder.g, placeholder.r, accuracy: 8, "the placeholder is grey, not green")

        let green = solidImage(.green, size: CGSize(width: 20, height: 10))
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green), "the element must be found")

        let after = try XCTUnwrap(pixels(canvas.render()))
        let frame = after(20, 20)
        XCTAssertEqual(frame.a, 255, "the frame is opaque where the placeholder was translucent")
        XCTAssertGreaterThan(Int(frame.g), Int(frame.r) + 100, "the frame's green reached the pixel")
        XCTAssertGreaterThan(after(12, 17).g, 200, "inside the rectangle, off centre")
        XCTAssertEqual(after(20, 34).a, 0, "below the rectangle — the frame did not grow the rect")
        XCTAssertEqual(after(50, 20).a, 0, "beside the rectangle")
    }

    /// A frame for an id that is not a stream on this canvas is refused, and nothing moves.
    func testAFrameForAnUnknownIdIsRefused() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(defaultElement())])
        let version = canvas.version
        XCTAssertFalse(canvas.setStreamFrame(id: UUID(), image: solidImage(.red, size: CGSize(width: 2, height: 2))))
        XCTAssertEqual(canvas.version, version, "A refused write moves nothing")
    }

    // MARK: - The bake key stays still

    /// **A frame moves `version` and not `committedVersion`.** The first is what the layer host and
    /// the render memo key on, so the tick repaints; the second is what `LayerContentVersion` and
    /// so the frame bake key read, so the tick does not re-bake the stream cel's span to disk. A
    /// `setStreamFrame` routed through `invalidate(.everything)` — the ordinary mutation seam —
    /// would move both and this would go red.
    func testAFrameMovesTheDisplayVersionAndNotTheCommittedVersion() {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        let version = canvas.version
        let committed = canvas.committedVersion

        canvas.setStreamFrame(id: stream.id, image: solidImage(.red, size: CGSize(width: 2, height: 2)))

        XCTAssertGreaterThan(canvas.version, version, "the display is stale and must say so")
        XCTAssertEqual(canvas.committedVersion, committed, "the bake must not see a live frame")
    }

    /// The complement, so the test above cannot pass on a `committedVersion` that never moves: an
    /// ordinary edit moves both counters together.
    func testAnOrdinaryEditMovesBothVersions() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(defaultElement())])
        let version = canvas.version
        let committed = canvas.committedVersion
        canvas.bumpVersion()
        XCTAssertGreaterThan(canvas.version, version)
        XCTAssertGreaterThan(canvas.committedVersion, committed)
    }

    /// `LayerContentVersion` — the bake key's leaf half — is byte-identical across a frame and
    /// differs across an edit. The stream cel's bake key is what stays still at the tick rate.
    func testTheLayerContentVersionIsBlindToAFrameAndNotToAnEdit() {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 4,
                      raster: .empty(size: Self.canvasSize), vector: canvas)
        let before = LayerContentVersion(cel: cel)

        canvas.setStreamFrame(id: stream.id, image: solidImage(.red, size: CGSize(width: 2, height: 2)))
        XCTAssertEqual(LayerContentVersion(cel: cel), before, "a frame is not a bake-visible change")

        canvas.bumpVersion()
        XCTAssertNotEqual(LayerContentVersion(cel: cel), before, "an edit is")
    }

    // MARK: - A suppressed element

    /// While the Move box holds the element, the walk skips it, so the memo's picture is right and
    /// a frame must not invalidate it — the coordinator refreshes the float's bitmap instead. The
    /// frame is still written, so the commit draws the newest one.
    func testAFrameForASuppressedElementIsStoredWithoutInvalidating() throws {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        canvas.suppressedElementIDs = [stream.id]
        let version = canvas.version

        let green = solidImage(.green, size: CGSize(width: 2, height: 2))
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green))

        XCTAssertEqual(canvas.version, version, "nothing in the picture changed")
        XCTAssertTrue(try XCTUnwrap(canvas.streams.first).displayFrame === green,
                      "the frame is held for the commit")
    }

    // MARK: - The placed-rectangle arms

    /// A stream follows a similarity exactly as a video does — the same six fields through the
    /// same arm — so the Move box moves it without a stream-specific line anywhere.
    func testAStreamFollowsASimilarityAsAVideoDoes() throws {
        var stream = defaultElement()
        stream.transform = LayerTransform(position: CGPoint(x: 10, y: 10), scale: 1, rotation: 0)
        let t = CGAffineTransform(translationX: 5, y: 7).scaledBy(x: 2, y: 2)
        let mapped = try XCTUnwrap(VectorCanvas.mapping(.stream(stream), throughSimilarity: t).stream)
        XCTAssertEqual(mapped.transform.position.x, 25, accuracy: 1e-9)
        XCTAssertEqual(mapped.transform.position.y, 27, accuracy: 1e-9)
        XCTAssertEqual(mapped.transform.scale, 2, accuracy: 1e-9)
    }

    /// `holdsStream` is memoized against `contentVersion` like `holdsVideo`, and answers for the
    /// display list as it is now.
    func testHoldsStreamFollowsTheDisplayList() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [])
        XCTAssertFalse(canvas.holdsStream)
        canvas.elements = [.stream(defaultElement())]
        canvas.bumpVersion()
        XCTAssertTrue(canvas.holdsStream)
        canvas.elements = []
        canvas.bumpVersion()
        XCTAssertFalse(canvas.holdsStream)
    }
}
