import XCTest
import CoreGraphics
import UIKit

/// **One mechanism for a transform being edited** — TODO (125), (136) and (140): what moves, how far,
/// what the canvas cuts the frame into while it does, and that the baker waits for the finger.
///
/// The coordinator that draws the bands (`CanvasView.Coordinator.showMovingBands`) is not compiled
/// into this target, so everything it decides from is a model answer, and these are their pins. The
/// one claim that is about pixels — a band composited once and re-posed by the delta the maps give is
/// the frame the compositor would have drawn at the new pose — is asserted on pixels, at both ends.
@MainActor
final class LiveTransformEditLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var canvasBox: CGRect { CGRect(origin: .zero, size: size) }

    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func stroke(y: CGFloat, from x0: CGFloat = 6, to x1: CGFloat = 30) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: StrokeSamples([VectorSample(x: x0, y: y, pressure: 1),
                                             VectorSample(x: x1, y: y, pressure: 1)],
                                            channels: .pressureOnly))
    }

    /// A vector layer named `name`, holding one bar at `y` over twelve frames.
    @discardableResult
    private func addInk(_ manager: CanvasManager, _ name: String, y: CGFloat) -> UUID {
        manager.addVectorLayer(name: name)
        let index = manager.currentLayerIndex
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke(y: y))
        manager.layers[index].cels = [cel]
        return manager.layers[index].id
    }

    private func index(_ id: UUID, _ manager: CanvasManager) -> Int {
        manager.layers.firstIndex { $0.id == id } ?? -1
    }

    private func pose(_ transform: CGAffineTransform) -> LayerPose {
        LayerPose(pose: PoseQuad(box: canvasBox, mappedBy: transform))
    }

    /// Bottom to top: `floor` (root), folder `F` holding `inner` and `innerToo`, `mover` (a
    /// transformation layer, root), `above` (root). So `mover` poses `floor` and the folder's two —
    /// everything beneath it in its own container — and not `above`.
    private struct Scene {
        let manager: CanvasManager
        let floor: UUID, inner: UUID, innerToo: UUID, mover: UUID, above: UUID
    }

    private func scene(_ moverPose: LayerPose = LayerPose(pose: PoseQuad(restingIn: CGRect(origin: .zero,
                                                                                            size: CanvasFixture.canvasSize))))
    -> Scene {
        let manager = CanvasManager()
        manager.canvasSize = size
        let floor = addInk(manager, "floor", y: 8)
        let inner = addInk(manager, "inner", y: 20)
        let innerToo = addInk(manager, "innerToo", y: 32)
        manager.addTransformLayer(name: "mover")
        let mover = manager.layers[manager.currentLayerIndex].id
        let above = addInk(manager, "above", y: 50)
        let folder = manager.addFolder(name: "F")
        manager.layers[index(inner, manager)].parentFolderID = folder
        manager.layers[index(innerToo, manager)].parentFolderID = folder
        manager.layers[index(mover, manager)].transform = moverPose
        manager.currentFrame = 0
        return Scene(manager: manager, floor: floor, inner: inner, innerToo: innerToo, mover: mover, above: above)
    }

    private func ids(_ runs: [[Int]], _ manager: CanvasManager) -> [[UUID]] {
        runs.map { $0.map { manager.layers[$0].id } }
    }

    private func maxChannelDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard let x = CanvasFixture.rgbaBytes(a), let y = CanvasFixture.rgbaBytes(b), x.count == y.count else {
            return .max
        }
        return x.indices.reduce(0) { max($0, abs(Int(x[$1]) - Int(y[$1]))) }
    }

    // MARK: - What moves

    /// A transformation layer moves everything beneath it in its own container — a folder's whole
    /// subtree with it — as one run, in the frame's leaf order; never what is above it.
    func testATransformLayerMovesEverythingBeneathItAsOneRun() {
        let s = scene()
        let runs = s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0)
        XCTAssertEqual(ids(runs, s.manager), [[s.floor, s.inner, s.innerToo]])
        XCTAssertEqual(Array(runs.joined()), s.manager.renderTree(atFrame: 0).leafLayerIndices
            .filter { runs.joined().contains($0) }, "in the order the frame evaluates them")
    }

    /// **Parallax shares its pose out per item**, so each item is a run of its own — and the folder,
    /// one item, is one run however many leaves it holds.
    func testAParallaxLayerMovesEachItemAsItsOwnRun() {
        let s = scene()
        s.manager.layers[index(s.mover, s.manager)].transform?.mode = .parallax
        let runs = s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0)
        XCTAssertEqual(ids(runs, s.manager), [[s.floor], [s.inner, s.innerToo]])
    }

    /// A grade or a flat colour is not posed, so it stays put between two runs that move as one.
    func testAPixelLessLayerBeneathSplitsTheRunAndStaysPut() {
        let manager = CanvasManager()
        manager.canvasSize = size
        let low = addInk(manager, "low", y: 8)
        manager.addValueLayer(name: "grade")
        let grade = manager.layers[manager.currentLayerIndex].id
        let high = addInk(manager, "high", y: 30)
        manager.addTransformLayer(name: "mover")
        let mover = manager.layers[manager.currentLayerIndex].id
        let runs = manager.liveTransformRuns(.container(layerID: mover), atFrame: 0)
        XCTAssertEqual(ids(runs, manager), [[low], [high]])
        XCTAssertFalse(runs.joined().contains(index(grade, manager)))
    }

    /// Where the layer poses nothing — its eye shut, a frame its bar does not cover, a Repeat —
    /// nothing moves, the same gates `renderNodes` applies.
    func testNothingMovesWhereTheLayerPosesNothing() {
        var s = scene()
        s.manager.layers[index(s.mover, s.manager)].isVisible = false
        XCTAssertEqual(s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0), [], "eye shut")

        s = scene()
        let block = s.manager.layers[index(s.mover, s.manager)].cels[0]
        XCTAssertEqual(s.manager.liveTransformRuns(.container(layerID: s.mover),
                                                   atFrame: block.startFrame + block.frameCount + 3), [],
                       "past its bar")

        s = scene()
        s.manager.layers[index(s.mover, s.manager)].transform?.mode = .repeat
        XCTAssertEqual(s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0), [], "a Repeat")
    }

    func testACelChannelMovesItsOwnLayerAndAFloatingPieceNothing() {
        let s = scene()
        XCTAssertEqual(ids(s.manager.liveTransformRuns(.cel(layerID: s.inner), atFrame: 0), s.manager),
                       [[s.inner]])
        XCTAssertEqual(s.manager.liveTransformRuns(.cel(layerID: s.mover), atFrame: 0), [],
                       "a transformation layer holds no drawing of its own")
        XCTAssertEqual(s.manager.liveTransformRuns(.floatingPiece, atFrame: 0), [],
                       "a floating piece draws its own picture")
    }

    // MARK: - How far

    /// **The delta a band is re-posed by is exactly the edit**: a stored base moved by (8, 4) gives a
    /// map at the mint and a map now whose difference is (8, 4) — read off a leaf inside the folder,
    /// so the inner-first composition is exercised.
    func testTheMapsDifferByExactlyTheEdit() throws {
        let s = scene()
        let runs = s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0)
        let minted = s.manager.liveTransformMaps(.container(layerID: s.mover), runs: runs, atFrame: 0)
        s.manager.layers[index(s.mover, s.manager)].transform = pose(CGAffineTransform(translationX: 8, y: 4))
        let now = s.manager.liveTransformMaps(.container(layerID: s.mover), runs: runs, atFrame: 0)
        let delta = try XCTUnwrap(minted[0].inverse?.concatenating(now[0]).affine)
        XCTAssertEqual(delta.tx, 8, accuracy: 1e-6)
        XCTAssertEqual(delta.ty, 4, accuracy: 1e-6)
        XCTAssertEqual(delta.a, 1, accuracy: 1e-9)
        XCTAssertEqual(delta.d, 1, accuracy: 1e-9)
    }

    /// A cel's whole-drawing channel reads through `inkPose`, so it sees the cel's own key.
    func testACelChannelsMapIsTheCelsOwnPose() throws {
        let s = scene()
        let inner = index(s.inner, s.manager)
        let runs = s.manager.liveTransformRuns(.cel(layerID: s.inner), atFrame: 0)
        let minted = s.manager.liveTransformMaps(.cel(layerID: s.inner), runs: runs, atFrame: 0)
        s.manager.layers[inner].cels[0].transformTracks = [TransformChannelID.cel.id: TransformTrack(keys: [
            .init(frame: 0, pose: PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: -5, y: 3)))])]
        let now = s.manager.liveTransformMaps(.cel(layerID: s.inner), runs: runs, atFrame: 0)
        let delta = try XCTUnwrap(minted[0].inverse?.concatenating(now[0]).affine)
        XCTAssertEqual(delta.tx, -5, accuracy: 1e-6)
        XCTAssertEqual(delta.ty, 3, accuracy: 1e-6)
    }

    // MARK: - The bands

    /// **The cut**: two runs give five bands, static and moving in turn, and a run that is not one
    /// span of the leaf order — or runs out of order — is refused rather than cut wrong.
    func testTheCutIsStaticAndMovingBandsInTurn() throws {
        let s = scene()
        let tree = s.manager.renderTree(atFrame: 0)
        let order = tree.leafLayerIndices
        let bands = try XCTUnwrap(tree.cut(around: [[order[1]], [order[3]]]))
        XCTAssertEqual(order.count, 5, "PREMISE: floor, inner, innerToo, the transformation layer, above")
        XCTAssertEqual(bands.map(\.leafLayerIndices), [[order[0]], [order[1]], [order[2]], [order[3]], [order[4]]])
        XCTAssertNil(tree.cut(around: [[order[1], order[3]]]), "a run with a gap in it")
        XCTAssertNil(tree.cut(around: [[order[3]], [order[1]]]), "runs out of order")
        XCTAssertNil(tree.cut(around: [[99]]), "a leaf that is not in the frame")
    }

    /// **The identity the mechanism stands on**: the bands of a normal stack, composited one by one
    /// and laid over each other, are the frame — byte for byte. Anything less and the drag would
    /// start with a jump.
    func testTheBandsRecomposeToTheFrame() throws {
        let s = scene()
        let runs = s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0)
        let recipe = try XCTUnwrap(s.manager.makeSandwichRecipe(atFrame: 0, runs: runs))
        let exact = try XCTUnwrap(Compositor.composite(recipe.resolve().full))
        let bands = try XCTUnwrap(recipe.compositeBands())
        XCTAssertEqual(bands.count, 3)
        let laid = try XCTUnwrap(lay(bands, deltas: [:]))
        XCTAssertEqual(maxChannelDelta(laid, exact), 0)
    }

    /// **The claim, on pixels**: a band minted at rest and re-posed by the delta the maps give is the
    /// frame the compositor draws at the new pose. A whole-pixel translation is exact; a turn is the
    /// bitmap resample the owner ruled acceptable under the finger, so it is held to where the ink
    /// lands rather than to its bytes. If the delta were the wrong way round, or measured from the
    /// wrong leaf, the ink would land elsewhere and both would go red.
    func testABandRePosedByTheDeltaIsTheFrameAtTheNewPose() throws {
        for (name, edit, exactBytes) in [("a slide", CGAffineTransform(translationX: 8, y: 4), true),
                                         ("a turn", CGAffineTransform(translationX: 32, y: 32)
                                            .rotated(by: .pi / 10).translatedBy(x: -32, y: -32), false)] {
            let s = scene()
            let mover = index(s.mover, s.manager)
            let runs = s.manager.liveTransformRuns(.container(layerID: s.mover), atFrame: 0)
            let recipe = try XCTUnwrap(s.manager.makeSandwichRecipe(atFrame: 0, runs: runs))
            let minted = s.manager.liveTransformMaps(.container(layerID: s.mover), runs: runs, atFrame: 0)
            let bands = try XCTUnwrap(recipe.compositeBands())

            s.manager.layers[mover].transform = pose(edit)
            PixelOps.clearRasterizeCache()
            let now = s.manager.liveTransformMaps(.container(layerID: s.mover), runs: runs, atFrame: 0)
            let delta = try XCTUnwrap(minted[0].inverse?.concatenating(now[0]).affine)
            let laid = try XCTUnwrap(lay(bands, deltas: [1: delta]))
            let rerendered = try XCTUnwrap(s.manager.makeRenderRequest(atFrame: 0, includeBackground: true)
                                            .flatMap(Compositor.composite))
            let difference = maxChannelDelta(laid, rerendered)
            print("[liveTransform] \(name): max channel delta, re-posed band against the re-render: \(difference)")
            if exactBytes {
                XCTAssertEqual(difference, 0, name)
            } else {
                let shown = try XCTUnwrap(PixelOps.opaqueContentBounds(UIImage(cgImage: inkOnly(laid))))
                let truth = try XCTUnwrap(PixelOps.opaqueContentBounds(UIImage(cgImage: inkOnly(rerendered))))
                XCTAssertEqual(shown.midX, truth.midX, accuracy: 1.5, name)
                XCTAssertEqual(shown.midY, truth.midY, accuracy: 1.5, name)
            }
        }
    }

    /// The bands laid bottom to top, the band at each index in `deltas` drawn through its delta in
    /// canvas space — what `showMovingBands` asks Core Animation to do.
    private func lay(_ bands: [CGImage?], deltas: [Int: CGAffineTransform]) -> CGImage? {
        UIGraphicsImageRenderer(bounds: canvasBox, format: PixelOps.transparentFormat()).image { context in
            for (index, band) in bands.enumerated() {
                guard let band else { continue }
                context.cgContext.saveGState()
                if let delta = deltas[index] { context.cgContext.concatenate(delta) }
                UIImage(cgImage: band, scale: 1, orientation: .up).draw(in: canvasBox)
                context.cgContext.restoreGState()
            }
        }.cgImage
    }

    /// Everything darker than the paper, as alpha: the ink's footprint, whichever band it came from.
    private func inkOnly(_ image: CGImage) -> CGImage {
        guard var bytes = CanvasFixture.rgbaBytes(image) else { return image }
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let dark = bytes[pixel] < 128
            for channel in 0..<4 { bytes[pixel + channel] = dark ? 255 : 0 }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    // MARK: - The baker waits for the finger

    /// The owner's *"pause the background renderer until the user raises their pen off the move
    /// tool"*: the sweep still marks what is dirty, and nothing is composited until the edit ends.
    func testTheBakerHoldsWhileAnEditIsLiveAndResumesWhenItEnds() {
        let s = scene()
        s.manager.syncFrameBake(suspended: false)
        XCTAssertFalse(s.manager.frameBaker.isSuspended, "PREMISE: a document at rest bakes")
        s.manager.beginLiveTransformEdit(.container(layerID: s.mover))
        s.manager.syncFrameBake(suspended: false)
        XCTAssertTrue(s.manager.frameBaker.isSuspended, "a transform under the finger holds the baker")
        s.manager.endLiveTransformEdit()
        s.manager.syncFrameBake(suspended: false)
        XCTAssertFalse(s.manager.frameBaker.isSuspended, "and the pass that ends it lets it bake the result")
    }

    // MARK: - The entry points' answers

    func testTheMoveBoxEditsWhatItHolds() throws {
        let s = scene()
        s.manager.currentLayerIndex = index(s.mover, s.manager)
        XCTAssertNil(s.manager.moveBoxEdit, "no box, no edit")
        XCTAssertTrue(s.manager.beginContainerPoseMove())
        XCTAssertEqual(s.manager.moveBoxEdit, .container(layerID: s.mover))
        _ = s.manager.commitFloatingPieceIfNeeded()

        let folder = try XCTUnwrap(s.manager.folders.first?.id)
        XCTAssertTrue(s.manager.beginVectorFolderMove(folder))
        XCTAssertEqual(s.manager.moveBoxEdit, .floatingPiece, "a folder's Move draws its own picture")
    }

    func testTheGraphEditorEditsOnePosesSubjectOrNothing() {
        let layer = KeyframeTarget.layer(id: UUID())
        guard case .layer(let id) = layer else { return }
        let manager = CanvasManager()
        let group = "poseGroup-\(UUID().uuidString).x"
        XCTAssertEqual(manager.graphBandEdit(target: layer, parameterIDs: ["containerPose.x", "containerPose.y"]),
                       .container(layerID: id))
        XCTAssertEqual(manager.graphBandEdit(target: layer, parameterIDs: ["celPose.rotation"]), .cel(layerID: id))
        XCTAssertNil(manager.graphBandEdit(target: layer, parameterIDs: [group]),
                     "an animation group moves part of a cel, which no band holds alone")
        XCTAssertNil(manager.graphBandEdit(target: layer, parameterIDs: ["brightnessContrast.brightness"]),
                     "a grade moves nothing")
        XCTAssertNil(manager.graphBandEdit(target: layer, parameterIDs: ["containerPose.x", "celPose.x"]),
                     "two subjects are not one band")
        XCTAssertNil(manager.graphBandEdit(target: .folder(id: id), parameterIDs: ["containerPose.x"]))
    }

    // MARK: - The compositor stays on

    /// **The transformation layer's box keeps the compositor** — it holds no picture, and leaving
    /// for the flat row is what re-rasterized every posed drawing per tick — while a box over lifted
    /// pixels or ink still leaves it. And a live edit engages a document that otherwise would not be.
    func testATransformLayersBoxKeepsTheCompositorAndAFloatDoesNot() throws {
        let s = scene(pose(CGAffineTransform(translationX: 4, y: 0)))
        s.manager.currentLayerIndex = index(s.mover, s.manager)
        XCTAssertTrue(s.manager.beginContainerPoseMove())
        XCTAssertTrue(s.manager.sandwichEngagesOnCanvas(tree: s.manager.renderTree(atFrame: 0)))
        _ = s.manager.commitFloatingPieceIfNeeded()

        XCTAssertTrue(s.manager.beginVectorFolderMove(try XCTUnwrap(s.manager.folders.first?.id)))
        XCTAssertFalse(s.manager.sandwichEngagesOnCanvas(tree: s.manager.renderTree(atFrame: 0)))

        let plain = scene()
        let tree = plain.manager.renderTree(atFrame: 0)
        XCTAssertFalse(plain.manager.sandwichEngagesOnCanvas(tree: tree), "PREMISE: nothing poses yet")
        plain.manager.beginLiveTransformEdit(.container(layerID: plain.mover))
        XCTAssertTrue(plain.manager.sandwichEngagesOnCanvas(tree: tree), "its first drag is drawn by bands")
        plain.manager.beginLiveTransformEdit(.floatingPiece)
        XCTAssertFalse(plain.manager.sandwichEngagesOnCanvas(tree: tree))
    }
}
