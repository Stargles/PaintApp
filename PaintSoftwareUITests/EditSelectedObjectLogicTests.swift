import XCTest
import SwiftUI
import UIKit

/// **TODO (116) and (128) — the Select panel's Edit entry.** One control for every kind of object
/// that has an editor of its own: *"When I select a textbox with the select tool, there should be
/// another edit option to edit the text, which will bring up the text menu, and I can change it in
/// real time. It also should bring up the move box for that text where I can move it"* and *"if a
/// gradient is selected, there should be an edit gradient button like the edit text button."*
///
/// What these pin is the dispatch and what each arm opens: which objects the loop's catch resolves to
/// (`SelectionStyle.editableObjects`, one per kind), that `editSelectedObject(_:)` opens the text
/// session on the caught box with the tool and the box a re-opened text has, or the gradient session on
/// the caught gradient, and that the loop survives. `EditSelectedObjectUITests` drives the same thing
/// off the screen.
@MainActor
final class EditSelectedObjectLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func vectorFixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    private func textElement(_ string: String, at origin: CGPoint = CGPoint(x: 20, y: 20)) -> VectorTextElement {
        VectorTextElement(id: UUID(),
                          recipe: TextRecipe(string: string, typography: Typography(pointSize: 14)),
                          frame: TextFrame(origin: origin, size: CGSize(width: 24, height: 16), autoSize: false))
    }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ rect: CGRect) {
        let path = CGPath(rect: rect, transform: nil)
        manager.selection = Selection(path: path, bounds: path.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    private let everything = CGRect(x: 1, y: 1, width: 62, height: 62)

    private func stroke(y: CGFloat) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 3, opacity: 1,
                     samples: [VectorSample(x: 6, y: y, pressure: 1), VectorSample(x: 14, y: y, pressure: 1)],
                     composite: .paint)
    }

    private func gradientFill(_ vector: VectorCanvas) -> UUID {
        vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 0, y: 0, width: 64, height: 64), transform: nil),
                       paint: .linearGradient(.spanning(CGRect(x: 0, y: 0, width: 64, height: 64), angle: 0))).id
    }

    // MARK: - What the loop catches

    /// **Text caught by the loop is an editable object**, and its entry is titled for it.
    func testALoopAroundATextBoxOffersEditText() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let text = textElement("Hello")
        vector.upsertText(text)
        select(manager, layerIndex, everything)

        XCTAssertEqual(manager.selectionStyle.editableKinds, [.text])
        XCTAssertEqual(manager.selectionStyle.editableObjects[.text], text.id)
        XCTAssertEqual(EditableKind.text.title, "Edit Text")
        XCTAssertEqual(EditableKind.text.panel, .text, "the text panel is the one it raises")
    }

    /// And a gradient caught by the loop offers Edit Gradient — titled for what it will open, raising
    /// no `ActivePanel` (its card is keyed on the session).
    func testALoopAroundAGradientOffersEditGradient() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let id = gradientFill(vector)
        select(manager, layerIndex, everything)

        XCTAssertEqual(manager.selectionStyle.editableKinds, [.gradient])
        XCTAssertEqual(manager.selectionStyle.editableObjects[.gradient], id)
        XCTAssertEqual(EditableKind.gradient.title, "Edit Gradient")
        XCTAssertEqual(EditableKind.gradient.panel, .none)
    }

    /// **Ink, flat fills and nothing at all offer no Edit entry** — it is not a button that does
    /// nothing, it is a button that is not there.
    func testNothingEditableMeansNoEntry() {
        let (manager, layerIndex, vector) = vectorFixture()
        vector.addStroke(stroke(y: 10))
        vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 30, y: 30, width: 10, height: 10), transform: nil),
                       color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        select(manager, layerIndex, everything)

        XCTAssertTrue(manager.selectionStyle.editableKinds.isEmpty, "strokes and flat fills have no editor of their own")
        for kind in EditableKind.allCases {
            XCTAssertFalse(manager.editSelectedObject(kind), "…and the model refuses \(kind) if a view asks anyway")
        }
        XCTAssertNotEqual(manager.selectedTool, .text, "a refusal leaves the tool alone")
        XCTAssertNil(manager.gradientEdit)
    }

    /// **A loop that catches both offers both, in a fixed order, whichever is on top** — one button
    /// each (the owner, 2026-10-01), so the entries do not swap places when the stacking does.
    func testALoopAroundATextBoxAndAGradientOffersBothEntries() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let gradient = gradientFill(vector)
        let text = textElement("On top")
        vector.upsertText(text)
        select(manager, layerIndex, everything)
        XCTAssertEqual(manager.selectionStyle.editableKinds, [.text, .gradient], "text above the gradient")
        XCTAssertEqual(manager.selectionStyle.editableObjects[.text], text.id)
        XCTAssertEqual(manager.selectionStyle.editableObjects[.gradient], gradient)

        let (manager2, layerIndex2, vector2) = vectorFixture()
        let under = textElement("Underneath")
        vector2.upsertText(under)
        let over = gradientFill(vector2)
        select(manager2, layerIndex2, everything)
        XCTAssertEqual(manager2.selectionStyle.editableKinds, [.text, .gradient], "gradient above the text")
        XCTAssertEqual(manager2.selectionStyle.editableObjects[.text], under.id)
        XCTAssertEqual(manager2.selectionStyle.editableObjects[.gradient], over)
    }

    /// **Each entry opens its own editor on its own object, whatever else the loop caught.** The
    /// gradient is on top, so a topmost-wins entry would have opened it for both.
    func testEachEntryOpensItsOwnKindWhateverIsOnTop() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let text = textElement("Underneath")
        vector.upsertText(text)
        let gradient = gradientFill(vector)
        select(manager, layerIndex, everything)

        XCTAssertTrue(manager.editSelectedObject(.text))
        XCTAssertEqual(manager.textEditingElementID, text.id, "Edit Text opened the text, not the gradient above it")
        XCTAssertNil(manager.gradientEdit)

        XCTAssertTrue(manager.editSelectedObject(.gradient))
        XCTAssertEqual(manager.gradientEdit?.elementID, gradient)
        XCTAssertNotNil(manager.selection, "the loop stays through both")
    }

    /// **Two of a kind: the entry opens the topmost of that kind** — the one the artist can see.
    func testTwoTextBoxesOfferOneEditTextOnTheTopmost() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let lower = textElement("Lower", at: CGPoint(x: 10, y: 10))
        let upper = textElement("Upper", at: CGPoint(x: 10, y: 40))
        vector.upsertText(lower)
        vector.upsertText(upper)
        select(manager, layerIndex, everything)

        XCTAssertEqual(manager.selectionStyle.editableKinds, [.text], "one entry for the kind, not one per box")
        XCTAssertEqual(manager.selectionStyle.editableObjects[.text], upper.id)
        XCTAssertTrue(manager.editSelectedObject(.text))
        XCTAssertEqual(manager.textEditingElementID, upper.id)
    }

    // MARK: - Edit Text

    /// **Edit Text opens the text session on the caught box**: the text tool is on, the session is the
    /// re-open of that object (its recipe, its frame, its id), and the loop is still up.
    func testEditTextReopensTheCaughtBoxInTheTextTool() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        var text = textElement("Hello")
        text.recipe.typography.pointSize = 22
        vector.upsertText(text)
        select(manager, layerIndex, everything)
        let undoDepth = manager.history.undoStack.count

        XCTAssertTrue(manager.editSelectedObject(.text))

        XCTAssertEqual(manager.selectedTool, .text, "the text tool, whose overlay is the box with its grips")
        XCTAssertTrue(manager.textGestureActive, "a live text session")
        XCTAssertEqual(manager.textEditingElementID, text.id, "on the object that was caught")
        XCTAssertEqual(manager.textRecipe.string, "Hello")
        XCTAssertEqual(manager.textRecipe.typography.pointSize, 22, "its own typography, for the panel to show")
        XCTAssertEqual(manager.textFrame[.topLeft].x, 20, accuracy: 0.01, "its own box, where it was")
        XCTAssertNotNil(manager.selection, "a live selection outlives the tool that made it")
        XCTAssertEqual(manager.history.undoStack.count, undoDepth, "opening it records nothing")
    }

    /// **Edited in real time and committed as one step**: the string changes, the box moves, and the
    /// commit rewrites the same element in place — the retyped object, not a second one.
    func testEditTextThenRetypeAndMoveCommitsTheSameElementInPlace() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let text = textElement("Hello")
        vector.upsertText(text)
        select(manager, layerIndex, everything)
        XCTAssertTrue(manager.editSelectedObject(.text))
        let undoDepth = manager.history.undoStack.count

        manager.updateTextString("Hello there")
        manager.beginTextFrameDrag()
        manager.dragTextFrame(toOrigin: CGPoint(x: 30, y: 40))
        manager.endTextFrameDrag()
        manager.commitInteractiveText()

        let texts = vector.elements.compactMap(\.text)
        XCTAssertEqual(texts.count, 1, "the same object, not a copy beside it")
        XCTAssertEqual(texts.first?.id, text.id)
        XCTAssertEqual(texts.first?.recipe.string, "Hello there")
        XCTAssertEqual(try XCTUnwrap(texts.first).frame[.topLeft].x, 30, accuracy: 0.01, "and it moved")
        XCTAssertEqual(manager.history.undoStack.count - undoDepth, 1, "one step for the whole session")
    }

    // MARK: - Edit Gradient

    /// **Edit Gradient opens the gradient session on the caught gradient**, leaves the loop and the
    /// tool alone, and a change made in it reaches the canvas.
    func testEditGradientOpensTheSessionOnTheCaughtGradient() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let id = gradientFill(vector)
        select(manager, layerIndex, everything)
        let tool = manager.selectedTool

        XCTAssertTrue(manager.editSelectedObject(.gradient))

        XCTAssertEqual(manager.gradientEdit?.elementID, id)
        XCTAssertEqual(manager.selectedTool, tool, "the tool is not changed")
        XCTAssertNotNil(manager.selection, "the loop stays")
        manager.setGradientColour(.end, to: Color(red: 0, green: 1, blue: 0))
        XCTAssertEqual(try XCTUnwrap(vector.elements.first?.fill?.gradient).end.green, 1, accuracy: 0.01)
    }

    /// **A gradient session settles before another edit lands on its canvas.** Its undo step swaps the
    /// whole display list between two snapshots, so an edit made while it was still open would be
    /// swept out by undoing it. `beginCanvasEdit` is the chokepoint every real edit passes: after it
    /// the session is closed, a later edit is a step of its own, and the two undo in the order they
    /// were made — the later edit first, the gradient edit second, neither taking the other with it.
    func testTheNextCanvasEditSettlesTheGradientSessionFirst() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let id = gradientFill(vector)
        select(manager, layerIndex, everything)
        manager.editSelectedObject(.gradient)
        manager.setGradientAngle(.pi / 2)
        XCTAssertTrue(manager.hasInteractiveStatePending, "an open gradient holds the autosave off")

        manager.beginCanvasEdit()
        XCTAssertNil(manager.gradientEdit, "the session is settled")
        XCTAssertFalse(manager.hasInteractiveStatePending)
        manager.placeVectorFill(CGPath(rect: CGRect(x: 4, y: 4, width: 8, height: 8), transform: nil),
                                paint: .solid(CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
                                layerIndex: layerIndex, celIndex: 0, label: .fill)
        XCTAssertEqual(vector.elements.count, 2)

        manager.undo()
        XCTAssertEqual(vector.elements.count, 1, "the first undo takes the later edit")
        XCTAssertEqual(try XCTUnwrap(vector.elements.first?.fill?.gradient).angle, .pi / 2, accuracy: 1e-6,
                       "…and leaves the gradient edit alone")
        manager.undo()
        XCTAssertEqual(vector.elements.first?.id, id)
        XCTAssertEqual(try XCTUnwrap(vector.elements.first?.fill?.gradient).angle, 0, accuracy: 1e-6,
                       "the second takes the gradient edit")
    }

    /// **Undo pressed with the panel open commits the edit and then reverts it** — the text
    /// session's rule, so the Undo button is lit while there is something to undo and pressing it
    /// takes the artist back to before they opened the panel.
    func testUndoWithTheGradientPanelOpenRevertsTheEdit() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        gradientFill(vector)
        select(manager, layerIndex, everything)
        manager.editSelectedObject(.gradient)
        manager.setGradientAngle(.pi)
        XCTAssertTrue(manager.canUndo, "the open edit is itself undoable")
        XCTAssertFalse(manager.canRedo)

        manager.undo()

        XCTAssertNil(manager.gradientEdit, "the panel's session is closed by the undo")
        XCTAssertEqual(try XCTUnwrap(vector.elements.compactMap(\.fill).first?.gradient).angle, 0, accuracy: 1e-6)
    }
}
