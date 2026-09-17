import UIKit
import CoreGraphics

/// The single source of truth for turning brush + input samples into stamps on a
/// `RasterLayerTexture`. Both live raster drawing (`StrokeCanvasView`) and vector re-rendering
/// (`VectorCanvas.render`) go through here, so a vector stroke rasterizes identically to how it
/// would have been drawn live — same tip/hardness/dynamics/scatter/spacing.
enum BrushStamper {

    /// Distance between consecutive stamps along a path. The 1 pt floor keeps thin or tight-spacing
    /// brushes continuous even at a spacing fraction of ~0.
    ///
    /// **It takes the fraction rather than the brush, because since §12 stage 7 there are two places
    /// the fraction can come from** — `Brush.dab.spacing`, and the `spacing` output resolved at a dab,
    /// which may differ from it anywhere along a stroke. §10's own warning is that two ways to compute
    /// one dab number is two ways for it to be wrong, so there is one function and the caller says
    /// which fraction it is asking about.
    static func stampSpacing(brushSize: CGFloat, fraction: Double) -> CGFloat {
        max(brushSize * CGFloat(fraction), 1)
    }

    /// **The live tier's walk** — one stroke laid down as the pen moves, one call per touch sample,
    /// into the scratch. `StrokeCanvasView` owns one per gesture; it lives here rather than in that
    /// view so a test can drive the walk the artist watches and compare it with the replay
    /// (`StrokeLiftParityLogicTests`), instead of mirroring it by hand and measuring a copy.
    ///
    /// **Fed every input sample, and that is deliberate.** A raster layer stores pixels, not
    /// samples, so there is no geometry to conserve on this path — thinning its input would buy
    /// nothing and would change the ink a raster stroke lays down. The refit belongs where samples
    /// are kept: `StrokeCanvasView.recordVectorSample`. At input density the straight line between
    /// two samples and `StrokePath`'s curve through them are the same line to well under a pixel,
    /// which is why this walk is a `StrokePath` of two points per call — the same march as
    /// `stampStroke`'s, on a chord.
    ///
    /// **§12 stage 7: this walk resolves §6's matrix, through §5.5's funnel, exactly as
    /// `stampStroke` does.** It has to — on a raster layer these dabs are the cel's pixels and
    /// nothing re-stamps them at lift, so a sensor the live walk could not read would be a feature
    /// the raster half of the app does not have. The sensors are built over the **one segment** a
    /// call bridges: a two-sample run from the previous sample to this one, and the straight line
    /// through them as the curve. That is the same geometry the walk already draws, so `direction`
    /// reads the line it is stamping along and `velocity` reads the interval that actually elapsed.
    /// `taper` answers its neutral, because `totalArcWidths` is nil for a walk that cannot know how
    /// long the stroke will be.
    ///
    /// Pressure ramps across a call, as it does across a replayed segment: `stampStroke` has always
    /// ramped, and the staircase the ramp exists to prevent was visible live on a fast flick with a
    /// wide brush.
    ///
    /// **Two things about this walk were what changed on lift, and both are TODO (84).** Measured on
    /// a hand-drawn arc in `StrokeLiftParityLogicTests`, the walk the artist watched against the
    /// stored stroke's replay of the same samples:
    ///
    /// - **It hopped from the last dab straight to the next sample**, so its arc length was the
    ///   chord from wherever the last dab landed rather than the path the pen took, and a
    ///   wide-spaced brush cut every corner: on a 48 pt splatter at 0.46 spacing the drops landed
    ///   inside the curve and fewer of them, a mean channel delta of 0.082/255 over 1,402 pixels
    ///   against the replay of the very same samples. The march is `StrokePath.advance` now, with
    ///   its `WalkCarry` crossing the per-sample calls, so a dab lands where the pen's own path has
    ///   travelled one spacing — which is where the replay puts it, to within the refit.
    /// - **The first dab faced `+x`**, because a stroke one point long has no direction, while the
    ///   replay's faces the fitted curve's outgoing tangent: on a 36 pt square nib that was one
    ///   whole dab turning on lift, 417 pixels at a channel delta of 240/255. The first sample is
    ///   held for one input interval — about 8 ms — and stamped facing the second, which is what the
    ///   outgoing tangent at the first knot is to within the refit's tolerance. A tap never gets a
    ///   second sample and stamps its one dab at `finish`, facing `+x`.
    struct LiveWalk {
        /// The stroke's own field, minted at pen-down, so what the pen lays down and what the
        /// stored stroke replays are drawn from the same randomness — BRUSH.md §4.
        let random: DabRandom
        /// The sample the walk is stamping **from** — the other end of the segment `stamp` bridges.
        /// Held alone, unstamped, until the second sample arrives.
        private var lastSample: VectorSample?
        /// Where the march left off — the distance travelled since the last dab and the gap that dab
        /// asked for — carried across calls exactly as `stampStroke` carries it across segments.
        /// Nil until the first dab.
        private var carry: WalkCarry?
        /// How far the walk has travelled, in brush widths — `DabRandom`'s coordinate, advanced one
        /// dab's worth per dab exactly as `stampStroke` advances its own.
        private(set) var arcWidths: CGFloat = 0

