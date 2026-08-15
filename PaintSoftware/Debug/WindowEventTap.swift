import UIKit
import ObjectiveC.runtime

/// One touch sample as it will be written to the file. Built in `WindowEventTap`, consumed by
/// `ActionRecorder.touch(_:)`; a struct rather than a dozen arguments because the emitter and the
/// producer are in different files and the field list is the schema.
struct TouchSample {
    let time: Double
    let phase: String
    let type: String
    /// Small integer identifying one finger/pen for the length of its sequence, so a reader can
    /// follow "the second finger" without matching pointers.
    let touchID: Int
    /// The accessibility identifier an XCUITest would address. Nil means this touch is not
    /// replayable as-is and the converter has to say so.
    let target: String?
    let targetClass: String
    let hitClass: String
    /// XCUIElement-ish type derived from accessibility traits, so the converter can emit
    /// `app.buttons[...]` rather than a generic descendant query.
    let role: String
    let label: String?
    /// Superview/ancestor steps walked from the hit view to whatever carried the identifier. 0 means
    /// the touch landed directly on the identified thing; a large number means the identifier is a
    /// coarse container and the replay will be approximate.
    let depth: Int
    /// How the target was found: `view` (a `UIView.accessibilityIdentifier` up the superview chain),
    /// `ax` (the accessibility element tree, which is where SwiftUI's identifiers actually live), or
    /// `none`.
    let resolution: String
    /// Position inside the target element's frame, 0–1. **This is the replayable coordinate**:
    /// `XCUIElement.coordinate(withNormalizedOffset:)` takes exactly this, and it also accepts values
    /// outside 0–1 — which is what makes a drag that leaves its starting element still expressible.
    let normalized: CGPoint
    let window: CGPoint
    /// The same point normalised within the **window**, always, whatever the target turned out to be.
    /// The fallback replay coordinate for a touch with no identifier: it is what
    /// `app.windows.firstMatch.coordinate(withNormalizedOffset:)` takes, and unlike the raw point it
    /// survives a device with a different screen size. Recorded unconditionally rather than only when
    /// the identifier is missing, so a converter never has to reason about which normalisation `nx`
    /// happens to be relative to.
    let windowNormalized: CGPoint
    let concurrent: Int
    let isPencil: Bool
    let force: CGFloat
    let maxForce: CGFloat
    let altitude: CGFloat
    let azimuth: CGFloat
    /// How many `.moved` samples the coalescer dropped since the last one written. Recorded so a
    /// reader can tell "the pen stopped moving" from "we thinned the data here".
    let coalescedAway: Int?
}

/// Intercepts `UIWindow.sendEvent(_:)` for the length of a recording, and nothing outside it.
///
/// **Why `sendEvent`.** It is the single funnel every touch in the app passes through, before
/// hit-testing, before any gesture recognizer, before any view's `touchesBegan`. Tapping it once
/// catches SwiftUI buttons, the UIKit timeline, the layer table and the canvas alike. Every
/// alternative needs instrumenting per control:
///
/// - Rejected: **a `UIGestureRecognizer` attached to the window** as a touch spy. It is the popular
///   answer and it is subtly wrong for this app: when another recognizer recognises with
///   `cancelsTouchesInView`, the spy receives `touchesCancelled` instead of the real `touchesEnded`
///   — so the one thing being hunted here (which recognizer terminated, and when) is exactly what
///   that route corrupts.
/// - Rejected: **`.onTapGesture`/callbacks per control.** ~100 edit sites, each a chance to change
///   behaviour, and it still would not see the canvas.
///
/// **Why the subclass is synthesised at runtime.** SwiftUI's `WindowGroup` owns window creation, so
/// there is no place to hand UIKit a `RecordingWindow` class — the only way to get one is a
/// `UIApplicationDelegateAdaptor` plus a `UIWindowSceneDelegate` that builds its own window and hosts
/// `ContentView` in a `UIHostingController`. That is taking scene lifecycle away from `WindowGroup`
/// permanently, in exchange for a debugging feature that is off by default: the wrong trade. So
/// instead this allocates a subclass **of whatever class the live window actually is**, overrides
/// `sendEvent:` on it, and points the existing instance at it with `object_setClass` — the same
/// mechanism KVO uses, and safe for the same reason: the subclass declares no stored properties, so
/// the instance's size and ivar layout are untouched. Subclassing the *actual* class rather than
/// `UIWindow` matters: the day SwiftUI hands us a private `UIWindow` subclass, hard-coding `UIWindow`
/// would silently discard that class's own behaviour, while this inherits it.
///
/// Rejected alternative: **global `method_exchangeImplementations` on `UIWindow.sendEvent`.** Fewer
/// lines, and it breaks the moment the live window is a subclass that overrides `sendEvent` itself,
/// because the swizzled `UIWindow` implementation is then never reached. It is also process-wide,
/// which is a poor fit for something that must be provably inert when off.
///
/// **Cost when off: zero.** `uninstall()` restores the original class, so the app's own unmodified
/// `sendEvent` is what runs, with no branch of ours in it.
@objc final class WindowEventTap: NSObject {
    /// Found by the synthesised `sendEvent:` override, which has no other way to reach `self`.
    /// Weak: `ActionRecorder` owns the tap for the length of a recording.
    static weak var current: WindowEventTap?

