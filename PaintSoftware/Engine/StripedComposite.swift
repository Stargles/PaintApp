import UIKit

// MARK: - Striped compositing (RENDER.md §3.8)
//
// **§2.12 is the ruling this file exists to satisfy**: *"If the user slides the slider to full, then
// the canvas should be set to full."* Nothing may answer a composite that does not fit by making it
// smaller. So when the native texture set exceeds the budget the frame is composited in **horizontal
// strips**, each with an **apron** equal to the summed vertical kernel reach of the effects in the
// tree, and the strips are written into one frame at the size that was asked for. The budget chooses
// the strip height instead of the resolution.
//
// ### How strips and chunks compose, which is the whole design
//
// They are two different cuts of the same walk and they **nest**, strips outside and chunks inside.
//
// - A **chunk** (§3.4, `ChunkedComposite.swift`) cuts by *node*. It carries the accumulator across
//   the cut as a synthetic leaf, so every chunk of a frame writes into **one buffer** and the cut
//   costs nothing but a readback.
// - A **strip** cuts by *space*. Every leaf is cropped to the strip, so a strip is a whole,
//   self-contained composite of the entire tree over fewer rows.
//
// The nesting is forced rather than chosen: a chunk hands its accumulator to the next chunk in the
// same buffer, so a chunk cannot span two strips. Strips must therefore be the outer loop, and each
// strip is composited by `ChunkedCompositor` exactly as a whole frame is.
//
// **And there is one budget account, not two.** A strip does not have its own arithmetic: it makes
// `CompositorBudget.textureBytes` smaller, which is the same term `ChunkedCompositor.chunkSources`
// divides the budget by. So a strip that still does not fit is chunked by the existing formula with
// no special case anywhere, and `ChunkedCompositor.affordableRows` — the height planner below asks
// for — is literally that formula solved for the height instead of for the leaf count.
//
// **Which cut runs first is not arbitrary either.** The node cut is free; the space cut costs an
// apron, and the apron is duplicated work in every strip. So the plan takes the *tallest* strip whose
// buffer still affords one leaf, and lets chunking absorb everything past that. A document that fits
// today takes one strip covering the whole frame, which is the unstripped path with no window, no
// crop and no apron — measurably the same code, not merely the same picture.
//
// ### What an ink-input effect needs at a strip boundary: nothing but the apron
//
// §3.4 rule 3 is the dangerous rule for chunks, because a chunk *discards sources* — Outline and
// Bloom re-walk `tree.split(atLeaf:).below` from the leaf sources to build a paper-free, ink-only
// input, and a chunk that no longer holds those sources cannot rebuild it. That is why the chunk
// driver carries a second, paper-free accumulator.
//
// **A strip discards no sources at all.** It windows every one of them, and it hands the whole tree
// to every strip. So the `.ink` re-walk inside a strip composites the same nodes from the same
// leaves over the strip's own window, which is exactly the window of what the whole-frame re-walk
// would have produced — and where the effect's kernel reaches past the strip, the apron is real
// composited pixels rather than a boundary. The rule needs no strip-specific machinery, and the
// chunk-boundary machinery keeps working unchanged *inside* a strip because a chunk boundary is
// still a chunk boundary there.
//
// ### The two things the apron cannot pay for
//
// 1. **An effect that reads absolute position rather than a neighbourhood.** `noiseValue` hashes the
//    pixel's coordinate and `screenValue` indexes a 4x4 dither screen by `gid.y & 3`, so a strip
//    would restart the grain and jump the screen's phase at every seam. No apron helps: it is not a
//    neighbourhood read. `EffectParams.originX/originY` carries the strip's own top-left into both
//    kernels, on both backends, and `Effect.readsAbsolutePosition` is the list a test holds them to.
// 2. **A memo keyed on size alone.** `PixelOps.RasterizeKey` and `MaskResolver.CacheKey` both carry
//    width and height and nothing about *where* the buffer sits, so two strips of equal height would
//    collide on one entry and the second would be served the first's pixels. Both keys carry the
//    window now. This is the single most dangerous thing about strips: it is silent, it needs no
//    unusual document, and the picture it produces is a repeated band.

/// **Which pixels of a frame one buffer holds** — RENDER.md §3.8, and the value that makes a strip
/// expressible without either compositor backend learning what a strip is.
///
/// A request whose `window` is nil composites the whole frame, which is every request anything but
/// the strip driver mints. A request whose window is set composites `size` pixels of a `frameSize`
/// frame starting at `origin`, and **everything downstream reads it as "the buffer is smaller",
/// which both backends already understand**: `canvasSize` is the strip, `background.rect` is the
/// paper translated into it, the sources are the leaves drawn through a translated CTM, and the
/// masks resolve from those. Neither backend gained a code path; they gained one uniform.
///
/// **Both `frameSize` and `origin` are in the key**, because either alone lets two different
/// windows hash together. A whole frame of 100x50 and the top strip of a 100x100 frame have the
/// same origin and the same buffer size and hold entirely different pixels — the cel is drawn at a
/// different scale in each.
struct StripWindow: Hashable {

