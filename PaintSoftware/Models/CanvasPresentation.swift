import Foundation

/// Every presentation the editor raises over the live canvas — one case each, a closed set.
///
/// **None of them is a UIKit presentation, and that is the whole reason the type exists.** They are
/// all drawn inside the app's own view hierarchy as `AnchoredMenu`s — the timeline's five by
/// `AnimationTimeline`'s menu layer, the rest by `View.canvasPresentationHost` — and all of them are
/// dismissed by one rule applied in one place: `AnchoredMenuRouter`, a single window-level observer
/// that lives as long as the editor does and asks `AnchoredMenuDismissal.presentationsToDismiss`
/// which of the open ones a touch just left.
///
/// A `.popover` cannot sit over this canvas. It presents behind a screen-covering
/// `_UIPassthroughGateGestureRecognizer` that UIKit binds to the same touches as `canvas.pan`,
/// `canvas.pinch` and `canvas.rotation`, and whenever that gate is removed while a two-finger gesture
/// is live — by the app closing the popover on the gesture's first finger, or by UIKit closing it on
/// its own because two fingers landed outside it — every recognizer bound alongside it is stranded
/// in a terminal state UIKit never resets. The canvas then binds only `canvas.touchCounter` to every
/// later touch and never pans, pinches or draws again until the project is reopened. MEASURED on the
/// simulator, both ways, and it is the owner's canvas freeze (TODO (110), and before it 2026-09-16);
/// `CanvasTransformFreezeUITests` drives it. `CanvasPresentationLogicTests` fails if a `.popover` is
/// written anywhere in the app.
///
/// Raw values are stable strings because the action recorder writes them into a capture — a
/// recording that says which presentation was on screen when the canvas stopped is the evidence two
/// freeze reports did not have.
enum CanvasPresentation: String, CaseIterable, Hashable, Identifiable {

    // MARK: - The timeline

    /// The one menu behind `AnimationTimeline.timelineMenu`, whichever of its three cases
    /// (block / gap / loop) is showing.
    case timelineSlotMenu

    /// `OnionSkinPanel`, hung off the timeline's onion-skin button.
    case onionSkinOptions

    /// `InterpolatePanel`, hung off the timeline's interpolate button.
    case interpolateOptions

    /// The graph editor's channel list, hung off the button beside the graph editor toggle —
    /// KEYFRAMES.md §11.5.
    case graphChannelList

    /// The frame-rate panel, hung off the timeline's fps readout — KEYFRAMES.md §2.7 and §5.
    case frameRateOptions

    // MARK: - The layer rail and its options panels

    /// `ViewSelectorMenu`, off the layer panel's "Views" button.
    case layerViewSelector

    /// The canvas background colour picker in the layer panel's canvas row.
    case canvasBackgroundColour

    /// A value layer's fill colour picker, in `LayerOptionsPanel`. Brackets an undo gesture over its
    /// own lifetime (`CanvasManager.beginStructureGesture`), which is why the modifier gives every
    /// case an `onDismiss` that runs on host deletion as well as on the flag going false.
    case valueLayerColour

    /// An effect's outline colour swatch, in `EffectSettingsBar`. Brackets `onEditBegan`/`onEditEnded`
    /// over its lifetime, same as `valueLayerColour`.
    case effectOutlineColour

    /// A gradient stop's colour, in the gradient-map effect's stop list.
    case effectGradientStopColour

    /// One end of a recolour pair's colour, in the recolour effect's entry list — the *swatch* route
    /// to a colour; the eyedropper beside it is a tool, not a presentation, and closes nothing.
    case effectRecolorColour

    /// A bloom's glow-tint swatch, in `EffectSettingsBar` — TODO (60). A case of its own rather than
    /// sharing `effectOutlineColour`'s: the raw value is what a capture says was open.
    case effectBloomColour

    /// A duplicate offset's colour swatch, in `EffectSettingsBar` — TODO (61) stage 6.
    case effectDuplicateOffsetColour

    /// A guide's line-colour swatch, in `EffectSettingsBar` — TODO (88).
    case effectGuideColour

    // MARK: - Onion skin

    /// The previous-drawings tint swatch, the red end of `OnionSkinPanel`'s gradient bar — TODO (72).
    case onionPreviousTintColour

    /// The next-drawings tint swatch, the green end of the same bar.
    case onionNextTintColour

    // MARK: - The Select panel

    /// The Select panel's Colour swatch — TODO (42)'s picker. Brackets a selection edit over its
    /// lifetime (`CanvasManager.beginSelectionEdit` on present, `commitSelectionEdit` on dismiss), so
    /// the picker's life is the drag and its dismissal is the one undo step.
    case selectionColour

    var id: String { rawValue }

    /// **The presentation this one is raised from inside, if any** — so a touch on it does not also
    /// close the one it sits in.
    ///
    /// Exhaustive with no `default:`: a case added later cannot compile until it says whether it is
    /// nested. The two onion tint pickers are the only nested ones — `ColorPickerPanel` is 300 pt
    /// wide and hangs off a swatch in the ~250 pt onion menu, so a touch on the picker necessarily
    /// falls outside the menu's own frame and would close it, and the picker with it, mid-pick.
    var parent: CanvasPresentation? {
        switch self {
        case .onionPreviousTintColour, .onionNextTintColour:
            return .onionSkinOptions
        case .timelineSlotMenu, .onionSkinOptions, .interpolateOptions, .graphChannelList,
             .frameRateOptions, .layerViewSelector, .canvasBackgroundColour, .valueLayerColour,
             .effectOutlineColour, .effectGradientStopColour, .effectRecolorColour, .effectBloomColour,
             .effectDuplicateOffsetColour, .effectGuideColour, .selectionColour:
            return nil
        }
    }
}
