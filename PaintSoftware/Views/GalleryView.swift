import SwiftUI

struct GalleryView: View {
    var onOpenProject: (CanvasManager) -> Void
    var onCreateNew: () -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var projectPendingDeletion: ProjectSummary?
    @State private var projectForVersions: ProjectSummary?
    @State private var showRecentlyDeleted = false
    @State private var showingUnrecoverableAlert = false

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

    private func open(_ project: ProjectSummary) {
        if let manager = ProjectStore.load(from: project.url) {
            onOpenProject(manager)
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
