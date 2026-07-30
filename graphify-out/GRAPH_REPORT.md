# Graph Report - PaintApp-dablattice  (2026-07-30)

## Corpus Check
- 116 files · ~194,188 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2620 nodes · 7102 edges · 104 communities (96 shown, 8 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 886 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `18d01e27`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
- ProjectBackupManager
- .manager
- VectorCanvas
- TimelineRowView
- FloatingPieceOverlayView
- BrushEngineLogicTests
- ColorPickerPanel
- CanvasManager
- bash
- StrokeGeometry
- CanvasManager
- VectorEraserLogicTests
- ShapeOverlayView
- StrokeCanvasView
- Vector Eraser — Design Plan
- ShapeGeometry
- CanvasManager
- Brush
- CanvasSizePickerView
- ShapeDetectorLogicTests
- StrokeGeometryLogicTests
- CodingKeys
- .transparentFormat
- PerfBaselineTests
- .withStructureUndo
- MetalFillEngine
- RasterLayerTexture
- VectorSample
- FillParams
- .stampStroke
- layers
- CanvasManager
- TouchCountRecognizer
- StrokeSpatialIndex
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- View
- ShapeDetector
- LayerStackCell
- Coordinator
- SelectionOverlayView
- ProjectSaveLogicTests
- PerfMonitor
- UIKit
- .stampCircle
- SelectionMode
- Color
- DrawingView
- Foundation
- CodingKeys
- ProjectManifest
- LayerStackListView.Coordinator
- SideToolbar
- ProjectSummary
- Coordinator
- LayerRowModel
- UndoHistory
- .load
- .hasContentBeneath
- CanvasManager
- CanvasHostView
- .makeUIView
- Known Issues
- XCTest
- LayerStackRow
- .reconcileLayers
- Refactor baseline (Stage 0)
- SaveSnapshot
- .handleTransformGesture
- .panelView
- .canvasTouchCountChanged
- Corner
- .setCanvasPadding
- ActionsMenu
- PaintSoftware - iPad Drawing and Animation App
- Layer
- VectorEraserMode
- BrushSettingsPanel
- EraserSettingsPanel
- Usage Guide
- CutOutcome
- Multi-Session Protocol
- Tool
- ProjectStore.swift
- VectorScratchRole
- AppliedTool
- Atomic
- parallel_test.sh
- LayerKind
- .tableView
- CopiedCel
- LayerTransform
- cleanup_session.sh
- screenshot.sh
- .init
- Suite parallelisation (2026-07-29, between Stage 3 and Stage 4)
- graphify-guard.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `VectorCanvas` - 100 edges
2. `VectorSample` - 86 edges
3. `CanvasManager` - 86 edges
4. `ShapeGeometry` - 73 edges
5. `Coordinator` - 70 edges
6. `Brush` - 61 edges
7. `layers` - 60 edges
8. `ProjectBackupManager` - 56 edges
9. `RasterLayerTexture` - 52 edges
10. `StrokeGeometryLogicTests` - 52 edges

## Surprising Connections (you probably didn't know these)
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `Gesture` --references--> `VectorSample`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/ShapeGeometry.swift
- `ParityScenario` --references--> `VectorSample`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/ShapeGeometry.swift

## Import Cycles
- None detected.

## Communities (104 total, 8 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (23): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+15 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+41 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "VectorCanvas"
Cohesion: 0.07
Nodes (42): Identifiable, CodableColor, .uiColor, kind, Kind, fill, image, stroke (+34 more)

### Community 5 - "TimelineRowView"
Cohesion: 0.07
Nodes (41): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+33 more)

### Community 6 - "FloatingPieceOverlayView"
Cohesion: 0.06
Nodes (37): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+29 more)

### Community 7 - "BrushEngineLogicTests"
Cohesion: 0.09
Nodes (16): StrokeStabilizer, .stabilization, CGPoint, Double, BrushEngineLogicTests, Any, CGFloat, CodableColor (+8 more)

### Community 8 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (40): Hashable, CelLocation, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+32 more)

### Community 9 - "CanvasManager"
Cohesion: 0.05
Nodes (35): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+27 more)

