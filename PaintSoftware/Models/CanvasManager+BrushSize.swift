import Foundation
import CoreGraphics

// MARK: - A stroke tool's size as a percentage of the canvas — TODO item (79)
//
// A profile's `size` (`ToolProfile`, copied from `Brush.size`) is unchanged by this feature: it stays
// in canvas points, exactly as `Brush.size`'s own doc comment already says, and every consumer
// downstream of it — `BrushStamper`, the brush library, a saved project's strokes — reads and writes
// canvas points exactly as before. What is new is purely the side toolbar's slider and its badge: a
// *presentation* of that same points value as a percentage of this document's canvas, computed fresh
// from the size and `canvasSize` on every read rather than stored.
//
// **Why points and not percent is what persists.** A brush preset ("a 20pt fineliner") is meant to
// draw the same absolute line whichever document it is used in — that is the whole point of a
// preset library shared across documents of different sizes. Persisting a *percentage* instead would
// make the same preset draw a hairline on a poster-sized canvas and a fat marker on a small one,
// which is not what "20pt fineliner" promises. So a document opened at a different canvas size keeps
// drawing the same absolute stroke width it always did; only the % this file computes for the
// slider's badge changes, because it is answering a different question — "how big is this brush
// *relative to this canvas*" — each time it is asked.
//
// **One curve for every tool.** The eraser's rail slider used to bind its size directly — 1...50,
// linear — while the brush's went through `BrushSizeCurve`; TODO (79)(a), the owner: *"I noticed that
// the eraser does not have it [the log curve]."* Both read and write through the two functions below.

extension CanvasManager {
    /// TODO (79)'s "100%": the canvas's shorter side, in points. The *artwork* rect (`artworkSize`),
    /// not the padded buffer (`canvasSize`) — `canvasPadding` is blank margin the artist added on
    /// purpose to work outside the drawn area, and sizing a brush off of it would make the same
    /// brush read as a different percentage purely because the artist dragged the padding slider,
    /// with nothing about the drawing itself having changed.
    ///
    /// Falls back to `1` with no document, which only matters to a caller that reads this before a
    /// canvas exists — the side toolbar itself never does, since it has nothing to render without
    /// one — and keeps `sizePercent(of:)` and the log curve's `log`/`pow` calls finite rather than
    /// dividing by zero.
    var brushSizeReferenceExtent: CGFloat {
        guard let size = artworkSize, size.width > 0, size.height > 0 else { return 1 }
        return min(size.width, size.height)
    }

    /// `tool`'s size (canvas points) as a fraction of `brushSizeReferenceExtent` — `1.0` means a
    /// stroke as wide as the canvas is short. What the side toolbar's badge multiplies by 100 and
    /// rounds. The reference extent is a property of the *canvas*, not of any tool, so every tool reads
    /// the one accessor above.
    func sizePercent(of tool: StrokeTool) -> Double {
        Double(toolProfiles[tool].size / brushSizeReferenceExtent)
    }

    /// The side toolbar's vertical `Slider` position for `tool`'s size — `0...1`, where
    /// `BrushSizeCurve` is the (currently logarithmic — see its own doc comment) map to and from a
    /// percentage of the canvas. This and `setSizeSliderPosition` are the **only** place that
    /// conversion happens for the live toolbar slider, so a drag always round-trips through the same
    /// two functions whichever direction it reads or writes the size.
    func sizeSliderPosition(of tool: StrokeTool) -> Double {
        BrushSizeCurve.sliderPosition(forPercent: sizePercent(of: tool))
    }

    func setSizeSliderPosition(_ position: Double, of tool: StrokeTool) {
        let percent = BrushSizeCurve.percent(forSliderPosition: position)
        toolProfiles[tool].size = CGFloat(percent) * brushSizeReferenceExtent
    }
}
