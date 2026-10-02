import XCTest
import UIKit

/// **Two fingers on the timeline: the frame under them when they land stays under them** — TODO (123),
/// *"zooming while panning sideways like the canvas move"*. `ViewportAnchorLogicTests` pins the rule;
/// this pins the timeline's one-axis use of it: the units (a frame is `pixelsPerFrame` wide), the
/// scroll offset the track is actually moved to, and the range the zoom is held inside.
///
/// **Taken at a non-zero scroll offset or it cannot see the defect.** A scroll view's coordinate system
/// *is* its content — `bounds.origin` is `contentOffset` — so `location(in: scrollView).x` is content
/// space, and the fingers' place in the *viewport* is that minus the offset. Handing the content-space
/// number to something that wants the viewport-space one lands the anchor
/// `contentOffsetX · (scale − 1)` points out: exact at frame 0, wrong by a screenful once scrolled a
/// screenful, so every offset below is a few hundred points in.
final class TimelineZoomGestureLogicTests: XCTestCase {

    private let viewportWidth: CGFloat = 400
    /// Wide enough that nothing below is clamped, unless a test says it is the subject.
    private let contentWidth: CGFloat = 100_000

    /// Which frame is under a point `x` from the viewport's left edge, given how the track is
    /// scrolled and zoomed. Derived from the fixture's own geometry — content x over zoom.
    private func frameUnder(viewportX x: CGFloat, contentOffsetX: CGFloat, pixelsPerFrame: CGFloat) -> CGFloat {
        (contentOffsetX + x) / pixelsPerFrame
    }

    /// **The frame-under-the-fingers property over the table of gestures** — zooming in and out, the
    /// fingers still and travelling both ways, at three scroll offsets. The location is converted by
    /// UIKit rather than restated here: `UIGestureRecognizer.location(in:)` is `convert(_:to:)` from
    /// the window, so this asks a real `UIScrollView` at a real `contentOffset` the same thing.
    func testTheFrameUnderTheFingersStaysUnderThemThroughAnyZoomAndTravel() {
        let fingersAtLanding: CGFloat = 220
        for contentOffsetX in [CGFloat(600), 750, 1234.5] {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: viewportWidth, height: 100))
            let scrollView = UIScrollView(frame: container.bounds)
            container.addSubview(scrollView)
            scrollView.contentOffset.x = contentOffsetX
            let locationInContent = container.convert(CGPoint(x: fingersAtLanding, y: 50), to: scrollView).x
            XCTAssertEqual(locationInContent, contentOffsetX + fingersAtLanding,
                           "PREMISE: a scroll view's own coordinates are content space")

