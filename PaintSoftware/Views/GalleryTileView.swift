import SwiftUI

struct GalleryTileView: View {
    let project: ProjectSummary
    var onOpen: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let thumbnail = project.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 160, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(project.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)

            Text(project.modifiedAt, style: .date)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(width: 160)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
