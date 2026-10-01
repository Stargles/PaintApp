import XCTest
import CoreGraphics

/// The one rule the canvas and the timeline both zoom by: the point of the content that was under the
/// fingers when the gesture began stays under them.
///
/// **Every assertion here is about the anchored point landing under the fingers**, derived from the
/// fixture by carrying that point through the transform by hand — never by calling the function under
/// test twice and comparing it with itself. The operands are the two things the claim names: where the
/// content's point *is* after the gesture, and where the fingers *are*.
final class ViewportAnchorLogicTests: XCTestCase {

    /// Where a content point lands in the viewport, for a content whose origin sits at `origin` and
    /// which has been scaled and turned about it. Written out here, not taken from the anchor.
    private func viewportPoint(ofContentOffset offset: CGPoint, origin: CGPoint,
                               scale: CGFloat, rotation: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + scale * (offset.x * cos(rotation) - offset.y * sin(rotation)),
                y: origin.y + scale * (offset.x * sin(rotation) + offset.y * cos(rotation)))
    }

    /// The identity: a gesture that has not changed anything leaves the content's origin where it was,
    /// wherever the fingers happen to be. This is the case that says the two spaces are crossed
    /// consistently in both directions rather than cancelling for one particular finger position.
    func testAGestureThatChangesNothingLeavesTheOriginWhereItWas() {
        for fingers in [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: -40), CGPoint(x: 1200.5, y: 800)] {
            let origin = CGPoint(x: 512, y: 384)
            let anchor = ViewportAnchor(fingers: fingers, contentOrigin: origin)
            let after = anchor.contentOrigin(fingersAt: fingers)
            XCTAssertEqual(after.x, origin.x, accuracy: 0.0001)
            XCTAssertEqual(after.y, origin.y, accuracy: 0.0001)
        }
    }

    /// **A pan is this rule at scale 1.** The fingers travel by `delta` and the content travels by
    /// exactly `delta` — which is the canvas's "offset by however far the fingers moved".
    func testAPlainPanMovesTheContentByTheFingersTravel() {
        let origin = CGPoint(x: 100, y: 200)
        let start = CGPoint(x: 340, y: 410)
        let anchor = ViewportAnchor(fingers: start, contentOrigin: origin)
        let after = anchor.contentOrigin(fingersAt: CGPoint(x: start.x + 75, y: start.y - 30))
        XCTAssertEqual(after.x, origin.x + 75, accuracy: 0.0001)
        XCTAssertEqual(after.y, origin.y - 30, accuracy: 0.0001)
    }

    /// **The defining property, over the whole table of gestures**: carry the anchored content point
    /// through the scale and the turn about the new origin and it lands under the fingers. The table
    /// mixes zooming in and out, turning both ways, and fingers that travel as they do it, because a
    /// version that handles each of those alone and not their composition is the version that fails.
    func testTheAnchoredPointStaysUnderTheFingersThroughAnyScaleRotationAndTravel() {
        let origin = CGPoint(x: 512, y: 384)
        let start = CGPoint(x: 700, y: 250)
        let anchor = ViewportAnchor(fingers: start, contentOrigin: origin)
        let anchoredPoint = anchor.offsetFromOrigin
        for (scale, rotation, travel) in [(CGFloat(1.0), CGFloat(0), CGSize(width: 0, height: 0)),
                                          (2.5, 0, CGSize(width: 0, height: 0)),
                                          (0.4, 0, CGSize(width: 90, height: -20)),
                                          (1.0, .pi / 2, CGSize(width: 0, height: 0)),
                                          (1.7, -0.6, CGSize(width: -140, height: 60)),
                                          (0.8, 2.9, CGSize(width: 33, height: 33))] {
            let fingers = CGPoint(x: start.x + travel.width, y: start.y + travel.height)
            let newOrigin = anchor.contentOrigin(fingersAt: fingers, scale: scale, rotation: rotation)
            let landed = viewportPoint(ofContentOffset: anchoredPoint, origin: newOrigin,
                                       scale: scale, rotation: rotation)
            XCTAssertEqual(landed.x, fingers.x, accuracy: 0.0001,
                           "scale \(scale), rotation \(rotation), travel \(travel): x")
            XCTAssertEqual(landed.y, fingers.y, accuracy: 0.0001,
                           "scale \(scale), rotation \(rotation), travel \(travel): y")
        }
    }

    /// A hand-computed case, so the property above is not the only witness: the fingers at (10, 0)
    /// from the origin, turned a quarter and doubled, put the anchored point 20 below the origin
    /// (the vector (10, 0) rotated to (0, 10) and doubled to (0, 20)), so the origin must sit 20
    /// above the fingers.
    func testAQuarterTurnAndADoubleHandComputed() {
        let anchor = ViewportAnchor(fingers: CGPoint(x: 110, y: 50), contentOrigin: CGPoint(x: 100, y: 50))
        let origin = anchor.contentOrigin(fingersAt: CGPoint(x: 110, y: 50), scale: 2, rotation: .pi / 2)
        XCTAssertEqual(origin.x, 110, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 30, accuracy: 0.0001)
    }
}
