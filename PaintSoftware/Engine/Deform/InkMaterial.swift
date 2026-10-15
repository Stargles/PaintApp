import Foundation
import CoreGraphics

/// Fatal archive damage, deliberately distinct from the geometry errors a lossy element slot can
/// quarantine. An unreadable material reference must never turn a drawing into undeformed ink.
enum InkMaterialCodingError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let reason): return "Invalid ink material: " + reason }
    }

    static func preserving<T>(_ read: () throws -> T) throws -> T {
        do { return try read() }
        catch let error as InkMaterialCodingError { throw error }
        catch { throw InkMaterialCodingError.invalid(String(describing: error)) }
    }
}

/// Runtime references are self-contained and immutable. Detached canvases, clipboard elements and
/// cut pieces retain the definition; only a scoped archive converts it to a UUID reference.
final class InkMaterialOperation: Equatable {
    let deformation: LiquifyDeformation
    var id: UUID { deformation.id }
    /// Compact derived support only. Runtime ownership never retains prepared numerical fields.
    let supportBounds: CGRect
    init(_ deformation: LiquifyDeformation, supportBounds: CGRect? = nil) {
        self.deformation = deformation
        self.supportBounds = supportBounds ?? deformation.materialSupportBounds
    }
    static func == (lhs: InkMaterialOperation, rhs: InkMaterialOperation) -> Bool {
        lhs === rhs || lhs.deformation == rhs.deformation
    }
}

/// A field's coordinates relative to the material's current shown space. Ordinary ink starts with
/// identity. Later poses conjugate it; a linked group uses the same immutable capture and current
/// lattice geometry that its authoritative vector points use.
enum InkMaterialBridge: Equatable, Codable {
    case identity
    case homography(Homography)
    indirect case lattice(captured: Lattice, current: Lattice, pose: Homography)
    case sequence([InkMaterialBridge])

    /// Forward transport, in order. Identity and adjacent projective maps stay compact.
    func followed(by outer: InkMaterialBridge) -> InkMaterialBridge {
        if outer == .identity { return self }
        if self == .identity { return outer }
        if case .homography(let a) = self, case .homography(let b) = outer { return .homography(b * a) }
        let before: [InkMaterialBridge]
        let after: [InkMaterialBridge]
        if case .sequence(let parts) = self { before = parts } else { before = [self] }
        if case .sequence(let parts) = outer { after = parts } else { after = [outer] }
        return .sequence(before + after)
    }

    /// A material base transport acts between the already-posed native group and spatial ops.
    /// Moving the native group as well conjugates this transport rather than applying Move twice.
    func moved(by map: Homography) -> InkMaterialBridge {
        guard self != .identity else { return self }
        guard let inverse = map.inverse else { return .homography(map) }
        return InkMaterialBridge.homography(inverse).followed(by: self).followed(by: .homography(map))
    }

    /// The largest temporary lattice index and vertex array needed by one geometry-map step.
    /// Sequences execute one step at a time; callers reserve their own point arrays separately.
    var mappingScratchByteUpperBound: Int {
        switch self {
        case .identity, .homography: return 0
        case .lattice(let a, let b, _):
            let index = max(DeformedCellIndex.storageByteUpperBound(lattice: a), DeformedCellIndex.storageByteUpperBound(lattice: b))
            let vertices = max(a.vertexCount, b.vertexCount) * MemoryLayout<CGPoint>.stride
            return index > Int.max - vertices ? Int.max : index + vertices
        case .sequence(let parts): return parts.map(\.mappingScratchByteUpperBound).max() ?? 0
        }
    }

