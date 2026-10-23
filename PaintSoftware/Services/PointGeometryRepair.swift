import Foundation
import CoreFoundation
import CoreGraphics
import Darwin

/// One-shot conversion from the previous writer's spatial ink archive to point geometry. Current
/// decoders never read the previous format. Every package is staged and validated before any swap;
/// originals also supply the update snapshot, which is then converted with the other restore points.
nonisolated enum PointGeometryRepair {
    struct Failure: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    struct Report: Equatable { var converted = 0 }
    private struct Stage { let original: URL; let converted: URL }

    static func run() throws -> Report {
        var stages: [Stage] = []
        var exchanged: [Stage] = []
        var canRemoveStages = true
        defer {
            if canRemoveStages {
                for stage in stages { try? FileManager.default.removeItem(at: stage.converted) }
            }
        }
        func prepare(_ package: URL) throws {
            do {
                if let converted = try stage(package) { stages.append(Stage(original: package, converted: converted)) }
            } catch { throw Failure(reason: package.lastPathComponent + ": " + error.localizedDescription) }
        }
        for package in packages() { try autoreleasepool { try prepare(package) } }
        guard !stages.isEmpty else { return Report() }

        let signature = ProjectBackupManager.currentAppSignature
        // The build signature is app-wide, but an old library can be selected or imported after
        // this build has launched. Finding old geometry itself requires a protection copy.
        do {
            let readable = Set(stages.map { $0.original.standardizedFileURL })
            guard ProjectBackupManager.copyUpdateSnapshots(signature: signature, validating: {
                readable.contains($0.standardizedFileURL) || ProjectBackupManager.validateProjectForRestore(at: $0)
            }) else { throw Failure(reason: "The before-update copy could not be saved. No scene was replaced.") }
            // Discover the snapshots only after cloning, so even the newest untouched version is
            // converted. Do not use a once-per-build preference that can skip this second census.
            let prepared = Set(stages.map { $0.original.standardizedFileURL })
            for package in packages() where !prepared.contains(package.standardizedFileURL) {
                try autoreleasepool { try prepare(package) }
            }
        }
        do {
            for stage in stages {
                try exchange(stage.original, stage.converted)
                exchanged.append(stage)
            }
        } catch {
            // Stages now hold original bytes. Roll back completed exchanges without an interval in
            // which either package is absent. If rollback itself fails, keep both complete copies.
            for stage in exchanged.reversed() {
                do { try exchange(stage.original, stage.converted) }
                catch { canRemoveStages = false }
            }
            throw Failure(reason: "The saved-scene format could not be replaced: " + error.localizedDescription)
        }
        ProjectBackupManager.settings.lastAppSignature = signature
        ProjectBackupManager.pruneUpdateSnapshots()
        return Report(converted: stages.count)
    }

    private static func packages() -> [URL] {
        [ProjectBackupManager.projectsDirectory, ProjectBackupManager.backupsRootDirectory,
         ProjectBackupManager.trashDirectory].flatMap { ProjectBackupManager.allProjectPackages(in: $0) }
            .sorted { $0.path < $1.path }
    }

    private static func stage(_ package: URL) throws -> URL? {
        guard try package.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw Failure(reason: "A project package is a symbolic link; its original was left untouched.")
        }
        let reader = try ProjectRecipeMetadata.reader(in: package)
        let target = package.deletingLastPathComponent().appendingPathComponent(".point-geometry-" + UUID().uuidString)
        var copied = false
        var ready = false
        defer { if !ready { try? FileManager.default.removeItem(at: target) } }
        for (urls, recipe) in [(reader.vectorURLs, false), (reader.urls, true)] {
            for url in Set(urls) {
                try autoreleasepool {
                    let resolvedPackage = package.resolvingSymlinksInPath().standardizedFileURL
                    let name = String(url.path.dropFirst(package.path.count + 1))
                    let expectedPath = resolvedPackage.appendingPathComponent(name).standardizedFileURL.path
                    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                    guard path.hasPrefix(resolvedPackage.path + "/"), path == expectedPath else {
                        throw Failure(reason: "A drawing address leaves its package or follows a symbolic link.")
                    }
                    guard let data = try convertedPayload(Data(contentsOf: url), recipe: recipe) else { return }
                    if !copied {
                        guard ProjectBackupManager.cloneItem(at: package, to: target) else {
                            throw Failure(reason: "A staging copy could not be saved.")
                        }
                        copied = true
                    }
                    try data.write(to: target.appendingPathComponent(name), options: .atomic)
                }
            }
        }
        guard copied else { return nil }
        guard ProjectBackupManager.validateProjectForRestore(at: target) else {
            throw Failure(reason: "The converted copy failed saved-scene validation. Its original was left untouched.")
        }
        ready = true
        return target
    }

    /// Nil means an already-current payload, which must never be re-encoded merely to sort JSON.
    static func convertedPayload(_ data: Data, recipe: Bool) throws -> Data? {
        var root = try object(data)
        if let version = root["geometryVersion"] {
            guard let number = version as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.intValue == VectorCanvasData.currentGeometryVersion,
                  number.doubleValue == Double(number.intValue) else {
                throw Failure(reason: "Unsupported saved geometry version.")
            }
            return nil
        }
        let definitions: [LiquifyDeformation] = try decode(try required(root, "materialOperations"))
        let operationIDs = Set(definitions.map(\.id))
        guard operationIDs.count == definitions.count else { throw Failure(reason: "Duplicate spatial operation definition.") }
        if recipe {
            guard var edits = root["localEdits"] as? [[String: Any]] else { throw Failure(reason: "Unreadable local edits.") }
            for index in edits.indices {
                guard let stroke = edits[index]["stroke"] as? [String: Any] else { throw Failure(reason: "Unreadable local stroke.") }
                edits[index]["stroke"] = try convertedStroke(stroke, operationIDs: operationIDs)
            }
            root["localEdits"] = edits
        } else {
            guard var elements = root["elements"] as? [Any] else { throw Failure(reason: "Unreadable ordered drawing.") }
            for index in elements.indices {
                // The ordinary decoder's reported-loss behavior is retained. A malformed ordinary
                // slot is not repaired into an empty replacement or made valid by this conversion.
                guard var element = elements[index] as? [String: Any], let kind = element["kind"] as? String else { continue }
                if kind == "stroke", let stroke = element["stroke"] as? [String: Any] {
                    element["stroke"] = try convertedStroke(stroke, operationIDs: operationIDs)
                } else if kind == "fill", var fill = element["fill"] as? [String: Any] {
                    let placement = try required(fill, "placement")
                    if !(placement is NSNull) { try validateFill(try dictionary(placement), operationIDs: operationIDs) }
                    fill.removeValue(forKey: "placement")
                    element["fill"] = fill
                }
                elements[index] = element
            }
            root["elements"] = elements
        }
        root.removeValue(forKey: "materialOperations")
        root["geometryVersion"] = VectorCanvasData.currentGeometryVersion
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func convertedStroke(_ old: [String: Any], operationIDs: Set<UUID>) throws -> [String: Any] {
        var stroke = old
        let raw = try required(stroke, "placement")
        guard !(raw is NSNull) else { return stroke }
        var placement = try dictionary(raw)
        let map: Homography = try decode(try required(placement, "map"))
        let source: StrokePlacement.Source = try decode(try required(placement, "source"))
        let material = try required(placement, "material")
        try validateBridge(try required(placement, "transport"))
        let size: CGFloat = try decode(try required(placement, "restSize"))
        guard size.isFinite, size >= 0, map.inverse != nil else { throw Failure(reason: "Unusable stroke placement.") }
        if !(material is NSNull) {
            _ = try validateProgram(material, operationIDs: operationIDs)
            guard case .retained = source else { throw Failure(reason: "Spatial stroke has no native source.") }
            if map.affine()?.isIdentity == true {
                stroke["placement"] = NSNull()
                return stroke
            }
            // The displayed samples and ancestral lattice are already committed geometry. The old
            // retained source is undeformed and must not survive as the source of this placement.
            placement["source"] = ["kind": "derived"]
        }
        placement.removeValue(forKey: "material")
        placement.removeValue(forKey: "transport")
        stroke["placement"] = placement
        return stroke
    }

    private static func validateProgram(_ raw: Any, operationIDs: Set<UUID>) throws -> Set<UUID> {
        let program = try dictionary(raw)
        guard program["scope"] as? String == "container", program["operations"] == nil,
              let bindings = program["bindings"] as? [[String: Any]], !bindings.isEmpty else {
            throw Failure(reason: "Unreadable spatial operation ownership.")
        }
        var seen = Set<UUID>()
        for binding in bindings {
            let id: UUID = try decode(try required(binding, "operation"))
            guard operationIDs.contains(id), seen.insert(id).inserted else {
                throw Failure(reason: "Missing or repeated spatial operation reference.")
            }
            try validateBridge(try required(binding, "bridge"))
        }
        return seen
    }

    private static func validateFill(_ placement: [String: Any], operationIDs: Set<UUID>) throws {
        let path: Data = try decode(try required(placement, "pathData"))
        let map: Homography = try decode(try required(placement, "map"))
        guard VectorFillElement.decodePath(path) != nil, map.inverse != nil,
              let coverage = placement["coverage"] as? [[String: Any]] else { throw Failure(reason: "Unreadable native fill.") }
        let used = try validateProgram(try required(placement, "material"), operationIDs: operationIDs)
        try validateBridge(try required(placement, "transport"))
        for clip in coverage {
            let path: Data = try decode(try required(clip, "pathData"))
            let id: UUID = try decode(try required(clip, "afterOperation"))
            let _: Bool = try decode(try required(clip, "inverted"))
            guard VectorFillElement.decodePath(path) != nil, used.contains(id) else { throw Failure(reason: "Unreadable chronological fill cut.") }
            try validateBridge(try required(clip, "bridge"))
        }
    }

    private static func validateBridge(_ raw: Any) throws {
        let bridge = try dictionary(raw)
        let mappingKeys = Set(["map", "captured", "current", "pose", "parts"])
        func only(_ allowed: Set<String>) throws {
            guard mappingKeys.intersection(bridge.keys).isSubset(of: allowed) else { throw Failure(reason: "Conflicting spatial transport fields.") }
        }
        func map(_ key: String) throws {
            let value: Homography = try decode(try required(bridge, key))
            guard value.inverse != nil else { throw Failure(reason: "Singular spatial transport.") }
        }
        switch bridge["kind"] as? String {
        case "identity": try only([])
        case "homography": try only(["map"]); try map("map")
        case "lattice":
            try only(["captured", "current", "pose"]); try map("pose")
            let _: Lattice = try decode(try required(bridge, "captured"))
            let _: Lattice = try decode(try required(bridge, "current"))
        case "sequence":
            try only(["parts"])
            guard let parts = bridge["parts"] as? [Any], parts.count >= 2 else { throw Failure(reason: "Unreadable spatial transport sequence.") }
            for part in parts { try validateBridge(part) }
        default: throw Failure(reason: "Unknown spatial transport.")
        }
    }

    private static func object(_ data: Data) throws -> [String: Any] { try dictionary(JSONSerialization.jsonObject(with: data)) }
    private static func dictionary(_ value: Any) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw Failure(reason: "Unreadable saved geometry object.") }
        return value
    }
    private static func required(_ value: [String: Any], _ key: String) throws -> Any {
        guard let result = value[key] else { throw Failure(reason: "Missing saved geometry field: " + key) }
        return result
    }
    private static func decode<T: Decodable>(_ value: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
    }
    private static func exchange(_ first: URL, _ second: URL) throws {
        let result = first.withUnsafeFileSystemRepresentation { a in
            second.withUnsafeFileSystemRepresentation { b in
                renameatx_np(AT_FDCWD, a!, AT_FDCWD, b!, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
