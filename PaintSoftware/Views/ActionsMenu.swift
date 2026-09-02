import SwiftUI
import PhotosUI

struct ActionsMenu: View {
    @ObservedObject var canvasManager: CanvasManager
    /// **The one panel that can open another panel.** Every other row here is a direct action, a
    /// `PhotosPicker` or an inert stub, so this view needed nothing but the manager until "Add Text"
    /// arrived — text is a *mode*, and entering it means swapping this menu for the text tool's own
    /// settings panel. `ADD_TEXT.md` §1 calls threading this binding through the change that "lands
    /// first and alone", because `ActionsMenu` is shared by every panel in the app and a change here
    /// wants to be bisectable on its own.
    @Binding var activePanel: ActivePanel
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var notice: String?
    /// Live slider position for the padding control. The (buffer-resizing) commit happens only on
    /// release, in `onEditingChanged`, so dragging the thumb doesn't re-render every layer per tick;
    /// this just tracks the thumb + the px readout meanwhile.
    @State private var paddingDraft: Double = 0
    /// Whether the "Resize Canvas" sheet is up. A sheet rather than an inline section like the padding
    /// slider, because this one has two typed fields and an irreversible Apply: the padding slider can
    /// be dragged back, and a resize that cropped artwork cannot (`history.removeAll()`, until
    /// CANVAS_RESIZE.md stage 3 gives it an undo step).
    @State private var showingResize = false
    /// Whether the "Export" sheet is up. A sheet for `showingResize`'s reason and one more: §3.9's
    /// visible progress needs a place to be visible.
    @State private var showingExport = false

