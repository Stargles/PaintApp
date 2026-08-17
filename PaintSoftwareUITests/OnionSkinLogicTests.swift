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
        Brush(name: "test", shape: .hardRound, size: size, dynamics: .fixed)
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

    /// The resolution rule, pinned against a stated cap rather than the shipped constant, so moving
    /// the constant is a product decision and not a test failure.
    func testTheCompositeIsCappedOnItsLongestEdgeAndNeverScaledUp() {
        let cap: CGFloat = 1024

        XCTAssertEqual(OnionSkinBudget.compositeSize(for: CGSize(width: 800, height: 600), maxEdge: cap),
                       CGSize(width: 800, height: 600),
                       "inert below the cap — and never scaled *up*, which would be pure cost")

        let square = OnionSkinBudget.compositeSize(for: CGSize(width: 4096, height: 4096), maxEdge: cap)
        XCTAssertEqual(square, CGSize(width: 1024, height: 1024))

        // Aspect is preserved and it is the *longest* edge that is capped, so a wide canvas is not
        // squared off and does not sneak past the cap on its long side.
        let wide = OnionSkinBudget.compositeSize(for: CGSize(width: 4096, height: 2048), maxEdge: cap)
        XCTAssertEqual(wide, CGSize(width: 1024, height: 512))
        let tall = OnionSkinBudget.compositeSize(for: CGSize(width: 2048, height: 4096), maxEdge: cap)
        XCTAssertEqual(tall, CGSize(width: 512, height: 1024))
    }

    /// **The whole memory claim, as arithmetic rather than as prose.** Everything the onion skin
    /// holds is one composite plus a full source cache, all at the cap — so the ceiling is a fact
    /// about two constants and cannot drift with the canvas, the skin count, or the device.
    func testTheResidentCeilingIsOneCompositePlusAFullSourceCache() {
        let one = Int(OnionSkinBudget.maxCompositeEdge * OnionSkinBudget.maxCompositeEdge) * 4
        XCTAssertEqual(OnionSkinBudget.residentCeilingBytes,
                       one * (OnionSkinBudget.sourceCacheLimit + 1))
        XCTAssertGreaterThan(OnionSkinBudget.sourceCacheLimit, OnionSkinSettings.maxSkinsPerSide * 2,
                             "the cache must be strictly larger than the window it caches, or every "
                             + "playhead step evicts the cel it is about to need again")

        // A number worth failing on rather than merely reporting: even at its ceiling — ten skins, the
        // most the artist can ask for — a ghost may not cost more than a third of the compositor's own
        // budget on the owner's 3 GB iPad. The *default* is two sources and a composite, about a
        // quarter of that ceiling.
        let compositorBudget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024)
        XCTAssertLessThan(OnionSkinBudget.residentCeilingBytes, compositorBudget / 3)
    }

    /// A reduced source is built once per cel version and then handed back by identity — the property
    /// the rebuild cost depends on, asserted rather than assumed. `===`, not `==`: an equal image
    /// rebuilt every call would pass a content comparison and would have fixed nothing.
    func testAReducedSourceIsBuiltOncePerCelVersionAndSkippedEntirelyWhenNoReductionIsNeeded() {
        let canvas = CGSize(width: 2048, height: 2048)
        let small = OnionSkinBudget.compositeSize(for: canvas)
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
                                                     at: OnionSkinBudget.compositeSize(for: tiny))
        XCTAssertTrue(passthrough === PixelOps.rasterize(cel: smallCel, canvasSize: tiny))
        XCTAssertEqual(OnionSkinRasterCache.residentBytes, 0,
                       "a document under the cap must not fill an onion cache it has no use for")
    }

    func testTheSourceCacheEvictsRatherThanGrowing() {
        let canvas = CGSize(width: 2048, height: 2048)
        let small = OnionSkinBudget.compositeSize(for: canvas)
        OnionSkinRasterCache.removeAll()
        for index in 0..<(OnionSkinBudget.sourceCacheLimit + 4) {
            var cel = Cel(id: UUID(), startFrame: index, frameCount: 1, raster: .empty(size: canvas))
            cel.bakedImage = CanvasFixture.solidImage(.red,
                                                      rect: CGRect(x: index, y: 0, width: 40, height: 40),
                                                      size: canvas)
            _ = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: small)
        }
        let perEntry = Int(small.width.rounded()) * Int(small.height.rounded()) * 4
        XCTAssertLessThanOrEqual(OnionSkinRasterCache.residentBytes,
                                 perEntry * OnionSkinBudget.sourceCacheLimit,
                                 "more cels than the limit must evict, not accumulate")
        OnionSkinRasterCache.removeAll()
        XCTAssertEqual(OnionSkinRasterCache.residentBytes, 0)
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
}
