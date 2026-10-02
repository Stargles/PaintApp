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

    /// **In `.composite`, the composite and not the active layer.** Two layers, the upper one covering the lower where
    /// they overlap: a pick in the overlap must return the *top* colour, which is what the artist
    /// sees. Sampling the active layer alone would return the bottom one here, since `addLayer`
    /// leaves the topmost active and this picks where both have paint.
    func testAPickReturnsWhatIsVisibleRatherThanWhatIsOnOneLayer() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.eyedropperMode = .composite
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
        manager.eyedropperMode = .composite
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
        manager.eyedropperMode = .composite
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

    // MARK: - Holding the revert back until the picking touch is gone

    /// **The colour and the tool move at different moments, and `revertTool: false` is what buys the
    /// gap.** The owner reported on 2026-08-17 that a pick also painted a stroke; the outer half of
    /// that was `shouldInteract` (see `ToolLogicTests`), and this is the inner half. The composite
    /// runs off the main thread, so a pick very often resolves while the picking touch is *still
    /// down* — and reverting there hands a painting tool back under a finger already on the glass,
    /// which `CanvasView.reconcileLayers` then makes the layer host interactive for on its next
    /// pass. `CanvasView.handleEyedropperPress` therefore takes the colour immediately (the rail's
    /// swatch is the artist's confirmation the pick worked) and holds the revert until the
    /// recognizer reports the touch gone.
    func testApplyingAPickWithoutTheRevertTakesTheColourAndStaysArmed() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .pen
        manager.brushColor = .black
        manager.selectEyedropper()

        let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        XCTAssertTrue(manager.applyEyedropperResult(red, revertTool: false))
        XCTAssertEqual(manager.brushColor.hexString, red.hexString,
                       "The colour lands at once — that is what tells the artist the pick worked")
        XCTAssertEqual(manager.selectedTool, .eyedropper,
                       "…and the tool does not, until the caller says the touch is over")

        // Which is what the gesture does on lift.
        manager.leaveEyedropper()
        XCTAssertEqual(manager.selectedTool, .pen)
    }

    /// A miss is held back the same way. The notice is raised immediately — it explains a tap that
    /// has already happened — but the tool the artist is holding does not change under their finger.
    func testAMissWithoutTheRevertStillSaysSoAndStaysArmed() {
        let manager = CanvasFixture.manager()
        manager.eyedropperMode = .composite
        manager.selectedTool = .eraser
        manager.notice = nil
        manager.selectEyedropper()

        XCTAssertFalse(manager.applyEyedropperResult(nil, revertTool: false))
        XCTAssertEqual(manager.notice?.kind, .nothingToPick)
        XCTAssertEqual(manager.selectedTool, .eyedropper)

        manager.leaveEyedropper()
        XCTAssertEqual(manager.selectedTool, .eraser)
    }

    /// The default is unchanged, so every caller that is *not* a live gesture — `pickColor`, and the
    /// tests above it — keeps the one-call behaviour. Asserted directly rather than only through
    /// `pickColor`, since the default is what makes the parameter safe to have added.
    func testTheRevertIsStillTheDefault() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .pencil
        manager.selectEyedropper()

        manager.applyEyedropperResult(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
        XCTAssertEqual(manager.selectedTool, .pencil)
    }

    // MARK: - The mode (TODO (119) and its follow-up)

    /// A red square on layer 0, a mid-grey **Multiply** value layer over it and a hue-shifting
    /// **effect** layer over that — so the picture the artist sees is a different colour from the one
    /// they painted, twice over. **The effect layer is left active**, the one that holds no pixels: a
    /// pick must not care which layer is selected.
    private func gradedStack() -> CanvasManager {
        let manager = CanvasFixture.manager()
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))
        manager.addValueLayer(color: PaletteColor(hex: "808080"))
        manager.layers[1].blendMode = .multiply
        manager.addValueLayer(effect: .hsvShift(Effect.HSVShift(hueDegrees: 120)))
        manager.brushColor = .black
        return manager
    }

    /// Layer 0 solid red over the whole canvas, layer 1 solid green over its left half.
    private func redUnderGreenOnTheLeft() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        manager.brushColor = .black
        return manager
    }

    private func channels(_ manager: CanvasManager) -> (r: Double, g: Double, b: Double) {
        let c = manager.brushColor.rgbaComponents
        return (c.r, c.g, c.b)
    }

    private func pick(_ manager: CanvasManager, at point: CGPoint,
                      file: StaticString = #filePath, line: UInt = #line) -> (r: Double, g: Double, b: Double)? {
        manager.brushColor = .black
        manager.selectEyedropper()
        guard manager.pickColor(atCanvasPoint: point) else { return nil }
        return channels(manager)
    }

    /// The owner's default, and the document's: a new manager reads the layer, and so does a manifest
    /// that never mentioned it.
    func testTheDefaultIsTheLayer() {
        XCTAssertEqual(CanvasFixture.manager().eyedropperMode, .layer)
        XCTAssertEqual(EditorStateManifest().eyedropperMode, .layer)
    }

    /// **The colour that was painted, whatever is composited over it and whichever layer is
    /// selected** — *"regardless of the selected layer … it should return the original color that the
    /// shape was."* Three layers hold the pick's candidates in turn as the active one — the object's
    /// own, the Multiply layer and the effect layer — and the answer never moves. The premise is
    /// asserted too: the same stack picked in `.composite` is a different colour.
    func testTheLayerModePicksThePaintedColourUnderAMultiplyAndAnEffectWhicheverLayerIsSelected() {
        let manager = gradedStack()
        let inside = CGPoint(x: 16, y: 16)

        manager.eyedropperMode = .composite
        let seen = pick(manager, at: inside)
        XCTAssertLessThan(seen?.r ?? 1, 0.2, "PREMISE: the multiply and the hue shift have taken the red out of the composite")
        XCTAssertGreaterThan(seen?.g ?? 0, 0.3, "PREMISE: the hue shift has rotated what the multiply left towards green")

        manager.eyedropperMode = .layer
        for active in 0..<manager.layers.count {
            manager.currentLayerIndex = active
            let painted = pick(manager, at: inside)
            XCTAssertEqual(painted?.r ?? -1, 1, accuracy: 1.0 / 255, "layer \(active) selected: the object's own red")
            XCTAssertEqual(painted?.g ?? -1, 0, accuracy: 1.0 / 255, "layer \(active) selected")
            XCTAssertEqual(painted?.b ?? -1, 0, accuracy: 1.0 / 255, "layer \(active) selected")
        }
    }

    /// **The object under the point is the topmost one, on whatever layer it is** — the plainest
    /// reading of *"the layer the shape belonged in"*. Where the green layer paints, the green is the
    /// shape under the finger (with layer 0 selected); where it does not, the red beneath is — with
    /// the green layer selected. The selected layer decides nothing.
    func testTheLayerModeReadsTheTopmostObjectUnderThePointOnWhicheverLayerItIs() {
        let manager = redUnderGreenOnTheLeft()

        manager.currentLayerIndex = 0
        XCTAssertEqual(pick(manager, at: CGPoint(x: 10, y: 10))?.g ?? -1, 1, accuracy: 1.0 / 255,
                       "layer 1's green is the shape under the finger, though layer 0 is selected")
        XCTAssertEqual(channels(manager).r, 0, accuracy: 1.0 / 255)

        manager.currentLayerIndex = 1
        let right = pick(manager, at: CGPoint(x: 50, y: 10))
        XCTAssertEqual(right?.r ?? -1, 1, accuracy: 1.0 / 255,
                       "layer 0's red is the shape under the finger, though layer 1 — which has nothing there — is selected")
        XCTAssertEqual(right?.g ?? -1, 0, accuracy: 1.0 / 255)
    }

    /// **A layer that is not on screen is not under the point**: its own eye, or the eye of the folder
    /// it is in. Both take the green out of the answer and leave the red beneath it.
    func testAHiddenLayerAndALayerInAHiddenFolderAreNotUnderThePoint() {
        let manager = redUnderGreenOnTheLeft()
        let onGreen = CGPoint(x: 10, y: 10)
        XCTAssertEqual(pick(manager, at: onGreen)?.g ?? -1, 1, accuracy: 1.0 / 255, "PREMISE: green is on top there")

        manager.layers[1].isVisible = false
        XCTAssertEqual(pick(manager, at: onGreen)?.r ?? -1, 1, accuracy: 1.0 / 255,
                       "a layer with its eye off is not an object")
        manager.layers[1].isVisible = true

        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        XCTAssertEqual(pick(manager, at: onGreen)?.g ?? -1, 1, accuracy: 1.0 / 255,
                       "PREMISE: a layer in a visible folder is still on top")
        manager.toggleFolderVisibility(folder)
        XCTAssertEqual(pick(manager, at: onGreen)?.r ?? -1, 1, accuracy: 1.0 / 255,
                       "a layer in a hidden folder is not an object, whatever its own eye says")
    }

    /// The layer's own opacity and blend mode are not part of the colour it holds — a 20% Multiply
    /// layer would otherwise read as a washed-out, darkened version of what was painted.
    func testTheLayersOwnOpacityAndBlendModeStandAside() {
        let manager = gradedStack()
        manager.layers[0].opacity = 0.2
        manager.layers[0].blendMode = .multiply
        let painted = pick(manager, at: CGPoint(x: 16, y: 16))
        XCTAssertEqual(painted?.r ?? -1, 1, accuracy: 1.0 / 255)
        XCTAssertEqual(painted?.g ?? -1, 0, accuracy: 1.0 / 255)
    }

    /// **A flat colour and a grade are not objects.** A Normal value layer covers the whole canvas and
    /// is visible content in the plainest sense, and an effect layer is visible too; neither is the
    /// *shape* the owner means. So a point with nothing painted under it is a miss that says so — it
    /// does not read the flat colour — while `.composite` still reads it.
    func testAFlatColourLayerAndAnEffectLayerAreNotObjects() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))
        manager.addValueLayer(color: PaletteColor(hex: "808080"))
        manager.addValueLayer(effect: .hsvShift(Effect.HSVShift(hueDegrees: 120)))
        let empty = CGPoint(x: 56, y: 56)

        manager.eyedropperMode = .composite
        XCTAssertNotNil(pick(manager, at: empty), "PREMISE: the flat grey is there to take in the composite")

        manager.eyedropperMode = .layer
        manager.notice = nil
        manager.brushColor = .black
        XCTAssertNil(pick(manager, at: empty), "…and is not an object")
        XCTAssertEqual(manager.notice?.kind, .nothingPaintedThere)
        XCTAssertEqual(manager.brushColor.hexString, Color.black.hexString, "A miss leaves the brush colour alone")
        XCTAssertTrue(manager.notice?.message.contains("painted") == true,
                      "The sentence says what is missing, and the way out is the panel's switch")
        XCTAssertEqual(CanvasNotice(.nothingToPick).message, "Nothing to pick up there.",
                       "…while the composite's own miss keeps its own sentence")
    }

    /// **A layer that grades is not an object even where it holds ink**: a vector layer in effect mode
    /// keeps its strokes as the mask its grade acts through, and `leafSnapshots` rasterizes them, so
    /// only the node's `effect` tells them from a drawing. Counted at the recipe level, where the
    /// candidates are.
    func testAVectorLayerThatGradesIsNotAnObjectEvenWhereItHoldsInk() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        let drawing = manager.currentLayerIndex
        manager.addVectorLayer()
        let grading = manager.currentLayerIndex
        for index in [drawing, grading] {
            let vector = try XCTUnwrap(manager.layers[index].cels[0].vector)
            vector.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                                          color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 12,
                                          opacity: 1,
                                          samples: [VectorSample(x: 10, y: 20, pressure: 1),
                                                    VectorSample(x: 50, y: 20, pressure: 1)],
                                          composite: .paint))
        }
        manager.layers[grading].effect = .hsvShift(Effect.HSVShift(hueDegrees: 120))
        XCTAssertNotNil(manager.layers[grading].layerEffect, "PREMISE: the layer grades")

        let full = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, quality: .full, includeBackground: true))
        let candidates = CanvasManager.objectRecipes(under: CGPoint(x: 30, y: 20), in: full)
        XCTAssertEqual(candidates.count, 1, "the drawing is a candidate and the grading layer is not")
    }

    /// **The colour that was painted, not its mixture with what is beneath it.** A half-transparent
    /// green over solid blue composites to a blue-green; the shape the artist is over is green. The
    /// composite is picked beside it as the premise.
    func testASoftEdgeReadsThePaintedColourAndNotTheMixWithWhatIsBeneathIt() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(UIColor(red: 0, green: 1, blue: 0, alpha: 0.5),
                                                               rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        let edge = CGPoint(x: 10, y: 10)

        manager.eyedropperMode = .composite
        XCTAssertGreaterThan(pick(manager, at: edge)?.b ?? 0, 0.3, "PREMISE: the composite carries the blue through")

        manager.eyedropperMode = .layer
        let painted = pick(manager, at: edge)
        XCTAssertEqual(painted?.g ?? -1, 1, accuracy: 2.0 / 255, "the shape's own green")
        XCTAssertEqual(painted?.b ?? -1, 0, accuracy: 2.0 / 255, "with none of the layer beneath it")
    }

    /// **An object a transformation layer has moved is found where it is shown**, not where it is
    /// stored — the leaf snapshots carry the pose, and the grade standing aside is not the geometry
    /// standing aside.
    func testAnObjectUnderATransformLayerIsFoundWhereItIsShown() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 8, y: 8, width: 16, height: 16)))
        manager.addTransformLayer()
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 24, y: 0)), mode: .move)

        XCTAssertEqual(pick(manager, at: CGPoint(x: 40, y: 16))?.r ?? -1, 1, accuracy: 1.0 / 255,
                       "the red is shown 24 points to the right of where it is stored")
        XCTAssertNil(pick(manager, at: CGPoint(x: 12, y: 16)),
                     "…and nothing is shown where it is stored")
    }

    /// **The one-row band reads the same pixel the whole frame would**, at every column — the left
    /// edge, the right edge and the middle — and every row. A 4 × 4 grid of distinct colours, picked
    /// in both modes where the paper cannot show: the two answers must agree cell by cell.
    func testTheBandReadsTheSamePixelAsTheWholeFrameAtEveryColumnAndRow() throws {
        let manager = CanvasFixture.manager()
        manager.isCanvasBackgroundVisible = false
        let size = CanvasFixture.canvasSize
        let grid = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            for column in 0..<4 {
                for row in 0..<4 {
                    UIColor(red: CGFloat(column) / 3, green: CGFloat(row) / 3,
                            blue: CGFloat((column + row) % 2), alpha: 1).setFill()
                    context.cgContext.fill(CGRect(x: column * 16, y: row * 16, width: 16, height: 16))
                }
            }
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, grid)

        for point in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 63.5, y: 0.5), CGPoint(x: 0.5, y: 63.5),
                      CGPoint(x: 63.5, y: 63.5), CGPoint(x: 17, y: 33), CGPoint(x: 32, y: 32),
                      CGPoint(x: 47.9, y: 15.2), CGPoint(x: 5, y: 50)] {
            manager.eyedropperMode = .composite
            let whole = try XCTUnwrap(pick(manager, at: point), "composite at \(point)")
            manager.eyedropperMode = .layer
            let band = try XCTUnwrap(pick(manager, at: point), "layer at \(point)")
            XCTAssertEqual(band.r, whole.r, accuracy: 1.0 / 255, "red at \(point)")
            XCTAssertEqual(band.g, whole.g, accuracy: 1.0 / 255, "green at \(point)")
            XCTAssertEqual(band.b, whole.b, accuracy: 1.0 / 255, "blue at \(point)")
        }
    }

    /// **Recolour's `to` end follows the switch too** (owner, 2026-10-01): in the layer mode it takes the
    /// colour the object under the point was painted in; in the composite mode, the one on screen. Its
    /// `from` end keeps reading under the effect in either.
    func testARecolourPairsToEndFollowsTheSwitch() {
        let manager = gradedStack()
        manager.addValueLayer(effect: .recolor(Effect.Recolor(entries: [RecolorEntry.blank],
                                                              preserveShading: false)))
        let target = KeyframeTarget.layer(id: manager.layers[manager.currentLayerIndex].id)
        let inside = CGPoint(x: 16, y: 16)

        func picked(in mode: Eyedropper.Mode) -> CodableColor? {
            manager.eyedropperMode = mode
            manager.selectEyedropper(for: .recolorEntry(target: target, index: 0, end: .to))
            XCTAssertTrue(manager.pickColor(atCanvasPoint: inside), "\(mode): there is paint there")
            guard case .recolor(let recolor)? = manager.storedEffect(of: target) else { return nil }
            return recolor.entries[0].to
        }

        let object = picked(in: .layer)
        XCTAssertEqual(object?.red ?? -1, 1, accuracy: 2.0 / 255, "the object's own red")
        XCTAssertEqual(object?.green ?? -1, 0, accuracy: 2.0 / 255)

        let screen = picked(in: .composite)
        XCTAssertLessThan(screen?.red ?? 1, 0.2, "the screen's colour, with the grade over it")
        XCTAssertGreaterThan(screen?.green ?? 0, 0.3)
    }
}