    var body: some View {
        // Scrolled, not just stacked: the panel that hosts this is capped at a fixed height, and a
        // plain VStack taller than that cap doesn't clip — it overflows symmetrically, pushing the
        // title off the top and leaving rows drawn outside the panel's own rounded bounds.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        .sheet(isPresented: $showingResize) {
            CanvasResizeSheet(canvasManager: canvasManager)
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(canvasManager: canvasManager)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Actions")
                .font(.headline)
                .foregroundColor(.white)
                .padding([.horizontal, .top])
                .padding(.bottom, 4)

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                row(icon: "photo.on.rectangle", title: canvasManager.activeLayerIsVector ? "Insert Photo (onto vector layer)" : "Insert Photo")
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await insertPhoto(newItem) }
            }

            addTextRow

            Button {
                canvasManager.flipCanvas(horizontal: true)
            } label: {
                row(icon: "arrow.left.and.right", title: "Flip Horizontal")
            }

            Button {
                canvasManager.flipCanvas(horizontal: false)
            } label: {
                row(icon: "arrow.up.and.down", title: "Flip Vertical")
            }

            resizeCanvasRow

            paddingControl

            bakePrecisionRow

            exportRow

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            pencilOnlyToggle

            renderResolutionControl

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            // Debug capture: record what the artist actually did, hand us the file. Default OFF and
            // inert while off — see `ActionRecorder.isCapturing`.
            ActionRecorderSection(canvasManager: canvasManager)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

            Button { notice = "Cut isn't available yet" } label: {
                row(icon: "scissors", title: "Cut")
            }
            Button { notice = "Copy isn't available yet" } label: {
                row(icon: "doc.on.doc", title: "Copy")
            }
            Button { notice = "Paste isn't available yet" } label: {
                row(icon: "doc.on.clipboard", title: "Paste")
            }
            Button { notice = "Drawing guides aren't available yet" } label: {
                row(icon: "grid", title: "Drawing Guide")
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Enters the text tool and swaps this menu for the text tool's settings panel — the only way
    /// into `Tool.text`, since the top toolbar has no text icon.
    ///
    /// **Disabled rather than hidden where text cannot go, with the reason underneath it.** The row
    /// is the feature's only signpost: hidden, "can this app do text" has no answer on the layer the
    /// artist happens to be standing on, and they conclude it cannot.
    ///
    /// As of `ADD_TEXT.md` stage 3 the only kind that still refuses is `.value`, and that one is not
    /// a "yet": a layer holding no pixels has nothing for text to mean. Raster bakes the glyphs;
    /// vector keeps the object editable. The row was disabled on vector through stage 1 precisely so
    /// that nothing had to be un-shipped when this arrived.
    ///
    /// `Tool.textUnavailableReason` is where the answer lives, keyed off the layer's *kind*: the
    /// caption and the disabled state read one value, so they cannot disagree about whether the row
    /// works, and a fourth `LayerKind` cannot quietly inherit "text is fine here".
    private var addTextRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // No `commitAllInteractiveState()`, and its absence is the point — see
                // `CanvasManager.enterTextMode`, and `Binding.toggleSettingsPanel` for the rule it
                // is following. Both statements are that rule: enter the mode, open its panel, bake
                // nothing on the way.
                canvasManager.enterTextMode()
                $activePanel.toggleSettingsPanel(.text)
            } label: {
                row(icon: "textformat", title: "Add Text", enabled: textUnavailableReason == nil)
            }
            .disabled(textUnavailableReason != nil)
            .accessibilityIdentifier("actions.addTextRow")

            if let textUnavailableReason {
                Text(textUnavailableReason)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.leading, 24)   // clears the row's icon column, so it reads as the row's own note
                    .padding(.bottom, 6)
            }
        }
    }

    /// **TODO item (14) — the other half of the Move bar's "Keep Full Precision".** Snaps every stroke
    /// in the document that is stored exactly back onto the quarter-pixel grid, recovering the file
    /// size the option costs. Above the divider, because everything above it acts on the drawing.
    ///
    /// **The count is in the title rather than in the caption**, so "is there anything to bake" is
    /// answered by the row itself and not by reading a sentence under it — and the row greys out at
    /// zero rather than disappearing, for the reason "Add Text" states: a hidden row is a feature with
    /// no signpost, and an artist who has never turned the toggle on would never learn what undoes it.
    private var bakePrecisionRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                canvasManager.bakePreciseStrokes()
            } label: {
                row(icon: "square.grid.3x3",
                    title: "Bake Precise Strokes (\(canvasManager.preciseStrokeCount))",
                    enabled: canvasManager.preciseStrokeCount > 0)
            }
            .disabled(canvasManager.preciseStrokeCount == 0)
            .accessibilityIdentifier("actions.bakePrecisionRow")

            Text(canvasManager.preciseStrokeCount == 0
                 ? "Nothing to bake — no stroke here is stored at full precision."
                 : "Snaps them back to the normal storage grid, which is smaller on disk. "
                   + "Shrinking and regrowing them after a save will lose a little accuracy again.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.leading, 24)   // clears the row's icon column, as "Add Text" does
                .padding(.bottom, 6)
        }
    }

    /// TODO item (29) — RENDER.md §3.9. The animation as video, or one frame as an image.
    ///
    /// **The last row above the divider, because it is the last thing you do to a document.**
    /// Everything above the divider acts on the drawing and everything below it is a preference;
    /// an export reads the drawing and produces something from it, which puts it on the acting side
    /// — and at the end of it, where "I am finished" belongs.
    ///
    /// A sheet rather than two rows, for `CanvasResizeSheet`'s reason plus one of its own: the wait
    /// needs somewhere to live. §3.9 asks for visible progress, and an export of a document the
    /// baker has not caught up with is a real wait that has to be cancellable and has to end
    /// somewhere the file can be picked up from.
    private var exportRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingExport = true
            } label: {
                row(icon: "square.and.arrow.up", title: "Export",
                    enabled: canvasManager.canvasSize != nil)
            }
            .disabled(canvasManager.canvasSize == nil)
            .accessibilityIdentifier("actions.exportRow")

            Text("Saves the animation as a video, or the frame you are on as an image, at the "
                 + "Render Resolution below.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.leading, 24)   // clears the row's icon column, as "Add Text" does
                .padding(.bottom, 6)
        }
    }

    /// Nil when "Add Text" is usable on the layer the artist is standing on. Recomputed per render
    /// off `activeLayerKind`, so selecting another layer enables or disables the row with no state
    /// of its own to keep in step.
    private var textUnavailableReason: String? {
        Tool.textUnavailableReason(onLayerOfKind: canvasManager.activeLayerKind)
    }

    /// Whether a finger may draw, or only an Apple Pencil. Phrased as "fingers can paint" — the
    /// state the user is actually choosing between — rather than as the `pencilOnlyDrawing` flag it
    /// sets, which is inverted and reads backwards on a toggle. Persists across launches.
    private var pencilOnlyToggle: some View {
        Toggle(isOn: Binding(get: { !canvasManager.pencilOnlyDrawing },
                             set: { canvasManager.pencilOnlyDrawing = !$0 })) {
            HStack {
                Image(systemName: "hand.draw").frame(width: 24)
                Text("Fingers Can Paint")
            }
            .foregroundColor(.white)
        }
        .tint(.blue)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityIdentifier("actions.fingersCanPaintToggle")
    }

    /// How large the live canvas's composites are rendered (see `RenderResolution`). Persists across
    /// launches, like the toggle above it and unlike `Compositor.backend`, which is a development
    /// seam and deliberately not a user choice.
    ///
    /// **Sits directly under "Fingers Can Paint" rather than in its own section**, because the two are
    /// the same kind of thing: a preference about this iPad and this artist's hands, rather than a
    /// command that does something to the drawing. Everything above the divider acts on the document;
    /// everything below it is a setting.
    ///
    /// A segmented picker, not a slider: there are three values and the artist should be able to see
    /// all of them and land on one exactly.
    ///
    /// **The subtitle used to say *"Your artwork, exports and thumbnails are always saved at full
    /// size"*, and RENDER §2.8 makes the middle third of that false.** The knob is now the export
    /// resolution — it is what the background baker mints at (stage 4d), so it is what the frame
    /// files hold, and export reads those files and re-renders nothing (§2.1). Leaving the old
    /// sentence there would have been the worst kind of stale copy: reassurance, about the one thing
    /// the change altered, on the control that alters it. What survives is the true half — the
    /// document's own layers and strokes are stored at full size and this setting cannot touch them
    /// — plus the fact the artist now needs, which the export sheet's caption repeats at the moment
    /// they are about to hand a file to somebody.
    private var renderResolutionControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.resize").frame(width: 24)
                Text("Render Resolution")
                Spacer()
            }
            .foregroundColor(.white)

            Picker("Render Resolution", selection: $canvasManager.renderResolution) {
                ForEach(RenderResolution.allCases) { resolution in
                    Text(resolution.title).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("actions.renderResolutionPicker")

            Text("Lower settings redraw layered artwork faster and look softer while you work. "
                 + "Playback and anything you export come out at this size too; your layers "
                 + "and strokes themselves are always kept at full size.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// TODO item (9) — "Resize Canvas". CANVAS_RESIZE.md stages 1 and 2: crop and expand at an
    /// arbitrary rectangle instead of the padding slider's symmetric margin, or scale the artwork
    /// with the canvas.
    ///
    /// **Directly above "Canvas Padding", because the two move the same document dimension from
    /// opposite ends** — this one sets the artwork rect, that one sets the margin around it, and the
    /// numbers they show have to be read together. The caption says which of the two the fields mean,
    /// since that is exactly the confusion §6 question 3 was raised about.
    ///
    /// The current size is in the row title rather than only inside the sheet, following
    /// "Bake Precise Strokes": the question "how big is this canvas" is answered by the menu without
    /// opening anything.
    private var resizeCanvasRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingResize = true
            } label: {
                row(icon: "arrow.up.left.and.arrow.down.right",
                    title: canvasManager.artworkSize.map {
                        "Resize Canvas (\(Int($0.width.rounded())) × \(Int($0.height.rounded())))"
                    } ?? "Resize Canvas",
                    enabled: canvasManager.canvasSize != nil)
            }
            .disabled(canvasManager.canvasSize == nil)
            .accessibilityIdentifier("actions.resizeCanvasRow")

            Text("Crops or expands the artwork area around what you have drawn, or scales the "
                 + "drawing with it. This cannot be undone.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.leading, 24)   // clears the row's icon column, as "Add Text" does
                .padding(.bottom, 6)
        }
    }

    /// Adjustable light-grey drawable margin around the canvas (see `CanvasManager.setCanvasPadding`).
    /// The px readout follows the thumb live; the actual resize commits on release.
    private var paddingControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.dashed").frame(width: 24)
                Text("Canvas Padding")
                Spacer()
                Text("\(Int(paddingDraft.rounded())) px").foregroundColor(.gray)
            }
            .foregroundColor(.white)

            Slider(
                value: $paddingDraft,
                in: Double(canvasManager.canvasPaddingRange.lowerBound)...Double(canvasManager.canvasPaddingRange.upperBound),
                onEditingChanged: { editing in
                    if !editing { canvasManager.setCanvasPadding(CGFloat(paddingDraft)) }
                }
            )
            .accessibilityIdentifier("actions.paddingSlider")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear { paddingDraft = Double(canvasManager.canvasPadding) }
    }

    /// `enabled` greys the row itself rather than leaning on `.disabled`'s own dimming, which this
    /// row never gets: the explicit `.foregroundColor(.white)` below wins over it, so a disabled row
    /// left to SwiftUI would look exactly like a working one and simply ignore taps.
    private func row(icon: String, title: String, enabled: Bool = true) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            Text(title)
            Spacer()
        }
        .foregroundColor(enabled ? .white : Color.white.opacity(0.35))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func insertPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        await MainActor.run {
            canvasManager.insertImage(image)
        }
    }
}

