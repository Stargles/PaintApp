import XCTest
import UIKit

/// The model half of §5.2's sandwich — LAYER_COMPOSITING.md §11 phase 5b.
///
/// `CanvasView.reconcileLayers` hands every layer to Core Animation as a flat sibling, and Core
/// Animation has no per-view Multiply against arbitrary siblings. So a blended layer composites
/// correctly in the thumbnail and shows nothing on the live canvas. §5.2's answer is three views —
/// the composite of everything below the active layer, that layer's own stroke host untouched, and
/// the composite of everything above — and `Array<RenderNode>.split(atLeaf:)` with
/// `CanvasManager.makeSandwichRecipe` is the cut and the snapshot that feed them. Nothing here
/// touches `CanvasView`; the wiring is a separate change against this API.
///
/// **The scope is narrower than §5.2 reads, and the tests are split along that line.**
///
/// - **At rest** the canvas shows one image, `composite(full)`, with every layer host hidden. Exact
///   for every mode and every nesting — `testTheFullRequestIsTheWholeTreeAndNothingElse`.
/// - **Mid-stroke** it shows the three views. `testTheSandwichReassemblesToTheExactComposite…` is the
///   load-bearing claim: wherever nothing above the active layer blends and no ancestor of it
///   buffers, the three add back up to the exact composite byte for byte.
/// - Where they do not, they are **deliberately** approximate for this phase, and the three
///   `testTheSandwichIsNotExactWhen…` cases record how wrong by measuring it. Their job is to fail
///   loudly if a later session comes to believe the mid-stroke path is exact.
///
/// Fixtures follow `CompositorParityLogicTests`: flat opaque rectangles painted as `bakedImage`, so
/// a failure reads as geometry rather than as brush output, and so both sides rasterize identical
/// leaves and the only thing under comparison is the walk.
///
/// `@MainActor` because `makeSandwichRecipe` is — the app target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and this one does not.
@MainActor
final class SandwichLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let yellow = UIColor(red: 1, green: 1, blue: 0, alpha: 1)
    private let cyan = UIColor(red: 0, green: 1, blue: 1, alpha: 1)
    private let grey = UIColor(white: 128.0 / 255, alpha: 1)

    /// **Held to CoreGraphics so that every "exact" in this file goes on meaning what it said.**
    ///
    /// The claims here are about the *walk* — that the `below` half is a prefix of the same one and
    /// so is a copy rather than a requantization, that a folder that carries nothing costs nothing.
    /// Isolating that means holding the backend fixed, exactly as `CompositorParityLogicTests` fixes
    /// it when it wants to vary one thing at a time.
    ///
    /// It was not pinned before because it did not need to be: `Compositor.backend` defaulted to
    /// `.coreGraphics` and no test here moved it. Now that the app ships `.metal`,
    /// `testTheSandwichCostsAtMostAChannelStepWhereAlphaIsFractional`'s exact-0 assertion fails —
    /// **and it fails for a real reason rather than a spurious one**, which is why the answer is to
    /// pin here and measure the shipped configuration in a case of its own
    /// (`testTheShippedBackendCostsTheLowerHalfAtMostOneChannelStep`) rather than to loosen this. The
    /// reassembly draws GPU-composited halves through UIKit and compares them against a GPU-composited
    /// whole, so the step is the documented backend-to-backend tolerance arriving in a new place, not
    /// the sandwich's own arithmetic changing.
    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
    }

    /// **`renderResolution` writes through to `UserDefaults`, and a test that sets it poisons every
    /// test that runs after it — in this process and in the next run on the same simulator.**
    ///
    /// Learned the hard way rather than anticipated: the three render-resolution cases below set it to
    /// `.half` and `.threeQuarter`, and every `CanvasManager()` reads the stored value in its property
    /// initialiser, so eight unrelated cases in this file started compositing at 32² and failing with
    /// "Widths differ: 32 is not 64". Nothing in the failure named the setting.
    ///
    /// Removing the key rather than writing `.full` back, because those are different states: the key
    /// being absent is what a fresh install has, and it is the only one of the two that leaves the
    /// simulator's defaults exactly as this file found them.
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        Compositor.backend = Compositor.defaultBackend
        super.tearDown()
    }

    // MARK: - Fixtures

    /// `count` layers, each an opaque rectangle overlapping its neighbours so that any two of them
    /// swapping changes bytes. Integer-aligned rects, so every pixel is alpha 0 or alpha 255 and a
    /// difference between the two walks can never be blamed on antialiasing.
    private func stack(_ count: Int) -> CanvasManager {
        let palette = [red, green, blue, yellow, cyan]
        let manager = CanvasFixture.manager(layerCount: count)
        for index in 0..<count {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(palette[index % palette.count],
                                                                   rect: CGRect(x: index * 6, y: 8 + index * 5,
                                                                                width: 40, height: 34)))
        }
        return manager
    }

    private struct Battery {
        let name: String
        let manager: CanvasManager
        let active: Int
    }

    /// The tree shapes every invariant below is swept over.
    ///
    /// Built fresh per call because the tests mutate managers, and enumerated by hand rather than
    /// generated because the point is coverage of *shapes* a recursive prune could get wrong: the
    /// leaf being first, last, alone, in the middle of a group, two levels down, or sharing a tree
    /// with a folder that contributes no leaves at all.
    private func battery() -> [Battery] {
        var cases: [Battery] = []

        cases.append(Battery(name: "a flat stack, active in the middle", manager: stack(3), active: 1))
        cases.append(Battery(name: "a flat stack, active at the very bottom", manager: stack(3), active: 0))
        cases.append(Battery(name: "a flat stack, active at the very top", manager: stack(3), active: 2))
        cases.append(Battery(name: "a single-layer document", manager: stack(1), active: 0))

        do {
            let manager = stack(5)
            let folder = manager.addFolder(name: "Middle")
            for index in 1...3 { manager.layers[index].parentFolderID = folder }
            cases.append(Battery(name: "active inside a group with siblings above and below it",
                                 manager: manager, active: 2))
        }
        do {
            let manager = stack(4)
            let outer = manager.addFolder(name: "Outer")
            let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
            manager.layers[0].parentFolderID = outer
            manager.layers[1].parentFolderID = inner
            manager.layers[2].parentFolderID = inner
            cases.append(Battery(name: "active inside a group nested two deep", manager: manager, active: 1))
        }
        do {
            // An empty folder has no span, so it ranks at the top of its container and lands in the
            // `above` half — which is the half that has to keep it rather than prune it away.
            let manager = stack(3)
            manager.addFolder(name: "Empty")
            cases.append(Battery(name: "a tree containing an empty folder", manager: manager, active: 1))
        }
        do {
            let manager = stack(4)
            let folder = manager.addFolder(name: "Above")
            manager.layers[2].parentFolderID = folder
            manager.layers[3].parentFolderID = folder
            cases.append(Battery(name: "a folder whose contents are wholly above the active layer",
                                 manager: manager, active: 1))
        }
        do {
            let manager = stack(4)
            let folder = manager.addFolder(name: "Below")
            manager.layers[0].parentFolderID = folder
            manager.layers[1].parentFolderID = folder
            cases.append(Battery(name: "a folder whose contents are wholly below the active layer",
                                 manager: manager, active: 2))
        }
        return cases
    }

    /// A tree's structure as a string — `L` per leaf, parentheses per node, `|` between input slots.
    /// Enough to tell two shapes apart without caring which layer is which.
    private func shape(_ nodes: [RenderNode]) -> String {
        nodes.map { node in
            switch node.content {
            case .leaf: return "L"
            case .node(_, let inputs): return "(" + inputs.map { shape($0) }.joined(separator: "|") + ")"
            }
        }.joined(separator: " ")
    }

    /// How many levels of node this tree has, top level counting as one.
    private func depth(_ nodes: [RenderNode]) -> Int {
        nodes.reduce(0) { deepest, node in
            switch node.content {
            case .leaf: return max(deepest, 1)
            case .node(_, let inputs): return max(deepest, 1 + (inputs.map { depth($0) }.max() ?? 0))
            }
        }
    }

    // MARK: - Measuring

    /// Largest absolute difference on any channel of any pixel — `CompositorParityLogicTests`' own,
    /// because a delta reported as a number is the only useful thing to say about an approximation.
    private func maxChannelDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard let x = CanvasFixture.rgbaBytes(a), let y = CanvasFixture.rgbaBytes(b), x.count == y.count else {
            return .max
        }
        return x.indices.reduce(0) { max($0, abs(Int(x[$1]) - Int(y[$1]))) }
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    /// **What the live canvas will show mid-stroke, assembled the way the three views assemble it.**
    ///
    /// The `below` composite as the bottom view; the active layer's own source drawn source-over at
    /// the opacity its host carries — `effectiveOpacity(ofLayer:)`, which folds every enclosing
    /// group's opacity in, exactly as `CanvasView` already sets it; then the `above` composite drawn
    /// source-over on top. Deliberately `.normal` for the active layer whatever its blend mode says:
    /// Core Animation has no other option, and that degradation is the phase's accepted cost.
    private func sandwichComposite(_ manager: CanvasManager, active: Int, atFrame frame: Int = 0) -> CGImage? {
        guard let canvasSize = manager.canvasSize,
              let requests = manager.makeSandwichRecipe(atFrame: frame, activeLayerIndex: active)?.resolve(),
              let below = Compositor.composite(requests.below),
              let above = Compositor.composite(requests.above) else { return nil }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        return UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat()).image { _ in
            UIImage(cgImage: below, scale: 1, orientation: .up).draw(in: bounds)
            if manager.isLayerEffectivelyVisible(active), let source = requests.below.sources[active] {
                UIImage(cgImage: source.image, scale: 1, orientation: .up)
                    .draw(in: bounds, blendMode: .normal,
                          alpha: CGFloat(manager.effectiveOpacity(ofLayer: active)))
            }
            UIImage(cgImage: above, scale: 1, orientation: .up).draw(in: bounds)
        }.cgImage
    }

    // MARK: - Pruning invariants

    /// **The invariant the whole cut rests on: the two halves and the active layer put the stack back
    /// together, in order.** A prune that dropped a node, duplicated one, or reordered slots would
    /// render a canvas missing a layer or showing one twice, and this is the cheapest place to catch
    /// it — `assertRenderTreeMatchesFlatOrder` is the same claim about the whole tree.
    func testEveryTreeSplitsIntoTwoHalvesThatPutTheStackBackTogether() {
        for testCase in battery() {
            let tree = testCase.manager.renderTree(atFrame: 0)
            guard let halves = tree.split(atLeaf: testCase.active) else {
                XCTFail("\(testCase.name): the active layer is a leaf of its own tree, so the split must succeed")
                continue
            }
            XCTAssertEqual(halves.below.leafLayerIndices + [testCase.active] + halves.above.leafLayerIndices,
                           tree.leafLayerIndices,
                           "\(testCase.name): below \(halves.below.leafLayerIndices) + active \(testCase.active) + above \(halves.above.leafLayerIndices) is not the tree's own leaf order \(tree.leafLayerIndices)")
            XCTAssertFalse(halves.below.leafLayerIndices.contains(testCase.active),
                           "\(testCase.name): the active layer is drawn by its own view and must not be in the lower texture too")
            XCTAssertFalse(halves.above.leafLayerIndices.contains(testCase.active),
                           "\(testCase.name): nor in the upper one")
        }
    }

    /// The sweep above is only worth its runtime if it is sweeping different *shapes* — nine runs of
    /// a flat stack would pass every assertion in this file while testing one code path.
    func testTheBatteryExercisesGenuinelyDifferentTreeShapes() {
        let shapes = battery().map { shape($0.manager.renderTree(atFrame: 0)) }
        XCTAssertGreaterThanOrEqual(Set(shapes).count, 6,
                                    "Only \(Set(shapes).count) distinct shapes in \(shapes.count) cases: \(shapes)")
        XCTAssertGreaterThanOrEqual(shapes.filter { $0.contains("(") }.count, 5,
                                    "Most of the battery must involve folders — the flat cases cannot exercise a half-group at all. Shapes: \(shapes)")
        XCTAssertGreaterThanOrEqual(battery().map { depth($0.manager.renderTree(atFrame: 0)) }.max() ?? 0, 3,
                                    "One case must nest two folders deep, which is where a half-group has to contain another half-group. Shapes: \(shapes)")
    }

    func testSplittingAtAnIndexThatIsNotALeafOfTheTreeReturnsNil() {
        let manager = stack(3)
        XCTAssertNil(manager.renderTree(atFrame: 0).split(atLeaf: 99), "There is no layer 99")
        XCTAssertNil(manager.renderTree(atFrame: 0).split(atLeaf: -1), "Nor a layer -1")
        XCTAssertNil([RenderNode]().split(atLeaf: 0), "An empty document has no leaf to cut at")
    }

    /// **A half-group is the same group, twice.** Every property is carried verbatim — including the
    /// `id`, which is what lets a caller recognise the two halves as one folder — because the active
    /// layer's own host already has the group's opacity folded into it by `effectiveOpacity`. A half
    /// that forgot the group's properties would disagree with the view sitting between the halves,
    /// which is a worse answer than the approximation carrying them is.
    func testAHalfGroupKeepsTheGroupsIdentityAndEveryPropertyOfIt() {
        let manager = stack(4)
        let folder = manager.addFolder(name: "Group")
        for index in 0..<3 { manager.layers[index].parentFolderID = folder }
        manager.setFolderOpacity(folder, to: 0.4)
        manager.setFolderBlendMode(folder, to: .multiply)
        manager.setFolderIsolated(folder, isIsolated: false)
        manager.toggleFolderVisibility(folder)

        guard let halves = manager.renderTree(atFrame: 0).split(atLeaf: 1),
              let lower = halves.below.first, let upper = halves.above.first else {
            return XCTFail("The group holds layers 0...2, so cutting at 1 must leave a half on each side")
        }
        for (label, half) in [("below", lower), ("above", upper)] {
            XCTAssertEqual(half.id, folder, "The \(label) half is still that folder")
            XCTAssertEqual(half.opacity, 0.4, accuracy: 0.0001, "\(label): opacity verbatim")
            XCTAssertEqual(half.blendMode, .multiply, "\(label): blend mode verbatim")
            XCTAssertFalse(half.isIsolated, "\(label): pass-through verbatim")
            XCTAssertFalse(half.isVisible, "\(label): visibility verbatim — a hidden group hides both halves")
        }
    }

    /// A half pruned to nothing is dropped rather than emitted as a node with an empty slot: it would
    /// buy a canvas-sized buffer (its opacity is not 1) to composite nothing into.
    func testAHalfGroupPrunedToNothingIsDroppedRatherThanEmitted() {
        let manager = stack(2)
        let folder = manager.addFolder(name: "Group")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].parentFolderID = folder
        manager.setFolderOpacity(folder, to: 0.5)

        guard let halves = manager.renderTree(atFrame: 0).split(atLeaf: 0) else {
            return XCTFail("The bottom layer of the group is still a leaf of the tree")
        }
        XCTAssertTrue(halves.below.isEmpty,
                      "Nothing is below the bottom layer of the only group, so the lower half is empty — not a faded group wrapped round an empty slot")
        XCTAssertEqual(halves.above.count, 1, "And the upper half is the group again, holding the one layer left")
        XCTAssertEqual(halves.above.leafLayerIndices, [1])
    }

    /// The other side of that rule, and the reason it is stated as "every slot empty" rather than "no
    /// leaves": the derivation keeps a genuinely empty folder on purpose (§4.1 — its group properties
    /// need somewhere to hang, and a folder that is empty only at this frame must not blink out of
    /// the tree), so a half that still contains one is not a half that was pruned to nothing.
    func testAnEmptyFolderSurvivesIntoWhicheverHalfItRanksIn() {
        let manager = stack(3)
        manager.addFolder(name: "Empty")

        guard let halves = manager.renderTree(atFrame: 0).split(atLeaf: 1) else {
            return XCTFail("Layer 1 is a leaf of this tree")
        }
        XCTAssertEqual(halves.below.count, 1, "Just layer 0")
        XCTAssertEqual(halves.above.count, 2,
                       "Layer 2 and the empty folder, which has no span and therefore ranks at the top of its container")
        XCTAssertEqual(halves.above.leafLayerIndices, [2], "The empty folder still contributes no leaves")
    }

    // MARK: - The composite identity

    /// **The load-bearing test.** Wherever nothing above the active layer blends and no ancestor of it
    /// buffers, the three views add back up to the exact composite: `composite(below)`, the active
    /// leaf drawn source-over at its effective opacity, `composite(above)` drawn source-over.
    ///
    /// Byte for byte rather than to a tolerance, and that is a real claim rather than a hopeful one:
    /// the upper half quantizes to 8-bit premultiplied once more than the direct walk does, which is
    /// the same extra rounding `CoreGraphicsCompositor.draw` declines a buffer to avoid. It comes out
    /// exact here — measured 0 on every one of the nine shapes — because the fixtures are opaque,
    /// every pixel alpha 0 or 255, where source-over through an intermediate is lossless.
    /// `testTheSandwichCostsAtMostAChannelStepWhereAlphaIsFractional` is what happens when that stops
    /// being true, measured rather than assumed.
    func testTheSandwichReassemblesToTheExactCompositeWhereverNothingAboveBlends() {
        var worst = 0
        for testCase in battery() {
            guard let requests = testCase.manager.makeSandwichRecipe(atFrame: 0,
                                                                      activeLayerIndex: testCase.active)?.resolve(),
                  let exact = Compositor.composite(requests.full),
                  let sandwich = sandwichComposite(testCase.manager, active: testCase.active) else {
                XCTFail("\(testCase.name): both sides must composite")
                continue
            }
            let delta = maxChannelDelta(sandwich, exact)
            worst = max(worst, delta)
            XCTAssertEqual(delta, 0,
                           "\(testCase.name): the sandwich differs from the exact composite by \(delta) on some channel")
        }
        print("[sandwich] max channel delta over the exact battery: \(worst)")
    }

    /// **The rest of the identity claim: `full` is the whole tree and nothing else.** At rest the
    /// canvas shows this one image with every layer host hidden, so it has to be what the thumbnail
    /// already composites — including for a document with a blend in it, which is the document the
    /// whole phase exists for.
    func testTheFullRequestIsTheWholeTreeAndNothingElse() {
        let manager = stack(3)
        manager.setLayerBlendMode(layerIndex: 2, to: .multiply)

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              // **`includeBackground: true`, as of EFFECT_BACKDROP.md §6 step 3.** `full` carries the
              // paper now, so the reference has to as well or this compares a graded picture against
              // a transparent one and fails for a reason that has nothing to do with the tree.
              let reference = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(requests.full.tree.leafLayerIndices, manager.renderLeafOrder(atFrame: 0))
        assertPixelsIdentical(Compositor.composite(requests.full), Compositor.composite(reference),
                              "At rest the canvas shows `composite(full)`, which must be the same picture the thumbnail shows")
    }

    // MARK: - `full` does not depend on the active layer (PERFORMANCE.md item 4)

    /// **The property the `full` cache rests on.** Switching layers changes where the tree is cut and
    /// nothing about the picture `full` composites — `makeSandwichRecipe` uses `activeLayerIndex`
    /// in exactly one place, the `split(atLeaf:)` that makes `below` and `above`. Until 2026-08-20
    /// every layer tap therefore recomposited, at full canvas size, an image byte-identical to the
    /// one already on screen.
    ///
    /// Asserted over every active index and over a document with a blend in it, because a blend is
    /// what makes the composite non-trivial — a flat stack would agree for the uninteresting reason
    /// that everything is source-over.
    func testFullIsTheSamePictureWhicheverLayerIsActive() {
        let manager = stack(4)
        manager.setLayerBlendMode(layerIndex: 2, to: .multiply)

        guard let reference = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0)?.resolve(),
              let referenceImage = Compositor.composite(reference.full) else {
            return XCTFail("Fixture needs a canvas size")
        }
        for active in 1..<manager.layers.count {
            guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: active)?.resolve() else {
                return XCTFail("Every leaf should cut")
            }
            XCTAssertEqual(requests.full.tree, reference.full.tree,
                           "active \(active): `full` is the whole tree, uncut, whichever leaf is active")
            assertPixelsIdentical(Compositor.composite(requests.full), referenceImage,
                                  "active \(active): the picture `full` composites does not depend on the active layer")
        }
    }

    /// …and the key that decides whether to reuse it moves for everything **except** the active
    /// layer. Both halves are needed: the property above makes reuse *sound*, this makes it *happen
    /// exactly when it should*. A key that failed to move on a content change would serve pre-edit
    /// pixels, which is the failure mode `LayerContentVersion` was written to prevent.
    func testTheFullKeyIgnoresTheActiveLayerAndNothingElse() {
        let manager = stack(3)
        func key(frame: Int = 0, resolution: RenderResolution = .full) -> SandwichFullKey {
            SandwichFullKey(tree: manager.renderTree(atFrame: frame),
                            frame: frame,
                            // `contentVersion(ofLayer:atFrame:)` rather than a copy of its field list:
                            // this stands in for `makeSandwichKey`, and a stand-in that builds the
                            // value its own way is not testing the builder the app uses — which is
                            // how the derivation came to be missing from that key in the first place.
                            contents: manager.layers.indices.map { manager.contentVersion(ofLayer: $0, atFrame: frame) },
                            renderResolution: resolution,
                            canvasBackgroundColor: manager.canvasBackgroundColor,
                            isCanvasBackgroundVisible: manager.isCanvasBackgroundVisible)
        }

        let base = key()
        // The active layer is not an input — that is the whole point, and it is expressed by the type
        // having no field for it rather than by a test that sets one and hopes.
        manager.currentLayerIndex = 2
        XCTAssertEqual(base, key(), "Switching the active layer leaves `full`'s key exactly where it was")

        XCTAssertNotEqual(base, key(frame: 1), "A different frame is a different picture")
        XCTAssertNotEqual(base, key(resolution: .half), "A reduced composite is a different size of picture")

        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
        XCTAssertNotEqual(base, key(), "A blend mode change moves the tree, and the tree is in the key")

        let treeChanged = key()
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(cyan, rect: CGRect(x: 2, y: 2, width: 10, height: 10)))
        XCTAssertNotEqual(treeChanged, key(), "New pixels on a layer move its content version")

        // **The paper, as of EFFECT_BACKDROP.md §6 step 3.** `full` carries the canvas colour now, so
        // recolouring the canvas is a new picture and has to be a new key. Without this the artist
        // changes the paper and the canvas keeps showing the old one until something unrelated moves
        // the key — the same "a control that visibly does nothing" failure `renderResolution` is in
        // the key to prevent.
        let painted = key()
        manager.canvasBackgroundColor = .yellow
        XCTAssertNotEqual(painted, key(), "A different paper is a different picture")

        let yellow = key()
        manager.isCanvasBackgroundVisible = false
        XCTAssertNotEqual(yellow, key(),
                          "…and turning the paper off is not the same as any colour it could have been: "
                          + "it is the difference between an effect grading a backdrop and grading nothing")
    }

    /// The saving, counted. `CompositeProbe` records what the compositor was actually asked to do, so
    /// this is an integer about the calls rather than a millisecond about the machine — which matters
    /// on a Mac where CLAUDE.md records contention making suites return wrong answers.
    ///
    /// Replays the two composites a layer-switch rebuild runs under the reuse rule, against the three
    /// it ran before. It does not drive `CanvasView.Coordinator`, which is a `UIViewRepresentable`
    /// coordinator and not reachable headlessly — what it pins is the arithmetic that coordinator
    /// now does, over the same requests, on the same document.
    func testALayerSwitchCompositesTwiceRatherThanThreeTimes() {
        let manager = stack(4)
        manager.setLayerBlendMode(layerIndex: 2, to: .multiply)
        guard let before = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              let after = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 2)?.resolve() else {
            return XCTFail("Fixture needs a canvas size")
        }

        CompositeProbe.begin()
        _ = Compositor.composite(before.full)
        _ = Compositor.composite(before.below)
        _ = Compositor.composite(before.above)
        XCTAssertEqual(CompositeProbe.end().count, 3, "Control: a first rebuild composites all three")

        // The layer tap. `SandwichFullKey` has not moved, so `full` is served from what is already
        // on screen and only the two halves are recomposited.
        CompositeProbe.begin()
        _ = Compositor.composite(after.below)
        _ = Compositor.composite(after.above)
        let sizes = CompositeProbe.end()
        XCTAssertEqual(sizes.count, 2, "A layer switch costs two composites, where it used to cost three")
        XCTAssertEqual(Set(sizes), [after.full.canvasSize],
                       "…and the two it does run are the same size as the one it skipped, so the saving is a whole composite")
    }

    /// **The one measured cost of the extra intermediate, and it is smaller and lopsided in a way
    /// worth writing down.**
    ///
    /// The `above` half quantizes to 8-bit premultiplied once more than the direct walk does — the
    /// same extra rounding `CoreGraphicsCompositor.draw` declines a buffer to avoid. Measured on this
    /// simulator, at 64²: **0 for one semi-transparent layer above, 1 once four of them stack**, and
    /// 1 again when they stack inside a folder. One layer costs nothing because applying alpha to a
    /// source and then compositing it *is* the direct operation, quantized at the same single point;
    /// it takes a second fractional draw landing on the first for the intermediate to appear.
    ///
    /// **The `below` half stays exact whatever the alphas are**, and that is structural rather than
    /// lucky: it is a prefix of the same walk, and drawing its result into a context that is still
    /// fully transparent is a copy. So the wiring session can treat the lower texture as exact and
    /// only the upper one as approximate.
    func testTheSandwichCostsAtMostAChannelStepWhereAlphaIsFractional() {
        let manager = stack(5)
        for (offset, opacity) in [0.37, 0.53, 0.41, 0.29].enumerated() {
            manager.layers[offset + 1].opacity = opacity
        }

        guard let low = makeSandwichAndExact(manager, active: 4),
              let high = makeSandwichAndExact(manager, active: 1) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(maxChannelDelta(low.sandwich, low.exact), 0,
                       "With the active layer on top there is nothing in the upper half, and the lower half is a prefix of the same walk — a copy, not a requantization")
        let above = maxChannelDelta(high.sandwich, high.exact)
        print("[sandwich] max channel delta with four semi-transparent layers above: \(above)")
        XCTAssertLessThanOrEqual(above, 1,
                                 "One step is what an extra 8-bit quantization can produce; \(above) would be a different picture rather than a rounding difference")
    }

    /// The two images every comparison in this file is between: what the three views will show, and
    /// what the compositor says the frame actually is.
    private func makeSandwichAndExact(_ manager: CanvasManager, active: Int,
                                      atFrame frame: Int = 0) -> (sandwich: CGImage, exact: CGImage)? {
        guard let requests = manager.makeSandwichRecipe(atFrame: frame, activeLayerIndex: active)?.resolve(),
              let exact = Compositor.composite(requests.full),
              let sandwich = sandwichComposite(manager, active: active, atFrame: frame) else { return nil }
        return (sandwich, exact)
    }

    // MARK: - The approximation, pinned honestly

    /// **The mid-stroke path is not exact, and this test's job is to fail loudly if anyone comes to
    /// believe otherwise.**
    ///
    /// A layer above the active one is composited onto transparency and then drawn source-over, so it
    /// has no backdrop to blend against and degrades to normal for the duration of the dab. Here that
    /// is the whole difference between multiply-onto-grey and plain red: the exact composite is
    /// (128, 0, 0) and the sandwich shows (255, 0, 0), a delta of 127 on the red channel. Accepted
    /// and deliberate for phase 5b — lift snaps the canvas back to `full`, which is exact.
    func testTheSandwichIsNotExactWhenSomethingAboveTheActiveLayerBlends() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(grey, rect: CGRect(origin: .zero,
                                                                                  size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0)?.resolve(),
              let exact = Compositor.composite(requests.full),
              let sandwich = sandwichComposite(manager, active: 0) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(pixel(exact, 16, 16), [128, 0, 0, 255], "Exact: red multiplies the grey floor")
        XCTAssertEqual(pixel(sandwich, 16, 16), [255, 0, 0, 255],
                       "Mid-stroke: the upper texture multiplied against transparency, which is itself, and then drew source-over")

        let delta = maxChannelDelta(sandwich, exact)
        print("[sandwich] max channel delta, a blending layer above the active one: \(delta)")
        XCTAssertGreaterThan(delta, 0,
                             "If this ever reaches 0 the mid-stroke path became exact and the degradation this file documents is stale — update §5.2 rather than deleting the test")
        XCTAssertEqual(delta, 127, "Measured, and stated so it also fails if the approximation gets worse")
    }

    /// The other accepted degradation: **the active layer's own blend mode goes to normal while the
    /// dab is live**, because Core Animation is what draws that view and it can only source-over.
    func testTheSandwichIsNotExactWhenTheActiveLayerItselfBlends() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(grey, rect: CGRect(origin: .zero,
                                                                                  size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              let exact = Compositor.composite(requests.full),
              let sandwich = sandwichComposite(manager, active: 1) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(pixel(exact, 16, 16), [128, 0, 0, 255], "Exact: the layer multiplies")
        XCTAssertEqual(pixel(sandwich, 16, 16), [255, 0, 0, 255], "Mid-stroke: its own host draws it source-over")

        let delta = maxChannelDelta(sandwich, exact)
        print("[sandwich] max channel delta, the active layer itself blends: \(delta)")
        XCTAssertGreaterThan(delta, 0, "The active layer's mode is applied on lift, not during the dab")
        XCTAssertEqual(delta, 127, "The same 127 the case above measures, and for the same reason: pure red instead of red multiplied into mid-grey")
    }

    /// **§5.2's "live stroke inside a blended group", which is the case the half-group approximation
    /// is named for.** Both halves keep the group's opacity, so a faded group fades twice — once per
    /// half — instead of once over the composite the halves would have made together, and the active
    /// layer's host carries the same fade a third time via `effectiveOpacity`.
    ///
    /// §10 decision 5 settles the real fix (recomposite the active node's subtree per frame). This
    /// test is the record that it has not been built, stated as the pixels it costs: two overlapping
    /// opaque squares in a group at 0.5 composite to RGBA (0, 128, 0, 128) — green covers red inside
    /// the group, and the finished thing fades once. The sandwich shows (64, 128, 0, 192): the red is
    /// no longer covered, because it is drawn by its own view before the upper half lands on it, and
    /// two half-alpha draws accumulate past one. **Measured max channel delta 64.**
    func testTheSandwichIsNotExactWhenTheActiveLayerIsInsideAFadedGroup() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let square = CGRect(x: 0, y: 0, width: 40, height: 40)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(red, rect: square))
        CanvasFixture.setBakedContent(manager, layerIndex: 1, CanvasFixture.solidImage(green, rect: square))
        let folder = manager.addFolder(name: "Faded")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].parentFolderID = folder
        manager.setFolderOpacity(folder, to: 0.5)
        // **The paper is switched off for this fixture alone, deliberately.** EFFECT_BACKDROP.md §6
        // step 3 put the canvas colour into `full` and `below`, and every other case in this file is
        // unaffected because its floor layer is already opaque. This one has no floor — two small
        // squares on nothing — so an opaque white sheet under them shifts every byte the test
        // measures without changing what it measures, which is the half-group approximation. The
        // measured 64 is a claim about the sandwich's arithmetic, not about what is behind it.
        manager.isCanvasBackgroundVisible = false

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0)?.resolve(),
              let exact = Compositor.composite(requests.full),
              let sandwich = sandwichComposite(manager, active: 0) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(pixel(exact, 20, 20), [0, 128, 0, 128],
                       "Exact: green covers red inside the group, and the finished composite fades once")
        XCTAssertEqual(pixel(sandwich, 20, 20), [64, 128, 0, 192],
                       "Mid-stroke: red is drawn by its own view at the folded opacity, so it is no longer covered, and the two half-alpha draws accumulate")

        let delta = maxChannelDelta(sandwich, exact)
        print("[sandwich] max channel delta, the active layer inside a faded group: \(delta)")
        XCTAssertEqual(delta, 64,
                       "A buffering ancestor is where the half-group approximation shows, and §5.2 says so — this is the measurement behind that sentence")
    }

    // MARK: - `needsCompositorOnCanvas`, which is the risk containment

    /// The documents that existed before phase 5a stay on today's code path, exactly. That is the
    /// whole of the phase's risk containment: if this ever answers true for an all-normal document,
    /// every project ever made starts rendering through a path it has never rendered through.
    func testAnAllNormalDocumentDoesNotNeedTheCompositorOnCanvas() {
        XCTAssertFalse(stack(3).renderTree(atFrame: 0).needsCompositorOnCanvas, "A flat all-normal stack is Core Animation's own case")

        let nested = stack(4)
        let outer = nested.addFolder(name: "Outer")
        let inner = nested.addFolder(name: "Inner", parentFolderID: outer)
        nested.layers[0].parentFolderID = outer
        nested.layers[1].parentFolderID = inner
        nested.layers[2].parentFolderID = inner
        XCTAssertFalse(nested.renderTree(atFrame: 0).needsCompositorOnCanvas,
                       "Untouched folders are transparent parentheses — opacity 1, normal, isolated over nothing that blends")
    }

    /// **The clause that is not covered by `needsOwnBuffer`, and the reason the predicate has two.**
    /// A leaf blends as it is drawn rather than as an assembled composite, so it never wants a buffer
    /// — and a blending leaf in a flat stack is precisely the document phase 5b exists for.
    func testABlendingLeafNeedsTheCompositorEvenThoughItNeedsNoBuffer() {
        let manager = stack(2)
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        XCTAssertFalse(manager.renderTree(atFrame: 0)[1].needsOwnBuffer, "A leaf's mode is an argument to one draw call")
        XCTAssertTrue(manager.renderTree(atFrame: 0).needsCompositorOnCanvas,
                      "A buffers-only predicate would answer false here and leave Multiply showing nothing on canvas again")
    }

    /// And it has to find one at any depth: the recursion is what a "does anything in this document
    /// blend" question actually is.
    func testABlendingLeafBuriedInsideFoldersIsStillFound() {
        let manager = stack(3)
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner
        manager.layers[2].parentFolderID = inner
        manager.setLayerBlendMode(layerIndex: 2, to: .screen)

        XCTAssertTrue(manager.renderTree(atFrame: 0).needsCompositorOnCanvas, "Two levels down is still in the document")
    }

    func testABlendingGroupNeedsTheCompositor() {
        let manager = stack(2)
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.setFolderBlendMode(folder, to: .overlay)

        XCTAssertTrue(manager.renderTree(atFrame: 0).needsCompositorOnCanvas,
                      "Core Animation cannot Overlay a group's finished composite against its siblings")
    }

    /// A faded group is the one case that was already wrong before blend modes existed —
    /// `effectiveOpacity(ofLayer:)` folds the fade into each child, which differs from fading the
    /// group's composite wherever children overlap. It reaches the compositor now through
    /// `needsOwnBuffer`'s first clause, without the predicate needing to know about opacity at all.
    func testAGroupAtAnyOpacityOtherThanOneNeedsTheCompositor() {
        let manager = stack(2)
        let folder = manager.addFolder(name: "Group")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].parentFolderID = folder

        XCTAssertFalse(manager.renderTree(atFrame: 0).needsCompositorOnCanvas, "At opacity 1 it is still a parenthesis")
        manager.setFolderOpacity(folder, to: 0.99)
        XCTAssertTrue(manager.renderTree(atFrame: 0).needsCompositorOnCanvas, "Not 1 is the test, not \"visibly faded\"")
    }

    /// The third clause of `needsOwnBuffer`, reached through the group rather than through the leaf.
    /// Both reasons fire here at once — the descendant blends, so the recursion would answer true on
    /// its own — and that is the point rather than a weakness in the fixture: an isolated group over a
    /// blend is a document Core Animation cannot draw for two independent reasons, and the predicate
    /// only has to notice one of them.
    func testAnIsolatedGroupOverABlendingDescendantNeedsTheCompositor() {
        let manager = stack(2)
        let folder = manager.addFolder(name: "Isolated")
        manager.layers[1].parentFolderID = folder
        manager.setFolderIsolated(folder, isIsolated: true)
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        XCTAssertTrue(manager.renderTree(atFrame: 0)[1].needsOwnBuffer,
                      "Isolated over something that blends is the clause — the group's children start from transparency, which differs from starting from the backdrop only because one of them blends")
        XCTAssertTrue(manager.renderTree(atFrame: 0).needsCompositorOnCanvas)
    }

    // MARK: - The split through a compositor node (§4.3, phase 8)
    //
    // **`split(atLeaf:)` has looped `inputs.enumerated()` since phase 1 and has never once been run
    // against a slot fold that is not `.stack`.** It reasons that "the slots before the one holding
    // the leaf are wholly below it and the ones after are wholly above", which is true of the leaf
    // *order* for any op — and is a claim about the composite only while the fold is source-over into
    // one shared accumulator. A `.mix` fold is not that. These cases run it.
    //
    // The trees are stated outright, because the derivation cannot build a `.mix` yet (the model
    // change is separate work) and because `split` operates on `[RenderNode]` rather than on a
    // manager, so nothing is being faked. Every node is left at opacity 1 and mode `.normal` so that
    // the half-group approximation `testTheSandwichIsNotExactWhenTheActiveLayerIsInsideAFadedGroup`
    // already measures cannot confound what the fold itself costs.

    /// Slot 0 is a full-canvas floor with two squares over it; slot 1 is a full-canvas sheet with a
    /// square over it. Opaque throughout, so `.normal` has no rounding to hide behind, and arranged so
    /// that the part of a slot *below* the active leaf still shows through where the part above it
    /// does not cover — which is the only place a fold applied to the wrong operand is visible.
    private func mixFixture() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 4)
        let whole = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(red, rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 1, CanvasFixture.solidImage(grey, rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 30, height: 30)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 16, y: 16, width: 30, height: 30)))
        return manager
    }

    private func leafNode(_ index: Int, of manager: CanvasManager) -> RenderNode {
        RenderNode(id: manager.layers[index].id, content: .leaf(layerIndex: index),
                   opacity: 1, isVisible: true, blendMode: .normal, isIsolated: false)
    }

    private func mixNode(_ slots: [[RenderNode]], _ mode: BlendMode) -> RenderNode {
        RenderNode(id: UUID(), content: .node(op: .mix(mode), inputs: slots),
                   opacity: 1, isVisible: true, blendMode: .normal, isIsolated: true)
    }

    private func request(_ manager: CanvasManager, tree: [RenderNode]) -> RenderRequest? {
        guard let base = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else { return nil }
        return RenderRequest(tree: tree, sources: base.sources, contentVersions: base.contentVersions,
                             maskStacks: base.maskStacks, frame: base.frame, canvasSize: base.canvasSize,
                             background: nil, quality: base.quality)
    }

    /// `sandwichComposite`'s three views, over halves cut from a stated tree rather than a derived
    /// one. Every node is at opacity 1, so the active layer's host draws at alpha 1 — which is what
    /// `effectiveOpacity(ofLayer:)` would return for this shape anyway.
    private func mixSandwich(_ manager: CanvasManager, tree: [RenderNode],
                             active: Int) -> (sandwich: CGImage, exact: CGImage)? {
        guard let canvasSize = manager.canvasSize,
              let halves = tree.split(atLeaf: active),
              let whole = request(manager, tree: tree),
              let exact = Compositor.composite(whole),
              let below = request(manager, tree: halves.below).flatMap(Compositor.composite),
              let above = request(manager, tree: halves.above).flatMap(Compositor.composite) else { return nil }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        guard let sandwich = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
            .image(actions: { _ in
                UIImage(cgImage: below, scale: 1, orientation: .up).draw(in: bounds)
                if let source = whole.sources[active] {
                    UIImage(cgImage: source.image, scale: 1, orientation: .up).draw(in: bounds)
                }
                UIImage(cgImage: above, scale: 1, orientation: .up).draw(in: bounds)
            }).cgImage else { return nil }
        return (sandwich, exact)
    }

    /// A leaf inside slot 0, and a leaf inside slot 1 — the two cases, both with content on each side
    /// of the leaf within its own slot.
    private func mixShapes(_ manager: CanvasManager, _ mode: BlendMode) -> [(name: String, tree: [RenderNode], active: Int)] {
        func leaf(_ index: Int) -> RenderNode { leafNode(index, of: manager) }
        return [
            // Slot 0 holds the lower layers and slot 1 the upper ones, which is the shape §4.3's
            // contiguous slot spans will actually produce — the cut is not being handed an ordering
            // the model could never build.
            (name: "the active leaf in slot 0",
             tree: [mixNode([[leaf(0), leaf(1), leaf(2)], [leaf(3)]], mode)], active: 1),
            (name: "the active leaf in slot 1",
             tree: [mixNode([[leaf(0)], [leaf(1), leaf(2), leaf(3)]], mode)], active: 2),
        ]
    }

    /// The structural half of the claim, and it holds: the cut reassembles the leaf order through a
    /// `.mix` exactly as it does through a `.stack`, in either slot. That much is arity-agnostic —
    /// `split` reasons about *order*, and slot order is slot order whatever the op does with the
    /// finished slots.
    func testTheSplitThroughAMixReassemblesTheStackFromEitherSlot() {
        let manager = mixFixture()
        for shape in mixShapes(manager, .multiply) {
            guard let halves = shape.tree.split(atLeaf: shape.active) else {
                XCTFail("\(shape.name): the active layer is a leaf of this tree, so the split must succeed")
                continue
            }
            XCTAssertEqual(halves.below.leafLayerIndices + [shape.active] + halves.above.leafLayerIndices,
                           shape.tree.leafLayerIndices,
                           "\(shape.name): below \(halves.below.leafLayerIndices) + active \(shape.active) + above \(halves.above.leafLayerIndices) is not the tree's own leaf order \(shape.tree.leafLayerIndices)")
        }
    }

    /// **A half of a two-slot Mix is a Mix with one slot, which its own arity says cannot exist.**
    ///
    /// `half(inputs:)` carries the op verbatim — correctly, since forgetting it would be worse — so
    /// cutting a `.fixed(2)` node produces a node whose slot count disagrees with `CompositorOp.arity`
    /// on one side of the cut. Both backends fold a one-slot Mix to that slot and nothing else
    /// (`CompositorParityLogicTests.testAMixWithOneSlotIsThatSlotAssembled`), so this is not a hole in
    /// the render, but it *is* a shape no validator downstream may assume away: a sandwich half is not
    /// a document, and arity is a rule about documents.
    func testAHalfOfATwoSlotMixKeepsTheOpAndLosesASlot() {
        let manager = mixFixture()
        let tree = [mixNode([[leafNode(0, of: manager), leafNode(2, of: manager)],
                             [leafNode(1, of: manager), leafNode(3, of: manager)]], .multiply)]
        guard let halves = tree.split(atLeaf: 2),
              case .node(let belowOp, let belowSlots)? = halves.below.first?.content,
              case .node(let aboveOp, let aboveSlots)? = halves.above.first?.content else {
            return XCTFail("Cutting inside slot 0 must leave a half on each side")
        }
        XCTAssertEqual(belowOp, .mix(.multiply), "The op is carried verbatim, the same as every other property")
        XCTAssertEqual(aboveOp, .mix(.multiply))
        XCTAssertEqual(belowSlots.count, 1, "Everything below the leaf is the part of slot 0 beneath it, and nothing else")
        XCTAssertEqual(aboveSlots.count, 2, "…while the upper half keeps the rest of slot 0 and the whole of slot 1")
        XCTAssertEqual(CompositorOp.mix(.multiply).arity, .fixed(2),
                       "Which the op's own arity says is not a shape a node may have — a half is not a document")
    }

    /// **The exact case, and it is exact: a `.mix(.normal)` splits and reassembles byte for byte in
    /// either slot.** Source-over is associative, so folding an isolated slot 1 onto an isolated slot
    /// 0 and then drawing the result is the same picture as drawing the pieces in order — which is
    /// what makes the cut legitimate at all for the op the derivation will produce most.
    func testTheSandwichThroughANormalMixIsExactInEitherSlot() {
        let manager = mixFixture()
        for shape in mixShapes(manager, .normal) {
            guard let (sandwich, exact) = mixSandwich(manager, tree: shape.tree, active: shape.active) else {
                XCTFail("\(shape.name): both sides must composite")
                continue
            }
            XCTAssertEqual(maxChannelDelta(sandwich, exact), 0,
                           "\(shape.name): a normal fold splits cleanly, so the halves and the live layer must add back up exactly")
        }
    }

    /// **The finding, pinned rather than papered over: a blending Mix does *not* split cleanly, and
    /// the arithmetic says why.**
    ///
    /// The fold applies its mode once, between two finished slots. A cut inside a slot breaks that
    /// slot into two pieces on opposite sides of the live layer, and neither half can fold against the
    /// operand the whole document folds against:
    ///
    /// - **Active leaf in slot 0.** Exact is `(b ⊕ leaf ⊕ a) ⊕ᵐᵒᵈᵉ slot1`. The upper half is
    ///   `Mix(a, slot1, mode)`, so slot 1 blends against `a` alone — `b` and the live layer are below
    ///   it in the sandwich and cannot participate.
    /// - **Active leaf in slot 1.** Exact is `slot0 ⊕ᵐᵒᵈᵉ (b ⊕ leaf ⊕ a)`. The lower half folds only
    ///   `b` onto slot 0; the live layer and `a` then land source-over on top, so the mode never sees
    ///   them at all.
    ///
    /// **This is the same degradation §5.2 already accepts, one level in** — it is
    /// `testTheSandwichIsNotExactWhenSomethingAboveTheActiveLayerBlends` reached through a slot
    /// instead of through a sibling, and it snaps correct on lift for the same reason: lift shows
    /// `full`, which is exact. It is recorded here as a measurement so that a later session cannot
    /// come to believe a node splits cleanly when only `.normal` does.
    ///
    /// **Measured max channel delta: 127 with the leaf in slot 0, 255 with it in slot 1.** Both are
    /// stated exactly rather than as "greater than zero", so the test also fails if the approximation
    /// gets *worse* — the same discipline the three existing `testTheSandwichIsNotExactWhen…` cases
    /// use. 127 is the grey floor at half brightness against the blue square it should have been
    /// multiplied into; 255 is the green square arriving at full strength where the exact composite
    /// multiplies it to black.
    func testTheSandwichThroughABlendingMixIsNotExactAndTheDeltaIsMeasured() {
        let expected = ["the active leaf in slot 0": 127, "the active leaf in slot 1": 255]
        let manager = mixFixture()
        for shape in mixShapes(manager, .multiply) {
            guard let (sandwich, exact) = mixSandwich(manager, tree: shape.tree, active: shape.active) else {
                XCTFail("\(shape.name): both sides must composite")
                continue
            }
            let delta = maxChannelDelta(sandwich, exact)
            print("[sandwich] max channel delta through a multiply Mix, \(shape.name): \(delta)")
            XCTAssertGreaterThan(delta, 0,
                                 "\(shape.name): if this ever reaches 0 the fold started splitting cleanly and this file's reasoning is stale — update §5.2 rather than deleting the test")
            XCTAssertEqual(delta, expected[shape.name],
                           "\(shape.name): measured, and stated so it also fails if the approximation gets worse")
        }
    }

    // MARK: - What a node does to the canvas gate

    /// **A Mix engages the compositor on canvas, and it has to engage on the *op* rather than on the
    /// node's own mode.** A `Mix(A, B, .multiply)` at `blendMode == .normal`, opacity 1, unmasked is
    /// an all-normal document by every test that predates phase 8 — and Core Animation cannot draw it,
    /// because the multiply is between two subtrees rather than between a view and its backdrop.
    ///
    /// Left un-taught, `LayerUITests.testAnAllNormalDocumentNeverEngagesTheSandwich` would have stayed
    /// green while a Mix document rendered correctly in the thumbnail and wrongly on the canvas the
    /// artist is looking at.
    func testAMixNodeAlwaysBuffersAndAlwaysEngagesTheCompositorOnCanvas() {
        let manager = mixFixture()
        let slots = [[leafNode(0, of: manager)], [leafNode(1, of: manager)]]

        for mode in [BlendMode.normal, .multiply] {
            let node = mixNode(slots, mode)
            XCTAssertTrue(node.needsOwnBuffer,
                          "\(mode.displayName): a fold happens between slots composited against transparency, so there is nowhere for it to happen but a buffer")
            XCTAssertTrue([node].needsCompositorOnCanvas,
                          "\(mode.displayName): Core Animation has no way to combine two subtrees, whatever the node's own mode says")
        }
        XCTAssertTrue(mixNode(slots, .multiply).opIsBlending, "The fold is the blend")
        XCTAssertFalse(mixNode(slots, .normal).opIsBlending, "A normal fold is source-over and blends nothing")
    }

    /// The other side of that, and the containment the whole phase rests on: **`.stack` is untouched.**
    /// A folder is still `.node(op: .stack, …)` and still a transparent parenthesis at its defaults —
    /// no buffer, no canvas path, not one byte different from before nodes existed.
    func testAStackNodeIsUnaffectedByTheOpsSecondCase() {
        let manager = stack(2)
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder

        guard case .node(let op, _)? = manager.renderTree(atFrame: 0).first(where: { $0.id == folder })?.content else {
            return XCTFail("The derivation still builds a folder as a node")
        }
        XCTAssertEqual(op, .stack, "Phase 8 adds a case to the op; it does not change what a folder derives to")
        XCTAssertEqual(op.arity, .variadic(min: 1), "Stacking N composites bottom-to-top is not an arity-1 idea")
        XCTAssertNil(op.slotCount, "A variadic op declares no slot count")
        XCTAssertFalse(op.needsOwnBuffer, "Which is what keeps an untouched folder on the direct path")
        XCTAssertFalse(manager.renderTree(atFrame: 0).needsCompositorOnCanvas)
    }

    // MARK: - The requests

    /// **One snapshot, three requests, and the sharing is the point.** `sources` is indexed by
    /// `layers` index rather than by position in a tree, so the same array answers all three walks —
    /// and the snapshot is the expensive half (§11: 276 ms against an 84 ms composite), so building
    /// it three times would cost more than the compositing does.
    func testTheThreeRequestsShareOneSnapshot() {
        let manager = stack(3)
        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve() else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(requests.full.sources.count, manager.layers.count, "Parallel to `layers`, as the type says")
        for index in manager.layers.indices {
            XCTAssertTrue(requests.full.sources[index]?.image === requests.below.sources[index]?.image,
                          "Leaf \(index) was rasterized twice for `below`")
            XCTAssertTrue(requests.full.sources[index]?.image === requests.above.sources[index]?.image,
                          "Leaf \(index) was rasterized twice for `above`")
        }
    }

    /// **Two of the three carry the paper, and `above` does not** — EFFECT_BACKDROP.md §6 step 3.
    ///
    /// This test asserted the opposite until 2026-08-27, on the grounds that "the live canvas paints
    /// its own `paperView` behind the whole stack, so a background in any of the three would be
    /// either a second one or an opaque sheet over the layers beneath it". Half of that was true and
    /// stayed true — `above` is drawn over everything beneath it, so a background in it is still an
    /// opaque sheet over the picture. The other half was BUGS.md's *"Every effect and blend mode is
    /// masked to the layer's own ink"*: a view behind the composite is a thing no compositor pass can
    /// read, so every adjustment layer graded a transparent sheet and every blend mode blended
    /// against nothing. `paperView` is what stopped painting instead.
    func testTheLowerTwoRequestsCarryThePaperAndTheUpperOneDoesNot() {
        let manager = stack(2)
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0)?.resolve() else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNotNil(requests.full.background, "`full` is what the canvas shows at rest")
        XCTAssertNotNil(requests.below.background, "`below` is the bottom of the mid-stroke sandwich")
        XCTAssertNil(requests.above.background,
                     "`above` composites onto transparency by design — see this test's own history")

        // The other switch, and it is not the same as painting white: an invisible canvas is what a
        // caller asking for a transparent-backed composite gets, and an effect over it grades nothing.
        manager.isCanvasBackgroundVisible = false
        guard let hidden = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0)?.resolve() else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNil(hidden.full.background, "The artist turned the paper off, so there is no paper")
        XCTAssertNil(hidden.below.background)
        XCTAssertNil(hidden.above.background)
    }

    func testTheHalvesCarryTheSplitTreesAndTheFrameAndQualityTheyWereAskedFor() {
        let manager = stack(3)
        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1, quality: .preview)?.resolve() else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(requests.below.tree.leafLayerIndices, [0])
        XCTAssertEqual(requests.above.tree.leafLayerIndices, [2])
        XCTAssertEqual(requests.full.tree.leafLayerIndices, [0, 1, 2])
        for request in [requests.full, requests.below, requests.above] {
            XCTAssertEqual(request.frame, 0)
            XCTAssertEqual(request.canvasSize, manager.canvasSize)
            XCTAssertEqual(request.quality, .preview)
        }
    }

    func testThereAreNoSandwichRequestsForALayerThatIsNotInTheTree() {
        XCTAssertNil(stack(2).makeSandwichRecipe(atFrame: 0, activeLayerIndex: 7)?.resolve(),
                     "A caller with a stale active index gets nil rather than a silently wrong cut")
    }

    func testThereAreNoSandwichRequestsWithoutACanvas() {
        let manager = CanvasManager()
        XCTAssertNil(manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0)?.resolve(),
                     "Same degenerate-size guard `makeRenderRequest` has")
    }

    /// A layer with no cel at this frame is elided from `sources` exactly as `makeRenderRequest`
    /// elides it, because it is the same code — the split changes which tree walks over the sources,
    /// never which sources exist.
    func testASandwichAtAFrameWithNoCelElidesThatLeafJustAsOneRequestWould() {
        let manager = stack(3)
        CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 5, length: 3)])

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              // Like for like: `full` carries the paper, so the reference does too.
              let reference = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNil(requests.above.sources[2], "Layer 2's block starts at frame 5")
        XCTAssertEqual(requests.full.sources.map { $0 == nil }, reference.sources.map { $0 == nil })
        assertPixelsIdentical(Compositor.composite(requests.full), Compositor.composite(reference),
                              "And the frame composites to the same picture either way")
    }

    // MARK: - The shipped configuration

    /// **What the exactness above costs in the backend the app actually runs**, measured rather than
    /// assumed, because `setUp` pins this file to CoreGraphics and something has to check the other
    /// one.
    ///
    /// `testTheSandwichCostsAtMostAChannelStepWhereAlphaIsFractional` asserts the lower half is exact
    /// — 0, not "small" — and its argument is structural: `below` is a prefix of the same walk, drawn
    /// into a still-transparent context, so it is a copy. That argument is about the *walk* and it
    /// survives the flip untouched. What does not survive is the arithmetic being identical on both
    /// sides of the comparison: mid-stroke the canvas shows GPU-composited halves recombined by Core
    /// Animation, and it is measured against a GPU-composited whole, so the two backends' float→unorm8
    /// rounding meets in a place it did not before.
    ///
    /// One step is the tolerance `CompositorParityLogicTests` already pins between the backends for
    /// every blend mode, so this asserts the same bound rather than a new one — and it is worth having
    /// as its own case so that a future change which makes it *two* is a failure with a name on it,
    /// rather than a slow drift nobody is watching.
    func testTheShippedBackendCostsTheLowerHalfAtMostOneChannelStep() {
        Compositor.backend = Compositor.defaultBackend
        let manager = stack(5)
        for (offset, opacity) in [0.37, 0.53, 0.41, 0.29].enumerated() {
            manager.layers[offset + 1].opacity = opacity
        }
        guard let low = makeSandwichAndExact(manager, active: 4) else {
            return XCTFail("Fixture needs a canvas size")
        }
        let delta = maxChannelDelta(low.sandwich, low.exact)
        print("[sandwich] lower-half delta on \(Compositor.defaultBackend): \(delta)")
        XCTAssertLessThanOrEqual(delta, 1,
                                 "The lower half is still a prefix of the same walk; a delta of \(delta) "
                                 + "is a different picture rather than the backends' documented rounding step")
    }

    // MARK: - Render resolution

    /// **The containment `RenderResolution` claims, asserted rather than described.** The setting is
    /// safe to leave switched on only because it cannot reach anything that is written down — so the
    /// two halves of that are one test: the sandwich shrinks, and the request every other consumer
    /// builds does not.
    func testRenderResolutionScalesTheSandwichAndLeavesEveryOtherRequestAlone() {
        let manager = stack(3)
        guard let canvasSize = manager.canvasSize else { return XCTFail("Fixture needs a canvas size") }
        manager.renderResolution = .half

        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              let reference = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must produce both shapes of request")
        }

        let halved = CGSize(width: canvasSize.width / 2, height: canvasSize.height / 2)
        for (name, request) in [("full", requests.full), ("below", requests.below), ("above", requests.above)] {
            XCTAssertEqual(request.canvasSize, halved, "The \(name) request renders at the chosen resolution")
        }
        XCTAssertEqual(reference.canvasSize, canvasSize,
                       "`makeRenderRequest` is what the thumbnail and the saved package go through, and "
                       + "a live-canvas preference must never reach either")

        // The sources have to shrink with the request, not merely the buffers it composites into: a
        // canvas-sized leaf under a half-sized full-canvas dispatch is the wrong-size-texture case
        // `RenderResolution.renderSize` guards against, and it is a garbage frame rather than a soft
        // one.
        XCTAssertEqual(requests.full.sources.compactMap { $0 }.first?.image.width, Int(halved.width),
                       "Sources are rasterized at the render size, not merely composited into it")
        XCTAssertEqual(Compositor.composite(requests.full)?.width, Int(halved.width))
        XCTAssertEqual(Compositor.composite(reference)?.width, Int(canvasSize.width))
    }

    /// `.full` has to be the exact identity, not "close enough at 100%" — otherwise the default
    /// setting would route every document through a resize that rounds, and the byte-parity the
    /// compositor tests pin would hold for the compositor and not for what reaches it.
    func testFullResolutionIsTheIdentityByteForByte() {
        let manager = stack(3)
        manager.renderResolution = .full
        guard let scaled = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              // Like for like: `full` carries the paper, so the reference does too.
              let reference = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must produce both shapes of request")
        }
        XCTAssertEqual(scaled.full.canvasSize, reference.canvasSize)
        assertPixelsIdentical(Compositor.composite(scaled.full), Compositor.composite(reference),
                              "Full resolution must be the same walk over the same pixels it always was")
    }

    /// An odd canvas is where a scale factor turns into an off-by-one, and 75% of an odd number is
    /// the case that exercises both roundings at once — see `RenderResolution.renderSize` for why
    /// this is rounded upstream of the backends rather than inside them.
    func testAnOddCanvasAtThreeQuartersKeepsSourcesAndCompositeTheSameSize() {
        let manager = stack(3)
        manager.canvasSize = CGSize(width: 65, height: 63)
        manager.renderResolution = .threeQuarter
        guard let requests = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve() else {
            return XCTFail("Fixture must produce a sandwich")
        }
        let composite = Compositor.composite(requests.full)
        XCTAssertEqual(composite?.width, requests.full.sources.compactMap { $0 }.first?.image.width,
                       "A source wider than the composite reading it is a garbage frame on the GPU")
        XCTAssertEqual(composite?.height, requests.full.sources.compactMap { $0 }.first?.image.height)
        XCTAssertEqual(composite?.width, 49, "65 * 0.75 = 48.75, rounded once, upstream of both backends")
    }

    // MARK: - An in-between under the playhead (KEYFRAMES §10)

    /// A three-cel vector layer whose middle cel is a `.generate` in-between, over an opaque backdrop.
    ///
    /// The ink is **cyan** and the backdrop is **red**, which is what makes the pixel claim below
    /// exact rather than approximate. `multiply`'s result is `a·(Cs·Cb) + (1 - a)·Cb`; with
    /// `Cs = (0, 1, 1)` and `Cb = (1, 0, 0)` the product is black, so the composited green and blue
    /// channels are **0 for every alpha the in-between happens to have**. Source-over at the same
    /// pixel gives `(1 - a, a, a)`, whose green is positive wherever there is any ink at all. So one
    /// pixel separates "the compositor drew this" from "Core Animation drew this" with no tolerance
    /// and no dependence on what the ARAP solve produced.
    ///
    /// The backdrop covers the whole canvas so that premultiplied bytes and straight bytes agree —
    /// `CanvasFixture.rgbaBytes` is premultiplied-last, and an opaque composite makes the two the
    /// same numbers.
    private func inBetweenOverBackdrop() throws -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        let size = CanvasFixture.canvasSize
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(origin: .zero, size: size)))
        manager.addVectorLayer()

        func stroke(_ points: [CGPoint]) -> VectorStroke {
            VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                         color: CodableColor(red: 0, green: 1, blue: 1, alpha: 1),
                         size: 9, opacity: 1,
                         samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
        }
        let cels = (0..<3).map { index in
            Cel(id: UUID(), startFrame: index * 4, frameCount: 4,
                raster: .empty(size: size), vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20), CGPoint(x: 30, y: 40)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 34, y: 20), CGPoint(x: 54, y: 20), CGPoint(x: 54, y: 40)]))

        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[1].id)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1),
                     "Setup: Generate must attach a recipe")
        manager.layers[1].cels[1].interpolation?.t = 0.5
        manager.exitInterpolateMode()
        try XCTSkipIf(manager.layers[1].cels[1].interpolation == nil, "Setup: no recipe")

        manager.currentFrame = 5      // inside the middle cel, which spans 4...7
        manager.currentLayerIndex = 1
        return manager
    }

    /// **The behaviour change, as pixels.** Until 2026-08-29 `isSandwichEngaged` refused whenever any
    /// layer's active cel carried a recipe, so the artist's blend modes, effects and mask clipping
    /// were silently off on every in-between (KEYFRAMES §10). `renderSources` hands every flatten its
    /// `DerivedCelContent` now, so the composite contains the in-between and the refusal has nothing
    /// left to protect.
    ///
    /// Three claims, in the order they would fail if this regressed:
    ///
    /// 1. The predicate engages. A document with a blend mode and an in-between under the playhead is
    ///    exactly the case the removed clause refused.
    /// 2. The in-between is *in* the composite — the same picture with the recipe taken off is a
    ///    different picture, so this is not asserting about an empty layer.
    /// 3. The blend actually reached it, at one exact pixel. See `inBetweenOverBackdrop` for why the
    ///    green channel is a clean discriminator.
    @MainActor
    func testAnInBetweenUnderABlendModeCompositesBlendedRatherThanFallingBack() throws {
        let manager = try inBetweenOverBackdrop()
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        let tree = manager.renderTree(atFrame: 5)
        XCTAssertTrue(tree.needsCompositorOnCanvas, "Setup: a multiply layer needs the compositor")
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree),
                      "An in-between under the playhead must no longer take the compositor off the canvas")

        guard let requests = manager.makeSandwichRecipe(atFrame: 5, activeLayerIndex: 1)?.resolve(),
              let multiplied = Compositor.composite(requests.full) else {
            return XCTFail("Fixture needs a canvas size")
        }

        // (2) — the same document with the recipe removed. The cel stores nothing, so this is the
        // picture the canvas would show if the in-between were missing from the composite.
        let blank = try inBetweenOverBackdrop()
        blank.setLayerBlendMode(layerIndex: 1, to: .multiply)
        blank.layers[1].cels[1].interpolation = nil
        guard let withoutTheInBetween = blank.makeSandwichRecipe(atFrame: 5, activeLayerIndex: 1)
            .flatMap({ Compositor.composite($0.resolve().full) }) else {
            return XCTFail("Control needs a canvas size")
        }
        XCTAssertNotEqual(CanvasFixture.rgbaBytes(multiplied), CanvasFixture.rgbaBytes(withoutTheInBetween),
                          "The composite the canvas now shows has to contain the in-between's ink")

        // (3) — the same document drawn source-over, which is what Core Animation's flat row of hosts
        // produces and therefore what the artist saw before this change.
        let plain = try inBetweenOverBackdrop()
        guard let sourceOver = plain.makeSandwichRecipe(atFrame: 5, activeLayerIndex: 1)
            .flatMap({ Compositor.composite($0.resolve().full) }) else {
            return XCTFail("Control needs a canvas size")
        }

        // The most-inked pixel of the derived frame, found rather than assumed: an ARAP in-between is
        // not where either keyframe's stroke is, and hard-coding a coordinate would pin the solver.
        let cel = manager.layers[1].cels[1]
        let derived = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 5)?.render(.full),
                                    "The in-between must derive something to blend")
        let inkBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(derived.cgImage)))
        var best = (alpha: 0, x: 0, y: 0)
        for y in 0..<Int(CanvasFixture.canvasSize.height) {
            for x in 0..<Int(CanvasFixture.canvasSize.width) {
                let alpha = Int(inkBytes[(x + y * Int(CanvasFixture.canvasSize.width)) * 4 + 3])
                if alpha > best.alpha { best = (alpha, x, y) }
            }
        }
        XCTAssertGreaterThan(best.alpha, 0, "The in-between has to have ink somewhere to blend")

        let blended = pixel(multiplied, best.x, best.y)
        let unblended = pixel(sourceOver, best.x, best.y)
        XCTAssertGreaterThan(unblended[1], 0,
                             "Control: source-over puts cyan's green on screen, which is the fallback picture")
        XCTAssertEqual(blended[1], 0, "multiply(cyan, red) has no green at any alpha — this is the blend")
        XCTAssertEqual(blended[2], 0, "…and no blue")
    }

    /// The same claim for an **effect** and for a **mask**, which are the other two things the removed
    /// clause was silently switching off — and the mask is the one KEYFRAMES §10 does not name and
    /// `isSandwichEngaged` calls the more visible loss: `updateSandwich`'s disengage branch also calls
    /// `host.setContentMask(nil)`, so §6.4's clipping came off the canvas on every in-between frame.
    ///
    /// Asserted through `needsCompositorOnCanvas` and the predicate rather than through pixels: the
    /// composite's own correctness for effects and masks is `EffectLayerLogicTests`' and
    /// `MaskParityLogicTests`' subject, and what is new here is only *whether the canvas asks for it*.
    @MainActor
    func testAnAdjustmentLayerAlsoEngagesOnAnInBetween() throws {
        let cases: [(String, (CanvasManager) -> Void)] = [
            // A grade is a `.value` layer in effect mode — `setLayerEffect` refuses any other kind —
            // so the adjustment layer is added rather than set on an existing one.
            ("an adjustment layer", {
                $0.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.6)))
            }),
            ("a blend mode", { $0.setLayerBlendMode(layerIndex: 1, to: .screen) }),
        ]
        for (what, prepare) in cases {
            let manager = try inBetweenOverBackdrop()
            prepare(manager)
            let tree = manager.renderTree(atFrame: 5)
            XCTAssertTrue(tree.needsCompositorOnCanvas, "Setup: \(what) needs the compositor")
            XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree),
                          "\(what) must reach the canvas on an in-between frame")
        }
    }

    /// **What the removal did not take with it.** The two gestures that draw outside every cel still
    /// refuse, and a document with nothing to composite still never engages — the containment.
    @MainActor
    func testTheEngagementClausesThatSurvivedTheRemoval() throws {
        let plain = stack(3)
        XCTAssertFalse(plain.sandwichEngagesOnCanvas(tree: plain.renderTree(atFrame: 0)),
                       "A document with no blend, effect, mask or node stays on Core Animation's path")

        let manager = try inBetweenOverBackdrop()
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
        let tree = manager.renderTree(atFrame: 5)
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree), "Baseline")

        // The interpolation slider writes `t` per tick and the derivation is in the key, so every
        // tick would otherwise be an ARAP evaluation and three canvas-sized composites. The clause is
        // the drag, not the frame — see `sandwichEngagesOnCanvas` and PERFORMANCE.md §14.
        manager.beginInterpolationDrag()
        XCTAssertFalse(manager.sandwichEngagesOnCanvas(tree: tree),
                       "The compositor comes off for the scrub gesture, not for the frames it lands on")
        manager.commitInterpolationDrag()
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree),
                      "…and is back the instant the drag commits")
    }

    /// **The key that has to move with it, and the reason removing the clause was not a one-line
    /// change.** `SandwichKey` decides whether to recomposite at all. An in-between's `t` lives on the
    /// `Cel` and moves no object identity and no version number, so a content version built without
    /// the derivation is *identical* across a retime — the canvas would engage on an in-between and
    /// then show the first one it composited for ever, with nothing in the key looking wrong
    /// (KEYFRAMES §4.5).
    ///
    /// It drives `CanvasManager.contentVersion(ofLayer:atFrame:)`, which is the function
    /// `makeSandwichKey` calls, rather than rebuilding the field list here — a mirror cannot catch a
    /// field the original is missing. Verified by mutation: dropping `derived:` from that builder
    /// fails both halves below and leaves the rest of the fast tier green.
    @MainActor
    func testTheLiveCompositesKeyMovesWhenAnInBetweensDerivationDoes() throws {
        let manager = try inBetweenOverBackdrop()
        let before = manager.contentVersion(ofLayer: 1, atFrame: 5)
        XCTAssertNotNil(before, "Setup: the layer has a cel at this frame")

        manager.layers[1].cels[1].interpolation?.t = 0.9
        XCTAssertNotEqual(before, manager.contentVersion(ofLayer: 1, atFrame: 5),
                          "Retiming an in-between is a new picture and must be a new key")

        // The other silent path, and the one the recipe's whole "derived, never stored" design exists
        // for: the pixels move because a *different* cel — at a different frame, so in no other field
        // of this key — was edited.
        let retimed = manager.contentVersion(ofLayer: 1, atFrame: 5)
        manager.layers[1].cels[0].vector?.addStroke(
            VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                         color: CodableColor(red: 0, green: 1, blue: 1, alpha: 1), size: 9, opacity: 1,
                         samples: [VectorSample(x: 8, y: 52, pressure: 1),
                                   VectorSample(x: 50, y: 52, pressure: 1)]))
        XCTAssertNotEqual(retimed, manager.contentVersion(ofLayer: 1, atFrame: 5),
                          "Editing keyframe A must reach the in-between's entry in the live key")

        // And the companion: a key unique per call would satisfy both while turning the composite
        // cache off entirely, which is a rebuild per SwiftUI pass that no test would name.
        XCTAssertEqual(manager.contentVersion(ofLayer: 1, atFrame: 5),
                       manager.contentVersion(ofLayer: 1, atFrame: 5),
                       "Nothing moved, so the key must not have")
        XCTAssertNil(manager.contentVersion(ofLayer: 1, atFrame: 99),
                     "No cel at this frame is no content version, exactly as the loop it replaced said")
    }
}
