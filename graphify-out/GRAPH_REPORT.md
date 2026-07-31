# Graph Report - animation-timeline-ui-fixes-59da33  (2026-07-30)

## Corpus Check
- 119 files · ~204,517 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2728 nodes · 7379 edges · 110 communities (101 shown, 9 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 906 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `44b0240f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- ParityScenario
- ProjectBackupManager
- .manager
- TimelineRowView
- ColorPickerPanel
- CanvasManager
- bash
- StrokeGeometry
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- ShapeDetectorLogicTests
- BrushDynamics
- StrokeCanvasView
- StrokeGeometryLogicTests
- ShapeGeometry
- ContentView
- VectorEraserHybridLogicTests
- CanvasManager
- .transparentFormat
- Coordinator
- CanvasSizePickerView
- CanvasManager
- MetalFillEngine
- VectorSample
- PlaybackBoundsCharacterizationTests
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- StrokeSpatialIndex
- LayerFolder
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- View
- .setUpGestures
- LayerStackCell
- UIView
- VectorStroke
- ProjectSaveLogicTests
- BrushBlendMode
- SelectionOverlayView
- .stampCircle
- RasterLayerTexture
- .init
- SwiftUI
- Foundation
- DrawingView
- PerfMonitor
- CodingKeys
- CodingKeys
- Color
- LayerRowModel
- Vector Eraser — Design Plan
- ProjectStore
- Codable
- SideToolbar
- UIKit
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- ShapeDetector
- Refactor baseline (Stage 0)
- CanvasManager
- VectorEraserMode
- UndoHistory
- CanvasHostView
- Layer
- Vector Eraser — Resume Here
- Known Issues
- StrokeStabilizer
- CanvasManager
- LayerStackRow
- ProjectSummary
- SelectPanel
- PaintSoftware - iPad Drawing and Animation App
- Multi-Session Protocol
- EraserSettingsPanel
- .canvasTouchCountChanged
- .centreStroke
- BrushShape
- ActionsMenu
- .refreshUndoRedoState
- BrushSettingsPanel
- StrokeGestureRecognizer
- Usage Guide
- Equatable
- ProjectStore.swift
- VectorScratchRole
- .init
- Tool
- Corner
- 11. Moving vector rendering to the GPU
- parallel_test.sh
- Stage 5 (2026-07-29) — after
- 1. The central problem
- Edge
- .registerRasterUndo
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- .placedImage

## God Nodes (most connected - your core abstractions)
1. `VectorCanvas` - 101 edges
2. `CanvasManager` - 92 edges
3. `VectorSample` - 88 edges
4. `ShapeGeometry` - 73 edges
5. `Coordinator` - 70 edges
6. `Brush` - 63 edges
7. `layers` - 62 edges
8. `ProjectBackupManager` - 56 edges
9. `RasterLayerTexture` - 52 edges
10. `StrokeGeometryLogicTests` - 52 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `Gesture` --references--> `VectorSample`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/ShapeGeometry.swift

## Import Cycles
- None detected.

## Communities (110 total, 9 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (23): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+15 more)

### Community 1 - "ParityScenario"
Cohesion: 0.09
Nodes (34): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+26 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (44): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+36 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (39): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+31 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (42): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .hasLoopBoundary (+34 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometry"
Cohesion: 0.13
Nodes (11): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat, CGPoint, CGRect (+3 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.09
Nodes (30): kind, Kind, fill, image, stroke, Bool, CGAffineTransform, CGContext (+22 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.31
Nodes (4): BrushEngineLogicTests, CGFloat, Int, UInt8

### Community 13 - "ShapeDetectorLogicTests"
Cohesion: 0.18
Nodes (5): ShapeDetectorLogicTests, CGFloat, CGPoint, CGRect, Int

### Community 14 - "BrushDynamics"
Cohesion: 0.16
Nodes (6): BrushDynamics, BrushGrain, Bool, CGFloat, Double, UUID

### Community 15 - "StrokeCanvasView"
Cohesion: 0.12
Nodes (22): StrokeInput, CGFloat, CGPoint, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+14 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (9): Deterministic, StrokeGeometryLogicTests, .fixedBrush, .ramp, CGFloat, StaticString, String, UInt (+1 more)

### Community 17 - "ShapeGeometry"
Cohesion: 0.11
Nodes (17): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+9 more)

### Community 18 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 19 - "VectorEraserHybridLogicTests"
Cohesion: 0.16
Nodes (14): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, CGFloat (+6 more)

### Community 20 - "CanvasManager"
Cohesion: 0.06
Nodes (37): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+29 more)

### Community 21 - ".transparentFormat"
Cohesion: 0.14
Nodes (18): CGPoint, IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint (+10 more)

### Community 22 - "Coordinator"
Cohesion: 0.09
Nodes (19): LayerHostView, AppliedTool, CanvasView, Coordinator, CanvasManager, CGFloat, CGPoint, CGSize (+11 more)

### Community 23 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 24 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 25 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 26 - "VectorSample"
Cohesion: 0.18
Nodes (11): Brush, VectorSample, Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange (+3 more)

### Community 27 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 28 - "PerfBaselineTests"
Cohesion: 0.08
Nodes (28): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, CGFloat (+20 more)

### Community 29 - "layers"
Cohesion: 0.19
Nodes (6): .activeLayerIsVector, CanvasManager, Bool, Int, Void, layers

### Community 30 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 31 - "TouchCountRecognizer"
Cohesion: 0.19
Nodes (10): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+2 more)

### Community 32 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 33 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (12): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+4 more)

### Community 34 - "LayerFolder"
Cohesion: 0.12
Nodes (14): CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String, UUID (+6 more)

### Community 35 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 36 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.07
Nodes (34): Content, Gesture, AnimationTimeline, .blockMenu, .body, .collapsedBar, .contentHeight, .dragHandle (+26 more)

### Community 38 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+3 more)

### Community 39 - ".load"
Cohesion: 0.35
Nodes (11): CelContent, LayerContent, SaveSnapshot, Bool, CanvasManager, CGSize, Double, Int (+3 more)

### Community 40 - "View"
Cohesion: 0.16
Nodes (19): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+11 more)

### Community 41 - ".setUpGestures"
Cohesion: 0.20
Nodes (7): UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 42 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 43 - "UIView"
Cohesion: 0.13
Nodes (18): FloatingTransform, .effectiveScaleX, .effectiveScaleY, Kind, rotate, scale, LayerTransform, .effectiveScaleX (+10 more)

### Community 44 - "VectorStroke"
Cohesion: 0.09
Nodes (32): Encoder, Identifiable, CodableColor, .uiColor, DabLattice, .range, ElementData, fill (+24 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "BrushBlendMode"
Cohesion: 0.22
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 48 - ".stampCircle"
Cohesion: 0.20
Nodes (10): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, CGFloat, CGPoint (+2 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.17
Nodes (11): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGSize, Int (+3 more)

### Community 51 - "SwiftUI"
Cohesion: 0.18
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 52 - "Foundation"
Cohesion: 0.09
Nodes (9): CoreGraphics, Foundation, LayerTransform, CGFloat, CGPoint, Notification.Name, AppVersion, .versionString (+1 more)

### Community 53 - "DrawingView"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 55 - "CodingKeys"
Cohesion: 0.12
Nodes (17): CodingKey, CodingKeys, brush, color, composite, elements, fill, fills (+9 more)

### Community 56 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 57 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 58 - "LayerRowModel"
Cohesion: 0.08
Nodes (31): IndexPath, Coordinator, DropTarget, between, onto, LayerRowModel, .folderID, LayerStackListView (+23 more)

### Community 59 - "Vector Eraser — Design Plan"
Cohesion: 0.11
Nodes (18): 10. Open items (not blocking Phase 0–1), 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions), 3.2 `StrokeSpatialIndex`, 3. Shared geometry foundation (+10 more)

### Community 60 - "ProjectStore"
Cohesion: 0.24
Nodes (6): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, URL

### Community 61 - "Codable"
Cohesion: 0.25
Nodes (19): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+11 more)

### Community 62 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 63 - "UIKit"
Cohesion: 0.11
Nodes (4): Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.27
Nodes (8): ObjectTransformOverlayView, CGPoint, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "ShapeDetector"
Cohesion: 0.27
Nodes (7): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.13
Nodes (15): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full-suite baseline, Garbage collection was the accumulating term — fixed, Performance baseline (+7 more)

### Community 68 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 69 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 73 - "Vector Eraser — Resume Here"
Cohesion: 0.15
Nodes (13): 1. Per-element Move, 2. The spatial index is rebuilt from scratch on every `invalidate()`, 3. GPU rendering, Carry-overs still open, Environment correction (important, saves 10 minutes), Mode 1, as it actually is, Multi-session protocol reminder, Next session: start here (+5 more)

### Community 74 - "Known Issues"
Cohesion: 0.17
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 76 - "CanvasManager"
Cohesion: 0.29
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 77 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 78 - "ProjectSummary"
Cohesion: 0.21
Nodes (9): ProjectSummary, Date, GalleryTileView, .body, Void, GalleryView, .body, CanvasManager (+1 more)

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.18
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 81 - "Multi-Session Protocol"
Cohesion: 0.20
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 84 - ".centreStroke"
Cohesion: 0.22
Nodes (6): Any, CodableColor, Data, Double, String, T

### Community 85 - "BrushShape"
Cohesion: 0.14
Nodes (14): CaseIterable, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+6 more)

### Community 86 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 87 - ".refreshUndoRedoState"
Cohesion: 0.20
Nodes (5): CanvasManager, Bool, CGFloat, CGSize, UIImage

### Community 88 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 89 - "StrokeGestureRecognizer"
Cohesion: 0.35
Nodes (6): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void

### Community 90 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 91 - "Equatable"
Cohesion: 0.25
Nodes (6): Equatable, CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 92 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 93 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 95 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 96 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 97 - "11. Moving vector rendering to the GPU"
Cohesion: 0.33
Nodes (6): 11. Moving vector rendering to the GPU, The number, The z-order optimisation, when it is needed, What is already on the GPU, What Phase 2 did to keep the door open, Why not now

### Community 98 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 99 - "Stage 5 (2026-07-29) — after"
Cohesion: 0.40
Nodes (5): Full suite, Live stroke cost, Other paths, Stage 5 (2026-07-29) — after, Three things later work should carry forward

### Community 100 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 101 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

## Knowledge Gaps
- **402 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+397 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VectorSample` connect `VectorSample` to `ParityScenario`, `CanvasManager`, `StrokeGeometry`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `ShapeGeometry`, `VectorEraserHybridLogicTests`, `Coordinator`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `VectorStroke`, `ProjectSaveLogicTests`, `RasterLayerTexture`, `Foundation`, `Codable`, `CanvasManager`, `.centreStroke`, `Equatable`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `LayerFolder`, `VectorEraserMode`, `UndoHistory`, `CanvasManager`, `RasterLayerTexture`, `ShapeGeometry`, `SwiftUI`, `CanvasManager`, `Codable`, `PerfMonitor`, `.refreshUndoRedoState`, `CanvasManager`, `MetalFillEngine`, `VectorSample`, `layers`, `Tool`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Why does `Brush` connect `VectorSample` to `ParityScenario`, `CanvasManager`, `StrokeGeometry`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `BrushDynamics`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `CanvasManager`, `Coordinator`, `PerfBaselineTests`, `StrokeSettingsPanel`, `.load`, `VectorStroke`, `BrushBlendMode`, `RasterLayerTexture`, `ProjectStore`, `Codable`, `BrushShape`, `BrushSettingsPanel`, `Equatable`?**
  _High betweenness centrality (0.116) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `VectorCanvas` (e.g. with `.testEraseHeavyVectorLayerCostAndMemory()` and `.testVectorLayerRenderCostAndMemory()`) actually correct?**
  _`VectorCanvas` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._