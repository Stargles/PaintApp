import SwiftUI

/// The real-size stamp preview: a small window beside a held size slider showing **one dab of the
/// current brush at the size it will land on the artwork**, at the zoom the artist is looking at.
///
/// One component, used by both size sliders — the left rail's and the brush/eraser settings panel's
/// — rather than two implementations. The arithmetic and the visibility rule live in
/// `Models/SizePreview.swift` (a `View` file is not compiled into the test target, so anything a
/// fast-tier test has to reach cannot live here); this file is layers, colours and placement.
struct SizePreviewWindow: View {
    @ObservedObject var canvasManager: CanvasManager
    /// Its own object, so a pinch only re-renders this window and not every view bound to
    /// `CanvasManager` — see `CanvasDisplayScale`.
    @ObservedObject var canvasScale: CanvasDisplayScale
    let request: SizePreviewRequest
    /// The slider's frame, in the same space as `bounds`.
    let sliderFrame: CGRect
    let bounds: CGRect

    private var isEraser: Bool { request.tool == .eraser }

    private var brush: Brush {
        isEraser ? canvasManager.selectedEraserBrush : canvasManager.selectedBrush
    }

    /// Size and opacity are picked by the request itself (`SizePreviewRequest.toolSize`), not by a
    /// ternary here — the brush and the eraser keep entirely separate state and getting that pick
    /// wrong is exactly the sort of thing a `View` file makes untestable.
    private var geometry: SizePreviewGeometry {
        SizePreviewGeometry(toolSize: request.toolSize(brushSize: canvasManager.brushSize,
                                                       eraserSize: canvasManager.eraserSize),
                            canvasScale: canvasScale.scale)
    }

    private var opacity: Double {
        request.opacity(brushOpacity: canvasManager.brushOpacity,
                        eraserOpacity: canvasManager.eraserOpacity)
    }

    /// **TODO (79)(b): the permanent % badge over the rail's size icon is gone; this is where its
    /// number lives now** — beside the pop-up, and only while the pop-up itself is up, since
    /// `SizePreviewWindow` only exists on screen while a size slider is held.
    private var sizePercentText: String {
        SizePreviewPercentFormat.string(for: request.sizePercent(brushSizePercent: canvasManager.brushSizePercent,
                                                                  eraserSizePercent: canvasManager.eraserSizePercent))
    }

    var body: some View {
        let geometry = self.geometry
        let side = geometry.windowSide
        let origin = SizePreviewGeometry.windowOrigin(sliderFrame: sliderFrame, side: request.side,
                                                      windowSide: side, within: bounds)
        return VStack(spacing: 4) {
            Text(sizePercentText)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .accessibilityIdentifier("\(request.sliderID).percent")
                .accessibilityValue(sizePercentText)
            ZStack {
                // What the mark lands on. Paper for the brush; transparency, drawn as a
                // checkerboard, for the eraser — whose stamp is a hole in the ink above it.
                if isEraser {
                    CheckerboardPattern()
                } else {
                    Color.white
                }

                Image(uiImage: SizePreviewStampRenderer.stampImage(
                    geometry: geometry,
                    brush: brush,
                    tool: request.tool,
                    color: canvasManager.brushColor.resolvedUIColor(opacity: 1),
                    opacity: opacity
                ))
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(border(isClipped: geometry.isClipped))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 3)

            // The crop has to look like a decision, not a rendering fault. A dashed border alone
            // could be read either way, so it is said out loud as well.
            if geometry.isClipped {
                Text("actual size · clipped")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.95))
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
        }
        // `.offset` inside a top-leading frame rather than `.position`, because the caption makes
        // this stack taller than the window and `.position` centres the whole thing.
        .offset(x: origin.x, y: origin.y)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The diameter the stamp is actually drawn at, in screen points — what a UI test would have
        // to read to know the zoom was honoured, since the picture itself proves nothing.
        .accessibilityElement()
        .accessibilityIdentifier("sizePreview.window")
        .accessibilityValue(String(format: "%.2f", geometry.stampDiameter))
    }

    private func border(isClipped: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isClipped ? Color.orange.opacity(0.9) : Color.white.opacity(0.35),
                          style: StrokeStyle(lineWidth: isClipped ? 1.5 : 1,
                                             dash: isClipped ? [5, 4] : []))
    }
}

