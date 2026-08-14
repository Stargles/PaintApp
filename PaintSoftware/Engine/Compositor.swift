import UIKit

// MARK: - The compositor
//
// One headless entry point that turns a `RenderRequest` into a frame. LAYER_COMPOSITING.md §1: the
// app has two unrelated compositing implementations that already disagree, and adding masks and
// blends to both guarantees drift — so build one, and delete the other (§5.2, phase 3).
//
// Two backends, one contract. The Core Graphics one is the reference: it is what `composite` falls
// back to when there is no GPU, it is the only one the fast test tier can run (see
// `CompositorBackend`), and it is the byte-for-byte definition of correct that the Metal one is
// measured against. §11's phase 2 gate — "byte-identical to the Core Animation path for all-normal,
// no-mask documents" — is enforced against it.

/// Which implementation `Compositor.composite` uses.
///
/// **Defaults to `.coreGraphics`, and that is still not a placeholder** — though phase 5 narrows the
/// reason. The GPU is what §5.1 wants for per-pixel blend math over 4.2M pixels and that math now
/// exists on both sides; what has not arrived is a consumer that needs it at interactive rates. The
/// one offline consumer is the project thumbnail, where a whole composite is cheaper on the CPU than
/// the upload the GPU pays first (measured: 84 ms against 1189 ms for six 2048² layers,
/// `PerfBaselineTests`, simulator). §5.2's sandwich is the consumer that flips this, because it
/// keeps its textures between frames and stops paying the upload every time.
///
/// **The fast tier can select either, which is new.** The `PaintSoftwareUITests` target opts out of
/// the app's `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so it had no shader of
/// any kind and `device.makeDefaultLibrary()` returned nil there — the reason `MetalFillEngine` has
/// never been exercisable outside a real app process. `Composite.metal` is an explicit member of that
/// target and `CompositorMetalEngine` asks for its library by `Bundle(for:)` rather than
/// `Bundle.main`, so both backends run headlessly and `CompositorParityLogicTests` compares them
/// directly. `Fill.metal` is still not a member, so `MetalFillEngine.shared` remains nil there.
enum CompositorBackend {
    case coreGraphics
    case metal
}

enum Compositor {

    /// The active backend. A `static var` rather than a `UserDefaults`-backed setting because this is
    /// a development seam, not something a user chooses — `CanvasManager.pencilOnlyDrawing` is what a
    /// real persisted preference looks like in this codebase, and this is deliberately not that.
    static var backend: CompositorBackend = .coreGraphics

    /// Composites one frame. Pure: every input is a value the caller owns, so this is safe to call
    /// from any thread — which is the whole point of §9.1 point 3 and what makes §9.2's background
    /// renderer a thread rather than a rewrite.
    ///
    /// Returns nil only for a degenerate canvas size.
    static func composite(_ request: RenderRequest) -> CGImage? {
        switch backend {
        case .coreGraphics:
            return CoreGraphicsCompositor.composite(request)
        case .metal:
            // Falling back rather than failing: a device with no GPU, or the fast test tier with no
            // metallib, should render a correct frame slowly rather than no frame at all. The two
            // backends agree exactly for source-over and to within a channel step for the blend
            // modes (`CompositorParityLogicTests` measures every one), so this is a performance
            // fallback and never a visual one.
            return MetalCompositor.composite(request) ?? CoreGraphicsCompositor.composite(request)
        }
    }
}

// MARK: - Blend modes on the CPU

extension BlendMode {

