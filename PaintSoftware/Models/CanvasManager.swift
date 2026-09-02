import SwiftUI
import Combine
import UIKit

// CanvasManager is decomposed across `CanvasManager+*.swift` files, each an `extension
// CanvasManager` holding one subsystem's methods. Deliberately NOT split into separate service
// objects: every view binds straight to the `@Published` properties below, and re-homing them
// behind child objects would mean rewriting all of those bindings or hand-maintaining forwarding
// plus manual `objectWillChange` re-publishing for dozens of properties.
//
// So: **all stored state stays declared here**, on the class — extensions cannot declare stored
// properties, so the extension files hold only functions.
//
// One mechanical consequence: `private` in Swift is scoped to the *file*, not the type, so a
// member an extension file calls cannot be `private` here — such members are `internal` (no
// keyword) instead, which does not widen anything past module scope.
final class CanvasManager: ObservableObject {
    /// The full working canvas size, *including* any padding margin — everything downstream
    /// (buffers, container bounds, fill, thumbnails, fit-to-screen, persistence) keys off this. The
    /// artwork rect is derived as this inset by `canvasPadding` on every side.
    @Published var canvasSize: CGSize?

    /// Light-grey drawable margin (in canvas pixels) around the artwork, adjustable from the Actions
    /// menu (default 0). Folded into `canvasSize` — real drawable canvas, not a visual-only border —
    /// so the artwork rect is `canvasSize` inset by this amount. Changed only via
    /// `setCanvasPadding`, which resizes every buffer to keep existing content centred.
    @Published var canvasPadding: CGFloat = 0

    /// The largest coordinate a canvas dimension may reach — **16383, not 16384**. TODO.md item (8)'s
    /// signed 16-bit quarter-pixel sample coordinate addresses -8192.0...+8191.75 (a span of
    /// 16383.75 pt, not 16384), so with the encoding origin at the canvas centre, 16383 is the largest
    /// dimension that encodes without clamping a quarter-pixel *inside* the artwork on two edges.
    /// **The single named home for this bound** — TODO.md item (13) asks for one, and this is it.
    /// `canvasPaddingRange` below and `CanvasSizePickerView.maxDimension` both read this rather than
    /// spelling 16383 a second time.
    static let maxCanvasExtent: CGFloat = 16383

    /// Base upper bound for `canvasPadding` on an ordinary canvas — 1024 pt per side, raised from 512
    /// by TODO.md item (13).
    static let canvasPaddingBaseUpperBound: CGFloat = 1024

    /// Clamp range for `canvasPadding`; the Actions-menu slider mirrors it.
    ///
    /// **Not `static` any more** — the bound depends on the *live* canvas, shrinking as it approaches
    /// `maxCanvasExtent` so `canvasSize` (which already includes padding, see that property's doc
    /// comment) can never exceed it: `min(canvasPaddingBaseUpperBound, (maxCanvasExtent -
    /// artworkExtent) / 2)`. `k = 2` because `setCanvasPadding` adds `2 * delta` to each dimension —
    /// padding is per side. `artworkExtent` is `canvasSize` inset by the padding *already applied*
    /// (`canvasSize` minus twice the current `canvasPadding`), not `canvasSize` itself, or the padding
    /// already on the canvas would be subtracted from the budget twice. Uses the larger of width/height
    /// so a non-square canvas (the owner's own 2048x1024 baseline) is bounded by whichever dimension is
    /// closer to the limit — `setCanvasPadding` grows both dimensions by the same `delta`.
    var canvasPaddingRange: ClosedRange<CGFloat> {
        guard let canvasSize else { return 0...Self.canvasPaddingBaseUpperBound }
        let artworkExtent = max(canvasSize.width, canvasSize.height) - 2 * canvasPadding
        let budgetBound = (Self.maxCanvasExtent - artworkExtent) / 2
        let upper = max(0, min(Self.canvasPaddingBaseUpperBound, budgetBound))
        return 0...upper
    }

    @Published var projectName: String = "Untitled"
    var projectID: UUID = UUID()
    var projectURL: URL?

    /// What the load of this document could not read, or empty for the ordinary case — a new project,
    /// or one that opened whole. Set once by `ProjectStore.assemble` and never mutated after.
    ///
    /// Not `@Published`: nothing observes it. The banner is raised by `ContentView` at the moment a
    /// save is attempted rather than by a view watching this, because the artist should be asked when
    /// there is a decision to make, not the instant a damaged project appears on screen — at which
    /// point there is nothing to decide and nothing at risk.
    var loadDamage = ProjectLoadDamage()

    /// Whether the artist has already answered the damaged-save banner for this document.
    ///
    /// **In memory, for the life of this `CanvasManager`, and deliberately not persisted.** Save
    /// Anyway rewrites the package without the unreadable entries, so the *next* load of this project
    /// reports clean and there is nothing left to ask — the document heals itself and a stored flag
    /// would have nothing to do. Cancel leaves the damage on disk, and asking again next time is
    /// correct, because the artist declined to decide. See `SaveDamageGate`.
    var damagedSaveAnswered = false

    @Published var layers: [Layer] = []
    @Published var folders: [LayerFolder] = []
    @Published var viewPresets: [ViewPreset] = []
    /// -1 means no view preset is active (all layers visible in their natural state).
    @Published var activeViewPresetIndex: Int = -1

    /// Every motion group in the document, in creation order. Strokes reference these by id
    /// (`VectorStroke.motionGroupID`); a recipe binds geometry to them (`MotionGroupBinding`).
    ///
    /// Document-level rather than per-layer so a group can span layers — what stops a lineart arm
    /// and its flat colour drifting apart. Empty until the artist tags something, so this costs
    /// nothing for a project that never interpolates.
    @Published var motionGroups: [MotionGroup] = []

    /// Every guide stroke in the document. Document-level for the same reason, and because a guide
    /// is meant to be *referenced* by several intervals rather than copied into each, which only
    /// works if it has one home and a stable id.
    @Published var guideStrokes: [GuideStroke] = []

    /// Whether the artist is in interpolate mode — the mode the whole interpolation workflow lives
    /// inside.
    ///
    /// A mode on the manager rather than a `Tool` case, same precedent as `vectorEraserMode`:
    /// interpolating is not a thing you *draw with*, it is a state the timeline and canvas are in
    /// while using whatever tool you had. Making it a tool would evict the brush on every reference.
    ///
    /// Leaving the mode clears `interpolationReferences` (see `exitInterpolateMode`) but never
    /// touches a recipe already attached to a cel — the recipe is document content, the selection is
    /// a transient.
    @Published var isInterpolateMode: Bool = false

    /// **Whether the graph editor band is open** — KEYFRAMES.md §11.3, opened and closed by the
    /// timeline's `timeline.graphEditorButton`.
    ///
    /// One `Bool` and not a set, because the owner ruled on 2026-08-29 that exactly one band is open
    /// at a time and it follows the selection: the row it expands is `currentLayerIndex`, so
    /// selecting another layer moves the band rather than opening a second one.
    ///
    /// **Transient view state, deliberately not persisted.** It changes no pixel of the document and
    /// has no meaning with the timeline closed, so putting it in the manifest would be a field that
    /// only ever says which panel was up last — §11.5 makes the same call about the channel list's
    /// visibility for the same reason. `interpolationThicknessFade` is the nearest precedent.
    ///
    /// **Closing the band drops the channel filter with it, and takes the channel list down**, which
    /// is D4's scoping rule stated in the one place that cannot be bypassed: §11.5 makes the filter
    /// transient *because* it has no meaning with the editor closed, so a filter that outlived the
    /// band would be exactly the state the ruling refuses. The other half of the same rule is
    /// `Filter.hidden(on:)`, which answers `[]` for any band but the one it was authored on.
    @Published var isGraphEditorOpen: Bool = false {
        didSet {
            if !isGraphEditorOpen {
                graphChannelFilter = .none
                isGraphChannelListOpen = false
            }
        }
    }

    /// **Whether the graph editor's channel list is up** — the `.popover`'s `isPresented`, held here
    /// rather than as `@State` in `AnimationTimeline` for one reason: it has a *rule*, and the rule
    /// has to be pinnable.
    ///
    /// The rule is the line above. The list is a control **of** the editor, so it cannot outlive it,
    /// and closing the band deletes the very button the popover hangs off —
    /// `CanvasPresentationModifier` clears the registry from `.onDisappear` but deliberately never
    /// the site's own flag, so a popover whose host is destroyed while it is up comes back by itself
    /// when the host returns (BUGS.md, "A popover whose host view disappears re-presents itself when
    /// the host comes back"). D4 is the first control in the app rendered conditionally with a
    /// presentation on it, so D4 is where that became reachable.
    ///
    /// **Written as a `didSet` on the model and not as an `onChange` on a view**, because
    /// `Views/AnimationTimeline.swift` is not compiled into `PaintSoftwareUITests` — a guard written
    /// there is pinned by nothing, and this one cannot be pinned from the UI tier either: a tap that
    /// lands on the graph editor's toggle while the popover is up is spent dismissing the popover and
    /// never reaches the button (measured 2026-08-29 on the simulator, which is why
    /// `testTheChannelListButtonExistsOnlyWhileTheBandIsOpen` taps the canvas first). Here it is one
    /// line and `testClosingTheEditorTakesTheChannelListDownWithIt`.
    ///
    /// Transient, like everything else on this surface: nothing here reaches a manifest.
    @Published var isGraphChannelListOpen: Bool = false

    /// **Which of the open band's channels the artist has switched off** — KEYFRAMES.md §11.5,
    /// set from `timeline.graphChannelsButton`'s popup.
    ///
    /// Transient view state for `isGraphEditorOpen`'s reason and one of its own: it can only ever
    /// *subtract* from what the band would draw, so it changes no pixel of the document and there is
    /// nothing in it a reopened project would be worse for having forgotten. Deliberately absent from
    /// `LayerManifest`, `FolderManifest` and every codec.
    @Published var graphChannelFilter: TimelineGraphChannelList.Filter = .none

    /// **The layer the band is held under while a timeline gesture owns the track**, or nil when it
    /// is free to follow the selection — KEYFRAMES.md §11.3. Written only through
    /// `pinGraphBand()` / `releaseGraphBand()`, which is where the reasoning lives.
    ///
    /// A layer index rather than a whole `Expansion` because that is the only part of the band a
    /// gesture must not be allowed to move: opening and closing it is the artist pressing a button,
    /// which is never a thing that happens under a finger already on the track.
    ///
    /// Transient like `isGraphEditorOpen`, and shorter lived than it — one gesture.
    @Published var graphBandPinnedLayerIndex: Int?

    /// The cels the artist has flagged as keyframes, in the order they were flagged — which is time
    /// order only because the artist picks them that way. Highlighted yellow on the timeline.
    ///
    /// Several cels on *different layers* may be flagged for one keyframe (lineart and flats
    /// interpolate together). `interpolationKeyframes` groups them back into
    /// `InterpolationReference`s, by frame.
    @Published var interpolationReferences: [CelRef] = []

    /// View-level toggle for `InterpolationEvaluator.Options.thicknessFade`, so the two behaviours
    /// can be compared on real drawings.
    ///
    /// Deliberately **not** persisted and **not** per-recipe: where it eventually belongs is a
    /// decision to take after looking at it. Off matches the evaluator's default; the reason it is
    /// off is in `InterpolationEvaluator.ThicknessFade`.
    @Published var interpolationThicknessFade: Bool = false

    /// True while a registration is running. Registration is the expensive step of the feature — an
    /// ARAP fit over the keyframes' point clouds — and it is synchronous, so this exists for the UI
    /// to show that something is happening rather than to gate anything.
    @Published var isRegisteringInterpolation: Bool = false

    /// True from the moment a "Resize Canvas" is committed until its walk has finished —
    /// CANVAS_RESIZE.md §5 rules 12 and 15, and stage 3's items 1 and 2.
    ///
    /// **It does two jobs and only one of them is the spinner.** `DrawingView` puts a hit-testing
    /// overlay up on it, so the artist can see the app is working and cannot draw into a document
    /// whose extent is changing under them; and `ContentView.saveIfNeeded` refuses to *start* a save
    /// while it is set, through `ScenePhaseSaveGate.mayStartSave`. The second is the one the owner's
    /// ruling makes **more** necessary rather than less: a block the artist is told about is still a
    /// block, and `ScenePhaseSaveGate` fires on `active → !active`, so an app switch during one
    /// would otherwise write a document that is half old-size and half new.
    ///
    /// **Set for the announced path only, and that is why nothing flashes.** A resize small enough
    /// to be imperceptible never suspends, so SwiftUI never lays out with this true and there is no
    /// frame in which the overlay could appear — see `resizeCanvasAnnouncingProgress`, which decides
    /// which path a resize takes and carries the reasoning.
    @Published var isResizing: Bool = false

    /// True between `beginInterpolationDrag` and `commitInterpolationDrag` — the `t` slider is being
    /// dragged. Selects `.preview` render quality for the duration; see `RenderQuality`.
    @Published var isScrubbingInterpolation: Bool = false

    /// The motion group a canvas tap assigns to, or nil when tapping does nothing — the retagging
    /// gesture, armed from its chip on `InterpolateBar`.
    ///
    /// **Armed state rather than a tool**, for the same reason `isInterpolateMode` is not a `Tool`
    /// case: the artist keeps whatever brush they had, and arming a group must not evict it. Cleared
    /// on leaving the mode — an armed group left set would turn the next ordinary tap into a silent
    /// document edit.
    ///
    /// Deliberately not a *selection* of strokes: a group's membership must stay "which ink is in
    /// this group", never "which stroke pairs with which", and arm-then-tap writes exactly that —
    /// one tag per stroke, no pairing anywhere.
    @Published var armedMotionGroupID: UUID? = nil

    /// Motion groups hidden from the interpolated preview — the mute half of solo/mute.
    ///
    /// A view filter, not document state: it changes what the in-between *shows* while the artist is
    /// working out which part moves wrongly, and must not survive the session or reach the file. It
    /// feeds `InterpolationEvaluator.Options.hiddenGroups`, and is in `InterpolationPreviewKey` —
    /// without that the preview is memoized against inputs that don't mention it, and muting appears
    /// to do nothing until something unrelated forces a re-render.
    @Published var hiddenMotionGroups: Set<UUID> = []

    /// Whether a keyframe's strokes are drawn in their motion groups' tag colours while interpolate
    /// mode is on.
    ///
    /// **On by default** — "what did it decide?" is the question this exists to answer, and an
    /// overlay nobody switches on answers nothing. Shows only where there is a decision to show — a
    /// drawing that grouped into one part is not tinted at all — and the switch is in the mode's
    /// options popover for the artist who wants their own colours back for a moment.
    @Published var showMotionGroupOverlay: Bool = true

    /// Whether the next canvas drag draws a **guide stroke** rather than ink.
    ///
    /// Armed state rather than a `Tool` case, exactly like `armedMotionGroupID` and for the same
    /// reason: the artist keeps the brush they had. Cleared on leaving the mode — left armed, the
    /// next ordinary stroke would silently become a guide instead of a drawing, which is the louder
    /// half of that failure since a guide does not appear in the layer at all.
    @Published var isDrawingGuide: Bool = false

    /// The guide a handle drag is reshaping, and its geometry as it stood at touch-down. Non-nil
    /// exactly while a handle is under the finger.
    ///
    /// The samples are kept because every move re-derives the whole path from *these* rather than
    /// nudging the path it last produced. Applying each move as a delta to the already-deformed
    /// geometry compounds the falloff, so the same drag performed slowly (more touch samples) bends
    /// the guide further than one performed quickly.
    ///
    /// Deliberately not `@Published`: nothing renders from it, and the guide itself is published, so
    /// a second object change per touch sample would only cost SwiftUI passes.
    var guideHandleDrag: (guideID: UUID, samples: [TimedSample])?

    /// Whether the guide overlay is showing its **spacing chart** instead of its geometry handles.
    ///
    /// Two editors on one path cannot both own it: a chart dot and a shape handle would sit on the
    /// same polyline and fight for the same touch, so geometric adjustment gets handles and timing
    /// adjustment gets the chart as *separate* controls — the overlay shows one at a time and the
    /// bar says which.
    @Published var isEditingGuideSpacing: Bool = false

    /// The guide whose chart is under the finger, the chart as it stood at touch-down, and the
    /// recipe it was read from — same shape as `guideHandleDrag`, same reasons. The recipe is what a
    /// cancelled drag is put back to; `cancelStructureGesture` drops the undo snapshot but
    /// deliberately does not restore from it.
    var guideSpacingDrag: (guideID: UUID, chart: SpacingChart, recipe: InterpolationRecipe)?

    @Published var currentLayerIndex: Int = 0 {
        didSet {
            if oldValue != currentLayerIndex {
                handleActiveContextChanged()
                // Debug recorder (off by default; see `ActionRecorder.isCapturing`). The *value*, not
                // just the fact of a change — "which layer was active" is what decides where a stroke
                // landed and which stroke recognizer the transform gestures were waiting on.
                ActionRecorder.ifRecording { $0.model("currentLayerIndex", String(currentLayerIndex)) }
            }
        }
    }

    /// The node whose mask is being edited (§6.5), or nil outside mask-edit mode.
    ///
    /// **Modal state on the manager rather than view `@State`**, specifically so `CanvasView` can
    /// read it too and dim every layer that isn't a legal source while it's on — a view-local flag
    /// on `LayerPanel` would be invisible from there. A `MaskSource` names both the target and its
    /// kind uniformly with the rest of §6.2, so nothing that reads this needs a separate "is it a
    /// folder" flag.
    ///
    /// Same precedent as `isDrawingGuide`/`armedMotionGroupID`: a mode the layer panel enters and
    /// leaves explicitly (§6.5 wants an explicit exit, not "tap away"), not a `Tool` case.
    @Published var maskEditTarget: MaskSource?

