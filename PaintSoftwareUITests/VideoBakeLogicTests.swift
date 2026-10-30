import XCTest
import UIKit
import AVFoundation

/// Pure-logic tests for VIDEO.md §8 stage 8 — `CanvasManager.bakeVideoToCels`, the verb behind the
/// timeline's "Bake to Images" row.
///
/// **Reachability is asked of the real verbs, not assumed.** `testAFreshDocumentReachesBakeOnlyAfterAnActualImport`
/// walks a brand-new document through `CanvasManager.insertVideo` — the same call the artist's own
/// `PhotosPicker` flow makes — rather than splicing a `VectorVideoElement` into `layers` by hand,
/// which is exactly the shortcut CLAUDE.md's "drive it before you call it done" section names as
/// the way three earlier features shipped unusable while every test on them stayed green.
///
/// **Every clip is generated at test time** with the app's own `VideoFrameWriter`, mirroring
/// `VideoFrameReaderLogicTests`: a flat grey frame names its own index, so a decoded picture can be
/// told apart from its neighbours by one pixel rather than by trusting that *something* arrived.
@MainActor
final class VideoBakeLogicTests: XCTestCase {

    private static let levels: [UInt8] = [40, 90, 140, 190, 230, 255]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-bake-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Fixtures

    private func clip(named name: String = "clip", frames: Int = VideoBakeLogicTests.levels.count) throws -> URL {
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).mp4")
        let levels = (0..<frames).map { Self.levels[$0 % Self.levels.count] }
        try CanvasFixture.writeGreyClip(levels: levels, fps: 24, side: 64, to: url)
        return url
    }

    private static var levelsCount: Int { levels.count }

    /// `CanvasFixture.celLayout` returns `[(start: Int, length: Int)]`, and a bare tuple is not
    /// `Equatable` — every existing use of it compares `.map(\.start)` and `.map(\.length)`
    /// separately. This folds both into one `[[Int]]` so a "nothing changed" assertion can be one
    /// line instead of two.
    private func layoutFingerprint(_ manager: CanvasManager, layerIndex: Int = 0) -> [[Int]] {
        CanvasFixture.celLayout(manager, layerIndex: layerIndex).map { [$0.start, $0.length] }
    }

    /// A stroke to plant alongside a video, exactly `VideoElementLogicTests`' own
    /// `managerHoldingAVideo` fixture does — "the stroke so a dropped video has something beside it
    /// to fail to take with it", read here as "something beside it whose id a bake must not repeat".
    private func stroke() -> VectorStroke {
        VectorStroke(brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: 6, opacity: 1,
                     samples: [VectorSample(x: 4, y: 4, pressure: 1),
                               VectorSample(x: 40, y: 40, pressure: 1)])
    }

    /// The one video element on `manager`'s newest (vector) layer, cel 0 — the shape every
    /// `insertVideo` call produces.
    private func importedVideo(_ manager: CanvasManager) throws -> (layerIndex: Int, video: VectorVideoElement) {
        let layerIndex = manager.layers.count - 1
        let video = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector?.videos.first)
        return (layerIndex, video)
    }

    private func bake(_ manager: CanvasManager, layerIndex: Int, celIndex: Int) throws -> CanvasManager.VideoBakeOutcome {
        let finished = expectation(description: "prepared video bake completion")
        var result: CanvasManager.VideoBakeOutcome?
        manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: celIndex) { outcome in
            result = outcome; finished.fulfill()
        }
        wait(for: [finished], timeout: 30)
        return try XCTUnwrap(result, "The asynchronous public bake must complete")
    }

    // MARK: - Cold-start reachability

    /// **The chain a real artist walks, with no step skipped and no state hand-built.** A fresh
    /// document cannot bake anything — there is no video anywhere yet — and the *only* thing that
    /// changes that is the same `insertVideo` call the Actions menu's `PhotosPicker` handler makes.
    /// If reaching Bake ever came to need some *other* precondition only Bake itself could create,
    /// this is the test that would catch it going stale.
    func testAFreshDocumentReachesBakeOnlyAfterAnActualImport() throws {
        let manager = CanvasFixture.manager(layerCount: 1)

        switch try bake(manager, layerIndex: 0, celIndex: 0) {
        case .baked: XCTFail("A fresh document's only cel holds no video and must refuse.")
        case .refused(let reason): XCTAssertEqual(reason, .noVideo)
        }

        XCTAssertTrue(manager.insertVideo(at: try clip()),
                      "Setup: the real import verb should succeed on a fresh document.")

        let (layerIndex, _) = try importedVideo(manager)
        switch try bake(manager, layerIndex: layerIndex, celIndex: 0) {
        case .baked(let cels): XCTAssertEqual(cels, Self.levelsCount)
        case .refused(let reason): XCTFail("Bake should now be reachable, refused: \(reason)")
        }
    }

    // MARK: - Correctness

    /// **The two operands are the baked picture and the source frame it was supposed to come
    /// from** — not "did some cel appear", which would pass even if every cel showed frame 0.
    func testBakingWritesOneCelPerFrameEachShowingItsOwnDecodedPicture() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, originalVideo) = try importedVideo(manager)

        guard case .baked(let cels) = try bake(manager, layerIndex: layerIndex, celIndex: 0) else {
            return XCTFail("Setup: bake should succeed on a freshly imported clip.")
        }
        XCTAssertEqual(cels, Self.levelsCount)
        XCTAssertEqual(manager.layers[layerIndex].cels.count, Self.levelsCount)

        let ordered = manager.layers[layerIndex].cels.sorted { $0.startFrame < $1.startFrame }
        for (index, cel) in ordered.enumerated() {
            XCTAssertEqual(cel.startFrame, index, "Cel \(index) starts at the wrong document frame.")
            XCTAssertEqual(cel.frameCount, 1, "Cel \(index) should be exactly one document frame long.")
            let elements = try XCTUnwrap(cel.vector).elements
            XCTAssertEqual(elements.count, 1, "Cel \(index) should hold exactly the baked image.")
            guard case .image(let image) = elements[0] else {
                return XCTFail("Cel \(index) still holds a \(elements[0]), not an image.")
            }
            XCTAssertNotEqual(image.id, originalVideo.id, "The image must not reuse the video's id.")
            let grey = try XCTUnwrap(CanvasFixture.greyAt(try image.source.resolveImage().get(), x: 32, y: 32),
                                     "Cel \(index)'s picture should have an opaque pixel to read.")
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(grey, in: Self.levels), index,
                          "Cel \(index) shows level \(grey), the wrong source frame's picture.")
            // The placement carries over untouched — same rectangle, same picture, just no longer
            // decoded live.
            XCTAssertEqual(image.transform.position, originalVideo.transform.position)
            XCTAssertEqual(image.transform.scale, originalVideo.transform.scale, accuracy: 1e-9)
        }
    }

    /// **Every id is fresh, video-turned-image and passthrough ink alike** — KEYFRAMES.md §6's rule,
    /// and the one a naive "just re-crop and keep copying" implementation would violate silently:
    /// nothing renders wrong when six cels share one stroke's id, but anything keyed by it (a
    /// motion-group lookup, `LayerContentVersion`'s identity) would alias the six together.
    func testBakingMintsFreshIdsForEveryElementItWrites() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, _) = try importedVideo(manager)

        let canvas = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        let plantedStroke = stroke()
        canvas.elements.append(.stroke(plantedStroke))
        canvas.bumpVersion()

        guard case .baked = try bake(manager, layerIndex: layerIndex, celIndex: 0) else {
            return XCTFail("Setup: bake should succeed.")
        }

        var allIDs: [UUID] = []
        for cel in manager.layers[layerIndex].cels {
            let elements = try XCTUnwrap(cel.vector).elements
            XCTAssertEqual(elements.count, 2, "Each cel should carry the image and the passenger stroke.")
            allIDs.append(contentsOf: elements.map(\.id))
            guard let carriedStroke = elements.compactMap(\.stroke).first else {
                return XCTFail("The stroke beside the video should still be there, id aside.")
            }
            XCTAssertEqual(carriedStroke.color, plantedStroke.color, "Only the id should have changed.")
            XCTAssertEqual(carriedStroke.samples.positions, plantedStroke.samples.positions)
        }
        XCTAssertFalse(allIDs.contains(plantedStroke.id), "The planted stroke's own id must not survive.")
        XCTAssertEqual(Set(allIDs).count, allIDs.count,
                      "Every element across every baked cel must have a distinct id.")
    }

    // MARK: - Undo, in one step

    /// **The exact case a naive `withStructureUndo` gets wrong**: `splitCel` never copies the left
    /// half's canvas, so the first of the resulting cels mutates the *same* `VectorCanvas` object
    /// the block had before baking. A snapshot-only undo restores the cel array's shape correctly
    /// while leaving that shared object's content baked — which reads as a passing "cel count is
    /// back to 1" and a silently wrong drawing underneath it. This asserts the content, not just
    /// the count.
    func testUndoingABakeRestoresTheOriginalVideoCelExactly() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, originalVideo) = try importedVideo(manager)
        let originalCelID = manager.layers[layerIndex].cels[0].id
        let costBefore = manager.layers[layerIndex].cels.count

        guard case .baked(let cels) = try bake(manager, layerIndex: layerIndex, celIndex: 0),
              cels > 1 else {
            return XCTFail("Setup: bake should split the block into more than one cel.")
        }
        XCTAssertEqual(manager.layers[layerIndex].cels.count, cels)

        manager.undo()

        XCTAssertEqual(manager.layers[layerIndex].cels.count, costBefore,
                       "Undo should collapse every split cel back into one, in a single press.")
        let restored = manager.layers[layerIndex].cels[0]
        XCTAssertEqual(restored.id, originalCelID)
        let elements = try XCTUnwrap(restored.vector).elements
        XCTAssertEqual(elements.count, 1)
        guard case .video(let video) = elements[0] else {
            return XCTFail("Undo left a \(elements[0]) where the original video belongs.")
        }
        XCTAssertEqual(video.id, originalVideo.id)
        XCTAssertEqual(video.assetFileName, originalVideo.assetFileName)
        XCTAssertEqual(video.sourceStart, originalVideo.sourceStart)
        XCTAssertEqual(video.sourceEnd, originalVideo.sourceEnd)

        manager.redo()
        XCTAssertEqual(manager.layers[layerIndex].cels.count, cels,
                       "Redo should bring every baked cel back in the same one press.")
        guard case .image = try XCTUnwrap(manager.layers[layerIndex].cels
            .sorted { $0.startFrame < $1.startFrame }[0].vector).elements.first else {
            return XCTFail("Redo should restore the baked image, not the video.")
        }
    }

    func testEverySplitConsumerRefusesBeforeChangingAnAdmittedVideoBlock() throws {
        for consumer in ["split", "video", "stream", "pose", "grade", "repeat", "merge"] {
            let manager = CanvasFixture.manager(layerCount: 1)
            XCTAssertTrue(manager.insertVideo(at: try clip(frames: 5)), "PREMISE: a real small movie imports")
            let (layerIndex, imported) = try importedVideo(manager)
            let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
            var video = imported
            video.sourceStart = SourceTime(value: 92_233_720_367_547_761, timescale: 3_000_000)
            video.sourceEnd = SourceTime(value: 92_233_720_367_847_761, timescale: 3_000_000)
            video.speed = 2e-7; video.mappedFrameRate = 3
            vector.elements = [.video(video), .stroke(stroke())]; vector.bumpVersion()
            manager.layers[layerIndex].cels[0].frameCount = 12
            let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
            let rest = PoseQuad(restingIn: box)
            manager.layers[layerIndex].cels[0].transformTracks = [TransformChannelID.cel.id:
                CanvasFixture.poseTrack([(0, rest), (11, PoseQuad(box: box, mappedBy: .init(translationX: 1, y: 0)))], interpolation: .linear)]
            manager.layers[layerIndex].cels[0].pendingPoseBaselines = [TransformChannelID.cel.id: rest]
            var baker: UUID?
            if consumer == "stream" {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4), format: PixelOps.transparentFormat()).image { c in
                    UIColor.green.setFill(); c.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
                }
                var stream = VectorStreamElement(naturalSize: image.size, host: "laptop", port: 47301,
                    sourceLabel: "Window", transform: LayerTransform(position: CGPoint(x: 8, y: 8), scale: 1, rotation: 0))
                stream.picture = StreamPicture(frame: image)
                vector.elements.append(.stream(stream)); vector.bumpVersion()
            } else if consumer == "grade" {
                manager.addValueLayer(effect: .hsvShift(.init(hueDegrees: 1)))
                baker = manager.layers[manager.currentLayerIndex].id
                manager.layers[manager.currentLayerIndex].cels[0].frameCount = 12
                manager.layers[manager.currentLayerIndex].effectTracks = ["hsvShift.hue": AnimationCurve(keys: [
                    .init(frame: 0, value: 1, interpolation: .linear), .init(frame: 11, value: 111, interpolation: .linear)])]
            } else if consumer == "repeat" {
                var held = manager.layers[layerIndex].cels[0]
                held.startFrame = 2; held.transformTracks = [:]; held.pendingPoseBaselines = [:]
                let plain = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: CanvasFixture.canvasSize),
                    vector: VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(stroke())]))
                manager.layers[layerIndex].cels = [plain, held]
                manager.addTransformLayer()
                baker = manager.layers[manager.currentLayerIndex].id
                manager.layers[manager.currentLayerIndex].transform = LayerPose(pose: rest, mode: .repeat, repeatPeriod: 1)
                manager.layers[manager.currentLayerIndex].cels = [Cel(id: UUID(), startFrame: 0, frameCount: 12,
                    raster: .empty(size: CanvasFixture.canvasSize))]
            } else if consumer == "merge" {
                manager.layers[0].cels = [Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: CanvasFixture.canvasSize)),
                    Cel(id: UUID(), startFrame: 1, frameCount: 11, raster: .empty(size: CanvasFixture.canvasSize))]
            }
            let index = try XCTUnwrap(manager.layers[layerIndex].cels.firstIndex { cel in
                cel.vector?.videos.contains(where: { $0.id == video.id }) == true
            })
            let cel = manager.layers[layerIndex].cels[index]
            try VideoFrameMap.validate(sourceStart: video.sourceStart, sourceEnd: video.sourceEnd,
                speed: video.speed, documentFPS: video.resolvedFrameRate)
            let beforeImage = try XCTUnwrap(manager.videoCelContent(for: cel, atFrame: cel.startFrame)?.render(.full))
            let grey = try XCTUnwrap(CanvasFixture.greyAt(beforeImage, x: 32, y: 48))
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(grey, in: Self.levels), 4,
                           "PREMISE: the real short asset holds its last decoded frame at the admitted far-future time")
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(beforeImage.cgImage)))
            var bluePixels: Int = 0
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let red: Int = Int(pixels[offset])
                let green: Int = Int(pixels[offset + 1])
                let blue: Int = Int(pixels[offset + 2])
                let alpha: UInt8 = pixels[offset + 3]
                let blueDominates: Bool = blue > red + 100 && blue > green + 100
                if blueDominates && alpha > 240 { bluePixels += 1 }
            }
            XCTAssertGreaterThan(bluePixels, 10, "PREMISE: opaque passenger ink is visibly drawn over the held movie frame")
            let layouts = manager.layers.map { $0.cels.map { [$0.startFrame, $0.frameCount] } }
            let ids = manager.layers.map(\.id), celIDs = manager.layers.map { $0.cels.map(\.id) }
            let tracks = cel.transformTracks, baselines = cel.pendingPoseBaselines
            let version = vector.version, history = manager.history.undoStack.count
            if let baker {
                guard case .plan(let plan) = manager.bakePlan(forLayerID: baker),
                      plan.layers.contains(where: { $0.layerID == manager.layers[layerIndex].id }) else {
                    return XCTFail("PREMISE: the real \(consumer) Bake plan reaches the target layer")
                }
            }

            if consumer == "stream" {
                XCTAssertNotNil(manager.prepareCelSplits(inLayerAt: layerIndex, at: [cel.startFrame + 2]),
                                "PREMISE: the first Stream Bake cut succeeds")
                XCTAssertNil(manager.prepareCelSplits(inLayerAt: layerIndex, at: [cel.startFrame + 2, cel.startFrame + 3]),
                             "PREMISE: a later child cut refuses under the current admission proof")
            }
            switch consumer {
            case "split":
                let crop = manager.splitCel(layerIndex: layerIndex, celIndex: index, atFrame: cel.startFrame + 1)
                XCTAssertNil(crop)
                guard crop == nil else { return }
            case "video":
                let outcome = try bake(manager, layerIndex: layerIndex, celIndex: index)
                XCTAssertEqual(outcome, .refused(.videoTiming), "A split refusal must never report twelve baked drawings")
                guard outcome == .refused(.videoTiming) else { return }
            case "stream":
                let outcome = manager.bakeStreamFrame(layerIndex: layerIndex, celIndex: index, atFrame: cel.startFrame + 2)
                XCTAssertEqual(outcome, .refused(.videoTiming), "Stream Bake must refuse its entire two-cut operation")
                guard outcome == .refused(.videoTiming) else { return }
            case "pose":
                let outcome = manager.bakePoseToCels(layerIndex: layerIndex, celIndex: index)
                XCTAssertEqual(outcome, .refused(.videoTiming), "Pose Bake must propagate the refused cuts")
                guard outcome == .refused(.videoTiming) else { return }
            case "grade", "repeat":
                guard case .refused(let reason) = manager.bakeLayer(id: baker!) else {
                    return XCTFail("The entire \(consumer) Bake must refuse before treatments or carving")
                }
                XCTAssertEqual(reason, .videoTiming)
                guard reason == .videoTiming else { return }
            case "merge":
                let merged = manager.mergeLayers(manager.layers[0].id, manager.layers[layerIndex].id)
                XCTAssertFalse(merged)
                guard !merged else { return }
            default: preconditionFailure("Unknown finite test consumer")
            }

            XCTAssertEqual(manager.layers.map { $0.cels.map { [$0.startFrame, $0.frameCount] } }, layouts,
                           "\(consumer) preflights the whole cut sequence before any structural write")
            XCTAssertEqual(manager.layers.map(\.id), ids, "A refused operation removes no layer")
            XCTAssertEqual(manager.layers.map { $0.cels.map(\.id) }, celIDs, "A refused operation mints no partial split cells")
            let restored = try XCTUnwrap(manager.layers[layerIndex].cels.first { $0.id == cel.id })
            XCTAssertEqual(restored.transformTracks, tracks, "A refused operation consumes no pose tracks")
            XCTAssertEqual(restored.pendingPoseBaselines, baselines)
            XCTAssertEqual(restored.vector?.videos.first.map(VideoCrop.init(of:)), VideoCrop(of: video), "The original video remains a video with its crop")
            XCTAssertEqual(vector.version, version, "No original canvas was rewritten in place")
            XCTAssertEqual(manager.history.undoStack.count, history, "A refused operation creates no history step")
            let after = try XCTUnwrap(manager.videoCelContent(for: restored, atFrame: restored.startFrame)?.render(.full)?.cgImage)
            XCTAssertEqual(CanvasFixture.rgbaBytes(after), pixels, "Every actual decoded/ink pixel is retained after \(consumer) refusal")
        }
    }

    /// Generic Bake accepts an earlier pending edit at its established action-entry boundary.
    /// A later timing refusal owns no split/treatment/history and leaves that edit undoable.
    func testAnAcceptedPendingShapeSurvivesARefusedLayerBakeAndUndoes() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip(frames: 5)))
        let (layerIndex, original) = try importedVideo(manager)
        let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        var video = original
        video.sourceStart = SourceTime(value: 92_233_720_367_547_761, timescale: 3_000_000)
        video.sourceEnd = SourceTime(value: 92_233_720_367_847_761, timescale: 3_000_000)
        video.speed = 2e-7; video.mappedFrameRate = 3
        vector.elements = [.video(video)]; vector.bumpVersion()
        manager.layers[layerIndex].cels[0].frameCount = 12
        manager.addValueLayer(effect: .hsvShift(.init(hueDegrees: 1)))
        let baker = manager.layers[manager.currentLayerIndex].id
        manager.layers[manager.currentLayerIndex].cels[0].frameCount = 12
        manager.layers[manager.currentLayerIndex].effectTracks = ["hsvShift.hue": AnimationCurve(keys: [
            .init(frame: 0, value: 1, interpolation: .linear), .init(frame: 11, value: 111, interpolation: .linear)])]
        manager.currentLayerIndex = layerIndex
        func pixels() throws -> [UInt8] {
            let cel = manager.layers[layerIndex].cels[0]
            let image = try XCTUnwrap(manager.videoCelContent(for: cel, atFrame: cel.startFrame)?.render(.full)?.cgImage)
            return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
        }
        let originalPixels = try pixels()
        manager.brushColor = .black
        manager.toolProfiles.brush.size = 6
        manager.beginInteractiveShape(ShapeGeometry(kind: .line,
            startPoint: CGPoint(x: 10, y: 8), endPoint: CGPoint(x: 50, y: 8)), samples: (0...20).map {
                VectorSample(x: 10 + CGFloat($0) * 2, y: 8, pressure: 1)
            })
        manager.endInteractiveShape()
        XCTAssertTrue(manager.shapeGestureActive, "PREMISE: a real adjustable shape is pending")
        XCTAssertNotNil(manager.shapeInk)
        XCTAssertEqual(vector.elements.count, 1, "The shape has not yet landed in the video cel")
        let history = manager.history.undoStack.count
        let ids = manager.layers.map(\.id), celIDs = manager.layers.map { $0.cels.map(\.id) }

        XCTAssertEqual(manager.bakeLayer(id: baker), .refused(.videoTiming))
        XCTAssertFalse(manager.shapeGestureActive, "The accepted shape settles before generic Bake planning")
        XCTAssertEqual(manager.history.undoStack.count, history + 1, "Only the preceding shape owns a history step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .shape)
        XCTAssertEqual(manager.layers.map(\.id), ids, "The refused Bake keeps the baker and drawings")
        XCTAssertEqual(manager.layers.map { $0.cels.map(\.id) }, celIDs, "No partial cut is installed")
        XCTAssertEqual(manager.layers[layerIndex].cels[0].frameCount, 12)
        XCTAssertEqual(vector.videos.first.map(VideoCrop.init(of:)), VideoCrop(of: video))
        XCTAssertEqual(vector.elements.count, 2, "Only the accepted shape is added")
        let landedPixels = try pixels()
        XCTAssertNotEqual(landedPixels, originalPixels, "The accepted shape is actually drawn over the held movie frame")
        guard manager.history.undoStack.count == history + 1 else { return }
        manager.undo()
        XCTAssertEqual(try pixels(), originalPixels, "Undo removes the preceding shape and restores every original movie pixel")
        XCTAssertEqual(vector.elements.count, 1)
        manager.redo()
        XCTAssertEqual(try pixels(), landedPixels, "Redo restores the shape alone, with no hidden Bake treatment")
        XCTAssertEqual(manager.layers.map(\.id), ids)
        XCTAssertEqual(manager.layers[layerIndex].cels.map(\.frameCount), [12])
    }

    func testTinyRoundedVideoCutsStillBakeTwelvePicturesAndUndo() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip(frames: 5)))
        let (layerIndex, original) = try importedVideo(manager)
        let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        var video = original
        video.sourceStart = .zero; video.sourceEnd = SourceTime(value: 1, timescale: 1)
        video.speed = 1e-9; video.mappedFrameRate = 24
        vector.elements = [.video(video)]; vector.bumpVersion()
        manager.layers[layerIndex].cels[0].frameCount = 12
        let crop = VideoCrop(of: video)
        let split = manager.splitCel(layerIndex: layerIndex, celIndex: 0, atFrame: 6)
        XCTAssertNotNil(split, "A successful rounded unchanged crop remains a real split")
        guard split != nil else { return }
        XCTAssertEqual(manager.layers[layerIndex].cels.map(\.frameCount), [6, 6])
        guard manager.layers[layerIndex].cels.map(\.frameCount) == [6, 6] else { return }
        XCTAssertTrue(manager.layers[layerIndex].cels.allSatisfy { $0.vector?.videos.first.map(VideoCrop.init(of:)) == crop })
        manager.undo()
        XCTAssertEqual(manager.layers[layerIndex].cels.map(\.frameCount), [12])

        XCTAssertEqual(try bake(manager, layerIndex: layerIndex, celIndex: 0), .baked(cels: 12))
        XCTAssertEqual(manager.layers[layerIndex].cels.map(\.frameCount), Array(repeating: 1, count: 12),
                       "A completed bake really has twelve one-frame cells")
        for cel in manager.layers[layerIndex].cels {
            let source = try XCTUnwrap(cel.vector?.images.first?.source)
            let image = try source.resolveImage().get()
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(try XCTUnwrap(CanvasFixture.greyAt(image, x: 32, y: 32)), in: Self.levels), 0,
                           "The tiny rounded timing displays its original first source picture on each frame")
            XCTAssertTrue(cel.vector?.videos.isEmpty == true)
        }
        manager.undo()
        XCTAssertEqual(manager.layers[layerIndex].cels.map(\.frameCount), [12])
        XCTAssertEqual(manager.layers[layerIndex].cels[0].vector?.videos.first.map(VideoCrop.init(of:)), crop)
        manager.redo()
        XCTAssertEqual(manager.layers[layerIndex].cels.map(\.frameCount), Array(repeating: 1, count: 12))
    }

    // MARK: - Refusals are visible, not swallowed

    func testBakeRefusesACelWithNoVideoAndTouchesNothing() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let before = layoutFingerprint(manager)

        switch try bake(manager, layerIndex: 0, celIndex: 0) {
        case .baked: XCTFail("An ordinary raster cel holds no video and must refuse.")
        case .refused(let reason): XCTAssertEqual(reason, .noVideo)
        }

        XCTAssertEqual(layoutFingerprint(manager), before, "A refusal must leave the timeline untouched.")
    }

    /// **An asset that will not open** — a video whose file is simply gone, which
    /// `VideoImportLogicTests`' own sentence about `ProjectStore.load` says already happens to a
    /// missing PNG and applies here the same way. Built directly rather than through `insertVideo`
    /// (which would refuse the missing file itself, never getting an element onto the canvas at
    /// all) — this is a fixture for a *refusal path*, not a claim that this is how an artist reaches
    /// it.
    func testBakeRefusesAnUnreadableAssetAndTouchesNothing() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.layers.count - 1
        let missing = directory.appendingPathComponent("never-written-\(UUID().uuidString).mp4")
        let video = VectorVideoElement(assetURL: missing, assetFileName: missing.lastPathComponent,
                                       naturalSize: CGSize(width: 64, height: 64),
                                       sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1),
                                       speed: 1, transform: LayerTransform(position: .zero, scale: 1, rotation: 0))
        let canvas = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        canvas.elements = [.video(video)]
        canvas.bumpVersion()
        let before = layoutFingerprint(manager, layerIndex: layerIndex)

        switch try bake(manager, layerIndex: layerIndex, celIndex: 0) {
        case .baked: XCTFail("A video whose file was never written must refuse.")
        case .refused(let reason): XCTAssertEqual(reason, .unreadableAsset)
        }

        XCTAssertEqual(layoutFingerprint(manager, layerIndex: layerIndex), before)
        XCTAssertEqual(try XCTUnwrap(manager.layers[layerIndex].cels[0].vector).elements.count, 1,
                       "A refusal must not have touched the element either.")
    }

    /// **This refutes what this file assumed on the first pass, and says so rather than hiding it.**
    /// The plan was: push `sourceStart`/`sourceEnd` far past the clip's real duration and expect
    /// `.noDecodableFrames`, reading `VideoFrameReader`'s doc — "a pipe opened past the end delivers
    /// nothing at all" — as "every such query comes back nil". MEASURED instead: bake **succeeds**,
    /// producing one cel per document frame, every one showing the clip's *last* frame. The reader's
    /// own "nearest sample" rule degrades gracefully past the end rather than failing outright —
    /// consistent with RENDER §2.10's "keep the previous picture, never a hard failure" philosophy
    /// applied one level down, inside the reader itself.
    ///
    /// **`.noDecodableFrames` is therefore defensive code with no test proving it fires against a
    /// real asset.** `VideoFrameWriter.finish()` itself throws on zero appended frames
    /// (`Failure.couldNotFinish("No frames were written.")`), so a *valid, openable* file with
    /// nothing in it is not constructible with the tools at hand — the only asset that reaches
    /// `.noDecodableFrames` in practice would be one that opens its container but fails on every
    /// sample read, which is a corruption this fixture cannot manufacture. The guard stays in
    /// `bakeVideoToCels` as a safety net; this test pins what actually happens on the input this
    /// stage's own brief named ("no frames in range"), rather than asserting the refusal this file
    /// originally guessed at and never observed.
    func testACropFarPastTheClipsDurationBakesTheLastFrameRatherThanRefusing() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, _) = try importedVideo(manager)

        let canvas = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        var elements = canvas.elements
        guard case .video(var video) = elements[0] else { return XCTFail("Setup: expected a video.") }
        video.sourceStart = SourceTime(value: 999, timescale: 1)
        video.sourceEnd = SourceTime(value: 1000, timescale: 1)
        elements[0] = .video(video)
        canvas.elements = elements
        canvas.bumpVersion()

        guard case .baked(let cels) = try bake(manager, layerIndex: layerIndex, celIndex: 0) else {
            return XCTFail("MEASURED behavior was a successful bake — see the doc comment above.")
        }
        XCTAssertEqual(cels, Self.levelsCount)
        for cel in manager.layers[layerIndex].cels {
            let elements = try XCTUnwrap(cel.vector).elements
            guard case .image(let image) = elements.first else {
                return XCTFail("Every resulting cel should still hold an image, just the wrong frame.")
            }
            let grey = try XCTUnwrap(CanvasFixture.greyAt(try image.source.resolveImage().get(), x: 32, y: 32))
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(grey, in: Self.levels), Self.levelsCount - 1,
                          "A far-future crop should decode the clip's last frame, repeatedly.")
        }
    }
}

