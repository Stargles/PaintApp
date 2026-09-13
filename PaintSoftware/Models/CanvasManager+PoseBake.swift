import Foundation
import CoreGraphics

/// **KEYFRAMES.md §6 — bake an animated cel to drawings.** §2.9's verb: destructive, undoable, one
/// step, and it exists so the artist can draw on the in-betweens. It is never a performance
/// instruction (§4.6 is the playback cache), and nothing here is offered as one.
///
/// The recipe is `bakePreciseStrokes`'s, by way of `bakeVideoToCels`: commit any interactive state
/// first, resolve everything from the *original* cel before touching it, cut the block into one cel
/// per distinct picture with `splitCel`, rewrite each one under fresh ids, and register one undo
/// step over the lot.
extension CanvasManager {

    /// What a pose bake returns — `VideoBakeOutcome`'s shape, for the reason given there: a refusal
    /// carries its sentence rather than being a `Bool` a caller can drop.
    enum PoseBakeOutcome: Equatable {
        /// One cel per distinct picture the animation showed over the block, minted fresh. `cels` is
        /// `poseBakeCelCount`'s answer for the same block, so the confirmation can name it before
        /// anything is written.
        case baked(cels: Int)
        case refused(PoseBakeRefusal)
    }

    /// Why a pose bake refused, in the artist's own terms. The menu row hides the first case, so a
    /// real artist never reads it; a direct caller or a test gets a named reason instead of a trap.
    enum PoseBakeRefusal: Equatable {
        /// The cel carries no pose channel — there is no motion to turn into drawings.
        case notAnimated
        /// The cel has no vector tier to write the posed ink into.
        case noDrawing

        var phrase: String {
            switch self {
            case .notAnimated: return "this block isn't animated"
            case .noDrawing: return "this block has no drawing to bake"
            }
        }
    }

    /// **One run of frames over which the animation shows one picture** — the unit a bake writes a
    /// cel for. `localStart` and `length` are cel-local; `mappings` is what `poseMappings` resolved
    /// at every frame of the run, identical across it by construction.
    struct PoseBakeSegment {
        var localStart: Int
        var length: Int
        var mappings: [(TransformChannelID, PoseMap)]
    }

    /// **Where the bake cuts, resolved on the cel as it stands.** §2.10 says a channel holds its
    /// evaluated pose for `step` frames, and §6 says a bake must honour that — *"a cel animated on
    /// twos bakes to 24 cels, not 48"*. Rather than reading `step` off each track and intersecting
    /// the grids (two channels can hold on different steps), this asks the same question the render
    /// asks — what maps does frame *f* resolve to — and starts a new segment wherever the answer
    /// changes. That reduces to the step grid when the pose is moving, and it also folds the
    /// constant hold past a track's last key into one cel rather than a drawing per frame of it. A
    /// bake never mints two cels of the same picture: `PosedCelIdentity` already treats two frames
    /// whose maps resolve equal as one flatten, and the cels this writes follow the same reading.
    ///
    /// **Resolved before the first `splitCel`, and that order is load-bearing.** §3.1 says a split
    /// re-parameterises the segment it cuts on both sides — *"a single bezier cannot be two beziers"*
    /// — so the halves show the frames between the keys differently from the whole, and a bake that
    /// re-read each half after cutting would bake a picture the artist never saw (MEASURED by
    /// mutation: on a bezier pair every middle frame changed; on a `.linear` pair none did, since a
    /// linear blend subdivides exactly). `split` also re-anchors the right half's `step` at the cut,
    /// which this bake's cuts happen to tolerate — they land on the grid — but the first reason is
    /// enough. Every segment's maps come from the uncut track.
    ///
    /// `frameCount` is the span in frames; `tracks` the cel's own channels. Empty for a cel with no
    /// span.
    static func poseBakeSegments(tracks: [String: TransformTrack],
                                 frameCount: Int) -> [PoseBakeSegment] {
        guard frameCount > 0 else { return [] }
        var segments: [PoseBakeSegment] = []
        for local in 0..<frameCount {
            let mappings = poseMappings(tracks, atCelLocalFrame: local)
            if let last = segments.last, Self.sameMappings(last.mappings, mappings) {
                segments[segments.count - 1].length += 1
            } else {
                segments.append(PoseBakeSegment(localStart: local, length: 1, mappings: mappings))
            }
        }
        return segments
    }

    private static func sameMappings(_ a: [(TransformChannelID, PoseMap)],
                                     _ b: [(TransformChannelID, PoseMap)]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.0 != y.0 || x.1 != y.1 { return false }
        return true
    }

