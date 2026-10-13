import XCTest
import SwiftUI

/// TODO (73)/(106)'s colour picker overhaul — the model, headless: the ring/triangle point<->colour
/// maths in `ColorMath` (no UIKit, no simulator gestures needed to check a round trip), then a scene's
/// Recent colours (`ColorPanelState`) and the app-wide `PaletteStore` — dedupe/cap and
/// CRUD/persistence/selection. `ColorPickerUITests` covers reachability (driving each tab from a fresh
/// document); this file covers whether the arithmetic and the two stores are correct.
final class ColorPickerLogicTests: XCTestCase {

    // MARK: - Isolated UserDefaults (same pattern `AppSettingsLogicTests` uses)

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "color-picker-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: - Hue ring

    /// TODO (106): the owner's own report — *"The red on the wheel is right, but red is selected at
    /// the top"* — was exactly `hueRingAngle`/`hueForRingTouch` disagreeing with `AngularGradient`'s
    /// own convention (0° at 3 o'clock, clockwise) about where angle 0 is. Cardinal points, in the
    /// corrected convention: 0=right, 0.25=down, 0.5=left, 0.75=up.
    func testHueRingAngleRoundTripsThroughAllFourCardinalHues() {
        XCTAssertEqual(ColorMath.hueForRingTouch(dx: 1, dy: 0), 0, accuracy: 0.0001, "Right (3 o'clock) is hue 0")
        XCTAssertEqual(ColorMath.hueRingAngle(forHue: 0), 0, accuracy: 0.0001)

        XCTAssertEqual(ColorMath.hueForRingTouch(dx: 0, dy: 1), 0.25, accuracy: 0.0001, "Down is a quarter turn clockwise")
        XCTAssertEqual(ColorMath.hueForRingTouch(dx: -1, dy: 0), 0.5, accuracy: 0.0001, "Left is halfway round")
        XCTAssertEqual(ColorMath.hueForRingTouch(dx: 0, dy: -1), 0.75, accuracy: 0.0001, "Up is three-quarters round")
    }

    func testHueRingAngleRoundTripsOverManyHues() {
        for i in 0..<37 {
            let hue = Double(i) / 36
            let angle = ColorMath.hueRingAngle(forHue: hue)
            let dx = cos(angle), dy = sin(angle)
            let recovered = ColorMath.hueForRingTouch(dx: dx, dy: dy)
            // Hue 1.0 and hue 0.0 are the same point on the ring; compare the wrapped distance.
            let delta = min(abs(recovered - hue), abs(recovered - hue + 1), abs(recovered - hue - 1))
            XCTAssertLessThan(delta, 0.0005, "hue \(hue) should round-trip through the ring's angle, got \(recovered)")
        }
    }

    /// The load-bearing regression test for TODO (106)'s hue-phase bug, pinned against the
    /// *drawing's own* angle convention rather than a second hard-coded constant: `dx = cos(θ), dy =
    /// sin(θ)` is where a touch would land at ring-angle θ under `AngularGradient`'s own convention
    /// (0° at 3 o'clock, clockwise in this y-down view — the same one `HueRing`'s explicit
    /// `startAngle`/`endAngle` states). Feeding that point to the drag handler and the resulting hue
    /// back into the marker's own placement function must return to the same angle, for the three
    /// primaries (0°, 120°, 240°) the owner named — this is `hueForRingTouch` and `hueRingAngle`
    /// checked against each other and against the gradient's own geometry, not against one another's
    /// copy of the same magic number.
    func testHueRingAngleAgreesWithTheGradientsOwnAngleConventionAtTheThreePrimaries() {
        for degrees in [0.0, 120.0, 240.0] {
            let gradientAngle = degrees * .pi / 180
            let dx = cos(gradientAngle), dy = sin(gradientAngle)
            let hue = ColorMath.hueForRingTouch(dx: dx, dy: dy)
            let markerAngle = ColorMath.hueRingAngle(forHue: hue)
            let delta = abs(atan2(sin(markerAngle - gradientAngle), cos(markerAngle - gradientAngle)))
            XCTAssertLessThan(delta, 0.0005,
                              "hue ring angle \(degrees)° should round-trip through the drag handler and land back at the same angle the gradient draws it, got \(markerAngle)")
        }
    }