        init(seed: UInt64) {
            random = DabRandom(seed: seed)
        }

        /// Lays down the dabs from the previous sample up to `sample`. The very first sample of a
        /// gesture is held rather than stamped; see the header.
        mutating func stamp(to sample: VectorSample, into target: DabTarget, brush: Brush,
                            color: UIColor, brushSize: CGFloat) {
            guard let previous = lastSample else {
                lastSample = sample
                return
            }
            // Two samples and the line through them. `.captured` because `StrokeInput` always
            // reports every channel — a finger reports the neutrals, which is what `compacted()`
            // later drops.
            let run = StrokeSamples([previous, sample], channels: .captured)
            let path = StrokePath(points: run.positions)
            let sensors = StrokeSensors(samples: run, path: path, random: random, brushSize: brushSize)
            func values(at parameter: CGFloat, arcWidths: CGFloat) -> BrushDabValues {
                brush.dabValues { sensors.value(of: $0, at: DabSite(parameter: parameter, arcWidths: arcWidths)) }
            }

            defer { lastSample = sample }
            var walked = arcWidths
            var march: WalkCarry
            if let carry {
                march = carry
            } else {
                // The held first sample, stamped now that the stroke has a direction: BRUSH.md
                // §2.30's stroke frame off this two-point path is the chord from it to `sample`,
                // which is what the fitted curve's outgoing tangent at the first knot is to within
                // the refit's tolerance.
                let resolved = values(at: 0, arcWidths: walked)
                BrushStamper.stampDab(into: target, at: previous.point, brush: brush, values: resolved,
                                      color: color, brushSize: brushSize,
                                      random: random, arcWidths: walked,
                                      tangent: path.tangent(at: 0))
                march = WalkCarry(spacing: BrushStamper.stampSpacing(brushSize: brushSize,
                                                                     fraction: resolved.spacing))
            }
            march = path.advance(segment: 0, carry: march) { dab, u, step in
                // One dab's worth of arc length in brush widths, from the spacing this step actually
                // walked — the same accumulation `stampStroke` makes, so the two walks address the
                // same points of the field even though their geometry differs by the refit's
                // tolerance.
                walked += brushSize > 0 ? step / brushSize : step
                let resolved = values(at: u, arcWidths: walked)
                // The same `StrokePath.tangent` the replay walk reads, off this walk's own two-point
                // path — so the live tier and the stored stroke differ in the scatter's *frame* only
                // by the refit's geometry, which is the difference BRUSH.md §4 already names.
                BrushStamper.stampDab(into: target, at: dab, brush: brush, values: resolved,
                                      color: color, brushSize: brushSize,
                                      random: random, arcWidths: walked,
                                      tangent: path.tangent(at: u))
                return BrushStamper.stampSpacing(brushSize: brushSize, fraction: resolved.spacing)
            }
            arcWidths = walked
            carry = march
        }

        /// The lift. A gesture that never got a second sample — a tap — stamps its one dab now,
        /// facing `+x` for want of a direction; a gesture that did has nothing left to lay down.
        mutating func finish(into target: DabTarget, brush: Brush, color: UIColor, brushSize: CGFloat) {
            guard carry == nil, let held = lastSample else { return }
            let run = StrokeSamples([held, held], channels: .captured)
            let path = StrokePath(points: run.positions)
            let sensors = StrokeSensors(samples: run, path: path, random: random, brushSize: brushSize)
            let resolved = brush.dabValues { sensors.value(of: $0, at: DabSite(parameter: 0, arcWidths: arcWidths)) }
            BrushStamper.stampDab(into: target, at: held.point, brush: brush, values: resolved,
                                  color: color, brushSize: brushSize, random: random, arcWidths: arcWidths,
                                  tangent: path.tangent(at: 0))
            carry = WalkCarry(spacing: BrushStamper.stampSpacing(brushSize: brushSize, fraction: resolved.spacing))
        }
    }

