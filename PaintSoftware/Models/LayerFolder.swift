import Foundation

/// How a layer or group combines with the backdrop beneath it.
///
/// One case so far, and deliberately an enum rather than nothing — the same call `CompositorOp`
/// makes, for the same reason. LAYER_COMPOSITING.md §7 lists twenty-odd modes arriving in phases 5
/// and 7 as "one `switch` in one shader"; what phase 4 needs from it now is a *name* for normal, so
/// that `RenderNode.needsOwnBuffer` — the rule deciding when a group costs an intermediate buffer —
/// can be written once and stay written when the cases land.
///
/// Lives beside `LayerFolder` because a folder is the only thing that has one yet. Phase 5 gives
/// `Layer` one too, and that is the moment to move this into a file of its own.
enum BlendMode: String, Codable, Equatable {
    case normal
}

struct LayerFolder: Identifiable {
    let id: UUID
    var name: String
    var isExpanded: Bool = true
    var isVisible: Bool = true
    /// Set when this folder is nested inside another. Ordering among siblings is derived from the
    /// layers each folder holds — see `CanvasManager.layerStackRows`.
    var parentFolderID: UUID? = nil

    // MARK: - Group properties (§4.1)
    //
    // A folder stopped being only a panel affordance in phase 4: it is a compositing unit, and these
    // are what hang on it. Each defaults to its identity, so a folder nobody has touched composites
    // exactly as one that predates them — which is what lets existing projects decode unchanged.

    /// Applied once to the group's finished composite, never per child. The two differ wherever
    /// children overlap, and only the first is what "group opacity" means.
    var opacity: Double = 1

    var blendMode: BlendMode = .normal

    /// Isolated (§3 decision 2, §4.2): children start from transparent and blend only against each
    /// other, and the finished buffer composites into the parent with this group's own opacity and
    /// blend mode. Pass-through — `false` — lets children blend against the backdrop below the
    /// group, which is Photoshop's and CSP's default and this app's *toggle* rather than its default.
    ///
    /// **Nothing observes it yet, and that is expected.** With every child at `.normal`, isolation
    /// changes no pixel: source-over is associative, so children composited onto transparency and
    /// then drawn over the backdrop equal children drawn straight onto it. It is stored and honoured
    /// now so that phase 5 adds blend modes and only blend modes.
    var isIsolated: Bool = true
}