    // MARK: - HSL triangle

    /// Saturation/lightness -> triangle point -> saturation/lightness, over a grid dense enough to
    /// cross the L=0.5 seam (where the fully-saturated edge switches from black-to-hue to
    /// hue-to-white) and to include both achromatic edges (L=0, L=1).
    func testTrianglePositionRoundTripsOverAGridOfSaturationLightness() {
        for sInt in stride(from: 0, through: 10, by: 1) {
            for lInt in stride(from: 0, through: 10, by: 1) {
                let s = Double(sInt) / 10
                let l = Double(lInt) / 10
                let point = ColorMath.trianglePosition(saturation: s, lightness: l)
                let back = ColorMath.triangleSaturationLightness(x: point.x, y: point.y)
                if l == 0 || l == 1 {
                    // Saturation is genuinely undefined at pure black/white — only lightness has to
                    // survive the round trip there (this is `triangleSaturationLightness`'s own
                    // convention: it always answers s=0 at those two lightnesses).
                    XCTAssertEqual(back.l, l, accuracy: 0.002, "lightness should round-trip at s=\(s), l=\(l)")
                } else {
                    XCTAssertEqual(back.s, s, accuracy: 0.002, "saturation should round-trip at s=\(s), l=\(l), got \(back)")
                    XCTAssertEqual(back.l, l, accuracy: 0.002, "lightness should round-trip at s=\(s), l=\(l), got \(back)")
                }
            }
        }
    }

    /// The three named vertices are exactly hue/black/white — the identity `trianglePosition` is
    /// built on, stated as a test rather than only as a doc comment.
    func testTheTrianglesThreeCornersAreHueBlackAndWhite() {
        let hueCorner = ColorMath.trianglePosition(saturation: 1, lightness: 0.5)
        XCTAssertEqual(hueCorner.x, ColorMath.trianglePureHueVertex.x, accuracy: 0.0001)
        XCTAssertEqual(hueCorner.y, ColorMath.trianglePureHueVertex.y, accuracy: 0.0001)

        let blackCorner = ColorMath.trianglePosition(saturation: 0, lightness: 0)
        XCTAssertEqual(blackCorner.x, ColorMath.triangleBlackVertex.x, accuracy: 0.0001)
        XCTAssertEqual(blackCorner.y, ColorMath.triangleBlackVertex.y, accuracy: 0.0001)

        let whiteCorner = ColorMath.trianglePosition(saturation: 0, lightness: 1)
        XCTAssertEqual(whiteCorner.x, ColorMath.triangleWhiteVertex.x, accuracy: 0.0001)
        XCTAssertEqual(whiteCorner.y, ColorMath.triangleWhiteVertex.y, accuracy: 0.0001)
    }

    /// A drag that leaves the triangle entirely must still answer *some* valid, in-range
    /// saturation/lightness (the clamp-and-renormalize this function documents) rather than a
    /// negative or out-of-range value that would paint a marker nobody asked for.
    func testTriangleSaturationLightnessClampsPointsOutsideTheTriangle() {
        let farOutside = ColorMath.triangleSaturationLightness(x: 5, y: 5)
        XCTAssertGreaterThanOrEqual(farOutside.s, 0)
        XCTAssertLessThanOrEqual(farOutside.s, 1)
        XCTAssertGreaterThanOrEqual(farOutside.l, 0)
        XCTAssertLessThanOrEqual(farOutside.l, 1)
    }

    // MARK: - Triangle rotation (TODO (106): "rotated 90 degrees clockwise")

