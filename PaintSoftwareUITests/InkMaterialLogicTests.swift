import XCTest
import CoreGraphics
import UIKit

/// Spatial material owns native ink independently of its editable spine. These fixtures exercise
/// archive ownership and transfer without substituting a canvas-global operation resolver.
final class InkMaterialLogicTests: XCTestCase {
    private let color = CodableColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 1)

    private func operation() -> InkMaterialOperation {
        InkMaterialOperation(LiquifyDeformation(brush: TestBrushes.hardRound, size: 40,
            power: 0.8, mode: .push, seed: 17,
            samples: StrokeSamples(points: [CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 25)])))
    }

    private func stroke(_ operation: InkMaterialOperation) -> VectorStroke {
        let samples = StrokeSamples(points: [CGPoint(x: 4, y: 20), CGPoint(x: 60, y: 20)])
        return VectorStroke(brush: TestBrushes.pencil, color: color, size: 8, opacity: 0.7,
            samples: samples, seed: 7,
            placement: StrokePlacement(map: .identity, restSize: 8,
                source: .retained(samples: samples, lattice: nil, precise: true),
                material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operation, bridge: .identity)])))
    }

    private func archive(_ value: VectorCanvasData) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    func testCanvasSharesOneDefinitionAndDetachedCopiesRetainIt() throws {
        let shared = operation()
        let strokes = (0..<100).map { _ in VectorCanvasData.ElementData.stroke(stroke(shared)) }
        let encoded = try JSONEncoder().encode(VectorCanvasData(elements: strokes, transform: []))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual((json["materialOperations"] as? [Any])?.count, 1,
                       "one gesture is stored once, irrespective of affected stroke count")
        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: encoded)
        let ink = decoded.elements.compactMap { element -> VectorStroke? in
            guard case .stroke(let value) = element else { return nil }; return value
        }
        XCTAssertEqual(ink.count, 100)
        let first = try XCTUnwrap(ink.first?.placement?.material?.bindings.first?.operation)
        XCTAssertTrue(ink.allSatisfy { $0.placement?.material?.bindings.first?.operation === first },
                      "archive references resolve to one immutable runtime definition")
        let detached = VectorCanvas(size: CGSize(width: 80, height: 40), elements: ink.map(VectorElement.stroke)).makeCopy()
        XCTAssertTrue(detached.elements.allSatisfy { $0.materialProgram?.bindings.first?.operation === first },
                      "element-only copies retain the definition without a canvas side table")
        XCTAssertEqual(first.deformation, shared.deformation)
    }

    func testDanglingDuplicateAndConflictingDefinitionsFailTheWholePayload() throws {
        let shared = operation()
        let value = VectorCanvasData(elements: [.stroke(stroke(shared))], transform: [])
        var dangling = try archive(value)
        dangling["materialOperations"] = []
        XCTAssertThrowsError(try JSONDecoder().decode(VectorCanvasData.self, from: JSONSerialization.data(withJSONObject: dangling))) {
            XCTAssertTrue($0 is InkMaterialCodingError, "a material error must escape lossy element slots")
        }
        var malformedToo = dangling
        var slots = try XCTUnwrap(malformedToo["elements"] as? [[String: Any]])
        var payload = try XCTUnwrap(slots[0]["stroke"] as? [String: Any])
        payload["color"] = "malformed ordinary field"
        slots[0]["stroke"] = payload; malformedToo["elements"] = slots
        XCTAssertThrowsError(try JSONDecoder().decode(VectorCanvasData.self, from: JSONSerialization.data(withJSONObject: malformedToo))) {
            XCTAssertTrue($0 is InkMaterialCodingError, "lossy geometry cannot conceal unreadable material")
        }
        var duplicate = try archive(value)
        let definitions = try XCTUnwrap(duplicate["materialOperations"] as? [Any])
        duplicate["materialOperations"] = definitions + definitions
        XCTAssertThrowsError(try JSONDecoder().decode(VectorCanvasData.self, from: JSONSerialization.data(withJSONObject: duplicate)))
        var changed = shared.deformation; changed.power = 0.2
        let conflicting = VectorCanvasData(elements: [.stroke(stroke(shared)), .stroke(stroke(InkMaterialOperation(changed)))], transform: [])
        XCTAssertThrowsError(try JSONEncoder().encode(conflicting), "same UUID cannot silently select either of two different fields")
    }

    func testStandaloneStrokeLocalEditAndRecipeOwnCompleteScopedTables() throws {
        let source = stroke(operation())
        let standalone = try JSONDecoder().decode(VectorStroke.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(standalone.placement, source.placement)
        let local = LocalEdit(stroke: source)
        let decodedLocal = try JSONDecoder().decode(LocalEdit.self, from: JSONEncoder().encode(local))
        XCTAssertEqual(decodedLocal.stroke.placement, source.placement)
        let recipe = InterpolationRecipe(localEdits: [local, LocalEdit(stroke: source)])
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["materialOperations"] as? [Any])?.count, 1)
        let read = try JSONDecoder().decode(InterpolationRecipe.self, from: data)
        let a = try XCTUnwrap(read.localEdits.first?.stroke.placement?.material?.bindings.first?.operation)
        let b = try XCTUnwrap(read.localEdits.last?.stroke.placement?.material?.bindings.first?.operation)
        XCTAssertTrue(a === b)
        XCTAssertEqual(read.localEdits[0].stroke.placement, source.placement)
    }

    func testNativeAncestorCorrespondenceSurvivesSelfCrossingAndSubdivision() throws {
        let native = StrokeSamples(points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20),
            CGPoint(x: 0, y: 20), CGPoint(x: 20, y: 0)])
        let parent = DabLattice(samples: native, parameters: [0, 1, 2, 3], precise: true)
        let source = StrokePlacement.Source.retained(samples: native, lattice: parent, precise: true)
        let cut = source.remapped(onto: [0.5, 1, 2, 2.5])
        guard case .retained(let own, let ancestor?, _) = cut else { return XCTFail("cut must retain its native ancestor") }
        XCTAssertEqual(own.positions.first, own.positions.last, "PREMISE: crossing sites share a position")
        XCTAssertEqual(ancestor.parameters, [0.5, 1, 2, 2.5], "native site identity uses ancestor parameters, never nearest position")
        guard case .retained(_, let subdivided?, _) = cut.remapped(onto: [0, 0.5, 1, 2, 2.5, 3]) else { return XCTFail("subdivision must retain correspondence") }
        XCTAssertEqual(subdivided.parameters, [0.5, 0.75, 1, 2, 2.25, 2.5])
        XCTAssertEqual(subdivided.samples, native, "parent walk, randomness and spacing keep their original owner")
        let restored = try JSONDecoder().decode(StrokePlacement.Source.self, from: JSONEncoder().encode(cut))
        XCTAssertEqual(restored, cut)
    }

    func testStationaryFillMaterialChangeIsRecognizedAndSurvivesMove() throws {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 60, height: 40), transform: nil)
        let original = VectorFillElement(path: path, color: color)
        var changed = original
        changed.placement = FillPlacement(pathData: original.pathData,
            material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operation(), bridge: .identity)]))
        XCTAssertFalse(VectorElement.fill(original).hasSameSpatialInk(as: .fill(changed)),
                       "a field inside a fill changes its material without moving any boundary point")
        let delta = CGAffineTransform(translationX: 10, y: 12)
        guard case .fill(let moved) = VectorCanvas.mapping(.fill(changed), throughStretch: delta) else { return XCTFail("fill remains editable") }
        XCTAssertEqual(moved.placement?.pathData, original.pathData, "Move retains native coverage")
        XCTAssertEqual(moved.placement?.map, Homography(delta))
        XCTAssertEqual(moved.placement?.material.bindings.first?.bridge, .homography(Homography(delta)))
        let restored = try JSONDecoder().decode(VectorFillElement.self, from: JSONEncoder().encode(moved))
        XCTAssertEqual(restored.placement, moved.placement)
    }

    func testSizeEditChangesNativeWidthAndLaterMoveKeepsSharedMaterial() throws {
        let original = stroke(operation())
        guard case .stroke(let resized)? = SelectionEditKind.rewritten(.stroke(original), to: .size(20)) else { return XCTFail("editable native size") }
        XCTAssertEqual(resized.placement?.restSize, 20)
        XCTAssertEqual(resized.effectiveWalk?.size, 20, "renderer must consume the edited native width")
        let delta = CGAffineTransform(translationX: 10, y: 12)
        guard case .stroke(let moved) = VectorCanvas.mapping(.stroke(resized), throughStretch: delta) else { return XCTFail("Move retains vector ink") }
        XCTAssertEqual(moved.placement?.source, original.placement?.source)
        XCTAssertEqual(moved.placement?.restSize, 20)
        XCTAssertEqual(moved.placement?.material?.bindings.first?.bridge, .homography(Homography(delta)))
        XCTAssertTrue(moved.placement?.material?.bindings.first?.operation === original.placement?.material?.bindings.first?.operation)
    }
    func testNonlinearNativeTransportComposesWithLaterMoveAndRoundTrips() throws {
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 30)
        var current = rest; current.vertices[4] = CGPoint(x: 40, y: 24)
        let bridge = InkMaterialBridge.lattice(captured: rest, current: current, pose: .identity)
        let point = CGPoint(x: 17, y: 22)
        let expected = current.warp(current.embedInRest([point]))[0]
        XCTAssertEqual(try XCTUnwrap(bridge.map([point])).first, expected)
        let restoredPoint = try XCTUnwrap(bridge.map([expected], inverse: true)).first!
        XCTAssertEqual(restoredPoint.x, point.x, accuracy: 0.0000001)
        XCTAssertEqual(restoredPoint.y, point.y, accuracy: 0.0000001)
        let move = Homography.translation(x: 100, y: 70) * .scale(x: 1.5, y: 1.5)
        let moved = bridge.moved(by: move)
        let shown = try XCTUnwrap(moved.map([try XCTUnwrap(move.map(point))])).first!
        let movedExpected = try XCTUnwrap(move.map(expected))
        XCTAssertEqual(shown.x, movedExpected.x, accuracy: 0.0000001, "native dabs and their transport must not apply Move twice")
        XCTAssertEqual(shown.y, movedExpected.y, accuracy: 0.0000001)
        var ink = stroke(operation())
        ink.placement?.transport = moved
        let read = try JSONDecoder().decode(VectorStroke.self, from: JSONEncoder().encode(ink))
        XCTAssertEqual(read.placement, ink.placement)
        XCTAssertEqual(read.effectiveWalk?.transport, moved, "detached native paint keeps its nonlinear transport")
    }

    func testMaterialBoundsIncludeCrossingsBetweenLatticeEdgesAndFieldBox() throws {
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 100)
        var captured = rest; captured.vertices[4] = CGPoint(x: 145, y: 125)
        let bridge = InkMaterialBridge.lattice(captured: captured, current: rest, pose: .identity)
        let box = CGRect(x: 20, y: 90, width: 30, height: 30)
        let bound = bridge.bounds(of: box)
        var edge: [CGPoint] = []
        for i in 0...100 {
            let t = CGFloat(i) / 100
            edge.append(CGPoint(x: box.minX, y: box.minY + box.height * t))
            edge.append(CGPoint(x: box.maxX, y: box.minY + box.height * t))
            edge.append(CGPoint(x: box.minX + box.width * t, y: box.minY))
            edge.append(CGPoint(x: box.minX + box.width * t, y: box.maxY))
        }
        XCTAssertTrue(try XCTUnwrap(bridge.map(edge)).allSatisfy(bound.contains), "support must include edge extrema even when no lattice vertex lies in the field box")
        XCTAssertLessThan(bound.minX, 14, "the demonstrated edge point reaches rest x13.86 beyond the x14.38 corner-only estimate")
    }

    func testUnusableRuntimeTransportRefusesMappingAndEncoding() throws {
        let singular = InkMaterialBridge.homography(.scale(x: 0, y: 1))
        XCTAssertNil(singular.map([CGPoint(x: 4, y: 8)]), "a failed transport cannot quietly show unmodified ink")
        XCTAssertThrowsError(try JSONEncoder().encode(singular)) { XCTAssertTrue($0 is InkMaterialCodingError) }
        let vanishing = InkMaterialBridge.homography(Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: -0.25, h: 0, i: 1))
        XCTAssertNil(vanishing.map([CGPoint(x: 4, y: 8)]), "the projective horizon has no source sample")
        XCTAssertTrue(vanishing.bounds(of: CGRect(x: 2, y: 2, width: 4, height: 4)).isInfinite,
                      "an invalid bounded support must widen conservatively rather than omit paint")
    }

    func testActualCutKeepsPreciseShownAndNativeParentThroughSave() throws {
        var ink = stroke(operation())
        let original = StrokeSamples(points: [CGPoint(x: 4.0625, y: 20.0625), CGPoint(x: 60.0625, y: 20.0625)])
        ink.samples = original
        ink.placement?.source = .retained(samples: original, lattice: nil, precise: true)
        ink = ink.markedPrecise()
        let canvas = VectorCanvas(size: CGSize(width: 80, height: 40), elements: [.stroke(ink)])
        XCTAssertTrue(canvas.erase(alongPath: StrokeSamples(points: [CGPoint(x: 32.0625, y: 20.0625)]),
            brush: TestBrushes.hardRound, size: 8, mode: .cutPoints))
        let pieces = canvas.elements.compactMap(\.stroke).filter { $0.composite == .paint }
        XCTAssertGreaterThan(pieces.count, 1, "PREMISE: the actual cutter made separate native fragments")
        XCTAssertTrue(pieces.allSatisfy { $0.precise && $0.lattice?.precise == true },
                      "a cut inherits the precision of the nonlinear parent's shown lattice")
        let saved = try JSONEncoder().encode(VectorCanvasData(elements: pieces.map(VectorCanvasData.ElementData.stroke), transform: []))
        let read = try JSONDecoder().decode(VectorCanvasData.self, from: saved).strokes
        XCTAssertEqual(read.count, pieces.count)
        for piece in read {
            XCTAssertEqual(piece.lattice?.samples, original, "fractional parent geometry survives the real cut/save boundary")
            guard case .retained(_, let ancestor?, _)? = piece.placement?.source else { return XCTFail("a fragment retains its native ancestor") }
            XCTAssertEqual(ancestor.samples, original)
        }
    }

    func testFillCutCoverageKeepsItsStageWhenALaterFieldAndMoveAreAdded() throws {
        let first = operation(), second = operation()
        var fill = VectorFillElement(path: CGPath(rect: CGRect(x: 0, y: 0, width: 60, height: 40), transform: nil), color: color)
        fill.placement = FillPlacement(pathData: fill.pathData,
            material: InkMaterialProgram(bindings: [.init(operation: first, bridge: .identity)]))
        let canvas = VectorCanvas(size: CGSize(width: 80, height: 40), elements: [.fill(fill)])
        let loop = CGPath(rect: CGRect(x: 0, y: 0, width: 30, height: 40), transform: nil)
        let split = try XCTUnwrap(canvas.splitForLassoMove(insideLocalPath: loop))
        let pieces = split.elements.compactMap { element -> VectorFillElement? in
            guard case .fill(let value) = element else { return nil }; return value
        }
        XCTAssertEqual(pieces.count, 2)
        for piece in pieces {
            let originalClip = try XCTUnwrap(piece.placement?.coverage.first)
            XCTAssertEqual(originalClip.afterOperation, first.id)
            let clipPath = try XCTUnwrap(VectorFillElement.decodePath(originalClip.pathData))
            XCTAssertEqual(clipPath.boundingBoxOfPath, loop.boundingBoxOfPath,
                           "the selection mask is retained without multiplying the native fill boundary twice")
            XCTAssertEqual(piece.placement?.pathData, fill.pathData, "native coverage stays whole; each cut has its own chronological mask")
            guard case .fill(let reshaped) = VectorGeometryMap.liquified(.fill(piece), region: loop.boundingBoxOfPath,
                binding: .init(operation: second, bridge: .identity), by: { $0 }) else { return XCTFail("fill stays editable") }
            XCTAssertEqual(reshaped.placement?.coverage, [originalClip], "later spatial paint acts after the cut")
            let delta = CGAffineTransform(translationX: 10, y: 12)
            guard case .fill(let moved) = VectorCanvas.mapping(.fill(reshaped), throughStretch: delta) else { return XCTFail("Move retains cut coverage") }
            XCTAssertEqual(moved.placement?.coverage.first?.bridge, .homography(Homography(delta)))
            let data = try JSONEncoder().encode(moved)
            XCTAssertEqual(try JSONDecoder().decode(VectorFillElement.self, from: data).placement, moved.placement)
            var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var placement = try XCTUnwrap(archive["placement"] as? [String: Any])
            var coverage = try XCTUnwrap(placement["coverage"] as? [[String: Any]])
            var missingSide = coverage; missingSide[0].removeValue(forKey: "inverted")
            var missingPlacement = placement; missingPlacement["coverage"] = missingSide
            var missingArchive = archive; missingArchive["placement"] = missingPlacement
            XCTAssertThrowsError(try JSONDecoder().decode(VectorFillElement.self,
                from: JSONSerialization.data(withJSONObject: missingArchive)), "the current format must name which side of a cut survives")
            coverage[0]["afterOperation"] = UUID().uuidString
            placement["coverage"] = coverage; archive["placement"] = placement
            XCTAssertThrowsError(try JSONDecoder().decode(VectorFillElement.self, from: JSONSerialization.data(withJSONObject: archive)),
                                 "a cut cannot refer to absent material history")
        }
        XCTAssertEqual(Set(pieces.compactMap { $0.placement?.coverage.first?.inverted }), [true, false])
    }

    func testMaterialPreflightNeedsNoBrushContextAndCannotHideDanglingRefsBehindBadGeometry() throws {
        var archive = try archive(VectorCanvasData(elements: [.stroke(stroke(operation()))], transform: []))
        var slots = try XCTUnwrap(archive["elements"] as? [[String: Any]])
        var ink = try XCTUnwrap(slots[0]["stroke"] as? [String: Any])
        ink["brush"] = "not an ordinary brush reference"
        ink["color"] = "not a colour"; ink["samples"] = "not samples"
        slots[0]["stroke"] = ink; archive["elements"] = slots
        let validMaterial = try JSONSerialization.data(withJSONObject: archive)
        XCTAssertNoThrow(try JSONDecoder().decode(VectorCanvasData.MaterialMetadata.self, from: validMaterial),
                         "material metadata deliberately preserves the ordinary geometry damage policy")
        archive["materialOperations"] = []
        XCTAssertThrowsError(try JSONDecoder().decode(VectorCanvasData.MaterialMetadata.self,
            from: JSONSerialization.data(withJSONObject: archive))) { XCTAssertTrue($0 is InkMaterialCodingError) }
    }

    func testLinkedFillCutKeepsItsPaintedStageThroughLaterPushAndMove() throws {
        let size = CGSize(width: 144, height: 128)
        let source = VectorFillElement(path: CGPath(rect: CGRect(x: 0, y: 0, width: 128, height: 128), transform: nil), color: color)
        func push(_ start: CGFloat, _ end: CGFloat) -> LiquifyField {
            LiquifyField(LiquifyDeformation(brush: TestBrushes.hardRound, size: 48, power: 0.8,
                mode: .push, seed: 4, samples: StrokeSamples(points: [CGPoint(x: start, y: 64), CGPoint(x: end, y: 64)])))
        }
        let first = push(48, 64), second = push(64, 80)
        guard case .fill(let firstInk) = first.mapping([.fill(source)])[0] else { return XCTFail("native fill stays editable") }
        let cut = CGPath(rect: CGRect(x: 0, y: 0, width: 64, height: 128), transform: nil)
        let retained = firstInk.clipped(to: cut)
        guard case .fill(let laterInk) = second.mapping([.fill(retained)])[0] else { return XCTFail("cut fill stays editable") }
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 64)
        var current = rest; current.vertices[4] = CGPoint(x: 72, y: 60)
        let transport = InkMaterialBridge.lattice(captured: rest, current: current, pose: .identity)
        let shift = CGAffineTransform(translationX: 8, y: 0)
        func linkedAndMoved(_ fill: VectorFillElement) -> VectorElement {
            var linked = VectorGeometryMap.fill(fill, mapPaint: false) { transport.map($0)! }
            linked.placement = linked.placement?.transported(by: transport)
            return VectorCanvas.mapping(.fill(linked), throughStretch: shift)
        }
        let picture = VectorCanvas(size: size, elements: [linkedAndMoved(laterInk)]).render()
        let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(picture.cgImage)))
        guard case .fill(let uncutInk) = second.mapping([.fill(firstInk)])[0] else { return XCTFail("uncut control stays editable") }
        let uncut = VectorCanvas(size: size, elements: [linkedAndMoved(uncutInk)]).render()
        let uncutPixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(uncut.cgImage)))
        for (point, survives) in [(CGPoint(x: 60, y: 64), true), (CGPoint(x: 68, y: 64), false)] {
            let pushed = second.map(point)
            let shown = try XCTUnwrap(transport.map([pushed])?.first).applying(shift)
            let alpha = pixels[(Int(shown.y) * 144 + Int(shown.x)) * 4 + 3]
            XCTAssertGreaterThan(uncutPixels[(Int(shown.y) * 144 + Int(shown.x)) * 4 + 3], 240,
                                 "PREMISE: both retained and discarded witnesses contain actual uncut native paint")
            if survives {
                XCTAssertGreaterThan(pushed.x, 68, "PREMISE: later Push carries retained paint beyond the cut's old boundary")
                XCTAssertGreaterThan(alpha, 240, "the later Push and linked geometry carry the half retained at the cut stage")
            } else {
                XCTAssertEqual(alpha, 0, "later operations and Move cannot restore the half discarded after the first Push")
            }
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = "linked-fill-cut-later-push-move"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testMaterialPreflightPreservesUnknownAndMalformedNonmaterialSlots() throws {
        let archive: [String: Any] = ["materialOperations": [], "elements": [
            ["kind": "future-kind", "stroke": "future payload"],
            ["kind": "stroke", "stroke": ["placement": NSNull(), "brush": "malformed"]],
            ["kind": "fill", "fill": ["placement": NSNull(), "color": "malformed"]],
            ["kind": "stroke", "stroke": 12], 42
        ]]
        XCTAssertNoThrow(try JSONDecoder().decode(VectorCanvasData.MaterialMetadata.self,
            from: JSONSerialization.data(withJSONObject: archive)))
    }

    func testNativePatternSelectionMovesInteriorAndKeepsEveryExteriorByte() throws {
        var brush = BrushLibrary.streaky; brush.modulations = BrushModulations()
        let ink = VectorStroke(brush: brush, color: color, size: 64, opacity: 1,
            samples: StrokeSamples(points: [CGPoint(x: 10, y: 64), CGPoint(x: 118, y: 64)]), seed: 19)
        let selection = CGPath(rect: CGRect(x: 64, y: 0, width: 64, height: 128), transform: nil)
        let gesture = LiquifyDeformation(brush: TestBrushes.hardRound, size: 70, power: 1,
            mode: .push, seed: 41, samples: StrokeSamples(points: [CGPoint(x: 72, y: 64), CGPoint(x: 90, y: 86)]), selection: selection)
        let moved = LiquifyField(gesture).mapping([.stroke(ink)])
        let size = CGSize(width: 128, height: 128)
        let images = [VectorCanvas(size: size, elements: [.stroke(ink)]).render(), VectorCanvas(size: size, elements: moved).render()]
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[0].cgImage)))
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[1].cgImage)))
        var interior = 0, exterior = 0
        for y in 0..<128 { for x in 0..<128 {
            let i = (y * 128 + x) * 4
            if before[i..<i + 4] != after[i..<i + 4] {
                if x < 64 { exterior += 1 } else { interior += 1 }
            }
        } }
        XCTAssertGreaterThan(interior, 100, "the production native-material path must visibly reshape selected texture")
        XCTAssertEqual(exterior, 0, "wide stamps crossing the selection keep every outside premultiplied pixel fixed")
        for (index, image) in images.enumerated() {
            let paper = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)); image.draw(at: .zero)
                context.cgContext.setStrokeColor(UIColor.blue.cgColor); context.cgContext.setLineWidth(1)
                context.cgContext.move(to: CGPoint(x: 64, y: 0)); context.cgContext.addLine(to: CGPoint(x: 64, y: 128)); context.cgContext.strokePath()
            }
            let attachment = XCTAttachment(image: paper); attachment.name = "liquify-B-native-pattern-" + (index == 0 ? "before" : "after")
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testFillInteriorMaterialMovesWithoutMovingBoundaryOrOutsidePaint() throws {
        let size = CGSize(width: 128, height: 128)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
            paint: .linearGradient(LinearGradientPaint(start: color, end: CodableColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1),
                from: .zero, to: CGPoint(x: 128, y: 0))))
        let gesture = LiquifyDeformation(brush: TestBrushes.hardRound, size: 40, power: 1, mode: .expand,
            seed: 31, samples: StrokeSamples(points: [CGPoint(x: 64, y: 64)]))
        let field = LiquifyField(gesture)
        let mapped = field.mapping([.fill(fill)])
        guard case .fill(let deformed) = mapped[0] else { return XCTFail("editable fill") }
        XCTAssertEqual(deformed.pathData, fill.pathData, "PREMISE: only interior paint, not a path point, is under the brush")
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(VectorCanvas(size: size, elements: [.fill(fill)]).render().cgImage)))
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(VectorCanvas(size: size, elements: mapped).render().cgImage)))
        var inside = 0, outside = 0
        for y in 0..<128 { for x in 0..<128 {
            let i = (y * 128 + x) * 4
            if before[i..<i + 4] != after[i..<i + 4] {
                if field.replacementBounds.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) { inside += 1 }
                else { outside += 1 }
            }
        } }
        XCTAssertGreaterThan(inside, 30, "an enclosing gradient's stationary boundary cannot suppress its material deformation")
        XCTAssertEqual(outside, 0)
    }

    func testOneHundredStrokesShareOneExactInverseCoordinateTile() throws {
        let shared = operation(), size = CGSize(width: 64, height: 64)
        func work(_ count: Int) -> [InkMaterialRenderProbe.Sample] {
            let elements = (0..<count).map { _ in VectorElement.stroke(stroke(shared)) }
            InkMaterialRenderProbe.begin()
            _ = VectorCanvas(size: size, elements: elements).render()
            return InkMaterialRenderProbe.end()
        }
        let single = work(1), many = work(100)
        XCTAssertEqual(single.count, 1); XCTAssertEqual(many.count, 1)
        XCTAssertTrue(single.allSatisfy(\.completed)); XCTAssertTrue(many.allSatisfy(\.completed))
        let one = single.reduce(0) { $0 + $1.evaluations }, hundred = many.reduce(0) { $0 + $1.evaluations }
        XCTAssertGreaterThan(one, 0, "PREMISE: this tile actually reversed a nonempty brush field")
        XCTAssertEqual(hundred, one, "the costly solver runs once per operation/transport/tile, not once per stroke")
        XCTAssertEqual(many.reduce(0) { $0 + $1.fields }, 1)
        XCTAssertEqual(many.reduce(0) { $0 + $1.hits }, 99)
        XCTAssertTrue(many.allSatisfy { $0.peakBytes <= InkMaterialRenderer.byteBudget + $0.peakFieldBytes })
        print("LIQUIFY MATERIAL TILE one=\(one) hundred=\(hundred) fields=\(many.map(\.fields)) hits=\(many.map(\.hits)) peak=\(many.map(\.peakBytes))")
    }

    func testFractionalVisibleWindowMatchesFullNativePictureWithOnlyVisibleInversePoints() throws {
        let size = CGSize(width: 320, height: 320)
        let frame = CGRect(origin: .zero, size: size)
        let clip = CGRect(x: 151.25, y: 153.5, width: 153, height: 111)
        var brush = TestBrushes.hardRound
        brush.texture = BrushTextureSettings(mask: .builtIn(.canvasWeave), tileSize: 37)
        let source = VectorStroke(brush: brush, color: color, size: 96, opacity: 0.37,
            samples: StrokeSamples(points: [CGPoint(x: 160, y: 240), CGPoint(x: 240, y: 240), CGPoint(x: 300, y: 240)]), seed: 8)
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 160)
        var current = rest; current.vertices[4] = CGPoint(x: 176, y: 154)
        let transport = InkMaterialBridge.lattice(captured: rest, current: current, pose: .identity)
        let operation = InkMaterialOperation(LiquifyDeformation(brush: TestBrushes.hardRound, size: 180,
            power: 0.8, mode: .push, seed: 4,
            samples: StrokeSamples(points: [CGPoint(x: 224, y: 224), CGPoint(x: 240, y: 240)])))
        var material = VectorGeometryMap.stroke(source) { transport.map($0)! }
        material.placement = StrokePlacement(map: .identity, restSize: source.size,
            source: .retained(samples: source.samples, lattice: nil, precise: true),
            material: InkMaterialProgram(bindings: [.init(operation: operation, bridge: .identity)]), transport: transport)
        let frozen = VectorCanvas(size: size, elements: [.stroke(material)]).freeze(quality: .full)
        for scale in [CGFloat(1), 1.5] {
            let format = PixelOps.transparentFormat(scale: scale); format.preferredRange = .standard
            func render(clipped: Bool) -> (UIImage, [InkMaterialRenderProbe.Sample]) {
                InkMaterialRenderProbe.begin()
                let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    if clipped { context.cgContext.clip(to: clip) }
                    XCTAssertNotNil(frozen.draw(into: context.cgContext, frameRect: frame, quality: .full))
                }
                return (image, InkMaterialRenderProbe.end())
            }
            let (full, fullWork) = render(clipped: false)
            let expected = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.clip(to: clip); full.draw(at: .zero)
            }
            let (actual, work) = render(clipped: true)
            let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(expected.cgImage)))
            let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(actual.cgImage)))
            XCTAssertGreaterThan(stride(from: 3, to: b.count, by: 4).filter { b[$0] > 0 && b[$0] < 255 }.count, 100,
                                 "PREMISE: the fractional clip contains visible paper and translucent linked ink")
            XCTAssertEqual(zip(a, b).filter { $0 != $1 }.count, 0,
                           "a fractional window across tile seams must preserve every full-render RGBA byte at scale \(scale)")
            XCTAssertTrue((fullWork + work).allSatisfy { $0.completed && $0.peakBytes <= InkMaterialRenderer.byteBudget + $0.peakFieldBytes })
            XCTAssertGreaterThan(work.reduce(0) { $0 + $1.evaluations }, 0,
                                 "PREMISE: the clipped picture actually runs the spatial inverse")
            let expectedPoints = Int((ceil(clip.maxX * scale) - floor(clip.minX * scale)) *
                                     (ceil(clip.maxY * scale) - floor(clip.minY * scale)))
            let fullPoints = fullWork.reduce(0) { $0 + $1.coordinatePoints }
            let clippedPoints = work.reduce(0) { $0 + $1.coordinatePoints }
            XCTAssertEqual(fullPoints, Int(size.width * scale) * Int(size.height * scale))
            XCTAssertEqual(clippedPoints, expectedPoints,
                           "only pixel centres in the outward-rounded visible window enter the inverse")
            print("MATERIAL VISIBLE WINDOW scale=\(scale) full=\(fullPoints) clipped=\(clippedPoints) evaluations=\(work.reduce(0) { $0 + $1.evaluations }) sourceTiles=\(work.reduce(0) { $0 + $1.sourceTiles })")
            let attachment = XCTAttachment(image: actual)
            attachment.name = "material-fractional-window-\(scale)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testScratchWholeStrokePreviewUsesNativeMaterialAtANonzeroWindowOrigin() throws {
        let size = CGSize(width: 512, height: 384)
        var native = stroke(operation()); native.brush = BrushLibrary.streaky; native.opacity = 1
        guard case .stroke(let moved) = VectorCanvas.mapping(.stroke(native),
            throughStretch: CGAffineTransform(translationX: 300, y: 200)) else { return XCTFail("Move retains stroke") }
        let paper = VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
            color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1))
        let before = VectorCanvas(size: size, elements: [.fill(paper), .stroke(moved)]).render()
        var erase = moved; erase.composite = .erase
        let expected = VectorCanvas(size: size, elements: [.fill(paper), .stroke(moved), .stroke(erase)]).render()
        let scratch = StrokeScratch(canvasSize: size, role: .replacing(backdrop: before))
        VectorCanvas.applyPreview(erasing: moved, into: scratch)
        XCTAssertTrue(scratch.completed)
        XCTAssertGreaterThan(scratch.windowRect.minX, 0, "PREMISE: this preview actually translates into a bounded window")
        let patch = try XCTUnwrap(scratch.image)
        let preview = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            before.draw(at: .zero); patch.draw(at: scratch.windowRect.origin, blendMode: .copy, alpha: 1)
        }
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(preview.cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(expected.cgImage)))
        XCTAssertEqual(zip(a, b).filter { $0 != $1 }.count, 0,
                       "scratch erase must replay the same native texture, field and shifted coordinates as the committed CGContext walk")
    }

    func testScratchRefusesAnOverBudgetMaterialGroupWithoutCommittingPartialPixels() throws {
        let size = CGSize(width: 128, height: 128)
        var ink = stroke(operation())
        let rest = Lattice(cols: 64, rows: 64, restOrigin: .zero, restCellSize: 1)
        var stretched = rest
        for row in 0...64 { for col in 0...64 {
            stretched.vertices[row * 65 + col] = CGPoint(x: col.isMultiple(of: 2) ? -1000 : 1000,
                                                        y: row.isMultiple(of: 2) ? -1000 : 1000)
        } }
        // Every one of 4096 cells crosses every one of 4096 bins: 16,777,216 index
        // entries, before capacity headroom. This is a counted allocation refusal, not a timer.
        XCTAssertGreaterThan(DeformedCellIndex.storageByteUpperBound(lattice: stretched), InkMaterialRenderer.byteBudget)
        ink.placement?.transport = .lattice(captured: rest, current: stretched, pose: .identity)
        XCTAssertTrue(VectorCanvas.materialBounds(of: ink).isInfinite,
                      "refused native geometry is an unknown footprint, never empty ink that can be culled")
        let paper = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        let scratch = StrokeScratch(canvasSize: size, role: .subtractive(backdrop: paper))
        BrushStamper.stampStroke(into: scratch, samples: StrokeSamples(points: [CGPoint(x: 70, y: 70)]),
            brush: TestBrushes.hardRound, color: .black, brushSize: 20, brushOpacity: 1,
            isEraser: false, random: DabRandom(seed: 8))
        let shownBeforeFailure = try XCTUnwrap(scratch.image)
        VectorCanvas.applyPreview(erasing: ink, into: scratch)
        XCTAssertFalse(scratch.completed, "the lattice index must reserve within the tile budget before allocating")
        XCTAssertNil(scratch.image, "a refused group cannot expose its partial window as a successful preview")
        XCTAssertNotNil(shownBeforeFailure.cgImage, "the caller already owns a valid picture to keep when the next preview fails")
        let destination = RasterLayerTexture(size: size, image: paper)
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(destination.renderToUIImage().cgImage)))
        scratch.commit(into: destination)
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(destination.renderToUIImage().cgImage)))
        XCTAssertEqual(zip(after, before).filter { $0 != $1 }.count, 0,
                       "a refused scratch cannot write its earlier partial coverage at lift")
        let frozen = VectorCanvas(size: size, elements: [.stroke(ink)]).freeze(quality: .full)
        var completion: Int?
        _ = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            completion = frozen.draw(into: context.cgContext, frameRect: CGRect(origin: .zero, size: size), quality: .full)
        }
        XCTAssertNil(completion, "Frozen draw must propagate the same budget refusal to its window caller")
    }

    func testPreparedNativeGeometryRemainsCountedByItsPainterAndPreviewDestination() throws {
        let size = CGSize(width: 64, height: 64)
        let bounds = CGRect(origin: .zero, size: size)
        for separateDestination in [false, true] {
            let owner = InkMaterialRenderer(window: bounds, scale: 1)
            let prepared = try XCTUnwrap(owner.prepareGeometry(transport: .identity, pointCount: 100_000) {
                [CGPoint](repeating: CGPoint(x: 32, y: 32), count: 100_000)
            })
            let painter = separateDestination ? InkMaterialRenderer(window: bounds, scale: 1) : owner
            let image = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
                painter.draw(into: context.cgContext, nativeBounds: bounds,
                    program: InkMaterialProgram(bindings: [.init(operation: operation(), bridge: .identity)]),
                    transport: .identity, geometry: prepared.reservation, blendMode: .normal) { native, _ in
                        native.setFillColor(UIColor.red.cgColor)
                        for point in prepared.value { native.fill(CGRect(x: point.x, y: point.y, width: 1, height: 1)) }
                    }
            }
            XCTAssertFalse(painter.completed,
                           "live mapped samples and inverse arrays share one cap, including a later preview destination")
            let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(image.cgImage)))
            XCTAssertFalse(bytes.contains { $0 != 0 }, "refusal happens before exposing any partial native picture")
        }
    }

    func testChronologicalFillCutKeepsNativeAntialiasedCoverage() throws {
        let size = CGSize(width: 64, height: 64)
        let definition = LiquifyDeformation(brush: TestBrushes.hardRound, size: 20, power: 1,
            mode: .push, seed: 41, samples: StrokeSamples(points: [CGPoint(x: 300, y: 300), CGPoint(x: 310, y: 310)]))
        let material = InkMaterialProgram(bindings: [.init(operation: InkMaterialOperation(definition), bridge: .identity)])
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var fill = VectorFillElement(path: path, color: color)
        fill.placement = FillPlacement(pathData: fill.pathData, material: material)
        let mask = CGPath(ellipseIn: CGRect(x: 9.3, y: 8.7, width: 43.2, height: 47.9), transform: nil)
        let fragment = fill.clipped(to: mask)
        var plain = fill.reshaped(to: mask); plain.placement = nil
        let actual = VectorCanvas(size: size, elements: [.fill(fragment)]).render()
        let expected = VectorCanvas(size: size, elements: [.fill(plain)]).render()
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(actual.cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(expected.cgImage)))
        XCTAssertGreaterThan(stride(from: 3, to: b.count, by: 4).filter { b[$0] > 0 && b[$0] < 255 }.count, 20,
                             "PREMISE: the cut has real partial edge coverage")
        XCTAssertLessThanOrEqual(zip(a, b).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0, 1,
                                 "a chronological cut must preserve antialiased coverage, not center-point containment")
        for (name, image) in [("actual", actual), ("expected", expected)] {
            let attachment = XCTAttachment(image: image); attachment.name = "material-fill-cut-" + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        let outsidePath = path.subtracting(mask)
        let outside = fill.clipped(to: outsidePath, mask: mask, inverted: true)
        var plainOutside = fill.reshaped(to: outsidePath); plainOutside.placement = nil
        let outsideActual = VectorCanvas(size: size, elements: [.fill(outside)]).render()
        let outsideExpected = VectorCanvas(size: size, elements: [.fill(plainOutside)]).render()
        let c = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(outsideActual.cgImage)))
        let d = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(outsideExpected.cgImage)))
        XCTAssertLessThanOrEqual(zip(c, d).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0, 1,
                                 "the outside fragment retains complementary partial coverage, not the inside mask")
    }

    func testExteriorMaterialInkStillAnswersTapOutlineAndWholeStrokeEraser() throws {
        let size = CGSize(width: 128, height: 160)
        let original = VectorStroke(brush: TestBrushes.hardRound, color: color, size: 80, opacity: 1,
            samples: StrokeSamples(points: [CGPoint(x: 88, y: 40)]), seed: 9)
        let selection = CGPath(rect: CGRect(x: 64, y: 0, width: 64, height: 128), transform: nil)
        let gesture = LiquifyDeformation(brush: TestBrushes.hardRound, size: 120, power: 1,
            mode: .push, seed: 14, samples: StrokeSamples(points: [CGPoint(x: 88, y: 40), CGPoint(x: 88, y: 200)]),
            selection: selection)
        let moved = LiquifyField(gesture).mapping([.stroke(original)])
        let ink = try XCTUnwrap(moved.first?.stroke)
        let point = CGPoint(x: 62.5, y: 11.5)
        let radius = StrokeGeometry.stampRadius(forPressure: 1, brush: ink.brush, size: ink.size)
        XCTAssertGreaterThan(StrokeGeometry.distanceSquared(from: point, toPolyline: ink.samples), radius * radius,
                             "PREMISE: the moved spine no longer accounts for this exterior ink")
        let canvas = VectorCanvas(size: size, elements: moved)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(canvas.render().cgImage)))
        XCTAssertGreaterThan(bytes[(11 * 128 + 62) * 4 + 3], 240,
                             "PREMISE: the actual renderer keeps opaque paint outside the selection")
        let empty = CGPoint(x: 50.5, y: 2.5)
        XCTAssertEqual(bytes[(2 * 128 + 50) * 4 + 3], 0, "PREMISE: loose material bounds also enclose bare canvas")
        XCTAssertNil(canvas.topmostStroke(atCanvasPoint: empty, slop: 0))
        XCTAssertFalse(canvas.erase(alongPath: StrokeSamples(points: [empty]), brush: TestBrushes.hardRound,
                                    size: 2, mode: .wholeStroke), "bounds overlap alone cannot delete a stroke")
        XCTAssertEqual(canvas.topmostStroke(atCanvasPoint: point, slop: 0)?.id, ink.id,
                       "tap/retag must answer the paint that is still visible")
        XCTAssertTrue(try XCTUnwrap(VectorHitTest.outline(of: .stroke(ink))).contains(point),
                      "the tap outline must contain retained exterior material")
        XCTAssertTrue(canvas.erase(alongPath: StrokeSamples(points: [point]), brush: TestBrushes.hardRound,
                                   size: 2, mode: .wholeStroke),
                      "whole-stroke erasing must consider retained material beyond the moved spine")
        XCTAssertFalse(canvas.elements.contains { $0.id == ink.id })
    }

    func testLinkedNativeTransportKeepsCanvasPaperOutsideTheSpatialOperation() throws {
        let size = CGSize(width: 128, height: 128)
        var brush = TestBrushes.hardRound
        brush.texture = BrushTextureSettings(mask: .builtIn(.canvasWeave), tileSize: 37)
        let native = StrokeSamples(points: [CGPoint(x: 64, y: 64)])
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 64)
        var current = rest; current.vertices[4] = CGPoint(x: 86, y: 50)
        let transport = InkMaterialBridge.lattice(captured: rest, current: current, pose: .identity)
        let remote = InkMaterialOperation(LiquifyDeformation(brush: TestBrushes.hardRound, size: 20,
            power: 1, mode: .expand, seed: 3, samples: StrokeSamples(points: [CGPoint(x: 1000, y: 1000)])))
        let source = VectorStroke(brush: brush, color: color, size: 400, opacity: 1, samples: native, seed: 8)
        var material = source
        material.samples = StrokeSamples(points: [CGPoint(x: 86, y: 50)])
        material.placement = StrokePlacement(map: .identity, restSize: 400,
            source: .retained(samples: native, lattice: nil, precise: true),
            material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: remote, bridge: .identity)]), transport: transport)
        var control = material; control.placement = nil
        InkMaterialRenderProbe.begin()
        let images = [VectorCanvas(size: size, elements: [.stroke(control)]).render(),
                      VectorCanvas(size: size, elements: [.stroke(material)]).render()]
        let work = InkMaterialRenderProbe.end()
        XCTAssertFalse(work.isEmpty, "PREMISE: the production material window was rendered")
        XCTAssertTrue(work.allSatisfy(\.completed))
        XCTAssertTrue(work.allSatisfy { $0.peakBytes <= InkMaterialRenderer.byteBudget + $0.peakFieldBytes },
                      "transported paper buffers and provider lifetimes remain within the existing payload cap")
        print("NATIVE TRANSPORTED PAPER PEAK BYTES \(work.map(\.peakBytes).max() ?? 0)")
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[0].cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[1].cgImage)))
        var differing = 0, paperRange: Set<UInt8> = []
        for y in 40..<88 { for x in 40..<88 {
            let i = (y * 128 + x) * 4
            paperRange.insert(a[i + 3])
            if a[i..<i + 4] != b[i..<i + 4] { differing += 1 }
        } }
        XCTAssertGreaterThan(paperRange.count, 10, "PREMISE: native opaque coverage exposes the canvas paper")
        for channel in 0..<4 {
            var histogram: [Int: Int] = [:]
            for y in 40..<88 { for x in 40..<88 {
                let i = (y * 128 + x) * 4 + channel
                histogram[Int(b[i]) - Int(a[i]), default: 0] += 1
            } }
            print("NATIVE PAPER CHANNEL \(channel) \(histogram)")
        }
        for (name, bytes) in [("control", a), ("transported", b)] {
            let attachment = XCTAttachment(data: Data(bytes), uniformTypeIdentifier: "public.data")
            attachment.name = "linked-paper-direct-rgba-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(differing, 0, "linked geometry transport must not drag canvas paper outside a Liquify operation")
        for (index, image) in images.enumerated() {
            let attachment = XCTAttachment(image: image)
            attachment.name = "linked-material-paper-" + (index == 0 ? "canvas-control" : "transported")
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testFiniteTransportOverflowRefusesBeforeIntegerSampling() throws {
        let bridge = InkMaterialBridge.homography(.scale(x: 1e18, y: 1))
        XCTAssertNil(bridge.map([CGPoint(x: 16, y: 4)]),
                     "a finite map beyond the supported sampling range cannot reach Int(floor(source))")
        let bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 128, space: PixelOps.deviceRGBColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let unsupported: [(CGFloat, CGFloat)] = [(1e19, 1), (1e10, 1e10)]
        for (translation, scale) in unsupported {
            let renderer = InkMaterialRenderer(window: bounds, scale: scale)
            renderer.draw(into: context, nativeBounds: bounds, program: InkMaterialProgram(bindings: []),
                transport: .homography(.translation(x: translation, y: 0)), blendMode: .normal) { cg, _ in
                    cg.setFillColor(UIColor.red.cgColor); cg.fill(bounds)
                }
            XCTAssertFalse(renderer.completed,
                           "unsupported source texels must refuse the picture, not succeed with transparent missing paint")
        }
    }

    func testFractionalGradientOpacityKeepsEveryExteriorPixel() throws {
        let size = CGSize(width: 96, height: 96)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
            paint: .linearGradient(LinearGradientPaint(start: color,
                end: CodableColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 0.4),
                from: .zero, to: CGPoint(x: 96, y: 0))), opacity: 0.37)
        let field = LiquifyField(LiquifyDeformation(brush: TestBrushes.hardRound, size: 30,
            power: 1, mode: .expand, seed: 11, samples: StrokeSamples(points: [CGPoint(x: 48, y: 48)])))
        let before = VectorCanvas(size: size, elements: [.fill(fill)]).render()
        let after = VectorCanvas(size: size, elements: field.mapping([.fill(fill)])).render()
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(before.cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(after.cgImage)))
        var outside = 0, inside = 0
        for y in 0..<96 { for x in 0..<96 {
            let i = (y * 96 + x) * 4
            guard a[i..<i + 4] != b[i..<i + 4] else { continue }
            if field.replacementBounds.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) { inside += 1 }
            else { outside += 1 }
        } }
        XCTAssertGreaterThan(inside, 10, "PREMISE: selected gradient paint changes at fractional opacity")
        XCTAssertEqual(outside, 0, "an extra offscreen group cannot re-quantize paint outside the spatial edit")
    }

    func testTransportedFractionalPaperKeepsExteriorPixelsAcrossTheTileSeam() throws {
        let size = CGSize(width: 512, height: 128)
        var brush = TestBrushes.hardRound
        brush.tip = .stamp(.builtIn(.squareBevelWide)); brush.dab.flow = 0.47
        brush.texture = BrushTextureSettings(mask: .builtIn(.canvasWeave), tileSize: 37)
        let tint = CodableColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 0.63)
        let native = StrokeSamples(points: [CGPoint(x: 40, y: 64), CGPoint(x: 440, y: 64)])
        let selection = CGPath(rect: CGRect(x: 256, y: 0, width: 256, height: 128), transform: nil)
        let operation = InkMaterialOperation(LiquifyDeformation(brush: TestBrushes.hardRound,
            size: 80, power: 0.8, mode: .push, seed: 4,
            samples: StrokeSamples(points: [CGPoint(x: 272, y: 64), CGPoint(x: 304, y: 76)]), selection: selection))
        for textured in [false, true] { for opacity in [1.0, 0.37] {
        var fixtureBrush = brush
        if !textured { fixtureBrush.texture = nil }
        let source = VectorStroke(brush: fixtureBrush, color: tint, size: 64, opacity: opacity, samples: native, seed: 8)
        var material = source
        material.samples = StrokeSamples(points: native.map { CGPoint(x: $0.point.x + 8, y: $0.point.y) })
        material.placement = StrokePlacement(map: .identity, restSize: 64,
            source: .retained(samples: native, lattice: nil, precise: true),
            material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operation, bridge: .identity)]),
            transport: .homography(.translation(x: 8, y: 0)))
        var control = material; control.placement = nil
        let images = [VectorCanvas(size: size, elements: [.stroke(control)]).render(),
                      VectorCanvas(size: size, elements: [.stroke(material)]).render()]
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[0].cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[1].cgImage)))
        var exterior = 0, interior = 0, seamInk = 0
        for y in 0..<128 { for x in 0..<512 {
            let i = (y * 512 + x) * 4
            if (252..<260).contains(x), a[i + 3] > 0 { seamInk += 1 }
            guard a[i..<i + 4] != b[i..<i + 4] else { continue }
            if selection.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) { interior += 1 }
            else { exterior += 1 }
        } }
        XCTAssertGreaterThan(seamInk, 100, "PREMISE: fractional paper ink crosses the native source-tile seam")
        XCTAssertGreaterThan(interior, 100, "PREMISE: the selected Push changes drawn ink")
        print("FRACTIONAL SEAM textured=\(textured) opacity=\(opacity) exterior=\(exterior) interior=\(interior)")
        XCTAssertEqual(exterior, 0, "tip, colour and group alpha must keep every unselected native pixel; textured=\(textured) opacity=\(opacity)")
        if textured, opacity < 1 {
            var boundaryInk = material
            boundaryInk.opacity = 0.005
            boundaryInk.brush.tip = .round; boundaryInk.brush.dab.hardness = 0.15
            let boundaryCanvas = VectorCanvas(size: size, elements: [.stroke(boundaryInk)])
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(boundaryCanvas.render().cgImage)))
            var boundary: [CGPoint] = []
            for y in 1..<127 { for x in 248..<256 where pixels[(y * 512 + x) * 4 + 3] == 1 {
                if boundary.count < 4 { boundary.append(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) }
            } }
            XCTAssertEqual(boundary.count, 4, "PREMISE: a nonempty one-byte alpha boundary crosses the seam")
            for point in boundary {
                XCTAssertEqual(boundaryCanvas.topmostStroke(atCanvasPoint: point, slop: 0)?.id, boundaryInk.id,
                               "the artist can tap visible one-byte ink at \(point)")
            }
            let empty = CGPoint(x: 248.5, y: 0.5)
            XCTAssertEqual(pixels[248 * 4 + 3], 0, "PREMISE: the negative probe is actually blank")
            XCTAssertNil(boundaryCanvas.topmostStroke(atCanvasPoint: empty, slop: 0))
        }
        for (name, image) in zip(["control", "transported"], images) {
            let attachment = XCTAttachment(image: image)
            attachment.name = "fractional-paper-seam-\(textured)-\(opacity)-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
        } }
    }

    func testLinkedGeometryAndActiveSpatialPaperKeepEveryExteriorNativePixel() throws {
        let size = CGSize(width: 256, height: 256)
        var brush = TestBrushes.hardRound
        brush.texture = BrushTextureSettings(mask: .builtIn(.canvasWeave), tileSize: 37)
        let source = VectorStroke(brush: brush, color: color, size: 64, opacity: 0.37,
            samples: StrokeSamples(points: [CGPoint(x: 40, y: 128), CGPoint(x: 128, y: 128), CGPoint(x: 216, y: 128)]), seed: 8)
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 128)
        var current = rest; current.vertices[4] = CGPoint(x: 148, y: 114)
        let transport = InkMaterialBridge.lattice(captured: rest, current: current, pose: .identity)
        let control = VectorGeometryMap.stroke(source) { transport.map($0)! }
        let selection = CGPath(rect: CGRect(x: 128, y: 0, width: 128, height: 256), transform: nil)
        let deformation = LiquifyDeformation(brush: TestBrushes.hardRound, size: 80, power: 0.8,
            mode: .push, seed: 4, samples: StrokeSamples(points: [CGPoint(x: 144, y: 120), CGPoint(x: 168, y: 144)]),
            selection: selection)
        let operation = InkMaterialOperation(deformation)
        var material = try XCTUnwrap(LiquifyField(deformation).mapping([.stroke(control)]).first?.stroke)
        material.placement = StrokePlacement(map: .identity, restSize: source.size,
            source: .retained(samples: source.samples, lattice: nil, precise: true),
            material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operation, bridge: .identity)]), transport: transport)
        InkMaterialRenderProbe.begin()
        let images = [VectorCanvas(size: size, elements: [.stroke(control)]).render(),
                      VectorCanvas(size: size, elements: [.stroke(material)]).render()]
        let work = InkMaterialRenderProbe.end()
        XCTAssertGreaterThan(work.reduce(0) { $0 + $1.evaluations }, 0, "PREMISE: nonlinear geometry and the active spatial inverse both run")
        XCTAssertTrue(work.allSatisfy { $0.completed && $0.peakBytes <= InkMaterialRenderer.byteBudget + $0.peakFieldBytes })
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[0].cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[1].cgImage)))
        var outside = 0, inside = 0
        for y in 0..<256 { for x in 0..<256 {
            let i = (y * 256 + x) * 4
            guard a[i..<i + 4] != b[i..<i + 4] else { continue }
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
            if selection.contains(point), operation.supportBounds.contains(point) { inside += 1 }
            else { outside += 1 }
        } }
        XCTAssertGreaterThan(inside, 100, "PREMISE: the selected Push visibly changes linked native ink")
        XCTAssertEqual(outside, 0, "geometry, paper and group alpha retain ordinary native pixels outside the spatial operation")
        for (name, image) in zip(["control", "liquified"], images) {
            let attachment = XCTAttachment(image: image)
            attachment.name = "linked-active-paper-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testLinkedGradientFillKeepsEveryExteriorNativePixel() throws {
        let size = CGSize(width: 256, height: 256)
        let source = VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 240, height: 240), transform: nil),
            paint: .linearGradient(LinearGradientPaint(start: color,
                end: CodableColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 0.4),
                from: CGPoint(x: 16, y: 80), to: CGPoint(x: 208, y: 144))), opacity: 0.37)
        let rest = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 128)
        var current = rest; current.vertices[4] = CGPoint(x: 148, y: 114)
        let transport = InkMaterialBridge.lattice(captured: rest, current: current, pose: .identity)
        let control = VectorGeometryMap.fill(source) { transport.map($0)! }
        let selection = CGPath(rect: CGRect(x: 128, y: 0, width: 128, height: 256), transform: nil)
        let deformation = LiquifyDeformation(brush: TestBrushes.hardRound, size: 80, power: 0.8,
            mode: .push, seed: 4, samples: StrokeSamples(points: [CGPoint(x: 144, y: 120), CGPoint(x: 168, y: 144)]),
            selection: selection)
        let operation = InkMaterialOperation(deformation)
        var material = VectorGeometryMap.fill(source, mapPaint: false) { transport.map($0)! }
        material.placement = FillPlacement(pathData: source.pathData,
            material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operation, bridge: .identity)]),
            transport: transport)
        let images = [VectorCanvas(size: size, elements: [.fill(control)]).render(),
                      VectorCanvas(size: size, elements: [.fill(material)]).render()]
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[0].cgImage)))
        let b = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(images[1].cgImage)))
        var outside = 0, inside = 0
        for y in 0..<256 { for x in 0..<256 {
            let i = (y * 256 + x) * 4
            guard a[i..<i + 4] != b[i..<i + 4] else { continue }
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
            if selection.contains(point), operation.supportBounds.contains(point) { inside += 1 }
            else { outside += 1 }
        } }
        XCTAssertGreaterThan(inside, 100, "PREMISE: the selected Push changes the linked gradient interior")
        XCTAssertEqual(outside, 0, "ordinary linked gradient geometry and native dither stay fixed outside the spatial operation")
        for (name, image) in zip(["control", "liquified"], images) {
            let attachment = XCTAttachment(image: image)
            attachment.name = "linked-active-gradient-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testWarmDistantMaterialWholeEraseDoesNotWalkNativeInk() throws {
        let remote = InkMaterialOperation(LiquifyDeformation(brush: TestBrushes.hardRound, size: 20,
            power: 1, mode: .expand, seed: 1, samples: StrokeSamples(points: [CGPoint(x: 1000, y: 1000)])))
        let strokes = (0..<100).map { _ -> VectorElement in
            var ink = stroke(remote)
            ink.samples = StrokeSamples(points: [CGPoint(x: 1000, y: 1000), CGPoint(x: 1010, y: 1000)])
            ink.placement?.source = .retained(samples: ink.samples, lattice: nil, precise: true)
            return .stroke(ink)
        }
        let canvas = VectorCanvas(size: CGSize(width: 64, height: 64), elements: strokes)
        _ = canvas.render()
        InkMaterialRenderProbe.begin()
        var doomed: Set<UUID> = []
        let edits = canvas.wholeStrokePreviewEdits(alongPath: StrokeSamples(points: [CGPoint(x: 2, y: 2)]),
            brush: TestBrushes.hardRound, size: 2, accumulating: &doomed)
        _ = InkMaterialRenderProbe.end()
        XCTAssertTrue(edits.isEmpty)
        print("NATIVE DISTANT MATERIAL BOUNDS WALKS \(InkMaterialRenderProbe.nativeBoundsWalkCount)")
        XCTAssertEqual(InkMaterialRenderProbe.nativeBoundsWalkCount, 0,
                       "existing measured painted bounds must reject distant material without another native brush walk")
        let local = VectorStroke(brush: TestBrushes.hardRound, color: color, size: 12, opacity: 1,
            samples: StrokeSamples(points: [CGPoint(x: 20, y: 20)]), seed: 1)
        let moved = LiquifyField(operation().deformation).mapping([.stroke(local)])
        let near = VectorCanvas(size: CGSize(width: 64, height: 64), elements: moved)
        _ = near.render()
        InkMaterialRenderProbe.begin(); doomed = []
        let point = try XCTUnwrap(moved.first?.stroke?.samples.first?.point)
        let touched = near.wholeStrokePreviewEdits(alongPath: StrokeSamples(points: [point]),
            brush: TestBrushes.hardRound, size: 2, accumulating: &doomed)
        _ = InkMaterialRenderProbe.end()
        XCTAssertEqual(touched.count, 1, "a participating material stroke still reaches the same native query")
        XCTAssertEqual(InkMaterialRenderProbe.nativeBoundsWalkCount, 1, "native bounds are measured once and passed to the query")
    }

    func testNativeSourceTileLookupKeepsLargeAdjacentIntegerTapsInOneTile() throws {
        let base = CGFloat(9_007_199_254_740_992 as Int64)
        let bounds = CGRect(x: base, y: 0, width: 2048, height: 32)
        let renderer = InkMaterialRenderer(window: .zero, scale: 1)
        let hit = renderer.hasInk(at: [CGPoint(x: base + 254, y: 0.5)], nativeBounds: bounds,
            program: InkMaterialProgram(bindings: []), transport: .identity) { context, rect in
                context.setFillColor(UIColor.red.cgColor); context.fill(rect)
            }
        XCTAssertEqual(hit, true, "the actual native source callback paints the requested tile")
        XCTAssertTrue(renderer.completed)
        XCTAssertEqual(renderer.sourceTiles, 1,
                       "taps2^53+254 and+255 both belong to one256-pixel tile; a CGFloat key can select its neighbour")
    }

}
