import CoreGraphics
import UIKit

/// One brush displacement gesture. The immutable starting display list/recipe is kept separately
/// from the held definition, so every preview and the final commit start from the same ink.
struct LiquifySession {
    let layerID: UUID
    let celID: UUID
    let vector: VectorCanvas?
    let renderSource: VectorCanvas.Frozen?
    let sourceIdentity: CelContentIdentity
    let oldRaster: RasterLayerTexture
    let oldBaked: RasterSource?
    let pixelSnapshot: CelPixelSnapshot?
    let recipeSnapshot: LiquifyRecipeSnapshot?
    let elementsBefore: [VectorElement]
    let recipeBefore: InterpolationRecipe?
    let rewriting: Set<UUID>
    let selectedIDs: Set<UUID>?
    let poses: [UUID: PoseMap]
    let placement: CelContentPlacement
    var gesture: LiquifyDeformation
    var samples = StrokeSamples(channels: .captured)
    var window: CGRect = .null
    var tick = 0
    mutating func includeBrushFootprints(_ dabs: [(BrushStamper.BakedDab, CGPoint)], canvasSize: CGSize) {
        for (dab, _) in dabs {
            let extent = LiquifyField.replacementBounds(of: dab)
            window = window.isNull ? extent : window.union(extent)
        }
        if !window.isNull { window = window.intersection(CGRect(origin: .zero, size: canvasSize)) }
    }

}

extension CanvasManager {
    @discardableResult
    func settlePendingLiquifyProcedure() -> Bool {
        guard let edit = liveCelContentEdit, let procedure = edit.procedure else { return true }
        return procedure.settlePending(edit.elements)
    }

