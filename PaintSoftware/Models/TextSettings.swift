import Combine

/// **The text tool's recipe, in an object of its own** — TODO (179), `FillSettings`' shape (TODO (157)).
///
/// The recipe was `@Published` on `CanvasManager`, and every view in the editor observes
/// `CanvasManager`, so each tick of a Text panel slider — and each keystroke, and each tick of the colour
/// picker while a box was open — was a SwiftUI pass over the whole editor (the canvas's reconcile, every
/// toolbar body, the timeline) for a value the panel and the box draw. Here only the views that show it
/// observe it: the Text panel and the toolbar's colour swatch while a box is open. The canvas is told
/// directly (`CanvasManager.onHeldPictureMoved`), and the box's glyphs are drawn off the main thread
/// (`TextOverlayView`).
///
/// `CanvasManager.textRecipe` reads and writes it; `textRecipeDidChange()` is what a panel control calls
/// after writing, so the font is re-resolved and a pristine box regrown in one place.
final class TextSettings: ObservableObject {

    /// The draft the panel's controls and the box's keystrokes both write — a live box's while one is
    /// open, and the next box's between them: font, size, tracking and colour carry over, and only the
    /// string is cleared when a box is placed.
    @Published var recipe = TextRecipe()

    /// Why the face on screen is not the one the recipe names, when it is not — what the panel says out
    /// loud (`FontLibrary.resolve`). Resolved whenever the recipe changes.
    @Published var fontSubstitution: FontSubstitution?
}
