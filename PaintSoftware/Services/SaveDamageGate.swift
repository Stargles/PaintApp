import Foundation

/// What a project lost on the way in, in the words the artist would use for it.
///
/// **Why this exists at all.** `VectorCanvasData` has decoded its display list one element at a time
/// since `ADD_TEXT.md` stage 2, so a single unreadable entry costs that entry instead of the whole
/// cel — a large improvement that nonetheless left the artist with no way to know it had happened.
/// The counts went to `os_log` and died there, and the next save wrote the survivors over the
/// original. That is the "silently destroy work" case the owner ruled on (2026-08-21): **prompt once,
/// then remember**.
///
/// **What is a loss and what is merely a version gap.** `DecodeReport` already tells a *malformed
/// known kind* apart from an *unknown kind*, and only the first is damage:
///
/// - A malformed known kind is a brush stroke (or fill, image, text) that this build understands
///   perfectly well and cannot read. Something is wrong with the file, the artist made that mark, and
///   it is gone. **Counted here.**
/// - An unknown kind is an element written by a *newer* build of the app. Nothing is wrong with the
///   document, this binary has no feature to render it with, and it was never on screen. **Not
///   counted**, deliberately: prompting on it would raise a banner at every open of a file that is
///   working exactly as the two-step discriminator was designed to make it work, and the artist has
///   no action to take. What protects that element is `ProjectBackupManager` — an older build saving
///   over the file stashes the newer package as a restore point first, so it is recoverable from the
///   gallery's Versions sheet rather than lost.
/// - A vector payload that will not parse *as a payload* costs the cel every mark on it. **Counted**,
///   as a whole drawing, because it is the largest loss of the three.
/// - A placed image whose PNG is missing from the package is **counted**, since the artist put it
///   there and it will not come back.
///
/// **Three failures deliberately absent, because they cannot reach a normal open.**
/// `ProjectBackupManager.validateProject` refuses a package whose manifest is unreadable, whose
/// raster/fill/baked PNGs are missing or truncated, or whose vector JSON file is missing — and the
/// launch-time repair pass restores such a package from its newest intact backup before the gallery
/// ever lists it. A prompt for those would be a prompt for a state the app does not open in.
///
/// **A raster PNG that is absent because it was never written is a fourth thing, and it is not a
/// failure at all.** Since 2026-08-22 a cel whose raster tier holds no bitmap writes no PNG and sets
/// `CelManifest.rasterOmitted` (PERFORMANCE.md item 14). That does not weaken the paragraph above,
/// because the two states stay distinguishable in exactly the place that matters: a cel that *names*
/// a raster and cannot produce it still fails `validateProject`, so "lost" is still unreachable at a
/// normal open, while "never existed" is now ordinary and correctly silent. The line that keeps those
/// apart is the `rasterOmitted != true` guard in `validateProject`; if it is ever loosened into an
/// unconditional skip, this comment stops being true and a lost raster becomes a silent blank cel.
nonisolated struct ProjectLoadDamage: Equatable {

    /// One layer's losses. Flat counters rather than a list of element ids: the artist is owed a
    /// sentence they can act on, and "which stroke, exactly" is a question about a stroke that no
    /// longer exists.
    struct LayerDamage: Equatable {
        var layerName: String = ""
        /// Cels whose vector payload would not parse at all, so every mark on them is gone.
        var drawings: Int = 0
        var brushStrokes: Int = 0
        var fills: Int = 0
        var images: Int = 0
        var texts: Int = 0
        /// A mark whose own kind could not be read either — a legacy payload, or an entry broken at
        /// the discriminator. Counted rather than dropped: the artist lost it whether or not the file
        /// can say what it was.
        var unnamed: Int = 0

        var total: Int { drawings + brushStrokes + fills + images + texts + unnamed }
        var isEmpty: Bool { total == 0 }

        /// Folds another cel's losses on the same layer into this one. The load fans out per cel, so a
        /// layer's total is assembled from as many partial reports as it has cels.
        mutating func merge(_ other: LayerDamage) {
            drawings += other.drawings
            brushStrokes += other.brushStrokes
            fills += other.fills
            images += other.images
            texts += other.texts
            unnamed += other.unnamed
        }

        /// Adds one malformed entry, named by its discriminator when the file could still say what it
        /// was. An unrecognised string lands in `unnamed` rather than inventing a noun for it.
        mutating func countMalformed(kind: String?) {
            switch kind {
            case "stroke": brushStrokes += 1
            case "fill": fills += 1
            case "image": images += 1
            case "text": texts += 1
            default: unnamed += 1
            }
        }

        /// "2 brush strokes and 1 fill" — this layer's losses, without the layer's name.
        var itemPhrase: String {
            var parts: [String] = []
            if drawings > 0 { parts.append(ProjectLoadDamage.counted(drawings, "whole drawing")) }
            if brushStrokes > 0 { parts.append(ProjectLoadDamage.counted(brushStrokes, "brush stroke")) }
            if fills > 0 { parts.append(ProjectLoadDamage.counted(fills, "fill")) }
            if images > 0 { parts.append(ProjectLoadDamage.counted(images, "image")) }
            if texts > 0 { parts.append(ProjectLoadDamage.counted(texts, "text object")) }
            if unnamed > 0 { parts.append(ProjectLoadDamage.counted(unnamed, "mark")) }
            return ProjectLoadDamage.list(parts)
        }
    }

    /// Damaged layers only, in the manifest's own layer order. A clean load leaves this empty, which
    /// is the state every ordinary open is in.
    var layers: [LayerDamage] = []

    var isDamaged: Bool { !layers.isEmpty }
    var itemCount: Int { layers.reduce(0) { $0 + $1.total } }

    /// Records one layer's losses, dropping an empty report so `isDamaged` means what it says.
    mutating func add(_ layer: LayerDamage) {
        guard !layer.isEmpty else { return }
        layers.append(layer)
    }

    /// The banner's first line: what could not be read, named the way the layer panel names it.
    ///
    /// **Two layers are named and the rest are counted.** A project damaged in one place is the case
    /// worth being specific about; a project damaged in nine is a case where the artist needs to know
    /// the scale and then go and look, and nine layer names in a banner is a wall of text nobody
    /// reads. Empty string for a clean load — nothing should ever ask.
    var summary: String {
        guard isDamaged else { return "" }
        var clauses = layers.prefix(2).map { "\($0.itemPhrase) on the \($0.layerName) layer" }
        let rest = layers.dropFirst(2)
        if !rest.isEmpty {
            let items = rest.reduce(0) { $0 + $1.total }
            clauses.append("\(Self.counted(items, "more item")) on \(Self.counted(rest.count, "other layer"))")
        }
        return "\(Self.list(clauses)) could not be read when this project opened."
    }

    /// The banner's second line: what each of the two buttons does, said before either is pressed.
    ///
    /// **Cancel is the half that has to be spelled out.** "Save Anyway" is self-describing and
    /// "Cancel" is not — on its own it reads as "lose what I just drew", which is the one thing it
    /// must never mean. Saying where the work goes is what makes the safe choice look safe.
    static let consequence = """
        Save Anyway writes the project without them. Cancel leaves the project file exactly as it is \
        and keeps your changes as a version you can restore from the gallery.
        """

    /// "1 fill" / "2 fills". Plural by appending an `s`, which is correct for every noun this type
    /// uses and is the reason those nouns were chosen ("text object", not "text").
    static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// "a", "a and b", "a, b and c" — the Oxford comma deliberately absent, matching the app's other
    /// artist-facing sentences.
    static func list(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }
}

