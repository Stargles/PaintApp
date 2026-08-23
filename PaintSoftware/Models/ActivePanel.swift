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
/// actually apply lives on a value layer's own Blend Mode menu (`LayerPanel.valueBlendModeRow`),
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
    /// there; the way in is the Actions menu's "Add Text" row, which is why `ActionsMenu` is the one
    /// panel that had to grow an `activePanel` binding. See `Tool.text`.
    case text
}
