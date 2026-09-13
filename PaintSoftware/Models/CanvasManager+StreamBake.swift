import Combine
import Foundation
import UIKit

/// **STREAM.md §5.4 and §5.5 — Freeze and Bake Frame**, the two verbs the stream bar carries, and
/// the one question the bar asks to know whether to be on screen at all.
///
/// Bake Frame is `bakeVideoToCels`' recipe (`CanvasManager+VideoBake.swift`) pointed at one frame
/// rather than a whole block: `splitCel` inside one `withInterpolationUndo(label:touching:)`, the
/// swap of the stream for a `VectorImageElement` with the same placement, refusals as an outcome
/// enum surfaced through `CanvasNotice`, never a silent `Bool`. That file's doc comment carries the
/// two arguments this one leans on without repeating them — why `withStructureUndo` alone would
/// corrupt the first cel's undo (the left half keeps the block's own `VectorCanvas` instance, so
/// `touching: [vector]` is what restores it), and why a cel's pose is baked into the written
/// geometry rather than dropped.
extension CanvasManager {

    /// What Bake Frame returns. Not `@discardableResult` — `VideoBakeOutcome`'s reason.
    enum StreamBakeOutcome: Equatable {
        /// The cel now spanning exactly the baked frame holds a placed image of the stream's
        /// picture, and the cels either side (if the split made any) hold the stream, untouched.
        case baked
        /// Nothing was written. See `StreamBakeRefusal.phrase` for what the artist is told.
        case refused(StreamBakeRefusal)
    }

    /// Why Bake Frame refused, in the artist's own terms — `VideoBakeRefusal`'s pattern.
    enum StreamBakeRefusal: Equatable {
        /// The laptop has not sent a picture yet, and there is no saved one either: the element is
        /// on its placeholder, and a bake of a placeholder is not what the button promises.
        case noFrameYet
        /// The cel at that frame on that layer holds no stream. The bar shows only on one that
        /// does, so a real artist never meets this; a direct caller or a test does.
        case notOnStreamCel

        var phrase: String {
            switch self {
            case .noFrameYet: return "No picture from the computer yet"
            case .notOnStreamCel: return "This frame doesn't hold a screen stream"
            }
        }
    }

    // MARK: - The bar's question (STREAM.md §5.7)

