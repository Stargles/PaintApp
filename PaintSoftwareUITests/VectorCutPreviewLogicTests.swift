import XCTest
import CoreGraphics
import UIKit

/// The Mode 2 live display list and commit share the same lattice-preserving cut pieces.
final class VectorCutPreviewLogicTests: XCTestCase {
    private let size = CGSize(width: 256, height: 256)

    func testAccumulatedPreviewListMatchesCommittedCut() throws {
        let paint = VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1), size: 28, opacity: 1,
            samples: StrokeSamples((0..<25).map { index in
                VectorSample(x: 28 + CGFloat(index) * 8, y: 128, pressure: 1)
            }, channels: .pressureOnly), seed: 47)
        let source = VectorCanvas(size: size, elements: [.stroke(paint)])
        let originalVersion = source.version
        let originalElements = source.elements
        let gesture = StrokeSamples((0..<17).map { index in
            VectorSample(x: 128, y: 56 + CGFloat(index) * 9, pressure: 1)
        }, channels: .pressureOnly)
        let brush = Brush(name: "CutPreview", tip: .round, size: 12,
                          dab: BrushDabSettings(hardness: 1))

        var progress: [UUID: VectorCanvas.CutPreviewProgress] = [:]
        var previous: VectorSample?
        var finalPreview: VectorCanvas.EraserPreview?
        for sample in gesture {
            let increment: StrokeSamples = previous.map { [$0, sample] } ?? [sample]
            previous = sample
            if let update = source.cutPreviewElements(alongPath: increment, brush: brush, size: 12,
                                                       accumulating: &progress) {
                finalPreview = update
            }
        }

        XCTAssertEqual(source.version, originalVersion, "Previewing must not mutate or invalidate the source")
        XCTAssertEqual(source.elements.map(\.id), originalElements.map(\.id))
        let preview = try XCTUnwrap(finalPreview, "The drag crosses the editable stroke")
        XCTAssertTrue(preview.rewriting.contains(paint.id))
        XCTAssertLessThan(preview.damage.width * preview.damage.height, size.width * size.height,
                          "The changed geometry must have a bounded damage region")

        let committed = VectorCanvas(size: size, elements: originalElements)
        XCTAssertTrue(committed.erase(alongPath: gesture, brush: brush, size: 12,
                                      opacity: 1, mode: .cutPoints, seed: 0))
        let previewCanvas = VectorCanvas(size: size, elements: preview.elements)
        let expected = try XCTUnwrap(committed.render())
        let actual = try XCTUnwrap(previewCanvas.render())
        let parity = try XCTUnwrap(RasterVectorParity.report(raster: expected, vector: actual, size: size))
        XCTAssertTrue(parity.isExact, parity.diagnostic)
    }

    func testAccumulatedPreviewMatchesCommittedCutAcrossThicknessAndOpacity() throws {
        func line(y: CGFloat, x0: CGFloat, x1: CGFloat, count: Int = 17) -> StrokeSamples {
            StrokeSamples((0..<count).map { index in
                VectorSample(x: x0 + (x1 - x0) * CGFloat(index) / CGFloat(count - 1),
                             y: y, pressure: 1)
            }, channels: .pressureOnly)
        }
        func opaqueBrush(size: CGFloat) -> Brush {
            Brush(name: "CutPreview hard disc", tip: .round, size: size,
                  dab: BrushDabSettings(hardness: 1))
        }
        func stroke(_ samples: StrokeSamples, size: CGFloat, opacity: Double = 1,
                    brush: Brush = TestBrushes.hardRound) -> VectorStroke {
            VectorStroke(brush: brush,
                color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: size,
                opacity: opacity, samples: samples, seed: 91)
        }
        func drag(x: CGFloat, from y0: CGFloat, to y1: CGFloat, count: Int = 17) -> StrokeSamples {
            StrokeSamples((0..<count).map { index in
                VectorSample(x: x, y: y0 + (y1 - y0) * CGFloat(index) / CGFloat(count - 1), pressure: 1)
            }, channels: .pressureOnly)
        }

        let thickBrush = opaqueBrush(size: 40)
        let narrowNib = opaqueBrush(size: 8)
        let horizontal = stroke(line(y: 128, x0: 40, x1: 216), size: 40)
        let opaqueHorizontal = stroke(line(y: 128, x0: 40, x1: 216), size: 40, brush: thickBrush)
        let thickNib = drag(x: 128, from: 96, to: 160)
        let thin = stroke(line(y: 128, x0: 40, x1: 216), size: 8)
        let translucent = stroke(line(y: 128, x0: 40, x1: 216), size: 24, opacity: 0.4)
        let vertical = stroke(StrokeSamples((0..<17).map { index in
            VectorSample(x: 128, y: 40 + CGFloat(index) * 11, pressure: 1)
        }, channels: .pressureOnly), size: 20)
        let crossingHorizontal = stroke(line(y: 128, x0: 40, x1: 216), size: 20)

        let cases: [(name: String, strokes: [VectorStroke], gesture: StrokeSamples,
                     eraserBrush: Brush, nibSize: CGFloat, minRemovedPixels: Int)] = [
            ("thick line / narrow nib", [opaqueHorizontal], thickNib, narrowNib, 8, 0),
            ("wide nib / thick line", [horizontal], drag(x: 128, from: 80, to: 176),
             TestBrushes.hardRound, 72, 500),
            ("thin line", [thin], thickNib, TestBrushes.hardRound, 24, 100),
            ("semi-transparent line", [translucent], thickNib, TestBrushes.hardRound, 12, 1),
            ("uncut crossing ink", [crossingHorizontal, vertical],
             StrokeSamples((0..<12).map { index in
                 VectorSample(x: 60 + CGFloat(index) * 3, y: 128, pressure: 1)
             }, channels: .pressureOnly), TestBrushes.hardRound, 30, 100),
        ]

        for scenario in cases {
            let originalElements = scenario.strokes.map(VectorElement.stroke)
            let source = VectorCanvas(size: size, elements: originalElements)
            let original = try XCTUnwrap(source.render())
            var progress: [UUID: VectorCanvas.CutPreviewProgress] = [:]
            var previous: VectorSample?
            var finalPreview: VectorCanvas.EraserPreview?
            for sample in scenario.gesture {
                let increment: StrokeSamples = previous.map { [$0, sample] } ?? [sample]
                previous = sample
                if let update = source.cutPreviewElements(alongPath: increment, brush: scenario.eraserBrush,
                    size: scenario.nibSize, accumulating: &progress) {
                    finalPreview = update
                }
            }
            let preview = try XCTUnwrap(finalPreview, "PREMISE: \(scenario.name) changes cut geometry")
            let committed = VectorCanvas(size: size, elements: originalElements)
            XCTAssertTrue(committed.erase(alongPath: scenario.gesture, brush: scenario.eraserBrush,
                size: scenario.nibSize, mode: .cutPoints, seed: 0),
                "PREMISE: \(scenario.name) commits a cut")
            let expected = try XCTUnwrap(committed.render())
            let actual = try XCTUnwrap(VectorCanvas(size: size, elements: preview.elements).render())
            let parity = try XCTUnwrap(RasterVectorParity.report(raster: expected, vector: actual, size: size))
            XCTAssertTrue(parity.isExact, "\(scenario.name): \(parity.diagnostic)")

            let changed = try XCTUnwrap(RasterVectorParity.report(raster: original, vector: expected, size: size))
                .differingPixelCount
            XCTAssertGreaterThanOrEqual(changed, scenario.minRemovedPixels,
                                        "PREMISE: \(scenario.name) has the expected visible effect")
            if scenario.minRemovedPixels == 0 {
                XCTAssertEqual(changed, 0,
                    "A 40pt line cut by an 8pt nib keeps its pixels because the pieces' caps meet")
            }
            if scenario.name == "uncut crossing ink" {
                XCTAssertTrue(preview.elements.contains(where: { $0.id == vertical.id }),
                              "The uncut crossing stroke remains in the preview's ordered list")
                XCTAssertFalse(preview.rewriting.contains(vertical.id),
                               "The eraser must not rewrite the crossing stroke it did not reach")
            }
        }
    }
}
