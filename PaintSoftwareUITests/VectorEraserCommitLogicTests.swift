import XCTest
import UIKit
import CoreGraphics

/// What an eraser gesture leaves in a cel at commit — TODO (80), (81), (82), (83) — driven through
/// the real `VectorCanvas.erase` and `CanvasManager.commitUniversalErase` rather than the geometry
/// they are built on.
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

    // MARK: - (81) An eraser that erases nothing lands nowhere

    /// A cel with a stroke along the top and a triangular fill whose *bounding box* covers the middle
    /// of the canvas while its region keeps to the lower-left half.
    private static func inkAroundTheMiddle() -> [VectorElement] {
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: 8, y: 248))
        triangle.addLine(to: CGPoint(x: 248, y: 248))
        triangle.addLine(to: CGPoint(x: 8, y: 8))
        triangle.closeSubpath()
        let fill = VectorFillElement(path: triangle, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let top = stroke([CGPoint(x: 40, y: 30), CGPoint(x: 216, y: 30)], size: 6)
        return [.fill(fill), .stroke(top)]
    }

    /// The footprint sits over the fill's box and under the stroke's, and touches neither's ink: the
    /// gesture leaves the display list exactly as it was and reports that nothing changed, which is
    /// what keeps the undo step from being recorded.
    func testAnEraserWhoseFootprintTouchesNoInkIsDroppedAtCommit() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.inkAroundTheMiddle())
        let nib = Self.brush(size: 20)
        // Above the triangle's hypotenuse (x + y == 256) by more than the nib's radius, and 30 pt
        // below the stroke's ink (y ≤ 33).
        let miss = Self.gesture([CGPoint(x: 150, y: 60), CGPoint(x: 200, y: 60)])
        XCTAssertFalse(canvas.eraserTouchesInk(alongPath: miss, brush: nib, size: 20))
        XCTAssertFalse(canvas.erase(alongPath: miss, brush: nib, size: 20, mode: .erase),
                       "an eraser over nothing must report that nothing changed")
        XCTAssertEqual(canvas.elements.count, 2, "nothing lands")
        XCTAssertTrue(canvas.strokes.allSatisfy { $0.composite == .paint }, "no punch is retained")
    }

    /// The same gesture nudged until its footprint reaches the stroke's ink — not its centreline,
    /// which stays 7 pt outside the footprint — lands as one `.erase` element.
    func testAnEraserWhoseFootprintGrazesInkLandsAsAPunch() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.inkAroundTheMiddle())
        let nib = Self.brush(size: 20)
        // Radius 10 at y == 42 reaches down to y == 32; the stroke's ink reaches up to y == 33.
        let graze = Self.gesture([CGPoint(x: 150, y: 42), CGPoint(x: 200, y: 42)])
        XCTAssertTrue(canvas.eraserTouchesInk(alongPath: graze, brush: nib, size: 20))
        XCTAssertTrue(canvas.erase(alongPath: graze, brush: nib, size: 20, mode: .erase))
        XCTAssertEqual(canvas.strokes.filter { $0.composite == .erase }.count, 1, "the gesture is retained as a punch")
        XCTAssertEqual(canvas.elements.count, 3)
    }

    /// The fill half of the predicate is the region, not the box: a footprint inside the triangle's
    /// bounding box but outside the triangle touches nothing, and one across its hypotenuse does.
    func testAFillIsTouchedByItsRegionAndNotByItsBoundingBox() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.inkAroundTheMiddle())
        let nib = Self.brush(size: 20)
        XCTAssertFalse(canvas.eraserTouchesInk(alongPath: Self.gesture([CGPoint(x: 200, y: 80)]), brush: nib, size: 20),
                       "inside the box, 24 pt clear of the hypotenuse")
        XCTAssertTrue(canvas.eraserTouchesInk(alongPath: Self.gesture([CGPoint(x: 132, y: 132)]), brush: nib, size: 20),
                      "across the hypotenuse")
        XCTAssertTrue(canvas.eraserTouchesInk(alongPath: Self.gesture([CGPoint(x: 40, y: 200)]), brush: nib, size: 20),
                      "wholly inside the region, touching no edge")
    }

    // MARK: - (82) The universal eraser

    /// Four vector layers and a raster one, in a 64² document: `under` and `alsoUnder` each hold a
    /// horizontal line the gesture crosses; `aside` holds one it never reaches; `hidden` holds one
    /// under the gesture but is switched off. Every stroke is 4 pt wide.
    private struct Stack {
        let manager: CanvasManager
        let under: Int, alsoUnder: Int, aside: Int, hidden: Int
        var canvases: [Int: VectorCanvas] {
            var out: [Int: VectorCanvas] = [:]
            for index in [under, alsoUnder, aside, hidden] { out[index] = manager.layers[index].cels[0].vector }
            return out
        }
    }

    private static func stack() -> Stack {
        let manager = CanvasFixture.manager(layerCount: 1)
        func vectorLayer(withLineAt y: CGFloat) -> Int {
            manager.addVectorLayer()
            let index = manager.layers.count - 1
            let line = stroke((0...8).map { CGPoint(x: 4 + CGFloat($0) * 7, y: y) }, size: 4)
            manager.layers[index].cels[0].vector?.addStroke(line)
            return index
        }
        let under = vectorLayer(withLineAt: 32)
        let alsoUnder = vectorLayer(withLineAt: 34)
        let aside = vectorLayer(withLineAt: 8)
        let hidden = vectorLayer(withLineAt: 30)
        manager.toggleLayerVisibility(layerIndex: hidden)
        manager.currentLayerIndex = under
        return Stack(manager: manager, under: under, alsoUnder: alsoUnder, aside: aside, hidden: hidden)
    }

    /// A vertical Cut through the middle: both visible lines under it are cut in two, the line
    /// aside and the hidden line are untouched, and one undo press restores both cut lines.
    func testUniversalCutLandsOnEveryVisibleLayerItErasesOnAsOneUndoStep() {
        let stack = Self.stack()
        let manager = stack.manager
        let canvases = stack.canvases
        let drag = Self.gesture([CGPoint(x: 32, y: 20), CGPoint(x: 32, y: 44)])
        let nib = Self.brush(size: 6)
        let steps = manager.history.undoStack.count

        let landed = manager.commitUniversalErase(runs: [drag], brush: nib, size: 6, opacity: 1, mode: .cutPoints)
        XCTAssertEqual(landed.count, 2, "the two visible layers with ink under the gesture, and no other")
        XCTAssertTrue(landed.contains { $0 === canvases[stack.under] })
        XCTAssertTrue(landed.contains { $0 === canvases[stack.alsoUnder] })
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 2, "cut in two")
        XCTAssertEqual(canvases[stack.alsoUnder]?.strokes.count, 2, "cut in two")
        XCTAssertEqual(canvases[stack.aside]?.strokes.count, 1, "a layer the gesture erases nothing on is left alone")
        XCTAssertEqual(canvases[stack.hidden]?.strokes.count, 1, "a hidden layer is never reached")

        XCTAssertEqual(manager.history.undoStack.count - steps, 1, "the gesture is one undo step")
        manager.undo()
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 1, "one press restores both layers")
        XCTAssertEqual(canvases[stack.alsoUnder]?.strokes.count, 1)
        manager.redo()
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 2)
        XCTAssertEqual(canvases[stack.alsoUnder]?.strokes.count, 2)
    }

    /// Mode 1 through the same stack: a punch lands on the two layers with ink under it and on
    /// neither of the others — (81)'s predicate, asked per layer.
    func testUniversalPunchLandsOnlyWhereItTouchesInk() {
        let stack = Self.stack()
        let canvases = stack.canvases
        let drag = Self.gesture([CGPoint(x: 32, y: 20), CGPoint(x: 32, y: 44)])
        let nib = Self.brush(size: 6)
        let landed = stack.manager.commitUniversalErase(runs: [drag], brush: nib, size: 6, opacity: 1, mode: .erase)
        XCTAssertEqual(landed.count, 2)
        for index in [stack.under, stack.alsoUnder] {
            XCTAssertEqual(canvases[index]?.strokes.filter { $0.composite == .erase }.count, 1,
                           "one punch on layer \(index)")
        }
        for index in [stack.aside, stack.hidden] {
            XCTAssertEqual(canvases[index]?.strokes.filter { $0.composite == .erase }.count, 0,
                           "no punch on layer \(index)")
        }
    }

    /// A gesture that reaches no ink on any layer records nothing at all.
    func testUniversalEraseOverNothingRecordsNoStep() {
        let stack = Self.stack()
        let steps = stack.manager.history.undoStack.count
        let miss = Self.gesture([CGPoint(x: 32, y: 50), CGPoint(x: 32, y: 60)])
        let landed = stack.manager.commitUniversalErase(runs: [miss], brush: Self.brush(size: 6), size: 6,
                                                        opacity: 1, mode: .erase)
        XCTAssertTrue(landed.isEmpty)
        XCTAssertEqual(stack.manager.history.undoStack.count, steps, "no step for a gesture that landed nowhere")
    }

    /// To Cross under the universal eraser: a session per visible layer, each cut on the sample that
    /// reaches its line, one undo step at the lift — and a cancel puts every cut back.
    func testUniversalToCrossCutsPerLayerAndUndoesAsOne() {
        let stack = Self.stack()
        let manager = stack.manager
        let canvases = stack.canvases
        let nib = Self.brush(size: 6)
        let steps = manager.history.undoStack.count

        var sessions = manager.beginUniversalIntersectionCut()
        XCTAssertEqual(sessions.count, 3, "every visible vector layer, hidden excluded")
        let cut = manager.resolveUniversalIntersectionCut(at: CGPoint(x: 32, y: 33), brush: nib, size: 6,
                                                          sessions: &sessions)
        XCTAssertEqual(cut.count, 2, "the two lines under the tip")
        // Neither line crosses anything, so each is deleted whole — To Cross's rule.
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 0)
        XCTAssertEqual(canvases[stack.alsoUnder]?.strokes.count, 0)
        XCTAssertEqual(canvases[stack.aside]?.strokes.count, 1)
        let landed = manager.endUniversalIntersectionCut(sessions)
        XCTAssertEqual(landed.count, 2)
        XCTAssertEqual(manager.history.undoStack.count - steps, 1, "one step for both cels")
        manager.undo()
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 1)
        XCTAssertEqual(canvases[stack.alsoUnder]?.strokes.count, 1)
        XCTAssertEqual(manager.history.undoStack.count, steps)

        // The cancel arm: cut, then a second finger lands.
        var again = manager.beginUniversalIntersectionCut()
        _ = manager.resolveUniversalIntersectionCut(at: CGPoint(x: 32, y: 33), brush: nib, size: 6, sessions: &again)
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 0, "Setup: cut again")
        manager.cancelUniversalIntersectionCut(again)
        XCTAssertEqual(canvases[stack.under]?.strokes.count, 1, "the cancel restores every cel")
        XCTAssertEqual(canvases[stack.alsoUnder]?.strokes.count, 1)
        XCTAssertEqual(manager.history.undoStack.count, steps, "and records nothing")
    }

    /// The switch persists with the mode it aims, and a manifest written before it existed reads
    /// as off.
    func testUniversalEraserRoundTripsThroughTheManifestAndDefaultsToOff() throws {
        let on = ProjectManifest(id: UUID(), name: "t", canvasWidth: 64, canvasHeight: 64, fps: 12,
                                 layers: [], modifiedAt: Date(), universalEraser: true)
        let back = try JSONDecoder().decode(ProjectManifest.self, from: JSONEncoder().encode(on))
        XCTAssertTrue(back.universalEraser)
        let off = ProjectManifest(id: UUID(), name: "t", canvasWidth: 64, canvasHeight: 64, fps: 12,
                                  layers: [], modifiedAt: Date())
        let bytes = try JSONEncoder().encode(off)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("universalEraser"),
                       "off is the absence of the key, so an older document's bytes are unchanged")
        XCTAssertFalse(try JSONDecoder().decode(ProjectManifest.self, from: bytes).universalEraser)
    }
}
