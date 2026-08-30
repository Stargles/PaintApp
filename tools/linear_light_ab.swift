// linear_light_ab.swift — throwaway A/B renderer for TODO.md item (10).
//
// Simulates the app's compositing formula two ways and writes labelled PNGs:
//   A = exactly what `Composite.metal`'s `blendOver` computes today (sRGB-encoded, unlinearized)
//   B = the same formula with sRGB -> linear on the way in and linear -> sRGB on the way out
//
// This is NOT the app. It is a port of `blendOver` (Composite.metal:238-250) plus
// `blendChannels` (Composite.metal:187-234) into Swift, run over synthetic scenes.
// Antialiased coverage in scene 1 is produced by CoreGraphics itself, in a context configured
// exactly as `PixelOps.rasterizeUncached` configures its own (deviceRGB, premultipliedLast,
// 8 bpc), so the coverage values are the real ones and only the compositing step is simulated.
//
// Build and run:
//   swiftc -O tools/linear_light_ab.swift -o /tmp/llab && /tmp/llab <outdir>

import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

// MARK: - Transfer functions

@inline(__always) func srgbToLinear(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}
@inline(__always) func linearToSrgb(_ c: Double) -> Double {
    let x = max(0.0, min(1.0, c))
    return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1.0 / 2.4) - 0.055
}

// MARK: - The blend functions, ported term for term from Composite.metal

typealias C3 = (r: Double, g: Double, b: Double)

enum Mode { case normal, multiply, screen }

@inline(__always) func blendChannels(_ mode: Mode, _ cb: C3, _ cs: C3) -> C3 {
    switch mode {
    case .normal:   return cs                                   // `default: return cs`
    case .multiply: return (cb.r * cs.r, cb.g * cs.g, cb.b * cs.b)
    case .screen:   return (cb.r + cs.r - cb.r * cs.r,
                            cb.g + cs.g - cb.g * cs.g,
                            cb.b + cs.b - cb.b * cs.b)
    }
}

/// `blendOver` from Composite.metal, on premultiplied 0..1 values. `linear == true` inserts the
/// transfer functions around the colour arithmetic; alpha is coverage and is never linearized.
func blendOver(dst: (C3, Double), src: (C3, Double), mode: Mode, linear: Bool) -> (C3, Double) {
    let (dc, da) = dst, (sc, sa) = src
    // Unpremultiply, exactly as the shader does (`saturate(src.rgb / sa)`).
    var cs: C3 = sa > 0 ? (min(1, sc.r / sa), min(1, sc.g / sa), min(1, sc.b / sa)) : (0, 0, 0)
    var cb: C3 = da > 0 ? (min(1, dc.r / da), min(1, dc.g / da), min(1, dc.b / da)) : (0, 0, 0)
    if linear {
        cs = (srgbToLinear(cs.r), srgbToLinear(cs.g), srgbToLinear(cs.b))
        cb = (srgbToLinear(cb.r), srgbToLinear(cb.g), srgbToLinear(cb.b))
    }
    let bl = blendChannels(mode, cb, cs)
    // cr = mix(cs, B(cb, cs), da)
    let cr: C3 = (cs.r + (bl.r - cs.r) * da,
                  cs.g + (bl.g - cs.g) * da,
                  cs.b + (bl.b - cs.b) * da)
    let ao = da * (1 - sa) + sa
    // co = Cb_premul * (1 - as) + as * Cr, all in whichever domain we are in.
    let dpm: C3 = (cb.r * da, cb.g * da, cb.b * da)
    var co: C3 = (dpm.r * (1 - sa) + sa * cr.r,
                  dpm.g * (1 - sa) + sa * cr.g,
                  dpm.b * (1 - sa) + sa * cr.b)
    if linear {
        guard ao > 0 else { return ((0, 0, 0), 0) }
        let u: C3 = (co.r / ao, co.g / ao, co.b / ao)
        let e: C3 = (linearToSrgb(u.r), linearToSrgb(u.g), linearToSrgb(u.b))
        co = (e.r * ao, e.g * ao, e.b * ao)
    }
    return (co, ao)
}

