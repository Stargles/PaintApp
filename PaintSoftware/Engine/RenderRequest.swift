import UIKit
import SwiftUI

// MARK: - The compositor's input
//
// Everything the compositor needs to produce one frame, captured as immutable values. See
// LAYER_COMPOSITING.md §9.1 point 3, which is the reason this type exists at all:
//
//     "A pure, snapshot-driven entry point: composite(RenderRequest) -> Texture, where the request
//      carries an immutable tree snapshot, the frame, the canvas size, and a quality. No @Published
//      reads, no UIKit view access, no live RasterLayerTexture/VectorCanvas reads."
//
// The temptation is to hand the compositor `[Layer]` and let it pull pixels as it walks — which is
// what `CanvasManager+Fill.swift`'s `compositeReferenceRGBA` does, capturing `(layer, cel)` tuples
// and calling `cel.raster.renderToUIImage()` from `fillQueue`. That works only because
// `RasterLayerTexture` and `VectorCanvas` each hold an `NSLock`, so it is thread-*safe* without
// being a snapshot: the bytes it reads are whatever the user had drawn by the time the lock was
// taken, which for a boundary reference is fine and for a rendered frame is a torn image. §9.1 is
// explicit that the compositor does not get to make that trade, and `ProjectStore.SaveSnapshot`
// (ProjectStore.swift:126) is the pattern that already got this right in this codebase — resolve on
// main, hand the other side values it owns outright.
//
// Doing it this way costs one main-thread render per visible leaf per request, and those renders are
// memoized by `version` on both texture types, so for a stack nobody has drawn on since the last
// request it is a cache read apiece. That is the price of §9.2's background renderer being a thread
// rather than a rewrite.

/// One leaf's pixels for one frame: already composited down to a single image, and owned outright.
///
/// The flattening (baked → live strokes → vector → the live fill preview on top) is
/// `PixelOps.rasterize(cel:)`'s job and stays there — it sits *below* the compositor (§2) and has
/// ~10 other callers. What this type adds
/// is the ownership guarantee: by the time a `RenderRequest` exists, every leaf is a `CGImage` that
/// no live object can mutate.
struct LayerRenderSource {

    /// Canvas-sized, scale 1 — the invariant everything in `PixelOps` already renders at and
    /// `opaqueContentBounds` already documents. `CGImage` rather than `UIImage` because the two
    /// consumers that matter both want it: Metal uploads from a `CGImage`, and a byte-identical
    /// comparison has no business guessing at a `UIImage`'s scale or orientation.
    let image: CGImage

    // **There is deliberately no `contentVersion` here, and the reason is a measurement.**
    //
    // §9.1 point 1 asks for propagating content versions so cached composites can key on them, and
    // this type first carried one as `ObjectIdentifier(image)` — safe against ABA, because whoever
    // cached it retained the image. It was also useless: `PixelOps.rasterize` builds a fresh
    // `UIImage` on every call, so `makeRenderRequest` mints new `CGImage`s for every leaf on every
    // request and an identity key cannot hit, ever. `MetalCompositor`'s upload cache was measured at
    // a zero hit rate and removed.
    //
    // A key that *would* hit has to come from the model rather than from the rendered result — the
    // cel's ID with `RasterLayerTexture.version`, `VectorCanvas.version`, and the identities of
    // `fillImage`/`bakedImage`, plus the request's quality, since `.preview` and `.full` are
    // different pixels. That is real work with an ABA hazard to handle, and it belongs with the cache
    // that needs it. §5.2's sandwich is that cache, and it caches *composites* of everything above
    // and below the active layer rather than one texture per layer — which is both the thing §5.3
    // asks for and a far better ratio than caching leaves.
    //
    // Phase 6 is the second cache to need that key (`MaskResolver`), so the request carries it as
    // `contentVersions` — beside the pixels rather than inside this type, because it is indexed the
    // same way and a mask keys on the versions of a *set* of layers rather than of one.
}

extension LayerRenderSource {

    /// One flat colour across the whole canvas — §4.5's value layer, resolved into a source the
    /// compositor cannot tell apart from a layer somebody painted flat.
    ///
    /// **Built from bytes rather than drawn through a `UIGraphicsImageRenderer`, so the colour *is*
    /// the bytes.** Both backends normalise a source through a device-RGB premultiplied context on the
    /// way in — `CoreGraphicsCompositor.premultipliedBytes` and `MetalCompositor.upload`, which is the
    /// pair whose agreeing on this conversion is half of why the backends can be compared byte for
    /// byte at all — so a buffer already in exactly that layout passes through both unchanged, and the
    /// two agree by construction rather than to within whatever a renderer's colour space and
    /// preferred range happen to round to.
    ///
    /// Premultiplied, and `.toNearestOrEven` for the same reason every other byte path in this engine
    /// uses it: it is the rule Metal's float→unorm8 conversion follows, so a fill below full alpha
    /// lands on the byte the compositor would have produced rather than one step off it.
    ///
    /// Returns nil only for a degenerate canvas size, which is the answer the guard in
    /// `makeRenderRequest` already gives for the same input.
    static func solid(_ color: PaletteColor, canvasSize: CGSize) -> CGImage? {
        let width = Int(canvasSize.width.rounded()), height = Int(canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        let c = color.color.rgbaComponents
        func byte(_ value: Double) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded(.toNearestOrEven))
        }
        let texel = (r: byte(c.r * c.a), g: byte(c.g * c.a), b: byte(c.b * c.a), a: byte(c.a))

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            bytes[offset] = texel.r
            bytes[offset + 1] = texel.g
            bytes[offset + 2] = texel.b
            bytes[offset + 3] = texel.a
        }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: width, height: height)
    }
}

