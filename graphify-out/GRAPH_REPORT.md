# Graph Report - PaintApp-lasso  (2026-08-18)

## Corpus Check
- 206 files · ~618,502 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6094 nodes · 18501 edges · 197 communities (184 shown, 13 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1907 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `58a0a0bc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- CGPoint
- CanvasManager
- VectorCanvas
- .manager
- VectorEraserHybridLogicTests
- CGFloat
- Lattice
- Coordinator
- LassoFillLogicTests
- CompositorParityLogicTests
- StrokeGeometryLogicTests
- AlphaMask
- layers
- Coordinator
- HistoryActionLabel
- EffectLayerLogicTests
- CodingKeys
- PointCloudIndex
- CodingKeys
- ColorPickerPanel
- PaintUITestCase
- SandwichLogicTests
- CanvasManager
- AnimationTimeline
- LayerTreeCharacterizationTests
- ProjectBackupManager
- CompositorMetalEngine
- ShapeOverlayView
- StrokeCanvasView
- Effect
- UIKit
- .drawLine
- ProjectSaveLogicTests
- EffectMultiPassLogicTests
- VectorSample
- .apply
- VectorEraserLogicTests
- LayerRowModel
- ValueLayerLogicTests
- .transparentFormat
- .launchIntoEditor
- CanvasManager
- BrushEngineLogicTests
- InterpolationRecipe
- XCTestCase
- View
- Codable
- BrushBlendMode
- StrokeGestureRecognizer
- InterpolationRenderLogicTests
- SaveSnapshot
- .withStructureUndo
- Fill.metal
- Coordinator
- InterpolationModelLogicTests
- PerfBaselineTests
- ARAPLogicTests
- CanvasManager
- .rows
- VectorCanvasDataLogicTests
- Binding
- CanvasNotice
- CanvasManager
- RenderNode
- ActionRecorder
- MotionGroupBinding
- PlaybackBoundsCharacterizationTests
- Composite.metal
- MaskSource
- BackupManagerLogicTests
- GuideOverlayView
- ObjectTransformOverlayView
- StrokeSpatialIndex
- EyedropperLogicTests
- RenderQuality
- BlendMode
- OnionSkinSettings
- Known Issues
- OnionSkinPanel
- SelectionOverlayView
- EffectParityLogicTests
- BrushStamper
- RasterLayerTexture
- OnionSkinSource.swift
- agent
- .group
- ActivePanel
- DrawingView
- ContentView
- GuideStroke
- bash
- TimedSample
- InterpolationGuideLogicTests
- XCUIApplication
- StrokeSampleGateLogicTests
- WindowEventTap
- FloatingPieceOverlayView
- .image
- Compositor.swift
- PinchMergeGateLogicTests
- GuideRow
- .compositeSize
- Gesture
- Layer Compositing
- read
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- .setUpGestures
- OnionSkinLogicTests
- LayerStackListView.Coordinator
- CanvasTransformFreezeUITests
- EffectParams
- ShapeHoldClock
- Kind
- Layer
- .makeUIView
- EraserSettingsPanel
- BlockDragCharacterizationTests
- .manager
- SandwichCompositingUITests
- Recording
- RenderRequest
- .arched
- InterpolationEngineDiagnosticsLogicTests
- 1. The decisions
- DabTarget
- PerfMonitor
- EffectPipelines
- CodingKeys
- StructureSnapshot
- SelectionOverlayLogicTests
- InterpolateBar
- GalleryView
- FillBoundaryLogicTests
- .measuringPeakMemory
- PaintSoftware - iPad Drawing and Animation App
- SwiftUI
- .indices
- CanvasSizePickerView
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- SpacingChart
- InterpolationRefusal
- VectorEraserMode
- ActionsMenu
- Foundation
- .sample
- ViewPreset
- UndoHistory
- CanvasHostView
- Performance
- MotionGroup
- CLAUDE.md
- String
- .textureBudgetBytes
- StrokeStabilizer
- SelectPanel
- 4. Future upgrades — the deferred list
- ToolLogicTests
- CaseIterable
- Handoff — 2026-08-18
- .sampledColor
- Multi-Session Protocol
- Lasso Fill — Specification
- Tool
- .row
- LayerContentVersion
- 6. Alpha masks
- command
- JSONValue
- CodingKeys
- InterpolatePanel
- Resolution
- ManifestSkeleton
- RecordingWriter
- CodingKeys
- VectorScratchRole
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- parallel_test.sh
- Corner
- Neighbourhood
- Performance baseline
- TODO
- Kind
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 615 edges
2. `CGFloat` - 478 edges
3. `Effect` - 149 edges
4. `CanvasManager` - 144 edges
5. `VectorCanvas` - 124 edges
6. `layers` - 119 edges
7. `VectorSample` - 116 edges
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

## Communities (197 total, 13 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - "CGPoint"
Cohesion: 0.05
Nodes (28): CGPoint, .length, Int, Edge, bottom, left, right, top (+20 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (58): Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+50 more)

### Community 3 - "VectorCanvas"
Cohesion: 0.05
Nodes (68): Error, CodableColor, .uiColor, image, kind, DabLattice, .range, DecodeReport (+60 more)

### Community 4 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 5 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (47): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+39 more)

### Community 6 - "CGFloat"
Cohesion: 0.04
Nodes (37): Accelerate, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Void (+29 more)

### Community 7 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 8 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 9 - "LassoFillLogicTests"
Cohesion: 0.07
Nodes (33): MTLBuffer, MTLCommandBuffer, LassoFillMask, CGPath, Float, Int, SIMD4, UInt8 (+25 more)

### Community 10 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 11 - "StrokeGeometryLogicTests"
Cohesion: 0.05
Nodes (15): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, samples (+7 more)

### Community 12 - "AlphaMask"
Cohesion: 0.07
Nodes (18): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8, AlphaMask (+10 more)

### Community 13 - "layers"
Cohesion: 0.07
Nodes (24): CanvasManager, .activeCelIsInBetween, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+16 more)

### Community 14 - "Coordinator"
Cohesion: 0.06
Nodes (33): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, Coordinator, .canvasContentScale (+25 more)

### Community 15 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (72): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+64 more)

### Community 16 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 17 - "CodingKeys"
Cohesion: 0.03
Nodes (62): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+54 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.11
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 19 - "CodingKeys"
Cohesion: 0.05
Nodes (45): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+37 more)

### Community 20 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (36): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+28 more)

### Community 21 - "PaintUITestCase"
Cohesion: 0.08
Nodes (15): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests (+7 more)

### Community 22 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 23 - "CanvasManager"
Cohesion: 0.07
Nodes (33): UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform (+25 more)

### Community 24 - "AnimationTimeline"
Cohesion: 0.05
Nodes (43): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+35 more)

### Community 25 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 26 - "ProjectBackupManager"
Cohesion: 0.10
Nodes (22): DateFormatter, Notification.Name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 27 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (31): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+23 more)

### Community 28 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 29 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (24): StrokeInput, TimeInterval, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+16 more)

### Community 30 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+24 more)

### Community 31 - "UIKit"
Cohesion: 0.08
Nodes (7): CoreGraphics, Darwin, Metal, ThumbnailRenderer, simd, UIKit, XCTest

### Community 32 - ".drawLine"
Cohesion: 0.13
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 33 - "ProjectSaveLogicTests"
Cohesion: 0.12
Nodes (12): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase, Set, StaticString (+4 more)

### Community 34 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 35 - "VectorSample"
Cohesion: 0.12
Nodes (15): Brush, VectorSample, .point, CutOutcome, cut, missed, unchanged, IntersectionDriver (+7 more)

### Community 36 - ".apply"
Cohesion: 0.13
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 37 - "VectorEraserLogicTests"
Cohesion: 0.12
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 38 - "LayerRowModel"
Cohesion: 0.08
Nodes (20): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+12 more)

### Community 39 - "ValueLayerLogicTests"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 40 - ".transparentFormat"
Cohesion: 0.13
Nodes (20): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+12 more)

### Community 41 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 42 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 43 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 44 - "InterpolationRecipe"
Cohesion: 0.11
Nodes (25): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+17 more)

### Community 45 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 46 - "View"
Cohesion: 0.14
Nodes (29): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+21 more)

### Community 47 - "Codable"
Cohesion: 0.13
Nodes (25): Codable, Decoder, ValueFill, CompositorRole, node, Decoder, Encoder, K (+17 more)

### Community 48 - "BrushBlendMode"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 49 - "StrokeGestureRecognizer"
Cohesion: 0.10
Nodes (20): StrokeGestureRecognizer, Any, Bool, Int, Selector, Set, UIEvent, UITouch (+12 more)

### Community 50 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (12): StrokeComposite, erase, paint, fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor (+4 more)

### Community 51 - "SaveSnapshot"
Cohesion: 0.11
Nodes (25): os, CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore (+17 more)

### Community 52 - ".withStructureUndo"
Cohesion: 0.12
Nodes (15): .interpolationTarget, CanvasManager, Bool, Int, Void, Cel, .endFrame, .isCertainlyBlank (+7 more)

### Community 53 - "Fill.metal"
Cohesion: 0.18
Nodes (36): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+28 more)

### Community 54 - "Coordinator"
Cohesion: 0.11
Nodes (17): DispatchWorkItem, IndexPath, Coordinator, LayerStackListView, CanvasManager, Context, Coordinator, Int (+9 more)

### Community 55 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 56 - "PerfBaselineTests"
Cohesion: 0.15
Nodes (8): PerfBaselineTests, Bool, CanvasManager, CGSize, Int, String, UIImage, VectorStroke

### Community 57 - "ARAPLogicTests"
Cohesion: 0.15
Nodes (6): ARAPInterpolation, ARAPLogicTests, Int, StaticString, String, UInt

### Community 58 - "CanvasManager"
Cohesion: 0.11
Nodes (17): CanvasManager, .fillHalfCoverageAlpha, FillKey, Bool, Cel, CGPath, Float, Int (+9 more)

### Community 59 - ".rows"
Cohesion: 0.12
Nodes (26): CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections(), effectMenuSlug() (+18 more)

### Community 60 - "VectorCanvasDataLogicTests"
Cohesion: 0.17
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 61 - "Binding"
Cohesion: 0.09
Nodes (29): Accessory, KeyPath, .isTimelineMenuPresented, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager (+21 more)

### Community 62 - "CanvasNotice"
Cohesion: 0.07
Nodes (18): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, Kind, hiddenLayer (+10 more)

### Community 63 - "CanvasManager"
Cohesion: 0.09
Nodes (15): CanvasManager, Bool, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale (+7 more)

### Community 64 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 65 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 66 - "MotionGroupBinding"
Cohesion: 0.10
Nodes (17): InterpolationMode, generate, reproject, .isWellFormed, InterpolationReference, Kind, easeIn, easeInOut (+9 more)

### Community 67 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 68 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 69 - "MaskSource"
Cohesion: 0.11
Nodes (15): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+7 more)

### Community 70 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 71 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 72 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (22): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, FloatingTransform (+14 more)

### Community 73 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 74 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 75 - "RenderQuality"
Cohesion: 0.12
Nodes (21): CanvasManager, LayerRenderSource, RenderBackground, RenderResolution, full, half, .id, .scale (+13 more)

### Community 76 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 77 - "OnionSkinSettings"
Cohesion: 0.17
Nodes (13): .gradientStops, OnionSkinOpacityRamp, OnionSkinSettings, Side, .id, next, previous, .step (+5 more)

### Community 78 - "Known Issues"
Cohesion: 0.07
Nodes (29): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16) (+21 more)

### Community 79 - "OnionSkinPanel"
Cohesion: 0.10
Nodes (22): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+14 more)

### Community 80 - "SelectionOverlayView"
Cohesion: 0.14
Nodes (15): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, Set, UIColor (+7 more)

### Community 81 - "EffectParityLogicTests"
Cohesion: 0.19
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 82 - "BrushStamper"
Cohesion: 0.15
Nodes (10): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+2 more)

### Community 83 - "RasterLayerTexture"
Cohesion: 0.17
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 84 - "OnionSkinSource.swift"
Cohesion: 0.11
Nodes (13): Colouring, .id, originalColors, tinted, .title, OnionSkinSettingsSource, OnionSkinSource, Bool (+5 more)

### Community 85 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-integration, worker-research, worker-test, worker-ui, model, description (+17 more)

### Community 86 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 87 - "ActivePanel"
Cohesion: 0.12
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 88 - "DrawingView"
Cohesion: 0.09
Nodes (19): Alignment, CanvasNoticeBanner, .body, .icon, String, Void, DrawingView, .body (+11 more)

### Community 89 - "ContentView"
Cohesion: 0.10
Nodes (16): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+8 more)

### Community 90 - "GuideStroke"
Cohesion: 0.15
Nodes (15): Hashable, Identifiable, .guideChips, GuideChip, .id, GuideRole, both, timing (+7 more)

### Community 91 - "bash"
Cohesion: 0.16
Nodes (24): worker-bugfix, worker-feature, gh *, git *, xcodebuild *, permission, bash, edit (+16 more)

### Community 92 - "TimedSample"
Cohesion: 0.13
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 94 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 95 - "StrokeSampleGateLogicTests"
Cohesion: 0.19
Nodes (4): CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 96 - "WindowEventTap"
Cohesion: 0.19
Nodes (9): AnyClass, NSObject, FoundElement, InstallReport, CGRect, UIEvent, WindowEventTap, UIAccessibilityTraits (+1 more)

### Community 97 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 98 - ".image"
Cohesion: 0.15
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 99 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 100 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 101 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 102 - ".compositeSize"
Cohesion: 0.18
Nodes (4): .resolutionNoteText, OnionSkinBudget, CGSize, Int

### Community 103 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 104 - "Layer Compositing"
Cohesion: 0.09
Nodes (22): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+14 more)

### Community 105 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 106 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 107 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 108 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 109 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 110 - "OnionSkinLogicTests"
Cohesion: 0.19
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 111 - "LayerStackListView.Coordinator"
Cohesion: 0.14
Nodes (11): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval, UIGestureRecognizer (+3 more)

### Community 112 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 113 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 114 - "ShapeHoldClock"
Cohesion: 0.19
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 115 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 116 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 117 - ".makeUIView"
Cohesion: 0.14
Nodes (8): AppliedTool, CanvasView, Color, Context, Coordinator, Double, LayerTransform, UIColor

### Community 118 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (16): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+8 more)

### Community 119 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 120 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 121 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 122 - "Recording"
Cohesion: 0.13
Nodes (14): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderIndicator, .body (+6 more)

### Community 123 - "RenderRequest"
Cohesion: 0.30
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, RenderRequest, UIGraphicsImageRendererContext

### Community 124 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 125 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 126 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 127 - "DabTarget"
Cohesion: 0.20
Nodes (10): AnyObject, CGGradient, Key, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode (+2 more)

### Community 128 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 129 - "EffectPipelines"
Cohesion: 0.19
Nodes (12): MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue, MTLComputeCommandEncoder (+4 more)

### Community 130 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, brush, color, composite, elements, fill, fills, id (+10 more)

### Community 131 - "StructureSnapshot"
Cohesion: 0.17
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, guideStrokes

### Community 132 - "SelectionOverlayLogicTests"
Cohesion: 0.16
Nodes (6): resolvedLastTouchType(), UITouch, SelectionOverlayLogicTests, Bool, UITouch, S

### Community 133 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 134 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 135 - "FillBoundaryLogicTests"
Cohesion: 0.32
Nodes (5): FillBoundaryLogicTests, Bool, Float, Int, UInt8

### Community 136 - ".measuringPeakMemory"
Cohesion: 0.22
Nodes (6): Atomic, .value, Double, UInt64, Value, Void

### Community 137 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 138 - "SwiftUI"
Cohesion: 0.17
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 141 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 142 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 143 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 144 - "SpacingChart"
Cohesion: 0.17
Nodes (4): SpacingChart, .curve, .draggable, stops

### Community 145 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (12): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+4 more)

### Community 146 - "VectorEraserMode"
Cohesion: 0.14
Nodes (14): FillMode, .displayName, flood, .id, lasso, Bool, String, VectorEraserMode (+6 more)

### Community 147 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 148 - "Foundation"
Cohesion: 0.14
Nodes (4): Foundation, AppVersion, .versionString, String

### Community 149 - ".sample"
Cohesion: 0.27
Nodes (9): ObjectiveC.runtime, ResolvedTarget, Bool, CGSize, Double, Int, UITouch, TouchSample (+1 more)

### Community 150 - "ViewPreset"
Cohesion: 0.21
Nodes (7): CanvasManager, Int, String, Bool, String, UUID, ViewPreset

### Community 151 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 152 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 153 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 154 - "MotionGroup"
Cohesion: 0.21
Nodes (10): GroupRegistration, Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor (+2 more)

### Community 156 - "String"
Cohesion: 0.32
Nodes (6): Entry, ObjectIdentifier, Set, String, UIGestureRecognizer, UIView

### Community 157 - ".textureBudgetBytes"
Cohesion: 0.32
Nodes (5): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64

### Community 158 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 159 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 160 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 162 - "CaseIterable"
Cohesion: 0.20
Nodes (10): CaseIterable, Kind, line, oval, rectangle, Placement, behind, .id (+2 more)

### Community 163 - "Handoff — 2026-08-18"
Cohesion: 0.20
Nodes (10): Handoff — 2026-08-18, Onion skin: what the device settled, Open: `tmp/lasso` — the live owner bug, Process, this pass, Still queued, The one thing to read first, The oval unification merged after this was first written, The two owner answers that did more than any analysis (+2 more)

### Community 164 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 165 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 166 - "Lasso Fill — Specification"
Cohesion: 0.22
Nodes (9): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+1 more)

### Community 167 - "Tool"
Cohesion: 0.22
Nodes (8): Tool, eraser, eyedropper, fill, .paintsOnCanvas, pen, pencil, text

### Community 168 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 169 - "LayerContentVersion"
Cohesion: 0.29
Nodes (5): Hasher, LayerContentVersion, Cel, ObjectIdentifier, UUID

### Community 170 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 171 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 172 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 173 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 174 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 175 - "Resolution"
Cohesion: 0.29
Nodes (7): Resolution, .fraction, full, half, .id, quarter, .title

### Community 176 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 178 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 179 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 180 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 182 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 183 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 184 - "Neighbourhood"
Cohesion: 0.40
Nodes (5): Neighbourhood, drawings, frames, .id, .title

### Community 185 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 186 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 187 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 188 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **899 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+894 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `CGPoint`, `CanvasManager`, `VectorCanvas`, `VectorEraserHybridLogicTests`, `Lattice`, `Coordinator`, `LassoFillLogicTests`, `CompositorParityLogicTests`, `StrokeGeometryLogicTests`, `AlphaMask`, `layers`, `Coordinator`, `EffectLayerLogicTests`, `PointCloudIndex`, `PaintUITestCase`, `SandwichLogicTests`, `CanvasManager`, `AnimationTimeline`, `ShapeOverlayView`, `StrokeCanvasView`, `ProjectSaveLogicTests`, `VectorSample`, `.apply`, `VectorEraserLogicTests`, `LayerRowModel`, `.transparentFormat`, `.launchIntoEditor`, `BrushEngineLogicTests`, `InterpolationRecipe`, `BrushBlendMode`, `InterpolationRenderLogicTests`, `Coordinator`, `InterpolationModelLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `CanvasManager`, `.rows`, `VectorCanvasDataLogicTests`, `Binding`, `CanvasManager`, `ActionRecorder`, `MotionGroupBinding`, `GuideOverlayView`, `ObjectTransformOverlayView`, `StrokeSpatialIndex`, `RenderQuality`, `BrushStamper`, `RasterLayerTexture`, `OnionSkinSource.swift`, `.group`, `DrawingView`, `TimedSample`, `InterpolationGuideLogicTests`, `XCUIApplication`, `StrokeSampleGateLogicTests`, `WindowEventTap`, `.image`, `PinchMergeGateLogicTests`, `.compositeSize`, `CanvasManager`, `CurveEditor`, `CanvasTransformFreezeUITests`, `.makeUIView`, `EraserSettingsPanel`, `.manager`, `SandwichCompositingUITests`, `RenderRequest`, `.arched`, `InterpolationEngineDiagnosticsLogicTests`, `DabTarget`, `InterpolateBar`, `.measuringPeakMemory`, `.indices`, `.perfManager`, `SideToolbar`, `SpacingChart`, `ActionsMenu`, `.sample`, `StrokeStabilizer`, `JSONValue`, `Resolution`?**
  _High betweenness centrality (0.288) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `CanvasManager`, `VectorCanvas`, `.manager`, `VectorEraserHybridLogicTests`, `CGFloat`, `Lattice`, `Coordinator`, `LassoFillLogicTests`, `CompositorParityLogicTests`, `.indices`, `StrokeGeometryLogicTests`, `layers`, `Coordinator`, `AlphaMask`, `.perfManager`, `PointCloudIndex`, `ColorPickerPanel`, `.sample`, `CanvasManager`, `AnimationTimeline`, `ShapeOverlayView`, `StrokeCanvasView`, `StrokeStabilizer`, `ProjectSaveLogicTests`, `VectorSample`, `.sampledColor`, `VectorEraserLogicTests`, `.transparentFormat`, `BrushEngineLogicTests`, `InterpolationRecipe`, `InterpolationRenderLogicTests`, `.withStructureUndo`, `InterpolationModelLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `CanvasManager`, `CanvasManager`, `GuideOverlayView`, `ObjectTransformOverlayView`, `StrokeSpatialIndex`, `EyedropperLogicTests`, `SelectionOverlayView`, `BrushStamper`, `RasterLayerTexture`, `.group`, `TimedSample`, `InterpolationGuideLogicTests`, `StrokeSampleGateLogicTests`, `WindowEventTap`, `FloatingPieceOverlayView`, `CurveEditor`, `.setUpGestures`, `LayerStackListView.Coordinator`, `.makeUIView`, `.manager`, `.arched`, `InterpolationEngineDiagnosticsLogicTests`, `DabTarget`?**
  _High betweenness centrality (0.139) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `CGPoint`, `.manager`, `VectorEraserHybridLogicTests`, `SelectionOverlayLogicTests`, `FillBoundaryLogicTests`, `Lattice`, `LassoFillLogicTests`, `CompositorParityLogicTests`, `StrokeGeometryLogicTests`, `AlphaMask`, `EffectLayerLogicTests`, `PaintUITestCase`, `SandwichLogicTests`, `LayerTreeCharacterizationTests`, `UIKit`, `ProjectSaveLogicTests`, `EffectMultiPassLogicTests`, `ToolLogicTests`, `VectorEraserLogicTests`, `ValueLayerLogicTests`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `VectorCanvasDataLogicTests`, `CanvasNotice`, `PlaybackBoundsCharacterizationTests`, `BackupManagerLogicTests`, `EyedropperLogicTests`, `EffectParityLogicTests`, `InterpolationGuideLogicTests`, `StrokeSampleGateLogicTests`, `PinchMergeGateLogicTests`, `MaskGuardLogicTests`, `OnionSkinLogicTests`, `ShapeHoldClock`, `BlockDragCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`?**
  _High betweenness centrality (0.100) - this node is a cross-community bridge._
- **Are the 69 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 69 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 13 INFERRED edges - model-reasoned connections that need verification._