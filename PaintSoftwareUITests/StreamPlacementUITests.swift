import XCTest

/// Cold-start reachability and actual pixels, including the artist's rotoscoping gesture.
final class StreamPlacementUITests: StreamUITestCase {
    private func selectLayer(_ app: XCUIApplication, _ index: Int) {
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.\(index)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        closeLayerRail(app)
    }

    func testSwitchPlacesTheLiveScreenUnderUpperMultiplyAndFreezeKeepsThatPlacement() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertTrue(placement.waitForExistence(timeout: 5))
        XCTAssertEqual(placement.value as? String, "onTop")

        addVectorLayer(app)
        for dy in [0.49, 0.5, 0.51] {
            drawLine(on: canvas, from: CGVector(dx: 0.25, dy: dy), to: CGVector(dx: 0.75, dy: dy))
        }
        setBlendMode(app, layerIndex: 2, to: "multiply")
        closeLayerRail(app)
        selectLayer(app, 1)
        waitForPicture(.red, on: canvas, "today's fallback is above the upper blend")
        placement.tap()
        XCTAssertEqual(placement.value as? String, "inPlace")
        waitForPicture(.black, on: canvas, "the upper Multiply now covers the screen")
        laptop.show(.green)
        waitForPicture(.black, on: canvas)
        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        laptop.show(.blue)
        waitForPicture(.black, on: canvas)
        XCTAssertFalse(app.staticTexts["streamBar.pictureNote"].exists)
        attachScreenshot(XCUIScreen.main, "In Place under Multiply")
        placement.tap()
        waitForPicture(.green, on: canvas, "On Top still shows the frozen computer frame")
        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.blue, on: canvas)
    }

    func testGuideAboveTheStreamStaysAboveTheScratchWhileThePenIsHeld() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        app.buttons["streamBar.placementButton"].tap()
        addDrawingGuide(app, landingAt: 2)
        selectLayer(app, 1)
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.1)
        let probe = paperPatch(canvas, paper, x: 0.42...0.58, y: 0.49...0.51)
        let before = readScreenNow(probe)
        let crossingIndex = try XCTUnwrap(before.indices.first { index in
            isGuideBlue(before[index]) && before.indices.contains { neighbour in
                abs(probe[neighbour].y - probe[index].y) < 1
                    && before[neighbour].map { Colour.red.matches($0) } == true
            }
        }, "PREMISE: a vertical Guide crosses a red row where held ink can be seen beside it")
        let crossing = probe[crossingIndex]
        let inkIndex = try XCTUnwrap(before.indices.first { index in
            abs(probe[index].y - crossing.y) < 1 && before[index].map { Colour.red.matches($0) } == true
        })
        let inkPoint = probe[inkIndex]
        let relativeY = (crossing.y - canvas.frame.minY) / canvas.frame.height
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: relativeY))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: relativeY))
        let held = samplesDuring([crossing, inkPoint], "Guide over stream-layer scratch") {
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4)
        }
        for sample in held.suffix(3) {
            XCTAssertTrue(isGuideBlue(sample.pixels.first ?? nil),
                "the Guide is over the black scratch before lift: \(sample.pixels)")
            XCTAssertTrue(sample.pixels[1].map { Colour.black.matches($0) } == true,
                "held ink is visible beside the crossing: \(sample.pixels)")
        }
        XCTAssertTrue(isGuideBlue(readScreenNow([crossing]).first ?? nil), "the committed stroke keeps the same order")
        XCTAssertTrue(readScreenNow([inkPoint]).first.flatMap { $0 }.map { Colour.black.matches($0) } == true,
            "the landed composite retains the ink beside the Guide")
        attachScreenshot(XCUIScreen.main, "Guide remains above stream-layer ink")
    }

    func testAnOverlappingOnTopStreamRemainsOverTheInPlaceWindow() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        app.buttons["streamBar.placementButton"].tap()
        laptop.show(.green)
        waitForPicture(.green, on: canvas)
        connectStream(app)
        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        laptop.show(.red)
        addDrawingGuide(app, landingAt: 3)
        selectLayer(app, 1)
        XCTAssertEqual(app.buttons["streamBar.placementButton"].value as? String, "inPlace")
        waitForPicture(.green, on: canvas, "the frozen On Top reference remains over the red In Place composite")
        selectLayer(app, 2)
        XCTAssertEqual(app.buttons["streamBar.placementButton"].value as? String, "onTop")
        waitForBarState(app, "frozen")
        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.red, on: canvas)
        attachScreenshot(XCUIScreen.main, "Overlapping streams with different placement choices")
    }

    func testPlacementSurvivesASaveAndColdRelaunch() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.green)
        waitForPicture(.green, on: canvas)
        app.buttons["streamBar.placementButton"].tap()
        app.buttons["streamBar.freezeButton"].tap()
        app.buttons["toolbar.galleryButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertTrue(placement.waitForExistence(timeout: 10))
        XCTAssertEqual(placement.value as? String, "inPlace")
        waitForBarState(app, "frozen")
        waitForPicture(.green, on: app.otherElements["canvas.host"], "the saved picture draws before any new computer frame")
    }
}
