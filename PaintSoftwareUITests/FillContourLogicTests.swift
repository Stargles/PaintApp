import CoreGraphics
import SwiftUI
import UIKit
import XCTest

/// `PixelOps.contourPath` — the one lossy step in the vector fill pipeline, and until this file
/// existed it had no test of any kind.
///
/// Every lasso fill on a vector layer and every magic-wand selection passes through it: the GPU
/// hands back a byte mask, this turns the mask into a `CGPath`, and from then on the path *is* the
/// artwork. Nothing downstream can recover a pixel it dropped. TODO (44) was exactly that — a
/// vertex where the region touches itself corner to corner starts **two** boundary edges, the store
/// kept one, and the walk closed the resulting open subpath with a straight line. The owner saw it
/// as straight-edged holes and wedges eaten out of an *earlier* fill, because committing a second
/// fill is what bakes the first one's mask through here for the first time.
///
/// **Every assertion here is one of two kinds, deliberately.** Area conservation says the trace kept
/// the right *amount* of paper; the round trip rasterizes the path back and compares it to the mask
/// byte for byte, which says it kept the right *shape*. Area alone passes a contour that is wrong in
/// compensating ways, and a fill's correctness is a picture.
///
/// **And every fixture is swept across 24 offsets rather than traced once**, which is not
/// belt-and-braces. `IntPoint`'s `Hashable` is Swift's, whose hash seed is randomised per process,
/// so the defect this file pins corrupted a *different* part of the drawing on every launch —
/// measured here at 14 of 60 processes tracing the two-square fixture correctly by luck. A
/// single-fixture assertion would therefore have been a coin flip, green about a quarter of the
/// time on thoroughly broken code. Sweeping offsets also varies the hash order *within* one
/// process, which is the only way this suite can see order-dependence at all: two calls with the
/// same mask in the same process take the same dictionary order and would agree however broken the
/// code was.
final class FillContourLogicTests: XCTestCase {

    // MARK: - Reading a traced path back

