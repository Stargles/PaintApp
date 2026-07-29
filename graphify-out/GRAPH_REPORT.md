# Graph Report - PaintApp-refactor  (2026-07-29)

## Corpus Check
- 97 files · ~124,030 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2013 nodes · 5071 edges · 83 communities (78 shown, 5 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 432 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `aab1ce9f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintSoftwareUITests
- ProjectBackupManager
- .manager
- ShapeGeometry
- .transparentFormat
- TimelineRowView
- FloatingPieceOverlayView
- FloatingPiece
- VectorCanvas
- LayerRowModel
- bash
- ShapeOverlayView
- CanvasManager
- PerfBaselineTests
- Cel
- AnimationTimeline
- ColorPickerPanel
- MetalFillEngine
- Coordinator
- LayerFolder
- FillParams
- .handleEnd
- ProjectSummary
- CanvasManager
- BrushEngineLogicTests
- ActivePanel
- StrokeSettingsPanel
- .refreshUndoRedoState
- Brush
- LayerOptionsPanel
- PerfMonitor
- SelectionOverlayView
- CanvasManager
- Codable
- CodingKeys
- .handleTransformGesture
- LayerStackCell
- DrawingView
- Foundation
- View
- TouchCountRecognizer
- CanvasSizePickerView
- .makeUIView
- .reconcileLayers
- BrushShape
- UndoHistory
- UIKit
- ContentView
- CanvasManager
- SelectPanel
- .panelView
- LayerTransform
- Tool
- ActionsMenu
- Layer
- BrushSettingsPanel
- StrokeCanvasView
- RasterLayerTexture
- ProjectStore.swift
- parallel_test.sh
- layers
- cleanup_session.sh
- screenshot.sh
- .load
- status.sh
- StrokeStabilizer
- .stampStroke
- .withStructureUndo
- CanvasManager
- SelectionMode
- TransformMode
- CanvasHostView
- Known Issues
- Remote testing via Tailscale
- .canvasTouchCountChanged
- PaintSoftware - iPad Drawing and Animation App
- CLAUDE.md
- Usage Guide
- Refactor baseline (Stage 0)
- .stampCircle
- AppliedTool
- .uiColor

## God Nodes (most connected - your core abstractions)
1. `PaintSoftwareUITests` - 98 edges
2. `CanvasManager` - 80 edges
3. `ShapeGeometry` - 72 edges
4. `Coordinator` - 70 edges
5. `layers` - 58 edges
6. `ProjectBackupManager` - 56 edges
7. `StrokeCanvasView` - 43 edges
8. `ShapeDetectorLogicTests` - 42 edges
9. `VectorCanvas` - 38 edges
10. `RasterLayerTexture` - 37 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `TimelineTrackView`  [INFERRED]
  PaintSoftware/Views/AnimationTimeline.swift → PaintSoftware/Views/TimelineTrackView.swift
- `.body` --calls--> `StrokeSettingsPanel`  [INFERRED]
  PaintSoftware/Views/BrushSettingsPanel.swift → PaintSoftware/Views/StrokeSettingsPanel.swift
- `.body` --calls--> `StrokeSettingsPanel`  [INFERRED]
  PaintSoftware/Views/EraserSettingsPanel.swift → PaintSoftware/Views/StrokeSettingsPanel.swift
- `.body` --calls--> `LayerStackListView`  [INFERRED]
  PaintSoftware/Views/LayerPanel.swift → PaintSoftware/Views/LayerStackListView.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift

## Import Cycles
- None detected.

## Communities (83 total, 5 thin omitted)

### Community 0 - "PaintSoftwareUITests"
Cohesion: 0.09
Nodes (11): CGVector, PaintSoftwareUITests, Bool, CGFloat, Double, Int, String, TimeInterval (+3 more)

### Community 1 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 2 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, String, UInt, UUID, XCTestCase (+10 more)

### Community 3 - "ShapeGeometry"
Cohesion: 0.06
Nodes (41): Equatable, ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int (+33 more)

### Community 4 - ".transparentFormat"
Cohesion: 0.18
Nodes (16): CGContext, IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint (+8 more)

### Community 5 - "TimelineRowView"
Cohesion: 0.07
Nodes (39): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+31 more)

### Community 6 - "FloatingPieceOverlayView"
Cohesion: 0.06
Nodes (37): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+29 more)

### Community 7 - "FloatingPiece"
Cohesion: 0.18
Nodes (14): FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform, Selection (+6 more)

### Community 8 - "VectorCanvas"
Cohesion: 0.09
Nodes (32): Data, CodableColor, .uiColor, ImageRef, Bool, CGAffineTransform, CGFloat, CGPath (+24 more)

### Community 9 - "LayerRowModel"
Cohesion: 0.08
Nodes (30): IndexPath, Coordinator, DropTarget, between, onto, LayerRowModel, .folderID, LayerStackListView (+22 more)

### Community 10 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 11 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 12 - "CanvasManager"
Cohesion: 0.09
Nodes (24): CanvasManager, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState, .isShapeFollowingFinger (+16 more)

### Community 13 - "PerfBaselineTests"
Cohesion: 0.10
Nodes (21): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+13 more)

### Community 14 - "Cel"
Cohesion: 0.24
Nodes (7): CGSize, Layer, Cel, .endFrame, Int, UIImage, UUID

### Community 15 - "AnimationTimeline"
Cohesion: 0.07
Nodes (30): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+22 more)

### Community 16 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (40): Hashable, Identifiable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+32 more)

### Community 17 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 18 - "Coordinator"
Cohesion: 0.15
Nodes (14): NSObject, Coordinator, CanvasManager, Date, NSLayoutConstraint, TimeInterval, Timer, UILongPressGestureRecognizer (+6 more)

### Community 19 - "LayerFolder"
Cohesion: 0.11
Nodes (15): String, CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String (+7 more)

### Community 20 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 21 - ".handleEnd"
Cohesion: 0.18
Nodes (9): StrokeInput, CGFloat, CGPoint, UITouch, UIView, CGFloat, CGPoint, UIEvent (+1 more)

### Community 22 - "ProjectSummary"
Cohesion: 0.16
Nodes (12): ProjectSummary, Bool, Date, String, UUID, GalleryTileView, .body, Void (+4 more)

### Community 23 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 24 - "BrushEngineLogicTests"
Cohesion: 0.27
Nodes (3): BrushDynamics, Double, BrushEngineLogicTests

### Community 25 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 26 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 27 - ".refreshUndoRedoState"
Cohesion: 0.19
Nodes (5): CanvasManager, Bool, CGFloat, CGSize, UIImage

### Community 28 - "Brush"
Cohesion: 0.15
Nodes (14): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+6 more)

### Community 29 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+10 more)

### Community 30 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 31 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 32 - "CanvasManager"
Cohesion: 0.20
Nodes (12): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+4 more)

### Community 33 - "Codable"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 34 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKey, CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes (+10 more)

### Community 35 - ".handleTransformGesture"
Cohesion: 0.23
Nodes (5): CGPoint, CGSize, LayerTransform, Void, Recognizer

### Community 36 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 37 - "DrawingView"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 38 - "Foundation"
Cohesion: 0.12
Nodes (9): Foundation, LayerKind, compositing, raster, vector, Notification.Name, AppVersion, .versionString (+1 more)

### Community 39 - "View"
Cohesion: 0.17
Nodes (15): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+7 more)

### Community 40 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): Any, StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Int (+8 more)

### Community 41 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 42 - ".makeUIView"
Cohesion: 0.23
Nodes (5): CanvasView, Context, Coordinator, UIImageView, UIViewRepresentable

### Community 44 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 45 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 46 - "UIKit"
Cohesion: 0.07
Nodes (12): Combine, CoreGraphics, Darwin, CopiedCel, Int, UIImage, ThumbnailRenderer, PhotosUI (+4 more)

### Community 47 - "ContentView"
Cohesion: 0.13
Nodes (12): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+4 more)

### Community 48 - "CanvasManager"
Cohesion: 0.19
Nodes (8): String, UUID, Void, CanvasManager, Int, UIImage, UUID, String

### Community 49 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 50 - ".panelView"
Cohesion: 0.13
Nodes (14): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, CanvasManager, FillSettingsPanel (+6 more)

### Community 51 - "LayerTransform"
Cohesion: 0.50
Nodes (3): LayerTransform, CGFloat, CGPoint

### Community 52 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 53 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 54 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 55 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 56 - "StrokeCanvasView"
Cohesion: 0.12
Nodes (17): NSCoder, StrokeCanvasView, .brush, .pencilOnlyDrawing, .raster, .vectorCanvas, Bool, CanvasManager (+9 more)

### Community 57 - "RasterLayerTexture"
Cohesion: 0.22
Nodes (8): RasterLayerTexture, .hasContent, Bool, CGSize, Int, UIImage, CGSize, UIImage

### Community 58 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 59 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 60 - "layers"
Cohesion: 0.33
Nodes (5): .activeLayerIsVector, CanvasManager, Bool, Int, layers

### Community 63 - ".load"
Cohesion: 0.24
Nodes (8): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, CanvasManager, UIImage, URL

### Community 66 - "StrokeStabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 67 - ".stampStroke"
Cohesion: 0.33
Nodes (9): BrushStamper, Sample, Bool, CGBlendMode, CGFloat, CGPoint, Double, UIColor (+1 more)

### Community 68 - ".withStructureUndo"
Cohesion: 0.23
Nodes (7): Bool, CanvasManager, StructureSnapshot, Int, Layer, String, Void

### Community 69 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 70 - "SelectionMode"
Cohesion: 0.17
Nodes (12): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+4 more)

### Community 71 - "TransformMode"
Cohesion: 0.17
Nodes (9): Bool, TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform (+1 more)

### Community 72 - "CanvasHostView"
Cohesion: 0.18
Nodes (7): CanvasHostView, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, Void, UIKeyCommand

### Community 73 - "Known Issues"
Cohesion: 0.20
Nodes (10): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Known Issues, Non-functional / missing (as-designed stubs) (+2 more)

### Community 74 - "Remote testing via Tailscale"
Cohesion: 0.20
Nodes (10): Auto-Resign (7-day bypass), Auto-Resign (7-day bypass), Available iPad simulators on the Mac, Connection, Deploying to iPad, Notes, Parallel testing, Prerequisites (+2 more)

### Community 75 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 76 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 77 - "CLAUDE.md"
Cohesion: 0.29
Nodes (3): Ending a session / handing off, Multi-Session Protocol, Starting work

### Community 78 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 79 - "Refactor baseline (Stage 0)"
Cohesion: 0.29
Nodes (7): After Stage 0's additions, As measured, 2026-07-28, Drift against the last recorded baseline, Environment, Full-suite baseline, Performance baseline, Refactor baseline (Stage 0)

### Community 80 - ".stampCircle"
Cohesion: 0.40
Nodes (4): CGBlendMode, CGFloat, CGPoint, UIColor

### Community 81 - "AppliedTool"
Cohesion: 0.33
Nodes (4): AppliedTool, CGFloat, Color, Double

## Knowledge Gaps
- **280 isolated node(s):** `gallery`, `sizePicker`, `editor`, `softRound`, `hardRound` (+275 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CanvasManager` connect `CanvasManager` to `ShapeGeometry`, `.withStructureUndo`, `SelectionMode`, `FloatingPiece`, `TransformMode`, `UndoHistory`, `UIKit`, `layers`, `Cel`, `MetalFillEngine`, `CanvasManager`, `LayerFolder`, `Tool`, `CanvasManager`, `RasterLayerTexture`, `.refreshUndoRedoState`, `Brush`, `PerfMonitor`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Why does `UIKit` connect `UIKit` to `LayerStackCell`, `TimelineRowView`, `FloatingPieceOverlayView`, `FloatingPiece`, `VectorCanvas`, `CanvasHostView`, `TouchCountRecognizer`, `LayerRowModel`, `PerfBaselineTests`, `Cel`, `MetalFillEngine`, `Layer`, `ProjectStore.swift`, `.refreshUndoRedoState`, `SelectionOverlayView`?**
  _High betweenness centrality (0.143) - this node is a cross-community bridge._
- **Why does `ShapeGeometry` connect `ShapeGeometry` to `CanvasManager`, `SelectionMode`, `.reconcileLayers`, `CanvasManager`, `ShapeOverlayView`, `Coordinator`?**
  _High betweenness centrality (0.116) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 21 inferred relationships involving `ShapeGeometry` (e.g. with `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()` and `.testCollapsedLineLandsExactlyOnTheLine()`) actually correct?**
  _`ShapeGeometry` has 21 INFERRED edges - model-reasoned connections that need verification._
- **What connects `gallery`, `sizePicker`, `editor` to the rest of the system?**
  _280 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PaintSoftwareUITests` be split into smaller, more focused modules?**
  _Cohesion score 0.09433962264150944 - nodes in this community are weakly interconnected._