import XCTest
import Combine

/// `CanvasPresentation` as a closed set of answers, and the rule that applies them: **a touch on the
/// canvas closes every open presentation that could be sitting over a live canvas, before that touch
/// becomes a stroke.**
///
/// **This file is written to fail on omission**, the way `ToolLogicTests` is. The defect it guards is
/// the one `MENU_PRESENTATION_CENSUS.md` counted: `CanvasManager.interactionBegan` used to be a bare
/// signal with two hand-written subscribers, each clearing one variable *by name*, so a presentation
/// was broken by default and became safe only if whoever added it happened to know there was a line
/// to write. Seven of them did not get that line — including two declared nine lines below the sink
/// written to fix exactly this class of bug.
///
/// The enum closes the implementation half: `overlapsLiveCanvas` is an exhaustive `switch` with no
/// `default:`, so a case added later cannot compile without stating an answer.
/// `testEveryPresentationStatesWhetherItOverlapsTheLiveCanvas` closes the other half — the compiler
/// will accept any answer, and a new case quietly answered `false` is the same bug again.
///
/// **And `testNoBarePopoverIsDeclaredOutsideTheModifier` closes as much of the third half as can be
/// closed.** Neither of the two above can stop somebody writing a raw `.popover` and adding no case
/// at all; that is the honest limit of the design, stated in `CanvasPresentationModifier`'s own doc
/// comment. Swift cannot forbid a standard-library modifier, so the guarantee there is a *test-time*
/// one rather than a compile-time one: the test reads the app's real source files off the host
/// filesystem, located from `#filePath`, and fails naming the file and line. It is the shell script
/// `tools/presentation-census.sh` promoted into the suite, so it runs whether or not anybody
/// remembers to run it.
final class CanvasPresentationLogicTests: XCTestCase {

    // MARK: - The closed set

    /// Every case's answer, stated once, here — keyed by `rawValue` rather than by the case, because
    /// the raw values are what `ActionRecorder` writes into a capture and a table keyed by them
    /// fails loudly if one is renamed.
    ///
    /// Adding a case to `CanvasPresentation` without adding it below fails the count assertion, and
    /// the message is addressed to whoever is reading it in that moment.
    private let expectedOverlapsLiveCanvas: [String: Bool] = [
        // The eight `.popover`s presented from chrome that sits over a mounted, touchable
        // `CanvasView`. A `.popover` left to its own dismissal is dismissed *by* the touch that lands
        // outside it, and this repo has twice observed that the touch is not swallowed: the stroke
        // begins and the teardown lands mid-sequence.
        "timelineSlotMenu": true,          // the original reported freeze
        "onionSkinOptions": true,          // symptom 2 of the 2026-08-18 report
        "interpolateOptions": true,        // never reported, identical line for line
        "layerViewSelector": true,
        "canvasBackgroundColour": true,
        "valueLayerColour": true,          // also closes an undo bracket on the way out
        "effectOutlineColour": true,       // ditto
        "effectGradientStopColour": true,
        // The gallery screen mounts no `DrawingView`, so there is no canvas, no `LayerHostView` and
        // no `StrokeGestureRecognizer` for a teardown to strand. `false` here is a fact about
        // `ContentView`'s `switch screen`, not about these two sheets — move the gallery into a sheet
        // over the editor and both become `true` overnight.
        "galleryProjectVersions": false,
        "galleryRecentlyDeleted": false,
    ]

    func testEveryPresentationStatesWhetherItOverlapsTheLiveCanvas() {
        XCTAssertEqual(CanvasPresentation.allCases.count, expectedOverlapsLiveCanvas.count, """
            A case has been added to `CanvasPresentation` without an entry in \
            `expectedOverlapsLiveCanvas`. Decide whether the new presentation can be on screen at a \
            moment when a touch on the canvas would become a stroke — and therefore whether a canvas \
            touch has to close it first — then say so in `CanvasPresentation.overlapsLiveCanvas` and \
            in the table above. Defaulting to `false` is how seven popovers shipped tearing down in \
            the middle of a stroke.
            """)

        for presentation in CanvasPresentation.allCases {
            guard let expected = expectedOverlapsLiveCanvas[presentation.rawValue] else {
                XCTFail("\(presentation.rawValue) has no stated answer — see the message on the count assertion")
                continue
            }
            XCTAssertEqual(presentation.overlapsLiveCanvas, expected,
                           "\(presentation.rawValue).overlapsLiveCanvas must be \(expected)")
        }
    }