    /// **The stream element the bar is about, or nil when there is no bar** — the active layer's
    /// cel at the current frame holds a stream. State-driven, deliberately: this is what
    /// `DrawingView.bottomDock` reads to show `StreamBar`, and it is not an `ActivePanel` case, so
    /// `canvasInteractionBegan`'s `activePanel = .none` cannot close it — a two-finger pan keeps
    /// the bar up. The Move bar wins while a piece floats; `bottomDock` asks that separately.
    ///
    /// The first stream on the cel, if there are several: one Stream Screen makes one layer with
    /// one element (§2.2), so a cel with two is a cel somebody assembled by hand, and the bar
    /// serves the one on top of the display list's bottom.
    @MainActor
    var activeStreamCel: (layerIndex: Int, celIndex: Int, element: VectorStreamElement)? {
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIndex].vector, vector.holdsStream,
              let stream = vector.streams.first else { return nil }
        return (currentLayerIndex, celIndex, stream)
    }

    /// **Whether the canvas at rest is the baked composite rather than the flat row of hosts** —
    /// the case `ScreenStreamCoordinator`'s header names, where a live frame cannot reach the
    /// screen because `committedVersion` keeps the bake blind to it. Asked of the whole document,
    /// exactly as `sandwichEngagesOnCanvas` asks it minus the two transient clauses (playback, a
    /// float), so the bar's note is about the document's *shape* and does not flicker with a
    /// gesture. The bar prints `StreamBarState.sandwichNote` while this is true.
    @MainActor
    var streamPictureIsHeldByTheSandwich: Bool {
        renderTree(atFrame: currentFrame).needsCompositorOnCanvas || hasContainerPoseInForce
    }

    // MARK: - The address row (STREAM.md §5.7)

    /// **Points an existing stream element at a different laptop** — the bar's address row, which
    /// reopens `StreamConnectSheet` with this in hand rather than inserting a second layer. The
    /// element keeps its placement, its frozen flag and its last picture; host, port, label and the
    /// laptop's size change. One undo step, since it is an edit to the document the artist made on
    /// purpose; the old connection stops on the next `sync()` if nothing else names it.
    @MainActor
    @discardableResult
    func retargetStream(_ target: StreamRetarget, host: String, port: UInt16, status: StreamStatus) -> Bool {
        guard layers.indices.contains(target.layerIndex),
              layers[target.layerIndex].cels.indices.contains(target.celIndex),
              let vector = layers[target.layerIndex].cels[target.celIndex].vector,
              vector.streams.contains(where: { $0.id == target.elementID }) else { return false }
        let layerID = layers[target.layerIndex].id
        let celID = layers[target.layerIndex].cels[target.celIndex].id
        withInterpolationUndo(label: .retargetStream, touching: [vector]) {
            vector.elements = vector.elements.map { element in
                guard case .stream(var stream) = element, stream.id == target.elementID else { return element }
                stream.host = host
                stream.port = port
                stream.sourceLabel = status.sourceLabel
                if status.width > 0, status.height > 0 {
                    stream.naturalSize = CGSize(width: status.width, height: status.height)
                }
                return .stream(stream)
            }
            vector.bumpVersion()
            celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }
        streamCoordinator.sync()
        return true
    }

    // MARK: - Freeze (STREAM.md §5.4)

    /// **Sets one stream element's `isFrozen`.** Not an undo step — the render-resolution knob's
    /// precedent: a viewing state persisted with the document, which the artist toggles rather than
    /// edits. The picture on the cel is untouched (`VectorCanvas.setStreamFrozen` invalidates
    /// nothing); the coordinator's tick stops feeding the element, and the client pauses the laptop
    /// once every element on that connection is frozen. Returns whether anything changed.
    ///
    /// Addressed by cel and not by element alone, because a split copies an element's id into a
    /// second cel: after a Bake Frame the cels either side of the baked one hold two streams with
    /// one id, and the artist freezes the one on the frame they are standing on.
    @MainActor
    @discardableResult
    func setStreamFrozen(layerIndex: Int, celIndex: Int, elementID: UUID, _ frozen: Bool) -> Bool {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let vector = layers[layerIndex].cels[celIndex].vector,
              vector.setStreamFrozen(id: elementID, frozen),
              let stream = vector.streams.first(where: { $0.id == elementID }) else { return false }
        // The bar reads `isFrozen` off the element through `activeStreamCel`, and a canvas is a
        // class — nothing published moved, so say so.
        objectWillChange.send()
        streamCoordinator.elementFrozenStateChanged(
            endpoint: StreamEndpoint(host: stream.host, port: stream.port), unfroze: !frozen)
        return true
    }

    // MARK: - Bake Frame (STREAM.md §2.4, §5.5)

    /// **Splits the cel at `frame` and replaces the stream on the resulting one-frame cel with a
    /// placed image of what it was showing.** Four frames, one cel, on frame 2 → [1] [2] [3–4], and
    /// only [2] changes; on frame 1 → [1] [2–4]; on frame 4 → [1–3] [4]; a one-frame cel is the
    /// swap alone. The playhead stays where it is (§2.4, answer 4). One undo step.
    ///
    /// **The picture is `displayFrame`** — the live frame, the frozen one, or the one the last save
    /// wrote and the load put back — so a bake works while frozen and bakes the frozen picture, and
    /// works with the laptop off and bakes the last picture it sent. No frame at all is
    /// `.noFrameYet`, before anything is touched.
    ///
    /// **Which elements are re-identified, and which are not.** The image is minted fresh
    /// (`VectorImageElement.init` takes a new id), and every other element on the baked cel is
    /// `reidentified()` as the video bake does — the baked cel is a new drawing. The cels either
    /// side are `splitCel`'s own copies and keep their ids verbatim, the stream's included: that is
    /// what Split Drawing does to every cel it cuts, the two neighbours *are* the same drawing shown
    /// on either side of the bake, and nothing keys on a stream id across cels —
    /// `ScreenStreamCoordinator` keys its drawn-frame memo on the cel *and* the element for exactly
    /// this case. `StreamBakeLogicTests` pins both halves.
    ///
    /// **The snapshot is the frame's own pixels at the laptop's size** (§6), unless the decoded
    /// frame and the STATUS-reported `naturalSize` disagree — then it is resampled to `naturalSize`,
    /// because the stream drew its frame *into* that rect and a placed image's rect is its own
    /// pixel size, so any other choice moves the picture on canvas by the ratio of the two.
    @MainActor
    func bakeStreamFrame(layerIndex: Int, celIndex: Int, atFrame frame: Int) -> StreamBakeOutcome {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else {
            return .refused(.notOnStreamCel)
        }
        let cel = layers[layerIndex].cels[celIndex]
        guard frame >= cel.startFrame, frame < cel.endFrame,
              let vector = cel.vector, vector.holdsStream,
              let stream = vector.streams.first else {
            return .refused(.notOnStreamCel)
        }
        guard let picture = stream.displayFrame else {
            return .refused(.noFrameYet)
        }
        let snapshot = Self.streamSnapshot(picture, fitting: stream.naturalSize)
        let streamID = stream.id

        // KEYFRAMES §6's recipe: a pending float baked first, so it lands as its own earlier step.
        commitAllInteractiveState()

        // `touching: [vector]`: the block's own canvas is the one `splitCel` never copies (it keeps
        // the left half), and it is the one the swap mutates whenever `frame` is the block's first
        // frame — see `bakeVideoToCels`. Every other cel the split makes is a fresh object the
        // restored `[Layer]` simply drops.
        withInterpolationUndo(label: .bakeStreamFrame, touching: [vector]) {
            // Cut in front of the frame, then behind it. Each `splitCel` re-sorts the cel array, so
            // the index is re-found from the frame rather than carried across the first cut.
            if frame > cel.startFrame,
               let index = activeCelIndex(inLayer: layerIndex, atFrame: cel.startFrame) {
                splitCel(layerIndex: layerIndex, celIndex: index, atFrame: frame)
            }
            if frame + 1 < cel.endFrame,
               let index = activeCelIndex(inLayer: layerIndex, atFrame: frame) {
                splitCel(layerIndex: layerIndex, celIndex: index, atFrame: frame + 1)
            }
            guard let index = activeCelIndex(inLayer: layerIndex, atFrame: frame),
                  let baked = layers[layerIndex].cels[index].vector else { return }
            let bakedCel = layers[layerIndex].cels[index]
            // The cel is one frame long now, so its local frame 0 is `frame`: a pose channel on it
            // is baked into the geometry and the channel dropped, `bakeVideoToCels`' argument.
            let mappings = Self.poseMappings(bakedCel.transformTracks, atCelLocalFrame: 0)
            let posed = Self.posed(baked.elements, through: mappings, inheriting: nil)
            let rebuilt = posed.map { element -> VectorElement in
                guard case .stream(let posedStream) = element, posedStream.id == streamID else {
                    return element.reidentified()
                }
                var image = VectorImageElement(image: snapshot,
                                               transform: posedStream.transform,
                                               aspect: posedStream.aspect,
                                               stretchAxis: posedStream.stretchAxis,
                                               mirrored: posedStream.mirrored)
                image.animationGroupID = posedStream.animationGroupID
                return .image(image)
            }
            baked.elements = rebuilt
            baked.bumpVersion()
            layers[layerIndex].cels[index].transformTracks = [:]
            layers[layerIndex].cels[index].pendingPoseBaselines = [:]
            celContentChangedOutsideStroke(layerID: layers[layerIndex].id, celID: bakedCel.id)
        }
        return .baked
    }

    /// The frame as the image element will carry it: its own pixels when they are the size the
    /// stream drew them at, and a resample to that size when they are not. A `UIImage` from a
    /// `CGImage` is at scale 1, so `size` is pixels.
    static func streamSnapshot(_ frame: UIImage, fitting naturalSize: CGSize) -> UIImage {
        guard naturalSize.width > 0, naturalSize.height > 0,
              frame.size != naturalSize || frame.scale != 1 else { return frame }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: naturalSize, format: format).image { _ in
            frame.draw(in: CGRect(origin: .zero, size: naturalSize))
        }
    }
}

/// Which stream element `StreamConnectSheet` is re-pointing, when it was opened from the bar's
/// address row rather than from Actions → Stream Screen.
struct StreamRetarget: Equatable {
    let layerIndex: Int
    let celIndex: Int
    let elementID: UUID
}
