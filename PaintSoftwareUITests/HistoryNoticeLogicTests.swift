import XCTest
import UIKit

/// The undo/redo reminder — CLAUDE.md's `CanvasNotice` reused for a fourth purpose: naming what an
/// undo or redo just did, the way the artist thinks of it rather than the way the code does.
///
/// Two things had to be true for this to ship without a missed call site: every one of
/// `UndoHistory`'s ~70 registration sites had to supply a `HistoryActionLabel`, and every label had
/// to map to a real phrase. Both are compiler-enforced (`HistoryActionLabel`'s own doc explains
/// how), but a compiler guarantee that a `switch` is exhaustive says nothing about whether an arm
/// returns something *good* — `testEveryLabelHasARealPhrase` is the test that would have caught a
/// case mapped to `""` or to a copy-pasted placeholder, which the compiler cannot.
///
/// Headless throughout: no `XCUIApplication`, no simulator. Whether the banner actually renders is
/// `CanvasNoticeUITests`' job.
@MainActor
final class HistoryNoticeLogicTests: XCTestCase {

    // MARK: - HistoryActionLabel.phrase: every case, for real

    /// The test a missed registration site cannot slip past: every case this enum declares must
    /// resolve to a phrase that could actually sit after "Undid "/"Redid " in a sentence. Iterating
    /// `allCases` rather than spot-checking a handful is the point — a label added to the enum but
    /// left out of `phrase`'s `switch` is already a build failure (no `default:` arm exists to catch
    /// it), so this test is really asserting the *content* of every arm, not their existence.
    func testEveryLabelHasARealPhrase() {
        for label in HistoryActionLabel.allCases {
            let phrase = label.phrase
            XCTAssertFalse(phrase.isEmpty, "\(label) has an empty phrase.")
            XCTAssertFalse(phrase.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(label)'s phrase is all whitespace.")
            // Placeholder text a copy-paste or a stub implementation might have left behind —
            // none of these belong in a sentence an artist reads.
            let placeholders = ["todo", "fixme", "placeholder", "unknown", "something", "tbd", "xxx"]
            let lowered = phrase.lowercased()
            for placeholder in placeholders {
                XCTAssertFalse(lowered.contains(placeholder),
                               "\(label)'s phrase \"\(phrase)\" reads like a placeholder.")
            }
            // Artist vocabulary, not code vocabulary: no case name (camelCase, no spaces) leaking
            // through unmapped — every phrase in the switch is hand-written lowercase words.
            XCTAssertFalse(phrase.contains(where: { $0.isUppercase }),
                           "\(label)'s phrase \"\(phrase)\" contains an uppercase letter; phrases are lowercase sentence fragments.")
        }
    }

    /// No two cases collapse to the same phrase by accident — `.brushStroke`/`.erase` is the pair
    /// this actually guards, since both are the same drag gesture in `StrokeCanvasView` and a
    /// mislabel there is exactly what would make the two read identically to an artist.
    func testDistinctAppSurfaceCasesHaveDistinctPhrases() {
        XCTAssertNotEqual(HistoryActionLabel.brushStroke.phrase, HistoryActionLabel.erase.phrase,
                          "A brush stroke and an erase must read differently in the undo banner.")
    }

    /// `CaseIterable` synthesis is itself worth pinning: if a future edit accidentally duplicates a
    /// case name (impossible to compile) or, more realistically, someone adds a case gated behind
    /// `#if` and breaks the derived list, `allCases.count` catching zero or a suspiciously small
    /// number is a cheap tripwire. The exact number isn't the point — the sanity floor is.
    func testAllCasesIsNonTrivial() {
        XCTAssertGreaterThan(HistoryActionLabel.allCases.count, 50,
                             "Expected on the order of the app's known registration sites; a much smaller count suggests allCases stopped enumerating everything.")
    }

    // MARK: - CanvasNotice wording

    func testUndoMessageNamesTheAction() {
        let notice = CanvasNotice(.historyUndo(.mergeLayers))
        XCTAssertEqual(notice.message, "Undid merge layers.")
    }

    func testRedoMessageNamesTheAction() {
        let notice = CanvasNotice(.historyRedo(.deleteLayer))
        XCTAssertEqual(notice.message, "Redid delete layer.")
    }

    /// Every label under both directions — the same "no arm skipped" guarantee as
    /// `testEveryLabelHasARealPhrase`, applied to the sentence the artist actually reads rather than
    /// to the raw phrase.
    func testEveryLabelProducesAWellFormedSentenceInBothDirections() {
        for label in HistoryActionLabel.allCases {
            let undoMessage = CanvasNotice(.historyUndo(label)).message
            XCTAssertTrue(undoMessage.hasPrefix("Undid "), "\(label): \"\(undoMessage)\" doesn't start with \"Undid \".")
            XCTAssertTrue(undoMessage.hasSuffix("."), "\(label): \"\(undoMessage)\" doesn't end with a period.")

            let redoMessage = CanvasNotice(.historyRedo(label)).message
            XCTAssertTrue(redoMessage.hasPrefix("Redid "), "\(label): \"\(redoMessage)\" doesn't start with \"Redid \".")
            XCTAssertTrue(redoMessage.hasSuffix("."), "\(label): \"\(redoMessage)\" doesn't end with a period.")
        }
    }

    /// History notices never block — no one-tap fix to offer, since the undo/redo already happened.
    /// Matches the 2.6s duration every other action-less notice gets (`CanvasNotice.duration`).
    func testHistoryNoticesOfferNoActionAndUseTheShortDuration() {
        let undo = CanvasNotice(.historyUndo(.fill))
        let redo = CanvasNotice(.historyRedo(.fill))
        XCTAssertNil(undo.actionTitle)
        XCTAssertNil(redo.actionTitle)
        XCTAssertEqual(undo.duration, 2.6)
        XCTAssertEqual(redo.duration, 2.6)
    }

    /// The banner's accessibility value distinguishes undo from redo (not just "history happened"),
    /// so a UI test could tell them apart without reading the sentence.
    func testUndoAndRedoHaveDistinctAccessibilityCodes() {
        XCTAssertEqual(CanvasNotice(.historyUndo(.fill)).code, "historyUndo")
        XCTAssertEqual(CanvasNotice(.historyRedo(.fill)).code, "historyRedo")
        XCTAssertNotEqual(CanvasNotice(.historyUndo(.fill)).code, CanvasNotice(.historyRedo(.fill)).code)
    }

    /// The three original blocker codes are exactly what they were before `Kind` grew associated
    /// values — `LayerUITests.testTheModePickerCreatesAnEffectLayerAStrokeCannotLandOn` asserts
    /// `notice.value == "noDrawingSurface"` and must keep passing unchanged.
    func testBlockerCodesAreUnchangedFromBeforeHistoryNoticesExisted() {
        XCTAssertEqual(CanvasNotice(.noLayers).code, "noLayers")
        XCTAssertEqual(CanvasNotice(.hiddenLayer).code, "hiddenLayer")
        XCTAssertEqual(CanvasNotice(.noDrawingSurface).code, "noDrawingSurface")
    }

    // MARK: - CanvasManager wiring: raised only when something actually happened

    /// Undo against a document with no history at all must not raise anything — a plain
    /// `CanvasManager()`, not `CanvasFixture.manager()`, since the fixture's `addLayer()` calls would
    /// themselves seed the stack.
    func testUndoOnEmptyHistoryStaysSilent() {
        let manager = CanvasManager()
        XCTAssertFalse(manager.history.canUndo)
        manager.undo()
        XCTAssertNil(manager.notice, "Undoing nothing must not raise a notice.")
    }

    func testRedoOnEmptyRedoStackStaysSilent() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addLayer()   // one undoable step, and nothing to redo yet
        XCTAssertFalse(manager.history.canRedo)
        manager.redo()
        XCTAssertNil(manager.notice, "Redoing nothing must not raise a notice.")
    }

