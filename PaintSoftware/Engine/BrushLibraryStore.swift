import Foundation
import Combine
import os

/// **The artist's brush library, persisted across documents** — BRUSH.md §8.1.
///
/// `PaletteStore` is the precedent and this is deliberately its twin: one shared instance so every
/// panel that is torn down and rebuilt on an `activePanel` switch sees the same collection, seeded on
/// first launch, and reset by a launch argument so a UI test starts from a known state.
///
/// **On disk as JSON, not in `UserDefaults`, and that is not a style preference.** CLAUDE.md carries
/// a section on a `UserDefaults`-backed static that outlived the test that set it and produced 15
/// reds in a *later* suite; a defaults key is process-wide, invisible and survives into the next run
/// in the same container. A file has the same persistence hazard — which is why `init(directory:)`
/// exists and every test points it at a temporary directory of its own — but it is *inspectable*,
/// and it sits beside the tip PNGs it names, so the library and the pictures it depends on are one
/// folder rather than two unrelated stores.
///
/// **The root is `BrushStorage`'s, under `Documents` rather than Application Support.** The brief
/// this was built from said Application Support; the directory that actually exists, and that
/// `ProjectStore` copies imported tips into and restores them from, is `Documents/Brushes`. The
/// library file goes *in* it — `library.json` — because a group naming
/// `.stamp(.imported(fileName:))` is meaningless without the file beside it.
///
/// **`init(storage:)` is BRUSH.md §2.27's injection, and it was `init(directory:)` before.** The
/// change is that the root is now a *type's* rather than a URL each caller resolved for itself, so
/// there is one value to point at an external folder later; this store's own behaviour is unchanged,
/// including the file it writes and the bytes in it.
final class BrushLibraryStore: ObservableObject {
    static let shared = BrushLibraryStore()

    private static let log = Logger(subsystem: "PaintSoftware", category: "BrushLibrary")
    static let fileName = "library.json"

    /// The groups, in menu order. Every mutation goes through the methods below rather than through
    /// a settable array, so there is one place that writes the file and one place that keeps the
    /// invariant that a brush id appears in at most one group.
    @Published private(set) var groups: [BrushGroup] {
        didSet { persist() }
    }

    /// **The library's root, held rather than resolved** — BRUSH.md §2.27's second requirement. Two
    /// stores over two storages are two libraries that cannot see each other, which is the state a
    /// relocation has to be testable against and which a static directory could not express.
    private let storage: BrushStorage
    /// Off while `init` is populating `groups`, so seeding does not write a file the artist never
    /// asked for — a device that has never opened the menu keeps an empty `Brushes/` folder.
    private var isLoaded = false

    init(storage: BrushStorage = .shared,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.storage = storage

        // UI tests pass this so a run starts from the seeded library rather than inheriting groups a
        // previous run added — the same job `-resetPalettes` does for `PaletteStore`, and the same
        // reason: an assertion about "the library on a fresh device" is otherwise a lie the second
        // time it runs. No effect on an ordinary launch.
        if arguments.contains("-resetBrushLibrary") {
            storage.remove(Self.fileName)
        }

        groups = Self.loadGroups(from: storage)
        isLoaded = true
    }

    private static func loadGroups(from storage: BrushStorage) -> [BrushGroup] {
        guard let data = storage.read(fileName) else { return BrushLibraryDocument.seeded.groups }
        do {
            let decoded = try JSONDecoder().decode(BrushLibraryDocument.self, from: data)
            // An empty file is a library the artist could not add to and could not pick from, so it
            // is treated as absent rather than honoured.
            return decoded.groups.isEmpty ? BrushLibraryDocument.seeded.groups : decoded.groups
        } catch {
            log.error("The brush library could not be read and was reseeded: \(String(describing: error), privacy: .public)")
            return BrushLibraryDocument.seeded.groups
        }
    }

