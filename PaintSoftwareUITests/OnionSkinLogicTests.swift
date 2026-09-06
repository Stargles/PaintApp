import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for the onion-skin feature: the source, the linked-opacity ramp, the slot
/// planner's index arithmetic, and the composite's memory ceiling.
///
/// `testVectorCelWithStrokeProducesNonBlankOnionSkin` pins a fixed bug: onion skin used to read
/// `cel.raster` directly, which is empty for a `.vector` cel, so a vector layer onion-skinned blank.
///
/// **Every source fixture here needs TWO cels, and that is the point rather than an incidental
/// detail.** These tests were originally written against a single cel spanning the whole scene — the
/// shape `addVectorLayer` actually mints — with the playhead at frame 1. In that document "the cel at
/// `currentFrame - 1`" and "the cel the playhead is in" are *the same object*, so a test asserting
/// the source returns "the previous cel" was comparing the current cel against itself and could not
/// have failed. It stayed green while pinning the defect it was named for: the onion skin drew the
/// artwork being drawn on as a 30% ghost of itself, and because that ghost was unmasked, a masked
/// layer leaked ink outside its mask everywhere except frame 0. A one-cel fixture cannot tell the
/// two apart; a two-cel fixture with *distinguishable* content can, which is why
/// `assertCelsAreDistinguishable` runs before anything is asserted about which one came back.
final class OnionSkinLogicTests: XCTestCase {

    private func fixedBrush(size: CGFloat = 10) -> Brush {
        Brush(name: "test", tip: .round, size: size)
    }

    private func opaqueRedStroke() -> VectorStroke {
        VectorStroke(brush: fixedBrush(), color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                     size: 10, opacity: 1,
                     samples: [VectorSample(x: 10, y: 10, pressure: 1), VectorSample(x: 40, y: 40, pressure: 1)])
    }

    /// Deliberately a different colour *and* a different path from `opaqueRedStroke`, so the two
    /// cels cannot rasterize to equal bytes and a test that returns the wrong one is caught.
    private func opaqueBlueStroke() -> VectorStroke {
        VectorStroke(brush: fixedBrush(), color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: 10, opacity: 1,
                     samples: [VectorSample(x: 10, y: 40, pressure: 1), VectorSample(x: 40, y: 10, pressure: 1)])
    }

