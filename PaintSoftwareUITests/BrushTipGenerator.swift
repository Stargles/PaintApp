import UIKit
import CoreGraphics

/// **BRUSH.md §12 stage 9's tip generator** — the procedural half of §8.4's *"generate Basics,
/// Sketching, Inking and Painting; source CC0 only for Texture"*.
///
/// **It is a build-time tool whose output is committed, not a runtime cost.** §12 stage 9 rules
/// that explicitly — *"a tip is a small alpha bitmap and generating it per launch buys nothing"* —
/// which is why this lives in the test target beside `DabCostBench` rather than in `Engine`.
/// Nothing in the app links it; `BrushContactSheetBench` runs it, writes the PNGs, and the owner
/// picks from the sheet. Only once they have picked does a chosen PNG become a
/// `BuiltInBrushTexture` case with its bytes committed to `Resources/`.
///
/// **Deterministic by construction, and that is the property that makes committing safe.** Every
/// value here comes from `splitmix64` over integer lattice coordinates and a written-down seed —
/// there is no `Double.random`, no `arc4random`, no clock and no dictionary iteration order in the
/// output path. Regenerating gives the identical bytes, so a committed PNG can always be shown to
/// be the one this file draws. `BrushTipGeneratorLogicTests` is the assertion.
///
/// **What is deliberately not generated, and §8.4 is the reason rather than an omission:**
///
/// - **The rough ink nib.** §8.4 MEASURED an eroded disc at 0.41% of a brush width of edge
///   roughness in a stroke against 3.6% for `random → size`, and found deeper erosion *not even
///   monotonic*. The nib is §2.17's λ and §2.18's `density` on a clean round tip and needs no
///   picture. `BrushCandidates` carries three of them and they own no file here.
/// - **Soft and hard round, the technical pens, and the opaque round.** `BrushTip.round` already
///   *is* a disc with a falloff; §8.4's *"a hard round is a disc, a soft round a falloff"* is a
///   description of the procedural arm, not an instruction to draw one. A generated near-disc would
///   be the eroded tip §8.4 refuted, one indirection later.
/// - **The Texture group.** §8.6's grunge, splatter, stipple and chalk are §12 stage 11's CC0
///   sourcing, because scanned grunge is what §8.4 says is genuinely hard to fake.
///
/// **A tip's silhouette has to be discriminating, and that is checked rather than assumed.** §12
/// stage 5 records the trap in this document's own back yard: *"a tip that fills its mask is
/// indistinguishable from the committed square, so an assertion built on that arm alone would be
/// green against a stamper that ignored the tip"*. Every shape below leaves a clear corner, a clear
/// gap, or both — and `BrushTipGeneratorLogicTests` stamps each one against `.builtIn(.square)` and
/// requires the pixels to differ.
enum BrushTipGenerator {

    /// The mask side and border every tip is drawn at — `BrushTipImport`'s, so a generated tip and
    /// an artist's imported one are the same kind of file. 256² at a 2 px transparent border is
    /// `BuiltInBrushTexture.square`'s own specification, and the border is what a rotated or
    /// downscaled draw antialiases into.
    static let side: Int = BrushTipImport.maskSide
    static let border: Int = BrushTipImport.border

    /// Half the usable span, in mask pixels: 128 - 2. Normalised tip coordinates run `-1…1` over
    /// exactly this, so `|u| > 1` is inside the transparent border by construction and no shape can
    /// reach the edge however it is authored.
    static let halfSpan: Float = Float(side / 2 - border)

    /// One mask pixel, in normalised tip units. The natural width for a "hard" edge: anything
    /// narrower is a step, anything wider is visibly soft at the sizes a nib is used.
    static let pixel: Float = 1 / halfSpan

    // MARK: - What a generated tip is

