# Graph Report - animation-block-shuffle-538212  (2026-08-10)

## Corpus Check
- 148 files · ~275,680 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3620 nodes · 12205 edges · 124 communities (113 shown, 11 thin omitted)
- Extraction: 82% EXTRACTED · 18% INFERRED · 0% AMBIGUOUS · INFERRED: 2235 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `32410388`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .beginInteractiveFill
- .launchIntoEditor
- .setCelLayout
- PerfBaselineTests
- cels
- Coordinator
- StrokeGeometryLogicTests
- StrokeCanvasView
- ColorPickerPanel
- Brush
- LatticeLogicTests
- InterpolationRecipe
- .arched
- .transparentFormat
- InterpolationMotionGroupLogicTests
- bash
- String
- ProjectBackupManager
- ParityScenario
- CanvasManager
- Lattice
- VectorCanvas
- LayerRowModel
- VectorEraserLogicTests
- CodableColor
- VectorEraserHybridLogicTests
- PointCloudIndex
- .registerGroups
- RasterLayerTexture
- BrushDynamics
- UIKit
- Coordinator
- .load
- InterpolationRenderLogicTests
- .soleGuide
- ARAPLogicTests
- ShapeGeometry
- XCTestCase
- AnimationTimeline
- StrokeSpatialIndex
- DeformFactorization
- .evaluate
- MetalFillEngine
- PlaybackBoundsCharacterizationTests
- View
- StrokeSettingsPanel
- Codable
- .moveCelToLayer
- GuideOverlayView
- FillParams
- GuideStroke
- .restackFolder
- GuideRow
- LayerStackCell
- ShapeOverlayView
- SwiftUI
- SpacingChart
- ShapeDetectorLogicTests
- .setUpGestures
- ActivePanel
- LayerFolder
- FloatingPieceOverlayView
- MotionGroup
- SelectionOverlayView
- ContentView
- CodingKeys
- ShapeDetector
- .manager
- CGPoint
- StrokeGeometry
- Foundation
- InterpolationGuideLogicTests
- CodingKeys
- SelectionMode
- Color
- InterpolationRefusal
- BrushSettingsPanel
- CanvasSizePickerView
- UndoHistory
- TouchCountRecognizer
- SideToolbar
- DrawingView
- .group
- StrokeGestureRecognizer
- ObjectTransformOverlayView
- TransformMode
- CanvasHostView
- InterpolationModelLogicTests
- GuidePath
- LayerStackRow
- CGFloat
- HandleKind
- 4. Future upgrades — the deferred list
- Is the brush engine ready for `.ABR` / Procreate brush import?
- ActionsMenu
- layers
- Corner
- PaintSoftware - iPad Drawing and Animation App
- OnionSkinLogicTests
- Identifiable
- Usage Guide
- CutOutcome
- Kind
- .activeCelIndex
- VectorEraserMode
- CLAUDE.md
- Known Issues
- .indices
- .commitFloatingPieceIfNeeded
- .refreshUndoRedoState
- Cel
- What needs to change
- Multi-Session Protocol
- parallel_test.sh
- Performance baseline
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- CopiedCel
- ThumbnailRenderer.swift

## God Nodes (most connected - your core abstractions)
1. `CanvasManager` - 596 edges
2. `CGPoint` - 533 edges
3. `CGFloat` - 402 edges
4. `VectorCanvas` - 116 edges
5. `layers` - 106 edges
6. `Lattice` - 99 edges
7. `VectorSample` - 97 edges
8. `InterpolationGuideLogicTests` - 90 edges
9. `Coordinator` - 79 edges
10. `CodableColor` - 75 edges

## Surprising Connections (you probably didn't know these)
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `ARAPLogicTests` --references--> `CGPoint`  [EXTRACTED]
  PaintSoftwareUITests/ARAPLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `.rigidMotionL` --calls--> `CGFloat`  [EXTRACTED]
  PaintSoftwareUITests/ARAPLogicTests.swift → PaintSoftware/Engine/Deform/Lattice.swift

## Import Cycles
- None detected.

## Communities (124 total, 11 thin omitted)

