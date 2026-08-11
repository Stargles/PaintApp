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
/// **Defaults to `.coreGraphics`, and that is not a placeholder.** The GPU is what §5.1 wants for
/// per-pixel blend math over 4.2M pixels, and none of that math exists until phase 5; for an
/// all-normal document the two backends do the same source-over and the CPU one has no upload to pay
/// for. The flag is here so the Metal path can be exercised and compared before anything depends on
/// it, which is what "behind a flag" in §11 phase 2 means.
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
            // backends agree byte for byte (`CompositorParityLogicTests`), so this is a performance
            // fallback and never a visual one.
            return MetalCompositor.composite(request) ?? CoreGraphicsCompositor.composite(request)
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
            .image { _ in
                if let background = request.background {
                    background.color.setFill()
                    UIRectFill(bounds)
                }
                draw(request.tree, of: request, in: bounds)
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
    /// So a group allocates only when it actually changes the result — when it carries an opacity
    /// other than 1, and in phase 4 a blend mode, a mask, or isolation. Today `renderNodes` hardcodes
    /// folder opacity to 1 (`RenderTree.swift`, "the identity that makes a group's presence in the
    /// tree a no-op"), so every document takes the direct path and the derived tree provably composites
    /// to what the flat walk composites. §5.3's "never allocate one per layer" wants this anyway.
    private static func draw(_ nodes: [RenderNode], of request: RenderRequest, in bounds: CGRect) {
        for node in nodes {
            switch node.content {
            case .leaf(let layerIndex):
                // Leaf visibility gates; **group visibility deliberately does not** (see the `.node`
                // case). `PixelOps.compositeCanvas`'s `where layer.isVisible` is exactly this test.
                guard node.isVisible,
                      request.sources.indices.contains(layerIndex),
                      let source = request.sources[layerIndex] else { continue }
                // Via `UIImage` rather than `CGContext.draw` so the top-left origin and the alpha
                // application are literally the same call `PixelOps.compositeCanvas` makes. A
                // byte-identical gate is not the place to hand-roll a coordinate flip.
                UIImage(cgImage: source.image, scale: 1, orientation: .up)
                    .draw(in: bounds, blendMode: .normal, alpha: CGFloat(node.opacity))

            case .node(let op, let inputs):
                // **A group's own `isVisible` is not consulted, and that is today's behaviour rather
                // than an oversight.** `toggleFolderVisibility` writes through to every descendant
                // (CanvasManager.swift:829), so a hidden folder is a folder whose children are each
                // already hidden, and the flag on the folder is a duplicate of theirs rather than a
                // gate over them. Honouring it here would change one shipped behaviour immediately:
                // a child re-shown inside a hidden folder renders today, and is pinned doing so by
                // `testAChildReShownInsideAHiddenFolderStillRendersToday`.
                //
                // §4.1 makes the group gate its subtree and stops the write-through — deliberately,
                // in phase 4, together with the migration question §10 item 3 leaves open. Phase 2's
                // gate is byte-identity with what ships now, so the change cannot be smuggled in here.
                switch op {
                case .stack:
                    guard node.opacity < 1 else {
                        for input in inputs { draw(input, of: request, in: bounds) }
                        continue
                    }
                    // The isolated case: render the group's own composite, then apply its opacity
                    // once to the finished thing. Unreachable until phase 4 gives folders an opacity,
                    // and written now because the alternative — applying group opacity per child — is
                    // a different and wrong picture wherever children overlap.
                    let grouped = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
                        .image { _ in
                            for input in inputs { draw(input, of: request, in: bounds) }
                        }
                    grouped.draw(in: bounds, blendMode: .normal, alpha: CGFloat(node.opacity))
                }
            }
        }
    }
}