    struct Tip {
        /// The candidate's own name, e.g. `square-slab-4to1`. Stable — it is what the contact sheet
        /// prints and what a committed `BuiltInBrushTexture` case would be named after.
        let name: String
        /// The file it is written under in `BrushStorage`. Deterministic rather than a UUID, so a
        /// regeneration overwrites its own file instead of littering the library.
        let fileName: String
        /// Row-major coverage, `side * side` bytes, top row first. The generator's real output —
        /// `png` is this run through ImageIO, and the determinism assertion is on both.
        let alpha: [UInt8]
        let png: Data

        var textureRef: BrushTextureRef { .imported(fileName: fileName) }
        var tip: BrushTip { .stamp(textureRef) }
    }

    // MARK: - The catalogue

    /// Every generated tip, in a fixed order. An array rather than a dictionary for the reason
    /// `BrushModulations` is one: iteration order has to be a property of the source, not of a hash
    /// seed, or "generate twice and compare" is testing the wrong thing.
    static func generateAll() -> [Tip] {
        shapes.map { render($0) }
    }

    static let shapes: [Shape] = [

        // MARK: Basics — the square slab and the chisel

        // **§8.6's "square", which is not a square.** *"A rectangle whose long side sits
        // perpendicular to the direction of travel, with deliberately ragged edges. One drag lays
        // down one rectangular slab."* The long axis is drawn along **u** and the perpendicularity
        // is the brush's `angle.base = 0.25` turns with `directionFollow = 1` — §8.6's own
        // arithmetic, and why this nib needs no `roundness`: a rough rectangle drawn inside a square
        // mask is a rough rectangle.
        //
        // The raggedness is two octaves on each of the four edges: a coarse tear at ~3 cycles across
        // the nib and a fine fray at ~11. One octave alone reads either as a wobble or as fuzz; the
        // reference the owner supplied has both.
        // **The two roughnesses are not equally visible and the sheet showed which.** With the base
        // turn at a quarter and follow at 1, the nib's *long* edges sweep along the travel and its
        // *ends* trace the stroke's two edges — so `endRough` is what an artist sees on a drag and
        // `edgeRough` only shows at the caps and where a stroke crosses itself. Both are cranked
        // well past what looked right on the mask for that reason.
        Shape(name: "square-slab-4to1", seed: 0x5148_0001,
              body: { u, v, s in slab(u, v, s, aspect: 4.0, edgeRough: 0.20, endRough: 0.26) }),

        Shape(name: "square-slab-2p5to1", seed: 0x5148_0002,
              body: { u, v, s in slab(u, v, s, aspect: 2.5, edgeRough: 0.34, endRough: 0.40) }),

        // **The chisel.** A cut edge, so the long sides are hard and straight and the raggedness the
        // slab has would be wrong: what makes a chisel a chisel is that one side of the stroke is a
        // clean line. The ends are slanted, which is what makes it a calligraphy nib rather than a
        // narrow slab — held at a fixed `angle.base` with no direction-follow, it thickens and thins
        // as the stroke turns, and that is the whole effect.
        Shape(name: "chisel-5to1", seed: 0x5148_0003,
              body: { u, v, _ in chisel(u, v, aspect: 5.0, slant: 0.34) }),

        // MARK: Sketching — four pencils

        // **A pencil is a mid-frequency noise threshold** (§8.4) on an irregular nib. The four differ
        // in the grain's frequency and how hard it is thresholded, which is what separates a hard
        // pencil's tooth from a soft one's smear, plus the nib's own outline.
        Shape(name: "pencil-hard", seed: 0x5148_0011,
              grain: Grain(frequency: 26, octaves: 2, floor: 0.05, threshold: 0.44, softness: 0.16),
              body: { u, v, s in nib(u, v, s, radius: 0.74, wobble: 0.10, wobbleFrequency: 5.5,
                                     edge: 1.6 * pixel, falloff: 0.05) }),

        Shape(name: "pencil-soft", seed: 0x5148_0012,
              grain: Grain(frequency: 13, octaves: 2, floor: 0.34, threshold: 0.30, softness: 0.42),
              body: { u, v, s in nib(u, v, s, radius: 0.95, wobble: 0.07, wobbleFrequency: 4.0,
                                     edge: 1.6 * pixel, falloff: 0.34) }),

        // **Blunt** — a worn nib, flattened on one side and wider than it is tall. The flat is the
        // discriminating feature: it is what makes the stroke's edge read as a chisel on one side
        // and a pencil on the other, and it is why this one takes a large `angle.jitter` in
        // `BrushCandidates` (§8.5 — rotating per dab is what breaks the sawtooth a repeated stamp
        // otherwise combs onto the stroke's edge).
        Shape(name: "pencil-blunt", seed: 0x5148_0013,
              grain: Grain(frequency: 9, octaves: 2, floor: 0.22, threshold: 0.26, softness: 0.34),
              body: { u, v, s in
                  let body = nib(u, v * 1.30, s, radius: 0.94, wobble: 0.09, wobbleFrequency: 3.5,
                                 edge: 1.6 * pixel, falloff: 0.10)
                  // The worn flat: everything past v = 0.30 is ground away.
                  return body * step(0.30 - v, 3 * pixel)
              }),

        // **Textured** — coarse enough that the holes survive into the stroke. §8.4's warning is
        // about *edge* erosion on a round tip; interior pits at this frequency are a different
        // mechanism and do survive the union, because a neighbouring dab's pits are at a different
        // phase only when the tip is also rotated per dab.
        Shape(name: "pencil-textured", seed: 0x5148_0014,
              grain: Grain(frequency: 6.5, octaves: 3, floor: 0.0, threshold: 0.46, softness: 0.13),
              body: { u, v, s in nib(u, v, s, radius: 0.96, wobble: 0.06, wobbleFrequency: 3.0,
                                     edge: 1.6 * pixel, falloff: 0.12) }),

        // MARK: Inking — the brush pen's nib

        // **A brush pen's nib is a teardrop that lies along the travel**, which is `directionFollow`
        // at 1 with no base turn. The taper an artist sees is mostly `size ← pressure`; what the
        // *shape* adds is the asymmetry — the trailing end is blunter than the leading one, so a
        // stroke that turns leaves a slightly different edge on the inside of the curve.
        Shape(name: "pen-brush", seed: 0x5148_0021,
              body: { u, v, _ in teardrop(u, v, halfHeight: 0.50, point: 0.72, lean: 0.22,
                                          soft: 0.20) }),

        // MARK: Painting — flat, bristle, blender

        // **The painting flat.** Like the slab but softer at the long edges and cleanly rounded at
        // the ends: a loaded flat brush does not tear, it feathers. Held at a fixed angle in
        // `BrushCandidates` rather than following the travel, which is how a flat is actually used.
        Shape(name: "paint-flat", seed: 0x5148_0031,
              grain: Grain(frequency: 4.5, octaves: 2, floor: 0.78, threshold: 0.0, softness: 1.0),
              body: { u, v, s in flat(u, v, s, aspect: 3.0, soft: 0.10, edgeRough: 0.10) }),

        // **Bristle — several parallel filaments**, which is §8.5's shaped tip and the one place
        // that section says a *variant set* earns its keep: *"the variant set earns its keep for
        // shaped tips (bristle, chalk, splatter) and not for a rough round"*. Three are generated so
        // the set exists; only the first is reachable today, because `BrushTip.stamp` carries one
        // `BrushTextureRef` and the per-dab pick §8.5 describes is not built.
        Shape(name: "paint-bristle-0", seed: 0x5148_0041,
              body: { u, v, s in bristle(u, v, s, filaments: 11) }),
        Shape(name: "paint-bristle-1", seed: 0x5148_0042,
              body: { u, v, s in bristle(u, v, s, filaments: 9) }),
        Shape(name: "paint-bristle-2", seed: 0x5148_0043,
              body: { u, v, s in bristle(u, v, s, filaments: 13) }),

        // **The blender** — a soft, mottled, low-coverage cloud. It has no hard edge anywhere, which
        // is exactly what makes it a blender rather than a soft round: the mottle means two passes
        // over the same area do not land the same coverage, so it smears rather than building.
        Shape(name: "paint-blender", seed: 0x5148_0051,
              grain: Grain(frequency: 3.2, octaves: 3, floor: 0.30, threshold: 0.0, softness: 1.0),
              body: { u, v, _ in
                  let r: Float = sqrt(u * u + v * v)
                  return 0.62 * smoothFalloff(1 - r, 0.75)
              })
    ]

