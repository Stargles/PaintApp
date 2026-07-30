# Graph Report - PaintApp-veraser34  (2026-07-30)

## Corpus Check
- 115 files · ~183,250 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2572 nodes · 6957 edges · 100 communities (94 shown, 6 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 893 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `fd7c2585`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- XCUIApplication
- ProjectBackupManager
- VectorEraserHybridLogicTests
- .manager
- Coordinator
- TimelineRowView
- FloatingPieceOverlayView
- ColorPickerPanel
- CanvasManager
- CanvasManager
- bash
- StrokeCanvasView
- ShapeOverlayView
- VectorEraserLogicTests
- VectorSample
- VectorCanvas
- StrokeGeometryLogicTests
- BrushEngineLogicTests
- Vector Eraser — Design Plan
- VectorStroke
- ShapeDetectorLogicTests
- ShapeGeometry
- .transparentFormat
- CanvasManager
- .withStructureUndo
- MetalFillEngine
- layers
- PerfBaselineTests
- FillParams
- RasterLayerTexture
- CanvasManager
- TouchCountRecognizer
- StrokeSpatialIndex
- Brush
- StrokeSettingsPanel
- BrushStamper
- ActivePanel
- Identifiable
- BrushDynamics
- LayerStackCell
- LayerOptionsPanel
- UIKit
- ShapeDetector
- SelectionOverlayView
- ContentView
- .stampCircle
- LayerRowModel
- .beginCanvasEdit
- DrawingView
- View
- PerfMonitor
- VectorImageElement
- Color
- AnimationTimeline
- Codable
- LayerStackRow
- CodingKeys
- Coordinator
- ProjectSaveLogicTests
- CanvasSizePickerView
- SideToolbar
- Foundation
- ProjectSummary
- LayerStackListView.Coordinator
- CodingKeys
- XCTest
- .load
- CanvasManager
- UndoHistory
- Known Issues
- StrokeStabilizer
- Refactor baseline (Stage 0)
- SaveSnapshot
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
- Atomic
- parallel_test.sh
- Corner
- Edge
- LayerKind
- CopiedCel
- LayerTransform
- AppVersion
- cleanup_session.sh
- screenshot.sh
- Suite parallelisation (2026-07-29, between Stage 3 and Stage 4)
- graphify-guard.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `VectorCanvas` - 96 edges
2. `CanvasManager` - 86 edges
3. `VectorSample` - 83 edges
4. `ShapeGeometry` - 73 edges
5. `Coordinator` - 70 edges
6. `Brush` - 61 edges
7. `layers` - 60 edges
8. `ProjectBackupManager` - 56 edges
9. `StrokeGeometryLogicTests` - 52 edges
10. `RasterLayerTexture` - 51 edges

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

## Communities (100 total, 6 thin omitted)

### Community 0 - "XCUIApplication"
Cohesion: 0.09
Nodes (16): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+8 more)

### Community 1 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 2 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+41 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "Coordinator"
Cohesion: 0.05
Nodes (36): CanvasHostView, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, Void, LayerHostView, AppliedTool (+28 more)

### Community 5 - "TimelineRowView"
Cohesion: 0.07
Nodes (42): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 6 - "FloatingPieceOverlayView"
Cohesion: 0.06
Nodes (37): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+29 more)

### Community 7 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (39): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+31 more)

### Community 8 - "CanvasManager"
Cohesion: 0.06
Nodes (34): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+26 more)

### Community 9 - "CanvasManager"
Cohesion: 0.07
Nodes (37): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+29 more)

### Community 10 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 11 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (31): StrokeInput, CGFloat, CGPoint, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+23 more)

### Community 12 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 13 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 14 - "VectorSample"
Cohesion: 0.14
Nodes (13): Equatable, VectorSample, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat (+5 more)

