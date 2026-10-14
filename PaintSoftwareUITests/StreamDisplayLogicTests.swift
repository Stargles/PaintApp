import XCTest
import UIKit

@MainActor
final class StreamDisplayLogicTests: XCTestCase {
    private let side = CGSize(width: 64, height: 64)

    private func fixture(inPlace: Bool = true) -> (CanvasManager, VectorCanvas, UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let vector = manager.layers[1].cels[0].vector!
        let stream = VectorStreamElement(naturalSize: CGSize(width: 20, height: 8), host: "laptop", port: 47301,
            sourceLabel: "fixture", rendersInPlace: inPlace,
            transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
        vector.elements = [.stream(stream)]
        vector.bumpVersion()
        _ = vector.setStreamFrame(id: stream.id, image: image(.red, size: stream.naturalSize), index: 1)
        return (manager, vector, stream.id)
    }

    private func image(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let cg = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0, y: CGFloat(image.height)); cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }

    private func centre(_ display: StreamDisplayRecipe) throws -> [UInt8] {
        let out = try XCTUnwrap(display.recipe.composite())
        return rgba(out, x: 32 - Int(display.buffer.minX), y: 32 - Int(display.buffer.minY))
    }

    func testOnTopMakesNoDisplayRecipeAndToggleChangesOnlyTheAddressedCel() throws {
        let (manager, vector, id) = fixture(inPlace: false)
        let version = vector.documentVersion
        XCTAssertNil(manager.makeStreamDisplayRecipe())
        let twin = vector.makeCopy()
        manager.layers[1].cels.append(Cel(id: UUID(), startFrame: 12, frameCount: 12,
            raster: RasterLayerTexture(size: side), vector: twin))
        XCTAssertTrue(manager.setStreamInPlace(layerIndex: 1, celIndex: 0, elementID: id, true))
        XCTAssertFalse(twin.streams[0].rendersInPlace)
        XCTAssertEqual(vector.documentVersion, version)
        XCTAssertNotNil(manager.makeStreamDisplayRecipe())
        XCTAssertNil(manager.activeStreamNote)
    }

