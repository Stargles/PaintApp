import XCTest
import UIKit

/// Pure-logic tests for the interpolation **data model**. Nothing here renders or interpolates
/// anything; these tests exist to pin the two properties that are expensive to discover later:
///
/// 1. **Backward compatibility.** A project saved before any of this existed loads unchanged, and a
///    project that never uses interpolation writes exactly the bytes it used to. The repo's whole
///    persistence discipline rests on that, and a regression is invisible until someone opens an old
///    file.
/// 2. **Round-trip fidelity.** A recipe — references, lattices, groups, guides, local edits,
///    visibility thresholds — survives save→load with nothing quietly dropped or approximated. The
///    lattice cases matter most: its encoding deliberately *omits* the rest configuration and
///    reconstructs it, so "unchanged" is a claim about a reconstruction, not a copy.
///
/// The class is `@MainActor` because `CanvasManager`, `ProjectStore.save` and `.load` are.
@MainActor
final class InterpolationModelLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("interp-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Helpers

    /// Deterministic key order, so two encodings of equal values are comparable as bytes.
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func topLevelKeys(_ data: Data) throws -> Set<String> {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    private func sampleStroke(id: UUID = UUID()) -> VectorStroke {
        VectorStroke(brush: BrushLibrary.softRound,
                     color: CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
                     size: 9, opacity: 0.8,
                     samples: [VectorSample(x: 10, y: 12, pressure: 0.5),
                               VectorSample(x: 40, y: 44, pressure: 0.9)])
            .withID(id)
    }

    /// A lattice that is genuinely deformed, so the encoder's "omit the rest configuration" path is
    /// not the one under test.
    private func deformedLattice() -> Lattice {
        var lattice = Lattice(cols: 3, rows: 2, restOrigin: CGPoint(x: -8, y: 4), restCellSize: 16,
                              activeCells: [0, 3, 5])
        for i in lattice.vertices.indices {
            lattice.vertices[i].x += CGFloat(i) * 0.75
            lattice.vertices[i].y -= CGFloat(i % 3) * 1.25
        }
        return lattice
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    // MARK: - Byte identity: nothing new on disk until the feature is used

    /// The headline back-compat property for `VectorStroke`: three fields were added to the most
    /// numerous type in the format, and a stroke that uses none of them must encode as if they did
    /// not exist. `encodeIfPresent` on a nil optional writes no key at all — this is what says so.
    func testUntaggedStrokeEncodesWithoutAnyInterpolationKeys() throws {
        let keys = try topLevelKeys(try encoded(sampleStroke()))
        XCTAssertEqual(keys, ["id", "brush", "color", "size", "opacity", "samples", "composite"],
                       "An ordinary stroke's payload must be exactly what it was before interpolation fields existed")
    }

    /// The decode half: a payload written before these fields existed still loads, with all three
    /// absent rather than throwing `keyNotFound`.
    func testStrokeSavedBeforeInterpolationDecodesWithNoTagOrThresholds() throws {
        let legacy = try encoded(sampleStroke())
        let decoded = try JSONDecoder().decode(VectorStroke.self, from: legacy)
        XCTAssertNil(decoded.motionGroupID)
        XCTAssertNil(decoded.visibilityThreshold)
        XCTAssertNil(decoded.sampleVisibilityThresholds)
    }

    /// The same contract one level up: a manifest from a project that never interpolated carries no
    /// registry keys, so an existing project's `manifest.json` is unchanged by this phase.
    func testManifestOmitsInterpolationRegistriesWhenEmpty() throws {
        let manifest = ProjectManifest(id: UUID(), name: "Untouched", canvasWidth: 64, canvasHeight: 64,
                                       fps: 24, sceneFrameCount: 12, layers: [], modifiedAt: Date())
        let keys = try topLevelKeys(try encoded(manifest))
        XCTAssertFalse(keys.contains("motionGroups"))
        XCTAssertFalse(keys.contains("guideStrokes"))
    }

    /// And a manifest saved before the registries existed loads with them empty rather than failing.
    func testManifestSavedBeforeRegistriesDecodesWithEmptyOnes() throws {
        let manifest = ProjectManifest(id: UUID(), name: "Legacy", canvasWidth: 64, canvasHeight: 64,
                                       fps: 24, sceneFrameCount: 12, layers: [], modifiedAt: Date())
        let decoded = try JSONDecoder().decode(ProjectManifest.self, from: try encoded(manifest))
        XCTAssertTrue(decoded.motionGroups.isEmpty)
        XCTAssertTrue(decoded.guideStrokes.isEmpty)
    }

    /// A cel manifest predating the recipe file simply has no such key, which must decode as "an
    /// ordinary, non-interpolated cel".
    func testCelManifestWithoutInterpolationFileDecodesAsNil() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","startFrame":0,"frameCount":1,"rasterFileName":"a.png"}"#.utf8)
        let decoded = try JSONDecoder().decode(CelManifest.self, from: json)
        XCTAssertNil(decoded.interpolationFileName)
    }

    // MARK: - Lattice encoding

    /// The encoding's central claim (HANDOFF §5.7): a lattice at rest costs four numbers plus its
    /// active set, because the rest grid is reconstructible in closed form.
    func testRestLatticeOmitsItsVerticesAndRebuildsThemExactly() throws {
        let lattice = Lattice(cols: 4, rows: 3, restOrigin: CGPoint(x: 12, y: -6),
                              restCellSize: 20, activeCells: [2, 7])
        let data = try encoded(lattice)
        XCTAssertFalse(try topLevelKeys(data).contains("vertices"),
                       "A lattice at rest carries no information in its vertices — they are derivable")

        let decoded = try JSONDecoder().decode(Lattice.self, from: data)
        XCTAssertEqual(decoded, lattice, "The rebuilt rest grid must equal the original exactly, not approximately")
    }

    /// A deformed lattice does carry its vertices, and they come back bit-for-bit — the whole
    /// deformation is in that array, so an approximation here would be a silently wrong warp.
    func testDeformedLatticeRoundTripsExactly() throws {
        let lattice = deformedLattice()
        let decoded = try JSONDecoder().decode(Lattice.self, from: try encoded(lattice))
        XCTAssertEqual(decoded, lattice)
        XCTAssertEqual(decoded.vertices, lattice.vertices)
        XCTAssertEqual(decoded.activeCells, lattice.activeCells)
    }

    /// A truncated or hand-edited payload must *throw*, not trap. `Lattice`'s designated initialiser
    /// has preconditions that would take the app down; the decoder validates ahead of them.
    func testLatticeWithAWrongVertexCountThrowsInsteadOfTrapping() throws {
        let json = Data(#"{"cols":2,"rows":2,"originX":0,"originY":0,"cellSize":10,"vertices":[0,0,1,1],"activeCells":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Lattice.self, from: json))
    }

    func testLatticeWithADegenerateTopologyThrowsInsteadOfTrapping() throws {
        let json = Data(#"{"cols":0,"rows":3,"originX":0,"originY":0,"cellSize":10,"activeCells":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Lattice.self, from: json))
    }

    /// The §5.7 constraint, tested as behaviour rather than as a comment: expansion shifts every cell
    /// and vertex index, so anything persisted that *indexed* a lattice would silently misread after
    /// one. Nothing is — the recipe stores geometry, never indices — and this is what proves the
    /// stored form survives an expansion with the geometry landing in the same place.
    func testARecipeSurvivesLatticeExpansionBecauseItStoresNoIndices() throws {
        let lattice = deformedLattice()
        let probe = [CGPoint(x: 6, y: 14), CGPoint(x: 20, y: 26)]
        let before = lattice.warp(lattice.embedInRest(probe))

        let expansion = lattice.expanded(toContain: [CGPoint(x: -200, y: -200)], maxRings: 2)
        XCTAssertTrue(expansion.didExpand, "Setup: the probe point should force at least one ring")

        var recipe = InterpolationRecipe(references: [InterpolationReference(layerID: UUID(), celID: UUID()),
                                                     InterpolationReference(layerID: UUID(), celID: UUID())],
                                         t: 0.5)
        recipe.groups = [MotionGroupBinding(groupID: UUID(), lattices: [lattice, expansion.lattice])]

        let decoded = try JSONDecoder().decode(InterpolationRecipe.self, from: try encoded(recipe))
        let restored = try XCTUnwrap(decoded.groups.first?.lattices.last)
        let after = restored.warp(restored.embedInRest(probe))
        XCTAssertEqual(after.count, before.count)
        for (a, b) in zip(after, before) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    // MARK: - Recipe round-trip

    /// Everything the recipe carries, through one encode/decode, compared as bytes. Byte comparison
    /// rather than field-by-field because it catches a field nobody thought to assert on.
    func testFullRecipeRoundTripsUnchanged() throws {
        let groupID = UUID()
        var stroke = sampleStroke()
        stroke.motionGroupID = groupID
        stroke.visibilityThreshold = 0.35
        stroke.sampleVisibilityThresholds = [0: 0.1, 1: 0.9]

        var recipe = InterpolationRecipe(
            references: [InterpolationReference(layerID: UUID(), celID: UUID()),
                         InterpolationReference(layerID: UUID(), celID: UUID())],
            t: 0.42, mode: .reproject)
        recipe.groups = [MotionGroupBinding(groupID: groupID,
                                            lattices: [deformedLattice(), deformedLattice()],
                                            spacing: SpacingCurve(kind: .sampled, samples: [0, 0.3, 1]),
                                            guideIDs: [UUID()])]
        recipe.guideIDs = [UUID()]
        recipe.localEdits = [LocalEdit(stroke: stroke, groupID: groupID)]
        recipe.spacing = SpacingCurve(kind: .easeInOut)

        let original = try encoded(recipe)
        let decoded = try JSONDecoder().decode(InterpolationRecipe.self, from: original)
        XCTAssertEqual(try encoded(decoded), original, "The recipe must survive a round trip with nothing dropped")

        // The parts that would be easiest to lose silently, named directly.
        XCTAssertEqual(decoded.mode, .reproject)
        XCTAssertEqual(decoded.localEdits.first?.stroke.motionGroupID, groupID)
        XCTAssertEqual(decoded.localEdits.first?.stroke.visibilityThreshold, 0.35)
        XCTAssertEqual(decoded.localEdits.first?.stroke.sampleVisibilityThresholds?[1], 0.9)
    }

    /// The spline-ready shape from PLAN §10 decision 7, persisted. A four-reference recipe is not
    /// producible by the UI and will not be for some time; the model has to carry it anyway, because
    /// the point of the ordered list is that adding the spline later needs no migration.
    func testFourReferenceRecipeRoundTrips() throws {
        let references = (0..<4).map { _ in InterpolationReference(layerID: UUID(), celID: UUID()) }
        var recipe = InterpolationRecipe(references: references, t: 0.7)
        recipe.groups = [MotionGroupBinding(groupID: UUID(),
                                            lattices: (0..<4).map { _ in deformedLattice() })]

        let decoded = try JSONDecoder().decode(InterpolationRecipe.self, from: try encoded(recipe))
        XCTAssertEqual(decoded.references.count, 4)
        XCTAssertEqual(decoded.groups.first?.lattices.count, 4)
        XCTAssertTrue(decoded.isWellFormed,
                      "One lattice per reference is what well-formed means, at two references or at four")
    }

    /// A recipe saved by a build that had fewer fields still loads: only `references` and `t` are
    /// required, and everything else has a meaningful empty value.
    func testMinimalRecipePayloadDecodesWithDefaults() throws {
        let json = Data(#"{"references":[],"t":0.25}"#.utf8)
        let decoded = try JSONDecoder().decode(InterpolationRecipe.self, from: json)
        XCTAssertEqual(decoded.t, 0.25)
        XCTAssertEqual(decoded.mode, .generate)
        XCTAssertTrue(decoded.groups.isEmpty)
        XCTAssertTrue(decoded.localEdits.isEmpty)
        XCTAssertEqual(decoded.spacing, .linear)
        XCTAssertFalse(decoded.isWellFormed, "Fewer than two keyframes is not evaluable")
    }

    func testMultiLayerReferenceKeepsEveryContributingCel() throws {
        let layerA = UUID(), layerB = UUID()
        let reference = InterpolationReference(cels: [CelRef(layerID: layerA, celID: UUID()),
                                                     CelRef(layerID: layerB, celID: UUID())])
        let recipe = InterpolationRecipe(references: [reference, reference], t: 0)
        XCTAssertEqual(recipe.referencedCels.count, 2,
                       "Both layers' cels are sources, and the two references share them")
        XCTAssertEqual(Set(recipe.referencedCels.map(\.layerID)), [layerA, layerB])
    }

    // MARK: - Spacing

    func testSpacingCurvesAgreeAtTheEndpoints() {
        for curve in [SpacingCurve.linear, SpacingCurve(kind: .easeIn), SpacingCurve(kind: .easeOut),
                      SpacingCurve(kind: .easeInOut), SpacingCurve(kind: .sampled, samples: [0, 0.2, 1])] {
            XCTAssertEqual(curve.eased(0), 0, accuracy: 1e-12, "\(curve.kind) must start at its first keyframe")
            XCTAssertEqual(curve.eased(1), 1, accuracy: 1e-12, "\(curve.kind) must end at its last")
        }
    }

    func testSampledSpacingInterpolatesBetweenItsSamples() {
        let curve = SpacingCurve(kind: .sampled, samples: [0, 0.25, 1])
        XCTAssertEqual(curve.eased(0.25), 0.125, accuracy: 1e-12)
        XCTAssertEqual(curve.eased(0.5), 0.25, accuracy: 1e-12)
    }

    /// A half-recorded guide should not break the frame it drives.
    func testSampledSpacingWithTooFewSamplesFallsBackToLinear() {
        XCTAssertEqual(SpacingCurve(kind: .sampled, samples: [0.5]).eased(0.3), 0.3, accuracy: 1e-12)
    }

    func testGroupSpacingOverridesTheRecipes() {
        let groupID = UUID()
        var recipe = InterpolationRecipe(references: [], t: 0.5, spacing: SpacingCurve(kind: .easeIn))
        recipe.groups = [MotionGroupBinding(groupID: groupID, spacing: SpacingCurve(kind: .easeOut))]
        XCTAssertEqual(recipe.easedT(forGroup: groupID), 0.75, accuracy: 1e-12, "The group's own curve wins")
        XCTAssertEqual(recipe.easedT(forGroup: nil), 0.25, accuracy: 1e-12, "With no group, the recipe's applies")
    }

    // MARK: - Guides

    func testGuideWithNoBoundGroupsDrivesEveryGroup() {
        let interval = KeyframeInterval(start: CelRef(layerID: UUID(), celID: UUID()),
                                        end: CelRef(layerID: UUID(), celID: UUID()))
        let wholeFrame = GuideStroke(interval: interval)
        XCTAssertTrue(wholeFrame.drives(UUID()), "An empty binding set means the whole frame — PLAN §10 decision 6")

        let bound = UUID()
        let specific = GuideStroke(interval: interval, boundGroups: [bound])
        XCTAssertTrue(specific.drives(bound))
        XCTAssertFalse(specific.drives(UUID()))
    }

    func testGuideRoundTripsItsTimedSamples() throws {
        let guide = GuideStroke(samples: [TimedSample(x: 1, y: 2, pressure: 0.4, time: 0),
                                          TimedSample(x: 9, y: 8, pressure: 0.7, time: 0.125)],
                                interval: KeyframeInterval(start: CelRef(layerID: UUID(), celID: UUID()),
                                                           end: CelRef(layerID: UUID(), celID: UUID())),
                                boundGroups: [UUID()], role: .timing)
        let original = try encoded(guide)
        XCTAssertEqual(try encoded(try JSONDecoder().decode(GuideStroke.self, from: original)), original)
    }

    // MARK: - Undo

    /// The mapping PLAN §9 asks for, at the one place it is *not* free: a stroke's tag lives inside
    /// `VectorCanvas`, which a `StructureSnapshot` shares rather than copies, so retagging needs the
    /// display list snapshotted too. If this passes, the bracket is doing that.
    func testUndoOfAGroupRetagRestoresThePreviousAssignment() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)

        let first = UUID(), second = UUID()
        var strokeA = sampleStroke(id: first)
        let originalGroup = manager.addMotionGroup(name: "Torso",
                                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        strokeA.motionGroupID = originalGroup.id
        canvas.addStroke(strokeA)
        canvas.addStroke(sampleStroke(id: second))

        let arm = manager.addMotionGroup(name: "Arm",
                                         tagColor: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        manager.setMotionGroup(arm.id, forStrokeIDs: [first, second])
        XCTAssertEqual(canvas.strokes.map(\.motionGroupID), [arm.id, arm.id], "Setup: both strokes retagged")

        manager.undo()
        XCTAssertEqual(canvas.strokes.map(\.motionGroupID), [originalGroup.id, nil],
                       "Undo must restore each stroke's previous tag, including the one that had none")

        manager.redo()
        XCTAssertEqual(canvas.strokes.map(\.motionGroupID), [arm.id, arm.id], "Redo reapplies the tag")
    }

    /// Deleting a group is one action spanning two tiers — the registry and every stroke carrying
    /// the tag — so it has to be one undo step, not two.
    func testDeletingAGroupClearsItsTagsAndUndoesAsOneStep() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)

        let group = manager.addMotionGroup(name: "Cape",
                                           tagColor: CodableColor(red: 0, green: 1, blue: 0, alpha: 1))
        let strokeID = UUID()
        canvas.addStroke(sampleStroke(id: strokeID))
        manager.setMotionGroup(group.id, forStrokeIDs: [strokeID])

        manager.removeMotionGroup(group.id)
        XCTAssertTrue(manager.motionGroups.isEmpty)
        XCTAssertNil(canvas.strokes.first?.motionGroupID, "Deleting a group must not leave a dangling tag")

        manager.undo()
        XCTAssertEqual(manager.motionGroups.map(\.id), [group.id])
        XCTAssertEqual(canvas.strokes.first?.motionGroupID, group.id,
                       "One undo restores both the group and the tag — they were one action")
    }

    /// A slider drag is one step regardless of how many ticks it emits. The trap PLAN §9 names.
    func testASliderDragRecordsExactlyOneUndoStep() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let layerID = manager.layers[0].id
        let celID = manager.layers[0].cels[0].id
        manager.setInterpolation(InterpolationRecipe(references: [], t: 0), forCel: celID, inLayer: layerID)

        manager.beginInterpolationDrag()
        for tick in 1...10 {
            manager.setInterpolationT(CGFloat(tick) / 10, forCel: celID, inLayer: layerID)
        }
        manager.commitInterpolationDrag()
        XCTAssertEqual(manager.layers[0].cels[0].interpolation?.t, 1)

        manager.undo()
        XCTAssertEqual(manager.layers[0].cels[0].interpolation?.t, 0,
                       "One undo must rewind the whole drag, not the last tick")
    }

    /// Removing a guide has to take its references with it, or a recipe keeps pointing at something
    /// that no longer exists.
    func testDeletingAGuideDropsItsReferencesFromEveryRecipe() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let layerID = manager.layers[0].id
        let celID = manager.layers[0].cels[0].id
        let groupID = UUID()

        let guide = manager.addGuideStroke(
            GuideStroke(interval: KeyframeInterval(start: CelRef(layerID: layerID, celID: celID),
                                                   end: CelRef(layerID: layerID, celID: celID))))
        var recipe = InterpolationRecipe(references: [], t: 0)
        recipe.guideIDs = [guide.id]
        recipe.groups = [MotionGroupBinding(groupID: groupID, guideIDs: [guide.id])]
        manager.setInterpolation(recipe, forCel: celID, inLayer: layerID)

        manager.removeGuideStroke(id: guide.id)
        XCTAssertTrue(manager.guideStrokes.isEmpty)
        XCTAssertEqual(manager.layers[0].cels[0].interpolation?.guideIDs, [])
        XCTAssertEqual(manager.layers[0].cels[0].interpolation?.groups.first?.guideIDs, [])
    }

    // MARK: - Cache eviction

    /// `VectorCanvas.cachedImage` had no eviction, which PLAN §8 flags as the thing to fix before a
    /// feature that multiplies live cels ships. The policy keeps the frames near the playhead.
    func testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = 1
        // Assigned directly rather than built with `addCel`: the fixture's layers start with one cel
        // spanning the whole scene, so every add would collide with it. The timeline here is the
        // premise of the test, not the thing under test.
        // Each cel gets a stroke: an empty `VectorCanvas` renders to a shared 1x1 and memoizes
        // nothing (PLAN §8.1), so a timeline of blank cels would have nothing for eviction to evict
        // and the test would pass vacuously.
        manager.layers[layerIndex].cels = (0..<6).map { frame in
            Cel(id: UUID(), startFrame: frame, frameCount: 1,
                raster: .empty(size: CanvasFixture.canvasSize),
                vector: VectorCanvas(size: CanvasFixture.canvasSize, strokes: [sampleStroke()]))
        }
        let cels = manager.layers[layerIndex].cels
        for cel in cels { _ = cel.vector?.render() }
        XCTAssertTrue(cels.allSatisfy { $0.vector?.hasCachedImage == true }, "Setup: every cel is cached")

        manager.currentFrame = 0
        manager.evictDistantVectorRenderCaches(limit: 2)

        let kept = cels.filter { $0.vector?.hasCachedImage == true }
        XCTAssertEqual(kept.count, 2, "Only the limit survives")
        XCTAssertEqual(kept.map(\.startFrame), [0, 1], "And it is the frames nearest the playhead that do")
    }

    /// Dropping a cache is a memory decision, never a content one: `version` must not move, or every
    /// version-keyed consumer would believe the drawing had changed.
    func testDroppingACachedImageDoesNotLookLikeAnEdit() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[1].cels[0].vector)
        canvas.addStroke(sampleStroke())
        _ = canvas.render()

        let versionBefore = canvas.version
        canvas.dropCachedImage()
        XCTAssertFalse(canvas.hasCachedImage)
        XCTAssertEqual(canvas.version, versionBefore, "Eviction is not an edit")
        XCTAssertNotNil(canvas.render(), "And the next render simply recomputes it")
    }

    // MARK: - Whole-project persistence

    /// The end-to-end case: a project carrying every kind of interpolation state saves and reloads
    /// with all of it intact. The per-cel recipe travels in its own file, the registries in the
    /// manifest, and the stroke tags inside the vector payload — three different places, one test.
    func testProjectWithInterpolationStateSurvivesSaveAndReload() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.projectName = "Interpolated"

        let group = manager.addMotionGroup(name: "Torso",
                                           tagColor: CodableColor(red: 1, green: 0.5, blue: 0, alpha: 1),
                                           mode: .crossFade)
        let strokeID = UUID()
        var stroke = sampleStroke(id: strokeID)
        stroke.visibilityThreshold = 0.6
        stroke.sampleVisibilityThresholds = [1: 0.8]
        try XCTUnwrap(manager.layers[1].cels[0].vector).addStroke(stroke)
        manager.setMotionGroup(group.id, forStrokeIDs: [strokeID])

        let layerID = manager.layers[1].id
        let celID = manager.layers[1].cels[0].id
        let celRef = CelRef(layerID: layerID, celID: celID)
        let guide = manager.addGuideStroke(
            GuideStroke(samples: [TimedSample(x: 0, y: 0, pressure: 1, time: 0),
                                  TimedSample(x: 30, y: 10, pressure: 1, time: 0.2)],
                        interval: KeyframeInterval(start: celRef, end: celRef),
                        boundGroups: [group.id], role: .both))

        var recipe = InterpolationRecipe(references: [InterpolationReference(cels: [celRef]),
                                                     InterpolationReference(cels: [celRef])],
                                         t: 0.375, mode: .generate)
        recipe.groups = [MotionGroupBinding(groupID: group.id,
                                            lattices: [deformedLattice(), deformedLattice()],
                                            guideIDs: [guide.id])]
        recipe.guideIDs = [guide.id]
        recipe.spacing = SpacingCurve(kind: .easeOut)
        manager.setInterpolation(recipe, forCel: celID, inLayer: layerID)

        let url = ProjectStore.createNewProjectURL(name: "Interpolated")
        saveAndWait(manager, to: url)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url), "The saved package should load")

        XCTAssertEqual(reloaded.motionGroups.map(\.id), [group.id])
        XCTAssertEqual(reloaded.motionGroups.first?.mode, .crossFade)
        XCTAssertEqual(reloaded.guideStrokes.map(\.id), [guide.id])
        XCTAssertEqual(reloaded.guideStrokes.first?.samples.last?.time, 0.2)

        let reloadedCel = try XCTUnwrap(reloaded.layers.first { $0.kind == .vector }?.cels.first)
        let reloadedRecipe = try XCTUnwrap(reloadedCel.interpolation, "The recipe must come back")
        XCTAssertEqual(reloadedRecipe.t, 0.375)
        XCTAssertEqual(reloadedRecipe.references.count, 2)
        XCTAssertEqual(reloadedRecipe.groups.first?.lattices, [deformedLattice(), deformedLattice()],
                       "Lattices come back exactly, deformation and active cells alike")
        XCTAssertEqual(reloadedRecipe.spacing, SpacingCurve(kind: .easeOut))

        let reloadedStroke = try XCTUnwrap(reloadedCel.vector?.strokes.first)
        XCTAssertEqual(reloadedStroke.motionGroupID, group.id)
        XCTAssertEqual(reloadedStroke.visibilityThreshold, 0.6)
        XCTAssertEqual(reloadedStroke.sampleVisibilityThresholds?[1], 0.8)
    }

    /// The other direction, and the one that protects every existing project: a document with no
    /// interpolation state at all reloads with none, and nothing about it changed.
    func testProjectWithoutInterpolationReloadsWithNone() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        try XCTUnwrap(manager.layers[1].cels[0].vector).addStroke(sampleStroke())

        let url = ProjectStore.createNewProjectURL(name: "Plain")
        saveAndWait(manager, to: url)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertTrue(reloaded.motionGroups.isEmpty)
        XCTAssertTrue(reloaded.guideStrokes.isEmpty)
        for layer in reloaded.layers {
            for cel in layer.cels {
                XCTAssertNil(cel.interpolation, "A cel that was never interpolated must load with no recipe")
            }
        }
        XCTAssertNil(reloaded.layers.first { $0.kind == .vector }?.cels.first?.vector?.strokes.first?.motionGroupID)
    }
}

private extension VectorStroke {
    /// A copy with a chosen id, so a test can name a stroke it later has to find again.
    func withID(_ id: UUID) -> VectorStroke {
        var copy = self
        copy.id = id
        return copy
    }
}
