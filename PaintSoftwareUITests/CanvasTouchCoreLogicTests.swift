import XCTest

/// `CanvasTouchCore` — whose a canvas touch is, and where the fingers have taken the view.
///
/// **The decisive half replays the owner's iPad.** `docs/bug-evidence/canvas-touches-2026-11-24.jsonl`
/// holds the touches of all 43 flights that caught the canvas deaf or half-deaf, one line each — every
/// landing, lift and cancellation with its place and time — and 120 ordinary gestures out of the same
/// files. A flight carries no move positions, so a contact travels from where it landed to where it left
/// in a straight line; the events, their order and which of them UIKit delivered together are the
/// recording's own.
///
/// The other half walks the arbitration table, which a synthesised gesture cannot reach: XCUITest has no
/// pencil and no cancellation.
final class CanvasTouchCoreLogicTests: XCTestCase {

    // MARK: - The recorded sequences

    private struct Line {
        let time: TimeInterval, phase: String, id: Int, isPencil: Bool, point: CGPoint, down: Int
    }

    private struct Recording {
        let name: String, trigger: String, isFinding: Bool
        let lines: [Line]
        var landings: Int { lines.filter { $0.phase == "b" }.count }
        var mostDown: Int { lines.map(\.down).max() ?? 0 }
        var hasPencil: Bool { lines.contains(where: \.isPencil) }
        var cancelled: Bool { lines.contains { $0.phase == "c" } }
        /// A contact cancelled while another stayed, and a new one landed beside it.
        var isReissue: Bool {
            guard let cancel = lines.firstIndex(where: { $0.phase == "c" && $0.down >= 1 }) else { return false }
            return lines[cancel...].contains { $0.phase == "b" }
        }
        /// The furthest any contact went.
        var travel: CGFloat {
            let from = Dictionary(lines.filter { $0.phase == "b" }.map { ($0.id, $0.point) }, uniquingKeysWith: { a, _ in a })
            return lines.compactMap { line in from[line.id].map { hypot(line.point.x - $0.x, line.point.y - $0.y) } }.max() ?? 0
        }
        /// The gesture the reissue happened in, and not the tap after it.
        var reissuedGesture: Recording {
            let cancel = lines.firstIndex { $0.phase == "c" && $0.down >= 1 } ?? 0
            var end = lines[cancel...].firstIndex { $0.down == 0 } ?? lines.count - 1
            while end + 1 < lines.count, lines[end + 1].down == 0, lines[end + 1].phase != "b" { end += 1 }
            return Recording(name: name, trigger: trigger, isFinding: isFinding, lines: Array(lines[...end]))
        }
    }

