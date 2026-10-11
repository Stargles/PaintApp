import Foundation

/// **Which picture the live canvas shows while the compositor is drawing it** — the choice
/// `CanvasView.Coordinator.updateSandwich` makes on every pass, as a value.
///
/// It lives here rather than nested in the coordinator for `SandwichKey`'s reason: `CanvasView.swift`
/// is not compiled into `PaintSoftwareUITests`, so a decision made inline there is one no logic test
/// can check, and this one decides what the artist sees after every edit they make.
///
/// Published on `canvas.host`'s accessibility label by raw value (`publishCanvasState`), because
/// none of it is otherwise visible to an XCUITest.
enum SandwichPresentation: String {

    /// Core Animation's flat row of hosts, unblanked — the document needs no compositor.
    case disengaged = "off"

    /// The baked frame (RENDER.md §3.6) in the lower view, every host blanked.
    case rest

    /// **An edit's live pair, shown until its bake lands** — TODO (145).
    ///
    /// The rest picture is the bake, and a bake is a whole-frame composite on a `.utility` queue:
    /// MEASURED at 334–365 ms a frame on the owner's iPad for one vector layer under two
    /// transformation layers (`bakeComposite` in recording-20261001-002226, 2026-10-01), plus the
    /// write. With nothing but the bake at rest, every edit that is not a stroke — an undo above all
    /// — stands on the previous picture for that long: the owner's *"the undos are latent. I'd
    /// estimate around 400ms"*. A stroke does not, because trap 2 keeps it on the mid-stroke pair
    /// until its bake lands; this is the same picture for the same wait, reached by an edit.
    ///
    /// The pair is the two halves plus the active layer's own picture, minted together off the main
    /// thread for one key (`startSandwichRebuild`). Two of the three are cheap — everything strictly
    /// below the active layer and everything strictly above, MEASURED at 14–23 ms on the same iPad
    /// (`sandwichComposite`) — so the edit is on screen a rebuild after it lands rather than a bake.
    /// Where a layer above the active one blends or grades, the halves are one picture of everything
    /// but the active layer and its host draws over it (`LivePairCut.overHost`, TODO (160)).
    ///
    /// **Fast, then exact — on every document** (owner, 2026-10-01, TODO (125)). Where the pair is
    /// not the picture it is §5.2's near picture: the active layer drawn *plain* — its host draws its
    /// own ink, with no blend mode, grade or mask — over a blended or graded layer above it rather
    /// than under it. The owner chose that over waiting: *"for the fast one it can be just the layer
    /// without any effects added, no need to try and approximate"*, and the bake replaces it when it
    /// lands. A layer above that blends is the same class of approximation as the active layer's own
    /// mode, so it takes the same rule rather than a wait of its own.
    ///
    /// **A stream is the other thing the pair is for, and there the bake never replaces it**
    /// (TODO (112), TODO (162)). A stream is reference (STREAM.md §2.13): no bake contains it, and a
    /// frame reaches the screen through its layer's host, never through a composite
    /// (`ScreenStreamCoordinator`). So on a canvas the compositor draws, the host has to be the middle
    /// of the pair for as long as a stream is on the frame — the pair is the picture, not a picture to
    /// wait out. The owner's *"a live stream does not require to be rendered because it is only used
    /// as reference"* is why this has no exact picture to come to: the stream is drawn plain, and so
    /// is every layer from the stream to the active one.
    case live

    /// **A transform edit's bands** — TODO (125): the frame cut around the leaves the edit moves,
    /// every band composited once, and each moving band re-posed per update by a Core Animation
    /// transform (`LiveTransformEdit`). Every host is blanked: nothing of the frame draws itself.
    ///
    /// Held after the finger lifts until a picture of the result lands — the bake, or the live pair
    /// minted for it — trap 2's rule for a stroke, reached by a move.
    case moving

    /// The live pair under the pen: a stroke is in progress, or has lifted and its bake has not
    /// landed yet (trap 2). **Drawn exactly as `.live` is**, and distinct from it for the one reader
    /// that cares why the active host is drawing itself — `midStrokeEntryCount`, which counts
    /// strokes.
    case midStroke = "stroke"

    /// Whether the active layer's host draws itself between the two halves — both live
    /// presentations — rather than being blanked under a picture that already contains it.
    var activeHostDrawsItself: Bool { self == .live || self == .midStroke }

