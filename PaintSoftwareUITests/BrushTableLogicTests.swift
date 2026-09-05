import XCTest
import UIKit

/// **BRUSH.md §12 stage 6 — the document-level brush table.** §2.9, §2.10 and §5.4.
///
/// A stroke stopped storing a `Brush` by value and holds a `BrushRef` into `BrushPool`; a save writes
/// the entries this document's ink references, and only those, into `brushtable.json` beside
/// `brushes/`; a load redeems every stored number against that file.
///
/// **What is deliberately asserted here, given how many ways a fixture can measure nothing:**
///
///   * The *table* decides which brush a stroke resolves to, not this process's pool. That is the one
///     assertion an in-process round trip cannot make on its own — CLAUDE.md's own warning about the
///     `static let` that made an encode-then-decode pin `JSONDecoder`. Two tables that map the *same*
///     stored number to two *different* brushes give two different answers, which no pool-reading
///     implementation can do.
///   * The stored number this file's decoding tests use is one this process's pool **cannot** hold,
///     so the resolution under test provably did not come from ambient state.
///   * The ProjectStore round trip is re-run against a package whose numbers have been shifted out
///     from under it, which is exactly what a launch with a differently-populated pool sees.
///   * The population of the texture copy — BUGS.md's *"copied by the palette, not by what is drawn"*
///     — is pinned from the side that was broken: a tip **no palette entry names**.
@MainActor
final class BrushTableLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brush-table-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Fixtures

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A brush that differs from every other in this file by more than its name, so two of them
    /// stamp visibly different ink and an assertion about "which brush" cannot pass by coincidence.
    private func brush(_ name: String, size: CGFloat, hardness: Double = 0.8,
                       spacing: Double = 0.1) -> Brush {
        Brush(id: UUID(), name: name, tip: .round, size: size, dab: BrushDabSettings(spacing: spacing, hardness: hardness))
    }

    private func stroke(_ brush: Brush, from a: CGPoint, to b: CGPoint,
                        size: CGFloat = 6) -> VectorStroke {
        VectorStroke(id: UUID(), brush: brush, color: black(), size: size, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    /// A manager with a raster layer at 0 and an active vector layer at 1.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    private func loop(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ path: CGPath) {
        manager.selection = Selection(path: path, bounds: path.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    private func projectURL(name: String) -> URL { ProjectStore.createNewProjectURL(name: name) }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    private func pixels(_ image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        return CanvasFixture.rgbaBytes(cg)
    }

    /// **A render that is blank makes every "the pixels are unchanged" assertion in this file vacuous**
    /// — two empty canvases are equal whatever the code does. So every such comparison states first
    /// that there is ink to be unchanged.
    private func assertHasInk(_ bytes: [UInt8], _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let opaque = stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
        XCTAssertTrue(opaque, "\(what): the fixture drew nothing, so comparing it to anything measures nothing",
                      file: file, line: line)
    }

    /// This package's brush table as it is on disk.
    private func tableOnDisk(at url: URL) throws -> BrushTable {
        let manifest = try JSONDecoder().decode(
            ProjectManifest.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
        let fileName = try XCTUnwrap(manifest.brushTableFileName,
                                     "a document with vector ink names its brush table")
        return try JSONDecoder().decode(BrushTable.self,
                                        from: Data(contentsOf: url.appendingPathComponent(fileName)))
    }

    /// A `BrushTable` built out of JSON, the way a load builds one — the only door in the app that
    /// mints a `BrushRef` from a number, and therefore the only way a test can name one this process's
    /// pool does not hold.
    private func table(_ pairs: [(ref: UInt32, brush: Brush)]) throws -> BrushTable {
        let entries = try pairs.map { pair -> String in
            let brush = String(decoding: try JSONEncoder().encode(pair.brush), as: UTF8.self)
            return #"{"ref":\#(pair.ref),"brush":\#(brush)}"#
        }
        return try JSONDecoder().decode(BrushTable.self,
                                        from: Data(#"{"entries":[\#(entries.joined(separator: ","))]}"#.utf8))
    }

    /// A stroke's JSON with its brush number replaced by `ref` — a number this process's pool cannot
    /// hold, so what redeems it is provably the table and not ambient state.
    private func strokeJSON(_ stroke: VectorStroke, storedAs ref: UInt32) throws -> Data {
        let json = String(decoding: try JSONEncoder().encode(stroke), as: UTF8.self)
        let rewritten = json.replacingOccurrences(of: #""brush":[0-9]+"#,
                                                  with: #""brush":\#(ref)"#,
                                                  options: .regularExpression)
        XCTAssertNotEqual(rewritten, json, "the rewrite has to actually find the key it is about")
        return Data(rewritten.utf8)
    }

    private func decoder(_ table: BrushTable?) -> JSONDecoder {
        let decoder = JSONDecoder()
        if let table { decoder.userInfo[.brushTable] = table.resolvingIntoPool() }
        return decoder
    }

    /// A number no `BrushPool` this suite can produce will ever be a live index — the pool is dense
    /// and one process would have to intern sixty thousand distinct brushes to reach it.
    private static let storedRef: UInt32 = 60_000

    // MARK: - A ref is an index into a table, and which table is not ambient

    /// **The assertion the rest of this file rests on: the table decides.**
    ///
    /// One set of bytes, two tables that map the same stored number to two different brushes, two
    /// different answers. No implementation that reads the process pool — which is what an in-process
    /// encode-then-decode would silently be measuring — can produce two answers from one input, so if
    /// this went red the code would be resolving against the wrong thing.
    func testTheDocumentsTableDecidesWhichBrushAStrokeResolvesTo() throws {
        let fine = brush("Fine", size: 3, hardness: 0.95, spacing: 0.04)
        let broad = brush("Broad", size: 40, hardness: 0.1, spacing: 0.3)
        let bytes = try strokeJSON(stroke(fine, from: .zero, to: CGPoint(x: 20, y: 20)),
                                   storedAs: Self.storedRef)

        let asFine = try decoder(table([(Self.storedRef, fine)])).decode(VectorStroke.self, from: bytes)
        let asBroad = try decoder(table([(Self.storedRef, broad)])).decode(VectorStroke.self, from: bytes)

        XCTAssertEqual(asFine.brush, fine)
        XCTAssertEqual(asBroad.brush, broad)
        XCTAssertNotEqual(asFine.brushRef, asBroad.brushRef,
                          "two brushes are two entries — a table that collapsed them would draw one "
                          + "document's ink with another's brush")
    }

    /// A stored number with no table to redeem it is a corrupt payload, not an old one (§2.14): it
    /// throws rather than substituting a brush the artist never chose. This is the sentence that stops
    /// the ambient-pool path from being reachable for a file — `ProjectStore` sets the key on every
    /// decoder it points at a package, even when the table is empty.
    func testAStoredRefWithNoTableToRedeemItRefusesRatherThanGuessing() throws {
        let bytes = try strokeJSON(stroke(brush("Any", size: 8), from: .zero, to: CGPoint(x: 9, y: 9)),
                                   storedAs: Self.storedRef)
        XCTAssertThrowsError(try decoder(nil).decode(VectorStroke.self, from: bytes))
        // And with a table that simply does not carry it — the shape a half-written table would take.
        XCTAssertThrowsError(
            try decoder(table([(1, brush("Elsewhere", size: 8))])).decode(VectorStroke.self, from: bytes))
    }

    /// The in-memory case the absent key is *for*: an undo snapshot, a pasteboard, a defensive copy.
    /// A ref minted by this process resolves in this process with no table at all.
    func testARefThisProcessMintedResolvesWithNoTable() throws {
        let mine = brush("Mine", size: 11, hardness: 0.44)
        let bytes = try JSONEncoder().encode(stroke(mine, from: .zero, to: CGPoint(x: 5, y: 5)))
        XCTAssertEqual(try decoder(nil).decode(VectorStroke.self, from: bytes).brush, mine)
    }

    // MARK: - What a stroke costs (§5.4)

    /// **§5.4's saving, measured on the field it is about.** A `Brush` by value was 333 bytes on the
    /// wire for a stock preset and 386 for a custom-shaped one; what a stroke writes now is the key and
    /// a short decimal.
    ///
    /// The operand is the `"brush":…` substring of a real encode rather than the payload's total size,
    /// and that is the difference between an assertion and a gesture: a whole three-sample stroke is
    /// MEASURED at **254.4 bytes** marginal, so a threshold on the total would still pass with a
    /// hundred bytes of brush back inside it. This one cannot.
    func testTheBrushAStrokeWritesIsAReferenceRatherThanABrush() throws {
        let shared = brush("A brush with a name long enough to be visible in a byte count", size: 9)
        let json = String(decoding: try JSONEncoder().encode(
            stroke(shared, from: .zero, to: CGPoint(x: 30, y: 30))), as: UTF8.self)
        let field = try XCTUnwrap(json.range(of: #""brush":[^,}]*"#, options: .regularExpression),
                                  "a stroke writes a brush key")
        XCTAssertLessThanOrEqual(json[field].count, 16,
                                 "\(json[field]) — a reference is the key plus a short decimal, 9 to 13 "
                                 + "bytes; 333–386 was the brush by value (BRUSH.md §5.4)")
        XCTAssertNotNil(UInt32(json[field].dropFirst(#""brush":"#.count)),
                        "and it is a bare number, not an object wearing a wrapper")
    }

    /// The marginal cost of one more stroke that shares a brush — the number §5.4 is really about,
    /// since a cel shaped like real artwork holds ~190 strokes and a handful of brushes. MEASURED at
    /// 254.4 bytes for a three-sample stroke; the threshold sits below 254 + 333, so a regression to a
    /// by-value brush fails it whichever preset is used.
    func testAnExtraStrokeSharingABrushDoesNotCarryTheBrushAgain() throws {
        let shared = brush("Shared", size: 9)
        func payloadBytes(strokes: Int) throws -> Int {
            let canvas = VectorCanvas.empty(size: CanvasFixture.canvasSize)
            for index in 0..<strokes {
                canvas.addStroke(stroke(shared, from: CGPoint(x: 2, y: index % 60),
                                        to: CGPoint(x: 40, y: index % 60)))
            }
            return try JSONEncoder().encode(VectorCanvasData(from: canvas, imageFileNames: [:])).count
        }
        let marginal = Double(try payloadBytes(strokes: 51) - (try payloadBytes(strokes: 1))) / 50
        XCTAssertLessThan(marginal, 300,
                          "a whole extra stroke costs \(marginal) bytes against a MEASURED 254.4")
    }

    /// And the table it shares is one entry, however many strokes name it — the deduplication §2.9
    /// asks for, asserted where it is visible rather than inferred from the byte count above.
    func testManyStrokesOfOneBrushAreOneTableEntry() throws {
        let (manager, _, vector) = fixture()
        let one = brush("One", size: 5)
        for index in 0..<20 {
            vector.addStroke(stroke(one, from: CGPoint(x: 2, y: index * 3), to: CGPoint(x: 40, y: index * 3)))
        }
        let url = projectURL(name: "Dedup")
        saveAndWait(manager, to: url)
        XCTAssertEqual(try tableOnDisk(at: url).count, 1)
    }

    // MARK: - The sweep (§5.4)

    /// **The sweep, from the side that matters: an entry nothing references is never written.**
    ///
    /// The pool holds `unused` — it was interned by being drawn into a stroke that was then removed,
    /// which is exactly what §2.10's minting produces in bulk — and the saved table does not.
    ///
    /// It also covers the recipe population, which is the one a cel walk alone would miss: a derived
    /// cel's `LocalEdit` strokes are reachable from no display list, so a table built from cels only
    /// would omit their brush and that recipe would fail to decode on the next load.
    func testTheSavedTableHoldsExactlyTheBrushesTheDocumentReferences() throws {
        let (manager, layerIndex, vector) = fixture()
        let drawn = brush("Drawn", size: 7)
        let unused = brush("Unused", size: 31, hardness: 0.05)
        let inARecipe = brush("Recipe", size: 13, spacing: 0.4)

        vector.addStroke(stroke(drawn, from: CGPoint(x: 4, y: 8), to: CGPoint(x: 50, y: 8)))
        // Interned and then thrown away — a brush the pool holds and the document does not use.
        let discarded = stroke(unused, from: .zero, to: CGPoint(x: 1, y: 1))
        XCTAssertEqual(discarded.brush, unused, "setup: the discarded stroke did intern its brush")

        // A recipe whose local edit uses a third brush — reachable from no display list, so a
        // collector that walked only cel elements would leave it out and that recipe would fail to
        // decode on the next load.
        var recipe = InterpolationRecipe(references: [], t: 0.5)
        recipe.localEdits = [LocalEdit(stroke: stroke(inARecipe, from: .zero, to: CGPoint(x: 20, y: 3)))]
        manager.layers[layerIndex].cels[0].interpolation = recipe

        let url = projectURL(name: "Sweep")
        saveAndWait(manager, to: url)

        let written = Set(try tableOnDisk(at: url).brushes)
        XCTAssertTrue(written.contains(drawn), "a brush the ink is made of is written")
        XCTAssertTrue(written.contains(inARecipe),
                      "a recipe's local edit is ink too, and nothing else references its brush")
        XCTAssertFalse(written.contains(unused),
                       "the sweep: a pool entry no element names is never collected, so a heavily "
                       + "tuned document does not accumulate dead brushes forever (§5.4)")
    }

    // MARK: - The round trip, including a table whose numbers this process cannot redeem

    /// Save, reopen, render, compare — and then do it again against a package whose numbers have been
    /// **shifted out from under it**, which is what a launch whose pool was populated differently
    /// sees. Without the shift this test would pass against an implementation that ignored the remap
    /// entirely, because in the launch that wrote the file the remap is the identity.
    func testAReopenedDocumentRendersIdenticallyEvenWhenItsStoredNumbersAreNotThisProcessesOwn() throws {
        let (manager, _, vector) = fixture()
        let a = brush("Ink A", size: 5, hardness: 0.95, spacing: 0.05)
        let b = brush("Ink B", size: 22, hardness: 0.05, spacing: 0.25)
        vector.addStroke(stroke(a, from: CGPoint(x: 6, y: 16), to: CGPoint(x: 56, y: 16)))
        vector.addStroke(stroke(b, from: CGPoint(x: 6, y: 44), to: CGPoint(x: 56, y: 44), size: 14))
        let expected = try XCTUnwrap(pixels(vector.render()))
        assertHasInk(expected, "two strokes on a 64x64 canvas")

        let url = projectURL(name: "Round Trip")
        saveAndWait(manager, to: url)

        func renderOfReopened(_ url: URL) throws -> [UInt8] {
            let reopened = try XCTUnwrap(ProjectStore.load(from: url))
            let canvas = try XCTUnwrap(reopened.layers.compactMap { $0.cels.first?.vector }
                                                     .first { !$0.strokes.isEmpty })
            XCTAssertEqual(canvas.strokes.count, 2, "both strokes came back")
            return try XCTUnwrap(pixels(canvas.render()))
        }

        XCTAssertEqual(try renderOfReopened(url), expected, "the ink is unchanged by a save and reopen")

        try shiftStoredBrushNumbers(at: url, by: 50_000)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "the shift rewrites numbers, not the package's shape")
        XCTAssertEqual(try renderOfReopened(url), expected,
                       "a document whose stored numbers this process's pool cannot hold still draws "
                       + "the ink it was saved with — the table is what redeems them")
    }

    /// The same round trip on a document whose table **has been swept**: a brush is used, then every
    /// stroke is re-pointed away from it, and the second save drops it. The ink after that save has to
    /// be the ink before it.
    func testADocumentWhoseTableWasSweptReopensUnchanged() throws {
        let (manager, layerIndex, vector) = fixture()
        let old = brush("Old", size: 9, hardness: 0.9)
        let new = brush("New", size: 9, hardness: 0.1, spacing: 0.3)
        vector.addStroke(stroke(old, from: CGPoint(x: 8, y: 30), to: CGPoint(x: 54, y: 30), size: 10))

        let url = projectURL(name: "Swept")
        saveAndWait(manager, to: url)
        XCTAssertEqual(Set(try tableOnDisk(at: url).brushes), [old], "before: the table names Old")

        manager.selectBrush(new)
        // Stated rather than inherited: the default is Cut, and a Cut that catches everything is a
        // split of nothing — true today and not what this test is about.
        manager.selectionMembership = .touching
        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 60)))
        manager.applyBrushToSelection()
        let expected = try XCTUnwrap(pixels(vector.render()))
        assertHasInk(expected, "the re-pointed stroke")

        saveAndWait(manager, to: url)
        XCTAssertEqual(Set(try tableOnDisk(at: url).brushes), [new],
                       "after: Old is referenced by nothing and is swept out")

        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        let canvas = try XCTUnwrap(reopened.layers.compactMap { $0.cels.first?.vector }
                                                 .first { !$0.strokes.isEmpty })
        XCTAssertEqual(try XCTUnwrap(pixels(canvas.render())), expected,
                       "a swept document's ink is the ink it had — the sweep drops entries, it never "
                       + "renumbers the strokes that survive")
    }

    /// Rewrites every stored brush number in a package — the table's `ref` keys and each stroke's
    /// `brush` value — by a constant. The two keys are different words, so one regex each cannot
    /// touch the other's file, and `manifest.json` is left alone because the palette it carries is
    /// brushes by value (§8.1) rather than references.
    private func shiftStoredBrushNumbers(at url: URL, by delta: UInt32) throws {
        func rewrite(_ fileURL: URL, key: String) throws {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            let pattern = try NSRegularExpression(pattern: "\"\(key)\":([0-9]+)")
            let range = NSRange(text.startIndex..., in: text)
            var shifted = 0
            var out = ""
            var cursor = text.startIndex
            for match in pattern.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text),
                      let digits = Range(match.range(at: 1), in: text),
                      let value = UInt32(text[digits]) else { continue }
                out += text[cursor..<whole.lowerBound] + "\"\(key)\":\(value + delta)"
                cursor = whole.upperBound
                shifted += 1
            }
            out += text[cursor...]
            XCTAssertGreaterThan(shifted, 0, "\(fileURL.lastPathComponent) had a \(key) to shift")
            try out.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let manifest = try JSONDecoder().decode(
            ProjectManifest.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
        try rewrite(url.appendingPathComponent(try XCTUnwrap(manifest.brushTableFileName)), key: "ref")
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: imagesDir.path)
        where name.hasSuffix(".json") {
            let fileURL = imagesDir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
                  text.contains("\"brush\":") else { continue }
            try rewrite(fileURL, key: "brush")
        }
    }

    // MARK: - The texture population (BUGS.md)

    /// **The half of `ProjectStore`'s texture copy that was missing.** Its doc comment claimed to make
    /// a saved project self-contained and walked `[selectedBrush] + customBrushes` — the picker list.
    /// This draws with an imported tip and then takes it *out* of the palette, which is the state
    /// §2.10's minting produces routinely, and asserts the file still travels.
    ///
    /// The existing pin, `ProjectSaveLogicTests.testSavingCopiesAnImportedTipIntoThePackageAndLeavesTheBuiltInsAlone`,
    /// says in its own comment that the population was out of its scope. This is that scope.
    func testAnImportedTipTheInkUsesTravelsEvenWhenNoPaletteEntryNamesIt() throws {
        let (manager, _, vector) = fixture()
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let stamp = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(CGRect(x: 8, y: 0, width: 16, height: 32))
        }
        let imported = try manager.importCustomBrush(from: stamp)
        let fileName = try XCTUnwrap(imported.tip.importedTextureFileName)

        vector.addStroke(stroke(imported, from: CGPoint(x: 8, y: 32), to: CGPoint(x: 54, y: 32), size: 12))

        // The palette forgets it — a rename, a future removal, or simply the artist editing on to the
        // next brush. The ink has not forgotten it.
        manager.customBrushes = []
        manager.selectBrush(TestBrushes.hardRound)
        XCTAssertFalse(([manager.selectedBrush] + manager.customBrushes)
                        .contains { $0.tip.importedTextureFileName == fileName },
                       "fixture precondition: no palette entry names this file any more")

        let url = projectURL(name: "Drawn Tip")
        saveAndWait(manager, to: url)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("brushes").appendingPathComponent(fileName).path),
            "the tip the document's ink is made of has to travel with it — with this file missing, "
            + "the document opens on another device with strokes drawn by a brush that draws nothing")
    }

    /// And the other half of the union: a custom brush the artist imported but has **not** drawn with
    /// is in no stroke's table, is in the palette `manifest.json` persists, and still has to travel or
    /// the picker comes back pointing at a file that is not there. Neither population subsumes the
    /// other, which is why the copy takes both.
    func testAPaletteTipNobodyHasDrawnWithStillTravels() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let stamp = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        }
        let imported = try manager.importCustomBrush(from: stamp)
        let fileName = try XCTUnwrap(imported.tip.importedTextureFileName)

        let url = projectURL(name: "Palette Only Tip")
        saveAndWait(manager, to: url)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("brushes").appendingPathComponent(fileName).path))
    }

    // MARK: - §2.10 — an edit does not move ink already drawn, and a verb that does

    /// **§2.10's first half.** Editing the brush the artist is holding mints a new entry; the stroke
    /// already on the canvas keeps the one it was drawn with, and its pixels do not move.
    ///
    /// The pixel operand is the point: a test that compared only the stored ref would pass against an
    /// implementation that mutated the pool entry in place, which is the one thing that could make a
    /// live edit reach ink retrospectively.
    func testEditingABrushDoesNotChangeAStrokeAlreadyDrawnWithIt() throws {
        let (manager, _, vector) = fixture()
        let asDrawn = brush("As Drawn", size: 8, hardness: 0.95, spacing: 0.05)
        manager.selectBrush(asDrawn)
        vector.addStroke(stroke(asDrawn, from: CGPoint(x: 8, y: 32), to: CGPoint(x: 54, y: 32), size: 12))
        let before = try XCTUnwrap(pixels(vector.render()))
        assertHasInk(before, "the stroke drawn before the edit")
        let drawnRef = try XCTUnwrap(vector.strokes.first).brushRef

        // The same brush, edited — same `id`, a different value.
        var edited = asDrawn
        edited.dab.hardness = 0.05
        edited.dab.spacing = 0.4
        manager.selectBrush(edited)

        XCTAssertEqual(try XCTUnwrap(vector.strokes.first).brushRef, drawnRef,
                       "the stroke keeps the entry it was drawn with")
        XCTAssertEqual(try XCTUnwrap(vector.strokes.first).brush, asDrawn,
                       "and that entry still holds the brush as it was — a pool entry is never mutated")
        XCTAssertEqual(try XCTUnwrap(pixels(vector.render())), before,
                       "so no pixel of the ink already on the canvas moves")
    }

    /// **§2.10's second half — the explicit verb, and it is one undo step.** Two strokes, both caught,
    /// both re-pointed, and one press of undo puts both back.
    func testApplyingABrushToASelectionIsOneUndoStepThatCoversEveryStrokeItTouched() throws {
        let (manager, layerIndex, vector) = fixture()
        let drawn = brush("Drawn", size: 8, hardness: 0.95, spacing: 0.05)
        let picked = brush("Picked", size: 8, hardness: 0.05, spacing: 0.35)
        vector.addStroke(stroke(drawn, from: CGPoint(x: 8, y: 20), to: CGPoint(x: 54, y: 20), size: 11))
        vector.addStroke(stroke(drawn, from: CGPoint(x: 8, y: 44), to: CGPoint(x: 54, y: 44), size: 11))
        let before = try XCTUnwrap(pixels(vector.render()))

        manager.selectBrush(picked)
        manager.selectionMembership = .touching
        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 60)))
        let baseline = manager.history.undoStack.count
        manager.applyBrushToSelection()

        XCTAssertEqual(manager.history.undoStack.count - baseline, 1,
                       "one verb, one step — however many strokes it touched")
        XCTAssertEqual(vector.strokes.map(\.brush), [picked, picked])
        let after = try XCTUnwrap(pixels(vector.render()))
        XCTAssertNotEqual(after, before, "and it is visible: a soft wide-spaced tip is not a hard one")

        manager.undo()
        XCTAssertEqual(vector.strokes.map(\.brush), [drawn, drawn],
                       "one press puts both back — not one press per stroke")
        XCTAssertEqual(try XCTUnwrap(pixels(vector.render())), before,
                       "and the pixels come back with them, which the version bump is what buys")
    }

    /// It re-points **what the loop caught and nothing else**, under the membership rule the Select
    /// panel owns (LASSO_MOVE.md §5.26). A stroke outside the loop keeps its brush.
    func testApplyingABrushLeavesInkTheLoopDidNotCatchAlone() throws {
        let (manager, layerIndex, vector) = fixture()
        let drawn = brush("Drawn", size: 8)
        let picked = brush("Picked", size: 8, hardness: 0.1)
        vector.addStroke(stroke(drawn, from: CGPoint(x: 4, y: 10), to: CGPoint(x: 26, y: 10)))
        vector.addStroke(stroke(drawn, from: CGPoint(x: 4, y: 56), to: CGPoint(x: 26, y: 56)))

        manager.selectBrush(picked)
        manager.selectionMembership = .enclosed
        select(manager, layerIndex, loop(CGRect(x: 0, y: 0, width: 40, height: 24)))
        manager.applyBrushToSelection()

        XCTAssertEqual(vector.strokes.map(\.brush), [picked, drawn],
                       "the loop caught the top stroke only")
    }

    /// A verb the artist can reach from a cold start, and one that costs nothing when there is nothing
    /// to do. Both directions of §2.10's *"as one undo step"*: a selection full of strokes already
    /// drawn with the picked brush is not an undo press.
    func testApplyingTheBrushStrokesAlreadyCarryRecordsNothing() throws {
        let (manager, layerIndex, vector) = fixture()
        let only = brush("Only", size: 8)
        vector.addStroke(stroke(only, from: CGPoint(x: 8, y: 30), to: CGPoint(x: 54, y: 30)))
        manager.selectBrush(only)
        manager.selectionMembership = .touching
        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 60)))

        let baseline = manager.history.undoStack.count
        manager.applyBrushToSelection()
        XCTAssertEqual(manager.history.undoStack.count - baseline, 0,
                       "an edit the artist cannot see must not cost them an undo press")
    }

    /// **Cold start, and it is the reachability question rather than the model one** — CLAUDE.md's
    /// *"a feature whose only entry point requires state that only that entry point can create"*. From
    /// a brand-new document: draw, pick a different brush, lasso, apply. Nothing here constructs a
    /// post-state by hand, and the refusal reason is nil at the moment the artist would press the
    /// button, which is what the panel gates on.
    func testTheVerbIsReachableFromANewDocument() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)

        manager.selectBrush(TestBrushes.hardRound)
        vector.addStroke(stroke(manager.selectedBrush,
                                from: CGPoint(x: 8, y: 30), to: CGPoint(x: 54, y: 30), size: 10))
        manager.selectBrush(TestBrushes.softRound)
        manager.selectionMembership = .touching
        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 60)))

        XCTAssertNil(manager.applyBrushUnavailableReason,
                     "the button the artist can see is live on the state they can reach")
        manager.applyBrushToSelection()
        XCTAssertEqual(vector.strokes.first?.brush, TestBrushes.softRound)
    }

    /// A raster layer says why rather than going quietly grey, exactly as Recolour does — and the
    /// action itself is a no-op, so a disabled control that is somehow pressed cannot write anything.
    func testApplyBrushRefusesAPixelLayerWithAReason() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentLayerIndex = 0
        select(manager, 0, loop(CGRect(x: 8, y: 8, width: 40, height: 40)))
        let reason = manager.applyBrushUnavailableReason
        XCTAssertNotNil(reason)
        XCTAssertFalse(reason?.isEmpty ?? true)
        let baseline = manager.history.undoStack.count
        manager.applyBrushToSelection()
        XCTAssertEqual(manager.history.undoStack.count - baseline, 0)
    }
}
