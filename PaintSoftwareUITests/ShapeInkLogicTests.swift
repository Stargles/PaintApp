import Combine
import IOSurface
import XCTest
import UIKit

/// **A pending smart shape's preview, as the canvas shows it while a handle is dragged** — TODO (179).
///
/// The preview used to be stamped on the main thread into a canvas-sized texture and handed to Core
/// Animation as a fresh canvas-sized image once a run-loop turn of the drag, behind a SwiftUI pass over
/// the whole editor per tick (`updateInteractiveShape` published). Now a tick writes the draft tier and
/// publishes nothing, and the overlay draws the shape's ink (`CanvasManager.shapeInk`) off the main
/// thread into a surface pair, one picture in flight. These pin the three things that has to keep
/// true: the picture is the ink the commit lands, a drag raises no pass, and the overlay's pictures
/// are two surfaces, the first drawn at once and the last of the newest geometry.
@MainActor
final class ShapeInkLogicTests: XCTestCase {

    /// A pending line on the fixture's raster layer, adjustable — the pen has lifted.
    private func pendingLine(_ manager: CanvasManager) -> ShapeGeometry {
        manager.toolProfiles.brush.size = 6
        let line = ShapeGeometry(kind: .line, startPoint: CGPoint(x: 10, y: 12), endPoint: CGPoint(x: 50, y: 40))
        manager.beginInteractiveShape(line, samples: (0...20).map {
            VectorSample(x: 10 + 2 * CGFloat($0), y: 12 + 1.4 * CGFloat($0), pressure: 0.4 + 0.03 * CGFloat($0))
        })
        manager.endInteractiveShape()
        return line
    }

    /// One tick of a drag of the line's far end, `step` of the way.
    private func dragEnd(_ manager: CanvasManager, step: Int) {
        manager.updateInteractiveShape(endPoint: CGPoint(x: 50 - CGFloat(step), y: 40 + CGFloat(step) / 2))
    }

