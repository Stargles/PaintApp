import Combine
import XCTest
import UIKit

/// **The drafts the canvas draws and the document does not hold yet, ticked without a pass over the
/// editor** — TODO (179): the text box (a Text panel slider, a keystroke, a drag of the box or a grip)
/// and a lifted bitmap's Move box. Each used to send `objectWillChange` on `CanvasManager` per tick (the
/// recipe was `@Published` there, and the bitmap's pose was written into the `@Published` piece), and
/// every view in the editor observes `CanvasManager` — so each tick was a SwiftUI pass over the whole
/// editor for something only the canvas and one panel draw. Now a tick tells the canvas
/// (`onHeldPictureMoved`), the Text panel observes the recipe on its own object (`TextSettings`), and
/// the bitmap's piece learns its travel once, at the lift.
@MainActor
final class DraftTickLogicTests: XCTestCase {

    /// Counts what a block sends: passes over the editor, and the times the canvas was told.
    private struct Sends { var editor = 0; var canvas = 0 }

    private func counting(_ manager: CanvasManager, _ body: () -> Void) -> Sends {
        var sends = Sends()
        let watch = manager.objectWillChange.sink { sends.editor += 1 }
        manager.onHeldPictureMoved = { sends.canvas += 1 }
        body()
        watch.cancel()
        manager.onHeldPictureMoved = nil
        return sends
    }

    private func managerWithABox() -> CanvasManager {
        let manager = CanvasFixture.manager()
        manager.beginTextSession(at: CGPoint(x: 8, y: 8))
        manager.updateTextString("Hi")
        XCTAssertTrue(manager.textGestureActive, "setup: a text box is open")
        return manager
    }

    // MARK: - The text box

    /// **A Text panel slider's tick redraws the panel and the box, and nothing else.** Thirty ticks of
    /// the Size slider, written the way the panel writes them, send nothing over the editor, tell the
    /// canvas each time (it re-lays the box), publish the recipe to the panel each time, and regrow the
    /// pristine box to the new size.
    func testATextPanelTickIsThePanelsAndTheBoxsAndNotTheEditors() {
        let manager = managerWithABox()
        let before = manager.textFrame.size
        let size = manager.textRecipe.typography.pointSize
        var panel = 0
        let panelWatch = manager.textSettings.objectWillChange.sink { panel += 1 }
        let sends = counting(manager) {
            for tick in 1...30 {
                manager.textRecipe.typography.pointSize = size + CGFloat(tick)
                manager.textRecipeDidChange()
            }
        }
        panelWatch.cancel()
        XCTAssertEqual(sends.editor, 0, "30 ticks of a Text panel slider raised \(sends.editor) passes over the editor")
        XCTAssertEqual(sends.canvas, 30, "the canvas was told on every tick")
        XCTAssertGreaterThanOrEqual(panel, 30, "and the panel was, through the recipe's own object")
        XCTAssertGreaterThan(manager.textFrame.size.height, before.height, "the pristine box regrew to the bigger type")
    }

    /// **A keystroke is the box's** — it regrows the box and tells the canvas, and the editor hears nothing.
    func testAKeystrokeTellsTheCanvasAndNotTheEditor() {
        let manager = managerWithABox()
        let before = manager.textFrame.size.width
        let sends = counting(manager) { manager.updateTextString("Hi there") }
        XCTAssertEqual(sends.editor, 0, "a keystroke raised a pass over the editor")
        XCTAssertEqual(sends.canvas, 1)
        XCTAssertGreaterThan(manager.textFrame.size.width, before, "the box grew with the string")
    }

    /// **A drag of the box or a grip ticks the canvas and not the editor; the finger lifting publishes
    /// once.** The lift is a state change the panel and the undo buttons read (`isTextInAdjustableState`),
    /// so it is the one publish a drag makes.
    func testABoxDragAndAGripDragTickTheCanvasAndTheLiftPublishesOnce() {
        let manager = managerWithABox()
        var sends = counting(manager) {
            manager.beginTextFrameDrag()
            for tick in 1...20 { manager.dragTextFrame(toOrigin: CGPoint(x: 8 + CGFloat(tick), y: 8)) }
        }
        XCTAssertEqual(sends.editor, 0, "20 ticks of a box drag raised \(sends.editor) passes over the editor")
        XCTAssertEqual(sends.canvas, 20)
        XCTAssertEqual(manager.textFrame[.topLeft].x, 28, accuracy: 1e-9, "the box went where the finger took it")
        sends = counting(manager) { manager.endTextFrameDrag() }
        XCTAssertEqual(sends.editor, 1, "the lift publishes once")

        sends = counting(manager) {
            manager.beginTextHandleDrag(.rotation)
            for tick in 1...20 { manager.dragTextHandle(to: CGPoint(x: 60, y: 8 + CGFloat(tick))) }
        }
        XCTAssertEqual(sends.editor, 0, "20 ticks of a grip drag raised \(sends.editor) passes over the editor")
        XCTAssertEqual(sends.canvas, 20)
        sends = counting(manager) { manager.endTextHandleDrag() }
        XCTAssertEqual(sends.editor, 1, "the lift publishes once")
    }