/// One layer's pixels at one frame, **by model identity rather than by rendered result** — the key
/// every cache downstream of a snapshot is allowed to use.
///
/// Deliberately the same identity `PixelOps.RasterizeKey` is built from, because it is the same
/// question: that memo is what makes taking a snapshot cheap, and a second key that moved when it did
/// not would re-render for nothing. The two `UIImage` tiers are compared by object identity because
/// that is how they change — a fill or a bake replaces them wholesale rather than drawing into them.
///
/// **Identity *and* version, for both tiers, and the identity is the load-bearing half.** A version
/// alone is monotonic only within one object's lifetime, while a cel id outlives any number of them:
/// reopening a project rebuilds every `RasterLayerTexture` with its counter back at 0 under the same
/// cel id, so a version-only key can match an entry cached before the last edit and serve pre-edit
/// pixels. Undo can swap in a texture object the same way. This is the mistake §9.1's original
/// `contentVersion` made from the other end — keying on the rendered `CGImage` that
/// `PixelOps.rasterize` mints fresh every call, measured at a zero hit rate and deleted in phase 2.
///
/// Lifted out of `CanvasView.Coordinator` in phase 6, where it was `SandwichKey`'s private business
/// until `MaskResolver` needed exactly the same answer. Two spellings of it would be two things to
/// keep right.
///
/// **`valueFill` and `effect` are the two components that do not come from a cel, and §4.5/§4.4 are
/// why.** A value layer's pixels are not in its cel — in flat-colour mode the *colour* is its content
/// and in effect mode the *grade* is — so a document whose only change is one of those would leave
/// every component above unmoved, and the caches keyed on this would go on serving the old picture: a
/// mask reading that layer as a source would resolve to a stale coverage. Nil for every other kind, so
/// no existing key moved when either field arrived.
///
/// **`effect` is here even though it is elided from `sources`, and that pairing is the whole point.**
/// `renderSources` renders no pixels for a grading layer (it has none) but still records a version for
/// it, because "what does this leaf contribute" and "what does this leaf draw" stopped being the same
/// question when §4.4's wrapper became a mode of an ordinary layer. See that function.
///
/// **This does not make it the live canvas's invalidation mechanism, and it was never needed as one.**
/// The tempting reading of the phase-9 gap is that an effect slider would fail to repaint the canvas
/// because the grade is not in a cache key — but `CanvasView.SandwichKey` carries the whole derived
/// `[RenderNode]`, `RenderNode` is `Equatable`, and `RenderNode.effect` holds the grade verbatim for
/// both of §4.4's wrappers. So the sandwich already moves on a grade change, from the tree half of its
/// key, and it moves for a *folder's* grade too — which nothing indexed by layer could ever cover.
/// This field is for the cache that has no tree in its key: `MaskResolver`'s.
///
/// **Hashed by hand, and only to skip `effect`.** `Effect` is `Equatable` but not `Hashable`, and
/// making it so means conforming it plus its thirteen payload structs, `CurvePoint`, `GradientStop`
/// and `CodableColor` — seventeen declarations in a file this change has no other business in — to buy
/// nothing but bucket spread. Hashing is allowed to collide; **equality** is what decides a cache hit,
/// and equality is synthesized and does include `effect`. Two versions differing only in their grade
/// therefore land in one bucket and are then told apart correctly, which is the contract.
struct LayerContentVersion: Hashable {
    let celID: UUID
    let raster: ObjectIdentifier
    let rasterVersion: Int
    let vector: ObjectIdentifier?
    let vectorVersion: Int
    let fillImage: ObjectIdentifier?
    let bakedImage: ObjectIdentifier?
    let valueFill: ValueFill?
    let effect: Effect?

    init(cel: Cel, valueFill: ValueFill? = nil, effect: Effect? = nil) {
        celID = cel.id
        self.valueFill = valueFill
        self.effect = effect
        raster = ObjectIdentifier(cel.raster)
        rasterVersion = cel.raster.version
        vector = cel.vector.map(ObjectIdentifier.init)
        // -1 rather than 0 for "no vector tier at all", so acquiring an empty one is a change.
        vectorVersion = cel.vector?.version ?? -1
        fillImage = cel.fillImage.map(ObjectIdentifier.init)
        bakedImage = cel.bakedImage.map(ObjectIdentifier.init)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(celID)
        hasher.combine(raster)
        hasher.combine(rasterVersion)
        hasher.combine(vector)
        hasher.combine(vectorVersion)
        hasher.combine(fillImage)
        hasher.combine(bakedImage)
        hasher.combine(valueFill)
    }
}

