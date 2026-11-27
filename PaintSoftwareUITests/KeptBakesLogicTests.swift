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

    /// A package with a manifest and, optionally, a kept set for `token` in `bakes/full/<token>/`.
    /// `keptFor: "current"` files the set under the manifest's own token.
    private func package(_ name: String, manifest: String, keptFor kept: String? = nil, bytes: Int = 1000,
                         modified: Date = Date()) throws -> URL {
        let url = base.appendingPathComponent(name + ".paintproj", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: url.appendingPathComponent("manifest.json"))
        if let kept {
            let token = kept == "current" ? try XCTUnwrap(KeptBakes.token(ofPackageAt: url)) : kept
            let dir = KeptBakes.root(package: url, renderResolution: .full).appendingPathComponent(token, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(count: bytes).write(to: dir.appendingPathComponent("0.pbk"))
            try FileManager.default.setAttributes([.modificationDate: modified],
                                                  ofItemAtPath: url.appendingPathComponent(KeptBakes.folderName).path)
        }
        return url
    }

    private func hasBakes(_ package: URL) -> Bool {
        FileManager.default.fileExists(atPath: package.appendingPathComponent(KeptBakes.folderName).path)
    }

    /// **Kept frames live inside the package and never change its token**: the token hashes the manifest,
    /// so a set promoted into the package is still the set that package's manifest asks for.
    func testAKeptSetInsideThePackageLeavesItsTokenAlone() throws {
        let pkg = try package("a", manifest: "one")
        let token = try XCTUnwrap(KeptBakes.token(ofPackageAt: pkg))
        let store = FrameBakeStore(root: base.appendingPathComponent("work"), byteCeiling: 1 << 24)
        let files = [(frame: 0, source: bake(1, in: store))]
        let root = KeptBakes.root(package: pkg, renderResolution: .full)
        XCTAssertEqual(KeptBakes.promote(files, playhead: 0, root: root, token: token, limit: .max / 2), 1)
        XCTAssertEqual(KeptBakes.token(ofPackageAt: pkg), token, "the bakes are not part of what the token names")
        XCTAssertEqual(KeptBakes.frames(in: root, token: token), [0])
        XCTAssertTrue(root.path.hasPrefix(pkg.path + "/"), "inside the package, so it follows the package")
    }

    /// **The setting at launch**: off strips every package's bakes (a scene holds none, including ones it
    /// arrived with); on keeps only the set the manifest asks for — a duplicate's or an older save's goes —
    /// and trims the rest to the limit, the least recently written package's first.
    func testTheLaunchPassStripsWhenOffAndSweepsStaleSetsAndTrimsWhenOn() throws {
        func make() throws -> (live: URL, stale: URL, older: URL) {
            (try package("live", manifest: "m1", keptFor: "current"),
             try package("stale", manifest: "m2", keptFor: "not-the-manifests"),
             try package("older", manifest: "m3", keptFor: "current", modified: Date(timeIntervalSinceNow: -1000)))
        }
        let (live, stale, older) = try make()
        KeptBakes.launchPass(packages: [live, stale, older], keeping: true, limit: 1500)
        XCTAssertTrue(hasBakes(live), "the newest package's current set stays")
        XCTAssertFalse(hasBakes(stale), "a set no manifest asks for is swept")
        XCTAssertFalse(hasBakes(older), "over the limit, the least recently written goes")

        KeptBakes.launchPass(packages: [live, stale, older], keeping: false, limit: .max)
        XCTAssertFalse(hasBakes(live), "off: stripped from every package at launch")
    }

    func testTheSettingDefaultsOffAndPersists() {
        let suite = UserDefaults(suiteName: "KeptBakesLogicTests-" + UUID().uuidString)!
        let settings = AppSettings(defaults: suite)
        XCTAssertFalse(settings.keepBakedFrames, "default off (owner ruling Q2)")
        settings.keepBakedFrames = true
        XCTAssertTrue(AppSettings(defaults: suite).keepBakedFrames)
    }
}
