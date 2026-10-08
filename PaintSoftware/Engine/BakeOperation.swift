import UIKit

/// **What a baking layer does to the drawing beneath it, resolved at one frame** — TODO (131).
///
/// Bake is the verb of a layer that holds no pixels of its own: an effect layer grades what is
/// beneath it, a flat-colour value layer blends a colour into it. Merge Down used to carry both into
/// *one* layer below, by compositing; Bake carries them into *every* drawing beneath, one at a time,
/// and the two share the arithmetic rather than spell it twice — each operation is a
/// `MergeContribution`, and `CoreGraphicsCompositor.mergedDown` is the one place a contribution meets
/// the pixels it acts on. That is also what makes "reuse the compositor's colour math" literal: the
/// grade is `EffectReference.apply` and the blend is `CoreGraphicsCompositor.draw`, exactly as the
/// canvas runs them, and there is no third copy of either.
///
/// **Two routes, and the operation says which** (`route`). A colour-class grade and every blend are a
/// function of the colour under them and nothing else, so an element's colour can be taken through
/// the operation and the drawing stays a drawing (`baked(_: CodableColor)`). Anything that reads
/// position or neighbours cannot be a colour, so the pixels are graded instead
/// (`baked(_: UIImage)`) — `Effect.bakeRoute` is the classification.
enum BakeOperation: Equatable {
    /// An effect layer's grade, crossfaded back by `opacity` — the layer's own, resolved at the frame.
    case grade(Effect, opacity: Double)
    /// A flat-colour value layer: `colour` composited over what is beneath in `mode`, at `opacity`.
    case blend(LayerRenderSource.SolidColor, mode: BlendMode, opacity: Double)

    /// A blend is always a colour; a grade is whatever the effect says.
    var route: Effect.BakeRoute {
        switch self {
        case .grade(let effect, _): return effect.bakeRoute
        case .blend: return .colour
        }
    }

    // MARK: - The pixel route

