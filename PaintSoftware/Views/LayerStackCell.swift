import UIKit

/// One row of the layer stack: a folder header or a layer.
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

    // Invisible probes so UI tests can read per-row state that isn't rendered as text.
    private let bakedMarker = UIView()
    private let vectorMarker = UIView()
    private let folderMarker = UIView()
    /// Carries `blendMode.rawValue` — stable across localization, unlike `displayName` in the
    /// subtitle/name suffix below, which is what a test should read instead of the visible label.
    private let blendModeMarker = UIView()

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
                     bakedMarker, vectorMarker, folderMarker, blendModeMarker] {
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

        folderIconView.contentMode = .scaleAspectFit
        folderIconView.image = UIImage(systemName: "folder.fill")
        folderIconView.tintColor = .systemYellow

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

        for marker in [bakedMarker, vectorMarker, folderMarker, blendModeMarker] {
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
        // opacity gets the same slider the layer rows already have).
        opacitySliderTrailingToMarker = opacitySlider.trailingAnchor.constraint(equalTo: currentMarker.leadingAnchor, constant: -8)
        opacitySliderTrailingToOptions = opacitySlider.trailingAnchor.constraint(equalTo: folderOptionsButton.leadingAnchor, constant: -8)
        opacitySliderTrailingToMarker.isActive = true
    }

    private var guideWidth: NSLayoutConstraint!
    private var layerNameLeading: NSLayoutConstraint!
    private var folderNameLeading: NSLayoutConstraint!
    private var layerNameCenterY: NSLayoutConstraint!
    private var folderNameCenterY: NSLayoutConstraint!
    private var opacitySliderTrailingToMarker: NSLayoutConstraint!
    private var opacitySliderTrailingToOptions: NSLayoutConstraint!

    // MARK: - Configuration

    func configure(with model: LayerRowModel) {
        isFolderRow = model.isFolder
        updateGuides(depth: model.depth)

        // A layer or group set to Multiply reads identically to Normal otherwise — the row is the
        // only place an artist checks a stack at a glance, so the mode has to show without opening
        // options (§7). Appended to the name rather than laid out as its own label: `.normal` (the
        // common case) contributes nothing, so no row shifts, and `accessibilityLabel` below stays
        // the bare name — VoiceOver/XCUITest read `blendModeMarker`'s stable rawValue instead of
        // parsing this display string.
        //
        // `!= .normal` rather than `isBlending`: "Clip to Below" answers false to the second, because
        // it composites source-over and expresses itself as a mask (§7) — but it is still a pick the
        // artist made and still needs to show here, which is a question about the picker rather than
        // about the arithmetic.
        nameLabel.text = model.blendMode != .normal ? "\(model.name)  ·  \(model.blendMode.displayName)" : model.name
        nameLabel.accessibilityLabel = model.name

        visibilityButton.setImage(UIImage(systemName: model.isVisible ? "eye" : "eye.slash"), for: .normal)
        visibilityButton.tintColor = model.isVisible ? .white : .gray
        visibilityButton.accessibilityIdentifier = model.isFolder
            ? "layerPanel.folder.\(model.name).visibility" : "layerPanel.row.\(model.layerIndex).visibility"

        if model.isFolder {
            thumbnailView.isHidden = true
            folderIconView.isHidden = false
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
        } else {
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
            // `.opacity` identifier above, which would otherwise linger on a reused cell.
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
        }

        isMergeHighlighted = false
        isDropHighlighted = false
        refreshBackground()
    }

    /// Vertical guide lines, one per enclosing folder, so nesting depth reads at a glance.
    private func updateGuides(depth: Int) {
        guideWidth.constant = CGFloat(depth) * Self.indentPerLevel

        while guideLines.count < depth {
            let line = UIView()
            line.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.35)
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
        }
    }

    /// Tints both rows of a live pinch so it's clear which two are about to merge.
    func setMergeHighlight(_ on: Bool) {
        isMergeHighlighted = on
        refreshBackground()
    }

    /// Outlines the row a drag would drop *into* — a folder to move inside it, a layer to wrap the
    /// pair in a new folder.
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
    }

    // MARK: - Actions

    @objc private func toggleVisibility() { onToggleVisibility?() }
    @objc private func toggleExpanded() { onToggleExpanded?() }
    @objc private func opacityChanged() { onOpacityChange?(Double(opacitySlider.value)) }
    @objc private func opacityDragBegan() { onOpacityChangeBegan?() }
    @objc private func opacityDragEnded() { onOpacityChangeEnded?() }
    @objc private func openFolderOptions() { onOpenFolderOptions?() }
}
