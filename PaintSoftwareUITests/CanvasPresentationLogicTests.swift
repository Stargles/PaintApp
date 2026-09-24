import XCTest
import Combine

/// `CanvasPresentation` as a closed set, and the two rules that keep it safe: **no presentation over
/// the canvas is a UIKit presentation**, and **a canvas touch closes the panels, not the
/// presentations** — those close through `AnchoredMenuRouter`, on any outside touch.
///
/// **This file is written to fail on omission**, the way `ToolLogicTests` is. `parent` is an
/// exhaustive `switch` with no `default:`, so a case added later cannot compile without stating
/// whether it is nested; `testEveryPresentationStatesItsParent` closes the other half — the compiler
/// accepts any answer, and a nested picker answered `nil` would close its own parent mid-pick.
///
/// **And `testNoPopoverIsDeclaredAnywhereInTheApp` closes what the type cannot.** Swift cannot forbid
/// a standard-library modifier, so the guarantee is a test-time one: the test reads the app's real
/// source files off the host filesystem, located from `#filePath`, and fails naming the file and
/// line. A `.popover` over this canvas is the canvas freeze — `CanvasPresentation`'s header — and it
/// is `tools/presentation-census.sh` promoted into the suite, so it runs whether or not anybody
/// remembers to run that.
final class CanvasPresentationLogicTests: XCTestCase {

    // MARK: - The closed set

    /// Every case's parent, stated once, here — keyed by `rawValue` because the raw values are what
    /// the action recorder writes into a capture, and a table keyed by them fails loudly if one is
    /// renamed. Adding a case without adding it below fails the count assertion.
    private let expectedParent: [String: String?] = [
        "timelineSlotMenu": nil,
        "onionSkinOptions": nil,
        "interpolateOptions": nil,
        "graphChannelList": nil,
        "frameRateOptions": nil,
        "layerViewSelector": nil,
        "canvasBackgroundColour": nil,
        "valueLayerColour": nil,
        "effectOutlineColour": nil,
        "effectGradientStopColour": nil,
        "effectRecolorColour": nil,
        "effectBloomColour": nil,
        "effectDuplicateOffsetColour": nil,
        "effectGuideColour": nil,
        "selectionColour": nil,
        // The only nesting: `ColorPickerPanel` hung off a swatch inside the ~250 pt onion menu.
        "onionPreviousTintColour": "onionSkinOptions",
        "onionNextTintColour": "onionSkinOptions",
    ]

