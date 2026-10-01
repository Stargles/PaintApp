import XCTest
import SwiftUI

/// **What the live canvas shows between an edit and its bake** — `SandwichPresentation.next` and
/// `LivePairFit`, TODO (145).
///
/// The owner, 2026-10-01, with one vector layer under two transformation layers: *"I place a stroke,
/// then undo, then place a stroke and undo again. The first stroke briefly appears the second time I
/// undo. Also, the undos are latent. I'd estimate around 400ms."* Both halves of that are decisions
/// made here: the latency is how long the canvas stands on the previous bake after an edit, and one
/// way to flash an undone stroke is to step back from an edit's live picture onto a bake older than
/// it. `CanvasView.Coordinator` makes the choice on every pass in a file this target does not
/// compile, so the choice is a pure function and these are its pins; the coordinator's other half —
/// that the live pair's middle is minted with its halves — is `InkUnderTransformUITests`'.
@MainActor
final class SandwichPresentationLogicTests: XCTestCase {

    private static let all: [SandwichPresentation] = [.disengaged, .rest, .live, .midStroke]
    private static let fits: [LivePairFit] = [.none, .stale, .current]

    /// Distinct keys, cheaply: everything equal but the cut index.
    private func key(_ n: Int) -> SandwichKey {
        SandwichKey(tree: [], activeLayerIndex: n, contents: [], renderResolution: .full,
                    canvasBackgroundColor: .white, isCanvasBackgroundVisible: true)
    }

    private let layerA = UUID()
    private let layerB = UUID()

    func testAStrokeUnderThePenIsAlwaysDrawnLive() {
        for current in Self.all {
            for fit in Self.fits {
                for bake in [false, true] {
                    XCTAssertEqual(SandwichPresentation.next(from: current, strokeIsLive: true,
                                                             bakeIsCurrent: bake, livePair: fit, livePairIsExact: true),
                                   .midStroke, "from \(current), pair \(fit), bake current \(bake)")
                }
            }
        }
    }

    func testABakeForThisKeyIsTheWholePictureOnceNoStrokeIsDown() {
        for current in Self.all {
            for fit in Self.fits {
                XCTAssertEqual(SandwichPresentation.next(from: current, strokeIsLive: false,
                                                         bakeIsCurrent: true, livePair: fit, livePairIsExact: true),
                               .rest, "from \(current), pair \(fit)")
            }
        }
    }

    /// **The latency half.** An edit at rest moves the key; until its bake lands, the pair minted for
    /// it is the newest picture the canvas has, and it goes up.
    func testAnEditsOwnPairGoesUpBeforeItsBake() {
        XCTAssertEqual(SandwichPresentation.next(from: .rest, strokeIsLive: false, bakeIsCurrent: false,
                                                 livePair: .current, livePairIsExact: true), .live)
        XCTAssertEqual(SandwichPresentation.next(from: .disengaged, strokeIsLive: false,
                                                 bakeIsCurrent: false, livePair: .current, livePairIsExact: true), .live,
                       "the first engage: a pair lands before the first bake does")
        XCTAssertEqual(SandwichPresentation.next(from: .live, strokeIsLive: false, bakeIsCurrent: false,
                                                 livePair: .current, livePairIsExact: true), .live)
    }

    /// **Trap 2, unchanged**: a lifted stroke stays on the mid-stroke presentation until its bake
    /// lands, through a pair landing for its key and through one that has not yet.
    func testALiftedStrokeStaysMidStrokeUntilItsBake() {
        for fit in [LivePairFit.stale, .current] {
            XCTAssertEqual(SandwichPresentation.next(from: .midStroke, strokeIsLive: false,
                                                     bakeIsCurrent: false, livePair: fit, livePairIsExact: true), .midStroke,
                           "pair \(fit)")
        }
    }

    /// **The flash half.** A live picture one edit behind is newer than any bake the canvas holds, so
    /// it is kept — and a stale pair is never *entered* from the bake, which is no older than it.
    func testAStalePairIsKeptButNeverEntered() {
        XCTAssertEqual(SandwichPresentation.next(from: .live, strokeIsLive: false, bakeIsCurrent: false,
                                                 livePair: .stale, livePairIsExact: true), .live)
        XCTAssertEqual(SandwichPresentation.next(from: .rest, strokeIsLive: false, bakeIsCurrent: false,
                                                 livePair: .stale, livePairIsExact: true), .rest)
        XCTAssertEqual(SandwichPresentation.next(from: .disengaged, strokeIsLive: false,
                                                 bakeIsCurrent: false, livePair: .stale, livePairIsExact: true), .rest)
    }

    /// A pair cut at another frame or another layer is not a picture of this one; §2.10's previous
    /// bake is.
    func testAPairCutElsewhereFallsBackToTheBake() {
        for current in Self.all {
            XCTAssertEqual(SandwichPresentation.next(from: current, strokeIsLive: false,
                                                     bakeIsCurrent: false, livePair: .none, livePairIsExact: true),
                           .rest, "from \(current)")
        }
    }

