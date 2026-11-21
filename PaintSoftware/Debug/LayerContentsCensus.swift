import IOSurface
import QuartzCore
import UIKit

/// **What the render server is being handed, counted from the layer tree it is handed.**
///
/// Every `CALayer.contents` in the window is a picture `backboardd` copies and keeps a texture for.
/// The iPad's render server dies at its own per-process limit (1,850 MiB on an iPad 9 — the three
/// November 16 jetsam events), and the app's own footprint says nothing about it: the app sat at
/// 626–816 MiB while the server was killed. A simulator enforces no such limit, so a run that drowns
/// the server on the device is green here unless something counts the quantity that drowns it.
///
/// **Two quantities, because the first alone does not see the failure.** MEASURED on 2026-11-16 at
/// the owner's shape (5000², five vector layers, iPad 9 simulator), against the simulator's own
/// `backboardd` footprint sampled from the Mac:
///
/// - `peak` — the distinct contents referenced at once. It never passed five canvas-sized pictures
///   (481 MiB) while the server climbed to 2.7 GB, so it is the steady state, not the failure.
/// - `handed`/`busiest` — **canvas-sized pictures handed over**: a large contents object present in
///   one display frame that was not in the frame before. The server climbed by one 95 MB picture per
///   picture handed and released them only once the run of them stopped; `busiest` is the most
///   handed within any one second, which is the rate that decides whether it keeps up.
///
/// - `handedMiB` — **every picture's bytes the render server is handed**, canvas-sized or not: a
///   bitmap counts each time a new one appears in the tree; an `IOSurface` counts the first time it
///   appears and never again, because the server maps a surface once and a later `contents`
///   assignment of the same surface hands it nothing (`WindowSurfaceView`). This is the quantity that
///   killed the iPad 9's server at 1,850 MiB during playback on 2026-11-18, where each played frame
///   was a fresh 95 MiB bitmap — the large-picture count alone would also see that, but not a run of
///   pictures just under `largeBytes`.
///
/// Armed only by `-uiTestContentsCensus` on a simulator. It walks the tree every display frame,
/// which an ordinary launch must never pay.
@MainActor
final class LayerContentsCensus {

    /// One look at a layer tree.
    struct Reading: Equatable {
        /// Distinct contents bytes referenced by the tree.
        var bytes = 0
        /// The distinct contents objects at least `largeBytes` each — canvas-sized pictures.
        var large: [AnyObject] = []
        /// The distinct contents objects at least `pictureBytes` each.
        var pictures: [AnyObject] = []
        /// For each of `pictures`, the view that put it in the tree — its layer's own view, or the
        /// nearest view above a bare sublayer.
        var owners: [String] = []

        static func == (a: Reading, b: Reading) -> Bool {
            a.bytes == b.bytes && a.large.count == b.large.count
                && zip(a.large, b.large).allSatisfy { $0 === $1 }
        }
    }

    /// A picture this size or larger is counted as canvas-sized: a quarter of a 4096² RGBA image.
    static let largeBytes = 16 << 20

    static let shared: LayerContentsCensus? = {
        guard ProjectBackupManager.isSimulator,
              ProcessInfo.processInfo.arguments.contains("-uiTestContentsCensus") else { return nil }
        return LayerContentsCensus()
    }()

    private(set) var peakBytes = 0
    /// Distinct contents bytes referenced by the tree at the last look.
    private(set) var heldBytes = 0
    private(set) var peakLarge = 0
    /// Canvas-sized pictures that have appeared in the tree, over the run.
    private(set) var handed = 0
    /// The most handed within any one second.
    private(set) var busiest = 0
    /// When each of the last second's pictures was handed.
    private var recent: [CFTimeInterval] = []
    /// The previous frame's large contents, held so an address cannot be reused by a new picture
    /// between two looks and be mistaken for the old one.
    private var previous: [AnyObject] = []
    /// Bytes of pictures handed to the render server over the run — see the type's comment.
    private(set) var handedBytes = 0
    /// `handedBytes` by the view that handed them, so a red bound names its producer.
    private(set) var handedByOwner: [String: Int] = [:]
    /// The previous frame's bitmaps of `pictureBytes` or more, held for `previous`'s reason.
    private var previousPictures: [AnyObject] = []
    /// Every surface the tree has carried, by `IOSurfaceID`: the server has each of these mapped.
    private var seenSurfaces = Set<IOSurfaceID>()
    /// Contents smaller than this are chrome (icons, glyphs) and not counted in `handedBytes`.
    static let pictureBytes = 1 << 20
    private weak var window: UIWindow?
    private var link: CADisplayLink?
    /// Called when a figure changes, so the canvas label can be republished.
    var onChange: (() -> Void)?

