# Graph Report - PaintApp-compperf  (2026-08-16)

## Corpus Check
- 180 files · ~510,012 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5373 nodes · 16558 edges · 189 communities (176 shown, 13 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1735 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f1578b90`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- CanvasManager
- LayerTreeCharacterizationTests
- ShapeGeometry
- Coordinator
- Lattice
- .apply
- CompositorParityLogicTests
- Coordinator
- EffectLayerLogicTests
- DeformFactorization
- .manager
- PerfBaselineTests
- VectorEraserHybridLogicTests
- AnimationTimeline
- PointCloudIndex
- SandwichLogicTests
- Equatable
- VectorElement
- CodingKeys
- ColorPickerPanel
- MaskGuardLogicTests
- .transparentFormat
- LayerManifest
- ProjectBackupManager
- AlphaMask
- PaintUITestCase
- StrokeCanvasView
- layers
- EffectMultiPassLogicTests
- .drawLine
- UIKit
- VectorEraserLogicTests
- CompositorMetalEngine
- String
- ShapeOverlayView
- Effect
- View
- VectorCanvas
- CanvasManager
- ProjectSaveLogicTests
- .launchIntoEditor
- ActionRecorder
- CGPoint
- ARAPLogicTests
- XCTestCase
- InterpolationRenderLogicTests
- LayerStackCell
- CGFloat
- .activeCelIndex
- .report
- SaveSnapshot
- .evaluate
- CanvasManager
- BackupManagerLogicTests
- CanvasNotice
- CodingKeys
- InterpolationModelLogicTests
- PlaybackBoundsCharacterizationTests
- CutOutcome
- Codable
- MaskSource
- Coordinator
- CanvasManager
- RenderNode
- BrushStamper
- StrokeSpatialIndex
- BlendMode
- GuideOverlayView
- EffectParityLogicTests
- FillParams
- StrokeSampleGateLogicTests
- StrokeGestureRecognizer
- RenderResolution
- .withStructureUndo
- MetalFillEngine
- RasterLayerTexture
- CodingKeys
- Composite.metal
- EraserSettingsPanel
- agent
- PaletteColor
- bash
- TimedSample
- ActivePanel
- InterpolationGuideLogicTests
- XCUIApplication
- StrokeSettingsPanel
- GuidePath
- FloatingPieceOverlayView
- read
- BrushDynamics
- GuideRow
- .manager
- Gesture
- WindowEventTap
- CompositorRole
- Layer Compositing
- CanvasManager
- CurveEditor
- SwiftUI
- InterpolationRefusal
- .setUpGestures
- ObjectTransformOverlayView
- SelectionOverlayView
- Compositor.swift
- SandwichCompositingUITests
- PerfMonitor
- LayerStackListView.Coordinator
- .rows
- GuideStroke
- EffectParams
- TransformMode
- OnionSkinLogicTests
- BlockDragCharacterizationTests
- ContentView
- Cel
- CodingKeys
- LayerRowModel
- Recording
- Identifiable
- StructureSnapshot
- .rasterize
- InterpolateBar
- GalleryView
- .indices
- CanvasSizePickerView
- CanvasTransformFreezeUITests
- Known Issues
- ViewPreset
- ActionsMenu
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- .arched
- BrushBlendMode
- DabTarget
- .attach
- .sample
- Kind
- CanvasHostView
- RenderRequest
- SpacingChart
- TransformOverlaySupport.swift
- .noteTransition
- StrokeStabilizer
- ValueFill
- SelectPanel
- 4. Future upgrades — the deferred list
- .testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold
- BrushGrain
- .setCanvasPadding
- .row
- Multi-Session Protocol
- Handoff — UX pass round 2 (2026-08-16)
- BrushShape
- Usage Guide
- PaintSoftware - iPad Drawing and Animation App
- CLAUDE.md
- LayerKind
- VectorEraserMode
- BrushSettingsPanel
- MoveTransformBottomBar
- .coverage
- 6. Alpha masks
- RecordingWriter
- JSONValue
- CodingKeys
- ManifestSkeleton
- VectorScratchRole
- Atomic
- ToolPanelsUITests
- parallel_test.sh
- effectChannels
- CodingKeys
- ProjectStore.swift
- Performance baseline
- SandwichPresentation
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- 5. The compositor
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- CopiedCel
- .setPinchHighlight
- Kind

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 557 edges
2. `CGFloat` - 437 edges
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

## Communities (189 total, 13 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - "CanvasManager"
Cohesion: 0.05
Nodes (33): Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+25 more)

### Community 2 - "LayerTreeCharacterizationTests"
Cohesion: 0.06
Nodes (14): Layer, StaticString, String, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String (+6 more)

### Community 3 - "ShapeGeometry"
Cohesion: 0.05
Nodes (32): ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft, bottomRight (+24 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (47): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+39 more)

### Community 5 - "Lattice"
Cohesion: 0.05
Nodes (35): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+27 more)

### Community 6 - ".apply"
Cohesion: 0.13
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 7 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 8 - "Coordinator"
Cohesion: 0.06
Nodes (26): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, CanvasView, Coordinator (+18 more)

### Community 9 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 10 - "DeformFactorization"
Cohesion: 0.12
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 11 - ".manager"
Cohesion: 0.07
Nodes (9): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager (+1 more)

### Community 12 - "PerfBaselineTests"
Cohesion: 0.14
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 13 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 14 - "AnimationTimeline"
Cohesion: 0.05
Nodes (46): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+38 more)

### Community 15 - "PointCloudIndex"
Cohesion: 0.10
Nodes (18): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+10 more)

### Community 16 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 17 - "Equatable"
Cohesion: 0.16
Nodes (21): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, .lookupTable (+13 more)

### Community 18 - "VectorElement"
Cohesion: 0.06
Nodes (37): kind, transform, ElementData, fill, image, stroke, ImageRef, Kind (+29 more)

### Community 19 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+20 more)

### Community 20 - "ColorPickerPanel"
Cohesion: 0.11
Nodes (21): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+13 more)

### Community 21 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 22 - ".transparentFormat"
Cohesion: 0.17
Nodes (14): IntPoint, PixelOps, .rasterizeCacheBytes, Bool, CGPath, CGRect, CGSize, Color (+6 more)

### Community 23 - "LayerManifest"
Cohesion: 0.20
Nodes (16): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool, CodableColor (+8 more)

### Community 24 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 25 - "AlphaMask"
Cohesion: 0.08
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 26 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): PaintUITestCase, Bool, CGVector, Int, String, XCUIApplication, XCUIElement, InterpolationWorkflowUITests (+3 more)

### Community 27 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (24): StrokeInput, TimeInterval, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+16 more)

### Community 28 - "layers"
Cohesion: 0.07
Nodes (25): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+17 more)

### Community 29 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 30 - ".drawLine"
Cohesion: 0.12
Nodes (9): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, Double, TimeInterval, UInt8, EraserAndPersistenceUITests, ShapeRecoveryUITests (+1 more)

### Community 31 - "UIKit"
Cohesion: 0.06
Nodes (10): CoreGraphics, Darwin, Foundation, Notification.Name, AppVersion, .versionString, String, ThumbnailRenderer (+2 more)

### Community 32 - "VectorEraserLogicTests"
Cohesion: 0.08
Nodes (9): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 33 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 34 - "String"
Cohesion: 0.10
Nodes (23): Kind, folder, layer, String, UUID, CanvasManager, FloatingPiece, .transformedBounds (+15 more)

### Community 35 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 36 - "Effect"
Cohesion: 0.07
Nodes (27): Effect, bloom, blur, brightnessContrast, chromaticAberration, curves, .displayName, gradientMap (+19 more)

### Community 37 - "View"
Cohesion: 0.12
Nodes (32): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+24 more)

### Community 38 - "VectorCanvas"
Cohesion: 0.09
Nodes (23): image, RenderQuality, full, preview, Int, UIImage, VectorCanvas, .elements (+15 more)

### Community 39 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 40 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 41 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 42 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 43 - "CGPoint"
Cohesion: 0.07
Nodes (18): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+10 more)

### Community 44 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (16): ARAPInterpolation, Interpolator, Options, Bool, Group, MotionGrouping, Options, Int (+8 more)

### Community 45 - "XCTestCase"
Cohesion: 0.10
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 46 - "InterpolationRenderLogicTests"
Cohesion: 0.15
Nodes (13): StrokeComposite, erase, paint, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double (+5 more)

### Community 47 - "LayerStackCell"
Cohesion: 0.11
Nodes (9): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, UIView, Void (+1 more)

### Community 48 - "CGFloat"
Cohesion: 0.07
Nodes (30): Brush, CGFloat, VectorSample, Capsule, .boundingBox, StrokeGeometry, Bool, CGRect (+22 more)

### Community 49 - ".activeCelIndex"
Cohesion: 0.18
Nodes (6): .interpolationTarget, LayerTransform, UIImage, CanvasManager, Bool, Int

### Community 50 - ".report"
Cohesion: 0.09
Nodes (34): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+26 more)

### Community 51 - "SaveSnapshot"
Cohesion: 0.15
Nodes (19): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+11 more)

### Community 52 - ".evaluate"
Cohesion: 0.11
Nodes (24): CGPathElementType, ContentProvider, GuideSet, .isEmpty, Bool, Direction, backward, forward (+16 more)

### Community 53 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 54 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 55 - "CanvasNotice"
Cohesion: 0.06
Nodes (26): Alignment, Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer (+18 more)

### Community 56 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 57 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (11): InterpolationReference, InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL (+3 more)

### Community 58 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 59 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 60 - "Codable"
Cohesion: 0.13
Nodes (20): Codable, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, Kind (+12 more)

### Community 61 - "MaskSource"
Cohesion: 0.12
Nodes (14): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Bool (+6 more)

### Community 62 - "Coordinator"
Cohesion: 0.22
Nodes (9): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+1 more)

### Community 63 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 64 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 65 - "BrushStamper"
Cohesion: 0.16
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 66 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 67 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 68 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 69 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 70 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 71 - "StrokeSampleGateLogicTests"
Cohesion: 0.11
Nodes (8): StrokeSampleGate, Bool, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

### Community 72 - "StrokeGestureRecognizer"
Cohesion: 0.08
Nodes (24): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo (+16 more)

### Community 73 - "RenderResolution"
Cohesion: 0.13
Nodes (18): CanvasManager, LayerRenderSource, RenderBackground, RenderResolution, full, half, .id, .scale (+10 more)

### Community 74 - ".withStructureUndo"
Cohesion: 0.13
Nodes (13): BlendMode, UUID, Void, LayerFolder, .compositorOp, .isCompositorNode, .maxInputCount, BlendMode (+5 more)

### Community 75 - "MetalFillEngine"
Cohesion: 0.08
Nodes (30): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+22 more)

### Community 76 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 77 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 78 - "Composite.metal"
Cohesion: 0.25
Nodes (26): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+18 more)

### Community 79 - "EraserSettingsPanel"
Cohesion: 0.16
Nodes (12): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+4 more)

### Community 80 - "agent"
Cohesion: 0.07
Nodes (28): agent, orchestrator, worker-integration, worker-test, worker-ui, command, deploy, resign (+20 more)

### Community 81 - "PaletteColor"
Cohesion: 0.16
Nodes (16): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+8 more)

### Community 82 - "bash"
Cohesion: 0.13
Nodes (28): worker-bugfix, worker-feature, worker-research, gh *, git *, xcodebuild *, permission, bash (+20 more)

### Community 83 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 84 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, layers, move (+9 more)

### Community 86 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 87 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 88 - "GuidePath"
Cohesion: 0.23
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 89 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 90 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 91 - "BrushDynamics"
Cohesion: 0.29
Nodes (3): BrushDynamics, Double, UUID

### Community 92 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 93 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 94 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 95 - "WindowEventTap"
Cohesion: 0.21
Nodes (9): AnyClass, NSObject, FoundElement, InstallReport, CGRect, UIEvent, WindowEventTap, UIAccessibilityTraits (+1 more)

### Community 96 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 97 - "Layer Compositing"
Cohesion: 0.11
Nodes (18): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+10 more)

### Community 98 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 99 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 100 - "SwiftUI"
Cohesion: 0.11
Nodes (10): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+2 more)

### Community 101 - "InterpolationRefusal"
Cohesion: 0.18
Nodes (11): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+3 more)

### Community 102 - ".setUpGestures"
Cohesion: 0.11
Nodes (13): .sandwichPresentation, CGSize, Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView (+5 more)

### Community 103 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 104 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 105 - "Compositor.swift"
Cohesion: 0.16
Nodes (21): os, BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor (+13 more)

### Community 106 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 107 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 108 - "LayerStackListView.Coordinator"
Cohesion: 0.16
Nodes (10): DispatchWorkItem, DropTarget, between, onto, LayerStackListView.Coordinator, CGRect, TimeInterval, UILongPressGestureRecognizer (+2 more)

### Community 109 - ".rows"
Cohesion: 0.12
Nodes (28): Gradient, stops, GradientStop, CodableColor, .color, Color, .effectColor, EffectCatalog (+20 more)

### Community 110 - "GuideStroke"
Cohesion: 0.16
Nodes (11): Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+3 more)

### Community 111 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 112 - "TransformMode"
Cohesion: 0.09
Nodes (20): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+12 more)

### Community 113 - "OnionSkinLogicTests"
Cohesion: 0.13
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 114 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 115 - "ContentView"
Cohesion: 0.13
Nodes (13): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+5 more)

### Community 116 - "Cel"
Cohesion: 0.18
Nodes (13): MergeLossKind, blendMode, .confirmationMessage, valueLayerContent, PendingMergeConfirmation, CGSize, Layer, String (+5 more)

### Community 117 - "CodingKeys"
Cohesion: 0.12
Nodes (17): CodingKeys, brush, color, composite, elements, fill, fills, id (+9 more)

### Community 118 - "LayerRowModel"
Cohesion: 0.18
Nodes (10): String, UIColor, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, Double (+2 more)

### Community 119 - "Recording"
Cohesion: 0.15
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 120 - "Identifiable"
Cohesion: 0.15
Nodes (14): Identifiable, .motionGroupChips, GroupRegistration, MotionGroupChip, .id, Layer, GroupInterpolation, auto (+6 more)

### Community 121 - "StructureSnapshot"
Cohesion: 0.16
Nodes (6): CanvasManager, StructureSnapshot, Int, Layer, String, guideStrokes

### Community 122 - ".rasterize"
Cohesion: 0.19
Nodes (7): RasterizeCache, .bytesResident, RasterizeKey, Cel, ObjectIdentifier, UUID, CGSize

### Community 123 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 124 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 126 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 127 - "CanvasTransformFreezeUITests"
Cohesion: 0.29
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 128 - "Known Issues"
Cohesion: 0.12
Nodes (17): A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16), Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues (+9 more)

### Community 129 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 130 - "ActionsMenu"
Cohesion: 0.21
Nodes (10): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, CanvasManager, Double (+2 more)

### Community 131 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 132 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 134 - "BrushBlendMode"
Cohesion: 0.22
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 135 - "DabTarget"
Cohesion: 0.20
Nodes (10): AnyObject, CGGradient, Key, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode (+2 more)

### Community 136 - ".attach"
Cohesion: 0.23
Nodes (5): IndexPath, Context, UIPinchGestureRecognizer, UISwipeActionsConfiguration, UITableView

### Community 137 - ".sample"
Cohesion: 0.29
Nodes (10): ObjectiveC.runtime, ResolvedTarget, Bool, CGSize, Double, Int, String, UITouch (+2 more)

### Community 138 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 139 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 140 - "RenderRequest"
Cohesion: 0.23
Nodes (12): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, Attempt, image (+4 more)

### Community 141 - "SpacingChart"
Cohesion: 0.19
Nodes (3): SpacingChart, .curve, .draggable

### Community 142 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 143 - ".noteTransition"
Cohesion: 0.29
Nodes (5): Entry, ObjectIdentifier, Set, UIGestureRecognizer, UIView

### Community 144 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 145 - "ValueFill"
Cohesion: 0.08
Nodes (23): CodingKey, CodingKeys, color, Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill (+15 more)

### Community 146 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 147 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 148 - ".testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold"
Cohesion: 0.33
Nodes (6): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64, CGSize

### Community 149 - "BrushGrain"
Cohesion: 0.20
Nodes (5): BrushGrain, Bool, BrushLibrary, .customBrushesDirectory, URL

### Community 150 - ".setCanvasPadding"
Cohesion: 0.36
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 151 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 152 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 153 - "Handoff — UX pass round 2 (2026-08-16)"
Cohesion: 0.22
Nodes (9): Also gating `tmp/compperf`, Blocked on the owner — ask for these, Close-out, when the above is merged, Handoff — UX pass round 2 (2026-08-16), Process — read this, it cost this session real time, Read these first, State of the work, Still open from BUGS.md, unrelated to this pass (+1 more)

### Community 154 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 155 - "Usage Guide"
Cohesion: 0.22
Nodes (9): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide (+1 more)

### Community 156 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 158 - "LayerKind"
Cohesion: 0.25
Nodes (6): LayerKind, raster, value, vector, K, KeyedDecodingContainer

### Community 159 - "VectorEraserMode"
Cohesion: 0.12
Nodes (16): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+8 more)

### Community 160 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 161 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 162 - ".coverage"
Cohesion: 0.18
Nodes (12): Hasher, CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8 (+4 more)

### Community 163 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 165 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 166 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, id, invert, isEnabled, kind, sources

### Community 167 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 168 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 169 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 171 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 172 - "effectChannels"
Cohesion: 0.70
Nodes (5): effectChannels(), lutEntry(), uint, noiseValue(), screenValue()

### Community 173 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 174 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 175 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 176 - "SandwichPresentation"
Cohesion: 0.67
Nodes (3): SandwichPresentation, disengaged, midStroke

### Community 177 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 180 - "5. The compositor"
Cohesion: 0.50
Nodes (4): 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance, 5. The compositor

### Community 186 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 188 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

## Knowledge Gaps
- **714 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+709 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `CanvasManager`, `ShapeGeometry`, `Coordinator`, `Lattice`, `.apply`, `CompositorParityLogicTests`, `Coordinator`, `EffectLayerLogicTests`, `DeformFactorization`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `AnimationTimeline`, `PointCloudIndex`, `SandwichLogicTests`, `VectorElement`, `.transparentFormat`, `AlphaMask`, `PaintUITestCase`, `StrokeCanvasView`, `layers`, `VectorEraserLogicTests`, `String`, `ShapeOverlayView`, `VectorCanvas`, `ProjectSaveLogicTests`, `.launchIntoEditor`, `ActionRecorder`, `CGPoint`, `ARAPLogicTests`, `InterpolationRenderLogicTests`, `LayerStackCell`, `.report`, `.evaluate`, `CanvasManager`, `CanvasNotice`, `InterpolationModelLogicTests`, `Codable`, `Coordinator`, `CanvasManager`, `BrushStamper`, `StrokeSpatialIndex`, `GuideOverlayView`, `StrokeSampleGateLogicTests`, `RenderResolution`, `RasterLayerTexture`, `EraserSettingsPanel`, `TimedSample`, `InterpolationGuideLogicTests`, `XCUIApplication`, `StrokeSettingsPanel`, `GuidePath`, `FloatingPieceOverlayView`, `BrushDynamics`, `.manager`, `WindowEventTap`, `CanvasManager`, `CurveEditor`, `.setUpGestures`, `SandwichCompositingUITests`, `.rows`, `OnionSkinLogicTests`, `LayerRowModel`, `InterpolateBar`, `.indices`, `CanvasTransformFreezeUITests`, `ActionsMenu`, `SideToolbar`, `DabTarget`, `.attach`, `.sample`, `RenderRequest`, `SpacingChart`, `TransformOverlaySupport.swift`, `StrokeStabilizer`, `BrushGrain`, `.setCanvasPadding`, `VectorEraserMode`, `JSONValue`?**
  _High betweenness centrality (0.315) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `ShapeGeometry`, `Coordinator`, `Lattice`, `.arched`, `DabTarget`, `Coordinator`, `.sample`, `DeformFactorization`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `AnimationTimeline`, `PointCloudIndex`, `StrokeStabilizer`, `TransformOverlaySupport.swift`, `VectorElement`, `ColorPickerPanel`, `BrushGrain`, `.setCanvasPadding`, `.transparentFormat`, `AlphaMask`, `StrokeCanvasView`, `layers`, `VectorEraserLogicTests`, `String`, `ShapeOverlayView`, `VectorCanvas`, `ProjectSaveLogicTests`, `ARAPLogicTests`, `InterpolationRenderLogicTests`, `CGFloat`, `.activeCelIndex`, `.report`, `.evaluate`, `CanvasManager`, `InterpolationModelLogicTests`, `CanvasManager`, `BrushStamper`, `StrokeSpatialIndex`, `GuideOverlayView`, `StrokeSampleGateLogicTests`, `RasterLayerTexture`, `TimedSample`, `InterpolationGuideLogicTests`, `GuidePath`, `FloatingPieceOverlayView`, `.manager`, `WindowEventTap`, `CurveEditor`, `.setUpGestures`, `ObjectTransformOverlayView`, `SelectionOverlayView`, `LayerStackListView.Coordinator`, `.rasterize`, `.indices`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `task` connect `bash` to `CanvasNotice`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._