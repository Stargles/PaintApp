import Foundation
import CoreFoundation
import CoreGraphics
import Darwin
import Combine
import os

/// One-shot conversion from the previous writer's spatial ink archive to point geometry. Current
/// decoders never read the previous format. Every package is staged and validated before any swap;
/// originals also supply the update snapshot, which is then converted with the other restore points.
nonisolated enum PointGeometryRepair {
    struct Failure: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    struct Report: Equatable, Sendable {
        var converted = 0
        /// Successfully read manifests whose JSON object or typed current metadata is unreadable.
        /// Their bytes remain for strict backup recovery; this is neither conversion nor a marker.
        var ambiguous: [URL] = []
    }
    private static let prefix = ".point-geometry-"
    private static let ownerSuffix = ".owner.json"
    private struct DirectoryIdentity: Codable, Equatable {
        let volume: Int64
        let inode: UInt64
        var isUsable: Bool { volume != 0 && inode != 0 }
    }
    private struct Owner: Codable, Equatable {
        let originalName: String
        let original: DirectoryIdentity
        var staged: DirectoryIdentity?
    }
    private struct Stage { let original: URL; let converted: URL; let ownerURL: URL; let owner: Owner }
    private struct Census { var packages: [URL] = []; var owners: [URL] = []; var stages: [URL] = [] }

    static func run(beforeCommit: () throws -> Void = {}) throws -> Report {
        var stages: [Stage] = []
        var ambiguous: [URL] = []
        func prepare(_ package: URL) throws {
            do {
                if let converted = try stage(package, ambiguous: &ambiguous) { stages.append(converted) }
            } catch { throw Failure(reason: package.lastPathComponent + ": " + error.localizedDescription) }
        }
        let initial = try census()
        for package in initial.packages { try autoreleasepool { try prepare(package) } }
        try retireInterruptedStages(initial, validated: stages)
        guard !stages.isEmpty else { return Report(ambiguous: ambiguous) }

        let signature = ProjectBackupManager.currentAppSignature
        // The build signature is app-wide, but an old library can be selected or imported after
        // this build has launched. Finding old geometry itself requires a protection copy.
        do {
            let readable = Set(stages.map { $0.original.standardizedFileURL })
            guard ProjectBackupManager.copyUpdateSnapshots(signature: signature,
                projects: initial.packages.filter { $0.path.hasPrefix(ProjectBackupManager.projectsDirectory.path + "/") }, validating: {
                readable.contains($0.standardizedFileURL) || ProjectBackupManager.validateProjectForRestore(at: $0)
            }) else { throw Failure(reason: "The before-update copy could not be saved. No scene was replaced.") }
            // Discover the snapshots only after cloning, so even the newest untouched version is
            // converted. Do not use a once-per-build preference that can skip this second census.
            let prepared = Set(initial.packages.map { $0.standardizedFileURL })
            for package in try census().packages where !prepared.contains(package.standardizedFileURL) {
                try autoreleasepool { try prepare(package) }
            }
        }
        try beforeCommit()
        // Owned copies survive every error. A later launch can identify either side of a completed
        // atomic swap; deleting or rolling back on failure could discard the only sound copy.
        for stage in stages {
            try validatePair(stage, swapped: false)
            try exchange(stage.original, stage.converted)
        }
        // Retention may delete original backup addresses. Retire validated pairs first, while both
        // identities can still prove ownership; signature/pruning never run after partial cleanup.
        for stage in stages {
            try validatePair(stage, swapped: true)
            try removeOwned(stage.converted, record: stage.ownerURL)
        }
        ProjectBackupManager.settings.lastAppSignature = signature
        ProjectBackupManager.pruneUpdateSnapshots()
        return Report(converted: stages.count, ambiguous: ambiguous)
    }

    /// A partial census is unsafe: it could advance the build signature or prune versions while
    /// an unreadable folder still contains unconverted work. Never follow a folder/package link.
    private static func census() throws -> Census {
        var result = Census()
        func walk(_ directory: URL) throws {
            let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard attributes.isSymbolicLink == false, attributes.isDirectory == true else {
                throw Failure(reason: "A library folder is unreadable or is a symbolic link: " + directory.lastPathComponent)
            }
            for item in try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let attributes = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard attributes.isSymbolicLink == false else {
                    throw Failure(reason: "A library entry is a symbolic link: " + item.lastPathComponent)
                }
                if item.pathExtension == "paintproj" { result.packages.append(item) }
                else if item.lastPathComponent.hasPrefix(prefix) {
                    let owner = item.lastPathComponent.hasSuffix(ownerSuffix)
                    let stem = owner ? String(item.lastPathComponent.dropLast(ownerSuffix.count)) : item.lastPathComponent
                    let token = String(stem.dropFirst(prefix.count))
                    guard let id = UUID(uuidString: token), stem == prefix + id.uuidString else {
                        throw Failure(reason: "An unknown format-repair item was preserved: " + item.lastPathComponent)
                    }
                    if owner { result.owners.append(item) }
                    else {
                        guard attributes.isDirectory == true else { throw Failure(reason: "A format-repair stage is not a directory.") }
                        result.stages.append(item)
                    }
                } else if !item.lastPathComponent.hasPrefix("."), attributes.isDirectory == true { try walk(item) }
            }
        }
        for root in [ProjectBackupManager.projectsDirectory, ProjectBackupManager.backupsRootDirectory,
                     ProjectBackupManager.trashDirectory] { try walk(root) }
        result.packages.sort { $0.path < $1.path }
        return result
    }

    /// An interrupted clone never becomes user content. Directory identity survives atomic swap,
    /// so a record can prove which side is still at the original address without reading pictures.
    private static func retireInterruptedStages(_ census: Census, validated: [Stage]) throws {
        let namedStages = Set(census.owners.map { $0.deletingLastPathComponent().appendingPathComponent(
            String($0.lastPathComponent.dropLast(ownerSuffix.count))).standardizedFileURL })
        guard census.stages.allSatisfy({ namedStages.contains($0.standardizedFileURL) }) else {
            throw Failure(reason: "An unowned format-repair copy was preserved for recovery.")
        }
        func validatedTarget(for record: URL) throws -> URL {
            let owner = try readOwner(record)
            guard !owner.originalName.contains("/"), !owner.originalName.isEmpty,
                  URL(fileURLWithPath: owner.originalName).lastPathComponent == owner.originalName,
                  (owner.originalName as NSString).pathExtension == "paintproj", owner.original.isUsable,
                  owner.staged?.isUsable != false, owner.staged != owner.original else {
                throw Failure(reason: "An unreadable format-repair owner was preserved for recovery.")
            }
            let original = record.deletingLastPathComponent().appendingPathComponent(owner.originalName)
            let target = record.deletingLastPathComponent().appendingPathComponent(
                String(record.lastPathComponent.dropLast(ownerSuffix.count)))
            let sourceID = try identity(original)
            let unswapped = sourceID == owner.original
            guard unswapped || sourceID == owner.staged else {
                throw Failure(reason: "A format-repair source changed or is missing; its copies were preserved.")
            }
            let targetID = FileManager.default.fileExists(atPath: target.path) ? try identity(target) : nil
            if let targetID {
                guard unswapped ? owner.staged == nil || targetID == owner.staged : targetID == owner.original else {
                    throw Failure(reason: "A format-repair copy changed; both copies were preserved.")
                }
            }
            if !ProjectBackupManager.validateProjectForRestore(at: original) {
                guard unswapped, let prepared = validated.first(where: {
                    $0.original == original && $0.owner.original == sourceID
                }) else {
                    throw Failure(reason: "A format-repair source could not be validated; its copies were preserved.")
                }
                try validatePair(prepared, swapped: false)
            }
            guard try identity(original) == sourceID, try readOwner(record) == owner,
                  (FileManager.default.fileExists(atPath: target.path) ? try identity(target) : nil) == targetID else {
                throw Failure(reason: "A format-repair pair changed during validation; its copies were preserved.")
            }
            return target
        }
        // A later malformed owner must not make an otherwise failed pass discard earlier copies.
        // Validate the entire interrupted set first, then recheck each pair at its removal boundary.
        for record in census.owners { _ = try validatedTarget(for: record) }
        for record in census.owners { try removeOwned(try validatedTarget(for: record), record: record) }
    }

    private static func readOwner(_ record: URL) throws -> Owner {
        let attributes = try record.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink == false else {
            throw Failure(reason: "A format-repair owner changed or is a symbolic link.")
        }
        return try JSONDecoder().decode(Owner.self, from: Data(contentsOf: record))
    }

    /// A directory swap preserves identity but not integrity against an in-place external edit.
    /// Check both identities and the current copy again at the destructive boundary.
    private static func validatePair(_ stage: Stage, swapped: Bool) throws {
        func checkOwnership() throws {
            guard try readOwner(stage.ownerURL) == stage.owner,
                  let convertedID = stage.owner.staged,
                  try identity(stage.original) == (swapped ? convertedID : stage.owner.original),
                  try identity(stage.converted) == (swapped ? stage.owner.original : convertedID) else {
                throw Failure(reason: "A format-repair pair changed; both copies were preserved.")
            }
        }
        try checkOwnership()
        guard ProjectBackupManager.validateProjectForRestore(at: swapped ? stage.original : stage.converted) else {
            throw Failure(reason: "A converted scene changed or failed validation; both copies were preserved.")
        }
        try checkOwnership()
    }

    private static func removeOwned(_ stage: URL, record: URL) throws {
        if FileManager.default.fileExists(atPath: stage.path) { try FileManager.default.removeItem(at: stage) }
        if FileManager.default.fileExists(atPath: record.path) { try FileManager.default.removeItem(at: record) }
    }

    private static func identity(_ url: URL) throws -> DirectoryIdentity {
        var value = stat()
        let status = url.withUnsafeFileSystemRepresentation { lstat($0!, &value) }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let id = DirectoryIdentity(volume: Int64(value.st_dev), inode: UInt64(value.st_ino))
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), id.isUsable else {
            throw Failure(reason: "Stable directory identity is unavailable: " + url.lastPathComponent)
        }
        return id
    }

    private static func stage(_ package: URL, ambiguous: inout [URL]) throws -> Stage? {
        guard try package.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw Failure(reason: "A project package is a symbolic link; its original was left untouched.")
        }
        let originalID = try identity(package)
        let manifestData = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let manifest: [String: Any]
        do { manifest = try object(manifestData) }
        catch {
            ambiguous.append(package)
            return nil
        }
        if manifest["geometryVersion"] != nil {
            _ = try JSONDecoder().decode(ProjectManifest.GeometryVersion.self, from: manifestData)
            return nil
        }
        // Adding the boundary must not re-serialize unrelated scene values or decimal spellings.
        var markedManifest = manifestData
        guard let root = markedManifest.firstIndex(of: UInt8(ascii: "{")) else {
            throw Failure(reason: "Unreadable project manifest object.")
        }
        markedManifest.insert(contentsOf: Data("\"geometryVersion\":\(VectorCanvasData.currentGeometryVersion),".utf8), at: root + 1)
        // Metadata damage belongs to existing backup recovery. Classify it before any payload
        // read or owned copy; drawing conversion and filesystem failures remain hard errors.
        do { _ = try JSONDecoder().decode(ProjectManifest.self, from: markedManifest) }
        catch is DecodingError {
            ambiguous.append(package)
            return nil
        }
        let reader = try ProjectRecipeMetadata.reader(in: package, manifest: manifest)
        let target = package.deletingLastPathComponent().appendingPathComponent(prefix + UUID().uuidString)
        let ownerURL = target.appendingPathExtension("owner.json")
        var owner = Owner(originalName: package.lastPathComponent, original: originalID, staged: nil)
        var copied = false
        func copy() throws {
            guard !copied else { return }
            try JSONEncoder().encode(owner).write(to: ownerURL, options: .atomic)
            guard ProjectBackupManager.cloneItem(at: package, to: target) else {
                throw Failure(reason: "A staging copy could not be saved.")
            }
            copied = true
            owner.staged = try identity(target)
            guard owner.staged != originalID else { throw Failure(reason: "The staging copy shares its source identity.") }
            try JSONEncoder().encode(owner).write(to: ownerURL, options: .atomic)
        }
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
                    try copy()
                    try data.write(to: target.appendingPathComponent(name), options: .atomic)
                }
            }
        }
        try copy()
        try markedManifest.write(to: target.appendingPathComponent("manifest.json"), options: .atomic)
        guard ProjectBackupManager.validateProjectForRestore(at: target) else {
            throw Failure(reason: "The converted copy failed saved-scene validation. Its original was left untouched.")
        }
        return Stage(original: package, converted: target, ownerURL: ownerURL, owner: owner)
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


