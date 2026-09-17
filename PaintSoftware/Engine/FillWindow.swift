import CoreGraphics
import UIKit

/// The rectangle of the canvas a fill gesture does its pixel work in, and the scale it works at —
/// TODO (86).
///
/// Every buffer a fill gesture makes — the reference composite, the path wall, the lasso stencil,
/// the GPU session's own buffers, the preview and the §7 collar — is `workingSize`, never the canvas.
/// **So a fill's memory is a function of the region being filled and of `pixelBudget`, and the
/// canvas extent is not in the formula**, which is the owner's own reading of the tool: *"I don't
/// see why it should ever have a memory complexity which is affected by the canvas size."*
///
/// **Exact at scale 1, and scale 1 is every window that fits the budget.** A lasso's window is the
/// loop's bounds plus `halo`, and nothing a lasso fill computes can reach past it: the collar flood
/// never leaves the loop (LASSO_FILL.md §6 step 3), and every neighbourhood operator — the gap
/// close's dilate and erode, the edge bridge, the coverage erosion — reads at most `halo` pixels
/// from the pixel it writes. A bucket's window starts as `initialBucketSide` around the tap and
/// **grows** while the painted region reaches the halo band along any edge that is not the
/// canvas's own (`MetalFillSession.paintedReaches`): a flood at the band may have more to reach, and
/// a close computed in the band was computed without the walls beyond it, so the window is trusted
/// only where the paint keeps clear of it. Each growth doubles the window toward the sides that were
/// reached, so a fill converges in a logarithmic number of re-runs and the window is never more than
/// about four times the region's own box.
///
/// **Below scale 1 only when the region alone exceeds the budget.** Then the window is worked at the
/// largest scale whose pixels fit, the kernel radii scale with it, and the picture comes back
/// coarser by that factor — a placed region a few pixels soft along its edge, where the alternative
/// was refusing the gesture. A vector layer keeps its walls sharp at any scale, because TODO (46)'s
/// path wall is a hairline redrawn at the working resolution rather than a resampled pixel.
struct FillWindow: Equatable {
    /// The canvas the window is cut from, in canvas pixels.
    let canvasSize: CGSize
    /// Whole canvas pixels, inside the canvas.
    let rect: CGRect
    /// Working pixels per canvas pixel: 1 whenever `rect` fits `pixelBudget`, less when it does not.
    let scale: CGFloat
    let workingWidth: Int
    let workingHeight: Int

    /// How far a fill's picture can depend on pixels beyond a window's rim, in canvas pixels: the gap
    /// close is a dilate then an erode of `gapRadius` each, the edge dilate and the coverage erosion
    /// read `edgeRadius`, and the two extra pixels cover the JFA's own rounding.
    static func halo(gapRadius: CGFloat, edgeRadius: CGFloat) -> CGFloat {
        (2 * gapRadius + edgeRadius + 2).rounded(.up)
    }

    /// The side of a bucket fill's first window. Deliberately small: a fill of a shape in line art —
    /// the ordinary bucket fill — is enclosed inside it and pays for one small session, and a fill
    /// that is not grows out of it in a step or two.
    static let initialBucketSide: CGFloat = 1024

    // MARK: - Making one

    /// The window covering `rect` of the canvas — clipped to the canvas, snapped outward to whole
    /// pixels — at the largest scale whose working pixels fit `pixelBudget`.
    static func fitting(_ rect: CGRect, in canvasSize: CGSize, pixelBudget: Int) -> FillWindow {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        var box = rect.integral.intersection(canvas)
        if box.isNull || box.width < 1 || box.height < 1 { box = canvas }
        let area = box.width * box.height
        let budget = CGFloat(max(1, pixelBudget))
        let scale = area <= budget ? 1 : (budget / area).squareRoot()
        return FillWindow(canvasSize: canvasSize, rect: box, scale: scale,
                          workingWidth: max(1, Int((box.width * scale).rounded(.down))),
                          workingHeight: max(1, Int((box.height * scale).rounded(.down))))
    }

