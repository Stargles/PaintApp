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

    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?

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

    /// Vertical distance between two track rows — the row plus the `VStack` spacing between them.
    private var rowPitch: CGFloat { rowHeight + 2 }

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
    @State private var draggingRowID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragOffsetRows: Int = 0

    var body: some View {
        // The interpolate bar sits *outside* the height-constrained timeline rather than inside it,
        // so turning the mode on adds a strip above the panel instead of eating rows out of it.
        VStack(spacing: 0) {
            if canvasManager.isInterpolateMode {
                InterpolateBar(canvasManager: canvasManager)
            }
            timelinePanel
        }
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
                    .frame(height: contentHeight)
                }
                .frame(height: max(0, timelineHeight - topBarHeight - dividerHeight))
            }
        }
        .frame(height: timelineHeight)
        .background(Color.black)
        .overlay(alignment: .topLeading) { menuAnchorLayer }
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
        // Touching the canvas closes whatever timeline menu is open, *before* the touch becomes a
        // stroke — the same contract `DrawingView` already applies to the top-bar dropdowns, and for
        // a sharper reason than tidiness.
        //
        // `timelineMenu` drives a `.popover`, and a popover left to its own dismissal is dismissed
        // *by* the touch that lands outside it. When that touch is the start of a stroke, the
        // presentation is torn down in the middle of the touch sequence, and UIKit then never sends
        // `StrokeGestureRecognizer` its `reset()`: the recognizer is stranded in a terminal-but-not-
        // `.failed` state, and
        // `CanvasView.Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)` has all three
        // canvas-transform recognizers waiting on exactly that recognizer failing. Two-finger
        // pan/pinch/rotate then stay dead for the life of the drawing view — the reported freeze,
        // and the reason returning to the gallery and reopening clears it without an app quit.
        //
        // `interactionBegan` fires from `StrokeGestureRecognizer.touchesBegan` before any of that,
        // so the popover is on its way out before the sequence it would otherwise break is underway.
        // Pinned by `CanvasTransformFreezeUITests`.
        .onReceive(canvasManager.interactionBegan) {
            timelineMenu = nil
        }
        .onDisappear { stopPlayback() }
    }

    /// Height of the grab handle plus whichever bar is showing — the fixed chrome above the tracks.
    private var topBarHeight: CGFloat {
        dragHandleHeight + (isCollapsed ? collapsedBarHeight : miniToolbarHeight)
    }

    private var contentHeight: CGFloat {
        rulerHeight + CGFloat(max(canvasManager.layerStackRows.count, 1)) * rowPitch + 8
    }

    // MARK: - Menus

    /// One zero-content view parked exactly where the tapped block / slot / ruler column is,
    /// carrying the single popover for whichever menu `timelineMenu` says is open. SwiftUI can only
    /// anchor a popover to a view, so the anchor has to exist as a view; it's transparent and takes
    /// no touches, so nothing about the timeline changes while no menu is up. When `timelineMenu`
    /// is nil the rect falls back to `.zero` — harmless, since `isPresented` is false at the same
    /// time and a popover with no content presented has nothing to anchor.
    private var menuAnchorLayer: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            menuAnchor(timelineMenu?.anchor ?? .zero, relativeTo: origin, isPresented: isTimelineMenuPresented) {
                timelineMenuContent
            }
        }
        .allowsHitTesting(false)
    }

    /// `.popover(isPresented:)` wants a `Bool`, but `timelineMenu` is the one piece of state that
    /// answers both "is a menu open" and "which one" — this derives the former from the latter. The
    /// setter is what makes the system's *own* dismissal (tap outside the popover, swipe down on
    /// iPhone's compact presentation) clear `timelineMenu` too, rather than leaving a stale payload
    /// behind a `Bool` that had already gone false.
    private var isTimelineMenuPresented: Binding<Bool> {
        Binding(get: { timelineMenu != nil }, set: { if !$0 { timelineMenu = nil } })
    }

    /// Two things about this order are load-bearing.
    ///
    /// `.position`, not `.offset`: a popover attaches to its anchor view's *layout* frame, and
    /// `.offset` is a render-time translation that leaves that frame where it started — every menu
    /// came up in the panel's top-left corner regardless of what had been tapped.
    ///
    /// And `.popover` goes *before* `.position`, because `.position` returns a view that fills all
    /// the space offered to it. Attaching the popover after it anchors the menu to the whole overlay
    /// and it comes up centred on the timeline — the very thing being fixed here.
    private func menuAnchor<Content: View>(_ rect: CGRect,
                                           relativeTo origin: CGPoint,
                                           isPresented: Binding<Bool>,
                                           @ViewBuilder content: @escaping () -> Content) -> some View {
        Color.clear
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .popover(isPresented: isPresented, content: content)
            .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
    }

    /// The one menu's content, resolved from whichever case `timelineMenu` currently holds.
    ///
    /// The `.block` branch keeps the same `canvasManager.layers.indices.contains(layerIndex)` guard
    /// the old `blockMenu` had: a block can be deleted (by undo, by another gesture) while its menu
    /// is up, and the popover must not survive that — showing stale actions for a cel that no longer
    /// exists, or worse, crashing on the array access those actions perform. `.gap` and `.loop` carry
    /// no such stale reference (a frame number and a layer index used only to set `currentLayerIndex`
    /// are never subscripted), so they need no equivalent guard — same as before the merge.
    @ViewBuilder
    private var timelineMenuContent: some View {
        switch timelineMenu?.menu {
        case .block(let layerIndex, let celIndex):
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
                    menuButton("Clear", icon: "eraser") {
                        canvasManager.clearCel(layerIndex: layerIndex, celIndex: celIndex)
                    }
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

        case nil:
            EmptyView()
        }
    }

    private func menuList<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, 6)
            .frame(minWidth: 190)
            .presentationCompactAdaptation(.popover)
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

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
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
        .popover(isPresented: $showOnionSkinOptions) {
            OnionSkinPanel(canvasManager: canvasManager)
                .frame(width: 380, height: 590)
                .presentationCompactAdaptation(.popover)
                // **A popover's default background is a light system material, and every label in
                // this app's chrome is white.** Without this the panel renders white-on-white and is
                // legible only where a control paints its own background — which a screenshot of the
                // first build showed exactly. Stated here rather than inside the panel because the
                // material is the *presentation's*, not the content's: a `.background` on the content
                // leaves the arrow and the inset light.
                .presentationBackground(Color.black.opacity(0.96))
        }
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
        .popover(isPresented: $showInterpolateOptions) {
            InterpolatePanel(canvasManager: canvasManager)
                .frame(width: 260)
                .presentationCompactAdaptation(.popover)
        }
        // Exit Interpolate Mode is inside the popover, so the popover has to close itself when the
        // mode goes off — otherwise it stays up over a bar that is no longer there.
        .onChange(of: canvasManager.isInterpolateMode) { _, on in
            if !on { showInterpolateOptions = false }
        }
    }

    /// The denominator widens to admit the playhead **for display only** — it is not written back to
    /// `sceneFrameCount`, which is an input to cel creation and so may only be changed by an edit
    /// (see `goToFrame`, where doing this in the model shipped a real bug). Parking out past the end
    /// of the scene therefore reads "Frame 40/40" rather than the impossible "Frame 40/12"; the
    /// counter stops describing the scene's length out there, which is honest, because out there the
    /// playhead is not in the scene.
    private var frameLabel: some View {
        let shown = max(canvasManager.sceneFrameCount, canvasManager.currentFrame + 1)
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
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: rulerHeight)
            ForEach(Array(canvasManager.layerStackRows.enumerated()), id: \.element.id) { position, row in
                let isLifted = draggingRowID == row.id
                nameRow(row)
                    .frame(height: rowHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(liftedBackground(isLifted: isLifted))
                    .contentShape(Rectangle())
                    .scaleEffect(isLifted ? 1.06 : 1, anchor: .leading)
                    .shadow(color: .black.opacity(isLifted ? 0.6 : 0), radius: 6, y: 3)
                    .offset(y: rowOffset(at: position))
                    .zIndex(isLifted ? 1 : 0)
                    // The rows opening the gap ease into place; the lifted one must not, or it lags
                    // behind the finger by the animation's duration.
                    .animation(isLifted ? nil : .easeOut(duration: 0.18), value: dragOffsetRows)
                    .gesture(reorderGesture(for: row))
            }
        }
        .frame(width: 110)
        .padding(.vertical, 4)
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
    private func rowOffset(at position: Int) -> CGFloat {
        guard let draggingRowID else { return 0 }
        let rows = canvasManager.layerStackRows
        guard let from = rows.firstIndex(where: { $0.id == draggingRowID }) else { return 0 }
        if position == from { return dragTranslation }

        let to = min(max(from + dragOffsetRows, 0), max(rows.count - 1, 0))
        if from < to, position > from, position <= to { return -rowPitch }
        if from > to, position >= to, position < from { return rowPitch }
        return 0
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
    /// resolved here by counting how many fixed-height rows the finger travelled.
    private func reorderGesture(for row: LayerStackRow) -> some Gesture {
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
                dragOffsetRows = Int((drag.translation.height / rowPitch).rounded())
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

    // MARK: - Playback

    /// Play/pause. Where playback stops or wraps is `CanvasManager`'s call (`advancePlayback`), which
    /// treats a missing loop marker as the first/last frame: looping on wraps at the end back to the
    /// start, looping off runs to the end and stops there instead of sitting on the last frame with
    /// the timer still ticking.
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }
        canvasManager.goToFrame(canvasManager.playbackEntryFrame())
        isPlaying = true
        let interval = 1.0 / Double(max(canvasManager.fps, 1))
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                if !canvasManager.advancePlayback() { stopPlayback() }
            }
        }
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
    }
}
