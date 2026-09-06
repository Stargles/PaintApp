import XCTest
import UIKit

/// **The timeline's key markers** — KEYFRAMES.md stage 3b, the half the artist can see.
///
/// **Read the target membership before believing a pin here.** `Views/TimelineTrackView.swift` and
/// `Views/AnimationTimeline.swift` are **not** compiled into `PaintSoftwareUITests`, so a test written
/// against either is silently a pin against nothing — the trap commit `6a396e1` was written to record.
/// Everything this stage decides therefore lives in `TimelineKeyMarkers`, which is in the target, and
/// the view holds only CoreGraphics calls. What is *not* pinnable here is whether the diamonds are
/// visible on screen; that is a picture, and it was taken.
///
/// The three questions the file is organised around:
///
/// - **What is a marker?** One per (target, frame), however many channels key there — the channel
///   collapse, which is unconditional. The frame set is the **union** of the target's keyframe marks
///   and its curves' keys, because neither list contains the other; that union is
///   `CanvasManager.keyframeFrames(of:)`, so these tests take it from there rather than from a second
///   copy.
/// - **How many kinds of marker are there?** One. There were two — a hollow form for a frame the
///   artist marked and no channel keyed — and the owner had it removed on 2026-09-03: a node in the
///   graph editor and an indicator on the cel are the same thing, so a greyed third state is
///   something to read and act on that says nothing.
/// - **What happens when markers touch?** The zoom collapse, which is the interesting one, and which
///   is pinned against the timeline's own pinch limits rather than against numbers re-typed here.
@MainActor
final class TimelineKeyMarkersLogicTests: XCTestCase {

    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    /// The two ends of the pinch range, named so a test reads as the zoom the artist is at.
    private var floorZoom: CGFloat { TimelineKeyMarkers.pixelsPerFrameRange.lowerBound }
    private var defaultZoom: CGFloat { TimelineKeyMarkers.basePixelsPerFrame }

    /// **The band's markers for a state a writer would be holding mid-edit.** The union is the
    /// model's — `CanvasManager.keyframeFrames(of:marks:tracks:)`, the one accessor — asked against a
    /// real graded document so the grade asymmetry it carries is in force. `TimelineLayoutKey.make`
    /// asks the same question the same way, so the assertions below are about the band the artist
    /// sees rather than about a fixture's own arithmetic.
    private func markerRow(marks: [Int], tracks: [String: AnimationCurve]) -> [Int] {
        let manager = gradedManager()
        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        return manager.keyframeFrames(of: target, marks: marks, tracks: tracks)
    }

    /// The same against a document's stored state, through the accessor production reads.
    private func markerRow(_ manager: CanvasManager, _ target: KeyframeTarget) -> [Int] {
        manager.keyframeFrames(of: target)
    }

