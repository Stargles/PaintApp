# Graph Report - PaintApp-closeout  (2026-08-27)

## Corpus Check
- 258 files · ~929,556 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 8009 nodes · 24758 edges · 226 communities (215 shown, 11 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2444 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `90f57912`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CGPoint
- cels
- CanvasManager
- ObjectTransformLogicTests
- Homography
- .manager
- Coordinator
- LassoFillLogicTests
- CanvasManager
- ProjectBackupManager
- InterpolationGuideLogicTests
- .solidImage
- Lattice
- CGFloat
- ARAPLogicTests
- AlphaMask
- ProjectSaveLogicTests
- UIKit
- String
- InterpolationRecipe
- .refreshUndoRedoState
- PerfBaselineTests
- HistoryActionLabel
- VectorCanvas
- LassoMoveLogicTests
- SizePreviewRequest
- StrokeCanvasView
- TextTransformLogicTests
- EffectLayerLogicTests
- FontDescriptor
- Codable
- ProjectManifest
- SandwichLogicTests
- VectorEraserLogicTests
- DeformFactorization
- StrokeGestureRecognizer
- ColorPickerPanel
- CompositorMetalEngine
- PaintUITestCase
- .report
- AnimationTimeline
- StrokeGeometryLogicTests
- ShapeOverlayView
- LayerTreeCharacterizationTests
- SelectionOverlayView
- BrushEngineLogicTests
- MaskParityLogicTests
- XCUIApplication
- CanvasManager
- ProjectStore
- VectorSample
- EffectMultiPassLogicTests
- Effect
- CanvasManager
- Binding
- .apply
- TextOverlayView
- LayerRowModel
- DrawingView
- .transparentFormat
- .launchIntoEditor
- Typography
- CanvasManager
- .rgbaBytes
- XCTestCase
- Fill.metal
- TextFrame
- View
- RenderRequest
- RasterLayerTexture
- TextBakeCharacterizationTests
- .rows
- Brush
- VectorEraserHybridLogicTests
- GuideStroke
- LayerStackCell
- .evaluate
- CodingKey
- InterpolationRenderLogicTests
- .activeCelIndex
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- TextRecipe
- FloatingPieceOverlayView
- GalleryOpenState
- BrushStamper
- Known Issues
- ActionRecorder
- RenderNode
- UndoHistory
- GuideOverlayView
- PlaybackBoundsCharacterizationTests
- SaveDamageGateLogicTests
- Composite.metal
- PinchMergeGateLogicTests
- TextHitTestLogicTests
- StrokeGeometry
- BlendMode
- StrokeSpatialIndex
- MetalFillSession
- OnionSkinSettings
- TextTransformOverlayView
- EffectParityLogicTests
- CaseIterable
- EyedropperLogicTests
- Coordinator
- SwiftUI
- Layer Compositing
- .compositeSize
- agent
- CanvasTouchOwnerLogicTests
- CodingKeys
- ProjectLoadDamage
- StrokeSampleGateLogicTests
- CanvasTouchOwner
- CanvasTransformFreezeUITests
- bash
- VectorTextPersistenceLogicTests
- ActivePanel
- SelectionMode
- CanvasTouchInputs
- .setUpGestures
- TimelineLayoutKeyLogicTests
- CanvasNotice
- .affine
- MoveTransformBottomBar
- TimelineRowView
- XCUIApplication
- read
- SpacingChart
- CodingKeys
- OnionSkinPanel
- FillGestureRestartLogicTests
- WindowEventTap
- 2. The decisions
- VectorPreviewPlanLogicTests
- 1. The decisions
- EffectPipelines
- Compositor.swift
- GuideRow
- TextRecipeCodableLogicTests
- Gesture
- CanvasManager
- CurveEditor
- Int
- Handle
- CodingKeys
- OnionSkinSource.swift
- OnionSkinLogicTests
- The layer transform — keep it, or bake it into the geometry?
- EffectParams
- .previewed
- Kind
- LayerStackListView.Coordinator
- CGRect
- SandwichCompositingUITests
- Recording
- .coverage
- ShapeHoldClock
- Alignment
- TextSettingsPanel
- BlockDragCharacterizationTests
- PaintSoftware - iPad Drawing and Animation App
- 1. The decisions
- PerfMonitor
- StructureSnapshot
- InterpolateBar
- .performDrag
- SideToolbar
- CelBlockView
- CanvasPresentationLogicTests
- .draw
- ViewPreset
- CanvasSizePickerView
- MenuInterruptionUITests
- ToolLogicTests
- CLAUDE.md
- ActionsMenu
- TimelineLayoutKey
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CGContextDabTarget
- .sample
- CanvasHostView
- Performance
- Lasso Fill — Specification
- Every dismissible presentation, and whether a stroke under it breaks
- String
- StrokeStabilizer
- .rasterize
- TODO
- 4. Future upgrades — the deferred list
- CanvasActiveLayer
- CanvasPresentationModifier
- Multi-Session Protocol
- WarpParams
- .sampledColor
- 1. What will actually hurt, ranked
- BrushBlendMode
- .textureBudgetBytes
- CutOutcome
- Kind
- .row
- TransformOverlaySupport.swift
- Handoff — 2026-08-27 (session 70)
- ProjectStore.swift
- JSONValue
- RecordingWriter
- CompositeProbe
- Atomic
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- parallel_test.sh
- Performance baseline
- AppVersion
- AppliedTool
- SandwichPresentation
- Kind
- Colouring
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- presentation-census.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 953 edges
2. `CGFloat` - 674 edges
3. `VectorCanvas` - 219 edges
4. `CanvasManager` - 176 edges
5. `Effect` - 150 edges
6. `VectorSample` - 147 edges
7. `Coordinator` - 130 edges
8. `ShapeGeometry` - 121 edges
9. `CanvasManager` - 100 edges
10. `Lattice` - 98 edges

## Surprising Connections (you probably didn't know these)
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `.sourceScale` --calls--> `CGFloat`  [EXTRACTED]
  PaintSoftwareUITests/WarpAgreementCharacterizationTests.swift → PaintSoftware/Engine/Deform/Lattice.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `.quads` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/WarpAgreementCharacterizationTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift

## Import Cycles
- None detected.

## Communities (226 total, 11 thin omitted)

### Community 0 - "CGPoint"
Cohesion: 0.04
Nodes (35): CGPoint, .length, Int, Corner, bottomLeft, bottomRight, topLeft, topRight (+27 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (65): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+57 more)

### Community 3 - "ObjectTransformLogicTests"
Cohesion: 0.04
Nodes (45): Handle, Handle, bottomLeft, bottomRight, .isCorner, .isDrawn, rotation, topLeft (+37 more)

### Community 4 - "Homography"
Cohesion: 0.04
Nodes (51): CATransform3D, Homography, .catransform3D, .determinant, .inverse, Bool, CGAffineTransform, CGRect (+43 more)

### Community 5 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, SelectionPersistenceLogicTests, CGPath, Bool (+2 more)

### Community 6 - "Coordinator"
Cohesion: 0.05
Nodes (36): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, ActiveObjectTransform, CanvasView, Coordinator (+28 more)

### Community 7 - "LassoFillLogicTests"
Cohesion: 0.07
Nodes (20): LassoFillMask, Float, Int, SIMD4, UInt8, mask, LassoFillLogicTests, .loopAroundEverything (+12 more)

### Community 8 - "CanvasManager"
Cohesion: 0.05
Nodes (37): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+29 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (35): DateFormatter, Decodable, Cel, Layer, ManifestSkeleton, Notification.Name, ProjectBackup, .id (+27 more)

### Community 10 - "InterpolationGuideLogicTests"
Cohesion: 0.07
Nodes (12): GuideHandles, GuideSet, .isEmpty, Bool, TimedSample, .point, InterpolationGuideLogicTests, CanvasManager (+4 more)

### Community 11 - ".solidImage"
Cohesion: 0.07
Nodes (16): CanvasFixture, CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager (+8 more)

### Community 12 - "Lattice"
Cohesion: 0.06
Nodes (28): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+20 more)

