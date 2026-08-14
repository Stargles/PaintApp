# Graph Report - PaintApp-integrate  (2026-08-14)

## Corpus Check
- 162 files · ~353,568 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4319 nodes · 13267 edges · 157 communities (145 shown, 12 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1501 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `a66a0fab`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- Coordinator
- VectorCanvas
- CanvasManager
- Lattice
- CanvasManager
- CompositorParityLogicTests
- ShapeGeometry
- MaskParityLogicTests
- .encode
- CGFloat
- UIKit
- ColorPickerPanel
- ParityScenario
- .manager
- ProjectBackupManager
- StrokeCanvasView
- Coordinator
- AnimationTimeline
- CanvasManager
- VectorEraserLogicTests
- PointCloudIndex
- CanvasManager
- StrokeGeometryLogicTests
- layers
- ShapeOverlayView
- BrushEngineLogicTests
- RenderNode
- ARAPLogicTests
- Identifiable
- .rasterize
- VectorEraserHybridLogicTests
- SandwichLogicTests
- InterpolationRenderLogicTests
- String
- BlendMode
- PerfBaselineTests
- CGPoint
- .coverage
- CanvasManager
- InterpolationRecipe
- GuideOverlayView
- View
- InterpolationModelLogicTests
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- XCTestCase
- DeformFactorization
- InterpolationEvaluator
- RasterLayerTexture
- StrokeGeometry
- FloatingPieceOverlayView
- MaskSource
- BackupManagerLogicTests
- SaveSnapshot
- PerfMonitor
- FillParams
- Layer Compositing
- .load
- TouchCountRecognizer
- RenderTreeCharacterizationTests
- .makeUIView
- DrawingView
- LayerStackCell
- agent
- .stampStroke
- .group
- ActivePanel
- Composite.metal
- StrokeSpatialIndex
- InterpolationGuideLogicTests
- LatticeEmbedding
- GuideRow
- ViewPresetCharacterizationTests
- SwiftUI
- Compositor.swift
- CanvasManager
- CodingKeys
- ContentView
- Codable
- .indices
- OnionSkinLogicTests
- SelectionOverlayView
- Equatable
- Coordinator
- .withInterpolationUndo
- BlockDragCharacterizationTests
- .manager
- CodingKeys
- You are the Orchestrator for the rest of the layer-compositing project
- ShapeDetector
- Color
- GalleryView
- StructureSnapshot
- InterpolateBar
- .arched
- TimedSample
- VectorEraserMode
- CanvasSizePickerView
- DabTarget
- bash
- InterpolationRefusal
- SideToolbar
- UndoHistory
- ObjectTransformOverlayView
- Layer
- CanvasHostView
- GuidePath
- SpacingChart
- .testManySmallStrokesAllStayUndoableWithinTheBudget
- ViewPreset
- TransformOverlaySupport.swift
- LayerRowModel
- StrokeStabilizer
- LayerStackListView.Coordinator
- SelectPanel
- 4. Future upgrades — the deferred list
- compositeOver
- CanvasManager
- ActionsMenu
- .attach
- Is the brush engine ready for `.ABR` / Procreate brush import?
- .clearRasterizeCache
- .setCanvasPadding
- .handleTransformGesture
- PaintSoftware - iPad Drawing and Animation App
- Known Issues
- Usage Guide
- command
- CutOutcome
- CodingKeys
- Kind
- CLAUDE.md
- Multi-Session Protocol
- ManifestSkeleton
- CodingKeys
- ProjectStore.swift
- Atomic
- What needs to change
- parallel_test.sh
- Performance baseline
- worker-bugfix
- worker-research
- Direction
- AppVersion
- cleanup_session.sh
- screenshot.sh
- .init
- Kind
- SandwichPresentation
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- .encode

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 538 edges
2. `CGFloat` - 411 edges
3. `VectorCanvas` - 123 edges
4. `CanvasManager` - 116 edges
5. `layers` - 115 edges
6. `CanvasManager` - 100 edges
7. `VectorSample` - 99 edges
8. `Lattice` - 98 edges
9. `Coordinator` - 94 edges
10. `InterpolationGuideLogicTests` - 90 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (157 total, 12 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 2 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 3 - "VectorCanvas"
Cohesion: 0.06
Nodes (45): CodableColor, .uiColor, image, kind, DabLattice, .range, Kind, fill (+37 more)

### Community 4 - "CanvasManager"
Cohesion: 0.06
Nodes (27): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+19 more)

### Community 5 - "Lattice"
Cohesion: 0.08
Nodes (17): vertices, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration, .vertexCount, CGRect (+9 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (45): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+37 more)

### Community 7 - "CompositorParityLogicTests"
Cohesion: 0.09
Nodes (13): UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int (+5 more)

### Community 8 - "ShapeGeometry"
Cohesion: 0.06
Nodes (27): Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom, left (+19 more)

### Community 9 - "MaskParityLogicTests"
Cohesion: 0.09
Nodes (14): AlphaMask, .isActive, Bool, Float, CGImage, CGRect, UInt8, MaskParityLogicTests (+6 more)

### Community 10 - ".encode"
Cohesion: 0.08
Nodes (36): Metal, MTLBuffer, MTLCommandBuffer, MTLTexture, BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor (+28 more)

### Community 11 - "CGFloat"
Cohesion: 0.09
Nodes (10): Brush, CGFloat, VectorSample, .point, Sweep, Bool, ClosedRange, Double (+2 more)

### Community 12 - "UIKit"
Cohesion: 0.06
Nodes (8): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, ThumbnailRenderer, UIKit, XCTest

### Community 13 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 14 - "ParityScenario"
Cohesion: 0.09
Nodes (34): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+26 more)

