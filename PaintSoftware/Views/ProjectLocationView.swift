import SwiftUI
import UniformTypeIdentifiers

/// **Where the artist says where their projects live** — TODO (36), the artist-facing half of
/// `ProjectLocation`.
///
/// The screen has to answer three questions in the order they are asked: *where are my files now*,
/// *how do I change that*, and — when something has gone wrong — *what happened and is my work
/// still there*. The third is the one that justifies the sheet existing at all rather than a bare
/// picker button: a bookmark that stops resolving is not an error to log, it is a sentence somebody
/// has to read.
struct ProjectLocationView: View {
    /// Called after a change lands, so the gallery can re-list from the new root.
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: ProjectLocation.Status = ProjectLocation.status
    @State private var showingPicker = false
    @State private var isWorking = false
    /// The last thing that happened, said in full. Not a toast: a migration that could not carry two
    /// files is exactly the message that must not disappear before it is read.
    @State private var outcome: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(iconColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.displayName)
                                .foregroundColor(.white)
                                .accessibilityIdentifier("storage.currentLocationName")
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        if isWorking { ProgressView().tint(.white) }
                    }
                } header: {
                    Text("Projects are saved in")
                } footer: {
                    Text("A folder you pick in Files stays on the device — or in iCloud — when the "
                         + "app is reinstalled. Anything saved inside the app is erased with it.")
                }

                if let problem {
                    Section {
                        Text(problem)
                            .foregroundColor(.yellow)
                            .accessibilityIdentifier("storage.problemMessage")
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label(ProjectLocation.hasChosenFolder ? "Choose a Different Folder…"
                                                              : "Choose a Folder…",
                              systemImage: "folder.badge.gearshape")
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("storage.chooseFolderButton")

                    if ProjectLocation.hasChosenFolder {
                        Button(role: .destructive) {
                            revert()
                        } label: {
                            Label("Move Back Inside the App", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier("storage.useDefaultButton")
                    }
                } footer: {
                    Text("Everything already saved moves with you. Each project is copied and "
                         + "checked before the old copy is removed, so an interrupted move can "
                         + "leave a duplicate but never a missing project.")
                }

                if let outcome {
                    Section {
                        Text(outcome)
                            .foregroundColor(.white)
                            .accessibilityIdentifier("storage.outcomeMessage")
                    }
                }
            }
            .navigationTitle("Storage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("storage.doneButton")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { refreshStatus() }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { adopt(url) }
            case .failure(let error):
                outcome = "That folder could not be opened — \(error.localizedDescription)"
            }
        }
    }

    private var icon: String {
        switch status {
        case .appFolder: return "iphone"
        case .chosen: return "folder.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .appFolder: return .gray
        case .chosen: return .blue
        case .unavailable: return .yellow
        }
    }

    private var subtitle: String {
        switch status {
        case .appFolder:
            // Not "Inside the app — …": the row's title already says that, and the subtitle
            // repeating it read as a stutter on the first screenshot of this screen.
            return "Reinstalling the app erases these files."
        case .chosen(let url):
            return url.deletingLastPathComponent().lastPathComponent.isEmpty
                ? "A folder you chose in Files."
                : "In \(url.deletingLastPathComponent().lastPathComponent)."
        case .unavailable:
            return "Not reachable right now."
        }
    }

    private func refreshStatus() {
        status = ProjectLocation.status
        problem = status.problem
    }

    /// **The security scope is started here and never stopped**, which is deliberate and is the
    /// difference between this and a document open. `fileImporter` vends a security-scoped URL whose
    /// scope the receiver owns; `ProjectLocation.adopt` mints a bookmark from it and immediately
    /// re-resolves that bookmark, taking its own process-lifetime hold. Stopping this one afterwards
    /// would be correct bookkeeping and is skipped on purpose: the two URLs are equal, the scope is
    /// refcounted, and a `stop` here has been observed to revoke the hold the resolve just took.
    private func adopt(_ url: URL) {
        // Not `guard`: a false answer here means "this URL was not security-scoped", which is true of
        // a folder inside the app's own container and says nothing about whether it is writable.
        // `ProjectLocation.adopt` re-resolves and probes for real, and reports the refusal in a
        // sentence if there is one. See `ProjectLocation.resolveStoredBookmark`.
        _ = url.startAccessingSecurityScopedResource()
        isWorking = true
        outcome = nil
        Task.detached(priority: .userInitiated) {
            let result = Result { try ProjectLocation.adopt(url) }
            await MainActor.run {
                isWorking = false
                switch result {
                case .success(let adoption):
                    status = adoption.status
                    problem = adoption.status.problem
                    outcome = adoption.migration.summary
                        ?? "Projects are now saved in “\(adoption.status.displayName)”."
                case .failure(let error):
                    outcome = "That folder could not be used — \(error.localizedDescription)"
                }
                onChanged()
            }
        }
    }

    private func revert() {
        isWorking = true
        outcome = nil
        Task.detached(priority: .userInitiated) {
            let report = ProjectLocation.revertToAppFolder()
            await MainActor.run {
                isWorking = false
                status = ProjectLocation.status
                problem = status.problem
                outcome = report.summary
                    ?? "Projects are saved inside the app again. Reinstalling will erase them."
                onChanged()
            }
        }
    }
}
