import SwiftUI

struct StubToolPanel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}
