# Graph Report - PaintApp-perfa  (2026-08-20)

## Corpus Check
- 228 files · ~681,400 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6676 nodes · 20160 edges · 224 communities (209 shown, 15 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2011 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `43be06b9`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- ShapeGeometry
- CanvasManager
- LassoFillLogicTests
- Lattice
- CGPoint
- .setBakedContent
- layers
- VectorEraserLogicTests
- VectorCanvas
- PointCloudIndex
- CompositorMetalEngine
- HistoryActionLabel
- Coordinator
- AnimationTimeline
- AlphaMask
- SandwichLogicTests
- .setCelLayout
- EffectLayerLogicTests
- PerfBaselineTests
- CodingKeys
- ColorPickerPanel
- CodingKeys
- VectorEraserHybridLogicTests
- LayerTreeCharacterizationTests
- Brush
- StrokeCanvasView
- UIKit
- SelectionOverlayView
- EffectMultiPassLogicTests
- CGFloat
- CanvasManager
- PaintUITestCase
- ShapeOverlayView
- Codable
- ProjectSaveLogicTests
- .transparentFormat
- CanvasManager
- ProjectBackupManager
- .apply
- .reconcileLayers
- .drawLine
- VectorElement
- BrushEngineLogicTests
- TextFrame
- ARAPLogicTests
- XCTestCase
- CanvasManager
- .manager
- .launchIntoEditor
- LayerOptionsPanel
- Fill.metal
- Effect
- SaveSnapshot
- RenderRequest
- RenderTreeCharacterizationTests
- LayerContentVersion
- InterpolationRecipe
- VectorCanvasData
- VectorSample
- .withStructureUndo
- RasterVectorParityLogicTests
- Hashable
- View
- BackupManagerLogicTests
- LayerStackCell
- ObjectTransformOverlayView
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- RenderNode
- TextOverlayView
- ActionRecorder
- InterpolationModelLogicTests
- InterpolationRenderLogicTests
- PlaybackBoundsCharacterizationTests
- RasterLayerTexture
- Typography
- Binding
- StrokeSpatialIndex
- BlendMode
- GuideOverlayView
- EffectParityLogicTests
- DeformFactorization
- EyedropperLogicTests
- MaskSource
- OnionSkinSettings
- agent
- Compositor.swift
- TimelineRowView
- TextBakeCharacterizationTests
- TextLayout
- bash
- GalleryOpenState
- WindowEventTap
- Composite.metal
- DrawingView
- OnionSkinLogicTests
- ContentView
- Known Issues
- CanvasNotice
- OnionSkinPanel
- ActivePanel
- FontResolveLogicTests
- InterpolationGuideLogicTests
- CodingKeys
- Coordinator
- XCUIApplication
- GuideStroke
- .stampStroke
- FloatingPieceOverlayView
- .sample
- read
- PinchMergeGateLogicTests
- Tool
- GuideRow
- .compositeSize
- Gesture
- LayerRowModel
- Layer Compositing
- .image
- .indices
- CanvasManager
- InterpolationRefusal
- CurveEditor
- TextRecipeCodableLogicTests
- SwiftUI
- StrokeGestureRecognizer
- LayerStackListView.Coordinator
- CGRect
- CanvasTransformFreezeUITests
- SandwichCompositingUITests
- EffectParams
- .arched
- StrokeGiveUp
- CodingKeys
- Kind
- Coordinator
- .resolvedCelIndices
- TextSettingsPanel
- BlockDragCharacterizationTests
- FillGestureRestartLogicTests
- .dragOnCanvas
- TimelineLayoutKeyLogicTests
- ShapeHoldClock
- InterpolationEngineDiagnosticsLogicTests
- 1. The decisions
- PerfMonitor
- MaskGuardLogicTests
- SelectionMode
- ViewPreset
- TimedSample
- InterpolateBar
- TouchCountRecognizer
- PaintSoftware - iPad Drawing and Animation App
- Foundation
- CanvasPresentation
- CanvasManager
- VectorEraserMode
- CanvasPresentationLogicTests
- Recording
- CanvasSizePickerView
- EraserSettingsPanel
- SideToolbar
- .manager
- MenuInterruptionUITests
- CaseIterable
- CompositorRole
- ActionsMenu
- CLAUDE.md
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CGContextDabTarget
- Identifiable
- SpacingChart
- UndoHistory
- CanvasHostView
- .relayout
- Performance
- TimelineLayoutKey
- StrokeStabilizer
- StructureSnapshot
- SelectPanel
- 4. Future upgrades — the deferred list
- Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit)
- Lasso Fill — Specification
- Every dismissible presentation, and whether a stroke under it breaks
- .sampledColor
- CanvasPresentationModifier
- .frames
- Multi-Session Protocol
- .textureBudgetBytes
- GuidePath
- CutOutcome
- Kind
- .row
- CodingKeys
- .tableView
- 6. Alpha masks
- JSONValue
- ProjectVersionsView
- Resolution
- ManifestSkeleton
- RecordingWriter
- VectorScratchRole
- Atomic
- Gesture
- parallel_test.sh
- effectChannels
- Performance baseline
- TODO
- Kind
- Colouring
- MenuRequest
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- .init
- presentation-census.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- ThumbnailRenderer.swift

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 662 edges
2. `CGFloat` - 519 edges
3. `CanvasManager` - 157 edges
4. `Effect` - 149 edges
5. `VectorCanvas` - 125 edges
6. `layers` - 121 edges
7. `VectorSample` - 117 edges
8. `Coordinator` - 113 edges
9. `ShapeGeometry` - 109 edges
10. `CanvasManager` - 100 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (224 total, 15 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 1 - "ShapeGeometry"
Cohesion: 0.05
Nodes (30): Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom, left (+22 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (58): Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+50 more)

### Community 3 - "LassoFillLogicTests"
Cohesion: 0.06
Nodes (32): MTLBuffer, MTLCommandBuffer, LassoFillMask, Float, Int, SIMD4, UInt8, FillParams (+24 more)

### Community 4 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 5 - "CGPoint"
Cohesion: 0.06
Nodes (18): CGPoint, .length, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+10 more)

