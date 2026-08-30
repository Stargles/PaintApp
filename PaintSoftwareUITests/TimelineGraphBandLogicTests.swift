import XCTest
import CoreGraphics

/// **The graph editor band's arithmetic** — KEYFRAMES.md §11.3, stage D2.
///
/// `Views/TimelineTrackView.swift` is not compiled into this target, so nothing about the drawing
/// itself is assertable here and none of it is decided there: `TimelineGraphBand` holds every
/// number the band draws at, and this file is where those numbers are pinned. What the view keeps
/// is `UIBezierPath` and `UIColor`, and `GraphEditorUITests` is the one check that the wiring from a
/// real tap reaches a real band.
///
/// The three owner rulings of 2026-08-29 each have a test below, because each is a decision that
/// looks arbitrary from inside the code and would be "tidied" away by the next reader: the axis is
/// `uiRange` rather than the key extent, the band **clips** an overshoot rather than rescaling for
/// it, and a curve's colour comes from the descriptor table rather than from its position in the
/// drawn list.
@MainActor
final class TimelineGraphBandLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// `KeyframeControlLogicTests`' graded document: an opaque floor under a value layer carrying a
    /// brightness/contrast grade, whose two parameters are `Effect.parameters` indices 0 and 1.
    private let gradeIndex = 1
    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    private func gradedManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        manager.currentLayerIndex = gradeIndex
        return manager
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[gradeIndex].id)
    }

    private func linear(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    private func channels(_ manager: CanvasManager) -> [TimelineGraphBand.Channel] {
        let target = target(manager)
        return TimelineGraphBand.channels(effect: manager.storedEffect(of: target),
                                          tracks: manager.keyframeState(of: target).tracks)
    }

    // MARK: - Which channels the band draws

    /// **The band's channel list and `listedAnimationChannelIDs` are the same list, and they have to
    /// stay so.** Two implementations of one invariant is the defect §2.28 was written about — the
    /// two device reports of 2026-08-29 were a keyframe union computed twice and diverging — so this
    /// pins the ids against the model's own accessor rather than against a literal.
    func testTheBandDrawsExactlyTheChannelsTheModelCallsAnimations() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (6, 0.2)]))

        XCTAssertEqual(channels(manager).map(\.parameterID),
                       manager.listedAnimationChannelIDs(of: target(manager)),
                       "The band asks the same question the channel list does, in the same order")
        XCTAssertEqual(channels(manager).map(\.parameterID), [brightnessID, contrastID],
                       "…which is `Effect.parameters` order, not dictionary order")
    }

    /// **The strict predicate, not the loose one** (§11.5). A channel keyed twice at the same value
    /// is a curve *in force* — the auto-key arm has to see it or an edit routed to the stored base
    /// springs back under the artist's finger — and it is not an animation. Drawing it would put a
    /// flat line in the band with no way to tell it from one that was authored.
    func testAFlatCurveIsInForceAndIsStillNotDrawn() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 1.0)]))

        XCTAssertEqual(manager.curvedEffectChannelIDs(of: target(manager)), [brightnessID],
                       "Fixture: the loose predicate sees it, which is what auto-key runs on")
        XCTAssertEqual(channels(manager).map(\.parameterID), [],
                       "…and the band draws nothing, because it is not an animation")
    }

    /// A layer that is not in effect form grades nothing, so tracks left on it by a kind change are
    /// storage rather than animation — `keyframes(of:)`'s asymmetry, read the same way one file over.
    func testATargetWithNoGradeDrawsNoCurves() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        XCTAssertEqual(TimelineGraphBand.channels(effect: nil,
                                                  tracks: manager.keyframeState(of: target(manager)).tracks)
                        .map(\.parameterID),
                       [])
    }

    /// The band carries `uiRange` and the descriptor position out of the same walk that found the
    /// curve, rather than looking each up again per id against a table `Effect.parameters` rebuilds
    /// on every call.
    func testEachChannelCarriesItsDescriptorPositionAndRange() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        guard let channel = channels(manager).first else { return XCTFail("Fixture: one channel") }
        XCTAssertEqual(channel.parameterID, contrastID)
        XCTAssertEqual(channel.name, "Contrast", "The artist-facing label, for D4's list")
        XCTAssertEqual(channel.descriptorIndex, 1, "Contrast is the second parameter of the grade")
        XCTAssertEqual(channel.uiRange, 0...2)
    }

    // MARK: - The y axis is `uiRange`, and the band clips

    /// `Effect.swift:1301` — *"A graph editor should draw its Y axis over `uiRange` and allow a key
    /// anywhere in [`modelDomain`]"* — a note written for this feature before it existed.
    func testTheAxisIsTheDeclaredRangeNotTheKeys() {
        // Keys nowhere near the ends of 0…2: the axis must not shrink onto them.
        let range = TimelineGraphBand.range(uiRange: 0...2, keyValues: [0.9, 1.1])
        XCTAssertEqual(range, 0...2)
        XCTAssertEqual(TimelineGraphBand.y(ofValue: 1, in: range, bandHeight: 96), 48,
                       "The middle of the declared range is the middle of the band")
    }

    /// The fallback, and only the fallback: 8 of the 33 parameters declare no `uiRange`.
    func testAParameterWithNoDeclaredRangeFallsBackToItsKeys() {
        XCTAssertEqual(TimelineGraphBand.range(uiRange: nil, keyValues: [-4, 0, 6]), -4...6)
        XCTAssertEqual(TimelineGraphBand.range(uiRange: nil, keyValues: [3, 3]), 2.5...3.5,
                       "A flat extent still has to be an axis rather than a division by zero")
        XCTAssertEqual(TimelineGraphBand.range(uiRange: nil, keyValues: []), 0...1)
    }

    /// **The overshoot ruling, which is the one a later reader is most likely to "fix".**
    ///
    /// `AnimationCurve`'s decision 1 is that the output is never clamped, so a bezier between two
    /// in-range keys genuinely leaves `uiRange`. The band cuts it. The assertion that matters is not
    /// only that the overshoot lands outside — it is that the *in-range* keys are drawn at exactly
    /// the same y they would be without it, which is what "clip rather than rescale" means and what
    /// a fit-to-content axis would break.
    func testAnOvershootIsCutAndTheRestOfTheCurveDoesNotMove() {
        let height: CGFloat = 96
        let range = TimelineGraphBand.range(uiRange: 0...2, keyValues: [0, 2])

        let top = TimelineGraphBand.y(ofValue: 2, in: range, bandHeight: height)
        let bottom = TimelineGraphBand.y(ofValue: 0, in: range, bandHeight: height)
        XCTAssertEqual(top, TimelineGraphBand.verticalInset)
        XCTAssertEqual(bottom, height - TimelineGraphBand.verticalInset)

        let over = TimelineGraphBand.y(ofValue: 2.6, in: range, bandHeight: height)
        XCTAssertLessThan(over, 0, "An overshoot leaves the band rather than piling up on its rim")
        XCTAssertFalse(TimelineGraphBand.isInsideBand(over, bandHeight: height))
        XCTAssertTrue(TimelineGraphBand.isInsideBand(top, bandHeight: height))
        XCTAssertTrue(TimelineGraphBand.isInsideBand(bottom, bandHeight: height))

        // The range is a function of the declaration, so the overshoot's presence among the keys
        // changes nothing about where the keys inside the range are drawn.
        let withOvershootKey = TimelineGraphBand.range(uiRange: 0...2, keyValues: [0, 2.6])
        XCTAssertEqual(withOvershootKey, range, "Nothing rescaled")
        XCTAssertEqual(TimelineGraphBand.y(ofValue: 2, in: withOvershootKey, bandHeight: height), top)
    }

    /// Up is more, which is every graph editor's convention and the opposite of the view's own
    /// coordinate direction — the sign is easy to lose and impossible to see in a unit test that
    /// only checks the endpoints are distinct.
    func testMoreValueIsHigherOnTheBand() {
        let range: ClosedRange<Double> = 0...1
        XCTAssertLessThan(TimelineGraphBand.y(ofValue: 0.9, in: range, bandHeight: 96),
                          TimelineGraphBand.y(ofValue: 0.1, in: range, bandHeight: 96))
    }

    // MARK: - The x axis belongs to the timeline

    /// The band's own inverse is the **continuous** one, and it is not
    /// `TimelineKeyMarkers.frame(atX:)`, which floors to a column. Using either for the other's job
    /// puts the curve half a frame off its own key dots.
    func testTimeAtXIsTheExactInverseOfAKeysOwnX() {
        for ppf: CGFloat in [10.5, 30, 120] {
            for frame in [0, 1, 7, 40] {
                let x = TimelineGraphBand.x(ofFrame: frame, pixelsPerFrame: ppf)
                XCTAssertEqual(TimelineGraphBand.time(atX: x, pixelsPerFrame: ppf),
                               Double(frame), accuracy: 1e-9,
                               "frame \(frame) at \(ppf) pt")
                XCTAssertEqual(x, TimelineKeyMarkers.centerX(frame: frame, pixelsPerFrame: ppf),
                               "A key's dot and its marker diamond sit on one vertical line")
            }
        }
    }

    func testSamplingClipsToTheDirtyRectWithOnePointOfSlackEachSide() {
        let sampling = TimelineGraphBand.sampling(in: CGRect(x: 100, y: 0, width: 50, height: 96),
                                                  pixelsPerFrame: 30, frameCount: 40)
        guard let sampling else { return XCTFail("A rect inside the track samples something") }
        XCTAssertEqual(sampling.minX, 99, "One point of slack, so the polyline joins across a tile seam")
        XCTAssertEqual(sampling.maxX, 151)
        XCTAssertEqual(sampling.step, 1, "CurveEditor's density: one sample per point of width")
        XCTAssertEqual(sampling.x(at: 0), 99)
        XCTAssertEqual(sampling.x(at: sampling.count - 1), 151,
                       "The last sample lands on the clip's edge rather than past it")
        XCTAssertGreaterThanOrEqual(sampling.count, 2, "A line, not a point")
    }

    func testSamplingStopsAtTheEndOfTheLaidOutTrack() {
        let sampling = TimelineGraphBand.sampling(in: CGRect(x: 0, y: 0, width: 10_000, height: 96),
                                                  pixelsPerFrame: 30, frameCount: 12)
        XCTAssertEqual(sampling?.minX, 0)
        XCTAssertEqual(sampling?.maxX, 360, "12 frames at 30 pt, and no sampling past them")
        XCTAssertNil(TimelineGraphBand.sampling(in: CGRect(x: 500, y: 0, width: 40, height: 96),
                                                pixelsPerFrame: 30, frameCount: 12),
                     "A dirty rect entirely past the track samples nothing at all")
    }

    // MARK: - Telling the curves apart

    /// **The colour comes from the descriptor table's position, and that is the whole reason it does
    /// not shuffle.** Taking it from the channel's index in the *drawn* list would repaint every
    /// curve below a channel the moment that channel started animating — which happens on an
    /// ordinary slider drag, mid-session, while the artist is looking at the band.
    func testAChannelKeepsItsColourWhenAnotherStartsAnimating() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        guard let before = channels(manager).first else { return XCTFail("Fixture: one channel") }
        XCTAssertEqual(before.parameterID, contrastID)
        let colourBefore = TimelineGraphBand.colour(forDescriptorIndex: before.descriptorIndex)

        // Brightness sorts *above* contrast in the descriptor table, so it takes slot 0 and pushes
        // contrast to position 1 of the drawn list without changing its descriptor index.
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 0.5)]))
        let after = channels(manager)
        XCTAssertEqual(after.map(\.parameterID), [brightnessID, contrastID],
                       "Fixture: contrast really did move down the drawn list")
        XCTAssertEqual(TimelineGraphBand.colour(forDescriptorIndex: after[1].descriptorIndex),
                       colourBefore,
                       "…and its colour did not move with it")
        XCTAssertNotEqual(TimelineGraphBand.colour(forDescriptorIndex: after[0].descriptorIndex),
                          colourBefore,
                          "Two channels of one effect are two colours")
    }

    /// The palette avoids the two hues this surface has already spent: ~211° is the playhead and the
    /// current-layer highlight, ~48° is an interpolation reference, and §2.8 exists so that the two
    /// kinds of "keyframe" are never confused with each other.
    func testThePaletteAvoidsThePlayheadAndTheInterpolationHighlight() {
        for hue in TimelineGraphBand.channelHues {
            XCTAssertGreaterThan(abs(hue - 211), 15, "\(hue)° reads as the playhead's blue")
            XCTAssertGreaterThan(abs(hue - 48), 15, "\(hue)° reads as an interpolation reference")
        }
        for (a, b) in zip(TimelineGraphBand.channelHues, TimelineGraphBand.channelHues.dropFirst()) {
            XCTAssertGreaterThan(abs(a - b), 40, "\(a)° and \(b)° are too close to tell apart")
        }
    }

    /// A ninth animated channel wraps rather than trapping — only `Blur`, `Bloom` and the curve
    /// grades carry more than eight parameters, and a repeated hue is legible because the id is in
    /// the band's accessibility value.
    func testTheColourWrapsRatherThanTrapping() {
        XCTAssertEqual(TimelineGraphBand.colour(forDescriptorIndex: 8),
                       TimelineGraphBand.colour(forDescriptorIndex: 0))
        XCTAssertEqual(TimelineGraphBand.colour(forDescriptorIndex: -1),
                       TimelineGraphBand.colour(forDescriptorIndex: 7),
                       "A negative index is not reachable and must still not crash")
    }

    // MARK: - What a UI test can see

    func testTheEncodedValueNamesEveryChannelAndItsKeyFrames() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (4, 2.0), (11, 0.0)]))
        XCTAssertEqual(TimelineGraphBand.encode(channels(manager)),
                       "brightnessContrast.brightness:0,4,11")
    }

    /// A band opened on a layer that animates nothing says so, rather than coming up blank —
    /// LASSO_MOVE §5.24's rule read across: a surface that caught nothing should report it.
    func testABandOnALayerWithNoAnimationSaysEmpty() {
        XCTAssertEqual(TimelineGraphBand.encode([]), "empty")
        let manager = gradedManager()
        XCTAssertEqual(TimelineGraphBand.encode(channels(manager)), "empty")
    }

    // MARK: - The band's content, as the timeline asks for it

    func testTheBandIsClosedUntilItIsOpened() {
        let manager = gradedManager()
        XCTAssertNil(manager.graphBandExpansion, "Closed by default — it is transient view state")
        XCTAssertNil(manager.graphBandContent)
    }

    /// It follows the selection rather than being pinned to the layer it was opened on — the owner's
    /// scope ruling, and the reason the state is one `Bool` rather than a set.
    func testTheOpenBandFollowsTheSelectedLayer() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.isGraphEditorOpen = true

        XCTAssertEqual(manager.graphBandExpansion?.layerIndex, gradeIndex)
        XCTAssertEqual(manager.graphBandExpansion?.height, TimelineGraphBand.height)
        XCTAssertEqual(manager.graphBandContent?.channels.map(\.parameterID), [brightnessID])

        manager.currentLayerIndex = 0
        XCTAssertEqual(manager.graphBandExpansion?.layerIndex, 0, "It moved with the selection")
        XCTAssertEqual(manager.graphBandContent?.channels, [],
                       "…and the floor animates nothing, so the band is open and empty")
    }
}
