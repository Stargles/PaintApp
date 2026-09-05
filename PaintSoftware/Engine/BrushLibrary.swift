import Foundation

/// **The shipped brush set — BRUSH.md §8.6, authored at §12 stage 9.**
///
/// Twenty brushes in five groups, replacing the five legacy presets **whole**:
/// §2.16 is *"all the current brushes should be removed and replaced with these as current brushes
/// are a legacy feature"*, and §12 stage 9 spells out that they are *"deleted here, not
/// deprecated"*. Nothing named `softRound`, `hardRound`, `pencil`, `pen` or the old `square`
/// survives, and the ids they carried are not reused: an old project's manifest holds a whole
/// `Brush` value, so its selection still decodes and draws — it simply is not a row of this
/// library any more, which is exactly what a legacy brush should be.
///
/// **They were chosen off a contact sheet rather than designed on paper.** §12 stage 9 is driven by
/// contact sheet at the owner's instruction: `BrushTipGenerator` draws the masks,
/// `BrushCandidates` carries the settings, `BrushContactSheetBench` renders every candidate through
/// the real `BrushStamper`, and the owner picks. Three rounds of that produced these. The values
/// below are the *starting* point an artist tunes from, not a final answer — the owner's own
/// instruction was *"you choose what to ship"* and then to adjust on the device.
///
/// **The ids are written down rather than minted, and that is load-bearing.** `UUID()` in a
/// `static let` is one value per *process*, so a preset saved into a project's manifest came back
/// with an id no running copy of the app could match: the picker's `preset.id == selectedBrush.id`
/// highlight found nothing after a reload. A written-down id makes a preset's identity a fact about
/// the preset rather than about the launch that wrote it.
///
/// **Where the tips come from.** Fifteen of the twenty stamp a `BuiltInBrushTexture` — a committed
/// PNG in `Resources/`, drawn by `BrushTipGenerator` and traceable to it by name. The other five
/// need **no artwork at all**, which is §8.4's whole finding: a soft round is a falloff, a hard
/// round a disc, a technical pen a small hard disc, an opaque round a near-hard one, and Rough Ink
/// Blotchy is §6's modulation matrix on a clean round tip.
///
/// **And none of them is sourced.** §8.4 ruled the Texture group CC0-only because scanned grunge and
/// splatter were held to be genuinely hard to fake; §12 stage 11's contact sheet refuted that, so
/// the four Texture brushes are generated on the same terms as the other eleven and the shipped set
/// carries no third-party licence at all.
enum BrushLibrary {

    // MARK: - Basics
    //
    // §8.6: *"Round Soft, Opaque Round, Round Hard"* and two square nibs. Opaque Round was moved
    // here from Painting at the owner's instruction — *"I feel it better belongs here"*.

