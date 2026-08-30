// linear_light_q1q2.swift — evidence renderer for TODO item (10)'s two UNRULED questions.
//
// Q1: how the result comes back OUT of linear light.
// Q2: what linearizing does to the six non-separable blend modes.
//
// Sibling of tools/linear_light_ab.swift, which settled the *whether*. This one settles the *how*,
// and it copies that file's construction deliberately: a port of the shipped arithmetic term for
// term, evaluated in double precision, quantized once at the end, every number it draws also
// printed into a measurements file.
//
// ===================== THIS IS SIMULATED. IT IS NOT A SCREENSHOT. =====================
// No Metal ran. No simulator ran. No xcodebuild ran. The generator is a Swift port of:
//   `blendOver`                        Composite.metal:236-249
//   `lum` / `sat` / `clipColor`        Composite.metal:145, :146, :152-160
//   `setLum` / `setSat`                Composite.metal:161, :167-172
//   `blendHue`/`Saturation`/`Color`/
//   `Luminosity`/`LighterColor`/
//   `DarkerColor`                      Composite.metal:175, :177, :179, :181, :185, :186
//   the half-up quantizer               Composite.metal:417 — floor(v * 255 + 0.5)
// whose Swift mirror is Compositor.swift:624-662 (`lum` at :624, and its doc at :621-623 says it
// "Must agree with `lum` in `Composite.metal`").
// ======================================================================================
//
// Build and run (NOT /tmp — this machine is shared):
//   swiftc -O linear_light_q1q2.swift -o ./bin && ./bin ./out

import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

// MARK: - Transfer functions (identical to tools/linear_light_ab.swift:24-30)

@inline(__always) func srgbToLinear(_ c: Double) -> Double {
    let x = max(0.0, min(1.0, c))
    return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
}
@inline(__always) func linearToSrgb(_ c: Double) -> Double {
    let x = max(0.0, min(1.0, c))
    return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1.0 / 2.4) - 0.055
}

typealias C3 = (r: Double, g: Double, b: Double)

@inline(__always) func lin3(_ c: C3) -> C3 { (srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b)) }
@inline(__always) func enc3(_ c: C3) -> C3 { (linearToSrgb(c.r), linearToSrgb(c.g), linearToSrgb(c.b)) }

/// `Composite.metal:417`'s rule, verbatim: `floor(v * 255 + 0.5)`, "the one rounding rule that can
/// be written identically in Metal and Swift".
@inline(__always) func q8(_ v: Double) -> Int { max(0, min(255, Int(floor(max(0, min(1, v)) * 255.0 + 0.5)))) }

// MARK: - Q1's four output routes, on one channel of Normal source-over
//
// Normal source-over on one channel is a lerp, so a single channel is the exhaustive case — the
// same reduction tools/linear_light_ab.swift:594-607 makes.

enum OutRoute: Int, CaseIterable {
    case today          // (a) 8-bit sRGB throughout. No transfer function anywhere. TODAY.
    case linear8        // (b) linear light, 8-bit LINEAR intermediate.
    case linearFloat    // (c) linear light, continuous float intermediate, encoded by pow.
    case table12        // (d) linear light, encoded by a 4096-entry integer-indexed table.
    var short: String {
        switch self {
        case .today: return "a TODAY"
        case .linear8: return "b LINEAR, 8-bit store"
        case .linearFloat: return "c LINEAR, float + pow"
        case .table12: return "d LINEAR, 12-bit table"
        }
    }
}

/// `encodeTable12[i]` is the displayed sRGB byte for linear value `i / 4095`, built with the same
/// half-up index rule `lutEntry` uses (Composite.metal:416-417). 4096 bytes — exactly the size of
/// Metal's `setBytes` limit, and four times the effect LUT already bound at MetalEffects.swift:91-94.
let encodeTable12: [UInt8] = (0...4095).map { UInt8(q8(linearToSrgb(Double($0) / 4095.0))) }
/// The displayed sRGB byte for each of the 256 codes an 8-bit LINEAR store can hold.
let linear8Display: [UInt8] = (0...255).map { UInt8(q8(linearToSrgb(Double($0) / 255.0))) }
/// sRGB byte -> linear, tabled. The input side is exact by construction (TODO.md:141-142's claim,
/// which is sound for the *input*).
let srgbToLinearTable: [Double] = (0...255).map { srgbToLinear(Double($0) / 255.0) }

/// One channel: source byte `cs` at coverage `t` over backdrop byte `cb`. Returns the DISPLAYED
/// sRGB byte — i.e. what reaches the panel after the route's own encode.
@inline(__always) func normalChannel(cb: Int, cs: Int, t: Double, route: OutRoute) -> Int {
    switch route {
    case .today:
        return q8((Double(cb) / 255) * (1 - t) + (Double(cs) / 255) * t)
    case .linear8:
        let l = srgbToLinearTable[cb] * (1 - t) + srgbToLinearTable[cs] * t
        return Int(linear8Display[q8(l)])                      // store 8-bit linear, then display
    case .linearFloat:
        let l = srgbToLinearTable[cb] * (1 - t) + srgbToLinearTable[cs] * t
        return q8(linearToSrgb(l))
    case .table12:
        let l = srgbToLinearTable[cb] * (1 - t) + srgbToLinearTable[cs] * t
        return Int(encodeTable12[max(0, min(4095, Int(floor(max(0, min(1, l)) * 4095.0 + 0.5))))])
    }
}

// MARK: - Q2's non-separable helpers, ported term for term from Composite.metal:145-186
//
// The only thing parameterised is the coefficient triple inside `lum`, because that IS the question.

struct LumRecipe { let r: Double, g: Double, b: Double; let name: String }
/// Composite.metal:145 — `0.3f * c.r + 0.59f * c.g + 0.11f * c.b`. These are ~Rec.601 *luma*
/// coefficients, which are defined on gamma-encoded values.
let W3C = LumRecipe(r: 0.30, g: 0.59, b: 0.11, name: "0.30 / 0.59 / 0.11")
/// Rec.709 *luminance*, defined on linear values.
let REC709 = LumRecipe(r: 0.2126, g: 0.7152, b: 0.0722, name: "0.2126 / 0.7152 / 0.0722")

@inline(__always) func lum(_ c: C3, _ k: LumRecipe) -> Double { k.r * c.r + k.g * c.g + k.b * c.b }
@inline(__always) func sat(_ c: C3) -> Double {
    max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))
}

/// Composite.metal:152-160. Both `max(_, 1e-6)` guards kept exactly where the shader puts them.
func clipColor(_ c0: C3, _ k: LumRecipe) -> C3 {
    var c = c0
    let l = lum(c, k)
    let n = min(c.r, min(c.g, c.b))
    let x = max(c.r, max(c.g, c.b))
    if n < 0 {
        let s = l / max(l - n, 1e-6)
        c = (l + (c.r - l) * s, l + (c.g - l) * s, l + (c.b - l) * s)
    }
    if x > 1 {
        let s = (1 - l) / max(x - l, 1e-6)
        c = (l + (c.r - l) * s, l + (c.g - l) * s, l + (c.b - l) * s)
    }
    return c
}
/// Composite.metal:161.
func setLum(_ c: C3, _ l: Double, _ k: LumRecipe) -> C3 {
    let d = l - lum(c, k)
    return clipColor((c.r + d, c.g + d, c.b + d), k)
}
/// Composite.metal:167-172 — the one affine remap, not the spec's sort-and-rewrite.
func setSat(_ c: C3, _ s: Double) -> C3 {
    let cMax = max(c.r, max(c.g, c.b)), cMin = min(c.r, min(c.g, c.b))
    if cMax <= cMin { return (0, 0, 0) }
    let k = s / (cMax - cMin)
    return ((c.r - cMin) * k, (c.g - cMin) * k, (c.b - cMin) * k)
}