### Community 13 - "CGFloat"
Cohesion: 0.05
Nodes (26): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, ClosedFit (+18 more)

### Community 14 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (26): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+18 more)

### Community 15 - "AlphaMask"
Cohesion: 0.04
Nodes (48): Hashable, AlphaMask, .antialiasHalfWidth, .isActive, .threshold, CodingKeys, id, invert (+40 more)

### Community 16 - "ProjectSaveLogicTests"
Cohesion: 0.08
Nodes (20): MainActor, Void, Bool, ScenePhase, VectorStroke, ProjectSaveLogicTests, Any, Bool (+12 more)

### Community 17 - "UIKit"
Cohesion: 0.05
Nodes (8): CoreGraphics, CoreText, Darwin, Foundation, Metal, simd, UIKit, XCTest

### Community 18 - "String"
Cohesion: 0.04
Nodes (64): Error, Identifiable, CodableColor, .uiColor, DabLattice, .range, DecodeReport, .droppedCount (+56 more)

### Community 19 - "InterpolationRecipe"
Cohesion: 0.06
Nodes (30): CelRef, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference (+22 more)

### Community 20 - ".refreshUndoRedoState"
Cohesion: 0.06
Nodes (29): CanvasManager, Bool, CGAffineTransform, CGRect, CGSize, Int, LayerTransform, Set (+21 more)

