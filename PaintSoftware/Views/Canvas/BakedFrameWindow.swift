import UIKit

/// **Where a whole-canvas picture is drawn for the screen: the host's own pixels, wherever the canvas
/// sits under them** — so the picture Core Animation is handed is the size of the screen, never the
/// size of the canvas. The bake's (below) and, through `CanvasPictureView`, every layer's and the
/// onion skin's.
///
/// The bake is a whole frame at the canvas's size: 95 MiB at the owner's 5000². Handed to a layer as a
/// bitmap, every frame shown is a fresh picture of that size for the render server to copy and keep,
/// and during playback that is one per flip — the iPad 9's `backboardd` was killed at its 1,850 MiB
/// limit seconds into playing Test1 (2026-11-18), the third time a canvas-sized picture per frame has
/// killed playback there. Drawn instead into a `WindowSurfaceView` sized by this type, the render
/// server is handed two surfaces of the window's size once and nothing new per frame: at 1080×810
/// points on a 2× screen, 13.3 MiB each, whatever the canvas size, zoom or rotation.
///
/// Pure geometry plus the draw, so the bound and the mapping are pinned where the fast tier reaches.
struct BakedFrameWindow: Equatable {

    /// The surface's pixel rectangle: the host's size in device pixels, at the origin.
    let window: CGRect
    /// Maps a surface pixel to the container's points — canvas points, since every view the canvas
    /// draws in is pinned edge to edge in the container. What the surface's layer applies.
    let placement: CGAffineTransform

    /// - Parameters:
    ///   - hostSize: the canvas host's bounds, in points — what the artist can see of the canvas.
    ///   - screenScale: device pixels per point.
    ///   - hostToCanvas: maps a host point to a container (canvas) point — the inverse of the pan,
    ///     zoom and rotation the container is shown under.
    init?(hostSize: CGSize, screenScale: CGFloat, hostToCanvas: CGAffineTransform) {
        let width = (hostSize.width * screenScale).rounded(.up)
        let height = (hostSize.height * screenScale).rounded(.up)
        guard screenScale > 0, width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        window = CGRect(x: 0, y: 0, width: width, height: height)
        placement = CGAffineTransform(scaleX: 1 / screenScale, y: 1 / screenScale).concatenating(hostToCanvas)
    }

    /// The bytes one surface of this window holds, 4 a pixel.
    var surfaceBytes: Int { Int(window.width) * Int(window.height) * 4 }

    /// Canvas points per surface pixel: above 1 the draw shrinks the canvas, below 1 it magnifies.
    var canvasPointsPerPixel: CGFloat { sqrt(abs(placement.a * placement.d - placement.b * placement.c)) }

    /// Draws `image` — the whole canvas at whatever resolution it was made — into a UIKit context
    /// whose origin is the window's top-left (`WindowSurfaceView`'s draw), the canvas filled with
    /// `backdrop` first when there is one: the bake carries the paper but not what is behind it, and
    /// the surface is cleared between frames. A layer's picture has no backdrop.
    ///
    /// Shrinking samples a filtered neighbourhood so thin ink survives; magnifying stays crisp, as
    /// the hosts' nearest-neighbour filter keeps it, unless `smoothWhenMagnified` — the onion skin's
    /// soft ghost, which may be made well below canvas resolution (`OnionSkinBudget`). `clip`'s alpha,
    /// over the same canvas, cuts the picture (the onion skin's `OnionSkinClip`).
    func draw(_ image: CGImage, canvasSize: CGSize, backdrop: UIColor?, smoothWhenMagnified: Bool = false,
              clip: CGImage? = nil, in cg: CGContext) {
        guard placement.a * placement.d - placement.b * placement.c != 0 else { return }
        cg.saveGState()
        cg.concatenate(placement.inverted())
        let canvas = CGRect(origin: .zero, size: canvasSize)
        if let backdrop {
            backdrop.setFill()
            cg.fill(canvas)
        }
        let imagePixelsPerPixel = canvasPointsPerPixel * CGFloat(image.width) / max(1, canvasSize.width)
        cg.interpolationQuality = imagePixelsPerPixel > 1 ? .medium : (smoothWhenMagnified ? .low : .none)
        UIImage(cgImage: image, scale: 1, orientation: .up).draw(in: canvas)
        if let clip {
            UIImage(cgImage: clip, scale: 1, orientation: .up).draw(in: canvas, blendMode: .destinationIn, alpha: 1)
        }
        cg.restoreGState()
    }
}
