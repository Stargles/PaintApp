import CoreGraphics

/// Where a menu hung off `anchor` is drawn, given how big it turned out to be and how much room
/// there is.
///
/// **Its own file, with no SwiftUI in it, so the fast tier can pin it.** This is the half of an
/// anchored menu (TODO (39)) that a simulator answers slowly and expensively and a logic test
/// answers in milliseconds — every branch below is a case a device would need a contrived layout to
/// reach at all.
///
/// **Above the anchor by preference, because every caller is at the bottom of the screen.** The
/// timeline's four menus hang off the mini toolbar and off cel blocks in the track, so there is
/// almost never room below and almost always room above. `.popover` chose the same side for the
/// same reason; this makes the choice the app's rather than UIKit's.
enum AnchoredMenuPlacement {

    /// Between the anchor's edge and the menu — the visual gap a popover's arrow used to occupy.
    static let gap: CGFloat = 6

    /// How close to the edge of `bounds` the menu may come. Keeps a menu clamped against the top of
    /// the screen clear of the status bar, and one clamped sideways from looking cut off.
    static let margin: CGFloat = 8

    /// The menu's frame, in the same coordinate space as `anchor` and `bounds`.
    ///
    /// - Parameters:
    ///   - anchor: the control or block the menu belongs to.
    ///   - menuSize: the menu's measured size — its natural size, already resolved.
    ///   - bounds: what the menu should not leave.
    static func frame(anchor: CGRect, menuSize: CGSize, bounds: CGRect) -> CGRect {
        CGRect(origin: CGPoint(x: horizontalOrigin(anchor: anchor, width: menuSize.width, bounds: bounds),
                               y: verticalOrigin(anchor: anchor, height: menuSize.height, bounds: bounds)),
               size: menuSize)
    }

    /// Centred on the anchor, then clamped so the whole menu stays inside `bounds`.
    ///
    /// The clamp is written high-then-low deliberately: a menu **wider than the bounds** has no
    /// satisfying position, and applying the trailing clamp last would push its *leading* edge
    /// off-screen — which is the edge its content reads from. This way it starts at the margin and
    /// overflows to the trailing side.
    static func horizontalOrigin(anchor: CGRect, width: CGFloat, bounds: CGRect) -> CGFloat {
        let centred = anchor.midX - width / 2
        let clampedToTrailing = min(centred, bounds.maxX - margin - width)
        return max(bounds.minX + margin, clampedToTrailing)
    }

    /// Above the anchor if it fits there, below if it fits there, and otherwise on whichever side
    /// has more room — clamped either way, so a menu taller than the screen shows its **top** rather
    /// than running off it.
    static func verticalOrigin(anchor: CGRect, height: CGFloat, bounds: CGRect) -> CGFloat {
        let above = anchor.minY - gap - height
        if above >= bounds.minY + margin { return above }

        let below = anchor.maxY + gap
        if below + height <= bounds.maxY - margin { return below }

        let roomAbove = anchor.minY - bounds.minY
        let roomBelow = bounds.maxY - anchor.maxY
        let preferred = roomAbove >= roomBelow ? above : below
        return max(bounds.minY + margin, min(preferred, bounds.maxY - margin - height))
    }
}

/// Whether a touch that has just landed should take an open anchored menu down with it.
///
/// **Separate from the placement above and from the UIKit plumbing, because it is the rule**, and
/// TODO (39) is a bug about a rule UIKit was making instead of the app. A `.popover` answered this
/// question with a screen-covering `_UIPassthroughGateGestureRecognizer` that swallowed the whole
/// gesture; this answers it without consuming anything, so the same drag that closes the menu also
/// scrolls the track.
enum AnchoredMenuDismissal {

    /// - Parameters:
    ///   - point: where the touch went down, in the same space as the two frames.
    ///   - menuFrame: what the menu occupies. **Empty means "not laid out yet"**, and the answer is
    ///     then no: a menu is measured on one pass and positioned on the next, so there is a moment
    ///     between appearing and being placed. Answering yes there would let a touch that is still
    ///     down from *opening* the menu close it again on a slow frame, and the artist would see
    ///     nothing happen at all.
    ///   - toggleControlFrame: the control whose own action governs this menu's openness, if there
    ///     is one. **This exemption is load-bearing, not politeness.** Three of the timeline's four
    ///     menus hang off a button that toggles them; without it, this touch-*down* dismissal and
    ///     the button's touch-*up* `toggle()` compose into a menu that can never be closed from the
    ///     button that opened it — closed here, reopened a moment later by the toggle.
    static func shouldDismiss(touchAt point: CGPoint,
                              menuFrame: CGRect,
                              toggleControlFrame: CGRect?) -> Bool {
        guard !menuFrame.isEmpty else { return false }
        guard !menuFrame.contains(point) else { return false }
        if let toggle = toggleControlFrame, !toggle.isEmpty, toggle.contains(point) { return false }
        return true
    }
}
