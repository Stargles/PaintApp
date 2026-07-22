import SwiftUI

/// Procreate-style color picker: a saturation/brightness square, a hue bar, an opacity slider, an
/// editable hex field, and a small swatch palette — all driving `canvasManager.brushColor` directly.
///
/// Internally this works in HSBA (hue/saturation/brightness/alpha), the natural space for the square
/// and hue bar, and derives `Color`/hex from that on every change via `ColorConversion.swift`'s
/// helpers. Those helpers resolve against a fixed trait collection before ever reading components, so
/// — unlike the old picker's underlying conversion — tapping a swatch like `.black`/`.white` or
/// typing a gray hex value can't silently come out wrong depending on light/dark appearance.
struct ColorPickerPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 0
    @State private var alpha: Double = 1
    @State private var hexText: String = "000000"
    @FocusState private var hexFieldFocused: Bool

    @State private var customSwatches: [Color] = []
    private static let defaultSwatchColors: [Color] = [
        .black, .white, .red, .orange, .yellow, .green, .blue, .purple
    ]
    private static let hueSpectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    private var currentColor: Color {
        Color.fromHSBA(h: hue, s: saturation, b: brightness, a: alpha)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Color")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                currentColor
                    .frame(height: 56)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)

                svSquare
                    .frame(height: 180)
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

                swatchGrid
                    .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.bottom, 16)
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

    // MARK: - Swatches

    private var swatchGrid: some View {
        let allSwatches = Self.defaultSwatchColors + customSwatches
        return VStack(alignment: .leading, spacing: 8) {
            Text("Swatches")
                .foregroundColor(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 30), spacing: 8)], spacing: 8) {
                ForEach(Array(allSwatches.enumerated()), id: \.offset) { index, swatch in
                    Circle()
                        .fill(swatch)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .accessibilityIdentifier("colorPanel.swatch.\(index)")
                        .onTapGesture { selectSwatch(swatch) }
                }

                Button(action: addCurrentAsSwatch) {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                                .font(.caption)
                        )
                }
                .accessibilityIdentifier("colorPanel.addSwatchButton")
            }
        }
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

    private func addCurrentAsSwatch() {
        customSwatches.append(currentColor)
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
