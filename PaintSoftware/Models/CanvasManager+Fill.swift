import Combine   // objectWillChange.send()
import SwiftUI
import UIKit

// MARK: - Fill (interactive: press to apply, drag to adjust gap-closing / edge-overlap)
//
// The interactive bucket fill: compositing the fill-reference layers, driving the GPU
// `MetalFillSession` on its own queue, the coalesced preview render loop, and committing or
// cancelling the result. Extracted from CanvasManager.swift as an extension — all state still lives
// on the class itself (see that file's header), so the gesture's stored properties and the
// `@Published` fill parameters the sliders bind to stay declared over there.
//
// This subsystem was the candidate for promotion to a real `InteractiveFillService` owned by
// CanvasManager, and it was measured for that rather than assumed. The machinery *is* private —
// nothing outside CanvasManager's own files names `fillQueue`, `fillLock`, `fillSession`, `FillKey`
// or any of the gesture fields. But the operations are not separable from the document: this file
// touches `layers` 29 times (10 of them writes into the `@Published` array, including the vector
// materialisation in `commitInteractiveFill`), plus `selection`, `currentFrame`,
// `currentLayerIndex`, `canvasSize` and `allowsPaintingOutsideSelection`, and it calls back into
// `beginCanvasEdit`, `recordUndo`, `registerUndoableCelChange`, `bakedRasterTexture`,
// `celContentChangedOutsideStroke`, `refreshUndoRedoState`, `scheduleThumbnailRegen`,
// `activeCelIndex`, `refreshDisplay` and `objectWillChange`.
//
// A service object would therefore hold a back-reference to CanvasManager and route all of that
// through it — mutating the `@Published` array from inside a child object, which is exactly the
// republishing failure mode sessions 47, 49 and 50 were spent fixing. The boundary is not clean, so
// it stays an extension.

extension CanvasManager {

    /// The three quantized fill parameters, coalesced across a burst of touch-moves.
    ///
    /// Not `private`: `fillPending`/`fillRendered` in CanvasManager.swift are typed with it, and
    /// Swift scopes `private` to the file rather than the type.
    struct FillKey: Equatable { var gap: Int; var threshold: Int; var edge: Int }

    /// Begins an interactive fill at `point` (canvas-pixel coords, top-left origin): composites every
    /// fill-reference layer into a reference image once, uploads it to a GPU `MetalFillSession`, samples
    /// the tapped colour, and paints an initial fill. A plain tap is just this immediately followed by
    /// `endInteractiveFill`; a press-and-drag streams `updateInteractiveFill` calls in between. The fill
    /// preview lives in `fillImage` until `commitInteractiveFill` bakes it into the layer proper.
    func beginInteractiveFill(at point: CGPoint) {
        guard !fillFingerDown else { return }
        // A fill is a canvas edit like any other: an earlier adjustable fill (or a pending shape)
        // bakes first, so this fill reads it as a real boundary/recolour target instead of flooding
        // against content that is about to change.
        beginCanvasEdit()
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        // Filling a frame with no block spawns one, exactly as a brush stroke there does — the two
        // are the same instruction ("put content on this frame") and it would be arbitrary for one
        // to work and the other to sit inert. See `ensureCelAtCurrentFrame`.
        guard let celIndex = ensureCelAtCurrentFrame(layerIndex: layerIndex) else { return }

        let references = fillReferenceSources()
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        let seedX = min(max(Int(point.x.rounded(.down)), 0), width - 1)
        let seedY = min(max(Int(point.y.rounded(.down)), 0), height - 1)

        fillGestureActive = true
        fillFingerDown = true
        fillLastRegionRGBA = nil
        fillGestureSeed = (seedX, seedY)
        fillGestureColor = Self.premultipliedComponents(brushColor.resolvedUIColor(opacity: brushOpacity))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        fillGestureFillColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        fillGestureLayerID = layers[layerIndex].id
        fillGestureCelID = layers[layerIndex].cels[celIndex].id
        fillGestureBaseBaked = layers[layerIndex].cels[celIndex].bakedImage
        refreshUndoRedoState() // the fill is undoable from the moment it starts, even on a blank canvas

        fillLock.lock()
        fillPending = currentFillKey()
        fillRendered = FillKey(gap: .min, threshold: .min, edge: .min)
        fillWorkerScheduled = true // claimed here so early drag updates don't spawn a second worker
        fillLock.unlock()

        fillQueue.async { [weak self] in
            guard let self else { return }
            if let refBytes = Self.compositeReferenceRGBA(references: references, width: width, height: height) {
                let session = MetalFillEngine.shared?.makeSession(referenceRGBA: refBytes, width: width, height: height)
                self.fillSession = session
                self.fillSeedColor = session?.seedColor(atX: seedX, y: seedY) ?? .zero
            }
            self.drainFillWork()
        }
    }

