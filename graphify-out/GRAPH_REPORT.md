# Graph Report - .  (2026-07-30)

## Corpus Check
- 114 files · ~165,747 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2431 nodes · 6338 edges · 109 communities (97 shown, 12 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 873 edges (avg confidence: 0.8)
- Token cost: 126,480 input · 0 output

## Community Hubs (Navigation)
- Fill Tool UI Tests
- Shape Detection Engine
- Cel/Layer Manifest Types
- Canvas Test Fixtures
- Timeline Track UI
- Color Palette Model
- Agent Orchestration Config
- Canvas Manager Layer Ops
- Vector Element Kind
- Shape Overlay Handles
- Brush Model
- Stroke Geometry Primitives
- Stroke Input Handling
- Vector Layer Persistence
- Brush Engine Tests
- Canvas Edit Commit Flow
- CanvasManager Extension Files
- Stroke Geometry Tests
- Vector Eraser Tests
- Canvas Tool Coordinator
- Pixel Operations Utility
- Vector Layer State Queries
- Interactive Fill Flow
- Metal Fill Engine
- Structure Undo Gestures
- Brush Stamping Engine
- Undo Redo Canvas Ops
- Layer Tree Management
- Performance Baseline Tests
- GPU Fill Shader
- Stroke Gesture Recognizer
- Raster Layer Texture
- Stroke Spatial Index
- Top Toolbar UI
- Stroke Settings Panel
- Layer Host View
- Floating Piece Overlay
- Animation Timeline UI
- Layer Panel UI
- Project Save Tests
- Layer Stack Cell UI
- Transform Overlay Support
- Selection Mode Shapes
- Selection Overlay View
- Drawing View Root
- Dab Stamping Target
- App Root Navigation
- Performance HUD Overlay
- Project Manifest Fields
- Project Manifest Structs
- Canvas Size Picker
- Layer Row View Model
- Side Toolbar UI
- Layer Stack Drag Coordinator
- Layer Reorder Drag
- Object Transform Overlay
- Known Bugs List
- Pure Geometry Modules
- Undo History Model
- Canvas View Coordinator
- Vector Eraser Handoff Notes
- Project Save Snapshot
- Stroke Stabilizer
- Vector Eraser Sweep
- Vector Fill Path Color
- Vector Canvas Rendering
- Layer Stack Row Model
- Canvas Host View
- Gallery Browser UI
- Select Tool Panel
- App Feature List
- Vector Eraser Plan Sections
- Cel CRUD Characterization Tests
- Project Store Service
- Color Conversion Utility
- Actions Menu UI
- Layer Model
- Vector Eraser Mode Enum
- Color Math Utility
- Brush Settings Panel
- Eraser Settings Panel
- Move Transform Bottom Bar
- Deterministic Test RNG
- Extended Range Color Bug
- Multi-Session Deploy Workflow
- Graphify Usage Notes
- Tool Enum
- Codable Color Conversion
- Atomic Value Wrapper
- Parallel Test Script
- Layer Kind Enum
- Vector Element Display List
- Table Swipe Actions
- Copied Cel Model
- Layer Transform Model
- App Version Utility
- Cleanup Session Script
- Screenshot Script
- Brush Preset Reset Bug
- Duplicated Flip/Transform Code
- Graphify Guard Hook
- Fast Test Script
- Status Script
- Raster Ghost Layer Bug
- Smart Shapes Feature History
- Save-If-Needed Gap Bug
- Distort Warp Render Bug
- Adjust Panel Stubs

## God Nodes (most connected - your core abstractions)
1. `CanvasManager` - 86 edges
2. `ShapeGeometry` - 73 edges
3. `VectorCanvas` - 70 edges
4. `Coordinator` - 70 edges
5. `VectorSample` - 65 edges
6. `layers` - 60 edges
7. `ProjectBackupManager` - 56 edges
8. `StrokeGeometryLogicTests` - 52 edges
9. `RasterLayerTexture` - 50 edges
10. `Brush` - 47 edges

## Surprising Connections (you probably didn't know these)
- `§11 Moving vector rendering to the GPU` --conceptually_related_to--> `BrushStamper.stampStroke`  [INFERRED]
  VECTOR_ERASER_PLAN.md → REFACTOR_BASELINE.md
- `Worktree-per-session workflow` --conceptually_related_to--> `Environment correction: Mac session is local, not Tailscale-remote`  [INFERRED]
  CLAUDE.md → VECTOR_ERASER_HANDOFF.md
- `UIGraphicsImageRendererFormat.preferredRange defaults to extended-range on wide-colour iPad` --conceptually_related_to--> `Dirty-rect render cache (Phase 5 performance target)`  [INFERRED]
  REFACTOR_BASELINE.md → VECTOR_ERASER_PLAN.md
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Vector eraser foundation (geometry + spatial index + display list, shared across plan/handoff/session log)** — vector_eraser_plan_strokegeometry_primitives, vector_eraser_plan_strokespatialindex_design, vector_eraser_plan_unified_display_list, vector_eraser_handoff_strokegeometry, vector_eraser_handoff_strokespatialindex, vector_eraser_handoff_vectorcanvas_elements, session_log_vector_eraser_phases [INFERRED 0.90]
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]
- **Perf findings shared across refactor baseline and vector-eraser GPU plan** — refactor_baseline_preferredrange_finding, refactor_baseline_cgimage_cropping_finding, refactor_baseline_stage5_perf, vector_eraser_plan_gpu_rendering_section, vector_eraser_plan_dirty_rect_cache [INFERRED 0.80]

