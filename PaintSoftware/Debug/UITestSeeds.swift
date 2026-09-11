import Foundation
import CoreGraphics

/// **Test-only seams, each armed by its own launch argument and inert on every ordinary launch.**
/// `Services/ProjectBackupManager.swift`'s `-resetGallery` and `-simulateProjectCorruption` are the
/// existing members of this family — a recognized string in `ProcessInfo.processInfo.arguments`
/// that only an XCUITest ever passes. This is the same idea for content no test can reach any other
/// way.
enum UITestSeeds {

    /// **Makes this simulator behave like the iPad that crashes, for the one number that decides
    /// whether it does** — `-uiTestTextureBudgetBytes <n>`, armed from `PaintApp.init`.
    ///
    /// `CompositorBudget.textureBudgetBytes` is `ProcessInfo.processInfo.physicalMemory / 16`, and in
    /// a simulator that reads the **Mac's** RAM: the budget comes out at the 768 MiB cap, every memo
    /// in the app fits everything it is asked for, and the thrash the owner reported on 2026-09-08
    /// cannot be reproduced at all. That is why it shipped, and it is why a UI test asserting *"a
    /// frame flip costs no canvas-sized render"* was, without this, comparing a converged count with
    /// itself: MEASURED on 2026-09-09, deleting the fix's own refusal left every assertion in
    /// `PlaybackBakeUITests` green.
    ///
    /// **A byte count from the caller rather than a device name**, because the caller knows the
    /// canvas it is about to create and this runs before there is one. The value that reproduces an
    /// iPad 9 is `CompositorBudget.textureBytes(for: canvas) * 2` — 183.7 MB against 67.1 MB a render
    /// at 4096² is two entries, and two entries is what the test wants whatever size it draws at.
    ///
    /// Simulator-only, on `honoursGalleryReset`'s rule and for a milder version of its reason: this
    /// one destroys nothing, but a flag that silently made a *device* build composite under a
    /// pretend budget would be a performance report about a machine that does not exist.
    static func applyTextureBudgetOverrideIfRequested() {
        guard ProjectBackupManager.honoursGalleryReset(isSimulator: ProjectBackupManager.isSimulator)
        else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiTestTextureBudgetBytes"),
              args.index(after: flag) < args.endIndex,
              let bytes = Int(args[args.index(after: flag)]), bytes > 0 else { return }
        CompositorBudget.budgetOverrideBytes = bytes
    }

    /// **Makes the pen-up render take long enough for a person to draw again inside it** —
    /// `-uiTestSlowVectorRenderMillis <n>`, read by `StrokeCanvasView.startVectorRender`.
    ///
    /// BUGS.md's 2026-09-04 defect opens by saying it is *"confirmed by tracing every path that
    /// repaints the base, not measured"*, and the reason is timing: the window between a stroke
    /// committing and its render landing is MEASURED at **14.4 ms** on the owner's own Test1 at
    /// 4096² and **27.3 ms** at 6000² (`StrokeHandoffBench`), while one XCUITest
    /// `press(forDuration:thenDragTo:)` is most of a second. So the race is real on a pen and
    /// unreachable from a test, and no assertion in the suite could see the defect at all — which is
    /// how it survived from 2026-09-04 to 2026-09-09.
    ///
    /// This makes it reachable by slowing the *one* thing whose duration the defect is about, and
    /// nothing else: the sleep is on `StrokeCanvasView.renderQueue`, which is a background serial
    /// queue whose only job is that rasterize. The main thread is untouched, so a test that stages
    /// the race is still driving the app the artist drives.
    ///
    /// Simulator-only, on `applyTextureBudgetOverrideIfRequested`'s rule and for its reason: a flag
    /// that silently made a *device* build draw slower would be a report about a machine that does
    /// not exist.
    static let slowVectorRenderDelay: TimeInterval = {
        guard ProjectBackupManager.honoursGalleryReset(isSimulator: ProjectBackupManager.isSimulator)
        else { return 0 }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiTestSlowVectorRenderMillis"),
              args.index(after: flag) < args.endIndex,
              let millis = Int(args[args.index(after: flag)]), millis > 0 else { return 0 }
        return TimeInterval(millis) / 1000
    }()

