import Foundation

/// `CaseIterable` exists for `ToolLogicTests`, which walks every case and asserts its
/// `paintsOnCanvas` answer is *stated* rather than inherited. See that property for why the
/// enumeration is the point.
enum Tool: Hashable, CaseIterable {
    case pen
    case pencil
    case eraser
    case fill
    /// Tap the canvas to take the colour under the tap as the brush colour. A *tool* rather than a
    /// swatch that opens a picker — the owner's wording, 2026-08-17.
    ///
    /// **It is momentary: picking reverts to whichever tool was selected before it.** See
    /// `CanvasManager.selectEyedropper`. Unlike every other case here, the artist reaches for this one
    /// in the middle of doing something else — they want a colour *so that* they can carry on
    /// painting with it, and the pick is complete in a single tap with nothing left to adjust. Left
    /// selected, the next canvas touch would re-pick instead of paint, which is never what the tap
    /// was for.
    case eyedropper

    /// Place and edit a live text object on the canvas. Entered from the Actions menu's "Add Text"
    /// row rather than from a toolbar icon — see `ActionsMenu` — because the toolbar's seven slots
    /// are spoken for and text is reached once per drawing, not once per stroke.
    ///
    /// **Inert as of this commit**: the mode can be entered and left, and nothing yet happens on a
    /// canvas touch. `ADD_TEXT.md` stage 1 is what fills it in; this case exists first and alone so
    /// the shared plumbing it needs (`ActivePanel.text`, the `activePanel` binding into
    /// `ActionsMenu`) lands where it can be bisected to.
    case text
}

extension Tool {
    /// Whether a canvas touch made with this tool selected belongs to the active layer's own
    /// drawing surface. `CanvasView.reconcileLayers`' `shouldInteract` is the caller of record: it
    /// is what decides whether that layer's host view — and the `StrokeGestureRecognizer` inside it
    /// — accepts touches at all, and `false` here is what lets the touch fall through to the
    /// container, where the tool's own recognizer is waiting. `handleCatchAllTap` asks the same
    /// question for the other half of that arrangement.
    ///
    /// **`false` does not mean "does nothing on the canvas".** Both false cases act on a canvas
    /// touch; they act on it through a `TouchTypePressRecognizer` mounted on the *container*
    /// (`fillTapRecognizer`, `eyedropperTapRecognizer`), and the active layer declining the touch is
    /// a precondition for theirs ever seeing it — the host fully covers the container, so an
    /// interactive one swallows the touch via `UIView`'s default hit-test. The question is "whose
    /// recognizer is this touch for", not "does anything happen".
    ///
    /// **Exhaustive, with no `default:`, and that is the whole reason it is a property rather than a
    /// list of exclusions written into the predicate.** It was a list, spelled `selectedTool !=
    /// .fill`, and adding `.eyedropper` to the enum did not add it to the list: the owner reported
    /// on 2026-08-17 that the eyedropper picked the colour *and* painted a stroke with the same tap,
    /// because the host stayed interactive and the touch reached both recognizers. A tool added
    /// after this cannot repeat that — it will not compile until it says which side it is on.
    var paintsOnCanvas: Bool {
        switch self {
        case .pen, .pencil, .eraser:
            // The eraser included: it is a stroke like any other, `.destinationOut` on a raster
            // layer and a real gesture on a vector one, and it goes through the same recognizer.
            return true
        case .fill, .eyedropper, .text:
            // Text sits with the fill, not with the brushes, and the smart shapes are the reason
            // the answer is not obvious. A shape *is* a brush stroke — it comes out of holding a
            // pen/pencil stroke still (`CanvasView.startShapeDetection`, gated on `.pen`/`.pencil`),
            // so its touch has to reach the layer host or there is no stroke to snap. Text's touch
            // never becomes a stroke: it places a box for an overlay that lives above the layers
            // (`ADD_TEXT.md` §1, "the overlay is the editor"), so the host must decline it exactly
            // as it declines the fill's, or the same touch would paint a stroke *and* start a text
            // box — the eyedropper's bug with a different tool's name on it.
            //
            // The other half of `false` follows and is wanted: `handleCatchAllTap` returns early
            // for a tool that does not paint, so a text-mode tap raises no "why did my finger not
            // draw" banner. It is not owed one; nothing about the tap was a drawing attempt.
            return false
        }
    }
}

