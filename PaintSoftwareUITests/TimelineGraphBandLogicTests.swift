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
                                                  visibleX: 0...1_200,
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
                                                  visibleX: 0...10_000,
                                                  pixelsPerFrame: 30, frameCount: 12)
        XCTAssertEqual(sampling?.minX, 0)
        XCTAssertEqual(sampling?.maxX, 360, "12 frames at 30 pt, and no sampling past them")
        XCTAssertNil(TimelineGraphBand.sampling(in: CGRect(x: 500, y: 0, width: 40, height: 96),
                                                visibleX: 0...10_000,
                                                pixelsPerFrame: 30, frameCount: 12),
                     "A dirty rect entirely past the track samples nothing at all")
    }

    /// **The cost is the viewport, not the document.**
    ///
    /// The dirty rect is not a clip on this view: the band's own width *is* the whole laid-out
    /// track, and UIKit hands a full-bounds rect for the no-argument `setNeedsDisplay()` that both
    /// `update` and `layoutSubviews` call — so before `visibleX` the band ran one `evaluate` and one
    /// `addLine` per point of the entire track, per channel, on every redraw. 9,000 pt is an
    /// ordinary 300-frame document at the default zoom and 36,000 pt is the same document at the
    /// 120 pt/frame ceiling; the viewport is ~1,366 pt on this iPad whatever either of those is.
    func testSamplingCostsTheViewportRatherThanTheWholeTrack() {
        let whole = CGRect(x: 0, y: 0, width: 10_000, height: 96)
        guard let sampling = TimelineGraphBand.sampling(in: whole, visibleX: 4_000...4_400,
                                                        pixelsPerFrame: 30, frameCount: 400)
        else { return XCTFail("A viewport inside the track samples something") }
        XCTAssertEqual(sampling.minX, 3_999)
        XCTAssertEqual(sampling.maxX, 4_401)
        XCTAssertEqual(sampling.count, 403, "O(viewport): 400 pt of window, one sample per point")

        // …and the same rect with the whole track on screen is what it used to cost, every time.
        let unclipped = TimelineGraphBand.sampling(in: whole, visibleX: 0...10_000,
                                                   pixelsPerFrame: 30, frameCount: 400)
        XCTAssertEqual(unclipped?.count, 10_002)
        XCTAssertLessThan(sampling.count, (unclipped?.count ?? 0) / 20)
    }

    /// **A clipped curve still has to reach the screen edge.** The slack is applied after both clips
    /// rather than only after the dirty rect, or the polyline stops a point short of the window and
    /// the artist sees the curve end in mid-air at the edge of the timeline.
    func testTheViewportClipKeepsThePolylineContinuousAtBothEdges() {
        guard let sampling = TimelineGraphBand.sampling(in: CGRect(x: 0, y: 0, width: 9_000, height: 96),
                                                        visibleX: 600...1_000,
                                                        pixelsPerFrame: 30, frameCount: 300)
        else { return XCTFail("A viewport inside the track samples something") }
        XCTAssertEqual(sampling.minX, 599, "One point beyond the left edge of the window")
        XCTAssertEqual(sampling.maxX, 1_001, "…and one beyond the right")
    }

    /// A band scrolled entirely off the laid-out track draws nothing rather than a line at frame 0.
    func testAViewportPastTheTrackSamplesNothing() {
        XCTAssertNil(TimelineGraphBand.sampling(in: CGRect(x: 0, y: 0, width: 9_000, height: 96),
                                                visibleX: 5_000...6_000,
                                                pixelsPerFrame: 30, frameCount: 12),
                     "12 frames at 30 pt is 360 pt of track; the window is nowhere near it")
        XCTAssertNil(TimelineGraphBand.sampling(in: CGRect(x: 0, y: 0, width: 9_000, height: 96),
                                                visibleX: 0...0,
                                                pixelsPerFrame: 30, frameCount: 12),
                     "A band with no window yet draws nothing rather than the whole track")
    }

    // MARK: - A key's dot against the line it belongs to

    /// **At `step == 1` the dot is always on the line, and nothing is drawn between them.** This is
    /// every curve in every document today — nothing in the app writes a step above 1 yet (§2.10 is
    /// unbuilt), so this is the case that must stay clean when the other one ships.
    func testAKeysDotSitsOnTheCurveAtEveryStepOfOne() {
        let curve = linear([(0, 0), (5, 10), (9, 2)])
        for key in curve.keys {
            XCTAssertNil(TimelineGraphBand.stem(forKeyAt: key.frame, in: curve),
                         "frame \(key.frame) needs no stem: the line passes through its dot")
        }
        XCTAssertNil(TimelineGraphBand.stem(forKeyAt: 3, in: curve), "…and a frame with no key has none")
    }

    /// **On twos, a key off the step's parity holds a value the animation never outputs**, because
    /// `AnimationCurve.stepped` quantises time *down* onto a multiple of the step, anchored at frame
    /// 0 of the curve's own time base. The dot stays on the key — that is what the artist authored
    /// and what D3 hands them to drag — and the line stays on the animation. What the band draws
    /// where they part is a hairline between the two, so the gap reads as a fact about the step
    /// rather than as a rendering bug.
    func testOnTwosAKeyOffTheStepIsJoinedToTheLineRatherThanMovedOntoIt() {
        let curve = AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 0, interpolation: .linear),
                                          AnimationCurve.Key(frame: 5, value: 10, interpolation: .linear)],
                                   step: 2)
        // Frame 5 evaluates at 4, which is four fifths of the way from 0 to 10.
        XCTAssertEqual(try XCTUnwrap(TimelineGraphBand.stem(forKeyAt: 5, in: curve)), 8, accuracy: 1e-9,
                       "The stem points at what the curve outputs at that frame, not at the key")
        XCTAssertNil(TimelineGraphBand.stem(forKeyAt: 0, in: curve),
                     "A key on the step's own parity is on the line already")

        let onParity = AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 0, interpolation: .linear),
                                             AnimationCurve.Key(frame: 4, value: 8, interpolation: .linear)],
                                      step: 2)
        for key in onParity.keys {
            XCTAssertNil(TimelineGraphBand.stem(forKeyAt: key.frame, in: onParity),
                         "frame \(key.frame) is a multiple of the step, so nothing diverges")
        }
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

    // MARK: - …except while a gesture owns the track

    /// **A selection made by a gesture already in flight must not move the band.**
    ///
    /// The band follows the selection (the ruling above), and selection is a *side effect* of half
    /// the timeline's gestures — `beginBlockDrag` writes `currentLayerIndex` for the layer the block
    /// came from. Following it there reflows the track by 96 pt inside a touch that has already
    /// begun, which detaches the ghost from the finger and, because `layerIndex(atY:)` then resolves
    /// an unmoved finger against moved rows, drops the block on a **different layer**.
    func testAPinnedBandStaysUnderItsOwnRowWhileTheSelectionMoves() {
        let manager = gradedManager()
        manager.isGraphEditorOpen = true
        XCTAssertEqual(manager.graphBandExpansion?.layerIndex, gradeIndex,
                       "PREMISE: open on the selected layer")

        manager.pinGraphBand()
        manager.currentLayerIndex = 0
        XCTAssertEqual(manager.graphBandExpansion?.layerIndex, gradeIndex,
                       "The gesture selected another layer; the band is not allowed to follow yet")
        XCTAssertEqual(manager.graphBandContent?.layerIndex, gradeIndex,
                       "…and what it draws is held with it, so the curves do not change mid-gesture")

        manager.releaseGraphBand()
        XCTAssertEqual(manager.graphBandExpansion?.layerIndex, 0,
                       "The finger is off the track: the band goes where the selection went")
    }

    /// **The pin defers the reflow; it does not cancel it** — and this is the arithmetic the artist
    /// actually feels, one step down from the model.
    ///
    /// Both halves of the timeline build a `TimelineRowLayout` from `graphBandExpansion`, so holding
    /// the expansion holds every row origin either of them derives. `y(ofRow:)` on the row *under*
    /// the band is the one that matters: that is the row a drag most often starts on, and the row
    /// that moves by exactly one band the moment the band arrives above it.
    func testTheRowUnderTheBandDoesNotMoveWhileTheBandIsPinned() {
        let manager = gradedManager()
        manager.currentLayerIndex = 0
        manager.isGraphEditorOpen = true

        // Synthetic rows, so layer *n* is row *n* and the test is about the band rather than about
        // which end of the stack the layer panel puts a new layer on.
        let rows: [LayerStackRow] = (0..<2).map { .layer(id: UUID(), index: $0, depth: 0) }
        func y(ofRow row: Int) -> CGFloat {
            TimelineRowLayout.make(rows: rows, rulerHeight: 18, rowHeight: 34,
                                   expansion: manager.graphBandExpansion).y(ofRow: row)
        }
        let grabbed = 1
        let before = y(ofRow: grabbed)

        manager.pinGraphBand()
        manager.currentLayerIndex = 1
        XCTAssertEqual(y(ofRow: grabbed), before,
                       "The row the finger is on stays exactly where the finger found it")

        manager.releaseGraphBand()
        XCTAssertEqual(before - y(ofRow: grabbed), TimelineGraphBand.height,
                       "…and then moves by exactly one band, because the band arrived above it")
    }

    /// Releasing a pin nobody took is a no-op, which is what lets `endBlockDrag` release
    /// unconditionally at the top rather than pairing the call with the guard that decides whether
    /// there was a drag at all. A pin that outlived its gesture would freeze the band for the
    /// session.
    func testReleasingAnUnpinnedBandChangesNothing() {
        let manager = gradedManager()
        manager.isGraphEditorOpen = true
        manager.releaseGraphBand()
        XCTAssertEqual(manager.graphBandExpansion?.layerIndex, gradeIndex)
    }
}
