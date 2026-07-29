import SwiftUI

enum AppScreen {
    case gallery
    case sizePicker
    case editor
}

struct ContentView: View {
    @State private var screen: AppScreen = .gallery
    @State private var canvasManager = CanvasManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch screen {
            case .gallery:
                GalleryView(onOpenProject: openProject, onCreateNew: startNewProject)
            case .sizePicker:
                CanvasSizePickerView(canvasManager: canvasManager, onCreated: { screen = .editor })
            case .editor:
                DrawingView(canvasManager: canvasManager, onOpenGallery: returnToGallery)
            }
        }
        #if os(iOS)
        .statusBar(hidden: true)
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                saveIfNeeded()
            }
        }
    }

    private func startNewProject() {
        canvasManager = CanvasManager()
        screen = .sizePicker
    }

    private func openProject(_ manager: CanvasManager) {
        canvasManager = manager
        screen = .editor
    }

    /// Shows the gallery only once the save has actually landed on disk. `GalleryView` lists projects
    /// from disk in a one-shot `onAppear`, so switching screens while `ProjectStore.save`'s background
    /// write was still in flight would list the project as missing (first save) or with stale content.
    /// The wait doesn't freeze anything — the encode and write are off the main thread now, so the
    /// editor stays responsive for the moment it takes.
    private func returnToGallery() {
        saveIfNeeded { screen = .gallery }
    }

    private func saveIfNeeded(completion: (@MainActor () -> Void)? = nil) {
        guard screen == .editor, canvasManager.canvasSize != nil else {
            completion?()
            return
        }
        // An adjustable fill, an adjustable smart shape, and a mid-transform move/duplicate are all
        // UI-only state (see `CanvasManager.beginCanvasEdit`) — bake every one of them in before
        // saving, or backgrounding the app silently drops whichever was still pending.
        canvasManager.commitAllInteractiveState()
        let url = canvasManager.projectURL ?? ProjectStore.createNewProjectURL(name: canvasManager.projectName)
        canvasManager.projectURL = url
        ProjectStore.save(canvasManager, to: url, completion: completion)
    }
}
