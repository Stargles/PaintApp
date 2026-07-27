import SwiftUI

/// Per-project version history (see ProjectBackupManager): the last saved state is always kept as
/// `latest`, every save stashes the previous state as an autosave, and every app update snapshots
/// the project beforehand. Restoring any entry moves the current live package to Trash (not a hard
/// delete), so even a restore is itself undoable.
struct ProjectVersionsView: View {
    let project: ProjectSummary
    var onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var backups: [ProjectBackupManager.ProjectBackup] = []

    var body: some View {
        NavigationStack {
            List {
                if backups.isEmpty {
                    Text("No saved versions yet. Versions are kept automatically once the project has been saved.")
                        .foregroundColor(.gray)
                }
                ForEach(backups) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(backup.date, style: .date)
                                Text(backup.date, style: .time)
                            }
                            Text(backup.isValid ? backup.label : "\(backup.label) — damaged")
                                .font(.caption)
                                .foregroundColor(backup.isValid ? .gray : .yellow)
                        }
                        Spacer()
                        Button("Restore") {
                            if ProjectBackupManager.restoreBackup(at: backup.url, toProjectAt: project.url) {
                                onRestored()
                                dismiss()
                            }
                        }
                        .disabled(!backup.isValid)
                        .accessibilityIdentifier("gallery.versionRestore.\(backup.id)")
                    }
                }
            }
            .navigationTitle("Versions — \(project.name)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { backups = ProjectBackupManager.listBackups(forProjectAt: project.url) }
    }
}

/// The Trash: projects deleted from the gallery (or replaced by a restore / auto-repaired after
/// corruption) are kept here for `ProjectBackupManager.trashRetentionInterval` (7 days) before
/// being permanently purged, and can be put back at any time until then.
struct RecentlyDeletedView: View {
    var onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ProjectBackupManager.TrashItem] = []

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("Nothing here. Deleted projects are kept for 7 days before being permanently removed.")
                        .foregroundColor(.gray)
                }
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                            HStack(spacing: 4) {
                                Text("Deleted")
                                Text(item.deletedAt, style: .date)
                                Text("·")
                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
                            }
                            .font(.caption)
                            .foregroundColor(.gray)
                        }
                        Spacer()
                        Button("Restore") {
                            if ProjectBackupManager.restoreFromTrash(item.url) != nil {
                                onRestored()
                                reload()
                            }
                        }
                        .accessibilityIdentifier("gallery.trashRestore.\(item.id)")
                    }
                }
            }
            .navigationTitle("Recently Deleted")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
    }

    private func reload() {
        items = ProjectBackupManager.listTrash()
    }
}
