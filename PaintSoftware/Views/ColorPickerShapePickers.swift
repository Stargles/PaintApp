import SwiftUI

/// The gesture areas for TODO (73)'s four picker types — `HueRing` (Disc/Triangle/Square tabs all
/// share it) plus one shape each: `SaturationBrightnessSquare` (today's, factored out unchanged),
/// `SaturationBrightnessDisc`, `HSLTriangle`. Every shape here writes into `ColorPickerPanel`'s own
/// `hue`/`saturation`/`brightness` (HSB) state via bindings — there is no second copy of the colour
/// anywhere in this file, per the brief: each shape is a pure view over the one state the panel owns.
///
/// All four are fixed-size (`diameter`/`size` passed in) rather than `GeometryReader`-sized, so the
/// panel controls layout and a drag's normalized offset means the same thing in every XCUITest.

// MARK: - Hue ring

/// An annulus (outer circle minus a concentric inner circle) — `HueRing`'s hit-test region, drawn
/// with the even-odd fill rule so the inner circle is genuinely a hole rather than doubly-wound
/// (both `addEllipse` calls wind the same direction, so under the default non-zero rule the "hole"
/// would still count as inside).
///
/// **Why this exists at all, rather than `HueRing` just using `Circle()` for its `contentShape` (the
/// whole disc).** The Disc/Square/Triangle tabs each centre a *second*, smaller shape inside the same
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
/// `ColorMath.hueRingAngle`/`hueForRingTouch` are the ring's math (0 at top, clockwise).
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
                    AngularGradient(gradient: Gradient(colors: Self.spectrum), center: .center),
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
        let x = Double(diameter) / 2 + sin(angle) * radius
        let y = Double(diameter) / 2 - cos(angle) * radius
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

// MARK: - Saturation/brightness disc (Disc tab — Procreate's)

/// The same saturation/brightness pairing the square offers, rendered (and picked) inside a circle
/// instead — `ColorMath.squareToDisc`/`discToSquare` is what makes that more than a cosmetic crop:
/// every corner of the square (including full saturation *and* full brightness together) still
/// lands somewhere on the disc's edge, just redistributed around it by angle, so the disc loses none
/// of the square's range.
///
/// **Rendered with `Canvas`, not a gradient.** `LinearGradient`/`RadialGradient` can't express the
/// disc<->square remap, and drawing a plain square gradient cropped to a circle would show a colour
/// at the touch point that disagrees with what `discToSquare` computes there — the dot would sit on
/// top of the wrong swatch. The grid is coarse (28 cells across) because it only has to look like a
/// smooth disc from an arm's length away, not be a pixel-accurate colour picker in its own right —
/// the marker (not the fill) is what the dot is actually checked against.
struct SaturationBrightnessDisc: View {
    @Binding var saturation: Double
    @Binding var brightness: Double
    var hue: Double
    var diameter: CGFloat
    var accessibilityID: String = "colorPanel.disc"
    var onChanged: () -> Void = {}

    private static let gridSize = 28

    var body: some View {
        ZStack {
            Canvas { context, size in
                let cell = size.width / CGFloat(Self.gridSize)
                for row in 0..<Self.gridSize {
                    for col in 0..<Self.gridSize {
                        let localX = (Double(col) + 0.5) / Double(Self.gridSize) * 2 - 1
                        let localY = (Double(row) + 0.5) / Double(Self.gridSize) * 2 - 1
                        guard localX * localX + localY * localY <= 1 else { continue }
                        let square = ColorMath.discToSquare(x: localX, y: localY)
                        let s = min(max((square.u + 1) / 2, 0), 1)
                        let b = min(max(1 - (square.v + 1) / 2, 0), 1)
                        let rgb = ColorMath.hsbToRGB(h: hue, s: s, v: b)
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell,
                                          width: cell + 0.75, height: cell + 0.75)
                        context.fill(Path(rect), with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))
                    }
                }
            }
            .clipShape(Circle())

            marker
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var localX = Double(value.location.x - diameter / 2) / Double(diameter / 2)
                    var localY = Double(value.location.y - diameter / 2) / Double(diameter / 2)
                    let r = (localX * localX + localY * localY).squareRoot()
                    if r > 1, r > 0 { localX /= r; localY /= r }
                    let square = ColorMath.discToSquare(x: localX, y: localY)
                    saturation = min(max((square.u + 1) / 2, 0), 1)
                    brightness = min(max(1 - (square.v + 1) / 2, 0), 1)
                    onChanged()
                }
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private var marker: some View {
        let u = saturation * 2 - 1
        let v = (1 - brightness) * 2 - 1
        let point = ColorMath.squareToDisc(u: u, v: v)
        let x = (point.x + 1) / 2 * Double(diameter)
        let y = (point.y + 1) / 2 * Double(diameter)
        return Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Circle().fill(Color.fromHSBA(h: hue, s: saturation, b: brightness, a: 1)))
            .frame(width: 18, height: 18)
            .position(x: CGFloat(x), y: CGFloat(y))
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
/// **Saturation/lightness, not saturation/brightness.** The Disc and Square tabs share the panel's
/// `saturation`/`brightness` (HSB) state directly; this tab reads/writes through
/// `ColorMath.hslToRGB(h: hue, …)` / `rgbToHSB` using the *same* `hue` (never re-deriving it from the
/// round trip, which is how `ColorPickerPanel.applyHSBA` already avoids losing hue at an achromatic
/// point) — so the picker still has exactly one colour, just two ways to parameterize a plane of it.
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

    private static let gridSize = 26

    /// Local-frame angle the hue corner should point at, so the triangle visibly tracks the ring's
    /// own marker rather than sitting still while only its fill colour changes.
    private var rotation: Double { ColorMath.hueRingAngle(forHue: hue) }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let cell = size.width / CGFloat(Self.gridSize)
                for row in 0..<Self.gridSize {
                    for col in 0..<Self.gridSize {
                        let localX = (Double(col) + 0.5) / Double(Self.gridSize) * 2 - 1
                        let localY = (Double(row) + 0.5) / Double(Self.gridSize) * 2 - 1
                        let unrotated = rotate(x: localX, y: localY, by: -rotation)
                        guard ColorMath.triangleContains(x: unrotated.x, y: unrotated.y) else { continue }
                        let sl = ColorMath.triangleSaturationLightness(x: unrotated.x, y: unrotated.y)
                        let rgb = ColorMath.hslToRGB(h: hue, s: sl.s, l: sl.l)
                        let rect = CGRect(x: CGFloat((localX + 1) / 2) * size.width - cell / 2,
                                          y: CGFloat((localY + 1) / 2) * size.height - cell / 2,
                                          width: cell + 0.75, height: cell + 0.75)
                        context.fill(Path(rect), with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))
                    }
                }
            }
            .clipShape(Circle())

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
