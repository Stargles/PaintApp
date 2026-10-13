import SwiftUI

/// The gesture areas for TODO (73)/(106)'s picker types — `HueRing` (Triangle/Square tabs share it)
/// plus one shape each: `SaturationBrightnessSquare`, `HSLTriangle` — and `OpacityBar`, the
/// checkerboard-and-thumb opacity control. Every shape here writes into `ColorPickerPanel`'s
/// `PickerColor` — there is no second copy of the colour anywhere in this file: each shape is a pure
/// view over the one model the panel owns.
///
/// **A shape is two things, and they are separate views.** What it *draws* depends on the colour and
/// changes every tick of a drag (the marker, the hue-tinted fill); what it *is* does not (the ring's
/// band, the gesture, the frame). The drawing views read the model in their own bodies and nothing else
/// does, so a tick re-evaluates the marker and leaves the gesture's owner, and everything around the
/// shape, where it stands (`PickerColor`'s header has the cost that spares).
///
/// All are fixed-size (`diameter`/`size`/`width` passed in) rather than `GeometryReader`-sized, so the
/// panel controls layout and a drag's normalized offset means the same thing in every XCUITest.

// MARK: - Hue ring

/// An annulus (outer circle minus a concentric inner circle) — `HueRing`'s hit-test region, drawn
/// with the even-odd fill rule so the inner circle is genuinely a hole rather than doubly-wound
/// (both `addEllipse` calls wind the same direction, so under the default non-zero rule the "hole"
/// would still count as inside).
///
/// **Why this exists at all, rather than `HueRing` just using `Circle()` for its `contentShape` (the
/// whole disc).** The Square/Triangle tabs each centre a *second*, smaller shape inside the same
/// bounding box as the ring. A ring whose hit area is the *whole* disc overlaps that inner shape's
/// own hit area everywhere the inner shape exists — and since a drag's touch-down decides which
/// gesture owns the whole gesture, a drag begun at the ring's own centre (which is inside the inner
/// shape's much larger hit area at that point) silently becomes a drag on the *inner shape* instead,
/// never moving the hue at all. Restricting the ring's hit area to its own visible band is what makes
/// "drag on the ring turns hue; drag inside the shape picks" (item 1) actually true rather than only
/// true when the two happen not to overlap.
private struct RingHitArea: Shape {
    var thickness: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        path.addEllipse(in: rect.insetBy(dx: thickness, dy: thickness))
        return path
    }
}

/// The hue selector every ring-based tab shares. Reuses `colorPanel.hueSlider`'s identifier even
/// though the control is no longer a bar — the string is what tests look up, and
/// `ColorMath.hueRingAngle`/`hueForRingTouch` are the ring's math (0 at 3 o'clock, clockwise — see
/// their own doc comments for TODO (106)'s phase fix).
struct HueRing: View {
    let model: PickerColor
    var diameter: CGFloat
    var thickness: CGFloat = 26
    var accessibilityID: String = "colorPanel.hueSlider"
    var onChanged: () -> Void = {}

    var body: some View {
        ZStack {
            HueRingBand(thickness: thickness)
            HueRingMarker(model: model, diameter: diameter, thickness: thickness)
        }
        .frame(width: diameter, height: diameter)
        // Only the ring's own band, not the whole disc — see `RingHitArea`'s doc comment for why
        // that is load-bearing rather than cosmetic.
        .contentShape(RingHitArea(thickness: thickness), eoFill: true)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = Double(value.location.x - diameter / 2)
                    let dy = Double(value.location.y - diameter / 2)
                    model.hue = ColorMath.hueForRingTouch(dx: dx, dy: dy)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }
}

/// The ring's spectrum. Reads nothing, so a drag never re-evaluates it.
private struct HueRingBand: View {
    var thickness: CGFloat

    private static let spectrum: [Color] = ColorMath.hueRail().map {
        Color(red: $0.r, green: $0.g, blue: $0.b)
    }

    var body: some View {
        Circle()
            .strokeBorder(
                // Explicit rather than relying on the default: this **is** the "one convention"
                // `ColorMath.hueRingAngle`'s doc comment names — 0° at 3 o'clock, sweeping
                // clockwise through `spectrum`'s hue-0-to-1 order — stated here instead of left
                // implicit, so the drawing, the marker and the drag handler are reading the same
                // fact rather than two of them assuming SwiftUI's default matches the third.
                AngularGradient(gradient: Gradient(colors: Self.spectrum), center: .center,
                                 startAngle: .degrees(0), endAngle: .degrees(360)),
                lineWidth: thickness
            )
    }
}

/// The ring's marker: where the hue sits on the band, in the hue's own colour.
private struct HueRingMarker: View {
    let model: PickerColor
    var diameter: CGFloat
    var thickness: CGFloat

