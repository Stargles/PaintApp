import CoreText
import UIKit

// ADD_TEXT.md §1 "Fonts go through one seam and nothing else".
//
// **No call site outside `SystemFontProvider` may touch `UIFont.familyNames` or
// `UIFont.fontNames(forFamilyName:)`.** That one greppable rule is the entire seam, and it is what
// makes adding a font pack later "append a provider" rather than a change to every call site that
// wanted a font. `FontLibrary` is structurally `BrushLibrary` (`Engine/BrushLibrary.swift:6-49`):
// built-in defaults plus, one day, a user directory at `Documents/Fonts/<packID>/` mirroring
// `BrushStorage`'s root.
//
// `SystemFontProvider` is the only implementation this stage ships, and that font packs can be
// deferred indefinitely without blocking Stages 1-5 is the proof the seam worked.

// MARK: - What a provider offers

/// One installed face, as the picker lists it and as `FontDescriptor` refers to it.
struct FontFace: Equatable, Hashable, Identifiable {
    /// The family this face belongs to, as its provider spells it.
    var familyName: String
    /// The PostScript name — what `UIFont(name:size:)` takes, and what `FontDescriptor.faceName`
    /// stores.
    var postScriptName: String
    /// What the picker shows, e.g. "Bold Italic". The family is the section header, so the row only
    /// has to name the face within it.
    var displayName: String
    var isBold: Bool
    var isItalic: Bool
    /// Nil for the system provider, mirroring `FontDescriptor.packID`.
    var packID: String?

    /// Qualified by pack, for the same reason `FontDescriptor` is: two packs shipping "Inter" must
    /// not collapse into one row.
    var id: String { "\(packID ?? SystemFontProvider.providerID):\(postScriptName)" }

    /// The descriptor that asks for exactly this face.
    var descriptor: FontDescriptor {
        FontDescriptor(familyName: familyName, faceName: postScriptName, packID: packID,
                       isBold: isBold, isItalic: isItalic)
    }
}

/// A titled section of the font picker — "System", "Serif", "Sans", "Mono", "Display", or a pack's
/// own name — holding the families that belong in it.
///
/// The picker UI is a grouped native `Menu` with `Section`s and a checkmark on the current value:
/// the `blendModeRow` / `BlendMode.menuGroups` idiom (`LayerPanel.swift:590-`), which is this app's
/// answer for "many named options" and already the one the artist has met.
struct FontFamilyGroup: Equatable, Identifiable {
    var title: String
    var families: [String]
    var packID: String?

    var id: String { "\(packID ?? SystemFontProvider.providerID):\(title)" }
}

/// The seam. Everything that knows how to find a font is behind this and nothing else is.
protocol FontProvider {
    /// Stable across launches — it is persisted inside every `FontDescriptor` this provider's faces
    /// produce, so renaming one orphans documents.
    var id: String { get }
    func groups() -> [FontFamilyGroup]
    func faces(inFamily family: String) -> [FontFace]
    /// The font for exactly this descriptor, or **nil meaning "not mine"** — either the descriptor
    /// names another pack, or it names a face this provider does not have. Deliberately *not* where
    /// fallback lives: `FontLibrary.resolve` owns the walk, so every caller gets the same walk and
    /// the same answer about whether a substitution happened.
    func uiFont(_ descriptor: FontDescriptor, size: CGFloat) -> UIFont?
}

extension FontProvider {
    /// The face in `family` whose traits match, or the family's plainest face if none does.
    ///
    /// `FontLibrary.resolve`'s middle step, written once on the protocol so the pack providers
    /// Stage 6 adds get it for free rather than each re-deriving "which one is the bold one".
    func face(inFamily family: String, bold: Bool, italic: Bool) -> FontFace? {
        let candidates = faces(inFamily: family)
        guard !candidates.isEmpty else { return nil }
        if let exact = candidates.first(where: { $0.isBold == bold && $0.isItalic == italic }) { return exact }
        // No exact traits match. Prefer the family's regular over an arbitrary first — an artist
        // whose bold italic went missing would rather read the words than get whatever sorted first.
        return candidates.first { !$0.isBold && !$0.isItalic } ?? candidates.first
    }
}

