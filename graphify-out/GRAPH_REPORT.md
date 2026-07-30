# Graph Report - PaintApp-perfsplit  (2026-07-30)

## Corpus Check
- 117 files · ~199,559 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2646 nodes · 7160 edges · 108 communities (102 shown, 6 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 893 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `fbd56377`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
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
- ShapeGeometry
- BrushBlendMode
- StrokeCanvasView
- StrokeGeometryLogicTests
- CanvasSizePickerView
- ShapeDetectorLogicTests
- FloatingPiece
- .transparentFormat
- CodingKeys
- Coordinator
- CanvasManager
- CanvasManager
- VectorElement
- MetalFillEngine
- VectorSample
- .stampStroke
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
- ShapeDetector
- LayerStackCell
- UIView
- ProjectSaveLogicTests
- .makeUIView
- SelectionOverlayView
- .stampCircle
- RasterLayerTexture
- .renderToUIImage
- UIKit
- Foundation
- DrawingView
- PerfMonitor
- CodingKeys
- Color
- LayerRowModel
- Vector Eraser — Design Plan
- Coordinator
- ProjectManifest
- SideToolbar
- VectorStroke
- XCTest
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- Refactor baseline (Stage 0)
- CanvasManager
- VectorEraserMode
- UndoHistory
- CanvasHostView
- LayerKind
- Vector Eraser — Resume Here
- Known Issues
- StrokeStabilizer
- CanvasManager
- LayerStackRow
- GalleryView
- SelectPanel
- PaintSoftware - iPad Drawing and Animation App
- Multi-Session Protocol
- .panelView
- .canvasTouchCountChanged
- Corner
- ActionsMenu
- .setCanvasPadding
- BrushSettingsPanel
- EraserSettingsPanel
- Usage Guide
- CutOutcome
- ProjectStore.swift
- VectorScratchRole
- AppliedTool
- ProjectVersionsView
- Atomic
- 11. Moving vector rendering to the GPU
- parallel_test.sh
- Stage 5 (2026-07-29) — after
- 1. The central problem
- .tableView
- AppVersion
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `VectorCanvas` - 101 edges
2. `VectorSample` - 88 edges
3. `CanvasManager` - 86 edges
4. `ShapeGeometry` - 73 edges
5. `Coordinator` - 70 edges
6. `Brush` - 63 edges
7. `layers` - 60 edges
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

## Communities (108 total, 6 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (23): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+15 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+41 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.07
Nodes (34): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+26 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (39): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+31 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+30 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (37): Hashable, CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .effectiveLoopRange, .isFillInAdjustableState, .isShapeFollowingFinger (+29 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometry"
Cohesion: 0.12
Nodes (13): Equatable, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat, CGPoint (+5 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.09
Nodes (22): kind, Kind, fill, image, stroke, CGAffineTransform, CGContext, CGPoint (+14 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.15
Nodes (12): BrushEngineLogicTests, Any, CGFloat, CodableColor, Data, Double, Int, String (+4 more)

### Community 13 - "ShapeGeometry"
Cohesion: 0.09
Nodes (27): CaseIterable, Edge, bottom, left, right, top, FollowFrame, Kind (+19 more)

### Community 14 - "BrushBlendMode"
Cohesion: 0.07
Nodes (27): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+19 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (22): NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas, Bool (+14 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (9): Deterministic, StrokeGeometryLogicTests, .fixedBrush, .ramp, CGFloat, StaticString, String, UInt (+1 more)

### Community 17 - "CanvasSizePickerView"
Cohesion: 0.06
Nodes (28): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+20 more)

### Community 18 - "ShapeDetectorLogicTests"
Cohesion: 0.17
Nodes (5): ShapeDetectorLogicTests, CGFloat, CGPoint, CGRect, Int

### Community 19 - "FloatingPiece"
Cohesion: 0.08
Nodes (29): FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform, Selection (+21 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.15
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 21 - "CodingKeys"
Cohesion: 0.08
Nodes (30): CodingKey, Encoder, CodingKeys, brush, color, composite, elements, fill (+22 more)

### Community 22 - "Coordinator"
Cohesion: 0.11
Nodes (17): Coordinator, CanvasManager, CGPoint, CGSize, Date, LayerTransform, NSLayoutConstraint, TimeInterval (+9 more)

### Community 23 - "CanvasManager"
Cohesion: 0.12
Nodes (10): .currentFrame, .currentLayerIndex, String, UUID, Void, CanvasManager, Bool, Int (+2 more)

### Community 24 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 25 - "VectorElement"
Cohesion: 0.14
Nodes (17): Identifiable, CodableColor, .uiColor, Bool, CGPath, CGRect, Data, Double (+9 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "VectorSample"
Cohesion: 0.21
Nodes (10): Brush, VectorSample, Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange (+2 more)

### Community 28 - ".stampStroke"
Cohesion: 0.16
Nodes (14): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, CGFloat, CGPoint (+6 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.24
Nodes (7): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UInt64

### Community 30 - "layers"
Cohesion: 0.21
Nodes (7): .activeLayerIsVector, Bool, CanvasManager, Bool, Int, Void, layers

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.19
Nodes (12): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+4 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (12): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+4 more)

### Community 35 - "LayerFolder"
Cohesion: 0.11
Nodes (14): CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String, UUID (+6 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.11
Nodes (19): Gesture, AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed (+11 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+3 more)

### Community 40 - ".load"
Cohesion: 0.21
Nodes (15): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CGSize (+7 more)

### Community 41 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 42 - "ShapeDetector"
Cohesion: 0.25
Nodes (7): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int

### Community 43 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 44 - "UIView"
Cohesion: 0.13
Nodes (18): FloatingTransform, .effectiveScaleX, .effectiveScaleY, Kind, rotate, scale, LayerTransform, .effectiveScaleX (+10 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.19
Nodes (9): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String (+1 more)

### Community 46 - ".makeUIView"
Cohesion: 0.16
Nodes (6): LayerHostView, CanvasView, Context, Coordinator, UIImageView, UIViewRepresentable

### Community 47 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 48 - ".stampCircle"
Cohesion: 0.20
Nodes (11): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+3 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.21
Nodes (10): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+2 more)

### Community 50 - ".renderToUIImage"
Cohesion: 0.15
Nodes (8): StrokeInput, CGFloat, CGPoint, UITouch, UIView, CGSize, UIImage, UIImage

### Community 51 - "UIKit"
Cohesion: 0.18
Nodes (6): Combine, ThumbnailRenderer, PhotosUI, QuartzCore, SwiftUI, UIKit

### Community 52 - "Foundation"
Cohesion: 0.13
Nodes (6): CoreGraphics, Foundation, LayerTransform, CGFloat, CGPoint, Notification.Name

### Community 53 - "DrawingView"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 55 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 56 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "LayerRowModel"
Cohesion: 0.17
Nodes (10): LayerRowModel, .folderID, Bool, Context, Double, String, UIGestureRecognizer, UIImage (+2 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.11
Nodes (18): 10. Open items (not blocking Phase 0–1), 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions), 3.2 `StrokeSpatialIndex`, 3. Shared geometry foundation (+10 more)

### Community 59 - "Coordinator"
Cohesion: 0.22
Nodes (10): NSObject, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID (+2 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.38
Nodes (14): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor, Date (+6 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 62 - "VectorStroke"
Cohesion: 0.23
Nodes (11): Codable, DabLattice, .range, StrokeComposite, erase, paint, CGFloat, ClosedRange (+3 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.27
Nodes (8): ObjectTransformOverlayView, CGPoint, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "LayerStackListView.Coordinator"
Cohesion: 0.20
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UILongPressGestureRecognizer, UIView, UIGestureRecognizerDelegate (+1 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.13
Nodes (15): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full-suite baseline, Garbage collection was the accumulating term — fixed, Performance baseline (+7 more)

### Community 68 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 69 - "VectorEraserMode"
Cohesion: 0.14
Nodes (13): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+5 more)

### Community 70 - "UndoHistory"
Cohesion: 0.23
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "LayerKind"
Cohesion: 0.15
Nodes (11): Layer, Bool, Cel, Double, String, UIImage, UUID, LayerKind (+3 more)

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

### Community 78 - "GalleryView"
Cohesion: 0.21
Nodes (7): GalleryTileView, .body, Void, GalleryView, .body, CanvasManager, Void

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.18
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 81 - "Multi-Session Protocol"
Cohesion: 0.20
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 82 - ".panelView"
Cohesion: 0.22
Nodes (8): .panelView, FillSettingsPanel, .body, CanvasManager, Color, StubToolPanel, .body, String

### Community 83 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 84 - "Corner"
Cohesion: 0.22
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 85 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 86 - ".setCanvasPadding"
Cohesion: 0.36
Nodes (5): CanvasManager, Bool, CGFloat, CGSize, UIImage

### Community 87 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 88 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 89 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 90 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 91 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 92 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 93 - "AppliedTool"
Cohesion: 0.33
Nodes (4): AppliedTool, CGFloat, Color, Double

### Community 94 - "ProjectVersionsView"
Cohesion: 0.47
Nodes (4): ProjectVersionsView, RecentlyDeletedView, .body, Void

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 96 - "11. Moving vector rendering to the GPU"
Cohesion: 0.33
Nodes (6): 11. Moving vector rendering to the GPU, The number, The z-order optimisation, when it is needed, What is already on the GPU, What Phase 2 did to keep the door open, Why not now

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "Stage 5 (2026-07-29) — after"
Cohesion: 0.40
Nodes (5): Full suite, Live stroke cost, Other paths, Stage 5 (2026-07-29) — after, Three things later work should carry forward

### Community 99 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 100 - ".tableView"
Cohesion: 0.50
Nodes (3): IndexPath, CGFloat, UISwipeActionsConfiguration

### Community 101 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

## Knowledge Gaps
- **391 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+386 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `LayerFolder`, `VectorEraserMode`, `UndoHistory`, `LayerKind`, `CanvasManager`, `ShapeGeometry`, `RasterLayerTexture`, `UIKit`, `FloatingPiece`, `PerfMonitor`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `VectorSample`, `layers`?**
  _High betweenness centrality (0.149) - this node is a cross-community bridge._
- **Why does `VectorSample` connect `VectorSample` to `VectorEraserHybridLogicTests`, `CanvasManager`, `StrokeGeometry`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `ShapeDetectorLogicTests`, `Coordinator`, `CanvasManager`, `VectorElement`, `.stampStroke`, `PerfBaselineTests`, `StrokeSpatialIndex`, `ShapeDetector`, `ProjectSaveLogicTests`, `.makeUIView`, `Foundation`, `VectorStroke`, `CanvasManager`?**
  _High betweenness centrality (0.142) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `.manager` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `ProjectBackupManager`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `ProjectSaveLogicTests`, `StrokeGeometryLogicTests`, `ShapeDetectorLogicTests`, `PerfBaselineTests`?**
  _High betweenness centrality (0.117) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `VectorCanvas` (e.g. with `.testEraseHeavyVectorLayerCostAndMemory()` and `.testVectorLayerRenderCostAndMemory()`) actually correct?**
  _`VectorCanvas` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._