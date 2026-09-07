import SwiftUI

/// A sub-folder of the project tree, drawn to the same 160pt grid as `GalleryTileView` so the two
/// interleave in one `LazyVGrid` — TODO (36).
///
/// The count on the tile is not decoration. A folder tile is otherwise indistinguishable from an
/// empty one, and the artist's own framing for this feature ("projects, sequences, scenes, shots")
/// is a tree they will navigate by memory; "12 projects" is what tells them they are in the right
/// branch before they open it.
struct GalleryFolderTileView: View {
    let folder: ProjectStore.ProjectFolder
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        // **A `Button`, not a `VStack` with an `onTapGesture`.** The project tile next door uses the
        // gesture form and its tests reach it through the ellipsis menu instead; a folder tile has to
        // be tappable *as itself*, and a plain stack with an accessibility identifier on it does not
        // appear in the element tree at all — which is what the first run of `ProjectStorageUITests`
        // found. It is also the truer description: opening a folder is a button, and VoiceOver now
        // says so.
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack {
                        Color.blue.opacity(0.18)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue.opacity(0.9))
                    }
                    .frame(width: 160, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(folder.name)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(folder.projectCount == 1 ? "1 project" : "\(folder.projectCount) projects")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.folderTile.\(folder.name)")
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button("Rename…", action: onRename)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(6)
                }
                .accessibilityIdentifier("gallery.folderMenu.\(folder.name)")
            }
            .contextMenu {
                Button("Rename…", action: onRename)
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .frame(width: 160)
    }
}

/// The "move this project into…" list — every folder in the tree, indented, plus the root.
///
/// It exists because without it folders are write-only: migration puts every existing project at the
/// top level, and a folder you can only fill by creating a *new* project inside it cannot organise
/// work that already exists. The owner's ask was explicitly about organising what they have.
struct ProjectMoveView: View {
    let project: ProjectSummary
    var onMoved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var folders: [(folder: ProjectStore.ProjectFolder, depth: Int)] = []

    private var currentParent: URL { project.url.deletingLastPathComponent() }

    var body: some View {
        NavigationStack {
            List {
                row(name: "Projects", depth: 0, url: ProjectStore.projectsDirectory, icon: "tray.full")
                ForEach(folders, id: \.folder.id) { entry in
                    row(name: entry.folder.name, depth: entry.depth + 1, url: entry.folder.url,
                        icon: "folder")
                }
            }
            .navigationTitle("Move “\(project.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { folders = ProjectStore.allFolders() }
    }

    @ViewBuilder
    private func row(name: String, depth: Int, url: URL, icon: String) -> some View {
        let isHere = url.standardizedFileURL == currentParent.standardizedFileURL
        Button {
            guard !isHere else { dismiss(); return }
            if ProjectStore.moveProject(at: project.url, into: url) != nil { onMoved() }
            dismiss()
        } label: {
            HStack {
                Spacer().frame(width: CGFloat(depth) * 16)
                Image(systemName: icon).foregroundColor(.blue)
                Text(name).foregroundColor(.white)
                Spacer()
                if isHere {
                    Text("Here").font(.caption).foregroundColor(.gray)
                }
            }
        }
        .disabled(isHere)
        .accessibilityIdentifier("gallery.moveTarget.\(name)")
    }
}
