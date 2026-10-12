import Combine
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
        s.manager.layers[inner].cels[0].transformTracks = [TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: -5, y: 3)))])]
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

    // MARK: - The pose under the finger — TODO (154)

    private var containerX: String { PoseChannelID.container.parameterID(.x) }

    private func xCurve(_ value: Double) -> AnimationCurve {
        AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: value)])
    }

    /// The scene with `mover` keyed on X, at rest, at frame 0 — a node a graph drag can carry.
    private func keyedScene() -> Scene {
        let s = scene()
        s.manager.layers[index(s.mover, s.manager)].transform?.track =
            TransformTrack(box: canvasBox, curves: [.x: xCurve(canvasBox.midX)])
        return s
    }

    private func tx(from minted: PoseMap, to now: PoseMap) throws -> CGFloat {
        try XCTUnwrap(minted.inverse?.concatenating(now).affine).tx
    }

    /// **A graph drag's tick moves the bands and nothing else** — the owner's *"still very laggy"*:
    /// each tick used to write the pose into `layers`, six `objectWillChange`s and a SwiftUI pass over
    /// the whole editor. Held, the canvas is told directly, the document does not move, and the walk
    /// under the held pose is the drag's own distance from the mint.
    func testAHeldPoseMovesTheBandsAndPublishesNothing() throws {
        let s = keyedScene()
        let edit = LiveTransformEdit.container(layerID: s.mover)
        let runs = s.manager.liveTransformRuns(edit, atFrame: 0)
        let minted = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0)
        let stored = s.manager.layers[index(s.mover, s.manager)].transform
        s.manager.beginLiveTransformEdit(edit)

        var publishes = 0, told = 0
        let token = s.manager.objectWillChange.sink { _ in publishes += 1 }
        s.manager.onHeldPictureMoved = { told += 1 }
        for dx in [2.0, 5.0, 8.0] {
            s.manager.holdLivePose([containerX: xCurve(canvasBox.midX + dx)], of: .layer(id: s.mover))
        }
        token.cancel()

        XCTAssertEqual(publishes, 0, "a tick held off the document raises no SwiftUI pass")
        XCTAssertEqual(told, 3, "and the canvas hears every tick directly")
        XCTAssertEqual(s.manager.layers[index(s.mover, s.manager)].transform, stored,
                       "the document does not hold the pose under the finger")
        let held = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0, holding: s.manager.liveEdit)
        XCTAssertEqual(try tx(from: minted[0], to: held[0]), 8, accuracy: 1e-6,
                       "the bands are re-posed by the drag's whole distance — read inside the folder too")
        let document = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0)
        XCTAssertEqual(try tx(from: minted[0], to: document[0]), 0, accuracy: 1e-9,
                       "and a mint, which reads the document alone, still sees the pose at rest")
    }

    /// **The lift writes the held pose, as one press of Undo** — and what the document then shows is
    /// what the finger was showing.
    func testTheLiftWritesTheHeldPoseAsOneUndoStep() throws {
        let s = keyedScene()
        let edit = LiveTransformEdit.container(layerID: s.mover)
        let runs = s.manager.liveTransformRuns(edit, atFrame: 0)
        let minted = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0)
        let mover = index(s.mover, s.manager)
        let steps = s.manager.history.undoStack.count
        s.manager.beginLiveTransformEdit(edit)
        s.manager.holdLivePose([containerX: xCurve(canvasBox.midX + 3)], of: .layer(id: s.mover))
        s.manager.holdLivePose([containerX: xCurve(canvasBox.midX + 8)], of: .layer(id: s.mover))
        let shown = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0, holding: s.manager.liveEdit)

        XCTAssertTrue(s.manager.commitLivePose(), "the lift changed the document")
        s.manager.endLiveTransformEdit()
        XCTAssertNil(s.manager.livePose)
        XCTAssertEqual(s.manager.layers[mover].transform?.track.curve(.x), xCurve(canvasBox.midX + 8),
                       "the last tick's curve is what lands — every tick replaced the one before it")
        XCTAssertEqual(s.manager.history.undoStack.count, steps + 1, "one drag, one step")
        let landed = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0)
        XCTAssertEqual(try tx(from: shown[0], to: landed[0]), 0, accuracy: 1e-9,
                       "the document shows exactly what the finger was showing")

        s.manager.undo()
        XCTAssertEqual(s.manager.layers[mover].transform?.track.curve(.x), xCurve(canvasBox.midX),
                       "one Undo puts the node back")
        XCTAssertEqual(try tx(from: minted[0], to: s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0)[0]),
                       0, accuracy: 1e-9)
    }

    /// **A cancelled drag, or one that came back to where it began, writes nothing** — no edit and no
    /// step — and the held pose goes with the edit whichever way it ended.
    func testAnEndedEditDropsTheHeldPoseAndWritesNothing() {
        let s = keyedScene()
        let mover = index(s.mover, s.manager)
        let stored = s.manager.layers[mover].transform
        let steps = s.manager.history.undoStack.count
        s.manager.beginLiveTransformEdit(.container(layerID: s.mover))
        s.manager.holdLivePose([containerX: xCurve(canvasBox.midX + 8)], of: .layer(id: s.mover))
        XCTAssertNotNil(s.manager.livePose)
        s.manager.endLiveTransformEdit()
        XCTAssertNil(s.manager.livePose, "ending the edit drops what it held")
        XCTAssertFalse(s.manager.commitLivePose(), "and nothing is left to commit")

        s.manager.beginLiveTransformEdit(.container(layerID: s.mover))
        s.manager.holdLivePose([:], of: .layer(id: s.mover))
        XCTAssertNil(s.manager.livePose, "a finger back where it began holds nothing")
        XCTAssertFalse(s.manager.commitLivePose())
        s.manager.endLiveTransformEdit()

        XCTAssertEqual(s.manager.layers[mover].transform, stored)
        XCTAssertEqual(s.manager.history.undoStack.count, steps, "no step for a drag that changed nothing")
    }

    /// A pose is held only inside an edit the canvas draws as bands — what shows it, and what drops it.
    func testAPoseIsHeldOnlyInsideAnEditThatMovesBands() {
        let s = keyedScene()
        let curves = [containerX: xCurve(canvasBox.midX + 8)]
        s.manager.holdLivePose(curves, of: .layer(id: s.mover))
        XCTAssertNil(s.manager.livePose, "no edit, nothing to show it")
        s.manager.beginLiveTransformEdit(.floatingPiece)
        s.manager.holdLivePose(curves, of: .layer(id: s.mover))
        XCTAssertNil(s.manager.livePose, "a floating piece draws its own picture")
    }

    /// **A cel channel's held pose reaches the bands through `inkPose`**, the cel's own tracks read
    /// from the hold in place of the document's.
    func testAHeldCelPoseIsReadThroughInkPose() throws {
        let s = scene()
        let inner = index(s.inner, s.manager)
        s.manager.layers[inner].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(box: canvasBox, curves: [.x: xCurve(canvasBox.midX)])]
        let edit = LiveTransformEdit.cel(layerID: s.inner)
        let runs = s.manager.liveTransformRuns(edit, atFrame: 0)
        let minted = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0)
        let celX = PoseChannelID.cel(.cel).parameterID(.x)
        let restX = try XCTUnwrap(s.manager.layers[inner].cels[0].transformTracks[TransformChannelID.cel.id]?
            .curve(.x)?.keys.first?.value)
        s.manager.beginLiveTransformEdit(edit)
        s.manager.holdLivePose([celX: xCurve(restX - 5)], of: .layer(id: s.inner))
        let held = s.manager.liveTransformMaps(edit, runs: runs, atFrame: 0, holding: s.manager.liveEdit)
        XCTAssertEqual(try tx(from: minted[0], to: held[0]), -5, accuracy: 1e-6)
        XCTAssertNotEqual(s.manager.layers[inner].cels[0].transformTracks[TransformChannelID.cel.id]?.curve(.x),
                          xCurve(restX - 5), "the cel itself is untouched until the lift")
    }

    // MARK: - The Move box holds its pose too — TODO (164)

    /// One tick of the box's drag: the overlay reports the whole box, carried `dx`, `dy` from where it
    /// came up.
    private func dragBox(_ manager: CanvasManager, by dx: CGFloat, _ dy: CGFloat = 0) {
        guard var box = manager.floatingPiece?.liftTransform else { return XCTFail("no box is up") }
        box.position.x += dx
        box.position.y += dy
        manager.updateFloatingPose(transform: box, distortQuad: nil)
    }

    /// **A Move-box drag's tick moves the bands and nothing else, and its lift is one step** — the
    /// graph node's mechanism, one entry point over. Each tick used to write the pose into `layers` and
    /// the box into the published piece: a SwiftUI pass over the whole editor per update, and a copy of
    /// the layer to put back at the lift. Operands: the publishes and the canvas's notices across three
    /// ticks, the document and the piece mid-drag, the walk under the held pose against the mint, and
    /// the document after the lift against what the finger showed.
    func testABoxDragHoldsItsPoseOffTheDocumentAndLandsItAsOneStep() throws {
        let s = scene()
        let m = s.manager
        let mover = index(s.mover, m)
        m.currentLayerIndex = mover
        XCTAssertTrue(m.beginContainerPoseMove())
        let edit = LiveTransformEdit.container(layerID: s.mover)
        let runs = m.liveTransformRuns(edit, atFrame: 0)
        let minted = m.liveTransformMaps(edit, runs: runs, atFrame: 0)
        let stored = m.layers[mover].transform
        let box = try XCTUnwrap(m.floatingPiece).transform
        m.moveBoxTouched()
        XCTAssertEqual(m.liveTransformEdit, edit, "PREMISE: the touch put the drag on the bands")
        let steps = m.history.undoStack.count

        var publishes = 0, told = 0
        let token = m.objectWillChange.sink { _ in publishes += 1 }
        m.onHeldPictureMoved = { told += 1 }
        for dx: CGFloat in [3, 7, 12] { dragBox(m, by: dx) }
        token.cancel()

        XCTAssertEqual(publishes, 0, "a box tick raises no SwiftUI pass")
        XCTAssertEqual(told, 3, "and the canvas hears every tick directly")
        XCTAssertEqual(m.layers[mover].transform, stored, "the document holds none of the drag")
        XCTAssertEqual(m.floatingPiece?.transform, box, "nor does the published piece — it learns at the lift")
        XCTAssertEqual(try XCTUnwrap(m.shownFloatingPiece).transform.position.x, box.position.x + 12,
                       accuracy: 1e-9, "while the overlay draws the box under the finger")
        let held = m.liveTransformMaps(edit, runs: runs, atFrame: 0, holding: m.liveEdit)
        XCTAssertEqual(try tx(from: minted[0], to: held[0]), 12, accuracy: 1e-6,
                       "the bands are re-posed by the drag's whole distance")

        m.moveBoxLifted()
        XCTAssertNil(m.livePose, "the lift lets the held pose go…")
        XCTAssertNil(m.liveTransformEdit, "…and the baker's hold")
        XCTAssertEqual(m.history.undoStack.count, steps + 1, "one drag, one step")
        XCTAssertEqual(try tx(from: held[0], to: m.liveTransformMaps(edit, runs: runs, atFrame: 0)[0]), 0,
                       accuracy: 1e-9, "the document shows exactly what the finger was showing")
        XCTAssertEqual(try XCTUnwrap(m.floatingPiece).transform.position.x, box.position.x + 12, accuracy: 1e-9,
                       "and the box stays where the finger left it")

        m.undo()
        XCTAssertEqual(m.layers[mover].transform, stored, "one Undo puts the whole drag back")
        XCTAssertNotNil(m.floatingPiece, "with the box still up")
    }

    /// **The pose held under the finger is the pose the lift writes, on every route the commit takes** —
    /// no keys, primed marks, standing on a mark, between two keys. They are folded by one function
    /// (`containerPoseMove`), so the operands are the whole `LayerPose` the finger held just before the
    /// lift and the whole `LayerPose` the document holds just after it: base, baseline, track and mode.
    func testTheHeldPoseIsTheLandedPoseOnEveryRoute() throws {
        let s = scene()
        let m = s.manager
        let mover = index(s.mover, m)
        let target = KeyframeTarget.layer(id: s.mover)
        m.currentLayerIndex = mover
        CanvasFixture.setCelLayout(m, layerIndex: mover, [(start: 0, length: 12)])

        func dragAndLand(atFrame frame: Int, _ dx: CGFloat, _ dy: CGFloat, _ route: String) throws {
            m.currentFrame = frame
            XCTAssertTrue(m.beginContainerPoseMove(), "\(route): the box comes up")
            m.moveBoxTouched()
            dragBox(m, by: dx, dy)
            let held = try XCTUnwrap(m.livePose?.containerPose(ofLayer: s.mover), "\(route): the drag holds a pose")
            XCTAssertNotEqual(m.layers[mover].transform, held, "\(route): PREMISE: the document does not have it yet")
            m.moveBoxLifted()
            XCTAssertEqual(m.layers[mover].transform, held, "\(route): the lift lands exactly the pose held")
            XCTAssertTrue(m.commitFloatingPieceIfNeeded())
        }

        try dragAndLand(atFrame: 4, 6, 0, "no keys")
        XCTAssertTrue(m.addKeys(target, atFrame: 0))
        try dragAndLand(atFrame: 6, 0, 5, "primed, between marks")
        XCTAssertTrue(m.addKeys(target, atFrame: 8))
        try dragAndLand(atFrame: 8, 9, 2, "on a mark")
        try dragAndLand(atFrame: 4, -4, 3, "between keys")
        XCTAssertFalse(try XCTUnwrap(m.layers[mover].transform).track.isEmpty,
                       "PREMISE: the keyed routes were taken")
    }

    /// **Undo or Redo pressed mid-drag drops the held pose** — the drag in the other hand is not a step,
    /// so the press acts on the steps and the canvas shows the document it leaves; the box stays under
    /// the finger and the lift lands only what it moved since.
    func testUndoMidDragLetsTheHeldPoseGo() throws {
        let s = scene()
        let m = s.manager
        let mover = index(s.mover, m)
        m.currentLayerIndex = mover
        XCTAssertTrue(m.beginContainerPoseMove())
        m.moveBoxTouched()
        dragBox(m, by: 10)
        m.moveBoxLifted()
        let afterFirst = m.layers[mover].transform
        m.moveBoxTouched()
        dragBox(m, by: 20)
        XCTAssertNotNil(m.livePose, "PREMISE: the second drag holds a pose")

        m.undo()
        XCTAssertNil(m.livePose, "the press lets the held pose go")
        XCTAssertNotEqual(m.layers[mover].transform, afterFirst, "and undid the first drag, the one step there was")
        XCTAssertEqual(try XCTUnwrap(m.shownFloatingPiece).transform.position.x,
                       try XCTUnwrap(m.floatingPiece).liftTransform.position.x + 20, accuracy: 1e-9,
                       "the box stays under the finger")
        dragBox(m, by: 25)
        m.moveBoxLifted()
        let landed = try XCTUnwrap(m.layers[mover].transform?.pose.affine)
        XCTAssertEqual(Double(landed.tx), 5, accuracy: 1e-9, "the lift lands only the 5 pt moved since the press")
    }

    // MARK: - The box's hold ends with its drag

    /// **A vector float's box that stands down mid-drag still ends the drag** — `onBoxTouchUp`, which
    /// is what ends the live transform edit and with it the baker's hold. Dropped silently, as it used
    /// to be, a box that vanished under the finger (`rasterizeLayer`, `handleActiveContextChanged`)
    /// left `FrameBaker.isSuspended` held until some later box gesture happened to end.
    func testAVectorBoxThatStandsDownMidDragEndsTheDrag() {
        let overlay = ObjectTransformOverlayView(frame: canvasBox)
        overlay.update(isActive: true,
                       frame: ObjectTransformFrame(
                           transform: LayerTransform(position: CGPoint(x: canvasBox.midX, y: canvasBox.midY),
                                                     scale: 1, rotation: 0),
                           contentSize: canvasBox.size),
                       canvasScale: 1, distorting: false)
        var downs = 0, ups = 0, ended = 0
        overlay.onBoxTouchDown = { downs += 1 }
        overlay.onBoxTouchUp = { ups += 1 }
        overlay.onHandleDragEnded = { ended += 1 }
        // A bare touch reads the origin, which is the box's top-left grip.
        let touch = UITouch()
        overlay.touchesBegan([touch], with: nil)
        XCTAssertEqual(downs, 1, "PREMISE: the touch took a grip")

        overlay.deactivate()
        XCTAssertEqual(ended, 1, "the drag's nudge lands")
        XCTAssertEqual(ups, 1, "and the touch-up is said, so the live edit ends")
        overlay.touchesEnded([touch], with: nil)
        XCTAssertEqual(ups, 1, "the touch's own end, later, says nothing a second time")
    }

    /// The same for the box over a floating piece — a transformation layer's, lifted pixels, a
    /// folder's — settled out from under the finger: its pan's own end finds no claim, so the
    /// settle is the only touch-up the drag gets.
    func testAFloatingBoxSettledMidDragEndsTheDrag() throws {
        let overlay = FloatingPieceOverlayView(frame: canvasBox)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let pose = FloatingTransform(position: CGPoint(x: canvasBox.midX, y: canvasBox.midY),
                                     scaleX: 1, scaleY: 1, rotation: 0)
        overlay.update(FloatingPiece(kind: .move, sourceLayerID: UUID(), sourceCelID: UUID(),
                                     targetLayerID: UUID(), targetCelID: UUID(), pieceImage: image,
                                     baseSize: CGSize(width: 20, height: 20), remainderPreview: nil,
                                     transform: pose, liftTransform: pose, mode: .freeform),
                       isInteractive: true)
        var downs = 0, ups = 0
        overlay.onBoxTouchDown = { downs += 1 }
        overlay.onBoxTouchUp = { ups += 1 }
        let pan = try XCTUnwrap(overlay.subviews.flatMap { $0.gestureRecognizers ?? [] }
            .compactMap { $0 as? TouchDownPanGestureRecognizer }.first)
        pan.onTouchDown?()
        XCTAssertEqual(downs, 1, "PREMISE: the pan took the box's touch")

        overlay.update(nil, isInteractive: false)
        XCTAssertEqual(ups, 1, "the settle says the drag is over, so the live edit ends")
        pan.onSequenceEnded?()
        XCTAssertEqual(ups, 1, "and the pan's own end, a moment later, says nothing a second time")
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

    /// **Every box keeps the compositor** — the transformation layer's, which holds no picture and
    /// whose leaving for the flat row re-rasterized every posed drawing per tick, and since TODO (160)
    /// a box over lifted ink too, whose hosts are the live pair's middle (`liveHostRun`). And a live
    /// edit engages a document that otherwise would not be; a float's own edit does not.
    func testEveryBoxKeepsTheCompositor() throws {
        let s = scene(pose(CGAffineTransform(translationX: 4, y: 0)))
        s.manager.currentLayerIndex = index(s.mover, s.manager)
        XCTAssertTrue(s.manager.beginContainerPoseMove())
        XCTAssertTrue(s.manager.sandwichEngagesOnCanvas(tree: s.manager.renderTree(atFrame: 0)))
        _ = s.manager.commitFloatingPieceIfNeeded()

        XCTAssertTrue(s.manager.beginVectorFolderMove(try XCTUnwrap(s.manager.folders.first?.id)))
        XCTAssertTrue(s.manager.sandwichEngagesOnCanvas(tree: s.manager.renderTree(atFrame: 0)))

        let plain = scene()
        let tree = plain.manager.renderTree(atFrame: 0)
        XCTAssertFalse(plain.manager.sandwichEngagesOnCanvas(tree: tree), "PREMISE: nothing poses yet")
        plain.manager.beginLiveTransformEdit(.container(layerID: plain.mover))
        XCTAssertTrue(plain.manager.sandwichEngagesOnCanvas(tree: tree), "its first drag is drawn by bands")
        plain.manager.beginLiveTransformEdit(.floatingPiece)
        XCTAssertFalse(plain.manager.sandwichEngagesOnCanvas(tree: tree))
    }
}
