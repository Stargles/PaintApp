import UIKit
import ImageIO

/// One selected drawing, independent of a document or process. The existing drawing/brush codecs
/// own geometry; this envelope owns only clipboard version, duration and the selected resources.
struct SelectionClipboard: Codable {
    static let type = "com.starg.paintsoftware.vector-selection"
    static let maximumBytes = 64 * 1024 * 1024
    static let currentVersion = 1

    let version: Int
    let frameCount: Int
    let brushes: BrushTable
    let drawing: Data
    let images: [String: Data]
    let textures: [String: Data]

    enum Failure: Error { case invalid, tooLarge }

    static func encode(_ elements: [VectorElement], canvasSize: CGSize, frameCount: Int) throws -> Data {
        guard frameCount > 0, !elements.isEmpty,
              VectorUndoCost.bytes(fromLists: [[]], toLists: [elements]) <= maximumBytes else { throw Failure.tooLarge }
        var decodedBytes = 0
        var names: [UUID: String] = [:]
        var images: [String: Data] = [:]
        var resourceBytes = 0
        let portable = try elements.map { element -> VectorElement in
            switch element {
            case .stroke(let stroke): return .stroke(stroke.markedPrecise())
            case .image(var image):
                guard image.source.logicalPayloadBytes <= maximumBytes else { throw Failure.tooLarge }
                let checkpoint = try image.source.prepareForSave().get()
                let data = try Data(contentsOf: checkpoint.backing.url, options: .mappedIfSafe)
                try addResource(data, to: &resourceBytes)
                try admitPNG(data, decodedBytes: &decodedBytes)
                let name = "\(image.id.uuidString).png"
                images[name] = data
                names[image.id] = name
                image.fileName = nil
                return .image(image)
            case .fill, .text: return element
            case .video, .stream: throw Failure.invalid
            }
        }
        var collector = BrushTable.Collector()
        collector.add(elements: portable)
        let brushes = collector.table
        var textures: [String: Data] = [:]
        for name in brushes.importedTextureFileNames {
            try validateTextureName(name)
            guard let data = BrushStorage.shared.read(name) else { throw Failure.invalid }
            try addResource(data, to: &resourceBytes)
            try admitPNG(data, decodedBytes: &decodedBytes, isTexture: true)
            textures[name] = data
        }
        let canvas = VectorCanvas(size: canvasSize, elements: portable)
        let encoder = JSONEncoder()
        encoder.userInfo[.brushTable] = brushes.identityRemap
        let drawing = try encoder.encode(VectorCanvasData(from: canvas, imageFileNames: names))
        let envelope = Self(version: currentVersion, frameCount: frameCount, brushes: brushes,
                            drawing: drawing, images: images, textures: textures)
        let encoded = try JSONEncoder().encode(envelope)
        guard encoded.count <= maximumBytes else { throw Failure.tooLarge }
        return encoded
    }

    struct Prepared {
        let elements: [VectorElement]
        let frameCount: Int
        /// Existing equal files are reused. Every other name is freshly minted, never overwritten.
        let textureWrites: [String: Data]

        func installingTextures(then insert: () -> Bool) -> Bool {
            var written: [String] = []
            var accepted = false
            defer { if !accepted { written.forEach { BrushStorage.shared.remove($0) } } }
            do {
                for (name, data) in textureWrites {
                    guard !BrushStorage.shared.contains(name) else { return false }
                    try BrushStorage.shared.write(data, to: name)
                    written.append(name)
                }
                accepted = insert()
                return accepted
            } catch { return false }
        }
    }

