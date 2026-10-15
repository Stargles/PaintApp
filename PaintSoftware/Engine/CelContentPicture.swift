import UIKit

/// The two existing display maps are independent: cel channels pose editable ink, while stored
/// pixel tiers follow only their container. Linked evaluated ink intentionally has no ink map.
struct CelContentPlacement: Equatable {
    let ink: PoseMap?
    let backing: PoseMap?

    init(ink: PoseMap? = nil, backing: PoseMap? = nil) {
        self.ink = ink.flatMap { $0.isIdentity ? nil : $0 }
        self.backing = backing.flatMap { $0.isIdentity ? nil : $0 }
    }
    static let identity = CelContentPlacement()
}

extension CanvasManager {
    func celContentPlacement(ofLayerAt index: Int, in walk: RenderWalk) -> CelContentPlacement {
        CelContentPlacement(ink: inkPose(ofLayerAt: index, showing: walk.frames[index] ?? currentFrame,
                                        inheriting: walk.poses[index], holding: liveEdit?.groupPose),
                            backing: walk.poses[index])
    }

    func celContentPlacement(forLayerID id: UUID) -> CelContentPlacement {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return .identity }
        return celContentPlacement(ofLayerAt: index, in: renderTreeAndPoses(atFrame: currentFrame))
    }
}

/// One immutable resolved cel replacement. Pixel backing and editable ink share presentation and
/// lifetime, while keeping their native posing rules: backing is sampled; ordinary ink is stamped
/// through its geometry pose; evaluated linked ink intentionally declines the container pose.
final class CelContentPicture {
    enum Ink {
        case ordinary(source: VectorCanvas.Frozen, elements: [VectorElement], rewriting: Set<UUID>)
        case linked(InterpolationEvaluator.Evaluation)
        case derived(DerivedCelContent, RenderQuality)
        case rendered(UIImage)
    }

    let size: CGSize
    let window: CGRect
    let backing: CelPixelSnapshot?
    let patch: CelPixelSnapshot.Patch?
    let ink: Ink?
    /// A vector eraser replaces local ink only; the immutable native source fills the rest of the union.
    let inkPatch: UIImage?

    private let failureLock = NSLock()
    private var failed = false
    var hasFailed: Bool {
        failureLock.lock(); defer { failureLock.unlock() }
        return failed
    }

    init(size: CGSize, window: CGRect, backing: CelPixelSnapshot?, patch: CelPixelSnapshot.Patch?, ink: Ink?, inkPatch: UIImage? = nil) {
        self.size = size
        self.window = window
        self.backing = backing
        self.patch = patch
        self.ink = ink
        self.inkPatch = inkPatch
    }

    struct RenderedWindow {
        let image: UIImage
        let window: CGRect
        let footprint: CGPath

        func draw(into cg: CGContext, content: CGRect, canvasSize: CGSize) {
            PixelOps.withCelWindow(footprint: footprint, canvasSize: canvasSize,
                                  into: cg, content: content, replacing: true) {
                image.draw(in: window)
            }
        }
    }

    func rendered(placement: CelContentPlacement = .identity) -> RenderedWindow? {
        let path = footprint(placement: placement)
        let output = path.boundingBoxOfPath.integral.intersection(CGRect(origin: .zero, size: size))
        guard !output.isNull, !output.isEmpty else { return nil }
        var completed = true
        let image = UIGraphicsImageRenderer(size: output.size, format: PixelOps.transparentFormat()).image { context in
            completed = draw(into: context.cgContext,
                content: CGRect(origin: CGPoint(x: -output.minX, y: -output.minY), size: size), placement: placement)
        }
        return completed ? RenderedWindow(image: image, window: output, footprint: path) : nil
    }

