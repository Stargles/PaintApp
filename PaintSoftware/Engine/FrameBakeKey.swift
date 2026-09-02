import UIKit
import CryptoKit

// MARK: - The bake key (RENDER.md §3.3)
//
// One key names the pixels of one frame. It is `SandwichFullKey` **with `frame` removed** and the
// inputs a persistent store needs added — and the removal is the whole design, not a saving: a
// nine-frame hold is one `Cel`, so every frame of it has byte-identical leaf versions and an
// identical tree, and leaving `frame` out is what makes those nine frames resolve to one file.
// `frame` reaches no pixel; the compositor reads it only to rebuild sub-requests
// (`Compositor.swift`, `MaskResolver.swift`). Putting it back would multiply the store by the
// length of every hold in the document.
//
// ## Why this file hand-writes an encoder instead of using `Hashable`
//
// **`LayerContentVersion.hash(into:)` deliberately omits `effect`.** Its own doc comment argues the
// point and is correct for its own purpose — *"Hashing is allowed to collide; equality is what
// decides a cache hit"* — because every in-memory cache in this app compares `==` after the bucket
// lookup, so a collision costs one compare. `InterpolatedCelIdentity.hash(into:)` omits five
// fields for the same reason and with the same justification.
//
// **A content-addressed disk store has no second chance.** The filename *is* the digest; there is
// no stored key to compare against and nothing to fall back on. A digest that omitted `effect`
// would resolve two frames differing only in a layer's grade to one file, and the store would then
// serve the wrong picture with no error anywhere — a green suite and a wrong canvas. So nothing
// here goes through `hashValue`, `Hasher`, or any `Hashable` conformance (`Hasher` is seeded per
// process and could not name a file even if it were complete). Every field is walked by hand.
//
// Three rules make the walk safe, and they are worth more than any test in
// `FrameBakeKeyLogicTests`:
//
// 1. **No `default:` clause anywhere below.** Every switch is exhaustive over its enum, so adding
//    an `Effect` case or a `BlendMode` tomorrow is a *compile error* here rather than a silent
//    digest collision. That is the durable half of the guarantee.
// 2. **A discriminator byte per enum case and a length prefix per collection**, so no two distinct
//    keys can concatenate to the same byte string. Without them `["ab"] + ["c"]` and `["a"] + ["bc"]`
//    are one encoding.
// 3. **Fixed-width, fixed-endian scalars.** Floats go in as their `bitPattern` little-endian;
//    `UUID` as its 16 bytes; `ObjectIdentifier` as its pointer bit pattern.

/// A type that can name itself to the bake key — the seam for `LayerContentVersion.derived`, which
/// is an `AnyHashable` this file cannot switch over.
///
/// Nothing in the app conforms yet. `DerivedCelContent`'s identities (today
/// `InterpolatedCelIdentity`, tomorrow a pose key) are the intended conformers; until one exists,
/// `BakeKeyEncoder.derived(_:)` falls back to reflection and says so.
protocol BakeKeyEncodable {
    func encodeForBakeKey(into encoder: inout BakeKeyEncoder)
}

/// A canonical byte encoder — append-only, no dictionaries, no reflection except at the one seam
/// named above.
///
/// Little-endian throughout, chosen once here rather than per call site: every device this ships to
/// is little-endian, and a file written on one and read on another would otherwise disagree about
/// a `bitPattern` without disagreeing about anything visible.
struct BakeKeyEncoder {

    private(set) var bytes = Data()

    // MARK: Scalars

    /// A one-byte tag. Every optional, every enum case and every structural boundary emits one.
    mutating func tag(_ value: UInt8) { bytes.append(value) }

    mutating func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func u64(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }

    /// `Int` as a fixed 64 bits, so a 32-bit build and a 64-bit build agree.
    mutating func int(_ value: Int) { u64(UInt64(bitPattern: Int64(value))) }

    mutating func bool(_ value: Bool) { tag(value ? 1 : 0) }

    /// **By bit pattern, never by description.** `0.1 + 0.2` and `0.3` are different pictures to a
    /// shader and different bit patterns here, which is the behaviour wanted; `-0.0` and `0.0`
    /// differ too, which costs at worst a re-bake and never a wrong picture.
    mutating func double(_ value: Double) { u64(value.bitPattern) }
    mutating func float(_ value: Float) { u32(value.bitPattern) }
    mutating func cgFloat(_ value: CGFloat) { double(Double(value)) }