    /// Replays a whole stroke (spacing-interpolated between samples, exactly like
    /// `LiveWalk`) into `raster`, as one `beginStroke`/`endStroke` unit.
    ///
    /// `random` is the stroke's own field — `VectorStroke.dabRandom` for stored geometry, the seed
    /// minted at pen-down for live drawing. Every per-dab random value is a hash of it and the dab's
    /// arc length, so there is nothing to keep in phase; BRUSH.md §4 and `DabRandom`.
    ///
    /// ## Arc length is the walk's own coordinate, in brush widths
    ///
    /// The march places dabs exactly `spacing` apart along the flattened curve, leftover carried
    /// across segments, so a dab's arc length is one step more than the previous dab's — the first
    /// sitting at zero, on `samples[0]`. Accumulated rather than multiplied out, because §6's spacing
    /// is itself sensor-driven and will vary along a stroke; adding the same step in the same order is
    /// what makes two tiers walking one stroke agree bit for bit.
    ///
    /// The step is `spacing / brushSize`, so the field is addressed in **brush widths** — the unit
    /// §2.17 states λ in, and the one that makes a uniform scale of a stroke leave its randomness
    /// exactly where it was. `DabRandom` carries the measurement.
    ///
    /// ## `visibleRange` — showing a sub-run without re-phasing it
    ///
    /// The dab lattice is anchored at `samples[0]`: dabs land every `spacing` along the path, leftover
    /// carried across segments. Naively re-stamping just a cut stroke's surviving sub-run would move
    /// the anchor to the cut, shifting the piece's ink along its whole length (most visibly at the far
    /// tip) instead of leaving Mode 1's geometric split where it was.
    ///
    /// `visibleRange` fixes this as a *filter over the original walk*, not a re-derivation: the caller
    /// passes the **whole** stroke's samples, this walks all of them exactly as before — same spacing
    /// arithmetic, same carry, same floating-point, same arc length — and skips the ones outside the
    /// range. The dabs that land are bit-for-bit what the uncut stroke produced, which matters because
    /// the acceptance test for this is asserted at *zero* tolerance.
    ///
    /// A skipped dab is skipped outright, and the arc length still advances over it. Arc length is a
    /// property of the walk rather than of what was drawn, which is what lets the skip be a skip.
    ///
    /// The range is in `StrokeGeometry`'s "sample index + fraction" domain; a dab exactly on a
    /// boundary is drawn, so two pieces cut at `low`/`high` render, between them, every dab of the
    /// original except those strictly inside `(low, high)`.
    ///
    /// ## The walk follows the curve, not the samples
    ///
    /// BRUSH.md §3.4. The stored points are a refit at a fixed geometric tolerance
    /// (`StrokePathFit`), so consecutive ones sit up to 12 pt apart rather than at input density, and
    /// two things that used to be indistinguishable no longer are. Walking the chords would
    /// polygonise a curve, and — the reason this is not merely cosmetic — the walk used to hop
    /// *from the last dab to the next sample*, cutting the corner at every stored point. At input
    /// density that cut was a fraction of a pixel. At the fit's spacing it would be the whole
    /// tolerance, and it would grow every time a brush's spacing was widened. `StrokePath.advance`
    /// marches the interpolant through the stored points instead, so a stroke's ink is a function of
    /// its geometry and not of the spacing it happens to be walked at.
    ///
    /// ## The spacing is read at every dab, drawn or not — §12 stage 7
    ///
    /// `spacing` is one of §6's outputs, so it may vary along a stroke. The gap leading *away* from a
    /// dab is resolved **at that dab**, which is the only causal choice: the walk has to know how far
    /// to travel before it arrives anywhere to ask.
    ///
    /// It is resolved for a dab the walk **skips** as well as one it draws — whether skipped by
    /// `visibleRange` or by §2.32's density gate — for exactly the reason arc length advances over a
    /// skipped dab: the lattice is a property of the walk, not of what came out of it. A cut piece and
    /// the uncut stroke march identically or the zero-tolerance parity net fails on the first dab past
    /// the cut.
    ///
    /// ## The whole walk is one group — BRUSH.md §2.11
    ///
    /// `brushOpacity` no longer reaches a dab. It is the **cap** on what this stroke may reach however
    /// often it crosses itself, and it is applied once, by the `beginStrokeGroup`/`endStrokeGroup`
    /// bracket round the walk; a dab inside lays down its own `flow`, `.normal`. The brush's blend
    /// mode — or `.destinationOut` when this is an eraser — travels on the group for the same reason:
    /// a `.multiply` stroke blends against what is under it rather than against its own overlaps.
    ///
    /// **A group per `stampStroke` call is the right granularity**, and it is why this is not on
    /// `beginStroke`/`endStroke`. `VectorCanvas.applyPreview` runs several of these into one
    /// `StrokeScratch` — an erase walk and then a restamp per surviving piece — and each wants its own
    /// merge with its own blend mode.
    static func stampStroke(into raster: DabTarget, samples: StrokeSamples, brush: Brush,
                            color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool = false,
                            random: DabRandom, visibleRange: ClosedRange<CGFloat>? = nil) {
        guard !samples.isEmpty else { return }
        raster.beginStroke()
        // BRUSH.md §2.25: the brush's paper rides the group, so it multiplies into the finished walk
        // in canvas coordinates and the cap below scales the textured result. An eraser carries it
        // too — the eraser is a stroke here, and what the paper rejects is ink it does not remove.
        raster.beginStrokeGroup(opacity: CGFloat(brushOpacity),
                                blendMode: isEraser ? .destinationOut
                                                    : brush.stroke.blendMode.cgBlendMode,
                                texture: brush.texture)
        defer {
            raster.endStrokeGroup()
            raster.endStroke()
        }
        let path = StrokePath(points: samples.positions)
        // **BRUSH.md §13's open question, answered by §12 stage 7: a *replay* knows how long the
        // stroke is, and a live walk does not.** This one is replaying stored geometry, so the length
        // is measurable — and is measured, once, only when a row actually asks for `taper`, because
        // it is a second flattening pass over the curve and no other brush should pay for it. The
        // live walk (`LiveWalk`) stamps as the pen moves and genuinely cannot know,
        // so `taper` answers its neutral there; that asymmetry is real, is confined to a brush that
        // tapers, and is written down rather than papered over.
        let totalArcWidths: CGFloat? = brush.modulations.readsTaper && brushSize > 0
            ? path.arcLength(to: path.domainEnd) / brushSize : nil
        // BRUSH.md §5.5: every sensor this walk reads resolves here, and a channel the stroke does not
        // carry answers a defined neutral rather than whatever a field defaulted to.
        let sensors = StrokeSensors(samples: samples, path: path, random: random,
                                    brushSize: brushSize, totalArcWidths: totalArcWidths)

        func draws(at parameter: CGFloat) -> Bool { visibleRange?.contains(parameter) ?? true }

        /// §6's matrix at one site, through §5.5's funnel — the one place this walk resolves anything.
        func values(at site: DabSite) -> BrushDabValues {
            brush.dabValues { sensors.value(of: $0, at: site) }
        }

        // The first dab sits on the first stored point — the anchor the whole lattice hangs from, what
        // `visibleRange` counts from, and arc length zero.
        var arcWidths: CGFloat = 0
        var resolved = values(at: DabSite(parameter: 0, arcWidths: 0))
        if draws(at: 0) {
            stampDab(into: raster, at: samples.positions[0], brush: brush, values: resolved,
                     color: color, brushSize: brushSize, random: random, arcWidths: arcWidths,
                     tangent: path.tangent(at: 0))
        }
        var carry = WalkCarry(spacing: stampSpacing(brushSize: brushSize, fraction: resolved.spacing))
        for index in 0..<max(samples.count - 1, 0) {
            carry = path.advance(segment: index, carry: carry) { dab, u, walked in
                // One dab's worth of arc length, in brush widths, taken from the spacing this step
                // actually walked. A zero-width brush has no width to measure against and falls back
                // to points, which keeps the degenerate case addressing distinct cells instead of
                // collapsing every dab onto one. Accumulated rather than multiplied out, because the
                // step is not a constant once §6's spacing is sensor-driven.
                arcWidths += brushSize > 0 ? walked / brushSize : walked
                let site = DabSite(parameter: CGFloat(index) + u, arcWidths: arcWidths)
                resolved = values(at: site)
                // Every parameter ramps across the dabs bridging two stored points rather than every
                // one of them taking the destination point's value. One segment can span many dabs,
                // and holding pressure flat across them turned a smooth press into a visible staircase
                // in both width and opacity. The ramp is the funnel's, so a stroke with no pressure
                // channel gets the neutral here and nowhere else.
                if draws(at: site.parameter) {
                    // BRUSH.md §2.30's frame, from the same `StrokePath.tangent` the `direction`
                    // sensor reads through `StrokeSensors` — one function, so the scatter's axes and
                    // a direction-following tip cannot disagree about which way the stroke is going.
                    stampDab(into: raster, at: dab, brush: brush, values: resolved,
                             color: color, brushSize: brushSize, random: random, arcWidths: arcWidths,
                             tangent: path.tangent(at: site.parameter))
                }
                return stampSpacing(brushSize: brushSize, fraction: resolved.spacing)
            }
        }
    }

