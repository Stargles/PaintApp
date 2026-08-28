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

    /// The save the artist started that is waiting on an answer to the damaged-save banner, or nil
    /// when nothing is being asked. See `SaveDamageGate` for the ruling this implements.
    @State private var pendingDamagedSave: PendingDamagedSave?

    /// A save held mid-flight: where it was going, and what it was going to do afterwards.
    ///
    /// The completion is the load-bearing field. `returnToGallery` passes "now show the gallery", and
    /// holding it here rather than running it is what makes the banner a question instead of a
    /// notification — the artist stays in the editor, looking at the layer the banner names, until
    /// they answer.
    private struct PendingDamagedSave: Identifiable {
        let id = UUID()
        let completion: (@MainActor () -> Void)?
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch screen {
            case .gallery:
                GalleryView(onOpenProject: openProject, onCreateNew: startNewProject)
            case .sizePicker:
                CanvasSizePickerView(canvasManager: canvasManager, onCreated: { screen = .editor })
            case .editor:
                DrawingView(canvasManager: canvasManager,
                            onOpenGallery: returnToGallery,
                            damagedSave: pendingDamagedSave == nil ? nil : canvasManager.loadDamage,
                            onSaveAnyway: saveAnywayOverDamage,
                            onCancelDamagedSave: keepDamagedOriginal)
            }
        }
        #if os(iOS)
        .statusBar(hidden: true)
        #endif
        // Both phases, not just the new one: `.inactive` occurs on the way out *and* on the way back,
        // so testing `newPhase` alone saved three times per app switch and stalled the return leg.
        // `ScenePhaseSaveGate` carries the reasoning and the transition matrix.
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if ScenePhaseSaveGate.shouldSave(from: oldPhase, to: newPhase) {
                // `.automatic`: this save must never stop to ask. There may be no screen to present
                // on and no time to present it in, and on a damaged, unanswered document it writes to
                // the project's version history instead of over the project. See `SaveDamageGate`.
                saveIfNeeded(intent: .automatic)
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
        // `.artist`: there is a person watching, waiting, who can be asked a question — the one save
        // in this app that a prompt is acceptable in front of.
        saveIfNeeded(intent: .artist) { screen = .gallery }
    }

    private func saveIfNeeded(intent: SaveIntent, completion: (@MainActor () -> Void)? = nil) {
        // The third condition is CANVAS_RESIZE.md §5 rule 12: no save may *start* while a canvas
        // resize is in flight, or the package written is half old-size and half new. See
        // `ScenePhaseSaveGate.mayStartSave` for why that document opens rather than failing.
        guard ScenePhaseSaveGate.mayStartSave(screenIsEditor: screen == .editor,
                                              hasCanvas: canvasManager.canvasSize != nil,
                                              isResizing: canvasManager.isResizing) else {
            completion?()
            return
        }
        // An adjustable fill, an adjustable smart shape, and a mid-transform move/duplicate are all
        // UI-only state (see `CanvasManager.beginCanvasEdit`) — bake every one of them in before
        // saving, or backgrounding the app silently drops whichever was still pending.
        canvasManager.commitAllInteractiveState()
        let url = canvasManager.projectURL ?? ProjectStore.createNewProjectURL(name: canvasManager.projectName)
        canvasManager.projectURL = url
        // `onSaveFailed` is the one channel `completion` never was (ARCHITECTURE_REVIEW.md finding
        // 3): `writeAtomically`'s three failure returns used to be silent, so the gallery could
        // appear exactly as it does on a real save while the artist's edits were never written.
        if ProjectStore.save(canvasManager, to: url, intent: intent,
                              onSaveFailed: { canvasManager.raise(.saveFailed) },
                              completion: completion) == .ask {
            // Nothing was written and `completion` did not run, so the editor stays put with the
            // banner up. The two buttons below are the only ways out.
            pendingDamagedSave = PendingDamagedSave(completion: completion)
        }
    }

    /// "Save Anyway": the artist has decided the project may be rewritten without what could not be
    /// read. Answered first, so the save that follows — and every save after it for this document —
    /// takes the ordinary path.
    ///
    /// The next load of this project reports clean, because the entries it could not read are no
    /// longer in the file. That is why the answer does not need to be persisted; see
    /// `CanvasManager.damagedSaveAnswered`.
    private func saveAnywayOverDamage() {
        guard let pending = pendingDamagedSave else { return }
        pendingDamagedSave = nil
        canvasManager.damagedSaveAnswered = true
        // Back through `saveIfNeeded`, not straight to `ProjectStore.save`: the banner does not block
        // the canvas, so the artist may have started an interactive fill or shape while it was up, and
        // `commitAllInteractiveState` is what stops that being silently dropped.
        saveIfNeeded(intent: .artist, completion: pending.completion)
    }

    /// "Cancel": do not overwrite the original. **Not "lose what I just drew"** — the same save runs,
    /// with `.automatic`'s destination, so a complete package of the artist's work lands in the
    /// project's version history as "Unsaved changes" and the damaged project file is left exactly as
    /// it is. The banner said so before the button was pressed
    /// (`ProjectLoadDamage.consequence`).
    ///
    /// `damagedSaveAnswered` stays false on purpose: they declined to decide, so the next
    /// artist-initiated save asks again. Nothing about the file has changed, so there is nothing to
    /// stop asking about.
    private func keepDamagedOriginal() {
        guard let pending = pendingDamagedSave else { return }
        pendingDamagedSave = nil
        saveIfNeeded(intent: .automatic, completion: pending.completion)
    }
}
