import Foundation

/// Which settings panel is open above the canvas.
///
/// **It lives here, in `Models/`, rather than in `TopToolbar.swift` where it was declared, for the
/// reason SESSION_LOG records against that file: `View` files are not compiled a second time into
/// the UI-test target**, so `@testable import` type-checks against them but does not link, and
/// anything a fast-tier logic test must name has to sit outside one. `CanvasTouchOwner` takes this
/// enum as an input, and `CanvasTouchOwnerLogicTests` walks every case of it — which is only
/// possible from here. Moving the declaration changes nothing about behaviour: Swift has no
/// per-file visibility, and the `Binding` extension that opens and closes a panel stays with the
/// toolbar that calls it.
///
/// **No `adjust` case.** The toolbar carried a slider icon for one, and behind it was
/// `StubToolPanel` — a placeholder that had never grown a feature. Every grade the artist can
/// actually apply lives on a value layer's own Blend Mode menu (`LayerPanel.blendOrEffectRow`),
/// reached from the layer they want to grade, which is where the owner said it belongs: "the adjust
/// icon at the top can be removed, its what the layer edit does."
///
/// `CaseIterable` exists for `CanvasTouchOwnerLogicTests`, which enumerates the whole input space of
/// the touch-ownership question rather than sampling it. **Only `.select` is load-bearing to that
/// question today** — every one of the fourteen gates that consults this enum spells `== .select` or
/// `!= .select` — and enumerating the rest is what makes that fact checkable instead of assumed.
enum ActivePanel: Equatable, CaseIterable {
    case none, actions, select, move, layers, brush, color, fill, eraser
    /// The text tool's settings panel. **Not opened from the toolbar** — there is no text icon
    /// there; the way in is the Add menu's "Add Text" row, which is why `AddMenu` is one of the two
    /// panels that had to grow an `activePanel` binding (`ActionsMenu` is the other, for its own
    /// sheets). See `Tool.text`.
    case text
    /// TODO (104) — Resize Canvas, Canvas Padding, Bake Precise Strokes, Fingers Can Paint, Render
    /// Resolution and the recorder entries, split out of `ActionsMenu` into `SettingsMenu` so
    /// "Actions" is left holding only the six actions the owner named. A toolbar icon of its own
    /// (`gearshape`), same shape as `.actions`.
    case settings
    /// TODO (103) — the "Add" submenu TODO (100) had put inside Actions, promoted to a toolbar icon
    /// of its own (`plus`): Insert Photo, Insert Video, Stream Screen, Add Text, Rectangle, Ellipse,
    /// Linear Gradient. See `AddMenu`.
    case add
}

extension ActivePanel {

    /// **Whether a canvas touch leaves this panel open for the tool the artist has armed.** The rule
    /// is `DrawingView`'s: a touch on the canvas closes whatever dropdown is standing over it, so the
    /// first touch both closes the menu and does its work.
    ///
    /// **The Text panel is the exception, because it is not a dropdown over the canvas but the text
    /// tool's own controls — and the touch is the tool at work.** The tap that places a box is what
    /// the panel's font, size and colour are *for*: closing it on that tap left the artist writing in
    /// a box whose menu had gone, to be got back by selecting the words again. The owner: *"When I
    /// create a text, then click on the board to place the box and start writing, I want to still be
    /// able to adjust the things on that menu after I make the text without having to select the text
    /// again."* The panel is bound to whichever box is open (`CanvasManager.textRecipe` is that box's
    /// draft) and to the next one when none is, and it goes with the tool: picking another tool
    /// closes it.
    func survivesACanvasTouch(withTool tool: Tool) -> Bool {
        self == .text && tool == .text
    }
}