### Community 0 - ".beginInteractiveFill"
Cohesion: 0.15
Nodes (9): FillKey, Cel, Float, Int, Layer, SIMD4, UIColor, UIImage (+1 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 2 - ".setCelLayout"
Cohesion: 0.11
Nodes (6): Bool, .gapMenu, CanvasFixture, Int, CelCRUDCharacterizationTests, Int

### Community 3 - "PerfBaselineTests"
Cohesion: 0.06
Nodes (31): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+23 more)

### Community 4 - "cels"
Cohesion: 0.13
Nodes (8): cels, InterpolationReferenceOnionSkinSource, InterpolationWorkflowLogicTests, Bool, Cel, Int, UUID, VectorStroke

### Community 5 - "Coordinator"
Cohesion: 0.06
Nodes (41): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+33 more)

### Community 6 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (7): Intersection, samples, StrokeGeometryLogicTests, .ramp, StaticString, String, UInt

### Community 7 - "StrokeCanvasView"
Cohesion: 0.07
Nodes (32): StrokeInput, TimeInterval, UITouch, UIView, String, UUID, Void, StrokeCanvasView (+24 more)

### Community 8 - "ColorPickerPanel"
Cohesion: 0.05
Nodes (50): CADisplayLink, CFTimeInterval, ObservableObject, Palette, PaletteColor, .color, PaletteStore, .palettes (+42 more)

### Community 9 - "Brush"
Cohesion: 0.11
Nodes (8): Brush, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser, .fixedBrush

### Community 10 - "LatticeLogicTests"
Cohesion: 0.15
Nodes (5): LatticeLogicTests, Int, StaticString, String, UInt

### Community 11 - "InterpolationRecipe"
Cohesion: 0.12
Nodes (17): Equatable, Set, CelRef, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed (+9 more)

### Community 12 - ".arched"
Cohesion: 0.15
Nodes (5): GuideSet, .isEmpty, Bool, Cel, UUID

### Community 13 - ".transparentFormat"
Cohesion: 0.16
Nodes (15): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+7 more)

### Community 14 - "InterpolationMotionGroupLogicTests"
Cohesion: 0.12
Nodes (7): InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, Cel, Int, UUID, VectorStroke

### Community 15 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 16 - "String"
Cohesion: 0.07
Nodes (34): CodingKeys, brush, color, composite, elements, fill, fills, id (+26 more)

### Community 17 - "ProjectBackupManager"
Cohesion: 0.05
Nodes (46): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+38 more)

### Community 18 - "ParityScenario"
Cohesion: 0.08
Nodes (35): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+27 more)

### Community 19 - "CanvasManager"
Cohesion: 0.04
Nodes (50): CanvasManager, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState, .isShapeFollowingFinger (+42 more)

### Community 20 - "Lattice"
Cohesion: 0.08
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 21 - "VectorCanvas"
Cohesion: 0.06
Nodes (47): AnyObject, DabTarget, image, kind, DabLattice, .range, Kind, fill (+39 more)

### Community 22 - "LayerRowModel"
Cohesion: 0.09
Nodes (28): IndexPath, Coordinator, DropTarget, between, onto, LayerRowModel, .folderID, LayerStackListView (+20 more)

### Community 23 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 24 - "CodableColor"
Cohesion: 0.13
Nodes (15): .uiColor, UIColor, CodableColor, .color, BrushEngineLogicTests, Any, Data, Double (+7 more)

### Community 25 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 26 - "PointCloudIndex"
Cohesion: 0.14
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 28 - "RasterLayerTexture"
Cohesion: 0.09
Nodes (22): CGGradient, CGContextDabTarget, DabGradientCache, Key, RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent (+14 more)

### Community 29 - "BrushDynamics"
Cohesion: 0.14
Nodes (8): BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory, URL

### Community 30 - "UIKit"
Cohesion: 0.08
Nodes (5): Combine, CoreGraphics, Darwin, UIKit, XCTest

### Community 31 - "Coordinator"
Cohesion: 0.07
Nodes (26): NSObject, Bool, LayerHostView, NSCoder, AppliedTool, CanvasView, Coordinator, InterpolationPreviewKey (+18 more)

### Community 32 - ".load"
Cohesion: 0.15
Nodes (18): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CGSize (+10 more)

### Community 33 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (10): fill, ID, InterpolationRenderLogicTests, CGSize, Double, Int, UIImage, UUID (+2 more)

### Community 35 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (8): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, StaticString, String, UInt