## Communities (109 total, 12 thin omitted)

### Community 0 - "Fill Tool UI Tests"
Cohesion: 0.09
Nodes (16): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+8 more)

### Community 1 - "Shape Detection Engine"
Cohesion: 0.06
Nodes (39): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int, Corner (+31 more)

### Community 2 - "Cel/Layer Manifest Types"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - "Canvas Test Fixtures"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "Timeline Track UI"
Cohesion: 0.07
Nodes (39): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+31 more)

### Community 5 - "Color Palette Model"
Cohesion: 0.07
Nodes (40): Equatable, Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+32 more)

### Community 6 - "Agent Orchestration Config"
Cohesion: 0.05
Nodes (57): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+49 more)

### Community 7 - "Canvas Manager Layer Ops"
Cohesion: 0.07
Nodes (33): CanvasManager, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState, .isShapeFollowingFinger (+25 more)

### Community 8 - "Vector Element Kind"
Cohesion: 0.09
Nodes (27): kind, Kind, fill, image, stroke, Bool, CGAffineTransform, CGFloat (+19 more)

### Community 9 - "Shape Overlay Handles"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 10 - "Brush Model"
Cohesion: 0.07
Nodes (30): Identifiable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+22 more)

### Community 11 - "Stroke Geometry Primitives"
Cohesion: 0.14
Nodes (13): VectorSample, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat, CGPoint (+5 more)

### Community 12 - "Stroke Input Handling"
Cohesion: 0.10
Nodes (25): StrokeInput, CGFloat, CGPoint, UITouch, UIView, StrokeCanvasView, .brush, .pencilOnlyDrawing (+17 more)

### Community 13 - "Vector Layer Persistence"
Cohesion: 0.08
Nodes (34): Codable, CodingKey, Encoder, CodingKeys, brush, color, composite, elements (+26 more)

### Community 14 - "Brush Engine Tests"
Cohesion: 0.15
Nodes (12): BrushEngineLogicTests, Any, CGFloat, CodableColor, Data, Double, Int, String (+4 more)

### Community 15 - "Canvas Edit Commit Flow"
Cohesion: 0.12
Nodes (18): String, UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingTransform, .affineTransform, Selection (+10 more)

### Community 16 - "CanvasManager Extension Files"
Cohesion: 0.08
Nodes (11): Combine, Darwin, FloatingPieceKind, duplicate, move, ThumbnailRenderer, PhotosUI, QuartzCore (+3 more)

### Community 17 - "Stroke Geometry Tests"
Cohesion: 0.09
Nodes (5): StrokeGeometryLogicTests, .ramp, StaticString, String, UInt

### Community 18 - "Vector Eraser Tests"
Cohesion: 0.16
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 19 - "Canvas Tool Coordinator"
Cohesion: 0.10
Nodes (20): NSObject, AppliedTool, Coordinator, CanvasManager, CGFloat, CGSize, Color, Date (+12 more)

