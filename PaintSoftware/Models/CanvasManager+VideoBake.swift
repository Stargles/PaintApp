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
        /// `VideoFrameSource.Client.info(for:)` could not open the file at all.
        case unreadableAsset
        /// The file opens, but nothing in the block's own span decoded — a crop naming a range the
        /// asset has nothing in.
        case noDecodableFrames
        case pendingEdit
        case videoTiming

        var phrase: String {
            switch self {
            case .videoTiming: return "the video timing cannot be divided into those drawings"
            case .noVideo: return "this block doesn't hold a video"
            case .unreadableAsset: return "that video's file can't be read"
            case .pendingEdit: return "the held picture could not be placed; try again"
            case .noDecodableFrames: return "no frames could be read from that video"
            }
        }
    }

    /// Bakes the video on `layers[layerIndex].cels[celIndex]` into one cel of concrete content per
    /// document frame the block spans.
    ///
    /// **Built on Timeline's shared prepared cuts.** The complete left-to-right sequence is
    /// admitted before history or image writes; every later cut reads the prepared child timing.
    /// The same track/crop/copy owner then lands the cuts inside one `withInterpolationUndo`, so
    /// the operation records one step and never consumes a still-multiframe cell after refusal.
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
    /// open: checked with `VideoFrameSource.Client.info(for:)` *before any mutation*, so a bad clip leaves
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
        guard videoFrames.info(for: video.assetURL) != nil else {
            return .refused(.unreadableAsset)
        }

        let startFrame = cel.startFrame
        let endFrame = cel.endFrame

        guard let pending = prepareCanvasEdit() else { return .refused(.pendingEdit) }
        guard let splits = prepareCelSplits(inLayerAt: layerIndex,
            at: (startFrame + 1) ..< endFrame, stagedCels: pending.cels) else { return .refused(.videoTiming) }

        // Whether *anything* in the block's own span can be decoded at all — asked before any
        // mutation, so a file that opens but names a crop with nothing in it refuses cleanly
        // instead of leaving every resulting cel still showing the video.
        var anyDecodes = false
        for frame in startFrame..<endFrame {
            // TODO (105): `video.resolvedFrameRate`, not the document's live fps — see
            // `VectorVideoElement.mappedFrameRate`.
            let time = VideoFrameMap.sourceTime(of: video, atDocumentFrame: frame,
                                                celStartFrame: startFrame, documentFPS: video.resolvedFrameRate)
            if videoFrames.frame(assetURL: video.assetURL, at: time) != nil {
                anyDecodes = true
                break
            }
        }
        guard anyDecodes else {
            return .refused(.noDecodableFrames)
        }

        // KEYFRAMES §6's recipe: a pending float baked first, so it lands as its own earlier step
        // rather than being swallowed into (or re-baked on top of) this one.
        guard pending.commit(), commitAllInteractiveState(), celSplitPlanIsCurrent(splits),
              let settledVector = layers[layerIndex].cels.first(where: { $0.id == cel.id })?.vector else { return .refused(.pendingEdit) }

        // `touching: [settledVector]` — see the doc comment above for why only the *original* canvas
        // needs its elements snapshotted explicitly.
        withInterpolationUndo(label: .bakeVideoToImages, touching: [settledVector]) {
            applyCelSplits(splits)

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
                        return element.reidentified()
                    }
                    // **`atDocumentFrame: frame` collapses to `elapsedDocumentFrames == 0` here,
                    // always** — every cel is one document frame by now, so the only frame
                    // `activeCelIndex` could have found this one at is its own `startFrame`. The
                    // general formula is kept anyway rather than reading `posedVideo.sourceStart`
                    // directly: it stays correct if a future change ever revisits a cel more than
                    // once, where a shortcut would silently start reading the wrong instant. MEASURED
                    // by mutation: substituting the outer `startFrame` constant here (which makes
                    // `elapsedDocumentFrames` negative instead of zero on every cel but the first)
                    // does not redden anything, because the checked frame map floors both to the same
                    // `sourceStart` — the real guarantee that each cel gets its own picture lives in
                    // the crop `splitCel`/`writeVideoCrop` anchored during the split above, which the
                    // cel-selection mutation just below this one pins directly.
                    let time = VideoFrameMap.sourceTime(of: posedVideo, atDocumentFrame: frame,
                                                        celStartFrame: bakedCel.startFrame,
                                                        documentFPS: posedVideo.resolvedFrameRate)
                    guard let decoded = videoFrames.frame(assetURL: posedVideo.assetURL, at: time),
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
}