    /// `image` with the operation applied to it, at the image's own pixel size and scale, **keeping the
    /// drawing's own coverage**: where the image is transparent the result is, and where it is partly
    /// covered it is covered by exactly that much.
    ///
    /// A grade never moves alpha, so it goes straight through `mergedDown`. **A blend does** — drawn
    /// over a transparent pixel it shows its own source, which is the paper's business and not the
    /// drawing's (the canvas would show the sheet there; a bake changes the drawings only). So a blend
    /// is taken through the *colour* the pixels carry: each pixel's colour laid on an opaque
    /// backdrop, blended by the compositor's own `draw`, and given back its coverage. That is the
    /// colour route's arithmetic at every pixel, so the two routes cannot disagree.
    ///
    /// Any size, which is what lets one function serve a cel's canvas-sized pixels and a placed image's
    /// own. Position-dependent effects are graded in the buffer's own coordinates here, which for a
    /// placed image is not the canvas's — they take this route for a vector layer's *rasterized cel*,
    /// never for a placed image (`CanvasManager.bakePlan` sends a pixel-route effect through
    /// `rasterizeLayer` first).
    func baked(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width, height = cgImage.height
        let pixels = CGSize(width: width, height: height)
        let result: CGImage?
        switch self {
        case .grade:
            result = CoreGraphicsCompositor.mergedDown(
                bottom: .pixels(UIImage(cgImage: cgImage, scale: 1, orientation: .up), mode: .normal, opacity: 1),
                top: contribution(canvasSize: pixels), canvasSize: pixels).cgImage
        case .blend:
            result = blendedKeepingCoverage(of: cgImage, width: width, height: height)
        }
        guard let result else { return image }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    private func blendedKeepingCoverage(of image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let coverage = CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height) else { return nil }
        // Each pixel's colour on an opaque backdrop: un-premultiplied, alpha 255.
        var ink = coverage
        for offset in stride(from: 0, to: ink.count, by: 4) {
            let alpha = Float(coverage[offset + 3])
            for channel in 0..<3 {
                ink[offset + channel] = alpha > 0
                    ? UInt8(min(255, (Float(coverage[offset + channel]) * 255 / alpha).rounded(.toNearestOrEven)))
                    : 0
            }
            ink[offset + 3] = 255
        }
        let pixels = CGSize(width: width, height: height)
        guard let opaque = CoreGraphicsCompositor.makeImage(fromPremultiplied: ink, width: width, height: height),
              let blended = CoreGraphicsCompositor.mergedDown(
                bottom: .pixels(UIImage(cgImage: opaque, scale: 1, orientation: .up), mode: .normal, opacity: 1),
                top: contribution(canvasSize: pixels), canvasSize: pixels).cgImage,
              var out = CoreGraphicsCompositor.premultipliedBytes(blended, width: width, height: height)
        else { return nil }
        // And the drawing's own coverage given back, premultiplied again.
        for offset in stride(from: 0, to: out.count, by: 4) {
            let alpha = Float(coverage[offset + 3]) / 255
            for channel in 0..<3 {
                out[offset + channel] = UInt8((Float(out[offset + channel]) * alpha).rounded(.toNearestOrEven))
            }
            out[offset + 3] = coverage[offset + 3]
        }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: out, width: width, height: height)
    }

    private func contribution(canvasSize: CGSize) -> MergeContribution {
        switch self {
        case .grade(let effect, let opacity):
            return .grade(effect, opacity: opacity, coverage: nil)
        case .blend(let colour, let mode, let opacity):
            guard let sheet = LayerRenderSource.solid(colour, canvasSize: canvasSize) else { return .nothing }
            return .pixels(UIImage(cgImage: sheet, scale: 1, orientation: .up), mode: mode, opacity: opacity)
        }
    }

    // MARK: - The colour route

    /// **One colour taken through the operation** — the colour as an opaque pixel, put through the
    /// same `mergedDown` the pixels go through. Its alpha is the element's own and does not travel
    /// (`SelectionEditKind`'s ruling for Change Colour: a faint stroke stays faint), and what comes
    /// back is on the 8-bit grid every stored colour is on anyway.
    ///
    /// For an opaque element over nothing else this is exactly the pixel the canvas shows under the
    /// grade; where elements overlap, or ink is soft at its edge, the canvas grades the *composite*
    /// and this grades each colour alone — the approximation Bake is ruled to make.
    func baked(_ colour: CodableColor) -> CodableColor {
        func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded(.toNearestOrEven)) }
        let pixel = CGSize(width: 1, height: 1)
        guard let backdrop = CoreGraphicsCompositor.makeImage(
                fromPremultiplied: [byte(colour.red), byte(colour.green), byte(colour.blue), 255],
                width: 1, height: 1),
              let result = CoreGraphicsCompositor.mergedDown(
                bottom: .pixels(UIImage(cgImage: backdrop, scale: 1, orientation: .up), mode: .normal, opacity: 1),
                top: contribution(canvasSize: pixel), canvasSize: pixel).cgImage,
              let bytes = CoreGraphicsCompositor.premultipliedBytes(result, width: 1, height: 1),
              bytes[3] > 0
        else { return colour }
        let alpha = Double(bytes[3])
        return CodableColor(red: Double(bytes[0]) / alpha, green: Double(bytes[1]) / alpha,
                            blue: Double(bytes[2]) / alpha, alpha: colour.alpha)
    }

    // MARK: - An element

    /// What one element becomes under the operation.
    enum ElementResult {
        /// The element with its colour — or, for a placed picture, its pixels — taken through it.
        case baked(VectorElement)
        /// The element has no colour for the operation to act on, by its nature rather than by
        /// anything the artist could change: an eraser stroke removes ink and carries none.
        case untouched
        /// The element is a picture that is not pixels in the document — a video or a live stream —
        /// and there is no colour or asset here to write the result into. Left as it was, and said so.
        case cannotTakeColour

        /// The element to write back: the baked one, or nil where the element stays as it was.
        var element: VectorElement? {
            if case .baked(let element) = self { return element }
            return nil
        }
    }

    /// **The colour route for one element, exhaustive over the element kinds** — a new kind has to
    /// decide what a bake does to it.
    ///
    /// - Every colour the element carries (`VectorElement.mappingColours`) goes through the operation.
    ///   A **gradient fill** is taken by its two stops, and stays a gradient: the ramp between them
    ///   is still mixed in Oklab, so it is the colour a person would call halfway between the two
    ///   *graded* stops. That is exact for a straight tint and an approximation for a curve, which
    ///   is the same one a colour makes against the composite.
    /// - A **placed image** is graded as pixels into a new picture with no file name, so the next
    ///   save writes it as a new asset beside the old one and the original is untouched until then.
    ///   A colour-class operation acts on pixel colour alone, so grading the picture in its own
    ///   coordinates is the same as grading it on the canvas.
    func baked(_ element: VectorElement, using colours: BakedColours) -> ElementResult {
        if let recoloured = element.mappingColours({ colours($0) }) { return .baked(recoloured) }
        switch element {
        case .image(var image):
            image.image = baked(image.image)
            image.fileName = nil
            return .baked(.image(image))
        case .video, .stream:
            return .cannotTakeColour
        case .stroke, .fill, .text:
            // Only an eraser stroke reaches here: it removes ink and carries none.
            return .untouched
        }
    }
}

/// **An operation's colour route, memoized.** A document holds a handful of distinct colours across
/// thousands of strokes, and each colour costs a one-pixel render, so the answer is remembered for
/// the life of one bake — a class so that the same instance is shared by every cel the bake rewrites.
final class BakedColours {
    let operation: BakeOperation
    private var memo: [CodableColor: CodableColor] = [:]

    init(_ operation: BakeOperation) { self.operation = operation }

    func callAsFunction(_ colour: CodableColor) -> CodableColor {
        if let known = memo[colour] { return known }
        let baked = operation.baked(colour)
        memo[colour] = baked
        return baked
    }
}
