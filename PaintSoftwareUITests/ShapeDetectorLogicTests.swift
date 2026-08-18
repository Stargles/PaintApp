import XCTest
import CoreGraphics

/// Pure-logic tests for smart-shape detection and stroke collapsing — no `XCUIApplication`, no
/// simulator gestures, so they run in milliseconds and exercise exactly the math the app bakes
/// shapes with.
///
/// `ShapeGeometry.swift` and `ShapeDetector.swift` are compiled into this target as well as the app
/// (see the project file's "Engine sources shared with PaintSoftwareUITests" group) — the same
/// arrangement `BrushEngineLogicTests` uses, and the reason both files are deliberately kept free of
/// any dependency beyond CoreGraphics.
final class ShapeDetectorLogicTests: XCTestCase {

    // MARK: - Helpers

    private func samples(_ points: [CGPoint], pressure: CGFloat = 0.5) -> [VectorSample] {
        points.map { VectorSample(x: $0.x, y: $0.y, pressure: pressure) }
    }

    /// A freehand-ish circle traced `coverage` of the way around.
    ///
    /// The last point lands exactly at the end of the sweep, so `coverage: 1.0` closes the loop
    /// rather than stopping one step short. The old divisor was `count`, which traced 47/48 of the
    /// way round for a "full" circle — invisible while nothing measured how much of a shape was
    /// drawn, and the difference between a circle and a circle with an 11.8 pt gap now that
    /// something does. Measured: the old helper reports |spanSweep| 0.9792 at `coverage: 1.0`, this
    /// one reports 1.0000.
    private func circlePoints(center: CGPoint, radius: CGFloat, count: Int = 48,
                             coverage: CGFloat = 1.0) -> [CGPoint] {
        (0..<count).map { i in
            let angle = coverage * 2 * .pi * CGFloat(i) / CGFloat(count - 1)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    /// An arc of an ellipse traced through `sweep` turns of *eccentric* angle starting at
    /// `startTurn` turns — the same `u` the geometry speaks, so a test can ask for exactly the arc
    /// it means. A negative `sweep` draws it backwards. `circlePoints` can express none of the
    /// three: no start phase, no direction, no aspect ratio.
    ///
    /// Written as an explicit loop with annotated types, per the Swift 6.3 solver note on
    /// `largestGap` above.
    private func ellipseArcPoints(center: CGPoint, a: CGFloat, b: CGFloat, rotation: CGFloat = 0,
                                  startTurn: CGFloat = 0, sweep: CGFloat = 1,
                                  count: Int = 48) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let u: CGFloat = startTurn + sweep * CGFloat(i) / CGFloat(count - 1)
            let t: CGFloat = u * 2 * .pi - .pi
            let localX: CGFloat = a * cos(t), localY: CGFloat = b * sin(t)
            result.append(CGPoint(x: center.x + localX * cos(rotation) - localY * sin(rotation),
                                  y: center.y + localX * sin(rotation) + localY * cos(rotation)))
        }
        return result
    }

    private func rectPoints(_ rect: CGRect, perSide: Int = 12) -> [CGPoint] {
        var result: [CGPoint] = []
        for i in 0..<perSide {
            let t = CGFloat(i) / CGFloat(perSide)
            result.append(CGPoint(x: rect.minX + rect.width * t, y: rect.minY))
        }
        for i in 0..<perSide {
            let t = CGFloat(i) / CGFloat(perSide)
            result.append(CGPoint(x: rect.maxX, y: rect.minY + rect.height * t))
        }
        for i in 0..<perSide {
            let t = CGFloat(i) / CGFloat(perSide)
            result.append(CGPoint(x: rect.maxX - rect.width * t, y: rect.maxY))
        }
        for i in 0..<perSide {
            let t = CGFloat(i) / CGFloat(perSide)
            result.append(CGPoint(x: rect.minX, y: rect.maxY - rect.height * t))
        }
        return result
    }

    /// Largest gap between consecutive collapsed samples — the metric that catches a seam or a
    /// chord cutting across the shape.
    /// Spelled as a loop rather than `map { hypot(…) }.max() ?? 0`: `hypot`'s four overloads inside
    /// a closure whose result type the `??` still has to pin down is one of the expressions Swift
    /// 6.3's solver gives up on outright ("unable to type-check in reasonable time"), which fails the
    /// whole test target's build. Same arithmetic, no inference to do.
    private func largestGap(_ samples: [VectorSample]) -> CGFloat {
        guard samples.count >= 2 else { return 0 }
        var largest: CGFloat = 0
        for index in 1..<samples.count {
            let dx: CGFloat = samples[index].x - samples[index - 1].x
            let dy: CGFloat = samples[index].y - samples[index - 1].y
            largest = max(largest, hypot(dx, dy))
        }
        return largest
    }

    // MARK: - Detection

    func testDetectsStraightLine() {
        let points = (0...20).map { CGPoint(x: CGFloat($0) * 10, y: 100) }
        let shape = ShapeDetector.detect(from: points)
        XCTAssertEqual(shape?.kind, .line)
    }

    func testDetectsRectangle() {
        let points = rectPoints(CGRect(x: 50, y: 60, width: 200, height: 140))
        XCTAssertEqual(ShapeDetector.detect(from: points)?.kind, .rectangle)
    }

    func testDetectsCircleAsOval() {
        let points = circlePoints(center: CGPoint(x: 200, y: 200), radius: 90)
        XCTAssertEqual(ShapeDetector.detect(from: points)?.kind, .oval)
    }