    /// **Turns one dab's resolved §6 outputs into one stamp.** The other half of the matrix: `values`
    /// is what `Brush.dabValues` computed at this site, and this is where those numbers become a
    /// diameter, an alpha, an angle and a colour.
    ///
    /// **The split is values against draws.** Everything in `values` is a pure function of the brush
    /// and the sensors; the two things that additionally need a *draw* from the stroke's own random
    /// field are taken here, because here is where `random` and `arcWidths` are — the scatter offset
    /// and the angle's jitter. That is what lets `BrushDabValues` be answerable by a caller with a
    /// pressure and no stroke (`Brush.dabValues(atPressure:)`).
    ///
    /// **It was three until §2.32.** The density dropout was the third, and deleting its draw is what
    /// makes `density` an ordinary output: it is now compared against a fixed threshold rather than
    /// against a number this function rolls, so a caller that resolves the matrix knows whether a dab
    /// is stamped without knowing where along a stroke it sits.
    ///
    /// **`tangent` is the fourth thing, and it is a geometry rather than a draw** — BRUSH.md §2.30
    /// resolves the scatter onto the *stroke's* frame, so the direction the walk is travelling in has
    /// to arrive here. It is a **unit** vector; both walks take it from the same place the `direction`
    /// sensor does (`StrokePath.tangent(at:)`), so the two cannot drift apart by having two ways to
    /// compute it. Its default is `+x`, which is the honest answer for the callers that stamp one dab
    /// with no stroke around it at all — the size preview and the contact sheet — and is exactly the
    /// heading `BrushInput.direction`'s own neutral of 0 turns names.
    ///
    /// **A dab lays down its `flow` and nothing else — BRUSH.md §2.11.** *"Flow is what one stamp
    /// lays down"*; the stroke's own opacity and its blend mode are the group's business
    /// (`DabTarget.beginStrokeGroup`), applied once when the whole walk merges. So there is no
    /// `brushOpacity` here to multiply in and no `isEraser` to switch a blend mode on: the alpha is
    /// the matrix's `flow` output and the blend is `.normal`, on the eraser exactly as on the brush.
    ///
    /// The eraser reuses this pipeline rather than a special-cased hard circle: it "paints" with the
    /// same tip/matrix/spacing as any other brush, and its dabs accumulate **coverage** which the
    /// group then punches out with `.destinationOut` in one operation. `color` is irrelevant under
    /// that punch (only the coverage's alpha matters), so an eraser's colour is arbitrary.
    ///
    /// `random` and `arcWidths` say **where in the stroke's random field** this dab sits — the field,
    /// and how far along the stroke it is in brush widths. There is one entry point rather than a
    /// seeded and an unseeded one: BRUSH.md §4 leaves nothing that a live dab could roll differently
    /// from a replayed one, and the seed exists at pen-down.
    static func stampDab(into raster: DabTarget, at point: CGPoint, brush: Brush,
                         values: BrushDabValues, color: UIColor, brushSize: CGFloat,
                         random: DabRandom, arcWidths: CGFloat,
                         tangent: CGPoint = CGPoint(x: 1, y: 0)) {
        // **BRUSH.md §2.32 — the dab is stamped when its resolved `density` is at least 0.5.**
        //
        // One comparison, and no draw of its own. Until 2026-09-05 this rolled an intrinsic dice
        // against `values.density` — the one output whose value was not a pure function of its
        // inputs — and the owner's objection is what deleted it: *"I cant change the wavelength or
        // octaves etc. of the random density."* The randomness lives on the chain now, where a
        // randomiser module already carries λ, octaves and a falloff and can itself be curved and
        // scaled, so what used to be a rate is a **gate**.
        //
        // A skip still disturbs nothing, and that is §4's design rather than care taken here: there
        // is no sequence and no phase, so not drawing shifts no value anywhere. The walk's arc
        // length and its spacing are resolved outside this function and advance over a skip exactly
        // as they advance over a `visibleRange` one.
        guard values.density >= BrushDensityGate.threshold else { return }
        let diameter = max(brushSize * CGFloat(values.size), 0.5)
        let radius = diameter / 2
        let alpha = CGFloat(values.flow)
        guard alpha > 0, radius > 0 else { return }

        let stampPoint = applyScatter(to: point, radius: radius,
                                      across: values.scatterAcross, along: values.scatterAlong,
                                      tangent: tangent, random: random, arcWidths: arcWidths)
        let hardness = CGFloat(values.hardness)
        // `.normal` on every dab, brush and eraser alike: the stroke's blend mode is the group's.
        let blendMode = CGBlendMode.normal
        // §6's hue/saturation/brightness outputs. Guarded rather than always applied: both dab caches
        // are keyed on the colour, so a per-dab colour is `DabGradientCache`'s own named pathological
        // case. A brush that asks for colour jitter pays for it; one that does not pays a comparison.
        let inkColor = (values.hueShift != 0 || values.saturationShift != 0 || values.brightnessShift != 0)
            ? BrushColorShift.apply(to: color, hue: values.hueShift,
                                    saturation: values.saturationShift, brightness: values.brightnessShift)
            : color

        // Exhaustive with no `default:`, which is the whole point of `BrushTip` being a
        // payload-carrying enum: a third tip kind is a compile error here rather than a search.
        switch brush.tip {
        case .round:
            // A disc turned is the same disc, so §6's `angle` output reaches only the other arm —
            // which is why `BakedDab.Tip` carries an angle on one case and a hardness on the other.
            raster.stampCircle(at: stampPoint, radius: radius, color: inkColor, alpha: alpha, hardness: hardness, blendMode: blendMode)
        case .stamp(let texture):
            // §4: the jitter is `hash(seed, arcLength)` on its own channel, so it is the same
            // value whichever piece of a split stroke this dab lands in and whatever the refit did
            // to the point count. The `> 0` test is an early-out and nothing more — unlike the
            // sequential stream it replaced, not drawing shifts nothing after it.
            //
            // §6: "Angle has three contributions that sum." The first two are in `values.angleTurns`
            // (turns, so `direction` — which is a fraction of a turn — reaches it with no conversion);
            // the jitter is a draw and is added here, in radians, at ±half a turn when it is 1.
            let jitter: CGFloat = brush.dab.angle.jitter > 0
                ? random.signedUnit(.rotation, at: arcWidths) * .pi * CGFloat(brush.dab.angle.jitter)
                : 0
            let rotation = CGFloat(values.angleTurns) * 2 * .pi + jitter
            // The tip carries which mask, so the artist's own PNG reaches the primitive by the
            // route the committed square already took. There is nothing to resolve here and no
            // second arm: `BrushTextureRef` is the only thing that names a mask.
            raster.stampImage(texture, at: stampPoint, diameter: diameter, angle: rotation,
                              color: inkColor, alpha: alpha, blendMode: blendMode)
        }
    }