/// How large the **live canvas's** composites are rendered, as a fraction of the canvas.
///
/// **A different axis from `RenderQuality`, and the two are deliberately not merged.** Quality is
/// about how a *stroke* is put down — `.preview` stamps one `CGPath` where `.full` stamps hundreds of
/// dabs — and it changes what a layer's own pixels look like at full size. This changes how many
/// pixels there are. An artist choosing between them is choosing between "slightly different mark"
/// and "same picture, softer", which are not the same trade and should not share a control.
///
/// **It reaches only `makeSandwichRequests`, and that containment is the whole safety argument.**
/// Everything else that composites goes through `makeRenderRequest` and is untouched: the project
/// thumbnail, the saved package, `MaskResolver`'s source stacks. So this setting cannot degrade
/// anything that is written to disk or looked at later — the only thing it can make smaller is the
/// image on screen right now, which is regenerated from scratch on the next rebuild.
///
/// **And it only bites on documents that engage the compositor at all** (`isSandwichEngaged` →
/// `needsCompositorOnCanvas`). A stack with no blend modes, masks, effects or nodes stays on Core
/// Animation's row of layer hosts at native resolution and this setting does nothing to it. That is
/// the right shape for a performance knob: it is inert exactly where there was no problem, and it
/// applies exactly to the documents that made the artist reach for it.
enum RenderResolution: String, CaseIterable, Identifiable {
    case full
    case threeQuarter
    case half

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .full:         return 1
        case .threeQuarter: return 0.75
        case .half:         return 0.5
        }
    }

    /// What the artist reads. Percentages rather than names like "Draft", because the number is the
    /// thing they can reason about — half resolution is visibly half, and a word would have to be
    /// learned.
    var title: String {
        switch self {
        case .full:         return "Full"
        case .threeQuarter: return "75%"
        case .half:         return "50%"
        }
    }

    /// The canvas size a composite at this resolution is rendered into.
    ///
    /// **Rounded to whole pixels here rather than left to the backends**, because they do not all
    /// round in the same place: `Compositor` takes `Int(width.rounded())` while `PixelOps.rasterize`
    /// hands the fractional size to a `UIGraphicsImageRenderer`. An odd canvas at 75% would then
    /// produce a source one pixel wider than the composite reading it, which on the GPU is a
    /// full-canvas dispatch over a texture of the wrong size — a garbage frame, not a soft one. One
    /// rounding, upstream of both, removes the question.
    ///
    /// `max(1, …)` because a degenerate canvas must stay degenerate in the same direction the rest of
    /// the pipeline already guards for, rather than becoming a zero-sized texture allocation.
    func renderSize(for canvasSize: CGSize) -> CGSize {
        guard self != .full else { return canvasSize }
        return CGSize(width: max(1, (canvasSize.width * scale).rounded()),
                      height: max(1, (canvasSize.height * scale).rounded()))
    }
}

/// The canvas backdrop, when the request wants one drawn under the stack.
///
/// Optional because the two consumers disagree and both are right: the **project thumbnail**
/// composites the stack alone onto transparency, while everything the artist is actually looking at
/// wants the paper. That difference has to be expressible rather than assumed, which is why this is a
/// request-level choice and not a property the compositor reads for itself.
/// Visibility is carried by the request's `background` being nil, not by a flag in here — this type
/// exists only when there is something to draw.
///
/// The doc here used to say the live canvas was the consumer that did *not* want one, because it
/// painted its own `paperView` behind the whole stack. That is what BUGS.md's *"Every effect and
/// blend mode is masked to the layer's own ink"* turned out to be: a view behind the composite is a
/// thing no compositor pass can read, so an adjustment layer graded a transparent sheet.
struct RenderBackground: Equatable {
    let color: UIColor

    /// **Which pixels of this request's own buffer the paper covers** — `canvasSize` inset by
    /// `canvasPadding` on every side, already scaled into this request's `canvasSize` and snapped to
    /// whole pixels, so both backends fill exactly the same integers and no rounding can separate
    /// them.
    ///
    /// **The decision this field records (EFFECT_BACKDROP.md §6 step 3's open question): the paper is
    /// the artwork rect, and the padding margin is not paper.** `CanvasManager.canvasSize` includes
    /// `canvasPadding`, so a fill across the whole buffer — which is what shipped, unnoticed, because
    /// the eyedropper was the only caller — paints canvas colour over a margin the artist is being
    /// shown in light grey. That was invisible while nothing composited a background onto the screen
    /// and stops being invisible the moment the live canvas does: the same document's margin would
    /// read grey with no effect layer in it and paper-coloured with one, because only the second
    /// engages the sandwich. Insetting keeps the margin exactly what it is today in both cases, and
    /// leaves `paddingBackdrop`'s grey showing through a composite that is still transparent there.
    ///
    /// The margin is also not part of the picture anywhere else: an exported or thumbnailed composite
    /// leaves it transparent, and the grey is a live-canvas affordance drawn by a view. Filling it
    /// would have made the paper mean one thing on screen and another in the file.
    ///
    /// **Symmetric on all four sides, which is what keeps it out of the flip.** CoreGraphics fills in
    /// UIKit's y-down space and Metal writes in texture space; a rect inset equally everywhere is the
    /// same rect in both, so this field cannot become the kind of parity bug an asymmetric one would.
    let rect: CGRect
}

/// One frame's worth of compositor input.
struct RenderRequest {

    /// The stack as `CanvasManager.renderTree` derived it — bottom-to-top, folders as 1-input nodes.
    /// A value type all the way down, so it needs no defensive copy.
    let tree: [RenderNode]

    /// Resolved pixels, **indexed by `layers` index** so a `.leaf(layerIndex:)` is a direct subscript.
    /// Parallel to `layers` rather than a dictionary because it is dense and the tree's leaves are
    /// exactly its indices — a dictionary would buy nothing and cost a hash per leaf.
    ///
    /// `nil` means "this leaf contributes nothing at this frame", which covers both a layer with no
    /// cel covering `frame` and a layer that is hidden. Rendering a hidden layer's pixels would be
    /// work nothing reads.
    ///
    /// **Phase 6 made that elision narrower, exactly as this note predicted.** §6.6 is that a mask
    /// ignores its source's visibility — a hidden layer still masks — so `renderSources` now
    /// snapshots a hidden layer that is somebody's mask source. The nil case is unchanged and still
    /// means "contributes nothing at this frame".
    let sources: [LayerRenderSource?]

    /// Parallel to `sources`: what each leaf *is*, by model identity, for the caches downstream of
    /// this request that key on content rather than on the image object.
    ///
    /// Nil where the leaf contributes nothing at this frame — no block covering it, or hidden and not
    /// read for its alpha. **Not** nil merely because `sources` is, which is what this used to say:
    /// a grading leaf (§4.4) holds no pixels and still has content, so it carries a version while its
    /// source stays nil. See `renderSources`, which argues the split.
    let contentVersions: [LayerContentVersion?]