    /// The reference: *"at hue 0 the hue vertex points at the ring's red."* `trianglePureHueVertex`
    /// is `(0, -1)` in the triangle's own local frame — straight up, screen angle 270° by
    /// `hueRingAngle`'s convention — so `triangleRotation` has to add exactly +90° to land it on
    /// `hueRingAngle(forHue: 0)` (0°, the ring's own red after the phase fix above). Rotating the
    /// vertex by the view's own rotation formula and comparing the result to the ring's angle
    /// function is the same "test the drawing's angle function against the marker's" shape the hue
    /// ring test above uses, applied to the triangle's own extra turn.
    func testTriangleRotationPointsTheHueVertexAtTheRingsRedAtHueZero() {
        let rotation = ColorMath.triangleRotation(forHue: 0)
        let vertex = ColorMath.trianglePureHueVertex
        let rotated = (x: vertex.x * cos(rotation) - vertex.y * sin(rotation),
                       y: vertex.x * sin(rotation) + vertex.y * cos(rotation))
        let rotatedAngle = atan2(rotated.y, rotated.x)
        let ringRedAngle = ColorMath.hueRingAngle(forHue: 0)
        let delta = abs(atan2(sin(rotatedAngle - ringRedAngle), cos(rotatedAngle - ringRedAngle)))
        XCTAssertLessThan(delta, 0.0001, "the triangle's hue vertex must land on the ring's own red at hue 0")
    }

    /// The vertex must keep tracking the ring's own marker at every other hue too, not just at 0 —
    /// the "turned 90° clockwise" is on top of the existing tracking behaviour, not instead of it.
    func testTriangleRotationTracksTheRingsMarkerAcrossHues() {
        let vertex = ColorMath.trianglePureHueVertex
        for i in 0..<12 {
            let hue = Double(i) / 12
            let rotation = ColorMath.triangleRotation(forHue: hue)
            let rotated = (x: vertex.x * cos(rotation) - vertex.y * sin(rotation),
                           y: vertex.x * sin(rotation) + vertex.y * cos(rotation))
            let rotatedAngle = atan2(rotated.y, rotated.x)
            let ringAngle = ColorMath.hueRingAngle(forHue: hue)
            let delta = abs(atan2(sin(rotatedAngle - ringAngle), cos(rotatedAngle - ringAngle)))
            XCTAssertLessThan(delta, 0.0001, "the triangle's hue vertex should track the ring's marker at hue \(hue)")
        }
    }

    // MARK: - HSL <-> RGB

    func testRGBToHSLRoundTripsThePrimariesSecondariesAndGreys() {
        let samples: [(r: Double, g: Double, b: Double)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (0, 1, 1), (1, 0, 1),
            (0, 0, 0), (1, 1, 1), (0.5, 0.5, 0.5), (0.8, 0.3, 0.1), (0.1, 0.6, 0.9)
        ]
        for rgb in samples {
            let hsl = ColorMath.rgbToHSL(r: rgb.r, g: rgb.g, b: rgb.b)
            let back = ColorMath.hslToRGB(h: hsl.h, s: hsl.s, l: hsl.l)
            XCTAssertEqual(back.r, rgb.r, accuracy: 0.0005, "R should round-trip for \(rgb)")
            XCTAssertEqual(back.g, rgb.g, accuracy: 0.0005, "G should round-trip for \(rgb)")
            XCTAssertEqual(back.b, rgb.b, accuracy: 0.0005, "B should round-trip for \(rgb)")
        }
    }

    func testAchromaticRGBAlwaysReadsHueZeroAndSaturationZero() {
        for grey in [0.0, 0.2, 0.5, 0.8, 1.0] {
            let hsl = ColorMath.rgbToHSL(r: grey, g: grey, b: grey)
            XCTAssertEqual(hsl.h, 0, "Grey \(grey) must not report a garbage hue")
            XCTAssertEqual(hsl.s, 0, "Grey \(grey) must not report spurious saturation")
        }
    }

    // MARK: - The triangle's shading, as pixels

