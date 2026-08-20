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
            return "A value layer holds no pixels for text to land in. Add it on a raster layer."
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
    /// **It is not the flood with a bigger seed, and the settings do not all carry over.** Gap
    /// closing and Threshold act on the collar that decides what is *held out*; Edge Overlap is
    /// forced to 0, because a fill that covers the line has no antialiasing seam to hide and growing
    /// it would only push colour past the artwork onto clean paper. See
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
