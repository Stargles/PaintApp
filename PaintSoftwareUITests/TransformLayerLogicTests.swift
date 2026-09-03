import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for **the transformation layer** — KEYFRAMES.md §2.3, §4.4 and §4.5, the half of
/// TODO (21) that moves whatever is *under* a layer rather than what is *on* a cel.
///
/// `TransformChannelLogicTests` beside this one pins the cel-scoped channel — a drawing moving inside
/// its own cel. This one pins the container-scoped pose: a `.value` layer in transform mode moving
/// everything beneath it in its container, and a folder moving everything inside it.
///
/// Four things are pinned here, ordered by how expensive each is to discover later.
///
/// 1. **Scope, which §4.4 says has to be computed structurally.** *"A pose applied at rasterisation
///    has no buffer to be bounded by, so the scope must be computed in `renderNodes` and carried per
///    layer index — get it wrong and the pose silently leaves its folder with nothing downstream to
///    stop it."* There is no assertion the compositor could make on the app's behalf, so these are it.
/// 2. **§4.5's caching trap, reached from the transformation layer's door.** A cel that carries no
///    channel of its own and is moved only from above is identical in every other key field at every
///    frame of the move, so the flatten memo hands frame one's pixels to all of them — and
///    `SandwichKey` compares the whole node tree and rebuilds the composite dutifully from the stale
///    entry. Three keys have to move (`PixelOps.RasterizeKey`, `LayerContentVersion`, `FrameBakeKey`)
///    and there is one test per key, each written so that deleting exactly one field turns exactly
///    one of them red.
/// 3. **Which currency each tier moves in** — §2.12. Vector ink is *re-posed* (stamped at the posed
///    position, crisp) and raster content is *resampled*, which is the owner's accepted consequence
///    rather than a defect, so both halves are asserted rather than only the one this feature is
///    named for.
/// 4. **Nothing changes for a document with no transformation layer in it**, which is the safety
///    property the whole feature is shaped around and is asserted directly rather than assumed.
///
/// `@MainActor` because `makeFrameRecipe` and `ProjectStore.save`/`load` are.
@MainActor
final class TransformLayerLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var canvasBox: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }

    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    // MARK: - Fixtures

    private func stroke(_ points: [CGPoint], size strokeSize: CGFloat = 6) -> VectorStroke {
        VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: strokeSize, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
    }

    /// A pose that shows the whole canvas moved by `transform` — the shape a transformation layer's
    /// stored base takes, with the canvas rect as its box.
    ///
    /// **The box is the canvas and that choice is inert for every pose this feature can author.** A
    /// `PoseQuad` is the map from its box to its corners, and `Homography.init(rect:to:)` zeroes the
    /// perspective row exactly for an affine quad — so the box cancels. It matters only for the
    /// centre `PoseInterpolation` linearises a *projective* pose at, which stage 5b authors and this
    /// one cannot.
    private func pose(_ transform: CGAffineTransform) -> LayerPose {
        LayerPose(pose: PoseQuad(box: canvasBox, mappedBy: transform))
    }

    /// A pose with two keys on its own track: resting at document frame 0, `transform` at frame 8.
    private func animatedPose(_ transform: CGAffineTransform) -> LayerPose {
        LayerPose(pose: PoseQuad(restingIn: canvasBox),
                  track: TransformTrack(keys: [
                    .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
                    .init(frame: 8, pose: PoseQuad(box: canvasBox, mappedBy: transform)),
                  ]))
    }

    private func inkBounds(_ image: UIImage) -> CGRect? { PixelOps.opaqueContentBounds(image) }

    private func index(of id: UUID, in manager: CanvasManager) -> Int {
        manager.layers.firstIndex { $0.id == id } ?? -1
    }

    /// **The document every scope test reads**, bottom to top:
    ///
    /// | index | what | where |
    /// |---|---|---|
    /// | 0 | `floor`, a vector layer | root |
    /// | 1 | `inner`, a vector layer | inside folder `F` |
    /// | 2 | `mover`, a `.value` layer in transform mode | inside folder `F` |
    /// | 3 | `above`, a vector layer | inside folder `F` |
    /// | 4 | `outside`, a vector layer | root |
    ///
    /// So `mover` has exactly one entry beneath it in its own container (`inner`), one above it
    /// (`above`), one beneath it in an *outer* container (`floor`) and one that is neither
    /// (`outside`). Every wrong scope rule anyone would write — everything in the document, everything
    /// beneath it anywhere, everything in its folder — picks up at least one of the other three.
    private struct Stack {
        let manager: CanvasManager
        let folder: UUID
        let floor: Int, inner: Int, mover: Int, above: Int, outside: Int
    }

    private func makeStack(mover moverPose: LayerPose?) -> Stack {
        let manager = CanvasManager()
        manager.canvasSize = size
        // Created bottom to top: `insertNewLayer` puts each new layer above the active one and makes
        // it active. Asserted below rather than assumed, because a fixture whose order is wrong
        // measures a different document than the one its table describes.
        manager.addVectorLayer(name: "floor")
        manager.addVectorLayer(name: "inner")
        manager.addValueLayer(name: "mover")
        manager.addVectorLayer(name: "above")
        manager.addVectorLayer(name: "outside")
        let ids = manager.layers.map(\.id)
        XCTAssertEqual(manager.layers.map(\.name), ["floor", "inner", "mover", "above", "outside"],
                       "The fixture's own premise: layers are created bottom to top")

        let folder = manager.addFolder(name: "F")
        for name in ["inner", "mover", "above"] {
            guard let at = manager.layers.firstIndex(where: { $0.name == name }) else { continue }
            manager.layers[at].parentFolderID = folder
        }
        if let at = manager.layers.firstIndex(where: { $0.name == "mover" }) {
            manager.layers[at].transform = moverPose
        }
        return Stack(manager: manager, folder: folder,
                     floor: index(of: ids[0], in: manager), inner: index(of: ids[1], in: manager),
                     mover: index(of: ids[2], in: manager), above: index(of: ids[3], in: manager),
                     outside: index(of: ids[4], in: manager))
    }

    /// One vector layer holding a short horizontal bar, with `pose` on a transformation layer above
    /// it in the same container. Returns the manager and the *drawn* layer's index.
    private func posedVectorLayer(_ layerPose: LayerPose) -> (manager: CanvasManager, drawn: Int) {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "ink")
        manager.addValueLayer(name: "mover")
        let drawn = manager.layers.firstIndex { $0.name == "ink" } ?? 0
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[drawn].cels = [cel]
        manager.sceneFrameCount = 12
        if let at = manager.layers.firstIndex(where: { $0.name == "mover" }) {
            manager.layers[at].transform = layerPose
        }
        return (manager, drawn)
    }

    /// The same shape with the ink in the **raster** tier instead — the case with no derivation at
    /// all, which is the one §4.5's two new key fields exist for.
    private func posedRasterLayer(_ layerPose: LayerPose) -> (manager: CanvasManager, drawn: Int) {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addLayer(name: "ink")
        manager.addValueLayer(name: "mover")
        let drawn = manager.layers.firstIndex { $0.name == "ink" } ?? 0
        manager.sceneFrameCount = 12
        manager.layers[drawn].cels[0].frameCount = 12
        CanvasFixture.setBakedContent(manager, layerIndex: drawn,
                                      CanvasFixture.solidImage(.black,
                                                               rect: CGRect(x: 4, y: 8, width: 8, height: 6)))
        if let at = manager.layers.firstIndex(where: { $0.name == "mover" }) {
            manager.layers[at].transform = layerPose
        }
        return (manager, drawn)
    }

    // MARK: - Scope (§4.4)

    /// **§4.4's scope rule, and every wrong answer to it in one assertion.** *"A value layer with an
    /// effect grades everything beneath it inside its own container. A transform layer uses the same
    /// rule."*
    ///
    /// The four layers that must *not* move are each a different mistake: `above` is "everything in
    /// the folder", `floor` is "everything beneath it anywhere", `outside` is "everything in the
    /// document", and `mover` itself is a leaf that holds no pixels and has nothing to pose.
    func testATransformLayerPosesWhatIsBeneathItInItsOwnContainerAndNothingElse() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        let poses = stack.manager.layerPoses(atFrame: 0)

        XCTAssertEqual(Set(poses.keys), [stack.inner],
                       "Only the entry beneath the transform layer *in its own container* is posed")
        XCTAssertEqual(poses[stack.inner]?.tx, 12)
    }

    /// **The containment §4.4 says nothing downstream can enforce.** The pose lives in a local of the
    /// folder's own recursion and travels only downward, so a layer at the root beneath the folder
    /// cannot see it — which is what `floor` is in the fixture above, and it is separated out here
    /// because it is the failure with no symptom: a pose that leaked out would move artwork the
    /// artist never put in the group, and nothing in the tree, the composite or any cache key would
    /// look wrong.
    func testAPoseDoesNotEscapeItsFolder() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        let poses = stack.manager.layerPoses(atFrame: 0)
        XCTAssertNil(poses[stack.floor], "A pose must not reach out of the container it was set in")
        XCTAssertNil(poses[stack.outside])
    }

    /// §2.21's folder form: a posed folder moves everything *inside* it, at any depth, and nothing
    /// outside. The complement of the layer form — `above` moves here and does not above.
    func testAFolderPosesEverythingInsideItAndNothingOutside() {
        let stack = makeStack(mover: nil)
        guard let at = stack.manager.folders.firstIndex(where: { $0.id == stack.folder }) else {
            return XCTFail("The fixture's folder went missing")
        }
        stack.manager.folders[at].transform = pose(CGAffineTransform(translationX: 5, y: 0))

        let poses = stack.manager.layerPoses(atFrame: 0)
        XCTAssertEqual(Set(poses.keys), [stack.inner, stack.mover, stack.above],
                       "A folder's pose is its contents' pose, and only its contents'")
        XCTAssertNil(poses[stack.floor])
        XCTAssertNil(poses[stack.outside])
    }

    /// **Composition order, with two maps that do not commute.**
    ///
    /// A leaf under two transformation layers is moved by the lower one and then carried by the upper
    /// one. Written with a rotate above a translate on purpose: with two translations every order
    /// gives the same answer, so a test built from those would be green against the reversed
    /// composition and against no composition at all beyond addition.
    func testTwoStackedTransformLayersComposeInnerFirst() throws {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "ink")
        manager.addValueLayer(name: "lower")
        manager.addValueLayer(name: "upper")
        let ink = manager.layers.firstIndex { $0.name == "ink" } ?? 0
        let slide = CGAffineTransform(translationX: 10, y: 0)
        let turn = CGAffineTransform(rotationAngle: .pi / 2)
        manager.layers[manager.layers.firstIndex { $0.name == "lower" }!].transform = pose(slide)
        manager.layers[manager.layers.firstIndex { $0.name == "upper" }!].transform = pose(turn)

        let composed = try XCTUnwrap(manager.layerPoses(atFrame: 0)[ink])
        // Slide then turn: (0,0) → (10,0) → (0,10). The other order would put it at (0,0) → (0,0) →
        // (10,0), which is a different picture and the same two matrices.
        let landed = CGPoint.zero.applying(composed)
        XCTAssertEqual(landed.x, 0, accuracy: 1e-9)
        XCTAssertEqual(landed.y, 10, accuracy: 1e-9)
    }

    /// **The `kind` half of `Layer.layerTransform`, and it is the trap CLAUDE.md names by name.** A
    /// pose left on a layer whose kind is not `.value` must reach nothing — otherwise a layer changed
    /// back to raster silently goes on moving the stack, and every test in this file that set the
    /// field without the kind would have been measuring the field rather than the feature.
    func testAPoseOnALayerThatIsNotAValueLayerReachesNothing() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        stack.manager.layers[stack.mover].kind = .raster
        XCTAssertTrue(stack.manager.layerPoses(atFrame: 0).isEmpty)
    }

    /// **And a grade wins over a pose**, which is `Layer.transform`'s stated precedence. Only a
    /// hand-written manifest can carry both; what matters is that the renderer and the panel resolve
    /// it the same way rather than each asking its own accessor first.
    func testAGradeOnTheSameLayerWinsOverAPose() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        stack.manager.layers[stack.mover].effect = .posterize(Effect.Posterize())
        XCTAssertTrue(stack.manager.layerPoses(atFrame: 0).isEmpty)
        XCTAssertNotNil(stack.manager.layers[stack.mover].layerEffect)
    }

    /// **The safety property the whole feature is shaped around.** A document with no transformation
    /// layer mints no pose entries at all, so nothing downstream — not a derivation, not a cache key,
    /// not a canvas-sized render — is paid for by a document that has never used this.
    func testADocumentWithNoTransformLayerMintsNoPoses() {
        let stack = makeStack(mover: nil)
        XCTAssertTrue(stack.manager.layerPoses(atFrame: 0).isEmpty)
    }

    /// A transformation layer the artist has added and not yet moved is resting, and resting is
    /// **absent** rather than present-and-identity — `LayerPose.mapping(atFrame:)`'s rule, asked from
    /// the tree side, because an entry in this dictionary is what gives a leaf a derivation.
    func testARestingTransformLayerMintsNoPoses() {
        let stack = makeStack(mover: LayerPose(restingIn: canvasBox))
        XCTAssertTrue(stack.manager.layerPoses(atFrame: 0).isEmpty)
    }

    // MARK: - The time base (§3.1)

    /// **§3.1's ruling, in the one place it can be got wrong.** A layer-scoped channel is in
    /// **absolute document frames** because its target has no cel to ride; the cel below it starts at
    /// frame 4, so a reader that subtracted a `startFrame` — as every cel-scoped channel correctly
    /// does — would resolve frame 8 to the track's frame 4 and show half the move.
    ///
    /// The keys are at 0 and 8 and the assertion is at 8, where the two readings differ by the whole
    /// of the animation rather than by a rounding.
    func testATransformLayersTrackIsReadInAbsoluteDocumentFrames() throws {
        let (manager, drawn) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        manager.layers[drawn].cels[0].startFrame = 4
        manager.layers[drawn].cels[0].frameCount = 12

        XCTAssertNil(manager.layerPoses(atFrame: 0)[drawn], "Frame 0 holds the resting key")
        let atEight = try XCTUnwrap(manager.layerPoses(atFrame: 8)[drawn])
        XCTAssertEqual(atEight.tx, 24, accuracy: 1e-6,
                       "Frame 8 is the second key's own frame — not frame 8 minus the cel's start")
    }

    // MARK: - The mode (§2.6)

    /// A `.value` layer in transform mode is neither of the other two things, so nothing paints a
    /// canvas-sized sheet of colour under the move.
    func testALayerInTransformModeIsNeitherAFlatColourNorAGrade() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        let mover = stack.manager.layers[stack.mover]
        XCTAssertNotNil(mover.fill, "`addValueLayer` stamps one, and transform mode leaves it stored")
        XCTAssertNil(mover.valueFill, "…and inert, exactly as effect mode leaves it")
        XCTAssertNil(mover.layerEffect)
        XCTAssertNotNil(mover.layerTransform)
    }

    /// **`leafSnapshots` has to elide it, and the two ends of that have to agree.** The tree gives the
    /// transformation layer a leaf (leaf order is `layers.indices` and the tree reorders nothing), so
    /// the snapshot is where "this leaf holds no pixels" is decided — and a leaf carrying a version
    /// and no content is the state §4.4's grading layer already put there.
    func testATransformLayerContributesAVersionAndNoPixels() throws {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        let recipe = try XCTUnwrap(stack.manager.makeFrameRecipe(atFrame: 0, includeBackground: false))
        let leaf = try XCTUnwrap(recipe.leaves[stack.mover])
        XCTAssertNil(leaf.content, "A transformation layer holds no pixels — rasterizing its blank "
                     + "cel would mint a canvas-sized transparent image per frame")
        XCTAssertEqual(recipe.tree.leafLayerIndices, Array(stack.manager.layers.indices),
                       "…and it is still a leaf: the tree reorders nothing and drops nothing")
    }

    // MARK: - What the ink does (§2.3, §2.12)

    /// **The whole feature, in pixels, through the shipped flatten.** A cel with no channel of its
    /// own, moved only by the layer above it, must show its ink where the pose puts it.
    func testAContainerPoseMovesInkOnACelWithNoChannelOfItsOwn() throws {
        let (manager, drawn) = posedVectorLayer(pose(CGAffineTransform(translationX: 20, y: 0)))
        let cel = manager.layers[drawn].cels[0]
        XCTAssertTrue(cel.transformTracks.isEmpty, "The premise: this cel is moved only from above")

        let resting = PixelOps.rasterize(cel: cel, canvasSize: size, derived: nil, pose: nil)
        let posed = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(
                                        for: cel, atFrame: 0,
                                        inheriting: manager.layerPoses(atFrame: 0)[drawn]),
                                       pose: manager.layerPoses(atFrame: 0)[drawn])
        let restBounds = try XCTUnwrap(inkBounds(resting))
        let posedBounds = try XCTUnwrap(inkBounds(posed))
        XCTAssertEqual(posedBounds.minX - restBounds.minX, 20, accuracy: 1.5)
    }

    /// **§2.3's *"crisp lines, not a bitmap magnify"*, asserted where the decision actually lives.**
    ///
    /// The pixel test above would be satisfied by a bitmap translate, which is why this one is
    /// separate and is about a **stretch**: ink re-posed as geometry takes `sqrt(|det|)` for its width
    /// (LASSO_MOVE.md §5.17) and lands its spine on the map, while a resampled bitmap would carry the
    /// per-axis scale into the picture instead. A 4:1 stretch is a width of 2×, not 4× and not 1×.
    func testContainerPosedInkIsRePosedAsGeometryRatherThanResampled() throws {
        let elements: [VectorElement] = [.stroke(stroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
                                                        size: 8))]
        let posed = CanvasManager.posed(elements, through: [],
                                        inheriting: CGAffineTransform(scaleX: 4, y: 1))
        let after = try XCTUnwrap(posed.first?.stroke)
        XCTAssertEqual(after.size, 16, accuracy: 1e-9, "sqrt(|det|) of a 4:1 stretch is 2")
        XCTAssertEqual(after.samples.last?.point.x ?? 0, 40, accuracy: 1e-6)
    }

    /// **§4.4's *"two placed-object refusals ride along"* is stale, and this is the measurement that
    /// says so.**
    ///
    /// That section was written against a `mapping(_:throughStretch:)` that `assertionFailure`d on a
    /// placed image, and asked for the assert to become a refusal the artist can read. LASSO_MOVE.md
    /// stage 3c has since given `VectorImageElement` a stored shape — `aspect`, `stretchAxis`,
    /// `mirrored` — and `VectorCanvas.placed(_:through:)` composes and re-decomposes an arbitrary
    /// affine through it. There is no assert left in that file and nothing to refuse: a photo under a
    /// transformation layer travels with the strokes around it. So the refusal §4.4 asks for is not
    /// built, deliberately, and this is what would go red if the arm ever regressed to leaving the
    /// image behind — which is the failure the refusal existed to make visible.
    func testAPlacedImageFollowsAContainerPoseRatherThanBeingRefused() throws {
        let placed = VectorImageElement(
            image: CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                            size: CGSize(width: 6, height: 6)),
            transform: LayerTransform(position: CGPoint(x: 10, y: 10), scale: 1, rotation: 0))
        let posed = CanvasManager.posed([.image(placed)], through: [],
                                        inheriting: CGAffineTransform(translationX: 20, y: 0))
        guard case .image(let moved)? = posed.first else {
            return XCTFail("A placed image under a transformation layer is still a placed image")
        }
        XCTAssertEqual(moved.transform.position.x, 30, accuracy: 1e-6)
        XCTAssertEqual(moved.transform.position.y, 10, accuracy: 1e-6)
    }

    /// A cel's own channel and its container's pose **compose**, in that order: the channel moves
    /// something within the drawing and the container moves the drawing.
    func testACelsOwnChannelAndItsContainerPoseCompose() throws {
        let elements: [VectorElement] = [.stroke(stroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]))]
        let posed = CanvasManager.posed(elements,
                                        through: [(.cel, CGAffineTransform(translationX: 5, y: 0))],
                                        inheriting: CGAffineTransform(scaleX: 2, y: 2))
        let after = try XCTUnwrap(posed.first?.stroke)
        // Channel first: 0 → 5, then the container's 2× → 10. The other order gives 0 → 0 → 5.
        XCTAssertEqual(after.samples.first?.point.x ?? -1, 10, accuracy: 1e-6)
    }

    /// §2.12's other currency, and it is the half this feature is *not* named for: a cel whose ink is
    /// in the raster tier has no display list to re-pose, so it is resampled through the CTM instead.
    /// The owner ruled the difference inherent — *"a raster layer softens under a push-in while the
    /// vector layer beside it stays sharp"* — so the pin is that it moves at all, not that it is
    /// crisp.
    func testRasterContentUnderATransformLayerIsResampledRatherThanLeftBehind() throws {
        let (manager, drawn) = posedRasterLayer(pose(CGAffineTransform(translationX: 20, y: 0)))
        let cel = manager.layers[drawn].cels[0]
        XCTAssertNil(manager.derivedCelContent(for: cel, atFrame: 0,
                                               inheriting: manager.layerPoses(atFrame: 0)[drawn]),
                     "The premise: a cel with no vector tier has no derivation at all")

        let resting = PixelOps.rasterize(cel: cel, canvasSize: size, pose: nil)
        let posed = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       pose: manager.layerPoses(atFrame: 0)[drawn])
        let restBounds = try XCTUnwrap(inkBounds(resting))
        let posedBounds = try XCTUnwrap(inkBounds(posed))
        XCTAssertEqual(posedBounds.minX - restBounds.minX, 20, accuracy: 1.5)
    }

    // MARK: - §4.5's caching trap, one test per key

    /// **`PixelOps.RasterizeKey`, through `PosedCelIdentity.inherited`.** Two frames of a move over a
    /// *vector* cel: warmed with the earlier frame first, which is the order that produces the defect.
    ///
    /// The cel carries no channel of its own, so every other field of both keys is byte-identical at
    /// the two frames and the container pose is the only thing that can separate them.
    func testTwoFramesOfAContainerPosedVectorCelAreTwoFlattens() throws {
        let (manager, drawn) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let cel = manager.layers[drawn].cels[0]

        func flatten(_ frame: Int) -> UIImage {
            let pose = manager.layerPoses(atFrame: frame)[drawn]
            return PixelOps.rasterize(cel: cel, canvasSize: size,
                                      derived: manager.derivedCelContent(for: cel, atFrame: frame,
                                                                         inheriting: pose),
                                      pose: pose)
        }
        let early = try XCTUnwrap(inkBounds(flatten(2)))
        let late = try XCTUnwrap(inkBounds(flatten(8)))
        XCTAssertGreaterThan(late.minX - early.minX, 12,
                             "Frame 8 is 24pt along a linear span and frame 2 is 6pt — one flatten "
                             + "cannot be both")
    }

    /// **The derivation identity itself**, which is what `PosedCelIdentity.inherited` is *for* and
    /// what the test above cannot isolate — `PixelOps.FrozenCel.Identity.pose` would keep that one
    /// green on its own.
    ///
    /// `CanvasView.updateInterpolationPreviews` builds `InterpolationPreviewKey` out of this identity
    /// and nothing else, so without the field the live canvas freezes on the first posed frame it
    /// drew while every export of the same frames moves — two paths disagreeing with nothing between
    /// them, which is the shape this file's sibling already caught once.
    func testTheDerivationIdentityCarriesTheContainerPose() throws {
        let (manager, drawn) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let cel = manager.layers[drawn].cels[0]
        let early = try XCTUnwrap(manager.derivedCelContent(
            for: cel, atFrame: 2, inheriting: manager.layerPoses(atFrame: 2)[drawn])?.identity)
        let late = try XCTUnwrap(manager.derivedCelContent(
            for: cel, atFrame: 8, inheriting: manager.layerPoses(atFrame: 8)[drawn])?.identity)
        XCTAssertNotEqual(early, late)
    }

    /// **`PixelOps.FrozenCel.Identity.pose`, isolated by using a cel that has no derivation at all.**
    /// A raster cel answers nil from `posedCelContent`, so the derived half of both keys is nil at
    /// every frame and this field is the only thing left. Delete it and the memo hands the first
    /// frame's pixels to the whole move.
    func testARasterCelUnderATransformLayerIsNotServedFromItsUnposedFlatten() throws {
        let (manager, drawn) = posedRasterLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let cel = manager.layers[drawn].cels[0]

        let early = try XCTUnwrap(inkBounds(PixelOps.rasterize(
            cel: cel, canvasSize: size, pose: manager.layerPoses(atFrame: 2)[drawn])))
        let late = try XCTUnwrap(inkBounds(PixelOps.rasterize(
            cel: cel, canvasSize: size, pose: manager.layerPoses(atFrame: 8)[drawn])))
        XCTAssertGreaterThan(late.minX - early.minX, 12)
    }

    /// **The other direction, and it is what stops all three tests above passing for the wrong
    /// reason.** A key that were unique per call would satisfy every one of them and cache nothing.
    /// Two frames a *held* pose covers are one picture and must share one entry: frames 9 and 11 are
    /// both past the last key, where `AnimationCurve`'s constant hold gives them one pose.
    func testAHeldContainerPoseIsStillOneCacheEntry() throws {
        let (manager, drawn) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let cel = manager.layers[drawn].cels[0]
        XCTAssertEqual(manager.layerPoses(atFrame: 9)[drawn], manager.layerPoses(atFrame: 11)[drawn])
        let a = try XCTUnwrap(manager.derivedCelContent(
            for: cel, atFrame: 9, inheriting: manager.layerPoses(atFrame: 9)[drawn])?.identity)
        let b = try XCTUnwrap(manager.derivedCelContent(
            for: cel, atFrame: 11, inheriting: manager.layerPoses(atFrame: 11)[drawn])?.identity)
        XCTAssertEqual(a, b, "One pose is one picture, however many frames hold it")
    }

    /// **`LayerContentVersion.pose` — the key §4.5 names beside the flatten memo**, and `MaskResolver`
    /// is what spends it. Asserted over a raster cel for the reason above: with a vector cel the
    /// derivation identity would carry the pose and this field could be deleted with the suite green.
    ///
    /// Goes through the shipped `contentVersion(ofLayer:atFrame:)` — the one builder `leafSnapshots`
    /// and `CanvasView.SandwichKey` share — rather than constructing a version by hand, so a field
    /// added to one of those and not the other is what this can catch.
    func testTheContentVersionOfARasterLeafCarriesTheContainerPose() throws {
        let (manager, drawn) = posedRasterLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let early = try XCTUnwrap(manager.contentVersion(ofLayer: drawn, atFrame: 2))
        let late = try XCTUnwrap(manager.contentVersion(ofLayer: drawn, atFrame: 8))
        XCTAssertNotEqual(early, late,
                          "Two frames of a move are two coverages — a mask over this leaf resolves "
                          + "different alpha at each")
        XCTAssertEqual(early, try XCTUnwrap(manager.contentVersion(ofLayer: drawn, atFrame: 2)),
                       "…and the same frame is the same version, or nothing caches")
    }

    /// **`FrameBakeKey`, which is the one key in this set that no compiler could have caught.** That
    /// file's rule 1 — no `default:` anywhere — turns a new *enum case* into a compile error; a new
    /// stored property on `LayerContentVersion` is not a compile error anywhere, and the hand-written
    /// walk would simply stop naming it.
    ///
    /// A content-addressed disk store has no second chance: the filename *is* the digest, so two
    /// frames of a move would resolve to one file and the store would serve the first frame's pixels
    /// for the whole move with no error anywhere. A raster leaf again, so the digest's only route to
    /// the pose is `encode(version:)`.
    func testTheBakeDigestMovesWithAContainerPose() throws {
        let (manager, _) = posedRasterLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        func digest(_ frame: Int) throws -> Data {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: frame, includeBackground: false))
            return FrameBakeKey(recipe: recipe, renderResolution: .full).digest
        }
        XCTAssertNotEqual(try digest(2), try digest(8))
        XCTAssertEqual(try digest(9), try digest(11),
                       "…and two frames of a held pose are still one file, which is what the store "
                       + "leaving `frame` out of the key is for")
    }

    // MARK: - The one arm that declines a container pose

    /// **§2.18's refusal, stated rather than silent.** A derived in-between has no stable elements —
    /// its display list is computed — and `InterpolationEvaluator.render` answers with an image rather
    /// than with the elements a pose maps, so there is nothing for §2.3's *"re-poses the vector
    /// objects"* to act on. The available alternative is to resample that image, which is the bitmap
    /// magnify §2.3 exists to refuse.
    ///
    /// **The assertion is that the pose does not enter the key**, which is the part that would
    /// otherwise cost something: a value carried but unread mints a second cache entry per frame of a
    /// move for pixels that did not change. If this went red the code would be wrong in one of two
    /// ways — the pose reached the identity without reaching the render, or the interpolation arm
    /// started posing and this test needs replacing with one that measures the pixels.
    func testAnInterpolatedCelDeclinesTheContainerPoseAndDoesNotKeyOnIt() throws {
        let (manager, drawn) = posedVectorLayer(pose(CGAffineTransform(translationX: 24, y: 0)))
        let celID = manager.layers[drawn].cels[0].id
        let layerID = manager.layers[drawn].id
        manager.layers[drawn].cels[0].interpolation = InterpolationRecipe(
            references: [InterpolationReference(layerID: layerID, celID: celID)], t: 0.5)
        let cel = manager.layers[drawn].cels[0]

        let unposed = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 0)?.identity)
        let posed = try XCTUnwrap(manager.derivedCelContent(
            for: cel, atFrame: 0,
            inheriting: manager.layerPoses(atFrame: 0)[drawn])?.identity)
        XCTAssertEqual(unposed, posed)
    }

    // MARK: - Persistence

    /// §3.5's field-presence idiom, on both of the two homes. A transformation layer whose pose did
    /// not survive a reload would look like an ordinary value layer painting mid-grey over the stack,
    /// which is a wrong picture rather than a lost setting.
    func testATransformLayerAndAPosedFolderSurviveASaveAndReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform-layer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let stack = makeStack(mover: animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        guard let folderAt = stack.manager.folders.firstIndex(where: { $0.id == stack.folder }) else {
            return XCTFail("The fixture's folder went missing")
        }
        stack.manager.folders[folderAt].transform = pose(CGAffineTransform(scaleX: 2, y: 2))
        let moverID = stack.manager.layers[stack.mover].id

        let url = root.appendingPathComponent("round-trip.paintproj", isDirectory: true)
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(stack.manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let mover = try XCTUnwrap(reloaded.layers.first { $0.id == moverID })
        XCTAssertEqual(mover.transform, stack.manager.layers[stack.mover].transform,
                       "The pose and its whole track, key handles included")
        XCTAssertNotNil(mover.layerTransform, "…and still live, which needs the kind as well")
        XCTAssertEqual(reloaded.folders.first { $0.id == stack.folder }?.transform,
                       stack.manager.folders[folderAt].transform)
        XCTAssertEqual(Set(reloaded.layerPoses(atFrame: 8).keys),
                       Set(stack.manager.layerPoses(atFrame: 8).keys),
                       "The reloaded document poses the same leaves, which is the only thing the "
                       + "artist can actually see")
    }
}
