# Graph Report - PaintApp-menuinterrupt  (2026-08-20)

## Corpus Check
- 224 files · ~670,522 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6600 nodes · 19929 edges · 216 communities (202 shown, 14 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1990 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `404d0858`
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
- VectorEraserHybridLogicTests
- CompositorParityLogicTests
- AlphaMask
- InterpolationGuideLogicTests
- HistoryActionLabel
- Coordinator
- InterpolationEngineDiagnosticsLogicTests
- EffectLayerLogicTests
- Identifiable
- CodingKeys
- Effect
- SandwichLogicTests
- PerfBaselineTests
- LayerTreeCharacterizationTests
- .drawLine
- StrokeGeometryLogicTests
- StrokeCanvasView
- TextFrame
- ShapeOverlayView
- PointCloudIndex
- PaintUITestCase
- CompositorMetalEngine
- AnimationTimeline
- UIKit
- CodingKeys
- .transparentFormat
- EffectMultiPassLogicTests
- .apply
- CaseIterable
- XCTestCase
- BrushEngineLogicTests
- CanvasManager
- SelectionOverlayView
- CodingKeys
- CGFloat
- .launchIntoEditor
- CanvasManager
- ProjectSaveLogicTests
- RenderTreeCharacterizationTests
- View
- CanvasManager
- ARAPLogicTests
- StrokeGestureRecognizer
- SaveSnapshot
- DeformFactorization
- layers
- MaskSource
- .rows
- VectorCanvasDataLogicTests
- RenderRequest
- InterpolationRenderLogicTests
- Codable
- VectorEraserMode
- InterpolationModelLogicTests
- agent
- ActionRecorder
- EyedropperLogicTests
- PlaybackBoundsCharacterizationTests
- Binding
- Composite.metal
- SwiftUI
- GuideOverlayView
- InterpolationRecipe
- LassoFillLogicTests
- BackupManagerLogicTests
- .evaluate
- FontFace
- BlendMode
- LayerStackCell
- EffectParityLogicTests
- VectorSample
- Known Issues
- FloatingPieceOverlayView
- EffectPipelines
- .coverage
- DrawingView
- BrushStamper
- RasterLayerTexture
- WindowEventTap
- LayerStackListView.Coordinator
- CanvasNotice
- ContentView
- TextOverlayView
- ActivePanel
- StrokeSpatialIndex
- ShapeDetector
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
- OnionSkinSettingsSource
- Gesture
- Layer Compositing
- read
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- .compositeSize
- InterpolationRefusal
- StructureSnapshot
- ShapeHoldClock
- .makeUIView
- SelectPanel
- LayerRowModel
- CanvasTransformFreezeUITests
- .rasterize
- EffectParams
- FillGestureRestartLogicTests
- SandwichCompositingUITests
- BlockDragCharacterizationTests
- Typography
- 1. The decisions
- PerfMonitor
- .setUpGestures
- String
- CanvasManager
- InterpolateBar
- FillBoundaryLogicTests
- PaintSoftware - iPad Drawing and Animation App
- CanvasPresentation
- TextBakeCharacterizationTests
- Coordinator
- Recording
- Layer
- StrokeStabilizer
- CanvasSizePickerView
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CodingKey
- bash
- ActionsMenu
- ObjectTransformOverlayView
- CGContextDabTarget
- Kind
- CodingKeys
- UndoHistory
- CanvasHostView
- Performance
- CanvasPresentationModifier
- CLAUDE.md
- Kind
- GuideStroke
- GalleryView
- MenuInterruptionUITests
- 4. Future upgrades — the deferred list
- Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit)
- ToolPanelsUITests
- .sampledColor
- Every dismissible presentation, and whether a stroke under it breaks
- Multi-Session Protocol
- BrushSettingsPanel
- Lasso Fill — Specification
- .row
- ColorPickerPanel
- RenderNode
- command
- JSONValue
- .group
- RecordingWriter
- TimedSample
- Foundation
- FontResolveLogicTests
- .indices
- CutOutcome
- TextRecipeCodableLogicTests
- parallel_test.sh
- Performance baseline
- TODO
- .manager
- ManifestSkeleton
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- Kind
- Corner
- .waitForDisappearance
- TextSettingsPanel
- .arched
- presentation-census.sh
- LayerStackRow
- TextLayout
- ViewPreset
- SpacingChart
- GuidePath
- .textureBudgetBytes
- CodingKeys
- .handleShouldReceive
- MoveTransformBottomBar
- PaintApp
- main.swift
- CodingKeys
- Atomic
- Edge
- .render
- LayerTransform

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 662 edges
2. `CGFloat` - 513 edges
3. `CanvasManager` - 157 edges
4. `Effect` - 149 edges
5. `VectorCanvas` - 125 edges
6. `layers` - 121 edges
7. `VectorSample` - 117 edges
8. `Coordinator` - 111 edges
9. `ShapeGeometry` - 109 edges
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