    /// **How long a `CanvasNotice` stays up, when a test needs to read one.**
    ///
    /// `CanvasNotice.duration` is 2.6 s, which is right for an artist and wrong for a harness: a
    /// banner that dismisses itself is gone before a loaded machine gets round to asking whether it
    /// is there, so `waitForExistence` misses it and **no timeout can fix that** — a longer wait
    /// cannot see something that has already left. MEASURED 2026-09-10:
    /// `TimingRecorderUITests.testArmingTellsTheArtistTheCanvasIsAWayToStartATake` red inside the
    /// full suite under four parallel clones and green in isolation on the same binary, which is the
    /// signature of exactly that race and not of a wrong assertion.
    ///
    /// So a test that reads a banner asks for one that waits for it. `-uiTestNoticeSeconds <n>`,
    /// read by `DrawingView`'s dismissal task. Simulator-only, on `slowVectorRenderDelay`'s rule and
    /// for its reason: a flag that silently made a *device* build hold its banners would be a report
    /// about an app nobody ships.
    static let noticeDurationOverride: TimeInterval? = {
        guard ProjectBackupManager.honoursGalleryReset(isSimulator: ProjectBackupManager.isSimulator)
        else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiTestNoticeSeconds"),
              args.index(after: flag) < args.endIndex,
              let seconds = Double(args[args.index(after: flag)]), seconds > 0 else { return nil }
        return seconds
    }()

    /// **How long the layer rail's opacity readout stays up after the finger lifts** — TODO (59),
    /// and `noticeDurationOverride`'s problem in a second costume.
    ///
    /// The readout is on screen from touch-down to shortly after lift, which is right for an artist
    /// and unreadable to a harness: **XCUITest has no asynchronous drag**, so an accessibility read
    /// taken after `press(…thenDragTo:…)` returns is a read of the state after the lift.
    /// `GraphEditorUITests` records the attempt to get round that with an
    /// `XCTNSPredicateExpectation` built beforehand — it times out on the affirmative case and its
    /// inverted twin then passes unconditionally, which is a green test measuring nothing.
    ///
    /// So the harness asks for a readout that waits for it. `-uiTestOpacityReadoutSeconds <n>`,
    /// read by `LayerStackCell.opacityReadoutLinger`. Simulator-only, on `slowVectorRenderDelay`'s
    /// rule and for its reason.
    ///
    /// **What this does and does not buy.** With the flag the test reads a real, visible label
    /// carrying a real value, and compares it against the slider's own reported position — so the
    /// assertion is about what is drawn. What it cannot prove is the *during*: production hides the
    /// label `opacityReadoutLinger` after the lift and the flag only moves that number. The rest of
    /// the rule — that the string is the slider's percentage, resolved at the playhead — is
    /// `OpacityChannelLogicTests`' and runs in the fast tier.
    static let opacityReadoutLingerOverride: TimeInterval? = {
        guard ProjectBackupManager.honoursGalleryReset(isSimulator: ProjectBackupManager.isSimulator)
        else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiTestOpacityReadoutSeconds"),
              args.index(after: flag) < args.endIndex,
              let seconds = Double(args[args.index(after: flag)]), seconds > 0 else { return nil }
        return seconds
    }()