    /// A falloff, and nothing else. `hardness 0.12` is the whole of what makes it soft.
    static let roundSoft = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000011")!,
        name: "Round Soft", tip: .round, size: 22,
        dab: BrushDabSettings(size: 0.5, flow: 0.35, spacing: 0.06, hardness: 0.12),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.5, atZero: 0.2),
            .flowFromPressure(amount: 0.65)
        ])
    )

    /// Flow 1 and a near-hard edge: covers in one pass, with no pressure on the flow at all. The
    /// falloff Square is calibrated against.
    static let opaqueRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000012")!,
        name: "Opaque Round", tip: .round, size: 34,
        dab: BrushDabSettings(size: 0.85, flow: 1, spacing: 0.05, hardness: 0.8),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.15, atZero: 0.75)
        ])
    )

    /// A disc. [BUGS.md](BUGS.md) records that `hardness 0.95` is already a fully aliased edge, which
    /// against a lineart nib is at least as likely to be an ingredient as a defect — §8.4.
    static let roundHard = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000013")!,
        name: "Round Hard", tip: .round, size: 16,
        dab: BrushDabSettings(size: 0.6, flow: 0.9, spacing: 0.045, hardness: 0.95),
        stroke: BrushStrokeSettings(stabilization: 0.1),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.4, atZero: 0.4),
            .flowFromPressure(amount: 0.1)
        ])
    )

    /// **§8.6's clean slab** — *"a slab with no noisy edges, and beveled corners, and softness sort
    /// of like opaque round in that it only falls off in the very edges."*
    ///
    /// **2.5:1 rather than the 4:1 the first sheet drew**, which is round two's recommendation: a
    /// shorter, fatter nib turns visibly, and the turning stroke on the sheet is where a
    /// direction-locked nib shows what it does. The perpendicularity is `angle.base 0.25` with
    /// `directionFollow 1` and there is **no jitter at all** — a clean nib is what was asked for and
    /// jitter is what would make it dirty.
    ///
    /// No `hardness`: a stamped dab's edge is in the tip's own pixels, and naming it here would say
    /// this brush reads something it does not.
    static let square = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000014")!,
        name: "Square", tip: .stamp(.builtIn(.squareBevelWide)), size: 36,
        dab: BrushDabSettings(size: 0.75, flow: 0.9, spacing: 0.05,
                              angle: BrushAngleSettings(base: 0.25, directionFollow: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.25, atZero: 0.6),
            .flowFromPressure(amount: 0.12)
        ])
    )

    /// **§8.6's dirty slab** — *"like the flat brush, except with messier ends. Still square, but the
    /// sprite gives it a unique non monolithic look for the ends, more of a slightly dirty
    /// falloff."*
    ///
    /// **All three terms, because the contact sheet showed the picture cannot do it alone.** The
    /// sprite's torn, combed ends are direction-locked, so §8.4's union argument applies to their
    /// *boundary*: eight dabs overlap and the running maximum is a slightly wobbly straight line.
    /// The sheet rendered that row as a CONTROL and it failed as predicted. What survives is the
    /// **comb**, which is at a fixed offset from the path and therefore draws ribbons — plus §6's
    /// two mechanisms, four degrees of `angle.jitter` and a short-λ `size ← random` envelope, which
    /// tear the boundary the picture could not.
    static let messyFlat = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000015")!,
        name: "Messy Flat", tip: .stamp(.builtIn(.flatMessyEndsDirty)), size: 32,
        dab: BrushDabSettings(size: 0.8, flow: 0.85, spacing: 0.065,
                              angle: BrushAngleSettings(base: 0.25, directionFollow: 1,
                                                        jitter: 0.012)),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.22, atZero: 0.6),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.5)), amount: 0.10),
            .flowFromPressure(amount: 0.15)
        ])
    )

    // MARK: - Sketching
    //
    // All four settled off the first contact sheet. Every one carries `angle.jitter`, which is
    // §8.5's answer to the sawtooth a repeated stamp otherwise combs onto a stroke's edge — and,
    // per §8.4's boundary paragraph, what turns an uneven silhouette into roughness at all.

    /// Mid-frequency grain, hard-thresholded: a tooth rather than a smear.
    static let pencilHard = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000016")!,
        name: "Pencil Hard", tip: .stamp(.builtIn(.pencilHard)), size: 8, opacity: 0.95,
        dab: BrushDabSettings(size: 0.7, flow: 0.45, spacing: 0.05,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.12),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            .flowFromPressure(amount: 0.55)
        ])
    )

    /// The grain modulates alpha instead of punching it, which is what makes this a smear.
    static let pencilSoft = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000017")!,
        name: "Pencil Soft", tip: .stamp(.builtIn(.pencilSoft)), size: 14, opacity: 0.85,
        dab: BrushDabSettings(size: 0.6, flow: 0.3, spacing: 0.04,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.4, atZero: 0.35),
            .flowFromPressure(amount: 0.7)
        ])
    )

    /// The ground flat makes the shape uneven and the jitter turns unevenness into roughness. The
    /// owner's note on this one is what §8.4's boundary paragraph is built from: it is *"much closer
    /// to the messy edge look I wanted for the rough ink brush"*.
    static let pencilBlunt = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000018")!,
        name: "Pencil Blunt", tip: .stamp(.builtIn(.pencilBlunt)), size: 18, opacity: 0.9,
        dab: BrushDabSettings(size: 0.72, flow: 0.4, spacing: 0.055,
                              angle: BrushAngleSettings(base: 0.08, directionFollow: 0.35,
                                                        jitter: 0.25)),
        stroke: BrushStrokeSettings(stabilization: 0.18),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.28, atZero: 0.55),
            .flowFromPressure(amount: 0.6)
        ])
    )

    /// Coarse pits at a wide spacing. §8.4: *"anything whose character is in its pixels needs the
    /// dabs far enough apart to be seen one at a time"* — 0.085 against Pencil Hard's 0.05.
    static let pencilTextured = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000019")!,
        name: "Pencil Textured", tip: .stamp(.builtIn(.pencilTextured)), size: 20, opacity: 0.9,
        dab: BrushDabSettings(size: 0.7, flow: 0.5, spacing: 0.085,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.15),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.45),
            .flowFromPressure(amount: 0.5)
        ])
    )

    // MARK: - Inking

    /// Constant width, **no modulation rows at all** — a Rotring, not a nib. Also the empty cell of
    /// §8.4's asymmetry × rotation factorial: no asymmetry and no turn.
    static let technicalPenFine = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001A")!,
        name: "Technical Pen — Fine", tip: .round, size: 4,
        dab: BrushDabSettings(size: 1, flow: 1, spacing: 0.03, hardness: 1),
        stroke: BrushStrokeSettings(stabilization: 0.45)
    )

    /// A teardrop lying along the travel. The taper an artist sees is mostly `size ← pressure`; what
    /// the picture adds is that the trailing end is blunter, so a stroke that turns leaves a
    /// different edge on the inside of the curve.
    static let brushPen = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001B")!,
        name: "Brush Pen", tip: .stamp(.builtIn(.penBrush)), size: 26,
        dab: BrushDabSettings(size: 0.35, flow: 0.9, spacing: 0.035,
                              angle: BrushAngleSettings(directionFollow: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.35),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.65, atZero: 0.12),
            .flowFromPressure(amount: 0.1)
        ])
    )

    /// **§8.4's first answer to §2.16's rough ink ask, and it ships beside the tipped one on
    /// purpose.** All dynamics and no picture: two `size ← random` rows at two wavelengths, a
    /// coherent scatter — §2.30's two axes at one amount, which is what the isotropic row it was
    /// authored as became — and a `density` dropout under a pressure threshold, written as §2.32's
    /// gate: a base sitting on it, the pressure curve at half gain and a randomiser at minus a half.
    /// The two are not weaker versions of each other — this one makes coarse lumps and outright
    /// breaks where the tipped nib makes a fine even tooth.
    static let roughInkBlotchy = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001C")!,
        name: "Rough Ink — Blotchy", tip: .round, size: 11,
        dab: BrushDabSettings(size: 0.5, flow: 0.9, spacing: 0.045, hardness: 0.85,
                              density: BrushDensityGate.threshold),
        stroke: BrushStrokeSettings(stabilization: 0.3),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.16, atZero: 0.55),
            BrushModulation(.size, .random(.scatterAcross, .plain(2.5)), amount: 0.30),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.3)), amount: 0.10),
            // **§2.30's migration of one isotropic `scatter` row, and it is two rows now.** The
            // amount and the wavelength are the ones the owner picked on the contact sheet; what
            // moved is the shape of the draw, from a disc to a square, which §2.30 rules is what
            // "both set equal" means. The across row keeps the channel the old row drew from.
            BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(1.5)), amount: 0.14),
            BrushModulation(.scatterAlong, .random(.scatterAcross, .plain(1.5)), amount: 0.14),
            .densityFromPressure(knee: 0.4, floor: 0.45),
            .randomisedDensity(wavelength: 4.0),
            .flowFromPressure(amount: 0.1)
        ])
    )

    /// **§2.16's brush, and §8.6's one piece of open design, settled.** *"An ink pen which is rough,
    /// almost giving it a sort of slightly rough blotchy sketchy feel to the lineart."*
    ///
    /// **Both mechanisms at once, because the second contact sheet showed they are different
    /// roughness rather than more and less of one.** The picture is the triangular blob the owner
    /// named — grossly asymmetric, so `angle.jitter 1` presents a different outline at every dab —
    /// and the dynamics are Rough Ink Blotchy's own, unchanged. The sheet's factorial is what says
    /// each half is necessary: the same triangle with the turn taken away, and an eroded round with
    /// the turn left in, both draw clean lines.
    static let roughInk = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001D")!,
        name: "Rough Ink", tip: .stamp(.builtIn(.roughInkTriangle)), size: 11,
        dab: BrushDabSettings(size: 0.6, flow: 1, spacing: 0.045,
                              density: BrushDensityGate.threshold,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.3),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.16, atZero: 0.55),
            BrushModulation(.size, .random(.scatterAcross, .plain(2.5)), amount: 0.30),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.3)), amount: 0.10),
            // **§2.30's migration of one isotropic `scatter` row, and it is two rows now.** The
            // amount and the wavelength are the ones the owner picked on the contact sheet; what
            // moved is the shape of the draw, from a disc to a square, which §2.30 rules is what
            // "both set equal" means. The across row keeps the channel the old row drew from.
            BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(1.5)), amount: 0.14),
            BrushModulation(.scatterAlong, .random(.scatterAcross, .plain(1.5)), amount: 0.14),
            .densityFromPressure(knee: 0.4, floor: 0.45),
            .randomisedDensity(wavelength: 4.0),
            .flowFromPressure(amount: 0.1)
        ])
    )

    // MARK: - Painting

    /// **The owner's paint-stroke reference**: *"a lot more squarish than slab shaped, though the
    /// shape is alot more blotchy than square, with a clear bristle direction noticeable in them."*
    ///
    /// **Flow is 0.45, not 0.9, and the second sheet is why.** At this spacing twenty-odd dabs
    /// overlap every point, so at flow 0.9 the accumulation saturates and every streak the nib
    /// carries is filled in — the first render of that row was a solid black band. A lower flow with
    /// the stroke's opacity still at 1 keeps the tonal range and still covers.
    static let painterly = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001E")!,
        name: "Painterly", tip: .stamp(.builtIn(.paintDryLoad)), size: 36,
        dab: BrushDabSettings(size: 0.85, flow: 0.45, spacing: 0.095,
                              angle: BrushAngleSettings(directionFollow: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.2, atZero: 0.7),
            .flowFromPressure(amount: 0.25)
        ])
    )

    /// **The open bristle nib plus the envelope that keeps its outline open.** The owner's defect
    /// on round one — *"right now you can see it fit within a clear oval shape"* — was in the mask
    /// and is fixed there. But a mask with no bounding shape still has its *outer* boundary dilated
    /// by the walk, about thirty dabs deep at this spacing, so the sheet's A/B was the same picture
    /// with and without dynamics. The envelope row won it: a short-λ `size ← random` and a coherent
    /// scatter, §8.4's two MEASURED-to-work mechanisms. The scatter is two rows since §2.30 —
    /// `scatterAcross` and `scatterAlong` at the one amount the sheet was judged on.
    static let bristle = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001F")!,
        name: "Bristle", tip: .stamp(.builtIn(.bristleOpen)), size: 34, opacity: 0.95,
        dab: BrushDabSettings(size: 0.8, flow: 0.55, spacing: 0.04,
                              angle: BrushAngleSettings(directionFollow: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.25, atZero: 0.55),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.6)), amount: 0.16),
            BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(1.0)), amount: 0.07),
            BrushModulation(.scatterAlong, .random(.scatterAcross, .plain(1.0)), amount: 0.07),
            .flowFromPressure(amount: 0.45)
        ])
    )

    /// **§8.6's Streaky** — *"imagine the sprite being just a bunch of little dots, like 6 or 8 of
    /// them placed randomly. The brush makes many streaks."* Six, stratified across the nib so six
    /// distinct ribbons are guaranteed, at half the radius round two drew at the owner's
    /// instruction.
    ///
    /// **`angle.jitter` is 0 and that is the design, not an omission.** Every other rough brush here
    /// wants rotation; this is the exception §8.4's rule predicts, because what makes a ribbon a
    /// ribbon is that a dot keeps the *same* perpendicular offset from the path dab after dab. Turn
    /// the pattern and the ribbons smear back into a band.
    static let streaky = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000020")!,
        name: "Streaky", tip: .stamp(.builtIn(.streakDots6)), size: 30,
        dab: BrushDabSettings(size: 0.9, flow: 0.9, spacing: 0.04,
                              angle: BrushAngleSettings(directionFollow: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.25, atZero: 0.55),
            .flowFromPressure(amount: 0.3)
        ])
    )

    // MARK: - Texture
    //
    // **§12 stage 11, and it carries no licensing step.** §8.4 ruled *"source CC0 only for Texture,
    // where scanned grunge and splatter are genuinely hard to fake"*; §13 asked whether the
    // generator had made that true-when-written claim obsolete, and round four's contact sheet says
    // it has. All four are `BrushTipGenerator` masks and two of them are the app's own paper.
    //
    // **What separates this group from every other one is `spacing`.** Basics through Painting walk
    // at 0.03–0.095; these walk at 0.09–0.46. §8.4 already had the rule — *"anything whose character
    // is in its pixels needs the dabs far enough apart to be seen one at a time"* — and the sheet's
    // CONTROL row is the proof: Grunge's own picture at spacing 0.05 renders as a plain black band
    // with a hairy edge.

    /// **§8.6's Grunge.** A lobed, torn crust at spacing 0.30, turned isotropically, laying its ink
    /// through §2.25's Rough Tooth.
    ///
    /// **The paper is not decoration and the A/B on the sheet is why.** The nib's holes survive
    /// three overlapping dabs and no more; the sheet merges **once per stroke**, so its holes
    /// survive any spacing and any flow — §8.4's union argument does not reach a canvas-anchored
    /// texture at all. Laid at 160 points so one repeat is three stroke widths: the first render put
    /// it at 44 and the paper competed with the nib instead of staining it.
    static let grunge = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000021")!,
        name: "Grunge", tip: .stamp(.builtIn(.grungeCrust)), size: 46,
        dab: BrushDabSettings(size: 0.9, flow: 0.55, spacing: 0.30,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.2, atZero: 0.7),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.9)), amount: 0.18),
            .flowFromPressure(amount: 0.35)
        ]),
        texture: BrushTextureSettings(mask: .builtIn(.paperTooth), tileSize: 160, depth: 0.6)
    )

    /// **§8.6's Splatter.** Twenty-six drops off a cube law, stamped every 0.46 of a width with
    /// §2.32's dropout under it — a base above the gate and a randomiser swinging back across it —
    /// each stamp turned and resized.
    ///
    /// **The size draw is doing more of the work than the turn**, which is §8.4's own measurement
    /// arriving in the one family where it can be seen: a drop is nearly a disc, and rotating a disc
    /// changes nothing. The sheet's no-turn control is the weakest control on it for exactly that
    /// reason — what breaks the repetition here is `size ← random`, not `angle.jitter`.
    ///
    /// **Its honest limit is that every drop lands within one dab of the path.** Nothing in the
    /// engine offsets a dab across the stroke, so the spread is the mask's own; §2.30's
    /// `scatterAcross` is the lever this brush wants and does not have yet.
    static let splatter = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000022")!,
        name: "Splatter", tip: .stamp(.builtIn(.splatterDrops)), size: 48,
        dab: BrushDabSettings(size: 0.95, flow: 0.95, spacing: 0.46,
                              density: BrushDensityGate.threshold + 0.7 * BrushDensityGate.halfAmount,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.25, atZero: 0.55),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.4)), amount: 0.35),
            .randomisedDensity(wavelength: 1.0),
            .flowFromPressure(amount: 0.15)
        ])
    )

    /// **§8.6's Stipple.** Seventeen hard-edged dots a stamp, at spacing 0.34 with a short-λ dropout.
    ///
    /// **The picture is what makes it a stipple, and the sheet's dynamics-only row is the
    /// refutation.** A `density` dropout on a small round tip at spacing 0.7 is a *beaded line* — the
    /// dots all sit on the path, because nothing spreads them across it. The tip is where the spread
    /// comes from. λ is 0.4 rather than §2.17's shipped 3.5 for §2.18's own surviving reason: a long λ drops
    /// contiguous runs, which is a segmented line rather than a stipple.
    static let stipple = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000023")!,
        name: "Stipple", tip: .stamp(.builtIn(.stippleSpecks)), size: 30,
        dab: BrushDabSettings(size: 0.9, flow: 0.95, spacing: 0.34,
                              density: BrushDensityGate.threshold + 0.85 * BrushDensityGate.halfAmount,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            BrushModulation(.size, .random(.scatterAcross, .plain(0.3)), amount: 0.25),
            .randomisedDensity(wavelength: 0.4)
        ])
    )

    /// **§8.6's Chalk, and it is the clearest result on round four's sheet.** Three rows differing
    /// in exactly one field — no texture, `paperGrain`, `paperTooth` — and only the third reads as
    /// chalk. The nib alone draws a dark stroke with a grainy edge, because at spacing 0.09 twenty
    /// dabs overlap and the holes union away exactly as §8.4 predicts.
    ///
    /// **80 points is the tile and it is a scale decision, not a taste one.** `tileSize` is in canvas
    /// points, so the sheet's coarsest feature is `32/256 · tileSize` ≈ 10 points against a 30 point
    /// nib — three grains across the stroke. A fourth row at 150 is on the sheet showing what the
    /// other side of that looks like: blotches the size of the brush.
    static let chalk = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000024")!,
        name: "Chalk", tip: .stamp(.builtIn(.chalkBlock)), size: 30, opacity: 0.95,
        dab: BrushDabSettings(size: 0.85, flow: 0.5, spacing: 0.09,
                              angle: BrushAngleSettings(jitter: 1)),
        stroke: BrushStrokeSettings(stabilization: 0.18),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            .flowFromPressure(amount: 0.5)
        ]),
        texture: BrushTextureSettings(mask: .builtIn(.paperTooth), tileSize: 80, depth: 0.9)
    )

    // MARK: - The groups

    /// **The group ids are written down for the reason the preset ids are** — they are persisted the
    /// moment the library is first saved, so a minted one would make the seeded groups' identity
    /// depend on which launch happened to write the file.
    enum GroupID {
        static let basics = UUID(uuidString: "B7051000-0000-4000-B000-000000000001")!
        static let sketching = UUID(uuidString: "B7051000-0000-4000-B000-000000000002")!
        static let inking = UUID(uuidString: "B7051000-0000-4000-B000-000000000003")!
        static let painting = UUID(uuidString: "B7051000-0000-4000-B000-000000000004")!
        static let texture = UUID(uuidString: "B7051000-0000-4000-B000-000000000005")!
    }

    /// **§8.6's five groups, in the owner's own order.**
    ///
    /// **Texture is full now, and it cost no licence.** It shipped empty at §12 stage 9 because §8.3
    /// gates CC0 sourcing on a per-file check nobody had done; §13 asked whether the generator could
    /// make it unnecessary, and round four's contact sheet says it can. Nothing in this library
    /// carries a third-party asset.
    ///
    /// Erasers are not a group: the eraser **is** a brush (§11), so every one of these erases
    /// already.
    static let groups: [BrushGroup] = [
        BrushGroup(id: GroupID.basics, name: "Basics",
                   brushes: [roundSoft, opaqueRound, roundHard, square, messyFlat]),
        BrushGroup(id: GroupID.sketching, name: "Sketching",
                   brushes: [pencilHard, pencilSoft, pencilBlunt, pencilTextured]),
        BrushGroup(id: GroupID.inking, name: "Inking",
                   brushes: [technicalPenFine, brushPen, roughInkBlotchy, roughInk]),
        BrushGroup(id: GroupID.painting, name: "Painting",
                   brushes: [painterly, bristle, streaky]),
        BrushGroup(id: GroupID.texture, name: "Texture",
                   brushes: [grunge, splatter, stipple, chalk])
    ]

    /// Every shipped brush, in menu order. Derived from `groups` rather than written twice — a
    /// second list is how a brush ends up pickable and ungrouped, or grouped and unpickable.
    static let defaults: [Brush] = groups.flatMap(\.brushes)

    /// **Whether picking this brush should put the artist on the pencil rather than the pen.**
    ///
    /// `CanvasManager.selectBrush` asked `brush.shape == .pencil`, and that question no longer
    /// exists: a pencil and a pen both stamp a tip and differ in their grain, spacing and dynamics.
    /// So the affinity is to the *library*, which is a fact the library owns and the brush value
    /// does not — a field would be the pair `BrushTip` removed, wearing a tool's name.
    ///
    /// **It is the Sketching group that answers it now**, which is what `BrushLibrary`'s previous
    /// note said stage 9 would do: five hand-checked ids become one membership test, and a brush the
    /// artist adds to Sketching gets the pencil tool with nothing to update here.
    static func isPencilPreset(_ brush: Brush) -> Bool {
        groups.first { $0.id == GroupID.sketching }?
            .brushes.contains { $0.id == brush.id } ?? false
    }
}