    /// **The next presentation, from the current one and what the canvas holds.**
    ///
    /// - A stroke under the pen is drawn live, whatever else is true.
    /// - A transform edit under the finger is drawn by its bands once bands for its cut are in hand,
    ///   and kept on them when they are merely stale — a take flips the frame under them, and the
    ///   rebuild that catches up is already on its way. Stale bands are never *entered*: the previous
    ///   gesture's are not this one's.
    /// - Otherwise a bake for this key is the whole truth, and wins.
    /// - Otherwise a transform edit's bands stay up, after the finger has lifted, while they are of
    ///   this frame — until the bake or the live pair minted for the result replaces them.
    /// - **A stream or a floating piece on the frame keeps the canvas on the pair** whatever the bake
    ///   says: no bake contains either, so it is never the picture to wait for. The pair is shown once it is
    ///   current, kept while it is stale, and a lifted stroke leaves `.midStroke` for `.live` the
    ///   moment its pair is current rather than when a bake lands. A pair cut around other hosts at
    ///   this frame (`.regrouped`) is kept on screen until the new cut's pair lands.
    /// - Otherwise a lifted stroke stays on its pair while the pair is cut here (trap 2).
    /// - Otherwise an edit's pair is shown if it is for this key, and **kept** if it is merely stale —
    ///   one edit behind, at most, and that edit's rebuild is already on its way. Falling back to the
    ///   bake there would show an *older* picture than the one leaving the screen: after two quick
    ///   undos the second would put the first undo's stroke back for a moment — the shape of the
    ///   flash the owner reported, reached by another door.
    /// - A stale pair is never *entered*, from the rest picture: it is no newer than the bake the
    ///   canvas is already standing on, so swapping one stale picture for another is a flicker for
    ///   nothing.
    static func next(from current: SandwichPresentation, live: Live, held: Held) -> SandwichPresentation {
        if live.stroke { return .midStroke }
        if live.transformEdit {
            switch held.livePair {
            case .current: return .moving
            case .stale: return current == .moving ? .moving : .rest
            case .none, .regrouped: return .rest
            }
        }
        if held.bakeIsCurrent, !live.drawnByHostsAlone { return .rest }
        if current == .moving, held.bandsOfThisFrame { return .moving }
        switch held.livePair {
        case .none:
            return .rest
        case .regrouped:
            return live.stream && current.activeHostDrawsItself ? current : .rest
        case .stale, .current:
            if current == .midStroke, !(live.drawnByHostsAlone && held.livePair == .current) { return .midStroke }
            return held.livePair == .current || current == .live ? .live : .rest
        }
    }

    /// **What is producing a picture right now** — each of these holds the canvas on a picture of its
    /// own, and `next` reads them as one fact.
    struct Live: Equatable {
        /// A stroke is under the pen.
        var stroke = false
        /// A transform edit is under a finger.
        var transformEdit = false
        /// A stream is on the frame — drawn by its host, which only a live presentation has
        /// (TODO (112)); no bake contains it, so the bake is never the picture (TODO (162)).
        var stream = false
        /// **A floating piece is up** — a lasso's, a folder's or a raster Move's, drawn by the hosts
        /// that carry it (`CanvasManager.floatHostLayerIndices`) in the middle of the pair (TODO
        /// (160)). The bake of the lifted state has a hole where the piece is, so, as for a stream,
        /// the bake is never the picture while it floats.
        var float = false

        /// Something on the frame reaches the screen only through its own host — what keeps the canvas
        /// on the live pair whatever the bake says.
        var drawnByHostsAlone: Bool { stream || float }
    }

    /// **The pictures the canvas has in hand** to choose between.
    struct Held: Equatable {
        /// The bake for this key has landed.
        var bakeIsCurrent: Bool
        /// How the live pair the canvas is holding relates to this key and cut.
        var livePair: LivePairFit
        /// A transform edit's bands of this frame are held — what keeps them up after the finger has
        /// lifted, until the bake or the pair minted for the result replaces them.
        var bandsOfThisFrame = false
    }
}

/// **How the live pair the canvas is holding relates to the key it is on.**
enum LivePairFit: Equatable {

    /// No pair, or one cut somewhere else. A pair cut at another active layer would draw that layer
    /// twice — once in a half and once by its own host — and a pair from another frame would put the
    /// other layers' ink from that frame beside the active layer's from this one; both are worse than
    /// the previous frame's bake, which is RENDER.md §2.10's picture for a frame not yet baked.
    case none

