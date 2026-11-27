import Combine   // objectWillChange.send()
import SwiftUI
import UIKit

// MARK: - Fill (interactive: press to apply, drag to adjust gap-closing / edge-overlap)
//
// The interactive bucket fill: compositing the fill-reference layers, driving the GPU
// `MetalFillSession` on its own queue, the live gesture's renders (`fillRenders`), and committing or
// cancelling the result. Extracted from CanvasManager.swift as an extension — all state still lives
// on the class itself (see that file's header), so the gesture's stored properties and the
// `@Published` fill parameters the sliders bind to stay declared over there.
//
// This subsystem was the candidate for promotion to a real `InteractiveFillService` owned by
// CanvasManager, and it was measured for that rather than assumed. The machinery *is* private —
// nothing outside CanvasManager's own files names the fill lane, `fillLock`, `fillSession`, `FillKey`
// or any of the gesture fields. But the operations are not separable from the document: this file
// touches `layers` 29 times (10 of them writes into the `@Published` array, including the vector
// materialisation in `commitInteractiveFill`), plus `selection`, `currentFrame`,
// `currentLayerIndex`, `canvasSize` and `allowsPaintingOutsideSelection`, and it calls back into
// `beginCanvasEdit`, `recordUndo`, `registerUndoableCelChange`, `preparedRasterTexture`,
// `celContentChangedOutsideStroke`, `refreshUndoRedoState`, `scheduleThumbnailRegen`,
// `activeCelIndex`, `refreshDisplay` and `objectWillChange`.
//
// A service object would therefore hold a back-reference to CanvasManager and route all of that
// through it — mutating the `@Published` array from inside a child object, which is exactly the
// republishing failure mode sessions 47, 49 and 50 were spent fixing. The boundary is not clean, so
// it stays an extension.

extension CanvasManager {

    /// The quantized fill parameters, coalesced across a burst of touch-moves.
    ///
    /// Not `private`: `fillMintedKey` in CanvasManager.swift is typed with it, and Swift scopes
    /// `private` to the file rather than the type.
    ///
    /// `inset` is how far the artwork rect sits inside the canvas: `canvasPadding`, less the
    /// extension the artist asked the boundary to reach into it (`fillSettings.canvasEdgeExtension`) —
    /// carried here rather than read in `renderFill` because that runs on the fill lane and both are
    /// `@Published` main-thread state. The key is already the main-thread-captured carrier for
    /// everything the render used, so putting it here keeps that invariant. The padding cannot change
    /// mid-gesture (`setCanvasPadding` calls `commitAllInteractiveState` first); the extension can,
    /// from its slider, and that is a re-render of the live fill like any other setting.
    ///
    /// `mendReach` is `fillSettings.mendReach` while `mendsGaps` is on and 0 while it is off — one
    /// field for both, so a slider moved with the option off changes nothing the render reads and
    /// schedules no work.
    struct FillKey: Equatable {
        var gap: Int; var threshold: Int; var edge: Int; var edgeIsWall: Bool; var inset: Int
        var mendReach: Int
    }

    /// Everything a fill-lane render needs from the gesture that asked for it, snapshotted on the
    /// main thread and handed to the worker as a value.
    ///
    /// **This exists because "set before any fill-lane work runs, then only read after" was not
    /// true of a second gesture**, which is the whole of the owner's *"using the fill tool more than
    /// once breaks it sometimes"*. The render used to read `fillGestureSeed`,
    /// `fillGestureColor`, `fillGestureLayerID` and `fillGestureCelID` — all main-thread state —
    /// off the fill queue, so a tap that landed while the previous tap's flood was still on the GPU
    /// paired the *new* seed with the *old* session, the old reference composite and the old sampled
    /// colour. Passing a snapshot instead makes that combination unrepresentable rather than merely
    /// warned against.
    ///
    /// `generation` is the gesture's identity: see `CanvasManager.fillGeneration`.
    struct FillGestureContext {
        var generation: UInt64
        var documentFrame: Int
        var seedX: Int, seedY: Int
        var color: SIMD4<Float>       // premultiplied
        var layerID: UUID, celID: UUID
    }

    /// A finished render, as the fill lane produced it — stored under `fillLock` the instant it exists,
    /// *before* the landing on the main thread that installs it as the preview.
    ///
    /// **The commit path reads this, and that is the point.** `liveFill`'s render is written by that
    /// landing, and `beginCanvasEdit` calls `commitInteractiveFill` from inside `beginInteractiveFill`
    /// — so "the artist tapped twice quickly" arrives at the commit with the first fill *rendered and
    /// about to be shown* but not yet on the main thread. Against the shown preview alone that fill
    /// was silently dropped: no pixels, no undo entry, no message.
    ///
    /// Not `private`, for `FillKey`'s reason: `fillRenderedRegion` in CanvasManager.swift is typed
    /// with it. **A class, and immutable**, so the landing, the commit path and the layer's host share
    /// one copy of the bytes, and the host can ask whether the render it is showing is the live one by
    /// identity (`LayerHostView.showFill`) rather than by comparing a window of pixels.
    ///
    /// `bytes` is `window.workingWidth × window.workingHeight` premultiplied RGBA, covering
    /// `window.rect` of the canvas — TODO (86): a fill's pixels are the window's, never the canvas's.
    nonisolated final class FillRenderResult {
        let generation: UInt64
        /// The request's document time, including any parent above Repeat. A timeline scrub settles
        /// this result after currentFrame has changed, so the cel id cannot recover this context.
        let documentFrame: Int
        let bytes: [UInt8]
        let window: FillWindow

        init(generation: UInt64, documentFrame: Int, bytes: [UInt8], window: FillWindow) {
            self.generation = generation
            self.documentFrame = documentFrame
            self.bytes = bytes
            self.window = window
        }

        /// **The bytes as the preview tier**: the window's picture over the window's rect, clipped to
        /// `clip` (layer coordinates) when there is one — `fillSelectionClip`. What the layer's host
        /// draws and what the commit flattens, built by this one function so the picture cannot change
        /// when the pencil lifts. Any thread: it reads only its own bytes.
        func preview(clippedTo clip: CGPath?) -> FillPreview? {
            guard let image = CanvasManager.imageFromRGBA(bytes, width: window.workingWidth,
                                                          height: window.workingHeight) else { return nil }
            // The clip is in the layer's coordinates and the picture's pixels are its window's.
            var toWindow = window.transform
            guard let clip else { return FillPreview(image: image, rect: window.rect) }
            guard let path = clip.copy(using: &toWindow) else { return nil }
            return FillPreview(image: PixelOps.maskedComposite(overlay: image, insidePath: path),
                               rect: window.rect)
        }
    }

    /// **The adjustable fill as the canvas shows it** — `HeldEdit.fill`, TODO (157): the layer and cel
    /// it will land on, and the latest render's picture, which nothing in the document holds. Held from
    /// the press until the fill commits or is cancelled.
    ///
    /// **Not in `layers`.** A preview in the cel makes every render a document write — a SwiftUI pass
    /// over the editor, a new bake key and a re-bake, a re-minted live pair, a thumbnail and a
    /// main-thread decode of the new bake — per slider tick, for a picture one host draws
    /// (PERFORMANCE.md §28). The fill's host draws it, the canvas keeps that host drawing while it is
    /// up (`heldHostLayerIndices`), and the commit writes the document once, as one undo step.
    ///
    /// **Bytes, not a picture.** The host draws them into a surface off the main thread
    /// (`LayerHostView.showFill`), so a render's landing builds no image and hands none to Core
    /// Animation; `preview` is the picture, built on demand by whoever needs one — the commit, once.
    struct LiveFill {
        let layerID: UUID
        let celID: UUID
        /// The latest render to land. Nil until the first does, and for a lasso that enclosed nothing.
        var render: FillRenderResult?
        /// The selection the fill is clipped to, in the layer's coordinates, when it is
        /// (`fillSelectionClip`) — resolved with each landing, on the main thread, where the selection is.
        var clip: CGPath?

        /// The picture the host shows: the render, clipped.
        var preview: FillPreview? { render?.preview(clippedTo: clip) }
    }

    /// The last render the main thread installed — its painted pixels and the window they cover — so a
    /// re-tap can be hit-tested against the pixels the current fill already covers
    /// (`isPointInPendingFill`) and the commit can bake them. Main thread only.
    var fillLastRender: FillRenderResult? { liveFill?.render }

    /// Starts showing a fill gesture over its cel. **The press publishes once**, so the canvas cuts its
    /// live picture around the fill's host (`heldHostLayerIndices`); the renders after it publish
    /// nothing (`showLiveFill`).
    private func beginLiveFill(layerID: UUID, celID: UUID) {
        beginLiveEdit(.fill(LiveFill(layerID: layerID, celID: celID)))
    }

    /// A render, shown by the fill's host and written nowhere — the whole of a slider tick's cost to
    /// the main thread (TODO (157), (179)).
    private func showLiveFill(_ render: FillRenderResult?, clip: CGPath?) {
        guard var fill = liveFill else { return }
        fill.render = render
        fill.clip = clip
        holdLiveEdit(.fill(fill))
    }

    /// Lets the gesture's picture go — its pixels are in the document by now, or were thrown away —
    /// and publishes once, so the canvas re-cuts without the fill's host.
    private func endLiveFill(landing: LivePictureLanding? = nil) {
        guard liveFill != nil else { return }
        endLiveEdit {
            if let landing { onLivePictureWillLand?(landing) }
        }
    }

    /// How far a fill's picture can depend on pixels beyond its window — `FillWindow.halo` at the
    /// top of both slider ranges, because a lasso's window is cut once per gesture and the sliders
    /// move after it is.
    static var fillWindowHalo: CGFloat {
        FillWindow.halo(gapWidth: fillGapRange.upperBound, edgeRadius: fillExpandRange.upperBound,
                        mendReach: fillMendReachRange.upperBound)
    }

    /// The live gesture's render inputs, as a render is minted (`mintFillRender`). Main thread only.
    private func fillGestureContext(generation: UInt64) -> FillGestureContext? {
        guard let layerID = fillGestureLayerID, let celID = fillGestureCelID else { return nil }
        return FillGestureContext(generation: generation, documentFrame: currentFrame,
                                  seedX: fillGestureSeed.x, seedY: fillGestureSeed.y,
                                  color: fillGestureColor, layerID: layerID, celID: celID)
    }

    /// Runs `body` on the fill lane — an R1 job of `fillGroup`, after every job already on it. Any
    /// thread. Each is its own job (never latest-wins: a session's setup, its teardown and a mend's
    /// work must all run, in order); the gesture's renders are `fillRenders`, which are.
    func fillWork(_ body: @escaping @Sendable () -> Void) {
        Scheduler.shared.submit(Job(key: JobKey("fill", UUID()), jobClass: .answer, name: "fill", group: fillGroup,
                                    work: { _ in body() }, land: { _ in }))
    }

    /// Claims the next gesture generation, and gives the gesture renders of its own (`fillRenders`).
    /// Main thread only; the write is under `fillLock` so the queue's reads pair with it.
    ///
    /// The caller enqueues the gesture's session on the fill lane and then asks for its first render
    /// (`requestFillRender`), in that order: the new `fillRenders` is idle, so the render is enqueued
    /// at once, behind the session it reads.
    private func beginFillGeneration() -> UInt64 {
        fillLock.lock()
        fillGeneration &+= 1
        let generation = fillGeneration
        fillRenderedRegion = nil
        fillLock.unlock()
        fillMintedKey = nil
        MainActor.assumeIsolated {
            fillRenders?.cancel()
            fillRenders = LatestWins(scheduler: .shared, key: JobKey("fill.render", generation), name: "fill render",
                                     group: fillGroup)
        }
        return generation
    }

