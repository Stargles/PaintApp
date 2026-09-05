import Foundation
import os

/// **A stroke's brush, by reference** — BRUSH.md §2.9's *"a stroke holds a small index, not a `Brush`
/// by value"*.
///
/// Four bytes where a `Brush` was 333–386 on the wire and ~150–160 resident (§5.4, MEASURED), and the
/// saving grows rather than shrinks as §6 makes `Brush` larger.
///
/// **A ref is an index into a table, and saying which table is not optional.** In memory there is one
/// table — `BrushPool`, this process's — and a ref means the same brush in every document open in this
/// process, because the pool is addressed by the brush's *value*. On disk there is one table per
/// document (`BrushTable`, written beside `brushes/`), because a file outlives the process that wrote
/// it and its numbers have to be redeemable in a launch that has never seen those brushes.
/// `BrushPool.resolve(_:in:)` is the one crossing between the two.
///
/// Only `BrushPool.intern` and a decode of a `BrushTable` mint one, which is what makes
/// `BrushPool.brush(_:)` total rather than optional: a ref that exists was appended by the pool.
struct BrushRef: Hashable, CustomStringConvertible {
    fileprivate let rawValue: UInt32
    fileprivate init(rawValue: UInt32) { self.rawValue = rawValue }
    var description: String { "brush#\(rawValue)" }
}

extension BrushRef: Codable {
    /// A bare integer on the wire, not `{"rawValue":7}` — `"brush":7` is the whole of §5.4's ~2 bytes,
    /// and a wrapper object would spend eleven characters saying what the key already says.
    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CodingUserInfoKey {
    /// The stored-ref → live-ref translation a decode of document content is given, as a
    /// `BrushTable.Remap`. `ProjectStore` sets it on **every** decoder it points at a package, even
    /// when the table is empty, and that is load-bearing: with the key absent a ref is taken to
    /// address this process's own pool, which is right for an in-memory round trip and would be
    /// silently wrong for a file written by an earlier launch. See `BrushPool.resolve(_:in:)`.
    static let brushTable = CodingUserInfoKey(rawValue: "PaintSoftware.brushTable")!
}

/// **The process's brush table** — append-only, addressed by the brush's value.
///
/// Interning by value is what gives §2.9's deduplication for free and what makes §2.10 fall out
/// rather than needing a rule: editing a brush produces a *different* `Brush` value, so it interns to
/// a different ref, so a stroke already drawn keeps the one it was drawn with. Nothing here ever
/// mutates or removes an entry, so a ref's meaning is fixed for the life of the process — which is
/// why `CanvasView`'s `AppliedTool`, an `Equatable` cache key holding a live `Brush` by value, cannot
/// be defeated by an edit landing in a table entry underneath it: there is no such edit to land.
///
/// **Process-wide, and that is not the hazard CLAUDE.md's static-that-outlives-its-test section
/// describes.** That one is about mutable configuration whose value changes what later code *does*.
/// This is content-addressed and append-only: a later test adding entries cannot change what an
/// earlier ref means, and nothing here is persisted. The one rule it does impose is that **no test may
/// assert a particular numeric ref**, because which integer a brush gets depends on what ran first.
enum BrushPool {
    /// `NSLock` rather than an actor or a queue because every access is a dictionary probe or an array
    /// index and the contention is one acquire per *stroke*, not per dab: `VectorCanvas.render` reads a
    /// stroke's brush once and hands it to `BrushStamper`, which walks hundreds of dabs with it.
    private static let lock = NSLock()
    private static var brushes: [Brush] = []
    private static var refs: [Brush: BrushRef] = [:]

    /// This brush's ref, minting one if the process has not seen this exact value before.
    static func intern(_ brush: Brush) -> BrushRef {
        lock.lock()
        defer { lock.unlock() }
        if let existing = refs[brush] { return existing }
        let ref = BrushRef(rawValue: UInt32(brushes.count))
        brushes.append(brush)
        refs[brush] = ref
        return ref
    }

