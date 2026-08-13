import Foundation

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
    /// Unobservable until phase 5 gave children something other than source-over to do — with every
    /// child at `.normal`, isolation changes no pixel, since children composited onto transparency
    /// and then drawn over the backdrop equal children drawn straight onto it. Storing and honouring
    /// it a phase early is what let phase 5 add blend modes and only blend modes.
    var isIsolated: Bool = true

    /// The group's own mask (§6.2), applied once to its finished composite for the same reason its
    /// opacity and blend mode are: masking each child instead clips the children rather than the
    /// group, which is a different picture wherever they overlap. A group can be masked *and* be a
    /// mask source.
    var alphaMask: AlphaMask? = nil
}