    /// The `CGBlendMode` that computes this mode, or **nil when CoreGraphics has no equivalent** and
    /// `CoreGraphicsCompositor` has to compute it per pixel itself.
    ///
    /// Eleven of the fourteen Tier 1 modes are CoreGraphics primitives, and that is worth leaning on
    /// rather than hand-rolling for uniformity: `CGBlendMode` implements the PDF imaging model's
    /// separable blend functions, which are the same formulas `Composite.metal` implements from the
    /// W3C spelling of them. So the CPU reference is *Apple's* implementation of the blend, not a
    /// second copy of the shader's — which is what makes the GPU-versus-CPU delta a real measurement
    /// instead of a test of whether one author wrote the same expression twice.
    ///
    /// **The three Tier 1 hand-rolled modes (`add`, `subtract`, `linearLight`) are hand-rolled because
    /// they are absent, not because they are awkward.** CoreGraphics offers `.plusLighter`, which
    /// looks like Add and is not: it is Porter-Duff *plus*, summing premultiplied channels including
    /// alpha, so it agrees with linear dodge only where the backdrop is opaque and the sum does not
    /// clamp, and it inflates alpha everywhere else. Substituting it would be wrong in exactly the
    /// cases a blend mode is interesting.
    ///
    /// **Tier 2 was swept the same way, and only one of its five Apple-backed modes actually keeps the
    /// primitive.** `vividLight`, `pinLight`, `linearBurn`, `divide`, `lighterColor` and `darkerColor`
    /// have no `CGBlendMode` case at all — absent, the `add`/`subtract`/`linearLight` category.
    /// `exclusion`, `hue`, `saturation`, `color` and `luminosity` *do* have Apple cases, but the switch
    /// below only returns one of them: `.exclusion` keeps `.exclusion`, while `.hue`, `.saturation`,
    /// `.color` and `.luminosity` return `nil` unconditionally, so `handRolledTriple` is the live path
    /// for all four, not a fallback.
    ///
    /// That split is a choice, not a measured disagreement. `exclusion`'s delta of 0
    /// (`CompositorParityLogicTests.testEveryBlendModeAgreesBetweenTheBackends`) is a genuine
    /// CoreGraphics-versus-spec data point, the same kind `multiply`'s delta of 1 is. The other four's
    /// reported deltas (hue 1, saturation 0, color 1, luminosity 1) are not: since this backend already
    /// hand-rolls those four, that sweep compares the GPU shader's W3C formulas against this backend's
    /// own W3C formulas — two implementations of the same spec agreeing to a float rounding step, which
    /// says nothing about whether Apple's non-separable blends agree with the spec. That comparison has
    /// never been run. Hand-rolling `hue`/`saturation`/`color`/`luminosity` here is the conservative
    /// choice: it is independently cross-checked (against the GPU shader and against hand-computed
    /// values from a Python transcription of the W3C formulas), where Apple's versions are unmeasured.
    /// Measuring them against `CGBlendMode` directly is a real future experiment, not a foregone
    /// conclusion — if they agree, these four could take the same faster path `exclusion` already does.
    var coreGraphicsBlendMode: CGBlendMode? {
        switch self {
        // `clipToBelow` is source-over plus a mask, and the tree has already turned it into exactly
        // that (`compositedMode`) — so it cannot arrive here. Named rather than left to a `default`
        // so that a genuinely new mode still fails to compile until someone decides what it draws.
        case .normal, .clipToBelow: return .normal
        case .multiply:    return .multiply
        case .screen:      return .screen
        case .overlay:     return .overlay
        case .darken:      return .darken
        case .lighten:     return .lighten
        case .hardLight:   return .hardLight
        case .difference:  return .difference
        case .exclusion:   return .exclusion
        // "CoreGraphics disagrees about these," not "CoreGraphics lacks these" — measured 141/249/16
        // against the spec; see `handRolledChannel` and the measured table in
        // `CompositorParityLogicTests`.
        case .colorDodge, .colorBurn, .softLight: return nil
        // Absent, not awkward: `CGBlendMode` has no case for any of these seven.
        case .add, .subtract, .linearLight: return nil
        case .vividLight, .pinLight, .linearBurn, .divide, .lighterColor, .darkerColor: return nil
        // CoreGraphics *does* have cases for these four — hand-rolled by choice, not by measured
        // disagreement. Apple's non-separable implementations have never been measured against the
        // spec; see `handRolledTriple`'s doc comment for what the sweep below actually compared.
        case .hue, .saturation, .color, .luminosity: return nil
        }
    }

    /// Whether this mode needs the whole RGB triple rather than one channel at a time — §7 Tier 2's
    /// trap. `CoreGraphicsCompositor.drawHandRolled` reads this to decide which of `handRolledChannel`
    /// (called three times, once per channel) or `handRolledTriple` (called once, given all three) is
    /// the right shape of call for a hand-rolled mode. `Composite.metal` needs no such branch — its
    /// `blendChannels` already takes and returns a `float3`, so a non-separable formula fits the exact
    /// same call site a separable one does and the split is CPU-only.
    fileprivate var isNonSeparable: Bool {
        switch self {
        case .hue, .saturation, .color, .luminosity, .lighterColor, .darkerColor: return true
        default: return false
        }
    }

