import CoreGraphics
import UIKit

/// **The transform channel** — KEYFRAMES.md build-order stage 5: where a cel's drawing is over the
/// frames that cel spans, keyed as poses and rendered by mapping ink rather than by resampling it.
///
/// **Why a `CanvasManager` extension rather than a type.** The same split `KeyframeControl` makes one
/// file over: everything that can be stated as a function of *values* is `static` here or on
/// `TransformTrack`, so the fast tier can reach it, and the view layer is left holding nothing but
/// which gesture happened. `Views/CanvasView.swift` and `Views/AnimationTimeline.swift` are not
/// compiled into `PaintSoftwareUITests`, so a rule written in either is pinned by nothing.
extension CanvasManager {

    // MARK: - The state a cel carries

    /// **Everything the transform channel stores on one cel, as one value** — the pose tracks and
    /// §2.27's held baselines. Read and written together for `KeyframeControl.KeyframeState`'s
    /// reason: one artist action touches both, so one undo step covers both by construction rather
    /// than by two careful closures.
    ///
    /// **There is no third field for "the stored pose", and that absence is a finding rather than an
    /// omission.** A value channel needs one — `Layer.effect` holds the number a slider writes when
    /// nothing is keyed — but a pose channel's stored base **is the cel's own geometry**: a Move with
    /// no keyframes anywhere bakes into `VectorCanvas.elements` exactly as it always has, and the
    /// pose that describes where that geometry sits relative to itself is the identity. So the pose
    /// channel's "current stored value" is always `PoseQuad(restingIn:)`, and the arm a value channel
    /// spends writing its base is spent here on the bake that already happens.
    struct CelPoseState: Equatable {
        var tracks: [String: TransformTrack] = [:]
        /// §2.27's *"the previous value is held"*, per channel id. Persisted, because the gap between
        /// keyframe A and keyframe B can span a save — lose it across a reopen and placing B writes
        /// two identical poses and produces no animation, with nothing on screen to explain it.
        var baselines: [String: PoseQuad] = [:]

        var isEmpty: Bool { tracks.isEmpty && baselines.isEmpty }
    }

