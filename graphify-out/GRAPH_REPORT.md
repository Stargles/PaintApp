# Graph Report - PaintApp-refactor  (2026-07-29)

## Corpus Check
- 106 files · ~138,648 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2126 nodes · 5434 edges · 88 communities (82 shown, 6 thin omitted)
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 823 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3153452f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- XCUIApplication
- ProjectBackupManager
- .manager
- ShapeGeometry
- .transparentFormat
- TimelineRowView
- FloatingPieceOverlayView
- UIView
- VectorCanvas
- LayerRowModel
- bash
- ShapeOverlayView
- CanvasManager
- PerfBaselineTests
- Color
- AnimationTimeline
- ColorPickerPanel
- MetalFillEngine
- Coordinator
- LayerFolder
- FillParams
- ProjectSaveLogicTests
- ProjectSummary
- CanvasManager
- BrushDynamics
- ActivePanel
- StrokeSettingsPanel
- .refreshUndoRedoState
- BrushBlendMode
- View
- PerfMonitor
- SelectionOverlayView
- CanvasManager
- Codable
- CodingKeys
- ObjectTransformOverlayView
- LayerStackCell
- DrawingView
- Foundation
- SideToolbar
- TouchCountRecognizer
- CanvasSizePickerView
- .makeUIView
- XCTest
- Brush
- UndoHistory
- UIKit
- ContentView
- CanvasManager
- SelectPanel
- .panelView
- Equatable
- LayerStackListView.Coordinator
- ActionsMenu
- LayerStackRow
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
- BrushEngineLogicTests
- .stampStroke
- .withStructureUndo
- SaveSnapshot
- SelectionMode
- .attach
- CanvasHostView
- Known Issues
- Remote testing via Tailscale
- .canvasTouchCountChanged
- PaintSoftware - iPad Drawing and Animation App
- Usage Guide
- Refactor baseline (Stage 0)
- .stampCircle
- PaintApp
- LayerStackListView
- Multi-Session Protocol
- .render
- .tableView
- graphify-guard.sh
- fast_test.sh

## God Nodes (most connected - your core abstractions)
1. `CanvasManager` - 83 edges
2. `ShapeGeometry` - 73 edges
3. `Coordinator` - 70 edges
4. `layers` - 59 edges
5. `ProjectBackupManager` - 56 edges
6. `RasterLayerTexture` - 50 edges
7. `VectorCanvas` - 47 edges
8. `StrokeCanvasView` - 44 edges
9. `ShapeDetectorLogicTests` - 42 edges
10. `PaintUITestCase` - 40 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift
- `.body` --calls--> `TimelineTrackView`  [INFERRED]
  PaintSoftware/Views/AnimationTimeline.swift → PaintSoftware/Views/TimelineTrackView.swift
- `.body` --calls--> `StrokeSettingsPanel`  [INFERRED]
  PaintSoftware/Views/BrushSettingsPanel.swift → PaintSoftware/Views/StrokeSettingsPanel.swift
- `.body` --calls--> `StrokeSettingsPanel`  [INFERRED]
  PaintSoftware/Views/EraserSettingsPanel.swift → PaintSoftware/Views/StrokeSettingsPanel.swift
- `.body` --calls--> `LayerStackListView`  [INFERRED]
  PaintSoftware/Views/LayerPanel.swift → PaintSoftware/Views/LayerStackListView.swift

## Import Cycles
- None detected.

## Communities (88 total, 6 thin omitted)

### Community 0 - "XCUIApplication"
Cohesion: 0.09
Nodes (16): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+8 more)

### Community 1 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 2 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, String, UInt, UUID, XCTestCase (+10 more)

### Community 3 - "ShapeGeometry"
Cohesion: 0.06
Nodes (40): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int, Corner (+32 more)

### Community 4 - ".transparentFormat"
Cohesion: 0.08
Nodes (37): FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform, CGAffineTransform (+29 more)

### Community 5 - "TimelineRowView"
Cohesion: 0.07
Nodes (39): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+31 more)

### Community 6 - "FloatingPieceOverlayView"
Cohesion: 0.20
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+3 more)

### Community 7 - "UIView"
Cohesion: 0.12
Nodes (17): FloatingTransform, .effectiveScaleX, .effectiveScaleY, Kind, rotate, scale, LayerTransform, .effectiveScaleX (+9 more)