// MARK: - 8-bit premultiplied RGBA buffer, row 0 = top (the app's convention)

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
    @inline(__always) func get(_ x: Int, _ y: Int) -> (C3, Double) {
        let i = (y * w + x) * 4
        return ((Double(px[i]) / 255, Double(px[i+1]) / 255, Double(px[i+2]) / 255),
                Double(px[i+3]) / 255)
    }
    @inline(__always) func set(_ x: Int, _ y: Int, _ v: (C3, Double)) {
        let i = (y * w + x) * 4
        px[i]   = UInt8(max(0, min(255, (v.0.r * 255).rounded())))
        px[i+1] = UInt8(max(0, min(255, (v.0.g * 255).rounded())))
        px[i+2] = UInt8(max(0, min(255, (v.0.b * 255).rounded())))
        px[i+3] = UInt8(max(0, min(255, (v.1 * 255).rounded())))
    }
    var cgImage: CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let data = CFDataCreate(nil, px, px.count)!
        let prov = CGDataProvider(data: data)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }
}

/// A CGContext over a Buf, configured exactly as `PixelOps` configures its own.
func context(over b: Buf) -> CGContext {
    let ctx = b.px.withUnsafeMutableBytes { raw -> CGContext in
        CGContext(data: raw.baseAddress, width: b.w, height: b.h, bitsPerComponent: 8,
                  bytesPerRow: b.w * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    ctx.setShouldAntialias(true)
    return ctx
}

/// Composite `src` over `dst` with the app's formula, returning a new buffer.
func composite(_ dst: Buf, _ src: Buf, mode: Mode, linear: Bool) -> Buf {
    let out = Buf(dst.w, dst.h)
    for y in 0..<dst.h {
        for x in 0..<dst.w {
            out.set(x, y, blendOver(dst: dst.get(x, y), src: src.get(x, y), mode: mode, linear: linear))
        }
    }
    return out
}

func maxDelta(_ a: Buf, _ b: Buf) -> (value: Int, x: Int, y: Int) {
    var best = 0, bx = 0, by = 0
    for y in 0..<a.h {
        for x in 0..<a.w {
            let i = (y * a.w + x) * 4
            for c in 0..<3 {
                let d = abs(Int(a.px[i+c]) - Int(b.px[i+c]))
                if d > best { best = d; bx = x; by = y }
            }
        }
    }
    return (best, bx, by)
}

/// `maxDelta` restricted to pixels where the *source* was fully covered (`interior`) or partly
/// covered (`edge`). Written because an assertion that a blend mode "changes the whole interior"
/// has to be measured rather than asserted — for Multiply and Screen it turned out to be small.
func maxDeltaSplit(_ a: Buf, _ b: Buf, src: Buf) -> (interior: Int, edge: Int) {
    var iBest = 0, eBest = 0
    for i in stride(from: 0, to: a.px.count, by: 4) {
        let sa = src.px[i + 3]
        if sa == 0 { continue }
        for c in 0..<3 {
            let d = abs(Int(a.px[i+c]) - Int(b.px[i+c]))
            if sa == 255 { if d > iBest { iBest = d } } else if d > eBest { eBest = d }
        }
    }
    return (iBest, eBest)
}

/// Per-channel |A - B| scaled by `amp`, on black.
func differenceMap(_ a: Buf, _ b: Buf, amp: Double) -> Buf {
    let out = Buf(a.w, a.h)
    for i in stride(from: 0, to: a.px.count, by: 4) {
        for c in 0..<3 {
            let d = abs(Double(a.px[i+c]) - Double(b.px[i+c])) * amp
            out.px[i+c] = UInt8(max(0, min(255, d.rounded())))
        }
        out.px[i+3] = 255
    }
    return out
}

// MARK: - Page assembly (y-down coordinates; the page context is flipped once)

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
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // page is flipped; un-flip glyphs
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
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)                                // y-down for the rest of this file
    body(ctx)
    return ctx.makeImage()!
}

func place(_ ctx: CGContext, _ b: Buf, _ r: CGRect, smooth: Bool = false) {
    ctx.saveGState()
    ctx.interpolationQuality = smooth ? .high : .none
    ctx.translateBy(x: 0, y: r.midY); ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -r.midY)
    ctx.draw(b.cgImage, in: r)
    ctx.restoreGState()
}