    /// A lasso fill's window: the loop plus its halo.
    static func lasso(around loop: CGRect, halo: CGFloat, in canvasSize: CGSize,
                      pixelBudget: Int) -> FillWindow {
        fitting(loop.insetBy(dx: -halo, dy: -halo), in: canvasSize, pixelBudget: pixelBudget)
    }

    /// A bucket fill's first window: `initialBucketSide` square about the tap.
    static func bucket(around seed: CGPoint, in canvasSize: CGSize, pixelBudget: Int) -> FillWindow {
        let half = initialBucketSide / 2
        return fitting(CGRect(x: seed.x - half, y: seed.y - half,
                              width: initialBucketSide, height: initialBucketSide),
                       in: canvasSize, pixelBudget: pixelBudget)
    }

    // MARK: - Growing

    /// The window's edges, for the two questions growth asks: which edges *can* move (those not on
    /// the canvas's own), and which the paint reached.
    struct Sides: OptionSet {
        let rawValue: UInt8
        static let left = Sides(rawValue: 1), top = Sides(rawValue: 2)
        static let right = Sides(rawValue: 4), bottom = Sides(rawValue: 8)
    }

    /// The edges that are not the canvas's own — the only ones a fill can be cut short at.
    var growableSides: Sides {
        var sides = Sides()
        if rect.minX > 0 { sides.insert(.left) }
        if rect.minY > 0 { sides.insert(.top) }
        if rect.maxX < canvasSize.width { sides.insert(.right) }
        if rect.maxY < canvasSize.height { sides.insert(.bottom) }
        return sides
    }

    /// The halo in working pixels — the band `paintedReaches` is asked about.
    func band(forHalo halo: CGFloat) -> Int {
        max(1, Int((halo * scale).rounded(.up)))
    }

    /// This window doubled toward `sides`, or nil when none of them can move.
    func grown(toward sides: Sides, pixelBudget: Int) -> FillWindow? {
        let movable = sides.intersection(growableSides)
        guard !movable.isEmpty else { return nil }
        var box = rect
        if movable.contains(.left) { box.origin.x -= rect.width; box.size.width += rect.width }
        if movable.contains(.right) { box.size.width += rect.width }
        if movable.contains(.top) { box.origin.y -= rect.height; box.size.height += rect.height }
        if movable.contains(.bottom) { box.size.height += rect.height }
        return Self.fitting(box, in: canvasSize, pixelBudget: pixelBudget)
    }

    // MARK: - Mapping

    /// Canvas pixels → working pixels. Maps `rect` onto exactly `[0, workingWidth) x [0, workingHeight)`,
    /// so its scale is `scale` up to the rounding of the working size to whole pixels.
    var transform: CGAffineTransform {
        let sx = CGFloat(workingWidth) / rect.width
        let sy = CGFloat(workingHeight) / rect.height
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: -rect.minX * sx, ty: -rect.minY * sy)
    }

    /// The canvas, as a rect in working pixels — where a canvas-sized image is drawn so that the
    /// window's part of it lands on the working buffer.
    var canvasInWorking: CGRect {
        CGRect(origin: .zero, size: canvasSize).applying(transform)
    }

    /// A canvas point's working pixel, clamped into the buffer.
    func workingPixel(of point: CGPoint) -> (x: Int, y: Int) {
        let p = point.applying(transform)
        return (min(max(Int(p.x.rounded(.down)), 0), workingWidth - 1),
                min(max(Int(p.y.rounded(.down)), 0), workingHeight - 1))
    }
}

/// A picture of part of the canvas: `image` covers `rect`, in canvas pixels, and nothing outside it.
/// The fill tool's live preview (`Cel.fillPreview`) and its §7 collar are both one of these, sized
/// to the window the fill worked in rather than to the canvas.
struct FillPreview {
    let image: UIImage
    let rect: CGRect

    /// The image stretched over its rect, for a draw into a canvas-sized context — the same picture
    /// at scale 1, and the resample that scale below 1 already accepted otherwise.
    func draw() { image.draw(in: rect) }
}