    // MARK: - The shape vocabulary
    //
    // Every one takes normalised tip coordinates `u, v` in `-1…1` and answers coverage in `0…1`.
    // They are pure functions of their arguments and the seed, which is the whole of what "seeded,
    // deterministic" means here.

    /// **§8.6's slab.** A rectangle of the given aspect with all four edges displaced by two octaves
    /// of seeded noise — a coarse tear plus a fine fray. The displacement is signed (`2n - 1`), not
    /// an erosion, so the nib keeps its nominal area: an erosion-only edge would quietly make a
    /// 4:1 slab thinner than 4:1.
    static func slab(_ u: Float, _ v: Float, _ seed: UInt64,
                     aspect: Float, edgeRough: Float, endRough: Float) -> Float {
        let halfV: Float = 1 / aspect
        let top: Float = -halfV * (1 + edgeRough * ragged(u, seed &+ 1))
        let bottom: Float = halfV * (1 + edgeRough * ragged(u, seed &+ 2))
        let left: Float = -1 * (1 + endRough * ragged(v * aspect, seed &+ 3))
        let right: Float = 1 * (1 + endRough * ragged(v * aspect, seed &+ 4))
        let dv: Float = max(v - bottom, top - v)
        let du: Float = max(u - right, left - u)
        return step(-max(du, dv), 1.2 * pixel)
    }