    /// **VIDEO.md §8 stage 8's own gap.** Every video- or image-carrying element in this app is
    /// reached, for a real artist, through `PhotosPicker` — real system UI in a separate process
    /// that XCUITest cannot drive reliably, which is why `VideoImportLogicTests`'s own header says
    /// "the picker itself is not here" and not one XCUITest in this suite, for any feature, drives
    /// it. That leaves Bake to Images with nothing to test against unless something else gets a
    /// video onto a fresh document first.
    ///
    /// `-uiTestSeedVideo` answers it by calling the exact verb the picker calls,
    /// `CanvasManager.insertVideo`, on a clip this writes with the app's own encoder rather than one
    /// a person picked through the system UI. Everything from that call onward — the new vector
    /// layer, the block on the timeline, the "Bake to Images" row and what tapping it does — is
    /// byte-for-byte what a real import produces; only the source of the file differs.
    ///
    /// Four frames at four flat grey levels, one second at 4 fps: enough for a bake to be visibly
    /// more than one cel, and for each resulting cel's picture to be told apart from its neighbours
    /// by a single pixel probe.
    static func seedVideoIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedVideo") else { return }
        let levels: [UInt8] = [40, 110, 180, 250]
        let side = 64
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-seed-video-\(UUID().uuidString).mp4")
        do {
            let writer = try VideoFrameWriter(url: url, size: CGSize(width: side, height: side), fps: 4)
            for (index, level) in levels.enumerated() {
                try writer.append(Self.flatFrame(level, side: side), at: index)
            }
            try writer.finish()
        } catch {
            // Nothing this seam can do about a write failure — the test that armed it will find no
            // video on the timeline and fail loudly there, which is the honest outcome rather than
            // a silently-empty seed pretending to have worked.
            return
        }
        canvasManager.insertVideo(at: url, consumingSource: true)
    }

    /// **TODO (53)'s document, which is the owner's own `AnimationTest`**: ink on a vector layer that
    /// holds for the whole scene, and a transformation layer above it carrying two pose keys, so
    /// every frame of playback is a different picture of the same strokes.
    ///
    /// **Seeded rather than authored, for `seedVideoIfRequested`'s reason applied to gestures rather
    /// than to a system picker.** Reaching this state by hand is a dozen taps across the layer panel,
    /// its options menu and the graph editor's keyframe marks, and a UI test that spent them would be
    /// testing those three surfaces rather than the one thing it is for — whether the canvas serves a
    /// keyframed move off the bake instead of rasterizing it per tick. Every field below is the value
    /// the real writers store: `addTransformLayer` then `Layer.transform`, which is what
    /// `transformMoveRow` and `setContainerPoseKey` end at.
    ///
    /// The ink is one horizontal stroke, thick enough that a single pixel probe finds it, and the move
    /// is a translation large enough that the probe point which is ink at frame 0 is paper at the last
    /// frame. That is what lets a test tell "the pose is on screen" from "the pose is anywhere".
    static func seedKeyframedMoveIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedKeyframedMove"),
              let size = canvasManager.canvasSize else { return }
        guard let celIndex = canvasManager.activeCelIndex(inLayer: canvasManager.layers.count - 1,
                                                          atFrame: 0),
              let vector = canvasManager.layers[canvasManager.layers.count - 1].cels[celIndex].vector
        else { return }
        var brush = canvasManager.selectedBrush
        brush.size = size.height / 8
        vector.addStroke(VectorStroke(
            id: UUID(), brush: brush,
            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
            size: brush.size, opacity: 1,
            samples: StrokeSamples([VectorSample(x: size.width * 0.2, y: size.height * 0.5, pressure: 1),
                                    VectorSample(x: size.width * 0.5, y: size.height * 0.5, pressure: 1)],
                                   channels: .pressureOnly)))

        canvasManager.addTransformLayer()
        let box = CGRect(origin: .zero, size: size)
        let mover = canvasManager.layers.count - 1
        canvasManager.layers[mover].transform = LayerPose(
            pose: PoseQuad(restingIn: box),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: box)),
                .init(frame: 11, pose: PoseQuad(box: box,
                                                mappedBy: CGAffineTransform(translationX: size.width * 0.4,
                                                                            y: 0)))]))
        canvasManager.currentLayerIndex = 0
    }

    /// **TODO (54)'s document: one scene that is half a move and half a hold**, so the control and
    /// the case under test are the same twelve frames of the same file.
    ///
    /// The owner, 2026-09-07: *"Lets say a frame in the animation is held for a couple cels where
    /// nothing changes. The bake and cache seems to re-render each frame even though they are the
    /// same."*
    ///
    /// Same construction as `seedKeyframedMoveIfRequested` — ink on a vector layer that holds the
    /// whole scene, a transformation layer above it — with **the last pose key at frame 4 instead of
    /// at the end**. `AnimationCurve` clamps past its last key, so frames 5–11 all resolve to the
    /// frame-4 pose: seven frames whose every render input is byte-identical, sitting immediately
    /// after five that all differ.
    ///
    /// **Both halves in one document is the whole point of the fixture.** An assertion that a count
    /// does not move across a hold measures nothing on its own — a counter that is broken, unpublished
    /// or never reached passes it. Walking 0→4 first, in the same launch and against the same
    /// instrument, is what makes the number that does not move afterwards mean something. It is also
    /// why the move is first: a fixture that held first would leave "the count was already stuck"
    /// available as an explanation.
    static func seedHoldAfterMoveIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedHoldAfterMove"),
              let size = canvasManager.canvasSize else { return }
        guard let celIndex = canvasManager.activeCelIndex(inLayer: canvasManager.layers.count - 1,
                                                          atFrame: 0),
              let vector = canvasManager.layers[canvasManager.layers.count - 1].cels[celIndex].vector
        else { return }
        var brush = canvasManager.selectedBrush
        brush.size = size.height / 8
        vector.addStroke(VectorStroke(
            id: UUID(), brush: brush,
            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
            size: brush.size, opacity: 1,
            samples: StrokeSamples([VectorSample(x: size.width * 0.2, y: size.height * 0.5, pressure: 1),
                                    VectorSample(x: size.width * 0.5, y: size.height * 0.5, pressure: 1)],
                                   channels: .pressureOnly)))

        canvasManager.addTransformLayer()
        let box = CGRect(origin: .zero, size: size)
        let mover = canvasManager.layers.count - 1
        canvasManager.layers[mover].transform = LayerPose(
            pose: PoseQuad(restingIn: box),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: box)),
                .init(frame: 4, pose: PoseQuad(box: box,
                                               mappedBy: CGAffineTransform(translationX: size.width * 0.4,
                                                                           y: 0)))]))
        canvasManager.currentLayerIndex = 0
    }

    /// **The owner's `Test1`, which is the document with nothing special about it at all**: three
    /// ordinary vector layers, two frames, a separate cel per layer per frame, Normal mode
    /// throughout — no folder, no mask, no blend mode, no effect, no pose.
    ///
    /// That last sentence is the whole fixture. Every other seed here builds something Core
    /// Animation's flat row of hosts cannot draw, and so engages the compositor by the containment
    /// `needsCompositorOnCanvas` has always applied. This one deliberately does not, because the
    /// defect it exists to catch is that **a document Core Animation draws perfectly well at rest
    /// cannot afford to be drawn that way while the frames are flipping** — one canvas-sized vector
    /// render per layer per flip, against a memo that on the owner's iPad 9 holds two of them.
    ///
    /// Two frames rather than twelve because that is what they reported and it is the harder case:
    /// a two-frame loop revisits the same six cels twice a second, so a memo that held even one lap
    /// would hide the defect entirely.
    ///
    /// One distinct stroke per cel, at a distinct height, so that no two cels render to the same
    /// picture and nothing can dedupe them by accident.
    static func seedPlainAnimationIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedPlainAnimation"),
              let size = canvasManager.canvasSize else { return }
        let layerCount = 3, frameCount = 2
        var brush = canvasManager.selectedBrush
        brush.size = size.height / 24
        // `createCanvas` has already added the first one.
        for _ in 1..<layerCount { canvasManager.addVectorLayer() }
        for layerIndex in 0..<layerCount {
            canvasManager.layers[layerIndex].cels = (0..<frameCount).map { frame in
                let cel = Cel(id: UUID(), startFrame: frame, frameCount: 1,
                              raster: .empty(size: size), vector: .empty(size: size))
                let y = size.height * (0.2 + 0.1 * CGFloat(layerIndex * frameCount + frame))
                cel.vector?.addStroke(VectorStroke(
                    id: UUID(), brush: brush,
                    color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                    size: brush.size, opacity: 1,
                    samples: StrokeSamples([VectorSample(x: size.width * 0.15, y: y, pressure: 1),
                                            VectorSample(x: size.width * 0.85, y: y, pressure: 1)],
                                           channels: .pressureOnly)))
                return cel
            }
        }
        canvasManager.currentLayerIndex = 0
        canvasManager.currentFrame = 0
    }

    /// One flat frame in `DecodedFrame`'s own layout (BGRA, premultiplied, opaque) — the same
    /// construction `PaintSoftwareUITests/CanvasManagerTestSupport.swift`'s `writeGreyClip` uses for
    /// the logic tier, duplicated rather than shared because that file is test-only and this one
    /// ships in every configuration.
    private static func flatFrame(_ level: UInt8, side: Int) -> DecodedFrame {
        var pixels = Data(count: side * side * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<(side * side) {
                base[i * 4] = level
                base[i * 4 + 1] = level
                base[i * 4 + 2] = level
                base[i * 4 + 3] = 255
            }
        }
        return DecodedFrame(width: side, height: side, pixels: pixels)
    }
}