    /// The shading is a corner blend (`ColorMath.triangleShadingPixels`), and it must be *the same
    /// colour* `hslToRGB` gives at the `(s, l)` the gesture reads at that point — inside the triangle
    /// where the weights are all positive, and outside it where both take the clamp. Compared at the
    /// pixel centres, where the maths is exact, for every pixel of a small image at several hues: a
    /// blend with one channel swapped, a pure colour taken at the wrong lightness, or a clamp the
    /// gesture does not share, goes red here.
    func testTheTriangleShadingIsHSLsColourAtEveryPixelInsideAndOutside() {
        let side = 24
        for hue in [0.0, 0.1, 1.0 / 3.0, 0.5, 0.75, 0.95] {
            let pixels = ColorMath.triangleShadingPixels(hue: hue, side: side)
            XCTAssertEqual(pixels.count, side * side * 4, "an RGBA8 image of side \(side)")
            for row in 0..<side {
                for column in 0..<side {
                    let x = (Double(column) + 0.5) / Double(side) * 2 - 1
                    let y = (Double(row) + 0.5) / Double(side) * 2 - 1
                    let sl = ColorMath.triangleSaturationLightness(x: x, y: y)
                    let want = ColorMath.hslToRGB(h: hue, s: sl.s, l: sl.l)
                    let offset = (row * side + column) * 4
                    for (channel, expected) in [want.r, want.g, want.b].enumerated() {
                        XCTAssertEqual(Double(pixels[offset + channel]) / 255, expected, accuracy: 1.5 / 255,
                                       "hue \(hue), pixel (\(column), \(row)), channel \(channel)")
                    }
                    XCTAssertEqual(pixels[offset + 3], 255, "the shading is opaque; the vector clip is the edge")
                }
            }
        }
    }

    /// The three corners of the triangle are the three colours it is named for — read off the image
    /// itself, near each vertex, not off the maths that drew it.
    func testTheTriangleShadingsCornersAreTheHueBlackAndWhite() {
        let side = 200, hue = 0.58
        let pixels = ColorMath.triangleShadingPixels(hue: hue, side: side)
        func colour(at vertex: (x: Double, y: Double)) -> (r: Double, g: Double, b: Double) {
            // Pulled 4% toward the centroid so the sample is inside the triangle, not on its edge.
            let x = vertex.x * 0.96, y = vertex.y * 0.96
            let column = Int((x + 1) / 2 * Double(side)), row = Int((y + 1) / 2 * Double(side))
            let offset = (row * side + column) * 4
            return (Double(pixels[offset]) / 255, Double(pixels[offset + 1]) / 255, Double(pixels[offset + 2]) / 255)
        }
        let pure = ColorMath.hslToRGB(h: hue, s: 1, l: 0.5)
        let top = colour(at: ColorMath.trianglePureHueVertex)
        XCTAssertEqual(top.r, pure.r, accuracy: 0.1); XCTAssertEqual(top.g, pure.g, accuracy: 0.1)
        XCTAssertEqual(top.b, pure.b, accuracy: 0.1)
        let white = colour(at: ColorMath.triangleWhiteVertex)
        XCTAssertGreaterThan(min(white.r, white.g, white.b), 0.9, "the white corner is white")
        let black = colour(at: ColorMath.triangleBlackVertex)
        XCTAssertLessThan(max(black.r, black.g, black.b), 0.1, "the black corner is black")
    }

    // MARK: - PickerColor

    /// A grey carries no hue (`rgbToHSB` says 0), and taking that at its word would throw the ring's
    /// marker to red whenever the artist picked a grey or typed `808080`.
    @MainActor
    func testLoadingAnAchromaticColourKeepsTheHueTheRingAlreadyHad() {
        let model = PickerColor()
        model.load(Color(hex: "3366FF")!, supportsOpacity: true)
        let blueHue = model.hue
        XCTAssertGreaterThan(blueHue, 0.5, "PREMISE: the colour is a blue")
        model.load(Color(hex: "808080")!, supportsOpacity: true)
        XCTAssertEqual(model.hue, blueHue, accuracy: 1e-9, "a grey did not move the hue")
        XCTAssertEqual(model.saturation, 0, accuracy: 1e-6)
        XCTAssertEqual(model.hexString, "808080")
    }

