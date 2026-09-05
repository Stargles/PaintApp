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
            BrushModulation(.scatter, .random(.modulation(.scatter, row: 0), wavelength: 2), amount: 0.3),
            BrushModulation(.scatter, .random(.modulation(.scatter, row: 1), wavelength: 5), amount: 0.2)
        ])
        let secondChannel = channel(of: modulations.rows[1].input)

        modulations.remove(at: 0)
        XCTAssertEqual(modulations.rows.count, 1)
        XCTAssertNotEqual(channel(of: modulations.rows[0].input), secondChannel,
                          "The surviving row moved to position 0, so its cell must move with it")
        XCTAssertEqual(channel(of: modulations.rows[0].input),
                       channel(of: BrushInput.random(.modulation(.scatter, row: 0), wavelength: 5)))
        XCTAssertEqual(modulations.rows[0].input.wavelength, 5, "…and its authored λ is untouched")

        modulations.append(BrushModulation(.scatter, .random(.modulation(.size, row: 9), wavelength: 1), amount: 0.1))
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

    // MARK: - The chain, and where it stops fitting

    /// **§2.24's chain and §6's row are the same thing on the ordinary case.** A row is
    /// `amount · curve(input) · second`, which read left to right is an input, a curve ramp and a
    /// gain — so this round-trips rather than approximating.
    func testAChainRoundTripsAnOrdinaryRow() {
        let rows = [
            BrushModulation(.size, .pressure, amount: 0.5, curve: .ramp(from: 0.2, to: 1)),
            BrushModulation(.flow, .tiltAngle, amount: -0.3),
            BrushModulation(.spacing, .pressure,
                            second: .random(.modulation(.spacing, row: 0, slot: 1), wavelength: 4),
                            amount: 0.4, curve: .threshold(knee: 0.4)),
            BrushModulation(.scatter, .velocity, second: .pressure, amount: 0.8)
        ]
        for row in rows {
            let rebuilt = BrushModulationChain(row).row(driving: row.output)
            XCTAssertEqual(rebuilt, row, "A chain read off a row and written back must be that row")
        }
    }

    /// **§7.0's fourth worked example, as the editor states it.** *"How much random wobble there is
    /// depends on pressure"* is the second slot at `.random` with pressure in the first — a
    /// randomiser module scaling what the curve produced.
    func testTheSecondSlotAtRandomReadsAsARandomiserModule() {
        let row = BrushModulation(.spacing, .pressure,
                                  second: .random(.modulation(.spacing, row: 0, slot: 1), wavelength: 3),
                                  amount: 0.5)
        let chain = BrushModulationChain(row)
        XCTAssertEqual(chain.modules, [.randomiser(wavelength: 3)])
        XCTAssertEqual(chain.input.kind, .pressure)

        // …and it is a *gain*, not a row: the wobble's amplitude is what pressure moves.
        XCTAssertEqual(row.contribution(1, second: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(row.contribution(1, second: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(row.contribution(0.5, second: 0.5), 0.125, accuracy: 1e-12)
    }

    /// **Where the two models genuinely differ, asserted rather than described.** A chain the owner
    /// could draw — two curve ramps in series — cannot be stored, and the last one wins. This is the
    /// boundary BRUSH.md §13 carries; it goes red if somebody later makes the storage able to hold
    /// both, which is the point.
    func testAChainWithTwoOfAModuleLosesOneAndTheLimitSaysSo() {
        let chain = BrushModulationChain(BrushModulation(.size, .pressure, amount: 1))
        var twoRamps = chain
        twoRamps.modules = [.curveRamp(.ramp(from: 0, to: 1)), .curveRamp(.threshold(knee: 0.5))]
        let rebuilt = twoRamps.row(driving: .size)
        XCTAssertEqual(rebuilt.curve, .threshold(knee: 0.5), "One `curve` field, so the last ramp wins")
        XCTAssertEqual(BrushModulationChain(rebuilt).modules.count, 1,
                       "…and reading it back gives one module, which is the honest shape")

        var twoSeconds = chain
        twoSeconds.modules = [.randomiser(wavelength: 2), .gain(.pressure)]
        XCTAssertEqual(BrushModulationChain(twoSeconds.row(driving: .size)).modules, [.gain(.pressure)],
                       "One `second` field, so a randomiser and a gain are alternatives")

        // The four sentences the screen shows are the four this file names.
        XCTAssertEqual(BrushChainLimit.allCases.count, 4)
        for limit in BrushChainLimit.allCases {
            XCTAssertFalse(limit.explanation.isEmpty)
        }
    }

    /// **The randomiser's cell is minted from the second slot, one plane up** — §6.2. A chain that
    /// rebuilt the row with the *first* slot's channel would make a row randomised on both sides
    /// square one draw instead of multiplying two, which is the trap §2.22 names by name.
    func testARebuiltRandomiserDrawsFromTheSecondPlane() {
        let chain = BrushModulationChain(BrushModulation(
            .spacing, .random(.modulation(.spacing, row: 0), wavelength: 2), amount: 1))
        var withRandomiser = chain
        withRandomiser.modules = [.randomiser(wavelength: 6)]
        // Through `BrushModulations`, because that is the only door the app has and the type is what
        // holds the invariant — a chain's own answer is overwritten by it either way.
        let modulations = BrushModulations([withRandomiser.row(driving: .spacing)])
        let row = modulations.rows[0]
        XCTAssertNotEqual(channel(of: row.input), channel(of: row.second!),
                          "Both slots randomised must be two independent draws")
        XCTAssertEqual(channel(of: row.second!),
                       channel(of: .random(.modulation(.spacing, row: 0, slot: 1), wavelength: 6)))
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

    // MARK: -

    private func channel(of input: BrushInput) -> UInt64 {
        guard case .random(let channel, _) = input else { return .max }
        return channel.rawValue
    }
}
