import IOSurface
import UIKit

/// **Where a live stream frame reaches the screen** — STREAM.md §5.3, TODO (97).
///
/// One per stream element a layer host is showing, sized to the element's window
/// (`VectorCanvas.streamWindow`) and frame-positioned over `StrokeCanvasView.imageView` in canvas
/// points, the way the scratch is positioned at a stroke's window. Its layer's contents is an
/// `IOSurface` — one of two this view owns and alternates between. A frame is drawn into the back
/// surface off the main thread and presenting it is one `contents` assignment of an object the render
/// server already has mapped: **nothing is copied per frame, and nothing new is handed to Core
/// Animation per frame.** That is the property the old path lacked. It presented a frame by
/// invalidating the layer's memo and re-rasterizing the canvas, so every frame was a canvas-sized
/// allocation, a canvas-sized blit, and a fresh canvas-sized `CGImage` on `imageView` for Core
/// Animation to copy to the render server — thirty times a second, for as long as the laptop was
/// on. On the owner's iPad the render server reached its 1850 MB limit and was killed, which is a
/// black screen and a respring: the four `backboardd` jetsam events of 2026-09-14/15 behind TODO (97).
///
/// **Two surfaces, not one**, so the render server never samples the pixels being written: the
/// front surface is what is on screen while the back one is drawn, and they swap at the present.
/// **One draw in flight at a time**, and a frame that arrives during one is dropped rather than
/// queued — the element holds only its newest frame, so the next draw shows the newest picture
/// whatever was skipped. The window is cleared before each draw because the element's quad can
/// change between frames (a nudge in the Move box) and the pixels outside the new quad must be
/// transparent, not last frame's.
final class StreamSurfaceView: UIView {

    private struct Surface {
        let surface: IOSurface
        let context: CGContext
    }

    /// Both surfaces, once `size(for:)` has made them; empty before the first present.
    private var surfaces: [Surface] = []
    private var back = 0
    private var drawInFlight = false

    /// How many frames have been presented — for tests, which spin the run loop until it moves.
    private(set) var presentedCount = 0
    /// The window the surfaces are sized to, in canvas points; `.null` before the first present.
    private(set) var surfaceWindow = CGRect.null

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
        // One canvas point is one surface pixel, exactly as `imageView` shows a canvas-sized bitmap
        // in a canvas-sized frame; the same sample filters as its siblings, for the same crispness
        // contract (`StrokeCanvasView.init`).
        layer.contentsScale = 1
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .trilinear
        // Placed by `position` at the window's own origin, so a canvas `transform` can be applied
        // about the canvas origin rather than about the view's centre — see `present`.
        layer.anchorPoint = .zero
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// **Draws one frame off the main thread and presents it.**
    ///
    /// `window` is the element's rectangle in canvas points; `placement` the canvas's own affine
    /// (`VectorCanvas.transform`), which the picture is drawn *before* and this layer applies.
    /// `draw` runs on `queue` with a UIKit context whose origin is the window's top-left corner and
    /// returns the rectangle it actually drew — `VectorCanvas.drawStreamWindow`'s answer — or nil
    /// to abandon; a rectangle other than `window` means the element moved between the two reads,
    /// and the frame is dropped rather than shown in the wrong place. The next present sizes again.
    ///
    /// Returns false when a draw is already in flight and this frame was dropped.
    @discardableResult
    func present(window: CGRect, placement: CGAffineTransform, on queue: DispatchQueue,
                 draw: @escaping (CGContext) -> CGRect?) -> Bool {
        guard !drawInFlight else { return false }
        size(for: window)
        guard surfaces.count == 2 else { return false }
        drawInFlight = true
        let target = surfaces[back]
        queue.async { [weak self] in
            _ = target.surface.lock(options: [], seed: nil)
            let cg = target.context
            cg.clear(CGRect(origin: .zero, size: window.size))
            UIGraphicsPushContext(cg)
            let drawn = draw(cg)
            UIGraphicsPopContext()
            _ = target.surface.unlock(options: [], seed: nil)
            DispatchQueue.main.async {
                guard let self else { return }
                self.drawInFlight = false
                guard drawn == window, self.surfaces.count == 2, self.surfaceWindow == window else { return }
                self.layer.contents = target.surface
                self.layer.bounds = CGRect(origin: .zero, size: window.size)
                self.layer.position = window.origin.applying(placement)
                self.layer.setAffineTransform(CGAffineTransform(a: placement.a, b: placement.b,
                                                                c: placement.c, d: placement.d,
                                                                tx: 0, ty: 0))
                self.isHidden = false
                self.back = 1 - self.back
                self.presentedCount += 1
            }
        }
        return true
    }

    /// Makes the two surfaces for `window`, or keeps the ones already that size. A window of a
    /// different size drops both — the old pixels are the wrong shape — and hides the view until
    /// the first frame of the new size lands, so the base underneath shows meanwhile.
    private func size(for window: CGRect) {
        guard surfaceWindow.size != window.size || surfaces.count != 2 else {
            surfaceWindow = window
            return
        }
        surfaces = []
        isHidden = true
        layer.contents = nil
        surfaceWindow = window
        let width = Int(window.width), height = Int(window.height)
        guard width > 0, height > 0 else { return }
        for _ in 0..<2 {
            guard let surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .pixelFormat: kCVPixelFormatType_32BGRA,
            ]) else { return }
            // The same 8-bit premultiplied BGRA every raster tier renders as; the context is made
            // once over the surface's own memory, flipped so it is the UIKit context
            // `VectorCanvas.drawStreamWindow` expects (`UIImage.draw(in:)` in the placed arms).
            guard let context = CGContext(data: surface.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            surfaces.append(Surface(surface: surface, context: context))
        }
    }
}