    /// The stack each mask source resolves to (§6.2), keyed by source.
    ///
    /// **Derived from the whole document rather than from `tree`, and that is the point.** A
    /// sandwich half is a pruned tree, so a masked layer in the `below` half can easily be clipped by
    /// a source that lives in `above` — resolving masks out of `tree` would silently drop it. All
    /// three sandwich requests therefore share one of these, built once from the full tree.
    ///
    /// Every node in these stacks has its visibility forced on, which is §6.6's "a hidden source
    /// still contributes its alpha" expressed where the compositor cannot forget it.
    let maskStacks: [MaskSource: [RenderNode]]

    let frame: Int
    let canvasSize: CGSize

    /// Nil when the stack composites onto transparency — see `RenderBackground`.
    let background: RenderBackground?

    /// `.preview` lets vector leaves resolve from `VectorCanvas`'s cheaper cache, the same knob the
    /// interpolation slider already turns. Reused rather than redefined: §9.1 asks the request to
    /// carry "a quality" and the app already has exactly one notion of what that means.
    let quality: RenderQuality

    /// The canvas size a composite should use to fill a `bound`-sized box, aspect preserved and
    /// **never larger than the canvas itself**.
    ///
    /// This is the rule behind `makeRenderRequest`'s `renderSize` hint, and it takes a bounding box
    /// rather than an exact size on purpose: the caller that wants a small composite knows the box it
    /// is filling (a 320×320 gallery tile) and has no business also computing which of the two
    /// dimensions binds. Getting that arithmetic wrong is silent — a request whose `canvasSize` has
    /// the wrong aspect composites a stretched picture that still looks like a picture — so it is
    /// written once, here, and it is deliberately the same `min` of the two ratios that
    /// `ThumbnailRenderer.render` uses to size the tile. The thumbnail's composite and its downscale
    /// therefore agree by construction rather than by two authors happening to match.
    ///
    /// **Clamped at 1× because a hint may only ask for less.** Compositing above native invents no
    /// detail and costs more than the native render it replaces, so a caller passing a box larger
    /// than the canvas gets the canvas.
    ///
    /// Rounding to whole pixels happens here for `RenderResolution.renderSize`'s reason, which
    /// applies identically: the backends round in different places, so an odd canvas scaled anywhere
    /// but upstream of both yields a source a pixel wider than the composite reading it.
    static func renderSize(fitting canvasSize: CGSize, within bound: CGSize) -> CGSize {
        guard canvasSize.width > 0, canvasSize.height > 0,
              bound.width > 0, bound.height > 0 else { return canvasSize }
        let scale = min(bound.width / canvasSize.width, bound.height / canvasSize.height, 1)
        guard scale < 1 else { return canvasSize }
        return CGSize(width: max(1, (canvasSize.width * scale).rounded()),
                      height: max(1, (canvasSize.height * scale).rounded()))
    }
}

/// The three requests §5.2's sandwich is assembled from, over one snapshot.
///
/// **`full` is not a spare.** The settled scope for phase 5b is that at rest the canvas shows one
/// image — `composite(full)`, exact for every mode and every nesting, with every layer host hidden —
/// and that the two halves appear only for the duration of a dab. So `full` is the picture the artist
/// looks at almost all of the time, and `below`/`above` are the ones that have to be *fast*, not the
/// ones that have to be right.
struct SandwichRequests {

    /// The whole tree, exactly as `makeRenderRequest` would have built it.
    let full: RenderRequest

    /// Everything strictly below the active layer in evaluation order.
    let below: RenderRequest

    /// Everything strictly above it. Drawn source-over onto the live stroke, which is why a blend
    /// mode up here degrades to normal mid-stroke: a texture composited onto transparency has no
    /// backdrop left to blend against. Accepted for this phase, and it snaps correct on lift because
    /// lift is when the canvas goes back to `full`.
    let above: RenderRequest
}

/// What `SandwichRequests.full` depends on — which is everything `CanvasView.SandwichKey` carries
/// **except** `activeLayerIndex`.
///
/// **The claim this type makes, and it is checkable by reading `makeSandwichRequests`.** All three
/// requests are built over one snapshot; `activeLayerIndex` is used in exactly one place, the
/// `tree.split(atLeaf:)` that produces `below` and `above`. `full` is `request(tree)` — the whole
/// tree, uncut. So switching the active layer changes *where the tree is cut* and nothing about the
/// picture `full` composites, and a rebuild triggered by a layer tap recomposites, at native canvas
/// size, an image byte-identical to the one already on screen.
///
/// `SandwichKey`'s own doc comment named this fix and declined it, in these words: "Worth the wasted
/// composite rather than a second key and a second cache to keep them apart." What changed is the
/// accounting rather than the argument — the composite it calls wasted is roughly 21 ms of a 54.8 ms
/// rebuild on a six-layer document at the owner's canvas, and a layer tap is not a rare gesture. The
/// second cache turns out to cost nothing extra either: the reused image is the one `sandwichImages`
/// is already retaining, so this is a key beside it and not a second copy of the pixels.
///
/// Lives here rather than inside the coordinator so it can be tested as the value type it is: the
/// property the reuse rests on — that this key moves for every input except the active layer — is
/// exactly what a headless test can pin.
struct SandwichFullKey: Equatable {
    let tree: [RenderNode]
    let frame: Int
    /// Parallel to `layers`; nil where a layer has no cel at this frame.
    let contents: [LayerContentVersion?]
    let renderResolution: RenderResolution

