import XCTest
import UIKit

/// **What a per-tick live composite of the engaged sandwich would cost** — the measurement STREAM.md
/// §5.3's open question turns on, taken so the decision rests on a number rather than on
/// PERFORMANCE.md's neighbouring ones.
///
/// The question: when the stream layer sits in an engaged sandwich at rest (a blend mode, a mask,
/// an effect, a container pose), the on-screen picture is the baked composite keyed on
/// `committedVersion`, which a live frame never moves — so the live picture goes stale. The cheapest
/// way to un-stale it would be to re-composite the current frame in memory on every tick with a
/// new frame. That costs, per tick: the stream cel's own re-flatten (a canvas-sized walk drawing a
/// 1080p picture, which the `.region` repair bounds to the element's footprint), and one full
/// composite of every layer at canvas size. This bench prices both halves at 2048², three layers,
/// with the stream layer on Multiply, on the CoreGraphics reference backend and on Metal when a
/// device is present.
///
/// **A simulator figure, labelled as one.** On the device the composite is Metal and the walk is
/// an A13; PERFORMANCE.md's device figures for a six-layer sandwich rebuild are 54.8 ms warm. The
/// verdict is about the order of magnitude against the ~4 ms a 30 Hz tick could carry, not about
/// the last millisecond.
///
/// Not a `*LogicTests` file: the fast tier's selector leaves it out, so it cannot flake a gate. One
/// loose assertion an order of magnitude clear of the number, so a busy machine cannot turn a
/// measurement into a red. Run it by name:
///
/// ```
/// SIMLOCK_SLOTS=1 tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj \
///   -scheme PaintSoftware -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/StreamSandwichBench \
///   -parallel-testing-enabled NO -derivedDataPath build/DerivedData
/// ```
@MainActor
final class StreamSandwichBench: XCTestCase {

    private static let canvasSize = CGSize(width: 2048, height: 2048)
    private static let frameSize = CGSize(width: 1920, height: 1080)

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        super.tearDown()
    }

    private func frame(_ hue: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: Self.frameSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: Self.frameSize))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 100, y: 100, width: 600, height: 300))
        }
    }

    /// Three layers at 2048²: ink below, the stream on Multiply, ink above.
    private func document() -> (manager: CanvasManager, vector: VectorCanvas, streamID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = Self.canvasSize
        manager.addLayer()
        manager.currentFrame = 0
        let bottom = manager.layers[0].cels[0].raster
        bottom.beginStroke()
        bottom.stampCircle(at: CGPoint(x: 700, y: 900), radius: 300, color: .red, alpha: 1, hardness: 0.8)
        bottom.endStroke()
        let status = StreamStatus(source: StreamStatus.Source(kind: "monitor", name: "Screen"),
                                  width: Int(Self.frameSize.width), height: Int(Self.frameSize.height),
                                  fps: 30, streaming: true)
        let element = manager.insertStream(host: "laptop", port: 47301, status: status)!
        manager.commitVectorFloatIfNeeded()
        let streamLayer = manager.currentLayerIndex
        manager.layers[streamLayer].blendMode = .multiply
        let vector = manager.layers[streamLayer].cels[0].vector!
        manager.addLayer()
        let top = manager.layers[manager.currentLayerIndex].cels[0].raster
        top.beginStroke()
        top.stampCircle(at: CGPoint(x: 1400, y: 1100), radius: 200, color: .blue, alpha: 0.7, hardness: 0.5)
        top.endStroke()
        return (manager, vector, element.id)
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }

    /// Per tick, for a correct live composite: a new frame on the element with its committed
    /// version moved (so every memo keyed on it re-flattens, which is what a correct path would
    /// have to do), the request built, the composite run. Printed as the three terms.
    func testWhatOneLiveCompositeTickCostsAtTheOwnersCanvas() throws {
        let (manager, vector, streamID) = document()
        XCTAssertTrue(manager.renderTree(atFrame: 0).needsCompositorOnCanvas, "Setup: the sandwich engages")
        let frames = (0..<6).map { frame(CGFloat($0) / 6) }

        for backend in [CompositorBackend.coreGraphics, .metal] {
            Compositor.backend = backend
            if backend == .metal, CompositorMetalEngine.shared == nil { continue }
            var walk: [Double] = [], build: [Double] = [], composite: [Double] = []
            for (index, image) in frames.enumerated() {
                autoreleasepool {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    // A correct per-tick path cannot leave `committedVersion` still — every memo the
                    // composite reads is keyed on it — so the frame is set through the edit seam here.
                    vector.setStreamFrame(id: streamID, image: image, index: index + 1)
                    vector.bumpVersion()
                    _ = vector.render()
                    let t1 = CFAbsoluteTimeGetCurrent()
                    guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
                        return XCTFail("request")
                    }
                    let t2 = CFAbsoluteTimeGetCurrent()
                    let out = Compositor.composite(request)
                    let t3 = CFAbsoluteTimeGetCurrent()
                    XCTAssertNotNil(out)
                    if index > 0 {   // the first is the cold one
                        walk.append(t1 - t0); build.append(t2 - t1); composite.append(t3 - t2)
                    }
                }
            }
            func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
            let total = median(walk) + median(build) + median(composite)
            print("""
                [StreamSandwichBench] SIMULATOR \(backend) 3 layers at 2048x2048, 1920x1080 frame, stream on Multiply, per tick (median of 5 warm): \
                cel re-walk \(ms(median(walk))), request (flattens) \(ms(median(build))), \
                composite \(ms(median(composite))), total \(ms(total))
                """)
            // Three orders of magnitude clear of any plausible number, so a loaded machine cannot
            // red this; the figure is the print.
            XCTAssertLessThan(total, 30, "One live-composite tick at 2048² taking half a minute is a structural regression")
        }
    }
}
