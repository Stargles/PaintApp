# PaintSoftware - iPad Drawing and Animation App

A Procreate-like drawing and animation app for iPad, built around a custom native-resolution
raster/vector drawing engine (no PencilKit), with layers, a full brush/eraser/fill/select-move
toolset, and a frame-by-frame animation timeline.

## Features

- **Drawing engine**: native-resolution raster strokes (own engine, not PencilKit — stays crisp at
  any zoom), plus resolution-independent vector layers that can be moved/rotated/scaled losslessly
- **Brushes**: a brush library (shape, hardness, spacing, stabilization, pressure dynamics, grain) with
  custom brush import, and a matching Eraser tool with its own settings
- **Fill**: GPU (Metal) colour-based flood fill with adjustable threshold/gap-closing/edge-overlap,
  live drag-to-adjust before committing, and per-layer "fill reference" boundaries
- **Select & Move**: lasso/rectangle/automatic (magic wand) selection, move/duplicate with
  resize/rotate/mirror, and a selection-clipped paint/fill mode
- **Layers**: three kinds — **raster** and **vector** hold pixels, and a **value** layer holds none.
  Plus opacity, visibility, fill-reference toggle, object (photo) layers with on-canvas transform
  handles, and groups that composite as parentheses — isolated or pass-through, with their own
  opacity, blend mode and mask