    /// **Cut for this frame around other hosts** — a layer switch, or a stream shown or hidden,
    /// moved the cut while the content stood still. The held pair is still a coherent picture of this
    /// frame (every host it names draws itself, every other layer is in a half), so a stream on the
    /// frame — which no bake contains, so the bake is not a picture to fall back on — keeps it on
    /// screen while the pair for the new cut is minted. Everything else treats it as `.none`: the bake is the picture on hand.
    case regrouped

    /// Cut here, minted for an older key. It differs from the current picture by exactly the edits
    /// made since, and each of them has moved the key and so is on its way.
    case stale

    /// Minted for this key. `SandwichKey`'s sufficiency argument makes that byte-identical to a pair
    /// minted now, at whatever frame.
    case current

    /// `held` is the key and cut of the picture the canvas has, nil when it has none.
    ///
    /// **A picture fits only a cut of its own kind.** Two cuts around the host fit whatever frame
    /// each was made at — equal keys are byte-identical halves — but a transform edit's bands are
    /// not a pair and a pair is not bands, whatever the key says: the middle of one is a host and of
    /// the other a picture, and showing either as the other blanks or doubles a layer. Bands fit
    /// only bands around the same runs, which is what makes them one edit's.
    init(held: (key: SandwichKey, cut: LivePairCut)?, key: SandwichKey, cut: LivePairCut?) {
        guard let held, let cut, held.cut.isSameKind(as: cut) else { self = .none; return }
        if held.key == key {
            self = .current
        } else if held.cut == cut {
            self = .stale
        } else if let frame = held.cut.hostFrame, frame == cut.hostFrame {
            self = .regrouped
        } else {
            self = .none
        }
    }
}

/// **Where a live picture is cut** — around the hosts that draw, or around a transform edit's runs.
///
/// By id rather than by index, because an index names a different layer after an insert or a delete
/// below it, and a pair cut at the old one would then be drawn around the wrong host.
enum LivePairCut: Equatable {

    /// A stroke's pair, or an edit's, a stream's or a floating piece's: the layers
    /// `CanvasManager.liveHostRun` names — the active layer, with every live stream and every host
    /// carrying a floating piece, and what lies between — drawn by their own hosts between two
    /// halves. **With its frame**, because the hosts draw the frame the canvas is on and must not
    /// stand between halves from another.
    ///
    /// The cut wherever the layers above those hosts composite onto transparency as they do onto the
    /// picture beneath (`CanvasManager.liveHostsSitBetweenTheHalves`), so the hosts are drawn at their
    /// true place in the stack.
    case aroundHost(frame: Int, layerIDs: [UUID])

    /// **The same hosts drawn over one picture of everything else** — TODO (160). Where something
    /// above the hosts blends or grades (an effect, the drawing Guide among them), the half above
    /// composited onto transparency would blend against nothing and grade nothing, so a guide above
    /// a stroke or a lasso move vanished for its length. Here the rest of the frame is composited in
    /// one pass, exactly, with the hosts' leaves left out (`[RenderNode].hidingLeaves`), and the hosts
    /// draw over it: what the owner ruled, *"rendering only the brush stroke without the compositing,
    /// and once the stroke ends, it joins down"*. The join is the bake landing, as for every pair.
    case overHost(frame: Int, layerIDs: [UUID])

    /// A transform edit's bands, around the runs it moves (`CanvasManager.liveTransformRuns`).
    /// **Without a frame**: every band is a picture of one moment, so bands from the previous frame
    /// of a take are one coherent picture a frame stale — §2.10's previous picture — not a mixture.
    case aroundRuns([[UUID]])

    /// The frame a cut around hosts was made at, or nil for a transform edit's bands.
    var hostFrame: Int? {
        switch self {
        case .aroundHost(let frame, _), .overHost(let frame, _): return frame
        case .aroundRuns: return nil
        }
    }

    /// The layers whose hosts draw themselves in this cut's picture, or nil for a transform edit's
    /// bands, where none does.
    var hostLayerIDs: [UUID]? {
        switch self {
        case .aroundHost(_, let ids), .overHost(_, let ids): return ids
        case .aroundRuns: return nil
        }
    }

    /// Of one shape both — around hosts, or over them, at any frame — or around the same runs both.
    /// A pair cut one way is never shown as the other: the one's middle is between two halves, the
    /// other's over a picture that already holds what the first one's upper half does.
    func isSameKind(as other: LivePairCut) -> Bool {
        switch (self, other) {
        case (.aroundHost, .aroundHost), (.overHost, .overHost): return true
        case (.aroundRuns(let a), .aroundRuns(let b)): return a == b
        default: return false
        }
    }
}
