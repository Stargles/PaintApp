import SwiftUI
import UIKit

// MARK: - The colour wheels
//
// TODO (63)'s Colour Wheels, the owner's *"Try to put some effort into making the UI for it nice. 4
// color pickers, plus their respective sliders."* `EffectSettingsBar` shows this in place of its slider
// rows for `Effect.colorWheels`; the model, the arithmetic and the weights are all in
// `Effect.ColorWheels`, and nothing here decides what a drag *means* — every write goes out through
// the same `onParameterChange` a slider row uses, so the keyframe routing (`KeyframeControl.write`),
// the live-take intercept and the one-undo-step-per-gesture bracket are the bar's, unchanged.

/// Four real colour wheels in a row — Shadows, Midtones, Highlights, Global — each a disc with a
/// draggable dot, a luminance slider and a strength slider beneath it and a reset beside its name.
///
/// **One row of four, not two rows of two, on the 13" iPad.** The bar is `BottomDock.preferredWidth`
/// (760) there, which is four columns of ~175 with the dock's own row padding, and a column holds a
/// 112pt disc, two compact sliders and a title in ~205pt — under `BottomDock.maxScrollHeight`'s 260
/// with the bar's note beneath, so the whole corrector is on screen at once with nothing to scroll,
/// which is how every grading program lays its wheels out and the reason an artist can read all four
/// dots against each other. `ViewThatFits` falls back to two-by-two when the bar is narrower than
/// four columns (a split view), where the bar's ceiling then scrolls.
///
/// **The disc is drawn once per pixel size and cached** (`ColorWheelDisc`), from the same Oklab
/// arithmetic the grade runs: a point at angle `θ` and radius `r` on the disc is a mid-grey pushed by
/// `r · rimChroma` toward `θ`, so the colour under the dot *is* the push, and the dot is painted the
/// same colour with the wheel's luminance applied. Nothing here approximates the wheel with an HSB
/// angular gradient, which would put the dot's colour beside the direction it pushes rather than on it.
///
/// **A drag places the dot under the finger; a tap does nothing; a double-tap resets the wheel.**
/// Absolute rather than relative because a fingertip on a 112pt disc is the direct thing, and a tap
/// is deliberately inert so a double-tap is one edit (a reset) rather than three (place, place,
/// reset). The reset button beside the name does the same and is the discoverable door.
///
/// **No `.accessibilityIdentifier` on any container here.** The disc image, the dot, each slider and
/// the reset button carry their own (`effectSettings.colorWheels.<wheel>.disc/.dot/.luminance/
/// .strength/.reset`), and an identifier on the `ZStack` or the column would stamp every one of them
/// — CLAUDE.md's rule, found live twice this month.
struct ColorWheelsEditor: View {
    let wheels: Effect.ColorWheels
    /// `Effect.parameters` for the effect being edited, so every write goes out by descriptor.
    let parameters: [EffectParameter]
    var animatedChannelIDs: Set<String> = []
    var onParameterChange: (EffectParameter, Double) -> Void
    var onEditBegan: () -> Void
    var onEditEnded: () -> Void
    var onSliderTouchDown: (EffectParameter) -> Void = { _ in }

    /// The four wheels in the order the bar shows them — Lumetri's order, dark to light, then Global.
    enum WheelID: String, CaseIterable {
        case shadows, midtones, highlights, global

        var title: String {
            switch self {
            case .shadows:    return "Shadows"
            case .midtones:   return "Midtones"
            case .highlights: return "Highlights"
            case .global:     return "Global"
            }
        }

        func wheel(of wheels: Effect.ColorWheels) -> Effect.ColorWheels.Wheel {
            switch self {
            case .shadows:    return wheels.shadows
            case .midtones:   return wheels.midtones
            case .highlights: return wheels.highlights
            case .global:     return wheels.global
            }
        }
    }

