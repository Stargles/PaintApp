import XCTest

/// **The screen never mixes pictures** (SCHEDULER.md rule 10): parts drawn in any order, at any time,
/// through any burst of steps, go up together or not at all — `CanvasPresenter`.
@MainActor
final class CanvasPresenterLogicTests: XCTestCase {

    /// One layer's picture: what it is asked to show (`wanted`), what is up (`shown`).
    private final class Part {
        var wanted = 0
        var shown = 0
        var drawing: Int?
    }

    private func land(_ part: Part, _ presenter: CanvasPresenter) {
        guard let drawn = part.drawing else { return }
        part.drawing = nil
        presenter.park(part, isCurrent: { part.wanted == drawn }, swap: { part.shown = drawn }, drop: {})
    }

    func testParkedPicturesGoUpTogetherWithWhatIsDoneAlongside() {
        let presenter = CanvasPresenter()
        let parts = [Part(), Part(), Part()]
        presenter.hold()
        var wholeTakenDown = false
        for part in parts { part.wanted = 1 }
        for (index, part) in parts.enumerated() {
            part.drawing = 1
            land(part, presenter)
            if index < 2 {
                XCTAssertFalse(presenter.isComplete(parts, showing: { $0.shown == $0.wanted }))
                XCTAssertTrue(parts.allSatisfy { $0.shown == 0 }, "nothing goes up while the set is incomplete")
            }
        }
        XCTAssertTrue(presenter.isComplete(parts, showing: { $0.shown == $0.wanted }))
        presenter.present(alongside: { wholeTakenDown = parts.allSatisfy { $0.shown == 0 } })
        XCTAssertTrue(wholeTakenDown, "what goes alongside runs in the same call, before the parts swap")
        XCTAssertEqual(parts.map(\.shown), [1, 1, 1])
        XCTAssertFalse(presenter.isHolding)
        XCTAssertEqual(presenter.setsPresented, 1)
    }

    func testAPictureParkedForAFrameTheStepsLeftNeverCompletesTheSet() {
        let presenter = CanvasPresenter()
        let parts = [Part(), Part()]
        presenter.hold()
        for part in parts { part.wanted = 1; part.drawing = 1 }
        land(parts[0], presenter)
        for part in parts { part.wanted = 2 }     // a second step before the first set completed
        parts[0].drawing = 2
        land(parts[1], presenter)                 // frame 1's picture: no longer wanted
        XCTAssertFalse(presenter.isComplete(parts, showing: { $0.shown == $0.wanted }))
        land(parts[0], presenter)
        XCTAssertFalse(presenter.isComplete(parts, showing: { $0.shown == $0.wanted }),
                       "part 1 holds frame 1, the frame the burst left")
        parts[1].drawing = 2
        land(parts[1], presenter)
        XCTAssertTrue(presenter.isComplete(parts, showing: { $0.shown == $0.wanted }))
        presenter.present()
        XCTAssertEqual(parts.map(\.shown), [2, 2])
    }

    /// A storm of steps, draws landing in random order, and the coordinator's rule — present when
    /// complete — observed after every event: one frame on every part, always.
    func testAStormOfStepsAndLandingsNeverShowsAMix() {
        let presenter = CanvasPresenter()
        let parts = (0..<5).map { _ in Part() }
        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        var frame = 0
        for _ in 0..<5000 {
            switch next(24) {
            case 0:
                frame += 1
                presenter.hold()
                for part in parts { part.wanted = frame }
            case 1...11:
                let part = parts[next(parts.count)]
                if part.drawing == nil, part.shown != part.wanted { part.drawing = part.wanted }
            default:
                land(parts[next(parts.count)], presenter)
            }
            if presenter.isHolding, presenter.isComplete(parts, showing: { $0.shown == $0.wanted }) {
                presenter.present()
            }
            XCTAssertEqual(Set(parts.map(\.shown)).count, 1, "the screen showed \(parts.map(\.shown))")
        }
        XCTAssertGreaterThan(presenter.setsPresented, 20, "PREMISE: the storm presented sets")
    }
}