    private func persist() {
        guard isLoaded else { return }
        let document = BrushLibraryDocument(groups: groups)
        let encoder = JSONEncoder()
        // Sorted so two saves of the same library are the same bytes — which is what lets a test
        // compare a written file against a literal rather than against its own encoder.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try storage.write(encoder.encode(document), to: Self.fileName)
        } catch {
            Self.log.error("The brush library could not be saved: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Reading

    var allBrushes: [Brush] { groups.flatMap(\.brushes) }

    /// The library's own copy of a brush, by id.
    ///
    /// **What makes an edit outlive the process** — BRUSH.md §7 and §12 stage 10.
    /// `CanvasManager.selectedBrush` starts life as the *literal* `BrushLibrary.softRound`, so
    /// without this a relaunch showed the shipped preset's values while the menu row beside it drew
    /// the edited stroke: the library had the edit and the live selection did not. See
    /// `CanvasManager.adoptLibrarySelections`.
    func brush(withID id: UUID) -> Brush? {
        for group in groups {
            if let found = group.brushes.first(where: { $0.id == id }) { return found }
        }
        return nil
    }

    func group(containingBrush id: UUID) -> BrushGroup? {
        groups.first { $0.brushes.contains { $0.id == id } }
    }

    /// The group the menu should open on for a given selection: the one holding it, else the first.
    func groupToOpen(forSelected id: UUID?) -> BrushGroup? {
        if let id, let owner = group(containingBrush: id) { return owner }
        return groups.first
    }

    // MARK: - Groups

    @discardableResult
    func addGroup(name: String = "New Group") -> BrushGroup {
        let group = BrushGroup(name: uniqueGroupName(from: name))
        groups.append(group)
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        guard groups[index].name != trimmed else { return }
        groups[index].name = uniqueGroupName(from: trimmed, excluding: id)
    }

    /// Moves a group `offset` places toward the end of the list (positive) or the start (negative),
    /// clamped. The menu's Move Up / Move Down; ordering is an array index here rather than a derived
    /// span, which is `BrushGroup`'s whole reason for not being a `LayerFolder`.
    func moveGroup(_ id: UUID, by offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(index + offset, 0), groups.count - 1)
        guard destination != index else { return }
        let group = groups.remove(at: index)
        groups.insert(group, at: destination)
    }

    /// Removes a group and every brush in it. Refused for the last group: a library with no groups
    /// has no column to add one from, which is the closed-loop failure CLAUDE.md's
    /// "a feature whose only entry point requires state that only that entry point can create"
    /// section describes.
    @discardableResult
    func removeGroup(_ id: UUID) -> Bool {
        guard groups.count > 1, let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups.remove(at: index)
        return true
    }

    private func uniqueGroupName(from name: String, excluding id: UUID? = nil) -> String {
        let taken = Set(groups.filter { $0.id != id }.map(\.name))
        guard taken.contains(name) else { return name }
        var suffix = 2
        while taken.contains("\(name) \(suffix)") { suffix += 1 }
        return "\(name) \(suffix)"
    }

    // MARK: - Brushes

    /// Adds a brush to a group — the named one, else the last, else a freshly made one.
    ///
    /// Returns the group it landed in, which is what the menu opens onto so the artist sees what
    /// they just imported instead of having to find it.
    @discardableResult
    func add(_ brush: Brush, toGroup groupID: UUID? = nil) -> UUID {
        let index: Int
        if let groupID, let found = groups.firstIndex(where: { $0.id == groupID }) {
            index = found
        } else if !groups.isEmpty {
            index = groups.count - 1
        } else {
            groups.append(BrushGroup(name: "Brushes"))
            index = 0
        }
        // A brush id lives in at most one group, so an add of something already held is a move.
        remove(brushID: brush.id)
        let landing = groups.indices.contains(index) ? index : groups.count - 1
        groups[landing].brushes.append(brush)
        return groups[landing].id
    }

    /// Replaces a brush wherever it lives, by id — what the editor writes through.
    ///
    /// **By id, and the brush's *value* is what changed**, which is the whole of BRUSH.md §2.10: the
    /// edited value interns to a different `BrushRef`, so ink already drawn keeps the brush it was
    /// drawn with, while the library row and the live selection move on.
    func update(_ brush: Brush) {
        for groupIndex in groups.indices {
            if let brushIndex = groups[groupIndex].brushes.firstIndex(where: { $0.id == brush.id }) {
                guard groups[groupIndex].brushes[brushIndex] != brush else { return }
                groups[groupIndex].brushes[brushIndex] = brush
                return
            }
        }
    }

    /// **Mints a brush from the engine's neutral defaults and puts it in a group** — BRUSH.md §7.1's
    /// *"create manually"*, the first arm of the `+`.
    ///
    /// The owner: *"the create brush right now makes you import a brush, but this library feature
    /// opens up the possibility of just taking you straight to the edit menu of a default brush."*
    /// `Brush.manuallyCreated` is what "a default brush" means and carries why it is not a copy of a
    /// preset; this is the half that needs a library — which group it lands in, and a name that is not
    /// already taken.
    ///
    /// **It is here rather than in the `+`'s own view** for the reason `CanvasManager
    /// .importCustomBrush` is: nothing in a `View` is reachable from the logic tier, so a rule written
    /// there is a rule no test can drive.
    @discardableResult
    func createBrush(inGroup groupID: UUID? = nil) -> Brush {
        let brush = Brush.manuallyCreated(named: uniqueBrushName(from: Brush.manualBaseName))
        add(brush, toGroup: groupID)
        return brush
    }

    /// A name no brush in the library already has. Group names are uniqued the same way and for the
    /// same reason: two rows reading the same is two rows an artist cannot tell apart, and — since a
    /// row's accessibility identifier is its name — two elements answering one query.
    private func uniqueBrushName(from name: String) -> String {
        let taken = Set(allBrushes.map(\.name))
        guard taken.contains(name) else { return name }
        var suffix = 2
        while taken.contains("\(name) \(suffix)") { suffix += 1 }
        return "\(name) \(suffix)"
    }

    @discardableResult
    func remove(brushID: UUID) -> Bool {
        for groupIndex in groups.indices {
            if let brushIndex = groups[groupIndex].brushes.firstIndex(where: { $0.id == brushID }) {
                groups[groupIndex].brushes.remove(at: brushIndex)
                return true
            }
        }
        return false
    }

    /// Takes in brushes a project restored that this device's library has never seen — a file made
    /// on another iPad, whose imported tips `ProjectStore` has just copied back into the library.
    /// Without this they would draw correctly and be unpickable.
    ///
    /// Additive and id-keyed, so re-opening the same project twice adds nothing the second time.
    func adopt(_ brushes: [Brush], intoGroupNamed name: String) {
        let unknown = brushes.filter { brush in !groups.contains { $0.brushes.contains { $0.id == brush.id } } }
        guard !unknown.isEmpty else { return }
        if let index = groups.firstIndex(where: { $0.name == name }) {
            groups[index].brushes.append(contentsOf: unknown)
        } else {
            groups.append(BrushGroup(name: name, brushes: unknown))
        }
    }

    // MARK: - Testing

    /// Replaces the whole library. Tests only — the menu has no verb that does this, and the reason
    /// it is not `private` is that a persistence test has to be able to set up a library, drop the
    /// store, and build a second one over the same directory.
    func replaceAll(with groups: [BrushGroup]) {
        self.groups = groups
    }
}
