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

    /// Walks from `last` toward `point`, invoking `body` at each `spacing`-sized step along the way,
    /// and returns the position of the final stamp — the carry point the next walk continues from.
    /// When the two points are closer together than one spacing, nothing is stamped and `last` comes
    /// straight back, so the leftover distance accumulates into the next call instead of being
    /// stamped short (which is what keeps a slow drag from bunching dabs up at the start).
    ///
    /// **The live preview's walk, and only the live preview's.** `stampStroke` below replays a
    /// *stored* stroke, whose points are a refit at a fixed tolerance rather than the input, and so
    /// walks `StrokePath`'s curve instead — see there. This one is called once per incoming touch
    /// sample, at input density, where the straight line between two consecutive samples and the
    /// curve through them are the same line to well under a pixel; it holds its carry point in a
    /// property across calls, which is why the carry is returned rather than stored.
    /// Each callback receives the dab's normalised position `t ∈ (0, 1]` along the `last`→`point`
    /// segment, so the caller can resolve §6's matrix per dab across the pair of samples this walk
    /// bridges instead of applying one endpoint's reading to all of them.
    ///
    /// **`spacing` is `inout` and the body answers with the next one**, exactly as
    /// `StrokePath.advance` does and for the same reason: BRUSH.md §6 makes spacing a sensor-driven
    /// output, so the gap between two dabs belongs to the dab the walk is leaving. It is `inout` so
    /// the value survives across the per-touch-sample calls this walk is made of, alongside the caller's
    /// own carry point.
    static func advance(from last: CGPoint, to point: CGPoint, spacing: CGFloat,
                        _ body: (CGPoint, CGFloat, CGFloat) -> CGFloat) -> (carry: CGPoint, spacing: CGFloat) {
        let dx = point.x - last.x, dy = point.y - last.y
        let distance = hypot(dx, dy)
        var spacing = spacing
        guard spacing > 0, distance > 0 else { return (last, spacing) }
        var travelled: CGFloat = 0
        while travelled + spacing <= distance {
            travelled += spacing
            let t = travelled / distance
            let walked = spacing
            spacing = max(body(CGPoint(x: last.x + dx * t, y: last.y + dy * t), t, walked),
                          StrokePath.minimumDabSpacing)
        }
        // Nothing placed: the leftover distance accumulates into the next call instead of being
        // stamped short, which is what keeps a slow drag from bunching dabs up at the start.
        guard travelled > 0 else { return (last, spacing) }
        let coveredT = travelled / distance
        return (CGPoint(x: last.x + dx * coveredT, y: last.y + dy * coveredT), spacing)
    }

    /// Replays a whole stroke (spacing-interpolated between samples, exactly like
    /// `StrokeCanvasView.stampPath`) into `raster`, as one `beginStroke`/`endStroke` unit.
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
    /// `visibleRange` or by §2.18's density — for exactly the reason arc length advances over a
    /// skipped dab: the lattice is a property of the walk, not of what came out of it. A cut piece and
    /// the uncut stroke march identically or the zero-tolerance parity net fails on the first dab past
    /// the cut.
    static func stampStroke(into raster: DabTarget, samples: StrokeSamples, brush: Brush,
                            color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool = false,
                            random: DabRandom, visibleRange: ClosedRange<CGFloat>? = nil) {
        guard !samples.isEmpty else { return }
        raster.beginStroke()
        let path = StrokePath(points: samples.positions)
        // **BRUSH.md §13's open question, answered by §12 stage 7: a *replay* knows how long the
        // stroke is, and a live walk does not.** This one is replaying stored geometry, so the length
        // is measurable — and is measured, once, only when a row actually asks for `taper`, because
        // it is a second flattening pass over the curve and no other brush should pay for it. The
        // live walk (`StrokeCanvasView.stampPath`) stamps as the pen moves and genuinely cannot know,
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
                     color: color, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser,
                     random: random, arcWidths: arcWidths)
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
                    stampDab(into: raster, at: dab, brush: brush, values: resolved,
                             color: color, brushSize: brushSize, brushOpacity: brushOpacity,
                             isEraser: isEraser, random: random, arcWidths: arcWidths)
                }
                return stampSpacing(brushSize: brushSize, fraction: resolved.spacing)
            }
        }
        raster.endStroke()
    }

    /// **Turns one dab's resolved §6 outputs into one stamp.** The other half of the matrix: `values`
    /// is what `Brush.dabValues` computed at this site, and this is where those numbers become a
    /// diameter, an alpha, an angle and a colour.
    ///
    /// **The split is values against draws.** Everything in `values` is a pure function of the brush
    /// and the sensors; the three things that additionally need a *draw* from the stroke's own random
    /// field are taken here, because here is where `random` and `arcWidths` are — §2.18's density
    /// dropout, the scatter offset, and the angle's jitter. That is what lets `BrushDabValues` be
    /// answerable by a caller with a pressure and no stroke (`Brush.dabValues(atPressure:)`).
    ///
    /// The eraser reuses this exact pipeline rather than a special-cased hard circle: it "paints"
    /// with the same tip/matrix/spacing as any other brush, just composited with `.destinationOut`
    /// instead of the brush's own blend mode — i.e. painting with 0 opacity as the color, so its
    /// stamp punches a hole instead of adding color. `color` is irrelevant under `.destinationOut`
    /// (only the stamp's alpha coverage matters), so it's ignored for an eraser dab.
    ///
    /// `random` and `arcWidths` say **where in the stroke's random field** this dab sits — the field,
    /// and how far along the stroke it is in brush widths. There is one entry point rather than a
    /// seeded and an unseeded one: BRUSH.md §4 leaves nothing that a live dab could roll differently
    /// from a replayed one, and the seed exists at pen-down.
    static func stampDab(into raster: DabTarget, at point: CGPoint, brush: Brush,
                         values: BrushDabValues, color: UIColor, brushSize: CGFloat,
                         brushOpacity: Double, isEraser: Bool,
                         random: DabRandom, arcWidths: CGFloat) {
        // **BRUSH.md §2.18 — the dab is skipped when its draw exceeds its density.**
        //
        // A skip disturbs nothing, and that is §4's design rather than care taken here: there is no
        // sequence and no phase, so not drawing shifts no value anywhere. The walk's arc length and
        // its spacing are resolved outside this function and advance over a skip exactly as they
        // advance over a `visibleRange` one. The `< 1` guard is an early-out only — a density of 1 is
        // never exceeded by a draw in `0..<1`, so taking the draw would change nothing but the clock.
        if values.density < 1 {
            let draw = random.unit(.density, at: arcWidths, wavelength: brush.dab.densityWavelength)
            guard Double(draw) <= values.density else { return }
        }
        let diameter = max(brushSize * CGFloat(values.size), 0.5)
        let radius = diameter / 2
        let alpha = CGFloat(brushOpacity) * CGFloat(values.flow) * CGFloat(values.opacity)
        guard alpha > 0, radius > 0 else { return }

        let stampPoint = applyScatter(to: point, radius: radius, scatter: values.scatter,
                                      random: random, arcWidths: arcWidths)
        let hardness = CGFloat(values.hardness)
        let blendMode = isEraser ? CGBlendMode.destinationOut : brush.stroke.blendMode.cgBlendMode
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

    /// The dab's centre, thrown off the path by up to `radius · 2 · scatter`.
    ///
    /// Angle and distance are two draws at one arc length and so come from two `DabRandom` channels —
    /// with no stream to take "the next value" off, the channel is what keeps them independent.
    static func applyScatter(to point: CGPoint, radius: CGFloat, scatter: Double,
                             random: DabRandom, arcWidths: CGFloat) -> CGPoint {
        guard scatter > 0 else { return point }
        let maxOffset = radius * 2 * CGFloat(scatter)
        let angle = random.unit(.scatterAngle, at: arcWidths) * 2 * .pi
        let distance = random.unit(.scatterDistance, at: arcWidths) * maxOffset
        return CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
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
        init() {}
        func beginStroke() {}
        func endStroke() {}
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
    /// small: `stampStroke`, `stampDab` and `applyScatter` all run **unchanged, in rest space**, so
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

    /// Walks a stroke in **rest space** and keeps its dabs instead of drawing them. Same arguments as
    /// `stampStroke`, because it is `stampStroke` — into a collector.
    static func bake(samples: StrokeSamples, brush: Brush, color: UIColor, brushSize: CGFloat,
                     brushOpacity: Double, isEraser: Bool = false,
                     random: DabRandom, visibleRange: ClosedRange<CGFloat>? = nil) -> [BakedDab] {
        let collector = CollectingDabTarget()
        stampStroke(into: collector, samples: samples, brush: brush, color: color,
                    brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser,
                    random: random, visibleRange: visibleRange)
        return collector.dabs
    }

    /// Draws a baked walk through a pose. The replay entry point §4.2 asks for, and the same
    /// arithmetic `PosedDabTarget` applies — shared through `DabPose.applied(to:)` so a stored bake
    /// and a streamed one cannot drift.
    ///
    /// A dab the pose has no image for is dropped rather than clamped: it is behind the vanishing
    /// line, where there is no answer to draw.
    static func replay(_ dabs: [BakedDab], into target: DabTarget, through pose: DabPose) {
        target.beginStroke()
        for dab in dabs {
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
        target.endStroke()
    }
}