    /// The per-channel blend for every *separable* hand-rolled mode, unpremultiplied on both sides.
    /// Must agree with the matching case of `blendChannels` in `Composite.metal`, and is the only
    /// place in this backend where separable blend arithmetic is written out.
    ///
    /// **Two different reasons a mode lands here, and the second one is a finding.**
    ///
    /// `add`, `subtract`, `linearLight`, and Tier 2's `vividLight`, `pinLight`, `linearBurn` and
    /// `divide` are here because `CGBlendMode` has no case for them.
    ///
    /// `colorDodge`, `colorBurn` and `softLight` are here because Apple's cases *exist and disagree*.
    /// Sweeping all fourteen Tier 1 modes over 4096 (colour, alpha) pairs put every other mode within
    /// one step of the shader and these three at **141, 249 and 16**. That is not a rounding regime;
    /// it is two different formulas. CoreGraphics implements the PDF 1.4 originals, where the
    /// divisions have no zero-backdrop case — so `colorDodge` lifts a black backdrop to white at
    /// `cs == 1` where the modern rule keeps it black, `colorBurn` does the mirror of that at
    /// `cs == 0`, and `softLight` uses a different `D(cb)` curve altogether. W3C Compositing Level 1
    /// (equivalently PDF 2.0) added the guards, and it is what Photoshop and CSP do, which settles
    /// which of the two an artist reaching for Color Dodge means.
    ///
    /// So the shader is the correct one and this backend follows it, rather than the reference being
    /// "whatever Apple ships". Worth stating plainly because §5.1 calls the CoreGraphics path the
    /// byte-for-byte definition of correct: that holds for the *walk* — the order, the buffers, the
    /// alpha — and not for the blend functions themselves, where the spec is the authority and both
    /// backends are implementations of it.
    ///
    /// `vividLight` and `pinLight` route through `colorDodgeChannel`/`colorBurnChannel` and
    /// `min`/`max` rather than restating dodge-and-burn or darken-and-lighten, for the same reason
    /// `Composite.metal`'s versions call `blendColorDodge`/`blendColorBurn`: one definition of each,
    /// so a future fix to Color Dodge cannot fix it in three places and miss a fourth.
    fileprivate func handRolledChannel(backdrop cb: Float, source cs: Float) -> Float {
        switch self {
        case .add:         return min(1, cb + cs)
        case .subtract:    return max(0, cb - cs)
        case .linearLight: return min(1, max(0, cb + 2 * cs - 1))
        case .colorDodge:  return colorDodgeChannel(backdrop: cb, source: cs)
        case .colorBurn:   return colorBurnChannel(backdrop: cb, source: cs)
        case .softLight:   return softLightChannel(backdrop: cb, source: cs)
        // Vivid Light: Color Burn below mid-grey, Color Dodge above it, each fed the doubled,
        // re-centred source — the same split Hard Light makes between Multiply and Screen.
        case .vividLight:
            return cs <= 0.5 ? colorBurnChannel(backdrop: cb, source: 2 * cs)
                              : colorDodgeChannel(backdrop: cb, source: 2 * cs - 1)
        // Pin Light: Darken below mid-grey, Lighten above it, same doubled-source split as above —
        // the "which of two ordinary modes" family Vivid Light belongs to as well.
        case .pinLight:
            return cs <= 0.5 ? min(cb, 2 * cs) : max(cb, 2 * cs - 1)
        // Linear Burn is Linear Dodge's mirror: `cb + cs - 1` where Add is `cb + cs`, clamped the
        // same way at the end the arithmetic can leave the [0, 1] range rather than the start.
        case .linearBurn:  return max(0, cb + cs - 1)
        // Divide mirrors Color Dodge's guard order exactly, with the pole moved from `1 - cs` to
        // `cs` itself: a black backdrop stays black regardless of the source (checked first, so it
        // wins over the next guard even at `cs == 0`), and a near-zero source saturates to white
        // rather than dividing by it.
        case .divide:
            if cb <= 0 { return 0 }
            if cs <= 0 { return 1 }
            return min(1, cb / cs)
        case .exclusion:   return cb + cs - 2 * cb * cs
        default:           return cs
        }
    }

