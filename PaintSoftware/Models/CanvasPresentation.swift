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
/// **That includes every menu.** A pull-down or a long-press menu is a case here too, drawn by
/// `CanvasMenu` / `canvasContextMenu` — never a SwiftUI `Menu` or `.contextMenu`, which UIKit presents
/// and whose teardown cancels the stroke that closed it (`CanvasPresentationLogicTests` fails if one
/// is written anywhere over the canvas).
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

    // MARK: - Objects placed on the canvas

    /// The start colour of a gradient object, in `GradientSettingsPanel`. Two cases rather than one
    /// shared index (`effectGradientStopColour`'s shape) because there are exactly two of these and
    /// always will be — `onionPreviousTintColour`/`onionNextTintColour` is the precedent for a fixed
    /// pair.
    case gradientStartColour
    /// The end colour — `gradientStartColour`'s twin.
    case gradientEndColour

    // MARK: - The text panel

    /// The font family list, hung off the text panel's Font row — TODO (115). A presentation of its
    /// own rather than a native `Menu` because a `Menu`'s rows are drawn by UIKit, which discards a
    /// custom font: this list exists so every family is shown in itself.
    case textFont

    /// The text panel's Colour swatch: the app's one colour picker on the text's own colour.
    case textColour

    // MARK: - The Select panel

    /// The Select panel's Colour swatch — TODO (42)'s picker. Brackets a selection edit over its
    /// lifetime (`CanvasManager.beginSelectionEdit` on present, `commitSelectionEdit` on dismiss), so
    /// the picker's life is the drag and its dismissal is the one undo step.
    case selectionColour

    // MARK: - Menus
    //
    // One case per kind of control that raises a menu, not per call site: two of one kind are never
    // open at once, because opening the second is a touch outside the first.

    /// The layer panel's "+": which kind of layer, folder or node to add.
    case layerAddMenu

    /// The Blend Mode / Effect / Operation row of a layer's or folder's options — the same list of
    /// blend modes with the effect catalogue below it, wherever it is asked.
    case layerBlendMenu

    /// A transformation layer's Mode row.
    case transformModeMenu

    /// A choice inside an effect's settings bar — a preset, a region, a type, a mode.
    case effectOptionMenu

    /// The interpolate panel's Fetch: link or duplicate a guide from another frame.
    case guideFetchMenu

    /// Press and hold on a motion-group chip: show, solo, interpolation, delete.
    case motionGroupMenu

    /// Press and hold on an animation group in the graph editor's channel list: rename.
    case graphGroupMenu

    /// The brush panel's open-group chevron: rename, reorder or delete the group.
    case brushGroupMenu

    /// The brush panel's "+": create or import a brush, or add a group.
    case brushAddMenu

    /// Press and hold on a brush in the brush panel: favourites.
    case brushRowMenu

    /// The text panel's Style row: the face within the family.
    case textFaceMenu

    /// Press and hold on a palette swatch: delete it. The colour picker's swatch grid is drawn inside a
    /// dozen other presentations, so this is the menu that is most often nested.
    case paletteSwatchMenu

    /// A choice or an add inside the full-screen brush editor — tip, texture, input, module.
    case brushEditorMenu

    var id: String { rawValue }
}