    /// The whole frame's buffer — the space every leaf is drawn in, and the space `RenderResolution`
    /// and the artist's canvas already agreed on.
    let frameSize: CGSize

    /// This buffer's top-left inside it, in frame pixels. Always whole and never negative; `x` is
    /// always 0 today, because §3.8's cut is horizontal.
    let origin: CGPoint
}

/// One frame's pixels, built a strip at a time when the whole frame's textures do not fit.
enum StripedCompositor {

    // MARK: - The entry point

    /// This recipe as an image, at the size it asked for — never at a size chosen for it (§2.12).
    ///
    /// **The identity when the frame fits**, and that is a property of the code rather than of the
    /// output: `plan` answers one strip covering everything, `composite` sees it and hands the
    /// unwindowed recipe straight to `ChunkedCompositor`. No window, no apron, no crop, no
    /// reassembly. So every document that composited in one piece yesterday takes exactly the path
    /// it took yesterday.
    static func composite(_ recipe: FrameRecipe,
                          budgetBytes: Int = CompositorBudget.textureBudgetBytes) -> CGImage? {
        guard recipe.canvasSize.width > 0, recipe.canvasSize.height > 0 else { return nil }
        let strips = plan(for: recipe, budgetBytes: budgetBytes)
        guard strips.count > 1 else {
            return ChunkedCompositor.composite(recipe, budgetBytes: budgetBytes)
        }
        return assemble(strips, of: recipe, budgetBytes: budgetBytes)
    }

    // MARK: - The apron

    /// **How many rows of context a strip needs above and below its own core** — §3.8's *"an apron
    /// equal to the summed kernel radius of the effects in the tree"*.
    ///
    /// **Summed rather than maxed, and that is not conservatism for its own sake.** Effects compose:
    /// an adjustment layer blurs the accumulator, and a second one above it blurs the result. A core
    /// pixel under the upper effect depends on rows within its radius of the *lower* effect's
    /// output, each of which depends on rows within the lower radius again — so a chain of effects
    /// reaches the sum of its radii, not the largest of them. Summing over every effect in the tree
    /// bounds every chain through it.
    ///
    /// **Mask stacks are in the sum too.** A mask's coverage is a composite of its own source stack
    /// (`MaskResolver.resolve`), and a graded node inside one convolves exactly as a node in the
    /// tree does. Rule 4 already puts a mask's *sources* inside the chunk width; this is the same
    /// relationship one dimension over.
    ///
    /// The radius per effect comes from `Effect.verticalKernelRadius`, in `Effect.swift`, where that
    /// file's own rule puts it: a knob is interpreted exactly once, in Swift, and both backends
    /// consume the result. An apron derived from a radius read a second time is a seam a few pixels
    /// wide with nothing to report it.
    static func apron(of tree: [RenderNode], maskStacks: [MaskSource: [RenderNode]]) -> Int {
        var total = summedKernelRadius(tree)
        for stack in maskStacks.values { total += summedKernelRadius(stack) }
        return total
    }

    private static func summedKernelRadius(_ nodes: [RenderNode]) -> Int {
        var total = 0
        for node in nodes {
            total += node.effect?.verticalKernelRadius ?? 0
            guard case .node(_, let inputs) = node.content else { continue }
            for input in inputs { total += summedKernelRadius(input) }
        }
        return total
    }

    // MARK: - The plan (pure, and no pixel anywhere in it)

    /// One strip: the rows of the frame it is responsible for, and the buffer it composites into.
    struct PlannedStrip: Equatable {

        /// The rows this strip owns, in frame pixels. The cores of a plan tile the frame exactly —
        /// they abut, they do not overlap, and their union is the whole frame.
        let core: CGRect

        /// `core` grown by the apron and clipped to the frame — what actually gets composited, and
        /// what the strip's `canvasSize` is. Equal to `core` for a one-strip plan.
        let buffer: CGRect
    }

