import SwiftUI
import Observation

/// **The colour picker's one colour — hue, saturation, brightness, alpha — kept where a drag can move it
/// without moving the picker.**
///
/// **Why a class of its own, observed per property.** A write to a `@State` re-evaluates the whole body of
/// the view that owns it, so a colour held as `@State` on the panel would rebuild the entire panel — the
/// header, the tab bar, the Recent grid and the whole palette (thirty-odd swatches, each with its own
/// context-menu presentation and long-press) — on every tick of a drag on the ring, the square, the
/// triangle or the opacity bar. What a tick costs either way is PERFORMANCE.md §31's.
///
/// This is an `@Observable` class so that a view which reads `hue` is re-evaluated when `hue` moves and
/// no other view is. The panel holds it and reads nothing from it; each shape, the swatch beside the
/// header, the hex field and the opacity row read what they draw. A tick re-evaluates those and the
/// rest of the picker stands still.
///
/// It is also where the colour's rules live, so they are testable without a view: the one funnel an
/// inbound colour passes through (`load`) and the triangle's write path (`setHSL`).
@MainActor
@Observable
final class PickerColor {
    var hue: Double = 0
    var saturation: Double = 0
    var brightness: Double = 0
    var alpha: Double = 1

    /// The colour as the host receives it.
    var color: Color {
        Color.fromHSBA(h: hue, s: saturation, b: brightness, a: alpha)
    }

    /// The same colour at full alpha — what the opacity bar fades *into*, and what its thumb is filled with
    /// at the current alpha.
    var opaqueColor: Color {
        Color.fromHSBA(h: hue, s: saturation, b: brightness, a: 1)
    }

    /// Uppercase hex of `color` (`Color.hexString`'s own spelling).
    var hexString: String { color.hexString }

    /// The Triangle tab's saturation and lightness, **derived** from the one stored colour — never a
    /// second pair kept beside it.
    var hsl: (s: Double, l: Double) {
        let rgb = ColorMath.hsbToRGB(h: hue, s: saturation, v: brightness)
        let hsl = ColorMath.rgbToHSL(r: rgb.r, g: rgb.g, b: rgb.b)
        return (hsl.s, hsl.l)
    }

    /// **The single funnel every inbound colour passes through** — the panel opening, the host moving
    /// the colour underneath it, a hex string, a swatch.
    ///
    /// Keeps the *previous* hue when the incoming colour is achromatic (saturation ~ 0) instead of
    /// snapping it to 0/red: `ColorMath.rgbToHSB` returns hue 0 for any r == g == b colour, since hue is
    /// genuinely undefined there, and taking it at its word would throw the ring's marker to red every
    /// time the artist picked a grey. Alpha is forced to 1 when the host does not take one.
    func load(_ hsba: (h: Double, s: Double, b: Double, a: Double), supportsOpacity: Bool) {
        if hsba.s > 0.0001 {
            hue = hsba.h
        }
        saturation = hsba.s
        brightness = hsba.b
        alpha = supportsOpacity ? hsba.a : 1
    }

    func load(_ color: Color, supportsOpacity: Bool) {
        load(color.hsbaComponents, supportsOpacity: supportsOpacity)
    }

    /// The Triangle tab's write path: HSL saturation/lightness at the stored `hue` -> RGB -> HSB, taking
    /// only the resulting saturation and brightness and leaving `hue` alone. Re-deriving the hue from
    /// the round trip instead (as `load` must, for an *external* colour of unknown history) would risk
    /// exactly the achromatic hue loss `load` guards against — avoidable here for free, because this
    /// tab already knows the hue it started from.
    func setHSL(saturation s: Double, lightness l: Double) {
        let rgb = ColorMath.hslToRGB(h: hue, s: s, l: l)
        let hsb = ColorMath.rgbToHSB(r: rgb.r, g: rgb.g, b: rgb.b)
        saturation = hsb.s
        brightness = hsb.v
    }
}
