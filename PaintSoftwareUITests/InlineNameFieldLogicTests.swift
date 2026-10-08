import XCTest
import UIKit

/// **A name edited where it is shown** — the rule `InlineNameField` gives the scene's title and every layer,
/// folder, group, view, palette and gallery-folder name: Return or a touch elsewhere commits, an empty name or an unchanged one commits nothing,
/// and only the trimmed text the artist typed leaves. The field is put on screen in a real window, since
/// UIKit only lets a view become first responder there; `InlineRenameUITests` drives the same rule through
/// the real top bar and the real rail, with the keyboard.
@MainActor
final class InlineNameFieldLogicTests: XCTestCase {

    private var retainedWindows: [UIWindow] = []

    override func tearDown() {
        retainedWindows.forEach { $0.isHidden = true }
        retainedWindows = []
        super.tearDown()
    }

    /// A field named `name`, on screen, with every callback recording into `events`.
    private func fieldOnScreen(named name: String, events: EventLog,
                               beginsEditingWhenShown: Bool = false) -> InlineNameField {
        let root = UIViewController()
        let field = InlineNameField(frame: CGRect(x: 20, y: 40, width: 240, height: 34))
        field.beginsEditingWhenShown = beginsEditingWhenShown
        field.name = name
        field.onCommit = { events.log.append("commit:\($0)") }
        field.onEndEditing = { events.log.append("end") }
        root.view.addSubview(field)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        window.rootViewController = root
        window.makeKeyAndVisible()
        retainedWindows.append(window)
        return field
    }

    private final class EventLog { var log: [String] = [] }

    private func edit(_ field: InlineNameField, typing typed: String) {
        XCTAssertTrue(field.becomeFirstResponder(), "PREMISE: the field takes the keyboard")
        field.text = typed
        XCTAssertTrue(field.resignFirstResponder())
    }

    func testAFieldShowsItsNameAndEditingStartsFromIt() {
        let events = EventLog()
        let field = fieldOnScreen(named: "Sky", events: events)
        XCTAssertEqual(field.text, "Sky")
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertEqual(field.text, "Sky", "editing starts from the name")
        field.resignFirstResponder()
        XCTAssertEqual(events.log, ["end"], "an edit that changed nothing commits nothing")
    }