### Community 21 - "PerfBaselineTests"
Cohesion: 0.11
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 22 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 23 - "VectorCanvas"
Cohesion: 0.07
Nodes (34): CGPathFillRule, VectorTextElement, image, Kind, fill, image, stroke, text (+26 more)

### Community 24 - "LassoMoveLogicTests"
Cohesion: 0.17
Nodes (9): .elements, LassoMoveLogicTests, CanvasManager, CGImage, CGPath, CGRect, CodableColor, Int (+1 more)

### Community 25 - "SizePreviewRequest"
Cohesion: 0.05
Nodes (37): Anchor, .sizePreview, .uploadableLeafCount, CanvasDisplayScale, SizePreviewGeometry, .isClipped, .stampDiameter, .windowSide (+29 more)

### Community 26 - "StrokeCanvasView"
Cohesion: 0.07
Nodes (30): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+22 more)

### Community 27 - "TextTransformLogicTests"
Cohesion: 0.08
Nodes (10): .clamped, Bool, CanvasManager, CGRect, CGSize, Int, StaticString, String (+2 more)

### Community 28 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 29 - "FontDescriptor"
Cohesion: 0.08
Nodes (25): FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+17 more)

### Community 30 - "Codable"
Cohesion: 0.05
Nodes (47): Codable, Kind, folder, layer, CodingKeys, amount, angleDegrees, brightness (+39 more)

### Community 31 - "ProjectManifest"
Cohesion: 0.06
Nodes (41): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+33 more)

### Community 32 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 33 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 34 - "DeformFactorization"
Cohesion: 0.07
Nodes (19): Accelerate, ARAPInterpolation, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization (+11 more)

### Community 35 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 36 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+29 more)

### Community 37 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (33): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+25 more)

### Community 38 - "PaintUITestCase"
Cohesion: 0.12
Nodes (13): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, HistoryNoticeUITests, PaintUITestCase, Bool, CGVector, Double (+5 more)

### Community 39 - ".report"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+25 more)

### Community 40 - "AnimationTimeline"
Cohesion: 0.05
Nodes (44): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+36 more)

### Community 41 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (7): MembershipRun, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 42 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (39): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+31 more)

### Community 43 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 44 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 45 - "BrushEngineLogicTests"
Cohesion: 0.11
Nodes (13): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+5 more)

### Community 46 - "MaskParityLogicTests"
Cohesion: 0.09
Nodes (6): MaskParityLogicTests, .side, Bool, CanvasManager, CGImage, Int

### Community 47 - "XCUIApplication"
Cohesion: 0.12
Nodes (7): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, Int, String, XCUIApplication, UndoAndLayerHistoryUITests

### Community 48 - "CanvasManager"
Cohesion: 0.07
Nodes (29): CanvasManager, .canResetFloating, .freeformUnavailableReason, .isAnyPieceFloating, .mirrorUnavailableReason, .vectorFloatIsFreeform, FixedAngleRotation, FloatingPiece (+21 more)

### Community 49 - "ProjectStore"
Cohesion: 0.09
Nodes (37): CFAbsoluteTime, CelContent, DecodedCel, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare, ProjectStore (+29 more)

### Community 50 - "VectorSample"
Cohesion: 0.12
Nodes (12): VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser (+4 more)

### Community 51 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 52 - "Effect"
Cohesion: 0.10
Nodes (35): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+27 more)

### Community 53 - "CanvasManager"
Cohesion: 0.10
Nodes (22): CanvasManager, .fillEdgeOverlap, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel (+14 more)

### Community 54 - "Binding"
Cohesion: 0.07
Nodes (39): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+31 more)

### Community 55 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 56 - "TextOverlayView"
Cohesion: 0.08
Nodes (24): RenderKey, Bool, CGPath, CGRect, CGSize, Float, NSCoder, Set (+16 more)

### Community 57 - "LayerRowModel"
Cohesion: 0.10
Nodes (26): DispatchWorkItem, IndexPath, .body, Coordinator, LayerRowModel, .folderID, .isFolder, .maskSource (+18 more)

### Community 58 - "DrawingView"
Cohesion: 0.06
Nodes (31): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+23 more)

