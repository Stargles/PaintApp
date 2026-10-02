import CoreGraphics

/// The two placements the Move bar offers a placed picture, video or stream — TODO (150), the owner's
/// *"have additional options to center the image/video/stream … Also have an option to make the size
/// 1 to 1, as in every pixel of the image is a pixel on the screen, and resets the rotation."*
enum MediaPlacement {
    /// The picture's centre on the canvas's centre. Its size, turn and mirror are left as they are.
    case centred
    /// One source pixel per canvas pixel, turned back upright about the centre it already has.
    /// A mirror stays: it is the picture's own flip, not a rotation.
    case actualSize
}

extension CanvasManager {

    // MARK: - What the float holds

    /// The float's one placed rectangle, together with where its picture sits at the instant it was
    /// lifted.
    private struct FloatedMedia {
        let element: any PlacedRectangle
        /// The natural rectangle mapped into the box's own space as lifted: the element's placement
        /// followed by the pose it is shown through. Frozen at the lift, like everything the float
        /// measures a nudge from.
        let shownAtLift: CGAffineTransform
    }

    /// **The picture, video or stream a float holds — when it holds exactly that.** A selection that
    /// also carries a stroke or a second picture has no one rectangle for "1:1" to mean, so it is not
    /// offered the placements at all, rather than being given a reading that picks one.
    ///
    /// **A rectangle shown through a keystone is not one either**: a keystone pose turns it into a
    /// quadrilateral that no centre, scale or angle describes. Every other pose — a cel channel, a
    /// transformation layer — is an affine, and `shownAtLift` carries it.
    private static func floatedMedia(in float: VectorFloat) -> FloatedMedia? {
        guard float.parts.count == 1, let part = float.parts.first, part.insideIDs.count == 1,
              let id = part.insideIDs.first,
              let element = part.liftedInside[id]?.placedRectangle else { return nil }
        let pose = part.poses[id]
        guard pose?.isProjective != true else { return nil }
        return FloatedMedia(element: element,
                            shownAtLift: element.placement.concatenating(pose?.affine ?? .identity))
    }

    /// Whether the Move bar offers Center and 1:1 for what the float holds.
    var floatHoldsPlacedMedia: Bool {
        vectorFloat.flatMap(Self.floatedMedia(in:)) != nil
    }

    // MARK: - The two placements

    /// Whether `placement` would change anything: false once the picture is already there, so the
    /// bar's button is off rather than a press that spends an undo step on nothing — Reset's rule.
    func canPlaceFloatedMedia(_ placement: MediaPlacement) -> Bool {
        guard let float = vectorFloat, let media = Self.floatedMedia(in: float),
              let target = targetPlacement(of: placement, for: media, in: float) else { return false }
        let current = Self.shownPlacement(of: media, in: float)
        return !Self.sameWithinRounding(current, target)
    }

    /// **One undo step, through the Move box's own nudge** — the transform the box would have to be
    /// dragged to for the picture to land on `placement`, handed to `applyToVectorFloat` like a drag,
    /// a Rotate press or a Mirror. So the live preview, the box, the undo step, the mirror and the
    /// pose a layer is shown through are the ones every other Move uses.
    func placeFloatedMedia(_ placement: MediaPlacement) {
        guard let float = vectorFloat, let media = Self.floatedMedia(in: float),
              let target = targetPlacement(of: placement, for: media, in: float),
              !Self.sameWithinRounding(Self.shownPlacement(of: media, in: float), target),
              let fields = Self.boxFields(placing: target, media: media, in: float) else { return }
        applyToVectorFloat(transform: fields.transform, aspect: fields.aspect,
                           stretchAxis: fields.stretchAxis, distort: float.distort, mirror: float.mirror)
    }

    // MARK: - The arithmetic

    /// **Where the picture is drawn right now, as the artist sees it** — its natural rectangle to the
    /// canvas. The lift's placement carried through what the box has done since: the mirror, then the
    /// box's own affine, which at lift is the layer's transform and so leaves a fresh float's picture
    /// exactly where the layer draws it.
    private static func shownPlacement(of media: FloatedMedia, in float: VectorFloat) -> CGAffineTransform {
        media.shownAtLift
            .concatenating(float.mirror)
            .concatenating(VectorCanvas.affine(from: float.frame.transform, aspect: float.frame.aspect,
                                               stretchAxis: float.frame.stretchAxis, pivot: float.pivot))
    }

