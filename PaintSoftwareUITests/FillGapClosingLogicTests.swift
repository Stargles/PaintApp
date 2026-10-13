import XCTest
import SwiftUI
import UIKit
import simd

/// **Gap closing that seals openings and nothing else** — TODO (158). The owner: *"when it is turned
/// up and the user fills a square with a small opening, the feature works as intended, but also leaves
/// the places near the edges of the squares not filled in."*
///
/// Every scene here is asked the two questions the owner's words make into one: does the fill stop at
/// an opening the slider covers, and does it still reach every edge and every corner? The answers are
/// counted over the whole region rather than sampled at a probe, because a fill that curled in from a
/// corner by three pixels is a handful of pixels in a few thousand, and a probe in the middle of the
/// shape cannot see it.
///
/// The session tests drive `MetalFillSession` — the production kernels and `FillBasins` exactly as
/// `CanvasManager.renderFill` drives them — over hand-built ink. The last test is the owner's own
/// scene through the app's fill path: a hand-wobbled square drawn with a brush on a vector layer at
/// their 2048×1024 canvas.
final class FillGapClosingLogicTests: XCTestCase {

    private static let side = 96

    // MARK: - Fixtures

    private struct Ink {
        let width: Int, height: Int
        var bytes: [UInt8]
        init(width: Int = FillGapClosingLogicTests.side, height: Int = FillGapClosingLogicTests.side) {
            self.width = width; self.height = height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
        }
        mutating func set(_ x: Int, _ y: Int, _ on: Bool = true) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            bytes[(y * width + x) * 4 + 3] = on ? 255 : 0
        }
        mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ on: Bool = true) {
            for y in y0...y1 { for x in x0...x1 { set(x, y, on) } }
        }
        /// A capsule of `thickness` from one point to another.
        mutating func line(_ a: CGPoint, _ b: CGPoint, thickness: CGFloat) {
            let v = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let lengthSquared = max(v.x * v.x + v.y * v.y, 1e-9)
            for y in 0..<height {
                for x in 0..<width {
                    let p = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    let u = min(max(((p.x - a.x) * v.x + (p.y - a.y) * v.y) / lengthSquared, 0), 1)
                    let dx = p.x - (a.x + u * v.x), dy = p.y - (a.y + u * v.y)
                    if dx * dx + dy * dy <= thickness * thickness / 4 { set(x, y) }
                }
            }
        }
        func isInk(_ x: Int, _ y: Int) -> Bool { bytes[(y * width + x) * 4 + 3] != 0 }

        /// Every paper pixel 4-connected to `seed`, counted without the engine — the region a fill
        /// with no gap closing must be, worked out independently of the code that makes it.
        func paperReachable(from seed: (x: Int, y: Int)) -> [Bool] {
            var reached = [Bool](repeating: false, count: width * height)
            var stack = [seed.y * width + seed.x]
            reached[stack[0]] = true
            while let p = stack.popLast() {
                let x = p % width, y = p / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height && !isInk(nx, ny) && !reached[ny * width + nx] {
                    reached[ny * width + nx] = true
                    stack.append(ny * width + nx)
                }
            }
            return reached
        }
    }

    /// A 3 px outline of the square [16, 79]², its right side broken by an opening `opening` rows
    /// tall centred on row 48. The interior is the 58² between the walls.
    private func box(opening: Int = 0) -> Ink {
        var ink = Ink()
        ink.rect(16, 16, 79, 18); ink.rect(16, 77, 79, 79); ink.rect(16, 16, 18, 79); ink.rect(77, 16, 79, 79)
        if opening > 0 { ink.rect(77, 48 - opening / 2, 79, 48 - opening / 2 + opening - 1, false) }
        return ink
    }
    private static let interior = 58 * 58

    /// A deterministic jitter, for outlines that wobble the way a hand does.
    private struct Jitter {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 11) / CGFloat(1 << 53) - 0.5
        }
    }

    // MARK: - Driving the session

    private struct Region {
        let bytes: [UInt8]
        let width: Int
        func isFilled(_ x: Int, _ y: Int) -> Bool { bytes[(y * width + x) * 4 + 3] != 0 }
        var count: Int { stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] != 0 ? 1 : 0) } }
    }

    private func session(_ ink: Ink) throws -> MetalFillSession {
        let engine = try XCTUnwrap(MetalFillEngine.shared, "No Metal device, or Fill.metal is not in this target")
        return try XCTUnwrap(engine.makeSession(referenceRGBA: ink.bytes, width: ink.width, height: ink.height).session)
    }

    /// One fill at the app's defaults but for Edge Overlap, which is 0 so a pixel's answer is the
    /// region's own and not a disk grown around it; the canvas edge is not a boundary unless asked.
    private func fill(_ session: MetalFillSession, seed: (x: Int, y: Int), gap: Float,
                      threshold: Float = 0.15) throws -> Region {
        let bytes = try XCTUnwrap(session.fill(seedX: seed.x, seedY: seed.y,
                                               seedColor: session.seedColor(atX: seed.x, y: seed.y),
                                               threshold: threshold, gapWidth: gap, edgeOverlap: 0,
                                               fillColor: SIMD4<Float>(1, 0, 0, 1)))
        return Region(bytes: bytes, width: session.width)
    }

    private func fill(_ ink: Ink, seed: (x: Int, y: Int), gap: Float) throws -> Region {
        try fill(try session(ink), seed: seed, gap: gap)
    }

    // MARK: - Edges and corners

    /// **The owner's complaint, stated as a count.** A closed square fills every one of its 58² inner
    /// pixels at every setting of the slider — the corners included, which is exactly where a fill that
    /// treated every edge as a gap curled in, by more as the slider rose.
    func testAClosedSquareFillsToItsEdgesAndCornersAtEverySetting() throws {
        let session = try session(box())
        for gap in [Float(0), 4, 8, 16, 24, 40] {
            let region = try fill(session, seed: (40, 40), gap: gap)
            XCTAssertEqual(region.count, Self.interior, "gap \(gap): every pixel inside the walls")
            for corner in [(19, 19), (76, 19), (19, 76), (76, 76)] {
                XCTAssertTrue(region.isFilled(corner.0, corner.1), "gap \(gap): the corner pixel \(corner)")
            }
        }
    }

    /// An acute corner fills to its tip at the top of the slider: every paper pixel the wedge holds, as
    /// counted without the engine.
    func testAnAcuteCornerFillsToItsTip() throws {
        var wedge = Ink()
        wedge.line(CGPoint(x: 8, y: 8), CGPoint(x: 88, y: 28), thickness: 3)
        wedge.line(CGPoint(x: 8, y: 8), CGPoint(x: 88, y: 60), thickness: 3)
        wedge.line(CGPoint(x: 88, y: 28), CGPoint(x: 88, y: 60), thickness: 3)
        let interior = wedge.paperReachable(from: (70, 40))
        XCTAssertGreaterThan(interior.filter { $0 }.count, 500, "Fixture check: the wedge's interior")
        let maxed = try fill(wedge, seed: (70, 40), gap: 40)
        var wrong = 0
        for y in 0..<wedge.height { for x in 0..<wedge.width where maxed.isFilled(x, y) != interior[y * wedge.width + x] {
            wrong += 1
        } }
        XCTAssertEqual(wrong, 0, "At 40 px the wedge fills to its tip, exactly its paper")
    }

    /// A shape outlined by hand wobbles, and every bump in its outline is a little rise and fall in the
    /// distance to ink. None of them is an opening: a wobbly strand 9–12 px wide fills whole at every
    /// setting, where a gap closing that sealed every narrowing would cut it into pieces.
    func testAWobblyOutlineIsOneShapeAtEverySetting() throws {
        var strand = Ink(width: 128, height: 40)
        var jitter = Jitter(state: 9)
        var top = CGPoint(x: 4, y: 14), bottom = CGPoint(x: 4, y: 26)
        for i in 1...30 {
            let x = 4 + CGFloat(i) * 4
            let nextTop = CGPoint(x: x, y: 14 + jitter.next() * 3)
            let nextBottom = CGPoint(x: x, y: 26 + jitter.next() * 3)
            strand.line(top, nextTop, thickness: 3); strand.line(bottom, nextBottom, thickness: 3)
            top = nextTop; bottom = nextBottom
        }
        strand.line(CGPoint(x: 4, y: 12), CGPoint(x: 4, y: 28), thickness: 3)
        strand.line(CGPoint(x: 124, y: 12), CGPoint(x: 124, y: 28), thickness: 3)
        let session = try session(strand)
        let paper = strand.paperReachable(from: (60, 20))
        for gap in [Float(0), 4, 8, 16, 40] {
            let region = try fill(session, seed: (60, 20), gap: gap)
            let wrong = (0..<paper.count).filter { region.isFilled($0 % strand.width, $0 / strand.width) != paper[$0] }.count
            XCTAssertEqual(wrong, 0, "gap \(gap): the whole strand, every paper pixel of it")
        }
    }

    // MARK: - Openings

    /// **Gap closing still does its job**: an opening is sealed once the slider reaches its width, and
    /// never before — an even width at its own number, an odd one at one more (`FillBasins` says why).
    /// Escaping is measured outside the box, where nothing but an escape can put paint.
    func testAnOpeningSealsOnceTheSliderReachesItsWidthAndNoSooner() throws {
        for opening in [2, 3, 6, 8, 9, 12] {
            let session = try session(box(opening: opening))
            let sealsAt = Float(opening % 2 == 0 ? opening : opening + 1)
            XCTAssertTrue(try fill(session, seed: (40, 40), gap: sealsAt - 1).isFilled(4, 4),
                          "a \(opening) px opening is open at \(sealsAt - 1)")
            let sealed = try fill(session, seed: (40, 40), gap: sealsAt)
            XCTAssertFalse(sealed.isFilled(4, 4), "a \(opening) px opening is sealed at \(sealsAt)")
            XCTAssertFalse(try fill(session, seed: (40, 40), gap: 40).isFilled(4, 4),
                           "…and stays sealed at the top of the slider")
        }
    }

    /// **Both halves at once, the owner's scene.** With the slider high over a square with a small
    /// opening, the fill stops at the opening *and* reaches every corner and the inner edge right
    /// beside the opening. The only pixels it adds to the interior are the slot through the wall
    /// itself, which the cut gives to the side it reaches first — at most the slot's 6 × 3.
    func testBesideASealedOpeningTheFillStillReachesEveryCornerAndEdge() throws {
        let region = try fill(box(opening: 6), seed: (40, 40), gap: 40)
        for corner in [(19, 19), (76, 19), (19, 76), (76, 76)] {
            XCTAssertTrue(region.isFilled(corner.0, corner.1), "the corner pixel \(corner)")
        }
        XCTAssertTrue(region.isFilled(76, 44), "the inner edge just above the opening")
        XCTAssertTrue(region.isFilled(76, 51), "…and just below it")
        XCTAssertFalse(region.isFilled(82, 48), "the paper just outside the opening")
        XCTAssertFalse(region.isFilled(4, 4), "…and the page beyond")
        XCTAssertGreaterThanOrEqual(region.count, Self.interior, "every inner pixel")
        XCTAssertLessThanOrEqual(region.count, Self.interior + 6 * 3, "…and at most the slot besides")
    }

    /// Two rooms joined by a 7 px neck: one region while the slider is under 7, and cut **at the neck**
    /// from 8 up — the tapped room fills to its own wall all the way round, and the other not at all.
    func testADumbbellIsCutAtItsNeck() throws {
        var dumbbell = Ink(width: 120, height: 70)
        dumbbell.rect(0, 0, 119, 69)
        func inRoom(_ x: Int, _ y: Int, _ cx: Int) -> Bool {
            let dx = x - cx, dy = y - 35
            return dx * dx + dy * dy <= 22 * 22
        }
        for y in 0..<70 { for x in 0..<120 where inRoom(x, y, 30) || inRoom(x, y, 90) || ((30...90).contains(x) && abs(y - 35) <= 3) {
            dumbbell.set(x, y, false)
        } }
        let session = try session(dumbbell)
        XCTAssertTrue(try fill(session, seed: (30, 35), gap: 6).isFilled(90, 35), "one region at 6")
        let cut = try fill(session, seed: (30, 35), gap: 8)
        XCTAssertFalse(cut.isFilled(90, 35), "cut at 8")
        for y in 0..<70 { for x in 0..<120 where inRoom(x, y, 30) {
            XCTAssertTrue(cut.isFilled(x, y), "the tapped room fills to its wall: (\(x), \(y))")
        } }
        for y in 0..<70 { for x in 0..<120 where inRoom(x, y, 90) {
            XCTAssertFalse(cut.isFilled(x, y), "the other room not at all: (\(x), \(y))")
        } }
    }

    /// **A pocket behind a narrow opening is a room, and stays one.** An eye drawn inside a face, its
    /// outline broken by a 2 px gap: the face's fill pours in at 0 and 1, and from 2 up the eye is its
    /// own — at every higher setting, so the partition only ever splits as the slider rises.
    func testAPocketBehindANarrowOpeningStaysSealedAtEveryHigherSetting() throws {
        var face = box()
        for y in 0..<Self.side { for x in 0..<Self.side {
            let dx = Double(x - 48), dy = Double(y - 48), d = (dx * dx + dy * dy).squareRoot()
            if d >= 8 && d <= 10 { face.set(x, y) }
        } }
        face.rect(56, 47, 60, 48, false)
        let session = try session(face)
        XCTAssertTrue(try fill(session, seed: (25, 25), gap: 0).isFilled(48, 48), "the eye fills with the face at 0")
        for gap in [Float(2), 4, 8, 16, 40] {
            let region = try fill(session, seed: (25, 25), gap: gap)
            XCTAssertFalse(region.isFilled(48, 48), "gap \(gap): the eye is its own")
            XCTAssertTrue(region.isFilled(48, 37), "gap \(gap): the face fills right up to the eye's outline")
            XCTAssertTrue(region.isFilled(19, 19), "gap \(gap): …and into the face's own corner")
        }
        XCTAssertTrue(try fill(session, seed: (48, 48), gap: 40).isFilled(52, 48),
                      "and tapping the eye fills the eye")
    }

    /// Tapping inside a region narrower than the slider still fills it: the seed belongs to the shape it
    /// lies in. A 6 px channel closed at both ends fills whole at the top of the slider.
    func testANarrowShapeStillFillsWhenTappedInside() throws {
        var channel = Ink()
        channel.rect(10, 40, 85, 42); channel.rect(10, 49, 85, 51)
        channel.rect(10, 40, 12, 51); channel.rect(83, 40, 85, 51)
        let session = try session(channel)
        let plain = try fill(session, seed: (48, 45), gap: 0)
        XCTAssertEqual(try fill(session, seed: (48, 45), gap: 40).bytes, plain.bytes,
                       "the whole channel, as with no gap closing")
        XCTAssertEqual(plain.count, 70 * 6, "Fixture check: 70 by 6")
    }

    // MARK: - The slider is a cut, not a re-run

    /// **Dragging Gap Closing re-runs nothing the slider cannot change.** The walls, the plain flood,
    /// the distance map and the basins are built once per press and reused for every value; only a
    /// change to what they depend on — here the threshold — builds them again.
    func testASliderTickReusesThePressesBasins() throws {
        let session = try session(box(opening: 6))
        _ = try fill(session, seed: (40, 40), gap: 8)
        XCTAssertEqual(session.structureBuilds, 1, "the press builds the basins")
        for gap in [Float(2), 12, 40, 0, 20] { _ = try fill(session, seed: (40, 40), gap: gap) }
        XCTAssertEqual(session.structureBuilds, 1, "five slider values, no rebuild")
        _ = try fill(session, seed: (40, 40), gap: 20, threshold: 0.3)
        XCTAssertEqual(session.structureBuilds, 2, "a new threshold is new walls")
    }

    /// The cut is exact against a fresh build: a tick on a reused session paints what a press at that
    /// setting paints.
    func testATickPaintsWhatAPressAtThatSettingPaints() throws {
        let reused = try session(box(opening: 6))
        _ = try fill(reused, seed: (40, 40), gap: 2)
        for gap in [Float(4), 6, 12, 0] {
            XCTAssertEqual(try fill(reused, seed: (40, 40), gap: gap).bytes,
                           try fill(box(opening: 6), seed: (40, 40), gap: gap).bytes, "gap \(gap)")
        }
    }

    /// **The app's sessions cap the distance map at the slider's reach, and that changes no answer.**
    /// Two big rooms joined by a 20 px neck, with a pocket behind a 3 px gap in one of them — rooms deep
    /// enough that the cap bites — cut on a session built for the top of the slider and on an uncapped
    /// one, at every setting up to that top: the same pixels each time.
    func testCappingTheDistanceMapAtTheSlidersReachChangesNoCut() throws {
        var rooms = Ink(width: 240, height: 120)
        rooms.rect(0, 0, 239, 119)
        rooms.rect(4, 4, 115, 115, false); rooms.rect(124, 4, 235, 115, false)
        rooms.rect(116, 50, 123, 69, false)
        for y in 0..<120 { for x in 0..<240 {
            let dx = Double(x - 60), dy = Double(y - 60), d = (dx * dx + dy * dy).squareRoot()
            if d >= 14 && d <= 16 { rooms.set(x, y) }
        } }
        rooms.rect(74, 59, 76, 61, false)
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let capped = try XCTUnwrap(engine.makeSession(referenceRGBA: rooms.bytes, width: 240, height: 120,
                                                      gapWidthLimit: 40).session)
        let exact = try session(rooms)
        for gap in [Float(0), 2, 3, 4, 8, 16, 20, 21, 24, 40] {
            for seed in [(20, 20), (200, 60), (60, 60)] {
                XCTAssertEqual(try fill(capped, seed: seed, gap: gap).bytes, try fill(exact, seed: seed, gap: gap).bytes,
                               "gap \(gap), seed \(seed)")
            }
        }
        XCTAssertFalse(try fill(capped, seed: (20, 20), gap: 24).isFilled(200, 60), "Fixture check: the neck seals at 24")
        XCTAssertTrue(try fill(capped, seed: (20, 20), gap: 16).isFilled(200, 60), "…and is open at 16")
    }

    // MARK: - The owner's scene

    /// **A hand-drawn square with an opening, at the owner's 2048×1024, through the app's own fill.**
    /// A vector layer holding a wobbly brush outline round a 600 px square, broken by a gap in its
    /// right side; a tap inside it at Gap Closing 30.
    ///
    /// The control is the same outline with one more short stroke across the gap, filled with no gap
    /// closing at all — the region an artist means, over byte-identical ink everywhere but the gap.
    /// Every pixel of that region away from the gap must be filled, so the fill reaches the ink along
    /// all four sides and into all four corners, and nothing outside the square may be. A third fill,
    /// the open outline at 0, proves the gap is a real way out.
    func testTheOwnersSquareFillsToItsInkAndStopsAtTheOpening() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let filled = try ownersFill(gapClosing: 30, closingTheGap: false)
        let control = try ownersFill(gapClosing: 0, closingTheGap: true)
        let leaked = try ownersFill(gapClosing: 0, closingTheGap: false)

        var interior = 0, missed = 0, spilled = 0
        for y in 0..<1024 {
            for x in 0..<2048 {
                let i = (y * 2048 + x) * 4 + 3
                let inside = control[i] != 0
                if inside { interior += 1 }
                let nearTheGap = abs(CGFloat(x) - Self.ownersGap.midX) < 40 && abs(CGFloat(y) - Self.ownersGap.midY) < 40
                guard !nearTheGap else { continue }
                if inside, filled[i] == 0 { missed += 1 }
                if !inside, filled[i] != 0 { spilled += 1 }
            }
        }
        XCTAssertGreaterThan(interior, 300_000, "Fixture check: the control is the square's interior")
        XCTAssertNotEqual(leaked[(40 * 2048 + 40) * 4 + 3], 0, "Fixture check: at 0 the fill leaks out through the gap")
        XCTAssertEqual(missed, 0, "every pixel of the square's interior away from the gap — edges and corners")
        XCTAssertEqual(spilled, 0, "and nothing outside the square: the gap held")

        // And the control is not merely self-consistent: along rays from the middle into each corner
        // and onto three sides, the fill runs up to the first pixel the ink walls off — alpha past the
        // 0.15 threshold's 77 — read off the outline's own render rather than off any fill.
        let ink = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
            VectorCanvas(size: CGSize(width: 2048, height: 1024), strokes: ownersOutline().strokes).render().cgImage)))
        let middle = CGPoint(x: 600, y: 460)
        for (name, target) in [("top-left", CGPoint(x: 250, y: 110)), ("top-right", CGPoint(x: 950, y: 100)),
                               ("bottom-right", CGPoint(x: 960, y: 820)), ("bottom-left", CGPoint(x: 240, y: 810)),
                               ("left", CGPoint(x: 240, y: 460)), ("top", CGPoint(x: 600, y: 100)),
                               ("bottom", CGPoint(x: 600, y: 820))] {
            let steps = Int(max(abs(target.x - middle.x), abs(target.y - middle.y)))
            var short = 0, reachedInk = false
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let o = (Int(middle.y + (target.y - middle.y) * t) * 2048 + Int(middle.x + (target.x - middle.x) * t)) * 4 + 3
                if ink[o] >= 77 { reachedInk = true; break }
                if filled[o] == 0 { short += 1 }
            }
            XCTAssertTrue(reachedInk, "Fixture check: the ray to the \(name) meets the outline")
            XCTAssertEqual(short, 0, "the fill reaches the ink toward the \(name)")
        }
    }

    /// Where the owner's outline skips, on its right side.
    private static let ownersGap = CGRect(x: 895, y: 450, width: 30, height: 20)

    /// The owner's outline as strokes: a hand-wobbled square, its right side broken across
    /// `ownersGap`, and the short stroke that would close it.
    private func ownersOutline() -> (strokes: [VectorStroke], bridge: VectorStroke) {
        var jitter = Jitter(state: 158)
        let corners = [CGPoint(x: 300, y: 160), CGPoint(x: 900, y: 150), CGPoint(x: 910, y: 770),
                       CGPoint(x: 290, y: 760)]
        var runs: [[VectorSample]] = [[]]
        for side in 0..<4 {
            let a = corners[side], b = corners[(side + 1) % 4]
            for step in 0..<60 {
                let t = CGFloat(step) / 60
                let p = CGPoint(x: a.x + (b.x - a.x) * t + jitter.next() * 4,
                                y: a.y + (b.y - a.y) * t + jitter.next() * 4)
                let pressure = Double(0.7 + jitter.next() * 0.4)
                if side == 1, (Self.ownersGap.minY...Self.ownersGap.maxY).contains(p.y) {
                    if !(runs.last?.isEmpty ?? true) { runs.append([]) }
                    continue
                }
                runs[runs.count - 1].append(VectorSample(x: Double(p.x), y: Double(p.y), pressure: pressure))
            }
        }
        runs[runs.count - 1].append(VectorSample(x: Double(corners[0].x), y: Double(corners[0].y), pressure: 0.8))
        func stroke(_ samples: [VectorSample]) -> VectorStroke {
            VectorStroke(brush: TestBrushes.hardRound, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                         size: 8, opacity: 1, samples: StrokeSamples(samples, channels: .pressureOnly))
        }
        let bridge = stroke([runs[0].last!, runs[1].first!])
        return (runs.filter { $0.count > 1 }.map(stroke), bridge)
    }

    /// The owner's outline on a vector layer of a 2048×1024 manager, filled from the square's middle on
    /// a raster layer above it and committed; returns that layer's RGBA.
    private func ownersFill(gapClosing: CGFloat, closingTheGap: Bool) throws -> [UInt8] {
        let size = CGSize(width: 2048, height: 1024)
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = size
        manager.addVectorLayer()
        manager.addLayer()
        manager.fillSettings.bucketEdgeOverlap = 0
        manager.fillSettings.gapClosing = gapClosing
        manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        let outline = ownersOutline()
        manager.layers[0].cels[0].vector = VectorCanvas(size: size,
                                                        strokes: outline.strokes + (closingTheGap ? [outline.bridge] : []))

        manager.beginInteractiveFill(at: CGPoint(x: 600, y: 460))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { done.fulfill() }
        wait(for: [done], timeout: 6)
        manager.commitInteractiveFill()
        let cg = try XCTUnwrap(manager.layers[1].cels.first?.raster.renderToUIImage().cgImage)
        return try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
    }
}
