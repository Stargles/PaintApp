import XCTest
import UIKit
import CoreGraphics

/// **Every bake, in stacks of several layers, keeps the picture and touches nothing it did not consume**
/// — TODO (153)'s second half. The owner: *"make sure that any bake down behaviour in a move layer or
/// effect layer works properly with multiple layers. Rules are that baking down should not change the
/// image (colors should remain near identical except for peculiarities. Think of it as applying the
/// correct transformation to brushstroke colors, not in the compositor)."*
///
/// One harness over a table of two-to-four-layer stacks mixing vector ink, raster ink, still and keyed
/// transformation layers, a Repeat, an effect layer and a flat-colour value layer, in several orders.
/// **Every layer that bakes is baked in turn, each from a fresh build of its stack**, and four things are
/// asserted of each bake:
///
/// 1. **The picture** at six frames — on the keys and between them — is what it was. **A flat colour is
///    compared inside the ink**: over transparency the compositor shows its sheet, and EFFECT_BACKDROP.md
///    §2.3's ruling — *"the paper stays white … gaps where paper or another drawing showed through do
///    change appearance … That is accepted"* — is that a bake changes drawings and not the paper. So
///    where the drawings beneath are opaque the colour must be what it was, where they are absent the
///    baked document must show nothing, and a texel the ink only partly covers — where the sheet showed
///    through it — is the stated exception and is not compared. The tolerance is
///    stated per row and is **zero** for every row whose ink is crisp and axis-aligned under the pose:
///    each of those is the same bytes. A turned pose re-rasterises a turned edge, and a turned edge's
///    coverage is computed once from posed geometry and once from geometry posed and stored — the same
///    map, rounded in a different order — so a turned row is allowed **2 of 255** on an edge texel, the
///    figure `BakeTransformLogicTests` already pins for one layer. A flat colour's blend is allowed
///    **1 of 255**: the bake computes the blended colour once, in floating point, and stores it on the
///    stroke, where the compositor blends two 8-bit buffers — one rounding against two, MEASURED at
///    exactly 1 on both blend rows and never more. Ink never overlaps other ink here: the
///    owner's "peculiarities" are exactly the overlaps and soft edges where grading a drawing alone and
///    grading the composite must differ, and a fixture that contained them would be measuring the rule's
///    stated exception rather than the rule.
/// 2. **Every layer the bake did not consume** — every layer but the baker and the drawings its plan
///    names — is identical: its keys, tracks, marks, pose, grade, colour, blend, opacity, order, and its
///    cels down to the same content objects. Compared within one fixture before and after, so a
///    difference is the bake's and not an allocation address (CLAUDE.md, "a green assertion is only as
///    good as its two operands").
/// 3. **Saved and opened again**, the baked document draws the same picture and the unconsumed layers
///    carry the same values.
/// 4. **One Undo** puts every layer back as it was, content objects included, and the picture with it.
///
/// A bake that refuses must change nothing at all; one that leaves a layer behind must say so by name.
@MainActor
final class BakeInvariantLogicTests: XCTestCase {

