import CoreGraphics
import Foundation
import os

/// **THROWAWAY: rewrites the pose tracks that earlier builds wrote into the current format, once, at
/// launch, over the whole library — and is deleted when the owner confirms their files are repaired.**
///
/// The app's decoder (`TransformTrack`, `LayerPose`, `CelAnimationData`) reads the current format and
/// nothing else, strictly: a track it cannot read is a document it cannot read, never a track with no
/// keys. Three shapes of file are not the current format, and this is the only place that knows them:
///
///  * **Whole-pose keys** (`"track": {"keys": […], "step": 1}`), which a track was before it became one
///    curve per component. Each key's pose is decomposed against the channel's box and the components
///    that move become curves with a key at every old key's frame. The old track drew a pose at frame
///    `f` as `blend(pose[i], pose[i+1], s)`, `s` being its *timing spine* — one curve through the key
///    indices 0, 1, 2… with the keys' own handles — read at `f`. **That spine's handles are carried
///    exactly**: each segment's handle heights are the spine's, scaled by how far that component
///    travels across the segment, as `.free` handles, so every component reaches every fraction of its
///    segment at the very frame the old pose did. The keys are the old poses exactly; between them a
///    slide and a turn are the old blend exactly, since that blend moves the box's centre and its angle
///    linearly in the spine, as these curves do.
///  * **An empty track on a box with no area** (`"box": [[0,0],[0,0]]`), which is what an earlier build
///    wrote over every whole-pose track it could not read. A transformation layer's track takes the
///    pose's box, which is the frame; a cel's is dropped, as a cel never holds a channel with no keys.
///  * **Keys on a box with no area**, which the same build wrote when the artist keyed such a layer
///    again. A box with no area has no corners, so no pose resolves on it and a Move composes onto
///    nothing. Every frame a component keys is evaluated against the old box and the map those values
///    make is decomposed against the frame (a cel's: the canvas): the keys then describe the same maps,
///    exactly on their own frames, and between them the layer pivots about the frame's centre rather
///    than the canvas corner. Handles of keys that carry their own are kept as they were.
///
/// **A whole-pose key that is not a map** (a pose collapsed to a line) cannot be a key of any
/// component; it is left out and named in the report and the log. The package it came from keeps its
/// original in the `preupdate-` snapshot this build took before it ran.
///
/// ## What it walks and how it writes
///
/// Every package under `Projects/`, `Backups/` and `Trash/` of the library root — the saved versions
/// are where the owner's keys still were — except the running build's own `preupdate-` snapshot, which
/// keeps the untouched originals. A file is rewritten only when a track in it changed, atomically, and
/// a second run changes nothing, so it can run on every launch until it is deleted.
///
/// ## Deleting it
///
/// This file, `LegacyPoseTrackRepairLogicTests.swift`, the call in
/// `ProjectBackupManager.runStartupMaintenance` and the two files' entries in `project.pbxproj`.
nonisolated enum LegacyPoseTrackRepair {

    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "PoseTrackRepair")

    /// What the repair did to one package.
    struct PackageResult: Equatable {
        /// Whole-pose tracks rewritten as curves.
        var migrated = 0
        /// Tracks whose keys were re-read against a box that has area.
        var rebased = 0
        /// Empty transformation-layer tracks given the frame as their box.
        var boxGiven = 0
        /// Empty cel channels dropped.
        var dropped = 0
        /// Whole-pose keys that are not a map, left out: `"<layer or channel> frame <n>"`.
        var skippedKeys: [String] = []
        /// Files that could not be written back.
        var failed: [String] = []

        var changed: Bool { migrated + rebased + boxGiven + dropped > 0 }
    }

    /// The packages the pass touched, or could not, by their path below the library root.
    struct Report: Equatable {
        var packages: [String: PackageResult] = [:]
    }

    // MARK: - The library

    /// Repairs every package in the library, and returns what it did.
    ///
    /// - Parameter leavingUntouched: the name prefix of the snapshot slots to skip — the running
    ///   build's own `preupdate-` clones, taken before this ran.
    @discardableResult
    static func repairLibrary(leavingUntouched untouchedPrefix: String) -> Report {
        let root = ProjectBackupManager.documentsDirectory
        let rootComponents = root.standardizedFileURL.pathComponents
        var report = Report()
        for directory in ["Projects", "Backups", "Trash"] {
            let walked = ProjectBackupManager.allProjectPackages(
                in: root.appendingPathComponent(directory, isDirectory: true))
            for package in walked where !package.lastPathComponent.hasPrefix(untouchedPrefix) {
                let result = repair(packageAt: package)
                guard result.changed || !result.skippedKeys.isEmpty || !result.failed.isEmpty else { continue }
                let path = package.standardizedFileURL.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
                report.packages[path] = result
                if !result.skippedKeys.isEmpty || !result.failed.isEmpty {
                    log.error("""
                        \(path, privacy: .public): left out \(result.skippedKeys.joined(separator: ", "), privacy: .public); \
                        could not write \(result.failed.joined(separator: ", "), privacy: .public)
                        """)
                }
            }
        }
        if !report.packages.isEmpty {
            log.info("Pose tracks repaired in \(report.packages.count, privacy: .public) package(s)")
        }
        return report
    }

    // MARK: - One package

    @discardableResult
    static func repair(packageAt package: URL) -> PackageResult {
        var result = PackageResult()
        let modified = (try? FileManager.default.attributesOfItem(atPath: package.path))?[.modificationDate] as? Date
        repairManifest(in: package, result: &result)
        lazy var canvas = readCanvas(of: package)
        for sidecar in animationFiles(in: package) {
            repairSidecar(at: sidecar, canvas: { canvas }, result: &result)
        }
        // A saved version without a timestamp in its name is dated by its package folder, which the
        // rewrite just touched.
        if result.changed, let modified {
            try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: package.path)
        }
        return result
    }

    private static func readCanvas(of package: URL) -> CGRect? {
        guard let data = try? Data(contentsOf: package.appendingPathComponent("manifest.json")),
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let width = manifest["canvasWidth"] as? Double, let height = manifest["canvasHeight"] as? Double,
              width > 0, height > 0 else { return nil }
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    /// The cel animation files of a package, wherever its layout keeps them.
    private static func animationFiles(in package: URL) -> [URL] {
        ["drawings", "images"].flatMap { directory -> [URL] in
            let folder = package.appendingPathComponent(directory, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { $0.hasSuffix("-animation.json") || $0.hasSuffix("_anim.json") }
                .map { folder.appendingPathComponent($0) }
        }
    }

    private static func repairManifest(in package: URL, result: inout PackageResult) {
        let url = package.appendingPathComponent("manifest.json")
        // Only a manifest that names a track is parsed: the pass runs on every launch and most
        // packages hold none.
        guard let data = try? Data(contentsOf: url), data.range(of: Data("\"track\"".utf8)) != nil,
              var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var layers = manifest["layers"] as? [[String: Any]] else { return }
        var changed = false
        for index in layers.indices {
            guard var transform = layers[index]["transform"] as? [String: Any],
                  let pose = decode(PoseQuad.self, from: transform["pose"]),
                  let object = transform["track"] as? [String: Any],
                  let repaired = repairedTrack(object, target: .container(pose)),
                  let track = repaired.track, let written = json(of: track) else { continue }
            transform["track"] = written
            layers[index]["transform"] = transform
            changed = true
            record(repaired, as: layers[index]["name"] as? String ?? "layer", in: &result)
        }
        guard changed else { return }
        manifest["layers"] = layers
        if !write(manifest, to: url) { result.failed.append(url.lastPathComponent) }
    }

    private static func repairSidecar(at url: URL, canvas: @escaping () -> CGRect?, result: inout PackageResult) {
        guard let data = try? Data(contentsOf: url),
              var sidecar = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var tracks = sidecar["tracks"] as? [String: Any] else { return }
        var changed = false
        for (id, value) in tracks {
            guard let object = value as? [String: Any],
                  let repaired = repairedTrack(object, target: .cel(canvas: canvas)) else { continue }
            if let track = repaired.track {
                guard let written = json(of: track) else { continue }
                tracks[id] = written
            } else {
                tracks.removeValue(forKey: id)
            }
            changed = true
            record(repaired, as: id, in: &result)
        }
        guard changed else { return }
        sidecar["tracks"] = tracks
        if !write(sidecar, to: url) { result.failed.append(url.lastPathComponent) }
    }

    private static func record(_ repaired: Repaired, as name: String, in result: inout PackageResult) {
        switch repaired.kind {
        case .migrated: result.migrated += 1
        case .rebased: result.rebased += 1
        case .boxGiven: result.boxGiven += 1
        case .dropped: result.dropped += 1
        }
        result.skippedKeys += repaired.skippedFrames.map { "\(name) frame \($0)" }
    }

    // MARK: - One track

    private enum Target {
        /// A transformation layer's track, read against the layer's own pose and its frame.
        case container(PoseQuad)
        /// A cel channel, whose canvas is read from the manifest only if a track needs it.
        case cel(canvas: () -> CGRect?)
    }

    private struct Repaired {
        enum Kind { case migrated, rebased, boxGiven, dropped }
        var kind: Kind
        /// Nil drops the channel.
        var track: TransformTrack?
        var skippedFrames: [Int] = []
    }

    /// The current-format track a file's track becomes, or nil when it is already right or cannot be read
    /// at all (the app's decoder then says so).
    private static func repairedTrack(_ object: [String: Any], target: Target) -> Repaired? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        if object["curves"] == nil, object["keys"] != nil {
            guard let legacy = try? JSONDecoder().decode(WholePoseTrack.self, from: data) else { return nil }
            return migrated(legacy, target: target)
        }
        guard let track = try? JSONDecoder().decode(TransformTrack.self, from: data) else { return nil }
        switch target {
        case .container(let pose):
            if hasArea(track.box) { return nil }
            guard !track.isEmpty else { return Repaired(kind: .boxGiven, track: TransformTrack(box: pose.box)) }
            let base = PoseComponents.decompose(pose, inBox: track.box) ?? .resting(in: track.box)
            return Repaired(kind: .rebased, track: rebased(track, onto: pose.box, base: base))
        case .cel(let canvas):
            guard !track.isEmpty else { return Repaired(kind: .dropped, track: nil) }
            guard !hasArea(track.box) else { return nil }
            guard let frame = canvas() else { return nil }
            let reread = rebased(track, onto: frame, base: track.restValues)
            return Repaired(kind: reread.isEmpty ? .dropped : .rebased, track: reread.isEmpty ? nil : reread)
        }
    }

    private static func hasArea(_ box: CGRect) -> Bool { box.width > 0 && box.height > 0 }

    // MARK: Keys on a box with no area

    /// `track` with every key re-read against `box`; see the type's note.
    private static func rebased(_ track: TransformTrack, onto box: CGRect,
                                base: PoseComponents.Values) -> TransformTrack {
        func shown(atFrame frame: Int) -> PoseComponents.Values {
            var values = base
            for component in PoseComponents.Component.allCases {
                guard let curve = track.curve(component) else { continue }
                values[component] = curve.key(atFrame: frame)?.value ?? curve.evaluate(at: Double(frame))
            }
            return values
        }
        let rereadBase = PoseComponents.map(base, box: track.box)
            .flatMap { PoseComponents.decompose($0, box: box) } ?? .resting(in: box)
        var reread: [Int: PoseComponents.Values] = [:]
        var turn = 0.0
        for frame in track.keyedFrames {
            guard let map = PoseComponents.map(shown(atFrame: frame), box: track.box),
                  let values = PoseComponents.decompose(map, box: box)?.unwrappingRotation(near: turn) else { continue }
            turn = values.rotation
            reread[frame] = values
        }
        // A component whose re-read keys all sit at its base is dropped: X and Y of a turn about the
        // centre, which the old box read as a slide of its corner, are not keys a Move would write.
        var curves: [PoseComponents.Component: AnimationCurve] = [:]
        for component in PoseComponents.Component.allCases {
            guard let curve = track.curve(component) else { continue }
            let keys = curve.keys.map { key -> AnimationCurve.Key in
                var key = key
                key.value = reread[key.frame]?[component] ?? key.value
                return key
            }
            guard keys.contains(where: { abs($0.value - rereadBase[component]) > component.flatTolerance }) else { continue }
            curves[component] = AnimationCurve(keys: keys, step: curve.step)
        }
        return TransformTrack(box: box, curves: curves)
    }

    // MARK: Whole-pose keys

    private struct WholePoseTrack: Decodable {
        var keys: [WholePoseKey]
        var step: Int?
    }

    /// One key of a track written before it became one curve per component: a whole pose at a frame,
    /// on a timing spine every component shared.
    private struct WholePoseKey: Decodable {
        let frame: Int
        let pose: PoseQuad
        let inHandle: AnimationCurve.Handle
        let outHandle: AnimationCurve.Handle
        let tangentMode: AnimationCurve.TangentMode
        let interpolation: AnimationCurve.Interpolation

        private enum CodingKeys: String, CodingKey { case frame, pose, inHandle, outHandle, tangentMode, interpolation }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frame = try c.decode(Int.self, forKey: .frame)
            pose = try c.decode(PoseQuad.self, forKey: .pose)
            inHandle = try c.decodeIfPresent(AnimationCurve.Handle.self, forKey: .inHandle) ?? .zero
            outHandle = try c.decodeIfPresent(AnimationCurve.Handle.self, forKey: .outHandle) ?? .zero
            tangentMode = try c.decodeIfPresent(AnimationCurve.TangentMode.self, forKey: .tangentMode) ?? .autoClamped
            interpolation = try c.decodeIfPresent(AnimationCurve.Interpolation.self, forKey: .interpolation) ?? .bezier
        }
    }

    /// The curves a whole-pose track means; see the type's note. A transformation layer's keys are read
    /// against its frame, a cel's against its first key's box. A component no key moves off rest is left
    /// unkeyed, so it shows the channel's base — for a cel rest, for a layer its stored pose, which the
    /// old model rewrote on every keying Move to the pose it keyed.
    private static func migrated(_ legacy: WholePoseTrack, target: Target) -> Repaired {
        var byFrame: [Int: WholePoseKey] = [:]
        for key in legacy.keys { byFrame[key.frame] = key }
        let ordered = byFrame.keys.sorted().compactMap { byFrame[$0] }
        let box: CGRect
        switch target {
        case .container(let pose): box = pose.box
        case .cel: box = ordered.first?.pose.box ?? .zero
        }

        var keys: [WholePoseKey] = []
        var values: [PoseComponents.Values] = []
        var skipped: [Int] = []
        for key in ordered {
            guard var decomposed = PoseComponents.decompose(key.pose, inBox: box) else {
                skipped.append(key.frame)
                continue
            }
            if let previous = values.last { decomposed = decomposed.unwrappingRotation(near: previous.rotation) }
            keys.append(key)
            values.append(decomposed)
        }
        let step = legacy.step ?? 1
        guard !keys.isEmpty else {
            switch target {
            case .container: return Repaired(kind: .migrated, track: TransformTrack(box: box), skippedFrames: skipped)
            case .cel: return Repaired(kind: .dropped, track: nil, skippedFrames: skipped)
            }
        }

        let spine = AnimationCurve(keys: keys.enumerated().map { index, key in
            AnimationCurve.Key(frame: key.frame, value: Double(index), inHandle: key.inHandle,
                               outHandle: key.outHandle, tangentMode: key.tangentMode,
                               interpolation: key.interpolation)
        }, step: step)
        let handles = keys.indices.map { spine.effectiveHandles(at: $0) }
        let rest = PoseComponents.Values.resting(in: box)

        var curves: [PoseComponents.Component: AnimationCurve] = [:]
        for component in PoseComponents.Component.allCases {
            let series = values.map { $0[component] }
            guard series.contains(where: { abs($0 - rest[component]) > component.flatTolerance }) else { continue }
            curves[component] = AnimationCurve(keys: keys.indices.map { i in
                let into = i > 0 ? series[i] - series[i - 1] : 0
                let onward = i < keys.count - 1 ? series[i + 1] - series[i] : 0
                return AnimationCurve.Key(
                    frame: keys[i].frame, value: series[i],
                    inHandle: AnimationCurve.Handle(deltaFrames: handles[i].inHandle.deltaFrames,
                                                    deltaValue: handles[i].inHandle.deltaValue * into),
                    outHandle: AnimationCurve.Handle(deltaFrames: handles[i].outHandle.deltaFrames,
                                                     deltaValue: handles[i].outHandle.deltaValue * onward),
                    tangentMode: .free, interpolation: keys[i].interpolation)
            }, step: step)
        }
        return Repaired(kind: .migrated, track: TransformTrack(box: box, curves: curves), skippedFrames: skipped)
    }

    // MARK: - JSON

    private static func decode<T: Decodable>(_ type: T.Type, from object: Any?) -> T? {
        guard let object, let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func json(of track: TransformTrack) -> Any? {
        (try? JSONEncoder().encode(track)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    private static func write(_ object: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