    /// The pose state of one cel, or an empty one for a cel that is not in the document — every other
    /// reader on this path answers rather than trapping.
    func celPoseState(layerID: UUID, celID: UUID) -> CelPoseState {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return CelPoseState() }
        let cel = layers[at.layer].cels[at.cel]
        return CelPoseState(tracks: cel.transformTracks, baselines: cel.pendingPoseBaselines)
    }

    /// The one mutation every direction of every pose undo goes through. **Re-resolves by id on every
    /// call** rather than capturing an index, `applyKeyframeState`'s rule: a restack or a cel
    /// insertion between the edit and the undo moves an index and cannot move an id.
    func applyCelPoseState(_ state: CelPoseState, layerID: UUID, celID: UUID) {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return }
        layers[at.layer].cels[at.cel].transformTracks = state.tracks
        layers[at.layer].cels[at.cel].pendingPoseBaselines = state.baselines
    }

    // MARK: - Evaluation

    /// **The affine each channel maps its members through at a cel-local frame**, in the order they
    /// must be applied.
    ///
    /// **Group channels first, the cel channel last, and that ordering is the artist's model rather
    /// than an arbitrary tie-break.** A group moves *within* the drawing and the cel channel moves the
    /// drawing, so an element in a group under an animated cel is carried by its group and then by the
    /// cel — a character's arm swinging while the character walks. Affines do not commute, so the
    /// order has to be decided somewhere; deciding it here rather than in a dictionary walk is what
    /// keeps it from depending on Swift's per-process hash seed. Groups among themselves are ordered
    /// by id, which is arbitrary and *cannot matter*: an element carries at most one
    /// `animationGroupID`, so no two group channels ever reach the same element.
    ///
    /// Channels resolving to the identity are absent, not present-and-identity — see
    /// `TransformTrack.mapping(atCelLocalFrame:)` for why that distinction decides whether the cel has
    /// a derivation at all.
    static func poseMappings(_ tracks: [String: TransformTrack],
                             atCelLocalFrame frame: Int) -> [(TransformChannelID, CGAffineTransform)] {
        guard !tracks.isEmpty else { return [] }
        var resolved: [(TransformChannelID, CGAffineTransform)] = []
        for (id, track) in tracks {
            guard let channel = TransformChannelID(id: id),
                  let map = track.mapping(atCelLocalFrame: frame) else { continue }
            resolved.append((channel, map))
        }
        return resolved.sorted { lhs, rhs in
            switch (lhs.0, rhs.0) {
            case (.cel, .cel): return false
            case (.cel, .group): return false
            case (.group, .cel): return true
            case (.group(let a), .group(let b)): return a.uuidString < b.uuidString
            }
        }
    }

    /// **The display list a posed cel shows** — every element carried by whichever channels claim it.
    ///
    /// **Ink goes through `VectorCanvas.mapping(_:throughStretch:)`, and §8 is emphatic about which of
    /// the two per-frame mapped-stroke paths that is.** The other one,
    /// `InterpolationEvaluator.warped`, scales `result.size` by `thicknessFade` alone and never by an
    /// area root — right for a lattice warp, whose local scale varies per point, and wrong for a pose.
    /// This one computes `sqrt(abs(t.a * t.d - t.b * t.c))` into `stroke.size`, which is
    /// LASSO_MOVE.md §5.17's rule verbatim; and because every pose stage 5 can author is **affine**,
    /// `|det|` does not vary with position, so that single scalar **is** the per-dab local area root
    /// at every dab — exactly, not approximately. That is the whole of why stage 5 needs none of §4.2's
    /// rest-space dab bake.
    ///
    /// **The stretch arm rather than the similarity arm, for every pose including a pure translation.**
    /// `mapping(_:throughSimilarity:)` `assertionFailure`s on a map whose two axes scale differently,
    /// and a blended in-between of two similarity poses is only a similarity to floating point — so
    /// routing by "is this a similarity" would put a debug trap on a path the artist can reach by
    /// scrubbing. The two arms agree where they overlap (`sqrt(|det|) == hypot(t.a, t.b)` for a
    /// similarity, which is `applyToVectorFloat`'s own reduction argument), so there is nothing to
    /// choose between them but the trap.
    ///
    /// **The maps are composed before they are applied, not applied in turn.** Two `mapping` calls
    /// would walk and re-round every sample twice; one composed affine walks them once, and the width
    /// scale is identical either way because `sqrt(|det|)` is multiplicative.
    static func posed(_ elements: [VectorElement],
                      through mappings: [(TransformChannelID, CGAffineTransform)]) -> [VectorElement] {
        guard !mappings.isEmpty else { return elements }
        return elements.map { element in
            var composed = CGAffineTransform.identity
            var carried = false
            for (channel, map) in mappings where element.isMoved(by: channel) {
                composed = composed.concatenating(map)
                carried = true
            }
            guard carried, !composed.isIdentity else { return element }
            return VectorCanvas.posing(element, through: composed)
        }
    }

    /// The pose one channel of one cel resolves to at an **absolute** document frame — the
    /// cel-local conversion in one place so no caller subtracts `startFrame` by hand.
    func resolvedPose(layerID: UUID, celID: UUID, channel: TransformChannelID,
                      atFrame frame: Int) -> PoseQuad? {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return nil }
        let cel = layers[at.layer].cels[at.cel]
        return cel.transformTracks[channel.id]?.pose(atCelLocalFrame: frame - cel.startFrame)
    }

    /// **Whether this cel shows its ink anywhere other than where it stores it, at `frame`.** The
    /// predicate the Move tool's refusal asks — see `celPoseIsRestingAtFrame`.
    static func poseIsResting(_ tracks: [String: TransformTrack], atCelLocalFrame frame: Int) -> Bool {
        poseMappings(tracks, atCelLocalFrame: frame).isEmpty
    }

    // MARK: - The derivation

    /// **What a posed cel displays** — the `CelContentProvider` seam's second derivation source, beside
    /// interpolation's.
    ///
    /// **Returns nil on a field test before doing any work**, `derivedCelContent`'s contract: this is
    /// reached for every cel of every rasterize, including in documents that have never been
    /// keyframed, so the untouched path is one `isEmpty`.
    ///
    /// ## The identity, and the one place this stage departed from §8's prescription
    ///
    /// §8 says a pose derivation's identity *"must include the frame"*, against interpolation's, which
    /// deliberately omits it *"because interpolation does not read it and a spurious frame field would
    /// mint a second cache entry per frame of a held cel"*. **The premise is right and the conclusion
    /// is one step too coarse, and the code is what shows it.** What the identity owes is everything
    /// `render` *reads*, and this render reads the **resolved maps** — the frame is what it reads them
    /// *through*. Carrying the maps is therefore both sufficient and strictly tighter: two frames whose
    /// poses resolve equal are two frames with the same pixels, and a frame field on top of the maps
    /// would mint a second entry for each of them — which is the very cost §8's own parenthesis warns
    /// about, arriving by the other door. A cel held across a `step: 2` track, or across the constant
    /// hold past its last key, is exactly that case and is common rather than exotic.
    ///
    /// So the enumeration below is: the cel, its stored ink (`vectorVersion`, plus the object identity
    /// of the canvas for `LayerContentVersion`'s reason — a version counter is monotonic only within
    /// one object's lifetime and a reopened project rebuilds every canvas with its counter at zero),
    /// what is suppressed under a live float, the canvas's own carried transform, the canvas size, and
    /// the resolved maps. Drop any one of them and a stale image is served; `TransformChannelLogicTests`
    /// pins the maps by mutation, which is §4.5's trap in its exact form.
    func posedCelContent(for cel: Cel, atFrame frame: Int) -> DerivedCelContent? {
        guard !cel.transformTracks.isEmpty, let vector = cel.vector, let canvasSize else { return nil }
        let mappings = Self.poseMappings(cel.transformTracks, atCelLocalFrame: frame - cel.startFrame)
        guard !mappings.isEmpty else { return nil }

        // Resolved **now**, on the main actor, into values the closure captures — `DerivedCelContent`'s
        // purity contract. `FrameRecipe.resolveSources` calls `render` from `PixelOps.parallelMap`'s
        // workers, and `[VectorElement]` is copy-on-write, so this is a retain rather than a copy.
        let suppressed = vector.suppressedElementIDs
        let elements = suppressed.isEmpty ? vector.elements
                                          : vector.elements.filter { !suppressed.contains($0.id) }
        let carried = vector.transform
        let version = vector.version
        let posed = Self.posed(elements, through: mappings)

        let identity = PosedCelIdentity(
            celID: cel.id,
            canvas: ObjectIdentifier(vector),
            vectorVersion: version,
            suppressed: suppressed.map(\.uuidString).sorted(),
            carried: [carried.a, carried.b, carried.c, carried.d, carried.tx, carried.ty],
            maps: Dictionary(uniqueKeysWithValues: mappings.map {
                ($0.0.id, [$0.1.a, $0.1.b, $0.1.c, $0.1.d, $0.1.tx, $0.1.ty])
            }),
            canvasWidth: Int(canvasSize.width.rounded()),
            canvasHeight: Int(canvasSize.height.rounded()))

        return DerivedCelContent(identity: AnyHashable(identity)) { quality in
            // Built inside the thunk, on whatever queue resolved it, from values nothing else can
            // reach — `VectorCanvas.Frozen.render`'s detached-canvas branch, which is the atomicity
            // guarantee this seam is for. The carried transform rides along so a document written by
            // a build that still stored one is posed rather than un-posed.
            VectorCanvas(size: canvasSize, elements: posed, transform: carried).render(quality: quality)
        }
    }
}

/// The identity of one posed frame. See `CanvasManager.posedCelContent` for the enumeration and for
/// why the frame itself is not one of these fields.
///
/// A private type in this file for `InterpolatedCelIdentity`'s reason: `AnyHashable` compares unequal
/// across types, so two derivations can never collide on one cache entry however similar their fields
/// look.
private struct PosedCelIdentity: Hashable {
    let celID: UUID
    let canvas: ObjectIdentifier
    let vectorVersion: Int
    let suppressed: [String]
    let carried: [CGFloat]
    let maps: [String: [CGFloat]]
    let canvasWidth: Int
    let canvasHeight: Int
}
