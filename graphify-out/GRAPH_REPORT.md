# Graph Report - vector-interpolation-keyframes-d484df  (2026-07-31)

## Corpus Check
- 121 files · ~213,222 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2735 nodes · 7255 edges · 112 communities (107 shown, 5 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 893 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `72ac6a92`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
- ProjectBackupManager
- .manager
- TimelineRowView
- Palette
- CanvasManager
- bash
- StrokeGeometry
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- ShapeGeometry
- Brush
- StrokeCanvasView
- StrokeGeometryLogicTests
- ContentView
- ShapeDetectorLogicTests
- FloatingPiece
- .transparentFormat
- VectorStroke
- Coordinator
- CanvasManager
- CanvasManager
- .erase
- MetalFillEngine
- VectorSample
- .stampStroke
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- StrokeSpatialIndex
- .withStructureUndo
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
- .reconcileLayers
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- ColorPickerPanel
- UIKit
- XCTest
- DrawingView
- PerfMonitor
- CodingKeys
- Color
- LayerRowModel
- Vector Eraser — Design Plan
- Coordinator
- Codable
- SideToolbar
- CodingKeys
- CanvasSizePickerView
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
- Vector Interpolation — Implementation Plan
- LayerStackRow
- ProjectSummary
- SelectionMode
- Vector Interpolation — Handoff & Session Protocol
- Multi-Session Protocol
- EraserSettingsPanel
- .canvasTouchCountChanged
- Corner
- ActionsMenu
- .makeUIView
- BrushSettingsPanel
- Tool
- SaveSnapshot
- CutOutcome
- ProjectStore.swift
- VectorScratchRole
- AppliedTool
- Identifiable
- Atomic
- parallel_test.sh
- MoveTransformBottomBar
- 1. The central problem
- .tableView
- CanvasView
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- 3. Session protocol
- TransformHandleView
- Edge
- 2. Data model

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

## Communities (112 total, 5 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (23): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, CGFloat, Double, Int (+15 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (48): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+40 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (40): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+32 more)

### Community 5 - "Palette"
Cohesion: 0.17
Nodes (15): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+7 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (32): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+24 more)

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
Nodes (28): image, kind, Kind, fill, image, stroke, CGAffineTransform, CGContext (+20 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (10): BrushEngineLogicTests, Any, CGFloat, CodableColor, Int, String, UIColor, UIImage (+2 more)

### Community 13 - "ShapeGeometry"
Cohesion: 0.11
Nodes (17): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+9 more)

### Community 14 - "Brush"
Cohesion: 0.19
Nodes (8): Equatable, Brush, BrushDynamics, BrushGrain, Bool, CGFloat, Double, UUID

