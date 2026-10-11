import XCTest
import SwiftUI
import UIKit
import Combine

/// **A fill slider's tick is a render of the adjustable fill and nothing else** — TODO (157). The owner:
/// *"The gap closing slider in the fill tool is being janky for some reason."*
///
/// Each tick used to write the slider's value into a `@Published` property of `CanvasManager` and the
/// render's picture into the cel, so every tick was a SwiftUI pass over the editor and a document
/// change the canvas re-baked. These pin the replacement from the model's side: the value lives in
/// `FillSettings`, the picture in `CanvasManager.liveFill`, the canvas hears of it through
/// `onHeldPictureMoved`, and the document changes once — at the commit, as one undo step.
final class FillLiveSliderLogicTests: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    /// A 64² document whose only layer holds a black box with a 6 px opening in its right side, and a
    /// fill tapped inside it with the slider at 0 — so the fill leaks out through the opening until the
    /// slider seals it.
    private func adjustableFill() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            for rect in [CGRect(x: 10, y: 10, width: 44, height: 3), CGRect(x: 10, y: 51, width: 44, height: 3),
                         CGRect(x: 10, y: 10, width: 3, height: 44), CGRect(x: 51, y: 10, width: 3, height: 19),
                         CGRect(x: 51, y: 35, width: 3, height: 19)] {
                ctx.fill(rect)
            }
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        manager.addLayer()
        manager.brushColor = Self.red
        manager.setFillSetting(.gapClosing, 0)
        manager.beginInteractiveFill(at: CGPoint(x: 30, y: 30))
        manager.endInteractiveFill()
        settle()
        return manager
    }

    private func settle(_ seconds: TimeInterval = 0.4) {
        let done = expectation(description: "the render's hop to main has run")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    private func alpha(_ preview: FillPreview?, at point: CGPoint) -> UInt8 {
        guard let preview, let cg = preview.image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg),
              preview.rect.contains(point) else { return 0 }
        let x = Int(point.x - preview.rect.minX), y = Int(point.y - preview.rect.minY)
        return bytes[(y * cg.width + x) * 4 + 3]
    }

    /// **Zero `objectWillChange` per tick, and the picture follows.** Eight slider values with the
    /// fill adjustable: the canvas manager publishes nothing — no editor pass, no document change —
    /// while `FillSettings` publishes each value, the canvas is told every new picture, and the last
    /// picture is the sealed fill: the opening at the slider's top no longer lets it out.
    func testATickPublishesNothingOnTheManagerAndTheCanvasIsToldThePicture() throws {
        let manager = adjustableFill()
        let outside = CGPoint(x: 60, y: 32)
        XCTAssertGreaterThan(alpha(manager.liveFill?.preview, at: outside), 0,
                             "Fixture check: at 0 the fill leaks out through the opening")

        var managerChanges = 0, settingsChanges = 0, told = 0
        let a = manager.objectWillChange.sink { managerChanges += 1 }
        let b = manager.fillSettings.objectWillChange.sink { settingsChanges += 1 }
        manager.onHeldPictureMoved = { told += 1 }
        defer { a.cancel(); b.cancel() }
        let versions = manager.layers.map { $0.cels.map { $0.raster.version } }

        for gap in stride(from: CGFloat(5), through: 40, by: 5) {
            manager.setFillSetting(.gapClosing, gap)
            manager.fillQueue.sync {}
            settle(0.15)
        }

        XCTAssertEqual(managerChanges, 0, "a tick raises no pass over the editor")
        XCTAssertGreaterThanOrEqual(settingsChanges, 8, "the sliders hear every value")
        XCTAssertGreaterThanOrEqual(told, 1, "the canvas is told the new picture")
        XCTAssertEqual(manager.layers.map { $0.cels.map { $0.raster.version } }, versions,
                       "no cel is written while the fill is adjustable")
        XCTAssertEqual(alpha(manager.liveFill?.preview, at: outside), 0, "the sealed fill stays inside the box")
        XCTAssertGreaterThan(alpha(manager.liveFill?.preview, at: CGPoint(x: 14, y: 14)), 0,
                             "…and reaches into its corner")
    }

    /// **The document changes once, at the commit, as one undo step**, and the picture it lands is the
    /// one the slider left on screen.
    func testTheCommitWritesTheSlidersLastPictureAsOneUndoStep() throws {
        let manager = adjustableFill()
        let before = manager.history.undoStack.count
        for gap in stride(from: CGFloat(5), through: 40, by: 5) {
            manager.setFillSetting(.gapClosing, gap)
            manager.fillQueue.sync {}
            settle(0.15)
        }
        XCTAssertEqual(manager.history.undoStack.count, before, "no step while the slider moves")
        let shown = try XCTUnwrap(manager.liveFill?.preview)

        manager.commitInteractiveFill()

        XCTAssertNil(manager.liveFill, "the picture is let go")
        XCTAssertEqual(manager.history.undoStack.count, before + 1, "one step for the fill")
        let landed = try XCTUnwrap(manager.layers[1].cels.first?.raster.renderToUIImage().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(landed))
        for point in [CGPoint(x: 30, y: 30), CGPoint(x: 14, y: 14), CGPoint(x: 60, y: 32)] {
            let landedAlpha = bytes[(Int(point.y) * landed.width + Int(point.x)) * 4 + 3]
            XCTAssertEqual(landedAlpha > 0, alpha(shown, at: point) > 0, "the commit lands what was shown at \(point)")
        }
    }

    /// **While a fill is adjustable its layer's host draws itself**, whatever the compositor would
    /// otherwise show — the bake holds no fill that has not landed — and not a moment longer.
    @MainActor
    func testTheFillsLayerIsAHeldHostWhileTheFillIsUp() throws {
        let manager = adjustableFill()
        XCTAssertEqual(manager.heldHostLayerIndices, [1], "the fill lands on layer 1, so its host draws it")
        manager.commitInteractiveFill()
        XCTAssertEqual(manager.heldHostLayerIndices, [], "committed: the document holds it now")

        let cancelled = adjustableFill()
        cancelled.cancelInteractiveFill()
        XCTAssertNil(cancelled.liveFill)
        XCTAssertEqual(cancelled.heldHostLayerIndices, [], "cancelled: nothing to draw")
    }
}
