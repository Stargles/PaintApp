import XCTest
import UIKit

/// **Every view that puts artwork on the canvas has to say how it is filtered when the canvas is
/// zoomed out.** Core Animation's default is `.linear` with no mipmap chain, which past about 2:1
/// degenerates to point sampling: it reads one texel per screen pixel, and ink thinner than the
/// sampling step is not faint, it is gone. MEASURED on the owner's iPad 9, Release, 2026-09-02
/// (BUGS.md's "A 16383² canvas draws nothing the artist can see", PERFORMANCE.md §9 item 2): a line
/// of the default 5-point brush, minified to fit zoom, leaves 800 pixels of ink at 2048² and
/// **zero** at 4096², 8192² and 12288²; box-filtered it survives at every size. The canvas opens at
/// `fitScale`, so that is the artist's starting view, and 4096² documents are affected today.
///
/// **This is a weak test and it is worth being explicit about why**, because a green run here is not
/// evidence that the artist can see their stroke:
///
/// - It reads *source text*, not pixels. It cannot see whether Core Animation actually builds the
///   mipmap chain, whether the chain helps at the ratios the artist works at, or what it costs.
///   Nothing headless can: the defect is in the render server, and every measurement behind it was
///   taken on a device.
/// - It knows which views are artwork only because this file says so. A new artwork view in a file
///   nobody listed here is invisible to it — which is why the last test refuses to let a *file*
///   grow a `UIImageView` without being classified, since that is the shape the regression takes.
/// - Only `ShapeOverlayView` is checked at runtime, because it is the one artwork view whose file is
///   compiled into this target; the rest reach the test as strings.
///
/// What it does catch is the regression it was written for: somebody adds a canvas image view and
/// forgets the filter, or a sweep "simplifies" one of these lines away.
final class CanvasLayerFilterLogicTests: XCTestCase {

    /// The files that hold canvas artwork views, and how many image views each of them builds. Every
    /// one of those image views must set `minificationFilter`, and every setting must be
    /// `.trilinear` — the count is the point, since an image view added without the line is exactly
    /// the regression.
    private static let artworkFiles: [(path: String, imageViews: Int)] = [
        ("PaintSoftware/Views/Canvas/LayerHostView.swift", 2),        // baked + fill tiers
        ("PaintSoftware/Views/Canvas/StrokeCanvasView.swift", 3),     // the layer's picture, the live scratch, the float
        ("PaintSoftware/Views/CanvasView.swift", 2),                  // the sandwich pair, the onion-skin pair
        ("PaintSoftware/Views/ShapeOverlayView.swift", 1),            // the live shape preview
        ("PaintSoftware/Views/FloatingPieceOverlayView.swift", 1)     // the lifted raster piece
    ]

    /// Files under `Views/` that build a `UIImageView` which is **not** canvas artwork, and so are
    /// deliberately outside the rule. Both are panel chrome: a thumbnail is authored at the size it
    /// is shown at, so nothing minifies it by the factors above.
    private static let nonArtworkImageViewFiles: Set<String> = [
        "LayerStackCell.swift", "TimelineTrackView.swift"
    ]

    // MARK: - The rule

    func testEveryArtworkImageViewSetsTheTrilinearMinificationFilter() throws {
        let root = try repositoryRoot()
        for (path, expected) in Self.artworkFiles {
            let source = try code(at: root.appendingPathComponent(path))
            let imageViews = source.filter { $0.text.contains("UIImageView()") }
            let settings = source.compactMap { line -> (Int, String)? in
                guard let value = Self.minificationValue(in: line.text) else { return nil }
                return (line.number, value)
            }

            XCTAssertEqual(imageViews.count, expected,
                           "\(path) builds \(imageViews.count) image views, not the \(expected) this "
                           + "test was written against. If that is a new artwork view it needs a "
                           + "`minificationFilter`; update the count here either way.")
            XCTAssertEqual(settings.count, expected, """
                \(path) sets `minificationFilter` \(settings.count) times for \(expected) image views.

                An artwork view without it runs Core Animation's default `.linear` with no mipmap \
                chain, and a default-width stroke seen at fit zoom is then not faint but absent — \
                MEASURED at 4096², 8192² and 12288². See `LayerHostView.init` for the reasoning and \
                PERFORMANCE.md §9 item 2 for the numbers.
                """)
            for (number, value) in settings {
                XCTAssertEqual(value, "trilinear",
                               "\(path):\(number) minifies artwork with `.\(value)`. Only "
                               + "`.trilinear` carries a mipmap chain, and the chain is the fix.")
            }
        }
    }

    /// **The one deliberate exception, pinned so a sweep does not tidy it into agreement.**
    /// `SelectionOverlayView`'s collar is not artwork — it is the diagnostic that shows the artist
    /// where their line has a gap — and its own comment argues that a bilinear smear over the very
    /// pixels they are hunting for defeats the point. It is `.nearest` at both ends on purpose.
    func testTheSelectionCollarKeepsItsNearestMinification() throws {
        let root = try repositoryRoot()
        let source = try code(at: root.appendingPathComponent("PaintSoftware/Views/SelectionOverlayView.swift"))
        let settings = source.compactMap { Self.minificationValue(in: $0.text) }
        XCTAssertEqual(settings, ["nearest"],
                       "The collar is chrome, not ink: it is the one minification in the app that "
                       + "is deliberately unfiltered, and there is exactly one of it")
    }

