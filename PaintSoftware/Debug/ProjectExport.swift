import Foundation

/// **Copies one of the artist's own projects out of the folder they chose, into somewhere a Mac can
/// reach it.**
///
/// ## Why this has to exist
///
/// Item (36) moved the project library **out** of the app container and onto a folder the artist
/// picks, which is the whole point of it: a test build that lands on the iPad can no longer take
/// their saved work with it. The owner's chosen folder is, MEASURED from the security-scoped
/// bookmark in the device's own defaults, inside Apple's local File Provider group:
///
///     /private/var/mobile/Containers/Shared/AppGroup/<uuid>/File Provider Storage/PaintApp
///
/// `devicectl` reaches exactly four domains — `temporary`, `appDataContainer`,
/// `appGroupDataContainer` and `systemCrashLogs` — and every one of them resolves against an app
/// *this* developer signed. The File Provider group is Apple's, so the answer to "pull Test1 off the
/// iPad" is not a `devicectl` flag and never will be. **The only process on that device entitled to
/// read the folder is this app**, because it is the one holding the bookmark.
///
/// So the export is a launch argument, for the same reason `PlaybackProbe` is one: it makes a
/// question cost one build instead of one message to the owner. The owner named `Test1` as their
/// source of truth for the disappearing-strokes defect — a 4096² document with three layers, many
/// strokes and placed images, which reproduces reliably once the canvas padding is raised. Nothing
/// seeded by `UITestSeeds` is that document, and a defect measured against a synthetic stand-in is a
/// defect measured against the wrong thing.
///
/// ## What it will not do
///
/// It **only reads** the chosen root. It never writes there, never renames, never deletes — the
/// owner's standing permission that "everything on the ipad right now is expendable" lapsed when
/// (36) turned that folder into somewhere they keep artwork, and TODO (57) says so in as many words.
/// The copy lands in `Documents/Export/` inside this app's own container, which is expendable by
/// construction and which `devicectl device copy from` can fetch.
///
/// ## Arguments
///
///     -exportProject               arm it; with no name, writes only the index
///     -exportName <s>              directory name or manifest title to copy (case-insensitive)
///     -exportAll                   copy every project found (careful: the library may be large)
///
/// `Documents/Export/index.json` is always written and always lists every project found, with its
/// directory name, its manifest title and its size on disk. **Those two names differing is TODO (57)
/// point 2** — the owner's `Test1` lives in a directory still called `Untitled.paintproj` — so the
/// index is also the cheapest possible evidence for that item, and it is worth reading even when the
/// copy is what you came for.
enum ProjectExport {

    // MARK: - Arming

    static var isArmed: Bool { ProcessInfo.processInfo.arguments.contains("-exportProject") }

    private static var wantsAll: Bool { ProcessInfo.processInfo.arguments.contains("-exportAll") }

    private static var requestedName: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-exportName"), args.index(after: flag) < args.endIndex
        else { return nil }
        return args[args.index(after: flag)]
    }

    // MARK: - What a project is, from outside the model

    /// One project as the index reports it. `directoryName` and `title` are read from two different
    /// places on purpose — the directory from the filesystem, the title from `manifest.json` — which
    /// is exactly the pair TODO (57) point 2 says has drifted apart.
    private struct Entry {
        let url: URL
        let directoryName: String
        let title: String?
        let bytes: Int64
    }

    // MARK: - The run

    /// Enumerates, writes the index, copies what was asked for, and exits. Called from `ContentView`'s
    /// `task` when armed, before anything else has had a chance to open a document.
    static func run() async {
        let root = ProjectLocation.currentRoot
        let exportDirectory = destinationDirectory()

        var lines: [String] = []
        lines.append("root: \(root.path)")
        lines.append("status: \(String(describing: ProjectLocation.status))")

        let entries = enumerateProjects(under: root)
        lines.append("found: \(entries.count)")

        writeIndex(entries, root: root, to: exportDirectory)

        let wanted: [Entry]
        if wantsAll {
            wanted = entries
        } else if let name = requestedName {
            wanted = entries.filter { matches($0, name: name) }
            lines.append("requested: \(name) -> \(wanted.count) match(es)")
        } else {
            wanted = []
            lines.append("requested: (index only)")
        }

        for entry in wanted {
            let destination = exportDirectory.appendingPathComponent(entry.directoryName)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: entry.url, to: destination)
                lines.append("copied: \(entry.directoryName) (\(entry.bytes) bytes) title=\(entry.title ?? "-")")
            } catch {
                lines.append("FAILED: \(entry.directoryName): \(error)")
            }
        }

        let log = lines.joined(separator: "\n") + "\n"
        try? log.write(to: exportDirectory.appendingPathComponent("export.log"),
                       atomically: true, encoding: .utf8)

        // Same contract as `PlaybackProbe`: the process ending is the signal that the work is done,
        // so the caller never has to poll for a file that may still be half-written.
        exit(0)
    }

    // MARK: - Enumeration

    /// Walks the chosen root for `.paintproj` bundles at any depth, because the gallery browses an
    /// arbitrarily deep tree and the owner was told they could organise into "projects, sequences,
    /// scenes, shots". A bundle is a directory, so the walk must not descend *into* one.
    private static func enumerateProjects(under root: URL) -> [Entry] {
        var found: [Entry] = []
        var stack: [URL] = [root]

        while let directory = stack.popLast() {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for url in contents {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDirectory else { continue }
                if url.pathExtension == "paintproj" {
                    found.append(Entry(url: url,
                                       directoryName: url.lastPathComponent,
                                       title: manifestTitle(at: url),
                                       bytes: byteSize(of: url)))
                } else {
                    stack.append(url)
                }
            }
        }
        return found.sorted { $0.directoryName < $1.directoryName }
    }

    /// Reads `name` straight out of `manifest.json` with `JSONSerialization` rather than through
    /// `ProjectStore.loadManifest`, so a manifest this build cannot decode still reports its title
    /// instead of vanishing from the index. A damaged project is exactly the one you want listed.
    private static func manifestTitle(at projectURL: URL) -> String? {
        let manifest = projectURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["name"] as? String
    }

    private static func byteSize(of directory: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    private static func matches(_ entry: Entry, name: String) -> Bool {
        let wanted = name.lowercased()
        if entry.directoryName.lowercased() == wanted { return true }
        if entry.directoryName.lowercased() == wanted + ".paintproj" { return true }
        if let title = entry.title?.lowercased(), title == wanted { return true }
        return false
    }

    // MARK: - Output

    /// **Wiped at the start of every run, which is the cleanup as well as the freshness.** A name can
    /// match many bundles — a project, its autosaves and its pre-update copies all carry the same
    /// manifest title, so one `-exportName Test1` copied ten of them and left ~100 MB inside the
    /// container. Leaving that to accumulate on a 3 GB device would be this tool taking storage from
    /// the artist to answer a developer's question. So a run with no `-exportName` both writes the
    /// index and clears the last run's copies, and there is nothing else to remember to do.
    private static func destinationDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeIndex(_ entries: [Entry], root: URL, to directory: URL) {
        let payload: [String: Any] = [
            "root": root.path,
            "projects": entries.map { entry in
                [
                    "directoryName": entry.directoryName,
                    "title": entry.title ?? NSNull(),
                    "bytes": entry.bytes,
                    "directoryMatchesTitle": entry.title.map {
                        entry.directoryName == "\($0).paintproj"
                    } ?? false,
                    "path": entry.url.path,
                ] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("index.json"))
    }
}
