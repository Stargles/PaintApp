import XCTest
import UIKit

/// **Can an artist reach Bake on an effect, blend or transformation layer, and get what the layer made
/// into the drawings beneath it?** — TODO (131), driven the way the artist drives it, from a fresh
/// document with no prior state.
///
/// `BakeLogicTests` and `BakeTransformLogicTests` own the rules: which colours, which pixels, where the
/// cels are cut, what is left. What they cannot say is whether a person can get there and see it, which
/// is what this file is for:
///
///  * the layer's menu offers **Bake** — and **not** Merge Down — on a layer that holds no pixels;
///  * the baked colours are **on the canvas**: two drawn strokes, each in its own colour, come out of the
///    bake in the colour a Multiply layer made of them, **with the layer gone and the paper still
///    white** — what is *drawn*, which a stored colour cannot show;
///  * **one press of Undo** brings the layer back and the paper grey again;
///  * a layer that cannot bake says so on the banner instead of doing nothing.
///
/// The picture is the same before and after for opaque ink — that is the point of a bake — so what proves
/// the colours moved into the strokes is the *paper*: the layer multiplied it grey while it was there, and
/// the bake leaves it white (Bake changes the drawings only).
final class LayerBakeUITests: PaintUITestCase {

    func testPastingAndBakingKeepsAnOrientationTaggedPictureDrawnTheSame() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let raw = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2), format: format).image { context in
            let colours: [UIColor] = [.red, .green, .blue, .blue, .red, .green]
            for row in 0..<2 {
                for column in 0..<3 {
                    context.cgContext.setFillColor(colours[row * 3 + column].cgColor)
                    context.cgContext.fill(CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1))
                }
            }
        }
        let rawCGImage = try XCTUnwrap(raw.cgImage)
        UIPasteboard.general.image = UIImage(cgImage: rawCGImage, scale: 2, orientation: .right)
        let roundTrip = try XCTUnwrap(UIPasteboard.general.image,
                                      "PREMISE: the runner can put a picture on the shared pasteboard")
        XCTAssertEqual(roundTrip.imageOrientation, .right,
                       "PREMISE: the runner pasteboard preserves the image's right orientation")
        XCTAssertEqual(roundTrip.scale, 2,
                       "PREMISE: the runner pasteboard preserves the scale-2 source")
        XCTAssertEqual(roundTrip.size, CGSize(width: 1, height: 1.5),
                       "PREMISE: the pasteboard exposes the oriented display size")

        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 96, height: 96),
                                       orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810),
                       "PREMISE: the public image route is drawn at the owner's landscape size")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let collapseTimeline = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapseTimeline.waitForExistence(timeout: 5),
                      "PREMISE: the public editor exposes the timeline collapse control")
        collapseTimeline.tap()
        XCTAssertTrue(collapseTimeline.waitForNonExistence(timeout: 5),
                      "PREMISE: the timeline finishes collapsing before image placement")
        let timeline = app.otherElements["timeline.panel"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertLessThan(timeline.frame.height, 70,
                          "PREMISE: the collapsed timeline leaves the lower paper exposed")

        app.buttons["toolbar.actionsButton"].tap()
        let paste = app.buttons["actions.pasteRow"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Actions exposes its public Paste row")
        paste.tap()
        // Pasteboard privacy is mediated by SpringBoard. The app's synchronous paste read can wait
        // for this first-use prompt, so answer it through SpringBoard before asking the app for AX.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowPaste = springboard.alerts.buttons["Allow Paste"]
        if allowPaste.waitForExistence(timeout: 5) { allowPaste.tap() }
        let actions = app.buttons["toolbar.actionsButton"]
        XCTAssertTrue(actions.isSelected, "PREMISE: Paste leaves the Actions dropdown open")
        let pasteRow = app.buttons["actions.pasteRow"]
        // The toolbar toggle closes Actions and commits any interactive pasted picture before Bake.
        actions.tap()
        XCTAssertTrue(pasteRow.waitForNonExistence(timeout: 5),
                      "The toolbar toggle dismisses the Actions dropdown")

        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5),
                      "PREMISE: the value layer was added above the pasted picture")
        app.buttons["toolbar.layersButton"].tap()
        setBlendMode(app, layerIndex: 1, to: "multiply")
        XCTAssertTrue(waitForSandwichState(app, "rest"), "PREMISE: the Multiply layer has settled")

        func sampleImage() throws -> [[Int]] {
            let paper = paperRect(in: canvas, canvasSize: CGSize(width: 96, height: 96))
            // The 3×2 source is `.right`: a 2×3 set of equal coloured cells centred in the paper,
            // fitted by insertImage to 80% of the canvas's long dimension.
            let points = [0.3667, 0.6333].flatMap { x in
                [0.2333, 0.5, 0.7667].map { y in onHost(paper, x, y) }
            }
            for (index, point) in points.enumerated() {
                assertAboveTheDock(app, canvas, dy: Double(point.dy),
                                   "oriented image cell probe \(index) must clear the timeline and any dock card")
            }
            let screen = try XCTUnwrap(ScreenshotPixels(canvas.screenshot().image))
            return points.map { point in
                let rgba = screen.pixel(normalizedX: Double(point.dx), normalizedY: Double(point.dy))
                return [Int(rgba.r), Int(rgba.g), Int(rgba.b), Int(rgba.a)]
            }
        }

        let before = try settled(timeout: 10) { try sampleImage() }
        XCTAssertEqual(before.count, 6)
        XCTAssertTrue(before.allSatisfy { $0[3] > 240 },
                      "PREMISE: all six oriented source cells are drawn opaquely: \(before)")
        XCTAssertGreaterThanOrEqual(Set(before.map { "\($0[0]),\($0[1]),\($0[2])" }).count, 3,
                                    "PREMISE: the asymmetric source's red, green and blue cells are exposed")
        attachScreenshot(XCUIScreen.main, "orientation-paste-before-bake")

        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.1"]
        row.tap()
        row.tap()
        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "The value layer offers its public Bake action")
        bake.tap()
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForNonExistence(timeout: 10),
                      "Bake removes the value layer after carrying its effect into the image")
        app.buttons["toolbar.layersButton"].tap()

        let after = try settled(timeout: 10) { try sampleImage() }
        XCTAssertEqual(after, before, "The pasted image's visible oriented cells survive Bake")
        XCTAssertGreaterThanOrEqual(Set(after.map { "\($0[0]),\($0[1]),\($0[2])" }).count, 3,
                                    "The baked red, green and blue cells remain drawn")
        attachScreenshot(XCUIScreen.main, "orientation-paste-after-bake")

        let tile = saveEditorAndReturnToGallery(app)
        tile.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 15), "The saved picture project reopens in the editor")
        let reopenedTimelineCollapse = app.buttons["timeline.collapseButton"]
        if reopenedTimelineCollapse.waitForExistence(timeout: 2) {
            reopenedTimelineCollapse.tap()
            XCTAssertTrue(reopenedTimelineCollapse.waitForNonExistence(timeout: 5),
                          "PREMISE: the reopened picture's timeline finishes collapsing")
        }
        let reopenedTimeline = app.otherElements["timeline.panel"]
        XCTAssertLessThan(reopenedTimeline.frame.height, 70,
                          "PREMISE: the reopened picture leaves its lower paper exposed")
        let reopened = try settled(timeout: 10) { try sampleImage() }
        XCTAssertEqual(reopened, after,
                       "The pasted picture's six drawn cells survive Bake, Gallery save and reopen")
        XCTAssertGreaterThanOrEqual(Set(reopened.map { "\($0[0]),\($0[1]),\($0[2])" }).count, 3,
                                    "All three asymmetric source colours remain visible after reopen")
        attachScreenshot(XCUIScreen.main, "orientation-paste-after-gallery-reopen")
    }

    func testBakingAMultiplyLayerColoursBothDrawingsBeneathItAndOneUndoBringsItBack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = safeOutsideCornerPoint(canvas)
        let second = CGVector(dx: start.dx, dy: start.dy + 0.2)
        let onFirst = CGVector(dx: start.dx + 0.06, dy: start.dy)
        let onSecond = CGVector(dx: second.dx + 0.06, dy: second.dy)
        let onPaper = CGVector(dx: start.dx + 0.06, dy: start.dy + 0.1)

        // Two drawings, each its own colour, each on its own vector layer.
        setBrushColor(app, hex: "FF0000")
        drawLine(on: canvas, from: start, to: CGVector(dx: start.dx + 0.12, dy: start.dy))
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))
        app.buttons["toolbar.layersButton"].tap()
        setBrushColor(app, hex: "0000FF")
        drawLine(on: canvas, from: second, to: CGVector(dx: second.dx + 0.12, dy: second.dy))

        // The layer that is going to be baked: a flat colour in Multiply (mid-grey, which is what a new
        // value layer is), on top of both.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 5), "Setup: the value layer is the third row")
        app.buttons["toolbar.layersButton"].tap()
        setBlendMode(app, layerIndex: 2, to: "multiply")
        XCTAssertTrue(waitUntil(canvas, onPaper, { !self.isWhitish($0) }),
                      "Setup: the Multiply layer greys the paper while it is there")

        // Bake it, from the layer's own menu.
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.2"]
        row.tap()
        row.tap()
        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "A layer that holds no pixels offers Bake")
        XCTAssertFalse(app.buttons["layerOptions.mergeDown"].exists, "…instead of Merge Down, which flattens drawings")
        attachScreenshot(app, "1-before-the-bake")
        bake.tap()

        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForNonExistence(timeout: 5),
                      "The value layer is gone — baked, not merged into one of them")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, true, "Both drawings stay vector layers")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.strokes, 1, "…each still holding its own stroke")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, true)
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 1)
        app.buttons["toolbar.layersButton"].tap()

        // What is DRAWN: red × grey and blue × grey, on paper the layer no longer greys.
        XCTAssertTrue(waitUntil(canvas, onPaper, isWhitish), "The paper stays white — Bake changes the drawings only")
        XCTAssertNotNil(waitForPixel(canvas, at: onFirst) { Int($0.r) > Int($0.g) + 40 && $0.r < 200 && $0.b < 80 },
                        "The red stroke carries its Multiply colour: \(probe(canvas, at: onFirst))")
        XCTAssertNotNil(waitForPixel(canvas, at: onSecond) { Int($0.b) > Int($0.r) + 40 && $0.b < 200 && $0.r < 80 },
                        "The blue stroke carries its Multiply colour: \(probe(canvas, at: onSecond))")
        attachScreenshot(app, "2-after-the-bake")

        // One press of Undo brings the layer back, greying the paper again.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitUntil(canvas, onPaper, { !self.isWhitish($0) }),
                      "Undo brings the Multiply layer back, and the paper under it grey")
        openLayerPanel(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 5), "…as the third row")
    }

    /// **An effect that works on pixels asks first, says what it will do, and changes nothing until the
    /// artist answers** — then the drawing beneath comes out a raster layer. Driven from a fresh
    /// document: draw, add a value layer, pick Gaussian Blur from its Blend Mode menu, Bake.
    func testABlurLayerAsksBeforeTurningTheDrawingIntoPixelsAndCancelChangesNothing() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = safeOutsideCornerPoint(canvas)
        drawLine(on: canvas, from: start, to: CGVector(dx: start.dx + 0.12, dy: start.dy))

        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Setup: the value layer is the second row")
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let blur = app.buttons["layerOptions.blendMode.gaussianblur"]
        XCTAssertTrue(blur.waitForExistence(timeout: 5), "The Blend Mode menu lists the effects")
        blur.tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, true, "Setup: the drawing is a vector layer")

        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "A layer that grades offers Bake")
        bake.tap()

        let ask = app.alerts.firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "A bake that turns a layer into pixels asks first")
        let sentence = ask.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(sentence.contains("Layer 1"), "It names the layer it will turn into pixels: \(sentence)")
        XCTAssertTrue(sentence.contains("raster layer"), "…and says what it becomes: \(sentence)")
        XCTAssertTrue(sentence.contains("undone"), "…and that it can be undone: \(sentence)")
        attachScreenshot(app, "3-the-prompt")
        ask.buttons["Cancel"].tap()
        XCTAssertTrue(ask.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].exists, "Cancel keeps the layer")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, true, "…and the drawing is still strokes")

        if !bake.exists { app.staticTexts["layerPanel.row.1"].tap() }   // the options menu may have closed behind the prompt
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "The layer's menu still offers Bake")
        bake.tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.buttons["Bake"].tap()

        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForNonExistence(timeout: 5), "The blur layer is gone")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, false,
                       "The drawing is painted into pixels: a raster layer now")
    }

    func testATransformationLayerOffersBakeAndAnAtRestOneSaysWhyItCannot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = safeOutsideCornerPoint(canvas)
        drawLine(on: canvas, from: start, to: CGVector(dx: start.dx + 0.12, dy: start.dy))

        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Setup: the transformation layer is the second row")
        row.tap()
        row.tap()
        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "A transformation layer offers Bake too")
        XCTAssertFalse(app.buttons["layerOptions.mergeDown"].exists)
        bake.tap()

        // It has not been moved, so there is nothing to carry into the drawing: said, not ignored.
        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "A refused bake raises a banner")
        XCTAssertEqual(notice.value as? String, "bakeRefused")
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].exists, "…and the layer is kept")
    }
}