/// "Resize Canvas" — CANVAS_RESIZE.md stages 1 and 2's dialog: crop/expand, or scale the artwork with
/// the canvas and letterbox it when the shape changes.
///
/// **The two fields are the artwork rect, not the buffer** — §5 rule 9, owner-confirmed 2026-08-28.
/// `canvasPadding` is preserved literally and never scales, so the buffer this produces is
/// `typed + 2 × canvasPadding`; when there is padding the sheet says so under the fields rather than
/// letting the artist discover it by watching `canvasSize` disagree with what they typed.
///
/// The validation is `CanvasSizePickerView`'s, reached through the same single named home
/// (`CanvasManager.maxCanvasExtent`), **inset by the padding**: that view creates documents with no
/// margin, so it can use the bound directly and this cannot — 16383 of artwork plus 1024 a side is a
/// buffer no canvas may have. `CanvasManager.resizableArtworkExtentRange` is where that lives, so the
/// clamp the button enforces and the clamp the model applies are one value.
///
/// ## Three sentences the sheet owes, and each is conditional on something the artist can see
///
///  * **Fit or Fill**, offered only when the new shape is a different aspect from the old one — at
///    the same aspect `min` and `max` are the same number and a picker between them would be a
///    control that does nothing. Fit is the default (§5 rule 2).
///  * **The floor sentence** (§2), when this particular document has a stroke the scale would carry
///    across `BrushStamper.stampSpacing`'s 1 pt floor. Surveyed once at `onAppear` and answered by
///    binary search after that, so a 1000-cel document is not walked per keystroke.
///  * **The compositor warning** (§5 rule 14), when the new buffer would put this document's layer
///    stack past `MetalCompositor`'s size-based admission gate. It warns and lets the artist proceed
///    — never refuses — and it names what actually happens rather than "falls back to CPU", which is
///    not what the artist experiences on the canvas.
struct CanvasResizeSheet: View {

