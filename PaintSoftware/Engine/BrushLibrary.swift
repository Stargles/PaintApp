import Foundation

/// Built-in brush presets, and the on-disk home for user-imported custom brushes. Real pressure-
/// curve tuning and the import flow are filled in going forward; the preset values here are
/// reasonable starting points, not final-tuned.
///
/// **The five ids are written down rather than minted.** `UUID()` in a `static let` is one value per
/// *process*, so a preset saved into a project's manifest came back with an id no running copy of
/// the app could match — the picker's `preset.id == selectedBrush.id` highlight found nothing after
/// a reload, and `isPencilPreset` below would have inherited the same hole. Stable ids make a
/// preset's identity a fact about the preset. §12 stage 9 replaces this list with the generated set
/// in groups; these ids belong to the presets, so they go when the presets do.
enum BrushLibrary {
    /// **BRUSH.md §12 stage 7: the dynamics are rows now, and the ink did not move.**
    ///
    /// Every preset below used to carry a `BrushDynamics(sizePressure: k, opacityPressure: o,
    /// minSizeFraction: m)`, and §10's ledger deletes that type's two blends outright rather than
    /// keeping them as a fast path beside the general one. What each preset carries instead is the
    /// same statement as two rows of §6's matrix:
    ///
    /// - `dab.size` is `1 - k` and one `size ← pressure` row of amount `k` ramps from `m` to 1. Read
    ///   plainly: *that fraction of the width is fixed, the rest comes from the pen.*
    /// - `dab.flow` is `1 - o` and one `flow ← pressure` row of amount `o` runs straight through.
    ///   **That row drove `opacity` until §12 stage 8**, which deleted the output: BRUSH.md §2.11
    ///   makes opacity the stroke's cap and flow what one stamp lays down, and pressure drives flow.
    ///   The numbers are untouched, so a single pass of any preset is the ink it always was; what
    ///   changed is that a second pass over the same ground now darkens toward the stroke's opacity
    ///   instead of past it.
    ///
    /// **Byte-identical, not merely equivalent** — the association and the order of operations are
    /// preserved exactly, and `ResponseCurve.scale`'s power of two is what makes the curve half exact.
    /// `BrushModulationLogicTests` renders all five before and after and asserts zero difference,
    /// which is the assertion that says the matrix subsumes what it replaced.
    static let softRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000001")!,
        name: "Soft Round", tip: .round, size: 18,
        dab: BrushDabSettings(size: 0.5, flow: 0.4, spacing: 0.08, hardness: 0.15),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.5, atZero: 0.2),
            .flowFromPressure(amount: 0.6)
        ])
    )

    static let hardRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000002")!,
        name: "Hard Round", tip: .round, size: 10,
        dab: BrushDabSettings(size: 0.6, flow: 0.9, spacing: 0.05, hardness: 0.95),
        stroke: BrushStrokeSettings(stabilization: 0.1),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.4, atZero: 0.4),
            .flowFromPressure(amount: 0.1)
        ])
    )

    static let pencil = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000003")!,
        name: "Pencil", tip: .round, size: 6, opacity: 0.9,
        dab: BrushDabSettings(size: 0.7, flow: 0.5, spacing: 0.04, hardness: 0.7),
        stroke: BrushStrokeSettings(stabilization: 0.15),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            .flowFromPressure(amount: 0.5)
        ])
    )

    static let pen = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000004")!,
        name: "Pen", tip: .round, size: 4, opacity: 1,
        dab: BrushDabSettings(size: 0.85, flow: 0.95, spacing: 0.03, hardness: 1.0),
        stroke: BrushStrokeSettings(stabilization: 0.4),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.15, atZero: 0.85),
            .flowFromPressure(amount: 0.05)
        ])
    )

    /// No `hardness`: a square dab is a picture and its edge is in the tip's own pixels. The field
    /// still exists on `BrushDabSettings` for the `.round` tip, and naming it here would say this
    /// brush reads something it does not.
    static let square = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000005")!,
        name: "Square", tip: .stamp(.builtIn(.square)), size: 16,
        dab: BrushDabSettings(size: 0.7, flow: 0.8, spacing: 0.15),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            .flowFromPressure(amount: 0.2)
        ])
    )

    /// Order shown in the brush picker.
    static let defaults: [Brush] = [softRound, hardRound, pencil, pen, square]

    /// **Whether picking this preset should put the artist on the pencil rather than the pen.**
    ///
    /// `CanvasManager.selectBrush` asked `brush.shape == .pencil`, and that question no longer
    /// exists: a pencil and a pen both stamp a `.round` tip and differ in their hardness, spacing
    /// and dynamics, which is exactly why the five shapes collapsed to two. So the affinity is to
    /// the *preset* — which is a fact the library owns and the brush value does not, and is why
    /// this is here rather than a field on `Brush`. A field would be the pair `BrushTip` just
    /// removed, wearing a tool's name.
    ///
    /// §12 stage 9 replaces `defaults` with a group tree, at which point a group answers this and
    /// the identity check goes with the preset it names.
    static func isPencilPreset(_ brush: Brush) -> Bool { brush.id == pencil.id }

    static var customBrushesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Brushes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