    /// Length-prefixed UTF-8 — see rule 2 in this file's header.
    mutating func string(_ value: String) {
        let utf8 = Array(value.utf8)
        u64(UInt64(utf8.count))
        bytes.append(contentsOf: utf8)
    }

    mutating func uuid(_ value: UUID) { withUnsafeBytes(of: value.uuid) { bytes.append(contentsOf: $0) } }

    /// **The pointer, which is what makes the default store process-lifetime only.**
    /// `LayerContentVersion` names a cel's tiers by `ObjectIdentifier` — a live address — so the same
    /// document reopened in a new process mints entirely different keys for pixels that have not
    /// changed. That is exactly right for the `Library/Caches` store, which RENDER §2.11 dumps at
    /// launch anyway. A bake the artist *keeps* beside the project needs a stamp the document
    /// persists instead; RENDER §3.5 scopes that to stage 6 and it is deliberately not built here.
    mutating func objectID(_ value: ObjectIdentifier) { u64(UInt64(UInt(bitPattern: value))) }

    // MARK: Structure

    /// A length prefix. Every collection emits one before its elements.
    mutating func count(_ value: Int) { int(value) }

    /// `nil` is one byte; a value is one byte and then itself.
    mutating func optional<T>(_ value: T?, _ encode: (inout BakeKeyEncoder, T) -> Void) {
        guard let value else { return tag(0) }
        tag(1)
        encode(&self, value)
    }

    mutating func array<T>(_ values: [T], _ encode: (inout BakeKeyEncoder, T) -> Void) {
        count(values.count)
        for value in values { encode(&self, value) }
    }

    // MARK: Geometry and colour

    mutating func size(_ value: CGSize) { cgFloat(value.width); cgFloat(value.height) }

    mutating func rect(_ value: CGRect) {
        cgFloat(value.origin.x); cgFloat(value.origin.y)
        cgFloat(value.size.width); cgFloat(value.size.height)
    }

    /// **The resolved colour, not the model's `Color`.** `SandwichFullKey` deliberately carries the
    /// model's `Color` and its visibility flag rather than the resolved `RenderBackground`, on the
    /// grounds that resolving through `PixelOps.uiColor` is one more thing that could make two equal
    /// states compare unequal. That argument is about a live in-memory cache being *missed*. Here
    /// the question is which bytes were written, so the key names the colour that reached them.
    mutating func color(_ value: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if value.getRed(&r, green: &g, blue: &b, alpha: &a) {
            tag(1)
        } else {
            // A colour outside an RGB space (a pattern, or a device-gray built by hand) cannot be
            // read as four components. Name it by its description rather than silently encoding
            // four zeros, which would make every such colour one key.
            tag(0)
            string(String(describing: value))
            return
        }
        cgFloat(r); cgFloat(g); cgFloat(b); cgFloat(a)
    }

    // MARK: The one reflective seam

    /// `LayerContentVersion.derived`, which is an `AnyHashable` by design — the *derivation* owns
    /// the enumeration (`FrozenCel.Identity.derived` says so) and neither this file nor that one
    /// should have to learn the list.
    ///
    /// **Its `hashValue` is unusable here for this file's whole reason**, and the live example is
    /// exact: `InterpolatedCelIdentity.hash(into:)` omits `spacing`, `groups`, `guides` and
    /// `thicknessFade` while its synthesized `==` includes them. So conform the identity to
    /// `BakeKeyEncodable` and it is named field by field; until something does, fall back to
    /// `String(reflecting:)`, which is `Mirror`-based and therefore walks **every stored property**
    /// recursively rather than the subset the hash chose. The fallback's weakness is unordered
    /// members (a `Set` prints in hash order, which is per-process), and that direction is safe: it
    /// can produce two descriptions for one value — a re-bake — never one description for two.
    mutating func derived(_ value: AnyHashable?) {
        guard let value else { return tag(0) }
        if let encodable = value.base as? BakeKeyEncodable {
            tag(1)
            string(String(reflecting: type(of: value.base)))
            encodable.encodeForBakeKey(into: &self)
        } else {
            tag(2)
            string(String(reflecting: type(of: value.base)))
            string(String(reflecting: value.base))
        }
    }
}

// MARK: - The key