    /// **The paper is an input to the picture now, so it is an input to the key.** Before
    /// EFFECT_BACKDROP.md §6 step 3 the composite did not contain the canvas colour at all — it was a
    /// `UIView` behind the images — so recolouring the canvas moved nothing here and correctly needed
    /// no rebuild. It is inside `full` and `below` now, and a key that does not carry it would leave
    /// the artist looking at the old colour until something unrelated happened to move the key. Same
    /// failure `renderResolution` is in `SandwichKey` for, and stated the same way: a control that
    /// visibly does nothing when you use it.
    ///
    /// Two fields rather than the resolved `RenderBackground`, because these are the model's own and
    /// the resolution through `PixelOps.uiColor` is one more thing that could make two equal states
    /// compare unequal.
    let canvasBackgroundColor: Color
    /// Invisible is not the same key as white: it is the difference between a graded backdrop and a
    /// transparent one, which is the whole subject of this change.
    let isCanvasBackgroundVisible: Bool

    init(tree: [RenderNode], frame: Int, contents: [LayerContentVersion?],
         renderResolution: RenderResolution,
         canvasBackgroundColor: Color, isCanvasBackgroundVisible: Bool) {
        self.tree = tree
        self.frame = frame
        self.contents = contents
        self.renderResolution = renderResolution
        self.canvasBackgroundColor = canvasBackgroundColor
        self.isCanvasBackgroundVisible = isCanvasBackgroundVisible
    }
}

// MARK: - Building one

extension CanvasManager {

    /// Captures the current stack at `frame` as a `RenderRequest`.
    ///
    /// `@MainActor` for the same reason `ProjectStore.SaveSnapshot.init` is (ProjectStore.swift:185):
    /// this is the half that reads published state and renders, and it is deliberately the *only*
    /// half that may. Everything downstream of the value it returns is pure.
    /// `fittingWithin` is an optional **bounding box for the composite**, and nil — the default and
    /// every caller but one — means "native, exactly as before".
    ///
    /// **Why the hint exists.** The project thumbnail composited the entire canvas to make a 320×320
    /// gallery tile: 2,097,152 pixels rendered to fill 51,200 at the owner's 2048×1024, and 16.8M at
    /// 4096². That is main-actor work inside every save, and until the scene-phase gate landed it was
    /// three of them per app switch. `makeSandwichRequests` has had the machinery to render smaller
    /// since the live preview grew a resolution setting; this is that pattern at a second call site,
    /// and nothing more.
    ///
    /// **It is a bounding box rather than a size, and a hint rather than an instruction.**
    /// `RenderRequest.renderSize(fitting:within:)` fits the canvas's aspect inside it and refuses to
    /// go above native; `CompositorBudget.affordableSize` then caps what the device can hold, in that
    /// order, for `makeSandwichRequests`' reason — a preference may ask for less than the device
    /// allows and never for more. The cap is inert at any thumbnail-sized box and is applied anyway,
    /// so a future caller asking for something large is bounded by the same rule the live canvas is.
    ///
    /// **Nil skips all of it rather than passing the canvas through the same arithmetic**, so the
    /// eyedropper, the live-mask resolve and every parity test composite at native size down the byte
    /// — an identity that `affordableSize` does not promise on a 4096² document with a deep stack.
    @MainActor
    func makeRenderRequest(atFrame frame: Int,
                           quality: RenderQuality = .full,
                           includeBackground: Bool,
                           fittingWithin bound: CGSize? = nil) -> RenderRequest? {
        guard let canvasSize, canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let tree = renderTree
        let renderSize: CGSize
        if let bound {
            let wanted = RenderRequest.renderSize(fitting: canvasSize, within: bound)
            let textures = tree.peakCompositeTextures + min(tree.uploadableLeafCount, 4)
            renderSize = CompositorBudget.affordableSize(for: wanted, textures: textures)
        } else {
            renderSize = canvasSize
        }

        let maskStacks = maskSourceStacks(of: tree)
        let snapshot = renderSources(atFrame: frame, canvasSize: renderSize, quality: quality,
                                     alsoIncluding: maskedLayerIndices(in: maskStacks))
        return RenderRequest(
            tree: tree,
            sources: snapshot.sources,
            contentVersions: snapshot.versions,
            maskStacks: maskStacks,
            frame: frame,
            canvasSize: renderSize,
            background: includeBackground ? canvasBackground(renderedInto: renderSize) : nil,
            quality: quality
        )
    }

    /// The paper as a request carries it, or nil when the artist has turned it off.
    ///
    /// One builder for every caller, which is the point: `makeRenderRequest` and
    /// `makeSandwichRequests` both need it, and the padding arithmetic is exactly the kind of thing
    /// that is written twice and then drifts. `renderedInto` is the request's own buffer size, which
    /// may be smaller than the canvas (`RenderResolution`, `CompositorBudget`, the thumbnail's
    /// bounding box), so the inset is scaled with it rather than applied in canvas pixels.
    ///
    /// **Rounded here, once, so the two backends receive integers rather than an arithmetic
    /// problem.** `CompositorParityLogicTests` is this subsystem's gate and a fill whose edge each
    /// backend rounded for itself is precisely the shape of failure it exists to catch.
    @MainActor
    func canvasBackground(renderedInto renderSize: CGSize) -> RenderBackground? {
        guard isCanvasBackgroundVisible, let canvasSize,
              canvasSize.width > 0, canvasSize.height > 0,
              renderSize.width > 0, renderSize.height > 0 else { return nil }
        let insetX = (canvasPadding * renderSize.width / canvasSize.width).rounded()
        let insetY = (canvasPadding * renderSize.height / canvasSize.height).rounded()
        // `max(0, …)` for the degenerate document the padding slider can reach on a small canvas:
        // an inset wider than the canvas means there is no artwork rect left, and an empty rect is
        // the honest answer to that rather than a negative one both backends would read differently.
        let rect = CGRect(x: insetX, y: insetY,
                          width: max(0, renderSize.width - 2 * insetX),
                          height: max(0, renderSize.height - 2 * insetY))
        return RenderBackground(color: PixelOps.uiColor(from: canvasBackgroundColor), rect: rect)
    }