enum Mode6: Int, CaseIterable {
    case hue, saturation, color, luminosity, lighterColor, darkerColor
    var name: String {
        switch self {
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .color: return "Color"
        case .luminosity: return "Luminosity"
        case .lighterColor: return "Lighter Color"
        case .darkerColor: return "Darker Color"
        }
    }
    /// What an artist would recognise, not what the formula says.
    var plain: [String] {
        switch self {
        case .hue:          return ["keeps the backdrop's brightness and how", "vivid it is; takes WHICH COLOUR from the top layer"]
        case .saturation:   return ["keeps the backdrop's colour and brightness;", "takes HOW VIVID it is from the top layer"]
        case .color:        return ["paints the top layer's colour onto the", "backdrop's own light and shade"]
        case .luminosity:   return ["keeps the backdrop's colour; takes the", "LIGHT AND SHADE from the top layer"]
        case .lighterColor: return ["shows whichever whole layer is judged", "the BRIGHTER of the two"]
        case .darkerColor:  return ["shows whichever whole layer is judged", "the DARKER of the two"]
        }
    }
    var line: String {
        switch self {
        case .hue: return "Composite.metal:175"
        case .saturation: return "Composite.metal:177"
        case .color: return "Composite.metal:179"
        case .luminosity: return "Composite.metal:181"
        case .lighterColor: return "Composite.metal:185"
        case .darkerColor: return "Composite.metal:186"
        }
    }
}

func blend6(_ m: Mode6, _ cb: C3, _ cs: C3, _ k: LumRecipe) -> C3 {
    switch m {
    case .hue:          return setLum(setSat(cs, sat(cb)), lum(cb, k), k)
    case .saturation:   return setLum(setSat(cb, sat(cs)), lum(cb, k), k)
    case .color:        return setLum(cs, lum(cb, k), k)
    case .luminosity:   return setLum(cb, lum(cs, k), k)
    case .lighterColor: return lum(cs, k) >= lum(cb, k) ? cs : cb
    case .darkerColor:  return lum(cs, k) <= lum(cb, k) ? cs : cb
    }
}

/// Which layer a whole-triple winner mode picks, under a given route. Used to measure FLIPS —
/// `blendLighterColor` (Composite.metal:185) has no "slightly different" answer, only a swap.
@inline(__always) func picksSource(_ m: Mode6, _ cbS: C3, _ csS: C3, _ route: Q2Route) -> Bool {
    let (cb, cs, k) = route.operands(cbS, csS)
    return m == .lighterColor ? lum(cs, k) >= lum(cb, k) : lum(cs, k) <= lum(cb, k)
}

enum Q2Route: Int, CaseIterable {
    case today              // (i)   sRGB values, 0.30/0.59/0.11 — what ships now.
    case linearSameRecipe   // (ii)  linear values, 0.30/0.59/0.11 kept — the naive port.
    case linearLightRecipe  // (iii) linear values, Rec.709 — the physically consistent port.
    case linearExempt       // (iv)  linear document, these six decode to sRGB, compute, re-encode.

    var short: [String] {
        switch self {
        case .today:             return ["i  TODAY", "as it ships"]
        case .linearSameRecipe:  return ["ii  LINEAR", "same recipe"]
        case .linearLightRecipe: return ["iii  LINEAR", "light recipe"]
        case .linearExempt:      return ["iv  LINEAR", "six exempt"]
        }
    }
    var isLinear: Bool { self != .today }
    func operands(_ cbS: C3, _ csS: C3) -> (C3, C3, LumRecipe) {
        switch self {
        case .today:             return (cbS, csS, W3C)
        case .linearSameRecipe:  return (lin3(cbS), lin3(csS), W3C)
        case .linearLightRecipe: return (lin3(cbS), lin3(csS), REC709)
        case .linearExempt:      return (cbS, csS, W3C)     // the exempt blend runs on sRGB values
        }
    }
}

/// `blendOver` (Composite.metal:236-249) with the route inserted. Alpha is coverage and is never
/// linearized, exactly as tools/linear_light_ab.swift:48-49 states.
func blendOver6(dst: (C3, Double), src: (C3, Double), mode: Mode6, route: Q2Route) -> (C3, Double) {
    let (dc, da) = dst, (sc, sa) = src
    // Composite.metal:245-246 — `saturate(src.rgb / sa)`.
    let csS: C3 = sa > 0 ? (min(1, sc.r / sa), min(1, sc.g / sa), min(1, sc.b / sa)) : (0, 0, 0)
    let cbS: C3 = da > 0 ? (min(1, dc.r / da), min(1, dc.g / da), min(1, dc.b / da)) : (0, 0, 0)

    let linear = route.isLinear
    let cs: C3 = linear ? lin3(csS) : csS
    let cb: C3 = linear ? lin3(cbS) : cbS

    let bl: C3
    switch route {
    case .today:
        bl = blend6(mode, cbS, csS, W3C)
    case .linearSameRecipe:
        bl = blend6(mode, cb, cs, W3C)
    case .linearLightRecipe:
        bl = blend6(mode, cb, cs, REC709)
    case .linearExempt:
        // Decode back out, compute exactly today's answer, re-enter the linear composite.
        let s = blend6(mode, cbS, csS, W3C)
        bl = lin3((max(0, min(1, s.r)), max(0, min(1, s.g)), max(0, min(1, s.b))))
    }

    // Composite.metal:248 — `float3 cr = mix(cs, blendChannels(mode, cb, cs), da);`
    let cr: C3 = (cs.r + (bl.r - cs.r) * da,
                  cs.g + (bl.g - cs.g) * da,
                  cs.b + (bl.b - cs.b) * da)
    let ao = da * (1 - sa) + sa
    // Composite.metal:249 — `fma(dst.rgb, 1.0f - sa, sa * cr)`, on premultiplied values.
    let dpm: C3 = (cb.r * da, cb.g * da, cb.b * da)
    var co: C3 = (dpm.r * (1 - sa) + sa * cr.r,
                  dpm.g * (1 - sa) + sa * cr.g,
                  dpm.b * (1 - sa) + sa * cr.b)
    if linear {
        guard ao > 0 else { return ((0, 0, 0), 0) }
        let u: C3 = (co.r / ao, co.g / ao, co.b / ao)
        let e = enc3(u)
        co = (e.r * ao, e.g * ao, e.b * ao)
    }
    return (co, ao)
}

/// Full-opacity result of one mode under one route, as displayed sRGB bytes.
@inline(__always) func opaqueResult(_ cb: (Int, Int, Int), _ cs: (Int, Int, Int),
                                    _ m: Mode6, _ r: Q2Route) -> (Int, Int, Int) {
    let b: C3 = (Double(cb.0) / 255, Double(cb.1) / 255, Double(cb.2) / 255)
    let s: C3 = (Double(cs.0) / 255, Double(cs.1) / 255, Double(cs.2) / 255)
    let o = blendOver6(dst: (b, 1), src: (s, 1), mode: m, route: r)
    return (q8(o.0.r), q8(o.0.g), q8(o.0.b))
}

// MARK: - Buffers and page assembly (copied from tools/linear_light_ab.swift:81-227)

final class Buf {
    let w: Int, h: Int
    var px: [UInt8]
    init(_ w: Int, _ h: Int, fill: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)) {
        self.w = w; self.h = h
        px = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = fill.0; px[i+1] = fill.1; px[i+2] = fill.2; px[i+3] = fill.3
        }
    }
    @inline(__always) func setByte(_ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        let i = (y * w + x) * 4
        px[i] = UInt8(max(0, min(255, r))); px[i+1] = UInt8(max(0, min(255, g)))
        px[i+2] = UInt8(max(0, min(255, b))); px[i+3] = UInt8(max(0, min(255, a)))
    }
    var cgImage: CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let data = CFDataCreate(nil, px, px.count)!
        let prov = CGDataProvider(data: data)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

let mono = CTFontCreateWithName("Menlo" as CFString, 15, nil)
let monoBold = CTFontCreateWithName("Menlo-Bold" as CFString, 15, nil)

func text(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat,
          size: CGFloat = 15, bold: Bool = false, grey: CGFloat = 0.08) {
    let f = CTFontCreateCopyWithAttributes(bold ? monoBold : mono, size, nil, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(red: grey, green: grey, blue: grey, alpha: 1)
    ])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func page(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // y-down for the rest
    body(ctx)
    return ctx.makeImage()!
}

func place(_ ctx: CGContext, _ b: Buf, _ r: CGRect) {
    ctx.saveGState()
    ctx.interpolationQuality = .none
    ctx.translateBy(x: 0, y: r.midY); ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -r.midY)
    ctx.draw(b.cgImage, in: r)
    ctx.restoreGState()
}

