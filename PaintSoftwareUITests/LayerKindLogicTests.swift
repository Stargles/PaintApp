import XCTest
import UIKit

/// **Every `LayerKind` through every site that switches on it** — TRANSFORM_LAYER.md §2 ruling 2's
/// fourth kind, and the test that makes a fifth one answer everywhere rather than only where the
/// compiler is looking.
///
/// `LayerKind`'s own doc names the exhaustive switches: `holdsPixels`, `Tool.textUnavailableReason`,
/// `CanvasManager.selectionMembershipUnavailableReason` and `CanvasActiveLayer.init(kind:)`. The
/// compiler makes each of those answer for a new case; what it cannot check is that the *answers
/// agree* — that a kind `holdsPixels` says is pixel-less is one text refuses, one the lasso refuses,
/// one the touch owner routes to no surface, and one `Layer.hasNoDrawingSurface` / `isFillReference`
/// read the same way. Those five used to be five spellings of `kind == .value`, and the day a second
/// pixel-less kind arrived each spelling had to be found by hand. This walks `allCases` through all
/// of them so the next kind is found by a red test instead.
///
/// The raw-value round trip and the two decode migrations are here too, since they are the other
/// places a kind's *name* is load-bearing.
@MainActor
final class LayerKindLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }

    /// One layer of each kind, in a document of its own, made the way the app makes it.
    private func manager(with kind: LayerKind) -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = size
        switch kind {
        case .raster: manager.addLayer()
        case .vector: manager.addVectorLayer()
        case .value: manager.addValueLayer()
        case .transform: manager.addTransformLayer()
        }
        manager.currentLayerIndex = manager.layers.count - 1
        return manager
    }

    /// **The four kinds, and which two draw.** Stated as data so the table below is legible; a fifth
    /// case fails the count before it fails anything subtler.
    func testTheKindsAndWhichOnesHoldPixels() {
        XCTAssertEqual(LayerKind.allCases, [.raster, .vector, .value, .transform])
        XCTAssertEqual(LayerKind.allCases.filter(\.holdsPixels), [.raster, .vector])
    }

    /// **Every site that answers "does this layer have a drawing surface" agrees with `holdsPixels`.**
    /// Watched failing with `.transform` moved to the `true` arm of `holdsPixels` (the text and lasso
    /// refusals disagreed with it), and with `CanvasActiveLayer.init` returning `.raster` for
    /// `.transform` (the touch owner disagreed).
    func testEverySwitchOverTheKindAgreesWithHoldsPixels() {
        for kind in LayerKind.allCases {
            let m = manager(with: kind)
            let layer = m.layers[m.currentLayerIndex]
            XCTAssertEqual(layer.kind, kind, "Fixture: the constructor for \(kind) makes a \(kind) layer")
            let holds = kind.holdsPixels

            XCTAssertEqual(layer.hasNoDrawingSurface, !holds, "`Layer.hasNoDrawingSurface` on \(kind)")
            XCTAssertEqual(layer.isFillReference, holds,
                           "A visible \(kind) layer is a fill wall exactly when it holds pixels")
            XCTAssertEqual(Tool.textUnavailableReason(onLayerOfKind: kind) == nil, holds,
                           "Text lands on \(kind) exactly when it holds pixels")
            XCTAssertEqual(m.selectionMembershipUnavailableReason == nil || kind == .raster, holds,
                           "The lasso's membership picker refuses \(kind) unless it holds pixels — "
                           + "a raster layer is refused for its own reason (cut only)")
            XCTAssertEqual(CanvasActiveLayer(kind: kind).hasNoDrawingSurface, !holds,
                           "The touch owner routes \(kind) to no drawing surface exactly when it holds none")
            XCTAssertTrue(CanvasActiveLayer(kind: kind).exists, "…but it exists, whatever it holds")
        }
    }

    /// **Only one kind grades, only one poses, and neither is a kind that draws.** The three
    /// accessors are the render path's whole reading of a layer; a kind that answered two of them, or
    /// a drawing kind that answered any, would be the forty-rows-that-set-nothing trap in reverse.
    func testEachPixelLessKindAnswersExactlyOneOfTheThreeAccessors() {
        for kind in LayerKind.allCases {
            let m = manager(with: kind)
            var layer = m.layers[m.currentLayerIndex]
            // Give every layer every payload, so the kind alone decides what is read.
            layer.effect = .posterize(Effect.Posterize())
            layer.fill = ValueFill()
            layer.transform = m.restingContainerPose
            let answers = [layer.layerEffect != nil, layer.valueFill != nil, layer.layerTransform != nil]
            switch kind {
            case .raster, .vector: XCTAssertEqual(answers, [false, false, false], "\(kind) draws pixels and reads no payload")
            case .value: XCTAssertEqual(answers, [true, false, false], "a value layer with a grade grades — and its fill is inert under it")
            case .transform: XCTAssertEqual(answers, [false, false, true], "a transform layer poses, whatever else it carries")
            }
        }
    }

    /// **The raw value is the document's spelling, so it round-trips for every case** — and the
    /// decoder that migrates the retired `"compositing"` string reads every live one unchanged.
    func testEveryKindRoundTripsThroughItsRawValueAndTheMigratingDecoder() throws {
        struct Box: Codable { let kind: LayerKind }
        for kind in LayerKind.allCases {
            XCTAssertEqual(LayerKind(rawValue: kind.rawValue), kind)
            let data = try JSONEncoder().encode(Box(kind: kind))
            XCTAssertEqual(try JSONDecoder().decode(Box.self, from: data).kind, kind, "\(kind) round-trips")
            XCTAssertEqual(String(data: data, encoding: .utf8), "{\"kind\":\"\(kind.rawValue)\"}",
                           "…as its raw value, which is what the manifest holds")
        }
        XCTAssertEqual(LayerKind.transform.rawValue, "transform",
                       "The spelling an older build cannot read — TRANSFORM_LAYER.md §2 ruling 2 says so")
    }

    /// **The transform-layer migration, as a function.** A value layer with a pose and no grade is a
    /// transform layer; with a grade it stays a value layer; every other kind is untouched whatever
    /// it carries. Watched failing with the function returning `kind` unchanged.
    func testMigratingTransformModeValueLayersRewritesExactlyOneShape() {
        let pose = LayerPose(restingIn: CGRect(origin: .zero, size: size))
        let grade = Effect.posterize(Effect.Posterize())
        XCTAssertEqual(LayerKind.migratingTransformModeValueLayers(.value, effect: nil, transform: pose), .transform)
        XCTAssertEqual(LayerKind.migratingTransformModeValueLayers(.value, effect: grade, transform: pose), .value)
        XCTAssertEqual(LayerKind.migratingTransformModeValueLayers(.value, effect: nil, transform: nil), .value)
        for kind in LayerKind.allCases where kind != .value {
            XCTAssertEqual(LayerKind.migratingTransformModeValueLayers(kind, effect: nil, transform: pose), kind)
            XCTAssertEqual(LayerKind.migratingTransformModeValueLayers(kind, effect: grade, transform: pose), kind)
        }
    }

    /// **A transform layer is named and labelled as one** — the row an artist reads their stack on,
    /// and the undo history's sentence. `addTransformLayer` is the only writer of either.
    func testATransformLayerIsNamedAndItsAddIsLabelled() {
        let m = manager(with: .transform)
        XCTAssertEqual(m.layers[m.currentLayerIndex].name, "Transform 1")
        XCTAssertEqual(m.history.undoStack.last?.label, .addTransformLayer)
        XCTAssertEqual(HistoryActionLabel.addTransformLayer.phrase, "add transform layer")
    }
}