### Community 6 - ".setBakedContent"
Cohesion: 0.07
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 7 - "layers"
Cohesion: 0.06
Nodes (28): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+20 more)

### Community 8 - "VectorEraserLogicTests"
Cohesion: 0.06
Nodes (15): Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser, StaticString, String (+7 more)

### Community 9 - "VectorCanvas"
Cohesion: 0.07
Nodes (35): CodableColor, .uiColor, kind, DabLattice, .range, Bool, CGAffineTransform, CGContext (+27 more)

### Community 10 - "PointCloudIndex"
Cohesion: 0.08
Nodes (22): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+14 more)

### Community 11 - "CompositorMetalEngine"
Cohesion: 0.06
Nodes (44): Metal, MTLLibrary, MTLTextureUsage, Admission, admitted, noHeadroom, overBudget, Attempt (+36 more)

### Community 12 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (73): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+65 more)

### Community 13 - "Coordinator"
Cohesion: 0.07
Nodes (27): CanvasView, Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, OnionSkinKey, CALayer, CanvasManager (+19 more)

### Community 14 - "AnimationTimeline"
Cohesion: 0.04
Nodes (49): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+41 more)

### Community 15 - "AlphaMask"
Cohesion: 0.08
Nodes (13): AlphaMask, .antialiasHalfWidth, .isActive, .threshold, Bool, Float, Int, MaskParityLogicTests (+5 more)

### Community 16 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 17 - ".setCelLayout"
Cohesion: 0.10
Nodes (6): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 18 - "EffectLayerLogicTests"
Cohesion: 0.11
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 19 - "PerfBaselineTests"
Cohesion: 0.12
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 20 - "CodingKeys"
Cohesion: 0.05
Nodes (45): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+37 more)

### Community 21 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (36): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+28 more)

