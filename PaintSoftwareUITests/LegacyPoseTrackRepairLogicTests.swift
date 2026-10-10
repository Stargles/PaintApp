import XCTest
import UIKit
import CoreGraphics

/// **The throwaway library repair rewrites the pose tracks earlier builds wrote, and nothing else** —
/// `LegacyPoseTrackRepair`, run at launch over `Projects/`, `Backups/` and `Trash/`.
///
/// The files are made the way the old builds made them: a real save, then the track put back in the
/// older shape (`rewriteTrack`), because the point is that a document written by a build that no longer
/// exists opens with its keys and draws what that build drew. The decoder itself reads the current
/// format only (`TransformKeysSurviveLogicTests` pins that it refuses the rest).
///
/// **Deleted with `LegacyPoseTrackRepair.swift`.**
@MainActor
final class LegacyPoseTrackRepairLogicTests: XCTestCase {

    private var root: URL!
    private var canvasBox: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    private var canvasCentre: CGPoint { CGPoint(x: canvasBox.midX, y: canvasBox.midY) }
    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-pose-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        UserDefaults.standard.removeObject(forKey: ProjectBackupManager.signatureDefaultsKey)
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDownWithError() throws {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        ProjectBackupManager.rootDirectoryOverride = nil
        UserDefaults.standard.removeObject(forKey: ProjectBackupManager.signatureDefaultsKey)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func drag(_ manager: CanvasManager, by delta: CGVector) {
        manager.updateFloatingPose(
            transform: FloatingTransform(position: CGPoint(x: canvasCentre.x + delta.dx, y: canvasCentre.y + delta.dy),
                                         scaleX: 1, scaleY: 1, rotation: 0),
            distortQuad: nil)
    }

    /// One whole Move on the current transformation layer.
    @discardableResult
    private func move(_ manager: CanvasManager, by delta: CGVector) -> Bool {
        guard manager.beginContainerPoseMove() else { return false }
        drag(manager, by: delta)
        manager.settleBoxNudge()
        return manager.commitFloatingPieceIfNeeded()
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    private func composite(_ manager: CanvasManager, frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite at frame \(frame)")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    private func components(of track: TransformTrack) -> Set<PoseComponents.Component> {
        Set(PoseComponents.Component.allCases.filter { track.curve($0) != nil })
    }

    private func maxByteDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    /// A red square on a vector layer under a transformation layer called "Keyed".
    private func scene() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.layers[0].cels[0].vector!.addFill(
            canvasSpacePath: CGPath(rect: CGRect(x: 8, y: 20, width: 12, height: 12), transform: nil), color: red)
        manager.addTransformLayer(name: "Keyed")
        return manager
    }

    private func turned(_ dx: CGFloat, _ angle: CGFloat) -> PoseQuad {
        PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: canvasCentre.x + dx, y: canvasCentre.y)
                    .rotated(by: angle).translatedBy(x: -canvasCentre.x, y: -canvasCentre.y))
    }

    private func object<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    /// One whole-pose key, in the form the old build wrote it.
    private func legacyKey(_ frame: Int, _ pose: PoseQuad, tangent: String = "autoClamped",
                           interpolation: String = "bezier") throws -> [String: Any] {
        ["frame": frame, "pose": try object(pose),
         "inHandle": ["deltaFrames": 0, "deltaValue": 0], "outHandle": ["deltaFrames": 0, "deltaValue": 0],
         "tangentMode": tangent, "interpolation": interpolation]
    }

    /// **What the old build drew at `frame`** — its timing spine (one curve through the key indices, with
    /// the keys' own handles) read at the frame, and the two poses either side blended at that fraction.
    private func legacyPose(_ keys: [(frame: Int, pose: PoseQuad)], atFrame frame: Int) -> PoseQuad? {
        let spine = AnimationCurve(keys: keys.enumerated().map {
            AnimationCurve.Key(frame: $1.frame, value: Double($0))
        })
        let index = spine.evaluate(at: Double(frame))
        let lower = min(max(Int(index.rounded(.down)), 0), keys.count - 2)
        return PoseInterpolation.blend(keys[lower].pose, keys[lower + 1].pose, t: CGFloat(index - Double(lower)))
    }

    private func readManifest(_ package: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: package.appendingPathComponent("manifest.json"))) as? [String: Any])
    }

    /// Puts one layer's `transform.track` in a saved package's manifest back in an older shape.
    private func rewriteTrack(ofLayer id: UUID, in package: URL, to track: [String: Any]) throws {
        var manifest = try readManifest(package)
        var layers = try XCTUnwrap(manifest["layers"] as? [[String: Any]])
        let at = try XCTUnwrap(layers.firstIndex { ($0["id"] as? String) == id.uuidString })
        var transform = try XCTUnwrap(layers[at]["transform"] as? [String: Any])
        transform["track"] = track
        layers[at]["transform"] = transform
        manifest["layers"] = layers
        try JSONSerialization.data(withJSONObject: manifest).write(to: package.appendingPathComponent("manifest.json"))
    }

    private func track(ofLayer id: UUID, in package: URL) throws -> [String: Any] {
        let layers = try XCTUnwrap(readManifest(package)["layers"] as? [[String: Any]])
        let layer = try XCTUnwrap(layers.first { ($0["id"] as? String) == id.uuidString })
        return try XCTUnwrap((layer["transform"] as? [String: Any])?["track"] as? [String: Any])
    }

    /// The cel animation file of a saved package.
    private func animationFile(in package: URL) throws -> URL {
        try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix("-animation.json") }, "the cel's animation file")
    }

    /// A package whose transformation layer "Keyed" holds `keys` in the whole-pose form.
    private func legacyPackage(keys: [[String: Any]], name: String = "Pre-139") throws -> (url: URL, layer: UUID) {
        let manager = scene()
        let layer = manager.layers[1].id
        let url = ProjectStore.createNewProjectURL(name: name)
        saveAndWait(manager, to: url)
        try rewriteTrack(ofLayer: layer, in: url, to: ["keys": keys, "step": 1])
        return (url, layer)
    }

    /// The zero box an earlier build wrote.
    private func zeroBox() throws -> Any { try object(CGRect.zero) }

    /// Keys at 0 (rest) and 8 (slid 12, turned 0.4 rad about the frame's centre) decomposed against a
    /// box with no area, the way that build wrote them once the artist keyed again.
    private func zeroBoxKeys() throws -> (track: [String: Any], moved: PoseQuad) {
        let moved = turned(12, 0.4)
        let v0 = try XCTUnwrap(PoseComponents.decompose(PoseQuad(restingIn: canvasBox), inBox: .zero))
        let v8 = try XCTUnwrap(PoseComponents.decompose(moved, inBox: .zero))
        var curves: [String: Any] = [:]
        for component in PoseComponents.Component.allCases where abs(v0[component] - v8[component]) > component.flatTolerance {
            curves[component.rawValue] = try object(AnimationCurve(keys: [
                AnimationCurve.Key(frame: 0, value: v0[component]), AnimationCurve.Key(frame: 8, value: v8[component])]))
        }
        return (["box": try zeroBox(), "curves": curves], moved)
    }

    // MARK: - Whole-pose keys

    /// **A transformation layer keyed before the change to curves opens with its keys and draws what the
    /// old build drew** — on the keys exactly, and between them to a millionth of a point, since a
    /// slide and a turn blend linearly in both.
    func testWholePoseKeysBecomeCurvesThatDrawWhatTheOldBuildDrew() throws {
        let keys = [(0, PoseQuad(restingIn: canvasBox)), (4, turned(6, 0.15)), (10, turned(18, 0.4))]
        let (url, layer) = try legacyPackage(keys: try keys.map { try legacyKey($0.0, $0.1) })

        let result = LegacyPoseTrackRepair.repair(packageAt: url)
        XCTAssertEqual(result.migrated, 1)

        let opened = try XCTUnwrap(ProjectStore.load(from: url), "the repaired file opens")
        XCTAssertFalse(opened.loadDamage.isDamaged)
        let pose = try XCTUnwrap(opened.layers.first { $0.id == layer }?.transform)
        XCTAssertEqual(pose.track.box, canvasBox, "A transformation layer's track is on the frame")
        XCTAssertEqual(pose.track.keyedFrames, [0, 4, 10], "Every old key is a key")
        XCTAssertEqual(components(of: pose.track), [.x, .rotation],
                       "…on the components the motion moves: a sideways slide and a turn about the centre move X and the angle")
        for frame in 0...12 {
            let want = try XCTUnwrap(legacyPose(keys.map { (frame: $0.0, pose: $0.1) }, atFrame: frame))
            let got = pose.resolvedPose(atFrame: frame)
            for (a, b) in zip([got.corners.p0, got.corners.p1, got.corners.p2, got.corners.p3],
                              [want.corners.p0, want.corners.p1, want.corners.p2, want.corners.p3]) {
                XCTAssertEqual(Double(a.x), Double(b.x), accuracy: 1e-6, "frame \(frame): the old build's picture")
                XCTAssertEqual(Double(a.y), Double(b.y), accuracy: 1e-6, "frame \(frame): the old build's picture")
            }
        }

        // Written once, then left alone.
        let bytes = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        XCTAssertFalse(LegacyPoseTrackRepair.repair(packageAt: url).changed, "A second run changes nothing")
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), bytes)
    }

    /// **The handles the old spine carried are carried too**: a key eased by hand, and a step held, reach
    /// each fraction of the segment at the same frame.
    func testTheOldTimingIsKeptHandleForHandle() throws {
        let rest = PoseQuad(restingIn: canvasBox)
        let slid = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 20, y: 0))
        let far = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 32, y: 10))
        var eased = try legacyKey(4, slid, tangent: "free")
        eased["outHandle"] = ["deltaFrames": 3.5, "deltaValue": 0.9]
        eased["inHandle"] = ["deltaFrames": -1, "deltaValue": -0.2]
        let (url, layer) = try legacyPackage(keys: [try legacyKey(0, rest, interpolation: "constant"), eased,
                                                    try legacyKey(12, far)])
        LegacyPoseTrackRepair.repair(packageAt: url)
        let pose = try XCTUnwrap(ProjectStore.load(from: url)?.layers.first { $0.id == layer }?.transform)

        let spine = AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 0, interpolation: .constant),
                         AnimationCurve.Key(frame: 4, value: 1, inHandle: .init(deltaFrames: -1, deltaValue: -0.2),
                                            outHandle: .init(deltaFrames: 3.5, deltaValue: 0.9), tangentMode: .free),
                         AnimationCurve.Key(frame: 12, value: 2)])
        let poses = [rest, slid, far]
        for frame in 0...14 {
            let index = spine.evaluate(at: Double(frame))
            let lower = min(max(Int(index.rounded(.down)), 0), 1)
            let want = try XCTUnwrap(PoseInterpolation.blend(poses[lower], poses[lower + 1], t: CGFloat(index - Double(lower))))
            let got = pose.resolvedPose(atFrame: frame)
            XCTAssertEqual(Double(got.corners.p0.x), Double(want.corners.p0.x), accuracy: 1e-6, "frame \(frame)")
            XCTAssertEqual(Double(got.corners.p0.y), Double(want.corners.p0.y), accuracy: 1e-6, "frame \(frame)")
        }
    }

    /// **A key that is not a map is left out and named, and the document opens.** A pose collapsed to a
    /// point cannot be the key of any component; the old build drew the nearer key where it fell, and
    /// the keys either side are still the artist's.
    func testAKeyThatIsNotAMapIsLeftOutAndNamedAndTheDocumentOpens() throws {
        let collapsed = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(scaleX: 0, y: 0))
        let (url, layer) = try legacyPackage(keys: [try legacyKey(0, collapsed),
                                                    try legacyKey(4, PoseQuad(restingIn: canvasBox)),
                                                    try legacyKey(8, turned(12, 0.4))])
        let result = LegacyPoseTrackRepair.repair(packageAt: url)
        XCTAssertEqual(result.skippedKeys, ["Keyed frame 0"], "Named, with the layer and the frame")

        let opened = try XCTUnwrap(ProjectStore.load(from: url), "one key the repair cannot carry must not make the document unreadable")
        XCTAssertEqual(opened.layers.first { $0.id == layer }?.transform?.track.keyedFrames, [4, 8], "The other two are kept")
    }

    // MARK: - A box with no area

    /// **An empty track on the zero box an earlier build wrote takes the frame**, and a Move between two
    /// primed frames then keys as on any layer.
    func testAnEmptyTrackOnABoxWithNoAreaTakesTheFrame() throws {
        let manager = scene()
        let layer = manager.layers[1].id
        let url = ProjectStore.createNewProjectURL(name: "Zero box")
        saveAndWait(manager, to: url)
        try rewriteTrack(ofLayer: layer, in: url, to: ["box": try zeroBox(), "curves": [String: Any]()])

        XCTAssertEqual(LegacyPoseTrackRepair.repair(packageAt: url).boxGiven, 1)

        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        let at = try XCTUnwrap(opened.layers.firstIndex { $0.id == layer })
        XCTAssertEqual(opened.layers[at].transform?.track.box, canvasBox)
        opened.currentLayerIndex = at
        let target = KeyframeTarget.layer(id: layer)
        opened.currentFrame = 0
        XCTAssertTrue(opened.addKeys(target, atFrame: 0))
        opened.currentFrame = 8
        XCTAssertTrue(opened.addKeys(target, atFrame: 8))
        XCTAssertTrue(move(opened, by: CGVector(dx: 9, dy: 0)))
        XCTAssertEqual(opened.layers[at].transform?.track.keyedFrames, [0, 8], "The Move keys, as on any layer")
    }

    /// **Keys the zero box was written under are read against the frame**: the layer draws what a
    /// healthy one with the same poses draws, at every frame including between the keys, and a Move on
    /// it writes.
    func testKeysOnABoxWithNoAreaDrawLikeAHealthyTrackAndAMoveWritesOnThem() throws {
        func build(zero: Bool) throws -> (url: URL, layer: UUID, moved: PoseQuad) {
            let manager = scene()
            let layer = manager.layers[1].id
            let (zeroTrack, moved) = try zeroBoxKeys()
            let v0 = try XCTUnwrap(PoseComponents.decompose(PoseQuad(restingIn: canvasBox), inBox: canvasBox))
            let v8 = try XCTUnwrap(PoseComponents.decompose(moved, inBox: canvasBox))
            var curves: [PoseComponents.Component: AnimationCurve] = [:]
            for component in PoseComponents.Component.allCases where abs(v0[component] - v8[component]) > component.flatTolerance {
                curves[component] = AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: v0[component]),
                                                          AnimationCurve.Key(frame: 8, value: v8[component])])
            }
            manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: canvasBox),
                                                    track: TransformTrack(box: canvasBox, curves: curves))
            let url = ProjectStore.createNewProjectURL(name: zero ? "zero" : "healthy")
            saveAndWait(manager, to: url)
            if zero { try rewriteTrack(ofLayer: layer, in: url, to: zeroTrack) }
            return (url, layer, moved)
        }
        let healthy = try build(zero: false)
        let damaged = try build(zero: true)
        XCTAssertEqual(LegacyPoseTrackRepair.repair(packageAt: healthy.url), LegacyPoseTrackRepair.PackageResult(), "A healthy file is left alone")
        XCTAssertEqual(LegacyPoseTrackRepair.repair(packageAt: damaged.url).rebased, 1)

        let good = try XCTUnwrap(ProjectStore.load(from: healthy.url))
        let repaired = try XCTUnwrap(ProjectStore.load(from: damaged.url))
        let track = try XCTUnwrap(repaired.layers[1].transform?.track)
        XCTAssertEqual(track.box, canvasBox)
        XCTAssertEqual(track.keyedFrames, [0, 8])
        XCTAssertEqual(components(of: track), components(of: good.layers[1].transform!.track),
                       "The components a Move would have keyed, and not the slide of the corner a turn about the centre read as")
        for frame in 0...10 {
            XCTAssertLessThanOrEqual(maxByteDifference(try composite(good, frame: frame), try composite(repaired, frame: frame)), 1,
                                     "frame \(frame): the same picture as the healthy track")
        }
        let half = repaired.layers[1].transform!.resolvedPose(atFrame: 4)
        let want = turned(6, 0.2)
        XCTAssertEqual(Double(half.corners.p0.x), Double(want.corners.p0.x), accuracy: 1e-6, "Halfway turns about the centre")
        XCTAssertEqual(Double(half.corners.p0.y), Double(want.corners.p0.y), accuracy: 1e-6)

        repaired.currentLayerIndex = 1
        repaired.currentFrame = 4
        let before = repaired.layers[1].transform
        XCTAssertTrue(move(repaired, by: CGVector(dx: 5, dy: 0)))
        XCTAssertNotEqual(repaired.layers[1].transform, before, "A Move on the repaired layer writes")
        XCTAssertTrue(repaired.layers[1].transform?.track.keyedFrames.contains(4) == true)
    }

    /// **A cel channel is the same**: keys on the zero box are read against the canvas, and an empty one
    /// is dropped, as a cel never holds a channel with no keys.
    func testCelChannelsOnABoxWithNoAreaAreReadAgainstTheCanvasOrDropped() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        let ink = manager.layers[0]
        CanvasFixture.setPoseTrack(manager, layerID: ink.id, celID: ink.cels[0].id, CanvasFixture.poseTrack(
            [(0, PoseQuad(restingIn: canvasBox)), (8, turned(12, 0.4))]))
        let url = ProjectStore.createNewProjectURL(name: "Cel zero")
        saveAndWait(manager, to: url)
        let sidecar = try animationFile(in: url)
        let (zeroTrack, _) = try zeroBoxKeys()
        try JSONSerialization.data(withJSONObject: ["tracks": ["cel": zeroTrack,
                                                               "group.1": ["box": try zeroBox(), "curves": [String: Any]()],
                                                               "group.2": ["box": try object(canvasBox), "curves": [String: Any]()]]])
            .write(to: sidecar)

        let result = LegacyPoseTrackRepair.repair(packageAt: url)
        XCTAssertEqual(result.rebased, 1)
        XCTAssertEqual(result.dropped, 2, "Empty channels go, on whatever box")

        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        let tracks = opened.layers[0].cels[0].transformTracks
        XCTAssertEqual(Array(tracks.keys), ["cel"], "The empty channel is gone")
        XCTAssertEqual(tracks["cel"]?.box, canvasBox)
        XCTAssertEqual(tracks["cel"]?.keyedFrames, [0, 8])
        XCTAssertEqual(tracks["cel"]?.curve(.x)?.key(atFrame: 8)?.value ?? .nan, Double(canvasCentre.x) + 12, accuracy: 1e-9,
                       "…and the key is where the centre is shown, as on any channel")
    }

    // MARK: - A cel channel written before curves

    func testACelChannelKeyedBeforeComponentCurvesOpensWithItsKeys() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        let ink = manager.layers[0]
        let rest = PoseQuad(restingIn: canvasBox)
        let slid = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 16, y: 0))
        CanvasFixture.setPoseTrack(manager, layerID: ink.id, celID: ink.cels[0].id,
                                   CanvasFixture.poseTrack([(0, rest), (8, slid)], interpolation: .linear))
        let url = ProjectStore.createNewProjectURL(name: "Pre-139 cel")
        saveAndWait(manager, to: url)
        let legacy: [String: Any] = ["tracks": ["cel": ["keys": [try legacyKey(0, rest), try legacyKey(8, slid)], "step": 1]]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: try animationFile(in: url))

        XCTAssertEqual(LegacyPoseTrackRepair.repair(packageAt: url).migrated, 1)

        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        let track = try XCTUnwrap(opened.layers[0].cels[0].transformTracks["cel"], "the channel opens")
        XCTAssertEqual(track.keyedFrames, [0, 8])
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 8)?.value ?? .nan, Double(canvasBox.midX) + 16, accuracy: 1e-9)
        XCTAssertFalse(opened.loadDamage.isDamaged, "Read, so nothing is reported lost")
    }

    // MARK: - The library

    /// A saved version of `project` in `Backups/`, the way the app files one.
    private func file(_ package: URL, asBackupNamed name: String, of id: UUID) throws -> URL {
        let slot = ProjectBackupManager.backupsDirectory(projectID: id).appendingPathComponent("\(name).paintproj")
        try FileManager.default.copyItem(at: package, to: slot)
        return slot
    }

    /// **The whole library is repaired — the project, its saved versions and the trash — except the
    /// running build's own snapshot, which keeps the original; and a second pass changes nothing.**
    func testTheWholeLibraryIsRepairedExceptTheSnapshotOfTheRunningBuild() throws {
        let keys = [try legacyKey(0, PoseQuad(restingIn: canvasBox)), try legacyKey(8, turned(12, 0.4))]
        let (project, layer) = try legacyPackage(keys: keys, name: "Shot")
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: project))
        let version = try file(project, asBackupNamed: "auto-20261010-000935", of: id)
        let snapshot = try file(project, asBackupNamed: "preupdate-1-0-43-9", of: id)
        let trashed = ProjectBackupManager.trashDirectory.appendingPathComponent("Old.paintproj")
        try FileManager.default.copyItem(at: project, to: trashed)
        let folder = ProjectBackupManager.projectsDirectory.appendingPathComponent("Scene 3", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filed = folder.appendingPathComponent("Filed.paintproj")
        try FileManager.default.copyItem(at: project, to: filed)
        let original = try Data(contentsOf: snapshot.appendingPathComponent("manifest.json"))

        let report = LegacyPoseTrackRepair.repairLibrary(leavingUntouched: "preupdate-1-0-43-9")

        XCTAssertEqual(Set(report.packages.keys),
                       ["Projects/Shot.paintproj", "Projects/Scene 3/Filed.paintproj", "Trash/Old.paintproj",
                        "Backups/\(id.uuidString)/auto-20261010-000935.paintproj"],
                       "Projects (filed ones too), saved versions and trash")
        for package in [project, filed, trashed, version] {
            let opened = try XCTUnwrap(ProjectStore.load(from: package), "\(package.lastPathComponent) opens")
            XCTAssertEqual(opened.layers.first { $0.id == layer }?.transform?.track.keyedFrames, [0, 8],
                           "\(package.lastPathComponent) holds its keys")
        }
        XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent("manifest.json")), original,
                       "The running build's snapshot keeps the untouched original")
        XCTAssertNil(ProjectStore.load(from: snapshot), "…which the current decoder refuses rather than reading as no keys")

        XCTAssertEqual(LegacyPoseTrackRepair.repairLibrary(leavingUntouched: "preupdate-1-0-43-9"), LegacyPoseTrackRepair.Report(),
                       "A second pass has nothing to do")
    }

    /// **The launch pass runs it, after the snapshot**: the project opens with its keys and the
    /// "Before app update" version is the file as it was.
    func testStartupMaintenanceRepairsTheProjectAfterSnapshottingTheOriginal() throws {
        let keys = [try legacyKey(0, PoseQuad(restingIn: canvasBox)), try legacyKey(8, turned(12, 0.4))]
        let (project, layer) = try legacyPackage(keys: keys, name: "Launch")
        let original = try Data(contentsOf: project.appendingPathComponent("manifest.json"))

        ProjectBackupManager.runStartupMaintenance()

        let opened = try XCTUnwrap(ProjectStore.load(from: project), "the project opens after the launch pass")
        XCTAssertEqual(opened.layers.first { $0.id == layer }?.transform?.track.keyedFrames, [0, 8])
        let versions = ProjectBackupManager.listBackups(forProjectAt: project).filter { $0.label == "Before app update" }
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(try Data(contentsOf: versions[0].url.appendingPathComponent("manifest.json")), original,
                       "The snapshot the update took is the untouched file")
    }

    /// **A file already in the current format is not rewritten** — not its bytes, not its layout — and the
    /// rest of a repaired manifest is what it was.
    func testWhatIsNotATrackIsLeftExactlyAsItWas() throws {
        let manager = scene()
        manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: canvasBox), mode: .shake, shakeSeed: UInt64.max - 3)
        let url = ProjectStore.createNewProjectURL(name: "Current")
        saveAndWait(manager, to: url)
        let bytes = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        XCTAssertEqual(LegacyPoseTrackRepair.repair(packageAt: url), LegacyPoseTrackRepair.PackageResult())
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), bytes)

        let (legacy, layer) = try legacyPackage(keys: [try legacyKey(0, PoseQuad(restingIn: canvasBox)),
                                                       try legacyKey(8, turned(12, 0.4))])
        var before = try readManifest(legacy)
        LegacyPoseTrackRepair.repair(packageAt: legacy)
        var after = try readManifest(legacy)
        func withoutTrack(_ manifest: inout [String: Any]) {
            var layers = manifest["layers"] as! [[String: Any]]
            for index in layers.indices where (layers[index]["id"] as? String) == layer.uuidString {
                var transform = layers[index]["transform"] as! [String: Any]
                transform.removeValue(forKey: "track")
                layers[index]["transform"] = transform
            }
            manifest["layers"] = layers
        }
        withoutTrack(&before)
        withoutTrack(&after)
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after),
                       "Every other field of the manifest is what it was")
        _ = try track(ofLayer: layer, in: legacy)
    }
}
