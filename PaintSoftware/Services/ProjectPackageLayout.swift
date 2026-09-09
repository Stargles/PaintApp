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

    /// Every directory this type can create inside a package, named once rather than as a literal
    /// list — `drawings`, `images`, `videos`. `brushes/` is not one of them: it belongs to
    /// `ProjectStore.copyCustomBrushTexturesIntoProject`, which already refuses to create it empty.
    static var contentDirectories: [String] { Set(Role.allCases.map(\.directory)).sorted() }

    /// **Removes any of the three content directories that is empty, and returns which ones went.**
    ///
    /// `createDirectories` above makes the *writer* exact, and the artist still ends up looking at an
    /// empty folder by two routes it does not cover. The migration is the loud one: `tidy` moves a
    /// legacy vector-only package's sidecars into `drawings/` and leaves the `images/` they came out
    /// of standing there empty — which is the owner's own complaint arriving one door over, at
    /// exactly the launch they would open Files to check the update. The quiet one is the writer's
    /// own: a role is added to the set from the snapshot, and the encode or the asset copy that was
    /// supposed to fill it can still fail, so a save can stage a `videos/` with no clip in it.
    ///
    /// **`rmdir(2)` rather than `contentsOfDirectory` then `removeItem`.** The kernel refuses a
    /// non-empty directory itself, in one call, with no window between the check and the removal —
    /// so this cannot delete a file under any interleaving, which is not a property the
    /// check-then-remove version has. It is also cheap enough to run on every package at every
    /// launch: three syscalls that fail instantly against the one manifest read the pass already
    /// pays. `ENOTEMPTY` and `ENOENT` are both the ordinary answer and neither is logged.
    @discardableResult
    static func pruneEmptyContentDirectories(in package: URL) -> [String] {
        var removed: [String] = []
        for directory in contentDirectories {
            let url = package.appendingPathComponent(directory, isDirectory: true)
            let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return rmdir(path)
            }
            if status == 0 { removed.append(directory) }
        }
        return removed
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
        /// At least one sidecar moved out of `images/`, or the directory was renamed to follow the
        /// title. Carries the package's URL **as it is now**, which is the new one after a rename.
        case tidied(URL)
        /// Nothing to do: already in the new layout under the right name, or a raster-only document
        /// with no sidecars whose directory already says what the project is called.
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
        /// Package directories whose name was made to follow their title — TODO (57) part 2. The
        /// **new** `lastPathComponent` of each, which is what the gallery will list.
        var renamed: [String] = []
        /// Package ids seen more than once in one walk — see `tidyEveryProject`.
        var duplicateProjectIDs: [String] = []
        /// Empty content directories removed, `<package>/<directory>` each — see
        /// `pruneEmptyContentDirectories`.
        var emptiedDirectories: [String] = []
        var seconds: Double = 0

        var isEmpty: Bool {
            tidied.isEmpty && movedFiles == 0 && renamed.isEmpty && emptiedDirectories.isEmpty
        }
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
            let pass = tidy(packageAt: url, migrating: safe)
            // **The duplicate-id backstop.** `ProjectSummary` is `Identifiable` by the manifest id,
            // so two packages sharing one give SwiftUI's `ForEach` two rows with one identity and one
            // of them may simply never draw — an orphan on disk the artist cannot see. Nothing in
            // this item can produce that shape (it renames no package directory), but the walk is
            // already here, the id came out of the read the pass had to do anyway, and the check is
            // one dictionary insert.
            if let id = pass.projectID {
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
            if let renamedTo = pass.renamedTo { report.renamed.append(renamedTo) }
            // Named `<package>/<directory>`, because "images" on its own says nothing about which of
            // two hundred packages shed it — and under the package's name **as it is now**, since a
            // rename in the same pass has already moved it.
            let packageName = pass.renamedTo ?? url.lastPathComponent
            report.emptiedDirectories += pass.emptied.map { "\(packageName)/\($0)" }
            switch pass.outcome {
            case .tidied(let tidied):
                report.tidied.append(tidied.lastPathComponent)
                report.movedFiles += pass.movedFiles
            case .unchanged:            report.unchanged += 1
            case .skippedDamaged:       report.skippedDamaged += 1
            case .skippedForeignVolume: report.skippedForeignVolume += 1
            }
        }
        report.seconds = CFAbsoluteTimeGetCurrent() - started
        if !report.isEmpty || report.skippedDamaged > 0 || report.skippedForeignVolume > 0 {
            log.info("""
                Project layout pass: \(report.tidied.count, privacy: .public) tidied \
                (\(report.movedFiles, privacy: .public) sidecars moved, \
                \(report.renamed.count, privacy: .public) directories renamed to follow their title, \
                \(report.emptiedDirectories.count, privacy: .public) empty content folders removed), \
                \(report.unchanged, privacy: .public) already tidy, \
                \(report.skippedDamaged, privacy: .public) skipped as damaged, \
                \(report.skippedForeignVolume, privacy: .public) skipped on a root this pass will not \
                rename inside, in \(report.seconds, privacy: .public) s
                """)
        }
        return report
    }

    /// What one package's pass produced, for the walk above: the outcome, plus two facts the walk
    /// would otherwise have to re-read the manifest to learn.
    private struct PackagePass {
        var outcome: TidyOutcome
        var projectID: UUID?
        var movedFiles = 0
        /// The package directory's new `lastPathComponent`, when TODO (57) part 2's rename fired.
        var renamedTo: String?
        /// Bare directory names this pass removed because they were empty — the sweep.
        var emptied: [String] = []
    }

    /// One package, moved into the new layout in place.
    ///
    /// **Move, never copy, and delete no file.** TODO (36)'s migration copies before it removes
    /// because it crosses two roots that may be different volumes; this one moves files *within one
    /// package on one volume*, where `rename(2)` is atomic, so a copy would add a window rather than
    /// remove one. The invariant is therefore stronger than (36)'s: **every file is complete at
    /// exactly one of two known addresses at every instant, and the reader knows both.** The package
    /// directory itself is never staged, cloned or removed.
    ///
    /// The one removal in the pass is step 8's sweep, and it is not an exception to that sentence:
    /// `rmdir(2)` on a *content directory* the moves emptied, which the kernel refuses outright if
    /// anything is inside it. It cannot reach a file under any interleaving.
    ///
    /// **Crash-resume is nothing**: every step is individually atomic and conditioned on what is on
    /// disk, so the next launch re-runs and finishes whatever is left. A third run changes nothing.
    ///
    /// | killed during | on disk | what the app does |
    /// |---|---|---|
    /// | the directory rename | one name or the other, both complete packages | opens normally; `origin.name` already names the new one |
    /// | a sidecar move | the file at `images/` **or** at `drawings/`, never neither, never both | the reader probes `images/` then `drawings/`; the cel loads whole |
    /// | between moves | some moved, some not, manifest still bare | every file resolves; the next run moves the rest |
    /// | the manifest write | the old manifest or the new one, never a partial one (`.atomic`) | old manifest + moved files still resolves via the alternate address |
    /// | the sweep | the emptied directory is there or gone, and `rmdir` is one syscall | either way nothing reads it; the next run finishes it |
    /// | after the manifest write | fully tidy | nothing left to do |
    @discardableResult
    static func tidy(packageAt url: URL) -> TidyOutcome {
        tidy(packageAt: url, migrating: migrationIsSafe(at: ProjectBackupManager.documentsDirectory)).outcome
    }

    private static func tidy(packageAt url: URL, migrating: Bool) -> PackagePass {
        let fm = FileManager.default
        // Reassigned by the directory rename in step 5, so every path below is derived from it rather
        // than captured before it.
        var url = url

        // 1. One manifest read, which is all a package already in the new layout ever costs. It is
        //    used by the work scan, by the move walk, and as the compare-and-swap's baseline.
        guard let originalBytes = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
              let skeleton = try? JSONDecoder().decode(ProjectBackupManager.ManifestSkeleton.self,
                                                       from: originalBytes) else {
            return PackagePass(outcome: .skippedDamaged)
        }
        let projectID = skeleton.id

        // 2. Is there anything to do? **Asked before the integrity check, deliberately**, because
        //    that check stats and PNG-sniffs every file the package names and `repairCorruptedProjects`
        //    has already paid for exactly that walk moments earlier. Every launch after the first
        //    would otherwise double the launch's I/O over the whole library to accomplish nothing.
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        var work: [(cel: UUID, role: Role, recorded: String)] = []
        for layer in skeleton.layers {
            for cel in layer.cels {
                guard let celID = cel.id else { continue }
                for role in [Role.drawing, .animation, .interpolation] {
                    guard let recorded = cel.fileName(for: role), !recorded.contains("/"),
                          fm.fileExists(atPath: imagesDir.appendingPathComponent(recorded).path) else { continue }
                    work.append((celID, role, recorded))
                }
            }
        }

        // 3. Does the directory name still say what the project is called? — TODO (57) part 2, the
        //    backlog half. A project retitled under a build that shipped before this one has no "the
        //    title changed in this save" event left for the save path to catch, so the launch pass
        //    asks the broad question instead: *is this stem an acceptable rendering of the title
        //    today?* After the first pass the two rules agree forever, because nothing but a title
        //    ever names a package.
        //
        //    **It costs a string comparison for a package whose name is already right**, which is the
        //    steady state and is why this sits beside the work scan rather than behind the integrity
        //    check: `reconciled` returns nil on `stem == desired` before it lists anything.
        let renameTarget = skeleton.name.flatMap {
            ProjectPackageName.reconciled(url, title: $0, projectID: projectID)
        }

        guard !work.isEmpty || renameTarget != nil else {
            // **The sweep still runs on a package with no work**, which is the whole reason it is
            // three `rmdir`s rather than three directory listings: a package tidied by an earlier
            // launch of this build (before the sweep existed) or one whose save staged a directory
            // it then failed to fill is exactly the package that reaches here, and it is the one
            // holding the empty folder. Gated on `migrating` like every other mutation in this pass,
            // even though removing an empty directory cannot lose a byte — one gate, one argument.
            let emptied = migrating ? pruneEmptyContentDirectories(in: url) : []
            return PackagePass(outcome: emptied.isEmpty ? .unchanged : .tidied(url),
                               projectID: projectID, emptied: emptied)
        }
        guard migrating else { return PackagePass(outcome: .skippedForeignVolume, projectID: projectID) }

        // 4. A package whose files do not add up is the repair pass's business, not ours — and a
        //    package whose manifest we could not read has no title either, so it must not be renamed.
        guard ProjectBackupManager.validateProject(at: url) else {
            return PackagePass(outcome: .skippedDamaged, projectID: projectID)
        }

        // 5. Rename the directory to follow the title. **Through `PackageRenameGate`**, which refuses
        //    outright if the artist has this package open in this process — see that type for the
        //    silent two-package fork this is the fix for.
        var renamedTo: String?
        if let renameTarget {
            let landed = PackageRenameGate.renamingIdlePackage(at: url) { () -> URL? in
                // `origin.name` **before** the move: it is `backupDirectory(forProjectAt:)`'s fallback
                // for a package whose manifest has gone unreadable, and a crash between the two lines
                // is better spent naming a package about to appear than one already gone.
                ProjectBackupManager.noteProjectRenamed(projectID: projectID,
                                                        to: renameTarget.lastPathComponent)
                do {
                    try fm.moveItem(at: url, to: renameTarget)
                    return renameTarget
                } catch {
                    // Put the marker back and carry on under the old name. Nothing is lost: the
                    // package is complete where it always was, and the next launch retries.
                    ProjectBackupManager.noteProjectRenamed(projectID: projectID,
                                                            to: url.lastPathComponent)
                    log.error("""
                        \(url.lastPathComponent, privacy: .public) could not be renamed to \
                        \(renameTarget.lastPathComponent, privacy: .public) and keeps its old name: \
                        \(String(describing: error), privacy: .public)
                        """)
                    return nil
                }
            }
            if let landed {
                renamedTo = landed.lastPathComponent
                url = landed
            }
        }

        // 6. Move the sidecars.
        var rewrites: [(old: String, new: String)] = []
        var madeDrawingsDirectory = false
        for item in work {
            let source = url.appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent(item.recorded)
            let relative = recordedName(for: item.role, cel: item.cel)
            let destination = resolve(relative, in: url)
            // **Both addresses occupied means something outside this flow wrote one of them**,
            // because a rename cannot leave both. The conservative answer is to touch neither and
            // say so.
            //
            // **`moveItem` would refuse an occupied destination anyway**, which a mutation proved:
            // deleting this branch entirely leaves every assertion green, because the throw below
            // produces the same "nothing moved, nothing rewritten" outcome. It stays because the
            // difference is what gets *said* — a sentence naming the file and the reason, rather
            // than an opaque `NSFileWriteFileExists` in a log nobody is reading — and because the
            // wrong repair for that error is the plausible one: removing the destination first. That
            // is the mutation the test does catch.
            if fm.fileExists(atPath: destination.path) {
                log.error("""
                    \(item.recorded, privacy: .public) exists at both its old and its new address in \
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
                rewrites.append((item.recorded, relative))
            } catch {
                // Left where it is, which the resolver still finds. The next run retries.
                log.error("""
                    \(item.recorded, privacy: .public) could not be moved out of images/ in \
                    \(url.lastPathComponent, privacy: .public) and stays where it is: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }
        guard !rewrites.isEmpty else {
            // A rename with no sidecars to move is still a pass that changed the library. The sweep
            // runs here too: `madeDrawingsDirectory` above can have created a `drawings/` that every
            // move then failed to put anything in.
            let emptied = pruneEmptyContentDirectories(in: url)
            let changed = renamedTo != nil || !emptied.isEmpty
            return PackagePass(outcome: changed ? .tidied(url) : .unchanged,
                               projectID: projectID, renamedTo: renamedTo, emptied: emptied)
        }

        // 7. Rewrite the manifest to name the new addresses. Everything here is optional work: the
        //    files already resolve through `existingURL` whether or not it lands. **Resolved against
        //    the post-rename `url`**, which is the whole reason step 5 reassigns it rather than
        //    keeping two variables.
        rewriteManifest(at: url.appendingPathComponent("manifest.json"), in: url,
                        originalBytes: originalBytes, rewrites: rewrites)

        // 8. The sweep. **After the manifest rewrite, not before**: the moves above are what can
        //    empty `images/`, and a vector-only package written before (57) is exactly the one whose
        //    `images/` held nothing but the sidecars that just left. Leaving it standing would put an
        //    empty folder beside `drawings/` at the one launch the artist opens Files to look.
        let emptied = pruneEmptyContentDirectories(in: url)
        return PackagePass(outcome: .tidied(url), projectID: projectID,
                           movedFiles: rewrites.count, renamedTo: renamedTo, emptied: emptied)
    }

    /// The one step that can destroy data, and the two lines that stop it.
    ///
    /// **Internal rather than private so a test can hand it bytes that are genuinely stale.** That
    /// is not a convenience: `tidy` reads the manifest at the instant it is called, so a test that
    /// changes the file and *then* calls `tidy` gives the compare-and-swap two copies of the same
    /// value and passes whether the guard is there or not — which is what the first version of
    /// `testAManifestThatChangedUnderTheMigrationIsNotOverwritten` did, and a mutation of this very
    /// line is what found it. The staleness has to come from the caller for the check to be about
    /// anything.
    static func rewriteManifest(at manifestURL: URL, in url: URL,
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

    // MARK: - Reconciling a package's directory name against its title — TODO (57) part 2

    /// **The name `current` should have, given `title` — or nil for "leave it alone".**
    ///
    /// The owner, 2026-09-08: *"Folder names are Untitled.paintproj but does not change when the
    /// project name is changed."* They were right about the cause: `createNewProjectURL` runs once,
    /// on a document's very first save, and nothing has ever re-derived the directory name since.
    ///
    /// Nil is the answer far more often than a URL, and the two nil cases are the whole rule:
    ///
    ///  - **The stem already is the title.** Compared precomposed, because APFS hands a name back in
    ///    a different Unicode normalisation than the manifest holds and an accented title would
    ///    otherwise rename itself on every single launch.
    ///  - **The stem is a *disambiguated rendering* of this exact title** — `Boat 2` for `Boat`.
    ///    Without this clause a second project called "Boat" is renamed to "Boat" (taken, so
    ///    "Boat 2") and back on every save forever, because the disambiguation is invisible to a
    ///    plain equality check.
    ///
    /// Otherwise: the first free of `desired`, `desired 2`, `desired 3`, … **in `current`'s own
    /// parent directory**. A rename never moves a project between folders — "Move to…" owns that —
    /// and a title is not a filing instruction.
    ///
    /// A candidate counts as free when it does not exist, when it *is* `current` compared
    /// case-insensitively (iOS's APFS volume is case-insensitive, so a retitle that changes only
    /// case must not disambiguate itself into "Boat 2" — a case-only `rename(2)` is MEASURED to
    /// succeed on this volume), or when the package occupying it already carries `projectID` — it is
    /// this same project, so that path is ours to take.
    static func reconciled(_ current: URL, title: String, projectID: UUID?) -> URL? {
        let desired = stem(forTitle: title)
        let stem = current.deletingPathExtension().lastPathComponent
            .precomposedStringWithCanonicalMapping
        if stem == desired { return nil }
        if isDisambiguation(stem, of: desired) { return nil }

        let parent = current.deletingLastPathComponent()
        var candidate = desired
        // Bounded rather than `while true`: a thousand projects called "Boat" in one folder is not a
        // library, and the failure this bound produces — nil, meaning "leave the name alone" — is the
        // one that costs nothing.
        for suffix in 2...1000 {
            let url = parent.appendingPathComponent("\(candidate).paintproj")
            if isFree(url, forPackageAt: current, projectID: projectID) { return url }
            candidate = "\(desired) \(suffix)"
        }
        return nil
    }

    /// `"Boat 2"` is a disambiguation of `"Boat"`; `"Boat II"` and `"Boatyard"` are not.
    ///
    /// A hand-written prefix-and-digits check rather than a regular expression, because `desired` is
    /// artist-typed text and would have to be escaped into a pattern — one forgotten escape and a
    /// title containing `(` decides every name is a disambiguation of it.
    static func isDisambiguation(_ stem: String, of desired: String) -> Bool {
        guard stem.hasPrefix(desired + " ") else { return false }
        let tail = stem.dropFirst(desired.count + 1)
        return !tail.isEmpty && tail.allSatisfy(\.isNumber)
    }

    private static func isFree(_ candidate: URL, forPackageAt current: URL, projectID: UUID?) -> Bool {
        if !FileManager.default.fileExists(atPath: candidate.path) { return true }
        // **The case-only retitle on a volume that folds case**, first because it is the cheap one —
        // a string compare where the clause below reads and decodes a manifest. There, `fileExists`
        // says the name is taken while the thing it found *is* the package being renamed, and without
        // this the artist's project becomes "Boat 2" for capitalising one letter.
        //
        // **MEASURED 2026-09-09: iOS does not fold case, so no test in this repo can catch a mutation
        // of this line, and it stays anyway.** The app container's volume answers `fileExists` false
        // for `Boat.paintproj` while `boat.paintproj` exists — while the host Mac's volume, probed the
        // same day, answers true, so reasoning from the Mac would have been wrong. On a case-sensitive
        // volume the `!fileExists` line above already answers and this one is never reached.
        //
        // It is not dead code: TODO (36) lets the library root be a folder in Files — an SMB share or
        // an external volume among them — and **the save path renames on any root**, since only the
        // launch pass is gated by `migrationIsSafe`. A guard for a volume the simulator is not,
        // deliberately kept and labelled rather than deleted because it is untestable here.
        if candidate.path.precomposedStringWithCanonicalMapping
            .compare(current.path.precomposedStringWithCanonicalMapping,
                     options: .caseInsensitive) == .orderedSame { return true }
        // Occupied by this same project — which happens when two overlapping saves both aim here, and
        // is the case `writeAtomically` turns into a restore point rather than a clobbering.
        if let projectID, ProjectBackupManager.manifestID(at: candidate) == projectID { return true }
        return false
    }
}

/// **The one gate every `.paintproj` directory rename passes through, and why there has to be one.**
///
/// TODO (57) part 2 gives a package's directory name two independent authors: the launch pass
/// (`ProjectPackageLayout.tidy`) and the save (`ProjectStore.writeAtomically`). Both compute
/// `ProjectPackageName.reconciled` from the same two inputs — the on-disk title, and which names are
/// free in the parent — and neither can see the other's answer. An adversarial review traced the
/// fork that falls out of that, and it is silent:
///
/// > the artist opens a project the launch pass has not reached yet and retitles it. The pass renames
/// > the directory from `url` to `targetA`, computed from the **stale** pre-session title it read.
/// > The save independently computes `targetB` from the artist's **new** title, finds `targetB` free
/// > (the pass put the package at `targetA`), and its `moveItem` simply succeeds. Two packages, one
/// > manifest id, forever — and `ProjectSummary` is `Identifiable` by that id, so SwiftUI's `ForEach`
/// > gets two rows with one identity and one of them may never draw.
///
/// **Re-running `reconciled` immediately before the swap does not close this**, which is worth
/// stating because it is the obvious fix: the second answer is computed from the same stale `url`,
/// finds `targetB` free exactly as the first did, and returns it again. The review's own closing
/// clause admits as much — such a check "does not catch a source directory relocated to a THIRD
/// address". `writeAtomically` re-runs it anyway, because it *does* close the narrower window where
/// another save took the name; it is not what makes the fork impossible.
///
/// What makes it impossible is this: **the launch pass never renames a package this process has
/// open**, and the check and the rename happen under one lock, so a project cannot become open in
/// between. A package the artist is working in has exactly one name-giver — its own save — and one
/// name-giver cannot fork.
///
/// There is deliberately **no `noteClosed`**. A package stays registered for the life of the process,
/// which costs only that the launch pass declines to rename something the artist opened during it —
/// and the save renames that one anyway, the moment its title changes. The pass runs once per launch;
/// leaving a name stale until the next one is the direction that loses nothing.
nonisolated enum PackageRenameGate {
    private static let lock = NSLock()
    private static var openPackages: Set<String> = []

    /// Case-folded and normalised, because the volume is: `boat.paintproj` and `Boat.paintproj` are
    /// one directory here, and a registry that thought otherwise would let the pass rename an open
    /// package whose case the artist had just changed.
    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    /// **The artist has this package open in this process.** Called at the top of every load and
    /// every save, which is the earliest either one knows which URL it is about to work on — earlier
    /// than `CanvasManager.projectURL` is assigned, and that gap is the window the registry exists to
    /// cover.
    static func noteOpen(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        openPackages.insert(key(url))
    }

    /// The save's side. It **always** proceeds — the caller *is* the open document, and refusing to
    /// rename here would be refusing the feature — but under the same lock the launch pass takes, so
    /// the two can never interleave. `body` returns the URL the package actually landed at, and the
    /// registry follows it there.
    static func renamingOpenPackage(from url: URL, _ body: () -> URL?) -> URL? {
        lock.lock(); defer { lock.unlock() }
        let landed = body()
        if let landed, key(landed) != key(url) {
            openPackages.remove(key(url))
            openPackages.insert(key(landed))
        }
        return landed
    }

    /// The launch pass's side. Refuses outright when the package is open, and otherwise runs `body`
    /// under the lock so the answer cannot go stale between the check and the `rename(2)`.
    static func renamingIdlePackage(at url: URL, _ body: () -> URL?) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard !openPackages.contains(key(url)) else { return nil }
        return body()
    }

    /// Whether this process has `url` open. Read by nothing in the app — it exists so a test can
    /// assert the registry is what refuses a rename, rather than inferring it from the refusal.
    static func isOpen(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return openPackages.contains(key(url))
    }

    /// **Test seam.** The registry is process-wide and has no `noteClosed`, so one suite's saves
    /// would otherwise silently disarm the launch pass for every suite that ran after it in the same
    /// process — a green test that measured nothing.
    static func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        openPackages.removeAll()
    }
}
