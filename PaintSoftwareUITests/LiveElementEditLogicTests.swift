import XCTest
import UIKit
import CoreGraphics

/// **A live element edit is held off the document and drawn in a window** — TODO (173), the Select
/// panel's Colour, Size and Opacity drag and the gradient panel's.
///
/// The owner's iPad 9 killed its render server twice in a minute recolouring fills on a 4096²
/// document, and the measurement behind it (PERFORMANCE.md §29) is that every tick was a document
/// write: a new version, so a SwiftUI pass, a re-bake, a re-minted live pair, a re-built onion skin,
/// and a fresh canvas-sized picture for Core Animation, ten times a second. These tests pin the three
/// things that make a tick none of that, and the one that makes the picture right:
///
/// 1. **A tick writes nothing** — not the cel, not its version, not the history — and says it moved
///    (`onHeldPictureMoved`); the commit is the only write.
/// 2. **The window is cut once, for the widest the control can make the ink**, and covers every pixel
///    where the committed list draws differently from the standing one.
/// 3. **The window's picture is the committed canvas's, pixel for pixel**, inside the window; outside
///    it the standing picture already *is* the committed one. Those two together are the claim the
///    host's hole-and-surface arrangement rests on, and they are asserted off two independent walks —
///    `VectorCanvas.drawEditWindow` and a `render()` of the written list — never off one of them twice.
///
/// Headless, so it runs in the fast tier. What is *drawn on the screen* — the surface, the hole, the
/// hand-off at lift — is `SelectionEditUITests`' and `SelectionEditLiveUITests`' business.
final class LiveElementEditLogicTests: XCTestCase {

    private let side: CGFloat = 256

    // MARK: - Fixtures

    private func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CodableColor {
        CodableColor(red: r, green: g, blue: b, alpha: a)
    }