### Community 20 - "Pixel Operations Utility"
Cohesion: 0.16
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 21 - "Vector Layer State Queries"
Cohesion: 0.17
Nodes (13): .activeLayerIsVector, .activeLayerKind, CGPoint, LayerTransform, CanvasManager, Bool, Int, Cel (+5 more)

### Community 22 - "Interactive Fill Flow"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 23 - "Metal Fill Engine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 24 - "Structure Undo Gestures"
Cohesion: 0.11
Nodes (15): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+7 more)

### Community 25 - "Brush Stamping Engine"
Cohesion: 0.16
Nodes (13): BrushStamper, DabRNG, Sample, Bool, CGBlendMode, CGFloat, CGPoint, Double (+5 more)

### Community 26 - "Undo Redo Canvas Ops"
Cohesion: 0.10
Nodes (15): CanvasManager, Bool, CGFloat, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage (+7 more)

### Community 27 - "Layer Tree Management"
Cohesion: 0.17
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 28 - "Performance Baseline Tests"
Cohesion: 0.23
Nodes (8): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UIImage, UInt64

### Community 29 - "GPU Fill Shader"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 30 - "Stroke Gesture Recognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 31 - "Raster Layer Texture"
Cohesion: 0.17
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 32 - "Stroke Spatial Index"
Cohesion: 0.18
Nodes (12): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+4 more)

### Community 33 - "Top Toolbar UI"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 34 - "Stroke Settings Panel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 35 - "Layer Host View"
Cohesion: 0.13
Nodes (7): LayerHostView, NSCoder, Bool, Int, UIGestureRecognizer, UIImage, UIImageView

### Community 36 - "Floating Piece Overlay"
Cohesion: 0.18
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+3 more)

### Community 37 - "Animation Timeline UI"
Cohesion: 0.11
Nodes (18): Gesture, AnimationTimeline, .body, .collapsedBar, .contentHeight, .fittedHeight, .isCollapsed, .layerNameColumn (+10 more)

### Community 38 - "Layer Panel UI"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 39 - "Project Save Tests"
Cohesion: 0.18
Nodes (9): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String (+1 more)

### Community 40 - "Layer Stack Cell UI"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 41 - "Transform Overlay Support"
Cohesion: 0.13
Nodes (18): FloatingTransform, .effectiveScaleX, .effectiveScaleY, Kind, rotate, scale, LayerTransform, .effectiveScaleX (+10 more)

### Community 42 - "Selection Mode Shapes"
Cohesion: 0.09
Nodes (20): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+12 more)

### Community 43 - "Selection Overlay View"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 44 - "Drawing View Root"
Cohesion: 0.11
Nodes (16): Alignment, DrawingView, .panelAlignment, .panelView, Bool, CanvasManager, CGFloat, UUID (+8 more)

### Community 45 - "Dab Stamping Target"
Cohesion: 0.22
Nodes (11): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+3 more)

### Community 46 - "App Root Navigation"
Cohesion: 0.13
Nodes (13): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+5 more)

### Community 47 - "Performance HUD Overlay"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, .body, PerfHUDOverlay, .body, .hudBody, .toggleButton (+7 more)

### Community 48 - "Project Manifest Fields"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 49 - "Project Manifest Structs"
Cohesion: 0.38
Nodes (14): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor, Date (+6 more)

### Community 50 - "Canvas Size Picker"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 51 - "Layer Row View Model"
Cohesion: 0.18
Nodes (10): LayerRowModel, .folderID, Bool, Context, Double, String, UIImage, UILongPressGestureRecognizer (+2 more)

### Community 52 - "Side Toolbar UI"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 53 - "Layer Stack Drag Coordinator"
Cohesion: 0.24
Nodes (9): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+1 more)

### Community 54 - "Layer Reorder Drag"
Cohesion: 0.18
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate (+1 more)

### Community 55 - "Object Transform Overlay"
Cohesion: 0.27
Nodes (8): ObjectTransformOverlayView, CGPoint, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 56 - "Known Bugs List"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "Pure Geometry Modules"
Cohesion: 0.17
Nodes (3): CoreGraphics, Foundation, Notification.Name

### Community 58 - "Undo History Model"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 59 - "Canvas View Coordinator"
Cohesion: 0.21
Nodes (6): CanvasView, CGPoint, Context, Coordinator, LayerTransform, UIViewRepresentable

