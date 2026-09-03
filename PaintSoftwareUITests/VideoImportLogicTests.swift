import AVFoundation
import XCTest
import UIKit

/// Pure-logic tests for `CanvasManager.insertVideo` — VIDEO.md stage 4.
///
/// **Two rulings and they are the whole of this suite.** §2.1: a video arrives in **its own new
/// vector layer**, whatever the artist was standing on — which is what makes §2.2's edge drags mean
/// "crop the video" rather than "resize a block that also holds ink. §2.4: the block arrives
/// **clipped to the current scene**, holding the head of the clip and croppable outward, and
/// **import never changes the shape of the timeline**.
///
/// The picker itself is not here. `ActionsMenu` is a SwiftUI view and is not a member of this
/// target, so what is tested is the verb it calls — which is also where every decision above lives.
/// What the view owns is loading the clip as a *file* rather than as `Data`, and that is a memory
/// claim rather than a behavioural one.
@MainActor
final class VideoImportLogicTests: XCTestCase {

    private static let levels: [UInt8] = [30, 72, 114, 156, 198, 240]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-import-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Staged into the test's own directory rather than the real Application Support one, so a
        // run leaves nothing behind on the machine it ran on.
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - §2.1, its own layer

    func testAVideoArrivesInItsOwnNewVectorLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let before = manager.layers.count
        XCTAssertTrue(manager.insertVideo(at: try shortClip()))

