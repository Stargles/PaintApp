import Foundation

// MARK: - What a bake will do, as a value — TODO (131)
//
// A bake is planned before it is performed, and the plan is plain data: which layers beneath the baking
// layer take it, how each is carried (colour into ink, pixels, a flat colour's own fill), where each cel
// is cut, and what is left as it was. Planning reads the document and writes nothing, so the confirmation
// can say exactly what a tap will do and the fast tier can read the same plan the artist's alert does;
// `CanvasManager.bakeLayer` performs it. `bakePoseToCels` (Bake Animation) is the same machinery with
// one cel and one kind of treatment, which is why the segment type below is generic rather than owned
// by either.

extension CanvasManager {

    // MARK: - Runs of frames

    /// **One run of frames over which a bake treats a cel's picture alike** — the unit a bake cuts a
    /// cel at and writes a drawing for. `localStart` is cel-local; the treatment is identical across
    /// the run by construction, nil meaning *this run is left as it is*.
    struct BakeSegment<Treatment: Equatable>: Equatable {
        var localStart: Int
        var length: Int
        var treatment: Treatment
    }

    /// **Where a bake cuts: wherever the treatment a frame would receive changes.** `treatment` is
    /// asked once per frame of a span of `frameCount`, and a new segment starts whenever the answer
    /// differs from the last — so a treatment that holds across a stretch stays one drawing, and one
    /// that moves every frame becomes a drawing a frame. Empty for a span of no frames.
    ///
    /// **Resolved before the first cut and never re-read after one**, which is Bake Animation's rule
    /// (KEYFRAMES.md §3.1): a split re-parameterises the segment it cuts on both sides, so a bake that
    /// asked again of each half would bake a picture the artist never saw.
    static func bakeSegments<Treatment: Equatable>(frameCount: Int,
                                                   treatment: (Int) -> Treatment) -> [BakeSegment<Treatment>] {
        guard frameCount > 0 else { return [] }
        var segments: [BakeSegment<Treatment>] = []
        for local in 0..<frameCount {
            let wanted = treatment(local)
            if let last = segments.last, last.treatment == wanted {
                segments[segments.count - 1].length += 1
            } else {
                segments.append(BakeSegment(localStart: local, length: 1, treatment: wanted))
            }
        }
        return segments
    }

    // MARK: - What a run receives

    /// What a bake writes into one run of a cel.
    enum BakeTreatment: Equatable {
        /// An effect or a flat colour carried into the drawing (`BakeOperation`).
        case operation(BakeOperation)
        /// A pose carried into the drawing's geometry (`PoseRun`).
        case pose(PoseRun)
    }

    /// **The poses a run of frames is shown through** — the cel's own channels, resolved at the frame
    /// (`poseMappings`'s order), and the container pose still to be carried into the geometry on top
    /// of them (§4.4's, or for Bake the transformation layer's own share of it).
    struct PoseRun: Equatable {
        var mappings: [(TransformChannelID, PoseMap)]
        var inherited: PoseMap?

