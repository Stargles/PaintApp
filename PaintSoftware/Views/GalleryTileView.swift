import SwiftUI

struct GalleryTileView: View {
    let project: ProjectSummary
    var onOpen: () -> Void
    var onDelete: () -> Void
    var onShowVersions: () -> Void
    var onRecover: () -> Void

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

            if project.isCorrupted {
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
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