    private func currentFillKey() -> FillKey {
        FillKey(gap: Int(fillGapClosingDistance.rounded()),
                threshold: Int((fillThreshold * 1000).rounded()),
                edge: Int(fillExpand.rounded()))
    }

    /// The layers whose content bounds the fill, bottom-to-top: every layer marked `isFillReference`, at
    /// its active cel for the current frame. Empty when nothing is a reference (the fill then floods the
    /// whole canvas).
    private func fillReferenceSources() -> [(layer: Layer, cel: Cel)] {
        layers.indices.compactMap { i in
            let layer = layers[i]
            guard layer.isFillReference,
                  let celIdx = activeCelIndex(inLayer: i, atFrame: currentFrame) else { return nil }
            return (layer, layer.cels[celIdx])
        }
    }

    /// Updates the in-progress fill's gap-closing (vertical drag), wall threshold (horizontal drag) and
    /// edge-overlap settings — clamped to the slider ranges — and re-fills from the cached GPU session.
    /// Also writes them back to the published settings so the fill sliders mirror the drag live. Cheap to
    /// call on every touch-move: identical quantized values schedule no work, and a burst coalesces.
    func updateInteractiveFill(gapClosing: CGFloat, threshold: CGFloat, edgeOverlap: CGFloat) {
        guard fillGestureActive else { return }
        let clampedGap = min(max(gapClosing, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
        let clampedThreshold = min(max(threshold, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
        let clampedEdge = min(max(edgeOverlap, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
        if fillGapClosingDistance != clampedGap { fillGapClosingDistance = clampedGap }
        if fillThreshold != clampedThreshold { fillThreshold = clampedThreshold }
        if fillExpand != clampedEdge { fillExpand = clampedEdge }
        scheduleFillRender()
    }

    /// Sets one fill setting from the Fill panel: updates the value, makes that setting the axis the
    /// fill tool's sideways drag will adjust next time, and — if a fill is currently adjustable — re-runs
    /// it live so the user sees the change without re-tapping. Called from the panel's slider bindings;
    /// the interactive drag writes the `@Published` values directly instead, so it never re-selects here.
    func setFillSetting(_ axis: FillAxis, _ value: CGFloat) {
        fillSelectedAxis = axis
        switch axis {
        case .gapClosing:
            let v = min(max(value, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
            if fillGapClosingDistance != v { fillGapClosingDistance = v }
        case .threshold:
            let v = min(max(value, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
            if fillThreshold != v { fillThreshold = v }
        case .edgeOverlap:
            let v = min(max(value, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
            if fillExpand != v { fillExpand = v }
        }
        if fillGestureActive { scheduleFillRender() }
    }

    /// Coalesces a re-render of the current fill for the latest `@Published` parameters onto `fillQueue`.
    private func scheduleFillRender() {
        fillLock.lock()
        fillPending = currentFillKey()
        let alreadyScheduled = fillWorkerScheduled
        fillWorkerScheduled = true
        fillLock.unlock()
        if !alreadyScheduled {
            fillQueue.async { [weak self] in self?.drainFillWork() }
        }
    }

    /// Whether `point` (canvas-pixel coords, top-left origin) lands on a pixel the current adjustable fill
    /// already covers. Used so a re-tap inside the just-filled region resumes drag-adjusting it, rather
    /// than starting a new fill.
    func isPointInPendingFill(at point: CGPoint) -> Bool {
        guard fillGestureActive, let bytes = fillLastRegionRGBA, fillLastRegionW > 0 else { return false }
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard x >= 0, x < fillLastRegionW, y >= 0, y < fillLastRegionH else { return false }
        return bytes[(y * fillLastRegionW + x) * 4 + 3] > 0
    }

    /// Re-arms drag-adjusting of the existing adjustable fill (same session/seed) when a finger presses
    /// back down inside it. No new session or reference composite — it just keeps adjusting what's there.
    func resumeInteractiveFillDrag() {
        guard fillGestureActive else { return }
        fillFingerDown = true
    }

    /// Ends the finger press but leaves the fill *adjustable*: the last-requested parameters are flushed
    /// and the preview stays visible with its GPU session alive, so panel sliders re-run it live and a
    /// re-tap inside it resumes dragging. It's baked (committed) only later, by `commitInteractiveFill`.
    func endInteractiveFill() {
        guard fillGestureActive, fillFingerDown else { return }
        fillFingerDown = false
        fillQueue.async { [weak self] in self?.drainFillWork() } // render anything still pending; keep session
    }

    /// Bakes the current adjustable fill into the layer as a single "Fill" undo step and tears the
    /// session down. The layer's kind decides the destination outright, with no fallback between
    /// them — each tier is invisible to the other's renderer:
    ///
    /// - **vector layer** → a `VectorFillElement` (a closed path) on the `VectorCanvas`, which is
    ///   the only thing such a layer draws.
    /// - **raster layer** → flattened straight into `Cel.raster`, the tier the eraser stamps, so the
    ///   fill can be erased afterwards (see `registerUndoableCelChange`'s doc comment).
    func commitInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false
        fillFingerDown = false
        // Capture the mask bytes before clearing — needed for the vector-path extraction below.
        let regionBytes = fillLastRegionRGBA
        let regionW = fillLastRegionW, regionH = fillLastRegionH
        fillLastRegionRGBA = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        let fillColor = fillGestureFillColor
        defer { fillGestureBaseBaked = nil; fillGestureLayerID = nil; fillGestureCelID = nil; refreshUndoRedoState() }
        guard let layerID = fillGestureLayerID, let celID = fillGestureCelID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        guard layers[layerIndex].cels[celIndex].fillImage != nil else { return }  // nothing was previewed

        if layers[layerIndex].kind == .vector {
            // --- Vector layer: the fill becomes a VectorFillElement, never raster pixels ---
            // A vector layer's on-screen content is `VectorCanvas.render()` alone (see
            // `StrokeCanvasView.refreshDisplay`), so this must NOT fall through to the raster branch
            // below when the contour can't be extracted: `PixelOps.rasterize` *does* read the raster
            // tier, so a fill left there would vanish from the canvas while still showing up in
            // thumbnails, fill references, Move lifts and merges — the vector twin of the raster
            // "ghost layer" bug. An unextractable mask means an empty fill, so dropping the preview
            // is the correct outcome; nothing is recorded.
            if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
                layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
            }
            // Clear the transient raster preview either way so it isn't drawn a second time.
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: nil)
            guard let vectorCanvas = layers[layerIndex].cels[celIndex].vector,
                  let bytes = regionBytes, regionW > 0, regionH > 0,
                  let path = PixelOps.pathFromAlphaMask(bytes: bytes, width: regionW, height: regionH) else { return }
            let fillsBefore = vectorCanvas.fills
            // The mask is measured against the *rendered* canvas, so it's canvas-space — this
            // overload maps it back through the layer's transform (see its doc comment).
            vectorCanvas.addFill(canvasSpacePath: path, color: fillColor)
            registerVectorFillUndo(vectorCanvas: vectorCanvas, oldFills: fillsBefore, newFills: vectorCanvas.fills,
                                   layerID: layerID, celID: celID, actionName: "Fill")
        } else {
            let cel = layers[layerIndex].cels[celIndex]
            guard let preview = cel.fillImage else { return }
            // --- Raster path: flatten into `raster` directly ---
            // `fillGestureBaseBaked` is only the pre-gesture `bakedImage` tier (see where it's
            // captured in `beginInteractiveFill`); the live raster strokes sit *above* both baked and
            // fill in render order (see `PixelOps.rasterize`), so they have to be composited back on
            // top explicitly here rather than just carried over via `newRaster: cel.raster` — leaving
            // the fill's own pixels stuck underneath a `raster` tier the eraser stamps into but the
            // fill itself never touched.
            let belowStrokes = PixelOps.compositeOver(base: fillGestureBaseBaked, overlay: preview)
            let finalImage = PixelOps.compositeOver(base: belowStrokes, overlay: cel.raster.renderToUIImage())
            registerUndoableCelChange(layerID: layerID, celID: celID,
                                      oldRaster: cel.raster, oldBaked: fillGestureBaseBaked, oldFill: nil,
                                      newRaster: bakedRasterTexture(image: finalImage, likeExisting: cel.raster),
                                      newBaked: nil, newFill: nil,
                                      actionName: "Fill")
        }
    }

    /// Registers one undo step that swaps a vector layer's `.fills` between `oldFills`/`newFills` —
    /// used by an adjustable-fill commit and by Fill/Clear-on-selection for vector layers (see
    /// `SelectionModels.swift`). Resolves the cel by ID (not a captured index) when the thumbnail
    /// regen fires, since other structural edits may have shifted indices by then.
    func registerVectorFillUndo(vectorCanvas: VectorCanvas,
                                oldFills: [VectorFillElement], newFills: [VectorFillElement],
                                layerID: UUID, celID: UUID, actionName: String) {
        let cost = (oldFills.count + newFills.count) * 512
        recordUndo(name: actionName, cost: cost, undo: { [weak self] in
            vectorCanvas.fills = oldFills
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vectorCanvas.fills = newFills
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

    /// Abandons the interactive fill without committing, discarding the preview. Used when an undo/redo
    /// tap takes over, or via `cancelInteractiveFillDrag` when a two-finger transform starts mid-drag.
    func cancelInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false // stops any in-flight render from applying (its main hop checks this)
        fillFingerDown = false
        fillLastRegionRGBA = nil
        if let layerID = fillGestureLayerID, let celID = fillGestureCelID,
           let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
           let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) {
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: nil)
        }
        fillGestureLayerID = nil
        fillGestureCelID = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        refreshUndoRedoState()
    }

    /// Discards the fill only if a finger is actively dragging it; an already-lifted adjustable fill
    /// survives (so a two-finger pan/zoom to inspect the canvas doesn't wipe it out).
    func cancelInteractiveFillDrag() {
        guard fillFingerDown else { return }
        cancelInteractiveFill()
    }

    /// Runs on `fillQueue`. Recomputes the fill for the latest requested parameters and pushes the painted
    /// preview to the active cel, looping until pending == last-rendered so a burst of drag updates
    /// collapses to a single trailing render.
    private func drainFillWork() {
        while true {
            fillLock.lock()
            let key = fillPending
            if key == fillRendered {
                fillWorkerScheduled = false
                fillLock.unlock()
                return
            }
            fillRendered = key
            fillLock.unlock()

            guard let session = fillSession else {
                fillLock.lock(); fillWorkerScheduled = false; fillLock.unlock()
                return
            }
            let bytes = session.fill(seedX: fillGestureSeed.x, seedY: fillGestureSeed.y,
                                     seedColor: fillSeedColor,
                                     threshold: Float(Double(key.threshold) / 1000.0),
                                     gapRadius: Float(key.gap), edgeOverlap: Float(key.edge),
                                     fillColor: fillGestureColor)
            let image = bytes.flatMap { Self.imageFromRGBA($0, width: session.width, height: session.height) }
            let layerID = fillGestureLayerID, celID = fillGestureCelID
            let regionW = session.width, regionH = session.height
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fillGestureActive,
                      let layerID, let celID,
                      let layerIndex = self.layers.firstIndex(where: { $0.id == layerID }),
                      let celIndex = self.layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
                let clipped = self.clippedForSelection(image, layerIndex: layerIndex, celIndex: celIndex)
                self.setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: clipped)
                self.fillLastRegionRGBA = bytes
                self.fillLastRegionW = regionW
                self.fillLastRegionH = regionH
            }
        }
    }

    /// Clips a fill preview to the active selection's path when the fill lands on the exact layer/cel
    /// the selection belongs to and outside interaction is denied — the flood-fill tool analogue of
    /// `StrokeCanvasView.selectionClipPath`, so a bucket fill can't paint outside the marching ants
    /// any more than a brush stroke can. Runs on the main thread (called from the `fillQueue` render's
    /// `DispatchQueue.main.async` hop), same as every other read of `selection`/
    /// `allowsPaintingOutsideSelection` here.
    private func clippedForSelection(_ image: UIImage?, layerIndex: Int, celIndex: Int) -> UIImage? {
        guard let image, let selection, !allowsPaintingOutsideSelection,
              layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].id == selection.layerID, layers[layerIndex].cels[celIndex].id == selection.celID else { return image }
        return PixelOps.maskedComposite(base: nil, overlay: image, insidePath: selection.path)
    }

    // MARK: - Fill helpers

    /// Premultiplied RGBA components (0..1) of a UIColor, resolved against a fixed light trait so
    /// dynamic colours don't silently return black (the getRed-on-dynamic-colour pitfall).
    private static func premultipliedComponents(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r * a), Float(g * a), Float(b * a), Float(a))
    }

    /// Composites the fill-reference layers (bottom-to-top) into a top-left-origin, premultiplied-last
    /// RGBA byte buffer the GPU reads its walls from. Excludes each layer's own transient fill preview
    /// (`fillImage`) but includes committed fills (now baked into `bakedImage`), so recolouring works.
    private static func compositeReferenceRGBA(references: [(layer: Layer, cel: Cel)], width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: PixelOps.transparentFormat())
        let composited = renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            for source in references {
                source.cel.bakedImage?.draw(in: rect)
                source.cel.raster.renderToUIImage().draw(in: rect)
                source.cel.vector?.render().draw(in: rect)
            }
        }
        guard let cg = composited.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        let ok: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            // No flip: drawing a top-down UIImage's cgImage into a default bitmap context already lands
            // its top row at buffer row 0. (The old engine's translate/scale(-1) here was the long-latent
            // vertical-mirror bug — invisible on the centred shapes every earlier test used.)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }

    /// Wraps a top-left-origin premultiplied-last RGBA byte buffer into a UIImage for the fill preview.
    /// Built via a `CGDataProvider`, which is canonically top-down (data row 0 is the top) — matching the
    /// top-down reference the GPU fills against, so the painted region displays where it was tapped.
    private static func imageFromRGBA(_ bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                               bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }


    func setFillImage(layerIndex: Int, celIndex: Int, image: UIImage?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].fillImage = image
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }}