/// What names one frame's pixels on disk. RENDER.md §3.3.
///
/// Build it from a `FrameRecipe` — which already carries the resolved tree, the leaf versions, the
/// mask stacks, the render size, the paper and the quality — plus the four inputs no in-memory
/// cache carries: the `RenderResolution`, `AlphaMask.tuningGeneration`, `Compositor.backend` and
/// the store's format version.
struct FrameBakeKey: Hashable {

    /// SHA-256 of the canonical encoding — 32 bytes.
    let digest: Data

    /// The filename: 64 lowercase hex characters, no extension of its own kind. Content-addressed,
    /// so two frames of one hold are one file and a frame a change did not reach keeps the file it
    /// had (RENDER §2.16).
    var fileName: String { digest.map { String(format: "%02x", $0) }.joined() }

    init(recipe: FrameRecipe,
         renderResolution: RenderResolution,
         maskTuningGeneration: Int = AlphaMask.tuningGeneration,
         backend: CompositorBackend = Compositor.backend,
         formatVersion: UInt16 = FrameBakeStore.formatVersion) {
        let bytes = Self.canonicalBytes(recipe: recipe,
                                        renderResolution: renderResolution,
                                        maskTuningGeneration: maskTuningGeneration,
                                        backend: backend,
                                        formatVersion: formatVersion)
        digest = Data(SHA256.hash(data: bytes))
    }

    /// For a store reading a header back: the digest it found, as a key to compare against.
    init(rawDigest: Data) { digest = rawDigest }

    /// The bytes the digest is taken over. Exposed so a test can assert determinism over the
    /// encoding itself rather than only over its hash, and so a future divergence can be diffed.
    ///
    /// **`frame` is not in here.** See this file's header; it is the design.
    static func canonicalBytes(recipe: FrameRecipe,
                               renderResolution: RenderResolution,
                               maskTuningGeneration: Int,
                               backend: CompositorBackend,
                               formatVersion: UInt16) -> Data {
        var e = BakeKeyEncoder()
        // A version byte for the *encoding*, distinct from the store's file format version: changing
        // how a field is written must invalidate every digest even if the file layout is unchanged.
        e.tag(0x01)
        e.u16(formatVersion)

        // The buffer. `FrameRecipe.canvasSize` is a `RenderSizing` already applied and rounded to
        // whole pixels, so it is the real extent — and canvas *padding* is already folded into it
        // twice over: `CanvasManager.canvasSize` includes the margin, and the margin's only reach
        // into any pixel is `RenderBackground.rect`, encoded below. `renderResolution` is *not*
        // implied by it, which is why it is a parameter: `.native` sizing ignores the knob outright,
        // and under `.liveComposite` two different knob positions can land on one size after
        // `CompositorBudget.affordableSize` clamps them.
        e.size(recipe.canvasSize)
        e.tag(renderResolution.bakeKeyTag)
        e.tag(recipe.quality.bakeKeyTag)

        // RENDER §4: both of these are accessors over a lock, and the key reads them through those
        // accessors. `tuningGeneration` is what makes a mask-tuning slider write invalidate a baked
        // frame — the two tunables are statics and reach no other field of this key.
        e.int(maskTuningGeneration)
        e.tag(backend.bakeKeyTag)

        // The paper, which is an input to the picture since EFFECT_BACKDROP §6 step 3 — and the only
        // route canvas padding takes into a composited pixel (`canvasBackground(renderedInto:)`
        // insets this rect by the padding). Nil is "paper hidden", which is a different picture from
        // white and not the same key.
        e.optional(recipe.background) { e, background in
            e.color(background.color)
            e.rect(background.rect)
        }

        e.encode(tree: recipe.tree)
        e.array(recipe.leaves) { e, leaf in e.encode(leaf: leaf) }

        // A dictionary has no order, so it is sorted into one before it is encoded — by source kind
        // and then by the id's bytes. Two documents whose mask stacks differ only in dictionary
        // layout must not be two keys.
        let stacks = recipe.maskStacks.sorted { $0.key.bakeKeySortOrder < $1.key.bakeKeySortOrder }
        e.count(stacks.count)
        for (source, nodes) in stacks {
            e.encode(maskSource: source)
            e.encode(tree: nodes)
        }
        return e.bytes
    }
}

// MARK: - Walking the tree
//
// Every switch below is exhaustive with **no `default:`**, which is what turns a new enum case into
// a compile error here instead of a collision on disk.

private extension BakeKeyEncoder {

