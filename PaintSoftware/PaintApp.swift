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
        // TODO (36): resolve the artist's chosen projects folder **before** anything reads
        // `ProjectBackupManager.documentsDirectory`. Synchronous and on the main thread on purpose —
        // it is one bookmark resolve, and every line below this one asks where the library is. The
        // maintenance pass in particular would otherwise snapshot and repair inside the app
        // container while the artist's real library sat untouched in Files.
        ProjectLocation.resolveOnLaunch()
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