### Community 15 - "VectorCanvas"
Cohesion: 0.12
Nodes (23): kind, Kind, fill, image, stroke, Bool, CGFloat, CGRect (+15 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (9): Deterministic, StrokeGeometryLogicTests, .fixedBrush, .ramp, CGFloat, StaticString, String, UInt (+1 more)

### Community 17 - "BrushEngineLogicTests"
Cohesion: 0.15
Nodes (12): BrushEngineLogicTests, Any, CGFloat, CodableColor, Data, Double, Int, String (+4 more)

### Community 18 - "Vector Eraser — Design Plan"
Cohesion: 0.05
Nodes (39): 1. Nothing has ever been run in the simulator UI, 2. Give the dab lattice a reproducible anchor — the unlock, 3. Then, Carry-overs still open, Environment correction (important, saves 10 minutes), Mode 1, as it actually is, Multi-session protocol reminder, Next session: start here (+31 more)

### Community 19 - "VectorStroke"
Cohesion: 0.11
Nodes (27): Encoder, CodableColor, .uiColor, ElementData, fill, image, stroke, ImageRef (+19 more)

### Community 20 - "ShapeDetectorLogicTests"
Cohesion: 0.18
Nodes (5): ShapeDetectorLogicTests, CGFloat, CGPoint, CGRect, Int

### Community 21 - "ShapeGeometry"
Cohesion: 0.11
Nodes (17): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+9 more)

### Community 22 - ".transparentFormat"
Cohesion: 0.15
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 23 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 24 - ".withStructureUndo"
Cohesion: 0.11
Nodes (15): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+7 more)

### Community 25 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 26 - "layers"
Cohesion: 0.18
Nodes (11): .activeLayerIsVector, Bool, CanvasManager, Bool, Int, Cel, .endFrame, Int (+3 more)

### Community 27 - "PerfBaselineTests"
Cohesion: 0.23
Nodes (8): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UIImage, UInt64

### Community 28 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 29 - "RasterLayerTexture"
Cohesion: 0.15
Nodes (11): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGSize, Int (+3 more)

### Community 30 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+5 more)

### Community 31 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 32 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (12): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+4 more)

### Community 33 - "Brush"
Cohesion: 0.23
Nodes (9): Brush, Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange, Double (+1 more)

### Community 34 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 35 - "BrushStamper"
Cohesion: 0.21
Nodes (13): AnyObject, BrushStamper, DabRNG, Sample, Bool, CGBlendMode, CGFloat, CGPoint (+5 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 37 - "Identifiable"
Cohesion: 0.09
Nodes (24): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+16 more)

### Community 38 - "BrushDynamics"
Cohesion: 0.13
Nodes (9): BrushDynamics, BrushGrain, Bool, CGFloat, Double, UUID, BrushLibrary, .customBrushesDirectory (+1 more)

### Community 39 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 40 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+10 more)

### Community 41 - "UIKit"
Cohesion: 0.14
Nodes (6): Combine, ThumbnailRenderer, PhotosUI, QuartzCore, SwiftUI, UIKit

### Community 42 - "ShapeDetector"
Cohesion: 0.27
Nodes (7): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int

### Community 43 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 44 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 45 - ".stampCircle"
Cohesion: 0.20
Nodes (10): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, CGFloat, CGPoint (+2 more)

### Community 46 - "LayerRowModel"
Cohesion: 0.14
Nodes (13): IndexPath, LayerRowModel, .folderID, Bool, CGFloat, Context, Double, String (+5 more)

### Community 47 - ".beginCanvasEdit"
Cohesion: 0.14
Nodes (7): CanvasManager, Bool, CGFloat, CGSize, UIImage, String, UUID

### Community 48 - "DrawingView"
Cohesion: 0.11
Nodes (16): Alignment, DrawingView, .panelAlignment, .panelView, Bool, CanvasManager, CGFloat, UUID (+8 more)

### Community 49 - "View"
Cohesion: 0.13
Nodes (16): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void, SelectPanel, .body (+8 more)

### Community 50 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, .body, PerfHUDOverlay, .body, .hudBody, .toggleButton (+7 more)

### Community 51 - "VectorImageElement"
Cohesion: 0.16
Nodes (9): transform, CGAffineTransform, CGContext, CGPoint, CGSize, LayerTransform, UIImage, .affineTransform (+1 more)

### Community 52 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 53 - "AnimationTimeline"
Cohesion: 0.12
Nodes (16): AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed, .maxTimelineHeight (+8 more)

### Community 54 - "Codable"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 55 - "LayerStackRow"
Cohesion: 0.12
Nodes (14): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+6 more)

### Community 56 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 57 - "Coordinator"
Cohesion: 0.20
Nodes (10): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+2 more)

