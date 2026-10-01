import XCTest
import CoreGraphics

/// **What the ruler writes, at the zoom the artist has pinched to** — TODO (122): *"When the timeline
/// is zoomed out it should display seconds instead of frames."* `Views/TimelineRulerStrip.swift` is not
/// compiled into this target, so the decision — frame numbers or time, and how many of either — lives in
/// `TimelineRulerLabels` and is pinned here; the view keeps only the font and the `NSString.draw`.
///
/// **Thresholds are asserted as relationships to the label's own width and to the timeline's zoom
/// range**, never as a `17.0` re-typed on this side: a number copied into a test is a constant compared
/// with its own copy, green on the day somebody retunes the font.
final class TimelineRulerLabelsLogicTests: XCTestCase {

    private let range = TimelineKeyMarkers.pixelsPerFrameRange
    private let defaultZoom = TimelineKeyMarkers.basePixelsPerFrame

    // MARK: - Frames or seconds

    /// **The unit the artist gets at the zoom they start at.** A new document opens at the base zoom, so
    /// this is the first thing the ruler says, and it must be frames: the artist is placing drawings.
    func testTheDefaultZoomLabelsFramesForASceneOfAnyUsualLength() {
        for lastFrame in [0, 11, 99, 999, 9_000] {
            let plan = TimelineRulerLabels.plan(pixelsPerFrame: defaultZoom, framesPerSecond: 24, lastFrame: lastFrame)
            XCTAssertEqual(plan.unit, .frames, "at the default zoom, frames up to \(lastFrame)")
            XCTAssertEqual(plan.framesBetweenLabels, 1, "every frame is numbered, none thinned")
        }
    }