    static let discDiameter: CGFloat = 112
    static let dotDiameter: CGFloat = 18
    private static let columnWidth: CGFloat = 168
    private static let columnSpacing: CGFloat = 10
    /// Below this much movement a touch is a tap rather than a drag, and places nothing.
    private static let tapSlop: CGFloat = 5
    /// Two taps closer than this on one disc are a double-tap, which resets the wheel.
    private static let doubleTapInterval: TimeInterval = 0.4

    /// Which wheel the live drag is on and whether it has moved past the slop — cleared on `.onEnded`,
    /// the only place `onEditEnded` is called, so a drag that never moved closes no bracket.
    @State private var dragging: WheelID?
    @State private var didMove = false
    /// When the last inert tap landed, per wheel, for the double-tap.
    @State private var lastTap: [WheelID: Date] = [:]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                ForEach(WheelID.allCases, id: \.self) { column(for: $0) }
            }
            VStack(spacing: Self.columnSpacing) {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    column(for: .shadows); column(for: .midtones)
                }
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    column(for: .highlights); column(for: .global)
                }
            }
        }
        .padding(.horizontal, BottomDock.rowHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: One wheel

    private func column(for id: WheelID) -> some View {
        let wheel = id.wheel(of: wheels)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                if isAnimated(id, "hue") || isAnimated(id, "saturation") {
                    Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundColor(.blue)
                }
                Text(id.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 0)
                Button {
                    reset(id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(wheel == Effect.ColorWheels.Wheel() ? 0.3 : 0.85))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("effectSettings.colorWheels.\(id.rawValue).reset")
            }
            .padding(.horizontal, 2)

            disc(for: id, wheel: wheel)

            compactSlider(id, "luminance", label: "Lum")
            compactSlider(id, "strength", label: "Strength")
        }
        .frame(width: Self.columnWidth)
    }

    private func disc(for id: WheelID, wheel: Effect.ColorWheels.Wheel) -> some View {
        let size = Self.discDiameter
        let dot = Self.dotPosition(wheel, diameter: size)
        return ZStack {
            Image(uiImage: ColorWheelDisc.image(diameter: size))
                .resizable()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .accessibilityIdentifier("effectSettings.colorWheels.\(id.rawValue).disc")
            // A faint cross through the centre, so "no push" has a mark to sit on.
            Path { path in
                path.move(to: CGPoint(x: size / 2, y: 0)); path.addLine(to: CGPoint(x: size / 2, y: size))
                path.move(to: CGPoint(x: 0, y: size / 2)); path.addLine(to: CGPoint(x: size, y: size / 2))
            }
            .stroke(Color.black.opacity(0.12), lineWidth: 1)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            Circle()
                .fill(Self.dotColour(wheel))
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .position(dot)
                .accessibilityIdentifier("effectSettings.colorWheels.\(id.rawValue).dot")
                // Hue and saturation, so a test reads the model back rather than a screen position.
                .accessibilityValue(String(format: "%.2f|%.4f", wheel.hue, wheel.saturation))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(dragGesture(id))
    }

    // MARK: Geometry and colour

    /// Where the dot sits on a disc of `diameter` — 0° to the right, angles turning anticlockwise on
    /// screen (yellow at the top, blue at the bottom), radius `saturation` clamped to the rim.
    static func dotPosition(_ wheel: Effect.ColorWheels.Wheel, diameter: CGFloat) -> CGPoint {
        let radius = diameter / 2
        let reach = radius - dotDiameter / 2
        let saturation = wheel.saturation.isFinite ? min(max(wheel.saturation, 0), 1) : 0
        let radians = (wheel.hue.isFinite ? wheel.hue : 0) * .pi / 180
        return CGPoint(x: radius + reach * saturation * cos(radians),
                       y: radius - reach * saturation * sin(radians))
    }

    /// The inverse of `dotPosition`: a touch at `point` on the disc, as (hue in degrees, 0…1
    /// saturation). Beyond the rim is the rim.
    static func polar(of point: CGPoint, diameter: CGFloat) -> (hue: Double, saturation: Double) {
        let radius = diameter / 2
        let reach = radius - dotDiameter / 2
        let dx = point.x - radius, dy = radius - point.y
        let angle = atan2(dy, dx) * 180 / .pi
        return (angle < 0 ? angle + 360 : angle, min(hypot(dx, dy) / reach, 1))
    }

    /// The colour a mid-grey becomes under this wheel alone, at full weight — the disc's own
    /// arithmetic with the luminance slider applied, so the dot says what it does.
    static func dotColour(_ wheel: Effect.ColorWheels.Wheel) -> Color {
        let saturation = wheel.saturation.isFinite ? min(max(wheel.saturation, 0), 1) : 0
        let strength = wheel.strength.isFinite ? min(max(wheel.strength, 0), 1) : 0
        let radians = (wheel.hue.isFinite ? wheel.hue : 0) * .pi / 180
        let chroma = saturation * Effect.ColorWheels.rimChroma * strength
        let luminance = wheel.luminance.isFinite ? min(max(wheel.luminance, -1), 1) : 0
        let L = min(max(ColorWheelDisc.discLightness
                        + luminance * Effect.ColorWheels.luminanceReach * strength, 0), 1)
        let rgb = ColorMath.oklabToRGB(L: L, a: chroma * cos(radians), b: chroma * sin(radians))
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: Gesture

    private func dragGesture(_ id: WheelID) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil { dragging = id }
                guard dragging == id else { return }
                guard didMove || hypot(value.translation.width, value.translation.height) > Self.tapSlop
                else { return }
                let hueParameter = parameter(id, "hue"), satParameter = parameter(id, "saturation")
                if !didMove {
                    didMove = true
                    // The landing before the bracket, `sliderRow`'s own order: the take's undo step
                    // has to be the outer one.
                    if let hueParameter { onSliderTouchDown(hueParameter) }
                    onEditBegan()
                }
                let polar = Self.polar(of: value.location, diameter: Self.discDiameter)
                let current = id.wheel(of: wheels)
                if let hueParameter {
                    onParameterChange(hueParameter,
                                      Effect.ColorWheels.continuedHue(from: current.hue, toward: polar.hue))
                }
                if let satParameter { onParameterChange(satParameter, polar.saturation) }
            }
            .onEnded { value in
                defer { dragging = nil; didMove = false }
                guard dragging == id else { return }
                if didMove {
                    onEditEnded()
                    return
                }
                guard hypot(value.translation.width, value.translation.height) <= Self.tapSlop else { return }
                // An inert tap — unless it is the second of two, which is a reset.
                let now = Date()
                if let previous = lastTap[id], now.timeIntervalSince(previous) <= Self.doubleTapInterval {
                    lastTap[id] = nil
                    reset(id)
                } else {
                    lastTap[id] = now
                }
            }
    }

    /// The wheel back to its identity — dot at the centre, hue 0, no lift, full strength — as one
    /// undo step, through the four descriptors so a keyed channel gets its key.
    private func reset(_ id: WheelID) {
        let identity = Effect.ColorWheels.Wheel()
        let writes: [(String, Double)] = [("hue", identity.hue), ("saturation", identity.saturation),
                                          ("luminance", identity.luminance), ("strength", identity.strength)]
        onEditBegan()
        for (field, value) in writes {
            if let parameter = parameter(id, field) { onParameterChange(parameter, value) }
        }
        onEditEnded()
    }

    // MARK: Sliders

    /// A slider short enough for a column — the bar's `sliderRow` with its 128pt label column and
    /// 52pt readout folded down to what fits beside a disc. Same bracket, same landing, same
    /// identifier scheme, same `accessibilityValue`.
    @ViewBuilder
    private func compactSlider(_ id: WheelID, _ field: String, label: String) -> some View {
        if let parameter = parameter(id, field), let range = parameter.uiRange,
           let value = parameter.read(.colorWheels(wheels)) {
            HStack(spacing: 5) {
                HStack(spacing: 3) {
                    if animatedChannelIDs.contains(parameter.id) {
                        Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundColor(.blue)
                    }
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(width: 46, alignment: .leading)
                Slider(value: Binding(get: { value }, set: { onParameterChange(parameter, $0) }),
                       in: range) { editing in
                    if editing { onSliderTouchDown(parameter); onEditBegan() } else { onEditEnded() }
                }
                .controlSize(.mini)
                .accessibilityIdentifier("effectSettings.\(parameter.controlIdentifier ?? parameter.id)")
                .accessibilityValue(String(format: "%.4f", value))
                Text(String(format: parameter.format ?? "%.2f", value))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 2)
        }
    }

    private func parameter(_ id: WheelID, _ field: String) -> EffectParameter? {
        let wanted = "colorWheels.\(id.rawValue).\(field)"
        let found = parameters.first { $0.id == wanted }
        assert(found != nil, "Colour Wheels has no parameter \"\(wanted)\"")
        return found
    }

    private func isAnimated(_ id: WheelID, _ field: String) -> Bool {
        animatedChannelIDs.contains("colorWheels.\(id.rawValue).\(field)")
    }
}