    private var root: URL!
    private var size: CGSize { CanvasFixture.canvasSize }
    private var canvasRect: CGRect { CGRect(origin: .zero, size: size) }
    private let frames = [0, 2, 3, 5, 8, 10]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bake-invariant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDownWithError() throws {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The layers a stack is built from, bottom to top

    private static let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    private static let grey = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    private static let hueRotate = Effect.hsvShift(Effect.HSVShift(hueDegrees: 120))
    private static let turn = CGAffineTransform(translationX: 32, y: 32).rotated(by: 0.3).translatedBy(x: -32, y: -32)

    private enum Spec {
        /// A crisp square of `colour` and a fixture-Pencil line under it, in a band of its own.
        case vector(String, band: Int, colour: CodableColor)
        /// One drawing per block, each in its own place — what a Repeat has to replay.
        case walker(String, band: Int)
        /// A crisp square whose cel carries its own motion: at rest at 0, carried by `to` at 8.
        case animated(String, band: Int, to: CGAffineTransform)
        /// A blue square of pixels.
        case raster(String, band: Int)
        /// A transformation layer posing by one map at every frame.
        case still(String, CGAffineTransform)
        /// A transformation layer keyed at 0 and 8: rest, then `to`.
        case keyed(String, to: CGAffineTransform)
        case loop(String, period: Int)
        case grade(String, Effect)
        case flat(String, hex: String, blend: BlendMode)

        var name: String {
            switch self {
            case .vector(let n, _, _), .walker(let n, _), .animated(let n, _, _), .raster(let n, _), .still(let n, _),
                 .keyed(let n, _), .loop(let n, _), .grade(let n, _), .flat(let n, _, _): return n
            }
        }

        /// A flat colour, whose sheet the paper rule takes away outside the ink.
        var isFlatColour: Bool {
            if case .flat = self { return true }
            return false
        }

        var isAnimatedDrawing: Bool {
            if case .animated = self { return true }
            return false
        }

        var bakes: Bool {
            switch self {
            case .vector, .walker, .animated, .raster: return false
            case .still, .keyed, .loop, .grade, .flat: return true
            }
        }
    }

    private struct Row {
        let name: String
        let stack: [Spec]
        /// The worst byte difference a bake of this stack may leave — see the type's header.
        var tolerance = 0
    }

    private static let rows: [Row] = [
        Row(name: "the owner's: a keyed Move over a still one",
            stack: [.vector("Ink", band: 0, colour: red), .still("Still", .init(translationX: 6, y: 0)),
                    .keyed("Keyed", to: CGAffineTransform(translationX: 14, y: 4))]),
        Row(name: "a turning keyed Move over a still one",
            stack: [.vector("Ink", band: 0, colour: red), .still("Still", .init(translationX: 6, y: 0)),
                    .keyed("Keyed", to: turn)], tolerance: 2),
        Row(name: "a still turn over a keyed slide",
            stack: [.vector("Ink", band: 0, colour: red), .keyed("Keyed", to: .init(translationX: 12, y: 0)),
                    .still("Still", turn)], tolerance: 2),
        Row(name: "raster and vector ink under a grade under a Move",
            stack: [.raster("Paint", band: 2), .vector("Ink", band: 0, colour: red), .grade("Grade", hueRotate),
                    .still("Still", .init(translationX: 6, y: 0))]),
        Row(name: "a Move under a grade",
            stack: [.vector("Ink", band: 0, colour: red), .keyed("Keyed", to: .init(translationX: 10, y: 0)),
                    .grade("Grade", hueRotate)]),
        Row(name: "a grade between two Moves",
            stack: [.vector("Ink", band: 0, colour: red), .still("Still", .init(translationX: 6, y: 0)),
                    .grade("Grade", hueRotate), .keyed("Keyed", to: .init(translationX: 0, y: 8))]),
        Row(name: "a multiplied flat colour under a keyed Move",
            stack: [.vector("Ink", band: 0, colour: grey), .raster("Paint", band: 2),
                    .flat("Tint", hex: "FF8000", blend: .multiply),
                    .keyed("Keyed", to: .init(translationX: 10, y: 0))], tolerance: 1),
        Row(name: "a keyed Move under a screened flat colour",
            stack: [.vector("Ink", band: 0, colour: red), .keyed("Keyed", to: .init(translationX: 10, y: 0)),
                    .flat("Tint", hex: "3366CC", blend: .screen)], tolerance: 1),
        Row(name: "an animated drawing under a keyed Move",
            stack: [.animated("Walk", band: 0, to: .init(translationX: 16, y: 0)), .vector("Ink", band: 2, colour: red),
                    .keyed("Keyed", to: .init(translationX: 0, y: 6))]),
        Row(name: "an animated drawing under a grade under a still turn",
            stack: [.animated("Walk", band: 0, to: .init(translationX: 16, y: 0)), .grade("Grade", hueRotate),
                    .still("Still", turn)], tolerance: 2),
        Row(name: "a Repeat under a still Move",
            stack: [.walker("Walker", band: 0), .loop("Loop", period: 3), .still("Still", .init(translationX: 4, y: 0))]),
        Row(name: "a still Move under a Repeat",
            stack: [.walker("Walker", band: 0), .still("Still", .init(translationX: 4, y: 0)), .loop("Loop", period: 3)]),
    ]

    private func build(_ row: Row) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        for spec in row.stack { add(spec, to: manager) }
        return manager
    }