// MARK: - The system provider

/// iOS's own installed fonts — roughly 60-80 families — and the only provider Stage 1 ships.
///
/// **The one place in the app allowed to call `UIFont.familyNames`.** See the file header.
struct SystemFontProvider: FontProvider {

    /// What `FontDescriptor.packID == nil` resolves to. A real string rather than nil inside the
    /// library's own bookkeeping, so provider lookup is one dictionary and not a special case.
    static let providerID = "system"

    var id: String { SystemFontProvider.providerID }

    // MARK: Grouping

    /// Section titles, in the order the menu shows them. San Francisco first because it is the app's
    /// own default and the one face the artist can be sure exists.
    static let systemGroupTitle = "System"
    static let serifGroupTitle = "Serif"
    static let sansGroupTitle = "Sans"
    static let monoGroupTitle = "Mono"
    static let displayGroupTitle = "Display"

    /// Families iOS ships that read as serif. Matched by name because `UIFontDescriptor`'s
    /// `.classSerif` trait is unset for most of the system's own faces — asking the OS gives the
    /// wrong answer far more often than this list does, and the failure mode of the list is a
    /// family in the wrong section rather than a family missing.
    private static let serifNameFragments = [
        "times", "georgia", "palatino", "baskerville", "didot", "hoefler", "cochin", "bodoni",
        "charter", "serif", "academy engraved", "iowan", "seravek", "new york"
    ]
    private static let monoNameFragments = ["mono", "courier", "menlo"]
    /// Families that are ornamental rather than text faces. Kept short and specific; anything not
    /// matched here lands in Sans, which is the honest default for "a face iOS ships".
    private static let displayNameFragments = [
        "papyrus", "chalkduster", "marker felt", "zapfino", "bradley hand", "snell", "savoye",
        "party", "trattatello", "phosphate", "impact", "copperplate", "american typewriter",
        "noteworthy", "kefa", "farah", "sinhala sangam", "rockwell"
    ]

