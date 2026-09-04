import Foundation
import CoreGraphics

/// **The random field one stroke's dabs are drawn from.** BRUSH.md §2.13, §2.17 and §4.
///
/// Every per-dab random value is `hash(seed, channel, arc length)`. There is no sequence and no
/// phase, which is the whole ruling: a value belongs to a *place on the stroke* rather than to a
/// position in a stream, so it survives every rebuild of the walk that used to shift it —
///
/// | | why a sequential stream shifted |
/// |---|---|
/// | a stroke is split | the surviving piece started at a different dab index |
/// | the path is refitted | dab positions and dab count changed |
/// | a brush's spacing is edited | every dab index shifted |
/// | the eraser punches, or an in-between re-derives the walk | the walk was rebuilt from different geometry |
///
/// A dab 43.2 brush widths along the stroke draws the same scatter, angle jitter and rotation
/// forever — whichever half of a split it lands in, whatever the refit did to the point count,
/// whether it is dab #200 or #150. What is *not* preserved, correctly, is which arc lengths carry a
/// dab: edit a brush's spacing and different points of the field are sampled, because those are
/// different dabs.
///
/// ## The coordinate is arc length **in brush widths**, not in points
///
/// §2.17 already states λ in brush widths, and measuring the field in the same unit buys the one
/// invariance points do not have: **a uniform scale of a stroke changes nothing at all.** A dab sits
/// at `n · spacing / brushSize` widths, and a lasso resize, a canvas resize and the layer transform
/// all scale `spacing` and `brushSize` together — MEASURED, `(k·size·fraction)/(k·size)` and
/// `(size·fraction)/size` are the *same Double* across every scale, size and fraction tried, so 60,000
/// accumulated dabs disagree by exactly zero. In points the same scale would re-roll every dab of
/// every scattering stroke the artist picks up with the lasso, and would put the Mode 2 cut preview
/// (which walks canvas space) on different dabs from the render (which walks the layer's own).
///
/// Pure `Foundation`/`CoreGraphics` — no UIKit, no `Brush` — so it is exercisable headless, the
/// bargain `StrokeStabilizer` and `StrokePathFit` both make. The one thing a caller owes it is the
/// conversion: `BrushStamper` divides its point-valued spacing by the brush width once per stroke.
struct DabRandom: Equatable {

    // MARK: - Addressing the field

    /// Which of a dab's several random values is being drawn.
    ///
    /// **A channel is what replaces "the next draw off the stream".** Scatter angle and scatter
    /// distance are two values at one arc length, and a stream distinguished them by *order*; with no
    /// stream there is no order, so the channel has to be part of the hash or the two would be the
    /// same number. BRUSH.md §6's modulation matrix adds a row per modulation on top of these, which
    /// is the reason this is an identifier folded into the hash rather than three separate seeds.
    ///
    /// Raw values are the hash's input and are therefore **stable**: renumbering one re-rolls every
    /// stroke drawn with it. Add channels, never renumber them.
    ///
    /// **A struct rather than an enum since §12 stage 7**, because the matrix mints a channel per
    /// modulation row and there is no fixed list of those — `DabRandom.Channel.modulation(_:row:)`
    /// (`BrushModulation.swift`) is the minting rule, kept there so this type stays free of `Brush`.
    /// The four named below are the intrinsic draws, and their raw values are exactly the enum's.
    /// 0–15 are reserved for them; the matrix starts at 16.
    struct Channel: Hashable {
        let rawValue: UInt64
        init(rawValue: UInt64) { self.rawValue = rawValue }

        static let scatterAngle = Channel(rawValue: 1)
        static let scatterDistance = Channel(rawValue: 2)
        /// The tip's per-dab angle jitter — `BrushAngleSettings.jitter`.
        static let rotation = Channel(rawValue: 3)
        /// **BRUSH.md §2.18's dropout draw.** The value a dab's `density` is compared against, and
        /// the one whose wavelength is carried by the density row itself.
        static let density = Channel(rawValue: 4)
    }

    /// The stroke's own seed. **Inherited on split rather than regenerated** — that is the property
    /// the brief's constraint asks for, and `VectorStroke.seed` is where it lives.
    let seed: UInt64