### Community 59 - ".transparentFormat"
Cohesion: 0.11
Nodes (21): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+13 more)

### Community 60 - ".launchIntoEditor"
Cohesion: 0.12
Nodes (10): EraserAndPersistenceUITests, SelectionAndMoveUITests, Double, Int, StaticString, UInt, XCUIApplication, XCUIElement (+2 more)

### Community 61 - "Typography"
Cohesion: 0.15
Nodes (10): ClosedRange, Typography, CGRect, CGSize, ClosedRange, Int, String, UIFont (+2 more)

### Community 62 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 63 - ".rgbaBytes"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 64 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 65 - "Fill.metal"
Cohesion: 0.18
Nodes (40): device, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams, edgeInset (+32 more)

### Community 66 - "TextFrame"
Cohesion: 0.12
Nodes (15): Basis, Bool, CGAffineTransform, CGRect, CGSize, CGVector, UUID, TextFrame (+7 more)

### Community 67 - "View"
Cohesion: 0.14
Nodes (29): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+21 more)

### Community 68 - "RenderRequest"
Cohesion: 0.10
Nodes (27): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+19 more)

### Community 69 - "RasterLayerTexture"
Cohesion: 0.12
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 70 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 71 - ".rows"
Cohesion: 0.11
Nodes (28): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+20 more)

### Community 72 - "Brush"
Cohesion: 0.09
Nodes (18): Brush, BrushDynamics, BrushGrain, BrushShape, custom, .displayName, hardRound, .id (+10 more)

### Community 73 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 74 - "GuideStroke"
Cohesion: 0.07
Nodes (28): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+20 more)

### Community 75 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+4 more)

### Community 76 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+13 more)

### Community 77 - "CodingKey"
Cohesion: 0.06
Nodes (36): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+28 more)

### Community 78 - "InterpolationRenderLogicTests"
Cohesion: 0.18
Nodes (9): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID (+1 more)

### Community 79 - ".activeCelIndex"
Cohesion: 0.12
Nodes (16): .activeLayerIsVector, .interpolationTarget, LayerTransform, CanvasManager, Bool, Int, Cel, .endFrame (+8 more)

### Community 80 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 81 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 82 - "TextRecipe"
Cohesion: 0.15
Nodes (18): CTFrame, CTFramesetter, NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool (+10 more)

### Community 83 - "FloatingPieceOverlayView"
Cohesion: 0.11
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 84 - "GalleryOpenState"
Cohesion: 0.11
Nodes (17): GalleryOpenState, .isBusy, Bool, UUID, ProjectVersionsView, RecentlyDeletedView, .body, Void (+9 more)

### Community 85 - "BrushStamper"
Cohesion: 0.11
Nodes (16): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+8 more)

### Community 86 - "Known Issues"
Cohesion: 0.06
Nodes (34): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), A vector cel holding warped text re-warps it on every invalidation, not once per commit (2026-08-26), An unclamped zoom-out drag can store a coordinate 100x the canvas extent (2026-08-27), Cleanup opportunities, Cut is a no-op on screen when the eraser is thinner than the line (2026-08-22) (+26 more)

### Community 87 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 88 - "RenderNode"
Cohesion: 0.08
Nodes (31): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+23 more)

### Community 89 - "UndoHistory"
Cohesion: 0.12
Nodes (15): Action, Bool, Int, UInt64, Void, UndoBudget, .maxCostBytes, UndoHistory (+7 more)

### Community 90 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, Bool (+9 more)

### Community 91 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 92 - "SaveDamageGateLogicTests"
Cohesion: 0.16
Nodes (10): SaveDamageGateLogicTests, Any, CanvasManager, Data, StaticString, String, UInt, URL (+2 more)

### Community 93 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 94 - "PinchMergeGateLogicTests"
Cohesion: 0.14
Nodes (7): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests, Bool, Int

### Community 95 - "TextHitTestLogicTests"
Cohesion: 0.15
Nodes (8): TextMeasure, Bool, CGAffineTransform, CGSize, String, UIScribbleInteraction, VectorStroke, TextHitTestLogicTests

### Community 96 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 97 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 98 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 99 - "MetalFillSession"
Cohesion: 0.19
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 100 - "OnionSkinSettings"
Cohesion: 0.14
Nodes (13): .gradientStops, .opacitySliders, OnionSkinSettings, Side, .id, next, previous, .step (+5 more)

### Community 101 - "TextTransformOverlayView"
Cohesion: 0.12
Nodes (16): Bool, CALayer, CGRect, NSCoder, Set, UIEvent, UITouch, Void (+8 more)