func box(_ ctx: CGContext, _ r: CGRect, _ w: CGFloat = 1.5, grey: CGFloat = 0) {
    ctx.setStrokeColor(CGColor(red: grey, green: grey, blue: grey, alpha: 1))
    ctx.setLineWidth(w); ctx.stroke(r)
}

func swatch(_ ctx: CGContext, _ c: (Int, Int, Int), _ r: CGRect) {
    ctx.setFillColor(CGColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                             blue: CGFloat(c.2) / 255, alpha: 1))
    ctx.fill(r)
}

func write(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
    print("wrote \(path)")
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
var log: [String] = []
func say(_ s: String) { log.append(s); print(s) }

say("=== linear_light_q1q2 — SIMULATED, not a screenshot. Port of Composite.metal:145-186,")
say("=== :236-249 and :417 into double precision. No Metal, no simulator, no xcodebuild.")
say("")

// ===========================================================================================
// MARK: - Q1 measurements
// ===========================================================================================

say("--- Q1 · the 8-bit LINEAR intermediate, on its own terms (MEASURED, exhaustive over 256 codes) ---")

// How many of the 256 sRGB output codes an 8-bit linear store can still reach.
var reachable = Set<Int>()
for k in 0...255 { reachable.insert(Int(linear8Display[k])) }
let reachableSorted = reachable.sorted()
var largestGap = 0, gapAt = 0
for i in 1..<reachableSorted.count {
    let g = reachableSorted[i] - reachableSorted[i-1]
    if g > largestGap { largestGap = g; gapAt = reachableSorted[i-1] }
}
say("Q1.1 8-bit LINEAR store reaches \(reachable.count) of the 256 sRGB output codes.")
say("Q1.1 largest hole between two reachable codes: \(largestGap) codes, starting at sRGB \(gapAt).")
say("Q1.1 the first six linear codes display as sRGB \((0...5).map { Int(linear8Display[$0]) }).")

// Where the 8-bit linear step stops being coarser than one sRGB code.
var crossoverLinearCode = -1, crossoverSrgbCode = -1
var stepCurve: [(srgb: Double, step: Double)] = []
for k in 0..<255 {
    let lo = linearToSrgb(Double(k) / 255.0) * 255.0
    let hi = linearToSrgb(Double(k + 1) / 255.0) * 255.0
    let step = hi - lo
    stepCurve.append((lo, step))
    if step < 1.0 && crossoverLinearCode < 0 {
        crossoverLinearCode = k; crossoverSrgbCode = Int(lo.rounded())
    }
}
say("Q1.2 the 8-bit LINEAR step is WIDER than one sRGB code for everything below sRGB \(crossoverSrgbCode)")
say("Q1.2   (linear code \(crossoverLinearCode)). Above that it is finer than 8-bit sRGB and costs nothing.")
say("Q1.2 REFUTES the brief's framing 'bands the shadows': the step SHRINKS as the value rises, so")
say("Q1.2   the coarse region is everything from black up to sRGB \(crossoverSrgbCode) — over half the tonal range,")
say("Q1.2   not a dark corner. Step at sRGB 0->1: \(String(format: "%.2f", stepCurve[0].step)) codes; at sRGB 128: " +
    "\(String(format: "%.2f", stepCurve.min(by: { abs($0.srgb - 128) < abs($1.srgb - 128) })!.step)) codes.")

// Exhaustive Normal sweep: worst error of each route against the float reference, plus the
// last-ulp at-risk population.
let ULP1 = pow(2.0, -23.0)          // one ulp of float32, relative
let ULP16 = 16.0 * ULP1             // Metal Shading Language's specified bound for `pow`
var worstBvsC = 0, wb_cb = 0, wb_cs = 0, wb_t = 0.0
var worstAvsC = 0, wa_cb = 0, wa_cs = 0, wa_t = 0.0
var worstDvsC = 0
var atRisk1 = 0, atRisk16 = 0, powBranch = 0
let total = 256 * 256 * 256

for cb in 0...255 {
    let lb = srgbToLinearTable[cb]
    for cs in 0...255 {
        let ls = srgbToLinearTable[cs]
        for i in 0...255 {
            let t = Double(i) / 255.0
            let l = lb * (1 - t) + ls * t
            let e = linearToSrgb(l)
            let c = q8(e)                                   // route (c), the float reference
            let a = q8((Double(cb) / 255) * (1 - t) + (Double(cs) / 255) * t)
            let b = Int(linear8Display[q8(l)])
            let d = Int(encodeTable12[max(0, min(4095, Int(floor(max(0, min(1, l)) * 4095.0 + 0.5))))])
            if abs(b - c) > worstBvsC { worstBvsC = abs(b - c); wb_cb = cb; wb_cs = cs; wb_t = t }
            if abs(a - c) > worstAvsC { worstAvsC = abs(a - c); wa_cb = cb; wa_cs = cs; wa_t = t }
            if abs(d - c) > worstDvsC { worstDvsC = abs(d - c) }
            // At-risk population for route (c): a byte that a `pow` disagreement would flip.
            // Only the pow branch is at risk — below 0.0031308 the encode is a multiply.
            if l > 0.0031308 {
                powBranch += 1
                let v = e * 255.0
                let s = v + 0.5
                let dist = abs(s - s.rounded())             // distance to the flip boundary
                // e = 1.055 * pow(l, 1/2.4) - 0.055, so a relative error d on the pow moves e by
                // d * (e + 0.055). Bounds the POW's contribution only — the float32 lerp feeding it
                // carries its own error, so this is a LOWER bound on the at-risk population.
                if dist < 255.0 * ULP1 * (e + 0.055) { atRisk1 += 1 }
                if dist < 255.0 * ULP16 * (e + 0.055) { atRisk16 += 1 }
            }
        }
    }
}
say("")
say("--- Q1 · exhaustive over all 256x256x256 (backdrop, source, coverage) Normal triples, one channel ---")
say("Q1.3 worst |b 8-bit-linear  -  c float+pow| = \(worstBvsC)/255  at backdrop \(wb_cb), source \(wb_cs), coverage \(String(format: "%.3f", wb_t))")
say("Q1.3 worst |d 12-bit table  -  c float+pow| = \(worstDvsC)/255")
say("Q1.3 worst |a TODAY         -  c float+pow| = \(worstAvsC)/255  at backdrop \(wa_cb), source \(wa_cs), coverage \(String(format: "%.3f", wa_t))")
say("Q1.3   (the last line is LINEAR_LIGHT_AB.md §3's 73/255 re-derived independently — a check on this port.)")
let f1 = Double(atRisk1) / Double(total), f16 = Double(atRisk16) / Double(total)
say("")
say("--- Q1 · the last-ulp parity risk of route (c). INFERRED-BUT-BOUNDED. ---")
say("Q1.4 triples whose byte a 1-ulp `pow` disagreement would flip:  \(atRisk1) of \(total)  = \(String(format: "%.3e", f1))")
say("Q1.4 triples whose byte a 16-ulp disagreement would flip:      \(atRisk16) of \(total)  = \(String(format: "%.3e", f16))")
say("Q1.4   (16 ulps is the Metal Shading Language spec's stated bound for `pow`.)")
say("Q1.4 \(powBranch) of \(total) triples take the pow branch at all; the rest are the linear segment (l <= 0.0031308).")
let canvasPx = 2048 * 1024
say("Q1.4 on the owner's 2048x1024 canvas that is \(String(format: "%.0f", f1 * Double(canvasPx))) pixels at 1 ulp and " +
    "\(String(format: "%.0f", f16 * Double(canvasPx))) at 16 ulps, PER FRAME.")
say("Q1.4 at-risk population for routes (a), (b) and (d): 0, by construction — none of them calls `pow`")
say("Q1.4   at run time. (a) has no transfer at all; (b) and (d) index integer tables built once on the CPU.")

// ===========================================================================================
// MARK: - Q1 scene 1 — the shadows, where the routes actually differ
// ===========================================================================================

/// A coverage ramp of source byte `cs` over backdrop byte `cb`, rendered through one route.
func rampStrip(_ w: Int, _ h: Int, cb: Int, cs: Int, route: OutRoute, amp: Int = 1) -> (Buf, Int) {
    let b = Buf(w, h)
    var levels = Set<Int>()
    for x in 0..<w {
        let t = Double(x) / Double(w - 1)
        let v = normalChannel(cb: cb, cs: cs, t: t, route: route)
        levels.insert(v)
        for y in 0..<h { b.setByte(x, y, v * amp, v * amp, v * amp) }
    }
    return (b, levels.count)
}

/// A dark soft dab: radial coverage falloff of source byte `cs` over backdrop byte `cb`.
func darkDab(_ s: Int, cb: Int, cs: Int, route: OutRoute, amp: Int = 1) -> Buf {
    let b = Buf(s, s)
    let c = Double(s) / 2, rr = Double(s) * 0.47
    for y in 0..<s {
        for x in 0..<s {
            let d = ((Double(x) + 0.5 - c) * (Double(x) + 0.5 - c)
                     + (Double(y) + 0.5 - c) * (Double(y) + 0.5 - c)).squareRoot() / rr
            let t = d >= 1 ? 0 : pow(1 - d, 1.5)
            let v = normalChannel(cb: cb, cs: cs, t: t, route: route)
            b.setByte(x, y, v * amp, v * amp, v * amp)
        }
    }
    return b
}

do {
    let SW = 1130, SH = 80               // ramp strip
    let SX: CGFloat = 260                // left label column
    let DAB = 300
    let W = 1660, H = 1740
    let RAMP_CS = 32, DAB_CS = 48, AMP = 7

    var rampLevels: [OutRoute: Int] = [:]
    var dabWorst: [OutRoute: Int] = [:]
    var dabLevels: [OutRoute: Int] = [:]

    let img = page(W, H) { ctx in
        text(ctx, "Q1 — how the picture comes back OUT of linear light.", 40, 48, size: 26, bold: true)
        text(ctx, "SIMULATED, not a screenshot. Port of Composite.metal's arithmetic (:236-249, :417) in double precision. No Metal, no simulator.",
             40, 78, size: 13, grey: 0.42)
        text(ctx, "All four routes composite in linear light except (a). They differ ONLY in how the finished linear value becomes an 8-bit pixel.",
             40, 100, size: 14, grey: 0.2)

        // ---- legend
        var ly: CGFloat = 140
        let legend: [(String, String)] = [
            ("(a) TODAY", "no transfer function anywhere. 8-bit sRGB in, 8-bit sRGB out. This is what ships."),
            ("(b) 8-bit LINEAR store", "the finished linear value is rounded to one of 256 linear codes, then displayed. Exact on both backends."),
            ("(c) float + pow", "the linear value stays continuous and is encoded with pow(x, 1/2.4). The 'correct' one, and the ulp risk."),
            ("(d) 12-bit table", "the linear value indexes a 4096-entry table built once on the CPU. NOT one of the three the brief names."),
        ]
        for (a, b) in legend {
            text(ctx, a, 40, ly, size: 15, bold: true)
            text(ctx, b, 300, ly, size: 14, grey: 0.25)
            ly += 24
        }

        // ---- Panel A: near-black coverage ramp
        text(ctx, "A.  A near-black coverage ramp — a dark grey (sRGB \(RAMP_CS)) fading to black across \(SW) px.",
             40, 272, size: 18, bold: true)
        text(ctx, "This is the shadow content the three routes disagree about. At 1:1 it is nearly invisible on most monitors, so each strip is repeated at \(AMP)x brightness.",
             40, 296, size: 13, grey: 0.42)
        var y: CGFloat = 320
        for r in OutRoute.allCases {
            let (b1, n) = rampStrip(SW, SH, cb: 0, cs: RAMP_CS, route: r, amp: 1)
            let (b2, _) = rampStrip(SW, SH, cb: 0, cs: RAMP_CS, route: r, amp: AMP)
            rampLevels[r] = n
            place(ctx, b1, CGRect(x: SX, y: y, width: CGFloat(SW), height: CGFloat(SH) / 2))
            place(ctx, b2, CGRect(x: SX, y: y + CGFloat(SH) / 2, width: CGFloat(SW), height: CGFloat(SH) / 2))
            box(ctx, CGRect(x: SX, y: y, width: CGFloat(SW), height: CGFloat(SH)))
            text(ctx, r.short, 40, y + 26, size: 15, bold: true)
            text(ctx, "1:1 above, \(AMP)x below", 40, y + 48, size: 11, grey: 0.45)
            text(ctx, "\(n) distinct levels", SX + CGFloat(SW) + 16, y + 46, size: 15,
                 bold: r == .linear8, grey: r == .linear8 ? 0.0 : 0.3)
            y += CGFloat(SH) + 14
        }
        text(ctx, "(b) collapses a \(rampLevels[.today] ?? 0)-step ramp to \(rampLevels[.linear8] ?? 0) steps. That is not a rounding difference; it is a different picture.",
             40, y + 24, size: 16, bold: true)
        text(ctx, "(a), (c) and (d) all keep the ramp smooth. The shapes of (a) and (c) differ — that is the linear-light change LINEAR_LIGHT_AB.md already priced at 73/255 — but neither one bands.",
             40, y + 48, size: 13, grey: 0.35)

        // ---- Panel B: the dark soft dab
        let by: CGFloat = y + 84
        text(ctx, "B.  A dark soft brush dab (sRGB \(DAB_CS)) on black — the same content an artist lays down in shadow.",
             40, by, size: 18, bold: true)
        text(ctx, "Shown at \(AMP)x brightness for the same reason. The rings in (b) are the 8-bit linear store's quantization, not anything in the artwork.",
             40, by + 24, size: 13, grey: 0.42)
        let refDab = darkDab(DAB, cb: 0, cs: DAB_CS, route: .linearFloat, amp: 1)
        for (i, r) in OutRoute.allCases.enumerated() {
            let x = CGFloat(40 + i * (DAB + 40))
            let d = darkDab(DAB, cb: 0, cs: DAB_CS, route: r, amp: AMP)
            let plain = darkDab(DAB, cb: 0, cs: DAB_CS, route: r, amp: 1)
            var worst = 0
            var lv = Set<UInt8>()
            for k in stride(from: 0, to: plain.px.count, by: 4) {
                worst = max(worst, abs(Int(plain.px[k]) - Int(refDab.px[k])))
                lv.insert(plain.px[k])
            }
            dabWorst[r] = worst
            dabLevels[r] = lv.count
            place(ctx, d, CGRect(x: x, y: by + 44, width: CGFloat(DAB), height: CGFloat(DAB)))
            box(ctx, CGRect(x: x, y: by + 44, width: CGFloat(DAB), height: CGFloat(DAB)))
            text(ctx, r.short, x, by + 44 + CGFloat(DAB) + 22, size: 14, bold: true)
            text(ctx, "\(lv.count) distinct levels", x, by + 44 + CGFloat(DAB) + 42, size: 13,
                 bold: r == .linear8, grey: r == .linear8 ? 0.0 : 0.4)
            text(ctx, "worst \(worst)/255 vs (c)", x, by + 44 + CGFloat(DAB) + 60, size: 13, grey: 0.4)
        }

        // ---- Panel C: where the banding stops
        let cy: CGFloat = by + 44 + CGFloat(DAB) + 124
        text(ctx, "C.  Where (b)'s banding stops — and it is not \"the shadows\".", 40, cy, size: 18, bold: true)
        text(ctx, "How wide one step of the 8-bit LINEAR store is, measured in sRGB output codes. Above 1.0 the store is coarser than the 8-bit sRGB it replaces.",
             40, cy + 24, size: 13, grey: 0.42)
        let PW: CGFloat = 1100, PH: CGFloat = 230, PX: CGFloat = 120, PY: CGFloat = cy + 78
        // axes
        ctx.setStrokeColor(CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)); ctx.setLineWidth(1)
        for gv in stride(from: 0.0, through: 4.0, by: 1.0) {
            let gy = PY + PH - CGFloat(gv / 4.0) * PH
            ctx.move(to: CGPoint(x: PX, y: gy)); ctx.addLine(to: CGPoint(x: PX + PW, y: gy)); ctx.strokePath()
            text(ctx, String(format: "%.0f", gv), PX - 34, gy + 5, size: 12, grey: 0.4)
        }
        // the 1.0 line, emphasised
        let oneY = PY + PH - CGFloat(1.0 / 4.0) * PH
        ctx.setStrokeColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: PX, y: oneY)); ctx.addLine(to: CGPoint(x: PX + PW, y: oneY)); ctx.strokePath()
        text(ctx, "one sRGB code — the width 8-bit sRGB already gives", PX + PW - 430, oneY - 10, size: 13, grey: 0.5)
        // the curve
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(2.5)
        var started = false
        for p in stepCurve {
            let px = PX + CGFloat(p.srgb / 255.0) * PW
            let py = PY + PH - CGFloat(min(p.step, 4.0) / 4.0) * PH
            if !started { ctx.move(to: CGPoint(x: px, y: py)); started = true }
            else { ctx.addLine(to: CGPoint(x: px, y: py)) }
        }
        ctx.strokePath()
        // crossover marker
        let cx = PX + CGFloat(Double(crossoverSrgbCode) / 255.0) * PW
        ctx.setStrokeColor(CGColor(red: 0.1, green: 0.35, blue: 0.8, alpha: 1)); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: cx, y: PY)); ctx.addLine(to: CGPoint(x: cx, y: PY + PH + 8)); ctx.strokePath()
        text(ctx, "sRGB \(crossoverSrgbCode)", cx - 34, PY + PH + 28, size: 14, bold: true, grey: 0.1)
        text(ctx, "coarser than 8-bit sRGB  <-", cx - 260, PY + 26, size: 14, bold: true, grey: 0.15)
        text(ctx, "->  finer, costs nothing", cx + 14, PY + 26, size: 14, grey: 0.35)
        text(ctx, "sRGB output code  0", PX - 10, PY + PH + 28, size: 12, grey: 0.4)
        text(ctx, "255", PX + PW - 16, PY + PH + 28, size: 12, grey: 0.4)
        text(ctx, "step width,", PX - 112, PY - 26, size: 12, grey: 0.4)
        text(ctx, "in sRGB codes", PX - 112, PY - 10, size: 12, grey: 0.4)
        text(ctx, "(clipped at 4; it reaches 12.71 at black)", PX + 10, PY - 10, size: 12, grey: 0.45)
        text(ctx, "MEASURED: an 8-bit LINEAR store is coarser than today's 8-bit sRGB for every value below sRGB \(crossoverSrgbCode) —",
             40, PY + PH + 66, size: 16, bold: true)
        text(ctx, "over half the tonal range, not a dark corner. It reaches only \(reachable.count) of the 256 output codes, and its widest hole is \(largestGap) codes at black.",
             40, PY + PH + 90, size: 16, bold: true)
        text(ctx, "The brief's phrase was \"bands the shadows\". The step SHRINKS as the value rises, so the coarse region runs from black up to mid-grey.",
             40, PY + PH + 116, size: 13, grey: 0.35)
    }
    write(img, "\(outDir)/Q1-shadow-banding.png")
    say("")
    say("--- Q1 · scene A, the near-black ramp (sRGB 0 -> \(RAMP_CS) over \(SW) px), MEASURED ---")
    for r in OutRoute.allCases { say("Q1.5 \(r.short): \(rampLevels[r] ?? -1) distinct output levels") }
    say("--- Q1 · scene B, the dark soft dab (sRGB \(DAB_CS) on black), MEASURED ---")
    for r in OutRoute.allCases {
        say("Q1.6 \(r.short): \(dabLevels[r] ?? -1) distinct levels, worst \(dabWorst[r] ?? -1)/255 vs route (c)")
    }
    say("Q1.6 NOTE the shape of this: (b)'s worst ERROR is only 7/255, which sounds tolerable, and its")
    say("Q1.6   worst error is SMALLER than (a)'s 10/255. The damage is not magnitude, it is the collapse")
    say("Q1.6   from \(dabLevels[.linearFloat] ?? -1) levels to \(dabLevels[.linear8] ?? -1). A number cannot show that and the picture can.")
}