    var body: some View {
        let hue = model.hue
        let angle = ColorMath.hueRingAngle(forHue: hue)
        let radius = Double(diameter - thickness) / 2
        let x = Double(diameter) / 2 + cos(angle) * radius
        let y = Double(diameter) / 2 + sin(angle) * radius
        Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(Color(hue: hue, saturation: 1, brightness: 1)))
            .frame(width: thickness - 6, height: thickness - 6)
            .position(x: CGFloat(x), y: CGFloat(y))
            .allowsHitTesting(false)
    }
}

// MARK: - Saturation/brightness square (Square tab)

struct SaturationBrightnessSquare: View {
    let model: PickerColor
    var size: CGFloat
    var accessibilityID: String = "colorPanel.svSquare"
    var onChanged: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            SquareShading(model: model)
            SquareMarker(model: model, size: size)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    model.saturation = min(max(value.location.x / size, 0), 1)
                    model.brightness = 1 - min(max(value.location.y / size, 0), 1)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }
}

/// The square's fill: the hue at full strength, white fading in from the left, black from the bottom.
/// Only the hue moves it.
private struct SquareShading: View {
    let model: PickerColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hue: model.hue, saturation: 1, brightness: 1))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))
        }
    }
}

private struct SquareMarker: View {
    let model: PickerColor
    var size: CGFloat

    var body: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(model.opaqueColor))
            .frame(width: 18, height: 18)
            .position(x: model.saturation * size, y: (1 - model.brightness) * size)
            .allowsHitTesting(false)
    }
}

// MARK: - HSL triangle (Triangle tab — Paint Tool SAI / Krita's)

/// A hue ring with an HSL triangle inside: one corner white, one black, one the current hue at full
/// saturation. `ColorMath.trianglePosition`/`triangleSaturationLightness` are the maths (barycentric
/// weights against the three corners, derived from HSL's own definition — see that file); this view
/// only draws the triangle (rotated so its hue corner tracks the ring) and turns a drag into a
/// local-frame point for that maths to read.
///
/// **Saturation/lightness, not saturation/brightness.** The Square tab shares the panel's
/// `saturation`/`brightness` (HSB) state directly; this tab reads/writes through
/// `ColorMath.hslToRGB(h: hue, …)` / `rgbToHSB` using the *same* `hue` (never re-deriving it from the
/// round trip, which is how `PickerColor.load` already avoids losing hue at an achromatic point) — so
/// the picker still has exactly one colour, just two ways to parameterize a plane of it
/// (`PickerColor.hsl`, `PickerColor.setHSL`).
///
/// **The rotation is `ColorMath.triangleRotation`, not just the ring's own angle** — TODO (106)'s
/// "turned 90° clockwise" on top of tracking the marker, so the full-hue vertex points at the ring's
/// red at hue 0 instead of sitting at the top of the bounding box. See that function's doc comment
/// for the arithmetic; the view applies it, identically for the shading and the marker, so the
/// two can never disagree about where the corner points.
struct HSLTriangle: View {
    let model: PickerColor
    var diameter: CGFloat
    var accessibilityID: String = "colorPanel.triangle"
    var onChanged: () -> Void = {}

    var body: some View {
        ZStack {
            TriangleShading(model: model, diameter: diameter)
            TriangleMarker(model: model, diameter: diameter)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let localX = Double(value.location.x - diameter / 2) / Double(diameter / 2)
                    let localY = Double(value.location.y - diameter / 2) / Double(diameter / 2)
                    let unrotated = rotated(x: localX, y: localY, by: -ColorMath.triangleRotation(forHue: model.hue))
                    let sl = ColorMath.triangleSaturationLightness(x: unrotated.x, y: unrotated.y)
                    model.setHSL(saturation: sl.s, lightness: sl.l)
                    onChanged()
                }
        )
        // One element for the whole triangle: its bitmap is decorative and its marker is a shape, so
        // without this the identifier has no leaf to land on.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Rotates `(x, y)` by `angle` radians clockwise (screen/y-down convention, matching
/// `ColorMath.hueRingAngle`) about the origin.
private func rotated(x: Double, y: Double, by angle: Double) -> (x: Double, y: Double) {
    let c = cos(angle), s = sin(angle)
    return (x * c - y * s, x * s + y * c)
}

/// **The triangle's shading — a small bitmap, clipped by the true vector triangle, turned by the GPU.**
/// The colour at every point of it is the corner blend `ColorMath.triangleShadingPixels` computes, and
/// only the hue changes it: a tick on the triangle moves the marker and leaves this alone, and a tick
/// on the ring renders one `side` × `side` bitmap.
///
/// **The edge is the vector path's, not the bitmap's.** The bitmap is smooth (a gradient survives being
/// stretched), so it is drawn small and the clip — a path CoreGraphics antialiases — is what makes the
/// boundary crisp. TODO (106): *"the edges are very pixelated"*; `ColorPickerUITests.
/// testTheTrianglesShadingEdgeIsAntialiasedNotJagged` reads it off the screen.
private struct TriangleShading: View {
    let model: PickerColor
    var diameter: CGFloat

