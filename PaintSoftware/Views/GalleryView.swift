import SwiftUI

struct GalleryView: View {
    var onOpenProject: (CanvasManager) -> Void
    var onCreateNew: () -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var projectPendingDeletion: ProjectSummary?
    @State private var projectForVersions: ProjectSummary?
    @State private var showRecentlyDeleted = false
    @State private var showingUnrecoverableAlert = false
    /// Which project is opening, if any — see `GalleryOpenState` for the two rules it carries.
    @State private var openState = GalleryOpenState()

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        Button(action: onCreateNew) {
                            VStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 32))
                                Text("New Canvas")
                                    .font(.caption)
                            }
                            .frame(width: 160, height: 160)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                        }
                        .accessibilityIdentifier("gallery.newCanvasButton")

                        ForEach(projects) { project in
                            GalleryTileView(
                                project: project,
                                isOpening: openState.isOpening(project.id),
                                onOpen: { open(project) },
                                onDelete: { projectPendingDeletion = project },
                                onShowVersions: { projectForVersions = project },
                                onRecover: { recover(project) }
                            )
                        }
                    }
                    .padding()
                }
                .background(Color.black.ignoresSafeArea())
                .navigationTitle("Gallery")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showRecentlyDeleted = true
                        } label: {
                            Image(systemName: "trash")
                                .accessibilityLabel("Recently Deleted")
                        }
                        .accessibilityIdentifier("gallery.recentlyDeletedButton")
                    }
                }

                // Version display in top-left corner
                VStack {
                    HStack {
                        Text(AppVersion.versionString)
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.leading, 16)
                            .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        // Not a scrim over the grid, deliberately: the tile carries its own spinner, and a
        // full-screen cover would hide the one thing that says *which* project is opening. This is
        // only the "no second tap" half of `GalleryOpenState`, expressed where SwiftUI can enforce it
        // for the New Canvas button and the toolbar as well as for the tiles.
        .disabled(openState.isBusy)
        .onAppear { refresh() }
        // Launch-time maintenance may have auto-restored a damaged project — re-list when it ends.
        .onReceive(NotificationCenter.default.publisher(for: .projectBackupMaintenanceDidFinish)) { _ in
            refresh()
        }
        .sheet(item: $projectForVersions) { project in
            ProjectVersionsView(project: project, onRestored: { refresh() })
        }
        .sheet(isPresented: $showRecentlyDeleted) {
            RecentlyDeletedView(onRestored: { refresh() })
        }
        .alert("Delete this project?", isPresented: Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let project = projectPendingDeletion {
                    ProjectStore.delete(at: project.url)
                    refresh()
                }
                projectPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { projectPendingDeletion = nil }
        } message: {
            Text("It will be kept in Recently Deleted for 7 days.")
        }
        .alert("No Backup Available", isPresented: $showingUnrecoverableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This project is damaged and no intact backup of it exists to restore from.")
        }
    }

    private func refresh() {
        projects = ProjectStore.listProjects()
    }

    /// Opens a project, having first put a spinner on the tile.
    ///
    /// **The spinner came first and the speed came second, in that order and on purpose.** An app
    /// that goes dead on the first tap of a session, with no indication it is doing anything, is
    /// indistinguishable from one that has crashed; that was fixed on its own so it did not have to
    /// wait for the work that shortens the wait. `loadInBackground` is that work (PERFORMANCE.md item
    /// 9(b)): the per-cel decode now runs on `ProjectStore.loadQueue`, spread over cores, so the main
    /// thread is free to *animate* the spinner rather than merely to have drawn it. What is still on
    /// the main actor is the `CanvasManager` assembly and the thumbnail walk.
    ///
    /// **The yield stays, and it is still load-bearing.** Setting `openState` marks the view dirty;
    /// SwiftUI renders that at the end of the current run-loop turn. `await Task.yield()` resumes on
    /// the main actor *after* that turn, so the spinner is on screen and committed before anything
    /// else happens. `loadInBackground` suspends immediately after its manifest read, which would
    /// usually be enough — but "usually" is not a guarantee about when a suspension point is reached,
    /// and one line is cheaper than depending on one.
    private func open(_ project: ProjectSummary) {
        guard openState.begin(project.id) else { return }
        Task { @MainActor in
            await Task.yield()
            let manager = await ProjectStore.loadInBackground(from: project.url)
            // Unconditional, and before the screen switch: a package that fails to decode returns nil
            // and leaves the artist in the gallery, which must not be a gallery stuck behind a
            // spinner. See `GalleryOpenState`.
            openState.finish()
            if let manager { onOpenProject(manager) }
        }
    }

    private func recover(_ project: ProjectSummary) {
        if ProjectBackupManager.restoreNewestValidBackup(forProjectAt: project.url) {
            refresh()
        } else {
            showingUnrecoverableAlert = true
        }
    }
}
