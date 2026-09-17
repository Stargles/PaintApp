import SwiftUI

/// The swatch grid every picker tab shows for one palette — the type tabs' "selected palette" section
/// (item 2) and `PalettesLibraryView`'s per-palette row (item 3) are both this, just with a different
/// `idPrefix` and always exactly one shared `PaletteStore`/model underneath. Tapping a filled swatch
/// picks it; long-pressing one offers to delete it (`.contextMenu`, which is itself a long-press).
/// Long-pressing an *empty* cell adds the current colour (Procreate's behaviour) — the leading empty
/// cell also answers a plain tap, since it is the one call sites relied on as a visible "+" button
/// before this existed, and there is no reason a long-press-only affordance should be less
/// discoverable than it has to be.
///
/// Always shows at least one full empty row past whatever is filled (rounded up to `Palette.columns`),
/// so there is always somewhere obvious to long-press.
struct PaletteSwatchGrid: View {
    @ObservedObject var paletteStore: PaletteStore
    let palette: Palette
    let currentColor: Color
    let idPrefix: String
    var onPick: (Color) -> Void = { _ in }

    private var emptyCount: Int {
        let filled = palette.colors.count
        let remainder = filled % Palette.columns
        let toFillRow = remainder == 0 ? 0 : Palette.columns - remainder
        return toFillRow + Palette.columns
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Palette.columns),
            spacing: 6
        ) {
            ForEach(Array(palette.colors.enumerated()), id: \.element.id) { index, swatch in
                RoundedRectangle(cornerRadius: 5)
                    .fill(swatch.color)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .accessibilityIdentifier("\(idPrefix).swatch.\(index)")
                    .accessibilityValue(swatch.hex)
                    .onTapGesture { onPick(swatch.color) }
                    .contextMenu {
                        Button(role: .destructive) {
                            paletteStore.removeColor(swatch, from: palette)
                        } label: {
                            Label("Delete Swatch", systemImage: "trash")
                        }
                    }
            }

            // The leading empty cell is a real `Button` — tap to add, exactly the one discoverable
            // "+" this grid always had (`colorPanel.addSwatchButton`, unchanged identifier and
            // element type, so every existing call site still finds and taps it). The rest are
            // long-press-only, per item 2's "long-press an empty palette cell" — plain shapes, not
            // buttons, since a `Button` fighting its own tap gesture for a long-press is the kind of
            // interaction SwiftUI doesn't resolve reliably, and there is already one fully
            // discoverable way to add without hunting for the exact cell to long-press.
            Button {
                paletteStore.addColor(currentColor, to: palette)
            } label: {
                emptyCellLabel
            }
            .accessibilityIdentifier("\(idPrefix).addSwatchButton")

            // `emptyCount` is always >= `Palette.columns` (10), so this range is never empty.
            ForEach(1..<emptyCount, id: \.self) { offset in
                emptyCellLabel
                    .contentShape(Rectangle())
                    .onLongPressGesture { paletteStore.addColor(currentColor, to: palette) }
                    .accessibilityIdentifier("\(idPrefix).emptySwatch.\(offset)")
            }
        }
    }

    private var emptyCellLabel: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3]))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Image(systemName: "plus")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.caption2)
            )
    }
}

/// TODO (73) item 3 — the Palettes tab: every one of the artist's palettes, each a name row (rename/
/// delete, the same always-visible pencil/trash pattern `LayerPanel`'s saved-views menu uses) plus a
/// Default indicator or Set Default button, and its full swatch grid; "New Palette" at the top.
///
/// **"Default" is `PaletteStore.selectedPaletteID`** — the palette the type tabs show — not a second
/// notion of default this view invents. Setting one here is exactly `paletteStore.select(_:)`, the
/// same call a swatch tap on a type tab never makes (picking a colour there doesn't change which
/// palette is "active"; only this tab's own button does).
struct PalettesLibraryView: View {
    @ObservedObject var paletteStore: PaletteStore
    let currentColor: Color
    var onPick: (Color) -> Void = { _ in }

    @State private var renamingPalette: Palette?
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Palettes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    paletteStore.addPalette()
                } label: {
                    Label("New Palette", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(6)
                }
                .accessibilityIdentifier("colorPanel.palettes.newButton")
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(paletteStore.palettes.enumerated()), id: \.element.id) { index, palette in
                        paletteRow(index: index, palette: palette)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .alert("Rename Palette", isPresented: Binding(
            get: { renamingPalette != nil },
            set: { if !$0 { renamingPalette = nil } }
        )) {
            TextField("Palette name", text: $renameText)
                .accessibilityIdentifier("colorPanel.palettes.renameField")
            Button("Cancel", role: .cancel) { renamingPalette = nil }
            Button("Save") {
                if let target = renamingPalette {
                    paletteStore.renamePalette(target, to: renameText)
                }
                renamingPalette = nil
            }
        }
    }

    private func paletteRow(index: Int, palette: Palette) -> some View {
        let idPrefix = "colorPanel.palettes.row.\(index)"
        let isDefault = palette.id == paletteStore.selectedPaletteID
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(palette.name)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if isDefault {
                    Text("Default")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.18))
                        .cornerRadius(5)
                        .accessibilityIdentifier("\(idPrefix).defaultIndicator")
                } else {
                    Button {
                        paletteStore.select(palette)
                    } label: {
                        Text("Set Default")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(idPrefix).setDefault")
                }

                Button {
                    renameText = palette.name
                    renamingPalette = palette
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(idPrefix).rename")

                Button(role: .destructive) {
                    paletteStore.deletePalette(palette)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(paletteStore.palettes.count <= 1)
                .accessibilityIdentifier("\(idPrefix).delete")
            }

            PaletteSwatchGrid(paletteStore: paletteStore, palette: palette, currentColor: currentColor,
                              idPrefix: idPrefix, onPick: onPick)
        }
    }
}
