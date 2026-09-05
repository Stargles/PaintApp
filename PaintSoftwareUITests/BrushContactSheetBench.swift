import XCTest
import UIKit
import CoreGraphics

/// **BRUSH.md §12 stage 9's contact sheet — the deliverable the owner judges.**
///
/// §12 stage 9 is *driven by contact sheet at the owner's instruction*: the candidates are rendered
/// through the real `BrushStamper`, the owner picks and adjusts, and only then are presets authored.
/// So what this produces is not a preview of a decision already taken — it **is** the decision's
/// input, and it is the same loop that settled §8.4, where an offline prototype running the
/// stamper's own walk refuted the tip-texture design for the rough ink nib.
///
/// **Every stroke on the sheet is a real `BrushStamper.stampStroke`** into a `CGContextDabTarget`,
/// which is the one call every tier funnels into. Nothing here re-implements a dab, a spacing or a
/// modulation — if the sheet is wrong, the app is wrong in the same way, which is the only property
/// that makes a picture worth ruling from.
///
/// **Not a `*LogicTests` file, deliberately, and gated on top of that.** The fast tier's selector is
/// `LogicTests$|CharacterizationTests$|^PerfBaselineTests$`, so the filename keeps this out of it —
/// which is how `DabCostBench` stays out. The filename alone is not enough here, because the **full**
/// suite runs every class and this one writes files; so it also carries `StrokeDensityBench`'s env
/// gate. Note the `TEST_RUNNER_` prefix, which is not decoration: `xcodebuild` forwards
/// `TEST_RUNNER_`-prefixed variables to the runner **with the prefix stripped**, and a gate written
/// without it skips under a green banner forever.
///
/// ```
/// TEST_RUNNER_PAINTAPP_TIPSHEET=1 \
/// TEST_RUNNER_PAINTAPP_TIPSHEET_DIR=/path/to/output \
/// tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
///   -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/BrushContactSheetBench \
///   -parallel-testing-enabled NO -derivedDataPath build/DerivedData
/// ```
final class BrushContactSheetBench: XCTestCase {

    // MARK: - Page geometry

    private static let pageWidth: CGFloat = 1120
    private static let rowHeight: CGFloat = 172
    private static let headerHeight: CGFloat = 58
    private static let margin: CGFloat = 20

    private static let swatchX: CGFloat = 20
    private static let swatchSide: CGFloat = 84
    private static let textX: CGFloat = 116
    private static let textWidth: CGFloat = 320
    private static let dabX: CGFloat = 448
    private static let dabWidth: CGFloat = 88
    private static let strokeX: CGFloat = 546
    /// **Two strokes per row, side by side**, which the first sheet rendered made necessary. A
    /// single ramping stroke spends only about a fifth of its length under §2.19's one-third knee,
    /// so the three rough ink candidates showed one gap at the very start and read as solid lines —
    /// the sheet would have hidden the entire mechanism the owner asked for. The second stroke is
    /// held at a constant light pressure, which is §2.18's own sentence: *"a stroke drawn genuinely
    /// light breaks up along its whole length"*.
    ///
    /// They are side by side rather than stacked because a *shorter* stroke turns harder for the
    /// same excursion, and the turn is what makes `angle.directionFollow` and a fixed-hold chisel
    /// legible at all. The first sheet's single 580 pt wave reached 15° of travel direction; two
    /// 270 pt ones reach 36°.
    private static let strokeGap: CGFloat = 14
    private static var strokeWidth: CGFloat { (pageWidth - strokeX - margin - strokeGap) / 2 }
    private static let lightPressure: CGFloat = 0.25

    private static let paper = UIColor.white
    private static let ink = UIColor.black
    private static let rule = UIColor(white: 0.82, alpha: 1)
    private static let dim = UIColor(white: 0.38, alpha: 1)
    private static let pillFill = UIColor(white: 0.90, alpha: 1)

    // MARK: - The run

