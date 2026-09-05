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
/// **Round four adds the Texture group**, which §12 stage 11 had deferred to CC0 sourcing and which
/// §13 asked the generator to attempt: fifteen rows over four slots, every slot carrying a control
/// that is meant to fail. Two of those controls are new in kind — a picture stamped at a *shipped*
/// brush's spacing rather than at its own, and a nib whose paper is removed — and both are the
/// sheet's way of asking which of §8.4's mechanisms is doing the work.
///
/// **The two things below changed because the first sheet was read, and they still hold.**
///
/// - **A third stroke that turns.** The first sheet's report recorded the Chisel as *"correct but
///   subtle; the thick/thin needs a stroke that turns more than a contact-sheet row allows"* — and
///   every square, flat and bristle nib has the same problem, because what a direction-following or
///   fixed-hold nib *does* is only visible where the travel direction sweeps. The two wave strokes
///   reach about 36° between them; the third is a 340° arc, so a nib held at a fixed angle passes
///   through every relationship to the travel it can have.
/// - **Rows are grouped by §8.6's sixteen slots**, not merely by group, and each row is marked
///   `CHOSEN`, `VARIANT` or `CONTROL`. Sixteen brushes are picked and four slots are open; a sheet
///   that does not say which is which invites a settled brush and a competing variant to be compared
///   as if the question were still open.
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

    private static let pageWidth: CGFloat = 1400
    private static let rowHeight: CGFloat = 220
    private static let headerHeight: CGFloat = 58
    private static let slotHeaderHeight: CGFloat = 30
    private static let margin: CGFloat = 20

    private static let swatchX: CGFloat = 20
    private static let swatchSide: CGFloat = 96
    private static let textX: CGFloat = 128
    private static let textWidth: CGFloat = 296
    private static let dabX: CGFloat = 436
    private static let dabWidth: CGFloat = 96
    private static let strokeX: CGFloat = 548

    /// **Three strokes per row, side by side.**
    ///
    /// The first two are the first sheet's pair and both of them were made necessary by rendering
    /// it. A single ramping stroke spends only about a fifth of its length under §2.19's one-third
    /// knee, so the rough ink candidates showed one gap at the very start and read as solid lines;
    /// the second is held at a constant light pressure, which is §2.18's own sentence — *"a stroke
    /// drawn genuinely light breaks up along its whole length"*.
    ///
    /// The third is new and it is the **turning** stroke. A wave reaches ±18° of travel direction;
    /// a nib held at a fixed `angle.base`, or one following the travel with an asymmetric picture,
    /// only shows what it does across a *wide* sweep of directions. 340° of arc is every one of
    /// them, so a chisel's thick/thin, a slab's corner behaviour and a bristle's rake are all on the
    /// page instead of being described in a report.
    private static let strokeGap: CGFloat = 14
    private static let turnSide: CGFloat = 156
    private static var waveWidth: CGFloat {
        (pageWidth - strokeX - margin - turnSide - 2 * strokeGap) / 2
    }
    private static let bandHeight: CGFloat = 156
    private static let lightPressure: CGFloat = 0.25
    private static let turnPressure: CGFloat = 0.7

    private static let paper = UIColor.white
    private static let ink = UIColor.black
    private static let rule = UIColor(white: 0.82, alpha: 1)
    private static let dim = UIColor(white: 0.38, alpha: 1)
    private static let pillFill = UIColor(white: 0.90, alpha: 1)
    private static let controlFill = UIColor(white: 0.80, alpha: 1)

    /// One group's rows, already split into §8.6's slots in the owner's own order.
    private typealias Section = (group: String, slots: [(slot: String,
                                                         rows: [BrushCandidates.Candidate])])

    // MARK: - The run

    func testRenderTheContactSheet() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_TIPSHEET"] != nil,
                          "Set TEST_RUNNER_PAINTAPP_TIPSHEET=1 to render the contact sheet. It "
                          + "writes PNGs, so it is off in an ordinary suite run.")

        let tips = BrushTipGenerator.writeAll()
        XCTAssertEqual(tips.count, BrushTipGenerator.shapes.count)
        let candidates = BrushCandidates.all(tips: tips)
        let directory = try Self.outputDirectory()

        // **The swatches are drawn from the tips that were just written, not re-rendered per row.**
        // The first sheet called `BrushTipGenerator.render` inside the swatch, which drew every mask
        // twice per appearance — once per group sheet and once on the overview — for a picture that
        // is a function of the catalogue and could not differ.
        var swatches: [String: UIImage] = [:]
        for tip in tips { swatches[tip.name] = UIImage(data: tip.png) }

        // The tips themselves, so a chosen one can be committed without re-running anything.
        let tipDirectory = directory.appendingPathComponent("tips", isDirectory: true)
        try FileManager.default.createDirectory(at: tipDirectory, withIntermediateDirectories: true)
        for tip in tips {
            try tip.png.write(to: tipDirectory.appendingPathComponent(tip.fileName))
        }

        var written: [String] = []

        for group in BrushCandidates.groups {
            let section = Self.section(for: group, in: candidates)
            let count = section.slots.reduce(0) { $0 + $1.rows.count }
            let image = Self.sheet(title: "Brush candidates — \(group)",
                                   subtitle: Self.subtitle(for: group, count: count),
                                   sections: [section], swatches: swatches, scale: 2)
            let url = directory.appendingPathComponent("contact-sheet-\(group.lowercased()).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            written.append(url.path)
            add(Self.attachment(image, named: "contact-sheet-\(group.lowercased())"))
        }

        // One overview at scale 1: the whole set on one page, for the shape of it rather than for
        // reading a nib's edge. Deliberately the lower-resolution of the two — the per-group sheets
        // are where an edge is judged, and a scale-2 overview is 60 MB of backing store for nothing.
        let all = BrushCandidates.groups.map { Self.section(for: $0, in: candidates) }
        let overview = Self.sheet(title: "Brush candidates — BRUSH.md §12 stage 11, round four",
                                  subtitle: "\(candidates.count) rows over §8.6's twenty slots, "
                                          + "\(tips.count) generated tips. CHOSEN is settled; "
                                          + "VARIANT competes for an open slot; CONTROL is on the "
                                          + "sheet in order to fail. The Texture group is §13's "
                                          + "open question — can the generator make credible "
                                          + "grunge, splatter, stipple and chalk, and does that "
                                          + "delete §12 stage 11's licensing step?",
                                  sections: all, swatches: swatches, scale: 1)
        let overviewURL = directory.appendingPathComponent("contact-sheet-all.png")
        try XCTUnwrap(overview.pngData()).write(to: overviewURL)
        written.append(overviewURL.path)
        add(Self.attachment(overview, named: "contact-sheet-all"))

        print("TIPSHEET directory: \(directory.path)")
        for path in written { print("TIPSHEET wrote: \(path)") }
        print("TIPSHEET tips: \(tipDirectory.path) (\(tips.count) PNGs)")
    }

    /// **The slot order comes from `BrushCandidates.slots`, not from the candidate list.** A slot
    /// nobody drew a candidate for renders as an empty header rather than vanishing, which is the
    /// difference between "we did not build this yet" and a sheet that silently lost a brush.
    private static func section(for group: String,
                                in candidates: [BrushCandidates.Candidate]) -> Section {
        let rows = candidates.filter { $0.group == group }
        var slots: [(slot: String, rows: [BrushCandidates.Candidate])] = []
        for slot in BrushCandidates.slots[group] ?? [] {
            slots.append((slot, rows.filter { $0.slot == slot }))
        }
        // Anything whose slot is not in the table would otherwise be dropped silently — the same
        // class of failure as a tip name that does not resolve.
        let known = Set(BrushCandidates.slots[group] ?? [])
        let orphans = rows.filter { !known.contains($0.slot) }
        if !orphans.isEmpty { slots.append(("Not in §8.6's sixteen", orphans)) }
        return (group, slots)
    }

    private static func subtitle(for group: String, count: Int) -> String {
        if count == 0 {
            return "No candidate was drawn for any slot in this group."
        }
        return "\(count) rows, each drawn at its own size through BrushStamper.stampStroke. "
             + "Left: pressure ramps 0.04 → 1 → 0.04. Middle: held light at 0.25. "
             + "Right: a 340° turn at 0.70, which is where a nib's angle shows."
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
                              sections: [Section], swatches: [String: UIImage],
                              scale: CGFloat) -> UIImage {
        let titleBlock: CGFloat = 76
        var height: CGFloat = titleBlock
        for section in sections {
            height += headerHeight
            if section.slots.isEmpty {
                height += rowHeight * 0.55
                continue
            }
            for slot in section.slots {
                height += slotHeaderHeight
                height += slot.rows.isEmpty ? 26 : rowHeight * CGFloat(slot.rows.count)
            }
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
            draw(subtitle, in: CGRect(x: margin, y: 46, width: pageWidth - 2 * margin, height: 30),
                 font: .systemFont(ofSize: 11), color: dim, wraps: true)

            var y: CGFloat = titleBlock
            for section in sections {
                let count = section.slots.reduce(0) { $0 + $1.rows.count }
                y = drawHeader(section.group, count: count, at: y, cg: cg)
                if section.slots.isEmpty {
                    draw("No slots are declared for this group.",
                         in: CGRect(x: swatchX, y: y + 16, width: pageWidth - 2 * margin, height: 20),
                         font: .italicSystemFont(ofSize: 12), color: dim)
                    y += rowHeight * 0.55
                    continue
                }
                for slot in section.slots {
                    y = drawSlotHeader(slot.slot, count: slot.rows.count, at: y, cg: cg)
                    if slot.rows.isEmpty {
                        draw("No candidate on this sheet.",
                             in: CGRect(x: swatchX, y: y + 4, width: 400, height: 18),
                             font: .italicSystemFont(ofSize: 11), color: dim)
                        y += 26
                        continue
                    }
                    for candidate in slot.rows {
                        drawRow(candidate, top: y, swatches: swatches, cg: cg)
                        y += rowHeight
                    }
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

    private static func drawSlotHeader(_ slot: String, count: Int,
                                       at y: CGFloat, cg: CGContext) -> CGFloat {
        UIColor(white: 0.975, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: y, width: pageWidth, height: slotHeaderHeight))
        UIColor(white: 0.72, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: y + slotHeaderHeight - 1, width: pageWidth, height: 1))
        draw("SLOT ▸ \(slot.uppercased())", at: CGPoint(x: margin, y: y + 8),
             font: .systemFont(ofSize: 12, weight: .bold), color: UIColor(white: 0.2, alpha: 1))
        draw(count == 1 ? "1 row" : "\(count) rows",
             at: CGPoint(x: pageWidth - margin - 52, y: y + 9),
             font: .systemFont(ofSize: 11), color: dim)
        return y + slotHeaderHeight
    }

    private static func drawRow(_ candidate: BrushCandidates.Candidate, top: CGFloat,
                                swatches: [String: UIImage], cg: CGContext) {
        rule.setFill()
        cg.fill(CGRect(x: 0, y: top + rowHeight - 1, width: pageWidth, height: 1))

        // The tip's own mask, so the owner sees the nib as well as what it draws.
        let swatchRect = CGRect(x: swatchX, y: top + 16, width: swatchSide, height: swatchSide)
        if let tipName = candidate.kind.tipName {
            rule.setStroke()
            cg.setLineWidth(1)
            cg.stroke(swatchRect)
            swatches[tipName]?.draw(in: swatchRect.insetBy(dx: 3, dy: 3))
            draw(tipName, in: CGRect(x: swatchX, y: swatchRect.maxY + 3,
                                     width: swatchSide + 30, height: 14),
                 font: .monospacedSystemFont(ofSize: 8, weight: .regular), color: dim)
        } else {
            rule.setStroke()
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [3, 3])
            cg.stroke(swatchRect)
            cg.setLineDash(phase: 0, lengths: [])
            draw("no tip", at: CGPoint(x: swatchX + 28, y: top + 56),
                 font: .systemFont(ofSize: 10), color: dim)
        }

        draw(candidate.name, at: CGPoint(x: textX, y: top + 12),
             font: .systemFont(ofSize: 16, weight: .semibold), color: ink)
        let standingWidth = drawPill(candidate.standing.label, at: CGPoint(x: textX, y: top + 34),
                                     fill: candidate.standing == .control ? controlFill : pillFill,
                                     cg: cg)
        drawPill(candidate.kind.label, at: CGPoint(x: textX + standingWidth + 6, y: top + 34),
                 fill: pillFill, cg: cg)
        draw(candidate.note,
             in: CGRect(x: textX, y: top + 56, width: textWidth, height: 86),
             font: .systemFont(ofSize: 10.5), color: dim, wraps: true)

        drawIsolatedDab(candidate.brush,
                        in: CGRect(x: dabX, y: top + 16, width: dabWidth, height: swatchSide), cg: cg)

        let band = CGRect(x: strokeX, y: top + 26, width: waveWidth, height: bandHeight)
        let secondX = strokeX + waveWidth + strokeGap
        let turnX = secondX + waveWidth + strokeGap
        draw("pressure 0.04 → 1 → 0.04", at: CGPoint(x: strokeX, y: top + 12),
             font: .systemFont(ofSize: 8.5), color: dim)
        draw("held light at \(String(format: "%.2f", Double(lightPressure)))",
             at: CGPoint(x: secondX, y: top + 12),
             font: .systemFont(ofSize: 8.5), color: dim)
        draw("340° turn at \(String(format: "%.2f", Double(turnPressure)))",
             at: CGPoint(x: turnX, y: top + 12),
             font: .systemFont(ofSize: 8.5), color: dim)
        drawStroke(candidate.brush, in: band, samples: wave(in: band, pressure: nil), cg: cg)
        drawStroke(candidate.brush, in: band.offsetBy(dx: waveWidth + strokeGap, dy: 0),
                   samples: wave(in: band.offsetBy(dx: waveWidth + strokeGap, dy: 0),
                                 pressure: lightPressure), cg: cg)
        let turnBand = CGRect(x: turnX, y: top + 26, width: turnSide, height: bandHeight)
        drawStroke(candidate.brush, in: turnBand,
                   samples: turn(in: turnBand, brushSize: max(candidate.brush.size, 3)), cg: cg)

        // The numbers, full width under the row — derived from the brush, never written out.
        draw(BrushCandidates.basesLine(candidate.brush),
             at: CGPoint(x: swatchX, y: top + rowHeight - 36),
             font: .monospacedSystemFont(ofSize: 9.5, weight: .medium), color: ink)
        draw(BrushCandidates.rowsLine(candidate.brush),
             in: CGRect(x: swatchX, y: top + rowHeight - 23,
                        width: pageWidth - 2 * margin, height: 22),
             font: .monospacedSystemFont(ofSize: 9.5, weight: .regular), color: dim, wraps: true)
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

    /// **Drawn at the brush's own size**, which is where this parts company with `BrushPreview`.
    /// That one clamps into the row's band, and its reason is good for a 28 pt menu row: a 4 pt Pen
    /// would be a hairline. It is the wrong trade here — the row prints `size 4pt` beside a stroke
    /// drawn at 14, and a sheet the owner rules a *set* from must not misreport the one number that
    /// separates a technical pen from a marker. Only a floor survives, against a brush whose size is
    /// zero.
    private static func drawStroke(_ brush: Brush, in rect: CGRect,
                                   samples: StrokeSamples, cg: CGContext) {
        cg.saveGState()
        cg.clip(to: rect)
        let target = CGContextDabTarget(cg)
        BrushStamper.stampStroke(into: target,
                                 samples: samples,
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

    /// **The stroke the owner reads a candidate by.** One gentle wave so `direction` actually
    /// varies — a straight line renders every direction-following nib as a bar and hides the whole
    /// mechanism — carrying a pressure ramp from 0.04 up to 1 and back, or held at a constant.
    ///
    /// The taper is the point, and `BrushPreview` already says why: *"a straight line at constant
    /// pressure would render four of the five shipped presets as near-identical bars, because what
    /// separates them is how width and flow answer the pen"*. It is also the only thing that makes
    /// §2.19's threshold visible — a `density ← pressure` brush is solid at full press and breaks up
    /// only under about a third of it.
    private static func wave(in rect: CGRect, pressure held: CGFloat?) -> StrokeSamples {
        let x0 = rect.minX + 14
        let x1 = rect.maxX - 14
        let midY = rect.midY
        let amplitude = rect.height * 0.24
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

    /// **The turning stroke — 340° of travel direction at one pressure.**
    ///
    /// A wave reaches ±18°, which is enough to tell a direction-following nib from a fixed one and
    /// not enough to show what either *does*. A nib held at a fixed `angle.base` is thick where the
    /// travel is perpendicular to it and vanishes where it is parallel, and that whole cycle only
    /// exists on an arc. Held at a constant pressure so the width is the angle's doing and not the
    /// ramp's, and left slightly open (340°, on a gentle spiral) so the two ends do not overlap and
    /// hide the cap.
    private static func turn(in rect: CGRect, brushSize: CGFloat) -> StrokeSamples {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // **The radius has to leave room for the brush, and the first render of this sheet did
        // not.** `drawStroke` clips to the band, so an arc laid out to the band's own half-width
        // has half a nib hanging outside it and the ring reads as cut on both sides. Every other
        // stroke on the page is a wave inside a band it never reaches the edge of; this one is
        // the only one whose extent is the band.
        let outer = min(rect.width, rect.height) / 2 - 10 - brushSize * 0.55
        let steps = 220
        var points: [VectorSample] = []
        points.reserveCapacity(steps + 1)
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = (-0.30 + t * (340.0 / 360.0)) * 2 * .pi
            let radius = max(outer - t * 8, 8)
            points.append(VectorSample(point: CGPoint(x: centre.x + cos(angle) * radius,
                                                      y: centre.y + sin(angle) * radius),
                                       pressure: turnPressure))
        }
        return StrokeSamples(points, channels: .pressureOnly)
    }

    // MARK: - Text

    @discardableResult
    private static func drawPill(_ text: String, at origin: CGPoint,
                                 fill: UIColor, cg: CGContext) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let width = (text as NSString)
            .size(withAttributes: [.font: font, .kern: 0.6]).width + 14
        let box = CGRect(x: origin.x, y: origin.y, width: width, height: 17)
        fill.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 7, y: origin.y + 3.5),
                                withAttributes: [.font: font, .kern: 0.6,
                                                 .foregroundColor: UIColor(white: 0.15, alpha: 1)])
        return width
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
