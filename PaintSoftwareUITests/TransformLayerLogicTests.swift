import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for **the transformation layer** — KEYFRAMES.md §2.3, §4.4 and §4.5, the half of
/// TODO (21) that moves whatever is *under* a layer rather than what is *on* a cel.
///
/// `TransformChannelLogicTests` beside this one pins the cel-scoped channel — a drawing moving inside
/// its own cel. This one pins the container-scoped pose: a `.transform` layer (TRANSFORM_LAYER.md §2
/// ruling 2 — its own kind since 2026-09-11, a mode of `.value` before) moving everything beneath it
/// in its container, and a folder moving everything inside it.
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

    override func tearDown() {
        // The span tests below switch backends; the default rather than a literal, for
        // `Compositor.defaultBackend`'s reason.
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    /// The composite's bytes at `frame` on the backend currently selected — what the artist sees,
    /// rather than what the model stores.
    private func compositeBytes(_ manager: CanvasManager, atFrame frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    /// Runs `body` once per backend, skipping Metal where this bundle has no device or shader.
    private func onBothBackends(_ body: (CompositorBackend) throws -> Void) throws {
        for backend in [CompositorBackend.coreGraphics, .metal] {
            if backend == .metal, CompositorMetalEngine.shared == nil { continue }
            Compositor.backend = backend
            try body(backend)
        }
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "CoreGraphics ran; no Metal device or shader library in this bundle for the second backend")
    }

    // MARK: - Fixtures

    private func stroke(_ points: [CGPoint], size strokeSize: CGFloat = 6) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: strokeSize, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
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

    /// **`animatedPose`'s shape, but every segment `.linear`** — for a "the pose the block showed at
    /// every remaining frame is unchanged by the crop" test, which `.bezier`/`.autoClamped`'s default
    /// tangent cannot honestly make: `AnimationCurve.effectiveHandles(at:)` computes a key's tangent
    /// from *both* neighbours, so removing a key past it changes the *other* neighbour's tangent too
    /// — a segment strictly between two keys that never moved can still change shape. `.linear`
    /// (`AnimationCurve.value(inSegmentStartingAt:at:)`'s `.linear` case) reads only a segment's own
    /// two endpoints, so a key's crop cannot be felt anywhere but past it.
    private func linearAnimatedPose(_ keys: [(frame: Int, transform: CGAffineTransform)]) -> LayerPose {
        LayerPose(pose: PoseQuad(restingIn: canvasBox),
                  track: TransformTrack(keys: keys.map {
                    .init(frame: $0.frame, pose: PoseQuad(box: canvasBox, mappedBy: $0.transform),
                         interpolation: .linear)
                  }))
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
    /// | 2 | `mover`, a `.transform` layer — or a plain value layer when no pose is given | inside folder `F` |
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
        // A transform layer when the test hands in a pose; a plain value layer when it hands in nil,
        // so that "a document with no transformation layer" is a document with none rather than one
        // whose transform layer happens to hold no pose.
        if moverPose != nil { manager.addTransformLayer(name: "mover") } else { manager.addValueLayer(name: "mover") }
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
        if let moverPose, let at = manager.layers.firstIndex(where: { $0.name == "mover" }) {
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
        manager.addTransformLayer(name: "mover")
        let drawn = manager.layers.firstIndex { $0.name == "ink" } ?? 0
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[drawn].cels = [cel]
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
        manager.addTransformLayer(name: "mover")
        let drawn = manager.layers.firstIndex { $0.name == "ink" } ?? 0
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
        XCTAssertEqual(poses[stack.inner]?.affine?.tx, 12)
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
        // **The value, not only the key set** — the layer form's own test one door up asserts
        // `tx == 12`, and this one asserted membership alone until TODO (21) gave the field a writer.
        // A pose that reached the right three leaves carrying the identity map would have satisfied
        // the assertions above, which is the shape of "a correct set drawn as nothing moving".
        XCTAssertEqual(poses[stack.inner]?.affine?.tx, 5)
        XCTAssertEqual(poses[stack.mover]?.affine?.tx, 5)
        XCTAssertEqual(poses[stack.above]?.affine?.tx, 5)
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
        manager.addTransformLayer(name: "lower")
        manager.addTransformLayer(name: "upper")
        let ink = manager.layers.firstIndex { $0.name == "ink" } ?? 0
        let slide = CGAffineTransform(translationX: 10, y: 0)
        let turn = CGAffineTransform(rotationAngle: .pi / 2)
        manager.layers[manager.layers.firstIndex { $0.name == "lower" }!].transform = pose(slide)
        manager.layers[manager.layers.firstIndex { $0.name == "upper" }!].transform = pose(turn)

        let composed = try XCTUnwrap(manager.layerPoses(atFrame: 0)[ink])
        // Slide then turn: (0,0) → (10,0) → (0,10). The other order would put it at (0,0) → (0,0) →
        // (10,0), which is a different picture and the same two matrices.
        let landed = try XCTUnwrap(composed.applied(to: .zero))
        XCTAssertEqual(landed.x, 0, accuracy: 1e-9)
        XCTAssertEqual(landed.y, 10, accuracy: 1e-9)
    }

    /// **The `kind` half of `Layer.layerTransform`, and it is the trap CLAUDE.md names by name.** A
    /// pose left on a layer whose kind is not `.transform` must reach nothing — otherwise a layer
    /// changed to raster silently goes on moving the stack, and every test in this file that set the
    /// field without the kind would have been measuring the field rather than the feature. Both
    /// other-kind cases, because `.value` is the one a pre-2026-09-11 document's inert grade-over-pose
    /// storage would have carried, and it must stay inert.
    func testAPoseOnALayerThatIsNotATransformLayerReachesNothing() {
        for kind in [LayerKind.raster, .value] {
            let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
            stack.manager.layers[stack.mover].kind = kind
            XCTAssertTrue(stack.manager.layerPoses(atFrame: 0).isEmpty, "a pose on a \(kind) layer")
            XCTAssertNil(stack.manager.layers[stack.mover].layerTransform, "…through the accessor too")
        }
    }

    /// **And a grade left on a transform layer reaches nothing either** — the kind is the
    /// discriminant on both sides. Under the old three-payload precedence a grade beside a pose won
    /// and parked the pose; now only a hand-written manifest can carry both, and what matters is that
    /// the renderer and the panel read the same answer: this layer poses, and it grades nothing.
    func testAGradeOnATransformLayerIsInertAndThePoseStillReaches() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        stack.manager.layers[stack.mover].effect = .posterize(Effect.Posterize())
        XCTAssertEqual(Set(stack.manager.layerPoses(atFrame: 0).keys), [stack.inner])
        XCTAssertNil(stack.manager.layers[stack.mover].layerEffect)
        XCTAssertNil(stack.manager.layers[stack.mover].layerEffect(atFrame: 0))
    }

    /// **§4.3's isolation, which §4.4 asks for by name when it says to reuse the existing
    /// `containerIsNode` machinery.** Inside a compositor node the entry one step down is the *other
    /// operand*, not something beneath — inputs are isolated from each other, and one operand posing
    /// another is the cross-input dependency isolation exists to prevent, arriving as a move nobody
    /// authored. So a transformation layer dropped into a Mix reaches nothing.
    ///
    /// **The complement is asserted in the same test**, because suppressing too much is the other way
    /// to get this wrong: a pose from *outside* the node still reaches everything the node is built
    /// from, since whatever poses the node poses its operands too.
    func testATransformLayerInsideACompositorNodePosesNoOtherOperand() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "operand")
        manager.addTransformLayer(name: "mover")
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix")
        for name in ["operand", "mover"] {
            guard let at = manager.layers.firstIndex(where: { $0.name == name }) else { continue }
            manager.layers[at].parentFolderID = node
        }
        let slide = CGAffineTransform(translationX: 12, y: 0)
        manager.layers[manager.layers.firstIndex { $0.name == "mover" }!].transform = pose(slide)
        XCTAssertTrue(manager.layerPoses(atFrame: 0).isEmpty,
                      "An operand's pose is not the node's answer to how its inputs combine")

        // …and the node itself, posed from outside, still carries both of its operands.
        guard let at = manager.folders.firstIndex(where: { $0.id == node }) else {
            return XCTFail("The node went missing")
        }
        manager.folders[at].transform = pose(slide)
        XCTAssertEqual(manager.layerPoses(atFrame: 0).count, 2)
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
        XCTAssertEqual(try XCTUnwrap(atEight.affine).tx, 24, accuracy: 1e-6,
                       "Frame 8 is the second key's own frame — not frame 8 minus the cel's start")
    }

    // MARK: - The kind (TRANSFORM_LAYER.md §2 ruling 2)

    /// A transform layer is neither a flat colour nor a grade, so nothing paints a canvas-sized sheet
    /// of colour under the move — and it is its own kind, with no fill stamped on it at all, where
    /// the old transform *mode* of a value layer carried the fill as inert storage.
    func testATransformLayerIsItsOwnKindAndNeitherAFlatColourNorAGrade() {
        let stack = makeStack(mover: pose(CGAffineTransform(translationX: 12, y: 0)))
        let mover = stack.manager.layers[stack.mover]
        XCTAssertEqual(mover.kind, .transform)
        XCTAssertNil(mover.fill, "`addTransformLayer` stamps no fill — there is no mode to flip back to")
        XCTAssertNil(mover.valueFill)
        XCTAssertNil(mover.layerEffect)
        XCTAssertNotNil(mover.layerTransform)
        XCTAssertTrue(mover.hasNoDrawingSurface, "a stroke has nowhere to land on it")
        XCTAssertFalse(mover.isFillReference, "…and it is no wall for the fill tool either")
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

    /// **The folder-posed analogue of the test above, in pixels** — TODO (21).
    ///
    /// The test above proves a folder's pose reaches its children's *entries in the pose map*; this
    /// one proves the ink lands somewhere else on the canvas because of it. They are separate for
    /// the reason CLAUDE.md gives about a correct value drawn in the wrong place: `layerPoses` could
    /// answer perfectly while `PixelOps.rasterize` ignored what it was handed, and the map assertion
    /// alone could not tell the two apart. Now that `setFolderTransform` lets an artist reach this
    /// field at all, the pixel end of it is worth pinning rather than inferring.
    func testAFolderPosedCelRasterizesAtTheShiftedPosition() throws {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "ink")
        let drawn = manager.layers.firstIndex { $0.name == "ink" } ?? 0
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[drawn].cels = [cel]
        let folder = manager.addFolder(name: "F")
        manager.layers[drawn].parentFolderID = folder
        guard let fAt = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("fixture folder missing")
        }
        manager.folders[fAt].transform = pose(CGAffineTransform(translationX: 20, y: 0))

        let resting = PixelOps.rasterize(cel: cel, canvasSize: size, derived: nil, pose: nil)
        let posed = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(
                                        for: cel, atFrame: 0,
                                        inheriting: manager.layerPoses(atFrame: 0)[drawn]),
                                       pose: manager.layerPoses(atFrame: 0)[drawn])
        let restBounds = try XCTUnwrap(inkBounds(resting))
        let posedBounds = try XCTUnwrap(inkBounds(posed))
        XCTAssertEqual(posedBounds.minX - restBounds.minX, 20, accuracy: 1.5,
                       "Ink inside a posed folder is drawn 20pt to the right of where it rests")
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
                                        inheriting: PoseMap(CGAffineTransform(scaleX: 4, y: 1)))
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
                                        inheriting: PoseMap(CGAffineTransform(translationX: 20, y: 0)))
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
                                        through: [(.cel, PoseMap(CGAffineTransform(translationX: 5, y: 0)))],
                                        inheriting: PoseMap(CGAffineTransform(scaleX: 2, y: 2)))
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

    // MARK: - The span (TRANSFORM_LAYER.md §2 ruling 1: the bar means "only here")

    /// **Shorten the bar and the frames past it show the drawing unposed, on both backends, byte for
    /// byte — ruling 1, unaffected by ruling 17's reversal.** The pose is keyed 0 → 24 px over frames
    /// 0…8 and in force at 8 while the bar covers it; cut the bar back to 6 and frame 8's composite is
    /// exactly the composite of the same document with the transform layer hidden. Watched failing
    /// with the accumulator's `activeCelIndex` clause removed: frame 8 stays posed.
    func testShorteningTheBarLeavesTheFramesPastItUnposed() throws {
        try onBothBackends { backend in
            let (manager, drawn) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
            let mover = try XCTUnwrap(manager.layers.firstIndex { $0.name == "mover" })
            XCTAssertNotNil(manager.layerPoses(atFrame: 8)[drawn], "Premise: posed at 8 while the bar covers it")
            let posed = try compositeBytes(manager, atFrame: 8)

            // What "unposed" is, measured rather than assumed: the same document with the transform
            // layer resting — resting is absent (`testARestingTransformLayerMintsNoPoses`), so this
            // is the picture with no pose in it and nothing else changed.
            let authored = manager.layers[mover].transform
            manager.layers[mover].transform = LayerPose(restingIn: canvasBox)
            let unposed = try compositeBytes(manager, atFrame: 8)
            manager.layers[mover].transform = authored
            XCTAssertNotEqual(posed, unposed, "Premise: the pose moves pixels at 8 (\(backend))")

            manager.resizeCelRightEdge(layerIndex: mover, celIndex: 0, newEndFrame: 6)
            XCTAssertNil(manager.activeCelIndex(inLayer: mover, atFrame: 8), "The bar now ends before 8")
            XCTAssertNil(manager.layerPoses(atFrame: 8)[drawn], "…so the render poses nothing there")
            XCTAssertEqual(try compositeBytes(manager, atFrame: 8), unposed,
                           "…and what is drawn at 8 is the unposed drawing, byte for byte (\(backend))")
            XCTAssertNotNil(manager.layerPoses(atFrame: 4)[drawn], "Inside the bar the pose is still in force")
        }
    }

    /// **Ruling 17, reversed 2026-09-11 (txcrop): shortening the bar past a key crops it, with a
    /// boundary key first, one undo step, and a banner** — replacing the old "kept, inert" pin.
    /// Keyed 0 → 12 px → 24 px over frames 0, 4 and 8 (three keys, not two, so "a key inside stays"
    /// is not the same case as "the edge survives"), `linearAnimatedPose` rather than `animatedPose`
    /// (see that helper's doc for why); shorten to 6 and 8 is discarded, 4 stays untouched, and a key
    /// lands on 5 — the new last frame — carrying whatever the block showed there before the crop,
    /// measured against a render taken *before* the resize rather than hand-derived, on both backends.
    ///
    /// Watched failing two ways: with `cropTransformLayerKeysToBlocks`'s call removed from
    /// `resizeCelRightEdge` (the keys read `[0, 4, 8]` and every frame-0..<6 assertion still passes,
    /// since nothing was cropped to disagree with the "before" snapshot — this is the mutation the
    /// crop assertion catches); and with the boundary insertion suppressed inside
    /// `TransformTrack.croppedToBlocks` (the keys read `[0, 4]` and frame 5's composite changes,
    /// which is the mutation the every-remaining-frame assertion catches).
    func testShorteningTheBarCropsTheKeyPastItWithABoundaryAndTellsTheArtist() throws {
        try onBothBackends { backend in
            let (manager, _) = posedVectorLayer(linearAnimatedPose([
                (frame: 0, transform: .identity),
                (frame: 4, transform: CGAffineTransform(translationX: 12, y: 0)),
                (frame: 8, transform: CGAffineTransform(translationX: 24, y: 0)),
            ]))
            let mover = try XCTUnwrap(manager.layers.firstIndex { $0.name == "mover" })
            XCTAssertEqual(manager.layers[mover].transform?.track.keys.map(\.frame), [0, 4, 8], "Premise")

            var before: [[UInt8]] = []
            for frame in 0..<6 { before.append(try compositeBytes(manager, atFrame: frame)) }

            let undoCountBefore = manager.history.undoStack.count
            manager.withStructureUndo(label: .resizeFrame) {
                manager.resizeCelRightEdge(layerIndex: mover, celIndex: 0, newEndFrame: 6)
            }
            XCTAssertEqual(manager.history.undoStack.count, undoCountBefore + 1,
                           "one undo step covers the span and the crop together (\(backend))")
            XCTAssertEqual(manager.layers[mover].transform?.track.keys.map(\.frame), [0, 4, 5],
                           "8 is gone; 4 stays, solidly inside; 5 gains the pose the block showed there (\(backend))")
            guard case .keyframesCropped(let crop)? = manager.notice?.kind else {
                return XCTFail("the artist is told a crop happened (\(backend))")
            }
            XCTAssertEqual(crop.frames, [8], "only the key actually discarded is named, in absolute frames (\(backend))")

            for frame in 0..<6 {
                XCTAssertEqual(try compositeBytes(manager, atFrame: frame), before[frame],
                               "frame \(frame) is exactly what the block showed before the crop (\(backend))")
            }

            manager.undo()
            XCTAssertEqual(manager.layers[mover].transform?.track.keys.map(\.frame), [0, 4, 8],
                           "the span and the key come back together, in the same press (\(backend))")
        }
    }

    /// **The ruling's hard half, one level up from (62)'s own**: lengthening the bar back does *not*
    /// bring a cropped key back — only undo does. Frame 8 holds at whatever the boundary key at 5
    /// preserved, not at the old key's pose, exactly as a track holds past its own last key.
    func testLengtheningAfterACroppedBarDoesNotBringTheKeyBack() throws {
        try onBothBackends { backend in
            let (manager, _) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
            let mover = try XCTUnwrap(manager.layers.firstIndex { $0.name == "mover" })
            let posedAt8 = try compositeBytes(manager, atFrame: 8)

            manager.withStructureUndo(label: .resizeFrame) {
                manager.resizeCelRightEdge(layerIndex: mover, celIndex: 0, newEndFrame: 6)
            }
            XCTAssertNotEqual(try compositeBytes(manager, atFrame: 8), posedAt8, "Premise: shortened, 8 is unposed")
            let heldAt5 = try compositeBytes(manager, atFrame: 5)
            manager.notice = nil   // the banner's timer, which the view owns

            manager.withStructureUndo(label: .resizeFrame) {
                manager.resizeCelRightEdge(layerIndex: mover, celIndex: 0, newEndFrame: 12)
            }
            XCTAssertEqual(manager.layers[mover].transform?.track.keys.map(\.frame), [0, 5],
                           "the key at 8 is gone until undo — lengthening does not bring it back (\(backend))")
            XCTAssertEqual(try compositeBytes(manager, atFrame: 8), heldAt5,
                           "…so frame 8 holds at the pose the crop preserved at 5, not the old key's (\(backend))")
            XCTAssertNil(manager.notice, "lengthening removed nothing, so it says nothing (\(backend))")
        }
    }

    /// **A transform layer's mode scalars crop with its block too, not only its pose track** —
    /// `channelTracks` (TRANSFORM_LAYER.md §3.3's `rotateSpeed` row is the concrete case), while
    /// `opacity` — the one member of that dictionary every layer owns — is untouched, since it is
    /// never gated by a block on any kind (`Layer.channelTracks`'s own doc). This is orthogonal to
    /// `mode`: the crop reads the dictionary, not which mode is selected, so no rotate fixture is
    /// needed to pin it.
    ///
    /// Watched failing with the `id != TargetChannel.opacity.id` filter removed from
    /// `cropTransformLayerKeysToBlocks`: opacity's key at 8 is cropped too, which it must never be.
    func testAModeScalarCropsWithTheBlockAndOpacityDoesNot() throws {
        let (manager, _) = posedVectorLayer(pose(CGAffineTransform.identity))
        let mover = try XCTUnwrap(manager.layers.firstIndex { $0.name == "mover" })
        manager.layers[mover].channelTracks[TargetChannel.rotateSpeed.id] =
            AnimationCurve(keys: [.init(frame: 0, value: 5), .init(frame: 8, value: 15)])
        manager.layers[mover].channelTracks[TargetChannel.opacity.id] =
            AnimationCurve(keys: [.init(frame: 0, value: 1), .init(frame: 8, value: 0.5)])

        manager.withStructureUndo(label: .resizeFrame) {
            manager.resizeCelRightEdge(layerIndex: mover, celIndex: 0, newEndFrame: 6)
        }

        XCTAssertEqual(manager.layers[mover].channelTracks[TargetChannel.rotateSpeed.id]?.keys.map(\.frame), [0, 5],
                       "the speed's key at 8 is gone; 5 — the new last frame — gains the value the curve showed there")
        XCTAssertEqual(manager.layers[mover].channelTracks[TargetChannel.opacity.id]?.keys.map(\.frame), [0, 8],
                       "opacity is untouched — it is not gated by a block at all")
        guard case .keyframesCropped(let crop)? = manager.notice?.kind else {
            return XCTFail("the artist is told")
        }
        XCTAssertEqual(crop.frames, [8], "only the speed's discarded key is named, not opacity's")
    }

    /// **A drag is many `.changed` calls on one open gesture, and each one has to crop from the
    /// gesture's own baseline, not from what the previous call's insertion just left** — a real bug
    /// this file's own review found the hard way: `TransformLayerSpanUITests`' drag went red with no
    /// crop banner at all, and `NSLog` tracing showed why — `frames=[8]`, then `[7]`, `[6]`, `[5]`…,
    /// a *different* key discarded on every tick because `cropTransformLayerKeysToBlocks` read the
    /// **live** track, already carrying the previous tick's boundary insertion, and cropped *that*
    /// again. The very last tick found nothing left to discard, so the committed crop was empty and
    /// the banner never appeared — exactly the shape `resizeCelLeftEdge`'s own comment warns about
    /// for the cel-level crop one door over, reached fresh through this one.
    ///
    /// The fix resets `transform`/`channelTracks`/`keyframeMarks` from `gestureSnapshot`'s baseline
    /// before every recomputation, mirroring the resized cel's own `transformTracks =
    /// baselineCel.transformTracks` three lines up. This pins both halves: a multi-tick drag that
    /// settles past the key reports the key gone (not empty), and a drag that goes past the key and
    /// back within the same gesture reports nothing, because the last tick recomputes from the
    /// untouched baseline rather than from an intermediate crop.
    ///
    /// Watched failing with the three baseline-reset lines removed from `resizeCelRightEdge`: the
    /// multi-tick assertion below reads an empty crop and the key survives at a frame no block covers.
    func testAMultiTickDragCropsFromTheGesturesBaselineNotFromThePreviousTick() throws {
        let (manager, _) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let mover = try XCTUnwrap(manager.layers.firstIndex { $0.name == "mover" })
        XCTAssertEqual(manager.layers[mover].transform?.track.keys.map(\.frame), [0, 8], "Premise")

        // Walk the end down one frame at a time, as `TimelineTrackView`'s pan handler does on every
        // `.changed` — each call recomputing from the same `gestureSnapshot`, exactly as the resized
        // cel's own crop already does.
        manager.beginStructureGesture()
        for end in stride(from: 11, through: 6, by: -1) {
            manager.resizeCelRightEdge(layerIndex: mover, celIndex: 0, newEndFrame: end)
        }
        manager.commitStructureGesture(label: .resizeFrame)

        XCTAssertEqual(manager.layers[mover].transform?.track.keys.map(\.frame), [0, 5],
                       "the key at 8 is gone and 5 gains the boundary pose — not whatever an "
                       + "intermediate tick's own insertion left behind")
        guard case .keyframesCropped(let crop)? = manager.notice?.kind else {
            return XCTFail("the committed crop is announced, not swallowed by the last tick's own reset")
        }
        XCTAssertEqual(crop.frames, [8], "the key actually discarded, from the gesture's one true baseline")

        // And the mirror the fix must not break: past the key and back within *one* gesture (a
        // single bracket the whole way, not a second commit) keeps it, exactly as it always did for
        // a cel's own crop — a fresh document, since the first half above already committed its crop
        // and a *second* gesture on the same track is `testLengtheningAfterACroppedBarDoesNotBringTheKeyBack`'s
        // case, not this one's.
        let (outAndBack, _) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let outAndBackMover = try XCTUnwrap(outAndBack.layers.firstIndex { $0.name == "mover" })
        outAndBack.beginStructureGesture()
        for end in [11, 6, 12] {
            outAndBack.resizeCelRightEdge(layerIndex: outAndBackMover, celIndex: 0, newEndFrame: end)
        }
        outAndBack.commitStructureGesture(label: .resizeFrame)
        XCTAssertEqual(outAndBack.layers[outAndBackMover].transform?.track.keys.map(\.frame), [0, 8],
                       "settled back past the key, in the same gesture — nothing was cropped")
        XCTAssertNil(outAndBack.notice, "nothing to announce")
    }

    /// **A frame past the bar resolves to no pose at all in `layerPoses`, so nothing downstream is
    /// paid for** — no derivation, no cache entry, no canvas-sized render — which is the same safety
    /// property `testADocumentWithNoTransformLayerMintsNoPoses` pins for a document that never had
    /// one. Two blocks with a gap: posed inside each, nothing in the gap, nothing past the end.
    func testAFrameOutsideEveryBlockOfATransformLayerMintsNoPose() {
        let (manager, drawn) = posedVectorLayer(pose(CGAffineTransform(translationX: 20, y: 0)))
        guard let mover = manager.layers.firstIndex(where: { $0.name == "mover" }) else {
            return XCTFail("The fixture's transform layer went missing")
        }
        manager.layers[drawn].cels[0].frameCount = 40
        CanvasFixture.setCelLayout(manager, layerIndex: mover, [(start: 0, length: 4), (start: 10, length: 4)])
        for frame in [0, 3, 10, 13] {
            XCTAssertNotNil(manager.layerPoses(atFrame: frame)[drawn], "posed inside a block, at \(frame)")
        }
        for frame in [4, 7, 9, 14, 30] {
            XCTAssertTrue(manager.layerPoses(atFrame: frame).isEmpty, "nothing minted outside every block, at \(frame)")
        }
    }

    // MARK: - The migration (TRANSFORM_LAYER.md §2 ruling 2)

    /// **A document saved while the transformation layer was a mode of `.value` opens as a
    /// `.transform` layer with its track intact, and draws the same picture at a posed frame on both
    /// backends.** The fixture is a real package written by this build and then edited on disk into
    /// the pre-2026-09-11 spelling — `"kind":"value"` beside the `transform` key, with the fill the
    /// old mode carried as inert storage — because there is no longer any way to *write* that
    /// spelling and a fixture built through the encoder could not express the document being
    /// migrated. Watched failing with `migratingTransformModeValueLayers` returning `kind` unchanged:
    /// the layer reopened as a mid-grey flat colour over the drawing.
    func testADocumentSavedWithATransformModeValueLayerOpensAsATransformLayerAndDrawsTheSame() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform-kind-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let (manager, drawn) = posedVectorLayer(animatedPose(CGAffineTransform(translationX: 24, y: 0)))
        let mover = try XCTUnwrap(manager.layers.firstIndex { $0.name == "mover" })
        let moverID = manager.layers[mover].id
        let url = root.appendingPathComponent("old-spelling.paintproj", isDirectory: true)
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        // Rewrite the manifest into the old spelling. The premise is checked first: this build writes
        // the new kind, so the rewrite is a real change and not a no-op.
        let manifestURL = url.appendingPathComponent("manifest.json")
        var json = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertTrue(json.contains("\"kind\":\"transform\""), "Premise: this build writes the new kind")
        let fillJSON = String(data: try JSONEncoder().encode(ValueFill()), encoding: .utf8)!
        json = json.replacingOccurrences(of: "\"kind\":\"transform\"",
                                         with: "\"kind\":\"value\",\"fill\":\(fillJSON)")
        try json.write(to: manifestURL, atomically: true, encoding: .utf8)

        let reloaded = try XCTUnwrap(ProjectStore.load(from: url), "The old spelling must still open")
        let migrated = try XCTUnwrap(reloaded.layers.first { $0.id == moverID })
        XCTAssertEqual(migrated.kind, .transform, "Read as the kind it is now")
        XCTAssertEqual(migrated.transform, manager.layers[mover].transform, "The pose and its whole track")
        XCTAssertNotNil(migrated.layerTransform, "…and in force, through the accessor the render reads")
        XCTAssertNil(migrated.fill, "The inert fill the old mode carried is dropped — a transform layer has none")
        XCTAssertNil(migrated.valueFill)
        let reloadedDrawn = try XCTUnwrap(reloaded.layers.firstIndex { $0.id == manager.layers[drawn].id })
        XCTAssertNotNil(reloaded.layerPoses(atFrame: 8)[reloadedDrawn], "…posing the leaf beneath at the keyed frame")

        try onBothBackends { backend in
            XCTAssertEqual(try compositeBytes(reloaded, atFrame: 8), try compositeBytes(manager, atFrame: 8),
                           "What is drawn at the posed frame is unchanged by the migration (\(backend))")
        }

        // And saving it again writes the new kind: an older build cannot open this, by design.
        let resaved = root.appendingPathComponent("resaved.paintproj", isDirectory: true)
        let done = expectation(description: "ProjectStore.save completion, second")
        ProjectStore.save(reloaded, to: resaved) { done.fulfill() }
        wait(for: [done], timeout: 30)
        let resavedJSON = try String(contentsOf: resaved.appendingPathComponent("manifest.json"), encoding: .utf8)
        XCTAssertTrue(resavedJSON.contains("\"kind\":\"transform\""), "Encoded as the new kind")
    }

    /// **A value layer that kept its grade and a stale pose stays a value layer, and the pose goes.**
    /// The old precedence parked a pose under a grade for a flip-back that no longer exists; a
    /// document carrying that state reopens as the grade it was showing, with no dead field.
    func testAValueLayerSavedWithAGradeOverAPoseStaysAValueLayerAndDropsThePose() throws {
        let poseJSON = String(data: try JSONEncoder().encode(LayerPose(restingIn: canvasBox)), encoding: .utf8)!
        let effectJSON = String(data: try JSONEncoder().encode(Effect.posterize(Effect.Posterize())), encoding: .utf8)!
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Posterize","opacity":1,"isVisible":true,
         "kind":"value","effect":\(effectJSON),"transform":\(poseJSON),
         "cels":[{"id":"\(UUID().uuidString)","startFrame":0,"frameCount":12,"rasterFileName":"r.png"}]}
        """
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.kind, .value)
        XCTAssertNotNil(decoded.effect, "The grade it was showing")
        XCTAssertNil(decoded.transform, "…and the pose it was not")

        let plain = """
        {"id":"\(UUID().uuidString)","name":"Mover","opacity":1,"isVisible":true,
         "kind":"value","transform":\(poseJSON),"fill":\(String(data: try JSONEncoder().encode(ValueFill()), encoding: .utf8)!),
         "cels":[{"id":"\(UUID().uuidString)","startFrame":0,"frameCount":12,"rasterFileName":"r.png"}]}
        """
        let transformed = try JSONDecoder().decode(LayerManifest.self, from: Data(plain.utf8))
        XCTAssertEqual(transformed.kind, .transform, "The manifest-level migration, on the bare decoder")
        XCTAssertNotNil(transformed.transform)
        XCTAssertNil(transformed.fill)
    }

    // MARK: - Visibility (BUGS.md / TRANSFORM_LAYER.md §0, 2026-09-11)

    /// **A hidden transformation layer poses nothing.** `RenderTree.renderNodes`'s accumulator used
    /// to read `layerTransform?.mapping(atFrame:)` with no `isVisible` test, so hiding the mover with
    /// its eye left the drawing beneath it moved — while a hidden *grade* already grades nothing,
    /// since both compositor backends guard `node.isVisible` before reaching `node.effect`. Pinned on
    /// both backends, as whole-image bytes: frame 8 with the mover hidden must be the *exact* picture
    /// frame 0 already is (the pose's own resting frame, where `mapping(atFrame:)` is nil) — not
    /// merely close, since a leaked pose here is a whole-canvas translation, not a rounding error.
    ///
    /// Watched failing with the `layers[index].isVisible` guard removed from `renderNodes`'s
    /// accumulator: frame 8 hidden differs from frame 0 by the same 24pt the shown frame 8 does.
    func testAHiddenTransformationLayerPosesNothingOnBothBackends() throws {
        let moverPose = animatedPose(CGAffineTransform(translationX: 24, y: 0))
        let (manager, _) = posedVectorLayer(moverPose)
        guard let moverAt = manager.layers.firstIndex(where: { $0.name == "mover" }) else {
            return XCTFail("Setup: the transformation layer must exist to be hidden")
        }

        func bytes(_ frame: Int) throws -> Data {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: frame, includeBackground: true))
            let cgImage = try XCTUnwrap(Compositor.composite(recipe.resolve()))
            return try XCTUnwrap(UIImage(cgImage: cgImage).pngData())
        }

        var backends: [CompositorBackend] = [.coreGraphics]
        if CompositorMetalEngine.shared != nil { backends.append(.metal) }
        let savedBackend = Compositor.backend
        defer { Compositor.backend = savedBackend }

        for backend in backends {
            Compositor.backend = backend
            PixelOps.clearRasterizeCache()

            let resting = try bytes(0)
            let posedVisible = try bytes(8)
            XCTAssertNotEqual(posedVisible, resting,
                              "\(backend): Premise — the mover really does move the ink at frame 8")

            manager.layers[moverAt].isVisible = false
            PixelOps.clearRasterizeCache()
            let posedHidden = try bytes(8)
            XCTAssertEqual(posedHidden, resting,
                           "\(backend): a hidden transformation layer must pose nothing — frame 8 "
                           + "hidden must be the exact un-posed picture")

            manager.layers[moverAt].isVisible = true
            PixelOps.clearRasterizeCache()
            let posedAgain = try bytes(8)
            XCTAssertEqual(posedAgain, posedVisible,
                           "\(backend): showing it again restores the pose exactly")
        }
    }

    // MARK: - Duplicate (BUGS.md, 2026-09-11)

    /// **`duplicateLayer` never carried `transform`.** `Layer(...)`'s memberwise call there named
    /// `effect`, `fill` and every keyframe field beside them, but not this one, so a duplicated
    /// transformation layer decoded with `transform == nil` — `layerEffect`, `layerTransform` and
    /// `valueFill` all read presence to decide the layer's mode, and a dropped `transform` reads as a
    /// flat colour. The BUGS.md filing found this with a test that duplicated a transformation layer
    /// and read `nil` back; this is that test, pinned in place.
    ///
    /// Watched failing with `transform:` removed from `duplicateLayer`'s `Layer(...)`:
    /// `copy.layerTransform` is nil, so the copy is a mid-grey flat-colour layer instead of a
    /// transformation layer, and the ink beneath it stops moving.
    func testDuplicatingATransformationLayerCarriesItsPoseAndItStillPosesInk() throws {
        let moverPose = animatedPose(CGAffineTransform(translationX: 24, y: 0))
        let (manager, drawn) = posedVectorLayer(moverPose)
        guard let moverAt = manager.layers.firstIndex(where: { $0.name == "mover" }) else {
            return XCTFail("Setup: the transformation layer must exist to be duplicated")
        }
        XCTAssertNotNil(manager.layers[moverAt].layerTransform,
                        "Premise: the source really is a transformation layer")
        let wantBounds = try XCTUnwrap(inkBounds(PixelOps.rasterize(
            cel: manager.layers[drawn].cels[0], canvasSize: size,
            derived: manager.derivedCelContent(for: manager.layers[drawn].cels[0], atFrame: 8))),
            "Premise: the mover's frame-8 key really does move the ink")

        manager.duplicateLayer(at: moverAt)
        XCTAssertEqual(manager.layers.count, 3, "Premise: the duplicate landed")
        let copy = manager.layers[moverAt + 1]

        XCTAssertEqual(copy.transform, moverPose, "the pose and its whole track — keys, handles and all")
        XCTAssertNotNil(copy.layerTransform, "still a transformation layer, not a flat colour")
        XCTAssertNil(copy.valueFill, "and not a flat colour by the other accessor either")

        // The duplicate landed *above* the source, in the same container as `drawn` — two stacked
        // transform layers compose (`testTwoStackedTransformLayersComposeInnerFirst`), so leaving the
        // original in force would double the translation and the comparison below would be about
        // composition rather than about the copy. Resting the original isolates what is being asked:
        // does the *copy*, on its own, still pose ink the way the source did.
        manager.layers[moverAt].transform = LayerPose(restingIn: canvasBox)
        let gotBounds = try XCTUnwrap(inkBounds(PixelOps.rasterize(
            cel: manager.layers[drawn].cels[0], canvasSize: size,
            derived: manager.derivedCelContent(for: manager.layers[drawn].cels[0], atFrame: 8))),
            "the copy alone must still derive a posed picture at frame 8")
        XCTAssertEqual(gotBounds.minX, wantBounds.minX, accuracy: 0.5,
                       "the ink moves the same amount under the copy alone as it did under the source")
    }
}
