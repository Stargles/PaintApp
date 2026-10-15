import XCTest
import CoreGraphics
import UIKit

final class LiquifyLogicTests: XCTestCase {
    private let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    private func gesture(_ mode: LiquifyMode = .push, power: Double = 1,
                         brush: Brush = TestBrushes.hardRound,
                         points: [CGPoint] = [CGPoint(x: 64, y: 64), CGPoint(x: 104, y: 64)],
                         selection: CGPath? = nil) -> LiquifyDeformation {
        LiquifyDeformation(brush: brush, size: 100, power: power, mode: mode, seed: 42,
            samples: StrokeSamples(points.map { VectorSample(point: $0) }, channels: .pressureOnly), selection: selection)
    }

    private func stroke(_ points: [CGPoint], group: UUID? = nil) -> VectorStroke {
        VectorStroke(brush: TestBrushes.hardRound, color: black, size: 5, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(point: $0) }, channels: .pressureOnly), motionGroupID: group)
    }

    func testPushMovesAlongTheUnscatteredWalk() {
        let field = LiquifyField(gesture())
        let moved = field.map(CGPoint(x: 64, y: 64))
        XCTAssertGreaterThan(moved.x, 68, "the centre of ink must follow the horizontal push")
        XCTAssertEqual(moved.y, 64, accuracy: 0.00001, "the straight walk has no vertical movement")
    }

    func testScatterChangesFootprintWithoutChangingPushDirection() {
        var brush = TestBrushes.hardRound
        brush.dab.scatterAcross = 0.8; brush.dab.scatterAlong = 0.8
        let field = LiquifyField(gesture(brush: brush, points: [CGPoint(x: 20, y: 64), CGPoint(x: 180, y: 64)]))
        let moved = (0..<160).map { field.map(CGPoint(x: $0, y: 64)) }
        XCTAssertTrue(moved.enumerated().contains { $0.element.x > CGFloat($0.offset) + 0.1 }, "scattered brush must still push some ink")
        XCTAssertTrue(moved.allSatisfy { $0.y == 64 }, "scatter must not inject a random push vector")
    }

    func testPinchMovesTowardTheDabCentre() {
        let field = LiquifyField(gesture(.pinch, points: [CGPoint(x: 64, y: 64)]))
        XCTAssertLessThan(field.map(CGPoint(x: 80, y: 64)).x, 80)
    }

    func testExpandMovesAwayFromTheDabCentre() {
        let field = LiquifyField(gesture(.expand, points: [CGPoint(x: 64, y: 64)]))
        XCTAssertGreaterThan(field.map(CGPoint(x: 80, y: 64)).x, 80)
    }

    func testTwirlTurnsTheInkAroundTheCentre() {
        let field = LiquifyField(gesture(.twirl, points: [CGPoint(x: 64, y: 64)]))
        XCTAssertGreaterThan(field.map(CGPoint(x: 80, y: 64)).y, 65)
    }

    func testPowerAndFlowBothControlMovement() {
        var fullBrush = TestBrushes.hardRound; fullBrush.modulations = BrushModulations(); fullBrush.dab.flow = 1
        var faint = fullBrush; faint.dab.flow = 0.25
        let full = LiquifyField(gesture(.expand, brush: fullBrush, points: [CGPoint(x: 64, y: 64)])).map(CGPoint(x: 80, y: 64)).x - 80
        let power = LiquifyField(gesture(.expand, power: 0.25, brush: fullBrush, points: [CGPoint(x: 64, y: 64)])).map(CGPoint(x: 80, y: 64)).x - 80
        let flow = LiquifyField(gesture(.expand, brush: faint, points: [CGPoint(x: 64, y: 64)])).map(CGPoint(x: 80, y: 64)).x - 80
        XCTAssertGreaterThan(power, 0)
        XCTAssertLessThan(power, full)
        XCTAssertEqual(flow, power, accuracy: 0.005, "flow and power multiply the same movement field")
    }

    func testBrushTipHolesLeaveSomeInkStationary() {
        let field = LiquifyField(gesture(.expand, brush: BrushLibrary.streaky, points: [CGPoint(x: 64, y: 64)]))
        let points = (40..<89).flatMap { y in (40..<89).map { CGPoint(x: $0, y: y) } }
        let distances = points.map { p -> CGFloat in let q = field.map(p); return hypot(q.x - p.x, q.y - p.y) }
        XCTAssertTrue(distances.contains { $0 > 0.1 }, "a patterned tip must move ink under its opaque parts")
        XCTAssertTrue(distances.contains { $0 == 0 }, "a patterned tip's holes must leave ink still")
    }

    func testSelectionLimitsBothSourceAndDestination() {
        let selection = CGPath(rect: CGRect(x: 60, y: 50, width: 15, height: 30), transform: nil)
        let field = LiquifyField(gesture(.expand, points: [CGPoint(x: 64, y: 64)], selection: selection))
        XCTAssertEqual(field.map(CGPoint(x: 80, y: 64)), CGPoint(x: 80, y: 64), "outside ink stays put")
        XCTAssertGreaterThan(field.map(CGPoint(x: 70, y: 64)).x, 70, "inside ink still moves")
        XCTAssertLessThanOrEqual(field.map(CGPoint(x: 74.9, y: 64)).x, 75, "ink cannot move through the selection's edge")
    }

    func testTrueCurvedSelectionEdgeHasContinuousMovementAndAValidInverse() {
        let selection = CGMutablePath()
        selection.move(to: CGPoint(x: 10, y: 20))
        selection.addQuadCurve(to: CGPoint(x: 118, y: 20), control: CGPoint(x: 64, y: -20))
        selection.addLine(to: CGPoint(x: 118, y: 120)); selection.addLine(to: CGPoint(x: 10, y: 120)); selection.closeSubpath()
        let field = LiquifyField(gesture(.expand, points: [CGPoint(x: 64, y: 20)], selection: selection))
        let t: CGFloat = 0.371234, u = 1 - t
        let boundary = CGPoint(x: 10 + 108 * t, y: 20 * (u * u + t * t) - 40 * u * t)
        let inside = CGPoint(x: boundary.x, y: boundary.y + 0.000001)
        let outside = CGPoint(x: boundary.x, y: boundary.y - 0.000001)
        XCTAssertTrue(selection.contains(inside, using: VectorCanvas.lassoFillRule), "PREMISE: true curved interior")
        XCTAssertFalse(selection.contains(outside, using: VectorCanvas.lassoFillRule), "PREMISE: true curved exterior")
        let moved = field.map(inside), still = field.map(outside)
        XCTAssertTrue(selection.contains(moved, using: VectorCanvas.lassoFillRule), "the chord approximation cannot let ink escape the real selected region")
        XCTAssertLessThan(hypot(moved.x - still.x, moved.y - still.y), 0.0001, "movement must vanish continuously at the true curve")
        let inverse = field.inverseSolution(moved)
        XCTAssertTrue(inverse.converged)
        XCTAssertLessThan(hypot(inverse.point.x - inside.x, inverse.point.y - inside.y), 0.000001)
    }

    func testFlattenerReportsCertifiedErrorsOnlyOnTheirOwnCurvedEdges() throws {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10, y: 20))
        path.addQuadCurve(to: CGPoint(x: 118, y: 20), control: CGPoint(x: 64, y: -20))
        path.addLine(to: CGPoint(x: 118, y: 120))
        var edges: [(CGPoint, CGPoint, CGFloat)] = []
        XCTAssertNotNil(StrokeGeometry.flattened(path, closeSubpaths: true) { edges.append(($0, $1, $2)) })
        XCTAssertEqual(edges.count, 66, "the existing64 chord cap plus the straight and implicit closing edges")
        XCTAssertEqual(edges[0].2, 160 / (8 * 64 * 64), accuracy: 0.0000001, "the quadratic's constant second derivative gives its analytic error bound")
        XCTAssertEqual(edges[64].2, 0, "a distant straight edge must not inherit a curve's taper loss")
        XCTAssertEqual(edges[65].2, 0)
        for index in 0..<64 {
            let t = (CGFloat(index) + 0.5) / 64, u = 1 - t
            let exact = CGPoint(x: 10 + 108 * t, y: 20 * (u * u + t * t) - 40 * u * t)
            let actual = sqrt(StrokeGeometry.distanceSquared(from: exact, toSegment: edges[index].0, edges[index].1))
            XCTAssertLessThanOrEqual(actual, edges[index].2 + 0.0000001, "the emitted bound must cover the real curve, including between chord endpoints")
        }
    }

    func testCurvedSelectionRasterPictureMovesInsideAndLeavesTransparentExteriorExact() throws {
        let side = 128, selection = CGMutablePath()
        selection.move(to: CGPoint(x: 12, y: 38))
        selection.addQuadCurve(to: CGPoint(x: 116, y: 38), control: CGPoint(x: 64, y: -8))
        selection.addLine(to: CGPoint(x: 116, y: 116)); selection.addLine(to: CGPoint(x: 12, y: 116)); selection.closeSubpath()
        var source = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side { for x in 0..<side where selection.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5), using: VectorCanvas.lassoFillRule) {
            let i = (y * side + x) * 4
            source[i] = (x + y) / 6 % 2 == 0 ? 220 : 25; source[i + 1] = 100; source[i + 3] = 255
        } }
        func attach(_ bytes: [UInt8], _ name: String) throws {
            let image = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: side, height: side))
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        try attach(source, "liquify-curved-selection-source")
        for (name, brush) in [("hard", TestBrushes.hardRound), ("pattern", BrushLibrary.streaky)] {
            let field = LiquifyField(gesture(.expand, brush: brush, points: [CGPoint(x: 64, y: 48)], selection: selection))
            var failures = 0
            let result = try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: side, sourceHeight: side,
                destinationWidth: side, destinationHeight: side) { point in
                    let inverse = field.inverseSolution(point)
                    if !inverse.converged { failures += 1 }
                    return inverse.point
                })
            XCTAssertEqual(failures, 0, "every selected pixel must have a coherent inverse")
            var changed = 0, leaked = 0
            for y in 0..<side { for x in 0..<side {
                let i = (y * side + x) * 4
                if selection.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5), using: VectorCanvas.lassoFillRule) {
                    if result[i] != source[i] { changed += 1 }
                } else if Array(result[i..<i + 4]) != Array(source[i..<i + 4]) { leaked += 1 }
            } }
            print("LIQUIFY CURVED SELECTION \(name) changed=\(changed) exteriorChanged=\(leaked) inverseFailures=\(failures)")
            XCTAssertGreaterThan(changed, 50, "the opaque parts of either native tip must reshape many selected pixels")
            XCTAssertEqual(leaked, 0, "all exterior pixels, including transparent ones, retain their exact bytes")
            try attach(result, "liquify-curved-selection-" + name)
        }
    }

    func testSparseLineBendsAndDistantStrokeStaysByteIdentical() throws {
        let line = stroke([CGPoint(x: 20, y: 64), CGPoint(x: 120, y: 64)])
        let distant = stroke([CGPoint(x: 20, y: 200), CGPoint(x: 120, y: 200)])
        let field = LiquifyField(gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)]))
        let result = field.mapping([.stroke(line), .stroke(distant)])
        guard case .stroke(let bent) = result[0], case .stroke(let unchanged) = result[1] else { return XCTFail("stroke kinds must remain vector strokes") }
        XCTAssertGreaterThan(bent.samples.positions.map(\.y).max() ?? 0, 67, "a two-point line must bend where the brush pushes it")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(unchanged), try encoder.encode(distant), "distant geometry and brush phase must remain identical")
    }

    func testLocalReshapePreviewWindowCoversAllChangedPaintedPixels() throws {
        var brush = BrushLibrary.streaky
        brush.modulations = BrushModulations(); brush.dab.spacing = 0.8
        let ink = VectorStroke(brush: brush, color: CodableColor(red: 1, green: 0.2, blue: 0.1, alpha: 1), size: 24, opacity: 1,
            samples: StrokeSamples(points: [CGPoint(x: 32, y: 96), CGPoint(x: 992, y: 96)]))
        let original: [VectorElement] = [.stroke(ink)]
        let field = LiquifyField(gesture(points: [CGPoint(x: 300, y: 96), CGPoint(x: 300, y: 128)]))
        let moved = field.mapping(original)
        let size = CGSize(width: 1024, height: 256)
        let beforeImage = (try XCTUnwrap(VectorCanvas(size: size, elements: original).render()))
        let afterImage = (try XCTUnwrap(VectorCanvas(size: size, elements: moved).render()))
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(beforeImage.cgImage)))
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(afterImage.cgImage)))
        // Even a correctly padded local spine window cannot cover a later native-dab phase change.
        let local = field.replacementBounds.insetBy(dx: -40, dy: -40)
        var outside = 0
        for y in 0..<256 { for x in 0..<1024 where !local.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
            let i = (y * 1024 + x) * 4
            if before[i + 3] != after[i + 3] { outside += 1 }
        } }
        print("LIQUIFY PAINTED PHASE outsideLocalChanged=\(outside) fieldBounds=\(field.replacementBounds)")
        for (name, image) in [("before", beforeImage), ("after", afterImage)] {
            let attachment = XCTAttachment(image: image); attachment.name = "liquify-long-patterned-target-" + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(outside, 0, "a local held replacement must agree with the eventual full committed drawing")
    }

    /// Test-only collection of the existing unscattered site emission, alongside native stamps.
    /// This does not choose a saved representation or change the production renderer.
    private final class NativeSiteComparisonTarget: DabTarget {
        let collected = BrushStamper.CollectingDabTarget()
        var sites: [CGPoint] = []
        private var site = CGPoint.zero
        func dabSite(at point: CGPoint, travel: CGPoint) { site = point }
        func beginStroke() {}
        func endStroke() {}
        func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {
            collected.beginStrokeGroup(opacity: opacity, blendMode: blendMode, texture: texture)
        }
        func endStrokeGroup() { collected.endStrokeGroup() }
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            sites.append(site)
            collected.stampCircle(at: point, radius: radius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
        }
        func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                        angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
            sites.append(site)
            collected.stampImage(texture, at: point, diameter: diameter, angle: angle, color: color, alpha: alpha, blendMode: blendMode)
        }
    }

    func testOwnerBoundaryComparisonUsesNativeStampsAndExactSelectedPixelWarp() throws {
        let size = CGSize(width: 192, height: 160)
        let selection = CGPath(rect: CGRect(x: 64, y: 48, width: 72, height: 48), transform: nil)
        let field = LiquifyField(gesture(points: [CGPoint(x: 100, y: 75), CGPoint(x: 100, y: 103)], selection: selection))
        var brush = BrushLibrary.streaky
        brush.modulations = BrushModulations()
        let native = NativeSiteComparisonTarget()
        BrushStamper.stampStroke(into: native, samples: StrokeSamples(points: [CGPoint(x: 20, y: 75), CGPoint(x: 172, y: 75)]),
            brush: brush, color: UIColor(red: 0.85, green: 0.16, blue: 0.05, alpha: 1), brushSize: 80,
            brushOpacity: 1, random: DabRandom(seed: 42))
        XCTAssertEqual(native.sites.count, native.collected.dabs.count)
        let original = BrushStamper.BakedStroke(dabs: native.collected.dabs, opacity: native.collected.opacity,
            blendMode: native.collected.blendMode, texture: native.collected.texture)
        var moved = original
        moved.dabs = zip(original.dabs, native.sites).map { dab, site in
            let displaced = field.map(site)
            var result = dab
            result.center.x += displaced.x - site.x; result.center.y += displaced.y - site.y
            return result
        }
        func render(_ stroke: BrushStamper.BakedStroke) -> UIImage {
            UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
                BrushStamper.replay(stroke, into: CGContextDabTarget(ctx.cgContext), through: .identity)
            }
        }
        let sourceImage = render(original), siteImage = render(moved)
        let source = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(sourceImage.cgImage)))
        let sites = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(siteImage.cgImage)))
        let pixels = try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: 192, sourceHeight: 160,
            destinationWidth: 192, destinationHeight: 160, inverseTexelMap: field.inverse))
        let pixelImage = UIImage(cgImage: try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: pixels, width: 192, height: 160)))
        var outsideSites = 0, outsidePixels = 0
        for y in 0..<160 { for x in 0..<192 where !selection.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5), using: VectorCanvas.lassoFillRule) {
            let i = (y * 192 + x) * 4
            if sites[i + 3] != source[i + 3] { outsideSites += 1 }
            if pixels[i + 3] != source[i + 3] { outsidePixels += 1 }
        } }
        print("LIQUIFY OWNER SELECTION A_outsideChanged=\(outsideSites) B_outsideChanged=\(outsidePixels) nativeDabs=\(original.dabs.count)")
        XCTAssertGreaterThan(outsideSites, 50, "PREMISE: whole native stamps visibly overhang the selected vector sites")
        XCTAssertEqual(outsidePixels, 0, "the pixel alternative preserves every exterior alpha byte")
        for (name, title, image) in [("original", "Before", sourceImage), ("A-line-points", "A: Move line points", siteImage), ("B-selected-pixels", "B: Move selected pixels", pixelImage)] {
            let format = PixelOps.transparentFormat(); format.opaque = true
            let paper = UIGraphicsImageRenderer(size: CGSize(width: 576, height: 480), format: format).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 576, height: 480))
                ctx.cgContext.scaleBy(x: 3, y: 3); ctx.cgContext.interpolationQuality = .none
                image.draw(in: CGRect(origin: .zero, size: size))
                (title as NSString).draw(at: CGPoint(x: 6, y: 8), withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.darkGray])
                ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor); ctx.cgContext.setLineWidth(1)
                ctx.cgContext.setLineDash(phase: 0, lengths: [3, 2]); ctx.cgContext.addPath(selection); ctx.cgContext.strokePath()
            }
            let attachment = XCTAttachment(image: paper); attachment.name = "liquify-selection-boundary-" + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testNonlinearMappingCarriesEverySensorAndParentDabWalk() {
        let samples = StrokeSamples([
            VectorSample(x: 20, y: 64, pressure: 0.2, deltaTime: 0, tiltAltitude: 0.4, tiltAzimuth: 0.2),
            VectorSample(x: 120, y: 64, pressure: 0.8, deltaTime: 0.1, tiltAltitude: 1.1, tiltAzimuth: 1.4)
        ], channels: .captured)
        var ink = stroke(samples.positions)
        ink.samples = samples
        ink.lattice = DabLattice(samples: samples, parameters: [0, 1])
        let field = LiquifyField(gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)]))
        let moved = VectorGeometryMap.stroke(ink, densify: true) { $0.map(field.map) }
        XCTAssertEqual(moved.samples.channels, samples.channels)
        XCTAssertEqual(moved.samples.map(\.deltaTime).reduce(0, +), 0.1, accuracy: 0.00001)
        XCTAssertEqual(moved.samples.first?.pressure, 0.2)
        XCTAssertEqual(moved.samples.last?.tiltAltitude, 1.1)
        XCTAssertEqual(moved.lattice?.samples, moved.samples, "split strokes must move their parent walk together with the spine")
    }

    func testFaintNonlinearMovementAndParentWalkSurviveFirstSave() throws {
        var ink = stroke([CGPoint(x: 64, y: 64), CGPoint(x: 80, y: 64)])
        ink.lattice = DabLattice(samples: ink.samples, parameters: [0, 1])
        let distant = stroke([CGPoint(x: 64, y: 200), CGPoint(x: 80, y: 200)])
        let field = LiquifyField(gesture(power: 0.002))
        let result = field.mapping([.stroke(ink), .stroke(distant)])
        guard case .stroke(let moved) = result[0], case .stroke(let untouched) = result[1] else { return XCTFail("expected strokes") }
        let shift = moved.samples.positions[0].x - ink.samples.positions[0].x
        XCTAssertGreaterThan(shift, 0)
        XCTAssertLessThan(shift, 0.125, "the fixture must expose ordinary quarter-point rounding")
        XCTAssertTrue(moved.precise)
        XCTAssertEqual(moved.lattice?.precise, true, "the spine and parent must use the same storage precision")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let reopened = try JSONDecoder().decode(VectorStroke.self, from: encoder.encode(moved))
        XCTAssertEqual(reopened.samples.positions[0].x, moved.samples.positions[0].x, accuracy: 0.0001)
        XCTAssertEqual(reopened.lattice!.samples.positions[0].x, moved.lattice!.samples.positions[0].x, accuracy: 0.0001)
        XCTAssertFalse(untouched.precise)
        XCTAssertEqual(try encoder.encode(untouched), try encoder.encode(distant), "unreached ink retains its original storage")
    }

    func testTappedSetDoesNotMoveAnUntappedOverlappingStroke() {
        let a = stroke([CGPoint(x: 40, y: 64), CGPoint(x: 90, y: 64)])
        let b = stroke([CGPoint(x: 40, y: 64), CGPoint(x: 90, y: 64)])
        let field = LiquifyField(gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)]))
        let moved = field.mapping([.stroke(a), .stroke(b)], selectedIDs: [a.id])
        guard case .stroke(let first) = moved[0], case .stroke(let second) = moved[1] else { return XCTFail("expected two strokes") }
        XCTAssertNotEqual(first.samples, a.samples)
        XCTAssertEqual(second.samples, b.samples)
    }

    func testBrushNearAStrokeBoundingBoxDoesNotRewriteUnreachedGeometry() throws {
        let corner = stroke([CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 120), CGPoint(x: 120, y: 120)])
        let field = LiquifyField(gesture(.expand, points: [CGPoint(x: 100, y: 30)]))
        guard case .stroke(let unchanged) = field.mapping([.stroke(corner)])[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(unchanged.samples, corner.samples, "a bounding rectangle is not proof that the brush reached the ink")
    }

    func testPosedInkIsMovedWhereTheArtistSeesItAndStoredBackAtRest() throws {
        let ink = stroke([CGPoint(x: 20, y: 24), CGPoint(x: 80, y: 24)])
        let pose = PoseMap(CGAffineTransform(translationX: 20, y: 40))
        let field = LiquifyField(gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)]))
        guard case .stroke(let changed) = field.mapping([.stroke(ink)], poses: [ink.id: pose])[0] else { return XCTFail("expected ink") }
        XCTAssertGreaterThan(changed.samples.positions.map(\.y).max() ?? 0, 27, "the displayed y64 line must move even though its rest line is at y24")
        XCTAssertLessThan(changed.samples.positions.map(\.y).max() ?? 100, 55, "the displayed pose must not be baked into stored geometry")
    }

    func testCompactSweepCostsGeometryRatherThanCanvasArea() throws {
        let sweep = gesture(points: [CGPoint(x: 0, y: 100), CGPoint(x: 4096, y: 100)])
        let field = LiquifyField(sweep)
        XCTAssertLessThan(try JSONEncoder().encode(sweep).count, 16000, "a 4096-point sweep must save a compact field definition")
        XCTAssertLessThan(field.retainedByteCount, 2 * 1024 * 1024, "a broad 4096-point sweep must never retain a canvas displacement grid")
    }

    func testComplete4096RowSweepHasAnExplicitActiveFieldBudget() throws {
        let points = (0..<42).flatMap { row -> [CGPoint] in
            let y = CGFloat(row * 100)
            return row.isMultiple(of: 2) ? [CGPoint(x: 0, y: y), CGPoint(x: 4096, y: y)] :
                [CGPoint(x: 4096, y: y), CGPoint(x: 0, y: y)]
        }
        let sweep = gesture(points: points), field = LiquifyField(sweep)
        let saved = try JSONEncoder().encode(sweep).count
        print("LIQUIFY ROW SWEEP dabs=\(field.steps.count) retained=\(field.retainedByteCount) saved=\(saved) hundredFields=\(field.retainedByteCount * 100)")
        XCTAssertLessThan(saved, 16000, "a complete canvas sweep persists sensor geometry, never a dense field")
        XCTAssertLessThan(field.retainedByteCount, 8 * 1024 * 1024, "one actively evaluated full-canvas field has a fixed working budget")
    }

    func testHardAndPatternedRasterEdgesHaveAConvergentInverseAtMaximumPower() throws {
        let side = 128
        var source = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side { for x in 0..<side {
            let offset = (y * side + x) * 4
            let filled = y < 58 || (y >= 72 && x >= 18 && x < 108)
            guard filled else { continue }
            source[offset] = x / 8 % 2 == 0 ? 220 : 25
            source[offset + 1] = y / 8 % 2 == 0 ? 150 : 35
            source[offset + 2] = 50; source[offset + 3] = 255
        } }
        func attach(_ bytes: [UInt8], _ name: String) throws {
            let image = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: side, height: side))
            let attachment = XCTAttachment(image: UIImage(cgImage: image)); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        try attach(source, "liquify-inverse-source")
        for (name, brush) in [("hard", TestBrushes.hardRound), ("pattern", BrushLibrary.streaky)] {
            for mode in [LiquifyMode.push, .expand, .twirl] {
                let field = LiquifyField(gesture(mode, brush: brush, points: [CGPoint(x: 42, y: 64), CGPoint(x: 86, y: 64)]))
                var unsolved = 0, evaluations = 0
                let rendered = try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: side, sourceHeight: side,
                    destinationWidth: side, destinationHeight: side) { point in
                    let inverse = field.inverseResult(point)
                    if !inverse.converged { unsolved += 1 }
                    evaluations += inverse.evaluations
                    return inverse.point
                })
                try attach(rendered, "liquify-inverse-\(name)-\(mode.rawValue)")
                print("LIQUIFY INVERSE \(name) \(mode) unsolved=\(unsolved) pixels=\(side * side) dabs=\(field.steps.count) retained=\(field.retainedByteCount) evaluations=\(evaluations)")
                XCTAssertEqual(unsolved, 0, "every destination must have a coherent inverse; original-pixel fallback can leave stationary speckles")
            }
        }
    }


    func testSmallBrushDoesNotExpandTheWholeLongSparseLine() throws {
        let line = stroke([CGPoint(x: -5000, y: 64), CGPoint(x: 5000, y: 64)])
        let field = LiquifyField(gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)]))
        guard case .stroke(let bent) = field.mapping([.stroke(line)])[0] else { return XCTFail("expected ink") }
        XCTAssertGreaterThan(bent.samples.positions.map(\.y).max() ?? 0, 67)
        XCTAssertLessThan(bent.samples.count, 150, "only the bounded brush region needs new samples")
        XCTAssertEqual(bent.samples.first?.point, line.samples.first?.point)
        XCTAssertEqual(bent.samples.last?.point, line.samples.last?.point)
    }

    func testSubdivisionConservesMultipleSegmentTimeIntervals() {
        let original = StrokeSamples([VectorSample(x: 0, y: 0, deltaTime: 0),
                                     VectorSample(x: 20, y: 0, deltaTime: 0.02),
                                     VectorSample(x: 40, y: 0, deltaTime: 0.03)], channels: .captured)
        let divided = StrokeGeometry.subdivision(original, maxSpacing: 1, region: CGRect(x: 5, y: -2, width: 30, height: 4))
        XCTAssertEqual(divided.samples.map(\.deltaTime).reduce(0, +), 0.05, accuracy: 0.000001,
                       "each source interval is divided once, never subtracted from the next segment")
    }

    func testInverseSolvesStrongMapsAcrossBrushAndBinBoundaries() {
        for mode in LiquifyMode.allCases {
            let field = LiquifyField(gesture(mode, points: [CGPoint(x: 48, y: 64), CGPoint(x: 112, y: 64)]))
            var solved = 0
            for y in stride(from: 25, through: 105, by: 4) {
                for x in stride(from: 25, through: 155, by: 4) {
                    let inverse = field.inverseResult(CGPoint(x: x, y: y))
                    XCTAssertTrue(inverse.point.x.isFinite && inverse.point.y.isFinite, "maximum-power \(mode) cannot produce a divergent sample")
                    if inverse.converged { solved += 1 }
                    XCTAssertTrue(inverse.converged, "every footprint location must invert without folds")
                    XCTAssertLessThan(inverse.residual, 0.005, "a reported inverse must actually solve the field")
                }
            }
            XCTAssertEqual(solved, 693, "\(mode) must genuinely invert every sampled point")
        }
    }

    func testReplacementWindowContainsHardTipMovementAtTheEdge() {
        let field = LiquifyField(gesture(.expand, points: [CGPoint(x: 64, y: 64)]))
        let original = CGPoint(x: 113.5, y: 64)
        let moved = field.map(original)
        XCTAssertGreaterThan(moved.x, original.x, "a hard tip moves ink near its continuously faded edge")
        XCTAssertTrue(field.replacementBounds.contains(original) && field.replacementBounds.contains(moved),
                      "preview and commit must replace both original and moved ink")
    }

    private func recipe(groups: [MotionGroupBinding] = []) -> InterpolationRecipe {
        let layer = UUID()
        return InterpolationRecipe(references: [InterpolationReference(layerID: layer, celID: UUID()),
                                               InterpolationReference(layerID: layer, celID: UUID())], t: 0.5, groups: groups)
    }

    func testTwoMotionGroupsBothReceiveTheCrossingGesture() throws {
        let a = UUID(), b = UUID()
        let rest = Lattice(covering: [.zero, CGPoint(x: 160, y: 160)], targetCellSize: 40, padding: 1)
        var recipe = recipe(groups: [MotionGroupBinding(groupID: a, lattices: [rest, rest]),
                                    MotionGroupBinding(groupID: b, lattices: [rest, rest])])
        var edit = gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)])
        edit.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe)
        recipe.deformations = [edit]
        let ink = [VectorElement.stroke(stroke([CGPoint(x: 30, y: 64), CGPoint(x: 120, y: 64)], group: a)),
                   .stroke(stroke([CGPoint(x: 30, y: 70), CGPoint(x: 120, y: 70)], group: b))]
        let result = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: { _ in ink }))
        XCTAssertEqual(result.forward.count, 2, "both groups' ink must remain in the picture")
        for element in result.forward {
            guard case .stroke(let ink) = element else { return XCTFail("expected ink") }
            XCTAssertGreaterThan(ink.samples.positions.map(\.y).max() ?? 0, ink.motionGroupID == a ? 67 : 73,
                                 "a crossing Liquify stroke must not silently choose only the nearest motion group")
        }
    }

    func testNonparticipatingGroupKeepsItsStoredSpine() throws {
        let a = UUID(), b = UUID()
        let rest = Lattice(covering: [.zero, CGPoint(x: 160, y: 160)], targetCellSize: 40, padding: 1)
        var recipe = recipe(groups: [MotionGroupBinding(groupID: a, lattices: [rest, rest]),
                                    MotionGroupBinding(groupID: b, lattices: [rest, rest])])
        var edit = gesture(); edit.captures = [.init(groupID: a, lattice: rest)]
        recipe.deformations = [edit]
        let ink = stroke([CGPoint(x: 30, y: 64), CGPoint(x: 120, y: 64)], group: b)
        let result = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: { _ in [.stroke(ink)] }))
        guard case .stroke(let unchanged) = result.forward[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(unchanged.samples, ink.samples, "a field captured for another group must not deform or densify this group's ink")
    }

    func testCaptureGeometrySurvivesLatticeExpansion() throws {
        let id = UUID()
        let rest = Lattice(covering: [.zero, CGPoint(x: 160, y: 160)], targetCellSize: 40, padding: 1)
        var recipe = recipe(groups: [MotionGroupBinding(groupID: id, lattices: [rest, rest])])
        var edit = gesture(); edit.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe)
        recipe.deformations = [edit]
        let ink = stroke([CGPoint(x: 30, y: 64), CGPoint(x: 120, y: 64)])
        let before = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: { _ in [.stroke(ink)] }))
        var untouched = recipe; untouched.deformations = []
        let control = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: untouched, at: 0.5, content: { _ in [.stroke(ink)] }))
        recipe.groups[0].lattices = recipe.groups[0].lattices.map { $0.expanded(toContain: [CGPoint(x: -500, y: -500)]).lattice }
        let after = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: { _ in [.stroke(ink)] }))
        let size = CGSize(width: 160, height: 160)
        let a = try XCTUnwrap((try XCTUnwrap(VectorCanvas(size: size, elements: before.forward).render())).cgImage)
        let b = try XCTUnwrap((try XCTUnwrap(VectorCanvas(size: size, elements: after.forward).render())).cgImage)
        let unreshaped = try XCTUnwrap((try XCTUnwrap(VectorCanvas(size: size, elements: control.forward).render())).cgImage)
        XCTAssertNotEqual(CanvasFixture.rgbaBytes(a), CanvasFixture.rgbaBytes(unreshaped), "the retained capture must actually reshape the picture")
        XCTAssertEqual(CanvasFixture.rgbaBytes(a), CanvasFixture.rgbaBytes(b), "immutable capture geometry cannot depend on recipe lattice cell indices")
    }

    func testLocalFillMovementPreservesDistantBezierCommandsExactly() throws {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 20, y: 64, width: 100, height: 25))
        path.addEllipse(in: CGRect(x: 500, y: 500, width: 180, height: 120))
        let fill = VectorFillElement(path: path, color: black)
        let field = LiquifyField(gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)]))
        guard case .fill(let changed) = field.mapping([.fill(fill)])[0] else { return XCTFail("expected fill") }
        XCTAssertNotEqual(changed.pathData, fill.pathData, "the local rectangular edge must move")
        func distantCommands(_ path: CGPath) -> ([Int], [CGPoint]) {
            var types: [Int] = [], points: [CGPoint] = [], distant = false
            path.applyWithBlock { raw in
                let item = raw.pointee
                if item.type == .moveToPoint { distant = item.points[0].x > 400 }
                if distant {
                    types.append(Int(item.type.rawValue))
                    for i in 0..<VectorGeometryMap.pointCount(of: item.type) { points.append(item.points[i]) }
                }
            }
            return (types, points)
        }
        let original = distantCommands(try XCTUnwrap(fill.cgPath)), result = distantCommands(try XCTUnwrap(changed.cgPath))
        XCTAssertEqual(result.0, original.0, "distant Beziers must remain curve commands, not flattened lines")
        XCTAssertEqual(result.1, original.1, "every distant control point must stay exact")
    }

    func testCapturedSupportIncludesBilinearGridEdgeExtrema() throws {
        var lattice = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 100)
        lattice.vertices[4] = CGPoint(x: 145, y: 125)
        var definition = gesture(.expand, points: [CGPoint(x: 35, y: 105)])
        definition.size = 30
        let field = LiquifyField(definition)
        let capture = LiquifyDeformation.Capture(groupID: UUID(), lattice: lattice)
        let support = try XCTUnwrap(definition.restBounds(capture: capture, using: field))
        let point = lattice.warpToRest(lattice.embedInCurrent([CGPoint(x: 20, y: 105)]))[0]
        XCTAssertTrue(support.contains(point), "an intersected cell edge can reach past the field box's inverse corners")
    }

    func testUnreachedCurveControlsStayExactWhenAnotherFillComponentMoves() throws {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 20, y: 200))
        path.addCurve(to: CGPoint(x: 108, y: 200), control1: CGPoint(x: 64, y: 100), control2: CGPoint(x: 64, y: 100))
        path.closeSubpath()
        path.addRect(CGRect(x: 60, y: 96, width: 8, height: 10))
        let fill = VectorFillElement(path: path, color: black)
        var brushGesture = gesture(points: [CGPoint(x: 64, y: 100), CGPoint(x: 64, y: 108)])
        brushGesture.size = 12
        let field = LiquifyField(brushGesture)
        guard case .fill(let changed) = field.mapping([.fill(fill)])[0] else { return XCTFail("expected fill") }
        XCTAssertNotEqual(changed.pathData, fill.pathData, "the small rectangular component must reshape")
        func firstCurve(_ path: CGPath) -> [CGPoint] {
            var points: [CGPoint] = []
            path.applyWithBlock { raw in
                if raw.pointee.type == .addCurveToPoint && points.isEmpty { points = (0..<3).map { raw.pointee.points[$0] } }
            }
            return points
        }
        XCTAssertEqual(firstCurve(try XCTUnwrap(changed.cgPath)), firstCurve(try XCTUnwrap(fill.cgPath)),
            "control points in the brush cannot bend an actual curve that never enters it")
    }

    func testDerivedRegionSelectionLimitsTheStoredFieldAndItsDestination() throws {
        let inside = stroke([CGPoint(x: 70, y: 60), CGPoint(x: 74, y: 70)])
        let outside = stroke([CGPoint(x: 80, y: 60), CGPoint(x: 100, y: 70)])
        var recipe = recipe()
        let selection = CGPath(rect: CGRect(x: 60, y: 50, width: 15, height: 30), transform: nil)
        var selected = gesture(.expand, points: [CGPoint(x: 64, y: 64)], selection: selection)
        selected.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe, content: { _ in [.stroke(inside), .stroke(outside)] })
        recipe.deformations = [selected]
        let decoded = try JSONDecoder().decode(InterpolationRecipe.self, from: JSONEncoder().encode(recipe))
        let result = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: decoded, at: 0.5, content: { _ in [.stroke(inside), .stroke(outside)] }))
        guard case .stroke(let a) = result.forward[0], case .stroke(let b) = result.forward[1] else { return XCTFail("expected linked ink") }
        XCTAssertNotEqual(a.samples, inside.samples, "selected linked ink moves after the field is reopened")
        XCTAssertTrue(a.samples.positions.allSatisfy { selection.contains($0) }, "the shown result remains within the selection")
        XCTAssertEqual(b.samples, outside.samples, "unselected linked ink stays exact")
        XCTAssertEqual(decoded.references, recipe.references, "the selection must not detach source links")
    }

    func testRepeatedStrongPatternedGesturesRemainReversibleAtSelectionEdges() {
        let selection = CGPath(rect: CGRect(x: 48, y: 35, width: 44, height: 65), transform: nil)
        let fields = [LiquifyMode.push, .expand, .twirl].map {
            LiquifyField(gesture($0, brush: BrushLibrary.streaky, points: [CGPoint(x: 50, y: 64), CGPoint(x: 86, y: 64)], selection: selection))
        }
        for y in stride(from: CGFloat(34.5), through: 100.5, by: 3) {
            for x in stride(from: CGFloat(47.5), through: 92.5, by: 3) {
                let original = CGPoint(x: x, y: y)
                let shown = fields.reduce(original) { $1.map($0) }
                var restored = shown
                for field in fields.reversed() {
                    let inverse = field.inverseResult(restored)
                    XCTAssertTrue(inverse.converged, "strong composed movement cannot fold at a selection edge")
                    restored = inverse.point
                }
                XCTAssertLessThan(hypot(restored.x - original.x, restored.y - original.y), 0.005)
                if !selection.contains(original) { XCTAssertEqual(shown, original, "outside pixels remain exact") }
                else { XCTAssertTrue(selection.contains(shown), "movement cannot leak through the selected edge") }
            }
        }
    }

    func testCaptureOccurrenceLineageSurvivesSplitMergeAndNewInkRules() {
        let a = UUID(), b = UUID(), replacement = UUID(), split = UUID()
        let ref = CelRef(layerID: UUID(), celID: UUID())
        let oldA = LiquifyDeformation.InkID(kind: .source, elementID: UUID(), reference: ref)
        let oldB = LiquifyDeformation.InkID(kind: .source, elementID: UUID(), reference: ref)
        let newcomers = [LiquifyDeformation.InkID(kind: .source, elementID: UUID(), reference: ref),
                         .init(kind: .subject, elementID: UUID())]
        let grid = Lattice(cols: 1, rows: 1, restOrigin: .zero, restCellSize: 100)
        let captures: [LiquifyDeformation.Capture] = [.init(groupID: a, lattice: grid, inkIDs: [oldA]), .init(groupID: b, lattice: grid, inkIDs: [oldB])]
        func resolver(_ members: [LiquifyDeformation.Membership]) -> LiquifyDeformation.CaptureResolver {
            .init(captures: captures, members: members)
        }
        let merged = resolver([.init(id: oldA, groupID: replacement), .init(id: oldB, groupID: replacement)])
        XCTAssertEqual(merged.capture(for: oldA, groupID: replacement)?.groupID, a, "merged ink retains its own original capture")
        XCTAssertEqual(merged.capture(for: oldB, groupID: replacement)?.groupID, b, "two old lineages must not be mapped through one capture")
        for new in newcomers {
            XCTAssertNil(merged.capture(for: new, groupID: replacement), "new source or subject ink in an ambiguous merge inherits no arbitrary history")
        }
        let unique = resolver([.init(id: oldA, groupID: split)])
        XCTAssertEqual(unique.capture(for: oldA, groupID: split)?.groupID, a, "splitting and re-registering preserves existing ink")
        for new in newcomers {
            XCTAssertEqual(unique.capture(for: new, groupID: split)?.groupID, a, "source and subject ink inherit one unambiguous replacement lineage")
            XCTAssertEqual(unique.capture(for: new, groupID: b)?.groupID, b, "source and subject ink inherit a surviving group")
        }
        XCTAssertEqual(resolver([]).capture(for: oldA, groupID: nil)?.groupID, a, "deleting a group cannot erase the old ink's reshape")
    }

    func testClonedSourceCelOccurrencesDoNotAliasAndEncodingIsCanonical() throws {
        let element = UUID(), layer = UUID(), a = UUID(), b = UUID()
        let first = LiquifyDeformation.InkID(kind: .source, elementID: element, reference: .init(layerID: layer, celID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
        let clone = LiquifyDeformation.InkID(kind: .source, elementID: element, reference: .init(layerID: layer, celID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))
        let grid = Lattice(cols: 1, rows: 1, restOrigin: .zero, restCellSize: 100)
        let capture = LiquifyDeformation.Capture(groupID: a, lattice: grid, inkIDs: [first, clone])
        let reordered = LiquifyDeformation.Capture(groupID: a, lattice: grid, inkIDs: Set([clone, first]))
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(capture), try encoder.encode(reordered), "set order must not change persisted bytes or cache identity")
        let resolver = LiquifyDeformation.CaptureResolver(captures: [.init(groupID: a, lattice: grid, inkIDs: [first]), .init(groupID: b, lattice: grid, inkIDs: [clone])], members: [])
        XCTAssertEqual(resolver.capture(for: first, groupID: nil)?.groupID, a)
        XCTAssertEqual(resolver.capture(for: clone, groupID: nil)?.groupID, b, "copied UUIDs in another cel must retain their own lineage")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(capture)) as? [String: Any])
        let encodedMembers = try XCTUnwrap(object["inkIDs"] as? [[String: Any]])
        let orderedReferences = encodedMembers.compactMap { ($0["reference"] as? [String: Any])?["celID"] as? String }
        XCTAssertEqual(orderedReferences, [first.reference!.celID.uuidString, clone.reference!.celID.uuidString],
            "saved occurrence order must be canonical, independent of Set iteration")
        for missing in ["groupID", "lattice", "inkIDs"] {
            var broken = object; broken.removeValue(forKey: missing)
            XCTAssertThrowsError(try JSONDecoder().decode(LiquifyDeformation.Capture.self,
                from: JSONSerialization.data(withJSONObject: broken)), "required current capture metadata cannot disappear")
        }
        var duplicate = object; duplicate["inkIDs"] = [encodedMembers[0], encodedMembers[0]]
        XCTAssertThrowsError(try JSONDecoder().decode(LiquifyDeformation.Capture.self,
            from: JSONSerialization.data(withJSONObject: duplicate)), "a duplicate occurrence cannot collapse silently")
        for source in [true, false] {
            var invalid = encodedMembers[0]
            if source { invalid.removeValue(forKey: "reference") } else { invalid["kind"] = "local" }
            var broken = object; broken["inkIDs"] = [invalid]
            XCTAssertThrowsError(try JSONDecoder().decode(LiquifyDeformation.Capture.self,
                from: JSONSerialization.data(withJSONObject: broken)), "source requires a cel; local ink cannot claim one")
        }
    }

    func testInverseBatchesKeepExactSourcesCountersAndFailuresAcrossTheTail() {
        let field = LiquifyField(gesture())
        var points = (0..<8_205).map { CGPoint(x: CGFloat($0 % 130) + 0.5, y: CGFloat($0 / 130) + 0.5) }
        points[4_097] = CGPoint(x: CGFloat.nan, y: 64)
        points[8_204] = CGPoint(x: 72, y: CGFloat.infinity)
        let scalar = points.map(field.inverseSolution)
        let work = field.inverseSolutions(&points)
        XCTAssertEqual(work.failure, .nonFinite, "a failed source in any batch refuses the complete picture")
        XCTAssertEqual(work.evaluations, scalar.reduce(0) { $0 + $1.evaluations })
        XCTAssertEqual(points.map { Double($0.x).bitPattern }, scalar.map { Double($0.point.x).bitPattern })
        XCTAssertEqual(points.map { Double($0.y).bitPattern }, scalar.map { Double($0.point.y).bitPattern })
        var empty: [CGPoint] = []
        let noWork = field.inverseSolutions(&empty)
        XCTAssertEqual(noWork.evaluations, 0)
        XCTAssertNil(noWork.failure)
        XCTAssertTrue(empty.isEmpty)
    }

    func testRasterInverseStripsMatchSerialPixelsAndRespectTheirWholeWindowBudget() throws {
        let size = CGSize(width: 320, height: 192)
        let image = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            for y in stride(from: 0, to: 192, by: 4) {
                for x in stride(from: 0, to: 320, by: 4) {
                    UIColor(red: CGFloat((x * 7 + y) % 255) / 255,
                            green: CGFloat((x + y * 3) % 255) / 255, blue: 0.7, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }
        let snapshot = CelPixelSnapshot(raster: nil, baked: image, size: size)
        let source = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(try XCTUnwrap(image.cgImage), width: 320, height: 192))
        let previousBudget = CompositorBudget.budgetOverrideBytes
        defer { CompositorBudget.budgetOverrideBytes = previousBudget }
        for mode in [LiquifyMode.push, .pinch, .expand, .twirl] {
            let field = LiquifyField(gesture(mode, brush: BrushLibrary.streaky,
                points: [CGPoint(x: 120, y: 90), CGPoint(x: 160, y: 105)]))
            let window = field.replacementBounds
            let rect = try XCTUnwrap(snapshot.replacementRect(in: window, through: nil))
            let patch = try XCTUnwrap(snapshot.liquifiedPatch(in: window, using: field))
            let expected = try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: 320, sourceHeight: 192,
                destinationWidth: Int(rect.width), destinationHeight: Int(rect.height)) { local in
                field.inverse(CGPoint(x: rect.minX + local.x, y: rect.minY + local.y))
            })
            let actual = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(try XCTUnwrap(patch.image.cgImage),
                width: Int(rect.width), height: Int(rect.height)))
            XCTAssertEqual(actual, expected, "every strip seam and nonzero origin preserves the serial picture")
            XCTAssertTrue(patch.changed, "the parity picture must include actual deformation")
            let sourceRect = rect.insetBy(dx: -1, dy: -1).intersection(CGRect(origin: .zero, size: size))
            let bytes = CelPixelSnapshot.liquifyWorkingBytes(sourceSize: sourceRect.size, destinationSize: rect.size)
            XCTAssertGreaterThan(bytes, Int(sourceRect.width * sourceRect.height) * 16 + Int(rect.width * rect.height) * 8,
                "the join needs both output copies plus parallel result headers")
            CompositorBudget.budgetOverrideBytes = bytes - 1
            XCTAssertNil(snapshot.liquifiedPatch(in: window, using: field), "refuse before allocating an under-budget picture")
            CompositorBudget.budgetOverrideBytes = previousBudget
        }
    }

    func testLongPatternPushInverseMatchesIndependentSixtyDigitSourceCoordinates() {
        let field = LiquifyField(gesture(brush: BrushLibrary.streaky,
            points: [CGPoint(x: 3000, y: 2000), CGPoint(x: 3500, y: 2000)]))
        // Decimal60 reference over126 exact native-tip dabs, no spatial bins. Input SHA and
        // independent script/results are recorded in PERFORMANCE; source pixels are the criterion.
        let references: [(CGFloat, CGFloat)] = [
            (3125.5, 3026.82978873623666503368059092357),
            (3141.5, 3026.82978873623920398145746544801),
            (3157.5, 3026.82978873623924191193948646073),
            (3173.5, 3026.82978873623924247860000600771),
            (3189.5, 3026.82978873623924248706560220644),
            (3205.5, 3026.82978873623924248719207355309),
            (3221.5, 3026.82978873623924248719396296538),
            (3237.5, 3026.82978873623924248719399119216)]
        for (destination, source) in references {
            let inverse = field.inverseSolution(CGPoint(x: destination, y: 1965.5))
            XCTAssertTrue(inverse.converged, "every independently checked source solve must converge")
            XCTAssertEqual(inverse.point.x, source, accuracy: 0.00000001,
                "1e-8 source pixels is far below bilinear sampling precision; destination residual is ill-conditioned")
            XCTAssertEqual(inverse.point.y, 1965.5, "a horizontal Push cannot move the source row")
        }
    }

    func testPushSubmapAcceleratesEveryTravelDirectionWithoutLosingSourcePrecision() {
        let destination = CGPoint(x: 3000, y: 2000)
        let directions = [CGPoint(x: 4, y: 0), CGPoint(x: -4, y: 0), CGPoint(x: 0, y: 4), CGPoint(x: 0, y: -4),
                          CGPoint(x: 3, y: 4), CGPoint(x: -3, y: 4), CGPoint(x: 3, y: -4), CGPoint(x: -3, y: -4),
                          CGPoint(x: 0.0000001, y: 4)]
        for travel in directions {
            let reference = CGPoint(x: destination.x - travel.x * 0.6, y: destination.y - travel.y * 0.6)
            let lengthSquared = travel.x * travel.x + travel.y * travel.y
            func iterate(_ point: CGPoint) -> CGPoint {
                let along = ((point.x - reference.x) * travel.x + (point.y - reference.y) * travel.y) / lengthSquared
                return CGPoint(x: destination.x - travel.x * (0.6 + 0.15 * along),
                               y: destination.y - travel.y * (0.6 + 0.15 * along))
            }
            let accelerated = LiquifyField.inverseSubmap(at: destination, pushTravel: travel, iterate: iterate)
            XCTAssertTrue(accelerated.converged, "both signs and either dominant travel axis must solve")
            XCTAssertEqual(accelerated.point.x, reference.x, accuracy: 0.000000000001)
            XCTAssertEqual(accelerated.point.y, reference.y, accuracy: 0.000000000001)
            XCTAssertLessThanOrEqual(accelerated.evaluations, 5, "a linear Push contraction should not spend the ordinary iteration count")
            let ordinary = LiquifyField.inverseSubmap(at: destination, pushTravel: nil, iterate: iterate)
            XCTAssertTrue(ordinary.converged, "other modes retain the ordinary shared source solver")
            XCTAssertEqual(ordinary.point.x, reference.x, accuracy: 0.000000000001)
            XCTAssertEqual(ordinary.point.y, reference.y, accuracy: 0.000000000001)
            XCTAssertGreaterThan(ordinary.evaluations, 8, "non-Push maps must not use the one-direction extrapolation")
        }
    }

    func testPushSubmapRejectsAnExtrapolationWithAWorseOtherAxisResidual() {
        var visited: [CGPoint] = []
        let result = LiquifyField.inverseSubmap(at: .zero, pushTravel: CGPoint(x: 1, y: 0)) { point in
            visited.append(point)
            return CGPoint(x: 1 + 0.2 * point.x, y: 1 + 0.1 * point.y)
        }
        XCTAssertTrue(result.converged, "the safeguard must keep ordinary convergence for a general contraction")
        XCTAssertEqual(result.point.x, 1.25, accuracy: 0.000000000001)
        XCTAssertEqual(result.point.y, 1 / 0.9, accuracy: 0.000000000001)
        XCTAssertGreaterThan(visited.count, 4)
        guard visited.count > 4 else { return }
        XCTAssertEqual(visited[3].x, 1.25, accuracy: 0.000000000001)
        XCTAssertEqual(visited[3].y, 1.25, accuracy: 0.000000000001)
        XCTAssertEqual(visited[4].x, 1.24, accuracy: 0.000000000001,
                       "the rejected proposal must resume the ordinary two-step point, reusing its evaluated next point")
        XCTAssertEqual(visited[4].y, 1.11, accuracy: 0.000000000001,
                       "an exact x proposal is insufficient while its y residual is worse")
    }

    func testInverseSubmapKeepsItsEvaluationLimitAndReportsNonFiniteValues() {
        for travel in [nil, CGPoint(x: 1, y: -1)] as [CGPoint?] {
            var calls = 0
            let unsolved = LiquifyField.inverseSubmap(at: .zero, pushTravel: travel) { point in
                calls += 1
                return CGPoint(x: point.x + 1, y: point.y - 1)
            }
            XCTAssertEqual(unsolved.failure, .iterationLimit, "exhausting the bound must not claim a source solution")
            XCTAssertEqual(unsolved.evaluations, 32)
            XCTAssertEqual(calls, 32, "the cap includes actual residual-check evaluations")
            let invalid = LiquifyField.inverseSubmap(at: .zero, pushTravel: travel) { _ in CGPoint(x: CGFloat.nan, y: 0) }
            XCTAssertEqual(invalid.failure, .nonFinite)
            XCTAssertEqual(invalid.evaluations, 1)
            let fixed = LiquifyField.inverseSubmap(at: CGPoint(x: 3, y: 4), pushTravel: travel) { $0 }
            XCTAssertTrue(fixed.converged, "unchanged support needs just its true fixed-point check")
            XCTAssertEqual(fixed.point, CGPoint(x: 3, y: 4))
            XCTAssertEqual(fixed.evaluations, 1)
        }
    }

    func testLocalInkDrawnAfterLongPushLandsAtPenAndOnlyLaterGesturesAffectIt() throws {
        var recipe = recipe()
        let original = stroke([CGPoint(x: 3026.75, y: 1965.5)])
        let provider: InterpolationEvaluator.ContentProvider = { _ in [.stroke(original)] }
        var first = gesture(brush: BrushLibrary.streaky,
            points: [CGPoint(x: 3000, y: 2000), CGPoint(x: 3500, y: 2000)])
        first.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe, content: provider)
        recipe.deformations = [first]
        let pen = CGPoint(x: 3141.5, y: 1965.5)
        let plan = try XCTUnwrap(InterpolationEvaluator.planLocalEdit(recipe: recipe, at: 0.5, points: [pen]),
            "a prior ill-conditioned forward map must not reject a new local brush mark")
        recipe.localEdits = [.init(stroke: stroke(plan.restPoints))]
        let before = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: provider)?.localEdits.first?.stroke?.samples.positions.first)
        XCTAssertEqual(before.x, pen.x, accuracy: 0.00000001, "old gestures cannot reshape a mark that did not exist then")
        XCTAssertEqual(before.y, pen.y, accuracy: 0.00000001)
        var later = gesture(.expand, points: [CGPoint(x: pen.x - 10, y: pen.y)])
        later.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe, content: provider)
        recipe.deformations.append(later)
        let after = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: provider)?.localEdits.first?.stroke?.samples.positions.first)
        XCTAssertGreaterThan(after.x, before.x, "a later Liquify gesture captures and moves the local mark normally")
    }

    func testLocalPenPositionDoesNotReplayGesturesThatPrecedeItsBirth() throws {
        var recipe = recipe()
        let ink = stroke([CGPoint(x: 30, y: 64), CGPoint(x: 120, y: 64)])
        let provider: InterpolationEvaluator.ContentProvider = { _ in [.stroke(ink)] }
        var first = gesture(points: [CGPoint(x: 64, y: 64), CGPoint(x: 64, y: 94)])
        first.captures = InterpolationEvaluator.liquifyCaptures(recipe: recipe, content: provider)
        var second = gesture(.twirl, points: [CGPoint(x: 64, y: 70)])
        second.captures = first.captures
        recipe.deformations = [first, second]
        let pen = CGPoint(x: 70, y: 72)
        let plan = try XCTUnwrap(InterpolationEvaluator.planLocalEdit(recipe: recipe, at: 0.5, points: [pen]))
        var stored = stroke(plan.restPoints); stored.visibilityThreshold = 0.5
        recipe.localEdits = [.init(stroke: stored)]
        let result = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 0.5, content: provider))
        let shown = try XCTUnwrap(result.localEdits.first?.stroke?.samples.positions.first)
        XCTAssertLessThan(hypot(shown.x - pen.x, shown.y - pen.y), 0.005, "drawing after two reshapes must land at the pen, without replaying gestures made before this mark existed")
        XCTAssertNil(first.captures.first?.groupID)
        XCTAssertFalse(first.captures.first?.inkIDs.isEmpty ?? true, "unbound ink needs a scoped identity capture for future resize conjugation")
    }

    func testRecipeFingerprintAndPackedGestureRoundTripIncludeDeformation() throws {
        var original = recipe()
        let key = original.contentFingerprint
        original.deformations = [gesture(.twirl, power: 0.37, brush: BrushLibrary.streaky,
            points: [CGPoint(x: 64.125, y: 65.375), CGPoint(x: 79.8125, y: 91.03125)])]
        let decoded = try JSONDecoder().decode(InterpolationRecipe.self, from: JSONEncoder().encode(original))
        XCTAssertNotEqual(original.contentFingerprint, key, "the bake must become dirty when a linked frame is reshaped")
        XCTAssertEqual(decoded.deformations, original.deformations, "saved field, captured brush and precise samples must survive reopen")
    }

    func testLiquifyProfileIsIndependentAndRestoresWithTheScene() throws {
        var tools = SceneTools()
        tools.profiles.brush.size = 41; tools.profiles.brush.opacity = 0.8
        tools.profiles.eraser.size = 62; tools.profiles.eraser.opacity = 0.4
        let brush = tools.profiles.brush, eraser = tools.profiles.eraser
        tools.tool = .liquify; tools.liquifyMode = .twirl
        tools.profiles.liquify.size = 88; tools.profiles.liquify.opacity = 0.23
        let decoded = try JSONDecoder().decode(SceneTools.self, from: JSONEncoder().encode(tools))
        XCTAssertEqual(decoded.profiles.brush, brush)
        XCTAssertEqual(decoded.profiles.eraser, eraser)
        XCTAssertEqual(decoded, tools, "the selected tool, mode, size and power are per-scene settings")
    }

    func testOrdinaryVectorGestureIsHeldAndCommitsExactlyOneUndoStep() throws {
        let manager = CanvasFixture.manager(); manager.addVectorLayer()
        let layer = manager.layers[1], cel = layer.cels[0]
        let canvas = try XCTUnwrap(cel.vector)
        let ink = stroke([CGPoint(x: 10, y: 24), CGPoint(x: 50, y: 24)])
        canvas.addStroke(ink); manager.history.removeAll()
        let profile = ToolProfile(preset: TestBrushes.hardRound, size: 50, opacity: 1)
        var session = try XCTUnwrap(manager.beginLiquify(layerID: layer.id, profile: profile, size: 50, seed: 7))
        session.samples = StrokeSamples([VectorSample(x: 32, y: 24), VectorSample(x: 32, y: 48)], channels: .pressureOnly)
        session.window = CGRect(x: 0, y: 0, width: 64, height: 64)
        manager.holdLiquify(&session)
        XCTAssertEqual(canvas.elements.count, 1)
        guard case .stroke(let heldBase) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(heldBase.samples, ink.samples, "a preview must not write the cel")
        manager.commitLiquify(session)
        guard case .stroke(let changed) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertNotEqual(changed.samples, ink.samples)
        XCTAssertEqual(manager.history.undo(), .liquify)
        guard case .stroke(let undone) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(undone.samples, ink.samples)
        XCTAssertNil(manager.history.undo(), "the whole stroke must be one undo step")
        XCTAssertEqual(manager.history.redo(), .liquify)
        guard case .stroke(let redone) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(redone.samples, changed.samples)
    }

    private func pendingGesture(inkCopies: Int = 1) throws -> (CanvasManager, VectorCanvas, VectorStroke, LiquifySession, CelContentProcedure) {
        let manager = CanvasFixture.manager(); manager.addVectorLayer()
        let layer = manager.layers[1], canvas = try XCTUnwrap(layer.cels[0].vector)
        let ink = stroke([CGPoint(x: 10, y: 24), CGPoint(x: 50, y: 24)])
        canvas.addStroke(ink)
        for _ in 1..<inkCopies { canvas.addStroke(stroke(ink.samples.positions)) }
        manager.history.removeAll()
        manager.onHeldPictureMoved = {} // A hosted gesture whose last draw has not landed.
        let profile = ToolProfile(preset: TestBrushes.hardRound, size: 50, opacity: 1)
        var session = try XCTUnwrap(manager.beginLiquify(layerID: layer.id, profile: profile, size: 50, seed: 7))
        session.samples = StrokeSamples([VectorSample(x: 32, y: 24), VectorSample(x: 32, y: 48)], channels: .pressureOnly)
        session.window = CGRect(x: 0, y: 0, width: 64, height: 64)
        manager.holdLiquify(&session)
        let procedure = try XCTUnwrap(manager.liveCelContentEdit?.procedure)
        manager.commitLiquify(session)
        return (manager, canvas, ink, session, procedure)
    }

    func testLiftWaitsForMatchingPictureAndReusesItsResolvedGeometryOnce() throws {
        let (manager, canvas, ink, session, procedure) = try pendingGesture()
        XCTAssertTrue(procedure.isPending)
        XCTAssertEqual(procedure.resolutionCount, 0, "normal lift must perform no geometry mapping on main")
        XCTAssertTrue(manager.history.undoStack.isEmpty)
        let picture = try XCTUnwrap(manager.liveCelContentEdit).picture()
        _ = try XCTUnwrap(manager.liveCelContentEdit).picture()
        XCTAssertEqual(procedure.resolutionCount, 1, "repeated presentation reads reuse one resolved tick")
        XCTAssertNotEqual(procedure.resolve(session.elementsBefore).first?.id, nil)
        procedure.didPresent()
        XCTAssertNil(manager.liveCelContentEdit)
        XCTAssertEqual(manager.history.undoStack.count, 1)
        XCTAssertEqual(procedure.resolutionCount, 1, "landing and committing reuse the worker value")
        guard case .stroke(let changed) = canvas.elements[0], case .stroke(let shown) = picture.elements[0] else { return XCTFail("expected ink") }
        XCTAssertNotEqual(changed.samples, ink.samples)
        XCTAssertEqual(changed.samples, shown.samples)
        procedure.didPresent()
        XCTAssertEqual(manager.history.undoStack.count, 1, "a late landing cannot duplicate the write")
    }

    func testUndoSettlesCompletedPendingGestureThenUndoesItBeforeLateLanding() throws {
        let (manager, canvas, ink, _, procedure) = try pendingGesture()
        manager.undo()
        guard case .stroke(let undone) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(undone.samples, ink.samples)
        XCTAssertTrue(manager.history.undoStack.isEmpty)
        XCTAssertEqual(manager.history.redoStack.count, 1)
        procedure.didPresent()
        XCTAssertEqual(canvas.elements.count, 1)
        XCTAssertTrue(manager.history.undoStack.isEmpty, "late rendering cannot resurrect an undone gesture")
    }

    func testSecondEditSettlesPendingGestureBeforeCapturingItsStartingInk() throws {
        let (manager, canvas, ink, first, procedure) = try pendingGesture()
        let profile = ToolProfile(preset: TestBrushes.hardRound, size: 50, opacity: 1)
        let next = try XCTUnwrap(manager.beginLiquify(layerID: first.layerID, profile: profile, size: 50, seed: 8))
        guard case .stroke(let starting) = next.elementsBefore[0], case .stroke(let committed) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertNotEqual(starting.samples, ink.samples)
        XCTAssertEqual(starting.samples, committed.samples, "the second edit starts after the first completed write")
        XCTAssertEqual(manager.history.undoStack.count, 1)
        let newInk = stroke([CGPoint(x: 4, y: 4), CGPoint(x: 20, y: 4)])
        canvas.addStroke(newInk)
        procedure.didPresent()
        XCTAssertEqual(canvas.elements.count, 2, "a late first draw cannot replace ink from the following edit")
        XCTAssertEqual(manager.history.undoStack.count, 1)
    }

    func testCancellingUnwrittenGestureDropsLatePresentationWithoutHistory() throws {
        let (manager, canvas, ink, _, procedure) = try pendingGesture()
        manager.endLiveEdit()
        _ = procedure.resolve(canvas.elements)
        procedure.didPresent()
        guard case .stroke(let unchanged) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertEqual(unchanged.samples, ink.samples)
        XCTAssertTrue(manager.history.undoStack.isEmpty)
    }

    func testSourceVersionChangeRejectsStaleFinalValueRatherThanReplacingNewInk() throws {
        let (manager, canvas, ink, _, procedure) = try pendingGesture()
        let fresh = stroke([CGPoint(x: 4, y: 4), CGPoint(x: 20, y: 4)])
        canvas.addStroke(fresh) // Simulate an external writer bypassing the common edit boundary.
        _ = procedure.resolve([.stroke(ink)])
        procedure.didPresent()
        XCTAssertEqual(canvas.elements.map(\.id), [ink.id, fresh.id])
        XCTAssertTrue(manager.history.undoStack.isEmpty)
        XCTAssertNil(manager.liveCelContentEdit)
    }

    private func startInFlightResolve(_ procedure: CelContentProcedure, original: [VectorElement]) throws -> DispatchSemaphore {
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = procedure.resolve(original)
            finished.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while !procedure.isResolving && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertTrue(procedure.isResolving, "PREMISE: the geometry worker is still producing the pending final tick")
        return finished
    }

    func testEditBoundaryRacingTheWorkerUsesOneProducerAndCommitsOnce() throws {
        let (manager, _, _, session, procedure) = try pendingGesture(inkCopies: 64)
        let finished = try startInFlightResolve(procedure, original: session.elementsBefore)
        manager.beginCanvasEdit()
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(procedure.resolutionCount, 1, "the explicit boundary waits for the in-flight value instead of remapping it")
        XCTAssertEqual(manager.history.undoStack.count, 1)
        XCTAssertNil(manager.liveCelContentEdit)
    }

    @MainActor
    func testSnapshotBoundaryRacingTheWorkerUsesOneProducerAndCommitsOnce() throws {
        let (manager, _, _, session, procedure) = try pendingGesture(inkCopies: 64)
        let finished = try startInFlightResolve(procedure, original: session.elementsBefore)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".paintproj")
        defer { try? FileManager.default.removeItem(at: url) }
        let saved = expectation(description: "in-flight gesture snapshot saved")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(procedure.resolutionCount, 1, "snapshot capture shares the already-running geometry producer")
        XCTAssertEqual(manager.history.undoStack.count, 1)
        XCTAssertNil(manager.liveCelContentEdit)
    }

    @MainActor
    func testSnapshotSettlesCompletedPendingGestureAndPreservesItsSavedInk() throws {
        let (manager, canvas, ink, session, procedure) = try pendingGesture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".paintproj")
        defer { try? FileManager.default.removeItem(at: url) }
        let saved = expectation(description: "pending gesture snapshot saved")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        XCTAssertNil(manager.liveCelContentEdit)
        XCTAssertEqual(manager.history.undoStack.count, 1)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        let savedCanvas = try XCTUnwrap(reopened.layers.first { $0.id == session.layerID }?.cels.first { $0.id == session.celID }?.vector)
        guard case .stroke(let written) = savedCanvas.elements[0], case .stroke(let current) = canvas.elements[0] else { return XCTFail("expected ink") }
        XCTAssertNotEqual(written.samples, ink.samples)
        XCTAssertEqual(written.samples.positions[0].x, current.samples.positions[0].x, accuracy: 0.0001)
        XCTAssertEqual(written.samples.positions[0].y, current.samples.positions[0].y, accuracy: 0.0001)
        procedure.didPresent()
        XCTAssertEqual(manager.history.undoStack.count, 1, "late rendering after snapshot cannot add another write")
    }
}