    /// The three requests §5.2's sandwich needs, or nil when there is no canvas to composite into or
    /// `activeLayerIndex` is not a leaf of the tree (`Array<RenderNode>.split(atLeaf:)`).
    ///
    /// **All three share one `sources` array, and that sharing is the reason this is one call rather
    /// than three.** `sources` is indexed by `layers` index rather than by position in a tree, so the
    /// same array answers all three walks unchanged, and `PixelOps.rasterize` is memoized on cel
    /// version — so the snapshot, which §11 measured at 276 ms against an 84 ms composite and is
    /// therefore the expensive half, is paid once for the three instead of three times.
    ///
    /// **The paper goes into `full` and `below`, and `above` keeps `background: nil`.**
    /// EFFECT_BACKDROP.md §6 step 3, which is the fix for BUGS.md's *"Every effect and blend mode is
    /// masked to the layer's own ink"*: all three used to be nil, because the live canvas painted its
    /// own `paperView` behind the whole stack, and a compositor pass cannot read a view behind
    /// itself. So every adjustment layer graded an accumulator that was transparent wherever the
    /// artist had not painted, every kernel correctly short-circuited on alpha 0, and the effect read
    /// as masked to the ink. The kernels were right and the input was wrong.
    ///
    /// **`above` stays nil, and that clause of the old doc comment is still exactly true**: `above`
    /// is drawn over the live stroke and over everything beneath it, so a background in it would be
    /// an opaque sheet hiding the whole picture. It is the one half of the sandwich that composites
    /// onto transparency by design.
    ///
    /// **`paperView` stops painting while the composite carries the paper**, or a translucent canvas
    /// colour would be applied twice — an opaque one hides that mistake and a translucent one does
    /// not. `CanvasView.updatePaper` owns that half, gated on the composite actually being on screen
    /// rather than on the sandwich merely being engaged (there is a window between the two: see the
    /// "do not blank the hosts until the first composite has landed" trap in `updateSandwich`).
    @MainActor
    func makeSandwichRequests(atFrame frame: Int,
                              activeLayerIndex: Int,
                              quality: RenderQuality = .full) -> SandwichRequests? {
        guard let canvasSize, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let tree = renderTree
        guard let halves = tree.split(atLeaf: activeLayerIndex) else { return nil }

        // **`renderResolution` is applied here and nowhere else**, which is what makes it a live-canvas
        // setting rather than a document one — see the type. One size for the whole request: the
        // sources are rasterized into it, the masks resolve at it, and both backends size their
        // buffers from it, so nothing downstream has to know a scale was applied at all. The view
        // stretches the result back over the canvas (`makeSandwichView`'s `.scaleToFill`).
        //
        // **One size for all three halves, and it is forced rather than chosen.** The tempting design
        // is to render `full` natively and only reduce `below`/`above` — the artist would then see a
        // sharp picture at rest and a soft one only while a stroke is down, which is strictly the
        // nicer behaviour. It is not available here: the three requests share one `sources` array, and
        // that sharing is the reason this is one call instead of three (see this function's note — the
        // snapshot is the expensive half at 276 ms against an 84 ms composite). Two sizes means two
        // snapshots, which costs more than the reduced composites save. So a reduced setting is soft
        // at rest as well as mid-stroke, and making it otherwise is a change to how snapshots are
        // taken rather than a change to this line.
        //
        // **And then capped by what this device can actually hold, which is the other half.** The
        // artist's setting is a preference; `CompositorBudget.affordableSize` is a limit, and the two
        // compose in the only order that is safe — a preference may ask for less than the device
        // allows and never for more. The cap is inert on every canvas that already fits (see the
        // budget type), so this line changes nothing for the documents the sandwich was measured on.
        //
        // **It is applied here rather than left to the engine to refuse, and that is the whole point
        // of doing it on this side.** `CompositorMetalEngine` declines a request it cannot afford,
        // and `Compositor.composite` answers a decline by rendering the whole frame through the
        // CoreGraphics reference — which for the scene that prompted this (4096², bloom and blur) is
        // four passes gathering a blur kernel per pixel over 16.8M pixels in scalar Swift. A correct
        // frame rendered slowly beats no frame, but a *smaller* frame on the GPU beats both, and
        // the artist is already looking at a preview here: the sandwich views stretch this back over
        // the canvas and `updateSandwich` picks linear filtering the moment it is not full size.
        //
        // The count comes from the tree rather than from a constant because it is the tree that
        // decides it: two grading layers cost three more textures than two ordinary ones, and a
        // document with no effects at all pays nothing.
        //
        // **`uploadableLeafCount` is in the count, capped at four, and both halves of that are a
        // judgement.** In it, because a cache that cannot hold one composite's leaves does not
        // "degrade" — it thrashes to a zero hit rate (see `UploadCache`), and at 4096² that is 64 MiB
        // of staging buffer and upload per leaf, three times per rebuild. Buying the walk room by
        // starving the thing that makes the walk fast is not a saving. Capped, because past a few
        // layers no size makes them all fit and shrinking further would trade real sharpness for a
        // cache that was going to thrash anyway; four is where that knee sits on the 3 GB device this
        // was sized against. Nothing here is reached by a document Core Animation can still draw
        // flat — `isSandwichEngaged` means a blend, a mask, an effect or a node is already present.
        //
        // **Applied whichever backend the tree prefers, and that is deliberate rather than an
        // oversight.** The count above is GPU textures, but the CPU reference is not cheap at this
        // size either: six layers at 2048² peaked at 381.3 MB through CoreGraphics on the owner's iPad
        // (`testCompositeCostAndMemoryAtCanvasResolution`), and it is per-layer-linear in time — 32.0
        // ms a composite there, so roughly 128 ms at 4096², times three for a rebuild. Gating the cap
        // on `prefersGPUCompositing` would leave the CPU path uncapped at exactly the canvas size
        // where it is most expensive, to preserve sharpness on the frames least able to afford it.
        let wanted = renderResolution.renderSize(for: canvasSize)
        let textures = tree.peakCompositeTextures + min(tree.uploadableLeafCount, 4)
        let renderSize = CompositorBudget.affordableSize(for: wanted, textures: textures)

        // From the *whole* tree, not from either half — see `RenderRequest.maskStacks`.
        let maskStacks = maskSourceStacks(of: tree)
        let snapshot = renderSources(atFrame: frame, canvasSize: renderSize, quality: quality,
                                     alsoIncluding: maskedLayerIndices(in: maskStacks))
        func request(_ tree: [RenderNode], background: RenderBackground?) -> RenderRequest {
            RenderRequest(tree: tree, sources: snapshot.sources, contentVersions: snapshot.versions,
                          maskStacks: maskStacks, frame: frame, canvasSize: renderSize,
                          background: background, quality: quality)
        }
        let paper = canvasBackground(renderedInto: renderSize)
        return SandwichRequests(full: request(tree, background: paper),
                                below: request(halves.below, background: paper),
                                above: request(halves.above, background: nil))
    }

