import IOSurface
import XCTest
import UIKit

/// **What a live picture hands Core Animation** — `WindowSurfaceView`, TODO (97) and (173).
///
/// The property under test is the one the old path lacked and the render server on the owner's
/// iPad died of — twice, once for a stream and once for a recolour: across any number of pictures,
/// the layer's contents cycle between **two** objects
/// this view owns, both `IOSurface`s the render server maps once. A view that minted a surface, or
/// a `CGImage`, per frame would fail the identity count; a view whose contents were not an
/// `IOSurface` would be handing the render server a copy to make. And since TODO (179) the draws go
/// through a `LatestWins`, so a frame asked for during a draw is not lost: the newest one waiting is
/// drawn when the draw in flight lands. Headless — no window, no host — so it runs in the fast tier;
/// the present lands on the main queue, which the test spins.
@MainActor
final class WindowSurfaceViewLogicTests: XCTestCase {

    private let queue = DispatchQueue(label: "WindowSurfaceViewLogicTests.draw")

    /// Presents `count` frames of `color` into `window` and waits for each to land.
    private func present(_ view: WindowSurfaceView, window: CGRect, count: Int,
                         color: (Int) -> UIColor = { _ in .green },
                         file: StaticString = #filePath, line: UInt = #line) {
        for index in 0..<count {
            autoreleasepool {
                let fill = color(index)
                let before = view.presentedCount
                view.present(window: window, placement: .identity) { cg in
                    fill.setFill()
                    cg.fill(CGRect(origin: .zero, size: window.size))
                    return window
                }
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
        let view = WindowSurfaceView(queue: queue)
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
        let view = WindowSurfaceView(queue: queue)
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
        let view = WindowSurfaceView(queue: queue)
        present(view, window: CGRect(x: 0, y: 0, width: 8, height: 4), count: 2)
        let first = try XCTUnwrap(view.layer.contents as AnyObject?)
        present(view, window: CGRect(x: 5, y: 5, width: 8, height: 4), count: 2)
        XCTAssertTrue(view.layer.contents as AnyObject? === first, "a moved window keeps its surfaces")
        XCTAssertEqual(view.layer.position, CGPoint(x: 5, y: 5))
        present(view, window: CGRect(x: 0, y: 0, width: 16, height: 4), count: 2)
        XCTAssertFalse(view.layer.contents as AnyObject? === first, "a resized one does not")
        XCTAssertEqual(view.layer.bounds.width, 16)
    }

    /// **One draw in flight, and the newest frame asked for during it is the one drawn next** — the
    /// stream's last frame of a burst and an edit's last tick, which have no successor to catch them
    /// up. A frame replaced while it waited is never drawn at all.
    func testTheNewestFrameAskedForDuringADrawIsDrawnWhenItLands() throws {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        let gate = DispatchSemaphore(value: 0)
        var drawn: [String] = []
        let lock = NSLock()
        func record(_ name: String) { lock.lock(); drawn.append(name); lock.unlock() }
        view.present(window: window, placement: .identity) { _ in
            gate.wait()
            record("first")
            return window
        }
        view.present(window: window, placement: .identity) { _ in
            record("replaced")
            return window
        }
        view.present(window: window, placement: .identity) { cg in
            record("newest")
            UIColor.red.setFill()
            cg.fill(CGRect(origin: .zero, size: window.size))
            return window
        }
        gate.signal()
        let deadline = Date().addingTimeInterval(2)
        while view.presentedCount < 2, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(view.presentedCount, 2, "the draw in flight and the newest waiting frame both landed")
        lock.lock(); let order = drawn; lock.unlock()
        XCTAssertEqual(order, ["first", "newest"], "the frame replaced while it waited was never drawn")
        let surface = try XCTUnwrap(view.layer.contents as? IOSurface)
        _ = surface.lock(options: [.readOnly], seed: nil)
        defer { _ = surface.unlock(options: [.readOnly], seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(Int(bytes[2]), Int(bytes[1]) + 100, "the newest frame (red) is what is on the layer")
    }

    /// **`finished` says how every draw ended, in the turn it ended** — a caller waiting to punch a
    /// hole under the picture waits for `true`.
    func testFinishedReportsWhetherTheDrawBecameTheContents() {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        var outcomes: [Bool] = []
        func settle(_ count: Int) {
            let deadline = Date().addingTimeInterval(2)
            while outcomes.count < count, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
        }
        view.present(window: window, placement: .identity, draw: { _ in window },
                     finished: { outcomes.append($0) })
        settle(1)
        XCTAssertEqual(outcomes, [true], "a draw of the window it was asked for became the contents")
        view.present(window: window, placement: .identity,
                     draw: { _ in CGRect(x: 1, y: 0, width: 8, height: 4) },
                     finished: { outcomes.append($0) })
        settle(2)
        XCTAssertEqual(outcomes, [true, false], "a draw of another rectangle did not")
        XCTAssertEqual(view.presentedCount, 1)
    }

    /// A draw that answers a different rectangle — the element moved between the window being
    /// read and the draw — is not shown.
    func testADrawOfAnotherRectangleIsNotShown() {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        view.present(window: window, placement: .identity) { _ in
            CGRect(x: 1, y: 0, width: 8, height: 4)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(view.presentedCount, 0)
        XCTAssertTrue(view.isHidden)
    }
}
