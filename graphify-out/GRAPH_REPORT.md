# Graph Report - vector-interpolation-keyframes-d484df  (2026-07-31)

## Corpus Check
- 130 files · ~235,054 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2910 nodes · 8224 edges · 120 communities (113 shown, 7 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1031 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5e5785ed`
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
- CGFloat
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- ShapeDetectorLogicTests
- Brush
- StrokeCanvasView
- StrokeGeometryLogicTests
- ContentView
- CGPoint
- SelectionMode
- .transparentFormat
- VectorStroke
- Coordinator
- CanvasManager
- CanvasManager
- OnionSkinLogicTests
- MetalFillEngine
- .cleanCutRanges
- .stampStroke
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- VectorSample
- LayerFolder
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- ProjectStore
- View
- Lattice
- LayerStackCell
- UIView
- ProjectSaveLogicTests
- .reconcileLayers
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- CGContextDabTarget
- UIKit
- CoreGraphics
- DeformFactorization
- PerfMonitor
- CodingKeys
- Color
- LatticeLogicTests
- Vector Eraser — Design Plan
- LayerRowModel
- ProjectManifest
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
- ProjectSummary
- SelectPanel
- Vector Interpolation — Handoff & Session Protocol
- ShapeGeometry
- ActionsMenu
- .canvasTouchCountChanged
- 5. Workflow and architecture
- FloatingPiece
- VectorEraserMode
- BrushSettingsPanel
- EraserSettingsPanel
- .load
- DrawingView
- ShapeDetector
- 3. Three candidate engines
- LayerKind
- CanvasManager
- Atomic
- Multi-Session Protocol
- parallel_test.sh
- 6. Guide strokes
- 7. Edge cases from the brief
- HandleKind
- .makeUIView
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- 3. Session protocol
- .handleKind
- MotionGrouping
- .collapseSamplesToShape
- Corner
- TransformOverlaySupport.swift
- Edge
- CutOutcome
- VectorScratchRole
- AppliedTool
- EndpointHandle

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 363 edges
2. `CGFloat` - 298 edges
3. `VectorCanvas` - 101 edges
4. `VectorSample` - 89 edges
5. `CanvasManager` - 86 edges
6. `Lattice` - 74 edges
7. `ShapeGeometry` - 73 edges
8. `Coordinator` - 72 edges
9. `Brush` - 64 edges
10. `layers` - 60 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (120 total, 7 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (45): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+37 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (39): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+31 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (43): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+35 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (31): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .effectiveLoopRange, .isFillInAdjustableState, .isShapeFollowingFinger, .isShapeInAdjustableState (+23 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "CGFloat"
Cohesion: 0.10
Nodes (14): CGFloat, Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+6 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.18
Nodes (11): CALayer, CornerHandle, EdgeHandle, HandleInfo, ShapeOverlayView, .isActive, Bool, CGRect (+3 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): CGRect, VectorEraser, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.09
Nodes (23): kind, Kind, fill, image, stroke, Bool, CGRect, CGSize (+15 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.12
Nodes (11): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, UIColor (+3 more)

### Community 13 - "ShapeDetectorLogicTests"
Cohesion: 0.17
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 14 - "Brush"
Cohesion: 0.09
Nodes (25): Equatable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+17 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (23): StrokeInput, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+15 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "CGPoint"
Cohesion: 0.13
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 19 - "SelectionMode"
Cohesion: 0.15
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.16
Nodes (15): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+7 more)

### Community 21 - "VectorStroke"
Cohesion: 0.06
Nodes (52): Codable, CodingKey, Encoder, Identifiable, CodableColor, .uiColor, CodingKeys, brush (+44 more)

### Community 22 - "Coordinator"
Cohesion: 0.12
Nodes (16): NSObject, Coordinator, CanvasManager, CGSize, Date, NSLayoutConstraint, TimeInterval, Timer (+8 more)

### Community 23 - "CanvasManager"
Cohesion: 0.14
Nodes (12): .currentFrame, .currentLayerIndex, String, UUID, Void, CanvasManager, Selection, Bool (+4 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "OnionSkinLogicTests"
Cohesion: 0.16
Nodes (9): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, UIColor, UIImage, OnionSkinLogicTests, Bool (+1 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - ".cleanCutRanges"
Cohesion: 0.30
Nodes (4): Sweep, Bool, ClosedRange, Double

### Community 28 - ".stampStroke"
Cohesion: 0.15
Nodes (13): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+5 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.24
Nodes (6): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64

### Community 30 - "layers"
Cohesion: 0.21
Nodes (6): .activeLayerIsVector, CanvasManager, Bool, Int, Void, layers

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.20
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 34 - "VectorSample"
Cohesion: 0.13
Nodes (13): Int64, VectorSample, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect (+5 more)

### Community 35 - "LayerFolder"
Cohesion: 0.11
Nodes (17): CelLocation, String, UUID, CanvasManager, .activeViewName, Int, String, LayerFolder (+9 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.10
Nodes (18): Gesture, AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed (+10 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - "ProjectStore"
Cohesion: 0.24
Nodes (6): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, URL

### Community 41 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 42 - "Lattice"
Cohesion: 0.11
Nodes (19): DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration, .triangles (+11 more)

### Community 43 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 44 - "UIView"
Cohesion: 0.20
Nodes (9): Kind, rotate, scale, Bool, NSCoder, UIEvent, TransformHandleView, TransformOverlayView (+1 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.19
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.10
Nodes (21): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 8. Performance — the real constraint (+13 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 50 - "CGContextDabTarget"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 51 - "UIKit"
Cohesion: 0.12
Nodes (11): Combine, CodableColor, .color, Color, .codable, CodableColor, ThumbnailRenderer, PhotosUI (+3 more)

### Community 52 - "CoreGraphics"
Cohesion: 0.06
Nodes (8): CoreGraphics, Darwin, Foundation, Notification.Name, AppVersion, .versionString, String, XCTest

### Community 53 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 55 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+10 more)

### Community 56 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "LatticeLogicTests"
Cohesion: 0.15
Nodes (5): LatticeLogicTests, Int, StaticString, String, UInt

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.12
Nodes (20): IndexPath, Coordinator, LayerRowModel, .folderID, LayerStackListView, Bool, CanvasManager, Context (+12 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.38
Nodes (14): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor, Date (+6 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.17
Nodes (6): ARAPInterpolation, ARAPLogicTests, Int, StaticString, String, UInt

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
Cohesion: 0.21
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

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
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.12
Nodes (17): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone* (+9 more)

### Community 77 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 78 - "ProjectSummary"
Cohesion: 0.21
Nodes (9): ProjectSummary, Date, GalleryTileView, .body, Void, GalleryView, .body, CanvasManager (+1 more)

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.12
Nodes (16): 1. Start-of-session checklist, 2. Current state, 4. Build and test, 5. Carry-overs, 6. Session log, 7. Handoff prompt template, 8. Suggested follow-on work, After changing code (+8 more)

### Community 81 - "ShapeGeometry"
Cohesion: 0.12
Nodes (14): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+6 more)

### Community 82 - "ActionsMenu"
Cohesion: 0.13
Nodes (15): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String, .panelView (+7 more)

### Community 83 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 84 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 85 - "FloatingPiece"
Cohesion: 0.12
Nodes (18): FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform, CGAffineTransform (+10 more)

### Community 86 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 87 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 88 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 89 - ".load"
Cohesion: 0.35
Nodes (11): CelContent, LayerContent, SaveSnapshot, Bool, CanvasManager, CGSize, Double, Int (+3 more)

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "ShapeDetector"
Cohesion: 0.28
Nodes (4): ClosedFit, ShapeDetector, Bool, CGRect

### Community 92 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 93 - "LayerKind"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 94 - "CanvasManager"
Cohesion: 0.29
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

### Community 99 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 100 - "HandleKind"
Cohesion: 0.17
Nodes (12): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+4 more)

### Community 101 - ".makeUIView"
Cohesion: 0.20
Nodes (5): CanvasView, Context, Coordinator, LayerTransform, UIViewRepresentable

### Community 108 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

### Community 109 - ".handleKind"
Cohesion: 0.36
Nodes (3): Set, UIEvent, UITouch

### Community 110 - "MotionGrouping"
Cohesion: 0.39
Nodes (5): Group, MotionGrouping, Options, Int, Set

### Community 112 - "Corner"
Cohesion: 0.22
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 114 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 117 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 118 - "AppliedTool"
Cohesion: 0.50
Nodes (3): AppliedTool, Color, Double

### Community 119 - "EndpointHandle"
Cohesion: 0.67
Nodes (3): EndpointHandle, end, start

## Knowledge Gaps
- **466 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+461 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `Brush`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `CGPoint`, `SelectionMode`, `.transparentFormat`, `VectorStroke`, `Coordinator`, `CanvasManager`, `OnionSkinLogicTests`, `.cleanCutRanges`, `.stampStroke`, `PerfBaselineTests`, `VectorSample`, `StrokeSettingsPanel`, `AnimationTimeline`, `Lattice`, `LayerStackCell`, `UIView`, `.reconcileLayers`, `RasterLayerTexture`, `CGContextDabTarget`, `DeformFactorization`, `Color`, `LatticeLogicTests`, `LayerRowModel`, `SideToolbar`, `ARAPLogicTests`, `CanvasManager`, `CaseIterable`, `StrokeStabilizer`, `ShapeGeometry`, `ActionsMenu`, `FloatingPiece`, `EraserSettingsPanel`, `.load`, `DrawingView`, `ShapeDetector`, `MotionGrouping`, `.collapseSamplesToShape`, `TransformOverlaySupport.swift`, `.inverseBilinear`, `AppliedTool`?**
  _High betweenness centrality (0.340) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `CGFloat`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `Brush`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `SelectionMode`, `.transparentFormat`, `VectorStroke`, `Coordinator`, `CanvasManager`, `CanvasManager`, `.cleanCutRanges`, `.stampStroke`, `PerfBaselineTests`, `layers`, `VectorSample`, `FloatingPieceOverlayView`, `Lattice`, `UIView`, `ProjectSaveLogicTests`, `.reconcileLayers`, `SelectionOverlayView`, `RasterLayerTexture`, `CGContextDabTarget`, `CoreGraphics`, `DeformFactorization`, `LatticeLogicTests`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `LayerStackListView.Coordinator`, `CanvasManager`, `CaseIterable`, `StrokeStabilizer`, `ShapeGeometry`, `FloatingPiece`, `ShapeDetector`, `.makeUIView`, `.handleKind`, `MotionGrouping`, `.collapseSamplesToShape`, `Corner`, `TransformOverlaySupport.swift`, `Edge`, `.inverseBilinear`?**
  _High betweenness centrality (0.155) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ColorPickerPanel`, `CGFloat`, `Brush`, `SelectionMode`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `layers`, `VectorSample`, `LayerFolder`, `RasterLayerTexture`, `UIKit`, `PerfMonitor`, `UndoHistory`, `ShapeGeometry`, `FloatingPiece`, `VectorEraserMode`, `LayerKind`, `CanvasManager`?**
  _High betweenness centrality (0.081) - this node is a cross-community bridge._
- **Are the 50 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 50 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `VectorCanvas` (e.g. with `.testEraseHeavyVectorLayerCostAndMemory()` and `.testVectorLayerRenderCostAndMemory()`) actually correct?**
  _`VectorCanvas` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 10 INFERRED edges - model-reasoned connections that need verification._