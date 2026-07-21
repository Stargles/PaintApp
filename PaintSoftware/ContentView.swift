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

    private func returnToGallery() {
        saveIfNeeded()
        screen = .gallery
    }

    private func saveIfNeeded() {
        guard screen == .editor, canvasManager.canvasSize != nil else { return }
        let url = canvasManager.projectURL ?? ProjectStore.createNewProjectURL(name: canvasManager.projectName)
        canvasManager.projectURL = url
        ProjectStore.save(canvasManager, to: url)
    }
}
