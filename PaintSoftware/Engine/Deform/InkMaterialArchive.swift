import Foundation

extension VectorCanvasData {
    /// Material integrity before a project is opened or restored. This intentionally reads no
    /// ordinary brush/colour/sample fields and needs no document BrushTable. It uses the same
    /// operation table and placement decoders as the full drawing, preserving ordinary lossy slots.
    struct MaterialMetadata: Decodable {
        private enum Root: String, CodingKey { case materialOperations, elements, strokes, fills }
        private enum Slot: String, CodingKey { case kind, stroke, fill }
        private enum Payload: String, CodingKey { case placement }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Root.self)
            let table = try InkMaterialCodingError.preserving {
                try InkMaterialTable(definitions: c.decode([LiquifyDeformation].self, forKey: .materialOperations))
            }
            func placement(_ decoder: Decoder, stroke: Bool) throws {
                // A non-object payload is ordinary malformed geometry. A named material key inside
                // an object must be present and readable even if its other geometry is malformed.
                guard let fields = try? decoder.container(keyedBy: Payload.self) else { return }
                try InkMaterialCodingError.preserving {
                    guard fields.contains(.placement) else { throw InkMaterialCodingError.invalid("missing ink placement") }
                    guard try !fields.decodeNil(forKey: .placement) else { return }
                    let source = try fields.superDecoder(forKey: .placement)
                    if stroke { _ = try StrokePlacement(from: source, table: table) }
                    else { _ = try FillPlacement(from: source, table: table) }
                }
            }
            if c.contains(.elements), try !c.decodeNil(forKey: .elements) {
                var elements = try c.nestedUnkeyedContainer(forKey: .elements)
                while !elements.isAtEnd {
                    let decoder = try elements.superDecoder()
                    guard let slot = try? decoder.container(keyedBy: Slot.self),
                          let kind = try? slot.decode(String.self, forKey: .kind) else { continue }
                    switch kind {
                    case "stroke":
                        if slot.contains(.stroke) { try placement(slot.superDecoder(forKey: .stroke), stroke: true) }
                    case "fill":
                        if slot.contains(.fill) { try placement(slot.superDecoder(forKey: .fill), stroke: false) }
                    default: continue
                    }
                }
            } else {
                for (key, isStroke) in [(Root.strokes, true), (.fills, false)] {
                    var elements = try c.nestedUnkeyedContainer(forKey: key)
                    while !elements.isAtEnd { try placement(elements.superDecoder(), stroke: isStroke) }
                }
            }
        }
    }
}