    /// Validate the complete native representation before a pending artist edit is settled. A
    /// recognized but damaged payload is refused whole, never downgraded to its flattened picture.
    static func prepare(_ data: Data, using residency: RasterResidency = .shared) throws -> Prepared {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        guard envelope.version == currentVersion, envelope.frameCount > 0 else { throw Failure.invalid }
        let requiredTextures = envelope.brushes.importedTextureFileNames
        guard Set(envelope.textures.keys) == requiredTextures else { throw Failure.invalid }
        var decodedBytes = 0
        var names: [String: String] = [:]
        var writes: [String: Data] = [:]
        for (name, bytes) in envelope.textures {
            try validateTextureName(name)
            try admitPNG(bytes, decodedBytes: &decodedBytes, isTexture: true)
            if BrushStorage.shared.read(name) == bytes { names[name] = name }
            else {
                let kind: BrushAssetKind = BrushAssetKind.tip.owns(name) ? .tip : .texture
                let fresh = kind.newFileName()
                names[name] = fresh
                writes[fresh] = bytes
            }
        }
        let relocated = BrushTable(entries: envelope.brushes.entries.mapValues { original in
            var brush = original
            if let name = brush.tip.importedTextureFileName, let mapped = names[name] {
                brush.tip = .stamp(.imported(fileName: mapped))
            }
            if let name = brush.texture?.mask.importedFileName, let mapped = names[name] {
                brush.texture?.mask = .imported(fileName: mapped)
            }
            return brush
        })
        let decoder = JSONDecoder()
        decoder.userInfo[.brushTable] = relocated.resolvingIntoPool()
        let drawing = try decoder.decode(VectorCanvasData.self, from: envelope.drawing)
        guard drawing.decodeReport.isClean, !drawing.elements.isEmpty, drawing.transform.isEmpty,
              drawing.elements.allSatisfy({
                  switch $0 { case .video, .stream: return false; default: return true }
              }), Set(drawing.images.map(\.fileName)) == Set(envelope.images.keys)
        else { throw Failure.invalid }
        var sources: [String: RasterSource] = [:]
        for (name, bytes) in envelope.images {
            try admitPNG(bytes, decodedBytes: &decodedBytes)
            guard let image = UIImage(data: bytes) else { throw Failure.invalid }
            sources[name] = try RasterSource.capturePlaced(image, using: residency).get()
        }
        let elements = try drawing.canvasSpaceElements(resolvingImages: { ref in
            guard let source = sources[ref.fileName] else { throw Failure.invalid }
            return source
        }, resolvingVideos: { _ in throw Failure.invalid }).map { element in
            let adopted = element.adoptedByAnotherCel()
            if case .image(var image) = adopted {
                image.fileName = nil
                return VectorElement.image(image)
            }
            return adopted
        }
        guard elements.count == drawing.elements.count,
              Set(elements.map(\.id)).count == elements.count,
              elements.allSatisfy(VectorCanvas.canBeMapped),
              let bounds = MoveBoxInk(of: elements).bounds(),
              [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              VectorUndoCost.bytes(fromLists: [[]], toLists: [elements]) <= maximumBytes
        else { throw Failure.invalid }
        return Prepared(elements: elements, frameCount: envelope.frameCount, textureWrites: writes)
    }

    private static func validateTextureName(_ name: String) throws {
        // Use the package address authority too: a texture name can never address another file.
        _ = try ProjectPackageLayout.writePath(named: "brushes/\(name)", role: .placedImage)
        guard !name.contains("/"), !name.contains("\\"),
              BrushAssetKind.tip.owns(name) || BrushAssetKind.texture.owns(name) else { throw Failure.invalid }
    }

    private static func addResource(_ bytes: Data, to total: inout Int) throws {
        guard bytes.count <= maximumBytes - total else { throw Failure.tooLarge }
        total += bytes.count
    }

    /// Inspect dimensions before UIImage or the residency owner is asked to decode any pixels.
    /// Both encoded size and the sum of decoded selected resources have a hard bound.
    private static func admitPNG(_ bytes: Data, decodedBytes: inout Int, isTexture: Bool = false) throws {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let count = RasterSurface.byteCount(width: width, height: height),
              count <= maximumBytes - decodedBytes,
              !isTexture || (width == BrushTipImport.maskSide && height == BrushTipImport.maskSide)
        else { throw Failure.invalid }
        decodedBytes += count
    }
}

extension CanvasManager {
    /// Nil means success. The Actions menu owns its existing inline refusal caption.
    @MainActor
    func pasteSelectionFromPasteboard() -> String? {
        if UIPasteboard.general.contains(pasteboardTypes: [SelectionClipboard.type]) {
            do {
                guard let data = UIPasteboard.general.data(forPasteboardType: SelectionClipboard.type) else {
                    throw SelectionClipboard.Failure.invalid
                }
                let prepared = try SelectionClipboard.prepare(data)
                guard prepared.installingTextures(then: {
                    insertPastedVectorSelection(prepared.elements, frameCount: prepared.frameCount)
                }) else { return "This copied drawing cannot be pasted here. Copy it again and try Paste." }
                return nil
            } catch { return "This copied drawing is unavailable or too large. Copy it again and try Paste." }
        }
        guard let image = UIPasteboard.general.image else {
            return "Nothing to paste — copy or cut a selection first."
        }
        return insertImage(image) ? nil : "This picture cannot be pasted here."
    }
}