    /// **The dab's centre, thrown off the path by up to `radius · 2 · amount` on each axis of the
    /// stroke's own frame** — BRUSH.md §2.30.
    ///
    /// `across` displaces along the **normal**, which widens and frays the silhouette while the ink
    /// stays evenly spaced; `along` displaces down the **tangent**, which widens nothing and instead
    /// bunches and gaps the dabs. They are two independent draws on two `DabRandom` channels — with
    /// no stream to take "the next value" off, the channel is what keeps them independent, and one
    /// channel used twice would put every dab on the same 45° diagonal.
    ///
    /// **The draws are signed, so an amount is a half-extent about the path rather than a push.** A
    /// one-sided offset would bend the stroke rather than fray it.
    ///
    /// **What this deliberately is *not* is the old isotropic disc with two radii.** That version —
    /// keep the free angle, scale its two components — reproduces the old ink exactly when the two
    /// amounts are equal, and it cannot make the axes independent: `cos θ` and `sin θ` come from one
    /// draw, so the along offset is a function of the across one and a brush asking for across alone
    /// still gets a correlated wobble down the path. Two draws is what §2.30's *"modulatable
    /// independently"* means, and the price is the one that ruling states: equal amounts give a
    /// filled square rather than a disc.
    ///
    /// The normal is `(-t.y, t.x)`, the convention `StrokeGeometry.normal(ofSampleAt:)` already uses,
    /// so "across" means the same side of the stroke here as it does everywhere else in the engine.
    static func applyScatter(to point: CGPoint, radius: CGFloat, across: Double, along: Double,
                             tangent: CGPoint, random: DabRandom, arcWidths: CGFloat) -> CGPoint {
        guard across != 0 || along != 0 else { return point }
        let reach = radius * 2
        // Both draws are taken even when one amount is zero. §4 has no stream to keep in phase, so a
        // skipped draw shifts nothing after it and the multiply is cheaper than a second branch.
        let acrossOffset = reach * CGFloat(across) * random.signedUnit(.scatterAcross, at: arcWidths)
        let alongOffset = reach * CGFloat(along) * random.signedUnit(.scatterAlong, at: arcWidths)
        return CGPoint(x: point.x + tangent.x * alongOffset - tangent.y * acrossOffset,
                       y: point.y + tangent.y * alongOffset + tangent.x * acrossOffset)
    }

}