### Community 8 - "VectorCanvas"
Cohesion: 0.06
Nodes (46): Data, Identifiable, CodableColor, .uiColor, ImageRef, Bool, CGAffineTransform, CGFloat (+38 more)

### Community 9 - "LayerRowModel"
Cohesion: 0.19
Nodes (13): NSObject, Coordinator, LayerRowModel, .folderID, Bool, CanvasManager, Double, Int (+5 more)

### Community 10 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 11 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 12 - "CanvasManager"
Cohesion: 0.07
Nodes (30): Hashable, CanvasManager, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+22 more)

### Community 13 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (11): Atomic, .value, PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String (+3 more)

### Community 14 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 15 - "AnimationTimeline"
Cohesion: 0.11
Nodes (19): Gesture, AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed (+11 more)

### Community 16 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+30 more)

### Community 17 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 18 - "Coordinator"
Cohesion: 0.09
Nodes (19): CanvasView, Coordinator, CanvasManager, CGPoint, CGSize, Coordinator, Date, LayerTransform (+11 more)

### Community 19 - "LayerFolder"
Cohesion: 0.11
Nodes (14): CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String, UUID (+6 more)

### Community 20 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 21 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 22 - "ProjectSummary"
Cohesion: 0.20
Nodes (9): ProjectSummary, Date, GalleryTileView, .body, Void, GalleryView, .body, CanvasManager (+1 more)

### Community 23 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 24 - "BrushDynamics"
Cohesion: 0.16
Nodes (7): BrushDynamics, BrushGrain, Bool, Double, BrushLibrary, .customBrushesDirectory, URL

### Community 25 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 26 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 27 - ".refreshUndoRedoState"
Cohesion: 0.18
Nodes (5): CanvasManager, Bool, CGFloat, CGSize, UIImage

### Community 28 - "BrushBlendMode"
Cohesion: 0.22
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 29 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

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

### Community 35 - "ObjectTransformOverlayView"
Cohesion: 0.25
Nodes (9): ObjectTransformOverlayView, CGPoint, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void (+1 more)

### Community 36 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 37 - "DrawingView"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 38 - "Foundation"
Cohesion: 0.11
Nodes (11): CoreGraphics, Foundation, Tool, eraser, fill, pen, pencil, Notification.Name (+3 more)

### Community 39 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 40 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): Any, StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Int (+8 more)

### Community 41 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 42 - ".makeUIView"
Cohesion: 0.16
Nodes (8): LayerHostView, NSCoder, AppliedTool, CGFloat, Color, Context, Double, UIImageView

### Community 44 - "Brush"
Cohesion: 0.17
Nodes (13): Brush, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+5 more)

### Community 45 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 46 - "UIKit"
Cohesion: 0.09
Nodes (15): Combine, CopiedCel, Int, UIImage, Layer, Bool, Cel, Double (+7 more)

### Community 47 - "ContentView"
Cohesion: 0.20
Nodes (9): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+1 more)

### Community 48 - "CanvasManager"
Cohesion: 0.15
Nodes (10): String, UUID, Void, CanvasManager, Selection, Bool, CGPath, Int (+2 more)

### Community 49 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 50 - ".panelView"
Cohesion: 0.13
Nodes (14): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, CanvasManager, FillSettingsPanel (+6 more)

### Community 51 - "Equatable"
Cohesion: 0.20
Nodes (8): Equatable, LayerKind, compositing, raster, vector, LayerTransform, CGFloat, CGPoint

### Community 52 - "LayerStackListView.Coordinator"
Cohesion: 0.18
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate (+1 more)

### Community 53 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 54 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 55 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 56 - "StrokeCanvasView"
Cohesion: 0.11
Nodes (23): StrokeInput, CGFloat, CGPoint, UITouch, UIView, StrokeCanvasView, .brush, .pencilOnlyDrawing (+15 more)

### Community 57 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 58 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 59 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 60 - "layers"
Cohesion: 0.19
Nodes (10): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+2 more)

### Community 63 - ".load"
Cohesion: 0.27
Nodes (6): ProjectStore, .projectsDirectory, CanvasManager, MainActor, URL, Void

### Community 66 - "BrushEngineLogicTests"
Cohesion: 0.18
Nodes (9): StrokeStabilizer, .stabilization, CGPoint, Double, BrushEngineLogicTests, CGFloat, Int, UIImage (+1 more)

