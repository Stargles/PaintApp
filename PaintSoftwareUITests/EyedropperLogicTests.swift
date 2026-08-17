import XCTest
import UIKit
import SwiftUI

/// The eyedropper, headlessly: the two pure halves in `Engine/Eyedropper.swift`, the view→canvas
/// mapping the feature *rests* on rather than implements, and the whole pick end to end through a
/// real `CanvasManager`.
///
/// **Why this is a logic test and not an XCUITest.** Nearly everything that can be wrong with an
/// eyedropper is invisible: an off-by-one at the far edge, a forgotten un-premultiply that darkens
/// every semi-transparent pick, a tap in the void reading the nearest edge pixel. A UI test that taps
/// the canvas and reads a swatch proves a colour arrived, not that it was the right one — and costs
/// 20 seconds to say so. These run in the fast tier and compare exact bytes.
///
/// `@MainActor` for `CompositorParityLogicTests`' reason: `makeRenderRequest` is, so everything that
/// reaches it must be.
@MainActor
final class EyedropperLogicTests: XCTestCase {

    // MARK: - Which pixel a point names

    func testAPointInsideTheCanvasNamesThePixelItIsInside() {
        let size = CGSize(width: 64, height: 64)
        // Floor, not round: a point anywhere inside pixel (1, 2) is pixel (1, 2), including at 1.9.
        XCTAssertEqual(Eyedropper.pixel(at: CGPoint(x: 0, y: 0), canvasSize: size).map { [$0.x, $0.y] }, [0, 0])
        XCTAssertEqual(Eyedropper.pixel(at: CGPoint(x: 1.9, y: 2.9), canvasSize: size).map { [$0.x, $0.y] }, [1, 2])
        XCTAssertEqual(Eyedropper.pixel(at: CGPoint(x: 1.0, y: 2.0), canvasSize: size).map { [$0.x, $0.y] }, [1, 2])
    }

    /// The far edge, which is where an off-by-one lives. A 64-wide canvas has pixels 0...63: 63.9 is
    /// the last one, and 64.0 is already past it.
    func testTheFarEdgeIsTheLastPixelAndOnePastItIsNothing() {
        let size = CGSize(width: 64, height: 64)
        XCTAssertEqual(Eyedropper.pixel(at: CGPoint(x: 63.9, y: 63.9), canvasSize: size).map { [$0.x, $0.y] }, [63, 63])
        XCTAssertNil(Eyedropper.pixel(at: CGPoint(x: 64, y: 32), canvasSize: size))
        XCTAssertNil(Eyedropper.pixel(at: CGPoint(x: 32, y: 64), canvasSize: size))
    }

    /// **Outside is nil, not clamped** — the deliberate divergence from `beginInteractiveFill`, which
    /// clamps the same coordinate. The canvas sits inside a black host at most zoom levels, so the
    /// void is a large target; clamping would hand back an edge colour the artist can see they never
    /// touched.
    func testATapOutsideTheCanvasPicksNothingRatherThanTheNearestEdge() {
        let size = CGSize(width: 64, height: 64)
        XCTAssertNil(Eyedropper.pixel(at: CGPoint(x: -0.1, y: 32), canvasSize: size))
        XCTAssertNil(Eyedropper.pixel(at: CGPoint(x: 32, y: -1), canvasSize: size))
        XCTAssertNil(Eyedropper.pixel(at: CGPoint(x: -500, y: -500), canvasSize: size))
        XCTAssertNil(Eyedropper.pixel(at: CGPoint(x: 5, y: 5), canvasSize: .zero))
    }

    // MARK: - What colour a buffer holds there

    /// One 2×2 buffer, four pixels, premultiplied last — the layout
    /// `CoreGraphicsCompositor.premultipliedBytes` produces.
    private func fourPixels() -> [UInt8] {
        [
            255, 0, 0, 255,      // (0,0) opaque red
            0, 128, 0, 255,      // (1,0) opaque half-green
            0, 0, 128, 128,      // (0,1) 50% blue — premultiplied, so straight blue is 1.0
            0, 0, 0, 0           // (1,1) empty
        ]
    }

