# Graph Report - PaintApp-brittle  (2026-08-17)

## Corpus Check
- 183 files · ~512,367 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5404 nodes · 16642 edges · 173 communities (164 shown, 9 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1739 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2b9462c1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- CGFloat
- CanvasManager
- Lattice
- ShapeGeometry
- .manager
- CGPoint
- CanvasManager
- VectorCanvas
- Coordinator
- Coordinator
- CompositorParityLogicTests
- String
- AlphaMask
- ARAPLogicTests
- EffectLayerLogicTests
- InterpolationRecipe
- InterpolationGuideLogicTests
- UIKit
- Codable
- PointCloudIndex
- StrokeCanvasView
- ColorPickerPanel
- AnimationTimeline
- SandwichLogicTests
- PerfBaselineTests
- VectorEraserHybridLogicTests
- ProjectBackupManager
- CompositorMetalEngine
- PaintUITestCase
- MetalFillEngine
- EffectMultiPassLogicTests
- .drawLine
- CanvasManager
- .apply
- ShapeOverlayView
- .transparentFormat
- Effect
- BrushStamper
- BrushEngineLogicTests
- View
- TimedSample
- CanvasManager
- ProjectSaveLogicTests
- LayerTreeCharacterizationTests
- .launchIntoEditor
- ValueLayerLogicTests
- DeformFactorization
- RenderQuality
- RenderTreeCharacterizationTests
- RasterVectorParityLogicTests
- LayerStackCell
- InterpolationRenderLogicTests
- .evaluate
- EffectSettingsMenu
- RasterLayerTexture
- RenderNode
- CanvasNotice
- PlaybackBoundsCharacterizationTests
- ActionRecorder
- VectorSample
- BackupManagerLogicTests
- StrokeSettingsPanel
- StrokeSpatialIndex
- layers
- CanvasManager
- BlendMode
- .beginCanvasEdit
- GuideOverlayView
- EffectParityLogicTests
- FillParams
- SaveSnapshot
- InterpolateBar
- StrokeGestureRecognizer
- SwiftUI
- OnionSkinLogicTests
- Composite.metal
- CodingKeys
- ObjectTransformOverlayView
- agent
- bash
- .coverage
- MaskSource
- ActivePanel
- XCUIApplication
- Compositor.swift
- .rows
- FloatingPieceOverlayView
- read
- PinchMergeGateLogicTests
- XCTestCase
- StructureSnapshot
- Gesture
- WindowEventTap
- CanvasManager
- CurveEditor
- .setUpGestures
- LayerRowModel
- SelectionOverlayView
- SandwichCompositingUITests
- PerfMonitor
- EffectParams
- Kind
- ContentView
- RenderRequest
- CodingKeys
- GuideStroke
- ProjectManifest
- BlockDragCharacterizationTests
- InterpolationEngineDiagnosticsLogicTests
- Known Issues
- Recording
- .recognizer
- GalleryView
- Coordinator
- CanvasSizePickerView
- CanvasTransformFreezeUITests
- CodingKey
- Layer Compositing
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CGContextDabTarget
- .sample
- UndoHistory
- EraserSettingsPanel
- CompositorRole
- CanvasHostView
- .mixFixture
- CanvasManager
- SpacingChart
- Layer
- LayerManifest
- ActionsMenu
- SelectPanel
- 4. Future upgrades — the deferred list
- .testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold
- .row
- MotionGroupRow
- CLAUDE.md
- Multi-Session Protocol
- TransformOverlaySupport.swift
- Usage Guide
- PaintSoftware - iPad Drawing and Animation App
- Hashable
- LayerKind
- MoveTransformBottomBar
- 6. Alpha masks
- command
- JSONValue
- CutOutcome
- Kind
- ManifestSkeleton
- Handoff — 2026-08-16
- 4. The render tree
- VectorScratchRole
- .handleShouldReceive
- Atomic
- ToolPanelsUITests
- parallel_test.sh
- effectChannels
- Performance baseline
- Attempt
- CopiedCel
- Kind
- TODO
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 557 edges
2. `CGFloat` - 444 edges
3. `Effect` - 149 edges
4. `CanvasManager` - 141 edges
5. `VectorCanvas` - 123 edges
6. `layers` - 118 edges
7. `VectorSample` - 111 edges
8. `CanvasManager` - 100 edges
9. `Lattice` - 98 edges
10. `Coordinator` - 97 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (173 total, 9 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 1 - "CGFloat"
Cohesion: 0.05
Nodes (28): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Brush, CGFloat (+20 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (55): Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame (+47 more)

### Community 3 - "Lattice"
Cohesion: 0.05
Nodes (35): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+27 more)

### Community 4 - "ShapeGeometry"
Cohesion: 0.05
Nodes (32): ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft, bottomRight (+24 more)

### Community 5 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 6 - "CGPoint"
Cohesion: 0.06
Nodes (21): CGPoint, .length, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+13 more)

### Community 7 - "CanvasManager"
Cohesion: 0.05
Nodes (42): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+34 more)

