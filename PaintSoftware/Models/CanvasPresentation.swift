import Foundation

/// Every presentation in this app whose openness is held in a binding — one case each, so that
/// "what happens to this when the artist puts a pen on the canvas?" has a place to be **answered**
/// instead of a place to be forgotten.
///
/// **This type exists because forgetting was the bug, three times.** `CanvasManager.interactionBegan`
/// used to be a bare signal with two hand-written subscribers, each clearing one variable by name:
/// `DrawingView` cleared `activePanel`, `AnimationTimeline` cleared `timelineMenu`. Nothing cleared
/// the two popovers declared nine lines above that second sink, or the five hanging off the layer
/// rail. A presentation was therefore **broken by default** and became safe only if whoever added it
/// happened to know there was a line to write — and the author of the sink written to fix exactly
/// this class of bug did not write it for the two popovers in their own file.
///
/// So the answer is not a third hand-written line. It is this enum plus `CanvasManager
/// .dismissPresentationsOverLiveCanvas()` plus `View.canvasPresentation(_:isPresented:)`: one closed
/// set, one exhaustive `switch` with no `default:`, and one modifier that is the only way to declare
/// a presentation at all. A case added here cannot compile until it states its answer below, and
/// `CanvasPresentationLogicTests` walks `allCases` against a table written by hand so a case added
/// without an entry fails rather than defaults. `Tool.paintsOnCanvas` is the precedent, and it is the
/// precedent for the same reason: it replaced a hand-maintained exclusion list that a newly added
/// tool was not added to.
///
/// **What is deliberately not in here, and why the guarantee is narrower than it looks.** A case
/// needs a binding for the modifier to observe. `Menu`, `.contextMenu`, the stock `ColorPicker` and
/// `ShareLink` present themselves and expose no `isPresented`, so the twelve of those listed in
/// `MENU_PRESENTATION_CENSUS.md` are outside this type and outside its protection. Whether they even
/// need it is the census's open question — they present through `UIContextMenuInteraction`/`UIMenu`
/// rather than `UIPopoverPresentationController`, and nothing in this repo has verified that an
/// outside touch reaches the canvas through them the way it demonstrably does through a `.popover`.
/// `ActionsMenu`'s `PhotosPicker` is out for the same mechanical reason (no binding) and needs
/// nothing anyway: it is a full-screen system modal, so no touch can reach the canvas beneath it.
///
/// Raw values are stable strings because `ActionRecorder` writes them into a capture — a recording
/// that says which presentation was on screen when a stroke went wrong is the evidence three
/// sessions of reading did not have.
enum CanvasPresentation: String, CaseIterable, Hashable, Identifiable {

    // MARK: - The timeline

    /// The one popover behind `AnimationTimeline.timelineMenu`, whichever of its three cases
    /// (block / gap / loop) is showing. **This is the presentation the owner's original freeze report
    /// was about**, and the one 8ae8613 fixed by hand.
    case timelineSlotMenu

    /// `OnionSkinPanel`, hung off the timeline's onion-skin button. Symptom 2 of the 2026-08-18
    /// report: nothing cleared it, so the stroke ran to completion and the teardown landed on the
    /// *lift* instead — a recognizer stranded in `.ended` with no `reset()`, which receives no
    /// further touches at all. That is why the artist could not paint again until they quit to the
    /// gallery: the recognizer is per-`LayerHostView`, and re-entering the project is what rebuilds it.
    case onionSkinOptions

    /// `InterpolatePanel`, hung off the timeline's interpolate button. Never reported, because
    /// interpolate mode is used less — but it is `onionSkinOptions` line for line, declared five
    /// lines below it, and it was broken in exactly the same way.
    case interpolateOptions

    // MARK: - The layer rail and its options panels

    /// `ViewSelectorMenu`, off the layer panel's "Views" button.
    case layerViewSelector

    /// The canvas background colour picker in the layer panel's canvas row.
    case canvasBackgroundColour

