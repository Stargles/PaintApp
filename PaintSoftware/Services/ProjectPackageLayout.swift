import Foundation
import os

/// **Where each kind of file lives inside a `.paintproj` package, answered once for the writer, the
/// reader and the validator** — TODO (57) part 1.
///
/// The owner, 2026-09-08, looking at their own project in Files on the iPad: *"There is a json file
/// for the layers im guessing that contains the strokes. Why is this file under the images folder?"*
/// It was there because `images/` was the only content directory a package had. This type gives it
/// three — `drawings/` for the per-cel JSON sidecars, `images/` for pixels, `videos/` for imported
/// clips — and makes "which address holds this file today" a single function rather than a path
/// literal repeated at eleven call sites.
///
/// ## The format version is a slash
///
/// The three JSON roles are recorded in the manifest as **package-relative paths**
/// (`drawings/<celID>.json`); every PNG stays a bare name. The repo versions its format *"by field
/// presence, not by a number"* (KEYFRAMES.md §3.5), and here the presence is a `/` inside a value
/// that already exists. No manifest key is added, renamed or removed.
///
/// A **bare** name in `vectorFileName` / `animationFileName` / `interpolationFileName` therefore
/// means a package written before (57): the file is in `images/` under its old `_vector.json` /
/// `_anim.json` / `_interp.json` name. `existingURL` resolves either, forever — `Backups/` and
/// `Trash/` are history and are never migrated, so restoring a seven-day-old backup has to open.
///
/// ## Probe order is the race proof, so it is a rule rather than an accident
///
/// **Probe the address the migration moves *from* first, and the address it moves *to* second.**
/// `tidy` only ever moves old→new, `rename(2)` is atomic, and a file is therefore at exactly one of
/// the two addresses at every instant — so a miss at `images/` proves the move already completed and
/// the second probe hits. No retry loop, no lock, and a reader may run concurrently with the
/// migration on the same package. For a role nothing moves (`.video`), the current address is probed
/// first because that is the common case.
///
/// ## Forward compatibility is not claimed, and that is an accepted one-way break
///
/// A build older than (57) resolves `vectorFileName` as `images/<name>`, so it would look for
/// `images/drawings/<celID>.json`, miss, and load the cel's ink as empty. **There is no scheme that
/// avoids this**: the manifest field is one string, so either it names the old address (and the JSON
/// has not left `images/`, which is the whole ask) or it names the new one. The safeguard is the
/// `preupdate-` snapshot the app-signature bump takes on the first launch of a (57) build — a clone
/// of the pre-migration package, in `Backups/`, which nothing here ever touches — plus the note in
/// BUGS.md. See `ProjectPackageLayout.tidyEveryProject`.
///
/// Pure Foundation, no UIKit and no app-model types, so it compiles into the UI-test bundle exactly
/// as `ProjectBackupManager` and `ProjectLocation` do.
nonisolated enum ProjectPackageLayout {

    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "ProjectLayout")

    // MARK: - Roles

    /// What a file inside a package *is*, which after (57) is also where it lives. The property the
    /// owner was missing: a file's kind can be read off its path.
    enum Role: Hashable, CaseIterable {
        /// The cel's display list — strokes, fills, text, image and video refs (`VectorCanvasData`).
        case drawing
        /// The cel's pose channels and held baselines (`CelAnimationData`) — KEYFRAMES.md §3.5.
        case animation
        /// The cel's in-between recipe, when it is a derived cel (`InterpolationRecipe`).
        case interpolation
        case raster
        case fill
        case baked
        /// A photo placed into a vector cel. Its name lives inside the *payload*, not the manifest.
        case placedImage
        /// An imported clip, copied whole (VIDEO.md §6). Its name also lives inside the payload.
        case video

        /// Where **this** build writes it.
        var directory: String {
            switch self {
            case .drawing, .animation, .interpolation: return "drawings"
            case .raster, .fill, .baked, .placedImage: return "images"
            case .video:                               return "videos"
            }
        }

        /// True for the three roles the (57) migration moves, and therefore the three whose bare
        /// recorded name has a second address worth probing. Drives `existingURL`'s probe order.
        var isMoved: Bool {
            switch self {
            case .drawing, .animation, .interpolation: return true
            default:                                   return false
            }
        }
    }

    // MARK: - Names

    /// The package-relative name **this build records in the manifest** for one cel's sidecar.
    ///
    /// One separator and no `_vec` / `_anim` / `_interp` abbreviations, because the audience is
    /// someone browsing Files; the three sort adjacent under the cel they belong to. The folder is
    /// `drawings` rather than `cels` for the same audience — a cel is a drawing to them.
    static func recordedName(for role: Role, cel: UUID) -> String {
        switch role {
        case .drawing:       return "drawings/\(cel.uuidString).json"
        case .animation:     return "drawings/\(cel.uuidString)-animation.json"
        case .interpolation: return "drawings/\(cel.uuidString)-interpolation.json"
        default:
            preconditionFailure("PNG and video names are not derived from the cel id — a placed "
                                + "image and a clip both carry their name inside the payload")
        }
    }

    /// The legacy name a **pre-(57)** package records for the same sidecar. Only the migration and
    /// its tests need this; the resolver never derives it, it only ever reads what the manifest says.
    static func legacyName(for role: Role, cel: UUID) -> String {
        switch role {
        case .drawing:       return "\(cel.uuidString)_vector.json"
        case .animation:     return "\(cel.uuidString)_anim.json"
        case .interpolation: return "\(cel.uuidString)_interp.json"
        default:
            preconditionFailure("Only the three moved roles have a legacy name")
        }
    }

    /// Appends a package-relative path one component at a time.
    ///
    /// Not `appendingPathComponent(name)` with the slash left in: that API's treatment of an embedded
    /// separator is a platform detail, and every address in this file is load-bearing enough that
    /// "probably does the right thing" is not good enough.
    static func resolve(_ relative: String, in package: URL) -> URL {
        relative.split(separator: "/").reduce(package) { $0.appendingPathComponent(String($1)) }
    }

    // MARK: - Writing

    /// Where to **write** `name`. A slashed name is package-relative; a bare one goes in the role's
    /// own directory.
    static func writeURL(named name: String, role: Role, in package: URL) -> URL {
        if name.contains("/") { return resolve(name, in: package) }
        return package.appendingPathComponent(role.directory, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// Creates exactly the content directories a document needs, once, **before** the per-cel
    /// fan-out — so no worker ever races another to `createDirectory`.
    ///
    /// Lazily, which is the point: a pure-vector document (the owner's own) used to ship an empty
    /// `images/` folder beside its content, which is the next question they would have asked.
    static func createDirectories(_ roles: Set<Role>, in package: URL) {
        let fm = FileManager.default
        for directory in Set(roles.map(\.directory)).sorted() {
            try? fm.createDirectory(at: package.appendingPathComponent(directory, isDirectory: true),
                                    withIntermediateDirectories: true)
        }
    }

    // MARK: - Reading

    /// Where to **read** `name` from — whichever of its two possible addresses holds it today.
    ///
    /// `cel` is the id from the manifest entry, needed only to derive the *new* address of a bare
    /// moved name. Nil (a hand-built manifest with no `id` key) simply means no alternate to probe.
    ///
    /// Returns `primary` when neither address exists, so a caller's "missing file" diagnostics name
    /// the address the file is supposed to be at.
    static func existingURL(named name: String, role: Role, cel: UUID? = nil, in package: URL) -> URL {
        let fm = FileManager.default
        let primary: URL
        let alternate: URL?
        if name.contains("/") {
            primary = resolve(name, in: package)
            alternate = nil
        } else if role.isMoved {
            primary = package.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
            alternate = cel.map { resolve(recordedName(for: role, cel: $0), in: package) }
        } else if role == .video {
            primary = package.appendingPathComponent("videos", isDirectory: true).appendingPathComponent(name)
            alternate = package.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        } else {
            primary = package.appendingPathComponent(role.directory, isDirectory: true).appendingPathComponent(name)
            alternate = nil
        }
        if fm.fileExists(atPath: primary.path) { return primary }
        if let alternate, fm.fileExists(atPath: alternate.path) { return alternate }
        return primary
    }

    // MARK: - Migration (TODO (57) part 1)

    /// What one package's `tidy` did.
    enum TidyOutcome: Equatable {
        /// At least one sidecar moved out of `images/`. Carries the package's URL.
        case tidied(URL)
        /// Nothing to do: already in the new layout, or a raster-only document with no sidecars.
        case unchanged
        /// The manifest could not be read, so nothing was touched. The repair pass owns this package.
        case skippedDamaged
        /// The library root is not one this pass is willing to rename inside — see
        /// `migrationIsSafe(at:)`.
        case skippedForeignVolume
    }

    /// What a whole pass did. Mirrors `ProjectLibraryMigration.Report` so a test can assert on it.
    struct Report: Equatable {
        var tidied: [String] = []
        var unchanged = 0
        var skippedDamaged = 0
        var skippedForeignVolume = 0
        /// Individual sidecars renamed out of `images/`.
        var movedFiles = 0
        /// Package ids seen more than once in one walk — see `tidyEveryProject`.
        var duplicateProjectIDs: [String] = []
        var seconds: Double = 0

        var isEmpty: Bool { tidied.isEmpty && movedFiles == 0 }
        static let empty = Report()
    }

    /// **Whether a plain `rename(2)` at `root` means what this migration's crash-safety argument
    /// assumes it means.**
    ///
    /// Every step below is a `FileManager.moveItem` with no `NSFileCoordinator`, and the whole
    /// resume story ("a file is at exactly one of two addresses at every instant") is a *local
    /// volume* guarantee. A File Provider extension — iCloud Drive, a third-party provider surfaced
    /// through Files — is not contractually obliged to honour it: a move there can go through the
    /// provider's own asynchronous machinery and can materialise an evicted placeholder on the way.
    /// TODO (36) deliberately lets the library root be such a folder, so the question is real.
    ///
    /// So the predicate is narrow and checkable: **not a ubiquitous item, and on the same volume as
    /// the app's own container**, which is where `rename(2)` is POSIX-atomic. That admits the owner's
    /// own case (a folder on the iPad, same APFS volume) and refuses iCloud Drive and external
    /// volumes. It is deliberately stricter than it needs to be rather than untested-and-assumed —
    /// and it costs an externally-rooted library nothing permanent, because a save stages a
    /// *complete* package every time, so such a project lands in the new layout the next time the
    /// artist saves it.
    static func migrationIsSafe(at root: URL) -> Bool {
        // A logic test points the root at a temp directory in the container's own volume; asking the
        // filesystem is still the honest way to answer, so there is no test-only branch here.
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .volumeIdentifierKey]
        guard let values = try? root.resourceValues(forKeys: keys) else { return false }
        if values.isUbiquitousItem == true { return false }
        guard let volume = values.volumeIdentifier,
              let appVolume = (try? ProjectLocation.appFolder
                    .resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier else { return false }
        return volume.isEqual(appVolume)
    }

    /// Moves every project's JSON sidecars out from under `images/`, in place, losing nothing.
    ///
    /// **Runs from `ProjectBackupManager.runStartupMaintenance`, after `repairCorruptedProjects` and
    /// before the purges** — after, so a damaged package is restored before we look at it; before, so
    /// nothing is name-matched against a half-reconciled tree. That pass already posts
    /// `.projectBackupMaintenanceDidFinish`, which the gallery re-lists on.
    ///
    /// **`Backups/` and `Trash/` are history and are never walked.** That is also why the legacy
    /// resolver above is permanent rather than transitional.
    @discardableResult
    static func tidyEveryProject() -> Report {
        let started = CFAbsoluteTimeGetCurrent()
        var report = Report()
        let root = ProjectBackupManager.documentsDirectory
        let safe = migrationIsSafe(at: root)
        var seenIDs: [UUID: URL] = [:]
        for url in ProjectBackupManager.allProjectPackages() {
            // **The duplicate-id backstop.** `ProjectSummary` is `Identifiable` by the manifest id,
            // so two packages sharing one give SwiftUI's `ForEach` two rows with one identity and one
            // of them may simply never draw — an orphan on disk the artist cannot see. Nothing in
            // this item can produce that shape (it renames no package directory), but the walk is
            // already here and the check is one dictionary insert.
            if let id = ProjectBackupManager.manifestID(at: url) {
                if let first = seenIDs[id] {
                    report.duplicateProjectIDs.append(id.uuidString)
                    log.error("""
                        Two project packages carry the same manifest id \(id.uuidString, privacy: .public) — \
                        \(first.lastPathComponent, privacy: .public) and \(url.lastPathComponent, privacy: .public). \
                        The gallery lists them by that id, so one of the two may never draw
                        """)
                } else {
                    seenIDs[id] = url
                }
            }
            guard safe else { report.skippedForeignVolume += 1; continue }
            switch tidy(packageAt: url) {
            case .tidied(let tidied):
                report.tidied.append(tidied.lastPathComponent)
                report.movedFiles += lastTidyMovedFiles
            case .unchanged:            report.unchanged += 1
            case .skippedDamaged:       report.skippedDamaged += 1
            case .skippedForeignVolume: report.skippedForeignVolume += 1
            }
        }
        report.seconds = CFAbsoluteTimeGetCurrent() - started
        if !report.isEmpty || report.skippedDamaged > 0 || report.skippedForeignVolume > 0 {
            log.info("""
                Project layout pass: \(report.tidied.count, privacy: .public) tidied \
                (\(report.movedFiles, privacy: .public) sidecars moved), \
                \(report.unchanged, privacy: .public) already tidy, \
                \(report.skippedDamaged, privacy: .public) skipped as damaged, \
                \(report.skippedForeignVolume, privacy: .public) skipped on a root this pass will not \
                rename inside, in \(report.seconds, privacy: .public) s
                """)
        }
        return report
    }

    /// How many sidecars the last `tidy(packageAt:)` moved. `tidyEveryProject` runs serially, so a
    /// single slot is enough; it exists only so `TidyOutcome` does not have to carry a count that no
    /// other caller wants.
    private nonisolated(unsafe) static var lastTidyMovedFiles = 0

    /// One package, moved into the new layout in place.
    ///
    /// **Move, never copy, and never delete.** TODO (36)'s migration copies before it removes because
    /// it crosses two roots that may be different volumes; this one moves files *within one package
    /// on one volume*, where `rename(2)` is atomic, so a copy would add a window rather than remove
    /// one. The invariant is therefore stronger than (36)'s: **every file is complete at exactly one
    /// of two known addresses at every instant, and the reader knows both.** The package directory
    /// itself is never staged, cloned or removed.
    ///
    /// **Crash-resume is nothing**: every step is individually atomic and conditioned on what is on
    /// disk, so the next launch re-runs and finishes whatever is left. A third run changes nothing.
    ///
    /// | killed during | on disk | what the app does |
    /// |---|---|---|
    /// | a sidecar move | the file at `images/` **or** at `drawings/`, never neither, never both | the reader probes `images/` then `drawings/`; the cel loads whole |
    /// | between moves | some moved, some not, manifest still bare | every file resolves; the next run moves the rest |
    /// | the manifest write | the old manifest or the new one, never a partial one (`.atomic`) | old manifest + moved files still resolves via the alternate address |
    /// | after the manifest write | fully tidy | nothing left to do |
    @discardableResult
    static func tidy(packageAt url: URL) -> TidyOutcome {
        let fm = FileManager.default
        lastTidyMovedFiles = 0

        // 0. A package whose manifest we cannot read is the repair pass's business, not ours.
        guard ProjectBackupManager.validateProject(at: url) else { return .skippedDamaged }

        // 1. One read, used by the move walk and by the compare-and-swap below.
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let originalBytes = try? Data(contentsOf: manifestURL),
              let skeleton = try? JSONDecoder().decode(ProjectBackupManager.ManifestSkeleton.self,
                                                       from: originalBytes) else { return .skippedDamaged }

        // 2. Move the sidecars. (The package *directory*'s own name is TODO (57)'s second bullet and
        //    is deliberately not touched here — see this file's header.)
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        var rewrites: [(old: String, new: String)] = []
        var madeDrawingsDirectory = false
        for layer in skeleton.layers {
            for cel in layer.cels {
                guard let celID = cel.id else { continue }
                for role in [Role.drawing, .animation, .interpolation] {
                    guard let recorded = cel.fileName(for: role), !recorded.contains("/") else { continue }
                    let source = imagesDir.appendingPathComponent(recorded)
                    guard fm.fileExists(atPath: source.path) else { continue }
                    let relative = recordedName(for: role, cel: celID)
                    let destination = resolve(relative, in: url)
                    // **Both addresses occupied means something outside this flow wrote one of
                    // them**, because a rename cannot leave both. The conservative answer is to touch
                    // neither and say so.
                    if fm.fileExists(atPath: destination.path) {
                        log.error("""
                            \(recorded, privacy: .public) exists at both its old and its new address in \
                            \(url.lastPathComponent, privacy: .public) — a rename cannot leave both, so \
                            neither is touched and the manifest is left naming the old one
                            """)
                        continue
                    }
                    if !madeDrawingsDirectory {
                        try? fm.createDirectory(at: url.appendingPathComponent(Role.drawing.directory,
                                                                              isDirectory: true),
                                                withIntermediateDirectories: true)
                        madeDrawingsDirectory = true
                    }
                    do {
                        try fm.moveItem(at: source, to: destination)
                        rewrites.append((recorded, relative))
                    } catch {
                        // Left where it is, which the resolver still finds. The next run retries.
                        log.error("""
                            \(recorded, privacy: .public) could not be moved out of images/ in \
                            \(url.lastPathComponent, privacy: .public) and stays where it is: \
                            \(String(describing: error), privacy: .public)
                            """)
                    }
                }
            }
        }
        guard !rewrites.isEmpty else { return .unchanged }
        lastTidyMovedFiles = rewrites.count

        // 3. Rewrite the manifest to name the new addresses. Everything below is optional work: the
        //    files already resolve through `existingURL` whether or not this lands.
        rewriteManifest(at: manifestURL, in: url, originalBytes: originalBytes, rewrites: rewrites)
        return .tidied(url)
    }

    /// The one step that can destroy data, and the two lines that stop it.
    private static func rewriteManifest(at manifestURL: URL, in url: URL,
                                        originalBytes: Data, rewrites: [(old: String, new: String)]) {
        // **Compare-and-swap.** A save lands a whole new package at this path by rename; if that
        // happened while we were moving files, the manifest on disk is already in the new layout and
        // writing our stale bytes over it would lose the artist's last edits. Byte-identical or we
        // abandon the rewrite entirely — the moved files still resolve, and the next launch finishes.
        guard let current = try? Data(contentsOf: manifestURL), current == originalBytes else {
            log.info("""
                The manifest of \(url.lastPathComponent, privacy: .public) changed while its sidecars \
                were being moved, so it is left exactly as the save wrote it
                """)
            return
        }
        // Text surgery rather than a model round trip: decoding and re-encoding `ProjectManifest`
        // would drop every key this build does not know and reformat every double. Each replacement
        // must match **exactly once**, else that pair is skipped.
        guard var text = String(data: originalBytes, encoding: .utf8) else { return }
        for (old, new) in rewrites {
            let token = "\"\(old)\""
            guard text.components(separatedBy: token).count == 2 else {
                log.error("""
                    \(old, privacy: .public) appears \(text.components(separatedBy: token).count - 1, privacy: .public) \
                    times in \(url.lastPathComponent, privacy: .public)'s manifest, not once, so that \
                    name is left naming its old address
                    """)
                continue
            }
            text = text.replacingOccurrences(of: token, with: "\"\(new)\"")
        }
        guard let newBytes = text.data(using: .utf8),
              (try? JSONDecoder().decode(ProjectBackupManager.ManifestSkeleton.self, from: newBytes)) != nil,
              (try? newBytes.write(to: manifestURL, options: .atomic)) != nil else { return }
        // Both manifests are readable against the moved files, so either outcome is a working
        // package — but a validator that disagrees means the surgery was wrong and the old bytes are
        // the ones that were proved good.
        if !ProjectBackupManager.validateProject(at: url) {
            try? originalBytes.write(to: manifestURL, options: .atomic)
            log.error("""
                The rewritten manifest of \(url.lastPathComponent, privacy: .public) did not validate, \
                so the original bytes were put back; the moved sidecars still resolve
                """)
        }
    }
}

/// **The stem a project's title produces, sanitised the way a directory name has to be.**
///
/// Split out of `ProjectStore.createNewProjectURL`, which trimmed and fell back to "Untitled" and did
/// nothing else — so a brand-new project titled `Boat/Race` was handed straight to
/// `appendingPathComponent("Boat/Race.paintproj")`, where the embedded separator silently created a
/// real subfolder `Boat/` (the staging directory is made `withIntermediateDirectories: true`) and put
/// the project inside it. A 300-character or heavy-ZWJ-emoji title was equally unbounded.
///
/// TODO (57)'s second bullet — the package directory following the title — is where this gets its
/// other caller. It is here now because the first-save path is a live defect today and the fix is one
/// line at the call site.
nonisolated enum ProjectPackageName {

    /// Character cap: what reads as a folder name rather than a paragraph.
    static let maximumStemCharacters = 60
    /// Byte cap, which is the one the filesystem enforces. A component must stay under 255 **bytes**,
    /// and `Trash` appends `__<tag>__<yyyyMMdd-HHmmss>[-XXXX].paintproj` — about 45 — to it. Sixty
    /// `Character`s can be many hundreds of UTF-8 bytes when they are ZWJ or flag sequences, so the
    /// count above is not a bound at all on its own.
    static let maximumStemBytes = 180

    /// The directory stem for `title`, or `"Untitled"` when nothing survives.
    static func stem(forTitle title: String) -> String {
        // `/` and `:` for `ProjectStore.sanitizedFolderName`'s rule and its reasons: one is the path
        // separator, the other is what the classic Finder path separator still means to some APIs.
        var name = title.replacingOccurrences(of: "/", with: " ")
                        .replacingOccurrences(of: ":", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
        // A **loop**, matching `sanitizedFolderName`: a title with two leading dots must not still
        // produce a dot-prefixed folder, which is invisible in Files and skipped by `subfolders`.
        while name.hasPrefix(".") { name.removeFirst() }
        while name.hasSuffix(".") { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.count > maximumStemCharacters || name.utf8.count > maximumStemBytes {
            var out = ""
            var bytes = 0
            for character in name {
                let width = String(character).utf8.count
                if out.count >= maximumStemCharacters || bytes + width > maximumStemBytes { break }
                out.append(character)
                bytes += width
            }
            name = out
        }
        // Truncation can expose a trailing space or dot that was harmless mid-string.
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix(".") { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return "Untitled" }
        // **Compared and stored precomposed.** APFS hands a name back in a different normalisation
        // than the manifest holds, so without this an accented title would compare unequal to its own
        // folder and rename itself on every launch once (57)'s second bullet lands.
        return name.precomposedStringWithCanonicalMapping
    }
}
