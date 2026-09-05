import XCTest
import CoreGraphics
import UIKit

/// **BRUSH.md §12 stage 10's model half** — the catalog, the chain, and the response curve's
/// arithmetic.
///
/// Everything a `View` cannot be asked about lives in `BrushEditorModel.swift` precisely so it can be
/// asked here; `BrushEditorUITests` is the other half and asks whether an artist can reach any of it.
final class BrushEditorLogicTests: XCTestCase {

    // MARK: - The index

    /// **Every output reaches a control.** §7's *"parameters with no UI at all today — `scatter`, the
    /// angle's three contributions, `hardness`, `density` and its λ, `blendMode` and the three HSB
    /// shifts — get one here"*, stated as a fact about `BrushOutput.allCases` rather than as a list
    /// somebody keeps in step.
    ///
    /// This is what catches a `BrushOutput` case added later with a renderer and no control — the
    /// half-built state CLAUDE.md's "a feature is not finished because its model is correct" section
    /// is about. It goes red if `roundness` lands (§12 stage 9) and nobody gives it a row.
    func testEveryBrushOutputHasAnEditorEntry() {
        for output in BrushOutput.allCases {
            XCTAssertTrue(BrushEditorCatalog.coveredOutputs.contains(output),
                          "\(output.rawValue) has a renderer and no control")
        }
        XCTAssertEqual(BrushEditorCatalog.coveredOutputs.count, BrushOutput.allCases.count)

        // The two stroke settings, which are not outputs and could not be — §6's grouping.
        XCTAssertTrue(BrushEditorCatalog.entries.contains { $0.control == .stabilization })
        XCTAssertTrue(BrushEditorCatalog.entries.contains { $0.control == .blendMode })

        let ids = BrushEditorCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "An entry's id is an accessibility identifier; two the same is one unreachable control")
    }

    /// **Each output's base keypath reaches the number the stamper resolves.**
    ///
    /// The operand that matters: not that the field changed, but that `Brush.dabValues` — what
    /// `BrushStamper.stampDab` turns into a stamp — answers differently. CLAUDE.md's
    /// `Layer.layerEffect` case is a field the render path does not read; this is the assertion that
    /// catches its counterpart here.
    func testEachBaseKeyPathMovesTheValueTheStamperResolves() {
        for output in BrushOutput.allCases {
            var brush = BrushLibrary.hardRound
            brush.modulations = BrushModulations()          // base only, so the row cannot mask it
            let before = brush.dabValues { _ in 1 }
            brush[keyPath: output.baseKeyPath] = brush[keyPath: output.baseKeyPath] + 0.25
            let after = brush.dabValues { _ in 1 }
            XCTAssertNotEqual(before, after,
                              "\(output.rawValue)'s base slider writes a field the resolver does not read")
        }
    }

    // MARK: - The curve, and TODO (38)'s defect

    /// **The y axis is a constant, and that is the whole of §7's first point.**
    ///
    /// `TimelineGraphBand.Channel.axis` auto-ranges to a channel's live key values, which is TODO
    /// (38)'s device defect: with two keys both are extremes, so the axis rescales by exactly what
    /// the drag changed and the dot lands back under the finger. This asserts the two halves that
    /// together tell a fixed axis from a fitted one — the dragged key moves, and the *other* key does
    /// not.
    func testDraggingAKeyMovesItAndLeavesTheOtherKeyWhereItWas() {
        let curve = ResponseCurve.ramp(from: 0.2, to: 1).curve
        let side = ResponseCurveEditing.side

        let lowBefore = ResponseCurveEditing.point(ofKey: curve.key(atFrame: 0)!)
        let highBefore = ResponseCurveEditing.point(ofKey: curve.key(atFrame: Int(ResponseCurve.scale))!)

        // Drag the top key down to about 0.5 — the middle of the fixed axis.
        let target = CGPoint(x: highBefore.x, y: ResponseCurveEditing.y(ofValue: 0.5))
        let moved = ResponseCurveEditing.moving(frame: Int(ResponseCurve.scale), to: target, in: curve)

        let draggedAfter = ResponseCurveEditing.point(ofKey: moved.key(atFrame: Int(ResponseCurve.scale))!)
        XCTAssertEqual(draggedAfter.y, target.y, accuracy: 0.01, "The dragged key must land under the finger")
        XCTAssertGreaterThan(draggedAfter.y, highBefore.y + 10,
                             "…and visibly further down the graph than it started")

        let otherAfter = ResponseCurveEditing.point(ofKey: moved.key(atFrame: 0)!)
        XCTAssertEqual(otherAfter.y, lowBefore.y, accuracy: 0.0001,
                       "A fitted axis would have moved this key too — that is the defect the fixed axis exists to prevent")
        XCTAssertEqual(side, ResponseCurveEditing.side)
    }

    /// The axis is a value rather than a function of the curve, which is the same fact stated
    /// without a drag: there is no overload of `y(ofValue:)` a curve could be handed to.
    func testTheAxisIsAConstantAndUpIsMore() {
        XCTAssertEqual(ResponseCurveEditing.axis, 0...1)
        XCTAssertGreaterThan(ResponseCurveEditing.y(ofValue: 0), ResponseCurveEditing.y(ofValue: 1),
                             "Up is more — every graph editor's convention and the opposite of the view's own y")
        // A reading of 0 and a reading of 1 land at the two ends of the square, inset by the shared
        // margin `TimelineGraphBand.verticalInset` — so the graph fills its own box whatever is on it.
        XCTAssertEqual(ResponseCurveEditing.y(ofValue: 1), TimelineGraphBand.verticalInset, accuracy: 0.001)
        XCTAssertEqual(ResponseCurveEditing.y(ofValue: 0),
                       ResponseCurveEditing.side - TimelineGraphBand.verticalInset, accuracy: 0.001)
    }

    /// **A key is stopped by its neighbour rather than allowed to eat it.** `AnimationCurve.setKey`
    /// replaces on collision, so a drag that could travel onto another key's frame would silently
    /// destroy it — a destructive edit made by a continuous gesture.
    func testAKeyCannotBeDraggedOntoItsNeighbour() {
        var curve = ResponseCurve.ramp(from: 0, to: 1).curve
        curve.setKey(AnimationCurve.Key(frame: 512, value: 0.5))
        XCTAssertEqual(curve.keys.count, 3)

        // Drag the middle key hard to the right, well past the last one.
        let moved = ResponseCurveEditing.moving(frame: 512,
                                                to: CGPoint(x: ResponseCurveEditing.side * 4, y: 10),
                                                in: curve)
        XCTAssertEqual(moved.keys.count, 3, "No key may be consumed by a drag")
        XCTAssertEqual(moved.keys.map(\.frame).sorted(), [0, Int(ResponseCurve.scale) - 1, Int(ResponseCurve.scale)])
    }

    /// **An empty curve materialises into the identity, bit-exactly.**
    ///
    /// `ResponseCurve`'s identity is the *empty* curve; `AnimationCurve` with one key is a constant.
    /// So the editor turns empty into a ramp before the first key is added, and that swap must move
    /// no value at all or every brush whose row is un-curved would change the moment its curve was
    /// opened.
    func testMaterialisingAnEmptyCurveChangesNothing() {
        let materialised = ResponseCurve(ResponseCurveEditing.materialised(AnimationCurve()))
        XCTAssertFalse(materialised.isLinear, "PREMISE: it is now keys rather than the empty guard")
        for step in 0...200 {
            let x = CGFloat(step) / 200
            XCTAssertEqual(materialised.value(at: x), ResponseCurve.linear.value(at: x), accuracy: 0,
                           "Materialising must be free, to the bit")
        }
    }

    /// A curve taken back down to one key is **emptied**, not left holding a constant.
    func testRemovingDownToOneKeyEmptiesTheCurve() {
        var curve = ResponseCurve.ramp(from: 0.2, to: 1).curve
        curve.setKey(AnimationCurve.Key(frame: 512, value: 0.9))

        let three = ResponseCurveEditing.removing(frame: 512, from: curve)
        XCTAssertEqual(three.keys.count, 2, "Removing one of three leaves two")

        let two = ResponseCurveEditing.removing(frame: 0, from: three)
        XCTAssertTrue(two.isEmpty, "One key is a constant, which is not a state this control may leave a row in")
        XCTAssertEqual(ResponseCurve(two).value(at: 0.37), 0.37, accuracy: 0,
                       "…and an emptied curve is the identity again")
    }

    /// A tap adds a key where the finger is, and a tap on top of one adds nothing.
    func testAddingAKeyLandsItUnderTheTouchAndRefusesADuplicate() {
        let empty = AnimationCurve()
        let at = CGPoint(x: ResponseCurveEditing.side * 0.5, y: ResponseCurveEditing.y(ofValue: 0.75))
        let added = ResponseCurveEditing.adding(at: at, to: empty)
        XCTAssertEqual(added.keys.count, 3, "The materialised ramp's two keys, plus the new one")
        let landed = added.keys.first { $0.frame != 0 && $0.frame != Int(ResponseCurve.scale) }
        XCTAssertEqual(landed?.value ?? -1, 0.75, accuracy: 0.02)

        let again = ResponseCurveEditing.adding(at: at, to: added)
        XCTAssertEqual(again.keys.count, added.keys.count, "A second tap on the same spot adds nothing")
    }

    // MARK: - Rows

    /// **Adding and removing a row re-mints the `.random` channels underneath it** — §6.2's invariant,
    /// through the accessors §7 asked for.
    ///
    /// The discriminating operand is the *second* random row's channel: its cell is a function of its
    /// index within its output, so removing the row in front of it has to change it. An accessor that
    /// spliced the array without re-normalising would leave two rows sharing one cell, which draws
    /// the same number twice and is invisible in every other assertion.
    func testAddingAndRemovingRowsRemintsTheRandomChannels() {
        var modulations = BrushModulations([
            BrushModulation(.scatter, .random(.modulation(.scatter, row: 0), .plain(2)), amount: 0.3),
            BrushModulation(.scatter, .random(.modulation(.scatter, row: 1), .plain(5)), amount: 0.2)
        ])
        let secondChannel = channel(of: modulations.rows[1].input)

        modulations.remove(at: 0)
        XCTAssertEqual(modulations.rows.count, 1)
        XCTAssertNotEqual(channel(of: modulations.rows[0].input), secondChannel,
                          "The surviving row moved to position 0, so its cell must move with it")
        XCTAssertEqual(channel(of: modulations.rows[0].input),
                       channel(of: BrushInput.random(.modulation(.scatter, row: 0), .plain(5))))
        XCTAssertEqual(modulations.rows[0].input.randomiser?.wavelength, 5,
                       "…and its authored λ is untouched")

        modulations.append(BrushModulation(.scatter, .random(.modulation(.size, row: 9), .plain(1)), amount: 0.1))
        XCTAssertNotEqual(channel(of: modulations.rows[0].input), channel(of: modulations.rows[1].input),
                          "No two rows of one output may share a cell")
    }

    /// `indices(for:)` answers positions in the whole table, not positions within the output — which
    /// is what the editor edits by, and what `firstIndex(of:)` on a value would get wrong for two
    /// equal rows.
    func testIndicesForOutputAreTablePositions() {
        let modulations = BrushModulations([
            BrushModulation(.flow, .pressure, amount: 0.5),
            BrushModulation(.size, .pressure, amount: 0.5),
            BrushModulation(.flow, .velocity, amount: 0.2)
        ])
        XCTAssertEqual(modulations.indices(for: .flow), [0, 2])
        XCTAssertEqual(modulations.indices(for: .size), [1])
        XCTAssertEqual(modulations.indices(for: .hue), [])
    }

    // MARK: - The chain the editor edits

    /// **The chain is the storage, not a view over it.** §2.28 made a modulation an input and an
    /// ordered list of modules, so there is no mapping layer left to round-trip through — the editor
    /// reads `BrushModulation.modules` and writes it back. What is worth asserting instead is that the
    /// *vocabulary* the menu offers lands on the storage exactly: three kinds, two cases, and a
    /// `.scale` carrying a `.random` reads back as the randomiser.
    func testEveryModuleKindTheMenuOffersReadsBackAsItself() {
        for kind in BrushModuleKind.allCases {
            XCTAssertEqual(kind.module.kind, kind,
                           "\(kind.displayName) must read back as the kind that made it")
            XCTAssertFalse(kind.detail.isEmpty, "every module says what it does")
        }
        XCTAssertEqual(BrushModule.scale(.random(.scatterAngle, .plain(2))).kind, .randomiser,
                       "a scale carrying a random *is* the randomiser — there is no third case")
        XCTAssertEqual(BrushModule.scale(.pressure).kind, .scale)
        XCTAssertNil(BrushModule.scale(.pressure).randomiser)
        // §2.29: a module that reads a sensor carries its own curve, and a fresh one is the
        // pass-through — so adding a scale multiplies by the raw reading until the artist draws on it.
        for kind in [BrushModuleKind.scale, .randomiser] {
            XCTAssertEqual(kind.module.sensorCurve, ResponseCurve.linear,
                           "a fresh \(kind.displayName) reads its sensor straight through")
        }
        XCTAssertNil(BrushModuleKind.curveRamp.module.sensorCurve,
                     "a curve ramp *is* its curve — it does not also carry a sensor's")
        XCTAssertEqual(BrushModule.scale(.random(.scatterAngle, .plain(2))).randomiser?.wavelength, 2)
        XCTAssertNil(BrushModule.curveRamp(.linear).randomiser)
    }

    /// **A fresh randomiser is one octave**, so adding one changes the amplitude and nothing else
    /// until the artist asks for scales — and the octave slider's range is the clamp the type
    /// enforces, not a wider one the model would silently trim.
    func testAFreshRandomiserIsOneOctaveAndTheCountIsClamped() {
        XCTAssertEqual(BrushEditorDefaults.randomiser.octaves, 1)
        XCTAssertEqual(BrushEditorDefaults.randomiser.falloff, BrushRandomiser.defaultFalloff)
        XCTAssertEqual(BrushRandomiser(wavelength: 1, octaves: 0).octaves, 1,
                       "zero octaves is not a field at all")
        XCTAssertEqual(BrushRandomiser(wavelength: 1, octaves: 99).octaves,
                       BrushRandomiser.maximumOctaves)
        XCTAssertEqual(BrushRandomiser(wavelength: 1, octaves: 2, falloff: 4).falloff, 1,
                       "a falloff above 1 would make the finest octave the loudest")
        XCTAssertEqual(BrushRandomiser(wavelength: -3, octaves: 1).wavelength, 0,
                       "a negative λ is a fresh draw per dab, not a reflection")
    }

    /// **Moving a randomiser along a chain moves the plane it draws from** — §6.2's derivation,
    /// through the reorder the editor performs.
    ///
    /// The discriminating operand is the *other* module's channel: reordering has to re-mint both, or
    /// two randomisers end up sharing one cell and draw the same number twice, which is invisible in
    /// every other assertion.
    func testReorderingAChainRemintsTheRandomiserChannels() {
        let wobbleA = BrushModule.scale(.random(.scatterAngle, .plain(2)))
        let wobbleB = BrushModule.scale(.random(.scatterAngle, .plain(5)))
        let forward = BrushModulations([
            BrushModulation(.spacing, .pressure, modules: [wobbleA, wobbleB], amount: 0.4)
        ])
        let reversed = BrushModulations([
            BrushModulation(.spacing, .pressure, modules: [wobbleB, wobbleA], amount: 0.4)
        ])
        // The λ travels with the module; the channel travels with the position.
        XCTAssertEqual(forward.rows[0].modules[0].randomiser?.wavelength, 2)
        XCTAssertEqual(reversed.rows[0].modules[0].randomiser?.wavelength, 5)
        XCTAssertEqual(moduleChannel(forward.rows[0], 0), moduleChannel(reversed.rows[0], 0),
                       "position 0 is plane 1 whichever randomiser sits in it")
        XCTAssertNotEqual(moduleChannel(forward.rows[0], 0), moduleChannel(forward.rows[0], 1),
                          "two randomisers in one chain never share a cell")
        XCTAssertEqual(moduleChannel(forward.rows[0], 1),
                       DabRandom.Channel.modulation(.spacing, row: 0, slot: 2).rawValue)
    }

    /// **The limits the screen prints are the limits the engine has.** §2.28 closed three of the four
    /// `BrushChainLimit` carried, and a sentence that is no longer true — still printed beside the
    /// control that disproves it — is worse than never having said it. So the count is pinned.
    func testTheOnlyChainLimitLeftIsTheOneSeveralChainsShare() {
        XCTAssertEqual(BrushChainLimit.allCases, [.severalChainsPerOutputAreSummed],
                       "§2.28 made the order the artist's, and a chain may carry as many curve ramps "
                       + "and randomisers as it likes — those three sentences are deleted, not reworded")
        for limit in BrushChainLimit.allCases {
            XCTAssertFalse(limit.explanation.isEmpty)
        }
    }

    /// The default a fresh row lands at is **not** zero. A row added at amount 0 does nothing, which
    /// reads as a control that did not work — CLAUDE.md's "a refusal with no notice", through a
    /// default.
    func testAFreshRowIsAudible() {
        var brush = BrushLibrary.hardRound
        let before = brush.dabValues { _ in 0.5 }
        brush.modulations.append(BrushModulation(.scatter, .pressure, amount: BrushEditorDefaults.amount))
        XCTAssertNotEqual(before, brush.dabValues { _ in 0.5 })
    }

    /// **A fresh module arrives in a state the artist can use**, and the three kinds mean different
    /// things by that — which is why this is three assertions rather than one loop with one rule.
    ///
    /// - A **randomiser** and a **scale** must change the value the moment they are added. One that
    ///   arrived at λ = 0, or reading a neutral 1, would be a control that did nothing — CLAUDE.md's
    ///   "a refusal with no notice", reached through a default.
    /// - A **curve ramp** must *not*. `ResponseCurve.ramp(from: 0, to: 1)` is documented and tested
    ///   bit-exact with the pass-through it replaces, and that is the point: adding the module puts
    ///   two draggable nodes on the graph without moving any ink until the artist drags one. The
    ///   failure it must not have is arriving **empty**, which is `AnimationCurve`'s own identity and
    ///   draws no nodes at all — a control whose first tap would flatten the row to a constant, which
    ///   is exactly what `ResponseCurveEditing.materialised` exists to prevent one surface over.
    func testEveryFreshModuleArrivesUsable() {
        var brush = BrushLibrary.hardRound
        brush.dab.size = 0.5
        brush.modulations = BrushModulations([BrushModulation(.size, .pressure, amount: 0.5)])
        let reading: (BrushInput) -> CGFloat = { input in
            if case .random = input { return 0.25 }
            return input == .pressure ? 0.5 : input.neutral
        }
        let before = brush.dabValues(reading)
        func withModule(_ kind: BrushModuleKind) -> Brush {
            var copy = brush
            var row = copy.modulations.rows[0]
            row.modules = [kind.module]
            copy.modulations.replace(at: 0, with: row)
            return copy
        }
        for kind in [BrushModuleKind.randomiser, .scale] {
            XCTAssertNotEqual(withModule(kind).dabValues(reading), before,
                              "a fresh \(kind.displayName) must change the value it is added to")
        }
        XCTAssertEqual(withModule(.curveRamp).dabValues(reading), before,
                       "a fresh curve ramp is the pass-through, to the bit — it hands the artist two "
                       + "nodes to drag rather than moving the ink on arrival")
        guard case .curveRamp(let fresh) = BrushModuleKind.curveRamp.module else {
            return XCTFail("the curve ramp kind must make a curve ramp")
        }
        XCTAssertEqual(fresh.curve.keys.count, 2,
                       "…and it must not arrive empty, or there is nothing on the graph to drag")
        XCTAssertFalse(fresh.isLinear, "an empty curve is the one state the control cannot edit")
    }

    // MARK: -

    private func channel(of input: BrushInput) -> UInt64 {
        guard case .random(let channel, _) = input else { return .max }
        return channel.rawValue
    }

    private func moduleChannel(_ row: BrushModulation, _ position: Int) -> UInt64 {
        guard case .scale(.random(let channel, _), _) = row.modules[position] else { return .max }
        return channel.rawValue
    }

    // MARK: - BRUSH.md §2.26 — the two collections

    /// **The two collections are disjoint, and neither of them contains the library file.**
    ///
    /// §2.26 rules *"two browsable collections, one storage mechanism"*, and one storage mechanism
    /// means `BrushStorage.fileNames()` answers **everything under the root** — the tips, the
    /// textures, and `library.json`. The discriminating operand is that last one: a picker built on
    /// an unfiltered listing looks perfectly right on a device that has imported nothing and offers
    /// the artist their own library file as a sprite the moment they save one.
    ///
    /// **And the tip prefix is pinned at `custom-`.** Renaming it to something tidier would orphan
    /// every tip already on an artist's device and every project package that names one; §2.14 makes
    /// documents expendable and says nothing about the artist's own brushes.
    func testTheTipAndTextureCollectionsAreDisjointAndExcludeTheLibraryFile() throws {
        let root = try makeScratchRoot("collections")
        let storage = BrushStorage(root: root)
        for name in ["custom-a.png", "custom-b.png", "texture-p.png", "library.json", "notes.txt"] {
            try storage.write(Data([0]), to: name)
        }

        let tips = BrushAssetLibrary.items(in: .tip, storage: storage)
        let textures = BrushAssetLibrary.items(in: .texture, storage: storage)

        XCTAssertEqual(tips.filter { $0.ref.importedFileName != nil }.map(\.id),
                       ["custom-a.png", "custom-b.png"],
                       "The tip collection is the `custom-` files, sorted, and nothing else")
        XCTAssertEqual(textures.filter { $0.ref.importedFileName != nil }.map(\.id),
                       ["texture-p.png"])
        for item in tips + textures {
            XCTAssertNotEqual(item.id, "library.json", "The artist's library file is not a sprite")
            XCTAssertNotEqual(item.id, "notes.txt", "…and neither is anything else under the root")
        }

        // The shipped halves, which are what makes each collection non-empty on a device that has
        // imported nothing — and the reason a paper must not be offered as a tip is that a dab would
        // stamp a dab-shaped patch of grain.
        XCTAssertEqual(builtIns(of: tips), [.square])
        XCTAssertEqual(Set(builtIns(of: textures)), Set([.paperGrain, .canvasWeave]))

        XCTAssertTrue(BrushAssetKind.tip.newFileName().hasPrefix("custom-"),
                      "A tip's name is `custom-`, unchanged — see BrushAssetKind for what a rename costs")
        XCTAssertTrue(BrushAssetKind.texture.newFileName().hasPrefix("texture-"))
    }

    /// **Every shipped paper is generated, deterministic, and tiles with no seam.**
    ///
    /// `BrushTextureMerge` lays one draw per repeat, so a field that does not wrap draws a visible
    /// grid across every stroke — and *"the sheet looks like paper"* is true of a non-wrapping field
    /// too, which is why the assertion is on the seam rather than on the picture.
    ///
    /// **The operand is the step across the wrap against the *largest* step between two interior
    /// columns, and the mean was tried first and is wrong.** A woven sheet has a real discontinuity
    /// at every thread boundary, so its wrap — which is one of those boundaries — is a jump beside
    /// the *average* column step and is not a seam at all. Measured against the largest interior
    /// boundary the claim is the honest one for both sheets: *the wrap is no worse than an ordinary
    /// edge of this field*. For the smooth one that is a tight bound, because it has no ordinary
    /// edges; for the woven one it is what says the pitch still divides the side.
    ///
    /// Determinism is the other half and it is not decorative: a sheet that differed between launches
    /// would be paper that moved under ink already drawn, which is the whole thing §2.25 anchors to
    /// the canvas to avoid.
    func testEveryShippedPaperIsDeterministicAndTilesWithoutASeam() throws {
        for paper in BuiltInBrushTexture.all(in: .texture) {
            let first = try XCTUnwrap(BrushPaperGenerator.mask(paper), "\(paper.rawValue) generates nothing")
            let second = try XCTUnwrap(BrushPaperGenerator.mask(paper))
            XCTAssertEqual(first.width, BrushTipImport.maskSide)
            XCTAssertEqual(first.height, BrushTipImport.maskSide)
            let a = try alphaGrid(of: first), b = try alphaGrid(of: second)
            XCTAssertEqual(a, b, "\(paper.rawValue) must generate the same bytes every time")

            let side = first.width
            func meanStep(from left: Int, to right: Int) -> Double {
                let total = (0..<side).reduce(0) { sum, y in
                    sum + abs(Int(a[y * side + left]) - Int(a[y * side + right]))
                }
                return Double(total) / Double(side)
            }
            let seam = meanStep(from: side - 1, to: 0)
            let worstInterior = (0..<(side - 1)).map { meanStep(from: $0, to: $0 + 1) }.max() ?? 0
            XCTAssertLessThanOrEqual(seam, worstInterior * 1.15 + 1,
                                     "\(paper.rawValue) does not wrap: the step across the tile "
                                     + "boundary (\(seam)) is a jump beyond anything inside the "
                                     + "sheet (\(worstInterior)), which is a grid of seams on every stroke")
        }

        XCTAssertNil(BrushPaperGenerator.mask(.square),
                     "A tip is not paper — the generator refuses rather than inventing a sheet")
    }

    /// **A paper never reaches zero alpha, so `depth` stays the only strength control.**
    ///
    /// `BrushTextureSettings.depth` scales the *shortfall* — `1 - depth·(1 - a)` — so an authored
    /// zero is ink deleted outright at full depth with nothing for the artist to dial back with. The
    /// floor is what keeps the one slider meaningful over its whole range.
    func testAShippedPaperNeverReachesZeroSoDepthIsTheOnlyStrengthControl() throws {
        for paper in BuiltInBrushTexture.all(in: .texture) {
            let grid = try alphaGrid(of: XCTUnwrap(BrushPaperGenerator.mask(paper)))
            let lowest = try XCTUnwrap(grid.min())
            XCTAssertGreaterThanOrEqual(Int(lowest), 60,
                                        "\(paper.rawValue) takes ink to nothing somewhere, which depth cannot undo")
            XCTAssertLessThan(Int(lowest), 250, "PREMISE: \(paper.rawValue) has some texture in it at all")
        }
    }

    /// **A texture import fills the square where a tip import letterboxes it, and that is the whole
    /// reason there are two normalisations.**
    ///
    /// The obvious implementation reuses `BrushTipImport` for both. It is wrong in a way that is
    /// invisible in the picker and obvious on the canvas: a tip is letterboxed inside a 2 px
    /// transparent border, a texture is **tiled**, and `BrushTextureMerge` multiplies with
    /// `.destinationIn` — so those transparent margins are not margins, they are a grid of lines cut
    /// out of every stroke.
    ///
    /// Both operands are needed. *"The texture fills the square"* alone is satisfied by an
    /// implementation that stretched it; the tip's clear corner beside it is what says the two really
    /// are different rules rather than one rule with a different name.
    func testATextureImportFillsTheSquareWhereATipImportLeavesAClearBorder() throws {
        let wide = solidImage(width: 64, height: 16)

        let tip = try alphaGrid(of: BrushTipImport.mask(from: wide))
        let texture = try alphaGrid(of: BrushTextureImport.mask(from: wide))
        let side = BrushTipImport.maskSide

        XCTAssertEqual(Int(tip[0]), 0, "A tip is letterboxed and bordered — its corner is clear")
        XCTAssertEqual(Int(tip[side * side - 1]), 0)
        XCTAssertGreaterThan(Int(tip[(side / 2) * side + side / 2]), 200,
                             "PREMISE: the tip's own middle is inked")

        for corner in [0, side - 1, side * (side - 1), side * side - 1] {
            XCTAssertGreaterThan(Int(texture[corner]), 200,
                                 "A tiled sheet reaches its own edge — a clear corner is a seam in every stroke")
        }
        XCTAssertEqual(texture.filter { $0 < 200 }.count, 0,
                       "An opaque picture aspect-fills the sheet with no margin at all")
    }

    // MARK: - BRUSH.md §7.1 — what "create manually" makes

    /// **A manually made brush is the engine's neutral, not a copy of a preset**, it lands in the
    /// open group, and a second one does not take the first one's name.
    ///
    /// The discriminating operand is `modulations`. Every shipped preset carries `size ← pressure`
    /// and `flow ← pressure` (§12 stage 7), so an implementation that duplicated whatever brush was
    /// selected would satisfy "a new brush appeared, in the right group, with a fresh name" and would
    /// hand the artist two rows they did not add — which is the opposite of the owner's *"you being
    /// able to fully customize it"*.
    ///
    /// The name matters for a reason beyond tidiness: a brush row's accessibility identifier **is**
    /// its name, so two brushes called the same thing are two elements answering one query.
    func testCreateManuallyMintsTheNeutralBrushIntoTheOpenGroupWithAUniqueName() throws {
        let root = try makeScratchRoot("create-manually")
        let store = BrushLibraryStore(storage: BrushStorage(root: root), arguments: [])
        let target = store.addGroup(name: "Mine")

        let made = store.createBrush(inGroup: target.id)

        XCTAssertEqual(store.group(containingBrush: made.id)?.id, target.id,
                       "It lands in the open group, not wherever the library felt like")
        XCTAssertEqual(made.name, Brush.manualBaseName)
        XCTAssertEqual(made.tip, .round)
        XCTAssertTrue(made.modulations.rows.isEmpty,
                      "A neutral brush carries no rows — a copy of any shipped preset carries two")
        XCTAssertEqual(made.dab, .default)
        XCTAssertEqual(made.stroke, .default)
        XCTAssertNil(made.texture)
        XCTAssertFalse(BrushLibrary.defaults.contains { $0.name == made.name },
                       "PREMISE: it is not one of the shipped presets under another id")

        let second = store.createBrush(inGroup: target.id)
        XCTAssertNotEqual(second.name, made.name,
                          "A row's identifier is its name; two the same is one unreachable row")
        XCTAssertEqual(store.groups.first { $0.id == target.id }?.brushes.count, 2)
    }

    // MARK: - BRUSH.md §7.2 — the pad's magnification

    /// **Zoom scales the view of a canvas-space render and leaves the brush alone.**
    ///
    /// §7.2's own words: the pad *"draws through the real stamper, so zoom must scale the view of a
    /// canvas-space render, not the brush's size — a brush drawn at 3× size is a different brush, not
    /// a magnified one"*. Getting it backwards makes the pad lie, which is the one thing it exists
    /// not to do.
    ///
    /// **Two operands, and neither works alone.** The stroke's width measured in *canvas points* must
    /// be the same at both zooms — that is the half a brush-scaling implementation fails. And the
    /// same width measured in *device pixels* must differ by the zoom — that is the half a pad which
    /// ignored zoom entirely would fail, and without it the first assertion is green against a
    /// control that does nothing at all.
    func testThePadZoomScalesTheViewAndNotTheBrush() throws {
        var brush = Brush.manuallyCreated(named: "flat")
        brush.dab.hardness = 1                       // a crisp disc, so an edge is an edge
        brush.dab.spacing = 0.05
        let strokeWidth: CGFloat = 20
        let viewSize = CGSize(width: 300, height: 200)
        let screenScale: CGFloat = 2
        // Inside the canvas extent at **both** zooms: at 3× this pad shows 100 × 66.7 canvas points.
        let path = StrokeSamples([VectorSample(point: CGPoint(x: 10, y: 30), pressure: 1),
                                  VectorSample(point: CGPoint(x: 60, y: 30), pressure: 1)],
                                 channels: .pressureOnly)

        var pixelWidths: [CGFloat: Int] = [:]
        for zoom in [BrushPadZoom.realSize, BrushPadZoom.standard] {
            let ctx = try XCTUnwrap(BrushPadZoom.makeContext(viewSize: viewSize,
                                                             screenScale: screenScale, zoom: zoom))
            BrushStamper.stampStroke(into: CGContextDabTarget(ctx), samples: path, brush: brush,
                                     color: .black, brushSize: strokeWidth, brushOpacity: 1,
                                     isEraser: false, random: DabRandom(seed: 7))
            // The device-pixel column through the middle of the stroke, at canvas x = 35.
            let column = Int(35 * screenScale * zoom)
            pixelWidths[zoom] = inkedRows(in: ctx, atColumn: column)
        }

        let real = try XCTUnwrap(pixelWidths[BrushPadZoom.realSize])
        let zoomed = try XCTUnwrap(pixelWidths[BrushPadZoom.standard])
        XCTAssertGreaterThan(real, 30, "PREMISE: a 20 pt stroke at 2× screen scale is about 40 pixels")

        let ratio = Double(zoomed) / Double(real)
        XCTAssertEqual(ratio, Double(BrushPadZoom.standard), accuracy: 0.25,
                       "The same stroke must occupy the zoom's multiple of the pixels — a pad that "
                       + "ignored the zoom would draw the identical picture")

        let realCanvasPoints = Double(real) / Double(screenScale * BrushPadZoom.realSize)
        let zoomedCanvasPoints = Double(zoomed) / Double(screenScale * BrushPadZoom.standard)
        XCTAssertEqual(zoomedCanvasPoints, realCanvasPoints, accuracy: 1.5,
                       "…and it must be the same width in **canvas points** at both, or the zoom "
                       + "scaled the brush rather than the view of it")

        // The arithmetic the two above are consequences of.
        XCTAssertEqual(BrushPadZoom.canvasSize(of: viewSize, at: 3).width, 100, accuracy: 0.001)
        XCTAssertEqual(BrushPadZoom.canvasPoint(CGPoint(x: 30, y: 60), at: 3), CGPoint(x: 10, y: 20))
        XCTAssertEqual(BrushPadZoom.toggled(BrushPadZoom.standard), BrushPadZoom.realSize)
        XCTAssertEqual(BrushPadZoom.toggled(BrushPadZoom.realSize), BrushPadZoom.standard)
        XCTAssertFalse(BrushPadZoom.isRealSize(BrushPadZoom.standard),
                       "PREMISE: the pad opens zoomed in — §7.2's second ask")
    }

    /// **There is one sample stroke in the codebase and it tapers.**
    ///
    /// §7.2: *"The default stroke must be the same fixed S-curve `BrushPreview` walks for §7.1's menu
    /// rows. One sample stroke in the codebase, not two, or a brush's row and its pad disagree about
    /// what it looks like."* So the row's render is asserted to be **exactly** what
    /// `BrushPreview.stampSample` lays down — the call the pad makes — rather than merely similar to
    /// it. A row that grew a private stroke would still look right beside a pad that had one too.
    ///
    /// The taper is the owner's own word for what the sample is *for*: a constant-pressure line
    /// renders four of the five shipped presets as near-identical bars.
    func testTheOneSampleStrokeTapersAndIsWhatAMenuRowDraws() throws {
        let size = CGSize(width: 156, height: 26)
        let samples = BrushPreview.samples(in: size)
        let pressures = samples.map(\.pressure)
        XCTAssertLessThan(try XCTUnwrap(pressures.first), 0.15, "It starts on a taper")
        XCTAssertLessThan(try XCTUnwrap(pressures.last), 0.15, "…and ends on one")
        XCTAssertGreaterThan(try XCTUnwrap(pressures.max()), 0.95, "…with a press between them")
        // **An S, which means it leaves the midline in *both* directions.** A range assertion was
        // tried first and had the wrong threshold in it: at a menu row's 156 × 26 the inset is
        // driven by the height, so the whole curve is about four points tall. What makes it an S is
        // the sign change, not the size.
        let midline = size.height / 2
        let ys = samples.map { $0.point.y }
        XCTAssertGreaterThan(try XCTUnwrap(ys.max()), midline + 1, "It dips below the midline")
        XCTAssertLessThan(try XCTUnwrap(ys.min()), midline - 1, "…and rises above it")

        let brush = BrushLibrary.softRound
        let fromRow = BrushPreview.render(brush, size: size, scale: 2, color: .white)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 2
        format.opaque = false
        let byHand = UIGraphicsImageRenderer(size: size, format: format).image { context in
            BrushPreview.stampSample(into: CGContextDabTarget(context.cgContext), over: size,
                                     brush: brush, color: .white,
                                     strokeWidth: BrushPreview.strokeWidth(for: brush, in: size),
                                     opacity: brush.opacity)
        }
        XCTAssertEqual(fromRow.pngData(), byHand.pngData(),
                       "A menu row must be that one stamp and nothing of its own")
    }

    // MARK: - Helpers for the four above

    private func builtIns(of items: [BrushAssetItem]) -> [BuiltInBrushTexture] {
        items.compactMap { item -> BuiltInBrushTexture? in
            guard case .builtIn(let builtIn) = item.ref else { return nil }
            return builtIn
        }
    }

    private func makeScratchRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brush-editor-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A `width × height` opaque black picture — read by luminance on the way in, by both importers,
    /// so it comes out as full coverage wherever it is drawn.
    private func solidImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func alphaGrid(of image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: buffer.count, by: 4).map { buffer[$0] }
    }

    /// How many rows of one device-pixel column carry ink.
    private func inkedRows(in ctx: CGContext, atColumn column: Int) -> Int {
        guard let data = ctx.data, column >= 0, column < ctx.width else { return 0 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        var count = 0
        for row in 0..<ctx.height where bytes[row * ctx.bytesPerRow + column * 4 + 3] > 8 { count += 1 }
        return count
    }
}
