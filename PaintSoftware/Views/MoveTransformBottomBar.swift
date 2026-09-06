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
/// **No control here is allowed to be pressed and do nothing.** One can be unavailable, and it says
/// so rather than going quietly grey: Reset, when the piece is already sitting exactly where it was
/// picked up (`CanvasManager.canResetFloating`).
///
/// **Mirror and the mode picker were the other two until LASSO_MOVE.md §3 stage 3c.** Both refused a
/// lassoed piece carrying a **placed image**, whose whole placement was a `LayerTransform` — no flip,
/// and no second axis scale. The image stores its own shape now, so every kind mirrors and stretches,
/// and the two captions are gone rather than left as sentences nothing can raise.
///
/// **"What travels" is not here, and since 2026-09-02 that is the point rather than an omission**
/// (TODO item (23)). Membership — Enclosed / Cut / Touching — is a property of the *selection*, not
/// of this tool, so its picker lives in `SelectPanel` where Recolour and Clear can be read beside it.
/// The bar carried it from TODO item (20) until then, on the argument that the Select panel is
/// suppressed for exactly as long as a float is up; the owner ruled the other way, and the cost is
/// stated where it lands (`CanvasManager.setSelectionMembership`): the rule is chosen before the lift
/// rather than flipped during it.
///
/// **Text stopped being refused on 2026-08-27** (owner: *"I rule text should be able to be
/// transformed"*) and the placed image, the last kind either refusal named, on stage 3c. The picker
/// is live for every float there is.
///
/// **Distort shipped 2026-09-02 (stage 5) and it reaches the raster piece only**, so the caption slot
/// has a second tenant rather than an empty one: `CanvasManager.distortUnavailableReason` refuses
/// Distort on a lassoed *vector* float and says what would unblock it. That is a refusal about one
/// piece, where the caption it replaced — `TransformMode.isImplemented`'s *"Coming soon"* — was a
/// statement about the whole mode.
struct MoveTransformBottomBar: View {
    @ObservedObject var canvasManager: CanvasManager

    /// One line under the picker, or none.
    ///
    /// **Stage 5 shipped Distort and this caption changed subject rather than going away.** It used
    /// to read *"Coming soon — acts like Uniform for now"* off `TransformMode.isImplemented`, which
    /// was true of every float; both are deleted. What is left is a refusal about one *piece* —
    /// Distort on a lassoed vector selection — and `CanvasManager.distortUnavailableReason` is where
    /// the sentence and the measurement behind it live.
    private var caption: String? { canvasManager.distortUnavailableReason }

    /// **Two rows, not four** — TODO item (49), the owner: *"too tall and obstructs your view. Make
    /// all of them wider and flatter."* The mode picker used to be a line of its own under the icons
    /// and the precision help a third line under its toggle; at `BottomDock.preferredWidth` the
    /// picker fits beside the icons and the help beside the switch, which is most of the height
    /// gone. Nothing was removed and no identifier moved.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                iconButton("arrow.left.and.right") {
                    canvasManager.mirrorFloating(horizontal: true)
                }
                .accessibilityLabel("Mirror Horizontal")
                .accessibilityIdentifier("moveBar.mirrorHorizontalButton")

                iconButton("arrow.up.and.down") {
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

                Picker("Mode", selection: Binding(
                    get: { canvasManager.transformMode },
                    set: { canvasManager.setTransformMode($0) }
                )) {
                    ForEach(TransformMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 200)

                divider

                Button("Done") { canvasManager.commitAnyFloatingPiece() }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("moveBar.doneButton")
            }

            precisionRow

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .accessibilityIdentifier("moveBar.modeCaption")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 24)
    }

    /// **TODO item (14) — "Keep Full Precision".** Named for what the artist gets rather than for what
    /// it stores: `CanvasManager.preserveMovePrecision` is the flag, `float32` is the layout, and
    /// neither is a thing anybody drawing has an opinion about. What they *do* have an opinion about
    /// is shrinking a drawing, saving, coming back and finding it grew back rough.
    ///
    /// **Its help line says what it costs**, in the voice `caption` above uses for a control that
    /// cannot act: there is a price, it is paid in file size, and there is a way to stop paying it.
    /// A toggle whose cost is invisible is one an artist leaves on for a year.
    ///
    /// Never disabled. There is no piece it cannot apply to — a fill, a text box and a placed image
    /// simply have no samples to keep, and the strokes beside them in the same lasso still do.
    private var precisionRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Toggle(isOn: $canvasManager.preserveMovePrecision) {
                Text("Keep Full Precision").foregroundColor(.white)
            }
            .tint(.blue)
            .fixedSize()
            .accessibilityIdentifier("moveBar.keepFullPrecisionToggle")

            Text("Strokes you move are stored exactly, so shrinking them now and growing them back "
                 + "after a save loses nothing. They take about 1.7× the file space until you run "
                 + "Bake Precise Strokes in Actions.")
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `enabled: false` uses `.disabled` rather than dropping the button, so the row does not reflow
    /// under the artist's finger — and so an XCUITest can assert the button is *there and off* rather
    /// than merely absent. Reset is the only caller that passes it today.
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
