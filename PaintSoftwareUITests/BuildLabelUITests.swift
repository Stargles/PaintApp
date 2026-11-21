import XCTest

/// The gallery names the build it is running. `tools/stamp-build.sh` stamps this test bundle with the
/// same commit it stamps the app with, in the same build, so the two must agree.
final class BuildLabelUITests: PaintUITestCase {
    func testGalleryShowsTheCommitThisBinaryWasBuiltFrom() throws {
        let stamped = try XCTUnwrap(Bundle(for: Self.self).object(forInfoDictionaryKey: "PaintBuildCommit") as? String,
                                    "the UI test bundle was not stamped by tools/stamp-build.sh")
        XCTAssertNotEqual(stamped, "unknown", "git could not name the commit at build time")
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        app.launch()
        let label = app.staticTexts["galleryBuildLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 20), "the gallery's build label is missing")
        XCTAssertTrue(label.label.hasPrefix("Build \(stamped) · "),
                      "gallery says \"\(label.label)\" but this build was stamped \(stamped)")
    }
}