### Community 60 - "Vector Eraser Handoff Notes"
Cohesion: 0.18
Nodes (14): Project directory structure (Engine/Models/Services/Utilities/Views), CanvasManager.activeLayerKind, AppliedTool.vectorEraserMode field (change-detection cache), Environment correction: Mac session is local, not Tailscale-remote, Probing along original segments instead of subdivided densification, Vector Eraser Resume Bookmark (Session 3 state), Engine/StrokeGeometry.swift, StrokeSpatialIndex.swift (+6 more)

### Community 61 - "Project Save Snapshot"
Cohesion: 0.33
Nodes (12): CelContent, LayerContent, ProjectSummary, SaveSnapshot, Bool, CGSize, Date, Double (+4 more)

### Community 62 - "Stroke Stabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 63 - "Vector Eraser Sweep"
Cohesion: 0.41
Nodes (7): Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange, VectorEraser

### Community 64 - "Vector Fill Path Color"
Cohesion: 0.27
Nodes (9): CodableColor, .uiColor, CGPath, Data, UIColor, UUID, VectorFillElement, .cgPath (+1 more)

### Community 65 - "Vector Canvas Rendering"
Cohesion: 0.32
Nodes (6): image, CGContext, CGRect, LayerTransform, UIImage, VectorImageElement

### Community 66 - "Layer Stack Row Model"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 67 - "Canvas Host View"
Cohesion: 0.18
Nodes (7): CanvasHostView, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, Void, UIKeyCommand

### Community 68 - "Gallery Browser UI"
Cohesion: 0.21
Nodes (7): GalleryTileView, .body, Void, GalleryView, .body, CanvasManager, Void

### Community 69 - "Select Tool Panel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 70 - "App Feature List"
Cohesion: 0.20
Nodes (12): Animation Timeline feature, Brush library feature (shape/hardness/spacing/stabilization/grain), Native-resolution raster/vector drawing engine (no PencilKit), GPU (Metal) colour-based flood fill feature, Gallery / project browser feature, Layers feature (raster/vector/object layers), PaintSoftware iPad drawing/animation app, Select & Move feature (lasso/rectangle/magic wand) (+4 more)