    /// **Whether the live gesture's first render has come back** — its picture landed, or the fill lane
    /// finished it and the landing has not run yet (`fillRenderedRegion`, published before the landing
    /// so a second tap inside that window still finds it). An empty answer counts: a loop that enclosed
    /// nothing has rendered, and has nothing to bake.
    private var fillHasProduced: Bool {
        guard fillLastRender == nil else { return true }
        fillLock.lock()
        defer { fillLock.unlock() }
        return fillAnsweredGeneration == fillGeneration
    }

    /// A tap the fill tool could not begin yet — see `queuedFills`.
    struct QueuedFill {
        enum Gesture {
            case bucket(at: CGPoint)
            case lasso(path: CGPath)
        }
        let gesture: Gesture
        /// The fill tool's colour when the tap was made.
        let color: UIColor
        /// The document it was made in: a tap never lands in another one.
        let project: UUID
    }

    /// **Queues a fill tap behind the live fill when that fill has nothing to bake yet** — the owner's
    /// ruling (Nov 26): *a second Fill tap while the first fill is still drawing is queued, lands right
    /// after the first, never dropped.* True when it was queued. A tap behind queued taps queues too,
    /// so they begin in the order they were made.
    ///
    /// This is what removed the last wait on the main thread (SCHEDULER.md rule 1): the tap used to
    /// park main until the first fill's render existed, because `beginCanvasEdit` bakes the live fill
    /// before the next edit reads the canvas, and there was nothing to bake. Now the tap waits instead
    /// of the thread — the first fill is baked as its picture lands (`landQueuedFills`) and the queued
    /// tap begins against a canvas the first fill is part of, exactly as it would have.
    private func queueFillIfTheLiveOneIsDrawing(_ gesture: QueuedFill.Gesture, color: UIColor) -> Bool {
        guard !queuedFills.isEmpty || (fillGestureActive && !fillHasProduced) else { return false }
        queuedFills.append(QueuedFill(gesture: gesture, color: color, project: projectID))
        fillCommitsOnLanding = true
        return true
    }

    /// **The live fill's render has come back: bake it if that was asked for, then begin the next
    /// queued tap** — in the main-thread turn after the landing, so the bake does not run inside the
    /// render lane's own callback. A render that came back with nothing (it failed) leaves nothing to
    /// bake, and its gesture is let go rather than holding the queue. A queued tap that cannot begin (its
    /// layer is gone, the edit was refused) is passed over for the next; one that begins waits for its
    /// own first picture.
    func landQueuedFills() {
        guard fillCommitsOnLanding else { return }
        fillCommitsOnLanding = false
        if fillGestureActive {
            if fillHasProduced { commitInteractiveFill() } else { cancelInteractiveFill() }
        }
        while !queuedFills.isEmpty {
            let next = queuedFills.removeFirst()
            guard next.project == projectID else { continue }
            switch next.gesture {
            case .bucket(let point): startBucketFill(at: point, color: next.color)
            case .lasso(let path): startLassoFill(path: path, color: next.color)
            }
            endInteractiveFill()
            // Begun: the rest wait for its first picture.
            if fillGestureActive {
                fillCommitsOnLanding = !queuedFills.isEmpty
                return
            }
        }
    }

    /// `landQueuedFills` in the next main-thread turn — out of the landing or the edit that asked.
    private func scheduleQueuedFills() {
        DispatchQueue.main.async { [weak self] in self?.landQueuedFills() }
    }

    /// The fill tool's colour, as a fill made now lands in.
    private var fillColorNow: UIColor { brushColor.resolvedUIColor(opacity: toolProfiles.brush.opacity) }

    /// Ends the live gesture's claim on the fill lane: nothing in flight may publish onto the document
    /// after this — the render running finds itself retired on the queue, and its landing is dropped
    /// with the gesture's `fillRenders`. Called by both `commitInteractiveFill` and
    /// `cancelInteractiveFill`, and it returns the render the queue had already produced for the
    /// gesture being retired — the bytes the commit bakes when the landing has not run yet.
    private func endFillGeneration() -> FillRenderResult? {
        let live = fillGeneration
        fillLock.lock()
        let queued = fillRenderedRegion
        fillGeneration &+= 1
        fillRenderedRegion = nil
        fillLock.unlock()
        MainActor.assumeIsolated { fillRenders?.cancel() }
        fillRenders = nil
        fillMintedKey = nil
        return queued?.generation == live ? queued : nil
    }

    /// Lets go of everything the retired gesture held on the fill lane: the GPU session, its window, and
    /// the layers it read. Queued behind any render still running for the gesture.
    private func endFillSession() {
        fillSession = nil
        fillWindow = nil
        fillGestureReferences = []
        fillGestureNeighbours = []
    }

    /// Begins an interactive fill at `point` (canvas-pixel coords, top-left origin): composites every
    /// fill-reference layer into a reference image once, uploads it to a GPU `MetalFillSession`, samples
    /// the tapped colour, and paints an initial fill. A plain tap is just this immediately followed by
    /// `endInteractiveFill`; a press-and-drag streams `updateInteractiveFill` calls in between. The fill
    /// preview lives in `liveFill`, off the document, until `commitInteractiveFill` bakes it into the
    /// layer proper.
    ///
    /// **Every buffer of the gesture is the size of a window of the canvas, not the canvas** — TODO
    /// (86), `FillWindow`. A tap starts in a small window about the seed and `renderFill` grows
    /// it while the paint reaches its rim, so the gesture's memory follows the region being filled
    /// and the canvas extent is not in it.
    func beginInteractiveFill(at point: CGPoint) {
        guard !fillFingerDown else { return }
        let color = fillColorNow
        guard !queueFillIfTheLiveOneIsDrawing(.bucket(at: point), color: color) else { return }
        startBucketFill(at: point, color: color)
    }

    /// `beginInteractiveFill`, once nothing is in front of it, in `color`.
    private func startBucketFill(at point: CGPoint, color: UIColor) {
        // A fill is a canvas edit like any other: an earlier adjustable fill (or a pending shape)
        // bakes first, so this fill reads it as a real boundary/recolour target instead of flooding
        // against content that is about to change.
        guard beginCanvasEdit() else { return }
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        // Filling a frame with no block spawns one, exactly as a brush stroke there does — the two
        // are the same instruction ("put content on this frame") and it would be arbitrary for one
        // to work and the other to sit inert. See `ensureCelAtCurrentFrame`.
        guard let celIndex = ensureCelAtCurrentFrame(layerIndex: layerIndex) else { return }

        let references = fillReferenceSources()
        let neighbours = [(layer: layers[layerIndex], cel: layers[layerIndex].cels[celIndex])]
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        // The tap is in canvas points and the flood runs in the layer's own space, where its
        // references are drawn and where the fill lands — TODO (124).
        let seed = layerSpacePoint(point, forLayerID: layers[layerIndex].id)
        let seedX = min(max(Int(seed.x.rounded(.down)), 0), width - 1)
        let seedY = min(max(Int(seed.y.rounded(.down)), 0), height - 1)
        let window = FillWindow.bucket(around: CGPoint(x: seedX, y: seedY), in: canvasSize,
                                       pixelBudget: MetalFillEngine.workingPixelBudget(isLasso: false))

        fillGestureActive = true
        fillFingerDown = true
        fillGestureIsLasso = false
        fillGestureSeed = (seedX, seedY)
        fillGestureColor = Self.premultipliedComponents(color)
        fillGestureFillColor = CodableColor(color)
        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        fillGestureLayerID = layerID
        fillGestureCelID = celID
        beginLiveFill(layerID: layerID, celID: celID)
        refreshUndoRedoState() // the fill is undoable from the moment it starts, even on a blank canvas

        let context = FillGestureContext(generation: beginFillGeneration(), documentFrame: currentFrame,
                                         seedX: seedX, seedY: seedY,
                                         color: fillGestureColor, layerID: layerID, celID: celID)

        fillWork { [weak self] in
            guard let self, self.isCurrentFillGeneration(context.generation) else { return }
            self.fillGestureReferences = references
            self.fillGestureNeighbours = neighbours
            // A tap has no fence to redraw. Cleared beside the session it belongs to, so the two can
            // never describe different gestures — see `fillGestureLoopPath`.
            self.fillGestureLoopPath = nil
            self.installFillSession(for: window, context: context, lassoMask: nil)
        }
        requestFillRender()
    }

    /// Builds the live gesture's session for `window` and installs it beside the window, on
    /// the fill lane — the one place a session is made, for the first window of a gesture and for
    /// every window `renderFill` grows it to.
    ///
    /// The reference pixels, path walls and canonical certificate share one frozen selected list.
    /// Every image stage and the own-fill exclusion belong to that same snapshot/window.
    ///
    /// **A refused session is announced now.** It used to be a bare nil that reached the render,
    /// which produced no preview and no message, so the artist tapped the bucket
    /// and nothing at all happened — see `CanvasNotice.Kind.fillNeedsMoreMemory`.
    /// `MetalFillEngine.shared` being nil takes the same notice: no Metal device is no fill either.
    ///
    /// - Returns: whether a session is installed.
    @discardableResult
    private func installFillSession(for window: FillWindow, context: FillGestureContext,
                                    lassoMask: [UInt8]?) -> Bool {
        guard isCurrentFillGeneration(context.generation) else { return false }
        // Replacements enter with no caller-local core alias. Retire the field and stale
        // worker readback before preparing another picture/core beside the same gesture.
        fillSession = nil
        fillWindow = nil
        fillLock.lock(); fillRenderedRegion = nil; fillLock.unlock()
        let references = fillGestureReferences
        var admittedWindow = window
        var outcome: MetalFillEngine.SessionOutcome?
        let maskBytes = lassoMask.map { UndoBudget.addingCost(32, $0.capacity) } ?? 0
        if let prepared = Self.prepareFillReference(references: references, window: window,
            isLasso: lassoMask != nil, reserving: maskBytes, certifiesMend: lassoMask != nil,
            isCurrent: { self.isCurrentFillGeneration(context.generation) }) {
            admittedWindow = prepared.window
            var admittedMask = lassoMask
            if lassoMask != nil && admittedWindow != window {
                guard let path = fillGestureLoopPath,
                      let resized = LassoFillMask.rasterize(path: path, width: admittedWindow.workingWidth,
                        height: admittedWindow.workingHeight, transform: admittedWindow.transform) else {
                    reportFillRefusal(context); fillSession = nil; fillWindow = nil; return false
                }
                admittedMask = resized
            }
            guard isCurrentFillGeneration(context.generation) else { return false }
            let neighbours: [UInt8]?
            if admittedWindow.scale < 1 {
                let held = [UndoBudget.addingCost(32, prepared.rgba.capacity), prepared.support.retainedBytes,
                            maskBytes, admittedWindow != window
                                ? (admittedMask.map { UndoBudget.addingCost(32, $0.capacity) } ?? 0) : 0]
                    .reduce(0, UndoBudget.addingCost)
                guard let mask = Self.neighbourMask(of: fillGestureNeighbours, in: admittedWindow,
                                                    reserving: held) else {
                    reportFillRefusal(context); fillSession = nil; fillWindow = nil; return false
                }
                neighbours = mask
            } else { neighbours = nil }
            guard isCurrentFillGeneration(context.generation) else { return false }
            outcome = MetalFillEngine.shared?.makeSession(referenceRGBA: prepared.rgba,
                width: admittedWindow.workingWidth, height: admittedWindow.workingHeight, lassoMask: admittedMask,
                pathWall: prepared.pathWall(),
                gapWidthLimit: Float(Self.fillGapRange.upperBound * admittedWindow.scale))
            outcome?.session?.installVectorReference(prepared.support)
            if let neighbours { outcome?.session?.installNeighbours(neighbours) }
        }
        guard isCurrentFillGeneration(context.generation) else { return false }
        let session = outcome?.session
        if session == nil { reportFillRefusal(context) }
        fillSession = session
        fillWindow = session == nil ? nil : admittedWindow
        if let session {
            // A lasso session derives the collar's reference colours from the ring itself (§6 2a)
            // and ignores whatever is handed to `fill(seedColor:)`. Mirroring its answer here keeps
            // the two from reading differently to anyone debugging a gesture.
            let seed = admittedWindow.workingPixel(of: CGPoint(x: context.seedX, y: context.seedY))
            fillSeedColor = session.isLasso ? session.referenceColours.0
                : session.seedColor(atX: seed.x, y: seed.y)
        }
        return session != nil
    }

