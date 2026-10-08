import Foundation
import CoreGraphics
import SwiftUI
import UIKit

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
    /// `-uiTestSlowVectorRenderMillis <n>`, read by `StrokeCanvasView.startVectorRender` and, for a
    /// layer the compositor is drawing, by the live pair's middle (`CanvasView.Coordinator
    /// .LiveActivePicture`), which is the pen-up render of a posed layer.
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
    /// nothing else: the sleep is on `StrokeCanvasView.renderQueue`, or on the sandwich's own queue
    /// for the live pair, both background serial queues whose job is that rasterize. The main thread
    /// is untouched, so a test that stages the race is still driving the app the artist drives.
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

    /// **Makes a bake take as long as it does on the owner's iPad** — `-uiTestSlowBakeMillis <n>`,
    /// armed from `PaintApp.init` into `FrameBaker.compositeDelay`.
    ///
    /// TODO (145)'s latency is the time between an edit and its bake, MEASURED at 334–365 ms of
    /// composite alone on the device and a few milliseconds here, so the picture the canvas shows
    /// inside that window — the previous bake, or the edit's live pair — is unobservable from a test
    /// without it. The sleep is on the baker's own worker queue and nowhere else, so a test that
    /// widens the window is still driving the app the artist drives.
    ///
    /// Simulator-only, on `slowVectorRenderDelay`'s rule and for its reason.
    static func applyBakeDelayIfRequested() {
        guard ProjectBackupManager.honoursGalleryReset(isSimulator: ProjectBackupManager.isSimulator)
        else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiTestSlowBakeMillis"),
              args.index(after: flag) < args.endIndex,
              let millis = Int(args[args.index(after: flag)]), millis > 0 else { return }
        FrameBaker.compositeDelay = TimeInterval(millis) / 1000
    }

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
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedVideo"),
              let url = writeSeedClip() else { return }
        canvasManager.insertVideo(at: url, consumingSource: true)
    }

    /// The clip `-uiTestSeedVideo` and `-uiTestPrimeVideo` both start from: four frames at four flat
    /// grey levels, square, one second at 4 fps. Nil when the write fails — nothing a seed can do
    /// about that, and the test that armed it finds no video and fails loudly there, which is the
    /// honest outcome rather than a silently-empty seed pretending to have worked.
    private static func writeSeedClip() -> URL? {
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
            return nil
        }
        return url
    }

    /// **A full Recent strip** — `-uiTestSeedColorHistory`, for TODO's colour-panel fit.
    ///
    /// The strip is "the last colours actually used to paint" (`ColorHistoryStore`), so the only way
    /// to a full one is `capacity` strokes in `capacity` colours — a few minutes of hex-field typing
    /// to assert one layout fact. This records twenty distinct colours through the store's own
    /// `record`, the verb a stroke's end calls, oldest first so the strip reads newest-first as it
    /// does for an artist.
    static func seedColorHistoryIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedColorHistory") else { return }
        ColorHistoryStore.shared.clear()
        for step in 0..<ColorHistoryStore.capacity {
            let hue = Double(step) / Double(ColorHistoryStore.capacity)
            ColorHistoryStore.shared.record(Color(hue: hue, saturation: 0.8, brightness: 0.9))
        }
    }

    /// **A transformation layer above the drawing layer that carries it a fifth of the canvas to the
    /// right** — `-uiTestSeedMovedTransformLayer`, for the media a picker or a pasteboard hands the app
    /// and that therefore have to land *after* the pose exists: `-uiTestPrimeImage`, `-uiTestPrimeVideo`
    /// and `-uiTestSeedImage` (TODO (149)'s follow-up). Authoring it by hand — `+` → Transform Layer, its
    /// Move row, a drag of the box, Done — leaves the primed object nothing to be primed by, because the
    /// picture is primed at document creation and the pen would place it on the first touch of that
    /// drag. The values are the ones `transformMoveRow` ends at, as `seedKeyframedMoveIfRequested`'s are.
    /// The drawing layer stays active, so everything placed lands under the pose.
    static func seedMovedTransformLayerIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedMovedTransformLayer"),
              let size = canvasManager.canvasSize else { return }
        canvasManager.addTransformLayer()
        canvasManager.layers[canvasManager.layers.count - 1].transform = LayerPose(
            pose: PoseQuad(box: CGRect(origin: .zero, size: size),
                           mappedBy: CGAffineTransform(translationX: size.width * 0.2, y: 0)),
            mode: .move)
        canvasManager.currentLayerIndex = 0
    }

    /// **A picture on a fresh document, the way an import leaves it — held in the Move box** —
    /// `-uiTestSeedImage`, for TODO (120).
    ///
    /// The photo picker is `seedVideoIfRequested`'s wall: system UI in another process, driven by no
    /// XCUITest in this suite. This calls the verb Actions → Paste calls, `insertImage`, on a picture
    /// the app draws itself, so everything from there — the placement, the fit, the lift into the Move
    /// box — is a real paste's. (Add → Insert Photo primes the pen instead: `-uiTestPrimeImage`.)
    ///
    /// **Four times wider than tall and black**, for what a test has to tell apart: the Move box of a
    /// wide picture is a wide rectangle, where a box that circumscribed it would be a square, and a
    /// black rectangle on the white paper is what `inkProbe` reads as ink.
    static func seedImageIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedImage") else { return }
        let size = CGSize(width: 240, height: 60)
        let picture = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        canvasManager.insertImage(picture)
    }

    /// **A picture primed for the pen, the way Add → Insert Photo leaves it** — `-uiTestPrimeImage`, for
    /// TODO (149)'s cold-start test. The picker is the wall `seedImageIfRequested` describes; this calls
    /// the verb the picker's caller calls, `primeImage`, on a black picture four times wider than tall, so
    /// a test can tell the picture's own shape from a square: the drag keeps the aspect.
    static func primeImageIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestPrimeImage") else { return }
        let size = CGSize(width: 240, height: 60)
        let picture = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        canvasManager.primeImage(picture)
    }

    /// **A clip primed for the pen** — `-uiTestPrimeVideo`, the video twin of `primeImageIfRequested`:
    /// the same clip `-uiTestSeedVideo` writes, handed to the verb Add → Insert Video's caller calls,
    /// `primeVideo`, which owns the file from there.
    static func primeVideoIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestPrimeVideo"),
              let url = writeSeedClip() else { return }
        if !canvasManager.primeVideo(at: url) { try? FileManager.default.removeItem(at: url) }
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

    /// **TODO (121)'s first repro: a smart-shape line whose far end is off the canvas**, pending and
    /// adjustable, on a fresh document — `-uiTestSeedPendingLine`.
    ///
    /// The owner: *"If you make a line half inside the canvas half outside, make that into a smart
    /// shape, then try to move the node sitting outside the canvas, it does not let you."* The shape
    /// itself is the one thing a test cannot make the artist's way: a smart shape fires on the pen
    /// holding still, `ShapeHoldClock` measures that on `UITouch.timestamp`, and XCUITest's synthetic
    /// touch reports nothing while it is stationary (`PaintUITestCase.drawAndHoldShape` carries the
    /// measurement). So this calls the two verbs the hold and the lift call —
    /// `beginInteractiveShape` with the line the detector would hand it, then `endInteractiveShape` —
    /// and everything after, the handles, the preview ink and the drag the test makes, is the app's.
    ///
    /// A vertical line from the paper's upper middle to 6% of the paper above its top edge, so the
    /// far endpoint sits in the surround above the paper where a portrait iPad has room for it. The
    /// brush is widened to a sixty-fourth of the canvas so a pixel probe at fit zoom finds the ink.
    static func seedPendingLineIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedPendingLine"),
              let size = canvasManager.canvasSize else { return }
        let start = CGPoint(x: size.width * 0.5, y: size.height * 0.4)
        let end = CGPoint(x: size.width * 0.5, y: -size.height * 0.06)
        let samples = (0...24).map { step -> VectorSample in
            let t = CGFloat(step) / 24
            return VectorSample(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t,
                                pressure: 1)
        }
        seedPendingShape(ShapeGeometry(kind: .line, startPoint: start, endPoint: end), samples: samples,
                         into: canvasManager, size: size)
    }

    /// **TODO (151)'s smart-shape rotate knob: a rectangle, pending and adjustable, in the middle of a
    /// fresh document** — `-uiTestSeedPendingRectangle`. A line has no rotate knob, and a rectangle is
    /// the shape a test cannot make the artist's way for `-uiTestSeedPendingLine`'s reason. The drawn
    /// samples are the rectangle's own outline, which is what a pen drawing one would have left.
    static func seedPendingRectangleIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedPendingRectangle"),
              let size = canvasManager.canvasSize else { return }
        let rect = CGRect(x: size.width * 0.3, y: size.height * 0.4, width: size.width * 0.4,
                          height: size.height * 0.2)
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                       CGPoint(x: rect.minX, y: rect.minY)]
        let samples = zip(corners, corners.dropFirst()).flatMap { from, to in
            (0..<24).map { step -> VectorSample in
                let t = CGFloat(step) / 24
                return VectorSample(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t,
                                    pressure: 1)
            }
        }
        seedPendingShape(ShapeGeometry(kind: .rectangle, startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                       endPoint: CGPoint(x: rect.maxX, y: rect.maxY)),
                         samples: samples, into: canvasManager, size: size)
    }

    /// The two verbs the hold and the lift call, with the shape the detector would hand them — and a
    /// brush a sixty-fourth of the canvas wide, so a pixel probe at fit zoom finds the ink.
    private static func seedPendingShape(_ shape: ShapeGeometry, samples: [VectorSample],
                                         into canvasManager: CanvasManager, size: CGSize) {
        canvasManager.brushSize = size.width / 64
        canvasManager.beginInteractiveShape(shape, samples: samples)
        canvasManager.endInteractiveShape()
    }

    /// **Two interpolated intervals with an arc drawn on the first** — `-uiTestSeedGuidedIntervals`,
    /// the document the interpolate bar's Fetch needs before it has anything to offer, and whose
    /// two-colour keyframes are what its motion-group chips need.
    ///
    /// Fetch lists the guides that other intervals own, so reaching it takes keyframes at frames 0, 8
    /// and 16, an in-between generated onto each interval, a guide drawn on the first, and the playhead
    /// on the second — five cels, four reference toggles, two Generates and a guide stroke, across the
    /// timeline and the canvas. It is the same document `InterpolationGuideLogicTests.twoIntervals`
    /// builds for the model tier, stated through the same verbs, so what a test then does with it is
    /// the artist's: open Fetch, pick Link or Duplicate, watch the guide join the frame. Left in
    /// interpolate mode on the second in-between.
    static func seedGuidedIntervalsIfRequested(into canvasManager: CanvasManager) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedGuidedIntervals"),
              let size = canvasManager.canvasSize else { return }
        let layer = canvasManager.layers.count - 1
        let cels = (0..<5).map {
            Cel(id: UUID(), startFrame: $0 * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        canvasManager.layers[layer].cels = cels
        var brush = canvasManager.selectedBrush
        brush.size = size.height / 32
        // An L at each keyframe, moved right from one to the next — its two arms in two colours, which
        // is what Tag by Colour needs to make a group of each.
        func arm(_ from: CGPoint, _ to: CGPoint, _ colour: CodableColor) -> VectorStroke {
            VectorStroke(id: UUID(), brush: brush, color: colour, size: brush.size, opacity: 1,
                         samples: StrokeSamples([VectorSample(x: from.x, y: from.y, pressure: 1),
                                                 VectorSample(x: to.x, y: to.y, pressure: 1)],
                                                channels: .pressureOnly))
        }
        let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        let red = CodableColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        for (index, left) in [(0, 0.10), (2, 0.40), (4, 0.70)] {
            let corner = CGPoint(x: size.width * (left + 0.2), y: size.height * 0.30)
            cels[index].vector?.addStroke(arm(CGPoint(x: size.width * left, y: corner.y), corner, black))
            cels[index].vector?.addStroke(arm(corner, CGPoint(x: corner.x, y: corner.y + size.width * 0.2), red))
        }
        canvasManager.enterInterpolateMode()
        canvasManager.currentLayerIndex = layer
        func references(_ pair: [Cel]) {
            for cel in pair {
                canvasManager.toggleInterpolationReference(celID: cel.id, inLayer: canvasManager.layers[layer].id)
            }
        }
        references([cels[0], cels[2]])
        _ = canvasManager.interpolate(mode: .generate, layerIndex: layer, celIndex: 1)
        canvasManager.currentFrame = 4
        let arc = [CGPoint(x: size.width * 0.2, y: size.height * 0.6),
                   CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                   CGPoint(x: size.width * 0.8, y: size.height * 0.6)]
        _ = canvasManager.recordGuideStroke(samples: arc.enumerated().map {
            TimedSample(point: $1, pressure: 1, time: TimeInterval($0) * 0.01)
        })
        references([cels[0], cels[2]])   // swap the pair over to the second interval
        references([cels[2], cels[4]])
        _ = canvasManager.interpolate(mode: .generate, layerIndex: layer, celIndex: 3)
        canvasManager.currentFrame = 12
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