    /// One resolved image per `layers` index, and its content version, or nil where a layer
    /// contributes nothing at this frame.
    ///
    /// Factored out of `makeRenderRequest` rather than copied into `makeSandwichRequests`, because a
    /// second copy of the elision rule is a second thing to update — which phase 6 proved by
    /// changing it: `alsoIncluding` is §6.6's "a mask ignores its source's visibility", and a hidden
    /// layer that clips something has to be rasterized after all.
    ///
    /// **Two passes as of PERFORMANCE.md item 9(b), and the split is the whole change.** Pass 1 asks
    /// the model which layers contribute and from which cel — `@Published` reads, no pixels. Pass 2
    /// rasterizes the survivors across every core via `PixelOps.parallelMap`, because two different
    /// cels share no mutable state and this was the largest main-thread term on a playback tick:
    /// **78.2 ms** for six layers at 2048×1024, memo-cold, against 22.2 ms for all three composites of
    /// the rebuild put together. It is **~22 ms** now, so the snapshot and the composites are the same
    /// size and neither dominates (both MEASURED 2026-08-20 — item 4b carries the before/after table
    /// and the three unchanged composites that calibrate the two runs against each other).
    ///
    /// **It is still on the main actor, and that is deliberate rather than unfinished.** The snapshot
    /// being synchronous is what makes it *atomic* with respect to the artist's own edits: nothing can
    /// stamp a dab into one of these textures between the first layer being read and the last.
    /// Suspending in the middle would buy a free main thread at the price of a torn frame — some
    /// layers pre-stroke, some post — on the most latency-sensitive path in the app. Spreading the
    /// same work over cores shortens the block without opening that window at all.
    ///
    /// **A value layer stays in pass 1**, where its `resolvedColor(atFrame:)` runs on the main actor.
    /// It is a memset rather than a rasterize, so there is nothing to parallelise, and resolving a
    /// `Color` is the one thing here whose thread-safety is not already established by somebody else's
    /// doc comment.
    @MainActor
    private func renderSources(atFrame frame: Int, canvasSize: CGSize, quality: RenderQuality,
                               alsoIncluding maskSourceLayers: Set<Int> = [])
    -> (sources: [LayerRenderSource?], versions: [LayerContentVersion?]) {
        var sources = [LayerRenderSource?](repeating: nil, count: layers.count)
        var versions = [LayerContentVersion?](repeating: nil, count: layers.count)
        // Layers that need a cel flattened, and which cel. Carries the `Layer` by value: it is a
        // struct, so this is a copy of the metadata and a retain of the texture objects, and pass 2
        // therefore reads nothing off `self`.
        var rasterJobs: [(index: Int, layer: Layer, celIndex: Int)] = []
        for index in layers.indices {
            let layer = layers[index]
            // The visibility check is an elision, not the compositing rule — `RenderNode.isVisible`
            // carries the flag and the compositor is what honours it. Skipping the render here only
            // avoids rasterizing pixels that would then be multiplied by zero, which is precisely
            // not true of a hidden mask source: its alpha is read even though it never draws.
            //
            // **A layer that is grading is elided outright (§4.4, phase 9a)**, and unlike the
            // visibility case there is nothing conditional about it: it holds no pixels at all, so
            // rasterizing its blank cel would mint a canvas-sized transparent image per frame for a
            // leaf the compositor reaches by its `effect` and never by its source. Nor is it an
            // exception to the mask rule above — a grading layer named as a mask source contributes
            // no alpha either way, because it has none to contribute.
            //
            // **Asked as `layerEffect == nil`, not as a kind test, and the kind test is what this
            // replaced.** §4.4's wrapper stopped being `LayerKind.compositing` and became the
            // effect *mode* of a `.value` layer, so "does this layer hold pixels" is no longer a
            // question the kind can answer on its own: the other mode of the same kind resolves to a
            // solid below and must not be elided. Reading the same accessor the tree's leaf
            // derivation reads (`RenderTree.renderNodes`) is what keeps the two in step — the leaf is
            // elided here exactly when the compositor is going to reach it by its grade instead.
            //
            // **The two guards below used to be one, and splitting them is phase 9's correction.**
            // `versions` was documented as "nil wherever `sources` is nil, and for the same reason",
            // which held for as long as a leaf's contribution *was* its pixels. It stopped holding
            // the moment a grading layer became an ordinary leaf: such a leaf contributes a real
            // thing to the composite — its grade — while contributing no pixels at all, so the one
            // guard was answering "does this draw?" for a field that asks "what is this?". Left
            // coupled, a grading leaf carried no version, and `MaskResolver`'s cache — whose key is
            // these versions and, unlike `CanvasView.SandwichKey`, contains no tree — would go on
            // serving the coverage it resolved before the grade changed. That is visible wherever the
            // grade reshapes alpha (outline, blur, bloom, Sobel, sharpen: `reshapesCoverage`) inside a
            // folder somebody is using as a mask source.
            //
            // What stays shared is the pair above it: no block at this frame, or hidden and not
            // wanted for its alpha, means the leaf contributes nothing of *either* sort, and nil for
            // both is exactly right.
            guard layer.isVisible || maskSourceLayers.contains(index),
                  let celIndex = activeCelIndex(inLayer: index, atFrame: frame)
            else { continue }
            versions[index] = LayerContentVersion(cel: layer.cels[celIndex], valueFill: layer.valueFill,
                                                  effect: layer.layerEffect)
            guard layer.layerEffect == nil else { continue }

            // **§4.5's value layer, resolved here, and this line's *placement* is the one
            // architectural decision that feature exists to get right.** This function already takes
            // the frame and already exists to turn "one layer" into "one layer's pixels at one
            // frame", so a value layer becomes an ordinary `LayerRenderSource` and **the compositor
            // never learns that value layers exist** — neither backend has a leaf case for a colour,
            // neither `RenderNode` nor `RenderRequest` carries one, and a fill is indistinguishable
            // downstream from a layer somebody painted flat.
            //
            // The owner wants keyframed values eventually and explicitly does not want them built
            // now. Doing the read here is what makes that a one-function change later: a keyframe
            // phase adds a track inside `ValueFill`, `resolvedColor(atFrame:)` starts reading it, and
            // this call site is already passing the frame. Resolving anywhere further in (in
            // `Compositor.draw`, or by giving `RenderNode` a colour field) puts the constant
            // somewhere the frame is not in scope, which is precisely the seam this buys.
            //
            // A value layer's cel is blank and unrendered — kept, like an effect layer's, so that
            // every cel-lifecycle path in the app goes on working rather than the timeline learning
            // about a layer without cels. It still gates: the `activeCelIndex` guard above is what
            // decides whether this layer contributes at this frame at all, so deleting a value
            // layer's block at frame *n* removes its colour at *n*, which is what every other layer
            // does and what the timeline shows.
            if let fill = layer.valueFill {
                if let image = LayerRenderSource.solid(fill.resolvedColor(atFrame: frame), canvasSize: canvasSize) {
                    sources[index] = LayerRenderSource(image: image)
                }
                continue
            }
            rasterJobs.append((index, layer, celIndex))
        }

        // Pass 2. `parallelMap` returns in index order and runs inline below two jobs, so a one- or
        // two-layer document behaves exactly as it did before this split.
        let images = PixelOps.parallelMap(rasterJobs.count) { job in
            PixelOps.rasterize(cel: rasterJobs[job].layer.cels[rasterJobs[job].celIndex],
                               canvasSize: canvasSize, quality: quality).cgImage
        }
        for (job, image) in zip(rasterJobs, images) {
            guard let image else { continue }
            sources[job.index] = LayerRenderSource(image: image)
        }
        return (sources, versions)
    }

