import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for **motion groups** — Phase 5 of `VECTOR_INTERPOLATION_IMPLEMENTATION.md`.
///
/// The division of labour with the three neighbouring classes: `ARAPLogicTests` owns
/// `MotionGrouping` as an algorithm ("does this partition split"), `InterpolationWorkflowLogicTests`
/// owns Phase 4's single whole-frame answer, `InterpolationRenderLogicTests` owns pixels. This file
/// owns the seam between them — `CanvasManager.registerGroups` and the document-level tagging,
/// retagging and undo that hang off it.
///
/// What is being pinned, in descending order of how expensive it is to discover later:
///
/// 1. **The whole-frame answer is preserved exactly.** A drawing with one part must take Phase 4's
///    path untouched: one anonymous binding, no registered group, no tags written. If that ever
///    stops holding, every single-body test drawing starts acquiring document state the artist did
///    not ask for, and it would show up as an unexplained group in the UI rather than as a failure.
/// 2. **Tags are written back onto the keyframes.** Without the write-back the partition lives only
///    inside the recipe's bindings, where nothing can show it and nothing can correct it — and, worse,
///    re-registration would find every stroke untagged again and mint a fresh set of groups on every
///    Generate (`HANDOFF.md` §5, "From Phase 5").
/// 3. **A retag changes the motion, not only the label.** Phase 5's definition of done is "the artist
///    can retag and see the result immediately"; `setMotionGroup` re-registers inside the same undo
///    step, and it is the re-registration rather than the tag that makes that true.
/// 4. **Generate's undo bracket covers the tags.** It writes stroke content now, so
///    `withStructureUndo` is not enough — undoing must take the tags off the reference drawings as
///    well as the recipe off the target (`HANDOFF.md` §5, Phase 2).
///
/// **The two-body fixture is copied from `ARAPLogicTests`, deliberately and verbatim.** §5's Phase 1
/// entry lists four two-body fixtures that looked obviously correct and asserted things that were
/// simply not true of the geometry, and §5's Phase 5 entry adds a fifth trap: two strokes alone can
/// never split, because `MotionGrouping.splinter`'s spatial radius is a multiple of the *median*
/// nearest-neighbour spacing and with two strokes the median is their own separation. A rectangle of
/// four strokes beside a triangle of three, with the rectangle moved along the line joining them, is
/// the arrangement that is known to split — do not simplify it.
final class InterpolationMotionGroupLogicTests: XCTestCase {

    // MARK: - Geometry fixtures (copied from ARAPLogicTests — see the class comment)

    private func bar(from a: CGPoint, to b: CGPoint, count: Int) -> [CGPoint] {
        (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// A closed rectangle outline as four strokes. Closed and unequal-sided so it pins its own
    /// position, orientation and scale — loose parallel strokes let point matching slide freely along
    /// them and ICP then explains two separately-moving bodies as one rotation.
    private func rectangleBody(at origin: CGPoint, width: CGFloat = 60, height: CGFloat = 30) -> [[CGPoint]] {
        let a = origin
        let b = CGPoint(x: origin.x + width, y: origin.y)
        let c = CGPoint(x: origin.x + width, y: origin.y + height)
        let d = CGPoint(x: origin.x, y: origin.y + height)
        return [bar(from: a, to: b, count: 11), bar(from: b, to: c, count: 7),
                bar(from: c, to: d, count: 11), bar(from: d, to: a, count: 7)]
    }

    /// A closed triangle outline as three strokes — a body the rectangle cannot be confused with.
    private func triangleBody(at origin: CGPoint, size: CGFloat = 44) -> [[CGPoint]] {
        let a = origin
        let b = CGPoint(x: origin.x + size, y: origin.y + 6)
        let c = CGPoint(x: origin.x + size * 0.35, y: origin.y + size * 0.8)
        return [bar(from: a, to: b, count: 11), bar(from: b, to: c, count: 9), bar(from: c, to: a, count: 9)]
    }

    private func moved(_ strokes: [[CGPoint]], by delta: CGPoint) -> [[CGPoint]] {
        strokes.map { $0.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) } }
    }

    /// The two bodies at rest, rectangle first. Indices 0–3 are the rectangle, 4–6 the triangle.
    private var twoBodiesAtRest: [[CGPoint]] {
        rectangleBody(at: CGPoint(x: 40, y: 60)) + triangleBody(at: CGPoint(x: 220, y: 60))
    }