    func testRejectsShortScribble() {
        // Under `minimumPathLength` — a stray tap shouldn't turn into a shape.
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 2), CGPoint(x: 6, y: 1)]
        XCTAssertNil(ShapeDetector.detect(from: points))
    }

    // `testRejectsPartialArc` used to sit here, asserting that a 90° arc is not an oval because it
    // "has nowhere near the outline coverage an oval needs". The owner reversed exactly that:
    // "Whatever the user draws that follows an oval path whether partial or full spawns in that
    // oval, and the stroke is then projected onto that oval." A quarter arc is now a quarter of an
    // oval, and `testQuarterOvalDetectsAsAnOvalWithAQuarterSpan` below is the same input with the
    // opposite expectation.

    /// The reported bug: "rectangle detection does not work at all, everything becomes an ellipse."
    ///
    /// A square is the worst case for it. Its covariance matrix is isotropic, so the principal axis
    /// the old detector fitted rect and oval inside was pure noise — often ~45°, where a square sits
    /// in a diamond-shaped box it fits nothing of, leaving the oval to win by default.
    func testDetectsSquareAsRectangleNotOval() {
        for side in [80, 150, 260] as [CGFloat] {
            let points = rectPoints(CGRect(x: 60, y: 60, width: side, height: side), perSide: 16)
            XCTAssertEqual(ShapeDetector.detect(from: points)?.kind, .rectangle,
                           "a \(side)pt square should detect as a rectangle")
        }
    }

    /// The same square, drawn at every angle. The rotation sweep has no degenerate orientation, so
    /// none of these may fall through to the oval.
    func testDetectsSquareAtEveryAngleAsRectangle() {
        let center = CGPoint(x: 200, y: 200)
        for degrees in stride(from: 0, through: 85, by: 5) {
            let angle = CGFloat(degrees) * .pi / 180
            let points = rectPoints(CGRect(x: 110, y: 110, width: 180, height: 180), perSide: 16)
                .map { p -> CGPoint in
                    let dx = p.x - center.x, dy = p.y - center.y
                    return CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle),
                                   y: center.y + dx * sin(angle) + dy * cos(angle))
                }
            XCTAssertEqual(ShapeDetector.detect(from: points)?.kind, .rectangle,
                           "a square drawn at \(degrees)° should detect as a rectangle")
        }
    }

    /// Circles must still win against the rectangle fit at every angle — the sweep made the two
    /// candidates directly comparable, which only helps if it didn't just flip the old bias around.
    func testDetectsEllipsesAsOvalsNotRectangles() {
        let center = CGPoint(x: 220, y: 220)
        for (a, b) in [(90, 90), (120, 70), (150, 40)] as [(CGFloat, CGFloat)] {
            for degrees in stride(from: 0, through: 75, by: 15) {
                let angle = CGFloat(degrees) * .pi / 180
                let points = (0..<56).map { i -> CGPoint in
                    let t = 2 * CGFloat.pi * CGFloat(i) / 56
                    let x = a * cos(t), y = b * sin(t)
                    return CGPoint(x: center.x + x * cos(angle) - y * sin(angle),
                                   y: center.y + x * sin(angle) + y * cos(angle))
                }
                XCTAssertEqual(ShapeDetector.detect(from: points)?.kind, .oval,
                               "a \(a)×\(b) ellipse at \(degrees)° should detect as an oval")
            }
        }
    }

    /// The hold gesture parks the pen for 0.8s before detection fires, which piles hundreds of
    /// samples onto one point. Every metric here is computed on arc-length-resampled points for
    /// exactly this reason — weighted by raw sample count, that pile drags the fit toward wherever
    /// the stroke happened to end.
    func testHoldTailOfPiledUpSamplesDoesNotSkewDetection() {
        let drawn = rectPoints(CGRect(x: 60, y: 80, width: 200, height: 160), perSide: 16)
        let parked = (0..<300).map { i -> CGPoint in
            // Sub-pixel tremor around the last point, as a Pencil held still reports.
            let wobble = CGFloat((i % 7)) * 0.1 - 0.3
            return CGPoint(x: drawn.last!.x + wobble, y: drawn.last!.y - wobble)
        }
        guard let shape = ShapeDetector.detect(from: drawn + parked) else {
            XCTFail("the held stroke should still detect")
            return
        }
        XCTAssertEqual(shape.kind, .rectangle)
        XCTAssertEqual(shape.boundingRect.width, 200, accuracy: 2)
        XCTAssertEqual(shape.boundingRect.height, 160, accuracy: 2)
    }

    /// A stroke zigzagging between the top and bottom of a box has every point sitting exactly on
    /// the box outline and covers all of it, so fit error and coverage both say "rectangle". Its
    /// arc length is what gives it away: tracing an outline costs about the outline's own length.
    func testRejectsZigzagThatFillsARectangularBox() {
        let points = (0..<40).map { i in
            CGPoint(x: CGFloat(i) * 10, y: i % 2 == 0 ? 100 : 160)
        }
        XCTAssertNil(ShapeDetector.detect(from: points))
    }

    /// **This one's margin moved, and it is the number to watch.** Against the old bounding-box oval
    /// fit the scribble scored ~0.21 — over `closedFitErrorMax` 0.16, so the fit-error gate rejected
    /// it outright. The conic fit scores it **0.1399**, which is *inside* that gate, so it now
    /// survives to the length gate and is rejected there instead: arc length 11957 against a span
    /// length of 383, a ratio of 31.2 where 1.75 is the ceiling. Two independent rejections became
    /// one. If that 0.1399 ever creeps over 0.16 the fix is to tighten the *length* gate, not the
    /// error gate — the error gate's calibration is what keeps rectangles working.
    func testRejectsRandomScribble() {
        // A deterministic, non-repeating wander that stays inside one region.
        let points = (0..<80).map { i -> CGPoint in
            let t = CGFloat(i)
            return CGPoint(x: 200 + 90 * sin(t * 1.7), y: 200 + 90 * cos(t * 2.9))
        }
        XCTAssertNil(ShapeDetector.detect(from: points))
    }

    /// A detected line's `startPoint` is the end the stroke started from. The overlay's two endpoint
    /// handles are identified by that ordering, so getting it backwards means the handle the user
    /// grabs and the end that moves are on opposite sides of the line.
    func testDetectedLineKeepsTheDirectionItWasDrawn() {
        let rightwards = ShapeDetector.detect(from: (0...20).map { CGPoint(x: 100 + CGFloat($0) * 10, y: 140) })
        XCTAssertEqual(rightwards?.kind, .line)
        XCTAssertEqual(rightwards?.startPoint.x ?? -1, 100, accuracy: 1)
        XCTAssertEqual(rightwards?.endPoint.x ?? -1, 300, accuracy: 1)

        let leftwards = ShapeDetector.detect(from: (0...20).map { CGPoint(x: 300 - CGFloat($0) * 10, y: 140) })
        XCTAssertEqual(leftwards?.kind, .line)
        XCTAssertEqual(leftwards?.startPoint.x ?? -1, 300, accuracy: 1)
        XCTAssertEqual(leftwards?.endPoint.x ?? -1, 100, accuracy: 1)
    }

    /// Elongated rectangles must not be handed to the line detector. The old detector rejected any
    /// box past 3:1 outright, which is well within what people actually draw.
    func testDetectsElongatedRectangles() {
        XCTAssertEqual(ShapeDetector.detect(from: rectPoints(CGRect(x: 20, y: 100, width: 400, height: 90)))?.kind,
                       .rectangle)
        XCTAssertEqual(ShapeDetector.detect(from: rectPoints(CGRect(x: 100, y: 20, width: 80, height: 340)))?.kind,
                       .rectangle)
    }

    /// A line with real freehand wobble stays a line rather than becoming the thin rectangle its
    /// bounding box describes.
    func testWobblyLineStaysALine() {
        let points = (0...40).map { i -> CGPoint in
            let t = CGFloat(i)
            return CGPoint(x: t * 9, y: 200 + 5 * sin(t * 0.8))
        }
        XCTAssertEqual(ShapeDetector.detect(from: points)?.kind, .line)
    }

    // MARK: - Resampling

    func testResamplingSpacesPointsEvenlyAlongThePath() {
        // Deliberately lopsided input: dense at the start, one long jump at the end.
        let dense = (0...20).map { CGPoint(x: CGFloat($0), y: 0) }
        let sparse = [CGPoint(x: 220, y: 0)]
        let resampled = ShapeDetector.resampled(dense + sparse, count: 24)

        XCTAssertEqual(resampled.count, 24)
        XCTAssertEqual(resampled.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(resampled.last?.x ?? -1, 220, accuracy: 0.001)
        let gaps = (1..<resampled.count).map { resampled[$0].x - resampled[$0 - 1].x }
        XCTAssertEqual(gaps.min() ?? 0, gaps.max() ?? 0, accuracy: 0.001,
                       "resampled points should be evenly spaced regardless of input density")
    }

    // MARK: - Outline parameterisation

    func testOutlineParameterInvertsPointOnOutline() {
        let shapes = [
            ShapeGeometry(kind: .line, startPoint: CGPoint(x: 10, y: 20), endPoint: CGPoint(x: 200, y: 90)),
            ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 30, y: 40), endPoint: CGPoint(x: 230, y: 180)),
            ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 30, y: 40), endPoint: CGPoint(x: 230, y: 180)),
        ]
        for shape in shapes {
            for step in 0...10 {
                let u = CGFloat(step) / 10
                let point = shape.pointOnOutline(at: u)
                let roundTripped = shape.outlineParameter(of: point)
                // The closed shapes' seam is the one place u = 0 and u = 1 name the same point,
                // so accept either end there.
                let error = shape.isClosed
                    ? min(abs(roundTripped - u), abs(abs(roundTripped - u) - 1))
                    : abs(roundTripped - u)
                XCTAssertLessThan(error, 0.02, "\(shape.kind) round-trip failed at u = \(u)")
            }
        }
    }

    // MARK: - Collapsing

    func testCollapsedLineLandsExactlyOnTheLine() {
        let shape = ShapeGeometry(kind: .line, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 300, y: 0))
        // A wobbly freehand line: every sample is off the ideal line by up to 8pt.
        let wobbly = samples((0...30).map { CGPoint(x: CGFloat($0) * 10, y: $0 % 2 == 0 ? 8 : -8) })
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: wobbly, shape: shape, spacing: 4)

        XCTAssertFalse(collapsed.isEmpty)
        for sample in collapsed {
            XCTAssertEqual(sample.y, 0, accuracy: 0.001, "collapsed sample left the line")
            XCTAssertTrue((0...300).contains(sample.x), "collapsed sample left the segment")
        }
        XCTAssertEqual(collapsed.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(collapsed.last?.x ?? -1, 300, accuracy: 0.001)
    }

    func testCollapsedOvalClosesItsSeam() {
        // The bug this guards: projecting samples onto the outline and re-sorting them leaves the
        // start and end at opposite ends of the array, so the stroke never closes and the renderer
        // draws a chord straight across the shape.
        let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 200, y: 200))
        let drawn = samples(circlePoints(center: CGPoint(x: 100, y: 100), radius: 100, coverage: 0.92))
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: drawn, shape: shape, spacing: 5)

        let first = collapsed.first!, last = collapsed.last!
        XCTAssertEqual(hypot(last.x - first.x, last.y - first.y), 0, accuracy: 0.01,
                       "collapsed oval should start and end at the same point")
        XCTAssertLessThan(largestGap(collapsed), 10,
                          "a gap far wider than the spacing means a chord was drawn across the oval")
        // Every sample sits on the ellipse.
        for sample in collapsed {
            XCTAssertEqual(hypot(sample.x - 100, sample.y - 100), 100, accuracy: 0.5)
        }
    }

    func testCollapsedRectangleCoversAllFourEdges() {
        let rect = CGRect(x: 20, y: 30, width: 160, height: 120)
        let shape = ShapeGeometry(kind: .rectangle, startPoint: rect.origin,
                                  endPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        let drawn = samples(rectPoints(rect))
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: drawn, shape: shape, spacing: 4)

        var onTop = false, onBottom = false, onLeft = false, onRight = false
        for sample in collapsed {
            // Every point must be on the perimeter, not floating inside it.
            let onVerticalEdge = abs(sample.x - rect.minX) < 0.01 || abs(sample.x - rect.maxX) < 0.01
            let onHorizontalEdge = abs(sample.y - rect.minY) < 0.01 || abs(sample.y - rect.maxY) < 0.01
            XCTAssertTrue(onVerticalEdge || onHorizontalEdge, "collapsed sample left the perimeter")
            if abs(sample.y - rect.minY) < 0.01 { onTop = true }
            if abs(sample.y - rect.maxY) < 0.01 { onBottom = true }
            if abs(sample.x - rect.minX) < 0.01 { onLeft = true }
            if abs(sample.x - rect.maxX) < 0.01 { onRight = true }
        }
        XCTAssertTrue(onTop && onBottom && onLeft && onRight, "an edge of the rectangle was never traced")
        XCTAssertLessThan(largestGap(collapsed), 10, "the rectangle outline has a hole in it")
    }

    func testCollapsePreservesThePressureProfile() {
        // Pressure ramps 0 → 1 along the line; the collapsed stroke should ramp the same way
        // instead of flattening to a constant.
        let shape = ShapeGeometry(kind: .line, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0))
        let drawn = (0...20).map { i -> VectorSample in
            let t = CGFloat(i) / 20
            return VectorSample(x: t * 100, y: 0, pressure: t)
        }
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: drawn, shape: shape, spacing: 5)

        XCTAssertEqual(collapsed.first?.pressure ?? -1, 0, accuracy: 0.05)
        XCTAssertEqual(collapsed.last?.pressure ?? -1, 1, accuracy: 0.05)
        for i in 1..<collapsed.count {
            XCTAssertGreaterThanOrEqual(collapsed[i].pressure, collapsed[i - 1].pressure - 0.001,
                                        "pressure should rise monotonically, as drawn")
        }
    }

    func testCollapseWithNoSamplesStillTracesTheShape() {
        // The "detection fired before any samples were captured" path: geometry must still be
        // produced (previously a separate fallback that could silently emit nothing).
        let shape = ShapeGeometry(kind: .oval, startPoint: .zero, endPoint: CGPoint(x: 120, y: 120))
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: [], shape: shape, spacing: 4)
        XCTAssertGreaterThan(collapsed.count, 20)
        for sample in collapsed {
            XCTAssertEqual(sample.pressure, 0.5, accuracy: 0.001)
            XCTAssertEqual(hypot(sample.x - 60, sample.y - 60), 60, accuracy: 0.5)
        }
    }

    // MARK: - Rotation

    func testDetectsRotatedOvalWithMatchingRotation() {
        // An oval traced at 40° should detect as `.oval` with a rotation near 40°, not silently
        // fall back to an axis-aligned bounding box around the tilted points.
        let angle = 40 * CGFloat.pi / 180
        let center = CGPoint(x: 200, y: 200)
        let a: CGFloat = 100, b: CGFloat = 88 // semi-major/minor axes
        let points = (0..<64).map { i -> CGPoint in
            let t = 2 * CGFloat.pi * CGFloat(i) / 64
            let localX = a * cos(t), localY = b * sin(t)
            return CGPoint(x: center.x + localX * cos(angle) - localY * sin(angle),
                           y: center.y + localX * sin(angle) + localY * cos(angle))
        }
        guard let shape = ShapeDetector.detect(from: points) else {
            XCTFail("expected a detected shape")
            return
        }
        XCTAssertEqual(shape.kind, .oval)
        // The detector's angle is only defined up to a 180° flip (an ellipse's axis is symmetric),
        // so accept either the swept angle or its mirror.
        let normalized = shape.rotation.truncatingRemainder(dividingBy: .pi)
        let wrapped = normalized < 0 ? normalized + .pi : normalized
        let target = angle.truncatingRemainder(dividingBy: .pi)
        let diff = min(abs(wrapped - target), abs(wrapped - target - .pi), abs(wrapped - target + .pi))
        XCTAssertLessThan(diff, 0.1, "expected rotation near \(angle) but got \(shape.rotation)")
    }

    func testDetectsRotatedRectangleWithMatchingRotation() {
        let angle = 30 * CGFloat.pi / 180
        let center = CGPoint(x: 200, y: 200)
        let localRect = CGRect(x: -100, y: -60, width: 200, height: 120)
        let localPoints = rectPoints(localRect)
        let points = localPoints.map { p -> CGPoint in
            CGPoint(x: center.x + p.x * cos(angle) - p.y * sin(angle),
                    y: center.y + p.x * sin(angle) + p.y * cos(angle))
        }
        guard let shape = ShapeDetector.detect(from: points) else {
            XCTFail("expected a detected shape")
            return
        }
        XCTAssertEqual(shape.kind, .rectangle)
        let normalized = shape.rotation.truncatingRemainder(dividingBy: .pi)
        let wrapped = normalized < 0 ? normalized + .pi : normalized
        let target = angle.truncatingRemainder(dividingBy: .pi)
        let diff = min(abs(wrapped - target), abs(wrapped - target - .pi), abs(wrapped - target + .pi))
        XCTAssertLessThan(diff, 0.1, "expected rotation near \(angle) but got \(shape.rotation)")
    }

    func testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview() {
        // The bug this guards: the preview drew `rotatedCGPath` but the committed stroke was built
        // from the unrotated geometry, so rotating a shape and letting go moved it back.
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        var shape = ShapeGeometry(kind: .rectangle, startPoint: rect.origin,
                                  endPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        shape.rotation = .pi / 2
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: [], shape: shape, spacing: 4)

        // A 90°-rotated 200×100 rect about its own centre becomes a 100×200 rect there.
        let xs = collapsed.map(\.x), ys = collapsed.map(\.y)
        XCTAssertEqual(xs.max()! - xs.min()!, 100, accuracy: 1)
        XCTAssertEqual(ys.max()! - ys.min()!, 200, accuracy: 1)
        XCTAssertEqual((xs.max()! + xs.min()!) / 2, rect.midX, accuracy: 1)
        XCTAssertEqual((ys.max()! + ys.min()!) / 2, rect.midY, accuracy: 1)
    }

    // MARK: - Two-finger constraint

    func testConstrainedRectangleBecomesASquareAboutItsCentre() {
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 0, y: 0),
                                  endPoint: CGPoint(x: 200, y: 100))
        let square = shape.constrained.boundingRect
        XCTAssertEqual(square.width, square.height, accuracy: 0.001)
        XCTAssertEqual(square.width, 200, accuracy: 0.001)
        XCTAssertEqual(square.midX, 100, accuracy: 0.001)
        XCTAssertEqual(square.midY, 50, accuracy: 0.001)
    }

    func testConstrainedLineSnapsToFifteenDegreeIncrements() {
        // 20° should snap to 15°, keeping the same length and start point.
        let angle = 20 * CGFloat.pi / 180
        let shape = ShapeGeometry(kind: .line, startPoint: .zero,
                                  endPoint: CGPoint(x: 100 * cos(angle), y: 100 * sin(angle)))
        let snapped = shape.constrained
        let snappedAngle = atan2(snapped.endPoint.y, snapped.endPoint.x)
        XCTAssertEqual(snappedAngle, 15 * CGFloat.pi / 180, accuracy: 0.0001)
        XCTAssertEqual(hypot(snapped.endPoint.x, snapped.endPoint.y), 100, accuracy: 0.0001)
    }

    func testCollapseHonoursTheConstraintTheUserSaw() {
        // Committing must collapse onto the *constrained* geometry — previously the constraint was
        // display-only, so a snapped shape previewed square and baked oblong.
        let shape = ShapeGeometry(kind: .rectangle, startPoint: .zero, endPoint: CGPoint(x: 200, y: 100))
        let collapsed = ShapeDetector.collapseSamplesToShape(samples: [], shape: shape.constrained, spacing: 4)
        let xs = collapsed.map(\.x), ys = collapsed.map(\.y)
        XCTAssertEqual(xs.max()! - xs.min()!, ys.max()! - ys.min()!, accuracy: 1)
    }

    // MARK: - Handle-drag math
    //
    // This math used to live inside CanvasView's overlay callbacks, where nothing could reach it.
    // Sessions 48 and 49 both shipped bugs in it; these pin the two behaviours those fixes added.

    func testDraggingACornerAnchorsTheOppositeCorner() {
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 10, y: 20),
                                  endPoint: CGPoint(x: 110, y: 120))
        let dragged = shape.draggingCorner(.bottomRight, to: CGPoint(x: 160, y: 170), anchor: nil)
        // The top-left corner is the anchor and must not have moved.
        XCTAssertEqual(dragged.boundingRect.minX, 10, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.minY, 20, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.maxX, 160, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.maxY, 170, accuracy: 0.001)
        XCTAssertEqual(dragged.rotation, 0, accuracy: 0.001, "a corner drag resizes, it never rotates")
    }

    func testDraggingACornerPastTheAnchorFlipsRatherThanInverting() {
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 0, y: 0),
                                  endPoint: CGPoint(x: 100, y: 100))
        // Drag the bottom-right corner up past the anchored top-left one.
        let dragged = shape.draggingCorner(.bottomRight, to: CGPoint(x: -40, y: -30), anchor: nil)
        XCTAssertEqual(dragged.boundingRect.minX, -40, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.minY, -30, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.maxX, 0, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.maxY, 0, accuracy: 0.001)
        XCTAssertGreaterThan(dragged.boundingRect.width, 0, "the rect must stay well-formed")
    }

    /// Session 48: a rotated rectangle used to resize toward the wrong corner, because the touch
    /// point was applied to axis-aligned math without being mapped into the shape's own frame first.
    func testDraggingACornerOfARotatedShapeResizesInItsOwnFrame() {
        let rotation = CGFloat.pi / 4
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 0, y: 0),
                                  endPoint: CGPoint(x: 100, y: 100), rotation: rotation)
        // A touch on the *rotated* position of the shape's own bottom-right corner should leave the
        // geometry where it is — the point maps back onto exactly that corner in local space.
        let rotatedCorner = CGPoint(x: 100, y: 100).applying(shape.rotationTransform)
        let dragged = shape.draggingCorner(.bottomRight, to: rotatedCorner, anchor: nil)
        XCTAssertEqual(dragged.boundingRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.maxX, 100, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.maxY, 100, accuracy: 0.001)
        XCTAssertEqual(dragged.rotation, rotation, accuracy: 0.001)
    }

    /// Session 51, the owner's report: the oval "treats the center as the transformation origin
    /// instead of the opposite side node", and an axis drag also *turned* the shape because it wrote
    /// `rotation` from the touch's bearing. This replaces
    /// `testDraggingAnOvalAxisHandleSetsBothLengthAndRotation`, which asserted both of those.
    /// Session 51, and the assertion whose absence let the bug ship: the anchored corner must not
    /// move **on the canvas**.
    ///
    /// The three tests above all read `boundingRect`, which is the shape's *local*, unrotated frame —
    /// so they were satisfied by a corner drag that pinned a local coordinate while the corner
    /// itself slid across the glass. It does slide: `rotationTransform` pivots about a centre that a
    /// corner drag moves by half the drag delta, so a locally-fixed corner travels by
    /// (I − R(θ))·(C − C′) every frame, and because the next frame's touch is mapped back through a
    /// transform built from the new centre the error compounds — the owner's "weird movement".
    func testDraggingACornerHoldsTheOppositeCornerFixedOnTheCanvas() {
        let rotation: CGFloat = 0.7
        let shape = ShapeGeometry(kind: .rectangle, startPoint: .zero,
                                  endPoint: CGPoint(x: 100, y: 100), rotation: rotation)
        let anchor = shape.canvasAnchor(opposite: .bottomRight)
        let c = cos(rotation), s = sin(rotation)
        // Touches expressed as an offset from the anchor along the shape's own axes, so every one of
        // them stays on the same side of the anchor (crossing it is the flip case, tested separately).
        for local in [CGPoint(x: 150, y: 120), CGPoint(x: 60, y: 200),
                      CGPoint(x: 100, y: 100), CGPoint(x: 20, y: 30)] {
            let touch = CGPoint(x: anchor.x + local.x * c - local.y * s,
                                y: anchor.y + local.x * s + local.y * c)
            let dragged = shape.draggingCorner(.bottomRight, to: touch, anchor: anchor)

            let anchorAfter = dragged.canvasAnchor(opposite: .bottomRight)
            XCTAssertEqual(anchorAfter.x, anchor.x, accuracy: 0.001)
            XCTAssertEqual(anchorAfter.y, anchor.y, accuracy: 0.001)
            // ...and the dragged corner is under the finger, which is the other half of the contract.
            let draggedCorner = dragged.canvasAnchor(opposite: .topLeft)
            XCTAssertEqual(draggedCorner.x, touch.x, accuracy: 0.001)
            XCTAssertEqual(draggedCorner.y, touch.y, accuracy: 0.001)

            XCTAssertEqual(dragged.boundingRect.width, local.x, accuracy: 0.001)
            XCTAssertEqual(dragged.boundingRect.height, local.y, accuracy: 0.001)
            XCTAssertEqual(dragged.rotation, rotation, accuracy: 0.001,
                           "a corner drag resizes, it never rotates")
        }
    }

    /// Feeding the result back in, the way a real drag does frame after frame, must be stable — the
    /// compounding drift is what the owner actually felt, and one frame of it is too small to see.
    func testRepeatedCornerDragsWithALatchedAnchorDoNotDrift() {
        let rotation: CGFloat = 0.7
        var shape = ShapeGeometry(kind: .rectangle, startPoint: .zero,
                                  endPoint: CGPoint(x: 100, y: 100), rotation: rotation)
        let anchor = shape.canvasAnchor(opposite: .bottomRight)
        let c = cos(rotation), s = sin(rotation)
        for step in 1...40 {
            let local = CGPoint(x: 100 + CGFloat(step), y: 100 + CGFloat(step) * 0.5)
            let touch = CGPoint(x: anchor.x + local.x * c - local.y * s,
                                y: anchor.y + local.x * s + local.y * c)
            shape = shape.draggingCorner(.bottomRight, to: touch, anchor: anchor)
        }
        let anchorAfter = shape.canvasAnchor(opposite: .bottomRight)
        XCTAssertEqual(anchorAfter.x, anchor.x, accuracy: 0.001,
                       "40 frames of dragging must leave the anchor exactly where it started")
        XCTAssertEqual(anchorAfter.y, anchor.y, accuracy: 0.001)
        XCTAssertEqual(shape.boundingRect.width, 140, accuracy: 0.001)
        XCTAssertEqual(shape.boundingRect.height, 120, accuracy: 0.001)
    }

    /// The oval axis rule, stated as the owner stated it: "the opposite node across the elipse is
    /// anchored". Everything else falls out of that — with the anchor pinned and the dragged node on
    /// the touch, the segment between them *is* the axis, so its length is the extent and its
    /// direction is the rotation.
    ///
    /// This replaces two assertions an earlier revision made, in opposite directions and both wrong:
    /// that an axis drag never rotates (it must — the owner asked for it), and before that, that
    /// rotation comes from the finger's bearing *about the centre* while the resize also pivoted
    /// there (two pivots fighting over one drag — the "weird movement").
    func testDraggingAnOvalAxisHandleAnchorsTheOppositeNode() {
        // Centre (100, 100), half-axes 50 x 20 — so the left axis node is at (50, 100).
        let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 50, y: 80),
                                  endPoint: CGPoint(x: 150, y: 120))
        let leftNode = shape.canvasAnchor(opposite: .right)
        XCTAssertEqual(leftNode.x, 50, accuracy: 0.001)
        XCTAssertEqual(leftNode.y, 100, accuracy: 0.001)

        // Drag the right axis handle down and to the right of the centre.
        let touch = CGPoint(x: 100, y: 160)
        let dragged = shape.draggingEdge(.right, to: touch)
        let anchorAfter = dragged.canvasAnchor(opposite: .right)
        XCTAssertEqual(anchorAfter.x, 50, accuracy: 0.001, "the opposite node is what holds still")
        XCTAssertEqual(anchorAfter.y, 100, accuracy: 0.001)
        // ...and the dragged node is under the finger, which is the other half of the contract.
        let draggedNode = dragged.canvasAnchor(opposite: .left)
        XCTAssertEqual(draggedNode.x, touch.x, accuracy: 0.001)
        XCTAssertEqual(draggedNode.y, touch.y, accuracy: 0.001)
        // The axis spans anchor -> touch, so its length is that distance and its direction is that
        // bearing. (50,60) from the anchor: length 78.10, bearing atan2(60,50).
        XCTAssertEqual(dragged.boundingRect.width, hypot(50, 60), accuracy: 0.001,
                       "the axis is the whole anchor-to-touch segment")
        XCTAssertEqual(dragged.rotation, atan2(60, 50), accuracy: 0.001,
                       "and its direction is the shape's rotation")
        XCTAssertEqual(dragged.boundingRect.height / 2, 20, accuracy: 0.001, "perpendicular axis is untouched")
    }

    /// The same property on a rotated oval, which is where centre-anchoring was visibly wrong: the
    /// node the artist is watching has to stay put on the glass, not in the shape's local frame.
    func testDraggingARotatedOvalAxisHoldsItsAnchorOnTheCanvas() {
        let rotation: CGFloat = 0.6
        let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 50, y: 80),
                                  endPoint: CGPoint(x: 150, y: 120), rotation: rotation)
        let anchor = shape.canvasAnchor(opposite: .right)
        for target in [CGPoint(x: 200, y: 40), CGPoint(x: 130, y: 190), CGPoint(x: 90, y: 105)] {
            let dragged = shape.draggingEdge(.right, to: target, anchor: anchor)
            let after = dragged.canvasAnchor(opposite: .right)
            XCTAssertEqual(after.x, anchor.x, accuracy: 0.001)
            XCTAssertEqual(after.y, anchor.y, accuracy: 0.001)
            let node = dragged.canvasAnchor(opposite: .left)
            XCTAssertEqual(node.x, target.x, accuracy: 0.001)
            XCTAssertEqual(node.y, target.y, accuracy: 0.001)
            XCTAssertEqual(dragged.boundingRect.height, shape.boundingRect.height, accuracy: 0.001,
                           "the perpendicular half-axis is held whatever the touch's perpendicular offset")
        }
    }

    /// All four axis handles, at several rotations, dragged in every direction: the anchor holds and
    /// the dragged node lands on the touch. The four differ — `.left`/`.right` are the two ends of
    /// the local x axis and `.top`/`.bottom` of the local y axis — so a sign error in any one of the
    /// four `atan2` arguments shows up here and nowhere else.
    func testEveryOvalAxisHandleHoldsItsOppositeNode() {
        let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 50, y: 80),
                                  endPoint: CGPoint(x: 150, y: 120), rotation: 0.7)
        let edges: [ShapeGeometry.Edge] = [.top, .bottom, .left, .right]
        let opposites: [ShapeGeometry.Edge: ShapeGeometry.Edge] =
            [.top: .bottom, .bottom: .top, .left: .right, .right: .left]
        for edge in edges {
            let anchor = shape.canvasAnchor(opposite: edge)
            let perpendicularBefore = (edge == .left || edge == .right)
                ? shape.boundingRect.height : shape.boundingRect.width
            for step in 0..<8 {
                let bearing = CGFloat(step) * .pi / 4 + 0.13
                let touch = CGPoint(x: anchor.x + cos(bearing) * 90, y: anchor.y + sin(bearing) * 90)
                let dragged = shape.draggingEdge(edge, to: touch, anchor: anchor)

                let held = dragged.canvasAnchor(opposite: edge)
                XCTAssertEqual(held.x, anchor.x, accuracy: 0.001, "\(edge) anchor moved")
                XCTAssertEqual(held.y, anchor.y, accuracy: 0.001, "\(edge) anchor moved")
                let node = dragged.canvasAnchor(opposite: opposites[edge]!)
                XCTAssertEqual(node.x, touch.x, accuracy: 0.001, "\(edge) node left the touch")
                XCTAssertEqual(node.y, touch.y, accuracy: 0.001, "\(edge) node left the touch")

                let axis = (edge == .left || edge == .right)
                    ? dragged.boundingRect.width : dragged.boundingRect.height
                XCTAssertEqual(axis, 90, accuracy: 0.001, "\(edge) axis is the anchor-to-touch distance")
                let perpendicular = (edge == .left || edge == .right)
                    ? dragged.boundingRect.height : dragged.boundingRect.width
                XCTAssertEqual(perpendicular, perpendicularBefore, accuracy: 0.001,
                               "\(edge) fattened the shape")
            }
        }
    }

    /// Dragging straight out along the axis the handle already lies on must not turn the shape — the
    /// pure stretch the owner already had, now a special case of the rule rather than the whole rule.
    /// Compared modulo π because an ellipse is symmetric under a half turn, so `.left` and `.right`
    /// describe the same drawing with rotations π apart.
    func testDraggingAnOvalAxisStraightOutDoesNotTurnIt() {
        for rotation in [CGFloat(0), 0.4, 1.1] {
            let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 50, y: 80),
                                      endPoint: CGPoint(x: 150, y: 120), rotation: rotation)
            for edge in [ShapeGeometry.Edge.top, .bottom, .left, .right] {
                let anchor = shape.canvasAnchor(opposite: edge)
                let opposites: [ShapeGeometry.Edge: ShapeGeometry.Edge] =
                    [.top: .bottom, .bottom: .top, .left: .right, .right: .left]
                let node = shape.canvasAnchor(opposite: opposites[edge]!)
                // Twice as far from the anchor, along the same line.
                let touch = CGPoint(x: anchor.x + (node.x - anchor.x) * 2,
                                    y: anchor.y + (node.y - anchor.y) * 2)
                let dragged = shape.draggingEdge(edge, to: touch, anchor: anchor)
                let delta = abs(dragged.rotation - rotation).truncatingRemainder(dividingBy: .pi)
                XCTAssertEqual(min(delta, .pi - delta), 0, accuracy: 0.001,
                               "\(edge) at \(rotation) turned on a straight pull")
                let axis = (edge == .left || edge == .right)
                    ? dragged.boundingRect.width : dragged.boundingRect.height
                let axisBefore = (edge == .left || edge == .right)
                    ? shape.boundingRect.width : shape.boundingRect.height
                XCTAssertEqual(axis, axisBefore * 2, accuracy: 0.001, "\(edge) did not double")
            }
        }
    }

    /// A drag that walks through its own anchor and out the far side. Unlike the rectangle's corner
    /// drag — where crossing mirrors the rect and the latched anchor becomes the dragged corner's
    /// *neighbour* — the oval's axis simply turns through the anchor, so both halves of the contract
    /// hold on every frame of the crossing.
    func testDraggingAnOvalAxisThroughItsAnchorKeepsBothEndsWhereTheyBelong() {
        let shape = ShapeGeometry(kind: .oval, startPoint: .zero,
                                  endPoint: CGPoint(x: 120, y: 60), rotation: 0.7)
        let anchor = shape.canvasAnchor(opposite: .right)
        let start = shape.canvasAnchor(opposite: .left)
        for step in 0...20 {
            let t = CGFloat(step) / 8   // 0 -> 2.5, i.e. through the anchor at t = 1
            let touch = CGPoint(x: start.x + (anchor.x - start.x) * t,
                                y: start.y + (anchor.y - start.y) * t)
            let dragged = shape.draggingEdge(.right, to: touch, anchor: anchor)
            let held = dragged.canvasAnchor(opposite: .right)
            XCTAssertEqual(held.x, anchor.x, accuracy: 0.001, "anchor moved at t=\(t)")
            XCTAssertEqual(held.y, anchor.y, accuracy: 0.001, "anchor moved at t=\(t)")
            let node = dragged.canvasAnchor(opposite: .left)
            XCTAssertEqual(node.x, touch.x, accuracy: 0.001, "node left the touch at t=\(t)")
            XCTAssertEqual(node.y, touch.y, accuracy: 0.001, "node left the touch at t=\(t)")
            XCTAssertGreaterThanOrEqual(dragged.boundingRect.width, 0, "rect must stay well-formed")
        }
    }

    /// Feeding the result back in the way a live drag does, on a curved path so rotation keeps
    /// moving. This is the oval twin of `testRepeatedCornerDragsWithALatchedAnchorDoNotDrift`, and it
    /// is the shape of failure the owner actually feels: one frame of drift is invisible, sixty is a
    /// shape sliding out from under the finger.
    func testRepeatedOvalAxisDragsWithALatchedAnchorDoNotDrift() {
        var shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 20, y: 40),
                                  endPoint: CGPoint(x: 140, y: 100), rotation: 0.7)
        let anchor = shape.canvasAnchor(opposite: .right)
        var touch = CGPoint.zero
        for frame in 1...60 {
            let angle = CGFloat(frame) * 0.05
            touch = CGPoint(x: anchor.x + cos(angle) * (40 + CGFloat(frame)),
                            y: anchor.y + sin(angle) * (40 + CGFloat(frame)))
            shape = shape.draggingEdge(.right, to: touch, anchor: anchor)
        }
        let held = shape.canvasAnchor(opposite: .right)
        XCTAssertEqual(held.x, anchor.x, accuracy: 0.001,
                       "60 frames of dragging must leave the anchor exactly where it started")
        XCTAssertEqual(held.y, anchor.y, accuracy: 0.001)
        let node = shape.canvasAnchor(opposite: .left)
        XCTAssertEqual(node.x, touch.x, accuracy: 0.001)
        XCTAssertEqual(node.y, touch.y, accuracy: 0.001)
    }

    /// A touch that lands exactly on the anchor has no direction to read a rotation from, so it
    /// collapses the axis and keeps the rotation the shape already had rather than snapping to an
    /// arbitrary angle. Reachable: a drag that passes through the anchor lands on it for one frame.
    func testAnOvalAxisDraggedOntoItsAnchorKeepsItsRotation() {
        let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 50, y: 80),
                                  endPoint: CGPoint(x: 150, y: 120), rotation: 0.9)
        let anchor = shape.canvasAnchor(opposite: .right)
        let dragged = shape.draggingEdge(.right, to: anchor, anchor: anchor)
        XCTAssertEqual(dragged.rotation, 0.9, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.width, 0, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.height, shape.boundingRect.height, accuracy: 0.001)
    }

    /// Rectangles get four corner handles and no mid-edge ones (`ShapeOverlayView.handleLayout`), so
    /// this branch is currently unreachable from the UI — it is kept and pinned because the handle
    /// set is a UI decision that could change back.
    func testDraggingARectangleEdgeMovesOnlyThatEdge() {
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 0, y: 0),
                                  endPoint: CGPoint(x: 100, y: 100))
        let dragged = shape.draggingEdge(.top, to: CGPoint(x: 999, y: 30))
        XCTAssertEqual(dragged.boundingRect.minY, 30, accuracy: 0.001, "top edge follows the touch's y")
        XCTAssertEqual(dragged.boundingRect.maxY, 100, accuracy: 0.001)
        XCTAssertEqual(dragged.boundingRect.minX, 0, accuracy: 0.001, "the touch's x is irrelevant to a top-edge drag")
        XCTAssertEqual(dragged.boundingRect.maxX, 100, accuracy: 0.001)
        XCTAssertEqual(dragged.rotation, 0, accuracy: 0.001)
    }

    // MARK: - The rectangle node rule, swept
    //
    // The owner, 2026-08-17, on the rectangle's corner handles: *"Basically, the rule is that the
    // opposite node to the one selected shouldn't move."* Everything below is that one sentence,
    // stated four ways — every rotation, every corner, every bearing, and drags taken clean through
    // the anchor and far out the other side.
    //
    // The five tests above this block reach one corner at one or two rotations each, which is how
    // `.topLeft`, `.topRight` and `.bottomLeft` went unswept and how the two failures the owner
    // reported survived a green suite. The sweep is cheap — pure `CGFloat` math, no simulator, no
    // allocation — so there is no reason for it to be narrow.
    //
    // The checks accumulate into a list rather than firing an `XCTAssert` each, because ~20k
    // individual assertions cost more to record than to compute; the count is asserted at the end so
    // a sweep that quietly stops sweeping fails instead of printing green (CLAUDE.md's rule, applied
    // to assertions rather than to test cases).

    /// The four corners of `shape` in **canvas** space — where the artist sees them, which is the
    /// frame the owner's rule is stated in. Order is TL, TR, BR, BL, i.e. walking the outline.
    private func canvasCorners(of shape: ShapeGeometry) -> [CGPoint] {
        let r = shape.boundingRect, t = shape.rotationTransform
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)].map { $0.applying(t) }
    }

    /// How far `point` is from the nearest corner of `shape`, in canvas space.
    ///
    /// Deliberately *not* `canvasAnchor(opposite:)`: once a drag crosses over, the corner labels
    /// rotate around the rectangle, so asking for a named corner asks the wrong question. "Is the
    /// anchored node still a corner of this shape, where it was?" is the question the owner's rule
    /// actually poses, and it is label-free.
    private func distanceToNearestCorner(of shape: ShapeGeometry, from point: CGPoint) -> CGFloat {
        canvasCorners(of: shape).map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .infinity
    }

    /// Rotations the sweeps run at: flat, barely-off-flat (where the old local-frame math first goes
    /// wrong), the diagonal, both right angles, a straight half turn, and negatives — the owner asked
    /// for a rotatable rectangle, so there is no privileged angle.
    private static let sweptRotations: [CGFloat] =
        [0, 0.01, 0.3, .pi / 4, .pi / 2, 3 * .pi / 4, .pi, -0.4, -.pi / 3, -2.0, 5.9]

    private static let allCorners: [ShapeGeometry.Corner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    /// The rule itself: for every rotation, every corner, every bearing and every distance — including
    /// ones that overshoot the far edge by six diagonals — the diametrically opposite node is exactly
    /// where it was, and the dragged node is exactly under the finger.
    ///
    /// Also asserts the result is still a *rectangle*: opposite sides equal and parallel as vectors,
    /// adjacent sides perpendicular. A drag that satisfied the anchor rule by shearing the shape would
    /// pass every other assertion here.
    func testEveryRectangleCornerHoldsItsOppositeNodeAtEveryRotation() {
        var failures: [String] = []
        var checks = 0
        for rotation in Self.sweptRotations {
            for corner in Self.allCorners {
                let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 20, y: 35),
                                          endPoint: CGPoint(x: 140, y: 115), rotation: rotation)
                let anchor = shape.canvasAnchor(opposite: corner)
                let diagonal = hypot(shape.boundingRect.width, shape.boundingRect.height)
                for step in 0..<16 {
                    let bearing = CGFloat(step) * .pi / 8 + 0.07
                    for distance in [CGFloat(5), 60, diagonal, diagonal * 6] {
                        let touch = CGPoint(x: anchor.x + cos(bearing) * distance,
                                            y: anchor.y + sin(bearing) * distance)
                        let dragged = shape.draggingCorner(corner, to: touch, anchor: anchor)
                        let where_ = "rot \(rotation) \(corner) bearing \(step) dist \(distance)"

                        checks += 1
                        let anchorTravel = distanceToNearestCorner(of: dragged, from: anchor)
                        if anchorTravel > 0.001 { failures.append("anchor moved \(anchorTravel) pt — \(where_)") }

                        checks += 1
                        let fingerGap = distanceToNearestCorner(of: dragged, from: touch)
                        if fingerGap > 0.001 { failures.append("node left the finger by \(fingerGap) pt — \(where_)") }

                        checks += 1
                        if abs(dragged.rotation - rotation) > 0.001 {
                            failures.append("a corner drag turned the shape — \(where_)")
                        }

                        // Still a rectangle.
                        let c = canvasCorners(of: dragged)
                        let top = CGPoint(x: c[1].x - c[0].x, y: c[1].y - c[0].y)
                        let bottom = CGPoint(x: c[2].x - c[3].x, y: c[2].y - c[3].y)
                        let left = CGPoint(x: c[3].x - c[0].x, y: c[3].y - c[0].y)
                        let right = CGPoint(x: c[2].x - c[1].x, y: c[2].y - c[1].y)
                        checks += 1
                        if abs(top.x - bottom.x) > 0.001 || abs(top.y - bottom.y) > 0.001 {
                            failures.append("top and bottom are no longer equal and parallel — \(where_)")
                        }
                        checks += 1
                        if abs(left.x - right.x) > 0.001 || abs(left.y - right.y) > 0.001 {
                            failures.append("left and right are no longer equal and parallel — \(where_)")
                        }
                        checks += 1
                        // Scale-relative, so a 6-diagonal drag isn't judged on an absolute dot product.
                        let scale = max(1, hypot(top.x, top.y) * hypot(left.x, left.y))
                        if abs(top.x * left.x + top.y * left.y) / scale > 0.001 {
                            failures.append("corner is no longer square — \(where_)")
                        }

                        // The anchor→touch segment is the rectangle's own diagonal, which is what
                        // "these two are the opposite ends of it" means numerically.
                        checks += 1
                        let segment = hypot(touch.x - anchor.x, touch.y - anchor.y)
                        let ownDiagonal = hypot(dragged.boundingRect.width, dragged.boundingRect.height)
                        if abs(segment - ownDiagonal) > 0.001 {
                            failures.append("diagonal \(ownDiagonal) is not the anchor-to-touch \(segment) — \(where_)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(failures.count, 0, "\(failures.count) of \(checks): \(failures.prefix(5).joined(separator: " | "))")
        XCTAssertEqual(checks, 11 * 4 * 16 * 4 * 7, "the sweep stopped sweeping")
    }

    /// The owner's second sentence: *"when I move the node past the other edge of the rectangle, the
    /// intended behaviour is the rectangle still works, just in the other quadrants."* Walked frame by
    /// frame from the dragged corner, straight through the anchor, to three times past it — the anchor
    /// holds on every frame, including the one where the rectangle is exactly zero-sized.
    func testDraggingARectangleCornerCleanThroughItsAnchorHoldsTheOppositeNode() {
        var failures: [String] = []
        var checks = 0
        for rotation in Self.sweptRotations {
            for corner in Self.allCorners {
                let shape = ShapeGeometry(kind: .rectangle, startPoint: .zero,
                                          endPoint: CGPoint(x: 120, y: 70), rotation: rotation)
                let anchor = shape.canvasAnchor(opposite: corner)
                // The dragged corner is the one furthest from the anchor — its diagonal opposite.
                let start = canvasCorners(of: shape).max(by: {
                    hypot($0.x - anchor.x, $0.y - anchor.y) < hypot($1.x - anchor.x, $1.y - anchor.y) })!
                for step in 0...24 {
                    let t = CGFloat(step) / 6      // crosses the anchor at t = 1, ends three times past
                    let touch = CGPoint(x: start.x + (anchor.x - start.x) * t,
                                        y: start.y + (anchor.y - start.y) * t)
                    let dragged = shape.draggingCorner(corner, to: touch, anchor: anchor)
                    let where_ = "rot \(rotation) \(corner) t=\(t)"

                    checks += 1
                    let travel = distanceToNearestCorner(of: dragged, from: anchor)
                    if travel > 0.001 { failures.append("anchor moved \(travel) pt crossing — \(where_)") }

                    checks += 1
                    if distanceToNearestCorner(of: dragged, from: touch) > 0.001 {
                        failures.append("node left the finger crossing — \(where_)")
                    }

                    checks += 1
                    if dragged.boundingRect.width < 0 || dragged.boundingRect.height < 0 {
                        failures.append("rect inverted rather than flipping — \(where_)")
                    }
                }
            }
        }
        XCTAssertEqual(failures.count, 0, "\(failures.count) of \(checks): \(failures.prefix(5).joined(separator: " | "))")
        XCTAssertEqual(checks, 11 * 4 * 25 * 3, "the sweep stopped sweeping")
    }

    /// Sixty frames of a curved drag fed back in the way a live one is. One frame of drift is
    /// invisible and sixty is a rectangle sliding out from under the finger — this is the shape of
    /// failure the owner actually feels, and the flat case cannot show it at all.
    func testSixtyFrameRectangleCornerDragsDoNotDriftAtAnyRotation() {
        var failures: [String] = []
        var checks = 0
        for rotation in Self.sweptRotations {
            for corner in Self.allCorners {
                var shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 10, y: 10),
                                          endPoint: CGPoint(x: 110, y: 90), rotation: rotation)
                let anchor = shape.canvasAnchor(opposite: corner)
                var touch = CGPoint.zero
                for frame in 1...60 {
                    let bearing = CGFloat(frame) * 0.11    // sweeps right around, so it crosses over
                    touch = CGPoint(x: anchor.x + cos(bearing) * (20 + CGFloat(frame) * 2.5),
                                    y: anchor.y + sin(bearing) * (20 + CGFloat(frame) * 2.5))
                    shape = shape.draggingCorner(corner, to: touch, anchor: anchor)
                }
                let where_ = "rot \(rotation) \(corner)"
                checks += 1
                let travel = distanceToNearestCorner(of: shape, from: anchor)
                if travel > 0.001 { failures.append("60 frames drifted the anchor \(travel) pt — \(where_)") }
                checks += 1
                if distanceToNearestCorner(of: shape, from: touch) > 0.001 {
                    failures.append("60 frames lost the finger — \(where_)")
                }
                checks += 1
                if abs(shape.rotation - rotation) > 0.001 { failures.append("60 frames turned it — \(where_)") }
            }
        }
        XCTAssertEqual(failures.count, 0, "\(failures.count) of \(checks): \(failures.prefix(5).joined(separator: " | "))")
        XCTAssertEqual(checks, 11 * 4 * 3, "the sweep stopped sweeping")
    }

    /// The failure the missing latch produces, pinned as a *characterisation* rather than a wish — it
    /// is why `draggingCorner`'s `anchor` lost its default value.
    ///
    /// This is the owner's "right now it pushes the opposite edge", reproduced exactly: past the
    /// crossing, re-deriving the anchor each frame returns the corner under the finger instead of the
    /// pinned one, so the rectangle freezes at one frame's width and marches along behind the touch.
    /// Flat and un-crossed it is indistinguishable from the correct path, which is precisely why the
    /// bug reads as "works fine when the rectangle is flat".
    func testACornerDragWithoutALatchedAnchorWalksTheOppositeEdge() {
        func run(latched: Bool) -> (travel: CGFloat, width: CGFloat) {
            var shape = ShapeGeometry(kind: .rectangle, startPoint: .zero,
                                      endPoint: CGPoint(x: 100, y: 100))
            let anchor = shape.canvasAnchor(opposite: .bottomRight)
            for frame in 1...20 {
                // Straight left along y = 100, from 100 pt right of the anchor to 140 pt past it.
                let touch = CGPoint(x: anchor.x + 100 - CGFloat(frame) * 12, y: anchor.y + 100)
                shape = shape.draggingCorner(.bottomRight, to: touch, anchor: latched ? anchor : nil)
            }
            return (distanceToNearestCorner(of: shape, from: anchor), shape.boundingRect.width)
        }

        let good = run(latched: true)
        XCTAssertEqual(good.travel, 0, accuracy: 0.001, "the latched anchor is the whole fix")
        XCTAssertEqual(good.width, 140, accuracy: 0.001,
                       "past the crossing the rectangle keeps growing into the other quadrant")

        let bad = run(latched: false)
        XCTAssertEqual(bad.travel, 128, accuracy: 0.001,
                       "unlatched, the node that must not move ends up 128 pt away")
        XCTAssertEqual(bad.width, 12, accuracy: 0.001,
                       "and the rectangle is frozen at one frame's width, marching after the finger")
    }

    // MARK: - Follow-the-finger math

    func testFollowingTheFingerFromItsOwnStartPointChangesNothing() {
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 0, y: 0),
                                  endPoint: CGPoint(x: 100, y: 60), rotation: 0.3)
        let start = CGPoint(x: 90, y: 10)
        let frame = shape.followFrame(startingAt: start)
        let unmoved = shape.following(start, from: frame)
        XCTAssertEqual(unmoved.startPoint.x, shape.startPoint.x, accuracy: 0.001)
        XCTAssertEqual(unmoved.startPoint.y, shape.startPoint.y, accuracy: 0.001)
        XCTAssertEqual(unmoved.endPoint.x, shape.endPoint.x, accuracy: 0.001)
        XCTAssertEqual(unmoved.endPoint.y, shape.endPoint.y, accuracy: 0.001)
        XCTAssertEqual(unmoved.rotation, shape.rotation, accuracy: 0.001)
    }

    /// Session 49: the shape's already-detected rotation used to be *replaced* by the finger's own
    /// bearing, so an angled shape snapped back to axis-aligned on the first drag sample. The
    /// finger's bearing change has to be added on top of the shape's own rotation.
    func testFollowingAddsTheFingersBearingOnTopOfTheShapesOwnRotation() {
        let ownRotation: CGFloat = 0.5
        // Centre (0, 0) so the bearing maths is easy to state.
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: -50, y: -25),
                                  endPoint: CGPoint(x: 50, y: 25), rotation: ownRotation)
        let frame = shape.followFrame(startingAt: CGPoint(x: 100, y: 0))   // bearing 0
        let moved = shape.following(CGPoint(x: 0, y: 100), from: frame)     // bearing +pi/2
        XCTAssertEqual(moved.rotation, ownRotation + .pi / 2, accuracy: 0.001,
                       "the finger's +90 deg must add to the shape's own 0.5 rad, not replace it")
    }

    func testFollowingScalesUniformlyAboutTheShapesCentre() {
        let shape = ShapeGeometry(kind: .oval, startPoint: CGPoint(x: 0, y: 50),
                                  endPoint: CGPoint(x: 100, y: 150))   // centre (50, 100), half 50x50
        let frame = shape.followFrame(startingAt: CGPoint(x: 90, y: 100))   // radius 40
        let moved = shape.following(CGPoint(x: 130, y: 100), from: frame)   // radius 80 => scale 2
        XCTAssertEqual(moved.boundingRect.width, 200, accuracy: 0.001)
        XCTAssertEqual(moved.boundingRect.height, 200, accuracy: 0.001)
        XCTAssertEqual(moved.center.x, 50, accuracy: 0.001, "the centre is the anchor, not the finger")
        XCTAssertEqual(moved.center.y, 100, accuracy: 0.001)
    }

    func testFollowingFromTheExactCentreHoldsTheShapesSize() {
        // Capturing the frame with the finger on the centre gives radius 0; the scale must fall back
        // to 1 rather than dividing by zero.
        let shape = ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: 0, y: 0),
                                  endPoint: CGPoint(x: 100, y: 100))
        let frame = shape.followFrame(startingAt: CGPoint(x: 50, y: 50))
        let moved = shape.following(CGPoint(x: 90, y: 50), from: frame)
        XCTAssertEqual(moved.boundingRect.width, 100, accuracy: 0.001)
        XCTAssertEqual(moved.boundingRect.height, 100, accuracy: 0.001)
    }
}