            for startZoom in [CGFloat(30), 60] {
                let gesture = TimelineZoomGesture(fingersInViewportX: locationInContent - contentOffsetX,
                                                  contentOffsetX: contentOffsetX,
                                                  pixelsPerFrame: startZoom)
                let anchoredFrame = frameUnder(viewportX: fingersAtLanding, contentOffsetX: contentOffsetX,
                                               pixelsPerFrame: startZoom)
                for (scale, travel) in [(CGFloat(1), CGFloat(0)), (1.5, 0), (0.7, 0),
                                        (1, 90), (1.5, 90), (1.5, -90), (0.7, 60)] {
                    let zoom = gesture.pixelsPerFrame(scale: scale)
                    let fingers = fingersAtLanding + travel
                    let offset = gesture.contentOffsetX(pixelsPerFrame: zoom, fingersInViewportX: fingers,
                                                        contentWidth: contentWidth, viewportWidth: viewportWidth)
                    // The assertion would be vacuous at a clamped offset: the track would be stopped
                    // at its edge and unable to honour the anchor.
                    XCTAssertGreaterThan(offset, 0, "Fixture: offset \(contentOffsetX), zoom \(startZoom)×\(scale), "
                                         + "travel \(travel) clamps at the left edge, which is a different test's subject")
                    XCTAssertEqual(frameUnder(viewportX: fingers, contentOffsetX: offset, pixelsPerFrame: zoom),
                                   anchoredFrame, accuracy: 0.0001,
                                   "offset \(contentOffsetX), zoom \(startZoom)×\(scale), travel \(travel)")
                }
            }
        }
    }

    /// **The fingers spread *and* travel sideways.** A zoom that held the fingers' landing position
    /// fixed would leave the frame where the fingers *had been*. Zoom 30→60 with the fingers 100 pt to
    /// the right leaves the frame that was under them at landing 100 pt further along the viewport, as
    /// well as twice as wide.
    func testAPinchThatAlsoTravelsCarriesTheFrameWithTheFingers() {
        let gesture = TimelineZoomGesture(fingersInViewportX: 200, contentOffsetX: 500, pixelsPerFrame: 30)
        let zoom = gesture.pixelsPerFrame(scale: 2)
        XCTAssertEqual(zoom, 60)
        let stationary = gesture.contentOffsetX(pixelsPerFrame: zoom, fingersInViewportX: 200,
                                                contentWidth: contentWidth, viewportWidth: viewportWidth)
        let travelled = gesture.contentOffsetX(pixelsPerFrame: zoom, fingersInViewportX: 300,
                                               contentWidth: contentWidth, viewportWidth: viewportWidth)
        XCTAssertEqual(stationary - travelled, 100, accuracy: 0.0001,
                       "Fingers 100 pt to the right pull the track 100 pt right under them, which is "
                       + "an offset 100 pt smaller — on top of the zoom, not instead of it")
    }

    /// A pan with no change of scale is the rule at scale 1: the offset moves by the fingers' travel,
    /// opposite in sign (content goes where the fingers go).
    func testAPlainTwoFingerPanScrollsByTheFingersTravel() {
        let gesture = TimelineZoomGesture(fingersInViewportX: 250, contentOffsetX: 800, pixelsPerFrame: 30)
        let offset = gesture.contentOffsetX(pixelsPerFrame: 30, fingersInViewportX: 190,
                                            contentWidth: contentWidth, viewportWidth: viewportWidth)
        XCTAssertEqual(offset, 860, accuracy: 0.0001, "Fingers 60 pt left → content 60 pt left → offset 60 more")
    }

    /// **Both ends are clamped**, the far end to the same `contentSize − bounds` a scroll view would stop
    /// at itself — pinch out far enough and the frame under the fingers would need the content to start
    /// left of zero.
    func testTheOffsetIsClampedToWhatTheTrackCanScrollTo() {
        let gesture = TimelineZoomGesture(fingersInViewportX: 100, contentOffsetX: 300, pixelsPerFrame: 30)
        XCTAssertEqual(gesture.contentOffsetX(pixelsPerFrame: 1, fingersInViewportX: 100,
                                              contentWidth: 5_000, viewportWidth: 400), 0,
                       "Pinched right out, the anchor wants a negative offset and the track stops at its left edge")
        XCTAssertEqual(gesture.contentOffsetX(pixelsPerFrame: 120, fingersInViewportX: 100,
                                              contentWidth: 1_000, viewportWidth: 400), 600,
                       "Pinched right in, it stops where the scroll view itself would: contentSize − bounds")
        XCTAssertEqual(gesture.contentOffsetX(pixelsPerFrame: 30, fingersInViewportX: 100,
                                              contentWidth: 200, viewportWidth: 400), 0,
                       "A track narrower than its viewport has nowhere to scroll to at all")
    }

    /// **The zoom is held inside the timeline's own range, and the range is read from where it lives**
    /// rather than re-typed, so widening it cannot leave this green against the old limits.
    func testTheZoomStopsAtBothEndsOfTheTimelinesRange() {
        let range = TimelineKeyMarkers.pixelsPerFrameRange
        let gesture = TimelineZoomGesture(fingersInViewportX: 0, contentOffsetX: 0, pixelsPerFrame: 30)
        XCTAssertEqual(gesture.pixelsPerFrame(scale: 100), range.upperBound)
        XCTAssertEqual(gesture.pixelsPerFrame(scale: 0.001), range.lowerBound)
        XCTAssertEqual(gesture.pixelsPerFrame(scale: 1), 30, accuracy: 0.0001)
    }

    /// **Past the end of the range the frame stays under the fingers**: the anchor is carried by the
    /// zoom the track actually took, not by the raw pinch, so spreading on after the limit does not
    /// slide the content out from under the fingers.
    func testASpreadHeldPastTheLimitStillKeepsTheFrameUnderTheFingers() {
        let range = TimelineKeyMarkers.pixelsPerFrameRange
        let gesture = TimelineZoomGesture(fingersInViewportX: 200, contentOffsetX: 600, pixelsPerFrame: 30)
        let anchored = frameUnder(viewportX: 200, contentOffsetX: 600, pixelsPerFrame: 30)
        let zoom = gesture.pixelsPerFrame(scale: 50)
        XCTAssertEqual(zoom, range.upperBound)
        let offset = gesture.contentOffsetX(pixelsPerFrame: zoom, fingersInViewportX: 200,
                                            contentWidth: contentWidth, viewportWidth: viewportWidth)
        XCTAssertEqual(frameUnder(viewportX: 200, contentOffsetX: offset, pixelsPerFrame: zoom),
                       anchored, accuracy: 0.0001)
    }
}