### Community 8 - "VectorCanvas"
Cohesion: 0.05
Nodes (55): CodableColor, .uiColor, image, kind, ElementData, fill, image, stroke (+47 more)

### Community 9 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 10 - "Coordinator"
Cohesion: 0.06
Nodes (30): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, AppliedTool, CanvasView, Coordinator (+22 more)

### Community 11 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 12 - "String"
Cohesion: 0.04
Nodes (59): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+51 more)

### Community 13 - "AlphaMask"
Cohesion: 0.07
Nodes (14): AlphaMask, .isActive, Bool, Decoder, Int, CGSize, UIColor, MaskParityLogicTests (+6 more)

### Community 14 - "ARAPLogicTests"
Cohesion: 0.07
Nodes (21): ARAPInterpolation, Group, MotionGrouping, Options, Bool, Int, Set, CodingKeys (+13 more)

### Community 15 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (11): UIImage, EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor (+3 more)

### Community 16 - "InterpolationRecipe"
Cohesion: 0.07
Nodes (22): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+14 more)

### Community 17 - "InterpolationGuideLogicTests"
Cohesion: 0.10
Nodes (8): GuideSet, .isEmpty, Bool, InterpolationGuideLogicTests, CanvasManager, Cel, UUID, VectorStroke

### Community 18 - "UIKit"
Cohesion: 0.05
Nodes (10): CoreGraphics, Darwin, Foundation, Notification.Name, AppVersion, .versionString, String, ThumbnailRenderer (+2 more)

### Community 19 - "Codable"
Cohesion: 0.05
Nodes (47): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+39 more)

### Community 20 - "PointCloudIndex"
Cohesion: 0.11
Nodes (18): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+10 more)

### Community 21 - "StrokeCanvasView"
Cohesion: 0.07
Nodes (33): StrokeInput, TimeInterval, UITouch, UIView, Bool, VectorEraserMode, cutPoints, cutToIntersection (+25 more)

### Community 22 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+30 more)

### Community 23 - "AnimationTimeline"
Cohesion: 0.05
Nodes (46): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+38 more)

### Community 24 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 25 - "PerfBaselineTests"
Cohesion: 0.13
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.12
Nodes (17): ParityReport, .diagnostic, .isExact, ParityScenario, RasterVectorParity, Bool, Int, UIImage (+9 more)

### Community 27 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 28 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 29 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): PaintUITestCase, Bool, CGVector, Int, String, XCUIApplication, XCUIElement, InterpolationWorkflowUITests (+3 more)

### Community 30 - "MetalFillEngine"
Cohesion: 0.08
Nodes (30): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+22 more)

### Community 31 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 32 - ".drawLine"
Cohesion: 0.12
Nodes (9): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, Double, TimeInterval, UInt8, EraserAndPersistenceUITests, ShapeRecoveryUITests (+1 more)

### Community 33 - "CanvasManager"
Cohesion: 0.08
Nodes (28): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+20 more)

### Community 34 - ".apply"
Cohesion: 0.13
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 35 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 36 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+12 more)

### Community 37 - "Effect"
Cohesion: 0.10
Nodes (31): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, Curves, Effect, .displayName (+23 more)

### Community 38 - "BrushStamper"
Cohesion: 0.09
Nodes (22): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+14 more)

### Community 39 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 40 - "View"
Cohesion: 0.12
Nodes (32): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+24 more)

### Community 41 - "TimedSample"
Cohesion: 0.09
Nodes (11): GuideHandles, GuidePath, .end, .start, CGVector, Int, TimeInterval, TimeInterval (+3 more)

