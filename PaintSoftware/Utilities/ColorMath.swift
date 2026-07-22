import Foundation

/// Pure, platform-independent color math — deliberately has no `import UIKit`/`SwiftUI` — so these
/// functions can be compiled and unit-tested with the plain `swift`/`swiftc` command line tool on
/// the host Mac, with no iOS Simulator involved at all. `ColorConversion.swift` is the only place
/// that touches `Color`/`UIColor` (that's where the historical semantic-color bugs lived); it
/// resolves a SwiftUI `Color` down to concrete RGBA components exactly once and then hands them to
/// these functions for everything else, so the actual math the new color picker relies on is
/// covered by tests that don't need UIKit or a simulator to run.
enum ColorMath {
    /// RGB (each component 0...1) -> HSB. Standard HSV conversion. Achromatic input (r == g == b —
    /// this covers black, white, and every gray in between) always comes back as hue 0, saturation
    /// 0, never NaN or a garbage hue from dividing by a zero delta.
    static func rgbToHSB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        let v = maxC
        let s = maxC == 0 ? 0 : delta / maxC
        guard delta > 0 else { return (0, s, v) }

        var h: Double
        if maxC == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h /= 6
        if h < 0 { h += 1 }
        return (h, s, v)
    }

    /// HSB (each component 0...1; hue wraps around outside that range) -> RGB. Inverse of
    /// `rgbToHSB`.
    static func hsbToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        guard s > 0 else { return (v, v, v) }
        let wrapped = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let hh = wrapped * 6
        let i = Int(hh) % 6
        let f = hh - Double(Int(hh))
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// RGBA (each component 0...1) -> uppercase hex, no leading '#'. Six digits (RRGGBB) when fully
    /// opaque, eight (RRGGBBAA) otherwise, so a fully-opaque round trip through `parseHex` stays a
    /// clean 6-digit string instead of picking up a spurious "FF" suffix.
    static func hexString(r: Double, g: Double, b: Double, a: Double) -> String {
        func byte(_ v: Double) -> UInt8 {
            UInt8((min(max(v, 0), 1) * 255).rounded())
        }
        let rb = byte(r), gb = byte(g), bb = byte(b), ab = byte(a)
        if ab == 255 {
            return String(format: "%02X%02X%02X", rb, gb, bb)
        }
        return String(format: "%02X%02X%02X%02X", rb, gb, bb, ab)
    }

    /// Parses a hex string — '#' prefix optional — accepting 3, 4, 6, or 8 hex digits (RGB, RGBA,
    /// RRGGBB, RRGGBBAA shorthand and full forms). Alpha defaults to fully opaque when the string
    /// omits it (3- or 6-digit forms). Returns `nil` for anything else: wrong length, non-hex
    /// characters, empty string.
    static func parseHex(_ string: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy({ $0.isHexDigit }) else { return nil }

        func expand(_ ch: Character) -> String { String([ch, ch]) }
        func value(_ hex: String) -> Double? {
            guard let byte = UInt8(hex, radix: 16) else { return nil }
            return Double(byte) / 255
        }

        let rHex: String, gHex: String, bHex: String, aHex: String
        let chars = Array(s)
        switch s.count {
        case 3, 4:
            rHex = expand(chars[0]); gHex = expand(chars[1]); bHex = expand(chars[2])
            aHex = s.count == 4 ? expand(chars[3]) : "FF"
        case 6, 8:
            rHex = String(chars[0...1]); gHex = String(chars[2...3]); bHex = String(chars[4...5])
            aHex = s.count == 8 ? String(chars[6...7]) : "FF"
        default:
            return nil
        }

        guard let r = value(rHex), let g = value(gHex), let b = value(bHex), let a = value(aHex) else {
            return nil
        }
        return (r, g, b, a)
    }
}