### Community 10 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 11 - "StrokeGeometry"
Cohesion: 0.11
Nodes (12): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat, CGPoint, CGRect (+4 more)

### Community 12 - "CanvasManager"
Cohesion: 0.08
Nodes (27): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+19 more)

### Community 13 - "VectorEraserLogicTests"
Cohesion: 0.14
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 14 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, CGFloat, CGPoint, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+17 more)

### Community 16 - "Vector Eraser — Design Plan"
Cohesion: 0.05
Nodes (40): 1. Perf — now genuinely overdue, 2. Then, Carry-overs still open, Environment correction (important, saves 10 minutes), Mode 1, as it actually is, Multi-session protocol reminder, Next session: start here, Notes worth not re-deriving (+32 more)

### Community 17 - "ShapeGeometry"
Cohesion: 0.09
Nodes (27): CaseIterable, Edge, bottom, left, right, top, FollowFrame, Kind (+19 more)

### Community 18 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 19 - "Brush"
Cohesion: 0.09
Nodes (31): Codable, Equatable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten (+23 more)

### Community 20 - "CanvasSizePickerView"
Cohesion: 0.06
Nodes (28): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+20 more)

### Community 21 - "ShapeDetectorLogicTests"
Cohesion: 0.17
Nodes (5): ShapeDetectorLogicTests, CGFloat, CGPoint, CGRect, Int

### Community 22 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (9): Deterministic, StrokeGeometryLogicTests, .fixedBrush, .ramp, CGFloat, StaticString, String, UInt (+1 more)

### Community 23 - "CodingKeys"
Cohesion: 0.08
Nodes (30): CodingKey, Encoder, CodingKeys, brush, color, composite, elements, fill (+22 more)

### Community 24 - ".transparentFormat"
Cohesion: 0.16
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 25 - "PerfBaselineTests"
Cohesion: 0.20
Nodes (8): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UIImage, UInt64

### Community 26 - ".withStructureUndo"
Cohesion: 0.11
Nodes (15): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+7 more)

### Community 27 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 28 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 29 - "VectorSample"
Cohesion: 0.21
Nodes (9): VectorSample, Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange, Double (+1 more)

### Community 30 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 31 - ".stampStroke"
Cohesion: 0.17
Nodes (13): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, CGFloat, CGPoint (+5 more)

### Community 32 - "layers"
Cohesion: 0.20
Nodes (10): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+2 more)

### Community 33 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+5 more)

### Community 34 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 35 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (12): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+4 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.11
Nodes (19): Gesture, AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed (+11 more)

### Community 39 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 40 - "ShapeDetector"
Cohesion: 0.25
Nodes (7): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int

### Community 41 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 42 - "Coordinator"
Cohesion: 0.16
Nodes (13): Coordinator, CanvasManager, Date, NSLayoutConstraint, TimeInterval, Timer, UILongPressGestureRecognizer, UIPanGestureRecognizer (+5 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 44 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 45 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 46 - "UIKit"
Cohesion: 0.17
Nodes (4): Combine, PhotosUI, SwiftUI, UIKit

### Community 47 - ".stampCircle"
Cohesion: 0.22
Nodes (11): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+3 more)

### Community 48 - "SelectionMode"
Cohesion: 0.12
Nodes (16): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage, SelectPanel (+8 more)

### Community 49 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 50 - "DrawingView"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 51 - "Foundation"
Cohesion: 0.14
Nodes (6): CoreGraphics, Foundation, Notification.Name, AppVersion, .versionString, String

### Community 52 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 53 - "ProjectManifest"
Cohesion: 0.38
Nodes (14): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor, Date (+6 more)

### Community 54 - "LayerStackListView.Coordinator"
Cohesion: 0.17
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UIGestureRecognizer, UILongPressGestureRecognizer, UIView (+1 more)

### Community 55 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 56 - "ProjectSummary"
Cohesion: 0.19
Nodes (10): ProjectSummary, Date, UIImage, GalleryTileView, .body, Void, GalleryView, .body (+2 more)

### Community 57 - "Coordinator"
Cohesion: 0.24
Nodes (9): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+1 more)

