import Foundation
import UIKit

/// Saved content identity excludes display-only video/stream arrivals.
struct CelContentIdentity: Equatable {
    let celID: UUID
    let raster: ObjectIdentifier
    let rasterVersion: Int
    let baked: ObjectIdentifier?
    let vector: ObjectIdentifier?
    let vectorDocumentVersion: Int
    let recipe: InterpolationRecipe.ContentFingerprint?

    init(_ cel: Cel) {
        celID = cel.id
        raster = ObjectIdentifier(cel.raster)
        rasterVersion = cel.raster.version
        baked = cel.bakedImage.map(ObjectIdentifier.init)
        vector = cel.vector.map(ObjectIdentifier.init)
        vectorDocumentVersion = cel.vector?.documentVersion ?? -1
        recipe = cel.interpolation?.contentFingerprint
    }
}

/// Immutable coverage travels with each rendered result, never inferred from its mutable source.
struct CelContentCoverage: Equatable {
    let celID: UUID
    let revision: Int
    let placement: CelContentPlacement
    let derivation: AnyHashable?

    init(celID: UUID, revision: Int, placement: CelContentPlacement = .identity,
         derivation: AnyHashable? = nil) {
        self.celID = celID
        self.revision = revision
        self.placement = placement
        self.derivation = derivation
    }
}

/// The derived image and the exact content it covers are installed as one value.
/// A late result for a replaced cel cannot change either half or trigger base retirement.
struct DerivedCelPresentation {
    enum Installation { case rejected, unchanged, changed }
    private(set) var image: UIImage?
    private(set) var coverage: CelContentCoverage?

    mutating func install(_ image: UIImage?, covering coverage: CelContentCoverage?,
                          on celID: UUID?, aimingAt desired: CelContentPlacement? = nil,
                          preservingPendingThrough pending: Int? = nil) -> Installation {
        if let coverage, coverage.celID != celID { return .rejected }
        if let coverage, let desired, coverage.placement != desired,
           coverage.placement != self.coverage?.placement { return .rejected }
        if let coverage, let pending, coverage.placement != (self.coverage?.placement ?? .identity),
           coverage.revision < pending { return .rejected }
        if let coverage, let shown = self.coverage, coverage.celID == shown.celID,
           coverage.revision < shown.revision { return .rejected }
        if self.image === image, self.coverage == coverage { return .unchanged }
        self.image = image
        self.coverage = coverage
        return .changed
    }

    /// A failed render is distinct from an intentional clear. No image, coverage or placement
    /// changes until a real picture has been produced and accepted.
    mutating func installRendered(_ image: UIImage?, covering coverage: CelContentCoverage,
                                  on celID: UUID?, aimingAt desired: CelContentPlacement,
                                  preservingPendingThrough pending: Int? = nil) -> Installation {
        guard let image else { return .rejected }
        return install(image, covering: coverage, on: celID, aimingAt: desired,
                       preservingPendingThrough: pending)
    }

    mutating func invalidateCoverage() { coverage = nil }
}

/// Host-local commit ordering, independent of texture replacement and each canvas's version zero.
/// Render requests capture one revision directly; no display-version history is retained.
final class CelContentRevisions {
    private var identity: CelContentIdentity?
    private var document: (object: ObjectIdentifier, version: Int, revision: Int)?
    private(set) var current = 0
    var celID: UUID? { identity?.celID }

    /// Reusing derived ink can advance whole-cel coverage only after both pixel slots have
    /// installed the current backing. A retained texture can have changed in place.
    func captureDisplayedCoverage(of cel: Cel, bakedImage: UIImage?, raster: RasterLayerTexture?,
                                  rasterVersion: Int, placement: CelContentPlacement,
                                  derivation: AnyHashable) -> CelContentCoverage? {
        guard bakedImage === cel.bakedImage, raster === cel.raster,
              rasterVersion == cel.raster.version else { return nil }
        return CelContentCoverage(celID: cel.id, revision: observe(cel),
                                  placement: placement, derivation: derivation)
    }

    @discardableResult
    func observe(_ cel: Cel) -> Int {
        let next = CelContentIdentity(cel)
        guard next != identity else { return current }
        let onlyVectorMoved = identity.map {
            $0.celID == next.celID && $0.raster == next.raster && $0.rasterVersion == next.rasterVersion
                && $0.baked == next.baked && $0.vector == next.vector && $0.recipe == next.recipe
        } == true
        if onlyVectorMoved, let canvas = cel.vector, let known = document,
           known.object == ObjectIdentifier(canvas), known.version == canvas.documentVersion {
            current = max(current, known.revision)
        } else { current += 1 }
        identity = next
        document = cel.vector.map { (ObjectIdentifier($0), $0.documentVersion, current) }
        return current
    }

    /// The canvas has just committed, or is being frozen for a base request on the main thread.
    func committed(_ canvas: VectorCanvas) -> Int {
        if let known = document, known.object == ObjectIdentifier(canvas), known.version == canvas.documentVersion {
            return known.revision
        }
        current += 1
        document = (ObjectIdentifier(canvas), canvas.documentVersion, current)
        return current
    }
}