    /// A failed runtime transport refuses its render; it never substitutes the undeformed point.
    /// Lattice extrapolation uses the existing deterministic cell inverse, including outside grids.
    func map(_ points: [CGPoint], inverse: Bool = false) -> [CGPoint]? {
        guard points.allSatisfy(Self.supportsCoordinates) else { return nil }
        let result: [CGPoint]
        switch self {
        case .identity: return points
        case .homography(let map):
            guard let transform = inverse ? map.inverse : map, transform.inverse != nil else { return nil }
            result = points.compactMap(transform.map)
        case .lattice(let captured, let current, let pose):
            guard let unpose = pose.inverse else { return nil }
            if inverse {
                let shown = points.compactMap(unpose.map)
                guard shown.count == points.count else { return nil }
                let rest = current.warpToRest(current.embedInCurrent(shown))
                guard Self.canEmbed(rest, in: captured) else { return nil }
                result = captured.warp(captured.embedInRest(rest))
            } else {
                let rest = captured.warpToRest(captured.embedInCurrent(points))
                guard Self.canEmbed(rest, in: current) else { return nil }
                result = current.warp(current.embedInRest(rest)).compactMap(pose.map)
            }
        case .sequence(let parts):
            var mapped = points
            for part in inverse ? Array(parts.reversed()) : parts {
                guard let next = part.map(mapped, inverse: inverse) else { return nil }; mapped = next
            }
            result = mapped
        }
        return result.count == points.count && result.allSatisfy(Self.supportsCoordinates) ? result : nil
    }

    private static func supportsCoordinates(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && abs(point.x) < CGFloat(Int.max / 4) && abs(point.y) < CGFloat(Int.max / 4)
    }

    private static func canEmbed(_ points: [CGPoint], in lattice: Lattice) -> Bool {
        points.allSatisfy {
            let x = ($0.x - lattice.restOrigin.x) / lattice.restCellSize
            let y = ($0.y - lattice.restOrigin.y) / lattice.restCellSize
            return x.isFinite && y.isFinite && abs(x) < CGFloat(Int.max / 4) && abs(y) < CGFloat(Int.max / 4)
        }
    }

    /// Conservative support through lattice cell boundaries. Mapping only a box's corners misses
    /// extrema where its edges cross a bilinear cell, including when no grid vertex is inside it.
    func bounds(of box: CGRect) -> CGRect {
        guard !box.isNull, !box.isInfinite else { return box }
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        func enclosing(_ points: [CGPoint]) -> CGRect {
            points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
        }
        switch self {
        case .identity: return box
        case .homography(let map):
            let weights = corners.map { map.g * $0.x + map.h * $0.y + map.i }
            guard weights.allSatisfy({ $0 > Lattice.epsilon }) || weights.allSatisfy({ $0 < -Lattice.epsilon }) else { return .infinite }
            let moved = corners.compactMap(map.map)
            return moved.count == 4 ? enclosing(moved) : .infinite
        case .lattice(let captured, let current, let pose):
            var rest = enclosing(captured.carriedToRest(corners))
            for cell in 0..<(captured.cols * captured.rows) {
                let indices = captured.corners(ofCell: cell)
                let cellBox = enclosing([indices.0, indices.1, indices.2, indices.3].map { captured.vertices[$0] })
                guard cellBox.intersects(box) else { continue }
                let origin = CGPoint(x: captured.restOrigin.x + CGFloat(cell % captured.cols) * captured.restCellSize,
                    y: captured.restOrigin.y + CGFloat(cell / captured.cols) * captured.restCellSize)
                rest = rest.union(CGRect(origin: origin, size: CGSize(width: captured.restCellSize, height: captured.restCellSize)))
            }
            var xs = [rest.minX, rest.maxX], ys = [rest.minY, rest.maxY]
            for x in 0...current.cols {
                let value = current.restOrigin.x + CGFloat(x) * current.restCellSize
                if value > rest.minX && value < rest.maxX { xs.append(value) }
            }
            for y in 0...current.rows {
                let value = current.restOrigin.y + CGFloat(y) * current.restCellSize
                if value > rest.minY && value < rest.maxY { ys.append(value) }
            }
            let sites = xs.flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
            let shown = current.warp(current.embedInRest(sites))
            return InkMaterialBridge.homography(pose).bounds(of: enclosing(shown))
        case .sequence(let parts): return parts.reduce(box) { $1.bounds(of: $0) }
        }
    }

    func conjugated(by map: Homography) -> InkMaterialBridge {
        followed(by: .homography(map))
    }