    func testStreamFrameIsFrozenAndNeverEntersTheOrdinaryRecipe() throws {
        let (manager, vector, id) = fixture()
        let first = try XCTUnwrap(manager.makeStreamDisplayRecipe())
        _ = vector.setStreamFrame(id: id, image: image(.green, size: CGSize(width: 20, height: 8)), index: 2)
        XCTAssertEqual(try centre(first), [255, 0, 0, 255], "the older recipe owns its frame")
        XCTAssertEqual(try centre(XCTUnwrap(manager.makeStreamDisplayRecipe())), [0, 255, 0, 255], "the next recipe owns the newest frame")
        let saved = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false)?.composite())
        XCTAssertEqual(rgba(saved, x: 32, y: 32), [0, 0, 0, 0], "every kept picture remains reference-free")
    }

    func testOwnBlendAndUpperEffectReachTheStream() throws {
        let (manager, _, _) = fixture()
        manager.layers[0].cels[0].bakedImage = image(.black, size: side)
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
        XCTAssertEqual(try centre(XCTUnwrap(manager.makeStreamDisplayRecipe())), [0, 0, 0, 255])
        manager.setLayerBlendMode(layerIndex: 1, to: .normal)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: -1)))
        let graded = try centre(XCTUnwrap(manager.makeStreamDisplayRecipe()))
        XCTAssertLessThan(graded[0], 20, "the upper grade reads the live red screen")
    }

    func testScratchIsARealLayerSourceUnderTheUpperBlendWhileHeld() throws {
        let (manager, _, _) = fixture()
        manager.addVectorLayer()
        manager.layers[2].blendMode = .multiply
        let ink = PixelOps.InkWindow(image: image(.black, size: CGSize(width: 12, height: 4)),
            rect: CGRect(x: 26, y: 30, width: 12, height: 4), canvasSize: side, opacity: 1, replacesBase: false)
        let display = try XCTUnwrap(manager.makeStreamDisplayRecipe(
            display: [manager.layers[2].id: PixelOps.CelDisplay(windows: [ink])], transientBounds: ink.rect))
        XCTAssertEqual(try centre(display), [0, 0, 0, 255], "upper ink covers the screen before lift")
        XCTAssertEqual(try centre(XCTUnwrap(manager.makeStreamDisplayRecipe())), [255, 0, 0, 255], "cancelling the scratch exposes the screen")
    }

    func testMaskCanReadTheLiveStreamAndClipUpperInk() throws {
        let (manager, _, _) = fixture()
        manager.addVectorLayer()
        manager.layers[2].cels[0].bakedImage = image(.blue, size: side)
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])
        let display = try XCTUnwrap(manager.makeStreamDisplayRecipe())
        XCTAssertEqual(try centre(display), [0, 0, 255, 255])
        let out = try XCTUnwrap(display.recipe.composite())
        let pixel = rgba(out, x: 5, y: 32 - Int(display.buffer.minY))
        XCTAssertNotEqual(pixel, [0, 0, 255, 255], "the upper ink is clipped off the stream's footprint")
    }

    func testWindowUsesOnlyAffectedRowsAndDirectVectorDraw() throws {
        let (manager, vector, _) = fixture()
        let count = vector.rasterizations
        let total = VectorCanvas.totalRasterizations
        let display = try XCTUnwrap(manager.makeStreamDisplayRecipe())
        let out = try XCTUnwrap(display.recipe.composite())
        XCTAssertEqual(out.width, 64)
        XCTAssertLessThan(out.height, 16, "an eight-row screen allocates its window, not a 64-row canvas")
        XCTAssertEqual(vector.rasterizations, count, "window resolve never asks the native vector memo to render")
        XCTAssertEqual(VectorCanvas.totalRasterizations, total, "no detached full-canvas intermediate is allocated either")
        XCTAssertEqual(try centre(display), [255, 0, 0, 255])
    }

    func testOutputReachHasAnotherInputApronAndNestedStripsKeepTheirOrigin() throws {
        let windows = try XCTUnwrap(StreamDisplayRecipe.windows(footprint: CGRect(x: 10, y: 30, width: 8, height: 4),
            canvasSize: CGSize(width: 100, height: 100), apron: 5))
        XCTAssertEqual(windows.core, CGRect(x: 0, y: 25, width: 100, height: 14))
        XCTAssertEqual(windows.buffer, CGRect(x: 0, y: 20, width: 100, height: 24))
        let (manager, _, _) = fixture()
        let whole = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true))
        let nested = whole.windowed(to: CGRect(x: 0, y: 10, width: 64, height: 30))
            .windowed(to: CGRect(x: 0, y: 5, width: 64, height: 10))
        XCTAssertEqual(nested.window?.origin, CGPoint(x: 0, y: 15))
        XCTAssertEqual(nested.window?.frameSize, side)
    }

    func testInPlaceLeavesThePlainRunAndMixedStreamsIncludeOnlyTheChosenReferences() throws {
        let (manager, _, _) = fixture()
        XCTAssertEqual(manager.onTopStreamLayerIndices(), [], "In Place does not keep a permanent plain pair")
        manager.addVectorLayer()
        let top = manager.layers[2].cels[0].vector!
        let green = VectorStreamElement(naturalSize: CGSize(width: 20, height: 8), host: "another", port: 47301,
            sourceLabel: "on top", transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
        top.elements = [.stream(green)]; top.bumpVersion()
        _ = top.setStreamFrame(id: green.id, image: image(.green, size: green.naturalSize), index: 1)
        XCTAssertEqual(manager.onTopStreamLayerIndices(), [2])
        XCTAssertEqual(try centre(XCTUnwrap(manager.makeStreamDisplayRecipe())), [255, 0, 0, 255],
            "the window contains the In Place reference; the On Top host supplies green above it")
    }

    func testGuideBetweenStreamAndActiveHostIsPartOfTheWindowTree() throws {
        let (manager, _, _) = fixture()
        manager.addValueLayer(effect: .guide(Effect.Guide(spacing: 8, lineWidth: 2, opacity: 1)))
        manager.addVectorLayer()
        let pixel = try centre(XCTUnwrap(manager.makeStreamDisplayRecipe()))
        XCTAssertGreaterThan(Int(pixel[2]), Int(pixel[0]) + 60,
            "a Guide between the screen and the active host still draws its blue line")
    }

    func testScratchOpacityAndReplacementAreAppliedAtTheirLayer() throws {
        let (manager, _, _) = fixture()
        manager.addVectorLayer()
        let rect = CGRect(x: 26, y: 30, width: 12, height: 4)
        let ink = PixelOps.InkWindow(image: image(.black, size: rect.size), rect: rect,
            canvasSize: side, opacity: 0.5, replacesBase: false)
        let faded = try centre(XCTUnwrap(manager.makeStreamDisplayRecipe(
            display: [manager.layers[2].id: PixelOps.CelDisplay(windows: [ink])], transientBounds: rect)))
        XCTAssertLessThanOrEqual(abs(Int(faded[0]) - 128), 1, "scratch opacity is applied exactly once")
        manager.layers[2].cels[0].bakedImage = image(.black, size: side)
        let hole = PixelOps.InkWindow(image: image(.clear, size: rect.size), rect: rect,
            canvasSize: side, opacity: 1, replacesBase: true)
        let erased = try centre(XCTUnwrap(manager.makeStreamDisplayRecipe(
            display: [manager.layers[2].id: PixelOps.CelDisplay(windows: [hole])], transientBounds: rect)))
        XCTAssertEqual(erased, [255, 0, 0, 255], "a replacement clears the upper source, exposing the live red screen")
    }

    func testAnInPlaceReferenceMovedOffCanvasNeedsNoDisplaySurface() throws {
        let (manager, vector, _) = fixture()
        vector.elements = vector.elements.map { element in
            guard case .stream(var stream) = element else { return element }
            stream.transform.position = CGPoint(x: 200, y: 200)
            return .stream(stream)
        }
        vector.bumpVersion()
        XCTAssertEqual(manager.inPlaceStreams().count, 0)
        XCTAssertNil(manager.makeStreamDisplayRecipe(), "no stale window is retained for a reference off the canvas")
    }

    func testAHeldContainerPoseStillHidesItsStreamUntilCancelled() throws {
        let (manager, _, _) = fixture()
        manager.addTransformLayer(name: "mover")
        var pose = try XCTUnwrap(manager.layers[2].transform)
        pose.track = TransformTrack(box: CGRect(origin: .zero, size: side),
            curves: [.x: AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 40)])])
        manager.holdLiveEdit(.pose(LivePose(layerID: manager.layers[2].id, holding: pose)))
        XCTAssertNil(manager.makeStreamDisplayRecipe(), "held poses do not show an unposed reference")
        manager.endLiveEdit()
        XCTAssertNotNil(manager.makeStreamDisplayRecipe(), "cancelling restores the reference's window")
    }

    /// Deleted with the throwaway repair: a real baseline 5d73184 save, not JSON made by this build.
    func testPreviousBuildPackageRepairsEveryLibraryRootAndRoundTripsItsPicture() throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "stream-before-placement", withExtension: "paintproj"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "stream-repair-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let originalRoot = ProjectBackupManager.rootDirectoryOverride
        let originalSettings = ProjectBackupManager.settings
        ProjectBackupManager.rootDirectoryOverride = root
        ProjectBackupManager.settings = AppSettings(defaults: defaults)
        defer {
            ProjectBackupManager.rootDirectoryOverride = originalRoot
            ProjectBackupManager.settings = originalSettings
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let packages = ["Projects/previous.paintproj", "Backups/previous/older.paintproj", "Trash/previous.paintproj"].map {
            root.appendingPathComponent($0)
        }
        for package in packages {
            try FileManager.default.createDirectory(at: package.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: package)
        }
        let originalDrawing = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: source.appendingPathComponent("drawings"), includingPropertiesForKeys: nil).first)
        let originalBytes = try Data(contentsOf: originalDrawing)
        LegacyStreamPlacementRepair.repairLibrary()
        LegacyMaskRepair.repairLibrary()
        let untouched = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
        let pristine = try XCTUnwrap(ProjectBackupManager.allProjectPackages(in: root.appendingPathComponent("Backups"))
            .first { $0.lastPathComponent.hasPrefix(untouched) })
        let pristineDrawing = pristine.appendingPathComponent("drawings/\(originalDrawing.lastPathComponent)")
        XCTAssertEqual(try Data(contentsOf: pristineDrawing), originalBytes, "the before-update original is pristine")
        func fileBytes(in package: URL) throws -> [String: Data] {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: package,
                includingPropertiesForKeys: [.isRegularFileKey]))
            var bytes: [String: Data] = [:]
            for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                bytes[String(file.path.dropFirst(package.path.count))] = try Data(contentsOf: file)
            }
            return bytes
        }
        let pristineBytes = try fileBytes(in: pristine)
        XCTAssertTrue(ProjectBackupManager.restoreBackup(at: pristine, toProjectAt: packages[0]),
                      "an actual previous-build snapshot is repaired on its staged restore copy")
        XCTAssertEqual(try fileBytes(in: pristine), pristineBytes,
                       "restoring preserves every original snapshot file byte for byte")
        for package in packages {
            let loaded = try XCTUnwrap(ProjectStore.load(from: package))
            XCTAssertTrue(!loaded.loadDamage.isDamaged, "strict load after repair has no lost marks in \(package.path)")
            let vector = try XCTUnwrap(loaded.layers.first(where: { $0.cels.contains { $0.vector?.holdsStream == true } })?.cels.first?.vector)
            let stream = try XCTUnwrap(vector.streams.first)
            XCTAssertFalse(stream.rendersInPlace, "old streams retain On Top")
            let picture = try XCTUnwrap(stream.displayFrame?.cgImage)
            let pixel = rgba(picture, x: picture.width / 2, y: picture.height / 2)
            XCTAssertGreaterThan(pixel[0], 240, "the previous build's red last frame survives")
            XCTAssertLessThan(pixel[1], 50, "the saved red H.264/JPEG frame stays red")
        }
        let loaded = try XCTUnwrap(ProjectStore.load(from: packages[0]))
        let rewritten = root.appendingPathComponent("Projects/roundtrip.paintproj")
        let saved = expectation(description: "strict repaired save")
        ProjectStore.save(loaded, to: rewritten) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: rewritten))
        XCTAssertTrue(!reloaded.loadDamage.isDamaged)
        let streams = reloaded.layers.flatMap { $0.cels.flatMap { $0.vector?.streams ?? [] } }
        XCTAssertEqual(streams.count, 1)
        XCTAssertFalse(try XCTUnwrap(streams.first).rendersInPlace)
    }

    func testPriorStreamRecordNeedsRepairAndRepairPreservesExistingChoice() throws {
        let (_, vector, _) = fixture()
        let data = try JSONEncoder().encode(VectorCanvasData(from: vector, imageFileNames: [:]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var elements = try XCTUnwrap(object["elements"] as? [[String: Any]])
        var stream = try XCTUnwrap(elements[0]["stream"] as? [String: Any])
        stream.removeValue(forKey: "rendersInPlace"); elements[0]["stream"] = stream; object["elements"] = elements
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(VectorCanvasData.self, from: old).decodeReport.isClean,
                       "the current decoder has no legacy default")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let drawing = root.appendingPathComponent("drawings/cel.json")
        try FileManager.default.createDirectory(at: drawing.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try old.write(to: drawing)
        XCTAssertEqual(LegacyStreamPlacementRepair.repair(packageAt: root), .repaired)
        let repaired = try JSONDecoder().decode(VectorCanvasData.self, from: Data(contentsOf: drawing))
        XCTAssertTrue(repaired.decodeReport.isClean)
        XCTAssertFalse(try XCTUnwrap(repaired.streams.first).rendersInPlace)
        XCTAssertEqual(LegacyStreamPlacementRepair.repair(packageAt: root), .current)
        try data.write(to: drawing)
        XCTAssertEqual(LegacyStreamPlacementRepair.repair(packageAt: root), .current)
        XCTAssertTrue(try XCTUnwrap(JSONDecoder().decode(VectorCanvasData.self, from: Data(contentsOf: drawing)).streams.first).rendersInPlace)
    }
}
