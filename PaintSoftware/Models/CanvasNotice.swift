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
        /// Move was tapped on an **interpolated in-between** — a frame whose picture is derived from
        /// the two cels either side of it rather than stored.
        ///
        /// It has always been refused, in two places, and until 2026-09-03 it was refused **in
        /// silence**: `activeVectorMoveTarget` returned nil and `beginVectorLassoMove` returned false,
        /// so the artist tapped Move and the app did nothing and said nothing. That is the same
        /// "reads as a broken button" case §5.24 ruled on for `nothingWhollyInside`, and it arrived
        /// through the owner's report of a *different* silent refusal beside it — Move at a posed
        /// frame, which is no longer refused at all.
        ///
        /// The fix is to move to one of the drawn cels either side, which is a decision the artist
        /// makes at the timeline rather than a button this banner could press.
        case cannotMoveDerivedFrame
        /// A Move caught **some but not all** of an animation group's members — the owner's ruling of
        /// 2026-09-03: *"Lets say animation A is a movement of a selection to a location. Now if you
        /// select half of the selection, then it shouldn't allow you to move it because that would
        /// break things."*
        ///
        /// **What it was before the refusal existed.** A group is a set of elements one pose channel
        /// carries, so a key written for it moves every one of them. `commitPoseFromFloat` reused an
        /// existing group whenever the lassoed elements all shared one — *without* asking whether the
        /// group had members the loop had missed — and `keyPoseRestoringRest` then put the pre-lift
        /// display list back and keyed the channel. So lassoing half of an animated group and dragging
        /// it moved **all** of it, and said nothing.
        ///
        /// **Named for the ink rather than for the tool**, `nothingWhollyInside`'s rule: what the
        /// artist has to change is the loop, and the message says so.
        case onlyPartOfAnAnimationGroup
        /// A Move caught an animation group **whole, but not on its own** — a second group's ink, or
        /// ink in no group at all, came with it. The other half of the same 2026-09-03 ruling, and
        /// the same rule reaching a second case: *if a Move would damage an existing animation, it
        /// does not happen, and it says why.*
        ///
        /// **What it was before the refusal existed.** `existingAnimationChannel` reuses a group only
        /// when every carried element shares one, so a mixed selection answered nil and
        /// `commitPoseFromFloat` fell through to `mintAnimationChannel` — which **overwrites**
        /// `animationGroupID` on every carried element with the fresh group's id. From that moment
        /// the tracks still sitting on the cel claimed no elements and posed nothing, so two
        /// animations silently stopped existing. Nothing looked wrong at the frame the Move was made
        /// on; the loss showed up only when the artist scrubbed.
        ///
        /// **A separate sentence from `onlyPartOfAnAnimationGroup` because the way out is opposite.**
        /// That one is fixed by widening the loop until it holds all of the group; this one by
        /// narrowing it until it holds nothing else. One rule, two instructions, and a notice that
        /// cannot say which is worth less than no notice.
        case animationGroupNotAlone
        /// `ProjectStore.writeAtomically` could not stage a valid package — the pre-save validation,
        /// the live-package stash, or the final rename failed. Until ARCHITECTURE_REVIEW.md finding 3,
        /// all three returns were silent: `completion` ran regardless, so the gallery appeared exactly
        /// as it does on success while the artist's edits were never actually written. Raised from
        /// `ContentView` (via `ProjectStore.save`'s `onSaveFailed`), which is the one place that both
        /// owns `canvasManager` and learns the write's outcome.
        case saveFailed
        /// A canvas resize declined to run because `M` could not carry every element — a damaged
        /// archived fill path is the one reachable cause (`VectorCanvas.canBeMapped`).
        /// CANVAS_RESIZE.md §5 rule 11: **never a partial resize**. The alternative the rule refuses
        /// is not an error at all but a silent one — `mapping(_:throughSimilarity:)` hands back an
        /// element it could not map, so the fill would stay at coordinates the rest of the document
        /// no longer uses, looking for all the world like the artist had moved it.
        ///
        /// Carries the refusal rather than a rendered sentence for `Kind`'s stated reason: the
        /// wording lives in `message`, and a test asserts on the case.
        case resizeRefused(CanvasResizeRefusal)
        /// A canvas resize ran, and undoing it will not bring the *pixels* back exactly —
        /// CANVAS_RESIZE.md §5 rule 10 and §6 Q2, which the owner settled as *undo it anyway, and
        /// say so*.
        ///
        /// **Raised when the resize happens, not when undo is pressed.** The artist is deciding
        /// whether to keep the resize now; telling them at the moment they reach for undo is telling
        /// them after the only decision it could have informed. Both halves of the condition are
        /// required — the map has to actually resample or crop (`losesRasterFidelity`) *and* there
        /// have to be raster pixels in the document to lose. A vector-only document, which is what
        /// the owner's own packages measure as (PERFORMANCE.md item 14), resizes exactly in both
        /// directions and is told nothing.
        case resizeResampled
        /// **Two vector layers merged, and the survivor came out as pixels** — TODO item (43).
        ///
        /// Concatenating two display lists is the same picture for plain strokes, and that is the
        /// merge the artist gets. `CanvasManager.vectorMergeIsExact` is the list of shapes where it is
        /// *not*, and each of them falls back to the pixel bake that has always run. This is that
        /// fallback announced, because the artist's next act depends on it: a vector survivor can
        /// still be erased stroke-wise, recoloured, interpolated and resized exactly, and a raster one
        /// cannot, so silently handing back pixels is a capability disappearing with nothing said.
        ///
        /// **Raised only when both layers were `.vector`.** Merging anything into a raster layer, or a
        /// raster layer into anything, produces pixels because one side already is pixels; saying so
        /// would be a banner on every ordinary merge in the app.
        case mergedAsPixels

        /// **The fill tool could not get the memory it needs, and used to say nothing at all.**
        ///
        /// `MetalFillSession` allocates 38 bytes per canvas pixel for a bucket fill and 42 for a
        /// lasso one (MEASURED, RENDER.md §5 stage 7) — 76 MB at the owner's 2048x1024 and 608 MB at
        /// 4096². `MetalFillEngine.makeSession` refuses past `fillBudgetBytes`, refuses when
        /// `CompositorBudget.hasHeadroom` declines, and used to return a bare nil when `makeBuffer`
        /// came back nil at 16383² — so on a large canvas the artist tapped the bucket and *nothing
        /// happened*, with no error and no mark. This is that refusal given a voice.
        ///
        /// **One case for all three reasons.** The artist's next act is the same whichever it was —
        /// work smaller, or close something else — and CLAUDE.md's own rule about notices is that a
        /// message which cannot say what to do is worth less than none. The distinction between "this
        /// canvas is too big for this device" and "this moment is" is in
        /// `MetalFillEngine.SessionOutcome`, where a debugger can read it.
        case fillNeedsMoreMemory

        /// VIDEO.md §8 stage 8: "Bake to Images" refused. In practice this is always an unreadable
        /// asset or a crop with nothing decodable in it — the menu row itself hides `.noVideo`, the
        /// third `VideoBakeRefusal` case, so a real artist never sees that one's sentence, only a
        /// direct caller or a test does.
        case videoBakeRefused(CanvasManager.VideoBakeRefusal)

        /// A live take could not start, or ended having caught nothing — KEYFRAMES.md §5, stage 7.
        ///
        /// **The refused-with-nothing case is why this exists at all.** A recorder that runs for
        /// three seconds and then puts nothing on the timeline, silently, is the worst instance of
        /// the "a refusal with no notice" defect this file already carries three cases of: the
        /// artist has *spent the take*, and nothing on screen says whether the feature is broken or
        /// they simply forgot to touch a control. Each `RecordingRefusal` names its own way out.
        case recordingRefused(CanvasManager.RecordingRefusal)

        /// **The recorder armed, and this is the only thing that says what to do next** —
        /// KEYFRAMES.md §5 and the owner's 2026-09-09 ruling, which made arming and starting two
        /// separate acts.
        ///
        /// Informational rather than a refusal, like `historyUndo` and `resizeResampled`: nothing
        /// went wrong. It exists because the trigger the ruling introduces — *put the pencil on a
        /// slider* — is not on the button that arms it and could not be: the slider is in another
        /// panel, raised from another menu. Without this sentence the feature is the closed loop the
        /// owner found three of in a minute, where the model is right at every step and the artist
        /// cannot get from one step to the next. The blue button is the state; this is the road.
        case recordingArmed

        /// **A selection joined, left, or changed animation group** — TODO (21)'s membership editing,
        /// ruled 2026-09-10.
        ///
        /// Informational, like `recordingArmed` and `resizeResampled`, and it is **not optional
        /// politeness**. The whole design of the edit is that the drawing stays exactly where it looks
        /// on the frame the artist is standing on, so the only thing they can see happen is *nothing*
        /// — which is indistinguishable from a control that does not work. That is the "a refusal with
        /// no notice" defect this file carries four cases of, wearing its positive costume: an action
        /// whose entire visible effect is deferred to another frame has to say what it did.
        case animationGroupMembershipChanged(AnimationGroupEdit)

        /// **The membership edit could not keep the drawing where it looks, so it did not happen.**
        ///
        /// Both arms are whole-edit refusals rather than per-element ones, and that is the requirement
        /// rather than caution: every key on both tracks changes meaning at once, so a membership edit
        /// applied to some of the loop's ink and not the rest is a corrupted document.
        case animationGroupEditRefused(AnimationGroupEditRefusal)
    }

    /// Which of the three operations happened, in the artist's own nouns — the group's display name,
    /// never an id.
    ///
    /// **Three cases and not one with two optionals**, because the sentence differs in what the artist
    /// needs told: joining says what it will follow, leaving says that it has stopped following
    /// anything, and moving has to name both ends or the artist cannot tell a move from a join.
    enum AnimationGroupEdit: Equatable {
        case joined(String)
        case moved(from: String, to: String)
        case left(String)
        /// **The destination carries no pose channel on this cel**, so the ink has joined a group that
        /// is not animating anything yet — which is *every* use of New Group, and the state an artist
        /// most needs a next step from.
        ///
        /// It is a fourth case rather than a flag on the first two because the sentence it wants is
        /// not a variation on theirs: those two end by saying what the drawing will do on the other
        /// frames, and here the honest answer is that it will do nothing until the artist keyframes a
        /// Move. Saying *"it follows Group 3 on the others"* of a group that goes nowhere is true and
        /// useless, which is the shape of an answer that sends a reader to the source.
        case joinedGroupThatIsNotAnimatedHere(String)
    }

    /// Why a membership edit was refused. Both are properties of the *pose at this frame* rather than
    /// of the drawing, which is why both sentences name a frame or a kind and neither says "can't".
    enum AnimationGroupEditRefusal: Equatable {
        /// The destination group's pose at this frame is singular — it has collapsed its members to a
        /// line — so there is no geometry that reproduces where the drawing looks. Reachable only from
        /// a pose an artist authored by dragging a box onto itself, and scrubbing one frame clears it.
        case destinationIsFlatOnThisFrame
        /// The compensation is **projective** and the loop caught a placed image or a video. Their
        /// whole placement is six numbers and a mirror bit where a homography needs eight, so there is
        /// nowhere for the perspective residue to live — `VectorCanvas.posing(_:through:)`'s two
        /// declining kinds, and `distortUnavailableReason` refuses the same pair one tier over.
        case aPlacedImageCannotFollowAKeystone
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
        case .cannotMoveDerivedFrame: return "This frame is an in-between — move the drawing on one of the keyframes either side."
        // **Each now names the second way out as well**, and that is TODO (21)'s membership editing
        // rather than a rewording. Until 2026-09-10 the only fix either sentence could offer was to
        // redraw the loop, because membership was unreachable; an artist who wanted *this ink out of
        // that group* had nowhere to go and the app said nothing about it. The loop fix stays first in
        // both, since it is what an artist who meant to move the whole group wants.
        case .onlyPartOfAnAnimationGroup: return "Only part of an animated group is inside the loop — it moves as one piece, so loop around all of it, or change what it belongs to under Select ▸ Animation Group."
        case .animationGroupNotAlone: return "The loop holds an animated group and ink that isn't part of it — a group moves on its own, so loop around just one group, or put them in the same one under Select ▸ Animation Group."
        case .nothingEnclosed:  return "Nothing enclosed — the fill leaked through a gap in the line, there was no shape inside the loop, or Edge Overlap pulled the colour back past everything there was to paint."
        case .saveFailed:       return "Couldn't save — your changes are still open, but not on disk yet."
        case .resizeRefused(let refusal):
            return "Couldn't resize — \(refusal.phrase) on this canvas can't be moved. Nothing was changed."
        case .resizeResampled:  return "Resized. Undo puts it back — drawn strokes exactly, painted layers approximately."
        case .mergedAsPixels:   return "Merged as pixels — the upper layer's blend mode, opacity, mask or eraser marks can't be carried as strokes."
        case .fillNeedsMoreMemory: return "Not enough memory to fill on a canvas this large — try a smaller canvas, or close other apps."
        case .videoBakeRefused(let refusal): return "Couldn't bake — \(refusal.phrase)."
        case .recordingRefused(let refusal): return refusal.message
        // **The canvas is named first and the slider second** — KEYFRAMES.md §7, stage 10. The order
        // is the ranking an artist reads as "the usual thing": drawing the timing is what the
        // recorder is mostly for, and the sentence has to reach the surface the artist is already
        // looking at. A sentence that named only the slider is what shipped before stage 10, and it
        // would have sent an artist who armed the recorder to draw into a settings panel instead.
        case .recordingArmed:   return "Recorder armed — draw on the canvas, or put your pencil on a layer's opacity or effect slider, and playback starts with it."
        // **Each sentence says the invisible half out loud**: that nothing moved on this frame is the
        // *design*, and that the change shows up when the artist scrubs is the thing they have to be
        // told or they will read the edit as having failed.
        case .animationGroupMembershipChanged(let edit):
            switch edit {
            case .joined(let group):
                return "Added to \(group) — it hasn't moved on this frame, and it follows \(group) on the others."
            case .moved(let from, let to):
                return "Moved from \(from) to \(to) — it hasn't moved on this frame, and it follows \(to) on the others."
            case .left(let group):
                return "Taken out of \(group) — it stays where it is now and stops moving with the group."
            case .joinedGroupThatIsNotAnimatedHere(let group):
                return "Now in \(group) — nothing is animating it yet. Mark a keyframe, scrub, and Move it, and this comes along."
            }
        case .animationGroupEditRefused(let refusal):
            switch refusal {
            case .destinationIsFlatOnThisFrame:
                return "That group's animation flattens to nothing on this frame, so there's no way to keep the drawing where it looks — scrub a frame and try again."
            case .aPlacedImageCannotFollowAKeystone:
                return "A placed image or video can't follow an animation that keystones — leave those out of the loop."
            }
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
        // Nor this one, and for the same reason once more: the fix is to scrub to a drawn cel, which
        // is a move on the timeline the artist can already see.
        case .cannotMoveDerivedFrame: return nil
        // Nor this one. "Select the rest of the group" is a loop only the artist can draw, and the
        // alternative a button could offer — widen the selection to the whole group for them — is a
        // Move they did not ask for on ink they did not point at.
        case .onlyPartOfAnAnimationGroup: return nil
        // Nor this one, and the same argument once more from the other side. "Drop the rest of the
        // loop" is a loop only the artist can redraw, and the button that would do it for them —
        // narrow the Move to one of the groups — is a Move on ink they did not choose, and there is
        // no way for a button to know which group they meant.
        case .animationGroupNotAlone: return nil
        // Nor this one: the artist's next stroke or the next backgrounding will retry the save on its
        // own, and there is no button here that would do anything a retry doesn't already do.
        case .saveFailed:       return nil
        // Nor either resize notice. The refusal's fix is to find the damaged fill, which is a look
        // rather than a tap; the resample one reports what already happened, and undo is on the top
        // toolbar where it always is.
        case .resizeRefused, .resizeResampled: return nil
        // Nor this one. It reports what already happened, and the one thing a button could offer —
        // undo — is on the top toolbar where it always is.
        case .mergedAsPixels:   return nil
        // Nor this one. Neither of the two fixes it names is a button: "a smaller canvas" is a
        // decision about the document the artist has to make with it in front of them, and "close
        // other apps" is not this app's to do.
        case .fillNeedsMoreMemory: return nil
        // Nor this one. An unreadable file has no fix this app can offer, and a crop with nothing
        // decodable in it is undone from the block's own edge handles or Adjust Speed row, neither
        // of which is a button this banner could press on the artist's behalf.
        case .videoBakeRefused: return nil
        // Nor this one, and each of its six cases fails the button test for its own reason. Two
        // name a thing to do *while recording* — open a layer's effect settings, move the slider —
        // which is not an action after the fact; one says the take was too short, whose fix is to
        // record for longer; `notRecordable` asks for a pencil somewhere else, which is not a tap
        // anything here could make; and `noTarget` could offer "Add Layer", except that an artist
        // with no layer at all is not mid-take and the layer panel is already on screen.
        case .recordingRefused: return nil
        // Nor this one, and here it is the sentence itself that rules the button out: what it asks
        // for is a pencil on a slider, which is the one thing in this app no button can do.
        case .recordingArmed:   return nil
        // Nor either of the membership notices. The success one reports what already happened and the
        // only thing a button could offer — undo — is on the top toolbar where it always is; both
        // refusals name a frame to scrub to or ink to leave out of the loop, and neither is a tap this
        // banner could make on the artist's behalf.
        case .animationGroupMembershipChanged, .animationGroupEditRefused: return nil
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
        case .cannotMoveDerivedFrame: return "cannotMoveDerivedFrame"
        case .onlyPartOfAnAnimationGroup: return "onlyPartOfAnAnimationGroup"
        case .animationGroupNotAlone: return "animationGroupNotAlone"
        case .saveFailed:       return "saveFailed"
        case .resizeRefused:    return "resizeRefused"
        case .resizeResampled:  return "resizeResampled"
        case .mergedAsPixels:   return "mergedAsPixels"
        case .fillNeedsMoreMemory: return "fillNeedsMoreMemory"
        case .videoBakeRefused: return "videoBakeRefused"
        // One code for all four, matching `videoBakeRefused`'s precedent: a test asserting a take was
        // refused reads this, and a test that cares *which* refusal reads `RecordingRefusal` off the
        // model, where the fast tier can compare the case itself rather than a string.
        case .recordingRefused: return "recordingRefused"
        case .recordingArmed:   return "recordingArmed"
        // **Three codes rather than one, and one of them is the *kind* of edit.** `videoBakeRefused`'s
        // precedent says a refusal gets one code and a test that cares which reads the model — that
        // holds for the refusal here. The success one is different: an add, a remove and a move are
        // three different things to have happened, and the whole reason the notice exists is that the
        // canvas looks identical after all three, so a test with only `"…Changed"` to read could not
        // tell them apart at all.
        case .animationGroupMembershipChanged(let edit):
            switch edit {
            case .joined: return "animationGroupJoined"
            case .moved:  return "animationGroupMoved"
            case .left:   return "animationGroupLeft"
            case .joinedGroupThatIsNotAnimatedHere: return "animationGroupJoinedStaticGroup"
            }
        case .animationGroupEditRefused: return "animationGroupEditRefused"
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