    func testRenderTheContactSheet() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_TIPSHEET"] != nil,
                          "Set TEST_RUNNER_PAINTAPP_TIPSHEET=1 to render the contact sheet. It "
                          + "writes PNGs, so it is off in an ordinary suite run.")

        let tips = BrushTipGenerator.writeAll()
        XCTAssertEqual(tips.count, BrushTipGenerator.shapes.count)
        let candidates = BrushCandidates.all(tips: tips)
        let directory = try Self.outputDirectory()

        // The tips themselves, so a chosen one can be committed without re-running anything.
        let tipDirectory = directory.appendingPathComponent("tips", isDirectory: true)
        try FileManager.default.createDirectory(at: tipDirectory, withIntermediateDirectories: true)
        for tip in tips {
            try tip.png.write(to: tipDirectory.appendingPathComponent(tip.fileName))
        }

        var written: [String] = []

        for group in BrushCandidates.groups {
            let rows = candidates.filter { $0.group == group }
            let image = Self.sheet(title: "Brush candidates — \(group)",
                                   subtitle: Self.subtitle(for: group, count: rows.count),
                                   sections: [(group, rows)],
                                   scale: 2)
            let url = directory.appendingPathComponent("contact-sheet-\(group.lowercased()).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            written.append(url.path)
            add(Self.attachment(image, named: "contact-sheet-\(group.lowercased())"))
        }

        // One overview at scale 1: the whole set on one page, for the shape of it rather than for
        // reading a nib's edge. Deliberately the lower-resolution of the two — 2240 × ~6800 px is
        // 60 MB of backing store and buys nothing the per-group sheets do not already give.
        let all = BrushCandidates.groups.map { group in
            (group, candidates.filter { $0.group == group })
        }
        let overview = Self.sheet(title: "Brush candidates — BRUSH.md §12 stage 9",
                                  subtitle: "\(candidates.count) candidates, \(tips.count) generated tips. "
                                          + "The owner picks; presets are authored after.",
                                  sections: all, scale: 1)
        let overviewURL = directory.appendingPathComponent("contact-sheet-all.png")
        try XCTUnwrap(overview.pngData()).write(to: overviewURL)
        written.append(overviewURL.path)
        add(Self.attachment(overview, named: "contact-sheet-all"))

        print("TIPSHEET directory: \(directory.path)")
        for path in written { print("TIPSHEET wrote: \(path)") }
        print("TIPSHEET tips: \(tipDirectory.path) (\(tips.count) PNGs)")
    }

    private static func subtitle(for group: String, count: Int) -> String {
        if count == 0 {
            return "§12 stage 11 — the CC0 group. Nothing is generated here: §8.4 rules that "
                 + "scanned grunge and splatter are what is genuinely hard to fake."
        }
        return "\(count) candidates, each drawn at its own size through BrushStamper.stampStroke. "
             + "Left stroke: pressure ramps 0.04 → 1 → 0.04. Right stroke: held light at 0.25."
    }

    private static func attachment(_ image: UIImage, named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    /// Where the PNGs land.
    ///
    /// `TEST_RUNNER_PAINTAPP_TIPSHEET_DIR` names a host directory; without it the runner's own
    /// temporary directory is used and its absolute path is printed. Every image is *also* attached
    /// to the xcresult, so a run whose filesystem write is refused still hands back the sheet.
    private static func outputDirectory() throws -> URL {
        let fromEnvironment = ProcessInfo.processInfo.environment["PAINTAPP_TIPSHEET_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("brush-contact-sheet", isDirectory: true)
        for candidate in [fromEnvironment, fallback].compactMap({ $0 }) {
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
                return candidate
            } catch {
                continue
            }
        }
        throw XCTSkip("No writable output directory")
    }

    // MARK: - Drawing a sheet

    private static func sheet(title: String, subtitle: String,
                              sections: [(String, [BrushCandidates.Candidate])],
                              scale: CGFloat) -> UIImage {
        let titleBlock: CGFloat = 76
        var height: CGFloat = titleBlock
        for (_, rows) in sections {
            height += headerHeight
            height += rows.isEmpty ? rowHeight * 0.55 : rowHeight * CGFloat(rows.count)
        }
        height += margin

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        format.opaque = true
        let size = CGSize(width: pageWidth, height: height)

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            paper.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            draw(title, at: CGPoint(x: margin, y: 18),
                 font: .systemFont(ofSize: 22, weight: .bold), color: ink)
            draw(subtitle, in: CGRect(x: margin, y: 48, width: pageWidth - 2 * margin, height: 24),
                 font: .systemFont(ofSize: 11), color: dim)

            var y: CGFloat = titleBlock
            for (group, rows) in sections {
                y = drawHeader(group, count: rows.count, at: y, cg: cg)
                if rows.isEmpty {
                    draw("Empty by design — §12 stage 11 sources this group CC0. "
                         + "§8.6: grunge, splatter, stipple, chalk.",
                         in: CGRect(x: swatchX, y: y + 16, width: pageWidth - 2 * margin, height: 20),
                         font: .italicSystemFont(ofSize: 12), color: dim)
                    y += rowHeight * 0.55
                    continue
                }
                for candidate in rows {
                    drawRow(candidate, top: y, cg: cg)
                    y += rowHeight
                }
            }
        }
    }

    private static func drawHeader(_ group: String, count: Int, at y: CGFloat, cg: CGContext) -> CGFloat {
        UIColor(white: 0.94, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: y, width: pageWidth, height: headerHeight))
        ink.setFill()
        cg.fill(CGRect(x: 0, y: y + headerHeight - 2, width: pageWidth, height: 2))
        draw(group.uppercased(), at: CGPoint(x: margin, y: y + 16),
             font: .systemFont(ofSize: 16, weight: .heavy), color: ink)
        draw("\(count)", at: CGPoint(x: pageWidth - margin - 30, y: y + 18),
             font: .systemFont(ofSize: 15, weight: .bold), color: dim)
        return y + headerHeight
    }

    private static func drawRow(_ candidate: BrushCandidates.Candidate, top: CGFloat, cg: CGContext) {
        rule.setFill()
        cg.fill(CGRect(x: 0, y: top + rowHeight - 1, width: pageWidth, height: 1))

        // The tip's own mask, so the owner sees the nib as well as what it draws.
        if let tipName = candidate.kind.tipName {
            drawSwatch(tipName, in: CGRect(x: swatchX, y: top + 12,
                                           width: swatchSide, height: swatchSide), cg: cg)
        } else {
            rule.setStroke()
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [3, 3])
            cg.stroke(CGRect(x: swatchX, y: top + 12, width: swatchSide, height: swatchSide))
            cg.setLineDash(phase: 0, lengths: [])
            draw("no tip", at: CGPoint(x: swatchX + 22, y: top + 46),
                 font: .systemFont(ofSize: 10), color: dim)
        }

        draw(candidate.name, at: CGPoint(x: textX, y: top + 12),
             font: .systemFont(ofSize: 16, weight: .semibold), color: ink)
        drawPill(candidate.kind.label, at: CGPoint(x: textX, y: top + 36), cg: cg)
        draw(candidate.note,
             in: CGRect(x: textX, y: top + 58, width: textWidth, height: 52),
             font: .systemFont(ofSize: 10.5), color: dim, wraps: true)

        drawIsolatedDab(candidate.brush,
                        in: CGRect(x: dabX, y: top + 12, width: dabWidth, height: swatchSide), cg: cg)

        let band = CGRect(x: strokeX, y: top + 20, width: strokeWidth, height: 92)
        draw("pressure 0.04 → 1 → 0.04", at: CGPoint(x: strokeX, y: top + 6),
             font: .systemFont(ofSize: 8.5), color: dim)
        draw("held light at \(String(format: "%.2f", Double(lightPressure)))",
             at: CGPoint(x: strokeX + strokeWidth + strokeGap, y: top + 6),
             font: .systemFont(ofSize: 8.5), color: dim)
        drawStroke(candidate.brush, in: band, pressure: nil, cg: cg)
        drawStroke(candidate.brush,
                   in: band.offsetBy(dx: strokeWidth + strokeGap, dy: 0),
                   pressure: lightPressure, cg: cg)

        // The numbers, full width under the row — derived from the brush, never written out.
        draw(BrushCandidates.basesLine(candidate.brush),
             at: CGPoint(x: swatchX, y: top + rowHeight - 46),
             font: .monospacedSystemFont(ofSize: 9.5, weight: .medium), color: ink)
        draw(BrushCandidates.rowsLine(candidate.brush),
             in: CGRect(x: swatchX, y: top + rowHeight - 32,
                        width: pageWidth - 2 * margin, height: 28),
             font: .monospacedSystemFont(ofSize: 9.5, weight: .regular), color: dim, wraps: true)
    }

    private static func drawSwatch(_ tipName: String, in rect: CGRect, cg: CGContext) {
        rule.setStroke()
        cg.setLineWidth(1)
        cg.stroke(rect)
        guard let tip = BrushTipGenerator.shapes.first(where: { $0.name == tipName }),
              let image = UIImage(data: BrushTipGenerator.render(tip).png)
        else { return }
        image.draw(in: rect.insetBy(dx: 3, dy: 3))
    }

    /// **One dab, through `BrushStamper.stampDab`.** Bracketed in a stroke group so the brush's own
    /// opacity applies exactly as it does on a real walk — §2.11's cap is applied at the merge, so a
    /// dab drawn outside a group would show the wrong alpha for every brush whose opacity is not 1.
    private static func drawIsolatedDab(_ brush: Brush, in rect: CGRect, cg: CGContext) {
        let target = CGContextDabTarget(cg)
        let values = brush.dabValues(atPressure: 1)
        let diameter = min(rect.width, rect.height) - 10
        target.beginStroke()
        target.beginStrokeGroup(opacity: CGFloat(brush.opacity),
                                blendMode: brush.stroke.blendMode.cgBlendMode,
                                texture: brush.texture)
        BrushStamper.stampDab(into: target, at: CGPoint(x: rect.midX, y: rect.midY), brush: brush,
                              values: values, color: ink,
                              brushSize: diameter / max(CGFloat(values.size), 0.01),
                              random: DabRandom(seed: sheetSeed), arcWidths: 0)
        target.endStrokeGroup()
        target.endStroke()
    }

    /// **The stroke the owner reads a candidate by.** One gentle wave so `direction` actually
    /// varies — a straight line renders every direction-following nib as a bar and hides the whole
    /// mechanism — carrying a pressure ramp from 0.04 up to 1 and back.
    ///
    /// The taper is the point, and `BrushPreview` already says why: *"a straight line at constant
    /// pressure would render four of the five shipped presets as near-identical bars, because what
    /// separates them is how width and flow answer the pen"*. It is also the only thing that makes
    /// §2.19's threshold visible — a `density ← pressure` brush is solid at full press and breaks up
    /// only under about a third of it, so a sheet drawn at constant pressure would show none of the
    /// three rough ink candidates doing anything at all.
    ///
    /// **Drawn at the brush's own size**, which is where this parts company with `BrushPreview`.
    /// That one clamps into the row's band, and its reason is good for a 28 pt menu row: a 4 pt Pen
    /// would be a hairline. It is the wrong trade here — the row prints `size 4pt` beside a stroke
    /// drawn at 14, and a sheet the owner rules a *set* from must not misreport the one number that
    /// separates a technical pen from a marker. Only a floor survives, against a brush whose size is
    /// zero.
    private static func drawStroke(_ brush: Brush, in rect: CGRect,
                                   pressure: CGFloat?, cg: CGContext) {
        cg.saveGState()
        cg.clip(to: rect)
        let target = CGContextDabTarget(cg)
        BrushStamper.stampStroke(into: target,
                                 samples: samples(in: rect, pressure: pressure),
                                 brush: brush,
                                 color: ink,
                                 brushSize: max(brush.size, 3),
                                 brushOpacity: brush.opacity,
                                 random: DabRandom(seed: sheetSeed))
        cg.restoreGState()
    }

    /// Arbitrary and fixed, exactly as `BrushPreview.previewSeed` is: §4's randomness is hashed by
    /// arc length rather than streamed, so one seed makes a candidate's row a *function of the
    /// candidate* and two renders of the sheet are the same picture.
    private static let sheetSeed: UInt64 = 0x51_4C_5041_494E_0009

    private static func samples(in rect: CGRect, pressure held: CGFloat?) -> StrokeSamples {
        let x0 = rect.minX + 14
        let x1 = rect.maxX - 14
        let midY = rect.midY
        let amplitude = rect.height * 0.26
        let steps = max(Int((x1 - x0) / 1.5), 48)
        var points: [VectorSample] = []
        points.reserveCapacity(steps + 1)
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = x0 + (x1 - x0) * t
            let y = midY - sin(t * 2 * .pi) * amplitude
            let pressure = held ?? (0.04 + 0.96 * sin(t * .pi))
            points.append(VectorSample(point: CGPoint(x: x, y: y), pressure: pressure))
        }
        return StrokeSamples(points, channels: .pressureOnly)
    }

    // MARK: - Text

    private static func drawPill(_ text: String, at origin: CGPoint, cg: CGContext) {
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let width = (text as NSString)
            .size(withAttributes: [.font: font, .kern: 0.6]).width + 14
        let box = CGRect(x: origin.x, y: origin.y, width: width, height: 17)
        pillFill.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 7, y: origin.y + 3.5),
                                withAttributes: [.font: font, .kern: 0.6,
                                                 .foregroundColor: UIColor(white: 0.15, alpha: 1)])
    }

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                             wraps: Bool = false) {
        let style = NSMutableParagraphStyle()
        // `.byTruncatingTail` on a multi-line box truncates to *one* line, which is what ate the
        // second half of every note on the first sheet rendered. Wrapping fills the box and clips.
        style.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color,
                                                           .paragraphStyle: style])
    }
}