### Community 67 - ".stampStroke"
Cohesion: 0.33
Nodes (9): BrushStamper, Sample, Bool, CGBlendMode, CGFloat, CGPoint, Double, UIColor (+1 more)

### Community 68 - ".withStructureUndo"
Cohesion: 0.20
Nodes (7): Bool, CanvasManager, StructureSnapshot, Int, Layer, String, Void

### Community 69 - "SaveSnapshot"
Cohesion: 0.38
Nodes (10): CelContent, LayerContent, SaveSnapshot, Bool, CGSize, Double, Int, String (+2 more)

### Community 70 - "SelectionMode"
Cohesion: 0.15
Nodes (12): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+4 more)

### Community 71 - ".attach"
Cohesion: 0.27
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 72 - "CanvasHostView"
Cohesion: 0.18
Nodes (7): CanvasHostView, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, Void, UIKeyCommand

### Community 73 - "Known Issues"
Cohesion: 0.17
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 74 - "Remote testing via Tailscale"
Cohesion: 0.20
Nodes (10): Auto-Resign (7-day bypass), Auto-Resign (7-day bypass), Available iPad simulators on the Mac, Connection, Deploying to iPad, Notes, Parallel testing, Prerequisites (+2 more)

### Community 75 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 76 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 78 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 79 - "Refactor baseline (Stage 0)"
Cohesion: 0.13
Nodes (15): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Live stroke cost (+7 more)

### Community 80 - ".stampCircle"
Cohesion: 0.22
Nodes (11): AnyObject, CGContext, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode (+3 more)

### Community 81 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 82 - "LayerStackListView"
Cohesion: 0.33
Nodes (4): LayerStackListView, Coordinator, Void, UIViewRepresentable

### Community 83 - "Multi-Session Protocol"
Cohesion: 0.40
Nodes (5): Ending a session / handing off, graphify, How it's wired, Multi-Session Protocol, Starting work

### Community 84 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 85 - ".tableView"
Cohesion: 0.50
Nodes (3): IndexPath, CGFloat, UISwipeActionsConfiguration

## Knowledge Gaps
- **295 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+290 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CanvasManager` connect `CanvasManager` to `ShapeGeometry`, `.withStructureUndo`, `.transparentFormat`, `SelectionMode`, `Foundation`, `Brush`, `UndoHistory`, `UIKit`, `CanvasManager`, `MetalFillEngine`, `LayerFolder`, `CanvasManager`, `RasterLayerTexture`, `.refreshUndoRedoState`, `layers`, `PerfMonitor`?**
  _High betweenness centrality (0.131) - this node is a cross-community bridge._
- **Why does `Coordinator` connect `Coordinator` to `ShapeGeometry`, `ObjectTransformOverlayView`, `FloatingPieceOverlayView`, `CanvasHostView`, `LayerRowModel`, `.makeUIView`, `TouchCountRecognizer`, `.canvasTouchCountChanged`, `ShapeOverlayView`, `LayerStackListView.Coordinator`, `ActivePanel`, `SelectionOverlayView`?**
  _High betweenness centrality (0.129) - this node is a cross-community bridge._
- **Why does `UIKit` connect `UIKit` to `.manager`, `.transparentFormat`, `TimelineRowView`, `UIView`, `VectorCanvas`, `Color`, `MetalFillEngine`, `.refreshUndoRedoState`, `SelectionOverlayView`, `ObjectTransformOverlayView`, `LayerStackCell`, `Foundation`, `TouchCountRecognizer`, `XCTest`, `ProjectStore.swift`, `layers`, `CanvasHostView`, `.stampCircle`, `LayerStackListView`, `.render`?**
  _High betweenness centrality (0.125) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 59 inferred relationships involving `XCUIApplication` (e.g. with `.testAdjustingThresholdAfterFillReappliesToUncommittedFill()` and `.testDrawingOverFillCommitsFillAndStrokeUndoesFirst()`) actually correct?**
  _`XCUIApplication` has 59 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._
- **Are the 58 inferred relationships involving `layers` (e.g. with `.activeLayerIsVector` and `.addImageToActiveVectorLayer()`) actually correct?**
  _`layers` has 58 INFERRED edges - model-reasoned connections that need verification._