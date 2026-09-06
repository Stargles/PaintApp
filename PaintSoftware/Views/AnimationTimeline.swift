import SwiftUI

struct AnimationTimeline: View {
    @ObservedObject var canvasManager: CanvasManager
    /// How tall the panel is right now. The user sets this by dragging the top bar; it does *not*
    /// grow on its own when layers are added (the tracks scroll instead), so the timeline never
    /// takes canvas space back without being asked.
    @State private var timelineHeight: CGFloat = 250
    /// Height at the start of the current resize drag, so the drag tracks its own translation
    /// rather than accumulating rounding from each `onChanged`.
    @State private var resizeStartHeight: CGFloat?

    /// Height available to the timeline's container, supplied by the parent so the maximum size
    /// respects Split View instead of assuming the whole screen.
    var availableHeight: CGFloat = 1024

    private let rowHeight: CGFloat = 34
    private let rulerHeight: CGFloat = 18
    private let collapsedHeight: CGFloat = 48
    private let minExpandedHeight: CGFloat = 130
    private let dragHandleHeight: CGFloat = 12
    private let collapsedBarHeight: CGFloat = 48
    private let miniToolbarHeight: CGFloat = 40
    private let dividerHeight: CGFloat = 1

    private var isCollapsed: Bool {
        timelineHeight <= collapsedHeight + 2
    }

    // The timeline's three menus (block options / gap "Add Drawing" / ruler loop-range) are a
    // popover hung off the thing that was tapped rather than a confirmation dialog centred on the
    // panel: `menuAnchor` is that thing's rect in window coordinates, reported up by
    // `TimelineTrackView`. A dialog was appearing over the timeline itself, covering the very block
    // or column it was about to act on.
    //
    // They used to be three independent `Bool` + payload + anchor triples (`showBlockMenu`/
    // `menuLayerIndex`/`menuCelIndex`/`blockMenuAnchor`, and the same shape twice more for the gap
    // and loop menus) wired to three separate `TimelineTrackView` callbacks. All three were always
    // the same underlying question — "is a menu open, and if so which one, over what, and where" —
    // asked three times, which is what the owner meant by "these two menus are coded off of the
    // same engine... make them into one": one `TimelineMenu` case answers all three at once, and it
    // is nil exactly when no menu is open, so there is no separate `Bool` to fall out of sync with
    // the payload it's supposed to be describing (the bug behind CHANGE 1's gap-menu gate was
    // exactly that kind of drift, just one state variable's worth instead of three's).
    //
    // `TimelineMenu` is a `typealias` for `TimelineTrackView.MenuRequest` rather than a fresh
    // private enum with the same three cases: `TimelineTrackView`'s own callback already has to
    // name a case for "which menu, with what payload" to fire it (see `onRequestMenu` there), and a
    // second, identically-shaped enum here would only exist to be switched into the first one on
    // every call — the same trap as `CanvasManager.CelDropRequest`, which `onRequestRasterizeConfirm`
    // already stores directly for the same reason.
    private typealias TimelineMenu = TimelineTrackView.MenuRequest
    @State private var timelineMenu: (menu: TimelineMenu, anchor: CGRect)?

    // Interpolate mode's options popover, opened by a second tap on the timeline's interpolate
    // button (the first tap enters the mode).
    @State private var showInterpolateOptions = false

    // Onion skin's panel, opened by a second tap on the onion-skin button — the same two-stage
    // behaviour as interpolate above, for the same reason: the button is the switch, so a panel that
    // opened on the first tap would put a mode change behind an extra step.
    @State private var showOnionSkinOptions = false

    /// A vector block dropped on a raster layer, waiting on the artist's answer. Non-nil raises the
    /// rasterize alert; the drop is only applied if they say yes. Held by identity (see
    /// `CanvasManager.CelDropRequest`) because the indices it came from can be renumbered while the
    /// alert is up.
    @State private var pendingRasterizeDrop: CanvasManager.CelDropRequest?

    // Press-and-hold reorder state for the pinned name column.
    /// The animation group the rename alert is open on, and the text field's draft — the shape
    /// `LayerPanel`'s own rename alert uses, and `@State` for the reason the popovers just above are:
    /// there is no rule about it that the model has to be able to see.
    @State private var renamingAnimationGroup: AnimationGroup?
    @State private var animationGroupDraftName = ""
    @State private var draggingRowID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragOffsetRows: Int = 0

    /// Where each of the three button-hung menus should appear, in global coordinates, reported by
    /// the buttons themselves through `AnchoredMenuAnchorKey`. The slot menu is not in here — its
    /// anchor is the tapped block, which arrives with the menu request.
    @State private var menuAnchors: [CanvasPresentation: CGRect] = [:]

    var body: some View {
        // The interpolate bar sits *outside* the height-constrained timeline rather than inside it,
        // so turning the mode on adds a strip above the panel instead of eating rows out of it.
        VStack(spacing: 0) {
            if canvasManager.isInterpolateMode {
                InterpolateBar(canvasManager: canvasManager)
            }
            timelinePanel
        }
        // **What the bottom dock rides on** — TODO item (49). The *rendered* height rather than
        // `timelineHeight`, deliberately: that state stays the one place the panel's size is
        // decided, and this reports what the whole timeline actually came to, so the interpolate
        // strip above the panel is included without `BottomDock` having to know it exists.
        .background(GeometryReader { geometry in
            Color.clear.preference(key: TimelineOccupiedHeightKey.self, value: geometry.size.height)
        })
    }