    func testEveryPresentationStatesItsParent() {
        XCTAssertEqual(CanvasPresentation.allCases.count, expectedParent.count, """
            A case has been added to `CanvasPresentation` without an entry in `expectedParent`. \
            Decide whether the new presentation is raised from inside another one — a touch on it \
            must not close the one it sits in — then say so in `CanvasPresentation.parent` and in \
            the table above.
            """)
        for presentation in CanvasPresentation.allCases {
            guard let expected = expectedParent[presentation.rawValue] else {
                XCTFail("\(presentation.rawValue) has no stated parent — see the message on the count assertion")
                continue
            }
            XCTAssertEqual(presentation.parent?.rawValue, expected,
                           "\(presentation.rawValue).parent must be \(expected ?? "nil")")
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

    // MARK: - The registry

    /// Registering and unregistering is the modifier's whole contract with the manager, and
    /// `onDisappear` can run for a presentation that is already gone — so removing something absent
    /// has to be harmless rather than an underflow.
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

    // MARK: - What a canvas touch closes

    /// **`canvasInteractionBegan()` closes the panels and nothing else.** It is the single entry point
    /// the seven canvas-touch sites in `CanvasView` call, and its `send()` is what closes the
    /// bottom-docked panels and the top-bar dropdowns (`DrawingView`'s `activePanel`, which is view
    /// `@State` and cannot live on the manager).
    ///
    /// **It must not close a presentation**, and not because that would be redundant. A hand lands
    /// its two fingers in two events, so this runs on the first finger of a two-finger pan; closing
    /// from here is closing under a live gesture, which is exactly the shape of the freeze. The
    /// presentations close through `AnchoredMenuRouter`, on the touch itself, with nothing a canvas
    /// recognizer is bound to going with them.
    func testCanvasInteractionBeganSignalsOnceAndClosesNoPresentation() {
        let manager = CanvasFixture.manager()
        var signals = 0
        let subscription = manager.interactionBegan.sink { signals += 1 }
        defer { subscription.cancel() }

        manager.presentationDidAppear(.layerViewSelector)
        manager.canvasInteractionBegan()

        XCTAssertEqual(signals, 1, "`interactionBegan` has to fire — it is what closes the panels")
        XCTAssertEqual(manager.openPresentations, [.layerViewSelector],
                       "…and a canvas touch closes no presentation; the router does that")
    }

    /// **`canvasTouchLanded` runs on *every* canvas touch — the first finger of a two-finger
    /// pan/pinch/rotate included — and must therefore close nothing** (TODO (67)): the panel-closing
    /// `send()` lives in `canvasInteractionBegan`, which only a single touch reaches. The seam
    /// `onSingleTouchBegan` is unreachable from this target (a real `UITouch`/`UIEvent` cannot be
    /// constructed here), but the split itself is a model fact, and this is its model-level half.
    func testCanvasTouchLandedDoesNotSignal() {
        let manager = CanvasFixture.manager()
        var signals = 0
        let subscription = manager.interactionBegan.sink { signals += 1 }
        defer { subscription.cancel() }

        manager.canvasTouchLanded()
        XCTAssertEqual(signals, 0, """
            `canvasTouchLanded` must not send `interactionBegan` — a two-finger canvas transform's \
            first finger reaches only this, and must not close the bottom-docked panels a stroke would.
            """)
    }

    // MARK: - The half the compiler cannot check

    /// **No `.popover` may be declared anywhere in the app.**
    ///
    /// A popover over this canvas presents behind a `_UIPassthroughGateGestureRecognizer` bound to
    /// the canvas's own touches, and when that gate goes away under a live two-finger gesture the
    /// transform recognizers strand for good — the owner's canvas freeze, twice. Every presentation
    /// the editor raises goes through `View.canvasPresentation`, which draws an `AnchoredMenu`
    /// instead; this is the gate that keeps it that way. Swift has no way to forbid a standard-library
    /// modifier, so this is a test-time gate rather than a compile-time one — a real one nonetheless,
    /// since it runs in the fast tier on every branch.
    ///
    /// **How it reaches the source.** `#filePath` is a compile-time literal holding this file's path
    /// on the machine that built it, and a simulator process can read the host filesystem, so the
    /// test walks the real `PaintSoftware/` tree two directories up. Comment lines are skipped — the
    /// string appears in doc comments *documenting* this very rule, and a checker that flagged its own
    /// explanation would be uninhabitable.
    ///
    /// Skipped, loudly, when the tree is not there — a run on a physical device, or a binary carried
    /// to another machine. That is the one case where "cannot read it" is not a finding.
    func testNoPopoverIsDeclaredAnywhereInTheApp() throws {
        let appSources = try repositoryRoot().appendingPathComponent("PaintSoftware", isDirectory: true)
        let offenders = try codeLines(under: appSources, containing: ".popover(")

        XCTAssertEqual(offenders, [], """
            A `.popover` is declared in the app:

            \(offenders.joined(separator: "\n"))

            Declare it through `View.canvasPresentation(_:isPresented:canvasManager:)` with a case in \
            `CanvasPresentation` instead. A UIKit popover over the canvas is torn down under a live \
            two-finger gesture — by the app on the gesture's first finger, or by UIKit itself when two \
            fingers land outside it — and takes the canvas's pan, pinch and rotation with it until the \
            project is reopened.
            """)
    }

    /// The assertion that stops the test above passing because it read nothing. A path typo, a moved
    /// directory or a sandbox that silently returns an empty enumerator all produce an empty offender
    /// list, which is indistinguishable from a clean tree — the green-sweep trap, exactly. So the same
    /// scan, comment-skipping included, has to find a needle that is known to be there in code.
    func testTheSourceScanIsActuallyReadingTheApp() throws {
        let appSources = try repositoryRoot().appendingPathComponent("PaintSoftware", isDirectory: true)
        let files = try swiftFiles(under: appSources)
        XCTAssertGreaterThan(files.count, 50,
                             "The app has far more than 50 Swift files; \(files.count) means the walk is not reaching them")

        let declarations = try codeLines(under: appSources, containing: ".canvasPresentation(")
        XCTAssertTrue(declarations.contains { $0.hasPrefix("LayerPanel.swift:") }, """
            The scan found no `.canvasPresentation(` declaration in `LayerPanel.swift`, where the Views \
            menu and two colour pickers are declared — so it is not reading code lines at all, and the \
            test above passes for the wrong reason. Found: \(declarations)
            """)
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

    /// `file:line: text` for every non-comment line under `directory` containing `needle`.
    private func codeLines(under directory: URL, containing needle: String) throws -> [String] {
        var found: [String] = []
        for file in try swiftFiles(under: directory) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                guard trimmed.contains(needle) else { continue }
                found.append("\(file.lastPathComponent):\(offset + 1): \(trimmed)")
            }
        }
        return found
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
