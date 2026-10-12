import XCTest
import UIKit

/// **A filled selection recoloured from the Select panel never shows the base through the edit while
/// the finger is on the picker** — the owner's report of 2026-10-12, on the iPad 9 in landscape:
/// *"Made a selection, clicked on fill, then clicked on edit and tried to change the color inside the
/// selection. Lots of flickering."*
///
/// The edit is held off the document (TODO (173)): the cel's base is punched out under a window, and
/// the window is drawn into one of two surfaces the render server shows. Each draw is minted in the
/// main-thread turn the last one landed in — before that turn's transaction has taken the swap to the
/// server — so the surface being cleared and redrawn could still be the one on screen, and for as long
/// as the main thread kept that turn from committing the paper showed through the punched hole, where
/// the fill had been. On the iPad 9 a window over a large fill takes hundreds of milliseconds to draw
/// and the colour picker keeps the main thread busy for up to 182 ms a turn (the owner's recording), so
/// the picture alternated with the hole on every tick. Here both are a few milliseconds, and the two
/// seams give the simulator the device's: `-uiTestSlowWindowDrawMillis` (the draw) and
/// `-uiTestBusyLandingTurnMillis` (the turn the swap lands in).
///
/// Cold start, the artist's way, on an iPad (9th generation) simulator turned to landscape: a red brush,
/// Select → Rectangle, a loop on the right half of the paper, Fill; Edit → the colour swatch → the
/// picker's hue ring dragged for eight seconds while another thread reads the filled region. Every
/// reading taken with the finger down must be the fill in *some* colour — never the paper.
final class SelectionFillRecolourUITests: PaintUITestCase {

    /// The screen read at fixed points, repeatedly, on another thread — `MidGestureSampler`'s job, with
    /// the screenshot drawn through its own orientation first so a landscape read lands where the
    /// points say (the shared sampler reads the portrait pixel buffer as it comes).
    private final class LandscapeSampler {
        private let points: [CGPoint]
        private var stopped = false
        private var samples: [(finished: CFAbsoluteTime, pixels: [RGBA?])] = []
        private let lock = NSLock()
        private let group = DispatchGroup()

        init(points: [CGPoint]) { self.points = points }

        func start() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                while true {
                    lock.lock(); let done = stopped; lock.unlock()
                    if done { return }
                    let read = Self.pixels(in: XCUIScreen.main.screenshot().image, at: points)
                    let finished = CFAbsoluteTimeGetCurrent()
                    lock.lock(); samples.append((finished, read)); lock.unlock()
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
        }

        func stop() -> [(finished: CFAbsoluteTime, pixels: [RGBA?])] {
            lock.lock(); stopped = true; lock.unlock()
            group.wait()
            return samples
        }

        private static func pixels(in image: UIImage, at points: [CGPoint]) -> [RGBA?] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
            guard let cg = upright.cgImage else { return points.map { _ in nil } }
            let width = cg.width, height = cg.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return points.map { _ in nil } }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let sx = CGFloat(width) / image.size.width, sy = CGFloat(height) / image.size.height
            return points.map { point in
                let x = Int(point.x * sx), y = Int(point.y * sy)
                guard x >= 0, y >= 0, x < width, y < height else { return nil }
                let offset = (y * width + x) * 4
                return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
            }
        }
    }

    func testRecolouringAFilledSelectionNeverShowsThePaperThroughTheEdit() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowWindowDrawMillis", "300", "-uiTestBusyLandingTurnMillis", "150"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height,
                             "PREMISE: the iPad is in landscape, as the owner holds it")

        // 1. Red, Select → Rectangle, a loop on the right half of the paper, Fill.
        setBrushColor(app, hex: "FF0000")
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        let visible = visiblePaperRect(app, in: canvas)
        dragOnCanvas(app, from: onHost(visible, 0.52, 0.12), to: onHost(visible, 0.94, 0.9))
        let fill = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "the loop raised the Select panel's Fill")
        fill.tap()

        let host = canvas.frame
        func screen(_ v: CGVector) -> CGPoint {
            CGPoint(x: host.minX + host.width * v.dx, y: host.minY + host.height * v.dy)
        }
        let probes = [(0.62, 0.3), (0.72, 0.45), (0.82, 0.3), (0.66, 0.65), (0.84, 0.7), (0.75, 0.55)]
            .map { screen(onHost(visible, $0.0, $0.1)) }
        let premise = LandscapeSampler(points: probes)
        premise.start()
        Thread.sleep(forTimeInterval: 1.5)
        let filled = premise.stop().last?.pixels ?? []
        XCTAssertTrue(filled.count == probes.count && filled.allSatisfy(isRed),
                      "PREMISE: the selection is filled red where it is read (\(filled))")

        // 2. Edit → the colour swatch → the picker, which must leave the probes in view.
        openSelectionEditBand(app)
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the loop raised the colour swatch")
        swatch.tap()
        let picker = app.descendants(matching: .any)["canvasPresentation.selectionColour"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the swatch opens the picker")
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "the picker's hue ring")
        let clear = probes.filter { !picker.frame.insetBy(dx: -8, dy: -8).contains($0) }
        XCTAssertGreaterThanOrEqual(clear.count, 3,
                                    "PREMISE: the fill is read clear of the picker (picker \(picker.frame))")
        attachScreenshot(app, "1-picker-open-over-the-filled-selection")

        // 3. The ring dragged for eight seconds, slowly, while the filled region is read.
        let f = ring.frame
        let centre = CGPoint(x: f.midX, y: f.midY)
        let radius = min(f.width, f.height) * 0.42
        func point(_ angle: Double) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: centre.x - f.minX + radius * cos(angle), dy: centre.y - f.minY + radius * sin(angle)))
        }
        let sampler = LandscapeSampler(points: clear)
        sampler.start()
        let start = Date()
        var angle = 0.6
        while Date().timeIntervalSince(start) < 8 {
            point(angle).press(forDuration: 0.05, thenDragTo: point(angle + 0.9), withVelocity: .slow,
                               thenHoldForDuration: 0.05)
            angle += 0.9
        }
        let returned = CFAbsoluteTimeGetCurrent()
        let taken = sampler.stop().filter { $0.finished < returned - 0.3 }
        attachScreenshot(app, "2-after-the-drag")

        let note = XCTAttachment(string: taken.map { sample in
            sample.pixels.map { $0.map { "\($0.r),\($0.g),\($0.b)" } ?? "-" }.joined(separator: " ")
        }.joined(separator: "\n"))
        note.name = "the filled region, read while the finger was on the ring"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThanOrEqual(taken.count, 10, "the screen was read \(taken.count) times while the finger was down")
        XCTAssertTrue(taken.contains { $0.pixels.contains { !isRed($0) && !isWhitish($0) } },
                      "PREMISE: the recolour reached the screen while the finger was down")
        let flashes = taken.filter { $0.pixels.contains(where: isWhitish) }
        XCTAssertTrue(flashes.isEmpty,
                      "the paper showed through the fill \(flashes.count) times in \(taken.count) reads while the "
                      + "colour was being dragged — the edit's window was redrawn in a surface still on screen")
    }
}
