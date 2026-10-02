import SwiftUI
import UIKit

// MARK: - Bake — TODO (131)
//
// > *"there is the option to merge down effects layers with the layer below them. This is an incomplete
// > implementation. Instead, replace that buttons function with baking: lets say you have 2 layers and a
// > blend mode value layer or effect layer above it. When that layer bakes, it should adjust the color of
// > all the strokes/objects etc affected below it. In this case, it is both the layers below. Add the same
// > feature for transform layers."* — owner.
//
// **Bake is the verb of a layer that holds no pixels.** An effect layer, a flat-colour value layer and a
// transformation layer all act on what is beneath them; merging one into the single layer below could
// only ever flatten *that one layer's* picture, so Bake carries the layer into **every drawing beneath
// it in its own group** instead and removes it, in one undo step. TODO.md's rulings:
//
// - A colour effect or a blend is taken into each element's colour (`BakeOperation`), and the drawing
//   stays a drawing. Pixels — a raster layer, or a vector layer under an effect that depends on position —
//   are graded exactly, through the compositor's own path.
// - An effect that needs pixels turns each affected vector layer into a raster layer, after a prompt.
// - Animation is baked one drawing per run of frames where the result changes — Bake Animation's rule
//   (`bakeSegments`) — and the prompt says how many and what every save then costs.
// - What cannot take it, or is only partly covered, is left as it was, the rest bakes, and a notice says so.
// - The paper stays white: Bake changes the drawings only.
//
// **The picture is not preserved, and that is the owner's ruling, not a shortfall.** The canvas grades the
// *composite*; a bake grades each drawing alone. Where drawings overlap or ink is soft at its edge the two
// differ, exactly as `CoreGraphicsCompositor.mergedDown`'s doc says of a merge. For opaque ink with
// nothing overlapping it, the baked document renders the picture the layer made.
//
// A transformation layer is carried the same way: its share of the pose is read off the render walk
// (`renderTreeAndPoses`) and written into each cel's geometry, so the walk stays the one source of what a
// transformation layer does.

extension CanvasManager {

    // MARK: - Asking for a bake

    /// A bake the layer panel is holding for confirmation. `LayerPanel` drives an `.alert` off it, for
    /// `pendingMergeConfirmation`'s reason: this pauses the bake until answered, which a banner cannot.
    struct PendingBake: Identifiable, Equatable {
        let id = UUID()
        let layerID: UUID
        let title: String
        let message: String
    }

    /// What `bakeLayer` did.
    enum BakeOutcome: Equatable {
        case baked(BakePlan)
        case refused(BakeRefusal)
    }

    /// **The one way a UI gesture asks for a bake** — the layer's Bake row, and the pinch on a layer that
    /// holds no pixels. A refusal is said out loud; a bake that changes what a layer *is* or what every
    /// save costs is held for the artist's yes; anything else just runs, and can be undone.
    func requestBake(layerID: UUID) {
        switch bakePlan(forLayerID: layerID) {
        case .refused(let refusal):
            raise(.bakeRefused(refusal))
        case .plan(let plan):
            if plan.needsConfirmation {
                pendingBake = PendingBake(layerID: layerID, title: "Bake \(plan.bakerName)?",
                                          message: plan.confirmationMessage)
            } else {
                bakeLayer(id: layerID)
            }
        }
    }

    /// Runs the bake a confirmed prompt named. Re-plans from the document as it stands, so a bake
    /// confirmed after another edit does what the document needs now rather than what it needed then.
    func confirmPendingBake() {
        guard let pending = pendingBake else { return }
        pendingBake = nil
        bakeLayer(id: pending.layerID)
    }

    func cancelPendingBake() {
        pendingBake = nil
    }

    // MARK: - Performing it

    /// **Bakes a layer into every drawing beneath it, and removes it** — one undo step, whatever it cut.
    ///
    /// The float settle comes first and the plan second, `bakePoseToCels`' order: a lifted lasso piece
    /// lands as its own earlier step, and the plan reads the whole drawing.
    ///
    /// **Fresh canvases, never edits in place** (`write`): `Cel.vector` is a class and the structure
    /// snapshot shares it, so rewriting a display list would leave the undo restoring a cel that still
    /// points at the baked ink. A new `VectorCanvas` per baked cel is what makes the one snapshot
    /// enough, and it gives every cache a new identity at the same time.
    @discardableResult
    func bakeLayer(id: UUID) -> BakeOutcome {
        commitAllInteractiveState()
        switch bakePlan(forLayerID: id) {
        case .refused(let refusal):
            raise(.bakeRefused(refusal))
            return .refused(refusal)
        case .plan(let plan):
            withStructureUndo(label: .bakeLayer) { perform(plan) }
            if !plan.leftovers.isEmpty { raise(.bakedWithLeftovers(plan.leftovers)) }
            return .baked(plan)
        }
    }