## Communities (216 total, 14 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (17): cels, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor, Int (+9 more)

### Community 1 - "CGPoint"
Cohesion: 0.05
Nodes (25): CGPoint, .length, Int, FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath (+17 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (57): Void, CanvasManager, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+49 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (8): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 4 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+14 more)

### Community 5 - "CanvasManager"
Cohesion: 0.06
Nodes (30): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+22 more)

### Community 6 - "VectorCanvas"
Cohesion: 0.04
Nodes (70): CodableColor, .uiColor, image, kind, DabLattice, .range, DecodeReport, .droppedCount (+62 more)

### Community 7 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 8 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 9 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+41 more)

### Community 10 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (16): CanvasFixture, CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager (+8 more)

### Community 11 - "AlphaMask"
Cohesion: 0.09
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 13 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (73): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+65 more)

### Community 14 - "Coordinator"
Cohesion: 0.06
Nodes (28): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, Coordinator, .canvasContentScale, .isLassoFilling (+20 more)

### Community 15 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 16 - "EffectLayerLogicTests"
Cohesion: 0.11
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 17 - "Identifiable"
Cohesion: 0.14
Nodes (18): Identifiable, Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+10 more)

### Community 18 - "CodingKeys"
Cohesion: 0.05
Nodes (45): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+37 more)

### Community 19 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, Curves, Effect, .displayName (+24 more)

### Community 20 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 21 - "PerfBaselineTests"
Cohesion: 0.12
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 22 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (7): Layer, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 23 - ".drawLine"
Cohesion: 0.11
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 24 - "StrokeGeometryLogicTests"
Cohesion: 0.05
Nodes (15): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+7 more)

### Community 25 - "StrokeCanvasView"
Cohesion: 0.07
Nodes (32): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+24 more)

### Community 26 - "TextFrame"
Cohesion: 0.09
Nodes (27): Int, .descriptor, corners, Corner, bottomLeft, bottomRight, topLeft, topRight (+19 more)

### Community 27 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 28 - "PointCloudIndex"
Cohesion: 0.10
Nodes (19): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+11 more)

### Community 29 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests (+3 more)

### Community 30 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (31): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+23 more)

### Community 31 - "AnimationTimeline"
Cohesion: 0.05
Nodes (38): Content, leaf, node, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+30 more)

### Community 32 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, simd, UIKit, XCTest

### Community 33 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, brush, color, composite, elements, fill, fills, id (+10 more)

### Community 34 - ".transparentFormat"
Cohesion: 0.10
Nodes (24): Hashable, IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool (+16 more)

### Community 35 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 36 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 37 - "CaseIterable"
Cohesion: 0.09
Nodes (22): CaseIterable, Kind, line, oval, rectangle, Neighbourhood, drawings, frames (+14 more)

### Community 38 - "XCTestCase"
Cohesion: 0.11
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 39 - "BrushEngineLogicTests"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 40 - "CanvasManager"
Cohesion: 0.07
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 41 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 42 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 43 - "CGFloat"
Cohesion: 0.07
Nodes (15): Brush, CGFloat, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser (+7 more)

### Community 44 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 45 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 46 - "ProjectSaveLogicTests"
Cohesion: 0.12
Nodes (12): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase, Set, StaticString (+4 more)

### Community 47 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, String, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 48 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 49 - "CanvasManager"
Cohesion: 0.10
Nodes (21): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+13 more)

### Community 50 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (9): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, StaticString, String (+1 more)

### Community 51 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 52 - "SaveSnapshot"
Cohesion: 0.12
Nodes (22): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+14 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 54 - "layers"
Cohesion: 0.10
Nodes (19): .activeContainerID, .activeLayerIsVector, .activeLayerKind, .newLayerPlacement, CanvasManager, Bool, CGSize, UIImage (+11 more)

### Community 55 - "MaskSource"
Cohesion: 0.07
Nodes (34): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Arity (+26 more)

### Community 56 - ".rows"
Cohesion: 0.11
Nodes (27): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+19 more)

### Community 57 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 58 - "RenderRequest"
Cohesion: 0.10
Nodes (27): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+19 more)

### Community 59 - "InterpolationRenderLogicTests"
Cohesion: 0.19
Nodes (8): ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID, VectorStroke

