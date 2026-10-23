import CoreGraphics
import Foundation
import UIKit

/// Only the references needed by this active recipe segment cross to a held worker.
struct LiquifyRecipeSnapshot {
    let recipe: InterpolationRecipe
    let content: [CelRef: [VectorElement]]
    let guides: [GuideStroke]
    let options: InterpolationEvaluator.Options
    let size: CGSize
}

/// One immutable Liquify tick owns its geometry, complete picture and presentation lifecycle.
/// Mutation boundaries settle the same memoized producer used by the held picture.
final class LiquifyProcedure {
    let deformation: LiquifyDeformation
    let selectedIDs: Set<UUID>?
    let poses: [UUID: PoseMap]
    let pixelSnapshot: CelPixelSnapshot?
    let window: CGRect
    let recipeSnapshot: LiquifyRecipeSnapshot?
    let canvasSize: CGSize?
    let renderSource: VectorCanvas.Frozen?
    let placement: CelContentPlacement
    let pixelBridge: PoseMap?
    var backingWindow: CGRect? { pixelSnapshot?.replacementRect(in: window, through: pixelBridge) }
    private let lock = NSCondition()
    private var value: Resolved?
    private var presented = false
    private var rejected = false
    private var finish: ((Resolved) -> Void)?
    private var cancelled = false
    private var computations = 0
    private var resolving = false

    init(deformation: LiquifyDeformation, selectedIDs: Set<UUID>?, poses: [UUID: PoseMap],
         pixelSnapshot: CelPixelSnapshot? = nil, window: CGRect = .null,
         recipeSnapshot: LiquifyRecipeSnapshot? = nil, canvasSize: CGSize? = nil,
         renderSource: VectorCanvas.Frozen? = nil, placement: CelContentPlacement = .identity) {
        self.deformation = deformation
        self.selectedIDs = selectedIDs
        self.poses = poses
        self.pixelSnapshot = pixelSnapshot
        self.window = window
        self.recipeSnapshot = recipeSnapshot
        self.canvasSize = canvasSize
        self.renderSource = renderSource
        self.placement = placement
        let bridge = (placement.backing ?? .identity).concatenating(placement.ink?.inverse ?? .identity)
        self.pixelBridge = bridge.isIdentity ? nil : bridge
    }

    struct Resolved {
        let elements: [VectorElement]
        let shown: [VectorElement]
        let changed: Set<UUID>
        let pixels: CelPixelSnapshot.Patch?
        let computationFailed: Bool
        var failed: Bool { computationFailed || contentPicture?.hasFailed == true }
        let presentation: CelContentPicture.RenderedWindow?
        let contentPicture: CelContentPicture?
        let fieldIsEmpty: Bool
    }

    var hasFailed: Bool { locked { value }?.failed == true }
    var isPending: Bool { locked { finish != nil } }
    var isPresented: Bool { locked { presented } }
    var resolutionCount: Int { locked { computations } }
    var isResolving: Bool { locked { resolving } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    func resolve(_ original: [VectorElement]) -> [VectorElement] {
        resolved(original).elements
    }
    private func resolved(_ original: [VectorElement]) -> Resolved {
        lock.lock()
        while resolving { lock.wait() }
        if let value { lock.unlock(); return value }
        resolving = true
        computations += 1
        lock.unlock()
        var elements = original
        var pixels: CelPixelSnapshot.Patch?
        var fieldIsEmpty = true
        var failed = false
        var evaluatedInk: InterpolationEvaluator.Evaluation?
        if let snapshot = recipeSnapshot {
            let evaluation = InterpolationEvaluator.evaluate(recipe: snapshot.recipe, at: snapshot.recipe.t,
                content: { snapshot.content[$0] ?? [] }, subject: original, guides: snapshot.guides,
                options: snapshot.options, didApplyDeformation: { index, field in
                    guard index == snapshot.recipe.deformations.count - 1 else { return }
                    fieldIsEmpty = field.isEmpty
                    pixels = self.pixelSnapshot?.liquifiedPatch(in: self.window, using: field, through: self.pixelBridge)
                })
            evaluatedInk = evaluation
            if evaluation == nil { failed = true }
        } else {
            let field = LiquifyField(deformation)
            fieldIsEmpty = field.isEmpty
            elements = field.mapping(original, selectedIDs: selectedIDs, poses: poses)
            pixels = pixelSnapshot?.liquifiedPatch(in: window, using: field, through: pixelBridge)
        }
        failed = failed || (pixelSnapshot != nil && pixels == nil)
        let changed = Set(zip(original, elements).compactMap { old, new in
            old.hasSameSpatialInk(as: new) ? nil : old.id
        })
        let shown = shown(elements)
        var picture: CelContentPicture?
        var presentation: CelContentPicture.RenderedWindow?
        if !window.isNull, !window.isEmpty, let size = pixelSnapshot?.size ?? canvasSize {
            let ink: CelContentPicture.Ink?
            if let evaluatedInk { ink = .linked(evaluatedInk) }
            else if renderSource != nil || !shown.isEmpty {
                let source = renderSource ?? VectorCanvas(size: size).freeze(quality: .full)
                ink = .ordinary(source: source, elements: shown, rewriting: changed.union(poses.keys))
            } else { ink = nil }
            picture = CelContentPicture(size: size, window: window, backing: pixelSnapshot,
                                        patch: pixels, ink: ink)
            if !failed { presentation = picture?.rendered(placement: placement) }
            failed = failed || presentation == nil
        }
        let result = Resolved(elements: elements, shown: shown, changed: changed, pixels: pixels,
                              computationFailed: failed, presentation: presentation, contentPicture: picture, fieldIsEmpty: fieldIsEmpty)
        lock.lock()
        value = result
        resolving = false
        lock.broadcast()
        lock.unlock()
        return result
    }
    func picture(_ original: [VectorElement]) -> [VectorElement] { resolved(original).shown }
    func presentation(_ original: [VectorElement], placement: CelContentPlacement) -> CelContentPicture.RenderedWindow? {
        guard placement == self.placement else { return nil }
        let result = resolved(original)
        return result.failed ? nil : result.presentation
    }
    func contentPicture(_ original: [VectorElement]) -> CelContentPicture? {
        let result = resolved(original)
        return result.failed ? nil : result.contentPicture
    }
    func didPresent() {
        lock.lock()
        presented = true
        let result = value
        let callback = result == nil ? nil : finish
        if callback != nil { finish = nil }
        lock.unlock()
        if let result { callback?(result) }
    }

    /// A completed draw that failed validation is an outcome too, but never a shown picture.
    /// Called by the presenter's main-thread completion, not by the producer.
    func didReject() {
        guard hasFailed else { return }
        lock.lock()
        rejected = true
        let result = value
        let callback = result == nil ? nil : finish
        if callback != nil { finish = nil }
        lock.unlock()
        if let result { callback?(result) }
    }

    func finishWhenPresented(_ callback: @escaping (Resolved) -> Void) {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        let ready = (presented || rejected) ? value : nil
        if ready == nil { finish = callback }
        lock.unlock()
        if let ready { callback(ready) }
    }

    func settlePending(_ original: [VectorElement]) {
        lock.lock()
        let callback = finish
        finish = nil
        lock.unlock()
        if let callback { callback(resolved(original)) }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        finish = nil
    }
    func shown(_ resolved: [VectorElement]) -> [VectorElement] {
        CanvasManager.posed(resolved, by: poses)
    }
}
