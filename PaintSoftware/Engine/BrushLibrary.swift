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
    static let softRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000001")!,
        name: "Soft Round", tip: .round, size: 18,
        spacingFraction: 0.08, hardness: 0.15, stabilization: 0.25,
        dynamics: BrushDynamics(sizePressure: 0.5, opacityPressure: 0.6, minSizeFraction: 0.2)
    )

    static let hardRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000002")!,
        name: "Hard Round", tip: .round, size: 10,
        spacingFraction: 0.05, hardness: 0.95, stabilization: 0.1,
        dynamics: BrushDynamics(sizePressure: 0.4, opacityPressure: 0.1, minSizeFraction: 0.4)
    )

    static let pencil = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000003")!,
        name: "Pencil", tip: .round, size: 6,
        opacity: 0.9, spacingFraction: 0.04, hardness: 0.7, stabilization: 0.15,
        dynamics: BrushDynamics(sizePressure: 0.3, opacityPressure: 0.5, minSizeFraction: 0.5)
    )

    static let pen = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000004")!,
        name: "Pen", tip: .round, size: 4,
        opacity: 1, spacingFraction: 0.03, hardness: 1.0, stabilization: 0.4,
        dynamics: BrushDynamics(sizePressure: 0.15, opacityPressure: 0.05, minSizeFraction: 0.85)
    )

    /// No `hardness`: a square dab is a picture and its edge is in the tip's own pixels. The field
    /// still exists on `Brush` for the `.round` tip, and naming it here would say this brush reads
    /// something it does not.
    static let square = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000005")!,
        name: "Square", tip: .stamp(.builtIn(.square)), size: 16,
        spacingFraction: 0.15, stabilization: 0.2,
        dynamics: BrushDynamics(sizePressure: 0.3, opacityPressure: 0.2, minSizeFraction: 0.5)
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