    struct InstallReport {
        let originalClass: String?
        let interceptedClass: String?
        let note: String
    }

    private weak var window: UIWindow?
    private var originalClass: AnyClass?

    // MARK: - Install / uninstall

    /// The app's key window. `connectedScenes` rather than the deprecated `UIApplication.windows`,
    /// and `isKeyWindow` rather than `.first` because on iPad an alert or a `PhotosPicker` can put a
    /// second window on screen and tapping the wrong one records nothing.
    static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    func install() -> InstallReport {
        guard let window = Self.activeWindow() else {
            return InstallReport(originalClass: nil, interceptedClass: nil, note: "no window on screen yet")
        }
        let original: AnyClass = object_getClass(window)!
        guard let intercepting = Self.interceptingClass(for: original) else {
            return InstallReport(originalClass: NSStringFromClass(original), interceptedClass: nil,
                                 note: "couldn't synthesise a sendEvent: override for \(NSStringFromClass(original))")
        }
        self.window = window
        self.originalClass = original
        Self.current = self
        object_setClass(window, intercepting)

        rescanRecognizers()

        return InstallReport(originalClass: NSStringFromClass(original),
                             interceptedClass: NSStringFromClass(intercepting),
                             note: "ok")
    }

    func uninstall() {
        if let window, let originalClass {
            object_setClass(window, originalClass)
        }
        for entry in registry {
            entry.recognizer?.removeTarget(self, action: #selector(recognizerFired(_:)))
        }
        registry.removeAll()
        targeted.removeAll()
        tracks.removeAll()
        window = nil
        originalClass = nil
        if Self.current === self { Self.current = nil }
    }

    /// Builds (once per process, then cached by name) a subclass of `original` whose `sendEvent:`
    /// brackets the original implementation with the recorder.
    ///
    /// The original implementation is captured as a C function pointer and called directly rather
    /// than through `objc_msgSendSuper` — Swift cannot call the variadic `objc_msgSendSuper` at all,
    /// and calling the captured IMP is what a super-send does anyway.
    private static func interceptingClass(for original: AnyClass) -> AnyClass? {
        let name = "PaintSoftwareRecording_" + NSStringFromClass(original)
        if let cached = NSClassFromString(name) { return cached }

        let selector = #selector(UIWindow.sendEvent(_:))
        guard let method = class_getInstanceMethod(original, selector),
              // extraBytes: 0 — no stored properties, so the instance layout is unchanged and
              // `object_setClass` on a live window is safe.
              let subclass = objc_allocateClassPair(original, name, 0) else { return nil }

        typealias SendEventIMP = @convention(c) (AnyObject, Selector, UIEvent) -> Void
        let callOriginal = unsafeBitCast(method_getImplementation(method), to: SendEventIMP.self)

        let block: @convention(block) (AnyObject, UIEvent) -> Void = { receiver, event in
            // UIKit delivers UI events on the main thread and only on the main thread; asserting it
            // here rather than hopping is the point — a hop would reorder the recording relative to
            // the app's own reaction to the same event, which is the whole value of the file.
            MainActor.assumeIsolated {
                let window = receiver as? UIWindow
                let tap = WindowEventTap.current
                // Touches are logged *before* dispatch and recognizer states *after*, so the file
                // reads as cause then effect: the touch line, then the transitions it produced.
                tap?.willSend(event, window: window)
                callOriginal(receiver, selector, event)
                tap?.didSend(event)
            }
        }
        guard class_addMethod(subclass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method)) else {
            objc_disposeClassPair(subclass)
            return nil
        }
        objc_registerClassPair(subclass)
        return subclass
    }

