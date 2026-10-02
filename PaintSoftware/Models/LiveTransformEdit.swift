import Foundation

/// **A transform being edited, finger down** — TODO (125), (136) and (140), which the owner named as
/// one task: *"I feel like this fix and ask 15 should basically be the same task without the need for
/// two separate mechanisms."*
///
/// ## Why each of the three lagged, MEASURED (PERFORMANCE.md §24)
///
/// - **A transformation layer's Move** wrote its pose on every tick, and its box was a floating piece,
///   which took the canvas off the compositor onto Core Animation's flat row of hosts — so every tick
///   re-rasterized every posed drawing beneath it **on the main thread**, one canvas-sized rest-space
///   dab bake per layer. Two updates a second on the owner's canvas in a simulator.
/// - **A pose node dragged in the graph editor** kept the compositor, and every tick moved its key:
///   the live pair and the bake both restarted each tick, re-posing the same drawings, and neither
///   ever landed while the finger moved. The canvas stood still for the whole drag.
/// - **A folder's Move** was already the cheap shape — its lifted ink is a picture under a Core
///   Animation transform (`StrokeCanvasView.updateVectorFloat`), and it measured realtime per update.
///   What it paid for was the baker, compositing every frame of the lifted-hole state underneath it.
///
/// ## The one mechanism
///
/// While an edit is set, **nothing the edit changes is rasterized**. The canvas cuts the frame around
/// the leaves the edit moves (`liveTransformRuns`), composites the bands once off the main thread
/// (`SandwichRecipe.compositeBands`), and re-poses each moving band per update with a Core Animation
/// transform — the delta from the map its ink was shown through when the band was minted to the map
/// it is shown through now (`liveTransformMaps`). That is `LiveLayerTransform`'s rule (PERFORMANCE.md
/// item 11 — stop re-rendering what Core Animation is compositing anyway), applied to the sandwich
/// the brush already uses, as the owner suggested. A floating piece needs no bands: its picture is
/// already its own.
///
/// **And the baker holds off** (`FrameBaker.isSuspended`, the stroke's own seam) until the finger
/// lifts — the owner's *"pause the background renderer until the user raises their pen off the move
/// tool"* — then bakes the result once. The bands stay up until a picture of the result lands
/// (`SandwichPresentation.next`), so nothing stale is shown after release.
enum LiveTransformEdit: Equatable {

    /// A transformation layer's own pose — its Move box, a take recorded through that box, or its pose
    /// nodes dragged in the graph editor. Everything the layer poses moves.
    case container(layerID: UUID)

    /// One cel's whole-drawing pose channel dragged in the graph editor: that layer's drawing moves.
    case cel(layerID: UUID)

    /// A Move box over a floating piece — lifted pixels, lassoed ink, a folder's contents, a Duplicate
    /// Offset's copy. The piece draws its own picture, so the canvas cuts no bands for it; only the
    /// baker's hold applies.
    case floatingPiece

    /// Whether the canvas draws this edit as bands re-posed by Core Animation.
    var movesBands: Bool { self != .floatingPiece }
}

extension CanvasManager {

    /// **What a finger on the Move box is editing**, read off what the box holds: a transformation
    /// layer's pose for `beginContainerPoseMove`'s box, the piece itself for every other.
    var moveBoxEdit: LiveTransformEdit? {
        if let piece = floatingPiece {
            if piece.kind == .containerPose, case .layer(let id)? = piece.containerTarget {
                return .container(layerID: id)
            }
            return .floatingPiece
        }
        return vectorFloat == nil ? nil : .floatingPiece
    }

    /// **What a graph-editor drag is editing**, from the channels it carries: one subject's pose, or
    /// nothing this mechanism draws.
    ///
    /// Nil for a grade, for a mix of a grade and a pose (the grade changes what every band holds), and
    /// for an **animation group's** channel, which moves part of a cel — a band holds the whole cel, so
    /// re-posing it would carry the drawings the group leaves behind. Those drags keep the live pair.
    func graphBandEdit(target: KeyframeTarget, parameterIDs: Set<String>) -> LiveTransformEdit? {
        guard case .layer(let id) = target else { return nil }
        var channels: Set<PoseChannelID> = []
        for parameterID in parameterIDs {
            guard let channel = PoseChannelID.resolve(parameterID: parameterID)?.channel else { return nil }
            channels.insert(channel)
        }
        guard channels.count == 1, let channel = channels.first else { return nil }
        switch channel {
        case .container: return .container(layerID: id)
        case .cel(.cel): return .cel(layerID: id)
        case .cel(.group): return nil
        }
    }

