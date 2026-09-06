import SwiftUI

extension View {
    /// Declares a `.popover` **and** its answer to "what happens when the artist touches the canvas".
    ///
    /// **This is the only way a `CanvasPresentation` may be presented.** A bare `.popover` still
    /// compiles — Swift has no way to forbid a modifier from the standard library — but it cannot get
    /// a `CanvasPresentation` case for free: the enum's `overlapsLiveCanvas` is an exhaustive
    /// `switch` with no `default:`, so adding a case is a decision the compiler makes you state, and
    /// `CanvasPresentationLogicTests` fails when a case is added without an entry in its
    /// hand-written table. What is left unguarded is somebody writing `.popover` and adding no case
    /// at all; `MENU_PRESENTATION_CENSUS.md` is the standing record of what that would look like, and
    /// `tools/presentation-census.sh` is the thirty-second check.
    ///
    /// What this buys over the two hand-written `interactionBegan` sinks it replaces:
    ///
    /// - **The dismissal is central.** `CanvasManager.dismissPresentationsOverLiveCanvas()` closes
    ///   every registered presentation whose case says it can sit over a live canvas. Nobody has to
    ///   remember a line in a file three hundred lines away from the popover they just wrote.
    /// - **`onDismiss` runs however the presentation ends**, including when its host view is
    ///   *deleted* out from under it. Three sites in this app open an undo bracket when a colour
    ///   picker appears and close it in `.onChange(of:)`, which does not fire on host deletion; each
    ///   had grown its own hand-written `.onDisappear` to patch that, and each of those was one more
    ///   line somebody had to know to write. Now it is the modifier's.
    /// - **The registry is observable**, so a logic test can drive the whole rule with no simulator
    ///   and a device capture can say what was on screen.
    ///
    /// - Parameters:
    ///   - presentation: which case this is. One case is presented from one place, except
    ///     `effectGradientStopColour`, where every stop row carries the same case and only one can be
    ///     open at a time (`colorPickerIndex` is a single optional index).
    ///   - isPresented: the site's own state, unchanged. The modifier writes `false` to it when the
    ///     central rule fires, and reads it in `onDisappear` to tell "the host went away while this
    ///     was up" from "this was already closed".
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
        modifier(CanvasPresentationModifier(presentation: presentation,
                                            isPresented: isPresented,
                                            canvasManager: canvasManager,
                                            onPresent: onPresent,
                                            onDismiss: onDismiss,
                                            presentedContent: content))
    }

    /// The contract above **without** the `.popover` — for a presentation this app draws itself.
    ///
    /// Everything `canvasPresentation` promises is promised here too: the case is registered while
    /// it is up, `CanvasManager.dismissPresentationsOverLiveCanvas()` still closes it, `onDismiss`
    /// still runs however it ends including host deletion, and `ActionRecorder` still sees it. What
    /// is different is only *who draws the thing*, and that is the whole of TODO (39): the
    /// timeline's four menus are anchored inside the app's own hierarchy (`AnchoredMenu`) because a
    /// `.popover` presents behind a screen-covering `_UIPassthroughGateGestureRecognizer` that
    /// swallows every drag on the timeline whole.
    ///
    /// **A site using this owes the drawing.** The four timeline menus are rendered by one layer in
    /// `AnimationTimeline`, which is why the content closure is absent rather than optional: there
    /// is nothing sensible for a modifier to do with content it is not going to present.
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

}

/// The one implementation of the contract above. Private on purpose: `canvasPresentation` is the
/// vocabulary, this is the plumbing.
private struct CanvasPresentationModifier<PresentedContent: View>: ViewModifier {
    let presentation: CanvasPresentation
    @Binding var isPresented: Bool
    @ObservedObject var canvasManager: CanvasManager
    let onPresent: (() -> Void)?
    let onDismiss: (() -> Void)?
    let presentedContent: () -> PresentedContent

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented) { presentedContent() }
            .modifier(CanvasPresentationRegistration(presentation: presentation,
                                                     isPresented: $isPresented,
                                                     canvasManager: canvasManager,
                                                     onPresent: onPresent,
                                                     onDismiss: onDismiss))
    }
}

/// The bookkeeping half, with no opinion about how the presentation is drawn — a `.popover` above,
/// an `AnchoredMenu` in `AnimationTimeline`. Factored out rather than written twice so that "what a
/// registered presentation guarantees" has exactly one implementation and the two presenters cannot
/// drift apart.
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
            // The central rule (`CanvasManager.dismissPresentationsOverLiveCanvas`) took this out of
            // the registry; bring the site's own binding down to match. Written as an observation of
            // the model rather than as another `.onReceive(interactionBegan)` so that there is
            // exactly one place in the app that decides *whether* a presentation closes on a canvas
            // touch, and it is the enum.
            .onChange(of: canvasManager.openPresentations.contains(presentation)) { _, stillOpen in
                if !stillOpen, isPresented { isPresented = false }
            }
            // The host view was deleted with this still up — `activePanel = .none` removing the layer
            // rail is the everyday way, and it is also exactly what a canvas touch does to the five
            // presentations that hang off it. `.onChange(of: isPresented)` cannot fire for that: the
            // state it watches is being destroyed, not written. Without this line the registry keeps
            // a presentation that is gone and every `onDismiss` bracket in the app leaks.
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
