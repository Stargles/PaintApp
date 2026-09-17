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

    // MARK: - sRGB transfer functions

    /// sRGB byte-domain value (0...1) -> linear light. IEC 61966-2-1's decoding function: the 12.92
    /// straight segment below 0.04045 and `((c + 0.055) / 1.055)^2.4` above it.
    ///
    /// **Clamps its input to 0...1 rather than extrapolating**, because a negative component has no
    /// real 2.4 power and every component that reaches this file came out of a `CodableColor`, a hex
    /// string or an HSB triple — all display-referred. An extended-range colour is not a thing this
    /// app stores, and returning NaN into a lookup table would be worse than clamping.
    static func srgbToLinear(_ c: Double) -> Double {
        let x = min(max(c, 0), 1)
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    /// Linear light -> sRGB byte-domain value. The exact inverse of `srgbToLinear`, clamped the same
    /// way at both ends.
    static func linearToSRGB(_ c: Double) -> Double {
        let x = min(max(c, 0), 1)
        return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    // MARK: - Oklab

    // Björn Ottosson's Oklab, published 2020-12-23 at
    // https://bottosson.github.io/posts/oklab/ — the "sRGB to Oklab" and "Oklab to sRGB" reference
    // listings, transcribed digit for digit. Both matrices below are quoted from that post; the
    // forward one folds linear sRGB into the LMS-like cone space, the cube roots are the
    // non-linearity, and the second matrix rotates that into one lightness axis (`L`) and two
    // opponent axes (`a` green-red, `b` blue-yellow).
    //
    // **Why this space and not HSB, which this file already speaks.** A straight line between two
    // colours in sRGB components is a straight line through a space whose axes are gamma-encoded
    // display voltages, so the middle of the line is darker than either end looks — the "muddy
    // middle" between two saturated hues. Oklab's axes are built so that equal steps look like equal
    // steps, which makes the middle of the line the colour a person would call halfway.
    //
    // MEASURED: `rgb -> Oklab -> rgb` returns the same 8-bit byte for **all 16,777,216** 8-bit
    // triples (`testTheOklabRoundTripIsByteExactOverTheWhole8BitCube` walks a sixteenth of them per
    // run and the generator in `tools/oklab_ramp_ab.swift` walked all of them once). So a gradient
    // stop's own colour survives being mixed at `t == 0` or `t == 1` exactly, with no special case.

    /// sRGB components (each 0...1) -> Oklab. `L` is perceptual lightness in 0...1; `a` and `b` are
    /// the two opponent chroma axes, roughly -0.4...0.4 for in-gamut colours.
    static func rgbToOklab(r: Double, g: Double, b: Double) -> (L: Double, a: Double, b: Double) {
        let lr = srgbToLinear(r), lg = srgbToLinear(g), lb = srgbToLinear(b)

        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)

        return (L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    /// Oklab -> sRGB components, each clamped to 0...1.
    ///
    /// **The clamp is per channel and it is a real approximation, not a formality.** A straight line
    /// between two in-gamut colours can leave the sRGB gamut in the middle, and clipping one channel
    /// there shifts the hue slightly rather than only the brightness. It is what every shipping
    /// implementation of an Oklab gradient does (CSS Color 4 leaves the gamut-mapping method to the
    /// implementation) and the alternative — scaling chroma back until the colour fits — is a second
    /// design with its own artefacts. MEASURED over the seven ramps the A/B renders: the straight
    /// line stays inside sRGB for all of them, so the clamp is inert on the cases this feature was
    /// built for.
    static func oklabToRGB(L: Double, a: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b

        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_

        return (r: linearToSRGB( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                g: linearToSRGB(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                b: linearToSRGB(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    /// Two sRGB colours mixed `t` of the way from `from` to `to`, **through Oklab** — the whole
    /// point of the two functions above.
    ///
    /// `t` is clamped to 0...1: every caller derives it from a position inside a segment, so a value
    /// outside that range is a bug at the call site rather than a request to extrapolate, and
    /// extrapolating in Oklab leaves the gamut almost immediately.
    ///
    /// There is deliberately **no short-circuit** at `t == 0` or `t == 1`. The round trip is byte
    /// exact over the whole 8-bit cube (see the note above), so the endpoints come back on their own
    /// — and a short-circuit would let a completely broken conversion still pass any test that only
    /// checks the ends.
    static func mixOklab(_ from: (r: Double, g: Double, b: Double),
                         _ to: (r: Double, g: Double, b: Double),
                         _ t: Double) -> (r: Double, g: Double, b: Double) {
        let f = min(max(t, 0), 1)
        let a = rgbToOklab(r: from.r, g: from.g, b: from.b)
        let z = rgbToOklab(r: to.r, g: to.g, b: to.b)
        return oklabToRGB(L: a.L + (z.L - a.L) * f,
                          a: a.a + (z.a - a.a) * f,
                          b: a.b + (z.b - a.b) * f)
    }

    /// How far apart two colours look, as the straight-line distance in Oklab. Used to state how
    /// finely a ramp has to be sampled before the sampling stops being visible.
    static func oklabDistance(_ x: (r: Double, g: Double, b: Double),
                              _ y: (r: Double, g: Double, b: Double)) -> Double {
        let a = rgbToOklab(r: x.r, g: x.g, b: x.b)
        let z = rgbToOklab(r: y.r, g: y.g, b: y.b)
        return ((a.L - z.L) * (a.L - z.L) + (a.a - z.a) * (a.a - z.a) + (a.b - z.b) * (a.b - z.b))
            .squareRoot()
    }

    // MARK: - The colour picker's hue rail

    /// How many samples the picker's hue bar is built from.
    ///
    /// **73 is 12 samples per sixth of the wheel, and the "per sixth" is the load-bearing half.** The
    /// fully-saturated hue function is piecewise linear with a corner at each of the six primaries
    /// and secondaries, so a sample count where `(count - 1) % 6 != 0` puts a segment *across* a
    /// corner and cuts it off. MEASURED against the true function at 8001 positions: 49 stops give
    /// 1/255, 73 give 1/255, but 33 — more stops than 7 and fewer than 49 — give **11/255**, worse
    /// than the seven this replaced, purely because 32 does not divide by 6.
    ///
    /// **Why more than seven at all, when seven is already exact.** The seven the picker used to
    /// carry sat exactly on the six corners, so if the gradient between them interpolates in the same
    /// sRGB component space the hue function is written in, the rail is perfect — MEASURED at 1/255.
    /// That is a bet on an interpolation space nobody documents. If it interpolates in linear light
    /// instead, the same seven stops are **74/255** wrong in the middle of a segment, which would put
    /// the colour under the drag thumb visibly beside the colour the thumb paints. At 73 the answer
    /// is 1/255 in the first case and 2/255 in the second, so the rail stops depending on the answer.
    static let hueRailStopCount = 73

    /// `count` fully saturated, fully bright hues, evenly spaced from 0 through 1 inclusive.
    ///
    /// **These are samples of `hsbToRGB`, not an Oklab mix between the corners**, and that is a
    /// decision rather than an oversight. The rail's job is to show the colour the picker will
    /// produce at that position — the drag thumb writes `hue = x / width` and paints
    /// `hsbToRGB(h: hue, s: 1, v: 1)`. Mixing the six corners in Oklab produces a *smoother* rail
    /// that is the wrong one: MEASURED, it lands **14.3 degrees** of hue and 61/255 away from the
    /// function the thumb uses, so the bar and the thumb would disagree about what the artist is
    /// picking. Oklab's job here is the sample count above, not the samples.
    static func hueRail(count: Int = hueRailStopCount) -> [(r: Double, g: Double, b: Double)] {
        guard count > 1 else { return [hsbToRGB(h: 0, s: 1, v: 1)] }
        return (0..<count).map { hsbToRGB(h: Double($0) / Double(count - 1), s: 1, v: 1) }
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

    // MARK: - HSL (TODO (73)'s Triangle picker)

    /// RGB (each 0...1) -> HSL. Standard conversion, achromatic input (r == g == b) always comes back
    /// hue 0 — same convention as `rgbToHSB` above, for the same reason: hue is genuinely undefined
    /// there, never NaN or a garbage value from a zero delta.
    static func rgbToHSL(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        let l = (maxC + minC) / 2
        guard delta > 0 else { return (0, 0, l) }

        let s = delta / (1 - abs(2 * l - 1))

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
        return (h, s, l)
    }

    /// HSL (each 0...1; hue wraps) -> RGB. Inverse of `rgbToHSL`.
    static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        guard s > 0 else { return (l, l, l) }
        let c = (1 - abs(2 * l - 1)) * s
        let wrapped = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let hh = wrapped * 6
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(hh) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }

    // MARK: - The colour picker's hue ring (Disc/Triangle/Square tabs)

    /// Where a hue sits on the ring, as radians **clockwise from the top** — the convention
    /// `AngularGradient`'s default start/direction already use, so the ring drawn with
    /// `hueRail`'s colours and the marker placed by this function agree with no extra rotation
    /// fudge either has to apply. `hue == 0` is straight up; `hue` increases clockwise.
    static func hueRingAngle(forHue hue: Double) -> Double {
        let wrapped = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        return wrapped * 2 * .pi
    }

    /// Inverse of `hueRingAngle`: the hue (0...1) for a touch at `(dx, dy)` relative to the ring's
    /// centre, in the same y-down screen coordinates every gesture here already uses. The centre
    /// itself (`dx == dy == 0`) reads as hue 0 rather than NaN — an arbitrary but harmless answer,
    /// since a touch exactly on the centre point has no well-defined angle anyway.
    static func hueForRingTouch(dx: Double, dy: Double) -> Double {
        guard dx != 0 || dy != 0 else { return 0 }
        let angle = atan2(dx, -dy)
        let normalized = angle < 0 ? angle + 2 * .pi : angle
        return normalized / (2 * .pi)
    }

    // MARK: - Square <-> disc (the Disc tab's saturation/brightness area)

    /// Maps a point in the square `[-1, 1] x [-1, 1]` onto the unit disc, preserving the angle from
    /// the origin and rescaling the radius so the square's edge lands on the disc's edge — the
    /// "radial"/Chebyshev square-to-disc map. Closed-form and exactly invertible by `discToSquare`
    /// (down to floating-point error), unlike the elliptical-grid mapping, which needs a
    /// difference-of-square-roots that is fussier near the edges. `(0, 0)` maps to `(0, 0)`.
    static func squareToDisc(u: Double, v: Double) -> (x: Double, y: Double) {
        let m = max(abs(u), abs(v))
        guard m > 0 else { return (0, 0) }
        let r = (u * u + v * v).squareRoot()
        let scale = m / r
        return (u * scale, v * scale)
    }

    /// Inverse of `squareToDisc`: a point in the unit disc back to the square `[-1, 1] x [-1, 1]`.
    static func discToSquare(x: Double, y: Double) -> (u: Double, v: Double) {
        let m = max(abs(x), abs(y))
        guard m > 0 else { return (0, 0) }
        let r = (x * x + y * y).squareRoot()
        let scale = r / m
        return (x * scale, y * scale)
    }

    // MARK: - The HSL triangle (the Triangle tab's saturation/lightness area)

    /// The triangle's three corners in its own local, unrotated frame: hue at the top, black and
    /// white at the base — an equilateral triangle inscribed in the unit circle, so it fits the same
    /// bounding box the ring/disc already use. The view layer is free to rotate this whole frame so
    /// the hue corner tracks the ring's marker; none of the maths below depends on that rotation.
    static let trianglePureHueVertex = (x: 0.0, y: -1.0)
    static let triangleBlackVertex = (x: -0.8660254037844387, y: 0.5)
    static let triangleWhiteVertex = (x: 0.8660254037844387, y: 0.5)

    /// Saturation/lightness (each 0...1) -> a point in the triangle's local frame. Derived from the
    /// standard HSL-to-RGB identity restricted to one hue: writing the corner blend as
    /// `wK*black + wW*white + wP*pureHue`, the barycentric weights that reproduce HSL's own `(s, l)`
    /// are `wP = chroma = (1 - |2l-1|) * s`, `wW = l - wP/2`, `wK = 1 - wW - wP`. That is what lets a
    /// point *in* the triangle mean an HSL colour at all, rather than the triangle being decoration
    /// around a separately-computed dot.
    static func trianglePosition(saturation s: Double, lightness l: Double) -> (x: Double, y: Double) {
        let chroma = (1 - abs(2 * l - 1)) * s
        let wP = chroma
        let wW = l - chroma / 2
        let wK = 1 - wW - wP
        let p = trianglePureHueVertex, w = triangleWhiteVertex, k = triangleBlackVertex
        return (wK * k.x + wW * w.x + wP * p.x, wK * k.y + wW * w.y + wP * p.y)
    }

    /// The raw (unclamped) barycentric weights of `(x, y)` against the triangle `(k, w, p)` —
    /// negative outside it. Split out from `triangleSaturationLightness` so rendering can ask "is
    /// this cell actually inside the triangle" (`triangleContains`) with the same arithmetic the
    /// gesture uses, rather than the clamped, always-in-range version below.
    private static func triangleBarycentricWeights(x: Double, y: Double) -> (wK: Double, wW: Double, wP: Double) {
        let p = trianglePureHueVertex, w = triangleWhiteVertex, k = triangleBlackVertex
        // Standard barycentric solve for a point against a triangle (k, w, p).
        let denom = (w.y - p.y) * (k.x - p.x) + (p.x - w.x) * (k.y - p.y)
        let wK = ((w.y - p.y) * (x - p.x) + (p.x - w.x) * (y - p.y)) / denom
        let wW = ((p.y - k.y) * (x - p.x) + (k.x - p.x) * (y - p.y)) / denom
        return (wK, wW, 1 - wK - wW)
    }

    /// Whether `(x, y)` (in the triangle's local frame) falls inside it — for rendering only, so a
    /// fill loop can leave the area outside the triangle blank instead of painting it with an edge
    /// colour it never actually is.
    static func triangleContains(x: Double, y: Double) -> Bool {
        let weights = triangleBarycentricWeights(x: x, y: y)
        let epsilon = -0.001
        return weights.wK >= epsilon && weights.wW >= epsilon && weights.wP >= epsilon
    }

    /// Inverse of `trianglePosition`: a point in the triangle's local frame -> saturation/lightness.
    /// A point outside the triangle (an in-progress drag can easily overshoot it) is **clamped by its
    /// barycentric weights** — any negative weight is raised to 0 and the three renormalized to sum
    /// to 1 — rather than rejected, so a drag that leaves the triangle still tracks its nearest edge
    /// instead of freezing the marker.
    static func triangleSaturationLightness(x: Double, y: Double) -> (s: Double, l: Double) {
        var (wK, wW, wP) = triangleBarycentricWeights(x: x, y: y)

        if wK < 0 || wW < 0 || wP < 0 {
            wK = max(wK, 0); wW = max(wW, 0); wP = max(wP, 0)
            let sum = wK + wW + wP
            if sum > 0 { wK /= sum; wW /= sum; wP /= sum }
        }

        let l = wW + wP / 2
        let denomS = 1 - abs(2 * l - 1)
        let s = denomS > 0.0001 ? min(max(wP / denomS, 0), 1) : 0
        return (s, min(max(l, 0), 1))
    }
}
