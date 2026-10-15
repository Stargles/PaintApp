import XCTest
import UIKit
import IOSurface

final class LiquifyRasterLogicTests: XCTestCase {
    private let size = CanvasFixture.canvasSize
    private func image(_ color: UIColor = .red) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 20, y: 18, width: 9, height: 12))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 52, y: 52, width: 5, height: 5))
        }
    }
    private func bytes(_ image: UIImage) throws -> [UInt8] {
        try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(try XCTUnwrap(image.cgImage), width: Int(image.size.width), height: Int(image.size.height)))
    }
    private func held(_ manager: CanvasManager, layer: Int) throws -> LiquifySession {
        let profile = ToolProfile(preset: TestBrushes.hardRound, size: 40, opacity: 1)
        var session = try XCTUnwrap(manager.beginLiquify(layerID: manager.layers[layer].id, profile: profile, size: 40, seed: 7))
        session.samples = StrokeSamples([VectorSample(x: 24, y: 24), VectorSample(x: 38, y: 24)], channels: .pressureOnly)
        session.window = CGRect(x: 0, y: 0, width: 60, height: 48)
        manager.holdLiquify(&session)
        return session
    }
    func testRasterGestureHoldsThenMovesBothPixelTiersAsOneUndo() throws {
        let manager = CanvasFixture.manager()
        let rasterImage = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 20, y: 28, width: 9, height: 7))
        }
        let bakedImage = image(.red)
        manager.layers[0].cels[0].raster = RasterLayerTexture(size: size, image: rasterImage, strokeCount: 1)
        manager.layers[0].cels[0].bakedImage = bakedImage
        manager.history.removeAll()
        let before = try bytes(UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            bakedImage.draw(at: .zero); rasterImage.draw(at: .zero)
        })
        let sourceRaster = manager.layers[0].cels[0].raster
        let session = try held(manager, layer: 0)
        XCTAssertTrue(manager.layers[0].cels[0].raster === sourceRaster, "preview leaves saved pixel tiers alone")
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === bakedImage)
        manager.commitLiquify(session)
        let after = try bytes(manager.layers[0].cels[0].raster.renderToUIImage())
        XCTAssertNotEqual(after, before, "the drawn rectangle moves")
        let green = stride(from: 0, to: after.count, by: 4).filter { after[$0 + 1] > 180 && after[$0] < 60 && after[$0 + 2] < 60 }.count
        let red = stride(from: 0, to: after.count, by: 4).filter { after[$0] > 180 && after[$0 + 1] < 60 && after[$0 + 2] < 60 }.count
        XCTAssertGreaterThan(green, 15, "visible paint from the live raster tier survives the move")
        XCTAssertGreaterThan(red, 15, "visible paint from the baked tier survives the move")
        XCTAssertNil(manager.layers[0].cels[0].bakedImage, "raster landing remains eraseable")
        XCTAssertEqual(Array(after[((54 * 64 + 54) * 4)..<((54 * 64 + 54) * 4 + 4)]), Array(before[((54 * 64 + 54) * 4)..<((54 * 64 + 54) * 4 + 4)]), "distant pixel island stays exact")
        XCTAssertEqual(manager.history.undo(), .liquify)
        XCTAssertTrue(manager.layers[0].cels[0].raster === sourceRaster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === bakedImage)
        XCTAssertNil(manager.history.undo(), "one gesture has one history entry")
        XCTAssertEqual(manager.history.redo(), .liquify)
        XCTAssertEqual(try bytes(manager.layers[0].cels[0].raster.renderToUIImage()), after)
    }
    func testMixedCelMovesInkAndBackingTogetherButKeepsEditableImage() throws {
        let manager = CanvasFixture.manager(); manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        let ink = VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 4, opacity: 1,
            samples: StrokeSamples([VectorSample(x: 20, y: 24), VectorSample(x: 30, y: 24)], channels: .pressureOnly))
        let editable = VectorImageElement(image: image(.yellow), transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
        canvas.restoreElements([.stroke(ink), .image(editable)], changedInk: nil)
        let backing = image()
        manager.layers[1].cels[0].bakedImage = backing
        manager.history.removeAll()
        let session = try held(manager, layer: 1)
        manager.commitLiquify(session)
        guard case .stroke(let moved) = canvas.elements[0], case .image(let kept) = canvas.elements[1] else { return XCTFail("typed objects remain editable") }
        XCTAssertNotEqual(moved.samples, ink.samples)
        XCTAssertEqual(kept.id, editable.id); XCTAssertEqual(kept.transform, editable.transform)
        XCTAssertTrue(kept.image === editable.image)
        let after = try bytes(try XCTUnwrap(manager.layers[1].cels[0].bakedImage))
        XCTAssertNotEqual(after, try bytes(backing))
        XCTAssertFalse(manager.layers[1].cels[0].raster.hasContent, "mixed vector backing has one pixel tier")
        XCTAssertEqual(manager.history.undo(), .liquify)
        guard case .stroke(let undone) = canvas.elements[0] else { return XCTFail("ink") }
        XCTAssertEqual(undone.samples, ink.samples)
        XCTAssertTrue(manager.layers[1].cels[0].bakedImage === backing)
        XCTAssertNil(manager.history.undo())
        XCTAssertEqual(manager.history.redo(), .liquify)
        XCTAssertEqual(try bytes(try XCTUnwrap(manager.layers[1].cels[0].bakedImage)), after)
    }
    func testLinkedEmptyInkStillMovesBackingAndOneUndoRestoresRecipeAndPixels() throws {
        for withPixels in [true, false] {
            let manager = CanvasFixture.manager(); manager.addVectorLayer(); manager.addVectorLayer()
            let refs = (0...1).map { InterpolationReference(layerID: manager.layers[$0].id, celID: manager.layers[$0].cels[0].id) }
            let recipe = InterpolationRecipe(references: refs, t: 0.37)
            manager.layers[2].cels[0].interpolation = recipe
            let backing = withPixels ? image() : nil
            manager.layers[2].cels[0].bakedImage = backing
            manager.history.removeAll()
            let session = try held(manager, layer: 2)
            let procedure = try XCTUnwrap(manager.liveCelContentEdit?.procedure)
            manager.commitLiquify(session)
            XCTAssertEqual(procedure.resolutionCount, 1, "ink and backing use one completed producer")
            let after = manager.layers[2].cels[0]
            XCTAssertEqual(after.interpolation?.references, refs, "the pixel change preserves live source links")
            XCTAssertEqual(after.interpolation?.deformations.count, 1, "the new field remains in the linked recipe")
            XCTAssertGreaterThan(manager.history.currentCost, 0, "a linked-only field is retained history, even without pixels")
            if let backing {
                XCTAssertNotEqual(try bytes(try XCTUnwrap(after.bakedImage)), try bytes(backing), "empty evaluated lists must not skip the last field's backing work")
                XCTAssertGreaterThan(manager.history.currentCost, Int(size.width * size.height * 4), "mixed history includes retained pixel buffers too")
            }
            XCTAssertEqual(manager.history.undo(), .liquify)
            XCTAssertEqual(manager.layers[2].cels[0].interpolation?.contentFingerprint, recipe.contentFingerprint)
            XCTAssertTrue(manager.layers[2].cels[0].bakedImage === backing)
            XCTAssertNil(manager.history.undo(), "recipe and backing share one reversal")
            XCTAssertEqual(manager.history.redo(), .liquify)
            XCTAssertEqual(manager.layers[2].cels[0].interpolation?.contentFingerprint, after.interpolation?.contentFingerprint)
        }
    }

    @MainActor
    func testRejectedPixelWindowKeepsThePresentedPaintAndDoesNotCommitAtLift() throws {
        let manager = CanvasFixture.manager()
        let before = image()
        manager.layers[0].cels[0].bakedImage = before
        manager.history.removeAll()
        manager.onHeldPictureMoved = {}
        var session = try held(manager, layer: 0)
        let good = try XCTUnwrap(manager.liveCelContentEdit)
        let view = WindowSurfaceView(queue: DispatchQueue(label: "LiquifyRasterLogicTests.rejection"))
        let first = expectation(description: "valid paint shown")
        view.present(window: good.window, placement: .identity, draw: { good.drawWindow(into: $0) }, finished: { shown in
            XCTAssertTrue(shown); good.procedure?.didPresent(); first.fulfill()
        })
        wait(for: [first], timeout: 10)
        let priorSurface = try XCTUnwrap(view.layer.contents as? IOSurface)
        // Deliberately under-declare the source support: an in-canvas inverse cannot be sampled.
        session.window = CGRect(x: 30, y: 20, width: 2, height: 2)
        manager.holdLiquify(&session)
        let bad = try XCTUnwrap(manager.liveCelContentEdit)
        manager.commitLiquify(session)
        let rejected = expectation(description: "invalid draw rejected")
        view.present(window: bad.window, placement: .identity, draw: { bad.drawWindow(into: $0) }, finished: { shown in
            XCTAssertFalse(shown, "a failed inverse may not replace valid paint with a partial picture")
            bad.procedure?.didReject(); rejected.fulfill()
        })
        wait(for: [rejected], timeout: 10)
        XCTAssertTrue(bad.procedure?.hasFailed == true, "PREMISE: source support failed")
        XCTAssertFalse(bad.procedure?.isPresented == true)
        XCTAssertTrue((view.layer.contents as? IOSurface) === priorSurface, "the prior drawn paint remains on screen")
        XCTAssertEqual(view.presentedCount, 1)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === before)
        XCTAssertFalse(manager.history.canUndo)
        XCTAssertNil(manager.liveCelContentEdit, "a rejected lift completes without waiting for a picture that cannot land")
    }

    @MainActor
    func testRefusedNativeMaterialWindowPreservesShownSurfaceAndSavedCel() throws {
        for linked in [false, true] {
            let manager = CanvasFixture.manager(); manager.addVectorLayer()
            let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
            let samples = StrokeSamples(points: [CGPoint(x: 12, y: 24), CGPoint(x: 45, y: 24)])
            let gesture = LiquifyDeformation(brush: TestBrushes.hardRound, size: 40, power: 1,
                mode: .push, seed: 4, samples: samples)
            let material = InkMaterialProgram(bindings: [InkMaterialBinding(operation: InkMaterialOperation(gesture),
                bridge: .identity)])
            let ink = VectorStroke(brush: TestBrushes.hardRound,
                color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 4, opacity: 1,
                samples: samples, placement: StrokePlacement(map: .identity, restSize: 4,
                    source: .retained(samples: samples, lattice: nil, precise: true), material: material,
                    transport: .homography(.scale(x: 0, y: 1))))
            if linked {
                let refs = (0...1).map { InterpolationReference(layerID: manager.layers[$0].id, celID: manager.layers[$0].cels[0].id) }
                manager.layers[1].cels[0].interpolation = InterpolationRecipe(references: refs, t: 0.4,
                    localEdits: [LocalEdit(stroke: ink)])
            } else { canvas.restoreElements([.stroke(ink)], changedInk: nil) }
            let original = manager.layers[1].cels[0]
            let backing = image(); manager.layers[1].cels[0].bakedImage = backing
            manager.history.removeAll(); manager.onHeldPictureMoved = {}
            let session = try held(manager, layer: 1)
            let bad = try XCTUnwrap(manager.liveCelContentEdit)
            let view = WindowSurfaceView(queue: DispatchQueue(label: "LiquifyRasterLogicTests.materialRefusal"))
            view.presentFirst(.init(window: bad.window, placement: .identity, draw: { _ in
                backing.draw(at: .zero); return bad.window
            }))
            let prior = try XCTUnwrap(view.layer.contents as? IOSurface)
            manager.commitLiquify(session)
            let rejected = expectation(description: "native material draw refused")
            view.present(window: bad.window, placement: .identity, draw: { bad.drawWindow(into: $0) }, finished: { shown in
                XCTAssertFalse(shown, "failed native or linked material must never certify a partial picture")
                bad.procedure?.didReject(); rejected.fulfill()
            })
            wait(for: [rejected], timeout: 10)
            XCTAssertTrue(bad.procedure?.hasFailed == true)
            XCTAssertTrue((view.layer.contents as? IOSurface) === prior, "the exact previous surface survives refusal")
            XCTAssertEqual(view.presentedCount, 1)
            XCTAssertFalse(manager.history.canUndo)
            XCTAssertTrue(manager.layers[1].cels[0].bakedImage === backing)
            XCTAssertEqual(manager.layers[1].cels[0].interpolation?.contentFingerprint, original.interpolation?.contentFingerprint)
            XCTAssertEqual(canvas.elements.count, linked ? 0 : 1)
            XCTAssertNil(manager.liveCelContentEdit, "rejected lift completes without saving failed native ink")
        }
    }

    @MainActor
    func testStreamArrivalIsNotACommitButRealInkChangeStillRejectsAStaleGesture() throws {
        for change in ["display", "pixels", "document"] {
            let manager = CanvasFixture.manager(); manager.addVectorLayer()
            let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
            let stream = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8), host: "fixture", port: 47301,
                sourceLabel: "fixture", rendersInPlace: true,
                transform: LayerTransform(position: CGPoint(x: 24, y: 24), scale: 1, rotation: 0))
            canvas.elements = [.stream(stream)]; canvas.bumpVersion()
            canvas.setStreamFrame(id: stream.id, image: image(.green), index: 1)
            if change != "display" { manager.layers[1].cels[0].bakedImage = image() }
            let original = manager.layers[1].cels[0]
            let revisions = CelContentRevisions()
            let beforeRevision = revisions.observe(original)
            let identity = CelContentIdentity(original)
            manager.history.removeAll()
            let session = try held(manager, layer: 1)
            canvas.setStreamFrame(id: stream.id, image: image(.blue), index: 2)
            XCTAssertEqual(CelContentIdentity(manager.layers[1].cels[0]), identity, "a laptop picture is display state")
            XCTAssertEqual(revisions.committed(canvas), beforeRevision)
            XCTAssertEqual(revisions.observe(manager.layers[1].cels[0]), beforeRevision, "stream arrival cannot turn cancellation into a landing")
            if change == "document" {
                let ink = VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 3, opacity: 1,
                    samples: StrokeSamples([VectorSample(x: 3, y: 50), VectorSample(x: 10, y: 50)], channels: .pressureOnly))
                canvas.addStroke(ink)
                XCTAssertNotEqual(CelContentIdentity(manager.layers[1].cels[0]), identity)
            }
            manager.commitLiquify(session)
            if change == "pixels" {
                XCTAssertTrue(manager.history.canUndo, "a live frame must not reject a genuine pixel edit")
                XCTAssertNotEqual(try bytes(try XCTUnwrap(manager.layers[1].cels[0].bakedImage)), try bytes(try XCTUnwrap(original.bakedImage)))
            } else {
                XCTAssertFalse(manager.history.canUndo, "untouched or stale input makes no Liquify history entry")
                XCTAssertTrue(manager.layers[1].cels[0].bakedImage === original.bakedImage)
                if change == "document" { XCTAssertEqual(canvas.elements.count, 2, "stale field must not overwrite newer ink") }
            }
        }
    }

    @MainActor
    func testPosedHeldBackingMatchesCommittedPixelsThroughTheStreamRecipe() throws {
        try assertPosedWindow(mixed: false, pixels: true)
        try assertPosedWindow(mixed: true, pixels: true)
    }

    @MainActor
    func testNativeInkWindowMatchesCommittedGeometryPoseThroughTheStreamRecipe() throws {
        try assertPosedWindow(mixed: true, pixels: false)
    }

    func testBackingPatchConjugatesTheGestureThroughItsIndependentPlacement() throws {
        var cel = CanvasFixture.manager().layers[0].cels[0]
        cel.bakedImage = image()
        let snapshot = try XCTUnwrap(CelPixelSnapshot(cel: cel))
        let samples = [VectorSample(x: 24, y: 24), VectorSample(x: 32, y: 24)]
        let window = CGRect(x: 0, y: 0, width: 60, height: 48)
        func field(offset: CGPoint) -> LiquifyField {
            let shifted = samples.map { VectorSample(x: $0.point.x + offset.x, y: $0.point.y + offset.y) }
            return LiquifyField(LiquifyDeformation(brush: TestBrushes.hardRound, size: 40, power: 1,
                mode: .push, seed: 7, samples: StrokeSamples(shifted, channels: .pressureOnly)))
        }
        let rest = try XCTUnwrap(snapshot.liquifiedPatch(in: window, using: field(offset: .zero)))
        let offset = CGPoint(x: 9, y: 4)
        let bridge = PoseMap.affine(CGAffineTransform(translationX: offset.x, y: offset.y))
        let placed = try XCTUnwrap(snapshot.liquifiedPatch(in: window.offsetBy(dx: offset.x, dy: offset.y),
            using: field(offset: offset), through: bridge))
        XCTAssertTrue(rest.changed, "the reference actually moves painted pixels")
        XCTAssertEqual(placed.rect, rest.rect, "patch storage remains in the backing's own coordinates")
        XCTAssertEqual(try bytes(placed.image), try bytes(rest.image),
            "a layer placement changes the field's coordinates without moving the brush away from the backing")
    }

    func testRasterOnlyTranslatedWindowLeavesPaintOutsideItsActualFootprintUntouched() throws {
        var cel = CanvasFixture.manager().layers[0].cels[0]
        let source = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.yellow.setFill(); ctx.fill(CGRect(x: 0, y: 10, width: 12, height: 12))
            UIColor.green.setFill(); ctx.fill(CGRect(x: 20, y: 10, width: 12, height: 12))
        }
        cel.bakedImage = source
        let shift = CGPoint(x: 20, y: 0)
        let pose = PoseMap.affine(CGAffineTransform(translationX: shift.x, y: shift.y))
        let placement = CelContentPlacement(ink: pose, backing: pose)
        let window = CGRect(x: 20, y: 10, width: 12, height: 12)
        let gesture = LiquifyDeformation(brush: TestBrushes.hardRound, size: 16, power: 0,
            mode: .push, seed: 4, samples: StrokeSamples([VectorSample(x: 24, y: 16)], channels: .pressureOnly))
        let procedure = CelContentProcedure(deformation: gesture, selectedIDs: nil, poses: [:],
            pixelSnapshot: try XCTUnwrap(CelPixelSnapshot(cel: cel)), window: window,
            canvasSize: size, placement: placement)
        let picture = try XCTUnwrap(procedure.contentPicture([]))
        // Independent full-image translation: the yellow island is at the unposed window, while
        // the green replacement belongs twenty pixels to its right.
        let expected = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            source.draw(at: shift)
        }
        var accepted = false
        let actual = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            source.draw(at: shift)
            accepted = picture.draw(into: ctx.cgContext, content: CGRect(origin: .zero, size: size),
                placement: placement, replacing: true)
        }
        XCTAssertTrue(accepted)
        let a = try bytes(actual), b = try bytes(expected)
        XCTAssertEqual(a, b, "an unchanged translated raster tick must not erase a second, unposed window")
        let yellow = (15 * Int(size.width) + 25) * 4
        XCTAssertEqual(Array(a[yellow..<(yellow + 4)]), [255, 255, 0, 255],
            "paint outside the actual shown replacement remains visible")
    }

    @MainActor
    private func assertPosedWindow(mixed: Bool, pixels: Bool) throws {
        let manager = CanvasFixture.manager()
        manager.layers[0].cels[0].bakedImage = pixels ? image() : nil
        if mixed {
            manager.layers[0].kind = .vector
            let ink = VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 0.83), size: 3.4, opacity: 0.83,
                samples: StrokeSamples([VectorSample(x: 8, y: 36), VectorSample(x: 44, y: 36)], channels: .pressureOnly))
            let editable = VectorImageElement(image: image(.green),
                transform: LayerTransform(position: CGPoint(x: 55, y: 15), scale: 0.1, rotation: 0))
            manager.layers[0].cels[0].vector = VectorCanvas(size: size, elements: [.stroke(ink), .image(editable)])
        }
        manager.addTransformLayer(name: "pose")
        let affine = CGAffineTransform(scaleX: 0.8, y: 0.8).concatenating(CGAffineTransform(rotationAngle: 0.15))
            .concatenating(CGAffineTransform(translationX: 10, y: 7))
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: CGRect(origin: .zero, size: size), mappedBy: affine), mode: .move)
        manager.addVectorLayer(name: "screen")
        let canvas = try XCTUnwrap(manager.layers[2].cels[0].vector)
        let stream = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8), host: "fixture", port: 47301,
            sourceLabel: "fixture", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 55, y: 55), scale: 1, rotation: 0))
        canvas.elements = [.stream(stream)]; canvas.bumpVersion()
        canvas.setStreamFrame(id: stream.id, image: image(.blue), index: 1)
        manager.currentLayerIndex = 0
        let initialCel = manager.layers[0].cels[0]
        let initialPlacement = manager.celContentPlacement(forLayerID: manager.layers[0].id)
        let unchanged = try XCTUnwrap(PixelOps.rasterize(cel: initialCel, canvasSize: size, memoize: false,
            derived: manager.derivedCelContent(for: initialCel, atFrame: manager.currentFrame, inheriting: initialPlacement.backing),
            pose: initialPlacement.backing))
        var session = try held(manager, layer: 0)
        session.window = CGRect(x: 3, y: 3, width: 57, height: 45)
        manager.holdLiquify(&session)
        let edit = try XCTUnwrap(manager.liveCelContentEdit)
        let placement = manager.celContentPlacement(forLayerID: edit.layerID)
        XCTAssertNotNil(placement.ink)
        let footprint = edit.displayedBounds(placement: placement)
        var source = PixelOps.CelDisplay()
        source.drawOverlays = edit.displaySource(placement: placement, canvasSize: size)
        let preview = try XCTUnwrap(manager.makeStreamDisplayRecipe(display: [edit.layerID: source], transientBounds: footprint))
        let heldImage = try XCTUnwrap(preview.recipe.composite())
        manager.commitLiquify(session)
        let committed = try XCTUnwrap(manager.makeStreamDisplayRecipe(transientBounds: footprint))
        XCTAssertEqual(preview.buffer, committed.buffer)
        let committedImage = try XCTUnwrap(committed.recipe.composite())
        let shown = try XCTUnwrap(edit.presentation(placement: placement))
        let cel = manager.layers[0].cels[0]
        let independent = try XCTUnwrap(PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false,
            derived: manager.derivedCelContent(for: cel, atFrame: manager.currentFrame, inheriting: placement.backing),
            pose: placement.backing))
        let actual = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            unchanged.draw(at: .zero)
            shown.draw(into: ctx.cgContext, content: CGRect(origin: .zero, size: size), canvasSize: size)
        }
        for (name, image) in [("posed-host-held", actual), ("posed-host-committed", independent)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name + (mixed ? "-mixed" : "-raster")
            attachment.lifetime = .keepAlways; add(attachment)
        }
        let hostA = try bytes(actual), hostB = try bytes(independent)
        XCTAssertTrue(hostA == hostB,
            "the actual held replacement over unchanged backing must equal the committed cel; differing channels: \(zip(hostA, hostB).filter { $0 != $1 }.count)")
        let heldPicture = UIImage(cgImage: heldImage), committedPicture = UIImage(cgImage: committedImage)
        for (name, picture) in [("posed-stream-held", heldPicture), ("posed-stream-committed", committedPicture)] {
            let attachment = XCTAttachment(image: picture)
            attachment.name = name + (mixed ? "-mixed" : "-raster"); attachment.lifetime = .keepAlways; add(attachment)
        }
        let a = try bytes(heldPicture), b = try bytes(committedPicture)
        let differences = a.indices.filter { a[$0] != b[$0] }
        XCTAssertTrue(differences.isEmpty,
                      "the posed \(mixed ? "mixed" : "raster") stream picture must land exactly; differing channels: \(differences.count), first: \(differences.prefix(12)), max delta: \(differences.map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0)")
    }

    @MainActor
    func testNewVectorPanelReplacementKeepsBackingFromAnOlderMixedWindow() throws {
        let manager = CanvasFixture.manager(); manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        let ink = VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 4, opacity: 1,
            samples: StrokeSamples([VectorSample(x: 18, y: 24), VectorSample(x: 38, y: 24)], channels: .pressureOnly))
        canvas.addStroke(ink)
        manager.layers[1].cels[0].bakedImage = image()
        let original = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[1].cels[0], canvasSize: size, memoize: false))
        let session = try held(manager, layer: 1)
        let old = try XCTUnwrap(manager.liveCelContentEdit)
        let oldRendered = try XCTUnwrap(old.presentation(placement: .identity))
        manager.commitLiquify(session)
        let beforePanel = canvas.elements
        var afterPanel = beforePanel
        guard case .stroke(var recolored) = afterPanel[0] else { return XCTFail("ink") }
        recolored.color = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        afterPanel[0] = .stroke(recolored)
        var panel = manager.beginElementEdit(layerID: manager.layers[1].id, celID: manager.layers[1].cels[0].id,
            vectorCanvas: canvas, elementsBefore: beforePanel, rewriting: [ink.id], extreme: afterPanel)
        manager.holdElementEdit(afterPanel, in: &panel)
        let newer = try XCTUnwrap(manager.liveCelContentEdit)
        let newRendered = try XCTUnwrap(newer.presentation(placement: .identity))
        manager.recordElementEdit(panel, finalElements: afterPanel, label: .liquify)
        let truth = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[1].cels[0], canvasSize: size, memoize: false))
        var pending = UnlandedInk()
        pending.hold(.init(id: 1, version: 1, windowRect: oldRendered.window, replacing: oldRendered.footprint,
            contents: .image(oldRendered.image)))
        pending.hold(.init(id: 2, version: 2, windowRect: newRendered.window, replacing: newRendered.footprint,
            contents: .image(newRendered.image)))
        let plan = pending.displayPlan()
        let root = UIView(frame: CGRect(origin: .zero, size: size))
        let base = UIImageView(image: original); base.frame = root.bounds
        let path = CGMutablePath(); path.addRect(root.bounds)
        if let hole = plan.baseHole { path.addPath(hole) }
        let mask = CAShapeLayer(); mask.frame = root.bounds; mask.fillRule = .evenOdd; mask.path = path
        base.layer.mask = mask; root.addSubview(base)
        for visible in plan.pictures {
            let view = visible.picture.makeCanvasView(size: size, placement: .identity)
            visible.applyClip(to: view); root.addSubview(view)
        }
        let shown = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { root.layer.render(in: $0.cgContext) }
        XCTAssertEqual(try bytes(shown), try bytes(truth), "newer vector-only replacement must carry the already-moved backing under its transparent areas")
    }

    func testPanelReplacementRedrawsBothTiersAcrossIndependentPoseWindows() throws {
        for opacityEdit in [false, true] {
            let manager = CanvasFixture.manager(); manager.addVectorLayer()
            let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
            func stroke(_ a: CGFloat, _ b: CGFloat, color: CodableColor) -> VectorStroke {
                VectorStroke(brush: TestBrushes.hardRound, color: color, size: 4, opacity: 1,
                    samples: StrokeSamples([VectorSample(x: a, y: 16), VectorSample(x: b, y: 16)], channels: .pressureOnly))
            }
            let target = stroke(12, 20, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1))
            let other = stroke(1, 5, color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
            canvas.restoreElements([.stroke(other), .stroke(target)], changedInk: nil)
            manager.layers[1].cels[0].bakedImage = UIGraphicsImageRenderer(size: size,
                format: PixelOps.transparentFormat()).image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(origin: .zero, size: size)) }
            let box = CGRect(origin: .zero, size: size)
            CanvasFixture.setPoseTrack(manager, layerID: manager.layers[1].id,
                celID: manager.layers[1].cels[0].id, channel: .cel,
                CanvasFixture.poseTrack([(0, PoseQuad(restingIn: box)),
                    (6, PoseQuad(box: box, mappedBy: .init(translationX: 12, y: 0)))], interpolation: .linear))
            manager.currentFrame = 6
            func committed() throws -> UIImage {
                let cel = manager.layers[1].cels[0]
                return try XCTUnwrap(PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false,
                    derived: manager.derivedCelContent(for: cel, atFrame: manager.currentFrame)))
            }
            let before = try committed()
            let original = canvas.elements
            var changed = target
            if opacityEdit { changed.opacity = 0.35 }
            else { changed.color = CodableColor(red: 0, green: 1, blue: 0, alpha: 1) }
            let final: [VectorElement] = [.stroke(other), .stroke(changed)]
            var panel = manager.beginElementEdit(layerID: manager.layers[1].id, celID: manager.layers[1].cels[0].id,
                vectorCanvas: canvas, elementsBefore: original, rewriting: [target.id], extreme: final)
            manager.holdElementEdit(final, in: &panel)
            let live = try XCTUnwrap(manager.liveCelContentEdit)
            let placement = manager.celContentPlacement(forLayerID: manager.layers[1].id)
            let presented = try XCTUnwrap(live.presentation(placement: placement))
            let actual = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
                before.draw(at: .zero)
                live.displaySource(placement: placement, canvasSize: size)(ctx.cgContext, box)
            }
            manager.recordElementEdit(panel, finalElements: final, label: .liquify)
            let truth = try committed()
            let crop = try XCTUnwrap(PixelOps.copiedSubimage(of: truth, in: presented.window))
            for (name, image) in [("held-window", presented.image), ("committed-window", crop),
                                  ("shown-cel", actual), ("committed-cel", truth)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "independent-poses-\(opacityEdit ? "opacity" : "colour")-\(name)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            XCTAssertTrue(try bytes(presented.image) == bytes(crop), "the actual host window includes backing beside posed ink and unrelated ink in the backing lobe")
            XCTAssertTrue(try bytes(actual) == bytes(truth), "Colour and Opacity stream replacements redraw the complete cel throughout their shared footprint")
        }
    }

    @MainActor
    func testVectorScratchCarriesIndependentBackingThroughLiveStreamAndPendingLift() throws {
        let side = CGSize(width: 256, height: 256), box = CGRect(x: 0, y: 0, width: 256, height: 256)
        for subtractive in [true, false] {
            let manager = CanvasFixture.manager(layerCount: 0)
            manager.canvasSize = side; manager.addVectorLayer()
            let canvas = try XCTUnwrap(manager.layers[0].cels[0].vector)
            func mark(_ x: CGFloat, _ end: CGFloat, _ y: CGFloat, _ color: CodableColor) -> VectorElement {
                .stroke(VectorStroke(brush: TestBrushes.hardRound, color: color, size: 8, opacity: 1,
                    samples: StrokeSamples([VectorSample(x: x, y: y), VectorSample(x: end, y: y)], channels: .pressureOnly)))
            }
            canvas.restoreElements([mark(96, 130, 100, .init(red: 0, green: 0, blue: 0, alpha: 1)),
                mark(16, 24, 80, .init(red: 0, green: 0, blue: 1, alpha: 1))], changedInk: nil)
            let backdrop = try XCTUnwrap(canvas.render())
            let backing = UIGraphicsImageRenderer(size: side, format: PixelOps.transparentFormat()).image { ctx in
                UIColor.red.setFill(); ctx.fill(CGRect(x: 60, y: 20, width: 36, height: 180))
                UIColor.green.setFill(); ctx.fill(CGRect(x: 156, y: 20, width: 28, height: 180))
            }
            manager.layers[0].cels[0].bakedImage = backing
            let pose = PoseMap(CGAffineTransform(translationX: 64, y: 0))
            let placement = CelContentPlacement(ink: pose)
            let source = StrokeScratch.CelContent(backing: CelPixelSnapshot(cel: manager.layers[0].cels[0]),
                ink: .ordinary(source: canvas.freeze(quality: .full), elements: canvas.elements, rewriting: []),
                placement: placement)
            let scratch = StrokeScratch(canvasSize: side,
                role: subtractive ? .subtractive(backdrop: backdrop) : .replacing(backdrop: backdrop),
                celContent: source)
            let fullInk = RasterLayerTexture(size: side, image: backdrop, strokeCount: 1)
            func erase(_ point: CGPoint) {
                scratch.stampCircle(at: point, radius: 6, color: .black, alpha: 1, hardness: 1,
                    blendMode: subtractive ? .normal : .destinationOut)
                fullInk.stampCircle(at: point, radius: 6, color: .black, alpha: 1, hardness: 1, blendMode: .destinationOut)
            }
            func complete(_ ink: UIImage) -> UIImage {
                UIGraphicsImageRenderer(size: side, format: PixelOps.transparentFormat()).image { ctx in
                    backing.draw(at: .zero)
                    ctx.cgContext.translateBy(x: 64, y: 0); ink.draw(at: .zero)
                }
            }
            let before = complete(backdrop)
            erase(CGPoint(x: 108, y: 100))
            let first = try XCTUnwrap(scratch.renderedCelContent)
            let truth = complete(fullInk.renderToUIImage())
            XCTAssertNotEqual(try bytes(before), try bytes(truth), "PREMISE: the full native ink oracle was erased")
            let crop = try XCTUnwrap(PixelOps.copiedSubimage(of: truth, in: first.window))
            XCTAssertTrue(try bytes(first.image) == bytes(crop), "live vector erasers redraw native ink and stationary backing through their shared union")
            let stream = UIGraphicsImageRenderer(size: side, format: PixelOps.transparentFormat()).image { ctx in
                before.draw(at: .zero); first.draw(into: ctx.cgContext, content: box, canvasSize: side)
            }
            XCTAssertTrue(try bytes(stream) == bytes(truth), "the immutable stream window is the same complete picture")
            var pending = UnlandedInk()
            pending.hold(.init(id: 1, version: 1, windowRect: first.window, replacing: first.footprint,
                contents: .image(first.image)))
            let plan = pending.displayPlan(placement: placement, coveringPaths: [])
            let root = UIView(frame: box), base = UIImageView(image: before)
            base.frame = box
            let cut = CGMutablePath(); cut.addRect(box); cut.addPath(try XCTUnwrap(plan.baseHole))
            let mask = CAShapeLayer(); mask.frame = box; mask.path = cut; mask.fillRule = .evenOdd
            base.layer.mask = mask; root.addSubview(base)
            for visible in plan.pictures {
                let view = visible.picture.makeCanvasView(size: side, placement: placement)
                visible.applyClip(to: view); root.addSubview(view)
            }
            let lifted = UIGraphicsImageRenderer(size: side, format: PixelOps.transparentFormat()).image {
                root.layer.render(in: $0.cgContext)
            }
            XCTAssertTrue(try bytes(lifted) == bytes(truth), "the pending lift holds the already-posed bitmap without reposing its backing")
            erase(CGPoint(x: 118, y: 100))
            let next = try XCTUnwrap(scratch.renderedCelContent)
            let nextTruth = complete(fullInk.renderToUIImage())
            let nextCrop = try XCTUnwrap(PixelOps.copiedSubimage(of: nextTruth, in: next.window))
            XCTAssertTrue(try bytes(next.image) == bytes(nextCrop), "a later dab inside the same window invalidates its complete picture")
            XCTAssertTrue(try bytes(first.image) == bytes(crop), "the earlier held picture stays immutable as the scratch advances")
        }
    }

    @MainActor
    func testPosedAdditiveWindowKeepsFractionalOpacityInWholeAndStreamStrips() throws {
        defer { PixelOps.clearRasterizeCache() }
        let manager = CanvasFixture.manager()
        let rect = CGRect(x: 12, y: 18, width: 20, height: 16)
        let patch = UIGraphicsImageRenderer(size: rect.size, format: PixelOps.transparentFormat()).image { context in
            UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: rect.size))
        }
        let opacity: CGFloat = 0.37
        let pose = PoseMap(CGAffineTransform(translationX: 8, y: 0))
        let ink = PixelOps.InkWindow(image: patch, rect: rect, canvasSize: size,
            opacity: opacity, replacesBase: false, pose: pose)
        let display = PixelOps.CelDisplay(windows: [ink])
        let cel = manager.layers[0].cels[0]
        let frozen = PixelOps.FrozenCel(cel: cel, derived: nil, quality: .full, display: display)
        let expected = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            patch.draw(in: rect.offsetBy(dx: 8, dy: 0), blendMode: .normal, alpha: opacity)
        }
        let reference = try bytes(expected)
        XCTAssertEqual(reference[(24 * 64 + 26) * 4 + 3], 94, "PREMISE: the independent picture has fractional coverage")
        let direct = try XCTUnwrap(PixelOps.rasterize(frozen, canvasSize: size, quality: .full))
        XCTAssertEqual(zip(try bytes(direct), reference).filter { $0 != $1 }.count, 0,
            "posed scratch opacity must reach the final sampler tile draw")
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false,
            liveDisplay: [manager.layers[0].id: display]))
        let band = CGRect(x: 0, y: 20, width: size.width, height: 10)
        let strip = recipe.windowed(to: band)
        let actual = UIImage(cgImage: try XCTUnwrap(Compositor.composite(strip.resolve(), resolving: .coreGraphics)))
        let crop = try XCTUnwrap(PixelOps.copiedSubimage(of: expected, in: band))
        XCTAssertEqual(zip(try bytes(actual), try bytes(crop)).filter { $0 != $1 }.count, 0,
            "the stream recipe's translated strip retains the same fractional scratch pixels")
    }

    @MainActor
    func testRequiredNativeMaterialRefusalRejectsPartialDisplayAndStripSources() throws {
        defer { PixelOps.clearRasterizeCache() }
        let manager = CanvasFixture.manager(layerCount: 0); manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[0].cels[0].vector)
        let samples = StrokeSamples(points: [CGPoint(x: 4, y: 20), CGPoint(x: 60, y: 20)])
        let operation = InkMaterialOperation(LiquifyDeformation(brush: TestBrushes.hardRound,
            size: 40, power: 0.8, mode: .push, seed: 17, samples: samples))
        let rest = Lattice(cols: 64, rows: 64, restOrigin: .zero, restCellSize: 1)
        var stretched = rest
        for row in 0...64 { for col in 0...64 {
            stretched.vertices[row * 65 + col] = CGPoint(x: col.isMultiple(of: 2) ? -1000 : 1000,
                                                        y: row.isMultiple(of: 2) ? -1000 : 1000)
        } }
        XCTAssertGreaterThan(DeformedCellIndex.storageByteUpperBound(lattice: stretched), InkMaterialRenderer.byteBudget,
            "PREMISE: native material itself exceeds its counted index budget; no whole-compositor budget override")
        let ink = VectorStroke(brush: TestBrushes.pencil, color: .init(red: 0, green: 0, blue: 0, alpha: 1),
            size: 8, opacity: 1, samples: samples, seed: 7,
            placement: StrokePlacement(map: .identity, restSize: 8,
                source: .retained(samples: samples, lattice: nil, precise: true),
                material: InkMaterialProgram(bindings: [.init(operation: operation, bridge: .identity)]),
                transport: .lattice(captured: rest, current: stretched, pose: .identity)))
        let prefix = VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 16, height: 24), transform: nil),
            color: .init(red: 1, green: 0, blue: 0, alpha: 1))
        canvas.restoreElements([.fill(prefix), .stroke(ink)], changedInk: nil)
        let native = canvas.freeze(quality: .full)
        var completion: Int?
        let partial = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            completion = native.draw(into: context.cgContext, frameRect: CGRect(origin: .zero, size: size), quality: .full)
        }
        XCTAssertNil(completion, "PREMISE: existing native renderer actually refuses this required source")
        XCTAssertTrue(try bytes(partial).contains { $0 != 0 }, "PREMISE: earlier valid ink already painted before refusal")
        PixelOps.clearRasterizeCache()
        let display = PixelOps.CelDisplay(vector: native)
        let direct = PixelOps.FrozenCel(cel: manager.layers[0].cels[0], derived: nil, quality: .full, display: display)
        XCTAssertNil(PixelOps.rasterize(direct, canvasSize: size, quality: .full),
            "a display source may not return the native painter's partial picture")
        XCTAssertEqual(PixelOps.rasterizeCacheBytes, 0, "failed native display pixels never enter the flatten memo")
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false))
        let band = CGRect(x: 0, y: 12, width: size.width, height: 16)
        let request = recipe.windowed(to: band).resolve()
        XCTAssertTrue(request.sourceResolutionFailed, "strip resolution propagates required native failure")
        XCTAssertNil(request.sources[0], "partial native strip pixels cannot become a compositor leaf")
        XCTAssertNil(Compositor.composite(request, resolving: .coreGraphics), "the existing frame refusal guard rejects partial native strips")
        XCTAssertEqual(PixelOps.rasterizeCacheBytes, 0, "failed native strips never enter the flatten memo")
        XCTAssertNil(native.render(quality: .full), "the frozen full renderer must retain native refusal")
        XCTAssertNil(native.render(quality: .full, fittingInto: CGSize(width: 32, height: 32)),
            "the fitted frozen renderer must retain native refusal")
        for sizing: RenderSizing in [.native, .fitting(CGSize(width: 32, height: 32))] {
            PixelOps.clearRasterizeCache()
            let whole = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false, sizing: sizing))
            let fullRequest = whole.resolve()
            XCTAssertTrue(fullRequest.sourceResolutionFailed, "full and fitted frames must propagate required native failure")
            XCTAssertNil(fullRequest.sources[0], "a refused native whole source is not transparent success")
            XCTAssertNil(Compositor.composite(fullRequest, resolving: .coreGraphics))
            XCTAssertEqual(PixelOps.rasterizeCacheBytes, 0, "refused native whole frames never enter the flatten memo")
        }
        let empty = CanvasFixture.manager(layerCount: 0); empty.addVectorLayer()
        let emptyRecipe = try XCTUnwrap(empty.makeFrameRecipe(atFrame: 0, includeBackground: false))
        let emptyRequest = emptyRecipe.windowed(to: band).resolve()
        XCTAssertFalse(emptyRequest.sourceResolutionFailed, "a genuinely empty vector leaf remains valid")
        XCTAssertNotNil(Compositor.composite(emptyRequest, resolving: .coreGraphics))
        OnionSkinRasterCache.removeAll()
        defer { OnionSkinRasterCache.removeAll() }
        let priorThumbnail = image(.green)
        manager.layers[0].cels[0].thumbnail = priorThumbnail
        manager.regenerateThumbnail(layerIndex: 0, celIndex: 0)
        XCTAssertTrue(manager.layers[0].cels[0].thumbnail === priorThumbnail,
            "a refused thumbnail keeps the exact previously displayed tile")
        XCTAssertNil(OnionSkinRasterCache.image(for: manager.layers[0].cels[0], canvasSize: size,
            at: CGSize(width: 32, height: 32)), "a required onion source refuses without becoming a blank ghost")
        XCTAssertEqual(OnionSkinRasterCache.residentBytes, 0, "refused onion source cannot enter its reduced cache")
        manager.addTransformLayer(name: "native refusal pose")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: CGRect(origin: .zero, size: size),
            mappedBy: CGAffineTransform(translationX: 8, y: 0)), mode: .move)
        let placement = manager.celContentPlacement(forLayerID: manager.layers[0].id)
        let derived = try XCTUnwrap(manager.derivedCelContent(for: manager.layers[0].cels[0], atFrame: 0,
            inheriting: placement.backing), "PREMISE: a posed native drawing has a required derived provider")
        XCTAssertNil(derived.render(.full), "a present posed provider retains the same native material refusal")
        PixelOps.clearRasterizeCache()
        let posedRecipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false))
        XCTAssertTrue(posedRecipe.resolve().sourceResolutionFailed,
            "a refused present provider cannot fall back to its unposed stored drawing")
        manager.deleteLayer(at: 1)
        manager.addLayer()
        let layerIDs = manager.layers.map(\.id)
        manager.history.removeAll()
        XCTAssertFalse(manager.mergeLayers(layerIDs[0], layerIDs[1]), "native refusal prevents a destructive pixel merge")
        XCTAssertEqual(manager.layers.map(\.id), layerIDs, "refused merge restores both source layers")
        XCTAssertTrue(manager.layers[0].cels[0].vector === canvas, "refused merge retains the original native drawing")
        XCTAssertFalse(manager.history.canUndo, "refused merge adds no successful history entry")
    }

    @MainActor
    private func posedRasterRefusalFixture() -> CanvasManager {
        let manager = CanvasFixture.manager()
        manager.layers[0].cels[0].bakedImage = image()
        manager.addTransformLayer(name: "Raster pose")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: CGRect(origin: .zero, size: size),
            mappedBy: CGAffineTransform(translationX: 8, y: 0)), mode: .move)
        manager.currentLayerIndex = 0
        manager.history.removeAll()
        PixelOps.clearRasterizeCache()
        return manager
    }

    @MainActor
    func testPosedRasterRefusalPreservesSelectionAndSourceBeforeLiftOrDuplicate() throws {
        defer { CompositorBudget.budgetOverrideBytes = nil; PixelOps.clearRasterizeCache() }
        for duplicate in [false, true] {
            CompositorBudget.budgetOverrideBytes = nil
            let manager = posedRasterRefusalFixture()
            let original = manager.layers[0].cels[0]
            let loop = CGRect(x: 24, y: 14, width: 24, height: 24)
            manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop)
            let selection = try XCTUnwrap(manager.selection)
            XCTAssertNotNil(manager.inkPose(forLayerID: manager.layers[0].id), "PREMISE: the pixels are shown through a real pose")
            CompositorBudget.budgetOverrideBytes = 1
            if duplicate { manager.beginDuplicate() } else { manager.beginMove() }
            XCTAssertNil(manager.floatingPiece, "a refused posed picture cannot become an empty or partial lifted piece")
            XCTAssertEqual(manager.layers.count, 2, "refused Duplicate must not insert a layer")
            XCTAssertTrue(manager.layers[0].cels[0].raster === original.raster)
            XCTAssertTrue(manager.layers[0].cels[0].bakedImage === original.bakedImage)
            XCTAssertEqual(manager.selection?.path, selection.path, "refusal preserves the artist's selection")
            XCTAssertEqual(manager.history.currentCost, 0, "a refused lift records no document edit")
        }
    }

    @MainActor
    func testPosedRasterRefusalPreservesFloatingPictureAtLanding() throws {
        defer { CompositorBudget.budgetOverrideBytes = nil; PixelOps.clearRasterizeCache() }
        let manager = posedRasterRefusalFixture()
        let loop = CGRect(x: 24, y: 14, width: 24, height: 24)
        manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop)
        manager.beginMove()
        let piece = try XCTUnwrap(manager.floatingPiece, "PREMISE: an ordinary posed lift succeeds before resource pressure")
        XCTAssertNotNil(piece.landingPose)
        let selected = try XCTUnwrap(manager.selection)
        let source = manager.layers[0].cels[0]
        let history = manager.history.currentCost
        PixelOps.clearRasterizeCache()
        CompositorBudget.budgetOverrideBytes = 1
        XCTAssertFalse(manager.commitFloatingPieceIfNeeded(), "a refused inverse pose cannot complete the landing")
        XCTAssertTrue(manager.floatingPiece?.pieceImage === piece.pieceImage, "keep the actual held picture on screen")
        XCTAssertEqual(manager.floatingPiece?.transform, piece.transform)
        XCTAssertEqual(manager.selection?.path, selected.path)
        XCTAssertTrue(manager.layers[0].cels[0].raster === source.raster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === source.bakedImage)
        XCTAssertEqual(manager.history.currentCost, history)
    }

    @MainActor
    private func posedBakeRefusalFixture() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addLayer(name: "Pixels")
        manager.layers[0].cels[0].bakedImage = image()
        manager.addVectorLayer(name: "Native ink")
        manager.layers[1].cels[0].vector?.addStroke(VectorStroke(brush: TestBrushes.hardRound,
            color: .init(red: 0, green: 0, blue: 0, alpha: 1), size: 4, opacity: 1,
            samples: StrokeSamples([VectorSample(x: 12, y: 12), VectorSample(x: 24, y: 12)], channels: .pressureOnly)))
        manager.addTransformLayer(name: "Pose")
        manager.layers[2].transform = LayerPose(pose: PoseQuad(box: CGRect(origin: .zero, size: size),
            mappedBy: CGAffineTransform(translationX: 8, y: 0)), mode: .move)
        return manager
    }

    @MainActor
    func testPosedRasterRefusalRollsBackBakeWithoutConsumingPoseOrHistory() throws {
        defer { CompositorBudget.budgetOverrideBytes = nil; PixelOps.clearRasterizeCache() }
        let manager = posedBakeRefusalFixture()
        let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
        let baker = manager.layers[2].id, ids = manager.layers.map(\.id)
        let pixels = manager.layers[0].cels[0]
        let originalInk = vector.elements
        guard case .plan(let plan) = manager.bakePlan(forLayerID: baker) else { return XCTFail("PREMISE: the transform has a valid bake plan") }
        XCTAssertEqual(plan.layers.map(\.layerID), [manager.layers[1].id, manager.layers[0].id],
            "PREMISE: native ink is rewritten before the raster portion refuses")
        manager.history.removeAll(); PixelOps.clearRasterizeCache()
        CompositorBudget.budgetOverrideBytes = 1
        let result = manager.bakeLayer(id: baker)
        if case .baked = result { XCTFail("the failed raster portion must refuse the entire Bake") }
        XCTAssertEqual(manager.layers.map(\.id), ids, "the transform layer and every drawing remain")
        XCTAssertTrue(manager.layers[1].cels[0].vector === vector, "rollback also restores the native tier that ran before raster refusal")
        let restoredInk = manager.layers[1].cels[0].vector?.elements ?? []
        XCTAssertTrue(restoredInk.count == originalInk.count && zip(restoredInk, originalInk).allSatisfy {
            $0.id == $1.id && $0.hasSameSpatialInk(as: $1)
        }, "rollback restores the original native drawing")
        XCTAssertTrue(manager.layers[0].cels[0].raster === pixels.raster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === pixels.bakedImage)
        XCTAssertEqual(manager.history.currentCost, 0)
    }

    @MainActor
    func testPosedRasterRefusalRejectsCompositeRatherThanTreatingRequiredLeafAsEmpty() throws {
        defer { CompositorBudget.budgetOverrideBytes = nil; PixelOps.clearRasterizeCache() }
        let manager = posedRasterRefusalFixture()
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: false))
        guard case .cel(let required)? = recipe.leaves[0]?.content else { return XCTFail("PREMISE: the frame actually requires this cel") }
        XCTAssertNotNil(required.pose)
        XCTAssertNotNil(required.bakedImage, "PREMISE: required painted pixels are distinct from an empty leaf")
        XCTAssertNotNil(Compositor.composite(recipe.resolve(), resolving: .coreGraphics), "PREMISE: the same scene renders before resource pressure")
        PixelOps.clearRasterizeCache()
        CompositorBudget.budgetOverrideBytes = 1
        XCTAssertNil(Compositor.composite(recipe.resolve(), resolving: .coreGraphics),
            "required raster refusal reaches the existing optional frame result; a missing leaf is not transparency")
        let empty = CanvasFixture.manager()
        let emptyRecipe = try XCTUnwrap(empty.makeFrameRecipe(atFrame: 0, includeBackground: false))
        XCTAssertNotNil(Compositor.composite(emptyRecipe.resolve(), resolving: .coreGraphics),
            "an actually empty leaf remains a valid transparent frame under the same budget")
    }

    @MainActor
    func testPosedRasterRefusalPreservesLiquifyPixelsAndHistory() throws {
        defer { CompositorBudget.budgetOverrideBytes = nil; PixelOps.clearRasterizeCache() }
        let manager = posedRasterRefusalFixture()
        let original = manager.layers[0].cels[0]
        let session = try held(manager, layer: 0)
        XCTAssertNotNil(session.placement.backing, "PREMISE: the completed Liquify picture needs a posed raster window")
        CompositorBudget.budgetOverrideBytes = 1
        manager.commitLiquify(session)
        XCTAssertTrue(manager.layers[0].cels[0].raster === original.raster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === original.bakedImage)
        XCTAssertEqual(manager.history.currentCost, 0, "a refused private replacement never lands pixels or an undo record")
    }

    @MainActor
    func testNestedBakeRefusalRestoresItsEntryStateAndPreservesPendingCrop() throws {
        defer { CompositorBudget.budgetOverrideBytes = nil; PixelOps.clearRasterizeCache() }
        let manager = posedBakeRefusalFixture()
        let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
        manager.layers[1].name = "Before gesture"
        guard case .plan(let plan) = manager.bakePlan(forLayerID: manager.layers[2].id) else { return XCTFail("valid Bake") }
        XCTAssertEqual(plan.layers.map(\.layerID), [manager.layers[1].id, manager.layers[0].id],
            "PREMISE: the failed transaction has already changed native ink")
        manager.history.removeAll()
        manager.beginStructureGesture()
        manager.layers[1].name = "Earlier gesture edit"
        var crop = KeyframeCrop()
        crop.record(channel: "cel.x", frames: [8])
        manager.noteKeyframeCrop(crop)
        XCTAssertNotNil(manager.gestureSnapshot, "PREMISE: the enclosing gesture owns its own baseline")
        CompositorBudget.budgetOverrideBytes = 1
        if case .baked = manager.bakeLayer(id: manager.layers[2].id) { XCTFail("nested Bake must decline") }
        XCTAssertTrue(manager.layers[1].cels[0].vector === vector, "a failed nested Bake restores its entry drawing")
        XCTAssertEqual(manager.layers[1].name, "Earlier gesture edit", "rollback must not consume the enclosing gesture's earlier edit")
        XCTAssertEqual(manager.pendingKeyframeCrop, crop, "rollback preserves a crop already owned by the enclosing gesture")
        XCTAssertNotNil(manager.gestureSnapshot, "the enclosing gesture remains open")
        XCTAssertEqual(manager.history.currentCost, 0)
        CompositorBudget.budgetOverrideBytes = nil
        manager.commitStructureGesture(label: .renameLayer)
        XCTAssertEqual(manager.history.undo(), .renameLayer)
        XCTAssertEqual(manager.layers[1].name, "Before gesture")
        XCTAssertTrue(manager.layers[1].cels[0].vector === vector)
        XCTAssertNil(manager.history.undo(), "only the earlier gesture was recorded")
    }

    @MainActor
    func testLandingAllocationRefusalKeepsHeldPixelsAndAcceptsValidTransparency() throws {
        defer { CompositorBudget.availableMemoryOverrideBytes = nil }
        let blank = CanvasFixture.manager()
        blank.beginMove()
        XCTAssertNotNil(blank.floatingPiece, "PREMISE: transparent pixels can be a valid held image")
        XCTAssertTrue(blank.commitFloatingPieceIfNeeded())
        XCTAssertTrue(blank.layers[0].cels[0].raster.hasContent,
            "a valid transparent landing owns an allocated context")

        let manager = CanvasFixture.manager()
        manager.layers[0].cels[0].bakedImage = image()
        manager.history.removeAll()
        manager.beginMove()
        let piece = try XCTUnwrap(manager.floatingPiece)
        XCTAssertNil(piece.landingPose, "PREMISE: this checks the final texture allocation after unposed rendering")
        let original = manager.layers[0].cels[0]
        CompositorBudget.availableMemoryOverrideBytes = 1
        XCTAssertFalse(manager.commitFloatingPieceIfNeeded())
        XCTAssertTrue(manager.floatingPiece?.pieceImage === piece.pieceImage)
        XCTAssertTrue(manager.layers[0].cels[0].raster === original.raster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === original.bakedImage)
        XCTAssertEqual(manager.history.currentCost, 0)
    }

    @MainActor
    func testRefusedLandingSurvivesAnotherMoveDuplicateOrBake() throws {
        defer { CompositorBudget.availableMemoryOverrideBytes = nil }
        for action in ["move", "duplicate", "bake"] {
            CompositorBudget.availableMemoryOverrideBytes = nil
            let manager = CanvasFixture.manager(layerCount: 0)
            manager.addVectorLayer(name: "Native ink")
            let vector = try XCTUnwrap(manager.layers[0].cels[0].vector)
            vector.addStroke(VectorStroke(brush: TestBrushes.hardRound,
                color: .init(red: 0, green: 0, blue: 0, alpha: 1), size: 4, opacity: 1,
                samples: StrokeSamples([VectorSample(x: 12, y: 12), VectorSample(x: 24, y: 12)], channels: .pressureOnly)))
            manager.addTransformLayer(name: "Native pose")
            manager.layers[1].transform = LayerPose(pose: PoseQuad(box: CGRect(origin: .zero, size: size),
                mappedBy: CGAffineTransform(translationX: 8, y: 0)), mode: .move)
            let baker = manager.layers[1].id
            manager.addLayer(name: "Held pixels")
            manager.layers[2].cels[0].bakedImage = image()
            manager.currentLayerIndex = 2
            let loop = CGRect(x: 24, y: 14, width: 24, height: 24)
            manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop)
            manager.beginMove()
            manager.floatingPiece?.transform.position.x += 5
            manager.floatingPiece?.transform.position.y += 3
            let piece = try XCTUnwrap(manager.floatingPiece)
            XCTAssertNil(piece.landingPose, "PREMISE: held pixels sit above the native-only Bake scope")
            guard case .plan(let plan) = manager.bakePlan(forLayerID: baker) else { return XCTFail("valid native Bake") }
            XCTAssertEqual(plan.layers.map(\.layerID), [manager.layers[0].id])
            let ids = manager.layers.map(\.id), selected = manager.selection?.path
            manager.history.removeAll()
            CompositorBudget.availableMemoryOverrideBytes = 1
            switch action {
            case "move": manager.beginMove()
            case "duplicate": manager.beginDuplicate()
            default:
                if case .baked = manager.bakeLayer(id: baker) { XCTFail("Bake must wait for the held pixels to land") }
            }
            XCTAssertTrue(manager.floatingPiece?.pieceImage === piece.pieceImage, "\(action) keeps the refused held picture")
            XCTAssertEqual(manager.floatingPiece?.transform, piece.transform, "\(action) preserves its displacement")
            XCTAssertEqual(manager.layers.map(\.id), ids, "\(action) cannot insert or remove a layer after refusal")
            XCTAssertTrue(manager.layers[0].cels[0].vector === vector, "\(action) cannot rewrite native ink after refusal")
            XCTAssertEqual(manager.selection?.path, selected)
            XCTAssertEqual(manager.currentLayerIndex, 2)
            XCTAssertEqual(manager.history.currentCost, 0)
        }
    }

    @MainActor
    func testRefusedLandingPreservesDocumentContextSizeAndTool() throws {
        defer { CompositorBudget.availableMemoryOverrideBytes = nil }
        for action in ["resize", "frame", "layer", "eyedropper", "delete"] {
            CompositorBudget.availableMemoryOverrideBytes = nil
            let manager = CanvasFixture.manager(layerCount: 2)
            manager.currentLayerIndex = 0
            manager.layers[0].cels[0].bakedImage = image()
            manager.beginMove()
            manager.floatingPiece?.transform.position.x += 5
            let piece = try XCTUnwrap(manager.floatingPiece), original = manager.layers[0].cels[0]
            let canvasSize = manager.canvasSize, tool = manager.selectedTool, ids = manager.layers.map(\.id)
            XCTAssertNil(manager.activeCelID(inLayer: 0, atFrame: original.endFrame),
                "PREMISE: the frame action leaves the held cel rather than ticking inside it")
            manager.history.removeAll()
            CompositorBudget.availableMemoryOverrideBytes = 1
            switch action {
            case "resize": XCTAssertFalse(manager.resizeCanvas(to: CGSize(width: 96, height: 96)))
            case "frame": manager.currentFrame = original.endFrame
            case "layer": manager.currentLayerIndex = 1
            case "delete": manager.deleteLayer(at: 0)
            default: manager.selectEyedropper()
            }
            XCTAssertEqual(manager.canvasSize, canvasSize, "\(action) must wait for the held landing")
            XCTAssertEqual(manager.currentLayerIndex, 0)
            XCTAssertEqual(manager.currentFrame, 0)
            XCTAssertEqual(manager.selectedTool, tool)
            XCTAssertEqual(manager.layers.map(\.id), ids)
            XCTAssertTrue(manager.floatingPiece?.pieceImage === piece.pieceImage)
            XCTAssertEqual(manager.floatingPiece?.transform, piece.transform)
            XCTAssertTrue(manager.layers[0].cels[0].raster === original.raster)
            XCTAssertTrue(manager.layers[0].cels[0].bakedImage === original.bakedImage)
            XCTAssertEqual(manager.history.currentCost, 0)
        }
    }

    @MainActor
    func testRefusedLandingDoesNotSnapshotOrCompleteSave() throws {
        defer { CompositorBudget.availableMemoryOverrideBytes = nil }
        let manager = CanvasFixture.manager()
        manager.layers[0].cels[0].bakedImage = image()
        manager.beginMove()
        manager.floatingPiece?.transform.position.x += 5
        let piece = try XCTUnwrap(manager.floatingPiece)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Held.paintproj")
        let finished = expectation(description: "save accepts or refuses")
        var failed = false, completed = false
        CompositorBudget.availableMemoryOverrideBytes = 1
        _ = ProjectStore.save(manager, to: url, onSaveFailed: {
            failed = true; finished.fulfill()
        }, completion: {
            completed = true; finished.fulfill()
        })
        wait(for: [finished], timeout: 30)
        XCTAssertTrue(failed, "the actual save entry refuses its snapshot while pixels cannot land")
        XCTAssertFalse(completed, "the gallery completion cannot discard an unresolved held picture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(manager.floatingPiece?.pieceImage === piece.pieceImage)
        XCTAssertEqual(manager.floatingPiece?.transform, piece.transform)
    }

    @MainActor
    func testLiquifyFinalAllocationRefusalPreservesSourceAndHistory() throws {
        defer { CompositorBudget.availableMemoryOverrideBytes = nil }
        let manager = CanvasFixture.manager()
        manager.layers[0].cels[0].bakedImage = image()
        manager.history.removeAll()
        let source = manager.layers[0].cels[0]
        let session = try held(manager, layer: 0)
        XCTAssertNil(session.placement.backing, "PREMISE: the final allocation follows an unposed pixel picture")
        CompositorBudget.availableMemoryOverrideBytes = 1
        manager.commitLiquify(session)
        XCTAssertTrue(manager.layers[0].cels[0].raster === source.raster)
        XCTAssertTrue(manager.layers[0].cels[0].bakedImage === source.bakedImage)
        XCTAssertEqual(manager.history.currentCost, 0)
    }

    func testFrozenReplacementStampsOnlyRewrittenInkInsideTheWindow() throws {
        let canvas = VectorCanvas(size: CGSize(width: 256, height: 256))
        func mark(_ y: CGFloat) -> VectorStroke {
            VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 3, opacity: 1,
                samples: StrokeSamples([VectorSample(x: 10, y: y), VectorSample(x: 230, y: y)], channels: .pressureOnly))
        }
        let target = mark(48)
        canvas.addStroke(target)
        for y in 80..<180 { canvas.addStroke(mark(CGFloat(y))) }
        _ = canvas.render()
        var replacement = canvas.elements
        guard case .stroke(var changed) = replacement[0] else { return XCTFail("ink") }
        changed.samples = mark(16).samples
        changed.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        replacement[0] = .stroke(changed)
        let window = CGRect(x: 0, y: 8, width: 240, height: 16)
        let frozen = canvas.freezeDisplay(quality: .full, referenceIDs: [], replacing: replacement, rewriting: [target.id])
        var work: Int?, oneStrokeWork: Int?
        let actual = UIGraphicsImageRenderer(size: window.size, format: PixelOps.transparentFormat()).image { ctx in
            work = frozen.draw(into: ctx.cgContext, frameRect: CGRect(x: 0, y: -window.minY, width: 256, height: 256), quality: .full)
        }
        let one = VectorCanvas(size: CGSize(width: 256, height: 256), elements: [.stroke(changed)]).freeze(quality: .full)
        let expected = UIGraphicsImageRenderer(size: window.size, format: PixelOps.transparentFormat()).image { ctx in
            oneStrokeWork = one.draw(into: ctx.cgContext, frameRect: CGRect(x: 0, y: -window.minY, width: 256, height: 256), quality: .full)
        }
        let measured = try XCTUnwrap(work), oneMeasured = try XCTUnwrap(oneStrokeWork)
        XCTAssertGreaterThan(oneMeasured, 0, "PREMISE: the rewritten stroke is really stamped")
        XCTAssertEqual(measured, oneMeasured, "100 distant measured strokes must cost no extra dabs on a held tick")
        XCTAssertEqual(try bytes(actual), try bytes(expected), "changed ink cannot reuse its stale footprint/content")
    }

    @MainActor
    func testDelayedBaseCoverageSurvivesDisplayTicksAndSupersededRequests() throws {
        let manager = CanvasFixture.manager(); manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        let stream = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8), host: "fixture", port: 47301,
            sourceLabel: "fixture", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 55, y: 55), scale: 1, rotation: 0))
        canvas.elements = [.stream(stream)]; canvas.bumpVersion()
        let revisions = CelContentRevisions(); revisions.observe(manager.layers[1].cels[0])
        func addMark(_ y: CGFloat) {
            canvas.addStroke(VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 3, opacity: 1,
                samples: StrokeSamples([VectorSample(x: 10, y: y), VectorSample(x: 20, y: y)], channels: .pressureOnly)))
            revisions.observe(manager.layers[1].cels[0])
        }
        addMark(10)
        let firstCoverage = CelContentCoverage(celID: manager.layers[1].cels[0].id, revision: revisions.current)
        var ink = UnlandedInk()
        let window = CGRect(x: 0, y: 0, width: 8, height: 8)
        ink.hold(.init(id: 1, version: firstCoverage.revision, windowRect: window, alpha: 1, replacesBase: true, image: image()))
        let view = WindowSurfaceView(queue: DispatchQueue(label: "LiquifyRasterLogicTests.delayed"))
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let first = expectation(description: "old content lands"), last = expectation(description: "latest content lands")
        view.present(window: window, placement: .identity, draw: { _ in
            started.signal(); _ = release.wait(timeout: .now() + 10); return window
        }, finished: { shown in
            XCTAssertTrue(shown)
            ink.retire(upTo: firstCoverage.revision)
            XCTAssertEqual(ink.pictures.map(\.id), [2], "old base covers its own commit, never a newer one")
            first.fulfill()
        })
        XCTAssertEqual(started.wait(timeout: .now() + 10), .success)
        let frame = image(.blue)
        for index in 0..<100 {
            canvas.setStreamFrame(id: stream.id, image: frame, index: index)
            XCTAssertEqual(revisions.committed(canvas), firstCoverage.revision)
            revisions.observe(manager.layers[1].cels[0])
        }
        addMark(20)
        let latestCoverage = CelContentCoverage(celID: manager.layers[1].cels[0].id, revision: revisions.current)
        ink.hold(.init(id: 2, version: latestCoverage.revision, windowRect: window, alpha: 1, replacesBase: true, image: image(.green)))
        view.present(window: window, placement: .identity, draw: { _ in XCTFail("superseded request must never draw"); return window },
                     finished: { _ in XCTFail("a cancelled waiting request has no landing") })
        view.present(window: window, placement: .identity, draw: { _ in window }, finished: { shown in
            XCTAssertTrue(shown); ink.retire(upTo: latestCoverage.revision)
            XCTAssertTrue(ink.isEmpty, "the latest frozen base retires both skipped and current commits")
            last.fulfill()
        })
        release.signal()
        wait(for: [first, last], timeout: 10)
    }

    func testReusedDerivedInkRequiresInstalledBackingVersionBeforeCoveringANewPose() throws {
        var cel = CanvasFixture.manager().layers[0].cels[0]
        let oldBaked = image(.red), freshBaked = image(.green), ink = image(.blue)
        cel.bakedImage = oldBaked
        let raster = cel.raster
        let shownVersion = raster.version
        let revisions = CelContentRevisions()
        let oldPose = CelContentPlacement.identity
        let newPose = CelContentPlacement(ink: nil, backing: .affine(CGAffineTransform(translationX: 9, y: 4)))
        let oldCoverage = try XCTUnwrap(revisions.captureDisplayedCoverage(of: cel,
            bakedImage: oldBaked, raster: raster, rasterVersion: shownVersion,
            placement: oldPose, derivation: "unchanged-linked-ink"))
        var presentation = DerivedCelPresentation()
        XCTAssertEqual(presentation.install(ink, covering: oldCoverage, on: cel.id), .changed)
        raster.stampCircle(at: CGPoint(x: 30, y: 30), radius: 5, color: .yellow, alpha: 1, hardness: 1)
        cel.bakedImage = freshBaked
        let pending = revisions.observe(cel)
        let newPixels = try bytes(raster.renderToUIImage())
        XCTAssertGreaterThan(raster.version, shownVersion, "the same texture really changed in place")
        func reuse(baked: UIImage?, version: Int) -> Bool {
            guard let coverage = revisions.captureDisplayedCoverage(of: cel, bakedImage: baked,
                raster: raster, rasterVersion: version, placement: newPose,
                derivation: "unchanged-linked-ink") else { return false }
            return presentation.install(ink, covering: coverage, on: cel.id, aimingAt: newPose,
                preservingPendingThrough: pending) != .rejected
        }
        XCTAssertFalse(reuse(baked: freshBaked, version: shownVersion),
            "object identity cannot certify newly painted pixels before their version is displayed")
        XCTAssertTrue(presentation.image === ink)
        XCTAssertEqual(presentation.coverage, oldCoverage, "image, linked key and old placement remain paired")
        XCTAssertFalse(reuse(baked: oldBaked, version: raster.version), "the baked sibling must also have landed")
        XCTAssertEqual(presentation.coverage, oldCoverage)
        let installedRaster = raster.renderToUIImage()
        XCTAssertEqual(try bytes(installedRaster), newPixels)
        XCTAssertTrue(reuse(baked: freshBaked, version: raster.version))
        XCTAssertTrue(presentation.image === ink, "unchanged linked ink needs no second render")
        XCTAssertEqual(presentation.coverage, CelContentCoverage(celID: cel.id, revision: pending,
            placement: newPose, derivation: "unchanged-linked-ink"))
        let replacement = RasterLayerTexture(size: size)
        XCTAssertNil(revisions.captureDisplayedCoverage(of: cel, bakedImage: freshBaked,
            raster: replacement, rasterVersion: raster.version, placement: newPose,
            derivation: "unchanged-linked-ink"), "another texture with a matching version is not the installed source")
    }

    func testDerivedPlacementWaitsForPendingCoverageAndCannotRollBackANewerPose() throws {
        let cel = UUID()
        let oldPose = CelContentPlacement(ink: .affine(CGAffineTransform(translationX: 8, y: 3)),
            backing: .affine(CGAffineTransform(translationX: 4, y: 1)))
        let newPose = CelContentPlacement(ink: .affine(CGAffineTransform(scaleX: 0.8, y: 0.9)),
            backing: .affine(CGAffineTransform(rotationAngle: 0.2)))
        let old = image(.red), intermediate = image(.green), fresh = image(.blue), tint = image(.yellow)
        var presentation = DerivedCelPresentation()
        let first = CelContentCoverage(celID: cel, revision: 1, placement: oldPose, derivation: "old")
        XCTAssertEqual(presentation.install(old, covering: first, on: cel, aimingAt: oldPose), .changed)
        let uncoveredPose = CelContentCoverage(celID: cel, revision: 2, placement: newPose, derivation: "uncovered")
        XCTAssertEqual(presentation.install(fresh, covering: uncoveredPose, on: cel, aimingAt: newPose,
            preservingPendingThrough: 3), .rejected, "a new pose cannot strand newer ink held at the old pose")
        XCTAssertTrue(presentation.image === old)
        XCTAssertEqual(presentation.coverage, first)
        let advance = CelContentCoverage(celID: cel, revision: 2, placement: oldPose, derivation: "advance")
        XCTAssertEqual(presentation.install(intermediate, covering: advance, on: cel, aimingAt: newPose,
            preservingPendingThrough: 3), .changed, "content may advance at the still-shown pose while its replacement waits")
        XCTAssertTrue(presentation.image === intermediate)
        let covered = CelContentCoverage(celID: cel, revision: 3, placement: newPose, derivation: "fresh")
        XCTAssertEqual(presentation.install(fresh, covering: covered, on: cel, aimingAt: newPose,
            preservingPendingThrough: 3), .changed, "a skipped intermediate base may cover every pending picture")
        XCTAssertTrue(presentation.image === fresh)
        XCTAssertEqual(presentation.coverage, covered)
        let failedCoverage = CelContentCoverage(celID: cel, revision: 4, placement: newPose, derivation: "failed")
        XCTAssertEqual(presentation.installRendered(nil, covering: failedCoverage, on: cel, aimingAt: newPose), .rejected,
            "delayed render failure cannot certify pixels it never produced")
        XCTAssertTrue(presentation.image === fresh)
        XCTAssertEqual(presentation.coverage, covered)
        let lateOldPose = CelContentCoverage(celID: cel, revision: 4, placement: oldPose, derivation: "late")
        XCTAssertEqual(presentation.install(old, covering: lateOldPose, on: cel, aimingAt: newPose), .rejected,
            "even newer content cannot restore an obsolete pose over the installed picture")
        XCTAssertTrue(presentation.image === fresh)
        XCTAssertEqual(presentation.coverage, covered)
        XCTAssertEqual(presentation.install(tint, covering: covered, on: cel, aimingAt: newPose), .changed,
            "same-coverage tint or pose refresh remains legal")
        XCTAssertTrue(presentation.image === tint)
        XCTAssertEqual(presentation.install(intermediate, covering: uncoveredPose, on: cel, aimingAt: newPose), .rejected)
        XCTAssertTrue(presentation.image === tint)
        XCTAssertEqual(presentation.coverage, covered)
        XCTAssertEqual(presentation.install(nil, covering: nil, on: cel), .changed, "intentional clear remains legal")
        XCTAssertNil(presentation.image)
        XCTAssertNil(presentation.coverage)
    }

    @MainActor
    func testLateDerivedPictureForAReplacedCelCannotOverwriteTheNewCelPresentation() throws {
        let celA = UUID(), celB = UUID()
        let delayedA = image(.red), installedB = image(.green)
        let aCoverage = CelContentCoverage(celID: celA, revision: 1)
        let bCoverage = CelContentCoverage(celID: celB, revision: 3)
        var presentation = DerivedCelPresentation()
        XCTAssertEqual(presentation.install(installedB, covering: bCoverage, on: celB), .changed)
        XCTAssertEqual(presentation.install(delayedA, covering: aCoverage, on: celB), .rejected,
                       "a delayed mint for deleted cel A cannot replace cel B at the same layer/frame")
        XCTAssertTrue(presentation.image === installedB, "the actual displayed-picture slot stays B's")
        XCTAssertEqual(presentation.coverage, bCoverage, "rejecting A must not clear B's retirement coverage")
        let updates = LatestWins(queue: DispatchQueue(label: "LiquifyRasterLogicTests.replacedCel"))
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let latest = expectation(description: "replacement cel's newest image lands")
        updates.request {
            {
                started.signal(); _ = release.wait(timeout: .now() + 10)
                return {
                    XCTFail("cancelled derived result must not reach its installer")
                    _ = presentation.install(delayedA, covering: aCoverage, on: celB)
                }
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 10), .success)
        updates.cancel()
        let latestB = image(.yellow), latestCoverage = CelContentCoverage(celID: celB, revision: 4)
        updates.request {
            { {
                XCTAssertEqual(presentation.install(latestB, covering: latestCoverage, on: celB), .changed)
                latest.fulfill()
            } }
        }
        release.signal()
        wait(for: [latest], timeout: 10)
        XCTAssertTrue(presentation.image === latestB)
        XCTAssertEqual(presentation.coverage, latestCoverage)
        let earlierB = image(.blue)
        let earlierCoverage = CelContentCoverage(celID: celB, revision: 2)
        XCTAssertEqual(presentation.install(earlierB, covering: earlierCoverage, on: celB), .rejected,
                       "an older result cannot roll back a newer image whose pending paint was retired")
        XCTAssertTrue(presentation.image === latestB)
        XCTAssertEqual(presentation.coverage, latestCoverage)
        let advancingB = image(.red), advancingCoverage = CelContentCoverage(celID: celB, revision: 5)
        XCTAssertEqual(presentation.install(advancingB, covering: advancingCoverage, on: celB), .changed,
                       "a result newer than the shown picture may advance it even while the model is further ahead")
        let retintedB = image(.green)
        XCTAssertEqual(presentation.install(retintedB, covering: advancingCoverage, on: celB), .changed,
                       "equal content coverage still allows a new pose or tint picture")
        XCTAssertTrue(presentation.image === retintedB)
        XCTAssertEqual(presentation.coverage, advancingCoverage)
        XCTAssertEqual(presentation.install(retintedB, covering: advancingCoverage, on: celB), .unchanged)
        XCTAssertEqual(presentation.install(nil, covering: nil, on: celB), .changed, "clearing a derivation remains an accepted update")
        XCTAssertNil(presentation.image)
        XCTAssertNil(presentation.coverage)
    }

    func testRecipeWindowMatchesFullFadeAndLocalEraseAtNonzeroOrigin() throws {
        let a = VectorImageElement(image: image(), transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
        let b = VectorImageElement(image: image(.green), transform: LayerTransform(position: CGPoint(x: 34, y: 33), scale: 1, rotation: 0))
        var erase = VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 5, opacity: 0.6,
            samples: StrokeSamples([VectorSample(x: 24, y: 22), VectorSample(x: 28, y: 26)], channels: .pressureOnly))
        erase.composite = .erase
        let evaluation = InterpolationEvaluator.Evaluation(forward: [.image(a)], backward: [.image(b)], localEdits: [.stroke(erase)], forwardWeight: 0.37, backwardWeight: 0.63)
        let window = CGRect(x: 17, y: 13, width: 28, height: 30)
        let full = try XCTUnwrap(InterpolationEvaluator.composite(evaluation, size: size))
        let crop = UIGraphicsImageRenderer(size: window.size, format: PixelOps.transparentFormat()).image { _ in full.draw(at: CGPoint(x: -window.minX, y: -window.minY)) }
        XCTAssertEqual(try bytes(XCTUnwrap(InterpolationEvaluator.composite(evaluation, size: size, window: window))), try bytes(crop), "window origin, fade and local eraser preserve the full picture")
    }
    func testSkippedMixedCommitRetiresEarlierReplacementsAcrossTextureVersionZero() {
        let manager = CanvasFixture.manager(); manager.addVectorLayer()
        var cel = manager.layers[1].cels[0]
        let revisions = CelContentRevisions()
        let start = revisions.observe(cel)
        cel.bakedImage = image(); cel.raster = RasterLayerTexture(size: size)
        let first = revisions.observe(cel)
        var ink = UnlandedInk()
        ink.hold(.init(id: 1, version: first, windowRect: CGRect(x: 10, y: 10, width: 20, height: 20), alpha: 1, replacesBase: true, image: image()))
        cel.bakedImage = image(.green); cel.raster = RasterLayerTexture(size: size)
        let latest = revisions.observe(cel)
        ink.hold(.init(id: 2, version: latest, windowRect: CGRect(x: 15, y: 15, width: 20, height: 20), alpha: 1, replacesBase: true, image: image(.green)))
        XCTAssertGreaterThan(first, start); XCTAssertGreaterThan(latest, first)
        XCTAssertEqual(ink.pictures.count, 2)
        ink.retire(upTo: revisions.committed(cel.vector!))
        XCTAssertTrue(ink.isEmpty, "LatestWins may skip the first mixed commit and land directly on the second")
    }
}