- **Value layers, two modes in one kind**: with no effect set it is one flat colour across the canvas
  (Photoshop's Solid Colour layer); set an effect on it and it becomes an adjustment layer, grading
  everything below it inside its own container. Which mode it is in is decided by whether it carries
  an effect — there is no separate kind and no mode switch to keep in sync
- **Compositing**: 25 blend modes on layers and groups, following W3C Compositing Level 1 rather than
  `CGBlendMode` where the two disagree; render-time alpha masks (never baked, raster and vector
  alike, including "clip to below"); and compositor **nodes** — a node's direct children are its
  inputs, bottom child first, and its dropdown picks either a blend op (two inputs) or one of the
  effects (one input). Picks its backend per composite: the GPU (Metal) for anything that grades or
  has four or more layers, the Core Graphics implementation — which is also the byte-for-byte
  reference and the fallback where there is no GPU — below that, because the two have opposite cost
  shapes on real hardware. The GPU path is also sized to the device it runs on (`CompositorBudget`):
  a canvas whose working set would not fit is composited smaller rather than crashing, which is what
  a 4K canvas with two effect layers does on a 3 GB iPad. See
  [LAYER_COMPOSITING.md](LAYER_COMPOSITING.md)
- **Effects**: 13, all configurable from the layer panel — levels, curves, brightness/contrast, HSV
  shift, gradient map, chromatic aberration, posterize, noise, gaussian/directional blur, bloom,
  sobel, sharpen and outline — with a curve editor and a gradient-stop editor for the two that need
  them. One shader per effect, used by both wrappers (value layer and node)
- **Canvas**: adjustable padding margin, flip horizontal/vertical, custom size presets, and a
  **render resolution** setting (Full / 75% / 50%) that trades live-canvas sharpness for speed on
  heavily layered artwork — it reaches only what is on screen, never the saved file or the export
- **Vector eraser**: three CSP-style modes (erase, cut points, cut to intersection). An eraser *is* a
  stroke — it is an `.erase` element in the same z-ordered display list as the paint it eats, so it
  is non-destructive and undoable, and Mode 1 splits a cleanly severed stroke into real pieces.
  In Mode 3 the brush size is a **selection radius**, not just a reach: every stroke whose centreline
  the circle covers is cut back to its own nearest crossings outside the circle, so erasing where two
  lines meet takes both. The circle is drawn on the canvas under the finger while the gesture is live
- **Animation Timeline**: multi-cel frame-by-frame animation, scrub/play, per-cel copy/clear/extend
- **Keyframe interpolation** on vector layers: mark two cels as references and the cels between them
  become derived (lattice + ARAP warp), with motion groups, guide strokes, editing at an in-between
  and Commit — see [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)
- **Color**: a Procreate-style HSB picker (SV square, hue bar, hex field) plus a custom palette
  builder (named palettes, swatch grid, persisted across launches). **One picker for the whole app** —
  brush, canvas background, value layer, effect colour and gradient stop all open the same panel, and
  the only thing that varies between them is whether opacity is offered. Plus an **eyedropper** on the
  side rail: select it, tap the canvas, and the colour under the tap becomes the brush colour. It
  samples the composite (what is on screen, paper included) and reverts to the previous tool
- **Gallery**: a project browser with thumbnails, backed by on-disk project packages
- **Gestures**: two-finger zoom, rotate, and pan

## Project Structure

```
PaintSoftware/
├── PaintApp.swift              # App entry point
├── ContentView.swift            # Root view (gallery <-> editor)
├── Engine/                      # Drawing engine
│   ├── RasterLayerTexture.swift #   persistent per-cel raster bitmap (stamp-based, thread-safe)
│   ├── VectorLayer.swift        #   resolution-independent vector layer content
│   ├── BrushStamper.swift       #   shared stamp pipeline (shape/dynamics/grain)
│   ├── Brush.swift / BrushLibrary.swift
│   ├── StrokeInput.swift / StrokeStabilizer.swift
│   ├── StrokeSampleGate.swift   #   which input samples become stored geometry (distance, not time)
│   ├── StrokeGeometry.swift / VectorEraser.swift  # vector eraser geometry + the three modes
│   ├── Eyedropper.swift         #   which pixel a canvas point names, and its colour (pure)
│   ├── InterpolationEvaluator.swift / GuidePath.swift
│   ├── Deform/                  #   lattice + ARAP deformation (app-type-free)
│   ├── Fill.metal / MetalFillEngine.swift  # GPU flood-fill
├── Models/
│   ├── CanvasManager.swift      # Core state/operations (layers, cels, tools, undo)
│   ├── InterpolationRecipe.swift / MotionGroup.swift / GuideStroke.swift
│   ├── SelectionModels.swift    # Select & Move tool operations
│   ├── Palette.swift            # Custom color palettes
│   └── ProjectManifest.swift    # On-disk project schema
├── Services/
│   ├── ProjectStore.swift       # Save/load a project package
│   └── PixelOps.swift           # Image compositing helpers
├── Utilities/
│   ├── ColorConversion.swift / ColorMath.swift
│   ├── ThumbnailRenderer.swift
│   └── AppVersion.swift
├── Debug/                       # off-by-default diagnostics (see "Action recorder" in CLAUDE.md)
│   ├── ActionRecorder.swift     #   records touches/recognizers/model changes to JSONL
│   └── WindowEventTap.swift     #   the one `sendEvent` interception it installs while recording
└── Views/                       # SwiftUI + UIKit-bridged views
    ├── CanvasView.swift, DrawingView.swift, ContentView-adjacent panels
    ├── TopToolbar.swift, SideToolbar.swift
    ├── LayerPanel.swift, LayerStackListView.swift, LayerStackCell.swift, EffectSection.swift
    ├── AnimationTimeline.swift, TimelineTrackView.swift
    ├── ColorPickerPanel.swift, BrushSettingsPanel.swift, EraserSettingsPanel.swift,
    │   FillSettingsPanel.swift, SelectPanel.swift
    ├── ObjectTransformOverlayView.swift, FloatingPieceOverlayView.swift, SelectionOverlayView.swift
    ├── GalleryView.swift, GalleryTileView.swift, CanvasSizePickerView.swift, ActionsMenu.swift
    └── ActionRecorderControls.swift
tools/
└── recording2xcuitest.py        # turns an action recording into a draft XCUITest
```

## Requirements

- Xcode 26 or later
- iPad simulator or device — this is an iPad-first app; the UI test suite specifically needs an iPad
  destination (an iPhone simulator's cramped layout fails several tests)
- Apple Pencil recommended, not required (finger drawing works out of the box)

## Building and Running

1. Open `PaintSoftware.xcodeproj` in Xcode.
2. Select an iPad simulator (or a connected iPad) as the run destination.
3. Press `Cmd + R` to build and run.

To run the UI test suite: `Cmd + U`, or via the command line:

```bash
xcodebuild -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination 'platform=iOS Simulator,name=<an iPad simulator>' test
```

### Deploying to a physical iPad

1. Connect the iPad via USB, select it as the run destination in Xcode, and set your team under
   **Signing & Capabilities**.
2. On first launch you may need to trust the developer certificate: **Settings → General → VPN &
   Device Management → [your developer profile] → Trust**.
3. For distribution without a cable, archive (**Product → Archive**) and distribute via TestFlight.

## Usage Guide

### Creating a Canvas
1. Launch the app into the Gallery.
2. Tap "New Canvas", pick a size preset (or custom dimensions), and tap "Create Canvas".

### Drawing
1. Pick Pen/Pencil, Eraser, Fill, or Select/Move from the top toolbar.
2. Adjust size/opacity (or a tool-specific setting) from the side rail sliders, or open the tool's
   panel for its full settings (shape, stabilization, grain, etc.).
3. Pick a color from the color picker, or a saved palette swatch. **There is one picker**: the same
   panel drives the brush, the canvas background, a value layer's colour, an effect's colour and a
   gradient stop, differing only in whether it offers opacity.
4. Or take a colour off the artwork: tap the eyedropper below the side rail's opacity slider, then
   tap the canvas. It samples the **composite** — what you can actually see, paper included — and
   hands the canvas back to the tool you were using.
5. Draw with your finger or Apple Pencil (toggle "Apple Pencil only" in the side rail if you want to
   ignore accidental finger/palm touches while drawing with a Pencil). The toggle gates **strokes and
   the fill tool alike**, and the lasso and the eyedropper with them; two-finger pan/zoom/rotate
   stays on a finger either way.
6. If a touch cannot draw — no layers, the active layer hidden, or a layer with no drawing surface —
   a banner appears under the top toolbar saying which, with the fix as a button. It dismisses itself
   and never interrupts the stroke.

### Fill
1. Select the Fill tool and tap inside a region bounded by content on the current layer's fill
   references.
2. Drag to adjust threshold/gap-closing/edge-overlap live before it commits; it also stays adjustable
   after lifting your finger until you draw elsewhere or start a new fill.
3. Toggle which layers count as fill boundaries with each row's drop button, shown while a layer's
   options menu is open. Shown layers are boundaries and hidden ones are not, until you say otherwise
   — after which your choice sticks through the eye icon.

### Select & Move
1. Pick a selection mode (lasso, rectangle, or automatic/magic-wand) from the Select bar.
2. Draw a selection, then Move/Duplicate/Fill/Clear it, or switch to the Move tool to drag/resize/
   rotate/mirror the selected (or, with no selection, the whole) layer content.
3. "Paint Outside Selection" (off by default) controls whether strokes/fills can spill past the
   selection boundary.

### Layers
1. Open the Layers panel from the top toolbar.
2. **Tap** "+" for the menu: a raster, vector or value layer, a group, a compositor node, or a photo
   as an object layer. The new item lands **directly above the active layer, inside that layer's own
   container** — not at the top of the document.
3. Adjust opacity with the slider, toggle visibility with the eye icon, tap a row to make it active.
4. Tap the active row again for its options menu (rename, blend mode, merge, delete). While one is
   open every row carries a checkmark to clip that layer to, and a drop to make it a fill boundary.
   Mask and Effect Settings each open as a sub-menu in place, with a Back button.
5. Swipe a row to Duplicate or Delete.
6. Drag a row to reorder it. Dropping onto another layer reorders — it does not group; drop onto a
   folder or node row to go inside one. The row you are dragging leaves its slot, and an orange
   guide shows where it will land and at what indent.

### Value layers and effects
1. Add a value layer from the "+" menu. Out of the box it is a flat colour, Normal blend — pick the
   colour from the row's colour swatch.
2. Its options menu opens on **Blend Mode**, one merged menu listing every blend mode plus the 13
   effects below them. Pick a blend mode and the layer is a flat colour composited that way; pick an
   effect and it becomes an adjustment layer instead, grading everything beneath it inside its own
   container. The two are answers to the same question, so picking one always clears the other. The
   row itself is never hidden — it shows the effect's name in place of the blend mode's while one is
   set, and the colour swatch below it is replaced by **Effect Settings ▸** for the same reason.
3. **Effect Settings ▸** opens the knobs for whichever effect is set, including a curve editor
   (Curves) and a gradient-stop editor (Gradient Map).
4. A compositor node's operation dropdown offers the same effects beneath the blend ops. A blend op
   takes two inputs; an effect op takes one, so it grades that input's composite as a unit.
5. A value layer or node renames itself to follow the effect you pick, unless you have renamed it by
   hand — after which it keeps your name.

### Animation
1. Expand the timeline at the bottom to manage cels/frames.
2. Tap a cel block for Copy/Extend to End/Clear/Delete; tap an empty gap to add a new cel there.
3. Drag a cel's edges to resize its frame range; scrub the ruler or press Play to preview.

### Canvas
- **Actions menu**: adjust canvas padding (a drawable margin around the artwork) or flip
  horizontal/vertical.
- **Pinch** to zoom, **two-finger rotate/drag** to rotate/pan the canvas.

## Troubleshooting

**Build errors** — make sure you're on Xcode 26+; the GPU fill engine's `Fill.metal` shader needs the
Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`), a one-time per-machine
install.

**Drawing not working** — the app says why in a banner under the top toolbar (no layers, hidden
layer, or a layer with no drawing surface) and offers the fix. If nothing happens at all and no
banner appears, "Apple Pencil only" is probably on (side rail) while you are using a simulator or a
finger — that gates fill as well as strokes, and is deliberately silent.

**UI tests failing on iPhone** — this app's layout assumes an iPad; run the test suite against an
iPad simulator destination.

## Known limitations / open work

See [BUGS.md](BUGS.md) for the tracked list. Notable ones: **two-finger pan/pinch/rotate is reported
dead on device while the Fill tool is selected**, unexplained and unreproduced on the simulator;
square/custom brush stamps are approximated as tiled round dabs (not true shaped stamps yet);
Distort/Warp transform modes render identically to Uniform; Cut/Copy/Paste and Drawing Guide are
still "Coming soon" stubs.

## License

This project is provided as-is for educational and personal use.
