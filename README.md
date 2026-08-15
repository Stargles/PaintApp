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
- **Layers**: raster and vector layers, opacity, visibility, fill-reference toggle, object (photo)
  layers with on-canvas transform handles
- **Canvas**: adjustable padding margin, flip horizontal/vertical, custom size presets
- **Vector eraser**: three CSP-style modes (erase, cut points, cut to intersection). An eraser *is* a
  stroke — it is an `.erase` element in the same z-ordered display list as the paint it eats, so it
  is non-destructive and undoable, and Mode 1 splits a cleanly severed stroke into real pieces
- **Animation Timeline**: multi-cel frame-by-frame animation, scrub/play, per-cel copy/clear/extend
- **Keyframe interpolation** on vector layers: mark two cels as references and the cels between them
  become derived (lattice + ARAP warp), with motion groups, guide strokes, editing at an in-between
  and Commit — see [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)
- **Color**: a Procreate-style HSB picker (SV square, hue bar, hex field) plus a custom palette
  builder (named palettes, swatch grid, persisted across launches)
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
│   ├── StrokeGeometry.swift / VectorEraser.swift  # vector eraser geometry + the three modes
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
└── Views/                       # SwiftUI + UIKit-bridged views
    ├── CanvasView.swift, DrawingView.swift, ContentView-adjacent panels
    ├── TopToolbar.swift, SideToolbar.swift
    ├── LayerPanel.swift, AnimationTimeline.swift, TimelineTrackView.swift
    ├── ColorPickerPanel.swift, BrushSettingsPanel.swift, EraserSettingsPanel.swift,
    │   FillSettingsPanel.swift, SelectPanel.swift
    ├── ObjectTransformOverlayView.swift, FloatingPieceOverlayView.swift, SelectionOverlayView.swift
    ├── GalleryView.swift, GalleryTileView.swift, CanvasSizePickerView.swift, ActionsMenu.swift
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
3. Pick a color from the color picker, or a saved palette swatch.
4. Draw with your finger or Apple Pencil (toggle "Apple Pencil only" in the side rail if you want to
   ignore accidental finger/palm touches while drawing with a Pencil).

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
2. Add a raster or vector layer, or insert a photo as an object layer, from the "+" menu.
3. Adjust opacity with the slider, toggle visibility with the eye icon, tap a row to make it active.
4. Tap the active row again for its options menu (rename, blend mode, merge, delete). While one is
   open every row carries a checkmark to clip that layer to, and a drop to make it a fill boundary.
5. Swipe a row to Duplicate or Delete.

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

**Drawing not working** — make sure a layer is selected and visible (eye icon); if "Apple Pencil
only" is toggled on (side rail) and you're using a simulator or a finger, toggle it off.

**UI tests failing on iPhone** — this app's layout assumes an iPad; run the test suite against an
iPad simulator destination.

## Known limitations / open work

See [BUGS.md](BUGS.md) for the tracked list. Notable ones: square/custom brush stamps are
approximated as tiled round dabs (not true shaped stamps yet); Distort/Warp transform modes render
identically to Uniform; the Adjust panel and Cut/Copy/Paste are still "Coming soon" stubs.

## License

This project is provided as-is for educational and personal use.
