import XCTest
import UIKit
import CoreGraphics

/// **KEYFRAMES.md §6 — Bake on an animated block**, against a real document.
///
/// The pin, said once: **a baked frame is the frame the animation rendered, byte for byte, on both
/// compositor backends, before a save and after a reload.** Everything else here is what makes that
/// pin honest (the animation really moves, the bake really cuts where the picture changes) or what
/// §6 asks beside it (fresh ids, the channels consumed, one undo step, the disclosed cost computed
/// rather than typed, a Repeat above the cel reading the source frames).
///
/// **Why the byte pin is the one that matters, and what it cost to make it hold.** The animated frame
/// walks the dab lattice in *rest* space and carries each dab through the pose (§4.2). Committing the
/// posed geometry through the affine Move path re-walks in posed space and re-phases the lattice —
/// on the Pencil, the brush this file draws with, on 24 frames of 24 — so the obvious bake is a
/// visibly different picture from the one the artist accepted. Storing `posing`'s transient walk
/// instead is right in memory and wrong after a reload. The bake therefore takes the projective
/// commit's persisted form for an affine map (`VectorCanvas.baking`), and the reload test below is
/// the assertion that justifies that choice: drop it and the in-memory pin still passes.
///
/// `@MainActor` because `makeRenderRequest` and `ProjectStore` are.
@MainActor
final class PoseBakeLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var box: CGRect { CGRect(x: 6, y: 20, width: 24, height: 12) }

    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A stroke of the fixture Pencil — `spacingFraction` 0.04, the brush §4.2 measured re-phasing
    /// on every frame of a posed slide, so a bake that re-walked would not pass the byte pin.
    private func stroke(_ points: [CGPoint], size strokeSize: CGFloat = 5,
                        brush: Brush = TestBrushes.pencil) -> VectorStroke {
        VectorStroke(id: UUID(), brush: brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: strokeSize, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    /// A manager with a vector layer (index 1) holding one cel over frames 0..<12 with two strokes
    /// in it — a bar and a short diagonal — drawn near the left so a 24 pt slide stays on the canvas.
    private func fixture() -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 8, y: 26), CGPoint(x: 14, y: 26), CGPoint(x: 20, y: 26),
                                      CGPoint(x: 26, y: 26)]))
        cel.vector?.addStroke(stroke([CGPoint(x: 9, y: 22), CGPoint(x: 15, y: 29)], size: 3))
        manager.layers[1].cels = [cel]
        return (manager, manager.layers[1].id, cel.id)
    }

    /// A pose that slides the box `dx` right and scales it by `scale` about its own origin — a
    /// scale so that the re-walk, if there were one, would change the dab count as well as the phase.
    private func moved(_ dx: CGFloat, scale: CGFloat = 1) -> PoseQuad {
        PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale))
    }

    /// A linear whole-cel channel from rest at frame 0 to `moved(dx, scale)` at frame 11, on `step`.
    private func animate(_ manager: CanvasManager, dx: CGFloat = 24, scale: CGFloat = 1.25, step: Int = 1) {
        manager.layers[1].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 11, pose: moved(dx, scale: scale), interpolation: .linear)],
                step: step)
        ]
    }

    private func onBothBackends(_ body: (CompositorBackend) throws -> Void) throws {
        for backend in [CompositorBackend.coreGraphics, .metal] {
            if backend == .metal, CompositorMetalEngine.shared == nil { continue }
            Compositor.backend = backend
            try body(backend)
        }
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "CoreGraphics ran; no Metal device or shader library in this bundle for the second backend")
    }

    /// The document's composite at `frame`, as bytes — what the artist sees, through the whole render
    /// path, with every memo cleared so a stale flatten cannot stand in for a render.
    private func compositeBytes(_ manager: CanvasManager, atFrame frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    /// **Two composites compared as bytes, reported as a summary rather than a dump** — how many
    /// bytes differ, the largest channel delta, and where the first differing pixel is — so a red
    /// says what kind of difference it found (one re-phased dab, or a whole stroke elsewhere).
    private func assertSameBytes(_ got: [UInt8], _ want: [UInt8], _ message: @autoclosure () -> String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard got.count == want.count else {
            return XCTFail("\(message()) — byte counts differ: \(got.count) vs \(want.count)", file: file, line: line)
        }
        var differing = 0, maxDelta = 0, first = -1
        for i in got.indices where got[i] != want[i] {
            differing += 1
            maxDelta = max(maxDelta, abs(Int(got[i]) - Int(want[i])))
            if first < 0 { first = i }
        }
        guard differing > 0 else { return }
        let w = Int(size.width)
        let pixel = first / 4
        XCTFail("\(message()) — \(differing) bytes differ (max delta \(maxDelta)), first at pixel "
                + "(\(pixel % w), \(pixel / w)) channel \(first % 4): got \(got[first]) want \(want[first])",
                file: file, line: line)
    }

    private func bake(_ manager: CanvasManager, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard case .baked(let cels) = manager.bakePoseToCels(layerIndex: 1, celIndex: 0) else {
            XCTFail("the bake refused an animated cel", file: file, line: line)
            return 0
        }
        return cels
    }

    private func elementIDs(_ manager: CanvasManager) -> [[UUID]] {
        manager.layers[1].cels.map { $0.vector?.elements.map(\.id) ?? [] }
    }


    // MARK: - Where it cuts

    /// **On twos, twelve frames bake to six cels of two frames each** — §2.10 and §6's *"24 cels,
    /// not 48"*, and the count the confirmation names is the count the bake makes.
    ///
    /// Watched failing with `poseBakeSegments` starting a new segment on every frame: 12 against 6,
    /// and the layout reads twelve one-frame cels.
    func testACelOnTwosOverTwelveFramesBakesToSixCelsOfTwoFrames() {
        let (manager, _, _) = fixture()
        animate(manager, step: 2)
        XCTAssertEqual(manager.poseBakeCelCount(layerIndex: 1, celIndex: 0), 6, "what the confirmation names")
        XCTAssertEqual(bake(manager), 6)
        XCTAssertEqual(CanvasFixture.celLayout(manager, layerIndex: 1).map { [$0.start, $0.length] },
                       [[0, 2], [2, 2], [4, 2], [6, 2], [8, 2], [10, 2]],
                       "one cel per held pair, cut where the held pose changes")
    }

    /// On ones the same animation is twelve one-frame cels — the count is the step's, not a constant.
    func testACelOnOnesBakesToOneCelPerFrame() {
        let (manager, _, _) = fixture()
        animate(manager, step: 1)
        XCTAssertEqual(bake(manager), 12)
        XCTAssertEqual(manager.layers[1].cels.count, 12)
        XCTAssertTrue(manager.layers[1].cels.allSatisfy { $0.frameCount == 1 })
    }

    /// **A hold past the last key is one cel, not a drawing per frame of it.** Keys at 0 and 4 on
    /// ones: frame 0 rests, 1–3 travel, and 4–11 all show the last key's pose — five pictures, so
    /// five cels, the last spanning eight frames. A bake never mints two cels of one picture.
    func testAHoldPastTheLastKeyBakesToOneCel() {
        let (manager, _, _) = fixture()
        manager.layers[1].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 4, pose: moved(16), interpolation: .linear)])
        ]
        XCTAssertEqual(bake(manager), 5)
        XCTAssertEqual(CanvasFixture.celLayout(manager, layerIndex: 1).map { [$0.start, $0.length] },
                       [[0, 1], [1, 1], [2, 1], [3, 1], [4, 8]])
    }

    /// **The segments are resolved on the uncut track.** `TransformTrack.split` re-phases the right
    /// half's step (its frame 0 is the cut), so a bake that re-read each half after cutting would
    /// bake a different animation from the one on screen. Pinned on the picture: on twos, every frame
    /// after the bake is the frame before it — which the byte test below asserts in full; this one
    /// asserts the shape that makes it possible, that the cut at an even frame did not move the held
    /// pose of the odd frame after it.
    func testSegmentsComeFromTheUncutTrackSoAStepIsNotRePhasedByTheCuts() throws {
        let (manager, _, _) = fixture()
        animate(manager, step: 2)
        let before = try (0..<12).map { try compositeBytes(manager, atFrame: $0) }
        XCTAssertEqual(before[10], before[11], "premise: on twos, 10 and 11 hold one pose")
        XCTAssertNotEqual(before[9], before[10], "premise: and 9 is a different one")
        _ = bake(manager)
        for frame in 0..<12 {
            assertSameBytes(try compositeBytes(manager, atFrame: frame), before[frame],
                           "frame \(frame) shows what it showed")
        }
    }

    // MARK: - The pin

    /// **Every baked frame is byte-identical to the animated frame, on both backends.** The fixture
    /// is a slide *and* a scale on the re-phasing brush, and the negative control is the animation
    /// itself: a middle frame differs from the resting one, so equal bytes after the bake are not
    /// equal because nothing moved.
    ///
    /// Watched failing with `VectorCanvas.baking` routed through `mapping(_:throughStretch:)` — the
    /// affine Move commit, which re-walks in posed space: every posed frame differed. That is §4.2's
    /// re-phase, and it is what this bake exists not to do.
    func testEveryBakedFrameIsByteIdenticalToTheAnimatedFrameOnBothBackends() throws {
        try onBothBackends { backend in
            let (manager, _, _) = fixture()
            animate(manager)
            let before = try (0..<12).map { try compositeBytes(manager, atFrame: $0) }
            XCTAssertNotEqual(before[0], before[6], "\(backend): premise — the animation moves")
            XCTAssertNotEqual(before[6], before[11], "\(backend): premise — and keeps moving")
            XCTAssertEqual(bake(manager), 12)
            for frame in 0..<12 {
                assertSameBytes(try compositeBytes(manager, atFrame: frame), before[frame],
                               "\(backend): frame \(frame) after the bake is the animated frame, byte for byte")
            }
            assertSameBytes(try compositeBytes(manager, atFrame: 6), before[6], "same bytes")
        }
    }

    /// **A group channel under a cel channel bakes what it showed.** The bar is in a group that
    /// slides on its own while the cel slides everything; the diagonal is carried by the cel alone.
    /// Both compose in `posed`'s order, and the bake goes through the same composition.
    func testAGroupChannelComposedWithTheCelChannelBakesByteIdentically() throws {
        let (manager, _, _) = fixture()
        let group = UUID()
        let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
        vector.elements = vector.elements.enumerated().map { index, element in
            guard index == 0, case .stroke(var bar) = element else { return element }
            bar.animationGroupID = group
            return .stroke(bar)
        }
        vector.bumpVersion()
        manager.layers[1].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 11, pose: moved(10), interpolation: .linear)]),
            TransformChannelID.group(group).id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 11, pose: PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: 8)),
                                   interpolation: .linear)])
        ]
        let before = try (0..<12).map { try compositeBytes(manager, atFrame: $0) }
        XCTAssertNotEqual(before[0], before[6], "premise — the animation moves")
        XCTAssertEqual(bake(manager), 12)
        for frame in 0..<12 {
            assertSameBytes(try compositeBytes(manager, atFrame: frame), before[frame],
                           "frame \(frame) after the bake is the animated frame")
        }
    }

    /// **The baked frame survives a save, and it reopens to the frame the *animated* document
    /// reopens to.** Stored as `posing`'s transient walk it would draw right until the document was
    /// reopened and re-walk after; stored through the affine commit it would re-walk from the start;
    /// stored as a posed spine pulled back through the map it would reopen an eighth of a pixel off,
    /// because `samples` are written quarter-pixel quantised. Only the rest spine kept beside the map
    /// — `StrokeDistort.rest`, packed as the animated stroke's own `samples` are — reloads to the same
    /// bytes, which is why the bake writes it.
    ///
    /// The honest operand is the reloaded animated document, since a reload quantises *its* spine
    /// too; on this integer fixture that is also the in-memory frame, and both are asserted.
    ///
    /// Watched failing with `baking` returning `posing`'s output (walk kept transient): in memory the
    /// byte test above still passes, and this one reads a re-walked frame 6 after the reload. And
    /// watched failing with `keepingRest: false` (the pull-back): frames 2, 9 and 10 lose a dab.
    func testABakedCelDrawsTheSameFrameAfterASaveAndReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose-bake-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let (manager, layerID, _) = fixture()
        animate(manager)
        let animated = try (0..<12).map { try compositeBytes(manager, atFrame: $0) }

        // The animated document, saved and reopened — what a reload of the *un*baked document shows.
        let animatedURL = root.appendingPathComponent("animated.paintproj", isDirectory: true)
        let savedAnimated = expectation(description: "the animated document is on disk")
        ProjectStore.save(manager, to: animatedURL) { savedAnimated.fulfill() }
        wait(for: [savedAnimated], timeout: 30)
        let reopenedAnimated = try XCTUnwrap(ProjectStore.load(from: animatedURL))
        for frame in 0..<12 {
            assertSameBytes(try compositeBytes(reopenedAnimated, atFrame: frame), animated[frame],
                            "premise: on this fixture the animated document reopens to its own frames (\(frame))")
        }

        XCTAssertEqual(bake(manager), 12)
        for frame in 0..<12 {
            assertSameBytes(try compositeBytes(manager, atFrame: frame), animated[frame], "premise: identical in memory (\(frame))")
        }
        let baked = try XCTUnwrap(manager.layers[1].cels[6].vector?.strokes.first?.distort,
                                  "the baked stroke carries its rest walk as a stored map, which is what survives")
        XCTAssertNotNil(baked.rest, "and the artist's own spine beside it — the pull-back is not exact")

        let url = root.appendingPathComponent("baked.paintproj", isDirectory: true)
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let layerIndex = try XCTUnwrap(reloaded.layers.firstIndex { $0.id == layerID })
        XCTAssertEqual(reloaded.layers[layerIndex].cels.count, 12, "twelve baked cels come back")
        XCTAssertTrue(reloaded.layers[layerIndex].cels.allSatisfy { $0.transformTracks.isEmpty },
                      "and none of them carries a channel")
        XCTAssertNotNil(reloaded.layers[layerIndex].cels[6].vector?.strokes.first?.distort?.rest,
                        "the stored spine survives the round trip")
        for frame in 0..<12 {
            assertSameBytes(try compositeBytes(reloaded, atFrame: frame),
                            try compositeBytes(reopenedAnimated, atFrame: frame),
                            "frame \(frame) of the reopened baked document is the reopened animated document's frame")
            assertSameBytes(try compositeBytes(reloaded, atFrame: frame), animated[frame],
                            "and, on this fixture, the frame the animation rendered before the save")
        }
    }

    // MARK: - What §6 asks beside the pin

    /// **Fresh ids on every element of every baked cel** — no baked element keeps the animated cel's
    /// id, and no two baked cels share one. `splitCel` copies with `makeCopy()`, which keeps ids, so
    /// without the re-mint every one of the twelve cels would alias the first.
    ///
    /// Watched failing with `reidentified()` dropped from `Self.baked`: every cel's ids equal the
    /// originals and each other.
    func testEveryBakedElementHasAFreshIdAndNoTwoBakedCelsShareOne() {
        let (manager, _, _) = fixture()
        animate(manager)
        let original = Set(elementIDs(manager).flatMap { $0 })
        XCTAssertEqual(original.count, 2, "premise: two elements")
        XCTAssertEqual(bake(manager), 12)
        let baked = elementIDs(manager)
        XCTAssertTrue(baked.allSatisfy { $0.count == 2 }, "every baked cel holds both elements")
        let all = baked.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count, "no id appears in two baked cels")
        XCTAssertTrue(original.isDisjoint(with: all), "no baked element keeps the animated cel's id")
        // And the tags stay: the bar's group survives the bake, so a later Move finds it.
        let group = UUID()
        let (tagged, _, _) = fixture()
        if let vector = tagged.layers[1].cels[0].vector, case .stroke(var bar) = vector.elements[0] {
            bar.animationGroupID = group
            vector.elements[0] = .stroke(bar)
        }
        animate(tagged)
        XCTAssertEqual(bake(tagged), 12)
        XCTAssertTrue(tagged.layers[1].cels.allSatisfy { $0.vector?.elements[0].stroke?.animationGroupID == group },
                      "the group tag rides onto every baked cel")
    }

    /// **The channels and the held baseline are gone from every baked cel** — the bake replaced the
    /// derivation with what it derived, and the menu no longer offers Bake on them.
    func testBakingClearsTheChannelsAndTheHeldBaselineOnEveryBakedCel() {
        let (manager, _, _) = fixture()
        animate(manager, step: 2)
        manager.layers[1].cels[0].pendingPoseBaselines = [TransformChannelID.cel.id: moved(-5)]
        XCTAssertTrue(manager.celHasPoseAnimation(layerIndex: 1, celIndex: 0), "premise: the row is offered")
        XCTAssertEqual(bake(manager), 6)
        for (index, cel) in manager.layers[1].cels.enumerated() {
            XCTAssertTrue(cel.transformTracks.isEmpty, "cel \(index) carries no channel")
            XCTAssertTrue(cel.pendingPoseBaselines.isEmpty, "cel \(index) holds no baseline")
            XCTAssertFalse(manager.celHasPoseAnimation(layerIndex: 1, celIndex: index))
            XCTAssertNil(manager.derivedCelContent(for: cel, atFrame: cel.startFrame),
                         "cel \(index) derives nothing — its picture is its own drawing")
        }
    }

    /// **One undo step restores the one animated cel, its channels, its baseline and its ink**, and
    /// every frame then renders what it rendered before the bake. Redo bakes it again.
    ///
    /// Watched failing with `touching: [vector]` dropped from the bracket: the cel comes back but
    /// its canvas still holds the baked, re-identified ink, and frame 6 renders the *first* baked
    /// picture at rest rather than the animated one.
    func testABakeIsOneUndoStepThatRestoresTheOneAnimatedCel() throws {
        let (manager, _, _) = fixture()
        animate(manager)
        manager.layers[1].cels[0].pendingPoseBaselines = [TransformChannelID.cel.id: moved(-5)]
        let tracksBefore = manager.layers[1].cels[0].transformTracks
        let idsBefore = elementIDs(manager)
        let framesBefore = try (0..<12).map { try compositeBytes(manager, atFrame: $0) }
        let steps = manager.history.undoStack.count

        XCTAssertEqual(bake(manager), 12)
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "one step, however many cels")

        manager.undo()
        XCTAssertEqual(manager.layers[1].cels.count, 1, "the one animated cel is back")
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks, tracksBefore, "with its channel")
        XCTAssertEqual(manager.layers[1].cels[0].pendingPoseBaselines[TransformChannelID.cel.id], moved(-5),
                       "and its held baseline")
        XCTAssertEqual(elementIDs(manager), idsBefore, "and its own ink under its own ids")
        for frame in 0..<12 {
            assertSameBytes(try compositeBytes(manager, atFrame: frame), framesBefore[frame],
                           "frame \(frame) renders the animation again")
        }

        manager.redo()
        XCTAssertEqual(manager.layers[1].cels.count, 12, "redo bakes it again")
        XCTAssertTrue(manager.layers[1].cels.allSatisfy { $0.transformTracks.isEmpty })
        assertSameBytes(try compositeBytes(manager, atFrame: 6), framesBefore[6], "same bytes")
    }

    /// A cel with no pose channel refuses with a named reason, and the menu hides the row.
    func testAnUnanimatedCelRefusesAndTheRowIsHidden() {
        let (manager, _, _) = fixture()
        XCTAssertFalse(manager.celHasPoseAnimation(layerIndex: 1, celIndex: 0))
        XCTAssertEqual(manager.poseBakeCelCount(layerIndex: 1, celIndex: 0), 1,
                       "an unanimated block is one picture")
        let steps = manager.history.undoStack.count
        XCTAssertEqual(manager.bakePoseToCels(layerIndex: 1, celIndex: 0), .refused(.notAnimated))
        XCTAssertEqual(manager.layers[1].cels.count, 1, "nothing was written")
        XCTAssertEqual(manager.history.undoStack.count, steps, "and no step was recorded")
        XCTAssertEqual(manager.bakePoseToCels(layerIndex: 7, celIndex: 0), .refused(.notAnimated),
                       "a cel that is not in the document refuses rather than trapping")
    }

    // MARK: - Under a Repeat

    /// **A bake under a Repeat reads the source frames** — TRANSFORM_LAYER.md §7's row: the repeat
    /// remaps the *read*, never the storage, so the cel's channels are numbered in the frames the
    /// repeat reads. The bake writes twelve cels over the block's own twelve frames and nothing
    /// past them, and every repeated document frame keeps showing the picture it showed.
    ///
    /// The Repeat's bar runs 0..<24 with period 12, so frames 12–23 show 0–11 again.
    func testABakeUnderARepeatReadsTheSourceFramesAndTheLoopStillShowsThem() throws {
        let (manager, _, _) = fixture()
        animate(manager)
        manager.addTransformLayer(name: "looper")
        let looper = try XCTUnwrap(manager.layers.firstIndex { $0.name == "looper" })
        CanvasFixture.setCelLayout(manager, layerIndex: looper, [(start: 0, length: 24)])
        manager.layers[looper].transform = LayerPose(pose: PoseQuad(restingIn: CGRect(origin: .zero, size: size)),
                                                     mode: .repeat, repeatPeriod: 12)
        let inkLayer = try XCTUnwrap(manager.layers.firstIndex { $0.kind == .vector })
        XCTAssertEqual(manager.leafFrames(atFrame: 18)[inkLayer], 6, "premise: frame 18 shows frame 6")

        let before = try (0..<24).map { try compositeBytes(manager, atFrame: $0) }
        XCTAssertEqual(before[18], before[6], "premise: the loop shows frame 6 at 18")
        XCTAssertNotEqual(before[18], before[12], "premise: and the loop is an animation")

        guard case .baked(let cels) = manager.bakePoseToCels(layerIndex: inkLayer, celIndex: 0) else {
            return XCTFail("the bake refused")
        }
        XCTAssertEqual(cels, 12)
        let layout = CanvasFixture.celLayout(manager, layerIndex: inkLayer)
        XCTAssertEqual(layout.count, 12, "twelve cels over the block's own frames")
        XCTAssertEqual(layout.last.map { $0.start + $0.length }, 12, "and nothing minted in the repeated span")
        for frame in 0..<24 {
            assertSameBytes(try compositeBytes(manager, atFrame: frame), before[frame],
                           "frame \(frame) — repeated or not — shows what it showed")
        }
    }

    // MARK: - The sentence

    /// **The confirmation's number is computed from the count and the measured rate, not typed.**
    /// Two different counts give two different costs, each equal to the arithmetic, and the count
    /// itself is in the sentence.
    ///
    /// Watched failing with the cost clause replaced by a typed `"about 0.4 s"`: the 6-cel and the
    /// 240-cel sentences carry the same clause and neither matches the arithmetic.
    func testTheConfirmationNamesTheCountAndAComputedCost() {
        let rate = CanvasManager.measuredSaveMillisecondsPerVectorCel
        XCTAssertGreaterThan(rate, 0)
        let six = CanvasManager.poseBakeConfirmationMessage(cels: 6)
        XCTAssertTrue(six.contains("6 drawings from 1"), six)
        XCTAssertTrue(six.contains(CanvasManager.saveCostPhrase(addedCels: 5, millisecondsPerCel: rate) + " longer"), six)
        XCTAssertTrue(six.contains("about \(Int((5 * rate).rounded())) ms longer"), six)
        XCTAssertTrue(six.contains("undone"), six)

        let many = CanvasManager.poseBakeConfirmationMessage(cels: 1000)
        XCTAssertTrue(many.contains("1000 drawings from 1"), many)
        XCTAssertTrue(many.contains(String(format: "about %.1f s longer", 999 * rate / 1000)), many)
        XCTAssertNotEqual(six, many)

        let one = CanvasManager.poseBakeConfirmationMessage(cels: 1)
        XCTAssertTrue(one.contains("1 drawing from 1"), one)
        XCTAssertFalse(one.contains("longer"), "one picture costs no extra save: \(one)")

        // The video bake's sentence is built the same way, on the raster rate.
        let raster = CanvasManager.measuredSaveMillisecondsPerRasterCel
        let video = CanvasManager.videoBakeConfirmationMessage(cels: 48)
        XCTAssertTrue(video.contains("48 cels of images"), video)
        XCTAssertTrue(video.contains("47 more cels"), video)
        XCTAssertTrue(video.contains(CanvasManager.saveCostPhrase(addedCels: 47, millisecondsPerCel: raster) + " more"), video)
    }
}