// MARK: - KEYFRAMES.md §4.2 — the rest-space dab bake

extension BrushStamper {

    /// **One dab, in the space its stroke was drawn in.** KEYFRAMES.md §4.2's *"dab record"*.
    ///
    /// It carries the dab's **radius**, not its diameter, and its **centre**, not its position along
    /// the path — a pose touches the centre, the radius, and (for an image tip) the angle, and
    /// nothing else.
    struct BakedDab: Equatable {
        var center: CGPoint
        /// Half the dab's extent: the circle's radius for a round tip, half the mask's side for an
        /// image one. One quantity, so `DabPose` scales it with one multiply whichever tip it is.
        var radius: CGFloat
        var color: UIColor
        var alpha: CGFloat
        var blendMode: CGBlendMode
        var tip: Tip

        /// **Which primitive draws the dab, carrying exactly what that primitive needs.**
        ///
        /// `hardness` and `angle` used to be candidates for flat fields beside `radius`, and both
        /// would have been meaningless on the other arm — a picture has no falloff parameter and a
        /// disc has no orientation. BRUSH.md §9.2 asks for payload-carrying enums for precisely
        /// this, so the illegal states are unrepresentable and `replay`'s switch stays exhaustive
        /// when §12 stage 5 adds a case.
        enum Tip: Equatable {
            case round(hardness: CGFloat)
            /// `angle` turns the mask about the dab's centre, radians, in the rest space the walk
            /// ran in — BRUSH.md §3.5's *"`BakedDab` gains an angle"*. A pose composes its own
            /// rotation onto it; see `DabPose.applied(to:)`.
            case image(BrushTextureRef, angle: CGFloat)
        }
    }

    /// **The pose a baked dab is replayed through — a point map, not a `CGAffineTransform`.**
    /// KEYFRAMES.md §4.2: *"One evaluator over `Homography.map` + `localScale(at:)` serves Uniform,
    /// Freeform and Distort. Three separate arms do not."*
    ///
    /// **`constantScale` is not an optimisation, it is the affine case being a different fact.** An
    /// affine's Jacobian determinant does not vary with position, so `sqrt(|det|)` *is* the local
    /// area root at every dab — LASSO_MOVE.md §5.17's rule, and the number
    /// `VectorCanvas.mapping(_:throughStretch:)` already writes into `VectorStroke.size`. Computing
    /// it once means a Uniform or Freeform pose lands the identical width the shipped path lands,
    /// bit for bit, rather than merely to within a `linearised` round trip. It is a homography whose
    /// `|det J|` varies across the stroke that has no scalar answer, and that is the only case that
    /// pays per dab.
    ///
    /// **`constantRotation` is the same fact about the same case, and it is not an extension by
    /// analogy.** A dab is drawn as a *similarity* — one uniform scale and one angle — so a pose's
    /// effect on it is that pose's Jacobian projected onto the similarity group. An affine's
    /// Jacobian is one matrix everywhere, so both halves of that projection are one number for the
    /// whole stroke; a projective map's Jacobian genuinely varies with position, so both halves
    /// genuinely vary. The angle is *not* deferrable to the same reasoning being redone later,
    /// because a pose that turned a stroke and left its stamps upright is BRUSH.md §3.5's named
    /// failure.
    struct DabPose: Equatable {
        let map: Homography
        /// Nil exactly when the map is projective and the scale has to be asked per dab.
        let constantScale: CGFloat?
        /// Nil exactly when the map is projective and the rotation has to be asked per dab. Same
        /// test, same case, same reason.
        let constantRotation: CGFloat?

