import SwiftUI

/// Which `CanvasManager` state a `StrokeSettingsPanel` drives, plus its labelling. The paint brush
/// and the eraser expose the same knobs over two parallel sets of properties (`selectedBrush`/
/// `brushSize`/`brushOpacity` vs `selectedEraserBrush`/`eraserSize`/`eraserOpacity`), so the panel
/// itself is shared and only this differs — see `BrushSettingsPanel`/`EraserSettingsPanel`.
///
/// **There is no `presets` keypath any more.** It used to name two different arrays —
/// `availableBrushes` for the brush, `availableEraserBrushes` (the five built-ins, no imports) for
/// the eraser — and BRUSH.md §11 rules that distinction away: *the eraser is a brush*, so an
/// imported tip erases with no eraser work. One library, two selections.
struct StrokeSettingsSpec {
    let title: String
    /// Prefix for every control's accessibility identifier, e.g. "brushPanel" → "brushPanel.sizeSlider".
    let idPrefix: String
    let selectedBrush: ReferenceWritableKeyPath<CanvasManager, Brush>
    let size: ReferenceWritableKeyPath<CanvasManager, CGFloat>
    let opacity: ReferenceWritableKeyPath<CanvasManager, Double>
    let selectPreset: (CanvasManager, Brush) -> Void
    /// Which tool's stamp the Size slider's real-size preview should draw. Carried here rather than
    /// inferred from `idPrefix` so adding a third stroke tool is a compile error, not a string match
    /// that quietly falls through to the brush.
    let previewTool: SizePreviewTool
}

/// **The brushes menu** — BRUSH.md §7.1, reached by §2.20's second tap on the tool icon.
///
/// Two independently scrolling columns: the groups on the left with the open one highlighted, that
/// group's brushes on the right, one row each showing the brush's **name over a stroke of itself**.
/// The open group's name and a chevron sit top-left, the `+` top-right.
///
/// ## What this replaced, and why the sliders moved
///
/// It was a horizontal strip of five preset icons above six sliders — Size, Opacity, Pressure →
/// Size, Pressure → Flow, Stabilization, Spacing — with the Import Custom Brush row below them,
/// **below the fold**, which the owner reported having to scroll to find. BRUSH.md §2.20 rules that
/// *"a brush parameter is changed in the brush editor and nowhere else"*, so those six are now
/// behind the second tap (`BrushEditorView`) and the importer is on the `+`, which is the top-right
/// corner of the first thing the artist sees.
///
/// ## The editor is a screen, and it is raised from here rather than shown inside here
///
/// §2.24: *"we need to have it cover the entire screen due to the complex interactions it can have."*
/// So the second tap calls `onEditBrush` and `DrawingView` puts `BrushEditorScreen` up as a layer of
/// its own `ZStack` — **not** a `.fullScreenCover`, for the reason the push it replaced existed: the
/// Size slider raises a real-size stamp preview drawn by `DrawingView`'s overlay against the
/// slider's frame in that view's coordinate space (`SizePreviewRequest`, `SizePreviewWindow`), and a
/// modal presentation is a separate window *above* that overlay, so the preview would be drawn
/// behind it and the control would look inert. A layer keeps one view tree, one coordinate space and
/// one preference chain, and leaves `activePanel` on `.brush` — which is what `CanvasTouchOwner` and
/// the draw-to-dismiss path already read.
///
/// `accessory` is extra content below the columns (the eraser's vector-mode picker; the brush has
/// none), `addMenuItems` is what the `+` offers beyond New Group (the brush's tip importer), and
/// `onEditBrush` is §2.20's second tap — which `DrawingView` answers by raising the full-screen
/// editor, because §2.24 rules the editor a screen and this panel is a 300-point dropdown.
struct StrokeSettingsPanel<Accessory: View, AddItems: View>: View {
    @ObservedObject var canvasManager: CanvasManager
    @ObservedObject var library: BrushLibraryStore
    let spec: StrokeSettingsSpec
    let onEditBrush: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let addMenuItems: () -> AddItems