### Community 58 - "LayerRowModel"
Cohesion: 0.20
Nodes (9): LayerRowModel, .folderID, Bool, Context, Double, String, UIImage, UIPinchGestureRecognizer (+1 more)

### Community 59 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 60 - ".load"
Cohesion: 0.26
Nodes (6): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, URL

### Community 61 - ".hasContentBeneath"
Cohesion: 0.27
Nodes (5): DabLattice, .range, CGFloat, CGRect, ClosedRange

### Community 62 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 63 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 64 - ".makeUIView"
Cohesion: 0.21
Nodes (5): CanvasView, Context, Coordinator, LayerTransform, UIViewRepresentable

### Community 65 - "Known Issues"
Cohesion: 0.17
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 67 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 69 - "Refactor baseline (Stage 0)"
Cohesion: 0.17
Nodes (12): After Stage 0's additions, As measured, 2026-07-28, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Live stroke cost, Other paths (+4 more)

### Community 70 - "SaveSnapshot"
Cohesion: 0.36
Nodes (10): CelContent, LayerContent, SaveSnapshot, Bool, CanvasManager, CGSize, Double, Int (+2 more)

### Community 71 - ".handleTransformGesture"
Cohesion: 0.29
Nodes (4): CGPoint, CGSize, Void, Recognizer

### Community 72 - ".panelView"
Cohesion: 0.22
Nodes (8): .panelView, FillSettingsPanel, .body, CanvasManager, Color, StubToolPanel, .body, String

### Community 73 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 74 - "Corner"
Cohesion: 0.22
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 75 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (5): CanvasManager, Bool, CGFloat, CGSize, UIImage

### Community 76 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 77 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 78 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 79 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 80 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 81 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 82 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 83 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 84 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 85 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 86 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 87 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 88 - "AppliedTool"
Cohesion: 0.33
Nodes (4): AppliedTool, CGFloat, Color, Double

### Community 89 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 91 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 92 - "LayerKind"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 93 - ".tableView"
Cohesion: 0.50
Nodes (3): IndexPath, CGFloat, UISwipeActionsConfiguration

### Community 94 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 95 - "LayerTransform"
Cohesion: 0.50
Nodes (3): LayerTransform, CGFloat, CGPoint

### Community 99 - "Suite parallelisation (2026-07-29, between Stage 3 and Stage 4)"
Cohesion: 0.67
Nodes (3): Counting caveat, if you are reading a text log, Suite parallelisation (2026-07-29, between Stage 3 and Stage 4), What this means for later stages

## Knowledge Gaps
- **374 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+369 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VectorSample` connect `VectorSample` to `VectorEraserHybridLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `CanvasManager`, `StrokeGeometry`, `VectorEraserLogicTests`, `StrokeCanvasView`, `ShapeGeometry`, `Brush`, `ShapeDetectorLogicTests`, `StrokeGeometryLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `layers`, `StrokeSpatialIndex`, `ShapeDetector`, `Coordinator`, `ProjectSaveLogicTests`, `Foundation`, `.hasContentBeneath`, `CanvasManager`, `.reconcileLayers`?**
  _High betweenness centrality (0.153) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ColorPickerPanel`, `CanvasManager`, `ShapeGeometry`, `CanvasManager`, `Brush`, `.withStructureUndo`, `MetalFillEngine`, `RasterLayerTexture`, `VectorSample`, `layers`, `CanvasManager`, `PerfMonitor`, `UIKit`, `SelectionMode`, `UndoHistory`, `.setCanvasPadding`, `VectorEraserMode`, `Tool`, `LayerKind`, `CopiedCel`?**
  _High betweenness centrality (0.152) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `.manager` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `ProjectBackupManager`, `BrushEngineLogicTests`, `ProjectSaveLogicTests`, `VectorEraserLogicTests`, `UIKit`, `ShapeDetectorLogicTests`, `StrokeGeometryLogicTests`, `PerfBaselineTests`?**
  _High betweenness centrality (0.121) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `VectorCanvas` (e.g. with `.testVectorLayerRenderCostAndMemory()` and `.parityOfGeometricSplit()`) actually correct?**
  _`VectorCanvas` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._