    // MARK: - Event handling

    private func willSend(_ event: UIEvent, window: UIWindow?) {
        guard event.type == .touches, let window, let touches = event.allTouches else { return }
        let recorder = ActionRecorder.shared
        // Counted from the whole event, not from the touches we end up writing: "how many fingers
        // are down" is the thing that separates a two-finger pan from a one-finger draw, and it has
        // to be right even on an event where only one of them moved.
        let concurrent = touches.reduce(into: 0) { count, touch in
            switch touch.phase {
            case .began, .moved, .stationary: count += 1
            default: break
            }
        }
        for touch in touches {
            guard let sample = sample(touch, in: window, event: event, concurrent: concurrent, recorder: recorder) else { continue }
            recorder.touch(sample)
        }
    }

    private func didSend(_ event: UIEvent) {
        guard event.type == .touches else { return }
        sweepRecognizerStates()
    }

    // MARK: - Touch sampling and coalescing

    /// Per-touch state that lives for one touch sequence.
    private struct Track {
        let touchID: Int
        var lastPhase: UITouch.Phase
        var lastEmittedTime: Double
        var lastEmittedPoint: CGPoint
        var skippedSinceEmit: Int
        /// Resolved once, at `.began`, and reused for the whole sequence — see `targetFrame`.
        var target: ResolvedTarget
        var targetFrame: CGRect
    }

    private var tracks: [ObjectIdentifier: Track] = [:]
    private var nextTouchID = 1

    /// Coalescing thresholds for `.moved`. `began`/`ended`/`cancelled` are never thinned — they are
    /// the events the whole file is structured around, and there are only ever a handful of them.
    ///
    /// **What was chosen and why:** a move is written when it has been at least 50 ms (≈20 Hz) *and*
    /// the touch has travelled at least 2 pt since the last one written, **or** when it has travelled
    /// 24 pt regardless of time. The two halves cover the two failure modes of a single rule. A pure
    /// 20 Hz clock turns a fast flick — which on this iPad can cross 400 pt in 150 ms — into three
    /// samples and loses the path's shape, so the distance escape hatch adds detail exactly where
    /// speed removed it. A pure distance rule writes nothing at all for a finger held still, which is
    /// wrong for a long-press: the 50 ms clock keeps a heartbeat. The 2 pt floor is what keeps a
    /// resting palm's jitter from filling the file with duplicate lines.
    ///
    /// The alternative — recording at the full event rate, including `coalescedTouches` — was
    /// rejected on the file's *primary* consumer: a three-second stroke is 360 samples at 120 Hz, and
    /// a file a human cannot scroll through is a file nobody reads. `skipped` on each line records
    /// what was dropped, so nothing is lost silently.
    private static let moveMinInterval: Double = 0.05
    private static let moveMinDistance: CGFloat = 2
    private static let moveForceDistance: CGFloat = 24