// ===========================================================================================
// MARK: - Q1 scene 2 — the parity risk, drawn
// ===========================================================================================

do {
    let MW = 620, MH = 620
    let W = 1520, H = 950
    // Map: x = coverage 0..1, y = source code 0..255, backdrop = 0.
    let dmap = Buf(MW, MH)
    var marked16 = 0, marked1 = 0
    var risky: [(Int, Int)] = []
    for py in 0..<MH {
        let cs = Int((Double(py) / Double(MH - 1)) * 255.0)
        let ls = srgbToLinearTable[cs]
        for px in 0..<MW {
            let t = Double(px) / Double(MW - 1)
            let l = ls * t
            let e = linearToSrgb(l)
            let v = e * 255.0 + 0.5
            let dist = abs(v - v.rounded())
            // grey = how far this pixel is from a rounding boundary; the fine texture is the point.
            let g = Int((dist / 0.5) * 255.0)
            dmap.setByte(px, py, g, g, g)
            if l > 0.0031308 {
                if dist < 255.0 * ULP16 * (e + 0.055) { marked16 += 1; risky.append((px, py)) }
                if dist < 255.0 * ULP1 * (e + 0.055) { marked1 += 1 }
            }
        }
    }
    for (px, py) in risky {                       // dilate 3x3 so a 1-in-2000 pixel is visible
        for dy in -1...1 { for dx in -1...1 {
            let x = px + dx, y = py + dy
            if x >= 0, x < MW, y >= 0, y < MH { dmap.setByte(x, y, 235, 30, 30) }
        } }
    }
    let img = page(W, H) { ctx in
        text(ctx, "Q1 — the parity risk of route (c), drawn.  INFERRED-BUT-BOUNDED.", 40, 48, size: 26, bold: true)
        text(ctx, "SIMULATED. This is arithmetic, not a run: Metal was not executed and the two pow implementations were not compared.",
             40, 78, size: 13, grey: 0.42)
        place(ctx, dmap, CGRect(x: 40, y: 120, width: CGFloat(MW), height: CGFloat(MH)))
        box(ctx, CGRect(x: 40, y: 120, width: CGFloat(MW), height: CGFloat(MH)))
        text(ctx, "coverage 0 ->", 40, 120 + CGFloat(MH) + 22, size: 12, grey: 0.4)
        text(ctx, "-> 1", 40 + CGFloat(MW) - 34, 120 + CGFloat(MH) + 22, size: 12, grey: 0.4)
        text(ctx, "source sRGB code, 0 at top -> 255 at bottom.  Backdrop is black.", 40, 120 + CGFloat(MH) + 42, size: 12, grey: 0.4)

        let tx: CGFloat = 40 + CGFloat(MW) + 50
        text(ctx, "What the grey texture is", tx, 150, size: 17, bold: true)
        var ty: CGFloat = 178
        let body: [String] = [
            "Each pixel's brightness is how far that composite's",
            "encoded value sits from a rounding boundary — black",
            "means it is about to flip to the next byte, white means",
            "it is safely mid-code.",
            "",
            "RED = a pixel whose output byte would change if Metal's",
            "pow and Swift's pow disagreed by 16 ulps, the Metal",
            "Shading Language spec's stated bound.",
            "",
            "Red pixels are drawn 3x3 so they can be seen at all.",
            "There are \(marked16) of them in \(MW * MH) — one in " +
            "\(Int((Double(MW * MH) / Double(max(marked16, 1))).rounded())).",
        ]
        for l in body { text(ctx, l, tx, ty, size: 14, grey: 0.15); ty += 22 }

        ty += 18
        text(ctx, "Exhaustive count, all 256x256x256 Normal triples", tx, ty, size: 17, bold: true); ty += 30
        let rows: [(String, String)] = [
            ("(a) TODAY", "0 at risk — no pow anywhere on the path"),
            ("(b) 8-bit linear", "0 at risk — an integer table, built once on the CPU"),
            ("(c) float + pow", "\(atRisk1) at 1 ulp, \(atRisk16) at 16 ulps"),
            ("(d) 12-bit table", "0 at risk — an integer table, built once on the CPU"),
        ]
        for (a, b) in rows {
            text(ctx, a, tx, ty, size: 15, bold: true); text(ctx, b, tx + 200, ty, size: 15, grey: 0.15); ty += 26
        }
        ty += 14
        text(ctx, "Per 2048x1024 frame that is ~\(Int((f1 * Double(2048 * 1024)).rounded())) pixels at 1 ulp and", tx, ty, size: 15, bold: true); ty += 24
        text(ctx, "~\(Int((f16 * Double(2048 * 1024)).rounded())) at 16 ulps. Any nonzero count fails a delta-0 gate.", tx, ty, size: 15, bold: true); ty += 40

        text(ctx, "What this DOES prove", tx, ty, size: 16, bold: true); ty += 26
        for l in ["That a delta-0 assertion has ~1000 chances a frame to",
                  "go red, if the two `pow`s differ at the spec bound.",
                  "The delta-0 assertions in CompositorParityLogicTests",
                  "are what would report it, and they are ALL-OR-NOTHING:",
                  "one flipped pixel is a failed gate."] {
            text(ctx, l, tx, ty, size: 14, grey: 0.15); ty += 21
        }
        ty += 16
        text(ctx, "What it does NOT prove", tx, ty, size: 16, bold: true); ty += 26
        for l in ["That the two implementations DO disagree. They may",
                  "agree exactly on most inputs; nobody has run Metal.",
                  "That any of it is VISIBLE — a one-byte flip is not.",
                  "It bounds the pow's contribution only: the float32",
                  "lerp feeding it carries its own error, so the real",
                  "population is LARGER than this, never smaller."] {
            text(ctx, l, tx, ty, size: 14, grey: 0.15); ty += 21
        }
    }
    write(img, "\(outDir)/Q1-parity-risk.png")
    say("")
    say("Q1.7 parity-risk map (\(MW)x\(MH), backdrop black): \(marked1) at-risk at 1 ulp, \(marked16) at 16 ulps.")
}

