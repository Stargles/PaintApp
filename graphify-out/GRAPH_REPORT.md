# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-10)

## Corpus Check
- 146 files · ~268,951 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3618 nodes · 11097 edges · 128 communities (118 shown, 10 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1329 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1bdcab10`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
- ProjectBackupManager
- .manager
- TimelineRowView
- ColorPickerPanel
- CanvasManager
- bash
- StrokeGeometryLogicTests
- CGPoint
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- InterpolationRenderLogicTests
- CanvasManager
- StrokeCanvasView
- .evaluate
- ContentView
- PointCloudIndex
- Coordinator
- .transparentFormat
- ShapeGeometry
- ShapeDetector
- String
- CanvasManager
- cels
- MetalFillEngine
- .manager
- HandleKind
- PerfBaselineTests
- .withStructureUndo
- FillParams
- TouchCountRecognizer
- CanvasManager
- VectorSample
- LayerFolder
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- LayerOptionsPanel
- Lattice
- CGFloat
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- InterpolationGuideLogicTests
- SelectionOverlayView
- CodingKeys
- RasterLayerTexture
- .listTrash
- SwiftUI
- StrokeGestureRecognizer
- DeformFactorization
- PerfMonitor
- LayerKind
- Color
- .stampCircle
- 4. Future upgrades — the deferred list
- LayerRowModel
- ProjectManifest
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- ActionsMenu
- Performance baseline
- CodingKeys
- ShapeDetectorLogicTests
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- Edge
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Usage Guide
- .stampDab
- .indices
- CodingKeys
- CodingKeys
- CLAUDE.md
- EraserSettingsPanel
- CanvasManager
- Known Issues
- GuideStroke
- InterpolationEngineDiagnosticsLogicTests
- GuideOverlayView
- View
- UIKit
- DrawingView
- .arched
- Gesture
- InterpolateBar
- ShapeOverlayView
- TimedSample
- Multi-Session Protocol
- parallel_test.sh
- What needs to change
- .registerGroups
- Corner
- BackupManagerLogicTests
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- InterpolationRefusal
- .encode
- BrushBlendMode
- StructureSnapshot
- UIView
- CutOutcome
- GuidePath
- MotionGroup
- GalleryView
- InterpolationRecipe
- InterpolationPreviewKey
- SpacingChart
- .group
- run.sh
- .flipCanvas
- ManifestSkeleton
- Atomic
- VectorEraserMode
- ProjectStore.swift
- VectorScratchRole

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 531 edges
2. `CGFloat` - 402 edges
3. `VectorCanvas` - 116 edges
4. `CanvasManager` - 100 edges
5. `Lattice` - 98 edges
6. `CanvasManager` - 98 edges
7. `layers` - 98 edges
8. `VectorSample` - 97 edges
9. `InterpolationGuideLogicTests` - 90 edges
10. `Coordinator` - 78 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (128 total, 10 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (40): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+32 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.15
Nodes (16): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+8 more)

### Community 3 - ".manager"
Cohesion: 0.05
Nodes (24): OnionSkinSource, PreviousCelOnionSkinSource, CanvasFixture, CanvasManager, Int, Layer, StaticString, String (+16 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.06
Nodes (43): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+35 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (33): CanvasManager, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+25 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (13): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+5 more)

### Community 9 - "CGPoint"
Cohesion: 0.11
Nodes (14): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+6 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.14
Nodes (8): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.06
Nodes (57): AnyObject, UUID, DabTarget, CodableColor, .uiColor, image, kind, DabLattice (+49 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "InterpolationRenderLogicTests"
Cohesion: 0.15
Nodes (13): StrokeComposite, erase, paint, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double (+5 more)

### Community 14 - "CanvasManager"
Cohesion: 0.12
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+17 more)

### Community 16 - ".evaluate"
Cohesion: 0.12
Nodes (24): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+16 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.14
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 19 - "Coordinator"
Cohesion: 0.08
Nodes (20): LayerHostView, CanvasView, Coordinator, CanvasManager, CGSize, Context, Coordinator, Date (+12 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.11
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "ShapeGeometry"
Cohesion: 0.12
Nodes (14): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+6 more)

### Community 22 - "ShapeDetector"
Cohesion: 0.17
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 23 - "String"
Cohesion: 0.06
Nodes (39): CaseIterable, Kind, line, oval, rectangle, Void, CanvasManager, FloatingPiece (+31 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 25 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 28 - "HandleKind"
Cohesion: 0.13
Nodes (15): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+7 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.15
Nodes (12): BrushStamper, Sample, ClosedRange, Void, PerfBaselineTests, CanvasManager, Double, Int (+4 more)

### Community 30 - ".withStructureUndo"
Cohesion: 0.13
Nodes (13): .interpolationTarget, CanvasManager, Bool, Int, Void, Cel, .endFrame, Int (+5 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 33 - "CanvasManager"
Cohesion: 0.17
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 34 - "VectorSample"
Cohesion: 0.15
Nodes (13): Int64, VectorSample, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect (+5 more)

### Community 35 - "LayerFolder"
Cohesion: 0.12
Nodes (14): CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String, UUID (+6 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.05
Nodes (43): Content, Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder (+35 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - ".load"
Cohesion: 0.17
Nodes (18): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+10 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 42 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 43 - "CGFloat"
Cohesion: 0.13
Nodes (9): Brush, CGFloat, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser (+1 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+11 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 50 - ".listTrash"
Cohesion: 0.21
Nodes (6): name, Date, UInt64, TrashItem, .id, Range

### Community 51 - "SwiftUI"
Cohesion: 0.11
Nodes (9): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+1 more)

### Community 52 - "StrokeGestureRecognizer"
Cohesion: 0.27
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 53 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - "LayerKind"
Cohesion: 0.15
Nodes (11): Layer, Bool, Cel, Double, String, UIImage, UUID, LayerKind (+3 more)

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - ".stampCircle"
Cohesion: 0.26
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 58 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.05
Nodes (38): IndexPath, LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+30 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.38
Nodes (14): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor, Date (+6 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.10
Nodes (8): ARAPInterpolation, groups, ARAPLogicTests, .rigidMotionL, Int, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 66 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 67 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 68 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, id (+10 more)

### Community 69 - "ShapeDetectorLogicTests"
Cohesion: 0.14
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 77 - ".stampDab"
Cohesion: 0.18
Nodes (7): DabRNG, DiscardedDabTarget, Bool, CGBlendMode, Double, UIColor, UInt64

### Community 79 - "CodingKeys"
Cohesion: 0.09
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 80 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.07
Nodes (30): Identifiable, CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider (+22 more)

### Community 84 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 85 - "GuideStroke"
Cohesion: 0.18
Nodes (10): Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+2 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 88 - "View"
Cohesion: 0.09
Nodes (26): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+18 more)

### Community 89 - "UIKit"
Cohesion: 0.06
Nodes (10): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String (+2 more)

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 92 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 93 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 94 - "ShapeOverlayView"
Cohesion: 0.15
Nodes (14): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, ShapeOverlayView (+6 more)

### Community 95 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 96 - "Multi-Session Protocol"
Cohesion: 0.40
Nodes (5): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 99 - ".registerGroups"
Cohesion: 0.23
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 100 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 101 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 108 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (11): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+3 more)

### Community 111 - "BrushBlendMode"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 112 - "StructureSnapshot"
Cohesion: 0.26
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 113 - "UIView"
Cohesion: 0.12
Nodes (16): FloatingTransform, .effectiveScaleX, .effectiveScaleY, Kind, rotate, scale, LayerTransform, .effectiveScaleX (+8 more)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 117 - "MotionGroup"
Cohesion: 0.21
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 118 - "GalleryView"
Cohesion: 0.15
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 119 - "InterpolationRecipe"
Cohesion: 0.12
Nodes (23): Codable, Equatable, CelRef, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed (+15 more)

### Community 120 - "InterpolationPreviewKey"
Cohesion: 0.17
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 122 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 123 - ".group"
Cohesion: 0.33
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 128 - ".flipCanvas"
Cohesion: 0.38
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 129 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 130 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 133 - "VectorEraserMode"
Cohesion: 0.12
Nodes (16): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+8 more)

### Community 140 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 141 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

## Knowledge Gaps
- **457 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+452 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `.manager`, `TimelineRowView`, `VectorEraserMode`, `CanvasManager`, `StrokeGeometryLogicTests`, `CGPoint`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `CanvasManager`, `StrokeCanvasView`, `.evaluate`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `ShapeGeometry`, `ShapeDetector`, `String`, `CanvasManager`, `cels`, `.manager`, `PerfBaselineTests`, `VectorSample`, `StrokeSettingsPanel`, `AnimationTimeline`, `.load`, `Lattice`, `InterpolationModelLogicTests`, `InterpolationGuideLogicTests`, `RasterLayerTexture`, `DeformFactorization`, `Color`, `.stampCircle`, `LayerRowModel`, `SideToolbar`, `ARAPLogicTests`, `ActionsMenu`, `ShapeDetectorLogicTests`, `StrokeStabilizer`, `.stampDab`, `.indices`, `CodingKeys`, `EraserSettingsPanel`, `CanvasManager`, `InterpolationEngineDiagnosticsLogicTests`, `GuideOverlayView`, `UIKit`, `DrawingView`, `.arched`, `InterpolateBar`, `ShapeOverlayView`, `TimedSample`, `.registerGroups`, `BrushBlendMode`, `UIView`, `GuidePath`, `InterpolationRecipe`, `InterpolationPreviewKey`, `SpacingChart`, `.group`?**
  _High betweenness centrality (0.359) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `CanvasManager`, `StrokeCanvasView`, `.evaluate`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `ShapeGeometry`, `ShapeDetector`, `String`, `CanvasManager`, `cels`, `.manager`, `HandleKind`, `PerfBaselineTests`, `.withStructureUndo`, `VectorSample`, `AnimationTimeline`, `FloatingPieceOverlayView`, `Lattice`, `CGFloat`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `InterpolationGuideLogicTests`, `SelectionOverlayView`, `RasterLayerTexture`, `DeformFactorization`, `.stampCircle`, `LayerRowModel`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `ShapeDetectorLogicTests`, `Edge`, `StrokeStabilizer`, `.stampDab`, `.indices`, `CanvasManager`, `InterpolationEngineDiagnosticsLogicTests`, `GuideOverlayView`, `UIKit`, `.arched`, `Gesture`, `ShapeOverlayView`, `TimedSample`, `.registerGroups`, `BrushBlendMode`, `UIView`, `GuidePath`, `.group`?**
  _High betweenness centrality (0.224) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `.manager` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `BackupManagerLogicTests`, `ShapeDetectorLogicTests`, `PlaybackBoundsCharacterizationTests`, `CGPoint`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `InterpolationModelLogicTests`, `InterpolationGuideLogicTests`, `InterpolationRenderLogicTests`, `ProjectSaveLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `cels`, `UIKit`, `PerfBaselineTests`, `ARAPLogicTests`?**
  _High betweenness centrality (0.094) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 10 INFERRED edges - model-reasoned connections that need verification._