### Community 71 - "Vector Eraser Plan Sections"
Cohesion: 0.18
Nodes (12): BrushStamper.DabRNG (seeded splitmix64), Vector eraser Phases 0-2 (Session 2-3, this log's tail), Phase 4 (Mode 1: live preview, hybrid commit, residue, GC), Brush-side findings (non-replayable dab randomness, pressure staircase), Central problem: alpha punch vs geometric split, Capsule-chain coverage test (clean cut vs residue), Garbage collection of retained .erase elements, Mode 1 — Erase (live preview + hybrid commit) (+4 more)

### Community 72 - "Cel CRUD Characterization Tests"
Cohesion: 0.18
Nodes (11): CelCRUDCharacterizationTests, Shared frame-length clamp relaxed to >=, duplicateCel adjacent-neighbour overlap bug, Autorelease artifact in re-measuring memory (renderToUIImage), BrushStamper.stampStroke, Stroke cost tracks path length, not sample count, PerfBaselineTests.swift, Refactor Stage 0 — baseline + characterization tests (+3 more)

### Community 73 - "Project Store Service"
Cohesion: 0.38
Nodes (3): ProjectStore, .projectsDirectory, URL

### Community 74 - "Color Conversion Utility"
Cohesion: 0.29
Nodes (6): Color, .hexString, .rgbaComponents, Double, String, UIColor

### Community 75 - "Actions Menu UI"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 76 - "Layer Model"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 77 - "Vector Eraser Mode Enum"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 78 - "Color Math Utility"
Cohesion: 0.36
Nodes (4): .hsbaComponents, ColorMath, Double, String

### Community 79 - "Brush Settings Panel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 80 - "Eraser Settings Panel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 81 - "Move Transform Bottom Bar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 82 - "Deterministic Test RNG"
Cohesion: 0.39
Nodes (3): Deterministic, CGFloat, UInt64

### Community 83 - "Extended Range Color Bug"
Cohesion: 0.29
Nodes (7): CGImage.cropping(to:) retains parent pixel data, PixelOps.copiedSubimage, UIGraphicsImageRendererFormat.preferredRange defaults to extended-range on wide-colour iPad, Stage 5 performance work (dab gradient cache, dirty-rect undo), Delta undo (deferred), Dirty-rect render cache (Phase 5 performance target), Point decimation (pressure-aware RDP)

### Community 84 - "Multi-Session Deploy Workflow"
Cohesion: 0.33
Nodes (6): Deploy to iPad (deploy.sh, auto-resign), Multi-Session Protocol, deploy/mac/parallel_test.sh, Remote testing via Tailscale to Mac, Worktree-per-session workflow, Foolproof project backups (Session 34)

### Community 85 - "Graphify Usage Notes"
Cohesion: 0.33
Nodes (6): graphify-out/GRAPH_REPORT.md, .claude/hooks/graphify-guard.sh, graphify usage protocol, Open carry-over items (alpha gate, square eraser, ordering, GPU), §11 Moving vector rendering to the GPU, Z-order prefix/suffix flatten optimisation

### Community 86 - "Tool Enum"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 87 - "Codable Color Conversion"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 88 - "Atomic Value Wrapper"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 89 - "Parallel Test Script"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - "Layer Kind Enum"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 91 - "Vector Element Display List"
Cohesion: 0.40
Nodes (5): VectorCanvas ordered [VectorElement] list, The eraser is a stroke (VectorStroke.composite), VectorCanvasData persistence migration (legacy fallback), StrokeComposite enum (.paint/.erase), Unified VectorElement display list (z-order)

### Community 92 - "Table Swipe Actions"
Cohesion: 0.50
Nodes (3): IndexPath, CGFloat, UISwipeActionsConfiguration

### Community 93 - "Copied Cel Model"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 94 - "Layer Transform Model"
Cohesion: 0.50
Nodes (3): LayerTransform, CGFloat, CGPoint

### Community 95 - "App Version Utility"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **302 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+297 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CanvasManager` connect `Canvas Manager Layer Ops` to `Shape Detection Engine`, `Brush Model`, `Stroke Geometry Primitives`, `Canvas Edit Commit Flow`, `CanvasManager Extension Files`, `Vector Layer State Queries`, `Interactive Fill Flow`, `Metal Fill Engine`, `Structure Undo Gestures`, `Undo Redo Canvas Ops`, `Layer Tree Management`, `Raster Layer Texture`, `Selection Mode Shapes`, `Performance HUD Overlay`, `Undo History Model`, `Vector Eraser Mode Enum`, `Tool Enum`, `Layer Kind Enum`, `Copied Cel Model`?**
  _High betweenness centrality (0.156) - this node is a cross-community bridge._
- **Why does `VectorSample` connect `Stroke Geometry Primitives` to `Shape Detection Engine`, `Color Palette Model`, `Canvas Manager Layer Ops`, `Vector Element Kind`, `Stroke Input Handling`, `Vector Layer Persistence`, `Brush Engine Tests`, `Stroke Geometry Tests`, `Vector Eraser Tests`, `Canvas Tool Coordinator`, `Vector Layer State Queries`, `Brush Stamping Engine`, `Undo Redo Canvas Ops`, `Performance Baseline Tests`, `Stroke Spatial Index`, `Layer Host View`, `Project Save Tests`, `Pure Geometry Modules`, `Vector Eraser Sweep`, `Deterministic Test RNG`?**
  _High betweenness centrality (0.127) - this node is a cross-community bridge._
- **Why does `Brush` connect `Brush Model` to `Stroke Settings Panel`, `Color Palette Model`, `Canvas Manager Layer Ops`, `Vector Element Kind`, `Project Store Service`, `Stroke Geometry Primitives`, `Stroke Input Handling`, `Vector Layer Persistence`, `Brush Engine Tests`, `Brush Settings Panel`, `Project Manifest Structs`, `Stroke Geometry Tests`, `Canvas Tool Coordinator`, `Vector Eraser Tests`, `Brush Stamping Engine`, `Performance Baseline Tests`, `Project Save Snapshot`?**
  _High betweenness centrality (0.114) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 59 inferred relationships involving `XCUIApplication` (e.g. with `.testAdjustingThresholdAfterFillReappliesToUncommittedFill()` and `.testDrawingOverFillCommitsFillAndStrokeUndoesFirst()`) actually correct?**
  _`XCUIApplication` has 59 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._