    /// An opaque floor under a value layer carrying a brightness/contrast grade — the fixture
    /// `KeyframeControlLogicTests` and `TimelineGraphBandLogicTests` both use, so a track written
    /// against `brightnessID` is one the layer really grades through.
    private func gradedManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        return manager
    }

    private func curve(_ frames: [Int]) -> AnimationCurve {
        AnimationCurve(keys: frames.map { AnimationCurve.Key(frame: $0, value: Double($0),
                                                            interpolation: .linear) })
    }

    // MARK: - The threshold is a relationship, not a number

    /// **A collapse the artist cannot reach is dead code, and one that fires at the default zoom is a
    /// timeline that lies about how many keys it has.** Both ends have to be pinned, and both have to
    /// be pinned against `TimelineKeyMarkers`' own copy of the pinch limits rather than against a
    /// `10.5` re-typed here — `TimelineTrackView` is not in this target, so a literal would be a
    /// constant compared to a copy of a constant, green forever including on the day the pinch range
    /// moves. This is `KeyframeControl`'s `4 < 6` argument one feature over.
    func testTheCollapseThresholdSitsInsideTheZoomRangeAtBothEnds() {
        XCTAssertGreaterThan(TimelineKeyMarkers.minimumSeparation,
                             TimelineKeyMarkers.pixelsPerFrameRange.lowerBound,
                             "Fully pinched out, adjacent frames must actually collapse — otherwise the collapsed form is unreachable and this design does nothing")
        XCTAssertLessThanOrEqual(TimelineKeyMarkers.minimumSeparation,
                                 TimelineKeyMarkers.basePixelsPerFrame,
                                 "At the unzoomed default, keys on adjacent frames have room and must be drawn one at a time")
        XCTAssertEqual(TimelineKeyMarkers.minimumSeparation,
                       TimelineKeyMarkers.markerWidth + TimelineKeyMarkers.markerGap,
                       "The threshold is derived from what a marker measures, not chosen — two diamonds are legible apart exactly while there is daylight between them")
    }

    /// The band has to fit a marker, or the diamonds are clipped by their own strip.
    func testTheBandIsTallerThanTheMarkerItHolds() {
        XCTAssertGreaterThan(TimelineKeyMarkers.bandHeight, TimelineKeyMarkers.markerWidth)
        XCTAssertLessThan(TimelineKeyMarkers.runBarHeight, TimelineKeyMarkers.markerWidth,
                          "The bar joining a run must be thin enough that its end diamonds still read as diamonds")
    }

    // MARK: - Collapse (1): channels

    /// **Thirteen channels keyed on one frame are one marker.** This is the ruling in the brief —
    /// the artist needs to see *a key is here*, not a stack of overlapping dots — and it is decided
    /// here, at the frame set, so the count is a property of the document rather than of the drawing.
    func testEveryChannelKeyedOnOneFrameProducesOneMarker() {
        let markers = markerRow(marks: [], tracks: [
            brightnessID: curve([4]),
            contrastID: curve([4])
        ])
        XCTAssertEqual(markers, [4], "Two channels, one frame, one marker")
    }

    func testChannelsKeyedOnDifferentFramesProduceOneMarkerEach() {
        let markers = markerRow(marks: [], tracks: [
            brightnessID: curve([0, 8]),
            contrastID: curve([4, 8])
        ])
        XCTAssertEqual(markers, [0, 4, 8],
                       "The union, deduped — frame 8 is keyed twice and drawn once")
    }

    /// **The order is not cosmetic.** This array goes into `TimelineLayoutKey`, which is an
    /// `Equatable` memoization gate, and `Dictionary.values` has no defined order. An unsorted result
    /// would make the key unequal to itself at random, turning the layout gate off in a way that
    /// looks like a performance regression with no cause and no failing test.
    func testTheFrameListIsAscendingWhateverOrderTheChannelsAreIn() {
        let a = markerRow(marks: [], tracks: [brightnessID: curve([9, 2]),
                                                               contrastID: curve([5])])
        let b = markerRow(marks: [], tracks: [contrastID: curve([5]),
                                                               brightnessID: curve([2, 9])])
        XCTAssertEqual(a, [2, 5, 9])
        XCTAssertEqual(a, b, "Two dictionaries with the same content must produce the same array")
    }

    /// The marks arrive sorted from the model, but the union is a `Set` and only this sort decides
    /// what comes out — so an out-of-order input must not survive into the layout key.
    func testTheUnionIsAscendingWhateverOrderTheMarksArriveIn() {
        XCTAssertEqual(markerRow(marks: [9, 2, 5], tracks: [:]), [2, 5, 9])
    }

    func testATargetWithNothingOnItHasNoMarkers() {
        XCTAssertEqual(markerRow(marks: [], tracks: [:]), [])
        XCTAssertEqual(markerRow(marks: [], tracks: [brightnessID: AnimationCurve()]), [],
                       "A channel whose curve is empty animates nothing and draws nothing")
    }

    // MARK: - The union

    /// **The whole of §2.26's first step.** A keyframe is placed and nothing is saved onto it; if that
    /// draws nothing the artist places A blind and the feature cannot be used. It is a marker, and it
    /// is the *same* marker as one that carries a key — the owner's rule of 2026-09-03, which took the
    /// second form away.
    func testAMarkWithNoKeyOnItIsStillAMarker() {
        XCTAssertEqual(markerRow(marks: [3], tracks: [:]), [3])
    }

    /// **A key with no mark is a marker too**, and it is a case that really occurs: §2.26 says a
    /// curve carries keys the artist never marked — an auto-key at the playhead, or a value seeded
    /// onto a neighbouring mark. So the union cannot be derived from the marks either.
    func testAKeyWithNoMarkOnItIsAMarker() {
        XCTAssertEqual(markerRow(marks: [], tracks: [brightnessID: curve([7])]),
                       [7])
    }

    /// The mixed row draws as one row: the artist's mark at 0 has taken a value and the one at 12 has
    /// not, and both are keyframes.
    func testAMarkThatHasTakenAKeyAndOneThatHasNotAreTheSameKindOfMarker() {
        XCTAssertEqual(markerRow(marks: [0, 12], tracks: [brightnessID: curve([0])]),
                       [0, 12])
    }

    // MARK: - Collapse (2): zoom

    func testOneKeyIsOneUncollapsedMarkerAtEveryZoom() {
        for zoom in [floorZoom, defaultZoom, TimelineKeyMarkers.pixelsPerFrameRange.upperBound] {
            let runs = TimelineKeyMarkers.runs(frames: [6], pixelsPerFrame: zoom)
            XCTAssertEqual(runs, [TimelineKeyMarkers.Run(firstFrame: 6, lastFrame: 6, count: 1)])
            XCTAssertFalse(runs[0].isCollapsed, "A run of one is a key, not a collapse")
        }
    }

    func testAtTheDefaultZoomAdjacentFramesAreStillDrawnApart() {
        let runs = TimelineKeyMarkers.runs(frames: [4, 5, 6], pixelsPerFrame: defaultZoom)
        XCTAssertEqual(runs.count, 3, "30 pt of column is far more room than a 9 pt diamond needs")
        XCTAssertTrue(runs.allSatisfy { !$0.isCollapsed })
    }

    func testAtTheMinimumZoomAdjacentFramesCollapseIntoOneRun() {
        let runs = TimelineKeyMarkers.runs(frames: [4, 5, 6, 7], pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs, [TimelineKeyMarkers.Run(firstFrame: 4, lastFrame: 7, count: 4)],
                       "Chaining is the behaviour wanted: four keys with no daylight anywhere between them are one dense region, not two pairs")
        XCTAssertTrue(runs[0].isCollapsed)
    }

    /// **The collapse must not swallow "on twos"**, which §2.10 makes a first-class thing this feature
    /// can produce. A key every other frame is a legible, countable rhythm at every zoom the artist
    /// can reach, and a timeline that drew it as a bar would be hiding the difference between ink on
    /// twos and a run recorded on every frame — the one distinction §2.10 exists to preserve.
    func testKeysOnTwosStayCountableEvenFullyPinchedOut() {
        let runs = TimelineKeyMarkers.runs(frames: [0, 2, 4, 6], pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs.count, 4)
        XCTAssertTrue(runs.allSatisfy { !$0.isCollapsed })
    }

    /// **The rule is per-neighbour, not a global "the zoom is low" flag**, and this is the test that
    /// says so. At the minimum zoom a dense burst collapses while a key forty frames away stays its
    /// own diamond — only the parts of the track that actually collide lose detail.
    func testOnlyTheDensePartOfATrackCollapses() {
        let runs = TimelineKeyMarkers.runs(frames: [0, 1, 2, 40], pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs, [TimelineKeyMarkers.Run(firstFrame: 0, lastFrame: 2, count: 3),
                              TimelineKeyMarkers.Run(firstFrame: 40, lastFrame: 40, count: 1)])
    }

    /// **A collapsed run keeps its two ends exactly.** That is the whole contract of the collapsed
    /// form: where the animation starts and where it stops survive, and only which interior frames
    /// carry keys is given up — which is what zooming in is for.
    func testACollapsedRunReportsItsRealFirstAndLastFrames() {
        let runs = TimelineKeyMarkers.runs(frames: [12, 13, 14, 15, 16], pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs.first?.firstFrame, 12)
        XCTAssertEqual(runs.first?.lastFrame, 16)
        XCTAssertEqual(runs.first?.count, 5)
    }

    func testNoKeysIsNoRuns() {
        XCTAssertEqual(TimelineKeyMarkers.runs(frames: [], pixelsPerFrame: defaultZoom), [])
    }

    // MARK: - Geometry

    /// **The playhead is a column of width `pixelsPerFrame`, not a hairline** (§10), so a marker on
    /// the current frame has to sit *inside* that band rather than on its leading edge — an
    /// edge-aligned marker reads as belonging to the frame before it. Centring in the column is what
    /// makes "the key is on the frame the playhead is over" true on screen and not merely in the data.
    func testAMarkerSitsInsideItsOwnFrameColumn() {
        for zoom in [floorZoom, defaultZoom] {
            for frame in [0, 1, 37] {
                let center = TimelineKeyMarkers.centerX(frame: frame, pixelsPerFrame: zoom)
                let column = CGRect(x: TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: zoom),
                                    y: 0, width: zoom, height: 1)
                XCTAssertGreaterThan(center, column.minX)
                XCTAssertLessThan(center, column.maxX)
                XCTAssertEqual(center, column.midX, accuracy: 0.0001)
            }
        }
    }

    /// The inverse mapping, pinned as a round trip. **Nothing drags a key yet** — that is the graph
    /// editor's stage — but this is what it will need, and pinning it now is what makes "the geometry
    /// will not have to be redone" a claim with a test behind it rather than an assurance.
    func testAPointOnTheBandMapsBackToTheFrameItsMarkerBelongsTo() {
        for zoom in [floorZoom, defaultZoom] {
            for frame in [0, 3, 91] {
                let center = TimelineKeyMarkers.centerX(frame: frame, pixelsPerFrame: zoom)
                XCTAssertEqual(TimelineKeyMarkers.frame(atX: center, pixelsPerFrame: zoom), frame)
            }
        }
    }

    func testASingleKeysRectIsExactlyOneMarkerWide() {
        let run = TimelineKeyMarkers.Run(firstFrame: 5, lastFrame: 5, count: 1)
        let rect = TimelineKeyMarkers.rect(for: run, pixelsPerFrame: defaultZoom,
                                           bandHeight: TimelineKeyMarkers.bandHeight)
        XCTAssertEqual(rect.width, TimelineKeyMarkers.markerWidth, accuracy: 0.0001)
        XCTAssertEqual(rect.midX,
                       TimelineKeyMarkers.centerX(frame: 5, pixelsPerFrame: defaultZoom),
                       accuracy: 0.0001)
        XCTAssertEqual(rect.midY, TimelineKeyMarkers.bandHeight / 2, accuracy: 0.0001,
                       "Vertically centred in the band, so the diamond is not clipped at either edge")
    }

    func testACollapsedRunsRectReachesFromItsFirstKeyToItsLast() {
        let run = TimelineKeyMarkers.Run(firstFrame: 2, lastFrame: 9, count: 8)
        let rect = TimelineKeyMarkers.rect(for: run, pixelsPerFrame: floorZoom,
                                           bandHeight: TimelineKeyMarkers.bandHeight)
        XCTAssertEqual(rect.minX,
                       TimelineKeyMarkers.centerX(frame: 2, pixelsPerFrame: floorZoom)
                           - TimelineKeyMarkers.markerWidth / 2,
                       accuracy: 0.0001)
        XCTAssertEqual(rect.maxX,
                       TimelineKeyMarkers.centerX(frame: 9, pixelsPerFrame: floorZoom)
                           + TimelineKeyMarkers.markerWidth / 2,
                       accuracy: 0.0001,
                       "The capping diamonds are inside the rect, so the bar between them is exactly centre-to-centre")
    }

    // MARK: - The pinch anchor (TODO 39a)

    /// **The reported defect, and the assertion has to be taken at a non-zero scroll offset or it
    /// cannot see it.** `TimelineTrackView` read the fingers' x out of the scroll view — which is
    /// content space, since a scroll view's `bounds.origin` *is* its `contentOffset` — and then
    /// added `contentOffset.x` to it as though it were viewport space. The anchor therefore landed
    /// `contentOffset.x · (scale − 1)` points out, which is **exactly zero at frame 0** and grows
    /// with the scroll. A pinch test written at the left edge of the track is green against the bug
    /// and against the fix alike, which is why the offsets below start at 300.
    ///
    /// **The conversion is done by UIKit rather than restated here**, because "is `location(in:)`
    /// content space or viewport space" is the whole question and a test that answers it by
    /// re-typing `offset + x` would be pinning the same mistake it exists to catch.
    /// `UIGestureRecognizer.location(in:)` is `convert(_:to:)` from the window; this asks a real
    /// `UIScrollView` at a real `contentOffset` the same thing.
    func testAPinchKeepsTheFrameUnderTheFingersAtAnyScrollOffset() {
        let viewportWidth: CGFloat = 400
        // Fingers 120 pt in from the track's left edge — the thing that must not move.
        let fingerInViewport: CGFloat = 120
        for contentOffsetX in [CGFloat(600), 750, 1234.5] {
            for (startZoom, endZoom) in [(CGFloat(30), CGFloat(60)), (30, 10.5), (120, 30)] {
                let container = UIView(frame: CGRect(x: 0, y: 0, width: viewportWidth, height: 100))
                let scrollView = UIScrollView(frame: container.bounds)
                container.addSubview(scrollView)
                scrollView.contentOffset.x = contentOffsetX

                let locationInContent = container
                    .convert(CGPoint(x: fingerInViewport, y: 50), to: scrollView).x
                // Derived from the fixture, not from the code under test: content x over zoom.
                let expectedFrame = (contentOffsetX + fingerInViewport) / startZoom

                let anchor = TimelineKeyMarkers.PinchAnchor(locationInContent: locationInContent,
                                                            contentOffsetX: contentOffsetX,
                                                            pixelsPerFrame: startZoom)
                // Wide enough at every zoom in the table that nothing here is clamped — the clamp is
                // the next test's subject, and letting it fire in this one would hide the anchor.
                // The right edge is bought with a huge `contentWidth`; the **left** edge is bought by
                // the offsets in the table, and this is the assertion that says so rather than
                // leaving the next person to lower one and get a mystery red.
                XCTAssertGreaterThanOrEqual(expectedFrame * endZoom - fingerInViewport, 0, """
                    Fixture: at \(contentOffsetX)/\(startZoom)→\(endZoom) the anchor wants a negative \
                    offset, so the track stops at its left edge and cannot honour it. That is right, \
                    and it is `testThePinchOffsetIsClampedToWhatTheTrackCanScrollTo`'s subject.
                    """)
                let contentWidth: CGFloat = 100_000
                let newOffset = anchor.contentOffsetX(pixelsPerFrame: endZoom,
                                                      contentWidth: contentWidth,
                                                      viewportWidth: viewportWidth)
                let frameUnderFingersNow = (newOffset + fingerInViewport) / endZoom
                XCTAssertEqual(frameUnderFingersNow, expectedFrame, accuracy: 0.0001, """
                    Pinching \(startZoom)→\(endZoom) pt/frame at content offset \(contentOffsetX) \
                    must leave frame \(expectedFrame) under the fingers
                    """)
            }
        }
    }

    /// The anchor can ask for an offset the track cannot reach — pinch out far enough and the frame
    /// under the fingers would need the content to start left of zero. Both ends are clamped, and
    /// the far end is clamped to the same `contentSize − bounds` a scroll view would stop at itself.
    func testThePinchOffsetIsClampedToWhatTheTrackCanScrollTo() {
        let anchor = TimelineKeyMarkers.PinchAnchor(locationInContent: 400,
                                                    contentOffsetX: 300,
                                                    pixelsPerFrame: 30)
        XCTAssertEqual(anchor.contentOffsetX(pixelsPerFrame: 1, contentWidth: 5_000, viewportWidth: 400), 0,
                       "Pinched right out, the anchor wants a negative offset and the track stops at its left edge")
        XCTAssertEqual(anchor.contentOffsetX(pixelsPerFrame: 400, contentWidth: 1_000, viewportWidth: 400), 600,
                       "Pinched right in, it stops where the scroll view itself would: contentSize − bounds")
        XCTAssertEqual(anchor.contentOffsetX(pixelsPerFrame: 30, contentWidth: 200, viewportWidth: 400), 0,
                       "A track narrower than its viewport has nowhere to scroll to at all")
    }

    /// A pinch that does not change the scale must not move the track, at any offset — the identity
    /// case, and the one that says the two spaces are being crossed in both directions consistently
    /// rather than merely cancelling for one particular zoom ratio.
    func testAPinchThatChangesNothingLeavesTheOffsetWhereItWas() {
        for contentOffsetX in [CGFloat(0), 300, 1234.5] {
            let anchor = TimelineKeyMarkers.PinchAnchor(locationInContent: contentOffsetX + 120,
                                                        contentOffsetX: contentOffsetX,
                                                        pixelsPerFrame: 30)
            XCTAssertEqual(anchor.contentOffsetX(pixelsPerFrame: 30,
                                                 contentWidth: 100_000,
                                                 viewportWidth: 400),
                           contentOffsetX, accuracy: 0.0001)
        }
    }

    // MARK: - Gridlines (TODO 38a): the timeline and the graph editor share one column x

    /// **The load-bearing relationship, and the reason `columnX` is not just `centerX` minus a
    /// constant re-typed here.** A gridline (`columnX`) marks the boundary between two frames; a key
    /// marker (`centerX`) sits at the middle of one. If a gridline for frame N and the marker for
    /// frame N are the same feature reading off two different formulas, this is the one algebraic
    /// fact that has to hold for every zoom: the marker sits exactly half a column to the right of
    /// its own frame's line, for any `(frame, pixelsPerFrame)` — not just the pair this test happens
    /// to pick. Break either function's offset (drop the `+ 0.5`, or add one to `columnX`) and this
    /// goes red; it does not go red for a bug that leaves both conventions internally self-consistent
    /// but wrong in the same direction, which is the one thing an equality against a re-typed number
    /// would not catch either.
    func testAGridlineSitsHalfAColumnBeforeItsFramesMarker() {
        for zoom in [floorZoom, defaultZoom, TimelineKeyMarkers.pixelsPerFrameRange.upperBound] {
            for frame in [0, 1, 37, 250] {
                let line = TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: zoom)
                let marker = TimelineKeyMarkers.centerX(frame: frame, pixelsPerFrame: zoom)
                XCTAssertEqual(marker - line, zoom / 2, accuracy: 0.0001)
            }
        }
    }

    /// **Gridlines segment the timeline — they have to tile with no gap and no overlap.** The line
    /// for frame N+1 is exactly one column-width to the right of frame N's, at every zoom in the
    /// pinch range, which is what makes the space between two consecutive lines legible as "frame N"
    /// with nothing left over and nothing double-covered.
    func testConsecutiveGridlinesAreExactlyOneColumnApart() {
        for zoom in [floorZoom, defaultZoom, TimelineKeyMarkers.pixelsPerFrameRange.upperBound] {
            for frame in [0, 1, 37, 250] {
                let here = TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: zoom)
                let next = TimelineKeyMarkers.columnX(frame: frame + 1, pixelsPerFrame: zoom)
                XCTAssertEqual(next - here, zoom, accuracy: 0.0001)
            }
        }
    }

    /// A point sitting exactly on a gridline belongs to the frame the line opens — the same inverse
    /// `centerX`'s own round-trip test uses, now checked at the boundary rather than at the middle.
    /// `TimelineGraphBand.frameDelta` and the ruler's own scrub both resolve a touch through this
    /// function, so this is what makes a tap that lands exactly on a drawn line resolve to the frame
    /// on its right rather than the one it closes.
    func testAPointOnAGridlineMapsToTheFrameItOpens() {
        for zoom in [floorZoom, defaultZoom] {
            for frame in [0, 1, 37, 250] {
                let line = TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: zoom)
                XCTAssertEqual(TimelineKeyMarkers.frame(atX: line, pixelsPerFrame: zoom), frame)
            }
        }
    }

    /// **Density needed no decision beyond the one the pinch already makes.** A gridline is a 1 pt
    /// hairline; `minimumSeparation` (12 pt) is the distance a 9 pt marker *diamond* needs to keep
    /// from its neighbour before the pair reads as one serrated shape. Pinning that the floor of the
    /// zoom range still leaves several hairline-widths of daylight between two adjacent columns is
    /// what backs "every frame, at every zoom, no thinning" rather than that being an assertion
    /// about a screenshot nobody re-checks when the pinch range moves.
    func testTheZoomFloorLeavesRoomForAGridlineOnEveryFrame() {
        let apart = TimelineKeyMarkers.columnX(frame: 1, pixelsPerFrame: floorZoom)
            - TimelineKeyMarkers.columnX(frame: 0, pixelsPerFrame: floorZoom)
        XCTAssertGreaterThan(apart, TimelineKeyMarkers.gridlineWidth * 5,
                             "Adjacent gridlines at the most zoomed-out pinch step still clear five line-widths of daylight")
    }

    // MARK: - What a UI test can read

    /// The band publishes one encoded value rather than one element per marker — `CurveEditor`'s
    /// `encode(points)` convention and `TimelineFolderRowView`'s. It exists because XCUITest can see
    /// neither a `CGContext` nor a colour, and the collapse is *only* visible as a shape, so without
    /// this the thing this stage designs would be unassertable above this tier.
    func testTheAccessibilityValueSaysWhichMarkersAreCollapsed() {
        let runs = TimelineKeyMarkers.runs(frames: [0, 1, 2, 40], pixelsPerFrame: floorZoom)
        XCTAssertEqual(TimelineKeyMarkers.encode(runs), "0-2|40")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: [0, 1, 2, 40], pixelsPerFrame: defaultZoom)),
                       "0|1|2|40",
                       "The same four keys, zoomed in: four separate markers")
        XCTAssertEqual(TimelineKeyMarkers.encode([]), "")
    }

    /// **The encoding has one form for a marker, and this is the guard on that.** It carried a second
    /// — a keyframe no channel keyed was parenthesised — and the owner asked for the state itself to
    /// go on 2026-09-03. A row mixing a keyed frame with an unkeyed mark is the case that used to
    /// print two shapes; it prints one now, and the assertion is on the *string* rather than on a flag
    /// so it is about what a UI test can read rather than about a field.
    func testTheAccessibilityValueDrawsEveryKeyframeTheSameWay() {
        let markers = markerRow(marks: [0, 12], tracks: [brightnessID: curve([0])])
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: markers, pixelsPerFrame: defaultZoom)), "0|12")
    }

    // MARK: - End to end, from a document to what is drawn

    /// One pass over the seam this stage actually adds: a real graded layer, real keys written by the
    /// real writer, straight through to the string a UI test reads off the band.
    func testKeysWrittenToALayerBecomeTheMarkersTheBandDraws() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        for frame in [3, 4, 20] {
            manager.setEffectParameterKeys(target, frame: frame,
                                           values: [brightnessID: Double(frame), contrastID: 1])
        }

        let markers = markerRow(manager, target)
        XCTAssertEqual(markers, [3, 4, 20],
                       "Two channels keyed on each of three frames — three markers")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: markers, pixelsPerFrame: defaultZoom)), "3|4|20")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: markers, pixelsPerFrame: floorZoom)), "3-4|20",
                       "Fully pinched out, the pair on adjacent frames becomes one run and the lone key does not")
    }

    /// **The owner's A/B workflow, read off the band at each step** — the one sequence this half of
    /// the stage exists to make visible. A is placed and shows; a slider moves and the band does not
    /// change, because §2.27 holds the previous value rather than writing a key; B is placed and both
    /// frames are keyed. A band that showed nothing until the last step is exactly the unusable state
    /// this fixes.
    ///
    /// **It also pins where the mark goes.** §2.26 needs a mark to store *"keyframe A is added,
    /// nothing is saved"* — that is why `keyframeMarks` still exists — and the 2026-09-03 rule needs
    /// it gone the moment a key lands on the same frame. Both are asserted here, on the same three
    /// steps, because they are the two halves of one invariant.
    func testTheOwnersABWorkflowFillsInOnTheTimelineOnlyWhenBLands() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        func band() -> String {
            let markers = markerRow(manager, target)
            return TimelineKeyMarkers.encode(TimelineKeyMarkers.runs(frames: markers,
                                                                     pixelsPerFrame: defaultZoom))
        }
        guard let brightness = manager.layers[1].layerEffect?
            .parameters.first(where: { $0.id == brightnessID }) else {
            return XCTFail("Fixture: the grade should expose a brightness parameter")
        }

        manager.addKeyframe(target, atFrame: 0)
        XCTAssertEqual(band(), "0", "Keyframe A is added and nothing is saved — the mark alone")
        XCTAssertEqual(manager.keyframeState(of: target).marks, [0],
                       "…and until a key lands on it, the mark is what stores it")

        manager.applyEffectParameterEdit(target, parameter: brightness, newValue: 2, atFrame: 8)
        XCTAssertEqual(band(), "0",
                       "The previous value is only held, so nothing has landed on the timeline yet")

        manager.addKeyframe(target, atFrame: 8)
        XCTAssertEqual(band(), "0|8", "B commits the held value onto A and the new one onto B")
        XCTAssertEqual(manager.keyframeState(of: target).marks, [], """
            And both marks are gone from storage, because both frames are keyed now. That is the \
            whole of the fix: a mark that has been keyed cannot be stranded by a later graph-editor \
            edit, because it is no longer there to strand.
            """)
    }
}