        static func == (lhs: PoseRun, rhs: PoseRun) -> Bool {
            lhs.inherited == rhs.inherited && lhs.mappings.count == rhs.mappings.count
                && zip(lhs.mappings, rhs.mappings).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    // MARK: - The plan

    /// One layer beneath the baking layer, and how it takes the bake.
    struct LayerBake: Equatable {
        /// How the layer's drawing is rewritten.
        enum Medium: Equatable {
            /// A vector layer's display list: colours taken through the operation, or geometry through
            /// the pose. The layer stays a vector layer and every stroke stays a stroke.
            case ink
            /// The layer's pixels. A raster layer's own; or a vector layer turned into one first
            /// (`rasterizes`), because the effect depends on position and no per-object colour
            /// stands for it.
            case pixels(rasterizes: Bool)
            /// A flat-colour value layer's own colour — there is no cel content to rewrite.
            case flatColour(BakeOperation)
        }

        let layerID: UUID
        let name: String
        var medium: Medium
        /// The cels the bake touches, each cut where its treatment changes. Empty for a flat colour.
        var cels: [CelBake]

        var rasterizes: Bool {
            if case .pixels(let rasterizes) = medium { return rasterizes }
            return false
        }
    }

    /// One cel and the runs it is cut into.
    struct CelBake: Equatable {
        let celID: UUID
        var segments: [BakeSegment<BakeTreatment?>]

        /// How many drawings the cut adds — none if no run is treated.
        var addedCels: Int { segments.contains { $0.treatment != nil } ? segments.count - 1 : 0 }
    }

    /// **Something a bake left exactly as it was, and why** — the artist is told, because the layer
    /// that carried the effect is gone and a drawing that did not take it will no longer match.
    struct BakeLeftover: Equatable {
        enum Reason: Equatable {
            /// The layer has a mask, or is clipped to the one below: the effect reaches only part of
            /// it, and no one colour stands for part of a drawing.
            case masked
            /// A layer or group between the baking layer and this one has an effect of its own, so the
            /// order the two apply in could not be kept by baking into the colours. Name of it.
            case underAnotherEffect(String)
            /// A group that combines its layers as a node, which no colour can follow. Name of it.
            case insideACombiner(String)
            /// A Repeat layer between them reads this one at another frame than the baking layer.
            case underARepeat(String)
            /// The baking layer's bar covers only some of a flat colour, which has no frames to cut.
            case partlyCovered
            /// A video or a live stream: there is no colour in it, or asset, to write the result to.
            case cannotTakeColour
            /// An effect that needs pixels has nothing to act on in a single flat colour.
            case flatColourNeedsAColourEffect
            /// A drawing laid between two others, shown by the two it is between rather than stored.
            case inBetween
            /// A pose that collapses the layer to a line, which cannot be carried around.
            case cannotBeCarried
            /// Its drawings are animated by pose channels, which painting them into pixels would flatten
            /// to one frame — Bake Animation turns the motion into drawings first.
            case animatedDrawing

            var phrase: String {
                switch self {
                case .masked: return "it has a mask"
                case .underAnotherEffect(let name): return "it sits under \(name), which has an effect of its own"
                case .insideACombiner(let name): return "it is inside \(name), which combines its layers"
                case .underARepeat(let name): return "it sits under \(name), which repeats it"
                case .partlyCovered: return "the layer only covers part of it"
                case .cannotTakeColour: return "a video or a stream in it can't take the effect"
                case .flatColourNeedsAColourEffect: return "this effect can't be applied to one flat colour"
                case .inBetween: return "it is an in-between, which is worked out from the drawings either side"
                case .cannotBeCarried: return "the pose squashes it flat"
                case .animatedDrawing: return "its drawings are animated, so bake that animation first"
                }
            }
        }

        var name: String
        var reason: Reason
    }

    /// Why a bake did not run — the artist's own terms, `PoseBakeRefusal`'s shape.
    enum BakeRefusal: Equatable {
        /// The layer holds drawings; it is merged, not baked. The row is not offered on one, so only a
        /// direct caller meets this.
        case notABakingLayer
        /// A hidden layer does nothing to the picture, so there is nothing to bake in.
        case hidden
        /// The baking layer has a mask or is clipped, so it reaches only part of what is beneath it.
        case partialCoverage
        /// A layer inside a combiner acts on nothing: the entries beside it are the other operands.
        case insideACombiner
        /// There is nothing beneath it in its group.
        case nothingBeneath
        /// Everything beneath it was either outside its frames or left as it was.
        case nothingToBake([BakeLeftover])
        /// A Repeat layer is a loop in time rather than a pose, so there is no drawing to carry it into.
        case repeatsInTime

        var phrase: String {
            switch self {
            case .notABakingLayer: return "this layer holds drawings, so it is merged rather than baked"
            case .hidden: return "this layer is hidden, so it changes nothing to bake"
            case .partialCoverage: return "this layer has a mask, so it reaches only part of what is beneath it"
            case .insideACombiner: return "a layer inside a combiner acts on nothing"
            case .nothingBeneath: return "there is nothing beneath this layer"
            case .nothingToBake: return "it has nothing to change in the layers beneath it"
            case .repeatsInTime: return "a Repeat layer loops time rather than moving drawings"
            }
        }
    }

    /// What `bakePlan` answers.
    enum BakePlanResult: Equatable {
        case plan(BakePlan)
        case refused(BakeRefusal)
    }

    /// What a bake does, planned and not yet done.
    struct BakePlan: Equatable {
        let bakerID: UUID
        let bakerName: String
        var layers: [LayerBake]
        var leftovers: [BakeLeftover]

        /// Names of the vector layers the bake turns into raster layers.
        var rasterizedLayerNames: [String] { layers.filter(\.rasterizes).map(\.name) }

        /// How many drawings the bake adds to the document, split by what they cost to save: a vector
        /// cel is a display list and a raster cel a canvas-sized picture.
        var addedCels: (vector: Int, raster: Int) {
            var vector = 0, raster = 0
            for layer in layers {
                let added = layer.cels.reduce(0) { $0 + $1.addedCels }
                switch layer.medium {
                case .ink: vector += added
                case .pixels: raster += added
                case .flatColour: break
                }
            }
            return (vector, raster)
        }

        /// **Whether the artist is asked first** — when the bake changes what a layer *is*, or what
        /// every save costs. A bake that only rewrites colours in place runs at once and can be undone.
        var needsConfirmation: Bool {
            let added = addedCels
            return !rasterizedLayerNames.isEmpty || added.vector + added.raster > 0
        }

        /// **The confirmation, in artist terms** — what becomes pixels, how many drawings are added,
        /// and what every save then costs, each computed from the plan and never typed. Pure, so the
        /// fast tier reads the same sentence the alert shows.
        var confirmationMessage: String {
            var sentences: [String] = []
            let rasterized = rasterizedLayerNames
            if !rasterized.isEmpty {
                let names = rasterized.joined(separator: ", ")
                sentences.append("\(names) will become \(rasterized.count == 1 ? "a raster layer" : "raster layers"): "
                    + "this effect works on pixels rather than on colours, so it is painted into them and "
                    + "the strokes can no longer be edited.")
            }
            let added = addedCels
            if added.vector + added.raster > 0 {
                let total = added.vector + added.raster
                let milliseconds = Double(added.vector) * CanvasManager.measuredSaveMillisecondsPerVectorCel
                    + Double(added.raster) * CanvasManager.measuredSaveMillisecondsPerRasterCel
                sentences.append("It adds \(total) \(total == 1 ? "drawing" : "drawings") — one for each stretch of "
                    + "frames where the result changes — so every save of this document will take "
                    + "\(CanvasManager.saveCostPhrase(milliseconds: milliseconds)) longer.")
            }
            sentences.append("\(bakerName) is removed. This can be undone.")
            return sentences.joined(separator: " ")
        }
    }
}