    private enum Kind: String, Codable { case identity, homography, lattice, sequence }
    private enum CodingKeys: String, CodingKey { case kind, map, captured, current, pose, parts }
    init(from decoder: Decoder) throws {
        self = try InkMaterialCodingError.preserving {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(Kind.self, forKey: .kind) {
            case .identity:
                guard !c.contains(.map), !c.contains(.captured), !c.contains(.current), !c.contains(.pose), !c.contains(.parts) else {
                    throw InkMaterialCodingError.invalid("identity bridge contains another mapping")
                }
                return .identity
            case .homography:
                let map = try c.decode(Homography.self, forKey: .map)
                guard map.inverse != nil, !c.contains(.captured), !c.contains(.current), !c.contains(.pose), !c.contains(.parts) else {
                    throw InkMaterialCodingError.invalid("unusable projective bridge")
                }
                return .homography(map)
            case .lattice:
                let pose = try c.decode(Homography.self, forKey: .pose)
                guard pose.inverse != nil, !c.contains(.map), !c.contains(.parts) else {
                    throw InkMaterialCodingError.invalid("unusable captured bridge pose")
                }
                return .lattice(captured: try c.decode(Lattice.self, forKey: .captured),
                                current: try c.decode(Lattice.self, forKey: .current), pose: pose)
            case .sequence:
                let parts = try c.decode([InkMaterialBridge].self, forKey: .parts)
                guard parts.count >= 2, !c.contains(.map), !c.contains(.captured), !c.contains(.current), !c.contains(.pose) else {
                    throw InkMaterialCodingError.invalid("unusable material transport sequence")
                }
                return .sequence(parts)
            }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .identity: try c.encode(Kind.identity, forKey: .kind)
        case .homography(let map):
            guard map.inverse != nil else { throw InkMaterialCodingError.invalid("unusable runtime projective bridge") }
            try c.encode(Kind.homography, forKey: .kind); try c.encode(map, forKey: .map)
        case .lattice(let captured, let current, let pose):
            guard pose.inverse != nil,
                  captured.vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                  current.vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                throw InkMaterialCodingError.invalid("unusable runtime lattice bridge")
            }
            try c.encode(Kind.lattice, forKey: .kind)
            try c.encode(captured, forKey: .captured); try c.encode(current, forKey: .current)
            try c.encode(pose, forKey: .pose)
        case .sequence(let parts):
            guard parts.count >= 2 else { throw InkMaterialCodingError.invalid("unusable runtime transport sequence") }
            try c.encode(Kind.sequence, forKey: .kind); try c.encode(parts, forKey: .parts)
        }
    }
}

struct InkMaterialBinding: Equatable {
    let operation: InkMaterialOperation
    var bridge: InkMaterialBridge
}

/// One archive's reachable definitions, never a process pool or a prepared-field cache. Duplicate
/// IDs on the wire are corrupt even if their payloads happen to agree. Runtime collection shares
/// agreeing definitions and rejects conflicting clones instead of choosing one silently.
struct InkMaterialTable {
    private let byID: [UUID: InkMaterialOperation]
    var definitions: [LiquifyDeformation] {
        byID.values.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.deformation)
    }
    init(programs: [InkMaterialProgram]) throws {
        var values: [UUID: InkMaterialOperation] = [:]
        for program in programs {
            for binding in program.bindings {
                let operation = binding.operation
                if let old = values[operation.id], old != operation {
                    throw InkMaterialCodingError.invalid("conflicting operation " + operation.id.uuidString)
                }
                values[operation.id] = operation
            }
        }
        byID = values
    }
    init(definitions: [LiquifyDeformation]) throws {
        var values: [UUID: InkMaterialOperation] = [:]
        for definition in definitions {
            guard values[definition.id] == nil else {
                throw InkMaterialCodingError.invalid("duplicate operation " + definition.id.uuidString)
            }
            values[definition.id] = InkMaterialOperation(definition)
        }
        byID = values
    }
    func operation(_ id: UUID) throws -> InkMaterialOperation {
        guard let value = byID[id] else {
            throw InkMaterialCodingError.invalid("dangling operation " + id.uuidString)
        }
        return value
    }
    func validate(_ operation: InkMaterialOperation) throws {
        guard try self.operation(operation.id) == operation else {
            throw InkMaterialCodingError.invalid("reference conflicts with its operation definition")
        }
    }
}

/// Ordered spatial material operations. Every binding retains its own definition at runtime.
/// Standalone stroke/fill archives own a complete local table; canvas and recipe codecs explicitly
/// pass their validated table. There is no missing-reference identity fallback or ambient resolver.
struct InkMaterialProgram: Equatable, Codable {
    var bindings: [InkMaterialBinding]
    init(bindings: [InkMaterialBinding]) { self.bindings = bindings }

