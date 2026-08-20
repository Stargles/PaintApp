import UIKit
import XCTest

/// `FontLibrary.resolve`'s three-step walk and its substitution report — `ADD_TEXT.md` §1, "Fonts go
/// through one seam and nothing else".
///
/// **The walk is: exact face → any face in the family matching the descriptor's traits → system.**
/// Each step has to be reachable, each has to report the right substitution, and the *stored*
/// descriptor must never be rewritten — reinstalling a pack has to restore the intended face, which
/// it cannot do if resolution wrote its fallback back into the document.
///
/// **Most of these run against a stub provider rather than the device's own fonts**, and that is the
/// point rather than a convenience: which faces a simulator ships is an OS build detail, so a test
/// that says "Helvetica Neue Thin exists" is a test that will fail on some future runtime for a
/// reason that has nothing to do with this code. `StubFontProvider` states the whole font world in
/// ten lines, so every branch below is reachable on purpose. The handful of tests that *do* use the
/// real `SystemFontProvider` assert only things iOS has always been true of — that there is a system
/// font, and that it is never absent.
final class FontResolveLogicTests: XCTestCase {

    // MARK: - A font world stated in full

    /// A provider with exactly the faces a test names. Everything `FontLibrary` needs from a
    /// provider and nothing more, which is also a check that the protocol is that small.
    private struct StubFontProvider: FontProvider {
        let id: String
        /// family → faces. `uiFont` answers from this and nowhere else.
        let families: [String: [FontFace]]

        func groups() -> [FontFamilyGroup] {
            [FontFamilyGroup(title: id, families: families.keys.sorted(), packID: id)]
        }

        func faces(inFamily family: String) -> [FontFace] { families[family] ?? [] }

        func uiFont(_ descriptor: FontDescriptor, size: CGFloat) -> UIFont? {
            guard descriptor.packID == id else { return nil }
            let available = families[descriptor.familyName] ?? []
            guard !available.isEmpty else { return nil }
            if let faceName = descriptor.faceName {
                guard available.contains(where: { $0.postScriptName == faceName }) else { return nil }
            }
            // A real face this provider owns. The identity of the returned `UIFont` does not matter
            // to the walk — only that it is non-nil — so the stub returns a distinguishable one.
            return UIFont.systemFont(ofSize: size, weight: descriptor.isBold ? .bold : .regular)
        }
    }

    private static let packID = "stub-pack"

    private func face(_ family: String, _ postScript: String, bold: Bool = false, italic: Bool = false) -> FontFace {
        FontFace(familyName: family, postScriptName: postScript, displayName: postScript,
                 isBold: bold, isItalic: italic, packID: FontResolveLogicTests.packID)
    }

    /// One family with four faces, in one pack. Every walk below starts here.
    private func stubLibrary() -> FontLibrary {
        let quill = [
            face("Quill", "Quill-Regular"),
            face("Quill", "Quill-Bold", bold: true),
            face("Quill", "Quill-Italic", italic: true),
            face("Quill", "Quill-BoldItalic", bold: true, italic: true)
        ]
        let provider = StubFontProvider(id: Self.packID, families: ["Quill": quill])
        return FontLibrary(providers: [provider])
    }

    private func descriptor(family: String = "Quill", face: String? = nil,
                            pack: String? = FontResolveLogicTests.packID,
                            bold: Bool = false, italic: Bool = false) -> FontDescriptor {
        FontDescriptor(familyName: family, faceName: face, packID: pack, isBold: bold, isItalic: italic)
    }

    // MARK: - Step 1: the exact face

    func testAnInstalledFaceResolvesExactlyAndReportsNoSubstitution() {
        let resolution = stubLibrary().resolve(descriptor(face: "Quill-BoldItalic", bold: true, italic: true),
                                               size: 40)
        XCTAssertFalse(resolution.substituted,
                       "The face asked for is installed. Reporting a substitution here would put a "
                       + "warning in the panel every time the artist picked a font that works.")
        XCTAssertNil(resolution.substitution)
        XCTAssertEqual(resolution.resolved.faceName, "Quill-BoldItalic")
        XCTAssertEqual(resolution.font.pointSize, 40)
    }

    // MARK: - Step 2: the family, matched on traits