    /// A host with no opacity row (a canvas background, a gradient stop) never receives an alpha: an
    /// inbound swatch saved with one arrives opaque.
    @MainActor
    func testAHostWithoutOpacityLoadsEveryColourOpaque() {
        let model = PickerColor()
        model.load(Color(hex: "FF000080")!, supportsOpacity: false)
        XCTAssertEqual(model.alpha, 1, "no opacity row: alpha is forced to 1")
        XCTAssertEqual(model.hexString, "FF0000")
        model.load(Color(hex: "FF000080")!, supportsOpacity: true)
        XCTAssertEqual(model.alpha, 128.0 / 255, accuracy: 0.01, "with one, it is kept")
    }

    /// The Triangle tab writes saturation and lightness at the stored hue and takes only the resulting
    /// saturation and brightness: the hue is untouched, and the pair reads back as it was written —
    /// including at an achromatic point, where re-deriving the hue from the round trip would lose it.
    @MainActor
    func testTheTrianglesWriteLeavesTheHueAndReadsBackAsWritten() {
        let model = PickerColor()
        model.hue = 0.31
        model.setHSL(saturation: 0.8, lightness: 0.4)
        XCTAssertEqual(model.hue, 0.31, accuracy: 1e-12, "the triangle never moves the hue")
        XCTAssertEqual(model.hsl.s, 0.8, accuracy: 1e-9)
        XCTAssertEqual(model.hsl.l, 0.4, accuracy: 1e-9)
        model.setHSL(saturation: 0, lightness: 0.5)
        XCTAssertEqual(model.hue, 0.31, accuracy: 1e-12, "a grey point keeps the hue the ring shows")
    }

    /// The model's colour is the colour the host receives: loaded from a hex and read back as the same
    /// hex, with the marker's position (saturation, brightness) where the hex says.
    @MainActor
    func testTheModelsColourIsTheColourItWasLoadedWith() {
        let model = PickerColor()
        for hex in ["FF0000", "00FF00", "0000FF", "FFFF00", "123456", "FEDCBA", "000000", "FFFFFF"] {
            model.load(Color(hex: hex)!, supportsOpacity: true)
            XCTAssertEqual(model.color.hexString, hex)
            XCTAssertEqual(model.opaqueColor.hexString, hex, "an opaque colour is its own opaque colour")
        }
        model.alpha = 0.5
        XCTAssertEqual(model.opaqueColor.hexString, "FFFFFF", "the opaque colour ignores alpha")
    }

    // MARK: - Recent colours (a scene's own)

    func testRecentColoursAreNewestFirst() {
        let panel = ColorPanelState()
        panel.recordPainted(Color(hex: "FF0000")!)
        panel.recordPainted(Color(hex: "00FF00")!)
        panel.recordPainted(Color(hex: "0000FF")!)
        XCTAssertEqual(panel.recentColors.map(\.hex), ["0000FF", "00FF00", "FF0000"])
    }

    func testARecentColourUsedAgainMovesToTheFrontRatherThanAppearingTwice() {
        let panel = ColorPanelState()
        panel.recordPainted(Color(hex: "FF0000")!)
        panel.recordPainted(Color(hex: "00FF00")!)
        panel.recordPainted(Color(hex: "FF0000")!)
        XCTAssertEqual(panel.recentColors.map(\.hex), ["FF0000", "00FF00"], "A re-used colour must not appear twice")
    }

    func testRecentColoursAreCappedAtTheirCapacity() {
        let panel = ColorPanelState()
        for i in 0..<(ColorPanelState.recentCapacity + 5) {
            panel.recordPainted(Color(hex: String(format: "%06X", i)) ?? .black)
        }
        XCTAssertEqual(panel.recentColors.count, ColorPanelState.recentCapacity, "Never past its capacity")
        XCTAssertEqual(panel.recentColors.first?.hex, String(format: "%06X", ColorPanelState.recentCapacity + 4))
    }

