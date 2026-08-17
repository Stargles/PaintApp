import CoreGraphics

/// The eyedropper's two pure halves: which pixel a canvas-space point names, and what colour a
/// premultiplied RGBA buffer holds there.
///
/// **Why this is a type and not two lines inside the gesture handler.** Both halves are exactly the
/// kind of thing that is wrong in ways a screenshot cannot show — an off-by-one at the far edge, a
/// forgotten un-premultiply that darkens every semi-transparent pick, a tap in the void reading the
/// nearest edge pixel instead of nothing. Living here, in a CoreGraphics-only file with no `View` and
/// no `App`, is what lets them join the "App sources shared with PaintSoftwareUITests" group and be
/// swept headlessly in the fast tier rather than probed through a 22-second XCUITest. Same
/// arrangement, and same reason, as `StrokeGeometry.swift` and `TouchTypeResolution.swift`.
///
/// **What is deliberately *not* here: the view→canvas mapping.** There is no arithmetic in this file
/// for zoom, pan or rotation, because the app already has that machinery and it is UIKit's. The
/// canvas container's bounds are set to `canvasSize` exactly (`CanvasView.applyTransform`), and the
/// container carries the zoom/rotation as its `transform`, so `recognizer.location(in: container)`
/// *is* the canvas-pixel coordinate at any zoom and any rotation — UIKit inverts the transform on the
/// way. `handleFillPress` has relied on that since the fill tool was written. What this file takes is
/// the point that call already returns.
enum Eyedropper {

    /// The pixel containing `point`, which is in canvas space (top-left origin, one unit per pixel),
    /// or nil when the point is outside the canvas.
    ///
    /// **Outside is nil, not clamped**, and that is a deliberate divergence from
    /// `beginInteractiveFill`, which clamps the same coordinate into range. The two tools are asking
    /// different questions: a fill needs *a* seed and the nearest legal one is a defensible answer,
    /// whereas an eyedropper is asking "what colour is under my finger", and out past the paper's
    /// edge the honest answer is that there is no colour there. Clamping would hand back the edge
    /// pixel — a colour the artist can see they did not touch — which is worse than nothing happening,
    /// because nothing happening is legible and a wrong pick is not.
    ///
    /// The canvas is zoomed out inside a black host far more often than not, so the void is a large
    /// and easily-hit target rather than a corner case.
    static func pixel(at point: CGPoint, canvasSize: CGSize) -> (x: Int, y: Int)? {
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }
        // `floor`, so the pixel is the one the point is *inside*. A point at exactly 1.0 belongs to
        // pixel 1, and a point at 1023.9 on a 1024-wide canvas belongs to pixel 1023 — which is why
        // the upper test below is `>=` against the count rather than `>` against the last index.
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return (x, y)
    }

    /// One sampled colour: straight (un-premultiplied) components, each 0...1.
    struct Sample: Equatable {
        var r: Double
        var g: Double
        var b: Double
        /// The alpha the composite held at that pixel. Reported rather than folded into `r`/`g`/`b`
        /// so the caller decides what to do with it — see `CanvasManager.pickColor`, which keeps the
        /// brush colour opaque and leaves transparency to the `brushOpacity` slider.
        var a: Double
    }

    /// The colour at `(x, y)` of a premultiplied-last, 8-bit, `width * height * 4` RGBA buffer with
    /// row 0 at the top — the layout `Compositor.premultipliedBytes` produces and the whole engine
    /// speaks.
    ///
    /// **Returns nil for a fully transparent pixel**, and that is arithmetic before it is policy:
    /// premultiplied components at alpha 0 are all 0, so the straight colour is 0/0 — undefined, not
    /// black. A picker that returned black there would silently hand the artist a colour that was
    /// never on the canvas every time they tapped an empty patch with the paper hidden.
    ///
    /// Un-premultiplying is clamped at 1: rounding in an 8-bit premultiplied buffer can leave a
    /// component one step above its own alpha (say 8 over an alpha of 7), which divides out to just
    /// over 1 and would otherwise escape as an out-of-range colour.
    static func color(inPremultipliedRGBA bytes: [UInt8], width: Int, height: Int,
                      x: Int, y: Int) -> Sample? {
        guard width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        guard bytes.count >= offset + 4 else { return nil }

        let a = Double(bytes[offset + 3]) / 255
        guard a > 0 else { return nil }
        func straight(_ premultiplied: UInt8) -> Double {
            min(1, (Double(premultiplied) / 255) / a)
        }
        return Sample(r: straight(bytes[offset]), g: straight(bytes[offset + 1]),
                      b: straight(bytes[offset + 2]), a: a)
    }

    /// `pixel(at:canvasSize:)` and `color(inPremultipliedRGBA:…)` in one call — the whole sample, from
    /// the coordinate the gesture handed over to the colour the brush takes. Nil for a tap off the
    /// canvas or onto a fully transparent pixel, which the caller reports the same way: nothing to
    /// pick.
    static func sample(at point: CGPoint, canvasSize: CGSize,
                       premultipliedRGBA bytes: [UInt8]) -> Sample? {
        guard let pixel = pixel(at: point, canvasSize: canvasSize) else { return nil }
        return color(inPremultipliedRGBA: bytes,
                     width: Int(canvasSize.width.rounded()), height: Int(canvasSize.height.rounded()),
                     x: pixel.x, y: pixel.y)
    }
}
