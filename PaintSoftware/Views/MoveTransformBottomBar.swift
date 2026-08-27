import SwiftUI

/// **The Move menu** — the bottom bar shown whenever anything is floating: a raster Move/Duplicate
/// piece *or* a lassoed vector region. Mirror horizontal/vertical, rotate 45° and 90° either way,
/// Reset, Done, and the Freeform/Uniform/Distort mode picker. Procreate reference: the Transform
/// tool's bottom toolbar.
///
/// **It replaces the Select menu rather than sitting on top of it** (owner, 2026-08-22: *"when
/// moving, there should be an option menu on the bottom instead of still keeping the select menu"*).
/// The two used to dock at the same place and could both be up at once. `DrawingView` now suppresses
/// the Select panel's *presentation* for as long as `isAnyPieceFloating`, and deliberately does not
/// clear `activePanel` — so when the piece bakes, the Select menu comes straight back if Select is
/// still the artist's open panel, and they have not lost their place.
///
/// **No control here is allowed to be pressed and do nothing.** Three can be unavailable, and each
/// says so rather than going quietly grey: Mirror, when the lassoed piece carries a **placed image**
/// (`CanvasManager.mirrorUnavailableReason` — `LayerTransform` has no flip); the **mode picker**, on a
/// piece carrying one for the neighbouring reason that a `LayerTransform` has no second axis scale
/// (`freeformUnavailableReason`); and Reset, when the piece is already sitting exactly where it was
/// picked up.
///
/// **Text used to be refused by both and no longer is** (owner, 2026-08-27: *"I rule text should be
/// able to be transformed"*), which leaves the placed image as the only kind either refusal names —
/// so the two reasons coincide again, on one kind rather than on two.
struct MoveTransformBottomBar: View {
    @ObservedObject var canvasManager: CanvasManager

    private var mirrorReason: String? { canvasManager.mirrorUnavailableReason }
    private var freeformReason: String? { canvasManager.freeformUnavailableReason }

    /// **The picker is live for a lassoed vector piece too, as of stage 3.** It used to be raster-only
    /// with the caption *"A lassoed piece scales uniformly about its centre"*, which was true:
    /// `ObjectTransformDrag`'s corner arm wrote one `scale`, so offering a working-looking Freeform
    /// would have been the "acts like Uniform for now" caption with no caption. It now writes an
    /// `ObjectTransformFrame.aspect` alongside it and `VectorCanvas.mapping(_:throughStretch:)` carries
    /// it into the geometry, so the only float that still cannot stretch is one carrying a placed
    /// image — and that one says so, in the caption, rather than going quietly grey.
    private var modeIsAdjustable: Bool { freeformReason == nil }

    /// One line under the buttons, or none. Ordered by which the artist is most likely to have just
    /// pressed against — and with the two refusals merged where they coincide, so a piece with a
    /// photo in it does not disable the picker with a caption that only mentions Mirror.
    ///
    /// The merged line names the **image alone** as of 2026-08-27. It is not bookkeeping: the two
    /// reasons no longer coincide except on an image, since a text box now mirrors and stretches, and
    /// a caption that still said "or a text box" would be telling the artist their type is stuck at
    /// the moment they can see it move.
    private var caption: String? {
        if mirrorReason != nil, freeformReason != nil {
            return "A placed image can't be mirrored or stretched."
        }
        if let mirrorReason { return mirrorReason }
        if let freeformReason { return freeformReason }
        if !canvasManager.transformMode.isImplemented { return "Coming soon — acts like Uniform for now" }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                iconButton("arrow.left.and.right", enabled: mirrorReason == nil) {
                    canvasManager.mirrorFloating(horizontal: true)
                }
                .accessibilityLabel("Mirror Horizontal")
                .accessibilityIdentifier("moveBar.mirrorHorizontalButton")

                iconButton("arrow.up.and.down", enabled: mirrorReason == nil) {
                    canvasManager.mirrorFloating(horizontal: false)
                }
                .accessibilityLabel("Mirror Vertical")
                .accessibilityIdentifier("moveBar.mirrorVerticalButton")

                divider

                // ±1 eighth of a turn and ±2, left pair then right pair, so the two directions read
                // as two directions rather than as four unrelated icons.
                iconButton("rotate.left") { canvasManager.rotateFloating(eighths: -2) }
                    .accessibilityLabel("Rotate 90° Left")
                    .accessibilityIdentifier("moveBar.rotate90LeftButton")
                iconButton("rotate.left", badge: "45") { canvasManager.rotateFloating(eighths: -1) }
                    .accessibilityLabel("Rotate 45° Left")
                    .accessibilityIdentifier("moveBar.rotate45LeftButton")
                iconButton("rotate.right", badge: "45") { canvasManager.rotateFloating(eighths: 1) }
                    .accessibilityLabel("Rotate 45° Right")
                    .accessibilityIdentifier("moveBar.rotate45RightButton")
                iconButton("rotate.right") { canvasManager.rotateFloating(eighths: 2) }
                    .accessibilityLabel("Rotate 90° Right")
                    .accessibilityIdentifier("moveBar.rotate90RightButton")

                divider

                iconButton("arrow.uturn.backward", enabled: canvasManager.canResetFloating) {
                    canvasManager.resetFloating()
                }
                .accessibilityLabel("Reset")
                .accessibilityIdentifier("moveBar.resetButton")

                divider

                Button("Done") { canvasManager.commitAnyFloatingPiece() }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("moveBar.doneButton")
            }

            Picker("Mode", selection: Binding(
                get: { canvasManager.transformMode },
                set: { canvasManager.setTransformMode($0) }
            )) {
                ForEach(TransformMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .disabled(!modeIsAdjustable)
            .opacity(modeIsAdjustable ? 1 : 0.45)

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.9))
        .cornerRadius(14)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 24)
    }

    /// `enabled: false` uses `.disabled` rather than dropping the button, so the row does not reflow
    /// under the artist's finger the moment a piece with text in it is lifted — and so an XCUITest can
    /// assert the button is *there and off* rather than merely absent.
    private func iconButton(_ system: String, badge: String? = nil, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: system)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.trailing, 1)
                }
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
