import XCTest
import SwiftUI

/// **What the live canvas shows between an edit and its bake** — `SandwichPresentation.next` and
/// `LivePairFit`, TODO (145), and what it shows while a transform is dragged, TODO (125).
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

    private static let all: [SandwichPresentation] = [.disengaged, .rest, .live, .moving, .midStroke]
    private static let fits: [LivePairFit] = [.none, .stale, .current]

    /// `SandwichPresentation.next` with every fact not under test at its quiet value: no transform
    /// edit, and no bands held of this frame.
    private func next(_ current: SandwichPresentation, stroke: Bool = false, edit: Bool = false,
                      bake: Bool, pair: LivePairFit, bands: Bool = false) -> SandwichPresentation {
        SandwichPresentation.next(from: current, strokeIsLive: stroke, transformEditIsLive: edit,
                                  bakeIsCurrent: bake, livePair: pair, holdsBandsOfThisFrame: bands)
    }

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
                    XCTAssertEqual(next(current, stroke: true, bake: bake, pair: fit),
                                   .midStroke, "from \(current), pair \(fit), bake current \(bake)")
                }
            }
        }
    }

    func testABakeForThisKeyIsTheWholePictureOnceNoStrokeIsDown() {
        for current in Self.all {
            for fit in Self.fits {
                XCTAssertEqual(next(current, bake: true, pair: fit),
                               .rest, "from \(current), pair \(fit)")
            }
        }
    }

    /// **The latency half.** An edit at rest moves the key; until its bake lands, the pair minted for
    /// it is the newest picture the canvas has, and it goes up.
    func testAnEditsOwnPairGoesUpBeforeItsBake() {
        XCTAssertEqual(next(.rest, bake: false, pair: .current), .live)
        XCTAssertEqual(next(.disengaged, bake: false, pair: .current), .live,
                       "the first engage: a pair lands before the first bake does")
        XCTAssertEqual(next(.live, bake: false, pair: .current), .live)
    }

    /// **Trap 2, unchanged**: a lifted stroke stays on the mid-stroke presentation until its bake
    /// lands, through a pair landing for its key and through one that has not yet.
    func testALiftedStrokeStaysMidStrokeUntilItsBake() {
        for fit in [LivePairFit.stale, .current] {
            XCTAssertEqual(next(.midStroke, bake: false, pair: fit), .midStroke,
                           "pair \(fit)")
        }
    }

    /// **The flash half.** A live picture one edit behind is newer than any bake the canvas holds, so
    /// it is kept — and a stale pair is never *entered* from the bake, which is no older than it.
    func testAStalePairIsKeptButNeverEntered() {
        XCTAssertEqual(next(.live, bake: false, pair: .stale), .live)
        XCTAssertEqual(next(.rest, bake: false, pair: .stale), .rest)
        XCTAssertEqual(next(.disengaged, bake: false, pair: .stale), .rest)
    }

    /// A pair cut at another frame or another layer is not a picture of this one; §2.10's previous
    /// bake is.
    func testAPairCutElsewhereFallsBackToTheBake() {
        for current in Self.all {
            XCTAssertEqual(next(current, bake: false, pair: .none),
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
            shown = next(shown, stroke: stroke, bake: bake, pair: pair)
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

    /// **The ruled fast picture** (owner, 2026-10-01, TODO (125)): an edit's pair goes up before its
    /// bake on every document, including one where the pair is only §5.2's near picture — the
    /// active layer drawn plain, a blended layer above it composited onto transparency. There is no
    /// exactness fact left in the choice for a document to fail.
    func testAnEditsPairGoesUpWhetherOrNotItIsThePicture() {
        XCTAssertEqual(next(.rest, bake: false, pair: .current), .live)
        XCTAssertEqual(next(.live, bake: false, pair: .stale), .live)
        XCTAssertEqual(next(.live, bake: true, pair: .current), .rest, "and the exact bake replaces it")
    }

    // MARK: - A transform edit's bands (TODO (125))

    /// The finger is down on a transform: its bands are the picture once they are in hand, whatever
    /// the bake says — under the edit the key holds the moving leaves, so the bake for that key is
    /// the picture from *before* the drag, not its result.
    func testATransformEditIsDrawnByItsBandsOnceTheyAreInHand() {
        for current in Self.all where current != .midStroke {
            for bake in [false, true] {
                XCTAssertEqual(next(current, edit: true, bake: bake, pair: .current), .moving,
                               "from \(current), bake current \(bake)")
                XCTAssertEqual(next(current, edit: true, bake: bake, pair: .none), .rest,
                               "from \(current): no bands yet, so the picture already up stays")
            }
        }
    }

    /// A take flips the frame under the bands, and the rebuild that catches up is one in flight:
    /// stale bands are kept. They are never entered — the previous gesture's are not this one's.
    func testStaleBandsAreKeptButNeverEntered() {
        XCTAssertEqual(next(.moving, edit: true, bake: false, pair: .stale), .moving)
        for current in [SandwichPresentation.rest, .live, .disengaged] {
            XCTAssertEqual(next(current, edit: true, bake: false, pair: .stale), .rest, "from \(current)")
        }
    }

    /// A stroke under the pen still wins, edit or no edit.
    func testAStrokeBeatsATransformEdit() {
        XCTAssertEqual(next(.moving, stroke: true, edit: true, bake: false, pair: .current), .midStroke)
    }

    /// **Nothing stale after release**: the bands stay up until a picture of the result lands — the
    /// bake, or the live pair minted for it (whose landing replaces the bands, so the canvas then
    /// holds no bands) — and they are not held for a frame they were not minted at.
    func testBandsStayUpAfterReleaseUntilAPictureOfTheResultLands() {
        XCTAssertEqual(next(.moving, bake: false, pair: .none, bands: true), .moving,
                       "released: neither the bake nor the result's pair has landed")
        XCTAssertEqual(next(.moving, bake: true, pair: .none, bands: true), .rest, "the bake lands")
        XCTAssertEqual(next(.moving, bake: false, pair: .current), .live, "the result's pair lands first")
        XCTAssertEqual(next(.moving, bake: false, pair: .none, bands: false), .rest,
                       "a scrub after release: bands of another frame are not this frame's picture")
        XCTAssertEqual(next(.rest, bake: false, pair: .none, bands: true), .rest,
                       "and bands are never entered without an edit")
    }

    /// **The owner's drag, pass by pass**: touch down before the bands exist, the bands land, ticks
    /// re-pose them, the finger lifts, the result's pair lands, its bake lands. The property is the
    /// one the lag broke — from the bands' landing to the bake's, the canvas never stands on a
    /// picture from before the drag.
    func testTheOwnersDragIsOnItsBandsFromTheirLandingToTheBake() {
        var shown = SandwichPresentation.rest
        func pass(edit: Bool, bake: Bool, pair: LivePairFit, bands: Bool) -> SandwichPresentation {
            shown = next(shown, edit: edit, bake: bake, pair: pair, bands: bands)
            return shown
        }
        XCTAssertEqual(pass(edit: true, bake: true, pair: .none, bands: false), .rest, "touch down")
        XCTAssertEqual(pass(edit: true, bake: true, pair: .current, bands: true), .moving, "the bands land")
        XCTAssertEqual(pass(edit: true, bake: true, pair: .current, bands: true), .moving, "a tick")
        XCTAssertEqual(pass(edit: false, bake: false, pair: .none, bands: true), .moving,
                       "lift: the key moves, and the bake on hand is from before the drag")
        XCTAssertEqual(pass(edit: false, bake: false, pair: .current, bands: false), .live,
                       "the result's pair lands")
        XCTAssertEqual(pass(edit: false, bake: true, pair: .current, bands: false), .rest, "its bake lands")
    }

    func testTheHostDrawsItselfExactlyInTheTwoLivePresentations() {
        XCTAssertFalse(SandwichPresentation.disengaged.activeHostDrawsItself)
        XCTAssertFalse(SandwichPresentation.rest.activeHostDrawsItself)
        XCTAssertFalse(SandwichPresentation.moving.activeHostDrawsItself,
                       "every leaf is in a band while a transform edit is drawn")
        XCTAssertTrue(SandwichPresentation.live.activeHostDrawsItself)
        XCTAssertTrue(SandwichPresentation.midStroke.activeHostDrawsItself)
    }

    /// What `canvas.host`'s label publishes, which `LayerUITests`, `BakeWiringUITests` and
    /// `InkUnderTransformUITests` read by string.
    func testThePublishedNames() {
        XCTAssertEqual(Self.all.map(\.rawValue), ["off", "rest", "live", "moving", "stroke"])
    }

    // MARK: - LivePairFit

    func testNoPairIsNoFit() {
        XCTAssertEqual(LivePairFit(held: nil, key: key(0), cut: LivePairCut.aroundHost(frame: 0, layerID: layerA)),
                       .none)
    }

    /// Equal keys are byte-identical halves by `SandwichKey`'s sufficiency argument, which holds
    /// across frames — so a pair for this key fits whatever frame it was cut at.
    func testAPairForThisKeyIsCurrentWhereverItWasCut() {
        let held = (key: key(0), cut: LivePairCut.aroundHost(frame: 3, layerID: layerA))
        XCTAssertEqual(LivePairFit(held: held, key: key(0), cut: LivePairCut.aroundHost(frame: 3, layerID: layerA)),
                       .current)
        XCTAssertEqual(LivePairFit(held: held, key: key(0), cut: LivePairCut.aroundHost(frame: 7, layerID: layerA)),
                       .current)
    }

    func testAnOlderPairCutHereIsStale() {
        let held = (key: key(0), cut: LivePairCut.aroundHost(frame: 3, layerID: layerA))
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: LivePairCut.aroundHost(frame: 3, layerID: layerA)),
                       .stale)
    }

    func testAnOlderPairCutAtAnotherFrameOrLayerDoesNotFit() {
        let held = (key: key(0), cut: LivePairCut.aroundHost(frame: 3, layerID: layerA))
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: LivePairCut.aroundHost(frame: 4, layerID: layerA)),
                       .none, "another frame")
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: LivePairCut.aroundHost(frame: 3, layerID: layerB)),
                       .none, "another layer between the halves")
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: nil), .none, "no active layer")
    }

    // MARK: - LivePairFit across the two cuts

    /// **A pair is never bands and bands are never a pair**, even at one key: the middle of one is a
    /// host and of the other a picture.
    func testAPictureFitsOnlyACutOfItsOwnKind() {
        let runs = LivePairCut.aroundRuns([[layerA]])
        let host = LivePairCut.aroundHost(frame: 3, layerID: layerA)
        XCTAssertEqual(LivePairFit(held: (key: key(0), cut: runs), key: key(0), cut: host), .none)
        XCTAssertEqual(LivePairFit(held: (key: key(0), cut: host), key: key(0), cut: runs), .none)
    }

    /// Bands fit bands around the same runs — at any frame, since they carry none — and no others.
    func testBandsFitOnlyTheirOwnRuns() {
        let held = (key: key(0), cut: LivePairCut.aroundRuns([[layerA, layerB]]))
        XCTAssertEqual(LivePairFit(held: held, key: key(0), cut: .aroundRuns([[layerA, layerB]])), .current)
        XCTAssertEqual(LivePairFit(held: held, key: key(1), cut: .aroundRuns([[layerA, layerB]])), .stale,
                       "a take's next frame")
        XCTAssertEqual(LivePairFit(held: held, key: key(0), cut: .aroundRuns([[layerA], [layerB]])), .none,
                       "the same leaves moving as two runs are another cut")
    }
}
