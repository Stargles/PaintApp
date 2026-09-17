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
/// The frame path is the interesting one. `VectorCanvas.setStreamFrame(id:image:index:)` is the one seam a
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
        element.picture = StreamPicture(frame: solidImage(.red, size: CGSize(width: 4, height: 4)))
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
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green, index: 1), "the element must be found")

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
        XCTAssertFalse(canvas.setStreamFrame(id: UUID(), image: solidImage(.red, size: CGSize(width: 2, height: 2)), index: 1))
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

        canvas.setStreamFrame(id: stream.id, image: solidImage(.red, size: CGSize(width: 2, height: 2)), index: 1)

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

        canvas.setStreamFrame(id: stream.id, image: solidImage(.red, size: CGSize(width: 2, height: 2)), index: 1)
        XCTAssertEqual(LayerContentVersion(cel: cel), before, "a frame is not a bake-visible change")

        canvas.bumpVersion()
        XCTAssertNotEqual(LayerContentVersion(cel: cel), before, "an edit is")
    }

    // MARK: - A suppressed element

    /// While the Move box holds the element, the walk skips it, so the memo's picture is right and
    /// a frame must not invalidate it — the float's own surface presents it instead. The frame is
    /// still written, so the commit draws the newest one.
    func testAFrameForASuppressedElementIsStoredWithoutInvalidating() throws {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        canvas.suppressedElementIDs = [stream.id]
        let version = canvas.version

        let green = solidImage(.green, size: CGSize(width: 2, height: 2))
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green, index: 1))

        XCTAssertEqual(canvas.version, version, "nothing in the picture changed")
        XCTAssertTrue(try XCTUnwrap(canvas.streams.first).displayFrame === green,
                      "the frame is held for the commit")
    }

    // MARK: - The window a live frame is presented in (TODO (97))

    /// A bitmap context of `window`'s size set up the way `StreamSurfaceView` sets its surface up —
    /// UIKit-flipped, current, origin at the window's corner — and a reader of its pixels after
    /// `draw` has run in it.
    private func drawWindow(_ window: CGRect, _ draw: (CGContext) -> Void)
        -> (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = Int(window.width), height = Int(window.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let cg = CGContext(data: buffer.baseAddress, width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            cg.translateBy(x: 0, y: CGFloat(height))
            cg.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(cg)
            draw(cg)
            UIGraphicsPopContext()
        }
        return { x, y in
            let i = (y * width + x) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }
    }

    /// **The window is the frame's pixels and the ink over them, at the window's own origin, and
    /// drawing it rasterizes nothing canvas-sized.** A green frame under a red fill: the window's
    /// centre is red (z-order), a corner inside the frame is green, `rasterizations` stands still
    /// and `streamWindowDraws` moves — the count a live stream is charged per frame.
    func testTheWindowDrawsTheFrameAndTheInkOverItWithoutACanvasSizedRender() throws {
        var stream = defaultElement()
        stream.naturalSize = CGSize(width: 20, height: 10)
        stream.transform = LayerTransform(position: CGPoint(x: 30, y: 30), scale: 1, rotation: 0)
        let over = VectorFillElement(path: CGPath(rect: CGRect(x: 27, y: 27, width: 6, height: 6),
                                                  transform: nil),
                                     color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), opacity: 1)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream), .fill(over)])
        canvas.setStreamFrame(id: stream.id, image: solidImage(.green, size: CGSize(width: 20, height: 10)),
                              index: 1)
        _ = canvas.render()
        let rasterizations = canvas.rasterizations
        let version = canvas.version

        let window = try XCTUnwrap(canvas.streamWindow(id: stream.id))
        XCTAssertEqual(window, CGRect(x: 18, y: 23, width: 24, height: 14), "the footprint, integral")
        let px = drawWindow(window) { cg in
            XCTAssertEqual(canvas.drawStreamWindow(id: stream.id, into: cg), window)
        }

        let centre = px(12, 7)
        XCTAssertGreaterThan(Int(centre.r), Int(centre.g) + 100, "the fill is over the frame")
        let corner = px(3, 3)
        XCTAssertGreaterThan(Int(corner.g), Int(corner.r) + 100, "the frame is where nothing covers it")
        XCTAssertEqual(corner.a, 255)
        XCTAssertEqual(canvas.rasterizations, rasterizations, "no canvas-sized render")
        XCTAssertEqual(canvas.streamWindowDraws, 1)
        XCTAssertEqual(canvas.version, version, "a display, not an invalidation")
    }

    /// **Clipped to the quad, not the box**: a turned stream's window is its bounding box, and the
    /// corners of that box outside the turned rectangle stay transparent — so the surface composites
    /// over the layer's own picture there without drawing any ink twice.
    func testATurnedStreamsWindowIsTransparentOutsideItsQuad() throws {
        var stream = defaultElement()
        stream.naturalSize = CGSize(width: 24, height: 8)
        stream.transform = LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: .pi / 4)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        canvas.setStreamFrame(id: stream.id, image: solidImage(.green, size: CGSize(width: 24, height: 8)),
                              index: 1)
        let window = try XCTUnwrap(canvas.streamWindow(id: stream.id))
        let px = drawWindow(window) { cg in
            XCTAssertEqual(canvas.drawStreamWindow(id: stream.id, into: cg), window)
        }
        let mid = px(Int(window.width / 2), Int(window.height / 2))
        XCTAssertEqual(mid.a, 255, "the frame at the centre")
        XCTAssertEqual(px(1, 1).a, 0, "a corner of the box is outside the turned rectangle")
        XCTAssertEqual(px(Int(window.width) - 2, 1).a, 0)
    }

    /// The Move box's case: the lifted ids alone, as the float shows them. A second element that is
    /// not lifted is not in the window even where it overlaps.
    func testAnIsolatedWindowDrawsTheLiftedIdsAlone() throws {
        var stream = defaultElement()
        stream.naturalSize = CGSize(width: 20, height: 10)
        stream.transform = LayerTransform(position: CGPoint(x: 30, y: 30), scale: 1, rotation: 0)
        let other = VectorFillElement(path: CGPath(rect: CGRect(x: 27, y: 27, width: 6, height: 6),
                                                   transform: nil),
                                      color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), opacity: 1)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream), .fill(other)])
        canvas.setStreamFrame(id: stream.id, image: solidImage(.green, size: CGSize(width: 20, height: 10)),
                              index: 1)
        canvas.suppressedElementIDs = [stream.id]
        let window = try XCTUnwrap(canvas.streamWindow(id: stream.id))
        let px = drawWindow(window) { cg in
            XCTAssertEqual(canvas.drawStreamWindow(id: stream.id, into: cg, isolating: [stream.id]), window)
        }
        let centre = px(12, 7)
        XCTAssertGreaterThan(Int(centre.g), Int(centre.r) + 100, "the frame, with the unlifted fill left out")
    }

    /// An id that is not a stream here has no window and draws nothing.
    func testAnUnknownIdHasNoWindow() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(defaultElement())])
        XCTAssertNil(canvas.streamWindow(id: UUID()))
        _ = drawWindow(CGRect(x: 0, y: 0, width: 4, height: 4)) { cg in
            XCTAssertNil(canvas.drawStreamWindow(id: UUID(), into: cg))
        }
        XCTAssertEqual(canvas.streamWindowDraws, 0)
    }

    // MARK: - The picture is shared by every copy of the element

    /// **An undo step's copy of the list pins no frame of its own.** A stream element copied into a
    /// snapshot shares the live element's `StreamPicture`, so a frame written after the copy is the
    /// copy's frame too — and the decoder's pool buffer the frame wraps is held once, not once per
    /// step. Without the box every `[VectorElement]` an undo step held while the laptop streamed
    /// kept a 1080p buffer alive for the life of the stack.
    func testACopiedElementSharesThePictureRatherThanPinningItsOwn() throws {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        let snapshot = canvas.elements
        let green = solidImage(.green, size: CGSize(width: 2, height: 2))
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green, index: 1))
        XCTAssertTrue(try XCTUnwrap(snapshot.first?.stream).displayFrame === green,
                      "the copy shows what the element shows")
        canvas.elements = snapshot
        canvas.bumpVersion()
        XCTAssertTrue(try XCTUnwrap(canvas.streams.first).displayFrame === green,
                      "and an undo puts back the newest picture, not the one from before the edit")
    }

    /// **A freeze detaches the picture**: the frozen element keeps the frame it froze on while a
    /// copy that shares nothing with it any more — the far cel of a bake — goes on receiving.
    func testAFreezeGivesTheElementAPictureOfItsOwn() throws {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        let far = VectorCanvas(size: Self.canvasSize, elements: canvas.elements)
        let green = solidImage(.green, size: CGSize(width: 2, height: 2))
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green, index: 1))
        XCTAssertTrue(canvas.setStreamFrozen(id: stream.id, true))
        let red = solidImage(.red, size: CGSize(width: 2, height: 2))
        XCTAssertTrue(far.setStreamFrame(id: stream.id, image: red, index: 2))
        XCTAssertTrue(try XCTUnwrap(canvas.streams.first).displayFrame === green, "frozen on green")
        XCTAssertTrue(try XCTUnwrap(far.streams.first).displayFrame === red, "the far cel moved on")
    }

    /// A canvas told about a frame index answers false to the same index again, and nothing moves —
    /// the tick's "unchanged slot costs nothing"; a canvas that shares the box but has not been told
    /// still answers true, so its own memo is invalidated (TODO (96) through the box).
    func testACanvasIsToldAboutAFrameOnce() throws {
        let stream = defaultElement()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stream(stream)])
        let far = VectorCanvas(size: Self.canvasSize, elements: canvas.elements)
        let green = solidImage(.green, size: CGSize(width: 2, height: 2))
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id, image: green, index: 1))
        let version = canvas.version
        XCTAssertFalse(canvas.setStreamFrame(id: stream.id, image: green, index: 1))
        XCTAssertEqual(canvas.version, version)
        let farVersion = far.version
        XCTAssertTrue(far.setStreamFrame(id: stream.id, image: green, index: 1), "the box was written; this memo was not told")
        XCTAssertGreaterThan(far.version, farVersion)
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
