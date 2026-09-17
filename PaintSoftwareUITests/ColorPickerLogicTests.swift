import XCTest
import SwiftUI

/// TODO (73)'s colour picker overhaul — the model, headless: the ring/disc/triangle point<->colour
/// maths in `ColorMath` (no UIKit, no simulator gestures needed to check a round trip), then
/// `ColorHistoryStore` and `PaletteStore` — dedupe/cap/persistence and CRUD/default/persistence —
/// and one cold-start "migration" test. `ColorPickerUITests` covers reachability (driving each tab
/// from a fresh document); this file covers whether the arithmetic and the two stores are correct.
final class ColorPickerLogicTests: XCTestCase {

    // MARK: - Isolated UserDefaults (same pattern `EditorStateLogicTests` uses)

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "color-picker-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: - Hue ring

    func testHueRingAngleRoundTripsThroughAllFourCardinalHues() {
        // 0 at top, clockwise: 0=top, 0.25=right, 0.5=bottom, 0.75=left — the convention
        // `AngularGradient`'s own default start/direction already use.
        let top = ColorMath.hueRingAngle(forHue: 0)
        XCTAssertEqual(ColorMath.hueForRingTouch(dx: 0, dy: -1), 0, accuracy: 0.0001, "Straight up is hue 0")
        XCTAssertEqual(top, 0, accuracy: 0.0001)

        XCTAssertEqual(ColorMath.hueForRingTouch(dx: 1, dy: 0), 0.25, accuracy: 0.0001, "Right is a quarter turn clockwise")
        XCTAssertEqual(ColorMath.hueForRingTouch(dx: 0, dy: 1), 0.5, accuracy: 0.0001, "Down is halfway round")
        XCTAssertEqual(ColorMath.hueForRingTouch(dx: -1, dy: 0), 0.75, accuracy: 0.0001, "Left is three-quarters round")
    }

    func testHueRingAngleRoundTripsOverManyHues() {
        for i in 0..<37 {
            let hue = Double(i) / 36
            let angle = ColorMath.hueRingAngle(forHue: hue)
            let dx = sin(angle), dy = -cos(angle)
            let recovered = ColorMath.hueForRingTouch(dx: dx, dy: dy)
            // Hue 1.0 and hue 0.0 are the same point on the ring; compare the wrapped distance.
            let delta = min(abs(recovered - hue), abs(recovered - hue + 1), abs(recovered - hue - 1))
            XCTAssertLessThan(delta, 0.0005, "hue \(hue) should round-trip through the ring's angle, got \(recovered)")
        }
    }

    // MARK: - Square <-> disc

    func testSquareToDiscRoundTripsForAGridOfPoints() {
        let samples: [(Double, Double)] = [
            (0, 0), (1, 0), (-1, 0), (0, 1), (0, -1),
            (1, 1), (1, -1), (-1, 1), (-1, -1),
            (0.5, 0.25), (-0.3, 0.9), (0.9, -0.9), (0.1, 0.6)
        ]
        for (u, v) in samples {
            let disc = ColorMath.squareToDisc(u: u, v: v)
            XCTAssertLessThanOrEqual(disc.x * disc.x + disc.y * disc.y, 1.0001,
                                     "square (\(u),\(v)) must map inside the unit disc, got \(disc)")
            let back = ColorMath.discToSquare(x: disc.x, y: disc.y)
            XCTAssertEqual(back.u, u, accuracy: 0.0005, "u should round-trip for (\(u),\(v))")
            XCTAssertEqual(back.v, v, accuracy: 0.0005, "v should round-trip for (\(u),\(v))")
        }
    }

    func testDiscToSquareRoundTripsForAGridOfPoints() {
        let samples: [(Double, Double)] = [
            (0, 0), (0.7071, 0.7071), (-0.7071, 0.7071), (0.7071, -0.7071), (-0.7071, -0.7071),
            (1, 0), (-1, 0), (0, 1), (0, -1), (0.3, 0.1), (-0.5, -0.2)
        ]
        for (x, y) in samples {
            let square = ColorMath.discToSquare(x: x, y: y)
            let back = ColorMath.squareToDisc(u: square.u, v: square.v)
            XCTAssertEqual(back.x, x, accuracy: 0.0005, "x should round-trip for (\(x),\(y))")
            XCTAssertEqual(back.y, y, accuracy: 0.0005, "y should round-trip for (\(x),\(y))")
        }
    }