### Community 15 - ".manager"
Cohesion: 0.13
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 16 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 17 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (31): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+23 more)

### Community 18 - "Coordinator"
Cohesion: 0.08
Nodes (22): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, Coordinator, .sandwichPresentation, InterpolationPreviewKey (+14 more)

### Community 19 - "AnimationTimeline"
Cohesion: 0.05
Nodes (41): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+33 more)

### Community 20 - "CanvasManager"
Cohesion: 0.07
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 21 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (8): CGRect, VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 22 - "PointCloudIndex"
Cohesion: 0.14
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 23 - "CanvasManager"
Cohesion: 0.08
Nodes (21): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+13 more)

### Community 24 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (8): Intersection, Deterministic, StrokeGeometryLogicTests, .ramp, StaticString, String, UInt, UInt64

### Community 25 - "layers"
Cohesion: 0.12
Nodes (15): .activeLayerIsVector, .activeCelIsInBetween, CanvasManager, Bool, Int, Void, Cel, .endFrame (+7 more)

### Community 26 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 27 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 28 - "RenderNode"
Cohesion: 0.08
Nodes (34): CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, Cel (+26 more)

### Community 29 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, Int, StaticString (+2 more)

### Community 30 - "Identifiable"
Cohesion: 0.07
Nodes (27): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+19 more)

### Community 31 - ".rasterize"
Cohesion: 0.13
Nodes (18): Hashable, IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath (+10 more)

### Community 32 - "VectorEraserHybridLogicTests"
Cohesion: 0.13
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 33 - "SandwichLogicTests"
Cohesion: 0.13
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 34 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 35 - "String"
Cohesion: 0.08
Nodes (32): CodingKeys, brush, color, composite, elements, fill, fills, id (+24 more)

### Community 36 - "BlendMode"
Cohesion: 0.05
Nodes (36): CaseIterable, Kind, line, oval, rectangle, BlendMode, add, clipToBelow (+28 more)

### Community 37 - "PerfBaselineTests"
Cohesion: 0.20
Nodes (5): PerfBaselineTests, Double, String, UInt64, VectorStroke

### Community 38 - "CGPoint"
Cohesion: 0.14
Nodes (12): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+4 more)

### Community 39 - ".coverage"
Cohesion: 0.13
Nodes (15): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, CacheKey (+7 more)

### Community 40 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 41 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (11): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve, Bool (+3 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 43 - "View"
Cohesion: 0.15
Nodes (27): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+19 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 46 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 47 - "XCTestCase"
Cohesion: 0.16
Nodes (10): CanvasFixture, CGSize, Layer, StaticString, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests (+2 more)

### Community 48 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 49 - "InterpolationEvaluator"
Cohesion: 0.14
Nodes (17): CGPathElementType, ContentProvider, Evaluation, InterpolationEvaluator, LocalEditPlan, Options, CGPath, CGSize (+9 more)

### Community 50 - "RasterLayerTexture"
Cohesion: 0.15
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 51 - "StrokeGeometry"
Cohesion: 0.15
Nodes (9): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, .dragHandle (+1 more)

### Community 52 - "FloatingPieceOverlayView"
Cohesion: 0.12
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 53 - "MaskSource"
Cohesion: 0.15
Nodes (12): MaskSource, folder, .id, layer, Encoder, UUID, Bool, CanvasManager (+4 more)

### Community 54 - "BackupManagerLogicTests"
Cohesion: 0.18
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 55 - "SaveSnapshot"
Cohesion: 0.15
Nodes (19): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+11 more)

