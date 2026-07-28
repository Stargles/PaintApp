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
    private func circlePoints(center: CGPoint, radius: CGFloat, count: Int = 48,
                             coverage: CGFloat = 1.0) -> [CGPoint] {
        (0..<count).map { i in
            let angle = coverage * 2 * .pi * CGFloat(i) / CGFloat(count)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
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
    private func largestGap(_ samples: [VectorSample]) -> CGFloat {
        guard samples.count >= 2 else { return 0 }
        return (1..<samples.count).map {
            hypot(samples[$0].x - samples[$0 - 1].x, samples[$0].y - samples[$0 - 1].y)
        }.max() ?? 0
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

    func testRejectsPartialArc() {
        // A 90° arc has uniform radii but nowhere near the outline coverage an oval needs.
        let points = circlePoints(center: CGPoint(x: 200, y: 200), radius: 90, coverage: 0.25)
        XCTAssertNotEqual(ShapeDetector.detect(from: points)?.kind, .oval)
    }

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
}
