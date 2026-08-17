import Foundation

/// A transient message shown across the top of the canvas — the owner's replacement for the modal
/// alerts that used to interrupt drawing.
///
/// **The whole point is that it does not take a tap to get rid of.** A brush stroke that has nowhere
/// to land is a thing the artist needs *told*, not a thing they need to acknowledge: the old
/// `.alert("No Drawing Surface")` stole the keyboard focus, dimmed the canvas and demanded an OK
/// before the next stroke could even be attempted, which is three interruptions to deliver one
/// sentence. This is one sentence, at the top, gone on its own.
///
/// A value type with an `id` rather than a bare `String?`: re-raising the *same* message has to
/// restart the dismissal timer and re-run the transition, and two equal strings are indistinguishable
/// to `onChange`. Minting an id per raise is what makes "tap again, see it again" work.
struct CanvasNotice: Identifiable, Equatable {
    let id: UUID
    let kind: Kind

    /// Which message this is. An enum rather than the text itself so the wording lives in one place
    /// (`message` below), so a UI test can assert on a code that survives a rewording, and so the
    /// optional action stays attached to the case that offers it rather than to a closure the model
    /// would have to store (closures are not `Equatable`, and this type has to be).
    ///
    /// **Not `String`-backed.** `historyUndo`/`historyRedo` carry a `HistoryActionLabel`, and Swift
    /// won't synthesise a raw value for an enum with associated data — see `code` below for the
    /// banner's `accessibilityValue` in its place.
    enum Kind: Equatable {
        /// The artist tried to draw with no layers at all.
        case noLayers
        /// The active layer is hidden — by its own eye or by an enclosing group's (§4.1).
        case hiddenLayer
        /// The active layer holds no pixels: a value layer, in either of its two modes.
        case noDrawingSurface
        /// An undo just reverted `HistoryActionLabel`. Raised only when one actually fired —
        /// `CanvasManager.undo()` checks `UndoHistory.undo()`'s return before calling `raise`, so an
        /// undo against an empty stack stays silent rather than announcing nothing happened.
        case historyUndo(HistoryActionLabel)
        /// The redo twin of `historyUndo`, same silence-on-empty-stack rule.
        case historyRedo(HistoryActionLabel)
    }

    init(_ kind: Kind) {
        self.id = UUID()
        self.kind = kind
    }

    var message: String {
        switch kind {
        case .noLayers:         return "No layers — add one to start drawing."
        case .hiddenLayer:      return "This layer is hidden."
        case .noDrawingSurface: return "This layer has no drawing surface."
        case .historyUndo(let label):  return "Undid \(label.phrase)."
        case .historyRedo(let label):  return "Redid \(label.phrase)."
        }
    }

    /// The one-tap fix, where the blocker has one. Both surviving actions are the ones the modal
    /// alerts offered; losing them to the banner would have made the new presentation strictly worse
    /// than the old one for exactly the artists who needed the message.
    ///
    /// **`noDrawingSurface` has none, and deliberately.** Its alert never offered an action either:
    /// switching layers is the only way forward and the artist can already see and do that behind the
    /// banner — which is now literally true rather than nearly true, since the banner does not dim
    /// the panel it is telling you to use.
    ///
    /// **The history notices have none either.** They report what already happened rather than
    /// asking the artist to decide something — the undo/redo *is* the action, and there is nothing
    /// left for a button to do once the banner is up.
    var actionTitle: String? {
        switch kind {
        case .noLayers:         return "Add Layer"
        case .hiddenLayer:      return "Show"
        case .noDrawingSurface: return nil
        case .historyUndo, .historyRedo: return nil
        }
    }

    /// The banner's `accessibilityValue` — what `CanvasNoticeBanner` puts on the identifier instead
    /// of the sentence, so a test can assert on the case rather than the wording (see `Kind`'s doc).
    /// Matches the three blocker cases' old `String`-enum `rawValue` verbatim, so the existing
    /// `LayerUITests` assertion against `"noDrawingSurface"` still passes unchanged.
    var code: String {
        switch kind {
        case .noLayers:         return "noLayers"
        case .hiddenLayer:      return "hiddenLayer"
        case .noDrawingSurface: return "noDrawingSurface"
        case .historyUndo:      return "historyUndo"
        case .historyRedo:      return "historyRedo"
        }
    }

    /// How long the banner stays up before dismissing itself.
    ///
    /// Long enough to read a short sentence twice at a glance, short enough that it is gone before an
    /// artist who ignored it reaches for the next stroke. A notice carrying an action gets longer:
    /// the artist has to notice it, read it, and decide to reach for a button, and a banner that
    /// vanishes mid-reach is worse than no button at all.
    var duration: TimeInterval { actionTitle == nil ? 2.6 : 4.0 }
}