    /// Samples a side. 128 is a cell under two points of the 240-point triangle: finer than a gradient
    /// can show, and 16,384 pixels a hue tick.
    private static let side = 128

    var body: some View {
        let hue = model.hue
        Image(decorative: Self.bitmap(hue: hue), scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: diameter, height: diameter)
            .clipShape(TriangleOutline())
            .rotationEffect(.radians(ColorMath.triangleRotation(forHue: hue)))
            .allowsHitTesting(false)
    }

    private static func bitmap(hue: Double) -> CGImage {
        PlaybackTrace.span(.pickerShading) {
            let pixels = ColorMath.triangleShadingPixels(hue: hue, side: side)
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true,
                                      intent: .defaultIntent)
            else { preconditionFailure("the triangle's \(side) x \(side) shading bitmap was refused") }
            return image
        }
    }
}

/// The exact triangle, in its own unrotated frame, built from the same three vertices
/// `ColorMath.trianglePosition` and `triangleSaturationLightness` use — so the boundary CoreGraphics
/// draws is the triangle the maths describes, not an approximation of it.
private struct TriangleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let corners = [ColorMath.trianglePureHueVertex, ColorMath.triangleWhiteVertex, ColorMath.triangleBlackVertex]
        var path = Path()
        for (index, corner) in corners.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat((corner.x + 1) / 2) * rect.width,
                                y: rect.minY + CGFloat((corner.y + 1) / 2) * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct TriangleMarker: View {
    let model: PickerColor
    var diameter: CGFloat

    var body: some View {
        let hue = model.hue
        let (saturation, lightness) = model.hsl
        let local = ColorMath.trianglePosition(saturation: saturation, lightness: lightness)
        let turned = rotated(x: local.x, y: local.y, by: ColorMath.triangleRotation(forHue: hue))
        let x = (turned.x + 1) / 2 * Double(diameter)
        let y = (turned.y + 1) / 2 * Double(diameter)
        let rgb = ColorMath.hslToRGB(h: hue, s: saturation, l: lightness)
        Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))
            .frame(width: 18, height: 18)
            .position(x: CGFloat(x), y: CGFloat(y))
            .allowsHitTesting(false)
    }
}

// MARK: - Opacity bar (every tab — TODO (106))

/// A horizontal checkerboard-to-colour bar with a round drag thumb — TODO (106): *"The opacity
/// slider should also display the color like in the image."* Built as its own gesture view for the
/// same reason `HueRing` and the others are: a native `Slider` has no public track-styling API this
/// app's deployment target can use, so a control whose *track itself* has to carry a picture (a
/// checkerboard fading into the current colour) is built the way every other custom shape in this file
/// already is.
///
/// **Fixed-width, not `GeometryReader`-sized**, for the same reason every other shape here is: a
/// drag's fraction of `width` has to mean the same screen distance in every XCUITest.
struct OpacityBar: View {
    let model: PickerColor
    var width: CGFloat
    var height: CGFloat = 22
    var accessibilityID: String = "colorPanel.opacitySlider"
    var onChanged: () -> Void = {}

    var body: some View {
        // The picker's current colour at full alpha — the bar fades *into* this, not into whatever
        // `alpha` currently is, or the gradient would be describing the colour it is drawn with rather
        // than the colour dragging to 1 would produce.
        let color = model.opaqueColor
        ZStack(alignment: .leading) {
            // The track only — clipped to its own rounded-rect shape so the checkerboard doesn't
            // spill past rounded corners. The thumb is a *sibling* in the outer `ZStack` below,
            // deliberately outside this clip: it is taller than `height` on purpose (a thumb flush
            // with a thin bar is hard to grab), and clipping it to the track's own rect would crop
            // its top and bottom into a lens shape instead of leaving it a full circle.
            ZStack(alignment: .leading) {
                CheckerboardPattern()
                LinearGradient(colors: [color.opacity(0), color.opacity(1)], startPoint: .leading, endPoint: .trailing)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
            .overlay(RoundedRectangle(cornerRadius: height / 2).stroke(Color.white.opacity(0.25), lineWidth: 1))

            thumb(color: color)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    model.alpha = min(max(Double(value.location.x / width), 0), 1)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private func thumb(color: Color) -> some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(color.opacity(model.alpha)))
            .frame(width: height + 6, height: height + 6)
            .position(x: CGFloat(model.alpha) * width, y: height / 2)
            .allowsHitTesting(false)
    }
}
