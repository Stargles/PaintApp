import XCTest
import UIKit
import CoreGraphics

/// What an eraser gesture leaves in a cel at commit — TODO (80), (81), (83) — driven through the real
/// `VectorCanvas.erase` rather than the geometry it is built on.
///
/// Same arrangement as `VectorEraserHybridLogicTests`: the engine files compile into this target as
/// well as the app, so no `@testable import`.
final class VectorEraserCommitLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 256, height: 256)

    private static func brush(size: CGFloat) -> Brush {
        Brush(name: "test", tip: .round, size: size)
    }

    private static func stroke(_ points: [CGPoint], size: CGFloat = 6, pressure: CGFloat = 1) -> VectorStroke {
        VectorStroke(brush: brush(size: size), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: size, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: pressure) },
                                            channels: .pressureOnly))
    }

    private static func gesture(_ points: [CGPoint]) -> StrokeSamples {
        StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) }, channels: .pressureOnly)
    }

    // MARK: - (83) A dense fixture: twenty short strokes under one dab, and a long one through it

    /// Twenty short strokes under a 40 pt dab at `centre`, at angles and offsets that make them
    /// overlap each other many times over; plus one long stroke through the centre.
    ///
    /// **Ten of the twenty have a centreline endpoint outside the dab's footprint by less than their
    /// own radius** — so their ink pokes past the eraser's edge by a point or two, which is what "a
    /// small stroke inside the circle" looks like on a screen, and what the centreline-only cut left
    /// standing as a dot the artist then had to chase.
    private static func denseScene(centre: CGPoint) -> (short: [VectorStroke], long: VectorStroke) {
        var short: [VectorStroke] = []
        for i in 0..<20 {
            let angle = CGFloat(i) * .pi / 10 + 0.3
            let size = 3 + CGFloat(i % 3)
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            // Even strokes sit well inside; odd ones reach 20 + 0.2·size from the centre, i.e. past
            // the edge by less than their half-width of size / 2.
            let reach: CGFloat = i % 2 == 0 ? 12 : 20 + size * 0.2
            let a = CGPoint(x: centre.x - direction.x * 6, y: centre.y - direction.y * 6)
            let mid = CGPoint(x: centre.x + direction.x * (reach - 6) / 2, y: centre.y + direction.y * (reach - 6) / 2)
            let b = CGPoint(x: centre.x + direction.x * reach, y: centre.y + direction.y * reach)
            // Three samples, so the middle one is an interior knot rather than an endpoint.
            short.append(stroke([a, mid, b], size: size))
        }
        let long = stroke((0...12).map { CGPoint(x: 20 + CGFloat($0) * 18, y: centre.y) }, size: 8)
        return (short, long)
    }

    /// A survivor none of whose ink the eraser missed: every point of its centreline lies within its
    /// own half-width of the footprint, so every dab it draws was under the eraser. Measured here
    /// against the gesture's own axis with a constant-pressure nib, independently of the engine's
    /// probe walk.
    private func stubs(in canvas: VectorCanvas, gesture: StrokeSamples, nibRadius: CGFloat) -> [VectorStroke] {
        let axis = gesture.map(\.point)
        return canvas.strokes.filter { stroke in
            let radius = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
            let path = StrokePath(stroke.samples)
            let length = path.arcLength(to: path.domainEnd)
            let steps = max(Int(length / 0.25), 1)
            for step in 0...steps {
                let parameter = path.domainEnd * CGFloat(step) / CGFloat(steps)
                guard let point = path.point(at: parameter) else { continue }
                let gap = sqrt(StrokeGeometry.distanceSquared(from: point, toPolyline: axis)) - nibRadius
                if gap > radius { return false }
            }
            return true
        }
    }

    func testCutDeletesEveryShortStrokeUnderTheDabAndLeavesNoStub() {
        let centre = CGPoint(x: 128, y: 128)
        let scene = Self.denseScene(centre: centre)
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: scene.short.map(VectorElement.stroke) + [.stroke(scene.long)])
        let nib = Self.brush(size: 40)
        let dab = Self.gesture([centre])
        XCTAssertTrue(canvas.erase(alongPath: dab, brush: nib, size: 40, mode: .cutPoints),
                      "the dab covers twenty strokes and crosses a twenty-first")

        let survivors = canvas.strokes
        XCTAssertEqual(survivors.count, 2,
                       "only the long stroke's two halves survive; \(survivors.count - 2) extra pieces are "
                       + "short strokes the dab covered whole or stubs of the long one")
        XCTAssertTrue(stubs(in: canvas, gesture: dab, nibRadius: 20).isEmpty,
                      "a survivor the eraser touched along its whole length is a stub: "
                      + "\(stubs(in: canvas, gesture: dab, nibRadius: 20).count) left")
        for piece in survivors {
            XCTAssertGreaterThan(StrokePath(piece.samples).arcLength(to: StrokePath(piece.samples).domainEnd), 40,
                                 "each half of the long stroke runs from the dab's edge to the stroke's end")
        }
    }

    /// The same scene under a *drag* rather than a dab: the eraser crosses the cluster top to bottom,
    /// so the sweep is a chain of capsules whose union contains the dab's disc.
    func testCutDragAcrossTheClusterDeletesEveryShortStrokeAndLeavesNoStub() {
        let centre = CGPoint(x: 128, y: 128)
        let scene = Self.denseScene(centre: centre)
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: scene.short.map(VectorElement.stroke) + [.stroke(scene.long)])
        let nib = Self.brush(size: 40)
        let drag = Self.gesture((0...8).map { CGPoint(x: 128, y: 100 + CGFloat($0) * 7) })
        XCTAssertTrue(canvas.erase(alongPath: drag, brush: nib, size: 40, mode: .cutPoints))
        let survivors = canvas.strokes
        XCTAssertEqual(survivors.count, 2, "only the long stroke's two halves survive")
        XCTAssertTrue(stubs(in: canvas, gesture: drag, nibRadius: 20).isEmpty,
                      "a survivor the eraser touched along its whole length is a stub: "
                      + "\(stubs(in: canvas, gesture: drag, nibRadius: 20).count) left")
    }

    /// The other stub: a thin eraser crossing a thick stroke's centreline near its end used to leave
    /// the short piece beyond the crossing standing as a full-width blob — its round cap regrew into
    /// the gap and its own end cap was there already, so the "cut" left more ink than a raster erase
    /// would have and the artist read it as a stub. A piece the eraser touched along its whole
    /// length has no ink the eraser missed, and goes.
    func testACutNearAThickStrokesEndDropsThePieceBeyondIt() {
        let thick = Self.stroke((0...10).map { CGPoint(x: 20 + CGFloat($0) * 18, y: 128) }, size: 40)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stroke(thick)])
        // Radius 4, crossing the centreline 10 pt from the stroke's end at x == 200.
        let drag = Self.gesture([CGPoint(x: 190, y: 100), CGPoint(x: 190, y: 156)])
        XCTAssertTrue(canvas.erase(alongPath: drag, brush: Self.brush(size: 8), size: 8, mode: .cutPoints))
        XCTAssertEqual(canvas.strokes.count, 1, "the 10 pt piece beyond the crossing is a stub and goes")
        guard let survivor = canvas.strokes.first else { return }
        XCTAssertEqual(survivor.samples.last?.x ?? 0, 186, accuracy: 0.01,
                       "the long piece ends at the eraser's near edge, exactly where the centreline left it")
    }

    /// The same eraser through the same stroke's *middle* changes nothing about which pieces survive:
    /// both halves run on past the eraser's reach, so both keep ink it never touched.
    func testAThinEraserAcrossAThickStrokesMiddleLeavesBothHalves() {
        let thick = Self.stroke((0...10).map { CGPoint(x: 20 + CGFloat($0) * 18, y: 128) }, size: 40)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stroke(thick)])
        let drag = Self.gesture([CGPoint(x: 110, y: 100), CGPoint(x: 110, y: 156)])
        XCTAssertTrue(canvas.erase(alongPath: drag, brush: Self.brush(size: 8), size: 8, mode: .cutPoints))
        XCTAssertEqual(canvas.strokes.count, 2)
        XCTAssertTrue(stubs(in: canvas, gesture: drag, nibRadius: 4).isEmpty)
    }
}
