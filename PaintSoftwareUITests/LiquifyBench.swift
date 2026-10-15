import XCTest
import CoreGraphics
import UIKit
import CryptoKit

/// Explicit renderer sizing benchmark; excluded from the filename-selected fast tier.
/// Run in Release with TEST_RUNNER_PAINTAPP_BENCH=1 and the class selector.
final class LiquifyBench: XCTestCase {
    func testRealisticRasterWindowHasMeasuredBoundedCostAwayFromTheOrigin() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] == "1", "explicit renderer sizing run")
        for (name, brush) in [("hard", TestBrushes.hardRound), ("pattern", BrushLibrary.streaky)] {
            let definition = LiquifyDeformation(brush: brush, size: 100, power: 1, mode: .push, seed: 42,
                samples: StrokeSamples(points: [CGPoint(x: 3000, y: 2000), CGPoint(x: 3500, y: 2000)]))
            let field = LiquifyField(definition)
            let window = field.replacementBounds.integral
            let width = Int(window.width), height = Int(window.height)
            var source = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                if y > 20 && y < height - 20 {
                    source[i] = x / 8 % 2 == 0 ? 220 : 25
                    source[i + 1] = 100; source[i + 3] = 255
                }
            } }
            func render() -> (bytes: [UInt8]?, evaluations: Int, unsolved: Int) {
                var evaluations = 0, unsolved = 0
                let bytes = ImageWarp.warp(source: source, sourceWidth: width, sourceHeight: height,
                    destinationWidth: width, destinationHeight: height) { point in
                    let shown = CGPoint(x: point.x + window.minX, y: point.y + window.minY)
                    let inverse = field.inverseSolution(shown)
                    evaluations += inverse.evaluations
                    if !inverse.converged { unsolved += 1 }
                    return CGPoint(x: inverse.point.x - window.minX, y: inverse.point.y - window.minY)
                }
                return (bytes, evaluations, unsolved)
            }
            let cold = render()
            let start = Date()
            let warm = render()
            let duration = Date().timeIntervalSince(start)
            print("LIQUIFY REAL WINDOW \(name) pixels=\(width * height) dabs=\(field.steps.count) fieldBytes=\(field.retainedByteCount) pixelBytes=\(source.count * 2) evaluations=\(warm.evaluations) unsolved=\(warm.unsolved) warmSeconds=\(duration)")
            // Native 17db4c3 used 54,319,422 / 290,752,890 evaluations for these exact windows.
            let originalEvaluations = name == "hard" ? 54_319_422 : 290_752_890
            let retainedWork = name == "hard" ? 95 : 80
            XCTAssertLessThan(warm.evaluations, originalEvaluations * retainedWork / 100,
                              "the source solver must retain its measured work reduction")
            for (label, pixels) in [("source", source), ("warped", try XCTUnwrap(warm.bytes))] {
                let image = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: pixels, width: width, height: height))
                let attachment = XCTAttachment(image: UIImage(cgImage: image))
                attachment.name = "liquify-window-\(name)-\(label)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            XCTAssertEqual(warm.unsolved, 0, "every production source solve on a real4096 canvas must converge")
            XCTAssertEqual(warm.bytes, cold.bytes, "resampling the same original ink is deterministic")
            XCTAssertLessThan(source.count * 2 + field.retainedByteCount, 2 * 1024 * 1024, "the active brush window must not allocate a full-canvas source or displacement grid")
        }
    }

    func testLargeCoordinateInverseDiagnosticsKeepEverySparsePixelCoherent() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] == "1", "explicit numerical diagnostic")
        let brush = BrushLibrary.streaky
        let global = LiquifyField(LiquifyDeformation(brush: brush, size: 100, power: 1, mode: .push, seed: 42, samples: StrokeSamples(points: [CGPoint(x: 3000, y: 2000), CGPoint(x: 3500, y: 2000)])))
        let tile = max(BrushTextureSettings.minimumTileSize, brush.texture?.tileSize.rounded() ?? 1)
        let shift = CGPoint(x: floor(3000 / tile) * tile, y: floor(2000 / tile) * tile)
        let local = LiquifyField(LiquifyDeformation(brush: brush, size: 100, power: 1, mode: .push, seed: 42, samples: StrokeSamples(points: [CGPoint(x: 3000 - shift.x, y: 2000 - shift.y), CGPoint(x: 3500 - shift.x, y: 2000 - shift.y)])))
        let window = global.replacementBounds.integral
        var globalReasons: [String: Int] = [:], localReasons: [String: Int] = [:], examples = 0
        for y in stride(from: Int(window.minY), to: Int(window.maxY), by: 8) {
            for x in stride(from: Int(window.minX), to: Int(window.maxX), by: 16) {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let a = global.inverseResult(point)
                let b = local.inverseResult(CGPoint(x: point.x - shift.x, y: point.y - shift.y))
                globalReasons[a.failure?.rawValue ?? "solved", default: 0] += 1
                localReasons[b.failure?.rawValue ?? "solved", default: 0] += 1
                if !a.converged && examples < 8 {
                    print("LIQUIFY LARGE FAILURE point=\(point) reason=\(a.failure!) residual=\(a.residual) source=\(a.point) ulp=\(a.point.x.ulp) localReason=\(b.failure?.rawValue ?? "solved") localResidual=\(b.residual) globalEvaluations=\(a.evaluations) localEvaluations=\(b.evaluations)")
                    examples += 1
                }
            }
        }
        print("LIQUIFY LARGE BREAKDOWN global=\(globalReasons) local=\(localReasons) shift=\(shift)")
        XCTAssertEqual(globalReasons["iterationLimit", default: 0] + globalReasons["nonFinite", default: 0] + globalReasons["selection", default: 0], 0,
                       "source convergence is independent of the ill-conditioned forward residual")
    }

    func testPushInverseMatchesNativePixelsAcrossDirectionsGrainAndSelection() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] == "1", "explicit native pixel and source-solver regression")
        var grained = BrushLibrary.streaky
        grained.texture = BrushTextureSettings(mask: .builtIn(.paperGrain), tileSize: 37, depth: 0.8)
        let selection = CGPath(rect: CGRect(x: 2981, y: 1978, width: 38, height: 44), transform: nil)
        let fixtures: [(String, Brush, CGPoint, CGPath?, LiquifyMode)] = [
            ("hard-right", TestBrushes.hardRound, CGPoint(x: 32, y: 0), nil, .push),
            ("hard-up", TestBrushes.hardRound, CGPoint(x: 0, y: -32), nil, .push),
            ("hard-negative-diagonal", TestBrushes.hardRound, CGPoint(x: -27, y: 19), nil, .push),
            ("pattern-right", BrushLibrary.streaky, CGPoint(x: 32, y: 0), nil, .push),
            ("pattern-left", BrushLibrary.streaky, CGPoint(x: -32, y: 0), nil, .push),
            ("pattern-up", BrushLibrary.streaky, CGPoint(x: 0, y: -32), nil, .push),
            ("pattern-down", BrushLibrary.streaky, CGPoint(x: 0, y: 32), nil, .push),
            ("pattern-diagonal", BrushLibrary.streaky, CGPoint(x: 24, y: 32), nil, .push),
            ("pattern-negative-diagonal", BrushLibrary.streaky, CGPoint(x: -24, y: -32), nil, .push),
            ("pattern-cross-diagonal", BrushLibrary.streaky, CGPoint(x: -31, y: 17), nil, .push),
            ("grain-diagonal", grained, CGPoint(x: 29, y: -23), nil, .push),
            ("grain-near-vertical", grained, CGPoint(x: 0.00001, y: 32), nil, .push),
            ("selected-grain-forward", grained, CGPoint(x: 32, y: 19), selection, .push),
            ("selected-grain-reverse", grained, CGPoint(x: -32, y: -19), selection, .push),
            ("selected-pattern", BrushLibrary.streaky, CGPoint(x: 0, y: -32), selection, .push),
            ("pinch", BrushLibrary.streaky, CGPoint(x: 24, y: 32), nil, .pinch),
            ("expand", BrushLibrary.streaky, CGPoint(x: 24, y: 32), nil, .expand),
            ("twirl", BrushLibrary.streaky, CGPoint(x: 24, y: 32), nil, .twirl)]
        // Captured from the ordinary inverse at 17db4c3 on native arm64. The full comparison
        // checked every source and RGBA byte before the temporary comparison solver was removed.
        let baselines: [String: (evaluations: Int, sha256: String)] = [
            "hard-right": (885826, "02abb95302b4aff599862f3ca9748ce6631a9f9b65e748e53f34ef969f2e45d3"),
            "hard-up": (879872, "7ba478fd21bbec447cee4eff688fa727ceb0045afa02f512510340b9468e4923"),
            "hard-negative-diagonal": (889940, "dee34df62f17c26728143c3d8216276cd5cd59da23a69861694b46555c98b085"),
            "pattern-right": (1543312, "05c9e80c28201f769942582e14058f43e038fcd8f46dbbe4e00d2c1a4b04e63e"),
            "pattern-left": (1543311, "5aba3047f9ba1b007b023f388cf212125da2e890a586ff595a1d475429eab2ed"),
            "pattern-up": (1546611, "45cc9c0171e7e7e99cfdc86dd2d472d0a116781b1b980762943c553eee027c63"),
            "pattern-down": (1546612, "02792746eb08310a524b8eea234a9e79a989a48739e7717b098f5f6db9063d1d"),
            "pattern-diagonal": (2141404, "acbea77d18cf19e614a13ca6e96dff594790d092ffa80ab80dbbb26ac273b23d"),
            "pattern-negative-diagonal": (2141398, "535fa95d459e780a24153bf4671954edc1bfe76b67d2553a1d9fc71cfe588580"),
            "pattern-cross-diagonal": (1825963, "ba038574bb5164f9c3328c290d19defd6ab43adab00962a0aa7f6e7ca4e9d3be"),
            "grain-diagonal": (2397802, "549011a3481dd4eb795b4cb0a9c3665725094e8419d41706f1c98a8564cec48c"),
            "grain-near-vertical": (2036476, "bd7e22dd9d7548da87776e0f36d97480006c1baef5fac53390b8735c0f179fa2"),
            "selected-grain-forward": (1594754, "b6629cc46e459cd79e045cd97e1f52e9bc3974787b42913b4075d5df55425ff2"),
            "selected-grain-reverse": (1544790, "e4fb77484492eb0f377c30f6c9ecead894aadd0365c29d9a324e607b8aeeccfe"),
            "selected-pattern": (1203670, "2d7549ae0956b994e07bf21bb4a22484a01df0a164c6f7b99b2d733ed890b231"),
            "pinch": (639822, "3839aac5ecdf6f1ca02f27eb2ee1ba12a2d2b0ba1aa026470f21c39683806399"),
            "expand": (836668, "8a85578f584e1d8952ada4f29fb7a3628cc643e8e76f516fb53e83efe20c1e20"),
            "twirl": (742332, "4b1e1c0bcc87deba816ea4c262bd6d855dff66cb219a69de34514962ab0698cc")]
        let side = 96, origin = CGPoint(x: 2952, y: 1952)
        var source = [UInt8](repeating: 0, count: side * side * 4)
        for y in 4..<(side - 4) { for x in 4..<(side - 4) {
            let offset = (y * side + x) * 4, alpha = 128 + (x + y) % 128
            source[offset] = UInt8((x * 31 + y * 7) % (alpha + 1))
            source[offset + 1] = UInt8((x * 3 + y * 29) % (alpha + 1))
            source[offset + 2] = UInt8((x * 13 + y * 11) % (alpha + 1))
            source[offset + 3] = UInt8(alpha)
        } }
        for (name, brush, travel, selection, mode) in fixtures {
            let definition = LiquifyDeformation(brush: brush, size: 48, power: 1, mode: mode, seed: 42,
                samples: StrokeSamples(points: [CGPoint(x: 3000 - travel.x / 2, y: 2000 - travel.y / 2),
                                               CGPoint(x: 3000 + travel.x / 2, y: 2000 + travel.y / 2)]), selection: selection)
            let field = LiquifyField(definition)
            let baseline = try XCTUnwrap(baselines[name])
            var evaluations = 0, failed = 0
            var sources: [CGPoint] = []
            for y in 0..<side { for x in 0..<side {
                let point = CGPoint(x: origin.x + CGFloat(x) + 0.5, y: origin.y + CGFloat(y) + 0.5)
                let actual = field.inverseSolution(point)
                evaluations += actual.evaluations
                if !actual.converged { failed += 1 }
                sources.append(actual.point)
                if let selection, !selection.contains(point, using: VectorCanvas.lassoFillRule) {
                    XCTAssertEqual(actual.point, point, "outside selected ink must remain exact")
                }
            } }
            func render(_ points: [CGPoint]) throws -> [UInt8] {
                try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: side, sourceHeight: side,
                    destinationWidth: side, destinationHeight: side) { point in
                    let resolved = points[Int(point.y) * side + Int(point.x)]
                    return CGPoint(x: resolved.x - origin.x, y: resolved.y - origin.y)
                })
            }
            let actualBytes = try render(sources)
            let digest = SHA256.hash(data: Data(actualBytes)).map { String(format: "%02x", $0) }.joined()
            print("LIQUIFY NATIVE INVERSE \(name) pixels=\(side * side) dabs=\(field.steps.count) evaluations=\(evaluations) failed=\(failed) SHA256=\(digest)")
            XCTAssertEqual(failed, 0, "every native source solve must converge for \(name)")
            XCTAssertEqual(digest, baseline.sha256, "\(name) must preserve every native rendered premultiplied RGBA byte")
            if mode == .push {
                XCTAssertLessThan(evaluations, baseline.evaluations * 95 / 100, "every Push fixture must remove measured solver work")
            } else {
                XCTAssertEqual(evaluations, baseline.evaluations, "other modes retain the ordinary evaluation sequence")
            }
            if name == "selected-grain-forward" || name == "pattern-negative-diagonal" {
                let image = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: actualBytes, width: side, height: side))
                let attachment = XCTAttachment(image: UIImage(cgImage: image))
                attachment.name = "liquify-inverse-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }


}
