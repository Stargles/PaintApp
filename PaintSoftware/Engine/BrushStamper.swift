import UIKit
import CoreGraphics

/// The single source of truth for turning brush + input samples into stamps on a
/// `RasterLayerTexture`. Both live raster drawing (`StrokeCanvasView`) and vector re-rendering
/// (`VectorCanvas.render`) go through here, so a vector stroke rasterizes identically to how it
/// would have been drawn live — same shape/hardness/dynamics/grain/scatter/spacing.
enum BrushStamper {
    struct Sample {
        var point: CGPoint
        var pressure: CGFloat
    }

    /// Distance between consecutive stamps along a path. The 1pt floor keeps thin or tight-spacing
    /// brushes continuous even at `spacingFraction` ~= 0.
    static func stampSpacing(brushSize: CGFloat, brush: Brush) -> CGFloat {
        max(brushSize * CGFloat(brush.spacingFraction), 1)
    }

    /// Walks from `last` toward `point`, invoking `body` at each `spacing`-sized step along the way,
    /// and returns the position of the final stamp — the carry point the next walk continues from.
    /// When the two points are closer together than one spacing, nothing is stamped and `last` comes
    /// straight back, so the leftover distance accumulates into the next call instead of being
    /// stamped short (which is what keeps a slow drag from bunching dabs up at the start).
    ///
    /// This is the arithmetic both callers share, and all they share: `stampStroke` below replays a
    /// whole finished stroke in one call and holds the carry point in a local, while
    /// `StrokeCanvasView.stampPath` is called once per incoming touch sample and holds it in a
    /// property across calls. Returning the carry point rather than storing it is what lets one
    /// helper serve both.
    static func advance(from last: CGPoint, to point: CGPoint, spacing: CGFloat,
                        _ body: (CGPoint) -> Void) -> CGPoint {
        let dx = point.x - last.x, dy = point.y - last.y
        let distance = hypot(dx, dy)
        guard spacing > 0, distance >= spacing else { return last }
        let steps = Int(distance / spacing)
        for i in 1...steps {
            let t = (CGFloat(i) * spacing) / distance
            body(CGPoint(x: last.x + dx * t, y: last.y + dy * t))
        }
        let coveredT = (CGFloat(steps) * spacing) / distance
        return CGPoint(x: last.x + dx * coveredT, y: last.y + dy * coveredT)
    }

    /// Replays a whole stroke (spacing-interpolated between samples, exactly like
    /// `StrokeCanvasView.stampPath`) into `raster`, as one `beginStroke`/`endStroke` unit.
    static func stampStroke(into raster: DabTarget, samples: [Sample], brush: Brush,
                            color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool = false) {
        guard !samples.isEmpty else { return }
        raster.beginStroke()
        let spacing = stampSpacing(brushSize: brushSize, brush: brush)
        var last: CGPoint?
        for sample in samples {
            let point = sample.point
            guard let lastPoint = last else {
                stampDab(into: raster, at: point, pressure: sample.pressure, brush: brush, color: color,
                         brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
                last = point
                continue
            }
            last = advance(from: lastPoint, to: point, spacing: spacing) { dab in
                stampDab(into: raster, at: dab, pressure: sample.pressure, brush: brush, color: color,
                         brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
            }
        }
        raster.endStroke()
    }

    /// Stamps one dab, honoring the brush's shape/hardness/pressure dynamics/scatter/grain. Ported
    /// verbatim from `StrokeCanvasView.stampOne` so live and replayed strokes match exactly.
    ///
    /// The eraser reuses this exact pipeline rather than a special-cased hard circle: it "paints"
    /// with the same shape/dynamics/spacing/grain as any other brush, just composited with
    /// `.destinationOut` instead of the brush's own blend mode — i.e. painting with 0 opacity as the
    /// color, so its stamp punches a hole instead of adding color. `color` is irrelevant under
    /// `.destinationOut` (only the stamp's alpha coverage matters), so it's ignored for an eraser dab.
    static func stampDab(into raster: DabTarget, at point: CGPoint, pressure: CGFloat,
                         brush: Brush, color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool) {
        let pressureValue = Double(max(0, min(pressure, 1)))
        let sizeFraction = brush.dynamics.sizeFraction(forPressure: pressureValue)
        let opacityFraction = brush.dynamics.opacityFraction(forPressure: pressureValue)
        let diameter = max(brushSize * CGFloat(sizeFraction), 0.5)
        let radius = diameter / 2
        let alpha = CGFloat(brushOpacity) * CGFloat(brush.flow) * CGFloat(opacityFraction)
        guard alpha > 0, radius > 0 else { return }

        let stampPoint = applyScatter(to: point, radius: radius, scatter: brush.scatter)
        let hardness = CGFloat(brush.hardness)
        let blendMode = isEraser ? CGBlendMode.destinationOut : brush.blendMode.cgBlendMode

        switch brush.shape {
        case .softRound, .hardRound, .pen:
            raster.stampCircle(at: stampPoint, radius: radius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
        case .pencil:
            let grainMultiplier = brush.grain.isEnabled ? grainAlphaMultiplier(at: stampPoint, grain: brush.grain) : 1
            raster.stampCircle(at: stampPoint, radius: radius, color: color, alpha: alpha * grainMultiplier, hardness: hardness, blendMode: blendMode)
        case .square, .custom:
            let rotation: CGFloat = brush.rotationJitter > 0
                ? CGFloat.random(in: -CGFloat.pi...CGFloat.pi) * CGFloat(brush.rotationJitter)
                : 0
            stampApproximateSquare(into: raster, at: stampPoint, diameter: diameter, rotation: rotation,
                                   color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
        }
    }

    static func applyScatter(to point: CGPoint, radius: CGFloat, scatter: Double) -> CGPoint {
        guard scatter > 0 else { return point }
        let maxOffset = radius * 2 * CGFloat(scatter)
        let angle = CGFloat.random(in: 0..<(2 * .pi))
        let distance = CGFloat.random(in: 0...maxOffset)
        return CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
    }

    static func grainAlphaMultiplier(at point: CGPoint, grain: BrushGrain) -> CGFloat {
        let noise = BrushGrain.noiseValue(atX: Double(point.x), y: Double(point.y), scale: grain.scale, rotation: grain.rotation)
        let depth = CGFloat(max(0, min(grain.depth, 1)))
        return (1 - depth) + depth * CGFloat(noise)
    }

    static func stampApproximateSquare(into raster: DabTarget, at center: CGPoint, diameter: CGFloat,
                                       rotation: CGFloat, color: UIColor, alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0 else { return }
        let half = diameter / 2
        let dabDiameter = max(diameter * 0.42, 1)
        let dabRadius = dabDiameter / 2
        let step = max(dabDiameter * 0.65, 1)
        let cosR = cos(rotation), sinR = sin(rotation)
        var y = -half
        while y <= half {
            var x = -half
            while x <= half {
                let rx = x * cosR - y * sinR
                let ry = x * sinR + y * cosR
                raster.stampCircle(at: CGPoint(x: center.x + rx, y: center.y + ry), radius: dabRadius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
                x += step
            }
            y += step
        }
    }
}
