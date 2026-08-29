import XCTest

/// `AnimationCurve` — the value curve every keyframe channel is made of (KEYFRAMES.md §3.2).
///
/// `AnimationCurve.swift` is compiled into this target as well as the app (see the project file's
/// shared-sources group), which is what its Foundation-only shape is for: none of what follows needs
/// a canvas, a manager or a simulator, so all of it runs in the fast tier.
///
/// The file's doc comment states four decisions, and the four sections below are what pins them.
/// Each is a decision that has a way of being made by accident — by inheriting an interpolant's
/// incidental behaviour, or by an evaluator that divides by zero on data no UI can currently produce
/// but a hand-edited sidecar can.
final class AnimationCurveLogicTests: XCTestCase {

    // MARK: - Helpers

    private typealias Curve = AnimationCurve
    private typealias Key = AnimationCurve.Key
    private typealias Handle = AnimationCurve.Handle

    private func key(_ frame: Int,
                     _ value: Double,
                     _ interpolation: Curve.Interpolation = .bezier,
                     _ tangentMode: Curve.TangentMode = .autoClamped) -> Key {
        Key(frame: frame, value: value, tangentMode: tangentMode, interpolation: interpolation)
    }

    /// The curve sampled ten times a frame across `range`, which is what "does not overshoot" has to
    /// be asked at — a bezier's extremum is almost never on a frame boundary.
    private func extremes(_ curve: Curve, from lower: Double, to upper: Double) -> (min: Double, max: Double) {
        var low = Double.greatestFiniteMagnitude, high = -Double.greatestFiniteMagnitude
        var t = lower
        while t <= upper + 1e-9 {
            let v = curve.evaluate(at: t)
            low = Swift.min(low, v)
            high = Swift.max(high, v)
            t += 0.1
        }
        return (low, high)
    }

    // MARK: - The three interpolation modes

    /// `.constant` is the hold, and it is carried on the key that *begins* the segment — which is the
    /// whole reason interpolation is stored per-key rather than per-curve: one hold sits here between
    /// two eases without disturbing either.
    func testAConstantSegmentHoldsItsStartValueAndStepsAtTheNextKey() {
        let curve = Curve(keys: [key(0, 0, .linear), key(10, 5, .constant), key(20, 15, .linear)])

        XCTAssertEqual(curve.evaluate(at: 10), 5, "the hold begins at its own key's value")
        XCTAssertEqual(curve.evaluate(at: 14), 5, "and does not move through the segment")
        XCTAssertEqual(curve.evaluate(at: 19.999), 5, "right up to the next key")
        XCTAssertEqual(curve.evaluate(at: 20), 15, "where it steps")

        XCTAssertEqual(curve.evaluate(at: 5), 2.5, accuracy: 1e-12, "the ease before it is untouched")
    }

    func testALinearSegmentIsTheStraightLineBetweenItsKeys() {
        let curve = Curve(keys: [key(0, 0, .linear), key(8, 4, .linear)])
        for frame in 0...8 {
            XCTAssertEqual(curve.evaluate(at: Double(frame)), Double(frame) / 2, accuracy: 1e-12)
        }
        XCTAssertEqual(curve.evaluate(at: 3.5), 1.75, accuracy: 1e-12, "including between frames")
    }