    enum MappingFailure: Error { case transport, inverse }
    struct MappingWork {
        var fields = 0
        var evaluations = 0
        var peakFieldBytes = 0
    }
    /// Shared by the tiled renderer and bounded painted-ink queries. Inverse coordinates, including
    /// unchanged points, have exactly one interpretation; no prepared field outlives this call.
    func inverse(_ points: [CGPoint], transport: InkMaterialBridge,
                 work: inout MappingWork) throws -> [CGPoint] {
        var points = points
        for binding in bindings.reversed() {
            let support = binding.bridge.bounds(of: binding.operation.supportBounds)
            let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
            if !support.intersects(box) { continue }
            points = try autoreleasepool {
                let field = LiquifyField(binding.operation.deformation)
                work.peakFieldBytes = max(work.peakFieldBytes, field.retainedByteCount)
                work.fields += 1
                guard let captured = binding.bridge.map(points, inverse: true) else { throw MappingFailure.transport }
                var inverse = captured
                let batch = field.inverseSolutions(&inverse)
                work.evaluations += batch.evaluations
                guard batch.failure == nil else { throw MappingFailure.inverse }
                guard let shown = binding.bridge.map(inverse) else { throw MappingFailure.transport }
                return points.indices.map { inverse[$0] != captured[$0] ? shown[$0] : points[$0] }
            }
        }
        guard let native = transport.map(points, inverse: true) else { throw MappingFailure.transport }
        return native
    }

    func transported(by map: InkMaterialBridge) -> InkMaterialProgram {
        InkMaterialProgram(bindings: bindings.map {
            InkMaterialBinding(operation: $0.operation, bridge: $0.bridge.followed(by: map))
        })
    }

    func appending(_ binding: InkMaterialBinding) -> InkMaterialProgram {
        precondition(!bindings.contains { $0.operation.id == binding.operation.id }, "one field may only be applied once")
        return InkMaterialProgram(bindings: bindings + [binding])
    }

    func conjugated(by map: Homography) -> InkMaterialProgram {
        InkMaterialProgram(bindings: bindings.map {
            InkMaterialBinding(operation: $0.operation, bridge: $0.bridge.conjugated(by: map))
        })
    }

    private enum Scope: String, Codable { case owned, container }
    private enum CodingKeys: String, CodingKey { case scope, operations, bindings }
    private struct Reference: Codable {
        var operation: UUID
        var bridge: InkMaterialBridge
    }

    init(from decoder: Decoder) throws { try self.init(from: decoder, table: nil) }
    init(from decoder: Decoder, table: InkMaterialTable?) throws {
        self = try InkMaterialCodingError.preserving {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let scope = try c.decode(Scope.self, forKey: .scope)
            let resolved: InkMaterialTable
            switch (scope, table) {
            case (.owned, nil): resolved = try InkMaterialTable(definitions: c.decode([LiquifyDeformation].self, forKey: .operations))
            case (.container, .some(let table)):
                guard !c.contains(.operations) else {
                    throw InkMaterialCodingError.invalid("container reference also supplies private definitions")
                }
                resolved = table
            default: throw InkMaterialCodingError.invalid("material archive has the wrong definition owner")
            }
            let references = try c.decode([Reference].self, forKey: .bindings)
            guard !references.isEmpty else { throw InkMaterialCodingError.invalid("empty program must be absent") }
            var seen = Set<UUID>()
            let bindings = try references.map { ref -> InkMaterialBinding in
                guard seen.insert(ref.operation).inserted else {
                    throw InkMaterialCodingError.invalid("repeated operation in one material chain")
                }
                return InkMaterialBinding(operation: try resolved.operation(ref.operation), bridge: ref.bridge)
            }
            return InkMaterialProgram(bindings: bindings)
        }
    }
    func encode(to encoder: Encoder) throws { try encode(to: encoder, table: nil) }
    func encode(to encoder: Encoder, table: InkMaterialTable?) throws {
        guard !bindings.isEmpty else { throw InkMaterialCodingError.invalid("empty material program") }
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let table {
            for binding in bindings { try table.validate(binding.operation) }
            try c.encode(Scope.container, forKey: .scope)
        } else {
            try c.encode(Scope.owned, forKey: .scope)
            try c.encode(InkMaterialTable(programs: [self]).definitions, forKey: .operations)
        }
        guard Set(bindings.map { $0.operation.id }).count == bindings.count else {
            throw InkMaterialCodingError.invalid("repeated operation in one material chain")
        }
        try c.encode(bindings.map { Reference(operation: $0.operation.id, bridge: $0.bridge) }, forKey: .bindings)
    }
}