func write(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
    print("wrote \(path)")
}

// MARK: - Colours

let ORANGE: (UInt8, UInt8, UInt8) = (255, 140, 0)
let BLUE:   (UInt8, UInt8, UInt8) = (0, 40, 255)
let GREEN:  (UInt8, UInt8, UInt8) = (0, 200, 40)
let RED:    (UInt8, UInt8, UInt8) = (230, 0, 30)

func flat(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) -> Buf {
    Buf(w, h, fill: (c.0, c.1, c.2, 255))
}

// MARK: - Scene 1: antialiased edge (coverage produced by CoreGraphics, not by me)

/// A disc with a wedge cut out, drawn with CG antialiasing so the boundary carries real coverage.
func shapeLayer(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) -> Buf {
    let b = Buf(w, h)
    let ctx = context(over: b)
    ctx.setFillColor(CGColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                             blue: CGFloat(c.2) / 255, alpha: 1))
    let cx = CGFloat(w) / 2, cy = CGFloat(h) / 2, rr = CGFloat(min(w, h)) * 0.42
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rr, startAngle: 0.45, endAngle: 5.6, clockwise: false)
    ctx.addLine(to: CGPoint(x: cx, y: cy))
    ctx.fillPath()
    // A shallow diagonal bar: the near-horizontal edge is where coverage is most gradual.
    ctx.move(to: CGPoint(x: 0, y: CGFloat(h) * 0.10))
    ctx.addLine(to: CGPoint(x: CGFloat(w), y: CGFloat(h) * 0.24))
    ctx.addLine(to: CGPoint(x: CGFloat(w), y: CGFloat(h) * 0.14))
    ctx.addLine(to: CGPoint(x: 0, y: 0))
    ctx.closePath()
    ctx.fillPath()
    return b
}

// MARK: - Scene 2: a soft feathered dab

func softDab(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) -> Buf {
    let b = Buf(w, h)
    let cx = Double(w) / 2, cy = Double(h) / 2, rr = Double(min(w, h)) * 0.46
    for y in 0..<h {
        for x in 0..<w {
            let d = (pow(Double(x) + 0.5 - cx, 2) + pow(Double(y) + 0.5 - cy, 2)).squareRoot() / rr
            // A smooth falloff over the whole radius: the transition is ~150 px wide, which is what
            // an artist's soft brush actually lays down.
            let a = d >= 1 ? 0 : pow(1 - d, 1.6)
            b.set(x, y, ((Double(c.0) / 255 * a, Double(c.1) / 255 * a, Double(c.2) / 255 * a), a))
        }
    }
    return b
}

// MARK: - Scene 3: a coverage ramp, which is exactly a hue-to-hue gradient

func ramp(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) -> Buf {
    let b = Buf(w, h)
    for y in 0..<h {
        for x in 0..<w {
            let a = Double(x) / Double(w - 1)
            b.set(x, y, ((Double(c.0) / 255 * a, Double(c.1) / 255 * a, Double(c.2) / 255 * a), a))
        }
    }
    return b
}

// MARK: - Main

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
var log: [String] = []