    /// A value layer's fill colour picker, in `LayerOptionsPanel`. Brackets an undo gesture over its
    /// own lifetime (`CanvasManager.beginStructureGesture`), which is why the modifier below gives
    /// every case an `onDismiss` that runs on host deletion as well as on the flag going false.
    case valueLayerColour

    /// An effect's outline colour swatch, in `EffectSettingsMenu`. Brackets `onEditBegan`/`onEditEnded`
    /// over its lifetime, same as `valueLayerColour`.
    case effectOutlineColour

    /// A gradient stop's colour, in the gradient-map effect's stop list.
    case effectGradientStopColour

    // MARK: - The gallery
    //
    // **Neither of these registers itself, and that is correct.** `GalleryView` holds no
    // `CanvasManager` — it mints one when a project is opened — so there is nothing for
    // `View.canvasPresentation` to register *into*, and nothing would be gained if there were: the
    // central rule only ever fires from a canvas touch, and on this screen there is no canvas. They
    // are cases here because the type is the census, and a decision that lives only in a Markdown
    // file is a decision the next person re-derives. `CanvasPresentationLogicTests` registers them
    // by hand to prove the rule is a filter rather than a blanket.

    /// The version-history sheet, `GalleryView`.
    case galleryProjectVersions

    /// The Recently Deleted sheet, `GalleryView`.
    case galleryRecentlyDeleted

    var id: String { rawValue }

    /// Whether this presentation can be on screen at a moment when a touch on the canvas would
    /// become a stroke — and therefore whether a canvas touch has to close it *first*.
    ///
    /// **Exhaustive, with no `default:`, and that is the whole point of the type.** The alternative
    /// is what this replaced: a list of variables to clear, maintained by hand, which a
    /// newly-declared popover is not added to. A presentation added after this cannot repeat that —
    /// it will not compile until it says which side it is on.
    ///
    /// **`true` does not mean "this is the fix".** Closing a popover on `interactionBegan` is what
    /// 8ae8613 did for `timelineSlotMenu`, and it converted a permanent canvas freeze into a
    /// truncated stroke that vanished when the next one started: the presentation still comes down
    /// mid-sequence, one frame later, and the ink painted so far was still discarded. Doing this to
    /// seven more popovers without `StrokeGiveUp.interrupted`'s ink rule would have converted seven
    /// freezes into seven lost strokes. The two halves ship together and neither is sufficient: this
    /// one decides *when* the teardown lands, and `StrokeInterruption` decides what the teardown is
    /// allowed to cost.
    ///
    /// **`false` is not "safe by accident" either** — each false case is false for its own stated
    /// reason, and a case that cannot say which reason applies to it probably belongs on the true
    /// side.
    var overlapsLiveCanvas: Bool {
        switch self {
        case .timelineSlotMenu, .onionSkinOptions, .interpolateOptions,
             .layerViewSelector, .canvasBackgroundColour, .valueLayerColour,
             .effectOutlineColour, .effectGradientStopColour:
            // All eight are `.popover`s presented from chrome that sits over a mounted, touchable
            // `CanvasView`. A `.popover` left to its own dismissal is dismissed *by* the touch that
            // lands outside it, and this repo has observed twice that the touch is not swallowed:
            // the stroke begins, and the presentation's teardown lands in the middle of the touch
            // sequence. The five hung off the layer rail look protected because `activePanel = .none`
            // deletes their host — but deleting the host *is* a teardown, caused by the same touch
            // one layer up, which is the identical hazard with a different name.
            return true
        case .galleryProjectVersions, .galleryRecentlyDeleted:
            // `ContentView` is a `switch screen`: on the gallery screen `DrawingView` is not mounted,
            // so there is no canvas, no `LayerHostView` and no `StrokeGestureRecognizer` for a
            // teardown to strand. These are cases here rather than absent from the type because the
            // reason they are safe is a fact about `ContentView` that could change — moving the
            // gallery into a sheet over the editor would make both of these `true` overnight, and a
            // reviewer of that change should find this line rather than nothing.
            return false
        }
    }
}
