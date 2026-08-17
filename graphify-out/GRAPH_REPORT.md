# Graph Report - PaintApp-pinchmerge  (2026-08-17)

## Corpus Check
- 181 files · ~509,643 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5376 nodes · 16562 edges · 186 communities (172 shown, 14 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1735 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2a3c604a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- VectorCanvas
- CanvasManager
- LayerTreeCharacterizationTests
- Lattice
- CGPoint
- Coordinator
- .manager
- CompositorParityLogicTests
- Coordinator
- CGFloat
- ARAPLogicTests
- CanvasManager
- AlphaMask
- CanvasManager
- EffectLayerLogicTests
- Codable
- UIKit
- StrokeCanvasView
- SandwichLogicTests
- ColorPickerPanel
- CodingKeys
- EffectMultiPassLogicTests
- PerfBaselineTests
- .drawLine
- ProjectBackupManager
- CompositorMetalEngine
- VectorEraserLogicTests
- .apply
- PaintUITestCase
- ShapeOverlayView
- .report
- Effect
- ValueLayerLogicTests
- BrushEngineLogicTests
- layers
- View
- CanvasManager
- SaveSnapshot
- ProjectSaveLogicTests
- AnimationTimeline
- .launchIntoEditor
- BrushBlendMode
- .transparentFormat
- .restLattice
- StrokeGeometryLogicTests
- RenderQuality
- InterpolationRenderLogicTests
- .rows
- CanvasManager
- WindowEventTap
- .evaluate
- RasterLayerTexture
- RenderNode
- BackupManagerLogicTests
- InterpolationModelLogicTests
- CanvasNotice
- FloatingPieceOverlayView
- agent
- ActionRecorder
- VectorSample
- PlaybackBoundsCharacterizationTests
- BrushStamper
- Composite.metal
- InterpolationRecipe
- VectorEraserHybridLogicTests
- StrokeSettingsPanel
- GuideOverlayView
- StrokeSpatialIndex
- BlendMode
- LayerManifest
- EffectParityLogicTests
- FillParams
- MetalFillEngine
- StrokeGestureRecognizer
- DeformFactorization
- MaskSource
- OnionSkinLogicTests
- ActionsMenu
- TimedSample
- LayerStackCell
- ActivePanel
- InterpolationGuideLogicTests
- XCUIApplication
- SwiftUI
- Compositor.swift
- GuideStroke
- GuideRow
- Gesture
- LayerStackListView.Coordinator
- read
- RenderRequest
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- ContentView
- .indices
- InterpolationRefusal
- SelectionOverlayView
- EffectPipelines
- EffectParams
- Layer
- .setUpGestures
- InterpolationEngineDiagnosticsLogicTests
- .manager
- SandwichCompositingUITests
- .arched
- CodingKeys
- BlockDragCharacterizationTests
- Known Issues
- PerfMonitor
- .coverage
- MotionGroup
- InterpolateBar
- LayerRowModel
- Coordinator
- Recording
- StructureSnapshot
- CanvasManager
- LayerStackRow
- UUID
- CanvasSizePickerView
- CanvasTransformFreezeUITests
- Layer Compositing
- ViewPreset
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- bash
- CompositorRole
- ObjectTransformOverlayView
- CGContextDabTarget
- Kind
- UndoHistory
- CanvasHostView
- SpacingChart
- .noteTransition
- .analyse
- StrokeStabilizer
- SelectPanel
- 4. Future upgrades — the deferred list
- Hashable
- .testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold
- VectorEraserMode
- .rasterize
- .row
- CLAUDE.md
- Multi-Session Protocol
- TransformOverlaySupport.swift
- Usage Guide
- PaintSoftware - iPad Drawing and Animation App
- MoveTransformBottomBar
- 6. Alpha masks
- command
- JSONValue
- CutOutcome
- ManifestSkeleton
- Handoff — 2026-08-16
- 4. The render tree
- Kind
- ProjectStore.swift
- VectorScratchRole
- ProjectVersionsView
- Atomic
- Gesture
- ToolPanelsUITests
- Gesture
- CaseIterable
- parallel_test.sh
- RecordingWriter
- Corner
- Edge
- Performance baseline
- .encode
- CopiedCel
- Kind
- TODO
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- Kind
- .bytes
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

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
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift

## Import Cycles
- None detected.

## Communities (186 total, 14 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 1 - "VectorCanvas"
Cohesion: 0.05
Nodes (62): Identifiable, CodableColor, .uiColor, image, kind, DabLattice, .range, ElementData (+54 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (52): Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame (+44 more)

### Community 3 - "LayerTreeCharacterizationTests"
Cohesion: 0.06
Nodes (15): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+7 more)

### Community 4 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 5 - "CGPoint"
Cohesion: 0.06
Nodes (30): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+22 more)