    /// A bezier segment is pinned at its keys and eases between them. With `.autoClamped` at both ends
    /// of a two-key curve both handles are flat (no neighbour on the outside), so the segment is the
    /// symmetric ease and its midpoint is exactly halfway.
    func testABezierSegmentIsPinnedAtItsKeysAndEasesBetweenThem() {
        let curve = Curve(keys: [key(0, 0), key(10, 1)])

        XCTAssertEqual(curve.evaluate(at: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(curve.evaluate(at: 10), 1, accuracy: 1e-12)
        XCTAssertEqual(curve.evaluate(at: 5), 0.5, accuracy: 1e-9, "symmetric handles, symmetric curve")

        XCTAssertLessThan(curve.evaluate(at: 2), 0.2, "eased in: slower than linear at the start")
        XCTAssertGreaterThan(curve.evaluate(at: 8), 0.8, "eased out: slower than linear at the end")
    }

    // MARK: - Decision 1 — the output is never clamped

    /// Overshoot is the feature. A `.free` handle authored to swing past its target does, and the
    /// value it reaches is nowhere near 0…1 in either direction.
    func testAFreeHandleOvershootIsNotClampedAway() {
        let curve = Curve(keys: [
            Key(frame: 0, value: 0, outHandle: Handle(deltaFrames: 5, deltaValue: 4), tangentMode: .free),
            Key(frame: 10, value: 1, inHandle: Handle(deltaFrames: -5, deltaValue: 4), tangentMode: .free)
        ])
        let swing = extremes(curve, from: 0, to: 10)

        XCTAssertGreaterThan(swing.max, 3, "the curve rides well above both of its keys and is not clipped to 1")
        XCTAssertEqual(curve.evaluate(at: 0), 0, accuracy: 1e-12, "and still lands on its keys")
        XCTAssertEqual(curve.evaluate(at: 10), 1, accuracy: 1e-12)
    }

    /// The other direction, and outside 0…1 on the negative side, because a range clamp written for an
    /// opacity would most likely be `0...1` and would be invisible in the test above.
    func testTheCurveIsNotClampedToAnyRangeInEitherDirection() {
        let curve = Curve(keys: [
            Key(frame: 0, value: 0, outHandle: Handle(deltaFrames: 5, deltaValue: -60), tangentMode: .free),
            Key(frame: 10, value: 100, inHandle: Handle(deltaFrames: -5, deltaValue: 60), tangentMode: .free)
        ])
        let swing = extremes(curve, from: 0, to: 10)

        XCTAssertLessThan(swing.min, -5, "below zero, and well below it")
        XCTAssertGreaterThan(swing.max, 105, "and above the larger key")
    }

    // MARK: - Decision 2 — extrapolation is a constant hold

    func testTheCurveHoldsFlatBeforeTheFirstKeyAndAfterTheLast() {
        let curve = Curve(keys: [key(10, 3, .linear), key(20, 8, .linear)])

        XCTAssertEqual(curve.evaluate(at: 9), 3, "held, not extended along the tangent")
        XCTAssertEqual(curve.evaluate(at: -500), 3, "however far back it is asked")
        XCTAssertEqual(curve.evaluate(at: 21), 8)
        XCTAssertEqual(curve.evaluate(at: 5_000), 8, "a linear extrapolation here would be 2503")
    }

    /// The other half of decision 2: an `.auto` handle at the first and last key is flat, so the curve
    /// meets the held region without a corner. A scheme that pointed the end handles along their one
    /// available segment would leave a visible kink at the outermost keys of every channel.
    func testAutoHandlesAreFlatAtTheFirstAndLastKey() {
        let curve = Curve(keys: [key(0, 0, .bezier, .auto), key(10, 1, .bezier, .auto), key(20, 5, .bezier, .auto)])

        XCTAssertEqual(curve.effectiveHandles(at: 0).outHandle.deltaValue, 0, accuracy: 1e-12)
        XCTAssertEqual(curve.effectiveHandles(at: 2).inHandle.deltaValue, 0, accuracy: 1e-12)
        XCTAssertNotEqual(curve.effectiveHandles(at: 1).outHandle.deltaValue, 0,
                          "while the interior key takes a real tangent from its neighbours")
    }

    // MARK: - Decision 3 — a bezier segment stays a function of time

    /// Handles dragged far enough along the frame axis to fold the curve back. Authoring keeps what was
    /// drawn; evaluation clamps the frame components into the segment, so the curve is still one value
    /// per frame and still monotone where its value controls are.
    ///
    /// These particular handles clamp to `x1 = 1, x2 = 0` — the extreme of the admissible set, where
    /// the x-map's derivative touches zero at the midpoint. If the clamp were merely conservative
    /// rather than sufficient, this is the input that would break it.
    func testAFoldedBezierAuthoringStillEvaluatesSingleValued() {
        let curve = Curve(keys: [
            Key(frame: 0, value: 0, outHandle: Handle(deltaFrames: 400, deltaValue: 0), tangentMode: .free),
            Key(frame: 10, value: 1, inHandle: Handle(deltaFrames: -400, deltaValue: 0), tangentMode: .free)
        ])

        XCTAssertEqual(curve.keys[0].outHandle.deltaFrames, 400, "what the artist drew is still stored")

        var previous = -Double.greatestFiniteMagnitude
        var t = 0.0
        while t <= 10 {
            let v = curve.evaluate(at: t)
            XCTAssertFalse(v.isNaN, "at \(t)")
            XCTAssertGreaterThanOrEqual(v, previous - 1e-12,
                                        "a fold would come back down; at \(t) it went \(previous) -> \(v)")
            previous = v
            t += 0.05
        }
        XCTAssertEqual(curve.evaluate(at: 10), 1, accuracy: 1e-9, "and still reaches the far key")
    }

    /// The property underneath it, asked of the inverse directly: for any admissible pair of clamped x
    /// controls, `bezierParameter(forX:)` really does invert the x map, which is the same statement as
    /// "one time, one parameter, one value".
    func testBezierParameterInvertsTheClampedXMappingForEveryAdmissiblePair() {
        for a in stride(from: 0.0, through: 1.0, by: 0.125) {
            for b in stride(from: 0.0, through: 1.0, by: 0.125) {
                var lastS = -1.0
                for step in 0...40 {
                    let x = Double(step) / 40
                    let s = Curve.bezierParameter(forX: x, x1: a, x2: b)
                    XCTAssertEqual(Curve.cubic(s, 0, a, b, 1), x, accuracy: 1e-6,
                                   "x1=\(a) x2=\(b) x=\(x)")
                    XCTAssertGreaterThanOrEqual(s, lastS - 1e-9, "the parameter never runs backwards")
                    lastS = s
                }
            }
        }
    }

    // MARK: - Decision 4 — one key per frame, the later one wins

    func testTwoKeysOnOneFrameCollapseToTheLaterOne() {
        let curve = Curve(keys: [key(0, 0), key(5, 1), key(5, 9), key(10, 2)])

        XCTAssertEqual(curve.keys.map(\.frame), [0, 5, 10])
        XCTAssertEqual(curve.keys[1].value, 9, "the later one in the caller's array wins")
        XCTAssertEqual(curve.evaluate(at: 5), 9)
    }

    func testKeysAreSortedOnConstructionSoAnUnorderedArrayIsStillWellFormed() {
        let curve = Curve(keys: [key(20, 3), key(0, 1), key(10, 2)])
        XCTAssertEqual(curve.keys.map(\.frame), [0, 10, 20])
        XCTAssertEqual(curve.evaluate(at: 20), 3)
    }

    func testSetKeyOnAnOccupiedFrameReplacesRatherThanAppends() {
        var curve = Curve(keys: [key(0, 0), key(10, 1)])

        curve.setKey(key(10, 7))
        XCTAssertEqual(curve.keys.count, 2, "no duplicate was created")
        XCTAssertEqual(curve.evaluate(at: 10), 7)

        curve.setKey(key(5, 3))
        XCTAssertEqual(curve.keys.map(\.frame), [0, 5, 10], "and an insert lands in order")

        curve.setKey(key(99, 4))
        XCTAssertEqual(curve.keys.map(\.frame), [0, 5, 10, 99], "including past the end")

        curve.removeKey(atFrame: 5)
        XCTAssertEqual(curve.keys.map(\.frame), [0, 10, 99])
        XCTAssertNil(curve.key(atFrame: 5))
    }

    /// The rule has to hold at the *other* entry point too: a hand-edited or corrupt sidecar is the
    /// only realistic source of a duplicate frame, and it arrives through `init(from:)`.
    func testDecodingADuplicateFrameNormalisesItTheSameWay() throws {
        let json = Data("""
        {"step":1,"keys":[
          {"frame":10,"value":9.0},
          {"frame":0,"value":0.0},
          {"frame":10,"value":1.0}
        ]}
        """.utf8)
        let curve = try JSONDecoder().decode(Curve.self, from: json)

        XCTAssertEqual(curve.keys.map(\.frame), [0, 10])
        XCTAssertEqual(curve.keys[1].value, 1, "the later of the two in the file")
    }

    // MARK: - `step` (§2.10)

    func testStepHoldsTheEvaluatedValueForItsRun() {
        let curve = Curve(keys: [key(0, 0, .linear), key(10, 10, .linear)], step: 2)
        XCTAssertEqual((0...10).map { curve.evaluate(at: Double($0)) },
                       [0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 10])

        var threes = curve
        threes.step = 3
        XCTAssertEqual((0...9).map { threes.evaluate(at: Double($0)) },
                       [0, 0, 0, 3, 3, 3, 6, 6, 6, 9])
    }

    /// `step: 1` must be a true identity rather than a round-down, or it would quietly truncate the
    /// sub-frame time the `Double` signature exists to accept.
    func testStepOneIsTheIdentityIncludingSubFrameTime() {
        let curve = Curve(keys: [key(0, 0, .linear), key(10, 10, .linear)], step: 1)
        XCTAssertEqual(curve.evaluate(at: 2.5), 2.5, accuracy: 1e-12)
        XCTAssertEqual(curve.evaluate(at: 7.25), 7.25, accuracy: 1e-12)
        XCTAssertEqual(curve.stepped(2.5), 2.5, "and the quantiser itself is the identity")

        var zero = curve
        zero.step = 0
        XCTAssertEqual(zero.evaluate(at: 2.5), 2.5, accuracy: 1e-12, "a step below 1 is treated as 1")
    }

    /// The run is anchored at frame 0 of the curve's own time base, not at the first key. Anchoring at
    /// the first key would make two channels both set to twos step on opposite frames whenever their
    /// first keys differ in parity — the one thing "on twos" exists to prevent.
    func testStepIsAnchoredAtFrameZeroNotTheFirstKey() {
        let odd = Curve(keys: [key(3, 0, .linear), key(13, 10, .linear)], step: 2)

        XCTAssertEqual(odd.evaluate(at: 4), odd.evaluate(at: 5), "frames 4 and 5 share one run…")
        XCTAssertNotEqual(odd.evaluate(at: 5), odd.evaluate(at: 6), "…and 6 begins the next")
        XCTAssertEqual(odd.stepped(7), 6, "even frames start the runs, whatever the first key is")
    }

    // MARK: - Codable

    func testACurveRoundTripsThroughCodable() throws {
        let original = Curve(keys: [
            Key(frame: 0, value: -3.5, outHandle: Handle(deltaFrames: 2, deltaValue: 1.25),
                tangentMode: .free, interpolation: .bezier),
            Key(frame: 7, value: 0, inHandle: Handle(deltaFrames: -1.5, deltaValue: -0.5),
                outHandle: Handle(deltaFrames: 3, deltaValue: 9),
                tangentMode: .aligned, interpolation: .constant),
            Key(frame: 24, value: 110, tangentMode: .vector, interpolation: .linear)
        ], step: 3)

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Curve.self, from: data)

        XCTAssertEqual(restored, original, "every field, including both handles and both enums")
        for frame in -5...30 {
            XCTAssertEqual(restored.evaluate(at: Double(frame)),
                           original.evaluate(at: Double(frame)), accuracy: 1e-12, "at \(frame)")
        }
    }

    /// Field-presence versioning, the idiom every persisted field in this tree follows: a curve written
    /// before a field existed decodes to that field's default rather than failing the whole sidecar.
    func testAbsentFieldsDecodeToTheirDefaults() throws {
        let json = Data("""
        {"keys":[{"frame":0,"value":0.0},{"frame":10,"value":1.0}]}
        """.utf8)
        let curve = try JSONDecoder().decode(Curve.self, from: json)

        XCTAssertEqual(curve.step, 1, "no step means every frame")
        XCTAssertEqual(curve.keys[0].tangentMode, .autoClamped, "the default tangent mode")
        XCTAssertEqual(curve.keys[0].interpolation, .bezier)
        XCTAssertEqual(curve.keys[0].inHandle, .zero)

        let empty = try JSONDecoder().decode(Curve.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.isEmpty, "and an object with no keys at all is a curve with no keys")
    }

    // MARK: - Degenerate curves

    func testASingleKeyCurveIsThatValueEverywhere() {
        let curve = Curve(keys: [key(7, 42)])

        XCTAssertTrue(curve.evaluate(at: -1_000) == 42 && curve.evaluate(at: 7) == 42
                      && curve.evaluate(at: 1_000) == 42,
                      "both extrapolations are holds, so one key is a constant")
        XCTAssertFalse(curve.isEmpty)
    }

    /// An empty curve has no value to give and returns 0. It is why `isEmpty` is public: a channel with
    /// no keys is not animated, and the caller is meant to use its static value rather than this.
    func testAnEmptyCurveIsZeroAndSaysSo() {
        let curve = Curve()
        XCTAssertTrue(curve.isEmpty)
        XCTAssertEqual(curve.evaluate(at: 0), 0)
        XCTAssertEqual(curve.evaluate(at: 12.5), 0)
        XCTAssertNil(curve.key(atFrame: 0))
    }

    // MARK: - Tangent modes, and the overshoot they do or do not permit

    /// The headline pairing. The same three keys, evaluated once with the default `.autoClamped` and
    /// once with `.free` handles authored to swing: the first stays inside its keys, the second does
    /// not — and neither is clamped by the evaluator, which is decision 1. `.autoClamped`'s restraint
    /// comes from where its handles are put, not from a limiter on the output.
    func testAutoClampedDoesNotOvershootBetweenTwoKeysWhileAFreeHandleDoes() {
        let clamped = Curve(keys: [key(0, 0), key(10, 1), key(20, 0.9)])
        let swing = extremes(clamped, from: 0, to: 20)
        XCTAssertGreaterThanOrEqual(swing.min, -1e-9, "never below the lowest key")
        XCTAssertLessThanOrEqual(swing.max, 1 + 1e-9, "and never above the highest — 1 is a local maximum")

        let free = Curve(keys: [
            Key(frame: 0, value: 0, outHandle: Handle(deltaFrames: 3, deltaValue: 0), tangentMode: .free),
            Key(frame: 10, value: 1, inHandle: Handle(deltaFrames: -3, deltaValue: -0.9),
                outHandle: Handle(deltaFrames: 3, deltaValue: 0.9), tangentMode: .free),
            Key(frame: 20, value: 0.9, inHandle: Handle(deltaFrames: -3, deltaValue: 0), tangentMode: .free)
        ])
        XCTAssertGreaterThan(extremes(free, from: 10, to: 20).max, 1.2,
                             "the same keys, authored to overshoot, do")
    }

    /// `.auto` is `.autoClamped` without the tip clamp, and the difference is exactly the overshoot.
    /// Both directions, because the undershoot below a segment's floor is the one that gets missed: it
    /// needs a steep run *after* the key to pull the *incoming* handle below the earlier key's value.
    func testAutoOvershootsWhereAutoClampedDoesNot() {
        let above = Curve(keys: [key(0, 0, .bezier, .auto), key(10, 1, .bezier, .auto), key(20, 0.9, .bezier, .auto)])
        XCTAssertGreaterThan(extremes(above, from: 0, to: 20).max, 1.02,
                             "the secant through the neighbours carries the handle past the local maximum")

        let below = Curve(keys: [key(0, 0, .bezier, .auto), key(10, 1, .bezier, .auto), key(20, 10, .bezier, .auto)])
        XCTAssertLessThan(extremes(below, from: 0, to: 10).min, -0.05,
                          "and a steep second segment drags the first below its own floor")

        let fixed = Curve(keys: [key(0, 0), key(10, 1), key(20, 10)])
        XCTAssertGreaterThanOrEqual(extremes(fixed, from: 0, to: 10).min, -1e-9,
                                    "which is precisely what the tip clamp removes")
    }

    func testVectorHandlesPointAThirdOfTheWayAtTheNeighbouringKeys() {
        let curve = Curve(keys: [key(0, 0, .bezier, .vector), key(9, 3, .bezier, .vector), key(18, 3, .bezier, .vector)])
        let middle = curve.effectiveHandles(at: 1)

        XCTAssertEqual(middle.inHandle.deltaFrames, -3, accuracy: 1e-12)
        XCTAssertEqual(middle.inHandle.deltaValue, -1, accuracy: 1e-12, "a third of the way back at key 0")
        XCTAssertEqual(middle.outHandle.deltaFrames, 3, accuracy: 1e-12)
        XCTAssertEqual(middle.outHandle.deltaValue, 0, accuracy: 1e-12, "and flat toward a flat neighbour")

        XCTAssertEqual(curve.evaluate(at: 4.5), 1.5, accuracy: 1e-9,
                       "so the segment either side of a vector join is the straight line")
    }

    func testAlignedHandlesShareOneDirectionAndKeepTheirOwnLengths() {
        let key = Key(frame: 10, value: 0,
                      inHandle: Handle(deltaFrames: -1, deltaValue: 1),      // up-and-back
                      outHandle: Handle(deltaFrames: 4, deltaValue: 0),      // flat forward
                      tangentMode: .aligned)
        let curve = Curve(keys: [self.key(0, 0), key, self.key(20, 0)])
        let handles = curve.effectiveHandles(at: 1)

        // The two authored directions are 45 degrees apart; the shared one is their mean.
        let inDirection = handles.inHandle.negated.unit!
        let outDirection = handles.outHandle.unit!
        XCTAssertEqual(inDirection.deltaFrames, outDirection.deltaFrames, accuracy: 1e-12)
        XCTAssertEqual(inDirection.deltaValue, outDirection.deltaValue, accuracy: 1e-12)
        XCTAssertLessThan(outDirection.deltaValue, 0, "and it tilts down, between flat and 45 degrees up")

        XCTAssertEqual(handles.inHandle.length, Handle(deltaFrames: -1, deltaValue: 1).length, accuracy: 1e-12)
        XCTAssertEqual(handles.outHandle.length, 4, accuracy: 1e-12, "each keeps the length it was given")
    }

    /// `.aligned` has to be the identity on data that is already aligned, or every save/load cycle
    /// would creep the handles — the same failure `SpacingChart.curve` documents for its own
    /// round trip.
    func testAlignedIsTheIdentityOnHandlesThatAlreadyAgree() {
        let key = Key(frame: 10, value: 0,
                      inHandle: Handle(deltaFrames: -2, deltaValue: -1),
                      outHandle: Handle(deltaFrames: 6, deltaValue: 3),
                      tangentMode: .aligned)
        let handles = Curve(keys: [self.key(0, 0), key, self.key(20, 0)]).effectiveHandles(at: 1)

        XCTAssertEqual(handles.inHandle.deltaFrames, -2, accuracy: 1e-12)
        XCTAssertEqual(handles.inHandle.deltaValue, -1, accuracy: 1e-12)
        XCTAssertEqual(handles.outHandle.deltaFrames, 6, accuracy: 1e-12)
        XCTAssertEqual(handles.outHandle.deltaValue, 3, accuracy: 1e-12)
    }

    /// A degenerate pair has no direction to agree on. Returning the stored handles is the only answer
    /// that does not invent an axis, and it keeps `effectiveHandles` total.
    func testAlignedWithADegenerateHandlePairReturnsWhatWasStored() {
        let zeroOut = Key(frame: 10, value: 0,
                          inHandle: Handle(deltaFrames: -2, deltaValue: -1),
                          outHandle: .zero, tangentMode: .aligned)
        let curve = Curve(keys: [key(0, 0), zeroOut, key(20, 0)])
        XCTAssertEqual(curve.effectiveHandles(at: 1).inHandle, Handle(deltaFrames: -2, deltaValue: -1))
        XCTAssertEqual(curve.effectiveHandles(at: 1).outHandle, .zero)

        let opposed = Key(frame: 10, value: 0,
                          inHandle: Handle(deltaFrames: 2, deltaValue: 0),    // both point forward
                          outHandle: Handle(deltaFrames: 2, deltaValue: 0),   // so the mean cancels
                          tangentMode: .aligned)
        let odd = Curve(keys: [key(0, 0), opposed, key(20, 0)])
        XCTAssertEqual(odd.effectiveHandles(at: 1).inHandle, Handle(deltaFrames: 2, deltaValue: 0))
        XCTAssertEqual(odd.effectiveHandles(at: 1).outHandle, Handle(deltaFrames: 2, deltaValue: 0))
    }

    /// `.free` is the only mode that returns the stored handles untouched, and the derived modes ignore
    /// them completely — which is what lets the editor keep an artist's handles while they experiment
    /// with a mode, and what stops a derived handle going stale when a neighbour moves.
    func testDerivedModesIgnoreTheStoredHandlesEntirely() {
        let stored = Handle(deltaFrames: 99, deltaValue: -99)
        func curve(_ mode: Curve.TangentMode) -> Curve {
            Curve(keys: [key(0, 0),
                         Key(frame: 10, value: 1, inHandle: stored, outHandle: stored, tangentMode: mode),
                         key(20, 2)])
        }
        for mode in [Curve.TangentMode.auto, .autoClamped, .vector] {
            let handles = curve(mode).effectiveHandles(at: 1)
            XCTAssertNotEqual(handles.outHandle, stored, "\(mode) derives its own")
            XCTAssertEqual(handles.outHandle.deltaFrames, 10.0 / 3, accuracy: 1e-12, "\(mode)")
        }
        XCTAssertEqual(curve(.free).effectiveHandles(at: 1).outHandle, stored)
    }
}
