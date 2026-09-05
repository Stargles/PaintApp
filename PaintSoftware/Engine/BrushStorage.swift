import Foundation

/// **The one place the brush library's files live** — BRUSH.md §2.27.
///
/// The owner: *"Right now all the files are stored internally on the app, which means that if the
/// app gets deleted, then all the files get deleted too. I'd like it to be able to have an external
/// folder, so build the architecture so that in the future when this feature gets added, moving the
/// library from internal app storage to this external folder is easy."*
///
/// **The external folder is not built here.** What is built is the property that makes it a small
/// change rather than an audit, and §2.27 states it as three requirements:
///
/// 1. *Every stored reference is a name, never a path.* Already true — `BrushTextureRef.imported`
///    carries a file name and `BrushTip`/`BrushTextureSettings` carry that ref, so nothing a brush,
///    a `library.json`, a `brushtable.json` or a project manifest holds encodes anybody's directory
///    layout. This type is what makes that keep paying: it is the only thing that turns a name into
///    a location, so there is nowhere else for a path to be minted and stored.
/// 2. *Every file lives under one root.* `BrushLibrary.customBrushesDirectory` was a computed
///    `static var` that five callers each resolved for themselves, so there was no single value to
///    change. There is one now, and it is `root` below.
/// 3. *Every access goes through that one type.* `read`, `write`, `contains`, `remove` and
///    `fileNames` are the whole of what the app does to a library file, and they are the five places
///    a security-scoped bookmark would be opened and closed. **That is the seam and it is
///    deliberately empty**: an external folder on iOS is a bookmarked URL that has to be
///    `startAccessingSecurityScopedResource`'d around each access, and §9.2 rules that a mechanism
///    nobody has measured a need for is not built. Five one-line brackets is the whole of what that
///    feature adds here.
///
/// **`relocate(to:)` drops the caches that were read out of the old root, and that is a correctness
/// requirement rather than tidiness.** `BrushTextureStore` memoizes a mask against a
/// `BrushTextureRef` — a *name* — and `BrushTextureMaskCache` holds a depth-adjusted copy of that.
/// Neither key names the root, which is fine while there is one root for the life of a process and
/// is RENDER.md §3.8's family of bug the moment there is not: the same name under a new root would
/// be served the old root's pixels, and a name whose file was missing before the move would stay
/// missing forever off a negative entry. Keying the root into two caches to hold entries that a
/// relocation invalidates anyway is the more expensive way to be correct.
///
/// **Injected rather than global.** `shared` is *the app's* library and everything that means "the
/// artist's brushes" reads it; `BrushLibraryStore` takes a storage by init because two libraries
/// over two roots is a state a test has to be able to build, and `BrushLibraryStore.init(directory:)`
/// was already that shape before this existed. What is deliberately *not* offered is a per-call
/// storage parameter on `BrushTextureStore` or `BrushTipImport`: their cache and their writes are
/// process-wide, so a parameter would let one caller write a tip into a root the renderer does not
/// read from — an incoherence the single global could not express and this must not introduce.
final class BrushStorage {

    /// The app's library. `Documents/Brushes`, which is where every file already was — §2.27 moves
    /// the *ownership* of that value, not the value.
    static let shared = BrushStorage(root: BrushStorage.applicationRoot)

    /// **Under `Documents`, not Application Support**, which is what `BrushLibraryStore`'s own note
    /// records: the directory that exists, and that `ProjectStore` copies imported tips into and
    /// restores them from, is `Documents/Brushes`.
    ///
    /// It does not create the directory. The old `customBrushesDirectory` did, on every read, which
    /// made a getter that answers "where" also a getter that has a side effect; `write` creates it
    /// when there is something to put in it, and a device that has never imported a brush keeps no
    /// empty folder.
    static var applicationRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brushes", isDirectory: true)
    }

    /// Guards `_root` alone. Every method below takes it for one read; the file work happens outside
    /// it, so a slow write cannot block a relocation or another reader.
    private let lock = NSLock()
    private var _root: URL

    init(root: URL) {
        _root = root
    }

    /// Where this storage's files are, right now.
    var root: URL {
        lock.lock()
        defer { lock.unlock() }
        return _root
    }

    /// **Points this storage at a different directory** — the verb a future external folder arrives
    /// through, and the one this feature exists to make cheap.
    ///
    /// The files are expected to have moved with it: every reference the app stores is a name
    /// (§2.27's first requirement), so a library whose folder was moved is found again with nothing
    /// rewritten. See the type's note for why the derived caches are dropped.
    func relocate(to newRoot: URL) {
        lock.lock()
        _root = newRoot
        lock.unlock()
        BrushTextureStore.removeAll()
        BrushTextureMaskCache.removeAll()
    }

    // MARK: - The five accesses

    /// Whether the library holds a file by this name.
    func contains(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    /// The file's bytes, or nil when it is not there. Nil is an ordinary answer here — a tip whose
    /// PNG the artist deleted draws nothing rather than drawing something else.
    func read(_ fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    /// Writes `data` under `fileName`, creating the root if this is the first file in it.
    ///
    /// Atomic, which the library file already was and an imported tip was not: a half-written PNG is
    /// a brush that draws garbage, and the cost is a rename.
    func write(_ data: Data, to fileName: String) throws {
        let target = url(for: fileName)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    /// Removes the file if it is there. Silent about one that is not — every caller's question is
    /// "make sure this is gone", not "was it".
    func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Every file the library holds, in no particular order. Empty for a root that does not exist.
    func fileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    }

    /// A name's location. `private` on purpose: a URL that escapes this type is a place an access
    /// can happen without the bracket §2.27's third requirement is reserving room for, and the five
    /// methods above are between them everything the app asks of a library file.
    private func url(for fileName: String) -> URL {
        root.appendingPathComponent(fileName)
    }
}