    /// The actual wiring: `CanvasManager.undo()` names the action it reverted.
    func testUndoRaisesTheReversedActionsNotice() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addLayer()
        manager.undo()
        XCTAssertEqual(manager.notice?.kind, .historyUndo(.addLayer))
    }

    /// And redo names the one it reapplied — a different label than the undo that preceded it in
    /// this test, so a copy-paste that hard-codes one direction's label would fail here.
    func testRedoRaisesTheReappliedActionsNotice() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addLayer()
        manager.addVectorLayer()
        manager.undo()   // reverts addVectorLayer
        manager.redo()   // reapplies it
        XCTAssertEqual(manager.notice?.kind, .historyRedo(.addVectorLayer))
    }

    /// **Rapid repeated undo must not queue a backlog.** `CanvasManager.notice` is a single optional
    /// slot, not a collection, and `raise(_:)` overwrites it — so after three undos in a row (no
    /// delay between them, exactly what holding the undo button produces) there is exactly one
    /// notice on the manager, and it names the *last* action reverted, not the first. The `id`
    /// changing each time is what makes `DrawingView`'s `.task(id: canvasManager.notice?.id)` cancel
    /// and restart its dismissal timer instead of leaving an earlier timer to dismiss a later
    /// banner early — see that file's own comment on the mechanism this test is characterizing from
    /// the model side.
    func testRapidRepeatedUndoReplacesRatherThanQueues() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addLayer()         // 1st undo will revert this last
        manager.addVectorLayer()
        manager.addFolder()

        manager.undo()   // reverts addFolder
        let firstNotice = manager.notice
        XCTAssertEqual(firstNotice?.kind, .historyUndo(.addFolder))

        manager.undo()   // reverts addVectorLayer
        let secondNotice = manager.notice
        XCTAssertEqual(secondNotice?.kind, .historyUndo(.addVectorLayer))
        XCTAssertNotEqual(secondNotice?.id, firstNotice?.id,
                          "Each raise must mint a fresh id or the dismissal timer never restarts.")

        manager.undo()   // reverts addLayer
        let thirdNotice = manager.notice
        XCTAssertEqual(thirdNotice?.kind, .historyUndo(.addLayer))
        XCTAssertNotEqual(thirdNotice?.id, secondNotice?.id)

        // There is nowhere for a backlog to live: `notice` is a single `CanvasNotice?`, so "replaced
        // rather than queued" is a fact about the type, not something that needs a count assertion —
        // but the three distinct kinds/ids above are the behavioral proof that each raise actually
        // ran (rather than, say, the second and third undo silently no-op-ing against a full queue).
    }

    /// The raster brush/eraser split this task's fix landed: both go through the same
    /// `StrokeCanvasView` gesture, and before this change the raster eraser undid as "Stroke". Not
    /// exercisable headlessly (no `UIView`), so this pins the *label* pair directly instead — the
    /// half of the fix that lives in `HistoryActionLabel` rather than in gesture code.
    func testBrushAndEraseAreDistinctLabelsNotAnAccidentalAlias() {
        XCTAssertNotEqual(HistoryActionLabel.brushStroke, HistoryActionLabel.erase)
        XCTAssertEqual(HistoryActionLabel.brushStroke.phrase, "brush stroke")
        XCTAssertEqual(HistoryActionLabel.erase.phrase, "erase")
    }
}
