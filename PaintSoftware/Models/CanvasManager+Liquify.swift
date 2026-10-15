import CoreGraphics
import UIKit

/// One brush displacement gesture. The immutable starting display list/recipe is kept separately
/// from the held definition, so every preview and the final commit start from the same ink.
struct LiquifySession {
    let layerID: UUID
    let celID: UUID
    let vector: VectorCanvas?
    let sourceVersion: Int
    let elementsBefore: [VectorElement]
    let recipeBefore: InterpolationRecipe?
    let rewriting: Set<UUID>
    let selectedIDs: Set<UUID>?
    let poses: [UUID: PoseMap]
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
    func beginLiquify(layerID: UUID, profile: ToolProfile, size: CGFloat, seed: UInt64) -> LiquifySession? {
        beginCanvasEdit()
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
        let base = inkPose(forLayerID: layerID) ?? .identity
        let poses = celPoseMaps(elements, layerID: layerID, celID: cel.id, atFrame: currentFrame)
            .mapValues { pose in pose.concatenating(base.inverse ?? .identity) }
            .filter { !$0.value.isIdentity }
        if let recipe = cel.interpolation {
            gesture.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe, content: interpolationContentProvider, subject: elements, guides: guideStrokes)
        }
        return LiquifySession(layerID: layerID, celID: cel.id, vector: cel.vector,
                              sourceVersion: cel.vector?.version ?? 0,
                              elementsBefore: elements, recipeBefore: cel.interpolation,
                              rewriting: Set(ink.map(\.id)), selectedIDs: selected, poses: poses, gesture: gesture)
    }

    func holdLiquify(_ session: inout LiquifySession) {
        guard !session.window.isNull else { return }
        session.gesture.path = PackedSampleRun(session.samples, about: session.samples.positions.first ?? .zero, precise: true)
        session.tick += 1
        if var recipe = session.recipeBefore {
            recipe.deformations.append(session.gesture)
            let held = HeldEdit.interpolation(HeldInterpolation(drag: .liquify, layerID: session.layerID,
                                                               celID: session.celID, recipe: recipe, guide: nil))
            if liveEdit == nil { beginLiveEdit(held) }
            holdLiveEdit(held)
        } else if let vector = session.vector {
            if let existing = liveElementEdit, existing.window == session.window,
               existing.procedure?.deformation == session.gesture { return }
            let held = HeldEdit.elements(LiveElementEdit(layerID: session.layerID, celID: session.celID,
                vectorCanvas: vector, window: session.window, rewriting: session.rewriting,
                elements: session.elementsBefore, tick: session.tick,
                procedure: ElementEditProcedure(deformation: session.gesture, selectedIDs: session.selectedIDs,
                                                poses: session.poses, sourceVersion: session.sourceVersion)))
            if liveEdit == nil { beginLiveEdit(held) }
            holdLiveEdit(held)
        }
    }

    func commitLiquify(_ session: LiquifySession) {
        guard let layer = layers.firstIndex(where: { $0.id == session.layerID }),
              let cel = layers[layer].cels.firstIndex(where: { $0.id == session.celID }) else {
            endLiveEdit(); return
        }
        if var recipe = session.recipeBefore {
            guard !LiquifyField(session.gesture).isEmpty else { endLiveEdit(); return }
            recipe.deformations.append(session.gesture)
            withInterpolationUndo(label: .liquify) { layers[layer].cels[cel].interpolation = recipe }
            endLiveEdit()
        } else if let vector = session.vector {
            guard let held = liveElementEdit, let procedure = held.procedure,
                  procedure.deformation == session.gesture else { endLiveEdit(); return }
            procedure.finishWhenPresented { [weak self] resolved in
                guard let self else { return }
                guard vector.version == procedure.sourceVersion, !resolved.changed.isEmpty else {
                    self.endLiveEdit(); return
                }
                let edit = ElementEditSession(layerID: session.layerID, celID: session.celID, vectorCanvas: vector,
                    elementsBefore: session.elementsBefore, rewriting: resolved.changed, held: resolved.elements)
                self.recordElementEdit(edit, finalElements: resolved.elements, label: .liquify)
            }
            // Headless callers have no surface to land. An artist's normal lift waits for the
            // existing window queue; only an explicit subsequent mutation settles it synchronously.
            if onHeldPictureMoved == nil { settlePendingElementProcedure() }
        }
    }
}