    func groups() -> [FontFamilyGroup] {
        var serif: [String] = [], sans: [String] = [], mono: [String] = [], display: [String] = []
        for family in UIFont.familyNames.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            // The private system families (".AppleSystemUIFont" and friends) are not stable names
            // and must never reach a document. `familyNames` normally omits them; the guard is
            // cheap insurance against an OS version that does not.
            guard !family.hasPrefix(".") else { continue }
            let lowered = family.lowercased()
            func matches(_ fragments: [String]) -> Bool { fragments.contains { lowered.contains($0) } }
            if matches(Self.monoNameFragments) { mono.append(family) }
            else if matches(Self.serifNameFragments) { serif.append(family) }
            else if matches(Self.displayNameFragments) { display.append(family) }
            else { sans.append(family) }
        }
        return [
            FontFamilyGroup(title: Self.systemGroupTitle, families: [FontDescriptor.systemFamilyName], packID: nil),
            FontFamilyGroup(title: Self.serifGroupTitle, families: serif, packID: nil),
            FontFamilyGroup(title: Self.sansGroupTitle, families: sans, packID: nil),
            FontFamilyGroup(title: Self.monoGroupTitle, families: mono, packID: nil),
            FontFamilyGroup(title: Self.displayGroupTitle, families: display, packID: nil)
        ].filter { !$0.families.isEmpty }
    }

    // MARK: Faces

    func faces(inFamily family: String) -> [FontFace] {
        if family == FontDescriptor.systemFamilyName { return Self.systemFaces }
        return UIFont.fontNames(forFamilyName: family).sorted().map { postScript in
            let traits = Self.traits(ofFaceNamed: postScript, inFamily: family)
            return FontFace(familyName: family, postScriptName: postScript,
                            displayName: Self.displayName(forFaceNamed: postScript, inFamily: family),
                            isBold: traits.bold, isItalic: traits.italic, packID: nil)
        }
    }

    /// San Francisco's four faces, synthesised. There is no `fontNames(forFamilyName:)` list for it
    /// — the system font is reached through `UIFont.systemFont(ofSize:weight:)`, not by name — so
    /// the picker's rows are stated here and `uiFont` maps them back.
    static let systemFaces: [FontFace] = [
        FontFace(familyName: FontDescriptor.systemFamilyName, postScriptName: "System-Regular",
                 displayName: "Regular", isBold: false, isItalic: false, packID: nil),
        FontFace(familyName: FontDescriptor.systemFamilyName, postScriptName: "System-Bold",
                 displayName: "Bold", isBold: true, isItalic: false, packID: nil),
        FontFace(familyName: FontDescriptor.systemFamilyName, postScriptName: "System-Italic",
                 displayName: "Italic", isBold: false, isItalic: true, packID: nil),
        FontFace(familyName: FontDescriptor.systemFamilyName, postScriptName: "System-BoldItalic",
                 displayName: "Bold Italic", isBold: true, isItalic: true, packID: nil)
    ]

    /// The face's own name with the family prefix taken off, so "HelveticaNeue-BoldItalic" reads as
    /// "Bold Italic" under a "Helvetica Neue" header. Falls back to the whole PostScript name for a
    /// face whose name does not start with its family's, which happens often enough to matter.
    static func displayName(forFaceNamed postScript: String, inFamily family: String) -> String {
        let squashedFamily = family.replacingOccurrences(of: " ", with: "")
        var remainder = postScript
        for prefix in [squashedFamily, family] where remainder.hasPrefix(prefix) {
            remainder = String(remainder.dropFirst(prefix.count))
            break
        }
        remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        return remainder.isEmpty ? "Regular" : remainder
    }

    /// Asks CoreText for the face's own symbolic traits, which is right where the name is not:
    /// "HelveticaNeue-Medium" is neither bold nor italic and no amount of substring matching says
    /// so. Falls back to the name only when the descriptor cannot be built at all.
    static func traits(ofFaceNamed postScript: String, inFamily family: String) -> (bold: Bool, italic: Bool) {
        if let font = UIFont(name: postScript, size: 12) {
            let symbolic = font.fontDescriptor.symbolicTraits
            return (symbolic.contains(.traitBold), symbolic.contains(.traitItalic))
        }
        let lowered = postScript.lowercased()
        return (lowered.contains("bold"), lowered.contains("italic") || lowered.contains("oblique"))
    }

    // MARK: Resolution

    func uiFont(_ descriptor: FontDescriptor, size: CGFloat) -> UIFont? {
        guard (descriptor.packID ?? Self.providerID) == Self.providerID else { return nil }
        if descriptor.familyName == FontDescriptor.systemFamilyName {
            return Self.systemFont(size: size, bold: descriptor.isBold, italic: descriptor.isItalic)
        }
        guard let faceName = descriptor.faceName else {
            // No face named: ask the family for the one matching the descriptor's traits. This is
            // *not* `FontLibrary`'s substitution step — a descriptor that never named a face has
            // not lost anything, so nothing was substituted.
            guard let face = face(inFamily: descriptor.familyName, bold: descriptor.isBold,
                                  italic: descriptor.isItalic) else { return nil }
            return UIFont(name: face.postScriptName, size: size)
        }
        return UIFont(name: faceName, size: size)
    }

    /// San Francisco at the requested weight and slant. `italicSystemFont` has no weight parameter,
    /// so the italic arms go through the descriptor.
    static func systemFont(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard italic else { return base }
        var symbolic = base.fontDescriptor.symbolicTraits
        symbolic.insert(.traitItalic)
        if bold { symbolic.insert(.traitBold) }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(symbolic) else {
            return UIFont.italicSystemFont(ofSize: size)
        }
        return UIFont(descriptor: descriptor, size: size)
    }

}

// MARK: - The library

/// Why the font on screen is not the font the document asked for. Nil inside `FontResolution` means
/// it is.
enum FontSubstitution: Equatable {
    /// The family is installed but that exact face is not — a sibling face with the nearest traits
    /// is being drawn.
    case faceMissing
    /// The family is not installed at all. The system font is being drawn.
    case familyMissing
    /// The whole pack is gone — uninstalled, or a document from another device. The system font is
    /// being drawn, and reinstalling the pack restores the intended face, because **the stored
    /// descriptor is never rewritten**.
    case packMissing(packID: String)

