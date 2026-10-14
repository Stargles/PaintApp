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
        var rewrites: [(URL, [String: Any])] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { return .unreadable }
            // A cel with no stream needs neither parsing nor rewriting.
            guard data.range(of: Data("\"stream\"".utf8)) != nil else { continue }
            guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .unreadable
            }
            var changed = false
            func rewrite(_ value: Any) throws -> Any {
                if var record = value as? [String: Any] {
                    if record["kind"] as? String == "stream" {
                        guard var stream = record["stream"] as? [String: Any] else {
                            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing stream record"))
                        }
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
            do { object = try rewrite(object) as! [String: Any] }
            catch { return .unreadable }
            if changed { rewrites.append((url, object)) }
        }
        guard !rewrites.isEmpty else { return .current }
        // Validate every stream before writing any file, including records already in today's
        // format. A corrupt backup must never become eligible to replace the live scene.
        var written = true
        LibraryRepair.keepingItsDate(package) {
            for (url, object) in rewrites where written { written = LibraryRepair.write(object, to: url) }
            return true
        }
        return written ? .repaired : .notWritten
    }
}