    /// Whether the active layer is a vector layer with a live vector canvas on the current frame.
    var activeLayerIsVector: Bool {
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIdx = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return false }
        return layers[currentLayerIndex].cels[celIdx].vector != nil
    }

    /// The active layer's `LayerKind`, or nil when `currentLayerIndex` points at nothing — which it
    /// legitimately does mid-edit, e.g. `deleteLayer` parks it at -1 while removing the active layer.
    /// Views deciding what to show for the active layer should ask this rather than indexing
    /// `layers` themselves, so the bounds check lives in one place.
    ///
    /// Deliberately weaker than `activeLayerIsVector` above: reports only what *kind* of layer is
    /// selected, nothing about whether a `VectorCanvas` exists on the current frame. That's what UI
    /// affordances want — `EraserSettingsPanel`'s mode picker should show on a vector layer whose
    /// current frame is still empty. Operations needing geometry to actually be there still want
    /// `activeLayerIsVector`.
    var activeLayerKind: LayerKind? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        return layers[currentLayerIndex].kind
    }

    /// Imports an image onto the active vector layer as a movable element (centered, scaled to fit,
    /// cascaded off whatever is already there), participating in the layer's overall transform.
    /// Returns false if the active layer isn't a vector layer (`insertImage` below falls back to
    /// creating one). Shapes and video slot in here the same way in future.
    ///
    /// Placement and the cascade both happen inside `VectorCanvas.addImage(canvasSpaceElement:...)`,
    /// under one lock acquisition, rather than here: this method would need `vector.transformScale`
    /// to convert `canvasSize`-derived numbers into local units, and reading that and then calling
    /// `addImage` separately is two lock acquisitions around a value that only `VectorCanvas` itself
    /// can be sure hasn't changed in between.
    @discardableResult
    func addImageToActiveVectorLayer(_ image: UIImage) -> Bool {
        beginCanvasEdit()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIdx = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIdx].vector,
              image.size.width > 0, image.size.height > 0 else { return false }
        let fit = min(canvasSize.width / image.size.width, canvasSize.height / image.size.height) * 0.8
        let imagesBefore = vector.images
        let element = vector.addImage(canvasSpaceElement: image,
                                      canvasPosition: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                                      canvasFit: fit)
        scheduleThumbnailRegen(layerIndex: currentLayerIndex, celIndex: celIdx)
        // VectorCanvas is a reference type; nudge SwiftUI so the canvas view reconciles + re-renders.
        objectWillChange.send()
        let layerID = layers[currentLayerIndex].id
        let celID = layers[currentLayerIndex].cels[celIdx].id
        recordUndo(label: .insertImage, cost: Self.approximateImageCost(image), undo: { [weak self] in
            vector.images = imagesBefore
            vector.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vector.images = imagesBefore + [element]
            vector.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
        return true
    }

    /// Inserts a photo as a movable vector element — images are always vector content (resolution-
    /// independent, move/rotate/scale with the rest of that layer's transform), never raster pixels.
    /// Adds to the active layer if it's already a vector layer; otherwise creates a fresh vector layer
    /// first (a separate, preceding undo step — see `addVectorLayer`). Replaces the old dedicated
    /// "object layer" concept (a whole layer pinned to one image).
    @discardableResult
    func insertImage(_ image: UIImage) -> Bool {
        if addImageToActiveVectorLayer(image) { return true }
        addVectorLayer()
        return addImageToActiveVectorLayer(image)
    }

    /// Converts a vector layer to raster in place: each cel's full content is folded into `raster`
    /// (not `bakedImage` — a raster-layer cel must hold its content in exactly one tier at rest, or
    /// the eraser can never reach it), `vector` is cleared, `kind` becomes `.raster`. No-op if the
    /// layer isn't currently `.vector`. `mergeLayers` also calls this on both layers being merged
    /// before flattening, so a vector layer never comes out of a merge still labeled `.vector` with
    /// stale geometry. The nested `withStructureUndo` below coalesces into whichever scope is
    /// already open, so calling this from inside `mergeLayers`'s own scope adds no extra step.
    func rasterizeLayer(layerIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].kind == .vector,
              let canvasSize else { return }
        // **The float's settle must stay above `withStructureUndo`, and it is silent artwork loss
        // without it.** A
        // float suppresses its ids out of the layer's own render; the suppression setter invalidates,
        // so `PixelOps.RasterizeKey` misses and `rasterizeUncached` flattens through
        // `cel.vector?.render(quality:)` *honouring* the suppression — and then the loop below sets
        // `vector = nil`, so the geometry that produced the missing ink is gone too. With a lasso
        // float that costs the lassoed subset; with a whole-cel float (`beginVectorWholeCelMove`,
        // where every id is suppressed) it flattens the entire cel to blank, in the saved document,
        // recoverable only by relaunch. Above `withStructureUndo` for that line's own reason: the
        // settle must be part of the state the snapshot is taken *of*, not of the step it records.
        commitVectorFloatIfLifted(fromLayer: layers[layerIndex].id)
        withStructureUndo(label: .rasterize) {
            // **Every derivation is resolved before the first cel is mutated, and the ordering is a
            // correctness requirement rather than tidiness.** An in-between's references are usually
            // other cels *in this same layer*, and the loop below clears `vector` as it goes — so
            // resolving cel 5's recipe after cel 2 had been flattened would read an emptied keyframe
            // and bake a blank in-between. `DerivedCelContent`'s closures capture the display lists
            // they resolved, so a batch taken here stays valid across the whole loop.
            let derived = layers[layerIndex].cels.map { derivedCelContent(for: $0, atFrame: $0.startFrame) }
            for celIndex in layers[layerIndex].cels.indices {
                let cel = layers[layerIndex].cels[celIndex]
                // **Through the seam, and a derived cel is why this is not cosmetic.** An in-between
                // stores no display list, so flattening it without a provider baked a blank frame
                // and then `vector = nil` and `kind = .raster` took away every way back — the same
                // "silent artwork loss" the float-settle above guards against, arriving by another
                // door. Item 18's own filing names rasterize as the chokepoint every consumer shares.
                let flattened = PixelOps.rasterize(cel: cel, canvasSize: canvasSize,
                                                   derived: derived[celIndex])
                layers[layerIndex].cels[celIndex].raster = bakedRasterTexture(image: flattened, likeExisting: cel.raster)
                layers[layerIndex].cels[celIndex].bakedImage = nil
                layers[layerIndex].cels[celIndex].fillImage = nil
                layers[layerIndex].cels[celIndex].vector = nil
                // The recipe has to go with the geometry, and **both** modes, not just `.reproject`.
                // The frame is now stored pixels; leaving the recipe would evaluate it a second time
                // over the bake on every draw, and it has nothing left to read anyway — a `.generate`
                // recipe on a `.raster` cel is not a state any other code path expects.
                layers[layerIndex].cels[celIndex].interpolation = nil
            }
            layers[layerIndex].kind = .raster
        }
    }

    // MARK: - Select & Move tool state (see SelectionModels.swift for the operations)
    @Published var selectionMode: SelectionMode = .lasso
    @Published var transformMode: TransformMode = .uniform
    /// **TODO item (14) — "Keep full precision" on the Move bar.** While this is on, every stroke a
    /// committed vector Move writes is marked `VectorStroke.precise`, so its samples are *stored* as
    /// float32 instead of on the quarter-pixel grid.
    ///
    /// Off by default, and that is the ruling rather than caution: the packed form is the compaction
    /// feature item (8) shipped, and the precise one costs ~1.7x the bytes a sample. It buys exactly
    /// one thing — a stroke the artist shrinks, saves, reopens and grows again comes back where it
    /// was — and only a Move can shrink one, so only a Move turns it on.
    ///
    /// Not persisted across launches, unlike `pencilOnlyDrawing`: that one is about the artist's
    /// hardware and this one is about the drawing in front of them.
    @Published var preserveMovePrecision: Bool = false
    /// **TODO item (20) — "What travels" on the Move bar.** Which of the three membership rules a
    /// lasso move follows: `Enclosed`, `Cut` (the default and the shipped behaviour), `Touching`.
    ///
    /// **Not persisted, and that is the ruling rather than an omission** — it draws exactly the line
    /// `preserveMovePrecision` above draws, one line up. This is per-drawing intent; storing it would
    /// make *last used* the default, which is not what the owner asked for. There is no `@AppStorage`
    /// anywhere in this project and this does not introduce one.
    ///
    /// Written through `setLassoMoveMembership(_:)` while a piece is floating, never assigned
    /// directly from the view: changing the rule at that moment has to re-lift the float so the
    /// artist sees the difference, and the order that re-lift happens in is load-bearing (see
    /// `CanvasManager+LassoMove.swift`).
    @Published var lassoMoveMembership: LassoMembership = .cutting
    @Published var magicWandTolerance: Double = 0.15
    @Published var selection: Selection?
    @Published var floatingPiece: FloatingPiece? {
        didSet {
            // Only the transitions in and out are recorded, not every transform tick: a floating
            // piece is the state that makes the Move bottom bar appear and makes the select overlay
            // stop capturing gestures (`DrawingView`, `CanvasView.updateSelectionOverlay`), and
            // "there is one now" / "there isn't any more" is the whole of what a reader needs.
            guard (oldValue == nil) != (floatingPiece == nil) else { return }
            ActionRecorder.ifRecording { $0.model("floatingPiece", floatingPiece == nil ? "nil" : "active") }
        }
    }
    /// The vector layers' answer to `floatingPiece`: a lassoed region split out of the display list
    /// and moving under the artist's finger. See `CanvasManager+LassoMove.swift`.
    @Published var vectorFloat: VectorFloat? {
        didSet {
            guard (oldValue == nil) != (vectorFloat == nil) else { return }
            ActionRecorder.ifRecording { $0.model("vectorFloat", vectorFloat == nil ? "nil" : "active") }
        }
    }
    /// Single-slot clipboard for the timeline's Copy/Paste block menu — holds a cel's content (not
    /// its position), set by `copyCel` and consumed non-destructively by `pasteCel`.
    @Published var copiedCel: CopiedCel?
    /// Whether painting/erasing/filling is allowed to touch pixels outside the active selection.
    /// Defaults to false (deny), matching Procreate-style selections. Shown as a toggle in the
    /// Select bottom bar; only meaningful while `selection` is non-nil.
    @Published var allowsPaintingOutsideSelection: Bool = false

    @Published var brushSize: CGFloat = 5.0
    @Published var brushOpacity: Double = 1.0
    @Published var brushColor: Color = .black
    /// **This property's `didSet` used to be the fifth closer of an engaged whole-layer vector Move**
    /// — a real tool switch cleared `isVectorTransforming`, which the six writers of this property
    /// (`TopToolbar`'s brush/eraser/fill buttons, `selectEyedropper`, `leaveEyedropper`,
    /// `enterTextMode`) therefore did by construction rather than one door at a time. TODO item (12)
    /// stage 2 deleted the flag, and with it the reason: Move with no selection is a `vectorFloat`
    /// now, and a float is settled by `commitAllInteractiveState()`, which `TopToolbar` already calls
    /// *before* it writes this property.
    /// `LassoMoveLogicTests.testAWholeCelMoveIsSettledByCommitAllInteractiveStateAndHandsTheCanvasBack`
    /// is where that is pinned; the tool-switch doors that do **not** route through that chokepoint
    /// are TODO item (16), and they were never this `didSet`'s business.
    @Published var selectedTool: Tool = .pen {
        didSet {
            guard oldValue != selectedTool else { return }
            ActionRecorder.ifRecording { $0.model("selectedTool", String(describing: selectedTool)) }
        }
    }
    /// The tool to return to when the eyedropper finishes its one tap — see `Tool.eyedropper` and
    /// `CanvasManager+Eyedropper.swift`. Not `@Published`: nothing renders it, and republishing on a
    /// field the artist cannot see would invalidate every observer of this object for nothing.
    var toolBeforeEyedropper: Tool?
    /// Defaults key for `pencilOnlyDrawing`. About the user's *hardware*, not any one drawing, so it
    /// belongs to the app rather than a project's manifest.
    static let pencilOnlyDefaultsKey = "paintapp.pencilOnlyDrawing"

    // Absent a stored preference this is false: an ON-by-default gate would silently swallow every
    // finger touch on a device with no Apple Pencil, reading as "drawing is broken". Users with a
    // Pencil who want to rest a palm switch it on, and it stays on from then on.
    @Published var pencilOnlyDrawing: Bool = UserDefaults.standard.bool(forKey: CanvasManager.pencilOnlyDefaultsKey) {
        didSet {
            guard oldValue != pencilOnlyDrawing else { return }
            UserDefaults.standard.set(pencilOnlyDrawing, forKey: Self.pencilOnlyDefaultsKey)
            // Recorded because it is the gate that decides whether a `.direct` touch draws at all —
            // a recording showing finger touches that produce no stroke is explained entirely by
            // this line being `true` somewhere above them.
            ActionRecorder.ifRecording { $0.model("pencilOnlyDrawing", pencilOnlyDrawing ? "true" : "false") }
        }
    }

    /// Defaults key for `renderResolution`. About the *machine* and the artist's tolerance for a soft
    /// preview, not about any one drawing — the same argument `pencilOnlyDefaultsKey` makes, and the
    /// reason neither of these is in a project's manifest. A document carried to a faster iPad should
    /// not bring a downgraded canvas with it.
    static let renderResolutionDefaultsKey = "paintapp.renderResolution"

    /// How large the live canvas's composites are rendered — see `RenderResolution`, which carries
    /// what it does and does not reach.
    ///
    /// Absent a stored preference this is `.full`, and that direction is not arbitrary: the failure
    /// mode of defaulting to a reduced setting is an artist who never opens this menu concluding the
    /// app renders softly, with nothing on screen to suggest a control exists. The failure mode of
    /// defaulting to full is that they find the app slow on a heavy document — which is the state
    /// they were in before this setting existed, and which sends them looking.
    @Published var renderResolution: RenderResolution =
        UserDefaults.standard.string(forKey: CanvasManager.renderResolutionDefaultsKey)
            .flatMap(RenderResolution.init(rawValue:)) ?? .full
    {
        didSet {
            guard oldValue != renderResolution else { return }
            UserDefaults.standard.set(renderResolution.rawValue, forKey: Self.renderResolutionDefaultsKey)
            // Recorded for the reason `pencilOnlyDrawing` is: a recording whose canvas looks soft, or
            // whose composites are unexpectedly cheap, is explained entirely by this line.
            ActionRecorder.ifRecording { $0.model("renderResolution", renderResolution.rawValue) }
        }
    }

    /// The full brush preset currently active (shape, hardness, spacing, stabilization, dynamics,
    /// scatter/rotation jitter, grain, blend mode). `brushSize`/`brushOpacity` above stay separate
    /// published properties rather than folded into this because `SideToolbar`'s sliders bind
    /// directly to them and can move independently of whichever preset is selected — nudging a
    /// brush's size doesn't become a new saved preset.
    @Published var selectedBrush: Brush = BrushLibrary.softRound
    /// User-imported custom brushes, in the order added. In-memory only here — persisted across app
    /// launches via `ProjectStore`/`ProjectManifest`.
    @Published var customBrushes: [Brush] = []

    /// Every brush offered in the picker: the 5 built-in presets followed by user imports.
    var availableBrushes: [Brush] { BrushLibrary.defaults + customBrushes }

    /// Selects a brush preset as the active brush. Also re-baselines the live
    /// `brushSize`/`brushOpacity` from the brush's own defaults, and — only when the active tool is
    /// one that *has* a paint-brush preset — retargets `selectedTool` at it (`.pencil` for the
    /// Pencil preset, `.pen` otherwise).
    ///
    /// **The condition is `Tool.followsBrushPresetSelection`, not a list written here.** It was
    /// `selectedTool != .eraser && selectedTool != .fill`, and `.eyedropper` and `.text` were both
    /// added to `Tool` after that line without being added to it. See that property for what the
    /// `.text` case in particular was capable of stranding.
    func selectBrush(_ brush: Brush) {
        selectedBrush = brush
        brushSize = brush.size
        brushOpacity = brush.opacity
        if selectedTool.followsBrushPresetSelection {
            selectedTool = (brush.shape == .pencil) ? .pencil : .pen
        }
    }

    /// Adds a freshly-imported custom brush to the in-memory list and makes it the active brush.
    func addCustomBrush(_ brush: Brush) {
        customBrushes.append(brush)
        selectBrush(brush)
    }

    // MARK: - Eraser (functions like the brush tool — same shape/dynamics/spacing/grain — but
    // `BrushStamper` composites its stamps with `.destinationOut` instead of painting `brushColor`.
    // Kept as entirely separate published state from the paint brush's, so adjusting the eraser
    // never disturbs the paint brush, and switching tools never clobbers either one's settings.)

    /// The eraser's own brush preset. Defaults to Hard Round, the crisp/predictable shape most paint
    /// apps default their eraser to.
    @Published var selectedEraserBrush: Brush = BrushLibrary.hardRound
    /// Live-adjustable eraser diameter, separate from `brushSize`. Defaults larger than the paint
    /// brush's default — erasers are typically used broader than the pen/pencil.
    @Published var eraserSize: CGFloat = 20
    @Published var eraserOpacity: Double = 1.0

    /// Which of the three vector-eraser behaviours (see `VectorEraserMode` in Tool.swift) the eraser
    /// uses. Only consulted while the active layer is `.vector`: on a raster layer the eraser is a
    /// plain `.destinationOut` brush, so `EraserSettingsPanel` hides its picker there entirely.
    ///
    /// Lives alongside the shape/size/opacity state rather than inside `selectedEraserBrush` because
    /// it is not a property of the *stamp* — the same eraser preset cuts or shaves depending on
    /// this, and switching presets (which re-baselines size/opacity) must not silently change which
    /// mode you're erasing in. Also what `VectorEraserMode.isStabilized` reads, so
    /// `StrokeCanvasView` can decide per-mode whether to smooth the input path.
    ///
    /// Defaults to `.erase`, the mode that behaves like the raster eraser users already know.
    @Published var vectorEraserMode: VectorEraserMode = .erase

    // MARK: - Real-size stamp preview

    /// Which size slider, if any, currently has a finger on it — the whole visibility rule for the
    /// real-size stamp preview. See `SizePreview.swift`; raised on touch-down and lowered on lift by
    /// `View.sizePreviewSlider`, drawn by `DrawingView`'s overlay.
    @Published var sizePreview = SizePreviewVisibility() {
        didSet {
            guard sizePreview.isVisible != oldValue.isVisible else { return }
            if sizePreview.isVisible {
                sizePreviewRaiseCount += 1
                canvasDisplayScale.beginPublishing()
            } else {
                canvasDisplayScale.endPublishing()
            }
        }
    }

    /// How many times a preview has been raised this launch.
    ///
    /// **Observability, and nothing in the app reads it.** The preview exists only while a finger is
    /// down on the slider, and XCUITest cannot query the tree in the middle of its own gesture, so
    /// "did touch-*down* raise it?" — the owner's actual requirement, as distinct from "did dragging
    /// raise it" — is unanswerable from outside unless the fact outlives the lift. Same job
    /// `CanvasView.Coordinator.midStrokeEntryCount` does for the sandwich, and surfaced the same way:
    /// a marker in `DrawingView` that a test can read.
    @Published private(set) var sizePreviewRaiseCount: Int = 0

    /// Screen points per canvas point, live. Written by `CanvasView.Coordinator.publishCanvasState`,
    /// read by the stamp preview so its dab is the size the mark will actually land as rather than
    /// the size the slider says. Its own object rather than a property here — see
    /// `CanvasDisplayScale`, which explains why republishing this manager on every pinch frame is not
    /// an option.
    let canvasDisplayScale = CanvasDisplayScale()

    /// Every shape offered in the eraser's picker — the same built-ins as the brush picker (custom
    /// imported textures are a paint-brush-only feature for now).
    var availableEraserBrushes: [Brush] { BrushLibrary.defaults }

    /// Eraser analogue of `selectBrush`: re-baselines `eraserSize`/`eraserOpacity` from the chosen
    /// preset. Never touches `selectedTool` — unlike `selectBrush`, picking an eraser shape only
    /// makes sense while already erasing.
    func selectEraserBrush(_ brush: Brush) {
        selectedEraserBrush = brush
        eraserSize = brush.size
        eraserOpacity = brush.opacity
    }

    /// Which fill setting the fill tool's sideways (horizontal) drag adjusts, and which slider is shown
    /// highlighted in the Fill panel. Defaults to gap-closing; changing any panel slider re-points it at
    /// that setting (see `setFillSetting`).
    enum FillAxis { case gapClosing, threshold, edgeOverlap }
    @Published var fillSelectedAxis: FillAxis = .gapClosing

    /// Which kind of fill the fill tool performs — a type option under the one tool, not a second
    /// tool. `.lasso` takes its gesture from `SelectionOverlayView` instead of the fill press
    /// recognizer; see `CanvasView.Coordinator.updateSelectionOverlay`.
    @Published var fillMode: FillMode = .flood

    @Published var fillGapClosingDistance: CGFloat = 8
    /// Colour-distance threshold (0..1) above which a boundary counts as a wall. Higher = the fill
    /// spreads across bigger colour differences (fewer walls); lower = subtle borders stop it.
    @Published var fillThreshold: CGFloat = 0.15
    /// Edge Overlap for the **bucket** fill, in px: how far the finished region is grown under the
    /// wall it stopped against. The lasso keeps its own value below; they are separate settings
    /// wearing one slider, and `fillEdgeOverlap` is the accessor that picks between them.
    @Published var fillExpand: CGFloat = 2

    /// Edge Overlap for the **lasso** fill, and it defaults to the top of the range rather than to
    /// the bucket's 2.
    ///
    /// Under the anchoring the owner ruled on 2026-08-21 the lasso reads this slider as *how far out
    /// the colour reaches, with the top being the ink's own outer edge* — `fillEdgeRadius(lasso:)`
    /// turns it into an erosion of `upperBound - v`. Sharing the bucket's stored 2 would therefore
    /// ship a 4 px inward retreat by default: a pale seam all round the drawing, which is a version
    /// of the very complaint that opened the day. Per-mode storage is the smallest thing that stops
    /// one mode's sensible default from being the other's defect, and the slider itself is unchanged
    /// — it shows and writes whichever value belongs to the mode in front of the artist.
    @Published var fillLassoExpand: CGFloat = CanvasManager.fillExpandRange.upperBound
    /// Whether the canvas rectangle's edge bounds the fill the way a drawn line does. On by default,
    /// at the owner's request.
    ///
    /// **"The canvas edge" is the edge of the artwork rect — `canvasSize` inset by `canvasPadding` on
    /// every side — and not the edge of the pixel buffer.** With padding those are different
    /// rectangles, and confusing them is what made this option not work: the flood has always been
    /// clamped to the *buffer*, which is free and needs no option, but with a margin around the
    /// artwork that clamp sits `canvasPadding` px too far out and an enclosure that leans on the
    /// paper's border is open along that whole border.
    ///
    /// Two things happen when it is on, and only the first is what the artist means by the name:
    /// - the artwork rect's boundary **bounds the flood**, on both sides — a fill started on the
    ///   paper stops at the paper's edge instead of spreading onto the grey margin, and a fill
    ///   started on the margin stays there. This does not consult `fillGapClosingDistance` at all.
    /// - gap-closing may additionally **bridge to that edge**, so a boundary stroke ending a few px
    ///   short of it seals against it rather than letting the fill run around its end. This half is
    ///   the one that does nothing while `fillGapClosingDistance` is 0.
    ///
    /// At `canvasPadding == 0` the two rectangles coincide, the flood already could not leave the
    /// buffer, and the option reduces exactly to the bridge — byte-for-byte the behaviour it had
    /// before padding was considered. See `edgeBridge` in Fill.metal for both mechanisms and for why
    /// the boundary is a barrier between pixels rather than ink added to the wall mask.
    @Published var fillCanvasEdgeIsBoundary: Bool = true
    @Published var isFilling: Bool = false

    @Published var canvasBackgroundColor: Color = .white
    @Published var isCanvasBackgroundVisible: Bool = true

    @Published var fps: Int = 24 {
        didSet {
            guard fps != oldValue else { return }
            // Playback derives the playhead from elapsed time at the *current* rate, so a change
            // here is live. Re-basing is what keeps it from being retroactive: without it the whole
            // elapsed span would be re-divided by the new rate and the playhead would jump.
            rebasePlaybackClock()
        }
    }
    @Published var sceneFrameCount: Int = 12
    @Published var currentFrame: Int = 0 {
        didSet {
            if oldValue != currentFrame {
                handleActiveContextChanged()
                ActionRecorder.ifRecording { $0.model("currentFrame", String(currentFrame)) }
            }
        }
    }
    @Published var isOnionSkinEnabled: Bool = true
    /// Everything the onion-skin panel configures — how many skins, which side, how they are tinted
    /// and how opaque each one is. See `OnionSkinSettings`.
    ///
    /// **One value, not a dozen `@Published` properties**, because the render path compares the
    /// settings that produced the picture on screen against the settings now, and one `==` is what
    /// makes that comparison possible to get right. `onionSkinOpacity` used to be the whole of this
    /// and is gone: it is `onionSkin.linkedLevel`, which is the same number with a ramp behind it.
    @Published var onionSkin = OnionSkinSettings()
    @Published var isLoopEnabled: Bool = true
    /// The frame range playback loops within, set via the ruler's frame-number tap menu. Nil means
    /// "the whole scene"; highlighted blue across its span once set, independent of `isLoopEnabled`.
    @Published var loopStartFrame: Int?
    @Published var loopEndFrame: Int?

    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    /// The single global undo/redo stack for every mutating action in the document — strokes,
    /// fills, layer/folder structure, and animation-timeline edits alike. See `UndoHistory`.
    let history = UndoHistory()

    /// Records one undoable action against the global `history` and refreshes `canUndo`/`canRedo`.
    /// The shared entry point every call site (content edits and structural edits alike) funnels
    /// through, so undo/redo bookkeeping lives in exactly one place.
    func recordUndo(label: HistoryActionLabel, cost: Int = 0, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        history.record(.init(label: label, cost: cost, undo: undo, redo: redo))
        refreshUndoRedoState()
    }

    /// Rough retained-byte estimate for an image held by an undo/redo closure, used to feed
    /// `UndoHistory`'s memory-budgeted trimming. Precision doesn't matter here — this only needs to
    /// be in the right ballpark so a handful of full-canvas snapshots don't silently balloon memory.
    static func approximateImageCost(_ image: UIImage?) -> Int {
        guard let cg = image?.cgImage else { return 0 }
        return cg.width * cg.height * 4
    }

    /// Fires whenever a real drawing/fill interaction begins on the canvas — `DrawingView` uses this
    /// to auto-dismiss whatever top-bar dropdown is open, so the first touch both closes the menu
    /// and performs the stroke/fill, rather than being swallowed by a dismiss tap first.
    ///
    /// **Do not send this directly; call `canvasInteractionBegan()`.** The subject is still how the
    /// two `activePanel`-shaped consumers hear about a canvas touch (`activePanel` is view `@State`
    /// and cannot live here), but the *presentations* are now closed centrally, and a send that
    /// bypassed that would be exactly the hand-written half-fix this whole mechanism replaced.
    let interactionBegan = PassthroughSubject<Void, Never>()

    // MARK: - Open presentations

    /// Which of the app's bindable presentations are on screen right now.
    ///
    /// Maintained by `View.canvasPresentation(_:isPresented:)`, which is the only way a presentation
    /// in `CanvasPresentation` is allowed to be declared. Nothing in the app reads this to decide
    /// layout — it exists so the *rule* below has something to apply itself to, and so a device
    /// capture can say which panel was up when a stroke went wrong.
    @Published private(set) var openPresentations: Set<CanvasPresentation> = []

    func presentationDidAppear(_ presentation: CanvasPresentation) {
        openPresentations.insert(presentation)
    }

    func presentationDidDisappear(_ presentation: CanvasPresentation) {
        openPresentations.remove(presentation)
    }

    /// **The rule, in one place.** A touch on the canvas closes every open presentation that could be
    /// sitting over a live canvas, before that touch becomes a stroke.
    ///
    /// This is what used to be two hand-written subscribers clearing one named variable each, and
    /// what `CanvasPresentation.overlapsLiveCanvas` now answers for the whole closed set. Returns
    /// what it closed so a test can assert on it; the app ignores the value.
    @discardableResult
    func dismissPresentationsOverLiveCanvas() -> Set<CanvasPresentation> {
        let doomed = openPresentations.filter(\.overlapsLiveCanvas)
        guard !doomed.isEmpty else { return [] }
        openPresentations.subtract(doomed)
        return doomed
    }

    /// The single entry point for "a touch has landed on the canvas": closes every presentation over
    /// the live canvas, then tells the `activePanel` subscribers.
    ///
    /// Order is deliberate but not load-bearing — both halves are SwiftUI state writes that land in
    /// the same transaction. What *is* load-bearing is that there is one function, called from all
    /// **six** canvas-touch sites in `CanvasView`, rather than a `.send()` at each of them and a
    /// separately-remembered dismissal somewhere else. Named rather than counted, because a number
    /// on its own cannot be checked against anything:
    ///
    /// `strokeRecognizer.onAnyTouchBegan`, `handleMoveBoxCommit`, `handleTextPress`,
    /// `handleCatchAllTap`, `handleFillPress`, `handleEyedropperPress`.
    ///
    /// **This said "four" until 2026-08-26, and the miscount was itself a live defect.** The commit
    /// that wrote the contract above counted the sites on the base it was cut from, then rebased
    /// onto a `main` that had meanwhile gained `handleTextPress` — a fifth site, with a bare
    /// `.send()` of its own. It converted the four it knew about, git reported the merge clean
    /// because the two changes touched different lines, and a canvas text press went on signalling
    /// the top-bar dropdowns while closing no presentation for six days. Anyone auditing the sites
    /// against this comment counted four, found four, and stopped. `handleMoveBoxCommit` is the
    /// sixth, added 2026-08-22 and correct from the start.
    func canvasInteractionBegan() {
        // A touch that is about to become an edit ends playback. The playhead moving under the
        // artist's hand is the whole hazard: a tick lands mid-gesture, `currentFrame`'s `didSet`
        // commits the float and clears the selection through `handleActiveContextChanged`, and the
        // gesture finishes against a different cel than it started on.
        //
        // Here rather than in `beginCanvasEdit`, which would be the tempting chokepoint and is a
        // recursion: `handleActiveContextChanged` calls `beginCanvasEdit`, and it runs on every
        // playback tick, so playback would stop itself on its first frame.
        stopPlayback()
        dismissPresentationsOverLiveCanvas()
        interactionBegan.send()
    }

    // MARK: - Canvas-edit chokepoint

    /// Reentrancy depth for `beginCanvasEdit`. The commits it performs are themselves canvas edits
    /// (they register undo steps and, for a structural edit, run inside `withStructureUndo`), so
    /// without this the first call would recurse back into itself through its own bookkeeping.
    private var canvasEditDepth = 0

    /// Bakes any transient, not-yet-committed content into the document. **Every operation that
    /// changes what the canvas looks like calls this before it does anything else** — a stroke, an
    /// erase, a fill, making or acting on a selection, Move/Duplicate, any layer/folder/timeline
    /// edit, a canvas flip or resize, and saving.
    ///
    /// A transient smart shape or fill lives in this manager's private gesture state until baked. An
    /// edit that runs while one is pending would read layer content that doesn't include it, and the
    /// transient would then bake *later* at whatever geometry it holds by then, landing out of order
    /// on the undo stack — the root cause behind shape/fill "teleports back"/"duplicates"/
    /// "disappears then reappears" bugs. Hence a single chokepoint invoked from inside the mutating
    /// operations themselves, not a rule each view call site has to remember.
    ///
    /// Fill commits before shape: a shape stroke is drawn over the fill in the same cel, so this
    /// order preserves what the user was looking at. Both self-guard when nothing is pending.
    ///
    /// A floating Move/Duplicate piece is deliberately *not* settled here — Move stays engaged
    /// across its own nudges and mode changes, which are canvas edits in their own right. Use
    /// `commitAllInteractiveState()` where the tool itself is changing out from under the user.
    func beginCanvasEdit() {
        guard canvasEditDepth == 0 else { return }
        canvasEditDepth += 1
        defer { canvasEditDepth -= 1 }
        commitInteractiveFill()
        commitInteractiveShape()
        // Last in the list, because the text overlay draws above the shape overlay and committing
        // last preserves what the user was looking at. `ADD_TEXT.md` §1 "The bake trigger is one
        // line" — every existing caller of this method inherits the text bake with no per-tool
        // retrofit, which is the whole reason the chokepoint exists.
        commitInteractiveText()
    }

    /// `beginCanvasEdit()` plus settling a floating Move/Duplicate piece — for the points where the
    /// active tool is being replaced (tool switch, layer/frame change, save), at which a piece left
    /// floating would otherwise be stranded or silently discarded.
    func commitAllInteractiveState() {
        beginCanvasEdit()
        commitFloatingPieceIfNeeded()
        // A lasso move's float joins the raster piece at the same chokepoint, and that one line is
        // what covers tool switch, panel switch, save and backgrounding. Missing one of those is how
        // a float gets stranded — suppressed artwork in the saved document, rendering nowhere.
        commitVectorFloatIfNeeded()
    }

    /// Enters the text tool — the Actions menu's "Add Text" row, and the only way in.
    ///
    /// **The missing `commitAllInteractiveState()` above is the entire method**, which is why it is a
    /// method at all rather than `selectedTool = .text` written into a SwiftUI button. `Tool.text`'s
    /// panel is a settings panel: it routes through `TopToolbar`'s `toggleSettingsPanel` rule, which
    /// deliberately bakes nothing, because a panel whose sliders exist to re-run the still-adjustable
    /// thing in front of you turns into a panel of no-ops the moment opening it freezes that thing
    /// (that comment is written out at `Binding<ActivePanel>.toggleSettingsPanel`, and the fill is
    /// where it was learned). Text inherits the rule with its own version of the stake: from
    /// `ADD_TEXT.md` stage 1 onward there is a live text session behind this panel, and committing on
    /// the way in bakes the very text the artist opened the panel to restyle.
    ///
    /// Stating it here rather than at the call site is the `Tool.paintsOnCanvas` move: the answer
    /// belongs somewhere a headless test can reach it, because "somebody added a bake" is a silent
    /// change that no view-layer test in this project can see.
    ///
    /// Nothing pending is stranded by the omission. A transient fill or smart shape stays in its own
    /// tier and is baked by `beginCanvasEdit()` at the next real canvas edit, exactly as it is while
    /// any other settings panel is open — and `beginCanvasEdit()` is where `ADD_TEXT.md` puts
    /// `commitInteractiveText()`, so the text session joins the same chokepoint rather than getting
    /// one of its own.
    ///
    /// A floating Move/Duplicate piece does survive into text mode, and that is the one case worth
    /// naming: `beginCanvasEdit()` deliberately does not settle a piece, so once text starts placing
    /// pixels the stage that does needs to decide whether Move commits first. Today text places
    /// nothing, so there is nothing to decide yet.
    func enterTextMode() {
        selectedTool = .text
    }

    /// The banner currently across the top of the canvas, or nil for none — the owner's replacement
    /// for the three modal alerts that used to interrupt drawing (`CanvasNotice` carries why).
    ///
    /// **One optional in place of three `Bool`s, and the collapse is the point rather than a
    /// tidying.** The three flags were mutually exclusive in fact and independent in the type: the one
    /// call site that raised them (`CanvasView.handleCatchAllTap`) set exactly one, but nothing said
    /// so, so every reader had to check all three and any two of them could be true at once and stack
    /// two alerts. An optional says "at most one message, and here is which" in the type, which is
    /// also what a banner *is* — there is one strip of screen and it shows one sentence.
    ///
    /// Nil rather than a `Bool` beside a payload for the same reason `LayerFolder.effect` is optional:
    /// presence is the state, so there is no second field to fall out of step with.
    ///
    /// Written only through `raise(_:)` below, and cleared by whoever is presenting it — the view owns
    /// the timer, because how long a banner stays up is a presentation decision and the model has no
    /// business scheduling one. `CanvasNotice.duration` is the model's advice, not its behaviour.
    @Published var notice: CanvasNotice?

    /// The picture half of a lasso fill that enclosed nothing — the tinted collar and the loop the
    /// artist drew, for `SelectionOverlayView` to hold and fade (LASSO_FILL.md §7.2 and §7.4).
    ///
    /// Raised in the same breath as `.nothingEnclosed` and subject to the same once-per-streak latch,
    /// so the two are never out of step: the banner tells the artist *what*, this tells them *where*.
    /// See `LassoFillDiagnostic` for why it is not a `CanvasNotice` — it is registered to the artwork
    /// rather than to the screen, so it has to live inside the canvas's transformed container.
    ///
    /// Cleared by whoever presents it, exactly as `notice` is, and for the same reason: the deadline
    /// is a presentation decision. `LassoFillDiagnostic.duration` is this model's advice about it.
    @Published var lassoFillDiagnostic: LassoFillDiagnostic?

    /// Shows a banner, **minting a fresh one every time**.
    ///
    /// A new `id` per raise is the whole of this method. Assigning an equal value to an `@Published`
    /// property still publishes, but the two `CanvasNotice`s would be `==`, so a presenter driving its
    /// transition and its dismissal timer off `.onChange(of: notice)` sees nothing and the second tap
    /// on a layer that cannot be drawn on produces no banner at all — the artist taps, gets told,
    /// taps again a moment later and is told nothing. `CanvasNotice`'s own doc calls this out; this is
    /// where it is honoured.
    ///
    /// Re-raising while one is already up is therefore a restart rather than a no-op, which is the
    /// behaviour that matches what the artist did: they asked again.
    func raise(_ kind: CanvasNotice.Kind) {
        notice = CanvasNotice(kind)
    }

    /// A pinch-to-merge the layer panel is holding for confirmation rather than applying — set when
    /// `mergeLossKind` says the pair would lose something `mergeLayers` cannot preserve.
    ///
    /// **Not `CanvasNotice`.** That banner's whole design is to inform *after* the fact, with no way
    /// to gate or cancel an action already taken (its own doc: "does not take a tap to get rid of").
    /// This has to pause the merge until the artist answers, which is a different shape of interrupt
    /// — the owner's own request was a prompt that can be proceeded with or backed out of, not a
    /// sentence that fades on its own while the merge has already happened.
    ///
    /// `Identifiable` so `LayerPanel` can drive a SwiftUI `.alert(presenting:)` straight off it; a
    /// fresh `id` per raise for `CanvasNotice.raise`'s reason, though nothing here re-raises the same
    /// pair today.
    @Published var pendingMergeConfirmation: PendingMergeConfirmation?

    struct PendingMergeConfirmation: Identifiable, Equatable {
        let id = UUID()
        let firstID: UUID
        let secondID: UUID
        let lossKind: MergeLossKind
    }

    /// What a pinch-merge would lose, as answered by `mergeLossKind`. Two cases because they are
    /// genuinely different losses, not two phrasings of one — a `Bool` here is what forced an earlier
    /// version of this fix to exclude `.value` layers from the gesture rather than warn about them,
    /// which traded one silent-failure shape (a lossy merge with no warning) for another (a pinch that
    /// does nothing, on a layer combination that looked mergeable). Neither is acceptable on its own;
    /// this is what lets both be handled the same way — a confirmation whose wording matches the loss.
    enum MergeLossKind: Equatable {
        /// Either layer's blend mode is not Normal. `PixelOps.flatten` always composites with
        /// `.normal` (see `mergeLayers`), so the mode is silently reset — the owner's own described
        /// case, and the mildest of the two: content is unaffected, only how it combines with what
        /// was under it.
        case blendMode
        /// Either layer is `.value` (§4.4's grade or §4.5's flat colour) — a layer that holds no
        /// pixels of its own. `mergeLayers` rasterizes its cel, which is blank, so the merge discards
        /// the grade or colour entirely rather than merely re-blending it. Worse than `.blendMode`,
        /// and checked first by `mergeLossKind` for that reason: a pair with both problems reports
        /// the one the artist needs told about more urgently.
        case valueLayerContent

        /// The confirmation's message — worded to the actual loss, not to a generic "blend mode"
        /// guess. `CanvasNotice.message`'s pattern: wording lives with the case it belongs to, one
        /// place, rather than duplicated at every presenting call site.
        var confirmationMessage: String {
            switch self {
            case .blendMode:
                return "One of these layers uses a blend mode other than Normal. Merging will apply Normal blend mode to the result instead."
            case .valueLayerContent:
                return "One of these layers is a colour or adjustment layer with no pixels of its own. Merging will flatten it into the layer below, and it will no longer be editable as its own colour or adjustment."
            }
        }
    }

    /// Runs the merge a confirmed prompt named, then clears it.
    ///
    /// Re-reads nothing from the moment the prompt was raised except the two ids: `mergeLayers`
    /// re-validates both are still layers with an active cel at the current frame, so a merge
    /// confirmed after some other edit removed one of the pair fails the same guard an unconfirmed
    /// call would, rather than needing its own staleness check here.
    func confirmPendingMerge() {
        guard let pending = pendingMergeConfirmation else { return }
        pendingMergeConfirmation = nil
        mergeLayers(pending.firstID, pending.secondID)
    }

    /// Backs out of a pending merge confirmation without applying it — the prompt's "Cancel".
    func cancelPendingMerge() {
        pendingMergeConfirmation = nil
    }

    /// Ticks the debounce. The *what* travels in `pendingThumbnailRegens` rather than in the value,
    /// because `.debounce` keeps only the last element it saw — carrying `(layerIndex, celIndex)`
    /// directly would regenerate only the last-scheduled cel of a burst and leave earlier ones
    /// showing a stale thumbnail indefinitely. The queue is a set the debounced sink drains in full.
    private let thumbnailRegenSubject = PassthroughSubject<Void, Never>()

    /// Cels awaiting a debounced thumbnail regen, identified by `(layerID, celID)` rather than
    /// index — indices aren't stable across the debounce interval (deleting a layer or sorting cels
    /// renumbers them). Identity survives that; `flushPendingThumbnailRegens` resolves back to
    /// current indices at render time. A since-deleted cel resolves to nothing and is dropped.
    private var pendingThumbnailRegens: Set<CelLocation> = []

    struct CelLocation: Hashable {
        let layerID: UUID
        let celID: UUID
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        thumbnailRegenSubject
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.flushPendingThumbnailRegens()
            }
            .store(in: &cancellables)

        // **Undo gives bytes back under memory pressure, by trimming rather than clearing.**
        // PERFORMANCE.md item 13: undo was the only one of the app's five memory budgets with no
        // response to a memory warning at all — `PixelOps.rasterizeCache`, `CompositorMetalEngine`'s
        // upload cache and `MaskResolver.cache` each drop wholesale, and this one sat at its
        // high-water mark. See `UndoBudget.pressuredMaxCostBytes` for why a trim and not a clear.
        //
        // **Registered here rather than in `UndoHistory` itself**, unlike the three caches, which
        // each subscribe from their own initialiser. Two reasons, and both are about this class
        // rather than about style: `canUndo`/`canRedo` are `@Published` mirrors that `UndoHistory`
        // cannot reach, so a trim that empties the stack has to be followed by
        // `refreshUndoRedoState()` or the toolbar offers an Undo that does nothing; and
        // `UndoHistory` imports Foundation alone and stays headless — the UIKit dependency belongs
        // on the side that already has one.
        //
        // **A Combine subscription rather than the caches' `addObserver` block, and that is not
        // cosmetic.** Those three caches are process-lifetime singletons, so a subscription they
        // never remove is exactly as long-lived as they are. A `CanvasManager` is per-document and
        // the test target builds dozens, and `addObserver(forName:…)` hands back a token that stays
        // registered until it is passed to `removeObserver` — `[weak self]` stops the *object*
        // leaking while leaving a dead closure behind for every document ever opened. `cancellables`
        // already exists two lines up and unsubscribes on deinit, which is the whole fix.
        //
        // `receive(on: DispatchQueue.main)` because `UndoHistory` has no lock of its own (the caches
        // do): every other caller reaches it from the main actor, and a notification is the one entry
        // point that could arrive from anywhere. The main *queue* rather than the main run loop
        // because that also makes the hop observable in order — a test that posts the warning and
        // then enqueues its own block on the same serial queue is guaranteed to see the trim first,
        // where a run-loop source and a queue block have no defined ordering between them.
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.history.trimUnderMemoryPressure() > 0 { self.refreshUndoRedoState() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Layers

    /// Writes a layer-stack change into an active debug recording, with the resulting shape of the
    /// stack rather than only the fact that something happened — the stack is what decides which
    /// `StrokeGestureRecognizer` exists and which one the transform gestures wait on, so "now 3
    /// layers, active 2" is the part a reader needs. `internal`, not `private`: `CanvasManager` is
    /// split across extension files (see the note at the top of this file) and `addCel` calls this
    /// from `CanvasManager+Timeline`.
    ///
    /// Costs one static `Bool` load when nothing is recording; the string is never built.
    func recordLayerStackChange(_ what: String) {
        ActionRecorder.ifRecording {
            $0.model("layers", "\(what) — now \(layers.count) layers, active \(currentLayerIndex)")
        }
    }

    /// Where a newly added layer goes: **directly above the active layer, inside the active layer's
    /// own container.** Every `add*Layer` below routes through this, so "+" means one thing.
    ///
    /// The old answer was `layers.append(...)`, which is the top of the *root* container however deep
    /// the artist was working — add a layer while painting inside a group and the new one appeared at
    /// the very top of the document, outside the group, several rows away from what it was for. It
    /// also never set `parentFolderID`, so the escape was silent rather than a drag away.
    ///
    /// **Why `currentLayerIndex + 1` cannot break the contiguous-span invariant** (`layerStackRows`:
    /// a folder's layers occupy a contiguous span of `layers`, and a span *is* a subtree in array
    /// form). Write `a` for the active index and `p` for its `parentFolderID`. The insertion point is
    /// the boundary between `a` and `a + 1`. Take any folder `F` with a span:
    ///
    /// - If the boundary is **strictly inside** `F`'s span — `F.lower <= a` and `F.upper >= a + 1` —
    ///   then `a` is inside `F`'s span, so layer `a` is in `F`'s subtree, so `p` is `F` or something
    ///   nested in `F`. The new layer therefore belongs in `F`'s subtree too, and `F`'s span simply
    ///   grows by one and stays contiguous. This is the mid-folder case, and the nested case: every
    ///   folder the boundary is strictly inside is an ancestor of `p`, and *only* ancestors of `p`
    ///   can be strictly inside it.
    /// - If `F.upper == a` — the active layer is **last in its folder** — the boundary is `F`'s upper
    ///   edge. When `F` is `p` or an ancestor of `p` the span extends by one; otherwise `F` is
    ///   untouched and the new layer lands just above its block. Either way nothing is split.
    /// - If `F.lower == a + 1` — the active layer sits at root **immediately below a folder's span** —
    ///   the boundary is `F`'s lower edge, `F` is not an ancestor of `p`, and the new layer lands
    ///   below all of `F`. `F`'s span shifts up by one, intact.
    ///
    /// So the only folders whose spans the insert enters are exactly the ones the new layer is a
    /// member of, which is what contiguity asks. No clamp is needed here, unlike `restackLayer` —
    /// that one takes an anchor chosen by a *drag*, which can name a container the anchor is not in.
    ///
    /// **`layers` empty, or `currentLayerIndex == -1`** (which `deleteLayer` sets when the last layer
    /// goes): there is no active layer to be above, so the answer is the top of the root container —
    /// `layers.count`, a boundary no span can be strictly inside since every span ends at or before
    /// `layers.count - 1`, with no parent folder. For an empty `layers` that is index 0, the only
    /// legal index there is.
    private var newLayerPlacement: (index: Int, parentFolderID: UUID?) {
        guard layers.indices.contains(currentLayerIndex) else { return (layers.count, nil) }
        return (currentLayerIndex + 1, layers[currentLayerIndex].parentFolderID)
    }

    /// Inserts a freshly built layer at `newLayerPlacement` and makes it active. The one place the
    /// placement is spent, so the four `add*Layer` methods cannot drift on where "+" puts things.
    private func insertNewLayer(_ build: (UUID?) -> Layer) {
        let placement = newLayerPlacement
        layers.insert(build(placement.parentFolderID), at: placement.index)
        currentLayerIndex = placement.index
    }

    func addLayer(name: String? = nil) {
        withStructureUndo(label: .addLayer) {
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
            insertNewLayer { parent in
                Layer(id: UUID(), name: name ?? "Layer \(layers.count + 1)", opacity: 1.0,
                      isVisible: true, parentFolderID: parent, cels: [cel])
            }
        }
        recordLayerStackChange("added raster layer")
    }

    /// Adds a `.vector` layer: brush strokes are stored as geometry (see `VectorCanvas`) so they can
    /// be moved/rotated/scaled without resolution loss, and it can also host imported images/shapes.
    /// Its cel still keeps an (empty) `raster` so every cel-lifecycle path assuming a non-optional
    /// raster keeps working — live strokes just live in `vector` instead.
    func addVectorLayer(name: String? = nil) {
        withStructureUndo(label: .addVectorLayer) {
            let size = canvasSize ?? CGSize(width: 1, height: 1)
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: size), vector: .empty(size: size))
            insertNewLayer { parent in
                Layer(id: UUID(), name: name ?? "Vector \(layers.count + 1)", opacity: 1.0,
                      isVisible: true, kind: .vector, parentFolderID: parent, cels: [cel])
            }
        }
        recordLayerStackChange("added vector layer")
    }

    /// Adds a `.value` layer — the kind that draws nothing of its own (§4.5) — in whichever of its two
    /// modes `effect` selects.
    ///
    /// With `effect` nil it *is* one flat colour across the whole canvas, which is Photoshop's Solid
    /// Colour layer: an operand for a Mix node, and a flat background or tint that blends with what is
    /// under it like any other leaf. With `effect` set it is §4.4's stack-layer wrapper instead,
    /// grading everything beneath it *within its own container* — Photoshop's adjustment layer.
    ///
    /// **One constructor for both modes, replacing the separate `addEffectLayer`.** The two used to be
    /// separate kinds and so needed separate constructors; they are now one kind whose mode is a field,
    /// and a second constructor would be a second place that has to know which fields make which mode.
    ///
    /// **A fill is stamped in *both* modes**, and that is the creation half of `Layer.valueFill`'s
    /// asymmetry: a layer added as an effect and later flipped to flat colour has to arrive somewhere,
    /// and mid-grey is the somewhere. Defaulting to mid-grey at full alpha is deliberate in its own
    /// right — a flat-colour layer added at the top of the stack turns the canvas one flat colour,
    /// which is correct and is what Photoshop does, so the first thing the artist sees has to read as a
    /// deliberate colour rather than as a crash, and mid-grey is also the constant the Mix-node case
    /// wants.
    ///
    /// It gets an empty cel, for `addVectorLayer`'s reason — every cel-lifecycle path in the app
    /// assumes a layer has one, and a blank cel is free (§8.1). Nothing ever draws into it: in
    /// flat-colour mode the fill is resolved into the snapshot's source at `leafSnapshots`, and in
    /// effect mode the snapshot elides the layer's pixels entirely and the compositor reaches the leaf
    /// by its grade before it would look for a source.
    func addValueLayer(color: PaletteColor = ValueFill.defaultColor, effect: Effect? = nil,
                       name: String? = nil) {
        withStructureUndo(label: effect == nil ? .addValueLayer : .addEffectLayer) {
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1),
                          raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
            insertNewLayer { parent in
                Layer(id: UUID(),
                      name: name ?? Self.defaultValueLayerName(effect: effect, ordinal: layers.count + 1),
                      // A caller that supplied a name chose it, so the mode picker must not take it
                      // back — see `Layer.hasCustomName`. Every in-app route leaves this nil.
                      hasCustomName: name != nil,
                      opacity: 1.0, isVisible: true, kind: .value, effect: effect,
                      fill: ValueFill(color: color), parentFolderID: parent, cels: [cel])
            }
        }
        // One constructor, two modes (see the doc above), so one recorder line that names which —
        // the recorder's two separate `addEffectLayer`/`addValueLayer` lines collapsed with them.
        recordLayerStackChange(effect == nil ? "added value layer" : "added effect layer")
    }

    /// **The one generator for a value layer's automatic name**, so the name it is born with and the
    /// name `setLayerEffect` renames it to cannot drift apart. Both call it; nothing else spells these
    /// strings.
    ///
    /// The grade's own `displayName` in effect mode — "Gaussian Blur", "Brightness / Contrast" — and
    /// the numbered default in flat-colour mode.
    ///
    /// `ordinal` is **the stack's layer count including this layer**, which is what the creation site
    /// has always used (`layers.count + 1`, taken before the insert) and what the rename site passes
    /// (`layers.count`, taken after). It is decoration, not identity: nothing preserves the number a
    /// layer was born with — a restack or a deletion changes what any positional scheme would say — so
    /// a layer that leaves effect mode in a taller stack than it entered it comes back with a larger
    /// number. Worth stating because it looks like a bug and is not; the alternative, storing the
    /// birth ordinal to reproduce it, is a second field carrying nothing an artist can act on.
    static func defaultValueLayerName(effect: Effect?, ordinal: Int) -> String {
        effect?.displayName ?? "Value \(ordinal)"
    }

    /// Sets or clears the grade on a `.value` layer — **the mode picker's whole model half.** Passing
    /// an `Effect` puts the layer in effect mode; passing nil returns it to flat colour.
    ///
    /// Nothing happens on a layer that is not `.value`: the kind is what makes an effect live
    /// (`Layer.layerEffect`), so writing one onto a raster layer would store a value that never
    /// renders. That guard used to read `.compositing` and is the one line of this method the
    /// kind-retirement changed.
    ///
    /// **Clearing drops the effect and keeps the fill, and that asymmetry is deliberate** — see
    /// `Layer.valueFill`, which argues it. In short: `effect`'s presence *is* the mode, so it has to go
    /// for the layer to leave effect mode, while `fill` is inert storage in effect mode and keeping it
    /// is what makes flipping back restore the artist's colour instead of resetting it to grey. A mode
    /// picker that silently destroys the other mode's setting is not a mode picker.
    ///
    /// **And it destroys every keyframe track the new grade cannot drive**, which is the one place
    /// this method is *not* that asymmetry — `Layer.effectTracks` carries the argument for why a track
    /// is unlike a fill. `Effect.tracksAddressed(by:from:)` is the rule, shared with `setNodeEffect`
    /// and with the two blend-mode setters that clear a grade; it filters by parameter id, so
    /// re-picking the grade already set keeps every track and this method's own early-out above is not
    /// what makes that true.
    ///
    /// **Inside the `withStructureUndo` bracket, not through `setEffectParameterTrack`.** The bracket
    /// has already snapshotted `layers` and `effectTracks` is a field on `Layer`, so the clear rides
    /// the one step the pick was always going to cost. Routing it through the channel writer would
    /// record a second step and split one artist action in two — and would leave a reachable state in
    /// which the grade is back but its channels are not.
    ///
    /// **The layer renames itself to follow the mode**, unless the artist has named it (owner's call,
    /// asked and answered directly: "yea rename it"). Enter Gaussian Blur and the row reads "Gaussian
    /// Blur"; switch to Levels and it follows; go back to a flat colour and it is "Value n" again. The
    /// row is where an artist reads their stack, and a row reading "Value 3" for something that is
    /// actually a blur is the state `LayerStackCell.title(for:)` exists to prevent — the rename in the
    /// *other* direction matters just as much, since leaving "Gaussian Blur" on a layer that is now a
    /// flat colour is the identical lie told backwards.
    ///
    /// `Layer.hasCustomName` is what makes that safe; see it for why a flag and not a guess.
    ///
    /// **Inside the same `withStructureUndo` as the effect write, not after it.** An artist who picks a
    /// grade and presses undo once expects the grade *and* the name back — two steps would leave the
    /// name of an effect on a layer that no longer has one, which is the exact inconsistency the rename
    /// exists to prevent, reachable by pressing undo.
    ///
    /// One undo step per call, like every other discrete pick.
    func setLayerEffect(layerIndex: Int, to effect: Effect?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].kind == .value,
              layers[layerIndex].effect != effect else { return }
        withStructureUndo(label: effect == nil ? .valueLayerColor : .valueLayerEffect) {
            layers[layerIndex].effect = effect
            layers[layerIndex].effectTracks = Effect.tracksAddressed(by: effect,
                                                                     from: layers[layerIndex].effectTracks)
            // A held pre-keyframe value is per-channel storage under the same ids, so it goes by the
            // same rule — see `Layer.pendingBaselines`. The **marks** stay: a keyframe is a point in
            // time rather than a property of a grade, and the artist's timeline must not silently
            // empty because they changed which effect the layer runs.
            layers[layerIndex].pendingBaselines =
                Effect.channelEntriesAddressed(by: effect, from: layers[layerIndex].pendingBaselines)
            if !layers[layerIndex].hasCustomName {
                layers[layerIndex].name = Self.defaultValueLayerName(effect: effect, ordinal: layers.count)
            }
        }
    }

    /// **Writes, replaces or removes one keyframe track on one effect parameter** — KEYFRAMES.md
    /// stage 2's write half, and the whole-curve writer the graph editor edits through.
    ///
    /// A grade has two homes and so does this: `setEffectParameterTrack(folderID:parameterID:to:)` is
    /// the folder overload (§2.21, stage 2b), and it states only what differs rather than restating
    /// any of the rules below.
    ///
    /// Passing a curve stores it against `parameterID`; passing nil, or an empty curve, removes the
    /// track. Those two are deliberately the same thing: a curve with no keys evaluates to 0 at every
    /// frame and `Effect.resolved(atFrame:through:)` skips it, so storing one would be a channel that
    /// exists, animates nothing, and shows up in a channel list.
    ///
    /// **Deliberately not routed through `setLayerEffect`, and not through `withStructureUndo`.** That
    /// bracket takes a whole-document-structure snapshot — `layers`, `folders`, `viewPresets`,
    /// `motionGroups` and `guideStrokes`, twice, at a declared cost of 4096 — which is the right price
    /// for a discrete structural pick and the wrong one for a channel edit; an animated channel keys
    /// on every value change, and the recorder of §5 writes one per resampled stop.
    /// `setLayerEffect` is also *unusable* here for a second reason that has nothing to do with cost:
    /// it early-outs on `layers[i].effect != effect`, and the value a resolver hands back at a key's
    /// own frame is by construction equal to the value already stored. The whole write would vanish.
    ///
    /// So: one narrow closure pair over one parameter's curve, `cost` sized to the two curves it
    /// actually retains, and the layer addressed **by id inside the closures** rather than by the
    /// index passed in — a restack or a deletion between the edit and the undo moves the index, and
    /// `withStructureUndo`'s whole-array restore is what usually hides that.
    ///
    /// **Refused at the door rather than in the resolver**, on three counts, each returning false:
    /// a layer that is not grading at all (there is no parameter to address); an id that is not a
    /// parameter of the grade it *is* running; and a parameter this stage cannot drive — see
    /// `EffectParameter.isScalarAnimatable`, which names why for each of the nine. Storing one anyway
    /// would be a track that renders as nothing, which is the failure this stage is supposed to make
    /// impossible rather than merely unlikely.
    ///
    /// **Records nothing while an enclosing bracket is open**, which is `withStructureUndo`'s own rule
    /// and is right for the same reason: that bracket has already snapshotted `layers`, `effectTracks`
    /// is a field on `Layer`, so the enclosing step restores this edit along with everything else it
    /// spans. A second step here would split one artist action in two.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func setEffectParameterTrack(layerIndex: Int, parameterID: String, to curve: AnimationCurve?) -> Bool {
        guard layers.indices.contains(layerIndex),
              let parameter = layers[layerIndex].layerEffect?.parameters.first(where: { $0.id == parameterID }),
              parameter.isScalarAnimatable
        else { return false }

        let layerID = layers[layerIndex].id
        let before = layers[layerIndex].effectTracks[parameterID]
        let after = (curve?.isEmpty == false) ? curve : nil
        guard after != before else { return false }

        // Every document edit is a canvas edit: a pending shape/fill/text transient bakes first, as
        // its own earlier step, rather than being swallowed into this one. Re-entrant-safe, so calling
        // it inside an enclosing bracket that already did is free.
        beginCanvasEdit()
        writeEffectParameterTrack(after, parameterID: parameterID, layerID: layerID)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return true }
        recordUndo(label: .effectKeyframes,
                   cost: Self.trackUndoCost(before) + Self.trackUndoCost(after),
                   undo: { [weak self] in
                       self?.writeEffectParameterTrack(before, parameterID: parameterID, layerID: layerID)
                   }, redo: { [weak self] in
                       self?.writeEffectParameterTrack(after, parameterID: parameterID, layerID: layerID)
                   })
        return true
    }

    /// The one mutation both directions of the undo above go through, addressing the layer by id.
    private func writeEffectParameterTrack(_ curve: AnimationCurve?, parameterID: String, layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
        if let curve {
            layers[index].effectTracks[parameterID] = curve
        } else {
            layers[index].effectTracks.removeValue(forKey: parameterID)
        }
    }

    /// **The same write, on a folder's grade** — KEYFRAMES.md §2.21, stage 2b, and the folder twin of
    /// `setEffectParameterTrack(layerIndex:parameterID:to:)` above.
    ///
    /// Every rule that overload's doc comment states holds here verbatim and for the same reasons, so
    /// they are not restated: nil-or-empty removes the track, `withStructureUndo` is avoided for its
    /// cost *and* because its equality early-out would swallow the write, non-scalar parameters are
    /// refused at the door rather than in the resolver, and nothing is recorded while an enclosing
    /// bracket is open. What follows is only what genuinely differs.
    ///
    /// **A folder is addressed by id, not by an index, and that is the shape the rest of the file
    /// already uses** — `setNodeEffect`, `setMixBlendMode`, `setAlphaMask(_:forFolder:)` and
    /// `setFolderOpacity` all take a `UUID`, because `folders` carries no ordering an artist can see
    /// (§4.1: sibling order is derived from the layers each folder holds, not from this array). So the
    /// by-id addressing the layer overload has to reach for *inside* its undo closures, to survive a
    /// restack, is simply what a folder's whole signature is — there is no index here to go stale.
    ///
    /// **Presence is `effect != nil` outright, with no `folderEffect` accessor to ask.** A layer needs
    /// one because `kind` and `effect` are two fields that can disagree — a `.raster` layer carrying a
    /// stale grade must not start grading — while `LayerFolder.effect`'s presence *is* the effect-node
    /// form (`LayerFolder.effect`, `maxInputCount`), so there is no second field to reconcile. This
    /// therefore accepts an ordinary group as readily as a compositor node, exactly as `setNodeEffect`
    /// does and for its stated reason.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func setEffectParameterTrack(folderID: UUID, parameterID: String, to curve: AnimationCurve?) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folderID }),
              let parameter = folders[index].effect?.parameters.first(where: { $0.id == parameterID }),
              parameter.isScalarAnimatable
        else { return false }

        let before = folders[index].effectTracks[parameterID]
        let after = (curve?.isEmpty == false) ? curve : nil
        guard after != before else { return false }

        beginCanvasEdit()
        writeFolderEffectParameterTrack(after, parameterID: parameterID, folderID: folderID)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return true }
        recordUndo(label: .effectKeyframes,
                   cost: Self.trackUndoCost(before) + Self.trackUndoCost(after),
                   undo: { [weak self] in
                       self?.writeFolderEffectParameterTrack(before, parameterID: parameterID, folderID: folderID)
                   }, redo: { [weak self] in
                       self?.writeFolderEffectParameterTrack(after, parameterID: parameterID, folderID: folderID)
                   })
        return true
    }

    /// The one mutation both directions of the undo above go through, addressing the folder by id —
    /// re-resolved on every call rather than captured, because a folder deleted and restored between
    /// the edit and the undo is a different position in `folders` and the same id.
    private func writeFolderEffectParameterTrack(_ curve: AnimationCurve?, parameterID: String, folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        if let curve {
            folders[index].effectTracks[parameterID] = curve
        } else {
            folders[index].effectTracks.removeValue(forKey: parameterID)
        }
    }

    /// Roughly what one retained `AnimationCurve` costs `UndoHistory`'s byte budget.
    ///
    /// A key is one `Int`, five `Double`s and two small enum rawValues; 96 bytes is that with the
    /// array's own slack rounded up, and the 64 is the dictionary entry plus the id string. The number
    /// matters only in that it is *small*: a 40-key curve is under 4 KiB, so a session that keyframes
    /// heavily costs the history what a couple of structural edits do, rather than what one 16 MiB
    /// whole-cel snapshot does. `CanvasManager.approximateImageCost` is the same kind of estimate for
    /// the other extreme, and says the same thing about precision.
    private static func trackUndoCost(_ curve: AnimationCurve?) -> Int {
        guard let curve else { return 0 }
        return 64 + 96 * curve.keys.count
    }

    /// Renames a layer — **the Rename action's model half, and the one place `hasCustomName` is set.**
    ///
    /// It used to be a bare `canvasManager.layers[index].name = trimmed` in the panel, which is how the
    /// flag could have gone missing: a write nobody routes through cannot record that it happened. This
    /// mirrors `renameFolder`, including the undo step it always should have had.
    func renameLayer(at index: Int, to name: String) {
        guard layers.indices.contains(index) else { return }
        withStructureUndo(label: .renameLayer) {
            layers[index].name = name
            layers[index].hasCustomName = true
        }
    }

    /// Replaces the colour on a value layer, leaving every other property alone. Nothing happens on a
    /// layer that is not `.value` — the kind is what makes a fill live (`Layer.valueFill`), so writing
    /// one onto a raster layer would store a value that never renders. `setLayerEffect`'s rule.
    ///
    /// **Deliberately *not* also refused in effect mode**, which was the tempting symmetry. `fill` is
    /// the layer's stored colour in both modes and live in one; refusing to write it while an effect is
    /// on would mean the colour a flip-back restores could never be chosen in advance, and would make
    /// this setter and `Layer.valueFill` disagree about what the field is — one treating it as "the
    /// colour", the other as "the colour, when it counts". The panel hides the swatch in effect mode,
    /// which is where "you cannot pick this right now" belongs.
    func setLayerFill(layerIndex: Int, to fill: ValueFill) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].kind == .value,
              layers[layerIndex].fill != fill else { return }
        withStructureUndo(label: .valueLayerColor) {
            layers[layerIndex].fill = fill
        }
    }

    func deleteLayer(at index: Int) {
        guard layers.indices.contains(index) else { return }
        // Settle a float lifted from this layer *before* the layer goes, for `rasterizeLayer`'s
        // reason one door along. `handleActiveContextChanged` below does commit it, but by then the
        // layer is out of `layers`, so `vectorCanvas(ofFloat:)` resolves nothing and the suppression
        // is left on the canvas — which `captureStructure` above is still holding by reference, so
        // undoing the delete brings the layer back with its ink suppressed and nothing left alive to
        // clear it.
        commitVectorFloatIfLifted(fromLayer: layers[index].id)
        withStructureUndo(label: .deleteLayer) {
            // If the deleted layer is the active one, currentLayerIndex's *numeric* value may end up
            // unchanged (a later layer slides into the same slot) — didSet won't fire, so
            // handleActiveContextChanged() must be called explicitly to invalidate any selection/
            // floating piece keyed to the now-deleted layer's UUID.
            let deletingActiveLayerInPlace = index == currentLayerIndex
            let deletedID = layers[index].id
            layers.remove(at: index)
            dropMaskSource(.layer(deletedID))
            if layers.isEmpty {
                currentLayerIndex = -1
            // Deleting a layer *below* the active one shifts every later index down by one, so
            // currentLayerIndex must shift too, or "active" silently jumps to whatever slid into the
            // old index and subsequent strokes land on the wrong layer.
            } else if index < currentLayerIndex {
                currentLayerIndex -= 1
            } else if currentLayerIndex >= layers.count {
                currentLayerIndex = layers.count - 1
            } else if deletingActiveLayerInPlace {
                handleActiveContextChanged()
            }
        }
        recordLayerStackChange("deleted layer at \(index)")
    }

    // MARK: - Playhead

    /// **No ceiling.** The playhead goes wherever it is sent, and the scene grows to admit it.
    ///
    /// It used to clamp to `sceneFrameCount - 1`, which on a new document is 12 — so the ruler drew
    /// columns the playhead flatly refused to visit, because `TimelineTrackView.displayedFrameCount`
    /// always lays out a screenful past the right edge while this clamped to the scene. Scrubbing
    /// stopped dead partway across a track that visibly continued. The owner's report: "im not sure
    /// why I cannot move the time selection in the timeline past a certian frame (default is 12)".
    ///
    /// **Moving the playhead does not resize the scene.** An earlier version of this fix raised
    /// `sceneFrameCount` to admit the frame, reasoning that the field is the laid-out length of the
    /// timeline rather than the length of the animation and that playback bounds itself with
    /// `contentEndFrame`. That reasoning audited three readers — `effectiveLoopRange`, `stepFrame`,
    /// the frame label — and missed the four that matter most: **every cel constructor sizes a new
    /// layer's first cel with `frameCount: max(sceneFrameCount, 1)`** (`addLayer`, `addVectorLayer`,
    /// `addValueLayer`, and `SelectionModels`' duplicate). So a scrub out to frame 200 gave the next
    /// layer a 200-frame cel, that cel *became* `contentEndFrame`, and playback ran two hundred
    /// frames of empty track — the very bug `contentEndFrame` was introduced to fix, back at a
    /// larger number, and persisted to the manifest by `ProjectStore`.
    ///
    /// The lesson worth keeping: `sceneFrameCount` is not display state. It is an input to cel
    /// creation, so anything that writes it is authoring the document, and only an edit may do that.
    /// Every other ratchet site raises it *because a cel now reaches that frame*; the playhead
    /// reaching a frame is not a cel reaching it.
    func goToFrame(_ frame: Int) {
        currentFrame = max(0, frame)
    }

    /// `loopStartFrame`/`loopEndFrame` clamped into the current scene length and ordered — the scene
    /// may have shortened since a range was set, and the two markers can be set in either order.
    var effectiveLoopRange: ClosedRange<Int> {
        let maxFrame = max(sceneFrameCount - 1, 0)
        let start = min(max(min(loopStartFrame ?? 0, loopEndFrame ?? maxFrame), 0), maxFrame)
        let end = min(max(max(loopStartFrame ?? 0, loopEndFrame ?? maxFrame), start), maxFrame)
        return start...end
    }

    func setLoopStart(_ frame: Int) {
        let end = loopEndFrame ?? max(sceneFrameCount - 1, 0)
        loopStartFrame = min(frame, end)
        loopEndFrame = max(frame, end)
    }

    func setLoopEnd(_ frame: Int) {
        let start = loopStartFrame ?? 0
        loopStartFrame = min(start, frame)
        loopEndFrame = max(start, frame)
    }

    func clearLoopRange() {
        loopStartFrame = nil
        loopEndFrame = nil
    }

    /// Step/step-back, wrapping the same way playback does so the two agree about where the
    /// animation ends — with no markers set that is the last drawn frame, not the last laid-out one
    /// (see `contentEndFrame`).
    ///
    /// Only the looping branch wraps. With looping off this walks out into the empty track without a
    /// ceiling, which is how the playhead reaches a blank frame to start a new block on in the first
    /// place; clamping it to the content would make those frames unreachable from the transport
    /// buttons.
    func stepFrame(by delta: Int) {
        var next = currentFrame + delta
        if isLoopEnabled {
            let start = playbackStartFrame
            let end = playbackEndFrame
            if next < start { next = end }
            if next > end { next = start }
            currentFrame = next
            return
        }
        // Not clamped to the scene either — `goToFrame` is the one place the playhead's bounds are
        // decided, so the transport button and a ruler scrub cannot disagree about where the timeline
        // ends. It walks out into the empty track and the track grows to meet it.
        goToFrame(next)
    }

    // MARK: - Playback bounds
    //
    // An unset loop marker means "the end of the *animation*", not "no boundary": the first frame
    // stands in for a missing loop start and the last drawn frame for a missing loop end. That
    // substitution lets both modes share one rule instead of each needing a special case for unset
    // markers. Set both markers and they become the animation window outright, content or no.

    /// One past the last frame any layer actually has a block on — where the animation ends, as
    /// opposed to where the *track* ends.
    ///
    /// `sceneFrameCount` is not that number and never was. It is the laid-out length of the
    /// timeline: it starts at 12 on a new document and only ever ratchets *upward* (every cel
    /// creator and resizer does `max(sceneFrameCount, …)`, nothing lowers it). So a two-frame
    /// animation still reported a 12-frame scene, and playback with no markers ran out over ten
    /// empty frames before wrapping — the "loops from an arbitrary frame like 12" report.
    ///
    /// Zero when no layer holds a cel at all, which `contentEndFrame`'s callers turn back into
    /// frame 0 rather than a negative bound.
    var contentEndFrame: Int {
        layers.flatMap(\.cels).map(\.endFrame).max() ?? 0
    }

    /// Whether the user has placed either loop marker.
    var hasLoopBoundary: Bool { loopStartFrame != nil || loopEndFrame != nil }

    /// The frame playback runs from: the loop start, or the first frame.
    var playbackStartFrame: Int { hasLoopBoundary ? effectiveLoopRange.lowerBound : 0 }

    /// The last frame playback shows: the loop end, or the last frame that has a drawing on it.
    var playbackEndFrame: Int {
        hasLoopBoundary ? effectiveLoopRange.upperBound : max(contentEndFrame - 1, 0)
    }

    /// Where the playhead should sit when the play button is pressed. Pressing play while parked at
    /// (or past) the end replays from the start rather than stopping on the spot.
    func playbackEntryFrame() -> Int {
        (currentFrame < playbackStartFrame || currentFrame >= playbackEndFrame) ? playbackStartFrame : currentFrame
    }

    /// Advances the playhead `count` frames of playback. Returns false when playback has run off the
    /// end and should stop — which only ever happens with looping off.
    ///
    /// `count` is a number of *frames of elapsed time*, not a number of ticks — see `PlaybackClock`.
    /// A tick that arrives two frame intervals late passes 2 and the animation skips a frame, which
    /// is the point: the alternative is playing back in slow motion whenever the main thread is busy.
    /// A refused advance still leaves the playhead on the end frame it reached, and `count` frames
    /// cost **one** write to `currentFrame` — whose `didSet` runs `handleActiveContextChanged`, which
    /// is not free — rather than one per frame stepped over.
    ///
    /// The walk is the single-frame rule applied `count` times and deliberately not a second,
    /// parallel account of where playback wraps and stops;
    /// `testAdvancingByNIsExactlyNSingleAdvances` pins that against the characterizations above.
    @discardableResult
    func advancePlayback(by count: Int = 1) -> Bool {
        // Hoisted: `playbackEndFrame` walks every cel of every layer, and neither bound depends on
        // where the playhead is.
        let start = playbackStartFrame
        let end = playbackEndFrame
        let looping = isLoopEnabled
        var remaining = max(count, 0)
        var frame = currentFrame
        var taken = 0
        var ranOff = false
        while taken < remaining {
            // Inside the loop range the walk is periodic, so an arbitrarily long catch-up folds to
            // at most one cycle of real work. Outside it the walk is not yet periodic — parked
            // before the start it plays *forward* into the range, and past the end it snaps in on
            // the first step — but reaching the range costs at most the scene's length in steps.
            if looping, frame >= start, frame <= end {
                remaining = taken + (remaining - taken) % (end - start + 1)
                if taken >= remaining { break }
            }
            guard frame < end else {
                guard looping else {
                    ranOff = true
                    break
                }
                frame = start
                taken += 1
                continue
            }
            frame += 1
            taken += 1
        }
        if frame != currentFrame { currentFrame = frame }
        return !ranOff
    }

    // MARK: - The playback clock
    //
    // The clock lives here and not on `AnimationTimeline`, which owned it as two `@State`s and a
    // `Timer` until 2026-09-01. Four defects came with that and all four are structural rather than
    // fixable in place: the timer ran in the default run-loop mode, so playback stalled during any
    // scroll or drag; `1.0 / fps` was captured into the timer's interval when play was pressed, so
    // a rate change mid-play did nothing; there was no wall clock, so a late tick *stretched* time
    // instead of skipping and the clock drifted; and nothing outside that one view could see that
    // playback was running. The last is the one that blocked work rather than merely being wrong —
    // a background baker cannot prebake ahead of a playhead it cannot observe (RENDER §3.6-3.7),
    // and audio (TODO 28) and keyframe scrubbing (KEYFRAMES §5) need the same hoist.

    /// Whether the animation is playing. Observable, so anything in the app can ask — which is the
    /// half of this that the view could not provide at all.
    @Published private(set) var isPlaying: Bool = false

    /// The wall clock playback derives its position from, injectable so a logic test can hand it
    /// numbers rather than sleeping through real frames.
    ///
    /// Foundation only. RENDER §2.6 rules out anything one OS can signal and another cannot, which
    /// is why this is not `CACurrentMediaTime` or a `CADisplayLink`.
    var playbackNow: () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }

    private var playbackClock: PlaybackClock?
    private var playbackTimer: Timer?

    /// How much faster than the frame rate the tick source asks. The tick only sets the *resolution*
    /// of the answer — `PlaybackClock` decides how many frames are actually due — but a tick source
    /// running at exactly `1/fps` lands 0 frames on one fire and 2 on the next as the two clocks
    /// beat against each other, which reads as judder. Oversampling costs a handful of integer
    /// comparisons a second and removes the beat.
    private static let playbackTickOversample: Double = 3

    /// Play, from `playbackEntryFrame()`.
    func play() {
        guard !isPlaying else { return }
        // Through `goToFrame`, which is the one place the playhead's bounds are decided.
        goToFrame(playbackEntryFrame())
        playbackClock = PlaybackClock(startedAt: playbackNow())
        isPlaying = true
        schedulePlaybackTimer()
    }

    /// Stop, from wherever. Idempotent — `@Published` fires on every write, equal or not, so the
    /// guard is what keeps a stop from a view that is merely disappearing off the invalidation path.
    func stopPlayback() {
        guard isPlaying else { return }
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackClock = nil
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { stopPlayback() } else { play() }
    }

    /// Hands the playhead whatever frames the wall clock says are due, and stops playback if that
    /// ran off the end. Called by the tick source, and directly by tests driving `playbackNow`.
    func tickPlayback() {
        guard isPlaying, var clock = playbackClock else { return }
        let due = clock.take(at: playbackNow(), fps: fps)
        playbackClock = clock
        guard due > 0 else { return }
        if !advancePlayback(by: due) { stopPlayback() }
    }

    private func schedulePlaybackTimer() {
        playbackTimer?.invalidate()
        let interval = 1.0 / (Double(max(fps, 1)) * Self.playbackTickOversample)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.tickPlayback()
        }
        // `.common`, not the default mode: a timer in the default mode does not fire while a scroll
        // view or a drag gesture is tracking, so playback used to freeze for as long as the artist
        // held a finger on the timeline.
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func rebasePlaybackClock() {
        guard isPlaying else { return }
        playbackClock?.rebase(at: playbackNow())
        // The tick source's interval is derived from the rate, so it is re-cut with it.
        schedulePlaybackTimer()
    }

    // MARK: - Drawing updates

    // Live strokes are stamped directly into the `RasterLayerTexture` instance already referenced by
    // `Cel.raster` (a shared class, not a value type), so there's no separate "push the finished
    // drawing back into the model" step mid-stroke — `strokeEnded` below is the only hook the
    // drawing surface needs, to trigger a thumbnail regen and force the `@Published layers` diff
    // that in-place texture mutation alone wouldn't otherwise produce.

    /// Called once per completed stroke. Any pending shape/fill was already baked at stroke *start*
    /// (`beginCanvasEdit`), so there's nothing transient left to settle, only the thumbnail to
    /// refresh. Goes through the debounce rather than rasterizing on the spot: regenerating a
    /// 2048x2048 cel's thumbnail costs ~4.3 ms against a ~14 ms stroke, so a burst of quick strokes
    /// pays it once 400 ms after the user stops instead of once per stroke.
    ///
    /// Safe to defer because nothing reads `Cel.thumbnail`/`Layer.thumbnail` except the timeline and
    /// layer-panel views. In particular **saving does not** — `ProjectStore.Snapshot` renders its
    /// own gallery thumbnail and stores each cel's pixels directly, so a pending regen can't put a
    /// stale image on disk. (`flushPendingThumbnailRegens()` exists for callers needing sync
    /// freshness.)
    func strokeEnded(layerIndex: Int, celIndex: Int) {
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    func scheduleThumbnailRegen(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return }
        scheduleThumbnailRegen(layerID: layers[layerIndex].id,
                               celID: layers[layerIndex].cels[celIndex].id)
    }

    /// The ID-based entry point every scheduled regen funnels through — for undo/redo closures,
    /// which can fire long after other structural edits have shifted indices.
    func scheduleThumbnailRegen(layerID: UUID, celID: UUID) {
        pendingThumbnailRegens.insert(CelLocation(layerID: layerID, celID: celID))
        thumbnailRegenSubject.send(())
    }

    /// Renders every queued thumbnail immediately and empties the queue. Called by the debounced
    /// sink; also the escape hatch for anything that needs `Cel.thumbnail` guaranteed current right
    /// now rather than up to 400 ms from now.
    func flushPendingThumbnailRegens() {
        guard !pendingThumbnailRegens.isEmpty else { return }
        let pending = pendingThumbnailRegens
        pendingThumbnailRegens.removeAll()
        for location in pending {
            guard let layerIndex = layers.firstIndex(where: { $0.id == location.layerID }),
                  let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == location.celID }) else { continue }
            regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
        }
    }

    /// Deliberately *not* debounced: this is a whole-project fan-out over every cel (project load,
    /// canvas resize) and every thumbnail genuinely has to be rendered. Queueing would only defer
    /// the same work by 400 ms while leaving the timeline blank. Any queued regen is redundant once
    /// this has run, so the queue is cleared.
    func regenerateAllThumbnails() {
        pendingThumbnailRegens.removeAll()
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
            }
        }
    }

    /// How many thumbnail re-renders have actually run (reached the renderer, not bailed on a stale
    /// index). Instrumentation for `PerfBaselineTests` — thumbnail regeneration rasterizes the whole
    /// cel, a real cost. Never read by the app itself; not `@Published` so reading it can't drive a
    /// view update.
    private(set) var thumbnailRegenerationCount = 0

    /// Records renders performed by the deferred backfill, which happen off the main actor and so
    /// cannot bump the counter where they run.
    ///
    /// Kept on the *same* counter deliberately. It means "cel rasterizes charged to thumbnails", and
    /// a second counter would make the blocking and deferred opens incomparable — which is exactly
    /// the comparison item 9(c) exists to make.
    func recordThumbnailRenders(_ count: Int) { thumbnailRegenerationCount += count }

    /// The deferred thumbnail pass started by `ProjectStore.loadInBackground`, if one is running —
    /// see `startThumbnailBackfill` (PERFORMANCE.md item 9(c)). Held so a second load can cancel the
    /// first's, and so a test can await it rather than sleep. Not `@Published`: nothing draws from it.
    var thumbnailBackfillTask: Task<Void, Never>?

    /// The timeline/layer-panel thumbnail box. Named because two renderers now fit into it — the
    /// synchronous regen below and the deferred backfill in `CanvasManager+Document.swift` — and a
    /// second literal is how they would start disagreeing about what a thumbnail is.
    static let celThumbnailSize = CGSize(width: 120, height: 120)

    /// The box a cel is flattened into on the way to `celThumbnailSize`.
    ///
    /// **A thumbnail must never mint a native-size entry in `PixelOps.rasterizeCache`.**
    /// `RasterizeKey` carries width and height, so a flatten at canvas size is a *different* entry
    /// from the one the sandwich holds for the same cel at its clamped render size. Both are
    /// canvas-sized — 64 MiB apiece at 4096², where six layers of sandwich already need 201 MiB
    /// against a 192 MiB budget — so the two sets evicted each other and every rebuild ran cold. At
    /// 2048×1024 the same pair is 48 MiB and nothing showed, which is why this was a large-canvas
    /// symptom.
    ///
    /// Four times the tile on the long side is more resolution than a 120 pt tile can show, and it
    /// bounds the entry at ~0.9 MiB whatever the canvas is. The downsample in `ThumbnailRenderer`
    /// still runs from the true `canvasSize`, so the tile's own dimensions are unchanged.
    static let celThumbnailRasterBound = CGSize(width: 480, height: 480)

    /// One cel's thumbnail pixels. **Pure, and reachable from any thread**: it reads the cel it is
    /// handed and nothing else, which is what lets the deferred backfill render off the main actor
    /// through the *same* code the synchronous path uses. Every tier it touches serialises on its own
    /// lock — see `PixelOps.parallelMap`, which makes the same argument at length.
    ///
    /// **`derived` is the `ContentProvider` seam** (VECTOR_INTERPOLATION item 18) — resolved by the
    /// caller, since this must stay pure. It is also in the *gate*: a `.generate` in-between has
    /// neither `bakedImage` nor `vector`, so without this clause it took the raster branch below and
    /// rendered a blank timeline thumbnail for a frame the canvas was showing ink on.
    static func celThumbnailImage(for cel: Cel, canvasSize: CGSize,
                                  derived: DerivedCelContent? = nil) -> UIImage {
        if derived != nil || cel.bakedImage != nil || cel.vector != nil {
            // PixelOps.rasterize folds fillImage/bakedImage/raster/vector into one image already —
            // into `celThumbnailRasterBound` rather than the whole canvas, which is what keeps its
            // memo entry out of the compositor's way (see the constant).
            let flattened = PixelOps.rasterize(cel: cel,
                                               canvasSize: RenderRequest.renderSize(fitting: canvasSize,
                                                                                    within: celThumbnailRasterBound),
                                               derived: derived)
            return ThumbnailRenderer.render(flattened, canvasSize: canvasSize,
                                            thumbnailSize: celThumbnailSize)
        }
        return ThumbnailRenderer.render(cel.raster, fillImage: cel.fillImage,
                                        canvasSize: canvasSize, thumbnailSize: celThumbnailSize)
    }

    func regenerateThumbnail(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvasSize else { return }
        thumbnailRegenerationCount += 1
        let cel = layers[layerIndex].cels[celIndex]
        // A cel's thumbnail is the picture at the frame that cel *starts* on. That is the only
        // honest answer for a held cel — one tile stands for the whole block — and it is the frame
        // `CelBlockView` draws the tile against.
        let image = Self.celThumbnailImage(for: cel, canvasSize: canvasSize,
                                           derived: derivedCelContent(for: cel, atFrame: cel.startFrame))
        installThumbnail(image, layerIndex: layerIndex, celIndex: celIndex)
    }

    /// Puts a rendered thumbnail on its cel, and on the layer too when that cel is the one the
    /// playhead is over. The single writer, so the deferred backfill cannot install one differently
    /// from the synchronous path.
    func installThumbnail(_ image: UIImage, layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].thumbnail = image
        if activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) == celIndex {
            layers[layerIndex].thumbnail = image
        }
    }

    // MARK: - Fill state (the operations live in CanvasManager+Fill.swift)
    //
    // Stays here rather than moving with the code that drives it: extensions can't declare stored
    // properties, and none can be `private` since CanvasManager+Fill.swift reads/writes all of them.

    /// Slider ranges for the two fill settings, mirrored from `FillSettingsPanel`. The interactive
    /// drag clamps to these and maps a full sweep onto a fixed amount of finger travel.
    static let fillGapRange: ClosedRange<CGFloat> = 0...40
    static let fillThresholdRange: ClosedRange<CGFloat> = 0...1
    static let fillExpandRange: ClosedRange<CGFloat> = 0...6

    /// Serial queue that owns every fill computation for the active gesture. Keeping it serial means
    /// the GPU session and render bookkeeping below are only ever touched from one thread, letting
    /// `drainFillWork` coalesce a burst of drag updates into a single render of the latest params.
    let fillQueue = DispatchQueue(label: "com.paintsoftware.interactiveFill", qos: .userInteractive)
    let fillLock = NSLock()
    var fillPending = FillKey(gap: 0, threshold: 0, edge: 0, edgeIsWall: true, inset: 0)
    var fillRendered = FillKey(gap: .min, threshold: .min, edge: .min, edgeIsWall: false, inset: .min)
    var fillWorkerScheduled = false

    /// **Which gesture `fillQueue` is working for.** Bumped by every `begin*Fill`, and again by
    /// `commitInteractiveFill`/`cancelInteractiveFill` when the gesture retires. Written on the main
    /// thread under `fillLock`, read on `fillQueue` under it, read freely on main (the only writer).
    ///
    /// It exists because a *second* fill is the case the old invariant did not cover — the owner's
    /// *"using the fill tool more than once breaks it sometimes"*. A worker whose gesture has been
    /// replaced must not claim the new gesture's key as rendered, must not render, and must not
    /// publish; `drainFillWork` checks this at each of those three points. See
    /// `CanvasManager+Fill.swift`'s `beginFillGeneration` / `FillGestureContext`.
    var fillGeneration: UInt64 = 0

    /// The live gesture's latest render, stored by `drainFillWork` on `fillQueue` under `fillLock`
    /// *before* the hop to main that installs it — so `commitInteractiveFill` can bake a fill whose
    /// pixels exist but have not reached the main thread yet. See `FillRenderResult`.
    var fillRenderedRegion: FillRenderResult?

    /// Gesture context. `fillSession`/`fillSeedColor`/`fillGestureLoopPath` are only touched on
    /// `fillQueue`; everything below is main-thread only. **Nothing here is read from `fillQueue`** —
    /// a worker gets what it needs as an immutable `FillGestureContext` snapshot instead, because the
    /// old arrangement ("set on the main thread before any `fillQueue` work runs, then only read
    /// after") is false the moment a second gesture starts while the first is still on the GPU.
    var fillSession: MetalFillSession?

    /// The loop the live lasso gesture drew, in canvas coordinates — kept so an empty result can
    /// redraw the artist's own fence (LASSO_FILL.md §7.4). Nil for a bucket fill.
    ///
    /// **Written beside `fillSession`, on `fillQueue`, and that pairing is the point**: the path and
    /// the session are two halves of one gesture, and the queue is serial, so a second loop drawn
    /// while the first is still rendering cannot pair one gesture's fence with the other's result.
    /// Setting it on the main thread would allow exactly that.
    var fillGestureLoopPath: CGPath?
    var fillSeedColor: SIMD4<Float> = .zero
    /// True while an interactive fill exists — either a finger is dragging it, or it's in the
    /// post-lift *adjustable* state (session still alive, preview shown, not yet baked). Cleared
    /// only on commit or cancel. Main-thread only.
    var fillGestureActive = false
    /// True only while a finger is actively pressing/dragging the fill; false in the adjustable state.
    var fillFingerDown = false         // main-thread only
    /// Whether the live fill came from a drawn loop rather than a tap.
    ///
    /// **No longer just the undo label.** It also clamps Edge Overlap to 0 (`currentFillKey`), and
    /// downstream of it the session runs an entirely different algorithm — ring seed, loop-confined
    /// flood, invert, empty check (see `beginInteractiveLassoFill` and LASSO_FILL.md §6).
    var fillGestureIsLasso = false     // main-thread only
    /// Whether the artist has already been told this lasso gesture encloses nothing. Latches the §7
    /// signal to once per empty *streak*, so dragging a slider through a run of empty results does
    /// not flicker the banner; cleared as soon as a fill lands, or when a new gesture starts.
    ///
    /// **`fillQueue`-owned, not main-thread**, and that is load-bearing rather than incidental: the
    /// §7.2 collar tint is built from the session's buffers on that queue, so the decision *whether
    /// to build it* has to be taken there too. Latching on main would mean rendering a canvas-sized
    /// tint on every empty render just so the main thread could throw all but the first away — a
    /// full-canvas allocation per slider tick, for a picture nobody sees. One latch rather than two
    /// because two would drift, and the drift would show as a banner without its tint.
    var lassoFillReportedEmpty = false  // fillQueue only
    /// True when a fill exists and the finger is NOT pressing (adjustable state). The coordinator checks
    /// this in the fill-press handler so that a two-finger pan's first touch doesn't commit the fill.
    var isFillInAdjustableState: Bool { fillGestureActive && !fillFingerDown }
    /// Last painted region (premultiplied RGBA) + its dimensions, kept so a re-tap can be hit-tested
    /// against the pixels the current fill already covers (`isPointInPendingFill`). Main-thread only.
    var fillLastRegionRGBA: [UInt8]?
    var fillLastRegionW = 0
    var fillLastRegionH = 0
    var fillGestureSeed: (x: Int, y: Int) = (0, 0)
    var fillGestureColor: SIMD4<Float> = .zero   // premultiplied 0..1
    var fillGestureFillColor: CodableColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    // IDs, not indices: the fill can stay adjustable across other edits, so the layer/cel it
    // targets must be re-resolved by identity rather than trusting a captured index to still
    // point at the same one (see `registerUndoableCelChange` for the same principle).
    var fillGestureLayerID: UUID?
    var fillGestureCelID: UUID?
    var fillGestureBaseBaked: UIImage?  // layer's baked pixels before this gesture (undo/composite base)

    /// Records the artist's own answer for whether a layer bounds the fill (§6.6) — written by the
    /// row's drop button, which is the only control that sets it.
    ///
    /// **Writes the override even when the effective value doesn't move.** Setting a visible layer to
    /// "yes" looks like a no-op today and is the difference between it staying a reference when it is
    /// hidden later and silently dropping out; the guard is on the *decision*, not on the value the
    /// decision currently produces.
    func setFillReference(layerIndex: Int, isReference: Bool) {
        guard layers.indices.contains(layerIndex) else { return }
        guard layers[layerIndex].fillReferenceOverride != isReference else { return }
        withStructureUndo(label: .fillReference) {
            layers[layerIndex].fillReferenceOverride = isReference
        }
    }

    /// Flips a layer's visibility. A layer nobody has decided about follows visibility as its fill
    /// boundary too — that fall-out is `Layer.isFillReference`'s own default (§6.6) rather than a
    /// write from here, which is what keeps it from overwriting a choice the artist did make.
    /// When a view preset is active, the change is saved into that preset automatically.
    func toggleLayerVisibility(layerIndex: Int) {
        guard layers.indices.contains(layerIndex) else { return }
        withStructureUndo(label: .toggleVisibility) {
            layers[layerIndex].isVisible.toggle()
            saveVisibilityToActiveView()
        }
    }

    /// Toggles a folder's own visibility. The flag **gates** the group's subtree rather than being
    /// copied into it (§4.1): everything inside is hidden while the folder is, and comes back exactly
    /// as it was when the folder does.
    ///
    /// It wrote through to every descendant until phase 4, which made hide-then-show destructive —
    /// re-showing a group clobbered whichever layers inside it the artist had hidden individually.
    /// The gate lives in three places now, one per consumer: `Compositor` walks the tree,
    /// `isLayerEffectivelyVisible` answers for the live canvas, and `ProjectStore.load` migrates the
    /// projects saved under the old rule.
    ///
    /// When a view preset is active the change is saved into it — the folder's own flag only, since
    /// there are no longer child changes to record.
    func toggleFolderVisibility(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        withStructureUndo(label: .toggleVisibility) {
            folders[idx].isVisible.toggle()
            saveVisibilityToActiveView()
        }
    }

    /// Sets a group's opacity, applied once to its finished composite (§4.1).
    ///
    /// Records no undo step of its own **because its caller already brackets the drag**: the slider
    /// wraps a gesture in `beginStructureGesture`/`commitStructureGesture` (`LayerStackListView`),
    /// and `captureStructure` snapshots `folders`, so one drag is one "Opacity" step. Taking a step
    /// per set would nest inside that bracket and be swallowed anyway — see `withStructureUndo`'s
    /// depth guard — which is why this is a bare write rather than an oversight.
    func setFolderOpacity(_ folderID: UUID, to opacity: Double) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].opacity = min(max(opacity, 0), 1)
    }

    /// Flips a group between isolated and pass-through (§4.2). Wrapped here rather than by a caller,
    /// unlike the opacity slider above: it is a single press with no drag to bracket.
    func setFolderIsolated(_ folderID: UUID, isIsolated: Bool) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].isIsolated != isIsolated else { return }
        withStructureUndo(label: isIsolated ? .isolateGroup : .passThrough) {
            folders[idx].isIsolated = isIsolated
        }
    }

    /// Sets a layer's blend mode (§7). Undoable as one step, like every other discrete pick.
    /// **On a value layer, picking a blend clears the grade** — `setMixBlendMode`'s rule, arriving here
    /// because the owner asked for the same collapse the node picker already had: "Move all the things
    /// in mode into blend mode for value." One menu now answers *what is this layer*, and the two
    /// answers it offers are mutually exclusive, so the setter that writes one has to clear the other.
    ///
    /// Without this, the merged menu could leave both set: `RenderTree`'s leaf derivation pins an
    /// effect-carrying leaf to `.normal` whatever the layer stores, so the artist would pick Multiply,
    /// see the checkmark move, and watch nothing change on the canvas. That is the state the row is
    /// meant to make unreachable rather than the state it explains afterwards.
    ///
    /// Clearing the grade takes its keyframe tracks with it (`Layer.effectTracks`), so this is three
    /// writes and one undo step, with the rename inside it — `setLayerEffect` argues all of them, and
    /// a layer still named "Gaussian Blur" after the blur was cleared is the same lie told backwards.
    /// Ordinary layers are untouched: they have no grade for a blend to conflict with.
    func setLayerBlendMode(layerIndex: Int, to mode: BlendMode) {
        guard layers.indices.contains(layerIndex) else { return }
        let clearsEffect = layers[layerIndex].kind == .value && layers[layerIndex].effect != nil
        guard layers[layerIndex].blendMode != mode || clearsEffect else { return }
        withStructureUndo(label: .blendMode) {
            layers[layerIndex].blendMode = mode
            if clearsEffect {
                layers[layerIndex].effect = nil
                // The grade is gone, so its channels go with it — `setLayerEffect`'s rule, reached by
                // the other door, through the one function that spells it. Nil addresses nothing.
                layers[layerIndex].effectTracks = Effect.tracksAddressed(by: nil,
                                                                         from: layers[layerIndex].effectTracks)
                layers[layerIndex].pendingBaselines =
                    Effect.channelEntriesAddressed(by: nil, from: layers[layerIndex].pendingBaselines)
                if !layers[layerIndex].hasCustomName {
                    layers[layerIndex].name = Self.defaultValueLayerName(effect: nil, ordinal: layers.count)
                }
            }
        }
    }

    /// Sets a group's blend mode — applied once to the group's assembled composite, never per child,
    /// which is the same rule its opacity follows and the reason both need an intermediate buffer.
    func setFolderBlendMode(_ folderID: UUID, to mode: BlendMode) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].blendMode != mode else { return }
        withStructureUndo(label: .blendMode) {
            folders[idx].blendMode = mode
        }
    }

    /// Sets a node's operation to a **blend of two inputs** in `mode` (§4.3) — a different question
    /// from `setFolderBlendMode` above, which the same folder also answers: that one is how the node's
    /// finished composite blends into whatever contains it.
    ///
    /// Still narrow: it refuses anything that is not already a node, because an ordinary folder the
    /// artist made is not a node and must not acquire an op by being asked about one. What widened is
    /// *which* node — it used to require the node already be a `.mix`, which made the picker one-way
    /// the moment an effect node could exist, with no route back to a blend.
    ///
    /// **Picking a blend clears the grade**, which is the other half of `setNodeEffect`'s rule and the
    /// reason both live next to each other. A node cannot both fold two inputs and grade one: the op
    /// and the effect would be two unrelated answers to "what does this node do", with nothing to say
    /// which runs first. One undo step — the state where both are set never exists, not even
    /// transiently on the undo stack — and the cleared grade's keyframe tracks go in the same step,
    /// which is `setLayerBlendMode`'s line on the other grade home.
    func setMixBlendMode(_ folderID: UUID, to mode: BlendMode) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].isCompositorNode,
              folders[idx].compositorOp != .mix(mode) || folders[idx].effect != nil else { return }
        withStructureUndo(label: .mixMode) {
            folders[idx].compositorRole = .node(op: .mix(mode))
            folders[idx].effect = nil
            // …and the grade's channels with it, the folder half of `setLayerBlendMode`'s line.
            folders[idx].effectTracks = Effect.tracksAddressed(by: nil, from: folders[idx].effectTracks)
            folders[idx].pendingBaselines =
                Effect.channelEntriesAddressed(by: nil, from: folders[idx].pendingBaselines)
            // A node that was named for the grade it no longer has must stop claiming it — the same
            // rule `setLayerEffect` applies to a value layer, in the same undo step. See
            // `renameFolderToFollowItsRole`.
            renameFolderToFollowItsRole(idx)
        }
    }

    /// Sets or clears the grade a folder applies to its own finished composite (§4.4's 1-input node
    /// form) — **the node panel's Effects section, and `setLayerEffect`'s folder twin.**
    ///
    /// Accepts any folder, not only a node: `LayerFolder.effect` has always been legal on an ordinary
    /// group, which is what "a group is a 1-input compositor node" means, and refusing it here would
    /// make the derivation's unconditional `effect: folder.effect` reachable only through load.
    ///
    /// **On a node, setting an effect forces the op to `.stack`** — the 1-input form — which is the
    /// converse of `setMixBlendMode` clearing the effect. `.stack` rather than a new
    /// `CompositorOp.effect(Effect)` case: `LayerFolder.effect`'s doc carries that argument, and
    /// `maxInputCount` is where the resulting arity-1 cap is stated. An ordinary folder keeps its nil
    /// `compositorRole` and does not become a node by acquiring a grade.
    ///
    /// **A node that already holds two children keeps them both.** The alternatives were to refuse the
    /// switch, which dead-ends the artist in a picker that will not pick until they go and drag a child
    /// out first, or to promote the extra child into the parent, which is a structural edit performed
    /// silently by a dropdown. Keeping them costs nothing and renders correctly with no special case:
    /// the op is `.stack`, so both backends' `fold` draws the children bottom-to-top into the node's
    /// own buffer exactly as an ordinary folder's, and the grade then runs on that assembled
    /// composite — which is precisely what §4.4's "input" means here, *this container's own
    /// composite*, however many children went into it. `maxInputCount` reads 1 against a real child
    /// count of 2 until the artist drags one out; `canDrop`'s `<` gets that right without help, so no
    /// third child can land and reordering the two that are there stays legal.
    ///
    /// **Changing the grade destroys the keyframe tracks the new one cannot drive**, exactly as it
    /// does on a layer and through the same `Effect.tracksAddressed(by:from:)` — `Layer.effectTracks`
    /// carries the argument and `LayerFolder.effectTracks` is why it is not restated here.
    ///
    /// One undo step per call, like every other discrete pick.
    func setNodeEffect(_ folderID: UUID, to effect: Effect?) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let opNeedsReshaping = effect != nil && folders[idx].isCompositorNode
            && folders[idx].compositorOp != .stack
        guard folders[idx].effect != effect || opNeedsReshaping else { return }
        withStructureUndo(label: effect == nil ? .clearEffect : .valueLayerEffect) {
            folders[idx].effect = effect
            // `setLayerEffect`'s track clear, on the other grade home and by the same one rule —
            // `LayerFolder.effectTracks` is `Layer.effectTracks`'s twin in every observable respect
            // and this is one of them.
            folders[idx].effectTracks = Effect.tracksAddressed(by: effect, from: folders[idx].effectTracks)
            folders[idx].pendingBaselines =
                Effect.channelEntriesAddressed(by: effect, from: folders[idx].pendingBaselines)
            if opNeedsReshaping { folders[idx].compositorRole = .node(op: .stack) }
            renameFolderToFollowItsRole(idx)
        }
    }

    /// Sets (or clears) a layer's alpha mask — §6.2's model half of the §6.5 panel.
    ///
    /// One undo step per call, like every other discrete pick. §6.6 wants a whole mask-edit *session*
    /// to coalesce into one step instead, and that bracket is the panel's to open
    /// (`beginStructureGesture`/`commitStructureGesture`, which nests these the way the opacity
    /// slider already nests `setFolderOpacity`) — so the rule lives with the mode that has a
    /// beginning and an end, rather than being guessed at here.
    func setAlphaMask(_ mask: AlphaMask?, forLayer index: Int) {
        guard layers.indices.contains(index), layers[index].alphaMask != mask else { return }
        withStructureUndo(label: .mask) {
            layers[index].alphaMask = mask
        }
    }

    func setAlphaMask(_ mask: AlphaMask?, forFolder folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].alphaMask != mask else { return }
        withStructureUndo(label: .mask) {
            folders[idx].alphaMask = mask
        }
    }

    // MARK: - Mask-edit mode (§6.5, §6.6)
    //
    // Every layer panel row carries a mask checkmark for as long as one node's options menu is open:
    // opening the menu *is* the session (`syncMaskEditSession`), a checkmark routes to
    // `toggleMaskSource`, and closing the menu ends it. Every mutation in between goes through the
    // by-index/by-id `setAlphaMask` overloads above, so it is still true that those two calls are
    // the only place `alphaMask` is ever written.

    /// Reads whichever of `Layer.alphaMask`/`LayerFolder.alphaMask` `target` names.
    func alphaMask(for target: MaskSource) -> AlphaMask? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.alphaMask
        case .folder(let id): return folders.first { $0.id == id }?.alphaMask
        }
    }

    /// Routes to the by-index/by-id overload `target` names — kept here rather than duplicated,
    /// since a `MaskSource` already carries which one applies.
    private func setAlphaMask(_ mask: AlphaMask?, for target: MaskSource) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            setAlphaMask(mask, forLayer: index)
        case .folder(let id):
            setAlphaMask(mask, forFolder: id)
        }
    }

    /// Enters mask-edit mode for `target`. Nothing is written yet — see `withMaskSessionUndo`.
    func beginMaskEdit(for target: MaskSource) {
        guard maskEditTarget == nil else { return } // one session at a time
        maskEditTarget = target
    }

    /// Closes the session and records whatever it changed as the one step. Safe to call with nothing
    /// pending, and idempotent — the panel calls it both from the action about to edit structure and
    /// again when SwiftUI notices the menu closed.
    func endMaskEdit() {
        guard maskEditTarget != nil else { return }
        maskEditTarget = nil
        guard maskSessionIsRecording else { return }
        maskSessionIsRecording = false
        commitStructureGesture(label: .mask)
    }

    /// **One undo step per session (§6.6), not one per checkmark — opened on the first write rather
    /// than on entry.** Every mask write in the session runs through here, so the bracket exists from
    /// the first one onwards and the `setAlphaMask` calls after it land inside `withStructureUndo`'s
    /// depth guard as nested no-ops, the same coalescing the opacity slider relies on.
    ///
    /// Lazy because the session now begins whenever a node's options menu opens (§6.5). Bracketing on
    /// entry would record an empty step for every menu the artist merely looked at, and creating the
    /// empty `AlphaMask` there — which is what used to give that step something to hold — would hang
    /// a mask off every node whose menu was ever opened.
    private func withMaskSessionUndo(_ body: () -> Void) {
        if maskEditTarget != nil, !maskSessionIsRecording {
            maskSessionIsRecording = true
            beginStructureGesture()
        }
        body()
    }

    /// Flips whether `source` clips the node under edit — a row's mask checkmark.
    ///
    /// Refuses a cyclic `source` via `canMask` even though the picker is expected to already filter
    /// with the same call before offering the row (§6.2: "the picker must filter with this call, do
    /// not write a second rule") — this is the one path both a correctly filtered row and a stale
    /// one still on screen from before a structural edit both go through, so it is where the rule is
    /// enforced rather than only trusted.
    ///
    /// **Picking enables the mask**, which is no longer the override it was when a Mask switch could
    /// pause one: with that switch gone, `isEnabled` is exactly "has sources", set here and cleared
    /// by `dropping(_:)` when the last one goes. The field stays in the model because §6.2 persists
    /// it and the render tree reads it.
    func toggleMaskSource(_ source: MaskSource) {
        guard let target = maskEditTarget, canMask(target.id, with: source) else { return }
        withMaskSessionUndo {
            var mask = alphaMask(for: target) ?? AlphaMask()
            if mask.sources.contains(source) {
                // `dropping(_:)` is also §6.6's deletion rule — reused rather than re-stated, so
                // "the list emptied" disables the mask exactly once, however it emptied.
                mask = mask.dropping(source)
            } else {
                mask.sources.append(source)
                mask.isEnabled = true
            }
            setAlphaMask(mask, for: target)
        }
    }

    /// Whether `source` currently clips the node under edit — a picker row's checkmark.
    func isMaskSource(_ source: MaskSource) -> Bool {
        guard let target = maskEditTarget else { return false }
        return alphaMask(for: target)?.sources.contains(source) == true
    }

    /// Whether `source` is legal to offer for the node under edit right now — `canMask` guards a
    /// cycle; there is nothing to offer at all outside a session.
    func maskEditAllows(_ source: MaskSource) -> Bool {
        guard let target = maskEditTarget else { return false }
        return canMask(target.id, with: source)
    }

    /// §6.5's on-canvas half of mask-edit mode: how much a layer should dim while a session is open,
    /// read by `CanvasView.reconcileLayers` alongside the opacity/visibility folding it already
    /// does. Two states rather than the picker row's three — the node under edit reads as "not a
    /// legal pick" here too (`maskEditAllows` already says so, via the same self-mask case `canMask`
    /// gives every layer), since a canvas dim has no good way to distinguish "this is what you're
    /// editing" from "this would cycle" the way a row's glyph can.
    func maskEditCanvasDim(forLayerAt index: Int) -> CGFloat {
        guard layers.indices.contains(index), maskEditTarget != nil else { return 1 }
        return maskEditAllows(.layer(layers[index].id)) ? 1 : 0.25
    }

    /// Sets `invert` on a node's mask (§6.5) — the options menu's own switch, which sits beside the
    /// rows that carry the checkmarks rather than in them, since inverting is a property of the
    /// mask and not of any one source. Coalesces into the open session like a pick does.
    func setMaskInvert(_ invert: Bool, for target: MaskSource) {
        guard var mask = alphaMask(for: target), mask.invert != invert else { return }
        withMaskSessionUndo {
            mask.invert = invert
            setAlphaMask(mask, for: target)
        }
    }

    /// Keeps §6.5's modal state in step with which options menu is open, which is the whole of what
    /// enters and leaves the session now that the Mask switch is gone: the menu names its target
    /// already, so a second control that said "…and mean it" was the redundancy the owner called out.
    ///
    /// **Every folder is a target, including a node.** The exclusion here was a consequence of input
    /// slots: a node held only its slots and a slot held only whatever was dropped in it, so neither
    /// was content an artist would clip. With slots gone a node is a folder that composites its
    /// children — as legal a mask target as any group, and §6.2's rule that a group can be masked
    /// *and* be a mask source applies to it unchanged.
    func syncMaskEditSession(toOptionsTarget id: UUID?) {
        var target: MaskSource?
        if let id {
            if folders.contains(where: { $0.id == id }) {
                target = .folder(id)
            } else if layers.contains(where: { $0.id == id }) {
                target = .layer(id)
            }
        }
        guard target != maskEditTarget else { return }
        endMaskEdit()
        if let target { beginMaskEdit(for: target) }
    }

    /// Toggles whether a folder's child layers are shown in the layer panel.
    func toggleFolderExpanded(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].isExpanded.toggle()
    }

    /// The container the active layer sits in, or nil when it sits at the top level (or when there is
    /// no active layer at all) — **what "+" should add into**, and the folder half of
    /// `newLayerPlacement`.
    ///
    /// A property rather than a new default for `addFolder`/`addCompositorNode` below, and that was a
    /// close call. Those two take `parentFolderID: UUID?` where nil means the root, so making nil mean
    /// "inherit" instead would have silently rewritten ~96 existing call sites that pass nothing and
    /// mean root — several of which run with the active layer inside a folder (`restackLayer` preserves
    /// the active layer across a move into one), so the change would land as a handful of fixtures
    /// quietly building a different tree than they describe, with no compile error anywhere. Swift has
    /// no way to distinguish "passed nil" from "passed nothing" for an `Optional` parameter short of a
    /// double optional or an enum, both of which read as puzzles at every call site to buy a default.
    ///
    /// So the inheritance is stated at the call site instead: the panel's "+" passes this, and every
    /// other caller goes on meaning exactly what it says.
    var activeContainerID: UUID? {
        layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].parentFolderID : nil
    }

    /// Creates an empty folder. It shows up at the top of the container that holds it (see
    /// `layerStackRows`) until layers are dragged into it.
    ///
    /// `parentFolderID` nil is the root, explicitly — pass `activeContainerID` to put the folder
    /// beside whatever the artist is working on, which is what the panel's "+" does.
    @discardableResult
    func addFolder(name: String? = nil, parentFolderID: UUID? = nil) -> UUID {
        let folder = LayerFolder(id: UUID(),
                                 name: name ?? Self.defaultFolderName(effect: nil, op: nil,
                                                                      ordinal: folders.count + 1),
                                 // `addValueLayer`'s rule: a supplied name is a chosen name.
                                 hasCustomName: name != nil,
                                 parentFolderID: parentFolderID)
        withStructureUndo(label: .addFolder) {
            folders.append(folder)
        }
        return folder.id
    }

    // MARK: - Compositor nodes (§4.3)

    /// Creates a compositor node — a folder whose direct children are its inputs. Returns its id.
    ///
    /// **Empty, and that is the whole of it.** The node used to arrive with one auto-created slot
    /// folder per input; §4.3's redesign deleted slots, so a node is now created exactly the way a
    /// folder is and is filled the same way — by dragging layers and folders into it. Input index is
    /// position: the bottom child is input 0, the backdrop.
    ///
    /// `parentFolderID` follows `addFolder`'s rule: nil is the root, explicitly, and the panel's "+"
    /// passes `activeContainerID` to land the node beside what the artist is working on.
    ///
    /// The op reshapes after creation too — `setMixBlendMode` picks a blend, `setNodeEffect` picks a
    /// grade, and each clears the other — so this is the starting op rather than the only one it can
    /// ever have.
    @discardableResult
    func addCompositorNode(op: CompositorOp, name: String? = nil, parentFolderID: UUID? = nil) -> UUID {
        let node = LayerFolder(id: UUID(), name: name ?? defaultNodeName(for: op),
                               hasCustomName: name != nil,
                               parentFolderID: parentFolderID, compositorRole: .node(op: op))
        withStructureUndo(label: .addNode) {
            folders.append(node)
        }
        return node.id
    }

    private func defaultNodeName(for op: CompositorOp) -> String {
        Self.defaultFolderName(effect: nil, op: op, ordinal: folders.filter(\.isCompositorNode).count + 1)
    }

    /// **The one generator for a folder's automatic name** — `defaultValueLayerName`'s twin, and there
    /// for its reason: `addFolder`, `addCompositorNode`, `setNodeEffect` and `setMixBlendMode` all
    /// produce names, and four spellings of "Mix \(n)" is how a node comes to be born with one name and
    /// renamed to a different one for the same state.
    ///
    /// **The grade wins over the op**, because a node with a grade *is* an effect node whatever op it
    /// stores — `LayerFolder.effect` is the discriminant and `.stack` is only the shape that carries it.
    /// A node named "Group 2" for a Gaussian Blur would be naming the implementation.
    ///
    /// `ordinal` is the caller's, because the two families count differently and always have: an
    /// ordinary folder is numbered among all folders, a node among nodes. `defaultValueLayerName`'s
    /// note on what an ordinal is and is not applies here unchanged.
    static func defaultFolderName(effect: Effect?, op: CompositorOp?, ordinal: Int) -> String {
        if let effect { return effect.displayName }
        switch op {
        case .none:    return "Folder \(ordinal)"
        case .stack?:  return "Group \(ordinal)"
        case .mix?:    return "Mix \(ordinal)"
        }
    }

    /// Re-derives `folders[idx]`'s automatic name after its op or grade changed, and leaves a
    /// hand-named folder alone (`LayerFolder.hasCustomName`).
    ///
    /// **Reads the folder's state after the write rather than taking the new op as an argument**, so it
    /// cannot disagree with what was actually stored — `setNodeEffect` reshapes the op as a side effect
    /// of setting a grade, and a caller passing what it *meant* to set would name the node for a state
    /// one line of code away from the one it is in.
    ///
    /// Must be called from inside the caller's `withStructureUndo`, for `setLayerEffect`'s reason: the
    /// rename and the reshape are one edit and undo has to treat them as one.
    private func renameFolderToFollowItsRole(_ idx: Int) {
        guard folders.indices.contains(idx), !folders[idx].hasCustomName else { return }
        let ordinal = folders[idx].isCompositorNode
            ? folders.filter(\.isCompositorNode).count
            : folders.count
        folders[idx].name = Self.defaultFolderName(effect: folders[idx].effect,
                                                   op: folders[idx].compositorOp,
                                                   ordinal: ordinal)
    }

    /// Removes a folder, keeping everything that was inside it. Its layers and subfolders move up
    /// into whatever contained the folder, in the same stacking positions.
    ///
    /// **A node is not a special case (§4.3's first owner decision).** Deleting one promotes its
    /// children like any other folder. The old `deleteCompositorNode` destroyed the whole subtree for
    /// one reason only — a promoted *slot* folder would be stranded, tagged as input to a node that
    /// no longer exists, with nothing on it to say which node it lost. No slots, no stranding, no
    /// second behaviour: a node's children are ordinary layers and folders and belong in the stack.
    func deleteFolder(_ folderID: UUID) {
        guard folders.contains(where: { $0.id == folderID }) else { return }
        withStructureUndo(label: .deleteFolder) {
            guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
            // Children move up into whatever contained this folder, not to the root, so deleting a
            // nested folder doesn't yank its contents out of the enclosing one.
            let grandparent = folders[idx].parentFolderID
            folders.remove(at: idx)
            for li in layers.indices where layers[li].parentFolderID == folderID {
                layers[li].parentFolderID = grandparent
            }
            for fi in folders.indices where folders[fi].parentFolderID == folderID {
                folders[fi].parentFolderID = grandparent
            }
            for vi in viewPresets.indices {
                viewPresets[vi].folderVisibility.removeValue(forKey: folderID)
            }
            dropMaskSource(.folder(folderID))
        }
    }

    /// Forgets a mask source that no longer exists (§6.6).
    ///
    /// **Called from inside the deletion's own `withStructureUndo`**, which is what makes one undo
    /// restore the source and the masks that pointed at it together — the alternative, a separate
    /// step, would restore a layer that nothing clips to any more.
    ///
    /// Deliberately unlike the render tree's own tolerance of a stale source, which carries on and
    /// contributes no alpha: that is what keeps a document *rendering*, and this is what keeps the
    /// document *true*. Both exist because either alone leaves a hole — dropping only here would
    /// leave a mask pointing at nothing whenever a source vanishes some way this misses.
    private func dropMaskSource(_ source: MaskSource) {
        for index in layers.indices where layers[index].alphaMask?.sources.contains(source) == true {
            layers[index].alphaMask = layers[index].alphaMask?.dropping(source)
        }
        for index in folders.indices where folders[index].alphaMask?.sources.contains(source) == true {
            folders[index].alphaMask = folders[index].alphaMask?.dropping(source)
        }
    }

    /// Renames a folder. Used by the layer options popover, and the one place a folder's
    /// `hasCustomName` is set — `renameLayer`'s twin.
    func renameFolder(_ folderID: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        withStructureUndo(label: .renameFolder) {
            folders[idx].name = name
            folders[idx].hasCustomName = true
        }
    }

    // MARK: - Smart Shapes state (the operations live in CanvasManager+Shape.swift)
    //
    // Stays here for the same reason the fill state above does: extensions can't declare stored
    // properties, and none can be `private` since CanvasManager+Shape.swift reads/writes all of them.

    /// True while an interactive shape exists — either the finger is still down, or it's in the
    /// post-lift *adjustable* state (preview shown, handles visible, not yet baked). Cleared only on
    /// commit or cancel. Main-thread only.
    var shapeGestureActive = false
    /// True only while the drawing finger is actively pressing; false in the adjustable state.
    var shapeFingerDown = false
    /// True when a shape exists and the finger is NOT pressing (adjustable state).
    var isShapeInAdjustableState: Bool { shapeGestureActive && !shapeFingerDown }
    /// True while the finger that drew the shape is still down and steering it, before lift hands it
    /// over to the adjustable state. Named rather than spelled out at each call site as
    /// `shapeGestureActive && !isShapeInAdjustableState`, which reads as a double negative.
    var isShapeFollowingFinger: Bool { shapeGestureActive && shapeFingerDown }

    /// The shape's editable geometry. Handle drags read this, adjust it, and write it back, so it
    /// stays *unconstrained* — `resolvedShape` is what the constraint gets applied to, and what the
    /// user sees and gets. Folding the constraint in here instead would bake it in permanently the
    /// first time a drag round-tripped through.
    var shapeGeometry = ShapeGeometry(kind: .line, startPoint: .zero, endPoint: .zero)
    var shapeIsConstrained = false
    /// Identify the target cel by ID, not index: the shape stays adjustable across other edits that
    /// may shift array positions before it commits (same reasoning as `fillGestureLayerID`).
    var shapeGestureLayerID: UUID?
    var shapeGestureCelID: UUID?
    var shapeGestureColor: CodableColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    var shapeGestureStrokeWidth: CGFloat = 5
    var shapeGestureOpacity: Double = 1.0
    /// The original stroke samples captured before shape detection fired, saved so they can be
    /// collapsed onto the final shape geometry at commit time (preserving brush dynamics).
    var shapeGestureSamples: [VectorSample] = []
    var shapeGestureBrush: Brush = BrushLibrary.softRound
    /// Memoized `activeShapePreviewImage`, keyed by the geometry it was rendered for, plus the
    /// texture it was stamped into. One re-render per geometry change (i.e. per drag event), not one
    /// per SwiftUI pass — `updateShapeOverlay` runs on every render.
    var shapePreviewCache: (shape: ShapeGeometry, image: UIImage)?
    var shapePreviewTexture: RasterLayerTexture?

    // MARK: - Text session state (the operations live in CanvasManager+Text.swift)
    //
    // Here rather than in the extension for the reason the two blocks above say: extensions cannot
    // declare stored properties. `ADD_TEXT.md` §1 "the overlay is the editor; the model is the
    // owner" — every mutation during a session lands in this draft tier, mirroring the smart-shape
    // scalars directly above, and `commitInteractiveText()` is what moves it into the document.

    /// True while a text session exists — a box is placed, whether or not the caret is in it.
    /// Cleared only on commit or cancel. Main-thread only.
    @Published var textGestureActive = false
    /// True only while the box is being dragged. The text tool's counterpart to `shapeFingerDown`,
    /// and the first arm of `finalizePendingGesturesForHistoryAction`'s three-way branch.
    var textFingerDown = false
    /// True while the on-canvas `UITextView` holds first responder. The arm fill and shape do not
    /// have: undo mid-typing must not strand a floating editor over a baked bitmap, so this is what
    /// tells `finalizePendingGesturesForHistoryAction` to resign focus before it commits.
    var textIsFocused = false

    /// The draft the panel's sliders and the overlay's keystrokes both write. `@Published` because,
    /// unlike the shape scalars, a whole settings panel is bound straight to it.
    @Published var textRecipe = TextRecipe()
    /// Where the draft sits on the canvas. Not `@Published`: it changes on every frame of a box
    /// drag, and the only view that reads it is the overlay, which the coordinator pushes to
    /// directly. `objectWillChange.send()` covers the panel's needs.
    var textFrame = TextFrame(origin: .zero, size: .zero)
    /// Identify the target cel by ID, not index — the session outlives other edits that may shift
    /// array positions before it commits (`shapeGestureLayerID`'s reasoning).
    var textGestureLayerID: UUID?
    var textGestureCelID: UUID?
    /// The handle drag in flight, or nil. Holds the **whole starting quad and the anchor**, latched
    /// at touch-down, so a mid-drag pinch-zoom cannot move the reference frame under the gesture
    /// (`ADD_TEXT.md` §1, and `TextFrameDrag`'s own doc for the second half of the argument).
    ///
    /// Here rather than on the overlay view for the reason the draft tier itself is here: the model
    /// owns the session, and a reference frame living in a view is a reference frame that dies when
    /// SwiftUI decides to rebuild one.
    var textHandleDrag: TextFrameDrag?
    /// What the four **corner** grips do — size the box the way stage 4 shipped, or move that one
    /// corner on its own, which is `ADD_TEXT.md` §3 stage 5's projective distort.
    ///
    /// **Tool state, not document state, and that is why it is here rather than on `TextFrame`.**
    /// §1's rule is that the object stores what the text is and where it sits and nothing else; which
    /// gesture the artist currently has selected is neither. It also has to survive between sessions
    /// — an artist putting six labels onto the same wall sets it once — which is the same argument
    /// the recipe's font and colour already win.
    ///
    /// A mode rather than a modifier because the owner framed the Move tool's version as one ("each
    /// of the 4 points can be moved independently"), and because stage 4 deliberately built
    /// corner-drag-as-scale and pinned it with a dozen identities. Distort is additive to that, not a
    /// replacement for it. The edge grips and the rotation knob are unaffected in either mode.
    @Published var textCornerMode: TextCornerMode = .scale
    /// The id of the **already-committed vector element** this session re-opened, or nil for a box
    /// that does not exist in any display list yet (a fresh placement, or any raster session).
    ///
    /// It is what makes the commit an upsert at the element's own index instead of an append, so
    /// re-typing the label behind a drawing does not pull it in front of it, and it is what the
    /// session's `VectorCanvas.editingElementID` suppression is set from. `ADD_TEXT.md` stage 3.
    var textEditingElementID: UUID?
    /// True while this session is re-editing a text object that is still sitting in a vector layer's
    /// display list, suppressed from the flatten. What `CanvasView`'s `makeSandwichKey` reads to
    /// freeze the active layer's content version for the session (`ADD_TEXT.md` §4 rule 5) — the
    /// belt to rule 4's braces, and what stops an unrelated bump (a timeline tick) triggering a
    /// full-canvas snapshot mid-edit.
    ///
    /// Deliberately *not* simply `textGestureActive`: a fresh box on a raster layer has nothing in
    /// any display list to freeze against, and freezing there would hold the active layer's version
    /// stale across whatever else the artist does while the box sits adjustable.
    var isTextEditLive: Bool { textGestureActive && textEditingElementID != nil }
    /// What the font actually resolved to, and why it is not what was asked for. Recomputed on
    /// every recipe change by `refreshTextFontResolution()`; the panel shows it. Nil while no
    /// session is live.
    var textFontSubstitution: FontSubstitution?

    /// Installed by the on-canvas overlay so the model can drop the keyboard without knowing what a
    /// first responder is. Nil whenever no overlay is mounted, which is every headless test.
    ///
    /// A closure rather than a delegate protocol because there is exactly one caller and exactly one
    /// implementor, and a protocol for that pair is ceremony that hides the coupling instead of
    /// naming it.
    var textFocusResigner: (() -> Void)?

    /// Installed by the same overlay. Asked *before* undo/redo does anything: returns true when the
    /// caret is live and the keyboard's own undo stack consumed the action.
    ///
    /// This is `ADD_TEXT.md` §5.1 — "undo while you are typing undoes the typing" — and it is the
    /// owner's decision, not an implementation convenience. Only once you tap away does undo remove
    /// the whole text object. The alternative, undo always stepping through drawing history, throws
    /// away typing corrections.
    var textEditUndoHandler: ((_ isRedo: Bool) -> Bool)?

    /// What must happen when a cel's committed content changes without a live stroke driving it (a
    /// transient baking down, an undo/redo of one): refresh the layer-panel thumbnail and republish.
    ///
    /// `RasterLayerTexture`/`VectorCanvas` are reference types mutated in place, so `@Published
    /// layers` is unchanged and nothing else would trigger a SwiftUI pass. Repainting the canvas
    /// itself is handled separately by the version check in `reconcileLayers`.
    func celContentChangedOutsideStroke(layerID: UUID, celID: UUID) {
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
        objectWillChange.send()
    }

    // MARK: - Undo / redo

    func undo() {
        // Before everything, including the finalize below: with the caret live, undo belongs to the
        // keyboard's own stack (`textEditUndoHandler`, and §5.1 of `ADD_TEXT.md` for why the owner
        // chose that). Returning here is the whole of it — the drawing history is untouched, so the
        // next undo after tapping away still finds the text object waiting on it.
        if textEditUndoHandler?(false) == true { return }
        // **A lift nobody dragged is undone by putting it back, and that press is spent.** The split
        // is the only thing that has happened since, and it carries no step of its own — so falling
        // through to `history.undo()` here would leave the artist's own drawing intact but revert
        // whatever they did *before* they drew the loop, which is not what they asked for.
        if vectorFloat?.nudges == 0 {
            cancelVectorFloat()
            return
        }
        finalizePendingGesturesForHistoryAction()
        // `history.undo()` returns nil (and does nothing) on an empty stack — that is the "silent
        // when nothing happened" case `raise` must not be called for. `finalizePendingGesturesFor-
        // HistoryAction` above may itself have just pushed a step (a lifted fill/shape gesture
        // becoming a real undo entry), so the label reported is always whatever this call actually
        // reverted, never stale.
        if let label = history.undo() {
            raise(.historyUndo(label))
        }
        refreshUndoRedoState()
    }

    func redo() {
        // `undo()`'s twin — see the comment there.
        if textEditUndoHandler?(true) == true { return }
        finalizePendingGesturesForHistoryAction()
        if let label = history.redo() {
            raise(.historyRedo(label))
        }
        refreshUndoRedoState()
    }

    /// An undo/redo can't operate on an interactive fill's or shape's private, off-stack state, so
    /// both are resolved first: one still under the finger is discarded; a lifted, still-adjustable
    /// one is committed so it becomes a real step the following `undo()` reverts, instead of the
    /// undo silently hitting the previous action while it lingers.
    private func finalizePendingGesturesForHistoryAction() {
        if fillFingerDown {
            cancelInteractiveFill()
        } else if fillGestureActive {
            commitInteractiveFill()
        }
        if shapeFingerDown {
            cancelInteractiveShape()
        } else if shapeGestureActive {
            commitInteractiveShape()
        }
        // Text's own three-way branch (`ADD_TEXT.md` §1, "The bake trigger is one line"). The first
        // two arms are the fill's and the shape's: a box under the finger is discarded, a
        // lifted-but-adjustable one commits so the following undo has a real step to revert.
        //
        // The third is the case neither of them has. **Keyboard focused with no finger down resigns
        // first responder and then commits**: undo mid-typing must not strand a floating editor over
        // a baked bitmap, and must not silently throw away what was typed. It is reachable only when
        // `textEditUndoHandler` above declined — i.e. the keyboard's own undo stack is empty — so an
        // artist who undoes past the start of their typing gets the object itself back, which is
        // exactly §5.1's "only once you tap away".
        if textFingerDown {
            cancelInteractiveText()
        } else if textIsFocused {
            textFocusResigner?()
            commitInteractiveText()
        } else if textGestureActive {
            commitInteractiveText()
        }
        // The lasso move's version of the same three-way rule — see
        // `finalizeVectorFloatForHistoryAction`, where the zero-nudge case is the one that has to be
        // un-happened rather than stepped back from.
        finalizeVectorFloatForHistoryAction()
    }

    func refreshUndoRedoState() {
        // A lifted-but-not-yet-committed fill or shape is itself an undoable action (undo finalizes
        // then reverts it), so the Undo affordance must be live even when the committed stack is empty.
        // A live text session joins the fill and the shape: it is an undoable action in its own
        // right (undo finalizes it, then reverts it), so the affordance must be live even on an
        // empty committed stack.
        // A lasso move's float is one too, and it is live from the moment of the lift rather than
        // from the first nudge: with zero nudges, undo closes a hole the artist can see, so the
        // affordance must be lit even on an empty committed stack. It absorbed the whole-layer
        // transform's own clause when that path was deleted (TODO item (12) stage 2): Move with no
        // selection is a float now, so `vectorFloat != nil` is the whole answer for both.
        let newCanUndo = fillGestureActive || shapeGestureActive || textGestureActive
            || vectorFloat != nil || history.canUndo
        let newCanRedo = !fillGestureActive && !shapeGestureActive && !textGestureActive && history.canRedo
        if canUndo != newCanUndo { canUndo = newCanUndo }
        if canRedo != newCanRedo { canRedo = newCanRedo }
    }

    // MARK: - Structural undo state (the operations live in CanvasManager+Undo.swift)
    //
    // Both properties stay here for the same reason as above; internal rather than private since
    // CanvasManager+Undo.swift reads and writes both.

    /// Nesting depth of `withStructureUndo`, so composite edits record exactly one step.
    var structureUndoDepth = 0

    /// In-flight snapshot for a continuous drag (opacity slider, object transform, timeline cel
    /// resize/move) — these call their `CanvasManager` mutator on every gesture-`.changed` event,
    /// so wrapping each individual call would flood the stack with one step per touch-move frame.
    /// Callers instead bracket the whole gesture: `beginStructureGesture()` at `.began`,
    /// `commitStructureGesture(label:)` at `.ended`/`.cancelled`.
    var gestureSnapshot: StructureSnapshot?

    /// How many gesture brackets are open, so an inner one nests instead of clobbering the outer's
    /// snapshot — `withStructureUndo`'s rule, applied to the continuous form.
    ///
    /// It became reachable when the mask-edit session grew to span an open layer options menu (§6.5):
    /// the rows stay live underneath it, so an opacity drag now begins a bracket inside the session's.
    /// Without the depth, that drag's `begin` overwrites the session's baseline and its `commit`
    /// records a step from the wrong one, leaving the session with nothing to commit at all.
    var structureGestureDepth = 0

    /// Whether the open mask-edit session has already opened its undo bracket (§6.6). Nil-until-used
    /// rather than opened in `beginMaskEdit`, because the session now begins whenever a layer's
    /// options menu opens: bracketing there would record an empty step for every menu merely looked at.
    var maskSessionIsRecording = false
}
