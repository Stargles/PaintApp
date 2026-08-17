import Foundation

/// What kind of thing one `UndoHistory.Action` represents, in the artist's own words rather than
/// the function that recorded it.
///
/// **A case per action, not a `String`.** Every undo/redo registration site already carried a
/// `name`/`actionName` string (`"Merge Layers"`, `"Stroke"`, ...) — that was enough to label a step
/// for a human reading code, but it is not enough to *guarantee* one: a `String` parameter can be
/// mistyped, reused for the wrong action, or simply left off a new call site with a default, and
/// nothing catches it. Replacing that parameter's type with this enum everywhere it was threaded
/// (`CanvasManager.recordUndo`, `withStructureUndo`, `commitStructureGesture`,
/// `withInterpolationUndo`, and the handful of private `register*Undo` helpers) turns every one of
/// those old string literals into a compile error until it names a case here — which is what made
/// this file's case list a reliable inventory of every registration site in the app rather than a
/// guess at one. Adding a new mutating action and forgetting to give it a label is now a build
/// failure, not a banner that silently reads "Undid something".
///
/// `phrase` below is the other half: an exhaustive `switch` with no `default:`, so a case added
/// here without a phrase is *also* a build failure. `HistoryNoticeLogicTests` asserts every case's
/// phrase is non-empty and free of placeholder text, which is the test that would have caught a
/// missed registration site before this existed.
enum HistoryActionLabel: CaseIterable, Equatable {

    // MARK: Pixel/vector content edits

    /// A brush stroke, on a raster or vector layer. Named apart from `.erase` even though both are
    /// the same drag-a-brush gesture (`StrokeCanvasView`'s `isEraser` is the only difference) — an
    /// artist who erased something undone as "brush stroke" would read the banner as wrong.
    case brushStroke
    case erase
    case shape
    case fill
    case clearSelection
    /// Baking a floating Move piece into its target cel.
    case move
    /// Baking a floating Duplicate piece — distinct from `.duplicateLayer`/`.duplicateFrame`/
    /// `.duplicateGuide`, which duplicate a different kind of thing entirely.
    case duplicatePiece
    case insertImage

    // MARK: Layer/folder structure

    case addLayer
    case addVectorLayer
    case addValueLayer
    case addEffectLayer
    /// A value layer's flat colour changing (`setLayerFill`).
    case valueLayerColor
    /// A value layer's grade changing, including the live drag of one of its parameters
    /// (`setLayerEffect`, and the panel's `commitStructureGesture(label: .valueLayerEffect)`).
    case valueLayerEffect
    case renameLayer
    case deleteLayer
    case fillReference
    /// A layer's or a folder's eye toggle.
    case toggleVisibility
    case isolateGroup
    case passThrough
    /// A layer's or a folder's blend mode.
    case blendMode
    case mixMode
    case clearEffect
    case mask
    case addFolder
    case addNode
    case deleteFolder
    case renameFolder
    case rasterize
    case reorderLayer
    case reorderFolder
    case groupLayers
    case mergeLayers
    case duplicateLayer
    case transform
    case opacity

    // MARK: Cel timeline

    case shuffleFrame
    case moveFrameToLayer
    case addFrame
    case duplicateFrame
    case pasteFrame
    case deleteFrame
    case extendFrame
    case clearFrame
    case splitFrame
    case moveFrame
    case resizeFrame

    // MARK: View presets

    case addView
    case switchView
    case deleteView

    // MARK: Interpolation (motion groups, guides, in-betweens)

    case addMotionGroup
    case changeGroupMode
    case deleteMotionGroup
    case clearMotionGroupTag
    case tagMotionGroup
    case tagByStrokeColour
    case interpolate
    case removeInterpolation
    case adjustTiming
    case eraseAtInBetween
    case drawAtInBetween
    case reproject
    case commitInterpolation
    case addGuide
    case editGuide
    case linkGuide
    case duplicateGuide
    case adjustSpacing
    case deleteGuide

    /// The artist-facing phrase for this action, lowercase and short enough to follow "Undid "/
    /// "Redid " without sounding like a log line — see `CanvasNotice.Kind.historyUndo`/`.historyRedo`.
    ///
    /// Exhaustive, deliberately: a case added above with no arm here fails to build rather than
    /// falling through to a placeholder, which is the whole point of this type existing.
    var phrase: String {
        switch self {
        case .brushStroke: return "brush stroke"
        case .erase: return "erase"
        case .shape: return "shape"
        case .fill: return "fill"
        case .clearSelection: return "clear selection"
        case .move: return "move"
        case .duplicatePiece: return "duplicate"
        case .insertImage: return "insert image"

        case .addLayer: return "add layer"
        case .addVectorLayer: return "add vector layer"
        case .addValueLayer: return "add value layer"
        case .addEffectLayer: return "add effect layer"
        case .valueLayerColor: return "change layer colour"
        case .valueLayerEffect: return "adjust layer effect"
        case .renameLayer: return "rename layer"
        case .deleteLayer: return "delete layer"
        case .fillReference: return "fill reference"
        case .toggleVisibility: return "toggle visibility"
        case .isolateGroup: return "isolate group"
        case .passThrough: return "pass through"
        case .blendMode: return "change blend mode"
        case .mixMode: return "change mix mode"
        case .clearEffect: return "clear effect"
        case .mask: return "edit mask"
        case .addFolder: return "add folder"
        case .addNode: return "add mix node"
        case .deleteFolder: return "delete folder"
        case .renameFolder: return "rename folder"
        case .rasterize: return "rasterize layer"
        case .reorderLayer: return "reorder layer"
        case .reorderFolder: return "reorder folder"
        case .groupLayers: return "group layers"
        case .mergeLayers: return "merge layers"
        case .duplicateLayer: return "duplicate layer"
        case .transform: return "transform"
        case .opacity: return "change opacity"

        case .shuffleFrame: return "reorder frame"
        case .moveFrameToLayer: return "move frame to layer"
        case .addFrame: return "add frame"
        case .duplicateFrame: return "duplicate frame"
        case .pasteFrame: return "paste frame"
        case .deleteFrame: return "delete frame"
        case .extendFrame: return "extend frame"
        case .clearFrame: return "clear frame"
        case .splitFrame: return "split frame"
        case .moveFrame: return "move frame"
        case .resizeFrame: return "resize frame"

        case .addView: return "add view"
        case .switchView: return "switch view"
        case .deleteView: return "delete view"

        case .addMotionGroup: return "add motion group"
        case .changeGroupMode: return "change group mode"
        case .deleteMotionGroup: return "delete motion group"
        case .clearMotionGroupTag: return "clear motion group tag"
        case .tagMotionGroup: return "tag motion group"
        case .tagByStrokeColour: return "tag by stroke colour"
        case .interpolate: return "interpolate"
        case .removeInterpolation: return "remove interpolation"
        case .adjustTiming: return "adjust timing"
        case .eraseAtInBetween: return "erase at in-between"
        case .drawAtInBetween: return "draw at in-between"
        case .reproject: return "reproject"
        case .commitInterpolation: return "commit interpolation"
        case .addGuide: return "add guide"
        case .editGuide: return "edit guide"
        case .linkGuide: return "link guide"
        case .duplicateGuide: return "duplicate guide"
        case .adjustSpacing: return "adjust spacing"
        case .deleteGuide: return "delete guide"
        }
    }
}