    /// The brush a ref names. Total, because a `BrushRef` cannot be built from an integer outside this
    /// file and every ref this file mints has already been appended.
    static func brush(_ ref: BrushRef) -> Brush {
        lock.lock()
        defer { lock.unlock() }
        return brushes[Int(ref.rawValue)]
    }

    /// How many distinct brushes this process has interned. Diagnostics and tests only — never a
    /// document-level count, which is `BrushTable.count`.
    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return brushes.count
    }

    /// Whether a raw stored number addresses an entry this process actually holds.
    fileprivate static func holds(rawValue: UInt32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Int(rawValue) < brushes.count
    }

    /// **The one crossing between a file's numbering and this process's** — called by
    /// `VectorStroke.init(from:)` and nothing else.
    ///
    /// With a table in `userInfo` the stored number is the file's, and an entry the table does not
    /// carry is a corrupt payload rather than an old one (§2.14): it throws, `VectorCanvasData`'s
    /// per-element decode counts it as a malformed element, and the artist is told. Without a table
    /// the stored number is this process's own — an in-memory round trip, an undo snapshot, a
    /// pasteboard — and the only check available is that the pool holds it.
    static func resolve(_ stored: BrushRef, in decoder: Decoder) throws -> BrushRef {
        if let remap = decoder.userInfo[.brushTable] as? BrushTable.Remap {
            guard let live = remap[stored] else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath,
                                          debugDescription: "\(stored) is not in this document's brush table"))
            }
            return live
        }
        guard holds(rawValue: stored.rawValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: """
                                          \(stored) does not address this process's brush pool, and the \
                                          decoder was given no document brush table to redeem it against
                                          """))
        }
        return stored
    }
}

/// **One document's brush table** — BRUSH.md §5.4, and the settlement of §13's first open item.
///
/// Every brush any stroke in this document was drawn with, and nothing else. It is **not** the
/// palette (§8.1): `ProjectManifest.selectedBrush` and `.customBrushes` are the brushes the artist can
/// *pick*, this is the brushes their ink was actually *made* with, and §2.10 makes the two populations
/// diverge on purpose — every one-off tweak lands here and none of it lands in the picker.
///
/// **It is a sidecar rather than a key in `manifest.json`, and the reason is in `CelManifest`**: the
/// manifest is decoded in full for every gallery tile, which is why per-cel vector data was pulled out
/// of it in the first place. §2.10 makes this the least bounded thing that could go back in — it grows
/// with every brush the artist edits and then draws with, forever, where `customBrushes` grows only
/// with deliberate imports.
///
/// **The sweep is the table's definition rather than a pass over it, so it cannot half-apply.** There
/// is no stored per-document numbering to renumber: a stroke holds a `BrushRef` into the process pool,
/// and a save writes the refs the document's own content references, each beside the brush it names.
/// Dropping an unreferenced brush is therefore not an edit — it is that brush never being collected.
/// A stroke's number and the table that redeems it are produced by one walk of one snapshot and
/// written by one save; there is no state in between for a half-applied sweep to live in.
struct BrushTable: Equatable {
    /// Stored ref → live ref, what a decode of this document's content is given. A `typealias` because
    /// it travels through `CodingUserInfoKey` as `Any` and the cast at the far end should name
    /// something.
    typealias Remap = [BrushRef: BrushRef]

    /// The brush each referenced ref names, keyed by the ref as it will be (or was) written.
    private(set) var entries: [BrushRef: Brush]

    init(entries: [BrushRef: Brush] = [:]) { self.entries = entries }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    /// The brushes this document's ink is made of, in no particular order. What
    /// `ProjectStore`'s texture copy walks — see `importedTextureFileNames`.
    var brushes: [Brush] { Array(entries.values) }

    /// The identity remap — every stored ref means itself. What a save hands its own encoders, and
    /// what a load of a document written by *this* process's pool comes out as.
    var identityRemap: Remap {
        var remap = Remap(minimumCapacity: entries.count)
        for ref in entries.keys { remap[ref] = ref }
        return remap
    }

