import XCTest
import UIKit

/// SCHEDULER.md rules 1, 2 and 4 for the live vector eraser: the move path admits a display list and
/// returns; the window's picture is drawn on a background queue, latest wins, and only lift settles.
@MainActor
final class EraserOffMainLogicTests: XCTestCase {

    override func tearDown() {
        StrokeScratch.renderObserver = nil
        super.tearDown()
    }

    private func fixture() -> (StrokeScratch, VectorCanvas, VectorStroke) {
        let size = CGSize(width: 256, height: 256)
        let samples = StrokeSamples([VectorSample(x: 20, y: 128, pressure: 1),
                                     VectorSample(x: 230, y: 128, pressure: 1)], channels: .pressureOnly)
        let paint = VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1), size: 16, opacity: 1,
            samples: samples, seed: 3)
        let canvas = VectorCanvas(size: size, elements: [.stroke(paint)])
        let ink = CelContentPicture.Ink.ordinary(source: canvas.freezeDisplay(referenceIDs: []),
                                                 elements: canvas.elements, rewriting: [])
        let scratch = StrokeScratch(canvasSize: size, role: .replacing(.fullResolution),
            celContent: StrokeScratch.CelContent(backing: nil, ink: ink, placement: .identity))
        return (scratch, canvas, paint)
    }

    func testMovePathNeverRendersOnMainAndLatestWins() {
        let (scratch, canvas, _) = fixture()
        var onMain = 0, total = 0
        StrokeScratch.renderObserver = { main in total += 1; if main { onMain += 1 } }
        let landed = expectation(description: "a render landed")
        landed.assertForOverFulfill = false
        scratch.onRenderLanded = { landed.fulfill() }

        for i in 0..<12 {
            let damage = CGRect(x: 20 + CGFloat(i) * 6, y: 100, width: 30, height: 60)
            XCTAssertTrue(scratch.replaceVectorDisplay(elements: canvas.elements, rewriting: [], damage: damage, revision: i))
        }
        XCTAssertEqual(onMain, 0, "the eraser's move path rendered a cel on the main thread")
        XCTAssertTrue(scratch.hasPendingRender, "a move must return before its picture exists")
        wait(for: [landed], timeout: 10)
        XCTAssertEqual(onMain, 0, "the window's picture must be drawn off the main thread")
        XCTAssertLessThan(total, 12, "newer moves must supersede pending renders, not queue behind them")
        XCTAssertNotNil(scratch.renderedCelContent, "the finished picture is swapped in")
    }

    func testSettleAtLiftMakesTheShownPictureTheNewest() {
        let (scratch, canvas, _) = fixture()
        XCTAssertTrue(scratch.replaceVectorDisplay(elements: canvas.elements, rewriting: [],
                                                   damage: CGRect(x: 40, y: 100, width: 60, height: 60), revision: 1))
        scratch.settleCelContent()
        XCTAssertFalse(scratch.hasPendingRender, "lift must leave no step pending")
        XCTAssertNotNil(scratch.renderedCelContent)
    }

    func testHeldPictureIsReplacedInPlaceWhenTheNewestRenderLands() {
        var held = UnlandedInk()
        let footprint = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        held.hold(.init(id: 7, version: 3, windowRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                        replacing: footprint, contents: .image(UIImage())))
        let newer = UIImage()
        XCTAssertTrue(held.replace(id: 7, window: CGRect(x: 0, y: 0, width: 20, height: 20),
                                   footprint: footprint, image: newer))
        XCTAssertEqual(held.pictures.count, 1)
        XCTAssertEqual(held.pictures[0].version, 3, "the swap must keep the picture's version")
        XCTAssertEqual(held.pictures[0].windowRect.width, 20)
        held.retire(upTo: 3)
        XCTAssertFalse(held.replace(id: 7, window: .zero, footprint: footprint, image: newer),
                       "a retired picture must not come back")
    }
}
