import XCTest
import UIKit
import CoreGraphics

/// **A Move's lift must not re-walk the whole cel** (audit 2026-11-16 finding 6).
///
/// The hole a lasso lift needs is the cel with the lifted ink hidden. It differs from the picture
/// already on screen only where that ink was, so the lift declares that rectangle and the next render
/// repairs it over the memo. The first test fails on a build where the lift is `.everything`: the
/// repair counter stays at zero and the whole canvas is walked.
///
/// Both operands of every pixel comparison come from shipped code over the same display list: the
/// repaired canvas, and a cold canvas (no memo, so a full walk) with the same suppression.
final class VectorLiftRepairLogicTests: XCTestCase {

    private static let size = CGSize(width: 400, height: 400)

    private static func stroke(_ index: Int, size: CGFloat = 8) -> VectorStroke {
        // Spread over a 4x4 grid of cells so a handful of lifted strokes cover a small corner.
        let cx = 40 + CGFloat(index % 4) * 100, cy = 40 + CGFloat((index / 4) % 4) * 100
        let samples = StrokeSamples((0..<6).map { step -> VectorSample in
            let t = CGFloat(step) / 5
            return VectorSample(x: cx + t * 40, y: cy + sin(t * .pi) * 14, pressure: 0.5 + 0.5 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: Brush(name: "Lift", tip: .round, size: size,
                                         dab: BrushDabSettings(spacing: 0.3)),
                            color: CodableColor(red: Double(index % 3) / 3, green: 0.2, blue: 0.7, alpha: 1),
                            size: size, opacity: 1, samples: samples, composite: .paint,
                            seed: UInt64(index + 1))
    }

    private func canvas(strokes: Int = 16) -> VectorCanvas {
        let canvas = VectorCanvas.empty(size: Self.size)
        for index in 0..<strokes { canvas.addStroke(Self.stroke(index)) }
        return canvas
    }

    private func bytes(_ image: UIImage?) throws -> [UInt8] {
        try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(image?.cgImage)))
    }

    private func cold(_ elements: [VectorElement], suppressing ids: Set<UUID>) -> VectorCanvas {
        let fresh = VectorCanvas(size: Self.size, elements: elements)
        fresh.suppressedElementIDs = ids
        return fresh
    }

    func testSuppressingAMeasuredPieceRepairsItsFootprintOnlyAndMatchesAColdWalk() throws {
        let vector = canvas()
        _ = vector.render()                          // the picture on screen, footprints measured
        let lifted = Set(vector.elements.prefix(2).map(\.id))
        let repairsBefore = vector.regionRepairs

        vector.suppressedElementIDs = lifted
        let hole = vector.render()

        XCTAssertEqual(vector.regionRepairs, repairsBefore + 1,
                       "the lift's hole is a repair of the lifted footprint, not a whole-cel walk")
        let region = vector.lastRepairedRegion
        XCTAssertFalse(region.isNull)
        XCTAssertLessThan(region.width * region.height, Self.size.width * Self.size.height / 4)
        XCTAssertEqual(try bytes(hole), try bytes(cold(vector.elements, suppressing: lifted).render()))
    }

    func testACutLiftThroughInstallLiftMatchesAColdWalkOfTheSameSplit() throws {
        let vector = canvas()
        _ = vector.render()
        // A loop that cuts the first stroke in two.
        let loop = CGPath(rect: CGRect(x: 30, y: 20, width: 28, height: 50), transform: nil)
        let split = try XCTUnwrap(vector.splitForLassoMove(insideLocalPath: loop, membership: .cutting))
        XCTAssertFalse(split.insideIDs.isEmpty)
        let repairsBefore = vector.regionRepairs

        vector.installLift(elements: split.elements, suppressing: split.insideIDs)
        let hole = vector.render()

        XCTAssertEqual(vector.regionRepairs, repairsBefore + 1)
        XCTAssertEqual(try bytes(hole), try bytes(cold(split.elements, suppressing: split.insideIDs).render()))
    }

    func testAnUnmeasuredFootprintFallsBackToAFullWalkAndStaysCorrect() throws {
        let vector = canvas()
        let lifted = Set(vector.elements.prefix(2).map(\.id))
        // Never rendered: no footprint is measured, so the lift cannot be bounded.
        vector.suppressedElementIDs = lifted
        let repairsBefore = vector.regionRepairs
        let hole = vector.render()
        XCTAssertEqual(vector.regionRepairs, repairsBefore)
        XCTAssertEqual(try bytes(hole), try bytes(cold(vector.elements, suppressing: lifted).render()))
    }

    func testPuttingTheLiftedInkBackRestoresTheOriginalPictureExactly() throws {
        let vector = canvas()
        let original = try bytes(vector.render())
        vector.suppressedElementIDs = Set(vector.elements.prefix(3).map(\.id))
        _ = vector.render()
        vector.suppressedElementIDs = []
        XCTAssertEqual(try bytes(vector.render()), original)
    }

    func testAnEditWhileLiftedNeverRepairsFromTheStaleHoleBase() throws {
        let vector = canvas()
        _ = vector.render()
        let lifted = Set(vector.elements.prefix(2).map(\.id))
        vector.suppressedElementIDs = lifted
        vector.addStroke(Self.stroke(9, size: 12))        // an edit under suppression, before any render
        XCTAssertEqual(try bytes(vector.render()),
                       try bytes(cold(vector.elements, suppressing: lifted).render()))
    }
}