        XCTAssertEqual(manager.layers.count, before + 1)
        let layer = try XCTUnwrap(manager.layers.last)
        XCTAssertEqual(layer.kind, .vector)
        XCTAssertEqual(layer.cels.count, 1)
        XCTAssertEqual(try XCTUnwrap(layer.cels[0].vector).videos.count, 1)
    }

    /// **§2.1's teeth.** `insertImage` joins the active vector layer when there is one; this must
    /// not, or the artist who imports a video onto the layer they were drawing on gets a block whose
    /// edges no longer mean "crop".
    func testAVideoStillGetsItsOwnLayerWhenAVectorLayerIsAlreadyActive() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let host = manager.layers[manager.currentLayerIndex].id
        let before = manager.layers.count

        XCTAssertTrue(manager.insertVideo(at: try shortClip()))
        XCTAssertEqual(manager.layers.count, before + 1)
        let hostLayer = try XCTUnwrap(manager.layers.first { $0.id == host })
        XCTAssertTrue(try XCTUnwrap(hostLayer.cels[0].vector).videos.isEmpty,
                      "The layer that was active must be left exactly as it was.")
    }

    // MARK: - §2.4, clipped to the scene

    /// **A clip longer than the scene is cropped, and the scene is not stretched.** Thirty frames of
    /// footage into a twelve-frame document is a twelve-frame block whose `sourceEnd` says so, and
    /// `sceneFrameCount` does not move — *"import never changes the shape of the timeline"*.
    ///
    /// The crop is asserted beside the block length on purpose: a block clipped without the crop
    /// following it would play the whole clip squeezed into twelve frames, which is a retime and §2.2
    /// says a crop is not one.
    func testALongClipIsClippedToTheSceneRatherThanTheSceneToTheClip() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        let scene = manager.sceneFrameCount
        XCTAssertTrue(manager.insertVideo(at: try clip(frames: 30, fps: 24, named: "long")))

        XCTAssertEqual(manager.sceneFrameCount, scene, "Import never lengthens the timeline.")
        let cel = try XCTUnwrap(manager.layers.last?.cels.first)
        XCTAssertEqual(cel.startFrame, 0)
        XCTAssertEqual(cel.frameCount, scene)

        let video = try XCTUnwrap(cel.vector?.videos.first)
        XCTAssertEqual(video.sourceStart, .zero, "It holds the head of the clip.")
        XCTAssertEqual(video.sourceEnd, SourceTime(value: Int64(scene), timescale: 24),
                       "And the crop is the scene's length of footage, so the block is a crop and "
                       + "not a retime.")
        XCTAssertEqual(video.speed, 1)
        XCTAssertEqual(VideoFrameMap.frameCount(of: video, documentFPS: 24), scene,
                       "The crop and the block agree, which is what lets a right-edge drag reveal "
                       + "more rather than fight the map.")
    }

    /// A clip shorter than the scene keeps its own length — §2.4 clips *to* the scene, it does not
    /// pad out to it, and a block holding four frames of held tail would be worse than a short one.
    func testAClipShorterThanTheSceneKeepsItsOwnLength() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        XCTAssertGreaterThan(manager.sceneFrameCount, Self.levels.count)
        XCTAssertTrue(manager.insertVideo(at: try shortClip()))

        let cel = try XCTUnwrap(manager.layers.last?.cels.first)
        XCTAssertEqual(cel.frameCount, Self.levels.count)
        XCTAssertLessThan(cel.frameCount, manager.sceneFrameCount)
    }

    /// The imported block shows the head of the clip on the canvas, at the frame the map names —
    /// which is the only assertion here that the import and the reader agree about anything.
    func testTheImportedBlockPlaysFromItsHead() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        XCTAssertTrue(manager.insertVideo(at: try shortClip()))
        let cel = try XCTUnwrap(manager.layers.last?.cels.first)

        for frame in 0..<3 {
            let derived = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: frame))
            let image = try XCTUnwrap(derived.render(.full))
            let grey = try XCTUnwrap(CanvasFixture.greyAt(image, x: 32, y: 32))
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(grey, in: Self.levels), frame,
                           "Document frame \(frame) of the imported block should be source frame \(frame).")
        }
    }

    // MARK: - The bytes

    /// **The import copies the picked file, and that is not tidiness.** `PhotosPicker` hands over a
    /// file the system deletes as soon as the transfer ends, so an element pointing at it would be
    /// an element pointing at nothing by the time anything drew. Deleting the source afterwards is
    /// what says the copy happened.
    func testTheImportOwnsItsOwnCopyOfTheClip() throws {
        let picked = try shortClip(named: "picked")
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: picked))
        try FileManager.default.removeItem(at: picked)

        let video = try XCTUnwrap(manager.layers.last?.cels.first?.vector?.videos.first)
        XCTAssertNotEqual(video.assetURL, picked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.assetURL.path))
        XCTAssertEqual(video.assetURL.lastPathComponent, video.assetFileName,
                       "The staged copy is named the same as the name the package will hold, so a "
                       + "save's `copyAsset` and a load's resolve are looking for one string.")
        XCTAssertNotNil(VideoFrameSource().frame(assetURL: video.assetURL, at: .zero),
                        "And the copy still decodes with the picked file gone.")
    }

    /// **`consumingSource` moves rather than copies**, which is what keeps a half-gigabyte clip from
    /// being written a third time on its way in. Only a caller that owns the file may ask for it, and
    /// `ActionsMenu` does because `PickedMovie` made that copy itself.
    func testConsumingTheSourceMovesItRatherThanCopyingIt() throws {
        let picked = try shortClip(named: "consumed")
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: picked, consumingSource: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: picked.path),
                       "A consumed source is moved, so it is no longer where it was.")
        let video = try XCTUnwrap(manager.layers.last?.cels.first?.vector?.videos.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.assetURL.path))
    }

    // MARK: - Refusals and undo

    /// A file that is not a video adds no layer at all — the refusal happens before the layer, so
    /// there is nothing half-imported to undo.
    func testAFileThatIsNotAVideoIsRefusedWithoutAddingALayer() throws {
        let prose = directory.appendingPathComponent("prose.mov")
        try Data("not a video".utf8).write(to: prose)
        let manager = CanvasFixture.manager(layerCount: 1)
        let before = manager.layers.count
        XCTAssertFalse(manager.insertVideo(at: prose))
        XCTAssertEqual(manager.layers.count, before)
    }

    /// Two undo steps, in the order the import made them: the element, then the layer it arrived on.
    /// `addVectorLayer` records its own structure step, exactly as `insertImage`'s fallback does.
    func testUndoTakesTheVideoBackOutAndThenTheLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let before = manager.layers.count
        XCTAssertTrue(manager.insertVideo(at: try shortClip()))

        manager.undo()
        XCTAssertEqual(manager.layers.count, before + 1, "The first undo is the element.")
        XCTAssertTrue(try XCTUnwrap(manager.layers.last?.cels.first?.vector).videos.isEmpty)

        manager.undo()
        XCTAssertEqual(manager.layers.count, before, "The second is the layer it arrived on.")
    }

    // MARK: - Support

    private func shortClip(named name: String = "short") throws -> URL {
        try clip(frames: Self.levels.count, fps: 24, named: name)
    }

    /// A clip of `frames` frames. Beyond six the palette repeats, which is fine for every test that
    /// asks about *length* and is why the pixel tests use `shortClip` instead.
    private func clip(frames: Int, fps: Int, named name: String) throws -> URL {
        let url = directory.appendingPathComponent("\(name).mp4")
        let levels = (0..<frames).map { Self.levels[$0 % Self.levels.count] }
        try CanvasFixture.writeGreyClip(levels: levels, fps: fps, side: 64, to: url)
        return url
    }
}