        init(_ map: Homography) {
            self.map = map
            // `affine(tolerance: 0)` is a decision, not a threshold — see its own doc comment. A
            // homography built from a `CGAffineTransform` has `g == h == 0` exactly.
            let affine = map.affine()
            constantScale = affine.map { sqrt(abs($0.a * $0.d - $0.b * $0.c)) }
            constantRotation = affine.map(Self.polarRotation)
        }

        /// **The rotation of a Jacobian's polar factor** — the rotation closest to `j` in the
        /// Frobenius sense, so the square this primitive can draw is the closest one to the
        /// parallelogram `j` actually makes of the dab.
        ///
        /// `atan2(b - c, a + d)` is the closed form for a 2×2, and it is the right operand rather
        /// than the obvious alternative: the angle of the *mapped x-axis*, `atan2(b, a)`, agrees on
        /// every rotation and disagrees on every shear — under `[[1, s], [0, 1]]` it reports zero
        /// turn while the tip's own body is visibly leaning. `ARAPRegistration` fits rotations the
        /// same way, for the same reason.
        ///
        /// **A mirroring pose is the stated limit.** With `det j < 0` the polar factor is a
        /// reflection, and a similarity stamp cannot express one; this returns the closest rotation
        /// and the tip comes out unmirrored. That is exactly what the sixteen-circle approximation
        /// this replaces did — it never mirrored either — and for the one shipped tip, a square, a
        /// reflection is a rotation anyway.
        static func polarRotation(_ j: CGAffineTransform) -> CGFloat { j.polarRotation }

        init(_ transform: CGAffineTransform) { self.init(Homography(transform)) }

        static let identity = DabPose(Homography.identity)

        var isIdentity: Bool { map == .identity }

        /// How much this pose magnifies area at `point`, as a linear scale. Nil on the vanishing
        /// line, where the dab has no image at all.
        func scale(at point: CGPoint) -> CGFloat? { constantScale ?? map.localScale(at: point) }

        /// How much this pose turns a tip at `point`. Nil on the vanishing line, as above.
        ///
        /// **Under a projective pose this is a different number at every dab, and that is correct
        /// rather than a cost to be optimised away.** A homography's local rotation genuinely varies
        /// across the plane — it is what makes a receding checkerboard's squares lean differently at
        /// the near and far edges — so any single angle for a whole stroke would be wrong somewhere
        /// along it, and wrong by more the longer the stroke.
        func rotation(at point: CGPoint) -> CGFloat? {
            if let constantRotation { return constantRotation }
            return map.linearised(at: point).map(Self.polarRotation)
        }

        /// One rest-space dab where this pose puts it. Nil where the pose has no image for it.
        func applied(to dab: BakedDab) -> BakedDab? {
            guard let center = map.map(dab.center), let k = scale(at: dab.center) else { return nil }
            var moved = dab
            moved.center = center
            moved.radius = dab.radius * k
            if case .image(let texture, let angle) = dab.tip {
                guard let turn = rotation(at: dab.center) else { return nil }
                moved.tip = .image(texture, angle: angle + turn)
            }
            return moved
        }
    }

    /// **A `DabTarget` that collects instead of drawing** — KEYFRAMES.md §4.2. The dab is computed by
    /// exactly the arithmetic that would have drawn it, and then kept instead of rasterized. Running
    /// `stampStroke` into one *is* the bake.
    ///
    /// It has state, so each bake owns one rather than sharing.
    final class CollectingDabTarget: DabTarget {
        private(set) var dabs: [BakedDab] = []
        /// **The stroke-level merge, kept beside the dabs rather than folded into them** — BRUSH.md
        /// §2.11. A flat `[BakedDab]` cannot carry an opacity cap or a blend mode that belong to the
        /// walk as a whole, and folding either into each dab would be exactly the double-darkening
        /// the cap exists to prevent.
        private(set) var opacity: CGFloat = 1
        private(set) var blendMode: CGBlendMode = .normal
        /// BRUSH.md §2.25's paper, kept beside the dabs for the same reason the two above are: it is
        /// a property of the merge, and a per-dab copy would be the sprite §2.4 deleted.
        private(set) var texture: BrushTextureSettings?
        init() {}
        func beginStroke() {}
        func endStroke() {}
        func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {
            self.opacity = opacity
            self.blendMode = blendMode
            self.texture = texture
        }
        func endStrokeGroup() {}
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            dabs.append(BakedDab(center: point, radius: radius, color: color, alpha: alpha,
                                 blendMode: blendMode, tip: .round(hardness: hardness)))
        }