    /// **A tick of the brush's colour is the swatches' and not the editor's** — TODO (179). The colour is
    /// published on its own object (`BrushColorState`), so sixty ticks of the picker — written the way the
    /// panel writes them, through `activeEditColor` — send nothing on `CanvasManager`, which every view in the
    /// editor observes, and one each on the brush colour's object, which the swatches observe. The stroke
    /// the brush draws next is in the colour the last tick left.
    @MainActor
    func testABrushColourTickIsTheSwatchesAndNotTheEditors() {
        let manager = CanvasFixture.manager(layerCount: 1)
        var editor = 0, swatches = 0
        let watchEditor = manager.objectWillChange.sink { editor += 1 }
        let watchSwatches = manager.brushColorState.objectWillChange.sink { swatches += 1 }
        for tick in 0..<60 {
            manager.activeEditColor = Color(hue: Double(tick) / 60, saturation: 0.8, brightness: 0.9)
        }
        watchEditor.cancel()
        watchSwatches.cancel()
        XCTAssertEqual(editor, 0, "60 ticks of the brush's colour raised \(editor) passes over the editor")
        XCTAssertEqual(swatches, 60, "and the swatches heard every one")
        XCTAssertEqual(manager.brushColor.hexString, Color(hue: 59.0 / 60, saturation: 0.8, brightness: 0.9).hexString,
                       "the brush paints in the last tick's colour")
    }

