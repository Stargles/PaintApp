import XCTest

/// Walks the **whole** input space of "who owns this canvas touch" — 1,920 combinations for each
/// (tool, fill mode) pair, 440 of them states the app can actually be in — rather than sampling it.
///
/// Both figures halved on 2026-08-27 when TODO item (12) stage 2 deleted the `isVectorTransforming`
/// axis: 3,840 and 490 are the numbers with it.
///
/// **Exhaustion is the point.** Every defect this type was extracted to retire was a combination
/// nobody thought to try: the pick tool with the Select panel open (owned by nobody), a shape's
/// outline under a finger (owned by two), the eyedropper on a `!= .fill` list (owned by two). A
/// handful of examples would have missed all three, and did. `Tool.paintsOnCanvas`' own test walks
/// every case for the same reason, and this file follows its style — an exhaustive `switch` with no
/// `default:`, so the next tool, panel or overlay has to answer.
///
/// **Nothing here is a number that moves when a tool is added, and that is a requirement rather than
/// a nicety.** The whole promise of `CanvasTouchOwner` is that the next tool is one edit; a test that
/// has to be recomputed whenever the thing it guards changes is not a guard, it is a tax on the
/// change it was written to make safe. So every expectation in this file is either
///
///  * a **set of signatures**, generated from a rule over `Tool.allCases` (so a new tool extends both
///    sides of the comparison and invalidates nothing) —
///    `testTheTransformDependencyIsUnresolvableOnlyInTheDeclaredCases`;
///  * a **property asserted per state**, which names the signature it failed at —
///    `testNoReachableTouchHasMoreThanOneActor`, `testEveryContenderAfterTheFirstStandsDown`,
///    `testAnOverlayClaimTakesTheTouchFromEveryOtherView`, `testEveryToolReachesTheOwnerItNames`;
///  * or a **per-(tool, fill-mode) count**, never a total, so the tool axis is factored out entirely
///    — `testTheReachableInputSpaceIsTheSizeThisFileClaims`.
///
/// The one hand-maintained list left is `testEveryTouchOfferedToMoreThanOneMechanism`'s set of
/// *combinations*, which carries no arithmetic and exists to be read. **Its meaning changed on
/// 2026-08-22 and that is worth saying plainly**: it used to be a list of live defects — two things
/// acting on one touch — and it is now a list of touches that are *offered* to two mechanisms and
/// settled by precedence, with only the first acting. The teeth that make that true are
/// `testEveryContenderAfterTheFirstStandsDown` and `testNoReachableTouchHasMoreThanOneActor`, which
/// assert per state; the list stays because "which combinations even arise" is still the thing a
/// person should read down when they add a mechanism.
final class CanvasTouchOwnerLogicTests: XCTestCase {

    // MARK: - The input space

    /// Whether the app can actually be in this state.
    ///
    /// **Not a convenience — without it the enumeration is dominated by combinations that cannot
    /// happen**, and a conflict list nobody can act on is the same as no conflict list. Each clause
    /// below names the code that makes it impossible.
    private func isReachable(_ i: CanvasTouchInputs) -> Bool {
        // `TopToolbar.toggleMove` branches on `activeLayerIsVector`: a raster Move lifts a
        // `floatingPiece`, a vector one begins a `vectorFloat`. Never both.
        if i.hasFloatingPiece && i.hasVectorFloat { return false }
        // `beginMove` needs an active layer to lift from.
        if i.hasFloatingPiece && !i.activeLayer.exists { return false }
        // `beginVectorLassoMove` runs on the active vector layer, and `updateTransformOverlay`'s
        // first arm re-checks that the float's layer is still in the document.
        if i.hasVectorFloat && i.activeLayer != .vector { return false }

        switch i.chrome {
        case .none:
            return true
        case .transformBoxOrHandle:
            // The Move box is on screen for exactly one state (`updateTransformOverlay`): a piece is
            // floating. It does not consult visibility, deliberately — see
            // `CanvasTouchInputs.moveBoxIsUp`, which carries the ruling — so a hidden layer reaches
            // this chrome too. There was a second arm, a whole vector layer mid-`isVectorTransforming`,
            // which *did* ask; it went with the flag (TODO item (12) stage 2).
            return i.hasVectorFloat
        case .shapeHandleOrOutline, .textBoxOrBand, .textHandle:
            // A pending shape and a live text session are both baked by
            // `commitAllInteractiveState()`, which every route into Move and every toolbar toggle
            // calls; and both need a layer with pixels to have started on.
            //
            // **Visibility is deliberately not required**, as it is not for the Move box above:
            // neither `updateShapeOverlay` nor `updateTextOverlay` consults
            // `isLayerEffectivelyVisible`, so hiding the layer a shape or a text box
            // is pending on leaves its handles on screen and grabbable. That is what produces the
            // `shapeOverlay+catchAllNotice` and `textOverlay+catchAllNotice` rows below.
            if i.hasFloatingPiece || i.hasVectorFloat { return false }
            return i.activeLayer == .raster || i.activeLayer == .vector
        case .guideGrip:
            // Guides are an orthogonal mode: `GuideOverlayView` is interactive whenever
            // `editing != .none`, which none of the four inputs here can see. Reachable throughout,
            // and that independence is exactly why it turns up in so many conflicts below.
            return true
        }
    }

