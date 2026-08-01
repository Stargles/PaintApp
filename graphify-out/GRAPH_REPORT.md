# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-01)

## Corpus Check
- 140 files · ~274,181 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3362 nodes · 9562 edges · 129 communities (123 shown, 6 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1197 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2346cf2d`
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
- StrokeGeometryLogicTests
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- CGPoint
- .setCanvasPadding
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- .warped
- .transparentFormat
- CodingKeys
- URL
- CanvasManager
- CanvasManager
- InterpolationWorkflowLogicTests
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
- Lattice
- StrokeGestureRecognizer
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- InterpolationRecipe
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- CGContextDabTarget
- SwiftUI
- StrokeGeometry
- DeformFactorization
- PerfMonitor
- CodingKeys
- Color
- .makeUIView
- Vector Eraser — Design Plan
- LayerRowModel
- ProjectManifest
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- agent
- Refactor baseline (Stage 0)
- CanvasManager
- Codable
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- Layer
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- command
- ProjectVersionsView
- SelectPanel
- 5. Carry-overs
- Known Issues
- EraserSettingsPanel
- CanvasManager
- 5. Workflow and architecture
- Equatable
- VectorScratchRole
- MotionGroup
- SelectionMode
- UIKit
- DrawingView
- Brush
- StructureSnapshot
- InterpolateBar
- CodingKeys
- Atomic
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- LayerStackRow
- ManifestSkeleton
- CodingKeys
- Coordinator
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- VectorImageElement
- InterpolatePanel
- Deterministic
- 3. Three candidate engines
- BrushSettingsPanel
- TransformOverlaySupport.swift
- 1. The central problem
- CutOutcome
- ActionsMenu
- 6. Guide strokes
- PaintApp
- Kind
- orchestrator
- ProjectStore.swift
- 7. Edge cases from the brief
- Foundation
- worker-bugfix
- worker-feature
- worker-integration
- worker-test
- worker-ui

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 394 edges
2. `CGFloat` - 336 edges
3. `VectorCanvas` - 112 edges
4. `CanvasManager` - 95 edges
5. `VectorSample` - 94 edges
6. `Lattice` - 89 edges
7. `Coordinator` - 74 edges
8. `ShapeGeometry` - 73 edges
9. `layers` - 73 edges
10. `Brush` - 64 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift

## Import Cycles
- None detected.

## Communities (129 total, 6 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (46): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+38 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.12
Nodes (16): DateFormatter, name, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory, .trashDirectory (+8 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.06
Nodes (43): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+35 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (38): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .hasLoopBoundary (+30 more)

### Community 7 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (6): StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.10
Nodes (22): Kind, fill, image, stroke, Bool, CGAffineTransform, CGRect, CGSize (+14 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "CGPoint"
Cohesion: 0.05
Nodes (40): Void, Constraint, CGFloat, CGPoint, .length, ClosedFit, ShapeDetector, Bool (+32 more)

### Community 14 - ".setCanvasPadding"
Cohesion: 0.39
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 15 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (22): StrokeInput, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+14 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 17 - "ContentView"
Cohesion: 0.20
Nodes (9): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+1 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.10
Nodes (18): ARAPRegistration, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty, Result (+10 more)

### Community 19 - ".warped"
Cohesion: 0.14
Nodes (19): CGPathElementType, ContentProvider, Direction, backward, forward, Evaluation, GroupWarp, InterpolationEvaluator (+11 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.15
Nodes (16): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+8 more)

### Community 21 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, brush, color, composite, elements, fill, fills, id (+13 more)

### Community 22 - "URL"
Cohesion: 0.13
Nodes (12): ProjectBackup, .id, Bool, URL, UUID, .body, BackupManagerLogicTests, Int (+4 more)

### Community 23 - "CanvasManager"
Cohesion: 0.09
Nodes (25): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+17 more)

### Community 24 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 25 - "InterpolationWorkflowLogicTests"
Cohesion: 0.09
Nodes (20): cels, InterpolationReferenceOnionSkinSource, OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CGSize, UIColor, UIImage (+12 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "VectorSample"
Cohesion: 0.21
Nodes (8): VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, VectorEraser, samples

### Community 28 - ".stampStroke"
Cohesion: 0.16
Nodes (12): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+4 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.23
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.20
Nodes (6): .activeLayerIsVector, CanvasManager, Bool, Int, Void, layers

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 33 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 35 - "LayerFolder"
Cohesion: 0.10
Nodes (17): CelLocation, String, UUID, CanvasManager, .activeViewName, Int, String, LayerFolder (+9 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.07
Nodes (32): Content, Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+24 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - ".load"
Cohesion: 0.12
Nodes (23): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+15 more)

### Community 41 - "View"
Cohesion: 0.16
Nodes (19): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+11 more)

### Community 42 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 43 - "StrokeGestureRecognizer"
Cohesion: 0.27
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "InterpolationRecipe"
Cohesion: 0.19
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.10
Nodes (21): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 8. Performance — the real constraint (+13 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 50 - "CGContextDabTarget"
Cohesion: 0.27
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 51 - "SwiftUI"
Cohesion: 0.17
Nodes (3): Combine, PhotosUI, SwiftUI

### Community 52 - "StrokeGeometry"
Cohesion: 0.16
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 53 - "DeformFactorization"
Cohesion: 0.10
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, guideStrokes (+11 more)

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - ".makeUIView"
Cohesion: 0.12
Nodes (7): LayerHostView, NSCoder, CanvasView, Context, Coordinator, LayerTransform, UIImageView

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 12. Open work, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.05
Nodes (39): IndexPath, LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+31 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.21
Nodes (19): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+11 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.16
Nodes (6): ARAPInterpolation, ARAPLogicTests, Int, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "agent"
Cohesion: 0.20
Nodes (9): agent, worker-research, model, plugin, $schema, description, mode, model (+1 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 69 - "Codable"
Cohesion: 0.10
Nodes (30): Codable, CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image (+22 more)

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.11
Nodes (19): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4.7 — Engine correctness: what the deformation actually does — ***next, ahead of Phase 5*** (+11 more)

### Community 77 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 78 - "ProjectVersionsView"
Cohesion: 0.47
Nodes (4): ProjectVersionsView, RecentlyDeletedView, .body, Void

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.05
Nodes (42): 1. Start-of-session checklist, 2. Current state, 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol (+34 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.08
Nodes (25): CanvasManager, .interpolationContentProvider, .interpolationKeyframes, .interpolationTarget, InterpolationRefusal, alreadyInterpolated, .message, notAVectorLayer (+17 more)

### Community 84 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 85 - "Equatable"
Cohesion: 0.17
Nodes (14): Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+6 more)

### Community 86 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 87 - "MotionGroup"
Cohesion: 0.23
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 88 - "SelectionMode"
Cohesion: 0.29
Nodes (7): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage

### Community 89 - "UIKit"
Cohesion: 0.09
Nodes (5): CoreGraphics, Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "Brush"
Cohesion: 0.05
Nodes (43): CaseIterable, Identifiable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten (+35 more)

### Community 92 - "StructureSnapshot"
Cohesion: 0.23
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 93 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .body, .commandRow, .commands, .referenceButton, .referenceSummary (+8 more)

### Community 94 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 99 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 100 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+12 more)

### Community 101 - "Coordinator"
Cohesion: 0.08
Nodes (23): AppliedTool, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, CGSize, Color, Date (+15 more)

### Community 108 - "VectorImageElement"
Cohesion: 0.23
Nodes (7): RenderQuality, full, preview, CGContext, LayerTransform, UIImage, VectorImageElement

### Community 109 - "InterpolatePanel"
Cohesion: 0.33
Nodes (5): .interpolateButton, InterpolatePanel, .body, .options, CanvasManager

### Community 111 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 112 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 114 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 117 - "6. Guide strokes"
Cohesion: 0.40
Nodes (5): 6.1 What they are, 6.2 The controls from requirement 6, 6.3 The data gap, 6.4 Reuse across frames (requirement 7), 6. Guide strokes

### Community 118 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 119 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 120 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 121 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 122 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 123 - "Foundation"
Cohesion: 0.11
Nodes (10): Foundation, Tool, eraser, fill, pen, pencil, Notification.Name, AppVersion (+2 more)

### Community 124 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 125 - "worker-feature"
Cohesion: 0.50
Nodes (4): worker-feature, description, mode, model

### Community 126 - "worker-integration"
Cohesion: 0.50
Nodes (4): worker-integration, description, mode, model

### Community 127 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

### Community 128 - "worker-ui"
Cohesion: 0.50
Nodes (4): worker-ui, description, mode, model

## Knowledge Gaps
- **551 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+546 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGPoint` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `.setCanvasPadding`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.warped`, `.transparentFormat`, `CodingKeys`, `CanvasManager`, `CanvasManager`, `InterpolationWorkflowLogicTests`, `VectorSample`, `.stampStroke`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `.load`, `Lattice`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `RasterLayerTexture`, `CGContextDabTarget`, `StrokeGeometry`, `DeformFactorization`, `Color`, `.makeUIView`, `LayerRowModel`, `SideToolbar`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `CanvasManager`, `Codable`, `StrokeStabilizer`, `EraserSettingsPanel`, `CanvasManager`, `Equatable`, `DrawingView`, `Brush`, `InterpolateBar`, `Coordinator`, `VectorImageElement`, `Deterministic`, `TransformOverlaySupport.swift`, `ActionsMenu`, `Kind`?**
  _High betweenness centrality (0.323) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `.setCanvasPadding`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.warped`, `.transparentFormat`, `CanvasManager`, `CanvasManager`, `InterpolationWorkflowLogicTests`, `VectorSample`, `.stampStroke`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `AnimationTimeline`, `FloatingPieceOverlayView`, `Lattice`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `InterpolationRecipe`, `SelectionOverlayView`, `RasterLayerTexture`, `CGContextDabTarget`, `StrokeGeometry`, `DeformFactorization`, `.makeUIView`, `LayerRowModel`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `CanvasManager`, `StrokeStabilizer`, `CanvasManager`, `Equatable`, `Coordinator`, `VectorImageElement`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.191) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CGPoint`, `.setCanvasPadding`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `VectorSample`, `layers`, `CanvasManager`, `LayerFolder`, `InterpolationRecipe`, `RasterLayerTexture`, `SwiftUI`, `PerfMonitor`, `ProjectManifest`, `UndoHistory`, `Equatable`, `MotionGroup`, `SelectionMode`, `Brush`, `StructureSnapshot`, `Foundation`?**
  _High betweenness centrality (0.106) - this node is a cross-community bridge._
- **Are the 53 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 53 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._