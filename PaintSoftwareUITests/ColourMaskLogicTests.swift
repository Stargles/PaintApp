import XCTest
import UIKit

@MainActor
final class ColourMaskLogicTests: XCTestCase {
    private func fixture(kind: LayerKind = .raster) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.layers[0].isVisible = false
        manager.layers[1].kind = kind
        let source = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
            UIColor.green.setFill(); ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, source)
        CanvasFixture.setBakedContent(manager, layerIndex: 1, CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)], colours: [ColourKey(from: .init(red: 1, green: 0, blue: 0, alpha: 1))])
        return manager
    }

    private func bytes(_ manager: CanvasManager, holding held: HeldEdit? = nil) throws -> [UInt8] {
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false, holding: held))
        let image = try XCTUnwrap(recipe.composite())
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    private func key(_ manager: CanvasManager) throws -> String {
        FrameBakeKey(recipe: try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false)),
                     renderResolution: .full, backend: .coreGraphics).fileName
    }

    func testColourNarrowsHiddenSourceToRedAndEmptyListRestoresAlpha() throws {
        let manager = fixture()
        let colour = try bytes(manager)
        XCTAssertEqual(Array(colour[(16 + 32 * 64) * 4..<(16 + 32 * 64) * 4 + 4]), [0, 0, 255, 255])
        XCTAssertEqual(Array(colour[(48 + 32 * 64) * 4..<(48 + 32 * 64) * 4 + 4]), [0, 0, 0, 0])
        manager.layers[1].alphaMask?.colours = []
        XCTAssertEqual(try bytes(manager)[(48 + 32 * 64) * 4 + 3], 255)
    }

    func testRasterAndVectorAndBothBackendsShareColourCoverage() throws {
        let raster = fixture()
        let vector = fixture(kind: .vector)
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = Compositor.defaultBackend }
        let reference = try bytes(raster)
        XCTAssertEqual(try bytes(vector), reference)
        if CompositorMetalEngine.shared != nil {
            Compositor.backend = .metal
            XCTAssertEqual(try bytes(raster), reference)
        }
    }

    func testColourKeysUseRecoloursRadiusAndSoftRing() {
        let key = ColourKey(from: .init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1), tolerance: 0.2, softness: 0.5)
        let table = ColourKeyTableEntry(key)
        var recolour = RecolorEntry.blank; recolour.key = key
        let entry = RecolorTableEntry(recolour)
        XCTAssertEqual([table.lab.x, table.lab.y, table.lab.z, table.tolerance, table.inner],
                       [entry.fromL, entry.fromA, entry.fromB, entry.tolerance, entry.inner])
        XCTAssertEqual(table.weight(for: table.lab + SIMD3(0.15, 0, 0)),
                       RecolorTableEntry.weight(distance: 0.15, tolerance: 0.2, inner: 0.1), accuracy: 0.00001)
    }

    func testTransparentPixelsCannotMatchBlackAndPremultipliedRedMatchesRed() throws {
        let manager = fixture()
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(UIColor(red: 1, green: 0, blue: 0, alpha: 0.5),
                                      rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        let red = try bytes(manager)
        XCTAssertEqual(red[(16 + 32 * 64) * 4 + 3], 128)
        manager.layers[1].alphaMask?.colours[0].from = .init(red: 0, green: 0, blue: 0, alpha: 1)
        let black = try bytes(manager)
        XCTAssertEqual(black.filter { $0 != 0 }.count, 0)
    }

    func testMultipleColoursUnionAndInvertAfterMembership() throws {
        let manager = fixture()
        manager.layers[1].alphaMask?.colours.append(ColourKey(from: .init(red: 0, green: 1, blue: 0, alpha: 1)))
        let union = try bytes(manager)
        XCTAssertEqual(union[(48 + 32 * 64) * 4 + 3], 255)
        manager.layers[1].alphaMask?.colours.removeLast()
        manager.layers[1].alphaMask?.invert = true
        let inverse = try bytes(manager)
        XCTAssertEqual([inverse[(16 + 32 * 64) * 4 + 3], inverse[(48 + 32 * 64) * 4 + 3]], [0, 255])
    }

    func testEveryColourFieldAndTuningChangeMovesBakeKeyAndCache() throws {
        let manager = fixture()
        let base = try key(manager)
        let mask = try XCTUnwrap(manager.layers[1].alphaMask)
        let request = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false))
        let before = try XCTUnwrap(MaskResolver.coverage(for: [mask], of: request))
        var variants: [AlphaMask] = []
        var colour = mask; colour.colours[0].from.green = 0.1; variants.append(colour)
        var radius = mask; radius.colours[0].tolerance = 0.15; variants.append(radius)
        var softness = mask; softness.colours[0].softness = 0.8; variants.append(softness)
        var threshold = mask; threshold.setTuning(threshold: 0.2, antialiasHalfWidth: 0.01); variants.append(threshold)
        var width = mask; width.setTuning(threshold: 0.1, antialiasHalfWidth: 0.04); variants.append(width)
        var failures = 0
        for variant in variants {
            manager.layers[1].alphaMask = variant
            if try key(manager) == base { failures += 1 }
            if MaskResolver.coverage(for: [variant], of: request) === before { failures += 1 }
        }
        XCTAssertEqual(failures, 0)
    }

    func testNestedSourceMaskChangesInvalidateOuterCoverage() throws {
        let manager = CanvasFixture.manager(layerCount: 3)
        for index in 0..<3 {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                CanvasFixture.solidImage(index == 2 ? .blue : .red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        }
        manager.layers[0].isVisible = false
        manager.layers[1].isVisible = false
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])
        let before = try bytes(manager)
        manager.layers[1].alphaMask?.colours = [ColourKey(from: .init(red: 0, green: 1, blue: 0, alpha: 1))]
        let afterKey = try bytes(manager)
        XCTAssertEqual(before[(32 + 32 * 64) * 4 + 3], 255)
        XCTAssertEqual(afterKey.filter { $0 != 0 }.count, 0)
        manager.layers[1].alphaMask?.colours = []
        _ = try bytes(manager)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
            CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        let afterInk = try bytes(manager)
        XCTAssertEqual(afterInk[(48 + 32 * 64) * 4 + 3], 0)
    }

    func testRearrangingGradedSourceSubtreesMovesCoverageWithUnchangedLeafVersions() throws {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
            CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
            CanvasFixture.solidImage(.red, rect: CGRect(x: 32, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
            CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        let parent = manager.addFolder(name: "Source")
        let first = manager.addFolder(name: "First", parentFolderID: parent)
        let second = manager.addFolder(name: "Second", parentFolderID: parent)
        manager.folders[0].isVisible = false
        manager.folders[1].effect = .hsvShift(.init(hueDegrees: 120))
        manager.layers[0].parentFolderID = first
        manager.layers[1].parentFolderID = second
        manager.layers[2].alphaMask = AlphaMask(sources: [.folder(parent)],
            colours: [ColourKey(from: .init(red: 1, green: 0, blue: 0, alpha: 1))])
        let before = try bytes(manager)
        let originalVersions = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false)).contentVersions
        manager.layers[0].parentFolderID = second
        manager.layers[1].parentFolderID = first
        let after = try bytes(manager)
        XCTAssertEqual(try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false)).contentVersions, originalVersions)
        XCTAssertEqual([before[(16 + 32 * 64) * 4 + 3], before[(48 + 32 * 64) * 4 + 3]], [0, 255])
        XCTAssertEqual([after[(16 + 32 * 64) * 4 + 3], after[(48 + 32 * 64) * 4 + 3]], [255, 0])
    }

    func testStrictMaskRoundTripAndRejectsMissingOrInvalidValues() throws {
        var mask = try XCTUnwrap(fixture().layers[1].alphaMask)
        mask.setTuning(threshold: 0.4, antialiasHalfWidth: 0.12)
        let data = try JSONEncoder().encode(mask)
        XCTAssertEqual(try JSONDecoder().decode(AlphaMask.self, from: data), mask)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "colours")
        XCTAssertThrowsError(try JSONDecoder().decode(AlphaMask.self, from: JSONSerialization.data(withJSONObject: object)))
        object["colours"] = []
        object["antialiasHalfWidth"] = 0.9
        XCTAssertThrowsError(try JSONDecoder().decode(AlphaMask.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testHeldMaskChangesDrawnPictureWithNoSceneWriteThenCommitsOnceAndUndoes() throws {
        let manager = fixture()
        let target = MaskSource.layer(manager.layers[1].id)
        let original = manager.layers[1].alphaMask
        let originalBytes = try bytes(manager)
        let originalKey = try key(manager)
        var publishes = 0
        let observation = manager.objectWillChange.sink { publishes += 1 }
        var heldFrames = 0
        manager.onHeldPictureMoved = { heldFrames += 1 }
        for _ in 0..<8 {
            var held = try XCTUnwrap(original)
            held.colours[0].from = .init(red: 0, green: 1, blue: 0, alpha: 1)
            manager.holdMask(held, for: target)
        }
        XCTAssertEqual(publishes, 0)
        XCTAssertEqual(heldFrames, 8)
        XCTAssertEqual(manager.layers[1].alphaMask, original)
        XCTAssertEqual(try key(manager), originalKey)
        let heldBytes = try bytes(manager, holding: manager.liveEdit)
        XCTAssertEqual([heldBytes[(16 + 32 * 64) * 4 + 3], heldBytes[(48 + 32 * 64) * 4 + 3]], [0, 255])
        XCTAssertTrue(try XCTUnwrap(manager.liveEdit).drawsWholeFrame(canvasEngaged: false))
        manager.commitHeldMask()
        XCTAssertNil(manager.liveEdit)
        XCTAssertEqual(try bytes(manager), heldBytes)
        manager.undo()
        XCTAssertEqual(try bytes(manager), originalBytes)
        withExtendedLifetime(observation) {}
    }

    func testMaskEyedropperReadsTickedHiddenSourcesAndKeepsPanelOpen() throws {
        let manager = fixture()
        let target = MaskSource.layer(manager.layers[1].id)
        let destination = CanvasManager.EyedropperDestination.maskColour(target: target, index: 0)
        let probe = try XCTUnwrap(manager.eyedropperProbe(for: destination, atCanvasPoint: CGPoint(x: 48, y: 32)))
        let colour = try XCTUnwrap(CanvasManager.sampledColor(from: probe, atCanvasPoint: CGPoint(x: 48, y: 32)))
        XCTAssertEqual(colour.hexString, "00FF00")
        XCTAssertTrue(destination.picksIntoAnOpenPanel)
        manager.selectEyedropper(for: destination)
        XCTAssertTrue(manager.applyEyedropperResult(colour))
        XCTAssertEqual(manager.layers[1].alphaMask?.colours[0].from.color.hexString, "00FF00")
    }
}