    /// **A field that exists because the artist asked to rename has the keyboard as soon as it is on screen**
    /// — once. A field not asked to begin editing waits to be tapped.
    func testAFieldMadeToBeginEditingTakesTheKeyboardWhenShownAndOnlyOnce() {
        /// Lets the run loop turn — the request is honoured on the pass after the window is shown.
        func spin(for seconds: TimeInterval, until reached: () -> Bool = { false }) {
            let deadline = Date().addingTimeInterval(seconds)
            while !reached(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        let waiting = fieldOnScreen(named: "Sky", events: EventLog())
        spin(for: 0.5)
        XCTAssertFalse(waiting.isFirstResponder, "a field that was not asked to begin editing waits for a tap")

        let field = fieldOnScreen(named: "Sky", events: EventLog(), beginsEditingWhenShown: true)
        spin(for: 2) { field.isFirstResponder }
        XCTAssertTrue(field.isFirstResponder, "the field asked to begin editing has the keyboard once it is on a window")
        XCTAssertFalse(field.beginsEditingWhenShown, "…and the request is spent")
        field.resignFirstResponder()
        let root = field.window?.rootViewController
        field.removeFromSuperview()
        root?.view.addSubview(field)
        spin(for: 0.5)
        XCTAssertFalse(field.isFirstResponder, "put back on screen after the edit, it does not take the keyboard again")
    }

    /// **A new name is trimmed, committed once, and shown at once**, with the end of editing after it so a
    /// caller that hides the field there finds the model already renamed.
    func testANewNameCommitsTrimmedAndThenTheEditEnds() {
        let events = EventLog()
        let field = fieldOnScreen(named: "Sky", events: events)
        edit(field, typing: "  Clouds \n")
        XCTAssertEqual(events.log, ["commit:Clouds", "end"])
        XCTAssertEqual(field.name, "Clouds")
        XCTAssertEqual(field.text, "Clouds", "the field shows the new name without waiting for the model")
    }

    /// **An empty name reverts**: nothing leaves, and the field shows the name it had.
    func testAnEmptyOrBlankNameRevertsAndCommitsNothing() {
        for typed in ["", "   ", " \n "] {
            let events = EventLog()
            let field = fieldOnScreen(named: "Sky", events: events)
            edit(field, typing: typed)
            XCTAssertEqual(events.log, ["end"], "'\(typed)' commits nothing")
            XCTAssertEqual(field.text, "Sky", "…and the name comes back")
            XCTAssertEqual(field.name, "Sky")
        }
    }

    func testTheSameNameCommitsNothingEvenWithWhitespaceAround() {
        let events = EventLog()
        let field = fieldOnScreen(named: "Sky", events: events)
        edit(field, typing: " Sky ")
        XCTAssertEqual(events.log, ["end"])
    }

    /// **Return commits**: it lets go of the keyboard, which is the commit.
    func testReturnLetsGoOfTheKeyboard() {
        let events = EventLog()
        let field = fieldOnScreen(named: "Sky", events: events)
        XCTAssertTrue(field.becomeFirstResponder())
        field.text = "Wind"
        XCTAssertFalse(field.textFieldShouldReturn(field), "the return key does not insert a newline")
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertEqual(events.log, ["commit:Wind", "end"])
    }

    /// **The model renaming the layer while the field is being typed into does not take the words away
    /// from the artist**: the name changes underneath and the text stays.
    func testReassigningTheNameWhileTypingLeavesTheTypedText() {
        let events = EventLog()
        let field = fieldOnScreen(named: "Sky", events: events)
        XCTAssertTrue(field.becomeFirstResponder())
        field.text = "Half typ"
        field.name = "Sky 2"
        XCTAssertEqual(field.text, "Half typ")
        field.text = "Typed"
        field.resignFirstResponder()
        XCTAssertEqual(events.log, ["commit:Typed", "end"])
    }

    /// **The window is watched for a touch elsewhere only while the field is being edited** — one
    /// recognizer, on the field's own window, gone when the edit ends.
    func testTheWindowIsWatchedOnlyWhileTheFieldIsBeingEdited() throws {
        let field = fieldOnScreen(named: "Sky", events: EventLog())
        let window = try XCTUnwrap(field.window)
        func watchers() -> [UIGestureRecognizer] {
            (window.gestureRecognizers ?? []).filter { $0.delegate === field }
        }
        XCTAssertTrue(watchers().isEmpty, "idle: nothing is watching")
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertEqual(watchers().count, 1)
        let watcher = try XCTUnwrap(watchers().first)
        XCTAssertFalse(watcher.cancelsTouchesInView, "the touch that ends the edit still reaches what it was aimed at")
        XCTAssertFalse(watcher.delaysTouchesBegan)
        XCTAssertEqual((watcher as? UILongPressGestureRecognizer)?.minimumPressDuration, 0, "it begins at touch-down")
        XCTAssertTrue(field.gestureRecognizer(watcher, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()),
                      "it never stands in another recognizer's way")
        field.resignFirstResponder()
        XCTAssertTrue(watchers().isEmpty, "the edit is over: nothing is watching")
    }

    /// The touch-elsewhere recognizer ends the edit.
    func testATouchElsewhereEndsTheEdit() {
        let events = EventLog()
        let field = fieldOnScreen(named: "Sky", events: events)
        XCTAssertTrue(field.becomeFirstResponder())
        field.text = "Clouds"
        // The recognizer's own action, as UIKit performs it when the recognizer begins.
        field.perform(NSSelectorFromString("touchedElsewhere:"), with: ForcedState(.began))
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertEqual(events.log, ["commit:Clouds", "end"])
    }

    /// A long-press recognizer whose state is chosen, for driving `touchedElsewhere(_:)` without a touch.
    private final class ForcedState: UILongPressGestureRecognizer {
        private let forced: UIGestureRecognizer.State
        init(_ state: UIGestureRecognizer.State) {
            forced = state
            super.init(target: nil, action: nil)
        }
        override var state: UIGestureRecognizer.State {
            get { forced }
            set { }
        }
    }
}
