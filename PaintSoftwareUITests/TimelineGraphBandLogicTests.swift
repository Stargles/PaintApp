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

    // MARK: - Stage D3: what a touch on the band means

    /// The band's own height, so a test's y arithmetic is the band's rather than a literal.
    private let band = TimelineGraphBand.height
    private let base = TimelineKeyMarkers.basePixelsPerFrame

    /// Where a channel's key is actually drawn, built from the two mappings under test so a change to
    /// either shows up as a failure here rather than as a test that quietly stopped aiming at a key.
    private func dot(_ channel: TimelineGraphBand.Channel, frame: Int,
                     pixelsPerFrame: CGFloat? = nil) -> CGPoint {
        let ppf = pixelsPerFrame ?? base
        let value = channel.curve.key(atFrame: frame)!.value
        return CGPoint(x: TimelineGraphBand.x(ofFrame: frame, pixelsPerFrame: ppf),
                       y: TimelineGraphBand.y(ofValue: value, in: channel.axis, bandHeight: band))
    }

    /// A blur layer, because `blur.radius` is the parameter whose `modelDomain` (0…128) is genuinely
    /// wider than its `uiRange` (0…64) — which is the case the clamping rule is *about*, and
    /// brightness/contrast cannot exercise it, being unbounded in the model.
    private let radiusID = "blur.radius"
    private func blurredManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: 8)))
        manager.currentLayerIndex = gradeIndex
        return manager
    }

    // MARK: Hit-testing

    /// **The nearest key inside the radius, and nothing outside it** — `CurveEditor.nearestHandle`'s
    /// rule, which matters more here because two channels can key the same frame and their dots then
    /// share an x.
    func testAGrabTakesTheNearestKeyInsideTheRadiusAndNothingOutsideIt() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 2.0), (10, 0.0)]))
        let drawn = channels(manager)
        let brightness = drawn.first { $0.parameterID == brightnessID }!
        let contrast = drawn.first { $0.parameterID == contrastID }!

        // Frame 0: brightness is at the bottom of its axis and contrast at the top, on the same x.
        let low = dot(brightness, frame: 0)
        let high = dot(contrast, frame: 0)
        XCTAssertGreaterThan(low.y, high.y, "PREMISE: the two channels' frame-0 dots are far apart")

        XCTAssertEqual(TimelineGraphBand.nearestKey(to: low, channels: drawn,
                                                    pixelsPerFrame: base, bandHeight: band),
                       TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 0))
        XCTAssertEqual(TimelineGraphBand.nearestKey(to: high, channels: drawn,
                                                    pixelsPerFrame: base, bandHeight: band),
                       TimelineGraphBand.KeyRef(parameterID: contrastID, frame: 0),
                       "The nearest match, not the first channel in the list")

        // **Two keys both inside the radius, with the wrong one first.** Without this the test cannot
        // tell "the nearest match" from "the first channel with anything in range" — the two answers
        // only differ when both are candidates, and every other pair on this fixture is 80 pt apart.
        // `channels` walks `Effect.parameters`, so brightness is index 0 and comes first.
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.5), (10, 0.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        let crowded = channels(manager)
        XCTAssertEqual(crowded.map(\.parameterID), [brightnessID, contrastID], "PREMISE: this order")
        let near = dot(crowded.first { $0.parameterID == contrastID }!, frame: 0)
        let far = dot(crowded.first { $0.parameterID == brightnessID }!, frame: 0)
        let between = CGPoint(x: near.x, y: near.y + 2)
        XCTAssertLessThan(hypot(near.x - between.x, near.y - between.y), TimelineGraphBand.hitRadius)
        XCTAssertLessThan(hypot(far.x - between.x, far.y - between.y), TimelineGraphBand.hitRadius,
                          "PREMISE: the wrong one is a candidate too, which is the whole test")
        XCTAssertEqual(TimelineGraphBand.nearestKey(to: between, channels: crowded,
                                                    pixelsPerFrame: base, bandHeight: band),
                       TimelineGraphBand.KeyRef(parameterID: contrastID, frame: 0),
                       "The nearest of two candidates, not the first one the walk reaches")

        // Just inside and just outside the radius, measured from the same dot along one axis.
        let justInside = CGPoint(x: low.x + TimelineGraphBand.hitRadius - 1, y: low.y)
        let justOutside = CGPoint(x: low.x + TimelineGraphBand.hitRadius + 1, y: low.y)
        XCTAssertNotNil(TimelineGraphBand.nearestKey(to: justInside, channels: drawn,
                                                     pixelsPerFrame: base, bandHeight: band))
        XCTAssertNil(TimelineGraphBand.nearestKey(to: justOutside, channels: drawn,
                                                  pixelsPerFrame: base, bandHeight: band),
                     "Outside the radius is empty band, which is what the marquee needs")
    }

    /// **A key above the top of its axis is still grabbable, from the rim of its own column.**
    ///
    /// The band clips (decision 3) and `modelDomain` is wider than `uiRange`, so a drag can legally
    /// put a key where nothing is drawn. Measuring the hit against the key's true y would make it
    /// permanently unreachable — an unreachable state D3's own gesture had created.
    func testAKeyOutsideTheAxisIsStillGrabbableFromTheRim() {
        let manager = blurredManager()
        // 100 is inside `blur.radius`'s modelDomain (0…128) and above its uiRange (0…64).
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: radiusID,
                                        to: linear([(0, 100.0), (10, 8.0)]))
        let drawn = channels(manager)
        let channel = drawn.first { $0.parameterID == radiusID }!

        let trueY = TimelineGraphBand.y(ofValue: 100, in: channel.axis, bandHeight: band)
        XCTAssertLessThan(trueY, 0, "PREMISE: a radius of 100 is drawn above the band and cut away")

        let rim = CGPoint(x: TimelineGraphBand.x(ofFrame: 0, pixelsPerFrame: base), y: 0)
        XCTAssertEqual(TimelineGraphBand.nearestKey(to: rim, channels: drawn,
                                                    pixelsPerFrame: base, bandHeight: band),
                       TimelineGraphBand.KeyRef(parameterID: radiusID, frame: 0),
                       "…and it can be taken back from the edge of its own column")
    }

    // MARK: The two axes a drag resolves

    /// `value(atY:)` and `y(ofValue:)` are inverses, including outside the axis — which is the half
    /// that matters, since that is where a drag off the top of the band lands.
    func testTheValueAxisRoundTripsBothInsideAndOutsideTheRange() {
        let axis: ClosedRange<Double> = 0...64
        for value in [0.0, 1.0, 32.0, 64.0, 100.0, -20.0] {
            let y = TimelineGraphBand.y(ofValue: value, in: axis, bandHeight: band)
            XCTAssertEqual(TimelineGraphBand.value(atY: y, in: axis, bandHeight: band), value,
                           accuracy: 1e-9, "value \(value)")
        }
    }

    /// **`tapSlop` is smaller than half a frame column at every zoom the pinch can reach**, so a
    /// gesture the view calls a tap can never have carried a key onto another frame.
    ///
    /// Stated against `TimelineKeyMarkers.pixelsPerFrameRange` rather than against `10.5`, which is
    /// that constant's own rule: comparing a number to a copy of itself is green forever, including
    /// on the day somebody widens the pinch range.
    func testATapCanNeverHaveMovedAKeyByAFrameAtAnyZoom() {
        let floor = TimelineKeyMarkers.pixelsPerFrameRange.lowerBound
        XCTAssertLessThan(TimelineGraphBand.tapSlop, floor / 2,
                          "A tap's whole allowance has to be less than half a column at the widest zoom")
        for ppf in [floor, TimelineKeyMarkers.basePixelsPerFrame,
                    TimelineKeyMarkers.pixelsPerFrameRange.upperBound] {
            XCTAssertEqual(TimelineGraphBand.frameDelta(translationX: TimelineGraphBand.tapSlop,
                                                        pixelsPerFrame: ppf), 0, "\(ppf)")
            XCTAssertEqual(TimelineGraphBand.frameDelta(translationX: -TimelineGraphBand.tapSlop,
                                                        pixelsPerFrame: ppf), 0, "\(ppf)")
        }
    }

    /// **The frame delta is the floored inverse and is independent of which key it is asked about** —
    /// the property that lets one number move a whole marquee rigidly.
    func testTheFrameDeltaIsTheSameWhicheverKeyItIsTakenFrom() {
        for ppf in [TimelineKeyMarkers.pixelsPerFrameRange.lowerBound,
                    TimelineKeyMarkers.basePixelsPerFrame,
                    TimelineKeyMarkers.pixelsPerFrameRange.upperBound] {
            for travel in [-3.0, -0.6, 0.0, 0.4, 0.5, 2.7] {
                let dx = CGFloat(travel) * ppf
                let delta = TimelineGraphBand.frameDelta(translationX: dx, pixelsPerFrame: ppf)
                for frame in [0, 1, 7, 250] {
                    XCTAssertEqual(
                        TimelineKeyMarkers.frame(atX: TimelineGraphBand.x(ofFrame: frame,
                                                                          pixelsPerFrame: ppf) + dx,
                                                 pixelsPerFrame: ppf) - frame,
                        delta,
                        "ppf \(ppf), travel \(travel), frame \(frame)")
                }
            }
        }
    }

    /// **A drag of the same *screen* distance means different frames at the two ends of the pinch
    /// range, and the same value.** The x axis belongs to the timeline and the y axis does not.
    func testADragResolvesFramesByZoomAndValuesIndependentlyOfIt() {
        let manager = blurredManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: radiusID,
                                        to: linear([(0, 8.0), (40, 32.0)]))
        let drawn = channels(manager)
        let ref = TimelineGraphBand.KeyRef(parameterID: radiusID, frame: 0)
        // 60 pt right and a sixth of the band up.
        let travel = CGSize(width: 60, height: -(band - TimelineGraphBand.verticalInset * 2) / 6)

        let atDefault = TimelineGraphBand.moves(of: [ref], in: drawn, translation: travel,
                                                pixelsPerFrame: base, bandHeight: band)[ref]
        let pinchedOut = TimelineGraphBand.moves(of: [ref], in: drawn, translation: travel,
                                                 pixelsPerFrame: TimelineKeyMarkers.pixelsPerFrameRange.lowerBound,
                                                 bandHeight: band)[ref]
        XCTAssertEqual(atDefault?.frame, 2, "60 pt is two frames at 30 pt each")
        XCTAssertEqual(pinchedOut?.frame, 6, "…and six at 10.5, because the axis is the timeline's")
        // A sixth of the usable band on a 0…64 axis is 64/6.
        XCTAssertEqual(atDefault?.value ?? 0, 8 + 64.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(pinchedOut?.value ?? 0, atDefault?.value ?? -1, accuracy: 1e-9,
                       "The value axis is the band's own and the pinch does not touch it")
    }

    /// **The clamp is `modelDomain`'s, and `uiRange` is not a wall.** `Effect.swift` says to draw the
    /// axis over `uiRange` and allow a key anywhere in `modelDomain`; clamping to the axis instead
    /// would make the model's own reachable values unreachable through the only UI that edits them.
    func testADragOvershootsUIRangeAndStopsAtModelDomain() {
        let manager = blurredManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: radiusID,
                                        to: linear([(0, 32.0), (40, 8.0)]))
        let drawn = channels(manager)
        let channel = drawn.first { $0.parameterID == radiusID }!
        XCTAssertEqual(channel.uiRange, 0...64)
        XCTAssertEqual(channel.modelDomain, 0...Double(Effect.maxBlurTaps))
        let ref = TimelineGraphBand.KeyRef(parameterID: radiusID, frame: 0)

        // Half a band upward is half of `uiRange` — 32 units — which takes a key at 32 to 64, the
        // top of the axis. A whole band takes it to 96, well outside it and well inside the domain.
        let usable = band - TimelineGraphBand.verticalInset * 2
        let up = TimelineGraphBand.moves(of: [ref], in: drawn,
                                         translation: CGSize(width: 0, height: -usable),
                                         pixelsPerFrame: base, bandHeight: band)[ref]
        XCTAssertEqual(up?.value ?? 0, 96, accuracy: 1e-9,
                       "A key above the axis is a real state — the band cuts it, it is not clamped")

        // Far enough that even `modelDomain` runs out, in both directions.
        let miles = TimelineGraphBand.moves(of: [ref], in: drawn,
                                            translation: CGSize(width: 0, height: -usable * 10),
                                            pixelsPerFrame: base, bandHeight: band)[ref]
        XCTAssertEqual(miles?.value, Double(Effect.maxBlurTaps))
        let down = TimelineGraphBand.moves(of: [ref], in: drawn,
                                           translation: CGSize(width: 0, height: usable * 10),
                                           pixelsPerFrame: base, bandHeight: band)[ref]
        XCTAssertEqual(down?.value, 0, "…and a blur radius stops at zero, which is its identity")
    }

    // MARK: The collision rule

    /// **A key is stopped by its neighbour rather than consuming it.** `AnimationCurve.setKey`
    /// replaces on collision, so travelling onto a neighbour's frame would silently destroy it —
    /// `CurveEditor.moving`'s epsilon guard, made of whole frames.
    func testAKeyIsStoppedByItsNeighbourRatherThanConsumingIt() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (4, 2.0), (5, 1.0)]))
        let drawn = channels(manager)
        let ref = TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 0)

        // Ten frames right, with a neighbour at 4: the answer is 3, not 4 and not 10.
        let far = TimelineGraphBand.moves(of: [ref], in: drawn,
                                          translation: CGSize(width: base * 10, height: 0),
                                          pixelsPerFrame: base, bandHeight: band)[ref]
        XCTAssertEqual(far?.frame, 3, "It stops one short of its neighbour")

        let curve = TimelineGraphBand.applying([ref: far!], to: drawn)[brightnessID]
        XCTAssertEqual(curve?.keys.map(\.frame), [3, 4, 5], "…and nothing was swallowed")

        // And the floor: frames are absolute document frames, so 0 is the wall on the other side.
        let backwards = TimelineGraphBand.moves(of: [TimelineGraphBand.KeyRef(parameterID: brightnessID,
                                                                              frame: 4)],
                                                in: drawn,
                                                translation: CGSize(width: -base * 10, height: 0),
                                                pixelsPerFrame: base, bandHeight: band)
        XCTAssertEqual(backwards.values.first?.frame, 1, "Stopped by the key at 0, not by frame 0")
    }

    /// **And frame 0 itself is a wall, for a key that has no neighbour below it at all.**
    ///
    /// The backwards case above is *not* this one and cannot stand in for it: its curve has a key
    /// sitting on frame 0, so `below` is non-nil and the neighbour arm answers. The floor reaches a
    /// first key through `below`'s `-1` sentinel instead, and nothing exercised that — a curve whose
    /// earliest key is at frame 2, dragged ten frames left, is the only shape that does.
    ///
    /// §3.1 puts a layer channel in absolute document frames and the track begins at x 0, so a
    /// negative frame is a key drawn off the left end of the band where no gesture can reach it back.
    func testTheFirstKeyOfACurveIsStoppedByFrameZero() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(2, 0.0), (8, 2.0)]))
        let drawn = channels(manager)
        let first = TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 2)

        let moves = TimelineGraphBand.moves(of: [first], in: drawn,
                                            translation: CGSize(width: -base * 10, height: 0),
                                            pixelsPerFrame: base, bandHeight: band)
        XCTAssertEqual(moves[first]?.frame, 0, "Ten frames left of frame 2 is frame 0, not frame -8")
        XCTAssertEqual(TimelineGraphBand.applying(moves, to: drawn)[brightnessID]?.keys.map(\.frame),
                       [0, 8])

        // Two frames left is inside the allowance and lands exactly on the floor, so the clamp is
        // pinned at the boundary as well as past it.
        let exact = TimelineGraphBand.moves(of: [first], in: drawn,
                                            translation: CGSize(width: -base * 2, height: 0),
                                            pixelsPerFrame: base, bandHeight: band)
        XCTAssertEqual(exact[first]?.frame, 0)
    }

    /// The other half of the same rule: **an add onto a frame the channel already keys is refused.**
    /// Reachable without a near miss, because at `step > 1` the drawn line and the key's own dot are
    /// deliberately apart, so a tap can be on the line and forty points from the key that owns it.
    func testAnAddOntoAFrameTheChannelAlreadyKeysIsRefused() {
        let manager = gradedManager()
        var stepped = linear([(0, 0.0), (1, 2.0), (10, 1.0)])
        stepped.step = 2
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: stepped)
        let drawn = channels(manager)
        let channel = drawn.first { $0.parameterID == brightnessID }!

        XCTAssertNotNil(TimelineGraphBand.stem(forKeyAt: 1, in: channel.curve),
                        "PREMISE: on twos the key at frame 1 sits off the line it belongs to")
        let onTheLine = CGPoint(
            x: TimelineGraphBand.x(ofFrame: 1, pixelsPerFrame: base),
            y: TimelineGraphBand.y(ofValue: channel.curve.evaluate(at: 1), in: channel.axis,
                                   bandHeight: band))
        XCTAssertNil(TimelineGraphBand.nearestKey(to: onTheLine, channels: drawn,
                                                  pixelsPerFrame: base, bandHeight: band),
                     "PREMISE: and far enough off it that the tap is not a grab")
        XCTAssertEqual(TimelineGraphBand.tap(at: onTheLine, channels: drawn,
                                             pixelsPerFrame: base, bandHeight: band),
                       .nothing,
                       "Adding here would have replaced the key at frame 1 with no gesture that looked destructive")
    }

    // MARK: Tap to add, tap to remove

    /// **A finished touch is a tap only if it never became a drag *and* it went nowhere.**
    ///
    /// The two halves are one conjunction and neither is redundant, which is what a truth table is
    /// for. It shipped as the travel alone, with a comment borrowed from `CurveEditor` explaining
    /// why `didMove` "would be the wrong question" — true there, where the flag is set only after a
    /// handle has been grabbed, and false here, where `updateGraphBandTouch` sets it for the marquee
    /// too before the gesture has decided which kind it is.
    ///
    /// What the missing half cost: press a key, nudge it past `tapSlop`, change your mind, bring the
    /// finger back to where it started and lift. The travel is nothing, so the touch resolved as a
    /// tap — on the key it was carrying, which is a **remove**. The key that was being dragged is
    /// deleted, and (the drag's undo bracket being open, and `setEffectParameterTrack` recording
    /// nothing while one is) with no undo step to bring it back.
    func testATouchIsATapOnlyIfItNeitherMovedNorTravelled() {
        let still = CGSize.zero
        let inside = CGSize(width: TimelineGraphBand.tapSlop - 1, height: 0)
        let sweep = CGSize(width: 200, height: 30)

        XCTAssertTrue(TimelineGraphBand.isTap(didMove: false, translation: still))
        XCTAssertTrue(TimelineGraphBand.isTap(didMove: false, translation: inside),
                      "A fingertip is not a point, which is what `tapSlop` is for")

        XCTAssertFalse(TimelineGraphBand.isTap(didMove: false, translation: sweep), """
            A sweep that began on empty band grabbed nothing, so `didMove` is false — asking only \
            that would call this a tap and drop a key wherever the finger stopped. `CurveEditor`'s \
            own warning, and it still holds here.
            """)
        XCTAssertFalse(TimelineGraphBand.isTap(didMove: true, translation: still), """
            A drag that changed its mind: out past the slop, then back to where it started. Asking \
            only the travel calls this a tap, and a tap on the key it is carrying REMOVES that key — \
            with the drag's bracket open, so `setEffectParameterTrack` records nothing and the \
            deletion cannot be undone. This is the assertion the shipped predicate failed.
            """)
        XCTAssertFalse(TimelineGraphBand.isTap(didMove: true, translation: sweep),
                       "An ordinary drag, which is neither half's disputed case")

        // The boundary is inclusive, matching the `.changed` guard that sets `didMove` on strictly
        // more than `tapSlop` — so no travel is both too far to be a tap and too near to be a drag.
        XCTAssertTrue(TimelineGraphBand.isTap(didMove: false,
                                              translation: CGSize(width: TimelineGraphBand.tapSlop,
                                                                  height: 0)))
        XCTAssertFalse(TimelineGraphBand.isTap(didMove: false,
                                               translation: CGSize(width: TimelineGraphBand.tapSlop + 0.5,
                                                                   height: 0)))
    }

    /// `CurveEditor`'s two halves of one gesture, and the part that has no equivalent there: with
    /// several curves in one band, "add here" has to name one, and proximity is the only
    /// non-arbitrary namer.
    func testATapRemovesAKeyAddsToTheNearestCurveAndOtherwiseDoesNothing() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 2.0), (10, 0.0)]))
        let drawn = channels(manager)
        let brightness = drawn.first { $0.parameterID == brightnessID }!

        XCTAssertEqual(TimelineGraphBand.tap(at: dot(brightness, frame: 10), channels: drawn,
                                             pixelsPerFrame: base, bandHeight: band),
                       .remove(TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 10)))

        // Frame 5, on brightness's own line: the two curves cross at the middle of the band, so aim
        // a quarter of the way up, which is brightness's half and not contrast's.
        let quarter = TimelineGraphBand.y(ofValue: 0.5, in: brightness.axis, bandHeight: band)
        let onBrightness = CGPoint(x: TimelineGraphBand.x(ofFrame: 3, pixelsPerFrame: base), y: quarter)
        XCTAssertEqual(TimelineGraphBand.tap(at: onBrightness, channels: drawn,
                                             pixelsPerFrame: base, bandHeight: band),
                       .add(parameterID: brightnessID, frame: 3, value: 0.5),
                       "The tapped value, not the curve's own there — the dot lands under the finger")

        // Between the two curves at frame 5 and further than `hitRadius` from either: empty band,
        // which is what the marquee needs to exist.
        let farAbove = CGPoint(x: TimelineGraphBand.x(ofFrame: 5, pixelsPerFrame: base),
                               y: TimelineGraphBand.verticalInset)
        XCTAssertEqual(TimelineGraphBand.tap(at: farAbove, channels: drawn,
                                             pixelsPerFrame: base, bandHeight: band),
                       .nothing)
    }

    /// **The nearest *curve*, not the first one in reach** — and it is `nearestKey`'s weakness one
    /// level down, in the same costume §11.4 already found it in twice.
    ///
    /// The test above is the only coverage `nearestChannel` had, and it cannot fail against a
    /// first-match implementation: its two lines are 4 pt and 36 pt from the tap against a
    /// `hitRadius` of 22, so exactly one of them is ever a candidate and "nearest" and "first" are
    /// the same answer. Mutating the `distance < best!.distance` comparison to `best == nil` leaves
    /// the whole suite green. This is the fixture where the two answers differ.
    ///
    /// What it guards is not hypothetical: a grade's two curves cross in the middle of the band —
    /// that same fixture's do — and a tap between them there would add a key to whichever channel
    /// `Effect.parameters` happens to list first rather than to the one under the finger.
    func testATapNamesTheNearestOfTwoCurvesInReachAndNotTheFirst() {
        let manager = gradedManager()
        // Two lines eight points apart at frame 3, with the *far* one first in the walk: `channels`
        // follows `Effect.parameters`, where brightness is index 0 and contrast index 1.
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 0.8), (10, 1.8)]))
        let drawn = channels(manager)
        XCTAssertEqual(drawn.map(\.parameterID), [brightnessID, contrastID], "PREMISE: this order")
        let brightness = drawn.first { $0.parameterID == brightnessID }!
        let contrast = drawn.first { $0.parameterID == contrastID }!

        let column = TimelineGraphBand.x(ofFrame: 3, pixelsPerFrame: base)
        let brightnessY = TimelineGraphBand.y(ofValue: brightness.curve.evaluate(at: 3),
                                              in: brightness.axis, bandHeight: band)
        let contrastY = TimelineGraphBand.y(ofValue: contrast.curve.evaluate(at: 3),
                                            in: contrast.axis, bandHeight: band)
        // Between the two lines and a quarter of the way off the nearer one.
        let between = CGPoint(x: column, y: contrastY - (contrastY - brightnessY) / 4)
        XCTAssertLessThan(abs(contrastY - between.y), abs(brightnessY - between.y),
                          "PREMISE: contrast is the nearer of the two")
        XCTAssertLessThan(abs(brightnessY - between.y), TimelineGraphBand.hitRadius,
                          "PREMISE: and the wrong one is a candidate too, which is the whole test")
        XCTAssertNil(TimelineGraphBand.nearestKey(to: between, channels: drawn,
                                                  pixelsPerFrame: base, bandHeight: band),
                     "PREMISE: no key is in reach, so a tap here is an add and not a remove")

        XCTAssertEqual(TimelineGraphBand.nearestChannel(to: between, channels: drawn,
                                                        pixelsPerFrame: base, bandHeight: band),
                       contrastID,
                       "The nearest line, not the first one the walk finds inside the radius")
        XCTAssertEqual(TimelineGraphBand.tap(at: between, channels: drawn,
                                             pixelsPerFrame: base, bandHeight: band),
                       .add(parameterID: contrastID, frame: 3,
                            value: TimelineGraphBand.value(atY: between.y, in: contrast.axis,
                                                           bandHeight: band)),
                       "…and the tap that rides on it names the same channel")

        // Neither line in reach names nothing, which is what leaves the band's empty space free for
        // the marquee to start in.
        XCTAssertNil(TimelineGraphBand.nearestChannel(to: CGPoint(x: column,
                                                                  y: TimelineGraphBand.verticalInset),
                                                      channels: drawn, pixelsPerFrame: base,
                                                      bandHeight: band))
    }

    // MARK: The marquee

    /// **A rubber band takes what is inside it, whichever way it was drawn**, and the group then
    /// moves as a rigid body: one frame delta for all of them, and a shared travel in *points*
    /// mapped through each channel's own axis.
    func testTheMarqueeTakesTheKeysInsideItAndMovesThemAsOneBody() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (2, 1.0), (20, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(1, 0.0), (20, 2.0)]))
        let drawn = channels(manager)

        // The first three columns, full height — and drawn bottom-right to top-left, so the
        // standardisation is under test too.
        let box = CGRect(x: base * 3, y: band, width: -base * 3, height: -band)
        let picked = TimelineGraphBand.keys(in: box, channels: drawn,
                                            pixelsPerFrame: base, bandHeight: band)
        XCTAssertEqual(picked, [TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 0),
                                TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 2),
                                TimelineGraphBand.KeyRef(parameterID: contrastID, frame: 1)],
                       "Three keys across two channels, and the ones at frame 20 left behind")

        let moves = TimelineGraphBand.moves(of: picked, in: drawn,
                                            translation: CGSize(width: base * 5, height: 0),
                                            pixelsPerFrame: base, bandHeight: band)
        XCTAssertEqual(moves.count, 3)
        XCTAssertEqual(Set(moves.map { $0.value.frame - $0.key.frame }), [5],
                       "One delta for all of them — the selection's shape survives the move")

        let after = TimelineGraphBand.applying(moves, to: drawn)
        XCTAssertEqual(after[brightnessID]?.keys.map(\.frame), [5, 7, 20])
        XCTAssertEqual(after[contrastID]?.keys.map(\.frame), [6, 20])
    }

    /// **The group is clamped by its tightest member, not per key** — the alternative collapses the
    /// selection onto whichever key hit a wall, and dragging back does not restore its shape.
    func testTheGroupIsClampedByItsTightestMember() {
        let manager = gradedManager()
        // The two carried keys are at 0 and 2; the blocker at 6 is not selected, so the leading key
        // may reach 5 and the whole group may travel three frames — not five.
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (2, 1.0), (6, 2.0)]))
        let drawn = channels(manager)
        let picked: Set<TimelineGraphBand.KeyRef> = [
            .init(parameterID: brightnessID, frame: 0), .init(parameterID: brightnessID, frame: 2)
        ]
        let moves = TimelineGraphBand.moves(of: picked, in: drawn,
                                            translation: CGSize(width: base * 20, height: 0),
                                            pixelsPerFrame: base, bandHeight: band)
        XCTAssertEqual(Set(moves.map { $0.value.frame }), [3, 5],
                       "Both moved by three, keeping their two-frame gap")
        XCTAssertEqual(TimelineGraphBand.applying(moves, to: drawn)[brightnessID]?.keys.map(\.frame),
                       [3, 5, 6], "…and the blocker survived")
    }

    /// **A selection sliding into the frames its own leading edge just vacated loses no member.**
    /// `setKey` replaces on collision and the clamp never fires inside a rigid group, so the removals
    /// have to all happen before any insertion — which is the one thing `applying` arranges.
    ///
    /// **This test's kill power depends on `applying` walking its keys in a defined order, and for
    /// most of a day it did not have one.** The walk was a `Dictionary`'s, whose order Swift seeds
    /// per process, and the mutation this test names — insert each key as it is removed — is
    /// harmless when that order comes out descending: each key vacates its frame before the one
    /// behind it arrives. Three keys have six orders and one of them is that one, so the test caught
    /// the defect about five runs in six and was green on the sixth, which is the worst of both
    /// answers. `applying` now sorts ascending, and the slide below is **rightward** deliberately:
    /// that is the pairing in which an interleaved walk destroys two of the three keys every time.
    func testAGroupSlidingOverItsOwnFramesLosesNothing() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (1, 1.0), (2, 2.0)]))
        let drawn = channels(manager)
        let picked: Set<TimelineGraphBand.KeyRef> = [
            .init(parameterID: brightnessID, frame: 0),
            .init(parameterID: brightnessID, frame: 1),
            .init(parameterID: brightnessID, frame: 2)
        ]
        let moves = TimelineGraphBand.moves(of: picked, in: drawn,
                                            translation: CGSize(width: base, height: 0),
                                            pixelsPerFrame: base, bandHeight: band)
        let after = TimelineGraphBand.applying(moves, to: drawn)[brightnessID]
        XCTAssertEqual(after?.keys.map(\.frame), [1, 2, 3])
        XCTAssertEqual(after?.keys.map(\.value), [0.0, 1.0, 2.0], "…and each kept its own value")
    }

    // MARK: What an edit costs, and what follows it

    /// **One drag is one press of Undo, however many channels and ticks it spanned.**
    ///
    /// `setEffectParameterTrack` records one step *per call*, which is right for a discrete edit and
    /// wrong for a gesture — `KeyframeControl.setEffectParameterKeys` states the same problem from the
    /// other side. The bracket is the answer, and this pins the arithmetic the coordinator relies on:
    /// nine writes across three ticks and two channels inside one `beginStructureGesture` /
    /// `commitStructureGesture` pair cost the artist exactly one press.
    func testADragOfManyKeysAcrossManyChannelsIsOneUndoStep() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 2.0), (10, 0.0)]))
        let before = manager.history.undoStack.count
        let startChannels = channels(manager)
        let picked: Set<TimelineGraphBand.KeyRef> = [
            .init(parameterID: brightnessID, frame: 0), .init(parameterID: contrastID, frame: 0)
        ]

        manager.beginStructureGesture()
        for tick in 1...3 {
            let moves = TimelineGraphBand.moves(of: picked, in: startChannels,
                                                translation: CGSize(width: base * CGFloat(tick), height: 4),
                                                pixelsPerFrame: base, bandHeight: band)
            for (id, curve) in TimelineGraphBand.applying(moves, to: startChannels) {
                manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: id, to: curve)
            }
        }
        manager.commitStructureGesture(label: .effectKeyframes)

        XCTAssertEqual(manager.history.undoStack.count - before, 1,
                       "Six writes over three ticks, one undo step")
        XCTAssertEqual(manager.keyframeState(of: target(manager)).tracks[brightnessID]?.keys.map(\.frame),
                       [3, 10], "PREMISE: the drag actually landed")
        manager.undo()
        XCTAssertEqual(manager.keyframeState(of: target(manager)).tracks[brightnessID]?.keys.map(\.frame),
                       [0, 10], "…and one press took all of it back")
        XCTAssertEqual(manager.keyframeState(of: target(manager)).tracks[contrastID]?.keys.map(\.frame),
                       [0, 10])
    }

    /// A single tap is a single write and therefore a single step, with no bracket — the discrete
    /// half of the same rule.
    ///
    /// **And the second half of this test is why `finishGraphBandTouch` closes the drag *before* it
    /// does the tap's write rather than in a `defer` after it.** The bracket that makes a drag one
    /// step is the same mechanism that makes a bare write record *nothing*, so a tap whose write
    /// happened while one was still open would be a deletion committed to the document with no way
    /// back — and the drag then drops that bracket with `cancelStructureGesture`, because a clamped
    /// drag may legitimately have written nothing of its own. The predicate above closes the door
    /// that reaches this state; the ordering closes it a second time, which is what an
    /// unrecoverable deletion is worth.
    func testATapToRemoveIsOneUndoStepOnItsOwn() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (5, 1.0), (10, 2.0)]))
        let before = manager.history.undoStack.count
        var curve = channels(manager).first!.curve
        curve.removeKey(atFrame: 5)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: curve)

        XCTAssertEqual(manager.history.undoStack.count - before, 1)
        manager.undo()
        XCTAssertEqual(manager.keyframeState(of: target(manager)).tracks[brightnessID]?.keys.map(\.frame),
                       [0, 5, 10])

        // The same write with a gesture bracket open: it lands, it reports that it changed
        // something, and it records nothing at all.
        let openBracket = manager.history.undoStack.count
        manager.beginStructureGesture()
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: gradeIndex,
                                                      parameterID: brightnessID, to: curve),
                      "PREMISE: the write itself succeeds either way")
        XCTAssertEqual(manager.keyframeState(of: target(manager)).tracks[brightnessID]?.keys.map(\.frame),
                       [0, 10], "PREMISE: and the key really is gone from the document")
        XCTAssertEqual(manager.history.undoStack.count - openBracket, 0, """
            A write inside a gesture bracket records no step of its own — which is exactly what makes \
            a drag one press of Undo, and exactly what would make a tap's removal unrecoverable if \
            the two were ever allowed to overlap.
            """)
        manager.cancelStructureGesture()
    }

    /// **§2.28: moving a curve key moves the keyframe, because the union is computed and never
    /// stored.** Both device reports of 2026-08-29 were a divergence between the marks and the keyed
    /// frames; the fix was one accessor, and this is the guard that a graph-editor edit goes through
    /// it rather than around it by writing a mark of its own.
    ///
    /// The frame vacated by the key keeps its diamond and becomes **bare**, which is the whole point
    /// of the two kinds: the artist's explicit mark is still there and now carries nothing.
    func testMovingAKeyMovesTheKeyframeUnionAndLeavesABareMarkBehind() {
        let manager = gradedManager()
        manager.addKeyframe(target(manager), atFrame: 0)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 0.0), (10, 2.0)]))
        XCTAssertEqual(manager.keyframes(of: target(manager)).frames, [0, 10])
        XCTAssertEqual(manager.keyframes(of: target(manager)).keyed, [0, 10])

        let drawn = channels(manager)
        let ref = TimelineGraphBand.KeyRef(parameterID: brightnessID, frame: 0)
        let moves = TimelineGraphBand.moves(of: [ref], in: drawn,
                                            translation: CGSize(width: base * 4, height: 0),
                                            pixelsPerFrame: base, bandHeight: band)
        for (id, curve) in TimelineGraphBand.applying(moves, to: drawn) {
            manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: id, to: curve)
        }

        let after = manager.keyframes(of: target(manager))
        XCTAssertEqual(after.frames, [0, 4, 10], "The union followed the key, with no mark written")
        XCTAssertEqual(after.keyed, [4, 10])
        XCTAssertEqual(TimelineKeyMarkers.encode(TimelineKeyMarkers.runs(
            markers: TimelineKeyMarkers.markers(frames: after.frames, keyed: after.keyed),
            pixelsPerFrame: base)), "(0)|4|10",
            "…and the frame it left keeps its explicit mark, now hollow")
    }
}
