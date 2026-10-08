import Foundation

// MARK: - What a bake will do, as a value — TODO (131)
//
// A bake is planned before it is performed, and the plan is plain data: which layers beneath the baking
// layer take it, how each is carried (colour into ink, pixels, a flat colour's own fill), where each cel
// is cut, and what is left as it was. Planning reads the document and writes nothing, so the confirmation
// can say exactly what a tap will do and the fast tier can read the same plan the artist's alert does;
// `CanvasManager.bakeLayer` performs it. `bakePoseToCels` (Bake Animation) is the same machinery with
// one cel and one kind of treatment, which is why the segment type below is generic rather than owned
// by either. A Repeat is the third case: its treatment is a time remap, so what is cut into runs is a
// stretch of frames (`LoopBake`) rather than a cel the layer already holds.

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
        /// What a Repeat's loop writes onto this layer. Nil for every other baking layer.
        var loop: LoopBake?

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

    /// **The drawing a Repeat showed over a run of frames** — the cel it read (nil where it read none:
    /// the loop showed nothing there) and, for a cel whose picture moves with its own time, how many
    /// frames later than the run's own frame it read it. A still has offset 0, so the same still on
    /// consecutive frames — across a cycle's end too — is one run, and so one cel.
    struct Replay: Equatable {
        var source: UUID?
        var offset: Int
    }

    /// **A Repeat's looped frames on one layer, cut into the runs that show one drawing.** The loop is a
    /// time remap, not a colour or a pose, so it is not written into a cel the layer holds: each run
    /// whose drawing the layer does not hold on those frames becomes a cel of its own
    /// (`CanvasManager.replay`).
    struct LoopBake: Equatable {
        /// One block of the Repeat layer's looped frames — everything after its first cycle. `start` is
        /// its first frame, the segments' `localStart` counts from it, and a nil treatment is a run the
        /// layer already shows as it is.
        struct Stretch: Equatable {
            let start: Int
            var segments: [BakeSegment<Replay?>]
        }

        var stretches: [Stretch]
        /// How many cels the layer gains once every run is written — the drawings a run replaces and the
        /// pieces a cut leaves are counted, so it is the figure every save then pays for.
        let addedCels: Int

        /// The runs that get a drawing of their own, in frame order, with what each one shows.
        var runs: [(frames: Range<Int>, replay: Replay)] { Self.runs(of: stretches) }

        /// `cels` are the frame spans the layer holds now: each keeps the pieces outside every run, each
        /// run that shows a drawing adds one, and a layer is never left with none.
        init(stretches: [Stretch], over cels: [Range<Int>]) {
            self.stretches = stretches
            let runs = Self.runs(of: stretches)
            let written = runs.filter { $0.replay.source != nil }.count
            let kept = cels.reduce(0) { $0 + Self.pieces(of: $1, outside: runs.map(\.frames)) }
            addedCels = max(kept + written, 1) - cels.count
        }

        private static func runs(of stretches: [Stretch]) -> [(frames: Range<Int>, replay: Replay)] {
            stretches.flatMap { stretch in
                stretch.segments.compactMap { segment in
                    segment.treatment.map { replay in
                        let first = stretch.start + segment.localStart
                        return (first ..< first + segment.length, replay)
                    }
                }
            }
        }

        /// How many cels remain of `span` once `runs` are taken out of it.
        private static func pieces(of span: Range<Int>, outside runs: [Range<Int>]) -> Int {
            var pieces = 0, cursor = span.lowerBound
            for run in runs.sorted(by: { $0.lowerBound < $1.lowerBound }) where run.overlaps(span) {
                if run.lowerBound > cursor { pieces += 1 }
                cursor = max(cursor, run.upperBound)
            }
            return cursor < span.upperBound ? pieces + 1 : pieces
        }
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
            /// A video or a live stream cannot be copied onto the frames a loop repeats it over.
            case cannotBeCopied
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
                case .cannotBeCopied: return "a video or a stream in it can't be copied"
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
        /// A Repeat layer's loop repeats more than the drawings under it — an opacity, a grade, a pose —
        /// and drawings alone cannot carry that.
        case loopsMoreThanDrawings

        var phrase: String {
            switch self {
            case .notABakingLayer: return "this layer holds drawings, so it is merged rather than baked"
            case .hidden: return "this layer is hidden, so it changes nothing to bake"
            case .partialCoverage: return "this layer has a mask, so it reaches only part of what is beneath it"
            case .insideACombiner: return "a layer inside a combiner acts on nothing"
            case .nothingBeneath: return "there is nothing beneath this layer"
            case .nothingToBake: return "it has nothing to change in the layers beneath it"
            case .loopsMoreThanDrawings:
                return "something under this Repeat also changes over time — an opacity, a grade or a move — "
                    + "and the loop repeats that too, which drawings can't carry"
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
                let added = max(0, layer.cels.reduce(0) { $0 + $1.addedCels } + (layer.loop?.addedCels ?? 0))
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
