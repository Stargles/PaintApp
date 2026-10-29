import Foundation

/// Named ink sidecars and their package brush-number remap. Readers release each drawing before
/// reading the next; no canvas, image or brush texture is loaded here.
nonisolated enum ProjectRecipeMetadata {
    struct Reader {
        let urls: [URL]
        let vectorURLs: [URL]
        let decoder: JSONDecoder
    }

    static func reader(in package: URL, manifest: [String: Any]? = nil) throws -> Reader {
        try autoreleasepool {
            let manifest = try manifest ?? object(at: ProjectPackageLayout.resolve("manifest.json", in: package))
            guard let layers = manifest["layers"] as? [[String: Any]] else { throw InvalidMetadata() }
            var urls: [URL] = []
            var vectorURLs: [URL] = []
            for layer in layers {
                guard let cels = layer["cels"] as? [[String: Any]] else { throw InvalidMetadata() }
                for cel in cels {
                    for (key, role) in [("interpolationFileName", ProjectPackageLayout.Role.interpolation),
                                        ("vectorFileName", .drawing)] {
                        guard let name = cel[key] else { continue }
                        guard let name = name as? String,
                              let idString = cel["id"] as? String, let id = UUID(uuidString: idString) else {
                            throw InvalidMetadata()
                        }
                        let url = try ProjectPackageLayout.existingURL(named: name, role: role, cel: id, in: package)
                        if role == .interpolation { urls.append(url) } else { vectorURLs.append(url) }
                    }
                }
            }
            let decoder = JSONDecoder()
            decoder.userInfo[ProjectPackageLayout.packageURLUserInfoKey] = package
            // Recipes contain ordinary LocalEdit strokes and need their document brush remap.
            // Geometry preflight reads only placements, never ordinary brush fields.
            if let name = manifest["brushTableFileName"] {
                guard let name = name as? String else { throw InvalidMetadata() }
                let table = try JSONDecoder().decode(BrushTable.self,
                    from: Data(contentsOf: ProjectPackageLayout.resolve(name, in: package)))
                try validateTextureNames(table.importedTextureFileNames, in: package)
                if !urls.isEmpty { decoder.userInfo[.brushTable] = table.resolvingIntoPool() }
            } else if !urls.isEmpty { decoder.userInfo[.brushTable] = BrushTable().resolvingIntoPool() }
            return Reader(urls: urls, vectorURLs: vectorURLs, decoder: decoder)
        }
    }

    static func validate(in package: URL, manifestData: Data) -> Bool {
        do {
            _ = try JSONDecoder().decode(ProjectManifest.GeometryVersion.self, from: manifestData)
            let manifest = try object(from: manifestData)
            let reader = try reader(in: package, manifest: manifest)
            let saved = try JSONDecoder().decode(TextureMetadata.self, from: manifestData)
            try validateTextureNames(((saved.editorState?.tools?.profiles?.presets ?? []) + (saved.customBrushes ?? []))
                .reduce(into: Set<String>()) { $0.formUnion($1.importedTextureFileNames) }, in: package)
            for url in reader.urls {
                try autoreleasepool {
                    let recipe = try reader.decoder.decode(InterpolationRecipe.self, from: Data(contentsOf: url))
                    for deformation in recipe.deformations {
                        try validateTextureNames(deformation.brush.importedTextureFileNames, in: package)
                    }
                }
            }
            for url in reader.vectorURLs {
                try autoreleasepool {
                    _ = try reader.decoder.decode(GeometryMetadata.self, from: Data(contentsOf: url))
                }
            }
            return true
        } catch { return false }
    }

    /// Reads only address-bearing brush populations; absent fields in a metadata-only skeleton
    /// do not manufacture an editor or change the full manifest decoder's requirements.
    private struct TextureMetadata: Decodable {
        let customBrushes: [Brush]?
        let editorState: Editor?
        struct Editor: Decodable {
            let tools: Tools?
            struct Tools: Decodable { let profiles: ToolProfiles? }
        }
    }

    /// Version, projective ownership and admitted video timing are payload integrity. Ordinary
    /// damaged element fields keep their reported-loss policy; no stroke samples or pixels are read.
    private struct GeometryMetadata: Decodable {
        private enum Root: String, CodingKey { case geometryVersion, elements }
        private enum Slot: String, CodingKey { case kind, stroke, video }
        private enum Stroke: String, CodingKey { case placement }
        init(from decoder: Decoder) throws {
            try VectorGeometryCodingError.preserving {
                let root = try decoder.container(keyedBy: Root.self)
                guard try root.decode(Int.self, forKey: .geometryVersion) == VectorCanvasData.currentGeometryVersion else {
                    throw InvalidMetadata()
                }
                var elements = try root.nestedUnkeyedContainer(forKey: .elements)
                while !elements.isAtEnd {
                    let decoder = try elements.superDecoder()
                    try VectorCanvasData.validateResourceAddress(from: decoder)
                    guard let slot = try? decoder.container(keyedBy: Slot.self),
                          let kind = try? slot.decode(String.self, forKey: .kind) else { continue }
                    if kind == "video" {
                        try VectorCanvasData.VideoRef.validateTiming(from: slot.superDecoder(forKey: .video))
                        continue
                    }
                    guard kind == "stroke", slot.contains(.stroke),
                          let stroke = try? slot.superDecoder(forKey: .stroke).container(keyedBy: Stroke.self) else { continue }
                    guard stroke.contains(.placement) else { throw InvalidMetadata() }
                    if try !stroke.decodeNil(forKey: .placement) {
                        _ = try stroke.decode(StrokePlacement.self, forKey: .placement)
                    }
                }
            }
        }
    }

    /// A saved reference must remain readable before a restore can displace the live scene. This
    /// reads only stream addresses, preserving ordinary geometry's reported-loss policy.
    static func validateRestoreStreams(in package: URL, manifestData: Data) -> Bool {
        do {
            let manifest = try object(from: manifestData)
            let reader = try reader(in: package, manifest: manifest)
            for url in reader.vectorURLs {
                try autoreleasepool {
                    let data = try Data(contentsOf: url)
                    guard data.range(of: Data("\"stream\"".utf8)) != nil else { return }
                    _ = try reader.decoder.decode(StreamMetadata.self, from: data)
                }
            }
            return true
        } catch { return false }
    }

    private struct StreamMetadata: Decodable {
        private enum Root: String, CodingKey { case elements }
        private enum Slot: String, CodingKey { case kind, stream }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Root.self)
            guard var elements = try? root.nestedUnkeyedContainer(forKey: .elements) else { return }
            while !elements.isAtEnd {
                let decoder = try elements.superDecoder()
                try VectorCanvasData.validateResourceAddress(from: decoder)
                guard let slot = try? decoder.container(keyedBy: Slot.self),
                      let kind = try? slot.decode(String.self, forKey: .kind), kind == "stream" else { continue }
                _ = try slot.decode(VectorCanvasData.StreamRef.self, forKey: .stream)
            }
        }
    }

    static func validateTextureNames(_ names: Set<String>, in package: URL) throws {
        for name in names {
            _ = try ProjectPackageLayout.resolve("brushes/\(name)", in: package)
        }
    }

    static func object(at url: URL) throws -> [String: Any] { try object(from: Data(contentsOf: url)) }

    static func object(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let object = object as? [String: Any] else { throw InvalidMetadata() }
        return object
    }

    private struct InvalidMetadata: Error {}
}
