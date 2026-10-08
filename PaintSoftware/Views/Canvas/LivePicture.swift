import UIKit

/// **The live picture: the bands of one rebuild, with the key and the cut they were minted
/// for** — wrapped as `UIImage` once so assigning them is an identity check rather than a
/// fresh wrapper, and therefore a Core Animation no-op, on every one of the many SwiftUI
/// passes that change nothing.
///
/// **`full` is not here any more: it is the baked frame** (RENDER.md §3.6, stage 4d). This is
/// the live picture and nothing else — a different product from the bake, keyed additionally
/// by where the tree is cut, and transient rather than stored.
///
/// **Two cuts, one product** (TODO (125)). Cut around the host, it is two thirds of the live
/// pair (TODO 145) and only makes a picture with the layer it was cut around: the third, the
/// active layer's own picture, went to its host in the same main-thread turn
/// (`finishSandwichRebuild`). Cut around a transform edit's runs, it is every band of the
/// frame, the moving ones re-posed per update from `mintMaps` (`showMovingBands`).
struct LivePicture {
    /// The `SandwichKey` the bands were minted at. Stale bands are still shown — at most one
    /// edit behind — while the rebuild that replaces them runs.
    let key: SandwichKey
    let cut: LivePairCut
    /// The frame they were minted at — what keeps a transform edit's bands from outliving a
    /// scrub after the finger lifts.
    let frame: Int
    /// One image per band, bottom-to-top; nil for a band the cut left empty, and for the run a
    /// host draws (a cut around the host composites only its two halves).
    let bands: [UIImage?]
    /// A transform edit's bands only: the edit, and the map each run's ink was shown through
    /// at the mint (`CanvasManager.liveTransformMaps`) — what each moving band's transform is
    /// measured from.
    let edit: LiveTransformEdit?
    let mintMaps: [PoseMap]

    var below: UIImage? { bands.first ?? nil }
    var above: UIImage? { bands.count > 1 ? bands[bands.count - 1] : nil }

    /// Whether these are a transform edit's bands of `frame` — what keeps them up after the finger has
    /// lifted (`SandwichPresentation.Held.bandsOfThisFrame`).
    func holdsBands(of frame: Int) -> Bool {
        if case .aroundRuns = cut { return self.frame == frame }
        return false
    }
}

/// **A host's third of the live pair** — what the host of each layer the pair is cut around
/// shows as its own picture at the pair's key, produced on `sandwichQueue` beside the two
/// halves and handed over with them (TODO 145).
///
/// **Why with the halves, and not by the pass that un-blanks the host.** A blanked host keeps
/// nothing current: `updateInterpolationPreviews` skips it, which is TODO (53)'s whole fix,
/// and `refreshDisplay` declines a rasterize nobody can see. So what it holds is the picture
/// from the last time it drew itself, any number of edits ago — and the edges that un-blank
/// it are not SwiftUI passes: `onStrokeBegan` latches a stroke and applies it on the spot,
/// and a rebuild or a bake landing reconciles from its own callback. A host refreshed only
/// by a later pass comes back on screen showing that old picture until the pass arrives,
/// which is the owner's *"The first stroke briefly appears"*: draw, undo, draw again, and
/// the undone stroke is under the pen for the length of the second one. Minted here, the
/// host's picture is never older than the halves either side of it, blanked or not.
enum LiveActivePicture {
    /// A picture in place of the cel's own ink — a pose or an in-between,
    /// `LiveCelPreview.derived`. `covering` is the canvas and version of the cel's own ink it
    /// already contains (`inkCoverage(of:)`).
    case derived(layerID: UUID, content: DerivedCelContent,
                 covering: (canvas: VectorCanvas, version: Int)?)
    /// The cel's own committed render, for a blanked host, which is not keeping it current.
    /// Rendered into the canvas's own memo — the one `refreshDisplay` reads — so the edge that
    /// un-blanks the host installs it synchronously instead of showing what it had.
    case committed(VectorCanvas, version: Int)