    /// **Where the picture should be drawn for `placement`**, in the same space as `shownPlacement`.
    ///
    /// Both start from where it is drawn now and change only what they name, so a placement can
    /// never move something it did not mention.
    private func targetPlacement(of placement: MediaPlacement, for media: FloatedMedia,
                                in float: VectorFloat) -> CGAffineTransform? {
        let current = Self.shownPlacement(of: media, in: float)
        switch placement {
        case .centred:
            guard let canvasSize else { return nil }
            var centred = current
            centred.tx = canvasSize.width / 2
            centred.ty = canvasSize.height / 2
            return centred
        case .actualSize:
            let natural = media.element.naturalSize, pixels = media.element.pixelSize
            guard natural.width > 0, pixels.width > 0 else { return nil }
            let flip = type(of: media.element).sourceFlip
            // The mirror is peeled off so the picture's own turn can be read from what is left, which
            // is a proper rotation-and-scale. `flip` is its own inverse, so `flip.concatenating(shown)`
            // is the shown placement with the reflection taken out.
            let reflected = current.a * current.d - current.b * current.c < 0
            let unmirrored = reflected ? flip.concatenating(current) : current
            // **Upright, and a flipped picture keeps the flip it has.** A mirrored placement stores a
            // horizontal flip plus a rotation, and a vertical flip is that flip turned half way round —
            // so "rotation 0" read literally would turn a vertically flipped picture into a
            // horizontally flipped one. Landing on whichever of the two upright flips is nearer keeps
            // what the artist can see.
            var turn: CGFloat = 0
            if reflected,
               let pose = ObjectTransformFrame.decompose(unmirrored, preferringAxisNear: 0),
               abs(pose.rotation.remainder(dividingBy: 2 * .pi)) > .pi / 2 {
                turn = .pi
            }
            let upright = VectorCanvas.affine(from: LayerTransform(position: CGPoint(x: current.tx, y: current.ty),
                                                                  scale: pixels.width / natural.width,
                                                                  rotation: turn),
                                              aspect: 1, stretchAxis: 0, pivot: .zero)
            return reflected ? flip.concatenating(upright) : upright
        }
    }

    /// **The box transform that draws the picture at `target`**, solved from
    /// `shownAtLift · mirror · boxAffine = target` — the one equation a nudge is, read for its last
    /// factor. Everything the layer's own transform contributed cancels out of it.
    ///
    /// The matrix is read back into the box's own fields the way a stretched placement is
    /// (`VectorCanvas.placed(_:through:)`, `ObjectTransformFrame.decompose`), because the answer is
    /// not always a similarity: a picture the artist has Freeform-stretched needs its stretch undone
    /// too.
    private static func boxFields(placing target: CGAffineTransform, media: FloatedMedia, in float: VectorFloat)
        -> (transform: LayerTransform, aspect: CGFloat, stretchAxis: CGFloat)? {
        guard let unmirror = invertedAffine(float.mirror), let unlift = invertedAffine(media.shownAtLift) else {
            return nil
        }
        let box = unmirror.concatenating(unlift).concatenating(target)
        guard let pose = ObjectTransformFrame.decompose(box, preferringAxisNear: float.frame.stretchAxis) else {
            return nil
        }
        return (LayerTransform(position: float.pivot.applying(box), scale: pose.scale, rotation: pose.rotation),
                pose.aspect, pose.stretchAxis)
    }

    /// Whether two placements are the same picture, to well under a thousandth of a canvas pixel.
    private static func sameWithinRounding(_ a: CGAffineTransform, _ b: CGAffineTransform) -> Bool {
        [a.a - b.a, a.b - b.b, a.c - b.c, a.d - b.d, a.tx - b.tx, a.ty - b.ty].allSatisfy { abs($0) < 1e-4 }
    }
}
