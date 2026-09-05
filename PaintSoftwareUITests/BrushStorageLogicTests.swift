import XCTest
import UIKit

/// **BRUSH.md §2.27 — the brush library's storage is relocatable.**
///
/// The owner: *"Right now all the files are stored internally on the app, which means that if the
/// app gets deleted, then all the files get deleted too. I'd like it to be able to have an external
/// folder, so build the architecture so that in the future when this feature gets added, moving the
/// library from internal app storage to this external folder is easy."*
///
/// The external folder is not built. What these tests pin is the property that makes it cheap, and
/// **the shape of the assertions matters more here than usual** because the obvious version of every
/// one of them is green against the exact defect the feature exists to prevent:
///
/// * *Write a library, read it back, assert it is there* passes against an implementation that
///   stores absolute paths, because nothing moved. **The directory is moved on disk** in every test
///   below, and what is read afterwards is read from the new location.
/// * *Render after the move and compare to before* passes against an implementation that never
///   reads the disk again, because `BrushTextureStore` memoizes a mask against a file *name*. So
///   each render test carries a second operand — the same brush over an **empty** root — which is
///   what says the picture is a function of where the files are rather than of what was cached.
/// * *The file came back after a load* passes against a `ProjectStore` that still resolves
///   `Documents/Brushes`, because on a simulator that directory exists and is writable. So the
///   project test asserts the restored file is **under the injected root and not under the
///   application's**.
@MainActor
final class BrushStorageLogicTests: XCTestCase {

    /// Everything this file writes lives under here, including the roots it moves between, so a
    /// relocation is a rename inside one temporary tree.
    private var scratch: URL!
    /// What `BrushStorage.shared` pointed at when the test started. Restored in `tearDown`, because
    /// a storage whose root is left in a deleted temporary directory is CLAUDE.md's *"a static that
    /// outlives the test that set it"* reached through one more door — and this one would take every
    /// later brush test in the run with it.
    private var originalRoot: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("brush-storage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = scratch
        originalRoot = BrushStorage.shared.root
    }

    override func tearDownWithError() throws {
        // `relocate` rather than a bare assignment: it is also what drops the masks these tests
        // loaded out of a directory that is about to stop existing.
        BrushStorage.shared.relocate(to: originalRoot)
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
        originalRoot = nil
    }

    private func makeRoot(_ name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Requirement 2 — one root, owned by one type

    /// **Where the library actually is has not moved, and that is the constraint this change is most
    /// able to break silently.** §2.27 relocates the *ownership* of the root, not the root: every
    /// library and every project already on a device names files that live in `Documents/Brushes`,
    /// and a refactor that quietly landed them in Application Support would read as "the artist's
    /// brushes are gone" with nothing in a diff to point at.
    func testTheApplicationsRootIsStillDocumentsBrushes() throws {
        let documents = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        XCTAssertEqual(BrushStorage.applicationRoot,
                       documents.appendingPathComponent("Brushes", isDirectory: true))
        XCTAssertEqual(originalRoot, BrushStorage.applicationRoot,
                       "and the app's one storage starts there")
    }

    /// **Two libraries over two roots cannot see each other, and each round-trips its own.**
    ///
    /// This is the assertion relocation actually needs and it is unstateable against a single global
    /// directory: the old `BrushLibrary.customBrushesDirectory` had exactly one value per process,
    /// so "these two libraries are separate" had no way to be written down. A test that pointed both
    /// stores at one directory would pass against an implementation with no root at all.
    func testTwoLibrariesOverTwoRootsDoNotSeeEachOtherAndEachRoundTripsItsOwn() throws {
        let rootA = try makeRoot("A"), rootB = try makeRoot("B")
        let storageA = BrushStorage(root: rootA), storageB = BrushStorage(root: rootB)

        let a = BrushLibraryStore(storage: storageA, arguments: [])
        a.addGroup(name: "Only in A")
        let b = BrushLibraryStore(storage: storageB, arguments: [])
        b.addGroup(name: "Only in B")

        XCTAssertFalse(a.groups.contains { $0.name == "Only in B" },
                       "a library must not see what was written to another root")
        XCTAssertFalse(b.groups.contains { $0.name == "Only in A" })

        // And each survives being dropped and rebuilt over its own root — which is what says the
        // separation is on disk rather than only in two live objects.
        let reopenedA = BrushLibraryStore(storage: BrushStorage(root: rootA), arguments: [])
        let reopenedB = BrushLibraryStore(storage: BrushStorage(root: rootB), arguments: [])
        // §8.6's whole seeded set plus the one group each store added — it was `["Basics", …]`
        // until §12 stage 9 authored the shipped library, and deriving it keeps this test about
        // *separation* rather than about how many groups ship.
        let seeded = BrushLibrary.groups.map(\.name)
        XCTAssertEqual(reopenedA.groups.map(\.name), seeded + ["Only in A"])
        XCTAssertEqual(reopenedB.groups.map(\.name), seeded + ["Only in B"])
    }

    // MARK: - Requirement 1 — every stored reference is a name, never a path

    /// **A library written under one root is found under another when its folder moves**, which is
    /// the whole of what "relocatable" means and is only meaningful because the directory is moved
    /// **on disk**.
    ///
    /// Re-reading the same directory would pass against an implementation that wrote absolute paths
    /// into `library.json`, so that version of this test would be green against the exact defect
    /// §2.27 exists to prevent. The second operand is the bytes: whatever the library encodes, it
    /// must not encode either root.
    func testALibraryWrittenUnderOneRootIsFoundUnderAnotherWhenItsFolderMoves() throws {
        let rootA = try makeRoot("written-here")
        let rootB = scratch.appendingPathComponent("read-there", isDirectory: true)

        let tip = BrushTip.stamp(.imported(fileName: "custom-\(UUID().uuidString).png"))
        let written = BrushLibraryStore(storage: BrushStorage(root: rootA), arguments: [])
        let group = written.addGroup(name: "Imported")
        written.add(Brush(name: "Travelling", tip: tip, size: 21), toGroup: group.id)

        let json = try XCTUnwrap(String(data: try Data(contentsOf: rootA.appendingPathComponent(
            BrushLibraryStore.fileName)), encoding: .utf8))
        XCTAssertFalse(json.contains(rootA.path),
                       "a library that writes down where it was written cannot be moved")
        XCTAssertFalse(json.contains("/"), "and nothing in it is a path of any shape")

        try FileManager.default.moveItem(at: rootA, to: rootB)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootA.path), "PREMISE: A is gone")