### Community 60 - "Codable"
Cohesion: 0.09
Nodes (31): Codable, Decoder, ValueFill, CompositorRole, node, Decoder, Encoder, K (+23 more)

### Community 61 - "VectorEraserMode"
Cohesion: 0.07
Nodes (24): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+16 more)

### Community 62 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

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
Cohesion: 0.07
Nodes (8): CanvasPresentationLogicTests, Bool, String, URL, PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "Binding"
Cohesion: 0.09
Nodes (29): Accessory, KeyPath, BrushShape, custom, .displayName, hardRound, .id, pen (+21 more)

### Community 68 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 69 - "SwiftUI"
Cohesion: 0.13
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 70 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 71 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 72 - "LassoFillLogicTests"
Cohesion: 0.06
Nodes (32): MTLBuffer, MTLCommandBuffer, LassoFillMask, Float, Int, SIMD4, UInt8, FillParams (+24 more)

### Community 73 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 74 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 75 - "FontFace"
Cohesion: 0.11
Nodes (19): CoreText, FontFace, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+11 more)

### Community 76 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 77 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+4 more)

### Community 78 - "EffectParityLogicTests"
Cohesion: 0.17
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 79 - "VectorSample"
Cohesion: 0.10
Nodes (10): VectorSample, StrokeSampleGate, Bool, VectorStroke, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor (+2 more)

### Community 80 - "Known Issues"
Cohesion: 0.07
Nodes (29): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16) (+21 more)

### Community 81 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 82 - "EffectPipelines"
Cohesion: 0.17
Nodes (13): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+5 more)

### Community 83 - ".coverage"
Cohesion: 0.31
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 84 - "DrawingView"
Cohesion: 0.08
Nodes (21): Alignment, center, .displayName, .id, justified, left, right, ActionRecorderIndicator (+13 more)

### Community 85 - "BrushStamper"
Cohesion: 0.13
Nodes (13): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+5 more)

### Community 86 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 87 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 88 - "LayerStackListView.Coordinator"
Cohesion: 0.18
Nodes (9): IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, TimeInterval, UIGestureRecognizerDelegate, UISwipeActionsConfiguration (+1 more)

### Community 89 - "CanvasNotice"
Cohesion: 0.07
Nodes (18): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, Kind, hiddenLayer (+10 more)

### Community 90 - "ContentView"
Cohesion: 0.13
Nodes (12): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+4 more)

### Community 91 - "TextOverlayView"
Cohesion: 0.10
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 92 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 93 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 94 - "ShapeDetector"
Cohesion: 0.20
Nodes (5): Void, ClosedFit, ShapeDetector, Bool, CGRect

### Community 95 - "OnionSkinSettings"
Cohesion: 0.15
Nodes (12): .opacitySliders, OnionSkinOpacityRamp, OnionSkinSettings, Side, .id, next, .step, Bool (+4 more)

### Community 96 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 97 - ".image"
Cohesion: 0.14
Nodes (13): NSObjectProtocol, InterpolationReferenceOnionSkinSource, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, OnionSkinSource, CanvasManager (+5 more)

### Community 98 - "OnionSkinPanel"
Cohesion: 0.10
Nodes (22): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+14 more)

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
Nodes (4): CelSpan, .end, OnionSkinPlanner, OnionSkinLogicTests

### Community 105 - "OnionSkinSettingsSource"
Cohesion: 0.14
Nodes (11): Colouring, .id, originalColors, tinted, .title, OnionSkinSettingsSource, Bool, CanvasManager (+3 more)

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
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 112 - ".compositeSize"
Cohesion: 0.25
Nodes (4): OnionSkinBudget, CGSize, Int, Int

### Community 113 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 114 - "StructureSnapshot"
Cohesion: 0.18
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 115 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 116 - ".makeUIView"
Cohesion: 0.14
Nodes (8): AppliedTool, CanvasView, Color, Context, Coordinator, Double, LayerTransform, UIColor

### Community 117 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 118 - "LayerRowModel"
Cohesion: 0.18
Nodes (12): LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, CanvasManager, Double, Int (+4 more)

### Community 119 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 121 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 122 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 123 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 124 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 125 - "Typography"
Cohesion: 0.19
Nodes (8): UIFont, ClosedRange, Typography, .clamped, Int, String, UIFont, TextLayoutLogicTests

### Community 126 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 127 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 128 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 129 - "String"
Cohesion: 0.10
Nodes (23): Error, Failure, unknownKind, Kind, folder, layer, CodingKeys, displayName (+15 more)