    private var timelinePanel: some View {
        VStack(spacing: 0) {
            // The whole top bar resizes the timeline, not just the grab handle: a drag anywhere on
            // it (including across the buttons — `simultaneousGesture` with a minimum distance lets
            // taps through untouched) raises or lowers the panel.
            VStack(spacing: 0) {
                dragHandle
                if isCollapsed { collapsedBar } else { miniToolbar }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(resizeGesture)

            if !isCollapsed {
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: dividerHeight)
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        layerNameColumn
                        TimelineTrackView(
                            canvasManager: canvasManager,
                            rowHeight: rowHeight,
                            rulerHeight: rulerHeight,
                            onRequestMenu: { request, anchor in
                                timelineMenu = (request, anchor)
                            },
                            onRequestRasterizeConfirm: { request in
                                pendingRasterizeDrop = request
                            }
                        )
                    }
                    // **The host fills the viewport when the rows fall short of it, and the track's
                    // own content keeps its natural height inside that.** Sized to `contentHeight`
                    // alone, the UIKit track simply did not exist below the last row: the strip
                    // between it and the bottom of the panel took no touch, so there was no
                    // horizontal scroll and no pinch there, and the gridlines stopped at the same
                    // edge. `max` keeps the other direction untouched — a stack taller than the
                    // panel still scrolls vertically, which is what this `ScrollView` is for.
                    .frame(height: rowLayout.contentHeight(filling: trackViewportHeight))
                }
                .frame(height: trackViewportHeight)
            }
        }
        .frame(height: timelineHeight)
        .background(Color.black)
        // Collected from the controls themselves rather than computed here, so a menu cannot end up
        // hanging off a position layout no longer agrees with.
        .onPreferenceChange(AnchoredMenuAnchorKey.self) { menuAnchors = $0 }
        // The slot menu's registration. Attached to the panel because the panel is its host: the
        // menu may not outlive the timeline, and `.onDisappear` in the registration is what says so.
        .canvasPresentationRegistration(.timelineSlotMenu, isPresented: isTimelineMenuPresented,
                                        canvasManager: canvasManager)
        .overlay(alignment: .bottom) { anchoredMenuLayer }
        .alert("Rasterize this block?",
               isPresented: Binding(get: { pendingRasterizeDrop != nil },
                                    set: { if !$0 { pendingRasterizeDrop = nil } })) {
            Button("Cancel", role: .cancel) { pendingRasterizeDrop = nil }
            Button("Rasterize & Move") {
                if let drop = pendingRasterizeDrop {
                    canvasManager.moveCelToLayer(celID: drop.celID,
                                                 fromLayer: drop.sourceLayerID,
                                                 toLayer: drop.targetLayerID,
                                                 startFrame: drop.startFrame,
                                                 rasterizing: true)
                }
                pendingRasterizeDrop = nil
            }
        } message: {
            Text("Moving a vector block onto a raster layer flattens its strokes to pixels. They can still be erased and painted over, but they can no longer be reshaped as vectors. This can be undone.")
        }
        // **There is deliberately no `.onReceive(canvasManager.interactionBegan)` here any more.**
        //
        // There used to be, clearing `timelineMenu` by name. It was right about the mechanism — a
        // popover left to its own dismissal is dismissed *by* the touch that lands outside it, and
        // when that touch starts a stroke the presentation comes down in the middle of the touch
        // sequence — and it was the wrong shape of fix twice over. It covered one of the three
        // popovers in this file, leaving the two declared a few lines above it (onion skin,
        // interpolate) broken in the way the owner reported on 2026-08-18. And closing the popover
        // *earlier* does not stop the teardown landing mid-sequence, it only moves it a frame: the
        // canvas stopped freezing and the artist's ink started disappearing instead.
        //
        // Both halves now live outside this file. `View.canvasPresentation` registers each of the
        // three popovers below, `CanvasManager.dismissPresentationsOverLiveCanvas()` closes them
        // from one place, and `StrokeGiveUp.interrupted` is what makes a mid-sequence teardown cost
        // the artist nothing worse than a short stroke they can undo.
        .onDisappear { canvasManager.stopPlayback() }
    }

    /// Height of the grab handle plus whichever bar is showing — the fixed chrome above the tracks.
    private var topBarHeight: CGFloat {
        dragHandleHeight + (isCollapsed ? collapsedBarHeight : miniToolbarHeight)
    }

    /// The row geometry both halves of the timeline lay out from — this column and the UIKit track,
    /// which builds its own from the same `TimelineRowLayout.make`, so the two cannot disagree about
    /// where a row starts or how tall it is.
    private var rowLayout: TimelineRowLayout {
        TimelineRowLayout.make(rows: canvasManager.layerStackRows,
                               rulerHeight: rulerHeight,
                               rowHeight: rowHeight,
                               // The graph editor band grows the row it opens under, so this column
                               // has to take the same growth or every name below it would label the
                               // track above the one it belongs to. Both halves read the one
                               // derivation on `CanvasManager` — KEYFRAMES.md §11.2's seam.
                               expansion: canvasManager.graphBandExpansion)
    }

    /// How much of the panel is left for the tracks once the chrome above them has taken its share.
    private var trackViewportHeight: CGFloat {
        max(0, timelineHeight - topBarHeight - dividerHeight)
    }

    // MARK: - Menus

    /// **All four of this panel's menus, drawn inside the app's own hierarchy — TODO (39).**
    ///
    /// They were four `.popover`s until 2026-09-06, and a `.popover` presents behind a
    /// screen-covering `_UIPassthroughGateGestureRecognizer`: `hitTest` still returned the timeline
    /// row, but `touchesBegan` never fired, so **every drag on the timeline was swallowed whole**
    /// while a menu was up. The track did not scroll, the ruler did not scrub, and the popover did
    /// not even go away — only a tap dismissed it. MEASURED at the time: menu up, a drag moved the
    /// cel block 0.0 pt; menu gone, the same drag moved it 369 pt.
    ///
    /// The owner ruled against the smaller fix (`UIPopoverPresentationController.passthroughViews`)
    /// on 2026-09-06: passthrough lets the drag through but leaves the menu standing while the track
    /// scrolls out from under it, and a cel menu names a *specific block*. So the menus stop being
    /// presentations. `AnchoredMenu` captures exactly what it covers, and its window observer closes
    /// this **without** consuming the gesture that closed it — one drag dismisses the menu and
    /// scrolls the track.
    ///
    /// **One layer for four menus rather than a modifier at each of the four sites**, because the
    /// menus have to be drawn over the canvas above this panel, and an overlay sized to the whole
    /// screen once is clearer than four views each escaping their own container. Each site keeps its
    /// own binding and its own `canvasPresentationRegistration`, so every rule those already carried
    /// — the central canvas-touch dismissal, `onDismiss` on host deletion, the `ActionRecorder`
    /// capture — is untouched. Only who draws the thing has changed.
    @ViewBuilder
    private var anchoredMenuLayer: some View {
        if let open = openAnchoredMenu {
            AnchoredMenu(anchor: open.anchor,
                         toggleControl: open.toggleControl,
                         identifier: "timeline.anchoredMenu.\(open.presentation.rawValue)",
                         onDismiss: { closeAnchoredMenu(open.presentation) }) {
                anchoredMenuContent(open.presentation)
            }
            // As tall as the screen and bottom-aligned to this panel, so a menu can be drawn above
            // the timeline over the canvas and still be **inside its own container** — which is what
            // makes it hit-testable there. `availableHeight` is the parent `GeometryReader`'s, which
            // is the whole editor.
            .frame(maxWidth: .infinity)
            .frame(height: availableHeight, alignment: .bottom)
        }
    }

    /// Which menu is up, where it hangs from, and which control (if any) governs its openness.
    ///
    /// **Only one is rendered even if two flags are somehow true**, and in practice they cannot be:
    /// opening any of these touches somewhere the open one does not cover, which closes it on the
    /// way. The order below is therefore a tiebreak nobody should reach rather than a policy —
    /// stated so it is deterministic instead of dependent on which `if` a future edit puts first.
    private var openAnchoredMenu: (presentation: CanvasPresentation, anchor: CGRect, toggleControl: CGRect?)? {
        // The slot menu's anchor is the tapped block, which is **not** a control that toggles it —
        // so no exemption, and a drag that starts on the block dismisses like any other.
        if let menu = timelineMenu { return (.timelineSlotMenu, menu.anchor, nil) }
        // The other three hang off buttons that toggle them. The button is passed as the toggle
        // control so the observer leaves it alone; without that, its touch-down dismissal and the
        // button's touch-up `toggle()` would compose into a menu that can never be closed from the
        // button that opened it. See `AnchoredMenuDismissal.shouldDismiss`.
        if showOnionSkinOptions, let rect = menuAnchors[.onionSkinOptions] {
            return (.onionSkinOptions, rect, rect)
        }
        if showInterpolateOptions, let rect = menuAnchors[.interpolateOptions] {
            return (.interpolateOptions, rect, rect)
        }
        if canvasManager.isGraphChannelListOpen, let rect = menuAnchors[.graphChannelList] {
            return (.graphChannelList, rect, rect)
        }
        return nil
    }

    /// The content of whichever menu is up. `default` is unreachable — `openAnchoredMenu` only ever
    /// returns these four — and returns `EmptyView` rather than trapping because a menu that fails
    /// to draw is a better failure than a crash in front of the artist.
    @ViewBuilder
    private func anchoredMenuContent(_ presentation: CanvasPresentation) -> some View {
        switch presentation {
        case .timelineSlotMenu:
            timelineMenuContent
        case .onionSkinOptions:
            OnionSkinPanel(canvasManager: canvasManager).frame(width: 380, height: 640)
        case .interpolateOptions:
            InterpolatePanel(canvasManager: canvasManager).frame(width: 260)
        case .graphChannelList:
            graphChannelList.frame(width: 250)
        default:
            EmptyView()
        }
    }

    /// Writes the site's own binding, which is what the registration observes — so closing an
    /// anchored menu goes through exactly the path a popover's own dismissal went through.
    private func closeAnchoredMenu(_ presentation: CanvasPresentation) {
        switch presentation {
        case .timelineSlotMenu:   timelineMenu = nil
        case .onionSkinOptions:   showOnionSkinOptions = false
        case .interpolateOptions: showInterpolateOptions = false
        case .graphChannelList:   canvasManager.isGraphChannelListOpen = false
        default:                  break
        }
    }

    /// `canvasPresentationRegistration` wants a `Bool`, but `timelineMenu` is the one piece of state
    /// that answers both "is a menu open" and "which one" — this derives the former from the latter.
    /// The setter is what makes a dismissal that comes from anywhere else — the central canvas-touch
    /// rule, `AnchoredMenu`'s observer — clear `timelineMenu` too, rather than leaving a stale
    /// payload behind a `Bool` that had already gone false.
    private var isTimelineMenuPresented: Binding<Bool> {
        Binding(get: { timelineMenu != nil }, set: { if !$0 { timelineMenu = nil } })
    }

    /// The one menu's content, resolved from whichever case `timelineMenu` currently holds.
    ///
    /// The `.block` branch keeps the same `canvasManager.layers.indices.contains(layerIndex)` guard
    /// the old `blockMenu` had: a block can be deleted (by undo, by another gesture) while its menu
    /// is up, and the popover must not survive that — showing stale actions for a cel that no longer
    /// exists, or worse, crashing on the array access those actions perform. `.gap` and `.loop` carry
    /// no such stale reference — a frame number, and a layer index nothing here subscripts: the two
    /// accessors the gap arm's keyframe section asks, `keyframeTarget(layerIndex:)` and
    /// `gapFrameRange(layerIndex:containing:)`, each bounds-check and answer nil, which is what lets
    /// that arm keep going without a guard of its own.
    @ViewBuilder
    private var timelineMenuContent: some View {
        switch timelineMenu?.menu {
        case .block(let layerIndex, let celIndex, let frame):
            if canvasManager.layers.indices.contains(layerIndex) {
                menuList {
                    // Copy only snapshots the block's content onto the clipboard — it doesn't touch
                    // the timeline. Pasting it somewhere else happens from the target empty slot's
                    // own menu.
                    menuButton("Copy", icon: "doc.on.doc") {
                        canvasManager.copyCel(layerIndex: layerIndex, celIndex: celIndex)
                    }
                    menuButton("Select Multiple", icon: "square.on.square.dashed") { }
                        .disabled(true)
                    menuButton("Extend to End", icon: "arrow.right.to.line") {
                        canvasManager.extendCelToEnd(layerIndex: layerIndex, celIndex: celIndex)
                    }
                    // VIDEO.md §8 stage 1. Always shown, never hidden — the only reason the row is
                    // ever unavailable is a cut at the edge (a one-frame cel included, which has no
                    // interior frame at all), so a disabled row always means the same thing. A
                    // keyframe-animated cel is not excluded — `canSplitCel`'s own doc names the proof
                    // that rests on. `canSplitCel` is the one place the rule is written; nothing here
                    // re-derives it.
                    menuButton("Split Drawing", icon: "square.split.2x1") {
                        canvasManager.splitCel(layerIndex: layerIndex, celIndex: celIndex, atFrame: frame)
                    }
                    .disabled(!canvasManager.canSplitCel(layerIndex: layerIndex, celIndex: celIndex, atFrame: frame))
                    videoSpeedItems(layerIndex: layerIndex, celIndex: celIndex)
                    menuButton("Clear", icon: "eraser") {
                        canvasManager.clearCel(layerIndex: layerIndex, celIndex: celIndex)
                    }
                    keyframeItems(layerIndex: layerIndex, frame: frame,
                                  clearing: canvasManager.celFrameRange(layerIndex: layerIndex,
                                                                        celIndex: celIndex))
                    if canvasManager.layers[layerIndex].cels.count > 1 {
                        menuButton("Delete", icon: "trash", role: .destructive) {
                            canvasManager.deleteCel(layerIndex: layerIndex, celIndex: celIndex)
                        }
                    }
                }
            }

        case .gap(let layerIndex, let frame):
            menuList {
                menuButton("Add Drawing", icon: "plus.square") {
                    canvasManager.currentLayerIndex = layerIndex
                    canvasManager.addCel(layerIndex: layerIndex, startFrame: frame, frameCount: 1)
                    canvasManager.goToFrame(frame)
                }
                if canvasManager.copiedCel != nil {
                    menuButton("Paste", icon: "doc.on.clipboard") {
                        canvasManager.currentLayerIndex = layerIndex
                        canvasManager.pasteCel(layerIndex: layerIndex, startFrame: frame)
                        canvasManager.goToFrame(frame)
                    }
                }
                // **A gap gets the keyframe section too, and leaving it out lost a region of the
                // model outright.** D2 repurposed §2.22's keyframe button into the graph editor
                // toggle on the reasoning that Add / Remove / Clear had moved to the cel menu — true,
                // and incomplete: §2.4 and §2.26 put marks on the *layer* in absolute document
                // frames, and `TimelineKeyMarkers` says in as many words that they "exist perfectly
                // well at frames the layer has no cel at". With the items only on the `.block` arm,
                // a layer whose one cel covers frames 0–9 could not be given a bare mark at frame 20
                // by any gesture in the app.
                keyframeItems(layerIndex: layerIndex, frame: frame,
                              clearing: canvasManager.gapFrameRange(layerIndex: layerIndex,
                                                                    containing: frame))
            }

        case .loop(let frame):
            menuList {
                menuButton("Set Loop Start", icon: "arrow.right.to.line") { canvasManager.setLoopStart(frame) }
                menuButton("Set Loop End", icon: "arrow.left.to.line") { canvasManager.setLoopEnd(frame) }
                if canvasManager.hasLoopBoundary {
                    menuButton("Clear Loop Range", icon: "xmark", role: .destructive) {
                        canvasManager.clearLoopRange()
                    }
                }
            }

        // **The graph editor node's own menu** — TODO (38)(b), and the fourth arm of the one engine.
        //
        // > *"Clicking on a node twice just like clicking on a cel twice brings up the menu and the
        // > option to delete it."*
        //
        // **This is where Delete lives now.** Until 2026-09-03 a single tap on a node removed it,
        // which is a destructive default on a surface where a fingertip is 22 pt across; the first
        // tap focuses the node and draws its bezier handles, and this is the second. It is the
        // `.block` arm's contract in every respect that matters — a second tap on the thing already
        // selected, a popover hung off that thing's own column, and one press of Undo behind whatever
        // it does.
        //
        // **Both actions go through `CanvasManager`, not through a curve edit written here**, because
        // this file is not compiled into `PaintSoftwareUITests` and a rule spelled here is pinned by
        // nothing — `TimelineGraphBand`'s doc gives that argument at length. They funnel to
        // `setEffectParameterTrack`, which is the one writer that drops a mark the node was standing
        // on, so a node deleted from here takes its keyframe indicator with it exactly as one dragged
        // off its frame does.
        case .graphNode(let layerIndex, let parameterID, let frame):
            menuList {
                // Offered only where there is something to reset — an authored tangent rather than a
                // derived one — which is `Clear Loop Range`'s rule on the arm above. It is also the
                // only way back out of `.free` once a handle has been dragged, so its absence on an
                // untouched node is the honest signal that the node is already on the default.
                if canvasManager.effectParameterKeyIsAuthored(layerIndex: layerIndex,
                                                              parameterID: parameterID, frame: frame) {
                    menuButton("Reset Curve", icon: "arrow.uturn.backward") {
                        canvasManager.resetEffectParameterKeyCurve(layerIndex: layerIndex,
                                                                   parameterID: parameterID,
                                                                   frame: frame)
                    }
                }
                menuButton("Delete Keyframe", icon: "trash", role: .destructive) {
                    canvasManager.removeEffectParameterKey(layerIndex: layerIndex,
                                                           parameterID: parameterID, frame: frame)
                }
            }

        case nil:
            EmptyView()
        }
    }

    /// **The timeline menu's keyframe section** — §2.26, where a keyframe is placed and taken back.
    /// **On both arms**: a block and an empty slot, because §2.28's union covers the whole track and
    /// not only the part of it with drawings on.
    ///
    /// **Which target.** The layer the tapped block or slot belongs to, by id, through the one
    /// conversion `KeyframeTarget` exposes. §2.4 puts keys and marks on the layer rather than on the
    /// cel, so there is nothing about the block itself in the address; the tap only says *which
    /// layer* and *which frame*.
    ///
    /// **Which frame.** The one carried in the request, which `handleTapOnCel` / `handleTapOnGap` set
    /// to the playhead at the instant the menu opened — the owner's ruling that the two are the same
    /// thing here, held by the two-stage tap. Reading `currentFrame` now instead would key wherever a
    /// running playback timer had since carried it.
    ///
    /// **What Clear is scoped to, which is the caller's knowledge and not this function's.** For a
    /// block it is the frames that block covers (`celFrameRange`); for an empty slot it is the run of
    /// empty frames the artist tapped (`gapFrameRange`). A range query either way, not a container
    /// lookup: an effect key lives on the layer in absolute document frames, so neither a cel nor a
    /// gap has a list of keyframes to empty and this is the only sense in which either has any. The
    /// owner's *"clear all keyframes in that cel"* generalises to *the stretch of track you tapped*,
    /// and it has to generalise to something, because a mark can be placed anywhere on the track and
    /// a Clear that only existed over cels would leave a gap full of marks removable one at a time.
    ///
    /// **`nil` is a legal answer and means no Clear item** — a block that has been undone out from
    /// under its own menu, or a frame that turned out to be inside a cel after all.
    ///
    /// Both conditional items follow the Delete item's precedent a few lines up — offered only when
    /// they would do something, rather than shown greyed. Neither is `.destructive`: red is this
    /// menu's mark for losing a whole drawing, and Clear, which empties the cel's ink, is not red
    /// either.
    @ViewBuilder
    private func keyframeItems(layerIndex: Int, frame: Int, clearing scope: Range<Int>?) -> some View {
        if let target = canvasManager.keyframeTarget(layerIndex: layerIndex) {
            menuButton("Add Keyframe", icon: "plus.diamond") {
                canvasManager.addKeyframe(target, atFrame: frame)
            }
            if canvasManager.hasKeyframe(target, atFrame: frame) {
                menuButton("Remove Keyframe", icon: "minus.diamond") {
                    canvasManager.removeKeyframe(target, atFrame: frame)
                }
            }
            if let scope, canvasManager.hasKeyframe(target, inFrames: scope) {
                menuButton("Clear Keyframes", icon: "xmark.diamond") {
                    canvasManager.clearKeyframes(target, inFrames: scope)
                }
            }
        }
    }

    /// **VIDEO.md §2.5's Adjust Speed**, shown only on a block that holds a video — so an ordinary
    /// block's menu is exactly the menu it was.
    ///
    /// **Flat rows rather than a nested `Menu`**, which is a deliberate refusal rather than a
    /// simplification: this popover is hand-built out of a `VStack` (`menuList`) under
    /// `.presentationCompactAdaptation(.popover)`, so a SwiftUI `Menu` here would be a presentation
    /// inside a presentation — a shape nothing else in this app uses and nothing in the fast tier
    /// could pin, since this file is not compiled into `PaintSoftwareUITests`.
    ///
    /// **The list and the arithmetic both live on `CanvasManager`** for that same reason:
    /// `videoSpeedChoices` is a static there and `frameForFrameVideoSpeed` computes §2.3's setting
    /// per clip, so what this file holds is a row per value and no rule at all. `TimelineGraphBand`'s
    /// doc gives the argument at length.
    ///
    /// Frame for Frame is offered only when the clip says what rate it runs at — a legal thing for a
    /// file not to say — and it is the one row whose number depends on the footage rather than on a
    /// list.
    @ViewBuilder
    private func videoSpeedItems(layerIndex: Int, celIndex: Int) -> some View {
        if let current = canvasManager.videoSpeed(layerIndex: layerIndex, celIndex: celIndex) {
            Text("Adjust Speed")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(CanvasManager.videoSpeedChoices, id: \.self) { choice in
                menuButton(Self.speedTitle(choice),
                           icon: Self.isSameSpeed(current, choice) ? "checkmark" : "speedometer") {
                    canvasManager.setVideoSpeed(layerIndex: layerIndex, celIndex: celIndex, to: choice)
                }
            }
            if let frameForFrame = canvasManager.frameForFrameVideoSpeed(layerIndex: layerIndex,
                                                                        celIndex: celIndex) {
                menuButton("Frame for Frame",
                           icon: Self.isSameSpeed(current, frameForFrame) ? "checkmark" : "film.stack") {
                    canvasManager.setVideoSpeed(layerIndex: layerIndex, celIndex: celIndex,
                                                to: frameForFrame)
                }
            }
        }
    }

    /// "1× (real time)" for the default and "0.5×" for the rest — the multiplier is the number the
    /// artist is choosing, and only one of them needs saying out loud.
    private static func speedTitle(_ speed: Double) -> String {
        let number = speed == speed.rounded() ? String(Int(speed)) : String(speed)
        return speed == 1 ? "1× (real time)" : "\(number)×"
    }

    /// Speeds are `Double`s an artist picked off a list or a clip's own rate produced, so they are
    /// compared with a tolerance rather than by `==`: 24/30 is not 0.8 in binary and a checkmark that
    /// depended on that would simply never appear.
    private static func isSameSpeed(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    private func menuList<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, 6)
            .frame(minWidth: 190)
    }

    private func menuButton(_ title: String, icon: String, role: ButtonRole? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(role: role) {
            action()
            timelineMenu = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(role == .destructive ? .red : .primary)
        .accessibilityIdentifier("timeline.menu.\(title)")
    }

    // MARK: - Resizing

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.35))
            .frame(width: 32, height: 4)
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
            .frame(height: dragHandleHeight)
    }

    /// Drag up to grow the timeline, down to shrink it — continuous all the way into the collapsed
    /// bar, so hiding it is the bottom of the same motion rather than a separate mode. This is also
    /// why the collapsed bar carries no "expand" chevron: the same swipe that shrank the panel is
    /// what brings it back, from anywhere on the bar.
    private var resizeGesture: some Gesture {
        // `.global` coordinate space, not the default `.local`: the drag handle's own view moves
        // upward as the panel grows, so measuring translation in its local frame creates a feedback
        // loop where the handle keeps "running away" from the finger — global coordinates are fixed
        // to the screen and don't have that problem.
        // A minimum distance at all, because this is a `simultaneousGesture` over the *whole* top bar
        // and the buttons in it have to keep working: 6 pt is far enough that a tap never starts a
        // resize and near enough that a deliberate drag feels immediate.
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                let proposed = resizeStartHeight ?? timelineHeight
                if resizeStartHeight == nil { resizeStartHeight = timelineHeight }
                timelineHeight = clampedHeight(proposed - value.translation.height)
            }
            .onEnded { _ in
                resizeStartHeight = nil
                // Anything below the halfway point of the first real row settles as collapsed, so a
                // drag can't leave the timeline stuck at an unusable in-between height.
                if timelineHeight < minExpandedHeight { timelineHeight = collapsedHeight }
            }
    }

    /// Heights the timeline is allowed to take: collapsed at the bottom, and never so tall that it
    /// crowds out the canvas. `availableHeight` comes from the parent rather than the screen, so
    /// this stays correct in Split View and Slide Over.
    private func clampedHeight(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, collapsedHeight), maxTimelineHeight)
    }

    /// Leaves just enough room for the top toolbar to stay visible above the panel; otherwise the
    /// timeline is free to grow across essentially the whole available height, not just half of it.
    private var maxTimelineHeight: CGFloat {
        max(availableHeight - 64, minExpandedHeight)
    }

    // MARK: - Transport

    /// Play / step / jump, as one group. Both bars centre this group in the panel rather than
    /// stacking it against the leading edge, so the controls sit under the thumb of a hand holding
    /// the iPad rather than off in a corner.
    private var transportControls: some View {
        HStack(spacing: 20) {
            Button(action: { canvasManager.goToFrame(0) }) {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityIdentifier("timeline.toStartButton")

            Button(action: { canvasManager.stepFrame(by: -1) }) {
                Image(systemName: "backward.frame.fill")
            }
            .accessibilityIdentifier("timeline.stepBackButton")

            Button(action: canvasManager.togglePlayback) {
                Image(systemName: canvasManager.isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityIdentifier("timeline.playButton")

            Button(action: { canvasManager.stepFrame(by: 1) }) {
                Image(systemName: "forward.frame.fill")
            }
            .accessibilityIdentifier("timeline.stepForwardButton")

            // The end of the *animation*, not of the laid-out track — jumping to frame 11 of a
            // two-frame scene parked the playhead on empty space (see `contentEndFrame`).
            Button(action: { canvasManager.goToFrame(max(canvasManager.contentEndFrame - 1, 0)) }) {
                Image(systemName: "forward.end.fill")
            }
            .accessibilityIdentifier("timeline.toEndButton")
        }
    }

    /// Two-stage, like `interpolateButton` and like the paint tools: the first tap turns onion skin
    /// on, and a tap once it is already on opens `OnionSkinPanel`. That is why the panel carries no
    /// on/off switch of its own — the button is the switch, and the panel is only reachable from the
    /// on state.
    ///
    /// The panel is a popover here rather than an `ActivePanel` case in the top toolbar because
    /// onion skin's subject is the timeline, which is the same argument `interpolateButton` records
    /// from the owner (2026-08-01).
    private var onionSkinButton: some View {
        Button(action: {
            if canvasManager.isOnionSkinEnabled {
                showOnionSkinOptions.toggle()
            } else {
                canvasManager.isOnionSkinEnabled = true
            }
        }) {
            Image(systemName: canvasManager.isOnionSkinEnabled
                  ? "square.stack.3d.forward.dottedline.fill"
                  : "square.stack.3d.forward.dottedline")
        }
        .foregroundColor(canvasManager.isOnionSkinEnabled ? .blue : .white)
        .accessibilityIdentifier("timeline.onionSkinToggle")
        // The panel itself is drawn by `anchoredMenuLayer`, over the canvas above this bar; this
        // button contributes the anchor it hangs from and the registration that keeps every rule a
        // `.popover` here used to carry. **The near-black card `AnchoredMenu` draws is what replaces
        // this site's old `.presentationBackground(Color.black.opacity(0.96))`** — every label in
        // this panel is white, and on a popover's default light material it rendered white-on-white.
        .anchoredMenuAnchor(.onionSkinOptions)
        .canvasPresentationRegistration(.onionSkinOptions, isPresented: $showOnionSkinOptions,
                                        canvasManager: canvasManager)
        // "Turn Off Onion Skin" lives inside the panel, so the panel has to close itself when it is
        // used — otherwise it stays up describing something that is no longer drawing.
        .onChange(of: canvasManager.isOnionSkinEnabled) { _, on in
            if !on { showOnionSkinOptions = false }
        }
    }

    private var loopButton: some View {
        Button(action: { canvasManager.isLoopEnabled.toggle() }) {
            Image(systemName: "repeat")
        }
        .foregroundColor(canvasManager.isLoopEnabled ? .blue : .white)
        .accessibilityIdentifier("timeline.loopButton")
    }

    /// **Opens the graph editor on the selected layer** — KEYFRAMES.md §11.3, and ask 3's own tail:
    /// *"When tapping the keyframe button it brings up the list of things being animated and graph
    /// editor instead of placing a keyframe (icon and its name also may have to be changed to graph
    /// editor)."*
    ///
    /// **The keyframe it used to place is not lost, it moved.** Add / Remove / Clear Keyframes are in
    /// the cel menu (`keyframeItems`), which is the workflow §2.26 describes and where the artist is
    /// already standing when they want one — beside the block, at the frame they tapped, rather than
    /// at wherever a playback timer has since carried the playhead.
    ///
    /// **`chart.xyaxis.line`**: a plotted line against a drawn pair of axes, which is what a graph
    /// editor *is* and what distinguishes it from the neighbouring
    /// `point.topleft.down.to.point.bottomright.curvepath` on the interpolate button — that one is a
    /// bare curve between two points, which is in-betweening, and §2.8 is the standing rule that the
    /// two kinds of "keyframe" must never read as one thing.
    ///
    /// **Tinted like `interpolateButton` rather than always white.** The band opens inside the
    /// timeline's scroll content, so with enough layers it can be open and scrolled out of sight; a
    /// button that looks the same either way leaves the artist with no way to tell a closed editor
    /// from one that is simply below the fold.
    ///
    /// **Rendered from both `collapsedBar` and `miniToolbar`, like every other button in this group.**
    /// A control added to only one is invisible in the other state, and the collapsed bar is exactly
    /// where an artist who dragged the timeline down will look for it. It is also where the tint earns
    /// the most: collapsed, the band is not on screen at all.
    ///
    /// The channel list ask 3 also wants is **not** on this button — §11.5 makes it a control of the
    /// graph editor's own (`graphChannelsButton`, which appears beside this one while the band is
    /// open), because hanging a second popover here would give one control two jobs and one of them
    /// would have to win the second tap.
    private var graphEditorButton: some View {
        Button(action: { canvasManager.isGraphEditorOpen.toggle() }) {
            Image(systemName: "chart.xyaxis.line")
        }
        .foregroundColor(canvasManager.isGraphEditorOpen ? .blue : .white)
        .accessibilityIdentifier("timeline.graphEditorButton")
    }

    /// **The graph editor's channel list** — KEYFRAMES.md §11.5, stage D4. The owner: *"just a button
    /// option in the graph editor which brings up a scrollable popup menu, which is basically an
    /// include or exclude checkmark box for each animation."*
    ///
    /// **Beside the graph editor button rather than on it, and rendered only while the band is
    /// open.** A toggle that also raises a menu has no good gesture — the second tap has to mean one
    /// of the two — so ask 3's "the button brings up the list as well" is answered by a second
    /// button that exists exactly when there is an editor for it to be an option of.
    ///
    /// **Tinted blue while anything is switched off**, `graphEditorButton`'s reason: a filter with no
    /// visible sign of itself is a band that looks broken. It matters most in the state that has no
    /// other signal — every channel hidden, so the band is correctly blank and only this says why.
    private var graphChannelsButton: some View {
        Button(action: { canvasManager.isGraphChannelListOpen.toggle() }) {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .foregroundColor(canvasManager.graphBandHasHiddenChannels ? .blue : .white)
        .accessibilityIdentifier("timeline.graphChannelsButton")
        // **`isPresented` is on the model, unlike every other popover in this file.** The list is a
        // control *of* the editor and may not outlive it — closing the band deletes this very button,
        // and a popover whose host is destroyed while it is up re-presents itself when the host
        // returns. That rule belongs where it can be pinned: `CanvasManager.isGraphChannelListOpen`,
        // cleared by `isGraphEditorOpen`'s `didSet` beside the filter it is the twin of. The other
        // popovers here are `@State` because they have no such rule.
        .anchoredMenuAnchor(.graphChannelList)
        .canvasPresentationRegistration(.graphChannelList,
                                        isPresented: $canvasManager.isGraphChannelListOpen,
                                        canvasManager: canvasManager)
    }

    /// The popup itself: one section per group, each a whole-group box over its channels' boxes.
    ///
    /// **Scrollable, because the owner asked for it and because thirteen effects' worth of channels
    /// will not fit** — and capped in height so a short list is a short popover rather than a tall
    /// one with air in it.
    ///
    /// **A group's rows fold now, and its header's body raises the Move box** — KEYFRAMES.md §11.7,
    /// which is where the two rulings this surface carries are recorded.
    ///
    /// §11.5 deferred the fold because *"a band is one layer, a layer is one grade and a grade is one
    /// id prefix, so every band today has exactly one group"*, and a chevron over one group folds the
    /// only thing in the list. The transform channel is the second channel source that premise was
    /// waiting for: a band can now show a grade beside one or more Move channels, so a fold has
    /// something to fold, and `TimelineGraphChannelList.Fold` scopes it to the band it was made on —
    /// which answers §11.5's other objection rather than waiving it.
    private var graphChannelList: some View {
        let groups = canvasManager.graphChannelGroups ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if groups.isEmpty {
                    // The same answer the band gives, in words: a surface that came up holding
                    // nothing says so rather than being blank (LASSO_MOVE §5.24, read across).
                    Text("This layer animates nothing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("timeline.graphChannels.empty")
                }
                ForEach(groups) { group in
                    graphChannelGroupRow(group)
                    if !group.isCollapsed {
                        ForEach(group.rows, id: \.parameterID) { row in
                            graphChannelRow(row)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 300)
        .alert("Rename Group", isPresented: Binding(get: { renamingAnimationGroup != nil },
                                                    set: { if !$0 { renamingAnimationGroup = nil } })) {
            TextField("Name", text: $animationGroupDraftName)
                .accessibilityIdentifier("timeline.graphChannels.nameField")
            Button("Cancel", role: .cancel) { renamingAnimationGroup = nil }
            Button("Save") {
                if let group = renamingAnimationGroup {
                    // Through the writer, never by writing `displayName` here: it is where the empty
                    // name is refused and where the one undo step is recorded, and a view that wrote
                    // the field would have neither.
                    canvasManager.renameAnimationGroup(group.id, to: animationGroupDraftName)
                }
                renamingAnimationGroup = nil
            }
        }
    }

    /// The group's header: a chevron that folds, a box that takes every channel under it, and a body
    /// that raises the Move box for the drawing the group names.
    ///
    /// **Three targets in one row, and they are three `Button`s rather than one with a `switch` on
    /// where the finger landed.** SwiftUI resolves that for us and the split is then legible from the
    /// layout; the alternative — one button plus a `simultaneousGesture` reading the location — is
    /// how a control comes to have a rule nobody can find. The chevron is present on every group,
    /// including a lone one, because a list whose rows appear and disappear with the *number* of
    /// groups is worse than one that always has the same furniture.
    private func graphChannelGroupRow(_ group: TimelineGraphChannelList.Group) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                canvasManager.setGraphGroupCollapsed(group.id, collapsed: !group.isCollapsed)
            }) {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .frame(width: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline.graphChannels.fold.\(group.id)")
            .accessibilityValue(group.isCollapsed ? "collapsed" : "expanded")
            Button(action: {
                canvasManager.setGraphChannels(group.rows.map(\.parameterID),
                                               visible: group.visibilityAfterToggle)
            }) {
                // Three states, because a group can be half off: checked, dashed, empty. The
                // dash is what stops "some are hidden" reading as "none are".
                Image(systemName: group.isMixed ? "minus.square"
                      : (group.isFullyVisible ? "checkmark.square.fill" : "square"))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline.graphChannels.group.\(group.id)")
            .accessibilityValue(group.isMixed ? "mixed" : (group.isFullyVisible ? "on" : "off"))
            Button(action: { revealGraphChannel(group.navigation) }) {
                HStack(spacing: 6) {
                    // **An animation group's tag colour, shown for the first time.** §3.4 calls it
                    // *"the swatch this group is drawn in when the timeline or a channel list names
                    // it"*, and until now nothing drew it — the swatch on a *channel* row is the
                    // band's curve colour, which is a different thing keyed on a different input. A
                    // generated colour nothing shows is a field that cannot be checked; a group with
                    // no tag (the whole cel's Move, a grade) draws none rather than a grey stand-in.
                    if let tag = canvasManager.animationGroup(named: group.navigation)?.tagColor {
                        Circle()
                            .fill(Color(red: tag.red, green: tag.green, blue: tag.blue)
                                .opacity(tag.alpha))
                            .frame(width: 8, height: 8)
                    }
                    Text(group.name).font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.navigation == nil)
            .accessibilityIdentifier("timeline.graphChannels.reveal.\(group.id)")
            // **Rename lives behind a long press rather than on the row**, for the reason the row's
            // three buttons are three buttons: the row already means fold / filter / reveal, and a
            // fourth target would leave no space that means "reveal" any more. A group whose name is
            // generated is the only thing here worth renaming — a grade's header is named by the
            // effect the artist picked, and the whole cel's Move is named by what it is.
            .contextMenu {
                if let animationGroup = canvasManager.animationGroup(named: group.navigation) {
                    Button {
                        animationGroupDraftName = animationGroup.displayName
                        renamingAnimationGroup = animationGroup
                    } label: {
                        Label("Rename Group", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("timeline.graphChannels.rename.\(group.id)")
                }
            }
        }
        .foregroundColor(group.isFullyVisible || group.isMixed ? .primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// **The click that raises the Move box** — §11.7's second ruling, wired here and decided in
    /// `CanvasManager.revealPoseChannel(_:)`. The popup goes down with it: the artist asked for the
    /// box, and leaving a list over the canvas they are about to drag on would cover the thing they
    /// came for.
    private func revealGraphChannel(_ channel: PoseChannelID?) {
        guard let channel else { return }
        canvasManager.isGraphChannelListOpen = false
        canvasManager.revealPoseChannel(channel)
    }

    /// One channel's row.
    ///
    /// **A row for a channel that is not an animation looks different, and that is §11.4's ruling of
    /// 2026-08-30 reaching this surface.** The band draws such a channel as a dashed, dimmed flat line
    /// (`TimelineGraphBand.Channel.isAnimated`), and the list is where the artist reads what the band
    /// is showing them — so the swatch is drawn **hollow**, matching the hollow key dots, and the name
    /// carries the word the picture cannot. Without it the list would say "Brightness, checked" about
    /// a line that is visibly not an animation, which is the same "no way to tell them apart" the dash
    /// exists to answer.
    private func graphChannelRow(_ row: TimelineGraphChannelList.Row) -> some View {
        // The swatch is the band's colour for this curve, taken from the **descriptor** index the
        // row carries — the same input the band draws with, so hiding a channel repaints nothing.
        let colour = TimelineGraphBand.colour(forDescriptorIndex: row.descriptorIndex)
        let swatch = Color(hue: colour.hue, saturation: colour.saturation,
                           brightness: colour.brightness)
        // **The box and the body are two buttons, §11.7's gesture split.** The box is the filter it
        // always was; the body raises the Move box for the channel the row names, and is disabled on
        // a grade's row because a Brightness curve has no subject to raise. The identifier stays on
        // the *box*, so every existing assertion about a row's on/off state still names the control
        // that carries it.
        return HStack(spacing: 8) {
            Button(action: {
                canvasManager.setGraphChannels([row.parameterID], visible: !row.isVisible)
            }) {
                Image(systemName: row.isVisible ? "checkmark.square.fill" : "square")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline.graphChannels.\(row.parameterID)")
            // Two facts on one value, comma-separated, because a row has two independent states and
            // XCUITest gives an element exactly one string to carry them in.
            .accessibilityValue((row.isVisible ? "on" : "off") + (row.isAnimated ? "" : ",flat"))
            Button(action: { revealGraphChannel(row.navigation) }) {
                HStack(spacing: 8) {
                    Group {
                        if row.isAnimated {
                            Circle().fill(swatch)
                        } else {
                            Circle().strokeBorder(swatch, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 8, height: 8)
                    .opacity(row.isVisible ? 1 : 0.3)
                    Text(row.name).font(.caption)
                    if !row.isAnimated {
                        Text("not animated").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.navigation == nil)
            .accessibilityIdentifier("timeline.graphChannels.reveal.\(row.parameterID)")
        }
        .foregroundColor(row.isVisible ? .primary : .secondary)
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    /// Interpolate mode's entry point, next to onion skin and loop rather than in the canvas's top
    /// toolbar — the mode's whole subject is the timeline, and so is every control it puts on screen
    /// (`InterpolateBar` right above this bar). Product owner, 2026-08-01.
    ///
    /// Two-stage like the paint tools: the first tap turns the mode on, and a tap once it is already
    /// on opens the options popover. That is why there is no mode switch inside the popover — the
    /// button *is* the switch, and the popover is only reachable from the on state.
    private var interpolateButton: some View {
        Button(action: {
            if canvasManager.isInterpolateMode {
                showInterpolateOptions.toggle()
            } else {
                canvasManager.enterInterpolateMode()
            }
        }) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .foregroundColor(canvasManager.isInterpolateMode ? .blue : .white)
        .accessibilityIdentifier("timeline.interpolateButton")
        .anchoredMenuAnchor(.interpolateOptions)
        .canvasPresentationRegistration(.interpolateOptions, isPresented: $showInterpolateOptions,
                                        canvasManager: canvasManager)
        // Exit Interpolate Mode is inside the popover, so the popover has to close itself when the
        // mode goes off — otherwise it stays up over a bar that is no longer there.
        .onChange(of: canvasManager.isInterpolateMode) { _, on in
            if !on { showInterpolateOptions = false }
        }
    }

    /// The denominator widens to admit the playhead **for display only** — the scene's own end is
    /// `contentEndFrame`, derived from the cels, and parking the playhead somewhere is not drawing
    /// there (see `goToFrame`, where authoring the document from a scrub shipped a real bug). Parking
    /// out past the end therefore reads "Frame 40/40" rather than the impossible "Frame 40/12"; the
    /// counter stops describing the scene's length out there, which is honest, because out there the
    /// playhead is not in the scene.
    private var frameLabel: some View {
        let shown = canvasManager.displayedSceneLength
        return Text("Frame \(canvasManager.currentFrame + 1)/\(shown)")
            .font(.caption)
            .foregroundColor(.gray)
            .accessibilityIdentifier("timeline.frameLabel")
    }

    // MARK: - Collapsed

    private var collapsedBar: some View {
        ZStack {
            HStack(spacing: 16) {
                onionSkinButton
                loopButton
                interpolateButton
                graphEditorButton
                if canvasManager.isGraphEditorOpen { graphChannelsButton }
                Spacer()
                frameLabel
            }
            transportControls
        }
        .foregroundColor(.white)
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Expanded mini toolbar

    private var miniToolbar: some View {
        ZStack {
            HStack(spacing: 14) {
                onionSkinButton
                loopButton
                interpolateButton
                graphEditorButton
                // Rendered from both bars, like every other button in this group: a control added to
                // only one is invisible in the other state.
                if canvasManager.isGraphEditorOpen { graphChannelsButton }

                Spacer()

                TextField("Scene", text: $canvasManager.projectName)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .frame(width: 110)

                frameLabel

                Text("\(canvasManager.fps) fps")
                    .font(.caption)
                    .foregroundColor(.gray)

                Button(action: { withAnimation(.easeOut(duration: 0.2)) { timelineHeight = collapsedHeight } }) {
                    Image(systemName: "chevron.down")
                }
                .accessibilityIdentifier("timeline.collapseButton")
            }
            transportControls
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Layer names (pinned, non-scrolling column)

    /// Mirrors the layer panel's row order exactly — same folder headers, same nesting, same
    /// collapse state — so the names line up with the track rows `TimelineTrackView` lays out from
    /// the same source. Rows reorder here too: press and hold one, then drag it up or down.
    private var layerNameColumn: some View {
        // Rows, layout and the lifted row's slot are resolved once for the whole column rather than
        // per row: each of the three used to re-read `layerStackRows`, which walks the layer tree.
        let rows = canvasManager.layerStackRows
        let layout = rowLayout
        let liftedFrom = draggingRowID.flatMap { id in rows.firstIndex { $0.id == id } }
        return VStack(alignment: .leading, spacing: TimelineRowLayout.gap) {
            Color.clear.frame(height: rulerHeight)
            ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                let isLifted = draggingRowID == row.id
                nameRow(row)
                    // **Two frames, and the inner one is what keeps this honest.** The name is
                    // centred in the *block* half of the row — which is the whole row for every row
                    // that has no graph editor band, so nothing moved — and that block is then
                    // pinned to the **top** of the full row. Centring the name in the full height
                    // instead would float it down beside the middle of the band, labelling the
                    // curves rather than the cel blocks it is the name of.
                    .frame(height: layout.blockHeight(ofRow: position), alignment: .leading)
                    .frame(height: layout.height(ofRow: position), alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(liftedBackground(isLifted: isLifted))
                    .contentShape(Rectangle())
                    .scaleEffect(isLifted ? 1.06 : 1, anchor: .leading)
                    .shadow(color: .black.opacity(isLifted ? 0.6 : 0), radius: 6, y: 3)
                    .offset(y: rowOffset(at: position, liftedFrom: liftedFrom, in: layout))
                    .zIndex(isLifted ? 1 : 0)
                    // The rows opening the gap ease into place; the lifted one must not, or it lags
                    // behind the finger by the animation's duration.
                    .animation(isLifted ? nil : .easeOut(duration: 0.18), value: dragOffsetRows)
                    .gesture(reorderGesture(for: row, at: position, in: layout))
            }
        }
        .frame(width: 110)
        .padding(.vertical, TimelineRowLayout.verticalInset)
    }

    /// The picked-up row gets a card of its own — dark fill, blue rim — so it reads as detached from
    /// the column and floating over it, the same lift the layer panel's drag snapshot has.
    @ViewBuilder
    private func liftedBackground(isLifted: Bool) -> some View {
        if isLifted {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 1))
                .padding(.trailing, 4)
        }
    }

    /// Where a row sits while a drag is in progress: the lifted one follows the finger, and the rows
    /// it is passing over slide one slot the other way to open the gap it would drop into.
    private func rowOffset(at position: Int, liftedFrom: Int?, in layout: TimelineRowLayout) -> CGFloat {
        guard let liftedFrom else { return 0 }
        if position == liftedFrom { return dragTranslation }
        return layout.reorderOffset(ofRow: position, liftedFrom: liftedFrom, movedBy: dragOffsetRows)
    }

    @ViewBuilder
    private func nameRow(_ row: LayerStackRow) -> some View {
        switch row {
        case .folder(let folderID, let depth, let kind):
            if let folder = canvasManager.folders.first(where: { $0.id == folderID }) {
                HStack(spacing: 3) {
                    Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .onTapGesture { canvasManager.toggleFolderExpanded(folderID) }
                    // Same three glyphs the layer panel's rows use (`LayerStackCell.configure`), so
                    // a node reads as a node in both columns rather than as a folder in one of them.
                    Image(systemName: folderIcon(kind))
                        .font(.system(size: 9))
                        .foregroundColor(kind == .group ? .yellow : .teal)
                    Text(folder.name)
                        .font(.caption)
                        .foregroundColor(folder.isVisible ? .white : .gray)
                        .lineLimit(1)
                        .accessibilityIdentifier("timeline.folderName.\(folder.name)")
                }
                .padding(.leading, 6 + CGFloat(depth) * 10)
            }

        case .layer(_, let index, let depth) where canvasManager.layers.indices.contains(index):
            Text(canvasManager.layers[index].name)
                .font(.caption)
                .foregroundColor(index == canvasManager.currentLayerIndex ? .blue : .white)
                .lineLimit(1)
                .padding(.leading, 8 + CGFloat(depth) * 10)
                .accessibilityIdentifier("timeline.layerName.\(index)")

        default:
            EmptyView()
        }
    }

    private func folderIcon(_ kind: LayerStackRow.FolderKind) -> String {
        switch kind {
        case .group:          return "folder.fill"
        case .compositorNode: return "camera.filters"
        }
    }

    /// Press and hold for half a second, then drag: the same reorder gesture the layer panel uses,
    /// resolved here by counting the rows the finger travelled over — a walk of their pitches rather
    /// than a division, so a row that is taller than its neighbours still counts as one row.
    private func reorderGesture(for row: LayerStackRow, at position: Int,
                                in layout: TimelineRowLayout) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                // Every row lifts. The one refusal that used to live here — an input slot, whose
                // position among its siblings *was* its stored index — went with the slots (§4.3);
                // a node's operands are ordinary children and reordering them is the point.
                draggingRowID = row.id
                dragTranslation = 0
                dragOffsetRows = 0
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(_, let drag?) = value, draggingRowID == row.id else { return }
                dragTranslation = drag.translation.height
                dragOffsetRows = layout.rowsCrossed(from: position, by: drag.translation.height)
            }
            .onEnded { _ in
                let delta = dragOffsetRows
                let wasDragging = draggingRowID == row.id
                // Settle the lift before the restack so the card visibly drops into the gap the
                // other rows opened, rather than blinking out and reappearing somewhere new.
                withAnimation(.easeOut(duration: 0.15)) {
                    draggingRowID = nil
                    dragTranslation = 0
                    dragOffsetRows = 0
                }
                guard wasDragging, delta != 0 else { return }
                commitReorder(of: row, byRows: delta)
            }
    }

    /// Applies a drag of `delta` rows (positive = downward on screen = lower in the stack) by
    /// resolving what the moved row would come to rest between, then handing that to the same
    /// restack calls the layer panel uses.
    private func commitReorder(of row: LayerStackRow, byRows delta: Int) {
        let rows = canvasManager.layerStackRows
        guard let from = rows.firstIndex(where: { $0.id == row.id }) else { return }
        var reordered = rows
        let moved = reordered.remove(at: from)
        let target = min(max(from + delta, 0), reordered.count)
        reordered.insert(moved, at: target)
        guard let newIndex = reordered.firstIndex(where: { $0.id == moved.id }) else { return }

        var parentFolderID: UUID?
        if newIndex > 0 {
            let above = reordered[newIndex - 1]
            parentFolderID = above.isFolder ? above.id : canvasManager.layers.first { $0.id == above.id }?.parentFolderID
        }

        func anchor(_ below: LayerStackRow?) -> CanvasManager.StackAnchor {
            guard let below else { return .bottom }
            return below.isFolder ? .folder(below.id) : .layer(below.id)
        }

        if moved.isFolder {
            var contents = canvasManager.folderSubtree(moved.id)
            for index in canvasManager.descendantLayerIndices(ofFolder: moved.id) {
                contents.insert(canvasManager.layers[index].id)
            }
            let below = reordered[(newIndex + 1)...].first { !contents.contains($0.id) }
            canvasManager.restackFolder(moved.id, above: anchor(below), parentFolderID: parentFolderID)
        } else {
            let below = reordered.indices.contains(newIndex + 1) ? reordered[newIndex + 1] : nil
            canvasManager.restackLayer(moved.id, above: anchor(below), parentFolderID: parentFolderID)
        }
    }
}