        let read = BrushLibraryStore(storage: BrushStorage(root: rootB), arguments: [])
        let travelled = try XCTUnwrap(read.allBrushes.first { $0.name == "Travelling" })
        XCTAssertEqual(travelled.tip, tip, "the brush comes back naming the same file")
        XCTAssertEqual(read.groups.map(\.name), BrushLibrary.groups.map(\.name) + ["Imported"])
    }

    /// **An imported tip and a textured brush both survive the move**, which is two tests in one
    /// because they are two different naming routes into the same store: `BrushTip.stamp` and
    /// `BrushTextureSettings.mask`. A relocation that carried one and not the other would look
    /// correct in a picker and wrong on the canvas.
    ///
    /// **The empty-root render is the operand that makes the comparison mean something.**
    /// `BrushTextureStore` memoizes a mask against a file *name*, so a process that had already
    /// drawn this brush would keep drawing it whatever happened to the disk — this test's "identical
    /// after the move" would then be true of an implementation that never resolved a file at all.
    /// Pointing the same brush at a root with nothing in it must produce a blank canvas; that is
    /// what says the ink is a function of where the files are.
    func testAnImportedTipAndATexturedBrushBothSurviveTheirFolderMoving() throws {
        let rootA = try makeRoot("library-A")
        let rootB = scratch.appendingPathComponent("library-B", isDirectory: true)
        let empty = try makeRoot("library-empty")
        BrushStorage.shared.relocate(to: rootA)

        let tip = try BrushTipImport.importTip(from: Self.disc(side: 96))
        let tipFile = try XCTUnwrap(tip.importedTextureFileName)
        XCTAssertTrue(BrushStorage.shared.contains(tipFile),
                      "PREMISE: the import wrote into the storage's root, not the app's")
        let sheet = try Self.writeCheckerSheet()

        let brush = Brush(name: "moved", tip: tip, size: 14,
                          dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.1, hardness: 1),
                          modulations: BrushModulations(),
                          texture: BrushTextureSettings(mask: sheet, tileSize: 32))
        let before = try Self.render(brush)
        XCTAssertFalse(Self.isBlank(before), "fixture precondition: the brush drew something")

        try FileManager.default.moveItem(at: rootA, to: rootB)
        BrushStorage.shared.relocate(to: rootB)
        XCTAssertEqual(try Self.render(brush), before,
                       "moving the library's folder must change no pixel — every reference the app "
                       + "stores is a name, so there is nothing pointing at the old location")

        BrushStorage.shared.relocate(to: empty)
        XCTAssertTrue(Self.isBlank(try Self.render(brush)),
                      "and the same brush over a root holding neither file must draw nothing — "
                      + "without this the comparison above is green against an implementation that "
                      + "resolves no file at all and serves the process's cache")
    }

    // MARK: - Requirement 3 — every access goes through the one type

    /// **A project saved and reopened renders identically with a non-default root**, and its brush
    /// files come back **into that root**.
    ///
    /// §5.4's save-time copy and load-time restore walk the union of the document's table and the
    /// palette; both sides touch the library, so both are places a stale `Documents/Brushes` would
    /// survive a refactor. The file-location assertion is the discriminating one: a simulator's
    /// `Documents/Brushes` exists and is writable, so a `ProjectStore` that still resolved it would
    /// pass every pixel comparison here while writing the artist's tips somewhere the library is not.
    func testAProjectSavedAndReopenedUnderANonDefaultRootRestoresIntoThatRoot() throws {
        let root = try makeRoot("project-library")
        BrushStorage.shared.relocate(to: root)

        let tip = try BrushTipImport.importTip(from: Self.disc(side: 96))
        let tipFile = try XCTUnwrap(tip.importedTextureFileName)
        let sheet = try Self.writeCheckerSheet()
        let sheetFile = try XCTUnwrap(sheet.importedFileName)
        let brush = Brush(name: "packaged", tip: tip, size: 14,
                          dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.1, hardness: 1),
                          modulations: BrushModulations(),
                          texture: BrushTextureSettings(mask: sheet, tileSize: 32))

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        vector.addStroke(Self.stroke(brush))
        let expected = try Self.pixels(vector.render())
        XCTAssertFalse(expected.isBlank, "fixture precondition: the stroke drew something")

        let url = ProjectStore.createNewProjectURL(name: "Relocated")
        let saved = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        wait(for: [saved], timeout: 30)

        // The library forgets both files, which is what another device looks like from the
        // document's point of view — and is what makes the load's restore do work.
        for name in [tipFile, sheetFile] { BrushStorage.shared.remove(name) }
        XCTAssertFalse(BrushStorage.shared.contains(tipFile), "PREMISE: the library is empty of it")
        BrushStorage.shared.relocate(to: root) // drop the masks read before the deletion

        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        for name in [tipFile, sheetFile] {
            XCTAssertTrue(BrushStorage.shared.contains(name),
                          "a load puts \(name) back so the brush still renders")
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: BrushStorage.applicationRoot.appendingPathComponent(name).path),
                           "and it goes into the library that is configured, not into "
                           + "Documents/Brushes — which exists here and would swallow it silently")
        }

        let canvas = try XCTUnwrap(reopened.layers.compactMap { $0.cels.first?.vector }
                                                  .first { !$0.strokes.isEmpty })
        XCTAssertEqual(try Self.pixels(canvas.render()).bytes, expected.bytes,
                       "and the ink is unchanged by a save and reopen under a relocated library")
    }

    // MARK: - Fixtures

    private struct Pixels {
        let bytes: [UInt8]
        var isBlank: Bool { !stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 } }
    }

    private static let canvas = CGSize(width: 96, height: 96)

    private static func stroke(_ brush: Brush) -> VectorStroke {
        VectorStroke(id: UUID(), brush: brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 14, opacity: 1,
                     samples: [VectorSample(x: 12, y: 48, pressure: 1),
                               VectorSample(x: 48, y: 48, pressure: 1),
                               VectorSample(x: 84, y: 48, pressure: 1)])
    }

    private static func render(_ brush: Brush) throws -> [UInt8] {
        let vector = VectorCanvas(size: canvas)
        vector.addStroke(stroke(brush))
        return try pixels(vector.render()).bytes
    }

    private static func isBlank(_ bytes: [UInt8]) -> Bool { Pixels(bytes: bytes).isBlank }

    private static func pixels(_ image: UIImage) throws -> Pixels {
        let cg = try XCTUnwrap(image.cgImage)
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(ok, "the read-back context could not be built")
        return Pixels(bytes: bytes)
    }

    /// A black disc on white — opaque, so `BrushTipImport` reads it by luminance, which is the arm
    /// an artist's own picture takes. Narrow enough not to fill its mask: a tip that covers its
    /// whole square is indistinguishable from the committed square, which is `BrushTipLogicTests`'
    /// own finding about what makes a tip fixture discriminating.
    private static func disc(side: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.black.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: side / 4, y: side / 4,
                                                 width: side / 2, height: side / 2))
        }
    }

    /// A 64² checkerboard alpha sheet, written straight into the library rather than through
    /// `BrushTipImport` — the import's letterbox and transparent border are right for a tip and
    /// wrong for paper that has to tile, which `BrushTextureLogicTests` records at length.
    private static func writeCheckerSheet(cell: Int = 16, side: Int = 64) throws -> BrushTextureRef {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(UIColor.black.cgColor)
        for row in 0..<(side / cell) {
            for column in 0..<(side / cell) where (row + column) % 2 == 0 {
                ctx.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
            }
        }
        let data = try XCTUnwrap(UIImage(cgImage: try XCTUnwrap(ctx.makeImage())).pngData())
        let fileName = "test-sheet-\(UUID().uuidString).png"
        try BrushStorage.shared.write(data, to: fileName)
        return .imported(fileName: fileName)
    }
}