### Community 130 - "CanvasManager"
Cohesion: 0.09
Nodes (16): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+8 more)

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
Cohesion: 0.12
Nodes (14): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+6 more)

### Community 135 - "TextBakeCharacterizationTests"
Cohesion: 0.21
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 136 - "Coordinator"
Cohesion: 0.15
Nodes (13): DispatchWorkItem, Coordinator, LayerStackListView, Context, Coordinator, UILongPressGestureRecognizer, UIPinchGestureRecognizer, Void (+5 more)

### Community 137 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 138 - "Layer"
Cohesion: 0.17
Nodes (11): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+3 more)

### Community 139 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 140 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 141 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 142 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 143 - "CodingKey"
Cohesion: 0.07
Nodes (29): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+21 more)

### Community 144 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 145 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 146 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (23): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, FloatingTransform (+15 more)

### Community 147 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 148 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 149 - "CodingKeys"
Cohesion: 0.08
Nodes (24): CodingKeys, alignment, autoSize, color, faceName, familyName, font, frame (+16 more)

### Community 150 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 151 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 152 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 153 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (6): CanvasPresentationModifier, Bool, CanvasManager, Void, PresentedContent, ViewModifier

### Community 155 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 156 - "GuideStroke"
Cohesion: 0.24
Nodes (5): Layer, GuideStroke, KeyframeInterval, Bool, UUID

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

### Community 161 - "ToolPanelsUITests"
Cohesion: 0.18
Nodes (4): SelectionPencilOnlyUITests, Bool, XCUIApplication, ToolPanelsUITests

### Community 162 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 163 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.20
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 164 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 165 - "BrushSettingsPanel"
Cohesion: 0.10
Nodes (20): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+12 more)

### Community 166 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 167 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 168 - "ColorPickerPanel"
Cohesion: 0.13
Nodes (17): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+9 more)

### Community 169 - "RenderNode"
Cohesion: 0.20
Nodes (14): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, RenderNode, .enclosesABlend (+6 more)

### Community 170 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 171 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 172 - ".group"
Cohesion: 0.20
Nodes (5): Group, MotionGrouping, Options, Int, Set

### Community 174 - "TimedSample"
Cohesion: 0.12
Nodes (9): GuideRole, both, timing, trajectory, Decoder, TimeInterval, TimedSample, .point (+1 more)

### Community 175 - "Foundation"
Cohesion: 0.09
Nodes (11): Foundation, os, Notification.Name, CodableColor, .color, Color, .codable, CodableColor (+3 more)

### Community 176 - "FontResolveLogicTests"
Cohesion: 0.21
Nodes (5): FontResolveLogicTests, StubFontProvider, Bool, String, UIFont

### Community 178 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 179 - "TextRecipeCodableLogicTests"
Cohesion: 0.15
Nodes (5): StaticString, String, T, UInt, TextRecipeCodableLogicTests

### Community 180 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 181 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 182 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 183 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 184 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 185 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 194 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 195 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 196 - ".waitForDisappearance"
Cohesion: 0.40
Nodes (3): Bool, TimeInterval, XCUIElement

### Community 197 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (13): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+5 more)

### Community 198 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 200 - "LayerStackRow"
Cohesion: 0.12
Nodes (15): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+7 more)

### Community 201 - "TextLayout"
Cohesion: 0.23
Nodes (10): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGSize (+2 more)

### Community 202 - "ViewPreset"
Cohesion: 0.19
Nodes (8): CanvasManager, .activeViewName, Int, String, Bool, String, UUID, ViewPreset

### Community 203 - "SpacingChart"
Cohesion: 0.19
Nodes (3): SpacingChart, .curve, .draggable

### Community 204 - "GuidePath"
Cohesion: 0.26
Nodes (6): GuidePath, .end, .start, CGVector, TimeInterval, points

### Community 205 - ".textureBudgetBytes"
Cohesion: 0.42
Nodes (5): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64

### Community 206 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKeys, groups, guideIDs, localEdits, mode, references, spacing, t

### Community 207 - ".handleShouldReceive"
Cohesion: 0.36
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 208 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 209 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 210 - "main.swift"
Cohesion: 0.33
Nodes (6): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int

### Community 211 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, id, invert, isEnabled, kind, sources

### Community 212 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 213 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 214 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

