import XCTest

/// **TODO (176)'s one global store** — `AppSettings`, every value the app keeps for itself rather than
/// for a scene, and `AppSettingsKeeper`, which carries the two of them that live on a `CanvasManager`.
///
/// Every store here is a suite of the test's own, so nothing a test sets reaches the app's own settings,
/// or a later test. A second `AppSettings` over the same suite is what a relaunch reads: a value must be
/// found in the store, which a value held in memory would not leave there.
final class AppSettingsLogicTests: XCTestCase {

    private func isolatedSettings() throws -> (settings: AppSettings, suite: String) {
        let suite = "app-settings-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (AppSettings(defaults: defaults), suite)
    }

    private func relaunched(_ suite: String) throws -> AppSettings {
        AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    // MARK: - A fresh install

    func testAFreshInstallReadsEveryValueAtItsDefault() throws {
        let settings = try isolatedSettings().settings
        XCTAssertFalse(settings.pencilOnlyDrawing, "Fingers can paint until the artist says otherwise")
        XCTAssertEqual(settings.renderResolution, .full)
        XCTAssertNil(settings.lastStreamEndpoint)
        XCTAssertNil(settings.projectsFolderBookmark)
        XCTAssertNil(settings.projectsFolderName)
        XCTAssertFalse(settings.storageInvitationDismissed)
        XCTAssertEqual(settings.galleryFolder, [], "The gallery opens at the top of the tree")
        XCTAssertEqual(settings.canvasRepairCount, 0)
        XCTAssertNil(settings.lastAppSignature)
    }

    // MARK: - Every value outlives a launch

    func testEveryValueIsStillThereAfterALaunch() throws {
        let (settings, suite) = try isolatedSettings()
        settings.pencilOnlyDrawing = true
        settings.renderResolution = .half
        settings.lastStreamEndpoint = StreamEndpoint(host: "desktop-cbr0fl6", port: 47302)
        settings.projectsFolderBookmark = Data([1, 2, 3])
        settings.projectsFolderName = "Animation"
        settings.storageInvitationDismissed = true
        settings.galleryFolder = ["Scene 3", "Shot 1"]
        settings.lastAppSignature = "1.0|2|3"

        let next = try relaunched(suite)
        XCTAssertTrue(next.pencilOnlyDrawing)
        XCTAssertEqual(next.renderResolution, .half)
        XCTAssertEqual(next.lastStreamEndpoint, StreamEndpoint(host: "desktop-cbr0fl6", port: 47302))
        XCTAssertEqual(next.projectsFolderBookmark, Data([1, 2, 3]))
        XCTAssertEqual(next.projectsFolderName, "Animation")
        XCTAssertTrue(next.storageInvitationDismissed)
        XCTAssertEqual(next.galleryFolder, ["Scene 3", "Shot 1"])
        XCTAssertEqual(next.lastAppSignature, "1.0|2|3")
    }

    /// The keys are the ones each value was saved under before (176), so an existing install's
    /// settings are where this store looks for them with nothing moved.
    func testTheKeysAreTheOnesAnExistingInstallHolds() throws {
        let (settings, suite) = try isolatedSettings()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "paintapp.pencilOnlyDrawing")
        defaults.set("threeQuarter", forKey: "paintapp.renderResolution")
        defaults.set("laptop", forKey: "streamScreen.lastHost")
        defaults.set(47301, forKey: "streamScreen.lastPort")
        defaults.set(Data([9]), forKey: "PaintApp.projectLocation.bookmark")
        defaults.set("Files", forKey: "PaintApp.projectLocation.displayName")
        defaults.set(true, forKey: "PaintApp.gallery.storageInvitationDismissed")
        defaults.set(4, forKey: "paintapp.canvasFreezesCaught")
        defaults.set("sig", forKey: "PaintApp.projectBackup.lastAppSignature")

        XCTAssertTrue(settings.pencilOnlyDrawing)
        XCTAssertEqual(settings.renderResolution, .threeQuarter)
        XCTAssertEqual(settings.lastStreamEndpoint, StreamEndpoint(host: "laptop", port: 47301))
        XCTAssertEqual(settings.projectsFolderBookmark, Data([9]))
        XCTAssertEqual(settings.projectsFolderName, "Files")
        XCTAssertTrue(settings.storageInvitationDismissed)
        XCTAssertEqual(settings.canvasRepairCount, 4)
        XCTAssertEqual(settings.lastAppSignature, "sig")
    }