### Community 36 - "ShapeGeometry"
Cohesion: 0.10
Nodes (19): Edge, bottom, left, right, top, FollowFrame, ShapeGeometry, .boundingRect (+11 more)

### Community 37 - "XCTestCase"
Cohesion: 0.19
Nodes (9): String, Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests (+1 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.09
Nodes (24): Content, Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed (+16 more)

### Community 39 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 40 - "DeformFactorization"
Cohesion: 0.14
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 41 - ".evaluate"
Cohesion: 0.11
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 42 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 43 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.14
Nodes (4): .loopMenu, PlaybackBoundsCharacterizationTests, Bool, Int

### Community 44 - "View"
Cohesion: 0.11
Nodes (24): ButtonRole, String, Void, .layerPanelRail, LayerOptionsPanel, .layerIndex, .mergeTargetIndex, LayerPanel (+16 more)

### Community 45 - "StrokeSettingsPanel"
Cohesion: 0.11
Nodes (24): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+16 more)

### Community 46 - "Codable"
Cohesion: 0.24
Nodes (18): Codable, LayerKind, compositing, raster, vector, CelManifest, FolderManifest, LayerManifest (+10 more)

### Community 47 - ".moveCelToLayer"
Cohesion: 0.11
Nodes (13): CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel, Int (+5 more)

### Community 48 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 49 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 50 - "GuideStroke"
Cohesion: 0.13
Nodes (12): Layer, Void, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+4 more)

### Community 51 - ".restackFolder"
Cohesion: 0.17
Nodes (11): .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange, Int (+3 more)

### Community 52 - "GuideRow"
Cohesion: 0.20
Nodes (9): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+1 more)

### Community 53 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 54 - "ShapeOverlayView"
Cohesion: 0.14
Nodes (14): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, ShapeOverlayView (+6 more)

### Community 55 - "SwiftUI"
Cohesion: 0.09
Nodes (10): .interpolateButton, GalleryTileView, .body, Void, InterpolatePanel, .body, .groupOverlayOption, .options (+2 more)

### Community 56 - "SpacingChart"
Cohesion: 0.23
Nodes (3): SpacingChart, .curve, .draggable

### Community 57 - "ShapeDetectorLogicTests"
Cohesion: 0.14
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 58 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): Bool, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 59 - "ActivePanel"
Cohesion: 0.14
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+9 more)

### Community 60 - "LayerFolder"
Cohesion: 0.22
Nodes (6): String, LayerFolder, Bool, String, UUID, folders

### Community 61 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (18): FloatingTransform, .affineTransform, CGAffineTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int (+10 more)

### Community 62 - "MotionGroup"
Cohesion: 0.31
Nodes (7): GroupInterpolation, auto, clean, crossFade, MotionGroup, Decoder, UUID

### Community 63 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 64 - "ContentView"
Cohesion: 0.12
Nodes (13): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+5 more)

### Community 65 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 66 - "ShapeDetector"
Cohesion: 0.21
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 67 - ".manager"
Cohesion: 0.21
Nodes (6): .activeViewName, Int, viewPresets, .body, Bool, ViewPresetCharacterizationTests

### Community 68 - "CGPoint"
Cohesion: 0.13
Nodes (10): CGPoint, .length, .point, StrokeStabilizer, .stabilization, Double, .rigidMotionL, InterpolationEngineDiagnosticsLogicTests (+2 more)

### Community 69 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 70 - "Foundation"
Cohesion: 0.12
Nodes (7): Foundation, Notification.Name, Color, .codable, AppVersion, .versionString, String

### Community 71 - "InterpolationGuideLogicTests"
Cohesion: 0.16
Nodes (5): TimeInterval, TimedSample, .point, InterpolationGuideLogicTests, TimeInterval

### Community 72 - "CodingKeys"
Cohesion: 0.05
Nodes (37): CodingKey, CodingKeys, boundGroups, id, interval, role, samples, CodingKeys (+29 more)

### Community 73 - "SelectionMode"
Cohesion: 0.25
Nodes (7): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage

### Community 74 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 75 - "InterpolationRefusal"
Cohesion: 0.08
Nodes (24): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+16 more)

### Community 76 - "BrushSettingsPanel"
Cohesion: 0.10
Nodes (17): FillAxis, edgeOverlap, gapClosing, threshold, BrushSettingsPanel, .body, .importCustomBrushRow, .preview (+9 more)

