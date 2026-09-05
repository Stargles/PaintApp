import Foundation

/// **One named, ordered set of brushes** — a row of the brushes menu's left column, BRUSH.md §7.1
/// and §8.
///
/// ## §8.2 said to reuse the layer tree, and the code refutes it
///
/// The claim was that *"the layer tree is already a complete, tested, persisted, ordered hierarchy
/// with folders"* and that a third hand-rolled tree should not be built. Three facts about that
/// hierarchy say otherwise, and each on its own is decisive:
///
/// 1. **There is no node type to reuse.** `Layer` and `LayerFolder` are two concrete structs, ~700
///    lines between them, and every field is about layers: cel content, `alphaMask`,
///    `compositorRole`, `effect` plus its keyframe tracks, `isFillReference`, blend mode, isolation.
///    Nothing there is generic over a payload, so "reuse" would mean either making `Layer` generic —
///    a refactor of the single most load-bearing type in the app, to gain a brush picker — or
///    instantiating layers as brushes and carrying twenty inert fields per brush.
/// 2. **A folder has no ordering field at all.** `CanvasManager.containerEntries` derives a folder's
///    position from the topmost `layers` index its contents occupy, on the invariant that a folder's
///    layers are a contiguous span. That is elegant for layers, where a folder without contents is a
///    transient state, and it is *unusable* here: an empty group sorts to `Int.max` and lands at the
///    top of its container with no way to place it. An artist who makes a group and then fills it
///    would watch it jump. Brush groups need an order of their own, which is an array.
/// 3. **The owner's own reference shows one level of grouping.** Nesting is the only thing the layer
///    tree would have contributed, and nothing has asked for it.
///
/// So this is a flat `[BrushGroup]`, each holding `[Brush]`, and it is ~40 lines rather than a
/// generalisation of the layer stack. BRUSH.md §8.2 is corrected to say so.
struct BrushGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var brushes: [Brush]

    init(id: UUID = UUID(), name: String, brushes: [Brush] = []) {
        self.id = id
        self.name = name
        self.brushes = brushes
    }
}

/// **The app-level library, as it sits on disk** — BRUSH.md §8.1's first collection.
///
/// Not the document's brush table (`BrushTable`, `brushtable.json`), and neither subsumes the other:
/// this is *the brushes the artist can pick*, that one is *the brushes this file's ink was made
/// with*. §8.1 is the argument; the two are separate types in separate files for the same reason.
///
/// `version` is written and read but nothing branches on it yet. It costs two bytes and it is the
/// difference between a later format change being a migration and being a lost library — BRUSH.md
/// §2.14 makes *documents* expendable, and says nothing about the artist's own brushes.
struct BrushLibraryDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var groups: [BrushGroup]

    init(version: Int = BrushLibraryDocument.currentVersion, groups: [BrushGroup]) {
        self.version = version
        self.groups = groups
    }

    /// What a device with no library file gets — BRUSH.md §8.6's five groups, sixteen brushes and
    /// an empty Texture, authored at §12 stage 9.
    ///
    /// **This used to be one "Basics" group holding all five legacy presets**, because the container
    /// was built a stage before the contents existed. The groups and their ids belong to
    /// `BrushLibrary` now — the library is what §8.6 names, and having the seed re-declare a group
    /// name here is how a shipped set and its seeding drift apart.
    static let basicsGroupID = BrushLibrary.GroupID.basics

    static var seeded: BrushLibraryDocument {
        BrushLibraryDocument(groups: BrushLibrary.groups)
    }
}

extension BrushLibraryDocument {
    /// Every brush in the library, in menu order. What `CanvasManager.availableBrushes` answers.
    var allBrushes: [Brush] { groups.flatMap(\.brushes) }

    /// The group holding a brush, or nil if no group does.
    func group(containingBrush id: UUID) -> BrushGroup? {
        groups.first { $0.brushes.contains { $0.id == id } }
    }
}