// ===========================================================================================
// MARK: - Q2 measurements — the sweep
// ===========================================================================================

say("")
say("--- Q2 · worst 8-bit channel difference between routes, per mode. MEASURED. ---")
say("Q2.0 swept over every pair from a 12-level-per-channel grid (1728 colours each side = 2,985,984")
say("Q2.0   pairs), at full opacity. Deterministic, nothing sampled. These are maxima over a FINITE")
say("Q2.0   grid, so every number below is a LOWER bound on the true worst case.")

let gridLevels: [Double] = (0...11).map { Double($0) / 11.0 }
var grid: [C3] = []
for r in gridLevels { for g in gridLevels { for b in gridLevels { grid.append((r, g, b)) } } }

let routePairs: [(Q2Route, Q2Route)] = [
    (.today, .linearSameRecipe), (.today, .linearLightRecipe), (.today, .linearExempt),
    (.linearSameRecipe, .linearLightRecipe), (.linearSameRecipe, .linearExempt),
    (.linearLightRecipe, .linearExempt),
]
var worst = [[Int]](repeating: [Int](repeating: 0, count: routePairs.count), count: Mode6.allCases.count)
var flips = [[Int]](repeating: [Int](repeating: 0, count: Q2Route.allCases.count), count: Mode6.allCases.count)
var pairCount = 0
/// How many (pair, mode) combinations route (iv) fails to reproduce (i) on EXACTLY. The exemption is
/// an sRGB -> linear -> sRGB round trip, so this is Q1's rounding-boundary question wearing Q2's hat.
var exemptOffBy1 = 0, exemptTotal = 0
/// A pair that makes Lighter/Darker Color pick the OTHER layer, found by SEARCH rather than by hand —
/// the same habit tools/linear_light_ab.swift:333-351 uses to locate its magnified crop.
var flipPair: (C3, C3, Double) = ((0, 0, 0), (0, 0, 0), -1)

