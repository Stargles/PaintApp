import XCTest
import UIKit
import CoreGraphics

/// **A direction-following brush's dabs at the ends of a stroke** — TODO (132), the owner's *"for
/// brushes which rotation follows the direction of the stroke, the start and end of those brushes are
/// messy"*, and the recording they left to prove it (`recording-20261001-002122`).
///
/// The operand throughout is **the angle each dab was stamped at**, read off the dab itself — a
/// `CollectingDabTarget` under the live walk and `BrushStamper.bake` for the replay — because the
/// defect is a dab turned the wrong way, and a stored direction can be right while the ink is not.
/// Every test that claims the ends are clean states its premise first: the same stroke read with
/// nothing held (`StrokeHeading()`), which is the answer before ends were held, and shows the mess is
/// in the fixture. A test that passed against an unheld reading would be measuring a definition.
final class StrokeHeadingLogicTests: XCTestCase {

    // MARK: - The owner's recording

    /// The five strokes on the canvas in `recording-20261001-002122.jsonl`, as the events delivered
    /// them: window x, window y, Pencil force. The canvas was at 1.0948×, and the recording is the
    /// main-thread touch events, not the coalesced stream — so what is here is sparser than what the
    /// app received and the ends are, if anything, kinder. **Three of the five lift with a hook**:
    /// 1.4, 2.9 and 0.7 canvas points, 85–170° off the stroke.
    private static let ownersRecording: [[(x: CGFloat, y: CGFloat, force: CGFloat)]] = [
        [(458.5, 352, 0.33), (460.5, 348.5, 0.64), (483, 328, 1.26), (502.5, 313, 1.44), (514.5, 301.5, 1.27), (515, 303, 0)],
        [(489, 369.5, 0.33), (492, 367.5, 0.77), (517, 348, 1.36), (538.5, 332, 1.29), (538, 334, 0.11), (537, 334.5, 0)],
        [(512.5, 400.5, 0.33), (515, 397.5, 0.78), (538, 378, 1.37), (556, 368, 1.03), (558, 366.5, 0.8), (558, 366.5, 0)],
        [(538, 429, 0.33), (540.5, 426, 0.98), (561.5, 408, 1.43), (576.5, 396, 1.3), (577, 396.5, 0)],
        [(566.5, 459.5, 0.33), (574.5, 452, 1.2), (596, 431, 1.8), (603, 425, 0)],
    ]

    private static func owners() -> [[VectorSample]] {
        ownersRecording.map { stroke in
            stroke.map { VectorSample(x: $0.x / 1.0948, y: $0.y / 1.0948, pressure: min($0.force / 4.17, 1),
                                      deltaTime: 0.05) }
        }
    }

    /// The brushes that follow the direction, at three sizes — the margin is proportional to the size,
    /// and a tip's own width is what makes a dab turned the wrong way visible.
    private static func followers() -> [(name: String, brush: Brush)] {
        var out: [(String, Brush)] = []
        for size: CGFloat in [12, 36, 80] {
            var square = BrushLibrary.square
            square.size = size
            out.append(("square \(Int(size))", square))
        }
        var painterly = BrushLibrary.painterly
        painterly.dab.angle.jitter = 0
        out.append(("painterly", painterly))
        return out
    }

    // MARK: - Reading dabs

    private func liveDabs(_ raw: [VectorSample], brush: Brush) -> [BrushStamper.BakedDab] {
        let target = BrushStamper.CollectingDabTarget()
        var walk = BrushStamper.LiveWalk(seed: 7)
        for sample in raw { walk.stamp(to: sample, into: target, brush: brush, color: .black, brushSize: brush.size) }
        walk.finish(into: target, brush: brush, color: .black, brushSize: brush.size)
        return target.dabs
    }

    private func replayDabs(_ raw: [VectorSample], brush: Brush) -> [BrushStamper.BakedDab] {
        BrushStamper.bake(samples: StrokeSamples(raw, channels: .captured), brush: brush, color: .black,
                          brushSize: brush.size, brushOpacity: 1, random: DabRandom(seed: 7)).dabs
    }

