import SwiftUI

struct GalleryTileView: View {
    let project: ProjectSummary
    /// True while `ProjectStore.load` is running for this project — see `GalleryOpenState`. The
    /// spinner sits on the tapped tile rather than over the grid because the artist tapped a
    /// particular project and "which one" is half the feedback.
    var isOpening: Bool = false
    var onOpen: () -> Void
    var onDelete: () -> Void
    var onShowVersions: () -> Void
    var onRecover: () -> Void
    /// TODO (36) — "Move to…". On the tile rather than only in the storage screen because filing a
    /// project is something the artist does *while looking at it*, and because migration lands every
    /// existing project at the top level: without this, folders could only ever hold new work.
    var onMove: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if project.isCorrupted {
                    Color.red.opacity(0.25)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.yellow)
                } else if let thumbnail = project.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }

                if isOpening {
                    Color.black.opacity(0.55)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .accessibilityIdentifier("gallery.openingSpinner")
                }
            }
            .frame(width: 160, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Menu {
                    if project.isCorrupted {
                        Button("Restore from Backup", action: onRecover)
                    } else {
                        Button("Versions…", action: onShowVersions)
                    }
                    Button("Move to…", action: onMove)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(6)
                }
                .accessibilityIdentifier("gallery.tileMenu.\(project.name)")
            }

            Text(project.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)

            if isOpening {
                Text("Opening…")
                    .font(.caption2)
                    .foregroundColor(.white)
            } else if project.isCorrupted {
                Text("Damaged — tap to recover")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            } else {
                Text(project.modifiedAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 160)
        .contentShape(Rectangle())
        .onTapGesture { project.isCorrupted ? onRecover() : onOpen() }
        .contextMenu {
            if project.isCorrupted {
                Button("Restore from Backup", action: onRecover)
            } else {
                Button("Versions…", action: onShowVersions)
            }
            Button("Move to…", action: onMove)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
