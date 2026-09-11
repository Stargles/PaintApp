import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for **the transform layer's Parallax and Rotate modes** — TRANSFORM_LAYER.md §5.2
/// and §5.3, §8's rows 2 and 3, and the rulings they rest on (§2 rulings 3–8).
///
/// `TransformLayerLogicTests` beside this one pins the container pose itself: scope, composition
/// order, the three cache keys, the span. This file pins what a *mode* does with that pose, and it
/// is arranged so that each assertion goes red for exactly one wrong implementation:
///
///  * **Parallax** — the positional defaults (100/75/50/25 for four), who counts as an item (a folder
///    is one, a tint is none), a typed share staying with its layer through a reorder, a negative
///    share moving the opposite way, a keyed share, and the one line `setParallaxShare` adds to the
///    channel funnel — the positional default is materialised before keyframe A is seeded.
///  * **Rotate** — 15°/frame is 90° six frames into the *block* (not six frames into the document),
///    a keyed speed integrates with no backward snap, a keyframe holds the box and not the angle, a
///    keystoned box carries one point's orbit onto the conic (four extremes), and a raster fixture
///    goes red on both backends when the function is dropped from the resolved map.
///  * **Persistence** — the mode and the two rows round-trip through a manifest and a real package,
///    and an older document with none of the three decodes to Move.
///
/// `@MainActor` because `makeRenderRequest` and `ProjectStore.save`/`load` are.
@MainActor
final class TransformLayerModesLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var canvasBox: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    private var centre: CGPoint { CGPoint(x: canvasBox.midX, y: canvasBox.midY) }

    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A pose that shows the whole canvas moved by `transform`, in `mode`.
    private func pose(_ transform: CGAffineTransform, mode: TransformLayerMode) -> LayerPose {
        LayerPose(pose: PoseQuad(box: canvasBox, mappedBy: transform), mode: mode)
    }

    private func index(of id: UUID, in manager: CanvasManager) -> Int {
        manager.layers.firstIndex { $0.id == id } ?? -1
    }

    private func layerIndex(named name: String, in manager: CanvasManager) -> Int {
        manager.layers.firstIndex { $0.name == name } ?? -1
    }

    /// **Four drawings under one transform layer, bottom to top `d`, `c`, `b`, `a`, then `mover`**
    /// — the owner's own example, *"with 4 layers, it is 100%, 75, 50, 25"*, so `a` (nearest the
    /// mover) is the 100% item and `d` the 25% one.
    private func fourDrawings(mover moverPose: LayerPose) -> (manager: CanvasManager, a: Int, b: Int, c: Int, d: Int, mover: Int) {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "d")
        manager.addVectorLayer(name: "c")
        manager.addVectorLayer(name: "b")
        manager.addVectorLayer(name: "a")
        manager.addTransformLayer(name: "mover")
        XCTAssertEqual(manager.layers.map(\.name), ["d", "c", "b", "a", "mover"],
                       "The fixture's own premise: layers are created bottom to top")
        let mover = layerIndex(named: "mover", in: manager)
        manager.layers[mover].transform = moverPose
        return (manager, layerIndex(named: "a", in: manager), layerIndex(named: "b", in: manager),
                layerIndex(named: "c", in: manager), layerIndex(named: "d", in: manager), mover)
    }

    /// One raster layer holding a small black block off-centre, with a Rotate transform layer above
    /// it whose block starts at `blockStart`. Returns the manager and the drawn layer's index.
    private func rotatedRasterLayer(speed: Double, blockStart: Int = 0) -> (manager: CanvasManager, drawn: Int, mover: Int) {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addLayer(name: "ink")
        manager.addTransformLayer(name: "wheel")
        let drawn = layerIndex(named: "ink", in: manager)
        let mover = layerIndex(named: "wheel", in: manager)
        manager.layers[drawn].cels[0].frameCount = 24
        // The block is what the angle integrates from; a cel starting later is a wheel that starts later.
        manager.layers[mover].cels[0].startFrame = blockStart
        manager.layers[mover].cels[0].frameCount = 24
        // A 6x6 block to the right of centre on the centre row: at 90° clockwise it sits below centre.
        CanvasFixture.setBakedContent(manager, layerIndex: drawn,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 44, y: 29, width: 6, height: 6)))
        manager.layers[mover].transform = LayerPose(pose: PoseQuad(restingIn: canvasBox), mode: .rotate)
        manager.layers[mover].rotateSpeed = speed
        return (manager, drawn, mover)
    }

    private func compositeBytes(_ manager: CanvasManager, atFrame frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    private func onBothBackends(_ body: (CompositorBackend) throws -> Void) throws {
        for backend in [CompositorBackend.coreGraphics, .metal] {
            if backend == .metal, CompositorMetalEngine.shared == nil { continue }
            Compositor.backend = backend
            try body(backend)
        }
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "CoreGraphics ran; no Metal device or shader library in this bundle for the second backend")
    }

    /// Where a `[UInt8]` RGBA composite of the fixture's canvas is opaque, as a rect — the drawn
    /// operand every raster assertion below compares.
    private func inkBounds(_ bytes: [UInt8]) -> CGRect? {
        let w = Int(size.width), h = Int(size.height)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func curve(_ keys: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: keys.map { AnimationCurve.Key(frame: $0.0, value: $0.1) })
    }

    // MARK: - Parallax: the positional defaults (§5.2, ruling 3)

    /// **Four drawings under a parallax layer moved 100 pt take 100, 75, 50 and 25 of it**, nearest
    /// first. Deleting the formula's `count - rank` (every item at 100%) or reversing the rank (the
    /// far item moving most) each turn a different row red, and a Move-mode accumulator that ignores
    /// the mode turns three of them red.
    func testFourDrawingsUnderAParallaxLayerTakeTheirPositionalSharesOfItsTranslation() {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        let poses = fx.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(poses[fx.a]?.affine?.tx ?? 0, 100, accuracy: 1e-9, "the item nearest the layer moves fully")
        XCTAssertEqual(poses[fx.b]?.affine?.tx ?? 0, 75, accuracy: 1e-9)
        XCTAssertEqual(poses[fx.c]?.affine?.tx ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(poses[fx.d]?.affine?.tx ?? 0, 25, accuracy: 1e-9, "the back item moves a quarter")
        XCTAssertNil(poses[fx.mover], "the parallax layer itself is not an item and takes nothing")
        XCTAssertEqual(TransformLayerMode.positionalParallaxShare(rank: 0, of: 1), 1,
                       "a single item is the whole move")
    }

    /// **A folder counts as one item and nothing inside it is split up** (ruling 3). Two loose
    /// drawings and a folder of two make three items — 100/67/33 — and both drawings inside the
    /// folder take the folder's share. A walk that counted the folder's contents as items would give
    /// four shares, and one that skipped folders would give two.
    func testAFolderIsOneItemAndEverythingInsideItTakesTheFoldersShare() {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 90, y: 0), mode: .parallax))
        let folder = fx.manager.addFolder(name: "F")
        for name in ["b", "c"] {
            fx.manager.layers[layerIndex(named: name, in: fx.manager)].parentFolderID = folder
        }
        let a = layerIndex(named: "a", in: fx.manager), b = layerIndex(named: "b", in: fx.manager)
        let c = layerIndex(named: "c", in: fx.manager), d = layerIndex(named: "d", in: fx.manager)
        let poses = fx.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(poses[a]?.affine?.tx ?? 0, 90, accuracy: 1e-9, "item 1 of 3")
        XCTAssertEqual(poses[b]?.affine?.tx ?? 0, 60, accuracy: 1e-9, "inside the folder: the folder's share, item 2 of 3")
        XCTAssertEqual(poses[c]?.affine?.tx ?? 0, 60, accuracy: 1e-9, "…and its sibling the same, not a share of its own")
        XCTAssertEqual(poses[d]?.affine?.tx ?? 0, 30, accuracy: 1e-9, "item 3 of 3")
    }

    /// **A tint between the drawings is not an item and takes no share** (ruling 3): with a value
    /// layer dropped between `b` and `c`, the four drawings still read 100/75/50/25 and the tint has
    /// no pose entry at all. A walk that counted every entry would shift `c` and `d` to 60/40 and
    /// hand the tint 40 — and the tint's version would then change with every drag.
    func testATintBetweenTheDrawingsIsNotAnItemAndShiftsNoDefault() {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        // A value layer directly above `c`: `insertNewLayer` puts it above the active layer.
        fx.manager.currentLayerIndex = fx.c
        fx.manager.addValueLayer(name: "tint")
        XCTAssertEqual(fx.manager.layers.map(\.name), ["d", "c", "tint", "b", "a", "mover"],
                       "Premise: the tint sits between c and b")
        let tint = layerIndex(named: "tint", in: fx.manager)
        let poses = fx.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(poses[layerIndex(named: "a", in: fx.manager)]?.affine?.tx ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(poses[layerIndex(named: "b", in: fx.manager)]?.affine?.tx ?? 0, 75, accuracy: 1e-9)
        XCTAssertEqual(poses[layerIndex(named: "c", in: fx.manager)]?.affine?.tx ?? 0, 50, accuracy: 1e-9,
                       "the tint above c does not push c down a rank")
        XCTAssertEqual(poses[layerIndex(named: "d", in: fx.manager)]?.affine?.tx ?? 0, 25, accuracy: 1e-9)
        XCTAssertNil(poses[tint], "a pixel-less leaf takes no share and gets no derivation")
    }

    // MARK: - Parallax: a typed share (rulings 4 and 5)

    /// **A negative share moves the item the opposite way, and a share past 100% moves it further**
    /// — the owner's *"can input negative values or higher"*, which is `PoseInterpolation.blend`
    /// extrapolating. A clamp into 0…1 at the share's read would pin both to the ends.
    func testANegativeShareMovesTheOppositeWayAndOnePastFullMovesFurther() {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        fx.manager.layers[fx.b].parallaxShare = -0.5
        fx.manager.layers[fx.c].parallaxShare = 1.5
        let poses = fx.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(poses[fx.b]?.affine?.tx ?? 0, -50, accuracy: 1e-9, "−50% is 50 pt the other way")
        XCTAssertEqual(poses[fx.c]?.affine?.tx ?? 0, 150, accuracy: 1e-9, "150% overshoots the box")
        XCTAssertEqual(poses[fx.d]?.affine?.tx ?? 0, 25, accuracy: 1e-9, "…and the untyped item keeps its default")
    }

    /// **A share of a turn or a scale is the factored blend** (§2.15, `PoseInterpolation.blend`):
    /// half of a 90° turn about the centre is a 45° turn about the centre — the rotation is blended
    /// by angle — and half of a 4× scale is 2.5×, the symmetric part blended linearly, which is what
    /// that blend does and what a keyframed scale already interpolates as. An entrywise
    /// `lerp(identity, M, t)` gives the chord for the turn, and a `t × P` on the matrix gives a
    /// squashed 2× for the scale.
    func testHalfOfATurnIsHalfTheAngleAndHalfOfAScaleIsTheFactoredBlend() throws {
        let turn = CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: .pi / 2).translatedBy(x: -centre.x, y: -centre.y)
        let fx = fourDrawings(mover: pose(turn, mode: .parallax))
        fx.manager.layers[fx.a].parallaxShare = 0.5
        let half = try XCTUnwrap(fx.manager.layerPoses(atFrame: 0)[fx.a]?.affine)
        let p = CGPoint(x: centre.x + 10, y: centre.y).applying(half)
        XCTAssertEqual(p.x, centre.x + 10 * cos(.pi / 4), accuracy: 1e-6, "45°, not the chord of 90°")
        XCTAssertEqual(p.y, centre.y + 10 * sin(.pi / 4), accuracy: 1e-6)

        let scale = CGAffineTransform(translationX: centre.x, y: centre.y)
            .scaledBy(x: 4, y: 4).translatedBy(x: -centre.x, y: -centre.y)
        let sx = fourDrawings(mover: pose(scale, mode: .parallax))
        sx.manager.layers[sx.a].parallaxShare = 0.5
        let halfScale = try XCTUnwrap(sx.manager.layerPoses(atFrame: 0)[sx.a]?.affine)
        XCTAssertEqual(halfScale.a, 2.5, accuracy: 1e-9, "half of 4× is 2.5×: the stretch is blended linearly")
        XCTAssertEqual(halfScale.d, 2.5, accuracy: 1e-9)
        XCTAssertEqual(halfScale.b, 0, accuracy: 1e-9, "…and it is still a pure scale about the centre")
        XCTAssertEqual(CGPoint(x: centre.x, y: centre.y).applying(halfScale).x, centre.x, accuracy: 1e-6)
    }

    /// **A keyed share resolves through its curve** (ruling 5): keyed 0 → 1 over frames 0…8, the
    /// item is at rest at 0, fully moved at 8, and between the two in between — while its untyped
    /// neighbours keep their positional defaults at every frame.
    func testAKeyedShareResolvesThroughItsCurve() throws {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        fx.manager.layers[fx.d].channelTracks[TargetChannel.parallaxShare.id] = curve([(0, 0), (8, 1)])

        XCTAssertNil(fx.manager.layerPoses(atFrame: 0)[fx.d], "a 0% share is rest, and rest costs no derivation")
        XCTAssertEqual(fx.manager.layerPoses(atFrame: 8)[fx.d]?.affine?.tx ?? 0, 100, accuracy: 1e-9)
        let mid = try XCTUnwrap(fx.manager.layerPoses(atFrame: 4)[fx.d]?.affine?.tx)
        XCTAssertGreaterThan(mid, 0); XCTAssertLessThan(mid, 100)
        XCTAssertEqual(fx.manager.layerPoses(atFrame: 4)[fx.a]?.affine?.tx ?? 0, 100, accuracy: 1e-9,
                       "the neighbour's default is untouched by d's curve")
    }

    /// **A typed number stays with its layer through a reorder, and the others re-default to their
    /// new positions** (ruling 4). `b` is typed 10% and dragged to the bottom: it still says 10%,
    /// while `d` — now rank 1 — reads 75% where it read 25%.
    func testReorderingKeepsATypedShareWithItsLayerAndReDefaultsTheRest() {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        let bID = fx.manager.layers[fx.b].id
        fx.manager.layers[fx.b].parallaxShare = 0.1
        fx.manager.restackLayer(bID, above: .bottom, parentFolderID: nil)
        XCTAssertEqual(fx.manager.layers.map(\.name), ["b", "d", "c", "a", "mover"],
                       "Premise: b went to the bottom")
        let poses = fx.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(poses[index(of: bID, in: fx.manager)]?.affine?.tx ?? 0, 10, accuracy: 1e-9,
                       "the typed share followed b to the bottom")
        XCTAssertEqual(poses[layerIndex(named: "a", in: fx.manager)]?.affine?.tx ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(poses[layerIndex(named: "c", in: fx.manager)]?.affine?.tx ?? 0, 75, accuracy: 1e-9,
                       "c is rank 1 of 4 now")
        XCTAssertEqual(poses[layerIndex(named: "d", in: fx.manager)]?.affine?.tx ?? 0, 50, accuracy: 1e-9,
                       "d is rank 2 of 4 now, where it was rank 3")
    }

    /// **The panel's list is the render's items** — same walk, so the row the artist reads names
    /// the layer the render moves, with the share it is showing and whether it was typed.
    func testThePanelsItemListNamesTheItemsTopToBottomWithTheirSharesAndWhetherTyped() {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        fx.manager.layers[fx.c].parallaxShare = 0.4
        let items = fx.manager.parallaxItems(beneath: .layer(id: fx.manager.layers[fx.mover].id))

        XCTAssertEqual(items.map(\.name), ["a", "b", "c", "d"], "top to bottom, the mover excluded")
        XCTAssertEqual(items.map(\.share), [1, 0.75, 0.4, 0.25])
        XCTAssertEqual(items.map(\.isExplicit), [false, false, true, false], "only c was typed")
        XCTAssertEqual(items.map(\.positionalDefault), [1, 0.75, 0.5, 0.25],
                       "…and c's positional default is still known, for the greyed reading and the seed")
        XCTAssertEqual(fx.manager.parallaxItems(beneath: .layer(id: fx.manager.layers[fx.d].id)), [],
                       "a drawing layer poses nothing and lists nothing")
    }

    /// **The first share edit on a keyed item seeds keyframe A with the positional default the
    /// artist was looking at, not with the key path's fallback.** `d` is marked at frames 0 and 8
    /// with no share typed; at frame 8 the slider writes 30%. Keyframe A must hold 25% — the default
    /// `d` showed — and the funnel can only read a *stored* number, so `setParallaxShare` writes the
    /// default through first. Delete that line and A seeds at 100%, the `parallaxShareValue`
    /// fallback: a visible jump on a layer the artist never set to 100%.
    func testTheFirstShareEditOnAKeyedItemSeedsKeyframeAWithThePositionalDefault() throws {
        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 100, y: 0), mode: .parallax))
        let poser = KeyframeTarget.layer(id: fx.manager.layers[fx.mover].id)
        let item = KeyframeTarget.layer(id: fx.manager.layers[fx.d].id)
        XCTAssertTrue(fx.manager.addKeyframe(item, atFrame: 0))
        XCTAssertTrue(fx.manager.addKeyframe(item, atFrame: 8))
        XCTAssertNil(fx.manager.layers[fx.d].parallaxShare, "Premise: nothing typed yet")

        let route = fx.manager.setParallaxShare(of: item, beneath: poser, to: 0.3, atFrame: 8)
        XCTAssertEqual(route, .seedAndKey, "two marks and no curve: A is seeded, B is keyed")
        let track = try XCTUnwrap(fx.manager.layers[fx.d].channelTracks[TargetChannel.parallaxShare.id])
        XCTAssertEqual(track.keys.first { $0.frame == 0 }?.value ?? -1, 0.25, accuracy: 1e-9,
                       "keyframe A holds the 25% the artist was looking at")
        XCTAssertEqual(track.keys.first { $0.frame == 8 }?.value ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(fx.manager.layerPoses(atFrame: 0)[fx.d]?.affine?.tx ?? 0, 25, accuracy: 1e-9,
                       "…and the render at A is what it was before the edit")
    }

    /// **The box drag moves each item live**: the preview writes the pose the render reads
    /// (`showContainerPoseLive`), so with the box lifted and carried 40 pt the four items are at
    /// 40/30/20/10 before anything is committed.
    func testTheBoxDragMovesEachItemByItsShareBeforeTheCommit() throws {
        let fx = fourDrawings(mover: pose(.identity, mode: .parallax))
        fx.manager.currentLayerIndex = fx.mover
        XCTAssertTrue(fx.manager.beginContainerPoseMove(), "the box comes up on the parallax layer")
        var carried = try XCTUnwrap(fx.manager.floatingPiece).transform
        carried.position.x += 40
        // The overlay's tick: `updateFloatingPose` is what every drag of the box ends in, and its
        // tail is the preview's write of the pose into the document.
        fx.manager.updateFloatingPose(transform: carried, distortQuad: nil)
        let poses = fx.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(poses[fx.a]?.affine?.tx ?? 0, 40, accuracy: 1e-6)
        XCTAssertEqual(poses[fx.b]?.affine?.tx ?? 0, 30, accuracy: 1e-6)
        XCTAssertEqual(poses[fx.c]?.affine?.tx ?? 0, 20, accuracy: 1e-6)
        XCTAssertEqual(poses[fx.d]?.affine?.tx ?? 0, 10, accuracy: 1e-6, "the back item follows at a quarter, live")
        XCTAssertEqual(fx.manager.layers[fx.mover].transform?.mode, .parallax,
                       "the preview's write of the pose did not lose the mode")
    }

    // MARK: - The picker's model half

    /// **Switching the mode is one undo step that leaves the pose, its keys and the speed alone** —
    /// §6's factorisation as a writer: the mode qualifies the pose, so picking Rotate on a keyed
    /// layer keeps both keys and the typed speed, undo puts Move back with nothing else changed, and
    /// a layer with no pose refuses. A writer that rebuilt the pose without its mode, or dropped a
    /// key on the way, turns this red.
    func testSwitchingTheModeIsOneUndoStepThatLeavesThePoseAndItsKeysAlone() throws {
        let fx = fourDrawings(mover: pose(.identity, mode: .move))
        var keyed = try XCTUnwrap(fx.manager.layers[fx.mover].transform)
        keyed.track.setKey(TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: canvasBox)))
        keyed.track.setKey(TransformTrack.Key(frame: 8, pose: PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 30, y: 0))))
        fx.manager.layers[fx.mover].transform = keyed
        fx.manager.layers[fx.mover].rotateSpeed = 15
        let target = KeyframeTarget.layer(id: fx.manager.layers[fx.mover].id)

        fx.manager.setTransformLayerMode(target, to: .rotate)
        XCTAssertEqual(fx.manager.transformLayerMode(of: target), .rotate)
        XCTAssertEqual(fx.manager.layers[fx.mover].transform?.track, keyed.track, "both keys are exactly what they were")
        XCTAssertEqual(fx.manager.layers[fx.mover].rotateSpeed, 15, "…and the speed")
        fx.manager.setTransformLayerMode(target, to: .rotate)
        fx.manager.undo()
        XCTAssertEqual(fx.manager.transformLayerMode(of: target), .move, "one step back is Move — the second, same-mode pick recorded nothing")
        XCTAssertEqual(fx.manager.layers[fx.mover].transform?.track, keyed.track)
        fx.manager.redo()
        XCTAssertEqual(fx.manager.transformLayerMode(of: target), .rotate)

        let drawing = KeyframeTarget.layer(id: fx.manager.layers[fx.a].id)
        fx.manager.setTransformLayerMode(drawing, to: .parallax)
        XCTAssertNil(fx.manager.transformLayerMode(of: drawing), "a drawing has no pose to put a mode on")
    }

    // MARK: - The folder twin (§3.3)

    /// **A folder's pose takes the modes as well** (§3.3): a folder in Parallax shares its move over
    /// its own children — three inside it take 100/67/33 — and the same folder switched to Rotate at
    /// 15°/frame has them turned 90° at frame 6, integrating from frame 0 because a folder has no
    /// block. A recursion that composed the folder's pose as one map onto every child would hand all
    /// three the full move and never read the mode at all.
    func testAFolderInParallaxSharesOverItsChildrenAndInRotateSpinsThem() throws {
        let fx = fourDrawings(mover: pose(.identity, mode: .move))
        let folder = fx.manager.addFolder(name: "F")
        for name in ["a", "b", "c"] {
            fx.manager.layers[layerIndex(named: name, in: fx.manager)].parentFolderID = folder
        }
        let at = try XCTUnwrap(fx.manager.folders.firstIndex { $0.id == folder })
        fx.manager.folders[at].transform = pose(CGAffineTransform(translationX: 90, y: 0), mode: .parallax)
        let a = layerIndex(named: "a", in: fx.manager), b = layerIndex(named: "b", in: fx.manager)
        let c = layerIndex(named: "c", in: fx.manager), d = layerIndex(named: "d", in: fx.manager)

        var poses = fx.manager.layerPoses(atFrame: 0)
        XCTAssertEqual(poses[a]?.affine?.tx ?? 0, 90, accuracy: 1e-9, "the folder's top child is its 100% item")
        XCTAssertEqual(poses[b]?.affine?.tx ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(poses[c]?.affine?.tx ?? 0, 30, accuracy: 1e-9)
        XCTAssertNil(poses[d], "a layer outside the folder is not the folder's item")
        XCTAssertEqual(fx.manager.parallaxItems(beneath: .folder(id: folder)).map(\.name), ["a", "b", "c"],
                       "…and the folder's panel lists exactly those three")

        fx.manager.folders[at].transform = LayerPose(pose: PoseQuad(restingIn: canvasBox), mode: .rotate)
        fx.manager.folders[at].rotateSpeed = 15
        XCTAssertTrue(fx.manager.hasContainerPoseInForce, "a spinning folder engages the compositor")
        poses = fx.manager.layerPoses(atFrame: 6)
        let right = CGPoint(x: centre.x + 10, y: centre.y)
        for (name, index) in [("a", a), ("b", b), ("c", c)] {
            let p = try XCTUnwrap(poses[index]?.applied(to: right), "\(name) is posed by the folder")
            XCTAssertEqual(p.x, centre.x, accuracy: 1e-6, "\(name): 90° six frames from frame 0")
            XCTAssertEqual(p.y, centre.y + 10, accuracy: 1e-6)
        }
        XCTAssertNil(fx.manager.layerPoses(atFrame: 0)[a], "at frame 0 the folder has not turned")
    }

    // MARK: - Rotate: the integral from the block's start (§5.3, ruling 6)

    /// **15°/frame is 90° six frames into the block, about the box's centre** — the row's own
    /// example. The block starts at frame 4, so frame 10 is the sixth frame in and frame 4 is not
    /// turned at all; an integral from the document's start would read 150° at 10 and 60° at 4.
    func testFifteenDegreesAFrameIsNinetyDegreesSixFramesIntoTheBlock() throws {
        let fx = rotatedRasterLayer(speed: 15, blockStart: 4)
        let right = CGPoint(x: centre.x + 10, y: centre.y)

        XCTAssertNil(fx.manager.layerPoses(atFrame: 4)[fx.drawn],
                     "at the block's first frame nothing has turned, and rest costs no derivation")
        let at10 = try XCTUnwrap(fx.manager.layerPoses(atFrame: 10)[fx.drawn]?.applied(to: right))
        XCTAssertEqual(at10.x, centre.x, accuracy: 1e-6, "90° about the centre: right goes to below")
        XCTAssertEqual(at10.y, centre.y + 10, accuracy: 1e-6, "clockwise on a y-down canvas")
        let at7 = try XCTUnwrap(fx.manager.layerPoses(atFrame: 7)[fx.drawn]?.applied(to: right))
        XCTAssertEqual(at7.x, centre.x + 10 * cos(.pi / 4), accuracy: 1e-6, "45° three frames in")
        XCTAssertEqual(at7.y, centre.y + 10 * sin(.pi / 4), accuracy: 1e-6)
        XCTAssertNil(fx.manager.layerPoses(atFrame: 2)[fx.drawn], "before the block the wheel is not there at all")
    }

    /// **A keyed speed integrates, with no backward snap** (§5.3). Speed keyed 15 at 0 → 0 at 8 is
    /// a wheel slowing to a stop: the angle only ever grows, and after frame 8 it holds where it
    /// stopped. Under `speed(f) × (f − start)` the angle would read 0 at 8 — the wheel snapping back
    /// to where it started as its speed reached zero.
    func testAKeyedSpeedIntegratesWithNoBackwardSnap() throws {
        let fx = rotatedRasterLayer(speed: 15)
        fx.manager.layers[fx.mover].channelTracks[TargetChannel.rotateSpeed.id] = curve([(0, 15), (8, 0)])
        let right = CGPoint(x: centre.x + 10, y: centre.y)

        func angle(at frame: Int) throws -> Double {
            guard let map = fx.manager.layerPoses(atFrame: frame)[fx.drawn] else { return 0 }
            let p = try XCTUnwrap(map.applied(to: right))
            var a = atan2(p.y - centre.y, p.x - centre.x) * 180 / .pi
            if a < 0 { a += 360 }
            return a
        }
        var previous = 0.0
        for frame in 0...8 {
            let a = try angle(at: frame)
            XCTAssertGreaterThanOrEqual(a + 1e-9, previous, "frame \(frame): the wheel never turns back")
            previous = a
        }
        XCTAssertGreaterThan(try angle(at: 8), 45, "it turned a good way before stopping")
        XCTAssertEqual(try angle(at: 12), try angle(at: 8), accuracy: 1e-9,
                       "…and holds where it stopped once the speed is 0")
        XCTAssertGreaterThan(try angle(at: 12), 0, "which is not where it started")
    }

    /// **A keyframe holds the box, never the angle** (ruling 7, §6). With the wheel at 15°/frame,
    /// placing a keyframe at 4 writes a key for the *authored* pose — the resting box — and the
    /// spin at frame 6 is still 90°. A writer that keyed the resolved map would freeze a 60° pose
    /// into the track and the wheel would stutter through the mark.
    func testAKeyframeHoldsTheBoxNotTheAngle() throws {
        let fx = rotatedRasterLayer(speed: 15)
        let target = KeyframeTarget.layer(id: fx.manager.layers[fx.mover].id)
        // §2.27's own workflow, so the key writer's container arm is actually reached: mark A, Move
        // the box between the marks (the baseline is held), mark B (the held pose is committed onto A
        // and the moved one keyed at B). A bare pair of marks with no Move between them writes no
        // key at all, and a test built that way exercises none of the writers.
        XCTAssertTrue(fx.manager.addKeyframe(target, atFrame: 0))
        let resting = PoseQuad(restingIn: canvasBox)
        let slid = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 6, y: 0))
        XCTAssertEqual(fx.manager.commitContainerPose(target, restingAt: resting, movedTo: slid, atFrame: 4),
                       .storedValueHoldingBaseline, "between two marks the Move holds a baseline")
        XCTAssertTrue(fx.manager.addKeyframe(target, atFrame: 4))

        let track = try XCTUnwrap(fx.manager.layers[fx.mover].transform?.track)
        XCTAssertEqual(track.keys.map(\.frame), [0, 4], "A took the held rest pose, B the moved box")
        XCTAssertTrue(try XCTUnwrap(track.key(atFrame: 0)).pose.isIdentity, "A holds the box where it rested")
        XCTAssertEqual(try XCTUnwrap(track.key(atFrame: 4)).pose.corners.p0.x, slid.corners.p0.x, accuracy: 1e-9,
                       "B holds the box where it went — the box, and never the angle")
        XCTAssertEqual(fx.manager.layers[fx.mover].transform?.mode, .rotate,
                       "neither the Move nor the mark lost the mode")
        let right = CGPoint(x: centre.x + 10, y: centre.y)
        let at6 = try XCTUnwrap(fx.manager.layerPoses(atFrame: 6)[fx.drawn]?.applied(to: right))
        XCTAssertEqual(at6.x, centre.x + 6, accuracy: 1e-6,
                       "still 90° at 6, about the box now slid 6 — the spin went on through the mark")
        XCTAssertEqual(at6.y, centre.y + 10, accuracy: 1e-6)
    }

    /// **The predicate the canvas switches render paths on reads the speed's track, not one frame**
    /// (§5.3's `movesItsContents`). A rotate layer with an untouched box moves nothing at 0°/frame,
    /// everything at 5°/frame, and — keyed 0 → 15 — everything, at *every* frame including the one
    /// where the speed is still 0.
    func testMovesItsContentsReadsTheModeAndTheSpeedTrack() {
        let fx = rotatedRasterLayer(speed: 0)
        XCTAssertFalse(fx.manager.hasContainerPoseInForce, "an untouched box at 0°/frame moves nothing")
        fx.manager.layers[fx.mover].rotateSpeed = 5
        XCTAssertTrue(fx.manager.hasContainerPoseInForce, "5°/frame moves everything beneath")
        fx.manager.layers[fx.mover].rotateSpeed = 0
        fx.manager.layers[fx.mover].channelTracks[TargetChannel.rotateSpeed.id] = curve([(0, 0), (8, 15)])
        XCTAssertTrue(fx.manager.hasContainerPoseInForce,
                      "a speed keyed 0 → 15 moves the stack at 8, so the answer is yes at 0 as well")
        fx.manager.layers[fx.mover].transform?.mode = .move
        XCTAssertFalse(fx.manager.hasContainerPoseInForce, "in Move the speed is inert storage")
    }

    // MARK: - Rotate: Distort on the box is the ellipse (ruling 8)

    /// **Under a keystoned box one point's orbit is the conic, and the four extremes pin the order
    /// of composition.** The rotation is applied in box space *before* the stored quad's map, so at
    /// θ the point `centre + r·(cos θ, sin θ)` is carried through the homography — an ellipse-like
    /// conic on screen, the owner's *"rotating in ellipses like they are in perspective"*. With the
    /// order reversed (turn on screen, after the keystone) the four images would sit on a circle
    /// about the mapped centre, and the last assertion says they do not.
    func testUnderAKeystonedBoxOnePointsOrbitIsTheConicAtFourExtremes() throws {
        let fx = rotatedRasterLayer(speed: 90)
        // A keystone: the top edge pulled in by a quarter on each side.
        let keystone = Quad(CGPoint(x: canvasBox.minX + 16, y: canvasBox.minY),
                            CGPoint(x: canvasBox.maxX - 16, y: canvasBox.minY),
                            CGPoint(x: canvasBox.maxX, y: canvasBox.maxY),
                            CGPoint(x: canvasBox.minX, y: canvasBox.maxY))
        let authored = PoseQuad(box: canvasBox, corners: keystone)
        let homography = try XCTUnwrap(authored.homography)
        XCTAssertNil(homography.affine(), "Premise: the box is genuinely projective")
        fx.manager.layers[fx.mover].transform = LayerPose(pose: authored, mode: .rotate)

        let r: CGFloat = 12
        var images: [CGPoint] = []
        for step in 0..<4 {
            let theta = CGFloat(step) * .pi / 2
            let onCircle = CGPoint(x: centre.x + r * cos(theta), y: centre.y + r * sin(theta))
            let expected = try XCTUnwrap(homography.map(onCircle), "the circle point maps")
            let map = try XCTUnwrap(fx.manager.layerPoses(atFrame: step)[fx.drawn], "frame \(step) is posed")
            let actual = try XCTUnwrap(map.applied(to: CGPoint(x: centre.x + r, y: centre.y)))
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-6, "θ = \(step * 90)°: the turn happens in box space")
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-6)
            images.append(actual)
        }
        let mappedCentre = try XCTUnwrap(homography.map(centre))
        let radii = images.map { hypot($0.x - mappedCentre.x, $0.y - mappedCentre.y) }
        XCTAssertGreaterThan((radii.max() ?? 0) - (radii.min() ?? 0), 1,
                             "the four extremes are not equidistant from the mapped centre: a conic, not a circle")
    }

    // MARK: - Rotate: what is drawn, on both backends (§7)

    /// **A raster fixture goes red when the rotation is dropped from the resolved map, on both
    /// backends.** A 6×6 block right of centre; six frames at 15°/frame draws it below centre. The
    /// operands are the composite's opaque bounds at frame 6 against frame 0 — what is drawn, not
    /// what is stored — and the same frame composited twice is byte-identical, which is RENDER's
    /// *"the same frame renders the same bytes"* with the function inside the version.
    func testARasterLayerUnderARotateLayerIsDrawnTurnedOnBothBackends() throws {
        try onBothBackends { backend in
            let fx = rotatedRasterLayer(speed: 15)
            let before = try compositeBytes(fx.manager, atFrame: 0)
            let after = try compositeBytes(fx.manager, atFrame: 6)
            let restBounds = try XCTUnwrap(inkBounds(before), "\(backend): the block is drawn at rest")
            let turned = try XCTUnwrap(inkBounds(after), "\(backend): the block is drawn at 90°")
            XCTAssertEqual(restBounds.midX, 47, accuracy: 1.5, "\(backend): at rest the block is right of centre")
            XCTAssertEqual(restBounds.midY, 32, accuracy: 1.5)
            XCTAssertEqual(turned.midX, 32, accuracy: 1.5, "\(backend): at 90° it is on the centre column")
            XCTAssertEqual(turned.midY, 47, accuracy: 1.5, "\(backend): …below centre — turned, not slid")
            XCTAssertEqual(try compositeBytes(fx.manager, atFrame: 6), after,
                           "\(backend): the same frame renders the same bytes")

            let v0 = fx.manager.contentVersion(ofLayer: fx.drawn, atFrame: 0)
            let v6 = fx.manager.contentVersion(ofLayer: fx.drawn, atFrame: 6)
            XCTAssertNotEqual(v0, v6, "\(backend): the resolved pose is in the version, so the frames cannot share a cache entry")
        }
    }

    // MARK: - Persistence

    /// **The mode and the two rows survive a manifest round trip; a manifest without them decodes to
    /// Move, 0 and the positional default; and a pose in Move writes no `mode` key at all** — §3.5's
    /// field-presence idiom, all three directions.
    func testTheModeAndTheRowsRoundTripAndAnOlderManifestDecodesToMove() throws {
        let cel = CelManifest(id: UUID(), startFrame: 0, frameCount: 12, rasterFileName: "r.png")
        let rotating = LayerPose(pose: PoseQuad(restingIn: canvasBox), mode: .rotate)
        let written = LayerManifest(id: UUID(), name: "Wheel", opacity: 1, isVisible: true, kind: .transform,
                                    transform: rotating, rotateSpeed: 15, parallaxShare: 0.4, cels: [cel])
        let data = try JSONEncoder().encode(written)
        let back = try JSONDecoder().decode(LayerManifest.self, from: data)
        XCTAssertEqual(back.transform?.mode, .rotate)
        XCTAssertEqual(back.rotateSpeed, 15)
        XCTAssertEqual(back.parallaxShare, 0.4)

        let folderWritten = FolderManifest(id: UUID(), name: "G", isExpanded: true, isVisible: true,
                                           transform: LayerPose(pose: PoseQuad(restingIn: canvasBox), mode: .parallax),
                                           rotateSpeed: -3, parallaxShare: 0.6)
        let folderBack = try JSONDecoder().decode(FolderManifest.self, from: try JSONEncoder().encode(folderWritten))
        XCTAssertEqual(folderBack.transform?.mode, .parallax)
        XCTAssertEqual(folderBack.rotateSpeed, -3)
        XCTAssertEqual(folderBack.parallaxShare, 0.6)

        // An older document: a transform layer with none of the three keys.
        let older = LayerManifest(id: UUID(), name: "Old", opacity: 1, isVisible: true, kind: .transform,
                                  transform: LayerPose(pose: PoseQuad(restingIn: canvasBox)), cels: [cel])
        let olderJSON = try XCTUnwrap(String(data: try JSONEncoder().encode(older), encoding: .utf8))
        XCTAssertFalse(olderJSON.contains("\"mode\""), "a pose in Move writes no mode key")
        XCTAssertFalse(olderJSON.contains("rotateSpeed"), "…and a layer with no speed writes none")
        XCTAssertFalse(olderJSON.contains("parallaxShare"))
        let olderBack = try JSONDecoder().decode(LayerManifest.self, from: Data(olderJSON.utf8))
        XCTAssertEqual(olderBack.transform?.mode, .move, "absent is Move")
        XCTAssertNil(olderBack.rotateSpeed, "absent is 0 once it reaches the model")
        XCTAssertNil(olderBack.parallaxShare, "absent is the positional default")
    }

    /// **Through a real package**: a parallax layer with one typed share and a rotating folder with a
    /// keyed speed are what they were after save and load — and the reloaded document poses the same
    /// leaves to the same maps, which is the only thing the artist can see.
    func testTheModesSurviveAPackageRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform-modes-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let fx = fourDrawings(mover: pose(CGAffineTransform(translationX: 40, y: 0), mode: .parallax))
        fx.manager.layers[fx.c].parallaxShare = 0.9
        let folder = fx.manager.addFolder(name: "G")
        fx.manager.layers[layerIndex(named: "d", in: fx.manager)].parentFolderID = folder
        let folderAt = try XCTUnwrap(fx.manager.folders.firstIndex { $0.id == folder })
        fx.manager.folders[folderAt].transform = LayerPose(pose: PoseQuad(restingIn: canvasBox), mode: .rotate)
        fx.manager.folders[folderAt].channelTracks[TargetChannel.rotateSpeed.id] = curve([(0, 0), (8, 15)])
        let moverID = fx.manager.layers[fx.mover].id, cID = fx.manager.layers[fx.c].id

        let url = root.appendingPathComponent("modes.paintproj", isDirectory: true)
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(fx.manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(reloaded.layers.first { $0.id == moverID }?.transform?.mode, .parallax)
        XCTAssertEqual(reloaded.layers.first { $0.id == cID }?.parallaxShare, 0.9)
        let reloadedFolder = try XCTUnwrap(reloaded.folders.first { $0.id == folder })
        XCTAssertEqual(reloadedFolder.transform?.mode, .rotate)
        XCTAssertEqual(reloadedFolder.channelTracks[TargetChannel.rotateSpeed.id],
                       fx.manager.folders[folderAt].channelTracks[TargetChannel.rotateSpeed.id])
        for frame in [0, 6, 8] {
            let before = fx.manager.layerPoses(atFrame: frame)
            let after = reloaded.layerPoses(atFrame: frame)
            XCTAssertEqual(before.count, after.count, "frame \(frame): the same leaves are posed")
            for (layerAt, map) in before {
                let reloadedIndex = index(of: fx.manager.layers[layerAt].id, in: reloaded)
                XCTAssertEqual(after[reloadedIndex]?.encoded ?? [], map.encoded,
                               "frame \(frame), \(fx.manager.layers[layerAt].name): the same map")
            }
        }
    }

    /// **The arithmetic, stated once and pinned once**: the positional shares, the integral's closed
    /// form against its sum, and frames per turn.
    func testTheModeArithmetic() {
        XCTAssertEqual((0..<4).map { TransformLayerMode.positionalParallaxShare(rank: $0, of: 4) }, [1, 0.75, 0.5, 0.25])
        XCTAssertEqual(TransformLayerMode.integratedRotationDegrees(from: 4, to: 10, hasCurve: false) { _ in 15 }, 90)
        XCTAssertEqual(TransformLayerMode.integratedRotationDegrees(from: 4, to: 10, hasCurve: true) { _ in 15 }, 90,
                       "the sum of six 15s is the product, bit for bit")
        XCTAssertEqual(TransformLayerMode.integratedRotationDegrees(from: 4, to: 4, hasCurve: true) { _ in 15 }, 0)
        XCTAssertEqual(TransformLayerMode.integratedRotationDegrees(from: 4, to: 2, hasCurve: false) { _ in 15 }, 0,
                       "before the block's start nothing has accumulated")
        XCTAssertEqual(TransformLayerMode.framesPerTurn(degreesPerFrame: 15), 24)
        XCTAssertEqual(TransformLayerMode.framesPerTurn(degreesPerFrame: -15), 24)
        XCTAssertNil(TransformLayerMode.framesPerTurn(degreesPerFrame: 0))
        XCTAssertNil(TransformLayerMode.rotationMap(authored: PoseQuad(restingIn: canvasBox), degrees: 720),
                     "two whole turns are no turn, exactly")
        XCTAssertNil(TransformLayerMode.parallaxMap(authored: PoseQuad(restingIn: canvasBox), share: 0.5),
                     "a share of rest is rest")
    }
}