### Community 6 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 7 - ".manager"
Cohesion: 0.07
Nodes (9): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager (+1 more)

### Community 8 - "CompositorParityLogicTests"
Cohesion: 0.09
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 9 - "Coordinator"
Cohesion: 0.06
Nodes (30): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, CanvasView, Coordinator, .sandwichPresentation (+22 more)

### Community 10 - "CGFloat"
Cohesion: 0.08
Nodes (18): Brush, CGFloat, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+10 more)

### Community 11 - "ARAPLogicTests"
Cohesion: 0.09
Nodes (19): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+11 more)

### Community 12 - "CanvasManager"
Cohesion: 0.05
Nodes (41): CanvasManager, Bool, CGSize, UIImage, String, UUID, Void, CanvasManager (+33 more)

### Community 13 - "AlphaMask"
Cohesion: 0.08
Nodes (12): AlphaMask, .isActive, Bool, Decoder, Int, MaskParityLogicTests, .side, Bool (+4 more)

### Community 14 - "CanvasManager"
Cohesion: 0.07
Nodes (24): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips (+16 more)

### Community 15 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 16 - "Codable"
Cohesion: 0.05
Nodes (47): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+39 more)

### Community 17 - "UIKit"
Cohesion: 0.06
Nodes (11): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String (+3 more)

### Community 18 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (27): StrokeInput, TimeInterval, UITouch, UIView, StrokeSampleGate, Bool, NSCoder, StrokeCanvasView (+19 more)

### Community 19 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 20 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (35): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+27 more)

### Community 21 - "CodingKeys"
Cohesion: 0.04
Nodes (57): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+49 more)

### Community 22 - "EffectMultiPassLogicTests"
Cohesion: 0.11
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 23 - "PerfBaselineTests"
Cohesion: 0.13
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 24 - ".drawLine"
Cohesion: 0.12
Nodes (11): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+3 more)

### Community 25 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 26 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 27 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 28 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 29 - "PaintUITestCase"
Cohesion: 0.11
Nodes (10): PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests, UndoAndLayerHistoryUITests (+2 more)

### Community 30 - "ShapeOverlayView"
Cohesion: 0.07
Nodes (30): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+22 more)

### Community 31 - ".report"
Cohesion: 0.12
Nodes (26): CustomStringConvertible, Backdrop, fill, image, none, ParityPixel, .description, ParityReport (+18 more)

### Community 32 - "Effect"
Cohesion: 0.10
Nodes (36): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+28 more)

### Community 33 - "ValueLayerLogicTests"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 34 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 35 - "layers"
Cohesion: 0.12
Nodes (16): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, LayerTransform, UIImage, CanvasManager (+8 more)

### Community 36 - "View"
Cohesion: 0.12
Nodes (32): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+24 more)

### Community 37 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 38 - "SaveSnapshot"
Cohesion: 0.10
Nodes (26): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+18 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 40 - "AnimationTimeline"
Cohesion: 0.07
Nodes (31): AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .isTimelineMenuPresented, .layerNameColumn (+23 more)

### Community 41 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 42 - "BrushBlendMode"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 43 - ".transparentFormat"
Cohesion: 0.13
Nodes (18): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+10 more)

### Community 44 - ".restLattice"
Cohesion: 0.10
Nodes (8): ARAPInterpolation, Interpolator, Options, Bool, Int, StaticString, String, UInt

### Community 45 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (6): StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 46 - "RenderQuality"
Cohesion: 0.09
Nodes (26): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderResolution, full, half (+18 more)

### Community 47 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 48 - ".rows"
Cohesion: 0.12
Nodes (28): Gradient, stops, GradientStop, CodableColor, .color, Color, .effectColor, EffectCatalog (+20 more)

### Community 49 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 50 - "WindowEventTap"
Cohesion: 0.15
Nodes (19): AnyClass, NSObject, ObjectiveC.runtime, FoundElement, InstallReport, ResolvedTarget, Bool, CGRect (+11 more)

### Community 51 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 52 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 53 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 54 - "BackupManagerLogicTests"
Cohesion: 0.15
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 55 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 56 - "CanvasNotice"
Cohesion: 0.06
Nodes (26): Alignment, Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer (+18 more)

### Community 57 - "FloatingPieceOverlayView"
Cohesion: 0.11
Nodes (18): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+10 more)

### Community 58 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 59 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 60 - "VectorSample"
Cohesion: 0.14
Nodes (8): VectorSample, .point, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

### Community 61 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 62 - "BrushStamper"
Cohesion: 0.13
Nodes (15): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+7 more)