    /// The path's subpaths as closed point rings. Every element `contourPath` emits is a line, so
    /// nothing here has to flatten a curve.
    private func rings(_ path: CGPath) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var current: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                if current.count > 1 { out.append(current) }
                current = [element.pointee.points[0]]
            case .addLineToPoint:
                current.append(element.pointee.points[0])
            case .closeSubpath:
                if current.count > 1 { out.append(current) }
                current = []
            default:
                XCTFail("contourPath emitted a curve segment; every edge of a pixel mask is a line")
            }
        }
        if current.count > 1 { out.append(current) }
        return out
    }

    /// The area the path encloses, by the shoelace formula — **exact**, not approximate, because
    /// every segment is a line between integer points. Holes trace with the opposite winding to
    /// their container, so summing the *signed* areas subtracts them, which is what the mask's
    /// popcount counts too.
    private func tracedArea(_ path: CGPath) -> Double {
        let total = rings(path).reduce(0.0) { running, ring in
            var doubled = 0.0
            for i in ring.indices {
                let p = ring[i], q = ring[(i + 1) % ring.count]
                doubled += Double(p.x * q.y - q.x * p.y)
            }
            return running + doubled / 2
        }
        return abs(total)
    }

    /// Fills the traced path back into a byte-per-pixel buffer with antialiasing off and the winding
    /// rule the fill and the marching-ants clip both use, so a mismatch is a real difference in
    /// shape rather than a rounding disagreement. Flipped exactly as `LassoFillMask.rasterize`
    /// flips, so row 0 of the result is row 0 of the mask.
    private func rasterized(_ path: CGPath, width: Int, height: Int) -> [Bool] {
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setShouldAntialias(false)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath(using: .winding)
        }
        return bytes.map { $0 != 0 }
    }

    /// The longest segment that is neither horizontal nor vertical. A pixel mask's boundary is made
    /// of unit axis steps and nothing else, so on a correct trace this is 0 — and the chord a
    /// dead-ended walk leaves behind, which is what the owner photographed, is the only thing that
    /// can make it non-zero.
    private func longestDiagonal(_ path: CGPath) -> Double {
        var worst = 0.0
        for ring in rings(path) {
            for i in ring.indices {
                let p = ring[i], q = ring[(i + 1) % ring.count]
                let dx = Double(q.x - p.x), dy = Double(q.y - p.y)
                if dx != 0 && dy != 0 { worst = max(worst, (dx * dx + dy * dy).squareRoot()) }
            }
        }
        return worst
    }

    /// A ring's points as a comparable string, with the fixture's own offset subtracted, so two
    /// traces of the same shape at different places on the canvas compare equal.
    private func shapeKey(_ path: CGPath, offsetX: Int, offsetY: Int) -> String {
        rings(path)
            .map { ring in ring.map { "\(Int($0.x) - offsetX),\(Int($0.y) - offsetY)" }.joined(separator: " ") }
            .joined(separator: "|")
    }

    // MARK: - Masks

    private struct Mask {
        var bits: [Bool]
        var width: Int
        var height: Int
        var popcount: Int { bits.reduce(0) { $0 + ($1 ? 1 : 0) } }
    }

    /// Vertices where the selected region touches itself corner to corner — the 2x2 checkerboard
    /// that starts two boundary edges at one point. **This is the whole defect**, and a fixture that
    /// contains none of them cannot exercise it.
    private func pinchCount(_ mask: Mask) -> Int {
        func on(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < mask.width, y >= 0, y < mask.height else { return false }
            return mask.bits[y * mask.width + x]
        }
        var found = 0
        for vy in 0...mask.height {
            for vx in 0...mask.width {
                let upLeft = on(vx - 1, vy - 1), upRight = on(vx, vy - 1)
                let downLeft = on(vx - 1, vy), downRight = on(vx, vy)
                if (upLeft && downRight && !upRight && !downLeft)
                    || (upRight && downLeft && !upLeft && !downRight) { found += 1 }
            }
        }
        return found
    }

    private func blank(_ width: Int, _ height: Int) -> Mask {
        Mask(bits: [Bool](repeating: false, count: width * height), width: width, height: height)
    }

    /// Two pixels sharing one corner — the defect at its smallest, 8 boundary edges of which the
    /// single-value store keeps 7.
    private func twoPixelsAtACorner(offsetX: Int, offsetY: Int) -> Mask {
        var mask = blank(16, 16)
        mask.bits[offsetY * 16 + offsetX] = true
        mask.bits[(offsetY + 1) * 16 + offsetX + 1] = true
        return mask
    }

    /// Two 50x50 squares sharing one corner: 5,000 px, 400 boundary edges, one shared vertex.
    private func twoSquaresAtACorner(offsetX: Int, offsetY: Int) -> Mask {
        var mask = blank(128, 128)
        for y in 0..<50 {
            for x in 0..<50 {
                mask.bits[(offsetY + y) * 128 + offsetX + x] = true
                mask.bits[(offsetY + 50 + y) * 128 + offsetX + 50 + x] = true
            }
        }
        return mask
    }

    /// A one-pixel 45-degree line — 50 pixels, every one of them touching its neighbours only at a
    /// corner, so it is 49 consecutive shared vertices. The worst case the app can actually produce:
    /// a diagonal ink wall inside a lasso fill traces to exactly this.
    private func diagonalInkWall(offsetX: Int, offsetY: Int) -> Mask {
        var mask = blank(64, 64)
        for i in 0..<50 { mask.bits[(offsetY + i) * 64 + offsetX + i] = true }
        return mask
    }

    private func rectangle(offsetX: Int, offsetY: Int) -> Mask {
        var mask = blank(64, 64)
        for y in 0..<30 { for x in 0..<20 { mask.bits[(offsetY + y) * 64 + offsetX + x] = true } }
        return mask
    }

    private func disc(offsetX: Int, offsetY: Int) -> Mask {
        var mask = blank(80, 80)
        let cx = Double(offsetX) + 30, cy = Double(offsetY) + 30
        for y in 0..<80 {
            for x in 0..<80 {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= 400 { mask.bits[y * 80 + x] = true }
            }
        }
        return mask
    }

    /// A square with a square hole — the winding case, so a hole that stopped being subtracted shows
    /// up as an area error rather than passing quietly.
    private func squareWithAHole(offsetX: Int, offsetY: Int) -> Mask {
        var mask = blank(80, 80)
        for y in 0..<24 { for x in 0..<24 { mask.bits[(offsetY + y) * 80 + offsetX + x] = true } }
        for y in 8..<16 { for x in 8..<16 { mask.bits[(offsetY + y) * 80 + offsetX + x] = false } }
        return mask
    }

    /// The 24 places each fixture is traced from. Both coordinates vary, because `IntPoint`'s hash
    /// mixes them together and moving a shape along one axis alone is a weaker shuffle.
    private static let offsets: [(x: Int, y: Int)] = (0..<24).map { (x: 1 + $0 % 6, y: 1 + $0 / 6) }

    private typealias Fixture = (name: String, make: (Int, Int) -> Mask)

    private var pinchFixtures: [Fixture] {
        [(name: "two pixels at a corner", make: twoPixelsAtACorner),
         (name: "two 50x50 squares at a corner", make: twoSquaresAtACorner),
         (name: "50 px diagonal ink wall", make: diagonalInkWall)]
    }

    private var smoothFixtures: [Fixture] {
        [(name: "20x30 rectangle", make: rectangle),
         (name: "r=20 disc", make: disc),
         (name: "square with a hole", make: squareWithAHole)]
    }

    // MARK: - (0) The fixtures must contain the thing under test

    /// **Without this the rest of the file can quietly start measuring nothing.** The defect needs a
    /// vertex where the region touches itself corner to corner, and the *intuitive* fixtures do not
    /// have one: a sweep of smooth antialiased ellipses, Venn lenses, tapering slivers and
    /// set-differences of smooth shapes produced zero between them. A straight 45-degree boundary
    /// produces zero as well — every 2x2 along it holds one or three selected pixels, never two on a
    /// diagonal — which is why the diagonal fixture here is a one-pixel *line* and not an edge.
    func testEveryPinchFixtureActuallyContainsAPinchVertex() {
        let expected = ["two pixels at a corner": 1,
                        "two 50x50 squares at a corner": 1,
                        "50 px diagonal ink wall": 49]
        for fixture in pinchFixtures {
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                XCTAssertEqual(pinchCount(mask), expected[fixture.name],
                               "\(fixture.name) at \(offset) must contain the corner-touch this file exists to trace")
            }
        }
    }

    /// The other half of the guard: the controls must contain **no** pinch, or a green control would
    /// mean nothing and a red one would be ambiguous.
    func testEverySmoothFixtureContainsNoPinchVertex() {
        for fixture in smoothFixtures {
            for offset in Self.offsets {
                XCTAssertEqual(pinchCount(fixture.make(offset.x, offset.y)), 0,
                               "\(fixture.name) at \(offset) is a control and must not pinch")
            }
        }
    }

    // MARK: - (1) Area conservation

    private func assertAreaIsConserved(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        for offset in Self.offsets {
            let mask = fixture.make(offset.x, offset.y)
            guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                return XCTFail("\(fixture.name) at \(offset) traced to no path at all", file: file, line: line)
            }
            XCTAssertEqual(tracedArea(path), Double(mask.popcount), accuracy: 0,
                           "\(fixture.name) at \(offset): the traced path encloses a different number of "
                           + "pixels than the mask selected", file: file, line: line)
        }
    }

    func testTwoPixelsSharingACornerKeepBothPixels() {
        assertAreaIsConserved(pinchFixtures[0])
    }

    func testTwoSquaresSharingACornerKeepEveryPixelOfBoth() {
        assertAreaIsConserved(pinchFixtures[1])
    }

    func testADiagonalInkWallKeepsEveryPixelOfTheWall() {
        assertAreaIsConserved(pinchFixtures[2])
    }

    /// The control. These have no shared corner, so they were correct before the multimap and must
    /// stay correct after it — without them a suite that had simply broken tracing outright would
    /// look just as green as one that fixed it.
    func testSmoothRegionsKeepTheirAreaToo() {
        for fixture in smoothFixtures { assertAreaIsConserved(fixture) }
    }

    // MARK: - (2) The round trip — the honest assertion

    /// Rasterizing the traced path must reproduce the mask **byte for byte**. This is the assertion
    /// that means "the fill still looks like itself"; area conservation can be satisfied by a shape
    /// that lost a wedge here and gained one there.
    func testTracedPathRasterizesBackToTheMaskExactly() {
        for fixture in pinchFixtures + smoothFixtures {
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                    XCTFail("\(fixture.name) at \(offset) traced to no path at all")
                    continue
                }
                let painted = rasterized(path, width: mask.width, height: mask.height)
                let wrong = zip(painted, mask.bits).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
                XCTAssertEqual(wrong, 0, "\(fixture.name) at \(offset): \(wrong) px differ between the mask "
                               + "and its own traced contour")
            }
        }
    }

    // MARK: - (3) No straight-line chords

    /// The owner's screenshot in one assertion. A pixel mask's boundary is unit axis steps and
    /// nothing else, so the traced path can contain no diagonal segment; a walk that dead-ends
    /// leaves one when `fillPath` closes the open subpath, and *that* is the wedge in the evidence.
    func testNoTracedSegmentIsDiagonal() {
        for fixture in pinchFixtures + smoothFixtures {
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                    XCTFail("\(fixture.name) at \(offset) traced to no path at all")
                    continue
                }
                XCTAssertEqual(longestDiagonal(path), 0, accuracy: 0,
                               "\(fixture.name) at \(offset) closed a subpath with a chord")
            }
        }
    }

    // MARK: - (4) Structure

    /// Every subpath is explicitly closed. `fillPath` would close an open one implicitly, so this
    /// says nothing about the fill — it is about every *other* consumer of a `VectorFillElement`'s
    /// path, which is stroked, hit-tested, warped by the interpolator and cut by `CGPath`'s boolean
    /// operations.
    func testEverySubpathIsExplicitlyClosed() {
        for fixture in pinchFixtures + smoothFixtures {
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                    XCTFail("\(fixture.name) at \(offset) traced to no path at all")
                    continue
                }
                var moves = 0, closes = 0
                path.applyWithBlock { element in
                    if element.pointee.type == .moveToPoint { moves += 1 }
                    if element.pointee.type == .closeSubpath { closes += 1 }
                }
                XCTAssertEqual(moves, closes,
                               "\(fixture.name) at \(offset): \(moves) subpaths but \(closes) closes")
            }
        }
    }

    /// At a shared corner the walk stays on the pixel it arrived on, so two regions touching at a
    /// point trace to two simple loops rather than one figure-of-eight through the corner. Both fill
    /// identically; the separated loops are the better input to the boolean path operations
    /// `VectorCanvas` splits a fill with.
    ///
    /// Pinned only on these fixtures, and that limit is real rather than laziness: a walk that has
    /// to *begin* at a shared corner has no arrival direction to answer from, so a mask riddled with
    /// them still produces some self-touching loops. It is a tidiness rule, not an invariant.
    func testTouchingRegionsTraceToSeparateLoops() {
        let expected = ["two pixels at a corner": 2,
                        "two 50x50 squares at a corner": 2,
                        "50 px diagonal ink wall": 50]
        for fixture in pinchFixtures {
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                    XCTFail("\(fixture.name) at \(offset) traced to no path at all")
                    continue
                }
                XCTAssertEqual(rings(path).count, expected[fixture.name],
                               "\(fixture.name) at \(offset) should trace to one loop per touching region")
                for ring in rings(path) {
                    XCTAssertEqual(Set(ring.map { "\(Int($0.x)),\(Int($0.y))" }).count, ring.count,
                                   "\(fixture.name) at \(offset) traced a loop that visits a vertex twice")
                }
            }
        }
    }

    /// A straight run of pixel edges is one segment, not one segment per pixel. `simplifyCollinear`
    /// is what does it, and nothing else in this file notices if it stops: the shape, the area and
    /// the closure are all identical either way. What changes is size — the two-square fixture is 8
    /// points with it and 400 without — and a `VectorFillElement` stores its path in the document,
    /// so an unsimplified contour is paid for on every save, load and interpolation of that fill.
    func testStraightRunsCollapseToASingleSegment() {
        for offset in Self.offsets {
            let box = rectangle(offsetX: offset.x, offsetY: offset.y)
            guard let boxPath = PixelOps.contourPath(selected: box.bits, width: box.width, height: box.height) else {
                XCTFail("the rectangle at \(offset) traced to no path at all")
                continue
            }
            XCTAssertEqual(rings(boxPath).map(\.count), [4],
                           "a 20x30 rectangle is four corners, not one point per boundary pixel")
        }
        // The general statement, over every fixture: no three consecutive points are collinear.
        for fixture in pinchFixtures + smoothFixtures {
            let mask = fixture.make(1, 1)
            guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                XCTFail("\(fixture.name) traced to no path at all")
                continue
            }
            for ring in rings(path) {
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count], c = ring[(i + 2) % ring.count]
                    let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
                    XCTAssertNotEqual(cross, 0, "\(fixture.name) kept a redundant point at \(b)")
                }
            }
        }
    }

    // MARK: - (5) The trace is a function of the mask alone

    /// **The same shape must trace to the same path wherever it sits on the canvas.** Loops used to
    /// start at `remaining.keys.first`, and `IntPoint`'s hash seed is randomised per process, so the
    /// traced path — and, while the defect above was live, the traced *area* — differed on every
    /// launch of the app. That is what made the owner's report unreproducible: the same drawing
    /// corrupted somewhere else each time it was opened.
    ///
    /// Translating the fixture is what makes this testable at all. Two calls with the *same* mask in
    /// one process take the same dictionary order and agree however broken the code is; two calls
    /// with the mask moved by a pixel do not, because the vertices hash to different buckets.
    /// Measured across these 24 offsets: 11 to 24 distinct paths for one shape before, 1 after.
    func testTheSameShapeTracesIdenticallyWhereverItSits() {
        for fixture in pinchFixtures + smoothFixtures {
            var keys = Set<String>()
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else {
                    XCTFail("\(fixture.name) at \(offset) traced to no path at all")
                    continue
                }
                keys.insert(shapeKey(path, offsetX: offset.x, offsetY: offset.y))
            }
            XCTAssertEqual(keys.count, 1,
                           "\(fixture.name) traced to \(keys.count) different paths depending only on where "
                           + "it sat — the walk is reading dictionary order")
        }
    }

    /// And the total area is stable across those offsets too, stated separately because it is the
    /// weaker claim that survives if the decomposition rule above is ever relaxed.
    func testTheSameShapeAlwaysTracesToTheSameArea() {
        for fixture in pinchFixtures + smoothFixtures {
            var areas = Set<Double>()
            for offset in Self.offsets {
                let mask = fixture.make(offset.x, offset.y)
                guard let path = PixelOps.contourPath(selected: mask.bits, width: mask.width, height: mask.height) else { continue }
                areas.insert(tracedArea(path))
            }
            XCTAssertEqual(areas.count, 1, "\(fixture.name) traced to \(areas.sorted()) — the area a fill "
                           + "covers depends on where it was drawn")
        }
    }

    // MARK: - (6) Through `pathFromAlphaMask`, the entry point the fill actually calls

    /// `CanvasManager.commitInteractiveFill` reaches `contourPath` only through this, and it applies
    /// the coverage cut on the way. A mask handed in as premultiplied RGBA must trace to the same
    /// area as the boolean mask it thresholds to.
    func testPathFromAlphaMaskConservesAreaThroughTheCoverageCut() {
        for offset in Self.offsets {
            let mask = twoSquaresAtACorner(offsetX: offset.x, offsetY: offset.y)
            var bytes = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
            for i in mask.bits.indices where mask.bits[i] {
                bytes[i * 4 + 0] = 200; bytes[i * 4 + 1] = 0; bytes[i * 4 + 2] = 0; bytes[i * 4 + 3] = 200
            }
            let path = try? XCTUnwrap(PixelOps.pathFromAlphaMask(bytes: bytes, width: mask.width,
                                                                 height: mask.height, minimumAlpha: 100))
            guard let path else { return XCTFail("pathFromAlphaMask returned nothing at \(offset)") }
            XCTAssertEqual(tracedArea(path), Double(mask.popcount), accuracy: 0,
                           "the fill's own entry point lost area at \(offset)")
        }
    }

    // MARK: - (7) Cold start: two lasso fills on a vector layer

    /// **The reachability test — from a new document, with no state a fixture had to construct.**
    /// Everything above is about a helper; this is about whether the artist gets the fix. It is the
    /// owner's report performed exactly: line art, a lasso fill, a *second* lasso fill somewhere
    /// else, and then a look at what became of the first one.
    ///
    /// The first fill is what breaks, and this is the mechanism the owner reasoned their way to from
    /// behaviour alone. Until the second gesture starts, fill one is on screen as `cel.fillImage` —
    /// the exact GPU mask bytes. `beginInteractiveLassoFill` calls `beginCanvasEdit`, which calls
    /// `commitInteractiveFill`, which clears that preview and traces the mask into a
    /// `VectorFillElement`. So the second fill is what *bakes* the first, and the bake is the lossy
    /// step. The owner had the cause the other way round and the observation exactly right.
    ///
    /// The line art is two squares meeting at a corner because the lasso fill paints the stencil
    /// minus everything its collar can walk to: the collar cannot enter ink, so the filled region
    /// **is** those two squares, and it therefore carries the corner-touch this file is about. That
    /// is asserted, not assumed — an end-to-end test whose region happens not to pinch would sail
    /// through on the broken code.
    func testASecondLassoFillOnAVectorLayerLeavesTheFirstOneIntact() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, inkTouchingAtACorner())
        manager.addVectorLayer()
        let vectorIndex = manager.layers.count - 1
        XCTAssertEqual(manager.currentLayerIndex, vectorIndex, "the new vector layer is the active one")
        manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        // Gap Closing dilates the walls the collar cannot cross, and it defaults to 8 px — which on a
        // 64 px fixture canvas bridges two 10 px squares into one blob and takes the corner-touch
        // with it. The guard below caught exactly that on the first run of this test. 0 is a setting
        // the Fill panel offers, and it is the one under which the fill traces the artist's ink.
        manager.setFillSetting(.gapClosing, 0)

        // --- the artist's first lasso, around both squares ---
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 4, y: 4, width: 34, height: 34)))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        settle()

        let regionBytes = try XCTUnwrap(manager.fillLastRegionRGBA, "the first lasso previewed nothing")
        let regionW = manager.fillLastRegionW, regionH = manager.fillLastRegionH
        let cut = manager.fillHalfCoverageAlpha
        let firstMask = Mask(bits: (0..<(regionW * regionH)).map { regionBytes[$0 * 4 + 3] >= cut },
                             width: regionW, height: regionH)

        XCTAssertGreaterThan(firstMask.popcount, 0, "the first lasso filled nothing at all")
        XCTAssertGreaterThan(pinchCount(firstMask), 0,
                             "the filled region has no corner-touch in it, so this test cannot see the defect "
                             + "— the fixture stopped measuring what it was written for. It covers "
                             + "\(firstMask.popcount) px of \(regionW)x\(regionH); the two ink squares are 200.")

        // --- the artist's second lasso, elsewhere; this is what bakes the first ---
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 40, y: 40, width: 20, height: 20)))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        settle()

        let celIndex = try XCTUnwrap(manager.activeCelIndex(inLayer: vectorIndex, atFrame: manager.currentFrame))
        let vector = try XCTUnwrap(manager.layers[vectorIndex].cels[celIndex].vector,
                                   "the vector layer's cel holds no VectorCanvas")
        let first = try XCTUnwrap(vector.fills.first, "the first fill was never committed as an element")
        let path = try XCTUnwrap(first.cgPath, "the committed fill has no path")

        XCTAssertEqual(tracedArea(path), Double(firstMask.popcount), accuracy: 0,
                       "the first fill lost \(Double(firstMask.popcount) - tracedArea(path)) px of the "
                       + "\(firstMask.popcount) px it covered when the second fill baked it")
        XCTAssertEqual(longestDiagonal(path), 0, accuracy: 0,
                       "the committed fill has a straight-line chord across it — the owner's screenshot")
    }

    /// Two 10x10 squares of opaque ink sharing the corner at (20, 20), on the 64x64 fixture canvas.
    /// Hard-edged on integer bounds, so the fill's coverage cut has no antialiased fringe to round.
    private func inkTouchingAtACorner() -> UIImage {
        UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            ctx.cgContext.setShouldAntialias(false)
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
            ctx.fill(CGRect(x: 20, y: 20, width: 10, height: 10))
        }
    }

    private func rectangleLoop(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        path.closeSubpath()
        return path
    }

    /// Pumps the main run loop long enough for a `fillQueue` render's main-thread hop to land — the
    /// same helper `FillGestureRestartLogicTests` and `LassoFillLogicTests` both use.
    private func settle(_ seconds: TimeInterval = 0.5) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }
}