    /// **The owner's sequence, pass by pass**, as the coordinator feeds it: draw, lift, the bake
    /// lands, undo, the pair lands, undo again before the bake, the second pair lands, the bake lands.
    /// The property is the one the flash broke — once an edit's live picture is up, the canvas never
    /// steps back to a bake that predates it — and that the edit is shown a rebuild after it lands.
    func testTheOwnersDrawUndoDrawUndoNeverStepsBackToAnOlderBake() {
        var shown = SandwichPresentation.rest
        func pass(stroke: Bool = false, bake: Bool, pair: LivePairFit) -> SandwichPresentation {
            shown = SandwichPresentation.next(from: shown, strokeIsLive: stroke, bakeIsCurrent: bake,
                                              livePair: pair, livePairIsExact: true)
            return shown
        }
        XCTAssertEqual(pass(stroke: true, bake: true, pair: .current), .midStroke, "pen down")
        XCTAssertEqual(pass(bake: false, pair: .stale), .midStroke, "lift: the key moves")
        XCTAssertEqual(pass(bake: false, pair: .current), .midStroke, "the stroke's pair lands")
        XCTAssertEqual(pass(bake: true, pair: .current), .rest, "its bake lands")
        XCTAssertEqual(pass(bake: false, pair: .stale), .rest,
                       "undo: the bake on screen is the newest picture until the undo's pair lands")
        XCTAssertEqual(pass(bake: false, pair: .current), .live, "the undo is on screen")
        XCTAssertEqual(pass(bake: false, pair: .stale), .live,
                       "a second undo before the first one's bake: the bake on hand is from before "
                       + "the FIRST undo, and stepping onto it would put the undone stroke back")
        XCTAssertEqual(pass(bake: false, pair: .current), .live, "the second undo is on screen")
        XCTAssertEqual(pass(bake: true, pair: .current), .rest, "and its bake lands")
    }

    /// **Where the pair is only §5.2's near picture, an edit waits for the bake** — the active
    /// layer's blend or grade would go to normal on the live pair, which is a wrong picture rather
    /// than a stale one, and EFFECT_BACKDROP.md rules the canvas at rest exact.
    func testAnEditWaitsForTheBakeWhereThePairIsNotThePicture() {
        for fit in [LivePairFit.stale, .current] {
            for current in [SandwichPresentation.disengaged, .rest, .live] {
                XCTAssertEqual(SandwichPresentation.next(from: current, strokeIsLive: false, bakeIsCurrent: false,
                                                         livePair: fit, livePairIsExact: false),
                               .rest, "from \(current), pair \(fit)")
            }
        }
    }

    /// …and a stroke is unaffected: the near picture under the pen, and through trap 2, is ruled.
    func testAStrokeIsDrawnLiveWhetherOrNotThePairIsThePicture() {
        XCTAssertEqual(SandwichPresentation.next(from: .rest, strokeIsLive: true, bakeIsCurrent: false,
                                                 livePair: .current, livePairIsExact: false), .midStroke)
        for fit in [LivePairFit.stale, .current] {
            XCTAssertEqual(SandwichPresentation.next(from: .midStroke, strokeIsLive: false, bakeIsCurrent: false,
                                                     livePair: fit, livePairIsExact: false), .midStroke,
                           "trap 2, pair \(fit)")
        }
    }

    func testTheHostDrawsItselfExactlyInTheTwoLivePresentations() {
        XCTAssertFalse(SandwichPresentation.disengaged.activeHostDrawsItself)
        XCTAssertFalse(SandwichPresentation.rest.activeHostDrawsItself)
        XCTAssertTrue(SandwichPresentation.live.activeHostDrawsItself)
        XCTAssertTrue(SandwichPresentation.midStroke.activeHostDrawsItself)
    }

    /// What `canvas.host`'s label publishes, which `LayerUITests`, `BakeWiringUITests` and
    /// `InkUnderTransformUITests` read by string.
    func testThePublishedNames() {
        XCTAssertEqual(Self.all.map(\.rawValue), ["off", "rest", "live", "stroke"])
    }

    // MARK: - LivePairFit

    func testNoPairIsNoFit() {
        XCTAssertEqual(LivePairFit(held: nil, key: key(0), cut: LivePairCut(frame: 0, activeLayerID: layerA)),
                       .none)
    }

    /// Equal keys are byte-identical halves by `SandwichKey`'s sufficiency argument, which holds
    /// across frames — so a pair for this key fits whatever frame it was cut at.
    func testAPairForThisKeyIsCurrentWhereverItWasCut() {
        let held = (key: key(0), cut: LivePairCut(frame: 3, activeLayerID: layerA))
        XCTAssertEqual(LivePairFit(held: held, key: key(0), cut: LivePairCut(frame: 3, activeLayerID: layerA)),
                       .current)
        XCTAssertEqual(LivePairFit(held: held, key: key(0), cut: LivePairCut(frame: 7, activeLayerID: layerA)),
                       .current)
    }

    func testAnOlderPairCutHereIsStale() {
        let held = (key: key(0), cut: LivePairCut(frame: 3, activeLayerID: layerA))
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: LivePairCut(frame: 3, activeLayerID: layerA)),
                       .stale)
    }

    func testAnOlderPairCutAtAnotherFrameOrLayerDoesNotFit() {
        let held = (key: key(0), cut: LivePairCut(frame: 3, activeLayerID: layerA))
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: LivePairCut(frame: 4, activeLayerID: layerA)),
                       .none, "another frame")
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: LivePairCut(frame: 3, activeLayerID: layerB)),
                       .none, "another layer between the halves")
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: nil), .none, "no active layer")
    }
}