    /// **The leaves an edit moves at `frame`, as runs** — bottom-to-top, each an unbroken span of the
    /// frame's leaf order whose every leaf moves by one map, which is what `[RenderNode].cut(around:)`
    /// takes and what makes one Core Animation transform right for a whole band.
    ///
    /// - A transformation layer moves the pixel-holding leaves beneath it in its own container — a
    ///   folder's whole subtree included — and only where it poses at all (its eye open, a block at
    ///   the frame, not a Repeat, not an operand of a compositor node: `renderNodes`' own gates).
    ///   **One run, unless it is a Parallax layer**, which shares its pose out per item beneath it, so
    ///   each item is a run of its own. Within an item the delta is one map whatever else poses its
    ///   leaves: a pose composes inner-first, so the edited layer's change conjugates every leaf's map
    ///   the same way.
    /// - A cel's pose channel moves that one leaf.
    ///
    /// A pixel-less leaf is never in a run — a grade or a flat colour is not posed, so it stays in the
    /// static band between two runs. Empty for a floating piece, and wherever nothing moves.
    ///
    /// **`tree` is an optimisation and not a second answer**, `sandwichKey(atFrame:…)`'s own: the
    /// canvas has already derived this frame's tree when it asks, and omitting it derives the same one.
    func liveTransformRuns(_ edit: LiveTransformEdit, atFrame frame: Int, tree: [RenderNode]? = nil) -> [[Int]] {
        let order = (tree ?? renderTree(atFrame: frame)).leafLayerIndices
        // The run each moving leaf belongs to, by a key that is the same for leaves that move as one.
        var keyOf: [Int: Int] = [:]
        switch edit {
        case .floatingPiece:
            return []
        case .cel(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }), layers[index].kind.holdsPixels
            else { return [] }
            keyOf[index] = 0
        case .container(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }),
                  let pose = layers[index].layerTransform, pose.mode != .repeat,
                  layers[index].isVisible, activeCelIndex(inLayer: index, atFrame: frame) != nil
            else { return [] }
            let container = resolvedContainer(ofLayer: index)
            guard container.flatMap({ id in folders.first { $0.id == id } })?.isCompositorNode != true
            else { return [] }
            let entries = containerEntries(inContainer: container)
            guard let position = entries.firstIndex(where: {
                if case .layer(let at) = $0 { return at == index }
                return false
            }) else { return [] }
            for (rank, entry) in entries[(position + 1)...].enumerated() {
                let key = pose.mode == .parallax ? rank : 0
                switch entry {
                case .layer(let at):
                    keyOf[at] = key
                case .folder(let folder):
                    for at in descendantLayerIndices(ofFolder: folder.id) { keyOf[at] = key }
                }
            }
            keyOf = keyOf.filter { layers[$0.key].kind.holdsPixels }
        }
        var runs: [[Int]] = []
        var openKey: Int?
        for leaf in order {
            guard let key = keyOf[leaf] else {
                openKey = nil
                continue
            }
            if key == openKey {
                runs[runs.count - 1].append(leaf)
            } else {
                runs.append([leaf])
                openKey = key
            }
        }
        return runs
    }

    /// **The map each run's ink is shown through at `frame`**, one per run, read off its first leaf —
    /// the run's definition is that every leaf in it moves by one delta, so one leaf answers for all.
    ///
    /// A transformation layer's edit reads the container pose the walk carries to the leaf; a cel
    /// channel's reads `inkPose`, which composes the cel's own whole-drawing pose under it. Nil maps
    /// are the identity: a leaf at rest.
    func liveTransformMaps(_ edit: LiveTransformEdit, runs: [[Int]], atFrame frame: Int) -> [PoseMap] {
        let walk = renderTreeAndPoses(atFrame: frame)
        return runs.map { run in
            guard let leaf = run.first else { return .identity }
            switch edit {
            case .container, .floatingPiece:
                return walk.poses[leaf] ?? .identity
            case .cel:
                return inkPose(ofLayerAt: leaf, showing: walk.frames[leaf] ?? frame,
                               inheriting: walk.poses[leaf]) ?? .identity
            }
        }
    }
}
