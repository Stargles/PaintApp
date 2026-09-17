import XCTest
import UIKit

/// **Surviving the computer being off** — STREAM.md §2.8 and §5.6, through a real package.
///
/// A stream that had a picture is saved; the package holds that picture as a JPEG beside the placed
/// images; the reloaded document *draws* it — pixels, through the real render — before any laptop
/// has answered, and the coordinator starts a client for it without blocking anything. The
/// reloaded element's own picture is then the thing Bake Frame bakes, which is what makes a bake
/// with the laptop off possible at all.
@MainActor
final class StreamPersistenceLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stream-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func status() -> StreamStatus {
        StreamStatus(source: StreamStatus.Source(kind: "window", name: "Blender"),
                     width: 8, height: 4, fps: 30, streaming: true)
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) -> SaveDecision {
        let finished = expectation(description: "ProjectStore.save completion")
        let decision = ProjectStore.save(manager, to: url, intent: .artist) { finished.fulfill() }
        if decision == .ask { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        return decision
    }

    /// RGBA at a canvas point of a cel's own render.
    private func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard let cg = image.cgImage else { return (0, 0, 0, 0) }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / CanvasFixture.canvasSize.width
        let i = (Int(CGFloat(y) * scale) * width + Int(CGFloat(x) * scale)) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// A manager holding one committed stream whose element has a solid green frame, as a tick
    /// would leave it.
    private func managerWithAGreenFrame() throws -> (CanvasManager, VectorStreamElement, VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        let element = try XCTUnwrap(manager.insertStream(host: "laptop", port: 47301, status: status()))
        manager.commitVectorFloatIfNeeded()
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        let frame = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 4),
                                             size: CGSize(width: 8, height: 4))
        XCTAssertTrue(vector.setStreamFrame(id: element.id, image: frame, index: 1))
        return (manager, element, vector)
    }

    private func streamElement(in manager: CanvasManager) -> (VectorCanvas, VectorStreamElement)? {
        for layer in manager.layers where layer.kind == .vector {
            for cel in layer.cels {
                if let vector = cel.vector, let stream = vector.streams.first { return (vector, stream) }
            }
        }
        return nil
    }

    // MARK: - Save → reload

    /// **The saved document draws the saved picture before the laptop answers.** The JPEG is in
    /// the package under `images/`, the ref names it, the reloaded element carries it, and the
    /// reloaded cel renders green at the stream's centre — against a placeholder that is grey.
    func testAReloadedStreamDrawsThePictureTheSaveWrote() throws {
        let (manager, _, vector) = try managerWithAGreenFrame()
        let before = pixel(vector.render(), 32, 32)
        XCTAssertGreaterThan(Int(before.g), Int(before.r) + 100, "Setup: the live picture is green")

        let projectURL = ProjectStore.createNewProjectURL(name: "WithStream")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)

        // The file is in the package, beside the placed images, as a JPEG.
        let images = projectURL.appendingPathComponent("images")
        let written = (try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []
        let jpegs = written.filter { $0.contains("_stream_") && $0.hasSuffix(".jpg") }
        XCTAssertEqual(jpegs.count, 1, "one last-frame JPEG for one stream: \(written)")
        let bytes = try Data(contentsOf: images.appendingPathComponent(try XCTUnwrap(jpegs.first)))
        XCTAssertEqual([UInt8](bytes.prefix(2)), [0xFF, 0xD8], "a JPEG, by its magic")

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        XCTAssertFalse(reopened.loadDamage.isDamaged, "a missing stream picture would not be damage, and this one is present")
        let (reloadedVector, reloaded) = try XCTUnwrap(streamElement(in: reopened))
        XCTAssertEqual(reloaded.lastFrameFileName, jpegs.first, "the ref names the file")
        XCTAssertNotNil(reloaded.displayFrame, "the picture is on the element at load")

        let after = pixel(reloadedVector.render(), 32, 32)
        XCTAssertEqual(after.a, 255)
        XCTAssertGreaterThan(Int(after.g), Int(after.r) + 100, "the reloaded cel draws the saved green")
        XCTAssertEqual(pixel(reloadedVector.render(), 2, 2).a, 0, "and nothing outside the rect")

        // And the reloaded picture is what a bake with the laptop off bakes.
        reopened.streamCoordinator.startsClients = false
        let layerIndex = try XCTUnwrap(reopened.layers.firstIndex { $0.cels.first?.vector?.holdsStream == true })
        XCTAssertEqual(reopened.bakeStreamFrame(layerIndex: layerIndex, celIndex: 0, atFrame: 0), .baked)
        let bakedVector = try XCTUnwrap(reopened.layers[layerIndex].cels[0].vector)
        XCTAssertNotNil(bakedVector.images.first)
        let baked = pixel(bakedVector.render(), 32, 32)
        XCTAssertGreaterThan(Int(baked.g), Int(baked.r) + 100, "the bake is the saved picture")
    }

    /// A stream that never had a picture writes no JPEG and reloads on its placeholder — nothing
    /// dangling, nothing counted as damage.
    func testAStreamWithNoPictureSavesNoFileAndReloadsOnThePlaceholder() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        XCTAssertNotNil(manager.insertStream(host: "laptop", port: 47301, status: status()))
        manager.commitVectorFloatIfNeeded()
        let projectURL = ProjectStore.createNewProjectURL(name: "NoPicture")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)

        let images = projectURL.appendingPathComponent("images")
        let written = (try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []
        XCTAssertTrue(written.filter { $0.contains("_stream_") }.isEmpty, "no picture, no file: \(written)")

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        XCTAssertFalse(reopened.loadDamage.isDamaged)
        let (_, reloaded) = try XCTUnwrap(streamElement(in: reopened))
        XCTAssertNil(reloaded.lastFrameFileName)
        XCTAssertNil(reloaded.displayFrame)
        XCTAssertEqual(reloaded.host, "laptop")
        XCTAssertFalse(reloaded.isFrozen)
    }

    /// Freeze survives the save — the flag is on the ref — and a frozen element reloads frozen with
    /// its picture, which is the state §5.4 calls a viewing state persisted with the document.
    func testFreezeSurvivesTheSave() throws {
        let (manager, element, _) = try managerWithAGreenFrame()
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: manager.currentLayerIndex, celIndex: 0,
                                              elementID: element.id, true))
        let projectURL = ProjectStore.createNewProjectURL(name: "Frozen")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)
        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        let (_, reloaded) = try XCTUnwrap(streamElement(in: reopened))
        XCTAssertTrue(reloaded.isFrozen)
        XCTAssertNotNil(reloaded.displayFrame)
    }

    /// The second save re-encodes from the picture the load put back — a document opened and
    /// closed with the laptop off keeps its picture, save after save.
    func testASecondSaveWithTheLaptopOffKeepsThePicture() throws {
        let (manager, _, _) = try managerWithAGreenFrame()
        let projectURL = ProjectStore.createNewProjectURL(name: "Twice")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)
        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        reopened.streamCoordinator.startsClients = false
        XCTAssertEqual(saveAndWait(reopened, to: projectURL), .write)
        let again = try XCTUnwrap(ProjectStore.load(from: projectURL))
        let (vector, reloaded) = try XCTUnwrap(streamElement(in: again))
        XCTAssertNotNil(reloaded.displayFrame)
        let p = pixel(vector.render(), 32, 32)
        XCTAssertGreaterThan(Int(p.g), Int(p.r) + 100, "still green after two saves")
    }

    // MARK: - Opening with the laptop unreachable

    /// **Opening a document whose laptop is unreachable blocks nothing.** The coordinator's first
    /// `sync()` starts a client (here: makes one and does not open a socket) and returns at once;
    /// the bar's word is a connecting one; the element keeps its picture; drawing on another layer
    /// is unaffected. Nothing modal, ever (§5.6).
    func testOpeningWithTheLaptopUnreachableDoesNotBlock() throws {
        let (manager, _, _) = try managerWithAGreenFrame()
        let projectURL = ProjectStore.createNewProjectURL(name: "Off")
        XCTAssertEqual(saveAndWait(manager, to: projectURL), .write)

        let reopened = try XCTUnwrap(ProjectStore.load(from: projectURL))
        reopened.streamCoordinator.startsClients = false
        let started = CFAbsoluteTimeGetCurrent()
        reopened.streamCoordinator.sync()
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - started, 0.5, "sync returns at once")
        XCTAssertEqual(reopened.streamCoordinator.referencedEndpoints, [StreamEndpoint(host: "laptop", port: 47301)])
        let (_, reloaded) = try XCTUnwrap(streamElement(in: reopened))
        XCTAssertEqual(reopened.streamCoordinator.barState(for: reloaded), .connecting)
        XCTAssertNotNil(reloaded.displayFrame, "the last picture is up while it waits")

        // A stroke on the raster layer lands as it would in any document.
        reopened.currentLayerIndex = 0
        let raster = reopened.layers[0].cels[0].raster
        raster.beginStroke()
        raster.stampCircle(at: CGPoint(x: 20, y: 20), radius: 6, color: .red, alpha: 1, hardness: 1)
        raster.endStroke()
        XCTAssertTrue(raster.hasContent, "the drawing tools work with the laptop off")
    }
}