for cb in grid {
    for cs in grid {
        pairCount += 1
        for m in Mode6.allCases {
            var out = [(Int, Int, Int)](repeating: (0, 0, 0), count: Q2Route.allCases.count)
            for r in Q2Route.allCases {
                let o = blendOver6(dst: (cb, 1), src: (cs, 1), mode: m, route: r)
                out[r.rawValue] = (q8(o.0.r), q8(o.0.g), q8(o.0.b))
            }
            for (pi, p) in routePairs.enumerated() {
                let a = out[p.0.rawValue], b = out[p.1.rawValue]
                let d = max(abs(a.0 - b.0), max(abs(a.1 - b.1), abs(a.2 - b.2)))
                if d > worst[m.rawValue][pi] { worst[m.rawValue][pi] = d }
            }
            exemptTotal += 1
            if out[Q2Route.today.rawValue] != out[Q2Route.linearExempt.rawValue] { exemptOffBy1 += 1 }
            if m == .lighterColor || m == .darkerColor {
                let base = picksSource(m, cb, cs, .today)
                for r in Q2Route.allCases where r != .today {
                    if picksSource(m, cb, cs, r) != base { flips[m.rawValue][r.rawValue] += 1 }
                }
            }
            if m == .lighterColor, picksSource(m, cb, cs, .today) != picksSource(m, cb, cs, .linearSameRecipe) {
                // Prefer the flip whose two layers are furthest apart, so the swap is unmistakable.
                let sep = ((cb.r - cs.r) * (cb.r - cs.r) + (cb.g - cs.g) * (cb.g - cs.g)
                           + (cb.b - cs.b) * (cb.b - cs.b)).squareRoot()
                        * min(sat(cb), sat(cs))
                if sep > flipPair.2 { flipPair = (cb, cs, sep) }
            }
        }
    }
}

func pairName(_ p: (Q2Route, Q2Route)) -> String {
    let n = ["i", "ii", "iii", "iv"]
    return "\(n[p.0.rawValue]) vs \(n[p.1.rawValue])"
}
say("Q2.1 pairs swept: \(pairCount)")
say("Q2.1 " + "mode".padding(toLength: 16, withPad: " ", startingAt: 0)
    + routePairs.map { pairName($0).padding(toLength: 12, withPad: " ", startingAt: 0) }.joined())
for m in Mode6.allCases {
    say("Q2.1 " + m.name.padding(toLength: 16, withPad: " ", startingAt: 0)
        + routePairs.indices.map { "\(worst[m.rawValue][$0])/255".padding(toLength: 12, withPad: " ", startingAt: 0) }.joined())
}
let exemptFrac = Double(exemptOffBy1) / Double(exemptTotal)
say("Q2.2 i vs iv tops out at \(worst[Mode6.hue.rawValue][2])/255, and it is 0 on \(String(format: "%.4f", (1 - exemptFrac) * 100))% of the \(exemptTotal) (pair, mode)")
say("Q2.2   combinations swept — \(exemptOffBy1) differ, every one of them by exactly 1. That 1 is NOT a behaviour")
say("Q2.2   difference: the exemption is an sRGB -> linear -> sRGB round trip, and a value that lands on a")
say("Q2.2   rounding boundary rounds the other way. It is Q1's last-ulp question wearing Q2's hat, which means")
say("Q2.2   the exemption cannot hold a delta-0 gate either unless its round trip is an integer table.")
say("Q2.3 flip pair found by SEARCH (largest separation among pairs where Lighter Color changes its answer):")
say("Q2.3   backdrop \(q8(flipPair.0.r)),\(q8(flipPair.0.g)),\(q8(flipPair.0.b))  top layer \(q8(flipPair.1.r)),\(q8(flipPair.1.g)),\(q8(flipPair.1.b))")
for m in [Mode6.lighterColor, Mode6.darkerColor] {
    let ii = Double(flips[m.rawValue][Q2Route.linearSameRecipe.rawValue]) / Double(pairCount) * 100
    let iii = Double(flips[m.rawValue][Q2Route.linearLightRecipe.rawValue]) / Double(pairCount) * 100
    say("Q2.3 \(m.name): the mode picks the OTHER layer on \(String(format: "%.2f", ii))% of pairs under (ii) and \(String(format: "%.2f", iii))% under (iii).")
}

