# Graph Report - PaintApp-menuinterrupt  (2026-08-20)

## Corpus Check
- 214 files · ~645,824 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6262 nodes · 18952 edges · 192 communities (180 shown, 12 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1924 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `23bba50e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- CGPoint
- CanvasManager
- .manager
- ProjectBackupManager
- CanvasManager
- VectorCanvas
- Lattice
- Coordinator
- ParityScenario
- CompositorParityLogicTests
- AlphaMask
- InterpolationGuideLogicTests
- HistoryActionLabel
- Coordinator
- CGFloat
- EffectLayerLogicTests
- ColorPickerPanel
- CodingKeys
- Effect
- SandwichLogicTests
- PerfBaselineTests
- LayerTreeCharacterizationTests
- .drawLine
- StrokeGeometryLogicTests
- StrokeCanvasView
- MaskSource
- ShapeOverlayView
- PointCloudIndex
- PaintUITestCase
- CompositorMetalEngine
- AnimationTimeline
- UIKit
- String
- .transparentFormat
- EffectMultiPassLogicTests
- .apply
- CaseIterable
- ValueLayerLogicTests
- RasterLayerTexture
- CanvasManager
- SelectionOverlayView
- CodingKey
- VectorEraserLogicTests
- .launchIntoEditor
- CanvasManager
- ProjectSaveLogicTests
- XCTestCase
- View
- CanvasManager
- ARAPLogicTests
- StrokeGestureRecognizer
- SaveSnapshot
- VectorEraserHybridLogicTests
- layers
- RenderNode
- .rows
- VectorCanvasDataLogicTests
- RenderQuality
- InterpolationRenderLogicTests
- Codable
- Tool
- InterpolationRecipe
- agent
- ActionRecorder
- EyedropperLogicTests
- PlaybackBoundsCharacterizationTests
- Binding
- Composite.metal
- SwiftUI
- GuideOverlayView
- SpacingChart
- LassoFillLogicTests
- BackupManagerLogicTests
- .evaluate
- Brush
- BlendMode
- LayerStackCell
- EffectParityLogicTests
- VectorSample
- Known Issues
- FloatingPieceOverlayView
- MetalFillSession
- RenderRequest
- DrawingView
- Foundation
- CodingKeys
- WindowEventTap
- LayerStackListView.Coordinator
- CanvasNotice
- ContentView
- .group
- ActivePanel
- StrokeSpatialIndex
- .coverage
- OnionSkinSettings
- XCUIApplication
- .image
- OnionSkinPanel
- Fill.metal
- .sample
- Compositor.swift
- PinchMergeGateLogicTests
- GuideRow
- OnionSkinLogicTests
- OnionSkinSource.swift
- Gesture
- Layer Compositing
- read
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- .compositeSize
- ViewPreset
- StructureSnapshot
- ShapeHoldClock
- .reconcileLayers
- SelectPanel
- Coordinator
- CanvasTransformFreezeUITests
- .rasterize
- EffectParams
- BrushSettingsPanel
- SandwichCompositingUITests
- BlockDragCharacterizationTests
- InterpolationEngineDiagnosticsLogicTests
- 1. The decisions
- PerfMonitor
- .setUpGestures
- MotionGroup
- .ifRecording
- InterpolateBar
- FillBoundaryLogicTests
- PaintSoftware - iPad Drawing and Animation App
- CanvasPresentation
- Kind
- LayerRowModel
- Recording
- Layer
- TransformOverlaySupport.swift
- CanvasSizePickerView
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- .attach
- bash
- ActionsMenu
- ObjectTransformOverlayView
- CGContextDabTarget
- Kind
- LayerContentVersion
- UndoHistory
- CanvasHostView
- Performance
- CanvasPresentationLogicTests
- CLAUDE.md
- Kind
- CodingKeys
- GalleryView
- MenuInterruptionUITests
- 4. Future upgrades — the deferred list
- Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit)
- ToolPanelsUITests
- .sampledColor
- Every dismissible presentation, and whether a stroke under it breaks
- Multi-Session Protocol
- Edge
- Lasso Fill — Specification
- .row
- Attempt
- SandwichPresentation
- command
- JSONValue
- RecordingWriter
- ProjectStore.swift
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- CutOutcome
- parallel_test.sh
- Performance baseline
- TODO
- ManifestSkeleton
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- Corner
- .waitForDisappearance
- presentation-census.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 629 edges
2. `CGFloat` - 489 edges
3. `CanvasManager` - 151 edges
4. `Effect` - 149 edges
5. `VectorCanvas` - 125 edges
6. `layers` - 119 edges
7. `VectorSample` - 117 edges
8. `ShapeGeometry` - 109 edges
9. `Coordinator` - 108 edges
10. `CanvasManager` - 100 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift

## Import Cycles
- None detected.

## Communities (192 total, 12 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - "CGPoint"
Cohesion: 0.06
Nodes (24): CGPoint, .length, FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained (+16 more)

### Community 2 - "CanvasManager"
Cohesion: 0.05
Nodes (47): CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary (+39 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (8): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 4 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 5 - "CanvasManager"
Cohesion: 0.04
Nodes (46): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+38 more)

### Community 6 - "VectorCanvas"
Cohesion: 0.05
Nodes (52): UUID, CodableColor, .uiColor, image, kind, DabLattice, .range, Kind (+44 more)

### Community 7 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 8 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 9 - "ParityScenario"
Cohesion: 0.10
Nodes (28): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+20 more)

### Community 10 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (16): CanvasFixture, CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager (+8 more)

### Community 11 - "AlphaMask"
Cohesion: 0.09
Nodes (12): AlphaMask, .isActive, Bool, Decoder, Int, MaskParityLogicTests, .side, Bool (+4 more)

### Community 12 - "InterpolationGuideLogicTests"
Cohesion: 0.07
Nodes (10): GuideHandles, TimeInterval, TimedSample, .point, InterpolationGuideLogicTests, CanvasManager, Cel, TimeInterval (+2 more)

### Community 13 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (72): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+64 more)

### Community 14 - "Coordinator"
Cohesion: 0.08
Nodes (22): Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, InterpolationPreviewKey, OnionSkinKey, SandwichKey, Bool (+14 more)

### Community 15 - "CGFloat"
Cohesion: 0.05
Nodes (31): Accelerate, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Sample (+23 more)

### Community 16 - "EffectLayerLogicTests"
Cohesion: 0.11
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 17 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+29 more)

### Community 18 - "CodingKeys"
Cohesion: 0.05
Nodes (46): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+38 more)

### Community 19 - "Effect"
Cohesion: 0.10
Nodes (40): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, Curves, Effect, .displayName (+32 more)

### Community 20 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 21 - "PerfBaselineTests"
Cohesion: 0.06
Nodes (31): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Bool, CGBlendMode, ClosedRange, Double (+23 more)

### Community 22 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 23 - ".drawLine"
Cohesion: 0.10
Nodes (11): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+3 more)

### Community 24 - "StrokeGeometryLogicTests"
Cohesion: 0.05
Nodes (15): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, samples (+7 more)

### Community 25 - "StrokeCanvasView"
Cohesion: 0.06
Nodes (34): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, StrokeStabilizer, .stabilization, Double (+26 more)

### Community 26 - "MaskSource"
Cohesion: 0.11
Nodes (14): MaskSource, folder, .id, layer, Encoder, UUID, Bool, LayerTransform (+6 more)

### Community 27 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 28 - "PointCloudIndex"
Cohesion: 0.15
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 29 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests (+3 more)

### Community 30 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 31 - "AnimationTimeline"
Cohesion: 0.04
Nodes (50): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+42 more)

### Community 32 - "UIKit"
Cohesion: 0.07
Nodes (6): CoreGraphics, Darwin, ThumbnailRenderer, simd, UIKit, XCTest

### Community 33 - "String"
Cohesion: 0.06
Nodes (45): Error, CodingKeys, brush, color, composite, elements, fill, fills (+37 more)

### Community 34 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+12 more)

### Community 35 - "EffectMultiPassLogicTests"
Cohesion: 0.11
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 36 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 37 - "CaseIterable"
Cohesion: 0.09
Nodes (22): CaseIterable, Kind, line, oval, rectangle, Neighbourhood, drawings, frames (+14 more)

### Community 38 - "ValueLayerLogicTests"
Cohesion: 0.15
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 39 - "RasterLayerTexture"
Cohesion: 0.08
Nodes (24): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+16 more)

### Community 40 - "CanvasManager"
Cohesion: 0.08
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 41 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 42 - "CodingKey"
Cohesion: 0.05
Nodes (41): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+33 more)

### Community 43 - "VectorEraserLogicTests"
Cohesion: 0.08
Nodes (11): Sweep, Bool, CGRect, Double, VectorEraser, ClosedRange, StaticString, UInt (+3 more)

### Community 44 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 45 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 46 - "ProjectSaveLogicTests"
Cohesion: 0.12
Nodes (12): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase, Set, StaticString (+4 more)

### Community 47 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 48 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 49 - "CanvasManager"
Cohesion: 0.06
Nodes (29): CanvasManager, .fillHalfCoverageAlpha, FillKey, Bool, Cel, CGPath, Float, Int (+21 more)

### Community 50 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (14): ARAPInterpolation, Interpolator, Options, Bool, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 51 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 52 - "SaveSnapshot"
Cohesion: 0.12
Nodes (22): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+14 more)

### Community 53 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 54 - "layers"
Cohesion: 0.10
Nodes (19): .activeLayerIsVector, CanvasManager, Bool, CGSize, UIImage, CanvasManager, Bool, Int (+11 more)

### Community 55 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 56 - ".rows"
Cohesion: 0.11
Nodes (27): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+19 more)

### Community 57 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 58 - "RenderQuality"
Cohesion: 0.12
Nodes (21): CanvasManager, LayerRenderSource, RenderBackground, RenderResolution, full, half, .id, .scale (+13 more)

### Community 59 - "InterpolationRenderLogicTests"
Cohesion: 0.18
Nodes (9): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID (+1 more)

### Community 60 - "Codable"
Cohesion: 0.10
Nodes (28): Codable, Kind, folder, layer, Decoder, Int, ValueFill, CompositorRole (+20 more)

### Community 61 - "Tool"
Cohesion: 0.08
Nodes (17): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+9 more)

### Community 62 - "InterpolationRecipe"
Cohesion: 0.05
Nodes (36): GuideSet, .isEmpty, Bool, LocalEditPlan, Int, GuideRole, both, timing (+28 more)

### Community 63 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 64 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 65 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 66 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "Binding"
Cohesion: 0.09
Nodes (28): Accessory, KeyPath, .isTimelineMenuPresented, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview (+20 more)

### Community 68 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 69 - "SwiftUI"
Cohesion: 0.13
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 70 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): points, Editing, handles, none, spacing, Grip, Guide, GuideOverlayView (+9 more)

### Community 71 - "SpacingChart"
Cohesion: 0.12
Nodes (9): GuidePath, .end, .start, SpacingChart, .curve, .draggable, CGVector, Int (+1 more)

### Community 72 - "LassoFillLogicTests"
Cohesion: 0.09
Nodes (16): LassoFillMask, Float, Int, SIMD4, UInt8, mask, LassoFillLogicTests, .loopAroundEverything (+8 more)

### Community 73 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 74 - ".evaluate"
Cohesion: 0.12
Nodes (20): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+12 more)

### Community 75 - "Brush"
Cohesion: 0.06
Nodes (33): Identifiable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+25 more)

### Community 76 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 77 - "LayerStackCell"
Cohesion: 0.10
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 78 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 79 - "VectorSample"
Cohesion: 0.19
Nodes (5): VectorSample, CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 80 - "Known Issues"
Cohesion: 0.07
Nodes (29): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16) (+21 more)

### Community 81 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 82 - "MetalFillSession"
Cohesion: 0.09
Nodes (29): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+21 more)

### Community 83 - "RenderRequest"
Cohesion: 0.32
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, RenderRequest, UIGraphicsImageRendererContext

### Community 84 - "DrawingView"
Cohesion: 0.08
Nodes (21): Alignment, ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void (+13 more)

### Community 85 - "Foundation"
Cohesion: 0.12
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 86 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+19 more)

### Community 87 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 88 - "LayerStackListView.Coordinator"
Cohesion: 0.12
Nodes (14): DispatchWorkItem, DropTarget, between, onto, LayerStackListView.Coordinator, Bool, CGRect, ObjectIdentifier (+6 more)

### Community 89 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 90 - "ContentView"
Cohesion: 0.09
Nodes (17): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+9 more)

### Community 91 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 92 - "ActivePanel"
Cohesion: 0.12
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 93 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 94 - ".coverage"
Cohesion: 0.16
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 95 - "OnionSkinSettings"
Cohesion: 0.16
Nodes (10): .opacitySliders, Int, OnionSkinSettings, Side, .id, next, .step, CodableColor (+2 more)

### Community 96 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 97 - ".image"
Cohesion: 0.14
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 98 - "OnionSkinPanel"
Cohesion: 0.12
Nodes (20): CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow, .neighbourhoodPicker (+12 more)

### Community 99 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 100 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 101 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 102 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 103 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 104 - "OnionSkinLogicTests"
Cohesion: 0.17
Nodes (6): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests, VectorStroke

### Community 105 - "OnionSkinSource.swift"
Cohesion: 0.13
Nodes (12): Colouring, .id, originalColors, tinted, .title, OnionSkinSettingsSource, OnionSkinSource, Bool (+4 more)

### Community 106 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 107 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 108 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 109 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 110 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 111 - "CurveEditor"
Cohesion: 0.25
Nodes (8): CurveEditor, .body, .dragGesture, .grid, .handles, .identityLine, Gesture, Int

### Community 112 - ".compositeSize"
Cohesion: 0.17
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 113 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 114 - "StructureSnapshot"
Cohesion: 0.27
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 115 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 116 - ".reconcileLayers"
Cohesion: 0.07
Nodes (15): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, AppliedTool, CanvasView (+7 more)

### Community 117 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 118 - "Coordinator"
Cohesion: 0.20
Nodes (11): .body, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID (+3 more)

### Community 119 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 121 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 122 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 123 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 124 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 125 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 126 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 127 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 128 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 129 - "MotionGroup"
Cohesion: 0.29
Nodes (8): GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder, UUID

### Community 130 - ".ifRecording"
Cohesion: 0.25
Nodes (7): Void, .currentFrame, .currentLayerIndex, .floatingPiece, .pencilOnlyDrawing, .renderResolution, .selectedTool

### Community 131 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 132 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 133 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 134 - "CanvasPresentation"
Cohesion: 0.09
Nodes (20): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+12 more)

### Community 135 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 136 - "LayerRowModel"
Cohesion: 0.15
Nodes (13): UIColor, Kind, compositorNode, group, layer, LayerRowModel, .folderID, .isFolder (+5 more)

### Community 137 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 138 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 139 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 140 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 141 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 142 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 143 - ".attach"
Cohesion: 0.17
Nodes (7): IndexPath, Context, UIPinchGestureRecognizer, .gradientStops, previous, UISwipeActionsConfiguration, UITableView

### Community 144 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 145 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 146 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 147 - "CGContextDabTarget"
Cohesion: 0.23
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 148 - "Kind"
Cohesion: 0.14
Nodes (14): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+6 more)

### Community 149 - "LayerContentVersion"
Cohesion: 0.33
Nodes (5): Hasher, LayerContentVersion, Cel, ObjectIdentifier, UUID

### Community 150 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 151 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 152 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 153 - "CanvasPresentationLogicTests"
Cohesion: 0.17
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 155 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 156 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 157 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 158 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 159 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 160 - "Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit)"
Cohesion: 0.18
Nodes (11): Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit), Machine state, Pace — this is a standing instruction now, not a suggestion, The four branches, in the order they are worth picking up, `tmp/crosseraser` — diagnosis ran, nothing is settled, `tmp/fillborder` — the only one that is clean, and closest to done, `tmp/lasso` — real progress, then stopped mid-edit, `tmp/menuinterrupt` — the largest finding of the pass, and the mechanism half-built (+3 more)

### Community 162 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 163 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.20
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 164 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 165 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 166 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 167 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 168 - "Attempt"
Cohesion: 0.50
Nodes (4): Attempt, image, unavailable, underPressure

### Community 169 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 170 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 171 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 175 - "ProjectStore.swift"
Cohesion: 0.38
Nodes (6): os, CodableColor, .color, Color, .codable, CodableColor

### Community 177 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 178 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 180 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 181 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 182 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 184 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 185 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 195 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 196 - ".waitForDisappearance"
Cohesion: 0.40
Nodes (3): Bool, TimeInterval, XCUIElement

## Knowledge Gaps
- **924 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+919 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `CGPoint`, `CanvasManager`, `CanvasManager`, `VectorCanvas`, `Lattice`, `Coordinator`, `ParityScenario`, `CompositorParityLogicTests`, `AlphaMask`, `InterpolationGuideLogicTests`, `Coordinator`, `EffectLayerLogicTests`, `SandwichLogicTests`, `PerfBaselineTests`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `ShapeOverlayView`, `PointCloudIndex`, `PaintUITestCase`, `AnimationTimeline`, `String`, `.transparentFormat`, `.apply`, `CaseIterable`, `RasterLayerTexture`, `CanvasManager`, `VectorEraserLogicTests`, `.launchIntoEditor`, `ProjectSaveLogicTests`, `CanvasManager`, `ARAPLogicTests`, `VectorEraserHybridLogicTests`, `layers`, `.rows`, `VectorCanvasDataLogicTests`, `RenderQuality`, `InterpolationRenderLogicTests`, `InterpolationRecipe`, `ActionRecorder`, `Binding`, `GuideOverlayView`, `SpacingChart`, `LassoFillLogicTests`, `.evaluate`, `Brush`, `LayerStackCell`, `VectorSample`, `FloatingPieceOverlayView`, `RenderRequest`, `DrawingView`, `WindowEventTap`, `.group`, `StrokeSpatialIndex`, `XCUIApplication`, `.image`, `.sample`, `PinchMergeGateLogicTests`, `OnionSkinLogicTests`, `OnionSkinSource.swift`, `CanvasManager`, `CurveEditor`, `.compositeSize`, `.reconcileLayers`, `Coordinator`, `CanvasTransformFreezeUITests`, `SandwichCompositingUITests`, `InterpolationEngineDiagnosticsLogicTests`, `InterpolateBar`, `LayerRowModel`, `TransformOverlaySupport.swift`, `SideToolbar`, `.attach`, `ActionsMenu`, `CGContextDabTarget`, `Kind`, `JSONValue`?**
  _High betweenness centrality (0.246) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `.setUpGestures`, `cels`, `CanvasManager`, `VectorCanvas`, `Lattice`, `Coordinator`, `ParityScenario`, `CompositorParityLogicTests`, `TransformOverlaySupport.swift`, `InterpolationGuideLogicTests`, `AlphaMask`, `Coordinator`, `CGFloat`, `ColorPickerPanel`, `ObjectTransformOverlayView`, `CGContextDabTarget`, `PerfBaselineTests`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `MaskSource`, `ShapeOverlayView`, `PointCloudIndex`, `AnimationTimeline`, `.sampledColor`, `.transparentFormat`, `RasterLayerTexture`, `CanvasManager`, `SelectionOverlayView`, `VectorEraserLogicTests`, `ProjectSaveLogicTests`, `CanvasManager`, `ARAPLogicTests`, `VectorEraserHybridLogicTests`, `layers`, `InterpolationRenderLogicTests`, `InterpolationRecipe`, `EyedropperLogicTests`, `GuideOverlayView`, `SpacingChart`, `LassoFillLogicTests`, `.evaluate`, `VectorSample`, `FloatingPieceOverlayView`, `WindowEventTap`, `LayerStackListView.Coordinator`, `.group`, `StrokeSpatialIndex`, `.sample`, `CurveEditor`, `.reconcileLayers`, `.rasterize`, `InterpolationEngineDiagnosticsLogicTests`?**
  _High betweenness centrality (0.176) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `CGPoint`, `.manager`, `FillBoundaryLogicTests`, `Lattice`, `ParityScenario`, `CompositorParityLogicTests`, `AlphaMask`, `InterpolationGuideLogicTests`, `EffectLayerLogicTests`, `SandwichLogicTests`, `PerfBaselineTests`, `LayerTreeCharacterizationTests`, `StrokeGeometryLogicTests`, `CanvasPresentationLogicTests`, `PaintUITestCase`, `UIKit`, `EffectMultiPassLogicTests`, `ValueLayerLogicTests`, `RasterLayerTexture`, `SelectionOverlayView`, `VectorEraserLogicTests`, `ProjectSaveLogicTests`, `ARAPLogicTests`, `StrokeGestureRecognizer`, `VectorEraserHybridLogicTests`, `VectorCanvasDataLogicTests`, `InterpolationRenderLogicTests`, `Tool`, `InterpolationRecipe`, `EyedropperLogicTests`, `PlaybackBoundsCharacterizationTests`, `LassoFillLogicTests`, `BackupManagerLogicTests`, `EffectParityLogicTests`, `VectorSample`, `CanvasNotice`, `PinchMergeGateLogicTests`, `OnionSkinLogicTests`, `MaskGuardLogicTests`, `ShapeHoldClock`, `BlockDragCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Are the 71 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 71 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 13 INFERRED edges - model-reasoned connections that need verification._