### Community 15 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (26): StrokeInput, CGFloat, CGPoint, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole (+18 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.10
Nodes (9): Deterministic, StrokeGeometryLogicTests, .fixedBrush, .ramp, CGFloat, StaticString, String, UInt (+1 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "ShapeDetectorLogicTests"
Cohesion: 0.18
Nodes (5): ShapeDetectorLogicTests, CGFloat, CGPoint, CGRect, Int

### Community 19 - "FloatingPiece"
Cohesion: 0.10
Nodes (22): CanvasManager, Bool, CGFloat, CGSize, UIImage, FloatingPiece, .transformedBounds, FloatingTransform (+14 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.15
Nodes (17): IntPoint, PixelOps, Bool, Cel, CGFloat, CGPath, CGPoint, CGRect (+9 more)

### Community 21 - "VectorStroke"
Cohesion: 0.09
Nodes (31): Encoder, CodableColor, .uiColor, ElementData, fill, image, stroke, ImageRef (+23 more)

### Community 22 - "Coordinator"
Cohesion: 0.14
Nodes (14): Coordinator, CGSize, Date, NSLayoutConstraint, TimeInterval, Timer, UILongPressGestureRecognizer, UIPanGestureRecognizer (+6 more)

### Community 23 - "CanvasManager"
Cohesion: 0.13
Nodes (10): String, UUID, Void, CanvasManager, Selection, Bool, CGPath, Int (+2 more)

### Community 24 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, FillKey, Bool, Cel, CGFloat, CGPoint, Float, Int (+9 more)

### Community 25 - ".erase"
Cohesion: 0.28
Nodes (5): DabLattice, .range, Bool, CGFloat, ClosedRange

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "VectorSample"
Cohesion: 0.20
Nodes (10): VectorSample, Sweep, Bool, CGFloat, CGPoint, CGRect, ClosedRange, Double (+2 more)

### Community 28 - ".stampStroke"
Cohesion: 0.14
Nodes (16): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, CGFloat (+8 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.18
Nodes (8): PerfBaselineTests, CanvasManager, CGFloat, Double, Int, String, UIImage, UInt64

### Community 30 - "layers"
Cohesion: 0.18
Nodes (11): .activeLayerIsVector, Bool, CanvasManager, Bool, Int, Cel, .endFrame, Int (+3 more)

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
Cohesion: 0.17
Nodes (12): Int32, Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGFloat (+4 more)

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
Cohesion: 0.11
Nodes (19): Gesture, AnimationTimeline, .body, .collapsedBar, .contentHeight, .dragHandle, .fittedHeight, .isCollapsed (+11 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+3 more)

### Community 40 - ".load"
Cohesion: 0.29
Nodes (6): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, URL

### Community 41 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 42 - "ShapeDetector"
Cohesion: 0.27
Nodes (7): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int

### Community 43 - "LayerStackCell"
Cohesion: 0.12
Nodes (11): LayerStackCell, Bool, CGFloat, Double, Int, NSCoder, NSLayoutConstraint, String (+3 more)

### Community 44 - "UIView"
Cohesion: 0.17
Nodes (13): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+5 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - ".reconcileLayers"
Cohesion: 0.21
Nodes (3): LayerHostView, NSCoder, UIImageView

### Community 47 - "SelectionOverlayView"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.04
Nodes (46): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 3. Three candidate engines, 4. The load-bearing decision: an inbetween is *derived*, never *stored* (+38 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.10
Nodes (22): CGGradient, CGContextDabTarget, DabGradientCache, Key, RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent (+14 more)

### Community 50 - "ColorPickerPanel"
Cohesion: 0.11
Nodes (20): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .paletteSelectionBinding, .palettesTab (+12 more)

### Community 51 - "UIKit"
Cohesion: 0.14
Nodes (8): Combine, FloatingPieceKind, duplicate, move, PhotosUI, QuartzCore, SwiftUI, UIKit

### Community 52 - "XCTest"
Cohesion: 0.06
Nodes (11): CoreGraphics, Darwin, Foundation, LayerTransform, CGFloat, CGPoint, Notification.Name, AppVersion (+3 more)

### Community 53 - "DrawingView"
Cohesion: 0.22
Nodes (8): Alignment, DrawingView, .panelAlignment, Bool, CanvasManager, CGFloat, UUID, Void

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
Cohesion: 0.10
Nodes (20): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 3.1 `StrokeGeometry` (pure functions), 3.2 `StrokeSpatialIndex`, 3. Shared geometry foundation, 4. Per-mode implementation, 5. Tool and UI plumbing, 6. Performance (+12 more)

### Community 59 - "Coordinator"
Cohesion: 0.22
Nodes (10): NSObject, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID (+2 more)

### Community 60 - "Codable"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 62 - "CodingKeys"
Cohesion: 0.12
Nodes (17): CodingKey, CodingKeys, brush, color, composite, elements, fill, fills (+9 more)

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

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
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.19
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, CGFloat (+2 more)

### Community 69 - "VectorEraserMode"
Cohesion: 0.09
Nodes (22): CaseIterable, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+14 more)

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
Cohesion: 0.06
Nodes (29): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+21 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.12
Nodes (17): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone* (+9 more)

### Community 77 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 78 - "ProjectSummary"
Cohesion: 0.19
Nodes (10): ProjectSummary, Date, UIImage, GalleryTileView, .body, Void, GalleryView, .body (+2 more)

### Community 79 - "SelectionMode"
Cohesion: 0.11
Nodes (16): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage, SelectPanel (+8 more)

### Community 80 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.12
Nodes (16): 1. Start-of-session checklist, 2. Current state, 4. Build and test, 5. Carry-overs, 6. Session log, 7. Handoff prompt template, 8. Suggested follow-on work, After changing code (+8 more)

### Community 81 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - ".canvasTouchCountChanged"
Cohesion: 0.24
Nodes (4): Bool, Int, UIGestureRecognizer, UIImage

### Community 84 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 85 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 86 - ".makeUIView"
Cohesion: 0.27
Nodes (3): CGPoint, Context, LayerTransform

### Community 87 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 88 - "Tool"
Cohesion: 0.18
Nodes (10): Hashable, CelLocation, Tool, eraser, fill, pen, pencil, Tab (+2 more)

### Community 89 - "SaveSnapshot"
Cohesion: 0.36
Nodes (10): CelContent, LayerContent, SaveSnapshot, Bool, CanvasManager, CGSize, Double, Int (+2 more)

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

### Community 94 - "Identifiable"
Cohesion: 0.20
Nodes (10): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+2 more)

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 99 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 100 - ".tableView"
Cohesion: 0.50
Nodes (3): IndexPath, CGFloat, UISwipeActionsConfiguration

### Community 101 - "CanvasView"
Cohesion: 0.29
Nodes (5): CanvasView, CanvasManager, Coordinator, .body, UIViewRepresentable

### Community 108 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

### Community 109 - "TransformHandleView"
Cohesion: 0.40
Nodes (5): Kind, rotate, scale, NSCoder, TransformHandleView

### Community 110 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 111 - "2. Data model"
Cohesion: 0.50
Nodes (4): 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model

## Knowledge Gaps
- **455 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+450 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `.withStructureUndo`, `VectorEraserMode`, `UndoHistory`, `LayerKind`, `ShapeGeometry`, `Brush`, `SelectionMode`, `RasterLayerTexture`, `UIKit`, `FloatingPiece`, `PerfMonitor`, `CanvasManager`, `Tool`, `CanvasManager`, `MetalFillEngine`, `VectorSample`, `layers`?**
  _High betweenness centrality (0.142) - this node is a cross-community bridge._
- **Why does `VectorSample` connect `VectorSample` to `VectorEraserHybridLogicTests`, `CanvasManager`, `StrokeGeometry`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `Brush`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `ShapeDetectorLogicTests`, `VectorStroke`, `Coordinator`, `CanvasManager`, `.erase`, `.stampStroke`, `PerfBaselineTests`, `StrokeSpatialIndex`, `ProjectSaveLogicTests`, `.reconcileLayers`, `XCTest`, `Codable`, `CanvasManager`?**
  _High betweenness centrality (0.134) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `.manager` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `ProjectBackupManager`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `ProjectSaveLogicTests`, `StrokeGeometryLogicTests`, `ShapeDetectorLogicTests`, `XCTest`, `PerfBaselineTests`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `VectorCanvas` (e.g. with `.testEraseHeavyVectorLayerCostAndMemory()` and `.testVectorLayerRenderCostAndMemory()`) actually correct?**
  _`VectorCanvas` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `VectorSample` (e.g. with `.cancelShapeDetection()` and `.fireShapeDetection()`) actually correct?**
  _`VectorSample` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `ShapeGeometry` (e.g. with `.testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce()` and `.testCollapseAppliesRotationSoTheBakedStrokeMatchesThePreview()`) actually correct?**
  _`ShapeGeometry` has 22 INFERRED edges - model-reasoned connections that need verification._