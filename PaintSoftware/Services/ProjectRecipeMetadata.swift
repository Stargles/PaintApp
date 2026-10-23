import Foundation

/// Named ink sidecars and their package brush-number remap. Readers release each drawing before
/// reading the next; no canvas, image, prepared material field or brush texture is loaded here.
nonisolated enum ProjectRecipeMetadata {
    struct Reader {
        let urls: [URL]
        let vectorURLs: [URL]
        let decoder: JSONDecoder
    }

    static func reader(in package: URL, manifest: [String: Any]? = nil) throws -> Reader {
        try autoreleasepool {
            let manifest = try manifest ?? object(at: package.appendingPathComponent("manifest.json"))
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
                        let url = ProjectPackageLayout.existingURL(named: name, role: role, cel: id, in: package)
                        if role == .interpolation { urls.append(url) } else { vectorURLs.append(url) }
                    }
                }
            }
            let decoder = JSONDecoder()
            // Recipes contain ordinary LocalEdit strokes and need their document brush remap.
            // Vector material preflight reads only placements, never their ordinary brush fields.
            if !urls.isEmpty {
                let table: BrushTable
                if let name = manifest["brushTableFileName"] {
                    guard let name = name as? String else { throw InvalidMetadata() }
                    table = try JSONDecoder().decode(BrushTable.self,
                        from: Data(contentsOf: package.appendingPathComponent(name)))
                } else { table = BrushTable() }
                decoder.userInfo[.brushTable] = table.resolvingIntoPool()
            }
            return Reader(urls: urls, vectorURLs: vectorURLs, decoder: decoder)
        }
    }

    static func validate(in package: URL, manifestData: Data) -> Bool {
        do {
            let manifest = try object(from: manifestData)
            let reader = try reader(in: package, manifest: manifest)
            for url in reader.urls {
                try autoreleasepool { _ = try reader.decoder.decode(InterpolationRecipe.self, from: Data(contentsOf: url)) }
            }
            for url in reader.vectorURLs {
                try autoreleasepool {
                    do { _ = try reader.decoder.decode(VectorCanvasData.MaterialMetadata.self, from: Data(contentsOf: url)) }
                    catch let error as InkMaterialCodingError { throw error }
                    // Ordinary damaged vector geometry keeps its existing reported-loss policy.
                    // Only material integrity is fatal here, just as it is in ProjectStore.
                    catch { }
                }
            }
            return true
        } catch { return false }
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
                guard let slot = try? decoder.container(keyedBy: Slot.self),
                      let kind = try? slot.decode(String.self, forKey: .kind), kind == "stream" else { continue }
                _ = try slot.decode(VectorCanvasData.StreamRef.self, forKey: .stream)
            }
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
