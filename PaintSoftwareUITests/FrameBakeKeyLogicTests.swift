import XCTest
import UIKit
import SwiftUI

/// RENDER.md §5 stage 4a's pin on the **bake key** — the thing that names a frame's pixels on disk.
///
/// Two claims, and they pull against each other, which is why both are here:
///
/// 1. **A hold is one file.** Two frames inside one cel's span must produce the *same* digest. That
///    is §3.3's whole design — `frame` reaches no pixel, so leaving it out is what makes a
///    nine-frame anime hold one file rather than nine.
/// 2. **Everything that reaches a pixel moves the digest.** A content-addressed store has no second
///    chance: the filename *is* the key, there is nothing to compare against after the lookup, so a
///    field missing from the digest is a wrong picture served with no error. The table below is one
///    row per field, and `testTheEffectOnALeafMovesTheDigest` is the row that would have been
///    silently wrong if this had been built out of `Hashable`.
///
/// **`LayerContentVersion.hash(into:)` omits `effect` on purpose and is right to.** Its doc comment
/// says so: *"Hashing is allowed to collide; equality is what decides a cache hit."* Every in-memory
/// cache in this app compares `==` after the bucket lookup, so a collision costs one compare. There
/// is no `==` on a filename. `FrameBakeKey` therefore walks every field by hand and this suite is
/// what says it walked them.
@MainActor
final class FrameBakeKeyLogicTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        // The shipping defaults, restored by value — `AlphaMask`'s generation counter cannot be put
        // back and does not need to be, since nothing keys on its absolute value.
        AlphaMask.setTuning(threshold: 0.1, antialiasHalfWidth: 0.01)
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Minting one

    /// Every key in this suite goes through here, so a test states only the thing it is varying.
    ///
    /// The three lock-backed inputs are passed explicitly and default to fixed values rather than
    /// being read from their accessors: `AlphaMask.tuningGeneration` and `Compositor.backend` are
    /// process-wide, and a suite that read them live would be measuring whatever ran before it.
    /// `testTheMaskTuningGenerationMovesTheDigest` is where the live accessor is exercised.
    private func key(_ manager: CanvasManager,
                     frame: Int = 0,
                     resolution: RenderResolution = .full,
                     quality: RenderQuality = .full,
                     tuningGeneration: Int = 0,
                     backend: CompositorBackend = .coreGraphics,
                     formatVersion: UInt16 = FrameBakeStore.formatVersion,
                     includeBackground: Bool = true,
                     sizing: RenderSizing = .native,
                     file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let recipe = manager.makeFrameRecipe(atFrame: frame, quality: quality,
                                                   includeBackground: includeBackground,
                                                   sizing: sizing) else {
            XCTFail("The manager has no canvas size, so it mints no recipe.", file: file, line: line)
            return ""
        }
        return FrameBakeKey(recipe: recipe, renderResolution: resolution,
                            maskTuningGeneration: tuningGeneration, backend: backend,
                            formatVersion: formatVersion).fileName
    }

    // MARK: - Claim 1: a hold is one file

    /// **§3.3's central claim, and the reason `frame` is not in the key.** One cel spanning frames
    /// 3 through 11 is byte-identical at every frame of it — the same `LayerContentVersion`, the
    /// same tree — so all nine frames name one file.
    func testEveryFrameOfOneHoldProducesTheSameDigest() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 3, length: 9)])
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 3,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 4, y: 4, width: 20, height: 20)))

        let inside = (3...11).map { key(manager, frame: $0) }
        XCTAssertEqual(Set(inside).count, 1,
                       "Nine frames of one hold must be one file. \(inside.count) frames produced \(Set(inside).count) digests.")
    }

    /// The other half of the same claim: a *different* cel is a different file even though the frame
    /// number is the only thing the caller changed. Without this the test above would be satisfied by
    /// a key that ignored the content as well as the frame.
    func testCrossingIntoAnotherCelMovesTheDigest() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 4), (start: 4, length: 4)])
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 4,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))

        XCTAssertEqual(key(manager, frame: 0), key(manager, frame: 3), "One cel, one digest.")
        XCTAssertEqual(key(manager, frame: 4), key(manager, frame: 7), "One cel, one digest.")
        XCTAssertNotEqual(key(manager, frame: 3), key(manager, frame: 4),
                          "Two cels are two pictures and must be two files.")
    }

    // MARK: - Determinism

    func testTheSameRecipeEncodesToTheSameBytesTwice() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        func bytes() -> Data {
            FrameBakeKey.canonicalBytes(recipe: recipe, renderResolution: .full,
                                        maskTuningGeneration: 0, backend: .coreGraphics,
                                        formatVersion: FrameBakeStore.formatVersion)
        }
        XCTAssertEqual(bytes(), bytes(), "The encoding must be a pure function of the recipe.")
        XCTAssertFalse(bytes().isEmpty, "An empty encoding would make every document one file.")
    }

    func testTheDigestIsSixtyFourLowercaseHexCharacters() {
        let name = key(CanvasFixture.chunkingZoo())
        XCTAssertEqual(name.count, 64, "SHA-256 is 32 bytes, which is 64 hex characters.")
        XCTAssertTrue(name.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                      "The filename must be lowercase hex: \(name)")
    }

    /// Two independently built recipes over the same document agree — which is what a store looking
    /// a frame up on the display path relies on, since it re-mints the recipe rather than keeping
    /// the one the baker used.
    func testTwoRecipesOverTheSameDocumentAgree() {
        let manager = CanvasFixture.chunkingZoo()
        XCTAssertEqual(key(manager), key(manager))
    }

    // MARK: - Claim 2: the per-field table
    //
    // One row per field the key claims to cover. Adding a field to `FrameBakeKey` means adding a row
    // here; the row is what says the field is really in the digest rather than merely mentioned in
    // a doc comment.

    /// Every mutation below must move the digest, and the mutations must not collide with each
    /// other either — so this asserts all of them are pairwise distinct rather than merely each
    /// different from the baseline.
    func testEveryDocumentFieldTheKeyCoversMovesTheDigest() {
        var digests: [String: String] = [:]

        func row(_ name: String, _ mutate: (CanvasManager) -> Void) {
            let manager = CanvasFixture.chunkingZoo()
            mutate(manager)
            digests[name] = key(manager)
        }

        row("baseline") { _ in }
        row("leaf opacity") { $0.layers[0].opacity = 0.5 }
        row("leaf visibility") { $0.layers[0].isVisible = false }
        row("leaf blend mode") { $0.layers[0].blendMode = .multiply }
        // **The row that would have been silently wrong.** `LayerContentVersion.hash(into:)` skips
        // `effect`, and `RenderNode.effect` is not in any in-memory cache key either except through
        // whole-tree `Equatable`. A digest built out of either would put this document and the
        // baseline in one file.
        row("leaf effect") { $0.layers[0].effect = .posterize(Effect.Posterize(levels: 5)) }
        row("folder opacity") { m in m.folders.first.map { m.setFolderOpacity($0.id, to: 0.31) } }
        row("folder grade") { m in
            m.folders.first.map { m.setNodeEffect($0.id, to: .hsvShift(Effect.HSVShift(hueDegrees: 40))) }
        }
        row("folder isolation") { m in
            m.folders.last.map { m.setFolderIsolated($0.id, isIsolated: false) }
        }
        row("folder visibility") { m in
            guard let id = m.folders.first?.id, let i = m.folders.firstIndex(where: { $0.id == id }) else { return }
            m.folders[i].isVisible = false
        }
        row("mask source") { $0.layers[6].alphaMask = AlphaMask(sources: [.layer($0.layers[0].id)]) }
        row("mask disabled") { $0.layers[6].alphaMask?.isEnabled = false }
        row("mask inverted") { $0.layers[6].alphaMask?.invert = true }
        row("leaf content version") { m in
            CanvasFixture.setBakedContent(m, layerIndex: 0,
                                          CanvasFixture.solidImage(.magenta, rect: CGRect(x: 1, y: 1, width: 5, height: 5)))
        }
        row("value layer colour") { m in
            guard let i = m.layers.firstIndex(where: { $0.fill != nil }) else {
                return XCTFail("The zoo is supposed to carry value layers.")
            }
            m.layers[i].fill?.color = PaletteColor(hex: "112233")
        }
        row("paper colour") { $0.canvasBackgroundColor = .red }
        row("paper hidden") { $0.isCanvasBackgroundVisible = false }
        row("canvas padding") { $0.canvasPadding = 6 }

        let unique = Set(digests.values)
        XCTAssertEqual(unique.count, digests.count,
                       "Two of these documents share a digest, so the store would serve one the other's pixels. "
                       + duplicateReport(digests))
    }

    /// The inputs that are not in the document: the sizing knob, the quality, the two lock-backed
    /// globals and the store's own format version.
    func testEveryNonDocumentInputMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        var digests: [String: String] = [:]
        digests["baseline"] = key(manager)
        digests["resolution 75%"] = key(manager, resolution: .threeQuarter)
        digests["resolution 50%"] = key(manager, resolution: .half)
        digests["quality preview"] = key(manager, quality: .preview)
        digests["tuning generation"] = key(manager, tuningGeneration: 1)
        digests["backend metal"] = key(manager, backend: .metal)
        digests["backend automatic"] = key(manager, backend: .automatic)
        digests["format version"] = key(manager, formatVersion: FrameBakeStore.formatVersion &+ 1)
        digests["no paper"] = key(manager, includeBackground: false)
        digests["smaller buffer"] = key(manager, sizing: .fitting(CGSize(width: 32, height: 32)))

        let unique = Set(digests.values)
        XCTAssertEqual(unique.count, digests.count,
                       "Two of these inputs share a digest. " + duplicateReport(digests))
    }

    /// **`renderResolution` is not implied by `canvasSize` and this is why it is a parameter.**
    /// `RenderSizing.native` — which the eyedropper, every parity suite and the default recipe take —
    /// ignores the knob outright, so all three knob positions mint the same `canvasSize`. A key that
    /// read the size alone would put a full-resolution bake and a half-resolution one in one file.
    func testTheResolutionKnobMovesTheDigestEvenWhenTheBufferDoesNot() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .native) else {
            return XCTFail("No recipe.")
        }
        let full = FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0,
                                backend: .coreGraphics, formatVersion: FrameBakeStore.formatVersion)
        let half = FrameBakeKey(recipe: recipe, renderResolution: .half, maskTuningGeneration: 0,
                                backend: .coreGraphics, formatVersion: FrameBakeStore.formatVersion)
        XCTAssertNotEqual(full.fileName, half.fileName,
                          "One buffer size, two knob positions — and they must not be one file.")
    }

    /// The live accessor, rather than the parameter. RENDER §4 says the key reads
    /// `AlphaMask.tuningGeneration` through its lock; a slider write bumps it, and every baked frame
    /// of a masked document is stale the instant it does.
    func testTheMaskTuningGenerationMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        func liveKey() -> String {
            FrameBakeKey(recipe: recipe, renderResolution: .full, backend: .coreGraphics).fileName
        }
        let before = liveKey()
        AlphaMask.setTuning(threshold: 0.2, antialiasHalfWidth: 0.02)
        XCTAssertNotEqual(before, liveKey(),
                          "A mask-tuning write must invalidate every baked frame; the generation is how.")
    }

    /// The live `Compositor.backend` accessor, for the same reason — its own doc comment says "the
    /// bake key will read this accessor when it is built".
    func testTheCompositorBackendMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        Compositor.backend = .coreGraphics
        let cpu = FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0).fileName
        Compositor.backend = .metal
        let gpu = FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0).fileName
        Compositor.backend = .coreGraphics
        XCTAssertNotEqual(cpu, gpu,
                          "The two backends agree only to within a channel step, so a frame is not interchangeable.")
    }

    // MARK: - Effects, case by case and parameter by parameter

    /// **Thirty-one effect values, all of which must be thirty-one digests.** Every case, and for
    /// every case at least one row per artist-facing parameter.
    ///
    /// Pairwise rather than each-against-a-baseline, because the failure a hand-written encoder
    /// actually risks is two *cases* sharing a tag or two parameters being written to the same
    /// place — neither of which a baseline comparison catches.
    func testEveryEffectCaseAndParameterMovesTheDigest() {
        let effects: [(String, Effect)] = [
            ("levels default", .levels(Effect.Levels())),
            ("levels inputBlack", .levels(Effect.Levels(inputBlack: 0.2))),
            ("levels inputWhite", .levels(Effect.Levels(inputWhite: 0.8))),
            ("levels gamma", .levels(Effect.Levels(gamma: 1.4))),
            ("levels outputBlack", .levels(Effect.Levels(outputBlack: 0.05))),
            ("levels outputWhite", .levels(Effect.Levels(outputWhite: 0.95))),
            ("curves default", .curves(Effect.Curves())),
            ("curves points", .curves(Effect.Curves(points: [CurvePoint(x: 0, y: 0),
                                                             CurvePoint(x: 0.5, y: 0.7),
                                                             CurvePoint(x: 1, y: 1)]))),
            ("brightnessContrast brightness", .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2))),
            ("brightnessContrast contrast", .brightnessContrast(Effect.BrightnessContrast(contrast: 1.2))),
            ("hsvShift hue", .hsvShift(Effect.HSVShift(hueDegrees: 30))),
            ("hsvShift saturation", .hsvShift(Effect.HSVShift(saturation: 1.5))),
            ("hsvShift value", .hsvShift(Effect.HSVShift(value: 0.5))),
            ("gradientMap default", .gradientMap(Effect.GradientMap())),
            ("gradientMap stop position", .gradientMap(Effect.GradientMap(stops: [
                GradientStop(position: 0, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)),
                GradientStop(position: 0.8, color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1)),
            ]))),
            ("gradientMap stop colour", .gradientMap(Effect.GradientMap(stops: [
                GradientStop(position: 0, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)),
                GradientStop(position: 1, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
            ]))),
            ("gradientMap mix", .gradientMap(Effect.GradientMap(mix: 0.4))),
            ("chromaticAberration x", .chromaticAberration(Effect.ChromaticAberration(offsetX: 2))),
            ("chromaticAberration y", .chromaticAberration(Effect.ChromaticAberration(offsetY: 2))),
            ("posterize levels", .posterize(Effect.Posterize(levels: 6))),
            ("posterize screen ordered", .posterize(Effect.Posterize(screen: .ordered))),
            ("posterize screen halftone", .posterize(Effect.Posterize(screen: .halftone))),
            ("posterize screenStrength", .posterize(Effect.Posterize(screenStrength: 0.7))),
            ("noise amount", .noise(Effect.Noise(amount: 0.2))),
            ("noise monochrome", .noise(Effect.Noise(isMonochrome: false))),
            ("noise seed", .noise(Effect.Noise(seed: 7))),
            ("blur radius", .blur(Effect.Blur(radius: 3))),
            ("blur angle", .blur(Effect.Blur(radius: 3, angleDegrees: 45, isDirectional: true))),
            ("blur directional", .blur(Effect.Blur(radius: 3, isDirectional: true))),
            ("bloom threshold", .bloom(Effect.Bloom(threshold: 0.5))),
            ("bloom radius", .bloom(Effect.Bloom(radius: 5))),
            ("bloom intensity", .bloom(Effect.Bloom(intensity: 0.6))),
            // EFFECT_BACKDROP §4's artist-facing choice — a different picture, and it lives only in
            // the effect payload, so nothing else in the key could stand in for it.
            ("bloom input backdrop", .bloom(Effect.Bloom(input: .backdrop))),
            ("sobel", .sobel(Effect.Sobel())),
            ("sharpen radius", .sharpen(Effect.Sharpen(radius: 2))),
            ("sharpen amount", .sharpen(Effect.Sharpen(radius: 2, amount: 0.5))),
            ("outline width", .outline(Effect.Outline(width: 3))),
            ("outline colour", .outline(Effect.Outline(color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)))),
            ("outline threshold", .outline(Effect.Outline(threshold: 0.7))),
        ]

        var digests: [String: String] = [:]
        for (name, effect) in effects {
            let manager = CanvasFixture.manager(layerCount: 2)
            manager.layers[0].effect = effect
            digests[name] = key(manager)
        }
        XCTAssertEqual(Set(digests.values).count, digests.count,
                       "Two effects share a digest, so one document would be served the other's grade. "
                       + duplicateReport(digests))
    }

    /// The same list again, on a **folder** rather than a leaf. §3.3 puts the resolved tree in the
    /// key specifically because "a folder's grade is resolved here — no `LayerContentVersion` carries
    /// it", and a key built only from leaf versions would be blind to the whole of this test.
    func testAFoldersGradeMovesTheDigest() {
        var digests: [String: String] = [:]
        let grades: [(String, Effect?)] = [
            ("none", nil),
            ("levels", .levels(Effect.Levels(gamma: 1.3))),
            ("posterize", .posterize(Effect.Posterize(levels: 3))),
            ("sobel", .sobel(Effect.Sobel())),
        ]
        for (name, grade) in grades {
            let manager = CanvasFixture.manager(layerCount: 2)
            let folder = manager.addFolder(name: "Graded")
            manager.layers[0].parentFolderID = folder
            manager.layers[1].parentFolderID = folder
            manager.setNodeEffect(folder, to: grade)
            digests[name] = key(manager)
        }
        XCTAssertEqual(Set(digests.values).count, digests.count,
                       "A folder's grade must reach the digest. " + duplicateReport(digests))
    }

    // MARK: - The reflective seam

    /// `LayerContentVersion.derived` is an `AnyHashable`, so it is the one field the encoder cannot
    /// switch over — and it is the field most likely to be under-hashed, because
    /// `InterpolatedCelIdentity.hash(into:)` omits four of its stored properties while its `==`
    /// includes them.
    ///
    /// This pins the *fallback*, using a type shaped exactly like that hazard: two values that
    /// differ only in a field the hash ignores. `hashValue` cannot tell them apart; the encoder must.
    func testTheDerivedFallbackSeesAFieldTheHashDoesNot() {
        struct UnderHashed: Hashable {
            let named: Int
            /// Deliberately not hashed, exactly as `InterpolatedCelIdentity` does with `spacing`.
            let unhashed: Int
            func hash(into hasher: inout Hasher) { hasher.combine(named) }
        }
        let a = UnderHashed(named: 1, unhashed: 1)
        let b = UnderHashed(named: 1, unhashed: 2)
        XCTAssertEqual(AnyHashable(a).hashValue, AnyHashable(b).hashValue,
                       "The fixture is only meaningful if the two really do collide under `Hashable`.")

        var first = BakeKeyEncoder(), second = BakeKeyEncoder()
        first.derived(AnyHashable(a))
        second.derived(AnyHashable(b))
        XCTAssertNotEqual(first.bytes, second.bytes,
                          "The encoder must see a field the hash skipped — that is why it exists.")
    }

    func testANilDerivedEncodesDifferentlyFromAnyValue() {
        var none = BakeKeyEncoder(), some = BakeKeyEncoder()
        none.derived(nil)
        some.derived(AnyHashable(0))
        XCTAssertNotEqual(none.bytes, some.bytes)
    }

    // MARK: - The encoder's structural guarantees

    /// Rule 2 in `FrameBakeKey.swift`'s header: without length prefixes, `["ab"] + ["c"]` and
    /// `["a"] + ["bc"]` are one byte string. This is the property that makes concatenation
    /// unambiguous, and it is cheap to state directly.
    func testConcatenationIsUnambiguous() {
        var wide = BakeKeyEncoder(), narrow = BakeKeyEncoder()
        wide.array(["ab", "c"]) { e, s in e.string(s) }
        narrow.array(["a", "bc"]) { e, s in e.string(s) }
        XCTAssertNotEqual(wide.bytes, narrow.bytes)

        var one = BakeKeyEncoder(), two = BakeKeyEncoder()
        one.array([1, 2, 3]) { e, v in e.int(v) }
        two.array([1, 2]) { e, v in e.int(v) }
        two.int(3)
        XCTAssertNotEqual(one.bytes, two.bytes, "A count prefix is what tells these two apart.")
    }

    /// Doubles go in by bit pattern, so two values a `String` description would round together stay
    /// apart.
    func testDoublesAreEncodedByBitPattern() {
        var a = BakeKeyEncoder(), b = BakeKeyEncoder()
        a.double(0.1 + 0.2)
        b.double(0.3)
        XCTAssertNotEqual(a.bytes, b.bytes, "0.1 + 0.2 is not 0.3 and the encoder must say so.")
        XCTAssertEqual(a.bytes.count, 8, "Fixed width, so no value's encoding can be a prefix of another's.")
    }

    // MARK: - Helpers

    private func duplicateReport(_ digests: [String: String]) -> String {
        var byDigest: [String: [String]] = [:]
        for (name, digest) in digests { byDigest[digest, default: []].append(name) }
        let clashes = byDigest.values.filter { $0.count > 1 }.map { $0.sorted().joined(separator: " == ") }
        return clashes.isEmpty ? "" : "Collisions: " + clashes.joined(separator: "; ")
    }
}
