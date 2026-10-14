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

    /// A new size makes new surfaces; the same size keeps them.
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

    func testAResizedWindowKeepsTheOldFrontUntilTheNewPictureLands() throws {
        let view = WindowSurfaceView(queue: queue)
        present(view, window: CGRect(x: 0, y: 0, width: 8, height: 4), count: 1)
        let old = try XCTUnwrap(view.layer.contents as AnyObject?)
        let gate = DispatchSemaphore(value: 0)
        let new = CGRect(x: 0, y: 0, width: 16, height: 8)
        view.present(window: new, placement: .identity) { cg in
            gate.wait()
            UIColor.red.setFill(); cg.fill(new)
            return new
        }
        XCTAssertFalse(view.isHidden, "a resize never exposes the old plain hosts")
        XCTAssertTrue(view.layer.contents as AnyObject? === old)
        XCTAssertEqual(view.layer.bounds.size, CGSize(width: 8, height: 4), "old pixels retain their placement")
        gate.signal()
        let until = Date().addingTimeInterval(2)
        while view.presentedCount < 2, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        XCTAssertEqual(view.presentedCount, 2)
        XCTAssertEqual(view.layer.bounds.size, new.size)
        XCTAssertFalse(view.layer.contents as AnyObject? === old)
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

    /// **A surface the render server still holds is not drawn into** — `WindowSurfaceView.present`'s
    /// wait, the cure for the owner's flicker of 2026-10-12 (*"Lots of flickering"* recolouring a
    /// filled selection). The draw for a frame is minted in the turn the last one landed, and the swap
    /// that put the last one up reaches the render server only when that turn's transaction commits —
    /// so the surface the new draw clears and fills is still the one on screen, and one frame of
    /// whatever lies under the view shows through it. `IOSurface.isInUse` is what says the server has
    /// let go. **This is the level at which the hazard is deterministic**: the simulator's render
    /// server does not show a retired surface of a window's size, so no screen read can see it there
    /// (`SelectionFillRecolourUITests` says what it can and cannot).
    ///
    /// Operands: the surface a frame will be drawn into — the one that was on the layer two frames
    /// ago, which the test takes a use count on, as the server's mapping does — read for its own
    /// pixels while the frame waits, and for whether the frame's draw has run. Frame three is drawn
    /// into frame one's surface (the view alternates two).
    func testASurfaceTheRenderServerStillHoldsIsNotDrawnIntoUntilItLetsGo() throws {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        present(view, window: window, count: 1)
        let held = try XCTUnwrap(view.layer.contents as? IOSurface, "frame one's surface is on the layer")
        held.incrementUseCount()
        var released = false
        defer { if !released { held.decrementUseCount() } }
        present(view, window: window, count: 1)

        let lock = NSLock()
        var drawStarted = false
        view.present(window: window, placement: .identity) { cg in
            lock.lock(); drawStarted = true; lock.unlock()
            UIColor.red.setFill()
            cg.fill(CGRect(origin: .zero, size: window.size))
            return window
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        lock.lock(); let startedWhileHeld = drawStarted; lock.unlock()
        XCTAssertFalse(startedWhileHeld, "frame three's draw ran into a surface the render server still held")
        XCTAssertEqual(view.presentedCount, 2, "and it did not land")
        XCTAssertEqual(alpha(of: held), 255, "the held surface still has frame one's picture: it was not cleared")

        held.decrementUseCount()
        released = true
        let deadline = Date().addingTimeInterval(2)
        while view.presentedCount < 3, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(view.presentedCount, 3, "once the server let go, the frame was drawn and landed")
        lock.lock(); let started = drawStarted; lock.unlock()
        XCTAssertTrue(started)
        XCTAssertTrue(view.layer.contents as AnyObject? === (held as AnyObject), "into the surface that was held")
    }

    /// **A server that never lets go costs one wait, not the picture** — the wait is bounded (half a
    /// second, past the longest busy turn the owner's iPad 9 recorded), so a surface that stays in use
    /// forever is drawn into after it rather than never.
    func testASurfaceTheServerNeverLetsGoOfIsDrawnIntoAfterTheBound() throws {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        present(view, window: window, count: 1)
        let held = try XCTUnwrap(view.layer.contents as? IOSurface)
        held.incrementUseCount()
        defer { held.decrementUseCount() }
        present(view, window: window, count: 1)
        view.present(window: window, placement: .identity) { _ in window }
        let deadline = Date().addingTimeInterval(4)
        while view.presentedCount < 3, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(view.presentedCount, 3, "the frame landed although the surface was never let go")
    }

    /// One pixel's alpha of a surface the test drew a full-window green fill into — 255 while it holds
    /// that picture, 0 once it has been cleared for another.
    private func alpha(of surface: IOSurface) -> UInt8 {
        _ = surface.lock(options: [.readOnly], seed: nil)
        defer { _ = surface.unlock(options: [.readOnly], seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        return bytes[2 * surface.bytesPerRow + 3 * 4 + 3]
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

    // MARK: - A picture asked for is never stranded

    /// Spins the main queue until `done`, failing by name if it is not reached.
    private func spin(until done: () -> Bool, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertTrue(done(), what, file: file, line: line)
    }

    /// **A frame dropped at its landing still lets the one behind it draw** — a draw that answers
    /// another rectangle (the element moved between the two reads) is not shown, and its landing must
    /// hand the worker on like any other: the newest frame, asked for while it drew, is the picture
    /// left up.
    func testAFrameDroppedAtItsLandingStillStartsTheNewestOneWaitingBehindIt() throws {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        let gate = DispatchSemaphore(value: 0)
        var outcomes: [String] = []
        view.present(window: window, placement: .identity, draw: { _ in
            gate.wait()
            return CGRect(x: 1, y: 0, width: 8, height: 4)
        }, finished: { outcomes.append("dropped: \($0 ? "shown" : "not shown")") })
        view.present(window: window, placement: .identity, draw: { cg in
            UIColor.red.setFill()
            cg.fill(CGRect(origin: .zero, size: window.size))
            return window
        }, finished: { outcomes.append("newest: \($0 ? "shown" : "not shown")") })
        gate.signal()
        spin(until: { outcomes.count == 2 }, "both frames reported how they ended")
        XCTAssertEqual(outcomes, ["dropped: not shown", "newest: shown"])
        XCTAssertEqual(view.presentedCount, 1)
        let surface = try XCTUnwrap(view.layer.contents as? IOSurface)
        _ = surface.lock(options: [.readOnly], seed: nil)
        defer { _ = surface.unlock(options: [.readOnly], seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(Int(bytes[2]), Int(bytes[1]) + 100, "the newest frame (red) is what is on the layer")
    }

    /// **A frame that cannot be minted does not wedge the view** — a window with no area has no surface
    /// to draw into, the mint answers nothing, and the next frame asked for is drawn as usual.
    func testAFrameWithNoSurfaceToDrawIntoLeavesTheViewAbleToDrawTheNext() {
        let view = WindowSurfaceView(queue: queue)
        var outcomes: [Bool] = []
        view.present(window: .zero, placement: .identity, draw: { _ in .zero }, finished: { outcomes.append($0) })
        XCTAssertEqual(view.presentedCount, 0)
        present(view, window: CGRect(x: 0, y: 0, width: 8, height: 4), count: 1)
        XCTAssertEqual(view.presentedCount, 1, "the frame after the unmintable one was drawn and shown")
        XCTAssertEqual(outcomes, [], "a frame never minted never reports")
    }

    /// **A frame asked for from inside `finished` is drawn after the landing returns, not inside it** —
    /// the held edit's `finished` re-shows overlays, and a caller may ask for a picture there.
    func testAFrameAskedForInsideFinishedIsDrawnAfterTheLandingReturns() {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        let lock = NSLock()
        var events: [String] = []
        func record(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
        view.present(window: window, placement: .identity, draw: { _ in record("draw first"); return window },
                     finished: { _ in
            record("first finished")
            view.present(window: window, placement: .identity, draw: { _ in record("draw second"); return window },
                         finished: { _ in record("second finished") })
            record("first finished returns")
        })
        spin(until: { view.presentedCount == 2 }, "the frame asked for inside finished was shown")
        lock.lock(); let order = events; lock.unlock()
        XCTAssertEqual(order, ["draw first", "first finished", "first finished returns", "draw second", "second finished"],
                       "the second frame was drawn after the first's landing returned")
    }

    /// **Frames asked for while a draw waits for the render server replace each other, and the newest
    /// is drawn** — the wait for `IOSurface.isInUse` is part of the draw in flight, so it is a state the
    /// scheduler's single waiting slot has to cover: the draw that waits is not abandoned, the ones
    /// asked for during the wait are not queued behind it one each, and none of them is lost.
    func testFramesAskedForWhileADrawWaitsForTheServerCollapseToTheNewest() throws {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        present(view, window: window, count: 1)
        let held = try XCTUnwrap(view.layer.contents as? IOSurface, "frame one's surface is on the layer")
        held.incrementUseCount()
        var released = false
        defer { if !released { held.decrementUseCount() } }
        present(view, window: window, count: 1)

        let lock = NSLock()
        var drawn: [String] = []
        func draw(_ name: String) -> (CGContext) -> CGRect? {
            { _ in
                lock.lock(); drawn.append(name); lock.unlock()
                return window
            }
        }
        view.present(window: window, placement: .identity, draw: draw("first asked"))
        view.present(window: window, placement: .identity, draw: draw("replaced"))
        view.present(window: window, placement: .identity, draw: draw("newest"))
        held.decrementUseCount()
        released = true
        spin(until: { view.presentedCount == 4 }, "the draw that waited and the newest frame asked for during its wait were both shown")
        lock.lock(); let order = drawn; lock.unlock()
        XCTAssertEqual(order, ["first asked", "newest"], "the replaced frame was never drawn")
    }
}