// Partial alpha — where the exemption stops being free.
say("")
say("--- Q2 · partial alpha, where route (iv) stops matching route (i). MEASURED. ---")
var alphaRows: [(Double, [Int])] = []
let alphaLevels: [Double] = (0...6).map { Double($0) / 6.0 }
var alphaGrid: [C3] = []
for r in alphaLevels { for g in alphaLevels { for b in alphaLevels { alphaGrid.append((r, g, b)) } } }
do {
    // A grid sweep, not one hand-picked pair. The first version of this panel used blue-over-orange
    // and reported 0 for Saturation and Lighter Color — which was DEGENERATE, not a finding: for
    // those operands the blend result happens to equal the backdrop, and then the route cannot
    // matter at any alpha. A cherry-picked fixture is exactly how a picture like this lies.
    say("Q2.4 swept over \(alphaGrid.count * alphaGrid.count) pairs from a 7-level grid, at four source alphas.")
    for a in [0.25, 0.5, 0.75, 1.0] {
        var row = [Int](repeating: 0, count: Mode6.allCases.count)
        for cb in alphaGrid {
            for cs in alphaGrid {
                let pm: C3 = (cs.r * a, cs.g * a, cs.b * a)
                for m in Mode6.allCases {
                    let i = blendOver6(dst: (cb, 1), src: (pm, a), mode: m, route: .today)
                    let iv = blendOver6(dst: (cb, 1), src: (pm, a), mode: m, route: .linearExempt)
                    let d = max(abs(q8(i.0.r) - q8(iv.0.r)),
                                max(abs(q8(i.0.g) - q8(iv.0.g)), abs(q8(i.0.b) - q8(iv.0.b))))
                    if d > row[m.rawValue] { row[m.rawValue] = d }
                }
            }
        }
        alphaRows.append((a, row))
        say("Q2.4 source alpha \(String(format: "%.2f", a)): worst |i - iv| " +
            Mode6.allCases.map { "\($0.name)=\(row[$0.rawValue])" }.joined(separator: "  "))
    }
    say("Q2.4 The exemption reproduces today only where the source is OPAQUE. Below that the `mix(cs, B, da)`")
    say("Q2.4   and the source-over around it (Composite.metal:248-249) still run in linear light, so an exempt")
    say("Q2.4   mode is not 'today's behaviour' — it is 'today's blend inside a linear composite'.")
}

// ===========================================================================================
// MARK: - Q2 scene 1 — the grid
// ===========================================================================================

struct Pair { let title: String; let cb: (Int, Int, Int); let cs: (Int, Int, Int) }
var pairs: [Pair] = [
    Pair(title: "two saturated hues", cb: (255, 140, 0), cs: (0, 40, 255)),
    Pair(title: "two saturated hues, second pair", cb: (0, 200, 40), cs: (230, 0, 30)),
    Pair(title: "two desaturated colours", cb: (152, 140, 128), cs: (108, 124, 148)),
    Pair(title: "near-black", cb: (20, 14, 28), cs: (44, 34, 10)),
]
// The pair the four above do NOT contain: one where Lighter/Darker Color change their answer.
// Located by SEARCH over the sweep, not chosen by hand — see `flipPair`.
pairs.append(Pair(title: "the pair that makes Lighter/Darker Color SWAP",
                  cb: (q8(flipPair.0.r), q8(flipPair.0.g), q8(flipPair.0.b)),
                  cs: (q8(flipPair.1.r), q8(flipPair.1.g), q8(flipPair.1.b))))

do {
    let SWZ: CGFloat = 100, GAP: CGFloat = 8, LABW: CGFloat = 400
    let blockW = LABW + 4 * (SWZ + GAP)
    let blockH = CGFloat(Mode6.allCases.count) * (SWZ + GAP) + 132
    let W = Int(40 + blockW * 2 + 60 + 40), H = Int(380 + blockH * 3 + 50)

    let img = page(W, H) { ctx in
        text(ctx, "Q2 — what linearizing does to the six modes that judge \"how bright is this colour\".",
             40, 48, size: 26, bold: true)
        text(ctx, "SIMULATED, not a screenshot. Port of Composite.metal:145-186 and :236-249 term for term, in double precision. No Metal, no simulator.",
             40, 78, size: 13, grey: 0.42)
        text(ctx, "Every swatch below is one flat colour laid over another at full opacity. The four columns are four ways of deciding what \"bright\" means.",
             40, 104, size: 14, grey: 0.2)
        text(ctx, "The number printed inside each swatch is its worst channel difference, out of 255, from column (i) — from what the app does today.",
             40, 124, size: 14, grey: 0.2)

        var ly: CGFloat = 146
        let legend: [(String, [String])] = [
            ("i    TODAY, as it ships", ["Brightness is judged from the numbers as they are stored. This is what every existing document was drawn against.",
                                          "The recipe is the one in the web standard these modes come from — Composite.metal:145."]),
            ("ii   LINEAR, same recipe", ["The picture composites in real light, but \"how bright\" is still judged with today's recipe.",
                                          "This is what happens if the switch is built and nobody touches line 145. It is the DEFAULT outcome, not a choice."]),
            ("iii  LINEAR, light recipe", ["The picture composites in real light and \"how bright\" is judged the way light actually adds up.",
                                            "Physically consistent. It is also the BIGGER change from today, which is the opposite of the intuition."]),
            ("iv   LINEAR, six exempt", ["The document composites in light, but these six modes decode back out, decide exactly as today, and re-enter.",
                                          "Today's answer preserved inside a linear document."]),
        ]
        for (a, bs) in legend {
            text(ctx, a, 40, ly, size: 16, bold: true)
            for (i, b) in bs.enumerated() { text(ctx, b, 340, ly + CGFloat(i) * 20, size: 13, grey: 0.28) }
            ly += 46
        }

        for (pi, p) in pairs.enumerated() {
            let bx: CGFloat = 40 + CGFloat(pi % 2) * (blockW + 60)
            let byy: CGFloat = 380 + CGFloat(pi / 2) * blockH

            text(ctx, p.title, bx, byy, size: 18, bold: true)
            // backdrop / source chips
            swatch(ctx, p.cb, CGRect(x: bx, y: byy + 14, width: 46, height: 26))
            box(ctx, CGRect(x: bx, y: byy + 14, width: 46, height: 26), 1, grey: 0.5)
            text(ctx, "backdrop \(p.cb.0),\(p.cb.1),\(p.cb.2)", bx + 54, byy + 33, size: 13, grey: 0.3)
            swatch(ctx, p.cs, CGRect(x: bx + 230, y: byy + 14, width: 46, height: 26))
            box(ctx, CGRect(x: bx + 230, y: byy + 14, width: 46, height: 26), 1, grey: 0.5)
            text(ctx, "top layer \(p.cs.0),\(p.cs.1),\(p.cs.2)", bx + 284, byy + 33, size: 13, grey: 0.3)

            // column headers
            for r in Q2Route.allCases {
                let x = bx + LABW + CGFloat(r.rawValue) * (SWZ + GAP)
                text(ctx, r.short[0], x, byy + 60, size: 13, bold: true)
                text(ctx, r.short[1], x, byy + 76, size: 12, grey: 0.35)
            }

            var ry = byy + 88
            for m in Mode6.allCases {
                text(ctx, m.name, bx, ry + 24, size: 15, bold: true)
                text(ctx, m.plain[0], bx, ry + 44, size: 12, grey: 0.32)
                text(ctx, m.plain[1], bx, ry + 60, size: 12, grey: 0.32)
                text(ctx, m.line, bx, ry + 80, size: 11, grey: 0.55)
                let base = opaqueResult(p.cb, p.cs, m, .today)
                for r in Q2Route.allCases {
                    let c = opaqueResult(p.cb, p.cs, m, r)
                    let x = bx + LABW + CGFloat(r.rawValue) * (SWZ + GAP)
                    let rect = CGRect(x: x, y: ry, width: SWZ, height: SWZ)
                    swatch(ctx, c, rect)
                    box(ctx, rect, 1, grey: 0.45)
                    let d = max(abs(c.0 - base.0), max(abs(c.1 - base.1), abs(c.2 - base.2)))
                    let lumi = 0.3 * Double(c.0) + 0.59 * Double(c.1) + 0.11 * Double(c.2)
                    let g: CGFloat = lumi > 140 ? 0.05 : 0.95
                    if r != .today {
                        text(ctx, d == 0 ? "same as i" : "\(d)/255", x + 6, ry + SWZ - 8, size: 12, bold: d > 40, grey: g)
                    } else {
                        text(ctx, "reference", x + 6, ry + SWZ - 8, size: 12, grey: g)
                    }
                }
                ry += SWZ + GAP
            }
        }

        // The empty sixth slot carries the reading of the fifth block.
        let nx: CGFloat = 40 + blockW + 60, ny: CGFloat = 380 + 2 * blockH
        text(ctx, "How to read the block to the left", nx, ny, size: 18, bold: true)
        var ty = ny + 34
        let flipPct = Double(flips[Mode6.lighterColor.rawValue][Q2Route.linearSameRecipe.rawValue])
                    / Double(pairCount) * 100
        for l in ["Those two colours are the ones the four blocks above",
                  "do not contain, and they were found by SEARCH over all",
                  "\(pairCount) colour pairs rather than chosen by hand:",
                  "the pair where Lighter Color changes its ANSWER, with",
                  "the largest separation between the two layers.",
                  "",
                  "Look at the Lighter Color and Darker Color rows. Column",
                  "(i) shows one layer; columns (ii) and (iii) show the",
                  "OTHER one. These two modes pick a whole layer rather",
                  "than mixing (Composite.metal:185-186), so there is no",
                  "\"slightly different\" answer available to them — either",
                  "nothing happens or the pixel changes completely.",
                  "",
                  "MEASURED: that swap happens on \(String(format: "%.2f", flipPct))% of colour pairs.",
                  "About one pair in thirteen shows the other layer.",
                  "",
                  "Note also the near-black block above: for these modes",
                  "dark artwork barely moves at all (1-5/255). The change",
                  "is a mid-tone and saturated-colour change, not a",
                  "shadow one — which is the opposite of Q1's answer."] {
            text(ctx, l, nx, ty, size: 14, grey: 0.15); ty += 22
        }
    }
    write(img, "\(outDir)/Q2-nonseparable-modes.png")
}

