import SwiftUI
import UIKit

/// **The timeline's keyframe control: tap inserts a key, hold 0.8 s enters or leaves Animate mode**
/// — KEYFRAMES.md §2.1, sitting in the timeline's own control strip beside onion skin, loop and
/// interpolate (§2.22).
///
/// ## Why this is UIKit when every other button in the strip is a SwiftUI `Button`
///
/// §10 is explicit that the hold *"must be a real gesture recognizer — not a `.contextMenu`, which
/// absorbs the whole touch, and never `UIDragInteraction`, which XCUITest cannot drive at all"*. That
/// rules two things out and leaves two in: SwiftUI's `.onLongPressGesture`, and a recognizer of our
/// own. The recognizer wins on three counts that are specific to this control rather than general
/// preference.
///
/// **The distances have to be chosen, not defaulted.** `AnimationTimeline` carries
/// `simultaneousGesture(resizeGesture)` — a `DragGesture(minimumDistance: 6)` — on the *whole* top
/// bar, this button included, so a hold whose finger wanders can resize the panel while it completes.
/// `UILongPressGestureRecognizer.allowableMovement` defaults to 10, which is above 6;
/// `KeyframeControl.holdAllowableMovement` is 4, which is below it, and that one number makes the two
/// gestures disjoint by construction. SwiftUI's `.onLongPressGesture(maximumDistance:)` can express
/// the same number, so this is not decisive on its own — but it is the reason the number exists.
///
/// **Tap and hold on one control must be arbitrated, not raced.** `tap.require(toFail: hold)` is the
/// whole arbitration and it costs the tap nothing: a long press *fails* the instant the touch ends
/// early, so a quick tap fires immediately rather than waiting out the 0.8 s. Stacking
/// `.onTapGesture` and `.onLongPressGesture` on a SwiftUI `Button` puts three gestures in one place
/// with the precedence decided by modifier order, which is the shape the app has been bitten by
/// before — `MotionGroupRow` records that *"two long presses of equal duration competing for one touch
/// have no stable winner"*, and `TimelineTrackView` declines to mode-overload its recognizer at all.
///
/// **§10 also requires this button be a dedicated, otherwise-untouched control**, which is why it is
/// a control of its own rather than a mode on something existing: cel-block pick-up and layer-name
/// reorder are both 0.5 s presses and the ruler runs a 0-duration press that scrubs on touch-down.
struct KeyframeButton: UIViewRepresentable {

    let isAnimateMode: Bool
    /// How many channels a tap would key. Zero dims the button — see `KeyframeControl.isDimmed`, and
    /// note that dimmed is not disabled: the *hold* still lands, because it is the only way into the
    /// mode and on a fresh document nothing is animated.
    let animatedChannelCount: Int
    /// Matches the enclosing bar's font — the collapsed bar is `.title3`, the mini toolbar is body —
    /// because the button is rendered from *both* and a fixed size would sit wrong in one of them.
    let pointSize: CGFloat
    let onTap: () -> Void
    let onHold: () -> Void

    func makeUIView(context: Context) -> KeyframeButtonView {
        let view = KeyframeButtonView()
        view.onTap = { onTap() }
        view.onHold = { onHold() }
        return view
    }

    /// Stated rather than left to SwiftUI's fallback, which for a representable with no explicit
    /// answer is to take whatever the proposal offers — in an `HStack` beside four `Image` buttons
    /// that is a control of an unpredictable width.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyframeButtonView,
                      context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    func updateUIView(_ view: KeyframeButtonView, context: Context) {
        // Re-bound every pass: the closures capture `self`, which SwiftUI rebuilds, so keeping the
        // first ones would leave the button acting on the state it was created with.
        view.onTap = { onTap() }
        view.onHold = { onHold() }
        view.configure(symbolName: KeyframeControl.symbolName(isAnimateMode: isAnimateMode),
                       pointSize: pointSize,
                       tint: isAnimateMode ? .systemBlue : .white,
                       isDimmed: KeyframeControl.isDimmed(isAnimateMode: isAnimateMode,
                                                          animatedChannelCount: animatedChannelCount),
                       status: KeyframeControl.statusValue(isAnimateMode: isAnimateMode,
                                                           animatedChannelCount: animatedChannelCount))
    }
}

/// The recognizer host. Separate from the representable so the gesture wiring is written once and the
/// representable is only the SwiftUI-facing shell.
final class KeyframeButtonView: UIView {

    var onTap: () -> Void = {}
    var onHold: () -> Void = {}

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true

        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = KeyframeControl.holdDuration
        hold.allowableMovement = KeyframeControl.holdAllowableMovement
        addGestureRecognizer(hold)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        // The tap waits for the hold to fail — which it does the instant a touch ends before 0.8 s, so
        // an ordinary tap is not delayed. Without this the two can both recognize on one touch.
        tap.require(toFail: hold)
        addGestureRecognizer(tap)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Keyframe"
        // Flat `timeline.<name>`, the namespace the rest of the strip already uses.
        accessibilityIdentifier = "timeline.keyframeButton"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A hit target rather than a glyph bound. The symbol is smaller than this; the extra points are
    /// what make an 0.8 s hold land on the button instead of beside it.
    override var intrinsicContentSize: CGSize { CGSize(width: 32, height: 32) }

    func configure(symbolName: String, pointSize: CGFloat, tint: UIColor,
                   isDimmed: Bool, status: String) {
        imageView.image = UIImage(systemName: symbolName,
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize,
                                                                                 weight: .regular))
        imageView.tintColor = tint
        imageView.alpha = isDimmed ? 0.35 : 1
        accessibilityValue = status
    }

    @objc private func handleTap() { onTap() }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        // `.began` is the 0.8 s mark with the finger still down, which is where the mode should flip:
        // waiting for `.ended` would make the artist hold, see nothing, and lift before finding out.
        guard recognizer.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onHold()
    }
}
