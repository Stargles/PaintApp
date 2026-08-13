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
    /// Eleven of the fourteen are CoreGraphics primitives, and that is worth leaning on rather than
    /// hand-rolling for uniformity: `CGBlendMode` implements the PDF imaging model's separable blend
    /// functions, which are the same formulas `Composite.metal` implements from the W3C spelling of
    /// them. So the CPU reference is *Apple's* implementation of the blend, not a second copy of the
    /// shader's — which is what makes the GPU-versus-CPU delta a real measurement instead of a test
    /// of whether one author wrote the same expression twice.
    ///
    /// **The three that are hand-rolled (`add`, `subtract`, `linearLight`) are hand-rolled because
    /// they are absent, not because they are awkward.** CoreGraphics offers `.plusLighter`, which
    /// looks like Add and is not: it is Porter-Duff *plus*, summing premultiplied channels including
    /// alpha, so it agrees with linear dodge only where the backdrop is opaque and the sum does not
    /// clamp, and it inflates alpha everywhere else. Substituting it would be wrong in exactly the
    /// cases a blend mode is interesting.
    var coreGraphicsBlendMode: CGBlendMode? {
        switch self {
        case .normal:      return .normal
        case .multiply:    return .multiply
        case .screen:      return .screen
        case .overlay:     return .overlay
        case .darken:      return .darken
        case .lighten:     return .lighten
        case .hardLight:   return .hardLight
        case .difference:  return .difference
        // Not "CoreGraphics lacks these" but "CoreGraphics disagrees about these" — see
        // `handRolledChannel`, and the measured table in `CompositorParityLogicTests`.
        case .colorDodge, .colorBurn, .softLight: return nil
        case .add, .subtract, .linearLight: return nil
        }
    }

    /// The per-channel blend for every mode this backend computes itself, unpremultiplied on both
    /// sides. Must agree with `blendChannels` in `Composite.metal`, and is the only place in this
    /// backend where blend arithmetic is written out at all.
    ///
    /// **Two different reasons a mode lands here, and the second one is a finding.**
    ///
    /// `add`, `subtract` and `linearLight` are here because `CGBlendMode` has no case for them.
    ///
    /// `colorDodge`, `colorBurn` and `softLight` are here because Apple's cases *exist and disagree*.
    /// Sweeping all fourteen modes over 4096 (colour, alpha) pairs put every other mode within one
    /// step of the shader and these three at **141, 249 and 16**. That is not a rounding regime; it is
    /// two different formulas. CoreGraphics implements the PDF 1.4 originals, where the divisions have
    /// no zero-backdrop case — so `colorDodge` lifts a black backdrop to white at `cs == 1` where the
    /// modern rule keeps it black, `colorBurn` does the mirror of that at `cs == 0`, and `softLight`
    /// uses a different `D(cb)` curve altogether. W3C Compositing Level 1 (equivalently PDF 2.0) added
    /// the guards, and it is what Photoshop and CSP do, which settles which of the two an artist
    /// reaching for Color Dodge means.
    ///
    /// So the shader is the correct one and this backend follows it, rather than the reference being
    /// "whatever Apple ships". Worth stating plainly because §5.1 calls the CoreGraphics path the
    /// byte-for-byte definition of correct: that holds for the *walk* — the order, the buffers, the
    /// alpha — and not for the blend functions themselves, where the spec is the authority and both
    /// backends are implementations of it.
    fileprivate func handRolledChannel(backdrop cb: Float, source cs: Float) -> Float {
        switch self {
        case .add:         return min(1, cb + cs)
        case .subtract:    return max(0, cb - cs)
        case .linearLight: return min(1, max(0, cb + 2 * cs - 1))
        case .colorDodge:
            if cb <= 0 { return 0 }
            if cs >= 1 { return 1 }
            return min(1, cb / (1 - cs))
        case .colorBurn:
            if cb >= 1 { return 1 }
            if cs <= 0 { return 0 }
            return 1 - min(1, (1 - cb) / cs)
        case .softLight:
            if cs <= 0.5 { return cb - (1 - 2 * cs) * cb * (1 - cb) }
            // The cubic below a quarter keeps the curve's slope finite at zero, where `sqrt` is
            // vertical and would band on dark backdrops.
            let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : sqrt(cb)
            return cb + (2 * cs - 1) * (d - cb)
        default:           return cs
        }
    }
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
                draw(UIImage(cgImage: source.image, scale: 1, orientation: .up),
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
                switch op {
                case .stack:
                    guard node.needsOwnBuffer else {
                        // The direct path is also the pass-through path: children drawn straight
                        // onto the backdrop blend against it, which is what "pass-through" means.
                        // `needsOwnBuffer` guarantees `node.blendMode == .normal` here, so there is
                        // no group mode being silently dropped — a group that blends always buffers.
                        for input in inputs { draw(input, of: request, in: bounds, context: context) }
                        continue
                    }
                    // Render the group's own composite, then apply its opacity and its mode once to
                    // the finished thing — the alternative, applying either per child, is a
                    // different and wrong picture wherever children overlap.
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
                    let grouped = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
                        .image { inner in
                            for input in inputs { draw(input, of: request, in: bounds, context: inner) }
                        }
                    draw(grouped, mode: node.blendMode, opacity: node.opacity, in: bounds, context: context)
                }
            }
        }
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

    /// `add`, `subtract` and `linearLight`, which CoreGraphics cannot express (see
    /// `BlendMode.coreGraphicsBlendMode`), computed a pixel at a time and stamped over the context.
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

        var result = backdrop
        for pixel in stride(from: 0, to: source.count, by: 4) {
            let sa = Float(source[pixel + 3]) / 255, da = Float(backdrop[pixel + 3]) / 255
            guard sa > 0 else { continue }  // a transparent source is the identity, exactly
            for channel in 0..<3 {
                let sp = Float(source[pixel + channel]) / 255
                let dp = Float(backdrop[pixel + channel]) / 255
                let cs = min(max(sp / sa, 0), 1)
                let cb = da > 0 ? min(max(dp / da, 0), 1) : 0
                let blended = mode.handRolledChannel(backdrop: cb, source: cs)
                let cr = cs + (blended - cs) * da            // (1 - da) * cs + da * blended
                let out = dp * (1 - sa) + sa * cr
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
    private static func premultipliedBytes(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private static func makeImage(fromPremultiplied bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
