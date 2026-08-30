// oklab_ramp_ab.swift — the picture for TODO.md item (10a), the Oklab colour ramps.
//
// **This compiles the shipped `ColorMath.swift` in, rather than porting it.** `linear_light_ab.swift`
// next door had to re-implement a Metal shader in Swift and say so loudly; this one does not, because
// `ColorMath` deliberately has no UIKit import and builds on the command line. So every ramp below is
// drawn by the same function the app calls. The only thing that is simulated is the drawing surface.
//
// Build and run (~15 s, no simulator, no xcodebuild):
//
//   swiftc -O tools/oklab_ramp_ab.swift PaintSoftware/Utilities/ColorMath.swift -o /tmp/okramp \
//     && /tmp/okramp docs/oklab-ramps
//
// It writes three PNGs and a measurements.txt. Every number quoted in
// `PaintSoftwareUITests/ColorMathOklabLogicTests.swift` and in `Effect.gradientColour`'s note is
// printed here.

import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

typealias RGB = (r: Double, g: Double, b: Double)

@inline(__always) func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }

/// The mix this feature replaced: a straight line through the three gamma-encoded channels.
func mixRGB(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    (r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
}

/// A straight line through linear light — not a candidate for the ramps, but the thing a UI gradient
/// might be doing between two stops without saying so, which is what the hue bar's density answers.
func mixLinearLight(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    func c(_ x: Double, _ y: Double) -> Double {
        ColorMath.linearToSRGB(ColorMath.srgbToLinear(x)
                               + (ColorMath.srgbToLinear(y) - ColorMath.srgbToLinear(x)) * t)
    }
    return (r: c(a.r, b.r), g: c(a.g, b.g), b: c(a.b, b.b))
}

func maxByteDelta(_ a: RGB, _ b: RGB) -> Int {
    max(abs(byte(a.r) - byte(b.r)), max(abs(byte(a.g) - byte(b.g)), abs(byte(a.b) - byte(b.b))))
}

/// How light a colour looks, 0 to 1 — Oklab's own lightness axis, used here only to put a number on
/// "the middle went dark".
func lightness(_ c: RGB) -> Double { ColorMath.rgbToOklab(r: c.r, g: c.g, b: c.b).L }

// MARK: - Page drawing

let mono = CTFontCreateWithName("Menlo" as CFString, 15, nil)
let monoBold = CTFontCreateWithName("Menlo-Bold" as CFString, 15, nil)

func text(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat,
          size: CGFloat = 15, bold: Bool = false, grey: CGFloat = 0.08) {
    let f = CTFontCreateCopyWithAttributes(bold ? monoBold : mono, size, nil, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(red: grey, green: grey, blue: grey, alpha: 1),
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
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)                       // y-down for everything below
    body(ctx)
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
    print("wrote \(path)")
}

/// One horizontal ramp, one screen pixel per column, drawn at 1:1 with no smoothing anywhere — the
/// colour in column x is `sample(x / (width - 1))` and nothing interpolates it.
func ramp(_ ctx: CGContext, _ rect: CGRect, _ sample: (Double) -> RGB) {
    let w = Int(rect.width)
    for i in 0..<w {
        let c = sample(Double(i) / Double(w - 1))
        ctx.setFillColor(CGColor(red: CGFloat(byte(c.r)) / 255, green: CGFloat(byte(c.g)) / 255,
                                 blue: CGFloat(byte(c.b)) / 255, alpha: 1))
        ctx.fill(CGRect(x: rect.minX + CGFloat(i), y: rect.minY, width: 1, height: rect.height))
    }
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
    ctx.setLineWidth(1)
    ctx.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
}

// MARK: - The pairs

let PAIRS: [(String, RGB, RGB)] = [
    ("orange to blue", (1, 0.549, 0), (0, 0.157, 1)),
    ("green to magenta", (0, 0.784, 0.157), (0.902, 0, 0.784)),
    ("red to cyan", (0.902, 0, 0.118), (0, 0.784, 0.902)),
    ("pure red to pure blue", (1, 0, 0), (0, 0, 1)),
]

var log: [String] = []
func note(_ s: String) { log.append(s); print(s) }

let BAR = 720, BARH = 62, LEFT = 150
/// Page width. Menlo advances 0.6 of its point size, so the longest line below — 114 characters at
/// 14pt starting at `LEFT` — needs 1108pt and the page is 1180. Text ran off the right edge at 910.
let PAGE = 1180
/// The hue-bar page indents further: its row labels are long enough to reach the bar at 150.
let LEFT3 = 330

// MARK: - 01: the ramps

func renderTheRamps(_ outDir: String) {
    let rowH = 24 + BARH + 6 + BARH + 34
    let h = 130 + rowH * PAIRS.count + 70
    let img = page(PAGE, h) { ctx in
        text(ctx, "COLOUR RAMPS: what a gradient between two strong colours does in the middle",
             40, 44, size: 20, bold: true)
        text(ctx, "Every bar is one screen pixel per column, shown at full size. Nothing here is scaled or smoothed.",
             40, 72, size: 14, grey: 0.3)
        text(ctx, "TOP of each pair = what the app did before. BOTTOM = what it does now.",
             40, 94, size: 14, grey: 0.3)

        var y: CGFloat = 130
        for (name, a, b) in PAIRS {
            let mid = 0.5
            let dipOld = lightness(mixRGB(a, b, mid))
            let dipNew = lightness(ColorMath.mixOklab(a, b, mid))
            var worst = 0
            for i in 0...255 {
                worst = max(worst, maxByteDelta(mixRGB(a, b, Double(i) / 255),
                                                ColorMath.mixOklab(a, b, Double(i) / 255)))
            }
            note(String(format: "%-22@  middle brightness: before %.2f, after %.2f (the ends average %.2f) — the ramp moves up to %d of 255",
                        name as NSString, dipOld, dipNew, (lightness(a) + lightness(b)) / 2, worst))

            text(ctx, name.uppercased(), 40, y + 16, size: 15, bold: true)
            ramp(ctx, CGRect(x: CGFloat(LEFT), y: y + 24, width: CGFloat(BAR), height: CGFloat(BARH))) {
                mixRGB(a, b, $0)
            }
            text(ctx, "before", 40, y + 24 + CGFloat(BARH) / 2 + 5, size: 14, grey: 0.35)
            ramp(ctx, CGRect(x: CGFloat(LEFT), y: y + 24 + CGFloat(BARH) + 6, width: CGFloat(BAR), height: CGFloat(BARH))) {
                ColorMath.mixOklab(a, b, $0)
            }
            text(ctx, "now", 40, y + 24 + CGFloat(BARH) * 1.5 + 11, size: 14, grey: 0.35)

            let pct = Int(((dipNew - dipOld) * 100).rounded())
            text(ctx, "The middle of the old bar is \(pct)% darker than the two ends suggest. The new bar's middle is where the eye expects it.",
                 CGFloat(LEFT), y + 24 + CGFloat(BARH) * 2 + 30, size: 14, grey: 0.2)
            y += CGFloat(rowH)
        }
        text(ctx, "The old middle is not just darker — it is greyer, because a colour halfway between two",
             40, y + 24, size: 14, grey: 0.2)
        text(ctx, "opposite hues has little of either left. Moving the mix out of the raw red/green/blue numbers",
             40, y + 44, size: 14, grey: 0.2)
        text(ctx, "fixes the darkness. It cannot invent colour that is not on the way between the two ends.",
             40, y + 64, size: 14, grey: 0.2)
    }
    write(img, "\(outDir)/01-the-ramps.png")
}

// MARK: - 02: the cost

func renderTheCost(_ outDir: String) {
    let img = page(PAGE, 640) { ctx in
        text(ctx, "THE COST: what this does to black-and-white", 40, 44, size: 20, bold: true)
        text(ctx, "The Gradient Map effect ships with a black-to-white ramp, which is how you turn a drawing grey.",
             40, 72, size: 14, grey: 0.3)
        text(ctx, "Making the middle of every ramp land where the eye expects also moves this one — it gets darker.",
             40, 94, size: 14, grey: 0.3)

        text(ctx, "BLACK TO WHITE", 40, 122, size: 15, bold: true)
        ramp(ctx, CGRect(x: CGFloat(LEFT), y: 130, width: CGFloat(BAR), height: CGFloat(BARH))) {
            mixRGB((0, 0, 0), (1, 1, 1), $0)
        }
        text(ctx, "before", 40, 168, size: 14, grey: 0.35)
        ramp(ctx, CGRect(x: CGFloat(LEFT), y: 130 + CGFloat(BARH) + 6, width: CGFloat(BAR), height: CGFloat(BARH))) {
            ColorMath.mixOklab((0, 0, 0), (1, 1, 1), $0)
        }
        text(ctx, "now", 40, 168 + CGFloat(BARH) + 6, size: 14, grey: 0.35)

        // Patch strip: nine input levels, before and after, with the numbers.
        var y: CGFloat = 300
        text(ctx, "The same thing as flat patches. Each column is one brightness going in:", 40, y - 14, size: 14, grey: 0.2)
        let cols = 9
        let cw = CGFloat(BAR) / CGFloat(cols)
        var worst = 0, worstAt = 0
        for i in 0...255 {
            let after = byte(ColorMath.mixOklab((0, 0, 0), (1, 1, 1), Double(i) / 255).r)
            if abs(after - i) > worst { worst = abs(after - i); worstAt = i }
        }
        note("black to white: the greyscale ramp is up to \(worst) of 255 darker, worst at input \(worstAt)")
        note("black to white: input 113 was 113, is now \(byte(ColorMath.mixOklab((0,0,0),(1,1,1), 113.0/255).r))")
        for c in 0..<cols {
            let t = Double(c + 1) / Double(cols + 1)
            let before = byte(t), after = byte(ColorMath.mixOklab((0, 0, 0), (1, 1, 1), t).r)
            let x = CGFloat(LEFT) + CGFloat(c) * cw
            ctx.setFillColor(CGColor(red: CGFloat(before) / 255, green: CGFloat(before) / 255, blue: CGFloat(before) / 255, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: cw - 4, height: 58))
            ctx.setFillColor(CGColor(red: CGFloat(after) / 255, green: CGFloat(after) / 255, blue: CGFloat(after) / 255, alpha: 1))
            ctx.fill(CGRect(x: x, y: y + 62, width: cw - 4, height: 58))
            text(ctx, "\(before)", x + 6, y + 138, size: 13, grey: 0.35)
            text(ctx, "\(after)", x + 6, y + 158, size: 13, grey: 0.35)
        }
        text(ctx, "before", 40, y + 34, size: 14, grey: 0.35)
        text(ctx, "now", 40, y + 96, size: 14, grey: 0.35)
        text(ctx, "was", 40, y + 138, size: 13, grey: 0.35)
        text(ctx, "is", 40, y + 158, size: 13, grey: 0.35)

        y += 200
        text(ctx, "This is the one place the change costs something rather than gaining something.",
             40, y, size: 15, bold: true)
        text(ctx, "A drawing put through a black-to-white Gradient Map used to come out with exactly the brightness",
             40, y + 28, size: 14, grey: 0.2)
        text(ctx, "it went in with. It now comes out with the brightness it *looks* like it went in with, which for",
             40, y + 50, size: 14, grey: 0.2)
        text(ctx, "the middle tones is up to \(worst) steps darker out of 255. Nothing else in the app changed — only this effect,",
             40, y + 72, size: 14, grey: 0.2)
        text(ctx, "and only when its two ends are grey. Say the word and the greys can be left exactly as they were.",
             40, y + 94, size: 14, grey: 0.2)
    }
    write(img, "\(outDir)/02-the-cost.png")
}

// MARK: - 03: the colour picker's hue bar

func renderTheHueBar(_ outDir: String) {
    let img = page(PAGE, 620) { ctx in
        text(ctx, "THE COLOUR PICKER'S HUE BAR", 40, 44, size: 20, bold: true)
        text(ctx, "The bar was built from seven colours with the system filling in between them. That is exact if the",
             40, 72, size: 14, grey: 0.3)
        text(ctx, "system fills in the way the picker's own maths does, and badly wrong if it fills in the other plausible",
             40, 94, size: 14, grey: 0.3)
        text(ctx, "way. Nobody documents which. It is now built from 73 colours, where the two answers agree.",
             40, 116, size: 14, grey: 0.3)

        func hue(_ t: Double) -> RGB { ColorMath.hsbToRGB(h: t, s: 1, v: 1) }
        func drawn(_ stops: [RGB], _ mix: @escaping (RGB, RGB, Double) -> RGB) -> (Double) -> RGB {
            { t in
                let n = stops.count
                let seg = min(Int(t * Double(n - 1)), n - 2)
                return mix(stops[seg], stops[seg + 1], t * Double(n - 1) - Double(seg))
            }
        }
        let seven = (0...6).map { hue(Double($0) / 6) }
        let dense = ColorMath.hueRail()

        var y: CGFloat = 160
        func row(_ label: String, _ sub: String, _ sample: @escaping (Double) -> RGB) {
            text(ctx, label, 40, y + 18, size: 14, bold: true)
            text(ctx, sub, 40, y + 38, size: 12, grey: 0.4)
            ramp(ctx, CGRect(x: CGFloat(LEFT3), y: y, width: CGFloat(BAR), height: 54), sample)
            var worst = 0
            for p in 0...2000 { worst = max(worst, maxByteDelta(sample(Double(p) / 2000), hue(Double(p) / 2000))) }
            text(ctx, worst == 0 ? "matches the picker exactly"
                                 : "up to \(worst) of 255 away from what the picker will actually paint",
                 CGFloat(LEFT3), y + 74, size: 13, grey: worst > 8 ? 0.1 : 0.35)
            note("hue bar — \(label): up to \(worst) of 255 from the picker's own colour")
            y += 100
        }
        row("7 colours, filled in one way", "the good case", drawn(seven, mixRGB))
        row("7 colours, filled in the other", "the case nobody rules out", drawn(seven, mixLinearLight))
        row("73 colours (what ships now)", "either way, same bar", drawn(dense, mixLinearLight))
        row("7 colours, smoothly blended", "prettier, and the wrong bar",
             drawn(seven, ColorMath.mixOklab))

        text(ctx, "The last bar is the interesting one: blending the seven corners smoothly gives a prettier strip that",
             40, y + 6, size: 14, grey: 0.2)
        text(ctx, "shows the wrong colours — up to 14 degrees around the wheel from the one the picker would paint at",
             40, y + 28, size: 14, grey: 0.2)
        text(ctx, "that spot. The bar's job is to be honest about the picker, so it samples rather than blends.",
             40, y + 50, size: 14, grey: 0.2)
    }
    write(img, "\(outDir)/03-the-hue-bar.png")
}

// MARK: - The numbers the tests quote

func printTheNumbersTheTestsQuote() {
    let corners = (0...6).map { ColorMath.hsbToRGB(h: Double($0) / 6, s: 1, v: 1) }
    var worstDeg = 0.0
    for p in 0...6000 {
        let t = Double(p) / 6000
        let seg = min(Int(t * 6), 5)
        let got = ColorMath.mixOklab(corners[seg], corners[seg + 1], t * 6 - Double(seg))
        let h = ColorMath.rgbToHSB(r: got.r, g: got.g, b: got.b)
        if max(got.r, max(got.g, got.b)) > min(got.r, min(got.g, got.b)) {
            var e = abs(h.h - t); e = min(e, 1 - e)
            worstDeg = max(worstDeg, e * 360)
        }
    }
    note(String(format: "hue bar — blending the corners is up to %.1f degrees of hue from the picker's own colour", worstDeg))

    for count in [7, 33, 49, 61, 73, 97] {
        let stops = ColorMath.hueRail(count: count)
        var eS = 0, eL = 0
        for p in 0...4000 {
            let t = Double(p) / 4000
            let seg = min(Int(t * Double(count - 1)), count - 2)
            let f = t * Double(count - 1) - Double(seg)
            let truth = ColorMath.hsbToRGB(h: t, s: 1, v: 1)
            eS = max(eS, maxByteDelta(mixRGB(stops[seg], stops[seg + 1], f), truth))
            eL = max(eL, maxByteDelta(mixLinearLight(stops[seg], stops[seg + 1], f), truth))
        }
        note("hue bar — \(count) stops: \(eS) of 255 filled in one way, \(eL) the other" +
             ((count - 1) % 6 == 0 ? "" : "   <- does not divide into sixths, so a straight piece crosses a corner"))
    }

    // The settings panel's gradient preview: how many stops a straight-line UI gradient needs before
    // it stops lying about the ramp. Two extra pairs beyond the four drawn above, because the bound
    // in `Effect.gradientPreviewSampleCount` is a worst case and the worst case is not on the poster.
    note("")
    let previewPairs = PAIRS + [("black to white", (0, 0, 0), (1, 1, 1)),
                                ("violet to cream", (0.1, 0, 0.3), (1, 0.95, 0.7)),
                                ("pure green to pure magenta", (0, 1, 0), (1, 0, 1))]
    for k in [2, 17, 33, 65, 129] {
        var wS = 0, wL = 0
        for (_, a, b) in previewPairs {
            let s = (0..<k).map { ColorMath.mixOklab(a, b, Double($0) / Double(k - 1)) }
            for p in 0...2000 {
                let t = Double(p) / 2000
                let truth = ColorMath.mixOklab(a, b, t)
                let seg = min(Int(t * Double(k - 1)), k - 2)
                let f = t * Double(k - 1) - Double(seg)
                wS = max(wS, maxByteDelta(mixRGB(s[seg], s[seg + 1], f), truth))
                wL = max(wL, maxByteDelta(mixLinearLight(s[seg], s[seg + 1], f), truth))
            }
        }
        note("gradient preview — \(k) stops: up to \(wS) of 255 from the real ramp filled in one way, \(wL) the other"
             + (k == 2 ? "   <- the two raw stops, which is what the preview used to be" : ""))
    }

    note("")
    note("EXHAUSTIVE: rgb -> Oklab -> rgb over all 16,777,216 8-bit triples")
    var mismatches = 0, worst = 0
    for r in 0...255 {
        for g in 0...255 {
            for b in 0...255 {
                let o = ColorMath.rgbToOklab(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
                let back = ColorMath.oklabToRGB(L: o.L, a: o.a, b: o.b)
                let d = max(abs(byte(back.r) - r), max(abs(byte(back.g) - g), abs(byte(back.b) - b)))
                if d > 0 { mismatches += 1; worst = max(worst, d) }
            }
        }
    }
    note("  triples that do not come back to the same byte: \(mismatches), worst by \(worst)")
}

@main
enum OklabRampAB {
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/oklab-ramps"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        renderTheRamps(outDir)
        renderTheCost(outDir)
        renderTheHueBar(outDir)
        printTheNumbersTheTestsQuote()
        try? log.joined(separator: "\n").write(toFile: "\(outDir)/measurements.txt",
                                               atomically: true, encoding: .utf8)
        print("wrote \(outDir)/measurements.txt")
    }
}