    // MARK: - Mask sources (§6.2)

    /// Every mask source named anywhere in `tree`, resolved to the stack that produces its alpha.
    ///
    /// A `.layer` source becomes a one-node stack and a `.folder` source the folder's whole node, so
    /// the union in `MaskResolver` is a composite of ordinary render nodes rather than a second
    /// notion of what a subtree means. Visibility is forced on throughout (§6.6) — including inside a
    /// folder source, so that a mask shape parked in a hidden group behaves like a mask shape parked
    /// on a hidden layer, and toggling an eye can never silently change where paint may land.
    ///
    /// A source naming something that is not in the tree is simply absent from the result, which the
    /// resolver treats as contributing no alpha. That covers a stale id the same way
    /// `resolvedContainer(ofFolder:)` covers a missing parent: by carrying on.
    func maskSourceStacks(of tree: [RenderNode]) -> [MaskSource: [RenderNode]] {
        var wanted: Set<MaskSource> = []
        collectMaskSources(in: tree, into: &wanted)
        guard !wanted.isEmpty else { return [:] }

        var stacks: [MaskSource: [RenderNode]] = [:]
        for source in wanted {
            guard let node = RenderNode.find(source.id, in: tree) else { continue }
            stacks[source] = [node.ignoringVisibility]
        }
        return stacks
    }

    private func collectMaskSources(in nodes: [RenderNode], into wanted: inout Set<MaskSource>) {
        for node in nodes {
            for mask in node.masks { wanted.formUnion(mask.sources) }
            if case .node(_, let inputs) = node.content {
                for input in inputs { collectMaskSources(in: input, into: &wanted) }
            }
        }
    }

    /// The `layers` indices those stacks read pixels from — what the snapshot has to rasterize even
    /// where the layer is hidden.
    private func maskedLayerIndices(in stacks: [MaskSource: [RenderNode]]) -> Set<Int> {
        Set(stacks.values.flatMap(\.leafLayerIndices))
    }
}