    /// The RGB-triple blend for the non-separable modes (`isNonSeparable`), unpremultiplied on both
    /// sides. Must agree with the matching case of `blendChannels` in `Composite.metal` — which needs
    /// no separate function for these the way this backend does, since a Metal `float3` already
    /// carries all three channels through the one call site both shapes of formula share.
    ///
    /// **All six cases here are live in this backend today.** `lighterColor` and `darkerColor` have no
    /// `CGBlendMode` case, so `draw` always reaches them through this function — the same
    /// "absent, not awkward" reason `add` is hand-rolled. `hue`, `saturation`, `color` and `luminosity`
    /// *do* have `CGBlendMode` cases, but `coreGraphicsBlendMode` returns `nil` for all four regardless
    /// — so `draw` reaches these four cases every time too, not as insurance against a future
    /// regression but as the ordinary production path.
    ///
    /// That is a choice, not a measured disagreement: Apple's non-separable implementations have never
    /// been checked against the W3C spec. The nearest measurement,
    /// `CompositorParityLogicTests.testEveryBlendModeAgreesBetweenTheBackends`, compares the GPU shader
    /// against this CPU backend — and since this backend already hand-rolls these four, that sweep
    /// compares the app's own two implementations of the spec against each other, not against
    /// CoreGraphics. Its reported deltas for them (hue 1, saturation 0, color 1, luminosity 1) are float
    /// rounding between our own two paths and say nothing about Apple's versions (contrast `exclusion`,
    /// which *does* cross `CGBlendMode` and whose delta of 0 is a real CoreGraphics-versus-spec
    /// measurement — see `coreGraphicsBlendMode`'s doc comment). Whether Apple's cases agree with the
    /// spec is a genuine open question and a future experiment, not yet run either direction.
    ///
    /// W3C Compositing and Blending Level 1's non-separable formulas, restated here rather than
    /// summarised: `Lum`/`Sat` read a colour's luminosity and saturation, `ClipColor` pulls an
    /// out-of-gamut colour back into `[0, 1]` along the axis that keeps its `Lum`, `SetLum`/`SetSat`
    /// transplant one colour's luminosity or saturation onto another's channels. Hue keeps the
    /// source's hue and saturation but the backdrop's luminosity; Saturation keeps the backdrop's hue
    /// and luminosity but the source's saturation; Color keeps the source's hue and saturation *and*
    /// the backdrop's luminosity in one step; Luminosity is Color with the two swapped.
    ///
    /// `setSat`'s spec pseudocode sorts the channels into min/mid/max and rewrites each in place; the
    /// version below is the same function stated as one affine remap of the whole triple —
    /// `(c - cMin) * s / (cMax - cMin)` sends `cMin` to 0, `cMax` to `s`, and everything between to the
    /// spec's `Cmid` formula, by construction — which needs no sort and no per-channel branch, on
    /// either backend.
    fileprivate func handRolledTriple(backdrop cb: Triple, source cs: Triple) -> Triple {
        switch self {
        case .hue:          return setLum(setSat(cs, sat(cb)), lum(cb))
        case .saturation:   return setLum(setSat(cb, sat(cs)), lum(cb))
        case .color:        return setLum(cs, lum(cb))
        case .luminosity:   return setLum(cb, lum(cs))
        // Whole-triple luminosity picks whole-triple winner — not a per-channel max/min, which is
        // what `lighten`/`darken` already are and would not need a new case to express.
        case .lighterColor: return lum(cs) >= lum(cb) ? cs : cb
        case .darkerColor:  return lum(cs) <= lum(cb) ? cs : cb
        default:            return cs
        }
    }
}

/// `(r, g, b)`, unpremultiplied and in `[0, 1]` on the way in — the shape `handRolledTriple` and its
/// W3C helpers pass around. A named tuple rather than `SIMD3<Float>`: nothing here is dispatched to
/// the GPU, and elementwise arithmetic written out per component is what the rest of this file
/// already does in `drawHandRolled`'s loop.
private typealias Triple = (r: Float, g: Float, b: Float)

/// Shared by `handRolledChannel`'s `colorDodge` case and its `vividLight` case, so Color Dodge has one
/// definition instead of two that could drift apart. Body unchanged from phase 5a.
private func colorDodgeChannel(backdrop cb: Float, source cs: Float) -> Float {
    if cb <= 0 { return 0 }
    if cs >= 1 { return 1 }
    return min(1, cb / (1 - cs))
}

/// Shared by `handRolledChannel`'s `colorBurn` case and its `vividLight` case. Body unchanged from
/// phase 5a.
private func colorBurnChannel(backdrop cb: Float, source cs: Float) -> Float {
    if cb >= 1 { return 1 }
    if cs <= 0 { return 0 }
    return 1 - min(1, (1 - cb) / cs)
}

/// Body unchanged from phase 5a; factored out alongside the other two so all three hand-rolled Tier 1
/// formulas live at the same scope as the Tier 2 callers that might one day want them.
private func softLightChannel(backdrop cb: Float, source cs: Float) -> Float {
    if cs <= 0.5 { return cb - (1 - 2 * cs) * cb * (1 - cb) }
    // The cubic below a quarter keeps the curve's slope finite at zero, where `sqrt` is vertical and
    // would band on dark backdrops.
    let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : sqrt(cb)
    return cb + (2 * cs - 1) * (d - cb)
}