### Community 22 - "CodingKeys"
Cohesion: 0.04
Nodes (57): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+49 more)

### Community 23 - "VectorEraserHybridLogicTests"
Cohesion: 0.11
Nodes (19): UUID, ParityReport, .diagnostic, .isExact, ParityScenario, RasterVectorParity, Bool, Double (+11 more)

### Community 24 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (7): Layer, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 25 - "Brush"
Cohesion: 0.05
Nodes (38): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+30 more)

### Community 26 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (23): CAShapeLayer, StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+15 more)

### Community 27 - "UIKit"
Cohesion: 0.07
Nodes (6): CoreGraphics, CoreText, Darwin, simd, UIKit, XCTest

### Community 28 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 29 - "EffectMultiPassLogicTests"
Cohesion: 0.11
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 30 - "CGFloat"
Cohesion: 0.07
Nodes (18): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Sample, Void (+10 more)

### Community 31 - "CanvasManager"
Cohesion: 0.09
Nodes (20): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+12 more)

### Community 32 - "PaintUITestCase"
Cohesion: 0.08
Nodes (15): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, CGVector, Int, String, XCUIApplication (+7 more)

### Community 33 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 34 - "Codable"
Cohesion: 0.08
Nodes (36): Codable, Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool (+28 more)

### Community 35 - "ProjectSaveLogicTests"
Cohesion: 0.12
Nodes (12): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase, Set, StaticString (+4 more)

### Community 36 - ".transparentFormat"
Cohesion: 0.11
Nodes (23): RenderQuality, full, preview, IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident (+15 more)

### Community 37 - "CanvasManager"
Cohesion: 0.08
Nodes (26): UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform (+18 more)

### Community 38 - "ProjectBackupManager"
Cohesion: 0.12
Nodes (18): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+10 more)

### Community 39 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 40 - ".reconcileLayers"
Cohesion: 0.07
Nodes (18): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, InterpolationPreviewKey, SandwichKey (+10 more)

### Community 41 - ".drawLine"
Cohesion: 0.13
Nodes (8): FillContainmentUITests, FillUndoRedoUITests, Double, TimeInterval, UInt8, EraserAndPersistenceUITests, ShapeRecoveryUITests, VectorLayerContentUITests

### Community 42 - "VectorElement"
Cohesion: 0.10
Nodes (27): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+19 more)

### Community 43 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 44 - "TextFrame"
Cohesion: 0.08
Nodes (31): Int, Alignment, center, .displayName, .id, justified, left, right (+23 more)

### Community 45 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, Int, StaticString (+2 more)

### Community 46 - "XCTestCase"
Cohesion: 0.11
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 47 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 48 - ".manager"
Cohesion: 0.09
Nodes (4): CGSize, Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 49 - ".launchIntoEditor"
Cohesion: 0.15
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, ToolPanelsUITests

### Community 50 - "LayerOptionsPanel"
Cohesion: 0.11
Nodes (30): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+22 more)

### Community 51 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 52 - "Effect"
Cohesion: 0.12
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, Curves, Effect, .displayName (+24 more)

### Community 53 - "SaveSnapshot"
Cohesion: 0.10
Nodes (27): os, CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore (+19 more)

### Community 54 - "RenderRequest"
Cohesion: 0.14
Nodes (16): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, CacheKey, MaskCache (+8 more)

### Community 55 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, String, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 56 - "LayerContentVersion"
Cohesion: 0.10
Nodes (24): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderResolution, full, half (+16 more)

### Community 57 - "InterpolationRecipe"
Cohesion: 0.13
Nodes (18): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, Kind, easeIn, easeInOut (+10 more)

### Community 58 - "VectorCanvasData"
Cohesion: 0.08
Nodes (28): Error, DecodeReport, .droppedCount, .isClean, ElementData, fill, image, stroke (+20 more)

### Community 59 - "VectorSample"
Cohesion: 0.13
Nodes (8): VectorSample, .point, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