    static func footprint(inkWindow: CGRect?, inkPose: PoseMap?, backingWindow: CGRect?, backingPose: PoseMap?) -> CGPath {
        var result: CGPath = CGMutablePath()
        if let inkWindow {
            let ink = CGPath(rect: inkWindow, transform: nil)
            result = inkPose?.mapped(ink) ?? ink
        }
        if let backingWindow {
            let local = CGPath(rect: backingWindow, transform: nil)
            let backing = backingPose?.mapped(local) ?? local
            result = result.isEmpty ? backing : result.union(backing, using: .winding)
        }
        return result
    }

    private var backingWindow: CGRect? { backing == nil && patch == nil ? nil : patch?.rect ?? window }

    private func inkPose(placement: CelContentPlacement) -> PoseMap? {
        if case .ordinary = ink { return placement.ink }
        return nil
    }

    func footprint(placement: CelContentPlacement) -> CGPath {
        let inkPose = inkPose(placement: placement)
        return Self.footprint(inkWindow: ink == nil ? nil : window, inkPose: inkPose,
                              backingWindow: backingWindow, backingPose: placement.backing)
    }

    @discardableResult
    func draw(into cg: CGContext, content: CGRect, placement: CelContentPlacement, replacing: Bool = false) -> Bool {
        guard !hasFailed else { return false }
        var completed = true
        let footprint = footprint(placement: placement)
        PixelOps.withCelWindow(footprint: footprint, canvasSize: size, into: cg,
                               content: content, replacing: replacing) {
            cg.saveGState()
            defer { cg.restoreGState() }
            cg.addPath(footprint)
            cg.clip()
            if let backing {
                if let pose = placement.backing {
                    completed = PixelOps.drawPosedRaster(canvasSize: size, through: pose, into: cg) {
                        backing.replacementWindow(in: $0, applying: patch)
                    }
                } else {
                    let sourceWindow = footprint.boundingBoxOfPath.integral.intersection(CGRect(origin: .zero, size: size))
                    if !sourceWindow.isEmpty, !sourceWindow.isNull {
                        backing.replacementWindow(in: sourceWindow, applying: patch).draw(in: sourceWindow)
                    }
                }
            } else if let patch {
                completed = PixelOps.drawWindow(patch.image, rect: patch.rect, canvasSize: size, through: placement.backing,
                    into: cg, content: CGRect(origin: .zero, size: size), replacing: false)
            }
            guard completed else { return }
            cg.saveGState()
            if inkPatch != nil {
                let local = CGPath(rect: window, transform: nil)
                let patchPath = inkPose(placement: placement)?.mapped(local) ?? local
                cg.addPath(footprint.subtracting(patchPath, using: .winding))
                cg.clip()
            }
            switch ink {
            case .ordinary(let source, let elements, let rewriting):
                let shown = CanvasManager.posed(elements, through: [], inheriting: placement.ink)
                let rewritten = placement.ink == nil ? rewriting : Set(shown.map(\.id))
                let references = Set(shown.compactMap { $0.stream }.filter(\.rendersInPlace).map(\.id))
                let frozen = source.replacingDisplayElements(shown, rewriting: rewritten, referenceIDs: references)
                completed = frozen.draw(into: cg, frameRect: CGRect(origin: .zero, size: size), quality: .full) != nil
            case .linked(let evaluation):
                let area = footprint.boundingBoxOfPath.integral.intersection(CGRect(origin: .zero, size: size))
                if let image = InterpolationEvaluator.composite(evaluation, size: size, window: area) {
                    image.draw(in: area)
                } else { completed = false }
            case .derived(let content, let quality):
                if let image = content.render(quality) { image.draw(in: CGRect(origin: .zero, size: size)) }
                else { completed = false }
            case .rendered(let image): image.draw(in: CGRect(origin: .zero, size: size))
            case nil: break
            }
            cg.restoreGState()
            guard completed else { return }
            if let inkPatch {
                completed = PixelOps.drawWindow(inkPatch, rect: window, canvasSize: size,
                    through: inkPose(placement: placement), into: cg,
                    content: CGRect(origin: .zero, size: size), replacing: false)
            }
        }
        if !completed {
            failureLock.lock(); failed = true; failureLock.unlock()
        }
        return completed
    }
}