    private func perform(_ plan: BakePlan) {
        let memo = BakeColourMemo()
        for layerBake in plan.layers { bake(layerBake, memo: memo) }
        if let at = layers.firstIndex(where: { $0.id == plan.bakerID }) { deleteLayer(at: at) }
    }

    private func bake(_ layerBake: LayerBake, memo: BakeColourMemo) {
        guard let canvasSize, let at = layers.firstIndex(where: { $0.id == layerBake.layerID }) else { return }
        switch layerBake.medium {
        case .flatColour(let operation):
            guard let fill = layers[at].fill else { return }
            let baked = operation.baked(fill.color.color.codable)
            layers[at].fill = ValueFill(color: PaletteColor(color: baked.color))
        case .ink, .pixels:
            // The cels are addressed by id from here on, so nothing depends on the layer keeping its index.
            if layerBake.rasterizes { rasterizeLayer(layerIndex: at) }
            for cel in layerBake.cels {
                bakeCel(layerID: layerBake.layerID, celID: cel.celID, segments: cel.segments,
                        canvasSize: canvasSize, memo: memo)
            }
        }
    }

    /// **Cuts a cel into the runs `segments` names and writes each one's treatment** — the body Bake
    /// and Bake Animation share. Cut left to right at each boundary, every nested `withStructureUndo`
    /// a no-op inside the step that is already open; then each run is addressed by the frame it starts
    /// on, which is stable across the cuts where an index is not.
    ///
    /// The segments were resolved on the uncut cel (`bakeSegments`), and **the order is load-bearing**:
    /// §3.1 says a split re-parameterises a bezier on both sides, so re-reading a half after cutting
    /// would bake frames the artist never saw.
    func bakeCel(layerID: UUID, celID: UUID, segments: [BakeSegment<BakeTreatment?>],
                 canvasSize: CGSize, memo: BakeColourMemo = BakeColourMemo()) {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return }
        let startFrame = layers[at.layer].cels[at.cel].startFrame
        for segment in segments.dropFirst() {
            let cut = startFrame + segment.localStart
            guard let idx = activeCelIndex(inLayer: at.layer, atFrame: cut - 1) else { continue }
            splitCel(layerIndex: at.layer, celIndex: idx, atFrame: cut)
        }
        for segment in segments {
            guard let treatment = segment.treatment,
                  let idx = activeCelIndex(inLayer: at.layer, atFrame: startFrame + segment.localStart)
            else { continue }
            write(treatment, layerID: layerID, celID: layers[at.layer].cels[idx].id,
                  canvasSize: canvasSize, memo: memo)
        }
    }

    /// **One run's drawing rewritten.** A vector cel gets a brand-new display list (`bakeLayer` says why);
    /// a raster cel gets a new texture, exactly as `bakeCelPair` writes a merge.
    ///
    /// A pose is **consumed** where it is carried into the geometry: the cel's own channels and held
    /// baselines go with the motion, because a live rig under drawings the artist is about to edit would
    /// be a lie (KEYFRAMES.md §2.9). An effect leaves them alone.
    private func write(_ treatment: BakeTreatment, layerID: UUID, celID: UUID,
                       canvasSize: CGSize, memo: BakeColourMemo) {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return }
        let cel = layers[at.layer].cels[at.cel]
        if layers[at.layer].kind == .vector {
            guard let vector = cel.vector else { return }
            let elements: [VectorElement]
            switch treatment {
            case .operation(let operation):
                let colours = memo.colours(for: operation)
                elements = vector.elements.map { operation.baked($0, using: colours).element ?? $0 }
            case .pose(let run):
                elements = Self.baked(vector.elements, through: run.mappings, inheriting: run.inherited)
                layers[at.layer].cels[at.cel].transformTracks = [:]
                layers[at.layer].cels[at.cel].pendingPoseBaselines = [:]
            }
            layers[at.layer].cels[at.cel].vector =
                VectorCanvas(size: vector.size, elements: elements, transform: vector.transform)
        } else {
            guard !cel.isCertainlyBlank else { return }
            let image: UIImage
            switch treatment {
            case .operation(let operation):
                image = operation.baked(PixelOps.rasterize(cel: cel, canvasSize: canvasSize))
            case .pose(let run):
                image = PixelOps.rasterize(cel: cel, canvasSize: canvasSize, pose: run.inherited)
            }
            layers[at.layer].cels[at.cel].raster = bakedRasterTexture(image: image, likeExisting: cel.raster)
            layers[at.layer].cels[at.cel].fillPreview = nil
            layers[at.layer].cels[at.cel].bakedImage = nil
        }
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)
    }

    // MARK: - Planning it

    /// **What baking this layer would do, read off the document and written nowhere** — the same plan the
    /// confirmation words and `bakeLayer` performs.
    func bakePlan(forLayerID id: UUID) -> BakePlanResult {
        guard let bakerIndex = layers.firstIndex(where: { $0.id == id }),
              layers[bakerIndex].kind.bakesIntoLayersBelow else { return .refused(.notABakingLayer) }
        guard isLayerEffectivelyVisible(bakerIndex) else { return .refused(.hidden) }
        let container = resolvedContainer(ofLayer: bakerIndex)
        // Inside a combiner the entry one step down is the *other operand*, which a layer never acts on
        // (`RenderTree.renderNodes`), so there is nothing beneath it to bake into.
        if let container, folders.first(where: { $0.id == container })?.isCompositorNode == true {
            return .refused(.insideACombiner)
        }
        let scope = bakeScope(ofLayerAt: bakerIndex)
        guard !scope.isEmpty else { return .refused(.nothingBeneath) }

        let baker = layers[bakerIndex]
        var plan = BakePlan(bakerID: baker.id, bakerName: baker.name, layers: [], leftovers: [])
        switch baker.kind {
        case .value:
            // A clip or a mask makes the layer reach only part of each drawing, and no colour stands for
            // part of a drawing: refused, with the layer kept, rather than baked into nothing.
            guard !baker.isClipped else { return .refused(.partialCoverage) }
            planOperation(of: bakerIndex, over: scope, into: &plan)
        case .transform:
            guard baker.layerTransform?.repeats != true else { return .refused(.repeatsInTime) }
            planPose(of: bakerIndex, over: scope, into: &plan)
        case .raster, .vector:
            return .refused(.notABakingLayer)
        }
        guard !plan.layers.isEmpty else { return .refused(.nothingToBake(plan.leftovers)) }
        return .plan(plan)
    }

    /// **What each of `bakerIndex`'s frames does to the drawings beneath it** — a grade, or a colour
    /// blended in, resolved at the frame exactly as `RenderTree.renderNodes` resolves them (the eye, the
    /// bar, the keyed parameters and opacity), and nil where the layer does nothing.
    func bakeOperation(ofLayerAt index: Int, atFrame frame: Int) -> BakeOperation? {
        let layer = layers[index]
        guard layer.isVisible, activeCelIndex(inLayer: index, atFrame: frame) != nil else { return nil }
        let opacity = layer.opacity(atFrame: frame)
        if let effect = layer.layerEffect(atFrame: frame) { return .grade(effect, opacity: opacity) }
        if let fill = layer.valueFill {
            return .blend(LayerRenderSource.SolidColor(fill.resolvedColor(atFrame: frame)),
                          mode: layer.blendMode.compositedMode, opacity: opacity)
        }
        return nil
    }

    /// An effect layer or a flat colour, carried into every drawing in `scope`.
    private func planOperation(of bakerIndex: Int, over scope: [BakeScoped], into plan: inout BakePlan) {
        let operationAt = { (frame: Int) in self.bakeOperation(ofLayerAt: bakerIndex, atFrame: frame) }
        for (index, shadow) in scope {
            let layer = layers[index]
            // Only a layer with a drawing takes an effect. A pose layer has none, and a layer that grades
            // is not ink: its own grade still applies to what is below it, which `BakeShadow` records.
            switch layer.kind {
            case .transform: continue
            case .raster: break
            case .vector, .value: if layer.layerEffect != nil { continue }
            }
            if let reason = shadow.reason ?? (layer.isClipped ? .masked : nil) {
                plan.leftovers.append(BakeLeftover(name: layer.name, reason: reason))
                continue
            }

            if layer.kind == .value {
                planFlatColour(layer, operationAt: operationAt, into: &plan)
                continue
            }

            var celBakes: [CelBake] = []
            var route: Effect.BakeRoute?
            for cel in layer.cels {
                let segments = Self.bakeSegments(frameCount: cel.frameCount) { local in
                    operationAt(cel.startFrame + local).map(BakeTreatment.operation)
                }
                guard let treated = segments.first(where: { $0.treatment != nil }),
                      case .operation(let operation)? = treated.treatment else { continue }
                celBakes.append(CelBake(celID: cel.id, segments: segments))
                route = route ?? operation.route
            }
            // The baking layer's bar never reaches this layer's frames: nothing to do, nothing to say.
            guard !celBakes.isEmpty, let route else { continue }

            let medium: LayerBake.Medium
            if layer.kind == .raster {
                medium = .pixels(rasterizes: false)
            } else {
                let holdsMovie = layer.cels.contains { $0.vector?.holdsVideo == true || $0.vector?.holdsStream == true }
                let holdsOnlyInk = layer.cels.allSatisfy(holdsOnlyVectorInk)
                if route == .colour && holdsOnlyInk {
                    // The rest of the layer bakes; the movie stays as it was.
                    if holdsMovie { plan.leftovers.append(BakeLeftover(name: layer.name, reason: .cannotTakeColour)) }
                    medium = .ink
                } else if holdsMovie {
                    // Turning the layer into pixels would flatten the movie to one still frame.
                    plan.leftovers.append(BakeLeftover(name: layer.name, reason: .cannotTakeColour))
                    continue
                } else if layer.cels.contains(where: { !$0.transformTracks.isEmpty }) {
                    // …and a pose channel to the frame the cel starts on.
                    plan.leftovers.append(BakeLeftover(name: layer.name, reason: .animatedDrawing))
                    continue
                } else {
                    medium = .pixels(rasterizes: true)
                }
            }
            plan.layers.append(LayerBake(layerID: layer.id, name: layer.name, medium: medium, cels: celBakes))
        }
    }

    /// A flat-colour value layer beneath: its own colour is the "drawing", and it has no frames of its
    /// own to cut, so it takes the bake only if the baking layer covers all of it the same way.
    private func planFlatColour(_ layer: Layer, operationAt: (Int) -> BakeOperation?, into plan: inout BakePlan) {
        let operations = layer.cels.flatMap { ($0.startFrame..<$0.endFrame).map(operationAt) }
        guard operations.contains(where: { $0 != nil }) else { return }
        guard let first = operations.first, let operation = first,
              operations.allSatisfy({ $0 == operation }) else {
            plan.leftovers.append(BakeLeftover(name: layer.name, reason: .partlyCovered))
            return
        }
        guard operation.route == .colour else {
            plan.leftovers.append(BakeLeftover(name: layer.name, reason: .flatColourNeedsAColourEffect))
            return
        }
        plan.layers.append(LayerBake(layerID: layer.id, name: layer.name, medium: .flatColour(operation), cels: []))
    }

    /// **A transformation layer, carried into the geometry of every drawing in `scope`.**
    ///
    /// Its share of the pose is read off the render walk — the walk with the layer, against the walk
    /// without it — so the one source of what a transformation layer does stays the walk, and what the
    /// other layers still do is untouched. A cel at frame *f* is shown through `with[f]`; with the layer
    /// gone it will be shown through `without[f]`, so the geometry has to carry
    /// `with[f] · without[f]⁻¹` — which is the layer's own map exactly when nothing else poses the cel
    /// (no inversion happens then), and the layer's map conjugated by the layers nearer the cel when
    /// something does. The cel's own channels are carried in the same step and consumed.
    private func planPose(of bakerIndex: Int, over scope: [BakeScoped], into plan: inout BakePlan) {
        let bakerID = layers[bakerIndex].id
        var walks: [Int: (with: [Int: PoseMap], without: [Int: PoseMap])] = [:]
        func poses(atFrame frame: Int) -> (with: [Int: PoseMap], without: [Int: PoseMap]) {
            if let known = walks[frame] { return known }
            let both = (renderTreeAndPoses(atFrame: frame).poses,
                        renderTreeAndPoses(atFrame: frame, excluding: bakerID).poses)
            walks[frame] = both
            return both
        }

        for (index, shadow) in scope {
            let layer = layers[index]
            switch layer.kind {
            case .value, .transform: continue          // no geometry for a pose to move
            case .raster, .vector: break
            }
            // A Repeat between the two reads this layer at another frame than the baking layer reads
            // itself, so a cel would be shown through different poses at different frames.
            if let name = shadow.repeated {
                plan.leftovers.append(BakeLeftover(name: layer.name, reason: .underARepeat(name)))
                continue
            }

            var celBakes: [CelBake] = []
            var leftover: BakeLeftover.Reason?
            for cel in layer.cels {
                let segments = Self.bakeSegments(frameCount: cel.frameCount) { local -> BakeTreatment? in
                    let frame = cel.startFrame + local
                    guard activeCelIndex(inLayer: bakerIndex, atFrame: frame) != nil else { return nil }
                    let pair = poses(atFrame: frame)
                    let with = pair.with[index], without = pair.without[index]
                    var share = with
                    if with != without {
                        if let without {
                            guard let inverse = without.inverse else { leftover = .cannotBeCarried; return nil }
                            share = (with ?? .identity).concatenating(inverse)
                        }
                    } else {
                        share = nil
                    }
                    // Only where the layer actually moves the drawing: a frame at rest leaves the cel's
                    // own animation alone.
                    guard let share, !share.isIdentity else { return nil }
                    if cel.interpolation != nil { leftover = .inBetween; return nil }
                    let mappings = layer.kind == .vector
                        ? Self.poseMappings(cel.transformTracks, atCelLocalFrame: local) : []
                    return .pose(PoseRun(mappings: mappings, inherited: share))
                }
                guard segments.contains(where: { $0.treatment != nil }) else { continue }
                celBakes.append(CelBake(celID: cel.id, segments: segments))
            }
            if let leftover { plan.leftovers.append(BakeLeftover(name: layer.name, reason: leftover)) }
            guard !celBakes.isEmpty else { continue }
            plan.layers.append(LayerBake(layerID: layer.id, name: layer.name,
                                         medium: layer.kind == .vector ? .ink : .pixels(rasterizes: false),
                                         cels: celBakes))
        }
    }

    // MARK: - Scope

    /// What lies between the baking layer and a layer beneath it that changes whether a bake into that
    /// layer's own colours can be right.
    fileprivate struct BakeShadow {
        var node: String?
        var masked: String?
        var graded: String?
        var repeated: String?

        /// Why a drawing under this shadow cannot take an effect baked into its colours, in the order
        /// the artist can best act on it.
        var reason: BakeLeftover.Reason? {
            if let node { return .insideACombiner(node) }
            if masked != nil { return .masked }
            if let graded { return .underAnotherEffect(graded) }
            return nil
        }
    }

    fileprivate typealias BakeScoped = (index: Int, shadow: BakeShadow)

    /// **Every layer beneath the baking layer in its own group**, at any depth of folder, each with the
    /// shadow it sits in — the adjustment layer's own scope rule (§4.4), which a transformation layer
    /// shares: *whatever is under it, within its container*. Hidden layers are in it: they would take
    /// the effect the moment they were shown.
    ///
    /// A layer that grades the layers under it, or a Repeat layer, casts its shadow on the entries after
    /// it **in its own container only**; a folder casts what *it* carries — a grade of its own, a mask, a
    /// combiner — on its contents alone.
    fileprivate func bakeScope(ofLayerAt bakerIndex: Int) -> [BakeScoped] {
        let entries = containerEntries(inContainer: resolvedContainer(ofLayer: bakerIndex))
        guard let position = entries.firstIndex(where: {
            if case .layer(let index) = $0 { return index == bakerIndex }
            return false
        }) else { return [] }
        var scoped: [BakeScoped] = []
        collectBakeScope(Array(entries[(position + 1)...]), shadow: BakeShadow(), into: &scoped)
        return scoped
    }

    private func collectBakeScope(_ entries: [ContainerEntry], shadow: BakeShadow, into scoped: inout [BakeScoped]) {
        var shadow = shadow
        for entry in entries {
            switch entry {
            case .layer(let index):
                scoped.append((index, shadow))
                let layer = layers[index]
                if layer.layerEffect != nil, shadow.graded == nil { shadow.graded = layer.name }
                if layer.isVisible, layer.layerTransform?.repeats == true, shadow.repeated == nil {
                    shadow.repeated = layer.name
                }
            case .folder(let folder):
                var inner = shadow
                if folder.isCompositorNode, inner.node == nil { inner.node = folder.name }
                if folder.alphaMask?.isActive == true, inner.masked == nil { inner.masked = folder.name }
                if folder.effect != nil, inner.graded == nil { inner.graded = folder.name }
                collectBakeScope(containerEntries(inContainer: folder.id), shadow: inner, into: &scoped)
            }
        }
    }
}

// MARK: - Helpers

private extension Layer {
    /// Whether the layer shows only part of itself — a mask, or a clip to the layer below — which an
    /// effect baked into its colours cannot follow.
    var isClipped: Bool { alphaMask?.isActive == true || blendMode == .clipToBelow }
}

/// The colour maps a bake has built, one per distinct operation — a bake that runs one grade across a
/// hundred cels asks the same question of the same few colours a hundred times.
final class BakeColourMemo {
    private var entries: [(operation: BakeOperation, colours: BakedColours)] = []

    func colours(for operation: BakeOperation) -> BakedColours {
        if let known = entries.first(where: { $0.operation == operation }) { return known.colours }
        let made = BakedColours(operation)
        entries.append((operation, made))
        return made
    }
}
