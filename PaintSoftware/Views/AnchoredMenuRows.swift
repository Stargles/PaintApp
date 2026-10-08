import SwiftUI

// What an `AnchoredMenu` of rows is made of. A pull-down, a long-press menu and the timeline's cel menu
// are all `MenuList { MenuItem… MenuSection… }` — one look, one way to close, one way to be reached by a
// test — where each was a SwiftUI `Menu` or a hand-built `VStack` before.

/// The list a menu shows: its rows at their natural size, scrolling once they run past
/// `AnchoredMenuPlacement.scrollableHeight`.
///
/// **A scroll view, so the whole list is in the accessibility tree at once.** A SwiftUI `Menu` realises
/// only the rows near its viewport, which is why a test had to sweep the menu to make a late entry
/// exist at all (`PaintUITestCase.scrollMenuTo`); every row here exists and XCUITest scrolls to it.
struct MenuList<Content: View>: View {
    @Environment(\.anchoredMenuScrollableHeight) private var scrollableHeight
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 190, maxHeight: scrollableHeight)
    }
}

/// One row: an optional icon, its title, and a tick on the right when it is the current choice.
///
/// **Acting closes the menu** (`EnvironmentValues.dismissAnchoredMenu`), the way a `Menu`'s row does —
/// after the action, so a row that closes the very panel the menu hangs off still runs.
///
/// `identifier` is optional: a row a test names by its label needs none, and a row the suite already
/// reaches by identifier (every blend mode and effect) keeps it. The label is always the title, so the
/// icon never leaks into what VoiceOver or a query reads.
struct MenuItem<Icon: View>: View {
    let title: String
    var isSelected = false
    var role: ButtonRole?
    var identifier: String?
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.dismissAnchoredMenu) private var dismiss

    var body: some View {
        Button(role: role) {
            action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                icon()
                Text(title)
                Spacer(minLength: 16)
                if isSelected {
                    Image(systemName: "checkmark").font(.footnote.weight(.semibold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(role == .destructive ? .red : .primary)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A row's leading symbol, 20 pt wide so titles line up down a column of them.
struct MenuItemSymbol: View {
    let name: String
    var body: some View { Image(systemName: name).frame(width: 20) }
}

extension MenuItem where Icon == MenuItemSymbol? {
    /// The common row: an SF Symbol, or none.
    init(_ title: String, systemImage: String? = nil, isSelected: Bool = false, role: ButtonRole? = nil,
         identifier: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, isSelected: isSelected, role: role, identifier: identifier, action: action) {
            if let systemImage { MenuItemSymbol(name: systemImage) }
        }
    }
}

extension MenuItem {
    /// A row with a picture of its own — a brush tip's mask beside its name.
    init(_ title: String, isSelected: Bool = false, role: ButtonRole? = nil, identifier: String? = nil,
         action: @escaping () -> Void, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title: title, isSelected: isSelected, role: role, identifier: identifier, action: action,
                  icon: icon)
    }
}

/// A run of rows under a small heading — the blend modes by family, the effects by kind.
struct MenuSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }
            content()
        }
    }
}

/// A hairline between groups of rows that have no heading to separate them.
struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.vertical, 4)
    }
}

/// Rows for every value of a pick-one setting, the current one ticked — the shape each picker in the
/// editor repeated by hand. `identifier` names a row for a test.
struct MenuChoices<Value: Hashable>: View {
    let values: [Value]
    let selected: Value?
    let title: (Value) -> String
    var identifier: ((Value) -> String)?
    let onSelect: (Value) -> Void

    var body: some View {
        ForEach(values, id: \.self) { value in
            MenuItem(title(value), isSelected: value == selected, identifier: identifier?(value)) {
                onSelect(value)
            }
        }
    }
}