### Community 77 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 78 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 79 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 80 - "SideToolbar"
Cohesion: 0.19
Nodes (12): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, ClosedRange (+4 more)

### Community 81 - "DrawingView"
Cohesion: 0.09
Nodes (18): Alignment, DrawingView, .body, .panelAlignment, Bool, UUID, Void, MoveTransformBottomBar (+10 more)

### Community 82 - ".group"
Cohesion: 0.18
Nodes (7): Group, MotionGrouping, Options, Int, Set, groups, Int

### Community 83 - "StrokeGestureRecognizer"
Cohesion: 0.27
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 84 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (11): ObjectTransformOverlayView, CGRect, CGSize, NSCoder, UIPanGestureRecognizer, Void, Kind, rotate (+3 more)

### Community 85 - "TransformMode"
Cohesion: 0.18
Nodes (10): Bool, TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform (+2 more)

### Community 86 - "CanvasHostView"
Cohesion: 0.14
Nodes (8): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, String, Void, UIKeyCommand

### Community 87 - "InterpolationModelLogicTests"
Cohesion: 0.11
Nodes (9): InterpolationModelLogicTests, Data, Set, String, T, URL, UUID, VectorStroke (+1 more)

### Community 88 - "GuidePath"
Cohesion: 0.23
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 89 - "LayerStackRow"
Cohesion: 0.14
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 90 - "CGFloat"
Cohesion: 0.18
Nodes (8): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, VectorSample

### Community 91 - "HandleKind"
Cohesion: 0.13
Nodes (15): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+7 more)

### Community 92 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 93 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 94 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .content, .pencilOnlyToggle, Double, PhotosPickerItem, String

### Community 95 - "layers"
Cohesion: 0.10
Nodes (16): .activeLayerIsVector, .activeLayerKind, .guideRefusal, .linkableGuideStrokes, Int, StructureSnapshot, Int, Layer (+8 more)

### Community 96 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 97 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 98 - "OnionSkinLogicTests"
Cohesion: 0.15
Nodes (10): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CGSize, UIColor, UIImage, OnionSkinLogicTests, Bool (+2 more)

### Community 99 - "Identifiable"
Cohesion: 0.06
Nodes (31): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+23 more)

### Community 100 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 101 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 102 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 103 - ".activeCelIndex"
Cohesion: 0.13
Nodes (13): .currentFrame, .currentLayerIndex, .interpolationTarget, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+5 more)

### Community 104 - "VectorEraserMode"
Cohesion: 0.13
Nodes (14): Hashable, Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode (+6 more)

### Community 106 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 108 - ".commitFloatingPieceIfNeeded"
Cohesion: 0.42
Nodes (3): Int, UIImage, UUID

### Community 109 - ".refreshUndoRedoState"
Cohesion: 0.21
Nodes (4): Bool, CGSize, UIImage, .paddingControl

### Community 110 - "Cel"
Cohesion: 0.33
Nodes (5): Cel, .endFrame, Int, UIImage, UUID

### Community 111 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 112 - "Multi-Session Protocol"
Cohesion: 0.40
Nodes (5): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol

### Community 113 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 114 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 125 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