    mutating func encode(tree: [RenderNode]) {
        array(tree) { e, node in e.encode(node: node) }
    }

    mutating func encode(node: RenderNode) {
        uuid(node.id)
        double(node.opacity)
        bool(node.isVisible)
        tag(node.blendMode.bakeKeyTag)
        bool(node.isIsolated)
        array(node.masks) { e, mask in e.encode(mask: mask) }
        // **The folder grade.** RENDER §3.3 puts the resolved tree in the key precisely because no
        // `LayerContentVersion` carries a *node's* effect — nothing indexed by layer could.
        optional(node.effect) { e, effect in e.encode(effect: effect) }
        switch node.content {
        case .leaf(let layerIndex):
            tag(0x10)
            int(layerIndex)
        case .node(let op, let inputs):
            tag(0x11)
            switch op {
            case .stack:
                tag(0x20)
            case .mix(let mode):
                tag(0x21)
                tag(mode.bakeKeyTag)
            }
            count(inputs.count)
            for slot in inputs { encode(tree: slot) }
        }
    }

    /// §6.2's mask, including the implicit clip-to-below one — `CanvasManager.renderNodes` resolves
    /// `.clipToBelow` into an ordinary `AlphaMask` whose source is the entry beneath, so it arrives
    /// here as a mask like any other and needs no case of its own.
    mutating func encode(mask: AlphaMask) {
        array(mask.sources) { e, source in e.encode(maskSource: source) }
        bool(mask.isEnabled)
        bool(mask.invert)
    }

    mutating func encode(maskSource: MaskSource) {
        switch maskSource {
        case .layer(let id):  tag(0x30); uuid(id)
        case .folder(let id): tag(0x31); uuid(id)
        }
    }

    mutating func encode(leaf: LeafSnapshot?) {
        guard let leaf else { return tag(0) }
        tag(1)
        encode(version: leaf.version)
        switch leaf.content {
        case .none:
            // A real state, not an absence: §4.4's grading layer holds no pixels and still
            // contributes. `LeafSnapshot`'s own doc argues it.
            tag(0x40)
        case .some(.solid(let color)):
            tag(0x41)
            double(color.r); double(color.g); double(color.b); double(color.a)
        case .some(.cel):
            // `PixelOps.FrozenCel` is named entirely by the `LayerContentVersion` just encoded —
            // the two carry the same identity fields — so there is nothing further to say about it
            // that would not be said twice.
            tag(0x42)
        }
    }

    /// **`effect` is in here, and it is the field that would have been silently wrong.**
    /// `LayerContentVersion.hash(into:)` skips it on purpose (see this file's header); equality does
    /// not, and a digest is standing in for equality.
    mutating func encode(version: LayerContentVersion) {
        uuid(version.celID)
        objectID(version.raster)
        int(version.rasterVersion)
        optional(version.vector) { e, v in e.objectID(v) }
        int(version.vectorVersion)
        optional(version.fillImage) { e, v in e.objectID(v) }
        optional(version.bakedImage) { e, v in e.objectID(v) }
        optional(version.valueFill) { e, fill in
            e.uuid(fill.color.id)
            e.string(fill.color.hex)
        }
        optional(version.effect) { e, effect in e.encode(effect: effect) }
        derived(version.derived)
    }
}

// MARK: - Effects
//
// Thirteen cases and their payload fields, by hand. Adding a fourteenth without touching this
// switch does not compile, which is the point.

private extension BakeKeyEncoder {

