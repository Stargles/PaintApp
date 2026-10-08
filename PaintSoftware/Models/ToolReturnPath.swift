/// **Where the canvas goes back to when a momentary tool lets go** — the one memory behind the
/// eyedropper's one tap and a primed object's one placement (`Tool.isMomentary`).
///
/// Both are entered in the middle of drawing and left for the tool the artist was holding, and they
/// nest in exactly one way: the eyedropper armed straight from a primed object hands back to it, and
/// the object, once placed, hands back to the tool before it was primed. So the memory is a path of
/// tools, innermost last — `[pen, place]` while the eyedropper is armed over an object primed from
/// the pen — and **a primed object lives exactly as long as `.place` is current or on the path**.
///
/// A tool the artist picks any other way ends the path (`CanvasManager.selectedTool`'s `didSet`), so
/// no door that switches tools has to remember to.
struct ToolReturnPath: Equatable {

    private var beneath: [Tool] = []

    /// Records `current` as the tool beneath `tool`, which is about to be selected. **Not when `tool`
    /// is already current**: arming the eyedropper twice must not make it its own previous tool, which
    /// would strand the artist in it.
    mutating func enter(_ tool: Tool, from current: Tool) {
        if current != tool { beneath.append(current) }
    }

    /// The tool the innermost momentary tool hands back to — the pen if nothing was recorded.
    var handsBackTo: Tool { beneath.last ?? .pen }

    /// Leaves the innermost momentary tool, and answers the tool to select in its place.
    mutating func leave() -> Tool { beneath.popLast() ?? .pen }

    /// Whether `tool` is parked beneath the momentary tool that is current — an object primed and
    /// then passed over by the eyedropper.
    func passesThrough(_ tool: Tool) -> Bool { beneath.contains(tool) }

    /// The artist picked a tool by another door: nothing is handed back to any more.
    mutating func abandon() { beneath.removeAll() }
}