    /// Whether `generation` is still the gesture the fill lane is working for. Safe from either thread:
    /// only the main thread writes `fillGeneration`, and always under `fillLock`.
    ///
    /// The early-out it guards at the top of each `begin*Fill` worker is not only tidiness — a tap
    /// that has already been superseded would otherwise composite the whole canvas and upload a GPU
    /// session for a gesture nobody is waiting on, which is time the *live* tap is queued behind on a
    /// serial queue.
    func isCurrentFillGeneration(_ generation: UInt64) -> Bool {
        fillLock.lock()
        defer { fillLock.unlock() }
        return generation == fillGeneration
    }

    /// **Tells the artist the fill is not going to happen** — the one place the four ways
    /// `makeSession` can decline become a banner.
    ///
    /// Called from the fill lane, so it hops to main, and it checks the generation on arrival for the
    /// reason a render's landing is dropped with its gesture: a refusal belonging to a gesture the
    /// artist has already abandoned is not news.
    ///
    /// It also ends the gesture. A fill with no session can never produce a preview or a commit, so
    /// leaving `fillGestureActive` set would leave the sliders live over a fill that does not exist
    /// and the undo affordance armed for a step that will never be recorded.
    func reportFillRefusal(_ context: FillGestureContext) {
        DispatchQueue.main.async { [weak self] in
            guard let self, context.generation == self.fillGeneration, self.fillGestureActive else { return }
            self.raise(.fillNeedsMoreMemory)
            self.cancelInteractiveFill()
        }
    }