    /// The picture, on `sandwichQueue`. A committed render lands in the canvas's memo, so
    /// there is nothing to hand over.
    func render() -> UIImage? {
        // For a posed layer this *is* the pen-up render, so it takes the pen-up render's seam
        // — zero on every ordinary launch; see `UITestSeeds.slowVectorRenderDelay`.
        if UITestSeeds.slowVectorRenderDelay > 0 {
            Thread.sleep(forTimeInterval: UITestSeeds.slowVectorRenderDelay)
        }
        switch self {
        case .derived(_, let content, _):
            return content.render(.full)
        case .committed(let canvas, let version):
            _ = canvas.render(quality: .full, ifStillAtVersion: version)
            return nil
        }
    }
}

/// **One rebuild of the live picture, minted on the main actor and rendered off it** — everything the
/// rebuild needs, frozen at one moment from the model: the recipe (pure over the values it froze, so
/// an edit the artist makes while it runs reaches the live tiers and not this), the cut, the maps a
/// transform edit's bands were shown through, and each host's third of the pair.
struct LivePictureMint {
    let key: SandwichKey
    let frame: Int
    let recipe: SandwichRecipe
    let cut: LivePairCut
    /// A transform edit's bands only (see `LivePicture.edit`).
    let edit: LiveTransformEdit?
    let mintMaps: [PoseMap]
    let active: [LiveActivePicture]

    /// What `render` produced, for the main actor to adopt or discard.
    struct Rendered {
        /// All or none: a half-updated pair would put a `below` from this frame under an `above` from
        /// the last one. Nil only for a degenerate canvas.
        let bands: [CGImage?]?
        /// One per `active`, in order.
        let activeImages: [UIImage?]
    }

    /// The whole of the rebuild's pixel work — call it off the main thread. Since RENDER.md stage 2
    /// that includes resolving the recipe's pixels, not only compositing them.
    func render() -> Rendered {
        // **`full` is deliberately not composited here.** It is the same product as the baked frame,
        // and §2.15 allows exactly one producer of it; that producer is `FrameBaker`, which chunks the
        // walk under a memory ceiling (§3.4) and writes the result where play and export can read it.
        // `SandwichRecipe.resolve()` still mints it because the *cut* is defined against it — the
        // bands are correct precisely when they recompose to `full` — and that invariant is what
        // `SandwichLogicTests` pins. Nothing on the canvas resolves it.
        //
        // **`compositeHalves`/`compositeBands` rather than `Compositor.composite`, and that is the
        // whole of RENDER.md §2.12 on this path.** Each band goes through `StripedCompositor` and
        // `ChunkedCompositor` — the same two cuts the bake takes — so a document whose textures do not
        // fit the device is composited in horizontal bands at the size the knob asked for, rather than
        // refused by the GPU and re-rendered whole on the CPU reference for the duration of every
        // stroke. A document that fits takes the identical path it took before: one composite per
        // band, unwindowed, unchunked.
        let bands: [CGImage?]? = PlaybackTrace.span(.sandwichComposite) {
            if case .aroundRuns = cut { return recipe.compositeBands() }
            return recipe.compositeHalves().map { [$0.below, nil, $0.above] }
        }
        // **The third picture of the pair, on the same queue and for the same key** — see
        // `LiveActivePicture`. After the halves, so a pair is never waiting on a half.
        return Rendered(bands: bands, activeImages: active.map { $0.render() })
    }

    /// The live picture these bands make, wrapped as `UIImage` once (see `LivePicture`).
    func picture(of bands: [CGImage?]) -> LivePicture {
        LivePicture(key: key, cut: cut, frame: frame,
                    bands: bands.map { $0.map { UIImage(cgImage: $0, scale: 1, orientation: .up) } },
                    edit: edit, mintMaps: mintMaps)
    }
}