    /// The same two bodies with the rectangle moved 40 along the line joining them and the triangle
    /// left still — the one arrangement `ARAPLogicTests` establishes really is two motion groups.
    private var twoBodiesMoved: [[CGPoint]] {
        moved(rectangleBody(at: CGPoint(x: 40, y: 60)), by: CGPoint(x: 40, y: 0))
            + triangleBody(at: CGPoint(x: 220, y: 60))
    }

    private static let rectangle = Array(0..<4)
    private static let triangle = Array(4..<7)

    // MARK: - Document fixtures

    private static let brush = BrushLibrary.hardRound

    private static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    private func stroke(_ points: [CGPoint],
                        color: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                        composite: StrokeComposite = .paint, id: UUID = UUID()) -> VectorStroke {
        VectorStroke(id: id, brush: Self.brush, color: color, size: 6, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                     composite: composite)
    }

    private func elements(_ strokes: [[CGPoint]], tags: [UUID?] = []) -> [VectorElement] {
        strokes.enumerated().map { index, points in
            var s = stroke(points)
            if index < tags.count { s.motionGroupID = tags[index] }
            return .stroke(s)
        }
    }

    private func frame(_ strokes: [[CGPoint]], tags: [UUID?] = []) -> CanvasManager.RegistrationFrame {
        CanvasManager.registrationFrame(of: elements(strokes, tags: tags))
    }

