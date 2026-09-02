import SwiftUI

@main
struct PaintApp: App {
    init() {
        // RENDER.md §2.11: **the bake is dumped between launches by default.** Synchronous and
        // before anything else, because the alternative is a race with the first document's own
        // baker — the process-lifetime bake key is built from object identities and in-memory
        // version counters (`RasterLayerTexture.version`, `VectorCanvas.version`) which restart at
        // every open, so a file left from the previous launch is a digest whose meaning is gone.
        // It is one `removeItem` on a Caches directory, not a walk.
        FrameBakeStore.purgeEverything()
        // Launch-time safety pass (off the main thread): snapshot every project if the app binary
        // changed (update/dev redeploy), auto-repair any damaged project package from its backups,
        // purge expired trash. The gallery re-lists when it finishes.
        Task.detached(priority: .utility) {
            ProjectBackupManager.runStartupMaintenance()
            await MainActor.run {
                NotificationCenter.default.post(name: .projectBackupMaintenanceDidFinish, object: nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
