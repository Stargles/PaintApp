import IOSurface
import XCTest
import UIKit
import Darwin

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

    /// **A frame that cannot be minted reports refusal and does not wedge the view** — the next valid
    /// request completes successfully and leaves its actual pixels on the layer.
    func testAFrameWithNoSurfaceToDrawIntoLeavesTheViewAbleToDrawTheNext() throws {
        let view = WindowSurfaceView(queue: queue)
        var outcomes: [String] = []
        view.present(window: .zero, placement: .identity, draw: { _ in .zero },
                     finished: { outcomes.append("empty: \($0 ? "shown" : "refused")") })
        XCTAssertEqual(view.presentedCount, 0)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        view.present(window: window, placement: .identity, draw: { cg in
            UIColor.green.setFill()
            cg.fill(CGRect(origin: .zero, size: window.size))
            return window
        }, finished: { outcomes.append("valid: \($0 ? "shown" : "refused")") })
        spin(until: { outcomes.count == 2 }, "the refused and valid frames both complete")
        XCTAssertEqual(view.presentedCount, 1, "the frame after the unmintable one was drawn and shown")
        XCTAssertEqual(outcomes, ["empty: refused", "valid: shown"], "refusal completes before the recovered frame")
        let surface = try XCTUnwrap(view.layer.contents as? IOSurface)
        let lockResult = surface.lock(options: [.readOnly], seed: nil)
        XCTAssertEqual(lockResult, KERN_SUCCESS, "the successfully completed frame is readable")
        guard lockResult == KERN_SUCCESS else { return }
        defer { _ = surface.unlock(options: [.readOnly], seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes, count: 4)), [0, 255, 0, 255],
                       "the valid request's green pixels reached the layer")
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

    /// Freeze while the other buffer is drawing, then reuse the same view. The finished picture
    /// must retain its pixels and identity; neither the cancelled landing nor a later draw owns it.
    func testFrozenPictureSurvivesInFlightAndFutureDraws() throws {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 10, y: 20, width: 8, height: 4)
        present(view, window: window, count: 1)
        let original = try XCTUnwrap(view.layer.contents as? IOSurface)
        let gate = DispatchSemaphore(value: 0)
        var cancelledFinished = false
        var replacedMinted = false
        view.present(window: window, placement: .identity, draw: { cg in
            gate.wait()
            UIColor.red.setFill(); cg.fill(CGRect(origin: .zero, size: window.size))
            return window
        }, finished: { _ in cancelledFinished = true })
        defer { gate.signal() }
        view.present { replacedMinted = true; return nil }
        let frozen = try XCTUnwrap(view.freezePresented())
        XCTAssertTrue(frozen.surface === original, "transfer the exact allocation already on screen")
        XCTAssertNil(view.layer.contents, "the old view no longer displays the transferred picture")
        XCTAssertTrue(view.isHidden)
        XCTAssertNil(view.freezePresented(), "a picture transfers only once")
        gate.signal()
        var drained = false
        queue.async { DispatchQueue.main.async { drained = true } }
        spin(until: { drained }, "the cancelled work has finished")
        present(view, window: window, count: 2, color: { _ in .blue })
        XCTAssertFalse(cancelledFinished, "the draw predating the transfer cannot land")
        XCTAssertFalse(replacedMinted, "the pending request was cancelled too")
        XCTAssertFalse(view.layer.contents as? IOSurface === original,
                       "reusing the view allocates a new writable pair")
        _ = original.lock(options: [.readOnly], seed: nil)
        defer { _ = original.unlock(options: [.readOnly], seed: nil) }
        let bytes = original.baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes, count: 4)), [0, 255, 0, 255],
                       "the retired green picture was neither cleared nor repainted blue")
    }

    /// A resize updates the requested window before it changes the picture actually shown.
    /// A transferred front must carry its own geometry, not that of the unfinished request.
    func testFreezeDuringResizeKeepsThePresentedWindowAndPlacement() throws {
        let view = WindowSurfaceView(queue: queue)
        let old = CGRect(x: 10, y: 20, width: 8, height: 4)
        let placement = CGAffineTransform(a: 2, b: 0.25, c: 0.5, d: 3, tx: 7, ty: 9)
        view.presentFirst(.init(window: old, placement: placement, draw: { _ in old }))
        let gate = DispatchSemaphore(value: 0)
        let resized = CGRect(x: 30, y: 40, width: 16, height: 8)
        view.present(window: resized, placement: .identity) { _ in gate.wait(); return resized }
        defer { gate.signal() }
        let frozen = try XCTUnwrap(view.freezePresented())
        XCTAssertEqual(frozen.window, old)
        XCTAssertEqual(frozen.placement, placement)
        XCTAssertEqual(frozen.surface.width, 8)
        XCTAssertEqual(frozen.surface.height, 4)
        gate.signal()
        present(view, window: resized, count: 1)
    }

    func testFreezingBeforeTheFirstPictureCancelsItsLanding() {
        let view = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        let gate = DispatchSemaphore(value: 0)
        var cancelledFinished = false
        view.present(window: window, placement: .identity, draw: { _ in gate.wait(); return window },
                     finished: { _ in cancelledFinished = true })
        XCTAssertNil(view.freezePresented(), "a pending draw is not a presented picture")
        gate.signal()
        present(view, window: window, count: 1)
        XCTAssertFalse(cancelledFinished)
        XCTAssertEqual(view.presentedCount, 1, "only the post-transfer request lands")
    }

    /// Frozen allocations count until the base covers them, even after their old view is gone.
    /// This is the memory count that the iPad probe reports, not a count of live UIView owners.
    func testFrozenSurfaceStaysAccountedForUntilTheBaseRetiresIt() throws {
        let before = WindowSurfaceView.residentBytes
        try autoreleasepool {
            var view: WindowSurfaceView? = WindowSurfaceView(queue: queue)
            let window = CGRect(x: 0, y: 0, width: 8, height: 4)
            view!.presentFirst(.init(window: window, placement: .identity, draw: { _ in window }))
            var frozen = try XCTUnwrap(view!.freezePresented()) as WindowSurfaceView.FrozenWindow?
            let bytes = frozen!.surface.allocationSize
            let surface = frozen!.surface
            let movedImage = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4),
                                                       format: PixelOps.transparentFormat()).image { _ in }
            let movedGroup = UnlandedInk.Picture.Contents.transformedGroup(
                image: movedImage, canvasSize: CGSize(width: 8, height: 4),
                transform: CATransform3DIdentity, windows: [frozen!]).makeView()
            XCTAssertTrue(movedGroup.subviews.last?.layer.contents as? IOSurface === surface,
                          "the Move group retains the exact On Top surface, not a rerender or copy")
            var ink = UnlandedInk()
            ink.hold(.init(id: 1, version: 7, windowRect: window, alpha: 1,
                           replacesBase: true, contents: .surface(frozen!)))
            frozen = nil
            view = nil
            XCTAssertEqual(WindowSurfaceView.residentBytes - before, bytes)
            let shown = ink.pictures[0].contents.makeView()
            XCTAssertTrue(shown.layer.contents as? IOSurface === surface,
                          "the held lane presents the same storage without a snapshot")
            shown.layer.contents = nil
            ink.retire(upTo: 6)
            XCTAssertEqual(WindowSurfaceView.residentBytes - before, bytes,
                           "an old base cannot release the finished picture")
            ink.retire(upTo: 7)
            XCTAssertEqual(WindowSurfaceView.residentBytes, before)
        }
    }
    func testAnAbandonedViewKeepsOnlyItsInFlightAllocationUntilTheDrawEnds() throws {
        let before = WindowSurfaceView.residentBytes
        var view: WindowSurfaceView? = WindowSurfaceView(queue: queue)
        let window = CGRect(x: 0, y: 0, width: 8, height: 4)
        view!.presentFirst(.init(window: window, placement: .identity, draw: { _ in window }))
        let bytes = try XCTUnwrap(view!.layer.contents as? IOSurface).allocationSize
        let gate = DispatchSemaphore(value: 0)
        view!.present(window: window, placement: .identity) { _ in gate.wait(); return window }
        view = nil
        XCTAssertEqual(WindowSurfaceView.residentBytes - before, bytes,
                       "the worker retains its writable buffer, not the departed view's pair")
        var drained = false
        queue.async { DispatchQueue.main.async { drained = true } }
        gate.signal()
        spin(until: { drained }, "the abandoned draw finished")
        XCTAssertEqual(WindowSurfaceView.residentBytes, before)
    }

    /// The real layer fill owner, extracted without fixing its old size-replacement policy.
    /// The queue gate holds B before its preview runs; this is not an inside-render timing hook.
    func testTheLayerFillOwnerKeepsOneSurfaceThroughQueuedWindowGrowth() throws {
        let before = WindowSurfaceView.residentBytes
        weak var retired: WindowSurfaceView?
        var drained = false
        try autoreleasepool {
            var owner: LayerFillView? = LayerFillView(queue: queue)
            let gate = DispatchSemaphore(value: 0)
            var released = false
            defer {
                _ = owner?.showFill(nil, clip: nil)
                owner = nil
                if !released { gate.signal() }
                queue.async { DispatchQueue.main.async { drained = true } }
            }
            let canvas = CGSize(width: 64, height: 64)
            let a = FillWindow.fitting(CGRect(x: 4, y: 6, width: 8, height: 4),
                                       in: canvas, pixelBudget: 4096)
            let b = FillWindow.fitting(CGRect(x: 8, y: 10, width: 16, height: 8),
                                       in: canvas, pixelBudget: 4096)
            let c = FillWindow.fitting(CGRect(x: 12, y: 18, width: 32, height: 16),
                                       in: canvas, pixelBudget: 288)
            let green: [UInt8] = [0, 255, 0, 255], red: [UInt8] = [255, 0, 0, 255]
            let blue: [UInt8] = [0, 0, 255, 255]
            let first = CanvasManager.FillRenderResult(generation: 1,
                bytes: Array(repeating: green, count: a.workingWidth * a.workingHeight).flatMap { $0 }, window: a)
            let active = CanvasManager.FillRenderResult(generation: 2,
                bytes: Array(repeating: red, count: b.workingWidth * b.workingHeight).flatMap { $0 }, window: b)
            let newest = CanvasManager.FillRenderResult(generation: 3,
                bytes: Array(repeating: blue, count: c.workingWidth * c.workingHeight).flatMap { $0 }, window: c)
            XCTAssertTrue(owner!.showFill(first, clip: nil))
            let surface = try XCTUnwrap(owner!.subviews.compactMap { $0 as? WindowSurfaceView }.first)
            retired = surface
            spin(until: { surface.presentedCount == 1 }, "PREMISE: A actually presents before growth")
            XCTAssertFalse(surface.isHidden, "PREMISE: A is an exposed layer picture")
            let front = try XCTUnwrap(surface.layer.contents as? IOSurface)
            _ = front.lock(options: [.readOnly], seed: nil)
            let initial = front.baseAddress.assumingMemoryBound(to: UInt8.self)
            XCTAssertEqual(Array(UnsafeBufferPointer(start: initial, count: 4)), [0, 255, 0, 255],
                           "PREMISE: A's real preview writes green BGRA pixels")
            _ = front.unlock(options: [.readOnly], seed: nil)
            XCTAssertEqual(surface.layer.bounds.size, CGSize(width: 8, height: 4))
            XCTAssertEqual(surface.layer.position, CGPoint(x: 4, y: 6))
            XCTAssertFalse(owner!.showFill(first, clip: nil), "An identical render and clip request is unchanged")

            queue.async { gate.wait() }
            XCTAssertTrue(owner!.showFill(active, clip: nil))
            let afterB = WindowSurfaceView.residentBytes
            XCTAssertTrue(owner!.showFill(newest, clip: nil))
            XCTAssertFalse(surface.isHidden, "The old front remains exposed while B is held")
            XCTAssertTrue(surface.layer.contents as AnyObject? === front, "Growth keeps the old front until landing")
            XCTAssertEqual(surface.layer.bounds.size, CGSize(width: 8, height: 4), "The old front keeps its extent")
            XCTAssertEqual(surface.layer.position, CGPoint(x: 4, y: 6), "The old front keeps its placement")
            let children = owner!.subviews.compactMap { $0 as? WindowSurfaceView }
            XCTAssertEqual(children.count, 1, "Different working sizes share one layer fill surface owner")
            XCTAssertTrue(children.last === surface, "The newest request keeps the original surface view identity")
            XCTAssertEqual(WindowSurfaceView.residentBytes, afterB,
                           "C remains unminted while B is active, rather than allocating another pair")
            // Later output/lifetime assertions are deliberately uncredited if OLD replacement failed.
            guard children.count == 1, children.first === surface else { return }
            XCTAssertEqual(surface.surfaceWindow.size, CGSize(width: 16, height: 8), "Only B has been minted")
            gate.signal()
            released = true
            spin(until: { surface.presentedCount == 3 }, "A, active B and newest C land on the same owner")
            XCTAssertEqual(owner!.subviews.count, 1)
            XCTAssertEqual(surface.layer.bounds.size, CGSize(width: 24, height: 12))
            XCTAssertEqual(surface.layer.position, CGPoint(x: 12, y: 18))
            XCTAssertEqual(surface.layer.affineTransform(),
                           CGAffineTransform(scaleX: CGFloat(4) / 3, y: CGFloat(4) / 3))
            let landed = try XCTUnwrap(surface.layer.contents as? IOSurface)
            _ = landed.lock(options: [.readOnly], seed: nil)
            let final = landed.baseAddress.assumingMemoryBound(to: UInt8.self)
            XCTAssertEqual(Array(UnsafeBufferPointer(start: final, count: 4)), [255, 0, 0, 255],
                           "The newest C preview, not active B or plain paper, is the actual surface")
            _ = landed.unlock(options: [.readOnly], seed: nil)
            XCTAssertTrue(owner!.showFill(nil, clip: nil))
            XCTAssertTrue(owner!.subviews.isEmpty, "Ending the fill removes its picture")
        }
        spin(until: { drained && retired == nil && WindowSurfaceView.residentBytes == before },
             "Clearing the owner and draining its own queue retires all actual surface allocations")
    }

    /// A refused surface allocation leaves this render and clip eligible for another admission.
    /// The factory returns the real IOSurface on the next request; it changes no drawing behavior.
    func testLayerFillRetriesTheSameRenderAfterOneSurfaceAllocationRefusal() throws {
        let before = WindowSurfaceView.residentBytes
        let gate = DispatchSemaphore(value: 0)
        var released = false
        var refusalsRemaining = 1
        let factory: WindowSurfaceView.SurfaceFactory = { width, height in
            if refusalsRemaining > 0 {
                refusalsRemaining -= 1
                return nil
            }
            return WindowSurfaceView.makeSurface(width: width, height: height)
        }
        queue.async { gate.wait() }
        var owner: LayerFillView? = LayerFillView(queue: queue, surfaceFactory: factory)
        defer {
            _ = owner?.showFill(nil, clip: nil)
            owner = nil
            if !released { gate.signal() }
        }

        let canvas = CGSize(width: 64, height: 64)
        let window = FillWindow.fitting(CGRect(x: 4, y: 6, width: 8, height: 4),
                                       in: canvas, pixelBudget: 4096)
        let green: [UInt8] = [0, 255, 0, 255]
        let render = CanvasManager.FillRenderResult(generation: 1,
            bytes: Array(repeating: green, count: window.workingWidth * window.workingHeight).flatMap { $0 },
            window: window)

        XCTAssertTrue(owner!.showFill(render, clip: nil), "the initial fill request changes the owner")
        let surface = try XCTUnwrap(owner!.subviews.compactMap { $0 as? WindowSurfaceView }.first)
        XCTAssertEqual(refusalsRemaining, 0, "PREMISE: the first surface allocation was refused")
        XCTAssertEqual(surface.presentedCount, 0, "PREMISE: refusal produced no picture")
        XCTAssertEqual(WindowSurfaceView.residentBytes, before,
                       "PREMISE: refusal allocated no retained surface memory")

        let retryAccepted = owner!.showFill(render, clip: nil)
        XCTAssertTrue(retryAccepted, "the same render and clip are admitted after allocation recovers")
        guard retryAccepted else { return }
        XCTAssertFalse(owner!.showFill(render, clip: nil), "the admitted retry is deduped while pending")
        XCTAssertEqual(surface.presentedCount, 0, "PREMISE: the gate keeps the admitted request pending")
        gate.signal()
        released = true
        spin(until: { surface.presentedCount == 1 }, "the admitted retry reaches the surface")
        let pixels = try XCTUnwrap(surface.layer.contents as? IOSurface)
        let lockResult = pixels.lock(options: [.readOnly], seed: nil)
        XCTAssertEqual(lockResult, KERN_SUCCESS, "the recovered surface can be read")
        guard lockResult == KERN_SUCCESS else { return }
        defer { _ = pixels.unlock(options: [.readOnly], seed: nil) }
        let bytes = pixels.baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes, count: 4)), green,
                       "the recovered allocation presents the actual green fill pixels")
        XCTAssertEqual(surface.layer.bounds.size, CGSize(width: 8, height: 4))
        XCTAssertEqual(surface.layer.position, CGPoint(x: 4, y: 6))
    }

    /// A second-surface refusal leaves one real allocation owned until Set Down removes the child.
    func testLayerFillSetDownReleasesASurfaceAfterSecondAllocationRefusal() throws {
        let before = WindowSurfaceView.residentBytes
        let gate = DispatchSemaphore(value: 0)
        var allocations = 0
        weak var retired: WindowSurfaceView?
        let factory: WindowSurfaceView.SurfaceFactory = { width, height in
            allocations += 1
            guard allocations != 2 else { return nil }
            return WindowSurfaceView.makeSurface(width: width, height: height)
        }
        queue.async { gate.wait() }
        defer { gate.signal() }

        let owner = LayerFillView(queue: queue, surfaceFactory: factory)
        autoreleasepool {
            let canvas = CGSize(width: 64, height: 64)
            let window = FillWindow.fitting(CGRect(x: 4, y: 6, width: 8, height: 4),
                                           in: canvas, pixelBudget: 4096)
            let green: [UInt8] = [0, 255, 0, 255]
            let render = CanvasManager.FillRenderResult(generation: 1,
                bytes: Array(repeating: green, count: window.workingWidth * window.workingHeight).flatMap { $0 },
                window: window)

            XCTAssertTrue(owner.showFill(render, clip: nil))
            retired = owner.subviews.compactMap { $0 as? WindowSurfaceView }.first
            XCTAssertNotNil(retired, "PREMISE: the refused fill still has its owner child before Set Down")
            XCTAssertEqual(allocations, 2, "PREMISE: one real allocation was followed by one refusal")
            XCTAssertGreaterThan(WindowSurfaceView.residentBytes, before,
                                 "PREMISE: the first IOSurface remains resident after the second refusal")

            XCTAssertTrue(owner.showFill(nil, clip: nil), "Set Down clears the live fill")
            XCTAssertTrue(owner.subviews.isEmpty, "Set Down removes the surface child")
        }
        withExtendedLifetime(owner) {
            XCTAssertNil(retired, "Set Down releases its child while the LayerFillView owner remains alive")
            spin(until: { retired == nil && WindowSurfaceView.residentBytes == before },
                 "the partial surface is released with its owner still alive")
        }
    }

    /// A stale A refusal cannot unset the identity of a newer pending A after reentrant B → A.
    func testLayerFillRefusalDoesNotClearSupersedingSameRenderDuringReentrantMint() throws {
        let gate = DispatchSemaphore(value: 0)
        var released = false
        let canvas = CGSize(width: 64, height: 64)
        let window = FillWindow.fitting(CGRect(x: 4, y: 6, width: 8, height: 4),
                                       in: canvas, pixelBudget: 4096)
        let green: [UInt8] = [0, 255, 0, 255]
        let red: [UInt8] = [255, 0, 0, 255]
        let renderA = CanvasManager.FillRenderResult(generation: 1,
            bytes: Array(repeating: green, count: window.workingWidth * window.workingHeight).flatMap { $0 },
            window: window)
        let renderB = CanvasManager.FillRenderResult(generation: 2,
            bytes: Array(repeating: red, count: window.workingWidth * window.workingHeight).flatMap { $0 },
            window: window)
        weak var ownerReference: LayerFillView? = nil
        var reentrantAdmissions: [Bool] = []
        var allocations = 0
        let factory: WindowSurfaceView.SurfaceFactory = { width, height in
            allocations += 1
            if allocations == 1 {
                guard let owner = ownerReference else { return nil }
                reentrantAdmissions.append(owner.showFill(renderB, clip: nil))
                reentrantAdmissions.append(owner.showFill(renderA, clip: nil))
                return nil
            }
            return WindowSurfaceView.makeSurface(width: width, height: height)
        }
        queue.async { gate.wait() }
        var owner: LayerFillView? = LayerFillView(queue: queue, surfaceFactory: factory)
        ownerReference = owner
        defer {
            _ = owner?.showFill(nil, clip: nil)
            owner = nil
            if !released { gate.signal() }
        }

        XCTAssertTrue(owner!.showFill(renderA, clip: nil), "the original A request is admitted")
        XCTAssertEqual(reentrantAdmissions, [true, true], "the allocator re-entered with B, then the same A")
        XCTAssertEqual(allocations, 3, "PREMISE: A refused once, then its superseding mint made two real surfaces")
        let surface = try XCTUnwrap(owner!.subviews.compactMap { $0 as? WindowSurfaceView }.first)
        XCTAssertEqual(surface.presentedCount, 0, "PREMISE: the render queue gate holds the newest A")
        XCTAssertFalse(owner!.showFill(renderA, clip: nil),
                       "the stale refusal must not clear the identity of the newer pending A")
        XCTAssertEqual(surface.presentedCount, 0, "PREMISE: no request lands before releasing the queue")

        gate.signal()
        released = true
        spin(until: { surface.presentedCount == 1 }, "only the latest A picture lands")
        let pixels = try XCTUnwrap(surface.layer.contents as? IOSurface)
        let lockResult = pixels.lock(options: [.readOnly], seed: nil)
        XCTAssertEqual(lockResult, KERN_SUCCESS, "the landed A surface is readable")
        guard lockResult == KERN_SUCCESS else { return }
        defer { _ = pixels.unlock(options: [.readOnly], seed: nil) }
        let bytes = pixels.baseAddress.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes, count: 4)), green,
                       "B was superseded; the visible pixels are the re-requested A")
        XCTAssertEqual(surface.layer.bounds.size, CGSize(width: 8, height: 4))
        XCTAssertEqual(surface.layer.position, CGPoint(x: 4, y: 6))
    }

}
