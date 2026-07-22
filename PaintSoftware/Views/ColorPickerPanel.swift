import SwiftUI

/// Procreate-style color picker: a saturation/brightness square, a hue bar, an opacity slider, an
/// editable hex field, and a full custom palette builder (see Palette.swift / PaletteStore) — all
/// driving `canvasManager.brushColor` directly. The palette section lets the artist switch between
/// named palettes, create/rename/duplicate/delete them, tap a swatch to load it, add the current
/// color, and delete swatches via long-press; the whole library is app-wide and persisted.
///
/// Internally this works in HSBA (hue/saturation/brightness/alpha), the natural space for the square
/// and hue bar, and derives `Color`/hex from that on every change via `ColorConversion.swift`'s
/// helpers. Those helpers resolve against a fixed trait collection before ever reading components, so
/// — unlike the old picker's underlying conversion — tapping a swatch like `.black`/`.white` or
/// typing a gray hex value can't silently come out wrong depending on light/dark appearance.
struct ColorPickerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    /// The app-wide palette library (see Palette.swift). Shared so edits persist across the panel
    /// being rebuilt each time it's reopened.
    @ObservedObject var paletteStore: PaletteStore = .shared

    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 0
    @State private var alpha: Double = 1
    @State private var hexText: String = "000000"
    @FocusState private var hexFieldFocused: Bool

    // Palette-management sheet/alert state.
    @State private var renameTarget: Palette?
    @State private var renameText: String = ""

    /// Which page of the panel is showing. Procreate splits the color picker and the palette library
    /// onto separate tabs; keeping them separate here also keeps the picker page short enough that its
    /// custom SV-square/hue drag gestures don't have to compete with a tall scroll view.
    private enum Tab: Hashable { case color, palettes }
    @State private var tab: Tab = .color

    private static let hueSpectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    private var currentColor: Color {
        Color.fromHSBA(h: hue, s: saturation, b: brightness, a: alpha)
    }

    var body: some View {
        VStack(spacing: 12) {
            tabPicker
                .padding([.horizontal, .top])

            switch tab {
            case .color:
                colorTab
            case .palettes:
                palettesTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        .onAppear {
            let hsba = canvasManager.brushColor.hsbaComponents
            hue = hsba.h
            saturation = hsba.s
            brightness = hsba.b
            alpha = hsba.a
            hexText = canvasManager.brushColor.hexString
        }
        .alert("Rename Palette", isPresented: renameAlertBinding) {
            TextField("Palette name", text: $renameText)
                .accessibilityIdentifier("colorPanel.renameField")
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    paletteStore.renamePalette(target, to: renameText)
                }
                renameTarget = nil
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    // MARK: - Tabs

    /// A two-segment control. Built from plain buttons (rather than a segmented `Picker`) so each
    /// segment carries a stable accessibility identifier for UI tests.
    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton("Color", tab: .color, id: "colorPanel.tab.color")
            tabButton("Palettes", tab: .palettes, id: "colorPanel.tab.palettes")
        }
        .padding(3)
        .background(Color.white.opacity(0.1))
        .cornerRadius(9)
    }

    private func tabButton(_ title: String, tab target: Tab, id: String) -> some View {
        Button {
            tab = target
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(tab == target ? Color.white.opacity(0.18) : Color.clear)
                .cornerRadius(7)
        }
        .accessibilityIdentifier(id)
    }

    /// The picker page: color preview, SV square, hue bar, opacity, hex. Deliberately kept compact so
    /// it fits the panel's fixed height *without* a scroll view — a scroll view here would compete
    /// with the SV square's/hue bar's custom drag gestures and rob them of travel (that regression is
    /// exactly why the palette library lives on its own tab rather than stacked below the picker).
    private var colorTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentColor
                .frame(height: 48)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

            svSquare
                .frame(height: 150)
                .padding(.horizontal)

            hueSlider
                .frame(height: 24)
                .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Opacity: \(Int(alpha * 100))%")
                    .foregroundColor(.white)
                Slider(value: $alpha, in: 0...1)
                    .accessibilityIdentifier("colorPanel.opacitySlider")
                    .onChange(of: alpha) { _, _ in commitColor() }
            }
            .padding(.horizontal)

            hexRow
                .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    /// The palette library page.
    private var palettesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Current color, so the artist can see what "add current color" will store.
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(currentColor)
                    .frame(width: 40, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                Text("#\(hexText)")
                    .font(.footnote.monospaced())
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal)

            paletteHeader
                .padding(.horizontal)

            ScrollView {
                if let palette = paletteStore.selectedPalette {
                    paletteGrid(palette)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Saturation/Brightness square

    private var svSquare: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))

                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(currentColor))
                    .frame(width: 18, height: 18)
                    .position(x: saturation * geo.size.width, y: (1 - brightness) * geo.size.height)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in updateSV(at: value.location, in: geo.size) }
            )
        }
        .accessibilityIdentifier("colorPanel.svSquare")
    }

    private func updateSV(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        saturation = min(max(location.x / size.width, 0), 1)
        brightness = 1 - min(max(location.y / size.height, 0), 1)
        commitColor()
    }

    // MARK: - Hue slider

    private var hueSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: Self.hueSpectrum, startPoint: .leading, endPoint: .trailing))

                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(hue: hue, saturation: 1, brightness: 1)))
                    .frame(width: 22, height: 22)
                    .position(x: hue * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geo.size.width > 0 else { return }
                        hue = min(max(value.location.x / geo.size.width, 0), 1)
                        commitColor()
                    }
            )
        }
        .accessibilityIdentifier("colorPanel.hueSlider")
    }

    // MARK: - Hex field

    private var hexRow: some View {
        HStack {
            Text("#")
                .foregroundColor(.gray)
            TextField("Hex", text: $hexText)
                .foregroundColor(.white)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
                .focused($hexFieldFocused)
                .accessibilityIdentifier("colorPanel.hexField")
                .onSubmit { applyHexText() }
                .onChange(of: hexFieldFocused) { _, focused in
                    if !focused { applyHexText() }
                }
        }
    }

    /// Parses `hexText` and, if valid, updates the HSBA state (and brushColor) from it. On invalid
    /// input, reverts the displayed text to the last known-good color instead of leaving the field
    /// showing something that was never actually applied.
    private func applyHexText() {
        guard let parsed = Color(hex: hexText) else {
            hexText = currentColor.hexString
            return
        }
        let hsba = parsed.hsbaComponents
        hue = hsba.h
        saturation = hsba.s
        brightness = hsba.b
        alpha = hsba.a
        hexText = parsed.hexString
        canvasManager.brushColor = parsed
    }

    // MARK: - Palettes

    /// The Procreate-style palette builder header: the selected palette's name plus a switcher/menu
    /// for managing the library. The grid itself (with its inline "add current color" slot) is
    /// `paletteGrid`; tapping a swatch loads it into the picker, long-pressing offers to delete it.
    private var paletteHeader: some View {
        HStack(spacing: 8) {
            Text("Palette")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Spacer()

            // Palette switcher + management, kept compact in a single menu so it fits the narrow panel.
            Menu {
                Picker("Palette", selection: paletteSelectionBinding) {
                    ForEach(paletteStore.palettes) { palette in
                        Text(palette.name).tag(palette.id)
                    }
                }

                Divider()

                Button {
                    paletteStore.addPalette()
                } label: {
                    Label("New Palette", systemImage: "plus")
                }

                if let selected = paletteStore.selectedPalette {
                    Button {
                        beginRename(selected)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        paletteStore.duplicatePalette(selected)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        paletteStore.deletePalette(selected)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(paletteStore.palettes.count <= 1)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(paletteStore.selectedPalette?.name ?? "—")
                        .font(.subheadline)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .cornerRadius(8)
            }
            .accessibilityIdentifier("colorPanel.paletteMenu")
        }
    }

    private func paletteGrid(_ palette: Palette) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Palette.columns),
            spacing: 6
        ) {
            ForEach(Array(palette.colors.enumerated()), id: \.element.id) { index, swatch in
                RoundedRectangle(cornerRadius: 5)
                    .fill(swatch.color)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .accessibilityIdentifier("colorPanel.swatch.\(index)")
                    .onTapGesture { selectSwatch(swatch.color) }
                    .contextMenu {
                        Button(role: .destructive) {
                            paletteStore.removeColor(swatch, from: palette)
                        } label: {
                            Label("Delete Swatch", systemImage: "trash")
                        }
                    }
            }

            // Trailing "add current color" slot, always last so the palette fills left-to-right.
            Button {
                paletteStore.addColor(currentColor, to: palette)
            } label: {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.caption)
                    )
            }
            .accessibilityIdentifier("colorPanel.addSwatchButton")
        }
    }

    private var paletteSelectionBinding: Binding<UUID> {
        Binding(
            get: { paletteStore.selectedPalette?.id ?? paletteStore.palettes.first?.id ?? UUID() },
            set: { newID in
                if let palette = paletteStore.palettes.first(where: { $0.id == newID }) {
                    paletteStore.select(palette)
                }
            }
        )
    }

    private func beginRename(_ palette: Palette) {
        renameText = palette.name
        renameTarget = palette
    }

    private func selectSwatch(_ color: Color) {
        let hsba = color.hsbaComponents
        hue = hsba.h
        saturation = hsba.s
        brightness = hsba.b
        alpha = hsba.a
        hexText = color.hexString
        canvasManager.brushColor = color
    }

    /// Pushes the current HSBA state to `canvasManager.brushColor` and, unless the hex field is
    /// mid-edit, refreshes its displayed text to match.
    private func commitColor() {
        canvasManager.brushColor = currentColor
        if !hexFieldFocused {
            hexText = currentColor.hexString
        }
    }
}