// MARK: - The disc

/// The colour disc every wheel is drawn on, rendered once per pixel size and kept.
///
/// A point at angle `θ` and radius `r` (0 at the centre, 1 at the rim) is Oklab
/// `(discLightness, r · rimChroma · cos θ, r · rimChroma · sin θ)` — the same push the grade applies
/// to a pixel of that lightness at that dot position, at full strength — converted through
/// `ColorMath.oklabToRGB`, which clamps per channel exactly as the kernels do. So the disc is a
/// picture of the effect rather than a decoration beside it. Outside the rim the image is
/// transparent; the view clips to a circle anyway.
enum ColorWheelDisc {

    /// The lightness the disc is drawn at — a mid-grey light enough that every hue at `rimChroma`
    /// stays inside sRGB (blue's gamut narrows fastest as `L` rises; at 0.6 and chroma 0.15 it is
    /// still inside), and the lightness `ColorWheelsEditor.dotColour` starts from.
    static let discLightness = 0.6

    private static var cache: [Int: UIImage] = [:]
    private static let lock = NSLock()

    /// The disc at `diameter` points, at the main screen's scale.
    static func image(diameter: CGFloat) -> UIImage {
        let scale = UIScreen.main.scale
        let pixels = max(Int((diameter * scale).rounded()), 2)
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[pixels] { return cached }
        let rendered = render(pixels: pixels, scale: scale)
        cache[pixels] = rendered
        return rendered
    }

    private static func render(pixels: Int, scale: CGFloat) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        let radius = Double(pixels) / 2
        for y in 0..<pixels {
            for x in 0..<pixels {
                let dx = Double(x) + 0.5 - radius, dy = radius - (Double(y) + 0.5)
                let distance = (dx * dx + dy * dy).squareRoot() / radius
                // A one-pixel soft edge so the rim does not alias against the card.
                let coverage = min(max((1 - distance) * radius, 0), 1)
                guard coverage > 0 else { continue }
                let r = min(distance, 1)
                let angle = atan2(dy, dx)
                let chroma = r * Effect.ColorWheels.rimChroma
                let rgb = ColorMath.oklabToRGB(L: discLightness, a: chroma * cos(angle), b: chroma * sin(angle))
                let offset = (x + y * pixels) * 4
                bytes[offset] = UInt8((rgb.r * coverage * 255).rounded())
                bytes[offset + 1] = UInt8((rgb.g * coverage * 255).rounded())
                bytes[offset + 2] = UInt8((rgb.b * coverage * 255).rounded())
                bytes[offset + 3] = UInt8((coverage * 255).rounded())
            }
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: pixels * 4, space: space, bitmapInfo: info,
                                    provider: provider, decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