    /// `image` drawn into a premultiplied RGBA bitmap of the fixture's canvas, its bytes.
    private func rgba(_ image: UIImage) -> [UInt8] {
        let size = CanvasFixture.canvasSize
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            UIGraphicsPushContext(context)
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(origin: .zero, size: size))
            UIGraphicsPopContext()
        }
        return bytes
    }

    /// `ink` drawn the way the overlay's surface draws it — into a UIKit context over the canvas.
    private func picture(of ink: ShapeInk) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: ink.canvasSize, format: format).image { ink.draw(into: $0.cgContext) }
    }

    /// **The preview is the ink the commit lands.** Two producers: the ink the overlay draws, stamped
    /// into a context of its own, and the raster cel after `commitInteractiveShape` stamped the shape into
    /// it through the commit's own path — the geometry a drag left, collapsed, at the brush, colour,
    /// size, opacity and random field taken when the shape formed. If they differed the artist would
    /// watch the shape change the moment it baked.
    func testThePreviewIsTheInkTheCommitLands() throws {
        let manager = CanvasFixture.manager()
        _ = pendingLine(manager)
        for step in 1...20 { dragEnd(manager, step: step) }
        let preview = rgba(picture(of: try XCTUnwrap(manager.shapeInk, "a pending shape has ink")))
        let inked = preview.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count
        XCTAssertGreaterThan(inked, 60, "the preview stamped a stroke — \(inked) pixels with ink")

        manager.commitInteractiveShape()
        let landed = rgba(manager.layers[0].cels[0].raster.renderToUIImage())
        let worst = zip(preview, landed).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 1, "the preview and the ink the commit landed differ by \(worst) in a channel")
    }

    /// **A drag of the shape publishes nothing.** Sixty ticks of a handle drag write the draft tier;
    /// the canvas re-lays the overlay itself, and nothing else in the editor draws the shape — so a
    /// tick that sent `objectWillChange` would be a SwiftUI pass over the whole editor for nothing.
    func testAHandleDragPublishesNothing() {
        let manager = CanvasFixture.manager()
        let line = pendingLine(manager)
        var sends = 0
        let watch = manager.objectWillChange.sink { sends += 1 }
        for step in 1...60 { dragEnd(manager, step: step % 30) }
        manager.updateInteractiveShape(isConstrained: true)
        watch.cancel()
        XCTAssertEqual(sends, 0, "a tick of the drag raised \(sends) passes over the editor across 61 ticks")
        XCTAssertNotEqual(manager.resolvedShape, line, "and the drag reached the shape")
    }

    /// The overlay's preview surface, once a shape is up.
    private func surface(of overlay: ShapeOverlayView) -> WindowSurfaceView? {
        overlay.subviews.flatMap(\.subviews).compactMap { $0 as? WindowSurfaceView }.first
    }

    /// **A drag is pictures in one surface view, as fast as one stamp, ending on the newest geometry.**
    /// The first picture of a shape is drawn in the turn the shape appears — it replaces the freehand
    /// stroke the hold reverted, so a turn with neither would blink. Thirty ticks with no turn between
    /// them are then at most two more pictures — the one minted at once and the newest waiting — never
    /// thirty, and the one left on the surface is the last tick's ink. All of them go through the one
    /// `WindowSurfaceView` the shape was given, whose contents are its own two `IOSurface`s
    /// (`WindowSurfaceViewLogicTests`): nothing new is handed to Core Animation per picture.
    func testADragIsPicturesInOneSurfaceViewTheFirstAtOnceAndTheLastOfTheNewestTick() throws {
        let manager = CanvasFixture.manager()
        let line = pendingLine(manager)
        let overlay = ShapeOverlayView(frame: CGRect(origin: .zero, size: CanvasFixture.canvasSize))
        overlay.isActive = true
        overlay.update(shape: line, ink: manager.shapeInk, showHandles: true)
        XCTAssertEqual(overlay.previewDrawCount, 1, "the first picture is drawn in the turn the shape appears")
        let preview = try XCTUnwrap(surface(of: overlay), "the overlay shows the shape through a surface")

        for step in 1...30 {
            dragEnd(manager, step: step)
            overlay.update(shape: try XCTUnwrap(manager.resolvedShape), ink: manager.shapeInk, showHandles: true)
        }
        var settled = overlay.previewDrawCount
        let deadline = Date().addingTimeInterval(3)
        repeat {
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            if overlay.previewDrawCount == settled { break }
            settled = overlay.previewDrawCount
        } while Date() < deadline
        XCTAssertGreaterThan(overlay.previewDrawCount, 1, "the drag was drawn")
        XCTAssertLessThanOrEqual(overlay.previewDrawCount, 3,
                                 "thirty ticks with no turn between them were \(overlay.previewDrawCount) pictures")
        XCTAssertTrue(surface(of: overlay) === preview, "every picture of the drag went through one surface view")

        let shown = try XCTUnwrap(preview.layer.contents as? IOSurface, "the contents are a surface")
        let newest = rgba(picture(of: try XCTUnwrap(manager.shapeInk)))
        _ = shown.lock(options: [.readOnly], seed: nil)
        defer { _ = shown.unlock(options: [.readOnly], seed: nil) }
        let bytes = shown.baseAddress.assumingMemoryBound(to: UInt8.self)
        var worst = 0
        for y in 0..<Int(CanvasFixture.canvasSize.height) {
            for x in 0..<Int(CanvasFixture.canvasSize.width) {
                let i = y * shown.bytesPerRow + x * 4, j = (y * Int(CanvasFixture.canvasSize.width) + x) * 4
                // BGRA on the surface against RGBA in the reference.
                worst = max(worst, abs(Int(bytes[i + 3]) - Int(newest[j + 3])),
                            abs(Int(bytes[i + 2]) - Int(newest[j])), abs(Int(bytes[i]) - Int(newest[j + 2])))
            }
        }
        XCTAssertLessThanOrEqual(worst, 1, "the picture left up is not the last tick's ink — \(worst) apart in a channel")

        overlay.isActive = false
        XCTAssertNil(surface(of: overlay), "the shape gone, its surfaces go with it")
    }
}
