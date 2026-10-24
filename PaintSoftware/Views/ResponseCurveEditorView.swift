import SwiftUI

/// **The curve ramp module's control** — BRUSH.md §7's four numbered points, §2.24's *"it passes
/// through an input/output curve ramp module"*.
///
/// Every rule it obeys is `ResponseCurveEditing`'s, which is where the arithmetic lives and what the
/// fast tier pins; this file is the `Path`s, the dots and one `DragGesture`. See that type for what
/// is reused from the timeline's graph band and what could not be, and for why the y axis is a
/// constant rather than a fit to the keys.
struct ResponseCurveEditorView: View {
    /// The row's curve. Written straight through to the editor's draft on every change — since
    /// §2.31 there is no "when does this reach the library" for a control to answer, because Done is
    /// the only thing that does.
    @Binding var curve: ResponseCurve
    /// What the x axis is a reading *of* — "Pressure", "Tilt Angle". Drawn under the graph, because a
    /// curve with no sensor named is a shape with no meaning.
    let inputName: String
    /// Prefix for this control's accessibility identifiers.
    let idPrefix: String

    /// Which key the live gesture grabbed (by frame), and whether it has travelled far enough to be a
    /// drag. `CurveEditor`'s pair, and cleared together in `onEnded`.
    @State private var dragFrame: Int?
    @State private var didMove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let side = min(max(geometry.size.width, 0), ResponseCurveEditing.side)
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

                    grid(side: side)
                    identityLine(side: side)
                    curvePath(side: side)
                    handles(side: side)
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(dragGesture(side: side))
                // The curve is drawn over its own fixed 0…1 output range, so a value outside it is cut
                // rather than admitted — `TimelineGraphBand`'s decision 3, which is the same decision as
                // "the axis does not move".
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            // Supply a square height before entering the enclosing vertical scroll view.
            .aspectRatio(1, contentMode: .fit)

            HStack(spacing: 8) {
                Text("\(inputName) 0 → 1")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
                Spacer(minLength: 0)
                Button("Reset") {
                    curve = .linear
                }
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .accessibilityIdentifier("\(idPrefix).reset")
            }
        }
        .frame(maxWidth: ResponseCurveEditing.side, alignment: .leading)
    }

    /// `frame:value` pairs, so a test can read the curve back without parsing a drawing — the probe
    /// `CurveEditor.encode` and `TimelineKeyMarkers.encode` both carry, in their spelling.
    private var encoded: String {
        curve.isLinear
            ? "linear"
            : curve.curve.keys.map { String(format: "%d:%.3f", $0.frame, $0.value) }.joined(separator: ";")
    }

    // MARK: Drawing

    private func grid(side: CGFloat) -> some View {
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
    private func identityLine(side: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: ResponseCurveEditing.y(ofValue: 0, side: side)))
            path.addLine(to: CGPoint(x: side, y: ResponseCurveEditing.y(ofValue: 1, side: side)))
        }
        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private func curvePath(side: CGFloat) -> some View {
        let points = ResponseCurveEditing.samples(of: curve, side: side)
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

    private func handles(side: CGFloat) -> some View {
        ZStack {
            ForEach(Array(curve.curve.keys.enumerated()), id: \.element.frame) { index, key in
                let at = ResponseCurveEditing.point(ofKey: key, side: side)
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
    private func dragGesture(side: CGFloat) -> some Gesture {
        // `minimumDistance: 0` so a plain tap arrives here at all — a `TapGesture` beside this one
        // would race it for the same touch.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragFrame == nil, !didMove {
                    dragFrame = ResponseCurveEditing.nearestKey(to: value.startLocation, in: curve.curve,
                                                               side: side)
                }
                guard hypot(value.translation.width, value.translation.height) > ResponseCurveEditing.tapSlop,
                      let frame = dragFrame else { return }
                didMove = true
                guard let moved = ResponseCurveEditing.moving(frame: frame, to: value.location,
                                                              in: curve.curve, side: side) else { return }
                dragFrame = moved.frame
                curve = ResponseCurve(moved.curve)
            }
            .onEnded { value in
                defer { dragFrame = nil; didMove = false }
                guard TimelineGraphBand.isTap(didMove: didMove, translation: value.translation) else {
                    return
                }
                if let frame = dragFrame {
                    curve = ResponseCurve(ResponseCurveEditing.removing(frame: frame, from: curve.curve))
                } else {
                    curve = ResponseCurve(ResponseCurveEditing.adding(at: value.location, to: curve.curve,
                                                                     side: side))
                }
            }
    }
}