// ---------- Scene 1 ----------
do {
    let S = 460
    let pairs: [(String, (UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8))] = [
        ("blue on orange", BLUE, ORANGE), ("red on green", RED, GREEN)
    ]
    let W = 60 + S * 2 + 40 + 100, H = 150 + S + 48 + 26 * 9 + 100
    let img = page(W, H) { ctx in
        text(ctx, "SCENE 1 — the antialiased edge.  Same shape, same coverage, two composites.",
             40, 46, size: 22, bold: true)
        text(ctx, "Coverage is produced by CoreGraphics with antialiasing on, in a deviceRGB / premultipliedLast context —", 40, 76, size: 14, grey: 0.35)
        text(ctx, "the same configuration PixelOps.rasterizeUncached uses. Only the compositing step is simulated.", 40, 96, size: 14, grey: 0.35)
        for (i, p) in pairs.enumerated() {
            let x = CGFloat(40 + i * (S + 40))
            let bg = flat(S, S, p.2), sh = shapeLayer(S, S, p.1)
            let a = composite(bg, sh, mode: .normal, linear: false)
            let b = composite(bg, sh, mode: .normal, linear: true)
            let d = maxDelta(a, b)
            log.append("scene1 \(p.0): max channel delta \(d.value) at (\(d.x),\(d.y))")
            place(ctx, a, CGRect(x: x, y: 150, width: CGFloat(S) / 2, height: CGFloat(S)))
            // Right half of the tile is B, so the seam runs straight through the edge itself.
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x + CGFloat(S) / 2, y: 150, width: CGFloat(S) / 2, height: CGFloat(S)))
            place(ctx, b, CGRect(x: x, y: 150, width: CGFloat(S), height: CGFloat(S)))
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: x, y: 150, width: CGFloat(S), height: CGFloat(S)))
            ctx.move(to: CGPoint(x: x + CGFloat(S) / 2, y: 150))
            ctx.addLine(to: CGPoint(x: x + CGFloat(S) / 2, y: 150 + CGFloat(S)))
            ctx.strokePath()
            text(ctx, "A: TODAY (sRGB)", x + 8, 144, size: 15, bold: true)
            text(ctx, "B: LINEAR", x + CGFloat(S) / 2 + 8, 144, size: 15, bold: true)
            text(ctx, "\(p.0) — worst channel difference \(d.value)/255", x, 150 + CGFloat(S) + 26, size: 16, bold: true)

            // Magnified inset: the N x N window holding the most partial-coverage pixels, found by
            // search rather than by hand — a hand-picked crop is how a picture like this lies.
            let N = 26, Z = 9
            var ix = 0, iy = 0, bestCount = -1
            var yy = 0
            while yy + N < S {
                var xx = 0
                while xx + N < S {
                    var c = 0
                    for py in stride(from: yy, to: yy + N, by: 2) {
                        for px in stride(from: xx, to: xx + N, by: 2) {
                            let a = sh.px[(py * S + px) * 4 + 3]
                            if a > 0 && a < 255 { c += 1 }
                        }
                    }
                    if c > bestCount { bestCount = c; ix = xx; iy = yy }
                    xx += 4
                }
                yy += 4
            }
            func crop(_ src: Buf) -> Buf {
                let c = Buf(N, N)
                for yy in 0..<N { for xx in 0..<N {
                    let si = ((iy + yy) * src.w + ix + xx) * 4, di = (yy * N + xx) * 4
                    for k in 0..<4 { c.px[di+k] = src.px[si+k] }
                } }
                return c
            }
            let zw = CGFloat(N * Z), iyTop = 150 + CGFloat(S) + 48
            place(ctx, crop(a), CGRect(x: x, y: iyTop, width: zw, height: zw))
            place(ctx, crop(b), CGRect(x: x + zw + 10, y: iyTop, width: zw, height: zw))
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: x, y: iyTop, width: zw, height: zw))
            ctx.stroke(CGRect(x: x + zw + 10, y: iyTop, width: zw, height: zw))
            text(ctx, "A at 9x", x, iyTop + zw + 22, size: 14)
            text(ctx, "B at 9x — same px", x + zw + 10, iyTop + zw + 22, size: 14)
            if i == 1 {
                text(ctx, "Each window is the \(N)x\(N) crop holding the most partial-coverage pixels in its tile, located by search rather than by hand.",
                     40, iyTop + zw + 50, size: 14, grey: 0.35)
                text(ctx, "Fully-covered interiors are identical in A and B by construction — source-over at coverage 1 is a copy, in either domain.",
                     40, iyTop + zw + 72, size: 14, grey: 0.35)
            }
        }
    }
    write(img, "\(outDir)/01-antialiased-edge.png")
}