    /// The Edge Overlap value the slider shows and writes: the bucket's or the lasso's, whichever mode
    /// the artist has in front of them. Two stored settings, one control — see `FillSettings.lassoEdgeOverlap` for
    /// why they cannot share a number.
    ///
    /// Every UI path goes through here (`FillSettingsPanel` and `SideToolbar`, through
    /// `setFillEdgeOverlap` below), so "which mode owns this value" is decided in exactly one place.
    var fillEdgeOverlap: CGFloat {
        get { fillMode == .lasso ? fillSettings.lassoEdgeOverlap : fillSettings.bucketEdgeOverlap }
        set {
            let v = min(max(newValue, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
            if fillMode == .lasso {
                if fillSettings.lassoEdgeOverlap != v { fillSettings.lassoEdgeOverlap = v }
            } else {
                if fillSettings.bucketEdgeOverlap != v { fillSettings.bucketEdgeOverlap = v }
            }
        }
    }

    /// The disk radius the engine is handed, which is **not** the slider value for a lasso.
    ///
    /// *"I want it so on the high setting it is on the outer edge, and when you lower it, it shrinks
    /// inwards"* — the owner, 2026-08-21. The slider keeps its direction (up is more colour) and its
    /// whole range slides down by its own width: the lasso passes `upperBound - v`, so the top of the
    /// slider is radius 0 — flush with the artwork's outer silhouette, byte-identical to the old
    /// zero — and nothing below it can paint outside that silhouette. The bucket is untouched and
    /// still dilates by `v`.
    ///
    /// **The two modes run the same operation on opposite sides of the lasso's invert**, which is the
    /// owner's own observation that it *"shouldn't be all that different codewise to the normal
    /// one"*: dilating a set and eroding its complement are one operator. The lasso's runs on the
    /// painted **coverage** rather than on the collar because the fill's soft edge is 8 bits of alpha
    /// that only exists after the invert — see `lassoEdgeErode` in Fill.metal, and LASSO_FILL.md §6
    /// step 7 for the measurement that settled it.
    ///
    /// The mapping lives here rather than in `MetalFillSession` on purpose: *where the top of a slider
    /// sits* is a fact about `fillExpandRange`, which is a UI range, and the engine should not have to
    /// know it to run a morphological operator. `lassoEdgeErode` in Fill.metal is the operator.
    func fillEdgeRadius(lasso: Bool) -> CGFloat {
        lasso ? Self.fillExpandRange.upperBound - fillSettings.lassoEdgeOverlap : fillSettings.bucketEdgeOverlap
    }

    /// **Edge Overlap used to be forced to 0 for a lasso gesture, then briefly grew the fill outward,
    /// and is now anchored at the ink's outer edge** — see `fillEdgeRadius(lasso:)` for the owner's
    /// two rulings of 2026-08-21 and LASSO_FILL.md §6 step 7 for the specification.
    ///
    /// `fillGestureIsLasso` rather than `fillMode` decides which mapping the key gets, and the
    /// difference is not academic: the key describes the *session* the worker will re-run, and a
    /// session's algorithm is fixed at `makeSession` by whether it was handed a lasso mask. Switching
    /// the mode picker while a fill is still adjustable would otherwise send the bucket's radius to a
    /// lasso session, which reads it as an erosion. Both flags are main-thread state and both are set
    /// before the `begin*Fill` that reaches here.
    ///
    /// Internal rather than `private` so `FillBoundaryLogicTests` can assert the wiring: every other
    /// fill test builds a raw buffer and drives `MetalFillSession` directly, which would let a
    /// correct shader ship behind a `canvasPadding` that never reaches it.
    func currentFillKey() -> FillKey {
        FillKey(gap: Int(fillSettings.gapClosing.rounded()),
                threshold: Int((fillSettings.threshold * 1000).rounded()),
                edge: Int(fillEdgeRadius(lasso: fillGestureIsLasso).rounded()),
                edgeIsWall: fillSettings.canvasEdgeIsBoundary,
                inset: Int(max(0, canvasPadding - fillSettings.canvasEdgeExtension).rounded()),
                mendReach: fillSettings.mendsGaps ? Int(fillSettings.mendReach.rounded()) : 0)
    }

    /// Toggles "the canvas edge bounds the fill" and, if a fill is currently adjustable, re-runs it so
    /// the artist sees the difference without re-tapping — the same live-update contract the sliders'
    /// setters give.
    func setFillCanvasEdgeIsBoundary(_ enabled: Bool) {
        guard fillSettings.canvasEdgeIsBoundary != enabled else { return }
        fillSettings.canvasEdgeIsBoundary = enabled
        if fillGestureActive { requestFillRender() }
    }

    /// Sets how far into the padding the canvas edge's boundary reaches, and re-runs an adjustable
    /// fill so the artist sees the boundary move. Whole pixels, never negative — the boundary does
    /// not come in from the paper's edge, which is the option's own meaning.
    func setFillCanvasEdgeExtension(_ pixels: CGFloat) {
        let v = max(0, pixels.rounded())
        guard fillSettings.canvasEdgeExtension != v else { return }
        fillSettings.canvasEdgeExtension = v
        if fillGestureActive { requestFillRender() }
    }

    /// Turns the mend on or off and, like the other two switches, re-runs an adjustable fill — the
    /// natural order is to fill, see the seam, and flip this, and the seam should close under the
    /// artist's finger.
    func setFillMendsGaps(_ enabled: Bool) {
        guard fillSettings.mendsGaps != enabled else { return }
        fillSettings.mendsGaps = enabled
        if fillGestureActive { requestFillRender() }
    }

    /// Sets how far the mend reaches and re-runs an adjustable fill so internal gaps and seams close
    /// as the slider moves. Whole pixels, within `fillMendReachRange`; set from the fill dropdown alone.
    func setFillMendReach(_ pixels: CGFloat) {
        let v = min(max(pixels.rounded(), Self.fillMendReachRange.lowerBound), Self.fillMendReachRange.upperBound)
        guard fillSettings.mendReach != v else { return }
        fillSettings.mendReach = v
        if fillGestureActive { requestFillRender() }
    }

    /// The layers whose content bounds the fill, bottom-to-top: every layer marked `isFillReference`, at
    /// its displayed cel for the current frame. Empty when nothing is a reference (the fill then floods the
    /// whole canvas).
    func fillReferenceSources() -> [(layer: Layer, cel: Cel)] {
        fillReferenceSources(atFrame: currentFrame)
    }

    func fillReferenceSources(atFrame frame: Int) -> [(layer: Layer, cel: Cel)] {
        let shown = displayedFrames(atFrame: frame)
        return layers.indices.compactMap { i in
            let layer = layers[i]
            guard layer.isFillReference,
                  let celIdx = activeCelIndex(inLayer: i, atFrame: shown[i] ?? frame) else { return nil }
            return (layer, layer.cels[celIdx])
        }
    }

    /// **The fill tool's sideways drag adjusts Gap Closing and nothing else, and rightward lowers it** —
    /// TODO (186), the owner: *"just fix it to gap closing (no other sliders). Also invert the direction,
    /// so that drag right decreases gap fill."* Finger travel that sweeps the whole range: generous, so
    /// fine adjustments are easy.
    static let fillDragSweepPoints: CGFloat = 320

    /// Gap Closing for a sideways fill drag `travelled` host points to the right of where it started at
    /// `start` — negative is leftward — clamped to the slider's range.
    static func fillDragGapClosing(from start: CGFloat, travelled: CGFloat) -> CGFloat {
        let perPoint = (fillGapRange.upperBound - fillGapRange.lowerBound) / fillDragSweepPoints
        return min(max(start - travelled * perPoint, fillGapRange.lowerBound), fillGapRange.upperBound)
    }

    /// Sets the in-progress fill's Gap Closing — the sideways drag's one setting — and re-fills from the
    /// cached GPU session; the Gap Closing sliders mirror the drag live. Cheap to call on every
    /// touch-move: identical quantized values mint no render, and a burst is one render of the newest.
    func updateInteractiveFill(gapClosing: CGFloat) {
        guard fillGestureActive else { return }
        let clamped = min(max(gapClosing, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
        if fillSettings.gapClosing != clamped { fillSettings.gapClosing = clamped }
        requestFillRender()
    }

    // The Fill panel's and the left rail's sliders: each sets its value and — if a fill is still
    // adjustable — re-runs it live, so the artist sees the change without re-tapping.

    func setFillGapClosing(_ value: CGFloat) {
        let v = min(max(value, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
        if fillSettings.gapClosing != v { fillSettings.gapClosing = v }
        if fillGestureActive { requestFillRender() }
    }

    func setFillThreshold(_ value: CGFloat) {
        let v = min(max(value, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
        if fillSettings.threshold != v { fillSettings.threshold = v }
        if fillGestureActive { requestFillRender() }
    }

    /// Clamped by `fillEdgeOverlap`'s setter, and written to whichever fill type's value the slider
    /// is showing.
    func setFillEdgeOverlap(_ value: CGFloat) {
        fillEdgeOverlap = value
        if fillGestureActive { requestFillRender() }
    }

    /// Asks for a render of the live gesture at the fill settings as they stand when the fill lane comes
    /// free (`fillRenders`). O(1); a request made while a render is in flight replaces any still
    /// waiting, so a burst of slider ticks is one render of the newest. Main thread only.
    private func requestFillRender() {
        MainActor.assumeIsolated {
            fillRenders?.request { [weak self] in self?.mintFillRender() }
        }
    }

    /// **One render, minted on the main thread as the queue comes free**: the settings and the gesture
    /// as they are now, or nothing when the last render was already of these settings. The render runs
    /// on the fill lane (`renderFill`) and its result lands back here (`landFillRender`).
    private func mintFillRender() -> LatestWins.Work? {
        let key = currentFillKey()
        guard fillGestureActive, key != fillMintedKey,
              let context = fillGestureContext(generation: fillGeneration) else { return nil }
        fillMintedKey = key
        return { [weak self] in
            let outcome = self?.renderFill(key, for: context)
            return { [weak self] in
                guard let self else { return }
                guard let outcome else {
                    // Nothing came back: a tap queued behind this fill must not wait on it for ever.
                    if self.fillCommitsOnLanding { self.scheduleQueuedFills() }
                    return
                }
                self.landFillRender(outcome, for: context)
            }
        }
    }

    /// Whether `point` (canvas-pixel coords, top-left origin) lands on a pixel the current adjustable fill
    /// already covers. Used so a re-tap inside the just-filled region resumes drag-adjusting it, rather
    /// than starting a new fill.
    ///
    /// **Half the gesture's own opacity, not "any alpha at all", and the lasso is why.** Its output
    /// carries a coverage ramp along the artwork's antialiased fringe (LASSO_FILL.md §6 step 6), so a
    /// pixel can be 1/255 opaque and still be *outside* the shape the artist sees. Against a bare
    /// `> 0` test the whole soft edge of the drawing would count as "inside the fill", and a tap
    /// there would resume adjusting instead of starting a new one.
    func isPointInPendingFill(at canvasPoint: CGPoint) -> Bool {
        // The fill lives in its layer's own space — `beginInteractiveFill`'s pull-back.
        let point = fillGestureLayerID.map { layerSpacePoint(canvasPoint, forLayerID: $0) } ?? canvasPoint
        guard fillGestureActive, let render = fillLastRender, render.window.rect.contains(point) else { return false }
        let pixel = render.window.workingPixel(of: point)
        return render.bytes[(pixel.y * render.window.workingWidth + pixel.x) * 4 + 3] >= fillHalfCoverageAlpha
    }

    /// Half the alpha a fully-covered pixel of the current gesture carries — the cut between "in the
    /// fill" and "in its antialiased fringe".
    ///
    /// Relative to the gesture rather than a constant 128 because `fillGestureColor` is premultiplied
    /// by the brush opacity: a fill at 30% opacity paints its *solid* interior at alpha 77, so a fixed
    /// 128 would call the entire fill empty. At least 1, so a fully transparent brush still hit-tests
    /// against the pixels it nominally covers rather than against none of them.
    var fillHalfCoverageAlpha: UInt8 {
        UInt8(max(1, min(255, Int((fillGestureColor.w * 255).rounded()) / 2)))
    }

    /// Re-arms drag-adjusting of the existing adjustable fill (same session/seed) when a finger presses
    /// back down inside it. No new session or reference composite — it just keeps adjusting what's there.
    func resumeInteractiveFillDrag() {
        guard fillGestureActive else { return }
        fillFingerDown = true
    }

    /// Ends the finger press but leaves the fill *adjustable*: the preview stays visible with its GPU
    /// session alive, so panel sliders re-run it live and a re-tap inside it resumes dragging — and the
    /// drag's last request still lands, because `fillRenders` mints it when the render before it does.
    /// It's baked (committed) only later, by `commitInteractiveFill`.
    func endInteractiveFill() {
        guard fillGestureActive, fillFingerDown else { return }
        fillFingerDown = false
    }

    /// Bakes the current adjustable fill into the layer as a single "Fill" undo step and tears the
    /// session down. The layer's kind decides the destination outright, with no fallback between
    /// them — each tier is invisible to the other's renderer:
    ///
    /// - **vector layer** → a `VectorFillElement` (a closed path) on the `VectorCanvas`, which is
    ///   the only thing such a layer draws.
    /// - **raster layer** → flattened straight into `Cel.raster`, the tier the eraser stamps, so the
    ///   fill can be erased afterwards (see `registerUndoableCelChange`'s doc comment).
    @discardableResult
    func commitInteractiveFill() -> Bool {
        var staged: [UUID: Cel] = [:]
        guard let commit = prepareInteractiveFill(staging: &staged) else { return false }
        commit()
        return true
    }

    /// Capture the latest produced render without retiring its generation. A failed admission
    /// keeps that render, the adjustable draft and its live picture available for another attempt.
    func prepareInteractiveFill(staging: inout [UUID: Cel]) -> (() -> Void)? {
        guard fillGestureActive else { return {} }
        // **Nothing to bake yet, and main never waits for it** (rule 1): the fill is baked the moment
        // its first picture lands (`landQueuedFills`). The edit after it goes ahead now.
        guard fillHasProduced else {
            return { [weak self] in
                self?.fillCommitsOnLanding = true
                self?.fillFingerDown = false
            }
        }
        fillLock.lock()
        let queued = fillRenderedRegion?.generation == fillGeneration ? fillRenderedRegion : nil
        fillLock.unlock()
        let render = fillLastRender ?? queued
        guard let layerID = fillGestureLayerID, let celID = fillGestureCelID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else {
            raise(.drawingSourceUnavailable); return nil
        }
        guard let render, !render.bytes.isEmpty else {
            return { [weak self] in self?.finishInteractiveFill() }
        }
        guard case .resolved(let clip) = fillSelectionClip(layerIndex: layerIndex, celIndex: celIndex,
                                                          atFrame: render.documentFrame),
              let preview = render.preview(clippedTo: clip) else {
            raise(.drawingSourceUnavailable); return nil
        }
        let landing = LivePictureLanding.fill(layerID: layerID, celID: celID, preview: preview,
                                              render: render, clip: clip)
        let label: HistoryActionLabel = fillGestureIsLasso ? .lassoFill : .fill
        var cel = staging[celID] ?? layers[layerIndex].cels[celIndex]
        if layers[layerIndex].kind == .vector {
            guard let traced = PixelOps.pathFromAlphaMask(bytes: render.bytes,
                width: render.window.workingWidth, height: render.window.workingHeight,
                minimumAlpha: fillHalfCoverageAlpha) else {
                return { [weak self] in self?.finishInteractiveFill() }
            }
            var toCanvas = render.window.transform.inverted()
            guard let tracedPath = traced.copy(using: &toCanvas) else { raise(.drawingSourceUnavailable); return nil }
            let path: CGPath
            if let clip {
                // A first lasso may still cross itself. Boolean operands must be normalized;
                // winding is also the live preview's clip rule, including composed holes.
                let rule = VectorCanvas.lassoFillRule
                path = tracedPath.normalized(using: rule).intersection(clip.normalized(using: rule), using: rule)
            } else { path = tracedPath }
            guard !path.isEmpty else { return { [weak self] in self?.finishInteractiveFill() } }
            let before = cel.vector?.elements ?? []
            let prepared = cel.vector?.makeCopy() ?? .empty(size: cel.raster.size)
            let added = prepared.addFill(path: path, paint: .solid(fillGestureFillColor))
            cel.vector = prepared
            staging[celID] = cel
            let elements = prepared.elements
            let size = cel.raster.size
            return { [weak self] in
                guard let self,
                      let layer = self.layers.firstIndex(where: { $0.id == layerID }),
                      let at = self.layers[layer].cels.firstIndex(where: { $0.id == celID }) else { return }
                if self.layers[layer].cels[at].vector == nil { self.layers[layer].cels[at].vector = .empty(size: size) }
                guard let vector = self.layers[layer].cels[at].vector else { return }
                vector.restoreElements(elements, changedInk: nil, rewriting: [])
                self.registerVectorElementsUndo(vectorCanvas: vector, oldElements: before,
                    newElements: elements, layerID: layerID, celID: celID, label: label,
                    swap: .addsAndRemoves(ink: added.ink))
                self.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                self.finishInteractiveFill(landing: landing)
            }
        }
        let before = cel
        let final: RasterSource
        do {
            let baked = try cel.bakedImage?.resolveImage().get()
            let strokes = try cel.raster.renderIfNonEmpty().get()
            let canvas = CGRect(origin: .zero, size: cel.raster.size)
            final = try RasterSource.render(size: cel.raster.size, using: cel.raster.residency) { _ in
                baked?.draw(in: canvas)
                strokes?.draw(in: canvas)
                preview.draw()
                return true
            }.get()
        } catch { raise(.drawingSourceUnavailable); return nil }
        let raster = preparedRasterTexture(source: final, likeExisting: cel.raster)
        cel.raster = raster
        cel.bakedImage = nil
        staging[celID] = cel
        return { [weak self] in
            guard let self else { return }
            self.registerUndoableCelChange(layerID: layerID, celID: celID,
                oldRaster: before.raster, oldBaked: before.bakedImage,
                newRaster: raster, newBaked: nil, label: label)
            self.finishInteractiveFill(landing: landing)
        }
    }

    private func finishInteractiveFill(landing: LivePictureLanding? = nil) {
        fillGestureActive = false
        fillFingerDown = false
        fillGestureIsLasso = false
        _ = endFillGeneration()
        fillWork { [weak self] in self?.endFillSession() }
        endLiveFill(landing: landing)
        fillGestureLayerID = nil
        fillGestureCelID = nil
        refreshUndoRedoState()
    }

    // MARK: - A path that is already known

    /// Where a solid path came to rest.
    enum SolidFillLanding: Equatable {
        /// A `VectorFillElement` on a vector layer, which can be selected, moved and edited.
        case element(UUID)
        /// Pixels in a raster layer's cel — there is no object to name.
        case pixels
    }

    /// **The fill tool's add path for geometry nobody has to flood-fill** — a lasso selection filled
    /// from the Select panel, a rectangle or an ellipse from the Add menu. `commitInteractiveFill` is
    /// the same destination reached by tracing a mask; everything after the path is known is shared.
    ///
    /// **The layer's kind decides the destination outright, with no fallback between the two** — each
    /// tier is invisible to the other's renderer, which is `commitInteractiveFill`'s own rule. A
    /// vector layer gets a `VectorFillElement`; a raster layer is flattened with the shape painted on
    /// top, into `Cel.raster`, the tier the eraser stamps. One undo step either way.
    ///
    /// - Parameters:
    ///   - path: **in the layer's own space** — where a raster cel's pixels and a vector cel's stored
    ///     geometry are — so a loop is pulled back through `layerSpacePath` and an added object's
    ///     geometry through `layerSpaceFill` before it arrives, and what lands is shown where it was
    ///     made under whatever poses the layer (TODO (124)).
    ///   - color: already resolved against the brush opacity, as the fill tool resolves its own.
    /// - Returns: nil when the cel is gone.
    @discardableResult
    func layDownSolidFill(_ path: CGPath, color: UIColor, layerIndex: Int, celIndex: Int,
                          label: HistoryActionLabel) -> SolidFillLanding? {
        guard let canvasSize, layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return nil }
        if layers[layerIndex].kind == .vector {
            return placeVectorFill(path, paint: .solid(CodableColor(color)), layerIndex: layerIndex,
                                   celIndex: celIndex, label: label).map(SolidFillLanding.element)
        }
        let cel = layers[layerIndex].cels[celIndex]
        guard let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize) else { return nil }
        guard case .success(let source) = PixelOps.fill(base: base, path: path, color: color,
            using: cel.raster.residency) else { raise(.drawingSourceUnavailable); return nil }
        registerUndoableCelChange(layerID: layers[layerIndex].id, celID: cel.id,
                                  oldRaster: cel.raster, oldBaked: cel.bakedImage,
                                  newRaster: preparedRasterTexture(source: source, likeExisting: cel.raster),
                                  newBaked: nil, label: label)
        return .pixels
    }

    /// The vector arm: one `VectorFillElement` appended to the cel's display list, and the step that
    /// takes it away.
    ///
    /// **The whole display list is what the step swaps, not `vectorCanvas.fills`.** `addFill` appends
    /// the new element on top of the strokes (LASSO_FILL.md §2a), so the list is no longer
    /// kind-sorted and a fills-bucket undo would have to invent a z-position for the fill it puts
    /// back — see `registerVectorElementsUndo`. One fill appended and nothing rewritten, and `addFill`
    /// says exactly where it went, so redoing this costs the fill's own rectangle rather than every
    /// dab on the cel. **The undo costs the same rectangle since TODO (41)**, and not because of this
    /// argument: a departing fill is bounded by `VectorCanvas.derivedFootprint(of:)`, which reads the
    /// very path that is about to leave the list. Passing the landing rectangle is still right — it
    /// is free, and it is the arriving half.
    ///
    /// A vector layer's cel with no canvas gets an empty one rather than the fill landing in a tier
    /// the layer never draws.
    ///
    /// - Parameter path: in the layer's own space — see `layDownSolidFill`.
    /// - Returns: the new element's id, or nil when the cel is gone.
    @discardableResult
    func placeVectorFill(_ path: CGPath, paint: FillPaint, layerIndex: Int, celIndex: Int,
                         label: HistoryActionLabel) -> UUID? {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex)
        else { return nil }
        if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
            layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
        }
        guard let vectorCanvas = layers[layerIndex].cels[celIndex].vector else { return nil }
        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        let elementsBefore = vectorCanvas.elements
        // The input pose has already been pulled back; insertion stores this canonical path.
        let added = vectorCanvas.addFill(path: path, paint: paint)
        registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                   newElements: vectorCanvas.elements,
                                   layerID: layerID, celID: celID, label: label,
                                   swap: .addsAndRemoves(ink: added.ink))
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        return added.id
    }

    // MARK: - Lasso fill

    /// Begins a lasso fill from the loop the artist just drew — the fill tool's `.lasso` type.
    ///
    /// **The rule, for an artist** (LASSO_FILL.md §3, and it has no branch in it): *the loop is a
    /// fence, and ink is a wall. Anything inside your fence that the fence can walk to — the paper
    /// around your drawing, and anywhere it can slip into through a gap — is left untouched.
    /// Everything else inside the fence is filled solid, lines and all. So the colour lands inside
    /// your shapes and nowhere else: not on the paper between the fence and the drawing, and never on
    /// the fence itself.*
    ///
    /// **It is not the bucket fill with a bigger seed**, which is what it used to be and is what the
    /// owner reported as a bug: *"when i circle something the entire canvas gets filled."* Seeding
    /// every open pixel inside the loop meant that circling a shape seeded the paper *around* it, and
    /// the flood ran from there over the whole page. The replacement is morphological hole filling
    /// marked from the loop — Krita ships it as *Enclose and Fill* — and it runs in five steps
    /// (LASSO_FILL.md §6 has the pixel-level statement):
    ///
    ///  1. Rasterise the closed loop, non-zero winding, clipped to the canvas → the stencil.
    ///  2. Take its one-pixel inner **ring**, and the colours that ring mostly sits on → the collar's
    ///     reference set (`LassoFillMask.ringMask` / `.referenceColours`).
    ///  3. Flood from the ring, through pixels close to a reference, **never leaving the stencil**.
    ///  4. Paint the stencil *minus* everything that flood reached (`lassoInvert`).
    ///  5. If that is empty, commit nothing and say so — see `renderFill` and §7.
    ///
    /// Step 4 is where each of the tool's promises comes from, and they are one line of code rather
    /// than three features: the fill cannot touch the loop because nothing outside the stencil is
    /// written; interior line art is painted over because the collar cannot walk through ink; and a
    /// face's eyes fill with the face because their interiors are walled off from the collar too.
    ///
    /// **What it will not do, on purpose.** A loop around blank paper, or one whose enclosure leaks
    /// through a gap wider than Gap Closing, fills *nothing* — the two are indistinguishable to the
    /// algorithm (§4 case 11), and falling back to painting the loop's own shape would dump a slab of
    /// colour over the artist's line art on the leak case. A shape that pokes out of the loop is not
    /// filled either (§4 case 12), because the loop passes through its interior and the collar seeds
    /// there. Both match Krita and Clip Studio Paint.
    ///
    /// Everything else — the reference composite, the wall threshold, gap closing, the canvas-edge
    /// boundary, the live re-run when a slider moves, the vector-versus-raster commit and the
    /// selection clip — is the machinery already there, which is why this stays a type option under
    /// the fill tool rather than a tool of its own. Edge Overlap is the exception: it is forced to 0
    /// (see `currentFillKey`).
    ///
    /// Left *adjustable* on purpose, exactly as a tap is: the caller follows with
    /// `endInteractiveFill()`, the preview stays live, and moving a slider re-runs this same loop.
    /// That matters most on the empty result, where nudging Threshold or Gap Closing can recover a
    /// near-miss without redrawing the loop.
    func beginInteractiveLassoFill(path drawnPath: CGPath) {
        guard !fillFingerDown else { return }
        let color = fillColorNow
        guard !queueFillIfTheLiveOneIsDrawing(.lasso(path: drawnPath), color: color) else { return }
        startLassoFill(path: drawnPath, color: color)
    }

    /// `beginInteractiveLassoFill`, once nothing is in front of it, in `color`.
    private func startLassoFill(path drawnPath: CGPath, color: UIColor) {
        guard beginCanvasEdit() else { return }
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        // The loop was drawn in canvas points and the fill is worked out in the layer's own space,
        // which is where its references are drawn and where it lands — TODO (124).
        let path = layerSpacePath(drawnPath, forLayerID: layers[layerIndex].id)

        // The loop plus its halo is the whole of what a lasso fill can touch (`FillWindow`), so the
        // stencil, the reference and the session are all cut to it.
        let window = FillWindow.lasso(around: path.boundingBoxOfPath, halo: Self.fillWindowHalo,
                                      in: canvasSize,
                                      pixelBudget: MetalFillEngine.workingPixelBudget(isLasso: true))
        guard let lassoMask = LassoFillMask.rasterize(path: path, width: window.workingWidth,
                                                      height: window.workingHeight,
                                                      transform: window.transform) else { return }
        // **A loop enclosing nothing is a cancelled gesture, not a failed fill** — LASSO_FILL.md §6
        // step 0 / §4 case 13: silent, no message, no undo entry, and no cel spawned by
        // `ensureCelAtCurrentFrame` below either, which is why this guard sits above it.
        //
        // Counted off the rasterisation that the fill will actually use, rather than off the path's
        // bounding box. The box test this replaced was an *or* of two extents, so a 100x1 px stylus
        // twitch — which encloses nothing at all — sailed through it, while this cannot: an area
        // measured on the winding-rule mask is the same number the algorithm goes on to work with.
        var enclosed = 0
        for byte in lassoMask where byte != 0 {
            enclosed += 1
            if enclosed >= Self.lassoFillMinimumArea { break }
        }
        guard enclosed >= Self.lassoFillMinimumArea else { return }

        guard let celIndex = ensureCelAtCurrentFrame(layerIndex: layerIndex) else { return }
        let references = fillReferenceSources()
        let neighbours = [(layer: layers[layerIndex], cel: layers[layerIndex].cels[celIndex])]

        fillGestureActive = true
        fillFingerDown = true
        fillGestureIsLasso = true
        fillGestureSeed = (0, 0)   // unused: a lasso session seeds from its mask
        fillGestureColor = Self.premultipliedComponents(color)
        fillGestureFillColor = CodableColor(color)
        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        fillGestureLayerID = layerID
        fillGestureCelID = celID
        beginLiveFill(layerID: layerID, celID: celID)
        refreshUndoRedoState()

        // A lasso session seeds from its mask, so the seed coordinate is unused — but the generation
        // is not, and this begin is exposed to a second gesture exactly as the bucket fill's is.
        let context = FillGestureContext(generation: beginFillGeneration(), documentFrame: currentFrame,
                                         seedX: 0, seedY: 0,
                                         color: fillGestureColor, layerID: layerID, celID: celID)
        // A new loop supersedes the last one's §7 picture, even mid-fade: whatever the artist is
        // about to be told is about *this* gesture. The presenter clears it on its own timer too;
        // this is the case that timer cannot cover, because it fires from a fill, not a clock.
        lassoFillDiagnostic = nil

        fillWork { [weak self] in
            guard let self, self.isCurrentFillGeneration(context.generation) else { return }
            self.lassoFillReportedEmpty = false
            self.fillGestureLoopPath = path
            self.fillGestureReferences = references
            self.fillGestureNeighbours = neighbours
            // The lasso's collar flood runs against the same wall set the bucket does, so it gets
            // (46) for free — a segmented enclosure lassoed no longer leaks its collar out through
            // the gaps between dabs.
            self.installFillSession(for: window, context: context, lassoMask: lassoMask)
        }
        requestFillRender()
    }

    /// The smallest area, in canvas pixels of the rasterised loop, a lasso must enclose before it
    /// counts as an edit — LASSO_FILL.md §4 case 13's "under 4 px²".
    static let lassoFillMinimumArea = 4

    /// Abandons the interactive fill without committing, discarding the preview. Used when an undo/redo
    /// tap takes over, or via `cancelInteractiveFillDrag` when a two-finger transform starts mid-drag.
    func cancelInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false
        fillFingerDown = false
        fillGestureIsLasso = false
        _ = endFillGeneration()   // retires it on the fill lane and drops its landing, so a restart can't inherit its work
        endLiveFill()
        fillGestureLayerID = nil
        fillGestureCelID = nil
        fillWork { [weak self] in self?.endFillSession() }
        refreshUndoRedoState()
        // The taps queued behind it are fills of their own, and go ahead.
        if fillCommitsOnLanding { scheduleQueuedFills() }
    }

    /// Discards the fill only if a finger is actively dragging it; an already-lifted adjustable fill
    /// survives (so a two-finger pan/zoom to inspect the canvas doesn't wipe it out).
    func cancelInteractiveFillDrag() {
        guard fillFingerDown else { return }
        cancelInteractiveFill()
    }

    /// What one render produced, carried from the fill lane to its landing: the bytes the commit bakes
    /// (nil for a lasso that enclosed nothing), and §7's picture when this render begins an empty
    /// streak.
    private struct FillRenderOutcome {
        let rendered: FillRenderResult?
        let enclosedNothing: Bool
        let diagnostic: LassoFillDiagnostic?
    }

    /// **Runs on the fill lane.** Recomputes the fill for `key` against the live gesture's session, and
    /// stores the result for the commit path before it is handed back to land. Nil when there is
    /// nothing to land: the gesture was retired while this waited, or it has no session.
    ///
    /// **`context` is the gesture this render belongs to, and the queue re-checks that it is still the
    /// live one** — before it renders and before it stores the result; the main thread drops its
    /// landing by cancelling the gesture's `fillRenders`. Without that a render whose gesture has been
    /// replaced does three separate kinds of damage, all of which the artist reads as *"filling twice
    /// breaks it"*: it renders the new seed against the old session, it overwrites the bytes the new
    /// gesture's commit bakes, and its picture installs itself as the new gesture's preview.
    private func renderFill(_ key: FillKey, for context: FillGestureContext) -> FillRenderOutcome? {
        guard isCurrentFillGeneration(context.generation), fillSession != nil, var window = fillWindow
        else { return nil }
        var session = fillSession
        var bytes: [UInt8]?
        // **The bucket's window grows here, and the lasso's never does** (`FillWindow`). A fill
        // is run, and if its paint reaches the halo band along a side that is not the canvas's
        // own the window is doubled that way, the session rebuilt for it, and the fill re-run —
        // on *every* render rather than once per gesture, because raising Threshold can let the
        // flood past a wall it stopped at last time. The loop is bounded by the canvas: each
        // step moves at least one side to the canvas edge or doubles it, and a window with no
        // growable side is trusted whole.
        while true {
            // Built once per session, and only for a fill that mends: the composite is a layer's
            // worth of drawing the artist who has not asked for it should not pay for. Here rather
            // than where the session is made so that switching the mend on over a fill already
            // on screen, and a window grown for a bigger flood, both find it in place.
            bytes = autoreleasepool {
                if key.mendReach > 0, session?.hasNeighbours == false {
                    guard let neighbours = Self.neighbourMask(of: fillGestureNeighbours, in: window) else {
                        reportFillRefusal(context)
                        return nil
                    }
                    session?.installNeighbours(neighbours)
                }
                return session.flatMap {
                    Self.runFill($0, in: window, key: key, context: context, seedColor: fillSeedColor)
                }
            } // GPU work is complete; drain command/encoder retainers before any replacement.
            guard bytes != nil, session?.isLasso == false else { break }
            guard let reached = session?.paintedReaches(band: window.band(forHalo: Self.fillWindowHalo),
                                                        of: window.growableSides) else { return nil }
            guard let grown = window.grown(toward: reached,
                                           pixelBudget: MetalFillEngine.workingPixelBudget(isLasso: false)),
                  grown != window else { break }
            // The old core has finished. Neither this local nor the property may retain it
            // during the replacement's capture/render/core peak; the old readback is stale too.
            session = nil
            bytes = nil
            guard installFillSession(for: grown, context: context, lassoMask: nil),
                  let next = fillSession, let nextWindow = fillWindow else { return nil }
            session = next
            window = nextWindow
        }
        // **The lasso's empty result, and it must leave no trace** (LASSO_FILL.md §6 step 5, §7.1).
        // A loop that encloses nothing — because it leaked through a gap, or because there was
        // nothing inside it — has to commit nothing *and push no undo entry*: a no-op that eats
        // an undo slot is a bug artists notice immediately (§8). The mechanism is simply that no
        // preview is shown, which makes `commitInteractiveFill`'s "nothing was previewed" guard
        // return before it records anything.
        //
        // `session.isLasso` rather than `fillGestureIsLasso`: this runs on the fill lane and that
        // flag is main-thread state. The count is the session's own, read on the same queue that
        // just wrote it.
        guard let session else { return nil }
        let enclosedNothing = session.isLasso && session.lastFilledPixelCount < Self.lassoFillMinimumArea
        // **Publish to the commit path before publishing to the screen.** `commitInteractiveFill`
        // reads this the moment a second tap arrives, which is long before the landing runs.
        // Empty means empty here too, so §7.1's no-undo-entry rule still holds by the same
        // mechanism (nothing to bake, so nothing recorded).
        let rendered = (enclosedNothing ? nil : bytes).map {
            FillRenderResult(generation: context.generation, documentFrame: context.documentFrame,
                             bytes: $0, window: window)
        }
        fillLock.lock()
        let stillCurrent = context.generation == fillGeneration
        if stillCurrent {
            fillRenderedRegion = rendered
            fillAnsweredGeneration = context.generation
        }
        fillLock.unlock()
        // Retired while the GPU was busy: the result belongs to nobody. A retired render touches no
        // live-gesture state and builds no picture nobody will see — `lassoFillReportedEmpty` is a
        // latch over the *live* gesture's streak of empty results and `lassoEmptyDiagnostic` reads
        // `fillGestureLoopPath`, so both are §7's version of the thing the generation stamp exists
        // to stop.
        guard stillCurrent else { return nil }
        // Said once per empty *streak*, not once per render. The gesture stays adjustable, so a
        // drag across the Threshold slider produces a run of empty results; re-raising on each would
        // flicker the banner and strobe the tint under the artist's finger. Re-arms as soon as a fill
        // lands, so losing it again is reported. Latched here rather than on the main thread because
        // the tint below is built from this session's buffers, which only this queue may read — see
        // the property's doc.
        let firstEmpty = enclosedNothing && !lassoFillReportedEmpty
        lassoFillReportedEmpty = enclosedNothing
        // **§7.2 and §7.4: the picture that goes with the sentence.** Built only on the first
        // empty result of a streak, so the canvas-sized tint costs nothing on the renders that
        // fill something and nothing on the repeats that would not be shown anyway.
        let diagnostic = firstEmpty ? lassoEmptyDiagnostic(from: session, in: window) : nil
        return FillRenderOutcome(rendered: rendered, enclosedNothing: enclosedNothing, diagnostic: diagnostic)
    }

    /// **A render's landing, on the main thread**: its bytes to the fill's host, clipped to the
    /// selection the fill obeys, and §7's sentence and picture when the render began an empty streak.
    /// A retired gesture's landing never gets here — cancelling its `fillRenders` dropped it.
    private func landFillRender(_ outcome: FillRenderOutcome, for context: FillGestureContext) {
        guard fillGestureActive,
              let layerIndex = layers.firstIndex(where: { $0.id == context.layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == context.celID }) else { return }
        guard case .resolved(let clip) = fillSelectionClip(layerIndex: layerIndex, celIndex: celIndex,
                                                          atFrame: context.documentFrame) else {
            raise(.drawingSourceUnavailable); return
        }
        showLiveFill(outcome.rendered, clip: clip)
        // The two halves of §7, raised together: the sentence naming both causes, and the
        // picture that lets the artist tell which one it was. `diagnostic` is non-nil exactly
        // when this is the first empty result of a streak, so the latch that keeps the banner
        // from flickering is the same one that keeps the tint from strobing.
        if let diagnostic = outcome.diagnostic {
            lassoFillDiagnostic = diagnostic
            raise(.nothingEnclosed)
        } else if !outcome.enclosedNothing {
            // A fill that landed retires the last one's picture rather than leaving it under
            // the new colour: the artist recovered the near-miss on a slider, and the tint is
            // now describing a state that no longer exists. Only when there is one: it is
            // published, and this runs on every render of every slider tick.
            if lassoFillDiagnostic != nil { lassoFillDiagnostic = nil }
        }
        if fillCommitsOnLanding { scheduleQueuedFills() }
    }

    /// Builds LASSO_FILL.md §7's picture for a lasso session that has just come back empty: the
    /// collar it reached, tinted, paired with the fence the artist drew.
    ///
    /// **The collar is where the paint went, and on this path that is the fence's whole interior.**
    /// An empty result *means* the collar reached everything (`lassoInvert` keeps only what it could
    /// not reach), so the tint says the thing the message names: the fence walked everywhere, and
    /// there was nothing in there to hold out. Paired with §7.4's redrawn fence it separates the two
    /// causes the sentence lists — a loop that enclosed blank paper looks different from one that
    /// closed early somewhere the artist did not intend. It is *not* a picture of a leak; see
    /// `MetalFillSession.lastReachedMask` for why a leak never reaches this path at all.
    ///
    /// Runs on the fill lane. Both of its inputs belong to that lane — the session's buffers, and
    /// `fillGestureLoopPath` — and neither is safe to read anywhere else. Returns nil without a loop
    /// rather than showing a tint with no fence beside it: half the picture invites the wrong reading
    /// (that the tinted area is what *would* have been filled), and §7.4 is there precisely because
    /// the fence is the thing most likely to be somewhere other than the artist believes.
    private func lassoEmptyDiagnostic(from session: MetalFillSession, in window: FillWindow) -> LassoFillDiagnostic? {
        guard let loop = fillGestureLoopPath, let reached = session.lastReachedMask() else { return nil }
        let tint = LassoFillMask.collarTintRGBA(reached: reached, width: session.width, height: session.height)
        let collar = tint.isEmpty ? nil : Self.imageFromRGBA(tint, width: session.width, height: session.height)
        return LassoFillDiagnostic(collar: collar.map { FillPreview(image: $0, rect: window.rect) }, loop: loop)
    }

    /// One run of the session's pipeline for `key`, with every length the key carries in canvas
    /// pixels — the radii, the seed, the paper's rect — taken into the window's working pixels.
    private static func runFill(_ session: MetalFillSession, in window: FillWindow, key: FillKey,
                                context: FillGestureContext, seedColor: SIMD4<Float>) -> [UInt8]? {
        let seed = window.workingPixel(of: CGPoint(x: context.seedX, y: context.seedY))
        let scale = Float(window.scale)
        // The paper: the canvas inset by its padding, in the window's pixels. Nil is the option off
        // — `MetalFillSession.fill` documents the rect as the one place its meaning is decided.
        let inset = CGFloat(key.inset)
        let paper = key.edgeIsWall
            ? CGRect(origin: .zero, size: window.canvasSize).insetBy(dx: inset, dy: inset).applying(window.transform)
            : nil
        return session.fill(seedX: seed.x, seedY: seed.y, seedColor: seedColor,
                            threshold: Float(Double(key.threshold) / 1000.0),
                            gapWidth: Float(key.gap) * scale, edgeOverlap: Float(key.edge) * scale,
                            artworkRect: paper, mendReach: Float(key.mendReach) * scale, fillColor: context.color)
    }

    private enum FillSelectionClip {
        /// Nil means the fill may paint freely; a failed required mapping has its own case.
        case resolved(CGPath?)
        case unavailable
    }

    /// **The selection a fill on `celIndex` of `layerIndex` is clipped to**, in the layer's coordinates —
    /// when the selection acts on that cel and outside interaction is denied; nil when the fill paints
    /// freely. The flood-fill tool analogue of `StrokeCanvasView.selectionClipPath`, so a bucket fill
    /// can't paint outside the marching ants any more than a brush stroke can. Main thread, where the
    /// selection is: read by each render's landing for the host, and by `commitInteractiveFill` for the
    /// flatten, so a fill baked by a second tap obeys the selection the same fill previewed inside.
    private func fillSelectionClip(layerIndex: Int, celIndex: Int, atFrame frame: Int) -> FillSelectionClip {
        guard let selection, !allowsPaintingOutsideSelection,
              layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              selection.acts(onLayer: layers[layerIndex].id, cel: layers[layerIndex].cels[celIndex].id)
        else { return .resolved(nil) }
        guard let path = Self.layerSpacePathIfInvertible(selection.path,
            shownThrough: inkPose(forLayerID: layers[layerIndex].id, atFrame: frame)) else { return .unavailable }
        return .resolved(path)
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
    /// RGBA byte buffer the GPU reads its walls from — the window's part of them, at the window's
    /// working size. Holds committed fills (baked into the cels' tiers), so recolouring works, and
    /// never the adjustable one, which is in no cel (`liveFill`).
    ///
    /// The tiers are the canvas-sized pictures the layer hosts already display — the raster tier's
    /// memoized readback and the vector canvas's own memo — drawn through the window's transform, so
    /// the composite allocates the window and nothing the size of the canvas. **One transient is
    /// CoreGraphics' own and is linear in the canvas's width**: drawing a bitmap-backed image into a
    /// context that clips it copies every source row the destination touches at the source's full
    /// stride, MEASURED (`FillFootprintBench`) at `windowHeight × canvasWidth × 4` — 24 MB for a
    /// 1024-row window on a 6000² canvas, 33 MB on 8192², freed when the draw returns. Cropping the
    /// image to the window first does not avoid it; the crop shares the rows.
    ///
    /// A saved fill being mended is absent from its own reference, just as an adjustable fill is.
    /// The matching cel draws its remaining display list directly into the working window; all
    /// other vector references keep the ordinary memoized render path.
    struct FillReference {
        let rgba: [UInt8]
        let support: VectorMendSupport.Reference
        let window: FillWindow
        private let walls: [VectorCanvas.Frozen]
        init(rgba: [UInt8], support: VectorMendSupport.Reference, walls: [VectorCanvas.Frozen], window: FillWindow) {
            self.rgba = rgba; self.support = support; self.walls = walls; self.window = window
        }
        func pathWall() -> [UInt8]? {
            StrokeWallMask.mask(of: walls, width: window.workingWidth, height: window.workingHeight,
                                transform: window.transform)
        }
    }

    private struct FillReferenceSnapshot {
        let baked: RasterSource?, raster: RasterSource?, vector: VectorCanvas.Frozen?
        let kind: LayerKind, celID: UUID
        func nativeImageBytes(in size: CGSize) -> Int {
            let pixels = size.width * size.height
            guard pixels.isFinite, pixels > 0, pixels < CGFloat(Int.max / 8) else { return Int.max }
            let one = Int(pixels) * 4
            var peak = baked.map({ !$0.isCertainlyTransparent }) == true
                || raster.map({ !$0.isCertainlyTransparent }) == true ? one : 0
            if let vector { peak = max(peak, vector.fillReferenceImageBytes) }
            return peak
        }
    }

    private static func fillReferenceListBytes(_ count: Int) -> Int {
        UndoBudget.addingCost(96, UndoBudget.payloadBytes(count: count,
            stride: 2 * (MemoryLayout<FillReferenceSnapshot>.stride + MemoryLayout<VectorCanvas.Frozen>.stride)))
    }

    private static func freezeFillReferences(_ references: [(layer: Layer, cel: Cel)]) -> [FillReferenceSnapshot] {
        references.map { source in
            FillReferenceSnapshot(baked: source.cel.bakedImage, raster: source.cel.raster.snapshot(),
                vector: source.cel.vector?.freezeFillReference(), kind: source.layer.kind, celID: source.cel.id)
        }
    }

    /// Explicit worker proof only. The source keeps its getter cheap and scans no image/backing;
    /// an admitted builder pays the pinned lease's actual alpha visits before its sole scan.
    private static func prepareFillTransparency(_ source: RasterSource,
        support: inout VectorMendSupport.Reference.Builder?, isCurrent: () -> Bool) throws(VectorMendSupport.Failure) {
        guard var builder = support else { return }
        defer { support = builder }
        var denied: VectorMendSupport.Failure?
        let result = source.prepareTransparencyProof { count in
            do throws(VectorMendSupport.Failure) {
                guard isCurrent() else { throw .cancelled }
                try builder.consumeWork(count)
                return true
            } catch { denied = error; return false }
        }
        if let denied { throw denied }
        guard case .success = result else { throw .exceedsBudget }
    }

    /// One frozen selected list owns the pixels, path walls and lazy canonical certificate. Raster
    /// snapshots are immutable source handles; nil is their existing exact transparency proof.
    static func makeFillReference(references: [(layer: Layer, cel: Cel)], window: FillWindow,
                                  excludingElement: (celID: UUID, elementID: UUID)? = nil,
                                  isLasso: Bool = false, reserving reservedBytes: Int = 0,
                                  certifiesMend: Bool = true) -> FillReference? {
        let listBytes = fillReferenceListBytes(references.count)
        guard reservedBytes >= 0, reservedBytes < MetalFillEngine.fillBudgetBytes,
              listBytes < MetalFillEngine.fillBudgetBytes - reservedBytes,
              MemoryBudget.shared.makeRoom(for: listBytes) else { return nil }
        return drawFillReference(snapshots: freezeFillReferences(references), window: window,
                          excludingElement: excludingElement, isLasso: isLasso,
                          supportOverride: window.scale < 1 || !certifiesMend ? .unavailable(width: window.workingWidth,
                              height: window.workingHeight) : nil, reservedBytes: reservedBytes, isCurrent: { true })
    }

    /// A scaled request plans geometry before allocating the core or filtering any image. Native
    /// windows keep the existing lazy recipe. This local owner dies at publication; hot SOURCE,
    /// Reach, Overlap and colour ticks use the session's one completed geometry packet.
    static func prepareFillReference(references: [(layer: Layer, cel: Cel)], window original: FillWindow,
                                     excludingElement: (celID: UUID, elementID: UUID)? = nil,
                                     isLasso: Bool = false, reserving reservedBytes: Int = 0,
                                     certifiesMend: Bool = true, isCurrent: () -> Bool) -> FillReference? {
        guard isCurrent() else { return nil }
        guard original.scale < 1, certifiesMend else {
            return makeFillReference(references: references, window: original,
                                     excludingElement: excludingElement, isLasso: isLasso, reserving: reservedBytes,
                                     certifiesMend: certifiesMend)
        }
        guard reservedBytes >= 0, reservedBytes < MetalFillEngine.fillBudgetBytes else { return nil }
        let budget = MetalFillEngine.fillBudgetBytes - reservedBytes
        let listBytes = fillReferenceListBytes(references.count)
        guard listBytes < budget, MemoryBudget.shared.makeRoom(for: listBytes) else { return nil }
        let snapshots = freezeFillReferences(references)
        let size = original.canvasSize
        guard size.width > 0, size.height > 0, size.width <= 16_383, size.height <= 16_383,
              size.width.rounded() == size.width, size.height.rounded() == size.height else { return nil }
        let sourceCapacity = UndoBudget.payloadBytes(count: snapshots.capacity, stride: MemoryLayout<FillReferenceSnapshot>.stride)
        guard sourceCapacity <= UndoBudget.addingCost(16,
            UndoBudget.payloadBytes(count: references.count, stride: 2 * MemoryLayout<FillReferenceSnapshot>.stride)) else { return nil }
        var maximumRecords = snapshots.count
        for source in snapshots {
            maximumRecords = UndoBudget.addingCost(maximumRecords, source.vector?.fillReferenceRecordCount ?? 0)
        }
        var request = VectorMendSupport.Meter(admission: .init(bytes: budget - listBytes, work: 64_000_000))
        var proposed = original
        do throws(VectorMendSupport.Failure) {
            var recipe: VectorMendSupport.Reference?
            do {
                var builder: VectorMendSupport.Reference.Builder? = try .init(width: Int(size.width),
                    height: Int(size.height), maximumRecords: maximumRecords, admission: request.admission)
                for source in snapshots {
                    guard isCurrent() else { throw .cancelled }
                    if let baked = source.baked {
                        try prepareFillTransparency(baked, support: &builder, isCurrent: isCurrent)
                    }
                    if let raster = source.raster {
                        try prepareFillTransparency(raster, support: &builder, isCurrent: isCurrent)
                    }
                    // Raster/baked uncertainty covers this ENTIRE window. The same final strict
                    // draw resolves its cached proof, then either keeps this private vector packet
                    // or disables it wholesale; do not capture an anonymous stale raster span.
                    let excluded = excludingElement.flatMap { $0.celID == source.celID ? $0.elementID : nil }
                    source.vector?.stageFillReference(into: &builder, nativeSize: size, excludingElement: excluded)
                    guard builder != nil else { throw .exceedsBudget }
                }
                recipe = builder?.finish()
            }
            var captured: VectorMendSupport.Preparation?
            do {
                guard let sourceRecipe = recipe else { throw .exceedsBudget }
                captured = try VectorMendSupport.prepare(sourceRecipe, meter: &request, isCurrent: isCurrent)
            }
            recipe = nil
            let captureCharge = request.bytes
            var reservation = 0
            var packet: VectorMendSupport.Packet?
            // A reservation grows geometrically only when required; the SAME work account can
            // refuse sooner. At most32 positive doublings fit the existing <=768MiB budget.
            for _ in 0..<32 {
                guard isCurrent(), captured != nil else { throw .cancelled }
                do {
                    let result: Result<VectorMendSupport.Packet, VectorMendSupport.Failure> = autoreleasepool {
                        do throws(VectorMendSupport.Failure) {
                            return .success(try VectorMendSupport.produce(captured!, in: proposed,
                                meter: &request, isCurrent: isCurrent))
                        } catch { return .failure(error) }
                    }
                    packet = try result.get()
                } // The result has no surviving packet alias when retry storage is retired.
                guard packet != nil else { throw .exceedsBudget }
                let rows = packet!.retainedBytes
                let upload = [UndoBudget.payloadBytes(count: packet!.patches.count, stride: MemoryLayout<VectorMendSupport.Patch>.stride),
                    UndoBudget.payloadBytes(count: packet!.contacts.count, stride: MemoryLayout<VectorMendSupport.Contact>.stride),
                    UndoBudget.payloadBytes(count: packet!.canonicalCoverage.count, stride: MemoryLayout<VectorMendSupport.Span>.stride),
                    12].reduce(0, UndoBudget.addingCost)
                let required = UndoBudget.addingCost(rows, upload)
                if required > reservation {
                    reservation = max(required, UndoBudget.addingCost(reservation, reservation))
                }
                let fixed = [listBytes, reservation, 512].reduce(0, UndoBudget.addingCost)
                let perPixel = MetalFillSession.bytesPerPixel(isLasso: isLasso, twoReferenceColours: true)
                    + 14 + (isLasso ? 4 : 2)
                guard fixed < budget, (budget - fixed) / perPixel > 0 else { throw .exceedsBudget }
                let pixelBudget = min(original.workingWidth * original.workingHeight, (budget - fixed) / perPixel)
                let fitted = FillWindow.fitting(original.rect, in: size, pixelBudget: pixelBudget)
                if fitted != proposed {
                    packet = nil // retire attempt rows before crediting their storage
                    proposed = fitted
                    request.bytes = captureCharge
                    continue
                }
                let pixels = proposed.workingWidth * proposed.workingHeight
                let nativeBytes = snapshots.reduce(0) { max($0, $1.nativeImageBytes(in: size)) }
                let renderFixed = [listBytes, rows, nativeBytes, pixels * 14].reduce(0, UndoBudget.addingCost)
                guard renderFixed < budget, isCurrent(),
                      let sampling = ImageWarp.RasterScaleSupport(sourceSize: size,
                        destination: CGRect(x: 0, y: 0, width: proposed.workingWidth, height: proposed.workingHeight),
                        inverseTexelMap: Homography(proposed.transform.inverted())) else { throw .exceedsBudget }
                let tileAllowance = budget - renderFixed
                var planningFailure: VectorMendSupport.Failure?
                var cropRequests = 0, planLeaves = 0
                let plansFit = ImageWarp.forEachRasterPlan(sourceSize: size, destination: sampling.destination,
                    inverseTexelMap: sampling.inverseTexelMap, maximumWorkingBytes: tileAllowance) { plan in
                        do throws(VectorMendSupport.Failure) {
                            // A split tree has fewer than twice as many nodes as leaves.
                            try request.visit(2)
                            planLeaves += 1
                            let (total, overflow) = cropRequests.addingReportingOverflow(
                                Int(plan.sourceRect.width * plan.sourceRect.height))
                            guard !overflow else { throw .exceedsWork }
                            cropRequests = total
                        } catch { planningFailure = error; return false }
                        return isCurrent()
                    }
                if let planningFailure { throw planningFailure }
                guard plansFit, isCurrent() else { throw .cancelled }
                guard let taps = try sampling.tapReadBound(visit: {
                    () throws(VectorMendSupport.Failure) in try request.visit(1)
                }) else { throw .exceedsWork }
                var imageStages = 0
                for source in snapshots {
                    try request.visit(1)
                    if source.baked.map({ !$0.isCertainlyTransparent }) == true { imageStages += 1 }
                    if source.raster.map({ !$0.isCertainlyTransparent }) == true { imageStages += 1 }
                    if (source.vector?.fillReferenceRecordCount ?? 0) > 0 { imageStages += 1 }
                }
                // Drawing repeats this same bounded planning walk once for each image stage.
                try request.visit(planLeaves, times: 2 * imageStages)
                // Upload/crop requests and repeated shader reads are DISTINCT finite bounds.
                // Neither is relabelled as the64M canonical-construction work allowance.
                guard !cropRequests.multipliedReportingOverflow(by: imageStages).overflow,
                      !taps.multipliedReportingOverflow(by: imageStages).overflow else { throw .exceedsWork }
                try request.visit(pixels, times: 2) // composite/copy initialization, separate from GPU filter taps
                captured = nil
                // Only completed rows survive capture retirement. The actual chosen image stages
                // still have to validate and draw successfully before this value can be returned.
                let reference = VectorMendSupport.Reference.completed(packet!)
                return autoreleasepool {
                    drawFillReference(snapshots: snapshots, window: proposed, excludingElement: excludingElement,
                        isLasso: isLasso, supportOverride: reference,
                        maximumWorkingBytes: tileAllowance, reservedBytes: reservedBytes, isCurrent: isCurrent)
                }
            }
            throw .exceedsBudget
        } catch {
            guard isCurrent() else { return nil }
            // An incomplete certificate disables only new interior acceptance; the existing
            // basin fill and neighbour seam still use the same actual frozen picture.
            return autoreleasepool {
                drawFillReference(snapshots: snapshots, window: proposed, excludingElement: excludingElement,
                    isLasso: isLasso, supportOverride: .unavailable(width: proposed.workingWidth,
                        height: proposed.workingHeight), reservedBytes: reservedBytes, isCurrent: isCurrent)
            }
        }
    }

    /// Both fixed-grid neighbours and fitted fill preparation draw this one frozen list in the
    /// same order. A prepared support value is still private until every actual image succeeds.
    private static func drawFillReference(snapshots: [FillReferenceSnapshot], window: FillWindow,
                                         excludingElement: (celID: UUID, elementID: UUID)?, isLasso: Bool,
                                         supportOverride: VectorMendSupport.Reference?,
                                         maximumWorkingBytes: Int = CompositorBudget.textureBudgetBytes, reservedBytes: Int = 0,
                                         isCurrent: () -> Bool) -> FillReference? {
        let width = window.workingWidth, height = window.workingHeight
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, count <= Int.max / 64,
              reservedBytes >= 0, reservedBytes < MetalFillEngine.fillBudgetBytes,
              supportOverride.map({ $0.width == width && $0.height == height }) ?? true else { return nil }
        // Reserve the impending session and old/new SOURCE cuts before support metadata. The
        // frozen draw list and path-wall list coexist with that one output pair during preparation.
        let cutReserve = UndoBudget.addingCost(512,
            UndoBudget.payloadBytes(count: count, stride: isLasso ? 4 : 2))
        let listReserve = fillReferenceListBytes(snapshots.count)
        let reserved = [MetalFillSession.predictedBytes(width: width, height: height, isLasso: isLasso),
                        cutReserve, listReserve, reservedBytes].reduce(0, UndoBudget.addingCost)
        let allowance = max(0, MetalFillEngine.fillBudgetBytes - reserved)
        var maximumRecords = snapshots.count
        for snapshot in snapshots {
            maximumRecords = UndoBudget.addingCost(maximumRecords, snapshot.vector?.fillReferenceRecordCount ?? 0)
        }
        var support: VectorMendSupport.Reference.Builder?
        var acceptedOverride = supportOverride
        do throws(VectorMendSupport.Failure) {
            guard UndoBudget.payloadBytes(count: snapshots.capacity, stride: MemoryLayout<FillReferenceSnapshot>.stride)
                <= UndoBudget.addingCost(16, UndoBudget.payloadBytes(count: snapshots.count,
                    stride: 2 * MemoryLayout<FillReferenceSnapshot>.stride)) else { throw .exceedsBudget }
            if supportOverride == nil {
                support = try .init(width: width, height: height, maximumRecords: maximumRecords,
                    admission: .init(bytes: allowance, work: 64_000_000))
            }
        } catch {
            support = nil
            if acceptedOverride != nil { acceptedOverride = .unavailable(width: width, height: height) }
        }
        var tileAllowance = maximumWorkingBytes
        if window.scale < 1 {
            let nativeBytes = snapshots.reduce(0) { max($0, $1.nativeImageBytes(in: window.canvasSize)) }
            let fixed = [reservedBytes, nativeBytes, count * 8, listReserve,
                         acceptedOverride?.retainedBytes ?? 0].reduce(0, UndoBudget.addingCost)
            guard fixed < MetalFillEngine.fillBudgetBytes else { return nil }
            tileAllowance = min(tileAllowance, MetalFillEngine.fillBudgetBytes - fixed)
            guard tileAllowance > 0, MemoryBudget.shared.makeRoom(for: fixed) else { return nil }
        }
        var completed = true
        var walls: [VectorCanvas.Frozen] = []
        walls.reserveCapacity(snapshots.count)
        let sampling = window.scale < 1 ? ImageWarp.RasterScaleSupport(sourceSize: window.canvasSize,
            destination: CGRect(x: 0, y: 0, width: width, height: height),
            inverseTexelMap: Homography(window.transform.inverted())) : nil
        if window.scale < 1 && sampling == nil { return nil }
        // Into an admitted buffer (`PixelOps.drawImage`): the one budget sees it, and no renderer copy.
        let composited = PixelOps.drawImage(size: CGSize(width: width, height: height)) { cg in
            let rect = window.canvasInWorking
            for source in snapshots {
                guard isCurrent() else { completed = false; return false }
                do throws(VectorMendSupport.Failure) {
                    if let baked = source.baked {
                        try prepareFillTransparency(baked, support: &support, isCurrent: isCurrent)
                    }
                    if let raster = source.raster {
                        try prepareFillTransparency(raster, support: &support, isCurrent: isCurrent)
                    }
                } catch { support = nil }
                guard isCurrent() else { completed = false; return false }
                do {
                    for value in [source.baked, source.raster] {
                        guard let raster = value, !raster.isCertainlyTransparent else { continue }
                        let drawn = try autoreleasepool { () throws -> Bool in
                            let image = try raster.resolveImage().get()
                            guard let sampling else { image.draw(in: rect); return true }
                            guard image.scale == 1, image.imageOrientation == .up,
                                  image.size == window.canvasSize, let pixels = image.cgImage,
                                  pixels.width == Int(window.canvasSize.width),
                                  pixels.height == Int(window.canvasSize.height) else { return false }
                            cg.saveGState(); cg.interpolationQuality = .none
                            let completed = ImageWarp.drawRaster(sourceSize: sampling.sourceSize,
                                destination: sampling.destination, inverseTexelMap: sampling.inverseTexelMap,
                                maximumWorkingBytes: tileAllowance, isCurrent: isCurrent,
                                source: { pixels.cropping(to: $0) }, consume: { tile, rect in
                                    UIImage(cgImage: tile, scale: 1, orientation: .up).draw(in: rect)
                                })
                            cg.restoreGState()
                            return completed
                        }
                        guard drawn else { completed = false; return false }
                    }
                } catch { completed = false; return false }
                if source.baked.map({ !$0.isCertainlyTransparent }) == true
                    || source.raster.map({ !$0.isCertainlyTransparent }) == true {
                    // Monotonic across the actual frozen draw order: one nonempty/unproved
                    // raster invalidates scaled support, even if a later contributor is clear.
                    if acceptedOverride != nil { acceptedOverride = .unavailable(width: width, height: height) }
                    do throws(VectorMendSupport.Failure) {
                        try support?.appendUnknown(CGRect(x: 0, y: 0, width: width, height: height))
                    } catch { support = nil }
                }
                if let vector = source.vector {
                    let excluded = excludingElement.flatMap { $0.celID == source.celID ? $0.elementID : nil }
                    let drawn = autoreleasepool {
                        vector.drawFillReference(into: cg, frameRect: rect,
                            width: width, height: height, excludingElement: excluded, support: &support,
                            sampling: sampling, maximumWorkingBytes: tileAllowance, isCurrent: isCurrent)
                    }
                    guard let drawn else {
                        completed = false; return false
                    }
                    if source.kind == .vector { walls.append(drawn) }
                }
            }
            return true
        }
        guard completed, isCurrent(), let composited, composited.scale == 1, composited.imageOrientation == .up,
              composited.size == CGSize(width: width, height: height), let cg = composited.cgImage,
              cg.width == width, cg.height == height else { return nil }
        // The RGBA reference the fill reads, admitted while it is made from the picture above.
        guard let referenceGrant = MemoryBudget.shared.admit(width * height * 4) else { return nil }
        defer { referenceGrant.release() }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            // Same-size top-down image copy; no extra flip or resampling stage.
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok, isCurrent() else { return nil }
        if UndoBudget.payloadBytes(count: walls.capacity, stride: MemoryLayout<VectorCanvas.Frozen>.stride)
            > UndoBudget.addingCost(16, UndoBudget.payloadBytes(count: snapshots.count,
                stride: 2 * MemoryLayout<VectorCanvas.Frozen>.stride)) {
            support = nil
            if acceptedOverride != nil { acceptedOverride = .unavailable(width: width, height: height) }
        }
        return FillReference(rgba: bytes,
            support: acceptedOverride ?? support?.finish() ?? .unavailable(width: width, height: height),
            walls: walls, window: window)
    }

    static func compositeReferenceRGBA(references: [(layer: Layer, cel: Cel)], window: FillWindow,
                                        excludingElement: (celID: UUID, elementID: UUID)? = nil,
                                        reserving reservedBytes: Int = 0) -> [UInt8]? {
        makeFillReference(references: references, window: window, excludingElement: excludingElement,
                          reserving: reservedBytes)?.rgba
    }

    /// Where `sources` have any paint at all, in the window's working pixels — the mend's neighbour set
    /// (TODO (113)). The same composite the reference is, of the one cel the fill lands on, so a
    /// vector cel's fills are drawn the way the artist sees them and a raster cel's committed fills
    /// are in it however they were baked. Unavailable pixels are a refusal, never an empty set:
    /// an empty fallback could let mending paint over content that was not rendered.
    static func neighbourMask(of sources: [(layer: Layer, cel: Cel)], in window: FillWindow,
                              reserving reservedBytes: Int = 0) -> [UInt8]? {
        let count = window.workingWidth * window.workingHeight
        guard let rgba = autoreleasepool(invoking: {
            compositeReferenceRGBA(references: sources, window: window, reserving: reservedBytes)
        }) else {
            return nil
        }
        return (0..<count).map { rgba[$0 * 4 + 3] != 0 ? 255 : 0 }
    }

    /// Wraps a top-left-origin premultiplied-last RGBA byte buffer into a UIImage for the fill preview.
    /// Built via a `CGDataProvider`, which is canonically top-down (data row 0 is the top) — matching the
    /// top-down reference the GPU fills against, so the painted region displays where it was tapped.
    static func imageFromRGBA(_ bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                               bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

}