### Community 60 - ".withStructureUndo"
Cohesion: 0.12
Nodes (15): .interpolationTarget, CanvasManager, Bool, Int, Void, Cel, .endFrame, .isCertainlyBlank (+7 more)

### Community 61 - "RasterVectorParityLogicTests"
Cohesion: 0.10
Nodes (23): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+15 more)

### Community 62 - "Hashable"
Cohesion: 0.13
Nodes (20): Hashable, FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider (+12 more)

### Community 63 - "View"
Cohesion: 0.12
Nodes (27): stops, View, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+19 more)

### Community 64 - "BackupManagerLogicTests"
Cohesion: 0.15
Nodes (8): Bool, UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 65 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): effectMenuSlug(), LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+4 more)

### Community 66 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (23): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, FloatingTransform (+15 more)

### Community 67 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 68 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 69 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 70 - "TextOverlayView"
Cohesion: 0.10
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 71 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 72 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 73 - "InterpolationRenderLogicTests"
Cohesion: 0.20
Nodes (8): ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID, VectorStroke

### Community 74 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 75 - "RasterLayerTexture"
Cohesion: 0.15
Nodes (12): BrushStamper, RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect (+4 more)

### Community 76 - "Typography"
Cohesion: 0.20
Nodes (7): UIFont, ClosedRange, Typography, Int, String, UIFont, TextLayoutLogicTests

### Community 77 - "Binding"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 78 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 79 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 80 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 81 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 82 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 83 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 84 - "MaskSource"
Cohesion: 0.13
Nodes (13): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Void (+5 more)

### Community 85 - "OnionSkinSettings"
Cohesion: 0.16
Nodes (11): .opacitySliders, OnionSkinOpacityRamp, OnionSkinSettings, Side, .id, next, .step, CodableColor (+3 more)

### Community 86 - "agent"
Cohesion: 0.07
Nodes (28): agent, orchestrator, worker-integration, worker-test, worker-ui, command, deploy, resign (+20 more)

### Community 87 - "Compositor.swift"
Cohesion: 0.13
Nodes (22): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), CompositeProbe, Compositor (+14 more)

### Community 88 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 89 - "TextBakeCharacterizationTests"
Cohesion: 0.22
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 90 - "TextLayout"
Cohesion: 0.12
Nodes (16): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGSize (+8 more)

### Community 91 - "bash"
Cohesion: 0.13
Nodes (28): worker-bugfix, worker-feature, worker-research, gh *, git *, xcodebuild *, permission, bash (+20 more)

### Community 92 - "GalleryOpenState"
Cohesion: 0.14
Nodes (13): GalleryOpenState, .isBusy, Bool, UUID, GalleryTileView, .body, Bool, Void (+5 more)

### Community 93 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 94 - "Composite.metal"
Cohesion: 0.25
Nodes (26): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+18 more)

### Community 95 - "DrawingView"
Cohesion: 0.08
Nodes (20): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DrawingView (+12 more)

### Community 96 - "OnionSkinLogicTests"
Cohesion: 0.14
Nodes (9): tinted, OnionSkinSettingsSource, OnionSkinLogicTests, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 97 - "ContentView"
Cohesion: 0.09
Nodes (16): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+8 more)

### Community 98 - "Known Issues"
Cohesion: 0.08
Nodes (26): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16) (+18 more)

### Community 99 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 100 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 101 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 102 - "FontResolveLogicTests"
Cohesion: 0.18
Nodes (5): FontResolveLogicTests, StubFontProvider, Bool, String, UIFont

### Community 104 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 105 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 106 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 107 - "GuideStroke"
Cohesion: 0.13
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 108 - ".stampStroke"
Cohesion: 0.17
Nodes (10): AnyObject, DabRNG, DiscardedDabTarget, Bool, CGBlendMode, ClosedRange, Double, UIColor (+2 more)

### Community 109 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 110 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 111 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 112 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 113 - "Tool"
Cohesion: 0.10
Nodes (11): String, Tool, eraser, eyedropper, fill, .paintsOnCanvas, pen, pencil (+3 more)

