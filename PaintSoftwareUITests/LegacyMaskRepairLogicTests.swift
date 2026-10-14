import XCTest

@MainActor
final class LegacyMaskRepairLogicTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mask-repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }
    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try FileManager.default.removeItem(at: root)
    }

    // Copied from the owner's 2026-10-09 previous-build package, evidence-153/Backups/
    // 936C4492-5737-45C8-841A-3ADD65B16A5E/latest.paintproj/manifest.json. Artwork stays outside git.
    private let previousMask = #"{"sources":[{"kind":"layer","id":"7D7F35BB-D277-42D0-BFF5-7C7C237A3645"},{"kind":"layer","id":"E331C25C-0F5D-421B-BACA-C2A90C0FFB4C"},{"kind":"layer","id":"62A497C2-04F1-466F-89AE-0C72A1917C68"}],"invert":false,"isEnabled":true}"#

    private func earlier(_ path: String) throws -> URL {
        let package = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let mask = try JSONSerialization.jsonObject(with: Data(previousMask.utf8))
        try JSONSerialization.data(withJSONObject: ["layers": [["alphaMask": mask]], "folders": [["alphaMask": mask]]])
            .write(to: package.appendingPathComponent("manifest.json"))
        return package
    }

    private func masks(_ package: URL) throws -> [AlphaMask] {
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent("manifest.json"))) as? [String: Any])
        return try ["layers", "folders"].flatMap { list -> [AlphaMask] in
            try XCTUnwrap(manifest[list] as? [[String: Any]]).map {
                try JSONDecoder().decode(AlphaMask.self, from: JSONSerialization.data(withJSONObject: try XCTUnwrap($0["alphaMask"])))
            }
        }
    }

    func testPreviousBuildMaskRepairsWithoutLosingPicksAndSecondPassChangesNothing() throws {
        let package = try earlier("Projects/earlier.paintproj")
        XCTAssertEqual(LegacyMaskRepair.repair(packageAt: package), .repaired)
        let rewritten = try masks(package)
        XCTAssertEqual(rewritten.map { [$0.sources.count, $0.colours.count] }, [[3, 0], [3, 0]])
        XCTAssertEqual(rewritten.map(\.threshold), [0.1, 0.1])
        XCTAssertEqual(rewritten.map(\.antialiasHalfWidth), [0.01, 0.01])
        XCTAssertEqual(rewritten.map(\.invert), [false, false])
        let once = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        XCTAssertEqual(LegacyMaskRepair.repair(packageAt: package), .alreadyCurrent)
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("manifest.json")), once)
    }

    func testLibraryWalkIncludesProjectsBackupsAndTrash() throws {
        let packages = try ["Projects/current.paintproj", "Backups/scene/latest.paintproj", "Trash/deleted.paintproj"].map(earlier)
        LegacyMaskRepair.repairLibrary()
        XCTAssertEqual(try packages.map { try masks($0).first?.sources.count }, [3, 3, 3])
    }

    func testBrokenEarlierPicksAreReportedAndNotRewritten() throws {
        let package = try earlier("Projects/broken.paintproj")
        let url = package.appendingPathComponent("manifest.json")
        let data = Data(#"{"layers":[{"alphaMask":{"sources":"broken","invert":false,"isEnabled":true}}]}"#.utf8)
        try data.write(to: url)
        XCTAssertEqual(LegacyMaskRepair.repair(packageAt: package), .unreadable)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