// MARK: - W3C's non-separable helpers (§7 Tier 2)
//
// `Lum`, `Sat`, `ClipColor`, `SetLum`, `SetSat` — free functions rather than `Triple` methods because
// nothing else in this file hangs functions off a tuple type, and because it keeps them visually
// grouped with the spec section they come from rather than scattered through `BlendMode`'s extension.

/// The perceptual weighting every one of Tier 2's non-separable formulas keys off — Hue, Saturation,
/// Color and Luminosity all call it, and so do `lighterColor`/`darkerColor`, so "how bright is this
/// colour" has exactly one definition in this file. Must agree with `lum` in `Composite.metal`.
private func lum(_ c: Triple) -> Float { 0.3 * c.r + 0.59 * c.g + 0.11 * c.b }

private func sat(_ c: Triple) -> Float { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }

/// Pulls an out-of-gamut colour back into `[0, 1]` along the line through it and its own `Lum` —
/// `SetLum` is the only caller, and always on a colour it just shifted uniformly, which is what can
/// push a channel negative or past 1 in the first place.
///
/// The two `max(_, 1e-6)` guards exist only for the case both branches meet: a colour whose `Lum`
/// equals its `min`/`max` is one whose three channels are already equal, and there `c - l` is exactly
/// zero for every channel — so the guard changes a `0 / 0` into a `0 / epsilon`, not the result.
private func clipColor(_ c: Triple) -> Triple {
    let l = lum(c)
    let n = min(c.r, c.g, c.b), x = max(c.r, c.g, c.b)
    var result = c
    if n < 0 {
        let scale = l / max(l - n, 1e-6)
        result = (l + (result.r - l) * scale, l + (result.g - l) * scale, l + (result.b - l) * scale)
    }
    if x > 1 {
        let scale = (1 - l) / max(x - l, 1e-6)
        result = (l + (result.r - l) * scale, l + (result.g - l) * scale, l + (result.b - l) * scale)
    }
    return result
}

private func setLum(_ c: Triple, _ l: Float) -> Triple {
    let d = l - lum(c)
    return clipColor((c.r + d, c.g + d, c.b + d))
}

/// See `handRolledTriple`'s doc comment for why this is one affine remap rather than the spec's
/// sort-and-rewrite — the two are the same function.
private func setSat(_ c: Triple, _ s: Float) -> Triple {
    let cMax = max(c.r, c.g, c.b), cMin = min(c.r, c.g, c.b)
    guard cMax > cMin else { return (0, 0, 0) }
    let scale = s / (cMax - cMin)
    return ((c.r - cMin) * scale, (c.g - cMin) * scale, (c.b - cMin) * scale)
}

// MARK: - The Core Graphics reference

enum CoreGraphicsCompositor {

    static func composite(_ request: RenderRequest) -> CGImage? {
        let size = request.canvasSize
        guard size.width > 0, size.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: size)