    /// One sentence for the panel and, for `.packMissing`, for a `CanvasNotice` banner. Phrased at
    /// the artist: what they are looking at, and what would fix it.
    func message(for descriptor: FontDescriptor) -> String {
        switch self {
        case .faceMissing:
            return "\"\(descriptor.faceName ?? descriptor.familyName)\" isn't installed — showing the nearest face in \(descriptor.familyName)."
        case .familyMissing:
            return "\"\(descriptor.familyName)\" isn't installed — showing the system font."
        case .packMissing(let packID):
            return "The font pack \"\(packID)\" isn't installed — showing the system font. Reinstalling it restores \(descriptor.familyName)."
        }
    }
}

/// What `FontLibrary.resolve` answers with: a font that can definitely be drawn, what it actually
/// is, and whether that is what was asked for.
///
/// **Reporting the substitution is half the contract.** A silently substituted font is the failure
/// mode `BrushTip.stamp(.imported)` already has: the document looks subtly wrong on the device
/// that is missing the resource and nobody can say why. Nothing short of embedding the font makes
/// the document round-trip, and this design does not pretend otherwise — it says so instead.
struct FontResolution {
    var font: UIFont
    /// What was actually drawn. **Never written back into the document** — see `FontSubstitution`.
    var resolved: FontDescriptor
    var substitution: FontSubstitution?

    var substituted: Bool { substitution != nil }
}

/// The composed list of providers, and the one resolution walk every call site shares.
///
/// `BrushLibrary`'s shape: a `shared` singleton for the app, and an initialiser taking an explicit
/// provider list so a test can state the whole font world in three lines instead of depending on
/// which faces the simulator's OS build happens to ship.
final class FontLibrary {

    static let shared = FontLibrary()

    private(set) var providers: [FontProvider]

    init(providers: [FontProvider] = [SystemFontProvider()]) {
        self.providers = providers
    }

    /// Appends a pack. Stage 6's whole integration point — `PackFontProvider` plus this call, and
    /// no call site changes.
    func register(_ provider: FontProvider) {
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
    }

    func provider(withID id: String?) -> FontProvider? {
        let wanted = id ?? SystemFontProvider.providerID
        return providers.first { $0.id == wanted }
    }

    /// Every section of the picker, in provider order — built-ins first, packs after, which is the
    /// order `register` maintains.
    func groups() -> [FontFamilyGroup] { providers.flatMap { $0.groups() } }

    func faces(inFamily family: String, packID: String?) -> [FontFace] {
        provider(withID: packID)?.faces(inFamily: family) ?? []
    }

    /// **exact face → any face in the family matching the descriptor's traits → system**, reporting
    /// which step answered. ADD_TEXT.md §1's contract, and the only route from a `FontDescriptor` to
    /// something drawable.
    func resolve(_ descriptor: FontDescriptor, size: CGFloat) -> FontResolution {
        let clampedSize = max(1, size)

        guard let provider = provider(withID: descriptor.packID) else {
            // A pack named by the document that this device does not have. Distinguished from a
            // missing family because the fix is different and worth telling the artist: install the
            // pack and the intended face comes back on its own.
            return FontResolution(font: SystemFontProvider.systemFont(size: clampedSize,
                                                                      bold: descriptor.isBold,
                                                                      italic: descriptor.isItalic),
                                  resolved: .system,
                                  substitution: .packMissing(packID: descriptor.packID ?? SystemFontProvider.providerID))
        }

        // 1. The exact face.
        if let font = provider.uiFont(descriptor, size: clampedSize) {
            return FontResolution(font: font, resolved: descriptor, substitution: nil)
        }

        // 2. Any face in the family with the descriptor's traits.
        if let face = provider.face(inFamily: descriptor.familyName, bold: descriptor.isBold,
                                    italic: descriptor.isItalic),
           let font = provider.uiFont(face.descriptor, size: clampedSize) {
            return FontResolution(font: font, resolved: face.descriptor, substitution: .faceMissing)
        }

        // 3. The system, which is always there.
        return FontResolution(font: SystemFontProvider.systemFont(size: clampedSize,
                                                                  bold: descriptor.isBold,
                                                                  italic: descriptor.isItalic),
                              resolved: .system,
                              substitution: .familyMissing)
    }
}
