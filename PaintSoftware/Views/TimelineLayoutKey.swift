import UIKit

/// Which frame columns of the ruler a dirty rect touches.
///
/// Split out of `TimelineRulerView.draw(_:)` so it is arithmetic rather than drawing — and so it can
/// be tested, since the view itself is `private` to `TimelineTrackView.swift` and a `UIView`'s
/// `draw` is not something a headless test can call anyway.
enum TimelineRulerClip {

    /// Clamped to `0..<frameCount`, with **one frame of slack on each side**.
    ///
    /// The slack is not padding for its own sake. A number is drawn at its column's left edge plus
    /// 2pt and is wider than nothing, so the label belonging to the column just left of `rect` can
    /// still have pixels inside it, and one at the right edge can overhang. A clip taking only the
    /// columns whose *origins* fall inside the rect would drop exactly those two, which shows up as
    /// numbers missing at a tile boundary — the failure mode of a clip is a hole, and a hole is
    /// harder to spot in review than a redundant draw.
    static func frames(in rect: CGRect, pixelsPerFrame: CGFloat, frameCount: Int) -> Range<Int> {
        guard frameCount > 0, pixelsPerFrame > 0, rect.width > 0 else { return 0..<0 }
        let first = max(0, Int((rect.minX / pixelsPerFrame).rounded(.down)) - 1)
        let last = min(frameCount, Int((rect.maxX / pixelsPerFrame).rounded(.up)) + 1)
        guard first < last else { return 0..<0 }
        return first..<last
    }
}

/// Everything `TimelineTrackView.Coordinator.relayout()` reads, as one comparable value.
///
/// **The problem it exists to solve.** `relayout()` ran unconditionally on every `updateUIView` —
/// which is every SwiftUI pass, and `CanvasManager` republishes on a great deal more than a timeline
/// edit. Each run re-derived every row's segment list, sorted each layer's cels, assigned a frame and
/// an accessibility identifier to every block view (a fresh interpolated `String` per cel per pass),
/// recomputed every folder's span by flat-mapping its descendants' cels, and called
/// `setNeedsDisplay()` on a ruler that lays out one `NSAttributedString` per frame of the scene. A
/// 300-frame, 6-layer document therefore paid 300 CoreText layouts and O(total cels) of view churn
/// on ticks where nothing it draws had moved — most obviously while scrubbing, where `onScrub` fires
/// unthrottled on every `.changed` sample.
///
/// **This is a constant-factor win, not an asymptotic one, and the doc comment says so rather than
/// letting the next reader assume otherwise.** Building this key is itself O(total cels): it walks
/// the same cels and pays the same folder-span flat-map. What it does not pay is the view mutation,
/// the string interpolation, the sort, the animation bookkeeping, or the ruler's CoreText — and those
/// are the expensive terms. The scene-length half of the cost is removed outright, since the ruler is
/// only invalidated when the key moves.
///
/// **Modelled on `CanvasView.SandwichKey` and `InterpolationPreviewKey`, which is the third use of
/// this idiom in the codebase and its rules travel with it**: every input the layout evaluates goes
/// in the key, and nothing that moves faster than the layout does. `currentFrame` is the one input
/// deliberately left out — the playhead is its own subview and a scrub moves nothing else on the
/// track, so it gets a fast path instead of a key field. Putting it in would make the key move on
/// every tick of the very gesture this exists to make cheap.
///
/// **The `ObjectIdentifier`s carry the same ABA hazard `LayerContentVersion` documents, and it is
/// closed the same way**: the coordinator retains the thumbnails this key names for exactly as long
/// as it holds the key, so a stale address cannot be reused by a new object and read as equal.
struct TimelineLayoutKey: Equatable {

    /// One block on a track. Everything `TimelineRowView.update` draws from, and nothing else.
    struct CelKey: Equatable {
        let id: UUID
        let startFrame: Int
        let frameCount: Int
        /// The picture on the block. Identity rather than content, because a regenerated thumbnail
        /// replaces the object wholesale — the same reason `LayerContentVersion` compares
        /// `fillImage`/`bakedImage` that way.
        let thumbnail: ObjectIdentifier?
    }

