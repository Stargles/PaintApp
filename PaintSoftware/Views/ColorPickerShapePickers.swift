import SwiftUI

/// The gesture areas for TODO (73)/(106)'s picker types — `HueRing` (Triangle/Square tabs share it)
/// plus one shape each: `SaturationBrightnessSquare` (today's, factored out unchanged), `HSLTriangle`
/// — and `OpacityBar`, TODO (106)'s checkerboard-and-thumb opacity control. Every shape here writes
/// into `ColorPickerPanel`'s own `hue`/`saturation`/`brightness`/`alpha` (HSB) state via bindings —
/// there is no second copy of the colour anywhere in this file, per the brief: each shape is a pure
/// view over the one state the panel owns.
///
/// All are fixed-size (`diameter`/`size`/`width` passed in) rather than `GeometryReader`-sized, so the
/// panel controls layout and a drag's normalized offset means the same thing in every XCUITest.
///
/// **The Disc picker type is gone (TODO (106)): "Remove the disc color picker."** Its shape
/// (`SaturationBrightnessDisc`) and `ColorMath`'s `squareToDisc`/`discToSquare` remap left with it —
/// nothing else read them.

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
    @Binding var hue: Double
    var diameter: CGFloat
    var thickness: CGFloat = 26
    var accessibilityID: String = "colorPanel.hueSlider"
    var onChanged: () -> Void = {}

    private static let spectrum: [Color] = ColorMath.hueRail().map {
        Color(red: $0.r, green: $0.g, blue: $0.b)
    }

    var body: some View {
        ZStack {
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
            marker
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
                    hue = ColorMath.hueForRingTouch(dx: dx, dy: dy)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private var marker: some View {
        let angle = ColorMath.hueRingAngle(forHue: hue)
        let radius = Double(diameter - thickness) / 2
        let x = Double(diameter) / 2 + cos(angle) * radius
        let y = Double(diameter) / 2 + sin(angle) * radius
        return Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(Color(hue: hue, saturation: 1, brightness: 1)))
            .frame(width: thickness - 6, height: thickness - 6)
            .position(x: CGFloat(x), y: CGFloat(y))
            .allowsHitTesting(false)
    }
}

// MARK: - Saturation/brightness square (Square tab — today's picker, unchanged maths)

struct SaturationBrightnessSquare: View {
    @Binding var saturation: Double
    @Binding var brightness: Double
    var hue: Double
    var size: CGFloat
    var accessibilityID: String = "colorPanel.svSquare"
    var onChanged: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hue: hue, saturation: 1, brightness: 1))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))

            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .background(Circle().fill(Color.fromHSBA(h: hue, s: saturation, b: brightness, a: 1)))
                .frame(width: 18, height: 18)
                .position(x: saturation * size, y: (1 - brightness) * size)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    saturation = min(max(value.location.x / size, 0), 1)
                    brightness = 1 - min(max(value.location.y / size, 0), 1)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
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
/// round trip, which is how `ColorPickerPanel.applyHSBA` already avoids losing hue at an achromatic
/// point) — so the picker still has exactly one colour, just two ways to parameterize a plane of it.
///
/// **The rotation is `ColorMath.triangleRotation`, not just the ring's own angle** — TODO (106)'s
/// "turned 90° clockwise" on top of tracking the marker, so the full-hue vertex points at the ring's
/// red at hue 0 instead of sitting at the top of the bounding box. See that function's doc comment
/// for the arithmetic; the view only applies it, identically for the shading and the marker, so the
/// two can never disagree about where the corner points.
struct HSLTriangle: View {
    /// Plain values, not `@Binding` — the panel's canonical state is HSB (`hue`/`saturation`/
    /// `brightness`), and `saturation`/`lightness` here are HSL, *derived* from it each render.
    /// A drag reports both together through `onChanged` rather than through two independent
    /// bindings, because the two are computed from one barycentric solve — writing them through
    /// separate `Binding` setters would apply one before the other existed, converting through a
    /// stale intermediate value on every tick.
    var saturation: Double
    var lightness: Double
    var hue: Double
    var diameter: CGFloat
    var accessibilityID: String = "colorPanel.triangle"
    var onChanged: (_ saturation: Double, _ lightness: Double) -> Void = { _, _ in }

    /// TODO (106): "the edges are very pixelated, not smooth" — the fix reads this to size the
    /// sampling grid against the display's actual pixel density rather than a fixed point count (see
    /// `sampleCount(for:)`), and the edge itself no longer depends on the grid at all (see
    /// `trianglePath(in:)`'s doc comment).
    @Environment(\.displayScale) private var displayScale

    private var rotation: Double { ColorMath.triangleRotation(forHue: hue) }

