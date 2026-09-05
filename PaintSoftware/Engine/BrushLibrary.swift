import Foundation

/// **The shipped brush set — BRUSH.md §8.6, authored at §12 stage 9.**
///
/// Sixteen brushes in four groups plus an empty fifth, replacing the five legacy presets **whole**:
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
/// **Where the tips come from.** Eleven of the sixteen stamp a `BuiltInBrushTexture` — a committed
/// PNG in `Resources/`, drawn by `BrushTipGenerator` and traceable to it by name. The other five
/// need **no artwork at all**, which is §8.4's whole finding: a soft round is a falloff, a hard
/// round a disc, a technical pen a small hard disc, an opaque round a near-hard one, and Rough Ink
/// Blotchy is §6's modulation matrix on a clean round tip.
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
    /// authored as became — and §2.18's `density` dropout under a pressure threshold. The two are not
    /// weaker versions of each other — this one makes coarse lumps and outright breaks where the
    /// tipped nib makes a fine even tooth.
    static let roughInkBlotchy = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-00000000001C")!,
        name: "Rough Ink — Blotchy", tip: .round, size: 11,
        dab: BrushDabSettings(size: 0.5, flow: 0.9, spacing: 0.045, hardness: 0.85,
                              density: 0, densityWavelength: 4.0),
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
                              density: 0, densityWavelength: 4.0,
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
    /// **Texture is empty and shipping it empty is deliberate** — §12 stage 11's CC0 sourcing fills
    /// it, and §8.3 gates that on a per-file licence check that has not happened. An empty group is
    /// honest about what is coming; a missing one is not, and `BrushGroup` exists precisely because
    /// an empty group has to be placeable (`BrushLibraryLogicTests`'
    /// `testAnEmptyGroupKeepsThePositionItWasMovedTo`).
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
        BrushGroup(id: GroupID.texture, name: "Texture", brushes: [])
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