    /// Which group's brushes the right column is showing. View state rather than manager state: the
    /// panel is rebuilt on every `activePanel` switch, and opening onto the group holding whatever is
    /// selected is a better answer than remembering where the artist last was.
    @State private var openGroupID: UUID?
    @State private var renamingGroup: BrushGroup?
    @State private var renameText = ""

    private var brush: Brush { canvasManager[keyPath: spec.selectedBrush] }

    private var openGroup: BrushGroup? {
        if let openGroupID, let found = library.groups.first(where: { $0.id == openGroupID }) { return found }
        return library.groupToOpen(forSelected: brush.id)
    }

    var body: some View {
        menu
        // **Top-aligned and filling, and the alternative was tried and looked worse.** `DrawingView`
        // draws the card — 300 wide, `maxHeight: 420`, centre-aligned — so a panel that hugs its
        // content floats in the middle of a card that is still 420 tall, with black above the header
        // as well as below the columns. Filling puts the header at the top where §7.1 wants it and
        // spends the slack on the two scroll areas, which is also what happens once §8.6's five
        // groups of up to thirty brushes land.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        // The panel can be dismissed out from under a held slider (`interactionBegan` closes it on
        // the next canvas touch), and a slider that goes away never sends `onEditingChanged(false)`.
        // Without this the window would be stranded on screen with nothing left to lower it.
        .onDisappear { canvasManager.sizePreview.dismiss() }
        .onAppear { openGroupID = library.groupToOpen(forSelected: brush.id)?.id }
        .alert("Rename Group", isPresented: Binding(get: { renamingGroup != nil },
                                                    set: { if !$0 { renamingGroup = nil } })) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("\(spec.idPrefix).renameField")
            Button("Cancel", role: .cancel) { renamingGroup = nil }
            Button("Rename") {
                if let group = renamingGroup { library.renameGroup(group.id, to: renameText) }
                renamingGroup = nil
            }
            .accessibilityIdentifier("\(spec.idPrefix).renameConfirm")
        }
    }

    // MARK: - The menu

    private var menu: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.15))
            HStack(spacing: 0) {
                groupColumn
                Divider().overlay(Color.white.opacity(0.15))
                brushColumn
            }
            accessory()
        }
    }

    /// The set name with its chevron top-left, the `+` top-right — §7.1.
    ///
    /// The chevron is not decoration: it opens the **open group's own** menu, which is where rename
    /// and reordering live. A library whose groups could not be renamed or ordered would be a list
    /// the artist cannot organise, which is the half of §2.16 that is not "make your own".
    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Rename…") {
                    renameText = openGroup?.name ?? ""
                    renamingGroup = openGroup
                }
                .accessibilityIdentifier("\(spec.idPrefix).renameGroup")
                Button("Move Up") { if let id = openGroup?.id { library.moveGroup(id, by: -1) } }
                Button("Move Down") { if let id = openGroup?.id { library.moveGroup(id, by: 1) } }
                if library.groups.count > 1 {
                    Button("Delete Group", role: .destructive) {
                        guard let id = openGroup?.id else { return }
                        library.removeGroup(id)
                        openGroupID = library.groups.first?.id
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(openGroup?.name ?? spec.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .accessibilityIdentifier("\(spec.idPrefix).groupMenu")

            Spacer(minLength: 4)

            Menu {
                addMenuItems()
                Button("New Group") {
                    openGroupID = library.addGroup().id
                }
                .accessibilityIdentifier("\(spec.idPrefix).newGroup")
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("\(spec.idPrefix).addButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var groupColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(library.groups) { group in
                    groupRow(group)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 106)
        // **The menu's own "I am on screen" element, and it is on the `ScrollView` deliberately.**
        // An identifier on the enclosing `VStack` is *inherited* by descendants rather than making a
        // container element of its own: it produced no `otherElements` node at all, and it silently
        // overwrote the two `Menu`s' identifiers, so `addButton` and `groupMenu` were both
        // unreachable while looking perfectly correct in the source. A `ScrollView` carries one.
        .accessibilityIdentifier("\(spec.idPrefix).groupList")
    }

    private func groupRow(_ group: BrushGroup) -> some View {
        let isOpen = group.id == openGroup?.id
        return Button {
            openGroupID = group.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundColor(isOpen ? .blue : .white.opacity(0.7))
                Text(group.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(isOpen ? Color.white.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("\(spec.idPrefix).group.\(group.name)")
        .accessibilityAddTraits(isOpen ? [.isSelected] : [])
    }

    private var brushColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Lazy so a group of thirty brushes renders the strokes for the rows on screen and not
            // for the twenty-two below the fold — §7.1's *"a panel that stamps thirty strokes
            // synchronously on open is a defect"*. `BrushPreviewRow` then takes its own render off
            // the main thread; the two together are what keep opening the menu free.
            LazyVStack(spacing: 0) {
                ForEach(openGroup?.brushes ?? []) { candidate in
                    brushRow(candidate)
                }
                if openGroup?.brushes.isEmpty ?? true {
                    Text("No brushes in this group yet — add one with +")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .padding(12)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// **One tap selects, a second tap on the already-selected row opens the editor** — §2.20.
    ///
    /// The row's own highlight is what makes that unambiguous, so it is exposed as an accessibility
    /// trait as well as drawn: a test that only read `canvasManager.selectedBrush` would stay green
    /// against a menu that had stopped highlighting anything, and the artist would have no way to
    /// know which tap they were about to make.
    private func brushRow(_ candidate: Brush) -> some View {
        let isSelected = candidate.id == brush.id
        return Button {
            if isSelected {
                onEditBrush()
            } else {
                spec.selectPreset(canvasManager, candidate)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .blue : .white)
                    .lineLimit(1)
                BrushPreviewRow(brush: candidate)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("\(spec.idPrefix).brush.\(candidate.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One row's rendered stroke — BRUSH.md §7.1's *"a brush's row is its name over a rendered stroke of
/// itself"*.
///
/// Renders **off the main thread** and only when the row is actually built, which with the enclosing
/// `LazyVStack` means when it is on screen. A cache hit is taken synchronously so a row that has
/// been seen before never flickers through the placeholder.
struct BrushPreviewRow: View {
    let brush: Brush
    var size = CGSize(width: 156, height: 26)

    @State private var image: UIImage?

    private var key: BrushPreviewKey { BrushPreviewKey(brush: brush, size: size, scale: 2) }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: size.width, height: size.height)
            if let image = image ?? BrushPreviewCache.shared.cached(key) {
                // **No `.accessibilityHidden(true)` here, and that is a fix rather than an
                // omission.** Marking the preview hidden — the obvious thing to do to a picture whose
                // meaning the row's own label already carries — made the **entire row unhittable**:
                // a row's centre lands on this image, the accessibility hit test there resolved to
                // nothing, and XCUITest reported `Computed hit point {-1, -1}` for all five rows
                // while the group rows beside them were fine. It is not only a harness problem —
                // direct-touch exploration under VoiceOver finds the same hole. MEASURED both ways
                // on 2026-09-04: hidden, 5 of 5 rows unhittable; not hidden, 5 of 5 hittable.
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            }
        }
        .task(id: brush) {
            if BrushPreviewCache.shared.cached(key) != nil { return }
            let requested = brush
            let target = size
            let rendered = await Task.detached(priority: .userInitiated) {
                BrushPreviewCache.shared.image(for: requested, size: target, scale: 2, color: .white)
            }.value
            guard !Task.isCancelled, requested == brush else { return }
            image = rendered
        }
    }
}