### Community 63 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 64 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 65 - "VectorEraserHybridLogicTests"
Cohesion: 0.18
Nodes (7): Bool, Double, Int, StaticString, UInt, VectorStroke, VectorEraserHybridLogicTests

### Community 66 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 67 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 68 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 69 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 70 - "LayerManifest"
Cohesion: 0.17
Nodes (18): Decoder, ValueFill, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode (+10 more)

### Community 71 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 72 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 73 - "MetalFillEngine"
Cohesion: 0.16
Nodes (17): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+9 more)

### Community 74 - "StrokeGestureRecognizer"
Cohesion: 0.13
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 75 - "DeformFactorization"
Cohesion: 0.12
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 76 - "MaskSource"
Cohesion: 0.15
Nodes (12): MaskSource, folder, .id, layer, Encoder, UUID, Bool, CanvasManager (+4 more)

### Community 77 - "OnionSkinLogicTests"
Cohesion: 0.13
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 78 - "ActionsMenu"
Cohesion: 0.09
Nodes (22): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, CanvasManager, Double (+14 more)

### Community 79 - "TimedSample"
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 80 - "LayerStackCell"
Cohesion: 0.10
Nodes (9): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, UIView, Void (+1 more)

### Community 81 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, layers, move (+9 more)

### Community 83 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 84 - "SwiftUI"
Cohesion: 0.11
Nodes (10): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+2 more)

### Community 85 - "Compositor.swift"
Cohesion: 0.16
Nodes (21): os, BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor (+13 more)

### Community 86 - "GuideStroke"
Cohesion: 0.13
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 87 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 88 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 89 - "LayerStackListView.Coordinator"
Cohesion: 0.13
Nodes (12): DispatchWorkItem, IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, CGRect, TimeInterval (+4 more)

### Community 90 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 91 - "RenderRequest"
Cohesion: 0.23
Nodes (12): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, Attempt, image (+4 more)

### Community 92 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 93 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 94 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 95 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 97 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 98 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 99 - "EffectPipelines"
Cohesion: 0.17
Nodes (13): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+5 more)

### Community 100 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 101 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 102 - ".setUpGestures"
Cohesion: 0.15
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 103 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 104 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 105 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 106 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 107 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 108 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 109 - "Known Issues"
Cohesion: 0.11
Nodes (18): A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), An interrupted stroke stubs, and no terminal callback runs (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16), Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21) (+10 more)

### Community 110 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 111 - ".coverage"
Cohesion: 0.29
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 112 - "MotionGroup"
Cohesion: 0.18
Nodes (8): GroupRegistration, RegistrationElement, RegistrationFrame, Layer, MotionGroup, CodableColor, Decoder, UUID

### Community 113 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 114 - "LayerRowModel"
Cohesion: 0.18
Nodes (10): String, UIColor, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, Double (+2 more)

### Community 115 - "Coordinator"
Cohesion: 0.20
Nodes (9): Coordinator, LayerStackListView, Context, Coordinator, UIPinchGestureRecognizer, Void, UITableView, UITableViewDiffableDataSource (+1 more)

### Community 116 - "Recording"
Cohesion: 0.15
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 117 - "StructureSnapshot"
Cohesion: 0.19
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 118 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 119 - "LayerStackRow"
Cohesion: 0.12
Nodes (15): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+7 more)

### Community 120 - "UUID"
Cohesion: 0.19
Nodes (6): Bool, CanvasManager, Int, Set, UIGestureRecognizer, UUID

### Community 121 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 122 - "CanvasTransformFreezeUITests"
Cohesion: 0.29
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 123 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 124 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 125 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 126 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 127 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 128 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 129 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 130 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 131 - "Kind"
Cohesion: 0.14
Nodes (14): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+6 more)

### Community 132 - "UndoHistory"
Cohesion: 0.23
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 133 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 134 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 135 - ".noteTransition"
Cohesion: 0.27
Nodes (5): Entry, ObjectIdentifier, Set, UIGestureRecognizer, UIView

### Community 136 - ".analyse"
Cohesion: 0.29
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 137 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 138 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 139 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 140 - "Hashable"
Cohesion: 0.18
Nodes (10): Hashable, CelLocation, Tool, eraser, fill, pen, pencil, Tab (+2 more)

### Community 141 - ".testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold"
Cohesion: 0.38
Nodes (6): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64, CGSize

### Community 142 - "VectorEraserMode"
Cohesion: 0.18
Nodes (11): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized (+3 more)

### Community 144 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 146 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 147 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 148 - "Usage Guide"
Cohesion: 0.22
Nodes (9): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide (+1 more)

