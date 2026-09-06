import Foundation
import UIKit

/// **VIDEO.md §8 stage 8 — bake a video to cels of images.** The brief's own words: *"Should have
/// the same option to bake to multiple cels containing images instead of the video."* §2.9 names
/// this KEYFRAMES.md §6's Bake "reaching a new source" — the same recipe (`bakePreciseStrokes`:
/// commit interactive state first, collect every edit, one `recordUndo` over all of them, fresh ids
/// on everything written), pointed at a video's decoded frames instead of a computed in-between.
extension CanvasManager {

    /// What a video bake returns. **Not `@discardableResult` and not a bare `Bool`** — CLAUDE.md
    /// already has a filed bug shaped exactly like that, and the brief for this stage asks for a
    /// sentence on every refusal rather than a silently-ignored return value.
    enum VideoBakeOutcome: Equatable {
        /// One cel per document frame the block covered, minted fresh. `cels` is that count, always
        /// the block's own `frameCount` — a frame that individually fails to decode still gets a
        /// cel (it is simply left showing the video on that one frame; see the note below), so this
        /// number is knowable before any pixel is touched.
        case baked(cels: Int)
        /// Nothing was written. See `VideoBakeRefusal.phrase` for what the artist is told.
        case refused(VideoBakeRefusal)
    }

    /// Why a video bake refused, in the artist's own terms — `CanvasResizeRefusal`'s own pattern,
    /// carried rather than rendered so `CanvasNotice.message` owns the one sentence and a test can
    /// assert on the case instead of on wording that might get revised.
    enum VideoBakeRefusal: Equatable {
        /// The row should never be reachable in this state — the menu hides it — but a direct
        /// caller or a test gets a named reason instead of a trap.
        case noVideo
        /// `VideoFrameSource.info(for:)` could not open the file at all.
        case unreadableAsset
        /// The file opens, but nothing in the block's own span decoded — a crop naming a range the
        /// asset has nothing in.
        case noDecodableFrames

        var phrase: String {
            switch self {
            case .noVideo: return "this block doesn't hold a video"
            case .unreadableAsset: return "that video's file can't be read"
            case .noDecodableFrames: return "no frames could be read from that video"
            }
        }
    }