        let image = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
            .image { context in
                if let background = request.background {
                    background.color.setFill()
                    UIRectFill(bounds)
                }
                draw(request.tree, of: request, in: bounds, context: context)
            }
        return image.cgImage
    }

    /// Draws one bottom-to-top stack into the context the caller has already made current.
    ///
    /// **Groups do not get their own buffer while they are still transparent parentheses, and that is
    /// what makes phase 2's gate reachable.** Source-over is associative, so compositing a group's
    /// children into a scratch buffer and then that buffer over the backdrop is the same *arithmetic*
    /// as drawing the children straight onto the backdrop — but it is not the same *bytes*: the
    /// intermediate rounds to 8-bit premultiplied once more than the direct path, and a group nested
    /// three deep rounds three more times. Against a gate that says "byte-identical", a scratch buffer
    /// per folder would fail on documents whose only sin is having folders in them.
    ///
    /// So a group allocates only when it actually changes the result, and `RenderNode.needsOwnBuffer`
    /// is that decision — stated once, for this backend and Metal's both. All three of its clauses
    /// are reachable as of phase 5; a folder nobody has touched is still opacity 1, normal and
    /// isolated over nothing that blends, so it takes the direct path and the derived tree still
    /// provably composites to what the deleted flat walk composited. §5.3's "never allocate one per
    /// layer" wants exactly this, and `PerfBaselineTests` measures it.
    private static func draw(_ nodes: [RenderNode], of request: RenderRequest, in bounds: CGRect,
                             context: UIGraphicsImageRendererContext) {
        for node in nodes {
            switch node.content {
            case .leaf(let layerIndex):
                // A leaf's flag gates the leaf; a group's gates its whole subtree (see the `.node`
                // case). The deleted flat walk's `where layer.isVisible` is exactly this test, and
                // `CompositorParityLogicTests.flatWalkComposite` still holds it to that.
                guard node.isVisible,
                      request.sources.indices.contains(layerIndex),
                      let source = request.sources[layerIndex] else { continue }
                // **A leaf blends as it is drawn** (`RenderNode.blendMode`): its mode is an argument
                // to this one draw, against whatever the walk has accumulated underneath. That is
                // the whole difference from the `.node` case below, which blends once against the
                // backdrop after assembling.
                //
                // A masked leaf needs no buffer of its own: the mask multiplies the one image it is
                // about to draw (§6.1 — at render time, never into the layer's own pixels).
                let pixels = masked(source.image, by: node, of: request)
                draw(UIImage(cgImage: pixels, scale: 1, orientation: .up),
                     mode: node.blendMode, opacity: node.opacity, in: bounds, context: context)

            case .node(let op, let inputs):
                // **A group's own `isVisible` gates its subtree** (§4.1) — a hidden group is a
                // subtree that is not walked, not a set of children that were each written hidden.
                // `toggleFolderVisibility` used to write through to every descendant, which made the
                // folder's flag a duplicate of its children's and made hide-then-show destroy the
                // per-layer visibility the artist had set by hand; phase 4a stopped that, and this is
                // the compositor's half of the same change. A child re-shown inside a hidden group
                // therefore does not draw, which is a deliberate change to shipped behaviour and is
                // pinned by `testAChildReShownInsideAHiddenFolderIsGatedByTheGroup`.
                //
                // Costs nothing to skip: the whole subtree is dropped before any buffer is
                // considered, so hiding a group is the cheapest thing in this walk rather than a
                // buffer full of nothing.
                guard node.isVisible else { continue }
                if !node.needsOwnBuffer {
                    // The direct path is also the pass-through path: children drawn straight onto
                    // the backdrop blend against it, which is what "pass-through" means.
                    // `needsOwnBuffer` guarantees `node.blendMode == .normal` here, so there is no
                    // group mode being silently dropped — a group that blends always buffers — and
                    // it guarantees `op == .stack`, so no fold is being dropped either.
                    for input in inputs { draw(input, of: request, in: bounds, context: context) }
                    continue
                }
                // Render the node's own composite, then apply its opacity and its mode once to the
                // finished thing — the alternative, applying either per child, is a different and
                // wrong picture wherever children overlap.
                //
                // **The scratch buffer starts transparent whatever `isIsolated` says, and that
                // is a decision rather than an omission.** A pass-through group that also
                // buffers — because it is faded, or because it has a mode of its own — cannot
                // have both: compositing children against the backdrop *and then* compositing
                // the result over that same backdrop counts it twice. Photoshop resolves the
                // same conflict the same way (choosing any mode other than Pass Through is what
                // makes a group isolated there), so a buffered group is an isolated group here,
                // and `isIsolated` is what decides the case that is still free to differ:
                // opacity 1, mode normal, something inside that blends.
                let assembled = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
                    .image { inner in fold(op, inputs, of: request, in: bounds, context: inner) }
                // The node's mask clips the node, so it lands on the assembled composite — which is
                // the same rule its opacity and its blend mode follow, and the reason
                // `needsOwnBuffer` counts a mask as a reason to allocate. It clips the *result* of
                // a fold, never the slots that went into it, for exactly the reason it clips a
                // group rather than its children.
                let clipped = assembled.cgImage.map { masked($0, by: node, of: request) }
                    .map { UIImage(cgImage: $0, scale: 1, orientation: .up) } ?? assembled
                draw(clipped, mode: node.blendMode, opacity: node.opacity, in: bounds, context: context)
            }
        }
    }

    /// **One node's input slots, combined by its op, into the buffer the caller has made current.**
    ///
    /// This is the whole of phase 8's change to this backend, and it is a change to the *walk* rather
    /// than to any arithmetic: §4.3's `Mix(A, B, .multiply)` is deliberately the same math as stacking
    /// B over A with multiply, so the fold reuses `draw(_:mode:opacity:in:context:)` — the same call a
    /// blending leaf and a blending group already go through — and no new primitive exists on either
    /// backend.
    ///
    /// **Slot 0 is drawn straight into the accumulator and every later slot gets a buffer of its own.**
    /// §4.3 says an input slot is always isolated, and slot 0 already is: the accumulator was made
    /// transparent one line above and nothing has touched it, so a separate buffer for it would buy
    /// nothing but one more 8-bit requantization. The later slots genuinely need one — the fold is
    /// between two *finished* composites, and drawing slot 1's contents one at a time onto slot 0
    /// would blend each of them against slot 0 in turn, which is `.stack` wearing a mode.
    ///
    /// `.stack` never takes the isolating branch, so it still runs the single-shared-accumulator loop
    /// it always did, byte for byte — the common case does not start paying a buffer per child.
    private static func fold(_ op: CompositorOp, _ inputs: [[RenderNode]], of request: RenderRequest,
                             in bounds: CGRect, context: UIGraphicsImageRendererContext) {
        for (slot, input) in inputs.enumerated() {
            guard case .mix(let mode) = op, slot > 0 else {
                draw(input, of: request, in: bounds, context: context)
                continue
            }
            let isolated = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
                .image { inner in draw(input, of: request, in: bounds, context: inner) }
            // Opacity 1: the node's own fade applies once to the finished fold, up in `draw`. Fading
            // a slot on its way into the fold would be the per-child mistake group opacity already
            // refuses to make.
            draw(isolated, mode: mode, opacity: 1, in: bounds, context: context)
        }
    }

    /// `image` with this node's masks applied, or `image` unchanged when it has none.
    ///
    /// Falls back to the unmasked pixels if a resolution fails, which is the same direction every
    /// other degenerate case in this file takes: show the artwork, not a hole. A mask that cannot
    /// resolve is one whose sources have gone (§6.6), and an unmasked layer is what that is defined
    /// to produce.
    private static func masked(_ image: CGImage, by node: RenderNode, of request: RenderRequest) -> CGImage {
        guard !node.masks.isEmpty,
              let mask = MaskResolver.coverage(for: node.masks, of: request),
              let clipped = MaskResolver.apply(mask, to: image) else { return image }
        return clipped
    }

    /// One image onto the current context, at `opacity`, in `mode` — the single place this backend
    /// applies a blend, for leaves and for assembled groups alike.
    private static func draw(_ image: UIImage, mode: BlendMode, opacity: Double,
                             in bounds: CGRect, context: UIGraphicsImageRendererContext) {
        if let cgMode = mode.coreGraphicsBlendMode {
            // Via `UIImage` rather than `CGContext.draw` so the top-left origin and the alpha
            // application are literally the same call the deleted flat walk made. A byte-identical
            // gate is not the place to hand-roll a coordinate flip.
            image.draw(in: bounds, blendMode: cgMode, alpha: CGFloat(opacity))
        } else {
            drawHandRolled(image, mode: mode, opacity: opacity, in: bounds, context: context)
        }
    }

    /// `add`, `subtract`, `linearLight` and Tier 2's hand-rolled modes, which CoreGraphics cannot
    /// express (see `BlendMode.coreGraphicsBlendMode`), computed a pixel at a time and stamped over
    /// the context.
    ///
    /// **This is slow on purpose, and the alternative was worse.** It snapshots the whole canvas,
    /// reads two buffers back, and writes a third — three canvas-sized allocations for one draw,
    /// where a CG primitive is one blit. The GPU is the answer for these modes at interactive rates
    /// (§5.1 is entirely this argument) and this backend's job is to be *right*: it is the oracle the
    /// shader is measured against and the fallback on a device with no Metal, so a fast approximation
    /// here would corrupt the measurement it exists to provide.
    ///
    /// The arithmetic is `blendOver`'s from `Composite.metal`, term for term, including the
    /// unpremultiply–blend–re-premultiply that keeps antialiased edges from darkening. `.toNearestOrEven`
    /// rather than `.rounded()` because that is the rule Metal's float→unorm8 conversion uses, and a
    /// half-way value rounded the other way is a delta of 1 on a channel that should have been exact.
    ///
    /// **One call to the blend per pixel, not one per channel — this is §7 Tier 2's trap, met.** Before
    /// Tier 2 this loop called `handRolledChannel` three times, once per channel, because every
    /// hand-rolled mode was separable and a channel's blended value depended on nothing but that same
    /// channel of `cb`/`cs`. Hue, Saturation, Color and Luminosity break that: the blended value of
    /// the red channel depends on green and blue too (`Lum`/`Sat` read all three), so the loop now
    /// builds the whole `(cb, cs)` triple first and asks `isNonSeparable` which one function can
    /// answer for all three channels at once. `Composite.metal` never had this problem — its
    /// `blendChannels` already takes a `float3` — which is exactly why the trap is CPU-only.
    private static func drawHandRolled(_ image: UIImage, mode: BlendMode, opacity: Double,
                                       in bounds: CGRect, context: UIGraphicsImageRendererContext) {
        let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
        guard width > 0, height > 0,
              let sourceImage = image.cgImage,
              let backdropImage = context.currentImage.cgImage,
              var source = premultipliedBytes(sourceImage, width: width, height: height),
              let backdrop = premultipliedBytes(backdropImage, width: width, height: height)
        else { return }

        let scale = Float(opacity)
        for index in source.indices {
            // Premultiplied, so opacity scales all four channels — the same `layer.read(gid) *
            // opacity` the kernel does, and for the reason `Composite.metal`'s header gives.
            source[index] = UInt8((Float(source[index]) * scale).rounded(.toNearestOrEven))
        }

        let nonSeparable = mode.isNonSeparable
        var result = backdrop
        for pixel in stride(from: 0, to: source.count, by: 4) {
            let sa = Float(source[pixel + 3]) / 255, da = Float(backdrop[pixel + 3]) / 255
            guard sa > 0 else { continue }  // a transparent source is the identity, exactly

            let sp = (Float(source[pixel]) / 255, Float(source[pixel + 1]) / 255, Float(source[pixel + 2]) / 255)
            let dp = (Float(backdrop[pixel]) / 255, Float(backdrop[pixel + 1]) / 255, Float(backdrop[pixel + 2]) / 255)
            let cs = (min(max(sp.0 / sa, 0), 1), min(max(sp.1 / sa, 0), 1), min(max(sp.2 / sa, 0), 1))
            let cb = da > 0 ? (min(max(dp.0 / da, 0), 1), min(max(dp.1 / da, 0), 1), min(max(dp.2 / da, 0), 1))
                            : (Float(0), Float(0), Float(0))
            // Non-separable modes need `handRolledTriple`'s single call over all three channels;
            // separable ones still go through `handRolledChannel`, once per channel, unchanged from
            // before Tier 2 — `mode.isNonSeparable` picked once per pixel rather than per channel is
            // just hoisting a loop-invariant, not a behaviour change.
            let blended: (Float, Float, Float) = nonSeparable
                ? mode.handRolledTriple(backdrop: cb, source: cs)
                : (mode.handRolledChannel(backdrop: cb.0, source: cs.0),
                   mode.handRolledChannel(backdrop: cb.1, source: cs.1),
                   mode.handRolledChannel(backdrop: cb.2, source: cs.2))

            // (1 - da) * cs + da * blended, then source-over — the same two lines `blendOver` in
            // `Composite.metal` runs, written three times because this array holds `UInt8`es rather
            // than a vector type.
            let channelValues: [(dp: Float, cs: Float, blended: Float)] =
                [(dp.0, cs.0, blended.0), (dp.1, cs.1, blended.1), (dp.2, cs.2, blended.2)]
            for channel in 0..<3 {
                let cr = channelValues[channel].cs + (channelValues[channel].blended - channelValues[channel].cs) * da
                let out = channelValues[channel].dp * (1 - sa) + sa * cr
                result[pixel + channel] = UInt8((min(max(out, 0), 1) * 255).rounded(.toNearestOrEven))
            }
            let outAlpha = da * (1 - sa) + sa
            result[pixel + 3] = UInt8((min(max(outAlpha, 0), 1) * 255).rounded(.toNearestOrEven))
        }

        guard let blended = makeImage(fromPremultiplied: result, width: width, height: height) else { return }
        // `.copy` rather than `.normal`: this image *is* the finished composite of everything drawn
        // so far, so it replaces the context rather than compositing onto it a second time.
        UIImage(cgImage: blended, scale: 1, orientation: .up).draw(in: bounds, blendMode: .copy, alpha: 1)
    }

    /// `image` redrawn into a buffer of exactly the app's byte layout — device RGB, premultiplied
    /// last, 8 bits per component, row 0 at the top.
    ///
    /// Redrawn rather than read out of whatever backing store the `CGImage` arrived with, which for
    /// something out of `UIGraphicsImageRenderer` may be a different component order, a different
    /// bit depth, or an extended range. `MetalCompositor.upload` normalises the same way for the same
    /// reason, and the two agreeing on this conversion is half of why the backends can be compared
    /// byte for byte at all.
    ///
    /// Shared with `MaskResolver` rather than copied there — a mask is resolved and applied in this
    /// same byte layout, and a second spelling of the conversion would be the drift §1 objects to.
    static func premultipliedBytes(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    static func makeImage(fromPremultiplied bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
