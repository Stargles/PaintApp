import SwiftUI
import UIKit

// MARK: - Objects the Add menu primes, and the pen that places them
//
// TODO (149), the owner: *"for the shapes in the add menu (rectangle, ellipse, image, linear
// gradient), make clicking on them prime it, and the next time the pen is touched to the screen, it
// spawns the shape. For ellipses, the circle starts on the pen press, and when the pen is dragged it
// expands its size. Same thing for rectangle, except its a square, and its rotation is locked
// (dragging only increases size, does not rotate it). For image and video, same thing as rectangle.
// For gradient, the direction of the gradient is the direction of the stroke from when it was placed
// to its current dragged position. The length is the length of that line. For the width, lets have
// the left menu show the width slider, being % of canvas size."*
//
// **One gesture, one value, one lift.** A press starts a `PlacementDrag`; every pen position
// re-derives a `PlacementPlan` from it — the one value the live preview draws and the lift lays down,
// so what the artist watches grow is what lands — and the lift commits it as a single undo step. Nothing
// touches the document before the lift, so a cancelled touch leaves no trace.

/// What the Add menu primed for the next pen-down.
enum PrimedObject: Equatable {
    case rectangle
    case ellipse
    case gradient
    /// A picture or a clip the artist already picked. **Picked first and primed second**: the picker is
    /// a sheet that has to finish before any canvas touch exists, and the drag's shape is the media's
    /// own aspect, which is known only once it has been read.
    case media(PrimedMedia)

    /// What the Add icon announces while this is primed — a value a test (or VoiceOver) reads off it.
    var name: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .gradient: return "gradient"
        case .media(let media):
            switch media.source {
            case .image: return "image"
            case .video: return "video"
            }
        }
    }

    /// The picked clip's file, which this object owns until a placement moves it away.
    var mediaFileURL: URL? {
        guard case .media(let media) = self, case .video(let url) = media.source else { return nil }
        return url
    }
}

/// A picked picture or clip, as much of it as a drag needs: where its bytes are and what shape it is.
struct PrimedMedia: Equatable {
    enum Source: Equatable {
        case image(UIImage)
        /// The picked file — **moved**, not copied, into the document when the clip is placed
        /// (`CanvasManager.insertVideo(consumingSource:)`), and deleted if it never is
        /// (`CanvasManager.primedObject`).
        case video(URL)
    }

    let source: Source
    /// The size the picture is shown at before the artist sizes it — a clip's is the displayed one, so
    /// a phone-shot portrait clip keeps its upright aspect. Only its aspect and its width (the unit a
    /// placement is measured against) are read.
    let displaySize: CGSize

    /// Width over height: the shape a drag keeps, because a square would stretch the picture.
    var aspect: CGFloat { displaySize.height > 0 ? displaySize.width / displaySize.height : 1 }

    /// The picture the live preview draws. A clip has none: its first frame would have to be turned by
    /// the clip's own orientation to match what lands, and the preview shows an outline instead.
    var poster: UIImage? {
        if case .image(let image) = source { return image }
        return nil
    }
}

/// The press and the pen of one placement, in canvas points.
struct PlacementDrag: Equatable {
    /// Where the pen went down: the centre of a shape, the first end of a gradient.
    let anchor: CGPoint
    /// Where the pen is now.
    var pen: CGPoint

    /// The shortest drag that is a placement rather than a tap, **in screen points** — what the artist's
    /// hand did, so a stray touch is told from a drag at any zoom: eight canvas points is a deliberate
    /// stroke at 400% and a tremor at 5%. A press that never travelled this far places nothing and
    /// leaves the object primed, so a stray touch costs nothing.
    static let minimumTravel: CGFloat = 8

    /// Whether the pen travelled far enough to be a placement, with `scale` the screen points one canvas
    /// point measures.
    func isDeliberate(atScale scale: CGFloat) -> Bool {
        hypot(pen.x - anchor.x, pen.y - anchor.y) * scale >= Self.minimumTravel
    }
}

/// **What a drag has laid out so far** — the single value `CanvasView`'s preview draws and
/// `CanvasManager.endPlacement` lays down. Geometry only: the colour of a shape is the brush's at the
/// moment it is drawn or laid down, and a gradient's colours are its own defaults.
enum PlacementPlan: Equatable {
    /// A rectangle or an ellipse in the brush colour, in canvas points.
    case solid(ShapeGeometry)
    /// A band the ramp fills end to end: `band` is the rectangle the gradient occupies, `from` and `to`
    /// the two points the ramp runs between — the press and the pen.
    case gradient(band: ShapeGeometry, from: CGPoint, to: CGPoint)
    /// A picture or clip, upright, `size` across and centred on `centre`.
    case media(PrimedMedia, centre: CGPoint, size: CGSize)
}

extension PrimedObject {
    /// The plan this object makes of `drag`. **The pen is always on the outline** — see
    /// `ShapeGeometry.dragged` — and a gradient is exactly the line from the press to the pen, `bandWidth`
    /// wide.
    func plan(for drag: PlacementDrag, bandWidth: CGFloat) -> PlacementPlan {
        switch self {
        case .rectangle:
            return .solid(.dragged(.rectangle, from: drag.anchor, to: drag.pen))
        case .ellipse:
            return .solid(.dragged(.oval, from: drag.anchor, to: drag.pen))
        case .gradient:
            let line = ShapeGeometry.dragged(.line, from: drag.anchor, to: drag.pen)
            return .gradient(band: line.band(width: bandWidth), from: drag.anchor, to: drag.pen)
        case .media(let media):
            let box = ShapeGeometry.dragged(.rectangle, from: drag.anchor, to: drag.pen, aspect: media.aspect)
            return .media(media, centre: drag.anchor, size: box.boundingRect.size)
        }
    }
}