## Knowledge Gaps
- **974 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+969 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `CGPoint`, `CanvasManager`, `CanvasManager`, `VectorCanvas`, `Lattice`, `Coordinator`, `VectorEraserHybridLogicTests`, `CompositorParityLogicTests`, `AlphaMask`, `InterpolationGuideLogicTests`, `Coordinator`, `InterpolationEngineDiagnosticsLogicTests`, `EffectLayerLogicTests`, `SandwichLogicTests`, `PerfBaselineTests`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `TextFrame`, `ShapeOverlayView`, `PointCloudIndex`, `PaintUITestCase`, `AnimationTimeline`, `.transparentFormat`, `.apply`, `CaseIterable`, `BrushEngineLogicTests`, `CanvasManager`, `.launchIntoEditor`, `ProjectSaveLogicTests`, `CanvasManager`, `ARAPLogicTests`, `DeformFactorization`, `layers`, `.rows`, `VectorCanvasDataLogicTests`, `RenderRequest`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `ActionRecorder`, `Binding`, `GuideOverlayView`, `InterpolationRecipe`, `LassoFillLogicTests`, `.evaluate`, `FontFace`, `LayerStackCell`, `VectorSample`, `DrawingView`, `BrushStamper`, `RasterLayerTexture`, `WindowEventTap`, `LayerStackListView.Coordinator`, `TextOverlayView`, `StrokeSpatialIndex`, `ShapeDetector`, `OnionSkinSettings`, `XCUIApplication`, `.image`, `.sample`, `PinchMergeGateLogicTests`, `OnionSkinSettingsSource`, `CanvasManager`, `CurveEditor`, `.compositeSize`, `.makeUIView`, `CanvasTransformFreezeUITests`, `SandwichCompositingUITests`, `Typography`, `CanvasManager`, `InterpolateBar`, `TextBakeCharacterizationTests`, `Coordinator`, `StrokeStabilizer`, `SideToolbar`, `ActionsMenu`, `ObjectTransformOverlayView`, `CGContextDabTarget`, `Kind`, `BrushSettingsPanel`, `RenderNode`, `JSONValue`, `.group`, `TimedSample`, `FontResolveLogicTests`, `.indices`, `.manager`, `TextSettingsPanel`, `.arched`, `TextLayout`, `SpacingChart`, `GuidePath`, `main.swift`, `LayerTransform`?**
  _High betweenness centrality (0.285) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `.setUpGestures`, `cels`, `CanvasManager`, `CanvasManager`, `CanvasManager`, `VectorCanvas`, `Lattice`, `Coordinator`, `VectorEraserHybridLogicTests`, `CompositorParityLogicTests`, `StrokeStabilizer`, `InterpolationGuideLogicTests`, `AlphaMask`, `Coordinator`, `InterpolationEngineDiagnosticsLogicTests`, `TextBakeCharacterizationTests`, `ObjectTransformOverlayView`, `CGContextDabTarget`, `PerfBaselineTests`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `TextFrame`, `ShapeOverlayView`, `PointCloudIndex`, `AnimationTimeline`, `.sampledColor`, `.transparentFormat`, `BrushEngineLogicTests`, `CanvasManager`, `ColorPickerPanel`, `SelectionOverlayView`, `CGFloat`, `.group`, `TimedSample`, `Foundation`, `ProjectSaveLogicTests`, `.indices`, `ARAPLogicTests`, `CanvasManager`, `TextRecipeCodableLogicTests`, `DeformFactorization`, `layers`, `.manager`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `EyedropperLogicTests`, `GuideOverlayView`, `.arched`, `InterpolationRecipe`, `TextLayout`, `.evaluate`, `LassoFillLogicTests`, `GuidePath`, `VectorSample`, `FloatingPieceOverlayView`, `main.swift`, `BrushStamper`, `RasterLayerTexture`, `WindowEventTap`, `LayerTransform`, `LayerStackListView.Coordinator`, `TextOverlayView`, `StrokeSpatialIndex`, `ShapeDetector`, `.sample`, `CurveEditor`, `.makeUIView`, `.rasterize`, `FillGestureRestartLogicTests`, `Typography`?**
  _High betweenness centrality (0.163) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CGPoint`, `CanvasManager`, `String`, `CanvasPresentation`, `UndoHistory`, `TextFrame`, `GuideStroke`, `CanvasManager`, `SelectionOverlayView`, `CGFloat`, `TimedSample`, `CanvasManager`, `layers`, `MaskSource`, `RenderRequest`, `Codable`, `VectorEraserMode`, `SwiftUI`, `InterpolationRecipe`, `LassoFillLogicTests`, `ViewPreset`, `FontFace`, `SpacingChart`, `VectorSample`, `RasterLayerTexture`, `CanvasNotice`, `OnionSkinSettings`, `StructureSnapshot`, `PerfMonitor`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 76 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 76 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 13 INFERRED edges - model-reasoned connections that need verification._