import XCTest

/// Walks the **whole** input space of "who owns this canvas touch" — 28,800 combinations, of which
/// 3,600 are states the app can actually be in — rather than sampling it.
///
/// **Exhaustion is the point.** Every defect this type was extracted to retire was a combination
/// nobody thought to try: the pick tool with the Select panel open (owned by nobody), a shape's
/// outline under a finger (owned by two), the eyedropper on a `!= .fill` list (owned by two). A
/// handful of examples would have missed all three, and did. `Tool.paintsOnCanvas`' own test walks
/// every case for the same reason, and this file follows its style — an exhaustive `switch` with no
/// `default:`, so the next tool, panel or overlay has to answer.
///
/// The three tests that matter are `testNobodyOwnsATouchOnlyInTheThreeDeclaredCases`,
/// `testTouchesWithMoreThanOneClaimant` and
/// `testTheTransformDependencyIsUnresolvableOnlyInTheDeclaredCases`. Each pins a *set of
/// signatures* rather than a count: a gate that changes does not merely move a number, it names the
/// combination it changed.
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
        // `isVectorTransforming` is toggled only on a vector layer, and `toggleMove` bakes any
        // float before it touches the flag.
        if i.isVectorTransforming && i.activeLayer != .vector { return false }
        if i.isVectorTransforming && (i.hasFloatingPiece || i.hasVectorFloat) { return false }

        switch i.chrome {
        case .none:
            return true
        case .transformBoxOrHandle:
            // The Move box is on screen for exactly two states (`updateTransformOverlay`).
            return i.hasVectorFloat || (i.isVectorTransforming && i.activeLayer == .vector)
        case .shapeHandleOrOutline, .textBoxOrBand, .textHandle:
            // A pending shape and a live text session are both baked by
            // `commitAllInteractiveState()`, which every route into Move and every toolbar toggle
            // calls; and both need a layer with pixels to have started on.
            if i.hasFloatingPiece || i.hasVectorFloat || i.isVectorTransforming { return false }
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
                            for isVectorTransforming in [false, true] {
                                for activeLayer in CanvasActiveLayer.allCases {
                                    for chrome in CanvasTouchChrome.allCases {
                                        let inputs = CanvasTouchInputs(
                                            tool: tool, fillMode: fillMode, panel: panel,
                                            hasFloatingPiece: hasFloatingPiece,
                                            hasVectorFloat: hasVectorFloat,
                                            isVectorTransforming: isVectorTransforming,
                                            activeLayer: activeLayer, chrome: chrome)
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
            + " vfloat=\(i.hasVectorFloat) vxform=\(i.isVectorTransforming)"
            + " layer=\(i.activeLayer.rawValue) chrome=\(i.chrome.rawValue)"
    }

    // MARK: - The space is the size it says it is

    func testTheReachableInputSpaceIsTheSizeThisFileClaims() {
        var reachable = 0
        var total = 0
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                for panel in ActivePanel.allCases {
                    for float in [false, true] {
                        for vfloat in [false, true] {
                            for vxform in [false, true] {
                                for layer in CanvasActiveLayer.allCases {
                                    for chrome in CanvasTouchChrome.allCases {
                                        total += 1
                                        let inputs = CanvasTouchInputs(
                                            tool: tool, fillMode: fillMode, panel: panel,
                                            hasFloatingPiece: float, hasVectorFloat: vfloat,
                                            isVectorTransforming: vxform,
                                            activeLayer: layer, chrome: chrome)
                                        if isReachable(inputs) { reachable += 1 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(total, 28_800, "the enumerated space changed — a case was added to one of the input enums")
        XCTAssertEqual(reachable, 3_600, "the reachability rules changed; re-read `isReachable`'s clauses")
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

    /// **The test this type exists for.** "Owned by nobody" is exactly what the 2026-08-22 pick-tool
    /// bug was, and it is invisible from any one gate: the touch simply does nothing and the app
    /// says nothing. Three families remain, all of them on a vector layer, and all three are
    /// reported to the owner rather than fixed here.
    ///
    ///  1. **Vector layer mid-Move, brush selected, touch away from the box.** `shouldInteract` is
    ///     false (`isVectorTransforming`), the catch-all is off (the layer is visible and has a
    ///     surface), and a paint tool has no recognizer of its own. The artist draws and nothing
    ///     happens, with no notice — where a value layer or a hidden layer would have explained
    ///     itself.
    ///  2. **Lassoed vector piece floating, brush selected, touch away from the box.** The same
    ///     hole, plus a second: `FloatingPieceOverlayView` covers the whole container and commits a
    ///     raster piece on a tap outside it, while a vector float's `ObjectTransformOverlayView`
    ///     claims only its own grips. So the raster and vector Move differ in whether tapping away
    ///     does anything at all.
    ///  3. **Lassoed vector piece floating with the Select panel open — every tool.** The selection
    ///     overlay yields to `vectorFloat`, the fill and text presses yield to the Select panel, and
    ///     nothing takes over. The canvas is inert away from the box even for the lasso the open
    ///     panel is for.
    func testNobodyOwnsATouchOnlyInTheThreeDeclaredCases() {
        var found = Set<String>()
        forEachReachableInput { inputs in
            guard CanvasTouchOwner.owner(in: inputs) == .nobody else { return }
            found.insert(self.signature(inputs))
        }

        var expected = Set<String>()
        for tool in Tool.allCases {
            let modes = tool == .fill ? ["/flood", "/lasso"] : [""]
            for m in modes {
                // 1 & 2 — a paint tool, no Select panel, a vector layer either mid-transform or
                // with a piece floating.
                if tool.paintsOnCanvas {
                    expected.insert("tool=\(tool)\(m) select=false float=false vfloat=false vxform=true layer=vector chrome=none")
                    expected.insert("tool=\(tool)\(m) select=false float=false vfloat=true vxform=false layer=vector chrome=none")
                }
                // 3 — Select open over a floating vector piece, whatever the tool.
                expected.insert("tool=\(tool)\(m) select=true float=false vfloat=true vxform=false layer=vector chrome=none")
            }
        }
        // The eyedropper is the one tool that survives case 3, and that is the 2026-08-22 fix
        // working: `isEyedropperArmed` does not consult the Select panel.
        expected.remove("tool=eyedropper select=true float=false vfloat=true vxform=false layer=vector chrome=none")

        XCTAssertEqual(found, expected,
                       "new: \(found.subtracting(expected).sorted())\ngone: \(expected.subtracting(found).sorted())")
    }

    /// The 2026-08-22 bug, stated directly: with the Select panel open and the eyedropper armed, the
    /// pick is owned by the eyedropper and by nothing else. Before `isEyedropperArmed` this was
    /// `.nobody` — the recognizer was off *and* the selection overlay was still eating the tap.
    func testThePickToolOwnsItsTapWithTheSelectPanelOpen() {
        for layer in CanvasActiveLayer.allCases {
            let inputs = CanvasTouchInputs(tool: .eyedropper, panel: .select, activeLayer: layer)
            XCTAssertEqual(CanvasTouchOwner.contenders(in: inputs), [.eyedropper],
                           "active layer \(layer.rawValue)")
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

    /// **Every combination in which two mechanisms both act on one touch.**
    ///
    /// These are defects present in the app right now, not modelling artefacts: each container
    /// recognizer sets `cancelsTouchesInView = false`, and UIKit delivers a touch to the recognizers
    /// of every view in its responder chain — so an overlay's `hitTest` claim does not take the
    /// touch away from the fill press mounted on the container underneath it.
    ///
    /// Two structural families produce all 29 signatures:
    ///
    ///  * **`<overlay chrome> + <whichever container recognizer is enabled>` (24 of them).** Grab a
    ///    guide grip with Fill selected and the grip drags *and* a flood fill lands under it; grab a
    ///    shape handle with the eyedropper armed and the brush colour changes too; drag a floating
    ///    vector piece's box with Fill selected and the piece moves *and* the layer is flooded.
    ///    `handleTextPress` is the **only** handler in the app that defends itself, by re-running the
    ///    two text overlays' `hitTest` before it acts — which is why `textOverlay+textPress` and
    ///    `textHandle+textPress` are absent from this list and every other pairing is present.
    ///  * **`catchAllNotice` alongside something that did work.** `needsCatch` reads only the
    ///    active layer's state and never asks whether a floating piece or the Select panel has taken
    ///    the touch, so dragging a Move piece over a hidden active layer raises "this layer is
    ///    hidden" on every touch, and lassoing with no layers raises "no layers" on every drag.
    func testTouchesWithMoreThanOneClaimant() {
        var found: [String: Int] = [:]
        forEachReachableInput { inputs in
            let contenders = CanvasTouchOwner.contenders(in: inputs)
            guard contenders.count > 1 else { return }
            found[contenders.map(\.rawValue).joined(separator: "+"), default: 0] += 1
        }

        let expected: [String: Int] = [
            // A guide grip is reachable in every state, because guide editing is a mode none of
            // these inputs can see.
            "guideOverlay+catchAllNotice": 162,
            "guideOverlay+eyedropper": 140,
            "guideOverlay+fillPress": 63,
            "guideOverlay+lassoFill": 63,
            "guideOverlay+textPress": 126,
            "guideOverlay+selectionOverlay": 42,
            "guideOverlay+selectionOverlay+catchAllNotice": 18,
            "guideOverlay+floatingPiece": 360,
            "guideOverlay+floatingPiece+catchAllNotice": 120,
            // A pending shape.
            "shapeOverlay+eyedropper": 40,
            "shapeOverlay+fillPress": 18,
            "shapeOverlay+lassoFill": 18,
            "shapeOverlay+textPress": 36,
            "shapeOverlay+selectionOverlay": 20,
            // A live text session — note the absence of any `+textPress` pairing.
            "textOverlay+eyedropper": 40,
            "textOverlay+fillPress": 18,
            "textOverlay+lassoFill": 18,
            "textOverlay+selectionOverlay": 20,
            "textTransformOverlay+eyedropper": 40,
            "textTransformOverlay+fillPress": 18,
            "textTransformOverlay+lassoFill": 18,
            "textTransformOverlay+selectionOverlay": 20,
            // The Move box, on a vector layer mid-transform or with a lassoed piece floating.
            "objectTransformOverlay+eyedropper": 40,
            "objectTransformOverlay+fillPress": 18,
            "objectTransformOverlay+lassoFill": 18,
            "objectTransformOverlay+textPress": 36,
            "objectTransformOverlay+selectionOverlay": 10,
            // The catch-all's own two, with no overlay involved.
            "floatingPiece+catchAllNotice": 120,
            "selectionOverlay+catchAllNotice": 18,
        ]

        XCTAssertEqual(Set(found.keys), Set(expected.keys),
                       "new: \(Set(found.keys).subtracting(expected.keys).sorted())\n"
                       + "gone: \(Set(expected.keys).subtracting(found.keys).sorted())")
        for (key, count) in expected {
            XCTAssertEqual(found[key], count, "count changed for \(key)")
        }
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
            found.insert("hiddenHost=\(!inputs.activeLayer.isOnScreen) chrome=\(inputs.chrome.rawValue) tool=\(inputs.tool)")
        }

        var expected = Set<String>()
        for tool in Tool.allCases where tool.paintsOnCanvas {
            expected.insert("hiddenHost=true chrome=none tool=\(tool)")
            expected.insert("hiddenHost=true chrome=guideGrip tool=\(tool)")
            for chrome in [CanvasTouchChrome.guideGrip, .shapeHandleOrOutline, .textBoxOrBand, .textHandle] {
                expected.insert("hiddenHost=false chrome=\(chrome.rawValue) tool=\(tool)")
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
    func testEveryToolEitherPaintsOnCanvasOrOwnsItsOwnRecognizer() {
        for tool in Tool.allCases {
            for fillMode in FillMode.allCases {
                let recognizer = tool.canvasRecognizerOwner(fillMode: fillMode)
                XCTAssertEqual(tool.paintsOnCanvas, recognizer == nil,
                               "\(tool) answers both / neither")
            }
        }
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
                let inputs = CanvasTouchInputs(tool: tool, activeLayer: layer)
                let expected = tool.paintsOnCanvas && !(layer == .raster || layer == .vector)
                XCTAssertEqual(inputs.catchAllRaisesNotice, expected,
                               "tool \(tool) on \(layer.rawValue)")
            }
        }
    }
}
