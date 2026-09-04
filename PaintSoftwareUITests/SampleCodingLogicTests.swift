import XCTest
import UIKit

/// Pure-logic tests for **TODO item (8)** — the fixed-point sample coordinate.
///
/// A stored sample is now a signed 16-bit quarter-pixel offset from a stored origin plus 8 bits of
/// pressure, five bytes, base64'd into one JSON string (`PackedSampleRun`). In memory nothing changed:
/// `VectorSample` is still three `CGFloat`, and these tests are as much about pinning that as about
/// the codec.
///
/// **The one that earns its keep is `testInkNearTheEdgeOfAWideCanvasSurvivesASaveAndReload`.** The
/// quantisation origin is the centre of the canvas, and the only channel `Codable` offers for that is
/// `JSONEncoder.userInfo` — which a call site can forget. `PackedSampleRun` writes the origin it was
/// given into the payload, so a forgotten origin can never produce a *wrong* coordinate on the way
/// back; what it does produce is a smaller addressable range, and that is invisible on a 2048-point
/// canvas and fatal on a 12,000-point one. So the guard is a real save and reload of ink near the far
/// edge of a wide canvas, which fails loudly if `ProjectStore` ever stops passing the origin. A source
/// scan would have been cheaper and would not have tested the thing.
///
/// The second-most useful is `testEncodingIsAFixedPoint`. The format is lossy exactly once: quantising
/// a value that is already on the grid must return the same bytes, or every save of an untouched
/// project would walk the artwork a quarter pixel at a time.
///
/// **TODO item (14) adds a second layout to the same type** — float32 x, float32 y, 8 bits of
/// pressure, nine bytes — declared on the wire by a `p` key that is written *only* in that mode. Its
/// tests are the last section, and the one that earns its keep there is
/// `testShrinkingToTwoPercentBeforeStoringCostsPointsOnTheGridAndNothingAtFullPrecision`: the whole
/// feature exists because the grid is a fixed size in canvas points, so a stroke shrunk before a save
/// has fewer usable bits and whatever it lost is multiplied by the scale-up afterwards.
@MainActor
final class SampleCodingLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-coding-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - The field itself

    /// The numbers item (8) is specified in, derived rather than restated. `Int16` at a quarter of a
    /// point reaches **-8192.0 … +8191.75** — a span of 16,383.75, which is why
    /// `CanvasManager.maxCanvasExtent` is 16383 and not 16384.
    func testTheStorableRangeIsTheSignedSixteenBitQuarterPixelField() {
        XCTAssertEqual(PackedSampleRun.quantum, 0.25, "the owner's quarter-pixel rule")
        XCTAssertEqual(PackedSampleRun.bytesPerSample, 5, "16 + 16 + 8 bits")
        XCTAssertEqual(PackedSampleRun.representable.lowerBound, -8192.0)
        XCTAssertEqual(PackedSampleRun.representable.upperBound, 8191.75)
        XCTAssertEqual(PackedSampleRun.representable.upperBound - PackedSampleRun.representable.lowerBound,
                       16383.75, "a span of 16383.75, not 16384 — the whole reason for maxCanvasExtent's value")
    }

    /// The bound above and the canvas bound are the same decision, so they are asserted together:
    /// a canvas of `maxCanvasExtent` encodes both its edges, and one point wider does not.
    func testAMaximumCanvasEncodesBothEdgesAndOnePointWiderDoesNot() {
        func clamps(atExtent extent: CGFloat) -> Int {
            let origin = CGPoint(x: extent / 2, y: extent / 2)
            return PackedSampleRun([VectorSample(x: 0, y: 0, pressure: 1),
                                    VectorSample(x: extent, y: extent, pressure: 1)],
                                   about: origin).clampedCount
        }
        XCTAssertEqual(clamps(atExtent: CanvasManager.maxCanvasExtent), 0,
                       "the largest permitted canvas must encode without losing a quarter pixel of artwork")
        XCTAssertEqual(clamps(atExtent: CanvasManager.maxCanvasExtent + 1), 1,
                       "one point wider saturates the far corner — this is why the bound is what it is")
    }

    /// Half a quantum is the worst a coordinate can be out, and half a step the worst pressure can be.
    func testASampleRunRoundTripsWithinHalfAQuantum() {
        let origin = CGPoint(x: 1024, y: 512)
        let original = Self.realisticRun(count: 600)
        let decoded = PackedSampleRun(original, about: origin).samples

        XCTAssertEqual(decoded.count, original.count)
        for (before, after) in zip(original, decoded) {
            XCTAssertEqual(after.x, before.x, accuracy: PackedSampleRun.quantum / 2)
            XCTAssertEqual(after.y, before.y, accuracy: PackedSampleRun.quantum / 2)
            XCTAssertEqual(after.pressure, before.pressure, accuracy: 1.0 / 510)
        }
    }

    /// Five bytes a sample, and no more — the claim the whole item rests on.
    func testARunIsFiveBytesASample() {
        let run = PackedSampleRun(Self.realisticRun(count: 200), about: .zero)
        XCTAssertEqual(run.bytes.count, 200 * PackedSampleRun.bytesPerSample)
        XCTAssertTrue(PackedSampleRun([], about: .zero).bytes.isEmpty, "an empty run costs nothing")
    }

    /// **Quantising an already-quantised value must be the identity.** Otherwise every save nudges the
    /// artwork, and a project opened and closed a hundred times is a hundred quarter-pixels adrift.
    /// The origin is snapped to the grid on the way in precisely so this holds exactly rather than
    /// nearly; `origin` here is deliberately a half-point value, which is what an odd canvas produces.
    func testEncodingIsAFixedPoint() throws {
        let origin = CGPoint(x: 1023.5, y: 511.5)
        let first = PackedSampleRun(Self.realisticRun(count: 300), about: origin)
        let second = PackedSampleRun(first.samples, about: origin)
        XCTAssertEqual(second.bytes, first.bytes, "re-encoding a decoded run must produce the same bytes")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(first)
        let decoded = try JSONDecoder().decode(PackedSampleRun.self, from: data)
        XCTAssertEqual(decoded.samples, first.samples, "the run survives JSON unchanged")
        XCTAssertEqual(try encoder.encode(decoded), data, "and the JSON is itself a fixed point")
    }

    /// The owner's ruling: *"If you draw outside the 16k, it should not wrap but rather clamp."*
    /// Unclamped, `Int16` truncation would put this ink on the **opposite** side of the canvas —
    /// BUGS.md's unclamped zoom makes a ~1.6-million-point coordinate reachable from a real drag, so
    /// this is the behaviour that keeps that bug boring instead of baffling.
    func testACoordinateBeyondTheFieldSaturatesRatherThanWrapping() {
        let origin = CGPoint(x: 1024, y: 512)
        let far = VectorSample(x: 1_638_400, y: -1_638_400, pressure: 1)
        let run = PackedSampleRun([far], about: origin)
        let back = try! XCTUnwrap(run.samples.first)

        XCTAssertEqual(run.clampedCount, 1, "the loss is counted, so the save can say it happened")
        XCTAssertEqual(back.x, origin.x + PackedSampleRun.representable.upperBound,
                       "a coordinate past the top of the field saturates at the top of the field")
        XCTAssertEqual(back.y, origin.y + PackedSampleRun.representable.lowerBound,
                       "…and past the bottom, at the bottom")
        XCTAssertGreaterThan(back.x, origin.x, "it must NOT reappear on the far side — that is wrapping")
        XCTAssertLessThan(back.y, origin.y, "…in either direction")
    }

    /// A NaN is a defect upstream in *either* layout, so both count it. float32 has no clamp to notice
    /// it with — `clampedCount` stays 0 there, correctly — and going quiet about a lost coordinate on
    /// precisely the strokes the artist asked to keep exactly is the worst place in the codec to be
    /// quiet, which is why `nonFiniteCount` exists beside it rather than being folded into it.
    func testANonFiniteCoordinateIsCountedInBothLayouts() {
        let bad = [VectorSample(x: .nan, y: 0, pressure: 1), VectorSample(x: 1, y: 2, pressure: 1)]

        let grid = PackedSampleRun(bad, about: .zero)
        XCTAssertEqual(grid.nonFiniteCount, 1)
        XCTAssertEqual(grid.clampedCount, 1, "the grid notices it as a saturation as well, and always did")

        let precise = PackedSampleRun(bad, about: .zero, precision: .float32)
        XCTAssertEqual(precise.nonFiniteCount, 1, "float32 must still say a coordinate was lost")
        XCTAssertEqual(precise.clampedCount, 0, "…but not by calling it a clamp, which it has no bound for")
        XCTAssertEqual(precise.samples.first?.x, 0, "the lost coordinate lands at the origin, not in a trap")
        XCTAssertEqual(precise.samples.last?.x, 1, "and the sample beside it is untouched")
    }

    /// A defect upstream must not take the app down inside a save. There is no legitimate way to draw
    /// a NaN, which is exactly why the encoder has to survive one.
    func testANonFiniteCoordinateIsCountedRatherThanTrapping() {
        let run = PackedSampleRun([VectorSample(x: .nan, y: .infinity, pressure: .nan)], about: .zero)
        let back = try! XCTUnwrap(run.samples.first)
        XCTAssertEqual(run.clampedCount, 1)
        XCTAssertEqual(back.x, 0, "a non-finite coordinate lands at the origin")
        XCTAssertEqual(back.pressure, 0)
    }

    /// A truncated, mis-aligned or non-base64 blob is a damaged file, and `VectorCanvasData`'s
    /// per-element decode can only classify it if this throws instead of trapping — `Lattice`'s own
    /// persistence extension makes the same argument for the same reason.
    func testAMalformedRunThrowsRatherThanTrapping() {
        for bad in [#"{"o":[0,0],"d":"AAAA"}"#,          // four bytes: not a whole number of samples
                    #"{"o":[0],"d":""}"#,                 // an origin is two numbers
                    #"{"o":[0,0],"d":"!!!!"}"#,           // not base64
                    #"{"o":[0,0]}"#] {                    // no run at all
            XCTAssertThrowsError(try JSONDecoder().decode(PackedSampleRun.self, from: Data(bad.utf8)),
                                 "\(bad) must be reported, not accepted")
        }
    }

    // MARK: - What a stroke writes

    /// The wire shape, asserted on a real stroke rather than on the codec in isolation: `samples` is
    /// still the key, and its value is now the packed object.
    func testAStrokeWritesItsSamplesPackedAndNotAsAnArrayOfObjects() throws {
        let encoder = JSONEncoder()
        encoder.userInfo[.sampleQuantisationOrigin] = CGPoint(x: 64, y: 64)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try encoder.encode(Self.stroke()), options: []) as? [String: Any])

        let samples = try XCTUnwrap(object["samples"] as? [String: Any],
                                    "samples is an object now, not an array")
        XCTAssertEqual(samples["o"] as? [Double], [64, 64], "the origin it was quantised about, written out")
        XCTAssertNotNil(samples["d"] as? String, "and the run itself, as base64")
        XCTAssertNil(object["samples"] as? [Any], "…and it is not an array of anything any more")
        XCTAssertEqual(Set(samples.keys), ["o", "d"], "two keys, and nothing derivable stored beside them")
    }

    /// A stroke encoded with no origin at all — every test in the suite that round-trips one through a
    /// bare `JSONEncoder()` — still decodes to the right place. The fallback costs addressable range,
    /// never correctness, which is what makes the `userInfo` channel safe to have.
    func testAStrokeEncodedWithNoOriginStillDecodesToTheSamePlace() throws {
        let stroke = Self.stroke()
        let decoded = try JSONDecoder().decode(VectorStroke.self, from: try JSONEncoder().encode(stroke))
        XCTAssertEqual(decoded.samples.count, stroke.samples.count)
        for (before, after) in zip(stroke.samples, decoded.samples) {
            XCTAssertEqual(after.x, before.x, accuracy: PackedSampleRun.quantum / 2)
            XCTAssertEqual(after.y, before.y, accuracy: PackedSampleRun.quantum / 2)
        }
    }

    /// A piece's lattice is the *parent's* whole walk, so it is the larger half of a cut-heavy cel and
    /// gets the same packing. `DabLattice`'s hand-written coder exists only for this.
    func testAPieceLatticeIsPackedToo() throws {
        var piece = Self.stroke()
        piece.lattice = DabLattice(samples: Self.realisticRun(count: 40), parameters: [0, 1])

        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(piece), options: []) as? [String: Any])
        let lattice = try XCTUnwrap(object["lattice"] as? [String: Any])
        XCTAssertNotNil(lattice["samples"] as? [String: Any],
                        "a lattice's samples are packed like any other run")

        let decoded = try JSONDecoder().decode(VectorStroke.self, from: try JSONEncoder().encode(piece))
        XCTAssertEqual(decoded.lattice?.samples.count, 40)
        XCTAssertEqual(decoded.lattice?.parameters, piece.lattice?.parameters, "the parameters are not coordinates")
        // The seed rides on the stroke rather than on its lattice — BRUSH.md §4 — so this is where a
        // piece's dab pattern survives the round trip now.
        XCTAssertEqual(decoded.seed, piece.seed)
    }

    /// Not a migration — TODO.md's standing permission says no document written so far has to survive.
    /// It is three lines, and what they buy is that a project written by yesterday's build still opens.
    func testTheOldArrayOfSamplesStillDecodes() throws {
        let stroke = Self.stroke()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(stroke), options: []) as? [String: Any])
        object["samples"] = [["x": 3.5, "y": 4.5, "pressure": 0.5]]

        let decoded = try JSONDecoder().decode(
            VectorStroke.self, from: try JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.samples, [VectorSample(x: 3.5, y: 4.5, pressure: 0.5)],
                       "an old file's samples decode at full precision, exactly as written")
    }

    // MARK: - The origin actually reaching the file

    /// **The guard on the whole design.** A canvas 12,000 points wide cannot be encoded about the
    /// canvas origin — half of it is past the top of the field — so ink near the far edge comes back
    /// flattened onto the boundary if `ProjectStore` fails to pass the quantisation origin. About the
    /// centre it fits with room to spare. A save and a reload is the only way to test that the origin
    /// travels the whole path, and it is what a source scan would have missed.
    func testInkNearTheEdgeOfAWideCanvasSurvivesASaveAndReload() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasSize = CGSize(width: 12000, height: 600)
        manager.addVectorLayer()
        let far = [VectorSample(x: 11_900.25, y: 64, pressure: 1),
                   VectorSample(x: 60.5, y: 500.75, pressure: 0.5)]
        manager.layers[1].cels[0].vector?.addStroke(
            VectorStroke(brush: manager.selectedBrush,
                         color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                         size: 8, opacity: 1, samples: far))

        let url = ProjectStore.createNewProjectURL(name: "Wide Canvas")
        saveAndWait(manager, to: url)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let reread = try XCTUnwrap(reloaded.layers[1].cels[0].vector?.strokes.first?.samples)

        XCTAssertEqual(reread.count, 2)
        for (before, after) in zip(far, reread) {
            XCTAssertEqual(after.x, before.x, accuracy: PackedSampleRun.quantum / 2,
                           "ink at x=\(before.x) on a 12,000-point canvas must come back where it was — "
                           + "if this reads ~8192 the save encoded about the canvas origin instead of its centre")
            XCTAssertEqual(after.y, before.y, accuracy: PackedSampleRun.quantum / 2)
        }
    }

    /// And the origin that reached the file is the one the ruling names — read off the bytes on disk,
    /// so the previous test's pass cannot be a coincidence of a canvas that happened to fit.
    func testTheOriginWrittenToDiskIsTheCentreOfTheCanvas() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasSize = CGSize(width: 12000, height: 600)
        manager.addVectorLayer()
        manager.layers[1].cels[0].vector?.addStroke(
            VectorStroke(brush: manager.selectedBrush,
                         color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                         size: 8, opacity: 1,
                         samples: [VectorSample(x: 100, y: 100, pressure: 1)]))

        let url = ProjectStore.createNewProjectURL(name: "Origin On Disk")
        saveAndWait(manager, to: url)

        let images = url.appendingPathComponent("images", isDirectory: true)
        let vectorFiles = try FileManager.default.contentsOfDirectory(atPath: images.path)
            .filter { $0.hasSuffix("_vector.json") }
        XCTAssertEqual(vectorFiles.count, 1, "Setup: exactly one vector cel was drawn on")

        let payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try Data(contentsOf: images.appendingPathComponent(vectorFiles[0]))) as? [String: Any])
        let elements = try XCTUnwrap(payload["elements"] as? [[String: Any]])
        let stroke = try XCTUnwrap(elements.compactMap { $0["stroke"] as? [String: Any] }.first)
        let samples = try XCTUnwrap(stroke["samples"] as? [String: Any])
        XCTAssertEqual(samples["o"] as? [Double], [6000, 300],
                       "the quantisation origin on disk is the centre of the canvas, per item (8)'s ruling")
    }

    /// Characterization, and the reason the item exists: the packed form is a large multiple smaller
    /// than the one it replaces. Asserted as a floor rather than a figure, because the exact ratio is
    /// a property of how many digits the coordinates need — see `PackedSampleRun`'s own measurement.
    func testThePackedFormIsAtLeastFiveTimesSmallerThanTheOneItReplaces() throws {
        struct Legacy: Encodable { var samples: [VectorSample] }
        let run = Self.realisticRun(count: 1000)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let today = try encoder.encode(Legacy(samples: run)).count
        let packed = try encoder.encode(PackedSampleRun(run, about: CGPoint(x: 1024, y: 512))).count
        XCTAssertLessThan(Double(packed) * 5, Double(today),
                          "packed \(packed) B against \(today) B for \(run.count) samples")
        XCTAssertLessThan(Double(packed) / Double(run.count), 8.0,
                          "and under 8 bytes a sample on the wire")
    }

    // MARK: - Item (14): the precision the grid cannot hold

    /// **The test that states why item (14) exists**, and the only one here that is about the artist
    /// rather than about the format.
    ///
    /// The quantisation grid is a fixed size in *canvas* points, so a stroke the artist shrank before
    /// a save has fewer usable bits — and whatever they lose is then multiplied by however much they
    /// grow it back by. Rotation and translation are fine; scale is not, and only scale is. The loss
    /// is one per store and it only materialises after a reopen, which is what makes it hard to see
    /// and easy to blame on the brush.
    ///
    /// Both numbers are in both messages on purpose: a failure here should say which of the two moved
    /// and by how much, not merely that a threshold was crossed.
    func testShrinkingToTwoPercentBeforeStoringCostsPointsOnTheGridAndNothingAtFullPrecision() {
        let pivot = CGPoint(x: 1024, y: 512)
        let original = Self.realisticRun(count: 200)

        /// The worst sample's displacement across shrink → store → regrow, in canvas points.
        func errorAfterRoundTrip(_ precision: PackedSampleRun.Precision) -> CGFloat {
            var shrink = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            shrink = shrink.scaledBy(x: 0.02, y: 0.02)
            shrink = shrink.translatedBy(x: -pivot.x, y: -pivot.y)
            let regrow = shrink.inverted()
            func mapped(_ samples: [VectorSample], through t: CGAffineTransform) -> [VectorSample] {
                samples.map {
                    let p = $0.point.applying(t)
                    return VectorSample(x: p.x, y: p.y, pressure: $0.pressure)
                }
            }
            let stored = PackedSampleRun(mapped(original, through: shrink),
                                         about: pivot, precision: precision).samples
            return zip(original, mapped(stored, through: regrow))
                .map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        }

        let onTheGrid = errorAfterRoundTrip(.quarterPixel)
        let atFullPrecision = errorAfterRoundTrip(.float32)
        let both = "quarter-pixel lost \(onTheGrid) pt, float32 lost \(atFullPrecision) pt"

        XCTAssertGreaterThan(onTheGrid, 1.0,
                             "the defect this feature cures must still be there on the grid — \(both). "
                             + "If this drops below a point the grid changed, and the feature's premise "
                             + "with it.")
        XCTAssertLessThan(atFullPrecision, 0.01,
                          "a stroke stored at full precision must survive the same round trip — \(both)")
    }

    /// **A precise stroke declares itself and an ordinary one is byte-for-byte what it always was.**
    ///
    /// The literal below is the fixed point, written out here rather than kept in a golden file: two
    /// `Int16` quarter-pixel coordinates and a byte of pressure, base64'd, under exactly the two keys
    /// item (8) shipped. A `p` appearing in that string would mean every stroke in every project on
    /// the owner's iPad had grown by a key — which is the whole reason the mode is written only when
    /// it is not the default.
    func testAnOrdinaryRunIsUnchangedByteForByteAndAPreciseOneSaysSo() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let fixture = [VectorSample(x: 3.5, y: 4.5, pressure: 0.5),
                       VectorSample(x: 10.25, y: -2.75, pressure: 1)]

        XCTAssertEqual(String(decoding: try encoder.encode(PackedSampleRun(fixture, about: .zero)), as: UTF8.self),
                       #"{"d":"DgASAIApAPX\/\/w==","o":[0,0]}"#,
                       "an ordinary run's bytes must be exactly what they were before item (14)")
        XCTAssertEqual(String(decoding: try encoder.encode(
                                PackedSampleRun(fixture, about: .zero, precision: .float32)), as: UTF8.self),
                       #"{"d":"AABgQAAAkECAAAAkQQAAMMD\/","o":[0,0],"p":"f32"}"#,
                       "and a precise run is the same two keys plus the mode token")

        // The same statement one level up, where a stroke decides which it writes.
        func samplesObject(of stroke: VectorStroke) throws -> [String: Any] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(stroke)) as? [String: Any])
            XCTAssertNil(object["precise"],
                         "`precise` is derived from the run's shape, never a key of its own")
            return try XCTUnwrap(object["samples"] as? [String: Any])
        }
        XCTAssertEqual(Set(try samplesObject(of: Self.stroke()).keys), ["o", "d"],
                       "an ordinary stroke writes two keys and no third")
        let precise = try samplesObject(of: Self.stroke().markedPrecise())
        XCTAssertEqual(Set(precise.keys), ["o", "d", "p"])
        XCTAssertEqual(precise["p"] as? String, "f32")
    }

    /// `precise` is not stored, so the only thing that can carry it across a save is the shape of the
    /// run itself — on the stroke **and on its lattice**, which is the parent's whole walk and is
    /// mapped by the very transform the stroke's own samples are.
    ///
    /// A real `ProjectStore` round trip rather than a bare `JSONEncoder`, for
    /// `testInkNearTheEdgeOfAWideCanvasSurvivesASaveAndReload`'s reason: the derivation has to survive
    /// the whole path, and a source scan would not have tested it.
    func testPreciseSurvivesASaveAndReloadOnTheStrokeAndItsLattice() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let walk = Self.realisticRun(count: 24)
        var piece = VectorStroke(brush: manager.selectedBrush,
                                 color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                 size: 8, opacity: 1, samples: Array(walk.prefix(8)))
        piece.lattice = DabLattice(samples: walk, parameters: [0, 1])
        manager.layers[1].cels[0].vector?.addStroke(piece.markedPrecise())
        manager.layers[1].cels[0].vector?.addStroke(
            VectorStroke(brush: manager.selectedBrush,
                         color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                         size: 8, opacity: 1, samples: Array(walk.suffix(8))))

        let url = ProjectStore.createNewProjectURL(name: "Precise Round Trip")
        saveAndWait(manager, to: url)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let strokes = try XCTUnwrap(reloaded.layers[1].cels[0].vector?.strokes)

        XCTAssertEqual(strokes.count, 2)
        XCTAssertTrue(strokes[0].precise, "the marked stroke comes back marked")
        XCTAssertEqual(strokes[0].lattice?.precise, true,
                       "and so does its lattice — one invariant, not two independent flags")
        XCTAssertFalse(strokes[1].precise, "the stroke beside it is untouched and stays on the grid")

        // And the point of the flag: the coordinates come back far better than a quarter pixel.
        for (before, after) in zip(piece.samples, strokes[0].samples) {
            XCTAssertEqual(after.x, before.x, accuracy: 0.001)
            XCTAssertEqual(after.y, before.y, accuracy: 0.001)
        }
    }

    /// **float32 does not clamp, and that is a real behavioural difference rather than a detail.**
    /// BUGS.md's unclamped zoom makes a ~1.6-million-point coordinate reachable from a real drag; the
    /// quarter-pixel form flattens it onto the storage boundary and counts it, and a precise stroke
    /// cannot be flattened that way at all. Both behaviours are wanted — the first keeps the bug
    /// boring, the second keeps the artist's *"store it exactly"* promise for geometry that is nowhere
    /// near the canvas.
    func testFullPrecisionDoesNotClampWhereTheGridSaturates() throws {
        let origin = CGPoint(x: 1024, y: 512)
        let far = VectorSample(x: 1_638_400, y: -1_638_400, pressure: 1)

        let precise = PackedSampleRun([far], about: origin, precision: .float32)
        let survived = try XCTUnwrap(precise.samples.first)
        XCTAssertEqual(precise.clampedCount, 0, "float32 has no boundary to flatten onto")
        XCTAssertEqual(survived.x, far.x, accuracy: 1)
        XCTAssertEqual(survived.y, far.y, accuracy: 1)

        let onTheGrid = PackedSampleRun([far], about: origin)
        let saturated = try XCTUnwrap(onTheGrid.samples.first)
        XCTAssertEqual(onTheGrid.clampedCount, 1)
        XCTAssertEqual(saturated.x, origin.x + PackedSampleRun.representable.upperBound,
                       "…where the quarter-pixel form saturates and says so")
    }

    /// A damaged float32 blob is a damaged file, and it has to be reported rather than trapped for
    /// `testAMalformedRunThrowsRatherThanTrapping`'s reason — plus one this mode adds: a length that
    /// is a whole number of *quarter-pixel* records is not a whole number of float32 ones, so the
    /// check has to be against the declared mode's width and not against a constant.
    func testAMalformedFullPrecisionRunThrowsRatherThanTrapping() {
        for bad in [#"{"o":[0,0],"d":"AAAAAAAAAAAAAA==","p":"f32"}"#,   // ten bytes: two grid records, not a whole float32 one
                    #"{"o":[0,0],"d":"AAAA","p":"f32"}"#,               // three bytes
                    #"{"o":[0,0],"d":"","p":"f64"}"#,                   // a mode this build does not know
                    #"{"o":[0,0],"d":"","p":""}"#] {                    // …including the empty one
            XCTAssertThrowsError(try JSONDecoder().decode(PackedSampleRun.self, from: Data(bad.utf8)),
                                 "\(bad) must be reported, not accepted")
        }
    }

    // MARK: - Helpers

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    /// Coordinates of the shape `UITouch.location(in:)` produces — full-precision doubles landing
    /// between the grid points, not the short decimals a hand-written fixture reaches for. The
    /// generator is a fixed-seed xorshift so a failure is reproducible.
    private static func realisticRun(count: Int) -> [VectorSample] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return CGFloat(Double(seed % 1_000_000_000) / 1_000_000_000)
        }
        return (0..<count).map { i in
            VectorSample(x: CGFloat(i % 2048) + next(), y: CGFloat(i % 1024) + next(), pressure: next())
        }
    }

    private static func stroke() -> VectorStroke {
        VectorStroke(brush: BrushLibrary.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 9, opacity: 1, samples: realisticRun(count: 12))
    }
}
