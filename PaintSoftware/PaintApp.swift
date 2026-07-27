import SwiftUI

@main
struct PaintApp: App {
    init() {
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
