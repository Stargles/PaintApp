import XCTest
import UIKit

/// **Where a project's files live, and that moving them loses nothing** — TODO (57) part 1.
///
/// The owner, 2026-09-08, browsing their own iPad: *"There is a json file for the layers im guessing
/// that contains the strokes. Why is this file under the images folder?"* So the per-cel JSON now
/// lives in `drawings/`, and every package written before that keeps working — which is the half that
/// needs pinning, because the failure mode is silent. A reader that cannot find a moved sidecar does
/// not throw; it falls through `decodeCel`'s `?? .empty` and the artist's ink is simply gone.
///
/// The suite is built around three questions:
///
///  1. **The new layout is actually on disk** — the drawing is under `drawings/` and there is no JSON
///     under `images/`, asserted against the bytes rather than against the model.
///  2. **The old layout still opens, with its ink** — a package mechanically reverted to the
///     pre-(57) shape loads with the *sample coordinates the artist drew*, not merely a non-nil
///     canvas. A vector layer always gets an empty `VectorCanvas` when its payload cannot be read
///     (`decodeCel`'s `if vector == nil, layerKind == .vector` arm), so `XCTAssertNotNil` here would
///     be green against total data loss.
///  3. **The migration is crash-safe at every step boundary** — each row of `tidy`'s own resume table
///     is left on disk deliberately and then both re-loaded and re-run, because "it is idempotent" is
///     a claim about the second run and nothing but a second run tests it.
///  4. **No empty folder is left standing, by either route** — part 3's sweep. The writer's laziness
///     does not cover the migration (which empties `images/` by moving its contents out) and does not
///     cover its own failures (a role created from the snapshot that the write then could not fill),
///     so both are driven, and both directions of `rmdir`'s refusal are asserted: a directory that
///     still holds a byte keeps it *and* keeps the byte.
///
/// `Services/ProjectPackageLayout.swift`, `ProjectStore.swift` and `ProjectBackupManager.swift` are
/// compiled directly into this bundle (see `BackupManagerLogicTests`' header for why
/// `@testable import` cannot be used), so every function below is the shipped one.
@MainActor
final class ProjectPackageLayoutLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-layout-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        // TODO (57) part 2's registry is process-wide and has no `noteClosed`, so an earlier
        // suite's saves would otherwise leave packages registered and make the launch-pass
        // tests below decline work for a reason that has nothing to do with them.
        PackageRenameGate.resetForTesting()
    }

    override func tearDownWithError() throws {
        PackageRenameGate.resetForTesting()
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Fixtures

    /// The two sample coordinates the fixture stroke is drawn through. Named so the assertion that
    /// the ink survived a migration is about *these two points* rather than about a count.
    private static let inkStart = CGPoint(x: 12, y: 34)
    private static let inkEnd = CGPoint(x: 56, y: 78)

    /// A document with one vector cel carrying a real stroke and a real pose channel, so a save
    /// writes both a `drawing` and an `animation` sidecar.
    private func makeManager() -> CanvasManager {
        let manager = CanvasManager()
        manager.projectName = "Layout"
        manager.addVectorLayer(name: "Ink")
        let vectorLayer = manager.layers.count - 1
        let canvas = manager.layers[vectorLayer].cels[0].vector
        XCTAssertNotNil(canvas, "Setup: a vector layer's first cel should carry a VectorCanvas")
        canvas?.addStroke(VectorStroke(
            brush: manager.toolProfiles.brush.preset,
            color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: 8, opacity: 1,
            samples: [VectorSample(x: Self.inkStart.x, y: Self.inkStart.y, pressure: 1),
                      VectorSample(x: Self.inkEnd.x, y: Self.inkEnd.y, pressure: 1)]))
        // A pose channel, so the `animation` sidecar is written too — KEYFRAMES.md §3.5. Two keys,
        // because one key is not a channel anybody would author.
        let box = CGRect(x: 0, y: 0, width: 64, height: 64)
        manager.layers[vectorLayer].cels[0].transformTracks["cel"] = CanvasFixture.poseTrack(box: box, [
            (0, PoseQuad(restingIn: box)),
            (8, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 20, y: 0)))], interpolation: .linear)
        return manager
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL,
                             file: StaticString = #filePath, line: UInt = #line) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { _ in finished.fulfill() }
        wait(for: [finished], timeout: 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Setup: the save should have landed a package at \(url.lastPathComponent)",
                      file: file, line: line)
    }

    /// A saved package, in this build's layout.
    private func savedProject(named name: String = "Layout") -> URL {
        let url = ProjectStore.createNewProjectURL(name: name)
        saveAndWait(makeManager(), to: url)
        return url
    }

    private func manifestJSON(at url: URL,
                              file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            XCTFail("the package at \(url.lastPathComponent) should carry a readable manifest.json",
                    file: file, line: line)
            return [:]
        }
        return json
    }

    /// Every cel entry in a package's manifest, flattened across layers — the JSON as it is on disk,
    /// which is the only way to assert what a *name* says rather than what the decoder makes of it.
    private func celEntries(at url: URL,
                            file: StaticString = #filePath, line: UInt = #line) -> [[String: Any]] {
        guard let layers = manifestJSON(at: url, file: file, line: line)["layers"] as? [[String: Any]] else {
            XCTFail("the manifest at \(url.lastPathComponent) should carry a layers array",
                    file: file, line: line)
            return []
        }
        return layers.flatMap { ($0["cels"] as? [[String: Any]]) ?? [] }
    }

    private func names(in directory: String, at url: URL) -> [String] {
        let dir = url.appendingPathComponent(directory, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    /// The three manifest keys the migration moves, paired with the role that owns each. One list so
    /// every fixture and assertion below walks the same three and none of them can quietly walk two.
    private static let movedFields: [(key: String, role: ProjectPackageLayout.Role)] = [
        ("vectorFileName", .drawing), ("animationFileName", .animation),
        ("interpolationFileName", .interpolation)
    ]

    /// **Turns a package this build wrote into one an older build would have written**: every JSON
    /// sidecar back under `images/` at its `_vector` / `_anim` / `_interp` name, the manifest naming
    /// it bare, and no `drawings/` directory at all.
    ///
    /// The `makeLegacyRasterPNGs` pattern from `ProjectSaveLogicTests`, and for its reason: starting
    /// from a real save and mechanically reverting it is how the fixture stays a *package this app
    /// once produced*, where hand-authoring old JSON would drift from it silently.
    @discardableResult
    private func makeLegacyLayout(at url: URL,
                                  file: StaticString = #filePath, line: UInt = #line) -> Int {
        let fm = FileManager.default
        var json = manifestJSON(at: url, file: file, line: line)
        guard var layers = json["layers"] as? [[String: Any]] else {
            XCTFail("fixture: the saved manifest should carry a layers array", file: file, line: line)
            return 0
        }
        let images = url.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: images, withIntermediateDirectories: true)
        var moved = 0
        for layerIndex in layers.indices {
            var cels = (layers[layerIndex]["cels"] as? [[String: Any]]) ?? []
            for celIndex in cels.indices {
                guard let idString = cels[celIndex]["id"] as? String,
                      let celID = UUID(uuidString: idString) else {
                    XCTFail("fixture: every saved cel entry should carry an id", file: file, line: line)
                    continue
                }
                for (key, role) in Self.movedFields {
                    guard let recorded = cels[celIndex][key] as? String, recorded.contains("/") else { continue }
                    let legacy = ProjectPackageLayout.legacyName(for: role, cel: celID)
                    do {
                        let source = try ProjectPackageLayout.resolve(recorded, in: url)
                        try fm.moveItem(at: source, to: images.appendingPathComponent(legacy))
                    } catch {
                        XCTFail("fixture: \(recorded) should move back to images/\(legacy): \(error)",
                                file: file, line: line)
                        continue
                    }
                    cels[celIndex][key] = legacy
                    moved += 1
                }
            }
            layers[layerIndex]["cels"] = cels
        }
        json["layers"] = layers
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            XCTFail("fixture: the legacy manifest should re-encode", file: file, line: line)
            return moved
        }
        try? rewritten.write(to: url.appendingPathComponent("manifest.json"))
        try? fm.removeItem(at: url.appendingPathComponent(ProjectPackageLayout.Role.drawing.directory,
                                                          isDirectory: true))
        XCTAssertGreaterThan(moved, 0,
                             "fixture: the saved package should have had sidecars to push back under images/",
                             file: file, line: line)
        return moved
    }

    /// The ink, read back out of a loaded document — the two sample points the fixture drew.
    ///
    /// **Sample coordinates, not "a canvas exists".** A `.vector` layer whose payload could not be
    /// read still comes back with an empty `VectorCanvas`, so nil-checking the canvas is green
    /// against total loss of the drawing; and TODO (8) stores samples quantised, so the comparison is
    /// to within half a quantum rather than exact.
    private func assertInkSurvived(at url: URL, _ context: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("\(context): the package should load at all", file: file, line: line)
        }
        let canvases = reloaded.layers.compactMap { $0.cels.first?.vector }
        guard let canvas = canvases.first(where: { !$0.strokes.isEmpty }) else {
            return XCTFail("\(context): some vector cel should still carry the stroke the fixture drew "
                           + "— an empty VectorCanvas is what an unreadable payload also produces",
                           file: file, line: line)
        }
        guard let stroke = canvas.strokes.first, stroke.samples.count == 2 else {
            return XCTFail("\(context): the surviving stroke should still have both of its samples",
                           file: file, line: line)
        }
        let quantum = PackedSampleRun.quantum / 2
        XCTAssertEqual(stroke.samples[0].x, Self.inkStart.x, accuracy: quantum,
                       "\(context): the stroke's first sample x is where the artist put it", file: file, line: line)
        XCTAssertEqual(stroke.samples[0].y, Self.inkStart.y, accuracy: quantum,
                       "\(context): the stroke's first sample y is where the artist put it", file: file, line: line)
        XCTAssertEqual(stroke.samples[1].x, Self.inkEnd.x, accuracy: quantum,
                       "\(context): the stroke's last sample x is where the artist put it", file: file, line: line)
        XCTAssertEqual(stroke.samples[1].y, Self.inkEnd.y, accuracy: quantum,
                       "\(context): the stroke's last sample y is where the artist put it", file: file, line: line)

        // The pose channel is the other half of what a lost sidecar costs, and it is the half nothing
        // else in the suite would notice: `decodeCel`'s animation branch has no else arm, so a miss
        // leaves an empty map with no log line at all.
        let tracks = reloaded.layers.compactMap { $0.cels.first }.flatMap { $0.transformTracks.values }
        XCTAssertEqual(tracks.first?.keyedFrames.count, 2,
                       "\(context): the cel's pose channel should still carry both of its keys — a "
                       + "missing animation sidecar loads as an empty map and says nothing",
                       file: file, line: line)
    }

    // MARK: - (a) A fresh save puts the JSON where the owner asked for it

    func testAFreshSaveWritesTheDrawingUnderDrawingsAndNoJSONUnderImages() throws {
        let url = savedProject()

        let drawings = names(in: ProjectPackageLayout.Role.drawing.directory, at: url)
        // Matched against the cel's own id rather than by "has no dash" — a UUID is four dashes long,
        // which is exactly the kind of near-miss that makes a filename filter quietly wrong.
        let celID = try XCTUnwrap(celEntries(at: url).compactMap { $0["id"] as? String }.first,
                                  "the saved manifest should name a cel")
        XCTAssertTrue(drawings.contains("\(celID).json"),
                      "drawings/ holds the cel's drawing as <celID>.json, got \(drawings)")
        XCTAssertTrue(drawings.contains("\(celID)-animation.json"),
                      "drawings/ holds the cel's pose channels as <celID>-animation.json, got \(drawings)")

        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                       "no JSON is left under images/ — that is the owner's complaint, stated as an "
                       + "assertion about the bytes on disk")
    }

    /// And the manifest records the new address, which is the whole of the format version: a `/` in a
    /// field that already existed, rather than a new key or a number.
    func testTheManifestRecordsTheSidecarAsAPackageRelativePath() throws {
        let url = savedProject()
        let cels = celEntries(at: url)
        let drawing = try XCTUnwrap(cels.compactMap { $0["vectorFileName"] as? String }.first,
                                    "the saved manifest should name a vector payload")
        XCTAssertTrue(drawing.hasPrefix("drawings/"),
                      "the manifest records the drawing package-relative, got \(drawing)")
        let celID = try XCTUnwrap(cels.compactMap { $0["id"] as? String }.first)
        XCTAssertTrue(drawing.hasSuffix("\(celID).json") || drawing.contains(celID),
                      "the recorded name is still derived from the cel id, got \(drawing)")
        // Every PNG name is untouched by (57) — that is a decision, not an accident, so it is pinned.
        for cel in cels {
            let raster = try XCTUnwrap(cel["rasterFileName"] as? String)
            XCTAssertFalse(raster.contains("/"),
                           "PNG names stay bare — only the three JSON roles carry a path, got \(raster)")
        }
    }

    /// **The lazy-directory half of the sweep.** A pure-vector document — the owner's own — used to
    /// ship an empty `images/` beside its content, which is the next question they would have asked.
    func testAVectorOnlyDocumentWritesNoImagesDirectoryAtAll() {
        let url = savedProject()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("images", isDirectory: true).path),
            "nothing in this document is a pixel, so it gets no images/ — the fixture draws only "
            + "vector ink and never touches a raster tier")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "and it does get the one directory it has content for")
    }

    /// The other direction, so the test above cannot pass by creating no directories at all.
    func testARasterDocumentStillGetsItsImagesDirectory() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let raster = manager.layers[0].cels[0].raster
        raster.beginStroke()
        raster.stampCircle(at: CGPoint(x: 20, y: 20), radius: 6, color: .red, alpha: 1, hardness: 1)
        raster.endStroke()
        let url = ProjectStore.createNewProjectURL(name: "Raster")
        saveAndWait(manager, to: url)

        XCTAssertTrue(names(in: "images", at: url).contains { $0.hasSuffix("_raster.png") },
                      "a drawn raster tier writes its PNG into images/, got \(names(in: "images", at: url))")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "and a raster-only document gets no drawings/ — every content directory is lazy")
    }

    // The writer supplies both valid packages. Only A's one required resource address is then
    // changed; A's own PNG stays present so this is containment, not missing-file recovery.
    private func siblingRasterEscape() throws -> (a: URL, b: URL, bFiles: [String: Data]) {
        let size = CanvasFixture.canvasSize
        var packages: [URL] = []
        var rasterNames: [String] = []
        for (name, color, expected) in [("A", UIColor.red, [UInt8(255), 0, 0, 255]),
                                         ("B", UIColor.blue, [UInt8(0), 0, 255, 255])] {
            let manager = CanvasFixture.manager()
            manager.projectName = name
            manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
                CanvasFixture.solidImage(color, rect: CGRect(origin: .zero, size: size)), size: size)
            let url = ProjectStore.createNewProjectURL(name: name)
            saveAndWait(manager, to: url)
            let entry = try XCTUnwrap(celEntries(at: url).first)
            let id = try XCTUnwrap(entry["id"] as? String)
            let recorded = try XCTUnwrap(entry["rasterFileName"] as? String)
            XCTAssertEqual(recorded, "\(id)_raster.png", "PREMISE: the current writer's bare PNG name")
            XCTAssertNotEqual(entry["rasterOmitted"] as? Bool, true, "PREMISE: this PNG is required")
            let png = try XCTUnwrap(UIImage(contentsOfFile: url.appendingPathComponent("images")
                .appendingPathComponent(recorded).path))
            let cg = try XCTUnwrap(png.cgImage)
            let pngBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
            XCTAssertEqual(CGSize(width: cg.width, height: cg.height), size, "PREMISE: actual saved PNG extent")
            XCTAssertEqual(Array(pngBytes.prefix(4)), expected, "PREMISE: each package has distinct real pixels")
            let picture = XCTAttachment(image: png)
            picture.name = "containment-original-\(name)-whole-PNG"
            picture.lifetime = .keepAlways
            add(picture)
            packages.append(url)
            rasterNames.append(recorded)
        }
        let a = packages[0], b = packages[1]
        let aFiles = try packageFileBytes(at: a)
        let bFiles = try packageFileBytes(at: b)
        XCTAssertEqual(a.deletingLastPathComponent(), b.deletingLastPathComponent(), "PREMISE: actual siblings")
        XCTAssertEqual(b.lastPathComponent, "B.paintproj", "PREMISE: the addressed sibling's exact name")
        for (url, expected) in [(a, [UInt8(255), 0, 0, 255]), (b, [UInt8(0), 0, 255, 255])] {
            XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "PREMISE: the fresh writer package validates")
            let loaded = try XCTUnwrap(ProjectStore.load(from: url), "PREMISE: the fresh writer package loads")
            let raster = try XCTUnwrap(loaded.layers.first?.cels.first?.raster)
            let image = try raster.renderToUIImage().get()
            let cg = try XCTUnwrap(image.cgImage)
            let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
            XCTAssertEqual(Array(bytes.prefix(4)), expected, "PREMISE: actual load preserves the package's own colour")
        }
        XCTAssertEqual(try packageFileBytes(at: b), bFiles, "PREMISE: initial validation/load did not alter B")
        let manifest = a.appendingPathComponent("manifest.json")
        let original = try String(contentsOf: manifest, encoding: .utf8)
        let token = "\"\(rasterNames[0])\""
        let escaped = "../B.paintproj/images/\(rasterNames[1])"
        let changed = try XCTUnwrap(original.components(separatedBy: token).count == 2
            ? original.replacingOccurrences(of: token, with: "\"\(escaped)\"") : nil,
            "PREMISE: exactly one required raster token may change")
        try changed.write(to: manifest, atomically: true, encoding: .utf8)
        var otherA = try packageFileBytes(at: a), originalOtherA = aFiles
        otherA.removeValue(forKey: "manifest.json")
        originalOtherA.removeValue(forKey: "manifest.json")
        XCTAssertEqual(otherA, originalOtherA, "PREMISE: all of A's legitimate resource bytes stay intact")
        XCTAssertEqual(celEntries(at: a).first?["rasterFileName"] as? String, escaped, "PREMISE: only A addresses B's actual PNG")
        return (a, b, bFiles)
    }

    private func packageFileBytes(at package: URL) throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: package,
            includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in files {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(file.path.dropFirst(package.path.count + 1))] = try Data(contentsOf: file)
        }
        return result
    }

    func testTheValidatorRefusesARequiredRasterOutsideItsPackage() throws {
        let fixture = try siblingRasterEscape()
        XCTAssertFalse(ProjectBackupManager.validateProject(at: fixture.a),
                       "A required raster cannot belong to a sibling package, even when that PNG is valid")
        XCTAssertEqual(try packageFileBytes(at: fixture.b), fixture.bFiles, "Validation preserves all outside B bytes")
    }

    func testTheLoaderRefusesARequiredRasterOutsideItsPackage() throws {
        let fixture = try siblingRasterEscape()
        let loaded = ProjectStore.load(from: fixture.a)
        if let raster = loaded?.layers.first?.cels.first?.raster,
           case .success(let image) = raster.renderToUIImage() {
            let picture = XCTAttachment(image: image)
            picture.name = "containment-unexpectedly-loaded-A-whole-raster"
            picture.lifetime = .keepAlways
            add(picture)
        }
        XCTAssertNil(loaded,
                     "Loading must refuse A, rather than borrow B's pixels or silently omit A's required ink")
        XCTAssertEqual(try packageFileBytes(at: fixture.b), fixture.bFiles, "Loading preserves all outside B bytes")
    }

    // Additional address witnesses use only fresh roots owned by this test; no protected package
    // or brush-library file is opened. Each package first passes the real writer/validator/loader.
    private func addressPackage(_ name: String, color: UIColor, expected: [UInt8],
                                elements: [VectorElement] = []) throws -> URL {
        let manager = CanvasFixture.manager()
        manager.projectName = name
        manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
            CanvasFixture.solidImage(color, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)),
            size: CanvasFixture.canvasSize)
        if !elements.isEmpty {
            XCTAssertTrue(manager.addVectorLayer(), "PREMISE: the fixture admits its vector layer")
            manager.layers[manager.currentLayerIndex].cels[0].vector =
                VectorCanvas(size: CanvasFixture.canvasSize, elements: elements)
        }
        let url = ProjectStore.createNewProjectURL(name: name)
        saveAndWait(manager, to: url)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "PREMISE: the own-package references validate")
        let loaded = try XCTUnwrap(ProjectStore.load(from: url))
        let image = try XCTUnwrap(loaded.layers.first?.cels.first?.raster).renderToUIImage().get()
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(image.cgImage)))
        XCTAssertEqual(Array(bytes.prefix(4)), expected, "PREMISE: the healthy package reloads its own pixels")
        XCTAssertFalse(loaded.loadDamage.isDamaged, "PREMISE: healthy resources are not silently dropped")
        if !elements.isEmpty {
            let vector = try XCTUnwrap(loaded.layers.flatMap(\.cels).compactMap(\.vector).first)
            XCTAssertEqual(vector.elements.count, elements.count, "PREMISE: all healthy vector resources reload")
            let rendered = try XCTUnwrap(vector.render()?.cgImage)
            let rgba = try XCTUnwrap(CanvasFixture.rgbaBytes(rendered))
            XCTAssertTrue(stride(from: 3, to: rgba.count, by: 4).contains { rgba[$0] != 0 },
                          "PREMISE: the healthy vector content actually draws")
        }
        return url
    }

    private func addressStroke(_ brush: Brush = TestBrushes.hardRound) -> VectorElement {
        .stroke(VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: 8, opacity: 1, samples: [VectorSample(x: 16, y: 32, pressure: 1),
                                         VectorSample(x: 48, y: 32, pressure: 1)]))
    }

    private func rewriteAddress(_ old: String, as replacement: String, in file: URL) throws {
        let data = try Data(contentsOf: file)
        // JSONEncoder supplies the same escaping as the real payload, including slash spelling.
        let token = try JSONEncoder().encode(old), changed = try JSONEncoder().encode(replacement)
        let range = try XCTUnwrap(data.range(of: token), "PREMISE: the saved address token exists")
        XCTAssertNil(data.range(of: token, in: range.upperBound..<data.endIndex),
                     "PREMISE: exactly one resource address is replaced")
        var result = data
        result.replaceSubrange(range, with: changed)
        try result.write(to: file, options: .atomic)
    }

    private func drawingURL(in package: URL) throws -> URL {
        let name = try XCTUnwrap(celEntries(at: package).compactMap { $0["vectorFileName"] as? String }.first)
        return try ProjectPackageLayout.resolve(name, in: package)
    }

    func testPlacedImagePNGAndReferenceKeepTheDrawnPixelsAcrossSaveLoad() throws {
        let rawSize = CGSize(width: 3, height: 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let upright = UIGraphicsImageRenderer(size: rawSize, format: format).image { context in
            let colours: [UIColor] = [.red, .green, .blue, .cyan, .magenta, .yellow]
            for row in 0..<2 {
                for column in 0..<3 {
                    context.cgContext.setFillColor(colours[row * 3 + column].cgColor)
                    context.cgContext.fill(CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1))
                }
            }
        }
        let raw = try XCTUnwrap(upright.cgImage)
        let orientations: [UIImage.Orientation] = [
            .up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored
        ]
        let manager = CanvasFixture.manager()
        manager.projectName = "PlacedImageUnits"
        XCTAssertTrue(manager.addVectorLayer(name: "Photos"), "PREMISE: the package accepts a vector image layer")
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        for (index, orientation) in orientations.enumerated() {
            for (scaleIndex, scale) in [CGFloat(1), 2].enumerated() {
                let image = UIImage(cgImage: raw, scale: scale, orientation: orientation)
                let column = index % 4
                let row = (index / 4) * 2 + scaleIndex
                let element = VectorImageElement(
                    image: image,
                    transform: LayerTransform(position: CGPoint(x: CGFloat(8 + column * 16),
                                                                  y: CGFloat(8 + row * 16)),
                                              scale: 4, rotation: 0))
                vector.addImage(element)
            }
        }

        let originals = vector.images
        XCTAssertEqual(originals.count, orientations.count * 2,
                       "PREMISE: each orientation is represented at source scales 1 and 2")
        XCTAssertTrue(originals.allSatisfy {
            $0.image.cgImage?.width == raw.width && $0.image.cgImage?.height == raw.height
        }, "PREMISE: all orientations and scales retain the same full-resolution source pixels")
        let originalCanvas = try XCTUnwrap(vector.render()?.cgImage)
        let expectedCanvas = try XCTUnwrap(CanvasFixture.rgbaBytes(originalCanvas),
                                           "PREMISE: the placed image matrix renders")
        for image in originals {
            let x = Int(image.transform.position.x), y = Int(image.transform.position.y)
            let alpha = expectedCanvas[(y * originalCanvas.width + x) * 4 + 3]
            XCTAssertGreaterThan(alpha, 0,
                                 "PREMISE: orientation \(image.image.imageOrientation.rawValue), "
                                 + "scale \(image.image.scale) draws at its placed center")
        }

        func assertSavedImageGeometry(_ loaded: CanvasManager,
                                      expectedImages: [VectorImageElement],
                                      expectedCanvas: [UInt8], named pass: String) throws {
            XCTAssertFalse(loaded.loadDamage.isDamaged, "PREMISE: \(pass) package loads without damage")
            let loadedVector = try XCTUnwrap(loaded.layers.flatMap(\.cels).compactMap(\.vector).first,
                                             "PREMISE: \(pass) retains the vector layer")
            let reopened = loadedVector.images
            XCTAssertEqual(reopened.count, expectedImages.count, "PREMISE: \(pass) retains all placed images")
            for index in expectedImages.indices {
                let source = expectedImages[index]
                let actual = reopened[index]
                XCTAssertEqual(actual.image.imageOrientation, source.image.imageOrientation,
                               "\(pass) preserves orientation at image \(index)")
                XCTAssertEqual(actual.image.scale, 1,
                               "The package PNG's UIImage is decoded at scale 1 for image \(index)")
                XCTAssertEqual(actual.corners, source.corners,
                               "\(pass) keeps the same physical canvas quad at image \(index)")
                let sourcePixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(source.image.cgImage)))
                let actualPixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(actual.image.cgImage)))
                XCTAssertEqual(actualPixels, sourcePixels,
                               "\(pass) preserves every asymmetric source pixel at image \(index)")
            }
            let rendered = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(loadedVector.render()?.cgImage)))
            XCTAssertEqual(rendered, expectedCanvas, "\(pass) draws the complete same canvas pixels")
        }

        let firstPackage = ProjectStore.createNewProjectURL(name: "PlacedImageUnitsA")
        saveAndWait(manager, to: firstPackage)
        let firstLoad = try XCTUnwrap(ProjectStore.load(from: firstPackage), "PREMISE: the package reopens")
        try assertSavedImageGeometry(firstLoad, expectedImages: originals,
                                     expectedCanvas: expectedCanvas, named: "first save/load")

        let resaveVector = try XCTUnwrap(firstLoad.layers.flatMap(\.cels).compactMap(\.vector).first)
        resaveVector.addStroke(VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
            size: 2, opacity: 1,
            samples: [VectorSample(x: 3, y: 16, pressure: 1), VectorSample(x: 61, y: 16, pressure: 1)]))
        let resavedImages = resaveVector.images
        let resavedCanvas = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(resaveVector.render()?.cgImage)))
        XCTAssertNotEqual(resavedCanvas, expectedCanvas,
                          "PREMISE: a visible vector edit makes the second save re-encode its image references")
        let secondPackage = ProjectStore.createNewProjectURL(name: "PlacedImageUnitsB")
        saveAndWait(firstLoad, to: secondPackage)
        let secondLoad = try XCTUnwrap(ProjectStore.load(from: secondPackage), "PREMISE: the resaved package reopens")
        try assertSavedImageGeometry(secondLoad, expectedImages: resavedImages,
                                     expectedCanvas: resavedCanvas, named: "second save/load")
    }

    func testOutsideBrushTableAddressesAreRefusedByValidationAndLoading() throws {
        let a = try addressPackage("TableA", color: .red, expected: [255, 0, 0, 255], elements: [addressStroke()])
        let b = try addressPackage("TableB", color: .blue, expected: [0, 0, 255, 255], elements: [addressStroke()])
        let bFiles = try packageFileBytes(at: b)
        let table = try XCTUnwrap(manifestJSON(at: a)["brushTableFileName"] as? String)
        let otherTable = try XCTUnwrap(manifestJSON(at: b)["brushTableFileName"] as? String)
        try rewriteAddress(table, as: "../\(b.lastPathComponent)/\(otherTable)",
                           in: a.appendingPathComponent("manifest.json"))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: a), "An outside brush table is not this package's table")
        XCTAssertNil(ProjectStore.load(from: a), "An outside table must refuse the open, not redeem foreign brushes")
        XCTAssertEqual(try packageFileBytes(at: b), bFiles, "The neighboring table package stays byte-exact")
    }

    func testOutsideBrushTextureNamesRefuseBeforeRestoringIntoTheIsolatedLibrary() throws {
        let oldLibrary = BrushStorage.shared.root
        let library = root.appendingPathComponent("library/selected", isDirectory: true)
        BrushStorage.shared.relocate(to: library)
        defer { BrushStorage.shared.relocate(to: oldLibrary) }
        let name = "custom-\(UUID().uuidString).png"
        let stamp = CanvasFixture.solidImage(.white, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                             size: CGSize(width: 8, height: 8))
        let stampBytes = try XCTUnwrap(stamp.pngData())
        try BrushStorage.shared.write(stampBytes, to: name)
        var brush = TestBrushes.hardRound
        brush.tip = .stamp(.imported(fileName: name))
        let a = try addressPackage("TextureA", color: .red, expected: [255, 0, 0, 255], elements: [addressStroke(brush)])
        let b = try addressPackage("TextureB", color: .blue, expected: [0, 0, 255, 255])
        let neighbor = b.appendingPathComponent("tip.png")
        try stampBytes.write(to: neighbor)
        let bFiles = try packageFileBytes(at: b), libraryFiles = try packageFileBytes(at: library)
        let table = a.appendingPathComponent(try XCTUnwrap(manifestJSON(at: a)["brushTableFileName"] as? String))
        let bad = "../../\(b.lastPathComponent)/tip.png"
        // Package lookup reaches Projects/TextureB; a mistaken library restore would write under
        // this test's root/TextureB instead. Both targets remain inside the disposable fixture root.
        let unexpected = library.appendingPathComponent(bad).standardizedFileURL
        guard unexpected.path.hasPrefix(root.path + "/") else {
            return XCTFail("PREMISE: even old writer side effects must be test-owned")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpected.path))
        try rewriteAddress(name, as: bad, in: table)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: a), "A texture reference may not escape package brushes")
        XCTAssertNil(ProjectStore.load(from: a), "An invalid texture name refuses before library restoration")
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpected.path), "Loading cannot write the invalid name outside the isolated library")
        XCTAssertEqual(try packageFileBytes(at: library), libraryFiles, "The isolated library stays byte-exact")
        XCTAssertEqual(try packageFileBytes(at: b), bFiles, "The neighboring texture stays byte-exact")
    }

    func testKnownNestedMediaAddressesRefuseInsteadOfDroppingOrBorrowingContent() throws {
        let picture = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                               size: CGSize(width: 8, height: 8))
        let source = root.appendingPathComponent("clip.mov")
        let assetBytes = Data("the existing video model fixture checks presence, not a media decoder".utf8)
        try assetBytes.write(to: source)
        let image = VectorImageElement(image: picture, transform: LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0), fileName: "placed.png")
        let video = VectorVideoElement(assetURL: source, assetFileName: "clip.mov", naturalSize: CGSize(width: 8, height: 8),
            sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1),
            transform: LayerTransform(position: CGPoint(x: 40, y: 40), scale: 1, rotation: 0))
        let stream = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8), host: "fixture", port: 47301,
            sourceLabel: "fixture", isFrozen: true, rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 48, y: 16), scale: 1, rotation: 0), picture: StreamPicture(frame: picture, index: 1))
        let elements: [VectorElement] = [.image(image), .video(video), .stream(stream)]
        let a = try addressPackage("MediaA", color: .red, expected: [255, 0, 0, 255], elements: elements)
        let b = try addressPackage("MediaB", color: .blue, expected: [0, 0, 255, 255], elements: elements)
        let bFiles = try packageFileBytes(at: b), file = try drawingURL(in: a), original = try Data(contentsOf: file)
        let other = try JSONDecoder().decode(VectorCanvasData.self, from: Data(contentsOf: drawingURL(in: b)))
        let payload = try JSONDecoder().decode(VectorCanvasData.self, from: original)
        let aImage = try XCTUnwrap(payload.elements.compactMap { if case .image(let ref) = $0 { return ref.fileName }; return nil }.first)
        let aVideo = try XCTUnwrap(payload.elements.compactMap { if case .video(let ref) = $0 { return ref.fileName }; return nil }.first)
        let aStream = try XCTUnwrap(payload.elements.compactMap { if case .stream(let ref) = $0 { return ref.lastFrameFileName }; return nil }.first)
        let bStream = try XCTUnwrap(other.elements.compactMap { if case .stream(let ref) = $0 { return ref.lastFrameFileName }; return nil }.first)
        let healthy = try XCTUnwrap(ProjectStore.load(from: a))
        let vector = try XCTUnwrap(healthy.layers.flatMap(\.cels).compactMap(\.vector).first)
        XCTAssertEqual(vector.images.count, 1); XCTAssertEqual(vector.videos.count, 1); XCTAssertEqual(vector.streams.count, 1)
        XCTAssertEqual(try Data(contentsOf: b.appendingPathComponent("videos/clip.mov")), assetBytes)
        let rendered = try XCTUnwrap(vector.render()?.cgImage), bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(rendered))
        XCTAssertGreaterThan(Int(bytes[(16 * rendered.width + 16) * 4 + 1]), 200, "PREMISE: the healthy own image really draws green")
        XCTAssertNotNil(vector.streams.first?.displayFrame, "PREMISE: the healthy stream's saved picture reloads")
        XCTAssertGreaterThan(Int(bytes[(16 * rendered.width + 48) * 4 + 1]), 200, "PREMISE: the healthy own stream picture really draws green")
        for (name, path) in [(aImage, "images/placed.png"), (aVideo, "videos/clip.mov"), (aStream, "images/\(bStream)")] {
            try original.write(to: file, options: .atomic)
            try rewriteAddress(name, as: "../\(b.lastPathComponent)/\(path)", in: file)
            XCTAssertFalse(ProjectBackupManager.validateProject(at: a), "A known nested resource cannot address a neighboring package: \(path)")
            XCTAssertNil(ProjectStore.load(from: a), "Invalid known refs refuse the open rather than drop, placeholder or borrow: \(path)")
            XCTAssertEqual(try packageFileBytes(at: b), bFiles, "Each nested consumer preserves all neighbor bytes")
        }
    }

    func testLinkedRequiredRasterParentsAndLeavesAreRefused() throws {
        let a = try addressPackage("LinkA", color: .red, expected: [255, 0, 0, 255])
        let b = try addressPackage("LinkB", color: .blue, expected: [0, 0, 255, 255])
        let bFiles = try packageFileBytes(at: b), manifest = a.appendingPathComponent("manifest.json")
        let original = try Data(contentsOf: manifest)
        let aName = try XCTUnwrap(celEntries(at: a).first?["rasterFileName"] as? String)
        let bName = try XCTUnwrap(celEntries(at: b).first?["rasterFileName"] as? String)
        let parent = a.appendingPathComponent("linked-images"), leaf = a.appendingPathComponent("images/linked.png")
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: b.appendingPathComponent("images"))
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: b.appendingPathComponent("images/\(bName)"))
        for name in ["linked-images/\(bName)", "linked.png"] {
            try original.write(to: manifest, options: .atomic)
            try rewriteAddress(aName, as: name, in: manifest)
            XCTAssertFalse(ProjectBackupManager.validateProject(at: a), "Linked required raster resources are not package-owned")
            XCTAssertNil(ProjectStore.load(from: a), "A linked raster must refuse, not follow the neighbor's pixels")
            XCTAssertEqual(try packageFileBytes(at: b), bFiles, "Link checks preserve neighbor bytes")
        }
    }

    func testAnInvalidProvidedImageNameRefusesTheSaveBeforeAnyOutsideWrite() throws {
        let picture = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                               size: CGSize(width: 8, height: 8))
        var image = VectorImageElement(image: picture, transform: LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0), fileName: "placed.png")
        let manager = CanvasFixture.manager()
        manager.projectName = "WriteA"
        XCTAssertTrue(manager.addVectorLayer())
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        vector.addImage(image)
        let a = ProjectStore.createNewProjectURL(name: manager.projectName)
        saveAndWait(manager, to: a)
        let healthy = try XCTUnwrap(ProjectStore.load(from: a))
        let own = try XCTUnwrap(healthy.layers.flatMap(\.cels).compactMap(\.vector).first)
        let ownImage = try XCTUnwrap(own.render()?.cgImage), pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(ownImage))
        XCTAssertGreaterThan(Int(pixels[(16 * ownImage.width + 16) * 4 + 1]), 200, "PREMISE: the healthy save/load draws the actual own image")
        let aFiles = try packageFileBytes(at: a)
        let b = try addressPackage("WriteB", color: .blue, expected: [0, 0, 255, 255])
        let bFiles = try packageFileBytes(at: b)
        let name = "escaped-\(UUID().uuidString).png"
        let outside = a.deletingLastPathComponent().appendingPathComponent(name)
        guard outside.path.hasPrefix(root.path + "/") else {
            return XCTFail("PREMISE: all old write destinations must remain inside this test owner")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        image.fileName = "../\(name)"
        vector.restoreElements([.image(image)], changedInk: nil)
        saveAndWait(manager, to: a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path), "A provided image name cannot write outside its staged package")
        XCTAssertEqual(try packageFileBytes(at: a), aFiles, "A refused invalid address preserves the prior live package")
        XCTAssertEqual(try packageFileBytes(at: b), bFiles, "The neighboring package stays byte-exact")
    }

    func testLiteralLegalAddressesKeepTheirBytesAndMissingLeafIdentity() throws {
        let fm = FileManager.default
        let package = root.appendingPathComponent("Literal.paintproj", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try ProjectPackageLayout.createDirectories([.placedImage], in: package)
        let bytes = Data([0, 17, 128, 255])
        for name in ["white space.png", "雪%2F%2E.png", "..ordinary..png", ".tip.png"] {
            let file = try ProjectPackageLayout.writeURL(named: name, role: .placedImage, in: package)
            XCTAssertEqual(file.lastPathComponent, name, "Legal names are literal, including percent escapes")
            XCTAssertEqual(try ProjectPackageLayout.writePath(named: name, role: .placedImage), "images/\(name)")
            try bytes.write(to: file)
            let reopened = try ProjectPackageLayout.existingURL(named: name, role: .placedImage, in: package)
            XCTAssertEqual(try Data(contentsOf: reopened), bytes, "Read and write resolve the same literal bytes")
        }
        let directory = try ProjectPackageLayout.resolve("custom folder", in: package, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let name = "custom folder/真%2F.png"
        let file = try ProjectPackageLayout.writeURL(named: name, role: .placedImage, in: package)
        try bytes.write(to: file)
        XCTAssertEqual(file.deletingLastPathComponent(), directory, "A legal slashed name stays package-relative")
        XCTAssertEqual(try Data(contentsOf: ProjectPackageLayout.existingURL(named: name, role: .placedImage, in: package)), bytes)
        let missing = package.appendingPathComponent("images/absent.png")
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: "absent.png", role: .placedImage, in: package),
                       missing, "A missing legal leaf keeps its diagnostic address")
        XCTAssertFalse(fm.fileExists(atPath: missing.path))
        XCTAssertEqual(try ProjectPackageLayout.resolve("not created/yet/file.png", in: package),
                       package.appendingPathComponent("not created/yet/file.png"), "A missing legal suffix can be staged")
    }

    func testTheAddressAuthorityRejectsInvalidComponentsAndWrongEntryKinds() throws {
        let fm = FileManager.default
        let package = root.appendingPathComponent("Kinds.paintproj", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        for name in ["", "/absolute", "a//b", "a/", "./a", "a/../b", "a/./b", "a\0b"] {
            XCTAssertThrowsError(try ProjectPackageLayout.resolve(name, in: package), "Invalid path: \(name)")
            XCTAssertThrowsError(try ProjectPackageLayout.writePath(named: name, role: .placedImage))
            XCTAssertThrowsError(try ProjectPackageLayout.existingURL(named: name, role: .placedImage, in: package))
        }
        let file = package.appendingPathComponent("ordinary")
        try Data([1]).write(to: file)
        let directory = package.appendingPathComponent("directory", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ProjectPackageLayout.resolve("ordinary/child", in: package), "A file cannot be a parent")
        XCTAssertThrowsError(try ProjectPackageLayout.resolve("directory", in: package), "A resource leaf cannot be a directory")
        XCTAssertThrowsError(try ProjectPackageLayout.resolve("ordinary", in: package, isDirectory: true))
        for (name, target) in [("linked-file", file), ("linked-directory", directory),
                               ("dangling", package.appendingPathComponent("absent"))] {
            try fm.createSymbolicLink(at: package.appendingPathComponent(name), withDestinationURL: target)
            XCTAssertThrowsError(try ProjectPackageLayout.resolve(name, in: package), "Links are invalid even when their target is inside")
        }
        XCTAssertThrowsError(try ProjectPackageLayout.resolve("linked-directory/absent", in: package))
    }

    func testAMalformedKnownMediaSlotCannotHideAnInvalidAddress() throws {
        let picture = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                               size: CGSize(width: 8, height: 8))
        let image = VectorImageElement(image: picture,
            transform: LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0), fileName: "placed.png")
        let package = try addressPackage("MalformedAddress", color: .red, expected: [255, 0, 0, 255], elements: [.image(image)])
        let file = try drawingURL(in: package)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var slots = try XCTUnwrap(json["elements"] as? [[String: Any]])
        let index = try XCTUnwrap(slots.firstIndex { $0["kind"] as? String == "image" })
        var fields = try XCTUnwrap(slots[index]["image"] as? [String: Any])
        fields.removeValue(forKey: "x")
        slots[index]["image"] = fields
        json["elements"] = slots
        let malformed = try JSONSerialization.data(withJSONObject: json)
        try malformed.write(to: file, options: .atomic)
        let ordinary = try XCTUnwrap(ProjectStore.load(from: package))
        XCTAssertEqual(ordinary.loadDamage.itemCount, 1, "An ordinary malformed image retains reported-loss policy")
        fields["fileName"] = "../outside.png"
        slots[index]["image"] = fields
        json["elements"] = slots
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: package), "Known invalid addresses survive metadata preflight")
        XCTAssertNil(ProjectStore.load(from: package), "Address refusal must precede the ordinary malformed-slot drop")
    }

    // MARK: - The sweep: no empty content directory, by either route

    /// **A directory the migration empties does not stay standing** — TODO (57) part 3.
    ///
    /// This is the whole of part 1's own complaint arriving one door over, at the worst possible
    /// moment. A vector-only package written before (57) keeps nothing in `images/` *but* the three
    /// JSON sidecars; the launch pass moves them into `drawings/` and, without this, leaves an empty
    /// `images/` beside them — at exactly the launch the artist opens Files to see whether the update
    /// did what it said. `createDirectories`' laziness does not reach this: it makes the *writer*
    /// exact, and nothing has been re-saved yet.
    func testTheMigrationRemovesTheImagesDirectoryItEmpties() {
        let url = savedProject()
        makeLegacyLayout(at: url)
        // The premise, asserted before the fix is: the legacy fixture really does put an `images/`
        // there, holding nothing but the sidecars that are about to leave.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("images", isDirectory: true).path),
            "Setup: the pre-(57) shape has an images/ directory")
        XCTAssertEqual(names(in: "images", at: url).filter { !$0.hasSuffix(".json") }, [],
                       "Setup: and it holds nothing but JSON, because the fixture draws no pixels")

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("images", isDirectory: true).path),
            "the folder the sidecars came out of does not survive them")
        assertInkSurvived(at: url, "a package whose images/ was swept")
    }

    /// **And one it does not empty is left exactly as it was.** The sweep's whole safety argument is
    /// that `rmdir(2)` refuses a non-empty directory in the kernel, so this is the assertion that
    /// says the refusal is real rather than assumed — and it is the one a "list it, then remove it"
    /// implementation could get wrong.
    func testTheMigrationLeavesAnImagesDirectoryThatStillHoldsAPixel() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let images = url.appendingPathComponent("images", isDirectory: true)
        // A PNG the migration knows nothing about — it is named in no manifest and moves nowhere.
        let bystander = images.appendingPathComponent("keepme.png")
        try Data("not a real png".utf8).write(to: bystander)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url))

        XCTAssertTrue(FileManager.default.fileExists(atPath: images.path),
                      "images/ still holds something, so it stays")
        XCTAssertEqual(try Data(contentsOf: bystander), Data("not a real png".utf8),
                       "and the something is byte-for-byte what it was — the sweep removes "
                       + "directories, never their contents")
    }

    /// **A clip an older build left in `images/` keeps its folder**, which is the case that would
    /// have made a careless sweep lose a video. The sidecars leave, the `.mp4` does not (its name
    /// lives in the vector payload, so nothing migrates it), and `images/` is therefore still the
    /// address the resolver's `.video` alternate probes.
    func testTheSweepDoesNotStrandAClipAnOlderBuildLeftInImages() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let images = url.appendingPathComponent("images", isDirectory: true)
        let clip = images.appendingPathComponent("\(UUID().uuidString)_video.mp4")
        try Data("clip".utf8).write(to: clip)

        ProjectPackageLayout.tidy(packageAt: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path),
                      "the clip is still where the older build put it, and images/ with it")
        XCTAssertEqual(
            try ProjectPackageLayout.existingURL(named: clip.lastPathComponent, role: .video, in: url),
            clip, "so the resolver's videos/-then-images/ probe still finds it")
    }

    /// **The launch pass reports what it swept**, under the package's name — the counterpart to the
    /// `movedFiles` and `renamed` counts beside it, and the only way an artist's log says where an
    /// empty folder went.
    func testTheLaunchPassReportsTheEmptyDirectoriesItRemoved() {
        let url = savedProject(named: "Swept")
        makeLegacyLayout(at: url)

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(report.emptiedDirectories, ["Swept.paintproj/images"],
                       "got \(report.emptiedDirectories)")

        // **`isEmpty` gates the pass's whole log line, so it has to count this.** Asserted on a
        // constructed `Report` rather than on the one above, because that one also moved files —
        // its `tidied` is non-empty, so `XCTAssertFalse(report.isEmpty)` there would hold whether
        // `isEmpty` looked at this field or not.
        var sweepOnly = ProjectPackageLayout.Report()
        sweepOnly.emptiedDirectories = ["Somewhere.paintproj/images"]
        XCTAssertFalse(sweepOnly.isEmpty,
                       "a pass whose only work was removing a directory is not an empty pass, and "
                       + "an empty pass says nothing in the log")
        XCTAssertTrue(ProjectPackageLayout.Report().isEmpty, "and a pass that did nothing is")
    }

    /// **The writer's own route to an empty folder, which the role scan cannot close.** That scan
    /// reads the snapshot and creates `videos/` because the document *has* a clip; the copy that was
    /// supposed to fill it can still fail — here because the asset the element names is gone, which
    /// is `VectorVideoElement`'s own documented hazard. Without the sweep the artist gets a saved
    /// package containing an empty `videos/` and no word of complaint.
    func testASaveWhoseClipCannotBeCopiedShipsNoEmptyVideosDirectory() throws {
        let manager = makeManager()
        let canvas = try XCTUnwrap(manager.layers[manager.layers.count - 1].cels[0].vector,
                                   "Setup: makeManager's last layer is the vector one")
        // An element naming a file that is not there. The save creates `videos/` from the snapshot
        // and then has nothing to put in it.
        let missing = root.appendingPathComponent("gone-\(UUID().uuidString).mov")
        canvas.elements.append(.video(VectorVideoElement(
            assetURL: missing, assetFileName: missing.lastPathComponent,
            naturalSize: CGSize(width: 32, height: 18),
            sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1), speed: 1,
            transform: LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0))))
        canvas.bumpVersion()

        let url = ProjectStore.createNewProjectURL(name: "Lost Clip")
        saveAndWait(manager, to: url)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("videos", isDirectory: true).path),
            "the copy failed, so nothing is in videos/, so there is no videos/")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "and the directory that did get content is untouched — the sweep is about emptiness, "
            + "not about videos")
    }

    /// **The accepted one-way break, asserted so it cannot be un-noticed** — BUGS.md carries the
    /// sentence and the rule that comes with it.
    ///
    /// A build older than (57) resolves `vectorFileName` as `images/<name>`, with no awareness of a
    /// slash. This is that arithmetic, done here rather than left as prose: the path such a build
    /// would compute does not exist, so it falls through `decodeCel`'s `?? .empty` and the cel's ink
    /// loads blank. No scheme avoids it — the manifest field is one string, so it either names the old
    /// address (and the JSON has not left `images/`, which is the whole ask) or it names the new one.
    /// If anyone ever adds a compatibility shim, this test is what tells them it worked.
    func testAnOlderBuildJoiningTheNameToImagesFindsNothing() throws {
        let url = savedProject()
        let recorded = try XCTUnwrap(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first)
        let asAnOldBuildWouldJoinIt = url.appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(recorded)

        XCTAssertFalse(FileManager.default.fileExists(atPath: asAnOldBuildWouldJoinIt.path),
                       "images/\(recorded) is what a pre-(57) build looks for, and it is not there — "
                       + "such a build opens this package with every drawing blank. Accepted, one-way, "
                       + "and the reason no worktree may install an older commit over a device that "
                       + "has run this one; the preupdate- clone in Backups/ is the way back")
        // And the address this build uses is the one that is actually there, so the break is about
        // the old resolver rather than about a file that failed to get written.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try ProjectPackageLayout.resolve(recorded, in: url).path),
            "the drawing itself is present at the address this build records")
    }

    // MARK: - (b) A package in the old layout still opens, with its ink

    func testAPackageInTheOldLayoutLoadsWithItsStrokesIntact() {
        let url = savedProject()
        makeLegacyLayout(at: url)

        // The premise, asserted before the fix is: the sidecars really are back under images/ and the
        // manifest really does name them bare. Without this the test below could be green against a
        // fixture that changed nothing.
        XCTAssertTrue(names(in: "images", at: url).contains { $0.hasSuffix("_vector.json") },
                      "Setup: the legacy fixture puts the drawing back under images/_vector.json")
        for cel in celEntries(at: url) {
            let drawing = cel["vectorFileName"] as? String
            XCTAssertEqual(drawing?.contains("/"), false,
                           "Setup: a legacy manifest names its sidecar bare, got \(drawing ?? "nil")")
        }

        assertInkSurvived(at: url, "a package in the pre-(57) layout")
    }

    /// And the validator agrees, which is the gate every save and the launch repair pass run through.
    func testAPackageInTheOldLayoutStillValidates() {
        let url = savedProject()
        makeLegacyLayout(at: url)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "a legacy package is intact, not damaged — calling it damaged would make "
                      + "repairCorruptedProjects restore over a perfectly good project")
    }

    // MARK: - (c) The migration, and its crash-resume table row by row

    func testTheMigrationMovesEverySidecarOutOfImagesAndRewritesTheManifest() {
        let url = savedProject()
        let pushedBack = makeLegacyLayout(at: url)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url),
                       "a legacy package is tidied")

        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                       "every JSON sidecar has left images/")
        XCTAssertEqual(names(in: "drawings", at: url).count, pushedBack,
                       "and all \(pushedBack) of them arrived in drawings/")
        for cel in celEntries(at: url) {
            for (key, _) in Self.movedFields {
                guard let recorded = cel[key] as? String else { continue }
                XCTAssertTrue(recorded.hasPrefix("drawings/"),
                              "the manifest's \(key) now names the new address, got \(recorded)")
                XCTAssertTrue(FileManager.default.fileExists(
                    atPath: try ProjectPackageLayout.resolve(recorded, in: url).path),
                    "and \(recorded) is actually there")
            }
        }
        assertInkSurvived(at: url, "a migrated package")
    }

    /// **Row 1 of the resume table: killed after a sidecar moved, before the manifest was rewritten.**
    /// The file is at `drawings/` and the manifest still names it bare — which is the state the
    /// resolver's whole probe order exists for.
    func testAMigrationKilledBeforeTheManifestRewriteStillLoadsWholeAndIsFinishedNextRun() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)

        // Move the files exactly as `tidy` would and leave the manifest alone — the interruption.
        let images = url.appendingPathComponent("images", isDirectory: true)
        let drawings = url.appendingPathComponent("drawings", isDirectory: true)
        try FileManager.default.createDirectory(at: drawings, withIntermediateDirectories: true)
        var movedByHand = 0
        for cel in celEntries(at: url) {
            let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
            for (key, role) in Self.movedFields {
                guard let recorded = cel[key] as? String, !recorded.contains("/") else { continue }
                try FileManager.default.moveItem(
                    at: images.appendingPathComponent(recorded),
                    to: try ProjectPackageLayout.resolve(ProjectPackageLayout.recordedName(for: role, cel: celID),
                                                     in: url))
                movedByHand += 1
            }
        }
        XCTAssertGreaterThan(movedByHand, 0, "Setup: the interruption should have moved something")

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "a package caught between the move and the manifest rewrite is intact, not "
                      + "damaged — if the validator said otherwise, repairCorruptedProjects would "
                      + "restore over it and tidy's own step-0 guard would refuse to finish the job")
        assertInkSurvived(at: url, "a package caught between the move and the manifest rewrite")

        // The next launch finishes it. There is nothing left to *move* — but the interruption is
        // exactly what leaves an empty `images/` standing, so the sweep has something to do and the
        // outcome says so rather than claiming the pass changed nothing.
        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url),
                       "the files are already at their new address, so the only thing left is the "
                       + "images/ the interrupted move emptied")
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.path),
                       "and it is gone — an empty images/ beside drawings/ is the owner's own "
                       + "complaint arriving one door over")
        assertInkSurvived(at: url, "the same package after the pass re-ran")

        // *Now* a re-run has nothing to do, which is what idempotence means here.
        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .unchanged,
                       "a third run over a package with nothing left changes nothing")
    }

    /// **Row 2: killed between two moves** — some sidecars moved, some still under `images/`, the
    /// manifest naming the old address for all of them. Every file resolves, and the next run moves
    /// the rest.
    func testAMigrationKilledBetweenTwoMovesIsFinishedByTheNextRun() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)

        // Move exactly one sidecar by hand, then stop.
        let cel = try XCTUnwrap(celEntries(at: url).first { $0["vectorFileName"] is String })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let bare = try XCTUnwrap(cel["vectorFileName"] as? String)
        let drawings = url.appendingPathComponent("drawings", isDirectory: true)
        try FileManager.default.createDirectory(at: drawings, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: url.appendingPathComponent("images", isDirectory: true).appendingPathComponent(bare),
            to: try ProjectPackageLayout.resolve(ProjectPackageLayout.recordedName(for: .drawing, cel: celID),
                                             in: url))
        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }.count, 1,
                       "Setup: one sidecar moved and one is still under images/")

        assertInkSurvived(at: url, "a package split across both addresses")

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url),
                       "the next run finishes what is left")
        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                       "and images/ is clear of JSON afterwards")
        assertInkSurvived(at: url, "the finished package")
    }

    /// **Row 4: a third run changes nothing.** Idempotence is a claim about the second and third
    /// runs, and nothing but running it again tests it.
    func testTidyIsIdempotentAndAFullyTidyPackageIsUnchanged() {
        let url = savedProject()
        makeLegacyLayout(at: url)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url), "the first run migrates")
        let afterFirst = manifestJSON(at: url)
        let namesAfterFirst = names(in: "drawings", at: url)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .unchanged, "the second run has nothing to do")
        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .unchanged, "and neither does the third")
        XCTAssertEqual(names(in: "drawings", at: url), namesAfterFirst,
                       "drawings/ holds exactly what the first run put there")
        XCTAssertEqual(NSDictionary(dictionary: manifestJSON(at: url)), NSDictionary(dictionary: afterFirst),
                       "and the manifest is byte-for-byte the one the first run wrote")
        assertInkSurvived(at: url, "a package tidied three times")
    }

    /// A later occupied destination refuses the entire plan before an earlier drawing can move.
    /// The file at the occupied address belongs to somebody else; tidy neither adopts nor replaces it.
    func testALaterOccupiedSidecarDestinationRefusesWholePlan() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)

        let cel = try XCTUnwrap(celEntries(at: url).first {
            $0["vectorFileName"] is String && $0["animationFileName"] is String
        })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let drawingName = try XCTUnwrap(cel["vectorFileName"] as? String)
        let animationName = try XCTUnwrap(cel["animationFileName"] as? String)
        let images = url.appendingPathComponent("images", isDirectory: true)
        let legacyDrawing = images.appendingPathComponent(drawingName)
        let legacyAnimation = images.appendingPathComponent(animationName)
        let drawingDestination = try ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: celID), in: url)
        let animationDestination = try ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .animation, cel: celID), in: url)
        try FileManager.default.createDirectory(at: animationDestination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let intruder = Data("{\"elements\":[]}".utf8)
        try intruder.write(to: animationDestination)
        let manifestURL = url.appendingPathComponent("manifest.json")
        let manifestBytes = try Data(contentsOf: manifestURL)
        let drawingBytes = try Data(contentsOf: legacyDrawing)
        let animationBytes = try Data(contentsOf: legacyAnimation)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .skippedDamaged,
                       "the whole sidecar plan refuses when a later target is already owned")

        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBytes,
                       "preflight refusal leaves the manifest byte-for-byte unchanged")
        XCTAssertEqual(try Data(contentsOf: legacyDrawing), drawingBytes,
                       "the earlier drawing remains byte-for-byte at its old address")
        XCTAssertFalse(FileManager.default.fileExists(atPath: drawingDestination.path),
                       "the earlier generated destination remains absent")
        XCTAssertEqual(try Data(contentsOf: legacyAnimation), animationBytes,
                       "the animation remains byte-for-byte at its old address")
        XCTAssertEqual(try Data(contentsOf: animationDestination), intruder,
                       "the occupied destination remains byte-for-byte with its existing owner")
    }

    /// The later cel's linked generated destination must be found before either earlier sidecar moves.
    func testTidyRefusesALaterLinkedDestinationBeforeMovingEarlierCels() throws {
        let manager = makeManager()
        let earlyCel = try XCTUnwrap(manager.layers[0].cels.first,
                                     "PREMISE: makeManager creates the earlier vector cel")
        let laterStart = earlyCel.endFrame
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: laterStart),
                      "PREMISE: create a nonoverlapping cel after the first cel's full scene span")
        let laterCanvas = try XCTUnwrap(
            manager.layers[0].cels.first(where: { $0.startFrame == laterStart })?.vector,
            "PREMISE: the later cel owns a vector drawing")
        manager.projectName = "TidyLinkedDestination"
        laterCanvas.addStroke(VectorStroke(
            brush: manager.toolProfiles.brush.preset,
            color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: 8, opacity: 1,
            samples: [VectorSample(x: 20, y: 30, pressure: 1),
                      VectorSample(x: 70, y: 80, pressure: 1)]))

        let url = ProjectStore.createNewProjectURL(name: "OldTidyFolder")
        let renameTarget = url.deletingLastPathComponent()
            .appendingPathComponent("TidyLinkedDestination.paintproj", isDirectory: true)
        saveAndWait(manager, to: url)
        let earlyID = try XCTUnwrap(manager.layers[0].cels.first(where: { $0.startFrame == 0 })?.id)
        let laterID = try XCTUnwrap(manager.layers[0].cels.first(where: { $0.startFrame == laterStart })?.id)

        XCTAssertEqual(makeLegacyLayout(at: url), 3,
                       "PREMISE: the first cel has drawing+animation and the later cel has its drawing")
        let entries = celEntries(at: url)
        XCTAssertEqual(entries.count, 2, "PREMISE: the saved package has exactly two cels")
        XCTAssertEqual(entries.compactMap { $0["id"] as? String },
                       [earlyID.uuidString, laterID.uuidString],
                       "PREMISE: the symlinked cel is later in manifest/work order")
        let early = try XCTUnwrap(entries.first { $0["id"] as? String == earlyID.uuidString })
        let later = try XCTUnwrap(entries.first { $0["id"] as? String == laterID.uuidString })
        let oldNames = [
            try XCTUnwrap(early["vectorFileName"] as? String),
            try XCTUnwrap(early["animationFileName"] as? String),
            try XCTUnwrap(later["vectorFileName"] as? String)
        ]
        let manifestURL = url.appendingPathComponent("manifest.json")
        let originalManifest = try Data(contentsOf: manifestURL)
        let images = url.appendingPathComponent("images", isDirectory: true)
        let oldSources = oldNames.map { images.appendingPathComponent($0) }
        let oldBytes = try oldSources.map { try Data(contentsOf: $0) }
        let earlyDestinations = [
            try ProjectPackageLayout.resolve(
                ProjectPackageLayout.recordedName(for: .drawing, cel: earlyID), in: url),
            try ProjectPackageLayout.resolve(
                ProjectPackageLayout.recordedName(for: .animation, cel: earlyID), in: url)
        ]
        let laterDestination = try ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: laterID), in: url)
        let external = root.appendingPathComponent("preserved-external-data.bin")
        let externalBytes = Data("preserve this data outside the package".utf8)
        try externalBytes.write(to: external)
        try FileManager.default.createDirectory(at: laterDestination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: laterDestination, withDestinationURL: external)
        let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: laterDestination.path)

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "PREMISE: all manifest-named legacy sources make the package valid")
        XCTAssertTrue(FileManager.default.fileExists(atPath: laterDestination.path),
                      "PREMISE: the later symlink resolves to existing external data")
        XCTAssertFalse(earlyDestinations.contains { FileManager.default.fileExists(atPath: $0.path) },
                       "PREMISE: earlier generated destinations are free before tidy")

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .skippedDamaged,
                       "the linked later destination refuses the complete migration plan")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "preflight refusal leaves the package at its original folder name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: renameTarget.path),
                       "preflight refusal does not perform the otherwise valid title rename")
        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifest,
                       "refusal leaves the manifest byte-for-byte unchanged")
        for (source, bytes) in zip(oldSources, oldBytes) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                          "refusal leaves each sidecar at its old address")
            XCTAssertEqual(try Data(contentsOf: source), bytes,
                           "refusal preserves each old sidecar byte-for-byte")
        }
        XCTAssertFalse(earlyDestinations.contains { FileManager.default.fileExists(atPath: $0.path) },
                       "refusal creates none of the earlier generated destinations")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: laterDestination.path),
                       linkTarget, "refusal keeps the later symlink pointed at its original owner")
        XCTAssertEqual(try Data(contentsOf: external), externalBytes,
                       "refusal preserves external data byte-for-byte")
        XCTAssertEqual(try Data(contentsOf: laterDestination), externalBytes,
                       "the linked destination still resolves to the same external bytes")
    }

    /// A later directory at a file destination is rejected by the existing checked resolver before
    /// an earlier drawing can move.
    func testTidyRefusesALaterDirectoryDestinationBeforeMovingEarlierSidecar() throws {
        let url = savedProject()
        XCTAssertEqual(makeLegacyLayout(at: url), 2,
                       "PREMISE: one cel has a drawing followed by an animation sidecar")
        let cel = try XCTUnwrap(celEntries(at: url).first {
            $0["vectorFileName"] is String && $0["animationFileName"] is String
        })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let images = url.appendingPathComponent("images", isDirectory: true)
        let oldDrawing = images.appendingPathComponent(try XCTUnwrap(cel["vectorFileName"] as? String))
        let oldAnimation = images.appendingPathComponent(try XCTUnwrap(cel["animationFileName"] as? String))
        let drawingDestination = try ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: celID), in: url)
        let animationDestination = try ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .animation, cel: celID), in: url)
        let originalManifest = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let drawingBytes = try Data(contentsOf: oldDrawing)
        let animationBytes = try Data(contentsOf: oldAnimation)
        try FileManager.default.createDirectory(at: animationDestination, withIntermediateDirectories: true)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .skippedDamaged,
                       "the later directory at a file destination refuses the complete plan")
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), originalManifest,
                       "refusal leaves the manifest byte-for-byte unchanged")
        XCTAssertEqual(try Data(contentsOf: oldDrawing), drawingBytes,
                       "the earlier drawing remains byte-for-byte at its old address")
        XCTAssertFalse(FileManager.default.fileExists(atPath: drawingDestination.path),
                       "the earlier generated destination remains absent")
        XCTAssertEqual(try Data(contentsOf: oldAnimation), animationBytes,
                       "the animation remains byte-for-byte at its old address")
        XCTAssertEqual(try ProjectFileTree.entry(at: animationDestination), .directory,
                       "the conflicting directory remains owned by its original contents")
    }

    /// **The compare-and-swap, which is the one step in the migration that can destroy data.** A save
    /// landing a whole new package at this path while the sidecars were being moved leaves a manifest
    /// that is already in the new layout; writing our stale bytes over it would lose the artist's last
    /// edits.
    /// **The staleness has to come from the caller, or this test measures nothing.** The first
    /// version of it changed the manifest and then called `tidy` — but `tidy` reads the manifest at
    /// the instant it is called, so the compare-and-swap was handed two copies of the same value and
    /// the test passed with the guard deleted. A mutation of that one line is what found it. So the
    /// rewrite is driven directly, with bytes that really are the ones a pass read *before* the save
    /// landed.
    func testAManifestThatChangedUnderTheMigrationIsNotOverwritten() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let manifestURL = url.appendingPathComponent("manifest.json")

        // What the pass read when it started, and the rewrite it computed from it.
        let stale = try Data(contentsOf: manifestURL)
        let bare = try XCTUnwrap(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first)
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(
            celEntries(at: url).first { $0["vectorFileName"] is String }?["id"] as? String)))
        let rewrites = [(old: bare, new: ProjectPackageLayout.recordedName(for: .drawing, cel: celID))]

        // A save lands a whole new package at this path while the sidecars are being moved. Its
        // manifest is already in the new layout and carries edits the pass has never seen.
        var json = manifestJSON(at: url)
        json["name"] = "Renamed By A Save"
        let fresh = try JSONSerialization.data(withJSONObject: json)
        try fresh.write(to: manifestURL)
        XCTAssertNotEqual(fresh, stale,
                          "Setup: the save really did change the manifest under the migration")

        ProjectPackageLayout.rewriteManifest(at: manifestURL, in: url,
                                             originalBytes: stale, rewrites: rewrites)

        XCTAssertEqual(try Data(contentsOf: manifestURL), fresh,
                       "the save's manifest is byte-for-byte the one on disk — the migration abandons "
                       + "its rewrite rather than writing bytes it read before the save landed, which "
                       + "is the only step in this pass that can destroy the artist's last edits")
        XCTAssertEqual(manifestJSON(at: url)["name"] as? String, "Renamed By A Save",
                       "and the edit the save carried is still there")
    }

    /// The other direction, so the test above cannot pass by a rewrite that never does anything: with
    /// the bytes it was given still on disk, the surgery lands.
    func testTheRewriteCommitsWhenTheManifestIsStillTheOneThePassRead() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let manifestURL = url.appendingPathComponent("manifest.json")
        let cel = try XCTUnwrap(celEntries(at: url).first { $0["vectorFileName"] is String })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let bare = try XCTUnwrap(cel["vectorFileName"] as? String)
        let relative = ProjectPackageLayout.recordedName(for: .drawing, cel: celID)

        // Move the file as `tidy` would, so the rewritten manifest names something that is there.
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("drawings", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: url.appendingPathComponent("images", isDirectory: true).appendingPathComponent(bare),
            to: try ProjectPackageLayout.resolve(relative, in: url))

        ProjectPackageLayout.rewriteManifest(at: manifestURL, in: url,
                                             originalBytes: try Data(contentsOf: manifestURL),
                                             rewrites: [(old: bare, new: relative)])

        XCTAssertEqual(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first, relative,
                       "the manifest names the new address")
        assertInkSurvived(at: url, "a package whose manifest the rewrite committed")
    }

    /// A package the manifest cannot be read from is the repair pass's business, and `tidy` must not
    /// touch it — it has no title, no cel ids and no way to know what any file on disk is.
    func testTidySkipsADamagedPackageWithoutTouchingIt() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let before = names(in: "images", at: url)
        try Data("corrupted".utf8).write(to: url.appendingPathComponent("manifest.json"))

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .skippedDamaged,
                       "a package whose manifest will not decode is skipped")
        XCTAssertEqual(names(in: "images", at: url), before,
                       "and nothing under images/ moved")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "not even the destination directory is created")
    }

    /// The whole-library pass, which is what actually runs at launch.
    func testTheLaunchPassTidiesEveryProjectAndReportsWhatItDid() {
        let first = savedProject(named: "One")
        let second = savedProject(named: "Two")
        makeLegacyLayout(at: first)
        makeLegacyLayout(at: second)
        let alreadyTidy = savedProject(named: "Three")

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(Set(report.tidied), ["One.paintproj", "Two.paintproj"],
                       "both legacy packages were tidied, got \(report.tidied)")
        XCTAssertEqual(report.unchanged, 1, "and the one already in the new layout was left alone")
        XCTAssertEqual(report.skippedDamaged, 0, "nothing was damaged")
        XCTAssertGreaterThan(report.movedFiles, 0, "the pass reports how many sidecars it moved")
        XCTAssertTrue(report.duplicateProjectIDs.isEmpty,
                      "three distinct projects carry three distinct manifest ids")
        for url in [first, second, alreadyTidy] {
            XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                           "\(url.lastPathComponent) has no JSON under images/ afterwards")
            assertInkSurvived(at: url, url.lastPathComponent)
        }
    }

    /// The backstop the reviewers asked for: two packages sharing one manifest id make the gallery's
    /// `ForEach` draw two rows with one identity, and one of them may simply never appear. Nothing in
    /// this item can produce that shape — it renames no package directory — but the walk is already
    /// there and the check is one dictionary insert.
    func testTheLaunchPassNoticesTwoPackagesSharingOneManifestID() throws {
        let original = savedProject(named: "Original")
        let twin = ProjectBackupManager.projectsDirectory.appendingPathComponent("Twin.paintproj")
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: original, to: twin),
                      "Setup: the fork is modelled by cloning a package under a second name")

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(report.duplicateProjectIDs.count, 1,
                       "the pass names the id two packages share rather than letting the gallery "
                       + "silently drop one of the rows forever")
    }

    // MARK: - The resolver's probe order, stated directly

    /// **Probe the address the migration moves *from* first, and the address it moves *to* second.**
    /// That order is the whole race proof: `tidy` only ever moves old→new, `rename(2)` is atomic, so a
    /// miss at `images/` proves the move completed and the second probe hits. Asserted here as a
    /// property of the function, because every caller depends on it and none of them states it.
    func testTheResolverProbesTheOldAddressFirstThenTheNew() throws {
        let fm = FileManager.default
        let package = root.appendingPathComponent("Probe.paintproj", isDirectory: true)
        let cel = UUID()
        let bare = ProjectPackageLayout.legacyName(for: .drawing, cel: cel)
        let images = package.appendingPathComponent("images", isDirectory: true)
        let drawings = package.appendingPathComponent("drawings", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try fm.createDirectory(at: drawings, withIntermediateDirectories: true)

        // Neither address occupied: the answer is the *old* one, so a caller's "missing" diagnostics
        // name where a legacy manifest says the file should be.
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: bare, role: .drawing, cel: cel, in: package),
                       images.appendingPathComponent(bare),
                       "with the file nowhere, a bare moved name resolves to its old address")

        // Only the new address occupied — the post-migration, pre-manifest-rewrite state.
        let moved = try ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: cel), in: package)
        try Data("new".utf8).write(to: moved)
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: bare, role: .drawing, cel: cel, in: package),
                       moved, "a miss at images/ falls through to drawings/")

        // Both occupied — impossible from a rename, and the old one wins, which is what makes the
        // resolver agree with `tidy`'s refusal to touch either.
        try Data("old".utf8).write(to: images.appendingPathComponent(bare))
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: bare, role: .drawing, cel: cel, in: package),
                       images.appendingPathComponent(bare),
                       "the address the migration moves from is probed first")

        // A slashed name is package-relative and has no alternate at all.
        let slashed = ProjectPackageLayout.recordedName(for: .animation, cel: cel)
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: slashed, role: .animation, cel: cel, in: package),
                       try ProjectPackageLayout.resolve(slashed, in: package),
                       "a slashed name is taken at its word")

        // A video: the current address first, then the one an old package used, because nothing
        // migrates a clip — its name lives inside the payload, not the manifest.
        let clip = "scene.mp4"
        try Data("clip".utf8).write(to: images.appendingPathComponent(clip))
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: clip, role: .video, in: package),
                       images.appendingPathComponent(clip),
                       "a clip an older package left in images/ still resolves")
        let videos = package.appendingPathComponent("videos", isDirectory: true)
        try fm.createDirectory(at: videos, withIntermediateDirectories: true)
        try Data("clip".utf8).write(to: videos.appendingPathComponent(clip))
        XCTAssertEqual(try ProjectPackageLayout.existingURL(named: clip, role: .video, in: package),
                       videos.appendingPathComponent(clip),
                       "and videos/ wins once the clip is there, because that is the common case")
    }

    // MARK: - The stem a title produces

    /// The first-save naming defect, stated as the cases that used to reach the filesystem verbatim.
    func testTheStemNeverProducesAPathAFolderNameCannotBe() {
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "Boat/Race"), "Boat Race",
                       "a separator in a title used to create a real subfolder and file the project inside it")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "10:30 take"), "10 30 take",
                       "a colon is replaced for sanitizedFolderName's reason")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "...hidden"), "hidden",
                       "every leading dot is stripped, not just the first — one left behind is a "
                       + "folder invisible in Files, which is where the owner found this item")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "Scene."), "Scene",
                       "and a trailing dot goes too")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "   "), "Untitled",
                       "a title of nothing still has to name a folder")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "/"), "Untitled",
                       "and so does one that sanitises down to nothing")
    }

    /// **Truncation is by UTF-8 bytes, not by `Character` count**, which is the bound the filesystem
    /// actually enforces: sixty ZWJ emoji `Character`s are many hundreds of bytes, and the trash name
    /// appends about forty-five more to whatever this returns.
    func testTheStemIsBoundedInBytesAsWellAsInCharacters() {
        let long = String(repeating: "a", count: 400)
        let plain = ProjectPackageName.stem(forTitle: long)
        XCTAssertEqual(plain.count, ProjectPackageName.maximumStemCharacters,
                       "a plain long title is cut at the character cap")

        let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 60)
        let cut = ProjectPackageName.stem(forTitle: emoji)
        XCTAssertLessThanOrEqual(cut.utf8.count, ProjectPackageName.maximumStemBytes,
                                 "sixty family emoji are \(emoji.utf8.count) bytes, and the stem has "
                                 + "to fit a path component with room for Trash's own suffix")
        XCTAssertFalse(cut.isEmpty, "and it is not cut to nothing")
        XCTAssertEqual(cut, String(cut.prefix(cut.count)),
                       "the cut lands on a Character boundary, never mid-sequence")
    }

    /// The defect end to end: the title reaches the filesystem through `createNewProjectURL`, and it
    /// must not be able to name a directory outside the folder it was given.
    func testANewProjectsFirstSaveCannotCreateAStraySubfolder() {
        let url = ProjectStore.createNewProjectURL(name: "Boat/Race")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       ProjectBackupManager.projectsDirectory.standardizedFileURL,
                       "the package lands directly in Projects/, not inside a folder the title invented")
        XCTAssertEqual(url.lastPathComponent, "Boat Race.paintproj",
                       "and it is named for the sanitised title")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ProjectBackupManager.projectsDirectory.appendingPathComponent("Boat").path),
            "no stray 'Boat' directory is created — a project filed there could never be moved back, "
            + "because a rename never moves a project between folders")
    }
}