    func testAnOpaquePixelReadsBackAsItsOwnComponents() {
        let sample = Eyedropper.color(inPremultipliedRGBA: fourPixels(), width: 2, height: 2, x: 0, y: 0)
        XCTAssertEqual(sample, Eyedropper.Sample(r: 1, g: 0, b: 0, a: 1))

        let half = Eyedropper.color(inPremultipliedRGBA: fourPixels(), width: 2, height: 2, x: 1, y: 0)
        XCTAssertEqual(half?.g ?? -1, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(half?.a ?? -1, 1, accuracy: 1e-9)
    }

    /// The un-premultiply, which is the half a screenshot cannot check. A 50%-alpha pure blue is
    /// stored as (0, 0, 128, 128); its *colour* is full blue, and a picker that skipped the divide
    /// would report a colour half as bright as the one the artist pointed at.
    func testASemiTransparentPixelReportsItsStraightColourNotItsPremultipliedOne() {
        let sample = Eyedropper.color(inPremultipliedRGBA: fourPixels(), width: 2, height: 2, x: 0, y: 1)
        XCTAssertEqual(sample?.b ?? -1, 1, accuracy: 1e-9, "128/128 is full blue, not half blue")
        XCTAssertEqual(sample?.a ?? -1, 128.0 / 255, accuracy: 1e-9, "…and the alpha is reported separately")
    }

    /// Alpha 0 is 0/0, not black. Returning black there would hand the artist a colour that was never
    /// on the canvas every time they tapped an empty patch with the paper hidden.
    func testAFullyTransparentPixelIsNothingRatherThanBlack() {
        XCTAssertNil(Eyedropper.color(inPremultipliedRGBA: fourPixels(), width: 2, height: 2, x: 1, y: 1))
    }

    /// 8-bit rounding can leave a component one step above its own alpha, which divides out past 1.
    func testUnPremultiplyingClampsAComponentThatRoundedAboveItsAlpha() {
        let bytes: [UInt8] = [8, 0, 0, 7]
        let sample = Eyedropper.color(inPremultipliedRGBA: bytes, width: 1, height: 1, x: 0, y: 0)
        XCTAssertEqual(sample?.r ?? -1, 1, accuracy: 1e-9, "8/7 is 1.14, and a colour component is not")
    }

    func testAnOutOfRangeIndexOrAShortBufferIsNothing() {
        XCTAssertNil(Eyedropper.color(inPremultipliedRGBA: fourPixels(), width: 2, height: 2, x: 2, y: 0))
        XCTAssertNil(Eyedropper.color(inPremultipliedRGBA: fourPixels(), width: 2, height: 2, x: 0, y: -1))
        XCTAssertNil(Eyedropper.color(inPremultipliedRGBA: [1, 2, 3], width: 2, height: 2, x: 1, y: 1))
    }

    // MARK: - The view→canvas mapping this feature rests on

    /// **The assumption the whole tool depends on, pinned.** `handleEyedropperPress` does no transform
    /// arithmetic: it calls `recognizer.location(in: container)` and treats the answer as a canvas
    /// pixel, exactly as `handleFillPress` has since the fill tool was written. That is only true
    /// because `CanvasView.applyTransform` sets `container.bounds` to `canvasSize` and puts the
    /// zoom/rotation on `container.transform`, so UIKit inverts the transform on the way in.
    ///
    /// This builds that arrangement and checks the round trip at 3× zoom and at 3× zoom plus 30°: a
    /// point that is the centre of canvas pixel (10, 20) is converted *out* to host space and back,
    /// and must name pixel (10, 20) again. If someone later gives the container a bounds that is not
    /// the canvas size, or moves the transform elsewhere, this fails and the doc comments that claim
    /// otherwise stop being true silently.
    func testAHostPointMapsToTheRightCanvasPixelAtAnyZoomAndRotation() {
        let canvasSize = CGSize(width: 64, height: 64)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let container = UIView()
        host.addSubview(container)
        container.bounds = CGRect(origin: .zero, size: canvasSize)
        container.center = CGPoint(x: host.bounds.midX, y: host.bounds.midY)

        // The centre of pixel (10, 20) — a half-pixel offset so rounding cannot tip it either way.
        let canvasPoint = CGPoint(x: 10.5, y: 20.5)

        for (name, transform) in [
            ("identity", CGAffineTransform.identity),
            ("3x zoom", CGAffineTransform(scaleX: 3, y: 3)),
            ("3x zoom, 30 degrees", CGAffineTransform.identity.rotated(by: .pi / 6).scaledBy(x: 3, y: 3)),
            ("0.4x zoom, -75 degrees", CGAffineTransform.identity.rotated(by: -1.309).scaledBy(x: 0.4, y: 0.4)),
        ] {
            container.transform = transform
            let inHostSpace = container.convert(canvasPoint, to: host)
            let backInCanvasSpace = host.convert(inHostSpace, to: container)
            let pixel = Eyedropper.pixel(at: backInCanvasSpace, canvasSize: canvasSize)
            XCTAssertEqual(pixel.map { [$0.x, $0.y] }, [10, 20],
                           "A host point must name the canvas pixel it is over — \(name)")
        }
    }

    // MARK: - The whole pick, through a real CanvasManager

    /// Paints a known colour over a known rect and picks inside it.
    func testPickingInsidePaintedContentTakesThatColourAsTheBrushColour() {
        let manager = CanvasFixture.manager()
        manager.brushColor = .black
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 8, y: 8, width: 16, height: 16)))

        manager.selectEyedropper()
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 12, y: 12)), "There is paint there")

        let picked = manager.brushColor.rgbaComponents
        XCTAssertEqual(picked.r, 1, accuracy: 1.0 / 255)
        XCTAssertEqual(picked.g, 0, accuracy: 1.0 / 255)
        XCTAssertEqual(picked.b, 0, accuracy: 1.0 / 255)
        XCTAssertEqual(picked.a, 1, accuracy: 1e-9, "Alpha stays the brushOpacity slider's business")
    }

    /// **The composite, not the active layer.** Two layers, the upper one covering the lower where
    /// they overlap: a pick in the overlap must return the *top* colour, which is what the artist
    /// sees. Sampling the active layer alone would return the bottom one here, since `addLayer`
    /// leaves the topmost active and this picks where both have paint.
    func testAPickReturnsWhatIsVisibleRatherThanWhatIsOnOneLayer() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))

        manager.selectEyedropper()
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 10, y: 10)))
        let overlap = manager.brushColor.rgbaComponents
        XCTAssertEqual(overlap.g, 1, accuracy: 1.0 / 255, "Green is on top there")
        XCTAssertEqual(overlap.b, 0, accuracy: 1.0 / 255)

        manager.selectEyedropper()
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 50, y: 50)))
        let uncovered = manager.brushColor.rgbaComponents
        XCTAssertEqual(uncovered.b, 1, accuracy: 1.0 / 255, "…and blue where green does not reach")
        XCTAssertEqual(uncovered.g, 0, accuracy: 1.0 / 255)
    }

    /// **The paper counts as something the artist can see.** A pick on an unpainted patch of a white
    /// canvas returns white, not "nothing here" — which is what `includeBackground: true` in
    /// `eyedropperRequest` buys, and the reason it is set.
    func testAPickOnBarePaperReturnsThePaperColour() {
        let manager = CanvasFixture.manager()
        manager.canvasBackgroundColor = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1)
        manager.isCanvasBackgroundVisible = true
        manager.brushColor = .black

        manager.selectEyedropper()
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 40, y: 40)))
        let picked = manager.brushColor.rgbaComponents
        XCTAssertEqual(picked.r, 0.2, accuracy: 2.0 / 255)
        XCTAssertEqual(picked.g, 0.4, accuracy: 2.0 / 255)
        XCTAssertEqual(picked.b, 0.6, accuracy: 2.0 / 255)
    }

    /// …and with the paper hidden, that same patch really is empty, so the pick finds nothing, says
    /// so, and leaves the brush colour alone.
    func testWithThePaperHiddenAnEmptyPatchPicksNothingAndSaysSo() {
        let manager = CanvasFixture.manager()
        manager.isCanvasBackgroundVisible = false
        manager.brushColor = .black
        manager.notice = nil

        manager.selectEyedropper()
        XCTAssertFalse(manager.pickColor(atCanvasPoint: CGPoint(x: 40, y: 40)))
        XCTAssertEqual(manager.notice?.kind, .nothingToPick)
        XCTAssertEqual(manager.brushColor.hexString, Color.black.hexString,
                       "A miss must not move the colour")
    }

    func testATapOffTheCanvasPicksNothing() {
        let manager = CanvasFixture.manager()
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.brushColor = .black

        manager.selectEyedropper()
        XCTAssertFalse(manager.pickColor(atCanvasPoint: CGPoint(x: 200, y: 200)),
                       "Past the paper's edge there is no colour, even on a fully painted canvas")
        XCTAssertEqual(manager.brushColor.hexString, Color.black.hexString)
    }

    // MARK: - Reverting

    /// The tool is momentary — see `Tool.eyedropper`. Whichever tool was selected when the eyedropper
    /// was armed is the one a completed pick returns to.
    func testPickingRevertsToTheToolThatWasSelectedBefore() {
        for previous in [Tool.pen, .pencil, .eraser, .fill] {
            let manager = CanvasFixture.manager()
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
            manager.selectedTool = previous
            manager.selectEyedropper()
            XCTAssertEqual(manager.selectedTool, .eyedropper)

            manager.pickColor(atCanvasPoint: CGPoint(x: 10, y: 10))
            XCTAssertEqual(manager.selectedTool, previous,
                           "A pick hands the canvas back to \(previous)")
        }
    }

    /// **A miss reverts too.** The artist took their one shot; leaving them armed so the next tap can
    /// also do nothing is not a kindness, and the notice already explains what happened.
    func testAMissRevertsAsWellAsAHit() {
        let manager = CanvasFixture.manager()
        manager.isCanvasBackgroundVisible = false
        manager.selectedTool = .eraser
        manager.selectEyedropper()

        XCTAssertFalse(manager.pickColor(atCanvasPoint: CGPoint(x: 40, y: 40)))
        XCTAssertEqual(manager.selectedTool, .eraser)
    }

    /// Arming twice must not make the eyedropper its own "previous tool" — that would strand the
    /// artist in it, since reverting would land back where they already were.
    func testArmingTheEyedropperTwiceStillRevertsToTheRealPreviousTool() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .pencil
        manager.selectEyedropper()
        manager.selectEyedropper()
        manager.leaveEyedropper()
        XCTAssertEqual(manager.selectedTool, .pencil)
    }

    /// The sidebar button toggles rather than only arming, so a mis-tap costs one tap.
    func testLeavingWithoutPickingGoesBackToo() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .fill
        manager.selectEyedropper()
        XCTAssertEqual(manager.selectedTool, .eyedropper)
        manager.leaveEyedropper()
        XCTAssertEqual(manager.selectedTool, .fill)
    }
}