    /// **Only what was painted with is recent**, and only in the scene it was painted in: a stroke's
    /// lift records the brush colour, an eraser's lift records nothing.
    @MainActor
    func testAStrokesLiftRecordsItsColourInItsOwnSceneAndAnErasersRecordsNothing() {
        let scene = CanvasFixture.manager(layerCount: 1)
        let other = CanvasFixture.manager(layerCount: 1)
        scene.brushColor = Color(hex: "ABCDEF")!
        scene.strokeEnded(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(scene.colorPanel.recentColors.map(\.hex), ["ABCDEF"])
        XCTAssertTrue(other.colorPanel.recentColors.isEmpty, "Another scene's Recent strip is its own")

        scene.selectedTool = .eraser
        scene.brushColor = Color(hex: "123456")!
        scene.strokeEnded(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(scene.colorPanel.recentColors.map(\.hex), ["ABCDEF"], "The eraser painted nothing")

        scene.colorPanel.clearRecent()
        XCTAssertTrue(scene.colorPanel.recentColors.isEmpty)
    }

    // MARK: - The palettes library (app-wide)

    private func isolatedSettings() throws -> AppSettings {
        AppSettings(defaults: try isolatedDefaults())
    }

    func testAddPaletteGivesItAUniqueName() throws {
        let store = PaletteStore(settings: try isolatedSettings())
        let before = store.palettes.count
        let added = try XCTUnwrap(store.addPalette())
        XCTAssertEqual(store.palettes.count, before + 1)
        let second = try XCTUnwrap(store.addPalette(name: added.name))
        XCTAssertNotEqual(second.name, added.name, "A duplicate name must be disambiguated")
    }

    func testRenamePaletteTrimsAndIgnoresAnEmptyName() throws {
        let store = PaletteStore(settings: try isolatedSettings())
        let palette = try XCTUnwrap(store.addPalette(name: "Mine"))
        store.renamePalette(palette, to: "  Renamed  ")
        XCTAssertEqual(store.palettes.first(where: { $0.id == palette.id })?.name, "Renamed")

        store.renamePalette(palette, to: "   ")
        XCTAssertEqual(store.palettes.first(where: { $0.id == palette.id })?.name, "Renamed",
                       "An all-whitespace name must not blank out the palette")
    }

    /// Deleting answers the neighbour that takes its place — what the scene that had it selected shows
    /// next — and the last palette cannot be deleted.
    func testDeletePaletteAnswersItsNeighbourAndRefusesTheLastOne() throws {
        let store = PaletteStore(settings: try isolatedSettings())
        let a = try XCTUnwrap(store.addPalette(name: "A"))
        let b = try XCTUnwrap(store.addPalette(name: "B"))
        let countBeforeDeletes = store.palettes.count

        XCTAssertEqual(store.deletePalette(a)?.id, b.id, "The neighbour takes its place")
        XCTAssertEqual(store.palettes.count, countBeforeDeletes - 1, "Deleting removes exactly it")

        while store.palettes.count > 1 {
            store.deletePalette(store.palettes[0])
        }
        let last = store.palettes[0]
        XCTAssertNil(store.deletePalette(last), "The last remaining palette must refuse to be deleted")
        XCTAssertEqual(store.palettes.map(\.id), [last.id])
    }

    func testAddAndRemoveColorMutateOnlyTheNamedPalette() throws {
        let store = PaletteStore(settings: try isolatedSettings())
        let a = try XCTUnwrap(store.addPalette(name: "A"))
        let b = try XCTUnwrap(store.addPalette(name: "B"))
        store.addColor(.red, to: a)
        XCTAssertEqual(store.palettes.first(where: { $0.id == a.id })?.colors.count, 1)
        XCTAssertEqual(store.palettes.first(where: { $0.id == b.id })?.colors.count, 0,
                       "Adding to A must not touch B")

        let swatch = store.palettes.first(where: { $0.id == a.id })!.colors[0]
        store.removeColor(swatch, from: a)
        XCTAssertEqual(store.palettes.first(where: { $0.id == a.id })?.colors.count, 0)
    }

    /// **A palette made in one scene is in every other** — the library is app-wide — and it outlives a
    /// launch with its swatches.
    func testPalettesOutliveALaunch() throws {
        let settings = try isolatedSettings()
        let first = PaletteStore(settings: settings)
        let mine = try XCTUnwrap(first.addPalette(name: "Mine"))
        first.addColor(.blue, to: mine)

        let second = PaletteStore(settings: settings)
        XCTAssertEqual(second.palettes.first(where: { $0.id == mine.id })?.colors.count, 1,
                       "A palette's swatches should persist")
    }

    /// A first launch seeds the built-in presets **and stores them**, so the id a scene's selection
    /// names is the same id on the next launch. They used to be minted afresh every launch until the
    /// artist first edited one, so a selection of an untouched preset could never survive a relaunch.
    ///
    /// The store is the operand, not a second `PaletteStore`: within one process the presets are one
    /// `static let`, so a second store agrees with the first whether or not anything was stored.
    func testAFirstLaunchSeedsThePresetsWithIdsThatOutliveIt() throws {
        let settings = try isolatedSettings()
        let first = PaletteStore(settings: settings)
        XCTAssertEqual(first.palettes.map(\.name), PaletteStore.defaultPresets.map(\.name))
        XCTAssertTrue(first.palettes.allSatisfy(\.isBuiltIn))
        guard case .palettes(let stored) = settings.readPalettes() else {
            return XCTFail("The seeded presets are stored on the first launch, so the next one reads their ids")
        }
        XCTAssertEqual(stored.map(\.id), first.palettes.map(\.id), "The ids the next launch reads")
    }

    /// A scene's selection is resolved against the library: an id the library has is that palette, and
    /// nil — or an id deleted from the library in another scene — is the first.
    func testASelectionResolvesToItsPaletteOrToTheFirst() throws {
        let store = PaletteStore(settings: try isolatedSettings())
        let mine = try XCTUnwrap(store.addPalette(name: "Mine"))
        XCTAssertEqual(store.palette(selectedBy: mine.id)?.id, mine.id)
        XCTAssertEqual(store.palette(selectedBy: nil)?.id, store.palettes.first?.id)
        XCTAssertEqual(store.palette(selectedBy: UUID())?.id, store.palettes.first?.id)
    }

    /// **The artist's palettes are never read as empty and written over.** A stored library this build
    /// cannot read shows none, takes no edit, and is still stored exactly as it was.
    func testAnUnreadableLibraryIsReportedAndLeftAsItWas() throws {
        let defaults = try isolatedDefaults()
        let garbage = Data("not palettes".utf8)
        defaults.set(garbage, forKey: AppSettings.Key.palettes)
        let store = PaletteStore(settings: AppSettings(defaults: defaults))
        XCTAssertNotNil(store.unreadable, "Said, not hidden")
        XCTAssertTrue(store.palettes.isEmpty, "Nothing invented in its place")
        XCTAssertNil(store.addPalette(), "Nothing can be added over it")
        XCTAssertEqual(defaults.data(forKey: AppSettings.Key.palettes), garbage, "The stored library is untouched")
    }
}
