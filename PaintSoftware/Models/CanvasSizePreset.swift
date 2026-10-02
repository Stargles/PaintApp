import Foundation

/// A named canvas size the New Canvas sheet offers — TODO (152), the owner's *"add many presets
/// including 2048x1024, 1920, 1080p, etc."*
///
/// **The one list of sizes in the app.** `all` is data, in the order the sheet draws it, and the
/// sheet reads nothing else: a size the artist can pick is a row here, so adding one is one line and
/// there is no second list to keep in step. The picker's own opening size is `initial`, a member of
/// the list rather than a literal beside it.
///
/// **Offered by what the device can hold, not by what the list says.** `offered(withinExtent:)` drops
/// every preset with a side above the ceiling — the same `CanvasManager.maxCanvasExtent` the
/// typed-size validation reads — so a preset can never be a size the sheet would then refuse.
struct CanvasSizePreset: Identifiable, Equatable {
    let width: Int
    let height: Int
    /// What the size is called, in the vocabulary of the thing it is for.
    let name: String

    var id: String { "\(width)x\(height)" }

    /// `1920 × 1080`, the way the sheet and a screen reader both say it.
    var dimensions: String { "\(width) × \(height)" }

    /// Whether a canvas this size is within `extent` on both sides — the rule the sheet's typed
    /// fields apply to a size the artist wrote out by hand.
    func fits(withinExtent extent: Int) -> Bool { width <= extent && height <= extent }

    /// The presets a device whose canvas ceiling is `extent` can actually open, in list order.
    static func offered(withinExtent extent: Int) -> [CanvasSizePreset] {
        all.filter { $0.fits(withinExtent: extent) }
    }

    /// The size the sheet opens on, which is also the size every earlier build opened on.
    static let initial = CanvasSizePreset(width: 2048, height: 2048, name: "Square 2K")

    /// Animation first: the video sizes, then the owner's own 2:1 working size
    /// (PERFORMANCE.md §1), then squares, then the vertical-video pair.
    static let all: [CanvasSizePreset] = [
        CanvasSizePreset(width: 1280, height: 720, name: "720p HD"),
        CanvasSizePreset(width: 1920, height: 1080, name: "1080p Full HD"),
        CanvasSizePreset(width: 2560, height: 1440, name: "1440p QHD"),
        CanvasSizePreset(width: 3840, height: 2160, name: "4K UHD"),
        CanvasSizePreset(width: 2048, height: 1024, name: "Wide 2:1"),
        CanvasSizePreset(width: 1024, height: 1024, name: "Square"),
        CanvasSizePreset(width: 1080, height: 1080, name: "Square HD"),
        initial,
        CanvasSizePreset(width: 1080, height: 1920, name: "Vertical 1080p"),
        CanvasSizePreset(width: 720, height: 1280, name: "Vertical 720p"),
    ]
}