    /// The corner (full saturation *and* full brightness together) is the case the disc's remap
    /// exists for: it must land exactly on the disc's edge, not be silently unreachable.
    func testTheSquaresCornerLandsExactlyOnTheDiscsEdge() {
        let disc = ColorMath.squareToDisc(u: 1, v: -1)
        let radius = (disc.x * disc.x + disc.y * disc.y).squareRoot()
        XCTAssertEqual(radius, 1, accuracy: 0.0005, "A square corner must reach the disc's boundary")
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

    func testTriangleContainsItsOwnCentreAndVerticesButNotFarOutsidePoints() {
        XCTAssertTrue(ColorMath.triangleContains(x: 0, y: 0), "The centroid area must read as inside")
        XCTAssertTrue(ColorMath.triangleContains(x: ColorMath.trianglePureHueVertex.x,
                                                  y: ColorMath.trianglePureHueVertex.y))
        XCTAssertFalse(ColorMath.triangleContains(x: 0, y: -5), "Far outside the triangle must read as outside")
        XCTAssertFalse(ColorMath.triangleContains(x: 5, y: 5))
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

    // MARK: - ColorHistoryStore

    func testHistoryRecordsNewestFirst() throws {
        let store = ColorHistoryStore(defaults: try isolatedDefaults())
        store.record(Color(hex: "FF0000")!)
        store.record(Color(hex: "00FF00")!)
        store.record(Color(hex: "0000FF")!)
        XCTAssertEqual(store.colors.map(\.hex), ["0000FF", "00FF00", "FF0000"])
    }

    func testHistoryDedupesByMovingTheExistingEntryToTheFront() throws {
        let store = ColorHistoryStore(defaults: try isolatedDefaults())
        store.record(Color(hex: "FF0000")!)
        store.record(Color(hex: "00FF00")!)
        store.record(Color(hex: "FF0000")!) // re-used, should move to the front, not duplicate
        XCTAssertEqual(store.colors.map(\.hex), ["FF0000", "00FF00"], "A re-used colour must not appear twice")
    }

    func testHistoryIsCappedAtItsCapacity() throws {
        let store = ColorHistoryStore(defaults: try isolatedDefaults())
        for i in 0..<(ColorHistoryStore.capacity + 5) {
            let hex = String(format: "%06X", i)
            store.record(Color(hex: hex) ?? .black)
        }
        XCTAssertEqual(store.colors.count, ColorHistoryStore.capacity, "History must never grow past its capacity")
        // Newest-first: the most recently recorded capacity+4 colour should still be at the front.
        XCTAssertEqual(store.colors.first?.hex, String(format: "%06X", ColorHistoryStore.capacity + 4))
    }

    func testHistoryPersistsAcrossInstancesAndClearErasesIt() throws {
        let defaults = try isolatedDefaults()
        let first = ColorHistoryStore(defaults: defaults)
        first.record(Color(hex: "ABCDEF")!)

        let second = ColorHistoryStore(defaults: defaults)
        XCTAssertEqual(second.colors.map(\.hex), ["ABCDEF"], "History should persist across instances, like PaletteStore's palettes")

        second.clear()
        XCTAssertTrue(second.colors.isEmpty)
        let third = ColorHistoryStore(defaults: defaults)
        XCTAssertTrue(third.colors.isEmpty, "Clear must persist too")
    }

    // MARK: - PaletteStore CRUD + default + persistence

    func testAddPaletteSelectsItAndGivesItAUniqueName() throws {
        let store = PaletteStore(defaults: try isolatedDefaults())
        let before = store.palettes.count
        let added = store.addPalette()
        XCTAssertEqual(store.palettes.count, before + 1)
        XCTAssertEqual(store.selectedPaletteID, added.id, "Adding a palette should make it the default/selected one")

        let second = store.addPalette(name: added.name)
        XCTAssertNotEqual(second.name, added.name, "A duplicate name must be disambiguated")
    }

    func testRenamePaletteTrimsAndIgnoresAnEmptyName() throws {
        let store = PaletteStore(defaults: try isolatedDefaults())
        let palette = store.addPalette(name: "Mine")
        store.renamePalette(palette, to: "  Renamed  ")
        XCTAssertEqual(store.palettes.first(where: { $0.id == palette.id })?.name, "Renamed")

        store.renamePalette(palette, to: "   ")
        XCTAssertEqual(store.palettes.first(where: { $0.id == palette.id })?.name, "Renamed",
                       "An all-whitespace name must not blank out the palette")
    }

    func testDeletePaletteRefusesToRemoveTheLastOneAndRepointsSelection() throws {
        let store = PaletteStore(defaults: try isolatedDefaults())
        // `PaletteStore` seeds the built-in presets on a cold start, so start from a known count
        // (two of our own) rather than assuming the store is empty.
        let a = store.addPalette(name: "A")
        let b = store.addPalette(name: "B")
        let countBeforeDeletes = store.palettes.count
        store.select(a)

        store.deletePalette(a)
        XCTAssertEqual(store.palettes.count, countBeforeDeletes - 1, "Deleting the selected palette should remove exactly it")
        XCTAssertEqual(store.selectedPaletteID, b.id, "Selection should move to a neighbor")

        // Delete every remaining palette down to one, to reach the refusal case for real rather
        // than assuming the store started empty.
        while store.palettes.count > 1 {
            store.deletePalette(store.palettes[0])
        }
        let last = store.palettes[0]
        let countAtOne = store.palettes.count
        store.deletePalette(last)
        XCTAssertEqual(store.palettes.count, countAtOne, "The last remaining palette must refuse to be deleted")
        XCTAssertEqual(store.palettes.first?.id, last.id)
    }

    func testAddAndRemoveColorMutateOnlyTheNamedPalette() throws {
        let store = PaletteStore(defaults: try isolatedDefaults())
        let a = store.addPalette(name: "A")
        let b = store.addPalette(name: "B")
        store.addColor(.red, to: a)
        XCTAssertEqual(store.palettes.first(where: { $0.id == a.id })?.colors.count, 1)
        XCTAssertEqual(store.palettes.first(where: { $0.id == b.id })?.colors.count, 0,
                       "Adding to A must not touch B")

        let swatch = store.palettes.first(where: { $0.id == a.id })!.colors[0]
        store.removeColor(swatch, from: a)
        XCTAssertEqual(store.palettes.first(where: { $0.id == a.id })?.colors.count, 0)
    }

    func testPalettesAndSelectionPersistAcrossInstances() throws {
        let defaults = try isolatedDefaults()
        let first = PaletteStore(defaults: defaults)
        let mine = first.addPalette(name: "Mine")
        first.addColor(.blue, to: mine)

        let second = PaletteStore(defaults: defaults)
        XCTAssertEqual(second.selectedPaletteID, mine.id, "The selected/default palette should persist")
        XCTAssertEqual(second.palettes.first(where: { $0.id == mine.id })?.colors.count, 1,
                       "A palette's swatches should persist")
    }

    // MARK: - Cold start ("the migration")

    /// TODO (73) asked for palette data to be migrated into this model on first read. There turned
    /// out to be nothing *to* migrate — `PaletteStore` already was the app-wide, `UserDefaults`-JSON
    /// store this feature needs (grepped: no other palette/history storage exists anywhere in the
    /// app), so the only real "migration" is this: a device that has never seen (73) — no
    /// `paletteStore.palettes.v1`/`colorHistoryStore.colors.v1` keys at all — must still boot into a
    /// valid, usable state rather than an empty or crashing picker.
    func testAFreshInstallWithNoPriorPickerDataBootstrapsValidDefaults() throws {
        let defaults = try isolatedDefaults()

        let palettes = PaletteStore(defaults: defaults)
        XCTAssertEqual(palettes.palettes.count, PaletteStore.defaultPresets.count,
                       "A cold start should seed the built-in presets")
        XCTAssertNotNil(palettes.selectedPalette, "A cold start must have something selected/default")
        XCTAssertTrue(palettes.palettes.allSatisfy(\.isBuiltIn))

        let history = ColorHistoryStore(defaults: defaults)
        XCTAssertTrue(history.colors.isEmpty, "A cold start's history is empty, not nil/crashing")
    }
}