    /// **The strip heights, top to bottom.** One strip covering the whole frame whenever the frame
    /// fits, which is the case §2.12 is about and the case nearly every document is in.
    ///
    /// The height comes from `ChunkedCompositor.affordableRows`, which is `chunkSources` solved for
    /// the height rather than for the leaf count — **one account, read two ways**, so a strip and a
    /// chunk cannot disagree about what the budget is. The target is "one leaf still fits", not
    /// "every leaf fits": cutting by space costs an apron in every strip while cutting by node costs
    /// a readback, so the plan takes the tallest strip that lets chunking do the rest.
    ///
    /// **The apron is paid out of the strip's height, not added to it.** `affordableRows` bounds the
    /// *buffer*, and the buffer is core plus apron, so the core is what is left. That is why a
    /// document with a deep effect chain gets shorter strips rather than a budget overrun.
    ///
    /// Floored at one row, honestly: a core of one row with an apron on each side may still exceed
    /// the budget, and there is nothing below one row. That is the same floor `chunkSources` takes
    /// at one leaf, for the same reason.
    static func plan(for recipe: FrameRecipe,
                     budgetBytes: Int = CompositorBudget.textureBudgetBytes) -> [PlannedStrip] {
        plan(tree: recipe.tree, maskStacks: recipe.maskStacks, canvasSize: recipe.canvasSize,
             budgetBytes: budgetBytes)
    }

    /// The plan without a recipe — **pure, and no pixel anywhere in it**, which is what lets a test
    /// ask what an iPad 9 would do with a 4096² canvas while running on a Mac that would have to
    /// allocate 64 MiB a texture to find out. The same seam
    /// `CompositorBudget.textureBudgetBytes(physicalMemory:)` exists for.
    static func plan(tree: [RenderNode], maskStacks: [MaskSource: [RenderNode]],
                     canvasSize: CGSize,
                     budgetBytes: Int = CompositorBudget.textureBudgetBytes) -> [PlannedStrip] {
        let frame = CGRect(origin: .zero, size: canvasSize)
        let frameRows = Int(canvasSize.height.rounded())
        guard frameRows > 0, canvasSize.width > 0 else { return [] }

        let apron = apron(of: tree, maskStacks: maskStacks)
        let bufferRows = ChunkedCompositor.affordableRows(width: canvasSize.width,
                                                          tree: tree, budgetBytes: budgetBytes)
        // The whole frame in one piece — including the case where the apron alone would not fit,
        // because a frame that already fits needs no apron at all.
        guard bufferRows < frameRows else {
            return [PlannedStrip(core: frame, buffer: frame)]
        }
        let coreRows = max(1, bufferRows - 2 * apron)

        var strips: [PlannedStrip] = []
        var top = 0
        while top < frameRows {
            let height = min(coreRows, frameRows - top)
            let core = CGRect(x: 0, y: CGFloat(top), width: canvasSize.width,
                              height: CGFloat(height))
            strips.append(PlannedStrip(core: core,
                                       buffer: core.insetBy(dx: 0, dy: CGFloat(-apron)).intersection(frame)))
            top += height
        }
        return strips
    }

    // MARK: - The driver

    /// Composites every strip and writes them into one frame.
    ///
    /// **`.copy`, not source-over.** The cores tile the frame exactly, so each strip's pixels
    /// *replace* the band they own rather than compositing onto whatever the renderer started with.
    /// Source-over would be the identity here only because the renderer starts transparent, which is
    /// a coincidence rather than the contract; `mixBack` ends the same way for the same reason.
    private static func assemble(_ strips: [PlannedStrip], of recipe: FrameRecipe,
                                 budgetBytes: Int) -> CGImage? {
        let frame = CGRect(origin: .zero, size: recipe.canvasSize)
        var pieces: [(image: CGImage, at: CGRect)] = []
        pieces.reserveCapacity(strips.count)

        for strip in strips {
            guard let composited = ChunkedCompositor.composite(recipe.windowed(to: strip.buffer),
                                                               budgetBytes: budgetBytes) else { return nil }
            // The apron is context, never output: it is composited so the core's kernels have real
            // pixels to read, and then it is thrown away. Cropping in the strip's own coordinates,
            // which is the core offset by the buffer's origin.
            let inset = CGRect(x: 0, y: strip.core.minY - strip.buffer.minY,
                               width: strip.core.width, height: strip.core.height)
            guard let core = crop(composited, to: inset) else { return nil }
            pieces.append((core, strip.core))
        }

        let image = UIGraphicsImageRenderer(bounds: frame, format: PixelOps.transparentFormat())
            .image { _ in
                for piece in pieces {
                    UIImage(cgImage: piece.image, scale: 1, orientation: .up)
                        .draw(in: piece.at, blendMode: .copy, alpha: 1)
                }
            }
        return image.cgImage
    }

    /// `CGImage.cropping(to:)` with the rounding stated rather than inherited.
    ///
    /// Every rect here is whole pixels by construction — the frame is `RenderRequest.wholePixels`,
    /// the strip heights are integers and the apron is a count of rows — so this is exact. It is
    /// spelled out anyway because a crop that silently moved by half a pixel would show up as a
    /// one-row seam, which is precisely the failure that is easiest to read as "the apron is too
    /// short" and spend a day on.
    private static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        image.cropping(to: CGRect(x: rect.origin.x.rounded(), y: rect.origin.y.rounded(),
                                  width: rect.width.rounded(), height: rect.height.rounded()))
    }
}
