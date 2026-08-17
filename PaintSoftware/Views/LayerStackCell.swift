import UIKit

/// One row of the layer stack: a layer, a group header, a compositor node header, or one of that
/// node's input slots (§4.3).
///
/// The last two are folders in storage and deliberately so — containment, spans and the ordering
/// rules reuse the group machinery untouched — which means the panel is the only place they can be
/// told apart at all, and the row is where an artist finds out that "Input A" is not a folder they
/// can delete or drag.
///
/// Laid out by hand at fixed heights. The SwiftUI version indented children by widening the row's
/// `HStack` spacing, which applied that gap between *every* control in the row rather than just at
/// the leading edge — that's where the extra space in nested rows came from. Here indentation is
/// one leading constant, and nesting is additionally drawn: a vertical guide line per enclosing
/// folder, so how deep a layer sits is readable at a glance.
final class LayerStackCell: UITableViewCell {
    static let reuseID = "LayerStackCell"
    static let layerHeight: CGFloat = 62
    static let folderHeight: CGFloat = 40

    /// Leading offset added per level of nesting.
    static let indentPerLevel: CGFloat = 18

    var onToggleVisibility: (() -> Void)?
    var onToggleExpanded: (() -> Void)?
    var onOpacityChange: ((Double) -> Void)?
    /// Bracket the whole opacity drag so it lands as one undo step rather than one per tick —
    /// see `CanvasManager.beginStructureGesture`'s doc comment.
    var onOpacityChangeBegan: (() -> Void)?
    var onOpacityChangeEnded: (() -> Void)?
    /// A folder row's tap already means expand/collapse, so its options menu (§4.2's pass-through
    /// toggle, Rename) hangs off this button instead of "tap the already-selected row again", which
    /// is how a layer row opens the same menu.
    var onOpenFolderOptions: (() -> Void)?
    /// §6.5's source pick: whether this row clips the node whose options menu is open.
    var onToggleMaskSource: (() -> Void)?
    /// §6.6's fill boundary for this row's own layer — a per-layer property rather than anything to
    /// do with the open session, shown alongside the checkmark because the two are the same question
    /// asked of the same rows.
    var onToggleFillReference: (() -> Void)?

    private let guideContainer = UIView()
    private var guideLines: [UIView] = []

    private let disclosureButton = UIButton(type: .system)
    private let visibilityButton = UIButton(type: .system)
    private let thumbnailView = UIImageView()
    private let folderIconView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let opacitySlider = UISlider()
    private let currentMarker = UIImageView()
    private let folderOptionsButton = UIButton(type: .system)
    /// §6.5's picker, as two trailing buttons that appear only while an options menu is open. They
    /// take space from the opacity slider rather than from any existing control: the session is now
    /// an ordinary state to be in, so a row has to stay a row while it is a picker.
    private let maskSourceButton = UIButton(type: .system)
    private let fillReferenceButton = UIButton(type: .system)

    // Invisible probes so UI tests can read per-row state that isn't rendered as text.
    private let bakedMarker = UIView()
    private let vectorMarker = UIView()
    private let folderMarker = UIView()
    /// Carries `blendMode.rawValue` — stable across localization, unlike `displayName` in the
    /// subtitle/name suffix below, which is what a test should read instead of the visible label.
    private let blendModeMarker = UIView()
    /// §4.3's row kind, as `"node,<mixMode>"` or `"slot,<index>"`. Which slot a row is is otherwise
    /// only readable from its position among its siblings, which is exactly the thing worth pinning.
    private let compositorMarker = UIView()
    /// §4.4's grade, as `effectMenuSlug` — set on any row applying one, layer or node. Its own probe
    /// rather than a third answer on `compositorMarker` because the two are independent facts: a
    /// value layer in effect mode can also be a node's operand, and `"input,0"` is what a test asks
    /// that row about. One probe, one question.
    private let effectMarker = UIView()

    private var contentLeading: NSLayoutConstraint!
    private var isFolderRow = false
    private var isCurrentRow = false
    private var isMergeHighlighted = false
    private var isDropHighlighted = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        buildHierarchy()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    private func buildHierarchy() {
        for view in [guideContainer, disclosureButton, visibilityButton, thumbnailView, folderIconView,
                     nameLabel, subtitleLabel, opacitySlider, currentMarker, folderOptionsButton,
                     maskSourceButton, fillReferenceButton, bakedMarker, vectorMarker, folderMarker,
                     blendModeMarker, compositorMarker, effectMarker] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        guideContainer.isUserInteractionEnabled = false

        disclosureButton.tintColor = .white
        disclosureButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)