    /// `census:<peak MiB>,<peak large>,<handed>,<busiest second>` for `canvas.host`'s label.
    var field: String {
        "census:\(peakBytes >> 20),\(peakLarge),\(handed),\(busiest) handedMiB:\(handedBytes >> 20)"
            + " holding:\(heldBytes >> 20) handedBy:\(producers) " + MemoryBudget.shared.censusField
    }

    /// `handedByOwner`'s three largest, `View=MiB` joined by `;` — one space-free field.
    var producers: String {
        let top = handedByOwner.sorted { $0.value > $1.value }.prefix(3)
        return top.isEmpty ? "none" : top.map { "\($0.key)=\($0.value >> 20)" }.joined(separator: ";")
    }

    func attach(to window: UIWindow?) {
        guard let window, self.window !== window else { return }
        self.window = window
        link?.invalidate()
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate func tick() {
        guard let root = window?.layer else { return }
        let reading = Self.reading(of: root)
        let now = CACurrentMediaTime()
        let new = reading.large.filter { object in !previous.contains { $0 === object } }.count
        previous = reading.large
        var newBytes = 0
        for (object, owner) in zip(reading.pictures, reading.owners) {
            let handedNow: Bool
            if CFGetTypeID(object) == IOSurfaceGetTypeID() {
                handedNow = seenSurfaces.insert(IOSurfaceGetID(unsafeBitCast(object, to: IOSurfaceRef.self))).inserted
            } else {
                handedNow = !previousPictures.contains { $0 === object }
            }
            guard handedNow else { continue }
            let bytes = Self.bytes(of: object)
            newBytes += bytes
            handedByOwner[owner, default: 0] += bytes
        }
        previousPictures = reading.pictures.filter { CFGetTypeID($0) != IOSurfaceGetTypeID() }
        recent.removeAll { now - $0 > 1 }
        recent.append(contentsOf: repeatElement(now, count: new))
        let figures = (peakBytes, peakLarge, handed, busiest, handedBytes >> 20, heldBytes >> 20)
        handedBytes += newBytes
        heldBytes = reading.bytes
        peakBytes = max(peakBytes, reading.bytes)
        peakLarge = max(peakLarge, reading.large.count)
        handed += new
        busiest = max(busiest, recent.count)
        if figures != (peakBytes, peakLarge, handed, busiest, handedBytes >> 20, heldBytes >> 20) { onChange?() }
    }

    /// The distinct contents a tree references, its masks included. Pure apart from the read.
    static func reading(of root: CALayer) -> Reading {
        var seen = Set<ObjectIdentifier>()
        var reading = Reading()
        var stack = [(root, "window")]
        while let (layer, above) = stack.popLast() {
            let owner = (layer.delegate as? UIView).map { Self.name(of: $0) } ?? above
            if let contents = layer.contents {
                let object = contents as AnyObject
                if seen.insert(ObjectIdentifier(object)).inserted {
                    let bytes = Self.bytes(of: object)
                    reading.bytes += bytes
                    if bytes >= largeBytes { reading.large.append(object) }
                    if bytes >= pictureBytes {
                        reading.pictures.append(object)
                        reading.owners.append(owner)
                    }
                }
            }
            if let mask = layer.mask { stack.append((mask, owner)) }
            if let sublayers = layer.sublayers { stack.append(contentsOf: sublayers.map { ($0, owner) }) }
        }
        return reading
    }

    /// `Superview.View` — type names with any generic arguments dropped, so it is one label field and
    /// a plain `UIImageView` still says whose it is.
    static func name(of view: UIView) -> String {
        func bare(_ view: UIView) -> String {
            String(String(describing: type(of: view)).prefix { $0 != "<" && $0 != " " })
        }
        return view.superview.map { bare($0) + "." + bare(view) } ?? bare(view)
    }

    static func bytes(of contents: AnyObject) -> Int {
        let type = CFGetTypeID(contents)
        if type == CGImage.typeID {
            let image = contents as! CGImage
            return image.bytesPerRow * image.height
        }
        if type == IOSurfaceGetTypeID() {
            return IOSurfaceGetAllocSize(unsafeBitCast(contents, to: IOSurfaceRef.self))
        }
        return 0
    }

    /// `CADisplayLink` retains its target; this breaks the cycle.
    private final class Ticker: NSObject {
        weak var census: LayerContentsCensus?
        init(_ census: LayerContentsCensus) { self.census = census }
        @MainActor @objc func tick() { census?.tick() }
    }
}