/// Who asked for this save.
///
/// The distinction is the whole of the owner's ruling: a prompt is only acceptable in front of a save
/// the artist started. `ContentView` has exactly two save call sites and they are one of each, so this
/// is a real property of the caller rather than a guess made downstream.
nonisolated enum SaveIntent: Equatable {
    /// The artist tapped the gallery button. There is a person looking at the screen, waiting, who
    /// can be asked a question.
    case artist
    /// The scene left `.active` — the app is being backgrounded or interrupted. There may be no
    /// screen to present on and no time to present it in, and iOS may suspend the process at any
    /// moment. **Never blocks.**
    case automatic
}

/// What a save should do, given what the project lost on the way in.
nonisolated enum SaveDecision: Equatable {
    /// Write the project package, the ordinary path.
    case write
    /// Write a full package into the project's version history and leave the project file untouched.
    /// The artist's edits are safe and the damaged original is still there to be decided about.
    case writeAside
    /// Write nothing. Raise the banner and wait for an answer.
    case ask
}

/// Whether a save may overwrite a project that loaded with something unreadable.
///
/// The owner's ruling, 2026-08-21, in three lines of code: **prompt once, then remember.** A banner
/// naming what could not be read, with Save Anyway / Cancel, in front of the first artist-initiated
/// save — and never again for that document.
///
/// **"Never block an automatic save" is the rule the rest is arranged around.** A modal over an app
/// being backgrounded is unacceptable and may not even be presentable, and refusing the save outright
/// would lose the artist's last edits to the next jetsam kill. So an automatic save on an unanswered
/// damaged document writes a complete package into `Documents/Backups/<projectID>/` instead — the
/// same place the gallery's Versions sheet already reads from — and does not touch the project file.
/// Nothing is lost and nothing is decided.
///
/// **"Remember" is in memory, for the life of the open document, and does not need to be persisted.**
/// The document heals itself: Save Anyway rewrites the package *without* the unreadable entries, so
/// the next load of that project produces a clean report and there is nothing left to ask about. And
/// if the artist cancels, the damage is still on disk — so the next load produces the same report
/// again and asks again, which is right, because they have not answered yet. A persisted "don't ask
/// me" flag would be a promise to stay silent about a file that is still broken; the in-memory one
/// cannot make that mistake.
///
/// **Why a prompt at all, when the last good copy is already on disk.** `BUGS.md`'s entry on
/// `validateProject` says the loss is "recoverable, not final", and that is true as far as it goes:
/// `ProjectStore.writeAtomically` calls `ProjectBackupManager.stashLiveProjectForSave` on every save,
/// which *moves* the live package into `Backups/<projectID>/auto-<timestamp>.paintproj` before the new
/// one is renamed into place — verified in the code, not taken from the doc. So the intact original
/// does survive the first overwrite.
///
/// **It does not survive the sixth.** `pruneBackups` keeps `maxAutosaveBackupsPerProject` (5) auto
/// slots, and `refreshLatestSnapshot` overwrites `latest.paintproj` with the just-saved — degraded —
/// package on every save. A damaged project opened and saved six times has no intact copy anywhere,
/// and nothing along the way said a word. That is the difference between a safety net and a decision,
/// and it is why this asks rather than merely surfacing what already exists: the artist gets the
/// choice while the good copy is still there.
///
/// A value type with no view in it, for `ScenePhaseSaveGate`'s reason one file over: the rule is the
/// part worth pinning headlessly, and it is silent when wrong.
nonisolated enum SaveDamageGate {

    /// The decision, given the document's damage, whether the artist has already answered for it, and
    /// who asked for the save.
    ///
    /// **A clean document short-circuits before anything else is consulted**, so the overwhelmingly
    /// common case pays one `isEmpty` and behaves exactly as it did before this feature existed.
    static func decide(damage: ProjectLoadDamage, answered: Bool, intent: SaveIntent) -> SaveDecision {
        guard damage.isDamaged, !answered else { return .write }
        return intent == .artist ? .ask : .writeAside
    }
}
