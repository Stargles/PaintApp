import Combine
import Foundation

/// **The artist's on/off choices for their tools, kept across launches** — TODO (175), the owner:
/// *"switch options should be saved."* A switch turned off in the Fill panel is still off the next
/// morning, in the next drawing and after the app was killed in between.
///
/// ## Where a switch lives
///
/// `EditorState`'s rule decides it: *how this document is being looked at goes with the document; the
/// tools in the artist's hand go with the app.* A switch is here when it is a tool in the artist's hand
/// and **not** here when it describes the drawing — the universal eraser (kept in the manifest beside
/// the eraser mode), the padding's draw order, the paper's visibility, the onion skin and loop, and
/// every layer's own switches all travel with the document and are untouched by this record.
///
/// ## How a switch is kept
///
/// **One value on the manager, one place that saves it.** `CanvasManager.toolSwitches` is the only
/// storage (so a switch's default is the initial value written beside its declaration below), and
/// `ToolSwitchesKeeper` is the only thing that reads or writes `UserDefaults` for it: it hands the saved
/// switches to a manager as it enters the editor and saves each switch the artist changes after. The
/// model itself touches no defaults, so a logic test that flips a switch leaves nothing behind for the
/// next `CanvasManager()` to find.
///
/// **A key per switch, not one JSON record**, so a switch added by a later build never invalidates the
/// ones already saved — an absent key is simply that switch's default — and so a UI test can seed one
/// with a launch argument (`-paintapp.pencilOnlyDrawing YES`), which a JSON blob would not allow.
///
/// Adding a switch is its field below and its row in `saved`;
/// `ToolSwitchesLogicTests.testEverySwitchHasARowInTheSavedTable` fails when the second is forgotten.
struct ToolSwitches: Equatable {

    // MARK: - Fill

    /// Whether the canvas rectangle's edge bounds the fill the way a drawn line does. On by default,
    /// at the owner's request.
    ///
    /// **"The canvas edge" is the edge of the artwork rect — `canvasSize` inset by `canvasPadding` on
    /// every side — and not the edge of the pixel buffer.** With padding those are different
    /// rectangles, and confusing them is what made this option not work: the flood has always been
    /// clamped to the *buffer*, which is free and needs no option, but with a margin around the
    /// artwork that clamp sits `canvasPadding` px too far out and an enclosure that leans on the
    /// paper's border is open along that whole border.
    ///
    /// Two things happen when it is on, and only the first is what the artist means by the name:
    /// - the artwork rect's boundary **bounds the flood**, on both sides — a fill started on the
    ///   paper stops at the paper's edge instead of spreading onto the grey margin, and a fill
    ///   started on the margin stays there. This does not consult Gap Closing at all.
    /// - the paper's edge counts as **ink for gap closing**, so a boundary stroke ending a few px
    ///   short of it leaves an opening that seals rather than letting the fill run around its end.
    ///   This half is the one that does nothing while Gap Closing is 0.
    ///
    /// At `canvasPadding == 0` the two rectangles coincide, the flood already could not leave the
    /// buffer, and the option reduces exactly to the second half. See `gapLevels` in Fill.metal for
    /// both mechanisms and for why the boundary is a barrier between pixels rather than ink added to
    /// the wall mask.
    var fillCanvasEdgeIsBoundary = true

    /// Whether a fill grows into the gap between itself and paint already on its layer — the owner's
    /// *"have fill B smartly detect its edge is near fill A, and mend the gap"* (TODO (113)). On by
    /// default (owner, 2026-10-12): a fill that ends short of the one beside it is a defect the artist
    /// would otherwise have to remember to switch off, and the switch is still in the fill menu.
    ///
    /// How far it reaches is `fillSettings.mendReach`, its own setting. Both fill types honour it.
    var fillMendsNeighbourGap = true

    // MARK: - Select

