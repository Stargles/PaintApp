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
///   `CanvasManager.keyframes`, so these tests take it from there rather than from a second copy.
/// - **Which kind is it?** Bare when the artist placed a keyframe there and nothing has been saved
///   onto it yet (§2.26), landed otherwise.
/// - **What happens when markers touch?** The zoom collapse, which is the interesting one, and which
///   is pinned against the timeline's own pinch limits rather than against numbers re-typed here.
@MainActor
final class TimelineKeyMarkersLogicTests: XCTestCase {

    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    /// A landed marker on each of `frames` — the shape most of the collapse tests want, since the
    /// collapse itself is indifferent to which kind a marker is.
    private func landed(_ frames: [Int]) -> [TimelineKeyMarkers.Marker] {
        frames.map { TimelineKeyMarkers.Marker(frame: $0, isBare: false) }
    }

    /// The two ends of the pinch range, named so a test reads as the zoom the artist is at.
    private var floorZoom: CGFloat { TimelineKeyMarkers.pixelsPerFrameRange.lowerBound }
    private var defaultZoom: CGFloat { TimelineKeyMarkers.basePixelsPerFrame }

    /// **The band's markers for one target's stored state.** The union is
    /// `CanvasManager.keyframes(marks:tracks:)`' — the model owns what counts as a keyframe — and
    /// `TimelineKeyMarkers.markers` only says which kind each one is drawn as. Pairing them here is
    /// what `TimelineLayoutKey.make` does, so the assertions below are about the band the artist sees
    /// rather than about either half alone.
    private func markerRow(marks: [Int], tracks: [String: AnimationCurve]) -> [TimelineKeyMarkers.Marker] {
        let placed = CanvasManager.keyframes(marks: marks, tracks: tracks)
        return TimelineKeyMarkers.markers(frames: placed.frames, keyed: placed.keyed)
    }

    /// The same pair against a real document, through the accessor production reads.
    private func markerRow(_ manager: CanvasManager, _ target: KeyframeTarget) -> [TimelineKeyMarkers.Marker] {
        let placed = manager.keyframes(of: target)
        return TimelineKeyMarkers.markers(frames: placed.frames, keyed: placed.keyed)
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
        XCTAssertEqual(markers, landed([4]), "Two channels, one frame, one marker")
    }