    mutating func encode(effect: Effect) {
        switch effect {
        case .levels(let p):
            tag(0x50)
            double(p.inputBlack); double(p.inputWhite); double(p.gamma)
            double(p.outputBlack); double(p.outputWhite)
        case .curves(let p):
            tag(0x51)
            array(p.points) { e, point in e.double(point.x); e.double(point.y) }
        case .brightnessContrast(let p):
            tag(0x52)
            double(p.brightness); double(p.contrast)
        case .hsvShift(let p):
            tag(0x53)
            double(p.hueDegrees); double(p.saturation); double(p.value)
        case .gradientMap(let p):
            tag(0x54)
            array(p.stops) { e, stop in
                e.double(stop.position)
                e.encode(codableColor: stop.color)
            }
            double(p.mix)
        case .chromaticAberration(let p):
            tag(0x55)
            double(p.offsetX); double(p.offsetY)
        case .posterize(let p):
            tag(0x56)
            int(p.levels)
            switch p.screen {
            case .none:     tag(0x60)
            case .ordered:  tag(0x61)
            case .halftone: tag(0x62)
            }
            double(p.screenStrength)
        case .noise(let p):
            tag(0x57)
            double(p.amount); bool(p.isMonochrome); u32(p.seed)
        case .blur(let p):
            tag(0x58)
            double(p.radius); double(p.angleDegrees); bool(p.isDirectional)
        case .bloom(let p):
            tag(0x59)
            double(p.threshold); double(p.radius); double(p.intensity)
            encode(effectInput: p.input)
        case .sobel:
            // No parameters at all — `Effect.Sobel` is an empty struct, and the divisor that used to
            // look like one is a resolved constant. The tag is the whole encoding.
            tag(0x5A)
        case .sharpen(let p):
            tag(0x5B)
            double(p.radius); double(p.amount)
        case .outline(let p):
            tag(0x5C)
            double(p.width)
            encode(codableColor: p.color)
            double(p.threshold)
        }
    }

    /// EFFECT_BACKDROP §4 — what Bloom sees. Outline's is fixed and never stored, so this reaches
    /// only Bloom today.
    mutating func encode(effectInput: Effect.Input) {
        switch effectInput {
        case .backdrop: tag(0x63)
        case .ink:      tag(0x64)
        }
    }

    mutating func encode(codableColor: CodableColor) {
        double(codableColor.red); double(codableColor.green)
        double(codableColor.blue); double(codableColor.alpha)
    }
}

// MARK: - Discriminators for the small enums
//
// Written as exhaustive switches rather than `rawValue`, because a `String` raw value is
// exhaustive-by-construction and would let a new case through silently — which is precisely what
// this file exists to prevent.

private extension BlendMode {
    var bakeKeyTag: UInt8 {
        switch self {
        case .normal:       return 0x80
        case .multiply:     return 0x81
        case .screen:       return 0x82
        case .overlay:      return 0x83
        case .add:          return 0x84
        case .subtract:     return 0x85
        case .darken:       return 0x86
        case .lighten:      return 0x87
        case .colorDodge:   return 0x88
        case .colorBurn:    return 0x89
        case .softLight:    return 0x8A
        case .hardLight:    return 0x8B
        case .linearLight:  return 0x8C
        case .difference:   return 0x8D
        case .vividLight:   return 0x8E
        case .pinLight:     return 0x8F
        case .linearBurn:   return 0x90
        case .hue:          return 0x91
        case .saturation:   return 0x92
        case .color:        return 0x93
        case .luminosity:   return 0x94
        case .divide:       return 0x95
        case .exclusion:    return 0x96
        case .lighterColor: return 0x97
        case .darkerColor:  return 0x98
        // Nothing downstream of the render tree ever carries this — `renderNodes` resolves it into
        // `.normal` plus a mask — but the enum has the case, so the switch has it too.
        case .clipToBelow:  return 0x99
        }
    }
}

private extension RenderResolution {
    var bakeKeyTag: UInt8 {
        switch self {
        case .full:         return 0xA0
        case .threeQuarter: return 0xA1
        case .half:         return 0xA2
        }
    }
}

private extension RenderQuality {
    var bakeKeyTag: UInt8 {
        switch self {
        case .full:    return 0xA8
        case .preview: return 0xA9
        }
    }
}

private extension CompositorBackend {
    /// **`.automatic` is its own tag rather than being resolved to what it would pick.** A frame
    /// baked under `.automatic` may have been drawn by either implementation — `Compositor.composite`
    /// asks the tree, and a `.metal` attempt can still come back `.unavailable` and fall back — so
    /// resolving here would claim more than the key knows. The two forced cases exist for the parity
    /// suites and the measurements, and a frame baked under one of them is not interchangeable with
    /// a frame baked under the other: the backends agree only to within a channel step.
    var bakeKeyTag: UInt8 {
        switch self {
        case .coreGraphics: return 0xB0
        case .metal:        return 0xB1
        case .automatic:    return 0xB2
        }
    }
}

private extension MaskSource {
    /// A total order over the mask-stack dictionary's keys, so its iteration order cannot reach the
    /// digest.
    var bakeKeySortOrder: String {
        switch self {
        case .layer(let id):  return "0" + id.uuidString
        case .folder(let id): return "1" + id.uuidString
        }
    }
}