// MARK: - Wiring

/// Carries the frame of whichever size slider is currently held, up to the overlay that draws beside
/// it. An `Anchor<CGRect>` rather than a resolved rect so no coordinate space has to be named and
/// kept in agreement between two files.
struct SizePreviewAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// **TODO (79)(c).** Reports "a touch is down on this view", backed by `@GestureState` — which
/// SwiftUI resets to its initial value the moment the gesture it backs stops being active for *any*
/// reason, a normal lift or a cancellation alike. That is not true of `DragGesture.onEnded` or
/// `Slider.onEditingChanged(false)`, both of which fire only when UIKit delivers the touch's own end
/// back to *this* view — which does not happen when a second touch (a Pencil stroke beginning on the
/// canvas while a finger still holds this slider) is claimed by a gesture recognizer on a different
/// view entirely. `SizePreviewVisibility`'s doc comment has the fuller account of the bug this
/// replaced.
///
/// `minimumDistance: 0` is what makes the touch-**down** itself register with no movement required —
/// measured 2026-08-22, a press that never moves produces no `Slider.onEditingChanged` at all, which
/// is precisely the case the owner named ("when the sliders are pressed down"). `.simultaneousGesture`
/// at the call site keeps the slider's own drag intact — this only observes the touch.
private struct TouchTrackingModifier: ViewModifier {
    @GestureState private var isTouched = false
    let onChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouched) { _, isTouched, _ in isTouched = true }
            )
            .onChange(of: isTouched) { _, touched in onChanged(touched) }
    }
}

extension View {
    /// See `TouchTrackingModifier`.
    func trackingTouch(_ onChanged: @escaping (Bool) -> Void) -> some View {
        modifier(TouchTrackingModifier(onChanged: onChanged))
    }
}

extension View {
    /// Marks this view as a size slider that raises the preview.
    ///
    /// Publishes its own frame **only while it is the slider being held**, which is what keeps the
    /// preference a single value: two size sliders exist for the same `brushSize` (the rail's and the
    /// panel's) and at most one of them ever has a finger on it. `request` is `nil` for the sliders
    /// that are not size sliders, so the shared slider-row helpers in `StrokeSettingsPanel` and
    /// `SideToolbar` can apply this unconditionally instead of branching at every call site.
    ///
    /// A slider that is not a size slider comes back completely untouched — no preference, no
    /// gesture. The fill rail's three sliders and both opacity sliders go through the same helpers,
    /// and attaching even a no-op gesture to them would be a behaviour change to controls this
    /// feature has no business touching.
    @ViewBuilder
    func sizePreviewSlider(_ request: SizePreviewRequest?, canvasManager: CanvasManager) -> some View {
        if let request {
            anchorPreference(key: SizePreviewAnchorKey.self, value: .bounds) { anchor in
                canvasManager.sizePreview.active?.sliderID == request.sliderID ? anchor : nil
            }
            .trackingTouch { touched in
                canvasManager.sizePreview.editingChanged(touched, for: request)
            }
        } else {
            self
        }
    }

    /// Draws the preview beside whichever size slider is held. Applied once, high enough up the tree
    /// to cover both the left rail and the trailing settings panel — the rail is clipped by its own
    /// `cornerRadius`, so a window overlaid *inside* it would be cut off at the rail's edge.
    func sizePreviewOverlay(canvasManager: CanvasManager) -> some View {
        overlayPreferenceValue(SizePreviewAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let request = canvasManager.sizePreview.active, let anchor {
                    SizePreviewWindow(canvasManager: canvasManager,
                                      canvasScale: canvasManager.canvasDisplayScale,
                                      request: request,
                                      sliderFrame: proxy[anchor],
                                      bounds: CGRect(origin: .zero, size: proxy.size))
                        .transition(.opacity)
                }
            }
            // Never eats a touch: the finger that raised it is still down, and the artist may well
            // drag the slider under it.
            .allowsHitTesting(false)
        }
    }
}
