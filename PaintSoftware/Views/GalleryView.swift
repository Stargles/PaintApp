import SwiftUI

struct GalleryView: View {
    var onOpenProject: (CanvasManager) -> Void
    /// The folder the new project should be created in — TODO (36). The gallery is the only thing
    /// that knows which branch of the tree the artist is looking at, and a "New Canvas" that always
    /// landed at the top level would make folders useless for the work they are actually doing.
    var onCreateNew: (URL) -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var folders: [ProjectStore.ProjectFolder] = []
    /// Where in the tree we are, root first. Empty means `Projects/` itself. Held as names rather
    /// than URLs so that a storage relocation under the artist's feet re-roots the same path instead
    /// of leaving a stale absolute URL pointing into the old library.
    @State private var path: [String] = []
    @State private var projectPendingDeletion: ProjectSummary?
    @State private var folderPendingDeletion: ProjectStore.ProjectFolder?
    @State private var projectForVersions: ProjectSummary?
    @State private var projectToMove: ProjectSummary?
    @State private var showRecentlyDeleted = false
    @State private var showingUnrecoverableAlert = false
    @State private var showingStorage = false
    @State private var showingNewFolder = false
    @State private var folderBeingRenamed: ProjectStore.ProjectFolder?
    @State private var folderNameField = ""
    @State private var folderError: String?
    @State private var locationProblem: String? = ProjectLocation.status.problem
    /// Which project is opening, if any — see `GalleryOpenState` for the two rules it carries.
    @State private var openState = GalleryOpenState()

    /// The directory the tiles on screen come from.
    private var currentDirectory: URL {
        path.reduce(ProjectStore.projectsDirectory) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // **The banner is the whole of "a failed bookmark is surfaced, not swallowed".**
                    // It is not dismissible, it names the folder, and it says in as many words that
                    // work saved right now is going somewhere a reinstall can reach.
                    if let locationProblem {
                        Button {
                            showingStorage = true
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text(locationProblem)
                                    .font(.footnote)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.yellow.opacity(0.18))
                        }
                        .accessibilityIdentifier("gallery.locationProblemBanner")
                    }

                    if !path.isEmpty {
                        breadcrumb
                    }

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            Button(action: { onCreateNew(currentDirectory) }) {
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

                            ForEach(folders) { folder in
                                GalleryFolderTileView(
                                    folder: folder,
                                    onOpen: { path.append(folder.name); refresh() },
                                    onRename: { beginRename(folder) },
                                    onDelete: { folderPendingDeletion = folder }
                                )
                            }

                            ForEach(projects) { project in
                                GalleryTileView(
                                    project: project,
                                    isOpening: openState.isOpening(project.id),
                                    onOpen: { open(project) },
                                    onDelete: { projectPendingDeletion = project },
                                    onShowVersions: { projectForVersions = project },
                                    onRecover: { recover(project) },
                                    onMove: { projectToMove = project }
                                )
                            }
                        }
                        .padding()
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(path.last ?? "Gallery")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            folderNameField = ""
                            folderError = nil
                            showingNewFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .accessibilityLabel("New Folder")
                        }
                        .accessibilityIdentifier("gallery.newFolderButton")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingStorage = true
                        } label: {
                            Image(systemName: "externaldrive")
                                .accessibilityLabel("Storage")
                        }
                        .accessibilityIdentifier("gallery.storageButton")
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .projectLocationDidChange)) { _ in
            path = []
            refresh()
        }
        .sheet(item: $projectForVersions) { project in
            ProjectVersionsView(project: project, onRestored: { refresh() })
        }
        .sheet(item: $projectToMove) { project in
            ProjectMoveView(project: project, onMoved: { refresh() })
        }
        .sheet(isPresented: $showRecentlyDeleted) {
            RecentlyDeletedView(onRestored: { refresh() })
        }
        .sheet(isPresented: $showingStorage) {
            ProjectLocationView(onChanged: {
                path = []
                refresh()
            })
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Name", text: $folderNameField)
                .accessibilityIdentifier("gallery.folderNameField")
            Button("Create") { createFolder() }
                .accessibilityIdentifier("gallery.createFolderButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders can hold projects and other folders — a sequence, a scene, a shot.")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderBeingRenamed != nil },
            set: { if !$0 { folderBeingRenamed = nil } }
        )) {
            TextField("Name", text: $folderNameField)
                .accessibilityIdentifier("gallery.folderRenameField")
            Button("Rename") { commitRename() }
                .accessibilityIdentifier("gallery.commitRenameButton")
            Button("Cancel", role: .cancel) { folderBeingRenamed = nil }
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
        .alert("Delete this folder?", isPresented: Binding(
            get: { folderPendingDeletion != nil },
            set: { if !$0 { folderPendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let folder = folderPendingDeletion {
                    ProjectStore.deleteFolder(at: folder.url)
                    refresh()
                }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            // Said as a count rather than as "and its contents", because the count is what makes an
            // artist stop. Every project inside goes to Recently Deleted individually, so all of it
            // is restorable — see `ProjectStore.deleteFolder`.
            let count = folderPendingDeletion?.projectCount ?? 0
            Text(count == 0
                 ? "The folder is empty."
                 : "The \(count) project\(count == 1 ? "" : "s") inside will be kept in Recently "
                   + "Deleted for 7 days.")
        }
        .alert("No Backup Available", isPresented: $showingUnrecoverableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This project is damaged and no intact backup of it exists to restore from.")
        }
        .alert("Couldn’t Create Folder", isPresented: Binding(
            get: { folderError != nil }, set: { if !$0 { folderError = nil } }
        )) {
            Button("OK", role: .cancel) { folderError = nil }
        } message: {
            Text(folderError ?? "")
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                path.removeLast()
                refresh()
            } label: {
                Image(systemName: "chevron.left")
                Text(path.count == 1 ? "Gallery" : path[path.count - 2])
            }
            .accessibilityIdentifier("gallery.breadcrumbBack")
            Spacer()
            Text((["Projects"] + path).joined(separator: " / "))
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.head)
                .accessibilityIdentifier("gallery.breadcrumbPath")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundColor(.white)
    }

    private func refresh() {
        // A folder that has gone (deleted from Files, or the library relocated under us) must not
        // leave the gallery staring at an empty directory with no way back: walk up until something
        // exists. `Projects/` itself is created on demand, so the loop always terminates.
        while !path.isEmpty && !ProjectBackupManager.isDirectory(currentDirectory) {
            path.removeLast()
        }
        locationProblem = ProjectLocation.status.problem
        folders = ProjectStore.listFolders(in: currentDirectory)
        projects = ProjectStore.listProjects(in: currentDirectory)
    }

    private func createFolder() {
        do {
            try ProjectStore.createFolder(named: folderNameField, in: currentDirectory)
            refresh()
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func beginRename(_ folder: ProjectStore.ProjectFolder) {
        folderNameField = folder.name
        folderBeingRenamed = folder
    }

    private func commitRename() {
        guard let folder = folderBeingRenamed else { return }
        folderBeingRenamed = nil
        do {
            try ProjectStore.renameFolder(at: folder.url, to: folderNameField)
            refresh()
        } catch {
            folderError = error.localizedDescription
        }
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