    /// Each dab's turn off the brush's own base angle, in degrees — what direction-follow contributed.
    private func headings(_ dabs: [BrushStamper.BakedDab], brush: Brush) -> [CGFloat] {
        dabs.map { dab in
            guard case .image(_, let angle) = dab.tip else { return 0 }
            return Self.wrapped(angle * 180 / .pi - CGFloat(brush.dab.angle.base) * 360)
        }
    }

    private static func wrapped(_ degrees: CGFloat) -> CGFloat {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// The largest turn between two neighbouring dabs among the first `count` and among the last
    /// `count` — the measure of a nib that spins at an end of the stroke.
    private func endJumps(_ headings: [CGFloat], count: Int = 8) -> (start: CGFloat, end: CGFloat) {
        func worst(_ run: ArraySlice<CGFloat>) -> CGFloat {
            zip(run, run.dropFirst()).map { abs(Self.wrapped($1 - $0)) }.max() ?? 0
        }
        return (worst(headings.prefix(count)), worst(headings.suffix(count)))
    }

    /// The dabs that lie wholly inside the lead-in and the tail — by arc, a spacing clear of each
    /// anchor so a dab on the boundary, which may fall either side of it between the chord and the
    /// curve, is not asked. The brushes here have a constant spacing, so a dab's arc is its index.
    private func heldDabs(_ headings: [CGFloat], raw: [VectorSample], brush: Brush) -> (lead: [CGFloat], tail: [CGFloat]) {
        let spacing = BrushStamper.stampSpacing(brushSize: brush.size, fraction: brush.dab.spacing)
        let margin = StrokeHeading.margin(brushSize: brush.size)
        let length = zip(raw, raw.dropFirst()).reduce(CGFloat(0)) { total, pair in
            total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
        let indexed = headings.enumerated().map { (arc: CGFloat($0.offset) * spacing, heading: $0.element) }
        return (indexed.filter { $0.arc <= margin - spacing }.map(\.heading),
                indexed.filter { $0.arc >= length - margin + spacing }.map(\.heading))
    }

    /// How far apart the most different two of `headings` are, in degrees.
    private func spread(_ headings: [CGFloat]) -> CGFloat {
        guard let first = headings.first else { return 0 }
        return headings.map { abs(Self.wrapped($0 - first)) }.max() ?? 0
    }

    /// **What a stroke's dabs faced before its ends were held**: the same march, with the direction
    /// read straight off the curve everywhere. `StrokeSensors` with an empty `StrokeHeading` is
    /// exactly what every brush was given until the ends were held.
    private func unheldHeadings(_ raw: [VectorSample], brush: Brush) -> [CGFloat] {
        let samples = StrokeSamples(raw, channels: .captured)
        let path = StrokePath(points: samples.positions)
        let sensors = StrokeSensors(samples: samples, path: path, random: DabRandom(seed: 7), brushSize: brush.size)
        let spacing = BrushStamper.stampSpacing(brushSize: brush.size, fraction: brush.dab.spacing)
        var out = [Self.degrees(sensors.value(of: .direction, at: DabSite(parameter: 0, arcWidths: 0)))]
        var arcWidths: CGFloat = 0
        var carry = WalkCarry(spacing: spacing)
        for index in 0..<(raw.count - 1) {
            carry = path.advance(segment: index, carry: carry) { _, u, walked in
                arcWidths += walked / brush.size
                out.append(Self.degrees(sensors.value(of: .direction,
                                                      at: DabSite(parameter: CGFloat(index) + u, arcWidths: arcWidths))))
                return spacing
            }
        }
        return out
    }

    private static func degrees(_ turns: CGFloat) -> CGFloat { wrapped(turns * 360) }

    // MARK: - The rule

    func testTheMarginIsAQuarterOfTheBrushAndNeverUnderTheFloor() {
        XCTAssertEqual(StrokeHeading.margin(brushSize: 80), 20, accuracy: 1e-9)
        XCTAssertEqual(StrokeHeading.margin(brushSize: 36), 9, accuracy: 1e-9)
        XCTAssertEqual(StrokeHeading.margin(brushSize: 4), StrokeHeading.minimumMargin,
                       "a fine nib's tail must still clear a pen lift's hook, which does not shrink with the brush")
        XCTAssertEqual(StrokeHeading.margin(brushSize: 0), StrokeHeading.minimumMargin, "a zero-width brush has a floor too")
    }

    func testTheTwoReadArcsMeetOnAShortStrokeAndTheLeadWinsWhereTheyDo() {
        let long = StrokeHeading.readArcs(length: 100, margin: 9)
        XCTAssertEqual(long.lead, 9, accuracy: 1e-9)
        XCTAssertEqual(long.tail, 91, accuracy: 1e-9)
        let dash = StrokeHeading.readArcs(length: 12, margin: 9)
        XCTAssertEqual(dash.lead, 9, accuracy: 1e-9)
        XCTAssertEqual(dash.tail, 9, accuracy: 1e-9, "the tail never reads before the lead, so a short dash faces one way")
        let sliver = StrokeHeading.readArcs(length: 4, margin: 9)
        XCTAssertEqual(sliver.lead, 4, accuracy: 1e-9, "a stroke under a margin reads its own far end")
        XCTAssertEqual(sliver.tail, 4, accuracy: 1e-9)

        let heading = StrokeHeading(lead: .init(arc: 9, direction: CGPoint(x: 1, y: 0)),
                                    tail: .init(arc: 9, direction: CGPoint(x: 0, y: 1)))
        XCTAssertEqual(heading.held(atArc: 9), CGPoint(x: 1, y: 0), "the lead wins where the two meet")
        XCTAssertNil(StrokeHeading(lead: .init(arc: 9, direction: CGPoint(x: 1, y: 0)), tail: nil).held(atArc: 10),
                     "past the lead, with no tail yet, a dab reads the path")
    }

    func testAnArcTableFindsTheSegmentAPointIsOnAndSkipsOneWithNoLength() {
        let table = ArcTable([0, 4, 4, 10])
        XCTAssertEqual(table.length, 10)
        XCTAssertEqual(table.locate(2)?.segment, 0)
        XCTAssertEqual(table.locate(2)?.offset ?? -1, 2, accuracy: 1e-12)
        XCTAssertEqual(table.locate(7)?.segment, 2, "the zero-length segment between two coincident vertices has no direction")
        XCTAssertEqual(table.locate(7)?.offset ?? -1, 3, accuracy: 1e-12)
        XCTAssertEqual(table.locate(99)?.segment, 2, "clamped to the path")
        XCTAssertNil(ArcTable([0, 0, 0]).locate(1), "a path with no length has no direction anywhere")
    }

    /// `parameter(ofSegment:atDistance:)` is the inverse of `length(ofSegment:upTo:)` on one polyline,
    /// to the flatness the polyline was cut at — the property that puts a held direction where the dab
    /// march would put a dab.
    func testTheParameterAtADistanceInvertsTheLengthUpToAParameter() {
        let path = StrokePath(points: [CGPoint(x: 0, y: 0), CGPoint(x: 9, y: 4), CGPoint(x: 18, y: 4), CGPoint(x: 30, y: 14)])
        for segment in 0..<3 {
            let whole = path.length(ofSegment: segment)
            for fraction: CGFloat in [0.1, 0.37, 0.5, 0.9] {
                let u = path.parameter(ofSegment: segment, atDistance: whole * fraction)
                XCTAssertEqual(path.length(ofSegment: segment, upTo: u), whole * fraction, accuracy: StrokePath.flatness,
                               "segment \(segment), \(fraction) of the way")
            }
        }
    }

    // MARK: - The owner's strokes

    /// **The recording's own strokes, replayed.** Before the ends were held, three of the five ended
    /// in a dab turned 85°, 113° and 140° off its neighbour by the pen's lift, and all five started
    /// with a dab or two turned 10–20° by the landing. Now every dab inside the lead-in faces one
    /// direction, every dab inside the tail faces one, and no neighbouring pair at either end turns
    /// by more than a few degrees.
    func testTheOwnersStrokesEndWithoutSpikesWhenReplayed() {
        var sawAHook = false, sawALanding = false
        for (name, brush) in Self.followers() {
            for (index, raw) in Self.owners().enumerated() {
                let unheld = heldDabs(unheldHeadings(raw, brush: brush), raw: raw, brush: brush)
                sawALanding = sawALanding || spread(unheld.lead) > 8
                sawAHook = sawAHook || spread(unheld.tail) > 45
                let replay = headings(replayDabs(raw, brush: brush), brush: brush)
                let held = heldDabs(replay, raw: raw, brush: brush)
                XCTAssertLessThan(spread(held.lead), 1e-6, "\(name) stroke \(index): the lead-in's dabs turn together")
                XCTAssertLessThan(spread(held.tail), 1e-6, "\(name) stroke \(index): the tail's dabs turn together")
                let jumps = endJumps(replay)
                XCTAssertLessThan(jumps.start, 5, "\(name) stroke \(index): the first dabs run smoothly into the stroke")
                XCTAssertLessThan(jumps.end, 5, "\(name) stroke \(index): the last dabs run smoothly out of it")
            }
        }
        XCTAssertTrue(sawALanding, "PREMISE: the recording's landings reach the dabs when nothing is held, or this measures nothing")
        XCTAssertTrue(sawAHook, "PREMISE: the recording's hooks reach the dabs when nothing is held, or this measures nothing")
    }

    /// **The same strokes under the pen** — the live walk, which is what a raster layer keeps. The
    /// recording is sparse enough that the chord turns between its samples by up to 11° in the
    /// interior, so the live ends are held to turning *together*, not to being smooth.
    func testTheOwnersStrokesEndWithoutSpikesUnderThePen() {
        for (name, brush) in Self.followers() {
            for (index, raw) in Self.owners().enumerated() {
                let held = heldDabs(headings(liveDabs(raw, brush: brush), brush: brush), raw: raw, brush: brush)
                XCTAssertLessThan(spread(held.lead), 1e-6, "\(name) stroke \(index): live, the lead-in's dabs turn together")
                XCTAssertLessThan(spread(held.tail), 1e-6, "\(name) stroke \(index): live, the tail's dabs turn together")
            }
        }
    }

    /// **The stroke under the pen and the stroke the baker replays turn their ends the same way.** The
    /// two read different geometry — a chord at input density against the curve through the same
    /// samples — so they agree to the curve's own angular error, which on these strokes is a few
    /// degrees.
    func testTheLiveEndsAndTheReplayedEndsFaceTheSameWay() {
        for (name, brush) in Self.followers() {
            for (index, raw) in Self.owners().enumerated() {
                let live = headings(liveDabs(raw, brush: brush), brush: brush)
                let replay = headings(replayDabs(raw, brush: brush), brush: brush)
                XCTAssertLessThanOrEqual(abs(live.count - replay.count), 1, "\(name) stroke \(index): the same dabs, to the refit")
                guard let liveFirst = live.first, let replayFirst = replay.first,
                      let liveLast = live.last, let replayLast = replay.last else { continue }
                XCTAssertLessThan(abs(Self.wrapped(liveFirst - replayFirst)), 8, "\(name) stroke \(index): the first dab")
                XCTAssertLessThan(abs(Self.wrapped(liveLast - replayLast)), 8, "\(name) stroke \(index): the last dab")
            }
        }
    }

    // MARK: - Synthetic strokes, where the right answer is known

    /// A straight stroke along `theta` from `(100, 100)`: `run` points long at 120 Hz, easing in and
    /// out, optionally landing with a sideways wobble over its first few points and lifting with a hook.
    private static func straight(theta: CGFloat, run: CGFloat = 120, landing: CGFloat = 0, hook: CGFloat = 0) -> [VectorSample] {
        let along = CGPoint(x: cos(theta), y: sin(theta)), across = CGPoint(x: -sin(theta), y: cos(theta))
        var out: [VectorSample] = []
        let steps = 60
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let s = (t * t * (3 - 2 * t)) * run
            let wobble = landing * exp(-s / 2) * sin(s * 1.2)
            out.append(VectorSample(x: 100 + along.x * s + across.x * wobble, y: 100 + along.y * s + across.y * wobble,
                                    pressure: min(0.2 + t * 2, 0.8), deltaTime: 1 / 120))
        }
        if hook > 0 {
            let end = out[steps].point
            let away = CGPoint(x: cos(theta + 1.8), y: sin(theta + 1.8))
            out.append(VectorSample(x: end.x + away.x * hook * 0.6, y: end.y + away.y * hook * 0.6, pressure: 0.1, deltaTime: 1 / 120))
            out.append(VectorSample(x: end.x + away.x * hook, y: end.y + away.y * hook, pressure: 0, deltaTime: 1 / 120))
        }
        return out
    }

    /// **A clean run that lifts with a hook: the last dabs face the run, not the hook.** The hook is
    /// 3 pt at 103° off, the size the owner's own hardware reported.
    func testALiftHookAfterACleanRunDoesNotTurnTheLastDabs() {
        let theta: CGFloat = -0.5
        let truth = theta * 180 / .pi
        let raw = Self.straight(theta: theta, hook: 3)
        var sawAHook = false
        for (name, brush) in Self.followers() {
            // A brush spaced wider than the hook may lay no dab on it at all; the premise is that
            // some of these do.
            sawAHook = sawAHook || abs(Self.wrapped(unheldHeadings(raw, brush: brush).last! - truth)) > 45
            for (walk, dabs) in [("live", liveDabs(raw, brush: brush)), ("replay", replayDabs(raw, brush: brush))] {
                for heading in headings(dabs, brush: brush).suffix(6) {
                    XCTAssertEqual(Self.wrapped(heading - truth), 0, accuracy: 3,
                                   "\(name) \(walk): the lift's hook must not reach the dabs")
                }
            }
        }
        XCTAssertTrue(sawAHook, "PREMISE: with nothing held the hook turns the last dab of a finely spaced brush")
    }

    /// **A landing wobble does not turn the first dabs.** A pen that lands and swings 1.2 pt sideways
    /// over its first 4 pt before committing to a direction.
    func testALandingWobbleDoesNotTurnTheFirstDabs() {
        let theta: CGFloat = 0.4
        let truth = theta * 180 / .pi
        let raw = Self.straight(theta: theta, landing: 1.2)
        var sawAWobble = false
        for (name, brush) in Self.followers() {
            sawAWobble = sawAWobble || abs(Self.wrapped(unheldHeadings(raw, brush: brush).first! - truth)) > 15
            for (walk, dabs) in [("live", liveDabs(raw, brush: brush)), ("replay", replayDabs(raw, brush: brush))] {
                for heading in headings(dabs, brush: brush).prefix(6) {
                    XCTAssertEqual(Self.wrapped(heading - truth), 0, accuracy: 6,
                                   "\(name) \(walk): the landing's wobble must not reach the dabs")
                }
            }
        }
        XCTAssertTrue(sawAWobble, "PREMISE: with nothing held the first dab follows the wobble")
    }

    /// **Every dab in the lead-in faces one direction, and every dab in the tail faces one** — the held
    /// ones, to the bit — and a dab between them faces the path's own tangent, exactly as it did.
    func testTheEndsAreHeldAndTheInteriorIsTheCurvesOwnTangent() {
        let raw = Self.straight(theta: 0.3, landing: 1.0, hook: 2.5)
        let brush = Self.followers()[1].brush
        let samples = StrokeSamples(raw, channels: .captured)
        let path = StrokePath(points: samples.positions)
        let margin = StrokeHeading.margin(brushSize: brush.size)
        let heading = path.heading(margin: margin)
        let length = path.arcLength(to: path.domainEnd)
        let held = StrokeSensors(samples: samples, path: path, random: DabRandom(seed: 7), brushSize: brush.size,
                                 heading: heading)
        let free = StrokeSensors(samples: samples, path: path, random: DabRandom(seed: 7), brushSize: brush.size)
        let lead = heading.lead!.direction, tail = heading.tail!.direction
        var interior = 0
        for step in 0...400 {
            let parameter = path.domainEnd * CGFloat(step) / 400
            let arc = path.arcLength(to: parameter)
            let site = DabSite(parameter: parameter, arcWidths: arc / brush.size)
            let direction = held.direction(at: site)
            if arc <= margin {
                XCTAssertEqual(direction, lead, "arc \(arc): inside the lead-in")
            } else if arc >= length - margin {
                XCTAssertEqual(direction, tail, "arc \(arc): inside the tail")
            } else {
                interior += 1
                XCTAssertEqual(direction, free.direction(at: site), "arc \(arc): between the anchors a dab reads the path")
            }
        }
        XCTAssertGreaterThan(interior, 200, "PREMISE: most of this stroke is interior")
    }

    /// **The scatter's frame is the direction sensor's reading, held ends included** — BRUSH.md §2.30's
    /// one-function rule, which holding the ends must not have broken.
    func testTheScatterFrameIsTheHeldDirection() {
        let raw = Self.straight(theta: -0.5, hook: 3)
        let samples = StrokeSamples(raw, channels: .captured)
        let path = StrokePath(points: samples.positions)
        let heading = path.heading(margin: 9)
        let sensors = StrokeSensors(samples: samples, path: path, random: DabRandom(seed: 7), brushSize: 36, heading: heading)
        let site = DabSite(parameter: path.domainEnd, arcWidths: path.arcLength(to: path.domainEnd) / 36)
        let direction = sensors.direction(at: site)
        XCTAssertEqual(sensors.value(of: .direction, at: site),
                       SampleChannel.wrappedAngle(atan2(direction.y, direction.x)) / (2 * .pi), accuracy: 1e-12)
        XCTAssertEqual(direction, heading.tail!.direction, "the last point of a hooked stroke reads the held tail")
        XCTAssertNotEqual(direction, path.tangent(at: path.domainEnd), "…which is not the hook the path itself ends in")
    }

    /// **Each end is held at its own margin, not at the stroke's overall direction.** A quarter circle
    /// of radius 60 turns 90°, so the lead-in's direction and the tail's differ by most of that — a
    /// walk that held both at one place would pass every straight-line test above. The right answers
    /// are known: the tangent of a circle `a` along it is `a / R` radians off where it started.
    func testACurvedStrokeHoldsEachEndAtItsOwnMargin() {
        let radius: CGFloat = 60
        let raw: [VectorSample] = (0...94).map { step in
            let phi = -CGFloat.pi / 2 + CGFloat(step) / radius
            return VectorSample(x: 100 + radius * cos(phi), y: 160 + radius * sin(phi), pressure: 0.5, deltaTime: 1 / 120)
        }
        let length = CGFloat(94)
        var brush = BrushLibrary.square
        brush.size = 36
        let margin = StrokeHeading.margin(brushSize: 36)
        let lead = margin / radius * 180 / .pi, tail = (length - margin) / radius * 180 / .pi
        XCTAssertGreaterThan(tail - lead, 40, "PREMISE: the two ends face well apart")
        for (walk, dabs) in [("live", liveDabs(raw, brush: brush)), ("replay", replayDabs(raw, brush: brush))] {
            let faced = headings(dabs, brush: brush)
            XCTAssertEqual(faced.first!, lead, accuracy: 3, "\(walk): the first dab faces the tangent a margin in")
            XCTAssertEqual(faced.last!, tail, accuracy: 3, "\(walk): the last dab faces the tangent a margin before the end")
        }
    }

    /// **The scatter about an end follows the held direction**, on both walks — BRUSH.md §2.30's
    /// one-function rule at the two call sites that stamp a dab. A brush that scatters *along* the
    /// stroke displaces each dab down its frame's tangent, so the displacement's direction is the frame
    /// itself: at the last dab of a hooked stroke it must lie along the held tail, and at the first dab
    /// of a wobbling one along the held lead, not along the hook and the wobble.
    func testTheScatterAboutAnEndFollowsTheHeldDirection() {
        var brush = BrushLibrary.square
        brush.size = 36
        var scattering = brush
        scattering.dab.scatterAlong = 0.6
        let theta: CGFloat = -0.5
        let raw = Self.straight(theta: theta, landing: 1.2, hook: 3)
        let along = CGPoint(x: cos(theta), y: sin(theta))
        for (walk, scattered, clean) in [("live", liveDabs(raw, brush: scattering), liveDabs(raw, brush: brush)),
                                          ("replay", replayDabs(raw, brush: scattering), replayDabs(raw, brush: brush))] {
            XCTAssertEqual(scattered.count, clean.count, walk)
            var measured = 0
            for index in [0, 1, 2, scattered.count - 3, scattered.count - 2, scattered.count - 1] {
                let offset = CGPoint(x: scattered[index].center.x - clean[index].center.x,
                                     y: scattered[index].center.y - clean[index].center.y)
                guard hypot(offset.x, offset.y) > 0.5 else { continue }
                measured += 1
                let sine = (offset.x * along.y - offset.y * along.x) / hypot(offset.x, offset.y)
                XCTAssertEqual(sine, 0, accuracy: sin(8 * .pi / 180),
                               "\(walk) dab \(index): its scatter lies along the stroke's held direction, not the hook's or the wobble's")
            }
            XCTAssertGreaterThanOrEqual(measured, 3, "\(walk) PREMISE: the scatter really displaced dabs at the ends")
        }
    }

    func testABrushReadsTheDirectionWhenItFollowsItOrARowIsDrivenByIt() {
        XCTAssertTrue(BrushLibrary.square.readsDirection, "direction-follow")
        XCTAssertFalse(BrushLibrary.roundHard.readsDirection)
        var row = BrushLibrary.roundHard
        row.modulations = BrushModulations([BrushModulation(.angle, .direction, amount: 1)])
        XCTAssertTrue(row.readsDirection, "a row driven by the direction reads it as much as direction-follow does")
    }

    // MARK: - The live walk's lag

    /// **A brush that reads the direction trails the pen by the margin and one input step, and no
    /// more** — which is the whole price of holding the tail, so it is bounded rather than described.
    func testTheLiveInkTrailsThePenByAtMostTheMarginAndAStep() {
        var brush = BrushLibrary.square
        brush.size = 36
        let margin = StrokeHeading.margin(brushSize: 36)
        let target = BrushStamper.CollectingDabTarget()
        var walk = BrushStamper.LiveWalk(seed: 7)
        let step: CGFloat = 2
        let spacing = BrushStamper.stampSpacing(brushSize: 36, fraction: brush.dab.spacing)
        var worstGap: CGFloat = 0
        for i in 0...100 {
            let pen = CGFloat(i) * step
            walk.stamp(to: VectorSample(x: 50 + pen, y: 80), into: target, brush: brush, color: .black, brushSize: 36)
            if let last = target.dabs.last { worstGap = max(worstGap, 50 + pen - last.center.x) }
        }
        XCTAssertLessThanOrEqual(worstGap, margin + step + spacing + 1e-9,
                                 "the ink is no further behind the pen than the margin, the last step and a spacing")
        XCTAssertGreaterThan(worstGap, margin - step, "PREMISE: the walk really waits, or this bounds nothing")
        walk.finish(into: target, brush: brush, color: .black, brushSize: 36)
        XCTAssertGreaterThanOrEqual(target.dabs.last!.center.x, 50 + 200 - spacing - 1e-9,
                                    "the lift lays down everything that was waiting")
    }

    /// **A brush that does not read the direction is laid down on arrival, as it always was.** Its
    /// ink is never further behind the pen than one spacing — there is no margin to wait for.
    func testABrushThatDoesNotReadTheDirectionIsLaidDownOnArrival() {
        let brush = BrushLibrary.roundHard
        XCTAssertFalse(brush.readsDirection)
        let target = BrushStamper.CollectingDabTarget()
        var walk = BrushStamper.LiveWalk(seed: 7)
        let spacing = BrushStamper.stampSpacing(brushSize: brush.size, fraction: brush.dab.spacing)
        for i in 0...40 {
            let pen = CGFloat(i) * 3
            walk.stamp(to: VectorSample(x: 50 + pen, y: 80), into: target, brush: brush, color: .black, brushSize: brush.size)
            guard let last = target.dabs.last else { continue }
            XCTAssertLessThanOrEqual(50 + pen - last.center.x, spacing + 1e-9, "sample \(i): nothing is held back")
        }
    }

    /// A tap is one dab facing `+x`, and a stroke too short to read a direction from is still drawn.
    func testATapAndAStrokeShorterThanTheMarginStillDraw() {
        let brush = BrushLibrary.square
        let tap = liveDabs([VectorSample(x: 60, y: 60)], brush: brush)
        XCTAssertEqual(tap.count, 1, "a tap stamps its one dab at the lift")
        XCTAssertEqual(headings(tap, brush: brush).first ?? 99, 0, accuracy: 1e-6, "…facing +x for want of a direction")

        let dash = [VectorSample(x: 60, y: 60), VectorSample(x: 62, y: 61), VectorSample(x: 64, y: 62)]
        for (name, dabs) in [("live", liveDabs(dash, brush: brush)), ("replay", replayDabs(dash, brush: brush))] {
            XCTAssertGreaterThan(dabs.count, 1, "\(name): a dash under the margin is still laid down")
            let turns = Set(headings(dabs, brush: brush).map { ($0 * 10).rounded() })
            XCTAssertEqual(turns.count, 1, "\(name): a stroke shorter than two margins faces one way throughout")
        }
        let still = [VectorSample(x: 60, y: 60), VectorSample(x: 60, y: 60), VectorSample(x: 60, y: 60)]
        XCTAssertFalse(liveDabs(still, brush: brush).isEmpty, "a pen that lands and does not move still stamps")
    }

    // MARK: - What it must not change

    /// **A cut piece keeps the whole stroke's ends.** `visibleRange` filters the original walk, so the
    /// heading is the whole stroke's and a piece cut out of the middle shows the dabs the uncut stroke
    /// had there — not dabs that have decided the cut is an end.
    func testACutPieceShowsTheDabsTheWholeStrokeHad() {
        let raw = Self.straight(theta: 0.2, landing: 1.0, hook: 2.5)
        let brush = Self.followers()[1].brush
        let samples = StrokeSamples(raw, channels: .captured)
        let whole = BrushStamper.bake(samples: samples, brush: brush, color: .black, brushSize: brush.size,
                                      brushOpacity: 1, random: DabRandom(seed: 7)).dabs
        let piece = BrushStamper.bake(samples: samples, brush: brush, color: .black, brushSize: brush.size,
                                      brushOpacity: 1, random: DabRandom(seed: 7), visibleRange: 20...40).dabs
        XCTAssertFalse(piece.isEmpty)
        XCTAssertLessThan(piece.count, whole.count)
        for dab in piece {
            XCTAssertTrue(whole.contains(dab), "a cut piece's dab is a dab of the uncut stroke, to the bit")
        }
    }

    /// **The same samples always walk to the same dabs** — the rest-space bake and the posed re-walk
    /// run this twice and compare.
    func testTheWalkIsDeterministic() {
        let raw = Self.straight(theta: -0.9, landing: 1.0, hook: 2.5)
        for (_, brush) in Self.followers() {
            XCTAssertEqual(replayDabs(raw, brush: brush), replayDabs(raw, brush: brush))
            XCTAssertEqual(liveDabs(raw, brush: brush), liveDabs(raw, brush: brush))
        }
    }

    /// A clean straight stroke has nothing at its ends to hold, so holding them changes no dab.
    func testACleanStraightStrokeIsUnchangedByHoldingItsEnds() {
        let raw = Self.straight(theta: 0.7)
        for (name, brush) in Self.followers() {
            let held = headings(replayDabs(raw, brush: brush), brush: brush)
            let free = unheldHeadings(raw, brush: brush)
            XCTAssertEqual(held.count, free.count, name)
            for (a, b) in zip(held, free) {
                XCTAssertEqual(Self.wrapped(a - b), 0, accuracy: 0.5, "\(name): a clean line has nothing at its ends to hold")
            }
        }
    }
}