    /// Bakes the video on `layers[layerIndex].cels[celIndex]` into one cel of concrete content per
    /// document frame the block spans.
    ///
    /// **Built on `splitCel`, not beside it.** Turning an *n*-frame block into *n* one-frame cels is
    /// exactly what *n − 1* calls to Split Drawing's own verb already do — the same crop anchoring
    /// (`writeVideoCrop`), the same `TransformTrack.split`, both already tested by
    /// `VideoCropLogicTests` and `SplitDrawingLogicTests`. The whole loop runs inside one
    /// `withInterpolationUndo`, which makes every `splitCel` call's own `withStructureUndo` bracket
    /// a no-op (both share `structureUndoDepth`, already nonzero by the time the loop starts), so
    /// the many splits and the image swap that follows land as the single undo step KEYFRAMES §6
    /// asks a bake to be, not one step per cel.
    ///
    /// **`withStructureUndo` alone would silently corrupt the first cel's undo.** `splitCel` never
    /// copies the *left* half's canvas — only the newly-split-off right half gets `makeCopy()` — so
    /// the very first of the *n* resulting one-frame cels keeps mutating the **same `VectorCanvas`
    /// instance** the block had before any of this ran. `withStructureUndo`'s snapshot is `[Layer]`
    /// by value, and `Cel.vector` is a class reference, so restoring it puts back a `Layer` array
    /// whose one cel still points at that same object — now holding the *baked* elements, because
    /// nothing about reverting the array un-mutates the class instance it references. That is
    /// exactly the trap `withInterpolationUndo`'s own doc comment names, and why it exists: passing
    /// the original canvas as `touching:` snapshots and restores its `elements` explicitly, the way
    /// `bakePreciseStrokes` does by hand for every canvas it touches. Every *other* resulting cel's
    /// canvas is a fresh object minted after the snapshot, so undoing simply drops it with the array
    /// shape `withInterpolationUndo` already restores — only the first needs the explicit treatment.
    ///
    /// **Every element gets a fresh id, video-turned-image and passthrough ink alike.** KEYFRAMES §6
    /// is explicit that a bake mints ids "unlike every existing copy path": `splitCel`'s own copies
    /// (`VectorCanvas.makeCopy()`) preserve ids verbatim, which is correct for a *copy* — the same
    /// drawing shown twice — and wrong here, where the whole point is *n* independent cels. Without
    /// this, any ink the artist drew on the video's layer alongside the clip (§9 leaves whether that
    /// is even encouraged as an open question, but nothing today refuses it) would share one id
    /// across every baked cel and alias anything keyed by it.
    ///
    /// **A cel's pose, if it has one, is baked into the written geometry rather than dropped.**
    /// `Self.poseMappings`/`Self.posed` are the exact pair `videoCelContent` already resolves a
    /// video's on-screen placement through; reusing them here means a video animated by a transform
    /// channel bakes to images sitting where the artist last saw them, not back at rest. The written
    /// cels carry no `transformTracks` of their own afterward — the pose was a *derivation*, and a
    /// bake's whole purpose is to replace a derivation with the concrete thing it was deriving.
    /// (This does not thread a *container* pose — a wrapping transformation layer or folder above
    /// this cel — through the bake; that is a narrower scope than a live preview's, noted in this
    /// stage's report rather than silently assumed away.)
    ///
    /// **What refuses, and why each is a sentence rather than a silent no-op** (the brief names all
    /// three by example). No video here: the row should never be reachable in this state, but a
    /// direct caller — or a test — gets a named reason instead of a trap. An asset that will not
    /// open: checked with `VideoFrameSource.info(for:)` *before any mutation*, so a bad clip leaves
    /// the document exactly as it was rather than a half-cut block. Nothing decodes anywhere in the
    /// block's own span: the same idea extended across every frame the bake would touch, because a
    /// file that opens but answers nothing for its own stored crop is the same failure to the artist
    /// as one that will not open at all.
    ///
    /// A frame that fails to decode **individually**, inside an otherwise-readable clip, is not a
    /// reason to refuse the whole bake: that one cel is left showing the video rather than an image
    /// — the same "keep the previous picture, do not fail" rule RENDER.md §2.10 already applies to a
    /// live decode that misses — and every other frame in the block still bakes. Nothing is
    /// destroyed by a bake that finds a gap: the source asset is untouched either way.
    func bakeVideoToCels(layerIndex: Int, celIndex: Int) -> VideoBakeOutcome {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else {
            return .refused(.noVideo)
        }
        let cel = layers[layerIndex].cels[celIndex]
        guard let vector = cel.vector, vector.holdsVideo, let video = vector.videos.first else {
            return .refused(.noVideo)
        }
        guard VideoFrameSource.shared.info(for: video.assetURL) != nil else {
            return .refused(.unreadableAsset)
        }

        let startFrame = cel.startFrame
        let endFrame = cel.endFrame
        let documentFPS = fps

        // Whether *anything* in the block's own span can be decoded at all — asked before any
        // mutation, so a file that opens but names a crop with nothing in it refuses cleanly
        // instead of leaving every resulting cel still showing the video.
        var anyDecodes = false
        for frame in startFrame..<endFrame {
            let time = VideoFrameMap.sourceTime(of: video, atDocumentFrame: frame,
                                                celStartFrame: startFrame, documentFPS: documentFPS)
            if VideoFrameSource.shared.frame(assetURL: video.assetURL, at: time) != nil {
                anyDecodes = true
                break
            }
        }
        guard anyDecodes else {
            return .refused(.noDecodableFrames)
        }

        // KEYFRAMES §6's recipe: a pending float baked first, so it lands as its own earlier step
        // rather than being swallowed into (or re-baked on top of) this one.
        commitAllInteractiveState()

        // `touching: [vector]` — see the doc comment above for why only the *original* canvas
        // needs its elements snapshotted explicitly.
        withInterpolationUndo(label: .bakeVideoToImages, touching: [vector]) {
            // Chop the block into one cel per document frame, left to right. Every nested
            // `withStructureUndo` inside `splitCel` below is a no-op bracket, because this one is
            // already open by the time it runs.
            var cursor = startFrame
            while cursor + 1 < endFrame {
                guard let idx = activeCelIndex(inLayer: layerIndex, atFrame: cursor) else { break }
                splitCel(layerIndex: layerIndex, celIndex: idx, atFrame: cursor + 1)
                cursor += 1
            }

            // Every cel in the span is now exactly one document frame. Swap each one's video for
            // the picture it shows at that instant and re-identify everything on it.
            for frame in startFrame..<endFrame {
                guard let idx = activeCelIndex(inLayer: layerIndex, atFrame: frame),
                      let bakedVector = layers[layerIndex].cels[idx].vector else { continue }
                let bakedCel = layers[layerIndex].cels[idx]
                let mappings = Self.poseMappings(bakedCel.transformTracks, atCelLocalFrame: 0)
                let posed = Self.posed(bakedVector.elements, through: mappings, inheriting: nil)
                let rebuilt = posed.map { element -> VectorElement in
                    guard case .video(let posedVideo) = element else {
                        return Self.reidentified(element)
                    }
                    let time = VideoFrameMap.sourceTime(of: posedVideo, atDocumentFrame: frame,
                                                        celStartFrame: bakedCel.startFrame,
                                                        documentFPS: documentFPS)
                    guard let decoded = VideoFrameSource.shared.frame(assetURL: posedVideo.assetURL, at: time),
                          let cgImage = decoded.makeImage() else {
                        return element // Left showing the video — see the doc comment above.
                    }
                    var image = VectorImageElement(image: UIImage(cgImage: cgImage),
                                                   transform: posedVideo.transform,
                                                   aspect: posedVideo.aspect,
                                                   stretchAxis: posedVideo.stretchAxis,
                                                   mirrored: posedVideo.mirrored)
                    image.animationGroupID = posedVideo.animationGroupID
                    return .image(image)
                }
                bakedVector.elements = rebuilt
                bakedVector.bumpVersion()
                layers[layerIndex].cels[idx].transformTracks = [:]
                layers[layerIndex].cels[idx].pendingPoseBaselines = [:]
                celContentChangedOutsideStroke(layerID: layers[layerIndex].id, celID: bakedCel.id)
            }
        }

        return .baked(cels: endFrame - startFrame)
    }

    /// A fresh id on whichever case `element` is, every other field untouched — KEYFRAMES.md §6's
    /// rule that a bake mints ids "unlike every existing copy path", extended to the ink a bake
    /// carries across as well as to the video it converts.
    private static func reidentified(_ element: VectorElement) -> VectorElement {
        switch element {
        case .stroke(var value): value.id = UUID(); return .stroke(value)
        case .fill(var value): value.id = UUID(); return .fill(value)
        case .image(var value): value.id = UUID(); return .image(value)
        case .text(var value): value.id = UUID(); return .text(value)
        case .video(var value): value.id = UUID(); return .video(value)
        }
    }
}