### Community 149 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 150 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 151 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 152 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 153 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 154 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 155 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 156 - "Handoff — 2026-08-16"
Cohesion: 0.33
Nodes (6): Blocked on the owner, Branch state, Handoff — 2026-08-16, Process, learned expensively here, The one genuinely new capability: you can test on the owner's iPad, The two open bugs, with what is already known

### Community 157 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 158 - "Kind"
Cohesion: 0.33
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 159 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 160 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 161 - "ProjectVersionsView"
Cohesion: 0.47
Nodes (4): ProjectVersionsView, RecentlyDeletedView, .body, Void

### Community 162 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 163 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 165 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 166 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, Kind, line, oval, rectangle

### Community 167 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 169 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 170 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 171 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 173 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 174 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 175 - "TODO"
Cohesion: 0.50
Nodes (4): Done this pass, In flight, Queued, TODO

### Community 176 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 179 - "Kind"
Cohesion: 0.67
Nodes (3): Kind, folder, layer

## Knowledge Gaps
- **715 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+710 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `VectorCanvas`, `CanvasManager`, `Lattice`, `CGPoint`, `Coordinator`, `CompositorParityLogicTests`, `Coordinator`, `ARAPLogicTests`, `CanvasManager`, `AlphaMask`, `CanvasManager`, `EffectLayerLogicTests`, `UIKit`, `StrokeCanvasView`, `SandwichLogicTests`, `PerfBaselineTests`, `VectorEraserLogicTests`, `.apply`, `PaintUITestCase`, `ShapeOverlayView`, `.report`, `BrushEngineLogicTests`, `ProjectSaveLogicTests`, `AnimationTimeline`, `.launchIntoEditor`, `BrushBlendMode`, `.transparentFormat`, `.restLattice`, `StrokeGeometryLogicTests`, `RenderQuality`, `InterpolationRenderLogicTests`, `.rows`, `CanvasManager`, `WindowEventTap`, `.evaluate`, `RasterLayerTexture`, `InterpolationModelLogicTests`, `CanvasNotice`, `FloatingPieceOverlayView`, `ActionRecorder`, `VectorSample`, `BrushStamper`, `InterpolationRecipe`, `VectorEraserHybridLogicTests`, `StrokeSettingsPanel`, `GuideOverlayView`, `StrokeSpatialIndex`, `DeformFactorization`, `OnionSkinLogicTests`, `ActionsMenu`, `TimedSample`, `LayerStackCell`, `InterpolationGuideLogicTests`, `XCUIApplication`, `LayerStackListView.Coordinator`, `RenderRequest`, `CanvasManager`, `CurveEditor`, `.indices`, `InterpolationEngineDiagnosticsLogicTests`, `.manager`, `SandwichCompositingUITests`, `.arched`, `CodingKeys`, `InterpolateBar`, `LayerRowModel`, `Coordinator`, `CanvasManager`, `CanvasTransformFreezeUITests`, `SideToolbar`, `CGContextDabTarget`, `SpacingChart`, `.analyse`, `StrokeStabilizer`, `VectorEraserMode`, `TransformOverlaySupport.swift`, `JSONValue`?**
  _High betweenness centrality (0.315) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `VectorCanvas`, `CGContextDabTarget`, `ObjectTransformOverlayView`, `Lattice`, `Coordinator`, `.analyse`, `StrokeStabilizer`, `CGFloat`, `ARAPLogicTests`, `CanvasManager`, `Coordinator`, `CanvasManager`, `.rasterize`, `AlphaMask`, `UIKit`, `StrokeCanvasView`, `TransformOverlaySupport.swift`, `ColorPickerPanel`, `PerfBaselineTests`, `VectorEraserLogicTests`, `ShapeOverlayView`, `.report`, `BrushEngineLogicTests`, `layers`, `Gesture`, `Gesture`, `ProjectSaveLogicTests`, `AnimationTimeline`, `BrushBlendMode`, `.transparentFormat`, `.restLattice`, `StrokeGeometryLogicTests`, `InterpolationRenderLogicTests`, `CanvasManager`, `WindowEventTap`, `.evaluate`, `RasterLayerTexture`, `InterpolationModelLogicTests`, `FloatingPieceOverlayView`, `VectorSample`, `BrushStamper`, `InterpolationRecipe`, `VectorEraserHybridLogicTests`, `GuideOverlayView`, `StrokeSpatialIndex`, `DeformFactorization`, `TimedSample`, `InterpolationGuideLogicTests`, `LayerStackListView.Coordinator`, `CurveEditor`, `.indices`, `SelectionOverlayView`, `.setUpGestures`, `InterpolationEngineDiagnosticsLogicTests`, `.manager`, `.arched`, `MotionGroup`, `CanvasManager`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `task` connect `ContentView` to `CanvasNotice`, `bash`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._