extension CanvasManager {

    // MARK: - Priming

    /// **Primes `object`: the next pen-down on the canvas places it.** Whatever was in progress settles
    /// first, as it does for any tool switch, so no floating piece or open session is left owning the
    /// touch the placement is about to take. An eyedropper that was armed is stood down — a pick is
    /// momentary and this is the artist's newer word.
    ///
    /// Priming what is already primed changes nothing; the menu's toggle lives in
    /// `togglePrimedObject`. A document with no canvas has nowhere to place anything, so it primes
    /// nothing.
    func primeObject(_ object: PrimedObject) {
        guard canvasSize != nil else { return }
        commitAllInteractiveState()
        if selectedTool == .eyedropper { leaveEyedropper() }
        primedObject = object
        enterMomentaryTool(.place)
    }

    /// **Primes a picked picture.** False when it has no size to drag out or the document has no canvas.
    @discardableResult
    func primeImage(_ image: UIImage) -> Bool {
        guard image.size.width > 0, image.size.height > 0 else { return false }
        primeObject(.media(PrimedMedia(source: .image(image), displaySize: image.size)))
        return primedObject != nil
    }

    /// **Primes a picked clip**, which the primed object now owns: a clip that is never placed is deleted
    /// with it. False — and the file is the caller's still — when it will not open as a video or the
    /// document has no canvas.
    @discardableResult
    func primeVideo(at pickedURL: URL) -> Bool {
        guard let info = VideoFrameSource.shared.info(for: pickedURL),
              info.displaySize.width > 0, info.displaySize.height > 0 else { return false }
        primeObject(.media(PrimedMedia(source: .video(pickedURL), displaySize: info.displaySize)))
        return primedObject?.mediaFileURL == pickedURL
    }

    /// The Add rows' verb: tapping an entry primes it, and **tapping the entry that is already primed
    /// puts it down again** — the way out for an artist who changed their mind, and the same gesture as
    /// every other toggle in the app.
    func togglePrimedObject(_ object: PrimedObject) {
        if primedObject == object {
            leavePlacement()
        } else {
            primeObject(object)
        }
    }

    /// Hands the canvas back to the tool that was selected before the object was primed, ending the
    /// priming. The single exit for both a placement and a cancel; `selectedTool`'s `didSet` clears the
    /// object.
    func leavePlacement() {
        guard selectedTool == .place else { return }
        placementDrag = nil
        leaveMomentaryTool()
    }

    // MARK: - The drag

    /// The pen has gone down. False when nothing is primed, so a handler can decline a touch that is
    /// not a placement.
    @discardableResult
    func beginPlacement(at point: CGPoint) -> Bool {
        guard selectedTool == .place, primedObject != nil else { return false }
        placementDrag = PlacementDrag(anchor: point, pen: point)
        return true
    }

    /// The pen moved.
    func updatePlacement(to point: CGPoint) {
        placementDrag?.pen = point
    }

    /// What the pen has dragged out so far, or nil between touches. The preview and the lift both read
    /// this, so they cannot disagree.
    var placementPlan: PlacementPlan? {
        guard let object = primedObject, let drag = placementDrag else { return nil }
        return object.plan(for: drag, bandWidth: gradientBandWidth)
    }

    /// **A gradient's width in canvas points** — `gradientWidthFraction` of the artwork's *longer*
    /// side, so 100% is wide enough to cover the whole paper whichever way the gradient is dragged.
    var gradientBandWidth: CGFloat {
        guard let artwork = artworkRect else { return 0 }
        return CGFloat(gradientWidthFraction) * max(artwork.width, artwork.height)
    }

    /// The pen is off the glass: lays the object down as one undo step and hands the canvas back.
    /// **A drag too short to be a placement lays nothing down and leaves the object primed**, and so
    /// does an object the document has nowhere to put.
    ///
    /// - Parameter canvasScale: the screen points one canvas point measures, which is what "too short"
    ///   is judged in (`PlacementDrag.minimumTravel`). 1 puts canvas and screen points together.
    /// - Returns: whether the object was placed.
    @discardableResult
    func endPlacement(canvasScale: CGFloat = 1) -> Bool {
        defer { placementDrag = nil }
        guard let plan = placementPlan, placementDrag?.isDeliberate(atScale: canvasScale) == true,
              layDown(plan) else { return false }
        leavePlacement()
        return true
    }

    /// The touch was cancelled — a second finger arrived, the system took it. Nothing was laid down, and
    /// the object stays primed for the next try.
    func cancelPlacement() {
        placementDrag = nil
    }

    // MARK: - The lift

    /// Lays `plan` down through the add path of its kind. Each of them is the one place that kind of
    /// object is made, and each answers whether it landed.
    private func layDown(_ plan: PlacementPlan) -> Bool {
        switch plan {
        case .solid(let shape):
            return placeSolidShape(shape)
        case .gradient(let band, let from, let to):
            return placeGradient(band: band, from: from, to: to)
        case .media(let media, let centre, let size):
            switch media.source {
            case .image(let image):
                return placeImage(image, centre: centre, width: size.width)
            case .video(let url):
                return insertVideo(at: url, consumingSource: true, placement: (centre, size.width))
            }
        }
    }
}
