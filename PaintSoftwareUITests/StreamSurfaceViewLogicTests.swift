import IOSurface
import XCTest
import UIKit

/// **What a live stream frame hands Core Animation** — `StreamSurfaceView`, TODO (97).
///
/// The property under test is the one the old path lacked and the render server on the owner's
/// iPad died of: across any number of frames, the layer's contents cycle between **two** objects
/// this view owns, both `IOSurface`s the render server maps once. A view that minted a surface, or
/// a `CGImage`, per frame would fail the identity count; a view whose contents were not an
/// `IOSurface` would be handing the render server a copy to make. Headless — no window, no host —
/// so it runs in the fast tier; the present lands on the main queue, which the test spins.
@MainActor
final class StreamSurfaceViewLogicTests: XCTestCase {

    private let queue = DispatchQueue(label: "StreamSurfaceViewLogicTests.draw")

    /// Presents `count` frames of `color` into `window` and waits for each to land.
    private func present(_ view: StreamSurfaceView, window: CGRect, count: Int,
                         color: (Int) -> UIColor = { _ in .green },
                         file: StaticString = #filePath, line: UInt = #line) {
        for index in 0..<count {
            autoreleasepool {
                let fill = color(index)
                let before = view.presentedCount
                XCTAssertTrue(view.present(window: window, placement: .identity, on: queue) { cg in
                    fill.setFill()
                    cg.fill(CGRect(origin: .zero, size: window.size))
                    return window
                }, "frame \(index) was accepted", file: file, line: line)
                let deadline = Date().addingTimeInterval(2)
                while view.presentedCount == before, Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                }
                XCTAssertEqual(view.presentedCount, before + 1, "frame \(index) landed", file: file, line: line)
            }
        }
    }

    /// **A hundred frames are two surfaces.** Counted by identity after every present, each in its
    /// own pool so the count is of what a frame leaves on the layer and not of what the loop has
    /// not released — CLAUDE.md's growth-measurement rule.
    func testAHundredFramesCycleBetweenTwoSurfaces() {
        let view = StreamSurfaceView()
        let window = CGRect(x: 10, y: 20, width: 32, height: 16)
        var contents = Set<ObjectIdentifier>()
        for _ in 0..<100 {
            present(view, window: window, count: 1)
            let object = try? XCTUnwrap(view.layer.contents as AnyObject?, "the layer has contents")
            if let object { contents.insert(ObjectIdentifier(object)) }
        }
        XCTAssertEqual(contents.count, 2, "two objects, alternated, for the life of the window")
        XCTAssertTrue(view.layer.contents is IOSurface, "and they are surfaces the render server maps once")
    }

    /// **The pixels drawn are the pixels on the surface**: a green fill through the UIKit context
    /// the view hands the draw reads back green and opaque from the surface's own memory — which
    /// is the flip, the format and the push all being right at once.
    func testTheDrawLandsOnTheSurfaceOpaque() throws {
        let view = StreamSurfaceView()
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        present(view, window: window, count: 1)
        let surface = try XCTUnwrap(view.layer.contents as? IOSurface)
        _ = surface.lock(options: [.readOnly], seed: nil)
        defer { _ = surface.unlock(options: [.readOnly], seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let i = 2 * surface.bytesPerRow + 3 * 4   // row 2, column 3, BGRA
        XCTAssertEqual(bytes[i + 3], 255, "alpha")
        XCTAssertGreaterThan(Int(bytes[i + 1]), Int(bytes[i + 2]) + 100, "green over red")
        XCTAssertEqual(view.layer.bounds.size, window.size)
        XCTAssertEqual(view.layer.position, window.origin, "placed at the window's own origin")
        XCTAssertFalse(view.isHidden)
    }

    /// A window of a new size makes new surfaces and hides the view until one lands; the same size
    /// keeps them.
    func testANewWindowSizeRemakesTheSurfacesAndTheSameSizeKeepsThem() throws {
        let view = StreamSurfaceView()
        present(view, window: CGRect(x: 0, y: 0, width: 8, height: 4), count: 2)
        let first = try XCTUnwrap(view.layer.contents as AnyObject?)
        present(view, window: CGRect(x: 5, y: 5, width: 8, height: 4), count: 2)
        XCTAssertTrue(view.layer.contents as AnyObject? === first, "a moved window keeps its surfaces")
        XCTAssertEqual(view.layer.position, CGPoint(x: 5, y: 5))
        present(view, window: CGRect(x: 0, y: 0, width: 16, height: 4), count: 2)
        XCTAssertFalse(view.layer.contents as AnyObject? === first, "a resized one does not")
        XCTAssertEqual(view.layer.bounds.width, 16)
    }

    /// One draw in flight: a frame that arrives during it is dropped, and reported as dropped.
    func testAFrameDuringADrawIsDropped() {
        let view = StreamSurfaceView()
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        let gate = DispatchSemaphore(value: 0)
        XCTAssertTrue(view.present(window: window, placement: .identity, on: queue) { _ in
            gate.wait()
            return window
        })
        XCTAssertFalse(view.present(window: window, placement: .identity, on: queue) { _ in window },
                       "a second frame while the first is drawing is dropped")
        gate.signal()
        let deadline = Date().addingTimeInterval(2)
        while view.presentedCount == 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(view.presentedCount, 1)
        XCTAssertTrue(view.present(window: window, placement: .identity, on: queue) { _ in window },
                      "and the next one after it lands is accepted")
    }

    /// A draw that answers a different rectangle — the element moved between the window being
    /// read and the draw — is not shown.
    func testADrawOfAnotherRectangleIsNotShown() {
        let view = StreamSurfaceView()
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        XCTAssertTrue(view.present(window: window, placement: .identity, on: queue) { _ in
            CGRect(x: 1, y: 0, width: 8, height: 4)
        })
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(view.presentedCount, 0)
        XCTAssertTrue(view.isHidden)
    }
}