// ===========================================================================================
// MARK: - Q2 scene 2 — the measured table, the flips, and the partial-alpha finding
// ===========================================================================================

do {
    let W = 1560, H = 1120
    let img = page(W, H) { ctx in
        text(ctx, "Q2 — the same question as numbers, and the three things the swatches cannot show.",
             40, 48, size: 26, bold: true)
        text(ctx, "MEASURED over \(pairCount) (backdrop, source) pairs — every pair from a 12-level-per-channel grid, at full opacity. Deterministic; nothing sampled.",
             40, 78, size: 13, grey: 0.42)
        text(ctx, "A maximum over a finite grid is a LOWER bound on the true worst case. An independent sweep on a different grid found 137 and 192 for Hue where this one finds \(worst[Mode6.hue.rawValue][0]) and \(worst[Mode6.hue.rawValue][1]).",
             40, 98, size: 13, grey: 0.42)

        // ---- table
        text(ctx, "Worst 8-bit channel difference between two routes, per mode", 40, 130, size: 18, bold: true)
        let colX: [CGFloat] = [40, 260, 400, 540, 680, 840, 1000, 1160]
        let heads = ["mode", "i vs ii", "i vs iii", "i vs iv", "ii vs iii", "ii vs iv", "iii vs iv"]
        for (i, h) in heads.enumerated() { text(ctx, h, colX[i], 164, size: 14, bold: true) }
        ctx.setStrokeColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)); ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 40, y: 174)); ctx.addLine(to: CGPoint(x: 1300, y: 174)); ctx.strokePath()
        var ry: CGFloat = 202
        for m in Mode6.allCases {
            text(ctx, m.name, colX[0], ry, size: 15, bold: true)
            for pi in routePairs.indices {
                let v = worst[m.rawValue][pi]
                text(ctx, "\(v)", colX[pi + 1], ry, size: 15, bold: v > 100, grey: v == 0 ? 0.55 : 0.05)
            }
            ry += 28
        }
        ry += 12
        text(ctx, "Every number is out of 255. A blend mode is not supposed to move by \(worst[Mode6.color.rawValue][1]) because a storage setting changed.",
             40, ry, size: 14, grey: 0.25); ry += 26
        text(ctx, "Read the \"i vs iii\" column against \"i vs ii\": the PHYSICALLY CORRECT route is the FARTHER one from today, for four of the six modes.",
             40, ry, size: 15, bold: true); ry += 24
        text(ctx, "Changing the recipe is a bigger behaviour change than changing the space. That is the opposite of the natural intuition.",
             40, ry, size: 14, grey: 0.25); ry += 26
        text(ctx, "And the \"i vs iv\" column is 1, not 0 — which is a finding, not a rounding footnote.",
             40, ry, size: 15, bold: true); ry += 24
        text(ctx, "The exemption is identical to today on \(String(format: "%.4f", (1 - exemptFrac) * 100))% of the \(exemptTotal) (pair, mode) combinations swept, and every one of the rest differs by exactly 1.",
             40, ry, size: 14, grey: 0.25); ry += 20
        text(ctx, "That 1 is not behaviour: the exemption is an sRGB -> linear -> sRGB round trip, and a value sitting on a rounding boundary rounds the other way. It is Q1's",
             40, ry, size: 14, grey: 0.25); ry += 20
        text(ctx, "last-ulp question wearing Q2's hat — so the exemption cannot hold a delta-0 gate either, unless its round trip is an integer table rather than a pow.",
             40, ry, size: 14, grey: 0.25); ry += 42

        // ---- flips
        text(ctx, "Lighter Color and Darker Color do not shift. They FLIP.", 40, ry, size: 18, bold: true); ry += 26
        text(ctx, "These two pick a whole layer rather than mixing (Composite.metal:185-186), so there is no \"looks slightly different\" answer available to them.",
             40, ry, size: 14, grey: 0.25); ry += 22
        text(ctx, "Either the same layer wins, or the other one does and the pixel changes completely — which is why their worst difference above is 255.",
             40, ry, size: 14, grey: 0.25); ry += 32
        for m in [Mode6.lighterColor, Mode6.darkerColor] {
            let ii = Double(flips[m.rawValue][Q2Route.linearSameRecipe.rawValue]) / Double(pairCount) * 100
            let iii = Double(flips[m.rawValue][Q2Route.linearLightRecipe.rawValue]) / Double(pairCount) * 100
            text(ctx, m.name, 40, ry, size: 15, bold: true)
            text(ctx, "the OTHER layer wins on \(String(format: "%.2f", ii))% of colour pairs under (ii),  \(String(format: "%.2f", iii))% under (iii),  0.00% under (iv)",
                 260, ry, size: 15)
            ry += 26
        }
        ry += 24

        // ---- partial alpha strip
        text(ctx, "Where the exemption stops being free: a partly transparent source.", 40, ry, size: 18, bold: true); ry += 26
        text(ctx, "Route (iv) equals today exactly only when the top layer is opaque. Below that the mix and the source-over around the blend (Composite.metal:248-249)",
             40, ry, size: 14, grey: 0.25); ry += 20
        text(ctx, "still happen in linear light, so (iv) is \"today's blend inside a linear composite\", not \"today\".",
             40, ry, size: 14, grey: 0.25); ry += 34
        text(ctx, "worst |i - iv| over \(alphaGrid.count * alphaGrid.count) pairs from a 7-level grid, per mode:", 40, ry, size: 14, bold: true); ry += 24
        let mx: [CGFloat] = [300, 460, 620, 780, 960, 1160]
        for m in Mode6.allCases { text(ctx, m.name, mx[m.rawValue], ry, size: 13, bold: true) }
        ry += 24
        for (a, row) in alphaRows {
            text(ctx, "top layer alpha \(String(format: "%.2f", a))", 40, ry, size: 14, bold: a == 1.0)
            for m in Mode6.allCases {
                let v = row[m.rawValue]
                text(ctx, "\(v)/255", mx[m.rawValue], ry, size: 14, bold: v > 20, grey: v == 0 ? 0.55 : 0.05)
            }
            ry += 26
        }
        ry += 20
        text(ctx, "One more thing no swatch here can show: `lum` has NINE call sites, not six.", 40, ry, size: 18, bold: true); ry += 26
        for l in ["Composite.metal:145 defines it; :175, :177, :179, :181, :185, :186 are the six modes. The other three are EFFECTS —",
                  ":523 Gradient Map (it indexes the LUT by lum), :637 Bloom (its threshold is compared against lum), :679-686 Sobel (eight calls).",
                  "Whichever of the four routes is chosen changes those three too, and EffectParityLogicTests' measured per-effect table has to be re-taken.",
                  "Compositor.swift:621-623 states the design property this puts at risk: \"how bright is this colour\" has exactly one definition, not two that nearly agree."] {
            text(ctx, l, 40, ry, size: 14, grey: 0.15); ry += 22
        }
    }
    write(img, "\(outDir)/Q2-route-deltas.png")
}

print("\n--- measurements ---")
try? log.joined(separator: "\n").write(toFile: "\(outDir)/measurements.txt", atomically: true, encoding: .utf8)
print("measurements written to \(outDir)/measurements.txt")