### Community 42 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 43 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 44 - "LayerTreeCharacterizationTests"
Cohesion: 0.13
Nodes (3): Layer, UUID, LayerTreeCharacterizationTests

### Community 45 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 46 - "ValueLayerLogicTests"
Cohesion: 0.13
Nodes (13): CGImage, CGRect, StaticString, String, UInt, UInt8, CanvasManager, CGImage (+5 more)

### Community 47 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 48 - "RenderQuality"
Cohesion: 0.10
Nodes (26): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderResolution, full, half (+18 more)

### Community 49 - "RenderTreeCharacterizationTests"
Cohesion: 0.15
Nodes (5): RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 50 - "RasterVectorParityLogicTests"
Cohesion: 0.10
Nodes (24): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+16 more)

### Community 51 - "LayerStackCell"
Cohesion: 0.09
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+3 more)

### Community 52 - "InterpolationRenderLogicTests"
Cohesion: 0.17
Nodes (10): ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage, UUID (+2 more)

### Community 53 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+13 more)

### Community 54 - "EffectSettingsMenu"
Cohesion: 0.11
Nodes (26): Gradient, stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+18 more)

### Community 55 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 56 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 57 - "CanvasNotice"
Cohesion: 0.06
Nodes (26): Alignment, Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer (+18 more)

### Community 58 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 59 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): FileHandle, ActionRecorder, .directory, .now, RecordingWriter, CFTimeInterval, CGSize, Double (+4 more)

### Community 60 - "VectorSample"
Cohesion: 0.15
Nodes (8): VectorSample, .point, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

### Community 61 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 62 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 63 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 64 - "layers"
Cohesion: 0.18
Nodes (11): .activeLayerIsVector, .activeCelIsInBetween, CanvasManager, Bool, Int, Cel, .endFrame, Int (+3 more)

### Community 65 - "CanvasManager"
Cohesion: 0.11
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 66 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 67 - ".beginCanvasEdit"
Cohesion: 0.09
Nodes (14): CanvasManager, Bool, CGSize, UIImage, String, UUID, VectorStroke, SelectionMode (+6 more)

### Community 68 - "GuideOverlayView"
Cohesion: 0.13
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 69 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 70 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 71 - "SaveSnapshot"
Cohesion: 0.15
Nodes (19): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+11 more)

### Community 72 - "InterpolateBar"
Cohesion: 0.08
Nodes (26): .body, GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton (+18 more)

### Community 73 - "StrokeGestureRecognizer"
Cohesion: 0.13
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 74 - "SwiftUI"
Cohesion: 0.08
Nodes (14): Combine, CodableColor, .color, Color, .codable, CodableColor, .interpolateButton, InterpolatePanel (+6 more)

### Community 75 - "OnionSkinLogicTests"
Cohesion: 0.13
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 76 - "Composite.metal"
Cohesion: 0.25
Nodes (26): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+18 more)

### Community 77 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+19 more)

### Community 78 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 79 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-integration, worker-research, worker-test, worker-ui, model, description (+17 more)

### Community 80 - "bash"
Cohesion: 0.16
Nodes (24): worker-bugfix, worker-feature, gh *, git *, xcodebuild *, permission, bash, edit (+16 more)

### Community 81 - ".coverage"
Cohesion: 0.16
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 82 - "MaskSource"
Cohesion: 0.16
Nodes (11): MaskSource, folder, .id, layer, Encoder, UUID, CanvasManager, .renderLeafOrder (+3 more)

### Community 83 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, layers, move (+9 more)

### Community 84 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 85 - "Compositor.swift"
Cohesion: 0.16
Nodes (21): os, BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor (+13 more)

### Community 86 - ".rows"
Cohesion: 0.14
Nodes (13): DispatchWorkItem, IndexPath, .rows, DropTarget, between, onto, LayerStackListView.Coordinator, CGRect (+5 more)

### Community 87 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 88 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 89 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 90 - "XCTestCase"
Cohesion: 0.14
Nodes (9): .antialiasHalfWidth, .threshold, Float, XCTestCase, MaskGuardLogicTests, ClosedRange, Float, Int (+1 more)

