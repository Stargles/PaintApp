import XCTest
import UIKit

/// **`VectorElement.colours` and `mappingColours`** — the one place that says which fields of which
/// element kind are colours, read by Bake and by the Select panel's Colour. What these pin is the slot
/// table itself and that the two accessors cannot disagree about it; the consumers' own behaviour is
/// `BakeLogicTests`' and `SelectionEditLogicTests`'.
final class VectorElementColoursLogicTests: XCTestCase {

    private func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CodableColor {
        CodableColor(red: r, green: g, blue: b, alpha: a)
    }

    private let ink = CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
    private let box = CGPath(rect: CGRect(x: 0, y: 0, width: 8, height: 8), transform: nil)
    private let place = LayerTransform(position: .zero, scale: 1, rotation: 0)

    private func stroke(_ composite: StrokeComposite) -> VectorElement {
        .stroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: ink, size: 6, opacity: 0.5,
                             samples: [VectorSample(x: 1, y: 1, pressure: 1), VectorSample(x: 5, y: 5, pressure: 1)],
                             composite: composite))
    }

    private var gradient: LinearGradientPaint {
        LinearGradientPaint(start: colour(1, 0, 0), end: colour(0, 0, 1, 0.5),
                            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 8, y: 0))
    }

    /// One element of every kind, named, so a row that fails says which.
    private func zoo() throws -> [(name: String, element: VectorElement)] {
        var recipe = TextRecipe(string: "hi")
        recipe.color = ink
        let picture = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 4, height: 4),
                                               size: CGSize(width: 4, height: 4))
        return [
            ("paint stroke", stroke(.paint)),
            ("erase stroke", stroke(.erase)),
            ("flat fill", .fill(VectorFillElement(path: box, color: ink))),
            ("gradient fill", .fill(VectorFillElement(path: box, paint: .linearGradient(gradient)))),
            ("text", .text(VectorTextElement(id: UUID(), recipe: recipe,
                                              frame: TextFrame(origin: .zero, size: CGSize(width: 8, height: 8))))),
            ("image", .image(VectorImageElement(image: picture, transform: place))),
            ("video", .video(VectorVideoElement(assetURL: URL(fileURLWithPath: "/dev/null"), assetFileName: "null",
                                                naturalSize: CGSize(width: 8, height: 4), sourceStart: .zero,
                                                sourceEnd: SourceTime(value: 1, timescale: 1), speed: 1,
                                                transform: place))),
            ("stream", .stream(VectorStreamElement(naturalSize: CGSize(width: 32, height: 18), host: "laptop",
                                                    port: 47301, sourceLabel: "monitor", transform: place))),
        ]
    }

    /// **The slot table**: a paint stroke, a flat fill and text carry one colour; a gradient carries two,
    /// start then end; an eraser stroke and the three pictures carry none.
    func testEachKindCarriesTheColoursTheTableSays() throws {
        let slots = Dictionary(uniqueKeysWithValues: try zoo().map { ($0.name, $0.element.colours) })
        XCTAssertEqual(slots["paint stroke"], [ink])
        XCTAssertEqual(slots["erase stroke"], [], "an eraser reads only alpha, so its colour is inert")
        XCTAssertEqual(slots["flat fill"], [ink])
        XCTAssertEqual(slots["gradient fill"], [gradient.start, gradient.end], "start, then end")
        XCTAssertEqual(slots["text"], [ink])
        for picture in ["image", "video", "stream"] {
            XCTAssertEqual(slots[picture], [], "\(picture): pixels and files are not a colour field")
        }
    }

    /// **The two accessors read one switch.** `mappingColours` answers nil exactly where there is no
    /// colour, and hands its closure exactly the colours `colours` lists, in that order.
    func testReadingAndRewritingCannotDisagreeAboutWhichColoursAnElementHas() throws {
        for (name, element) in try zoo() {
            var handed: [CodableColor] = []
            let mapped = element.mappingColours { handed.append($0); return $0 }
            XCTAssertEqual(handed, element.colours, "\(name): the closure is handed what `colours` lists")
            XCTAssertEqual(mapped == nil, element.colours.isEmpty, "\(name): nil exactly when there is nothing to map")
        }
    }

    /// **A rewrite replaces the colour fields and touches nothing else** — id, size, opacity, the
    /// gradient's two points — and reaches both of a gradient's stops.
    func testMappingReplacesTheColourFieldsAndNothingElse() throws {
        let marker = colour(0.9, 0.8, 0.7)
        let mapped = try zoo().compactMap { name, element in
            element.mappingColours { _ in marker }.map { (name, element, $0) }
        }
        XCTAssertEqual(mapped.map(\.0), ["paint stroke", "flat fill", "gradient fill", "text"])
        for (name, before, after) in mapped {
            XCTAssertEqual(after.id, before.id, "\(name): same object")
            XCTAssertEqual(after.colours, Array(repeating: marker, count: before.colours.count), "\(name): every slot taken")
        }
        let stroke = try XCTUnwrap(mapped[0].2.stroke)
        XCTAssertEqual(stroke.size, 6)
        XCTAssertEqual(stroke.opacity, 0.5)
        let ramp = try XCTUnwrap(mapped[2].2.fill?.gradient)
        XCTAssertEqual(ramp.from, gradient.from, "a gradient keeps its ramp")
        XCTAssertEqual(ramp.to, gradient.to)
    }
}
