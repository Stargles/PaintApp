import XCTest
import UIKit

/// Pure-logic tests for `VectorVideoElement` — VIDEO.md stage 2, the fifth `VectorElement`.
///
/// **Stage 2 is the model and nothing else**: the element persists, round-trips, degrades when its
/// asset is gone, and renders a placeholder. There is no decoder here and no `AVFoundation` import,
/// which is why the fixture's "video" is a handful of bytes with a `.mov` name — the load path checks
/// that a file *is there*, never that it plays, and pinning that distinction is half the point of
/// `testAnUnplayableAssetIsStillAnAssetAtLoad`.
///
/// The persistence half runs against real packages written by `ProjectStore.save` and reopened by
/// `ProjectStore.load`, the way `SaveDamageGateLogicTests` does: a test that hands
/// `VectorCanvasData` a hand-built payload proves the codec round-trips and proves nothing about
/// whether the asset ever reached the package.
///
/// `Engine/VectorLayer.swift`, `Services/ProjectStore.swift` and `Services/SaveDamageGate.swift` are
/// compiled into this test target directly — see `BrushEngineLogicTests`' header for why
/// `@testable import` cannot work here.
@MainActor
final class VideoElementLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 64, height: 64)

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-element-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Fixtures

    /// A file that exists and is not a video. Stage 2 never opens it, and a fixture that pretended
    /// otherwise would be claiming coverage of a decoder that does not exist yet.
    private func writeAsset(named name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("not a video, and stage 2 never asks".utf8).write(to: url)
        return url
    }

    /// **Every field at its default**, so a round-trip row that passes without the encoder carrying
    /// its field would have to be passing on a default rather than on the value it names. The
    /// mutations in `storedFields` move each one off its default exactly once.
    private func defaultElement(assetURL: URL) -> VectorVideoElement {
        VectorVideoElement(assetURL: assetURL, assetFileName: assetURL.lastPathComponent,
                           naturalSize: CGSize(width: 32, height: 18),
                           sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1),
                           speed: 1,
                           transform: LayerTransform(position: CGPoint(x: 0, y: 0), scale: 1,
                                                     rotation: 0))
    }

    private func stroke() -> VectorStroke {
        VectorStroke(brush: Brush(name: "Test", tip: .round, size: 8, opacity: 1, flow: 1,
                                  spacingFraction: 0.1, hardness: 1, stabilization: 0, scatter: 0,
                                  rotationJitter: 0, dynamics: .fixed,
                                  blendMode: .normal),
                     color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: 8, opacity: 1,
                     samples: [VectorSample(x: 4, y: 4, pressure: 1),
                               VectorSample(x: 30, y: 30, pressure: 1)])
    }

    private func fill() -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(x: 0, y: 0, width: 8, height: 8), transform: nil),
                          color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
    }

    // MARK: - The round trip

    /// One row per stored field: how to move it off its default, and how to read it back as a string
    /// so a failure names the field and prints both values.
    private struct StoredField {
        let name: String
        let mutate: (inout VectorVideoElement) -> Void
        let read: (VectorVideoElement) -> String
    }

    /// **Every field VIDEO.md §4.1 puts on the element, plus the natural size §4.1 forgot.**
    ///
    /// Each value is distinct from every other value in the table, which is what makes a *swapped*
    /// pair of keys in the encoder visible as well as a dropped one: `sourceStart` and `sourceEnd`
    /// exchanged would satisfy any assertion that only checked "the pair came back".
    private var storedFields: [StoredField] {
        [
            StoredField(name: "assetFileName",
                        mutate: { $0.assetFileName = "renamed-clip.mov" },
                        read: { $0.assetFileName }),
            StoredField(name: "naturalSize",
                        mutate: { $0.naturalSize = CGSize(width: 1920, height: 1080) },
                        read: { "\($0.naturalSize.width)x\($0.naturalSize.height)" }),
            StoredField(name: "sourceStart",
                        mutate: { $0.sourceStart = SourceTime(value: 47, timescale: 30) },
                        read: { "\($0.sourceStart.value)/\($0.sourceStart.timescale)" }),
            StoredField(name: "sourceEnd",
                        mutate: { $0.sourceEnd = SourceTime(value: 953, timescale: 24) },
                        read: { "\($0.sourceEnd.value)/\($0.sourceEnd.timescale)" }),
            StoredField(name: "speed",
                        mutate: { $0.speed = 2.5 },
                        read: { "\($0.speed)" }),
            StoredField(name: "transform.position",
                        mutate: { $0.transform.position = CGPoint(x: 11, y: -7) },
                        read: { "\($0.transform.position.x),\($0.transform.position.y)" }),
            StoredField(name: "transform.scale",
                        mutate: { $0.transform.scale = 1.75 },
                        read: { "\($0.transform.scale)" }),
            StoredField(name: "transform.rotation",
                        mutate: { $0.transform.rotation = 0.3 },
                        read: { "\($0.transform.rotation)" }),
            StoredField(name: "aspect",
                        mutate: { $0.aspect = 1.4 },
                        read: { "\($0.aspect)" }),
            StoredField(name: "stretchAxis",
                        mutate: { $0.stretchAxis = 0.9 },
                        read: { "\($0.stretchAxis)" }),
            StoredField(name: "mirrored",
                        mutate: { $0.mirrored = true },
                        read: { "\($0.mirrored)" }),
            StoredField(name: "animationGroupID",
                        mutate: { $0.animationGroupID = UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0") },
                        read: { $0.animationGroupID?.uuidString ?? "nil" }),
        ]
    }

    /// **The load-bearing one. Every stored field, non-default, through real JSON bytes.**
    ///
    /// **One fixture mutated cumulatively, not one fixture per row.** A per-row table would build a
    /// fresh element for each field and compare it against a fresh decode, and this repo has already
    /// shipped one of those: it passed with the field under test deleted from the encoder, because
    /// the two sides were separately-allocated defaults that agreed by accident. Here the *same*
    /// element accumulates every mutation and is encoded once at the end, so a field the encoder
    /// drops comes back as its default and disagrees with the mutation that set it.
    ///
    /// If a row goes red the code is wrong in one exact way: `VectorCanvasData.init(from:)` or
    /// `localElements(resolvingImages:resolvingVideos:)` is not carrying the field that row names,
    /// and a document that saved it loses it on the next open.
    func testEveryStoredFieldSurvivesEncodeAndDecode() throws {
        let asset = try writeAsset(named: "clip.mov")
        var element = defaultElement(assetURL: asset)
        for field in storedFields { field.mutate(&element) }

        let decoded = try roundTrip(element, resolvingTo: asset)

        for field in storedFields {
            XCTAssertEqual(field.read(decoded), field.read(element),
                           "\(field.name) did not survive the round trip")
        }
    }

    /// The complement, and it is what makes the test above mean anything: at least one row has to be
    /// **capable** of failing. A `VideoRef` built entirely from defaults would satisfy every
    /// assertion above by accident, so this states in the file that the fixture is not the default.
    func testTheRoundTripFixtureDiffersFromADefaultElementInEveryField() throws {
        let asset = try writeAsset(named: "clip.mov")
        let plain = defaultElement(assetURL: asset)
        var mutated = plain
        for field in storedFields { field.mutate(&mutated) }

        for field in storedFields {
            XCTAssertNotEqual(field.read(mutated), field.read(plain),
                              "\(field.name) is at its default in the round-trip fixture, so that "
                              + "row would pass whether or not the encoder carried it")
        }
    }

    /// `id` is deliberately **not** in the table above, and this says so rather than leaving its
    /// absence to be read as an oversight. A placed image's id is not persisted either — `ImageRef`
    /// has no id key and `localElements` mints a fresh one — and a video follows it, because the
    /// element's identity is a session-lifetime handle for the lasso and the undo stack, not a
    /// property of the footage.
    func testTheElementIdIsNotPersisted() throws {
        let asset = try writeAsset(named: "clip.mov")
        let element = defaultElement(assetURL: asset)
        let decoded = try roundTrip(element, resolvingTo: asset)
        XCTAssertNotEqual(decoded.id, element.id,
                          "A fresh id on load is the placed image's behaviour, and the fixture would "
                          + "not detect a change to it if this passed by coincidence")
    }

    /// Encode through the real payload type and real JSON bytes, then decode and resolve — the
    /// identical path `ProjectStore` takes, minus the file system.
    private func roundTrip(_ element: VectorVideoElement,
                           resolvingTo url: URL) throws -> VectorVideoElement {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.video(element)])
        let payload = VectorCanvasData(from: canvas, imageFileNames: [:])
        let data = try JSONEncoder().encode(payload)
        let reloaded = try JSONDecoder().decode(VectorCanvasData.self, from: data)
        XCTAssertTrue(reloaded.decodeReport.isClean,
                      "The payload itself must decode clean: \(reloaded.decodeReport)")
        XCTAssertEqual(reloaded.videos.count, 1,
                       "It has to come back under the `video` discriminator, not as an unknown kind "
                       + "the report quietly dropped — `isClean` above is true of an empty payload too")
        let rebuilt = reloaded.canvasSpaceElements(resolvingImages: { _ in nil },
                                                   resolvingVideos: { _ in url })
        return try XCTUnwrap(rebuilt.compactMap(\.video).first,
                             "The video did not come back as a video element")
    }

    // MARK: - SourceTime

    /// **`==` and `seconds` must agree**, or a crop compared one way and rendered the other way is
    /// two different crops. Normalising on construction is what makes them agree; if this goes red,
    /// `2/4` and `1/2` are different instants to the model and the same instant to the artist.
    func testEqualInstantsSpelledDifferentlyAreEqual() {
        XCTAssertEqual(SourceTime(value: 2, timescale: 4), SourceTime(value: 1, timescale: 2))
        XCTAssertEqual(SourceTime(value: 90, timescale: 30), SourceTime(value: 3, timescale: 1))
        XCTAssertEqual(SourceTime(value: 0, timescale: 600), SourceTime.zero)
        XCTAssertNotEqual(SourceTime(value: 1, timescale: 2), SourceTime(value: 1, timescale: 3))
        XCTAssertEqual(SourceTime(value: 47, timescale: 30).seconds, 47.0 / 30.0, accuracy: 1e-12)
    }

    /// A crop's *exactness* is the whole reason §4.1 stores rationals, so this pins the property
    /// rather than one arithmetic result: a value that is not representable in binary floating point
    /// comes back as the same pair of integers rather than as the nearest `Double`.
    func testAnUnrepresentableInstantRoundTripsExactly() throws {
        let asset = try writeAsset(named: "clip.mov")
        var element = defaultElement(assetURL: asset)
        // 1/30 s is not representable in binary; 30 frames at 1001/30000 is the NTSC clock.
        element.sourceStart = SourceTime(value: 1, timescale: 30)
        element.sourceEnd = SourceTime(value: 1001 * 900, timescale: 30000)

        let decoded = try roundTrip(element, resolvingTo: asset)

        XCTAssertEqual(decoded.sourceStart, element.sourceStart)
        XCTAssertEqual(decoded.sourceEnd, element.sourceEnd)
        XCTAssertEqual(decoded.sourceEnd.timescale, 30000 / 300,
                       "fixture precondition: the pair reduces, so this is testing the reduced form")
    }

    /// **A file is untrusted input and a timescale of zero is a division by zero.** It must cost the
    /// element and nothing else — the same contract every other unreadable payload gets — rather
    /// than trapping the process or reaching `seconds` with a zero denominator.
    func testAZeroTimescaleOnDiskCostsTheElementAndNotTheCel() throws {
        let asset = try writeAsset(named: "clip.mov")
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: [.stroke(stroke()), .video(defaultElement(assetURL: asset))])
        var object = try jsonObject(VectorCanvasData(from: canvas, imageFileNames: [:]))
        var elements = try XCTUnwrap(object["elements"] as? [[String: Any]])
        var video = try XCTUnwrap(elements[1]["video"] as? [String: Any])
        video["sourceStart"] = ["value": 3, "timescale": 0]
        elements[1]["video"] = video
        object["elements"] = elements

        let decoded = try JSONDecoder().decode(VectorCanvasData.self,
                                               from: try JSONSerialization.data(withJSONObject: object))

        XCTAssertEqual(decoded.elements.count, 1, "The stroke beside it must survive")
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
        XCTAssertEqual(decoded.decodeReport.malformedKinds, ["video"],
                       "A kind this build knows with a payload it cannot read is named, so the save "
                       + "prompt can say 'a video' rather than 'an element'")
        XCTAssertTrue(decoded.decodeReport.unknownKinds.isEmpty,
                      "A broken payload is a defect, not a version gap")
    }

    // MARK: - The missing asset

    /// **The degradation rule, stated at the codec.** A video whose asset the resolver cannot produce
    /// is dropped exactly as a placed image whose PNG is missing is — and the marks beside it on the
    /// cel are untouched, which is the half that used to cost the whole drawing.
    func testAVideoWithNoAssetIsDroppedAndTheRestOfTheCelSurvives() throws {
        let asset = try writeAsset(named: "clip.mov")
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: [.fill(fill()), .video(defaultElement(assetURL: asset)),
                                             .stroke(stroke())])
        let payload = VectorCanvasData(from: canvas, imageFileNames: [:])

        let kept = payload.canvasSpaceElements(resolvingImages: { _ in nil },
                                               resolvingVideos: { _ in url(for: asset) })
        let dropped = payload.canvasSpaceElements(resolvingImages: { _ in nil },
                                                  resolvingVideos: { _ in nil })

        XCTAssertEqual(kept.count, 3, "fixture precondition: with a resolver the video comes back")
        XCTAssertEqual(dropped.count, 2)
        XCTAssertNil(dropped.compactMap(\.video).first)
        XCTAssertNotNil(dropped.compactMap(\.stroke).first, "The stroke is not the video's to lose")
        XCTAssertNotNil(dropped.compactMap(\.fill).first)
        XCTAssertTrue(payload.decodeReport.isClean,
                      "A missing *asset* is not a decode failure — the payload read perfectly; it is "
                      + "the resolver that could not produce the file")
    }

    private func url(for asset: URL) -> URL { asset }

    // MARK: - Through a real package

    /// **What "persists" actually means**: saved by `ProjectStore`, the asset copied into the package
    /// whole (VIDEO.md §6), and the element restored on the way back in.
    func testASavedProjectCopiesTheAssetIntoThePackageAndRestoresTheElement() throws {
        let asset = try writeAsset(named: "clip.mov")
        let (manager, element) = try managerHoldingAVideo(asset: asset)
        let projectURL = ProjectStore.createNewProjectURL(name: "WithVideo")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)

        let copied = projectURL.appendingPathComponent("images/clip.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path),
                      "The source has to be inside the package, or the project is not portable")
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: asset),
                       "Copied whole — VIDEO.md §6 keeps the audio track by never re-encoding")

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        let restored = try XCTUnwrap(videoElement(in: reopened))
        XCTAssertFalse(reopened.loadDamage.isDamaged)
        XCTAssertEqual(restored.assetFileName, element.assetFileName)
        XCTAssertEqual(restored.sourceStart, element.sourceStart)
        XCTAssertEqual(restored.sourceEnd, element.sourceEnd)
        XCTAssertEqual(restored.speed, element.speed)
        XCTAssertEqual(restored.assetURL.standardizedFileURL, copied.standardizedFileURL,
                       "The restored URL must name the package's own copy — that is the only path "
                       + "stage 3's reader can open")
    }

    /// **The second save is the one that could lose the file.** A re-save writes a whole new package
    /// and swaps it in, so the asset has to be copied again from somewhere — and after the first
    /// save the only copy in the world may be the package's own. This deletes the import source to
    /// make that literally true, saves again, and reopens.
    ///
    /// It holds because of `writeAtomically`'s step order rather than by luck: the stage is written
    /// *before* the live package is moved aside, so the element's `assetURL` still names a real file
    /// when `writeCel` copies it, and the swap puts the new package back at the same URL. If those
    /// steps are ever reordered this goes red — and the code would be wrong in the worst way
    /// available, silently emptying a project of its footage one save at a time.
    func testASecondSaveKeepsTheAssetEvenWithTheImportSourceGone() throws {
        let asset = try writeAsset(named: "clip.mov")
        let (manager, _) = try managerHoldingAVideo(asset: asset)
        let projectURL = ProjectStore.createNewProjectURL(name: "WithVideo")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        try FileManager.default.removeItem(at: asset)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path),
                       "fixture precondition: the package's own copy is now the only one")
        XCTAssertEqual(saveAndWait(reopened, to: projectURL), .write)

        let again = try XCTUnwrap(ProjectStore.load(from: projectURL))
        XCTAssertFalse(again.loadDamage.isDamaged,
                       "A save must not be able to lose an asset it was already holding")
        XCTAssertNotNil(videoElement(in: again))
        XCTAssertTrue(FileManager.default
            .fileExists(atPath: projectURL.appendingPathComponent("images/clip.mov").path))
    }

    /// The missing-asset rule end to end, through the counter the artist is actually shown: the video
    /// is dropped, the strokes beside it are not, and the save gate is told a **video** was lost
    /// rather than an anonymous element.
    func testAnAssetDeletedFromThePackageIsCountedAsOneVideoOfDamage() throws {
        let asset = try writeAsset(named: "clip.mov")
        let (manager, _) = try managerHoldingAVideo(asset: asset)
        let projectURL = ProjectStore.createNewProjectURL(name: "WithVideo")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)
        try FileManager.default.removeItem(at: projectURL.appendingPathComponent("images/clip.mov"))

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))

        XCTAssertNil(videoElement(in: reopened), "The element cannot be restored without it")
        XCTAssertEqual(reopened.loadDamage.itemCount, 1)
        XCTAssertEqual(reopened.loadDamage.layers.first?.videos, 1)
        XCTAssertEqual(reopened.loadDamage.summary,
                       "1 video on the Ink layer could not be read when this project opened.")
        let cel: VectorCanvas = try XCTUnwrap(vectorLayer(in: reopened)?.cels.first?.vector)
        XCTAssertEqual(cel.elements.compactMap(\.stroke).count, 1,
                       "The stroke on the same cel is not the missing asset's to take")
    }

    /// **Existence, not playability** — and that is a decision rather than an accident. Deciding a
    /// file is not a video needs a decoder, which is VIDEO.md stage 3; a present-but-unplayable file
    /// is a failure to report at the frame, not a reason to throw the artist's element away at load.
    /// The fixture's asset is thirty-odd bytes of ASCII, so if this ever starts failing, something on
    /// the load path has begun opening the file.
    func testAnUnplayableAssetIsStillAnAssetAtLoad() throws {
        let asset = try writeAsset(named: "clip.mov")
        let (manager, _) = try managerHoldingAVideo(asset: asset)
        let projectURL = ProjectStore.createNewProjectURL(name: "WithVideo")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        XCTAssertNotNil(videoElement(in: reopened))
        XCTAssertFalse(reopened.loadDamage.isDamaged)
    }

    // MARK: - Geometry

    /// **A video follows a canvas-space map the way a placed image does**, which is what keeps a
    /// canvas resize or a whole-cel move from leaving it at coordinates the rest of the document no
    /// longer uses. Asserted against the *image* arm's own answer rather than against numbers typed
    /// here, so the two cannot drift: if this goes red the two kinds have stopped agreeing about
    /// where a rectangle of pixels goes.
    func testAVideoFollowsASimilarityExactlyAsAPlacedImageDoes() throws {
        let asset = try writeAsset(named: "clip.mov")
        var video = defaultElement(assetURL: asset)
        video.transform = LayerTransform(position: CGPoint(x: 12, y: 20), scale: 1.5, rotation: 0.2)
        video.aspect = 1.3
        video.stretchAxis = 0.4
        let image = VectorImageElement(image: solidImage(),
                                       transform: video.transform, aspect: video.aspect,
                                       stretchAxis: video.stretchAxis, mirrored: video.mirrored)
        let map = CGAffineTransform(translationX: 5, y: -3).rotated(by: 0.35).scaledBy(x: 2, y: 2)

        let movedVideo = try XCTUnwrap(VectorCanvas.mapping(.video(video), throughSimilarity: map).video)
        let movedImage = try XCTUnwrap(VectorCanvas.mapping(.image(image), throughSimilarity: map).image)

        XCTAssertEqual(movedVideo.transform.position.x, movedImage.transform.position.x, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.transform.position.y, movedImage.transform.position.y, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.transform.scale, movedImage.transform.scale, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.transform.rotation, movedImage.transform.rotation, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.aspect, movedImage.aspect, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.stretchAxis, movedImage.stretchAxis, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.mirrored, movedImage.mirrored)
        XCTAssertNotEqual(movedVideo.transform.position.x, video.transform.position.x,
                          "fixture precondition: the map actually moves the element")
    }

    /// The same agreement for a **reflection**, which is the arm that composes and re-decomposes the
    /// pose rather than adding an angle — and the one that would silently NaN a placement if it were
    /// wired to the wrong helper.
    func testAMirroredMapAgreesWithThePlacedImageArmToo() throws {
        let asset = try writeAsset(named: "clip.mov")
        var video = defaultElement(assetURL: asset)
        video.transform = LayerTransform(position: CGPoint(x: 9, y: 4), scale: 1.2, rotation: 0.1)
        let image = VectorImageElement(image: solidImage(), transform: video.transform)
        let map = CGAffineTransform(scaleX: -1, y: 1)

        let movedVideo = try XCTUnwrap(VectorCanvas.mapping(.video(video), throughSimilarity: map).video)
        let movedImage = try XCTUnwrap(VectorCanvas.mapping(.image(image), throughSimilarity: map).image)

        XCTAssertTrue(movedVideo.mirrored, "A reflection has to land in the stored bit")
        XCTAssertEqual(movedVideo.mirrored, movedImage.mirrored)
        XCTAssertEqual(movedVideo.transform.rotation, movedImage.transform.rotation, accuracy: 1e-9)
        XCTAssertEqual(movedVideo.transform.scale, movedImage.transform.scale, accuracy: 1e-9)
    }

    /// **The placeholder is drawn where the element says it is.** Not "something was drawn" — a
    /// render that put the placeholder at the origin, or axis-aligned when the placement is turned,
    /// would satisfy that. Ink inside the placed rectangle and none outside it is the assertion that
    /// distinguishes them, and it is also the property stage 3 must preserve when it swaps a decoded
    /// frame in: what the artist lassoes is what the artist can see.
    func testThePlaceholderFillsTheElementsOwnRectangleAndNothingElse() throws {
        let asset = try writeAsset(named: "clip.mov")
        var video = defaultElement(assetURL: asset)
        video.naturalSize = CGSize(width: 20, height: 10)
        video.transform = LayerTransform(position: CGPoint(x: 20, y: 20), scale: 1, rotation: 0)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.video(video)])

        let pixels = try XCTUnwrap(alphaMap(canvas.render()))

        XCTAssertGreaterThan(pixels(20, 20), 0, "the placeholder's own centre")
        XCTAssertGreaterThan(pixels(12, 17), 0, "inside the rectangle, off centre")
        XCTAssertEqual(pixels(20, 34), 0, "below the rectangle")
        XCTAssertEqual(pixels(50, 20), 0, "beside the rectangle")
        XCTAssertEqual(pixels(2, 2), 0, "the corner of the canvas")
    }

    /// The complement: the rectangle **travels** with the placement. Two renders of one element that
    /// differ only by position must differ in exactly that way — a placeholder that ignored
    /// `transform` would paint the same pixels twice and this is what says so.
    func testThePlaceholderMovesWithTheTransform() throws {
        let asset = try writeAsset(named: "clip.mov")
        var video = defaultElement(assetURL: asset)
        video.naturalSize = CGSize(width: 20, height: 10)
        video.transform = LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0)
        let near = try XCTUnwrap(alphaMap(VectorCanvas(size: Self.canvasSize,
                                                      elements: [.video(video)]).render()))
        video.transform.position = CGPoint(x: 46, y: 46)
        let far = try XCTUnwrap(alphaMap(VectorCanvas(size: Self.canvasSize,
                                                     elements: [.video(video)]).render()))

        XCTAssertGreaterThan(near(16, 16), 0)
        XCTAssertEqual(near(46, 46), 0)
        XCTAssertGreaterThan(far(46, 46), 0)
        XCTAssertEqual(far(16, 16), 0)
    }

    // MARK: - Support

    private func solidImage(side: CGFloat = 16) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// A closure answering the alpha at a canvas point, so a pixel assertion reads as a coordinate
    /// rather than as an index into a byte buffer.
    private func alphaMap(_ image: UIImage) -> ((Int, Int) -> UInt8)? {
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
            guard px >= 0, px < width, py >= 0, py < height else { return 0 }
            return bytes[(py * width + px) * 4 + 3]
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A manager with one raster layer and one vector layer whose only cel holds a stroke and a
    /// video — the stroke so a dropped video has something beside it to fail to take with it.
    private func managerHoldingAVideo(asset: URL) throws -> (CanvasManager, VectorVideoElement) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.projectName = "WithVideo"
        manager.addVectorLayer()
        manager.layers[1].name = "Ink"
        manager.layers[1].hasCustomName = true

        var element = defaultElement(assetURL: asset)
        element.sourceStart = SourceTime(value: 12, timescale: 30)
        element.sourceEnd = SourceTime(value: 300, timescale: 30)
        element.speed = 1.5
        element.transform = LayerTransform(position: CGPoint(x: 24, y: 24), scale: 1, rotation: 0)

        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector,
                                   "Setup: a vector layer's cel should carry a VectorCanvas")
        canvas.elements = [.stroke(stroke()), .video(element)]
        canvas.bumpVersion()
        return (manager, element)
    }

    private func vectorLayer(in manager: CanvasManager) -> Layer? {
        manager.layers.first { $0.name == "Ink" }
    }

    private func videoElement(in manager: CanvasManager) -> VectorVideoElement? {
        vectorLayer(in: manager)?.cels.first?.vector?.elements.compactMap(\.video).first
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL,
                             intent: SaveIntent = .artist) -> SaveDecision {
        let finished = expectation(description: "ProjectStore.save completion")
        let decision = ProjectStore.save(manager, to: url, intent: intent) { finished.fulfill() }
        if decision == .ask { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        return decision
    }
}
