import SwiftUI
import UIKit

/// Bridges SwiftUI `Color` to concrete RGBA/UIColor values. All the actual color *math* — RGB<->HSB,
/// hex parsing/formatting — lives in `ColorMath` (see ColorMath.swift), which has no UIKit dependency
/// and is unit-tested without a simulator. This file's only job is turning a `Color` into components
/// reliably, which is where the historical "semantic color" bugs actually lived.
///
/// Root cause of those bugs: `UIColor(someColor)` can hand back a *dynamic* color — one whose RGBA
/// values depend on whichever `UITraitCollection` (in particular, light/dark appearance) happens to
/// be current at the moment it's resolved, rather than a single fixed value. Calling
/// `getRed(_:green:_:blue:_:alpha:)` directly on a color like that is only reliably defined *after*
/// it's been resolved against a concrete trait collection; called on the still-dynamic value, it can
/// fail (return `false`) and silently leave its `inout` parameters at whatever they were initialized
/// to. That's exactly how this went wrong twice before: `ProjectStore`'s `codable` initialized its
/// components to white (1,1,1,1) and got black colors coming out inverted to white, got "fixed" by
/// flipping the initializer to black (0,0,0,1) instead — which only changes *which* wrong answer a
/// failed resolve silently returns, not whether it can still fail. Then `resolvedUIColor` here got
/// `if self == Color.black` / `if self == Color.white` special cases bolted on for the same
/// underlying failure — which only ever covered those two literal singletons, leaving grays,
/// `.primary`/`.secondary`, and any other color resolved outside a SwiftUI body (a background
/// thread, `ProjectStore` serialization, etc.) exposed to the exact same silent failure.
///
/// The actual fix: resolve against an explicit, fixed trait collection *before* ever asking for
/// components, so extraction always runs on a concrete, non-dynamic color. That works uniformly for
/// black, white, gray, and any hue or alpha — no per-color special-casing, and no dependence on
/// whatever trait collection happens to be ambient when the call happens to run.
extension Color {
    private static let fixedTraitCollection = UITraitCollection(userInterfaceStyle: .light)

    /// Resolves this color to a concrete (non-dynamic) `UIColor` against a fixed trait collection,
    /// then reads back its RGBA components. This is the one place semantic/dynamic colors get
    /// collapsed to real numbers — everything else below builds on top of it.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        let resolved = UIColor(self).resolvedColor(with: Color.fixedTraitCollection)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// HSB(A) components (each 0...1), derived from the same resolved RGBA.
    var hsbaComponents: (h: Double, s: Double, b: Double, a: Double) {
        let c = rgbaComponents
        let hsb = ColorMath.rgbToHSB(r: c.r, g: c.g, b: c.b)
        return (hsb.h, hsb.s, hsb.v, c.a)
    }

    /// Builds a `Color` from HSB(A) components (each expected in 0...1).
    static func fromHSBA(h: Double, s: Double, b: Double, a: Double) -> Color {
        let rgb = ColorMath.hsbToRGB(h: h, s: s, v: b)
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: a)
    }

    /// Uppercase hex string (RRGGBB, or RRGGBBAA when not fully opaque), no leading '#'.
    var hexString: String {
        let c = rgbaComponents
        return ColorMath.hexString(r: c.r, g: c.g, b: c.b, a: c.a)
    }

    /// Parses a hex string (optionally '#'-prefixed; 3, 4, 6, or 8 hex digits). `nil` if it doesn't
    /// parse as one of those forms.
    init?(hex: String) {
        guard let c = ColorMath.parseHex(hex) else { return nil }
        self = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    /// Rebuilds a plain, non-dynamic `UIColor` at the given opacity — used everywhere brush color
    /// needs to become a concrete color for drawing/fill (`StrokeCanvasView`, `CanvasManager`'s fill
    /// tool). Because it goes through the same fixed-trait-collection resolution as everything else
    /// in this file, the result always matches exactly what was picked in the swatch, regardless of
    /// the caller's context (SwiftUI body, background thread, wherever this happens to run) or the
    /// device's current light/dark appearance — never darkened, inverted, or substituted with black
    /// or white.
    func resolvedUIColor(opacity: Double) -> UIColor {
        let c = rgbaComponents
        return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a * opacity))
    }
}