    /// A render knob value from a newer build shows as Full **and is not written over** — reading it is
    /// never a reason to lose it.
    func testAnUnknownRenderResolutionShowsFullAndStaysStored() throws {
        let (settings, suite) = try isolatedSettings()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("eighth", forKey: AppSettings.Key.renderResolution)
        XCTAssertEqual(settings.renderResolution, .full)
        XCTAssertEqual(defaults.string(forKey: AppSettings.Key.renderResolution), "eighth",
                       "Reading the knob left the value it could not read where it was")
    }

    func testAStreamEndpointIsForgottenWhole() throws {
        let settings = try isolatedSettings().settings
        settings.lastStreamEndpoint = StreamEndpoint(host: "laptop", port: 47301)
        settings.lastStreamEndpoint = nil
        XCTAssertNil(settings.lastStreamEndpoint)
        XCTAssertNil(settings.defaults.object(forKey: AppSettings.Key.lastStreamPort), "No port is left without its host")
    }

    // MARK: - The canvas repair count

    /// Each repair is one, the new total is what `recordCanvasRepair` answers, and the count reads it
    /// back — after a launch too, so a build's repair rate can be read off the iPad.
    func testEveryCanvasRepairIsCountedOnceAndOutlivesALaunch() throws {
        let (settings, suite) = try isolatedSettings()
        XCTAssertEqual(settings.recordCanvasRepair(), 1)
        XCTAssertEqual(settings.recordCanvasRepair(), 2)
        XCTAssertEqual(settings.recordCanvasRepair(), 3)
        XCTAssertEqual(settings.canvasRepairCount, 3)
        let next = try relaunched(suite)
        XCTAssertEqual(next.canvasRepairCount, 3)
        XCTAssertEqual(next.recordCanvasRepair(), 4, "and the next repair carries on from it")
    }

    /// The Settings row reads the count with `@AppStorage(AppSettings.Key.canvasRepairCount)`, so the
    /// key is what ties the number on screen to the number counted.
    func testTheRepairCountLivesUnderTheKeyTheMenuRowReads() throws {
        let settings = try isolatedSettings().settings
        settings.recordCanvasRepair()
        settings.recordCanvasRepair()
        XCTAssertEqual(settings.defaults.integer(forKey: AppSettings.Key.canvasRepairCount), 2)
    }

    func testTheRepairRowSaysWhatItCounts() {
        XCTAssertEqual(CanvasRepairCount.title(0), "Canvas freezes caught: 0")
        XCTAssertEqual(CanvasRepairCount.title(12), "Canvas freezes caught: 12")
    }

    // MARK: - Launch-argument hooks

    private func seeded() throws -> AppSettings {
        let settings = try isolatedSettings().settings
        settings.pencilOnlyDrawing = true
        settings.renderResolution = .half
        settings.lastStreamEndpoint = StreamEndpoint(host: "laptop", port: 47301)
        settings.galleryFolder = ["Scene 3"]
        settings.recordCanvasRepair()
        settings.projectsFolderBookmark = Data([1])
        settings.projectsFolderName = "Files"
        settings.storageInvitationDismissed = true
        settings.lastAppSignature = "sig"
        return settings
    }

