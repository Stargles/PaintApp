# Graph Report - vector-interpolation-keyframes-d484df  (2026-07-31)

## Corpus Check
- 123 files · ~213,759 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2755 nodes · 7301 edges · 110 communities (103 shown, 7 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 901 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f5363ce5`
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
- ShapeGeometry
- BrushBlendMode
- StrokeCanvasView
- StrokeGeometryLogicTests
- ContentView
- VectorEraserHybridLogicTests
- .setCanvasPadding
- .transparentFormat
- VectorStroke
- Coordinator
- CanvasManager
- CanvasManager
- OnionSkinLogicTests
- MetalFillEngine
- Brush
- .stampStroke
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- VectorSample
- .withStructureUndo
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- LayerOptionsPanel
- .renderToUIImage
- LayerStackCell
- UIView
- ProjectSaveLogicTests
- .makeUIView
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- .stampCircle
- UIKit
- CoreGraphics
- .centreStroke
- PerfMonitor
- CodingKeys
- Color
- LayerRowModel
- Vector Eraser — Design Plan
- Coordinator
- Codable
- SideToolbar
- XCTest
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- Refactor baseline (Stage 0)
- CanvasManager
- String
- UndoHistory
- CanvasHostView
- Layer
- Vector Eraser — Resume Here
- Known Issues
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- LayerStackRow
- ProjectSummary
- View
- Vector Interpolation — Handoff & Session Protocol
- DrawingView
- .canvasTouchCountChanged
- 5. Workflow and architecture
- ActionsMenu
- VectorEraserMode
- BrushSettingsPanel
- EraserSettingsPanel
- SaveSnapshot
- Deterministic
- ProjectStore.swift
- 3. Three candidate engines
- LayerKind
- .render
- Atomic
- Multi-Session Protocol
- parallel_test.sh
- 6. Guide strokes
- 7. Edge cases from the brief
- .tableView
- CanvasView
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- 3. Session protocol
- .placedImage

## God Nodes (most connected - your core abstractions)
1. `VectorCanvas` - 101 edges
2. `VectorSample` - 89 edges
3. `CanvasManager` - 86 edges
4. `ShapeGeometry` - 73 edges
5. `Coordinator` - 72 edges
6. `Brush` - 64 edges
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

## Communities (110 total, 7 thin omitted)

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
Nodes (41): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+33 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (39): Identifiable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+31 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (37): Hashable, CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+29 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometry"
Cohesion: 0.14
Nodes (13): Equatable, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGFloat, CGPoint (+5 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (31): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+23 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (7): CGFloat, CGPoint, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.09
Nodes (30): kind, DabLattice, .range, Kind, fill, image, stroke, Bool (+22 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.30
Nodes (4): BrushEngineLogicTests, CGFloat, Int, UInt8

### Community 13 - "ShapeGeometry"
Cohesion: 0.06
Nodes (39): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int, Corner (+31 more)

### Community 14 - "BrushBlendMode"
Cohesion: 0.10
Nodes (15): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+7 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (27): StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas, Bool, CanvasManager (+19 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.11
Nodes (6): StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "VectorEraserHybridLogicTests"
Cohesion: 0.19
Nodes (9): .samples, Bool, CGFloat, CGPoint, Double, Int, StaticString, UInt (+1 more)

### Community 19 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (5): CanvasManager, Bool, CGFloat, CGSize, UIImage

### Community 20 - ".transparentFormat"
Cohesion: 0.15
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 21 - "VectorStroke"
Cohesion: 0.06
Nodes (48): CodingKey, Encoder, CodableColor, .uiColor, CodingKeys, brush, color, composite (+40 more)

### Community 22 - "Coordinator"
Cohesion: 0.10
Nodes (18): AppliedTool, Coordinator, CGFloat, CGSize, Color, Date, Double, NSLayoutConstraint (+10 more)

### Community 23 - "CanvasManager"
Cohesion: 0.09
Nodes (26): String, UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingTransform, .affineTransform, Selection (+18 more)

### Community 24 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 25 - "OnionSkinLogicTests"
Cohesion: 0.16
Nodes (11): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGFloat, UIColor, UIImage, OnionSkinLogicTests (+3 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "Brush"
Cohesion: 0.15
Nodes (14): Brush, CutOutcome, cut, missed, unchanged, IntersectionDriver, Sweep, Bool (+6 more)

### Community 28 - ".stampStroke"
Cohesion: 0.15
Nodes (16): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, CGFloat (+8 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.24
Nodes (7): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UInt64

### Community 30 - "layers"
Cohesion: 0.21
Nodes (10): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+2 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.17
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 34 - "VectorSample"
Cohesion: 0.18
Nodes (13): Int32, Int64, VectorSample, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+5 more)

### Community 35 - ".withStructureUndo"
Cohesion: 0.09
Nodes (20): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+12 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.12
Nodes (16): AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed, .maxTimelineHeight (+8 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+3 more)

### Community 40 - ".load"
Cohesion: 0.29
Nodes (6): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, URL

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+10 more)

### Community 42 - ".renderToUIImage"
Cohesion: 0.18
Nodes (6): StrokeInput, CGFloat, CGPoint, UITouch, UIView, UIImage

### Community 43 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 44 - "UIView"
Cohesion: 0.12
Nodes (17): FloatingTransform, .effectiveScaleX, .effectiveScaleY, Kind, rotate, scale, LayerTransform, .effectiveScaleX (+9 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - ".makeUIView"
Cohesion: 0.15
Nodes (6): LayerHostView, NSCoder, CGPoint, Context, LayerTransform, UIImageView

### Community 47 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.10
Nodes (21): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 8. Performance — the real constraint (+13 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.20
Nodes (10): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+2 more)

### Community 50 - ".stampCircle"
Cohesion: 0.25
Nodes (9): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, CGFloat, CGPoint (+1 more)

### Community 51 - "UIKit"
Cohesion: 0.11
Nodes (10): Combine, CopiedCel, Int, UIImage, FloatingPieceKind, duplicate, move, PhotosUI (+2 more)

### Community 52 - "CoreGraphics"
Cohesion: 0.09
Nodes (9): CoreGraphics, Foundation, LayerTransform, CGFloat, CGPoint, Notification.Name, AppVersion, .versionString (+1 more)

### Community 53 - ".centreStroke"
Cohesion: 0.26
Nodes (4): Any, CodableColor, String, T

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 56 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "LayerRowModel"
Cohesion: 0.24
Nodes (8): LayerRowModel, .folderID, Bool, Double, String, UIImage, UILongPressGestureRecognizer, UIPinchGestureRecognizer

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "Coordinator"
Cohesion: 0.24
Nodes (9): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+1 more)

### Community 60 - "Codable"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.25
Nodes (9): ObjectTransformOverlayView, CGPoint, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void (+1 more)

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "LayerStackListView.Coordinator"
Cohesion: 0.18
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, CGPoint, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate (+1 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.12
Nodes (12): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+4 more)

### Community 69 - "String"
Cohesion: 0.08
Nodes (27): CaseIterable, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+19 more)

### Community 70 - "UndoHistory"
Cohesion: 0.23
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
Cohesion: 0.06
Nodes (29): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+21 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.12
Nodes (17): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone* (+9 more)

### Community 77 - "LayerStackRow"
Cohesion: 0.12
Nodes (14): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+6 more)

### Community 78 - "ProjectSummary"
Cohesion: 0.19
Nodes (10): ProjectSummary, Date, UIImage, GalleryTileView, .body, Void, GalleryView, .body (+2 more)

### Community 79 - "View"
Cohesion: 0.12
Nodes (16): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void, SelectPanel, .body (+8 more)

### Community 80 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.12
Nodes (16): 1. Start-of-session checklist, 2. Current state, 4. Build and test, 5. Carry-overs, 6. Session log, 7. Handoff prompt template, 8. Suggested follow-on work, After changing code (+8 more)

### Community 82 - "DrawingView"
Cohesion: 0.11
Nodes (16): Alignment, DrawingView, .panelAlignment, .panelView, Bool, CanvasManager, CGFloat, UUID (+8 more)

### Community 83 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 84 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 85 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 86 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 87 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 88 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 89 - "SaveSnapshot"
Cohesion: 0.36
Nodes (10): CelContent, LayerContent, SaveSnapshot, Bool, CanvasManager, CGSize, Double, Int (+2 more)

### Community 90 - "Deterministic"
Cohesion: 0.43
Nodes (3): Deterministic, CGFloat, UInt64

### Community 91 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 92 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 93 - "LayerKind"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 94 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 96 - "Multi-Session Protocol"
Cohesion: 0.21
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "6. Guide strokes"
Cohesion: 0.40
Nodes (5): 6.1 What they are, 6.2 The controls from requirement 6, 6.3 The data gap, 6.4 Reuse across frames (requirement 7), 6. Guide strokes

### Community 99 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 100 - ".tableView"
Cohesion: 0.25
Nodes (5): IndexPath, CGFloat, Context, UISwipeActionsConfiguration, UITableView

### Community 101 - "CanvasView"
Cohesion: 0.29
Nodes (5): CanvasView, CanvasManager, Coordinator, .body, UIViewRepresentable

### Community 108 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

## Knowledge Gaps
- **455 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+450 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VectorSample` connect `VectorSample` to `ParityScenario`, `CanvasManager`, `StrokeGeometry`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `VectorStroke`, `Coordinator`, `OnionSkinLogicTests`, `Brush`, `PerfBaselineTests`, `ProjectSaveLogicTests`, `.makeUIView`, `RasterLayerTexture`, `CoreGraphics`, `.centreStroke`, `Codable`, `CanvasManager`, `String`, `.interpolatedSample`?**
  _High betweenness centrality (0.136) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `VectorSample`, `.withStructureUndo`, `CanvasManager`, `String`, `UndoHistory`, `ShapeGeometry`, `RasterLayerTexture`, `UIKit`, `.setCanvasPadding`, `PerfMonitor`, `CanvasManager`, `CanvasManager`, `VectorEraserMode`, `MetalFillEngine`, `Brush`, `LayerKind`, `layers`?**
  _High betweenness centrality (0.128) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `.manager` to `.launchIntoEditor`, `ParityScenario`, `ProjectBackupManager`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `ProjectSaveLogicTests`, `ShapeGeometry`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `OnionSkinLogicTests`, `PerfBaselineTests`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `VectorCanvas` (e.g. with `.testEraseHeavyVectorLayerCostAndMemory()` and `.testVectorLayerRenderCostAndMemory()`) actually correct?**
  _`VectorCanvas` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 10 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._