    func testChannelsKeyedOnDifferentFramesProduceOneMarkerEach() {
        let markers = markerRow(marks: [], tracks: [
            brightnessID: curve([0, 8]),
            contrastID: curve([4, 8])
        ])
        XCTAssertEqual(markers, landed([0, 4, 8]),
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
        XCTAssertEqual(a, landed([2, 5, 9]))
        XCTAssertEqual(a, b, "Two dictionaries with the same content must produce the same array")
    }

    /// The marks arrive sorted from the model, but the union is a `Set` and only this sort decides
    /// what comes out — so an out-of-order input must not survive into the layout key.
    func testTheUnionIsAscendingWhateverOrderTheMarksArriveIn() {
        XCTAssertEqual(markerRow(marks: [9, 2, 5], tracks: [:]).map(\.frame),
                       [2, 5, 9])
    }

    func testATargetWithNothingOnItHasNoMarkers() {
        XCTAssertEqual(markerRow(marks: [], tracks: [:]), [])
        XCTAssertEqual(markerRow(marks: [], tracks: [brightnessID: AnimationCurve()]), [],
                       "A channel whose curve is empty animates nothing and draws nothing")
    }

    // MARK: - The union, and which kind each marker is

    /// **The whole of §2.26's first step.** A keyframe is placed and nothing is saved onto it; if that
    /// draws nothing the artist places A blind and the feature cannot be used. It has to be a marker,
    /// and it has to be visibly a *different* marker from one that carries a key.
    func testAMarkWithNoKeyOnItIsABareMarker() {
        XCTAssertEqual(markerRow(marks: [3], tracks: [:]),
                       [TimelineKeyMarkers.Marker(frame: 3, isBare: true)])
    }

    /// **A key with no mark is landed, not bare**, and it is a case that really occurs: §2.26 says a
    /// curve carries keys the artist never marked — an auto-key at the playhead, or a value seeded
    /// onto a neighbouring mark. So the union cannot be derived from the marks either.
    func testAKeyWithNoMarkOnItIsALandedMarker() {
        XCTAssertEqual(markerRow(marks: [], tracks: [brightnessID: curve([7])]),
                       landed([7]))
    }

    /// The mixed row: the artist's mark at 0 has taken a value, the one at 12 has not yet.
    func testAMarkThatHasTakenAKeyIsLandedAndOneThatHasNotIsBare() {
        XCTAssertEqual(markerRow(marks: [0, 12], tracks: [brightnessID: curve([0])]),
                       [TimelineKeyMarkers.Marker(frame: 0, isBare: false),
                        TimelineKeyMarkers.Marker(frame: 12, isBare: true)])
    }

    // MARK: - Collapse (2): zoom

    func testOneKeyIsOneUncollapsedMarkerAtEveryZoom() {
        for zoom in [floorZoom, defaultZoom, TimelineKeyMarkers.pixelsPerFrameRange.upperBound] {
            let runs = TimelineKeyMarkers.runs(markers: landed([6]), pixelsPerFrame: zoom)
            XCTAssertEqual(runs, [TimelineKeyMarkers.Run(firstFrame: 6, lastFrame: 6, count: 1, isBare: false)])
            XCTAssertFalse(runs[0].isCollapsed, "A run of one is a key, not a collapse")
        }
    }

    func testAtTheDefaultZoomAdjacentFramesAreStillDrawnApart() {
        let runs = TimelineKeyMarkers.runs(markers: landed([4, 5, 6]), pixelsPerFrame: defaultZoom)
        XCTAssertEqual(runs.count, 3, "30 pt of column is far more room than a 9 pt diamond needs")
        XCTAssertTrue(runs.allSatisfy { !$0.isCollapsed })
    }

    func testAtTheMinimumZoomAdjacentFramesCollapseIntoOneRun() {
        let runs = TimelineKeyMarkers.runs(markers: landed([4, 5, 6, 7]), pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs, [TimelineKeyMarkers.Run(firstFrame: 4, lastFrame: 7, count: 4, isBare: false)],
                       "Chaining is the behaviour wanted: four keys with no daylight anywhere between them are one dense region, not two pairs")
        XCTAssertTrue(runs[0].isCollapsed)
    }

    /// **The collapse must not swallow "on twos"**, which §2.10 makes a first-class thing this feature
    /// can produce. A key every other frame is a legible, countable rhythm at every zoom the artist
    /// can reach, and a timeline that drew it as a bar would be hiding the difference between ink on
    /// twos and a run recorded on every frame — the one distinction §2.10 exists to preserve.
    func testKeysOnTwosStayCountableEvenFullyPinchedOut() {
        let runs = TimelineKeyMarkers.runs(markers: landed([0, 2, 4, 6]), pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs.count, 4)
        XCTAssertTrue(runs.allSatisfy { !$0.isCollapsed })
    }

    /// **The rule is per-neighbour, not a global "the zoom is low" flag**, and this is the test that
    /// says so. At the minimum zoom a dense burst collapses while a key forty frames away stays its
    /// own diamond — only the parts of the track that actually collide lose detail.
    func testOnlyTheDensePartOfATrackCollapses() {
        let runs = TimelineKeyMarkers.runs(markers: landed([0, 1, 2, 40]), pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs, [TimelineKeyMarkers.Run(firstFrame: 0, lastFrame: 2, count: 3, isBare: false),
                              TimelineKeyMarkers.Run(firstFrame: 40, lastFrame: 40, count: 1, isBare: false)])
    }

    /// **A run is hollow only when everything in it is bare, and a mixed run draws as landed.** The
    /// collapse already gives up which interior frames carry keys, so giving up which of them are bare
    /// is the same loss resolved the same way — by zooming in. The direction is what matters: hollow
    /// is the alarming reading, *nothing here is saved yet*, so claiming it over a run that does hold
    /// saved keys would send the artist hunting a bug that is not there.
    func testARunIsBareOnlyWhenEveryMarkerInItIs() {
        let allBare = [0, 1, 2].map { TimelineKeyMarkers.Marker(frame: $0, isBare: true) }
        XCTAssertEqual(TimelineKeyMarkers.runs(markers: allBare, pixelsPerFrame: floorZoom),
                       [TimelineKeyMarkers.Run(firstFrame: 0, lastFrame: 2, count: 3, isBare: true)])

        var mixed = allBare
        mixed[1] = TimelineKeyMarkers.Marker(frame: 1, isBare: false)
        XCTAssertEqual(TimelineKeyMarkers.runs(markers: mixed, pixelsPerFrame: floorZoom),
                       [TimelineKeyMarkers.Run(firstFrame: 0, lastFrame: 2, count: 3, isBare: false)],
                       "One landed key in the run is enough for the run to read as landed")
    }

    /// The kind belongs to the run it is in and does not leak into the next one — the mirror of
    /// `testOnlyTheDensePartOfATrackCollapses`, for the field that was added beside `count`.
    func testEachRunCarriesItsOwnKindWhenTheTrackMixesThem() {
        let markers = [TimelineKeyMarkers.Marker(frame: 0, isBare: false),
                       TimelineKeyMarkers.Marker(frame: 40, isBare: true)]
        XCTAssertEqual(TimelineKeyMarkers.runs(markers: markers, pixelsPerFrame: floorZoom),
                       [TimelineKeyMarkers.Run(firstFrame: 0, lastFrame: 0, count: 1, isBare: false),
                        TimelineKeyMarkers.Run(firstFrame: 40, lastFrame: 40, count: 1, isBare: true)])
    }

    /// **A collapsed run keeps its two ends exactly.** That is the whole contract of the collapsed
    /// form: where the animation starts and where it stops survive, and only which interior frames
    /// carry keys is given up — which is what zooming in is for.
    func testACollapsedRunReportsItsRealFirstAndLastFrames() {
        let runs = TimelineKeyMarkers.runs(markers: landed([12, 13, 14, 15, 16]), pixelsPerFrame: floorZoom)
        XCTAssertEqual(runs.first?.firstFrame, 12)
        XCTAssertEqual(runs.first?.lastFrame, 16)
        XCTAssertEqual(runs.first?.count, 5)
    }

    func testNoKeysIsNoRuns() {
        XCTAssertEqual(TimelineKeyMarkers.runs(markers: [], pixelsPerFrame: defaultZoom), [])
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
        let run = TimelineKeyMarkers.Run(firstFrame: 5, lastFrame: 5, count: 1, isBare: false)
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
        let run = TimelineKeyMarkers.Run(firstFrame: 2, lastFrame: 9, count: 8, isBare: false)
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
    /// neither a `CGContext` nor a colour, and the collapse and the hollow form are *only* visible as
    /// shapes, so without this the two things this stage designs would be unassertable above this tier.
    func testTheAccessibilityValueSaysWhichMarkersAreCollapsed() {
        let runs = TimelineKeyMarkers.runs(markers: landed([0, 1, 2, 40]), pixelsPerFrame: floorZoom)
        XCTAssertEqual(TimelineKeyMarkers.encode(runs), "0-2|40")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(markers: landed([0, 1, 2, 40]), pixelsPerFrame: defaultZoom)),
                       "0|1|2|40",
                       "The same four keys, zoomed in: four separate markers")
        XCTAssertEqual(TimelineKeyMarkers.encode([]), "")
    }

