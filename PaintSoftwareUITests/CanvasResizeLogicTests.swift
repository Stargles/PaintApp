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
            let map = CanvasResizeMap(from: old, to: new, mode: .cropExpand)
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
                let out = CanvasResizeMap(from: old, to: new, mode: .cropExpand)
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
        let expected = CanvasResizeMap(from: CanvasFixture.canvasSize, to: newSize, mode: .cropExpand)
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
        let map = CanvasResizeMap(from: CanvasFixture.canvasSize, to: newSize, mode: .cropExpand)
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

            let map = CanvasResizeMap(from: oldSize, to: newSize, mode: .cropExpand)
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

    /// Crop/expand stays the default, so a caller that says nothing gets the non-destructive mode —
    /// §5 rule 1. Stage 1 refused `scaleContent: true` outright; stage 2 accepts it, and the guard
    /// that used to make the refusal safe is now the default argument that makes the *choice*
    /// explicit at every site that wants the other one.
    func testCropExpandIsWhatACallerGetsWithoutAsking() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let canvas = try! XCTUnwrap(manager.layers[1].cels[0].vector)
        canvas.addStroke(Self.stroke(at: [CGPoint(x: 10, y: 12)], size: 8, brush: manager.selectedBrush))

        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 128, height: 128)))
        let moved = try! XCTUnwrap(manager.layers[1].cels[0].vector?.strokes.first)
        XCTAssertEqual(moved.size, 8, accuracy: 0, "the default mode re-stamps nothing")
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

    // MARK: - Stage 2, part 1: §2's two verified identities, as assertions on the real types
    //
    // Both were established in a scratch `swiftc` file while §2 was being written, and a scratch file
    // is not a regression test: it proved the arithmetic on the day and pins nothing about the code
    // that shipped. These two are the same claims made against `CanvasResizeMap` and
    // `VectorCanvas.resized(to:placing:)` themselves.

    /// **§2's first identity.** `M` maps `p` to `k·p + d`, and `.scaledBy` *after* `translationX:` is
    /// the spelling that means that.
    ///
    /// The order is the whole point and it is invisible by inspection: the other spelling —
    /// `CGAffineTransform(scaleX:y:).translatedBy(x:y:)` — reads identically at the call site and
    /// gives `k·(p + d)`. So this asserts the hand form matches *and* that the wrong composition
    /// differs, on a case where `k != 1` and `d != 0`; without the second half the test passes
    /// against either spelling on every case where one of them happens to be trivial.
    func testTheMapIsScaleThenTranslateAndNotTheOtherWayRound() {
        let probes = [CGPoint(x: 0, y: 0), CGPoint(x: 13, y: 29), CGPoint(x: 63.5, y: 2.25)]
        var sawADistinguishingCase = false
        for (old, new, mode) in Self.scalingResizes {
            let map = CanvasResizeMap(from: old, to: new, mode: mode)
            for p in probes {
                let hand = CGPoint(x: map.scale * p.x + map.offset.x, y: map.scale * p.y + map.offset.y)
                let matrix = map.apply(p)
                XCTAssertEqual(matrix.x, hand.x, accuracy: 1e-12, "\(old) → \(new) \(mode) at \(p)")
                XCTAssertEqual(matrix.y, hand.y, accuracy: 1e-12, "\(old) → \(new) \(mode) at \(p)")

                let reversed = CGAffineTransform(scaleX: map.scale, y: map.scale)
                    .translatedBy(x: map.offset.x, y: map.offset.y)
                let wrong = p.applying(reversed)
                if abs(wrong.x - matrix.x) > 1e-6 || abs(wrong.y - matrix.y) > 1e-6 {
                    sawADistinguishingCase = true
                }
            }
        }
        XCTAssertTrue(sawADistinguishingCase, """
            PREMISE: every case tried had `k == 1` or `d == .zero`, where scale-then-translate and \
            translate-then-scale agree — so the assertions above would pass against the wrong \
            spelling and prove nothing about the order.
            """)
    }

    /// **§2's second identity: the composition with an existing layer transform.** 324 cases —
    /// `k_T ∈ {0.31, 1, 2.7}` × `θ ∈ {0°, 17°, 90°, 213°}` × three translations × three resizes ×
    /// three probe points, the same grid §2 measured on, where it recorded a worst deviation of
    /// 1.8e-12 pt.
    ///
    /// **Two forms are pinned against each other, and neither is redundant.** §2 states the closed
    /// form as *"scale the elements by `k`, replace `_transform`'s translation with
    /// `(k·tx + dx, k·ty + dy)`, leave `a, b, c, d` untouched"*. `VectorCanvas.resized(to:placing:)`
    /// does something stronger — it bakes `_transform ∘ placement` into the elements and hands back an
    /// **identity** transform, since TODO item (12) stage 3 left the app with no producer of a
    /// non-identity cel transform. Those are the same rendered point and different stored bytes, so
    /// this asserts both land on `M(T(p))`: the document's stated derivation stays honest, and the
    /// shipped primitive is checked against it rather than against itself.
    func testTheCompositionWithALayerTransformIsSection2sClosedForm() throws {
        let translations = [CGPoint(x: 0, y: 0), CGPoint(x: 12, y: -7), CGPoint(x: -33.5, y: 41)]
        let probes = [CGPoint(x: 0, y: 0), CGPoint(x: 13, y: 29), CGPoint(x: 63.5, y: 2.25)]
        var cases = 0
        var worst: CGFloat = 0
        for kT in [0.31, 1.0, 2.7] as [CGFloat] {
            for theta in [0.0, 17.0, 90.0, 213.0].map({ $0 * .pi / 180 }) as [CGFloat] {
                for tT in translations {
                    let T = CGAffineTransform(translationX: tT.x, y: tT.y)
                        .rotated(by: theta).scaledBy(x: kT, y: kT)
                    for (old, new, mode) in Self.scalingResizes {
                        let map = CanvasResizeMap(from: old, to: new, mode: mode)
                        for p in probes {
                            cases += 1
                            let expected = p.applying(T).applying(map.transform)

                            // The shipped primitive: bake everything, hand back identity.
                            let canvas = VectorCanvas(size: old,
                                                      elements: [.stroke(Self.stroke(at: [p], size: 8))],
                                                      transform: T)
                            let out = canvas.resized(to: new, placing: map.contentRect)
                            XCTAssertTrue(out.transform.isIdentity,
                                          "the shift bakes into the geometry — \(old) → \(new) \(mode)")
                            let baked = try XCTUnwrap(out.strokes.first).samples[0]
                            worst = max(worst, abs(baked.x - expected.x))
                            worst = max(worst, abs(baked.y - expected.y))

                            // §2's closed form: elements at `k·L`, `_transform`'s translation
                            // rewritten, linear part untouched.
                            var rewritten = T
                            rewritten.tx = map.scale * T.tx + map.offset.x
                            rewritten.ty = map.scale * T.ty + map.offset.y
                            let stated = CGPoint(x: map.scale * p.x, y: map.scale * p.y)
                                .applying(rewritten)
                            worst = max(worst, abs(stated.x - expected.x))
                            worst = max(worst, abs(stated.y - expected.y))
                        }
                    }
                }
            }
        }
        XCTAssertEqual(cases, 324, "PREMISE: §2's grid is 3 × 4 × 3 × 3 × 3 = 324 cases")
        XCTAssertLessThan(worst, 1e-9, """
            Both spellings of `M ∘ T` must land on the same point; §2 measured the worst deviation \
            over this grid at 1.8e-12 pt and this run saw \(worst).
            """)
    }

    // MARK: - Stage 2, part 2: the letterbox invariant

    /// **Fit: the content fits, exactly one axis has slack, and the slack is split evenly.**
    ///
    /// The three clauses are one rule and each of them fails differently. "Fits" is the owner's ask;
    /// "exactly one axis" is what makes it a *letterbox* rather than a shrink with margin all round —
    /// the binding axis has to touch both edges, or `k` was not `min`; "split evenly" is §5 rule 3.
    func testFitLandsTheDrawingInsideWithTheSlackOnOneAxisSplitEvenly() {
        for (old, new) in Self.aspectChangingResizes {
            let map = CanvasResizeMap(from: old, to: new, mode: .scaleToFit)
            let content = map.contentRect
            let slackX = new.width - content.width
            let slackY = new.height - content.height

            XCTAssertGreaterThanOrEqual(slackX, -1e-9, "Fit never overflows in x — \(old) → \(new)")
            XCTAssertGreaterThanOrEqual(slackY, -1e-9, "Fit never overflows in y — \(old) → \(new)")
            XCTAssertTrue(abs(slackX) < 1e-9 || abs(slackY) < 1e-9,
                          "exactly one axis binds under Fit, or `k` was not the minimum — \(old) → \(new)")
            XCTAssertEqual(content.minX, slackX / 2, accuracy: 1e-9, "\(old) → \(new)")
            XCTAssertEqual(content.minY, slackY / 2, accuracy: 1e-9, "\(old) → \(new)")
            XCTAssertEqual(new.width - content.maxX, content.minX, accuracy: 1e-9,
                           "the two x margins are equal — \(old) → \(new)")
            XCTAssertEqual(new.height - content.maxY, content.minY, accuracy: 1e-9,
                           "the two y margins are equal — \(old) → \(new)")
        }
    }

    /// **Fill: the dual.** The content covers, exactly one axis overflows, and the overflow is split
    /// evenly — so what hangs off is the same amount on both sides rather than all of it off one.
    func testFillCoversTheNewShapeWithTheOverflowOnOneAxisSplitEvenly() {
        for (old, new) in Self.aspectChangingResizes {
            let map = CanvasResizeMap(from: old, to: new, mode: .scaleToFill)
            let content = map.contentRect
            let slackX = new.width - content.width
            let slackY = new.height - content.height

            XCTAssertLessThanOrEqual(slackX, 1e-9, "Fill never leaves a gap in x — \(old) → \(new)")
            XCTAssertLessThanOrEqual(slackY, 1e-9, "Fill never leaves a gap in y — \(old) → \(new)")
            XCTAssertTrue(abs(slackX) < 1e-9 || abs(slackY) < 1e-9,
                          "exactly one axis binds under Fill, or `k` was not the maximum — \(old) → \(new)")
            XCTAssertEqual(content.minX, slackX / 2, accuracy: 1e-9, "\(old) → \(new)")
            XCTAssertEqual(content.minY, slackY / 2, accuracy: 1e-9, "\(old) → \(new)")
            XCTAssertEqual(content.maxX - new.width, -content.minX, accuracy: 1e-9,
                           "the overflow is the same on both x edges — \(old) → \(new)")
        }
    }

    /// The two modes are the *same map* with a different ratio — §5 rule 2's "no second code path" —
    /// and at an unchanged aspect they are literally the same number, which is why the sheet offers
    /// the choice only when the shape changes.
    func testFitAndFillAgreeExactlyWhenTheAspectDoesNotChange() {
        let old = CGSize(width: 64, height: 32)
        for new in [CGSize(width: 128, height: 64), CGSize(width: 16, height: 8), old] {
            let fit = CanvasResizeMap(from: old, to: new, mode: .scaleToFit)
            let fill = CanvasResizeMap(from: old, to: new, mode: .scaleToFill)
            XCTAssertEqual(fit.scale, fill.scale, accuracy: 0, "same aspect, same k — \(old) → \(new)")
            XCTAssertEqual(fit.offset, fill.offset, "\(old) → \(new)")
        }
    }

    // MARK: - Stage 2, part 3: the round trip

    /// **A vector round trip returns every sample to where it started** — §4 stage 2's `k = 0.25`
    /// then `k = 4`, to within 1e-9, on a real document rather than on the arithmetic.
    ///
    /// **And the second case is the one that matters, because it is the one the inverse can get
    /// wrong.** `0.25 → 4` is square, so Fit and Fill agree and any inverse rule passes it. `64² →
    /// 100×40 → 64²` is not: Fit out is `min(100/64, 40/64) = 0.625`, and coming back wants `1/0.625
    /// = 1.6`, which is `max(64/100, 64/40)` — **Fill's** rule, not Fit's. Fit both ways would come
    /// back at `min(0.64, 1.6) = 0.64` and land the drawing 2% small, on every aspect change. That is
    /// `CanvasResizeMode.inverted`, and until stage 2 this file derived the inverse from `scale != 1`
    /// instead, which picks Fit both ways; it was never wrong only because nothing could run it.
    func testAScaleOutAndBackReturnsEverySampleToWhereItStarted() throws {
        let trips: [(CGSize, CanvasResizeMode, CGSize, CanvasResizeMode)] = [
            (CGSize(width: 16, height: 16), .scaleToFit, CGSize(width: 64, height: 64), .scaleToFit),
            (CGSize(width: 100, height: 40), .scaleToFit, CGSize(width: 64, height: 64), .scaleToFill),
            (CGSize(width: 100, height: 40), .scaleToFill, CGSize(width: 64, height: 64), .scaleToFit),
        ]
        let samples = [CGPoint(x: 10, y: 12), CGPoint(x: 30, y: 34), CGPoint(x: 63, y: 1)]

        for (out, outMode, back, backMode) in trips {
            let manager = CanvasFixture.manager(layerCount: 1)
            manager.addVectorLayer()
            let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
            canvas.addStroke(Self.stroke(at: samples, size: 8, brush: manager.selectedBrush))
            let label = "\(out) \(outMode) then \(back) \(backMode)"

            XCTAssertTrue(manager.resizeCanvas(to: out, mode: outMode), label)
            XCTAssertTrue(manager.resizeCanvas(to: back, mode: backMode), label)

            XCTAssertEqual(manager.canvasSize, back, label)
            let stroke = try XCTUnwrap(manager.layers[1].cels[0].vector?.strokes.first, label)
            XCTAssertEqual(stroke.samples.count, samples.count, label)
            for (i, original) in samples.enumerated() {
                XCTAssertEqual(stroke.samples[i].x, original.x, accuracy: 1e-9, "sample \(i), \(label)")
                XCTAssertEqual(stroke.samples[i].y, original.y, accuracy: 1e-9, "sample \(i), \(label)")
            }
            XCTAssertEqual(stroke.size, 8, accuracy: 1e-9,
                           "the brush width rides the same similarity, \(label)")
        }
    }

    /// The same claim on the map alone, over every aspect-changing pair in both modes: `M⁻¹ ∘ M` is
    /// the identity to float noise, and the inverse's own mode is the flipped one.
    func testTheInverseMapUndoesTheScaleAndFlipsFitToFill() {
        for (old, new) in Self.aspectChangingResizes {
            for mode in [CanvasResizeMode.scaleToFit, .scaleToFill] {
                let out = CanvasResizeMap(from: old, to: new, mode: mode)
                let back = out.inverse
                XCTAssertEqual(back.mode, mode.inverted, "\(old) → \(new) \(mode)")
                XCTAssertEqual(back.scale, 1 / out.scale, accuracy: 1e-12, "\(old) → \(new) \(mode)")
                for p in [CGPoint(x: 0, y: 0), CGPoint(x: 13, y: 29), CGPoint(x: 63.5, y: 2.25)] {
                    let returned = back.apply(out.apply(p))
                    XCTAssertEqual(returned.x, p.x, accuracy: 1e-9, "\(old) → \(new) \(mode) at \(p)")
                    XCTAssertEqual(returned.y, p.y, accuracy: 1e-9, "\(old) → \(new) \(mode) at \(p)")
                }
            }
        }
    }

    // MARK: - Stage 2, part 4: the spacing floor

    /// **The floor boundary, stated as `LassoMoveLogicTests` states it** — the dab count is
    /// scale-invariant above the floor and is not below it, and it is `size × spacingFraction` that
    /// decides which.
    ///
    /// This is the limitation §2 inherits knowingly rather than fixes; the test exists so the
    /// boundary is a pinned fact rather than a paragraph, and so the survey below can be checked
    /// against the engine instead of against its own arithmetic.
    func testTheSpacingFloorIsWhereAResizeStopsBeingASimilarity() {
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = 0.05
        let line = [VectorSample(x: 0, y: 0, pressure: 1), VectorSample(x: 40, y: 0, pressure: 1)]
        func walk(size: CGFloat, scale k: CGFloat) -> Int {
            let target = RecordingDabTarget()
            BrushStamper.stampStroke(into: target,
                                     samples: line.map {
                                         BrushStamper.Sample(point: CGPoint(x: $0.x * k, y: $0.y * k),
                                                             pressure: $0.pressure)
                                     },
                                     brush: brush, color: .black, brushSize: size * k,
                                     brushOpacity: 1, seed: 99)
            return target.dabs.count
        }
        // Clear of the floor at both sizes — 40 × 0.05 = 2 pt, halving to 1 pt — so a resize is the
        // exact similarity `mapping(_:throughSimilarity:)`'s doc claims.
        XCTAssertEqual(walk(size: 40, scale: 0.5), walk(size: 40, scale: 1),
                       "above the floor the dab count is scale-invariant")
        // Under it at both sizes: 4 × 0.05 = 0.2 pt, floored to 1 pt either way, so the half-length
        // path simply gets half as many 1 pt steps.
        XCTAssertNotEqual(walk(size: 4, scale: 0.5), walk(size: 4, scale: 1),
                          "under the floor the spacing stops scaling and the count follows the length")
    }

    /// The survey the dialog asks answers **exactly** the strokes the engine's floor catches.
    ///
    /// A stroke with threshold `s = size × spacingFraction` crosses at factor `k` iff
    /// `(s < 1) != (s·k < 1)`. This checks the closed form against that definition over a grid rather
    /// than restating it: the interval arithmetic is where a sign or a bound would go wrong quietly,
    /// and a survey that answered "no" on everything would leave the dialog silently correct-looking.
    func testTheFloorSurveyAnswersExactlyTheStrokesThatCrossIt() {
        let thresholds: [CGFloat] = [0.2, 0.5, 0.9, 1.0, 1.6, 2.0, 40.0]
        let survey = SpacingFloorSurvey(thresholds: thresholds)
        for k in [0.1, 0.25, 0.5, 0.625, 0.9, 1.0, 1.1, 1.6, 2.0, 4.0, 10.0] as [CGFloat] {
            let expected = thresholds.contains { ($0 < 1) != ($0 * k < 1) }
            XCTAssertEqual(survey.isCrossed(byScaling: k), expected, "k = \(k)")
        }
        XCTAssertFalse(SpacingFloorSurvey(thresholds: []).isCrossed(byScaling: 0.25),
                       "a document with no strokes has nothing to re-stamp")
        XCTAssertFalse(survey.isCrossed(byScaling: 1), "a crop/expand re-stamps nothing")
    }

    /// The survey reads the document the dialog will be looking at: vector strokes, and the
    /// `LocalEdit` strokes an in-between carries, which are re-stamped by the evaluator exactly like
    /// any other. A raster tier contributes nothing — it is resampled, not re-stamped.
    func testTheFloorSurveyReadsVectorStrokesAndLocalEdits() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = 0.05
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        canvas.addStroke(Self.stroke(at: [CGPoint(x: 1, y: 1)], size: 40, brush: brush))   // s = 2
        manager.layers[0].cels[0].interpolation = InterpolationRecipe(
            t: 0.5, groups: [],
            localEdits: [LocalEdit(stroke: Self.stroke(at: [CGPoint(x: 2, y: 2)], size: 4, brush: brush))]) // s = 0.2

        XCTAssertEqual(manager.spacingFloorSurvey.thresholds.map { ($0 * 100).rounded() / 100 },
                       [0.2, 2.0], "both strokes, ascending — and nothing from the raster tiers")
    }

    // MARK: - Stage 2, part 5: what the walk does to a whole document

    /// **`k` is the ratio of the artwork rects, not of the buffers** — the correction stage 2 made to
    /// `CanvasResizeMap`'s own doc comment, and it is only visible on a document with padding.
    ///
    /// With 4 pt of padding, doubling a 32 pt artwork gives a buffer ratio of `72/40 = 1.8` where the
    /// artist typed a number meaning 2. Under the buffer reading their drawing comes out 57.6 pt wide
    /// inside a margin that has silently grown to 7.2; under the artwork reading it comes out 64 pt
    /// wide with the margin still 4, which is what §5 rule 9 and §6 Q3 between them require.
    func testTheScaleFactorIsTheArtworkRatioAndNotTheBufferRatio() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.setCanvasPadding(4)
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        // The artwork rect's two corners, in buffer coordinates: padding is 4, artwork is 64.
        canvas.addStroke(Self.stroke(at: [CGPoint(x: 4, y: 4), CGPoint(x: 68, y: 68)],
                                     size: 8, brush: manager.selectedBrush))

        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 128, height: 128), mode: .scaleToFit))

        XCTAssertEqual(manager.canvasPadding, 4, "the margin is preserved literally and never scales")
        XCTAssertEqual(manager.canvasSize, CGSize(width: 136, height: 136))
        let stroke = try XCTUnwrap(manager.layers[1].cels[0].vector?.strokes.first)
        XCTAssertEqual(stroke.samples[0].x, 4, accuracy: 1e-9,
                       "the old artwork rect's corner lands on the new artwork rect's corner")
        XCTAssertEqual(stroke.samples[1].x, 132, accuracy: 1e-9)
        XCTAssertEqual(stroke.size, 16, accuracy: 1e-9, "k is 2 — the artwork ratio, not 136/72")
    }

    /// Every tier of every cel scales together, and the vector tier carries the brush width with it.
    /// §5 rules 5 and 7 under `k != 1`: one map, no partial application.
    func testEveryTierScalesTogetherAndTheBrushWidthTravels() throws {
        let manager = Self.documentWithEveryTierPopulated()
        let newSize = CGSize(width: 32, height: 32)
        XCTAssertTrue(manager.resizeCanvas(to: newSize, mode: .scaleToFit))

        XCTAssertEqual(manager.canvasSize, newSize)
        for (layerIndex, layer) in manager.layers.enumerated() {
            for (celIndex, cel) in layer.cels.enumerated() {
                let where_ = "layer \(layerIndex) cel \(celIndex)"
                XCTAssertEqual(cel.raster.size, newSize, "raster tier, \(where_)")
                if let fill = cel.fillImage { XCTAssertEqual(fill.size, newSize, "fillImage, \(where_)") }
                if let baked = cel.bakedImage { XCTAssertEqual(baked.size, newSize, "bakedImage, \(where_)") }
                if let vector = cel.vector {
                    XCTAssertEqual(vector.size, newSize, "vector tier, \(where_)")
                    XCTAssertTrue(vector.transform.isIdentity, "\(where_)")
                }
            }
        }
        let stroke = try XCTUnwrap(manager.layers[2].cels[0].vector?.strokes.first)
        XCTAssertEqual(stroke.size, 4, accuracy: 1e-9, "8 pt at k = 0.5")
        XCTAssertEqual(stroke.samples[0].x, 5, accuracy: 1e-9, "and the samples with it")
    }

    /// **The raster tier really resamples**, rather than landing at the new extent with its pixels
    /// drawn at the old size — which is exactly what `placing:` would do if the rect it was handed
    /// were still the source's own size, and which nothing above would catch.
    ///
    /// Asserted as the bounding box of what is painted, not as bytes: `draw(in:)` filters, so the
    /// edges are soft by a pixel and a byte comparison would be a test of CoreGraphics' resampler.
    func testTheRasterTierIsResampledIntoThePlacementRect() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 8, y: 12, width: 24, height: 16)))
        XCTAssertTrue(manager.resizeCanvas(to: CGSize(width: 32, height: 32), mode: .scaleToFit))

        let image = try XCTUnwrap(manager.layers[0].cels[0].bakedImage?.cgImage)
        let painted = try XCTUnwrap(Self.paintedBounds(image), "the resize left the tier empty")
        // k = 0.5, offset zero (square to square), so (8, 12, 24, 16) becomes (4, 6, 12, 8).
        XCTAssertEqual(painted.minX, 4, accuracy: 1.5, "\(painted)")
        XCTAssertEqual(painted.minY, 6, accuracy: 1.5, "\(painted)")
        XCTAssertEqual(painted.width, 12, accuracy: 2, "\(painted)")
        XCTAssertEqual(painted.height, 8, accuracy: 2, "\(painted)")
    }

    /// **The vector/raster asymmetry under Fill, which is §6 Q4's interesting consequence.** An
    /// element that overflows the new canvas is *kept* — an off-canvas element is still an element,
    /// and stored coordinates leave `[0, extent)` routinely — while a raster tier is cropped
    /// destructively, because a raster tier is a buffer of exactly the canvas extent and the overflow
    /// has nowhere to live. Not a §5 rule 11 refusal case: nothing here is unmappable.
    func testFillKeepsOverflowingVectorGeometryAndCropsTheRaster() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        // Vertical, because y is the axis that overflows below and a horizontal stroke would stay
        // comfortably inside — the premise assertions are what say so.
        canvas.addStroke(Self.stroke(at: [CGPoint(x: 32, y: 2), CGPoint(x: 32, y: 62)],
                                     size: 8, brush: manager.selectedBrush))

        // 64² → 100×40 under Fill: k = max(100/64, 40/64) = 1.5625, so x fits exactly and y overflows
        // by 60 points, 30 off each edge.
        let newSize = CGSize(width: 100, height: 40)
        XCTAssertTrue(manager.resizeCanvas(to: newSize, mode: .scaleToFill))

        let stroke = try XCTUnwrap(manager.layers[1].cels[0].vector?.strokes.first)
        XCTAssertEqual(manager.layers[1].cels[0].vector?.strokes.count, 1,
                       "nothing is dropped for hanging over the edge")
        XCTAssertEqual(stroke.samples[0].y, 2 * 1.5625 - 30, accuracy: 1e-9,
                       "and it keeps its real coordinate, outside [0, 40) though it is")
        XCTAssertEqual(stroke.samples[1].y, 62 * 1.5625 - 30, accuracy: 1e-9)
        XCTAssertLessThan(stroke.samples[0].y, 0, "PREMISE: this end really is off the new canvas")
        XCTAssertGreaterThan(stroke.samples[1].y, newSize.height,
                             "PREMISE: and this one off the other edge")

        let baked = try XCTUnwrap(manager.layers[0].cels[0].bakedImage)
        XCTAssertEqual(baked.size, newSize, "the raster tier is exactly the canvas extent, so it crops")
    }

    /// Interpolation lattices scale their cell size with their vertices, and the `LocalEdit` strokes
    /// embedded in them ride through **once**.
    ///
    /// `restCellSize` is the scalar the scale arm added. The rest grid is `cols × rows` cells of that
    /// size from `restOrigin`, so leaving it behind while the vertices scaled would make
    /// `embedInRest`'s closed form describe a grid the vertex array no longer is.
    func testInterpolationLatticesScaleTheirCellSizeAndCarryTheirLocalEditsOnce() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let groupID = UUID()
        let lattice = Lattice(cols: 2, rows: 2, restOrigin: CGPoint(x: 10, y: 14),
                              restCellSize: 8, activeCells: [0, 3])
        let edit = LocalEdit(stroke: Self.stroke(at: [CGPoint(x: 16, y: 20)], size: 5,
                                                 brush: manager.selectedBrush),
                             groupID: groupID)
        manager.layers[0].cels[0].interpolation = InterpolationRecipe(
            t: 0.5, groups: [MotionGroupBinding(groupID: groupID, lattices: [lattice])], localEdits: [edit])

        let newSize = CGSize(width: 32, height: 32)
        let map = CanvasResizeMap(from: CanvasFixture.canvasSize, to: newSize, mode: .scaleToFit)
        XCTAssertEqual(map.scale, 0.5, accuracy: 0, "PREMISE: 64 → 32 is a halving")
        XCTAssertTrue(manager.resizeCanvas(to: newSize, mode: .scaleToFit))

        let recipe = try XCTUnwrap(manager.layers[0].cels[0].interpolation)
        let moved = try XCTUnwrap(recipe.groups.first?.lattices.first)
        XCTAssertEqual(moved.restOrigin, map.apply(CGPoint(x: 10, y: 14)))
        XCTAssertEqual(moved.restCellSize, 4, accuracy: 1e-9, "cell size is a length and scales with k")
        for (i, vertex) in lattice.vertices.enumerated() {
            XCTAssertEqual(moved.vertices[i].x, map.apply(vertex).x, accuracy: 1e-9, "vertex \(i)")
            XCTAssertEqual(moved.vertices[i].y, map.apply(vertex).y, accuracy: 1e-9, "vertex \(i)")
        }
        // The vertex array still *is* the rest grid it describes, which is the whole reason
        // `restCellSize` had to move: the two are two statements of one geometry.
        XCTAssertEqual(moved.vertices[1].x - moved.vertices[0].x, moved.restCellSize, accuracy: 1e-9)
        XCTAssertEqual(moved.cols, 2); XCTAssertEqual(moved.rows, 2)
        XCTAssertEqual(moved.activeCells, [0, 3], "cell topology is not geometry")

        let movedEdit = try XCTUnwrap(recipe.localEdits.first)
        let expected = map.apply(CGPoint(x: 16, y: 20))
        XCTAssertEqual(movedEdit.stroke.samples[0].x, expected.x, accuracy: 1e-9,
                       "the local edit rides the lattice — once, not twice")
        XCTAssertEqual(movedEdit.stroke.samples[0].y, expected.y, accuracy: 1e-9)
        XCTAssertEqual(movedEdit.stroke.size, 2.5, accuracy: 1e-9,
                       "it goes through `mapping`, so its width travels with its samples")
    }

    /// Guides are document-level canvas coordinates and scale like everything else — the same walk
    /// stage 1 fixed, now under `k != 1`. `pressure` and `time` are unit-free.
    func testGuidesScaleWithTheArtwork() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let celRef = CelRef(layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)
        manager.guideStrokes = [GuideStroke(
            samples: [TimedSample(x: 10, y: 12, pressure: 0.5, time: 0),
                      TimedSample(x: 30, y: 34, pressure: 0.75, time: 0.25)],
            interval: KeyframeInterval(start: celRef, end: celRef))]

        let newSize = CGSize(width: 100, height: 40)
        let map = CanvasResizeMap(from: CanvasFixture.canvasSize, to: newSize, mode: .scaleToFit)
        XCTAssertTrue(manager.resizeCanvas(to: newSize, mode: .scaleToFit))

        let guide = try XCTUnwrap(manager.guideStrokes.first)
        for (i, original) in [CGPoint(x: 10, y: 12), CGPoint(x: 30, y: 34)].enumerated() {
            XCTAssertEqual(guide.samples[i].x, map.apply(original).x, accuracy: 1e-9, "sample \(i)")
            XCTAssertEqual(guide.samples[i].y, map.apply(original).y, accuracy: 1e-9, "sample \(i)")
        }
        XCTAssertEqual(guide.samples[1].pressure, 0.75, accuracy: 1e-12, "pressure is unit-free")
        XCTAssertEqual(guide.samples[1].time, 0.25, accuracy: 1e-12, "time is unit-free")
    }

    // MARK: - Stage 2, part 6: the compositor gate the dialog warns about

    /// §5 rule 14's predicate: **silent below the budget, and it names two different thresholds
    /// above it**, because the live canvas and the eyedropper reach the gate by different routes.
    ///
    /// Against a stated budget rather than the running device's, for
    /// `CompositorBudget.textureBudgetBytes(physicalMemory:)`'s reason — the real one is a property
    /// of whatever Mac or iPad this runs on and would make the assertion a measurement.
    func testTheCompositorGateIsSilentBelowTheBudgetAndWarnsAboveIt() {
        // 5 textures for the walk, 7 for the sandwich — an ordinary stack with a couple of uploads.
        let gate = CompositorSizeGate(nativeTextures: 5, sandwichTextures: 7)
        let budget = 192 * 1024 * 1024   // the owner's iPad 9

        // 2048×1024 is 8 MiB a texture: 40 MiB for the walk, 56 for the sandwich. Both fit.
        let clear = gate.pressure(atBufferSize: CGSize(width: 2048, height: 1024), budgetBytes: budget)
        XCTAssertTrue(clear.isClear, "an ordinary canvas must not raise a warning")

        // 4096×2048 is 32 MiB a texture: 160 for the walk, 224 for the sandwich. The canvas softens;
        // a native composite still fits, so the eyedropper is unaffected. That asymmetry is the
        // reason there are two counts and not one.
        let softens = gate.pressure(atBufferSize: CGSize(width: 4096, height: 2048), budgetBytes: budget)
        XCTAssertTrue(softens.canvasSoftens)
        XCTAssertFalse(softens.nativeCompositeFallsToCPU)

        // 8192×4096 is 128 MiB a texture. Both.
        let both = gate.pressure(atBufferSize: CGSize(width: 8192, height: 4096), budgetBytes: budget)
        XCTAssertTrue(both.canvasSoftens)
        XCTAssertTrue(both.nativeCompositeFallsToCPU)
        XCTAssertFalse(both.isClear)
    }

    /// The gate the dialog actually asks is built from the live layer stack, so it moves when the
    /// document's structure does — which is the half a hand-written count could get wrong.
    func testTheGateComesFromTheDocumentsOwnLayerStack() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let one = manager.compositorSizeGate
        XCTAssertGreaterThan(one.nativeTextures, 0, "even a single layer needs the accumulator pair")
        XCTAssertGreaterThanOrEqual(one.sandwichTextures, one.nativeTextures,
                                    "the sandwich asks for the walk's textures plus its uploads")
        for _ in 0..<4 { manager.addLayer() }
        XCTAssertGreaterThanOrEqual(manager.compositorSizeGate.sandwichTextures, one.sandwichTextures,
                                    "adding layers cannot make the walk cheaper")
    }

    // MARK: - Fixtures

    /// The three resizes §2's 324-case grid uses, and the ones the identity tests share: a Fit and a
    /// Fill onto the same changed aspect, plus a plain shrink. Non-square in both directions, so a
    /// swapped axis cannot pass.
    private static let scalingResizes: [(CGSize, CGSize, CanvasResizeMode)] = [
        (CGSize(width: 64, height: 64), CGSize(width: 100, height: 40), .scaleToFit),
        (CGSize(width: 64, height: 64), CGSize(width: 100, height: 40), .scaleToFill),
        (CGSize(width: 64, height: 64), CGSize(width: 16, height: 16), .scaleToFit),
    ]

    /// Pairs whose aspect really changes, so Fit and Fill are different maps and the letterbox
    /// invariants have something to be about. Both directions of binding axis, and both a growth and
    /// a shrink, because "exactly one axis has slack" is the clause that fails when `min` and `max`
    /// are swapped and it fails on only half the cases.
    private static let aspectChangingResizes: [(CGSize, CGSize)] = [
        (CGSize(width: 64, height: 64), CGSize(width: 100, height: 40)),
        (CGSize(width: 64, height: 64), CGSize(width: 40, height: 100)),
        (CGSize(width: 100, height: 40), CGSize(width: 64, height: 64)),
        (CGSize(width: 2048, height: 1024), CGSize(width: 999, height: 3001)),
        (CGSize(width: 7, height: 3), CGSize(width: 8, height: 8)),
    ]

    /// A stroke at known samples, so a test states the geometry it is going to assert on rather than
    /// the eight fields `VectorStroke` needs to exist.
    private static func stroke(at points: [CGPoint], size: CGFloat,
                               brush: Brush = BrushLibrary.hardRound) -> VectorStroke {
        VectorStroke(brush: brush,
                     color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: size, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
    }

    /// The bounding box of everything with any alpha in it — what a resample moved, measured in a way
    /// that a filtered edge cannot break.
    private static func paintedBounds(_ image: CGImage) -> CGRect? {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return nil }
        let width = image.width, height = image.height
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 8 {
                minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    /// Records where every dab landed, so the floor test asserts on the *walk* rather than inferring
    /// it from pixels. `LassoMoveLogicTests` has its own copy, private to that class for the same
    /// reason this one is: it is three lines of protocol conformance, and a shared one would put a
    /// test helper in the app's own namespace.
    private final class RecordingDabTarget: DabTarget {
        private(set) var dabs: [(point: CGPoint, radius: CGFloat)] = []
        func beginStroke() {}
        func endStroke() {}
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            dabs.append((point, radius))
        }
    }

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
