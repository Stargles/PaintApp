import SwiftUI

/// Floating bottom bar shown whenever a `FloatingPiece` is active (a Move or Duplicate in
/// progress): mirror horizontal/vertical, rotate 90° left/right, and the Freeform/Uniform/Distort/
/// Warp mode picker. Procreate reference: the Transform tool's bottom toolbar.
struct MoveTransformBottomBar: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                iconButton("arrow.left.and.right") { canvasManager.mirrorFloating(horizontal: true) }
                    .accessibilityLabel("Mirror Horizontal")
                iconButton("arrow.up.and.down") { canvasManager.mirrorFloating(horizontal: false) }
                    .accessibilityLabel("Mirror Vertical")

                divider

                iconButton("rotate.left") { canvasManager.rotateFloating90(clockwise: false) }
                    .accessibilityLabel("Rotate 90° Left")
                iconButton("rotate.right") { canvasManager.rotateFloating90(clockwise: true) }
                    .accessibilityLabel("Rotate 90° Right")

                divider

                Button("Done") { canvasManager.commitFloatingPieceIfNeeded() }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("moveBar.doneButton")
            }

            Picker("Mode", selection: Binding(
                get: { canvasManager.transformMode },
                set: { canvasManager.setTransformMode($0) }
            )) {
                ForEach(TransformMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            if !canvasManager.transformMode.isImplemented {
                Text("Coming soon — acts like Uniform for now")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.9))
        .cornerRadius(14)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 24)
    }

    private func iconButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
        }
    }
}
