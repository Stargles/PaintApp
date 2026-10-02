import XCTest

/// **Two fingers on the timeline zoom and pan it at once, the way two fingers move the canvas** —
/// TODO (123): *"The animation timeline supports zooming in and out with two fingers, but it seems that
/// it does not support zooming while panning sideways like the canvas move."*
///
/// `TimelineZoomGestureLogicTests` pins the arithmetic. What only a touch can answer is whether the
/// recognizers actually deliver it: that a pinch which also travels is *recognized* beside the scroll
/// view's own pan (before this it was not — the pan reached its threshold first and the pinch never
/// began, so the track scrolled and did not zoom), and that what lands on screen is the frame the
/// fingers started over still being under them.
///
/// **Every assertion is on what is drawn.** The scale and the frame under the fingers are both read off
/// the first cel block's accessibility frame — 12 frames wide at the default zoom, inset 2 pt inside its
/// slot by `TimelineRowView` — never off a stored zoom, so a zoom the track stored and did not draw
/// would still fail. Each test starts from a new document.
final class TimelineZoomPanUITests: PaintUITestCase {

    /// How far `TimelineRowView` insets a cel block inside its frame slot, each side. Read here only to
    /// turn a block's frame into the frame *slot's* left edge.
    private let blockInset: CGFloat = 2
    /// The default document's first cel starts at frame 0 and is this long.
    private let celLength: CGFloat = 12

    /// What the cel block says about the track right now: how wide a frame is, and the screen x of the
    /// left edge of frame 0.
    private func track(_ app: XCUIApplication) -> (pointsPerFrame: CGFloat, originX: CGFloat) {
        let frame = app.otherElements["timeline.cel.0.0"].frame
        return ((frame.width + 2 * blockInset) / celLength, frame.minX - blockInset)
    }

    /// Which frame is under screen x, fractionally.
    private func frame(atScreenX x: CGFloat, _ app: XCUIApplication) -> CGFloat {
        let geometry = track(app)
        return (x - geometry.originX) / geometry.pointsPerFrame
    }

    /// A pinch-and-travel gesture on `y`: two fingers `spread` points either side of `centre` that end
    /// `end` points either side of `centre + travel`.
    private func spreadAndTravel(centre: CGFloat, y: CGFloat, spread: CGFloat, end: CGFloat, travel: CGFloat) throws {
        try twoFingerGesture(
            from: (CGPoint(x: centre - spread, y: y), CGPoint(x: centre + spread, y: y)),
            to: (CGPoint(x: centre + travel - end, y: y), CGPoint(x: centre + travel + end, y: y)))
    }

    /// **The reported defect, on the rows**: spread two fingers over the first cel while moving them
    /// sideways, and the frame that was under them is under them still, wherever they have travelled to,
    /// with the track zoomed in. Once with a short travel to the right and once with a long one to the
    /// left. The long one matters most: the scroll view's own pan reaches its threshold well before the
    /// pinch does, so a track whose pinch is not recognised beside that pan scrolls and does not zoom.
    func testAPinchThatTravelsSidewaysZoomsAndKeepsTheFrameUnderTheFingers() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5))
        let rowY = cel.frame.midY

        for travel in [CGFloat(40), -120] {
            let before = track(app)
            // Frame 9 of the cel, which is far enough in that zooming in and travelling right need not
            // run the track off its left edge — a clamped offset could not keep the anchor, and that is
            // `TimelineZoomGestureLogicTests`' subject rather than this test's.
            let centre = before.originX + 9 * before.pointsPerFrame
            let anchored = frame(atScreenX: centre, app)
            try spreadAndTravel(centre: centre, y: rowY, spread: 60, end: 96, travel: travel)
            attachScreenshot(app, "pinch-and-travel-\(travel)")

            let after = track(app)
            let scale = after.pointsPerFrame / before.pointsPerFrame
            XCTAssertGreaterThan(scale, 1.2,
                                 "Spreading the fingers while they travel by \(travel) pt zooms the track in — "
                                 + "it was \(before.pointsPerFrame) pt a frame and is \(after.pointsPerFrame)")
            XCTAssertEqual(frame(atScreenX: centre + travel, app), anchored, accuracy: 0.4,
                           "The frame that was under the fingers (\(anchored)) is under them still, "
                           + "at x \(centre + travel), once they have travelled \(travel) pt")
        }
    }

    /// **The ruler is a second place to do it**, and no longer part of the scroll view it zooms — so it
    /// needs a pinch and a two-finger pan of its own. Same assertion as above, fingers on the ruler.
    func testAPinchThatTravelsSidewaysOnTheRulerDoesTheSame() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let ruler = app.otherElements["timeline.ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["timeline.cel.0.0"].waitForExistence(timeout: 5))

        let before = track(app)
        let centre = before.originX + 9 * before.pointsPerFrame
        let anchored = frame(atScreenX: centre, app)
        try spreadAndTravel(centre: centre, y: ruler.frame.midY, spread: 60, end: 96, travel: 40)

        let after = track(app)
        XCTAssertGreaterThan(after.pointsPerFrame / before.pointsPerFrame, 1.2,
                             "A pinch on the ruler zooms the track below it")
        XCTAssertEqual(frame(atScreenX: centre + 40, app), anchored, accuracy: 0.4,
                       "…about the fingers, as it does over the rows")
    }

    /// **Two fingers dragging on the ruler scroll the track**, which they did when the ruler was part of
    /// the scroll view and would not have if it had been moved out without a pan of its own. Neither
    /// zooms, and the track follows the fingers by roughly their travel.
    func testTwoFingersDraggingAlongTheRulerScrollTheTrackWithoutZoomingIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let ruler = app.otherElements["timeline.ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["timeline.cel.0.0"].waitForExistence(timeout: 5))

        let before = track(app)
        let y = ruler.frame.midY
        let start = before.originX + 300
        try twoFingerGesture(from: (CGPoint(x: start - 50, y: y), CGPoint(x: start + 50, y: y)),
                             to: (CGPoint(x: start - 50 - 150, y: y), CGPoint(x: start + 50 - 150, y: y)))

        let after = track(app)
        XCTAssertEqual(after.pointsPerFrame, before.pointsPerFrame, accuracy: 0.5,
                       "A pan that does not change the finger spacing does not zoom")
        XCTAssertEqual(before.originX - after.originX, 150, accuracy: 30,
                       "The track went where the fingers went: it was at \(before.originX) and is at \(after.originX)")
    }

    /// **What the track's own scroll still does**: two fingers dragging along the rows without spreading
    /// are the scroll view's pan, not the pinch, and keep scrolling by the fingers' travel. A guard that
    /// the pinch's new simultaneity did not take the plain two-finger scroll with it.
    func testTwoFingersDraggingAlongTheRowsStillScrollWithoutZooming() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5))

        let before = track(app)
        let y = cel.frame.midY
        let start = before.originX + 300
        try twoFingerGesture(from: (CGPoint(x: start - 50, y: y), CGPoint(x: start + 50, y: y)),
                             to: (CGPoint(x: start - 50 - 150, y: y), CGPoint(x: start + 50 - 150, y: y)))

        let after = track(app)
        XCTAssertEqual(after.pointsPerFrame, before.pointsPerFrame, accuracy: 0.5)
        // At least the fingers' travel less the pan's 10 pt of slop, and more if the scroll view's own
        // momentum carried it on — which is its doing and not this change's.
        let scrolled = before.originX - after.originX
        XCTAssertGreaterThanOrEqual(scrolled, 120,
                                    "The rows scrolled with the fingers: they were at \(before.originX) and are at \(after.originX)")
    }
}
