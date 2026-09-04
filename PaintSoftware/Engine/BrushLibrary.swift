import Foundation

/// Built-in brush presets, and the on-disk home for user-imported custom brushes. Real pressure-
/// curve tuning and the import flow are filled in going forward; the preset values here are
/// reasonable starting points, not final-tuned.
enum BrushLibrary {
    static let softRound = Brush(
        name: "Soft Round", shape: .softRound, size: 18,
        spacingFraction: 0.08, hardness: 0.15, stabilization: 0.25,
        dynamics: BrushDynamics(sizePressure: 0.5, opacityPressure: 0.6, minSizeFraction: 0.2)
    )

    static let hardRound = Brush(
        name: "Hard Round", shape: .hardRound, size: 10,
        spacingFraction: 0.05, hardness: 0.95, stabilization: 0.1,
        dynamics: BrushDynamics(sizePressure: 0.4, opacityPressure: 0.1, minSizeFraction: 0.4)
    )

    static let pencil = Brush(
        name: "Pencil", shape: .pencil, size: 6,
        opacity: 0.9, spacingFraction: 0.04, hardness: 0.7, stabilization: 0.15,
        dynamics: BrushDynamics(sizePressure: 0.3, opacityPressure: 0.5, minSizeFraction: 0.5)
    )

    static let pen = Brush(
        name: "Pen", shape: .pen, size: 4,
        opacity: 1, spacingFraction: 0.03, hardness: 1.0, stabilization: 0.4,
        dynamics: BrushDynamics(sizePressure: 0.15, opacityPressure: 0.05, minSizeFraction: 0.85)
    )

    static let square = Brush(
        name: "Square", shape: .square, size: 16,
        spacingFraction: 0.15, hardness: 1.0, stabilization: 0.2,
        dynamics: BrushDynamics(sizePressure: 0.3, opacityPressure: 0.2, minSizeFraction: 0.5)
    )

    /// Order shown in the brush picker.
    static let defaults: [Brush] = [softRound, hardRound, pencil, pen, square]

    static var customBrushesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Brushes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