extension VideoBakeLogicTests {
    func testAPreparationRefusalAfterThreeNativeOutputsPreservesTheOriginalVideoDrawingAndHistory() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, video) = try importedVideo(manager)
        weak var observed: RasterResidency?
        let owner = RasterResidency(budgetBytes: 1024 * 1024, hasHeadroom: { _ in
            (observed?.usage.allocations ?? 0) < 3
        })
        observed = owner
        manager.layers[layerIndex].cels[0].raster = RasterLayerTexture(size: CanvasFixture.canvasSize, residency: owner)
        let original = manager.layers[layerIndex].cels[0]
        let vector = try XCTUnwrap(original.vector)
        let beforeElements = vector.elements.map(\.id)
        let beforePixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
        let undo = manager.history.undoStack.count, redo = manager.history.redoStack.count
        let completed = expectation(description: "refused native output batch")
        var result: CanvasManager.VideoBakeOutcome?
        manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0) { result = $0; completed.fulfill() }
        XCTAssertTrue(manager.isUpdatingCanvas, "The existing canvas owner blocks edits/saves before work begins")
        XCTAssertEqual(manager.layers[layerIndex].cels.count, 1)
        XCTAssertTrue(manager.layers[layerIndex].cels[0].vector === vector, "Nothing is published at request time")
        wait(for: [completed], timeout: 30)
        XCTAssertEqual(result, .refused(.sourceUnavailable))
        XCTAssertFalse(manager.isUpdatingCanvas)
        XCTAssertEqual(owner.usage.allocations, 3, "The fixture reaches three actual copied outputs before checkpoint admission refuses")
        XCTAssertEqual(owner.usage.chargedBytes, 0)
        XCTAssertEqual(manager.layers[layerIndex].cels.count, 1)
        XCTAssertEqual(manager.layers[layerIndex].cels[0].id, original.id)
        XCTAssertTrue(manager.layers[layerIndex].cels[0].vector === vector)
        XCTAssertTrue(manager.layers[layerIndex].cels[0].raster === original.raster)
        XCTAssertEqual(vector.elements.map(\.id), beforeElements)
        XCTAssertEqual(vector.videos.first.map(VideoCrop.init(of:)), VideoCrop(of: video))
        XCTAssertEqual(try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage))), beforePixels)
        XCTAssertEqual(manager.history.undoStack.count, undo); XCTAssertEqual(manager.history.redoStack.count, redo)
        if FileManager.default.fileExists(atPath: owner.storage.url.path) {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: owner.storage.url, includingPropertiesForKeys: nil).isEmpty,
                          "The refused private batch releases its already prepared files")
        }
    }
}
