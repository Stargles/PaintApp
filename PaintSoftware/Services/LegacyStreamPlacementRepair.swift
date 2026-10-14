import Foundation
import os

/// THROWAWAY until the owner confirms their library opens correctly. Earlier builds wrote no
/// placement choice; add today's On Top choice exactly once to stream records in every package,
/// including saved versions and Trash. The current StreamRef decoder requires the field.
nonisolated enum LegacyStreamPlacementRepair {
    enum Outcome: Equatable { case current, repaired, unreadable, notWritten }
    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "StreamPlacementRepair")

    static func repairLibrary() {
        let snapshot = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
        for package in LibraryRepair.packages(leavingUntouched: snapshot) {
            let result = repair(packageAt: package.url)
            if result == .unreadable || result == .notWritten {
                log.error("Stream placement repair: \(package.path, privacy: .public): \(String(describing: result), privacy: .public)")
            }
        }
    }

    @discardableResult
    static func repair(packageAt package: URL) -> Outcome {
        let drawings = package.appendingPathComponent("drawings", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drawings.path) else { return .current }
        guard let files = try? FileManager.default.contentsOfDirectory(at: drawings,
            includingPropertiesForKeys: nil) else { return .unreadable }
        var rewrites: [URL] = []
        do {
            for url in files where url.pathExtension == "json" {
                let changed = try autoreleasepool { try repairedDrawing(at: url) != nil }
                if changed { rewrites.append(url) }
            }
        } catch { return .unreadable }
        guard !rewrites.isEmpty else { return .current }
        // Validate every stream before writing any file, including records already in today's
        // format. Retain only paths: stream cels can also contain substantial vector artwork.
        var result = Outcome.repaired
        LibraryRepair.keepingItsDate(package) {
            do {
                for url in rewrites {
                    try autoreleasepool {
                        guard let object = try repairedDrawing(at: url) else { return }
                        guard LibraryRepair.write(object, to: url) else { throw RepairFailure.notWritten }
                    }
                }
            } catch RepairFailure.notWritten { result = .notWritten }
            catch { result = .unreadable }
            return true
        }
        return result
    }

    private enum RepairFailure: Error { case malformedDrawing, notWritten }

    /// One drawing at a time, shared by validation and the write pass. Current records are decoded
    /// too; a malformed present field must not be treated as a valid restore point.
    private static func repairedDrawing(at url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        guard data.range(of: Data("\"stream\"".utf8)) != nil else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RepairFailure.malformedDrawing
        }
        var changed = false
        func rewrite(_ value: Any) throws -> Any {
            if var record = value as? [String: Any] {
                if record["kind"] as? String == "stream" {
                    guard var stream = record["stream"] as? [String: Any] else { throw RepairFailure.malformedDrawing }
                    if stream["rendersInPlace"] == nil {
                        stream["rendersInPlace"] = false
                        changed = true
                    }
                    _ = try JSONDecoder().decode(VectorCanvasData.StreamRef.self,
                        from: JSONSerialization.data(withJSONObject: stream))
                    record["stream"] = stream
                }
                for key in Array(record.keys) { record[key] = try rewrite(record[key]!) }
                return record
            }
            if let array = value as? [Any] { return try array.map(rewrite) }
            return value
        }
        let repaired = try rewrite(object) as! [String: Any]
        return changed ? repaired : nil
    }
}