// ---------- Scene 2 ----------
do {
    let S = 440
    let W = 40 * 3 + S * 2 + 80, H = 150 + S + 130
    let img = page(W, H) { ctx in
        text(ctx, "SCENE 2 — a soft brush dab, the case an artist actually paints.", 40, 46, size: 22, bold: true)
        text(ctx, "Radial coverage falloff over the whole radius, so the transition is ~200 px wide rather than one pixel.", 40, 80, size: 14, grey: 0.35)
        let pairs: [(String, (UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8))] =
            [("blue dab on orange", BLUE, ORANGE), ("red dab on green", RED, GREEN)]
        for (i, p) in pairs.enumerated() {
            let x = CGFloat(40 + i * (S + 40))
            let bg = flat(S, S, p.2), dab = softDab(S, S, p.1)
            let a = composite(bg, dab, mode: .normal, linear: false)
            let b = composite(bg, dab, mode: .normal, linear: true)
            let d = maxDelta(a, b)
            log.append("scene2 \(p.0): max channel delta \(d.value) at (\(d.x),\(d.y))")
            place(ctx, a, CGRect(x: x, y: 150, width: CGFloat(S) / 2, height: CGFloat(S)))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x + CGFloat(S) / 2, y: 150, width: CGFloat(S) / 2, height: CGFloat(S)))
            place(ctx, b, CGRect(x: x, y: 150, width: CGFloat(S), height: CGFloat(S)))
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: x, y: 150, width: CGFloat(S), height: CGFloat(S)))
            ctx.move(to: CGPoint(x: x + CGFloat(S) / 2, y: 150))
            ctx.addLine(to: CGPoint(x: x + CGFloat(S) / 2, y: 150 + CGFloat(S))); ctx.strokePath()
            text(ctx, "A: TODAY (sRGB)", x + 8, 144, size: 15, bold: true)
            text(ctx, "B: LINEAR", x + CGFloat(S) / 2 + 8, 144, size: 15, bold: true)
            text(ctx, "\(p.0) — worst \(d.value)/255", x, 150 + CGFloat(S) + 30, size: 16, bold: true)
        }
        text(ctx, "The dark ring on every A half is the symptom. It is not in the artwork: it is what averaging two saturated hues in sRGB",
             40, 150 + CGFloat(S) + 62, size: 14, grey: 0.2)
        text(ctx, "produces where the coverage is partial. B, the same coverage averaged in linear light, has no ring at all.",
             40, 150 + CGFloat(S) + 84, size: 14, grey: 0.2)
    }
    write(img, "\(outDir)/02-soft-brush-dab.png")
}

// ---------- Scene 3 ----------
do {
    let W0 = 1180, BH = 110
    let pairs: [(String, (UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8))] = [
        ("orange -> blue", BLUE, ORANGE), ("green -> red", RED, GREEN),
        ("cyan -> red", (230, 0, 30), (0, 190, 210)), ("yellow -> violet", (140, 0, 220), (255, 225, 0))
    ]
    let H = 170 + pairs.count * (BH * 2 + 62) + 40
    let img = page(W0 + 80, H) { ctx in
        text(ctx, "SCENE 3 — a coverage ramp between two saturated hues. \"Muddy through the middle\".",
             40, 46, size: 22, bold: true)
        text(ctx, "Source-over at coverage t of A onto opaque B is exactly lerp(B, A, t) — so this band is both the", 40, 78, size: 14, grey: 0.35)
        text(ctx, "gradient case and the coverage case. Only the pixel width differs from scenes 1 and 2.", 40, 98, size: 14, grey: 0.35)
        var y: CGFloat = 170
        for p in pairs {
            let bg = flat(W0, BH, p.2), rp = ramp(W0, BH, p.1)
            let a = composite(bg, rp, mode: .normal, linear: false)
            let b = composite(bg, rp, mode: .normal, linear: true)
            let d = maxDelta(a, b)
            log.append("scene3 \(p.0): max channel delta \(d.value) at (\(d.x),\(d.y)) i.e. t=\(String(format: "%.3f", Double(d.x) / Double(W0 - 1)))")
            place(ctx, a, CGRect(x: 40, y: y, width: CGFloat(W0), height: CGFloat(BH)))
            place(ctx, b, CGRect(x: 40, y: y + CGFloat(BH), width: CGFloat(W0), height: CGFloat(BH)))
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: 40, y: y, width: CGFloat(W0), height: CGFloat(BH * 2)))
            ctx.move(to: CGPoint(x: 40, y: y + CGFloat(BH)))
            ctx.addLine(to: CGPoint(x: 40 + CGFloat(W0), y: y + CGFloat(BH))); ctx.strokePath()
            text(ctx, "A TODAY", 48, y + 22, size: 14, bold: true, grey: 1)
            text(ctx, "B LINEAR", 48, y + CGFloat(BH) + 22, size: 14, bold: true, grey: 1)
            // Mark where the two disagree most.
            let mx = 40 + CGFloat(d.x)
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: mx, y: y - 6)); ctx.addLine(to: CGPoint(x: mx, y: y)); ctx.strokePath()
            text(ctx, "\(p.0) — worst channel difference \(d.value)/255 at coverage \(String(format: "%.2f", Double(d.x) / Double(W0 - 1))) (marked)",
                 40, y + CGFloat(BH * 2) + 26, size: 16, bold: true)
            y += CGFloat(BH * 2) + 62
        }
    }
    write(img, "\(outDir)/03-hue-ramp.png")
}