    /// The half of the rule the list above cannot express: a *new* file that shows artwork. It fails
    /// on any file under `Views/` that builds a `UIImageView` and is in neither list, which forces
    /// the question "is this canvas artwork?" to be answered by whoever adds it rather than
    /// discovered later on a device.
    func testNoUnclassifiedViewFileBuildsAnImageView() throws {
        let views = try repositoryRoot().appendingPathComponent("PaintSoftware/Views", isDirectory: true)
        let known = Set(Self.artworkFiles.map { ($0.path as NSString).lastPathComponent })
            .union(Self.nonArtworkImageViewFiles)

        var unclassified: [String] = []
        for file in try swiftFiles(under: views) where !known.contains(file.lastPathComponent) {
            let source = try code(at: file)
            guard source.contains(where: { $0.text.contains("UIImageView()") }) else { continue }
            unclassified.append(file.lastPathComponent)
        }

        XCTAssertEqual(unclassified.sorted(), [], """
            \(unclassified.sorted().joined(separator: ", ")) builds a `UIImageView` and is in \
            neither list in `CanvasLayerFilterLogicTests`.

            If it shows artwork on the canvas it needs `minificationFilter = .trilinear` and a row \
            in `artworkFiles`; if it is panel chrome authored at the size it is displayed at, add it \
            to `nonArtworkImageViewFiles` and it is exempt. The one answer that is wrong is leaving \
            it undecided — that is how the defect this file exists for reached a shipped build.
            """)
    }

    // MARK: - Runtime, for the one file this target compiles

    /// The source scan proves a line exists; this proves the property lands on a real layer. Only
    /// `ShapeOverlayView` can be reached — the layer hosts and `CanvasView` are not compiled into
    /// this target and pulling them in would drag the whole editor with them.
    func testTheShapePreviewLayerReallyCarriesTheFilter() {
        let overlay = ShapeOverlayView(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
        let previews = overlay.subviews.compactMap { $0 as? UIImageView }
        XCTAssertEqual(previews.count, 1, "The shape overlay shows its preview through one image view")
        XCTAssertEqual(previews.first?.layer.minificationFilter, .trilinear)
        XCTAssertEqual(previews.first?.layer.magnificationFilter, .nearest,
                       "Untouched — magnified artwork stays crisp, which is a separate contract")
    }

    // MARK: - The assertion that stops the scans passing because they read nothing

    /// A path typo, a moved directory or a sandbox that silently returns an empty enumerator all
    /// produce an empty offender list, which is indistinguishable from a clean tree. Same guard, and
    /// same reasoning, as `CanvasPresentationLogicTests.testTheSourceScanIsActuallyReadingTheApp`.
    func testTheSourceScanIsActuallyReadingTheApp() throws {
        let root = try repositoryRoot()
        for (path, _) in Self.artworkFiles {
            let source = try code(at: root.appendingPathComponent(path))
            XCTAssertGreaterThan(source.count, 20, "\(path) came back with \(source.count) code lines")
        }
        let views = try swiftFiles(under: root.appendingPathComponent("PaintSoftware/Views",
                                                                     isDirectory: true))
        XCTAssertGreaterThan(views.count, 20,
                             "`Views/` holds far more than 20 Swift files; \(views.count) means the "
                             + "walk is not reaching them")
        // And that the needle is findable at all — a regex that matches nothing would pass every
        // assertion above for the wrong reason.
        XCTAssertEqual(Self.minificationValue(in: "        view.layer.minificationFilter = .trilinear"),
                       "trilinear")
        XCTAssertNil(Self.minificationValue(in: "let magnificationFilter = CALayerContentsFilter.nearest"))
    }

    // MARK: - Helpers

    private static func minificationValue(in line: String) -> String? {
        guard let range = line.range(of: "minificationFilter") else { return nil }
        let tail = line[range.upperBound...].drop { $0 == " " }
        guard tail.first == "=" else { return nil }
        let value = tail.dropFirst().drop { $0 == " " }
        guard value.first == "." else { return nil }
        return String(value.dropFirst().prefix { $0.isLetter })
    }

    /// The file's lines with the comments dropped — the strings this file looks for appear in doc
    /// comments that are *documenting the rule*, and a checker that flagged its own explanation
    /// would be uninhabitable.
    private func code(at url: URL) throws -> [(number: Int, text: String)] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (number: $0.offset + 1, text: String($0.element)) }
            .filter {
                let trimmed = $0.text.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*")
            }
    }

    /// The repo root, from this file's own compile-time path: `<root>/PaintSoftwareUITests/<this>.swift`.
    /// Skipped, loudly, when the tree is not there — a run on a physical device, or a build carried
    /// to another machine. That is the one case where "cannot read it" is not a finding.
    private func repositoryRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PaintSoftwareUITests
            .deletingLastPathComponent()   // the repo root
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("PaintSoftware").path) else {
            throw XCTSkip("""
                The source tree is not readable from here (\(root.path)). That is expected on a \
                physical device or a build carried to another machine, and nowhere else — on the \
                simulator this test reads the host filesystem.
                """)
        }
        return root
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate \(directory.path)")
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