### Community 58 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 59 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 60 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 61 - "Foundation"
Cohesion: 0.16
Nodes (3): CoreGraphics, Foundation, Notification.Name

### Community 62 - "ProjectSummary"
Cohesion: 0.19
Nodes (10): ProjectSummary, Date, UIImage, GalleryTileView, .body, Void, GalleryView, .body (+2 more)

### Community 63 - "LayerStackListView.Coordinator"
Cohesion: 0.18
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate (+1 more)

### Community 64 - "CodingKeys"
Cohesion: 0.13
Nodes (15): CodingKey, CodingKeys, brush, color, composite, elements, fill, fills (+7 more)

### Community 66 - ".load"
Cohesion: 0.28
Nodes (6): ProjectStore, .projectsDirectory, CanvasManager, MainActor, URL, Void

### Community 67 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 68 - "UndoHistory"
Cohesion: 0.23
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 69 - "Known Issues"
Cohesion: 0.17
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 70 - "StrokeStabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 71 - "Refactor baseline (Stage 0)"
Cohesion: 0.17
Nodes (12): After Stage 0's additions, As measured, 2026-07-28, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Live stroke cost, Other paths (+4 more)

### Community 72 - "SaveSnapshot"
Cohesion: 0.42
Nodes (9): CelContent, LayerContent, SaveSnapshot, Bool, CGSize, Double, Int, String (+1 more)

### Community 73 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 75 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 76 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 77 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 78 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 79 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 80 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 81 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 82 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 83 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 84 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 86 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 87 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 88 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 89 - "LayerKind"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 90 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 91 - "LayerTransform"
Cohesion: 0.50
Nodes (3): LayerTransform, CGFloat, CGPoint

### Community 92 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 95 - "Suite parallelisation (2026-07-29, between Stage 3 and Stage 4)"
Cohesion: 0.67
Nodes (3): Counting caveat, if you are reading a text log, Suite parallelisation (2026-07-29, between Stage 3 and Stage 4), What this means for later stages

## Knowledge Gaps
- **369 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+364 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VectorSample` connect `VectorSample` to `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `StrokeCanvasView`, `VectorEraserLogicTests`, `VectorCanvas`, `StrokeGeometryLogicTests`, `BrushEngineLogicTests`, `VectorStroke`, `ShapeDetectorLogicTests`, `ShapeGeometry`, `PerfBaselineTests`, `StrokeSpatialIndex`, `Brush`, `BrushStamper`, `.beginCanvasEdit`, `Codable`, `ProjectSaveLogicTests`, `Foundation`, `CanvasManager`?**
  _High betweenness centrality (0.169) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `LayerKind`, `Brush`, `UndoHistory`, `CopiedCel`, `UIKit`, `CanvasManager`, `VectorEraserMode`, `VectorSample`, `.beginCanvasEdit`, `PerfMonitor`, `Tool`, `ShapeGeometry`, `CanvasManager`, `.withStructureUndo`, `MetalFillEngine`, `layers`, `RasterLayerTexture`, `CanvasManager`?**
  _High betweenness centrality (0.154) - this node is a cross-community bridge._
- **Why does `Brush` connect `Brush` to `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `StrokeCanvasView`, `VectorEraserLogicTests`, `VectorSample`, `VectorCanvas`, `StrokeGeometryLogicTests`, `BrushEngineLogicTests`, `VectorStroke`, `PerfBaselineTests`, `StrokeSettingsPanel`, `BrushStamper`, `Identifiable`, `BrushDynamics`, `Codable`, `.load`, `SaveSnapshot`, `BrushSettingsPanel`?**
  _High betweenness centrality (0.109) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `VectorCanvas` (e.g. with `.testVectorLayerRenderCostAndMemory()` and `.parityOfGeometricSplit()`) actually correct?**
  _`VectorCanvas` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 10 INFERRED edges - model-reasoned connections that need verification._
- **Are the 59 inferred relationships involving `XCUIApplication` (e.g. with `.testAdjustingThresholdAfterFillReappliesToUncommittedFill()` and `.testDrawingOverFillCommitsFillAndStrokeUndoesFirst()`) actually correct?**
  _`XCUIApplication` has 59 INFERRED edges - model-reasoned connections that need verification._