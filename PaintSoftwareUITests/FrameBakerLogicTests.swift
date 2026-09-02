import XCTest
import UIKit
import SwiftUI

/// RENDER.md §5 stage 4c's pin on the **loop** — the serial worker that joins the key, the store,
/// the queue, the ring and the recipe.
///
/// **The acceptance test is §2.16 in the owner's own words**, and it is
/// `testEditingInsideACelSpanningTwoToSixRecompositesExactlyThoseFiveFrames`:
///
/// > *"If I had frame 1 through 10 and I edited something inside a cel which spanned frames 2 to 6,
/// > then only frames 2 to 6 would need to get re-rendered."*
///
/// **Composites are counted with `CompositeProbe`, never with a proxy for them.** The baker keeps
/// counters of its own (`bakedCount`, `dedupedCount`) and they are asserted too, but they are the
/// baker's own account of what it did — a probe inside `Compositor.composite` is the only thing that
/// can say a composite did or did not *happen*, which is the whole claim §2.16 makes.
///
/// **Every fixture is on a temp root** (`FrameBakeStore(root:)`) and forces `.coreGraphics` in
/// `setUp`, restoring `Compositor.defaultBackend` — not the literal — in `tearDown`, for the reason
/// `ChunkedCompositeLogicTests` writes out: restoring the literal is how one suite silently switches
/// every later suite in the process off the shipped backend.
@MainActor
final class FrameBakerLogicTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameBakerLogicTests-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        FrameBakeStore.cachesDirectoryOverride = nil
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        CompositeProbe.end()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeBaker(_ manager: CanvasManager,
                           ceiling: Int = FrameBakeStore.defaultByteCeiling,
                           ringBytes: Int = 32 * 1024 * 1024) -> FrameBaker {
        FrameBaker(manager: manager,
                   store: FrameBakeStore(root: root, byteCeiling: ceiling),
                   ring: DecodedFrameRing(byteBudget: ringBytes))
    }

    /// Runs the loop to a stop and returns the frames it visited, **in the order it visited them**.
    ///
    /// The loop is asynchronous by construction — main actor, serial queue, hop back — so there is no
    /// synchronous drain and deliberately none added: a second, test-only spelling of the loop would
    /// be a suite pinning something the app does not run (§2.15, and CLAUDE.md's banner-versus-count
    /// trap wearing a third costume). `onIdle` is the loop's own "nothing left", so waiting on it
    /// waits on exactly the thing under test.
    @discardableResult
    private func drain(_ baker: FrameBaker, timeout: TimeInterval = 60) -> [Int] {
        var order: [Int] = []
        var settled = false
        let idle = expectation(description: "the bake queue drains and the loop stops")
        baker.observeFrameFinished(self) { order.append($0) }
        baker.onIdle = {
            guard !settled else { return }
            settled = true
            idle.fulfill()
        }
        baker.kick()
        wait(for: [idle], timeout: timeout)
        baker.onIdle = nil
        baker.stopObservingFrameFinished(self)
        return order
    }

    /// A document whose every frame is a **different picture**, so every frame is its own bake key.
    ///
    /// One one-frame cel per frame on layer 0, each carrying its own content. That matters more than
    /// it looks: a document made of holds resolves many frames to one file by design (§3.3), which is
    /// exactly right for the app and useless for counting *which* frames were re-rendered. Where a
    /// test wants to count frames, the fixture has to make frames countable.
    private func perFrameDocument(frames: Int, extraLayers: Int = 0) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1 + extraLayers)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, (0..<frames).map { (start: $0, length: 1) })
        manager.sceneFrameCount = frames
        for frame in 0..<frames {
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: frame,
                                          CanvasFixture.solidImage(.red, rect: CGRect(x: frame * 2, y: 0,
                                                                                      width: 10, height: 10)))
        }
        return manager
    }

    /// Every frame index this manager lays out.
    private func allFrames(_ manager: CanvasManager) -> [Int] { Array(0..<manager.sceneFrameCount) }

    private func pending(_ baker: FrameBaker, _ manager: CanvasManager) -> [Int] {
        allFrames(manager).filter { baker.bakeQueue.isPending($0) }
    }

    private func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.count ?? 0
    }

    /// Composites recorded while `body` runs. `CompositeProbe` counts calls to
    /// `Compositor.composite`, so a frame cut into several chunks would count several times — every
    /// fixture here is a 64×64 canvas under the default budget, which `ChunkedCompositor` plans as
    /// exactly one chunk, and `testABakeOfOneFrameIsExactlyOneComposite` pins that so the arithmetic
    /// in every other test below is not a hope.
    private func composites(_ body: () -> Void) -> Int {
        CompositeProbe.begin()
        body()
        return CompositeProbe.end().count
    }

    // MARK: - The unit of measurement

    /// **The premise every count below rests on**: one frame is one call to `Compositor.composite`.
    ///
    /// If the fixture ever grew past one chunk this would go to 2 and every "5 composites" assertion
    /// in this file would be measuring chunks rather than frames. Stated as its own test so that
    /// failure names itself instead of arriving as five unrelated ones.
    func testABakeOfOneFrameIsExactlyOneComposite() {
        let manager = perFrameDocument(frames: 1)
        let baker = makeBaker(manager)
        let count = composites {
            baker.noteDocumentChanged()
            drain(baker)
        }
        XCTAssertEqual(count, 1, "A 64×64 frame under the default budget is one chunk, so one composite.")
        XCTAssertEqual(baker.bakedCount, 1)
        XCTAssertEqual(fileCount(), 1)
    }

    // MARK: - §2.16, the acceptance test

    /// **RENDER §2.16, in the owner's own words, as an executable claim.**
    ///
    /// > *"If I had frame 1 through 10 and I edited something inside a cel which spanned frames 2 to
    /// > 6, then only frames 2 to 6 would need to get re-rendered."*
    ///
    /// Ten frames; layer 0 gives each of them its own picture so that frames are countable; layer 1
    /// holds one cel spanning `[2, 7)`, which is frames 2 through 6 inclusive — `Cel.endFrame` is one
    /// past the last frame covered, which is the same half-open shape `BakeQueue.markDirty` takes.
    ///
    /// Three assertions, and they are three because any one of them alone can pass for the wrong
    /// reason. The dirty set says the *scheduler* reached exactly those five. The probe says exactly
    /// five composites *happened*. The keys say the five that moved are the five that changed picture
    /// and the other five kept the file they had — which is §3.3's claim that the key, not the dirty
    /// bit, is the proof.
    func testEditingInsideACelSpanningTwoToSixRecompositesExactlyThoseFiveFrames() {
        let manager = perFrameDocument(frames: 10, extraLayers: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 2, length: 5)])
        manager.sceneFrameCount = 10
        XCTAssertEqual(manager.layers[1].cels.map { ($0.startFrame, $0.endFrame) }.map(\.0), [2])
        XCTAssertEqual(manager.layers[1].cels[0].endFrame, 7,
                       "The cel must cover frames 2 through 6 inclusive — that is what §2.16 says.")

        let baker = makeBaker(manager)
        let firstPass = composites {
            baker.noteDocumentChanged()
            drain(baker)
        }
        XCTAssertEqual(firstPass, 10, "Ten distinct pictures is ten composites the first time.")
        let before = baker.keyByFrame
        XCTAssertEqual(before.count, 10)

        // The edit: one image into the cel that spans 2…6. Frame 4 is inside it, and
        // `setBakedContent` resolves the cel covering that frame rather than an index.
        CanvasFixture.setBakedContent(manager, layerIndex: 1, frame: 4,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 4, y: 4, width: 30, height: 30)))

        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [2, 3, 4, 5, 6],
                       "Only the frames the edited cel spans may be scheduled.")

        let secondPass = composites { drain(baker) }
        XCTAssertEqual(secondPass, 5, "Exactly five frames may be re-rendered, and no more.")
        XCTAssertEqual(baker.bakedCount, 15, "Ten the first time, five the second.")
        XCTAssertEqual(baker.dedupedCount, 0)

        let after = baker.keyByFrame
        for frame in [2, 3, 4, 5, 6] {
            XCTAssertNotEqual(before[frame], after[frame],
                              "Frame \(frame) is inside the edited cel and its key must have moved.")
        }
        for frame in [0, 1, 7, 8, 9] {
            XCTAssertEqual(before[frame], after[frame],
                           "Frame \(frame) is outside the edited cel and must keep the file it had.")
        }
    }

    /// The same edit again, and the second time it costs **nothing** — the change did not move, so
    /// nothing did. This is the difference between "only the frames that matter are rebaked" and
    /// "the frames that matter are rebaked, repeatedly".
    func testASweepThatFindsNothingSchedulesNothing() {
        let manager = perFrameDocument(frames: 10)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        let again = composites {
            baker.syncDirty()
            XCTAssertEqual(pending(baker, manager), [], "An unchanged document schedules no frame at all.")
            drain(baker)
        }
        XCTAssertEqual(again, 0)
    }

    // MARK: - The half of a cel's picture `LayerContentVersion` cannot see

    /// The box every pose in this file is read off, and the one the bar sits inside.
    private var posedBox: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }

    /// Ten countable frames, plus a vector cel over `[2, 7)` holding one bar, posed by a whole-cel
    /// channel with keys at cel-local 0 (resting) and 4 (slid 20 right).
    private func posedDocument() -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = perFrameDocument(frames: 10)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: 2, frameCount: 5,
                      raster: .empty(size: CanvasFixture.canvasSize),
                      vector: .empty(size: CanvasFixture.canvasSize))
        cel.vector?.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                           color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                           size: 6, opacity: 1,
                                           samples: [VectorSample(x: 6, y: 10, pressure: 1),
                                                     VectorSample(x: 18, y: 10, pressure: 1)]))
        manager.layers[1].cels = [cel]
        let layerID = manager.layers[1].id
        manager.setTransformPoseKey(layerID: layerID, celID: cel.id, channel: .cel,
                                    atCelLocalFrame: 0, pose: PoseQuad(restingIn: posedBox))
        manager.setTransformPoseKey(layerID: layerID, celID: cel.id, channel: .cel,
                                    atCelLocalFrame: 4,
                                    pose: PoseQuad(box: posedBox,
                                                   mappedBy: CGAffineTransform(translationX: 20, y: 0)))
        return (manager, layerID, cel.id)
    }

    /// **Dragging a pose keyframe dirties the span of the cel it poses** — KEYFRAMES.md stage 5's
    /// channel meeting §3.6's sweep.
    ///
    /// `Cel.transformTracks` is the one thing a cel's picture depends on that `LayerContentVersion`
    /// cannot supply. A pose is a *derivation*: the identity naming it reaches
    /// `LayerContentVersion.derived` only where a caller resolves the derivation, and the sweep
    /// deliberately does not. Nothing else moves either — `commitCelPoseState` writes the track,
    /// schedules a thumbnail and publishes, and bumps no tier's version counter — so a `CelStamp` that
    /// does not carry the tracks sees an unchanged document, schedules nothing, and leaves the artist
    /// looking at the picture from before the edit until something else dirties that span.
    ///
    /// **Three assertions, and they are three because any one of them can pass for the wrong reason.**
    /// The dirty set says the scheduler reached the span. The keys say the picture actually moved on
    /// the four frames whose resolved pose changed — which is also the only thing that can prove the
    /// pose reaches the bake *key*, not merely the dirty bit. The composite count says frame 2, inside
    /// the span but resolving to the resting pose it already had, cost one mint and no render, which
    /// is §3.3's claim that over-marking is cheap by construction.
    func testEditingAPoseKeyframeDirtiesTheCelsSpan() {
        let (manager, layerID, celID) = posedDocument()
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        let before = baker.keyByFrame
        XCTAssertEqual(before.count, 10)

        // The edit: the key at cel-local 4 — frame 6 — dragged further right. Frames 3 through 6
        // resolve to a new map; frame 2 is the resting key and resolves to the one it had.
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 4,
                                    pose: PoseQuad(box: posedBox,
                                                   mappedBy: CGAffineTransform(translationX: 34, y: 0)))

        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [2, 3, 4, 5, 6],
                       "A pose edit must dirty the span of the cel it posed.")

        let second = composites { drain(baker) }
        XCTAssertEqual(second, 4, "Four frames changed picture; frame 2 keeps the resting pose it had.")

        let after = baker.keyByFrame
        for frame in [3, 4, 5, 6] {
            XCTAssertNotEqual(before[frame], after[frame],
                              "Frame \(frame) resolves to a new pose, so its key must have moved.")
        }
        for frame in [0, 1, 2, 7, 8, 9] {
            XCTAssertEqual(before[frame], after[frame],
                           "Frame \(frame) shows what it showed, so it must keep the file it had.")
        }
    }

    /// **Undoing the pose edit dirties the span again.** The sweep is what makes undo work at all
    /// here — nothing in the stored undo closure reaches the baker, and `applyCelPoseState` is the one
    /// mutation both directions go through — so a stamp that misses the tracks misses the undo too,
    /// and this is the half an artist notices first.
    func testUndoingAPoseKeyframeEditDirtiesTheCelsSpanAgain() {
        let (manager, layerID, celID) = posedDocument()
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        let before = baker.keyByFrame

        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 4,
                                    pose: PoseQuad(box: posedBox,
                                                   mappedBy: CGAffineTransform(translationX: 34, y: 0)))
        baker.syncDirty()
        drain(baker)

        manager.undo()
        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [2, 3, 4, 5, 6],
                       "Undoing a pose edit must dirty the span the edit dirtied.")

        let back = composites { drain(baker) }
        XCTAssertEqual(back, 0, "Every frame is back to a picture the store already holds.")
        XCTAssertEqual(baker.keyByFrame, before,
                       "An undone edit must leave every frame naming the file it named before it.")
    }

    /// **An edit that lands while a bake is in flight is not swallowed by that bake's completion.**
    ///
    /// The race is real and reachable from the loop's own shape: `kick` mints the key on the main
    /// actor and hops to `workQueue`, `BakeQueue.next` does not consume, and `syncDirty` marking an
    /// already-dirty frame is a no-op — so a sweep between the mint and the hop back does its job and
    /// leaves no trace of having done it. A `finish` that clears the bit regardless discards it.
    ///
    /// **The fixture is deterministic rather than timed**, and that is what makes it worth having:
    /// everything between `kick()` and the next suspension point runs while this test holds the main
    /// actor, so the composite's `Task { @MainActor in }` hop *cannot* land in the middle of it. The
    /// edit is therefore guaranteed to be the mid-flight one.
    func testAnEditLandingDuringABakeIsNotClearedByIt() {
        let manager = perFrameDocument(frames: 3)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()

        // Synchronous: mints frame 0's key and dispatches its composite. Nothing can hop back yet.
        baker.kick()
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 1, y: 1, width: 20, height: 20)))
        baker.syncDirty()

        drain(baker)
        XCTAssertEqual(pending(baker, manager), [],
                       "The loop must settle — the edit is baked, not merely re-marked forever.")
        XCTAssertEqual(baker.keyByFrame[0], baker.currentKey(atFrame: 0),
                       "Frame 0 must end up naming the file for the picture the document actually has.")
    }

    // MARK: - The two stamps' other blind spots

    /// **A folder's animated grade dirties the document.** A folder's effect is carried by no
    /// `LayerContentVersion` — it is not a cel's content — and `renderTree(atFrame: 0)` sees only what
    /// the grade resolves to at frame 0, so a curve edited to change frame 2 and not frame 0 is
    /// visible in exactly one place: the tracks the structural stamp holds.
    func testAnAnimatedFolderGradeIsAStructuralChange() {
        let manager = perFrameDocument(frames: 3)
        let folder = manager.addFolder(name: "Graded")
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(pending(baker, manager), [])

        let index = try? XCTUnwrap(manager.folders.firstIndex { $0.id == folder })
        guard let index else { return XCTFail("The folder just added must be in `folders`.") }
        // Frame 0 is deliberately left where it was: a stamp reading the tree at frame 0 alone
        // cannot tell this apart from no edit, which is the whole reason the tracks are stamped.
        manager.folders[index].effectTracks["bloom.intensity"] =
            AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 0),
                                  AnimationCurve.Key(frame: 2, value: 1)])

        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [0, 1, 2],
                       "§3.6 rules a structural edit dirties every frame, and a folder's grade is one.")
    }

    /// **Retiming an in-between dirties its span**, which no other tier of the sweep can do for it.
    ///
    /// Tier 3 exists for an in-between whose *referenced* cel moved and is gated on `touchedACel`;
    /// a retime moves no cel at all, so that gate is shut. The recipe is stamped in `CelStamp`
    /// instead, and tier 1 marks exactly this cel's own span — which is tighter than tier 3 would
    /// have been anyway.
    func testRetimingAnInBetweenDirtiesItsOwnSpanAndNothingElse() {
        let manager = perFrameDocument(frames: 6)
        CanvasFixture.setCelLayout(manager, layerIndex: 0,
                                   [(start: 0, length: 2), (start: 2, length: 2), (start: 4, length: 2)])
        manager.sceneFrameCount = 6
        for (index, frame) in [0, 2, 4].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: frame,
                                          CanvasFixture.solidImage(.red, rect: CGRect(x: index * 6, y: 0,
                                                                                      width: 10, height: 10)))
        }
        let cels = manager.layers[0].cels
        manager.layers[0].cels[1].interpolation = InterpolationRecipe(
            references: [InterpolationReference(layerID: manager.layers[0].id, celID: cels[0].id),
                         InterpolationReference(layerID: manager.layers[0].id, celID: cels[2].id)],
            t: 0.5)

        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(pending(baker, manager), [])

        // The whole of a retime: `setInterpolationT` writes this field and nothing else — no cel is
        // touched, no tier object's version moves.
        manager.layers[0].cels[1].interpolation?.t = 0.25

        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [2, 3],
                       "Only the in-between's own span, and it must not be empty.")
    }

    // MARK: - §3.3, the dedupe the whole key design was built for

    /// **A nine-frame hold is one file and one composite**, end to end.
    ///
    /// This is the claim `FrameBakeKey` leaves `frame` out of the key to make: a hold is one `Cel`,
    /// so every frame of it has byte-identical leaf versions and an identical tree, and the nine
    /// frames resolve to one digest. Eight of the nine cost one O(layers) mint and one `stat`.
    func testANineFrameHoldIsOneFileAndOneComposite() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 9)])
        manager.sceneFrameCount = 9
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.green, rect: CGRect(x: 8, y: 8, width: 40, height: 40)))

        let baker = makeBaker(manager)
        let count = composites {
            baker.noteDocumentChanged()
            drain(baker)
        }

        XCTAssertEqual(count, 1, "Nine frames of one hold are one picture, so one composite.")
        XCTAssertEqual(fileCount(), 1, "…and one file.")
        XCTAssertEqual(baker.bakedCount, 1)
        XCTAssertEqual(baker.dedupedCount, 8, "The other eight found the file the first one wrote.")
        XCTAssertEqual(Set(baker.keyByFrame.keys), Set(0..<9), "Every frame must resolve to something.")
        XCTAssertEqual(baker.framesByDigest.count, 1, "One digest…")
        XCTAssertEqual(baker.framesByDigest.values.first, Set(0..<9), "…named by all nine frames.")
    }

    /// **Scrubbing through a hold costs zero composites**, however coarsely it is marked.
    ///
    /// The playhead walks all nine frames of the hold and every frame is marked dirty at every step —
    /// the coarsest hint the scheduler can be given, and far coarser than a scrub actually produces.
    /// Nothing composites, because §3.3's exact test is the key and the key has a file. That is what
    /// makes dirty marking safe to be sloppy about.
    func testAScrubThroughAHoldCostsNoComposites() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 9)])
        manager.sceneFrameCount = 9
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.green, rect: CGRect(x: 4, y: 4, width: 20, height: 20)))

        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        let bakedBefore = baker.bakedCount

        let count = composites {
            for frame in 0..<9 {
                manager.currentFrame = frame
                baker.markEverythingDirty()
                drain(baker)
            }
        }
        XCTAssertEqual(count, 0, "Every frame of the hold already has its file.")
        XCTAssertEqual(baker.bakedCount, bakedBefore, "Nothing was written either.")
        XCTAssertEqual(fileCount(), 1)
    }

    // MARK: - §2.10, the order

    /// **The frame the artist is on is baked first**, so they can keep drawing (§2.10).
    ///
    /// The whole document is marked dirty with the playhead parked on 5, and 5 is what comes back
    /// first — ahead of frame 0, which a queue that simply walked the document would have taken.
    func testThePlayheadsFrameIsBakedFirst() {
        let manager = perFrameDocument(frames: 10)
        manager.currentFrame = 5

        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        let order = drain(baker)

        XCTAssertEqual(order.count, 10, "Every frame must be visited exactly once.")
        XCTAssertEqual(order.first, 5, "§2.10: the frame the artist is on goes first.")
        guard let indexOfZero = order.firstIndex(of: 0) else { return XCTFail("Frame 0 must be baked.") }
        XCTAssertGreaterThan(indexOfZero, 0, "Frame 0 must not beat the playhead's own frame.")
        XCTAssertEqual(Set(order), Set(0..<10))
    }

    // MARK: - §3.6, structural edits

    /// A structural edit dirties every frame — §3.6 rules it outright, and layer opacity is the
    /// shortest thing that is one.
    func testAStructuralEditDirtiesEveryFrame() {
        let manager = perFrameDocument(frames: 10)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(pending(baker, manager), [])

        manager.layers[0].opacity = 0.5
        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), Array(0..<10),
                       "Opacity is not confined to a cel's span, so it reaches every frame.")

        let count = composites { drain(baker) }
        XCTAssertEqual(count, 10, "A different opacity is a different picture at every frame.")
        XCTAssertEqual(fileCount(), 20, "Ten new files beside the ten the first pass wrote.")
    }

    /// **The gap a single probe frame cannot see, and the field that closes it.**
    ///
    /// `StructuralStamp` reads `renderTree(atFrame: 0)` — one probe frame, fixed so that scrubbing
    /// does not read as a structural change. An animation curve on an effect parameter is invisible
    /// there whenever it does not move frame 0, and `effectTracks` is the field in the stamp that
    /// catches it anyway.
    ///
    /// The test proves its own premise rather than assuming it: the tree at the probe frame is
    /// asserted **identical** either side of the edit, so a green result cannot come from the tree
    /// having noticed. Deleting `effectTracks` from `StructuralStamp` takes this test red and no
    /// other.
    ///
    /// It marks every frame for a track that reaches no pixel on this raster layer, and that is
    /// deliberate over-marking rather than a bug: §3.3 makes it cost one mint and no composite, and
    /// the alternative — asking whether the track reaches a pixel — is the "which field did I
    /// forget" hazard that a content-addressed store punishes with a wrong picture and no error.
    func testAnEffectTrackEditIsCaughtEvenThoughTheProbeFrameCannotSeeIt() {
        let manager = perFrameDocument(frames: 10)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(pending(baker, manager), [])

        let treeBefore = manager.renderTree(atFrame: 0)
        manager.layers[0].effectTracks["intensity"] =
            AnimationCurve(keys: [.init(frame: 0, value: 1), .init(frame: 7, value: 0.25)])
        XCTAssertEqual(manager.renderTree(atFrame: 0), treeBefore,
                       "The premise: the probe frame's tree must be unchanged, or this test proves nothing.")

        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), Array(0..<10),
                       "An animated effect parameter must dirty the document even when frame 0 is unmoved.")
    }

    /// A cel that **slid** dirties where it was as well as where it is. Both halves, because the
    /// frames it left show something else now.
    func testACelThatMovedDirtiesBothItsOldSpanAndItsNew() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, (0..<10).map { (start: $0, length: 1) })
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 1, length: 2)])
        manager.sceneFrameCount = 10

        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(pending(baker, manager), [])

        manager.layers[1].cels[0].startFrame = 6
        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [1, 2, 6, 7],
                       "Where it was and where it is, and nothing in between.")
    }

    /// A deleted cel dirties the span it used to cover. Nothing else knows those frames changed —
    /// the cel is gone, so a sweep that only looked at what is there would see nothing at all.
    func testADeletedCelDirtiesTheSpanItUsedToCover() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, (0..<10).map { (start: $0, length: 1) })
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 3, length: 3)])
        manager.sceneFrameCount = 10

        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        manager.layers[1].cels.removeAll()
        baker.syncDirty()
        XCTAssertEqual(pending(baker, manager), [3, 4, 5])
    }

    // MARK: - The loop itself

    /// **It drains and stops rather than spinning**, and a kick against a drained queue composites
    /// nothing. `isBaking` false at rest is the other half: a loop that stopped while still holding
    /// its own mutual-exclusion flag would never start again.
    func testTheLoopDrainsAndStops() {
        let manager = perFrameDocument(frames: 6)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        XCTAssertEqual(baker.bakeQueue.pendingCount, 0)
        XCTAssertFalse(baker.isBaking, "The loop must not still hold its own lock at rest.")

        let idle = composites { drain(baker) }
        XCTAssertEqual(idle, 0, "Kicking a drained queue composites nothing.")
        XCTAssertEqual(baker.bakedCount, 6)
    }

    /// **Never two composites at once.** The loop is serial by construction — one job is in flight
    /// at a time and `finish` is what starts the next — so a second kick landing mid-bake must not
    /// dispatch a second job. Ten kicks in a row are one job.
    func testKickingRepeatedlyDoesNotStartASecondComposite() {
        let manager = perFrameDocument(frames: 8)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        XCTAssertTrue(baker.isBaking, "The first kick must have a job in flight.")

        let count = composites {
            for _ in 0..<10 { baker.kick() }
            drain(baker)
        }
        XCTAssertEqual(count, 8, "Eight frames, eight composites — the extra kicks bought nothing.")
        XCTAssertEqual(baker.bakedCount, 8)
    }

    // MARK: - §3.5, a write failure is a bake failure

    /// **Disk full leaves the document untouched and the loop running** (§3.5, §2.10).
    ///
    /// A ceiling of eight bytes is smaller than the 64-byte header, so every write is refused with
    /// `exceedsCeiling` before a byte is written. What must survive that: every frame is still
    /// visited (the loop did not stop at the first refusal), nothing is left pending (it did not spin
    /// either), the store holds nothing, and the model is exactly as it was.
    func testAStoreThatCannotWriteLeavesTheDocumentUntouchedAndTheLoopRunning() {
        let manager = perFrameDocument(frames: 10)
        let celCount = manager.layers[0].cels.count
        let firstCelHasContent = manager.layers[0].cels[0].bakedImage != nil

        let baker = makeBaker(manager, ceiling: 8)
        baker.noteDocumentChanged()
        let order = drain(baker)

        XCTAssertEqual(order.count, 10, "Every frame must still be visited — the loop continues.")
        XCTAssertEqual(baker.failedCount, 10)
        XCTAssertEqual(baker.bakedCount, 0)
        XCTAssertEqual(baker.bakeQueue.pendingCount, 0,
                       "A spent hint is not re-raised, or the loop would spin on an unwritable disk.")
        XCTAssertEqual(baker.store.totalBytes, 0)
        XCTAssertEqual(fileCount(), 0)
        XCTAssertTrue(baker.keyByFrame.isEmpty, "Nothing may claim a file that was never written.")
        XCTAssertTrue(baker.framesByDigest.isEmpty)
        if case .exceedsCeiling = baker.lastWriteFailure {} else {
            XCTFail("The refusal must be the ceiling one: \(String(describing: baker.lastWriteFailure))")
        }

        XCTAssertEqual(manager.layers.count, 1, "The document is untouched.")
        XCTAssertEqual(manager.layers[0].cels.count, celCount)
        XCTAssertEqual(manager.layers[0].cels[0].bakedImage != nil, firstCelHasContent)
        XCTAssertEqual(manager.sceneFrameCount, 10)
    }

    /// A refused frame is a **miss** on the read path, not a wrong picture. §2.10's "the previous
    /// picture stays" is only safe because the frame that was never written reads back as nil.
    func testAFrameThatCouldNotBeWrittenReadsBackAsAMiss() {
        let manager = perFrameDocument(frames: 3)
        let baker = makeBaker(manager, ceiling: 8)
        baker.noteDocumentChanged()
        drain(baker)

        for frame in 0..<3 {
            XCTAssertNil(baker.image(atFrame: frame), "Frame \(frame) was never written.")
            XCTAssertFalse(baker.isBaked(atFrame: frame))
        }
    }

    // MARK: - The read path stage 4d wires

    /// Ring, then store, then nothing — and what comes back is the frame that was baked.
    func testTheReadPathAnswersWithTheFrameThatWasBaked() {
        let manager = perFrameDocument(frames: 4)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        for frame in 0..<4 {
            XCTAssertTrue(baker.isBaked(atFrame: frame))
            guard let image = baker.image(atFrame: frame) else {
                return XCTFail("Frame \(frame) is on disk and must come back.")
            }
            // **The live canvas's size, not the canvas's** — stage 4d mints the bake at
            // `.liveComposite` so the bake and the two mid-stroke halves share one
            // `PixelOps.rasterize` memo (`FrameBaker.recipe`). The two agree on any document the
            // knob has not been moved on, which is every fixture here; derived rather than written
            // out so that this states the coupling instead of hiding it behind a coincidence.
            XCTAssertEqual(CGSize(width: image.width, height: image.height),
                           manager.liveCompositeSize(of: manager.renderTree(atFrame: frame),
                                                     canvasSize: CanvasFixture.canvasSize))
        }
    }

    /// **`currentKey` is minted from the model, not looked up.** §3.3: the display path computes the
    /// current frame's key to find its file, and a key with no file shows the previous picture. A
    /// lookup in `keyByFrame` would answer with what the baker last saw — which is exactly the stale
    /// answer that section forbids.
    func testTheDisplayPathsKeyMovesWithTheModelRatherThanWithTheBaker() {
        let manager = perFrameDocument(frames: 3)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        let recorded = baker.keyByFrame[1]
        XCTAssertEqual(baker.currentKey(atFrame: 1), recorded)

        // An edit the baker has not been told about at all.
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 1,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 2, y: 2, width: 20, height: 20)))

        XCTAssertNotEqual(baker.currentKey(atFrame: 1), recorded,
                          "The key is derived from the model, so it moved the moment the model did.")
        XCTAssertNil(baker.image(atFrame: 1),
                     "A key with no file is a miss — §2.10's previous picture, never a stale one.")
        XCTAssertEqual(baker.keyByFrame[1], recorded,
                       "The baker's own record is what is stale, which is why nothing reads it for a picture.")
    }

    /// **The ring is filled ahead of the playhead, and only ahead of it** (§3.5).
    ///
    /// Lookahead 3 with the playhead on 0 admits frames 0, 1, 2 and 3 and nothing else — play never
    /// decodes on the display thread, and the frames behind are not what play is about to want.
    func testTheRingIsFilledAheadOfThePlayhead() {
        let manager = perFrameDocument(frames: 10)
        manager.currentFrame = 0

        let baker = makeBaker(manager)
        baker.ringLookahead = 3
        baker.noteDocumentChanged()
        drain(baker)

        XCTAssertEqual(baker.ring.count, 4, "The playhead's frame and the three ahead of it.")
        for frame in 0...3 {
            guard let key = baker.keyByFrame[frame] else { return XCTFail("Frame \(frame) must be baked.") }
            XCTAssertTrue(baker.ring.contains(key.fileName), "Frame \(frame) is inside the lookahead.")
        }
        for frame in 4..<10 {
            guard let key = baker.keyByFrame[frame] else { return XCTFail("Frame \(frame) must be baked.") }
            XCTAssertFalse(baker.ring.contains(key.fileName),
                           "Frame \(frame) is past the lookahead and belongs on disk only.")
        }
    }

    /// A hold is one entry in the ring as well as one file — the ring is keyed by digest for the same
    /// reason the store is, and nine frames of a hold must not be nine copies of one picture in
    /// memory on a device this feature exists to fit inside.
    func testAHoldIsOneRingEntryForAllOfItsFrames() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 9)])
        manager.sceneFrameCount = 9
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.green, rect: CGRect(x: 1, y: 1, width: 30, height: 30)))

        let baker = makeBaker(manager)
        baker.ringLookahead = 100
        baker.noteDocumentChanged()
        drain(baker)

        XCTAssertEqual(baker.ring.count, 1, "Nine frames, one digest, one resident frame.")
        let composited = manager.liveCompositeSize(of: manager.renderTree(atFrame: 0),
                                                   canvasSize: CanvasFixture.canvasSize)
        XCTAssertEqual(baker.ring.byteCount, Int(composited.width * composited.height) * 4)
    }

    // MARK: - Bookkeeping

    /// The digest→frames map is the baker's alone, and it must stay in step in **both** directions —
    /// the store's playhead-distance eviction reads it to answer "how far is the nearest frame that
    /// still wants this file", and a stale entry there evicts the wrong file.
    func testTheDigestToFramesMapFollowsTheFramesItNames() {
        let manager = perFrameDocument(frames: 4)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        XCTAssertEqual(baker.framesByDigest.count, 4)
        for (frame, key) in baker.keyByFrame {
            XCTAssertEqual(baker.framesByDigest[key.fileName], [frame])
        }

        let oldKey = baker.keyByFrame[2]!
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 2,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 1, y: 1, width: 40, height: 40)))
        baker.noteDocumentChanged()
        drain(baker)

        XCTAssertNil(baker.framesByDigest[oldKey.fileName],
                     "The file frame 2 used to name is named by nothing now.")
        XCTAssertEqual(baker.framesByDigest[baker.keyByFrame[2]!.fileName], [2])
        XCTAssertEqual(baker.framesByDigest.count, 4)
    }

    /// `reset()` forgets everything the baker believes and leaves the store alone — purging is
    /// §2.11's own call, made by the app, not a side effect of dropping bookkeeping.
    func testResetForgetsTheBookkeepingAndNotTheStore() {
        let manager = perFrameDocument(frames: 4)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(fileCount(), 4)

        baker.reset()
        XCTAssertTrue(baker.keyByFrame.isEmpty)
        XCTAssertTrue(baker.framesByDigest.isEmpty)
        XCTAssertEqual(baker.bakeQueue.pendingCount, 0)
        XCTAssertEqual(baker.ring.count, 0)
        XCTAssertEqual(baker.bakedCount, 0)
        XCTAssertEqual(fileCount(), 4, "The files on disk are not the baker's to throw away.")

        // And the store is still the truth: everything comes back as a dedupe, not a re-bake.
        let count = composites {
            baker.noteDocumentChanged()
            drain(baker)
        }
        XCTAssertEqual(count, 0)
        XCTAssertEqual(baker.dedupedCount, 4)
    }

    /// A scene that shrinks must not leave the baker asking for frames the document no longer has.
    func testASceneThatShrinksDropsTheFramesItNoLongerHas() {
        let manager = perFrameDocument(frames: 10)
        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)

        manager.sceneFrameCount = 4
        baker.syncDirty()
        XCTAssertEqual(baker.bakeQueue.frameCount, 4)
        XCTAssertEqual(pending(baker, manager), Array(0..<4),
                       "The scene length is in the structural stamp, so the shorter scene is a re-bake…")
        for frame in 4..<10 {
            XCTAssertFalse(baker.bakeQueue.isPending(frame), "…and frame \(frame) is not in it.")
        }
    }

    // MARK: - §3.7, what the timeline's baked-frame indication reads

    /// **`isBaked` before, during and after** — a frame the baker has never reached, the same frame
    /// once it has, and the whole document once the loop has drained.
    func testIsBakedIsFalseUntilTheLoopHasActuallyReachedTheFrame() {
        let manager = perFrameDocument(frames: 4)
        let baker = makeBaker(manager)

        for frame in 0..<4 {
            XCTAssertFalse(baker.isBaked(atFrame: frame),
                           "Nothing has been baked yet, so nothing may claim to be.")
        }

        baker.noteDocumentChanged()
        for frame in 0..<4 {
            XCTAssertFalse(baker.isBaked(atFrame: frame),
                           "The sweep has scheduled frame \(frame); scheduling is not baking.")
        }

        drain(baker)
        for frame in 0..<4 {
            XCTAssertTrue(baker.isBaked(atFrame: frame), "Frame \(frame) has a file now.")
        }
        XCTAssertFalse(baker.isBaked(atFrame: 4),
                       "Frame 4 is past the end of a four-frame scene and was never baked.")
    }

    /// **The load-bearing half: an edit un-bakes the frames it reaches, and the file it had is still
    /// sitting there.**
    ///
    /// `keyByFrame` is not cleared by an edit — entries are only forgotten on a *failure* — so the
    /// five keys covering the edited cel still name five real files that still exist on disk. They
    /// are the picture from *before* the edit. An `isBaked` that answered from `keyByFrame` alone
    /// would therefore report every one of them baked, and the timeline would say a stretch was
    /// ready to play while showing the artist's own edit missing from it. The pending check is what
    /// makes that impossible, and this test is the pin on it: delete `!bakeQueue.isPending(frame) &&`
    /// from `FrameBaker.isBaked` and the middle block below goes green-to-red.
    func testAnEditUnbakesTheFramesItReachesThoughTheirOldFilesRemain() {
        let manager = perFrameDocument(frames: 10, extraLayers: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 2, length: 5)])
        manager.sceneFrameCount = 10

        let baker = makeBaker(manager)
        baker.noteDocumentChanged()
        drain(baker)
        let filesBefore = fileCount()
        XCTAssertEqual(allFrames(manager).filter { baker.isBaked(atFrame: $0) }, Array(0..<10),
                       "Setup: the whole scene is baked.")

        CanvasFixture.setBakedContent(manager, layerIndex: 1, frame: 4,
                                      CanvasFixture.solidImage(.blue,
                                                               rect: CGRect(x: 4, y: 4, width: 30, height: 30)))
        baker.syncDirty()

        XCTAssertEqual(allFrames(manager).filter { !baker.isBaked(atFrame: $0) }, [2, 3, 4, 5, 6],
                       "The five frames the edit reached are no longer ready to play…")
        XCTAssertEqual(allFrames(manager).filter { baker.isBaked(atFrame: $0) }, [0, 1, 7, 8, 9],
                       "…and the five it did not reach still are.")
        for frame in [2, 3, 4, 5, 6] {
            XCTAssertNotNil(baker.keyByFrame[frame],
                            "Frame \(frame) still has a recorded key — that is exactly the trap: it "
                            + "names a real file holding the picture from before the edit.")
        }
        XCTAssertEqual(fileCount(), filesBefore, "And that file is still on disk, unchanged.")

        drain(baker)
        XCTAssertEqual(allFrames(manager).filter { baker.isBaked(atFrame: $0) }, Array(0..<10),
                       "Once the loop has caught up, the whole scene is ready again.")
    }

    // MARK: - The observer registry

    /// **Two consumers, one event.** Stage 4d gave the single `onFrameFinished` slot to the canvas;
    /// §3.7's indication is the second listener, and the registry is what lets both have it without
    /// a second callback beside the first (§2.15).
    ///
    /// Delete either `observer.body(frame)` call site's loop in `notifyFrameFinished` — or reduce it
    /// to a single stored closure — and one of these two arrays comes back empty.
    func testEveryObserverIsToldAboutEveryFrame() {
        let manager = perFrameDocument(frames: 3)
        let baker = makeBaker(manager)
        let canvas = NSObject()
        let timeline = NSObject()
        var heardByCanvas: [Int] = []
        var heardByTimeline: [Int] = []
        baker.observeFrameFinished(canvas) { heardByCanvas.append($0) }
        baker.observeFrameFinished(timeline) { heardByTimeline.append($0) }

        baker.noteDocumentChanged()
        let visited = drain(baker)

        XCTAssertEqual(heardByCanvas.sorted(), visited.sorted())
        XCTAssertEqual(heardByTimeline.sorted(), visited.sorted())
        XCTAssertEqual(heardByCanvas.count, 3)
    }

    /// Registering twice from one owner replaces rather than stacks, which is what lets both callers
    /// install unconditionally on every pass; and an owner that has gone away is dropped rather than
    /// kept forever.
    func testAnOwnerRegistersOnceAndAnOwnerThatDiesIsForgotten() {
        let manager = perFrameDocument(frames: 2)
        let baker = makeBaker(manager)
        let owner = NSObject()
        var first = 0
        var second = 0
        baker.observeFrameFinished(owner) { _ in first += 1 }
        baker.observeFrameFinished(owner) { _ in second += 1 }

        var ghostCalls = 0
        // Released explicitly rather than by scope, so the test does not rest on where the optimiser
        // chooses to end a `let`'s lifetime.
        var transient: NSObject? = NSObject()
        baker.observeFrameFinished(transient!) { _ in ghostCalls += 1 }
        transient = nil

        baker.noteDocumentChanged()
        drain(baker)

        XCTAssertEqual(first, 0, "The second registration from one owner replaces the first.")
        XCTAssertEqual(second, 2, "…and it is the one that hears both frames.")
        XCTAssertEqual(ghostCalls, 0, "An observer whose owner is gone is not called.")
    }
}
