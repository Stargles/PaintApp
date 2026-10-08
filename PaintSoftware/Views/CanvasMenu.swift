import SwiftUI

// The two ways a menu is raised over the canvas — tapped open and pressed open — as one type each, so
// that no SwiftUI `Menu` or `.contextMenu` is written anywhere over the canvas
// (`CanvasPresentationLogicTests.testNoSystemMenuIsDeclaredOverTheCanvas`).
//
// **Why not a `Menu`.** UIKit presents a `Menu` and tears it down itself, and that teardown cancels the
// touch that closed it: a stroke begun outside an open menu was drawn and then cancelled, the layer held
// none of it, and the canvas's wedge detector announced a freeze it had repaired (BUGS.md, 2026-10-07).
// A menu drawn by `CanvasPresentationHost` is dismissed by `AnchoredMenuRouter` like every other
// presentation over the canvas, without consuming the touch: the stroke lands and the menu goes.

/// A pull-down: `label` is the control, `rows` the menu it opens — the shape of `Menu { } label: { }`.
///
/// The label is a button that toggles the menu, so a second tap closes it. Rows are `MenuItem`s,
/// `MenuSection`s and `MenuChoices`; a tap on one acts and closes the menu.
struct CanvasMenu<Label: View, Rows: View>: View {
    let presentation: CanvasPresentation
    @ObservedObject var canvasManager: CanvasManager
    let identifier: String
    let value: String?
    @ViewBuilder let rows: () -> Rows
    @ViewBuilder let label: () -> Label

    @State private var isOpen = false

    init(_ presentation: CanvasPresentation, canvasManager: CanvasManager, identifier: String,
         value: String? = nil,
         @ViewBuilder rows: @escaping () -> Rows, @ViewBuilder label: @escaping () -> Label) {
        self.presentation = presentation
        self.canvasManager = canvasManager
        self.identifier = identifier
        self.value = value
        self.rows = rows
        self.label = label
    }

    var body: some View {
        Button { isOpen.toggle() } label: { label() }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(value ?? "")
            .canvasPresentation(presentation, isPresented: $isOpen, canvasManager: canvasManager) {
                MenuList { rows() }
            }
    }
}

extension View {
    /// A menu raised by pressing and holding this view, the way `.contextMenu` was — for half a
    /// second, the same as UIKit's.
    ///
    /// **The view must take its tap with `.onTapGesture`, not be a `Button`.** A `Button` runs its
    /// action when the finger lifts however long it was held, so a held chip would also have been
    /// tapped; a tap gesture gives way to the long press.
    ///
    /// - Parameter isEnabled: false when there is nothing to offer, so a press raises no empty card.
    func canvasContextMenu<Rows: View>(_ presentation: CanvasPresentation, canvasManager: CanvasManager,
                                       isEnabled: Bool = true,
                                       @ViewBuilder rows: @escaping () -> Rows) -> some View {
        modifier(CanvasContextMenu(presentation: presentation, canvasManager: canvasManager,
                                   isEnabled: isEnabled, rows: rows))
    }
}

private struct CanvasContextMenu<Rows: View>: ViewModifier {
    let presentation: CanvasPresentation
    let canvasManager: CanvasManager
    let isEnabled: Bool
    @ViewBuilder let rows: () -> Rows

    @State private var isOpen = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.5) { if isEnabled { isOpen = true } }
            // Not the toggling control: a touch on the pressed view while its menu is up is an
            // ordinary touch, and closes the menu like any other.
            .canvasPresentation(presentation, isPresented: $isOpen, canvasManager: canvasManager,
                                anchorToggles: false) {
                MenuList { rows() }
            }
    }
}

/// The row a pull-down shows in a panel: the setting's name, its current value, and the chevron that
/// says there is a list behind it. `caption` is a second line under the name.
struct PullDownLabel: View {
    let title: String
    let value: String
    var caption: String?
    var verticalPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            if let caption {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.white)
                    Text(caption).font(.caption2).foregroundColor(.gray).lineLimit(2)
                }
            } else {
                Text(title).foregroundColor(.white)
            }
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
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
}