### Community 114 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 115 - ".compositeSize"
Cohesion: 0.20
Nodes (5): .resolutionNoteText, OnionSkinBudget, CGSize, Int, Int

### Community 116 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 117 - "LayerRowModel"
Cohesion: 0.13
Nodes (14): DispatchWorkItem, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, CGRect, Double (+6 more)

### Community 118 - "Layer Compositing"
Cohesion: 0.09
Nodes (22): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+14 more)

### Community 119 - ".image"
Cohesion: 0.15
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 121 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 122 - "InterpolationRefusal"
Cohesion: 0.13
Nodes (15): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+7 more)

### Community 123 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 124 - "TextRecipeCodableLogicTests"
Cohesion: 0.14
Nodes (5): StaticString, String, T, UInt, TextRecipeCodableLogicTests

### Community 125 - "SwiftUI"
Cohesion: 0.13
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 126 - "StrokeGestureRecognizer"
Cohesion: 0.23
Nodes (10): StrokeGestureRecognizer, Any, Bool, Int, Selector, Set, UIEvent, UITouch (+2 more)

### Community 127 - "LayerStackListView.Coordinator"
Cohesion: 0.14
Nodes (11): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval, UIGestureRecognizer (+3 more)

### Community 128 - "CGRect"
Cohesion: 0.21
Nodes (10): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+2 more)

### Community 129 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 130 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 131 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 132 - ".arched"
Cohesion: 0.23
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 133 - "StrokeGiveUp"
Cohesion: 0.14
Nodes (9): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeInterruptionLogicTests, Bool (+1 more)

### Community 134 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 135 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 136 - "Coordinator"
Cohesion: 0.22
Nodes (10): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+2 more)

### Community 137 - ".resolvedCelIndices"
Cohesion: 0.17
Nodes (5): CelSpan, .end, OnionSkinPlanner, OnionSkinSource, Bool

### Community 138 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 139 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 140 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 141 - ".dragOnCanvas"
Cohesion: 0.18
Nodes (5): SelectionPencilOnlyUITests, Bool, XCUIApplication, SelectionAndMoveUITests, GalleryRecoveryUITests

### Community 142 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 143 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 144 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 145 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 146 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 147 - "MaskGuardLogicTests"
Cohesion: 0.18
Nodes (5): MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 148 - "SelectionMode"
Cohesion: 0.14
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 149 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 150 - "TimedSample"
Cohesion: 0.17
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 151 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 152 - "TouchCountRecognizer"
Cohesion: 0.20
Nodes (10): Any, Int, Selector, Set, UIEvent, UITouch, Void, TouchCountRecognizer (+2 more)

### Community 153 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 154 - "Foundation"
Cohesion: 0.12
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 155 - "CanvasPresentation"
Cohesion: 0.12
Nodes (14): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+6 more)

### Community 156 - "CanvasManager"
Cohesion: 0.16
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+2 more)

### Community 157 - "VectorEraserMode"
Cohesion: 0.12
Nodes (16): FillMode, .displayName, flood, .id, lasso, Bool, VectorEraserMode, cutPoints (+8 more)

### Community 158 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 159 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 160 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 161 - "EraserSettingsPanel"
Cohesion: 0.15
Nodes (13): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+5 more)

### Community 162 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 164 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 165 - "CaseIterable"
Cohesion: 0.13
Nodes (15): CaseIterable, Kind, line, oval, rectangle, Neighbourhood, drawings, frames (+7 more)

### Community 166 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 167 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 169 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 170 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 171 - "Identifiable"
Cohesion: 0.20
Nodes (12): Identifiable, .motionGroupChips, MotionGroupChip, .id, GroupInterpolation, auto, clean, crossFade (+4 more)

### Community 172 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, Range