    /// `-resetEditorPreferences` — every `launchIntoEditor` passes it — puts the artist's app-wide
    /// preferences back at a fresh install's, **Render Resolution among them**: CLAUDE.md's "A static
    /// that writes through to `UserDefaults` outlives the test that set it" was this knob, which had no
    /// reset of its own. Where the library lives is not a preference and is left alone.
    func testResetEditorPreferencesForgetsThePreferencesAndNotTheLibrary() throws {
        for argument in ["-resetEditorPreferences", "-resetGallery"] {
            let settings = try seeded()
            settings.forgetIfRequested(arguments: ["app", argument])
            XCTAssertFalse(settings.pencilOnlyDrawing, argument)
            XCTAssertEqual(settings.renderResolution, .full, argument)
            XCTAssertNil(settings.lastStreamEndpoint, argument)
            XCTAssertEqual(settings.galleryFolder, [], argument)
            XCTAssertEqual(settings.canvasRepairCount, 0, argument)
            XCTAssertEqual(settings.projectsFolderBookmark, Data([1]), "\(argument) leaves the library where it is")
            XCTAssertEqual(settings.projectsFolderName, "Files", argument)
            XCTAssertTrue(settings.storageInvitationDismissed, argument)
            XCTAssertEqual(settings.lastAppSignature, "sig", argument)
        }
    }

    func testAnOrdinaryLaunchForgetsNothing() throws {
        let settings = try seeded()
        settings.forgetIfRequested(arguments: ["app"])
        XCTAssertTrue(settings.pencilOnlyDrawing)
        XCTAssertEqual(settings.renderResolution, .half)
        XCTAssertEqual(settings.galleryFolder, ["Scene 3"])
        XCTAssertEqual(settings.canvasRepairCount, 1)
    }

    /// `-resetGallery`'s own half, which `ProjectBackupManager` runs beside the wipe of the library.
    func testForgettingTheLibraryLocationForgetsTheFolderAndTheWarning() throws {
        let settings = try seeded()
        settings.forgetLibraryLocation()
        XCTAssertNil(settings.projectsFolderBookmark)
        XCTAssertNil(settings.projectsFolderName)
        XCTAssertFalse(settings.storageInvitationDismissed)
        XCTAssertTrue(settings.pencilOnlyDrawing, "…and nothing that is not about the library")
    }

    // MARK: - The keeper

    /// A document entering the editor gets the saved values, and a change the artist makes is saved as
    /// it is made — not with the next document save, so an app swiped away keeps it.
    func testTheKeeperHandsTheSavedValuesToADocumentAndSavesEachChange() throws {
        let (settings, suite) = try isolatedSettings()
        settings.pencilOnlyDrawing = true
        settings.renderResolution = .threeQuarter
        let keeper = AppSettingsKeeper(settings: settings)
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertFalse(manager.pencilOnlyDrawing, "PREMISE: a manager nothing has handed them to is at the defaults")
        XCTAssertEqual(manager.renderResolution, .full, "PREMISE")

        keeper.follow(manager)
        XCTAssertTrue(manager.pencilOnlyDrawing)
        XCTAssertEqual(manager.renderResolution, .threeQuarter)

        manager.pencilOnlyDrawing = false
        manager.renderResolution = .half
        let next = try relaunched(suite)
        XCTAssertFalse(next.pencilOnlyDrawing, "Saved as it changed")
        XCTAssertEqual(next.renderResolution, .half)
    }

    /// The keeper follows one document at a time: the one the artist left can no longer write.
    func testTheKeeperLetsGoOfThePreviousDocument() throws {
        let settings = try isolatedSettings().settings
        let keeper = AppSettingsKeeper(settings: settings)
        let first = CanvasFixture.manager(layerCount: 1)
        keeper.follow(first)
        let second = CanvasFixture.manager(layerCount: 1)
        keeper.follow(second)
        first.renderResolution = .half
        XCTAssertEqual(settings.renderResolution, .full, "A document that has left the editor saves nothing")
        second.renderResolution = .threeQuarter
        XCTAssertEqual(settings.renderResolution, .threeQuarter)
    }

    /// Following a document writes nothing: a value never touched stays unsaved and keeps following its
    /// default, so a build that changes a default reaches everyone who had not chosen otherwise.
    func testFollowingADocumentSavesNothingTheArtistDidNotChange() throws {
        let settings = try isolatedSettings().settings
        AppSettingsKeeper(settings: settings).follow(CanvasFixture.manager(layerCount: 1))
        XCTAssertNil(settings.defaults.object(forKey: AppSettings.Key.pencilOnlyDrawing))
        XCTAssertNil(settings.defaults.object(forKey: AppSettings.Key.renderResolution))
    }
}
