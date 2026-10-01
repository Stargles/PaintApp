import CoreText
import SwiftUI

/// The text tool's settings panel — `ADD_TEXT.md` stage 1, in `StrokeSettingsPanel`'s shape inside
/// the scrolling card the other three bottom-docked panels use (`BottomDock`, which owns its width,
/// its chrome and its height ceiling).
///
/// **Opening it bakes nothing.** The way in is `AddMenu`'s "Add Text" row, which calls
/// `enterTextMode()` and `$activePanel.toggleSettingsPanel(.text)` — and that binding method
/// deliberately omits `commitAllInteractiveState()`. The stake is spelled out at
/// `CanvasManager.enterTextMode`: from this stage on there is a live text session behind this panel,
/// and committing on the way in bakes the very text the artist opened the panel to restyle.
///
/// Every control writes `canvasManager.textRecipe` and then calls `textRecipeDidChange()`, which
/// re-resolves the font and regrows a pristine box. Routing every one of them through that single
/// call is what keeps "the box grew because the point size did" from being something each slider has
/// to remember.
///
/// **No favourites strip.** `ADD_TEXT.md` §5 item 5 leaves *which faces* belong in one open, and the
/// owner has not answered; the honest version is all families grouped, with the question still open,
/// rather than an invented shortlist that becomes the answer by default.
struct TextSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    /// Prefix for every control's accessibility identifier — `StrokeSettingsSpec.idPrefix`'s job,
    /// stated here because this panel drives one fixed set of properties and so needs no spec.
    private static let idPrefix = "textPanel"

    /// The label column of a one-line slider row — the label and its live readout sit beside the
    /// slider rather than above it (TODO item (49)). Wide enough for "Paragraph Spacing: 000",
    /// which is the longest of the five.
    private static let labelWidth: CGFloat = 190

    /// Whether the font list is up. View state: the list is a presentation, and its own lifetime is
    /// the router's (`CanvasPresentation.textFont`).
    @State private var showingFontPicker = false

    private var typography: Typography { canvasManager.textRecipe.typography }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Text")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                statusRow
                fontRow
                faceRow
                colorRow

                sliderRow(title: "Size", valueText: "\(Int(typography.pointSize))",
                          value: binding(\.pointSize), range: Typography.pointSizeRange,
                          idSuffix: "sizeSlider")
                sliderRow(title: "Tracking", valueText: String(format: "%.1f", typography.tracking),
                          value: binding(\.tracking), range: Typography.trackingRange,
                          idSuffix: "trackingSlider")
                sliderRow(title: "Line Height", valueText: String(format: "%.2f×", typography.lineHeightMultiple),
                          value: binding(\.lineHeightMultiple), range: Typography.lineHeightRange,
                          idSuffix: "lineHeightSlider")
                sliderRow(title: "Line Spacing", valueText: String(format: "%.0f", typography.lineSpacing),
                          value: binding(\.lineSpacing), range: Typography.lineSpacingRange,
                          idSuffix: "lineSpacingSlider")
                sliderRow(title: "Paragraph Spacing", valueText: String(format: "%.0f", typography.paragraphSpacing),
                          value: binding(\.paragraphSpacing), range: Typography.paragraphSpacingRange,
                          idSuffix: "paragraphSpacingSlider")

                alignmentPicker
                cornerModePicker

                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // **No card chrome and no width here** — `DrawingView` wears both for all four docked
        // panels (`BottomDock`, TODO item (49)). This used to carry its own `Color.black.opacity(0.9)`
        // under the one the call site painted over it.
        .accessibilityIdentifier("panel.textSettings")
    }

    // MARK: - Status

    /// What the panel is currently acting on, and — when it applies — why the font on screen is not
    /// the font that was asked for.
    ///
    /// **The substitution notice is half of `ADD_TEXT.md` §1's font contract.** `FontLibrary.resolve`
    /// reports whether it substituted precisely so it can be said out loud here; a silently
    /// substituted face is the failure mode `BrushTip.stamp(.imported)` already has.
    @ViewBuilder
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !canvasManager.textGestureActive {
                Text("Tap the canvas to place text. These settings apply to the next box you place.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(Self.idPrefix).placementHint")
            }
            if let substitution = canvasManager.textFontSubstitution {
                Label(substitution.message(for: canvasManager.textRecipe.font),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(Self.idPrefix).substitutionNotice")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Font

    /// The family picker: a list of every installed family, grouped System / Serif / Sans / Mono /
    /// Display — plus a section per installed pack once Stage 6 exists, for free, because the
    /// sections come from `FontLibrary.groups()` rather than from a list written here — **each name
    /// drawn in its own face**, with a checkmark on the current one.
    ///
    /// TODO (115), the owner: *"When adding text and selecting the font, I currently have no idea
    /// what the fonts look like. Make the fonts font in the selector menu the actual font."* It was a
    /// native `Menu` (`blendModeRow`'s idiom) until then, and a SwiftUI `Menu`'s rows are drawn by
    /// UIKit, which discards a custom `.font` — so the list is the app's own presentation instead
    /// (`CanvasPresentation.textFont`, an `AnchoredMenu`), which draws real SwiftUI rows.
    private var fontRow: some View {
        Button {
            showingFontPicker.toggle()
        } label: {
            menuLabel(title: "Font", value: canvasManager.textRecipe.font.familyName)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(Self.idPrefix).fontButton")
        .accessibilityValue(canvasManager.textRecipe.font.familyName)
        .canvasPresentation(.textFont, isPresented: $showingFontPicker, canvasManager: canvasManager) {
            FontFamilyList(current: canvasManager.textRecipe.font.familyName) { family, packID in
                selectFamily(family, packID: packID)
                showingFontPicker = false
            }
            .frame(width: Self.fontListSize.width, height: Self.fontListSize.height)
        }
    }

    /// Tall enough for about ten rows, which is what makes the list a thing to scroll through and not
    /// a thing to read at a glance; narrow enough that the longest family name still fits at 20 pt.
    private static let fontListSize = CGSize(width: 320, height: 440)

    /// The face within the family — Regular / Bold / Italic and whatever else the family ships.
    ///
    /// A second menu rather than bold and italic toggles, because a family's faces are a *list*, not
    /// two independent bits: "Helvetica Neue Thin" and "Avenir Black" have no bold checkbox that
    /// produces them, and a toggle pair would have to invent a mapping onto whichever faces happen
    /// to exist. Hidden for a family with only one face, which is most display faces.
    @ViewBuilder
    private var faceRow: some View {
        let font = canvasManager.textRecipe.font
        let faces = FontLibrary.shared.faces(inFamily: font.familyName, packID: font.packID)
        if faces.count > 1 {
            Menu {
                ForEach(faces) { face in
                    Button {
                        canvasManager.textRecipe.font = face.descriptor
                        canvasManager.textRecipeDidChange()
                    } label: {
                        if face.postScriptName == font.faceName {
                            Label(face.displayName, systemImage: "checkmark")
                        } else {
                            Text(face.displayName)
                        }
                    }
                    .accessibilityIdentifier("textPanel.face.\(face.postScriptName)")
                }
            } label: {
                menuLabel(title: "Style", value: currentFaceDisplayName(faces))
            }
            .accessibilityIdentifier("\(Self.idPrefix).faceButton")
            .accessibilityValue(currentFaceDisplayName(faces))
        }
    }

    private func currentFaceDisplayName(_ faces: [FontFace]) -> String {
        let font = canvasManager.textRecipe.font
        return faces.first { $0.postScriptName == font.faceName }?.displayName ?? "Regular"
    }

    /// Picking a family keeps the traits the artist already chose and finds the nearest face in the
    /// new family — the same walk `FontLibrary.resolve` performs, applied at the moment of choosing
    /// rather than at the moment of drawing. Switching Helvetica Bold to Georgia gives Georgia Bold,
    /// not Georgia Regular.
    private func selectFamily(_ family: String, packID: String?) {
        let current = canvasManager.textRecipe.font
        if let provider = FontLibrary.shared.provider(withID: packID),
           let face = provider.face(inFamily: family, bold: current.isBold, italic: current.isItalic) {
            canvasManager.textRecipe.font = face.descriptor
        } else {
            canvasManager.textRecipe.font = FontDescriptor(familyName: family, faceName: nil,
                                                           packID: packID, isBold: current.isBold,
                                                           isItalic: current.isItalic)
        }
        canvasManager.textRecipeDidChange()
    }

    // MARK: - Colour

    /// The recipe's colour, editable without leaving the panel.
    ///
    /// The top toolbar's swatch edits the same value while a session is live
    /// (`CanvasManager.activeEditColor`) — two ways to one value, which is the arrangement the brush
    /// size slider already has between this kind of panel and the toolbar.
    private var colorRow: some View {
        ColorPicker(selection: $canvasManager.activeEditColor, supportsOpacity: false) {
            Text("Colour").foregroundColor(.white)
        }
        .padding(.horizontal)
        .accessibilityIdentifier("\(Self.idPrefix).colorSwatch")
    }

    // MARK: - Alignment

    /// A segmented `Picker` — `EraserSettingsPanel.vectorModePicker`'s control, and for its reason:
    /// a handful of short, mutually exclusive options with a current value.
    private var alignmentPicker: some View {
        VStack(alignment: .leading) {
            Text("Alignment").foregroundColor(.white)
            Picker("Alignment", selection: alignmentBinding) {
                ForEach(Typography.Alignment.allCases) { alignment in
                    Text(alignment.displayName).tag(alignment)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(Self.idPrefix).alignmentPicker")
        }
        .padding(.horizontal)
    }

    // MARK: - Corners

    /// What the four corner grips do — `ADD_TEXT.md` §3 stage 5, "four independent corner handles".
    ///
    /// **A mode rather than a modifier key**, which an iPad does not reliably have and which the
    /// owner did not ask for: they framed the Move tool's version of this as a mode ("each of the 4
    /// points can be moved independently"), and stage 5 is the solver both will share. It is also
    /// additive — stage 4 built corner-drag-as-scale and pinned a dozen identities on it, and none of
    /// them change.
    ///
    /// Not bound to `textRecipe`, so — unlike every other control on this panel — it does **not** go
    /// through `textRecipeDidChange()`. Nothing about the type changed, so nothing needs re-resolving
    /// and a pristine box must not regrow because the artist changed their mind about a gesture.
    private var cornerModePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Corners").foregroundColor(.white)
            Picker("Corners", selection: $canvasManager.textCornerMode) {
                ForEach(TextCornerMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(Self.idPrefix).cornerModePicker")
            Text(canvasManager.textCornerMode == .distort
                 ? "Drag a corner on its own to put the text into perspective. Tap into the text to type and it flattens while you do."
                 : "Drag a corner to scale the box about the opposite one.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(Self.idPrefix).cornerModeHint")
        }
        .padding(.horizontal)
    }

    private var alignmentBinding: Binding<Typography.Alignment> {
        Binding(
            get: { canvasManager.textRecipe.typography.alignment },
            set: {
                canvasManager.textRecipe.typography.alignment = $0
                canvasManager.textRecipeDidChange()
            }
        )
    }

    // MARK: - Rows

    /// `StrokeSettingsPanel.sliderRow`, copied rather than shared: that one is `private` to a
    /// generic type parameterised over a `StrokeSettingsSpec`, which is a brush concept this panel
    /// has no version of. Lifting it into a third file to share nine lines of `VStack` would couple
    /// the two panels' layouts for no gain.
    private func sliderRow(title: String, valueText: String, value: Binding<Double>,
                           range: ClosedRange<CGFloat>, idSuffix: String) -> some View {
        HStack(spacing: 10) {
            Text("\(title): \(valueText)")
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            Slider(value: value, in: Double(range.lowerBound)...Double(range.upperBound))
                .accessibilityIdentifier("\(Self.idPrefix).\(idSuffix)")
        }
        .padding(.horizontal)
    }

    private func menuLabel(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Every typography slider goes through here, so every one of them re-resolves the font and
    /// regrows a pristine box. A slider that wrote the property directly would change the type and
    /// leave the box the size it was, and the artist would watch their text overflow its own outline.
    private func binding(_ path: WritableKeyPath<Typography, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(canvasManager.textRecipe.typography[keyPath: path]) },
            set: {
                canvasManager.textRecipe.typography[keyPath: path] = CGFloat($0)
                canvasManager.textRecipeDidChange()
            }
        )
    }
}

/// **Every installed font family, each name set in that family** — TODO (115). Rows come from
/// `FontLibrary.groups()` and are drawn in `FontLibrary.previewFont`, the same resolution the text
/// itself goes through, so a row can never promise a face the panel cannot apply.
///
/// **A family whose own face cannot spell its name** (`FontLibrary.canSpell`) — the ornament and symbol
/// fonts — is named in the system face with a sample of itself beside it; every other row is its name
/// in its face.
///
/// **A row's accessibility value is the PostScript name of the face it is drawn in**, so a test can
/// tell a list drawn in its families from one drawn in the system face: the picture is not something
/// XCUITest can read, and a value that agreed with the family name alone would say nothing.
///
/// Lazy, because a device ships dozens of families and the list is opened to look at, not to render.
struct FontFamilyList: View {
    let current: String
    let onPick: (_ family: String, _ packID: String?) -> Void

    /// Large enough to read the face's character, small enough that ten rows share a screen.
    static let previewSize: CGFloat = 20

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(FontLibrary.shared.groups()) { group in
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    ForEach(group.families, id: \.self) { family in
                        row(family, packID: group.packID)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.92))
    }

    private func row(_ family: String, packID: String?) -> some View {
        let font = FontLibrary.shared.previewFont(inFamily: family, packID: packID, size: Self.previewSize)
        return Button {
            onPick(family, packID)
        } label: {
            HStack {
                if FontLibrary.canSpell(family, in: font) {
                    Text(family)
                        .font(Font(font as CTFont))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    // A symbol or ornament family: its own face cannot spell its name, so the name is
                    // said in the system face and the family is shown as a sample of itself.
                    Text(family)
                        .font(.system(size: Self.previewSize))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("ABC abc 123")
                        .font(Font(font as CTFont))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer()
                if family == current {
                    Image(systemName: "checkmark").foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("textPanel.font.\(family)")
        .accessibilityValue(font.fontName)
    }
}