    @ObservedObject var canvasManager: CanvasManager
    @Environment(\.dismiss) private var dismiss

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var scaleContent = false
    @State private var fillsNewShape = false
    /// Both taken once, at `onAppear` — see the type doc comments for why they are not recomputed.
    @State private var floorSurvey = SpacingFloorSurvey(thresholds: [])
    @FocusState private var focusedField: Field?

    private enum Field { case width, height }

    private var range: ClosedRange<CGFloat> { canvasManager.resizableArtworkExtentRange }
    private var minDimension: Int { Int(range.lowerBound) }
    private var maxDimension: Int { Int(range.upperBound) }

    private var width: Int? { Int(widthText) }
    private var height: Int? { Int(heightText) }

    private var isValid: Bool {
        guard let width, let height else { return false }
        return (minDimension...maxDimension).contains(width) && (minDimension...maxDimension).contains(height)
    }

    private var mode: CanvasResizeMode {
        guard scaleContent else { return .cropExpand }
        return fillsNewShape ? .scaleToFill : .scaleToFit
    }

    /// The map the Resize button would build, or nil while the fields do not parse. Built from the
    /// **model's own type** rather than from a second copy of the arithmetic, so the factor the sheet
    /// describes and the factor the document gets cannot drift.
    private var previewMap: CanvasResizeMap? {
        guard let width, let height, isValid, let current = canvasManager.canvasSize else { return nil }
        let padding = canvasManager.canvasPadding
        let newBuffer = CGSize(width: CGFloat(width) + 2 * padding, height: CGFloat(height) + 2 * padding)
        return CanvasResizeMap(from: current, to: newBuffer, padding: padding, mode: mode)
    }

