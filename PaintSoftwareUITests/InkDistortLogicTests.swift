import XCTest
import QuartzCore
import UIKit

/// **Distort on ink — TODO item (12), LASSO_MOVE.md §3 stage 5's second half.**
///
/// The raster tier shipped 2026-09-02 and refused a lassoed *drawing*, on a measurement: a
/// homography's local scale spans 1.3×–8.5× across one quad, so no single `VectorStroke.size` is
/// right and the best available scalar is wrong by 15%–315%. **That refusal outlived its own
/// argument by four days.** KEYFRAMES.md §8 stage 4 merged on 2026-09-02 and gave
/// `BrushStamper.DabPose` a `Homography`, `localScale` and `rotation` answered **per dab**, and
/// `PosedDabTarget` in the shipped render — so there is no single scalar on that path to be wrong.
///
/// **So the assertion this file exists for is the per-dab one**, and it is the one that can go red:
/// every dab of a keystoned stroke is stamped at the rest dab's radius times the map's local scale at
/// the *rest dab's own centre*, and the two ends of one stroke therefore differ. An implementation
/// that took the scale once — at the midpoint, at the centroid, out of `sqrt(|det|)` — passes every
/// geometry assertion in the suite and fails that one.
///
/// The rest is the shape of the gesture: the corner goes where the finger is and the other three do
/// not move, an undrawable quad is refused rather than clamped, the residue composes under a later
/// Move / turn / scale / Mirror, and Reset clears it.
///
/// Pure logic, no simulator. `DistortUITests` is what says a corner handle takes the drag.
final class InkDistortLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let ink = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// A straight stroke from `from` to `to`.
    ///
    /// **Diagonal by default, and that is the fixture rather than a style.** `keystone()`'s
    /// perspective is in `y` alone (`g == 0`), so the homogeneous weight `h·y + 1` is *constant* along
    /// a horizontal line — a horizontal stroke under it magnifies by the same factor at both ends and
    /// there is nothing for a per-dab assertion to be about. KEYFRAMES.md §8 measured its own
    /// 1.3×/8.5× spread along a diagonal for the same reason.
    private func stroke(from: CGPoint = CGPoint(x: 60, y: 100),
                        to: CGPoint = CGPoint(x: 340, y: 320),
                        count: Int = 15, size: CGFloat = 20) -> VectorStroke {
        let dx = (to.x - from.x) / CGFloat(count - 1), dy = (to.y - from.y) / CGFloat(count - 1)
        return VectorStroke(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                            brush: TestBrushes.hardRound, color: Self.ink, size: size, opacity: 1,
                            samples: StrokeSamples((0..<count).map {
                                VectorSample(x: from.x + CGFloat($0) * dx,
                                             y: from.y + CGFloat($0) * dy, pressure: 1)
                            }, channels: .pressureOnly))
    }

    /// A keystone over the 400×400 canvas: the top edge pulled in on both sides, so the map magnifies
    /// strongly at the bottom and shrinks at the top. Built by solving a known box onto a known quad
    /// so that every assertion's two operands are exact.
    private func keystone(inset: CGFloat = 120) -> Homography {
        let box = CGRect(x: 0, y: 0, width: 400, height: 400)
        let quad = Quad(CGPoint(x: inset, y: 0), CGPoint(x: 400 - inset, y: 0),
                        CGPoint(x: 400, y: 400), CGPoint(x: 0, y: 400))
        return Homography(rect: box, to: quad)!
    }

    /// The dabs the **shipped render path** stamped for `elements` — `VectorCanvas.render` →
    /// `renderLocalContent` → `draw(stroke:)` → `stamp` → `CGContextDabTarget`, with `DabProbe` on the
    /// last of those. Nothing here re-derives `stamp`'s dispatch.
    private func stamped(_ elements: [VectorElement]) -> [DabProbe.Dab] {
        DabProbe.begin()
        _ = VectorCanvas(size: CGSize(width: 400, height: 400), elements: elements).render(quality: .full)
        return DabProbe.end()
    }

    override func tearDown() {
        // A probe left armed by a test that threw would collect another suite's dabs — the restore
        // rule `Compositor.backend` gets, and `DabProbe` is process-wide in exactly that way.
        DabProbe.end()
        super.tearDown()
    }

    // MARK: - The refusal, and what is left of it

    /// **Ink is offered and only a placed image or a video is refused.**
    ///
    /// The sentence this replaces — *"Distort needs a pixel selection — not available on a lassoed
    /// drawing yet"* — was true when it was written and false when it shipped. What is refused now is
    /// a *kind*: `VectorImageElement` and `VectorVideoElement` store six numbers and a mirror bit
    /// where a homography needs eight, so there is nowhere for the projective residue to live.
    ///
    /// **Per float and not per kind**, which is stage 3c's ruling: a float carrying a photo almost
    /// always carries ink beside it, and refusing the ink but not the photo would be the per-kind
    /// refusal that stage deleted.
    func testDistortIsOfferedOnInkAndRefusedOnlyForAPlacedImageOrAVideo() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let index = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[index].cels[0].vector)
        vector.addStroke(stroke(from: CGPoint(x: 16, y: 32), to: CGPoint(x: 48, y: 40),
                                count: 4, size: 4))
        manager.setTransformMode(.distort)
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: a vector float holding ink")

        XCTAssertNil(manager.distortUnavailableReason,
                     "the rest-space dab bake shipped 2026-09-02 and the refusal's own argument went with it")
        XCTAssertTrue(manager.vectorFloatIsDistort, "so a corner grip means Distort")

        manager.cancelVectorFloat()
        vector.addImage(VectorImageElement(id: UUID(), image: CanvasFixture.solidImage(.red,
                                                                                         rect: CGRect(x: 0, y: 0, width: 8, height: 8)),
                                              transform: LayerTransform(position: CGPoint(x: 32, y: 32),
                                                                        scale: 1, rotation: 0)))
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: the same float, now carrying a photo")
        let reason = try XCTUnwrap(manager.distortUnavailableReason,
                                   "a placed image has six numbers and a mirror bit where a homography needs eight")
        XCTAssertTrue(reason.contains("image"), "and the sentence names the kind in the way: \(reason)")
        XCTAssertFalse(manager.vectorFloatIsDistort, "so a corner grip goes on scaling")

        manager.setTransformMode(.uniform)
        XCTAssertNil(manager.distortUnavailableReason, "the caption is about the mode as well as the piece")
    }

    // MARK: - The engine: per-dab width is the whole point

    /// **Every dab takes its own local scale, and the two ends of one stroke differ because of it.**
    ///
    /// This is the assertion the four-day-stale refusal was about. The radius is checked *per dab*
    /// against `localScale` at that dab's own rest centre, so an implementation that resolved one
    /// number for the stroke — the midpoint linearisation, `sqrt(|det|)` of anything, the mean —
    /// fails it at both ends however good that number is.
    ///
    /// The second assertion is what makes the first non-vacuous: the extreme radii differ by a factor
    /// this fixture MEASURES, so "every dab is the same radius" cannot also satisfy the first.
    func testEveryDabOfAKeystonedStrokeTakesTheLocalScaleAtItsOwnRestCentre() throws {
        let ink = stroke()
        let map = keystone()
        let posed = try XCTUnwrap(VectorCanvas.posing(.stroke(ink), through: map))
        let rest = stamped([.stroke(ink)])
        let dabs = stamped([posed])

        XCTAssertEqual(dabs.count, rest.count,
                       "the walk happens once, in rest space — the pose moves finished dabs and mints none")
        XCTAssertGreaterThan(dabs.count, 20, "setup: enough dabs for the two ends to be far apart")

        var minRadius = CGFloat.infinity, maxRadius: CGFloat = 0
        for (restDab, posedDab) in zip(rest, dabs) {
            let scale = try XCTUnwrap(map.localScale(at: restDab.center),
                                      "no rest dab of this stroke is on the vanishing line")
            let centre = try XCTUnwrap(map.map(restDab.center))
            XCTAssertEqual(posedDab.center.x, centre.x, accuracy: 1e-9)
            XCTAssertEqual(posedDab.center.y, centre.y, accuracy: 1e-9)
            XCTAssertEqual(posedDab.radius, restDab.radius * scale, accuracy: 1e-9,
                           "dab at \(restDab.center) took a scale that is not its own")
            minRadius = min(minRadius, posedDab.radius)
            maxRadius = max(maxRadius, posedDab.radius)
        }
        // MEASURED for this fixture: a 120 pt inset over a 400 pt box, sampled along y = 200.
        XCTAssertGreaterThan(maxRadius / minRadius, 1.15,
                             "if the two ends came out the same width there would be nothing to assert above")
    }

    /// **The posed copy carries the artist's own walk, not the walk of its own posed spine.**
    ///
    /// KEYFRAMES.md §4.2's whole construction: the dab lattice is laid once where the stroke was
    /// drawn, and the pose touches only each finished dab. A copy that re-walked its posed samples
    /// would re-derive spacing and the square brush's sub-lattice per map, which is the boil that
    /// stage 4 removed — and under a *projective* map it would also re-derive them at a width that
    /// varies along the line.
    func testAKeystonedStrokeKeepsTheArtistsOwnRestWalk() throws {
        let ink = stroke()
        let map = keystone()
        guard case .stroke(let posed) = try XCTUnwrap(VectorCanvas.posing(.stroke(ink), through: map))
        else { return XCTFail("a stroke poses to a stroke") }

        let walk = try XCTUnwrap(posed.restWalk, "a projective pose attaches the walk it was laid on")
        XCTAssertEqual(walk.samples.positions, ink.samples.positions, "the artist's own points")
        XCTAssertEqual(walk.size, ink.size, "and the artist's own width")
        XCTAssertEqual(walk.pose.map, map, "and the whole map, projective row included")
        XCTAssertNil(walk.pose.constantScale,
                     "which is the flag that makes `DabPose.scale(at:)` ask per dab")
        XCTAssertNotEqual(posed.samples.positions, ink.samples.positions,
                          "while the display list itself is posed — every bounds and index reader believes it")
    }

    /// **A second Distort composes onto the first rather than replacing it.**
    ///
    /// The failure this guards is silent and total: overwriting the walk would claim the *posed* spine
    /// as the artist's own and re-lay the dabs on it, throwing away the first keystone's per-dab width
    /// while leaving a picture that still looks distorted. Two poses in sequence must be the product.
    func testASecondKeystoneComposesOntoTheFirst() throws {
        let ink = stroke()
        let first = keystone(inset: 60), second = keystone(inset: 100)
        let once = try XCTUnwrap(VectorCanvas.posing(.stroke(ink), through: first))
        let twice = try XCTUnwrap(VectorCanvas.posing(once, through: second))
        guard case .stroke(let composed) = twice else { return XCTFail("a stroke poses to a stroke") }

        let walk = try XCTUnwrap(composed.restWalk)
        XCTAssertEqual(walk.samples.positions, ink.samples.positions,
                       "still the artist's own points, two poses later")
        let product = second * first
        // A homography is defined up to scale, so the claim is about the *map*: every rest sample
        // lands where the product puts it.
        for point in ink.samples.positions {
            let viaWalk = try XCTUnwrap(walk.pose.map.map(point))
            let viaProduct = try XCTUnwrap(product.map(point))
            XCTAssertEqual(viaWalk.x, viaProduct.x, accuracy: 1e-9)
            XCTAssertEqual(viaWalk.y, viaProduct.y, accuracy: 1e-9)
        }
        XCTAssertEqual(stamped([twice]).count, stamped([.stroke(ink)]).count,
                       "and the walk is still the one the artist drew, so the dab count has not moved")
    }

    /// **A map that is an affine takes the affine path, bit for bit.**
    ///
    /// `Homography.affine()`'s default tolerance is exact zero, which makes this a decision rather
    /// than a threshold: a homography built from a `CGAffineTransform` has `g == h == 0` exactly, and
    /// so does one solved for a quad inside `init(boxSize:to:)`'s parallelogram tolerance. So a
    /// Distort dragged back to a parallelogram is the Freeform document it would have been.
    func testTheProjectiveEntryPointIsTheAffineOneWheneverTheMapIsAffine() throws {
        let ink = stroke()
        let affine = CGAffineTransform(translationX: 12, y: -5).rotated(by: 0.3).scaledBy(x: 1.7, y: 0.4)
        guard case .stroke(let viaAffine) = VectorCanvas.posing(.stroke(ink), through: affine),
              case .stroke(let viaProjective) = try XCTUnwrap(VectorCanvas.posing(.stroke(ink),
                                                                                  through: Homography(affine)))
        else { return XCTFail("both arms answer with a stroke") }

        XCTAssertEqual(viaProjective.samples.positions, viaAffine.samples.positions)
        XCTAssertEqual(viaProjective.size, viaAffine.size,
                       "including `sqrt(|det|)` into the size rather than a per-dab envelope")
        XCTAssertEqual(viaProjective.restWalk?.pose, viaAffine.restWalk?.pose)

        // And a quad that *is* a parallelogram solves to exact zeros, so it lands here too.
        let box = CGRect(x: -50, y: -20, width: 100, height: 40)
        let sheared = Quad(CGPoint(x: -40, y: -20), CGPoint(x: 60, y: -20),
                           CGPoint(x: 40, y: 20), CGPoint(x: -60, y: 20))
        let solved = try XCTUnwrap(Homography(rect: box, to: sheared))
        XCTAssertNotNil(solved.affine(), "a parallelogram is an affine and is answered as one")
    }

    /// **A placed image and a video decline rather than being carried wrong**, which is what
    /// `distortUnavailableReason` is built on. A `LayerTransform` plus `aspect`, `stretchAxis` and a
    /// mirror bit is six numbers and a sign; a homography is eight.
    func testAPlacedImageAndAVideoDeclineAProjectiveMap() throws {
        let image = VectorImageElement(id: UUID(),
                                       image: CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 8, height: 8)),
                                       transform: LayerTransform(position: CGPoint(x: 40, y: 40),
                                                                 scale: 1, rotation: 0))
        let video = VectorVideoElement(assetURL: URL(fileURLWithPath: "/dev/null"),
                                       assetFileName: "null",
                                       naturalSize: CGSize(width: 32, height: 18),
                                       sourceStart: .zero,
                                       sourceEnd: SourceTime(value: 1, timescale: 1), speed: 1,
                                       transform: LayerTransform(position: CGPoint(x: 40, y: 40),
                                                                 scale: 1, rotation: 0))
        XCTAssertNil(VectorCanvas.posing(.image(image), through: keystone()))
        XCTAssertNil(VectorCanvas.posing(.video(video), through: keystone()))
        XCTAssertTrue(VectorCanvas.refusesDistort(.image(image)))
        XCTAssertTrue(VectorCanvas.refusesDistort(.video(video)))
        XCTAssertFalse(VectorCanvas.refusesDistort(.stroke(stroke())))
        // And an *affine* still carries both, which is what says this is a refusal of the projective
        // row rather than of the kind: `mapping(_:throughStretch:)`'s image arm is untouched.
        XCTAssertNotNil(VectorCanvas.posing(.image(image),
                                            through: Homography(CGAffineTransform(scaleX: 2, y: 3))))
    }

    /// **The scalar a distorted stroke stores never understates its own footprint.**
    ///
    /// `VectorStroke.size` stops being the ink's width under a projective map — the dabs take
    /// `localScale` per dab — but it is still what `MoveBoxInk`, `localBounds`, the spatial index and
    /// the eraser's candidacy test pad by. An under-estimate there is ink outside the damage
    /// rectangle, which is a stale pixel nothing repairs, so the envelope is the **maximum** over the
    /// stroke rather than the value at its middle or its mean.
    func testTheStoredWidthOfAKeystonedStrokeIsAnUpperBoundOnItsFootprint() throws {
        let ink = stroke()
        let map = keystone()
        guard case .stroke(let posed) = try XCTUnwrap(VectorCanvas.posing(.stroke(ink), through: map))
        else { return XCTFail("a stroke poses to a stroke") }

        var widest: CGFloat = 0
        for point in ink.samples.positions {
            widest = max(widest, try XCTUnwrap(map.localScale(at: point)))
        }
        XCTAssertEqual(posed.size, ink.size * widest, accuracy: 1e-12)
        for point in ink.samples.positions {
            let here = try XCTUnwrap(map.localScale(at: point))
            XCTAssertGreaterThanOrEqual(posed.size + 1e-12, ink.size * here,
                                        "the stored width has to cover every dab, not the average one")
        }
        // Non-vacuous: the midpoint's own scale would not have covered the wide end.
        let middle = try XCTUnwrap(map.localScale(at: ink.samples.positions[ink.samples.positions.count / 2]))
        XCTAssertLessThan(middle, widest, "setup: the scale genuinely varies along this stroke")
    }

    /// **A Pencil's azimuth turns by the map's rotation *at its own point*.**
    ///
    /// BRUSH.md §2.7 stores azimuth in the samples' own space, so a map that turns the ink has turned
    /// the nib with it — and a homography's local rotation genuinely varies across the plane, which is
    /// what makes a receding checkerboard's squares lean differently near and far. One angle for the
    /// whole run would be right in the middle and wrong at both ends.
    func testAPencilsAzimuthTurnsByTheMapsRotationAtItsOwnPoint() throws {
        var ink = stroke(count: 9)
        ink.samples.setChannel(.tiltAzimuth, to: Array(repeating: 0, count: ink.samples.positions.count))
        let map = keystone()
        let moved = try XCTUnwrap(ink.samples.mapped(through: map))

        let turns = ink.samples.positions.map { map.linearised(at: $0)?.polarRotation ?? 0 }
        XCTAssertGreaterThan(try XCTUnwrap(turns.max()) - (try XCTUnwrap(turns.min())), 0.05,
                             "setup: this map really does turn the two ends differently")
        for (index, expected) in turns.enumerated() {
            XCTAssertEqual(moved.storedValues(.tiltAzimuth)[index],
                           SampleChannel.tiltAzimuth.rotated(0, by: expected), accuracy: 1e-9)
        }
    }

    /// **Every handle but the Distort corner carries the keystone through untouched**, which is what
    /// makes a Move, a scale, a turn, a Freeform and a box turn compose over a distort rather than
    /// flatten it. An arm that dropped `distort` on its way out of `pose(draggedTo:)` would un-keystone
    /// the artist's drawing on their next drag, silently.
    func testEveryHandleButTheDistortCornerPassesTheKeystoneThrough() throws {
        let plain = Self.box()
        let stored = BoxDistort(quad: Self.pulled(plain), boxSize: plain.contentSize,
                                boxOffset: plain.contentOffset, boxAngle: 0)
        let frame = plain.distortFrame(stored)
        let start = CGPoint(x: frame.centre.x + 20, y: frame.centre.y + 10)
        for handle in ObjectTransformFrame.Handle.allCases {
            for freeform in [false, true] {
                let drag = ObjectTransformDrag(frame: frame, handle: handle, at: start,
                                               freeform: freeform, distort: false)
                let pose = drag.pose(draggedTo: CGPoint(x: start.x + 25, y: start.y - 15))
                XCTAssertEqual(pose.distort, stored,
                               "\(handle) with freeform=\(freeform) dropped the residue")
            }
        }
    }

    /// **The fit is frozen at the distort's own box**, so the corners the artist grabs and the corners
    /// the ink is warped onto are one value. Everything `fittedFrame` otherwise does is measure an
    /// axis-aligned hull of the ink in the box's frame, and a keystoned box is not a rectangle in any
    /// frame — so there is nothing left for it to hug.
    func testTheFittedBoxIsFrozenAtTheDistortsOwnBox() throws {
        let float = try Self.float()
        let stored = BoxDistort(quad: Self.pulled(Self.box(size: float.contentSize,
                                                           at: float.frame.transform.position)),
                                boxSize: float.contentSize, boxOffset: CGPoint(x: 3, y: -4),
                                boxAngle: 0.4)
        var moved = float.frame.transform
        moved.position = CGPoint(x: moved.position.x + 30, y: moved.position.y)
        let pose = ObjectTransformDrag.Pose(transform: moved, aspect: 1, boxAngle: 1.1,
                                            stretchAxis: 0, distort: stored)
        let fitted = CanvasManager.fittedFrame(of: float, at: pose)

        XCTAssertEqual(fitted.contentSize, stored.boxSize)
        XCTAssertEqual(fitted.contentOffset, stored.boxOffset)
        XCTAssertEqual(fitted.boxAngle, stored.boxAngle,
                       "the frozen angle, not the pose's live one — LASSO_MOVE.md §5.21")
        XCTAssertEqual(fitted.distortQuad, stored.quad)
        XCTAssertEqual(fitted.transform, moved, "and it still travels with the piece")
    }

    /// **A fill is flattened before it is mapped, because a cubic's projective image is not a cubic.**
    ///
    /// `Homography.mapped(_:)` carries control points and says so; that is right for its own caller,
    /// whose paths are straight-segment lasso outlines. A fill can be a real curve, and the test is
    /// the one place the two answers differ: a point in the *middle* of the source curve. The
    /// flattened path passes within a fraction of a point of where the map puts it; the naive
    /// control-point map is off by far more.
    func testAFillsCurvesAreFlattenedSoTheirMiddlesLandWhereTheMapPutsThem() throws {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 40, y: 360))
        path.addCurve(to: CGPoint(x: 360, y: 360),
                      control1: CGPoint(x: 120, y: 40), control2: CGPoint(x: 280, y: 40))
        path.closeSubpath()
        let fill = VectorFillElement(path: path, color: Self.ink)
        let map = keystone()

        guard case .fill(let mapped) = try XCTUnwrap(VectorCanvas.posing(.fill(fill), through: map)),
              let out = mapped.cgPath else { return XCTFail("a fill poses to a fill") }

        // The source curve's own midpoint, and where the map sends it.
        let source = CGPoint(x: (40 + 3 * 120 + 3 * 280 + 360) / 8.0,
                             y: (360 + 3 * 40 + 3 * 40 + 360) / 8.0)
        let target = try XCTUnwrap(map.map(source))
        XCTAssertLessThan(Self.distance(from: target, to: out), 0.5,
                          "the flattened image passes through the map's own answer")

        var raw = map
        let naive = try XCTUnwrap(raw.mapped(path), "the control-point map, for comparison")
        _ = raw
        XCTAssertGreaterThan(Self.distance(from: target, to: naive), 4,
                             "which the un-flattened one does not — this is what the flatten buys")
    }

    /// **Text corners are carried exactly**, and that is a theorem rather than a tolerance: a
    /// homography is determined by four correspondences, so the box→corners map of the mapped quad is
    /// identically this map composed with the box→corners map of the original.
    func testTextCornersComposeExactlyUnderAKeystone() throws {
        let recipe = TextRecipe(string: "abc")
        let frame = TextFrame(origin: CGPoint(x: 100, y: 100), size: CGSize(width: 120, height: 40))
        let element = VectorTextElement(id: UUID(), recipe: recipe, frame: frame)
        let map = keystone()

        guard case .text(let moved) = try XCTUnwrap(VectorCanvas.posing(.text(element), through: map))
        else { return XCTFail("text poses to text") }

        XCTAssertEqual(moved.frame.size, frame.size,
                       "the layout box is unchanged — the words wrap identically and the corners carry the shape")
        XCTAssertEqual(moved.frame.mode, .projective)
        XCTAssertFalse(moved.frame.autoSize, "a box whose corners were placed by hand is authoritative")
        for (before, after) in zip(frame.corners, moved.frame.corners) {
            let expected = try XCTUnwrap(map.map(before))
            XCTAssertEqual(after.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(after.y, expected.y, accuracy: 1e-9)
        }

        // The composition claim, stated on the maps rather than on the corners: solving the mapped
        // quad and solving the original then applying `map` agree at an interior point.
        let solvedBefore = try XCTUnwrap(Homography(boxSize: frame.size,
                                                    to: try XCTUnwrap(Quad(frame.corners))))
        let solvedAfter = try XCTUnwrap(Homography(boxSize: frame.size,
                                                   to: try XCTUnwrap(Quad(moved.frame.corners))))
        let probe = CGPoint(x: frame.size.width * 0.37, y: frame.size.height * 0.71)
        let viaProduct = try XCTUnwrap(map.map(try XCTUnwrap(solvedBefore.map(probe))))
        let viaSolve = try XCTUnwrap(solvedAfter.map(probe))
        XCTAssertEqual(viaSolve.x, viaProduct.x, accuracy: 1e-6)
        XCTAssertEqual(viaSolve.y, viaProduct.y, accuracy: 1e-6)
    }

    // MARK: - The box and the drag

    /// **The corner goes where the finger is and the other three do not move** — `TextFrameDrag`'s
    /// three rules and `FloatingDistortDrag`'s, on the third box in the app that offers them. The
    /// transform is `start` bit for bit, which is what makes a Move compose over a keystone.
    func testAPulledCornerGoesWhereTheFingerIsAndTheOtherThreeStay() throws {
        let frame = Self.box()
        let start = frame.corners
        let drag = ObjectTransformDrag(frame: frame, handle: .topLeft, at: start[0], distort: true)
        let target = CGPoint(x: start[0].x + 30, y: start[0].y + 10)
        let pose = drag.pose(draggedTo: target)

        let quad = try XCTUnwrap(pose.distort?.quad)
        let moved = frame.distortFrame(try XCTUnwrap(pose.distort)).corners
        XCTAssertEqual(moved[0].x, target.x, accuracy: 1e-9)
        XCTAssertEqual(moved[0].y, target.y, accuracy: 1e-9)
        for index in 1..<4 {
            XCTAssertEqual(moved[index].x, start[index].x, accuracy: 1e-9)
            XCTAssertEqual(moved[index].y, start[index].y, accuracy: 1e-9)
        }
        XCTAssertEqual(pose.transform, frame.transform, "a Distort adds a residue and moves no affine")
        XCTAssertFalse(quad.isParallelogram(tolerance: 1e-6), "and the box really is keystoned now")
    }

    /// **A quad no homography can be drawn through is refused, and an un-distorted box that has only
    /// ever been dragged somewhere undrawable is still un-distorted when the finger lifts.**
    ///
    /// The second half is the one worth writing down. Clamping to the last valid quad — or answering
    /// with `startLocalQuad`, which is the rectangle — would stamp a `distortQuad` onto a box nobody
    /// distorted, and every `distort != nil` reader downstream (Reset's live-ness, the fit, the box
    /// knob's withdrawal) would believe it.
    func testAnUndrawableQuadIsRefusedAndLeavesAnUndistortedBoxAlone() throws {
        let frame = Self.box()
        let corners = frame.corners
        let drag = ObjectTransformDrag(frame: frame, handle: .topLeft, at: corners[0], distort: true)
        // Straight across the box's diagonal and out the far side: the quad self-crosses.
        let refused = drag.pose(draggedTo: CGPoint(x: corners[2].x + 40, y: corners[2].y + 40))
        XCTAssertNil(refused.distort, "nothing was distorted, so nothing is")
        XCTAssertEqual(refused.transform, frame.transform)

        // And once a valid quad exists, a refused delta answers with *that* rather than the rectangle.
        let good = try XCTUnwrap(drag.pose(draggedTo: CGPoint(x: corners[0].x + 20, y: corners[0].y)).distort)
        let onDistorted = frame.distortFrame(good)
        let second = ObjectTransformDrag(frame: onDistorted, handle: .topRight,
                                         at: onDistorted.corners[1], distort: true)
        let refusedAgain = second.pose(draggedTo: CGPoint(x: onDistorted.corners[3].x - 40,
                                                          y: onDistorted.corners[3].y + 40))
        XCTAssertEqual(refusedAgain.distort?.quad, good.quad, "the handle sticks at the last committed shape")
    }

    /// **The box knob is withdrawn while a distort stands.** A keystoned box is not a rectangle in any
    /// frame, so the knob whose whole job is to turn the rectangle the fit hugs has nothing to turn.
    /// Withdrawn from `allowedHandles` rather than left inert, so it is not drawn and not grabbable —
    /// a control that is gone needs no sentence, where one that does nothing does.
    func testTheBoxKnobIsWithdrawnWhileADistortStands() throws {
        let frame = Self.box()
        XCTAssertTrue(frame.allowedHandles.contains(.boxRotation), "setup: an ordinary box offers it")
        let distorted = frame.distortFrame(BoxDistort(quad: Self.pulled(frame), boxSize: frame.contentSize,
                                                      boxOffset: frame.contentOffset, boxAngle: 0))
        XCTAssertFalse(distorted.allowedHandles.contains(.boxRotation))
        XCTAssertNil(distorted.handleLayout(rotationOffset: 36).first { $0.handle == .boxRotation })
        XCTAssertNotNil(distorted.handleLayout(rotationOffset: 36).first { $0.handle == .rotation },
                        "the green knob turns the ink and is untouched")
    }

    /// **The residue's frame is frozen at the first pulled corner, so §5.21 survives**: a turn of the
    /// yellow knob is free — no undo step — on the argument that it moves no ink, and a box angle read
    /// *live* would put the knob inside the map and drag the artist's keystoned drawing.
    func testTheDistortMapCannotSeeALiveBoxAngle() throws {
        let float = try Self.float()
        let distort = BoxDistort(quad: Self.pulled(Self.box()), boxSize: float.contentSize,
                                 boxOffset: .zero, boxAngle: 0)
        let placement = VectorCanvas.affine(from: float.frame.transform, aspect: 1,
                                            stretchAxis: 0, pivot: float.pivot)
        let map = try XCTUnwrap(CanvasManager.distortMap(distort, transform: float.frame.transform,
                                                         aspect: 1, stretchAxis: 0,
                                                         placement: placement, mirror: .identity,
                                                         base: float.baseTransform))
        // The same call with a hand-turned box: the *live* angle is not a parameter of this function
        // at all, and the frozen one is what `BoxDistort` carries.
        var turned = distort
        turned.boxAngle = 0.7
        let other = try XCTUnwrap(CanvasManager.distortMap(turned, transform: float.frame.transform,
                                                           aspect: 1, stretchAxis: 0,
                                                           placement: placement, mirror: .identity,
                                                           base: float.baseTransform))
        XCTAssertNotEqual(map, other, "setup: the frozen angle really is in the map")
        // `turnVectorFloatBox` writes `frame.boxAngle` and never `distort.boxAngle`, which is the
        // whole guarantee — asserted through the manager in `testTurningTheBoxAfterADistort…` below.
    }

    // MARK: - Through the model

    /// **The first pulled corner moves no ink at all**, because the residue it seeds is the identity:
    /// the quad starts as the four corners of the box *as drawn*, so `Homography(rect:to:)` solves to
    /// the identity and the whole chain collapses to the affine one.
    ///
    /// This is the property that makes a Distort on a re-fitted or hand-turned box safe — the fit is
    /// chrome and must not map anything.
    func testSeedingADistortFromTheDrawnBoxChangesNoSample() throws {
        let manager = try Self.managerWithFloat()
        let float = try XCTUnwrap(manager.vectorFloat)
        let before = try XCTUnwrap(manager.vectorCanvas(ofFloat: float)).elements
        let drawn = CanvasManager.fittedFrame(of: float, at: ObjectTransformDrag.Pose(
            transform: float.frame.transform, aspect: float.frame.aspect,
            boxAngle: float.frame.boxAngle, stretchAxis: float.frame.stretchAxis, distort: nil))

        manager.nudgeVectorFloat(to: float.frame.transform,
                                 distort: .some(BoxDistort(quad: drawn.localQuad,
                                                           boxSize: drawn.contentSize,
                                                           boxOffset: drawn.contentOffset,
                                                           boxAngle: drawn.boxAngle)))
        let after = try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements
        assertSamePoints(Self.positions(after), Self.positions(before), accuracy: 1e-9)
        XCTAssertNotNil(manager.vectorFloat?.distort, "and the residue is on the model, ready to be pulled")
    }

    /// **Reset clears the keystone, and `canResetFloating` sees it.** A piece dragged back to the
    /// position, scale and rotation it lifted at but left with a pulled corner is not sitting where it
    /// was picked up — the raster arm's `distortQuad != nil` term, one tier over.
    func testResetClearsTheKeystoneAndTheButtonKnowsAboutIt() throws {
        let manager = try Self.managerWithFloat()
        let float = try XCTUnwrap(manager.vectorFloat)
        let before = try XCTUnwrap(manager.vectorCanvas(ofFloat: float)).elements
        XCTAssertFalse(manager.canResetFloating, "setup: nothing has moved yet")

        manager.nudgeVectorFloat(to: float.frame.transform,
                                 distort: .some(BoxDistort(quad: Self.pulled(float.frame),
                                                           boxSize: float.contentSize,
                                                           boxOffset: .zero, boxAngle: 0)))
        XCTAssertTrue(manager.canResetFloating, "a pulled corner is something to put back")
        let keystoned = try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements
        XCTAssertNotEqual(Self.positions(keystoned), Self.positions(before),
                          "setup: the keystone actually moved the ink")

        manager.resetFloating()
        XCTAssertNil(manager.vectorFloat?.distort)
        let reset = try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements
        assertSamePoints(Self.positions(reset), Self.positions(before), accuracy: 1e-9)
        XCTAssertFalse(manager.canResetFloating)
    }

    /// **Turning the yellow knob after a Distort changes no sample** — LASSO_MOVE.md §5.21, through
    /// the manager rather than through the map, so the guarantee is asserted where the artist reaches
    /// it. `testTheDistortMapCannotSeeALiveBoxAngle` is the same claim one level down.
    func testTurningTheBoxAfterADistortChangesNoSample() throws {
        let manager = try Self.managerWithFloat()
        let float = try XCTUnwrap(manager.vectorFloat)
        manager.nudgeVectorFloat(to: float.frame.transform,
                                 distort: .some(BoxDistort(quad: Self.pulled(float.frame),
                                                           boxSize: float.contentSize,
                                                           boxOffset: .zero, boxAngle: 0)))
        let keystoned = try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements

        manager.turnVectorFloatBox(to: 0.6)
        let after = try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements
        assertSamePoints(Self.positions(after), Self.positions(keystoned), accuracy: 0,
                         "a box turn moves no ink, keystone or no keystone")
    }

    /// **A Move after a Distort carries the keystone with it rather than flattening it.** The residue
    /// sits between the box's affine and its inverse, so every affine gesture composes over it; an arm
    /// that dropped `distort` on its way through `applyToVectorFloat` would silently un-keystone the
    /// drawing on the next drag.
    func testAMoveAfterADistortCarriesTheKeystoneWithIt() throws {
        let manager = try Self.managerWithFloat()
        let float = try XCTUnwrap(manager.vectorFloat)
        let quad = Self.pulled(float.frame)
        let atRest = Self.positions(try XCTUnwrap(manager.vectorCanvas(ofFloat: float)).elements)
        manager.nudgeVectorFloat(to: float.frame.transform,
                                 distort: .some(BoxDistort(quad: quad, boxSize: float.contentSize,
                                                           boxOffset: .zero, boxAngle: 0)))
        let keystoned = Self.positions(try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements)
        // Non-vacuous: without this the whole test passes against a `distortMap` that drops the
        // residue, because a translation of nothing is still a translation. MEASURED as a real
        // difference rather than asserted as one — the mutation sweep found this gap.
        XCTAssertNotEqual(keystoned, atRest, "setup: the residue actually moved the ink")

        var moved = float.frame.transform
        moved.position = CGPoint(x: moved.position.x + 17, y: moved.position.y - 9)
        manager.nudgeVectorFloat(to: moved)
        XCTAssertEqual(manager.vectorFloat?.distort?.quad, quad, "the residue survived the move")
        let after = Self.positions(try XCTUnwrap(manager.vectorCanvas(ofFloat: try XCTUnwrap(manager.vectorFloat))).elements)
        XCTAssertEqual(after.count, keystoned.count)
        for (before, now) in zip(keystoned, after) {
            XCTAssertEqual(now.x, before.x + 17, accuracy: 1e-6)
            XCTAssertEqual(now.y, before.y - 9, accuracy: 1e-6)
        }
    }

    // MARK: - The picture: what the finger sees and what lands

    /// **The live preview's matrix and the geometry's map are the same map**, which is the raster
    /// tier's own pin (`DistortLogicTests.testThePreviewMatrixAndTheBakeMatrixAreTheSameMap`) applied
    /// to ink — with the difference that here the two are built from one accessor,
    /// `CanvasManager.floatPictureMap`, so there is nothing for them to disagree about.
    ///
    /// What this asserts on top of that identity is the **conjugation**: a `CALayer` applies its
    /// transform about its anchor point, so the canvas-space delta has to be translated to the centre
    /// and back, and getting that backwards is silent for a translation and wrong for everything else.
    /// Asserted as a *mapping* rather than as a matrix, which is the discipline
    /// `ObjectTransformLogicTests.testTheLiveViewTransformShowsWhatARerenderWouldHave` already sets.
    func testTheLivePreviewMapShowsWhatARerenderWouldHave() throws {
        let size = CGSize(width: 400, height: 400)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = Homography(CGAffineTransform(translationX: 20, y: -8).rotated(by: 0.2))
        let current = keystone()
        let view = try XCTUnwrap(LiveLayerTransform.viewMap(from: base, to: current, inBoundsOfSize: size))
        let delta = current * (try XCTUnwrap(base.inverse))

        for probe in [CGPoint(x: 40, y: 40), CGPoint(x: 300, y: 120), CGPoint(x: 210, y: 390)] {
            // What a `CALayer` shows for a content point at `probe`: `c + M(probe − c)`.
            let shifted = CGPoint(x: probe.x - centre.x, y: probe.y - centre.y)
            let mapped = try XCTUnwrap(view.map(shifted))
            let shown = CGPoint(x: mapped.x + centre.x, y: mapped.y + centre.y)
            let rerendered = try XCTUnwrap(delta.map(probe))
            XCTAssertEqual(shown.x, rerendered.x, accuracy: 1e-6, "at \(probe)")
            XCTAssertEqual(shown.y, rerendered.y, accuracy: 1e-6, "at \(probe)")
        }
    }

    /// **And it reduces to the affine one exactly where the two overlap**, so an undistorted float's
    /// preview is the matrix it always was rather than a projective matrix that happens to agree.
    func testTheProjectivePreviewReducesToTheAffineOne() throws {
        let size = CGSize(width: 400, height: 400)
        let base = CGAffineTransform(translationX: 20, y: -8).rotated(by: 0.2)
        let current = CGAffineTransform(translationX: -3, y: 44).rotated(by: -0.5).scaledBy(x: 1.4, y: 1.4)
        let affine = LiveLayerTransform.viewTransform(from: base, to: current, inBoundsOfSize: size)
        let projective = try XCTUnwrap(LiveLayerTransform.viewMap(from: Homography(base),
                                                                  to: Homography(current),
                                                                  inBoundsOfSize: size))
        let recovered = try XCTUnwrap(projective.affine(), "no perspective row survives an affine pair")
        XCTAssertEqual(recovered.a, affine.a, accuracy: 1e-12)
        XCTAssertEqual(recovered.b, affine.b, accuracy: 1e-12)
        XCTAssertEqual(recovered.c, affine.c, accuracy: 1e-12)
        XCTAssertEqual(recovered.d, affine.d, accuracy: 1e-12)
        XCTAssertEqual(recovered.tx, affine.tx, accuracy: 1e-9)
        XCTAssertEqual(recovered.ty, affine.ty, accuracy: 1e-9)
    }

    /// **The picture, not the numbers: a keystoned line really is drawn wider where the map
    /// magnifies, and by the amount the map says.**
    ///
    /// Every other assertion in this file is about geometry the same code produced. This one renders
    /// and counts opaque *pixels*, so it fails if the ink stops following `localScale` for any reason
    /// at all — a change to `stamp`'s dispatch, a lost rest walk, a renderer that draws the polyline
    /// instead of the dabs — while every model assertion above stays green.
    ///
    /// The stroke is drawn at one width everywhere and probed at three places along its image; the
    /// expected diameter at each is the *rest* dab's own drawn diameter times the map's local scale
    /// at the point that maps there. A single-scalar implementation matches at most one probe.
    func testAKeystonedLineIsDrawnWiderWhereTheMapMagnifies() throws {
        let ink = stroke(from: CGPoint(x: 60, y: 300), to: CGPoint(x: 340, y: 300), size: 16)
        // Perspective in **x**: the left edge of the box is squeezed into a short segment and the
        // right edge left alone, so a horizontal stroke's two ends are genuinely different scales.
        let quad = Quad(CGPoint(x: 0, y: 130), CGPoint(x: 400, y: 0),
                        CGPoint(x: 400, y: 400), CGPoint(x: 0, y: 270))
        let map = try XCTUnwrap(Homography(rect: CGRect(x: 0, y: 0, width: 400, height: 400), to: quad))
        let posed = try XCTUnwrap(VectorCanvas.posing(.stroke(ink), through: map))

        // The rest picture's own drawn diameter, measured rather than derived from `stampRadius`, so
        // the two sides of the comparison come from the same renderer.
        let restImage = try XCTUnwrap(VectorCanvas(size: CGSize(width: 400, height: 400),
                                                   elements: [.stroke(ink)]).render(quality: .full))
        let restRun = try XCTUnwrap(Self.inkedRun(try XCTUnwrap(Self.alphaGrid(of: restImage)),
                                                  column: 200))
        let image = try XCTUnwrap(VectorCanvas(size: CGSize(width: 400, height: 400),
                                               elements: [posed]).render(quality: .full))
        let alpha = try XCTUnwrap(Self.alphaGrid(of: image))

        var ratios: [CGFloat] = []
        for sourceX in [CGFloat(80), 200, 330] {
            let source = CGPoint(x: sourceX, y: 300)
            let destination = try XCTUnwrap(map.map(source))
            let scale = try XCTUnwrap(map.localScale(at: source))
            let run = try XCTUnwrap(Self.inkedRun(alpha, column: Int(destination.x.rounded())),
                                    "no ink at x = \(destination.x), which is where \(source) maps")
            // Two pixels of slop: the run is thresholded at half alpha, so each edge can fall either
            // side of a pixel, and the column is a vertical cut through a line that is not vertical.
            XCTAssertEqual(CGFloat(run), CGFloat(restRun) * scale, accuracy: 2.5,
                           "drawn \(run) px where the map magnifies by \(scale) from \(restRun) px")
            ratios.append(scale)
        }
        XCTAssertGreaterThan(try XCTUnwrap(ratios.max()) / (try XCTUnwrap(ratios.min())), 1.5,
                             "setup: if the three probes were the same scale there would be nothing to see")
    }

    // MARK: - Helpers

    private static func box(size: CGSize = CGSize(width: 200, height: 100),
                            at centre: CGPoint = CGPoint(x: 200, y: 200)) -> ObjectTransformFrame {
        ObjectTransformFrame(transform: LayerTransform(position: centre, scale: 1, rotation: 0),
                             contentSize: size)
    }

    /// A quad with one corner pulled in, in the frame's own local space.
    private static func pulled(_ frame: ObjectTransformFrame) -> Quad {
        var quad = frame.localQuad
        quad[0] = CGPoint(x: quad.p0.x + frame.contentSize.width * 0.3, y: quad.p0.y)
        return quad
    }

    private static func managerWithFloat() throws -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let index = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[index].cels[0].vector)
        vector.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: ink,
                                      size: 4, opacity: 1,
                                      samples: StrokeSamples([VectorSample(x: 12, y: 32, pressure: 1),
                                                              VectorSample(x: 52, y: 32, pressure: 1),
                                                              VectorSample(x: 52, y: 44, pressure: 1)],
                                                             channels: .pressureOnly)))
        manager.setTransformMode(.distort)
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: a vector float")
        return manager
    }

    private static func float() throws -> VectorFloat {
        try XCTUnwrap(managerWithFloat().vectorFloat)
    }

    private static func positions(_ elements: [VectorElement]) -> [CGPoint] {
        elements.compactMap(\.stroke).flatMap(\.samples.positions)
    }

    /// The nearest distance from `point` to any point on `path`, sampled at the path's own vertices —
    /// which for a flattened path is every point it has.
    private static func distance(from point: CGPoint, to path: CGPath) -> CGFloat {
        var best = CGFloat.infinity
        path.applyWithBlock { raw in
            let element = raw.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for index in 0..<count {
                let p = element.points[index]
                best = min(best, hypot(p.x - point.x, p.y - point.y))
            }
        }
        return best
    }

    /// The image's alpha channel as one byte per pixel, at the image's own pixel size.
    private static func alphaGrid(of image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        // **Read out of an RGBA buffer rather than an alpha-only one.** `CGContext` will not build an
        // `alphaOnly` context against a colour space, and the combination that *is* accepted comes
        // back as luminance — where black ink and a transparent background are both 0 and the ink is
        // invisible to any threshold. Drawing into premultiplied RGBA and taking the fourth byte is
        // the coverage, unambiguously.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = rgba.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) { bytes[index] = rgba[index * 4 + 3] }
        return (bytes, width, height)
    }

    /// How many rows of `column` carry more than half alpha — the ink's drawn width there, in pixels.
    private static func inkedRun(_ grid: (bytes: [UInt8], width: Int, height: Int), column: Int) -> Int? {
        let scale = CGFloat(grid.width) / 400
        let x = Int((CGFloat(column) * scale).rounded())
        guard x >= 0, x < grid.width else { return nil }
        var count = 0
        for y in 0..<grid.height where grid.bytes[y * grid.width + x] > 127 { count += 1 }
        return count > 0 ? count : nil
    }
}

private extension XCTestCase {
    /// Two point lists compared coordinate by coordinate. Named rather than spelled as an
    /// `XCTAssertEqual` overload because an overload in scope *shadows* the global function for every
    /// other call in the file, which turns forty working assertions into compile errors.
    func assertSamePoints(_ lhs: [CGPoint], _ rhs: [CGPoint], accuracy: CGFloat,
                          _ message: String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, "point counts differ. \(message)", file: file, line: line)
        for (a, b) in zip(lhs, rhs) {
            XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
            XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        }
    }
}
