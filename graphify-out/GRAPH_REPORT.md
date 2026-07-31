# Graph Report - vector-interpolation-keyframes-d484df  (2026-07-31)

## Corpus Check
- 135 files · ~246,211 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3094 nodes · 8682 edges · 123 communities (117 shown, 6 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1100 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `49906eab`
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
- CGPoint
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- ShapeDetectorLogicTests
- BrushShape
- StrokeCanvasView
- BackupManagerLogicTests
- ContentView
- PointCloudIndex
- .setCanvasPadding
- .transparentFormat
- String
- .setUpGestures
- CanvasManager
- CanvasManager
- OnionSkinLogicTests
- MetalFillEngine
- CGFloat
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
- Int
- LayerStackCell
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- InterpolationRecipe
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- DabTarget
- UIKit
- CoreGraphics
- DeformFactorization
- PerfMonitor
- CodingKeys
- Color
- Lattice
- Vector Eraser — Design Plan
- LayerStackListView
- Codable
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- Refactor baseline (Stage 0)
- CanvasManager
- CaseIterable
- UndoHistory
- CanvasHostView
- Layer
- Vector Eraser — Resume Here
- Known Issues
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- LayerStackRow
- GalleryView
- SelectionMode
- Vector Interpolation — Handoff & Session Protocol
- ShapeGeometry
- BrushSettingsPanel
- CanvasManager
- 5. Workflow and architecture
- Equatable
- VectorEraserMode
- CodingKeys
- EraserSettingsPanel
- XCTest
- DrawingView
- ShapeDetector
- 3. Three candidate engines
- StrokeGestureRecognizer
- StructureSnapshot
- Atomic
- Multi-Session Protocol
- parallel_test.sh
- 6. Guide strokes
- Coordinator
- HandleKind
- Coordinator
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- 3. Session protocol
- LayerRowModel
- .group
- MotionGroup
- Corner
- UIView
- Edge
- CutOutcome
- ActionsMenu
- VectorScratchRole
- CodingKeys
- Kind
- ManifestSkeleton
- ProjectStore.swift
- Gesture

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 369 edges
2. `CGFloat` - 309 edges
3. `VectorCanvas` - 107 edges
4. `VectorSample` - 90 edges
5. `CanvasManager` - 88 edges
6. `Lattice` - 81 edges
7. `ShapeGeometry` - 73 edges
8. `Coordinator` - 72 edges
9. `layers` - 65 edges
10. `Brush` - 64 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `.paddingControl` --calls--> `CGFloat`  [INFERRED]
  PaintSoftware/Views/ActionsMenu.swift → PaintSoftware/Engine/Deform/Lattice.swift

## Import Cycles
- None detected.

## Communities (123 total, 6 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (35): CustomStringConvertible, UUID, Backdrop, fill, image, none, ParityPixel, .description (+27 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (20): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+12 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (37): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+29 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (31): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+23 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "CGPoint"
Cohesion: 0.09
Nodes (14): CGPoint, .length, .point, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool (+6 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.16
Nodes (14): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, ShapeOverlayView (+6 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.08
Nodes (9): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 11 - "VectorCanvas"
Cohesion: 0.07
Nodes (42): Identifiable, CodableColor, .uiColor, image, kind, Kind, fill, image (+34 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 13 - "ShapeDetectorLogicTests"
Cohesion: 0.16
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 14 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (23): StrokeInput, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+15 more)

### Community 16 - "BackupManagerLogicTests"
Cohesion: 0.15
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.14
Nodes (14): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+6 more)

### Community 19 - ".setCanvasPadding"
Cohesion: 0.36
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 20 - ".transparentFormat"
Cohesion: 0.16
Nodes (15): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+7 more)

### Community 21 - "String"
Cohesion: 0.06
Nodes (40): CodingKeys, brush, color, composite, elements, fill, fills, id (+32 more)

### Community 22 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 23 - "CanvasManager"
Cohesion: 0.08
Nodes (26): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingTransform, .affineTransform (+18 more)

### Community 24 - "CanvasManager"
Cohesion: 0.12
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "OnionSkinLogicTests"
Cohesion: 0.18
Nodes (9): OnionSkinFrame, PreviousCelOnionSkinSource, CanvasManager, UIColor, UIImage, OnionSkinLogicTests, Bool, UIImage (+1 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "CGFloat"
Cohesion: 0.13
Nodes (14): Brush, CGFloat, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double (+6 more)

### Community 28 - ".stampStroke"
Cohesion: 0.16
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.21
Nodes (8): PerfBaselineTests, CanvasManager, Double, Int, String, UIImage, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.16
Nodes (12): .activeLayerIsVector, Bool, CanvasManager, Bool, Int, Void, Cel, .endFrame (+4 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 33 - "CanvasManager"
Cohesion: 0.20
Nodes (12): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+4 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 35 - "LayerFolder"
Cohesion: 0.12
Nodes (14): CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String, UUID (+6 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.12
Nodes (15): AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed, .maxTimelineHeight (+7 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 40 - ".load"
Cohesion: 0.14
Nodes (21): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+13 more)

### Community 41 - "View"
Cohesion: 0.17
Nodes (18): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+10 more)

### Community 42 - "Int"
Cohesion: 0.18
Nodes (9): DeformedCellIndex, Hit, LatticeEmbedding, .count, .isEmpty, LatticeExpansion, .didExpand, Bool (+1 more)

### Community 43 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (14): InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit (+6 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.18
Nodes (9): SelectionOverlayView, .isCapturingGestures, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer, UITapGestureRecognizer (+1 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.08
Nodes (26): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 7.1 Erasers — mostly already solved (+18 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 50 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 51 - "UIKit"
Cohesion: 0.11
Nodes (8): Combine, FloatingPieceKind, duplicate, move, ThumbnailRenderer, PhotosUI, SwiftUI, UIKit

### Community 52 - "CoreGraphics"
Cohesion: 0.16
Nodes (7): CoreGraphics, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String

### Community 53 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+12 more)

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "Lattice"
Cohesion: 0.08
Nodes (18): vertices, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration, .triangles, .vertexCount (+10 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 60 - "Codable"
Cohesion: 0.22
Nodes (20): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+12 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.19
Nodes (5): ARAPInterpolation, ARAPLogicTests, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "LayerStackListView.Coordinator"
Cohesion: 0.17
Nodes (9): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UILongPressGestureRecognizer, UIView, UIGestureRecognizerDelegate (+1 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.12
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 69 - "CaseIterable"
Cohesion: 0.33
Nodes (5): CaseIterable, Kind, line, oval, rectangle

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
Cohesion: 0.06
Nodes (29): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+21 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.12
Nodes (17): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone* (+9 more)

### Community 77 - "LayerStackRow"
Cohesion: 0.12
Nodes (14): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+6 more)

### Community 78 - "GalleryView"
Cohesion: 0.14
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 79 - "SelectionMode"
Cohesion: 0.11
Nodes (16): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage, SelectPanel (+8 more)

### Community 80 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.10
Nodes (20): 1. Start-of-session checklist, 2. Current state, 4. Build and test, 5.7 For Phase 2's data model, 5. Carry-overs, 6. Session log, 7. Handoff prompt template, 8. Suggested follow-on work (+12 more)

### Community 81 - "ShapeGeometry"
Cohesion: 0.11
Nodes (14): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+6 more)

### Community 82 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.14
Nodes (11): CanvasManager, Bool, Cel, CodableColor, Int, Layer, Set, String (+3 more)

### Community 84 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 85 - "Equatable"
Cohesion: 0.18
Nodes (15): Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+7 more)

### Community 86 - "VectorEraserMode"
Cohesion: 0.14
Nodes (13): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+5 more)

### Community 87 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, boundGroups, id, interval, role, samples, CodingKeys (+11 more)

### Community 88 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "ShapeDetector"
Cohesion: 0.19
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 92 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 93 - "StrokeGestureRecognizer"
Cohesion: 0.27
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 94 - "StructureSnapshot"
Cohesion: 0.23
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

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

### Community 99 - "Coordinator"
Cohesion: 0.28
Nodes (7): NSObject, Coordinator, CanvasManager, Int, Set, UUID, UITableViewDiffableDataSource

### Community 100 - "HandleKind"
Cohesion: 0.13
Nodes (15): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+7 more)

### Community 101 - "Coordinator"
Cohesion: 0.08
Nodes (21): LayerHostView, AppliedTool, CanvasView, Coordinator, Bool, CanvasManager, Color, Context (+13 more)

### Community 108 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

### Community 109 - "LayerRowModel"
Cohesion: 0.27
Nodes (7): LayerRowModel, .folderID, Bool, Double, String, UIImage, UIPinchGestureRecognizer

### Community 110 - ".group"
Cohesion: 0.21
Nodes (6): Group, MotionGrouping, Options, Int, Set, groups

### Community 111 - "MotionGroup"
Cohesion: 0.29
Nodes (8): GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder, UUID

### Community 112 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 113 - "UIView"
Cohesion: 0.16
Nodes (11): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+3 more)

### Community 114 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 117 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 118 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 119 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 120 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 121 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 122 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

## Knowledge Gaps
- **506 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+501 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `CGPoint`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `StrokeCanvasView`, `PointCloudIndex`, `.setCanvasPadding`, `.transparentFormat`, `String`, `.setUpGestures`, `CanvasManager`, `CanvasManager`, `OnionSkinLogicTests`, `.stampStroke`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `Int`, `LayerStackCell`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `RasterLayerTexture`, `DabTarget`, `CoreGraphics`, `DeformFactorization`, `Color`, `Lattice`, `LayerStackListView`, `SideToolbar`, `ARAPLogicTests`, `CanvasManager`, `CaseIterable`, `StrokeStabilizer`, `ShapeGeometry`, `CanvasManager`, `Equatable`, `EraserSettingsPanel`, `DrawingView`, `ShapeDetector`, `Coordinator`, `Coordinator`, `.group`, `UIView`, `ActionsMenu`, `Kind`?**
  _High betweenness centrality (0.290) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `StrokeCanvasView`, `PointCloudIndex`, `.setCanvasPadding`, `.transparentFormat`, `String`, `.setUpGestures`, `CanvasManager`, `CanvasManager`, `CGFloat`, `.stampStroke`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `FloatingPieceOverlayView`, `Int`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `InterpolationRecipe`, `SelectionOverlayView`, `RasterLayerTexture`, `DabTarget`, `CoreGraphics`, `DeformFactorization`, `Lattice`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `LayerStackListView.Coordinator`, `CanvasManager`, `CaseIterable`, `StrokeStabilizer`, `ShapeGeometry`, `Equatable`, `ShapeDetector`, `HandleKind`, `Coordinator`, `.group`, `UIView`, `Gesture`?**
  _High betweenness centrality (0.196) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `.setCanvasPadding`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `CGFloat`, `layers`, `CanvasManager`, `LayerFolder`, `RasterLayerTexture`, `UIKit`, `PerfMonitor`, `Codable`, `CanvasManager`, `UndoHistory`, `SelectionMode`, `ShapeGeometry`, `Equatable`, `VectorEraserMode`, `StructureSnapshot`, `MotionGroup`?**
  _High betweenness centrality (0.103) - this node is a cross-community bridge._
- **Are the 53 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 53 INFERRED edges - model-reasoned connections that need verification._
- **Are the 7 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `VectorCanvas` (e.g. with `.testEraseHeavyVectorLayerCostAndMemory()` and `.testVectorLayerRenderCostAndMemory()`) actually correct?**
  _`VectorCanvas` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 11 INFERRED edges - model-reasoned connections that need verification._