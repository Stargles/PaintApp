import XCTest

/// TODO (152): the New Canvas sheet's size presets are one list of data, and what the sheet draws is
/// that list held to what the device can open.
///
/// `CanvasSizePickerUITests` owns the part a model cannot say — that the buttons are *drawn*, that a
/// tap fills the fields, that Cancel leaves. This owns the list itself: that it has no repeats, that
/// it carries every size the owner named, and that the ceiling filter drops exactly the sizes over
/// the ceiling and nothing else.
final class CanvasSizePresetLogicTests: XCTestCase {

    private func preset(_ width: Int, _ height: Int) -> CanvasSizePreset? {
        CanvasSizePreset.all.first { $0.width == width && $0.height == height }
    }

    // MARK: - The list

    func testNoSizeIsListedTwice() {
        let ids = CanvasSizePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a size appearing twice is two buttons that do one thing: \(ids)")
    }

    func testTheListCarriesEverySizeTheOwnerNamed() {
        // 2048×1024 is the owner's working size (PERFORMANCE.md §1); "1920, 1080p" is 1920×1080; the
        // rest of the brief's list is the video set, the squares and the vertical-video pair.
        for (width, height) in [(2048, 1024), (1920, 1080), (1280, 720), (3840, 2160),
                                (1024, 1024), (2048, 2048), (1080, 1920)] {
            XCTAssertNotNil(preset(width, height), "\(width) × \(height) should be a preset")
        }
    }

    func testTheOpeningSizeIsOneOfThePresets() {
        XCTAssertTrue(CanvasSizePreset.all.contains(CanvasSizePreset.initial),
                      "the sheet opens on a member of the list, not on a literal beside it")
    }

    func testEverySizeIsOneTheFormatCanHold() {
        let ceiling = Int(CanvasManager.formatExtentCeiling)
        for preset in CanvasSizePreset.all {
            XCTAssertTrue(preset.fits(withinExtent: ceiling), "\(preset.dimensions) is past the format's own ceiling")
            XCTAssertGreaterThan(min(preset.width, preset.height), 0, "\(preset.dimensions) has no area")
        }
    }

    // MARK: - What a device is offered

    /// The ceiling is on **each side**, which is what the typed fields check — so a wide size over it
    /// goes whichever side is the long one, and a tall one likewise.
    func testASizeIsDroppedWhenEitherSideIsOverTheCeiling() {
        let wide = CanvasSizePreset(width: 3000, height: 1000, name: "wide")
        let tall = CanvasSizePreset(width: 1000, height: 3000, name: "tall")
        XCTAssertFalse(wide.fits(withinExtent: 2999))
        XCTAssertFalse(tall.fits(withinExtent: 2999))
        XCTAssertTrue(wide.fits(withinExtent: 3000), "a side equal to the ceiling is allowed, as it is in the field")
        XCTAssertTrue(tall.fits(withinExtent: 3000))
    }

    func testAnUnderpoweredDeviceIsNotOfferedFourK() {
        let offered = CanvasSizePreset.offered(withinExtent: 3000)
        XCTAssertNil(offered.first { $0.width == 3840 && $0.height == 2160 },
                     "4K is 3840 wide, so a device whose canvas ceiling is 3000 cannot open it")
        XCTAssertNotNil(offered.first { $0.width == 2560 && $0.height == 1440 }, "and 1440p, at 2560, it can")
        XCTAssertEqual(offered, CanvasSizePreset.all.filter { $0.width <= 3000 && $0.height <= 3000 },
                       "the filter drops what is over the ceiling and keeps the rest in list order")
    }

    /// The device this tier runs as is the reference iPad (6000 — `CanvasGeometryLogicTests` pins it),
    /// which is the device the owner draws on: every preset is offered there, 4K included.
    func testTheReferenceIPadIsOfferedEveryPreset() {
        let ceiling = Int(CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: CanvasManager.referenceDeviceMemoryBudgetBytes))
        XCTAssertEqual(CanvasSizePreset.offered(withinExtent: ceiling), CanvasSizePreset.all)
    }
}
