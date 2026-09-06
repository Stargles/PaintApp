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
