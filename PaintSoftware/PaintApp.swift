import SwiftUI

@main
struct PaintApp: App {
    @StateObject private var geometryRepair = PointGeometryRepairStartup()
    init() {
        // Scribble is refused for every text input the app ever shows, by the hook that has to be in
        // place before the first one is created. See `ScribbleRefusal`.
        ScribbleRefusal.install()
        // RENDER.md §2.11: **the bake is dumped between launches by default.** Synchronous and
        // before anything else, because the alternative is a race with the first document's own
        // baker — the process-lifetime bake key is built from object identities and in-memory
        // version counters (`RasterLayerTexture.version`, `VectorCanvas.version`) which restart at
        // every open, so a file left from the previous launch is a digest whose meaning is gone.
        // It is one `removeItem` on a Caches directory, not a walk.
        FrameBakeStore.purgeEverything()
        // Inert unless an XCUITest passed `-uiTestTextureBudgetBytes`, and simulator-only. First,
        // because every memo in the app reads this number and one of them is filled before the first
        // frame is drawn. See `UITestSeeds` for why a simulator cannot otherwise reproduce the
        // owner's device at all on this axis.
        UITestSeeds.applyTextureBudgetOverrideIfRequested()
        // Inert unless an XCUITest passed `-uiTestSlowBakeMillis`, and simulator-only; before the
        // first document's baker exists, which reads it at every mint.
        UITestSeeds.applyBakeDelayIfRequested()
        UITestSeeds.applyWindowDrawDelayIfRequested()
        // TODO (36): resolve the artist's chosen projects folder **before** anything reads
        // `ProjectBackupManager.documentsDirectory`. Synchronous and on the main thread on purpose —
        // it is one bookmark resolve, and every line below this one asks where the library is. The
        // maintenance pass in particular would otherwise snapshot and repair inside the app
        // container while the artist's real library sat untouched in Files.
        ProjectLocation.resolveOnLaunch()
        AppSettings.standard.forgetIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch geometryRepair.phase {
                case .preparing:
                    VStack(spacing: 16) {
                        ProgressView()
                            .accessibilityIdentifier("startup.progress")
                        Text("Preparing saved scenes")
                            .font(.headline)
                            .accessibilityIdentifier("startup.preparing")
                        Text("Your scenes are being checked and kept safe. Please keep PaintApp open.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                case .failed(let reason):
                    ContentUnavailableView("Saved scenes need repair", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("Saved scenes were kept for recovery. Please reopen the app to try again.\n\n" + reason))
                        .accessibilityIdentifier("startup.failed")
                case .ready:
                    ContentView()
                }
            }
            .task { await geometryRepair.start() }
        }
    }
}
