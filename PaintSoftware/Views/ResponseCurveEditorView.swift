import SwiftUI

/// **The curve ramp module's control** — BRUSH.md §7's four numbered points, §2.24's *"it passes
/// through an input/output curve ramp module"*.
///
/// Every rule it obeys is `ResponseCurveEditing`'s, which is where the arithmetic lives and what the
/// fast tier pins; this file is the `Path`s, the dots and one `DragGesture`. See that type for what
/// is reused from the timeline's graph band and what could not be, and for why the y axis is a
/// constant rather than a fit to the keys.
struct ResponseCurveEditorView: View {
    /// The row's curve. Written through on every change; the caller decides when that reaches the
    /// library (the editor writes on gesture end, exactly as a slider does on lift).
    @Binding var curve: ResponseCurve
    /// What the x axis is a reading *of* — "Pressure", "Tilt Angle". Drawn under the graph, because a
    /// curve with no sensor named is a shape with no meaning.
    let inputName: String
    /// Prefix for this control's accessibility identifiers.
    let idPrefix: String
    var onEditBegan: () -> Void = {}
    var onEditEnded: () -> Void = {}

    private var side: CGFloat { ResponseCurveEditing.side }

    /// Which key the live gesture grabbed (by frame), and whether it has travelled far enough to be a
    /// drag. `CurveEditor`'s pair, and cleared together in `onEnded`.
    @State private var dragFrame: Int?
    @State private var didMove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // The identifier rides this rectangle rather than the `ZStack`: an identifier on a
                // SwiftUI container is inherited by its descendants and beats their own, which
                // CLAUDE.md records and which the brushes menu was bitten by in exactly this shape.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .frame(width: side, height: side)
                    .accessibilityIdentifier("\(idPrefix).graph")
                    .accessibilityValue(encoded)

                grid
                identityLine
                curvePath
                handles
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            // The curve is drawn over its own fixed 0…1 output range, so a value outside it is cut
            // rather than admitted — `TimelineGraphBand`'s decision 3, which is the same decision as
            // "the axis does not move".
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Text("\(inputName) 0 → 1")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
                Spacer(minLength: 0)
                Button("Reset") {
                    onEditBegan()
                    curve = .linear
                    onEditEnded()
                }
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .accessibilityIdentifier("\(idPrefix).reset")
            }
            .frame(width: side)
        }
    }

    /// `frame:value` pairs, so a test can read the curve back without parsing a drawing — the probe
    /// `CurveEditor.encode` and `TimelineKeyMarkers.encode` both carry, in their spelling.
    private var encoded: String {
        curve.isLinear
            ? "linear"
            : curve.curve.keys.map { String(format: "%d:%.3f", $0.frame, $0.value) }.joined(separator: ";")
    }

    // MARK: Drawing

    private var grid: some View {
        Path { path in
            for step in 1..<4 {
                let offset = side * CGFloat(step) / 4
                path.move(to: CGPoint(x: offset, y: 0));  path.addLine(to: CGPoint(x: offset, y: side))
                path.move(to: CGPoint(x: 0, y: offset));  path.addLine(to: CGPoint(x: side, y: offset))
            }
        }
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// y = x, so "how far from doing nothing" reads without remembering what flat looked like — and
    /// so the *identity* an empty curve evaluates to is visible rather than implied.
    private var identityLine: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: ResponseCurveEditing.y(ofValue: 0)))
            path.addLine(to: CGPoint(x: side, y: ResponseCurveEditing.y(ofValue: 1)))
        }
        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var curvePath: some View {
        let points = ResponseCurveEditing.samples(of: curve)
        return Path { path in
            for (index, point) in points.enumerated() {
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(Color.white.opacity(curve.isLinear ? 0.35 : 0.9),
                lineWidth: ResponseCurveEditing.lineWidth)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var handles: some View {
        ZStack {
            ForEach(Array(curve.curve.keys.enumerated()), id: \.element.frame) { index, key in
                let at = ResponseCurveEditing.point(ofKey: key)
                Circle()
                    .fill(dragFrame == key.frame ? Color.blue : Color.white)
                    .frame(width: ResponseCurveEditing.keyRadius * 2,
                           height: ResponseCurveEditing.keyRadius * 2)
                    .position(at)
                    // **Identified by position, not by frame.** A drag changes the frame, so a
                    // frame-keyed identifier would name a *different* element after the gesture and a
                    // before/after comparison of where the dot sits could not be made at all — which
                    // is precisely the assertion TODO (38)'s defect needs.
                    .accessibilityIdentifier("\(idPrefix).key.\(index)")
                    .accessibilityValue(String(format: "%d:%.3f", key.frame, key.value))
            }
        }
        .frame(width: side, height: side)
    }

    // MARK: Gesture

    /// `CurveEditor`'s grammar, which `TimelineGraphBand` took in turn: drag moves the nearest key,
    /// a tap on a key removes it, a tap on empty graph adds one.
    private var dragGesture: some Gesture {
        // `minimumDistance: 0` so a plain tap arrives here at all — a `TapGesture` beside this one
        // would race it for the same touch.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragFrame == nil, !didMove {
                    dragFrame = ResponseCurveEditing.nearestKey(to: value.startLocation, in: curve.curve)
                }
                guard hypot(value.translation.width, value.translation.height) > ResponseCurveEditing.tapSlop,
                      let frame = dragFrame else { return }
                if !didMove {
                    didMove = true
                    onEditBegan()
                }
                let moved = ResponseCurveEditing.moving(frame: frame, to: value.location, in: curve.curve)
                // The key's frame is what identifies it to the next `onChanged`, so it has to travel
                // with the finger — otherwise the second tick of a sideways drag grabs nothing and
                // the key stops after one frame of movement.
                dragFrame = ResponseCurveEditing.nearestKey(to: value.location, in: moved) ?? frame
                curve = ResponseCurve(moved)
            }
            .onEnded { value in
                defer { dragFrame = nil; didMove = false }
                guard TimelineGraphBand.isTap(didMove: didMove, translation: value.translation) else {
                    if didMove { onEditEnded() }
                    return
                }
                onEditBegan()
                if let frame = dragFrame {
                    curve = ResponseCurve(ResponseCurveEditing.removing(frame: frame, from: curve.curve))
                } else {
                    curve = ResponseCurve(ResponseCurveEditing.adding(at: value.location, to: curve.curve))
                }
                onEditEnded()
            }
    }
}