    /// A chisel blade: hard straight long edges, ends cut on a slant. No noise at all — the point of
    /// a chisel is the clean line, and roughening it makes it a slab.
    static func chisel(_ u: Float, _ v: Float, aspect: Float, slant: Float) -> Float {
        let halfV: Float = 1 / aspect
        let sheared: Float = u + slant * v * aspect
        let du: Float = abs(sheared) - 0.97
        let dv: Float = abs(v) - halfV
        return step(-max(du, dv), 1.1 * pixel)
    }

    /// A pencil's outline: a disc whose radius wobbles with the angle, optionally fading over the
    /// last `falloff` of it.
    ///
    /// The angular noise is sampled on the **unit circle** rather than on an angle, so it wraps: a
    /// 1-D noise indexed by `atan2` has a seam at `-π`, which shows up as one straight facet on
    /// every dab and is exactly the sort of artifact a repeated stamp turns into a stripe.
    static func nib(_ u: Float, _ v: Float, _ seed: UInt64,
                    radius: Float, wobble: Float, wobbleFrequency: Float,
                    edge: Float, falloff: Float) -> Float {
        let r: Float = sqrt(u * u + v * v)
        guard r > 1e-4 else { return 1 }
        let cx: Float = u / r, cy: Float = v / r
        let n: Float = value2(cx * wobbleFrequency + 7.3, cy * wobbleFrequency + 3.1, seed)
        let rr: Float = radius * (1 + wobble * (2 * n - 1))
        let hard: Float = step(rr - r, edge)
        guard falloff > 1e-4 else { return hard }
        return hard * smoothFalloff(rr - r, falloff)
    }