    /// Whether painting/erasing/filling is allowed to touch pixels outside the active selection.
    /// Defaults to false (deny), matching Procreate-style selections. Shown as a switch in the
    /// Select bottom bar; only meaningful while `selection` is non-nil.
    var allowsPaintingOutsideSelection = false

    /// **TODO (95) — "Add / Subtract", in the Select panel's rule row.** Off, a new loop is added to the
    /// selection already up; on, it is taken from it. Read through `selectionComposition` in one place,
    /// `finishSelection`, so a freehand loop, a rectangle and the wand all compose the same way.
    ///
    /// A subtract drawn with nothing selected raises `CanvasNotice.nothingToSubtractFrom` rather than
    /// selecting, so a switch that was left on shows itself the first time it is used.
    var subtractsSelection = false

    // MARK: - Move

    /// **TODO item (14) — "Keep full precision" on the Move bar.** While this is on, every stroke a
    /// committed vector Move writes is marked `VectorStroke.precise`, so its samples are *stored* as
    /// float32 instead of on the quarter-pixel grid.
    ///
    /// Off by default, and that is the ruling rather than caution: the packed form is the compaction
    /// feature item (8) shipped, and the precise one costs ~1.7x the bytes a sample. It buys exactly
    /// one thing — a stroke the artist shrinks, saves, reopens and grows again comes back where it
    /// was — and only a Move can shrink one, so only a Move turns it on.
    var preserveMovePrecision = false

    /// **TODO (75) — "Keep Stroke Width" on the Move bar.** The owner: *"there should be a toggle
    /// where there is the option that the brushstroke size is constant. Right now I believe it scales
    /// with the move."* It does, by ruling — LASSO_MOVE.md §5.17's `sqrt(|det|)` — and that stays the
    /// default. While this is on, a scaled Move leaves every stroke's `VectorStroke.size` exactly what
    /// it was at the lift; `applyToVectorFloat` is the one place a Move writes geometry and the one
    /// place this is read.
    ///
    /// **A keystoned stroke is outside it, and that is the shape of the thing rather than a gap.** Under
    /// Distort a stroke's width is not one number: each dab takes its radius from the map's local scale
    /// where it lands (`StrokeDistort`, KEYFRAMES.md §8), so "unchanged" has no single width to name.
    /// The switch governs the two affine arms, which is every Move, scale, turn, Freeform and Mirror.
    var keepsStrokeWidthOnMove = false

    // MARK: - Interpolate

    /// View-level switch for `InterpolationEvaluator.Options.thicknessFade`, so the two behaviours
    /// can be compared on real drawings. Not per-recipe. Off matches the evaluator's default; the
    /// reason it is off is in `InterpolationEvaluator.ThicknessFade`.
    var interpolationThicknessFade = false

    /// Whether a keyframe's strokes are drawn in their motion groups' tag colours while interpolate
    /// mode is on.
    ///
    /// **On by default** — "what did it decide?" is the question this exists to answer, and an
    /// overlay nobody switches on answers nothing. Shows only where there is a decision to show — a
    /// drawing that grouped into one part is not tinted at all — and the switch is in the mode's
    /// options popover for the artist who wants their own colours back for a moment.
    var showMotionGroupOverlay = true

    // MARK: - Touch input

    /// Whether only the Apple Pencil draws. About the user's *hardware*, not any one drawing.
    ///
    /// Absent a saved choice this is false: an ON-by-default gate would silently swallow every finger
    /// touch on a device with no Apple Pencil, reading as "drawing is broken". Users with a Pencil who
    /// want to rest a palm switch it on, and it stays on from then on. Recorded by the action recorder
    /// like every switch, because it is the gate that decides whether a `.direct` touch draws at all —
    /// a recording showing finger touches that produce no stroke is explained entirely by this being
    /// `true` somewhere above them.
    var pencilOnlyDrawing = false
}

extension ToolSwitches {