        visibilityButton.addTarget(self, action: #selector(toggleVisibility), for: .touchUpInside)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 4
        thumbnailView.layer.borderWidth = 1
        thumbnailView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        thumbnailView.backgroundColor = .white

        // Image and tint are set per row in `configure` — a node and a slot take this same slot with
        // their own glyph, which is most of what makes them read as something other than a folder.
        folderIconView.contentMode = .scaleAspectFit

        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = .white
        nameLabel.isAccessibilityElement = true
        nameLabel.accessibilityTraits = .staticText

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .lightGray
        subtitleLabel.isAccessibilityElement = true

        opacitySlider.minimumValue = 0
        opacitySlider.maximumValue = 1
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        opacitySlider.addTarget(self, action: #selector(opacityDragBegan), for: .touchDown)
        opacitySlider.addTarget(self, action: #selector(opacityDragEnded),
                                for: [.touchUpInside, .touchUpOutside, .touchCancel])

        // Deliberately image-less: which layer is active is shown by tinting the whole row blue
        // (`setCurrentRow`), which reads at a glance where a small checkmark tucked against the
        // trailing edge did not. The view stays in the hierarchy as an accessibility probe so
        // `layerPanel.row.<n>.current` remains queryable from UI tests.
        currentMarker.contentMode = .scaleAspectFit
        currentMarker.isAccessibilityElement = true
        currentMarker.accessibilityTraits = .image

        folderOptionsButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        folderOptionsButton.tintColor = .white
        folderOptionsButton.addTarget(self, action: #selector(openFolderOptions), for: .touchUpInside)

        maskSourceButton.isHidden = true
        maskSourceButton.addTarget(self, action: #selector(toggleMaskSource), for: .touchUpInside)

        fillReferenceButton.isHidden = true
        fillReferenceButton.addTarget(self, action: #selector(toggleFillReference), for: .touchUpInside)

        for marker in [bakedMarker, vectorMarker, folderMarker, blendModeMarker, compositorMarker,
                       effectMarker] {
            marker.isAccessibilityElement = true
            marker.isUserInteractionEnabled = false
            marker.backgroundColor = .clear
        }

        contentLeading = guideContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6)
        guideWidth = guideContainer.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            contentLeading,
            guideWidth,
            guideContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            guideContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            disclosureButton.leadingAnchor.constraint(equalTo: guideContainer.trailingAnchor, constant: 2),
            disclosureButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 22),
            disclosureButton.heightAnchor.constraint(equalToConstant: 30),

            visibilityButton.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 2),
            visibilityButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            visibilityButton.widthAnchor.constraint(equalToConstant: 30),
            visibilityButton.heightAnchor.constraint(equalToConstant: 34),

            thumbnailView.leadingAnchor.constraint(equalTo: visibilityButton.trailingAnchor, constant: 6),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 44),
            thumbnailView.heightAnchor.constraint(equalToConstant: 44),

            folderIconView.leadingAnchor.constraint(equalTo: visibilityButton.trailingAnchor, constant: 6),
            folderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderIconView.widthAnchor.constraint(equalToConstant: 22),
            folderIconView.heightAnchor.constraint(equalToConstant: 22),

            opacitySlider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            opacitySlider.widthAnchor.constraint(equalToConstant: 90),

            currentMarker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            currentMarker.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            currentMarker.widthAnchor.constraint(equalToConstant: 20),
            currentMarker.heightAnchor.constraint(equalToConstant: 20),

            folderOptionsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            folderOptionsButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderOptionsButton.widthAnchor.constraint(equalToConstant: 30),
            folderOptionsButton.heightAnchor.constraint(equalToConstant: 30),

            maskSourceButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            maskSourceButton.widthAnchor.constraint(equalToConstant: 30),
            maskSourceButton.heightAnchor.constraint(equalToConstant: 34),

            // Fixed to the mask button rather than to the row, so the pair reads as one control
            // group and stays in the same column whether or not a folder row's options button is
            // pushing them inward.
            fillReferenceButton.trailingAnchor.constraint(equalTo: maskSourceButton.leadingAnchor, constant: -2),
            fillReferenceButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fillReferenceButton.widthAnchor.constraint(equalToConstant: 30),
            fillReferenceButton.heightAnchor.constraint(equalToConstant: 34),

            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: opacitySlider.leadingAnchor, constant: -8),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: opacitySlider.leadingAnchor, constant: -8),

            bakedMarker.widthAnchor.constraint(equalToConstant: 1),
            bakedMarker.heightAnchor.constraint(equalToConstant: 1),
            bakedMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bakedMarker.topAnchor.constraint(equalTo: contentView.topAnchor),

            vectorMarker.widthAnchor.constraint(equalToConstant: 1),
            vectorMarker.heightAnchor.constraint(equalToConstant: 1),
            vectorMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            vectorMarker.topAnchor.constraint(equalTo: contentView.topAnchor),

            folderMarker.widthAnchor.constraint(equalToConstant: 1),
            folderMarker.heightAnchor.constraint(equalToConstant: 1),
            folderMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            folderMarker.topAnchor.constraint(equalTo: contentView.topAnchor),

            blendModeMarker.widthAnchor.constraint(equalToConstant: 1),
            blendModeMarker.heightAnchor.constraint(equalToConstant: 1),
            blendModeMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            blendModeMarker.topAnchor.constraint(equalTo: contentView.topAnchor),

            compositorMarker.widthAnchor.constraint(equalToConstant: 1),
            compositorMarker.heightAnchor.constraint(equalToConstant: 1),
            compositorMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            compositorMarker.topAnchor.constraint(equalTo: contentView.topAnchor),

            effectMarker.widthAnchor.constraint(equalToConstant: 1),
            effectMarker.heightAnchor.constraint(equalToConstant: 1),
            effectMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            effectMarker.topAnchor.constraint(equalTo: contentView.topAnchor),
        ])

        // The name sits after the thumbnail on layer rows and after the folder icon on folder rows,
        // and rides above its subtitle only on layer rows; `configure` activates one of each pair.
        layerNameLeading = nameLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10)
        folderNameLeading = nameLabel.leadingAnchor.constraint(equalTo: folderIconView.trailingAnchor, constant: 8)
        layerNameCenterY = nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -7)
        folderNameCenterY = nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        layerNameLeading.isActive = true
        layerNameCenterY.isActive = true

        // The opacity slider ends before whichever trailing control the row has — the invisible
        // `currentMarker` probe on a layer row, `folderOptionsButton` on a folder row (§4.1's group
        // opacity gets the same slider the layer rows already have), and the picker pair while an
        // options menu is open, which is what the session costs the row: a shorter slider.
        opacitySliderTrailingToMarker = opacitySlider.trailingAnchor.constraint(equalTo: currentMarker.leadingAnchor, constant: -8)
        opacitySliderTrailingToOptions = opacitySlider.trailingAnchor.constraint(equalTo: folderOptionsButton.leadingAnchor, constant: -8)
        opacitySliderTrailingToPicker = opacitySlider.trailingAnchor.constraint(equalTo: fillReferenceButton.leadingAnchor, constant: -6)
        opacitySliderTrailingToMarker.isActive = true

        maskTrailingToEdge = maskSourceButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        maskTrailingToOptions = maskSourceButton.trailingAnchor.constraint(equalTo: folderOptionsButton.leadingAnchor, constant: -2)
    }

    private var guideWidth: NSLayoutConstraint!
    private var layerNameLeading: NSLayoutConstraint!
    private var folderNameLeading: NSLayoutConstraint!
    private var layerNameCenterY: NSLayoutConstraint!
    private var folderNameCenterY: NSLayoutConstraint!
    private var opacitySliderTrailingToMarker: NSLayoutConstraint!
    private var opacitySliderTrailingToOptions: NSLayoutConstraint!
    private var opacitySliderTrailingToPicker: NSLayoutConstraint!
    private var maskTrailingToEdge: NSLayoutConstraint!
    private var maskTrailingToOptions: NSLayoutConstraint!

    // MARK: - Configuration

    func configure(with model: LayerRowModel) {
        isFolderRow = model.isFolder
        updateGuides(depth: model.depth)

        nameLabel.text = title(for: model)
        nameLabel.accessibilityLabel = model.name

        visibilityButton.setImage(UIImage(systemName: model.isVisible ? "eye" : "eye.slash"), for: .normal)
        visibilityButton.tintColor = model.isVisible ? .white : .gray
        visibilityButton.accessibilityIdentifier = model.isFolder
            ? "layerPanel.folder.\(model.name).visibility" : "layerPanel.row.\(model.layerIndex).visibility"

        // Three kinds where this was `if model.isFolder`. The two folder kinds share their whole
        // geometry — a node is a group in storage and there is nothing to lay out differently — so
        // what the switch actually picks is the glyph and its tint.
        switch model.kind {
        case .layer:
            configureLayerRow(model)
        case .group:
            configureFolderRow(model, icon: "folder.fill", tint: .systemYellow)
        case .compositorNode:
            // Two overlapping circles: the node combines its inputs, which is the one thing about it
            // a glyph can say.
            configureFolderRow(model, icon: "camera.filters", tint: .systemTeal)
        }

        configureMaskEdit(model)

        isMergeHighlighted = false
        isDropHighlighted = false
        refreshBackground()
    }

    /// The row's visible title: its name, plus every pick that would otherwise be invisible without
    /// opening the options panel.
    ///
    /// A layer or group set to Multiply reads identically to Normal otherwise — the row is the only
    /// place an artist checks a stack at a glance, so the mode has to show here (§7). Appended to the
    /// name rather than laid out as its own label: the common case contributes nothing, so no row
    /// shifts, and `accessibilityLabel` stays the bare name — VoiceOver and XCUITest read the
    /// `blendModeMarker`/`compositorMarker` raw values instead of parsing this display string.
    ///
    /// **A Mix node's mode shows even at Normal**, unlike a layer's. It is the whole content of the
    /// node's op (§4.3), so Normal there is a pick the artist made rather than the absence of one —
    /// and a Mix node with nothing after its name would look like a node whose op had gone missing.
    ///
    /// **§4.4's grade shows for the same reason, and it is the newest thing here.** A value layer is
    /// two things chosen by one field, and both arrive under a name (`addValueLayer` calls the layer
    /// after its effect, but a rename or a mode flip parts the two immediately) — so a row reading
    /// "Value 2" while the layer is in fact a Gaussian Blur is precisely the invisible state this
    /// method exists to prevent. A node's grade is the same fact about the other wrapper, and lands
    /// where its Mix mode would: it is the whole content of what the node does.
    private func title(for model: LayerRowModel) -> String {
        var parts = [model.name]
        if let mix = model.mixMode { parts.append(mix.displayName) }
        // **Suppressed when the name already is the grade**, which is now the common case rather than
        // a coincidence: entering effect mode renames the layer or node to the effect's `displayName`
        // (`CanvasManager.setLayerEffect` / `setNodeEffect`), so appending it unconditionally produced
        // "Gaussian Blur  ·  Gaussian Blur". Compared against the *name* rather than gated on
        // `hasCustomName`, because what makes the suffix redundant is that the row already says it —
        // an artist who types "Gaussian Blur" by hand has said it too, and a suffix is not owed to
        // them for having agreed with the generator.
        if let effect = model.effect, effect.displayName != model.name { parts.append(effect.displayName) }
        // `!= .normal` rather than `isBlending`: "Clip to Below" answers false to the second, because
        // it composites source-over and expresses itself as a mask (§7) — but it is still a pick the
        // artist made and still needs to show here, which is a question about the picker rather than
        // about the arithmetic.
        if model.blendMode != .normal { parts.append(model.blendMode.displayName) }
        return parts.joined(separator: "  ·  ")
    }

    private func configureFolderRow(_ model: LayerRowModel, icon: String, tint: UIColor) {
        thumbnailView.isHidden = true
        folderIconView.isHidden = false
        folderIconView.image = UIImage(systemName: icon)
        folderIconView.tintColor = tint
        opacitySlider.isHidden = false
        currentMarker.isHidden = true
        folderOptionsButton.isHidden = false
        subtitleLabel.isHidden = true
        disclosureButton.isHidden = false
        disclosureButton.setImage(UIImage(systemName: model.isExpanded ? "chevron.down" : "chevron.right"), for: .normal)

        layerNameLeading.isActive = false
        layerNameCenterY.isActive = false
        folderNameLeading.isActive = true
        folderNameCenterY.isActive = true
        opacitySliderTrailingToMarker.isActive = false
        opacitySliderTrailingToOptions.isActive = true
        if !opacitySlider.isTracking {
            opacitySlider.value = Float(model.opacity)
        }
        opacitySlider.accessibilityIdentifier = "layerPanel.folder.\(model.name).opacity"
        setCurrentRow(false)
        nameLabel.textColor = model.isVisible ? .white : .gray
        nameLabel.accessibilityIdentifier = "layerPanel.folder.\(model.name)"
        nameLabel.accessibilityValue = "\(model.depth)"
        folderOptionsButton.accessibilityIdentifier = "layerPanel.folder.\(model.name).options"

        bakedMarker.accessibilityIdentifier = nil
        vectorMarker.accessibilityIdentifier = nil
        folderMarker.accessibilityIdentifier = nil
        subtitleLabel.accessibilityIdentifier = nil
        currentMarker.accessibilityIdentifier = nil
        blendModeMarker.accessibilityIdentifier = "layerPanel.folder.\(model.name).blendMode"
        blendModeMarker.accessibilityValue = model.blendMode.rawValue
        configureCompositorMarker(model)
        configureEffectMarker(model)
    }

    /// Overwrites whatever a recycled cell's last row left on the probe — a row that is neither a
    /// node nor an operand clears it, so a stale `input,0` can't linger on a reused cell and make an
    /// unrelated row answer as an operand.
    ///
    /// Two answers on one probe. `node,<mode>` says the row *is* a node, which nothing structural
    /// otherwise distinguishes; `input,<index>` says the row is the *n*th operand of the node it sits
    /// in, which is what the named "Input A"/"Input B" slot folders used to carry and which is
    /// otherwise only readable by comparing row frames. A node nested inside a node reports the
    /// first: what it is outranks where it sits.
    ///
    /// **`node,effect` is the third op a node can have**, and it needs saying here because it is
    /// otherwise indistinguishable from the ordinary one: `setNodeEffect` reshapes the op to `.stack`
    /// when it sets a grade, so an effect node and a bare stack node both read `compositorOp ==
    /// .stack` and this probe would report `node,stack` for both. *Which* grade is on `effectMarker`
    /// rather than appended here, so a test asking "is this a node, and of what shape" and a test
    /// asking "what grade is applied" read two values that cannot be confused for one another.
    private func configureCompositorMarker(_ model: LayerRowModel) {
        let identifier = model.isFolder
            ? "layerPanel.folder.\(model.name).compositor" : "layerPanel.row.\(model.layerIndex).compositor"
        if model.kind == .compositorNode {
            compositorMarker.accessibilityIdentifier = identifier
            let op = model.effect != nil ? "effect" : (model.mixMode?.rawValue ?? "stack")
            compositorMarker.accessibilityValue = "node,\(op)"
        } else if let input = model.nodeInputIndex {
            compositorMarker.accessibilityIdentifier = identifier
            compositorMarker.accessibilityValue = "input,\(input)"
        } else {
            compositorMarker.accessibilityIdentifier = nil
            compositorMarker.accessibilityValue = nil
        }
    }

    /// §4.4's grade as `effectMenuSlug` — the same stable spelling the picker's menu items carry, so
    /// a test that taps `layerOptions.blendMode.gaussianblur` reads `gaussianblur` back off the row
    /// rather than matching against a `displayName` that a wording change would move.
    ///
    /// Cleared, identifier and all, on a row with no grade: `configure` runs on recycled cells, and a
    /// stale identifier here would make an unrelated row answer a query about somebody else's effect
    /// — the failure `configureCompositorMarker`'s doc records for its own probe.
    private func configureEffectMarker(_ model: LayerRowModel) {
        guard let effect = model.effect else {
            effectMarker.accessibilityIdentifier = nil
            effectMarker.accessibilityValue = nil
            return
        }
        effectMarker.accessibilityIdentifier = model.isFolder
            ? "layerPanel.folder.\(model.name).effect" : "layerPanel.row.\(model.layerIndex).effect"
        effectMarker.accessibilityValue = effectMenuSlug(effect)
    }

    private func configureLayerRow(_ model: LayerRowModel) {
        thumbnailView.isHidden = false
        folderIconView.isHidden = true
        opacitySlider.isHidden = false
        subtitleLabel.isHidden = false
        disclosureButton.isHidden = true
        folderOptionsButton.isHidden = true

        folderNameLeading.isActive = false
        folderNameCenterY.isActive = false
        layerNameLeading.isActive = true
        layerNameCenterY.isActive = true
        opacitySliderTrailingToOptions.isActive = false
        opacitySliderTrailingToMarker.isActive = true
        nameLabel.textColor = .white

        thumbnailView.image = model.thumbnail
        thumbnailView.backgroundColor = model.thumbnail == nil ? .white : .clear
        thumbnailView.alpha = CGFloat(model.opacity)

        if !opacitySlider.isTracking {
            opacitySlider.value = Float(model.opacity)
        }
        // Overwrites whatever a recycled cell's last row left here — including a folder row's
        // `.opacity` identifier, which would otherwise linger on a reused cell.
        opacitySlider.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).opacity"
        currentMarker.isHidden = !model.isCurrent
        currentMarker.isAccessibilityElement = model.isCurrent
        setCurrentRow(model.isCurrent)

        subtitleLabel.text = model.isFillReference ? "Fill Reference" : "Fill Excluded"

        nameLabel.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex)"
        nameLabel.accessibilityValue = "\(model.strokeCount)"
        subtitleLabel.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).fillRef"
        subtitleLabel.accessibilityValue = model.isFillReference ? "1" : "0"
        currentMarker.accessibilityIdentifier = model.isCurrent ? "layerPanel.row.\(model.layerIndex).current" : nil
        bakedMarker.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).hasBaked"
        bakedMarker.accessibilityValue = model.hasBakedImage ? "1" : "0"
        vectorMarker.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).vector"
        vectorMarker.accessibilityValue = "\(model.isVector ? 1 : 0),\(model.vectorStrokeCount),\(model.vectorEraseCount)"
        folderMarker.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).folder"
        folderMarker.accessibilityValue = model.folderName ?? ""
        blendModeMarker.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).blendMode"
        blendModeMarker.accessibilityValue = model.blendMode.rawValue
        configureCompositorMarker(model)
        configureEffectMarker(model)
    }

    /// §6.5's picker chrome: the mask checkmark and the fill-reference button, added to the row for
    /// as long as some node's options menu is open.
    ///
    /// **Added, not substituted.** The old flow could take the row over entirely — it was reached by
    /// a deliberate switch and the panel had a Mask Sources header to say so. The session is now the
    /// ordinary state of having a menu open, so the eye, the thumbnail, the opacity slider and the
    /// options button all stay live; the two buttons take their space out of the slider. The dim that
    /// marks an illegal source moved onto the checkmark alone for the same reason: fading the whole
    /// row would fade a fill-reference button that has nothing to do with cycles.
    private func configureMaskEdit(_ model: LayerRowModel) {
        maskSourceButton.isHidden = !model.showsMaskControl
        fillReferenceButton.isHidden = !model.showsFillReferenceControl

        // Deactivate before activating, always: two live trailing constraints on the same view are
        // an unsatisfiable pair, and Auto Layout resolves that by dropping one of its choosing.
        opacitySliderTrailingToPicker.isActive = false
        maskTrailingToEdge.isActive = false
        maskTrailingToOptions.isActive = false
        guard model.showsMaskControl || model.showsFillReferenceControl else { return }

        opacitySliderTrailingToMarker.isActive = false
        opacitySliderTrailingToOptions.isActive = false
        opacitySliderTrailingToPicker.isActive = true
        // A folder row keeps its options button, so the pair sits inboard of it; a layer row has
        // nothing there but the invisible `currentMarker` probe, so they go to the edge.
        if model.isFolder {
            maskTrailingToOptions.isActive = true
        } else {
            maskTrailingToEdge.isActive = true
        }

        if model.isMaskEditTarget {
            // Fails `canMask` the same way any self-mask does, but "this is what you're editing"
            // reads differently than "this would cycle" — a distinct glyph says which one it is.
            maskSourceButton.setImage(UIImage(systemName: "pencil.circle.fill"), for: .normal)
            maskSourceButton.tintColor = .white
        } else if model.isMaskSourceSelected {
            maskSourceButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
            maskSourceButton.tintColor = .systemBlue
        } else {
            maskSourceButton.setImage(UIImage(systemName: "circle"), for: .normal)
            maskSourceButton.tintColor = UIColor.white.withAlphaComponent(0.4)
        }
        // A cyclic pick is never offered (§6.2) — dimmed and inert rather than hidden, so the stack's
        // shape stays legible while a pick is in progress. The node under edit reads the same way for
        // the same underlying reason (it fails `canMask` too) but at a lighter dim, so the two don't
        // look identical.
        maskSourceButton.isEnabled = model.isMaskEligible
        maskSourceButton.alpha = model.isMaskEligible ? 1 : (model.isMaskEditTarget ? 0.55 : 0.3)
        maskSourceButton.accessibilityIdentifier = model.isFolder
            ? "layerPanel.folder.\(model.name).maskSource" : "layerPanel.row.\(model.layerIndex).maskSource"
        maskSourceButton.accessibilityValue = model.isMaskSourceSelected ? "1" : "0"

        guard model.showsFillReferenceControl else {
            // A folder row keeps the gutter — the pair stays in one column across kinds — but must
            // not keep a recycled layer row's identifier on a button it is not showing.
            fillReferenceButton.accessibilityIdentifier = nil
            return
        }
        // A drop, because what this bounds is the fill tool's flood. Filled and orange when the layer
        // walls the fill in, hollow when it does not — and the glyph says nothing about *why*, since
        // §6.6 makes "defaulted off because hidden" and "switched off by hand" the same picture on
        // purpose: what the fill will do is the artist's question, not which of the two produced it.
        fillReferenceButton.setImage(UIImage(systemName: model.isFillReference ? "drop.fill" : "drop"), for: .normal)
        fillReferenceButton.tintColor = model.isFillReference ? .systemOrange : UIColor.white.withAlphaComponent(0.4)
        fillReferenceButton.accessibilityIdentifier = "layerPanel.row.\(model.layerIndex).fillRefButton"
        fillReferenceButton.accessibilityValue = model.isFillReference ? "1" : "0"
    }

    /// A guide line for a container the row already sits in. Faint on purpose: it is standing
    /// structure, and at full strength a deep stack reads as a barcode.
    private static let restingGuideColor = UIColor.systemYellow.withAlphaComponent(0.35)
    /// A guide line for a container the row is *about to* be dropped into — the owner's request,
    /// verbatim: "having that orange vertical line appear in the group to signal the tree structure
    /// when the layer is hovering". Orange rather than a brighter yellow, and near-opaque rather than
    /// at 0.35, because it has to answer a different question from every other line on screen:
    /// "where this is going" against "where things already are". A stronger yellow would read as one
    /// more resting guide that happened to be nearer the eye.
    private static let pendingGuideColor = UIColor.systemOrange.withAlphaComponent(0.95)

    /// Vertical guide lines, one per enclosing folder, so nesting depth reads at a glance.
    ///
    /// `pendingLevel` marks one of them as a container the row has not entered yet — see
    /// `applyDropPreview`, which is the only caller that passes it. The colour is reassigned on every
    /// call rather than only when it changes, because the line views are pooled and reused: a cell
    /// that once rendered a pending guide would otherwise keep it orange for every row it is
    /// recycled into.
    private func updateGuides(depth: Int, pendingLevel: Int? = nil) {
        guideWidth.constant = CGFloat(depth) * Self.indentPerLevel

        while guideLines.count < depth {
            let line = UIView()
            line.translatesAutoresizingMaskIntoConstraints = false
            guideContainer.addSubview(line)
            NSLayoutConstraint.activate([
                line.widthAnchor.constraint(equalToConstant: 1.5),
                line.topAnchor.constraint(equalTo: guideContainer.topAnchor),
                line.bottomAnchor.constraint(equalTo: guideContainer.bottomAnchor),
                line.leadingAnchor.constraint(equalTo: guideContainer.leadingAnchor,
                                              constant: CGFloat(guideLines.count) * Self.indentPerLevel + 7)
            ])
            guideLines.append(line)
        }
        for (index, line) in guideLines.enumerated() {
            line.isHidden = index >= depth
            let isPending = index == pendingLevel
            line.backgroundColor = isPending ? Self.pendingGuideColor : Self.restingGuideColor
            // The pending line is drawn thicker as well as differently coloured. Colour alone is the
            // one channel an artist may not have — this app has no colour-blind mode, and orange
            // against yellow is the pair that goes first — so the signal is carried twice.
            line.transform = isPending ? CGAffineTransform(scaleX: 2, y: 1) : .identity
        }
    }

    /// Re-draws this cell's indentation and guides at a depth its row model does **not** have — the
    /// drag proxy's whole reason for being a real `LayerStackCell` rather than a bitmap.
    ///
    /// The owner asked for the hover to mirror the drop: "the look when hovering should mirror the
    /// look when it is let go". The only way to guarantee that literally is for the same code to draw
    /// both, which is what this buys — the proxy under the finger is a cell configured from the
    /// dragged row's own `LayerRowModel`, indented by `updateGuides` exactly as the settled row will
    /// be, rather than a second renderer kept in step with this one by hand.
    ///
    /// **Only ever called on the proxy**, never on a cell the table owns. A live cell's depth comes
    /// from its row model through `configure(with:)`, and a transient override applied to one would
    /// survive into whatever row the cell was next recycled for — the compounding one-slot-off class
    /// of bug `LayerStackListView.handleReorderDrag`'s `.ended` case records for preview transforms.
    func applyDropPreview(depth: Int, isNesting: Bool) {
        updateGuides(depth: depth, pendingLevel: isNesting && depth > 0 ? depth - 1 : nil)
        layoutIfNeeded()
    }

    /// Tints both rows of a live pinch so it's clear which two are about to merge.
    func setMergeHighlight(_ on: Bool) {
        isMergeHighlighted = on
        refreshBackground()
    }

    /// Outlines the row a drag would drop *into*. Folders and compositor nodes only now: dropping a
    /// layer squarely onto another layer used to wrap the pair in a new folder, and no longer does
    /// (see `LayerStackListView.dropOnto`), so a plain layer row is never a drop target and never
    /// gets this outline.
    func setDropHighlight(_ on: Bool) {
        isDropHighlighted = on
        refreshBackground()
    }

    /// The active layer, shown as a filled blue row.
    private func setCurrentRow(_ on: Bool) {
        isCurrentRow = on
        refreshBackground()
    }

    /// All three row states paint the same surface, so they're resolved in one place with a fixed
    /// precedence — a transient drag/pinch state has to win over the standing selection tint, or the
    /// row you are dropping onto stops being distinguishable while it happens to be the active one.
    private func refreshBackground() {
        let fill: UIColor
        if isDropHighlighted {
            fill = UIColor.systemBlue.withAlphaComponent(0.18)
        } else if isMergeHighlighted {
            fill = UIColor.systemBlue.withAlphaComponent(0.28)
        } else if isCurrentRow {
            fill = UIColor.systemBlue.withAlphaComponent(0.32)
        } else {
            fill = .clear
        }
        contentView.backgroundColor = fill
        contentView.layer.borderWidth = isDropHighlighted ? 2 : 0
        contentView.layer.borderColor = UIColor.systemBlue.cgColor
        contentView.layer.cornerRadius = (isDropHighlighted || isCurrentRow) ? 8 : 0
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A reorder drag leaves preview translations on the cells it shifted; a cell recycled while
        // one is still applied would otherwise render its new row at the old row's offset.
        transform = .identity
        // The lifted row is hidden outright for as long as the drag lasts (`handleReorderDrag`),
        // and a cell recycled while hidden — the table is free to do that the moment the row scrolls
        // out — would come back as an invisible row somewhere else entirely.
        contentView.isHidden = false
    }

    // MARK: - Actions

    @objc private func toggleVisibility() { onToggleVisibility?() }
    @objc private func toggleExpanded() { onToggleExpanded?() }
    @objc private func opacityChanged() { onOpacityChange?(Double(opacitySlider.value)) }
    @objc private func opacityDragBegan() { onOpacityChangeBegan?() }
    @objc private func opacityDragEnded() { onOpacityChangeEnded?() }
    @objc private func openFolderOptions() { onOpenFolderOptions?() }
    @objc private func toggleMaskSource() { onToggleMaskSource?() }
    @objc private func toggleFillReference() { onToggleFillReference?() }
}