    /// The brush pen's teardrop, long axis along `u`. `point` sharpens the leading end and `lean`
    /// biases the width toward the trailing one.
    static func teardrop(_ u: Float, _ v: Float,
                         halfHeight: Float, point: Float, lean: Float, soft: Float) -> Float {
        let along: Float = min(max(1 - u * u, 0), 1)
        let width: Float = halfHeight * pow(along, point) * (1 - lean * u)
        guard width > 1e-4 else { return 0 }
        return smoothFalloff(width - abs(v), soft * halfHeight) * step(width - abs(v), 1.2 * pixel)
    }

    /// The painting flat: a rounded-ended bar, softly feathered along its long edges.
    static func flat(_ u: Float, _ v: Float, _ seed: UInt64,
                     aspect: Float, soft: Float, edgeRough: Float) -> Float {
        let halfV: Float = 1 / aspect
        let edge: Float = halfV * (1 + edgeRough * ragged(u, seed &+ 5))
        // A superellipse in u so the ends are round rather than cut.
        let endFade: Float = smoothFalloff(1 - pow(abs(u), 3.0), 0.22)
        return smoothFalloff(edge - abs(v), soft) * endFade
    }

    /// **Several parallel filaments**, running along `u` so the brush's `directionFollow` lays them
    /// along the travel. Each filament's centre, half-width and alpha are seeded draws, and each is
    /// broken along its length by 1-D noise: a bristle brush's streaks are not continuous.
    static func bristle(_ u: Float, _ v: Float, _ seed: UInt64, filaments: Int) -> Float {
        let envelope: Float = step(1 - sqrt(u * u + (v / 0.44) * (v / 0.44)), 0.12)
        guard envelope > 0 else { return 0 }
        var coverage: Float = 0
        for i in 0..<filaments {
            let s: UInt64 = seed &+ UInt64(i) &* 0x9E37_79B9
            let slot: Float = (Float(i) + 0.5) / Float(filaments)
            let centre: Float = (slot * 2 - 1) * 0.42 + (hash01(i, 1, s) - 0.5) * 0.05
            let halfWidth: Float = 0.010 + 0.022 * hash01(i, 2, s)
            let peak: Float = 0.55 + 0.45 * hash01(i, 3, s)
            var f: Float = smoothFalloff(halfWidth - abs(v - centre), 0.9 * halfWidth)
            guard f > 0 else { continue }
            // Along the filament: a slow break-up, never fully closing.
            f *= 0.45 + 0.55 * value1(u * 5.5 + Float(i) * 17.0, s &+ 0x51)
            coverage = max(coverage, f * peak)
        }
        return coverage * envelope
    }

    // MARK: - Edge and falloff helpers

    /// A hard-ish edge: 1 where `d` is comfortably positive, 0 where comfortably negative, one ramp
    /// of width `w` between. `d` is "how far inside", so callers pass `boundary - position`.
    @inline(__always)
    static func step(_ d: Float, _ w: Float) -> Float {
        guard w > 1e-6 else { return d > 0 ? 1 : 0 }
        return min(max(d / w + 0.5, 0), 1)
    }