### Community 91 - "StructureSnapshot"
Cohesion: 0.12
Nodes (13): StructureSnapshot, Int, Layer, String, CanvasManager, .activeViewName, Int, String (+5 more)

### Community 92 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 93 - "WindowEventTap"
Cohesion: 0.21
Nodes (9): AnyClass, NSObject, FoundElement, InstallReport, CGRect, UIEvent, WindowEventTap, UIAccessibilityTraits (+1 more)

### Community 94 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 95 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 96 - ".setUpGestures"
Cohesion: 0.14
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 97 - "LayerRowModel"
Cohesion: 0.18
Nodes (12): LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, CanvasManager, Double, Int (+4 more)

### Community 98 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 99 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 100 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+7 more)

### Community 101 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 102 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 103 - "ContentView"
Cohesion: 0.13
Nodes (13): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+5 more)

### Community 104 - "RenderRequest"
Cohesion: 0.30
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, RenderRequest, UIGraphicsImageRendererContext

### Community 105 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 106 - "GuideStroke"
Cohesion: 0.18
Nodes (9): GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool, Decoder (+1 more)

### Community 107 - "ProjectManifest"
Cohesion: 0.25
Nodes (13): CodableColor, FolderManifest, ProjectManifest, Bool, CodableColor, Date, Decoder, Double (+5 more)

### Community 108 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 109 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 110 - "Known Issues"
Cohesion: 0.11
Nodes (18): A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), An interrupted stroke stubs, and no terminal callback runs (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16), Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21) (+10 more)

### Community 111 - "Recording"
Cohesion: 0.14
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 112 - ".recognizer"
Cohesion: 0.18
Nodes (7): ObjectIdentifier, UIGestureRecognizer, Entry, ObjectIdentifier, Set, UIGestureRecognizer, UIView

### Community 113 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 114 - "Coordinator"
Cohesion: 0.20
Nodes (9): Coordinator, LayerStackListView, Context, Coordinator, UIPinchGestureRecognizer, Void, UITableView, UITableViewDiffableDataSource (+1 more)

### Community 115 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 116 - "CanvasTransformFreezeUITests"
Cohesion: 0.29
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 117 - "CodingKey"
Cohesion: 0.12
Nodes (16): CodingKey, CodingKeys, id, invert, isEnabled, kind, sources, CodingKeys (+8 more)

### Community 118 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 119 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 120 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 121 - "CGContextDabTarget"
Cohesion: 0.23
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 122 - ".sample"
Cohesion: 0.29
Nodes (10): ObjectiveC.runtime, ResolvedTarget, Bool, CGSize, Double, Int, String, UITouch (+2 more)

### Community 123 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 124 - "EraserSettingsPanel"
Cohesion: 0.16
Nodes (12): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+4 more)

### Community 125 - "CompositorRole"
Cohesion: 0.14
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 126 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 127 - ".mixFixture"
Cohesion: 0.25
Nodes (3): CanvasManager, String, UUID

### Community 129 - "SpacingChart"
Cohesion: 0.23
Nodes (3): SpacingChart, .curve, .draggable

### Community 130 - "Layer"
Cohesion: 0.17
Nodes (11): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+3 more)

### Community 131 - "LayerManifest"
Cohesion: 0.27
Nodes (5): Decoder, ValueFill, CelManifest, LayerManifest, BlendMode

### Community 132 - "ActionsMenu"
Cohesion: 0.23
Nodes (10): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, CanvasManager, Double (+2 more)

### Community 133 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 134 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 135 - ".testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold"
Cohesion: 0.38
Nodes (6): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64, CGSize

### Community 136 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 137 - "MotionGroupRow"
Cohesion: 0.31
Nodes (6): MotionGroupRow, .body, .colourBakeButton, .wholeFrameNote, CanvasManager, String

### Community 139 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 140 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 141 - "Usage Guide"
Cohesion: 0.22
Nodes (9): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide (+1 more)

### Community 142 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 143 - "Hashable"
Cohesion: 0.25
Nodes (7): Hashable, CelLocation, Tool, eraser, fill, pen, pencil

### Community 144 - "LayerKind"
Cohesion: 0.25
Nodes (6): LayerKind, raster, value, vector, K, KeyedDecodingContainer