    private func sample(_ touch: UITouch, in window: UIWindow, event: UIEvent, concurrent: Int, recorder: ActionRecorder) -> TouchSample? {
        let key = ObjectIdentifier(touch)
        let phase = touch.phase
        // Hover phases (`regionEntered`/`regionMoved`/`regionExited`, which an Apple Pencil Pro and a
        // trackpad both produce) are deliberately not recorded: they are not replayable by XCUITest
        // in any form, and at hover rate they would outnumber the real touches several to one.
        guard phase == .began || phase == .moved || phase == .ended || phase == .cancelled || phase == .stationary else { return nil }

        let point = touch.location(in: window)
        let time = recorder.stamp(touch.timestamp)

        if phase == .began {
            let resolved = resolveTarget(for: touch, at: point, in: window, event: event)
            let track = Track(touchID: nextTouchID, lastPhase: .began, lastEmittedTime: time,
                              lastEmittedPoint: point, skippedSinceEmit: 0,
                              target: resolved.target, targetFrame: resolved.frameInWindow)
            tracks[key] = track
            nextTouchID += 1
            return makeSample(touch, track: track, phase: "began", point: point, time: time,
                              concurrent: concurrent, skipped: nil, windowSize: window.bounds.size)
        }

        // A touch we never saw begin (recording started mid-gesture). Adopt it rather than drop it —
        // its `ended` is still evidence, and dropping it is how a file ends up showing a stroke that
        // never finished when in fact we simply were not watching yet.
        guard var track = tracks[key] else {
            guard phase != .stationary else { return nil }
            let resolved = resolveTarget(for: touch, at: point, in: window, event: event)
            let adopted = Track(touchID: nextTouchID, lastPhase: phase, lastEmittedTime: time,
                                lastEmittedPoint: point, skippedSinceEmit: 0,
                                target: resolved.target, targetFrame: resolved.frameInWindow)
            tracks[key] = adopted
            nextTouchID += 1
            return makeSample(touch, track: adopted, phase: name(for: phase), point: point, time: time,
                              concurrent: concurrent, skipped: nil, windowSize: window.bounds.size)
        }

        switch phase {
        case .stationary:
            return nil
        case .moved:
            let dx = point.x - track.lastEmittedPoint.x
            let dy = point.y - track.lastEmittedPoint.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let elapsed = time - track.lastEmittedTime
            let worthWriting = (elapsed >= Self.moveMinInterval && distance >= Self.moveMinDistance)
                || distance >= Self.moveForceDistance
            guard worthWriting else {
                track.skippedSinceEmit += 1
                track.lastPhase = .moved
                tracks[key] = track
                return nil
            }
            let skipped = track.skippedSinceEmit
            track.skippedSinceEmit = 0
            track.lastEmittedTime = time
            track.lastEmittedPoint = point
            track.lastPhase = .moved
            tracks[key] = track
            return makeSample(touch, track: track, phase: "moved", point: point, time: time,
                              concurrent: concurrent, skipped: skipped, windowSize: window.bounds.size)
        case .ended, .cancelled:
            // Guard against UIKit repeating a terminal phase in a later event for the same touch.
            guard track.lastPhase != phase else { return nil }
            let skipped = track.skippedSinceEmit
            tracks.removeValue(forKey: key)
            return makeSample(touch, track: track, phase: name(for: phase), point: point, time: time,
                              concurrent: concurrent, skipped: skipped, windowSize: window.bounds.size)
        default:
            return nil
        }
    }

    private func makeSample(_ touch: UITouch, track: Track, phase: String, point: CGPoint,
                            time: Double, concurrent: Int, skipped: Int?, windowSize: CGSize) -> TouchSample {
        let frame = track.targetFrame
        // Normalised inside the target's frame **as it stood when the touch began**. Deliberately not
        // re-measured per sample: the canvas container is transformed live during a two-finger pan,
        // so a per-sample frame would make a straight drag read as a curve. Values outside 0–1 mean
        // the touch left its starting element, which `coordinate(withNormalizedOffset:)` handles.
        let nx = frame.width > 0 ? (point.x - frame.minX) / frame.width : 0
        let ny = frame.height > 0 ? (point.y - frame.minY) / frame.height : 0
        let isPencil = touch.type == .pencil
        return TouchSample(
            time: time,
            phase: phase,
            type: typeName(touch.type),
            touchID: track.touchID,
            target: track.target.identifier,
            targetClass: track.target.identifierClass,
            hitClass: track.target.hitClass,
            role: track.target.role,
            label: track.target.label,
            depth: track.target.depth,
            resolution: track.target.resolution,
            normalized: CGPoint(x: nx, y: ny),
            window: point,
            windowNormalized: CGPoint(x: windowSize.width > 0 ? point.x / windowSize.width : 0,
                                      y: windowSize.height > 0 ? point.y / windowSize.height : 0),
            concurrent: concurrent,
            isPencil: isPencil,
            force: isPencil ? touch.force : 0,
            maxForce: isPencil ? touch.maximumPossibleForce : 0,
            altitude: isPencil ? touch.altitudeAngle : 0,
            azimuth: isPencil ? touch.azimuthAngle(in: nil) : 0,
            coalescedAway: skipped
        )
    }