extension Tool {
    /// Whether picking a *paint-brush preset* should also make that brush's tool the active tool.
    ///
    /// **The third hand-maintained exclusion list in this file's history, and it is here for the
    /// same reason the other two are.** `CanvasManager.selectBrush` spelled it
    /// `selectedTool != .eraser && selectedTool != .fill`, written when those were the only two
    /// tools it had to stand clear of. `.eyedropper` and `.text` were both added to the enum
    /// afterwards and neither was added to the list, so a preset tap in either mode silently
    /// retargeted `selectedTool` at `.pen`/`.pencil` — exactly the shape `paintsOnCanvas` above
    /// exists to prevent, and exactly the shape that shipped the eyedropper painting a stroke with
    /// every pick. An exhaustive `switch` with no `default:` means the next tool cannot compile
    /// without answering.
    ///
    /// **`.text` is the answer that matters, and it is about stranded state rather than tidiness.**
    /// Leaving text mode has to run `commitAllInteractiveState()` — that is the whole of
    /// `CanvasManager.enterTextMode`'s doc comment, from the other side — and `selectBrush` runs
    /// none. A `true` here would take `selectedTool` off `.text` while `textGestureActive` stayed
    /// true, which leaves `TextOverlayView` on screen claiming touches in its `hitTest` while
    /// `activeHostIsInteractive` has just gone true underneath it. That pair is
    /// `CanvasTouchInputs.transformDependencyIsUnresolvable`: pan/pinch/rotate then wait on a stroke
    /// recognizer that receives nothing, which is the dead-canvas symptom, and it is why this is a
    /// `false` rather than a "commit first".
    ///
    /// **No reachable UI path is known to reach the bad state today** (`BrushSettingsPanel` is the
    /// only caller and needs `activePanel == .brush`, which `TopToolbar.selectBrushToolAndTogglePanel`
    /// only ever reaches from `.pen`/`.pencil`, having committed on the way). So this is a latent
    /// hazard closed structurally, not a reported defect repaired — see `ToolLogicTests`.
    var followsBrushPresetSelection: Bool {
        switch self {
        case .pen, .pencil:
            // The preset *is* this tool's preset. Following it is what makes picking "Pencil" in the
            // brush panel switch to the pencil, which is the feature.
            return true
        case .eraser:
            // The eraser keeps its own preset (`selectedEraserBrush`) entirely separate, so a tap in
            // the paint-brush panel while erasing must not silently put the artist back to painting.
            // The original rule, unchanged.
            return false
        case .fill, .eyedropper, .text:
            // None of the three is a stroke tool, so none of them has a brush preset to follow — and
            // all three carry state that only their own exit path settles: the fill's interactive
            // gesture, the eyedropper's `toolBeforeEyedropper` memory, and the live text session.
            // Retargeting `selectedTool` from underneath any of them strands that state.
            return false
        }
    }

    /// Whether this tool is a momentary detour rather than the artist's ongoing choice — true only
    /// for `.eyedropper`, which `Tool.eyedropper`'s own doc comment already calls out: "picking
    /// reverts to whichever tool was selected before it." Consulted by `CanvasManager.selectedTool`'s
    /// `didSet`, which closes an engaged whole-layer vector Move (`isVectorTransforming`) on a tool
    /// switch — see that property's own doc comment for the fix and the report it closes.
    ///
    /// **`false` would end the Move twice over a single colour pick, and neither end is obviously
    /// safe to skip.** `selectEyedropper`/`leaveEyedropper` both write `selectedTool` — arming the
    /// pick and returning from it — so a blanket "any tool switch ends Move" rule fires on both
    /// halves of one motion the artist experiences as a single tap, not two tool changes. And it
    /// would be layering a second close on top of a mechanism that already exists:
    /// `CanvasTouchOwner.contenders(in:)` appends `.eyedropper` **before** `.moveBoxCommit`, so a tap
    /// that both picks a colour and lands away from the box is *already* owned by the pick — the box
    /// was never going to auto-commit from that touch. Closing the flag here on top of that would be
    /// a behaviour nobody asked for: engage a whole-layer Move, tap the eyedropper to sample a
    /// colour, and the box disappears with a transform committed and an undo step pushed — reported
    /// from the far side as "my move box keeps disappearing."
    ///
    /// **This property is only the entering half.** `selectedTool.isMomentary` alone tells the
    /// `didSet` to stand down when the tool being *armed* is the eyedropper, but it cannot tell the
    /// `didSet` what to do when the tool being *left* is — `.eyedropper` is not itself momentary
    /// going out, and a bare `oldValue == .eyedropper` catches a genuine tool pick made while the
    /// eyedropper merely happened to be armed, which must still end the Move
    /// (`testSwitchingToARealToolStillEndsAnEngagedWholeLayerMoveWhileTheEyedropperIsArmed` is what
    /// caught the first, wrong attempt at this). The `didSet` tells the two apart with
    /// `toolBeforeEyedropper` instead, which is instance state this property cannot see — see its own
    /// comment there for the mechanism.
    ///
    /// **`.text` stays `false` here even though the same arbitration protects its placement tap**
    /// (`.textPress` also precedes `.moveBoxCommit`), and that is a real decision rather than an
    /// oversight: unlike the eyedropper's single tap, text opens a session that outlives it —
    /// typing, dragging the box, editing — so leaving the Move box up for the session's whole
    /// duration risks the same class of two-live-mechanisms hazard `followsBrushPresetSelection`
    /// above is about, and inserting new geometry into a layer with a live uncommitted transform is
    /// exactly the shape of the open defects `LAYER_TRANSFORM.md` already carries. Text is safer
    /// entered onto a settled layer, so it is treated as a real tool switch and ends the Move.
    ///
    /// **Exhaustive, no `default:`, for the reason every such property in this file is:** a tool
    /// added later has to say whether selecting it is a momentary detour or an ongoing choice rather
    /// than silently inheriting one answer or the other.
    var isMomentary: Bool {
        switch self {
        case .eyedropper:
            return true
        case .pen, .pencil, .eraser, .fill, .text:
            return false
        }
    }

