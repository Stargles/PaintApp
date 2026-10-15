import Foundation
import os

/// THROWAWAY after the owner confirms their scenes and saved versions open correctly.
/// Add the new tool, recipe and native-material fields; current decoders remain strict.
/// Validate every sidecar before rewriting, retaining only changed URLs across the package.
nonisolated enum LegacyLiquifyRepair {
    enum Outcome: Equatable { case current, repaired, unreadable, notWritten }
    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "LiquifyRepair")

    static func repairLibrary() {
        let snapshot = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
        for package in LibraryRepair.packages(leavingUntouched: snapshot) {
            let result = repair(packageAt: package.url)
            if result == .unreadable || result == .notWritten {
                log.error("Liquify repair: \(package.path, privacy: .public): \(String(describing: result), privacy: .public)")
            }
        }
    }

    @discardableResult
    static func repair(packageAt package: URL) -> Outcome {
        let plan: Plan
        do { plan = try autoreleasepool { try plannedWrites(in: package) } }
        catch { return .unreadable }
        guard !plan.files.isEmpty else { return .current }
        var outcome = Outcome.repaired
        LibraryRepair.keepingItsDate(package) {
            for file in plan.files where outcome == .repaired {
                outcome = autoreleasepool {
                    do {
                        let current = try repaired(file, decoder: plan.reader.decoder)
                        return LibraryRepair.write(current, to: file.url) ? .repaired : .notWritten
                    } catch { return .unreadable }
                }
            }
            return true
        }
        return outcome
    }

    /// Temporary read-only preflight for an earlier saved version that is cloned before conversion.
    static func inkIsRepairable(in package: URL, manifestData: Data) -> Bool {
        do {
            let manifest = try ProjectRecipeMetadata.object(from: manifestData)
            let reader = try ProjectRecipeMetadata.reader(in: package, manifest: manifest)
            for url in reader.urls {
                try autoreleasepool {
                    _ = try repairedRecipe(ProjectRecipeMetadata.object(at: url), decoder: reader.decoder)
                }
            }
            for url in reader.vectorURLs {
                try autoreleasepool {
                    _ = try repairedDrawing(ProjectRecipeMetadata.object(at: url), decoder: reader.decoder)
                }
            }
            return true
        } catch { return false }
    }

    private struct Plan {
        let files: [File]
        let reader: ProjectRecipeMetadata.Reader
    }

    private struct File {
        enum Kind { case manifest, recipe, drawing }
        let url: URL
        let kind: Kind
    }

    private static func repaired(_ file: File, decoder: JSONDecoder) throws -> [String: Any] {
        let object = try ProjectRecipeMetadata.object(at: file.url)
        switch file.kind {
        case .manifest: return try repairedManifest(object)
        case .recipe: return try repairedRecipe(object, decoder: decoder)
        case .drawing: return try repairedDrawing(object, decoder: decoder)
        }
    }

    private static func plannedWrites(in package: URL) throws -> Plan {
        let manifestURL = package.appendingPathComponent("manifest.json")
        let original = try ProjectRecipeMetadata.object(at: manifestURL)
        let current = try repairedManifest(original)
        var files: [File] = []
        if !NSDictionary(dictionary: original).isEqual(to: current) { files.append(File(url: manifestURL, kind: .manifest)) }
        let reader = try ProjectRecipeMetadata.reader(in: package, manifest: original)
        let ink = reader.urls.map { File(url: $0, kind: .recipe) }
            + reader.vectorURLs.map { File(url: $0, kind: .drawing) }
        for file in ink {
            let changed = try autoreleasepool {
                let original = try ProjectRecipeMetadata.object(at: file.url)
                let current = try repaired(file, decoder: reader.decoder)
                return !NSDictionary(dictionary: original).isEqual(to: current)
            }
            if changed { files.append(file) }
        }
        return Plan(files: files, reader: reader)
    }

    private static func repairedManifest(_ original: [String: Any]) throws -> [String: Any] {
        var manifest = original
        guard var editor = manifest["editorState"] as? [String: Any],
              var tools = editor["tools"] as? [String: Any],
              var profiles = tools["profiles"] as? [String: Any] else { throw InvalidMetadata() }
        if profiles["liquify"] == nil {
            profiles["liquify"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ToolProfiles().liquify))
        }
        if tools["liquifyMode"] == nil { tools["liquifyMode"] = "push" }
        tools["profiles"] = profiles; editor["tools"] = tools
        _ = try decode(EditorStateManifest.self, editor, decoder: JSONDecoder())
        manifest["editorState"] = editor
        return manifest
    }

    private static func repairedRecipe(_ original: [String: Any], decoder: JSONDecoder) throws -> [String: Any] {
        var object = original
        let legacyMaterial = object["materialOperations"] == nil
        let defaults: [String: Any] = ["mode": "generate", "groups": [], "guideIDs": [],
            "localEdits": [], "spacing": ["kind": "linear", "samples": []], "deformations": []]
        for (key, value) in defaults where object[key] == nil { object[key] = value }
        if legacyMaterial { object["materialOperations"] = [] }
        guard var edits = object["localEdits"] as? [[String: Any]] else { throw InvalidMetadata() }
        for i in edits.indices {
            guard let stroke = edits[i]["stroke"] as? [String: Any] else { throw InvalidMetadata() }
            edits[i]["stroke"] = try repairedStroke(stroke, legacy: legacyMaterial, decoder: decoder)
        }
        object["localEdits"] = edits
        _ = try decode(InterpolationRecipe.self, object, decoder: decoder)
        return object
    }

    private static func repairedDrawing(_ original: [String: Any], decoder: JSONDecoder) throws -> [String: Any] {
        var object = original
        let legacy = object["materialOperations"] == nil
        if legacy { object["materialOperations"] = [] }
        if var elements = object["elements"] as? [Any] {
            for i in elements.indices {
                guard var element = elements[i] as? [String: Any], let kind = element["kind"] as? String,
                      kind == "stroke" || kind == "fill", var ink = element[kind] as? [String: Any] else { continue }
                if kind == "stroke" { ink = try repairedStroke(ink, legacy: legacy, decoder: decoder) }
                else if legacy, ink["placement"] == nil { ink["placement"] = NSNull() }
                element[kind] = ink; elements[i] = element
            }
            object["elements"] = elements
        } else {
            // The earlier parallel-array payload remains supported by the existing vector codec.
            if let strokes = object["strokes"] as? [[String: Any]] {
                object["strokes"] = try strokes.map { try repairedStroke($0, legacy: legacy, decoder: decoder) }
            }
            if legacy, let fills = object["fills"] as? [[String: Any]] {
                object["fills"] = fills.map { fill in
                    var fill = fill
                    if fill["placement"] == nil { fill["placement"] = NSNull() }
                    return fill
                }
            }
        }
        _ = try decode(VectorCanvasData.MaterialMetadata.self, object, decoder: decoder)
        return object
    }

    /// Move packed native runs without decoding/repacking their coordinates. The old renderer used
    /// the live lattice's range with the saved parent's samples, so a trimmed bake keeps that range.
    private static func repairedStroke(_ original: [String: Any], legacy: Bool,
                                       decoder: JSONDecoder) throws -> [String: Any] {
        var stroke = original
        let oldKeys = ["distort", "distortRest", "distortRestLattice"]
        if stroke["placement"] != nil {
            guard oldKeys.allSatisfy({ stroke[$0] == nil }) else { throw InvalidMetadata() }
            return stroke
        }
        guard legacy else { throw InvalidMetadata() }
        if let distort = stroke["distort"], !(distort is NSNull) {
            guard var placement = distort as? [String: Any] else { throw InvalidMetadata() }
            var source: [String: Any] = ["kind": "derived"]
            if let rest = stroke["distortRest"] {
                var nativeLattice: Any = NSNull()
                if let kept = stroke["distortRestLattice"], !(kept is NSNull) {
                    guard var kept = kept as? [String: Any] else { throw InvalidMetadata() }
                    let saved = try decode(DabLattice.self, kept, decoder: decoder)
                    if let live = stroke["lattice"] as? [String: Any],
                       try decode(DabLattice.self, live, decoder: decoder).samples.count == saved.samples.count {
                        kept["parameters"] = live["parameters"]
                        nativeLattice = kept
                    }
                }
                source = ["kind": "retained", "samples": rest, "lattice": nativeLattice]
            } else if stroke["distortRestLattice"] != nil { throw InvalidMetadata() }
            placement["source"] = source
            placement["material"] = NSNull()
            placement["transport"] = ["kind": "identity"]
            stroke["placement"] = placement
        } else {
            guard stroke["distortRest"] == nil, stroke["distortRestLattice"] == nil else { throw InvalidMetadata() }
            stroke["placement"] = NSNull()
        }
        for key in oldKeys { stroke.removeValue(forKey: key) }
        return stroke
    }

    private struct InvalidMetadata: Error {}

    private static func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any], decoder: JSONDecoder) throws -> T {
        try decoder.decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
}