    /// Whether Fit and Fill would differ — i.e. whether the artist is being asked a real question.
    private var aspectChanges: Bool {
        guard let width, let height, isValid, let artwork = canvasManager.artworkSize,
              artwork.width > 0, artwork.height > 0 else { return false }
        return abs(CGFloat(width) / artwork.width - CGFloat(height) / artwork.height) > 1e-9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Resize Canvas")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    dimensionField("Width", text: $widthText, field: .width)
                    Text("x").foregroundColor(.secondary)
                    dimensionField("Height", text: $heightText, field: .height)
                }

                if !isValid {
                    Text("Enter values between \(minDimension) and \(maxDimension)")
                        .font(.caption).foregroundColor(.red)
                        .accessibilityIdentifier("resizeCanvas.validationMessage")
                } else if canvasManager.canvasPadding > 0 {
                    Text("Plus \(Int(canvasManager.canvasPadding.rounded())) px of canvas padding on every side.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Scale artwork", isOn: $scaleContent)
                    .accessibilityIdentifier("resizeCanvas.scaleToggle")

                if scaleContent && aspectChanges {
                    Picker("", selection: $fillsNewShape) {
                        Text("Fit").tag(false)
                        Text("Fill").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("resizeCanvas.fitFillPicker")
                }

                Text(explanation)
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("resizeCanvas.explanation")

                if scaleContent, let map = previewMap, floorSurvey.isCrossed(byScaling: map.scale) {
                    Text("Brush textures will re-stamp at the new size, so some strokes will be "
                         + "grained or shaded slightly differently.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("resizeCanvas.brushFloorNotice")
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("resizeCanvas.cancelButton")
                Spacer()
                Button("Resize") {
                    guard let width, let height, isValid else { return }
                    // The announcing entry point, not `resizeCanvas(to:mode:)` itself: on a document
                    // large enough for the walk to be felt it puts the busy overlay up and gets it a
                    // frame before the block starts (§5 rule 15), and on one small enough that a
                    // modal would flicker it runs the resize straight through. It also raises the
                    // refusal (rule 11) and the resample notice (rule 10).
                    canvasManager.resizeCanvasAnnouncingProgress(to: CGSize(width: width, height: height),
                                                                 mode: mode)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .accessibilityIdentifier("resizeCanvas.applyButton")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Prefilled from the live artwork rect, so the common edit is changing one number. `onAppear`
        // rather than an initialiser default: a sheet's body can be built before it is presented, and
        // the size may have moved since.
        .onAppear {
            let current = canvasManager.artworkSize ?? CGSize(width: 2048, height: 2048)
            widthText = String(Int(current.width.rounded()))
            heightText = String(Int(current.height.rounded()))
            focusedField = .width
            floorSurvey = canvasManager.spacingFloorSurvey
        }
    }

    /// What the resize will do to the drawing, in the artist's terms. One sentence per mode, and the
    /// undo clause every mode shares.
    ///
    /// **The undo clause changed with stage 3 and says two things now**, because §5 rule 10 gives
    /// exactly two: the resize itself takes one press to undo, and everything below it on the stack
    /// is gone — every entry there holds pixel patches at the old canvas dimensions, so restoring one
    /// after a resize would put them at the wrong size in the wrong place. Depth 1 afterwards is
    /// strictly better than the 0 this operation used to leave, which is the owner's own reason for
    /// choosing it (§6 Q2). What it does *not* promise is that the pixels come back bit-exact; that
    /// is a property of the particular resize rather than of the dialog, so it is said by
    /// `CanvasNotice.resizeResampled` at the moment it is true.
    private var explanation: String {
        let undo = " The resize itself can be undone; anything you did before it can't."
        guard scaleContent else {
            return "Your artwork keeps its size and stays centred. Anything outside the new edges "
                 + "is cropped away." + undo
        }
        if fillsNewShape {
            return "Your artwork is scaled to cover the new size and stays centred. Whatever hangs "
                 + "over the edges is cropped from painted layers; drawn strokes and shapes keep "
                 + "their whole geometry." + undo
        }
        return "Your artwork is scaled to fit inside the new size and stays centred. If the shape "
             + "changes, the leftover is empty canvas — nothing is stretched and no bars are "
             + "painted." + undo
    }

    private func dimensionField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: field)
            .accessibilityIdentifier(field == .width ? "resizeCanvas.widthField" : "resizeCanvas.heightField")
    }
}
