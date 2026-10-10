import XCTest
import UIKit

/// **Which hosts draw themselves on an engaged canvas, and how the rest of the frame is drawn around
/// them** — TODO (160).
///
/// The owner, 2026-10-10: *"when I have a drawing guide on the bottom of my drawing disappears if i
/// try to lasso move … If i also have my drawing guide over the drawing and draw, it again
/// disappears"*. The drawing guide is the Guide effect on a value layer (TODO (88)): lines graded
/// over whatever the layer sits on, nothing where nothing is. Both halves of the report are decisions
/// made in the model and read by `CanvasView.Coordinator` in a file this target does not compile:
///
/// - a floating piece keeps the compositor — the live pair is cut around the hosts that carry it
///   (`liveHostRun`, `floatHostLayerIndices`), so a guide below stays in the picture;
/// - the hosts sit between two halves only where the layers above them composite onto transparency
///   exactly; where something above blends or grades, the rest of the frame is one picture with the
///   hosts' leaves hidden and the hosts draw over it (`liveHostsSitBetweenTheHalves`,
///   `makeSandwichRecipe(atFrame:over:)`), so a guide above stays too.
///
/// `SandwichPresentationLogicTests` owns what the canvas then shows; `GuideUnderLassoMoveUITests` and
/// `GuideOverStrokeUITests` own the pixels.
@MainActor
final class SandwichLiveHostsLogicTests: XCTestCase {

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    private func stroke(y: CGFloat) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                     samples: [VectorSample(x: 12, y: y, pressure: 1),
                               VectorSample(x: 32, y: y, pressure: 1),
                               VectorSample(x: 52, y: y, pressure: 1)])
    }

    /// Bottom to top: a guide, the drawing (active), a guide — a vector line each, at its own height.
    private struct Stack {
        let manager: CanvasManager
        let below: Int, drawing: Int, above: Int
        var tree: [RenderNode] { manager.renderTree(atFrame: 0) }
    }

    private func guideStack() -> Stack {
        let manager = CanvasFixture.manager(layerCount: 0)
        for (name, y) in [("guide below", CGFloat(12)), ("drawing", CGFloat(32)), ("guide above", CGFloat(52))] {
            manager.addVectorLayer(name: name)
            manager.layers[manager.currentLayerIndex].cels[0].vector?.addStroke(stroke(y: y))
        }
        let index = { (name: String) in manager.layers.firstIndex { $0.name == name } ?? -1 }
        let stack = Stack(manager: manager, below: index("guide below"), drawing: index("drawing"),
                          above: index("guide above"))
        manager.currentLayerIndex = stack.drawing
        XCTAssertEqual([stack.below, stack.drawing, stack.above], [0, 1, 2], "PREMISE: added bottom to top")
        return stack
    }

    // MARK: - (a) A floating piece is carried by the sandwich

    /// **A lasso float on a canvas the compositor draws keeps the compositor**, and its host is the
    /// live pair's middle — so both guides are in a half for the whole move. Watched failing with the
    /// float clause restored to `sandwichEngagesOnCanvas`.
    func testALassoFloatKeepsTheCompositorAndOnlyItsHostDrawsItself() {
        let s = guideStack()
        s.manager.setLayerBlendMode(layerIndex: s.above, to: .multiply)
        XCTAssertTrue(s.manager.sandwichEngagesOnCanvas(tree: s.tree), "PREMISE: a Multiply guide engages it")
        s.manager.selection = Selection(path: CGPath(rect: CGRect(x: 4, y: 24, width: 56, height: 16), transform: nil),
                                        bounds: CGRect(x: 4, y: 24, width: 56, height: 16),
                                        layerID: s.manager.layers[s.drawing].id,
                                        celID: s.manager.layers[s.drawing].cels[0].id)
        XCTAssertTrue(s.manager.beginVectorLassoMove(), "PREMISE: the loop catches the drawing's line")
        XCTAssertNotNil(s.manager.vectorFloat)

        XCTAssertTrue(s.manager.sandwichEngagesOnCanvas(tree: s.tree),
                      "a float must not take the compositor away: that is what dropped the guides' blend and "
                      + "made every host repaint at the lift")
        XCTAssertEqual(s.manager.floatHostLayerIndices, [s.drawing])
        XCTAssertEqual(s.manager.liveHostRun(tree: s.tree), [s.drawing],
                       "the guides stay in the halves; only the float's host draws itself")
    }

    /// **A folder's float names every host it rides in**, wherever the active layer is — the run spans
    /// them all, so a part is never blanked under a half that still holds its un-lifted ink.
    func testAFolderFloatsPartsAreAllDrawnByTheirHosts() {
        let s = guideStack()
        let folder = s.manager.addFolder(name: "Guides")
        s.manager.layers[s.below].parentFolderID = folder
        s.manager.layers[s.drawing].parentFolderID = folder
        s.manager.currentLayerIndex = s.above
        s.manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 1.2, contrast: 1.5)))
        let top = s.manager.currentLayerIndex
        XCTAssertEqual(top, 3, "PREMISE: the effect lands on top, outside the folder")
        XCTAssertTrue(s.manager.beginVectorFolderMove(folder), "PREMISE: the folder lifts")
        s.manager.currentLayerIndex = top
        let parts = Set(s.manager.floatHostLayerIndices)
        XCTAssertEqual(parts, [s.below, s.drawing])
        XCTAssertTrue(s.manager.sandwichEngagesOnCanvas(tree: s.tree))
        XCTAssertTrue(parts.isSubset(of: s.manager.liveHostRun(tree: s.tree)),
                      "a part outside the run would be blanked, its piece with it")
    }

    /// **A raster Move's source draws the hole the cel does not have yet** (`remainderPreview`), so it
    /// is the middle as well; the cel itself still holds the lifted pixels, which is why no half may.
    func testARasterMovesSourceIsDrawnByItsHost() {
        let manager = CanvasFixture.manager(layerCount: 3)
        for index in 0..<3 {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(.black, rect: CGRect(x: 8, y: 8 + index * 16,
                                                                                        width: 40, height: 8)))
        }
        manager.setLayerBlendMode(layerIndex: 2, to: .multiply)
        manager.currentLayerIndex = 1
        manager.selection = Selection(path: CGPath(rect: CGRect(x: 4, y: 20, width: 56, height: 16), transform: nil),
                                      bounds: CGRect(x: 4, y: 20, width: 56, height: 16),
                                      layerID: manager.layers[1].id, celID: manager.layers[1].cels[0].id)
        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .move, "PREMISE: a raster lift")
        let tree = manager.renderTree(atFrame: 0)
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree))
        XCTAssertEqual(manager.floatHostLayerIndices, [1])
        XCTAssertEqual(manager.liveHostRun(tree: tree), [1])
    }

    /// A transformation layer's box holds no pixels — the composite itself moves under it, as bands —
    /// so it names no host and the run is the active layer's alone.
    func testABoxWithNoPixelsNamesNoHost() {
        let s = guideStack()
        s.manager.addTransformLayer()
        XCTAssertTrue(s.manager.beginContainerPoseMove(), "PREMISE: the transformation layer's box comes up")
        XCTAssertEqual(s.manager.floatingPiece?.kind, .containerPose)
        XCTAssertEqual(s.manager.floatHostLayerIndices, [])
    }

    // MARK: - (b) Between the halves, or over the rest of the frame

    /// `liveHostsSitBetweenTheHalves` for the run the canvas would cut around now.
    private func sitsBetween(_ s: Stack) -> Bool {
        s.manager.liveHostsSitBetweenTheHalves(s.manager.liveHostRun(tree: s.tree), in: s.tree)
    }

    /// **Plain layers above: the hosts sit exactly beneath them**, between the halves — source-over is
    /// associative, so the upper half over transparency is the picture.
    func testTheHostsSitBetweenPlainLayersAbove() {
        let s = guideStack()
        XCTAssertTrue(sitsBetween(s))
        s.manager.layers[s.above].opacity = 0.4
        XCTAssertTrue(sitsBetween(s),
                      "a faded guide is still source-over, at its own alpha")
        s.manager.addValueLayer()
        XCTAssertTrue(sitsBetween(s),
                      "a flat colour above is an opaque leaf like any other")
    }

    /// **A blend mode above: the upper half blends against nothing**, so the hosts draw over the rest.
    /// Watched failing with the predicate answering `true` unconditionally.
    func testTheHostsGoOverABlendingLayerAbove() {
        let s = guideStack()
        s.manager.setLayerBlendMode(layerIndex: s.above, to: .multiply)
        XCTAssertFalse(sitsBetween(s))
    }

    /// **An effect above grades nothing over transparency** — the drawing Guide draws its lines over
    /// nothing at all — so the hosts draw over the rest.
    func testTheHostsGoOverAnEffectAbove() {
        let s = guideStack()
        s.manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 1.2, contrast: 1.5)))
        s.manager.currentLayerIndex = s.drawing
        XCTAssertFalse(sitsBetween(s))
    }

    /// **Only what is above matters.** A blended or graded layer *below* is in the lower half, which is
    /// composited over the paper exactly; a transformation layer above poses and draws nothing.
    func testWhatIsBelowTheHostsAndAPoseAboveThemDoNotMoveThem() {
        let s = guideStack()
        s.manager.setLayerBlendMode(layerIndex: s.below, to: .multiply)
        XCTAssertTrue(sitsBetween(s))
        s.manager.addTransformLayer()
        s.manager.currentLayerIndex = s.drawing
        XCTAssertTrue(sitsBetween(s))
    }

    /// **A faded folder around the hosts** fades once per half when cut (`cut(around:)`'s part-group),
    /// so its upper part over transparency is not the picture either.
    func testHostsInsideAFadedFolderWithLayersAboveThemGoOver() {
        let s = guideStack()
        let folder = s.manager.addFolder(name: "Faded")
        s.manager.layers[s.drawing].parentFolderID = folder
        s.manager.layers[s.above].parentFolderID = folder
        s.manager.setFolderOpacity(folder, to: 0.5)
        s.manager.currentLayerIndex = s.drawing
        XCTAssertFalse(sitsBetween(s))
    }

    // MARK: - The picture the hosts draw over

    /// **The rest of the frame, exactly**: the over recipe's one band composites to the picture of the
    /// same document with the hosts' layer switched off — a folder spanning the hosts buffers once and
    /// fades once, and the effect above grades everything else. Watched failing with `hidingLeaves`
    /// replaced by the two halves of `cut(around:)` laid one over the other, which fades the folder once
    /// per half and lets the black under the red show through.
    func testThePictureUnderTheHostsIsTheFrameWithoutThem() throws {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 8, y: 8, width: 40, height: 12)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 8, y: 40, width: 40, height: 8)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 8, y: 8, width: 40, height: 12)))
        let folder = manager.addFolder(name: "Faded")
        for index in 0..<3 { manager.layers[index].parentFolderID = folder }
        manager.setFolderOpacity(folder, to: 0.5)
        manager.currentLayerIndex = 2
        manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 1.2, contrast: 0.8)))
        manager.layers[manager.currentLayerIndex].parentFolderID = nil
        manager.currentLayerIndex = 1
        let tree = manager.renderTree(atFrame: 0)
        let run = manager.liveHostRun(tree: tree)
        XCTAssertEqual(run, [1])
        XCTAssertFalse(manager.liveHostsSitBetweenTheHalves(run, in: tree), "PREMISE: a faded folder spans the host")

        let recipe = try XCTUnwrap(manager.makeSandwichRecipe(atFrame: 0, over: run))
        XCTAssertEqual(recipe.bands.count, 1, "one picture, no halves")
        let over = try XCTUnwrap(recipe.compositeBands()?.first ?? nil)
        let whole = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: true)
            .flatMap(Compositor.composite))

        manager.layers[1].isVisible = false
        let without = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: true)
            .flatMap(Compositor.composite))
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(over)), b = try XCTUnwrap(CanvasFixture.rgbaBytes(without))
        XCTAssertEqual(a.count, b.count, "one size")
        let delta = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 255
        XCTAssertLessThanOrEqual(delta, 1, "the picture the hosts draw over is the frame with their layer off")
        // PREMISE that the comparison could fail: the host's own line is in the whole frame, here.
        let w = try XCTUnwrap(CanvasFixture.rgbaBytes(whole))
        let line = ((40 + 4) * Int(over.width) + 20) * 4
        XCTAssertGreaterThan(abs(Int(w[line]) - Int(a[line])), 32, "the host's line is not in the picture under it")
    }

    /// A run that is not in the tree makes no picture rather than one with the run's ink drawn twice.
    func testNoPictureForAHostThatIsNotALeaf() {
        let s = guideStack()
        s.manager.layers[s.drawing].isVisible = false
        XCTAssertNotNil(s.manager.makeSandwichRecipe(atFrame: 0, over: [s.drawing]), "hidden is still a leaf")
        XCTAssertNil(s.manager.makeSandwichRecipe(atFrame: 0, over: []))
        XCTAssertNil(s.manager.makeSandwichRecipe(atFrame: 0, over: [99]))
    }
}