    func testTheAccessibilityValueParenthesisesABareMarker() {
        let markers = markerRow(marks: [0, 12], tracks: [brightnessID: curve([0])])
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(markers: markers, pixelsPerFrame: defaultZoom)), "0|(12)")
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
        XCTAssertEqual(markers, landed([3, 4, 20]),
                       "Two channels keyed on each of three frames — three markers, none of them bare")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(markers: markers, pixelsPerFrame: defaultZoom)), "3|4|20")
        XCTAssertEqual(TimelineKeyMarkers.encode(
            TimelineKeyMarkers.runs(markers: markers, pixelsPerFrame: floorZoom)), "3-4|20",
                       "Fully pinched out, the pair on adjacent frames becomes one run and the lone key does not")
    }

    /// **The owner's A/B workflow, read off the band at each step** — the one sequence this half of
    /// the stage exists to make visible. A is placed and is hollow; a slider moves and *stays* hollow,
    /// because §2.27 holds the previous value rather than writing a key; B is placed and both fill in.
    /// A band that showed nothing until the last step is exactly the unusable state this fixes.
    func testTheOwnersABWorkflowFillsInOnTheTimelineOnlyWhenBLands() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        func band() -> String {
            let markers = markerRow(manager, target)
            return TimelineKeyMarkers.encode(TimelineKeyMarkers.runs(markers: markers,
                                                                     pixelsPerFrame: defaultZoom))
        }
        guard let brightness = manager.layers[1].layerEffect?
            .parameters.first(where: { $0.id == brightnessID }) else {
            return XCTFail("Fixture: the grade should expose a brightness parameter")
        }

        manager.addKeyframe(target, atFrame: 0)
        XCTAssertEqual(band(), "(0)", "Keyframe A is added and nothing is saved — a bare mark")

        manager.applyEffectParameterEdit(target, parameter: brightness, newValue: 2, atFrame: 8)
        XCTAssertEqual(band(), "(0)",
                       "The previous value is only held, so nothing has landed on the timeline yet")

        manager.addKeyframe(target, atFrame: 8)
        XCTAssertEqual(band(), "0|8", "B commits the held value onto A and the new one onto B")
    }
}