// ---------- Scene 4: the control, and the cost ----------
do {
    let W = 1560, H = 880
    let img = page(W, H) { ctx in
        text(ctx, "SCENE 4 — the grey control. What linearizing does where there is no hue at all.",
             40, 46, size: 22, bold: true)
        text(ctx, "This is the cost side of the picture: linearizing changes every existing composite, not only the muddy ones.",
             40, 78, size: 14, grey: 0.35)

        // (a) The physical reference: a 1px checker averages to linear 0.5.
        text(ctx, "(a) Which grey is physically half the light of white?  View this from across the room.",
             40, 132, size: 17, bold: true)
        let CH = 190
        let chk = Buf(CH, CH)
        for y in 0..<CH { for x in 0..<CH {
            let v: UInt8 = (x + y) % 2 == 0 ? 255 : 0
            let i = (y * CH + x) * 4
            chk.px[i] = v; chk.px[i+1] = v; chk.px[i+2] = v; chk.px[i+3] = 255
        } }
        place(ctx, chk, CGRect(x: 40, y: 155, width: CGFloat(CH), height: CGFloat(CH)))
        place(ctx, Buf(CH, CH, fill: (128, 128, 128, 255)), CGRect(x: 40 + CGFloat(CH) + 20, y: 155, width: CGFloat(CH), height: CGFloat(CH)))
        place(ctx, Buf(CH, CH, fill: (188, 188, 188, 255)), CGRect(x: 40 + CGFloat(CH) * 2 + 40, y: 155, width: CGFloat(CH), height: CGFloat(CH)))
        text(ctx, "1px black/white checker", 40, 155 + CGFloat(CH) + 24, size: 14)
        text(ctx, "flat sRGB 128  <- TODAY", 40 + CGFloat(CH) + 20, 155 + CGFloat(CH) + 24, size: 14, bold: true)
        text(ctx, "flat sRGB 188  <- LINEAR", 40 + CGFloat(CH) * 2 + 40, 155 + CGFloat(CH) + 24, size: 14, bold: true)
        let px0 = 40 + CGFloat(CH) * 3 + 70
        text(ctx, "The checker is genuinely half the light of white.", px0, 190, size: 14, grey: 0.2)
        text(ctx, "Whichever patch it matches from a distance is the one", px0, 214, size: 14, grey: 0.2)
        text(ctx, "that is physically right for a half-covered pixel.", px0, 238, size: 14, grey: 0.2)
        text(ctx, "That is the whole case for linear light — and it is also", px0, 272, size: 14, grey: 0.2)
        text(ctx, "the whole cost, because the app has produced 128 for", px0, 296, size: 14, grey: 0.2)
        text(ctx, "every such pixel it has ever drawn.", px0, 320, size: 14, grey: 0.2)

        // (b) Existing artwork: black over white at a range of coverages.
        text(ctx, "(b) Every antialiased grey edge in existing artwork: black over white, by coverage.",
             40, 450, size: 17, bold: true)
        text(ctx, "coverage of the black source ->", 40, 478, size: 13, grey: 0.4)
        let n = 11, sw = 108, sh = 118, top: CGFloat = 520
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let x = CGFloat(40 + i * sw)
            let today = UInt8(((1 - t) * 255).rounded())
            let lin = UInt8((linearToSrgb(1 - t) * 255).rounded())
            place(ctx, Buf(sw - 6, sh, fill: (today, today, today, 255)), CGRect(x: x, y: top, width: CGFloat(sw - 6), height: CGFloat(sh)))
            place(ctx, Buf(sw - 6, sh, fill: (lin, lin, lin, 255)), CGRect(x: x, y: top + CGFloat(sh), width: CGFloat(sw - 6), height: CGFloat(sh)))
            text(ctx, String(format: "%.1f", t), x + 30, top - 12, size: 13)
            text(ctx, "\(today)", x + 30, top + CGFloat(sh) - 12, size: 13, grey: t > 0.55 ? 1 : 0.05)
            text(ctx, "\(lin)", x + 30, top + CGFloat(sh) * 2 - 12, size: 13, grey: lin < 110 ? 1 : 0.05)
            if i == 0 { log.append("scene4 delta table:") }
            log.append("  coverage \(String(format: "%.1f", t)): today \(today) -> linear \(lin)  (delta \(Int(lin) - Int(today)))")
        }
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: 40, y: top, width: CGFloat(n * sw - 6), height: CGFloat(sh * 2)))
        text(ctx, "TODAY", 40 + CGFloat(n * sw) + 10, top + 60, size: 15, bold: true)
        text(ctx, "LINEAR", 40 + CGFloat(n * sw) + 10, top + CGFloat(sh) + 60, size: 15, bold: true)
        text(ctx, "Every one of these gets lighter, by up to 73/255. A hairline stroke, a piece of antialiased text and every soft edge",
             40, top + CGFloat(sh * 2) + 42, size: 15, grey: 0.15)
        text(ctx, "already on the owner's iPad would read thinner and paler after the change — reopening a finished drawing changes it.",
             40, top + CGFloat(sh * 2) + 66, size: 15, grey: 0.15)
    }
    write(img, "\(outDir)/04-grey-control.png")
}

