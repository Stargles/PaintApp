import XCTest
import UIKit

/// **Kept bake files** (`KeptBakes`): the file layer — token, promote, adopt, the launch pass. What the
/// baker does with them is `FrameBakerLogicTests`' adoption tests.
final class KeptBakesLogicTests: XCTestCase {

    private var base: URL!

    override func setUp() {
        super.setUp()
        base = FileManager.default.temporaryDirectory.appendingPathComponent("KeptBakes-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
        super.tearDown()
    }

    private func key(_ seed: UInt8) -> FrameBakeKey { FrameBakeKey(rawDigest: Data(repeating: seed, count: 32)) }

    /// Writes a real bake file into a working store and answers its URL.
    private func bake(_ seed: UInt8, in store: FrameBakeStore, color: UInt8 = 200) -> URL {
        let pixels = [UInt8](repeating: color, count: 8 * 8 * 4)
        if case .failure = store.store(pixels: (pixels, 8, 8), for: key(seed)) { XCTFail("the fixture bake must write") }
        return store.url(for: key(seed))
    }

    func testTheTokenIsTheManifestsAndMovesWithIt() throws {
        let package = base.appendingPathComponent("a.paintproj", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        XCTAssertNil(KeptBakes.token(ofPackageAt: package), "no manifest, no token")
        try Data("one".utf8).write(to: package.appendingPathComponent("manifest.json"))
        let first = try XCTUnwrap(KeptBakes.token(ofPackageAt: package))
        XCTAssertEqual(KeptBakes.token(ofPackageAt: package), first)
        try Data("two".utf8).write(to: package.appendingPathComponent("manifest.json"))
        XCTAssertNotEqual(KeptBakes.token(ofPackageAt: package), first, "any save rewrites the manifest, so is a new token")
    }

    /// **A save replaces the kept set, nearest the playhead first, within the limit** — and every older
    /// token's set goes with it.
    func testPromoteKeepsTheNearestFramesWithinTheLimitAndDropsOlderSets() throws {
        let store = FrameBakeStore(root: base.appendingPathComponent("work"), byteCeiling: 1 << 24)
        let files = (0..<4).map { (frame: $0, source: bake(UInt8($0 + 1), in: store)) }
        let size = try XCTUnwrap(try files[0].source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let root = base.appendingPathComponent("kept")

        XCTAssertEqual(KeptBakes.promote(files, playhead: 3, root: root, token: "old", limit: .max / 2), 4)
        XCTAssertEqual(KeptBakes.frames(in: root, token: "old"), [0, 1, 2, 3])

        XCTAssertEqual(KeptBakes.promote(files, playhead: 3, root: root, token: "new", limit: size * 2 + 1), 2)
        XCTAssertEqual(KeptBakes.frames(in: root, token: "new"), [2, 3], "the two nearest the playhead")
        XCTAssertEqual(KeptBakes.frames(in: root, token: "old"), [], "an older save's set is gone")
    }

    /// **An adopted file reads as the new key's, and the kept copy is untouched.**
    func testAdoptMakesAFileTheSessionsKeyReadsAndLeavesTheKeptCopyAlone() throws {
        let work = FrameBakeStore(root: base.appendingPathComponent("work"), byteCeiling: 1 << 24)
        let source = bake(1, in: work, color: 77)
        let root = base.appendingPathComponent("kept")
        KeptBakes.promote([(frame: 5, source: source)], playhead: 5, root: root, token: "t", limit: .max / 2)
        let keptBefore = try Data(contentsOf: root.appendingPathComponent("t/5.pbk"))

        let next = FrameBakeStore(root: base.appendingPathComponent("next"), byteCeiling: 1 << 24)
        XCTAssertTrue(next.adopt(frame: 5, from: (root, "t"), as: key(9)))
        XCTAssertTrue(next.contains(key(9)))
        let decoded = try XCTUnwrap(next.loadDecoded(key(9)), "the digest was rewritten to the new key")
        XCTAssertEqual(decoded.pixels[0], 77)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("t/5.pbk")), keptBefore, "the kept file is never written")
        XCTAssertFalse(next.adopt(frame: 6, from: (root, "t"), as: key(10)), "no kept file for frame 6")
    }

    /// A kept file this build cannot read is a miss — the frame is baked again.
    func testAnUnreadableKeptFileIsAMiss() throws {
        let root = base.appendingPathComponent("kept")
        let dir = root.appendingPathComponent("t", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: dir.appendingPathComponent("0.pbk"))
        let next = FrameBakeStore(root: base.appendingPathComponent("next"), byteCeiling: 1 << 24)
        XCTAssertFalse(next.adopt(frame: 0, from: (root, "t"), as: key(1)))
        XCTAssertFalse(next.contains(key(1)))
    }

    /// **The setting at launch**: off empties the folder, as the bake always was; on drops the frames of a
    /// project that is gone and trims the rest to the limit, least recently written first.
    func testTheLaunchPassEmptiesWhenOffAndSweepsAndTrimsWhenOn() throws {
        let projects = base.appendingPathComponent("Projects", isDirectory: true)
        let live = UUID(), gone = UUID(), older = UUID()
        func seed(_ id: UUID, bytes: Int, modified: Date) throws {
            let dir = KeptBakes.root(projectsDirectory: projects, projectID: id, renderResolution: .full)
                .appendingPathComponent("t", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(count: bytes).write(to: dir.appendingPathComponent("0.pbk"))
            let project = KeptBakes.folder(in: projects).appendingPathComponent(id.uuidString)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: project.path)
        }
        func exists(_ id: UUID) -> Bool {
            FileManager.default.fileExists(atPath: KeptBakes.folder(in: projects).appendingPathComponent(id.uuidString).path)
        }
        try seed(live, bytes: 1000, modified: Date())
        try seed(gone, bytes: 1000, modified: Date())
        try seed(older, bytes: 1000, modified: Date(timeIntervalSinceNow: -1000))

        KeptBakes.launchPass(projectsDirectory: projects, keeping: true, liveProjectIDs: { [live, older] }, limit: 1500)
        XCTAssertTrue(exists(live), "the newest live project stays")
        XCTAssertFalse(exists(gone), "a trashed or deleted project's frames are swept")
        XCTAssertFalse(exists(older), "over the limit, the least recently written goes")

        KeptBakes.launchPass(projectsDirectory: projects, keeping: false, liveProjectIDs: { [live] }, limit: .max)
        XCTAssertFalse(FileManager.default.fileExists(atPath: KeptBakes.folder(in: projects).path), "off: emptied at launch")
    }

    func testTheSettingDefaultsOffAndPersists() {
        let suite = UserDefaults(suiteName: "KeptBakesLogicTests-" + UUID().uuidString)!
        let settings = AppSettings(defaults: suite)
        XCTAssertFalse(settings.keepBakedFrames, "default off (owner ruling Q2)")
        settings.keepBakedFrames = true
        XCTAssertTrue(AppSettings(defaults: suite).keepBakedFrames)
    }
}