### Community 102 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 103 - "CaseIterable"
Cohesion: 0.08
Nodes (28): CaseIterable, Kind, line, oval, rectangle, FillMode, .displayName, flood (+20 more)

### Community 104 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 105 - "Coordinator"
Cohesion: 0.14
Nodes (14): BlockDrag, Coordinator, MenuRequest, block, gap, loop, CanvasManager, Context (+6 more)

### Community 106 - "SwiftUI"
Cohesion: 0.09
Nodes (11): Combine, ScenePhaseSaveGate, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager (+3 more)

### Community 107 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 108 - ".compositeSize"
Cohesion: 0.12
Nodes (12): NSObjectProtocol, .resolutionNoteText, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel (+4 more)

### Community 109 - "agent"
Cohesion: 0.07
Nodes (28): agent, orchestrator, worker-bugfix, worker-research, worker-test, command, deploy, resign (+20 more)

### Community 110 - "CanvasTouchOwnerLogicTests"
Cohesion: 0.18
Nodes (3): CanvasTouchOwnerLogicTests, String, Void

### Community 111 - "CodingKeys"
Cohesion: 0.07
Nodes (29): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+21 more)

### Community 112 - "ProjectLoadDamage"
Cohesion: 0.12
Nodes (19): DecodedCels, LayerDamage, .isEmpty, .itemPhrase, .total, ProjectLoadDamage, .isDamaged, .itemCount (+11 more)

### Community 113 - "StrokeSampleGateLogicTests"
Cohesion: 0.17
Nodes (4): CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 114 - "CanvasTouchOwner"
Cohesion: 0.08
Nodes (26): CanvasTouchChrome, guideGrip, none, .owner, shapeHandleOrOutline, textBoxOrBand, textHandle, transformBoxOrHandle (+18 more)

### Community 115 - "CanvasTransformFreezeUITests"
Cohesion: 0.21
Nodes (7): CanvasTransformFreezeUITests, Bool, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 116 - "bash"
Cohesion: 0.14
Nodes (27): worker-feature, worker-integration, worker-ui, gh *, git *, xcodebuild *, permission, bash (+19 more)

### Community 117 - "VectorTextPersistenceLogicTests"
Cohesion: 0.21
Nodes (4): String, UUID, VectorStroke, VectorTextPersistenceLogicTests

### Community 118 - "ActivePanel"
Cohesion: 0.11
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 119 - "SelectionMode"
Cohesion: 0.11
Nodes (16): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+8 more)

### Community 120 - "CanvasTouchInputs"
Cohesion: 0.09
Nodes (19): CanvasTouchInputs, .activeHostIsInteractive, .activeHostReceivesTouches, .catchAllIsEnabled, .catchAllRaisesNotice, .eyedropperPressIsEnabled, .fillPressIsEnabled, .floatingOverlayIsInteractive (+11 more)

### Community 121 - ".setUpGestures"
Cohesion: 0.12
Nodes (12): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITapGestureRecognizer, UITouch, UIView, Void (+4 more)

### Community 122 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.17
Nodes (5): CGRect, Range, CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 123 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 124 - ".affine"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 125 - "MoveTransformBottomBar"
Cohesion: 0.09
Nodes (21): .bottomDock, MoveTransformBottomBar, .body, .caption, .divider, .freeformReason, .mirrorReason, .modeIsAdjustable (+13 more)

### Community 126 - "TimelineRowView"
Cohesion: 0.14
Nodes (15): Kind, cel, gap, Segment, Cel, Int, UIPanGestureRecognizer, UITapGestureRecognizer (+7 more)

### Community 127 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 128 - "read"
Cohesion: 0.34
Nodes (25): float2, read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+17 more)

### Community 129 - "SpacingChart"
Cohesion: 0.11
Nodes (10): GuidePath, .end, .start, SpacingChart, .curve, .draggable, CGVector, Int (+2 more)

### Community 130 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 131 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 132 - "FillGestureRestartLogicTests"
Cohesion: 0.22
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 133 - "WindowEventTap"
Cohesion: 0.19
Nodes (9): AnyClass, NSObject, FoundElement, InstallReport, CGRect, UIEvent, WindowEventTap, UIAccessibilityTraits (+1 more)

### Community 134 - "2. The decisions"
Cohesion: 0.08
Nodes (24): 0. What already exists, 1. Every tier, and what a resize owes it, 2. The decisions, 3. Why the rejected alternatives were rejected, 4. Staged delivery, 5. Behaviour, decided, 6. Open questions for the owner, Canvas Resize — Specification (+16 more)

