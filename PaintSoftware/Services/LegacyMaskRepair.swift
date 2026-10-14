import Foundation
import os

/// THROWAWAY: the previous build stored only source picks and flags. Give each mask its shipped
/// tuning and an empty colour list before the strict decoder or gallery sees it. Delete after the
/// owner confirms their Projects, saved Versions and Trash open correctly.
enum LegacyMaskRepair {
    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "MaskRepair")
    enum Outcome: Equatable { case alreadyCurrent, repaired, unreadable, notWritten }

    static func repairLibrary() {
        let candidates = LibraryRepair.packages(leavingUntouched: nil).filter { package in
            guard let data = try? Data(contentsOf: package.url.appendingPathComponent("manifest.json")) else { return false }
            return data.range(of: Data("\"alphaMask\"".utf8)) != nil
        }
        guard !candidates.isEmpty else { return }
        let snapshot = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
        for package in candidates where !package.url.lastPathComponent.hasPrefix(snapshot)
            && FileManager.default.fileExists(atPath: package.url.path) {
            let result = repair(packageAt: package.url)
            if result == .unreadable || result == .notWritten {
                log.error("Mask repair \(String(describing: result), privacy: .public): \(package.path, privacy: .public)")
            }
        }
    }

    static func repair(packageAt package: URL) -> Outcome {
        let url = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        var changed = false
        do {
            for list in ["layers", "folders"] {
                guard var nodes = manifest[list] as? [[String: Any]] else { continue }
                for index in nodes.indices {
                    guard var mask = nodes[index]["alphaMask"] as? [String: Any] else { continue }
                    // Only the earlier shape is repaired; a partially written current record fails
                    // the current decoder, instead of being silently treated as an alpha mask.
                    guard mask["colours"] == nil, mask["threshold"] == nil,
                          mask["antialiasHalfWidth"] == nil else { continue }
                    // The earlier decoder's defaults, confined to this one-shot repair.
                    mask["sources"] = mask["sources"] ?? []
                    mask["isEnabled"] = mask["isEnabled"] ?? true
                    mask["invert"] = mask["invert"] ?? false
                    mask["colours"] = []
                    mask["threshold"] = 0.1
                    mask["antialiasHalfWidth"] = 0.01
                    _ = try JSONDecoder().decode(AlphaMask.self, from: JSONSerialization.data(withJSONObject: mask))
                    nodes[index]["alphaMask"] = mask
                    changed = true
                }
                manifest[list] = nodes
            }
        } catch { return .unreadable }
        guard changed else { return .alreadyCurrent }
        var written = false
        LibraryRepair.keepingItsDate(package) {
            written = LibraryRepair.write(manifest, to: url)
            return written
        }
        return written ? .repaired : .notWritten
    }
}
