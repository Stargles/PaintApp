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
                             atCelLocalFrame frame: Int) -> [(TransformChannelID, PoseMap)] {
        guard !tracks.isEmpty else { return [] }
        var resolved: [(TransformChannelID, PoseMap)] = []
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
    /// **`inherited` is §4.4's container pose** — the transformation layer above this cel, or the
    /// folder holding it, resolved by `renderNodes` and handed down.
    ///
    /// **It reaches every element, which is what makes it a *container* pose rather than a channel.**
    /// `TransformChannelID` addresses a subset of one cel's own drawing and its members are asked by
    /// `isMoved(by:)`; a transformation layer addresses *whatever is under it* (§2.3), which at this
    /// level is the whole cel and cannot be otherwise — a stroke drawn a moment later has to join the
    /// move, exactly as `.cel`'s own doc argues one level in.
    ///
    /// **It composes last**, after the cel's own channels, because it moves the drawing rather than
    /// moving something within it — the reading `poseMappings`' ordering note already gives for a
    /// group channel under a cel channel, taken one level further out.
    static func posed(_ elements: [VectorElement],
                      through mappings: [(TransformChannelID, PoseMap)],
                      inheriting inherited: PoseMap? = nil) -> [VectorElement] {
        guard !mappings.isEmpty || inherited != nil else { return elements }
        return elements.map { element in
            guard let composed = composedPose(of: element, through: mappings, inheriting: inherited) else {
                return element
            }
            // **An element a keystone cannot carry is left where it rests**, which is
            // `applyToVectorFloat`'s own answer to the same question one tier over: a placed image and
            // a video store six numbers and a mirror bit, and `distortUnavailableReason` refuses the
            // float before an artist can key a projective pose over one. This is therefore the guard
            // and not a case anything walks into — and it is nil only on the projective arm, since
            // `posing(_:through: CGAffineTransform)` always answers.
            return VectorCanvas.posing(element, through: composed) ?? element
        }
    }

    /// **The one map an element is shown through, or nil when nothing here moves it** — the
    /// composition `posed(_:through:inheriting:)` applies, factored so that KEYFRAMES.md §6's bake
    /// writes the picture through the *same* membership rule and the same composition order rather
    /// than a second copy of either. The comment on `poseMappings` is the argument for the order.
    private static func composedPose(of element: VectorElement,
                                     through mappings: [(TransformChannelID, PoseMap)],
                                     inheriting inherited: PoseMap?) -> PoseMap? {
        composedPose(movedBy: element.isMoved(by:), through: mappings, inheriting: inherited)
    }

    /// `composedPose(of:)` for whatever `moves` says the channels claim — an element's membership, or
    /// the membership of ink not drawn yet (`inkPose`), which only the cel channel claims.
    private static func composedPose(movedBy moves: (TransformChannelID) -> Bool,
                                     through mappings: [(TransformChannelID, PoseMap)],
                                     inheriting inherited: PoseMap?) -> PoseMap? {
        var composed = PoseMap.identity
        var carried = false
        for (channel, map) in mappings where moves(channel) {
            composed = composed.concatenating(map)
            carried = true
        }
        if let inherited {
            composed = composed.concatenating(inherited)
            carried = true
        }
        guard carried, !composed.isIdentity else { return nil }
        return composed
    }

    /// **The display list `posed` would show, written to keep** — KEYFRAMES.md §6. The same
    /// composition per element as `posed(_:through:)`, committed through `VectorCanvas.baking` so it
    /// survives a save, and every element under a fresh id whether the pose moved it or not.
    ///
    /// **`inherited` is the part of a container pose the bake consumes, and Bake Animation passes
    /// none.** That bake consumes the cel's *own* channels — what it then clears from the cel — and a
    /// container pose above it (a folder's, a transformation layer's) is not consumed: it keeps posing
    /// the baked cels exactly as it posed the animated one, so the picture at every frame is
    /// unchanged by the bake, and new ink keeps landing where it is drawn, because every input surface
    /// reads that live pose (`inkPose(forLayerID:)`). Baking a transformation layer *is* consuming
    /// part of the container pose — its own share — and `CanvasManager.bakeLayer` hands exactly that
    /// share in; composed after the cel's channels, as `posed` composes it.
    static func baked(_ elements: [VectorElement],
                      through mappings: [(TransformChannelID, PoseMap)],
                      inheriting inherited: PoseMap? = nil) -> [VectorElement] {
        elements.map { element in
            guard let composed = composedPose(of: element, through: mappings, inheriting: inherited) else {
                return element.reidentified()
            }
            return (VectorCanvas.baking(element, through: composed) ?? element).reidentified()
        }
    }

    /// **The affine each element is *shown* through, kept rather than applied** — `posed(_:through:)`
    /// with the map handed back instead of the mapped element.
    ///
    /// This is what a Move at a posed frame needs and what stage 5 did not have, in three places at
    /// once: the lasso loop has to be pulled back through it before membership means anything
    /// (`LassoLoops`), the float's box has to be measured on ink mapped by it or the artist drags a
    /// box that is not around their drawing, and every nudge has to be conjugated by it so a screen
    /// delta lands as a screen delta. The old answer to all three was `activeVectorMoveTarget`
    /// refusing outright — silently, which is the defect the owner reported as *"try to select it in
    /// an inbetween, it does not let you"*.
    ///
    /// **Only the elements that are actually carried appear**, so an ordinary cel gets an empty
    /// dictionary and every consumer's fast path is one `isEmpty`.
    ///
    /// **A composed map that cannot be inverted is left out rather than carried**, and that is a
    /// reading rather than a guard. Every consumer inverts: the loop pull-back, the nudge's
    /// conjugation, the commit's outer map. A singular pose has collapsed that element to a line at
    /// this frame, so there is nothing on screen to lasso and nothing a delta could be measured
    /// against; leaving it at rest keeps the arithmetic finite and keeps the element out of the
    /// float. `TransformTrack.mapping` already drops a channel whose quad is degenerate, so this is
    /// reachable only through a *composition* of two channels that is singular without either being
    /// so.
    ///
    /// **`inherited` is §4.4's container pose, composed last exactly as `posed` composes it** — TODO
    /// (124). Without it every one of the three consumers above was blind to a transformation layer:
    /// a loop drawn round ink a Move layer had carried selected what was *stored* there, and the box
    /// stood where the ink would have been with no Move layer at all.
    static func poseMaps(_ elements: [VectorElement],
                         through mappings: [(TransformChannelID, PoseMap)],
                         inheriting inherited: PoseMap? = nil) -> [UUID: PoseMap] {
        guard !mappings.isEmpty || inherited != nil else { return [:] }
        var maps: [UUID: PoseMap] = [:]
        for element in elements {
            guard let composed = composedPose(of: element, through: mappings, inheriting: inherited),
                  composed.inverse != nil else { continue }
            maps[element.id] = composed
        }
        return maps
    }

    /// The same, for one cel of the document at an **absolute** frame — the conversion in one place,
    /// `resolvedPose`'s rule.
    ///
    /// `elements` is a parameter rather than read off the cel because the two callers want different
    /// lists: a lift asks against the **pre-split** display list to decide what the loop caught, and
    /// then against the **post-split** one to give the float the poses of the pieces it is actually
    /// carrying. A cut mints fresh ids, so a dictionary built before the split cannot answer for the
    /// halves — but `piece(of:)` copies the parent whole and `splitForLassoMove` carries a fill's
    /// group onto both halves, so a map built after it can.
    func celPoseMaps(_ elements: [VectorElement], layerID: UUID, celID: UUID,
                     atFrame frame: Int) -> [UUID: PoseMap] {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return [:] }
        let cel = layers[at.layer].cels[at.cel]
        return Self.poseMaps(elements,
                             through: Self.poseMappings(cel.transformTracks,
                                                        atCelLocalFrame: frame - cel.startFrame),
                             inheriting: containerPose(ofLayerAt: at.layer, atFrame: frame))
    }

    /// **§4.4's container pose for one layer at a document frame** — the product of every
    /// transformation layer and posed folder above it, exactly the map `renderNodes` hands that leaf,
    /// or nil where none reaches it. Read off the render walk rather than recomputed, so input cannot
    /// disagree with the picture.
    func containerPose(ofLayerAt index: Int, atFrame frame: Int) -> PoseMap? {
        layerPoses(atFrame: frame)[index]
    }

    /// **The map a mark made on this layer now is shown through** — TODO (124): *"Make it so the
    /// stroke the user lays down is properly transformed so whatever they draw accurately reflects
    /// the position the stroke gets set in."*
    ///
    /// Ink is stored in the layer's own space and the canvas shows it through its cel's channels and
    /// then the transformation layers above it (`posed(_:through:inheriting:)`), so a mark landed
    /// where the pen was is shown somewhere else by exactly this map. Every input surface that writes
    /// into a layer therefore takes the artist's canvas point through its **inverse** first, and
    /// shows its live preview through the map itself — `StrokeCanvasView`'s pose space, a smart
    /// shape's commit, a fill's seed and a text box's placement. One answer, so no two of them can
    /// disagree about where the layer is.
    ///
    /// It is the composition `posed` gives an element no group claims: the cel channel, then the
    /// container pose — at the frame the layer is *showing*, so under a Repeat it is the source
    /// frame's. **Nil for an in-between**, which `derivedCelContent` draws where its cel drew it
    /// whatever poses it, and nil wherever the composition is the identity, which is every layer of
    /// every document that has never been posed.
    func inkPose(forLayerID id: UUID) -> PoseMap? {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        let walk = renderTreeAndPoses(atFrame: currentFrame)
        return inkPose(ofLayerAt: index, showing: walk.frames[index] ?? currentFrame,
                       inheriting: walk.poses[index])
    }

    /// **A path the artist made on the canvas, in the layer's own space** — `inLayerSpace`'s answer for
    /// a loop: pulled back through the inverse of the pose the layer is shown through, so whatever
    /// is cut, cleared or filled inside it in the layer's pixels is what the artist drew round. The
    /// path itself where nothing poses the layer, and where the pose cannot be inverted (a layer
    /// collapsed to a line, which shows nothing to draw round).
    func layerSpacePath(_ canvasPath: CGPath, forLayerID id: UUID) -> CGPath {
        inkPose(forLayerID: id)?.inverse?.mapped(canvasPath) ?? canvasPath
    }

    /// **Geometry the artist made in canvas points, written into a layer the canvas shows through
    /// `pose`** — mapped through the pose's inverse, so the layer's render puts it back exactly where
    /// it was made. The element itself where nothing poses the layer; nil only where a keystone
    /// cannot carry the kind (`VectorCanvas.mapping(_:through:)`).
    static func inLayerSpace(_ element: VectorElement, shownThrough pose: PoseMap?) -> VectorElement? {
        guard let inverse = pose?.inverse else { return element }
        return VectorCanvas.mapping(element, through: inverse)
    }

    /// **A placed picture, clip or screen the artist put down in canvas points, written where layer
    /// `index` will show it** — `inLayerSpace` through the pose that layer is shown through, so a picture
    /// dragged out, pasted or imported under a transformation layer is *shown* where it was put and not a
    /// pose away (TODO (149)'s follow-up, the (124) defect class reached by another input).
    ///
    /// **Never nil, where `inLayerSpace` can be**: a keystone cannot carry a placed rectangle
    /// (`VectorCanvas.mapping(_:through:)`), and the render leaves one a keystone poses where it rests
    /// (`posed(_:through:inheriting:)`) — so under a keystone it is stored as put, which is where it is
    /// shown. Every other pose is an affine, and the element is carried through its inverse.
    func placedInLayerSpace(_ element: VectorElement, onLayerAt index: Int) -> VectorElement {
        Self.inLayerSpace(element, shownThrough: inkPose(forLayerID: layers[index].id)) ?? element
    }

    /// `inkPose(forLayerID:)` from a render walk the caller already holds — `frame` is the frame the
    /// layer is showing and `container` its container pose, both read off that walk — so a caller
    /// asking for every layer at once pays one walk rather than one per layer.
    func inkPose(ofLayerAt index: Int, showing frame: Int, inheriting container: PoseMap?) -> PoseMap? {
        var mappings: [(TransformChannelID, PoseMap)] = []
        if let celIndex = activeCelIndex(inLayer: index, atFrame: frame) {
            let cel = layers[index].cels[celIndex]
            guard cel.interpolation == nil else { return nil }
            mappings = Self.poseMappings(cel.transformTracks, atCelLocalFrame: frame - cel.startFrame)
        }
        return Self.composedPose(movedBy: { $0 == .cel }, through: mappings, inheriting: container)
    }

    /// `elements` with each one carried by its own pose — `posed(_:through:)`'s answer, addressed by
    /// id instead of by channel. What the Move box is measured on at a posed frame, and what the
    /// float's latched bitmap is rendered from.
    static func posed(_ elements: [VectorElement],
                      by poses: [UUID: PoseMap]) -> [VectorElement] {
        guard !poses.isEmpty else { return elements }
        return elements.map { element in
            guard let pose = poses[element.id], !pose.isIdentity else { return element }
            return VectorCanvas.posing(element, through: pose) ?? element
        }
    }

    /// **A delta the artist made in the space they are looking at, expressed in the space the ink is
    /// stored in** — `P · D · P⁻¹`, the conjugation that makes a nudge on a posed cel land where the
    /// finger went.
    ///
    /// Rest geometry `r` is shown at `r·P`. Dropping it at `r·P·D` means storing `r' = r·P·D·P⁻¹`,
    /// because `r'·P = r·P·D`. With no pose it is `D` unchanged, which is why an unkeyframed document
    /// takes exactly the map it always did.
    ///
    /// **It answers a `PoseMap` because the pose can now be a keystone (stage 5b), and an affine
    /// delta conjugated by a keystone is not affine.** The affine-by-affine case still composes
    /// through `CGAffineTransform` — `PoseMap.concatenating`'s invariant — so a nudge on an
    /// affinely-posed cel is bit-for-bit the nudge it was.
    static func restDelta(_ delta: CGAffineTransform, pose: PoseMap?) -> PoseMap {
        guard let pose, !pose.isIdentity, let inverse = pose.inverse else { return PoseMap(delta) }
        return pose.concatenating(PoseMap(delta)).concatenating(inverse)
    }

    /// The same conjugation for a **projective** delta — a lasso Distort at a posed frame.
    ///
    /// `P·D·P⁻¹` is the same expression with the same argument: the box, the finger and the latched
    /// bitmap are all in the posed space and `vector.elements` is at rest, so a screen delta has to be
    /// pulled back through the pose or the piece moves twice. Conjugating a homography by anything is
    /// a homography, so nothing about the shape of the answer changes — which is why this is an
    /// overload rather than a second idea. The two bodies are now identical and the overload is kept
    /// only so a caller holding a `Homography` need not wrap it at the call site.
    static func restDelta(_ delta: Homography, pose: PoseMap?) -> PoseMap {
        guard let pose, !pose.isIdentity, let inverse = pose.inverse else { return PoseMap(delta) }
        return pose.concatenating(PoseMap(delta)).concatenating(inverse)
    }

    /// **The loop as drawn, plus the loop as each posed element has to be asked about it.**
    ///
    /// One `CGPath` per *distinct* pose rather than one per element — a cel channel carries every
    /// element through the same map, so the common posed cel maps the loop once however much ink is
    /// on it, and `LassoLoops` memoizes its bounding boxes on the same object identity.
    static func lassoLoops(_ loop: CGPath, posedBy poses: [UUID: PoseMap], only: Set<UUID>? = nil) -> LassoLoops {
        guard !poses.isEmpty else { return LassoLoops(loop, only: only) }
        var byMap: [[CGFloat]: CGPath] = [:]
        var perElement: [UUID: CGPath] = [:]
        for (id, pose) in poses {
            // **`PoseMap.encoded`, so the memo distinguishes a keystone from its own affine part.**
            // Six numbers for an affine and nine for a homography, and the demotion invariant says one
            // map never has both spellings — so two genuinely different pull-backs cannot collide on
            // one entry, which is `RENDER.md` §3.8's size-keyed memo trap asked of this one.
            let key = pose.encoded
            if let cached = byMap[key] {
                perElement[id] = cached
                continue
            }
            // **A projective loop is flattened by `PoseMap.mapped`**, since the projective image of a
            // cubic is not a cubic. A lasso loop is already a polyline the finger drew, so nothing is
            // lost; the flattening matters for the memo's other callers, not for this one.
            guard let inverse = pose.inverse, let pulled = inverse.mapped(loop) else { continue }
            byMap[key] = pulled
            perElement[id] = pulled
        }
        return LassoLoops(loop, perElement: perElement, only: only)
    }

    /// **What a selection catches, as loops** — the one door every consumer of a selection reads it
    /// through: Move and Duplicate, Recolour, Size, Opacity, Apply Brush, Clear, To New Layer and the
    /// animation-group edits. The selection's canvas-space path in the cel's local space and normalized
    /// — both preconditions `VectorCanvas.splitForLassoMove` states, and neither is optional: stored
    /// geometry is local, so an unmapped loop is correct on an untransformed layer and silently wrong
    /// on every layer Move has already touched; and Core Graphics leaves `intersection`/`subtracting`
    /// **undefined** on the self-intersecting path a lasso becomes the moment the artist loops back
    /// over their own line — and then pulled back per element through the poses the cel is shown
    /// under, with a Tap selection's loops answering for its tapped elements (`Selection.elements`).
    static func lassoLoops(of selection: Selection, in vector: VectorCanvas,
                           posedBy poses: [UUID: PoseMap]) -> LassoLoops {
        let drawn = vector.localPath(fromCanvas: selection.path).normalized(using: VectorCanvas.lassoFillRule)
        return lassoLoops(drawn, posedBy: poses, only: selection.elements)
    }

    /// **The affine the channels applied *after* `channel` carry its members through at `frame`.**
    ///
    /// `posed(_:through:)` composes groups first and the cel last — a group moves *within* the drawing
    /// and the cel moves the drawing — so a group's members are shown at `rest·G·C` and everything
    /// else at `rest·C`. A Move at a posed frame is a delta `D` in the space the artist is looking at,
    /// which is *after* `C`, so keying it onto a channel means conjugating: the cel channel takes
    /// `C·D` and a group takes `G·C·D·C⁻¹`, and both are `M·O·D·O⁻¹` for this function's `O`.
    ///
    /// The container pose (`containerPose(ofLayerAt:atFrame:)`) is outside both and is composed last,
    /// as `posed` composes it. So it is the identity for `.cel` on a layer no transformation layer
    /// reaches, and the cel channel for a group there — on a document nobody has keyframed or posed
    /// the whole expression reduces to `D` and the commit is byte-for-byte what it was.
    func outerPoseMap(layerID: UUID, celID: UUID, channel: TransformChannelID,
                      atFrame frame: Int) -> PoseMap {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return .identity }
        let container = containerPose(ofLayerAt: at.layer, atFrame: frame) ?? .identity
        switch channel {
        case .cel: return container
        case .group:
            let cel = layers[at.layer].cels[at.cel]
            let celMap = cel.transformTracks[TransformChannelID.cel.id]?
                .mapping(atCelLocalFrame: frame - cel.startFrame) ?? .identity
            return celMap.concatenating(container)
        }
    }

    /// The affine one channel maps its members through at an absolute frame, or the identity when it
    /// has no track — the loose reading every commit-side caller wants.
    func resolvedPoseMap(layerID: UUID, celID: UUID, channel: TransformChannelID,
                         atFrame frame: Int) -> PoseMap {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return .identity }
        let cel = layers[at.layer].cels[at.cel]
        return cel.transformTracks[channel.id]?.mapping(atCelLocalFrame: frame - cel.startFrame)
            ?? .identity
    }

    /// `t` inverted, or nil for a singular or non-finite one. One spelling, because three call sites
    /// on this path each need it and a second one would be a second threshold.
    static func invertedAffine(_ t: CGAffineTransform) -> CGAffineTransform? {
        let determinant = t.a * t.d - t.b * t.c
        guard determinant.isFinite, abs(determinant) > Quad.epsilon else { return nil }
        let inverse = t.inverted()
        guard inverse.a.isFinite, inverse.b.isFinite, inverse.c.isFinite,
              inverse.d.isFinite, inverse.tx.isFinite, inverse.ty.isFinite else { return nil }
        return inverse
    }

    /// The pose one channel of one cel resolves to at an **absolute** document frame — the
    /// cel-local conversion in one place so no caller subtracts `startFrame` by hand.
    func resolvedPose(layerID: UUID, celID: UUID, channel: TransformChannelID,
                      atFrame frame: Int) -> PoseQuad? {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return nil }
        let cel = layers[at.layer].cels[at.cel]
        return cel.transformTracks[channel.id]?.pose(atCelLocalFrame: frame - cel.startFrame)
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
    ///
    /// ## `inherited` — §4.4's transformation layer, and the half of it this derivation owns
    ///
    /// A container pose arrives here already resolved (`CanvasManager.renderNodes` accumulated it
    /// down the tree) and is composed onto every element, after the cel's own channels.
    ///
    /// **It covers the *vector* tier and only the vector tier, which is §2.12 rather than a
    /// shortfall.** `PixelOps.rasterizeUncached` lets a derivation replace `cel.vector`'s image and
    /// draws the baked, raster and fill tiers beside it — so this arm re-poses vector objects (§2.3's
    /// *"crisp lines, not a bitmap magnify"*) and `PixelOps.FrozenCel.pose` resamples the raster
    /// tiers through the CTM. Two currencies, which is exactly the ruling: *"a raster layer softens
    /// under a push-in while the vector layer beside it stays sharp"*. **So a cel with no vector tier
    /// answers nil here and is still posed** — by the other half.
    func posedCelContent(for cel: Cel, atFrame frame: Int,
                         inheriting inherited: PoseMap? = nil) -> DerivedCelContent? {
        let container = inherited.flatMap { $0.isIdentity ? nil : $0 }
        guard !cel.transformTracks.isEmpty || container != nil,
              let vector = cel.vector, let canvasSize else { return nil }
        let mappings = Self.poseMappings(cel.transformTracks, atCelLocalFrame: frame - cel.startFrame)
        guard !mappings.isEmpty || container != nil else { return nil }

        // Resolved **now**, on the main actor, into values the closure captures — `DerivedCelContent`'s
        // purity contract. `FrameRecipe.resolveSources` calls `render` from `PixelOps.parallelMap`'s
        // workers, and `[VectorElement]` is copy-on-write, so this is a retain rather than a copy.
        let suppressed = vector.suppressedElementIDs
        let elements = suppressed.isEmpty ? vector.elements
                                          : vector.elements.filter { !suppressed.contains($0.id) }
        let carried = vector.transform
        // `committedVersion`: a posed stream cel must not mint a fresh identity — and with it a
        // fresh bake key — per live frame. See `VectorCanvas.committedVersion`.
        let version = vector.committedVersion

        let identity = PosedCelIdentity(
            celID: cel.id,
            canvas: ObjectIdentifier(vector),
            vectorVersion: version,
            suppressed: suppressed.map(\.uuidString).sorted(),
            carried: [carried.a, carried.b, carried.c, carried.d, carried.tx, carried.ty],
            maps: Dictionary(uniqueKeysWithValues: mappings.map { ($0.0.id, $0.1.encoded) }),
            // **§4.5, reached from the transformation layer's door.** The container pose is an input
            // `render` reads and nothing else in this identity carries it: two frames of a cel with
            // *no channels of its own*, moved only by a transform layer above it, are identical in
            // every other field — so without this the flatten memo hands the first frame's pixels to
            // every frame of the move, and `SandwichKey` rebuilds the composite dutifully from it.
            inherited: container.map(\.encoded),
            canvasWidth: Int(canvasSize.width.rounded()),
            canvasHeight: Int(canvasSize.height.rounded()))

        return DerivedCelContent(identity: AnyHashable(identity)) { quality in
            // Built inside the thunk, on whatever queue resolved it, from values nothing else can
            // reach — `VectorCanvas.Frozen.render`'s detached-canvas branch, which is the atomicity
            // guarantee this seam is for. The carried transform rides along so a document written by
            // a build that still stored one is posed rather than un-posed.
            //
            // **`posed` is inside the thunk and not beside the identity, which is the one place this
            // derivation differs in shape from interpolation's.** That one resolves its references
            // eagerly because it must — they are read off `layers`, which a worker thread may not
            // touch — and the resolve is a retain per reference. This one's eager work would be a
            // walk of every element and every sample in the cel, and it depends on nothing but the
            // two values captured here, so hoisting it out of the thunk would pay that walk on
            // **every SwiftUI pass** of a posed document and throw it away on the memo hit that
            // follows. `livePreview` asks on every pass, which is what makes the difference visible.
            VectorCanvas(size: canvasSize,
                         elements: Self.posed(elements, through: mappings, inheriting: container),
                         transform: carried).render(quality: quality)
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
    /// §4.4's container pose — `PoseMap.encoded`, so six numbers for an affine and nine for a
    /// keystone, or nil. **An array rather than a second dictionary**, and
    /// that is about `FrameBakeKey` rather than about this type: `BakeKeyEncoder.derived(_:)` falls
    /// back to `String(reflecting:)` for an identity that is not `BakeKeyEncodable`, and a dictionary
    /// prints in per-process hash order — which is safe in the direction it fails (two descriptions
    /// for one value is a re-bake, never one description for two) but is a cost with no reason to
    /// pay it here, where there is exactly one pose.
    let inherited: [CGFloat]?
    let canvasWidth: Int
    let canvasHeight: Int
}