    /// A folder's summary band. Its span is derived from every descendant's cels, so it moves when a
    /// child's block does even though the folder holds no cels of its own.
    struct FolderKey: Equatable {
        let id: UUID
        let name: String
        let isVisible: Bool
        let span: ClosedRange<Int>?
        /// The folder's own markers — §2.21 makes a folder's grade animate exactly as a layer's, so
        /// the folder row draws a marker band like any other row. Its **own** marks and keys, not its
        /// descendants': a marker says "a keyframe is here on this target", and a target is a row.
        let markers: [Int]
    }

    /// A block in flight. `TimelineTrackView.Coordinator.BlockDrag` mapped down to the parts the
    /// layout reads — declared here rather than referenced there so this type stays free of the view,
    /// which is what lets a headless test build one.
    struct DragKey: Equatable {
        let celID: UUID
        let sourceLayerIndex: Int
        let targetLayerIndex: Int
        let targetStartFrame: Int
        let frameCount: Int
    }

    /// The presented stack: row order, nesting depth, and which folders are collapsed. `LayerStackRow`
    /// is already `Equatable`, so this one field covers every structural change at once.
    let rows: [LayerStackRow]
    /// Parallel to the `.layer` entries of `rows`, in their order.
    let tracks: [[CelKey]]
    /// The document frames each of those layers carries a keyframe on — ascending, unique, and **one
    /// entry per frame however many channels key there** (`CanvasManager.keyframeFrames(of:)`).
    ///
    /// **A second array rather than a field on `CelKey`, because a keyframe is not on a cel.** §2.4
    /// puts effect keys on the *layer*, in absolute document frames, and §2.26's marks likewise, so
    /// they exist perfectly well at frames the layer has no cel at, and the marker band spans the
    /// whole track for that reason.
    ///
    /// **Every input the union reads has to be reachable from this key, or the band renders once and
    /// freezes** — `relayout()` early-returns on `built.key == laidOutKey`. It is: the union's own
    /// output *is* this field, so a mark, a curve key or a grade going away all change it.
    ///
    /// **Cheap enough to compare on every layout, which is the bar this key has to clear.** Building
    /// it is an id lookup and two `isEmpty` checks per layer for the overwhelming majority of
    /// documents, which have neither a mark nor a track; for one that does it is a walk of the curves'
    /// own key arrays and nothing else — in particular it never touches `Effect.parameters`, which
    /// rebuilds up to thirty-three closures per call. Comparing it is equality over a handful of
    /// `Int`s, against a key that already carries every cel's id, start, length and thumbnail
    /// address.
    let trackMarkers: [[Int]]
    /// Parallel to the `.folder` entries of `rows`, in their order.
    let folders: [FolderKey]

    let currentLayerIndex: Int
    let pixelsPerFrame: CGFloat
    let displayedFrameCount: Int
    let contentWidth: CGFloat
    /// **The height every *unexpanded* row is, which is no longer the whole story.** It was
    /// sufficient on its own while heights were a pure function of `(rows, rowHeight)` and `rows` was
    /// already in the key; `graphBand` below is the input that broke that, and it is in the key for
    /// exactly this reason (KEYFRAMES.md §11.2).
    let rowHeight: CGFloat
    let rulerHeight: CGFloat
    let loopRange: ClosedRange<Int>?

    /// **The graph editor band: which row it expands, by how much, and every curve it draws.**
    ///
    /// Three separate things it has to carry, and each one fails silently if it is left out.
    ///
    /// 1. **The expanded row and its height**, because `relayout()` early-returns on an unchanged
    ///    key and D2 is the first stage to derive a row's height from something other than
    ///    `(rows, rowHeight)`. Without it, opening the band leaves every row exactly where it was
    ///    and nothing at all happens.
    /// 2. **The curves themselves**, because unlike the playhead a curve changes *shape* rather than
    ///    position, so it cannot take a `movePlayhead`-style fast path. `AnimationCurve` is
    ///    `Equatable`, so this is an ordinary field rather than a hash — and no hash has to be
    ///    described, audited, or kept in step with the fields it covers.
    /// 3. **Nothing while the band is closed.** `nil`, so a document that has never opened the
    ///    editor pays one optional comparison and the cost argument for the whole gate is unchanged.
    ///
    /// **Cheap enough to compare every layout, which is the bar this key has to clear.** Only one
    /// band is open at a time (the owner's scope ruling), so the worst case is one layer's animated
    /// channels — a handful of curves of a handful of keys — against a key that already carries
    /// every cel's id, start, length and thumbnail address. Building it walks `Effect.parameters`
    /// once, and only while the band is open.
    ///
    /// **`uiRange` rides along inside `Channel` rather than being looked up at draw time**, so the
    /// axis a curve is drawn against is keyed too. It is a function of the parameter id today — ids
    /// are `"<case>.<field>"`, so no two effects share one — but "the drawn value is in the key" is
    /// the property worth having by construction rather than by that argument.
    let graphBand: TimelineGraphBand.Content?