    var body: some View {
        ZStack {
            Canvas { context, size in
                // The true vector edge, clipped once before any fill — CoreGraphics antialiases a
                // path clip, which is what makes the boundary smooth regardless of how coarse the
                // shading grid below it is. This replaces the old per-cell `triangleContains` guard,
                // which drew a *staircase* of whole grid cells at the boundary instead: a cell was
                // either painted in full or skipped in full, so the edge was only ever as smooth as
                // one cell was small.
                context.clip(to: trianglePath(in: size))

                let count = Self.sampleCount(for: size.width, displayScale: displayScale)
                let cell = size.width / CGFloat(count)
                for row in 0..<count {
                    for col in 0..<count {
                        let localX = (Double(col) + 0.5) / Double(count) * 2 - 1
                        let localY = (Double(row) + 0.5) / Double(count) * 2 - 1
                        let unrotated = rotate(x: localX, y: localY, by: -rotation)
                        let sl = ColorMath.triangleSaturationLightness(x: unrotated.x, y: unrotated.y)
                        let rgb = ColorMath.hslToRGB(h: hue, s: sl.s, l: sl.l)
                        let rect = CGRect(x: CGFloat((localX + 1) / 2) * size.width - cell / 2,
                                          y: CGFloat((localY + 1) / 2) * size.height - cell / 2,
                                          width: cell + 0.75, height: cell + 0.75)
                        context.fill(Path(rect), with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))
                    }
                }
            }

            marker
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let localX = Double(value.location.x - diameter / 2) / Double(diameter / 2)
                    let localY = Double(value.location.y - diameter / 2) / Double(diameter / 2)
                    let unrotated = rotate(x: localX, y: localY, by: -rotation)
                    let sl = ColorMath.triangleSaturationLightness(x: unrotated.x, y: unrotated.y)
                    onChanged(sl.s, sl.l)
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }

    /// The exact triangle the shading is clipped to, built from the same three vertices and the same
    /// `rotation` the shading and the marker use, in this canvas's own point space — so the boundary
    /// CoreGraphics draws is the triangle the maths describes, not an approximation of it.
    private func trianglePath(in size: CGSize) -> Path {
        let corners = [ColorMath.trianglePureHueVertex, ColorMath.triangleWhiteVertex, ColorMath.triangleBlackVertex]
        var path = Path()
        for (index, corner) in corners.enumerated() {
            let rotated = rotate(x: corner.x, y: corner.y, by: rotation)
            let point = CGPoint(x: CGFloat((rotated.x + 1) / 2) * size.width,
                                 y: CGFloat((rotated.y + 1) / 2) * size.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Samples-per-axis for the shading grid, scaled by the display's own pixel density rather than
    /// fixed in points — the old constant (26, chosen with no reference to any display) is what made
    /// the shading itself a coarse mosaic independently of the edge; the edge is `trianglePath`'s
    /// job now, this is only the interior's. Clamped at both ends: 40 is the old grid's rough order
    /// of magnitude (a floor so a 1x display is never worse than before), 120 is enough that a finer
    /// grid stops being visible at arm's length and would only cost render time.
    private static func sampleCount(for widthPoints: CGFloat, displayScale: CGFloat) -> Int {
        min(120, max(40, Int((widthPoints * displayScale / 2).rounded())))
    }

    private var marker: some View {
        let local = ColorMath.trianglePosition(saturation: saturation, lightness: lightness)
        let rotated = rotate(x: local.x, y: local.y, by: rotation)
        let x = (rotated.x + 1) / 2 * Double(diameter)
        let y = (rotated.y + 1) / 2 * Double(diameter)
        let rgb = ColorMath.hslToRGB(h: hue, s: saturation, l: lightness)
        return Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))
            .frame(width: 18, height: 18)
            .position(x: CGFloat(x), y: CGFloat(y))
            .allowsHitTesting(false)
    }

    /// Rotates `(x, y)` by `angle` radians clockwise (screen/y-down convention, matching
    /// `ColorMath.hueRingAngle`) about the origin.
    private func rotate(x: Double, y: Double, by angle: Double) -> (x: Double, y: Double) {
        let c = cos(angle), s = sin(angle)
        return (x * c - y * s, x * s + y * c)
    }
}

// MARK: - Opacity bar (every tab — TODO (106))

/// A horizontal checkerboard-to-colour bar with a round drag thumb — TODO (106): *"The opacity
/// slider should also display the color like in the image"* — replacing the native `Slider` the
/// opacity row used before. Built as its own gesture view for the same reason `HueRing` and the
/// others are: a native `Slider` has no public track-styling API this app's deployment target can
/// use, so a control whose *track itself* has to carry a picture (a checkerboard fading into the
/// current colour) is built the way every other custom shape in this file already is.
///
/// **Fixed-width, not `GeometryReader`-sized**, for the same reason every other shape here is: a
/// drag's fraction of `width` has to mean the same screen distance in every XCUITest.
struct OpacityBar: View {
    @Binding var alpha: Double
    /// The picker's current colour at full alpha — the bar fades *into* this, not into whatever
    /// `alpha` currently is, or the gradient would be describing the colour it is drawn with rather
    /// than the colour dragging to 1 would produce.
    var color: Color
    var width: CGFloat
    var height: CGFloat = 22
    var accessibilityID: String = "colorPanel.opacitySlider"
    var onChanged: () -> Void = {}

    var body: some View {
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

            thumb
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    alpha = min(max(Double(value.location.x / width), 0), 1)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private var thumb: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(color.opacity(alpha)))
            .frame(width: height + 6, height: height + 6)
            .position(x: CGFloat(alpha) * width, y: height / 2)
            .allowsHitTesting(false)
    }
}
