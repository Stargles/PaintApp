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
        /// The eyedropper was tapped somewhere with no colour: off the paper's edge, or on a fully
        /// transparent pixel with the canvas background hidden. Raised rather than left silent
        /// because the tool reverts on a miss as well as a hit (`applyEyedropperResult`), so without
        /// a word the artist sees only their tool changing under them for no stated reason.
        case nothingToPick
        /// A lasso fill's loop held nothing out: the collar leaked through a gap in the line art,
        /// there was no enclosed shape inside the loop at all, or Edge Overlap ate what little there
        /// was.
        ///
        /// **The third cause is a later arrival and is genuinely distinguishable from the first
        /// two** — the count is taken after `lassoEdgeErode`, so a fill that existed and was then
        /// eroded away is a different path from one that never existed. It is named in the same
        /// sentence anyway, because the artist's next move is the same whichever it was (look at the
        /// slider, look at the line) and a fourth branch of UI for a one-line difference is not
        /// worth its weight. It became reachable when Edge Overlap started defaulting to something
        /// other than 0 on this tool: lasso a 3 px hatch line with the slider low and every painted
        /// pixel legitimately goes.
        ///
        /// **Both causes, in one message, because the algorithm genuinely cannot tell them apart**
        /// (LASSO_FILL.md §4 case 11): each is "the collar reached everything inside the fence". Made
        /// the tool guess between them and the blank-paper branch would have to paint the loop's own
        /// shape — which on the leak case means a slab of colour dumped over the artist's drawing.
        ///
        /// Raised rather than left silent for the reason §7 opens with: Krita ships this same
        /// algorithm with no diagnostic, and its users report only that "it just won't fill
        /// anything". A tool that does nothing and says nothing reads as broken.
        case nothingEnclosed
        /// A lasso **move** under the `Enclosed` membership rule caught nothing, on a loop that has
        /// ink in it — TODO item (20), and the owner's ruling of 2026-08-28 that this case must say
        /// so.
        ///
        /// **It is deliberately not the same silence LASSO_MOVE.md §5.9 rules for an empty lasso.**
        /// There the paper inside the loop was blank and the artist can see the reason; here the loop
        /// is full of ink and the *rule they just picked* is what excluded it, so a Move that did
        /// nothing and said nothing reads as a broken button. `CanvasManager.beginVectorLassoMove`
        /// tells the two apart by asking the `.touching` predicate whether a laxer rule would have
        /// caught anything, and stays silent when it would not.
        ///
        /// Named for the rule rather than for the tool because that is what the artist has to change:
        /// the fix is one tap on the picker that is already on screen, or a wider loop.
        case nothingWhollyInside
        /// `ProjectStore.writeAtomically` could not stage a valid package — the pre-save validation,
        /// the live-package stash, or the final rename failed. Until ARCHITECTURE_REVIEW.md finding 3,
        /// all three returns were silent: `completion` ran regardless, so the gallery appeared exactly
        /// as it does on success while the artist's edits were never actually written. Raised from
        /// `ContentView` (via `ProjectStore.save`'s `onSaveFailed`), which is the one place that both
        /// owns `canvasManager` and learns the write's outcome.
        case saveFailed
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
        case .nothingToPick:    return "Nothing to pick up there."
        case .nothingWhollyInside: return "Nothing is completely inside the loop — try Cut or Touching, or draw a wider loop."
        case .nothingEnclosed:  return "Nothing enclosed — the fill leaked through a gap in the line, there was no shape inside the loop, or Edge Overlap pulled the colour back past everything there was to paint."
        case .saveFailed:       return "Couldn't save — your changes are still open, but not on disk yet."
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
        // Nor this one, for the same reason: the fix is to tap somewhere with paint on it, which the
        // artist can already see and do behind the banner.
        case .nothingToPick:    return nil
        // Nor this one, and here the reason is that the fix is a *choice* the artist has to make with
        // the canvas in front of them — patch the gap, redraw the loop, or raise Gap Closing on the
        // slider that is already on screen. None of the three is a button this banner could press.
        case .nothingEnclosed:  return nil
        // Nor this one, and for the neighbouring reason: the fix is a choice between three rules the
        // artist is already looking at, or a loop only they can redraw.
        case .nothingWhollyInside: return nil
        // Nor this one: the artist's next stroke or the next backgrounding will retry the save on its
        // own, and there is no button here that would do anything a retry doesn't already do.
        case .saveFailed:       return nil
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
        case .nothingToPick:    return "nothingToPick"
        case .nothingEnclosed:  return "nothingEnclosed"
        case .nothingWhollyInside: return "nothingWhollyInside"
        case .saveFailed:       return "saveFailed"
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