    /// A manager with one raster layer (index 0, from `CanvasFixture`) and one vector layer at 1.
    private func manager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        return manager
    }

    /// Three cels on the vector layer: the two bodies at frame 0, an empty in-between at frame 4, the
    /// bodies with the rectangle moved at frame 8.
    ///
    /// Assigns `cels` directly rather than calling `addCel`, because `CanvasFixture.manager` gives each
    /// layer one cel spanning the whole scene and every `addCel` inside it collides (`HANDOFF.md` §5).
    @discardableResult
    private func twoBodyKeyframes(_ manager: CanvasManager, layerIndex: Int = 1) -> [Cel] {
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[layerIndex].cels = cels
        for element in elements(twoBodiesAtRest) {
            if case .stroke(let s) = element { cels[0].vector?.addStroke(s) }
        }
        for element in elements(twoBodiesMoved) {
            if case .stroke(let s) = element { cels[2].vector?.addStroke(s) }
        }
        return cels
    }

    /// A single moving body across three cels — the drawing that must keep taking Phase 4's path.
    @discardableResult
    private func oneBodyKeyframes(_ manager: CanvasManager, layerIndex: Int = 1) -> [Cel] {
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[layerIndex].cels = cels
        let body = rectangleBody(at: CGPoint(x: 40, y: 60))
        for points in body { cels[0].vector?.addStroke(stroke(points)) }
        for points in moved(body, by: CGPoint(x: 40, y: 0)) { cels[2].vector?.addStroke(stroke(points)) }
        return cels
    }

    private func setReferences(_ manager: CanvasManager, layerIndex: Int, cels: [Cel]) {
        for cel in cels {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[layerIndex].id)
        }
    }

    /// Generate on the middle cel of a three-cel layer, with the outer two as references.
    private func generate(_ manager: CanvasManager, layerIndex: Int = 1, cels: [Cel]) {
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: layerIndex, cels: [cels[0], cels[2]])
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: layerIndex, celIndex: 1))
    }

    /// Every stroke's tag on a cel, in display-list order, nils included.
    private func strokeTags(of cel: Cel) -> [UUID?] {
        var result: [UUID?] = []
        for element in cel.vector?.elements ?? [] {
            guard let stroke = element.stroke else { continue }
            result.append(stroke.motionGroupID)
        }
        return result
    }

    private func strokeIDs(of cel: Cel) -> [UUID] {
        (cel.vector?.elements ?? []).compactMap { $0.stroke?.id }
    }

    /// How far a binding actually carries its own part, averaged over the part's source points.
    ///
    /// Mean displacement rather than a single probe point: a lattice fit is not exact anywhere in
    /// particular, and averaging over the body is the honest reading of "did this part move".
    private func meanDisplacement(_ binding: MotionGroupBinding, of points: [CGPoint]) -> CGPoint {
        guard binding.lattices.count >= 2, !points.isEmpty else { return .zero }
        let warped = binding.lattices[1].warp(binding.lattices[0].embedInRest(points))
        var dx: CGFloat = 0, dy: CGFloat = 0
        for (from, to) in zip(points, warped) { dx += to.x - from.x; dy += to.y - from.y }
        return CGPoint(x: dx / CGFloat(points.count), y: dy / CGFloat(points.count))
    }

    // MARK: - registerGroups: the whole-frame answer

    /// Phase 4's answer must survive Phase 5 *bit for bit* on a drawing with one part. Not a nicety:
    /// a registered `MotionGroup` is an artist-facing object with a name, a swatch and a mode badge,
    /// and minting one for a single-body doodle would put document state on screen that nobody asked
    /// for (`HANDOFF.md` §5.10). One anonymous binding, nothing invented, nothing tagged.
    func testASinglePartDrawingKeepsPhase4sAnonymousWholeFrameBinding() {
        let body = rectangleBody(at: CGPoint(x: 40, y: 60))
        let registration = CanvasManager.registerGroups(
            frames: [frame(body), frame(moved(body, by: CGPoint(x: 40, y: 0)))], existing: [])

        XCTAssertEqual(registration.bindings.count, 1, "one part is one binding")
        XCTAssertTrue(registration.invented.isEmpty,
                      "the whole-frame group stays anonymous — no registry entry")
        XCTAssertTrue(registration.assignments.isEmpty,
                      "nothing to tag when the whole drawing is one group")
    }

    func testTwoEmptyKeyframesRegisterNothingAtAll() {
        let registration = CanvasManager.registerGroups(frames: [frame([]), frame([])], existing: [])

        XCTAssertTrue(registration.bindings.isEmpty)
        XCTAssertTrue(registration.invented.isEmpty)
        XCTAssertTrue(registration.assignments.isEmpty)
    }

    // MARK: - registerGroups: the partition

    func testTwoBodiesMovingDifferentlyRegisterAsOneBindingEach() throws {
        let registration = CanvasManager.registerGroups(
            frames: [frame(twoBodiesAtRest), frame(twoBodiesMoved)], existing: [])

        XCTAssertEqual(registration.bindings.count, 2, "one body moving and one still are two groups")
        XCTAssertEqual(registration.invented.count, 2,
                       "a real partition is artist-facing, so both parts get a registry entry")
        XCTAssertEqual(Set(registration.invented.map(\.id)), Set(registration.bindings.map(\.groupID)),
                       "every binding's group must exist in the registry")
        XCTAssertNotEqual(registration.invented[0].tagColor, registration.invented[1].tagColor,
                          "two groups the artist has to tell apart need two swatches")

        let assignments = registration.assignments
        XCTAssertEqual(assignments.count, 2, "one assignment row per keyframe")
        let atRest = try XCTUnwrap(assignments.first)
        XCTAssertEqual(atRest.count, 7)
        XCTAssertEqual(Set(Self.rectangle.map { atRest[$0] }).count, 1,
                       "the rectangle's four strokes land in one group")
        XCTAssertEqual(Set(Self.triangle.map { atRest[$0] }).count, 1,
                       "the triangle's three strokes land in one group")
        XCTAssertNotEqual(atRest[0], atRest[4], "and it is not the same group")
    }

    /// The point of a partition: each part is fitted to *its own* counterpart, so the rectangle's
    /// lattice carries the rectangle 40 across and the triangle's carries the triangle nowhere. A
    /// single whole-frame fit would split the difference and move both about 20.
    func testEachPartIsFittedToItsOwnCounterpart() throws {
        let rest = frame(twoBodiesAtRest)
        let registration = CanvasManager.registerGroups(
            frames: [rest, frame(twoBodiesMoved)], existing: [])
        XCTAssertEqual(registration.bindings.count, 2, "Setup: the drawing split")

        let atRest = try XCTUnwrap(registration.assignments.first)
        let rectangleID = try XCTUnwrap(atRest[0])
        let triangleID = try XCTUnwrap(atRest[4])
        let rectangleBinding = try XCTUnwrap(registration.bindings.first { $0.groupID == rectangleID })
        let triangleBinding = try XCTUnwrap(registration.bindings.first { $0.groupID == triangleID })

        let rectanglePoints = Self.rectangle.flatMap { rest.elements[$0].points }
        let trianglePoints = Self.triangle.flatMap { rest.elements[$0].points }
        let rectangleMotion = meanDisplacement(rectangleBinding, of: rectanglePoints)
        let triangleMotion = meanDisplacement(triangleBinding, of: trianglePoints)

        XCTAssertEqual(rectangleMotion.x, 40, accuracy: 8,
                       "the moving body's own lattice should carry it the whole 40")
        XCTAssertEqual(rectangleMotion.y, 0, accuracy: 8)
        XCTAssertLessThan(hypot(triangleMotion.x, triangleMotion.y), 8,
                          "the still body's lattice should leave it where it is")
    }

    /// The artist's own tags are the seeds, and registration must come back with *their* groups
    /// rather than a parallel set beside them. This is the attached-limb case — the one automatic
    /// grouping cannot do (`HANDOFF.md` §8 item 1) — so it is also the case where reuse matters most:
    /// a session that minted new groups here would lose the artist's tagging on every Generate.
    func testTaggedSeedsAreReusedRatherThanRepartitioned() throws {
        let joint = CGPoint(x: 130, y: 120)
        let torso = rectangleBody(at: CGPoint(x: 60, y: 100), width: 70, height: 40)
        let arm = [bar(from: joint, to: CGPoint(x: 190, y: 120), count: 11),
                   bar(from: CGPoint(x: 190, y: 120), to: CGPoint(x: 215, y: 148), count: 7)]
        func swung(_ p: CGPoint) -> CGPoint {
            let dx = p.x - joint.x, dy = p.y - joint.y
            return CGPoint(x: joint.x + dx * cos(0.6) - dy * sin(0.6),
                           y: joint.y + dx * sin(0.6) + dy * cos(0.6))
        }
        let torsoGroup = MotionGroup(displayName: "Torso", tagColor: Self.black)
        let armGroup = MotionGroup(displayName: "Arm", tagColor: Self.black)
        let seeded = frame(torso + arm,
                           tags: [torsoGroup.id, torsoGroup.id, torsoGroup.id, torsoGroup.id,
                                  armGroup.id, armGroup.id])
        let swungFrame = frame(torso + arm.map { $0.map(swung) })

        let registration = CanvasManager.registerGroups(frames: [seeded, swungFrame],
                                                        existing: [torsoGroup, armGroup])

        XCTAssertEqual(Set(registration.bindings.map(\.groupID)), [torsoGroup.id, armGroup.id],
                       "the bindings must be the artist's groups, not new ones beside them")
        XCTAssertTrue(registration.invented.isEmpty,
                      "nothing to invent when every part already agrees on a tag")
        let atRest = try XCTUnwrap(registration.assignments.first)
        XCTAssertEqual(atRest, [torsoGroup.id, torsoGroup.id, torsoGroup.id, torsoGroup.id,
                                armGroup.id, armGroup.id],
                       "a tagged seed is refined, not rediscovered")
    }

    // MARK: - Generate writes the partition back onto the keyframes

    /// The write-back is what makes group ids **stable**, and each link in that chain looks optional
    /// while none is: a part reuses the tag its members agree on, an untagged part has none to reuse
    /// so it mints one, and if that id were not written onto the strokes the next registration would
    /// find them untagged and mint another. Groups would accumulate one set per Generate.
    func testGenerateWritesTheGroupTagsOntoBothKeyframes() throws {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)

        XCTAssertEqual(manager.motionGroups.count, 2,
                       "the two parts registration found are now document objects")
        for (label, cel) in [("keyframe A", cels[0]), ("keyframe C", cels[2])] {
            let tags = strokeTags(of: cel)
            XCTAssertEqual(tags.count, 7, "\(label): every stroke should have been visited")
            XCTAssertFalse(tags.contains(nil), "\(label): the partition covers the whole drawing")
            XCTAssertEqual(Set(Self.rectangle.map { tags[$0] }).count, 1,
                           "\(label): the rectangle is one group")
            XCTAssertEqual(Set(Self.triangle.map { tags[$0] }).count, 1,
                           "\(label): the triangle is one group")
            XCTAssertNotEqual(tags[0], tags[4], "\(label): and the two bodies are different groups")
        }
        XCTAssertEqual(Set(strokeTags(of: cels[0]).compactMap { $0 }),
                       Set(strokeTags(of: cels[2]).compactMap { $0 }),
                       "both keyframes must be tagged with the same two groups, or the parts cannot pair")
    }

    /// Phase 4's behaviour, unchanged, for the drawing that has one part. The failure this guards
    /// against is a quiet one: a single-stroke test drawing that starts acquiring a "Group 1" nobody
    /// created.
    func testGenerateOnASinglePartDrawingRegistersNoGroupAndTagsNothing() {
        let manager = manager()
        let cels = oneBodyKeyframes(manager)
        generate(manager, cels: cels)

        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.groups.count, 1,
                       "one binding, exactly as Phase 4 produced")
        XCTAssertTrue(manager.motionGroups.isEmpty, "and it stays anonymous")
        XCTAssertEqual(strokeTags(of: cels[0]).compactMap { $0 }.count, 0)
        XCTAssertEqual(strokeTags(of: cels[2]).compactMap { $0 }.count, 0)
    }

    /// Generate now writes stroke content, so it needs `withInterpolationUndo` rather than
    /// `withStructureUndo`: `StructureSnapshot` copies `[Layer]` but shares each `VectorCanvas`, so
    /// the structural bracket would put the recipe back and leave the tags on the reference drawings
    /// (`HANDOFF.md` §5, Phase 2 — the trap this feature was warned about three phases early).
    func testUndoingGenerateTakesTheTagsOffAsWellAsTheRecipe() {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)
        XCTAssertFalse(strokeTags(of: cels[0]).contains(nil), "Setup: the keyframes were tagged")

        manager.undo()

        XCTAssertNil(manager.layers[1].cels[1].interpolation, "the recipe goes")
        XCTAssertTrue(manager.motionGroups.isEmpty, "the invented groups go")
        for (label, index) in [("keyframe A", 0), ("keyframe C", 2)] {
            let tags = strokeTags(of: manager.layers[1].cels[index])
            XCTAssertEqual(tags.compactMap { $0 }.count, 0,
                           "\(label): the tags go too — one action, one step")
        }
    }

    // MARK: - Retagging

    /// Phase 5's definition of done is "the artist can retag and see the result immediately", and it
    /// is the *re-registration* that makes "immediately" true. A retag that only rewrote the tag
    /// would recolour the swatch and leave the motion exactly as it was, which reads as the tag
    /// having done nothing at all.
    func testRetaggingAStrokeReRegistersSoTheMotionChangesToo() throws {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)
        let before = try XCTUnwrap(manager.layers[1].cels[1].interpolation?.groups)
        let ids = strokeIDs(of: cels[0])
        let rectangleGroup = try XCTUnwrap(strokeTags(of: cels[0])[0])

        // Move one of the triangle's strokes into the rectangle's group.
        manager.setMotionGroup(rectangleGroup, forStrokeIDs: [ids[4]])

        let after = try XCTUnwrap(manager.layers[1].cels[1].interpolation?.groups)
        XCTAssertNotEqual(after, before,
                          "the fitted lattices must differ — a retag moves ink, not just a label")
        let tags = strokeTags(of: cels[0])
        XCTAssertEqual(Set(tags.compactMap { $0 }), Set(after.map(\.groupID)),
                       "every tag on the drawing must be a group the recipe can actually warp by")
        XCTAssertFalse(tags.contains(nil),
                       "and re-registration leaves nothing untagged")
    }

    /// **Characterisation of a design consequence, not an aspiration — and one to put in front of the
    /// product owner** (`HANDOFF.md` §3.5).
    ///
    /// The artist's tag is a *seed*, not a constraint. `MotionGrouping.group` puts seeds through
    /// exactly the same splitting loop as an untagged partition (`PLAN.md` §5.3's "one algorithm, two
    /// seeds"), so a seeded part whose residual is high is splintered like any other — and
    /// `dominantTag` then hands the reused name to the larger half and mints a fresh group for the
    /// splinter. That reads correctly as "it found another part inside the one I tagged" when the
    /// split is a *discovery*. It reads as the tool undoing the artist's work when the artist has
    /// just deliberately moved a stroke into a group whose motion it does not share, which is this
    /// test: the stroke lands in neither the group that was named nor the one it came from, but in a
    /// third group of its own.
    ///
    /// Both readings come from one line of behaviour and nothing in the model distinguishes them. The
    /// fix — never splitting a *seeded* part, and only refining the untagged leftover — would change
    /// `PLAN.md` §5.3, so it is the product owner's call rather than this session's.
    func testRetaggingAStrokeAgainstItsGeometrySplintersItIntoANewGroup() throws {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)
        let ids = strokeIDs(of: cels[0])
        let tagsBefore = strokeTags(of: cels[0])
        let rectangleGroup = try XCTUnwrap(tagsBefore[0])
        let triangleGroup = try XCTUnwrap(tagsBefore[4])
        XCTAssertEqual(manager.motionGroups.count, 2, "Setup: two parts")

        manager.setMotionGroup(rectangleGroup, forStrokeIDs: [ids[4]])

        let tags = strokeTags(of: cels[0])
        XCTAssertEqual(tags[0], rectangleGroup, "the larger half keeps the name it had")
        XCTAssertNotEqual(tags[4], rectangleGroup,
                          "the retagged stroke does NOT stay in the group the artist named")
        XCTAssertNotEqual(tags[4], triangleGroup, "nor does it go back to the one it came from")
        XCTAssertEqual(manager.motionGroups.count, 3,
                       "a third group is minted for it, which is the behaviour to review")
    }

    func testRetaggingIsOneUndoStepThatRestoresTheMotionAsWellAsTheTag() throws {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)
        let before = try XCTUnwrap(manager.layers[1].cels[1].interpolation?.groups)
        let ids = strokeIDs(of: cels[0])
        let originalTag = try XCTUnwrap(strokeTags(of: cels[0])[4])
        let rectangleGroup = try XCTUnwrap(strokeTags(of: cels[0])[0])

        manager.setMotionGroup(rectangleGroup, forStrokeIDs: [ids[4]])
        manager.undo()

        XCTAssertEqual(strokeTags(of: manager.layers[1].cels[0])[4], originalTag,
                       "the tag comes back")
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.groups, before,
                       "and so does the motion it changed")
    }

    /// Clearing a tag is the same action with a nil group — and it does **not** leave the stroke
    /// untagged, because clearing re-registers and registration tags everything it partitions. Worth
    /// pinning precisely because the opposite is the natural expectation: "clear" reads like it should
    /// hand the stroke back to the untagged default (the recipe's first binding, `HANDOFF.md` §5.9),
    /// and after one Generate there is no untagged state left to hand it back to. What clearing
    /// actually means is "forget what I said and re-decide", which is a useful action but a different
    /// one, and the UI wording in Phase 5 item 2 should say so.
    func testClearingATagReDecidesItRatherThanLeavingTheStrokeUntagged() throws {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)
        let ids = strokeIDs(of: cels[0])
        let before = try XCTUnwrap(strokeTags(of: cels[0])[4])

        manager.setMotionGroup(nil, forStrokeIDs: [ids[4]])

        XCTAssertNotNil(strokeTags(of: cels[0])[4],
                        "re-registration re-tags it — clearing is 're-decide', not 'leave it out'")
        manager.undo()
        XCTAssertEqual(strokeTags(of: manager.layers[1].cels[0])[4], before,
                       "and the whole thing is one undo step")
    }

    // MARK: - Tag by stroke colour

    /// `PLAN.md` §5.1.1's one-shot populate — the mitigation the product owner named for the
    /// attached-limb limitation. A *populate*, never a live binding: after it runs the tags are
    /// ordinary tags, so recolouring a stroke afterwards must not silently move it to another group.
    func testTagByStrokeColourMakesOneGroupPerColour() throws {
        let manager = manager()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 4, raster: .empty(size: size),
                      vector: .empty(size: size))
        manager.layers[1].cels = [cel]
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        let body = rectangleBody(at: CGPoint(x: 40, y: 60))
        for (index, points) in body.enumerated() {
            cel.vector?.addStroke(stroke(points, color: index < 2 ? red : blue))
        }
        let ref = CelRef(layerID: manager.layers[1].id, celID: cel.id)

        let created = manager.tagMotionGroupsByStrokeColour(in: [ref])

        XCTAssertEqual(created.count, 2, "two paint colours are two groups")
        let tags = strokeTags(of: manager.layers[1].cels[0])
        XCTAssertEqual(tags[0], tags[1], "the two reds land together")
        XCTAssertEqual(tags[2], tags[3], "and so do the two blues")
        XCTAssertNotEqual(tags[0], tags[2])
        XCTAssertEqual(Set(tags.compactMap { $0 }), Set(created.map(\.id)))

        manager.undo()
        XCTAssertEqual(strokeTags(of: manager.layers[1].cels[0]).compactMap { $0 }.count, 0,
                       "one action, one undo step")
        XCTAssertTrue(manager.motionGroups.isEmpty)
    }

    /// One colour is not a grouping — it is the whole-frame group the drawing already had, and
    /// minting a single artist-facing object for it would say nothing. The refusal lives in the model
    /// rather than in the button, so every caller gets it.
    func testTagByStrokeColourRefusesWhenTheDrawingIsAllOneColour() {
        let manager = manager()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 4, raster: .empty(size: size),
                      vector: .empty(size: size))
        manager.layers[1].cels = [cel]
        for points in rectangleBody(at: CGPoint(x: 40, y: 60)) { cel.vector?.addStroke(stroke(points)) }

        let created = manager.tagMotionGroupsByStrokeColour(
            in: [CelRef(layerID: manager.layers[1].id, celID: cel.id)])

        XCTAssertTrue(created.isEmpty)
        XCTAssertTrue(manager.motionGroups.isEmpty)
        XCTAssertEqual(strokeTags(of: manager.layers[1].cels[0]).compactMap { $0 }.count, 0,
                       "a refusal must not half-tag the drawing")
    }

    /// An eraser's colour is not a colour — it says nothing about which part it belongs to — so
    /// clustering on it would invent a group made of every eraser on the drawing. Left untagged they
    /// ride the first binding, which is what they did before this action existed.
    func testTagByStrokeColourSkipsErasers() throws {
        let manager = manager()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 4, raster: .empty(size: size),
                      vector: .empty(size: size))
        manager.layers[1].cels = [cel]
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        let body = rectangleBody(at: CGPoint(x: 40, y: 60))
        cel.vector?.addStroke(stroke(body[0], color: red))
        cel.vector?.addStroke(stroke(body[1], color: blue))
        cel.vector?.addStroke(stroke(body[2], color: red, composite: .erase))

        let created = manager.tagMotionGroupsByStrokeColour(
            in: [CelRef(layerID: manager.layers[1].id, celID: cel.id)])

        XCTAssertEqual(created.count, 2, "the eraser's colour must not open a third cluster")
        let tags = strokeTags(of: manager.layers[1].cels[0])
        XCTAssertNotNil(tags[0])
        XCTAssertNotNil(tags[1])
        XCTAssertNil(tags[2], "the eraser stays untagged and rides the first binding")
    }

    // MARK: - The group registry

    func testDeletingAGroupClearsItsTagsAndDropsItsBindings() throws {
        let manager = manager()
        let cels = twoBodyKeyframes(manager)
        generate(manager, cels: cels)
        let doomed = try XCTUnwrap(strokeTags(of: cels[0])[0])

        manager.removeMotionGroup(doomed)

        XCTAssertFalse(manager.motionGroups.contains { $0.id == doomed })
        XCTAssertFalse(strokeTags(of: cels[0]).contains(doomed),
                       "a stroke must not be left pointing at a group that no longer exists")
        XCTAssertFalse(strokeTags(of: cels[2]).contains(doomed))
        let bindings = try XCTUnwrap(manager.layers[1].cels[1].interpolation?.groups)
        XCTAssertFalse(bindings.contains { $0.groupID == doomed },
                       "and the recipe must not keep warping by it")

        manager.undo()
        XCTAssertTrue(manager.motionGroups.contains { $0.id == doomed })
        XCTAssertTrue(strokeTags(of: manager.layers[1].cels[0]).contains(doomed))
    }

    /// The per-group mode badge is Phase 5 item 3. Nothing displays it yet; this pins that setting it
    /// is a real, undoable document edit rather than view state, which is what the badge will need.
    func testChangingAGroupsModeIsOneUndoableDocumentEdit() throws {
        let manager = manager()
        let group = manager.addMotionGroup(name: "Arm", tagColor: Self.black)
        XCTAssertEqual(manager.motionGroup(withID: group.id)?.mode, .auto)

        manager.setMotionGroupMode(.crossFade, forGroup: group.id)
        XCTAssertEqual(manager.motionGroup(withID: group.id)?.mode, .crossFade)

        manager.undo()
        XCTAssertEqual(manager.motionGroup(withID: group.id)?.mode, .auto,
                       "the mode is document state, so it undoes")
    }
}
