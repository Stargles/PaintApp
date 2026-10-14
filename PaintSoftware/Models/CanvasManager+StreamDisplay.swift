import UIKit

/// A stream is reference in every saved picture. This recipe exists only on the canvas: its
/// frozen sources explicitly include the In Place elements and transient ink at their own layers.
struct StreamDisplayRecipe {
    let recipe: FrameRecipe
    let core: CGRect
    let buffer: CGRect

    /// Full-width rows, because several effects read horizontally beyond their input footprint.
    /// Grow the output for effects, then give that output an additional apron of real input.
    static func windows(footprint: CGRect, canvasSize: CGSize, apron: Int) -> (core: CGRect, buffer: CGRect)? {
        let frame = CGRect(origin: .zero, size: canvasSize)
        guard !footprint.isNull, !footprint.isEmpty else { return nil }
        let affected = footprint.insetBy(dx: 0, dy: -CGFloat(apron)).integral.intersection(frame)
        guard !affected.isNull, !affected.isEmpty else { return nil }
        let core = CGRect(x: 0, y: affected.minY, width: frame.width, height: affected.height)
        return (core, core.insetBy(dx: 0, dy: -CGFloat(apron)).intersection(frame))
    }
}

extension CanvasManager {
    @MainActor
    func inPlaceStreams() -> [(layerIndex: Int, vector: VectorCanvas, ids: Set<UUID>)] {
        streamLayerIndices(holding: liveEdit).compactMap { index in
            guard let celIndex = displayedCelIndex(inLayer: index, atFrame: currentFrame),
                  let vector = layers[index].cels[celIndex].vector else { return nil }
            let ids = Set(vector.streams.filter {
                $0.rendersInPlace && vector.streamWindow(id: $0.id) != nil
            }.map(\.id))
            return ids.isEmpty ? nil : (index, vector, ids)
        }
    }

    @MainActor
    func makeStreamDisplayRecipe(display: [UUID: PixelOps.CelDisplay] = [:],
                                 transientBounds: CGRect = .null,
                                 sizing: RenderSizing = .liveComposite) -> StreamDisplayRecipe? {
        let streams = inPlaceStreams()
        guard !streams.isEmpty, let size = canvasSize else { return nil }
        var values = display
        var footprint = transientBounds
        for entry in streams {
            let id = layers[entry.layerIndex].id
            if values[id]?.vector == nil {
                var value = values[id] ?? PixelOps.CelDisplay()
                value.vector = entry.vector.freezeDisplay(quality: .full, referenceIDs: entry.ids)
                values[id] = value
            }
            for elementID in entry.ids {
                if let rect = entry.vector.streamWindow(id: elementID) {
                    footprint = footprint.union(rect.applying(entry.vector.transform))
                }
            }
        }
        guard let whole = makeFrameRecipe(atFrame: currentFrame, includeBackground: true,
                                          sizing: sizing, holding: liveEdit,
                                          liveDisplay: values) else { return nil }
        let scale = CGAffineTransform(scaleX: whole.canvasSize.width / size.width,
                                      y: whole.canvasSize.height / size.height)
        let apron = StripedCompositor.apron(of: whole.tree, maskStacks: whole.maskStacks,
            frameSize: (Int(whole.canvasSize.width), Int(whole.canvasSize.height)))
        guard let windows = StreamDisplayRecipe.windows(footprint: footprint.applying(scale),
                                                        canvasSize: whole.canvasSize, apron: apron)
        else { return nil }
        return StreamDisplayRecipe(recipe: whole.windowed(to: windows.buffer),
                                   core: windows.core, buffer: windows.buffer)
    }
}
