import UIKit

struct Cel: Identifiable {
    let id: UUID
    var startFrame: Int
    var frameCount: Int
    /// Live brush strokes, rasterized at canvas-native resolution. A class, not a value type — call
    /// sites needing an independent copy (duplicating/splitting a cel) must call `.makeCopy()`.
    var raster: RasterLayerTexture
    /// Rasterized bucket-fill output, composited underneath `bakedImage` and `raster`'s strokes.
    /// Nil until the fill tool is used on this cel.
    var fillImage: UIImage? = nil
    /// Flattened raster content "baked" in by a pixel-level operation (select+move, duplicate,
    /// color fill, clear selection). Sits above `fillImage`, underneath `raster`'s live strokes.
    var bakedImage: UIImage? = nil
    /// Vector content for `.vector` layers (strokes/images as geometry, re-rasterized at
    /// canvas-native resolution). Nil on `.raster` layers. Still uses `fillImage`/`bakedImage`
    /// the same way a raster layer does; only the live-stroke tier differs.
    var vector: VectorCanvas? = nil
    /// Non-nil makes this an *interpolated* cel: content is computed from the recipe's references
    /// at time `t` rather than stored here. Lives on `Cel` (inside `Layer.cels`, which
    /// `CanvasManager.StructureSnapshot` copies wholesale) so undo covers every recipe edit with
    /// no new machinery. A `.reproject` recipe coexists with `vector` content (the artist's own
    /// drawing, re-posed); a `.generate` recipe normally sits on a cel with none.
    var interpolation: InterpolationRecipe? = nil
    var thumbnail: UIImage? = nil

    var endFrame: Int { startFrame + frameCount }
}