// ---------- Scene 5: difference maps + Multiply/Screen ----------
do {
    let S = 400, AMP = 3.0
    let W = 40 * 4 + S * 3 + 140, H = 150 + S + 60 + S + 110
    let img = page(W, H) { ctx in
        text(ctx, "SCENE 5 — difference maps, and two blend modes other than Normal.", 40, 46, size: 22, bold: true)
        text(ctx, "Top row: |A - B| per channel, amplified 3x, on black. Black means the change is invisible there.",
             40, 78, size: 14, grey: 0.35)
        text(ctx, "Bottom row: Multiply and Screen. Their interiors are the one place a blend mode could change where coverage is full.",
             40, 98, size: 14, grey: 0.35)

        let bg1 = flat(S, S, ORANGE), sh1 = shapeLayer(S, S, BLUE)
        let a1 = composite(bg1, sh1, mode: .normal, linear: false)
        let b1 = composite(bg1, sh1, mode: .normal, linear: true)
        let bg2 = flat(S, S, ORANGE), d2 = softDab(S, S, BLUE)
        let a2 = composite(bg2, d2, mode: .normal, linear: false)
        let b2 = composite(bg2, d2, mode: .normal, linear: true)
        let rp = ramp(S, S, BLUE)
        let a3 = composite(bg1, rp, mode: .normal, linear: false)
        let b3 = composite(bg1, rp, mode: .normal, linear: true)

        let maps = [("hard edge (scene 1)", a1, b1), ("soft dab (scene 2)", a2, b2), ("ramp (scene 3)", a3, b3)]
        for (i, m) in maps.enumerated() {
            let x = CGFloat(40 + i * (S + 40))
            place(ctx, differenceMap(m.1, m.2, amp: AMP), CGRect(x: x, y: 150, width: CGFloat(S), height: CGFloat(S)))
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: x, y: 150, width: CGFloat(S), height: CGFloat(S)))
            let d = maxDelta(m.1, m.2)
            text(ctx, "\(m.0) — |A-B| x\(Int(AMP)), peak \(d.value)/255", x, 150 + CGFloat(S) + 26, size: 15, bold: true)
        }

        // Multiply and Screen: a half-covered blue layer over orange.
        var y = CGFloat(150 + S + 60)
        let modes: [(String, Mode)] = [("Multiply", .multiply), ("Screen", .screen)]
        for (i, m) in modes.enumerated() {
            let x = CGFloat(40 + i * (S + 40))
            let src = shapeLayer(S, S, BLUE)
            let a = composite(bg1, src, mode: m.1, linear: false)
            let b = composite(bg1, src, mode: m.1, linear: true)
            let d = maxDelta(a, b)
            let sp = maxDeltaSplit(a, b, src: src)
            log.append("scene5 \(m.0) blue-on-orange: max delta \(d.value) at (\(d.x),\(d.y)) — interior \(sp.interior), edge \(sp.edge)")
            place(ctx, a, CGRect(x: x, y: y, width: CGFloat(S) / 2, height: CGFloat(S)))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x + CGFloat(S) / 2, y: y, width: CGFloat(S) / 2, height: CGFloat(S)))
            place(ctx, b, CGRect(x: x, y: y, width: CGFloat(S), height: CGFloat(S)))
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: x, y: y, width: CGFloat(S), height: CGFloat(S)))
            ctx.move(to: CGPoint(x: x + CGFloat(S) / 2, y: y))
            ctx.addLine(to: CGPoint(x: x + CGFloat(S) / 2, y: y + CGFloat(S))); ctx.strokePath()
            text(ctx, "A TODAY", x + 8, y + 22, size: 14, bold: true, grey: 1)
            text(ctx, "B LINEAR", x + CGFloat(S) / 2 + 8, y + 22, size: 14, bold: true, grey: 1)
            text(ctx, "\(m.0) — interior \(sp.interior)/255, edge \(sp.edge)/255", x, y + CGFloat(S) + 26, size: 16, bold: true)
            let px = CGFloat(40 + 2 * (S + 40))
            if i == 0 {
                text(ctx, "MEASURED, and it refutes the obvious guess: the filled", px, y + 30, size: 14, grey: 0.15)
                text(ctx, "interiors move by only \(sp.interior)/255 under Multiply here,", px, y + 52, size: 14, grey: 0.15)
                text(ctx, "because both operands land near black either way.", px, y + 74, size: 14, grey: 0.15)
            } else {
                text(ctx, "Screen's interior moves \(sp.interior)/255 — real but small.", px, y + 110, size: 14, grey: 0.15)
                text(ctx, "The large numbers stay where they were in scenes 1-3:", px, y + 144, size: 14, grey: 0.15)
                text(ctx, "at partial coverage, \(sp.edge)/255. Even for a blend mode,", px, y + 166, size: 14, grey: 0.15)
                text(ctx, "this is an edge-and-gradient effect, not a fills effect.", px, y + 188, size: 14, grey: 0.15)
            }
        }
    }
    write(img, "\(outDir)/05-difference-and-blend-modes.png")
}

// ---------- Worst case over the whole 8-bit domain, Normal ----------
do {
    var worst = 0, wa = 0, wb = 0, wt = 0.0
    // Every (backdrop, source) 8-bit channel pair against every 1/255 coverage step: source-over on
    // one channel is lerp, so this is the exhaustive answer for Normal.
    for cb in 0...255 {
        for cs in 0...255 {
            let lb = srgbToLinear(Double(cb) / 255), ls = srgbToLinear(Double(cs) / 255)
            for i in 0...255 {
                let t = Double(i) / 255
                let today = ((Double(cb) / 255) * (1 - t) + (Double(cs) / 255) * t) * 255
                let lin = linearToSrgb(lb * (1 - t) + ls * t) * 255
                let d = Int(abs(today.rounded() - lin.rounded()))
                if d > worst { worst = d; wa = cb; wb = cs; wt = t }
            }
        }
    }
    log.append("EXHAUSTIVE (Normal, one channel): worst 8-bit delta \(worst), backdrop \(wa), source \(wb), coverage \(String(format: "%.3f", wt))")
}

print("\n--- measurements ---")
for l in log { print(l) }
try? log.joined(separator: "\n").write(toFile: "\(outDir)/measurements.txt", atomically: true, encoding: .utf8)
