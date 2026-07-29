# Graph Report - .  (2026-07-28)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1860 nodes · 4946 edges · 67 communities (61 shown, 6 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 321 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `64e76354`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 66

## God Nodes (most connected - your core abstractions)
1. `CanvasManager` - 164 edges
2. `PaintSoftwareUITests` - 98 edges
3. `Coordinator` - 67 edges
4. `layers` - 57 edges
5. `ProjectBackupManager` - 56 edges
6. `ShapeGeometry` - 53 edges
7. `StrokeCanvasView` - 43 edges
8. `VectorCanvas` - 38 edges
9. `RasterLayerTexture` - 36 edges
10. `Brush` - 33 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift
- `.body` --calls--> `TimelineTrackView`  [INFERRED]
  PaintSoftware/Views/AnimationTimeline.swift → PaintSoftware/Views/TimelineTrackView.swift
- `.body` --calls--> `StrokeSettingsPanel`  [INFERRED]
  PaintSoftware/Views/BrushSettingsPanel.swift → PaintSoftware/Views/StrokeSettingsPanel.swift
- `.body` --calls--> `StrokeSettingsPanel`  [INFERRED]
  PaintSoftware/Views/EraserSettingsPanel.swift → PaintSoftware/Views/StrokeSettingsPanel.swift
- `.body` --calls--> `CanvasSizePickerView`  [INFERRED]
  PaintSoftware/ContentView.swift → PaintSoftware/Views/CanvasSizePickerView.swift

## Import Cycles
- None detected.

## Communities (67 total, 6 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.09
Nodes (11): CGVector, PaintSoftwareUITests, Bool, CGFloat, Double, Int, String, TimeInterval (+3 more)

### Community 1 - "Community 1"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 2 - "Community 2"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, String, UInt, UUID, XCTestCase (+10 more)

### Community 3 - "Community 3"
Cohesion: 0.08
Nodes (29): ClosedFit, ShapeDetector, Bool, CGFloat, CGPoint, CGRect, Int, ShapeGeometry (+21 more)

### Community 4 - "Community 4"
Cohesion: 0.07
Nodes (38): CGContext, BrushStamper, Sample, Bool, CGBlendMode, CGFloat, CGPoint, Double (+30 more)

### Community 5 - "Community 5"
Cohesion: 0.07
Nodes (39): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+31 more)

### Community 6 - "Community 6"
Cohesion: 0.06
Nodes (37): FloatingTransform, FloatingPieceOverlayView, Bool, CGPoint, CGRect, CGSize, Int, NSCoder (+29 more)

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (37): .currentFrame, .currentLayerIndex, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+29 more)

### Community 8 - "Community 8"
Cohesion: 0.08
Nodes (36): Data, Identifiable, CodableColor, .uiColor, ImageRef, Bool, CGAffineTransform, CGFloat (+28 more)

### Community 9 - "Community 9"
Cohesion: 0.07
Nodes (34): IndexPath, NSObject, .body, Coordinator, DropTarget, between, onto, LayerRowModel (+26 more)

### Community 10 - "Community 10"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 11 - "Community 11"
Cohesion: 0.06
Nodes (39): CALayer, CornerHandle, bottomLeft, bottomRight, topLeft, topRight, EdgeHandle, bottom (+31 more)

### Community 12 - "Community 12"
Cohesion: 0.05
Nodes (32): CanvasManager, .activeShape, .activeShapePreviewImage, .availableBrushes, .availableEraserBrushes, .effectiveLoopRange, .isActiveShapePreviewStale, .isFillInAdjustableState (+24 more)

### Community 13 - "Community 13"
Cohesion: 0.11
Nodes (21): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+13 more)

### Community 14 - "Community 14"
Cohesion: 0.16
Nodes (7): .activeLayerIsVector, Bool, Cel, CGSize, Int, Layer, layers

### Community 15 - "Community 15"
Cohesion: 0.07
Nodes (30): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+22 more)

### Community 16 - "Community 16"
Cohesion: 0.16
Nodes (16): Equatable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+8 more)

### Community 17 - "Community 17"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 18 - "Community 18"
Cohesion: 0.15
Nodes (15): AppliedTool, Coordinator, CGFloat, CGSize, Color, Date, Double, NSLayoutConstraint (+7 more)

### Community 19 - "Community 19"
Cohesion: 0.15
Nodes (12): StackAnchor, bottom, folder, layer, Set, String, UUID, LayerFolder (+4 more)

### Community 20 - "Community 20"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 21 - "Community 21"
Cohesion: 0.19
Nodes (11): StrokeInput, CGFloat, CGPoint, StrokeCanvasView, .brush, .pencilOnlyDrawing, .raster, .vectorCanvas (+3 more)

### Community 22 - "Community 22"
Cohesion: 0.15
Nodes (14): ProjectStore, .projectsDirectory, ProjectSummary, Bool, CanvasManager, Date, String, UIImage (+6 more)

### Community 23 - "Community 23"
Cohesion: 0.11
Nodes (20): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .paletteSelectionBinding, .palettesTab (+12 more)

### Community 24 - "Community 24"
Cohesion: 0.30
Nodes (3): BrushDynamics, Double, BrushEngineLogicTests

### Community 25 - "Community 25"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 26 - "Community 26"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+12 more)