    /// Why the text tool cannot be used on the active layer, or nil when it can.
    ///
    /// **Driven by the layer's kind, not by a list of layers text is banned from.** Same defect
    /// shape as the exclusion `paintsOnCanvas` above replaced: a hand-maintained list is a list that
    /// a later `LayerKind` does not get added to. The `switch` has no `default:`, so a fourth kind
    /// has to state whether text may land on it before this compiles.
    ///
    /// Phrased as a *reason* rather than a `Bool` because the row it drives is disabled rather than
    /// hidden, and a control that is visibly there and will not respond has to say why.
    ///
    /// **The `.vector` arm returned a "not available yet" string until `ADD_TEXT.md` stage 3, and
    /// deleting it was the whole of that stage's UI change.** Stage 1 shipped raster-only and
    /// "shipped nothing it would have to un-ship"; this is the un-shipping it planned for. On a
    /// vector layer text now stays a real, re-editable element in the display list instead of baking
    /// to pixels — see `CanvasManager.commitInteractiveText`.
    static func textUnavailableReason(onLayerOfKind kind: LayerKind?) -> String? {
        switch kind {
        case .raster, .vector:
            return nil
        case .value:
            // Neither mode of `.value` — the grade wrapper nor the flat colour — has a drawing
            // surface for the bake to land in (`LayerKind`, `Layer.hasNoDrawingSurface`). This is
            // not a "yet": text on a layer that holds no pixels has nothing to mean.
            return "A value layer holds no pixels for text to land in. Add it on a raster or vector layer."
        case nil:
            // `activeLayerKind` is legitimately nil mid-edit — `deleteLayer` parks the index at -1
            // while it removes the active layer — as well as on a document with no layers at all.
            return "Select a layer to add text to."
        }
    }
}

/// The two ways the fill tool can decide *what* to fill. A type option under the one tool, the way
/// `VectorEraserMode` is under the eraser, rather than a second entry in the toolbar.
///
/// Lives here rather than in `Engine/` for the same reason `VectorEraserMode` does: it is a tool
/// setting owned by `CanvasManager` and pushed down to the views, not an engine concept.
enum FillMode: String, Codable, CaseIterable, Identifiable {
    /// Tap a point; the region around it floods outward and stops at every boundary it meets.
    /// `MetalFillEngine` and the Gap Closing / Threshold / Edge Overlap settings are all this mode's.
    case flood