    /// **Load: put every entry back in this process's pool and say what its stored number now means.**
    ///
    /// Interning is by value, so a document reopened in the launch that wrote it comes back with an
    /// identity remap and a document from another launch comes back with a real translation — one code
    /// path, and neither case is special.
    func resolvingIntoPool() -> Remap {
        var remap = Remap(minimumCapacity: entries.count)
        for (stored, brush) in entries { remap[stored] = BrushPool.intern(brush) }
        return remap
    }

    /// The artist's own imported files this document's ink needs, which is the honest answer to
    /// *"which textures does this document use"* that BUGS.md says the palette was standing in for.
    /// A built-in tip travels inside the binary and a round tip is arithmetic, so neither is named —
    /// `Brush.importedTextureFileNames` is the whole of that rule and it is stated once. **Since
    /// BRUSH.md §2.25 a brush names up to two files**, its tip's and its paper's, and the accessor is
    /// where that became true rather than here.
    var importedTextureFileNames: Set<String> {
        entries.values.reduce(into: Set<String>()) { $0.formUnion($1.importedTextureFileNames) }
    }

    // MARK: - Collecting

    /// Accumulates the refs a document's content actually references. **The sweep**: a brush the pool
    /// holds but no element names is never offered one, so it is never written.
    struct Collector {
        private var refs: Set<BrushRef> = []

        init() {}

        mutating func add(_ ref: BrushRef) { refs.insert(ref) }

        mutating func add(elements: [VectorElement]) {
            for element in elements {
                if case .stroke(let stroke) = element { refs.insert(stroke.brushRef) }
            }
        }

        /// A derived cel's recipe holds whole `VectorStroke`s of its own — an in-between's ink is
        /// *not* reachable from any cel's display list, so a collector that walked only cels would
        /// write a table missing exactly those brushes and the recipe would fail to decode on the
        /// next load. `ProjectSaveLogicTests` pins it.
        mutating func add(recipe: InterpolationRecipe?) {
            guard let recipe else { return }
            for edit in recipe.localEdits { refs.insert(edit.stroke.brushRef) }
        }

        var table: BrushTable {
            var entries: [BrushRef: Brush] = Dictionary(minimumCapacity: refs.count)
            for ref in refs { entries[ref] = BrushPool.brush(ref) }
            return BrushTable(entries: entries)
        }
    }
}

extension BrushTable: Codable {
    /// A flat array of `{ref, brush}` pairs, ordered by ref.
    ///
    /// A `[BrushRef: Brush]` dictionary would encode as a flat alternating array (Swift's codec does
    /// that for any non-`String`/`Int` key), which is unreadable in a file an artist's work lives in;
    /// and ordering makes two saves of one document differ only where the document does.
    private struct Entry: Codable {
        let ref: BrushRef
        let brush: Brush
    }

    /// **One unreadable entry costs the strokes that name it, not the document.** The same reasoning
    /// `VectorCanvasData`'s per-element decode already applies: a `Brush` written by a newer build with
    /// a tip kind this one does not know would otherwise throw out of the array decode and take every
    /// stroke in the file with it. A skipped entry leaves its ref unmapped, so `BrushPool.resolve`
    /// refuses exactly the strokes that named it and `VectorCanvasData` counts them as malformed —
    /// which is the artist being told, rather than a blank document.
    private struct LossyEntry: Decodable {
        let entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }

    private enum CodingKeys: String, CodingKey { case entries }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let ordered = entries.keys.sorted { $0.rawValue < $1.rawValue }
        try container.encode(ordered.map { Entry(ref: $0, brush: entries[$0]!) }, forKey: .entries)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([LossyEntry].self, forKey: .entries)
        var entries: [BrushRef: Brush] = Dictionary(minimumCapacity: decoded.count)
        for entry in decoded.compactMap(\.entry) { entries[entry.ref] = entry.brush }
        self.entries = entries
    }
}
