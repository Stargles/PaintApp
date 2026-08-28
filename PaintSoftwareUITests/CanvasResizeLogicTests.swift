import XCTest
import UIKit

/// Pure-logic tests for CANVAS_RESIZE.md **stage 1** — "Resize Canvas", crop/expand only.
///
/// Headless, like `CanvasManagerTestSupport`'s other clients: `CanvasManager` and the rest of the
/// app's non-view sources are compiled a second time straight into this target, so `resizeCanvas`,
/// `setCanvasPadding` and `ProjectStore` are called for real rather than simulated.
///
/// The four obligations §4 sets for this stage, and what each is actually protecting:
///
///  1. **The map.** `M` at `k == 1` is a whole-point translation, and out-and-back is the identity.
///     Whole points because a bitmap drawn at a half-point offset is filtered, and a crop/expand
///     that filtered would be a lossy operation pretending not to be.
///  2. **The per-tier walk.** A document of N layers × M cels comes out with *every* tier at the new
///     size and no tier missed. This is the one that catches a real regression: PERFORMANCE.md item
///     14 records that a resize which handles the active cel and forgets the other 999 is a
///     data-loss bug, and §1's table is long enough that a tier is easy to drop.
///  3. **The two fixes.** Guides transformed and `copiedCel` cleared — §0's "two existing defects on
///     this path", which `setCanvasPadding` has had all along and which stage 1 fixes rather than
///     inherits.
///  4. **A round trip through `ProjectStore`**, proving the manifest header and every buffer agree.
///     §0 names the trap this closes: `decodeCel` builds every texture at the manifest's canvas size
///     and `setContents` stretches a mismatched PNG to fit, aspect and all — so a header that
///     disagreed with the buffers would look like a crop before the save and a non-uniform stretch
///     after the reload.
@MainActor
final class CanvasResizeLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvas-resize-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - 1. The map

    /// At `k == 1` the map is a translation and nothing else: unit scale, whole-point offset, and a
    /// transform whose linear part is the identity.
    ///
    /// The odd cases are the point. An even difference lands on a whole point by itself and would
    /// pass with no rounding at all; `65 → 100` is where `.rounded()` earns its keep.
    func testTheCropExpandMapIsAWholePointTranslation() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 64, height: 64), CGSize(width: 128, height: 128)),
            (CGSize(width: 65, height: 100), CGSize(width: 100, height: 65)),
            (CGSize(width: 2048, height: 1024), CGSize(width: 999, height: 3001)),
            (CGSize(width: 7, height: 7), CGSize(width: 8, height: 8)),
        ]
        for (old, new) in cases {
            let map = CanvasResizeMap(from: old, to: new, scaleContent: false)
            XCTAssertEqual(map.scale, 1, "crop/expand never scales — \(old) → \(new)")
            XCTAssertEqual(map.offset.x, map.offset.x.rounded(), accuracy: 0,
                           "a fractional x offset would filter the bitmap — \(old) → \(new)")
            XCTAssertEqual(map.offset.y, map.offset.y.rounded(), accuracy: 0,
                           "a fractional y offset would filter the bitmap — \(old) → \(new)")

            let t = map.transform
            XCTAssertEqual(t.a, 1, accuracy: 0); XCTAssertEqual(t.b, 0, accuracy: 0)
            XCTAssertEqual(t.c, 0, accuracy: 0); XCTAssertEqual(t.d, 1, accuracy: 0)
            XCTAssertEqual(t.tx, map.offset.x, accuracy: 0)
            XCTAssertEqual(t.ty, map.offset.y, accuracy: 0)

            // The placement rect is the source's own size, which is what makes the draw a copy
            // rather than a resample.
            XCTAssertEqual(map.contentRect.size, old, "\(old) → \(new)")
            XCTAssertEqual(map.contentRect.origin, map.offset, "\(old) → \(new)")

            // Centred: the slack is split evenly, to within the whole point it was rounded onto.
            XCTAssertLessThanOrEqual(abs(map.offset.x - (new.width - old.width) / 2), 0.5, "\(old) → \(new)")
            XCTAssertLessThanOrEqual(abs(map.offset.y - (new.height - old.height) / 2), 0.5, "\(old) → \(new)")
        }
    }

    /// Out and back is **exactly** the identity, including when the difference is odd.
    ///
    /// `Double.rounded()` rounds half away from zero, which is symmetric about zero — so
    /// `((Ow − Nw)/2).rounded() == −((Nw − Ow)/2).rounded()` even at `±1.5`. That symmetry is the
    /// whole reason the crop/expand map is reversible, and it is not a property of every rounding
    /// rule: `.rounded(.down)` would drift by a point per round trip.
    func testCropExpandOutAndBackIsExactlyTheIdentity() {
        let sizes: [CGSize] = [
            CGSize(width: 64, height: 64), CGSize(width: 65, height: 101),
            CGSize(width: 2048, height: 1024), CGSize(width: 1, height: 1),
        ]
        for old in sizes {
            for new in sizes where new != old {
                let out = CanvasResizeMap(from: old, to: new, scaleContent: false)
                let back = out.inverse
                XCTAssertEqual(back.newSize, old, "the inverse lands back on the old extent")
                XCTAssertEqual(out.offset.x + back.offset.x, 0, accuracy: 0,
                               "out-and-back must cancel exactly — \(old) → \(new)")
                XCTAssertEqual(out.offset.y + back.offset.y, 0, accuracy: 0,
                               "out-and-back must cancel exactly — \(old) → \(new)")

                let probe = CGPoint(x: 13, y: 29)
                let returned = back.apply(out.apply(probe))
                XCTAssertEqual(returned.x, probe.x, accuracy: 0, "\(old) → \(new)")
                XCTAssertEqual(returned.y, probe.y, accuracy: 0, "\(old) → \(new)")
            }
        }
    }

    /// The same identity on real pixels rather than on the arithmetic: grow the canvas, shrink it
    /// back, and the bytes are the ones that went in.
    ///
    /// This is the assertion that would fail if the offset were ever fractional — `draw(in:)` would
    /// filter on the way out and again on the way back, and a hard edge would come home soft.
    func testGrowingThenShrinkingReturnsThePixelsUnchanged() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 8, y: 12, width: 20, height: 16)))
        let before = try XCTUnwrap(manager.layers[0].cels[0].bakedImage?.cgImage)
        let beforeBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(before))

        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 129, height: 91)))
        XCTAssertTrue(manager.resizeCanvas(to: CanvasFixture.canvasSize))

        XCTAssertEqual(manager.canvasSize, CanvasFixture.canvasSize)
        let after = try XCTUnwrap(manager.layers[0].cels[0].bakedImage?.cgImage)
        XCTAssertEqual(CanvasFixture.rgbaBytes(after), beforeBytes,
                       "a whole-point crop/expand out and back must be byte-identical")
    }

    // MARK: - 2. The per-tier walk

    /// **Every tier of every cel of every layer**, with nothing skipped and nothing left at the old
    /// extent. §1's rule 7: no partial application, no "active cel only", no deferral.
    func testEveryTierOfEveryCelOfEveryLayerLandsAtTheNewSize() {
        let manager = Self.documentWithEveryTierPopulated()
        let oldSize = CanvasFixture.canvasSize
        let newSize = CGSize(width: 100, height: 140)

        // **The fixture has to be worth walking, or every assertion below is vacuous.** Each of the
        // four tiers is checked for separately rather than counted in total: a total would still pass
        // if the fixture lost its only `fillImage` and grew a second `bakedImage`, and it is precisely
        // a *missed tier* that this test exists to catch.
        let cels = manager.layers.flatMap(\.cels)
        for cel in cels { XCTAssertEqual(cel.raster.size, oldSize, "setup: every cel starts at the old extent") }
        XCTAssertTrue(cels.contains { $0.raster.hasContent }, "setup: a raster tier with real pixels")
        XCTAssertTrue(cels.contains { $0.fillImage != nil }, "setup: a fillImage tier")
        XCTAssertTrue(cels.contains { $0.bakedImage != nil }, "setup: a bakedImage tier")
        XCTAssertTrue(cels.contains { ($0.vector?.elements.isEmpty == false) }, "setup: a vector tier with geometry")

        XCTAssertTrue(manager.resizeCanvas(to: newSize))

        XCTAssertEqual(manager.canvasSize, newSize)
        XCTAssertEqual(manager.layers.count, 3, "a resize adds and removes no layers")
        var celsSeen = 0
        for (layerIndex, layer) in manager.layers.enumerated() {
            XCTAssertFalse(layer.cels.isEmpty, "layer \(layerIndex) kept its cels")
            for (celIndex, cel) in layer.cels.enumerated() {
                celsSeen += 1
                let where_ = "layer \(layerIndex) cel \(celIndex)"
                XCTAssertEqual(cel.raster.size, newSize, "raster tier, \(where_)")
                if let fill = cel.fillImage {
                    XCTAssertEqual(fill.size, newSize, "fillImage tier, \(where_)")
                }
                if let baked = cel.bakedImage {
                    XCTAssertEqual(baked.size, newSize, "bakedImage tier, \(where_)")
                }
                if let vector = cel.vector {
                    XCTAssertEqual(vector.size, newSize, "vector tier, \(where_)")
                    XCTAssertTrue(vector.transform.isIdentity,
                                  "the shift bakes into the geometry; a cel transform is what clipped later ink — \(where_)")
                }
                XCTAssertNil(cel.thumbnail,
                             "a thumbnail of the old extent is stale; it is nil'd for the deferred backfill — \(where_)")
            }
        }
        XCTAssertEqual(celsSeen, 5, "every cel in the document was visited")
    }

    /// The vector tier moves with the raster one, to the same point. Two expressions of one geometry
    /// are how they come to disagree (§2), so this checks they agree on an actual document.
    func testTheVectorTierLandsWhereTheRasterTierLands() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        canvas.addStroke(VectorStroke(brush: manager.selectedBrush,
                                      color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                      size: 8, opacity: 1,
                                      samples: [VectorSample(x: 10, y: 12, pressure: 1),
                                                VectorSample(x: 30, y: 34, pressure: 1)]))

        let newSize = CGSize(width: 128, height: 128)
        let expected = CanvasResizeMap(from: CanvasFixture.canvasSize, to: newSize, scaleContent: false)
        XCTAssertTrue(manager.resizeCanvas(to: newSize))

        let moved = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements.compactMap { element -> VectorStroke? in
            if case .stroke(let s) = element { return s } else { return nil }
        }.first)
        let first = expected.apply(CGPoint(x: 10, y: 12))
        XCTAssertEqual(moved.samples[0].x, first.x, accuracy: 1e-9)
        XCTAssertEqual(moved.samples[0].y, first.y, accuracy: 1e-9)
        XCTAssertEqual(moved.size, 8, accuracy: 1e-9, "crop/expand re-stamps nothing, so the width is untouched")
    }

    /// Interpolation lattices and the strokes embedded in them travel with the artwork.
    ///
    /// A lattice's `restOrigin`/`vertices` are canvas points; a `LocalEdit`'s stroke is in that
    /// lattice's *rest* space, so it moves by the same `d` and **only once** — mapping it again in
    /// canvas space is §1's named trap. The topology (`cols`/`rows`/`activeCells`) and the cell size
    /// are not geometry at `k == 1` and must not move.
    func testInterpolationLatticesAndTheirLocalEditsTravelTogether() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let groupID = UUID()
        let lattice = Lattice(cols: 2, rows: 2, restOrigin: CGPoint(x: 10, y: 14),
                              restCellSize: 8, activeCells: [0, 3])
        let edit = LocalEdit(stroke: VectorStroke(brush: manager.selectedBrush,
                                                 color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                                                 size: 5, opacity: 1,
                                                 samples: [VectorSample(x: 16, y: 20, pressure: 1)]),
                             groupID: groupID)
        manager.layers[0].cels[0].interpolation = InterpolationRecipe(
            t: 0.5, groups: [MotionGroupBinding(groupID: groupID, lattices: [lattice])], localEdits: [edit])

        let newSize = CGSize(width: 128, height: 128)
        let map = CanvasResizeMap(from: CanvasFixture.canvasSize, to: newSize, scaleContent: false)
        XCTAssertTrue(manager.resizeCanvas(to: newSize))

        let recipe = try XCTUnwrap(manager.layers[0].cels[0].interpolation)
        let moved = try XCTUnwrap(recipe.groups.first?.lattices.first)
        XCTAssertEqual(moved.restOrigin, map.apply(CGPoint(x: 10, y: 14)))
        XCTAssertEqual(moved.vertices[0], map.apply(lattice.vertices[0]))
        XCTAssertEqual(moved.vertices.last, map.apply(lattice.vertices[lattice.vertices.count - 1]))
        XCTAssertEqual(moved.restCellSize, 8, "cell size is a length, and a translation is not a scale")
        XCTAssertEqual(moved.cols, 2); XCTAssertEqual(moved.rows, 2)
        XCTAssertEqual(moved.activeCells, [0, 3], "cell topology is not geometry")

        let movedEdit = try XCTUnwrap(recipe.localEdits.first)
        let expected = map.apply(CGPoint(x: 16, y: 20))
        XCTAssertEqual(movedEdit.stroke.samples[0].x, expected.x, accuracy: 1e-9,
                       "the local edit rides the lattice — once, not twice")
        XCTAssertEqual(movedEdit.stroke.samples[0].y, expected.y, accuracy: 1e-9)
        XCTAssertEqual(recipe.t, 0.5, accuracy: 1e-12, "normalised time is not geometry")
    }

    // MARK: - 3. The two fixes

    /// **Guides are document-level canvas coordinates and were left behind by every resize until
    /// stage 1.** `TimedSample.x/y` are absolute canvas points; growing the padding moved the artwork
    /// and not the guide drawn over it. `pressure` and `time` are unit-free and stay put.
    func testGuidesTravelWithTheArtwork() throws {
        for growPadding in [false, true] {
            let manager = CanvasFixture.manager(layerCount: 1)
            let celRef = CelRef(layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)
            manager.guideStrokes = [GuideStroke(
                samples: [TimedSample(x: 10, y: 12, pressure: 0.5, time: 0),
                          TimedSample(x: 30, y: 34, pressure: 0.75, time: 0.25)],
                interval: KeyframeInterval(start: celRef, end: celRef))]

            let oldSize = CanvasFixture.canvasSize
            let newSize: CGSize
            if growPadding {
                manager.setCanvasPadding(6)
                newSize = CGSize(width: oldSize.width + 12, height: oldSize.height + 12)
            } else {
                newSize = CGSize(width: 100, height: 40)
                XCTAssertTrue(manager.resizeCanvas(to: newSize))
            }
            XCTAssertEqual(manager.canvasSize, newSize, "setup: growPadding=\(growPadding)")

            let map = CanvasResizeMap(from: oldSize, to: newSize, scaleContent: false)
            let guide = try XCTUnwrap(manager.guideStrokes.first)
            let first = map.apply(CGPoint(x: 10, y: 12))
            XCTAssertEqual(guide.samples[0].x, first.x, accuracy: 1e-9, "growPadding=\(growPadding)")
            XCTAssertEqual(guide.samples[0].y, first.y, accuracy: 1e-9, "growPadding=\(growPadding)")
            let second = map.apply(CGPoint(x: 30, y: 34))
            XCTAssertEqual(guide.samples[1].x, second.x, accuracy: 1e-9, "growPadding=\(growPadding)")
            XCTAssertEqual(guide.samples[1].y, second.y, accuracy: 1e-9, "growPadding=\(growPadding)")
            XCTAssertEqual(guide.samples[1].pressure, 0.75, accuracy: 1e-12, "pressure is unit-free")
            XCTAssertEqual(guide.samples[1].time, 0.25, accuracy: 1e-12, "time is unit-free")
        }
    }

    /// **The timeline clipboard holds canvas-sized buffers and nothing cleared it.** `pasteCel` does
    /// no size check, so a copy-resize-paste installed a cel whose `RasterLayerTexture.size` was the
    /// *old* canvas's — a cel the compositor and the save would then disagree about. Both entry
    /// points clear it, since both change the extent.
    func testTheTimelineClipboardIsClearedByEveryResize() {
        for viaPadding in [false, true] {
            let manager = CanvasFixture.manager(layerCount: 1)
            manager.copyCel(layerIndex: 0, celIndex: 0)
            XCTAssertNotNil(manager.copiedCel, "setup: something must be on the clipboard")

            if viaPadding {
                manager.setCanvasPadding(6)
            } else {
                XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 100, height: 40)))
            }

            XCTAssertNil(manager.copiedCel,
                         "a clipboard payload at the old extent must not survive a resize — viaPadding=\(viaPadding)")
        }
    }

    // MARK: - The artwork rect is what the artist types (§5 rule 9)

    /// **The typed width and height mean the artwork rect; `canvasPadding` is preserved literally in
    /// canvas points and never scales** (§5 rule 9, owner-confirmed 2026-08-28). So the buffer that
    /// comes out is `typed + 2 × padding`, and the padding slider's own number has not moved.
    ///
    /// Getting this backwards makes the two Actions controls fight over one number: typing 100 into a
    /// document with 6 pt of padding would silently give 88 pt of artwork.
    func testTheTypedSizeIsTheArtworkRectAndPaddingSurvivesLiterally() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.setCanvasPadding(6)
        XCTAssertEqual(manager.canvasPadding, 6)
        XCTAssertEqual(manager.artworkSize, CanvasFixture.canvasSize, "setup: padding grows the buffer, not the artwork")

        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 100, height: 40)))

        XCTAssertEqual(manager.artworkSize, CGSize(width: 100, height: 40),
                       "the artist typed the artwork rect")
        XCTAssertEqual(manager.canvasSize, CGSize(width: 112, height: 52),
                       "the buffer is the artwork plus the margin on every side")
        XCTAssertEqual(manager.canvasPadding, 6, "padding is a working margin, not artwork — it never scales")
        XCTAssertEqual(manager.layers[0].cels[0].raster.size, CGSize(width: 112, height: 52),
                       "every buffer is the buffer extent, padding included")
    }

    /// The accepted range is the canvas ceiling **inset by the padding**, because `canvasSize`
    /// includes the margin and `maxCanvasExtent` bounds `canvasSize`. `CanvasSizePickerView` needs no
    /// such inset — it creates documents with no padding — which is why this could not simply reuse
    /// its bound directly.
    func testTheAcceptedArtworkRangeIsInsetByThePaddingAndClampsRatherThanRefuses() {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertEqual(manager.resizableArtworkExtentRange.upperBound, CanvasManager.maxCanvasExtent,
                       "with no padding the artwork bound is the canvas bound")

        manager.canvasPadding = 100
        XCTAssertEqual(manager.resizableArtworkExtentRange.upperBound, CanvasManager.maxCanvasExtent - 200)

        manager.canvasPadding = 0
        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 0, height: 40)))
        XCTAssertEqual(manager.artworkSize?.width, 1, "a zero-width canvas clamps to the floor rather than throwing")
    }

    /// `scaleContent: true` is stage 2 and is **refused**, not quietly crop/expanded. A caller that
    /// asked for a letterbox and got a crop has lost artwork and been told it succeeded.
    func testTheScaleModeIsRefusedRatherThanQuietlyCropping() {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertFalse(manager.resizeCanvas(to: CGSize(width: 128, height: 128), scaleContent: true))
        XCTAssertEqual(manager.canvasSize, CanvasFixture.canvasSize, "nothing moved")
    }

    /// A resize is still not undoable, and still says so by clearing the stack — §4's "exactly
    /// today's contract with an arbitrary rectangle instead of a symmetric margin". Every entry below
    /// it holds canvas-coordinate pixel patches at the old dimensions, so restoring one would put
    /// pixels of the wrong size in the wrong place. Stage 3 is what gives this a single inverse step.
    func testAResizeStillClearsTheHistoryStack() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addLayer()
        XCTAssertTrue(manager.canUndo, "setup: adding a layer is an undoable structure change")

        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 100, height: 40)))
        XCTAssertFalse(manager.canUndo, "the stack below a resize is unrestorable and is cleared")
    }

    // MARK: - 4. The manifest and every buffer agree

    /// **The header and every buffer move together, or not at all** (§0's trap). `decodeCel` builds
    /// every texture as `RasterLayerTexture.load(from:size: canvasSize)` and `setContents` draws the
    /// decoded PNG into `CGRect(origin: .zero, size: size)` — so a PNG whose dimensions disagreed
    /// with `canvasWidth/Height` would be *stretched to fit, aspect and all*, silently. A resize that
    /// changed only the header would therefore look like a crop before the save and like a
    /// non-uniform stretch after the reload.
    ///
    /// The fixture is deliberately non-square in both directions across the resize, so a swapped or
    /// stretched axis cannot pass.
    func testASaveAndReloadFindsTheManifestAndEveryBufferAtTheNewSize() throws {
        let manager = Self.documentWithEveryTierPopulated()
        let newSize = CGSize(width: 100, height: 140)
        XCTAssertTrue(manager.resizeCanvas(to: newSize))

        let url = ProjectStore.createNewProjectURL(name: "Resize Round Trip")
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        let reloaded = try XCTUnwrap(ProjectStore.load(from: url), "the package should load")
        XCTAssertEqual(reloaded.canvasSize, newSize, "the manifest header carries the new extent")
        XCTAssertEqual(reloaded.layers.count, manager.layers.count)

        for (layerIndex, layer) in reloaded.layers.enumerated() {
            XCTAssertFalse(layer.cels.isEmpty, "layer \(layerIndex) survived the round trip")
            for (celIndex, cel) in layer.cels.enumerated() {
                let where_ = "reloaded layer \(layerIndex) cel \(celIndex)"
                XCTAssertEqual(cel.raster.size, newSize, "raster tier, \(where_)")
                if let fill = cel.fillImage { XCTAssertEqual(fill.size, newSize, "fillImage tier, \(where_)") }
                if let baked = cel.bakedImage { XCTAssertEqual(baked.size, newSize, "bakedImage tier, \(where_)") }
                if let vector = cel.vector { XCTAssertEqual(vector.size, newSize, "vector tier, \(where_)") }
            }
        }
    }

    // MARK: - Fixtures

    /// Three layers — two raster, one vector — five cels between them, with `fillImage`,
    /// `bakedImage`, real stamped raster pixels and real vector geometry all present, so the per-tier
    /// walk has something of every kind to miss.
    private static func documentWithEveryTierPopulated() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        let size = CanvasFixture.canvasSize

        for layerIndex in 0..<2 {
            let raster = manager.layers[layerIndex].cels[0].raster
            raster.beginStroke()
            raster.stampCircle(at: CGPoint(x: 20 + layerIndex * 8, y: 24), radius: 6,
                               color: .red, alpha: 1, hardness: 1)
            raster.endStroke()
        }
        manager.layers[0].cels[0].fillImage =
            CanvasFixture.solidImage(.green, rect: CGRect(x: 4, y: 4, width: 16, height: 16), size: size)
        manager.layers[0].cels[0].bakedImage =
            CanvasFixture.solidImage(.blue, rect: CGRect(x: 24, y: 8, width: 12, height: 20), size: size)

        // A second cel on layer 0, so the per-cel loop runs more than once per layer, and a third on
        // layer 1 with its own baked content.
        _ = manager.addCel(layerIndex: 0, startFrame: 12, frameCount: 2)
        _ = manager.addCel(layerIndex: 1, startFrame: 12, frameCount: 2)
        manager.layers[1].cels[1].bakedImage =
            CanvasFixture.solidImage(.yellow, rect: CGRect(x: 2, y: 30, width: 10, height: 10), size: size)

        manager.addVectorLayer()
        manager.layers[2].cels[0].vector?.addStroke(
            VectorStroke(brush: manager.selectedBrush,
                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                         size: 8, opacity: 1,
                         samples: [VectorSample(x: 10, y: 10, pressure: 1),
                                   VectorSample(x: 40, y: 40, pressure: 1)]))
        return manager
    }
}