    /// Whether the cel menu offers Bake on this block: the cel carries a pose channel. Interpolated
    /// cels carry none (§2.18), so an in-between is excluded by the same test.
    func celHasPoseAnimation(layerIndex: Int, celIndex: Int) -> Bool {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return false }
        return !layers[layerIndex].cels[celIndex].transformTracks.isEmpty
    }

    /// **How many drawings the bake would make of this block** — what the confirmation names, read
    /// at the moment the row is tapped so the sentence cannot drift from the bake that follows.
    func poseBakeCelCount(layerIndex: Int, celIndex: Int) -> Int {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return 0 }
        let cel = layers[layerIndex].cels[celIndex]
        return Self.poseBakeSegments(tracks: cel.transformTracks, frameCount: cel.frameCount).count
    }

    /// Bakes the pose animation on `layers[layerIndex].cels[celIndex]` into one cel of concrete
    /// drawing per distinct picture the animation showed, and clears the channels it consumed.
    ///
    /// **What is written is `posed`'s display list, persisted.** `Self.baked` composes each element's
    /// own channels exactly as the render does and commits the result through
    /// `VectorCanvas.baking`, which is the projective commit taken on purpose for an affine map: the
    /// stroke keeps its rest walk as a stored `distort`, so the baked frame stamps the same dabs the
    /// animated frame stamped — before a save and after a reload. `PoseBakeLogicTests` pins that
    /// byte for byte on both compositor backends. A stroke committed through the affine arm instead
    /// re-walks in posed space, which is the re-phase §4.2 removed; a stroke stored with `posing`'s
    /// transient walk draws right until the document is reopened.
    ///
    /// **Fresh ids on every element of every baked cel.** `splitCel` copies through `makeCopy()`,
    /// which keeps ids — correct for a split, whose halves are one drawing shown twice — and wrong
    /// here, where the point is *n* independent drawings. `VectorElement.reidentified()` keeps every
    /// other field, the group tags included: the artist's grouping outlives the motion it was made
    /// for, so a later Move on a baked cel finds the group it expects.
    ///
    /// **One undo step, `bakeVideoToCels`'s bracket for `bakeVideoToCels`'s reason.** `splitCel`
    /// never copies the *left* half's canvas, so the first baked cel keeps mutating the very
    /// `VectorCanvas` the block had; a `[Layer]` snapshot restores a cel that still points at that
    /// object, now holding baked ink. `withInterpolationUndo(touching:)` snapshots and restores its
    /// `elements` explicitly. Every other baked cel's canvas was minted after the snapshot and is
    /// dropped by restoring the array. The nested `withStructureUndo` in each `splitCel` is a no-op
    /// bracket while this one is open, which is the re-entrancy §6 says to rely on deliberately.
    ///
    /// **The channels go with the motion.** `transformTracks` and `pendingPoseBaselines` are cleared
    /// on every baked cel: the bake replaced the derivation with the thing it derived, and a live rig
    /// under the drawings the artist is about to edit would be a lie (§2.9). The layer's bare
    /// keyframe marks are not touched — they are the artist's own marks, in absolute frames, and
    /// §2.28 already drops a mark wherever a key landed on it.
    ///
    /// **A container pose above the cel is not consumed** — see `Self.baked`. **A Repeat above the
    /// cel needs nothing here**: the cel's channels are numbered in its own frames, which are the
    /// source frames the repeat reads (TRANSFORM_LAYER.md §7), so the segments are resolved in that
    /// base by construction and the repeated document frames keep showing the same pictures.
    ///
    /// **The crop banner can fire from inside this step.** A document written before TODO (62)'s
    /// ruling can carry a key past its span; `splitCel` crops it and the bracket raises the notice,
    /// which was ruled acceptable for a bake (the key was outside the frames the bake draws).
    func bakePoseToCels(layerIndex: Int, celIndex: Int) -> PoseBakeOutcome {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else {
            return .refused(.notAnimated)
        }
        let cel = layers[layerIndex].cels[celIndex]
        guard !cel.transformTracks.isEmpty else { return .refused(.notAnimated) }
        guard let vector = cel.vector else { return .refused(.noDrawing) }

        // §6's recipe: a float under the artist's finger lands as its own earlier step rather than
        // being baked mid-motion — and it un-suppresses whatever it was carrying, so the display list
        // read below is the whole drawing.
        commitAllInteractiveState()

        let startFrame = cel.startFrame
        let layerID = layers[layerIndex].id
        // From the uncut track — see `poseBakeSegments` for why the order matters.
        let segments = Self.poseBakeSegments(tracks: cel.transformTracks, frameCount: cel.frameCount)
        guard !segments.isEmpty else { return .refused(.notAnimated) }

        withInterpolationUndo(label: .bakePoseToCels, touching: [vector]) {
            // Cut the block at each segment boundary, left to right. Each nested `withStructureUndo`
            // is a no-op bracket, because this one is already open.
            for segment in segments.dropFirst() {
                let cut = startFrame + segment.localStart
                guard let idx = activeCelIndex(inLayer: layerIndex, atFrame: cut - 1) else { continue }
                splitCel(layerIndex: layerIndex, celIndex: idx, atFrame: cut)
            }

            // Every cel now spans exactly one segment. Write each one's picture and take its
            // channels away.
            for segment in segments {
                let frame = startFrame + segment.localStart
                guard let idx = activeCelIndex(inLayer: layerIndex, atFrame: frame),
                      let bakedVector = layers[layerIndex].cels[idx].vector else { continue }
                let bakedCel = layers[layerIndex].cels[idx]
                bakedVector.elements = Self.baked(bakedVector.elements, through: segment.mappings)
                bakedVector.bumpVersion()
                layers[layerIndex].cels[idx].transformTracks = [:]
                layers[layerIndex].cels[idx].pendingPoseBaselines = [:]
                celContentChangedOutsideStroke(layerID: layerID, celID: bakedCel.id)
            }
        }

        return .baked(cels: segments.count)
    }

    // MARK: - The cost the artist is told

    /// **What every future save costs per cel, MEASURED on this Mac** — KEYFRAMES.md §6's second
    /// disclosed cost. `ProjectStore` re-encodes every cel on every save with no skip-unchanged path,
    /// so a bake that makes *n* cels of one raises every later save by `n − 1` of these for the life
    /// of the document, and the confirmation says so with the number.
    ///
    /// **Provenance.** `PerfBaselineTests.testWhatAVectorOnlyDocumentCostsToSaveAndLoad` reports
    /// `saveMsPerCel` for a sixty-cel vector-only document (`movingSceneStrokes` on every cel, at
    /// 2048×2048, `pngsEncoded` 0) — the kind of cel a pose bake writes, since its ink is geometry.
    /// **MEASURED 2026-09-12 on this Mac, Debug, 83% idle, three runs: 2.6 / 2.2 / 2.4 ms a cel**
    /// (`saveAwaited` 153 / 133 / 145 ms over sixty cels); this is the median. The 15.2 ms/cel figure
    /// KEYFRAMES §6 and PERFORMANCE.md §6 carry is the *raster* cel's `pngData()`, MEASURED
    /// 2026-08-20 before the encode fan-out; a baked drawing pays the vector sidecar and its
    /// thumbnail, not a canvas-sized PNG. It scales with the ink on the cel, not the canvas, so a
    /// dense drawing costs more than this and an empty one less. Re-take on a machine that is not
    /// this one before quoting it elsewhere, and read `PerfBaselineTests`' printed row rather than
    /// this constant — the constant is what the artist is told, the row is what is true today.
    static let measuredSaveMillisecondsPerVectorCel: Double = 2.4

    /// The raster cel's figure, for `videoBakeConfirmationMessage`: a video bakes to *images*, and a
    /// placed image is written as its own PNG. MEASURED 2026-08-20 (PERFORMANCE.md §6), 15.0–16.9 ms
    /// across a 4× range of documents, 95% of it `pngData()`.
    static let measuredSaveMillisecondsPerRasterCel: Double = 15.2

    /// **The sentence's cost clause, computed from the count** — never a typed number. `added` is
    /// how many cels the bake makes beyond the one it replaces; `perCel` is the measured rate.
    static func saveCostPhrase(addedCels added: Int, millisecondsPerCel perCel: Double) -> String {
        let ms = Double(added) * perCel
        return ms >= 1000
            ? String(format: "about %.1f s", ms / 1000)
            : "about \(Int(ms.rounded())) ms"
    }

    /// The confirmation for Bake on an animated block, in artist terms: what it makes, what every
    /// save then costs, and that it can be undone. Pure, so the fast tier reads the same sentence
    /// the alert shows.
    static func poseBakeConfirmationMessage(cels: Int) -> String {
        let added = max(cels - 1, 0)
        guard added > 0 else {
            return "This block shows one picture over its whole length, so baking makes 1 drawing "
                + "from 1 and takes the animation off it. This can be undone."
        }
        let cost = saveCostPhrase(addedCels: added, millisecondsPerCel: measuredSaveMillisecondsPerVectorCel)
        return "Baking makes \(cels) drawings from 1 and takes the animation off them, so you can draw "
            + "on the in-betweens. Every save of this document will then take \(cost) longer. This can be undone."
    }

    /// The video bake's confirmation — VIDEO.md §8 stage 8 — moved here from the timeline view so
    /// that its number is computed where a test can see it, beside the pose bake's.
    static func videoBakeConfirmationMessage(cels: Int) -> String {
        let added = max(cels - 1, 0)
        let plural = cels == 1 ? "cel" : "cels"
        guard added > 0 else {
            return "This turns the block into 1 cel of images. This can be undone."
        }
        let cost = saveCostPhrase(addedCels: added, millisecondsPerCel: measuredSaveMillisecondsPerRasterCel)
        let addedPlural = added == 1 ? "cel" : "cels"
        return "This turns the block into \(cels) \(plural) of images. Every future save then writes "
            + "\(added) more \(addedPlural) — \(cost) more each time, at this app's own measured "
            + "rate. This can be undone."
    }
}