### Community 27 - "Community 27"
Cohesion: 0.15
Nodes (3): LayerTransform, UIImage, Void

### Community 28 - "Community 28"
Cohesion: 0.12
Nodes (17): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+9 more)

### Community 29 - "Community 29"
Cohesion: 0.17
Nodes (18): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+10 more)

### Community 30 - "Community 30"
Cohesion: 0.12
Nodes (16): CADisplayLink, CFTimeInterval, Combine, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton (+8 more)

### Community 31 - "Community 31"
Cohesion: 0.16
Nodes (11): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGPoint, CGRect, NSCoder, UIColor (+3 more)

### Community 32 - "Community 32"
Cohesion: 0.12
Nodes (10): App, task, PaintApp, .body, GalleryTileView, .body, Void, PhotosUI (+2 more)

### Community 33 - "Community 33"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 34 - "Community 34"
Cohesion: 0.11
Nodes (18): CodingKey, CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes (+10 more)

### Community 35 - "Community 35"
Cohesion: 0.29
Nodes (8): StrokeGestureRecognizer, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount, UIGestureRecognizer

### Community 36 - "Community 36"
Cohesion: 0.15
Nodes (8): LayerStackCell, Bool, CGFloat, Double, Int, NSLayoutConstraint, UIView, Void

### Community 37 - "Community 37"
Cohesion: 0.12
Nodes (15): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, CGFloat, UUID (+7 more)

### Community 38 - "Community 38"
Cohesion: 0.12
Nodes (9): Foundation, LayerKind, compositing, raster, vector, Notification.Name, AppVersion, .versionString (+1 more)

### Community 39 - "Community 39"
Cohesion: 0.17
Nodes (14): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+6 more)

### Community 40 - "Community 40"
Cohesion: 0.13
Nodes (9): Any, CanvasHostView, .canBecomeFirstResponder, .keyCommands, CanvasManager, NSCoder, Selector, UIKeyCommand (+1 more)

### Community 41 - "Community 41"
Cohesion: 0.15
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 42 - "Community 42"
Cohesion: 0.22
Nodes (7): CanvasView, CGPoint, CGRect, Context, Coordinator, LayerTransform, UIColor

### Community 44 - "Community 44"
Cohesion: 0.14
Nodes (14): CaseIterable, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+6 more)

### Community 45 - "Community 45"
Cohesion: 0.22
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 46 - "Community 46"
Cohesion: 0.21
Nodes (4): Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 47 - "Community 47"
Cohesion: 0.24
Nodes (7): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager

### Community 48 - "Community 48"
Cohesion: 0.24
Nodes (6): .activeViewName, viewPresets, Bool, String, UUID, ViewPreset

### Community 49 - "Community 49"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 50 - "Community 50"
Cohesion: 0.22
Nodes (8): .panelView, FillSettingsPanel, .body, CanvasManager, Color, StubToolPanel, .body, String

### Community 51 - "Community 51"
Cohesion: 0.20
Nodes (4): CoreGraphics, LayerTransform, CGFloat, CGPoint

### Community 52 - "Community 52"
Cohesion: 0.20
Nodes (9): Hashable, Tool, eraser, fill, pen, pencil, Tab, color (+1 more)

### Community 53 - "Community 53"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 54 - "Community 54"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 55 - "Community 55"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 56 - "Community 56"
Cohesion: 0.33
Nodes (6): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, CanvasManager

### Community 58 - "Community 58"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 59 - "Community 59"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 60 - "Community 60"
Cohesion: 0.40
Nodes (3): NSCoder, String, UITableViewCell

### Community 66 - "Community 66"
Cohesion: 0.35
Nodes (4): StrokeStabilizer, .stabilization, CGPoint, Double

## Knowledge Gaps
- **243 isolated node(s):** `gallery`, `sizePicker`, `editor`, `softRound`, `hardRound` (+238 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CanvasManager` connect `Community 12` to `Community 3`, `Community 4`, `Community 7`, `Community 45`, `Community 14`, `Community 15`, `Community 48`, `Community 17`, `Community 19`, `Community 52`, `Community 57`, `Community 27`, `Community 28`, `Community 30`?**
  _High betweenness centrality (0.212) - this node is a cross-community bridge._
- **Why does `UIKit` connect `Community 46` to `Community 32`, `Community 35`, `Community 36`, `Community 5`, `Community 6`, `Community 7`, `Community 8`, `Community 9`, `Community 11`, `Community 12`, `Community 13`, `Community 17`, `Community 51`, `Community 54`, `Community 58`, `Community 30`, `Community 31`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **Why does `Brush` connect `Community 28` to `Community 33`, `Community 4`, `Community 7`, `Community 8`, `Community 44`, `Community 12`, `Community 16`, `Community 18`, `Community 21`, `Community 22`, `Community 55`, `Community 24`, `Community 26`, `Community 27`?**
  _High betweenness centrality (0.111) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `layers` (e.g. with `.activeCelIndex()` and `.activeLayerIsVector`) actually correct?**
  _`layers` has 56 INFERRED edges - model-reasoned connections that need verification._
- **What connects `gallery`, `sizePicker`, `editor` to the rest of the system?**
  _243 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.09433962264150944 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.06416999789606564 - nodes in this community are weakly interconnected._