## Knowledge Gaps
- **441 isolated node(s):** `graphify-guard.sh script`, `ID`, `Darwin`, `.value`, `.description` (+436 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CanvasManager` connect `CanvasManager` to `.beginInteractiveFill`, `.setCelLayout`, `PerfBaselineTests`, `cels`, `Coordinator`, `StrokeCanvasView`, `ColorPickerPanel`, `Brush`, `InterpolationRecipe`, `.arched`, `.transparentFormat`, `InterpolationMotionGroupLogicTests`, `ProjectBackupManager`, `VectorCanvas`, `LayerRowModel`, `CodableColor`, `.registerGroups`, `RasterLayerTexture`, `UIKit`, `Coordinator`, `.load`, `.soleGuide`, `ShapeGeometry`, `XCTestCase`, `AnimationTimeline`, `.evaluate`, `MetalFillEngine`, `PlaybackBoundsCharacterizationTests`, `View`, `StrokeSettingsPanel`, `Codable`, `.moveCelToLayer`, `GuideStroke`, `.restackFolder`, `GuideRow`, `SwiftUI`, `SpacingChart`, `.setUpGestures`, `ActivePanel`, `LayerFolder`, `FloatingPieceOverlayView`, `MotionGroup`, `ContentView`, `.manager`, `InterpolationGuideLogicTests`, `SelectionMode`, `InterpolationRefusal`, `BrushSettingsPanel`, `CanvasSizePickerView`, `UndoHistory`, `SideToolbar`, `DrawingView`, `TransformMode`, `CanvasHostView`, `InterpolationModelLogicTests`, `LayerStackRow`, `CGFloat`, `ActionsMenu`, `layers`, `OnionSkinLogicTests`, `.activeCelIndex`, `VectorEraserMode`, `.commitFloatingPieceIfNeeded`, `.refreshUndoRedoState`, `CopiedCel`?**
  _High betweenness centrality (0.402) - this node is a cross-community bridge._
- **Why does `CGFloat` connect `CGFloat` to `.beginInteractiveFill`, `.launchIntoEditor`, `PerfBaselineTests`, `cels`, `Coordinator`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `Brush`, `LatticeLogicTests`, `InterpolationRecipe`, `.arched`, `.transparentFormat`, `InterpolationMotionGroupLogicTests`, `String`, `ParityScenario`, `CanvasManager`, `Lattice`, `VectorCanvas`, `LayerRowModel`, `VectorEraserLogicTests`, `CodableColor`, `VectorEraserHybridLogicTests`, `PointCloudIndex`, `.registerGroups`, `RasterLayerTexture`, `BrushDynamics`, `Coordinator`, `.load`, `InterpolationRenderLogicTests`, `.soleGuide`, `ARAPLogicTests`, `ShapeGeometry`, `AnimationTimeline`, `StrokeSpatialIndex`, `DeformFactorization`, `.evaluate`, `StrokeSettingsPanel`, `.moveCelToLayer`, `GuideOverlayView`, `LayerStackCell`, `ShapeOverlayView`, `SpacingChart`, `ShapeDetectorLogicTests`, `FloatingPieceOverlayView`, `ShapeDetector`, `CGPoint`, `StrokeGeometry`, `InterpolationGuideLogicTests`, `Color`, `BrushSettingsPanel`, `SideToolbar`, `DrawingView`, `.group`, `ObjectTransformOverlayView`, `GuidePath`, `OnionSkinLogicTests`, `Identifiable`, `Kind`, `.activeCelIndex`, `.indices`, `.refreshUndoRedoState`?**
  _High betweenness centrality (0.267) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `.beginInteractiveFill`, `PerfBaselineTests`, `cels`, `Coordinator`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `ColorPickerPanel`, `Brush`, `LatticeLogicTests`, `InterpolationRecipe`, `.arched`, `.transparentFormat`, `InterpolationMotionGroupLogicTests`, `String`, `ProjectBackupManager`, `ParityScenario`, `CanvasManager`, `Lattice`, `VectorCanvas`, `LayerRowModel`, `VectorEraserLogicTests`, `CodableColor`, `VectorEraserHybridLogicTests`, `PointCloudIndex`, `.registerGroups`, `RasterLayerTexture`, `BrushDynamics`, `Coordinator`, `InterpolationRenderLogicTests`, `.soleGuide`, `ARAPLogicTests`, `ShapeGeometry`, `AnimationTimeline`, `StrokeSpatialIndex`, `DeformFactorization`, `.evaluate`, `GuideOverlayView`, `ShapeOverlayView`, `ShapeDetectorLogicTests`, `.setUpGestures`, `FloatingPieceOverlayView`, `SelectionOverlayView`, `ShapeDetector`, `StrokeGeometry`, `Foundation`, `InterpolationGuideLogicTests`, `.group`, `ObjectTransformOverlayView`, `InterpolationModelLogicTests`, `GuidePath`, `CGFloat`, `HandleKind`, `Identifiable`, `.activeCelIndex`, `.indices`, `.refreshUndoRedoState`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Are the 171 inferred relationships involving `CanvasManager` (e.g. with `UndoHistory` and `.blockMenu`) actually correct?**
  _`CanvasManager` has 171 INFERRED edges - model-reasoned connections that need verification._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `CGFloat` (e.g. with `.celInsertionIndex()` and `.load()`) actually correct?**
  _`CGFloat` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._