    /// A smooth falloff over the last `w` of the inside: 1 well inside, 0 outside, smoothstepped.
    @inline(__always)
    static func smoothFalloff(_ d: Float, _ w: Float) -> Float {
        guard w > 1e-6 else { return d > 0 ? 1 : 0 }
        let t: Float = min(max(d / w, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Two octaves of signed 1-D noise in `-1…1` — a coarse tear at ~3 cycles across the nib and a
    /// fine fray at ~11. §8.4's *"several `random` rows at different λ give multi-scale
    /// roughness"*, one level down: the same argument applies to a tip's outline.
    @inline(__always)
    static func ragged(_ t: Float, _ seed: UInt64) -> Float {
        let coarse: Float = value1(t * 3.0, seed)
        let fine: Float = value1(t * 11.0, seed &+ 0x5BF0_3635)
        return (0.66 * coarse + 0.34 * fine) * 2 - 1
    }

    // MARK: - Deterministic noise

    /// `splitmix64`'s mixer — the same one `DabRandom` hashes with, for the same reason: it is a
    /// bijection with good avalanche and no state.
    @inline(__always)
    static func mix(_ x: UInt64) -> UInt64 {
        var z: UInt64 = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A lattice draw in `0..<1`. Integer coordinates only — a float coordinate would make the value
    /// depend on rounding and the field would not be reproducible across architectures.
    @inline(__always)
    static func hash01(_ a: Int, _ b: Int, _ seed: UInt64) -> Float {
        let ha: UInt64 = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        let hb: UInt64 = UInt64(bitPattern: Int64(b)) &* 0xC2B2_AE3D_27D4_EB4F
        return Float(mix(ha ^ hb ^ seed) >> 40) / Float(1 << 24)
    }

    @inline(__always)
    static func floorInt(_ x: Float) -> Int {
        let i = Int(x)
        return x < 0 && Float(i) != x ? i - 1 : i
    }

    /// Smooth 1-D value noise in `0…1`.
    @inline(__always)
    static func value1(_ x: Float, _ seed: UInt64) -> Float {
        let xi: Int = floorInt(x)
        let fx: Float = x - Float(xi)
        let s: Float = fx * fx * (3 - 2 * fx)
        let a: Float = hash01(xi, 0, seed)
        let b: Float = hash01(xi + 1, 0, seed)
        return a + (b - a) * s
    }

    /// Smooth 2-D value noise in `0…1`.
    @inline(__always)
    static func value2(_ x: Float, _ y: Float, _ seed: UInt64) -> Float {
        let xi: Int = floorInt(x), yi: Int = floorInt(y)
        let fx: Float = x - Float(xi), fy: Float = y - Float(yi)
        let sx: Float = fx * fx * (3 - 2 * fx)
        let sy: Float = fy * fy * (3 - 2 * fy)
        let a: Float = hash01(xi, yi, seed)
        let b: Float = hash01(xi + 1, yi, seed)
        let c: Float = hash01(xi, yi + 1, seed)
        let d: Float = hash01(xi + 1, yi + 1, seed)
        let top: Float = a + (b - a) * sx
        let bottom: Float = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    static func fbm2(_ x: Float, _ y: Float, octaves: Int, seed: UInt64) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, norm: Float = 0
        var fx: Float = x, fy: Float = y
        for octave in 0..<octaves {
            sum += amplitude * value2(fx, fy, seed &+ UInt64(octave) &* 0x0100_0193)
            norm += amplitude
            amplitude *= 0.5
            fx *= 2
            fy *= 2
        }
        return norm > 0 ? sum / norm : 0
    }

    // MARK: - Grain

    /// A tip's interior texture. Multiplies the silhouette's coverage, so it can only ever take ink
    /// away — a grain that could add would paint outside the nib.
    struct Grain {
        /// Cycles across the whole tip.
        var frequency: Float
        var octaves: Int
        /// What the grain reads where the noise is at its lowest. `0` punches holes; `0.3` is a
        /// mottle.
        var floor: Float
        /// Noise below this is the floor. `0` with `softness: 1` is a plain mottle with no pits.
        var threshold: Float
        /// Width of the ramp above the threshold.
        var softness: Float
    }

    struct Shape {
        let name: String
        /// `var` so a test can re-seed one and prove the seed is read at all — a determinism
        /// assertion against a generator that ignored its seed would be green and vacuous.
        var seed: UInt64
        var grain: Grain?
        /// Coverage at normalised `(u, v)`, given the shape's seed.
        let body: (Float, Float, UInt64) -> Float

        init(name: String, seed: UInt64, grain: Grain? = nil,
             body: @escaping (Float, Float, UInt64) -> Float) {
            self.name = name
            self.seed = seed
            self.grain = grain
            self.body = body
        }
    }

    // MARK: - Rasterizing a shape

    /// **The silhouette is supersampled and the grain is not**, which is a cost decision with a
    /// correctness argument behind it. A silhouette's edge is where a jagged sample shows, so it is
    /// evaluated `samples²` times per pixel; the grain is a continuous field whose own frequency is
    /// far below the pixel grid, so sampling it once per pixel is exact enough to be
    /// indistinguishable and is 4× cheaper across the whole mask.
    static let samples: Int = 2

    static func render(_ shape: Shape) -> Tip {
        let n: Int = side
        var alpha = [UInt8](repeating: 0, count: n * n)
        let inv: Float = 1 / Float(samples)

        for y in border..<(n - border) {
            for x in border..<(n - border) {
                var accumulated: Float = 0
                for sy in 0..<samples {
                    let py: Float = Float(y) + (Float(sy) + 0.5) * inv
                    let v: Float = (py - Float(n / 2)) / halfSpan
                    for sx in 0..<samples {
                        let px: Float = Float(x) + (Float(sx) + 0.5) * inv
                        let u: Float = (px - Float(n / 2)) / halfSpan
                        accumulated += shape.body(u, v, shape.seed)
                    }
                }
                var coverage: Float = accumulated * inv * inv
                if coverage > 0, let grain = shape.grain {
                    let u: Float = (Float(x) + 0.5 - Float(n / 2)) / halfSpan
                    let v: Float = (Float(y) + 0.5 - Float(n / 2)) / halfSpan
                    coverage *= grainValue(u, v, grain, shape.seed &+ 0x6721)
                }
                alpha[y * n + x] = UInt8(min(max(coverage, 0), 1) * 255 + 0.5)
            }
        }

        return Tip(name: shape.name,
                   fileName: "gen-\(shape.name).png",
                   alpha: alpha,
                   png: png(from: alpha))
    }

    static func grainValue(_ u: Float, _ v: Float, _ grain: Grain, _ seed: UInt64) -> Float {
        let noise: Float = fbm2(u * grain.frequency, v * grain.frequency,
                                octaves: grain.octaves, seed: seed)
        let ramp: Float = grain.softness > 1e-6
            ? min(max((noise - grain.threshold) / grain.softness, 0), 1)
            : (noise > grain.threshold ? 1 : 0)
        return grain.floor + (1 - grain.floor) * ramp
    }

    // MARK: - Bytes

    /// The alpha buffer as a straight-alpha PNG in the shape `BrushTextureStore` reads.
    ///
    /// **RGB is black everywhere, which makes premultiplied and straight the same bytes**, so the
    /// premultiplied context below writes a file whose unpremultiplied alpha is exactly the buffer
    /// — `0 / a == 0` for every `a`. That is the same trick `BrushTipImport` relies on, and it is
    /// why the round trip in `BrushTipGeneratorLogicTests` can be exact rather than approximate.
    static func png(from alpha: [UInt8]) -> Data {
        let n: Int = side
        var rgba = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) { rgba[i * 4 + 3] = alpha[i] }
        let image: CGImage? = rgba.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n,
                                      bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
        guard let image, let data = UIImage(cgImage: image).pngData() else { return Data() }
        return data
    }

    /// Writes every generated tip into the brush library and hands back what was written.
    ///
    /// **`BrushTextureStore` is dropped first**, because it caches a *negative* answer for a ref
    /// whose file was missing — the hazard `860a4a0` records for the restored-texture path, reached
    /// here by a different door: a test that stamped a `gen-…` ref before this ran would otherwise
    /// hold a nil mask for the life of the process and every dab after it would draw nothing.
    @discardableResult
    static func writeAll() -> [Tip] {
        let tips = generateAll()
        for tip in tips {
            try? BrushStorage.shared.write(tip.png, to: tip.fileName)
        }
        BrushTextureStore.removeAll()
        return tips
    }
}
