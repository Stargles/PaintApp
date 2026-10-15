import CoreGraphics
import Foundation
import UIKit

enum LiquifyMode: String, Codable, CaseIterable, Identifiable {
    case push, pinch, expand, twirl
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .push: return "Push"
        case .pinch: return "Pinch"
        case .expand: return "Expand"
        case .twirl: return "Twirl"
        }
    }
}

/// The compact definition of a brush displacement field. It keeps the same walk, channels and
/// seed the brush renderer consumes, rather than an eight-byte displacement at every canvas pixel.
/// It is recipe-owned in rest space through immutable capture geometry; no saved vertex indices.
struct LiquifyDeformation: Codable, Equatable {
    var id = UUID()
    var brush: Brush
    var size: CGFloat
    var power: Double
    var mode: LiquifyMode
    var seed: UInt64
    var path: PackedSampleRun
    /// The selection is captured with the gesture, using the fill's existing secure path archive.
    var selection: Data?
    /// Element UUIDs are not globally unique: copying a cel retains them. Source occurrence,
    /// local edit, and reprojection subject identities therefore occupy separate namespaces.
    struct InkID: Codable, Hashable {
        enum Kind: String, Codable { case source, local, subject }
        var kind: Kind
        var elementID: UUID
        var reference: CelRef?
        init(kind: Kind, elementID: UUID, reference: CelRef? = nil) {
            precondition((kind == .source) == (reference != nil))
            self.kind = kind; self.elementID = elementID; self.reference = reference
        }
        private enum CodingKeys: String, CodingKey { case kind, elementID, reference }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(Kind.self, forKey: .kind)
            elementID = try c.decode(UUID.self, forKey: .elementID)
            reference = try c.decodeIfPresent(CelRef.self, forKey: .reference)
            guard (kind == .source) == (reference != nil) else {
                throw DecodingError.dataCorruptedError(forKey: .reference, in: c, debugDescription: "source ink requires a cel occurrence; local and subject ink cannot have one")
            }
        }
        var canonicalKey: String {
            kind.rawValue + ":" + (reference.map { $0.layerID.uuidString + ":" + $0.celID.uuidString } ?? "") + ":" + elementID.uuidString
        }
    }
    struct Capture: Codable, Equatable {
        var groupID: UUID?
        var lattice: Lattice
        var inkIDs: Set<InkID>
        init(groupID: UUID?, lattice: Lattice, inkIDs: Set<InkID> = []) {
            self.groupID = groupID; self.lattice = lattice; self.inkIDs = inkIDs
        }
        private enum CodingKeys: String, CodingKey { case groupID, lattice, inkIDs }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Explicit null denotes unbound ink; a missing field is an unreadable format.
            guard c.contains(.groupID) else {
                throw DecodingError.keyNotFound(CodingKeys.groupID, .init(codingPath: decoder.codingPath, debugDescription: "missing capture group"))
            }
            groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
            lattice = try c.decode(Lattice.self, forKey: .lattice)
            let members = try c.decode([InkID].self, forKey: .inkIDs)
            inkIDs = Set(members)
            guard members.count == inkIDs.count else {
                throw DecodingError.dataCorruptedError(forKey: .inkIDs, in: c, debugDescription: "duplicate capture ink occurrence")
            }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let groupID { try c.encode(groupID, forKey: .groupID) } else { try c.encodeNil(forKey: .groupID) }
            try c.encode(lattice, forKey: .lattice)
            try c.encode(inkIDs.sorted { $0.canonicalKey < $1.canonicalKey }, forKey: .inkIDs)
        }
    }
    struct Membership {
        var id: InkID
        var groupID: UUID?
    }
    /// Existing ink owns its capture even after regrouping. Newly drawn ink inherits a surviving
    /// group, or the one unambiguous lineage in its replacement group. Merged lineages do not guess.
    struct CaptureResolver {
        let captures: [Capture]
        let members: [Membership]
        func capture(for id: InkID, groupID: UUID?) -> Capture? {
            if let own = captures.first(where: { $0.inkIDs.contains(id) }) { return own }
            // Local marks are authored at the shown frame after prior gestures. Only gestures
            // that actually captured this LocalEdit.id may touch them; source edits inherit groups.
            if id.kind == .local { return nil }
            if let same = captures.first(where: { $0.groupID == groupID }) { return same }
            let current = Set(members.filter { $0.groupID == groupID }.map(\.id))
            let lineage = captures.filter { !$0.inkIDs.isDisjoint(with: current) }
            return lineage.count == 1 ? lineage[0] : nil
        }
    }
    var captures: [Capture] = []

    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.brush == b.brush && a.size == b.size && a.power == b.power &&
        a.mode == b.mode && a.seed == b.seed && a.path.origin == b.path.origin && a.path.channels == b.path.channels && a.path.bytes == b.path.bytes &&
        a.selection == b.selection && a.captures == b.captures
    }

    init(brush: Brush, size: CGFloat, power: Double, mode: LiquifyMode, seed: UInt64,
         samples: StrokeSamples, selection: CGPath? = nil, captures: [Capture] = []) {
        self.brush = brush; self.size = size; self.power = power; self.mode = mode; self.seed = seed
        path = PackedSampleRun(samples, about: samples.positions.first ?? .zero, precise: true)
        self.selection = selection.map { VectorFillElement(path: $0, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)).pathData }
        self.captures = captures
    }

    private enum CodingKeys: String, CodingKey {
        case id, brush, size, power, mode, seed, path, selection, captures
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        brush = try c.decode(Brush.self, forKey: .brush)
        size = try c.decode(CGFloat.self, forKey: .size)
        power = try c.decode(Double.self, forKey: .power)
        mode = try c.decode(LiquifyMode.self, forKey: .mode)
        seed = try c.decode(UInt64.self, forKey: .seed)
        path = try c.decode(PackedSampleRun.self, forKey: .path)
        selection = try c.decodeIfPresent(Data.self, forKey: .selection)
        if let selection, VectorFillElement.decodePath(selection) == nil {
            throw DecodingError.dataCorruptedError(forKey: .selection, in: c,
                debugDescription: "unreadable Liquify selection path archive")
        }
        captures = try c.decode([Capture].self, forKey: .captures)
    }

    /// The compact operation can retain this support without retaining a prepared field. Use the
    /// already-prepared field's bounds when available; archive decode needs only the native walk.
    var materialSupportBounds: CGRect {
        let collector = BrushStamper.CollectingDabTarget()
        var walk = BrushStamper.LiveWalk(seed: seed)
        for sample in path.samples {
            walk.stamp(to: sample, into: collector, brush: brush, color: .white, brushSize: size)
        }
        walk.finish(into: collector, brush: brush, color: .white, brushSize: size)
        return collector.dabs.reduce(CGRect.null) { $0.union(LiquifyField.replacementBounds(of: $1)) }
    }

    var selectionPath: CGPath? {
        guard let selection else { return nil }
        return VectorFillElement.decodePath(selection)
    }

    func restBounds(capture: Capture, using field: LiquifyField) -> CGRect? {
        let box = field.bounds
        guard !box.isNull else { return nil }
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        let points = corners + capture.lattice.vertices.filter { box.contains($0) }
        let rest = capture.lattice.warpToRest(capture.lattice.embedInCurrent(points))
        var result = rest.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
        // A bilinear cell edge can cross the field box between its corners. Include the rest
        // rectangle of every possibly intersecting cell, rather than assuming corner extrema.
        let lattice = capture.lattice
        for cell in 0..<(lattice.cols * lattice.rows) {
            let c = lattice.corners(ofCell: cell)
            let vertices = [c.0, c.1, c.2, c.3].map { lattice.vertices[$0] }
            let current = vertices.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
            guard current.intersects(box) else { continue }
            let origin = CGPoint(x: lattice.restOrigin.x + CGFloat(cell % lattice.cols) * lattice.restCellSize,
                                 y: lattice.restOrigin.y + CGFloat(cell / lattice.cols) * lattice.restCellSize)
            result = result.union(CGRect(origin: origin, size: CGSize(width: lattice.restCellSize, height: lattice.restCellSize)))
        }
        return result
    }

    func touchesRest(_ points: [CGPoint], capture: Capture, using field: LiquifyField) -> Bool {
        let captured = capture.lattice.warp(capture.lattice.embedInRest(points))
        return field.intersects(captured)
    }

    func mapRest(_ points: [CGPoint], capture: Capture, using field: LiquifyField) -> [CGPoint] {
        let shown = capture.lattice.warp(capture.lattice.embedInRest(points))
        let moved = shown.map(field.map)
        return zip(points.indices, zip(shown, moved)).map { index, pair in
            guard pair.0 != pair.1 else { return points[index] }
            return capture.lattice.warpToRest(capture.lattice.embedInCurrent([pair.1]))[0]
        }
    }
}