/// Temporary launch owner for the one-shot repair. Every window shares this gate, and no gallery,
/// editor or automatic save exists until both conversion and ordinary recovery have finished.
/// Delete with PointGeometryRepair after the owner confirms the converted real library.
@MainActor
final class PointGeometryRepairStartup: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing
    private var started = false
    private let repair: @Sendable () throws -> PointGeometryRepair.Report
    private let maintenance: @Sendable () -> Void

    init(repair: @escaping @Sendable () throws -> PointGeometryRepair.Report = { try PointGeometryRepair.run() },
         maintenance: @escaping @Sendable () -> Void = { ProjectBackupManager.runStartupMaintenance() }) {
        self.repair = repair
        self.maintenance = maintenance
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            // The synchronous repair is explicitly nonisolated. A detached task calling an
            // @MainActor repair would still block the first frame and the progress animation.
            // It owns its complete file/JSON working set; only a Sendable report crosses back.
            let report = try await Task.detached(priority: .userInitiated) { [repair, maintenance] in
                let report = try repair()
                maintenance()
                return report
            }.value
            for package in report.ambiguous {
                Logger(subsystem: "Starg.PaintSoftware", category: "PointGeometryRepair").warning(
                    "Unreadable manifest preserved for existing backup recovery: \(package.lastPathComponent, privacy: .public)")
            }
            phase = .ready
        } catch {
            // Recovery/retention must never run over a partly converted library. Its original and
            // owned staging copies stay on disk; relaunch retries the same strict repair.
            phase = .failed(error.localizedDescription)
        }
    }
}