    /// The middle step, and the whole reason `FontDescriptor` stores its traits rather than parsing
    /// them back out of the face name: "the bold one in this family" is a question that can be
    /// answered; "Quill-SemiBold" as a string is not.
    func testAMissingFaceFallsBackToTheSameFamilyWithTheSameTraits() {
        let resolution = stubLibrary().resolve(
            descriptor(face: "Quill-SemiBold", bold: true, italic: false), size: 30)
        XCTAssertEqual(resolution.substitution, .faceMissing)
        XCTAssertEqual(resolution.resolved.familyName, "Quill",
                       "The family survives — only the face was missing.")
        XCTAssertEqual(resolution.resolved.faceName, "Quill-Bold",
                       "Bold asked for, bold delivered. Falling to Quill-Regular here would silently "
                       + "un-bold a heading.")
    }

    func testAMissingFaceWithNoTraitsMatchPrefersTheFamilysRegular() {
        // A family with no italic at all: asking for one must not land on the *bold* just because it
        // sorted first.
        let provider = StubFontProvider(id: Self.packID, families: [
            "Quill": [face("Quill", "Quill-Bold", bold: true), face("Quill", "Quill-Regular")]
        ])
        let resolution = FontLibrary(providers: [provider])
            .resolve(descriptor(face: "Quill-Italic", italic: true), size: 20)
        XCTAssertEqual(resolution.substitution, .faceMissing)
        XCTAssertEqual(resolution.resolved.faceName, "Quill-Regular")
    }

    /// A descriptor that never named a face has lost nothing when the family answers it, so nothing
    /// is reported. This is the boundary the middle step is easy to get wrong at: it is a *fallback*
    /// for a missing face, not the ordinary way an unqualified descriptor is served.
    func testADescriptorWithNoFaceNameIsNotASubstitution() {
        let resolution = stubLibrary().resolve(descriptor(face: nil, bold: true), size: 20)
        XCTAssertFalse(resolution.substituted)
        XCTAssertNil(resolution.substitution)
    }

    // MARK: - Step 3: the system

    func testAMissingFamilyFallsAllTheWayToTheSystemFont() {
        let resolution = stubLibrary().resolve(descriptor(family: "Nowhere", face: "Nowhere-Regular"),
                                               size: 25)
        XCTAssertEqual(resolution.substitution, .familyMissing)
        XCTAssertEqual(resolution.resolved, .system)
        XCTAssertEqual(resolution.font.pointSize, 25)
    }

    /// A pack the document names and this device does not have. Told apart from a missing *family*
    /// because the fix is different and worth telling the artist: install the pack and the intended
    /// face comes back on its own.
    func testAMissingPackIsReportedAsAMissingPackAndNotAsAMissingFamily() {
        let resolution = stubLibrary().resolve(
            FontDescriptor(familyName: "Quill", faceName: "Quill-Bold", packID: "not-installed", isBold: true),
            size: 18)
        XCTAssertEqual(resolution.substitution, .packMissing(packID: "not-installed"))
        XCTAssertEqual(resolution.resolved, .system)
    }

    /// **The stored descriptor is never rewritten.** `resolve` returns what it drew in `resolved`
    /// and leaves the input alone, which is what makes reinstalling a pack restore the intended
    /// face rather than find the document has forgotten it ever wanted one.
    func testResolvingDoesNotRewriteTheDescriptorItWasGiven() {
        let asked = descriptor(family: "Quill", face: "Quill-SemiBold", bold: true)
        let library = stubLibrary()
        _ = library.resolve(asked, size: 30)
        XCTAssertEqual(asked.faceName, "Quill-SemiBold",
                       "`FontDescriptor` is a value type and `resolve` takes it by value, so this "
                       + "cannot fail today. It is asserted because the first refactor that makes it "
                       + "`inout` or stores it back is the one that loses the artist's font.")
    }

    /// Reinstalling the pack, in one test: the same descriptor that fell to the system resolves
    /// exactly once the provider is registered.
    func testReinstallingAPackRestoresTheIntendedFace() {
        let asked = descriptor(family: "Quill", face: "Quill-Bold", bold: true)
        let library = FontLibrary(providers: [])
        XCTAssertEqual(library.resolve(asked, size: 20).substitution, .packMissing(packID: Self.packID))

        library.register(StubFontProvider(id: Self.packID, families: [
            "Quill": [face("Quill", "Quill-Bold", bold: true)]
        ]))
        let after = library.resolve(asked, size: 20)
        XCTAssertFalse(after.substituted)
        XCTAssertEqual(after.resolved.faceName, "Quill-Bold")
    }

    // MARK: - The library's own bookkeeping

    func testRegisteringAProviderTwiceReplacesItRatherThanDuplicatingIt() {
        let library = FontLibrary(providers: [])
        library.register(StubFontProvider(id: Self.packID, families: ["A": [face("A", "A-1")]]))
        library.register(StubFontProvider(id: Self.packID, families: ["B": [face("B", "B-1")]]))
        XCTAssertEqual(library.providers.count, 1)
        XCTAssertEqual(library.groups().flatMap(\.families), ["B"],
                       "A pack re-registered after an update is the same pack, not a second copy of it.")
    }