    func beginLiquify(layerID: UUID, profile: ToolProfile, size: CGFloat, seed: UInt64) -> LiquifySession? {
        guard beginCanvasEdit() else { return nil }
        guard let layer = layers.firstIndex(where: { $0.id == layerID }),
              let index = displayedCelIndex(inLayer: layer, atFrame: currentFrame),
              layers[layer].kind.holdsPixels else { return nil }
        let cel = layers[layer].cels[index]
        let selected = selection?.objects.flatMap {
            $0.layerID == layerID && $0.celID == cel.id ? $0.elements : nil
        }
        let elements = cel.vector?.elements ?? []
        let ink = elements.filter {
            guard selected?.contains($0.id) ?? true else { return false }
            switch $0 { case .stroke, .fill: return true; case .image, .video, .stream, .text: return false }
        }
        let constraint = selection.flatMap { selection -> CGPath? in
            guard selection.acts(onLayer: layerID, cel: cel.id), selection.isRegion else { return nil }
            return Self.layerSpacePath(selection.path, shownThrough: inkPose(forLayerID: layerID))
        }
        var gesture = LiquifyDeformation(brush: profile.preset, size: size, power: profile.opacity,
                                        mode: liquifyMode, seed: seed, samples: StrokeSamples(channels: .captured), selection: constraint)
        let placement = celContentPlacement(forLayerID: layerID)
        let base = placement.ink ?? .identity
        let poses = celPoseMaps(elements, layerID: layerID, celID: cel.id, atFrame: currentFrame)
            .mapValues { pose in pose.concatenating(base.inverse ?? .identity) }
            .filter { !$0.value.isIdentity }
        if let recipe = cel.interpolation {
            gesture.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe, content: interpolationContentProvider, subject: elements, guides: guideStrokes)
        }
        let pixelSnapshot = CelPixelSnapshot(cel: cel)
        var recipeSnapshot: LiquifyRecipeSnapshot?
        if let recipe = cel.interpolation, recipe.references.count >= 2 {
            let span = CGFloat(recipe.references.count - 1)
            let segment = min(max(Int((recipe.spacing.eased(recipe.t) * span).rounded(.down)), 0), recipe.references.count - 2)
            var content: [CelRef: [VectorElement]] = [:]
            for reference in recipe.references[segment...segment + 1] {
                for ref in reference.cels { content[ref] = interpolationContentProvider(ref) }
            }
            recipeSnapshot = LiquifyRecipeSnapshot(recipe: recipe, content: content,
                guides: guides(driving: recipe), options: interpolationOptions)
        }
        return LiquifySession(layerID: layerID, celID: cel.id, vector: cel.vector,
                              renderSource: cel.vector?.freeze(quality: .full),
                              sourceIdentity: CelContentIdentity(cel),
                              oldRaster: cel.raster, oldBaked: cel.bakedImage,
                              pixelSnapshot: pixelSnapshot, recipeSnapshot: recipeSnapshot,
                              elementsBefore: elements, recipeBefore: cel.interpolation,
                              rewriting: Set(ink.map(\.id)), selectedIDs: selected, poses: poses, placement: placement, gesture: gesture)
    }

    func holdLiquify(_ session: inout LiquifySession) {
        guard !session.window.isNull else { return }
        session.gesture.path = PackedSampleRun(session.samples, about: session.samples.positions.first ?? .zero, precise: true)
        session.tick += 1
        if let existing = liveCelContentEdit, existing.window == session.window,
           existing.procedure?.deformation == session.gesture { return }
        var recipeSnapshot = session.recipeSnapshot
        if let old = recipeSnapshot {
            var recipe = old.recipe
            recipe.deformations.append(session.gesture)
            recipeSnapshot = LiquifyRecipeSnapshot(recipe: recipe, content: old.content, guides: old.guides,
                                                  options: old.options)
        }
        let held = HeldEdit.celContent(LiveCelContentEdit(layerID: session.layerID, celID: session.celID,
            vectorCanvas: session.vector, pixelSnapshot: session.pixelSnapshot,
            window: session.window, rewriting: session.rewriting, elements: session.elementsBefore,
            tick: session.tick, procedure: LiquifyProcedure(deformation: session.gesture,
                selectedIDs: session.selectedIDs, poses: session.poses,
                pixelSnapshot: session.pixelSnapshot, window: session.window, recipeSnapshot: recipeSnapshot,
                canvasSize: session.oldRaster.size, renderSource: session.renderSource, placement: session.placement)))
        if liveEdit == nil { beginLiveEdit(held) }
        holdLiveEdit(held)
        guard onHeldPictureMoved != nil, let edit = held.celContent, let procedure = edit.procedure else { return }
        MainActor.assumeIsolated {
            liquifyPictures.request { [weak self] in
                guard self?.liveCelContentEdit?.procedure === procedure else { return nil }
                return {
                    _ = procedure.resolve(edit.elements)
                    return { [weak self] in
                        guard self?.liveCelContentEdit?.procedure === procedure else { return }
                        if procedure.hasFailed { procedure.didReject() }
                        else { self?.onHeldPictureMoved?() }
                    }
                }
            }
        }
    }

    func commitLiquify(_ session: LiquifySession) {
        guard layers.contains(where: { $0.id == session.layerID && $0.cels.contains(where: { $0.id == session.celID }) }) else {
            endLiveEdit(); return
        }
        guard let held = liveCelContentEdit, let procedure = held.procedure,
              procedure.deformation == session.gesture else { endLiveEdit(); return }
        procedure.finishWhenPresented { [weak self, weak procedure] resolved, staging in
            guard let self, let procedure,
                  self.liveCelContentEdit?.procedure === procedure,
                  let layer = self.layers.firstIndex(where: { $0.id == session.layerID }),
                  let index = self.layers[layer].cels.firstIndex(where: { $0.id == session.celID }) else { return nil }
            let current = self.layers[layer].cels[index]
            guard CelContentIdentity(current) == session.sourceIdentity else {
                return { [weak self] in
                    if self?.liveCelContentEdit?.procedure === procedure { self?.endLiveEdit() }
                }
            }
            guard !resolved.failed else {
                return { [weak self] in
                    guard self?.liveCelContentEdit?.procedure === procedure else { return }
                    self?.raise(.drawingSourceUnavailable)
                    self?.endLiveEdit()
                }
            }
            let pixelsChanged = resolved.pixels?.changed == true
            let recipeChanged = session.recipeBefore != nil && !resolved.fieldIsEmpty
            guard pixelsChanged || !resolved.changed.isEmpty || recipeChanged else {
                return { [weak self] in
                    if self?.liveCelContentEdit?.procedure === procedure { self?.endLiveEdit() }
                }
            }
            var cel = staging[session.celID] ?? current
            var raster = cel.raster
            var baked = cel.bakedImage
            if pixelsChanged, let snapshot = session.pixelSnapshot, let patch = resolved.pixels {
                guard let source = snapshot.committing(patch) else {
                    self.raise(.drawingSourceUnavailable); return nil
                }
                if session.vector != nil {
                    raster = RasterLayerTexture(size: session.oldRaster.size, residency: session.oldRaster.residency)
                    baked = source
                } else {
                    raster = RasterLayerTexture(size: session.oldRaster.size, source: source,
                        strokeCount: max(session.oldRaster.strokeCount, 1))
                    baked = nil
                }
            }
            let vector = session.vector.flatMap { canvas -> CelVectorChange? in
                guard !resolved.changed.isEmpty else { return nil }
                return CelVectorChange(canvas: canvas, before: session.elementsBefore,
                                       after: resolved.elements, rewriting: resolved.changed)
            }
            let recipe = session.recipeBefore.flatMap { before in
                procedure.recipeSnapshot.map { CelRecipeChange(before: before, after: $0.recipe) }
            }
            cel.raster = raster
            cel.bakedImage = baked
            if let vector {
                let prepared = vector.canvas.makeCopy()
                prepared.restoreElements(vector.after, changedInk: nil, rewriting: vector.rewriting)
                cel.vector = prepared
            }
            if let recipe { cel.interpolation = recipe.after }
            staging[session.celID] = cel
            return { [weak self] in
                guard let self,
                      self.liveCelContentEdit?.procedure === procedure,
                      let layer = self.layers.firstIndex(where: { $0.id == session.layerID }),
                      let at = self.layers[layer].cels.firstIndex(where: { $0.id == session.celID }),
                      CelContentIdentity(self.layers[layer].cels[at]) == session.sourceIdentity else { return }
                self.registerUndoableCelChange(layerID: session.layerID, celID: session.celID,
                    oldRaster: session.oldRaster, oldBaked: session.oldBaked, newRaster: raster, newBaked: baked,
                    vector: vector, recipe: recipe, label: .liquify)
                self.endLiveEdit()
            }
        }
        // Normal lift waits for the matching picture. Explicit mutation boundaries and headless
        // callers settle this same producer before their own document write.
        if onHeldPictureMoved == nil { settlePendingLiquifyProcedure() }
    }
}