    private func band(_ band: Int) -> CGFloat { 6 + 18 * CGFloat(band) }

    private func add(_ spec: Spec, to manager: CanvasManager) {
        switch spec {
        case .vector(let name, let band, let colour):
            manager.addVectorLayer(name: name)
            let vector = manager.layers[manager.layers.count - 1].cels[0].vector!
            vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 8, y: self.band(band), width: 10, height: 10),
                                                    transform: nil), color: colour)
            vector.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.pencil, color: colour, size: 4, opacity: 1,
                                          samples: StrokeSamples([VectorSample(x: 24, y: self.band(band) + 5, pressure: 1),
                                                                  VectorSample(x: 34, y: self.band(band) + 6, pressure: 1)],
                                                                 channels: .pressureOnly)))
        case .walker(let name, let band):
            manager.addVectorLayer(name: name)
            manager.layers[manager.layers.count - 1].cels = [(0, 1), (1, 1), (2, 10)].enumerated().map { i, block in
                let vector = VectorCanvas.empty(size: size)
                vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 6 + 12 * CGFloat(i), y: self.band(band),
                                                                    width: 8, height: 10), transform: nil),
                               color: Self.red)
                return Cel(id: UUID(), startFrame: block.0, frameCount: block.1, raster: .empty(size: size), vector: vector)
            }
        case .animated(let name, let band, let map):
            manager.addVectorLayer(name: name)
            let at = manager.layers.count - 1
            manager.layers[at].cels[0].vector!.addFill(
                canvasSpacePath: CGPath(rect: CGRect(x: 8, y: self.band(band), width: 10, height: 10), transform: nil),
                color: Self.red)
            let rest = PoseQuad(restingIn: canvasRect)
            CanvasFixture.setPoseTrack(manager, layerID: manager.layers[at].id, celID: manager.layers[at].cels[0].id,
                                       CanvasFixture.poseTrack([(0, rest), (8, PoseQuad(box: canvasRect, mappedBy: map))],
                                                               interpolation: .linear))
        case .raster(let name, let band):
            manager.addLayer(name: name)
            CanvasFixture.setBakedContent(manager, layerIndex: manager.layers.count - 1,
                                          CanvasFixture.solidImage(.blue, rect: CGRect(x: 8, y: self.band(band),
                                                                                       width: 10, height: 10)))
        case .still(let name, let map):
            manager.addTransformLayer(name: name)
            manager.layers[manager.layers.count - 1].transform = LayerPose(pose: PoseQuad(box: canvasRect, mappedBy: map))
        case .keyed(let name, let map):
            manager.addTransformLayer(name: name)
            let rest = PoseQuad(restingIn: canvasRect)
            manager.layers[manager.layers.count - 1].transform = LayerPose(
                pose: rest,
                track: CanvasFixture.poseTrack([(0, rest), (8, PoseQuad(box: canvasRect, mappedBy: map))],
                                               interpolation: .linear))
        case .loop(let name, let period):
            manager.addTransformLayer(name: name)
            manager.layers[manager.layers.count - 1].transform = LayerPose(pose: PoseQuad(restingIn: canvasRect),
                                                                           mode: .repeat, repeatPeriod: period)
        case .grade(let name, let effect):
            manager.addValueLayer(effect: effect, name: name)
        case .flat(let name, let hex, let blend):
            manager.addValueLayer(color: PaletteColor(hex: hex), name: name)
            manager.layers[manager.layers.count - 1].blendMode = blend
        }
    }

    // MARK: - What is compared

    /// **One layer, every field a bake could touch**, plus its cels' content objects when `identity` is
    /// asked for — the same object before and after is a cel nothing rewrote.
    private struct Print: Equatable {
        struct CelPrint: Equatable {
            let id: UUID, start: Int, length: Int
            let tracks: [String: TransformTrack]
            let baselines: [String: PoseQuad]
            let content: [ObjectIdentifier]
        }
        let id: UUID, name: String, kind: LayerKind
        let opacity: Double, isVisible: Bool, blendMode: BlendMode, alphaMask: AlphaMask?
        let effect: Effect?, effectTracks: [String: AnimationCurve]
        let channelTracks: [String: AnimationCurve], channelBaselines: [String: Double]
        let marks: [Int], pendingBaselines: [String: Double]
        let transform: LayerPose?, rotateSpeed: Double, parallaxShare: Double?
        let shake: [Double], fill: ValueFill?, parent: UUID?
        let cels: [CelPrint]
    }

    private func prints(_ manager: CanvasManager, identity: Bool) -> [UUID: Print] {
        Dictionary(uniqueKeysWithValues: manager.layers.map { layer in
            (layer.id, Print(
                id: layer.id, name: layer.name, kind: layer.kind,
                opacity: layer.opacity, isVisible: layer.isVisible, blendMode: layer.blendMode, alphaMask: layer.alphaMask,
                effect: layer.effect, effectTracks: layer.effectTracks,
                channelTracks: layer.channelTracks, channelBaselines: layer.channelBaselines,
                marks: layer.keyframeMarks, pendingBaselines: layer.pendingBaselines,
                transform: layer.transform, rotateSpeed: layer.rotateSpeed, parallaxShare: layer.parallaxShare,
                shake: [layer.shakeX, layer.shakeY, layer.shakeRotation], fill: layer.fill, parent: layer.parentFolderID,
                cels: layer.cels.map { cel in
                    Print.CelPrint(id: cel.id, start: cel.startFrame, length: cel.frameCount,
                                   tracks: cel.transformTracks, baselines: cel.pendingPoseBaselines,
                                   content: identity
                                       ? [ObjectIdentifier(cel.raster)] + (cel.vector.map { [ObjectIdentifier($0)] } ?? [])
                                       : [])
                }))
        })
    }

    private func composite(_ manager: CanvasManager, frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite at frame \(frame)")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    private func scene(_ manager: CanvasManager) throws -> [[UInt8]] {
        try frames.map { try composite(manager, frame: $0) }
    }

    /// The worst byte difference between two renders of the same frames, and the frame it is on —
    /// over every texel, or, given the drawings' own coverage, where they are opaque (and, where they
    /// are absent, against nothing at all).
    private func worst(_ got: [[UInt8]], _ want: [[UInt8]], insideInk ink: [[UInt8]]? = nil)
        -> (difference: Int, frame: Int) {
        var result = (difference: 0, frame: -1)
        for index in got.indices {
            var difference = 0
            for texel in stride(from: 0, to: got[index].count, by: 4) {
                let coverage = ink?[index][texel + 3] ?? 255
                for channel in 0..<4 {
                    let a = Int(got[index][texel + channel])
                    switch coverage {
                    case 255: difference = max(difference, abs(a - Int(want[index][texel + channel])))
                    case 0: difference = max(difference, a)
                    default: break
                    }
                }
            }
            if difference > result.difference { result = (difference, frames[index]) }
        }
        return result
    }

    /// **Where the drawings beneath a flat colour are, at each frame** — the stack with the colour
    /// taken out (not baked), which holds no pixels of its own and so moves no coverage.
    private func ink(of row: Row, without position: Int) throws -> [[UInt8]] {
        let manager = build(row)
        manager.deleteLayer(at: position)
        return try scene(manager)
    }

    private func saveAndOpen(_ manager: CanvasManager, name: String) throws -> CanvasManager {
        let url = ProjectStore.createNewProjectURL(name: name)
        let finished = expectation(description: "save \(name)")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        return try XCTUnwrap(ProjectStore.load(from: url), "\(name): the saved document must open")
    }

    // MARK: - The harness

    /// What one bake did: refused, or baked with the layers it consumed (rewrote) and the one it
    /// removed, if any.
    private enum Done {
        case refused(String)
        case baked(consumed: Set<UUID>, removed: UUID?, leftovers: [CanvasManager.BakeLeftover])
    }

    /// **Every bakeable layer of every stack, baked from a fresh build — the four invariants above.**
    func testEveryBakeInEveryStackKeepsThePictureAndTouchesNothingElse() throws {
        var bakes = 0
        for row in Self.rows {
            for (position, spec) in row.stack.enumerated() where spec.bakes {
                let baked = try check(row, "baking \(spec.name)",
                                      insideInk: spec.isFlatColour ? try ink(of: row, without: position) : nil) {
                    let id = $0.layers[position].id
                    switch $0.bakeLayer(id: id) {
                    case .refused(let refusal): return .refused("\(refusal)")
                    case .baked(let plan):
                        return .baked(consumed: Set(plan.layers.map(\.layerID)), removed: id, leftovers: plan.leftovers)
                    }
                }
                if baked { bakes += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(bakes, 21, "The table must exercise every bake it lists, not refuse its way to green")
    }

    /// **Bake Animation on a drawing in a stack** — the cel's own motion turned into drawings, under and
    /// beside the other kinds — keeps the picture and touches no other layer.
    func testBakeAnimationInEveryStackKeepsThePictureAndTouchesNothingElse() throws {
        var bakes = 0
        for row in Self.rows {
            for (position, spec) in row.stack.enumerated() where spec.isAnimatedDrawing {
                let baked = try check(row, "Bake Animation on \(spec.name)") {
                    switch $0.bakePoseToCels(layerIndex: position, celIndex: 0) {
                    case .refused(let refusal): return .refused("\(refusal)")
                    case .baked: return .baked(consumed: [$0.layers[position].id], removed: nil, leftovers: [])
                    }
                }
                if baked { bakes += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(bakes, 2, "Every animated drawing in the table must bake")
    }

    /// The four invariants, for one bake of one stack. Returns whether it baked.
    private func check(_ row: Row, _ what: String, insideInk ink: [[UInt8]]? = nil,
                       bake: (CanvasManager) -> Done) throws -> Bool {
        let label = "\(row.name) — \(what)"
        let manager = build(row)
        let before = try scene(manager)
        let printsBefore = prints(manager, identity: true)
        let order = manager.layers.map(\.id)

        switch bake(manager) {
        case .refused(let refusal):
            XCTAssertEqual(prints(manager, identity: true), printsBefore, "\(label): refused (\(refusal)), and nothing moved")
            XCTAssertEqual(try scene(manager), before, "\(label): refused, and the picture is the same")
            return false
        case .baked(let consumed, let removed, let leftovers):
            XCTAssertTrue(leftovers.isEmpty, "\(label): nothing in these stacks is left behind, got \(leftovers)")
            let untouched = order.filter { $0 != removed && !consumed.contains($0) }

            // 1. The picture.
            let after = try scene(manager)
            let difference = worst(after, before, insideInk: ink)
            XCTAssertLessThanOrEqual(difference.difference, row.tolerance,
                                     "\(label): the picture changed by \(difference.difference) at frame \(difference.frame)")

            // 2. Nothing it did not consume.
            XCTAssertEqual(manager.layers.map(\.id), order.filter { $0 != removed },
                           "\(label): only the baker leaves, and the order is kept")
            let printsAfter = prints(manager, identity: true)
            for id in untouched {
                XCTAssertEqual(printsAfter[id], printsBefore[id],
                               "\(label): \(printsBefore[id]?.name ?? "?") was not consumed and must not change")
            }

            // 3. Through the file.
            let opened = try saveAndOpen(manager, name: label)
            let reopened = worst(try scene(opened), after)
            XCTAssertEqual(reopened.difference, 0, "\(label): saved and opened, frame \(reopened.frame) differs")
            let printsOpened = prints(opened, identity: false)
            let printsBaked = prints(manager, identity: false)
            for id in untouched {
                XCTAssertEqual(printsOpened[id], printsBaked[id], "\(label): \(printsBaked[id]?.name ?? "?") through the file")
            }

            // 4. One Undo.
            manager.undo()
            XCTAssertEqual(prints(manager, identity: true), printsBefore, "\(label): one Undo restores every layer")
            XCTAssertEqual(try scene(manager), before, "\(label): …and the picture")
            return true
        }
    }
}