### Community 135 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 136 - "1. The decisions"
Cohesion: 0.09
Nodes (23): 0. What shipped, and where it lives, 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, 6. Open risks, A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls (+15 more)

### Community 137 - "EffectPipelines"
Cohesion: 0.14
Nodes (16): MTLLibrary, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState (+8 more)

### Community 138 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 139 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 140 - "TextRecipeCodableLogicTests"
Cohesion: 0.14
Nodes (5): StaticString, String, T, UInt, TextRecipeCodableLogicTests

### Community 141 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 142 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 143 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 144 - "Int"
Cohesion: 0.22
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 145 - "Handle"
Cohesion: 0.10
Nodes (20): Int, Corner, bottomLeft, bottomRight, topLeft, topRight, Handle, bottom (+12 more)

### Community 146 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, brush, color, composite, elements, fill, fills, id (+13 more)

### Community 147 - "OnionSkinSource.swift"
Cohesion: 0.14
Nodes (7): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, UIImage, VectorStroke

### Community 148 - "OnionSkinLogicTests"
Cohesion: 0.21
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 149 - "The layer transform — keep it, or bake it into the geometry?"
Cohesion: 0.10
Nodes (20): 0. The ruling, and what this document is answering, 1. What `_transform` actually buys today, 1a. The census — every read and every write, 1b. Per feature — does it need a layer transform, or a way to map a gesture into storage?, 2. What breaks if it is removed, in order of severity, 3. Migration, 4. The live drag, and the question that decides its cost, 5. Images and text — which transforms survive, and why they are not the same wart (+12 more)

### Community 150 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 151 - ".previewed"
Cohesion: 0.36
Nodes (5): Double, Int, UIImage, VectorStroke, VectorCutPreviewLogicTests

### Community 152 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 153 - "LayerStackListView.Coordinator"
Cohesion: 0.15
Nodes (11): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval, UIGestureRecognizer (+3 more)

### Community 154 - "CGRect"
Cohesion: 0.22
Nodes (10): CGRect, NSCoder, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView, TimelinePlayheadView, TimelineRulerView (+2 more)

### Community 155 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 156 - "Recording"
Cohesion: 0.13
Nodes (14): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderIndicator, .body (+6 more)

### Community 157 - ".coverage"
Cohesion: 0.27
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 158 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 159 - "Alignment"
Cohesion: 0.11
Nodes (17): Alignment, center, .displayName, .id, justified, left, right, Mode (+9 more)

### Community 160 - "TextSettingsPanel"
Cohesion: 0.15
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 161 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 162 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (19): A project that opened with something unreadable, Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features (+11 more)

### Community 163 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 164 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 165 - "StructureSnapshot"
Cohesion: 0.17
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, guideStrokes

### Community 166 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 167 - ".performDrag"
Cohesion: 0.16
Nodes (5): InterpolationWorkflowUITests, Bool, TimeInterval, XCUIElement, TimelineGestureUITests

### Community 168 - "SideToolbar"
Cohesion: 0.16
Nodes (14): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+6 more)

### Community 169 - "CelBlockView"
Cohesion: 0.16
Nodes (7): CelBlockView, Bool, ClosedRange, String, UIGestureRecognizer, UIImage, UITouch

### Community 170 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 171 - ".draw"
Cohesion: 0.34
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 172 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 173 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 174 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 175 - "ToolLogicTests"
Cohesion: 0.12
Nodes (3): Bool, Tool, ToolLogicTests

### Community 177 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 178 - "TimelineLayoutKey"
Cohesion: 0.24
Nodes (13): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+5 more)

### Community 179 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 180 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 181 - ".sample"
Cohesion: 0.27
Nodes (9): ObjectiveC.runtime, ResolvedTarget, Bool, CGSize, Double, Int, UITouch, TouchSample (+1 more)

### Community 182 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 183 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 184 - "Lasso Fill — Specification"
Cohesion: 0.15
Nodes (12): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 2a. Where a fill lands in the stack: on top of everything already on the layer, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill (+4 more)

### Community 185 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.17
Nodes (11): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+3 more)

### Community 186 - "String"
Cohesion: 0.32
Nodes (6): Entry, ObjectIdentifier, Set, String, UIGestureRecognizer, UIView

### Community 187 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 189 - "TODO"
Cohesion: 0.17
Nodes (12): (12) A layer should not have a *resolution* — bake geometry into canvas coordinates, (13) Canvas padding shares one 16k budget with the canvas, and the base maximum rises, (14) A reversible Move: keep the transform in doubles until you choose to bake it, (8) Fixed-point sample coordinates, (9) Resize the canvas from the Actions menu, Canvas geometry, and how a coordinate is stored, Carried — deliberate, and not an ask, Done this pass (+4 more)

