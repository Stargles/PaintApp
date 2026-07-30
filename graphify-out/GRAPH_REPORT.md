# Graph Report - PaintApp-simui  (2026-07-30)

## Corpus Check
- 116 files · ~188,512 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2601 nodes · 7014 edges · 113 communities (106 shown, 7 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 880 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9e45b877`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
- ProjectBackupManager
- .manager
- Coordinator
- TimelineRowView
- ColorPickerPanel
- CanvasManager
- FloatingPieceOverlayView
- CanvasManager
- VectorEraserLogicTests
- ShapeOverlayView
- StrokeCanvasView
- BrushEngineLogicTests
- VectorSample
- Vector Eraser — Design Plan
- VectorStroke
- VectorCanvas
- ShapeDetectorLogicTests
- ShapeGeometry
- StrokeGeometryLogicTests
- .transparentFormat
- PerfBaselineTests
- StrokeSpatialIndex
- CanvasManager
- .withStructureUndo
- MetalFillEngine
- CanvasManager
- FillParams
- TouchCountRecognizer
- RasterLayerTexture
- BrushStamper
- VectorElement
- layers
- StrokeSettingsPanel
- ActivePanel
- UIKit
- Brush
- VectorEraser
- View
- LayerStackCell
- ShapeDetector
- ProjectSaveLogicTests
- SelectionOverlayView
- .recordUndo
- AnimationTimeline
- DrawingView
- PerfMonitor
- Codable
- LayerStackRow
- CodingKeys
- Color
- .stampCircle
- CodingKeys
- Foundation
- XCTest
- CanvasSizePickerView
- SideToolbar
- bash
- UndoHistory
- LayerStackListView.Coordinator
- LayerStackListView
- ContentView
- CanvasManager
- ProjectSummary
- Known Issues
- StrokeStabilizer
- Coordinator
- LayerRowModel
- SelectPanel
- Refactor baseline (Stage 0)
- SaveSnapshot
- .load
- .panelView
- Identifiable
- agent
- BrushShape
- ActionsMenu
- PaintSoftware - iPad Drawing and Animation App
- Layer
- VectorEraserMode
- BrushSettingsPanel
- EraserSettingsPanel
- Usage Guide
- PaintApp
- command
- CutOutcome
- Multi-Session Protocol
- ProjectStore.swift
- VectorScratchRole
- Atomic
- parallel_test.sh
- Corner
- Edge
- LayerKind
- orchestrator
- worker-bugfix
- worker-feature
- worker-integration
- worker-research
- worker-test
- CopiedCel
- LayerTransform
- AppVersion
- cleanup_session.sh
- screenshot.sh
- .init
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
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `Gesture` --references--> `VectorSample`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/ShapeGeometry.swift

## Import Cycles
- None detected.

## Communities (113 total, 7 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (23): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+15 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (53): CaseIterable, CustomStringConvertible, Kind, line, oval, rectangle, Backdrop, fill (+45 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "Coordinator"
Cohesion: 0.05
Nodes (39): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+31 more)

### Community 5 - "TimelineRowView"
Cohesion: 0.07
Nodes (43): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+35 more)

### Community 6 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (45): Hashable, CelLocation, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+37 more)

### Community 7 - "CanvasManager"
Cohesion: 0.05
Nodes (38): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+30 more)

### Community 8 - "FloatingPieceOverlayView"
Cohesion: 0.06
Nodes (37): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+29 more)

### Community 9 - "CanvasManager"
Cohesion: 0.07
Nodes (34): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+26 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.14
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 11 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (25): StrokeInput, CGFloat, CGPoint, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+17 more)

### Community 13 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CGFloat, CodableColor, Data, Double, Int, String (+4 more)

### Community 14 - "VectorSample"
Cohesion: 0.15
Nodes (12): VectorSample, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat, CGPoint (+4 more)

### Community 15 - "Vector Eraser — Design Plan"
Cohesion: 0.05
Nodes (39): 1. Give the dab lattice a reproducible anchor — the unlock, 2. Then, Carry-overs still open, Environment correction (important, saves 10 minutes), Mode 1, as it actually is, Multi-session protocol reminder, Next session: start here, Notes worth not re-deriving (+31 more)

### Community 16 - "VectorStroke"
Cohesion: 0.10
Nodes (29): Encoder, CodableColor, .uiColor, ElementData, fill, image, stroke, ImageRef (+21 more)

### Community 17 - "VectorCanvas"
Cohesion: 0.15
Nodes (12): Bool, CGAffineTransform, CGFloat, CGPoint, CGRect, CGSize, ClosedRange, VectorCanvas (+4 more)

### Community 18 - "ShapeDetectorLogicTests"
Cohesion: 0.18
Nodes (5): ShapeDetectorLogicTests, CGFloat, CGPoint, CGRect, Int

### Community 19 - "ShapeGeometry"
Cohesion: 0.11
Nodes (17): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+9 more)

### Community 20 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (5): StrokeGeometryLogicTests, .ramp, StaticString, String, UInt

### Community 21 - ".transparentFormat"
Cohesion: 0.16
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 22 - "PerfBaselineTests"
Cohesion: 0.20
Nodes (8): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UIImage, UInt64

### Community 23 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (15): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+7 more)

### Community 24 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 25 - ".withStructureUndo"
Cohesion: 0.11
Nodes (15): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+7 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "CanvasManager"
Cohesion: 0.17
Nodes (14): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+6 more)

### Community 28 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 29 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 30 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 31 - "BrushStamper"
Cohesion: 0.19
Nodes (14): AnyObject, BrushStamper, DabRNG, Sample, Bool, CGBlendMode, CGFloat, CGPoint (+6 more)

### Community 32 - "VectorElement"
Cohesion: 0.13
Nodes (18): kind, Kind, fill, image, stroke, CGContext, Int, LayerTransform (+10 more)

### Community 33 - "layers"
Cohesion: 0.25
Nodes (5): .activeLayerIsVector, CanvasManager, Bool, Int, layers

### Community 34 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 35 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 36 - "UIKit"
Cohesion: 0.13
Nodes (6): Combine, ThumbnailRenderer, PhotosUI, QuartzCore, SwiftUI, UIKit

### Community 37 - "Brush"
Cohesion: 0.16
Nodes (12): Equatable, Brush, BrushDynamics, BrushGrain, Bool, CGFloat, Double, UUID (+4 more)

### Community 38 - "VectorEraser"
Cohesion: 0.24
Nodes (8): Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange, Double, VectorEraser

### Community 39 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 41 - "ShapeDetector"
Cohesion: 0.27
Nodes (7): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int

### Community 42 - "ProjectSaveLogicTests"
Cohesion: 0.19
Nodes (9): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String (+1 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 44 - ".recordUndo"
Cohesion: 0.14
Nodes (8): CanvasManager, Bool, CGFloat, CGSize, UIImage, String, UUID, Void

### Community 45 - "AnimationTimeline"
Cohesion: 0.12
Nodes (16): AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed, .maxTimelineHeight (+8 more)

### Community 46 - "DrawingView"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 48 - "Codable"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 49 - "LayerStackRow"
Cohesion: 0.12
Nodes (14): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+6 more)

### Community 50 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 51 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 52 - ".stampCircle"
Cohesion: 0.25
Nodes (9): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, CGFloat, CGPoint (+1 more)

### Community 53 - "CodingKeys"
Cohesion: 0.12
Nodes (17): CodingKey, CodingKeys, brush, color, composite, elements, fill, fills (+9 more)

### Community 54 - "Foundation"
Cohesion: 0.15
Nodes (3): CoreGraphics, Foundation, Notification.Name

### Community 56 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 57 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 58 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 59 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 60 - "LayerStackListView.Coordinator"
Cohesion: 0.20
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UIGestureRecognizer, UIView, UITableViewDelegate

### Community 61 - "LayerStackListView"
Cohesion: 0.16
Nodes (8): IndexPath, LayerStackListView, CGFloat, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView

### Community 62 - "ContentView"
Cohesion: 0.20
Nodes (9): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+1 more)

### Community 63 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 64 - "ProjectSummary"
Cohesion: 0.21
Nodes (9): ProjectSummary, Date, GalleryTileView, .body, Void, GalleryView, .body, CanvasManager (+1 more)

### Community 65 - "Known Issues"
Cohesion: 0.17
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 66 - "StrokeStabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 67 - "Coordinator"
Cohesion: 0.32
Nodes (6): Coordinator, CanvasManager, Int, Set, UUID, UITableViewDiffableDataSource

### Community 68 - "LayerRowModel"
Cohesion: 0.24
Nodes (8): LayerRowModel, .folderID, Bool, Double, String, UIImage, UILongPressGestureRecognizer, UIPinchGestureRecognizer

### Community 69 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 70 - "Refactor baseline (Stage 0)"
Cohesion: 0.17
Nodes (12): After Stage 0's additions, As measured, 2026-07-28, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Live stroke cost, Other paths (+4 more)

### Community 71 - "SaveSnapshot"
Cohesion: 0.38
Nodes (10): CelContent, LayerContent, SaveSnapshot, Bool, CGSize, Double, Int, String (+2 more)

### Community 72 - ".load"
Cohesion: 0.38
Nodes (3): ProjectStore, .projectsDirectory, URL

### Community 73 - ".panelView"
Cohesion: 0.22
Nodes (8): .panelView, FillSettingsPanel, .body, CanvasManager, Color, StubToolPanel, .body, String

### Community 74 - "Identifiable"
Cohesion: 0.20
Nodes (10): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+2 more)

### Community 75 - "agent"
Cohesion: 0.20
Nodes (9): agent, worker-ui, model, plugin, $schema, description, mode, model (+1 more)

### Community 76 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 77 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 78 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 79 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 80 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 81 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 83 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 84 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 85 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 86 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 87 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 88 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 89 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 90 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 92 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 93 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 94 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 95 - "LayerKind"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 96 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 97 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 98 - "worker-feature"
Cohesion: 0.50
Nodes (4): worker-feature, description, mode, model

### Community 99 - "worker-integration"
Cohesion: 0.50
Nodes (4): worker-integration, description, mode, model

### Community 100 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 101 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

### Community 102 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 103 - "LayerTransform"
Cohesion: 0.50
Nodes (3): LayerTransform, CGFloat, CGPoint

### Community 104 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 108 - "Suite parallelisation (2026-07-29, between Stage 3 and Stage 4)"
Cohesion: 0.67
Nodes (3): Counting caveat, if you are reading a text log, Suite parallelisation (2026-07-29, between Stage 3 and Stage 4), What this means for later stages

## Knowledge Gaps
- **371 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+366 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VectorSample` connect `VectorSample` to `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `VectorEraserLogicTests`, `StrokeCanvasView`, `BrushEngineLogicTests`, `VectorStroke`, `VectorCanvas`, `ShapeDetectorLogicTests`, `ShapeGeometry`, `StrokeGeometryLogicTests`, `PerfBaselineTests`, `StrokeSpatialIndex`, `RasterLayerTexture`, `layers`, `Brush`, `VectorEraser`, `ProjectSaveLogicTests`, `Codable`, `Foundation`, `CanvasManager`?**
  _High betweenness centrality (0.156) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `layers`, `UIKit`, `Brush`, `ColorPickerPanel`, `CopiedCel`, `CanvasManager`, `UndoHistory`, `.recordUndo`, `VectorSample`, `PerfMonitor`, `VectorEraserMode`, `ShapeGeometry`, `CanvasManager`, `.withStructureUndo`, `MetalFillEngine`, `CanvasManager`, `RasterLayerTexture`, `LayerKind`?**
  _High betweenness centrality (0.153) - this node is a cross-community bridge._
- **Why does `Brush` connect `Brush` to `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `VectorEraserLogicTests`, `StrokeCanvasView`, `BrushEngineLogicTests`, `VectorSample`, `VectorStroke`, `VectorCanvas`, `StrokeGeometryLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `BrushStamper`, `StrokeSettingsPanel`, `VectorEraser`, `Codable`, `SaveSnapshot`, `.load`, `Identifiable`, `BrushShape`, `BrushSettingsPanel`?**
  _High betweenness centrality (0.118) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `VectorCanvas` (e.g. with `.testVectorLayerRenderCostAndMemory()` and `.parityOfGeometricSplit()`) actually correct?**
  _`VectorCanvas` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 10 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._