/// One native geometry owner replaces the old independent optional rest spine/lattice. A normal
/// homography can still recover its source compactly; a spatial material map or exact animation
/// bake retains the native source. Own samples and the ancestor walk have different cut/envelope
/// domains, so a cut piece legitimately needs both.
struct StrokePlacement: Equatable, Codable {
    enum Source: Equatable, Codable {
        case derived
        case retained(samples: StrokeSamples, lattice: DabLattice?, precise: Bool = false)

        /// The same ancestor-parameter correspondence used by cutters, also used when a geometry
        /// mapper inserts vertices or visibility removes them. No position-nearest matching, so a
        /// self-crossing keeps the identity of its original native dab sites.
        func remapped(onto parameters: [CGFloat]) -> Source {
            guard case .retained(let samples, let lattice, let precise) = self else { return self }
            let parent = lattice?.samples ?? samples
            let mapped = lattice.map { walk in parameters.map(walk.parentParameter(of:)) } ?? parameters
            let own = mapped.compactMap { StrokeGeometry.interpolatedSample(in: parent, at: $0) }
            return .retained(samples: samples.replacingSamples(own),
                             lattice: DabLattice(samples: parent, parameters: mapped, precise: lattice?.precise ?? precise), precise: precise)
        }

        func markedPrecise() -> Source {
            guard case .retained(let samples, var lattice, _) = self else { return self }
            lattice?.precise = true
            return .retained(samples: samples, lattice: lattice, precise: true)
        }

        private enum Kind: String, Codable { case derived, retained }
        private enum CodingKeys: String, CodingKey { case kind, samples, lattice }
        init(from decoder: Decoder) throws {
            self = try InkMaterialCodingError.preserving {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                switch try c.decode(Kind.self, forKey: .kind) {
                case .derived:
                    guard !c.contains(.samples), !c.contains(.lattice) else {
                        throw InkMaterialCodingError.invalid("derived source also contains retained geometry")
                    }
                    return .derived
                case .retained:
                    let run = try VectorSample.decodeRun(from: c, forKey: .samples)
                    guard c.contains(.lattice) else { throw InkMaterialCodingError.invalid("missing native ancestor lattice") }
                    return .retained(samples: run.samples, lattice: try c.decodeIfPresent(DabLattice.self, forKey: .lattice), precise: run.precise)
                }
            }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .derived: try c.encode(Kind.derived, forKey: .kind)
            case .retained(let samples, let lattice, let precise):
                try c.encode(Kind.retained, forKey: .kind)
                try c.encode(VectorSample.packed(samples, for: encoder, precise: precise), forKey: .samples)
                if let lattice { try c.encode(lattice, forKey: .lattice) } else { try c.encodeNil(forKey: .lattice) }
            }
        }
    }

    var map: Homography
    var transport: InkMaterialBridge
    var restSize: CGFloat
    var source: Source
    var material: InkMaterialProgram?

    init(map: Homography, restSize: CGFloat, source: Source = .derived,
         material: InkMaterialProgram? = nil, transport: InkMaterialBridge = .identity) {
        self.map = map; self.restSize = restSize; self.source = source; self.material = material
        self.transport = transport
    }

    /// A geometry-only nonlinear rewrite can reconstruct a homography's new source, just as before.
    /// Spatial material callers retain their native source and compose an explicit material binding.
    var withoutStoredGeometry: StrokePlacement {
        guard material == nil else { return self }
        var copy = self; copy.source = .derived; return copy
    }

    private enum CodingKeys: String, CodingKey { case map, restSize, source, material, transport }
    init(from decoder: Decoder) throws { try self.init(from: decoder, table: nil) }
    init(from decoder: Decoder, table: InkMaterialTable?) throws {
        self = try InkMaterialCodingError.preserving {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let map = try c.decode(Homography.self, forKey: .map)
            let size = try c.decode(CGFloat.self, forKey: .restSize)
            guard map.inverse != nil, size.isFinite, size >= 0, c.contains(.material) else {
                throw InkMaterialCodingError.invalid("unusable native placement")
            }
            let source = try c.decode(Source.self, forKey: .source)
            let material = try c.decodeNil(forKey: .material) ? nil :
                InkMaterialProgram(from: c.superDecoder(forKey: .material), table: table)
            if material != nil, case .derived = source {
                throw InkMaterialCodingError.invalid("spatial material lacks its native source")
            }
            return StrokePlacement(map: map, restSize: size, source: source, material: material,
                transport: try c.decode(InkMaterialBridge.self, forKey: .transport))
        }
    }
    func encode(to encoder: Encoder) throws { try encode(to: encoder, table: nil) }
    func encode(to encoder: Encoder, table: InkMaterialTable?) throws {
        guard map.inverse != nil, restSize.isFinite, restSize >= 0 else {
            throw InkMaterialCodingError.invalid("unusable runtime native placement")
        }
        if material != nil, case .derived = source {
            throw InkMaterialCodingError.invalid("spatial material lacks its native source")
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(map, forKey: .map); try c.encode(restSize, forKey: .restSize)
        try c.encode(source, forKey: .source)
        try c.encode(transport, forKey: .transport)
        if let material { try material.encode(to: c.superEncoder(forKey: .material), table: table) }
        else { try c.encodeNil(forKey: .material) }
    }
}