        func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                        angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
            dabs.append(BakedDab(center: point, radius: diameter / 2, color: color, alpha: alpha,
                                 blendMode: blendMode, tip: .image(texture, angle: angle)))
        }
    }

    /// **A `DabTarget` that maps every dab through a pose on the way out** — the streaming form of
    /// bake-then-replay, and what the render path uses.
    ///
    /// Wrapping the sink rather than the walk is the whole trick, and it is what makes this stage
    /// small: `stampStroke`, `stampDab` and `applyScatter` all run **unchanged, in rest space** —
    /// §2.30's stroke frame included, so a posed dab is scattered about the *rest* tangent and then
    /// mapped, which is what stops the offset re-rolling as a pose turns the stroke — so
    /// the dab count, the dab phase and the arc lengths the random field is addressed at — including
    /// the rotation jitter an image dab draws — are invariant across every frame of an animation *by
    /// construction* rather than by arithmetic that happens to agree. Only the three numbers a pose
    /// can legitimately change — where the dab is, how big it is, and which way a picture faces — are
    /// touched, and
    /// they are touched last.
    ///
    /// `beginStroke`/`endStroke` forward, because the wrapped target may be a `RasterLayerTexture`
    /// keeping a stroke count.
    final class PosedDabTarget: DabTarget {
        private let inner: DabTarget
        private let pose: DabPose

        init(_ inner: DabTarget, pose: DabPose) {
            self.inner = inner
            self.pose = pose
        }

        func beginStroke() { inner.beginStroke() }
        func endStroke() { inner.endStroke() }

        /// Forwarded untouched. A pose moves, scales and turns *dabs*; it has no opinion about what
        /// the finished stroke may reach or how it meets what is under it — and because the merge's
        /// buffer is sized from the dabs it is actually handed (`DabTarget.beginStrokeGroup`), the
        /// posed dabs bound it with no transform of a rectangle to get wrong.
        func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {
            inner.beginStrokeGroup(opacity: opacity, blendMode: blendMode, texture: texture)
        }
        func endStrokeGroup() { inner.endStrokeGroup() }

        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            guard let center = pose.map.map(point), let k = pose.scale(at: point) else { return }
            inner.stampCircle(at: center, radius: radius * k, color: color,
                              alpha: alpha, hardness: hardness, blendMode: blendMode)
        }

        /// The image arm asks the pose for one thing more than the round arm does, because there is
        /// one thing more that a pose can change about a picture and cannot change about a disc.
        func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                        angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
            guard let center = pose.map.map(point), let k = pose.scale(at: point),
                  let turn = pose.rotation(at: point) else { return }
            inner.stampImage(texture, at: center, diameter: diameter * k, angle: angle + turn,
                             color: color, alpha: alpha, blendMode: blendMode)
        }
    }

    /// **A whole baked walk: its dabs, and the merge they belong to.**
    ///
    /// The opacity and the blend mode are here rather than on `BakedDab` because BRUSH.md §2.11 puts
    /// them on the *stroke*: they are applied once, over all the dabs together, and a per-dab copy of
    /// either would reintroduce exactly the double-darkening the cap exists to prevent.
    struct BakedStroke: Equatable {
        var dabs: [BakedDab]
        var opacity: CGFloat
        var blendMode: CGBlendMode
        /// BRUSH.md §2.25's paper. **Baked strokes carry it unbaked, and that is the point of
        /// canvas-anchoring**: a posed frame maps the dabs and the paper stays exactly where it was,
        /// so there is nothing to re-sample per frame — which is §2.5's argument, and the reason the
        /// owner's stroke-anchored alternative was the expensive one.
        var texture: BrushTextureSettings?
    }

    /// Walks a stroke in **rest space** and keeps its dabs instead of drawing them. Same arguments as
    /// `stampStroke`, because it is `stampStroke` — into a collector.
    static func bake(samples: StrokeSamples, brush: Brush, color: UIColor, brushSize: CGFloat,
                     brushOpacity: Double, isEraser: Bool = false,
                     random: DabRandom, visibleRange: ClosedRange<CGFloat>? = nil) -> BakedStroke {
        let collector = CollectingDabTarget()
        stampStroke(into: collector, samples: samples, brush: brush, color: color,
                    brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser,
                    random: random, visibleRange: visibleRange)
        return BakedStroke(dabs: collector.dabs, opacity: collector.opacity,
                           blendMode: collector.blendMode, texture: collector.texture)
    }

    /// Draws a baked walk through a pose. The replay entry point §4.2 asks for, and the same
    /// arithmetic `PosedDabTarget` applies — shared through `DabPose.applied(to:)` so a stored bake
    /// and a streamed one cannot drift.
    ///
    /// The stroke's own group is opened round the replay, so a bake drawn back lands the same pixels
    /// the walk that produced it would have — cap included.
    ///
    /// A dab the pose has no image for is dropped rather than clamped: it is behind the vanishing
    /// line, where there is no answer to draw.
    static func replay(_ stroke: BakedStroke, into target: DabTarget, through pose: DabPose) {
        target.beginStroke()
        target.beginStrokeGroup(opacity: stroke.opacity, blendMode: stroke.blendMode,
                                texture: stroke.texture)
        for dab in stroke.dabs {
            guard let moved = pose.applied(to: dab) else { continue }
            switch moved.tip {
            case .round(let hardness):
                target.stampCircle(at: moved.center, radius: moved.radius, color: moved.color,
                                   alpha: moved.alpha, hardness: hardness, blendMode: moved.blendMode)
            case .image(let texture, let angle):
                target.stampImage(texture, at: moved.center, diameter: moved.radius * 2, angle: angle,
                                  color: moved.color, alpha: moved.alpha, blendMode: moved.blendMode)
            }
        }
        target.endStrokeGroup()
        target.endStroke()
    }
}
