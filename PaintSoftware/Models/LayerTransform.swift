import CoreGraphics

/// Position/scale/rotation, in canvas point space (same coordinate system as everything drawn into
/// a Cel's raster). Used for a `VectorImageElement`'s own placement, and for driving/reading a
/// vector layer's overall transform via `ObjectTransformOverlayView` while `isVectorTransforming`.
struct LayerTransform: Equatable {
    var position: CGPoint
    var scale: CGFloat
    var rotation: CGFloat // radians

    static let identity = LayerTransform(position: .zero, scale: 1, rotation: 0)
}