### Community 190 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 191 - "CanvasActiveLayer"
Cohesion: 0.20
Nodes (9): CanvasActiveLayer, .exists, .hasNoDrawingSurface, noDrawingSurface, none, raster, vector, Bool (+1 more)

### Community 192 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (7): CanvasPresentationModifier, Bool, CanvasManager, Void, View, PresentedContent, ViewModifier

### Community 193 - "Multi-Session Protocol"
Cohesion: 0.20
Nodes (10): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, `git stash` is per-repository, not per-worktree, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change (+2 more)

### Community 194 - "WarpParams"
Cohesion: 0.20
Nodes (10): WarpParams, m0, m1, m2, m3, m4, m5, m6 (+2 more)

### Community 195 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 196 - "1. What will actually hurt, ranked"
Cohesion: 0.22
Nodes (9): 1. Nothing answers "who owns this canvas touch" — and this is where the bugs are — CLOSED, `38b6fed`, 1. What will actually hurt, ranked, 2. What a frame looks like is memoized in eleven hand-written keys, 2. What is genuinely good — do not disturb, 3. A save that fails tells nobody, and one nil PNG fails the whole document, 3. What is not worth doing, 4. One persisted property means four hand-kept structs, and the initializer defaults hide the miss, 4. The owner's question, answered (+1 more)

### Community 197 - "BrushBlendMode"
Cohesion: 0.22
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 198 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 199 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 200 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 201 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 202 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 203 - "Handoff — 2026-08-27 (session 70)"
Cohesion: 0.25
Nodes (7): Carried, deliberately not done, Handoff — 2026-08-27 (session 70), Start here — paste this to begin the next session, State, Still open, blocked on the owner's iPad, Still true, carried forward, What landed

### Community 204 - "ProjectStore.swift"
Cohesion: 0.38
Nodes (6): os, CodableColor, .color, Color, .codable, CodableColor

### Community 205 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 208 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 209 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 210 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 211 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 212 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 213 - "AppliedTool"
Cohesion: 0.50
Nodes (4): AppliedTool, Color, Double, Tool

### Community 214 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 215 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 216 - "Colouring"
Cohesion: 0.50
Nodes (4): Colouring, .id, originalColors, .title

