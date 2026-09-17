import XCTest
import SwiftUI
import UIKit

/// **What one fill gesture adds to the process, at three canvas sizes — TODO (86)'s measurement.**
///
/// The claim `FillWindow` makes is that a fill's memory follows the region and not the canvas. This
/// takes `phys_footprint` before a gesture and at its peak — the preview installed, the session and
/// its window still alive — on a 2048², a 6000² and an 8192² document, and prints the three deltas.
/// If the claim holds they are the same number; before (86) they were 58 bytes a canvas pixel, so
/// 243 MB, 2.1 GB and 3.9 GB.
///
/// **The delta is a footprint proxy** (CLAUDE.md): it includes whatever else the process allocated
/// in the window, and it is taken with the layer's own display render already resident — the
/// canvas-sized memo the layer host holds while the artist is looking at the layer, which the fill
/// reads through the window rather than re-rendering. That memo is the canvas's cost and is charged
/// to the display, not to the gesture; a measurement that took it here would be measuring
/// `VectorCanvas.render` at three sizes.
///
/// The measurement prints unconditionally. The assertion that the three are flat is opt-in — set
/// `PAINTAPP_FILL_FOOTPRINT=1` — because a footprint sampled on a loaded machine is a sample of the
/// machine (CLAUDE.md's bench rule); a re-take reads the printed numbers.
///
/// Not `…LogicTests`, so the fast tier does not build three canvases up to 8192² on every run.
final class FillFootprintBench: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    override func tearDown() {
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    private func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    private func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "FILL FOOTPRINT | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "FILL FOOTPRINT — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// A vector document at `side`², one layer, one 200-pixel box of ink at the centre, its display
    /// render already made.
    private func document(side: Int) -> (CanvasManager, VectorCanvas, CGRect) {
        let size = CGSize(width: side, height: side)
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = size
        manager.addLayer()
        manager.layers[0].kind = .vector
        manager.brushColor = Self.red
        let brush = Brush(name: "Test", tip: .round, size: 12, opacity: 1,
                          dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1, angle: BrushAngleSettings(jitter: 0)),
                          stroke: BrushStrokeSettings(stabilization: 0, blendMode: .normal))
        let box = CGRect(x: side / 2 - 100, y: side / 2 - 100, width: 200, height: 200)
        let outline = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                   size: 12, opacity: 1,
                                   samples: [VectorSample(x: Double(box.minX), y: Double(box.minY), pressure: 1),
                                             VectorSample(x: Double(box.maxX), y: Double(box.minY), pressure: 1),
                                             VectorSample(x: Double(box.maxX), y: Double(box.maxY), pressure: 1),
                                             VectorSample(x: Double(box.minX), y: Double(box.maxY), pressure: 1),
                                             VectorSample(x: Double(box.minX), y: Double(box.minY), pressure: 1)])
        let canvas = VectorCanvas(size: size, strokes: [outline])
        manager.layers[0].cels[0].vector = canvas
        _ = canvas.render()   // the display's own memo, resident as it is while the layer is on screen
        return (manager, canvas, box)
    }

    /// One lasso around the box and one tap inside it, each measured from a resident display to its
    /// preview — the two shapes of the tool, on the same document.
    private func measure(side: Int) throws -> (lasso: Int, bucket: Int, lassoWindow: CGRect, bucketWindow: CGRect) {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        var lassoDelta = 0, bucketDelta = 0
        var lassoWindow = CGRect.null, bucketWindow = CGRect.null
        try autoreleasepool {
            let (manager, canvas, box) = document(side: side)
            let centre = CGPoint(x: box.midX, y: box.midY)

            let beforeLasso = residentBytes()
            let loop = CGMutablePath()
            loop.addRect(box.insetBy(dx: -40, dy: -40))
            manager.beginInteractiveLassoFill(path: loop)
            manager.endInteractiveFill()
            manager.fillQueue.sync {}
            settle()
            let render = try XCTUnwrap(manager.fillLastRender, "the lasso previewed nothing at \(side)²")
            XCTAssertTrue(manager.isPointInPendingFill(at: centre), "the box is filled at \(side)²")
            lassoDelta = Int(residentBytes()) - Int(beforeLasso)
            lassoWindow = render.window.rect
            manager.commitInteractiveFill()
            XCTAssertNotNil(canvas.elements.last?.fill, "the lasso committed a vector fill at \(side)²")
            // The commit changed the layer, so the display re-renders it — the canvas's cost again,
            // and the display's, taken before the next gesture is measured.
            _ = canvas.render()

            let beforeBucket = residentBytes()
            manager.beginInteractiveFill(at: centre)
            manager.endInteractiveFill()
            manager.fillQueue.sync {}
            settle()
            let tap = try XCTUnwrap(manager.fillLastRender, "the tap previewed nothing at \(side)²")
            XCTAssertTrue(manager.isPointInPendingFill(at: centre))
            bucketDelta = Int(residentBytes()) - Int(beforeBucket)
            bucketWindow = tap.window.rect
            manager.commitInteractiveFill()
            withExtendedLifetime(canvas) {}
        }
        report("\(side)x\(side)", [
            ("lassoDelta", mb(lassoDelta)), ("lassoWindow", "\(Int(lassoWindow.width))x\(Int(lassoWindow.height))"),
            ("bucketDelta", mb(bucketDelta)), ("bucketWindow", "\(Int(bucketWindow.width))x\(Int(bucketWindow.height))"),
            ("canvasBytes", mb(side * side * 4))
        ])
        return (lassoDelta, bucketDelta, lassoWindow, bucketWindow)
    }

    func testOneFillsFootprintIsFlatAcrossCanvasSizes() throws {
        let sides = [2048, 6000, 8192]
        let deltas = try sides.map { try measure(side: $0) }

        // The windows are the fixture's shape, not the canvas's: the lasso's is the loop plus the
        // halo (280 + 2·88 = 456), the bucket's is its first window, and neither moves with `side`.
        for (side, delta) in zip(sides, deltas) {
            XCTAssertEqual(delta.lassoWindow.size, CGSize(width: 456, height: 456), "the lasso's window at \(side)²")
            XCTAssertEqual(delta.bucketWindow.size, CGSize(width: 1024, height: 1024), "the tap's window at \(side)²")
        }

        guard ProcessInfo.processInfo.environment["PAINTAPP_FILL_FOOTPRINT"] != nil else {
            print("FILL FOOTPRINT | flatness not asserted; set PAINTAPP_FILL_FOOTPRINT=1 to gate on it")
            return
        }
        // Flat within the noise of a footprint proxy and CoreGraphics' row-strip copy
        // (`CanvasManager.compositeReferenceRGBA`): the largest may not exceed the smallest by more
        // than 32 MB, where the canvas alone grows by 240 MB from the first size to the last and the
        // gesture's old cost by 3.7 GB.
        let slack = 32 * 1_048_576
        let lasso = deltas.map(\.lasso), bucket = deltas.map(\.bucket)
        XCTAssertLessThan(lasso.max()! - lasso.min()!, slack, "a lasso fill's footprint moved with the canvas: \(lasso)")
        XCTAssertLessThan(bucket.max()! - bucket.min()!, slack, "a bucket fill's footprint moved with the canvas: \(bucket)")
    }
}
