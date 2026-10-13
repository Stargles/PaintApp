import Combine
import SwiftUI

/// **The brush's colour, in an object of its own** — TODO (179), `FillSettings`' shape (TODO (157)).
///
/// It was `@Published` on `CanvasManager`, and every view in the editor observes `CanvasManager`, so each
/// tick of a drag on the brush's colour picker was a SwiftUI pass over the whole editor — the toolbars, the
/// timeline, the layer rail, the canvas's reconcile — 8–14 ms a tick on the iPad 9 simulator
/// (PERFORMANCE.md §31.4) for a colour a swatch and the next stroke use. Here only the views that show it
/// observe it: the toolbar's colour swatch, the side toolbar's eyedropper button and the colour panel's host.
/// The canvas is told directly (`CanvasView.Coordinator` subscribes), so the next stroke is drawn in it.
///
/// `CanvasManager.brushColor` reads and writes it.
final class BrushColorState: ObservableObject {
    @Published var color: Color = .black
}