    /// Interpolate mode highlights reference blocks in yellow. The reference list is carried whole
    /// rather than resolved per cel — it is a short array and `CelRef` is `Equatable`, so this is one
    /// comparison instead of one `contains` per block — and only while the mode is on, so a document
    /// that has never used interpolation pays nothing for it.
    let isInterpolateMode: Bool
    let interpolationReferences: [CelRef]

    let drag: DragKey?
}

extension TimelineLayoutKey {

    /// Builds the key for the timeline as it stands, and hands back the thumbnails it named.
    ///
    /// **The second half of the tuple is not incidental.** `CelKey.thumbnail` is an address, and an
    /// address is only a sound identity while the object behind it cannot be freed and replaced. The
    /// caller stores these alongside the key and drops them together — the idiom
    /// `CanvasView.Coordinator` spells out at its `retainedOnionSources`.
    @MainActor
    static func make(canvasManager: CanvasManager,
                     stackRows: [LayerStackRow],
                     pixelsPerFrame: CGFloat,
                     displayedFrameCount: Int,
                     contentWidth: CGFloat,
                     rowHeight: CGFloat,
                     rulerHeight: CGFloat,
                     drag: DragKey?) -> (key: TimelineLayoutKey, retainedThumbnails: [UIImage]) {
        var tracks: [[CelKey]] = []
        var trackMarkers: [[Int]] = []
        var folders: [FolderKey] = []
        var retained: [UIImage] = []

        for row in stackRows {
            if let layerIndex = row.layerIndex, canvasManager.layers.indices.contains(layerIndex) {
                let layer = canvasManager.layers[layerIndex]
                let cels = layer.cels.map { cel -> CelKey in
                    if let thumbnail = cel.thumbnail { retained.append(thumbnail) }
                    return CelKey(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                                  thumbnail: cel.thumbnail.map(ObjectIdentifier.init))
                }
                tracks.append(cels)
                // **What counts as a keyframe is the model's answer, asked here rather than rebuilt.**
                // `CanvasManager.keyframeFrames(of:)` unions the explicit marks with every frame a
                // channel in force keys on, and carries the grade asymmetry that used to sit on this
                // line.
                trackMarkers.append(canvasManager.keyframeFrames(of: .layer(id: layer.id)))
            } else if let folderID = row.folderID {
                let folder = canvasManager.folders.first { $0.id == folderID }
                let childCels = canvasManager.descendantLayerIndices(ofFolder: folderID)
                    .flatMap { canvasManager.layers[$0].cels }
                let span: ClosedRange<Int>? = childCels.isEmpty
                    ? nil
                    : (childCels.map(\.startFrame).min() ?? 0)...(childCels.map(\.endFrame).max() ?? 0)
                // §2.21: a folder's grade animates exactly as a layer's, so it asks the same accessor.
                folders.append(FolderKey(id: folderID,
                                         name: folder?.name ?? folderID.uuidString,
                                         isVisible: folder?.isVisible ?? true,
                                         span: span,
                                         markers: canvasManager.keyframeFrames(of: .folder(id: folderID))))
            }
        }

        let loopRange = (canvasManager.loopStartFrame != nil || canvasManager.loopEndFrame != nil)
            ? canvasManager.effectiveLoopRange
            : nil

        let key = TimelineLayoutKey(
            rows: stackRows,
            tracks: tracks,
            trackMarkers: trackMarkers,
            folders: folders,
            currentLayerIndex: canvasManager.currentLayerIndex,
            pixelsPerFrame: pixelsPerFrame,
            displayedFrameCount: displayedFrameCount,
            contentWidth: contentWidth,
            rowHeight: rowHeight,
            rulerHeight: rulerHeight,
            loopRange: loopRange,
            graphBand: canvasManager.graphBandContent,
            isInterpolateMode: canvasManager.isInterpolateMode,
            interpolationReferences: canvasManager.isInterpolateMode ? canvasManager.interpolationReferences : [],
            drag: drag
        )
        return (key, retained)
    }
}
