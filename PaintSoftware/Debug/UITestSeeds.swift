import Foundation
import CoreGraphics

/// **Test-only seams, each armed by its own launch argument and inert on every ordinary launch.**
/// `Services/ProjectBackupManager.swift`'s `-resetGallery` and `-simulateProjectCorruption` are the
/// existing members of this family — a recognized string in `ProcessInfo.processInfo.arguments`
/// that only an XCUITest ever passes. This is the same idea for content no test can reach any other
/// way.
enum UITestSeeds {

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
    /// the real writers store: `addValueLayer` then `Layer.transform`, which is what
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

        canvasManager.addValueLayer()
        let box = CGRect(origin: .zero, size: size)
        let mover = canvasManager.layers.count - 1
        canvasManager.layers[mover].fill = nil
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

        canvasManager.addValueLayer()
        let box = CGRect(origin: .zero, size: size)
        let mover = canvasManager.layers.count - 1
        canvasManager.layers[mover].fill = nil
        canvasManager.layers[mover].transform = LayerPose(
            pose: PoseQuad(restingIn: box),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: box)),
                .init(frame: 4, pose: PoseQuad(box: box,
                                               mappedBy: CGAffineTransform(translationX: size.width * 0.4,
                                                                           y: 0)))]))
        canvasManager.currentLayerIndex = 0
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
