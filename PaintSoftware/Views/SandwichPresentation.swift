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
    ///
    /// **Only where the pair is the picture** (`liveCutIsExact`). Elsewhere it is §5.2's near
    /// picture — the active layer's blend or grade gone to normal, a faded group faded twice — which
    /// a stroke may show while the pen is down, because lift snaps it back to the bake, and which an
    /// edit at rest must not trade the true picture for: there the previous bake is the right thing
    /// to stand on, stale but never wrong. That is EFFECT_BACKDROP.md's 2026-08-27 ruling — at rest
    /// the canvas is the exact composite, and the mid-stroke approximation is tolerable because
    /// stopping returns the artist to it.
    case live

    /// The live pair under the pen: a stroke is in progress, or has lifted and its bake has not
    /// landed yet (trap 2). **Drawn exactly as `.live` is**, and distinct from it for the one reader
    /// that cares why the active host is drawing itself — `midStrokeEntryCount`, which counts
    /// strokes.
    case midStroke = "stroke"

    /// Whether the active layer's host draws itself between the two halves — both live
    /// presentations — rather than being blanked under a picture that already contains it.
    var activeHostDrawsItself: Bool { self == .live || self == .midStroke }

    /// **The next presentation, from the current one and four facts about what the canvas holds.**
    ///
    /// - A stroke under the pen is drawn live, whatever else is true.
    /// - Otherwise a bake for this key is the whole truth, and wins.
    /// - Otherwise a lifted stroke stays on its pair while the pair is cut here (trap 2).
    /// - Otherwise an edit's pair is shown if it is for this key and is the picture
    ///   (`livePairIsExact`), and **kept** if it is merely stale — one edit behind, at most, and that
    ///   edit's rebuild is already on its way. Falling back to the bake there would show an *older*
    ///   picture than the one leaving the screen: after two quick undos the second would put the
    ///   first undo's stroke back for a moment — the shape of the flash the owner reported, reached
    ///   by another door.
    /// - A stale pair is never *entered*, from the rest picture: it is no newer than the bake the
    ///   canvas is already standing on, so swapping one stale picture for another is a flicker for
    ///   nothing.
    static func next(from current: SandwichPresentation, strokeIsLive: Bool, bakeIsCurrent: Bool,
                     livePair: LivePairFit, livePairIsExact: Bool) -> SandwichPresentation {
        if strokeIsLive { return .midStroke }
        if bakeIsCurrent { return .rest }
        switch livePair {
        case .none:
            return .rest
        case .stale, .current:
            if current == .midStroke { return .midStroke }
            guard livePairIsExact else { return .rest }
            return livePair == .current || current == .live ? .live : .rest
        }
    }
}

/// **How the live pair the canvas is holding relates to the key it is on.**
enum LivePairFit: Equatable {

    /// No pair, or one cut somewhere else. A pair cut at another active layer would draw that layer
    /// twice — once in a half and once by its own host — and a pair from another frame would put the
    /// other layers' ink from that frame beside the active layer's from this one; both are worse than
    /// the previous frame's bake, which is RENDER.md §2.10's picture for a frame not yet baked.
    case none

    /// Cut here, minted for an older key. It differs from the current picture by exactly the edits
    /// made since, and each of them has moved the key and so is on its way.
    case stale

    /// Minted for this key. `SandwichKey`'s sufficiency argument makes that byte-identical to a pair
    /// minted now, at whatever frame.
    case current

    /// `held` is the key and cut of the pair the canvas has, nil when it has none.
    init(held: (key: SandwichKey, cut: LivePairCut)?, key: SandwichKey, cut: LivePairCut?) {
        guard let held else { self = .none; return }
        if held.key == key {
            self = .current
        } else if let cut, held.cut == cut {
            self = .stale
        } else {
            self = .none
        }
    }
}

/// **Where a live pair is cut**: the frame it was minted at and the layer drawn between its halves.
///
/// By id rather than by index, because an index names a different layer after an insert or a delete
/// below it, and a pair cut at the old one would then be drawn around the wrong host.
struct LivePairCut: Equatable {
    let frame: Int
    let activeLayerID: UUID
}
