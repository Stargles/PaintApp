import XCTest
import SwiftUI
import UIKit

/// **TODO (147) — Select → Tap.** The owner: *"a new select mode which is simple: you just tap on
/// anything and it selects whatever object you tapped on. If it is a text, it instantly opens the
/// edit text menu, vice versa for gradients, brushstrokes/fill shapes, etc."*
///
/// Two halves. `VectorHitTest` answers *which object* from the drawn shape of each kind, and is
/// tested as pure geometry. `CanvasManager.selectObject(at:)` turns the answer into a `Selection` and
/// is tested through what a selection is *for*: the verbs read what it caught, so "selects the stroke"
/// is asserted as "Recolour changed the stroke and left the fill under it alone", not as a stored id.
/// `TapSelectUITests` drives the same thing from a fresh document.
@MainActor
final class TapSelectLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)

    private func vectorFixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.selectionMode = .tap
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    private func stroke(from a: CGPoint, to b: CGPoint, size: CGFloat = 4, erasing: Bool = false) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black, size: size, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)],
                     composite: erasing ? .erase : .paint)
    }

    private func rect(_ r: CGRect) -> CGPath { CGPath(rect: r, transform: nil) }

    private func text(_ string: String, at origin: CGPoint = CGPoint(x: 20, y: 20)) -> VectorTextElement {
        VectorTextElement(id: UUID(),
                          recipe: TextRecipe(string: string, typography: Typography(pointSize: 14)),
                          frame: TextFrame(origin: origin, size: CGSize(width: 24, height: 16), autoSize: false))
    }

    @discardableResult
    private func flatFill(_ vector: VectorCanvas, _ r: CGRect) -> UUID {
        vector.addFill(canvasSpacePath: rect(r), paint: .solid(red)).id
    }

    private func gradientFill(_ vector: VectorCanvas, _ r: CGRect = CGRect(x: 0, y: 0, width: 64, height: 64)) -> UUID {
        vector.addFill(canvasSpacePath: rect(r), paint: .linearGradient(.spanning(r, angle: 0))).id
    }

    private func element(_ id: UUID, in vector: VectorCanvas) -> VectorElement? {
        vector.elements.first { $0.id == id }
    }

    // MARK: - Which object — the drawn shape of each kind

    /// **A stroke is its ink**: a point within the stamp radius of the centre line is on it, and one
    /// beyond the radius and a fingertip is not — measured on a 10-wide stroke, so the answer cannot be
    /// the centre line's alone.
    func testAStrokeIsHitWhereItIsInkedAndNotBeyondItsWidth() {
        let wide = VectorElement.stroke(stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30), size: 10))
        XCTAssertTrue(VectorHitTest.covers(wide, point: CGPoint(x: 30, y: 30), slop: 0), "on the centre line")
        XCTAssertTrue(VectorHitTest.covers(wide, point: CGPoint(x: 30, y: 34), slop: 0), "inside the inked half-width")
        XCTAssertFalse(VectorHitTest.covers(wide, point: CGPoint(x: 30, y: 37), slop: 0), "beyond the ink")
        XCTAssertTrue(VectorHitTest.covers(wide, point: CGPoint(x: 30, y: 37), slop: 4), "…which a fingertip's slop reaches")
        XCTAssertFalse(VectorHitTest.covers(wide, point: CGPoint(x: 3, y: 30), slop: 0), "past the end of the line")
    }

    /// An eraser mark has no ink of its own, only a hole — tapping it is tapping what shows through.
    func testAnEraserMarkIsNotAnObject() {
        let eraser = VectorElement.stroke(stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30),
                                                 size: 10, erasing: true))
        XCTAssertFalse(VectorHitTest.covers(eraser, point: CGPoint(x: 30, y: 30), slop: 6))
        XCTAssertNil(VectorHitTest.topmost(in: [eraser], at: CGPoint(x: 30, y: 30)))
    }

    /// **A fill is its path, under its own rule** — the hole in a ring is not the ring.
    func testAFillIsHitOnItsPathAndNotInItsHole() {
        let (_, _, vector) = vectorFixture()
        let ring = CGMutablePath()
        ring.addRect(CGRect(x: 10, y: 10, width: 40, height: 40))
        ring.addRect(CGRect(x: 20, y: 20, width: 20, height: 20))
        let id = vector.addFill(canvasSpacePath: ring, paint: .solid(red), evenOddFill: true).id
        let fill = element(id, in: vector)!
        XCTAssertTrue(VectorHitTest.covers(fill, point: CGPoint(x: 14, y: 30), slop: 0), "on the ring")
        XCTAssertFalse(VectorHitTest.covers(fill, point: CGPoint(x: 30, y: 30), slop: 0), "in the hole")
        XCTAssertFalse(VectorHitTest.covers(fill, point: CGPoint(x: 60, y: 30), slop: 0), "outside it")
    }

    /// Text is hit on its box — the hole in an "O" is the text — and not beyond it.
    func testTextIsHitOnItsBox() {
        let element = VectorElement.text(text("Hi"))
        XCTAssertTrue(VectorHitTest.covers(element, point: CGPoint(x: 32, y: 28), slop: 0))
        XCTAssertFalse(VectorHitTest.covers(element, point: CGPoint(x: 60, y: 28), slop: 0))
    }

    /// **The topmost wins**, by the display list's own order — a stroke over a fill is the stroke, the
    /// same point with the two the other way up is the fill.
    func testTheTopmostElementWinsByDisplayOrder() {
        let (_, _, vector) = vectorFixture()
        let fillID = flatFill(vector, CGRect(x: 0, y: 0, width: 64, height: 64))
        let line = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30))
        vector.addStroke(line)
        XCTAssertEqual(VectorHitTest.topmost(in: vector.elements, at: CGPoint(x: 30, y: 30))?.id, line.id,
                       "the stroke is above the fill")
        XCTAssertEqual(VectorHitTest.topmost(in: vector.elements, at: CGPoint(x: 30, y: 50))?.id, fillID,
                       "away from the stroke the fill is what is there")
        XCTAssertNil(VectorHitTest.topmost(in: vector.elements, at: CGPoint(x: 90, y: 90)), "and bare canvas is nothing")
    }

    /// **The outline holds the whole of the shape it stands for, with room to spare** — it is the loop
    /// the selection's rule reads, and a loop that only just reached its object would fail the Enclosed
    /// rule on a rounding error.
    func testEveryOutlineHoldsItsShapeWithAMargin() throws {
        let (_, _, vector) = vectorFixture()
        let line = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 34), size: 8)
        let shapes: [VectorElement] = [
            .stroke(line),
            .fill(try XCTUnwrap(element(flatFill(vector, CGRect(x: 5, y: 5, width: 20, height: 12)), in: vector)?.fill)),
            .text(text("Hi")),
        ]
        for shape in shapes {
            let outline = try XCTUnwrap(VectorHitTest.outline(of: shape))
            let corners: [CGPoint]
            switch shape {
            case .stroke: corners = [CGPoint(x: 10, y: 30), CGPoint(x: 50, y: 34)]
            case .fill: corners = [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 5), CGPoint(x: 5, y: 17), CGPoint(x: 25, y: 17)]
            case .text(let t): corners = t.frame.corners
            default: corners = []
            }
            for corner in corners {
                XCTAssertTrue(outline.contains(corner), "\(shape) is held at \(corner)")
            }
        }
        let textOutline = try XCTUnwrap(VectorHitTest.outline(of: .text(text("Hi"))))
        XCTAssertTrue(textOutline.contains(CGPoint(x: 19, y: 19)), "a point just outside the box is inside the margin")
    }

    // MARK: - Selecting it

    /// **A tap on a stroke selects that stroke and not the fill under it.** Asserted through the verbs
    /// that read a selection: Recolour changes the stroke's colour and leaves the fill the colour it
    /// was, and Clear deletes the stroke and leaves the fill whole. With the selection's loops
    /// answering for every element — the outline of a stroke lying inside a fill — both would have
    /// reached the fill too.
    func testATapOnAStrokeSelectsThatStrokeAloneNotTheFillUnderIt() throws {
        let (manager, _, vector) = vectorFixture()
        let fillID = flatFill(vector, CGRect(x: 0, y: 0, width: 64, height: 64))
        let line = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30))
        vector.addStroke(line)

        XCTAssertNil(manager.selectObject(at: CGPoint(x: 30, y: 30)), "a stroke has no editor of its own")
        XCTAssertEqual(manager.selection?.elements, [line.id], "the tap named the stroke")
        XCTAssertEqual(manager.selectionStyle.size, 4, "the readout is the stroke's, not the fill's")

        let blue = Color(red: 0, green: 0, blue: 1)
        XCTAssertTrue(manager.recolorSelection(to: blue))
        XCTAssertEqual(element(line.id, in: vector)?.stroke?.color.blue, 1, "the stroke was recoloured")
        XCTAssertEqual(element(fillID, in: vector)?.fill?.solidColor?.red, 1, "…and the fill under it was not")

        manager.clearSelectionPixels()
        XCTAssertNil(element(line.id, in: vector), "Clear removed the stroke")
        XCTAssertNotNil(element(fillID, in: vector), "…and left the fill whole")
        XCTAssertEqual(vector.elements.count, 1)
        XCTAssertNil(manager.selection, "the tapped object is gone, and its selection with it")
    }

    /// And Move lifts exactly the tapped object: the float carries the stroke and nothing else.
    func testMoveLiftsTheTappedObjectAndNothingUnderIt() throws {
        let (manager, _, vector) = vectorFixture()
        flatFill(vector, CGRect(x: 0, y: 0, width: 64, height: 64))
        let line = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30))
        vector.addStroke(line)
        manager.selectObject(at: CGPoint(x: 30, y: 30))

        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(manager.vectorFloat?.parts.flatMap(\.insideIDs), [line.id],
                       "the float carries the tapped stroke alone")
    }

    /// **Text opens Edit Text at once**: the session is on the tapped box, the tool is the text tool,
    /// and the selection stays up behind it.
    func testATapOnTextOpensEditTextAtOnce() throws {
        let (manager, _, vector) = vectorFixture()
        gradientFill(vector)
        let words = text("Hello")
        vector.upsertText(words)

        XCTAssertEqual(manager.selectObject(at: CGPoint(x: 30, y: 28)), .text, "the box on top is the text, not the gradient under it")
        XCTAssertEqual(manager.textEditingElementID, words.id, "Edit Text is open on that box")
        XCTAssertTrue(manager.textGestureActive)
        XCTAssertEqual(manager.selectedTool, .text)
        XCTAssertEqual(manager.selection?.elements, [words.id], "the selection outlives the editor it opened")
        XCTAssertNil(manager.gradientEdit, "and no gradient session opened")
    }

    /// **A gradient opens Edit Gradient at once**, and no text session.
    func testATapOnAGradientOpensEditGradientAtOnce() throws {
        let (manager, _, vector) = vectorFixture()
        let id = gradientFill(vector)

        XCTAssertEqual(manager.selectObject(at: CGPoint(x: 30, y: 30)), .gradient)
        XCTAssertNotNil(manager.gradientEdit, "the gradient's card is open")
        XCTAssertEqual(manager.selection?.elements, [id])
        XCTAssertFalse(manager.textGestureActive)
    }

    /// A flat fill has no editor: the tap selects it and opens nothing, so the Select panel's own
    /// verbs are what the artist has.
    func testATapOnAFlatFillSelectsItAndOpensNoEditor() throws {
        let (manager, _, vector) = vectorFixture()
        let id = flatFill(vector, CGRect(x: 10, y: 10, width: 30, height: 30))

        XCTAssertNil(manager.selectObject(at: CGPoint(x: 20, y: 20)))
        XCTAssertEqual(manager.selection?.elements, [id])
        XCTAssertNil(manager.gradientEdit)
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertNotEqual(manager.selectedTool, .text)
    }

    /// **A tap on nothing clears the selection**, and with none up changes nothing.
    func testATapOnNothingClearsTheSelection() {
        let (manager, _, vector) = vectorFixture()
        flatFill(vector, CGRect(x: 10, y: 10, width: 20, height: 20))
        manager.selectObject(at: CGPoint(x: 20, y: 20))
        XCTAssertNotNil(manager.selection)

        manager.selectObject(at: CGPoint(x: 55, y: 55))
        XCTAssertNil(manager.selection, "the tap landed on bare canvas")
        manager.selectObject(at: CGPoint(x: 56, y: 56))
        XCTAssertNil(manager.selection)
    }

    /// **Any visible layer, and the object's layer becomes the active one** — the owner's *"anything"*.
    /// The active layer is empty here; the stroke is on the other, and a tap on it selects it, switches
    /// to its layer, and leaves a selection that is that layer's.
    func testATapReachesAnObjectOnAnotherLayerAndMakesItsLayerActive() throws {
        let (manager, lower, lowerVector) = vectorFixture()
        let line = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30))
        lowerVector.addStroke(line)
        manager.addVectorLayer()
        let upper = manager.currentLayerIndex
        XCTAssertNotEqual(upper, lower, "PREMISE: the empty layer is the active one")

        manager.selectObject(at: CGPoint(x: 30, y: 30))
        XCTAssertEqual(manager.currentLayerIndex, lower, "the tap switched to the object's layer")
        XCTAssertEqual(manager.selection?.layerID, manager.layers[lower].id)
        XCTAssertEqual(manager.selection?.elements, [line.id])
    }

    /// **The topmost layer wins where two layers have an object under the finger**, and a hidden layer is
    /// not asked at all.
    func testALayerOnTopWinsAndAHiddenLayerIsNotAsked() throws {
        let (manager, lower, lowerVector) = vectorFixture()
        lowerVector.addStroke(stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30)))
        manager.addVectorLayer()
        let upper = manager.currentLayerIndex
        let upperVector = try XCTUnwrap(manager.layers[upper].cels[0].vector)
        let top = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 50, y: 30))
        upperVector.addStroke(top)

        manager.selectObject(at: CGPoint(x: 30, y: 30))
        XCTAssertEqual(manager.selection?.elements, [top.id], "the layer on top answers first")

        manager.layers[upper].isVisible = false
        manager.selectObject(at: CGPoint(x: 30, y: 30))
        XCTAssertEqual(manager.currentLayerIndex, lower, "with it hidden the tap goes through to the layer below")
        XCTAssertNotEqual(manager.selection?.elements, [top.id])
    }

    /// **The object is where it is shown, not where it is stored.** A cel channel slides the drawing 20
    /// to the right at frame 12; a tap on the stroke where it is drawn selects it, and a tap where it
    /// rests selects nothing.
    func testATapFindsTheObjectWhereAPoseShowsIt() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        manager.layers[layerIndex].cels[0].startFrame = 0
        manager.layers[layerIndex].cels[0].frameCount = 16
        let line = stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 30, y: 30))
        vector.addStroke(line)
        let box = CGRect(x: 4, y: 24, width: 32, height: 12)
        manager.layers[layerIndex].cels[0].transformTracks = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(restingIn: box)), (12, PoseQuad(box: box, mappedBy: .init(translationX: 20, y: 0)))], interpolation: .linear)
        ]
        manager.currentFrame = 12

        manager.selectObject(at: CGPoint(x: 45, y: 30))
        XCTAssertEqual(manager.selection?.elements, [line.id], "the stroke is selected where it is drawn (x 30…50)")
        manager.selectObject(at: CGPoint(x: 12, y: 30))
        XCTAssertNil(manager.selection, "…and a tap where it is stored selects nothing")
    }

    /// **A loop drawn over a tapped selection replaces it** — an object is not a region to add to.
    func testALoopDrawnOverATappedSelectionReplacesIt() {
        let (manager, _, vector) = vectorFixture()
        let id = flatFill(vector, CGRect(x: 10, y: 10, width: 20, height: 20))
        manager.selectObject(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(manager.selection?.elements, [id])

        manager.finishSelection(path: rect(CGRect(x: 40, y: 40, width: 20, height: 20)))
        XCTAssertNotNil(manager.selection)
        XCTAssertNil(manager.selection?.elements, "the loop is a region, and replaced the tapped object")
        XCTAssertEqual(manager.selection?.bounds, CGRect(x: 40, y: 40, width: 20, height: 20))
    }
    // MARK: - Single, Add, Subtract

    /// A fixture for the picker's three rules: two strokes side by side and a fill lying under both,
    /// which a selection that caught "everything inside the outlines" would also take.
    private func twoStrokesOverAFill() -> (manager: CanvasManager, vector: VectorCanvas,
                                           left: VectorStroke, right: VectorStroke, fill: UUID) {
        let (manager, _, vector) = vectorFixture()
        let fill = flatFill(vector, CGRect(x: 0, y: 0, width: 64, height: 64))
        let left = stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 26, y: 20))
        let right = stroke(from: CGPoint(x: 6, y: 44), to: CGPoint(x: 26, y: 44))
        vector.addStroke(left)
        vector.addStroke(right)
        return (manager, vector, left, right, fill)
    }

    private let onLeft = CGPoint(x: 16, y: 20)
    private let onRight = CGPoint(x: 16, y: 44)

    /// **The three rules are set arithmetic and nothing else** — the picker's whole meaning, with no
    /// canvas to confuse it. Single is the default, which is what Tap did before it had a picker.
    func testTheThreeRulesAreWhatTheirNamesSay() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(TapComposition.single.result(of: c, onto: [a, b]), [c])
        XCTAssertEqual(TapComposition.add.result(of: c, onto: [a, b]), [a, b, c])
        XCTAssertEqual(TapComposition.add.result(of: a, onto: [a, b]), [a, b], "adding what is held changes nothing")
        XCTAssertEqual(TapComposition.subtract.result(of: a, onto: [a, b]), [b])
        XCTAssertEqual(TapComposition.subtract.result(of: c, onto: [a, b]), [a, b], "subtracting what is not held changes nothing")
        XCTAssertEqual(CanvasFixture.manager(layerCount: 1).tapComposition, .single, "a fresh document selects one object per tap")
    }

    /// **Add puts a second object in the selection, and the verbs reach both and nothing else.** Asserted
    /// through Recolour (both strokes change, the fill under them does not) and through the outline the
    /// selection is drawn with, which holds both strokes.
    func testAddJoinsASecondObjectAndTheVerbsReachBothAndNothingUnderThem() throws {
        let (manager, vector, left, right, fill) = twoStrokesOverAFill()
        manager.selectObject(at: onLeft)
        manager.tapComposition = .add
        XCTAssertNil(manager.selectObject(at: onRight), "a stroke has no editor of its own")

        XCTAssertEqual(manager.selection?.elements, [left.id, right.id], "the second tap joined the first")
        let held = try XCTUnwrap(manager.selection)
        XCTAssertTrue(held.path.contains(onLeft) && held.path.contains(onRight), "the outline holds both strokes")
        XCTAssertFalse(held.path.contains(CGPoint(x: 50, y: 32)), "…and not the fill between and around them")
        XCTAssertGreaterThan(held.bounds.height, 24, "the bounds span both")

        let blue = Color(red: 0, green: 0, blue: 1)
        XCTAssertTrue(manager.recolorSelection(to: blue))
        XCTAssertEqual(element(left.id, in: vector)?.stroke?.color.blue, 1, "the first stroke was recoloured")
        XCTAssertEqual(element(right.id, in: vector)?.stroke?.color.blue, 1, "…and the second")
        XCTAssertEqual(element(fill, in: vector)?.fill?.solidColor?.red, 1, "…and the fill under both was not")
    }

    /// And Move lifts exactly the two: the float carries both strokes and not the fill.
    func testMoveLiftsEveryTappedObjectAndNothingUnderThem() throws {
        let (manager, _, left, right, _) = twoStrokesOverAFill()
        manager.tapComposition = .add
        manager.selectObject(at: onLeft)
        manager.selectObject(at: onRight)

        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(Set(manager.vectorFloat?.parts.flatMap(\.insideIDs) ?? []), [left.id, right.id],
                       "the float carries both tapped strokes and the fill is left")
    }

    /// **Subtract takes one object out and leaves the rest selected**, and what is left is what the
    /// verbs reach: Recolour changes the stroke that stayed and not the one that went.
    func testSubtractTakesTheTappedObjectOutOfTheSelection() throws {
        let (manager, vector, left, right, _) = twoStrokesOverAFill()
        manager.tapComposition = .add
        manager.selectObject(at: onLeft)
        manager.selectObject(at: onRight)
        manager.tapComposition = .subtract

        XCTAssertNil(manager.selectObject(at: onLeft))
        XCTAssertEqual(manager.selection?.elements, [right.id], "the left stroke left the selection")
        let held = try XCTUnwrap(manager.selection)
        XCTAssertTrue(held.path.contains(onRight))
        XCTAssertFalse(held.path.contains(onLeft), "the outline no longer holds it")

        XCTAssertTrue(manager.recolorSelection(to: Color(red: 0, green: 0, blue: 1)))
        XCTAssertEqual(element(right.id, in: vector)?.stroke?.color.blue, 1)
        XCTAssertEqual(element(left.id, in: vector)?.stroke?.color.blue, 0, "the stroke that was taken out is untouched")
    }

    /// **Subtracting the last object is a deselect**, not an empty selection the artist is still holding.
    func testSubtractingTheLastObjectDeselects() {
        let (manager, _, _, _, _) = twoStrokesOverAFill()
        manager.selectObject(at: onLeft)
        manager.tapComposition = .subtract
        manager.selectObject(at: onLeft)
        XCTAssertNil(manager.selection)
    }

    /// **Subtract asks the selected objects alone.** A stroke that is not selected lies over the one that
    /// is; a tap there takes out the selected one beneath it rather than finding the stroke on top and
    /// doing nothing.
    func testSubtractFindsTheSelectedObjectBeneathAnUnselectedOne() throws {
        let (manager, _, left, _, _) = twoStrokesOverAFill()
        manager.selectObject(at: onLeft)
        let over = stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 26, y: 20), size: 8)
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        vector.addStroke(over)
        XCTAssertEqual(VectorHitTest.topmost(in: vector.elements, at: onLeft)?.id, over.id, "PREMISE: the new stroke is on top")
        XCTAssertEqual(manager.selection?.elements, [left.id])

        manager.tapComposition = .subtract
        manager.selectObject(at: onLeft)
        XCTAssertNil(manager.selection, "the selected stroke under the unselected one was the one taken out")
    }

    /// **A miss never costs a set that took several taps to build** — under Add and Subtract. Under Single
    /// a miss clears, as it always did.
    func testAMissChangesNothingUnderAddAndSubtractAndClearsUnderSingle() {
        let (manager, _, left, right, _) = twoStrokesOverAFill()
        manager.tapComposition = .add
        manager.selectObject(at: onLeft)
        manager.selectObject(at: onRight)
        let bare = CGPoint(x: 90, y: 90)

        manager.selectObject(at: bare)
        XCTAssertEqual(manager.selection?.elements, [left.id, right.id], "an Add that found nothing kept the set")
        manager.tapComposition = .subtract
        manager.selectObject(at: bare)
        XCTAssertEqual(manager.selection?.elements, [left.id, right.id], "…and so did a Subtract")
        manager.selectObject(at: CGPoint(x: 50, y: 32))
        XCTAssertEqual(manager.selection?.elements, [left.id, right.id], "…a fill is not a selected object to take out")
        manager.tapComposition = .single
        manager.selectObject(at: bare)
        XCTAssertNil(manager.selection, "a Single that found nothing put the selection down")
    }

    /// **A Subtract with nothing tapped to take from says so**: with no selection at all, and with a
    /// region drawn by a loop, which holds no tapped objects.
    func testSubtractWithNothingTappedToTakeFromSaysSo() {
        let (manager, _, _, _, _) = twoStrokesOverAFill()
        manager.tapComposition = .subtract
        manager.selectObject(at: onLeft)
        XCTAssertEqual(manager.notice?.code, "nothingTappedToSubtractFrom", "no selection at all")
        XCTAssertNil(manager.selection)

        manager.notice = nil
        manager.finishSelection(path: rect(CGRect(x: 0, y: 0, width: 40, height: 30)))
        let region = manager.selection
        XCTAssertNotNil(region)
        manager.selectObject(at: onLeft)
        XCTAssertEqual(manager.notice?.code, "nothingTappedToSubtractFrom", "a drawn region is not a set of tapped objects")
        XCTAssertEqual(manager.selection?.bounds, region?.bounds, "…and it was left as it was")
    }

    /// **Add and Subtract open no editor** — the artist is building a set, and the Select panel's Edit
    /// entries are one tap away. Single is the rule that opens text at once.
    func testOnlySingleOpensAnObjectsEditor() {
        let (manager, _, vector) = vectorFixture()
        vector.upsertText(text("Hello"))
        manager.tapComposition = .add
        XCTAssertNil(manager.selectObject(at: CGPoint(x: 30, y: 28)), "Add selected the words and opened nothing")
        XCTAssertFalse(manager.textGestureActive)
        XCTAssertNotNil(manager.selection)
        XCTAssertTrue(manager.selectionStyle.editableKinds.contains(.text), "…the panel's Edit Text is what is offered")

        manager.deselect()
        manager.tapComposition = .single
        XCTAssertEqual(manager.selectObject(at: CGPoint(x: 30, y: 28)), .text)
        XCTAssertTrue(manager.textGestureActive)
    }

    /// **An Add on another cel starts a new set there**: one selection holds the objects of one cel, and
    /// walking to another has always put the selection down.
    func testAnAddOnAnotherLayerStartsANewSetThere() throws {
        let (manager, lower, lowerVector) = vectorFixture()
        let below = stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10))
        lowerVector.addStroke(below)
        manager.addVectorLayer()
        let upper = manager.currentLayerIndex
        let above = stroke(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 50, y: 50))
        try XCTUnwrap(manager.layers[upper].cels[0].vector).addStroke(above)

        manager.tapComposition = .add
        manager.selectObject(at: CGPoint(x: 30, y: 10))
        XCTAssertEqual(manager.currentLayerIndex, lower)
        manager.selectObject(at: CGPoint(x: 30, y: 50))
        XCTAssertEqual(manager.currentLayerIndex, upper, "the tap's layer is the active one")
        XCTAssertEqual(manager.selection?.elements, [above.id], "the set is the object tapped, on its own layer")
        XCTAssertEqual(manager.selection?.layerID, manager.layers[upper].id)
    }

    /// **A set and a region replace each other**: a loop over a tapped set (the existing rule), and an Add
    /// over a drawn region, which is not a set an object can join.
    func testATapAddedOverADrawnRegionStartsASet() {
        let (manager, _, _, right, _) = twoStrokesOverAFill()
        manager.finishSelection(path: rect(CGRect(x: 0, y: 0, width: 40, height: 30)))
        XCTAssertNil(manager.selection?.elements, "PREMISE: a drawn region")

        manager.tapComposition = .add
        manager.selectObject(at: onRight)
        XCTAssertEqual(manager.selection?.elements, [right.id], "the Add made a set of the tapped object alone")
    }

    /// **Clear deletes the whole set and the selection goes with it**, as it did for one object.
    func testClearTakesEveryTappedObjectAwayAndTheSelectionWithThem() {
        let (manager, vector, left, right, fill) = twoStrokesOverAFill()
        manager.tapComposition = .add
        manager.selectObject(at: onLeft)
        manager.selectObject(at: onRight)

        manager.clearSelectionPixels()
        XCTAssertNil(element(left.id, in: vector))
        XCTAssertNil(element(right.id, in: vector))
        XCTAssertNotNil(element(fill, in: vector), "the fill under them stays")
        XCTAssertNil(manager.selection)
    }

}
