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

    /// **Two kinds grade, one poses, and no kind answers two of the three accessors.** The three
    /// accessors are the render path's whole reading of a layer; a kind that answered two of them
    /// would be the forty-rows-that-set-nothing trap in reverse. The vector layer is the one drawing
    /// kind that grades (TODO (92), `LayerKind.carriesEffect`) — through its own ink, which is why a
    /// drawing kind can: the pixels it holds are the mask, not a second thing the grade competes
    /// with. The raster layer still reads no payload.
    func testEachKindAnswersAtMostOneOfTheThreeAccessors() {
        for kind in LayerKind.allCases {
            let m = manager(with: kind)
            var layer = m.layers[m.currentLayerIndex]
            // Give every layer every payload, so the kind alone decides what is read.
            layer.effect = .posterize(Effect.Posterize())
            layer.fill = ValueFill()
            layer.transform = m.restingContainerPose
            let answers = [layer.layerEffect != nil, layer.valueFill != nil, layer.layerTransform != nil]
            switch kind {
            case .raster: XCTAssertEqual(answers, [false, false, false], "a raster layer draws pixels and reads no payload")
            case .vector: XCTAssertEqual(answers, [true, false, false], "a vector layer with a grade grades, through its ink")
            case .value: XCTAssertEqual(answers, [true, false, false], "a value layer with a grade grades — and its fill is inert under it")
            case .transform: XCTAssertEqual(answers, [false, false, true], "a transform layer poses, whatever else it carries")
            }
            XCTAssertEqual(layer.layerEffect != nil, kind.carriesEffect, "\(kind): the accessor and the kind's own answer agree")
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

    /// **A new layer is named by its kind's own word and the next number of that kind** — TODO (142),
    /// the owner: vector layers are "Layer N", raster layers "Raster N", and each counts on its own.
    /// Spelled out kind by kind rather than derived from `defaultNameStem`, which would be a function
    /// compared with itself.
    func testANewLayerIsNamedByItsKindsWordAndCountsOnItsOwn() {
        let expected: [LayerKind: String] = [.raster: "Raster 1", .vector: "Layer 1",
                                             .value: "Value 1", .transform: "Transform 1"]
        for kind in LayerKind.allCases {
            let m = manager(with: kind)
            XCTAssertEqual(m.layers[m.currentLayerIndex].name, expected[kind], "the first \(kind) layer of a document")
        }

        let m = CanvasManager()
        m.canvasSize = size
        m.addVectorLayer()
        m.addLayer()
        m.addVectorLayer()
        m.addLayer()
        m.addValueLayer()
        m.addTransformLayer()
        m.addValueLayer()
        XCTAssertEqual(m.layers.map(\.name),
                       ["Layer 1", "Raster 1", "Layer 2", "Raster 2", "Value 1", "Transform 1", "Value 2"],
                       "no kind takes a number from another's sequence")
    }

    /// **The next number is one past the highest in use, so a deletion never makes a duplicate.** With
    /// `Layer 1` and `Layer 2`, deleting the first and adding gives `Layer 3` — a count of the layers
    /// of the kind would say `Layer 2`, over the layer already called that. Deleting the *last* one
    /// hands its number back, which is not a duplicate: nothing carries it.
    func testTheNextNumberIsOnePastTheHighestInUseSoADeletionNeverMakesADuplicate() {
        let m = CanvasManager()
        m.canvasSize = size
        m.addVectorLayer()
        m.addVectorLayer()
        XCTAssertEqual(m.layers.map(\.name), ["Layer 1", "Layer 2"], "Setup")

        m.deleteLayer(at: 0)
        m.addVectorLayer()
        XCTAssertEqual(m.layers.map(\.name), ["Layer 2", "Layer 3"],
                       "the survivor is still Layer 2, so the new one is Layer 3 and not a second Layer 2")

        m.deleteLayer(at: m.layers.count - 1)
        m.addVectorLayer()
        XCTAssertEqual(m.layers.map(\.name), ["Layer 2", "Layer 3"],
                       "with the highest gone its number is free again")
    }

    /// **The numbering reads names, so it steps past one the artist typed, and ignores what is not the
    /// pattern** — the rule itself, on plain strings.
    func testNextDefaultNameReadsOnlyExactStemAndNumberNames() {
        XCTAssertEqual(LayerKind.vector.nextDefaultName(among: [String]()), "Layer 1")
        XCTAssertEqual(LayerKind.vector.nextDefaultName(among: ["Layer 1", "Layer 2"]), "Layer 3")
        XCTAssertEqual(LayerKind.vector.nextDefaultName(among: ["Layer 2", "Layer 7", "Layer 3"]), "Layer 8",
                       "the highest, not the count and not the first gap")
        XCTAssertEqual(LayerKind.vector.nextDefaultName(among: ["Layer 41"]), "Layer 42",
                       "an artist's own Layer 41 is a name to step past")
        XCTAssertEqual(LayerKind.raster.nextDefaultName(among: ["Layer 5", "Raster 2"]), "Raster 3",
                       "another kind's numbers are another sequence")
        XCTAssertEqual(LayerKind.vector.nextDefaultName(among: ["Layer 2 copy", "Layer", "Layer  3", "Layer -4",
                                                                  "Layer +9", "Layer 1x", "my Layer 6", "layer 8"]),
                       "Layer 1", "only the stem, one space and digits count")
        XCTAssertEqual(LayerKind.vector.nextDefaultName(among: ["Layer 99999999999999999999"]), "Layer 1",
                       "a number too long to be one the app made cannot overflow the next")
        XCTAssertEqual(LayerKind.value.nextDefaultName(among: ["Gaussian Blur", "Value 3"]), "Value 4",
                       "a value layer in effect mode is named for its grade and takes no number")
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