    private func name(for phase: UITouch.Phase) -> String {
        switch phase {
        case .began: return "began"
        case .moved: return "moved"
        case .stationary: return "stationary"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        default: return "phase\(phase.rawValue)"
        }
    }

    /// `.pencil` vs `.direct` is recorded on every single sample, never inferred and never elided.
    /// Two of the bugs being chased turn on it (pencil-only mode swallowing a finger; a palm touch
    /// racing the pen), and XCUITest cannot synthesise a pencil at all — so the converter needs it on
    /// the line in front of it to know when to refuse.
    private func typeName(_ type: UITouch.TouchType) -> String {
        switch type {
        case .direct: return "direct"
        case .indirect: return "indirect"
        case .pencil: return "pencil"
        case .indirectPointer: return "pointer"
        @unknown default: return "type\(type.rawValue)"
        }
    }

    // MARK: - Resolving what was actually hit

    struct ResolvedTarget {
        var identifier: String?
        var identifierClass: String
        var hitClass: String
        var role: String
        var label: String?
        var depth: Int
        var resolution: String
    }

    /// Finds the identifier an XCUITest would use for this touch, and the frame the normalised offset
    /// is measured against.
    ///
    /// Two searches, in this order, because **SwiftUI does not put its identifiers on `UIView`s.**
    /// `.accessibilityIdentifier("toolbar.selectButton")` on a SwiftUI `Button` lands on an
    /// accessibility *element* vended by a host view, not on any view's `accessibilityIdentifier` —
    /// so a superview walk alone would come back empty for most of this app's chrome, which is
    /// precisely the part a replayed test needs to drive. The accessibility tree is also literally
    /// what XCUITest queries, so an identifier found there is one a test can address by construction.
    /// The `UIView` walk still matters for the UIKit half (`canvas.host` and friends) and is tried
    /// second because it is coarser: it answers "which container" rather than "which control".
    ///
    /// ## Known limitation, measured rather than assumed
    ///
    /// **SwiftUI builds its accessibility elements lazily, and only once an accessibility *client* is
    /// attached to the process** — VoiceOver, Accessibility Inspector, or an XCUITest runner. With
    /// none of them running, `_UIHostingView.accessibilityElements` is nil and
    /// `accessibilityElementCount()` is 0, so the `ax` searches below find nothing and a tap on a
    /// SwiftUI button records `"target": null`. Verified on the iPad Pro 13-inch (M4) simulator,
    /// iOS 26.5: three separate captures, one of them after forcing
    /// `com.apple.Accessibility ApplicationAccessibilityEnabled` and posting the AX cache
    /// notifications into the running app, all recorded null for the same toolbar taps. There is no
    /// public API for an app to enable accessibility on itself, so this cannot be fixed from in here.
    ///
    /// What that costs, concretely, and why it was accepted:
    /// - **The canvas is unaffected**, and the canvas is where the bugs being chased live. It is
    ///   UIKit (`StrokeCanvasView` inside `CanvasHostView`), so it resolves through the `UIView` walk
    ///   every time, as `canvas.host` at depth 3.
    /// - Chrome taps still carry `wnx`/`wny` (window-normalised, replayable) and `hitClass`, and the
    ///   `model` line that follows almost always names what the tap did — `activePanel = actions`
    ///   after a tap at the wrench. A reader loses nothing; a converter emits a coordinate tap and a
    ///   TODO instead of an element query.
    /// - **Recording under an XCUITest run resolves everything**, because the runner is exactly the
    ///   missing client. That is the route to take if a fully-identified capture is ever needed.
    ///
    /// The fix, if it is ever worth the diff, is a `UIViewRepresentable` tag view behind each control
    /// carrying the same string in `UIView.accessibilityIdentifier`, found here by a geometric search
    /// over `UIView` frames. That is ~140 edit sites across every view file in the app, for chrome
    /// taps that are already legible from the model events beside them — which is why it was not done.
    private func resolveTarget(for touch: UITouch, at point: CGPoint, in window: UIWindow, event: UIEvent) -> (target: ResolvedTarget, frameInWindow: CGRect) {
        // `touch.view` is nil for a `.began` touch here: hit-testing happens *inside* the
        // `sendEvent` we are wrapping, and we run before it. Doing the hit test ourselves gives the
        // same answer UIKit is about to compute. Safe to repeat — the two `hitTest` overrides in this
        // app (`ShapeOverlayView`, `GuideOverlayView`) are pure geometry with no side effects.
        let hitView = touch.view ?? window.hitTest(point, with: event)
        let hitClass = hitView.map { String(describing: type(of: $0)) } ?? "none"
        let screenPoint = Self.screenPoint(point, in: window)

        if let hit = hitView,
           let found = Self.accessibilityElement(at: screenPoint, under: hit, depth: 0) {
            return (ResolvedTarget(identifier: found.identifier,
                                   identifierClass: String(describing: type(of: found.element)),
                                   hitClass: hitClass,
                                   role: Self.role(for: found.traits),
                                   label: found.label,
                                   depth: found.depth,
                                   resolution: "ax"),
                    Self.windowRect(found.screenFrame, in: window))
        }

        var view = hitView
        var depth = 0
        while let current = view {
            if let identifier = current.accessibilityIdentifier, !identifier.isEmpty {
                return (ResolvedTarget(identifier: identifier,
                                       identifierClass: String(describing: type(of: current)),
                                       hitClass: hitClass,
                                       role: Self.role(for: current.accessibilityTraits),
                                       label: current.accessibilityLabel,
                                       depth: depth,
                                       resolution: "view"),
                        current.convert(current.bounds, to: window))
            }
            view = current.superview
            depth += 1
        }

        // Last resort: the whole accessibility tree from the window down. Expensive (it is a full
        // walk) but it only runs on `began`/`ended`, only while recording, and only when the two
        // cheap searches failed — and coming back with an identifier is the difference between a
        // replayable line and a dead one.
        if let found = Self.accessibilityElement(at: screenPoint, under: window, depth: 0) {
            return (ResolvedTarget(identifier: found.identifier,
                                   identifierClass: String(describing: type(of: found.element)),
                                   hitClass: hitClass,
                                   role: Self.role(for: found.traits),
                                   label: found.label,
                                   depth: found.depth,
                                   resolution: "ax-window"),
                    Self.windowRect(found.screenFrame, in: window))
        }

        let frame = hitView.map { $0.convert($0.bounds, to: window) } ?? window.bounds
        return (ResolvedTarget(identifier: nil, identifierClass: "none", hitClass: hitClass,
                               role: "other", label: nil, depth: 0, resolution: "none"),
                frame)
    }

