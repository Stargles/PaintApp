import UIKit

struct Cel: Identifiable {
    let id: UUID
    var startFrame: Int
    var frameCount: Int
    /// Live brush strokes, rasterized directly at canvas-native resolution (see
    /// `RasterLayerTexture`'s doc comment for why this replaced `PKDrawing`). A class, not a value
    /// type — call sites that need an independent copy (duplicating/splitting a cel) must call
    /// `.makeCopy()` explicitly rather than relying on implicit value semantics.
    var raster: RasterLayerTexture
    /// Rasterized bucket-fill output for this frame, composited underneath both `bakedImage` and
    /// `raster`'s strokes within the same layer. Nil until the fill tool is used on this cel.
    var fillImage: UIImage? = nil
    /// Flattened raster content "baked" into this cel by a pixel-level operation (select+move,
    /// duplicate, color fill, clear selection) — see SelectionModels.swift. Sits above `fillImage`
    /// and underneath `raster`'s live strokes when rendered. Nil means the cel has never had a
    /// raster operation applied beyond its own strokes.
    var bakedImage: UIImage? = nil
    /// Vector content for `.vector` layers (strokes/images stored as geometry, re-rasterized at
    /// canvas-native resolution — see `VectorCanvas`). Nil on `.raster` layers, whose live strokes
    /// live in `raster` instead. A vector layer still uses `fillImage`/`bakedImage` the same way a
    /// raster one does; only the live-stroke tier differs.
    var vector: VectorCanvas? = nil
    /// Non-nil makes this an *interpolated* cel: its content is computed from the recipe's
    /// references at time `t` rather than stored here. See `InterpolationRecipe` and
    /// VECTOR_INTERPOLATION_PLAN.md §4.
    ///
    /// It lives on `Cel` — a struct, inside `Layer.cels`, which `CanvasManager.StructureSnapshot`
    /// copies wholesale — precisely so that undo covers every recipe edit with no new machinery.
    /// That is the whole reason for this placement rather than a side table keyed by cel id.
    ///
    /// A `.reproject` recipe coexists with `vector` content (the artist's own drawing, re-posed); a
    /// `.generate` recipe normally sits on a cel with none.
    var interpolation: InterpolationRecipe? = nil
    var thumbnail: UIImage? = nil

    var endFrame: Int { startFrame + frameCount }
}