### Community 56 - "PerfMonitor"
Cohesion: 0.09
Nodes (22): CADisplayLink, CFTimeInterval, ObservableObject, .body, MoveTransformBottomBar, .body, .divider, CanvasManager (+14 more)

### Community 57 - "FillParams"
Cohesion: 0.18
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 58 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 59 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

### Community 60 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 61 - "RenderTreeCharacterizationTests"
Cohesion: 0.20
Nodes (4): String, RenderTreeCharacterizationTests, CanvasManager, String

### Community 62 - ".makeUIView"
Cohesion: 0.10
Nodes (10): CanvasView, Context, Coordinator, LayerTransform, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView (+2 more)

### Community 63 - "DrawingView"
Cohesion: 0.09
Nodes (22): Alignment, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String (+14 more)

### Community 64 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 65 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-feature, worker-integration, worker-test, worker-ui, model, description (+17 more)

### Community 66 - ".stampStroke"
Cohesion: 0.16
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 67 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 68 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 69 - "Composite.metal"
Cohesion: 0.28
Nodes (24): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+16 more)

### Community 70 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 72 - "LatticeEmbedding"
Cohesion: 0.16
Nodes (11): DeformedCellIndex, Hit, .triangles, LatticeEmbedding, .count, .isEmpty, LatticeExpansion, .didExpand (+3 more)

### Community 73 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 74 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 75 - "SwiftUI"
Cohesion: 0.11
Nodes (9): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+1 more)

### Community 76 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 77 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 78 - "CodingKeys"
Cohesion: 0.09
Nodes (22): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes (+14 more)

### Community 79 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 80 - "Codable"
Cohesion: 0.33
Nodes (16): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool (+8 more)

### Community 82 - "OnionSkinLogicTests"
Cohesion: 0.14
Nodes (11): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+3 more)

### Community 83 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 84 - "Equatable"
Cohesion: 0.19
Nodes (11): Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+3 more)

### Community 85 - "Coordinator"
Cohesion: 0.16
Nodes (12): NSObject, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UIView (+4 more)

### Community 86 - ".withInterpolationUndo"
Cohesion: 0.14
Nodes (11): Layer, String, Void, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 87 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 88 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 89 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+11 more)

### Community 90 - "You are the Orchestrator for the rest of the layer-compositing project"
Cohesion: 0.11
Nodes (17): At each phase boundary, Deliberately cut, with the answer worked out, Gotchas that each cost a cycle — put these in every worker prompt, Measurement lessons that cost real time, Phase 8 — the survey is done, do not redo it, Read this first, Start here, because the tree may not be where you would guess, What 6a/7/6b established that you should not re-litigate (+9 more)

### Community 91 - "ShapeDetector"
Cohesion: 0.21
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 92 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 93 - "GalleryView"
Cohesion: 0.14
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 94 - "StructureSnapshot"
Cohesion: 0.18
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 95 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 96 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 97 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 98 - "VectorEraserMode"
Cohesion: 0.12
Nodes (16): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+8 more)

### Community 99 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 100 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 101 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 102 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (12): .visibleGuideStrokes, InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences (+4 more)

### Community 103 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 104 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 105 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 106 - "Layer"
Cohesion: 0.14
Nodes (12): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID (+4 more)

### Community 107 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 108 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 109 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 110 - ".testManySmallStrokesAllStayUndoableWithinTheBudget"
Cohesion: 0.27
Nodes (4): Bool, CanvasManager, Int, UIImage

### Community 111 - "ViewPreset"
Cohesion: 0.23
Nodes (7): CanvasManager, Int, String, Bool, String, UUID, ViewPreset

### Community 112 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 113 - "LayerRowModel"
Cohesion: 0.18
Nodes (10): IndexPath, LayerRowModel, .folderID, .maskSource, BlendMode, Bool, Double, String (+2 more)

### Community 114 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 115 - "LayerStackListView.Coordinator"
Cohesion: 0.23
Nodes (7): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 116 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 117 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 118 - "compositeOver"
Cohesion: 0.31
Nodes (11): blendOver(), compositeFill(), compositeMask(), compositeOver(), constant, float4, kernel, uint (+3 more)

### Community 119 - "CanvasManager"
Cohesion: 0.22
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 120 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 121 - ".attach"
Cohesion: 0.29
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 122 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 124 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 125 - ".handleTransformGesture"
Cohesion: 0.31
Nodes (3): CGSize, Void, Recognizer

### Community 126 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 127 - "Known Issues"
Cohesion: 0.25
Nodes (8): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22), The test target does not compile under `-configuration Release` (2026-08-14)