### Community 173 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 174 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 175 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 176 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 177 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 178 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 179 - "StructureSnapshot"
Cohesion: 0.27
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 180 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 181 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 182 - "Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit)"
Cohesion: 0.18
Nodes (11): Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit), Machine state, Pace — this is a standing instruction now, not a suggestion, The four branches, in the order they are worth picking up, `tmp/crosseraser` — diagnosis ran, nothing is settled, `tmp/fillborder` — the only one that is clean, and closest to done, `tmp/lasso` — real progress, then stopped mid-edit, `tmp/menuinterrupt` — the largest finding of the pass, and the mechanism half-built (+3 more)

### Community 183 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 184 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.20
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 185 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 186 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (6): CanvasPresentationModifier, Bool, CanvasManager, Void, PresentedContent, ViewModifier

### Community 187 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 188 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 189 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 190 - "GuidePath"
Cohesion: 0.31
Nodes (4): GuidePath, .end, .start, TimeInterval

### Community 191 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 192 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 193 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 194 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKeys, groups, guideIDs, localEdits, mode, references, spacing, t

### Community 195 - ".tableView"
Cohesion: 0.33
Nodes (4): IndexPath, Context, UISwipeActionsConfiguration, UITableView

### Community 196 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 197 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 198 - "ProjectVersionsView"
Cohesion: 0.38
Nodes (5): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void

### Community 199 - "Resolution"
Cohesion: 0.29
Nodes (7): Resolution, .fraction, full, half, .id, quarter, .title

### Community 200 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 202 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 203 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 204 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 205 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 206 - "effectChannels"
Cohesion: 0.70
Nodes (5): effectChannels(), lutEntry(), uint, noiseValue(), screenValue()

### Community 207 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 208 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 209 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 210 - "Colouring"
Cohesion: 0.50
Nodes (4): Colouring, .id, originalColors, .title

