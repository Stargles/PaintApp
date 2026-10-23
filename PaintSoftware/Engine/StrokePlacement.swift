import CoreGraphics
import Foundation

/// A damaged authoritative geometry owner fails the payload rather than silently dropping ink.
enum VectorGeometryCodingError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let reason): return "Invalid vector geometry: " + reason } }
    static func preserving<T>(_ read: () throws -> T) throws -> T {
        do { return try read() }
        catch let error as VectorGeometryCodingError { throw error }
        catch { throw VectorGeometryCodingError.invalid(String(describing: error)) }
    }
}

/// A committed projective placement. Ordinary Distort derives its source through the inverse map;
/// an exact animation bake retains the original walk so saving cannot rephase its dabs.
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
            self = try VectorGeometryCodingError.preserving {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                switch try c.decode(Kind.self, forKey: .kind) {
                case .derived:
                    guard !c.contains(.samples), !c.contains(.lattice) else {
                        throw VectorGeometryCodingError.invalid("derived source also contains retained geometry")
                    }
                    return .derived
                case .retained:
                    let run = try VectorSample.decodeRun(from: c, forKey: .samples)
                    guard c.contains(.lattice) else { throw VectorGeometryCodingError.invalid("missing native ancestor lattice") }
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
    var restSize: CGFloat
    var source: Source

    init(map: Homography, restSize: CGFloat, source: Source = .derived) {
        self.map = map; self.restSize = restSize; self.source = source
    }

    /// Point editing makes any retained bake source stale. The unchanged projective placement can
    /// derive its new native geometry from the edited spine and ancestral walk.
    var withoutStoredGeometry: StrokePlacement {
        var copy = self; copy.source = .derived; return copy
    }

    private enum CodingKeys: String, CodingKey { case map, restSize, source }
    init(from decoder: Decoder) throws {
        self = try VectorGeometryCodingError.preserving {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let map = try c.decode(Homography.self, forKey: .map)
            let size = try c.decode(CGFloat.self, forKey: .restSize)
            guard map.inverse != nil, size.isFinite, size >= 0 else {
                throw VectorGeometryCodingError.invalid("unusable projective placement")
            }
            return StrokePlacement(map: map, restSize: size, source: try c.decode(Source.self, forKey: .source))
        }
    }
    func encode(to encoder: Encoder) throws {
        guard map.inverse != nil, restSize.isFinite, restSize >= 0 else {
            throw VectorGeometryCodingError.invalid("unusable projective placement")
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(map, forKey: .map); try c.encode(restSize, forKey: .restSize)
        try c.encode(source, forKey: .source)
    }
}
