import XCTest
import UIKit


/// **BRUSH.md §7.1 and §8.1 — the brushes menu's model, its persistence, and its row previews.**
///
/// Every test here points its store at a temporary directory of its own. `BrushLibraryStore.shared`
/// writes into `Documents/Brushes/library.json`, and CLAUDE.md's section on a `UserDefaults`-backed
/// static leaking 15 reds into a *later* suite is about exactly this hazard reached through a
/// different door — a file survives the process that wrote it just as a defaults key does.
final class BrushLibraryLogicTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("brushLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func makeStore() -> BrushLibraryStore {
        // `arguments: []` rather than the process's own: a test must not inherit `-resetBrushLibrary`
        // from whatever launched the runner, and must not be affected by its absence either.
        BrushLibraryStore(storage: BrushStorage(root: directory), arguments: [])
    }

    // MARK: - The seeded library

    /// **A device that has never held a library gets §8.6's set** — five groups and twenty brushes,
    /// in the owner's own order. Authored at §12 stage 9; before it this seeded one "Basics" group
    /// holding the five legacy presets.
    ///
    /// **Texture was empty here until §12 stage 11 and is asserted full now.** It shipped empty
    /// because §8.3 gates CC0 sourcing on a per-file licence check; §13 asked whether the generator
    /// made that unnecessary and round four's contact sheet answered yes, so the four are generated
    /// like every other tip and the count is four rather than zero.
    func testAFreshLibrarySeedsTheShippedGroupsAndTheirBrushes() {
        let store = makeStore()
        XCTAssertEqual(store.groups.map(\.name),
                       ["Basics", "Sketching", "Inking", "Painting", "Texture"])
        XCTAssertEqual(store.groups.map(\.brushes.count), [5, 4, 4, 3, 4])
        XCTAssertEqual(store.allBrushes.count, 20)
        XCTAssertEqual(store.allBrushes.count, BrushLibrary.defaults.count)
        XCTAssertEqual(Set(store.allBrushes.map(\.id)).count, 20,
                       "twenty written-down ids, and no two the same — a collision makes the "
                       + "picker highlight two rows and `update(_:)` write to one of them")
        XCTAssertEqual(Set(store.groups.map(\.id)).count, 5)
    }

    /// **Every shipped preset's tip resolves to a mask that is actually in the bundle.**
    ///
    /// A preset naming a file the app does not carry is a brush that stamps *nothing* —
    /// `BrushTextureStore.mask(for:)` answers nil and `stampDab` skips the dab, which is the honest
    /// failure for a deleted import and a silent catastrophe for a shipped preset. No assertion on
    /// the model can see it: `.stamp(.builtIn(.pencilHard))` is a perfectly well-formed value
    /// whether or not `brushtip-pencil-hard.png` was ever added to the target.
    func testEveryShippedPresetsTipIsAMaskTheBundleActuallyCarries() throws {
        var stamped = 0
        for brush in BrushLibrary.defaults {
            switch brush.tip {
            case .round:
                continue
            case .stamp(let ref):
                stamped += 1
                guard case .builtIn = ref else {
                    return XCTFail("\(brush.name) names \(ref): a shipped preset cannot depend on a "
                                   + "file in the artist's own library")
                }
                let mask = BrushTextureStore.mask(for: ref)
                XCTAssertNotNil(mask, "\(brush.name)'s tip \(ref) is not in the bundle — that brush "
                                + "stamps nothing at all")
                XCTAssertEqual(mask?.width, BrushTipImport.maskSide, brush.name)
                XCTAssertEqual(mask?.height, BrushTipImport.maskSide, brush.name)
            }
        }
        XCTAssertEqual(stamped, 15,
                       "PREMISE: fifteen of §8.6's twenty carry a picture and five are answered by "
                       + "arithmetic — if this moves, the count above is stale rather than wrong")
    }

    /// **And every shipped preset actually lays ink.** The check above says the file is there; this
    /// says the brush draws with it. A tip whose mask is entirely transparent, a `flow` of zero or a
    /// `size` base of zero all pass every structural assertion and paint a blank canvas.
    func testEveryShippedPresetLaysInkOnAPlainStroke() {
        for brush in BrushLibrary.defaults {
            let image = BrushPreview.render(brush, size: Self.previewSize, scale: 2, color: .white)
            let inked = nonTransparentPixelCount(image)
            XCTAssertGreaterThan(inked, 40, "\(brush.name) drew \(inked) pixels — it is unusable")
        }
    }

    /// Seeding writes no file. A library nobody has touched is one the *next* build's seed may still
    /// change; persisting it on first read would freeze today's set onto every device before a later
    /// stage got to add to it.
    func testSeedingDoesNotWriteAFile() {
        _ = makeStore()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(BrushLibraryStore.fileName).path),
                       "A library that was only seeded, never edited, should leave no file behind")
    }

    // MARK: - Ordering and rename — the two things §8.2's layer tree cannot express

    /// **An empty group can be placed, and this is the refutation of BRUSH.md §8.2.**
    ///
    /// `LayerFolder` carries no ordering field: `CanvasManager.containerEntries` derives a folder's
    /// position from the topmost `layers` index its contents occupy, and an *empty* folder has no
    /// span at all — it sorts to `Int.max` and pins to the top of its container. An artist who makes
    /// a brush group and then fills it would watch it move. Ordering here is an array index, so a
    /// group that holds nothing sits exactly where it was put.
    ///
    /// **The two groups are named "Comics" and "Washes" and neither is one of §8.6's**, which was
    /// not true before §12 stage 9 authored the shipped set: `addGroup(name:)` uniques its argument,
    /// so asking for "Inking" against a library that now seeds one gets back "Inking 2" and every
    /// name assertion below reads as a broken ordering.
    func testAnEmptyGroupKeepsThePositionItWasMovedTo() {
        let store = makeStore()
        let comics = store.addGroup(name: "Comics")
        let washes = store.addGroup(name: "Washes")
        XCTAssertEqual(store.groups.suffix(2).map(\.name), ["Comics", "Washes"])
        XCTAssertTrue(comics.brushes.isEmpty, "PREMISE: a new group is empty")

        store.moveGroup(washes.id, by: -1)
        XCTAssertEqual(store.groups.suffix(2).map(\.name), ["Washes", "Comics"],
                       "An empty group must sit where it was placed, not float to the top")

        // And it stays there once it has contents, which is the half a span-derived order gets right.
        store.add(BrushLibrary.brushPen, toGroup: comics.id)
        XCTAssertEqual(store.groups.suffix(2).map(\.name), ["Washes", "Comics"])
    }

    func testRenamingAGroupKeepsItsIdentityAndItsBrushes() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.groups.first).id
        store.renameGroup(id, to: "Everyday")
        XCTAssertEqual(store.groups.first?.name, "Everyday")
        XCTAssertEqual(store.groups.first?.id, id, "A rename is not a new group")
        XCTAssertEqual(store.groups.first?.brushes.count, 5)
    }

    /// An empty rename is refused rather than applied: a group with no name is a row an artist cannot
    /// aim at, and the alert's Cancel is already the way to change nothing.
    func testAnEmptyRenameIsRefused() throws {
        let store = makeStore()
        store.renameGroup(try XCTUnwrap(store.groups.first).id, to: "   ")
        XCTAssertEqual(store.groups.first?.name, "Basics")
    }

    /// The last group cannot be deleted. With no groups there is no column, and the `+` that would
    /// make one lives above a menu that has nothing to show — the closed loop CLAUDE.md's
    /// three-unusable-features section warns about.
    func testTheLastGroupCannotBeDeleted() throws {
        let store = makeStore()
        let seeded = store.groups.map(\.name)
        XCTAssertGreaterThan(seeded.count, 1, "PREMISE: §8.6 seeds several groups")

        let added = store.addGroup(name: "Comics")
        XCTAssertTrue(store.removeGroup(added.id))
        XCTAssertEqual(store.groups.map(\.name), seeded)

        // Down to one, then refused.
        for name in seeded.dropFirst() {
            let group = try XCTUnwrap(store.groups.first { $0.name == name })
            XCTAssertTrue(store.removeGroup(group.id))
        }
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertFalse(store.removeGroup(try XCTUnwrap(store.groups.first).id))
        XCTAssertEqual(store.groups.count, 1)
    }

    /// A brush lives in exactly one group, so adding one it already holds moves it rather than
    /// duplicating it. Without this the same brush would render twice in the menu and the second row
    /// would be unselectable — both rows carry the same id, so both would highlight.
    func testAddingABrushToASecondGroupMovesItRatherThanCopyingIt() {
        let store = makeStore()
        let comics = store.addGroup(name: "Comics")
        store.add(BrushLibrary.brushPen, toGroup: comics.id)

        XCTAssertEqual(store.groups.first { $0.name == "Inking" }?.brushes.map(\.name),
                       ["Technical Pen — Fine", "Rough Ink — Blotchy", "Rough Ink"],
                       "Brush Pen left the group it was seeded into")
        XCTAssertEqual(store.groups.last?.brushes.map(\.name), ["Brush Pen"])
        XCTAssertEqual(store.allBrushes.filter { $0.id == BrushLibrary.brushPen.id }.count, 1)
    }

    // MARK: - Persistence

    /// **A round trip across a launch, decoded from bytes written down here.**
    ///
    /// BRUSH.md §12 stage 5 records the mistake this avoids being made in this very file: a `static
    /// let` holds one value for a process's life, so a test that encodes and then decodes in the same
    /// process can agree with itself about something no *file* would ever say. These bytes were typed,
    /// not produced by the encoder under test.
    func testALibraryWrittenDownInThisSourceDecodesToTheGroupsItNames() throws {
        let json = """
        {
          "version" : 1,
          "groups" : [
            {
              "id" : "B7051000-0000-4000-B000-000000000001",
              "name" : "Everyday",
              "brushes" : [
                {
                  "id" : "B7051000-0000-4000-A000-000000000004",
                  "name" : "Pen",
                  "tip" : { "kind" : "round" },
                  "size" : 4,
                  "opacity" : 1
                }
              ]
            },
            {
              "id" : "44444444-0000-4000-B000-000000000002",
              "name" : "Inking",
              "brushes" : [
                {
                  "id" : "44444444-0000-4000-A000-000000000009",
                  "name" : "Rough Nib",
                  "tip" : { "kind" : "stamp", "texture" : { "builtIn" : "square" } },
                  "size" : 12,
                  "opacity" : 0.5,
                  "dab" : { "spacing" : 0.25 }
                }
              ]
            }
          ]
        }
        """
        let url = directory.appendingPathComponent(BrushLibraryStore.fileName)
        try Data(json.utf8).write(to: url)

        let store = makeStore()
        XCTAssertEqual(store.groups.map(\.name), ["Everyday", "Inking"],
                       "The group the artist renamed, and the one they added, both come back")
        XCTAssertEqual(store.groups.first?.brushes.map(\.name), ["Pen"])

        let nib = try XCTUnwrap(store.groups.dropFirst().first?.brushes.first)
        XCTAssertEqual(nib.name, "Rough Nib")
        XCTAssertEqual(nib.size, 12)
        XCTAssertEqual(nib.opacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(nib.dab.spacing, 0.25, accuracy: 1e-9)
        XCTAssertEqual(nib.tip, .stamp(.builtIn(.square)), "The tip is a picture, and it came back as one")
    }

    /// **A library written in *today's* format still round-trips, and the two migrations do not touch
    /// it.**
    ///
    /// The companion to `testTheOwnersOwnLibraryOpensRatherThanBeingReplacedByTheShippedSet`, and the
    /// half a migration most easily breaks: a reader that splits a `scatter` row into two must leave a
    /// `scatterAcross` row as *one* row, and a dab that already names both axes must keep the two
    /// different numbers it names rather than collapsing them. These bytes were typed, not produced by
    /// the encoder under test — §12 stage 5's rule, and the reason is that an encode-then-decode in
    /// one process can agree with itself about something no file would ever say.
    ///
    /// The dab's two axes are deliberately **unequal**, which no pre-§2.30 file could express: it is
    /// what says the reader is taking them from the bytes rather than from one number twice.
    func testALibraryInTodaysFormatIsUntouchedByTheTwoMigrations() throws {
        let json = """
        {
          "version" : 1,
          "groups" : [
            {
              "id" : "77777777-0000-4000-B000-000000000001",
              "name" : "Modern",
              "brushes" : [
                {
                  "id" : "77777777-0000-4000-A000-000000000001",
                  "name" : "Two Axes",
                  "tip" : { "kind" : "round" },
                  "size" : 9,
                  "opacity" : 1,
                  "dab" : { "scatterAcross" : 0.4, "scatterAlong" : 0.1, "density" : 0.5 },
                  "modulations" : [
                    { "output" : "scatterAcross", "amount" : 0.25,
                      "input" : { "kind" : "random", "wavelength" : 2 } },
                    { "output" : "density", "amount" : -0.5,
                      "input" : { "kind" : "random", "wavelength" : 3 } }
                  ]
                }
              ]
            }
          ]
        }
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent(BrushLibraryStore.fileName))

        let brush = try XCTUnwrap(makeStore().allBrushes.first)
        XCTAssertEqual(brush.name, "Two Axes")
        XCTAssertEqual(brush.dab.scatterAcross, 0.4, accuracy: 1e-12)
        XCTAssertEqual(brush.dab.scatterAlong, 0.1, accuracy: 1e-12,
                       "two axes written down stay two numbers — §2.30's base migration must not fire")
        XCTAssertEqual(brush.modulations.rows(for: .scatterAcross).count, 1,
                       "a modern row is one row: the split fires on the deleted output's name only")
        XCTAssertTrue(brush.modulations.rows(for: .scatterAlong).isEmpty)
        XCTAssertEqual(brush.modulations.rows(for: .scatterAcross).first?.amount, 0.25)
        XCTAssertEqual(brush.dab.density, 0.5, accuracy: 1e-12,
                       "and with no legacy λ on the dab, §2.32's density migration must not fire "
                       + "either — a gate written at the threshold stays at the threshold")
        XCTAssertEqual(brush.modulations.rows(for: .density).count, 1,
                       "…and no second density row is appended")

        // The write half, over the same store: what it saves is what a second store reads.
        let store = makeStore()
        var edited = brush
        edited.dab.scatterAlong = 0.7
        store.update(edited)
        XCTAssertEqual(makeStore().allBrushes.first?.dab.scatterAlong, 0.7,
                       "the format the app writes is the format it reads")
    }

    /// The write half: a rename and an added brush survive the store being dropped and a *second*
    /// one built over the same directory, which is what a relaunch is.
    func testARenamedGroupAndAnAddedBrushSurviveARelaunch() throws {
        let custom = Brush(id: UUID(uuidString: "5E5E5E5E-0000-4000-A000-000000000001")!,
                           name: "My Nib", tip: .stamp(.builtIn(.square)), size: 30, opacity: 0.75,
                           dab: BrushDabSettings(spacing: 0.2))
        var expected: [String] = []
        do {
            let first = makeStore()
            first.renameGroup(try XCTUnwrap(first.groups.first).id, to: "Everyday")
            let comics = first.addGroup(name: "Comics")
            first.add(custom, toGroup: comics.id)
            expected = first.groups.map(\.name)
        }

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.groups.map(\.name), expected)
        XCTAssertEqual(expected.first, "Everyday")
        XCTAssertEqual(expected.last, "Comics")
        // `dropFirst().first`, not `[1]`: when this test caught a mutation that stopped the store
        // writing, an index would have trapped and taken the whole class down with it — a red test
        // must fail, not crash the runner out of the fifteen behind it.
        let restored = try XCTUnwrap(relaunched.groups.last?.brushes.first)
        XCTAssertEqual(restored, custom, "The brush comes back byte-for-byte, not merely by name")
        XCTAssertEqual(relaunched.groupToOpen(forSelected: custom.id)?.name, "Comics",
                       "…and the menu opens onto the group holding whatever is selected")
    }

    /// A corrupt or truncated file reseeds rather than leaving the artist with no brushes at all. A
    /// library that failed to decode into *nothing* is a picker with no rows and a `+` above it.
    func testAnUnreadableLibraryReseedsRatherThanEmptying() throws {
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent(BrushLibraryStore.fileName))
        XCTAssertEqual(makeStore().groups.map(\.name),
                       BrushLibrary.groups.map(\.name),
                       "a corrupt file reseeds §8.6's whole set, not an empty picker")
    }

    /// **…and the bytes it could not read are still there afterwards.**
    ///
    /// The half above is what the store already did and it is not enough: reseeding leaves the shipped
    /// set in `groups`, and the artist's next edit persists *that* over `library.json`. The artist's
    /// tuning is then gone with a log line as its only trace, and no artist reads the log. §8.1 makes
    /// this file app-level and hand-made rather than a §2.14 expendable document, which is the whole
    /// argument in `BrushScatterSplit`.
    ///
    /// **The second assertion is the one a "it recovered" test misses.** That the picker came back
    /// full says nothing about whether anything survived; this reads the preserved file back through
    /// `BrushStorage` and compares it to the bytes that went in.
    func testAnUnreadableLibraryIsKeptUnderTheRootRatherThanDestroyed() throws {
        let original = Data("{ \"groups\": [ this is not json".utf8)
        try original.write(to: directory.appendingPathComponent(BrushLibraryStore.fileName))

        let store = makeStore()
        XCTAssertEqual(store.groups.map(\.name), BrushLibrary.groups.map(\.name),
                       "PREMISE: it still seeds, so the artist is not left with an empty picker")

        let storage = BrushStorage(root: directory)
        let kept = storage.fileNames().filter { $0.hasPrefix("library-unreadable-") }
        XCTAssertEqual(kept.count, 1, "exactly one copy of the file it could not read")
        XCTAssertEqual(storage.read(try XCTUnwrap(kept.first)), original,
                       "the bytes are recoverable, byte for byte — a person can open this file and a "
                       + "future session can migrate it")
        XCTAssertFalse(storage.contains(BrushLibraryStore.fileName),
                       "…and the unreadable file was *moved*, not copied: the seeded library is what "
                       + "gets persisted over that name next")
    }

    /// **A file the app cannot read grows one copy, not one per launch.**
    ///
    /// This is why the original is removed rather than left where it is. Leaving it means the next
    /// launch fails to decode it again and keeps a second dated sibling, and the launch after that a
    /// third — a directory that fills up for as long as the artist does not notice.
    func testAPreservedLibraryIsNotPreservedAgainOnEveryLaunch() throws {
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent(BrushLibraryStore.fileName))
        _ = makeStore()
        _ = makeStore()
        _ = makeStore()
        let kept = BrushStorage(root: directory).fileNames().filter { $0.hasPrefix("library-unreadable-") }
        XCTAssertEqual(kept.count, 1, "three launches, one copy — kept: \(kept)")
    }

    /// **Two unreadable libraries inside one second are two files.** The dated name is only accurate
    /// to the second, so without the uniquing suffix the second preserve writes the first one's name
    /// and the first artist's bytes are gone — which is precisely the destruction this whole path
    /// exists to prevent, reintroduced at the last step.
    ///
    /// The test above cannot reach this: it removes the original, so the second and third launches
    /// find nothing to preserve. Only a *fresh* unreadable file written between two launches gets
    /// there, and the two contents must differ or an overwrite would be undetectable.
    func testTwoUnreadableLibrariesInTheSameSecondAreBothKept() throws {
        let first = Data("{ first broken library".utf8)
        let second = Data("{ second broken library, different bytes".utf8)
        let path = directory.appendingPathComponent(BrushLibraryStore.fileName)

        try first.write(to: path)
        _ = makeStore()
        try second.write(to: path)
        _ = makeStore()

        let storage = BrushStorage(root: directory)
        let kept = storage.fileNames().filter { $0.hasPrefix("library-unreadable-") }.sorted()
        XCTAssertEqual(kept.count, 2, "two different unreadable files, two copies — kept: \(kept)")
        XCTAssertEqual(Set(kept.compactMap { storage.read($0) }), [first, second],
                       "…and both artists' bytes are recoverable, not just the later one's")
    }

    // MARK: - BRUSH.md §2.30 and §2.32 — the owner's own library opens

    /// **The library pulled off the owner's iPad loads, end to end, through the store.**
    ///
    /// This is the assertion that is false on `main`: the file was saved before §2.30, so a row names
    /// the isotropic `scatter` output that ruling deleted, `BrushOutput` throws on the string, the
    /// whole document fails and `loadGroups` hands back `BrushLibraryDocument.seeded`. The artist's
    /// entire library is replaced by the shipped set and the only trace is a log line.
    ///
    /// **Through `BrushLibraryStore` rather than through `JSONDecoder`**, because the destruction
    /// happens in the store's `catch` and a decode test cannot see it: a decoder test that threw
    /// would be red for the right reason, but a *store* that seeds is green while losing everything.
    /// The operand that tells them apart is the group and brush names — theirs, not §8.6's.
    func testTheOwnersOwnLibraryOpensRatherThanBeingReplacedByTheShippedSet() throws {
        let url = try XCTUnwrap(Bundle(for: BrushLibraryLogicTests.self)
            .url(forResource: "owner-tuned-library-2026-09-05", withExtension: "json"),
                                "fixture is not in the test bundle")
        try Data(contentsOf: url).write(to: directory.appendingPathComponent(BrushLibraryStore.fileName))

        let store = makeStore()
        XCTAssertEqual(store.groups.map(\.name), ["Basics", "Sketching", "Inking", "Painting", "Texture"])
        XCTAssertEqual(store.allBrushes.count, 16,
                       "their sixteen, not §8.6's twenty — their file predates the Texture group, and "
                       + "an empty Texture group is how you tell the two apart")
        XCTAssertTrue(store.groups.last?.brushes.isEmpty ?? false,
                      "Texture is empty in their file and full in the seeded set, so this is the "
                      + "assertion that cannot pass on a reseed")

        // And the brush they tuned came through both migrations rather than merely surviving decode.
        let theirs = try XCTUnwrap(store.allBrushes.first { $0.name == "Rough Ink" })
        XCTAssertEqual(theirs.tip, .stamp(.builtIn(.square)))
        XCTAssertGreaterThan(theirs.dab.scatterAcross, 0, "§2.30: the isotropic base reached an axis")
        XCTAssertEqual(theirs.dab.scatterAcross, theirs.dab.scatterAlong, accuracy: 1e-12)
        XCTAssertEqual(theirs.modulations.rows(for: .scatterAcross).count, 1)
        XCTAssertEqual(theirs.modulations.rows(for: .scatterAlong).count, 1)
        XCTAssertEqual(theirs.dab.density, BrushDensityGate.threshold, accuracy: 1e-12,
                       "§2.32: and the density base sits on the gate")
        XCTAssertEqual(theirs, BrushLibrary.roughInk,
                       "…which is §8.6's Rough Ink, because this pass extracted it from these bytes")
    }

    /// An imported brush a project restored, on a device whose library has never seen it, is taken in
    /// — and taken in only once, however many times that project is reopened.
    func testAdoptingRestoredBrushesIsAdditiveAndIdempotent() {
        let store = makeStore()
        let fromAnotherDevice = Brush(name: "Their Brush", tip: .stamp(.imported(fileName: "x.png")), size: 20)

        let seeded = store.groups.map(\.name)
        store.adopt([fromAnotherDevice], intoGroupNamed: "Imported")
        store.adopt([fromAnotherDevice], intoGroupNamed: "Imported")
        XCTAssertEqual(store.groups.map(\.name), seeded + ["Imported"])
        XCTAssertEqual(store.groups.last?.brushes.count, 1)

        // A brush the library already holds is not adopted a second time into a new group.
        store.adopt([BrushLibrary.brushPen], intoGroupNamed: "Imported")
        XCTAssertEqual(store.groups.last?.brushes.count, 1)
    }

    // MARK: - The row preview

    private static let previewSize = CGSize(width: 156, height: 26)

    private func nonTransparentPixelCount(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: bytes.count, by: 4).reduce(into: 0) { count, index in
            if bytes[index] > 0 { count += 1 }
        }
    }

    /// **The preview is of the brush** — BRUSH.md §7.1's whole reason for the row being a stroke
    /// rather than a name.
    ///
    /// The discriminating operand is that two brushes differing *only* in a setting that changes ink
    /// produce **different pictures**. An assertion that merely got an image back would pass against a
    /// renderer that ignored its argument entirely, which is CLAUDE.md's
    /// "a green assertion is only as good as its two operands" wearing this feature's clothes.
    func testTwoBrushesDifferingOnlyInHardnessPreviewDifferently() throws {
        let soft = Brush(name: "A", tip: .round, size: 14,
                         dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.05, hardness: 0.02))
        var hard = soft
        hard.dab.hardness = 1.0

        let a = BrushPreview.render(soft, size: Self.previewSize, scale: 2, color: .white)
        let b = BrushPreview.render(hard, size: Self.previewSize, scale: 2, color: .white)
        XCTAssertNotEqual(a.pngData(), b.pngData(),
                          "A preview that ignores the brush would make these identical")

        // And the difference is the brush rather than noise: the same brush renders the same picture.
        let again = BrushPreview.render(soft, size: Self.previewSize, scale: 2, color: .white)
        XCTAssertEqual(a.pngData(), again.pngData(),
                       "BRUSH.md §4's randomness is hashed, not streamed — one seed, one picture")
    }

    /// A preview is *ink*, not an empty box. Without this the test above could be satisfied by two
    /// different flavours of nothing.
    func testAPreviewActuallyStampsInk() {
        let image = BrushPreview.render(BrushLibrary.roundHard, size: Self.previewSize, scale: 2, color: .white)
        let painted = nonTransparentPixelCount(image)
        XCTAssertGreaterThan(painted, 200, "The row should carry a visible stroke, not a blank")
        XCTAssertLessThan(painted, Int(Self.previewSize.width * 2 * Self.previewSize.height * 2),
                          "…and not a solid block either")
    }

    /// A brush's own size reaches the preview, monotonically and inside the row.
    func testAFatterBrushPreviewsFatterAndStaysInsideTheRow() {
        let thin = Brush(name: "thin", tip: .round, size: 3,
                         dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.05, hardness: 1))
        var fat = thin
        fat.size = 60

        XCTAssertLessThan(BrushPreview.strokeWidth(for: thin, in: Self.previewSize),
                          BrushPreview.strokeWidth(for: fat, in: Self.previewSize))
        XCTAssertLessThanOrEqual(BrushPreview.strokeWidth(for: fat, in: Self.previewSize),
                                 Self.previewSize.height,
                                 "A 60 pt brush must not be one dab that covers the row")
        XCTAssertGreaterThan(nonTransparentPixelCount(BrushPreview.render(fat, size: Self.previewSize, scale: 2, color: .white)),
                             nonTransparentPixelCount(BrushPreview.render(thin, size: Self.previewSize, scale: 2, color: .white)))
    }

    /// **The cache is keyed on the brush's identity, not on the object** — §7.1's *"an edited brush
    /// re-renders and an unedited one never does"*.
    ///
    /// The second half is asserted by **counting renders**, not by comparing images: two identical
    /// pictures cannot tell a cache hit from a second identical render, so an image comparison would
    /// stay green against a cache that did nothing at all.
    func testAnEditedBrushRerendersAndAnUneditedOneDoesNot() {
        let cache = BrushPreviewCache()
        let brush = BrushLibrary.roundHard

        let first = cache.image(for: brush, size: Self.previewSize, scale: 2, color: .white)
        XCTAssertEqual(cache.renderCount, 1)

        _ = cache.image(for: brush, size: Self.previewSize, scale: 2, color: .white)
        _ = cache.image(for: brush, size: Self.previewSize, scale: 2, color: .white)
        XCTAssertEqual(cache.renderCount, 1, "An unedited brush must never re-render")

        // Same id, different value — which is what an edit is, and what `BrushPool` addresses by.
        var edited = brush
        edited.dab.hardness = 0.05
        XCTAssertEqual(edited.id, brush.id, "PREMISE: an edit keeps the brush's id")
        let second = cache.image(for: edited, size: Self.previewSize, scale: 2, color: .white)
        XCTAssertEqual(cache.renderCount, 2, "An edited brush must miss")
        XCTAssertNotEqual(first.pngData(), second.pngData(),
                          "…and the re-render must actually be a different picture")

        // A different size is a different entry: a row and a contact sheet are different pictures.
        _ = cache.image(for: brush, size: CGSize(width: 300, height: 60), scale: 2, color: .white)
        XCTAssertEqual(cache.renderCount, 3)
    }

    /// The cache probe never renders, which is what lets a SwiftUI row ask on the main thread before
    /// deciding to go off it.
    func testTheCacheProbeNeverRenders() {
        let cache = BrushPreviewCache()
        let key = BrushPreviewKey(brush: BrushLibrary.brushPen, size: Self.previewSize, scale: 2)
        XCTAssertNil(cache.cached(key))
        XCTAssertEqual(cache.renderCount, 0)

        _ = cache.image(for: BrushLibrary.brushPen, size: Self.previewSize, scale: 2, color: .white)
        XCTAssertNotNil(cache.cached(key))
        XCTAssertEqual(cache.renderCount, 1)
    }

    /// The preview stroke is a curve carrying a pressure ramp, not a flat bar — which is what makes a
    /// `size ← pressure` row visible as a shape. Asserted on the samples, because a brush with no
    /// pressure response would render the same either way and hide the mistake.
    func testThePreviewStrokeCarriesAPressureRampAndBendsBothWays() throws {
        let samples = BrushPreview.samples(in: Self.previewSize)
        XCTAssertGreaterThan(samples.count, 8)

        let pressures = (0..<samples.count).map { samples[$0].pressure }
        XCTAssertLessThan(try XCTUnwrap(pressures.first), 0.2, "It starts light")
        XCTAssertGreaterThan(try XCTUnwrap(pressures.max()), 0.9, "…presses…")
        XCTAssertLessThan(try XCTUnwrap(pressures.last), 0.2, "…and releases")

        let ys = samples.positions.map(\.y)
        let midY = Self.previewSize.height / 2
        XCTAssertTrue(ys.contains { $0 < midY - 1 } && ys.contains { $0 > midY + 1 },
                      "An S goes both sides of the middle; a straight line would go neither")
        XCTAssertTrue(samples.positions.allSatisfy { $0.x >= 0 && $0.x <= Self.previewSize.width },
                      "and it stays inside the row it is drawn into")
    }
    /// **Every shipped brush's density lands inside the control an artist edits it on** — BRUSH.md
    /// §2.32's stated reason for converting a dropout at *half* gain rather than at full.
    ///
    /// The gate `D ≥ u` survives any positive scale of the whole chain, so no assertion about the
    /// **ink** can see the difference — a mutation of `BrushDensityGate.halfAmount` passed every one
    /// of them. What the halves buy is reachability: at a whole amount Splatter's converted base is
    /// **1.2**, past the end of a `0…1` slider, so the one number the artist would reach for to tune
    /// their dropout could not be dragged to where it already was.
    func testEveryShippedDensityBaseAndGainSitsInsideItsOwnControl() {
        for brush in BrushLibrary.defaults {
            XCTAssertTrue(BrushOutput.density.editorRange.contains(brush.dab.density),
                          "\(brush.name): density base \(brush.dab.density) is outside "
                          + "\(BrushOutput.density.editorRange)")
            for row in brush.modulations.rows where row.output == .density {
                XCTAssertTrue((-1.0...1.0).contains(row.amount),
                              "\(brush.name): a density gain of \(row.amount) is off the slider")
            }
        }
        // PREMISE: four of the twenty actually use a dropout, so the loop above is not vacuous.
        let dropouts = BrushLibrary.defaults.filter { $0.modulations.drives(.density) }
        XCTAssertEqual(Set(dropouts.map(\.name)),
                       ["Rough Ink", "Rough Ink — Blotchy", "Splatter", "Stipple"],
                       "§2.32 converted four presets; this list is what a fifth would have to join")
    }

}