    /// The raw values are the recording vocabulary and `id` is derived from them, so a rename is not
    /// free even though the compiler treats it as such.
    func testRawValuesAreStableAndUnique() {
        let raws = CanvasPresentation.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "Two cases share a raw value: \(raws)")
        for presentation in CanvasPresentation.allCases {
            XCTAssertEqual(presentation.id, presentation.rawValue, "`id` is the raw value")
        }
    }

    /// The assertion that stops the answer being "return true for everything". A blanket `true`
    /// would pass the sweep above only if the table were rewritten to match, but it would also make
    /// the rule below a blanket rather than a filter — which is the thing the gallery cases exist to
    /// keep honest.
    func testTheSetIsSplitRatherThanUniform() {
        XCTAssertTrue(CanvasPresentation.allCases.contains { $0.overlapsLiveCanvas },
                      "If nothing overlaps the live canvas the rule closes nothing and the bug is back")
        XCTAssertTrue(CanvasPresentation.allCases.contains { !$0.overlapsLiveCanvas },
                      "If everything overlaps, `dismissPresentationsOverLiveCanvas` is a blanket, not a filter")
    }

    // MARK: - The rule, driven end to end

    /// The whole registry cycle on a real `CanvasManager`: register every case, fire the rule, and
    /// check exactly the right ones came down.
    ///
    /// **The gallery cases are registered by hand here on purpose.** Nothing in the app registers
    /// them — `GalleryView` holds no `CanvasManager` — so this is the only place the `false` arm is
    /// ever exercised, and without it "closes everything registered" and "closes what the enum says"
    /// are indistinguishable.
    func testDismissingOverTheLiveCanvasIsAFilterAndNotABlanket() {
        let manager = CanvasFixture.manager()
        XCTAssertTrue(manager.openPresentations.isEmpty, "fixture precondition: nothing open")

        for presentation in CanvasPresentation.allCases {
            manager.presentationDidAppear(presentation)
        }
        XCTAssertEqual(manager.openPresentations.count, CanvasPresentation.allCases.count,
                       "fixture precondition: every case has to be registered for the filter to have anything to reject")

        let closed = manager.dismissPresentationsOverLiveCanvas()

        XCTAssertEqual(closed, Set(CanvasPresentation.allCases.filter(\.overlapsLiveCanvas)),
                       "The rule closes exactly what `overlapsLiveCanvas` names")
        XCTAssertEqual(manager.openPresentations,
                       Set(CanvasPresentation.allCases.filter { !$0.overlapsLiveCanvas }), """
                       The presentations that do not overlap a live canvas have to survive a canvas \
                       touch. A registry emptied wholesale would pass every other assertion in this \
                       file and would be a blanket wearing a filter's name.
                       """)
        XCTAssertTrue(manager.openPresentations.contains(.galleryProjectVersions),
                      "Named, so rewriting the sweep above cannot take the filter's proof with it")
    }

    /// Nothing open, nothing closed — and specifically, no notification storm for a canvas touch
    /// made with no menu up, which is the overwhelmingly common case.
    func testDismissingWithNothingOpenClosesNothing() {
        let manager = CanvasFixture.manager()
        XCTAssertEqual(manager.dismissPresentationsOverLiveCanvas(), [])
        XCTAssertTrue(manager.openPresentations.isEmpty)
    }

    /// A second canvas touch while only gallery-side cases are registered must also be a no-op —
    /// the early-return path, distinct from the one above because the registry is *not* empty.
    func testDismissingClosesNothingWhenOnlyNonOverlappingPresentationsAreOpen() {
        let manager = CanvasFixture.manager()
        manager.presentationDidAppear(.galleryRecentlyDeleted)
        XCTAssertEqual(manager.dismissPresentationsOverLiveCanvas(), [])
        XCTAssertEqual(manager.openPresentations, [.galleryRecentlyDeleted])
    }

    /// Registering and unregistering is the modifier's whole contract with the manager, and
    /// `onDisappear` can run for a presentation the rule has already taken out of the registry — so
    /// removing something absent has to be harmless rather than an underflow.
    func testRegistrationRoundTrips() {
        let manager = CanvasFixture.manager()
        manager.presentationDidAppear(.onionSkinOptions)
        XCTAssertEqual(manager.openPresentations, [.onionSkinOptions])

        manager.presentationDidAppear(.onionSkinOptions)
        XCTAssertEqual(manager.openPresentations, [.onionSkinOptions], "A set, so a double appear is one entry")

        manager.presentationDidDisappear(.onionSkinOptions)
        XCTAssertTrue(manager.openPresentations.isEmpty)

        manager.presentationDidDisappear(.onionSkinOptions)
        XCTAssertTrue(manager.openPresentations.isEmpty, "Removing what is already gone is a no-op, not an error")
    }

    /// **`canvasInteractionBegan()` has to do both halves.** It is the single entry point the four
    /// canvas-touch sites in `CanvasView` call, and each half was somebody's whole fix at some point:
    /// dropping the dismissal brings back the seven broken popovers, dropping the `send()` breaks the
    /// top-bar dropdowns (`DrawingView`'s `activePanel`, which is view `@State` and cannot live on
    /// the manager). Nothing else in the app would notice either loss until an artist did.
    func testCanvasInteractionBeganBothDismissesAndSignals() {
        let manager = CanvasFixture.manager()
        var signals = 0
        let subscription = manager.interactionBegan.sink { signals += 1 }
        defer { subscription.cancel() }

        manager.presentationDidAppear(.timelineSlotMenu)
        manager.presentationDidAppear(.galleryProjectVersions)

        manager.canvasInteractionBegan()

        XCTAssertEqual(signals, 1, "`interactionBegan` still has to fire — it is what closes the top-bar dropdowns")
        XCTAssertEqual(manager.openPresentations, [.galleryProjectVersions],
                       "…and the overlapping presentation has to have come down with it")
    }

    // MARK: - The half the compiler cannot check

    /// **No `.popover` may be declared anywhere in the app except inside `CanvasPresentationModifier`.**
    ///
    /// This is the gap the enum cannot close and says so itself: adding a *case* forces you to answer,
    /// but nothing forces you to add a case when you write a raw `.popover`. Swift has no way to
    /// forbid a standard-library modifier, so this is a test-time gate rather than a compile-time one
    /// — a real one nonetheless, since it runs in the fast tier on every branch, which
    /// `tools/presentation-census.sh` only does when somebody remembers.
    ///
    /// **How it reaches the source.** `#filePath` is a compile-time literal holding this file's path
    /// on the machine that built it, and a simulator process can read the host filesystem, so the
    /// test walks the real `PaintSoftware/` tree two directories up. Comment lines are skipped — the
    /// string `.popover(isPresented:)` appears in two doc comments that are *documenting* this very
    /// rule, and a checker that flagged its own explanation would be uninhabitable.
    ///
    /// Skipped, loudly, when the tree is not there — a run on a physical device, or a binary carried
    /// to another machine. That is the one case where "cannot read it" is not a finding.
    func testNoBarePopoverIsDeclaredOutsideTheModifier() throws {
        let appSources = try repositoryRoot().appendingPathComponent("PaintSoftware", isDirectory: true)

        var offenders: [String] = []
        for file in try swiftFiles(under: appSources) {
            if file.lastPathComponent == "CanvasPresentationModifier.swift" { continue }
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                guard trimmed.contains(".popover(") else { continue }
                offenders.append("\(file.lastPathComponent):\(offset + 1): \(trimmed)")
            }
        }

        XCTAssertEqual(offenders, [], """
            A `.popover` is declared outside `CanvasPresentationModifier.swift`:

            \(offenders.joined(separator: "\n"))

            Every presentation that can sit over a live canvas must be declared through \
            `View.canvasPresentation(_:isPresented:canvasManager:)` with a case in \
            `CanvasPresentation`, or a touch that starts a stroke will tear it down in the middle of \
            the touch sequence. That is the defect `MENU_PRESENTATION_CENSUS.md` counted seven times. \
            If the new popover genuinely cannot sit over a canvas — a gallery-screen presentation, \
            say — add a case anyway and answer `false`: the census is the type, and a decision that \
            lives only in a comment is one the next person re-derives.
            """)
    }

    /// The assertion that stops the test above passing because it read nothing. A path typo, a moved
    /// directory or a sandbox that silently returns an empty enumerator all produce an empty offender
    /// list, which is indistinguishable from a clean tree — the green-sweep trap, exactly.
    func testTheSourceScanIsActuallyReadingTheApp() throws {
        let appSources = try repositoryRoot().appendingPathComponent("PaintSoftware", isDirectory: true)
        let files = try swiftFiles(under: appSources)

        XCTAssertGreaterThan(files.count, 50,
                             "The app has far more than 50 Swift files; \(files.count) means the walk is not reaching them")
        XCTAssertTrue(files.contains { $0.lastPathComponent == "CanvasPresentationModifier.swift" },
                      "The one file the scan excludes has to be a file the scan can actually see")

        // And that the needle is findable at all: the modifier really does declare a `.popover`, so a
        // scan including it would find exactly one. If this stops being true the checker above is
        // looking for a string that no longer exists and passes for the wrong reason.
        let modifier = try XCTUnwrap(files.first { $0.lastPathComponent == "CanvasPresentationModifier.swift" })
        let contents = try String(contentsOf: modifier, encoding: .utf8)
        XCTAssertTrue(contents.contains(".popover(isPresented: $isPresented)"),
                      "`CanvasPresentationModifier` is supposed to be the one place a `.popover` is written")
    }

    // MARK: - Source-tree helpers

    /// The repo root, from this file's own compile-time path: `<root>/PaintSoftwareUITests/<this>.swift`.
    private func repositoryRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PaintSoftwareUITests
            .deletingLastPathComponent()   // the repo root
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("PaintSoftware").path) else {
            throw XCTSkip("""
                The source tree is not readable from here (\(root.path)). That is expected on a \
                physical device or a build carried to another machine, and nowhere else — on the \
                simulator this test reads the host filesystem. `tools/presentation-census.sh` is the \
                same check from a shell.
                """)
        }
        return root
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate \(directory.path)")
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