    /// How far along the original stroke this stroke's own walk begins, in brush widths.
    ///
    /// Zero for a stroke drawn as itself and for a piece that still replays its parent's whole walk
    /// (a `DabLattice` carrier — there the walk *is* the parent's, so it already starts at the
    /// field's origin). Non-zero exactly for a piece that has left the parent's lattice and re-anchors
    /// its own: the eraser's Modes 2 and 3, which remove geometry. Without it such a piece would hash
    /// from zero and the surviving ink would re-roll along its whole length.
    let arcOffset: CGFloat

    init(seed: UInt64, arcOffset: CGFloat = 0) {
        self.seed = seed
        self.arcOffset = arcOffset
    }

    // MARK: - The lattice

    /// The lattice arc length is hashed on, in brush widths — **1/4096 of a width**, and both bounds
    /// on the size are load-bearing.
    ///
    /// **Fine enough that two dabs can never share a bucket.** The Spacing slider's range is
    /// `0.02...0.5` of a brush width and `BrushStamper.stampSpacing`'s 1 pt floor only ever makes the
    /// gap *wider*, so the tightest spacing the app can produce is 0.02 widths — **82 quanta**, four
    /// doublings of headroom below anything an artist can dial in. It is also what gives a wavelength
    /// its resolution: λ is a lattice step measured in these quanta, so §2.17's 3–4 widths is a
    /// 12,000-step fade rather than a staircase.
    ///
    /// **Coarse enough that two routes to the same arc length land in the same bucket.** Arc length is
    /// accumulated one spacing per dab, so a dab that survives a spacing edit is reached by a
    /// *different* sum — 499,992 additions of 0.01 against 41,666 of 0.12, say. MEASURED over every
    /// such coincidence inside a 5,000-width stroke (a 20,000 pt line drawn with a 4 pt brush) across
    /// eight spacings, the worst disagreement between two routes is **6.6e-8 widths, 2.7e-4 of one
    /// quantum** — and that is the extreme; an ordinary stroke is two orders of magnitude inside it.
    /// `RasterVectorParityLogicTests` compares the two tiers at zero tolerance and a one-bucket
    /// difference is a visibly different scatter offset, so the margin matters.
    ///
    /// A negative power of two, so `arcLength / quantum` is an exact scaling and the only rounding is
    /// the one that lands on the lattice.
    static let quantum: CGFloat = 1.0 / 4096

    /// `arcLength` on the lattice, as a count of quanta.
    ///
    /// Clamped rather than trapped on a value no walk should produce: a non-finite or absurd arc
    /// length is a defect upstream of here, and answering 0 draws a wrong dab where `Int64(_:)` would
    /// take the app down.
    static func lattice(_ arcLength: CGFloat) -> Int64 {
        guard arcLength.isFinite else { return 0 }
        let scaled = (arcLength / quantum).rounded()
        guard scaled > -9.0e15 else { return Int64(-9.0e15) }
        guard scaled < 9.0e15 else { return Int64(9.0e15) }
        return Int64(scaled)
    }

    // MARK: - Drawing

    /// One random value in `0..<1` for `channel`, at `arcWidths` along this stroke's own walk.
    ///
    /// `wavelength` is BRUSH.md §2.17's λ, in brush widths, which is the unit §2.17 already states it
    /// in and the unit this whole field is addressed in — so there is no conversion here to get
    /// wrong. The value is band-limited to λ: it interpolates smoothly between hashed lattice points λ
    /// apart, so a run of consecutive dabs shares a slowly-varying value instead of each drawing its
    /// own. λ is what separates a stipple from a segmented line.
    ///
    /// **λ = 0 is not a second arm, it is `Λ = 1`.** A wavelength of zero quantises to a lattice step
    /// of one quantum, at which every dab sits in its own cell with `fraction == 0` and the
    /// interpolation returns that cell's hash exactly — a fresh draw per dab. So the two behaviours
    /// §2.17 describes separately are one code path and cannot drift apart.
    func unit(_ channel: Channel, at arcWidths: CGFloat, wavelength: CGFloat = 0) -> CGFloat {
        // Both offsets go onto the lattice before they are added, so a piece's local arc lengths
        // address exactly the cells they would have addressed at offset zero, shifted whole.
        let index = DabRandom.lattice(arcOffset) &+ DabRandom.lattice(arcWidths)
        let step = max(DabRandom.lattice(wavelength), 1)
        let (cell, fraction) = DabRandom.cell(index, step: step)
        let low = value(channel, at: cell)
        // `a + (b - a) * 0` is exactly `a` in IEEE arithmetic, so this is an early exit rather than a
        // second answer — at λ = 0 it is the only branch ever taken.
        guard fraction > 0 else { return low }
        let high = value(channel, at: cell &+ 1)
        return low + (high - low) * DabRandom.smoothstep(fraction)
    }