### Community 211 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 212 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **972 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+967 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `ShapeGeometry`, `CanvasManager`, `LassoFillLogicTests`, `Lattice`, `CGPoint`, `.setBakedContent`, `layers`, `VectorEraserLogicTests`, `VectorCanvas`, `PointCloudIndex`, `Coordinator`, `AnimationTimeline`, `SandwichLogicTests`, `EffectLayerLogicTests`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `Brush`, `StrokeCanvasView`, `CanvasManager`, `PaintUITestCase`, `ShapeOverlayView`, `ProjectSaveLogicTests`, `.transparentFormat`, `CanvasManager`, `.apply`, `.reconcileLayers`, `VectorElement`, `BrushEngineLogicTests`, `TextFrame`, `ARAPLogicTests`, `.launchIntoEditor`, `RenderRequest`, `LayerContentVersion`, `InterpolationRecipe`, `VectorSample`, `RasterVectorParityLogicTests`, `Hashable`, `View`, `LayerStackCell`, `ObjectTransformOverlayView`, `VectorCanvasDataLogicTests`, `TextOverlayView`, `ActionRecorder`, `InterpolationModelLogicTests`, `InterpolationRenderLogicTests`, `RasterLayerTexture`, `Typography`, `Binding`, `StrokeSpatialIndex`, `GuideOverlayView`, `DeformFactorization`, `TimelineRowView`, `TextBakeCharacterizationTests`, `TextLayout`, `WindowEventTap`, `DrawingView`, `OnionSkinLogicTests`, `FontResolveLogicTests`, `InterpolationGuideLogicTests`, `Coordinator`, `XCUIApplication`, `.stampStroke`, `.sample`, `PinchMergeGateLogicTests`, `.compositeSize`, `.image`, `.indices`, `CanvasManager`, `CurveEditor`, `CGRect`, `CanvasTransformFreezeUITests`, `SandwichCompositingUITests`, `.arched`, `CodingKeys`, `Coordinator`, `.resolvedCelIndices`, `TextSettingsPanel`, `TimelineLayoutKeyLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `SelectionMode`, `TimedSample`, `InterpolateBar`, `CanvasManager`, `VectorEraserMode`, `EraserSettingsPanel`, `SideToolbar`, `ActionsMenu`, `CGContextDabTarget`, `SpacingChart`, `.relayout`, `TimelineLayoutKey`, `StrokeStabilizer`, `.frames`, `GuidePath`, `.tableView`, `JSONValue`, `Resolution`?**
  _High betweenness centrality (0.281) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `CGRect`, `ShapeGeometry`, `CanvasManager`, `cels`, `Lattice`, `.arched`, `.setBakedContent`, `layers`, `VectorEraserLogicTests`, `VectorCanvas`, `PointCloudIndex`, `LassoFillLogicTests`, `FillGestureRestartLogicTests`, `Coordinator`, `AnimationTimeline`, `AlphaMask`, `InterpolationEngineDiagnosticsLogicTests`, `PerfBaselineTests`, `SelectionMode`, `ColorPickerPanel`, `TimedSample`, `VectorEraserHybridLogicTests`, `StrokeCanvasView`, `Foundation`, `CanvasManager`, `SelectionOverlayView`, `CGFloat`, `CanvasManager`, `ShapeOverlayView`, `.manager`, `.transparentFormat`, `CanvasManager`, `ProjectSaveLogicTests`, `VectorElement`, `CGContextDabTarget`, `BrushEngineLogicTests`, `ARAPLogicTests`, `TextFrame`, `.manager`, `StrokeStabilizer`, `RenderRequest`, `.sampledColor`, `VectorCanvasData`, `VectorSample`, `.withStructureUndo`, `.frames`, `GuidePath`, `InterpolationRecipe`, `RasterVectorParityLogicTests`, `ObjectTransformOverlayView`, `TextOverlayView`, `InterpolationModelLogicTests`, `InterpolationRenderLogicTests`, `RasterLayerTexture`, `Typography`, `Gesture`, `StrokeSpatialIndex`, `GuideOverlayView`, `DeformFactorization`, `EyedropperLogicTests`, `TimelineRowView`, `TextBakeCharacterizationTests`, `TextLayout`, `WindowEventTap`, `InterpolationGuideLogicTests`, `Coordinator`, `.stampStroke`, `FloatingPieceOverlayView`, `.sample`, `Tool`, `.indices`, `CurveEditor`, `TextRecipeCodableLogicTests`, `LayerStackListView.Coordinator`?**
  _High betweenness centrality (0.164) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `ShapeGeometry`, `LassoFillLogicTests`, `Lattice`, `CGPoint`, `.setBakedContent`, `StrokeGiveUp`, `VectorEraserLogicTests`, `BlockDragCharacterizationTests`, `FillGestureRestartLogicTests`, `TimelineLayoutKeyLogicTests`, `AlphaMask`, `InterpolationEngineDiagnosticsLogicTests`, `.setCelLayout`, `EffectLayerLogicTests`, `MaskGuardLogicTests`, `PerfBaselineTests`, `SandwichLogicTests`, `ShapeHoldClock`, `VectorEraserHybridLogicTests`, `LayerTreeCharacterizationTests`, `UIKit`, `SelectionOverlayView`, `EffectMultiPassLogicTests`, `CanvasPresentationLogicTests`, `PaintUITestCase`, `ProjectSaveLogicTests`, `BrushEngineLogicTests`, `ARAPLogicTests`, `.manager`, `RenderTreeCharacterizationTests`, `VectorSample`, `RasterVectorParityLogicTests`, `BackupManagerLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `InterpolationModelLogicTests`, `InterpolationRenderLogicTests`, `PlaybackBoundsCharacterizationTests`, `Typography`, `EffectParityLogicTests`, `EyedropperLogicTests`, `TextBakeCharacterizationTests`, `GalleryOpenState`, `OnionSkinLogicTests`, `CanvasNotice`, `FontResolveLogicTests`, `InterpolationGuideLogicTests`, `PinchMergeGateLogicTests`, `Tool`, `TextRecipeCodableLogicTests`?**
  _High betweenness centrality (0.119) - this node is a cross-community bridge._
- **Are the 76 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 76 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 13 INFERRED edges - model-reasoned connections that need verification._