/// Fills retain native coverage just as strokes retain their native walk. The editable paint stays
/// on the fill: recolour and gradient edits do not fork a second colour owner. A later pose maps the
/// native path and the paint in their existing stages, then conjugates the spatial operators.
/// A later geometric cut masks the material at that point in its chronology. Later Liquify
/// operations move the clipped material, while earlier operations never redraw the discarded half.
struct InkMaterialCoverage: Equatable, Codable {
    var pathData: Data
    let afterOperation: UUID
    var bridge: InkMaterialBridge
    let inverted: Bool

    init(pathData: Data, afterOperation: UUID, bridge: InkMaterialBridge = .identity, inverted: Bool = false) {
        self.pathData = pathData; self.afterOperation = afterOperation; self.bridge = bridge; self.inverted = inverted
    }
    private enum CodingKeys: String, CodingKey { case pathData, afterOperation, bridge, inverted }
    init(from decoder: Decoder) throws {
        self = try InkMaterialCodingError.preserving {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let data = try c.decode(Data.self, forKey: .pathData)
            guard VectorFillElement.decodePath(data) != nil else { throw InkMaterialCodingError.invalid("unreadable material cut coverage") }
            return InkMaterialCoverage(pathData: data,
                afterOperation: try c.decode(UUID.self, forKey: .afterOperation),
                bridge: try c.decode(InkMaterialBridge.self, forKey: .bridge),
                inverted: try c.decode(Bool.self, forKey: .inverted))
        }
    }
}

struct FillPlacement: Equatable, Codable {
    var pathData: Data
    var map: Homography
    var transport: InkMaterialBridge
    var material: InkMaterialProgram
    var coverage: [InkMaterialCoverage]

