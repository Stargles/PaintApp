import SwiftUI

extension View {
    /// Declares a presentation over the canvas **and** its answer to "what happens when the artist
    /// touches outside it".
    ///
    /// **This is the only way a `CanvasPresentation` may be presented, and it is not a `.popover`.**
    /// The content is handed up to `canvasPresentationHost`, which draws it as an `AnchoredMenu`
    /// inside the app's own hierarchy, hung off the view this modifies — so no UIKit presentation, and
    /// no `_UIPassthroughGateGestureRecognizer`, ever sits over the canvas to be torn down under a live
    /// two-finger gesture (`CanvasPresentation`'s header has what that did).
    ///
    /// What the declaration buys:
    ///
    /// - **The dismissal is central.** `AnchoredMenuRouter` closes it when a touch lands outside both
    ///   it and the control it hangs off, whether that touch is a stroke, a two-finger pan or a tap on
    ///   the toolbar — and the touch goes on to do what it was going to do. The control is exempt so
    ///   that its own action decides: every site toggles, so a second tap on the swatch closes it.
    /// - **`onDismiss` runs however the presentation ends**, including when its host view is
    ///   *deleted* out from under it — `activePanel = .none` removing the layer rail is the everyday
    ///   way. Three sites open an undo bracket when a colour picker appears and close it here.
    /// - **The registry is observable** (`CanvasManager.openPresentations`), so a logic test can drive
    ///   it with no simulator and a device capture can say what was on screen.
    ///
    /// - Parameters:
    ///   - presentation: which case this is. One case is presented from one place, except
    ///     `effectGradientStopColour`, where every stop row carries the same case and only one can be
    ///     open at a time (`colorPickerIndex` is a single optional index).
    ///   - isPresented: the site's own state. The router writes `false` to it; it is read in
    ///     `onDisappear` to tell "the host went away while this was up" from "this was already closed".
    ///   - onPresent: runs when it appears — an undo bracket opening, typically.
    ///   - onDismiss: runs exactly once when it goes away, by any route.
    func canvasPresentation<PresentedContent: View>(
        _ presentation: CanvasPresentation,
        isPresented: Binding<Bool>,
        canvasManager: CanvasManager,
        onPresent: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> PresentedContent
    ) -> some View {
        anchorPreference(key: CanvasPresentationEntries.self, value: .bounds) { anchor in
            guard isPresented.wrappedValue else { return [] }
            return [CanvasPresentationEntry(presentation: presentation, anchor: anchor,
                                            dismiss: { isPresented.wrappedValue = false },
                                            content: AnyView(content()))]
        }
        .canvasPresentationRegistration(presentation, isPresented: isPresented,
                                        canvasManager: canvasManager,
                                        onPresent: onPresent, onDismiss: onDismiss)
    }

    /// The contract above **without** the drawing — for the timeline's menus, which
    /// `AnimationTimeline` draws in a layer of its own (TODO (39)).
    ///
    /// The case is registered while it is up, `onDismiss` still runs however it ends including host
    /// deletion, and the router still closes it: an `AnchoredMenu` reports its placement to the router
    /// whoever draws it.
    func canvasPresentationRegistration(_ presentation: CanvasPresentation,
                                        isPresented: Binding<Bool>,
                                        canvasManager: CanvasManager,
                                        onPresent: (() -> Void)? = nil,
                                        onDismiss: (() -> Void)? = nil) -> some View {
        modifier(CanvasPresentationRegistration(presentation: presentation,
                                                isPresented: isPresented,
                                                canvasManager: canvasManager,
                                                onPresent: onPresent,
                                                onDismiss: onDismiss))
    }

    /// **Where every `canvasPresentation` below this view is drawn, and the one router that closes
    /// all of them.** Applied once, at the root of the editor.
    ///
    /// An overlay the size of the editor, so a picker raised from the rail, the bottom dock or the
    /// timeline is drawn over everything and is hit-testable wherever it lands. A presentation raised
    /// from inside one this host draws would be drawn by nothing — the overlay that reads the entries
    /// does not read its own — and there is none: the one nesting, the onion tint pickers inside the
    /// onion menu, works because `AnimationTimeline` draws the onion menu in its own layer, which is
    /// part of the content read here.
    func canvasPresentationHost() -> some View {
        modifier(CanvasPresentationHost())
    }
}

/// One presentation that is up, as the host needs it: where it hangs from, how to close it, and what
/// to draw.
struct CanvasPresentationEntry: Identifiable {
    let presentation: CanvasPresentation
    let anchor: Anchor<CGRect>
    let dismiss: () -> Void
    let content: AnyView
    var id: CanvasPresentation { presentation }
}

private struct CanvasPresentationEntries: PreferenceKey {
    static let defaultValue: [CanvasPresentationEntry] = []
    static func reduce(value: inout [CanvasPresentationEntry], nextValue: () -> [CanvasPresentationEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct CanvasPresentationHost: ViewModifier {
    @State private var router = AnchoredMenuRouter()

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(CanvasPresentationEntries.self) { entries in
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    ForEach(entries) { entry in
                        // The control it hangs off is also the control that toggles it.
                        let anchor = proxy[entry.anchor].offsetBy(dx: origin.x, dy: origin.y)
                        AnchoredMenu(presentation: entry.presentation,
                                     anchor: anchor,
                                     toggleControl: anchor,
                                     identifier: "canvasPresentation.\(entry.presentation.rawValue)",
                                     onDismiss: entry.dismiss) {
                            entry.content
                        }
                    }
                }
            }
            .background(AnchoredMenuRouterHost(router: router))
            .environment(\.anchoredMenuRouter, router)
    }
}

/// The bookkeeping half, with no opinion about how the presentation is drawn. Factored out so that
/// "what a registered presentation guarantees" has exactly one implementation and the two drawers —
/// the host above and `AnimationTimeline`'s layer — cannot drift apart.
private struct CanvasPresentationRegistration: ViewModifier {
    let presentation: CanvasPresentation
    @Binding var isPresented: Bool
    @ObservedObject var canvasManager: CanvasManager
    let onPresent: (() -> Void)?
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, showing in
                if showing {
                    canvasManager.presentationDidAppear(presentation)
                    onPresent?()
                } else {
                    close()
                }
            }
            // The host view was deleted with this still up — `activePanel = .none` removing the layer
            // rail is the everyday way. `.onChange(of: isPresented)` cannot fire for that: the state it
            // watches is being destroyed, not written. Without this line the registry keeps a
            // presentation that is gone and every `onDismiss` bracket in the app leaks.
            .onDisappear {
                guard isPresented else { return }
                close()
            }
    }

    private func close() {
        canvasManager.presentationDidDisappear(presentation)
        onDismiss?()
    }
}