    private struct FoundElement {
        let element: NSObject
        let identifier: String
        let label: String?
        let traits: UIAccessibilityTraits
        let screenFrame: CGRect
        let depth: Int
    }

    /// Depth-first search of the accessibility tree for the **smallest** identified element whose
    /// frame contains the point. Smallest, not first: containers legitimately overlap their contents,
    /// and a test that taps the panel instead of the button in it is a test that does nothing.
    ///
    /// Bounded at 4,000 nodes and 40 levels. SwiftUI builds these elements lazily on the first query,
    /// so an unbounded walk of a screen full of layer rows is a real cost even at `began` rate; the
    /// bound is generous enough that no screen in this app comes close, and it means a pathological
    /// tree degrades the recording rather than the app.
    private static func accessibilityElement(at screenPoint: CGPoint, under root: NSObject, depth: Int) -> FoundElement? {
        var visited = 0
        return search(root, screenPoint, depth, &visited)
    }

    private static func search(_ node: NSObject, _ point: CGPoint, _ depth: Int, _ visited: inout Int) -> FoundElement? {
        guard depth < 40, visited < 4000 else { return nil }
        visited += 1

        var best: FoundElement?
        func consider(_ candidate: FoundElement?) {
            guard let candidate else { return }
            if let current = best {
                let currentArea = current.screenFrame.width * current.screenFrame.height
                let candidateArea = candidate.screenFrame.width * candidate.screenFrame.height
                if candidateArea < currentArea { best = candidate }
            } else {
                best = candidate
            }
        }

        let frame = node.accessibilityFrame
        // `accessibilityIdentifier` lives on `UIAccessibilityIdentification`, not on the informal
        // `NSObject` accessibility protocol the rest of these properties come from — so it needs the
        // cast. Both things that can appear in this tree (`UIView` and `UIAccessibilityElement`)
        // conform, so the cast never actually fails in practice.
        if let identifier = (node as? UIAccessibilityIdentification)?.accessibilityIdentifier, !identifier.isEmpty,
           frame.width > 0, frame.height > 0, frame.contains(point) {
            consider(FoundElement(element: node, identifier: identifier, label: node.accessibilityLabel,
                                  traits: node.accessibilityTraits, screenFrame: frame, depth: depth))
        }

        // Two ways a container vends children, and both are in use here — so both are asked, not one
        // or the other. `accessibilityElements` returning an **empty array rather than nil** is the
        // trap: an `else` would then never reach the count/index pair, and SwiftUI's hosting view is
        // exactly the node that does that. Asking both ways costs one extra message send on a node
        // that already answered, and it is the difference between resolving `toolbar.actionsButton`
        // and writing `"target": null` for every button in the app.
        var childCount = 0
        if let elements = node.accessibilityElements as? [NSObject], !elements.isEmpty {
            childCount = elements.count
            for child in elements {
                consider(search(child, point, depth + 1, &visited))
            }
        }
        if childCount == 0 {
            let count = node.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    guard let child = node.accessibilityElement(at: index) as? NSObject else { continue }
                    consider(search(child, point, depth + 1, &visited))
                }
            }
        }
        if let view = node as? UIView {
            for subview in view.subviews where !subview.isHidden && subview.alpha > 0.01 {
                consider(search(subview, point, depth + 1, &visited))
            }
        }
        return best
    }

    /// Accessibility traits mapped to the XCUIElement type the converter should emit. Only the types
    /// this app actually vends are distinguished; everything else falls through to `other`, which the
    /// converter turns into an untyped descendant query rather than a wrong guess.
    private static func role(for traits: UIAccessibilityTraits) -> String {
        if traits.contains(.button) { return "button" }
        if traits.contains(.adjustable) { return "slider" }
        if traits.contains(.link) { return "link" }
        if traits.contains(.searchField) { return "searchField" }
        if traits.contains(.header) { return "staticText" }
        if traits.contains(.image) { return "image" }
        if traits.contains(.staticText) { return "staticText" }
        return "other"
    }

    /// Window → screen. `UIAccessibility.convertToScreenCoordinates` is the only public API that
    /// answers this without reaching for `UIScreen.coordinateSpace`, which is unavailable on some of
    /// the platforms this target claims to support (`SUPPORTED_PLATFORMS` includes xrOS). A window is
    /// never rotated or scaled relative to the screen, so the whole conversion is the origin offset.
    private static func screenPoint(_ point: CGPoint, in window: UIWindow) -> CGPoint {
        let origin = UIAccessibility.convertToScreenCoordinates(window.bounds, in: window).origin
        return CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }

    private static func windowRect(_ screenRect: CGRect, in window: UIWindow) -> CGRect {
        let origin = UIAccessibility.convertToScreenCoordinates(window.bounds, in: window).origin
        return screenRect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: - Gesture recognizers

    private final class Entry {
        weak var recognizer: UIGestureRecognizer?
        let name: String
        let objectID: ObjectIdentifier
        var lastState: UIGestureRecognizer.State

        init(recognizer: UIGestureRecognizer, name: String) {
            self.recognizer = recognizer
            self.name = name
            self.objectID = ObjectIdentifier(recognizer)
            self.lastState = recognizer.state
        }
    }

    private var registry: [Entry] = []
    private var targeted: Set<ObjectIdentifier> = []

    /// Discovers every named recognizer under the window and starts watching it.
    ///
    /// Discovery by walking the hierarchy, rather than by each recognizer registering itself, is what
    /// keeps this free when off: the app's only contribution is `recognizer.name = "canvas.pan"` at
    /// creation, which is a stored-property write on a `UIGestureRecognizer` and costs nothing at
    /// runtime. `UIGestureRecognizer.name` exists for exactly this — debugging — and nothing in the
    /// app reads it.
    ///
    /// Re-run on the flush tick because layers, and therefore `StrokeGestureRecognizer`s, appear and
    /// vanish while recording.
    func rescanRecognizers() {
        guard let window else { return }
        var found: [Entry] = []
        var seen: Set<ObjectIdentifier> = []
        collect(from: window, into: &found, seen: &seen)

        // Preserve `lastState` for recognizers we were already watching, so a rescan mid-gesture
        // doesn't resynthesise a transition that already went into the file.
        let previous = Dictionary(uniqueKeysWithValues: registry.map { ($0.objectID, $0.lastState) })
        for entry in found {
            if let state = previous[entry.objectID] { entry.lastState = state }
            if !targeted.contains(entry.objectID), let recognizer = entry.recognizer {
                // Adding a target is additive: it makes UIKit deliver action messages we then log,
                // and changes nothing about recognition, precedence or failure requirements. It is
                // the least invasive way to see a stock recognizer's transitions — we do not own
                // `UIPanGestureRecognizer` and cannot put a hook inside it.
                recognizer.addTarget(self, action: #selector(recognizerFired(_:)))
                targeted.insert(entry.objectID)
            }
        }
        registry = found
    }

    private func collect(from view: UIView, into entries: inout [Entry], seen: inout Set<ObjectIdentifier>) {
        for recognizer in view.gestureRecognizers ?? [] {
            guard let name = recognizer.name, !name.isEmpty else { continue }
            let id = ObjectIdentifier(recognizer)
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            entries.append(Entry(recognizer: recognizer, name: name))
        }
        for subview in view.subviews {
            collect(from: subview, into: &entries, seen: &seen)
        }
    }

    /// UIKit delivered an action message. Catches transitions that happen **outside** an event —
    /// a long-press's timer firing, a `require(toFail:)` relationship resolving — which the post-event
    /// sweep would not see until the next touch, if ever.
    @objc private func recognizerFired(_ recognizer: UIGestureRecognizer) {
        guard ActionRecorder.isCapturing else { return }
        note(recognizer, source: "action")
    }

    /// Reads every watched recognizer's state after the event has been dispatched and writes whatever
    /// changed.
    ///
    /// **This is what makes `.failed` visible.** UIKit sends action messages for `began`/`changed`/
    /// `ended`/`cancelled` but **not for `.failed`** — verified against this app's own recognizers,
    /// and it is why the target-action route alone is not enough. `.failed` is exactly the state that
    /// matters here: `StrokeGestureRecognizer.failTrackedStroke` drives the transform recognizers'
    /// `require(toFail:)`, so a stroke recognizer that never reaches it is the deadlock. The sweep
    /// catches it, along with UIKit's own reset back to `.possible`.
    ///
    /// The two routes compose rather than duplicate: both update `lastState`, so whichever notices a
    /// transition first is the one that writes it, and `src` on the line says which that was.
    private func sweepRecognizerStates() {
        for entry in registry {
            guard let recognizer = entry.recognizer else { continue }
            let state = recognizer.state
            guard state != entry.lastState else { continue }
            ActionRecorder.shared.recognizer(entry.name, object: entry.objectID,
                                             from: entry.lastState, to: state, source: "sweep")
            entry.lastState = state
        }
    }

    /// Records a transition for a recognizer we own the source of (`StrokeGestureRecognizer`), keeping
    /// the registry's `lastState` in step so the sweep doesn't write it a second time.
    func noteTransition(_ recognizer: UIGestureRecognizer, to newState: UIGestureRecognizer.State, source: String) {
        guard let entry = registry.first(where: { $0.objectID == ObjectIdentifier(recognizer) }) else {
            // Not discovered yet (created since the last rescan). Still worth writing — a nameless
            // line is better than a missing transition — and the name falls back to the class.
            ActionRecorder.shared.recognizer(recognizer.name ?? String(describing: type(of: recognizer)),
                                             object: ObjectIdentifier(recognizer),
                                             from: recognizer.state, to: newState, source: source)
            return
        }
        guard entry.lastState != newState else { return }
        ActionRecorder.shared.recognizer(entry.name, object: entry.objectID,
                                         from: entry.lastState, to: newState, source: source)
        entry.lastState = newState
    }

    private func note(_ recognizer: UIGestureRecognizer, source: String) {
        noteTransition(recognizer, to: recognizer.state, source: source)
    }

    /// The name a recognizer is known by in the file, for the `requireFailure` lines — which name two
    /// recognizers that may not both be in the registry yet.
    func displayName(for recognizer: UIGestureRecognizer) -> String {
        recognizer.name ?? String(describing: type(of: recognizer))
    }
}