    /// As `unit`, in `-1..<1`. The sign is part of the same draw, not a second one.
    func signedUnit(_ channel: Channel, at arcWidths: CGFloat, wavelength: CGFloat = 0) -> CGFloat {
        unit(channel, at: arcWidths, wavelength: wavelength) * 2 - 1
    }

    /// Which λ-cell `index` falls in, and how far through it — floor division, so a negative index
    /// (a piece cut from the very start of a warped stroke) lands in the cell below rather than
    /// reflecting about zero.
    static func cell(_ index: Int64, step: Int64) -> (cell: Int64, fraction: CGFloat) {
        var cell = index / step
        var remainder = index % step
        if remainder < 0 {
            cell -= 1
            remainder += step
        }
        return (cell, CGFloat(remainder) / CGFloat(step))
    }

    /// The Hermite fade between two lattice values. Zero derivative at both ends, so the field is
    /// smooth *across* a lattice point rather than merely continuous at it — a linear fade puts a
    /// visible kink every λ.
    static func smoothstep(_ f: CGFloat) -> CGFloat { f * f * (3 - 2 * f) }

    /// One lattice point's value, uniform in `0..<1`. Takes the top 53 bits, the standard way to land
    /// a `Double` mantissa exactly without the modulo bias of `raw % n`.
    private func value(_ channel: Channel, at cell: Int64) -> CGFloat {
        CGFloat(DabRandom.raw(seed: seed, channel: channel, cell: cell) >> 11)
            * (1.0 / 9_007_199_254_740_992.0)
    }

    // MARK: - The hash

    /// splitmix64's increment — the golden ratio in 64 bits.
    private static let golden: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// splitmix64's finalizer, used here as a **hash** rather than as the tail of a state machine.
    static func avalanche(_ x: UInt64) -> UInt64 {
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The raw 64 bits for one lattice point of one channel.
    ///
    /// **This is splitmix64 addressed rather than stepped.** That generator is `state += golden;
    /// avalanche(state)`, so its n-th output from a base state is `avalanche(base + n · golden)` —
    /// exactly the expression below. The stream this replaces was splitmix64, so the statistical
    /// quality of a dab's jitter is not merely comparable to what it was, it is the same generator's
    /// same output, indexed by where the dab is instead of by how many dabs came before it.
    ///
    /// The channel is folded in through its own avalanche, which makes each channel an independently
    /// seeded stream rather than a fixed displacement along one.
    static func raw(seed: UInt64, channel: Channel, cell: Int64) -> UInt64 {
        let base = avalanche(seed &+ channel.rawValue &* golden)
        return avalanche(base &+ UInt64(bitPattern: cell) &* golden)
    }

    // MARK: - Minting a seed

    /// A seed for a stroke about to be drawn. **Minted at pen-down**, not at commit: live drawing
    /// hashes with it too, so the ink a scattering brush lays down under the pen is the ink the
    /// stored stroke replays.
    static func freshSeed() -> UInt64 { UInt64.random(in: .min ... .max) }

    /// A stable 64-bit seed derived from a UUID — FNV-1a over its bytes, so it survives save/load
    /// (a `Hasher` is per-process seeded and would not).
    ///
    /// Not how a stroke gets its seed any more: a split mints a fresh id on each piece, so an
    /// id-derived seed is precisely the defect §4 exists to fix. It stays for the things that are
    /// *not* strokes and want a stable pattern from an identity they already have — the size
    /// preview's brush, and a decoded stroke written before `VectorStroke.seed` existed.
    static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { raw in
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a 64
            for byte in raw {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            return hash
        }
    }
}