    /// How the next selection loop meets the one already up — `subtractsSelection` as the operation
    /// `Selection.composed(with:by:)` takes.
    var selectionComposition: SelectionComposition {
        subtractsSelection ? .subtract : .add
    }
}

// MARK: - Saved

extension ToolSwitches {

    /// Every switch, by the name it is recorded under and the field it is. **The one list a new switch
    /// is added to besides its declaration**; the `UserDefaults` key is `paintapp.` and the name, which
    /// is what `pencilOnlyDrawing` has always been kept under.
    static let saved: [(name: String, field: WritableKeyPath<ToolSwitches, Bool>)] = [
        ("fillCanvasEdgeIsBoundary", \.fillCanvasEdgeIsBoundary),
        ("fillMendsNeighbourGap", \.fillMendsNeighbourGap),
        ("allowsPaintingOutsideSelection", \.allowsPaintingOutsideSelection),
        ("subtractsSelection", \.subtractsSelection),
        ("preserveMovePrecision", \.preserveMovePrecision),
        ("keepsStrokeWidthOnMove", \.keepsStrokeWidthOnMove),
        ("interpolationThicknessFade", \.interpolationThicknessFade),
        ("showMotionGroupOverlay", \.showMotionGroupOverlay),
        ("pencilOnlyDrawing", \.pencilOnlyDrawing),
    ]

    static func defaultsKey(_ name: String) -> String { "paintapp.\(name)" }

    /// The switches as the artist last left them; a switch never saved is at its default.
    static func stored(in defaults: UserDefaults = .standard) -> ToolSwitches {
        var switches = ToolSwitches()
        for (name, field) in saved where defaults.object(forKey: defaultsKey(name)) != nil {
            switches[keyPath: field] = defaults.bool(forKey: defaultsKey(name))
        }
        return switches
    }

    /// Saves the switches that differ from `previous`. **Only the ones the artist changed**: a switch
    /// never touched stays unsaved and keeps following its default, so a build that changes a default
    /// reaches everyone who had not chosen otherwise.
    func store(changesFrom previous: ToolSwitches, in defaults: UserDefaults = .standard) {
        for (name, field) in Self.saved where self[keyPath: field] != previous[keyPath: field] {
            defaults.set(self[keyPath: field], forKey: Self.defaultsKey(name))
        }
    }

    /// The launch-argument test hook, answered under `EditorPreferences.forgetIfRequested`'s own
    /// condition — `PaintUITestCase.launchIntoEditor` passes it on every launch it makes, so a test
    /// starts on the defaults whatever the test before it switched. Synchronous, in `PaintApp.init`,
    /// because the first document reads the switches as it opens.
    static func forgetIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                  defaults: UserDefaults = .standard) {
        guard EditorPreferences.forgetRequested(in: arguments) else { return }
        for (name, _) in saved { defaults.removeObject(forKey: defaultsKey(name)) }
    }
}

/// Hands the saved switches to the document in the editor and saves each change the artist makes to
/// them — the only reader and writer of `ToolSwitches`' defaults. `ContentView` holds one and calls
/// `follow` as a document enters the editor, new or reopened.
///
/// **A change is saved as it happens, not with the next document save**, because a switch flipped and
/// then the app swiped away is the case the owner reported; nothing else in the editor would have
/// written it by then.
final class ToolSwitchesKeeper {
    private let defaults: UserDefaults
    private var changes: AnyCancellable?

    /// The defaults are an argument so the logic tests hand it a suite of their own.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Puts the saved switches on `manager` and saves every change to its switches from here on,
    /// letting go of the previous document's.
    func follow(_ manager: CanvasManager) {
        var lastSeen = ToolSwitches.stored(in: defaults)
        manager.toolSwitches = lastSeen
        changes = manager.$toolSwitches
            .dropFirst()
            .sink { [defaults] switches in
                switches.store(changesFrom: lastSeen, in: defaults)
                lastSeen = switches
            }
    }
}