    private func recordings() throws -> [Recording] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/bug-evidence/canvas-touches-2026-11-24.jsonl")
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { text in
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let rows = try XCTUnwrap(object["events"] as? [[Any]])
            return Recording(
                name: "\(object["flight"] ?? "") \(object["id"] ?? "")", trigger: object["trigger"] as? String ?? "",
                isFinding: object["role"] as? String == "finding",
                lines: try rows.map { row in
                    Line(time: try XCTUnwrap(row[0] as? Double), phase: try XCTUnwrap(row[1] as? String),
                         id: try XCTUnwrap(row[2] as? Int), isPencil: row[3] as? String == "p",
                         point: CGPoint(x: try XCTUnwrap(row[4] as? Double), y: try XCTUnwrap(row[5] as? Double)),
                         down: try XCTUnwrap(row[6] as? Int))
                })
        }
    }

    /// One call of `update` and what it answered.
    private struct Step {
        let time: TimeInterval
        let down: [CanvasTouchCore.Contact]
        let events: [CanvasTouchCore.Event]
    }

    /// Feeds a recording to `core` as the window delivered it, with a move every 8 ms between, stopping
    /// after the event that carries line `last` when one is given.
    private func replay(_ recording: Recording, into core: inout CanvasTouchCore, startingAt: TimeInterval = 0,
                        through last: Int? = nil) -> [Step] {
        var steps: [Step] = []
        var down: [CanvasTouchCore.Contact] = []
        let lines = recording.lines
        func place(_ id: Int, at time: TimeInterval) -> CGPoint {
            let from = lines.first { $0.id == id && $0.phase == "b" }!, to = lines.first { $0.id == id && $0.phase != "b" }!
            guard to.time > from.time else { return to.point }
            let t = min(1, max(0, (time - from.time) / (to.time - from.time)))
            return CGPoint(x: from.point.x + (to.point.x - from.point.x) * t, y: from.point.y + (to.point.y - from.point.y) * t)
        }
        func move(to time: TimeInterval) {
            down = down.map { .init(id: $0.id, kind: $0.kind, point: place($0.id, at: time)) }
        }
        func send(_ ends: [Int: CanvasTouchCore.End], at time: TimeInterval) {
            let events = core.update(down, ends: ends, at: startingAt + time)
            steps.append(Step(time: time, down: down, events: events))
        }
        var index = 0
        while index < lines.count {
            // One event carries every line at one instant that agrees on how many are down after it.
            let first = lines[index]
            var batch: [Line] = []
            while index < lines.count, lines[index].time == first.time, lines[index].down == first.down {
                batch.append(lines[index])
                index += 1
            }
            if let sent = steps.last?.time {
                var time = sent + 0.008
                while time < first.time, !down.isEmpty {
                    move(to: time)
                    send([:], at: time)
                    time += 0.008
                }
            }
            move(to: first.time)
            var ends: [Int: CanvasTouchCore.End] = [:]
            for line in batch where line.phase != "b" {
                ends[line.id] = line.phase == "c" ? .cancelled : .lifted
                down.removeAll { $0.id == line.id }
            }
            for line in batch where line.phase == "b" {
                down.append(.init(id: line.id, kind: line.isPencil ? .pencil : .finger, point: line.point))
            }
            send(ends, at: first.time)
            if let last, index > last { break }
        }
        return steps
    }

    private func taps(_ steps: [Step]) -> [Int] {
        steps.flatMap(\.events).compactMap { if case .tapped(let fingers) = $0 { return fingers } else { return nil } }
    }

    private func navigations(_ steps: [Step]) -> Int {
        steps.flatMap(\.events).filter { if case .navigationBegan = $0 { return true } else { return false } }.count
    }

    private func moves(_ steps: [Step]) -> [(time: TimeInterval, centroid: CGPoint, scale: CGFloat, turn: CGFloat)] {
        steps.flatMap { step in
            step.events.compactMap { event in
                guard case .navigationMoved(let centroid, let scale, let turn) = event else { return nil }
                return (step.time, centroid, scale, turn)
            }
        }
    }

    /// Two fingers landing 20 ms apart that pan, spread to twice the distance and turn a quarter.
    private func assertTheNextGestureWorks(_ core: inout CanvasTouchCore, _ name: String) {
        var events: [CanvasTouchCore.Event] = []
        func at(_ t: CGFloat, _ time: TimeInterval) {
            let centre = CGPoint(x: 500 + 120 * t, y: 400 + 40 * t), radius = 100 + 100 * t, angle = .pi / 2 * t
            let arm = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            events += core.update([.init(id: 9001, kind: .finger, point: CGPoint(x: centre.x - arm.x, y: centre.y - arm.y)),
                                   .init(id: 9002, kind: .finger, point: CGPoint(x: centre.x + arm.x, y: centre.y + arm.y))],
                                  at: time)
        }
        events += core.update([.init(id: 9001, kind: .finger, point: CGPoint(x: 400, y: 400))], at: 100)
        for step in 0...40 { at(CGFloat(step) / 40, 100.02 + Double(step) * 0.008) }
        events += core.update([], ends: [9001: .lifted, 9002: .lifted], at: 100.4)
        let last = events.compactMap { event -> (CGFloat, CGFloat)? in
            if case .navigationMoved(_, let scale, let turn) = event { return (scale, turn) } else { return nil }
        }.last
        XCTAssertEqual(last?.0 ?? 0, 400 / (200 + CanvasTouchCore.zoomSlop), accuracy: 0.01, "\(name): the next gesture zooms")
        XCTAssertEqual(last?.1 ?? 0, .pi / 2 - CanvasTouchCore.turnSlop, accuracy: 0.01, "\(name): the next gesture turns")
        XCTAssertTrue(events.contains(.navigationEnded), "\(name): and ends")
        XCTAssertTrue(core.isAtRest, "\(name): at rest after the next gesture")
    }

    func testEveryRecordedFreezeEndsAtRestAndTheNextGestureWorks() throws {
        let findings = try recordings().filter(\.isFinding)
        XCTAssertEqual(findings.count, 43, "the evidence is every flight")
        XCTAssertEqual(findings.filter { $0.trigger == "stranded" }.count, 26)
        for finding in findings {
            var core = CanvasTouchCore()
            let steps = replay(finding, into: &core)
            XCTAssertTrue(core.isAtRest, "\(finding.name) leaves something behind")
            XCTAssertEqual(steps.last?.events.contains(.countChanged(0)), true, "\(finding.name) counts down to none")
            assertTheNextGestureWorks(&core, finding.name)
        }
    }

    /// All of them one after another into one core, the way the iPad had them: nothing one leaves is
    /// there for the next to meet.
    func testTheRecordedFreezesInARowLeaveOneCoreAtRest() throws {
        var core = CanvasTouchCore()
        for (index, recording) in try recordings().enumerated() {
            let offset = index * 100
            let lines = recording.lines.map {
                Line(time: $0.time, phase: $0.phase, id: $0.id + offset, isPencil: $0.isPencil, point: $0.point, down: $0.down)
            }
            _ = replay(Recording(name: recording.name, trigger: "", isFinding: false, lines: lines), into: &core,
                       startingAt: Double(offset))
            XCTAssertTrue(core.isAtRest, recording.name)
        }
        assertTheNextGestureWorks(&core, "after all of them")
    }

    func testARecordedLateThirdFingerIsARedoAndMovesNothing() throws {
        let findings = try recordings().filter { $0.isFinding && $0.mostDown == 3 }
        XCTAssertEqual(findings.count, 17, "the recorded three-finger strandings")
        for finding in findings {
            var core = CanvasTouchCore()
            let steps = replay(finding, into: &core)
            XCTAssertEqual(taps(steps), [3], "\(finding.name) is one redo")
            XCTAssertEqual(navigations(steps), 0, "\(finding.name) moves nothing")
        }
    }

    /// The pair of fingers that is on the glass decides where the view is, whichever of them the system
    /// took away and gave back: after the reissue the view still follows their centre, and their spread
    /// and turn are still being read.
    func testARecordedReissueKeepsTheViewFollowingThePair() throws {
        let findings = try recordings().filter { $0.isFinding && $0.isReissue }.map(\.reissuedGesture)
        XCTAssertEqual(findings.count, 21, "5 strandings and 16 navigation misses")
        for finding in findings {
            var core = CanvasTouchCore()
            let steps = replay(finding, into: &core)
            let cancel = try XCTUnwrap(finding.lines.first { $0.phase == "c" && $0.down >= 1 })
            let reissue = try XCTUnwrap(finding.lines.last { $0.phase == "b" && $0.time >= cancel.time })
            let after = moves(steps).filter { $0.time > reissue.time }
            XCTAssertFalse(after.isEmpty, "\(finding.name): the view stops following after the reissue")
            for move in after {
                let down = try XCTUnwrap(steps.last { $0.time == move.time }?.down)
                let centre = CGPoint(x: (down[0].point.x + down[1].point.x) / 2, y: (down[0].point.y + down[1].point.y) / 2)
                XCTAssertEqual(move.centroid.x, centre.x, accuracy: 0.01, finding.name)
                XCTAssertEqual(move.centroid.y, centre.y, accuracy: 0.01, finding.name)
            }
            XCTAssertEqual(navigations(steps), 1, "\(finding.name) is one gesture, not two")
            XCTAssertEqual(taps(steps), [], "\(finding.name) undoes nothing")
        }
    }

    /// The same recordings, cut where the reissued contact has landed: from there the pair pans, spreads
    /// and turns, and the view pans, zooms and turns with it.
    func testPanZoomAndTurnAllSurviveEveryRecordedReissue() throws {
        for finding in try recordings().filter({ $0.isFinding && $0.isReissue }).map(\.reissuedGesture) {
            let cancel = try XCTUnwrap(finding.lines.firstIndex { $0.phase == "c" && $0.down >= 1 })
            let reissue = try XCTUnwrap(finding.lines.lastIndex { $0.phase == "b" && $0.time >= finding.lines[cancel].time })
            var core = CanvasTouchCore()
            let steps = replay(finding, into: &core, through: reissue)
            let at = try XCTUnwrap(steps.last)
            let pair = Array(at.down.suffix(2))
            XCTAssertEqual(pair.count, 2, finding.name)
            let was = moves(steps).last.map { ($0.scale, $0.turn) } ?? (1, 0)
            let a = pair[0].point, b = pair[1].point
            let centre = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let distance = hypot(b.x - a.x, b.y - a.y), angle = atan2(b.y - a.y, b.x - a.x)
            var last: (centroid: CGPoint, scale: CGFloat, turn: CGFloat)?
            for step in 1...60 {
                let t = CGFloat(step) / 60
                let c = CGPoint(x: centre.x + 90 * t, y: centre.y - 60 * t)
                let radius = distance / 2 * (1 + t), direction = angle + .pi / 2 * t
                let arm = CGPoint(x: cos(direction) * radius, y: sin(direction) * radius)
                let events = core.update([.init(id: pair[0].id, kind: .finger, point: CGPoint(x: c.x - arm.x, y: c.y - arm.y)),
                                          .init(id: pair[1].id, kind: .finger, point: CGPoint(x: c.x + arm.x, y: c.y + arm.y))],
                                         at: at.time + Double(step) * 0.008)
                for case .navigationMoved(let centroid, let scale, let turn) in events { last = (centroid, scale, turn) }
            }
            let moved = try XCTUnwrap(last, "\(finding.name): nothing moved the view")
            XCTAssertEqual(moved.centroid.x, centre.x + 90, accuracy: 0.01, "\(finding.name) pans")
            let zoom = moved.scale / was.0
            XCTAssertTrue(abs(zoom - 2) < 0.01 || abs(zoom - distance * 2 / (distance + CanvasTouchCore.zoomSlop)) < 0.01,
                          "\(finding.name) zooms: \(zoom)")
            let round = moved.turn - was.1
            XCTAssertTrue(abs(round - .pi / 2) < 0.01 || abs(round - (.pi / 2 - CanvasTouchCore.turnSlop)) < 0.01,
                          "\(finding.name) turns: \(round)")
        }
    }

    /// The one flight of a pair that bound no navigation recognizer at all: a palm cancelled, then two
    /// fingers 10 ms apart.
    func testTheRecordedPairAfterACancelledPalmMovesTheView() throws {
        let finding = try XCTUnwrap(try recordings().first {
            $0.isFinding && $0.trigger == "navigation" && !$0.isReissue
        })
        XCTAssertEqual(finding.lines.map(\.phase), ["b", "c", "b", "b", "e", "e"])
        var core = CanvasTouchCore()
        let steps = replay(finding, into: &core)
        XCTAssertEqual(navigations(steps), 1)
        XCTAssertGreaterThan(moves(steps).count, 10)
    }

    func testARecordedPalmCancelledAtOnceIsNothing() throws {
        let findings = try recordings().filter { $0.isFinding && $0.landings == 1 }
        XCTAssertEqual(findings.count, 4)
        for finding in findings {
            var core = CanvasTouchCore()
            let steps = replay(finding, into: &core)
            XCTAssertEqual(taps(steps), [], finding.name)
            XCTAssertEqual(navigations(steps), 0, finding.name)
        }
    }

    /// 120 ordinary gestures out of the same files, each of them the thing it was.
    func testTheRecordedHealthyGesturesStillAreWhatTheyWere() throws {
        let controls = try recordings().filter { !$0.isFinding }
        XCTAssertEqual(controls.count, 120)
        var pans = 0, undos = 0, redos = 0, strokes = 0
        for control in controls {
            var core = CanvasTouchCore()
            let steps = replay(control, into: &core)
            XCTAssertTrue(core.isAtRest, control.name)
            if control.hasPencil {
                XCTAssertEqual(navigations(steps), 0, control.name)
                XCTAssertEqual(taps(steps), [], control.name)
                strokes += 1
            } else if control.travel < 3, !control.cancelled, control.mostDown == 2 {
                XCTAssertEqual(taps(steps), [2], "\(control.name) is an undo")
                undos += 1
            } else if control.travel < 3, !control.cancelled, control.mostDown == 3 {
                XCTAssertEqual(taps(steps), [3], "\(control.name) is a redo")
                redos += 1
            } else if control.cancelled {
                XCTAssertEqual(taps(steps), [], "\(control.name) was cancelled, and undoes nothing")
            } else if control.mostDown == 2, control.travel > 25 {
                XCTAssertEqual(navigations(steps), 1, "\(control.name) moves the view")
                pans += 1
            }
        }
        XCTAssertGreaterThanOrEqual(pans, 25)
        XCTAssertGreaterThanOrEqual(undos, 20)
        XCTAssertGreaterThanOrEqual(redos, 20)
        XCTAssertEqual(strokes, 6)
    }

    // MARK: - The arbitration table

    private var core = CanvasTouchCore()
    private var clock: TimeInterval = 0

    override func setUp() {
        core = CanvasTouchCore()
        clock = 0
    }

    @discardableResult
    private func send(_ contacts: [(Int, CanvasTouchCore.Kind, CGFloat, CGFloat)], ends: [Int: CanvasTouchCore.End] = [:],
                      mayNavigate: Bool = true) -> [CanvasTouchCore.Event] {
        clock += 0.01
        return core.update(contacts.map { .init(id: $0.0, kind: $0.1, point: CGPoint(x: $0.2, y: $0.3)) }, ends: ends, at: clock,
                           mayNavigate: { mayNavigate })
    }

    func testALoneFingerMayDrawAndLiftsWithNothingElseHappening() {
        XCTAssertEqual(send([(1, .finger, 0, 0)]), [.countChanged(1)])
        XCTAssertEqual(core.drawer, 1)
        XCTAssertEqual(send([(1, .finger, 300, 0)]), [], "one finger moves nothing")
        XCTAssertEqual(send([], ends: [1: .lifted]), [.countChanged(0)])
        XCTAssertTrue(core.isAtRest)
    }

    func testTwoFingersInOneEventNeverMayDraw() {
        XCTAssertEqual(send([(1, .finger, 0, 0), (2, .finger, 100, 0)]), [.countChanged(2)])
        XCTAssertNil(core.drawer)
    }

    func testASecondFingerTakesAFingersStrokeHoweverLongItHasRun() {
        send([(1, .finger, 0, 0)])
        for step in 1...50 { send([(1, .finger, CGFloat(step) * 10, 0)]) }
        XCTAssertEqual(send([(1, .finger, 500, 0), (2, .finger, 600, 0)]), [.countChanged(2), .strokeRevoked(1, .handedOver)])
        XCTAssertNil(core.drawer)
    }

    func testTheViewFollowsThePairFromWhereItPassedItsSlop() {
        send([(1, .finger, 0, 0)])
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        XCTAssertEqual(send([(1, .finger, 0, 9), (2, .finger, 100, 9)]), [], "inside the slop")
        XCTAssertEqual(send([(1, .finger, 0, 12), (2, .finger, 100, 12)]),
                       [.navigationBegan(CGPoint(x: 50, y: 12)),
                        .navigationMoved(centroid: CGPoint(x: 50, y: 12), scale: 1, turn: 0)])
        XCTAssertTrue(core.isNavigating)
        XCTAssertEqual(send([(1, .finger, 40, 12), (2, .finger, 140, 12)]),
                       [.navigationMoved(centroid: CGPoint(x: 90, y: 12), scale: 1, turn: 0)])
        XCTAssertEqual(send([], ends: [1: .lifted, 2: .lifted]), [.countChanged(0), .navigationEnded])
        XCTAssertTrue(core.isAtRest)
    }

    /// MEASURED on UIKit's own pinch, which this replaced: from 200 pt apart, 208 does not zoom and 216
    /// zooms by 216/208 — the slop is waited for and taken off.
    func testZoomWaitsForItsSlopAndTakesItOff() {
        send([(1, .finger, 0, 0), (2, .finger, 200, 0)])
        XCTAssertEqual(send([(1, .finger, -3, 0), (2, .finger, 204, 0)]), [])
        send([(1, .finger, -8, 0), (2, .finger, 208, 0)])
        XCTAssertEqual(lastScale(send([(1, .finger, -100, 0), (2, .finger, 300, 0)])), 400 / 208, accuracy: 0.001)
        XCTAssertEqual(lastScale(send([(1, .finger, 40, 0), (2, .finger, 160, 0)])), 120 / 208, accuracy: 0.001)
    }

    func testPinchingInTakesTheSlopOffTheOtherWay() {
        send([(1, .finger, 0, 0), (2, .finger, 200, 0)])
        XCTAssertEqual(lastScale(send([(1, .finger, 40, 0), (2, .finger, 160, 0)])), 120 / 192, accuracy: 0.001)
    }

    /// MEASURED on UIKit's own rotation: 8° turned by 2.9°, 15° by 9.8°.
    func testTurnWaitsForFiveDegreesAndTakesThemOff() {
        func turned(_ degrees: CGFloat) -> [CanvasTouchCore.Event] {
            let a = degrees * .pi / 180
            return send([(1, .finger, -100 * cos(a), -100 * sin(a)), (2, .finger, 100 * cos(a), 100 * sin(a))])
        }
        _ = turned(0)
        XCTAssertEqual(turned(4), [])
        XCTAssertEqual(lastTurn(turned(15)), 10 * .pi / 180, accuracy: 0.001)
        XCTAssertEqual(lastTurn(turned(-15)), -20 * .pi / 180, accuracy: 0.001, "and back through where it began")
    }

    /// The long way round is never taken: a finger crossing the half turn is still going the same way.
    func testATurnPastHalfAWayRoundKeepsGoing() {
        for step in 0...36 {
            let a = CGFloat(step) * 10 * .pi / 180
            let events = send([(1, .finger, -100 * cos(a), -100 * sin(a)), (2, .finger, 100 * cos(a), 100 * sin(a))])
            if step == 36 { XCTAssertEqual(lastTurn(events), 355 * .pi / 180, accuracy: 0.001) }
        }
    }

    func testAPanThatNeitherSpreadsNorTurnsNeitherZoomsNorTurns() {
        send([(1, .finger, 0, 0), (2, .finger, 200, 0)])
        for step in 1...30 {
            let x = CGFloat(step) * 10, wobble: CGFloat = step % 2 == 0 ? 2 : -2
            let events = send([(1, .finger, x, wobble), (2, .finger, 200 + x + wobble, 0)])
            guard step > 1 else { continue }  // the first is still inside the slop
            XCTAssertEqual(lastScale(events), 1)
            XCTAssertEqual(lastTurn(events), 0)
        }
    }

    func testAFingerLeavingHoldsTheViewAndOneJoiningCarriesItOnWithoutAJump() {
        send([(1, .finger, 0, 0), (2, .finger, 200, 0)])
        XCTAssertEqual(lastScale(send([(1, .finger, 0, 0), (2, .finger, 416, 0)])), 2, accuracy: 0.001)
        XCTAssertEqual(send([(1, .finger, 0, 0)], ends: [2: .lifted]), [.countChanged(1)], "the view holds")
        XCTAssertEqual(send([(1, .finger, 50, 50)]), [], "and one finger does not move it")
        XCTAssertTrue(core.isNavigating)
        XCTAssertEqual(send([(1, .finger, 50, 50), (3, .finger, 50, 150)]),
                       [.countChanged(2), .navigationRebased(CGPoint(x: 50, y: 100))])
        XCTAssertNil(core.drawer)
        XCTAssertEqual(send([(1, .finger, 50, 50), (3, .finger, 50, 250)]),
                       [.navigationMoved(centroid: CGPoint(x: 50, y: 150), scale: 4, turn: 0)],
                       "already zooming, so the new pair zooms from its first movement, from where the view was")
    }

    func testAThirdFingerWhileNavigatingIsIgnoredAndTakesOverWhenOneLeaves() {
        send([(1, .finger, 0, 0), (2, .finger, 200, 0)])
        send([(1, .finger, 0, 50), (2, .finger, 200, 50)])
        XCTAssertEqual(send([(1, .finger, 0, 60), (2, .finger, 200, 60), (3, .finger, 100, 400)]),
                       [.countChanged(3), .navigationMoved(centroid: CGPoint(x: 100, y: 60), scale: 1, turn: 0)])
        XCTAssertEqual(send([(2, .finger, 200, 60), (3, .finger, 100, 400)], ends: [1: .lifted]),
                       [.countChanged(2), .navigationRebased(CGPoint(x: 150, y: 230))])
    }

    func testAThreeFingerTapToleratesMoreWanderThanAPairBeforeItIsAGesture() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0), (3, .finger, 200, 0)])
        XCTAssertEqual(send([(1, .finger, 0, 20), (2, .finger, 100, 20), (3, .finger, 200, 20)]), [])
        XCTAssertEqual(send([], ends: [1: .lifted, 2: .lifted, 3: .lifted]), [.countChanged(0), .tapped(fingers: 3)])
        send([(4, .finger, 0, 0), (5, .finger, 100, 0), (6, .finger, 200, 0)])
        XCTAssertTrue(send([(4, .finger, 0, 40), (5, .finger, 100, 40), (6, .finger, 200, 40)])
            .contains(.navigationBegan(CGPoint(x: 50, y: 40))))
        XCTAssertEqual(send([], ends: [4: .lifted, 5: .lifted, 6: .lifted]), [.countChanged(0), .navigationEnded])
    }

    func testFourFingersAndOneFingerTapNothing() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0), (3, .finger, 200, 0), (4, .finger, 300, 0)])
        XCTAssertEqual(send([], ends: [1: .lifted, 2: .lifted, 3: .lifted, 4: .lifted]), [.countChanged(0)])
        send([(5, .finger, 0, 0)])
        XCTAssertEqual(send([], ends: [5: .lifted]), [.countChanged(0)])
    }

    func testATapTakesNoLongerThanUIKitsDid() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        clock = 1.4
        XCTAssertEqual(send([], ends: [1: .lifted, 2: .lifted]), [.countChanged(0), .tapped(fingers: 2)])
        send([(3, .finger, 0, 0), (4, .finger, 100, 0)])
        clock += 1.6
        XCTAssertEqual(send([], ends: [3: .lifted, 4: .lifted]), [.countChanged(0)], "a rest is not a tap")
        send([(5, .finger, 0, 0)])
        clock += 0.8
        send([(5, .finger, 0, 0), (6, .finger, 100, 0)])
        XCTAssertEqual(send([], ends: [5: .lifted, 6: .lifted]), [.countChanged(0)], "nor is a finger that came much later")
    }

    func testACancelledContactSpoilsTheTapItWasPartOf() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        send([(1, .finger, 0, 0)], ends: [2: .cancelled])
        XCTAssertEqual(send([], ends: [1: .lifted]), [.countChanged(0)])
    }

    func testAPencilDrawsAndAFingerNeverInterruptsItNorMovesTheView() {
        send([(1, .pencil, 0, 0)])
        XCTAssertEqual(core.drawer, 1)
        send([(1, .pencil, 10, 0), (2, .finger, 300, 300)])
        send([(1, .pencil, 20, 0), (2, .finger, 300, 300), (3, .finger, 400, 300)])
        XCTAssertEqual(send([(1, .pencil, 30, 0), (2, .finger, 300, 400), (3, .finger, 400, 400)]), [], "palms move nothing")
        XCTAssertEqual(core.drawer, 1)
        XCTAssertEqual(send([(2, .finger, 300, 400), (3, .finger, 400, 400)], ends: [1: .lifted]), [.countChanged(2)])
        XCTAssertEqual(send([(2, .finger, 300, 500), (3, .finger, 400, 500)]), [],
                       "a palm is a palm for its whole life, whoever lifts first")
        XCTAssertEqual(send([], ends: [2: .lifted, 3: .lifted]), [.countChanged(0)], "and undoes nothing")
        XCTAssertTrue(core.isAtRest)
    }

    /// A palm still resting after the pen has lifted leaves the canvas to the other hand.
    func testTwoFingersBesideARestingPalmMoveTheView() {
        send([(1, .pencil, 0, 0)])
        send([(1, .pencil, 0, 0), (2, .finger, 300, 300)])
        send([(2, .finger, 300, 300)], ends: [1: .lifted])
        send([(2, .finger, 300, 300), (3, .finger, 0, 0), (4, .finger, 100, 0)])
        XCTAssertTrue(send([(2, .finger, 300, 300), (3, .finger, 0, 20), (4, .finger, 100, 20)])
            .contains(.navigationBegan(CGPoint(x: 50, y: 20))))
        XCTAssertEqual(send([(2, .finger, 300, 300)], ends: [3: .lifted, 4: .lifted]), [.countChanged(1), .navigationEnded],
                       "the gesture ends with its own fingers, not with the palm")
    }

    func testAPencilTakesOverFromAFingersStroke() {
        send([(1, .finger, 0, 0)])
        XCTAssertEqual(send([(1, .finger, 0, 0), (2, .pencil, 100, 0)]), [.countChanged(2), .strokeRevoked(1, .handedOver)])
        XCTAssertEqual(core.drawer, 2)
    }

    func testAPencilLandingWhileTwoFingersMoveTheViewDoesNotDraw() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        send([(1, .finger, 0, 50), (2, .finger, 100, 50)])
        send([(1, .finger, 0, 50), (2, .finger, 100, 50), (3, .pencil, 300, 0)])
        XCTAssertNil(core.drawer)
        XCTAssertEqual(send([(1, .finger, 0, 60), (2, .finger, 100, 60), (3, .pencil, 300, 0)]),
                       [.navigationMoved(centroid: CGPoint(x: 50, y: 60), scale: 1, turn: 0)])
    }

    func testAPencilLandingWhileTheViewIsOnlyHeldDrawsAndEndsTheGesture() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        send([(1, .finger, 0, 50), (2, .finger, 100, 50)])
        send([(1, .finger, 0, 50)], ends: [2: .lifted])
        XCTAssertEqual(send([(1, .finger, 0, 50), (3, .pencil, 300, 0)]), [.countChanged(2), .navigationEnded])
        XCTAssertEqual(core.drawer, 3)
    }

    func testADragThatHoldsATouchKeepsThePairFromMovingTheViewForGood() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        XCTAssertEqual(send([(1, .finger, 0, 50), (2, .finger, 100, 50)], mayNavigate: false), [])
        XCTAssertEqual(send([(1, .finger, 0, 90), (2, .finger, 100, 90)]), [], "asked once")
        XCTAssertEqual(send([], ends: [1: .lifted, 2: .lifted]), [.countChanged(0)], "and no tap")
        XCTAssertTrue(core.isAtRest)
    }

    // MARK: - Touches that end without saying so

    func testAStrokeWhoseTouchVanishesIsInterruptedAndTheNextTouchDraws() {
        send([(1, .finger, 0, 0)])
        XCTAssertEqual(send([]), [.countChanged(0), .strokeRevoked(1, .interrupted)])
        XCTAssertTrue(core.isAtRest)
        // UIKit hands the same touch object out again: the caller gives it a new id in the same event.
        send([(2, .pencil, 0, 0)])
        XCTAssertEqual(send([(3, .pencil, 10, 0)]), [.strokeRevoked(2, .interrupted)])
        XCTAssertEqual(core.drawer, 3, "the touch that found the corpse draws")
    }

    func testACancelledStrokeIsInterruptedAndALiftedOneIsNot() {
        send([(1, .pencil, 0, 0)])
        XCTAssertEqual(send([], ends: [1: .cancelled]), [.countChanged(0), .strokeRevoked(1, .interrupted)])
        send([(2, .pencil, 0, 0)])
        XCTAssertEqual(send([], ends: [2: .lifted]), [.countChanged(0)])
    }

    func testAPairThatVanishesEndsItsGesture() {
        send([(1, .finger, 0, 0), (2, .finger, 100, 0)])
        send([(1, .finger, 0, 50), (2, .finger, 100, 50)])
        XCTAssertEqual(send([]), [.countChanged(0), .navigationEnded])
        XCTAssertTrue(core.isAtRest)
    }

    func testHearingOneEventTwiceChangesNothing() {
        send([(1, .finger, 0, 0)])
        XCTAssertEqual(core.update([.init(id: 1, kind: .finger, point: .zero)], at: clock), [])
        XCTAssertEqual(core.drawer, 1)
    }

    private func lastScale(_ events: [CanvasTouchCore.Event]) -> CGFloat {
        for case .navigationMoved(_, let scale, _) in events.reversed() { return scale }
        return .nan
    }

    private func lastTurn(_ events: [CanvasTouchCore.Event]) -> CGFloat {
        for case .navigationMoved(_, _, let turn) in events.reversed() { return turn }
        return .nan
    }
}
