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
/// The two questions the file is organised around:
///
/// - **What is a marker?** One per (target, frame), however many channels key there — the channel
///   collapse, which is unconditional.
/// - **What happens when markers touch?** The zoom collapse, which is the interesting one, and which
///   is pinned against the timeline's own pinch limits rather than against numbers re-typed here.
@MainActor
final class TimelineKeyMarkersLogicTests: XCTestCase {

    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    /// The two ends of the pinch range, named so a test reads as the zoom the artist is at.
    private var floorZoom: CGFloat { TimelineKeyMarkers.pixelsPerFrameRange.lowerBound }
    private var defaultZoom: CGFloat { TimelineKeyMarkers.basePixelsPerFrame }

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
        let frames = TimelineKeyMarkers.keyedFrames(in: [
            brightnessID: curve([4]),
            contrastID: curve([4])
        ])
        XCTAssertEqual(frames, [4], "Two channels, one frame, one marker")
    }

    func testChannelsKeyedOnDifferentFramesProduceOneMarkerEach() {
        let frames = TimelineKeyMarkers.keyedFrames(in: [
            brightnessID: curve([0, 8]),
            contrastID: curve([4, 8])
        ])
        XCTAssertEqual(frames, [0, 4, 8], "The union, deduped — frame 8 is keyed twice and drawn once")
    }

    /// **The order is not cosmetic.** This array goes into `TimelineLayoutKey`, which is an
    /// `Equatable` memoization gate, and `Dictionary.values` has no defined order. An unsorted result
    /// would make the key unequal to itself at random, turning the layout gate off in a way that
    /// looks like a performance regression with no cause and no failing test.
    func testTheFrameListIsAscendingWhateverOrderTheChannelsAreIn() {
        let a = TimelineKeyMarkers.keyedFrames(in: [brightnessID: curve([9, 2]), contrastID: curve([5])])
        let b = TimelineKeyMarkers.keyedFrames(in: [contrastID: curve([5]), brightnessID: curve([2, 9])])
        XCTAssertEqual(a, [2, 5, 9])
        XCTAssertEqual(a, b, "Two dictionaries with the same content must produce the same array")
    }

    func testATargetWithNoTracksHasNoMarkers() {
        XCTAssertEqual(TimelineKeyMarkers.keyedFrames(in: [:]), [])
        XCTAssertEqual(TimelineKeyMarkers.keyedFrames(in: [brightnessID: AnimationCurve()]), [],
                       "A channel whose curve is empty animates nothing and draws nothing")
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
                let column = CGRect(x: CGFloat(frame) * zoom, y: 0, width: zoom, height: 1)
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

    // MARK: - What a UI test can read

    /// The band publishes one encoded value rather than one element per marker — `CurveEditor`'s
    /// `encode(points)` convention and `TimelineFolderRowView`'s. It exists because XCUITest can see
    /// neither a `CGContext` nor a colour, and the collapse in particular is *only* visible as a
    /// shape, so without this the one thing this stage designs would be unassertable above this tier.
    func testTheAccessibilityValueSaysWhichMarkersAreCollapsed() {
        let runs = TimelineKeyMarkers.runs(frames: [0, 1, 2, 40], pixelsPerFrame: floorZoom)
        XCTAssertEqual(TimelineKeyMarkers.encode(runs), "0-2|40")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: [0, 1, 2, 40], pixelsPerFrame: defaultZoom)),
                       "0|1|2|40",
                       "The same four keys, zoomed in: four separate markers")
        XCTAssertEqual(TimelineKeyMarkers.encode([]), "")
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

        let frames = TimelineKeyMarkers.keyedFrames(in: manager.layers[1].effectTracks)
        XCTAssertEqual(frames, [3, 4, 20], "Two channels keyed on each of three frames — three markers")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: frames, pixelsPerFrame: defaultZoom)), "3|4|20")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(frames: frames, pixelsPerFrame: floorZoom)), "3-4|20",
                       "Fully pinched out, the pair on adjacent frames becomes one run and the lone key does not")
    }
}