    /// **And fully pinched out it is seconds, whatever the scene.** At the floor of the zoom range even a
    /// one-digit frame number is wider than the column it must sit in, so there is no frame count at
    /// which frames fit — which is the whole case for the switch.
    func testFullyPinchedOutAlwaysLabelsSeconds() {
        for lastFrame in [0, 9, 99, 999, 9_999] {
            let plan = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: 24, lastFrame: lastFrame)
            XCTAssertEqual(plan.unit, .seconds, "at the zoom floor, frames up to \(lastFrame)")
        }
    }

    /// **The threshold is the widest label against its own column, for every width of number.** One pitch
    /// short of what `n` digits need is seconds; exactly what they need is frames. Taken at one digit
    /// up to five, because the longer the scene the sooner the numbers collide.
    func testTheSwitchIsWhereTheWidestFrameNumberStopsFittingItsColumn() {
        for digits in 1...5 {
            let lastFrame = Int(pow(10.0, Double(digits))) - 2     // frame number 10^digits − 1: `digits` wide
            let needed = TimelineRulerLabels.minimumPitch(forCharacters: digits)
            XCTAssertEqual(TimelineRulerLabels.plan(pixelsPerFrame: needed, framesPerSecond: 24,
                                                    lastFrame: lastFrame).unit, .frames,
                           "\(digits)-digit numbers fit a column exactly \(needed) pt wide")
            XCTAssertEqual(TimelineRulerLabels.plan(pixelsPerFrame: needed - 0.01, framesPerSecond: 24,
                                                    lastFrame: lastFrame).unit, .seconds,
                           "…and collide in one a hair narrower")
        }
    }

    /// **A longer scene switches sooner than a short one**, because its numbers are wider.
    func testALongSceneSwitchesToSecondsBeforeAShortOneDoes() {
        let pitch = TimelineRulerLabels.minimumPitch(forCharacters: 2) + 0.5
        XCTAssertEqual(TimelineRulerLabels.plan(pixelsPerFrame: pitch, framesPerSecond: 24, lastFrame: 40).unit, .frames)
        XCTAssertEqual(TimelineRulerLabels.plan(pixelsPerFrame: pitch, framesPerSecond: 24, lastFrame: 4_000).unit, .seconds)
    }

    // MARK: - What a label says

    /// Frames are counted the way the frame readout counts them: from 1.
    func testFrameLabelsCountFromOne() {
        let plan = TimelineRulerLabels.plan(pixelsPerFrame: defaultZoom, framesPerSecond: 24, lastFrame: 30)
        XCTAssertEqual(plan.label(atFrame: 0), "1")
        XCTAssertEqual(plan.label(atFrame: 23), "24")
        XCTAssertEqual(plan.labelledFrames(in: 3..<7), [3, 4, 5, 6])
    }

    /// **A second begins on the frame index `n × fps`**, because frame `i` is shown at time `i / fps` —
    /// so the label for second 1 at 24 fps is on the 25th frame (index 24), and the frames between are
    /// not labelled at all.
    func testSecondsAreLabelledOnTheirFirstFrame() {
        let plan = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: 24, lastFrame: 100)
        XCTAssertEqual(plan.unit, .seconds)
        XCTAssertEqual(plan.framesBetweenLabels, 24, "one label a second while a second has room")
        XCTAssertEqual(plan.label(atFrame: 0), "0s")
        XCTAssertEqual(plan.label(atFrame: 24), "1s")
        XCTAssertEqual(plan.label(atFrame: 48), "2s")
        XCTAssertNil(plan.label(atFrame: 25), "the frames between two seconds carry no label")
        XCTAssertEqual(plan.labelledFrames(in: 0..<100), [0, 24, 48, 72, 96])
        XCTAssertEqual(plan.labelledFrames(in: 25..<73), [48, 72], "a window starting mid-second begins at the next one")
    }

    /// The frame rate moves the labels and nothing else: the same zoom at 12 fps puts the seconds half
    /// as far apart in frames.
    func testTheFrameRateSetsWhereTheSecondsFall() {
        let at12 = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: 12, lastFrame: 100)
        let at24 = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: 24, lastFrame: 100)
        XCTAssertEqual(at12.framesBetweenLabels * 2, at24.framesBetweenLabels)
        XCTAssertEqual(at12.label(atFrame: 12), "1s")
    }

    /// **`5s`, then a clock** once a minute is worth saying — the suffix goes when the colon makes the
    /// unit plain, and hours appear only when there are some.
    func testSecondsReadAsASecondCountThenAsAClock() {
        XCTAssertEqual(TimelineRulerLabels.secondsText(0), "0s")
        XCTAssertEqual(TimelineRulerLabels.secondsText(5), "5s")
        XCTAssertEqual(TimelineRulerLabels.secondsText(59), "59s")
        XCTAssertEqual(TimelineRulerLabels.secondsText(60), "1:00")
        XCTAssertEqual(TimelineRulerLabels.secondsText(125), "2:05")
        XCTAssertEqual(TimelineRulerLabels.secondsText(3_599), "59:59")
        XCTAssertEqual(TimelineRulerLabels.secondsText(3_600), "1:00:00")
        XCTAssertEqual(TimelineRulerLabels.secondsText(3_725), "1:02:05")
    }

    // MARK: - Seconds thin themselves

    /// **No two labels ever collide, at any zoom the timeline can reach.** For every frame rate the
    /// document allows and every zoom in range, the gap between two labelled ticks is at least the
    /// widest label in the window plus its margin — unless the stride has run out of numbers to thin
    /// by, which only a one-frame-per-second document at the floor of the range could reach.
    func testLabelledTicksAreNeverCloserThanTheirLabelsAreWide() {
        for fps in [1, 6, 12, 24, 30, 60] {
            for zoom in stride(from: range.lowerBound, through: range.upperBound, by: 1.5) {
                for lastFrame in [50, 500, 5_000, 50_000] {
                    let plan = TimelineRulerLabels.plan(pixelsPerFrame: zoom, framesPerSecond: fps, lastFrame: lastFrame)
                    let widest = (plan.labelledFrames(in: max(lastFrame - plan.framesBetweenLabels, 0)..<(lastFrame + 1))
                        .compactMap { plan.label(atFrame: $0) }.map(\.count).max()) ?? 1
                    let pitch = CGFloat(plan.framesBetweenLabels) * zoom
                    let atLimit = plan.framesBetweenLabels == TimelineRulerLabels.secondsStrides.last! * fps
                    XCTAssertTrue(pitch >= TimelineRulerLabels.minimumPitch(forCharacters: widest) || atLimit,
                                  "fps \(fps), zoom \(zoom), frames to \(lastFrame): labels \(pitch) pt apart, "
                                  + "needing \(TimelineRulerLabels.minimumPitch(forCharacters: widest))")
                }
            }
        }
    }

    /// **The stride is the *smallest* that fits**, so zooming out thins the labels one step at a time and
    /// never by more than it has to: a ruler that jumped from every second to every minute would lose
    /// the seconds the artist is looking for.
    func testTheStrideIsTheSmallestThatLeavesEachLabelItsRoom() {
        // One frame a second, so a second is as narrow as a frame and the stride has to climb; at 24 fps
        // the first stride already fits and the "smaller stride collides" half would be vacuous.
        let fps = 1
        let plan = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: fps, lastFrame: 1_000)
        XCTAssertEqual(plan.unit, .seconds)
        let strides = TimelineRulerLabels.secondsStrides
        guard let index = strides.firstIndex(where: { $0 * fps == plan.framesBetweenLabels }) else {
            return XCTFail("the stride is one of the numbers a person counts in")
        }
        XCTAssertGreaterThan(index, 0, "Fixture: at this zoom and rate one second is too narrow for its own label")
        let smaller = CGFloat(strides[index - 1] * fps) * range.lowerBound
        let widest = TimelineRulerLabels.secondsText(1_000 / fps).count
        XCTAssertLessThan(smaller, TimelineRulerLabels.minimumPitch(forCharacters: widest),
                          "the next stride down would have collided, or it would have been the one chosen")
    }

    /// A one-frame-per-second document is a divisor of 1 and cannot trap or divide by zero, and a rate of
    /// zero — which `CanvasManager.fps` clamps away but a plan must not trust — is read as 1.
    func testAZeroFrameRateIsReadAsOne() {
        let plan = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: 0, lastFrame: 10)
        XCTAssertEqual(plan.unit, .seconds)
        XCTAssertGreaterThanOrEqual(plan.framesBetweenLabels, 1)
        XCTAssertNotNil(plan.label(atFrame: 0))
    }

    // MARK: - What a test can read

    /// The accessibility encoding names the unit and lists the labels of a window — what the artist
    /// reads off the ruler, as text, so a UI test can say which vocabulary is on screen.
    func testTheEncodingNamesTheUnitAndTheVisibleLabels() {
        let frames = TimelineRulerLabels.plan(pixelsPerFrame: defaultZoom, framesPerSecond: 24, lastFrame: 5)
        XCTAssertEqual(TimelineRulerLabels.encode(frames, frames: 0..<4), "frames:1,2,3,4")
        let seconds = TimelineRulerLabels.plan(pixelsPerFrame: range.lowerBound, framesPerSecond: 24, lastFrame: 100)
        XCTAssertEqual(TimelineRulerLabels.encode(seconds, frames: 0..<73), "seconds:0s,1s,2s,3s")
    }
}