    /// A manager with a raster layer at 0 and an **active vector layer at 1**, on a 256² canvas — big
    /// enough that a local edit's window is visibly smaller than the canvas.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasSize = CGSize(width: side, height: side)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        precondition(vector.size == CGSize(width: side, height: side), "fixture precondition: a 256² canvas")
        return (manager, layerIndex, vector)
    }

    private func stroke(y: CGFloat, size: CGFloat = 10, colour: CodableColor,
                        from x0: CGFloat = 30, to x1: CGFloat = 90) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: colour, size: size, opacity: 1,
                     samples: [VectorSample(x: x0, y: y, pressure: 1),
                               VectorSample(x: (x0 + x1) / 2, y: y, pressure: 1),
                               VectorSample(x: x1, y: y, pressure: 1)])
    }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ rect: CGRect) {
        let path = CGPath(rect: rect, transform: nil)
        manager.selection = Selection(path: path, bounds: rect,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    /// **A scene with z-order in it**: a fill, a stroke across the fill, both inside the loop; a
    /// second fill and a second stroke outside it, the stroke across the second fill. A window that
    /// drew only the edited elements would lose the stroke that sits *over* the fill it edits.
    private func scene() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas, caught: Set<UUID>) {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 20, y: 20, width: 80, height: 60), transform: nil),
                       color: colour(0.8, 0.1, 0.1))
        vector.addStroke(stroke(y: 50, colour: colour(0.1, 0.1, 0.8)))
        vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 150, y: 150, width: 60, height: 60), transform: nil),
                       color: colour(0.1, 0.6, 0.1))
        vector.addStroke(stroke(y: 180, colour: colour(0.1, 0.1, 0.1), from: 120, to: 230))
        let caught = Set(vector.elements.prefix(2).map(\.id))
        select(manager, layerIndex, CGRect(x: 10, y: 10, width: 100, height: 80))
        return (manager, layerIndex, vector, caught)
    }

    /// A list's identity for comparison — `VectorElement` is not `Equatable`, and what these edits
    /// change is exactly its id order, its colours, its widths and its opacities.
    private func signature(_ elements: [VectorElement]) -> [String] {
        elements.map { "\($0.id)|\($0.colours)|\($0.stroke?.size ?? 0)|\($0.stroke?.opacity ?? $0.fill?.opacity ?? 1)" }
    }

    private func rgba(_ image: UIImage) -> [UInt8] {
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return [] }
        return bytes
    }

    /// The window's picture as the host draws it: `drawEditWindow` into a window-sized bitmap.
    private func windowPicture(_ vector: VectorCanvas, _ live: LiveElementEdit) -> [UInt8] {
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: live.window.size, format: format).image { ctx in
            vector.drawEditWindow(of: live.elements, in: live.window, into: ctx.cgContext, rewriting: live.rewriting)
        }
        return rgba(image)
    }

    /// **Asserts the whole claim for one held tick**: the window's picture is the written canvas's
    /// inside the window, and outside it the standing picture is already the written one. Commits.
    private func assertWindowIsExact(_ manager: CanvasManager, _ vector: VectorCanvas,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let standing = rgba(vector.render())
        let live = try XCTUnwrap(manager.liveElementEdit, "an edit is held", file: file, line: line)
        let held = windowPicture(vector, live)
        XCTAssertTrue(manager.commitSelectionEdit(), "the edit changed something", file: file, line: line)
        let written = rgba(vector.render())
        let width = Int(side), window = live.window
        XCTAssertEqual(held.count, Int(window.width * window.height) * 4, "the picture is the window's size",
                       file: file, line: line)
        var insideDiffs = 0, outsideDiffs = 0
        for y in 0..<Int(side) {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if window.contains(CGPoint(x: x, y: y)) {
                    let j = ((y - Int(window.minY)) * Int(window.width) + (x - Int(window.minX))) * 4
                    if (0..<4).contains(where: { abs(Int(held[j + $0]) - Int(written[i + $0])) > 1 }) { insideDiffs += 1 }
                } else if (0..<4).contains(where: { standing[i + $0] != written[i + $0] }) {
                    outsideDiffs += 1
                }
            }
        }
        XCTAssertEqual(insideDiffs, 0, "\(insideDiffs) pixels in the window differ from what the written canvas draws there",
                       file: file, line: line)
        XCTAssertEqual(outsideDiffs, 0, "\(outsideDiffs) pixels outside the window changed — the window does not cover the edit",
                       file: file, line: line)
    }

    // MARK: - A tick writes nothing

    /// **Twenty ticks, no document write, twenty announcements.** The cel's version, its elements and
    /// the history are what they were before the finger went down; `onHeldPictureMoved` is how the
    /// canvas hears each tick, and the live edit's `tick` counts them.
    ///
    /// Mutation caught: `holdElementEdit` writing the list through `restoreElements` (the old tick)
    /// moves `version` on the first tick and every assertion on it goes red.
    func testATickIsHeldOffTheDocumentAndAnnounced() {
        let (manager, _, vector, _) = scene()
        let before = signature(vector.elements)
        let version = vector.version, steps = manager.history.undoStack.count
        var announced = 0
        manager.onHeldPictureMoved = { announced += 1 }

        XCTAssertTrue(manager.beginSelectionEdit(.color))
        let atBegin = announced
        for tick in 1...20 {
            manager.previewSelectionEdit(.color(colour(Double(tick) / 20, 0.5, 0.2)))
            XCTAssertEqual(vector.version, version, "tick \(tick) moved the canvas's version")
            XCTAssertEqual(signature(vector.elements), before, "tick \(tick) wrote the document")
            XCTAssertEqual(manager.history.undoStack.count, steps, "tick \(tick) recorded a step")
        }
        XCTAssertEqual(announced - atBegin, 20, "every tick told the canvas")
        XCTAssertEqual(manager.liveElementEdit?.tick, 20, "and the window counted them")
        XCTAssertEqual(manager.liveElementEdit?.elements.first?.colours.first?.red ?? -1,
                       1, accuracy: 1e-9, "the newest tick is what the window holds")
        manager.cancelSelectionEdit()
    }

    /// **The commit is the one write, and the window goes with it.** One version step, one undo step,
    /// the document holds the list the last tick held, and `liveElementEdit` is nil with the canvas
    /// told.
    ///
    /// Mutation caught: `recordElementEdit` not writing (a held list that only ever lived in the
    /// window) leaves the document at its old colour; writing it twice reads `version + 2`.
    func testTheCommitIsTheOnlyWriteAndTheWindowGoes() {
        let (manager, _, vector, caught) = scene()
        let version = vector.version, steps = manager.history.undoStack.count
        var announced = 0
        manager.onHeldPictureMoved = { announced += 1 }
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        for tick in 1...5 { manager.previewSelectionEdit(.color(colour(Double(tick) / 5, 0, 0))) }
        let heldList = signature(manager.liveElementEdit?.elements ?? [])
        XCTAssertFalse(heldList.isEmpty, "fixture: an edit is held")
        let before = announced

        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(signature(vector.elements), heldList, "the document holds the last tick's list")
        XCTAssertEqual(vector.version, version + 1, "one write")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "one step")
        XCTAssertNil(manager.liveElementEdit, "the window is gone")
        XCTAssertGreaterThan(announced, before, "and the canvas was told, so the host takes it down")
        for id in caught {
            XCTAssertEqual(vector.elements.first { $0.id == id }?.colours.first?.red ?? -1, 1, accuracy: 1e-9)
        }
        manager.undo()
        XCTAssertNotEqual(signature(vector.elements), heldList, "one undo puts the colours back")
    }

    /// **A revert writes nothing, and the window goes.** A drag cancelled by undo, by deselect or by
    /// the call leaves the document exactly as the finger found it.
    func testARevertLeavesTheDocumentUntouchedAndTheWindowGoes() {
        let (manager, _, vector, _) = scene()
        let before = signature(vector.elements), version = vector.version
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        manager.previewSelectionEdit(.color(colour(0, 1, 0)))
        XCTAssertNotNil(manager.liveElementEdit)
        manager.cancelSelectionEdit()
        XCTAssertNil(manager.liveElementEdit)
        XCTAssertEqual(signature(vector.elements), before)
        XCTAssertEqual(vector.version, version, "nothing was ever written, so nothing needed putting back")
    }

    /// **A picker opened and closed untouched shows the canvas a window and leaves no trace.** The
    /// session engages the canvas's live pair at the open (so the first tick is on screen the moment
    /// it lands) and lets it go at the close, and the document, its version and its history never
    /// moved.
    func testAnUntouchedSessionHoldsAWindowAndLeavesNoTrace() {
        let (manager, _, vector, _) = scene()
        let version = vector.version, steps = manager.history.undoStack.count
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        XCTAssertNotNil(manager.liveElementEdit, "the window is up at the open")
        XCTAssertFalse(manager.commitSelectionEdit())
        XCTAssertNil(manager.liveElementEdit)
        XCTAssertEqual(vector.version, version)
        XCTAssertEqual(manager.history.undoStack.count, steps)
    }

    /// **The host is held live while an edit is up and not before or after** — the canvas keeps the
    /// edited layer's host drawing (`heldHostLayerIndices`), exactly as it does for the adjustable
    /// fill, because the baked frame has the old colours in it.
    @MainActor
    func testTheEditedLayersHostIsHeldLiveOnlyWhileTheEditIsUp() {
        let (manager, layerIndex, _, _) = scene()
        XCTAssertEqual(manager.heldHostLayerIndices, [])
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        XCTAssertEqual(manager.heldHostLayerIndices, [layerIndex])
        manager.previewSelectionEdit(.color(colour(0, 1, 0)))
        XCTAssertEqual(manager.heldHostLayerIndices, [layerIndex])
        manager.commitSelectionEdit()
        XCTAssertEqual(manager.heldHostLayerIndices, [])
    }

    // MARK: - The window

    /// **The window is the edit's rectangle, not the canvas.** A recolour of two elements in the top
    /// left of a 256² canvas is a window around those two, which is the whole of why it costs a
    /// window's pixels and not a canvas's.
    func testALocalEditsWindowIsSmallerThanTheCanvasAndContainsTheEditedInk() throws {
        let (manager, _, vector, caught) = scene()
        _ = vector.render()
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        let live = try XCTUnwrap(manager.liveElementEdit)
        XCTAssertLessThan(live.window.width * live.window.height, side * side / 2, "a window, not the canvas")
        XCTAssertEqual(live.window, live.window.integral, "whole pixels, so the clip is not antialiased")
        for id in caught {
            let element = try XCTUnwrap(vector.elements.first { $0.id == id })
            let alone = VectorCanvas(size: vector.size, elements: [element], transform: vector.transform).render()
            let ink = try XCTUnwrap(PixelOps.opaqueContentBounds(alone), "the element has ink")
            XCTAssertTrue(live.window.insetBy(dx: -1, dy: -1).contains(ink), "the window holds \(ink)")
        }
        XCTAssertEqual(live.rewriting, caught)
        manager.cancelSelectionEdit()
    }

    /// **For a recolour the window's picture is exactly what the written canvas draws there**, a
    /// stroke over the fill it recolours included, and outside it the standing picture is already the
    /// written one — the claim the host's hole rests on.
    ///
    /// Mutation caught: `editWindow` answering only the *new* half of a rewrite, or a window cut one
    /// pixel short, leaves changed pixels outside it (`outsideDiffs`); `drawEditWindow` drawing only
    /// the edited ids loses the stroke over the fill (`insideDiffs`).
    func testARecoloursWindowPictureIsTheWrittenCanvasesAndOutsideItNothingChanged() throws {
        let (manager, _, vector, _) = scene()
        _ = vector.render()
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        manager.previewSelectionEdit(.color(colour(0.9, 0.9, 0.1)))
        try assertWindowIsExact(manager, vector)
    }

    /// **For a size drag the window is cut for the widest value the slider reaches**, so a tick at 50
    /// is inside it though the strokes were 10 when it opened — and the picture is still the written
    /// canvas's.
    ///
    /// Mutation caught: sizing the window from the list as found (`extreme: elementsBefore`) leaves
    /// the 50-point ink outside it; a window that grew per tick would remake the surfaces mid-drag.
    func testASizeDragsWindowIsCutForTheWidestValueAndItsPictureIsExact() throws {
        let (manager, _, vector, _) = scene()
        _ = vector.render()
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        let opened = try XCTUnwrap(manager.liveElementEdit).window
        manager.previewSelectionEdit(.size(CGFloat(SelectionEditKind.sizeRange.upperBound)))
        XCTAssertEqual(try XCTUnwrap(manager.liveElementEdit).window, opened, "the window does not grow with the drag")
        try assertWindowIsExact(manager, vector)
    }

    /// An opacity drag, which moves no ink's reach, is exact as well — the fill's alpha and the
    /// stroke's, over each other.
    func testAnOpacityDragsWindowPictureIsExact() throws {
        let (manager, _, vector, _) = scene()
        _ = vector.render()
        XCTAssertTrue(manager.beginSelectionEdit(.opacity))
        manager.previewSelectionEdit(.opacity(0.35))
        try assertWindowIsExact(manager, vector)
    }

    /// **Under Cut the window's list is the split one**: a stroke straddling the loop is two pieces
    /// under fresh ids, and the picture drawn from them is the written canvas's — the seam included.
    func testACutEditsWindowPictureIsExactAcrossTheSplit() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 60, size: 12, colour: colour(0.1, 0.1, 0.8), from: 20, to: 150))
        select(manager, layerIndex, CGRect(x: 100, y: 10, width: 90, height: 100))
        XCTAssertEqual(manager.selectionMembership, .cutting, "fixture: the default rule cuts")
        _ = vector.render()
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        manager.previewSelectionEdit(.color(colour(0.9, 0.2, 0.2)))
        XCTAssertEqual(manager.liveElementEdit?.elements.count, 2, "the held list is the split one")
        XCTAssertEqual(vector.elements.count, 1, "the document is not split yet")
        try assertWindowIsExact(manager, vector)
    }

    // MARK: - A frame the picture cannot be shown on

    /// **Where a group's pose moves part of the cel somewhere the layer's own pose does not, the edit
    /// is held with no window — and the artist is told once.** The picture stays what it was; the
    /// change lands when the finger lifts, as one step, exactly as a shown edit's does.
    ///
    /// Mutation caught: dropping `shownThroughOnePose` draws the window at the layer's pose, which
    /// puts the recoloured stroke where the group's pose is not.
    func testAGroupPosedFrameHoldsTheEditWithNoWindowAndSaysSo() throws {
        let (manager, layerIndex, vector) = fixture()
        let group = UUID()
        var posed = stroke(y: 50, colour: colour(0.1, 0.1, 0.8))
        posed.animationGroupID = group
        vector.addStroke(posed)
        vector.addStroke(stroke(y: 120, colour: colour(0.1, 0.1, 0.1)))
        let box = CGRect(x: 4, y: 24, width: 32, height: 12)
        CanvasFixture.setPoseTrack(manager, layerID: manager.layers[layerIndex].id,
                                   celID: manager.layers[layerIndex].cels[0].id,
                                   channel: .group(group),
                                   CanvasFixture.poseTrack([(0, PoseQuad(restingIn: box)),
                                                            (12, PoseQuad(box: box, mappedBy: .init(translationX: 40, y: 0)))],
                                                           interpolation: .linear))
        manager.currentFrame = 6
        select(manager, layerIndex, CGRect(x: 0, y: 0, width: side, height: side))
        XCTAssertFalse(CanvasManager.poseMaps(vector.elements,
                                              through: CanvasManager.poseMappings(manager.layers[layerIndex].cels[0].transformTracks,
                                                                                  atCelLocalFrame: 6)).isEmpty,
                       "fixture: the group's pose moves one of the two strokes")
        let steps = manager.history.undoStack.count

        XCTAssertTrue(manager.beginSelectionEdit(.color))
        XCTAssertNil(manager.liveElementEdit, "no window: the pictures would not agree about where the ink is")
        XCTAssertNil(manager.notice, "and nothing is said before there is something to say")
        manager.previewSelectionEdit(.color(colour(0.9, 0.9, 0.1)))
        XCTAssertEqual(manager.notice?.kind, .editShownOnRelease, "the first tick says why nothing moves")
        manager.previewSelectionEdit(.color(colour(0.9, 0.5, 0.1)))
        XCTAssertTrue(manager.commitSelectionEdit(), "the edit still lands")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "as one step")
        XCTAssertEqual(vector.elements.compactMap(\.stroke).map(\.color.green), [0.5, 0.5],
                       "on both strokes, at the last tick's value")
    }

    /// **A cel posed as one is still shown**: every element is carried by the same map the layer is
    /// shown through, so the window's picture goes where the base's does.
    func testACelPosedAsOneStillHasAWindow() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 50, colour: colour(0.1, 0.1, 0.8)))
        let box = CGRect(x: 4, y: 24, width: 32, height: 12)
        CanvasFixture.setPoseTrack(manager, layerID: manager.layers[layerIndex].id,
                                   celID: manager.layers[layerIndex].cels[0].id, channel: .cel,
                                   CanvasFixture.poseTrack([(0, PoseQuad(restingIn: box)),
                                                            (12, PoseQuad(box: box, mappedBy: .init(translationX: 40, y: 0)))],
                                                           interpolation: .linear))
        manager.currentFrame = 6
        select(manager, layerIndex, CGRect(x: 0, y: 0, width: side, height: side))
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        XCTAssertNotNil(manager.liveElementEdit)
        manager.cancelSelectionEdit()
    }

    // MARK: - The gradient panel

    /// **The gradient panel is the same edit**: its ticks are held off the document, the panel reads
    /// what it holds, and closing it is the one write and the one step.
    func testTheGradientPanelHoldsItsTicksAndWritesOnClose() throws {
        let (manager, _, vector) = fixture()
        let gradient = LinearGradientPaint(start: colour(0, 0, 0), end: colour(1, 1, 1),
                                           from: CGPoint(x: 20, y: 100), to: CGPoint(x: 120, y: 100))
        let element = VectorFillElement(path: CGPath(rect: CGRect(x: 20, y: 60, width: 100, height: 80), transform: nil),
                                        paint: .linearGradient(gradient))
        vector.addFill(element)
        let before = signature(vector.elements), version = vector.version, steps = manager.history.undoStack.count
        XCTAssertTrue(manager.beginGradientEdit(elementID: element.id))
        XCTAssertNotNil(manager.liveElementEdit, "the panel's window is up")

        manager.setGradientAngle(.pi / 2)
        manager.setGradientColour(.start, to: .red)
        XCTAssertEqual(vector.version, version, "no tick wrote the cel")
        XCTAssertEqual(signature(vector.elements), before)
        XCTAssertEqual(try XCTUnwrap(manager.editedGradient).angle, .pi / 2, accuracy: 1e-6,
                       "the panel reads what the window holds")
        XCTAssertEqual(manager.history.undoStack.count, steps)

        XCTAssertTrue(manager.commitGradientEdit())
        XCTAssertNil(manager.liveElementEdit)
        XCTAssertEqual(vector.version, version + 1, "one write")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "one step")
        XCTAssertEqual(try XCTUnwrap(vector.elements.first?.fill?.gradient).angle, .pi / 2, accuracy: 1e-6)
    }
}