    init(pathData: Data, map: Homography = .identity, material: InkMaterialProgram,
         transport: InkMaterialBridge = .identity, coverage: [InkMaterialCoverage] = []) {
        self.pathData = pathData; self.map = map; self.material = material; self.transport = transport
        self.coverage = coverage
    }
    func transformed(by transform: Homography) -> FillPlacement {
        var copy = self
        copy.map = transform * map
        copy.material = material.conjugated(by: transform)
        copy.transport = transport.moved(by: transform)
        copy.coverage = coverage.map { clip in
            var moved = clip; moved.bridge = clip.bridge.conjugated(by: transform); return moved
        }
        return copy
    }
    func transported(by transform: InkMaterialBridge) -> FillPlacement {
        var copy = self
        copy.transport = transport.followed(by: transform)
        copy.material = material.transported(by: transform)
        copy.coverage = coverage.map { clip in
            var moved = clip; moved.bridge = clip.bridge.followed(by: transform); return moved
        }
        return copy
    }
    func clipped(to data: Data, inverted: Bool) -> FillPlacement {
        var copy = self
        if let last = material.bindings.last {
            copy.coverage.append(InkMaterialCoverage(pathData: data, afterOperation: last.operation.id, inverted: inverted))
        }
        return copy
    }
    private enum CodingKeys: String, CodingKey { case pathData, map, material, transport, coverage }
    init(from decoder: Decoder) throws { try self.init(from: decoder, table: nil) }
    init(from decoder: Decoder, table: InkMaterialTable?) throws {
        self = try InkMaterialCodingError.preserving {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let path = try c.decode(Data.self, forKey: .pathData)
            let map = try c.decode(Homography.self, forKey: .map)
            guard VectorFillElement.decodePath(path) != nil, map.inverse != nil else {
                throw InkMaterialCodingError.invalid("unusable native fill coverage")
            }
            let material = try InkMaterialProgram(from: c.superDecoder(forKey: .material), table: table)
            let coverage = try c.decode([InkMaterialCoverage].self, forKey: .coverage)
            let ids = Set(material.bindings.map { $0.operation.id })
            guard coverage.allSatisfy({ ids.contains($0.afterOperation) }) else {
                throw InkMaterialCodingError.invalid("material cut refers to a missing operation")
            }
            return FillPlacement(pathData: path, map: map, material: material,
                transport: try c.decode(InkMaterialBridge.self, forKey: .transport), coverage: coverage)
        }
    }
    func encode(to encoder: Encoder) throws { try encode(to: encoder, table: nil) }
    func encode(to encoder: Encoder, table: InkMaterialTable?) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pathData, forKey: .pathData); try c.encode(map, forKey: .map)
        try c.encode(transport, forKey: .transport)
        guard map.inverse != nil, VectorFillElement.decodePath(pathData) != nil,
              coverage.allSatisfy({ clip in material.bindings.contains { $0.operation.id == clip.afterOperation } }) else {
            throw InkMaterialCodingError.invalid("unusable runtime fill placement or cut stage")
        }
        try c.encode(coverage, forKey: .coverage)
        try material.encode(to: c.superEncoder(forKey: .material), table: table)
    }
}

extension VectorElement {
    var materialProgram: InkMaterialProgram? {
        switch self {
        case .stroke(let stroke): return stroke.materialProgram
        case .fill(let fill): return fill.placement?.material
        case .image, .text, .video, .stream: return nil
        }
    }

    /// Shared change predicate for procedural windows. Native material can change even when a
    /// fill's boundary or a scattered brush's spine remains stationary.
    func hasSameSpatialInk(as other: VectorElement) -> Bool {
        guard id == other.id else { return false }
        switch (self, other) {
        case (.stroke(let a), .stroke(let b)):
            return a.samples == b.samples && a.lattice == b.lattice && a.placement == b.placement
                && a.size == b.size && a.brushRef == b.brushRef && a.color == b.color
                && a.opacity == b.opacity && a.composite == b.composite && a.seed == b.seed
                && a.visibilityThreshold == b.visibilityThreshold
                && a.sampleVisibilityThresholds == b.sampleVisibilityThresholds
                && a.restWalk?.material == b.restWalk?.material
                && a.restWalk?.pose == b.restWalk?.pose
                && a.restWalk?.transport == b.restWalk?.transport
        case (.fill(let a), .fill(let b)):
            return a.pathData == b.pathData && a.placement == b.placement && a.paint == b.paint
                && a.opacity == b.opacity && a.evenOddFill == b.evenOddFill
        case (.image, .image), (.text, .text), (.video, .video), (.stream, .stream): return true
        default: return false
        }
    }
}

/// The pixel renderer's complete immutable material operand. Other tools still edit the one stroke
/// owner; native dabs, sensors, random identity and paper reach the existing group merge unchanged.
struct InkMaterialPaint {
    let program: InkMaterialProgram
    let transport: InkMaterialBridge
    var geometry: InkMaterialRenderer.GeometryReservation? = nil
    func bounds(of native: CGRect) -> CGRect {
        program.bindings.reduce(transport.bounds(of: native)) {
            $0.union($1.bridge.bounds(of: $1.operation.supportBounds))
        }
    }
    func requiresWarp(in clip: CGRect) -> Bool {
        transport != .identity || program.bindings.contains { $0.bridge.bounds(of: $0.operation.supportBounds).intersects(clip) }
    }
}
