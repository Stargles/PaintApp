import SwiftUI

struct GalleryView: View {
    var onOpenProject: (CanvasManager) -> Void
    var onCreateNew: () -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var projectPendingDeletion: ProjectSummary?

    var body: some View {
        NavigationStack {
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
                            onDelete: { projectPendingDeletion = project }
                        )
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Gallery")
        }
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
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
}
