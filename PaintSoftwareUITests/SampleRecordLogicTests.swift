import XCTest
import CoreGraphics
import UIKit
@testable import PaintSoftware

/// **The sample record** — BRUSH.md §12 stage 4: the channel set, struct-of-arrays, Δt, tilt, and
/// §5.5's evaluation funnel with its defined neutral.
///
/// The load-bearing test in this file is
/// `testABrushReadingAChannelTheStrokeDoesNotCarryDrawsWhatTheSameBrushWithoutThatModulationDraws`.
/// Everything else supports it: the neutral has to survive quantisation exactly, an absent channel has
/// to cost nothing, and a channel a run does carry must not shift the bytes of the ones beside it.
final class SampleRecordLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A four-point run carrying every channel, with values that are *not* any channel's neutral, so a
    /// test that accidentally reads the neutral fails rather than agreeing by luck.
    private func fullRun() -> StrokeSamples {
        StrokeSamples((0..<4).map { i in
            let t = CGFloat(i)
            return VectorSample(x: 20 + t * 30, y: 40 + t * 7,
                                pressure: 0.2 + t * 0.2,
                                deltaTime: 0.008 + t * 0.004,
                                tiltAltitude: 0.4 + t * 0.15,
                                tiltAzimuth: 0.9 + t * 0.5)
        }, channels: .captured)
    }

    /// The same geometry with position and pressure only — the record as it stood before this stage.
    private func pressureRun() -> StrokeSamples {
        StrokeSamples(fullRun().map { VectorSample(x: $0.x, y: $0.y, pressure: $0.pressure) },
                      channels: .pressureOnly)
    }

    private func sensors(_ samples: StrokeSamples, brushSize: CGFloat = 10,
                         totalArcWidths: CGFloat? = nil) -> StrokeSensors {
        StrokeSensors(samples: samples, path: StrokePath(points: samples.positions),
                      random: DabRandom(seed: 7), brushSize: brushSize, totalArcWidths: totalArcWidths)
    }

    // MARK: - The channel set

    /// The record width is **derived from the set**, not restated — BRUSH.md §5.5, and the reason
    /// `.quarterPixel` / `.float32` could be absorbed rather than kept beside it.
    func testTheRecordWidthIsDerivedFromTheChannelSetAndTheOldPrecisionFlagIsOneOfItsBits() {
        XCTAssertEqual(SampleChannelSet([]).bytesPerSample, 4, "two Int16 coordinates and nothing else")
        XCTAssertEqual(SampleChannelSet.pressureOnly.bytesPerSample, 5, "the record before this stage")
        XCTAssertEqual(SampleChannelSet.captured.bytesPerSample, 8, "BRUSH.md §5.1's eight against five")
        XCTAssertEqual(SampleChannelSet([.preciseCoordinates]).bytesPerSample, 8,
                       "two Float32 coordinates — the width choice the old `Precision` enum carried")
        XCTAssertEqual(SampleChannelSet.captured.union(.preciseCoordinates).bytesPerSample, 12)
        // Every bit is distinct, which is what stops two channels sharing a byte silently.
        XCTAssertEqual(Set(SampleChannel.allCases.map(\.bit.rawValue)).count, SampleChannel.allCases.count)
        XCTAssertFalse(SampleChannelSet.captured.contains(.preciseCoordinates),
                       "the coordinate width is not a per-point channel and must not be in `captured`")
    }

    /// **The case a fixed record cannot express**, and the whole reason the header is a mask: a run
    /// that carries *some* channels and not others, in both directions.
    func testARunCarryingSomeChannelsAndNotOthersRoundTripsThroughTheWireBothWays() throws {
        var partial = StrokeSamples(fullRun(), channels: [.pressure, .tiltAzimuth])
        XCTAssertEqual(partial.channels.bytesPerSample, 6)
        XCTAssertTrue(partial.carries(.tiltAzimuth))
        XCTAssertFalse(partial.carries(.deltaTime))
        XCTAssertFalse(partial.carries(.tiltAltitude))

        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(
            PackedSampleRun.self, from: try encoder.encode(PackedSampleRun(partial, about: .zero)))
        let back = decoded.samples

        XCTAssertEqual(back.channels, partial.channels, "the set survives the wire, not just the values")
        XCTAssertEqual(back.count, partial.count)
        for i in back.indices {
            XCTAssertEqual(back.positions[i].x, partial.positions[i].x, accuracy: PackedSampleRun.quantum)
            XCTAssertEqual(back.value(.pressure, at: i), partial.value(.pressure, at: i), accuracy: 1.0 / 255)
            XCTAssertEqual(back.value(.tiltAzimuth, at: i), partial.value(.tiltAzimuth, at: i),
                           accuracy: 2 * .pi / 256)
            XCTAssertEqual(back.value(.deltaTime, at: i), SampleChannel.deltaTime.neutral,
                           "a channel the run never carried reads as its neutral, not as zero bytes")
            XCTAssertEqual(back.value(.tiltAltitude, at: i), SampleChannel.tiltAltitude.neutral)
        }

        // And the other direction: adding a channel to a run that lacked it changes nothing else.
        partial.setChannel(.tiltAltitude, to: (0..<partial.count).map { 0.3 + CGFloat($0) * 0.1 })
        XCTAssertEqual(partial.channels.bytesPerSample, 7)
        let widened = PackedSampleRun(partial, about: .zero).samples
        for i in widened.indices {
            XCTAssertEqual(widened.value(.pressure, at: i), partial.value(.pressure, at: i), accuracy: 1.0 / 255,
                           "pressure moved when a channel was added beside it — the byte offsets are wrong")
        }
    }

    /// **One byte a run, inside the blob**, so the run is self-describing and the wire is two keys.
    func testTheChannelSetIsOneByteInsideTheBlobAndTheWireIsStillTwoKeys() throws {
        let run = fullRun()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try encoder.encode(PackedSampleRun(run, about: .zero))) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["o", "d"], "two keys, always — the mode token is gone")

        let blob = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(json["d"] as? String)))
        XCTAssertEqual(blob.count, 1 + run.count * SampleChannelSet.captured.bytesPerSample,
                       "one header byte for the run, then the samples")
        XCTAssertEqual(blob.first, SampleChannelSet.captured.rawValue)
    }

    /// A blob whose header names a set this build does not know throws rather than mis-reading the
    /// bytes after it. The malformed-input discipline `PackedSampleRun`'s coder already had.
    func testAnUnknownChannelSetThrowsRatherThanDecodingTheBytesWrong() {
        let blob = Data([0xFF]) + Data(repeating: 0, count: 24)
        let json = #"{"o":[0,0],"d":"\#(blob.base64EncodedString())"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(PackedSampleRun.self,
                                                      from: Data(json.utf8)))
    }

    /// **Every channel's neutral survives its own quantisation exactly** — not nearly. It is what lets
    /// an all-neutral channel be dropped with no change to a single pixel, and an inexact one would
    /// make `compacted()` a lossy operation dressed as a free one.
    func testEveryChannelsNeutralSurvivesQuantisationExactly() {
        for channel in SampleChannel.allCases {
            XCTAssertEqual(channel.value(of: channel.quantised(channel.neutral)), channel.neutral,
                           "\(channel)'s neutral does not round-trip")
        }
        XCTAssertEqual(SampleChannel.pressure.neutral, 1)
        XCTAssertEqual(SampleChannel.tiltAltitude.neutral, .pi / 2, "upright")
        XCTAssertEqual(SampleChannel.tiltAzimuth.neutral, 0)
        XCTAssertEqual(SampleChannel.deltaTime.neutral, 0)
    }

    /// The widths BRUSH.md §5.1 settles, stated as the resolution an artist would see.
    func testTheChannelResolutionsAreTheOnesTheOwnerRuledSufficient() {
        let altitudeStep = SampleChannel.tiltAltitude.value(of: 1) - SampleChannel.tiltAltitude.value(of: 0)
        XCTAssertEqual(altitudeStep * 180 / .pi, 0.35, accuracy: 0.01, "0.35° a step over 0…π/2")
        let azimuthStep = SampleChannel.tiltAzimuth.value(of: 1) - SampleChannel.tiltAzimuth.value(of: 0)
        XCTAssertEqual(azimuthStep * 180 / .pi, 1.40625, accuracy: 1e-6, "1.4° a step over a full turn")
        XCTAssertEqual(SampleChannel.deltaTime.value(of: 255), 0.1275, accuracy: 1e-9,
                       "Δt saturates at 127.5 ms, which is slower than 8 Hz")
    }

    /// Azimuth **wraps** rather than clamping, because it is an angle: 0 and 2π are one byte, not two,
    /// and a nib turned past a full circle reads the same as one that was not.
    func testAzimuthWrapsRatherThanSaturatingAtTheEndsOfItsRange() {
        let channel = SampleChannel.tiltAzimuth
        XCTAssertEqual(channel.quantised(0), channel.quantised(2 * .pi))
        XCTAssertEqual(channel.quantised(0.4), channel.quantised(0.4 + 4 * .pi))
        XCTAssertEqual(channel.value(of: channel.quantised(-0.3)),
                       channel.value(of: channel.quantised(2 * .pi - 0.3)),
                       "a negative angle folds into the same cell as its positive twin")
    }

    /// **An all-neutral channel is dropped, and nothing about the run changes.** This is the common
    /// case, not an optimisation: a finger reports π/2 and 0 for tilt on every sample it ever
    /// produces, so a finger-drawn stroke stores six bytes a point rather than eight.
    func testAChannelOfNothingButNeutralsIsDroppedAndReadsExactlyTheSameAfterwards() {
        var finger = StrokeSamples(channels: .captured)
        for i in 0..<6 {
            finger.append(VectorSample(x: CGFloat(i) * 9, y: 30,
                                       pressure: SampleChannel.pressure.neutral,
                                       deltaTime: 0.008,
                                       tiltAltitude: SampleChannel.tiltAltitude.neutral,
                                       tiltAzimuth: SampleChannel.tiltAzimuth.neutral))
        }
        let compact = finger.compacted()
        XCTAssertEqual(compact.channels, [.deltaTime],
                       "tilt and pressure were all neutral; Δt was not, and stays")
        XCTAssertEqual(compact.channels.bytesPerSample, 5)
        XCTAssertEqual(PackedSampleRun(compact, about: .zero).bytes.count,
                       6 * 5, "and the bytes really did shrink")
        for i in compact.indices {
            XCTAssertEqual(compact[i], finger[i], "the sample values are unchanged by dropping the channel")
        }
    }

    // MARK: - Tilt, and the space azimuth lives in

    /// **An affine turns the nib with the ink and leaves every other channel alone** — BRUSH.md §2.7's
    /// conversion, at the one place the app performs it.
    func testAnAffineTurnsTheAzimuthWithTheInkAndCarriesEveryOtherChannelUntouched() {
        let run = fullRun()
        let theta: CGFloat = 0.7
        let turned = run.transformed(by: CGAffineTransform(rotationAngle: theta))

        for i in run.indices {
            assertSameDirection(turned.value(.tiltAzimuth, at: i),
                                run.value(.tiltAzimuth, at: i) + theta,
                                accuracy: 1e-12, "the nib did not turn with the ink at \(i)")
            XCTAssertEqual(turned.value(.pressure, at: i), run.value(.pressure, at: i))
            XCTAssertEqual(turned.value(.deltaTime, at: i), run.value(.deltaTime, at: i))
            XCTAssertEqual(turned.value(.tiltAltitude, at: i), run.value(.tiltAltitude, at: i),
                           "altitude is a lean, not a compass bearing: a canvas turn does not change it")
            XCTAssertEqual(turned.positions[i].x,
                           run.positions[i].x * cos(theta) - run.positions[i].y * sin(theta),
                           accuracy: 1e-9)
        }
    }

    /// A translation or a uniform scale has no rotation in it, so the nib must not move — the case a
    /// naive `atan2(b, a)` would also get right and a wrong sign convention would not.
    func testATranslationOrAUniformScaleLeavesTheNibPointingWhereItWas() {
        let run = fullRun()
        for t in [CGAffineTransform(translationX: 400, y: -30), CGAffineTransform(scaleX: 3.25, y: 3.25)] {
            let moved = run.transformed(by: t)
            for i in run.indices {
                XCTAssertEqual(moved.value(.tiltAzimuth, at: i), run.value(.tiltAzimuth, at: i),
                               "a \(t) turned the nib")
            }
        }
    }

    /// **The round trip through a layer's own transform** — canvas space in, layer space stored, canvas
    /// space back out. The composition of the two rotations has to be the identity on the angle, or a
    /// stroke drawn on a turned layer would render with its nib pointing somewhere the pen never was.
    func testAzimuthSurvivesTheCanvasToLayerRoundTripThatEveryStoredStrokeMakes() throws {
        let canvas = VectorCanvas(size: CGSize(width: 400, height: 400))
        canvas.setTransform(CGAffineTransform(rotationAngle: 0.9).translatedBy(x: 25, y: -10))
        let drawn = fullRun()
        canvas.addStroke(canvasSpaceStroke: VectorStroke(
            brush: BrushLibrary.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
            size: 8, opacity: 1, samples: drawn))

        let stored = try XCTUnwrap(canvas.strokes.first).samples
        XCTAssertTrue(stored.carries(.tiltAzimuth), "the layer transform must not drop the channel")
        for i in stored.indices {
            assertSameDirection(stored.value(.tiltAzimuth, at: i),
                                drawn.value(.tiltAzimuth, at: i) - 0.9,
                                "stored azimuth is not in the layer's own space")
        }

        let backInCanvasSpace = stored.transformed(by: canvas.transform)
        for i in stored.indices {
            assertSameDirection(backInCanvasSpace.value(.tiltAzimuth, at: i),
                                drawn.value(.tiltAzimuth, at: i), "the round trip moved the nib")
        }
    }

    /// A lasso resize, a canvas resize and a whole-layer transform all reach
    /// `VectorCanvas.mapping(_:throughSimilarity:)`, and a rotation there turns the nib with the ink —
    /// which is what a physical nib does against paper when you turn the paper.
    func testALassoRotationTurnsTheStoredNibWithTheInk() throws {
        let stroke = VectorStroke(brush: BrushLibrary.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 8, opacity: 1, samples: fullRun())
        let turned = VectorCanvas.mapping(.stroke(stroke), throughSimilarity:
            CGAffineTransform(rotationAngle: -0.45))
        let moved = try XCTUnwrap(turned.stroke).samples
        for i in moved.indices {
            assertSameDirection(moved.value(.tiltAzimuth, at: i),
                                stroke.samples.value(.tiltAzimuth, at: i) - 0.45,
                                "a lasso rotation did not turn the nib with the ink")
        }
    }

    // MARK: - Δt, and velocity as a sensor

    /// **The stored intervals are between *stored* points, not between input samples.** `StrokePathFit`
    /// drops most of what the digitiser delivers, so a knot has to absorb the time the dropped samples
    /// took; without that a refitted stroke's velocity would read as the digitiser's rate whatever the
    /// hand was doing.
    func testTheStoredIntervalsSumToTheStrokesOwnDurationRatherThanToOneSamplePeriod() {
        var fit = StrokePathFit()
        var stored = StrokeSamples(channels: .captured)
        let period: CGFloat = 1.0 / 240
        let count = 240
        for i in 0..<count {
            // A straight, slow line: the fit throws most of this away.
            let sample = VectorSample(x: 100 + CGFloat(i) * 0.4, y: 200,
                                      pressure: 1, deltaTime: i == 0 ? 0 : period,
                                      tiltAltitude: .pi / 2, tiltAzimuth: 0)
            for knot in fit.offer(sample) { stored.append(knot) }
        }
        for knot in fit.finish(nil) { stored.append(knot) }

        XCTAssertLessThan(stored.count, count / 4, "Setup: the fit must actually be dropping samples")
        let total = stored.indices.reduce(CGFloat(0)) { $0 + stored.value(.deltaTime, at: $1) }
        XCTAssertEqual(total, CGFloat(count - 1) * period, accuracy: 1e-9,
                       "the intervals of the dropped samples were lost rather than absorbed")
        XCTAssertGreaterThan(stored.value(.deltaTime, at: 1), period * 2,
                             "a stored interval must be longer than one input period, or nothing was absorbed")
    }

    /// **A cut piece reads the same speed the uncut stroke read at the same place.** Δt is an interval
    /// rather than a reading (`SampleChannel.isCumulative`), so a boundary inserted part-way through a
    /// segment has to take its share and leave the rest.
    func testACutPieceReadsTheSameVelocityAsTheUncutStrokeAtTheSamePlace() {
        // Constant speed: 15 pt every 50 ms — 300 pt/s, which at a 10 pt brush is 30 widths/s against
        // `referenceSpeed`'s 40. **The fixture has to sit off both ends of the clamp**: at the pace a
        // first draft used, both the right answer and the wrong one saturated at 1, and the test
        // agreed with a mutation that broke the very thing it is about.
        var run = StrokeSamples(channels: [.deltaTime])
        for i in 0..<6 {
            run.append(VectorSample(x: CGFloat(i) * 15, y: 0, deltaTime: i == 0 ? 0 : 0.05))
        }
        let whole = sensors(run)
        let reference = whole.value(of: .velocity, at: DabSite(parameter: 2.5, arcWidths: 0))
        XCTAssertGreaterThan(reference, 0, "Setup: the fixture must actually be moving")
        XCTAssertLessThan(reference, 1,
                          "Setup: and not fast enough to clamp, or every answer here is 1 and equal")

        let pieces = StrokeGeometry.splitStroke(run, removing: [1.4...1.6])
        guard let tail = pieces.last, tail.count > 2 else { return XCTFail("expected a tail piece") }
        let tailRun = run.replacingSamples(tail)
        // The tail begins at parameter 1.6 of the original, so its own parameter 1 is the original's
        // 2.0 and its segment 1→2 is the original's 2→3 — the segment `reference` was read from.
        let cut = sensors(tailRun).value(of: .velocity, at: DabSite(parameter: 1.5, arcWidths: 0))
        XCTAssertEqual(cut, reference, accuracy: 1e-9,
                       "the cut changed how fast the pen was going through ink it did not touch")

        // And the segment that *was* cut: the boundary took 0.6 of its interval and left 0.4 for the
        // sample after it, so the shorter segment still reads the same speed. This is the assertion
        // an interval channel treated as a reading fails.
        let firstSegment = sensors(tailRun).value(of: .velocity, at: DabSite(parameter: 0.5, arcWidths: 0))
        XCTAssertEqual(firstSegment, reference, accuracy: 1e-9,
                       "the segment the cut shortened reads slower than the pen was actually moving")
    }

    /// Velocity is in **brush widths** per second, which is §4.1's unit and the one that makes a
    /// uniform scale of a stroke change nothing about how it looks.
    func testVelocityIsMeasuredInBrushWidthsSoAUniformScaleDoesNotChangeIt() {
        var run = StrokeSamples(channels: [.deltaTime])
        for i in 0..<5 { run.append(VectorSample(x: CGFloat(i) * 24, y: 0, deltaTime: i == 0 ? 0 : 0.03)) }
        let k: CGFloat = 4.5
        let plain = sensors(run, brushSize: 12).value(of: .velocity, at: DabSite(parameter: 1.5, arcWidths: 0))
        let scaled = sensors(run.transformed(by: CGAffineTransform(scaleX: k, y: k)), brushSize: 12 * k)
            .value(of: .velocity, at: DabSite(parameter: 1.5, arcWidths: 0))
        XCTAssertGreaterThan(plain, 0)
        XCTAssertEqual(scaled, plain, accuracy: 1e-12)
    }

    /// A run with **no** Δt answers velocity's neutral rather than dividing by a stored zero. The
    /// funnel reads the channel's *presence*, because "no interval recorded" and "no time passed" are
    /// different facts.
    func testAStrokeWithNoIntervalChannelReadsAsStillRatherThanInfinitelyFast() {
        let v = sensors(pressureRun()).value(of: .velocity, at: DabSite(parameter: 1.5, arcWidths: 0))
        XCTAssertEqual(v, BrushInput.velocity.neutral)
        XCTAssertTrue(v.isFinite)
    }

    // MARK: - The funnel and its neutral

    /// **Every channel-backed input answers its defined neutral when the stroke carries no data for
    /// it** — BRUSH.md §5.5.
    func testEveryChannelBackedInputAnswersItsNeutralWhenTheRunCarriesNothingForIt() {
        let bare = StrokeSamples(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)])
        let funnel = sensors(bare)
        for input: BrushInput in [.pressure, .tiltAngle, .tiltDirection, .velocity] {
            XCTAssertNotNil(input.backingChannel, "\(input) should be channel-backed")
            XCTAssertEqual(funnel.value(of: input, at: DabSite(parameter: 1.2, arcWidths: 3)),
                           input.neutral, "\(input) did not answer its neutral")
        }
        XCTAssertEqual(BrushInput.pressure.neutral, 1, "full press — the finger's own reading")
        XCTAssertEqual(BrushInput.tiltAngle.neutral, 0, "upright — no lean at all")
        XCTAssertEqual(BrushInput.tiltDirection.neutral, 0, "pointing nowhere")
        XCTAssertEqual(BrushInput.taper.neutral, 1, "no taper effect where the walk cannot know the length")
    }

    /// **The neutral is the hardware's own answer for a finger**, and that is a claim about the world
    /// rather than a definition: a stroke that stores what `StrokeInput` reports for a non-Pencil touch
    /// must resolve exactly as one that stores nothing at all. It would go red if any neutral, any
    /// quantisation or any of the funnel's normalisations disagreed with `StrokeInput`.
    func testAStrokeStoringTheFingersOwnReadingsResolvesExactlyAsOneStoringNothing() {
        // The values `StrokeInput.init(touch:in:)` assigns for a non-Pencil touch, spelled out.
        let fingerPressure: CGFloat = 1, fingerAltitude: CGFloat = .pi / 2, fingerAzimuth: CGFloat = 0
        var stored = StrokeSamples(channels: [.pressure, .tiltAltitude, .tiltAzimuth])
        var bare = StrokeSamples(points: [])
        for i in 0..<4 {
            let p = CGPoint(x: CGFloat(i) * 25, y: 60)
            stored.append(VectorSample(x: p.x, y: p.y, pressure: fingerPressure,
                                       tiltAltitude: fingerAltitude, tiltAzimuth: fingerAzimuth))
            bare.append(VectorSample(x: p.x, y: p.y))
        }
        // Through the packer as well as in memory, so a byte that does not round-trip is caught.
        let viaWire = PackedSampleRun(stored, about: .zero).samples
        for input: BrushInput in [.pressure, .tiltAngle, .tiltDirection] {
            for parameter in stride(from: CGFloat(0), through: 3, by: 0.37) {
                let site = DabSite(parameter: parameter, arcWidths: parameter)
                XCTAssertEqual(sensors(viaWire).value(of: input, at: site),
                               sensors(bare).value(of: input, at: site),
                               "\(input) at \(parameter): a finger's stored reading is not the neutral")
            }
        }
    }

    /// **The guarantee BRUSH.md §5.5 states, at the dabs**: a brush reading a channel the stroke does
    /// not carry draws exactly what the same brush with that modulation removed draws.
    ///
    /// Pressure is the modulation that exists today, and a run with no pressure channel is the ordinary
    /// case rather than a contrived one — `compacted()` produces one from any stroke drawn at a
    /// constant full press, and `StrokeSamples(points:)` is what the intersection eraser probes with.
    ///
    /// It can go red: a funnel that answered `0` for a missing channel would make the first render a
    /// tapered hairline against the second's full-width line. `BrushDynamics.sizeFraction(forPressure:
    /// 1)` is exactly 1 for every `sizePressure`, which is why "the modulation removed" and "the
    /// modulation reading the neutral" have the same answer and the comparison is at zero tolerance.
    func testABrushReadingAChannelTheStrokeDoesNotCarryDrawsWhatTheSameBrushWithoutThatModulationDraws() {
        let bare = StrokeSamples(points: (0..<6).map { CGPoint(x: 20 + CGFloat($0) * 18, y: 60) })
        XCTAssertFalse(bare.carries(.pressure), "Setup: this run must genuinely lack the channel")

        var reading = BrushLibrary.hardRound
        reading.dynamics = BrushDynamics(sizePressure: 1, opacityPressure: 1, minSizeFraction: 0.1)
        var removed = reading
        removed.dynamics = .fixed

        let withModulation = BrushStamper.bake(samples: bare, brush: reading, color: .black,
                                               brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 11))
        let withoutModulation = BrushStamper.bake(samples: bare, brush: removed, color: .black,
                                                  brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 11))
        XCTAssertGreaterThan(withModulation.count, 10, "Setup: there are dabs to compare")
        XCTAssertEqual(withModulation, withoutModulation,
                       "a missing channel changed the ink — the funnel is not answering the neutral")

        // And at the pixels, which is what the artist sees.
        XCTAssertEqual(Self.rendered(bare, brush: reading), Self.rendered(bare, brush: removed),
                       "the two renders differ by at least one byte")

        // The same fixture with a *non*-neutral pressure must differ, or the comparison above is
        // measuring a brush that ignores pressure rather than a funnel that answers the neutral.
        let light = StrokeSamples(bare.map { VectorSample(x: $0.x, y: $0.y, pressure: 0.2) },
                                  channels: .pressureOnly)
        XCTAssertNotEqual(BrushStamper.bake(samples: light, brush: reading, color: .black, brushSize: 20,
                                            brushOpacity: 1, random: DabRandom(seed: 11)),
                          withoutModulation,
                          "control: a stroke that does carry pressure must be able to differ")
    }

    /// The same guarantee for **tilt**, which has no modulation yet and so is pinned where it can still
    /// go wrong: carrying the channels must not disturb the ink drawn from the ones beside them. An
    /// off-by-one in the packer's per-channel offsets breaks this and nothing else would catch it.
    func testCarryingTiltChangesNoPixelOfAStrokeDrawnWithABrushThatDoesNotReadIt() {
        var withTilt = StrokeSamples(channels: .captured)
        var without = StrokeSamples(channels: .pressureOnly)
        for i in 0..<7 {
            let p = CGPoint(x: 18 + CGFloat(i) * 14, y: 55)
            let pressure = 0.3 + CGFloat(i) * 0.1
            withTilt.append(VectorSample(x: p.x, y: p.y, pressure: pressure,
                                         deltaTime: 0.01, tiltAltitude: 0.31, tiltAzimuth: 4.2))
            without.append(VectorSample(x: p.x, y: p.y, pressure: pressure))
        }
        let brush = BrushLibrary.hardRound
        XCTAssertEqual(Self.rendered(PackedSampleRun(withTilt, about: .zero).samples, brush: brush),
                       Self.rendered(PackedSampleRun(without, about: .zero).samples, brush: brush),
                       "tilt bytes leaked into the pressure the brush reads")
    }

    /// The funnel's derived inputs, which have no channel to be missing and so no neutral case: they
    /// are pinned against the geometry they are derived from.
    func testTheDerivedInputsReadTheWalkRatherThanAStoredChannel() {
        let straightUp = StrokeSamples(points: [CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 90)])
        // +y in canvas space, so a quarter turn: 0.25 of a full turn.
        XCTAssertEqual(sensors(straightUp).value(of: .direction, at: DabSite(parameter: 0.5, arcWidths: 0)),
                       0.25, accuracy: 1e-9)

        let run = pressureRun()
        let tapered = sensors(run, totalArcWidths: 10)
        XCTAssertEqual(tapered.value(of: .taper, at: DabSite(parameter: 0, arcWidths: 0)), 0, accuracy: 1e-12)
        XCTAssertEqual(tapered.value(of: .taper, at: DabSite(parameter: 0, arcWidths: 5)), 1, accuracy: 1e-12)
        XCTAssertEqual(tapered.value(of: .taper, at: DabSite(parameter: 0, arcWidths: 10)), 0, accuracy: 1e-12)
        XCTAssertEqual(sensors(run).value(of: .taper, at: DabSite(parameter: 0, arcWidths: 5)),
                       BrushInput.taper.neutral,
                       "a walk that cannot know the total answers the neutral rather than guessing")

        // `random` is BRUSH.md §4's field, reached through the funnel like everything else.
        let field = DabRandom(seed: 7)
        XCTAssertEqual(sensors(run).value(of: .random(.scatterAngle, wavelength: 0),
                                          at: DabSite(parameter: 0, arcWidths: 12.5)),
                       field.unit(.scatterAngle, at: 12.5))
    }

    // MARK: - Struct-of-arrays

    /// **An absent channel is an empty array and costs nothing** — BRUSH.md §5.5's words, checked
    /// against the storage rather than against the doc comment.
    func testAnAbsentChannelIsAnEmptyArrayAndAPresentOneIsOnePerSample() {
        let bare = StrokeSamples(points: [.zero, CGPoint(x: 5, y: 5)])
        XCTAssertTrue(bare.pressures.isEmpty)
        XCTAssertTrue(bare.tiltAzimuths.isEmpty)
        XCTAssertEqual(bare.storedChannels, [])

        let full = fullRun()
        XCTAssertEqual(full.storedChannels, SampleChannel.allCases)
        for channel in SampleChannel.allCases {
            XCTAssertEqual(full.storedValues(channel).count, full.count, "\(channel) is not one per sample")
        }
    }

    /// The sample view is **lossless**, which is what lets the geometry layer slice, interpolate and
    /// bisect runs without knowing any channel exists.
    func testASliceThroughTheSampleViewCarriesEveryChannel() {
        let run = fullRun()
        let sliced = run.replacingSamples(run.dropFirst())
        XCTAssertEqual(sliced.channels, run.channels)
        for i in sliced.indices {
            XCTAssertEqual(sliced[i], run[i + 1], "a channel was dropped by the slice")
        }
    }

    /// Interpolation is **per channel by its own rule**: an angle takes the short way round, an
    /// interval is divided, a reading is linear. The wrap case is the one a single linear rule gets
    /// visibly wrong — a nib at 359° and one at 1° would sweep through 180° between them.
    func testAnAngleChannelInterpolatesTheShortWayRoundBetweenTwoStoredPoints() {
        let a = VectorSample(x: 0, y: 0, pressure: 0.2, deltaTime: 0.01, tiltAzimuth: 0.05)
        let b = VectorSample(x: 10, y: 0, pressure: 0.8, deltaTime: 0.04,
                             tiltAzimuth: 2 * .pi - 0.05)
        let mid = VectorSample.lerp(a, b, 0.5)
        XCTAssertEqual(SampleChannel.wrappedAngle(mid.tiltAzimuth), 0, accuracy: 1e-9,
                       "the nib swung the long way round: \(mid.tiltAzimuth)")
        XCTAssertEqual(mid.pressure, 0.5, accuracy: 1e-12, "a reading is linear")
        XCTAssertEqual(mid.deltaTime, 0.02, accuracy: 1e-12, "an interval is divided, not averaged")
    }

    // MARK: - What the record costs

    /// BRUSH.md §5.1 predicts **eight bytes a point against five**. Measured on the wire as well as in
    /// the payload, because base64 and JSON escaping are what the file actually pays.
    func testTheRecordIsEightBytesAPointWithEveryChannelAndFiveWithoutAnyTiltOrTiming() throws {
        let count = 1000
        var full = StrokeSamples(channels: .captured)
        var old = StrokeSamples(channels: .pressureOnly)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return CGFloat(Double(seed % 1_000_000_000) / 1_000_000_000)
        }
        for i in 0..<count {
            let x = CGFloat(i % 2048) + next(), y = CGFloat(i % 1024) + next()
            full.append(VectorSample(x: x, y: y, pressure: next(), deltaTime: next() * 0.05,
                                     tiltAltitude: next() * .pi / 2, tiltAzimuth: next() * 2 * .pi))
            old.append(VectorSample(x: x, y: y, pressure: next()))
        }
        XCTAssertEqual(PackedSampleRun(full, about: .zero).bytes.count, count * 8)
        XCTAssertEqual(PackedSampleRun(old, about: .zero).bytes.count, count * 5)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let fullWire = Double(try encoder.encode(PackedSampleRun(full, about: .zero)).count) / Double(count)
        let oldWire = Double(try encoder.encode(PackedSampleRun(old, about: .zero)).count) / Double(count)
        XCTAssertLessThan(fullWire, 12.0, "the full record costs \(fullWire) B a sample on the wire")
        XCTAssertLessThan(oldWire, 8.0, "and the old one \(oldWire) B")
        XCTAssertLessThan(fullWire / oldWire, 1.7,
                          "eight bytes against five is 1.6x of payload, and base64 does not change that")
    }

    // MARK: - Helpers

    /// Two angles compared as **angles** — by the shortest arc between them, not by their spelling.
    /// A wrap-boundary equality is a test of the representation rather than of the nib: `wrappedAngle`
    /// lands one rounding short of zero and answers 2π, which is the same direction.
    private func assertSameDirection(_ actual: CGFloat, _ expected: CGFloat,
                                     accuracy: CGFloat = 1e-9, _ message: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        var delta = (actual - expected).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        XCTAssertEqual(delta, 0, accuracy: accuracy,
                       "\(message) — \(actual) against \(expected)", file: file, line: line)
    }

    /// The bytes a run actually paints, so "renders identically" is a statement about pixels.
    private static func rendered(_ samples: StrokeSamples, brush: Brush) -> Data {
        let texture = RasterLayerTexture(size: CGSize(width: 140, height: 110))
        BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                 brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 11))
        guard let cg = texture.renderToUIImage().cgImage,
              let data = cg.dataProvider?.data as Data? else { return Data() }
        return data
    }
}