    /// Draw a loop. **The loop is a fence and ink is a wall: whatever inside the fence the fence
    /// cannot walk to is filled solid, lines and all — and nothing else is touched.** So the colour
    /// lands inside the shapes the loop contains, not on the paper between the loop and the drawing,
    /// and never on the loop itself. Modelled on Krita's *Enclose and Fill* and Clip Studio Paint's
    /// closed-area fill; LASSO_FILL.md is the specification, §3 the rule in one paragraph.
    ///
    /// That is what makes it a different tool rather than a shortcut for the flood: an ordinary fill
    /// stops at every line it meets, and this one paints over every line *inside* the loop while
    /// treating the loop as an absolute boundary. Filling a dozen small compartments separated by
    /// hatching is one gesture instead of a dozen taps, and a face's eyes fill with the face.
    ///
    /// **What it commits lands on top of everything already on the layer** — earlier fills and that
    /// layer's own ink alike, so the same place can be filled over and over. LASSO_FILL.md §2a is the
    /// owner's ruling and `commitInteractiveFill` is where both layer kinds implement it. That is a
    /// property of every fill, not of this mode; it is stated here because it is what makes "paints
    /// over every line inside the loop" true on screen and not merely true of the region.
    ///
    /// **It is not the flood with a bigger seed, and the settings do not all carry over.** Gap
    /// closing and Threshold act on the collar that decides what is *held out*. Edge Overlap is live
    /// here too, but it is anchored differently, because the two fills end on opposite sides of the
    /// artist's line: the bucket stops inside the line and grows under it, while this one already
    /// covers the line and reaches its outer edge. So on the lasso the slider's **top** is that outer
    /// edge and lowering it tucks the colour further underneath — no setting paints on clean paper.
    /// `CanvasManager.fillEdgeRadius(lasso:)` is the mapping and holds the owner's ruling; see
    /// `CanvasManager.beginInteractiveLassoFill` for the mechanism, and for the cases — blank paper,
    /// a gap wider than Gap Closing — where it deliberately fills nothing and says so.
    case lasso

    var id: String { rawValue }

    /// Label for the segmented control at the top of `FillSettingsPanel`.
    var displayName: String {
        switch self {
        case .flood: return "Flood"
        case .lasso: return "Lasso"
        }
    }
}

/// How the eraser behaves on a `.vector` layer. Modelled on Clip Studio Paint's three vector-eraser
/// modes. Raster layers ignore this entirely — there the eraser stays a `.destinationOut` brush.
///
/// Lives here rather than in `Engine/` because it is a *tool* setting owned by `CanvasManager`,
/// persisted in `ProjectManifest`, and pushed into `StrokeCanvasView` alongside `isEraser`.
enum VectorEraserMode: String, Codable, CaseIterable, Identifiable {
    /// Mode 1 — *erase touched parts*. Indistinguishable from raster erasing: partial-width shaves,
    /// soft edges and `< 1` opacity all reproduce. Retains the eraser's gesture whole as an
    /// `.erase` punch, then removes geometry the punch was going to hide anyway: a stroke covered
    /// end to end is deleted outright; one covered full-width over a stretch is cut into pieces
    /// that keep rendering on the original's dab lattice (`DabLattice` — cutting was unsafe before
    /// that type existed, since a re-stamped piece re-anchors `BrushStamper`'s dab lattice and
    /// lands ink outside the punch). `RasterVectorParityLogicTests` proves the punch is
    /// byte-identical to raster erasing.
    case erase

    /// Mode 2 — deletes the stroke geometry the eraser's footprint covers, cutting at the eraser's
    /// edge. Always a real geometric split: no residue element, no alpha.
    case cutPoints

    /// Mode 3 — removes, from **every** stroke whose centreline passes under the eraser tip, the span
    /// between that stroke's own nearest crossings *outside* the tip. A stroke with no crossings at all
    /// is deleted whole. The eraser's size is therefore the selection radius, not just a reach test:
    /// erase where two lines cross and both lose their crossing, each running out to whatever it hits
    /// next. Owner's ruling, 2026-08-18.
    case cutToIntersection

    var id: String { rawValue }

    /// Label for the segmented control in `EraserSettingsPanel`. Short enough to fit three across.
    var displayName: String {
        switch self {
        case .erase: return "Erase"
        case .cutPoints: return "Cut"
        case .cutToIntersection: return "To Cross"
        }
    }

    /// Whether input for this mode should go through `StrokeStabilizer`. Mode 1 is a brush stroke,
    /// so jitter shows up directly in the erased edge and wants the same smoothing a paint stroke
    /// gets. Modes 2 and 3 are cuts, which belong exactly where the finger went — smoothing would
    /// move the cut away from the aimed line.
    var isStabilized: Bool {
        switch self {
        case .erase: return true
        case .cutPoints, .cutToIntersection: return false
        }
    }
}