    /// Every reachable state, once.
    private func forEachReachableInput(_ body: (CanvasTouchInputs) -> Void) {
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                for panel in ActivePanel.allCases {
                    for hasFloatingPiece in [false, true] {
                        for hasVectorFloat in [false, true] {
                            for activeLayer in CanvasActiveLayer.allCases {
                                for onScreen in [false, true] {
                                    for chrome in CanvasTouchChrome.allCases {
                                        let inputs = CanvasTouchInputs(
                                            tool: tool, fillMode: fillMode, panel: panel,
                                            hasFloatingPiece: hasFloatingPiece,
                                            hasVectorFloat: hasVectorFloat,
                                            activeLayer: activeLayer,
                                            activeLayerIsOnScreen: onScreen, chrome: chrome)
                                        // `.none` normalises visibility to false, so the `true` half
                                        // of that pair is the same state twice.
                                        guard inputs.activeLayerIsOnScreen == onScreen else { continue }
                                        guard isReachable(inputs) else { continue }
                                        body(inputs)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A combination named the way a reader can act on: the tool, whether Select is open, what is
    /// floating, what the active layer is, and what the touch landed on. The nine non-`.select`
    /// panels collapse, because no gate distinguishes them — `testTheOnlySettingsPanelAnyGateReads`
    /// proves that rather than assuming it.
    private func signature(_ i: CanvasTouchInputs) -> String {
        let mode = i.tool == .fill ? "/\(i.fillMode.rawValue)" : ""
        return "tool=\(i.tool)\(mode) select=\(i.panel == .select) float=\(i.hasFloatingPiece)"
            + " vfloat=\(i.hasVectorFloat)"
            + " layer=\(i.activeLayer.rawValue) visible=\(i.activeLayerIsOnScreen)"
            + " chrome=\(i.chrome.rawValue)"
    }

    // MARK: - The space is the size it says it is

    /// **Counted per (tool, fill mode) pair, never in total, and the difference is the whole point.**
    /// A total is a number that moves whenever a tool is added — the one event this type exists to
    /// make cheap — and it moves for a reason that has nothing to do with what the number is
    /// guarding, which is "did a case appear on one of the *other* axes, or did `isReachable`'s
    /// clauses change". Dividing the tool axis out leaves a number that only moves when something
    /// worth looking at moved.
    ///
    /// The division is legitimate because **no clause in `isReachable` reads the tool or the fill
    /// mode** — every one of them is about floats, the active layer or the chrome — so every pair
    /// admits exactly the same states. That is asserted here rather than assumed, and it is the
    /// assertion that makes the per-pair figure meaningful: if a reachability rule ever did start
    /// reading the tool, the uniformity check below is what says so.
    func testTheReachableInputSpaceIsTheSizeThisFileClaims() {
        var totalByPair: [String: Int] = [:]
        var reachableByPair: [String: Int] = [:]
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                let pair = "\(tool)/\(fillMode.rawValue)"
                for panel in ActivePanel.allCases {
                    for float in [false, true] {
                        for vfloat in [false, true] {
                            for layer in CanvasActiveLayer.allCases {
                                for onScreen in [false, true] {
                                    for chrome in CanvasTouchChrome.allCases {
                                        totalByPair[pair, default: 0] += 1
                                        let inputs = CanvasTouchInputs(
                                            tool: tool, fillMode: fillMode, panel: panel,
                                            hasFloatingPiece: float, hasVectorFloat: vfloat,
                                            activeLayer: layer,
                                            activeLayerIsOnScreen: onScreen, chrome: chrome)
                                        guard inputs.activeLayerIsOnScreen == onScreen else { continue }
                                        if isReachable(inputs) { reachableByPair[pair, default: 0] += 1 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let pairs = Tool.allCases.count * FillMode.allCases.count
        XCTAssertEqual(totalByPair.count, pairs, "every (tool, fill mode) pair should have been walked")
        for (pair, count) in totalByPair.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(count, 1_920,
                           "\(pair): the enumerated space changed — a case was added to `ActivePanel`, "
                           + "`CanvasActiveLayer` or `CanvasTouchChrome`")
        }
        for (pair, count) in reachableByPair.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(count, 440,
                           "\(pair): the reachability rules changed; re-read `isReachable`'s clauses. "
                           + "A figure that differs *between* pairs means a clause has started reading "
                           + "the tool, which this file's per-pair counting assumes it does not.")
        }
    }

    // MARK: - The answer is always defined, and always singular where it can be

    func testOwnerIsAlwaysTheFirstContenderOrNobody() {
        forEachReachableInput { inputs in
            let contenders = CanvasTouchOwner.contenders(in: inputs)
            let owner = CanvasTouchOwner.owner(in: inputs)
            XCTAssertEqual(owner, contenders.first ?? .nobody, "at \(self.signature(inputs))")
            if owner != .nobody {
                XCTAssertTrue(contenders.contains(owner), "at \(self.signature(inputs))")
            }
        }
    }

    /// No owner in the enum is unreachable. A case nothing can produce is a case that has quietly
    /// stopped being wired up, which is the failure `Tool.paintsOnCanvas` makes impossible for tools.
    func testEveryOwnerCaseIsReachable() {
        var seen = Set<CanvasTouchOwner>()
        forEachReachableInput { seen.formUnion(CanvasTouchOwner.contenders(in: $0)) }
        seen.insert(.nobody) // produced by absence, so it never appears in `contenders`
        XCTAssertEqual(seen, Set(CanvasTouchOwner.allCases),
                       "unreachable owner(s): \(Set(CanvasTouchOwner.allCases).subtracting(seen))")
    }

    // MARK: - Nobody

    /// **The test this type exists for, and since 2026-08-22 the set is empty.**
    ///
    /// "Owned by nobody" is exactly what the pick-tool bug was, and it is invisible from any one
    /// gate: the touch simply does nothing and the app says nothing. Three families survived the
    /// extraction, all of them on a vector layer:
    ///
    ///  1. **Vector layer mid-Move, brush selected, touch away from the box.** `shouldInteract` was
    ///     false (`isVectorTransforming`, since deleted), the catch-all is off (the layer is visible
    ///     and has a surface), and a paint tool has no recognizer of its own.
    ///  2. **A vector piece floating, brush selected, touch away from the box.** The same
    ///     hole, plus the structural one: `FloatingPieceOverlayView` covers the whole container and
    ///     commits a raster piece on a tap outside it, while a vector float's
    ///     `ObjectTransformOverlayView` claims only its own grips. Family 1 collapsed into this one
    ///     when Move with no selection became a float (TODO item (12) stage 1).
    ///  3. **A vector piece floating with the Select panel open — every tool but the pick.**
    ///     The selection overlay stands aside for `vectorFloat`, the fill and text presses for the
    ///     Select panel, and nothing took over.
    ///
    /// The owner ruled (j) on all three: **the tap commits the float**, so a vector Move behaves like
    /// a raster one — chosen over leaving it silent and over raising a notice. `.moveBoxCommit` is
    /// what took them, and this test is now the statement that nothing is left.
    ///
    /// Watched failing with `.moveBoxCommit` taken back out of `contenders(in:)`: **122 reachable
    /// inputs in 15 signatures** on the input space as it stood on 2026-08-22, which carried a
    /// `vxform` axis this file no longer enumerates. (The report of this defect quoted 118. 122 was
    /// what the enumeration measured then; the four-state gap was never reconciled, and the assertion
    /// is on zero either way.)
    func testNoReachableTouchIsOwnedByNobody() {
        var found = Set<String>()
        var reachableInputs = 0
        forEachReachableInput { inputs in
            guard CanvasTouchOwner.owner(in: inputs) == .nobody else { return }
            reachableInputs += 1
            found.insert(self.signature(inputs))
        }
        XCTAssertEqual(reachableInputs, 0,
                       "\(reachableInputs) reachable inputs owned by nobody, in \(found.count) "
                       + "signatures: \(found.sorted())")
    }

    /// (j), stated at the point the artist is standing: a lassoed vector piece is floating, the
    /// finger comes down away from the box, and **the box is put down** — where before the ruling
    /// nothing happened and nothing was said.
    ///
    /// **The tool axis is the interesting half, and the answer is "only where the tool had nothing to
    /// do".** `.moveBoxCommit` is last in the precedence on purpose: a tool with a live recognizer of
    /// its own keeps the touch exactly as it did before — the fill still floods, the pick still
    /// picks, the text tool still places a box — and the tap-away takes only what used to fall
    /// through. A brush has no canvas recognizer, and with the Select panel open the fill and text
    /// presses are suspended and the selection overlay stands aside for the float, so those are
    /// precisely the states that had nobody.
    ///
    /// Watched failing with `.moveBoxCommit` out of `contenders(in:)`: *("nobody") is not equal to
    /// ("moveBoxCommit") — tool pen/flood, select false*, sixteen times over.
    func testATouchAwayFromAFloatingVectorPieceCommitsIt() {
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                for panel in [ActivePanel.none, .select] {
                    let inputs = CanvasTouchInputs(tool: tool, fillMode: fillMode, panel: panel,
                                                   hasVectorFloat: true, activeLayer: .vector)
                    let owner = CanvasTouchOwner.owner(in: inputs)
                    let what = "tool \(tool)/\(fillMode.rawValue), select \(panel == .select)"
                    XCTAssertNotEqual(owner, .nobody, "\(what) still does nothing at all")
                    // The tool's own mechanism where it has one and it is armed; the box's tap-away
                    // everywhere else. Spelled from `Tool.canvasRecognizerOwner` rather than listed,
                    // so a tool added later answers here the way it answers everywhere.
                    let toolsOwn = tool.canvasRecognizerOwner(fillMode: fillMode)
                    let toolIsArmed = toolsOwn != nil
                        && CanvasTouchOwner.contenders(in: inputs).contains(toolsOwn!)
                    XCTAssertEqual(owner, toolIsArmed ? toolsOwn! : .moveBoxCommit, what)
                    XCTAssertEqual(CanvasTouchOwner.actors(in: inputs), [owner],
                                   "and only one thing acts — \(what)")
                }
            }
        }
        // The plainest form of the ruling, which is the one the owner will try: a brush in hand, a
        // piece floating, a finger anywhere off the box.
        let brush = CanvasTouchInputs(tool: .pen, hasVectorFloat: true, activeLayer: .vector)
        XCTAssertEqual(CanvasTouchOwner.owner(in: brush), .moveBoxCommit)
    }

    /// **The visibility question, decided rather than dropped.** `moveBoxIsUp` used to have two arms
    /// and they disagreed about `activeLayerIsOnScreen`: the whole-layer transform's asked, the
    /// float's did not. TODO item (12) stage 2 deleted the arm that asked, so the answer had to be
    /// chosen for the one that is left rather than left to fall out of the deletion.
    ///
    /// **Ruled: the box stays up on a hidden layer**, because a float is a *lift* — the moved ids are
    /// suppressed out of the layer's own render and the only copy of them is in `VectorFloat` — so the
    /// box is the grip on geometry that is currently out of the document, not decoration over content
    /// the artist cannot see. Adding the visibility term would take `chrome ==
    /// .transformBoxOrHandle` out of `moveBoxIsUp` and leave a lift the artist cannot grab.
    /// The whole-layer arm could afford the check precisely because it lifted nothing.
    ///
    /// The tap *away* is untouched by the ruling and lands on the notice either way: `.catchAllNotice`
    /// precedes `.moveBoxCommit`, so a touch off the box on a hidden layer says "this layer is
    /// hidden" instead of settling silently. (j) was about touches that did *nothing*, not about
    /// touches that already explained themselves.
    func testAMoveBoxStaysUpOnAHiddenLayerBecauseTheLiftIsStillOutOfTheDocument() {
        let hidden = CanvasTouchInputs(tool: .pen, hasVectorFloat: true, activeLayer: .vector,
                                       activeLayerIsOnScreen: false)
        XCTAssertTrue(hidden.moveBoxIsUp, "the ruling, stated on the property it is about")
        XCTAssertTrue(hidden.moveBoxCommitIsEnabled)

        // The grips still claim their own touches, which is the half the ruling is for.
        let onGrip = CanvasTouchInputs(tool: .pen, hasVectorFloat: true, activeLayer: .vector,
                                       activeLayerIsOnScreen: false, chrome: .transformBoxOrHandle)
        XCTAssertEqual(CanvasTouchOwner.owner(in: onGrip), .objectTransformOverlay,
                       "a hidden layer's float must still be grabbable, or the lift is stranded")

        // The tap away defers to the notice, ahead of it in the precedence.
        XCTAssertEqual(CanvasTouchOwner.owner(in: hidden), .catchAllNotice)
        XCTAssertTrue(CanvasTouchOwner.contenders(in: hidden).contains(.moveBoxCommit))

        // And on a visible layer the tap away is the settle, unchanged.
        let visible = CanvasTouchInputs(tool: .pen, hasVectorFloat: true, activeLayer: .vector,
                                        activeLayerIsOnScreen: true)
        XCTAssertEqual(CanvasTouchOwner.owner(in: visible), .moveBoxCommit)
    }

    /// A touch **on** the box is a drag, not a commit. The two are one feature and two owners, the
    /// same split `.selectionOverlay`/`.lassoFill` makes, and getting it wrong would mean grabbing
    /// the box put it down.
    func testATouchOnTheMoveBoxIsStillADragAndNotACommit() {
        for tool in Tool.allCases {
            let inputs = CanvasTouchInputs(tool: tool, hasVectorFloat: true, activeLayer: .vector,
                                           chrome: .transformBoxOrHandle)
            XCTAssertEqual(CanvasTouchOwner.owner(in: inputs), .objectTransformOverlay, "tool \(tool)")
            XCTAssertFalse(CanvasTouchOwner.contenders(in: inputs).contains(.moveBoxCommit),
                           "the tap-away is not even offered a touch on the box — tool \(tool)")
        }
    }

    /// The 2026-08-22 bug, stated directly: with the Select panel open and the eyedropper armed, the
    /// pick is owned by the eyedropper and by nothing else. Before `isEyedropperArmed` this was
    /// `.nobody` — the recognizer was off *and* the selection overlay was still eating the tap.
    func testThePickToolOwnsItsTapWithTheSelectPanelOpen() {
        for layer in CanvasActiveLayer.allCases {
            for onScreen in [false, true] {
                let inputs = CanvasTouchInputs(tool: .eyedropper, panel: .select, activeLayer: layer,
                                               activeLayerIsOnScreen: onScreen)
                XCTAssertEqual(CanvasTouchOwner.contenders(in: inputs), [.eyedropper],
                               "active layer \(layer.rawValue) onScreen=\(onScreen)")
            }
        }
    }

    /// The other half of the same fix: a floating piece *does* suspend the eyedropper, so the two
    /// sites cannot end up both live or both dead.
    func testAFloatingPieceOwnsTheTouchEvenWithTheEyedropperSelected() {
        let inputs = CanvasTouchInputs(tool: .eyedropper, panel: .select,
                                       hasFloatingPiece: true, activeLayer: .raster)
        XCTAssertEqual(CanvasTouchOwner.owner(in: inputs), .floatingPiece)
    }

    /// 2026-08-17: the eyedropper picked a colour **and** painted a stroke, because the host's tool
    /// clause was a hand-maintained `!= .fill` list. The active layer must decline every tool that
    /// has a recognizer of its own.
    func testNoToolEverOwnsBothTheLayerHostAndItsOwnRecognizer() {
        forEachReachableInput { inputs in
            let contenders = CanvasTouchOwner.contenders(in: inputs)
            guard contenders.contains(.activeLayerStroke) else { return }
            for recognizer in [CanvasTouchOwner.fillPress, .lassoFill, .eyedropper, .textPress] {
                XCTAssertFalse(contenders.contains(recognizer),
                               "\(recognizer.rawValue) alongside the stroke at \(self.signature(inputs))")
            }
        }
    }

    /// `30e38e3`: dragging a smart shape's outline drew a stroke, because `ShapeOverlayView.hitTest`
    /// claimed the handles and declined everything else. A touch on the outline is the overlay's,
    /// and the stroke recognizer does not see it.
    func testAShapeOutlineTouchBelongsToTheShapeOverlayAndNotToTheStroke() {
        for tool in [Tool.pen, .pencil] {
            for chrome in [CanvasTouchChrome.shapeHandleOrOutline] {
                let inputs = CanvasTouchInputs(tool: tool, activeLayer: .raster, chrome: chrome)
                XCTAssertEqual(CanvasTouchOwner.contenders(in: inputs), [.shapeOverlay],
                               "tool \(tool)")
            }
        }
        // …and plain canvas beside it still is the stroke's, which is what makes the overlay
        // transparent everywhere else rather than modal.
        let beside = CanvasTouchInputs(tool: .pen, activeLayer: .raster, chrome: .none)
        XCTAssertEqual(CanvasTouchOwner.owner(in: beside), .activeLayerStroke)
    }

    // MARK: - More than one

    /// **One touch, one actor — the rule the owner settled on 2026-08-22, walked over the whole
    /// space.**
    ///
    /// Before it — the report of the defect counted 1,678 reachable combinations — two things acted
    /// on one touch: drag a guide grip with Fill selected and the grip moved *and* a flood fill landed
    /// under it; with the pick armed, the grip moved *and* the brush colour changed and the tool
    /// reverted; drag a floating vector piece's box with Fill selected and the piece moved *and* a
    /// fill dumped underneath; tap into your own text with Fill selected and the caret placed *and*
    /// the layer flooded; adjust a guide while a Move piece floated and the guide moved *and* the
    /// piece was dropped.
    ///
    /// **No combination is deliberately left with two**, so there is no exemption list here.
    ///
    /// Watched failing by making `CanvasTouchOwner.yieldsToTheOwner` answer `false` for the five
    /// container recognizers — which is exactly the app as it stood, four of the five handlers not
    /// asking. **5,662 assertion failures**, the first *[guideOverlay, catchAllNotice] both act at
    /// tool=eraser select=false float=false vfloat=false vxform=false layer=none visible=false
    /// chrome=guideGrip*.
    func testNoReachableTouchHasMoreThanOneActor() {
        forEachReachableInput { inputs in
            let actors = CanvasTouchOwner.actors(in: inputs)
            XCTAssertLessThanOrEqual(actors.count, 1,
                                     "\(actors.map(\.rawValue)) both act at \(self.signature(inputs))")
            let owner = CanvasTouchOwner.owner(in: inputs)
            XCTAssertEqual(actors, owner == .nobody ? [] : [owner], "at \(self.signature(inputs))")
        }
    }

    /// **The teeth under the rule: everything offered a touch behind the owner is something that
    /// stands down.**
    ///
    /// `actors(in:)` can only be right if `yieldsToTheOwner` is right, and `yieldsToTheOwner` is a
    /// claim about handlers — five of them open by asking `owner(in:)`. This is the assertion that a
    /// *sixth* mechanism cannot be added behind them without either asking the same question or
    /// showing up here. It is the one that fails when somebody wires a new recognizer onto the
    /// container and forgets the guard.
    ///
    /// The first contender is exempt because it *is* the owner; nothing else may be a view, because
    /// UIKit gives a touch to one view and the owner is the view it gave it to.
    func testEveryContenderAfterTheFirstStandsDown() {
        forEachReachableInput { inputs in
            let contenders = CanvasTouchOwner.contenders(in: inputs)
            for loser in contenders.dropFirst() {
                XCTAssertTrue(loser.yieldsToTheOwner,
                              "\(loser.rawValue) is offered this touch behind "
                              + "\(contenders[0].rawValue) and does not stand down, at "
                              + "\(self.signature(inputs))")
            }
        }
    }

    /// **Every combination in which two mechanisms are offered one touch.**
    ///
    /// Not defects any more — each is settled by the precedence in `contenders(in:)`, and only the
    /// first of them acts — but still the reviewable set, because "which combinations arise at all"
    /// is what a person adding a mechanism has to read. Three structural families produce every row:
    ///
    ///  * **`<overlay chrome> + <whichever container recognizer is enabled>`.** Each container
    ///    recognizer sets `cancelsTouchesInView = false` and is attached to an ancestor of every
    ///    overlay, so a `hitTest` claim above it takes nothing away — it is offered the touch and
    ///    declines. That declining is rule (i).
    ///  * **`+ catchAllNotice` alongside something that worked.** `needsCatch` reads only the active
    ///    layer's state and never asks whether a floating piece or the Select panel has taken the
    ///    touch. The notice sits behind everything that acts, so it now stays quiet.
    ///  * **`<anything armed> + moveBoxCommit`.** The vector Move box's tap-away, which is (j). It is
    ///    *behind* the tools rather than ahead of them — a raster float outranks them through
    ///    `!hasFloatingPiece` inside `fillPressIsEnabled` and friends, and copying that would have
    ///    settled rows nobody ruled on. It takes only the touch nothing else wanted.
    ///
    /// **What is *absent* is the change (i) made to this list.** Every `<overlay> + <container-sized
    /// view>` row — `guideOverlay+selectionOverlay`, `guideOverlay+floatingPiece`,
    /// `shapeOverlay+lassoFill` and the rest — is gone, because UIKit hands a touch to one view and
    /// those two views are no longer above the overlays that claim grips (see `updateUIView`'s
    /// ordering, and `updateGuideOverlay`, which is the pass that moved).
    func testEveryTouchOfferedToMoreThanOneMechanism() {
        var found = Set<String>()
        forEachReachableInput { inputs in
            let contenders = CanvasTouchOwner.contenders(in: inputs)
            guard contenders.count > 1 else { return }
            found.insert(contenders.map(\.rawValue).joined(separator: "+"))
        }

        let expected: Set<String> = [
            // A guide grip is reachable in every state, because guide editing is a mode none of
            // these inputs can see.
            "guideOverlay+catchAllNotice",
            "guideOverlay+eyedropper",
            "guideOverlay+fillPress",
            "guideOverlay+textPress",
            "guideOverlay+moveBoxCommit",
            "guideOverlay+catchAllNotice+moveBoxCommit",
            "guideOverlay+eyedropper+moveBoxCommit",
            "guideOverlay+fillPress+moveBoxCommit",
            "guideOverlay+textPress+moveBoxCommit",
            // A pending shape. The `+catchAllNotice` row is the one the earlier shape of this model
            // could not express: `updateShapeOverlay` never asks whether the layer is still visible,
            // so hiding it leaves the handles up *and* arms the "this layer is hidden" notice under
            // them.
            "shapeOverlay+eyedropper",
            "shapeOverlay+fillPress",
            "shapeOverlay+textPress",
            "shapeOverlay+catchAllNotice",
            // A live text session — note the absence of any `+textPress` pairing.
            "textOverlay+eyedropper",
            "textOverlay+fillPress",
            "textOverlay+catchAllNotice",
            "textTransformOverlay+eyedropper",
            "textTransformOverlay+fillPress",
            "textTransformOverlay+catchAllNotice",
            // The Move box itself, with a piece floating. No `+moveBoxCommit`: a touch on the box is
            // a drag, and the tap-away is not offered it.
            "objectTransformOverlay+eyedropper",
            "objectTransformOverlay+fillPress",
            "objectTransformOverlay+textPress",
            "objectTransformOverlay+catchAllNotice",
            // (j)'s own rows, on plain canvas away from the box. `moveBoxCommit` is last in every one
            // of them, which is the whole of its precedence argument: it takes what is left.
            "catchAllNotice+moveBoxCommit",
            "eyedropper+moveBoxCommit",
            "fillPress+moveBoxCommit",
            "textPress+moveBoxCommit",
            "lassoFill+moveBoxCommit",
            // No `selectionOverlay+moveBoxCommit`, and its disappearance is the one behavioural
            // trace TODO item (12) stage 2 left on this list. `selectionOverlayIsCapturing` requires
            // `!hasVectorFloat`, and `moveBoxIsUp` is now exactly `hasVectorFloat`, so the two are
            // mutually exclusive by construction. The row existed only through the deleted
            // whole-layer arm: `isVectorTransforming` put a box up *without* a float, which the
            // selection overlay's guard did not exclude.
            // The catch-all's own two, with no overlay involved.
            "floatingPiece+catchAllNotice",
            "selectionOverlay+catchAllNotice",
        ]

        XCTAssertEqual(found, expected,
                       "new: \(found.subtracting(expected).sorted())\n"
                       + "gone: \(expected.subtracting(found).sorted())")
    }

    /// **Why the list above needs no census: an overlay's claim displaces every other *view* and
    /// nothing else, and this says so once per state.**
    ///
    /// The `<overlay> + <recognizer>` rows are not independent facts. They are one fact stated as an
    /// equation — the contenders for a touch on chrome are the chrome's owner, followed by exactly
    /// the contenders the same state would have had on plain canvas, less
    ///
    ///  * **every view**, because UIKit hands a touch to one view: the layer host underneath
    ///    (`30e38e3`), `SelectionOverlayView` while it captures, and `FloatingPieceOverlayView` while
    ///    a piece floats. The last two are the (i) change — they are pinned to the whole container
    ///    with no `hitTest` override, and until the pass ordering in `updateUIView` was fixed they
    ///    sat *above* the guide overlay and quietly ate its grips;
    ///  * **`textPress`, on the two text chromes only**, which is `handleTextPress`' own guard: there
    ///    the placement tap is not merely outranked, it is wrong;
    ///  * **`moveBoxCommit`, on the Move box only**, because a touch on the box is a drag.
    ///
    /// Asserted per state and reported by signature, so a change that moved one combination into
    /// another fails here naming the combination, where a total would have absorbed it.
    ///
    /// Watched failing with the previous `contenders(in:)` put back — the one that listed the
    /// container-sized views alongside a chrome claim: 1,174 states, the first
    /// *("[guideOverlay, selectionOverlay]") is not equal to ("[guideOverlay]")*.
    func testAnOverlayClaimTakesTheTouchFromEveryOtherView() {
        forEachReachableInput { inputs in
            guard let chromeOwner = inputs.chrome.owner else { return }
            var plainCanvas = inputs
            plainCanvas.chrome = .none
            let isTextChrome = inputs.chrome == .textBoxOrBand || inputs.chrome == .textHandle
            let expected = [chromeOwner] + CanvasTouchOwner.contenders(in: plainCanvas).filter {
                if !$0.yieldsToTheOwner { return false }
                if isTextChrome, $0 == .textPress { return false }
                if inputs.chrome == .transformBoxOrHandle, $0 == .moveBoxCommit { return false }
                return true
            }
            XCTAssertEqual(CanvasTouchOwner.contenders(in: inputs), expected,
                           "at \(self.signature(inputs))")
        }
    }

    /// The other half of the same argument, for the states where no overlay is involved at all:
    /// **on plain canvas a touch is offered twice exactly when the catch-all speaks over something
    /// that did work, or when the Move box's tap-away sits over an armed tool**, and never for any
    /// other reason.
    ///
    /// Everything else on plain canvas is mutually exclusive by construction, and that is worth
    /// stating because it is what makes the rows in the list above the *only* rows: a floating piece
    /// suppresses the selection overlay, both presses and the stroke; the Select panel suppresses
    /// both presses and the stroke; and no two tools' mechanisms can be armed at once
    /// (`testEveryToolReachesTheOwnerItNames`).
    func testTheOnlyTwoWaysToBeOfferedATouchTwiceWithNoOverlayInvolved() {
        forEachReachableInput { inputs in
            guard inputs.chrome == .none else { return }
            let contenders = CanvasTouchOwner.contenders(in: inputs)
            // The catch-all is the one gate that never asks whether anybody else took the touch —
            // `needsCatch` reads only the active layer's own state.
            let catchAllSpeaksOverSomeoneElse = inputs.catchAllRaisesNotice
                && (inputs.floatingOverlayIsInteractive || inputs.selectionOverlayIsCapturing)
            // …and the Move box's tap-away, whose gate is the float rather than the tool, so
            // whatever was armed stays armed underneath it. It is last in the precedence, so it is
            // the one thing here that never displaces anybody.
            let moveBoxSitsUnderSomething = inputs.moveBoxCommitsThisTouch && contenders.count > 1
            XCTAssertEqual(contenders.count > 1,
                           catchAllSpeaksOverSomeoneElse || moveBoxSitsUnderSomething,
                           "at \(self.signature(inputs))")
            guard catchAllSpeaksOverSomeoneElse else { return }
            // The mechanism that *acted* is still the owner, and the notice is behind it.
            XCTAssertEqual(contenders.firstIndex(of: .catchAllNotice).map { $0 > 0 }, true,
                           "at \(self.signature(inputs))")
        }
    }

    // MARK: - Rule (i), at the four places the owner named

    /// **Grab a guide grip with Fill selected and only the grip moves.** The flood used to land under
    /// it, because `fillTapRecognizer` sits on the container with `cancelsTouchesInView = false` and
    /// the guide overlay's `hitTest` claim took nothing away from it.
    ///
    /// Watched failing with `yieldsToTheOwner` returning false for the five recognizers:
    /// *("[guideOverlay, fillPress]") is not equal to ("[guideOverlay]") — fill/flood on a guide
    /// grip*, and fifteen more across the four chromes.
    func testGrabbingChromeWithAToolArmedLeavesTheToolAlone() {
        let cases: [(chrome: CanvasTouchChrome, owner: CanvasTouchOwner, why: String)] = [
            (.guideGrip, .guideOverlay, "a guide grip"),
            (.shapeHandleOrOutline, .shapeOverlay, "a smart shape's handle or outline"),
            (.textBoxOrBand, .textOverlay, "your own live text"),
            (.textHandle, .textTransformOverlay, "a text box's grip"),
        ]
        for (chrome, owner, why) in cases {
            for tool in Tool.allCases {
                for fillMode in FillMode.allCases {
                    let inputs = CanvasTouchInputs(tool: tool, fillMode: fillMode,
                                                   activeLayer: .raster, chrome: chrome)
                    XCTAssertEqual(CanvasTouchOwner.actors(in: inputs), [owner],
                                   "\(tool)/\(fillMode.rawValue) on \(why)")
                }
            }
        }
    }

    /// **The Move box wins over the tool under it**, which is the owner's "drag a floating piece's
    /// box with Fill selected → the piece moves *and* a fill dumps under it".
    func testDraggingTheMoveBoxDoesNotAlsoRunTheToolUnderneath() {
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                let inputs = CanvasTouchInputs(tool: tool, fillMode: fillMode, hasVectorFloat: true,
                                               activeLayer: .vector, chrome: .transformBoxOrHandle)
                XCTAssertEqual(CanvasTouchOwner.actors(in: inputs), [.objectTransformOverlay],
                               "\(tool)/\(fillMode.rawValue) on the Move box")
            }
        }
    }

    /// **Family F2: the catch-all must not speak over something that worked.** A Move piece dragged
    /// over a hidden active layer popped "this layer is hidden" on every touch of the drag, and
    /// lassoing with no layers popped "no layers" on every drag.
    ///
    /// Watched failing with `yieldsToTheOwner` returning false for the five recognizers, on both
    /// halves: *("[floatingPiece, catchAllNotice]") is not equal to ("[floatingPiece]")* and
    /// *("[selectionOverlay, catchAllNotice]") is not equal to ("[selectionOverlay]")*.
    func testTheNoticeStaysQuietWhenSomebodyElseTookTheTouch() {
        // A raster piece floating over a hidden active layer, brush selected.
        let overAHiddenLayer = CanvasTouchInputs(tool: .pen, hasFloatingPiece: true,
                                                 activeLayer: .raster, activeLayerIsOnScreen: false)
        XCTAssertTrue(overAHiddenLayer.catchAllRaisesNotice, "the gate is still open — that is the point")
        XCTAssertEqual(CanvasTouchOwner.actors(in: overAHiddenLayer), [.floatingPiece])

        // Lassoing with no layers at all.
        let withNoLayers = CanvasTouchInputs(tool: .pen, panel: .select, activeLayer: .none)
        XCTAssertTrue(withNoLayers.catchAllRaisesNotice)
        XCTAssertEqual(CanvasTouchOwner.actors(in: withNoLayers), [.selectionOverlay])

        // And on plain canvas with nobody else in the way it still speaks, which is its whole job.
        let plainHiddenLayer = CanvasTouchInputs(tool: .pen, activeLayer: .raster,
                                                 activeLayerIsOnScreen: false)
        XCTAssertEqual(CanvasTouchOwner.actors(in: plainHiddenLayer), [.catchAllNotice])
    }

    /// **A guide grip stays the guide's with the Select panel open and with a piece floating.**
    ///
    /// This is the one row of (i) that is not a handler guard at all: `SelectionOverlayView` and
    /// `FloatingPieceOverlayView` are pinned to the whole container with no `hitTest` override, so
    /// while the guide overlay was fronted *before* them in `updateUIView` they were above it and ate
    /// every touch that would have reached a grip. Moving that one pass is the fix, and this is what
    /// says the model now agrees.
    ///
    /// Watched failing against the previous `contenders(in:)`, which listed the container-sized views
    /// alongside a chrome claim: *[guideOverlay, selectionOverlay] is not [guideOverlay]*.
    func testAGuideGripIsTheGuidesEvenUnderTheSelectPanelOrAFloatingPiece() {
        let underSelect = CanvasTouchInputs(tool: .pen, panel: .select, activeLayer: .raster,
                                            chrome: .guideGrip)
        XCTAssertEqual(CanvasTouchOwner.contenders(in: underSelect), [.guideOverlay])

        let overAFloat = CanvasTouchInputs(tool: .pen, hasFloatingPiece: true, activeLayer: .raster,
                                           chrome: .guideGrip)
        XCTAssertEqual(CanvasTouchOwner.contenders(in: overAFloat), [.guideOverlay],
                       "and the piece is not dropped by the same touch")

        // Beside the grip the two views have everything back, which is what makes the overlay
        // transparent everywhere else rather than modal.
        var beside = underSelect
        beside.chrome = .none
        XCTAssertEqual(CanvasTouchOwner.owner(in: beside), .selectionOverlay)
        var besideFloat = overAFloat
        besideFloat.chrome = .none
        XCTAssertEqual(CanvasTouchOwner.owner(in: besideFloat), .floatingPiece)
    }

    /// The one compensation the app already has, pinned so a refactor cannot drop it: a tap that
    /// landed in a live text box, or on one of its grips, is not also a request to place a new box.
    /// Without it, tapping into your own text to move the caret would commit that text and open a
    /// fresh empty box on top of it.
    func testATapOnALiveTextBoxDoesNotAlsoPlaceANewOne() {
        for chrome in [CanvasTouchChrome.textBoxOrBand, .textHandle] {
            let inputs = CanvasTouchInputs(tool: .text, activeLayer: .raster, chrome: chrome)
            XCTAssertFalse(CanvasTouchOwner.contenders(in: inputs).contains(.textPress),
                           "chrome \(chrome.rawValue)")
        }
        // On plain canvas beside the box, the placement tap is live again — that is what lets one
        // tap commit this box and place the next.
        let beside = CanvasTouchInputs(tool: .text, activeLayer: .raster, chrome: .none)
        XCTAssertEqual(CanvasTouchOwner.owner(in: beside), .textPress)
    }

    // MARK: - The fifteenth question

    /// **Where two-finger navigation is staked on something that cannot resolve.**
    ///
    /// `shouldRequireFailure` makes pan / pinch / rotate wait for the active layer's stroke
    /// recognizer whenever `shouldInteract` is true. That asks "is the host accepting touches?",
    /// but the question that decides whether the recognizer will ever reach a terminal state is
    /// "did *this* touch reach the host?", and two things answer no:
    ///
    ///  * **the active layer is hidden.** `shouldInteract` never consults visibility — visibility is
    ///    applied one line above it as `host.isHidden`, a different mechanism — so the host is
    ///    `isUserInteractionEnabled` *and* invisible, and UIKit delivers nothing to a hidden view.
    ///    Hide the layer you are on (or the group holding it), keep a brush selected, and the canvas
    ///    will not pan, pinch or rotate.
    ///  * **an overlay above the hosts claimed the touch** — a shape outline, a text box or grip, a
    ///    guide grip. Two fingers landing there produce the same stall.
    ///
    /// **This does not explain BUGS.md's "two-finger pan is dead while Fill is selected".** With
    /// Fill selected `Tool.paintsOnCanvas` is false, so `shouldInteract` is false, so no dependency
    /// is stated at all — no tool with its own recognizer appears below. Whatever kills that gesture
    /// on the owner's iPad is not in the arbitration layer.
    func testTheTransformDependencyIsUnresolvableOnlyInTheDeclaredCases() {
        var found = Set<String>()
        forEachReachableInput { inputs in
            guard inputs.transformDependencyIsUnresolvable else { return }
            found.insert("hiddenHost=\(!inputs.activeLayerIsOnScreen) chrome=\(inputs.chrome.rawValue) tool=\(inputs.tool)")
        }

        var expected = Set<String>()
        for tool in Tool.allCases where tool.paintsOnCanvas {
            expected.insert("hiddenHost=true chrome=none tool=\(tool)")
            for chrome in [CanvasTouchChrome.guideGrip, .shapeHandleOrOutline, .textBoxOrBand, .textHandle] {
                expected.insert("hiddenHost=false chrome=\(chrome.rawValue) tool=\(tool)")
                expected.insert("hiddenHost=true chrome=\(chrome.rawValue) tool=\(tool)")
            }
        }

        XCTAssertEqual(found, expected,
                       "new: \(found.subtracting(expected).sorted())\ngone: \(expected.subtracting(found).sorted())")
    }

    /// No tool with a recognizer of its own can stall the transform, because none of them makes the
    /// host interactive. States the Fill half of BUGS.md's open report as an assertion.
    func testNoToolWithItsOwnRecognizerEverStakesTheTransformOnAStroke() {
        forEachReachableInput { inputs in
            guard inputs.tool.canvasRecognizerOwner(fillMode: inputs.fillMode) != nil else { return }
            XCTAssertFalse(inputs.transformWaitsOnActiveStroke, "at \(self.signature(inputs))")
        }
    }

    // MARK: - Properties of the gates themselves

    /// Every one of the fourteen gates spells `activePanel == .select` or `!= .select` and ignores
    /// the other nine cases. Asserted rather than assumed, because "which panel is open decides what
    /// a canvas touch even means" and a tenth panel that mattered would be invisible otherwise.
    func testTheOnlySettingsPanelAnyGateReads() {
        let others = ActivePanel.allCases.filter { $0 != .select }
        forEachReachableInput { inputs in
            guard inputs.panel != .select else { return }
            var reference = inputs
            reference.panel = .none
            for panel in others {
                var variant = inputs
                variant.panel = panel
                XCTAssertEqual(CanvasTouchOwner.contenders(in: variant),
                               CanvasTouchOwner.contenders(in: reference),
                               "panel \(panel) differs at \(self.signature(inputs))")
            }
        }
    }

    /// `Tool.canvasRecognizerOwner` and `Tool.paintsOnCanvas` are complementary by construction, and
    /// this is what says so. A tool that answered `true` to both would be the 2026-08-17 defect
    /// exactly — one touch reaching a stroke view *and* a recognizer of its own.
    ///
    /// **And the answer's *identity* is checked, not only its nil-ness.** `canvasRecognizerOwner` is
    /// sold as having `Tool.paintsOnCanvas`' shape — an exhaustive `switch` with no `default:`, so
    /// the next tool cannot ship without answering — but a test that only asks whether it returned
    /// *something* lets the next tool answer wrongly and stay green, which is the same hole
    /// `paintsOnCanvas` was written to close one level down. So the name is checked against the
    /// model: in the tool's own plain state (a visible raster layer, no panel, nothing floating,
    /// plain canvas under the finger) the owner `CanvasTouchOwner` derives must be exactly the
    /// mechanism the tool named, or the active layer's stroke where it named none.
    ///
    /// That also states "**every tool reaches at least one owner**": there is no tool whose plain
    /// touch is owned by nobody, which is the single-tool form of the 2026-08-22 bug.
    func testEveryToolReachesTheOwnerItNames() {
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                let named = tool.canvasRecognizerOwner(fillMode: fillMode)
                XCTAssertEqual(tool.paintsOnCanvas, named == nil,
                               "\(tool) answers both / neither")
                let plain = CanvasTouchInputs(tool: tool, fillMode: fillMode, activeLayer: .raster)
                XCTAssertEqual(CanvasTouchOwner.contenders(in: plain), [named ?? .activeLayerStroke],
                               "\(tool)/\(fillMode.rawValue) names \(named.map(\.rawValue) ?? "no recognizer") "
                               + "but its plain touch is owned by "
                               + "\(CanvasTouchOwner.contenders(in: plain).map(\.rawValue))")
            }
        }
    }

    /// The one part of `CanvasView.Coordinator.canvasTouchInputs(chrome:)` that had a decision in it,
    /// pulled into the model so it can be checked at all — see `CanvasActiveLayer.init(kind:)` for
    /// why, and `CanvasTouchInputs`' own comment for the part of the gathering that still cannot be.
    /// A `.value` layer is the interesting row: it exists, and it holds no pixels, and collapsing
    /// those two into one answer is what the two-axis shape of these inputs exists to avoid.
    func testALayersKindMapsToTheKindTheGatesMakeOfIt() {
        XCTAssertEqual(CanvasActiveLayer(kind: nil), .none)
        XCTAssertEqual(CanvasActiveLayer(kind: .raster), .raster)
        XCTAssertEqual(CanvasActiveLayer(kind: .vector), .vector)
        XCTAssertEqual(CanvasActiveLayer(kind: .value), .noDrawingSurface)

        // And the two properties the fourteen gates actually read off it, so a future case cannot be
        // added to `CanvasActiveLayer` and left answering the defaults.
        XCTAssertFalse(CanvasActiveLayer(kind: nil).exists)
        XCTAssertTrue(CanvasActiveLayer(kind: .value).exists)
        XCTAssertTrue(CanvasActiveLayer(kind: .value).hasNoDrawingSurface)
        XCTAssertFalse(CanvasActiveLayer(kind: .raster).hasNoDrawingSurface)
        XCTAssertFalse(CanvasActiveLayer(kind: .vector).hasNoDrawingSurface)
    }

    /// The fill tool's two modes reach two different owners, and that is the whole of the
    /// `isLassoFilling` tie-break: the Select panel wins over the lasso fill, so a selection drag
    /// begun there does not turn into a fill because Fill happened to be the last tool picked.
    func testTheFillToolsTwoModesReachTwoDifferentOwners() {
        let flood = CanvasTouchInputs(tool: .fill, fillMode: .flood, activeLayer: .raster)
        let lasso = CanvasTouchInputs(tool: .fill, fillMode: .lasso, activeLayer: .raster)
        XCTAssertEqual(CanvasTouchOwner.owner(in: flood), .fillPress)
        XCTAssertEqual(CanvasTouchOwner.owner(in: lasso), .lassoFill)

        var lassoUnderSelect = lasso
        lassoUnderSelect.panel = .select
        XCTAssertEqual(CanvasTouchOwner.owner(in: lassoUnderSelect), .selectionOverlay)
    }

    /// The catch-all exists to *explain* a touch the canvas cannot act on, and it explains only
    /// touches that would have drawn — `handleCatchAllTap` asks `Tool.paintsOnCanvas` first. So a
    /// fill or a pick on a layer with no pixels is silent by design, and the notice cases are
    /// exactly the three states `reconcileLayers` names.
    func testTheCatchAllSpeaksOnlyForATouchThatWouldHaveDrawn() {
        for tool in Tool.allCases {
            for layer in CanvasActiveLayer.allCases {
                for onScreen in [false, true] {
                    let inputs = CanvasTouchInputs(tool: tool, activeLayer: layer,
                                                   activeLayerIsOnScreen: onScreen)
                    let drawable = (layer == .raster || layer == .vector) && inputs.activeLayerIsOnScreen
                    XCTAssertEqual(inputs.catchAllRaisesNotice, tool.paintsOnCanvas && !drawable,
                                   "tool \(tool) on \(layer.rawValue) onScreen=\(onScreen)")
                }
            }
        }
    }
}
