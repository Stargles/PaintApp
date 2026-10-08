import SwiftUI
import UIKit
import XCTest

/// **Scribble is refused for every text input the app can show, by one mechanism** (TODO (148)) —
/// `ScribbleRefusal`, a hook on `UITextField` and `UITextView` that adds a refusing
/// `UIScribbleInteraction` as each one comes on screen.
///
/// **What these prove and what they cannot.** They prove the hook reaches every kind of text input
/// the app is built from — UIKit's two text classes, the `UITextField` SwiftUI's `TextField`,
/// `SecureField` and `TextEditor` stand on, a `UIAlertController`'s fields, and the canvas's own
/// `TextOverlayView` — that the delegate refuses at every location, and that nothing else in the app
/// builds a Scribble interaction, so a second per-feature blocker cannot grow back unnoticed. They
/// cannot prove iOS *asks*: that takes a pencil, and XCUITest cannot synthesise one (see
/// `tools/recording2xcuitest.py`). The on-device half is the `scribble.veto` line the delegate writes
/// into an `ActionRecorder` file.
///
/// The tests install the hook themselves, so `testPaintAppInstallsTheHookBeforeAnythingIsCreated`
/// reads the app's launch path as source — the honest substitute for a launch this tier cannot make.
final class ScribbleRefusalLogicTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ScribbleRefusal.install()
    }

    // MARK: - The scene

    /// A key window on screen, which is what makes UIKit call `didMoveToWindow` and SwiftUI build its
    /// UIKit views at all.
    private func onScreenWindow(root: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        }
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        window.rootViewController = root
        window.makeKeyAndVisible()
        retainedWindows.append(window)
        return window
    }

    private var retainedWindows: [UIWindow] = []

    override func tearDown() {
        retainedWindows.forEach { $0.isHidden = true }
        retainedWindows = []
        super.tearDown()
    }

    private func settle(_ seconds: TimeInterval = 0.5) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Walking the tree

    /// Every view under `root` that is a text input, which is what Scribble attaches to — by the
    /// protocol, not by a class list, so a text input of a kind nobody thought of is still found.
    private func textInputs(under root: UIView) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            if view is UITextInput { found.append(view) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    private func refusals(on view: UIView) -> [UIScribbleInteraction] {
        view.interactions.compactMap { $0 as? UIScribbleInteraction }
    }

    /// One refusing interaction, adopted by UIKit, whose delegate says no.
    private func assertRefuses(_ input: UIView, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let found = refusals(on: input)
        XCTAssertEqual(found.count, 1, "\(what): exactly one Scribble interaction, found \(found.count)",
                       file: file, line: line)
        guard let interaction = found.first else { return }
        XCTAssertTrue(interaction.view === input,
                      "\(what): UIKit never adopted the interaction, so it will never ask it anything",
                      file: file, line: line)
        let answer = interaction.delegate?.scribbleInteraction?(interaction, shouldBeginAt: CGPoint(x: 5, y: 5))
        XCTAssertEqual(answer, false,
                       "\(what): the delegate must exist and say no — a nil delegate defaults to allowing Scribble",
                       file: file, line: line)
    }

    // MARK: - Every kind of text input

    /// UIKit's own text classes, added to a window the way any view is.
    func testUIKitTextFieldsAndTextViewsCarryTheRefusalOnceOnScreen() {
        let root = UIViewController()
        let field = UITextField(frame: CGRect(x: 20, y: 20, width: 200, height: 40))
        let secure = UITextField(frame: CGRect(x: 20, y: 80, width: 200, height: 40))
        secure.isSecureTextEntry = true
        let search = UISearchTextField(frame: CGRect(x: 20, y: 140, width: 200, height: 40))
        let textView = UITextView(frame: CGRect(x: 20, y: 200, width: 200, height: 80))
        for view in [field, secure, search, textView] { root.view.addSubview(view) }
        _ = onScreenWindow(root: root)

        assertRefuses(field, "UITextField")
        assertRefuses(secure, "a secure UITextField")
        assertRefuses(search, "UISearchTextField")
        assertRefuses(textView, "UITextView")
    }

    /// Moving a field to another window calls the hook again, and a second interaction would be a
    /// second thing to keep in step.
    func testAFieldMovedBetweenWindowsKeepsOneRefusal() {
        let first = UIViewController(), second = UIViewController()
        let field = UITextField(frame: CGRect(x: 20, y: 20, width: 200, height: 40))
        first.view.addSubview(field)
        _ = onScreenWindow(root: first)
        _ = onScreenWindow(root: second)
        assertRefuses(field, "after its first window")

        field.removeFromSuperview()
        second.view.addSubview(field)
        assertRefuses(field, "after moving to a second window")
    }

    /// The text inputs SwiftUI builds: `TextField`, `SecureField`, `TextEditor` and a vertical-axis
    /// `TextField` — every one of the app's panels and dialogs is made of these. Found by walking the
    /// hosting controller's real view tree for `UITextInput`, so the assertion does not name the
    /// private classes SwiftUI uses.
    func testEverySwiftUITextInputCarriesTheRefusal() {
        struct Form: View {
            @State var plain = ""
            @State var secret = ""
            @State var long = ""
            @State var multi = ""
            var body: some View {
                VStack {
                    TextField("Name", text: $plain)
                    SecureField("Secret", text: $secret)
                    TextEditor(text: $long).frame(height: 80)
                    TextField("Notes", text: $multi, axis: .vertical)
                }
                .padding()
            }
        }
        let host = UIHostingController(rootView: Form())
        let window = onScreenWindow(root: host)
        // SwiftUI builds its platform views on a render pass of its own, a couple of run-loop turns
        // after the window shows; wait for the four, not for a guessed delay.
        var inputs: [UIView] = []
        let deadline = Date().addingTimeInterval(10)
        while inputs.count < 4, Date() < deadline {
            host.view.layoutIfNeeded()
            settle(0.1)
            inputs = textInputs(under: window)
        }
        XCTAssertGreaterThanOrEqual(inputs.count, 4,
                                    "Fixture check: SwiftUI built its four text inputs (found \(inputs.count)), or this walked nothing")
        for input in inputs { assertRefuses(input, "SwiftUI text input \(type(of: input))") }
    }

    /// A `UIAlertController`'s text fields — what every `.alert` with a `TextField` in this app
    /// (Rename View, Rename Folder, New Folder, Rename Palette, …) is made of, and what no
    /// representable could ever stand in for.
    func testAnAlertsTextFieldCarriesTheRefusal() {
        let root = UIViewController()
        let window = onScreenWindow(root: root)
        let alert = UIAlertController(title: "Rename View", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(alert, animated: false)
        settle()

        guard let field = alert.textFields?.first else {
            XCTFail("Fixture check: the alert has no text field")
            return
        }
        XCTAssertNotNil(field.window, "Fixture check: the alert is on screen, or its field never saw a window")
        assertRefuses(field, "an alert's text field")
        XCTAssertTrue(textInputs(under: window).contains(field), "the walk reaches the alert's field too")
    }

    /// The same, through SwiftUI's `.alert` — the call sites' own spelling.
    func testASwiftUIAlertsTextFieldCarriesTheRefusal() {
        struct Host: View {
            @State var shown = true
            @State var name = ""
            var body: some View {
                Color.clear.alert("Rename View", isPresented: $shown) {
                    TextField("Name", text: $name)
                    Button("OK") {}
                }
            }
        }
        let host = UIHostingController(rootView: Host())
        _ = onScreenWindow(root: host)
        var alert: UIAlertController?
        let deadline = Date().addingTimeInterval(10)
        while alert?.textFields?.first?.window == nil, Date() < deadline {
            settle(0.1)
            alert = host.presentedViewController as? UIAlertController
        }
        guard let alert else {
            XCTFail("Fixture check: SwiftUI presented no alert in this process, so there is no field to inspect")
            return
        }
        guard let field = alert.textFields?.first else {
            XCTFail("Fixture check: the alert has no text field")
            return
        }
        assertRefuses(field, "a SwiftUI alert's text field")
    }

    /// The canvas's own editor, which used to carry a veto of its own and now has none: the text tool's
    /// `UITextView`, the one text input that sits **over the artwork**.
    func testTheCanvasTextEditorCarriesTheRefusalWithNoVetoOfItsOwn() {
        let overlay = TextOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let root = UIViewController()
        root.view.addSubview(overlay)
        _ = onScreenWindow(root: root)
        assertRefuses(overlay.textView, "the text tool's UITextView")
    }

    // MARK: - The answer

    /// Every location, not one. The delegate is handed a point and nothing else, so there is no seam
    /// on which "a tap keyboards, a scrawl writes" could be built, and a location-conditional answer
    /// would only make the bug intermittent — including a point *outside* the field, which is where a
    /// pencil resting "near" it lands.
    func testScribbleIsRefusedAtEveryLocationInsideTheFieldAndOutOfIt() throws {
        let root = UIViewController()
        let field = UITextField(frame: CGRect(x: 20, y: 20, width: 200, height: 40))
        root.view.addSubview(field)
        _ = onScreenWindow(root: root)
        let interaction = try XCTUnwrap(refusals(on: field).first)
        let delegate = try XCTUnwrap(interaction.delegate)
        for point in [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: 100, y: 20), CGPoint(x: 199, y: 39),
                      CGPoint(x: -40, y: -40), CGPoint(x: 10_000, y: 10_000)] {
            XCTAssertEqual(delegate.scribbleInteraction?(interaction, shouldBeginAt: point), false,
                           "Scribble allowed at \(point) — the pencil is the brush here")
        }
    }

    // MARK: - One mechanism, and the app uses it

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appSources() throws -> [(name: String, text: String)] {
        let root = repoRoot.appendingPathComponent("PaintSoftware").path
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root))
        var files: [(String, String)] = []
        for case let relative as String in enumerator where relative.hasSuffix(".swift") {
            if let text = try? String(contentsOfFile: root + "/" + relative, encoding: .utf8) {
                files.append((relative, text))
            }
        }
        return files
    }

    /// **The architecture, as a test.** Scribble used to be blocked feature by feature — one on the
    /// canvas editor, a different dodge for the title and for layer names, nothing on the hex field —
    /// and each new field was another chance to forget. `ScribbleRefusal.swift` is now the only file
    /// that names a Scribble interaction, in code, anywhere in the app.
    func testNothingButTheOneMechanismBuildsAScribbleInteraction() throws {
        let sources = try appSources()
        XCTAssertGreaterThan(sources.count, 100, "Fixture check: the scan found the app's sources")
        let names = ["UIScribbleInteraction", "UIIndirectScribbleInteraction", "scribbleInteraction("]
        var offenders: [String] = []
        for (file, text) in sources where file != "Utilities/ScribbleRefusal.swift" {
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.range(of: "//").map { String(line[line.startIndex..<$0.lowerBound]) } ?? line
                if names.contains(where: { code.contains($0) }) { offenders.append("\(file):\(index + 1)") }
            }
        }
        XCTAssertEqual(offenders, [], "a second Scribble blocker — fold it into ScribbleRefusal")
    }

    /// The hook is only as good as the line that installs it, and this tier installs it itself. Read
    /// as source, like `CanvasGeometryLogicTests` reads the canvas picker: `PaintApp.init` must call it,
    /// and before the first thing that can build a view.
    func testPaintAppInstallsTheHookBeforeAnythingIsCreated() throws {
        let text = try String(contentsOf: repoRoot.appendingPathComponent("PaintSoftware/PaintApp.swift"), encoding: .utf8)
        let initRange = try XCTUnwrap(text.range(of: "init() {"), "PaintApp has an init")
        let body = text[initRange.upperBound...]
        let install = try XCTUnwrap(body.range(of: "ScribbleRefusal.install()"), "PaintApp.init must install ScribbleRefusal")
        let firstOtherCall = try XCTUnwrap(body.range(of: "FrameBakeStore."), "Fixture check: the next statement is still there")
        XCTAssertLessThan(install.lowerBound, firstOtherCall.lowerBound, "install comes first")
    }
}
