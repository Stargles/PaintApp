import UIKit

/// **The live picture of an object the pen is dragging out** — TODO (149). Pinned to the canvas
/// container like every overlay, so its coordinates are canvas points and it moves, scales and turns
/// with the canvas for free.
///
/// It draws one `PlacementPlan` and nothing else: the same value the lift lays down, so what grows
/// under the pen is what lands. Every kind is a Core Animation layer whose geometry is re-set per pen
/// sample — a path, a bounds and a transform — so a drag redraws no pixels: a shape is a `CAShapeLayer`
/// in the brush colour, a picture is its image in a layer, and a gradient is a `CAGradientLayer` fed the
/// same 257-stop Oklab ramp (`LinearGradientPaint.rampComponents`) the vector renderer draws, laid along
/// the band's own axis so its ends are the gradient's ends. A clip is drawn as a translucent frame:
/// its first frame would have to be turned by the clip's own orientation to match what lands.
///
/// Never interactive, and it claims no touch (`CanvasPlaneView` answers `point(inside:)` for every view
/// in the plane, but a view with interaction off is never hit), so where it sits in the stack decides
/// nothing about who owns the pen.
final class PlacementPreviewView: CanvasPlaneView {

    private let solidLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let pictureLayer = CALayer()
    /// The picture `pictureLayer.contents` was last made from, so a drag re-renders it once rather than
    /// once per pen sample.
    private var pictureSource: UIImage?

    /// The longest side the preview's copy of a picture is rendered at, in pixels. A drag shows a
    /// picture a few hundred points across; a 12-megapixel photo as a layer's contents would be 48 MB
    /// for a thing on screen for a second.
    private static let pictureLongSide: CGFloat = 1024

    /// The default ramp as colours, built once: it is the same for every gradient the Add menu places
    /// and 257 `CGColor`s per pen sample would be the most expensive line of the drag.
    private static let defaultRamp: [CGColor] = {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let components = LinearGradientPaint.fresh(from: .zero, to: .zero).rampComponents
        return stride(from: 0, to: components.count, by: 4).compactMap { i in
            CGColor(colorSpace: space, components: Array(components[i..<(i + 4)]))
        }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true

        gradientLayer.colors = Self.defaultRamp
        gradientLayer.locations = LinearGradientPaint.rampLocations.map { NSNumber(value: Double($0)) }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)

        pictureLayer.contentsGravity = .resize

        for sublayer in [solidLayer, gradientLayer, pictureLayer] {
            sublayer.isHidden = true
            layer.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `plan`, drawing a shape in `color` (a gradient and a picture carry their own).
    func show(_ plan: PlacementPlan, color: UIColor) {
        // Implicit animations would trail the preview a quarter-second behind the pen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        isHidden = false
        solidLayer.isHidden = true
        gradientLayer.isHidden = true
        pictureLayer.isHidden = true

        switch plan {
        case .solid(let shape):
            solidLayer.path = shape.rotatedCGPath
            solidLayer.fillColor = color.cgColor
            solidLayer.isHidden = false
        case .gradient(let band, _, _):
            gradientLayer.bounds = CGRect(origin: .zero, size: band.boundingRect.size)
            gradientLayer.position = band.center
            gradientLayer.transform = CATransform3DMakeRotation(band.rotation, 0, 0, 1)
            gradientLayer.isHidden = false
        case .media(let media, let centre, let size):
            pictureLayer.bounds = CGRect(origin: .zero, size: size)
            pictureLayer.position = centre
            setPicture(media.poster)
            // A clip has no picture to show: a translucent frame says where it will land.
            pictureLayer.backgroundColor = media.poster == nil ? UIColor.white.withAlphaComponent(0.25).cgColor : nil
            pictureLayer.borderColor = UIColor.white.cgColor
            pictureLayer.borderWidth = media.poster == nil ? 2 : 0
            pictureLayer.isHidden = false
        }
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
        solidLayer.path = nil
        setPicture(nil)
    }

    /// **Upright**, drawn through UIKit rather than handed over as `cgImage`: a photo carries its
    /// orientation as metadata that `UIImage` honours and a bare `CGImage` does not, so a portrait
    /// phone photo would preview on its side and land the right way up.
    private func setPicture(_ picture: UIImage?) {
        guard picture !== pictureSource else { return }
        pictureSource = picture
        guard let picture, picture.size.width > 0, picture.size.height > 0 else {
            pictureLayer.contents = nil
            return
        }
        let longSide = max(picture.size.width, picture.size.height)
        let shrink = min(1, Self.pictureLongSide / longSide)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let size = CGSize(width: picture.size.width * shrink, height: picture.size.height * shrink)
        pictureLayer.contents = UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in picture.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}