    func testEveryProvidersGroupsAppearInTheComposedList() {
        let library = FontLibrary(providers: [
            StubFontProvider(id: "one", families: ["A": [face("A", "A-1")]]),
            StubFontProvider(id: "two", families: ["B": [face("B", "B-1")]])
        ])
        XCTAssertEqual(library.groups().map(\.title), ["one", "two"])
    }

    func testAGroupIsIdentifiedByItsPackSoTwoPacksCannotCollapseIntoOneRow() {
        let a = FontFamilyGroup(title: "Sans", families: ["Inter"], packID: "pack-a")
        let b = FontFamilyGroup(title: "Sans", families: ["Inter"], packID: "pack-b")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(
            FontFace(familyName: "Inter", postScriptName: "Inter-Regular", displayName: "Regular",
                     isBold: false, isItalic: false, packID: "pack-a").id,
            FontFace(familyName: "Inter", postScriptName: "Inter-Regular", displayName: "Regular",
                     isBold: false, isItalic: false, packID: "pack-b").id)
    }

    // MARK: - The real system provider
    //
    // Only claims iOS has always made. Anything more specific is a claim about an OS build.

    func testTheSystemProviderAlwaysAnswersForTheSystemFamily() {
        let provider = SystemFontProvider()
        let font = provider.uiFont(.system, size: 33)
        XCTAssertNotNil(font, "There is always a system font. If this is ever nil there is nothing "
                        + "left for the last step of the walk to fall back to.")
        XCTAssertEqual(font?.pointSize, 33)
    }

    func testTheSystemFamilyIsItsOwnGroupAndIsListedFirst() {
        let groups = SystemFontProvider().groups()
        XCTAssertEqual(groups.first?.title, SystemFontProvider.systemGroupTitle,
                       "San Francisco is surfaced as a distinguished \"System\" entry rather than "
                       + "buried alphabetically — `ADD_TEXT.md` §1.")
        XCTAssertEqual(groups.first?.families, [FontDescriptor.systemFamilyName])
    }

    func testNoGroupListsAPrivateSystemFamily() {
        let families = SystemFontProvider().groups().flatMap(\.families)
        XCTAssertFalse(families.contains { $0.hasPrefix(".") },
                       "\".AppleSystemUIFont\" and its siblings are not stable names and must never "
                       + "reach a document.")
        XCTAssertGreaterThan(families.count, 10, "iOS ships dozens of families; a list this short "
                             + "means the grouping dropped them.")
    }

    func testTheSystemFamilyOffersBoldAndItalicFaces() {
        let faces = SystemFontProvider().faces(inFamily: FontDescriptor.systemFamilyName)
        XCTAssertEqual(faces.count, 4)
        XCTAssertTrue(faces.contains { $0.isBold && $0.isItalic })
        for face in faces {
            XCTAssertNotNil(SystemFontProvider().uiFont(face.descriptor, size: 12),
                            "Every face the picker lists must be one the provider can actually make: "
                            + "\(face.postScriptName)")
        }
    }

    func testTheSystemProviderDeclinesADescriptorBelongingToAPack() {
        XCTAssertNil(SystemFontProvider().uiFont(
            FontDescriptor(familyName: "Quill", faceName: "Quill-Bold", packID: "some-pack"), size: 12),
                     "\"nil means not mine\" is what lets `FontLibrary` compose providers without "
                     + "each one having to know about the others.")
    }

    /// The display-name trim, which is what the picker's Style menu reads. Asserted on synthetic
    /// input rather than on an installed family, for the reason at the top of this file.
    func testAFaceNameIsShownWithItsFamilyPrefixTrimmedOff() {
        XCTAssertEqual(SystemFontProvider.displayName(forFaceNamed: "HelveticaNeue-BoldItalic",
                                                      inFamily: "Helvetica Neue"), "BoldItalic")
        XCTAssertEqual(SystemFontProvider.displayName(forFaceNamed: "Georgia", inFamily: "Georgia"),
                       "Regular", "A face whose name *is* its family's is that family's regular.")
        XCTAssertEqual(SystemFontProvider.displayName(forFaceNamed: "Foundry-Text", inFamily: "Nothing Alike"),
                       "Foundry-Text", "A face that does not start with its family's name keeps its "
                       + "whole name rather than being trimmed to nonsense.")
    }
}