    // MARK: - A lifted bitmap's Move box

    /// A pixel selection on the fixture's raster layer, lifted by Move.
    private func managerWithALiftedBitmap() throws -> CanvasManager {
        let manager = CanvasFixture.manager()
        let rect = CGRect(x: 16, y: 24, width: 32, height: 16)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(.black, rect: rect))
        manager.selection = Selection(path: CGPath(rect: rect, transform: nil), bounds: rect)
        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .move, "setup: a lifted bitmap")
        return manager
    }

    /// **A drag of a lifted bitmap's box writes the piece once, at the lift.** Thirty ticks send nothing
    /// over the editor and tell the canvas each time (it moves the ants with the box); the piece the
    /// editor observes stays where the drag found it while the box shows the finger's travel
    /// (`shownFloatingPiece`), and the lift lands the travel on it as one publish.
    func testABitmapsBoxDragWritesThePieceOnceAtTheLift() throws {
        let manager = try managerWithALiftedBitmap()
        let lifted = try XCTUnwrap(manager.floatingPiece?.transform)
        var travel = lifted
        // The touch-down is a publish of its own (the live transform edit opens), once a gesture.
        manager.moveBoxTouched()
        let sends = counting(manager) {
            for tick in 1...30 {
                travel.position = CGPoint(x: lifted.position.x + CGFloat(tick) / 3, y: lifted.position.y + 1)
                manager.updateFloatingPose(transform: travel, distortQuad: nil)
            }
        }
        XCTAssertEqual(sends.editor, 0, "30 ticks of the box raised \(sends.editor) passes over the editor")
        XCTAssertEqual(sends.canvas, 30, "the canvas was told on every tick, so the ants ride the box")
        XCTAssertEqual(manager.floatingPiece?.transform, lifted, "the published piece waits for the lift")
        XCTAssertEqual(manager.shownFloatingPiece?.transform, travel, "while the box shows the finger's travel")

        var published = 0
        let watch = manager.objectWillChange.sink { published += 1 }
        manager.moveBoxLifted()
        watch.cancel()
        XCTAssertEqual(manager.floatingPiece?.transform, travel, "the lift lands the travel on the piece")
        XCTAssertGreaterThanOrEqual(published, 1, "as a publish")
        XCTAssertNil(manager.boxNudge, "and the gesture is over")
    }

    /// **A bitmap set down with a finger still on its box lands where the box is** — a tool switch or a
    /// save mid-drag reaches `commitFloatingPieceIfNeeded` before the lift has taught the piece its
    /// travel. Read off the pixels: the ink ends at the box, not where the drag began.
    func testABitmapSetDownMidDragLandsWhereTheBoxIs() throws {
        let manager = try managerWithALiftedBitmap()
        var travel = try XCTUnwrap(manager.floatingPiece?.transform)
        travel.position.x += 12
        manager.moveBoxTouched()
        manager.updateFloatingPose(transform: travel, distortQuad: nil)
        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
        XCTAssertNil(manager.boxNudge, "setting the piece down ends the gesture")

        let landed = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        let opaque = try XCTUnwrap(opaqueColumns(landed, row: 32), "ink landed on the row")
        XCTAssertEqual(opaque.lowerBound, 28, accuracy: 1, "the ink begins where the box was, 12 px on")
        XCTAssertEqual(opaque.upperBound, 59, accuracy: 1)
    }

    /// The first and last opaque column on `row`, or nil for a row with no ink.
    private func opaqueColumns(_ image: UIImage?, row: Int) -> ClosedRange<Int>? {
        guard let cg = image?.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let columns = (0..<width).filter { bytes[(row * width + $0) * 4 + 3] > 128 }
        guard let first = columns.first, let last = columns.last else { return nil }
        return first...last
    }
}