### Community 128 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 129 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 130 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 131 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 132 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 134 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 135 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 136 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 137 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 138 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 139 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 140 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 141 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 142 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 143 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 144 - "Direction"
Cohesion: 0.50
Nodes (4): Direction, backward, forward, fromRest

### Community 145 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 149 - "Kind"
Cohesion: 0.67
Nodes (3): Kind, folder, layer

### Community 150 - "SandwichPresentation"
Cohesion: 0.67
Nodes (3): SandwichPresentation, disengaged, midStroke

## Knowledge Gaps
- **561 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+556 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `Coordinator`, `VectorCanvas`, `CanvasManager`, `Lattice`, `CanvasManager`, `Kind`, `ShapeGeometry`, `CompositorParityLogicTests`, `MaskParityLogicTests`, `UIKit`, `ParityScenario`, `StrokeCanvasView`, `Coordinator`, `AnimationTimeline`, `CanvasManager`, `VectorEraserLogicTests`, `PointCloudIndex`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `BrushEngineLogicTests`, `ARAPLogicTests`, `Identifiable`, `.rasterize`, `VectorEraserHybridLogicTests`, `SandwichLogicTests`, `InterpolationRenderLogicTests`, `String`, `BlendMode`, `PerfBaselineTests`, `CGPoint`, `.coverage`, `InterpolationRecipe`, `GuideOverlayView`, `InterpolationModelLogicTests`, `StrokeSettingsPanel`, `DeformFactorization`, `InterpolationEvaluator`, `RasterLayerTexture`, `StrokeGeometry`, `FloatingPieceOverlayView`, `.load`, `DrawingView`, `LayerStackCell`, `.stampStroke`, `.group`, `StrokeSpatialIndex`, `InterpolationGuideLogicTests`, `LatticeEmbedding`, `CanvasManager`, `.indices`, `OnionSkinLogicTests`, `Coordinator`, `.manager`, `ShapeDetector`, `Color`, `InterpolateBar`, `.arched`, `TimedSample`, `VectorEraserMode`, `DabTarget`, `SideToolbar`, `GuidePath`, `SpacingChart`, `.testManySmallStrokesAllStayUndoableWithinTheBudget`, `TransformOverlaySupport.swift`, `LayerRowModel`, `StrokeStabilizer`, `CanvasManager`, `ActionsMenu`, `.setCanvasPadding`, `.handleTransformGesture`?**
  _High betweenness centrality (0.343) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `Coordinator`, `VectorCanvas`, `CanvasManager`, `Lattice`, `CanvasManager`, `ShapeGeometry`, `MaskParityLogicTests`, `CGFloat`, `UIKit`, `ColorPickerPanel`, `ParityScenario`, `StrokeCanvasView`, `Coordinator`, `AnimationTimeline`, `CanvasManager`, `VectorEraserLogicTests`, `PointCloudIndex`, `CanvasManager`, `StrokeGeometryLogicTests`, `layers`, `ShapeOverlayView`, `BrushEngineLogicTests`, `ARAPLogicTests`, `Identifiable`, `.rasterize`, `VectorEraserHybridLogicTests`, `InterpolationRenderLogicTests`, `BlendMode`, `PerfBaselineTests`, `InterpolationRecipe`, `GuideOverlayView`, `DeformFactorization`, `InterpolationEvaluator`, `RasterLayerTexture`, `StrokeGeometry`, `FloatingPieceOverlayView`, `.load`, `.makeUIView`, `.stampStroke`, `.group`, `StrokeSpatialIndex`, `InterpolationGuideLogicTests`, `LatticeEmbedding`, `.indices`, `SelectionOverlayView`, `.manager`, `ShapeDetector`, `.arched`, `TimedSample`, `DabTarget`, `ObjectTransformOverlayView`, `GuidePath`, `.testManySmallStrokesAllStayUndoableWithinTheBudget`, `TransformOverlaySupport.swift`, `StrokeStabilizer`, `LayerStackListView.Coordinator`, `CanvasManager`, `.clearRasterizeCache`, `.setCanvasPadding`, `.handleTransformGesture`?**
  _High betweenness centrality (0.193) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ShapeGeometry`, `.encode`, `CGFloat`, `CanvasManager`, `CanvasManager`, `layers`, `InterpolationRecipe`, `RasterLayerTexture`, `MaskSource`, `PerfMonitor`, `SwiftUI`, `Equatable`, `.withInterpolationUndo`, `StructureSnapshot`, `TimedSample`, `VectorEraserMode`, `UndoHistory`, `Layer`, `SpacingChart`, `ViewPreset`, `.setCanvasPadding`?**
  _High betweenness centrality (0.093) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._