import XCTest

/// The canvas's repair counter: how many times `replaceStrandedRecognizers` has caught a freeze,
/// kept across launches and shown in the Settings menu and in every flight file's header.
///
/// Every defaults store here is a suite of the test's own. Nothing reads `UserDefaults.standard`, so
/// no test in this file can leave a count behind for the app's own row, or for a flight header in a
/// later test, to find.
final class CanvasRepairCountLogicTests: XCTestCase {

    private func isolatedDefaults() throws -> (defaults: UserDefaults, suite: String) {
        let suite = "canvas-repair-count-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (defaults, suite)
    }

    func testAnAppThatHasNeverRepairedAnythingCountsZero() throws {
        XCTAssertEqual(CanvasRepairCount.current(in: try isolatedDefaults().defaults), 0)
    }

    /// Each repair is one, the new total is what `record` answers, and `current` reads it back.
    func testEveryRepairIsCountedOnce() throws {
        let (defaults, _) = try isolatedDefaults()
        XCTAssertEqual(CanvasRepairCount.record(in: defaults), 1)
        XCTAssertEqual(CanvasRepairCount.record(in: defaults), 2)
        XCTAssertEqual(CanvasRepairCount.record(in: defaults), 3)
        XCTAssertEqual(CanvasRepairCount.current(in: defaults), 3)
    }

    /// **The count is the app's, not the process's.** A second `UserDefaults` on the same suite is what
    /// a relaunch reads: it must find the count in the store, which a value held in memory (a static,
    /// an `ObservableObject`) would not leave there.
    func testTheCountIsStillThereAfterALaunch() throws {
        let (defaults, suite) = try isolatedDefaults()
        for _ in 0..<5 { CanvasRepairCount.record(in: defaults) }
        defaults.synchronize()

        let afterRelaunch = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(CanvasRepairCount.current(in: afterRelaunch), 5)
        XCTAssertEqual(CanvasRepairCount.record(in: afterRelaunch), 6, "and the next repair carries on from it")
    }

    /// The Settings row reads the count with `@AppStorage(CanvasRepairCount.defaultsKey)`, so the key
    /// is what ties the number on screen to the number counted.
    func testTheCountLivesUnderTheKeyTheMenuRowReads() throws {
        let (defaults, _) = try isolatedDefaults()
        CanvasRepairCount.record(in: defaults)
        CanvasRepairCount.record(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: CanvasRepairCount.defaultsKey), 2)
    }

    func testTheMenuRowSaysWhatItCounts() {
        XCTAssertEqual(CanvasRepairCount.title(0), "Canvas freezes caught: 0")
        XCTAssertEqual(CanvasRepairCount.title(12), "Canvas freezes caught: 12")
    }
}
