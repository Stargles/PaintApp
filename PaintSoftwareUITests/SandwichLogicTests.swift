import XCTest
import UIKit

/// The model half of §5.2's sandwich — LAYER_COMPOSITING.md §11 phase 5b.
///
/// `CanvasView.reconcileLayers` hands every layer to Core Animation as a flat sibling, and Core
/// Animation has no per-view Multiply against arbitrary siblings. So a blended layer composites
/// correctly in the thumbnail and shows nothing on the live canvas. §5.2's answer is three views —
/// the composite of everything below the active layer, that layer's own stroke host untouched, and
/// the composite of everything above — and `Array<RenderNode>.split(atLeaf:)` with
/// `CanvasManager.makeSandwichRequests` is the cut and the snapshot that feed them. Nothing here
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
/// `@MainActor` because `makeSandwichRequests` is — the app target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and this one does not.
@MainActor
final class SandwichLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let yellow = UIColor(red: 1, green: 1, blue: 0, alpha: 1)
    private let cyan = UIColor(red: 0, green: 1, blue: 1, alpha: 1)
    private let grey = UIColor(white: 128.0 / 255, alpha: 1)

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
              let requests = manager.makeSandwichRequests(atFrame: frame, activeLayerIndex: active),
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
            let tree = testCase.manager.renderTree
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
        let shapes = battery().map { shape($0.manager.renderTree) }
        XCTAssertGreaterThanOrEqual(Set(shapes).count, 6,
                                    "Only \(Set(shapes).count) distinct shapes in \(shapes.count) cases: \(shapes)")
        XCTAssertGreaterThanOrEqual(shapes.filter { $0.contains("(") }.count, 5,
                                    "Most of the battery must involve folders — the flat cases cannot exercise a half-group at all. Shapes: \(shapes)")
        XCTAssertGreaterThanOrEqual(battery().map { depth($0.manager.renderTree) }.max() ?? 0, 3,
                                    "One case must nest two folders deep, which is where a half-group has to contain another half-group. Shapes: \(shapes)")
    }

    func testSplittingAtAnIndexThatIsNotALeafOfTheTreeReturnsNil() {
        let manager = stack(3)
        XCTAssertNil(manager.renderTree.split(atLeaf: 99), "There is no layer 99")
        XCTAssertNil(manager.renderTree.split(atLeaf: -1), "Nor a layer -1")
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

        guard let halves = manager.renderTree.split(atLeaf: 1),
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

        guard let halves = manager.renderTree.split(atLeaf: 0) else {
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

        guard let halves = manager.renderTree.split(atLeaf: 1) else {
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
            guard let requests = testCase.manager.makeSandwichRequests(atFrame: 0,
                                                                      activeLayerIndex: testCase.active),
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

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 1),
              let reference = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertEqual(requests.full.tree.leafLayerIndices, manager.renderLeafOrder)
        assertPixelsIdentical(Compositor.composite(requests.full), Compositor.composite(reference),
                              "At rest the canvas shows `composite(full)`, which must be the same picture the thumbnail shows")
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
        guard let requests = manager.makeSandwichRequests(atFrame: frame, activeLayerIndex: active),
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

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0),
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

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 1),
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

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0),
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
        XCTAssertFalse(stack(3).renderTree.needsCompositorOnCanvas, "A flat all-normal stack is Core Animation's own case")

        let nested = stack(4)
        let outer = nested.addFolder(name: "Outer")
        let inner = nested.addFolder(name: "Inner", parentFolderID: outer)
        nested.layers[0].parentFolderID = outer
        nested.layers[1].parentFolderID = inner
        nested.layers[2].parentFolderID = inner
        XCTAssertFalse(nested.renderTree.needsCompositorOnCanvas,
                       "Untouched folders are transparent parentheses — opacity 1, normal, isolated over nothing that blends")
    }

    /// **The clause that is not covered by `needsOwnBuffer`, and the reason the predicate has two.**
    /// A leaf blends as it is drawn rather than as an assembled composite, so it never wants a buffer
    /// — and a blending leaf in a flat stack is precisely the document phase 5b exists for.
    func testABlendingLeafNeedsTheCompositorEvenThoughItNeedsNoBuffer() {
        let manager = stack(2)
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        XCTAssertFalse(manager.renderTree[1].needsOwnBuffer, "A leaf's mode is an argument to one draw call")
        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas,
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

        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas, "Two levels down is still in the document")
    }

    func testABlendingGroupNeedsTheCompositor() {
        let manager = stack(2)
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.setFolderBlendMode(folder, to: .overlay)

        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas,
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

        XCTAssertFalse(manager.renderTree.needsCompositorOnCanvas, "At opacity 1 it is still a parenthesis")
        manager.setFolderOpacity(folder, to: 0.99)
        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas, "Not 1 is the test, not \"visibly faded\"")
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

        XCTAssertTrue(manager.renderTree[1].needsOwnBuffer,
                      "Isolated over something that blends is the clause — the group's children start from transparency, which differs from starting from the backdrop only because one of them blends")
        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas)
    }

    // MARK: - The requests

    /// **One snapshot, three requests, and the sharing is the point.** `sources` is indexed by
    /// `layers` index rather than by position in a tree, so the same array answers all three walks —
    /// and the snapshot is the expensive half (§11: 276 ms against an 84 ms composite), so building
    /// it three times would cost more than the compositing does.
    func testTheThreeRequestsShareOneSnapshot() {
        let manager = stack(3)
        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 1) else {
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

    /// The live canvas paints its own `paperView` behind the whole stack, so a background in any of
    /// the three would be either a second one or an opaque sheet over the layers beneath it.
    func testNoneOfTheThreeRequestsCarriesABackground() {
        let manager = stack(2)
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNil(requests.full.background)
        XCTAssertNil(requests.below.background)
        XCTAssertNil(requests.above.background)
    }

    func testTheHalvesCarryTheSplitTreesAndTheFrameAndQualityTheyWereAskedFor() {
        let manager = stack(3)
        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 1, quality: .preview) else {
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
        XCTAssertNil(stack(2).makeSandwichRequests(atFrame: 0, activeLayerIndex: 7),
                     "A caller with a stale active index gets nil rather than a silently wrong cut")
    }

    func testThereAreNoSandwichRequestsWithoutACanvas() {
        let manager = CanvasManager()
        XCTAssertNil(manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0),
                     "Same degenerate-size guard `makeRenderRequest` has")
    }

    /// A layer with no cel at this frame is elided from `sources` exactly as `makeRenderRequest`
    /// elides it, because it is the same code — the split changes which tree walks over the sources,
    /// never which sources exist.
    func testASandwichAtAFrameWithNoCelElidesThatLeafJustAsOneRequestWould() {
        let manager = stack(3)
        CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 5, length: 3)])

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 1),
              let reference = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNil(requests.above.sources[2], "Layer 2's block starts at frame 5")
        XCTAssertEqual(requests.full.sources.map { $0 == nil }, reference.sources.map { $0 == nil })
        assertPixelsIdentical(Compositor.composite(requests.full), Compositor.composite(reference),
                              "And the frame composites to the same picture either way")
    }
}