    /// True if any pixel in `image` has non-zero alpha.
    private func hasVisibleContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] != 0 { return true }
        return false
    }

    /// A vector layer with two adjacent cels — 0..5 carrying the red stroke, 6..11 the blue one.
    /// This is the document `addVectorLayer` does *not* make, which is exactly why it is needed:
    /// the shipped shape is one cel over the whole scene.
    private func twoCelManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        let size = CanvasFixture.canvasSize

        var first = Cel(id: UUID(), startFrame: 0, frameCount: 6,
                        raster: .empty(size: size), vector: .empty(size: size))
        first.vector?.addStroke(opaqueRedStroke())
        var second = Cel(id: UUID(), startFrame: 6, frameCount: 6,
                         raster: .empty(size: size), vector: .empty(size: size))
        second.vector?.addStroke(opaqueBlueStroke())
        manager.layers[0].cels = [first, second]
        // The shipped default is Tinted, which recolours the ink — every "which cel came back"
        // assertion below compares raw rasterized bytes, so the fixture asks for the colours it is
        // about to compare against. Tinting is exercised by `testTintedColouringTintsEachSide`.
        manager.onionSkin.colouring = .originalColors
        return manager
    }

    /// The premise every "which cel came back" assertion below depends on. Without it a fixture
    /// whose two cels rasterize identically would pass those assertions while proving nothing —
    /// the failure mode that let the original one-cel version of this file stay green.
    private func assertCelsAreDistinguishable(_ manager: CanvasManager,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let first = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        let second = PixelOps.rasterize(cel: manager.layers[0].cels[1], canvasSize: CanvasFixture.canvasSize)
        XCTAssertTrue(hasVisibleContent(first), "fixture cel 0 must actually have ink", file: file, line: line)
        XCTAssertTrue(hasVisibleContent(second), "fixture cel 1 must actually have ink", file: file, line: line)
        XCTAssertNotEqual(first.pngData(), second.pngData(),
                          "the two cels must be distinguishable or nothing below can tell them apart",
                          file: file, line: line)
    }

    // MARK: - The source

    func testVectorCelWithStrokeProducesNonBlankOnionSkin() {
        let manager = twoCelManager()
        assertCelsAreDistinguishable(manager)
        manager.currentFrame = 8          // inside cel 1, so cel 0 is a genuine previous cel

        let frames = OnionSkinSettingsSource().frames(for: manager)

        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(hasVisibleContent(frames[0].image), "a vector cel with a stroke must not onion-skin blank")
    }

    func testDefaultSettingsReturnExactlyThePreviousCel() {
        let manager = twoCelManager()
        assertCelsAreDistinguishable(manager)
        manager.currentFrame = 8

        // The shipped default is one skin either side; there is no cel after cel 1, so exactly one
        // comes back and it is the previous one.
        XCTAssertEqual(manager.onionSkin.previousCount, 1)
        XCTAssertEqual(manager.onionSkin.nextCount, 1)

        let previous = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        let current  = PixelOps.rasterize(cel: manager.layers[0].cels[1], canvasSize: CanvasFixture.canvasSize)
        let frames = OnionSkinSettingsSource().frames(for: manager)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].image.pngData(), previous.pngData(), "must return the PREVIOUS cel")
        XCTAssertNotEqual(frames[0].image.pngData(), current.pngData(),
                          "must not return the cel the playhead is sitting in")
        XCTAssertNil(frames[0].tint, "Original Colors was asked for")
        XCTAssertEqual(frames[0].opacity, CGFloat(manager.onionSkin.linkedLevel), accuracy: 1e-9,
                       "one skin on a side is slot 1, which the ramp puts at the level itself")
    }

    /// The product owner's bug, headless: a masked layer showed translucent ink outside its mask on
    /// every frame of a block except the first. `addVectorLayer` mints ONE cel spanning the whole
    /// scene, so from frame 5 a `currentFrame - 1` lookup resolves to that very cel and the onion
    /// skin draws the live artwork as a ghost of itself. There is no other *drawing* here, so there
    /// is nothing to onion-skin — in either neighbourhood, with or without looping.
    func testThePlayheadInsideACelDoesNotOnionSkinThatCelOntoItself() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        manager.layers[0].cels[0].vector?.addStroke(opaqueRedStroke())
        manager.onionSkin.previousCount = OnionSkinSettings.maxSkinsPerSide
        manager.onionSkin.nextCount = OnionSkinSettings.maxSkinsPerSide

        // Premise: one cel, it really does span the frame we are about to sit on, and it really
        // does carry ink — otherwise an empty result below would be trivially true.
        XCTAssertEqual(manager.layers[0].cels.count, 1)
        XCTAssertEqual(manager.activeCelIndex(inLayer: 0, atFrame: 5), 0)
        XCTAssertTrue(hasVisibleContent(PixelOps.rasterize(cel: manager.layers[0].cels[0],
                                                           canvasSize: CanvasFixture.canvasSize)))

        for neighbourhood in OnionSkinSettings.Neighbourhood.allCases {
            for loops in [false, true] {
                manager.onionSkin.neighbourhood = neighbourhood
                manager.onionSkin.loops = loops
                for frame in 0...11 {
                    manager.currentFrame = frame
                    XCTAssertTrue(OnionSkinSettingsSource().frames(for: manager).isEmpty,
                                  "frame \(frame), \(neighbourhood.rawValue), loops=\(loops): the only cel is the one being drawn on")
                }
            }
        }
    }

    func testEmptyCelReturnsNothing() {
        // Frame 0 has no previous frame — the same "nothing to show" case today's guard hides for.
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentLayerIndex = 0
        manager.currentFrame = 0

        XCTAssertTrue(OnionSkinSettingsSource().frames(for: manager).isEmpty)
    }

    func testTintedColouringTintsEachSideAndOriginalColorsDoesNot() {
        let manager = twoCelManager()
        manager.currentFrame = 3          // inside cel 0, so cel 1 is the next drawing
        manager.onionSkin.colouring = .tinted

        let tinted = OnionSkinSettingsSource().frames(for: manager)
        XCTAssertEqual(tinted.count, 1, "cel 0 is first, so only the next side has anything")
        XCTAssertEqual(tinted[0].tint, manager.onionSkin.nextTint.uiColor)

        manager.onionSkin.colouring = .originalColors
        XCTAssertNil(OnionSkinSettingsSource().frames(for: manager).first?.tint)
    }

    func testASlotAtZeroOpacityIsNotCompositedAtAll() {
        let manager = twoCelManager()
        manager.currentFrame = 8
        manager.onionSkin.linkedLevel = 0

        XCTAssertTrue(OnionSkinSettingsSource().frames(for: manager).isEmpty,
                      "a skin at zero opacity is a canvas-sized draw that produces nothing")
    }

    func testABlankCelIsSkippedRatherThanComposited() {
        let manager = twoCelManager()
        manager.layers[0].cels[0].vector = .empty(size: CanvasFixture.canvasSize)
        manager.currentFrame = 8

        XCTAssertTrue(manager.layers[0].cels[0].isCertainlyBlank)
        XCTAssertTrue(OnionSkinSettingsSource().frames(for: manager).isEmpty)
    }

    // MARK: - Linked opacity: the ramp

    /// The normalised shape, stated as literals rather than recomputed from the formula — a test that
    /// re-derives the thing under test proves only that the compiler is deterministic.
    func testTheRampShapeIsALinearFallFromTheNearestSlotToTheFurthest() {
        XCTAssertEqual(OnionSkinOpacityRamp.shape(count: 0), [])
        assertVector(OnionSkinOpacityRamp.shape(count: 1), [1])
        assertVector(OnionSkinOpacityRamp.shape(count: 2), [1, 0.5])
        assertVector(OnionSkinOpacityRamp.shape(count: 3), [1, 2.0 / 3, 1.0 / 3])
        assertVector(OnionSkinOpacityRamp.shape(count: 4), [1, 0.75, 0.5, 0.25])
        assertVector(OnionSkinOpacityRamp.shape(count: 5), [1, 0.8, 0.6, 0.4, 0.2])

        // Strictly positive everywhere, which is what keeps the furthest slider able to move the
        // level at all — a shape reaching 0 there would make `value / shape` undefined.
        for n in 1...OnionSkinSettings.maxSkinsPerSide {
            for s in OnionSkinOpacityRamp.shape(count: n) { XCTAssertGreaterThan(s, 0) }
        }
    }

    func testDraggingTheNearestSliderScalesTheWholeRamp() {
        var settings = OnionSkinSettings()
        settings.previousCount = 5
        settings.nextCount = 5

        settings.setOpacity(0.8, slot: 1, on: .previous)

        assertVector(settings.opacities(on: .previous), [0.8, 0.64, 0.48, 0.32, 0.16])
        XCTAssertEqual(settings.opacities(on: .previous)[0], 0.8, accuracy: 1e-9,
                       "the dragged slider lands exactly where the finger put it")
    }

    func testDraggingAMiddleSliderRescalesTheRampAndLandsOnTheDraggedValue() {
        var settings = OnionSkinSettings()
        settings.previousCount = 5
        settings.nextCount = 5

        settings.setOpacity(0.3, slot: 3, on: .previous)

        assertVector(settings.opacities(on: .previous), [0.5, 0.4, 0.3, 0.2, 0.1])
    }

    /// The far endpoint, and the ceiling that comes with a straight ramp. Slot 5 of 5 is one fifth of
    /// the nearest, so it tops out at 0.2 however far the finger goes — going higher would need the
    /// nearer slots above 1. Unlinking is the escape hatch and the next test shows it working.
    func testTheFurthestSliderScalesTheRampAndCannotExceedItsShareOfAFullOne() {
        var settings = OnionSkinSettings()
        settings.previousCount = 5

        settings.setOpacity(0.15, slot: 5, on: .previous)
        assertVector(settings.opacities(on: .previous), [0.75, 0.6, 0.45, 0.3, 0.15])

        settings.setOpacity(0.5, slot: 5, on: .previous)
        assertVector(settings.opacities(on: .previous), [1, 0.8, 0.6, 0.4, 0.2])
        XCTAssertEqual(settings.linkedLevel, 1, accuracy: 1e-9)
    }

    func testDraggingAnySliderToZeroZeroesEveryOtherSlider() {
        var settings = OnionSkinSettings()
        settings.previousCount = 4
        settings.nextCount = 3

        settings.setOpacity(0, slot: 2, on: .next)

        assertVector(settings.opacities(on: .previous), [0, 0, 0, 0])
        assertVector(settings.opacities(on: .next), [0, 0, 0])
        XCTAssertEqual(settings.linkedLevel, 0, accuracy: 1e-9)
    }

    /// "All the opacity sliders behave linearly to each other" — the owner's words, read as strongly
    /// as they can be: a drag on one side moves the other side too. The two sides have different
    /// counts here precisely so this cannot pass by the vectors happening to be identical.
    func testALinkedDragOnOneSideMovesTheOtherSide() {
        var settings = OnionSkinSettings()
        settings.previousCount = 3
        settings.nextCount = 2

        settings.setOpacity(0.4, slot: 2, on: .previous)

        assertVector(settings.opacities(on: .previous), [0.6, 0.4, 0.2])
        assertVector(settings.opacities(on: .next), [0.6, 0.3])
    }

    func testUnlinkedSlidersMoveOneAtATime() {
        var settings = OnionSkinSettings()
        settings.previousCount = 4
        settings.nextCount = 4
        settings.setOpacity(0.8, slot: 1, on: .previous)
        settings.setOpacityLinked(false)

        // Unlinking freezes the ramp rather than resetting it, so the sliders do not jump the
        // instant they become independent.
        assertVector(settings.opacities(on: .previous), [0.8, 0.6, 0.4, 0.2])

        settings.setOpacity(0.05, slot: 2, on: .previous)

        assertVector(settings.opacities(on: .previous), [0.8, 0.05, 0.4, 0.2])
        assertVector(settings.opacities(on: .next), [0.8, 0.6, 0.4, 0.2],
                     "the other side must not move while unlinked")
    }

    func testLoweringAndRaisingTheCountGivesUnlinkedValuesBack() {
        var settings = OnionSkinSettings()
        settings.previousCount = 5
        settings.setOpacityLinked(false)
        settings.setOpacity(0.9, slot: 5, on: .previous)

        settings.previousCount = 2
        XCTAssertEqual(settings.opacities(on: .previous).count, 2)
        settings.previousCount = 5

        XCTAssertEqual(settings.opacities(on: .previous)[4], 0.9, accuracy: 1e-9,
                       "slot 5's value survived the count going down and back up")
    }

    func testTheLinkIsOnByDefaultAndBehindIsTheDefaultPlacement() {
        let settings = OnionSkinSettings()
        XCTAssertTrue(settings.isOpacityLinked, "the owner's emphasis: linked opacity, default on")
        XCTAssertEqual(settings.placement, .behind, "the owner's instruction: default Behind")
        XCTAssertEqual(settings.colouring, .tinted)
        XCTAssertEqual(settings.neighbourhood, .drawings)
        XCTAssertFalse(settings.loops)
    }

    private func assertVector(_ actual: [Double], _ expected: [Double], _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count,
                       "\(message) expected \(expected), got \(actual)", file: file, line: line)
        guard actual.count == expected.count else { return }
        for (index, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: 1e-9,
                           "slot \(index + 1): expected \(expected), got \(actual). \(message)",
                           file: file, line: line)
        }
    }

    // MARK: - Drawings vs Frames

    /// Three drawings, the middle one held for three frames. The playhead sits on the last frame of
    /// that held drawing, which is exactly where the two neighbourhoods disagree — and they must,
    /// or the segmented control is decoration.
    private let heldSpans = [CelSpan(start: 0, length: 1),
                             CelSpan(start: 1, length: 3),
                             CelSpan(start: 4, length: 1)]

    func testDrawingsStepsByCelRegardlessOfHowLongEachIsHeld() {
        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: heldSpans, currentCelIndex: 1, currentFrame: 3,
            neighbourhood: .drawings, loops: false, side: .previous, count: 3)
        XCTAssertEqual(previous, [0, nil, nil], "one drawing back, then off the front of the layer")

        let next = OnionSkinPlanner.resolvedCelIndices(
            spans: heldSpans, currentCelIndex: 1, currentFrame: 3,
            neighbourhood: .drawings, loops: false, side: .next, count: 3)
        XCTAssertEqual(next, [2, nil, nil])
    }

    func testFramesStepsByFrameSoAHeldDrawingFillsSeveralSlots() {
        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: heldSpans, currentCelIndex: 1, currentFrame: 3,
            neighbourhood: .frames, loops: false, side: .previous, count: 3)
        // Frames 2 and 1 are still the current drawing, so they are dropped; frame 0 is drawing 0.
        XCTAssertEqual(previous, [nil, nil, 0])

        let next = OnionSkinPlanner.resolvedCelIndices(
            spans: heldSpans, currentCelIndex: 1, currentFrame: 3,
            neighbourhood: .frames, loops: false, side: .next, count: 3)
        // Frame 4 is drawing 2; frames 5 and 6 are past the end of the layer.
        XCTAssertEqual(next, [2, nil, nil])
    }

    /// The two neighbourhoods must actually disagree somewhere, or the control is decoration. Same
    /// document, same playhead, different answers.
    func testTheTwoNeighbourhoodsDisagreeOnAHeldDrawing() {
        let drawings = OnionSkinPlanner.resolvedCelIndices(
            spans: heldSpans, currentCelIndex: 1, currentFrame: 3,
            neighbourhood: .drawings, loops: false, side: .previous, count: 3)
        let frames = OnionSkinPlanner.resolvedCelIndices(
            spans: heldSpans, currentCelIndex: 1, currentFrame: 3,
            neighbourhood: .frames, loops: false, side: .previous, count: 3)
        XCTAssertNotEqual(drawings, frames)
    }

    func testAGapUnderThePlayheadAnchorsOnTheNearestDrawingOnEachSide() {
        // Two drawings with a gap at frames 2..4 — the playhead is parked on nothing.
        let spans = [CelSpan(start: 0, length: 2), CelSpan(start: 5, length: 2)]

        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: nil, currentFrame: 3,
            neighbourhood: .drawings, loops: false, side: .previous, count: 2)
        XCTAssertEqual(previous, [0, nil], "distance 1 in a gap is the nearest drawing, not one past it")

        let next = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: nil, currentFrame: 3,
            neighbourhood: .drawings, loops: false, side: .next, count: 2)
        XCTAssertEqual(next, [1, nil])
    }

    func testAnEmptyFrameInFramesModeCostsItsSlotRatherThanBeingSkipped() {
        let spans = [CelSpan(start: 0, length: 2), CelSpan(start: 5, length: 2)]
        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 1, currentFrame: 5,
            neighbourhood: .frames, loops: false, side: .previous, count: 4)
        // Frames 4 and 3 and 2 are the gap; frame 1 is drawing 0. Timing-faithful by construction.
        XCTAssertEqual(previous, [nil, nil, nil, 0])
    }

    // MARK: - Loop wrap-around

    func testLoopWrapsDrawingsAroundTheEndsOfTheLayer() {
        let spans = (0..<3).map { CelSpan(start: $0, length: 1) }

        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 0,
            neighbourhood: .drawings, loops: true, side: .previous, count: 3)
        // -1, -2, -3 modulo 3 is 2, 1, 0 — and 0 is the current drawing, which is never skinned.
        XCTAssertEqual(previous, [2, 1, nil])

        let next = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 0,
            neighbourhood: .drawings, loops: true, side: .next, count: 3)
        XCTAssertEqual(next, [1, 2, nil])
    }

    func testWithoutLoopTheSameSlotsAreSimplyEmpty() {
        let spans = (0..<3).map { CelSpan(start: $0, length: 1) }
        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 0,
            neighbourhood: .drawings, loops: false, side: .previous, count: 3)
        XCTAssertEqual(previous, [nil, nil, nil],
                       "the negative index must not wrap — Swift's `%` would have made it -1")
    }

    /// A layer shorter than the skin count is where off-by-ones live: the wrap goes round more than
    /// once, and every second slot lands back on the current drawing.
    func testALayerShorterThanTheSkinCountWrapsRepeatedlyAndStillNeverShowsTheCurrentDrawing() {
        let spans = [CelSpan(start: 0, length: 1), CelSpan(start: 1, length: 1)]

        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 0,
            neighbourhood: .drawings, loops: true, side: .previous, count: 5)
        XCTAssertEqual(previous, [1, nil, 1, nil, 1],
                       "two drawings asked for five skins: the other one, repeated, never this one")

        let next = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 0,
            neighbourhood: .drawings, loops: true, side: .next, count: 5)
        XCTAssertEqual(next, [1, nil, 1, nil, 1])
    }

    func testASingleDrawingLayerLoopsToNothingRatherThanToItself() {
        let spans = [CelSpan(start: 0, length: 4)]
        for side in OnionSkinSettings.Side.allCases {
            let slots = OnionSkinPlanner.resolvedCelIndices(
                spans: spans, currentCelIndex: 0, currentFrame: 2,
                neighbourhood: .drawings, loops: true, side: side, count: 3)
            XCTAssertEqual(slots, [nil, nil, nil], "\(side.rawValue): one drawing has no neighbours")
        }
    }

    func testLoopWrapsFramesAroundTheLayersOwnExtent() {
        // Drawing 0 covers frames 0..2, drawing 1 covers 3..4; the layer spans 5 frames.
        let spans = [CelSpan(start: 0, length: 3), CelSpan(start: 3, length: 2)]

        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 0,
            neighbourhood: .frames, loops: true, side: .previous, count: 3)
        // -1, -2, -3 wrap to 4, 3, 2. Frames 4 and 3 are drawing 1; frame 2 is the current drawing.
        XCTAssertEqual(previous, [1, 1, nil])
    }

    func testFrameWrapIgnoresEmptyFramesBeforeTheLayerStarts() {
        // The artist began drawing at frame 4; frames 0..3 were never part of the cycle.
        let spans = [CelSpan(start: 4, length: 1), CelSpan(start: 5, length: 1)]
        let previous = OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 0, currentFrame: 4,
            neighbourhood: .frames, loops: true, side: .previous, count: 2)
        // The cycle is frames 4..5, so stepping back from 4 lands on 5, then on 4 (the current one).
        XCTAssertEqual(previous, [1, nil])
    }

    func testPositiveModuloIsPositiveForNegativeInputs() {
        XCTAssertEqual(OnionSkinPlanner.positiveModulo(-1, 3), 2)
        XCTAssertEqual(OnionSkinPlanner.positiveModulo(-3, 3), 0)
        XCTAssertEqual(OnionSkinPlanner.positiveModulo(-4, 3), 2)
        XCTAssertEqual(OnionSkinPlanner.positiveModulo(4, 3), 1)
        XCTAssertEqual(OnionSkinPlanner.positiveModulo(5, 0), 0, "no crash on an empty layer")
    }

    func testACountOfZeroAsksForNothing() {
        let spans = (0..<3).map { CelSpan(start: $0, length: 1) }
        XCTAssertEqual(OnionSkinPlanner.resolvedCelIndices(
            spans: spans, currentCelIndex: 1, currentFrame: 1,
            neighbourhood: .drawings, loops: true, side: .previous, count: 0), [])
    }

    // MARK: - Resolution and memory ceiling

    /// The resolution rule: the artist's fraction, floored at a readable size, never scaled up.
    /// Pinned against a stated fraction and floor rather than the shipped constants, so moving either
    /// is a product decision and not a test failure.
    func testResolutionAppliesTheFractionThenTheReadableFloorAndNeverScalesUp() {
        let floor: CGFloat = 768
        func size(_ canvas: CGFloat, _ fraction: CGFloat) -> CGSize {
            OnionSkinBudget.compositeSize(for: CGSize(width: canvas, height: canvas),
                                          fraction: fraction, floorEdge: floor)
        }

        // A big canvas: the fraction is what is in force and the floor never binds.
        XCTAssertEqual(size(4096, 1.0), CGSize(width: 4096, height: 4096))
        XCTAssertEqual(size(4096, 0.5), CGSize(width: 2048, height: 2048))
        XCTAssertEqual(size(4096, 0.25), CGSize(width: 1024, height: 1024))

        // **A small canvas is where a pure fraction would be wrong.** Half of 1024 is 512, which the
        // resolution sweep showed collapsing hatching into moiré — so the floor raises it.
        XCTAssertEqual(size(1024, 0.5), CGSize(width: floor, height: floor))
        XCTAssertEqual(size(1024, 0.25), CGSize(width: floor, height: floor))
        XCTAssertEqual(size(2048, 0.25), CGSize(width: floor, height: floor))

        // And the floor must never magnify a skin above the artwork it ghosts.
        XCTAssertEqual(size(512, 0.25), CGSize(width: 512, height: 512),
                       "the floor may raise a skin toward the canvas, never past it")
        XCTAssertEqual(size(700, 0.5), CGSize(width: 700, height: 700))

        // Aspect is preserved and it is the *longest* edge the rule acts on, so a wide canvas is not
        // squared off and does not sneak past on its long side.
        XCTAssertEqual(OnionSkinBudget.compositeSize(for: CGSize(width: 4096, height: 2048),
                                                     fraction: 0.25, floorEdge: floor),
                       CGSize(width: 1024, height: 512))
    }

    /// The shipped options, as the owner named them, and the default they asked for.
    func testTheShippedResolutionsAreFullHalfQuarterAndDefaultToHalf() {
        XCTAssertEqual(OnionSkinSettings().resolution, .half, "the owner's call: default half resolution")
        XCTAssertEqual(OnionSkinSettings.Resolution.allCases.map(\.fraction), [1, 0.5, 0.25])
        let canvas = CGSize(width: 4096, height: 4096)
        XCTAssertEqual(OnionSkinBudget.compositeSize(for: canvas, resolution: .full), canvas,
                       "Full must mean full — no reduction, and so nothing for the source cache to hold")
        XCTAssertEqual(OnionSkinBudget.compositeSize(for: canvas, resolution: .half),
                       CGSize(width: 2048, height: 2048))
    }

    /// **The whole memory claim, as arithmetic rather than as prose**, now that the artist can choose
    /// how big an entry is. The cache is bounded in *bytes*, so a resolution that makes entries four
    /// times larger holds four times fewer of them rather than four times the memory.
    func testTheSourceCacheIsBoundedInBytesAtEveryResolution() {
        let canvas = CGSize(width: 4096, height: 4096)
        for resolution in OnionSkinSettings.Resolution.allCases {
            let ceiling = OnionSkinBudget.residentCeilingBytes(for: canvas, resolution: resolution)
            XCTAssertLessThanOrEqual(ceiling, OnionSkinBudget.residentBudgetBytes,
                                     "\(resolution.rawValue): the budget covers the composite too, or the "
                                     + "total is whatever the arithmetic happens to give — which is how Half "
                                     + "once reported a higher ceiling than Full")
        }
        // And a third of the compositor's own budget on the owner's 3 GB iPad: a reference the artist
        // looks *through* may not outweigh a third of the thing it references.
        let compositorBudget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024)
        XCTAssertLessThanOrEqual(OnionSkinBudget.residentBudgetBytes, compositorBudget / 3)

        // A quarter-resolution entry is a sixteenth of a full-resolution one, so the cache holds many
        // more of them — the count falls out of the size rather than being fixed.
        let quarterEntry = 1024 * 1024 * 4
        let halfEntry = 2048 * 2048 * 4
        XCTAssertGreaterThan(OnionSkinBudget.sourceCacheLimit(entryBytes: quarterEntry),
                             OnionSkinBudget.sourceCacheLimit(entryBytes: halfEntry))
        XCTAssertGreaterThanOrEqual(OnionSkinBudget.sourceCacheLimit(entryBytes: 512 * 1024 * 1024),
                                    OnionSkinBudget.minimumSourceCacheEntries,
                                    "even an absurd entry size must leave room for the default two skins")
        XCTAssertGreaterThan(OnionSkinBudget.sourceCacheLimit(entryBytes: quarterEntry),
                             OnionSkinSettings.maxSkinsPerSide * 2,
                             "at the cheap end the cache must still be larger than the window it caches")
    }

    /// **Changing the resolution must not serve skins at the old one.** Both caches key on the size,
    /// and this is the assertion that says so rather than the comment that hopes so.
    func testChangingResolutionMintsFreshSourcesRatherThanReusingTheOldOnes() {
        let canvas = CGSize(width: 4096, height: 4096)
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas))
        cel.bakedImage = CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 2000, height: 2000),
                                                  size: canvas)
        OnionSkinRasterCache.removeAll()

        let quarter = OnionSkinBudget.compositeSize(for: canvas, resolution: .quarter)
        let half = OnionSkinBudget.compositeSize(for: canvas, resolution: .half)
        XCTAssertNotEqual(quarter, half, "premise: the two settings really do differ on this canvas")

        let atQuarter = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: quarter)
        let atHalf = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: half)
        XCTAssertEqual(atQuarter.size, quarter)
        XCTAssertEqual(atHalf.size, half)
        XCTAssertFalse(atQuarter === atHalf, "a resolution change must not hand back the old size")
        // And going back is still a hit, so flipping between two settings does not re-render both.
        XCTAssertTrue(OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: quarter) === atQuarter)
        OnionSkinRasterCache.removeAll()
    }

    /// A reduced source is built once per cel version and then handed back by identity — the property
    /// the rebuild cost depends on, asserted rather than assumed. `===`, not `==`: an equal image
    /// rebuilt every call would pass a content comparison and would have fixed nothing.
    func testAReducedSourceIsBuiltOncePerCelVersionAndSkippedEntirelyWhenNoReductionIsNeeded() {
        let canvas = CGSize(width: 2048, height: 2048)
        let small = OnionSkinBudget.compositeSize(for: canvas, resolution: .quarter)
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas))
        cel.bakedImage = CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 900, height: 900),
                                                  size: canvas)
        OnionSkinRasterCache.removeAll()

        let first = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: small)
        let second = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: small)
        XCTAssertTrue(first === second, "the second call must be a cache hit, not an equal rebuild")
        XCTAssertEqual(first.size, small)

        // Editing the cel is a new version, so it must *not* hit — a cache that served the old
        // pixels here would show the artist a stale ghost of their own drawing.
        cel.bakedImage = CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: 500, height: 500),
                                                  size: canvas)
        XCTAssertFalse(OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: small) === first)

        // And a canvas already within the cap is passed straight through: same object as the shared
        // rasterize, no second copy, nothing added to this cache at all.
        OnionSkinRasterCache.removeAll()
        let tiny = CanvasFixture.canvasSize
        var smallCel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: tiny))
        smallCel.bakedImage = CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        let passthrough = OnionSkinRasterCache.image(for: smallCel, canvasSize: tiny,
                                                     at: OnionSkinBudget.compositeSize(for: tiny, resolution: .quarter))
        XCTAssertTrue(passthrough === PixelOps.rasterize(cel: smallCel, canvasSize: tiny))
        XCTAssertEqual(OnionSkinRasterCache.residentBytes, 0,
                       "a document under the cap must not fill an onion cache it has no use for")
    }

    func testTheSourceCacheEvictsRatherThanGrowing() {
        let canvas = CGSize(width: 2048, height: 2048)
        let small = OnionSkinBudget.compositeSize(for: canvas, resolution: .quarter)
        let perEntry = Int(small.width.rounded()) * Int(small.height.rounded()) * 4
        let limit = OnionSkinBudget.sourceCacheLimit(entryBytes: perEntry)
        OnionSkinRasterCache.removeAll()
        for index in 0..<(limit + 4) {
            var cel = Cel(id: UUID(), startFrame: index, frameCount: 1, raster: .empty(size: canvas))
            cel.bakedImage = CanvasFixture.solidImage(.red,
                                                      rect: CGRect(x: index, y: 0, width: 40, height: 40),
                                                      size: canvas)
            _ = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: small)
        }
        XCTAssertLessThanOrEqual(OnionSkinRasterCache.residentBytes, perEntry * limit,
                                 "more cels than the limit must evict, not accumulate")
        OnionSkinRasterCache.removeAll()
        XCTAssertEqual(OnionSkinRasterCache.residentBytes, 0)
    }

    // MARK: - What the panel says a rebuild will cost

    /// The owner's canvas (TODO.md, 2026-08-17) and the stress case every earlier onion figure was
    /// taken at, named once so the tables below cannot drift apart from each other.
    private static let ownerCanvas = CGSize(width: 2048, height: 1024)
    private static let stressCanvas = CGSize(width: 4096, height: 4096)

    /// A 3 GB iPad 9's texture budget, stated rather than read — the estimate's cache arithmetic
    /// depends on it and the machine running this test is not that device.
    private static let deviceBudget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024)

    private func settings(_ resolution: OnionSkinSettings.Resolution, skins: Int) -> OnionSkinSettings {
        var settings = OnionSkinSettings()
        settings.resolution = resolution
        settings.previousCount = min(skins, OnionSkinSettings.maxSkinsPerSide)
        settings.nextCount = max(0, skins - settings.previousCount)
        return settings
    }

    /// **The test that stops the calibration constant rotting.**
    ///
    /// `OnionSkinBudget`'s four timing constants were fitted to measurements taken on the owner's
    /// iPad 9 (A13, 3 GB) in Release on 2026-08-18 by
    /// `PerfBaselineTests.testOnionSkinCostOfEachResolutionOption`. Nothing in the app re-measures
    /// them, so without this they are four numbers that will quietly stop describing the device the
    /// moment anything about the composite or the flatten changes — and the caution built on them
    /// would go on speaking with total confidence.
    ///
    /// Each row is `composite + misses x miss`, both halves measured. The composite figures are the
    /// device's own; the per-miss figures are the simulator's from the same test scaled by the 1.26x
    /// device factor that the composite rows of the same pair of runs establish, except the 4096
    /// Quarter one, which the device reported directly as `sourceMiss = 122.3 ms`.
    ///
    /// **Ten skins, not two, and that is the calibration point rather than an arbitrary choice.**
    /// The composite constant is the ten-skin slope (11.5 ms/MP/skin against 9.2 at two), because a
    /// caution is about the expensive end and the difference between the two is fixed per-composite
    /// overhead. Two-skin cases are therefore *over*-estimated on purpose, which the test below
    /// pins in that direction rather than leaving to be discovered as a discrepancy.
    func testTheRebuildEstimateReproducesTheMeasuredDeviceFigures() {
        // canvas, resolution, measured composite at 10 skins, measured cost of one miss
        let measured: [(CGSize, OnionSkinSettings.Resolution, Double, Double)] = [
            (Self.ownerCanvas,  .full,    237.1,  13.0),
            (Self.ownerCanvas,  .half,     59.8,  20.4),
            (Self.ownerCanvas,  .quarter,  33.9,  17.9),
            (Self.stressCanvas, .full,   1953.8, 103.8),
            (Self.stressCanvas, .half,    486.2, 161.8),
            (Self.stressCanvas, .quarter, 120.6, 122.3),
        ]

        for (canvas, resolution, composite, miss) in measured {
            let size = OnionSkinBudget.compositeSize(for: canvas, resolution: resolution)
            // The miss half on its own first, so a failure says which of the two terms moved.
            let predictedMiss = OnionSkinBudget.sourceMissMilliseconds(canvasSize: canvas, compositeSize: size)
            XCTAssertEqual(predictedMiss, miss, accuracy: miss * 0.1,
                           "one source miss at \(resolution.title) on \(Int(canvas.width))x\(Int(canvas.height))")

            let misses = OnionSkinBudget.sourceMissesPerRebuild(for: canvas, resolution: resolution,
                                                                skins: 10,
                                                                sharedBudgetBytes: Self.deviceBudget)
            let expected = composite + Double(misses) * miss
            let estimate = OnionSkinBudget.estimatedRebuildMilliseconds(
                for: canvas, resolution: resolution, skins: 10, sharedBudgetBytes: Self.deviceBudget)
            XCTAssertEqual(estimate, expected, accuracy: expected * 0.1,
                           "ten skins at \(resolution.title) on \(Int(canvas.width))x\(Int(canvas.height))")
        }

        // And the deliberate bias at the cheap end: two skins are over-estimated, never under, so a
        // caution can only ever be early rather than late.
        for (canvas, resolution, _, miss) in measured {
            let misses = OnionSkinBudget.sourceMissesPerRebuild(for: canvas, resolution: resolution,
                                                                skins: 2, sharedBudgetBytes: Self.deviceBudget)
            let estimate = OnionSkinBudget.estimatedRebuildMilliseconds(
                for: canvas, resolution: resolution, skins: 2, sharedBudgetBytes: Self.deviceBudget)
            let floor = Double(misses) * miss
            XCTAssertGreaterThan(estimate, floor,
                                 "two skins must cost more than their misses alone")
        }
        // Two skins measured on the device at Full on the owner's canvas: 37.4 ms composite plus one
        // 13.0 ms miss. The estimate is above that and within a third of it — the over-statement is
        // bounded, not open-ended.
        let twoSkins = OnionSkinBudget.estimatedRebuildMilliseconds(
            for: Self.ownerCanvas, resolution: .full, skins: 2, sharedBudgetBytes: Self.deviceBudget)
        XCTAssertGreaterThan(twoSkins, 37.4 + 13.0)
        XCTAssertLessThan(twoSkins, (37.4 + 13.0) * 1.33)
    }

    /// **How many sources are actually held, which is the second and larger reason a combination is
    /// expensive.** A miss is tens or hundreds of milliseconds; this is what decides whether a
    /// rebuild pays one of them or ten.
    ///
    /// The Full row is the finding that this whole caution had to be designed around:
    /// `OnionSkinRasterCache` stores nothing at Full — there is no reduction to store — so the
    /// sources go through `PixelOps.rasterize` into the *compositor's* cache, whose entries are
    /// canvas-sized. On a 3 GB iPad that budget holds **three** 4096x4096 flattens in total, shared
    /// with the artwork, so a ten-skin window at Full cannot be cached at any count and every rebuild
    /// re-flattens every skin. `residentCeilingBytes` reporting 0 bytes cached there is an accounting
    /// fact about which cache pays, not a saving.
    func testTheSourceCacheCannotHoldTheWindowAtFullOnALargeCanvasNorAtHalf() {
        // 4096x4096, 3 GB device: 64 MiB an entry against a 192 MiB compositor budget.
        XCTAssertEqual(OnionSkinBudget.cachedSourceCount(for: Self.stressCanvas, resolution: .full,
                                                         sharedBudgetBytes: Self.deviceBudget), 3)
        // Half at 4096 is the thrash the branch already documented: 16 MiB an entry out of the onion
        // skin's own 64 MiB, so three fit and a ten-skin window does not.
        XCTAssertEqual(OnionSkinBudget.cachedSourceCount(for: Self.stressCanvas, resolution: .half,
                                                         sharedBudgetBytes: Self.deviceBudget), 3)
        XCTAssertEqual(OnionSkinBudget.cachedSourceCount(for: Self.stressCanvas, resolution: .quarter,
                                                         sharedBudgetBytes: Self.deviceBudget), 12)
        // The owner's canvas is a different world: 8 MiB an entry, so the compositor's own entry
        // limit is what binds rather than its bytes, and Full caches the whole window.
        XCTAssertEqual(OnionSkinBudget.cachedSourceCount(for: Self.ownerCanvas, resolution: .full,
                                                         sharedBudgetBytes: Self.deviceBudget),
                       PixelOps.sharedRasterizeEntryLimit)

        // Which turns into misses: one per rebuild when the window fits, all of them when it does
        // not. FIFO over a window scanned in the same order every rebuild has no middle ground.
        for skins in 1...10 {
            XCTAssertEqual(OnionSkinBudget.sourceMissesPerRebuild(for: Self.ownerCanvas, resolution: .full,
                                                                  skins: skins,
                                                                  sharedBudgetBytes: Self.deviceBudget), 1,
                           "the owner's canvas caches the whole window at Full")
        }
        XCTAssertEqual(OnionSkinBudget.sourceMissesPerRebuild(for: Self.stressCanvas, resolution: .full,
                                                              skins: 10, sharedBudgetBytes: Self.deviceBudget), 10)
        XCTAssertEqual(OnionSkinBudget.sourceMissesPerRebuild(for: Self.stressCanvas, resolution: .half,
                                                              skins: 10, sharedBudgetBytes: Self.deviceBudget), 10)
        // Three cached is enough for two skins plus the one arriving, and not for three.
        XCTAssertEqual(OnionSkinBudget.sourceMissesPerRebuild(for: Self.stressCanvas, resolution: .half,
                                                              skins: 2, sharedBudgetBytes: Self.deviceBudget), 1)
        XCTAssertEqual(OnionSkinBudget.sourceMissesPerRebuild(for: Self.stressCanvas, resolution: .half,
                                                              skins: 3, sharedBudgetBytes: Self.deviceBudget), 3)
    }

    /// **The threshold, from both sides.** 4096x4096 at Half straddles it on one skin: one skin
    /// estimates 208 ms and two estimate 254 ms, so this pins that the line is where
    /// `cautionThresholdMilliseconds` says it is and not merely somewhere nearby.
    func testTheCautionAppearsExactlyAtTheThresholdAndNotBefore() {
        let one = OnionSkinBudget.estimatedRebuildMilliseconds(
            for: Self.stressCanvas, resolution: .half, skins: 1, sharedBudgetBytes: Self.deviceBudget)
        let two = OnionSkinBudget.estimatedRebuildMilliseconds(
            for: Self.stressCanvas, resolution: .half, skins: 2, sharedBudgetBytes: Self.deviceBudget)
        XCTAssertLessThan(one, OnionSkinBudget.cautionThresholdMilliseconds,
                          "premise: one skin is under the threshold")
        XCTAssertGreaterThan(two, OnionSkinBudget.cautionThresholdMilliseconds,
                             "premise: two skins are over it")

        XCTAssertNil(OnionSkinBudget.caution(for: Self.stressCanvas, settings: settings(.half, skins: 1),
                                             sharedBudgetBytes: Self.deviceBudget),
                     "under the threshold the panel says nothing")
        XCTAssertNotNil(OnionSkinBudget.caution(for: Self.stressCanvas, settings: settings(.half, skins: 2),
                                                sharedBudgetBytes: Self.deviceBudget),
                        "over the threshold it speaks")

        // No skins is not a cheap onion skin, it is no onion skin, and a caution about nothing would
        // be the panel talking to itself.
        XCTAssertNil(OnionSkinBudget.caution(for: Self.stressCanvas, settings: settings(.full, skins: 0),
                                             sharedBudgetBytes: Self.deviceBudget))
    }

    /// **The owner's own canvas is silent at every setting it can be put in, and the stress case is
    /// not silent even at the shipped default.** This pair is the whole product requirement
    /// (owner, 2026-08-18) — "silent on a document where Full is fine, speaking up when it is not" —
    /// asserted rather than described.
    func testTheOwnersCanvasIsSilentEverywhereAndTheStressCanvasSpeaksAtTheDefault() {
        for resolution in OnionSkinSettings.Resolution.allCases {
            for skins in 0...(OnionSkinSettings.maxSkinsPerSide * 2) {
                XCTAssertNil(OnionSkinBudget.caution(for: Self.ownerCanvas,
                                                     settings: settings(resolution, skins: skins),
                                                     sharedBudgetBytes: Self.deviceBudget),
                             "2048x1024 at \(resolution.title) with \(skins) skins must not caution")
            }
        }
        // The most expensive thing that document can be asked to do, and the margin under the
        // threshold, both pinned — 7 ms is small enough to be worth failing on if it moves.
        let worst = OnionSkinBudget.estimatedRebuildMilliseconds(
            for: Self.ownerCanvas, resolution: .full, skins: 10, sharedBudgetBytes: Self.deviceBudget)
        XCTAssertEqual(worst, 243, accuracy: 5, "Full at ten skins on the owner's canvas")
        XCTAssertLessThan(worst, OnionSkinBudget.cautionThresholdMilliseconds)

        // The shipped default is one skin a side; the ruling was about what happens when Full is
        // chosen on top of it.
        let shipped = OnionSkinSettings()
        XCTAssertEqual(shipped.previousCount + shipped.nextCount, 2, "premise: the default is two skins")
        var fullAtDefault = shipped
        fullAtDefault.resolution = .full
        XCTAssertNil(OnionSkinBudget.caution(for: Self.ownerCanvas, settings: fullAtDefault,
                                             sharedBudgetBytes: Self.deviceBudget),
                     "Full on the owner's canvas at the shipped count is fine and must stay silent")
        guard let stress = OnionSkinBudget.caution(for: Self.stressCanvas, settings: fullAtDefault,
                                                   sharedBudgetBytes: Self.deviceBudget) else {
            return XCTFail("4096x4096 at Full must caution even at the shipped two skins")
        }

        // And what it says: the cost here, and a cheaper option that is genuinely under the
        // threshold rather than merely cheaper. Half at two skins on this canvas is 254 ms and so is
        // not an answer; Quarter at 145 ms is.
        XCTAssertTrue(stress.contains("Quarter"),
                      "the suggestion must be an option that is actually under the threshold: \(stress)")
        XCTAssertFalse(stress.contains("Half"),
                       "Half is still over the threshold at this canvas and count: \(stress)")
        XCTAssertFalse(stress.uppercased().contains("WARNING"), "it is a caution, not an alarm")

        // Half at ten skins on this canvas is the thrash case the branch already documented, and the
        // line names the setting that fixes it — which is the same answer TODO.md reached by hand.
        guard let thrashing = OnionSkinBudget.caution(for: Self.stressCanvas, settings: settings(.half, skins: 10),
                                                      sharedBudgetBytes: Self.deviceBudget) else {
            return XCTFail("Half at ten skins on 4096x4096 must caution")
        }
        XCTAssertTrue(thrashing.contains("Quarter"),
                      "Quarter at ten skins is 237 ms and is the answer here: \(thrashing)")

        // And when no option is under the threshold, the line stops recommending one and names the
        // other lever instead. An 8192x8192 document is over it at Quarter on composite cost alone.
        let huge = CGSize(width: 8192, height: 8192)
        guard let noWayOut = OnionSkinBudget.caution(for: huge, settings: settings(.quarter, skins: 10),
                                                     sharedBudgetBytes: Self.deviceBudget) else {
            return XCTFail("8192x8192 at Quarter with ten skins must caution")
        }
        XCTAssertTrue(noWayOut.contains("Fewer skins"),
                      "with nothing cheaper to suggest the line must name the count: \(noWayOut)")
    }

    /// The sizes the panel now prints under each segment, at both canvases — the factual half of the
    /// owner's ruling. Pinned here as well as in `PerfBaselineTests` because this is the string the
    /// artist reads, and the readability floor is what makes two of these six not the obvious
    /// fraction.
    func testEachResolutionOptionReportsItsRealCompositeSize() {
        let expected: [(CGSize, [(OnionSkinSettings.Resolution, CGSize)])] = [
            (Self.ownerCanvas, [(.full, CGSize(width: 2048, height: 1024)),
                                (.half, CGSize(width: 1024, height: 512)),
                                // Not 512x256: the readability floor raises the long edge to 768.
                                (.quarter, CGSize(width: 768, height: 384))]),
            (Self.stressCanvas, [(.full, CGSize(width: 4096, height: 4096)),
                                 (.half, CGSize(width: 2048, height: 2048)),
                                 (.quarter, CGSize(width: 1024, height: 1024))]),
        ]
        for (canvas, rows) in expected {
            for (resolution, size) in rows {
                XCTAssertEqual(OnionSkinBudget.compositeSize(for: canvas, resolution: resolution), size,
                               "\(resolution.title) on \(Int(canvas.width))x\(Int(canvas.height))")
            }
        }

        // The legend has to distinguish the three options or it is decoration — and on the owner's
        // canvas the floor is what keeps Quarter from collapsing onto something unreadable, so the
        // three really are three.
        let owner = OnionSkinSettings.Resolution.allCases.map {
            OnionSkinBudget.compositeSize(for: Self.ownerCanvas, resolution: $0)
        }
        XCTAssertEqual(Set(owner.map(\.width)).count, 3)
    }

    /// The read-out the caution formats with. Rounded to 10 ms because the artist is reading an
    /// estimate, and a digit that changes with a slider drag but means nothing is worse than no
    /// digit.
    func testTheDurationReadOutRoundsAndSwitchesToSecondsAtOne() {
        XCTAssertEqual(OnionSkinBudget.duration(243), "240 ms")
        XCTAssertEqual(OnionSkinBudget.duration(254), "250 ms")
        XCTAssertEqual(OnionSkinBudget.duration(994), "990 ms")
        XCTAssertEqual(OnionSkinBudget.duration(999), "1.0 s", "rounded before the unit is chosen")
        XCTAssertEqual(OnionSkinBudget.duration(1000), "1.0 s")
        XCTAssertEqual(OnionSkinBudget.duration(2880), "2.9 s")
    }

    func testTenSkinsCostOneImageNotTen() {
        // The whole memory argument in one assertion: the composite's size does not depend on how
        // many frames go into it.
        let frames = (0..<10).map { index in
            OnionSkinFrame(image: CanvasFixture.solidImage(.red, rect: CGRect(x: index, y: 0, width: 4, height: 4)),
                           opacity: 0.3, tint: nil)
        }
        let size = CGSize(width: 64, height: 64)
        guard let composite = OnionSkinFrame.composite(frames, size: size) else {
            return XCTFail("ten frames must composite")
        }
        XCTAssertEqual(composite.size, size)
        XCTAssertTrue(hasVisibleContent(composite))
    }

    // MARK: - Placement: the clip that IS "Behind" (TODO (40))

    /// Alpha per pixel, row-major from the top-left — the channel `CALayer.mask` reads and the only
    /// one any assertion below is about.
    private func alphaGrid(_ image: CGImage) -> (width: Int, height: Int, alpha: [UInt8]) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
    }

    private func alpha(_ grid: (width: Int, height: Int, alpha: [UInt8]), _ x: Int, _ y: Int) -> UInt8 {
        grid.alpha[y * grid.width + x]
    }

    private func alphaGrid(of image: UIImage) -> (width: Int, height: Int, alpha: [UInt8]) {
        alphaGrid(image.cgImage!)
    }

    /// The whole ruling in one assertion: Behind cuts the ghost where the current layer is drawn,
    /// In Front does not touch it.
    func testBehindSubtractsTheCurrentLayersInkFromTheClipAndInFrontDoesNot() {
        let size = CanvasFixture.canvasSize
        // The left half of the canvas, opaque — a shape whose inside and outside are both easy to
        // name, so a cut in the wrong place cannot look like a cut in the right one.
        let ink = CanvasFixture.solidImage(.black, rect: CGRect(x: 0, y: 0, width: 32, height: 64))

        let manager = twoCelManager()
        manager.currentFrame = 8
        manager.onionSkin.placement = .inFront
        XCTAssertNil(manager.onionSkinInkToSubtract(at: size),
                     "In Front subtracts nothing, so the clip is whatever §6.4's coverage was")
        manager.onionSkin.placement = .behind
        XCTAssertNotNil(manager.onionSkinInkToSubtract(at: size),
                        "Behind subtracts the current drawing")

        XCTAssertNil(OnionSkinClip.mask(layerMask: nil, subtracting: nil, size: size),
                     "nothing to subtract and nothing to keep is no clip at all")

        guard let behind = OnionSkinClip.mask(layerMask: nil, subtracting: ink, size: size) else {
            return XCTFail("Behind with ink present must produce a clip")
        }
        let grid = alphaGrid(behind)
        XCTAssertEqual(alpha(grid, 10, 10), 0, "the ghost is masked out where the artist's ink is")
        XCTAssertEqual(alpha(grid, 40, 10), 255, "and left whole where it is not")
        XCTAssertEqual(alpha(grid, 10, 50), 0)
        XCTAssertEqual(alpha(grid, 40, 50), 255)
    }

    /// §6.4's coverage survives the subtraction. A Behind clip that forgot it would put the ghost
    /// back outside the current layer's alpha mask — BUGS.md's "The onion skin renders unmasked",
    /// re-opened by the feature that closes (40).
    func testBehindKeepsTheLayerMaskItSubtractsFrom() {
        let size = CanvasFixture.canvasSize
        // Coverage over the top half, in the shape `ResolvedMask.makeMaskImage` produces: white
        // premultiplied by coverage, so alpha is the coverage.
        let coverage = CanvasFixture.solidImage(.white, rect: CGRect(x: 0, y: 0, width: 64, height: 32)).cgImage!
        let ink = CanvasFixture.solidImage(.black, rect: CGRect(x: 0, y: 0, width: 32, height: 64))

        guard let clip = OnionSkinClip.mask(layerMask: coverage, subtracting: ink, size: size) else {
            return XCTFail("Behind with ink present must produce a clip")
        }
        let grid = alphaGrid(clip)
        XCTAssertEqual(alpha(grid, 40, 10), 255, "inside the coverage and clear of the ink: the ghost shows")
        XCTAssertEqual(alpha(grid, 10, 10), 0, "inside the coverage but under the ink: cut")
        XCTAssertEqual(alpha(grid, 40, 50), 0, "outside the coverage: hidden, ink or no ink")
        XCTAssertEqual(alpha(grid, 10, 50), 0, "outside the coverage and under the ink: still hidden")
    }

    /// **TODO (51), the owner's 2026-09-06 reversal: Behind cuts by how much ink is there, not
    /// merely whether any is.** Pinned at two opacities on purpose — a single assertion at 100%
    /// cannot distinguish this from the old rule, since a full-opacity layer cuts fully either way.
    /// Only comparing 30% against 100% catches the defect this closes: the old code cut the ghost
    /// completely at *any* opacity above zero, so "faint ink barely dents the ghost, solid ink still
    /// hides it" could not have been true of it.
    ///
    /// Driven through `onionSkinInkToSubtract` and `onionSkinInkOpacity` exactly as
    /// `CanvasView.updateOnionSkin` calls them, rather than only `OnionSkinClip.mask`'s own
    /// parameter — a manager that computed the right opacity and never handed it to the mask would
    /// still be caught here, and would not be caught by a test that only called `mask` directly.
    func testBehindsCutIsProportionalToLayerOpacityAtTwoOpacities() {
        let manager = twoCelManager()
        manager.currentFrame = 8      // inside cel 1, the blue diagonal stroke
        let size = CanvasFixture.canvasSize

        func cutAlphaUnderInk(opacity: CGFloat) -> UInt8 {
            manager.layers[0].opacity = Double(opacity)
            guard let ink = manager.onionSkinInkToSubtract(at: size) else {
                XCTFail("premise: this layer has ink to subtract"); return 255
            }
            XCTAssertEqual(manager.onionSkinInkOpacity, opacity,
                           "premise: the accessor reads the opacity just set")
            guard let clip = OnionSkinClip.mask(layerMask: nil, subtracting: ink, size: size,
                                                opacity: manager.onionSkinInkOpacity) else {
                XCTFail("Behind with ink present must produce a clip"); return 255
            }
            // (25, 25) is the blue stroke's own midpoint, well inside its 5 pt radius — see
            // `testTheGhostIsErasedWhereTheCurrentDrawingCoversItAndSurvivesElsewhere`, which uses
            // the same point for the same reason.
            return alpha(alphaGrid(clip), 25, 25)
        }

        let full = cutAlphaUnderInk(opacity: 1)
        let faint = cutAlphaUnderInk(opacity: 0.3)

        XCTAssertEqual(full, 0, "100% opacity still cuts the ghost fully — unchanged from before the ruling")
        XCTAssertGreaterThan(faint, 150, "30% opacity must leave most of the ghost visible under faint ink")
        XCTAssertLessThan(faint, 255, "…but still cut some of it, or opacity isn't reaching the mask at all")
        XCTAssertNotEqual(faint, full,
                          "30% and 100% must cut differently — the bug this pins made every opacity cut fully")
    }

    /// The empty-layer case, which is the one an animator meets first: a blank drawing has no ink,
    /// so there is nothing for the ghost to be behind and Behind must look exactly like In Front.
    func testAnEmptyCurrentLayerLeavesTheGhostWhole() {
        let manager = twoCelManager()
        manager.currentFrame = 8
        manager.layers[0].cels[1].vector = .empty(size: CanvasFixture.canvasSize)

        XCTAssertEqual(manager.onionSkin.placement, .behind, "premise: the placement under test")
        XCTAssertNil(manager.onionSkinInkToSubtract(at: CanvasFixture.canvasSize),
                     "a cel with nothing in it subtracts nothing")
        XCTAssertNil(OnionSkinClip.mask(layerMask: nil, subtracting: nil, size: CanvasFixture.canvasSize),
                     "and no ink means no clip, so the ghost is whole")
    }

    /// A layer the artist has hidden draws no ink, so a ghost cut out by it would be cut by
    /// something nobody can see.
    func testAHiddenCurrentLayerSubtractsNothingFromTheGhost() {
        let manager = twoCelManager()
        manager.currentFrame = 8
        XCTAssertNotNil(manager.onionSkinInkToSubtract(at: CanvasFixture.canvasSize),
                        "premise: this layer does have ink to subtract while it is visible")

        manager.layers[0].isVisible = false
        XCTAssertNil(manager.onionSkinInkToSubtract(at: CanvasFixture.canvasSize),
                     "a hidden current layer subtracts nothing")
    }

    /// A `.value` layer is either an adjustment or one flat colour across the whole canvas. Either
    /// way it holds no cel, and a flat colour treated as ink would erase the entire ghost.
    func testAValueLayerSubtractsNothingFromTheGhost() {
        let manager = twoCelManager()
        manager.currentFrame = 8
        XCTAssertNotNil(manager.onionSkinInkToSubtract(at: CanvasFixture.canvasSize),
                        "premise: this layer does have ink to subtract while it is a drawing layer")
        manager.layers[0].kind = .value

        XCTAssertNil(manager.onionSkinInkToSubtract(at: CanvasFixture.canvasSize),
                     "a value layer has no drawing surface, so it cuts nothing out of the ghost")
    }

    /// What gets subtracted is the drawing the artist is *on*, not the drawing being skinned. Those
    /// are different cels of the same layer, which is exactly the confusion this file's header
    /// records a one-cel fixture hiding.
    func testWhatBehindSubtractsIsTheCurrentCelAndNotTheOneBeingSkinned() {
        let manager = twoCelManager()
        assertCelsAreDistinguishable(manager)
        manager.currentFrame = 8          // inside cel 1; cel 0 is what the ghost shows

        guard let ink = manager.onionSkinInkToSubtract(at: CanvasFixture.canvasSize) else {
            return XCTFail("the current cel has ink")
        }
        let current = PixelOps.rasterize(cel: manager.layers[0].cels[1], canvasSize: CanvasFixture.canvasSize)
        let skinned = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        XCTAssertEqual(ink.pngData(), current.pngData(), "must subtract the cel the playhead is in")
        XCTAssertNotEqual(ink.pngData(), skinned.pngData(), "must not subtract the cel being skinned")
    }

    /// **What the artist sees, not what the model holds.** The ghost, composited exactly as the view
    /// composites it, then multiplied by the clip exactly as `CALayer.mask` multiplies it — so this
    /// goes red if the clip stops being built, stops being applied, or is built inside out, while
    /// every stored value stays correct.
    ///
    /// The fixture's two strokes cross at (25, 25): the red one is the ghost, the blue one is what
    /// the artist has drawn on the current frame. Every premise is asserted before the conclusion
    /// is, because an assertion about a cut is worthless if there was nothing there to cut.
    func testTheGhostIsErasedWhereTheCurrentDrawingCoversItAndSurvivesElsewhere() {
        let manager = twoCelManager()
        assertCelsAreDistinguishable(manager)
        manager.currentFrame = 8
        let size = OnionSkinBudget.compositeSize(for: CanvasFixture.canvasSize,
                                                 resolution: manager.onionSkin.resolution)
        XCTAssertEqual(size, CanvasFixture.canvasSize,
                       "premise: on this fixture the skin is canvas-sized, so pixel coordinates are 1:1")

        let frames = OnionSkinSettingsSource().frames(for: manager)
        guard let ghost = OnionSkinFrame.composite(frames, size: size),
              let ink = manager.onionSkinInkToSubtract(at: size) else {
            return XCTFail("premise: one ghost frame and the current drawing's ink")
        }
        let ghostAlpha = alphaGrid(of: ghost)
        let inkAlpha = alphaGrid(of: ink)
        XCTAssertGreaterThan(alpha(ghostAlpha, 25, 25), 0, "premise: the ghost reaches the crossing")
        XCTAssertGreaterThan(alpha(ghostAlpha, 15, 15), 0, "premise: and reaches its own arm")
        XCTAssertEqual(alpha(inkAlpha, 25, 25), 255, "premise: the artist's ink covers the crossing")
        XCTAssertEqual(alpha(inkAlpha, 15, 15), 0, "premise: and not the ghost's own arm")

        guard let clip = OnionSkinClip.mask(layerMask: nil, subtracting: ink, size: size) else {
            return XCTFail("Behind must produce a clip")
        }
        // Core Animation's alpha multiply, in CoreGraphics: `.destinationIn` is dst x src alpha,
        // which is what `CALayer.mask` does to the layer it is installed on.
        let seen = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            ghost.draw(in: CGRect(origin: .zero, size: size))
            UIImage(cgImage: clip).draw(in: CGRect(origin: .zero, size: size),
                                        blendMode: .destinationIn, alpha: 1)
        }
        let seenAlpha = alphaGrid(of: seen)
        XCTAssertEqual(alpha(seenAlpha, 25, 25), 0,
                       "the ghost is gone where the artist's own drawing covers it — this is Behind")
        XCTAssertEqual(alpha(seenAlpha, 15, 15), alpha(ghostAlpha, 15, 15),
                       "and untouched everywhere else, at full strength")
    }
}