### Community 145 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 146 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 147 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 148 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 149 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 150 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 151 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 152 - "Handoff — 2026-08-16"
Cohesion: 0.33
Nodes (6): Blocked on the owner, Branch state, Handoff — 2026-08-16, Process, learned expensively here, The one genuinely new capability: you can test on the owner's iPad, The two open bugs, with what is already known

### Community 153 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 154 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 155 - ".handleShouldReceive"
Cohesion: 0.53
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 156 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 158 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 159 - "effectChannels"
Cohesion: 0.70
Nodes (5): effectChannels(), lutEntry(), uint, noiseValue(), screenValue()

### Community 160 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 161 - "Attempt"
Cohesion: 0.50
Nodes (4): Attempt, image, unavailable, underPressure

### Community 162 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 163 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 164 - "TODO"
Cohesion: 0.50
Nodes (4): Done this pass, In flight, Queued, TODO

### Community 165 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **715 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+710 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `SpacingChart`, `CanvasManager`, `Lattice`, `ShapeGeometry`, `ActionsMenu`, `CGPoint`, `CanvasManager`, `VectorCanvas`, `Coordinator`, `Coordinator`, `CompositorParityLogicTests`, `String`, `TransformOverlaySupport.swift`, `ARAPLogicTests`, `EffectLayerLogicTests`, `InterpolationRecipe`, `InterpolationGuideLogicTests`, `AlphaMask`, `JSONValue`, `PointCloudIndex`, `StrokeCanvasView`, `Kind`, `AnimationTimeline`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `SandwichLogicTests`, `PaintUITestCase`, `CanvasManager`, `.apply`, `ShapeOverlayView`, `.transparentFormat`, `BrushStamper`, `BrushEngineLogicTests`, `TimedSample`, `ProjectSaveLogicTests`, `.launchIntoEditor`, `DeformFactorization`, `RenderQuality`, `RasterVectorParityLogicTests`, `LayerStackCell`, `InterpolationRenderLogicTests`, `.evaluate`, `EffectSettingsMenu`, `RasterLayerTexture`, `CanvasNotice`, `ActionRecorder`, `VectorSample`, `StrokeSettingsPanel`, `StrokeSpatialIndex`, `CanvasManager`, `.beginCanvasEdit`, `GuideOverlayView`, `InterpolateBar`, `OnionSkinLogicTests`, `ObjectTransformOverlayView`, `XCUIApplication`, `.rows`, `PinchMergeGateLogicTests`, `WindowEventTap`, `CanvasManager`, `CurveEditor`, `SandwichCompositingUITests`, `RenderRequest`, `CodingKeys`, `InterpolationEngineDiagnosticsLogicTests`, `Coordinator`, `CanvasTransformFreezeUITests`, `SideToolbar`, `CGContextDabTarget`, `.sample`, `EraserSettingsPanel`?**
  _High betweenness centrality (0.328) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `CGFloat`, `CanvasManager`, `Lattice`, `ShapeGeometry`, `.manager`, `CanvasManager`, `VectorCanvas`, `Coordinator`, `Coordinator`, `TransformOverlaySupport.swift`, `AlphaMask`, `ARAPLogicTests`, `String`, `InterpolationRecipe`, `InterpolationGuideLogicTests`, `UIKit`, `PointCloudIndex`, `StrokeCanvasView`, `ColorPickerPanel`, `AnimationTimeline`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `CanvasManager`, `ShapeOverlayView`, `.transparentFormat`, `BrushStamper`, `BrushEngineLogicTests`, `TimedSample`, `ProjectSaveLogicTests`, `DeformFactorization`, `RasterVectorParityLogicTests`, `InterpolationRenderLogicTests`, `.evaluate`, `RasterLayerTexture`, `VectorSample`, `StrokeSpatialIndex`, `layers`, `CanvasManager`, `.beginCanvasEdit`, `GuideOverlayView`, `ObjectTransformOverlayView`, `.rows`, `FloatingPieceOverlayView`, `WindowEventTap`, `CurveEditor`, `.setUpGestures`, `SelectionOverlayView`, `InterpolationEngineDiagnosticsLogicTests`, `CGContextDabTarget`, `.sample`?**
  _High betweenness centrality (0.127) - this node is a cross-community bridge._
- **Why does `permission` connect `bash` to `read`, `agent`?**
  _High betweenness centrality (0.111) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._