### Community 217 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **1214 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+1209 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `CGPoint`, `cels`, `CanvasManager`, `ObjectTransformLogicTests`, `Homography`, `Coordinator`, `LassoFillLogicTests`, `CanvasManager`, `InterpolationGuideLogicTests`, `.solidImage`, `Lattice`, `ARAPLogicTests`, `ProjectSaveLogicTests`, `String`, `InterpolationRecipe`, `.refreshUndoRedoState`, `PerfBaselineTests`, `VectorCanvas`, `LassoMoveLogicTests`, `SizePreviewRequest`, `StrokeCanvasView`, `TextTransformLogicTests`, `EffectLayerLogicTests`, `FontDescriptor`, `SandwichLogicTests`, `VectorEraserLogicTests`, `DeformFactorization`, `.report`, `AnimationTimeline`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `BrushEngineLogicTests`, `XCUIApplication`, `CanvasManager`, `ProjectStore`, `VectorSample`, `CanvasManager`, `Binding`, `.apply`, `TextOverlayView`, `LayerRowModel`, `DrawingView`, `.transparentFormat`, `Typography`, `TextFrame`, `RenderRequest`, `RasterLayerTexture`, `TextBakeCharacterizationTests`, `.rows`, `Brush`, `VectorEraserHybridLogicTests`, `GuideStroke`, `LayerStackCell`, `.evaluate`, `InterpolationRenderLogicTests`, `VectorCanvasDataLogicTests`, `TextRecipe`, `FloatingPieceOverlayView`, `BrushStamper`, `ActionRecorder`, `GuideOverlayView`, `PinchMergeGateLogicTests`, `TextHitTestLogicTests`, `StrokeGeometry`, `StrokeSpatialIndex`, `TextTransformOverlayView`, `Coordinator`, `.compositeSize`, `StrokeSampleGateLogicTests`, `CanvasTransformFreezeUITests`, `SelectionMode`, `TimelineLayoutKeyLogicTests`, `.affine`, `TimelineRowView`, `XCUIApplication`, `SpacingChart`, `WindowEventTap`, `CanvasManager`, `CurveEditor`, `Int`, `Handle`, `CodingKeys`, `OnionSkinSource.swift`, `.previewed`, `CGRect`, `SandwichCompositingUITests`, `Alignment`, `TextSettingsPanel`, `InterpolateBar`, `.performDrag`, `SideToolbar`, `CelBlockView`, `.draw`, `ActionsMenu`, `TimelineLayoutKey`, `CGContextDabTarget`, `.sample`, `StrokeStabilizer`, `TransformOverlaySupport.swift`, `JSONValue`, `AppliedTool`?**
  _High betweenness centrality (0.285) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `CanvasManager`, `ObjectTransformLogicTests`, `Homography`, `Coordinator`, `LassoFillLogicTests`, `CanvasManager`, `InterpolationGuideLogicTests`, `.solidImage`, `Lattice`, `CGFloat`, `ARAPLogicTests`, `ProjectSaveLogicTests`, `String`, `InterpolationRecipe`, `.refreshUndoRedoState`, `PerfBaselineTests`, `VectorCanvas`, `LassoMoveLogicTests`, `SizePreviewRequest`, `StrokeCanvasView`, `TextTransformLogicTests`, `VectorEraserLogicTests`, `DeformFactorization`, `ColorPickerPanel`, `.report`, `AnimationTimeline`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `SelectionOverlayView`, `BrushEngineLogicTests`, `MaskParityLogicTests`, `CanvasManager`, `VectorSample`, `CanvasManager`, `TextOverlayView`, `.transparentFormat`, `Typography`, `TextFrame`, `RasterLayerTexture`, `TextBakeCharacterizationTests`, `Brush`, `VectorEraserHybridLogicTests`, `GuideStroke`, `.evaluate`, `InterpolationRenderLogicTests`, `.activeCelIndex`, `TextRecipe`, `FloatingPieceOverlayView`, `BrushStamper`, `GuideOverlayView`, `SaveDamageGateLogicTests`, `TextHitTestLogicTests`, `StrokeGeometry`, `StrokeSpatialIndex`, `TextTransformOverlayView`, `EyedropperLogicTests`, `Coordinator`, `StrokeSampleGateLogicTests`, `VectorTextPersistenceLogicTests`, `SelectionMode`, `.setUpGestures`, `.affine`, `TimelineRowView`, `SpacingChart`, `FillGestureRestartLogicTests`, `WindowEventTap`, `TextRecipeCodableLogicTests`, `CurveEditor`, `Handle`, `LayerStackListView.Coordinator`, `CGRect`, `CelBlockView`, `ToolLogicTests`, `CGContextDabTarget`, `.sample`, `StrokeStabilizer`, `.rasterize`, `.sampledColor`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.185) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `CGPoint`, `cels`, `ObjectTransformLogicTests`, `FillGestureRestartLogicTests`, `.manager`, `Homography`, `LassoFillLogicTests`, `VectorPreviewPlanLogicTests`, `ProjectBackupManager`, `InterpolationGuideLogicTests`, `.solidImage`, `Lattice`, `CGFloat`, `ARAPLogicTests`, `AlphaMask`, `ProjectSaveLogicTests`, `UIKit`, `TextRecipeCodableLogicTests`, `InterpolationRecipe`, `OnionSkinLogicTests`, `PerfBaselineTests`, `.previewed`, `LassoMoveLogicTests`, `TextTransformLogicTests`, `EffectLayerLogicTests`, `FontDescriptor`, `ShapeHoldClock`, `SandwichLogicTests`, `BlockDragCharacterizationTests`, `VectorEraserLogicTests`, `StrokeGestureRecognizer`, `PaintUITestCase`, `.report`, `StrokeGeometryLogicTests`, `CanvasPresentationLogicTests`, `LayerTreeCharacterizationTests`, `SelectionOverlayView`, `BrushEngineLogicTests`, `MaskParityLogicTests`, `ToolLogicTests`, `EffectMultiPassLogicTests`, `Typography`, `.rgbaBytes`, `TextBakeCharacterizationTests`, `VectorEraserHybridLogicTests`, `InterpolationRenderLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `GalleryOpenState`, `UndoHistory`, `PlaybackBoundsCharacterizationTests`, `SaveDamageGateLogicTests`, `PinchMergeGateLogicTests`, `TextHitTestLogicTests`, `EffectParityLogicTests`, `EyedropperLogicTests`, `CanvasTouchOwnerLogicTests`, `StrokeSampleGateLogicTests`, `VectorTextPersistenceLogicTests`, `TimelineLayoutKeyLogicTests`, `CanvasNotice`, `.affine`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 89 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 89 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 40 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 40 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 8 INFERRED edges - model-reasoned connections that need verification._