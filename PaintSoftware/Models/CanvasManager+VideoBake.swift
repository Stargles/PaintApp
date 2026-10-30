import Foundation
import UIKit

extension CanvasManager {
    enum VideoBakeOutcome: Equatable {
        case baked(cels: Int)
        case refused(VideoBakeRefusal)
    }
    enum VideoBakeRefusal: Error, Equatable {
        case noVideo, unreadableAsset, noDecodableFrames, pendingEdit, videoTiming, sourceUnavailable
        var phrase: String {
            switch self {
            case .videoTiming: return "the video timing cannot be divided into those drawings"
            case .noVideo: return "this block doesn't hold a video"
            case .unreadableAsset: return "that video's file can't be read"
            case .pendingEdit: return "the held picture could not be placed; try again"
            case .noDecodableFrames: return "no frames could be read from that video"
            case .sourceUnavailable: return "those pictures could not be prepared; try again"
            }
        }
    }

    /// Freeze only metadata and immutable handles on main. The shared canvas-preparation lane
    /// prepares private cels off-main; one source is copied, durably checkpointed and released
    /// before the next frame. A failure never publishes cuts, pixels, pose changes or history.
    @MainActor
    func bakeVideoToCels(layerIndex: Int, celIndex: Int,
                         completion: @escaping (VideoBakeOutcome) -> Void) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              let vector = layers[layerIndex].cels[celIndex].vector,
              vector.holdsVideo, let firstVideo = vector.videos.first else { completion(.refused(.noVideo)); return }
        guard !isUpdatingCanvas, let pending = prepareCanvasEdit() else { completion(.refused(.pendingEdit)); return }
        let original = layers[layerIndex].cels[celIndex]
        let start = original.startFrame, end = original.endFrame
        guard let splits = prepareCelSplits(inLayerAt: layerIndex, at: (start + 1)..<end,
                                            stagedCels: pending.cels) else { completion(.refused(.videoTiming)); return }
        let identity = CanvasPixelTransformInput(self)
        let layerID = layers[layerIndex].id
        let originalCels = layers[layerIndex].cels
        var frozen = originalCels.map { pending.cels[$0.id] ?? $0 }
        guard let target = frozen.firstIndex(where: { $0.id == original.id }) else { completion(.refused(.pendingEdit)); return }
        frozen[target].vector = frozen[target].vector?.makeCopy()
        frozen[target].raster = frozen[target].raster.makeCopy()
        let client = videoFrames
        let scheduled = prepareCanvasUpdate { [weak self] in
            guard self != nil else { return nil }
            return {
                let result = Self.prepareVideoBake(cels: frozen, splits: splits, span: start..<end,
                                                   firstVideo: firstVideo, client: client)
                return { [weak self] in
                    guard let self else { return }
                    guard identity.stillMatches(self), self.celSplitPlanIsCurrent(splits),
                          let index = self.layers.firstIndex(where: { $0.id == layerID }),
                          self.layers[index].cels.count == originalCels.count,
                          zip(originalCels, self.layers[index].cels).allSatisfy({ old, current in
                              old.id == current.id && old.transformTracks == current.transformTracks
                                  && old.pendingPoseBaselines == current.pendingPoseBaselines
                          }) else { completion(.refused(.pendingEdit)); return }
                    switch result {
                    case .failure(let refusal): completion(.refused(refusal))
                    case .success(let prepared):
                        guard pending.commit(), self.commitAllInteractiveState() else { completion(.refused(.pendingEdit)); return }
                        self.withStructureUndo(label: .bakeVideoToImages) {
                            self.layers[index].cels = prepared.cels
                            self.noteKeyframeCrop(prepared.crop)
                            for celIndex in prepared.cels.indices where prepared.cels[celIndex].startFrame >= start
                                && prepared.cels[celIndex].endFrame <= end {
                                self.celContentChangedOutsideStroke(layerID: layerID, celID: prepared.cels[celIndex].id)
                            }
                        }
                        completion(.baked(cels: end - start))
                    }
                }
            }
        }
        if !scheduled { completion(.refused(.pendingEdit)) }
    }

    private struct PreparedVideoBake {
        let cels: [Cel]
        let crop: KeyframeCrop
    }

    private static func prepareVideoBake(cels: [Cel], splits: CelSplitPlan, span: Range<Int>,
                                         firstVideo: VectorVideoElement, client: VideoFrameSource.Client)
        -> Result<PreparedVideoBake, VideoBakeRefusal> {
        guard !client.isClosed else { return .failure(.sourceUnavailable) }
        guard client.info(for: firstVideo.assetURL) != nil else { return .failure(.unreadableAsset) }
        guard let prepared = materializeCelSplits(splits, from: cels) else { return .failure(.videoTiming) }
        var outputs = prepared.cels
        var anyDecodes = false
        for index in outputs.indices where outputs[index].startFrame >= span.lowerBound && outputs[index].endFrame <= span.upperBound {
            guard !client.isClosed else { return .failure(.sourceUnavailable) }
            let result: Result<Cel, VideoBakeRefusal> = autoreleasepool {
                var cel = outputs[index]
                guard let canvas = cel.vector else { return .failure(.sourceUnavailable) }
                let mappings = poseMappings(cel.transformTracks, atCelLocalFrame: 0)
                let posed = Self.posed(canvas.elements, through: mappings, inheriting: nil)
                var elements: [VectorElement] = []
                for element in posed {
                    guard case .video(let video) = element else { elements.append(element.reidentified()); continue }
                    let time = VideoFrameMap.sourceTime(of: video, atDocumentFrame: cel.startFrame,
                        celStartFrame: cel.startFrame, documentFPS: video.resolvedFrameRate)
                    switch client.read(assetURL: video.assetURL, at: time) {
                    case .unavailable: return .failure(.sourceUnavailable)
                    case .missing: elements.append(element) // An individual missing frame keeps its video.
                    case .decoded(let frame):
                        guard let cg = frame.makeImage(),
                              case .success(let source) = RasterSource.capturePlaced(UIImage(cgImage: cg), using: cel.raster.residency) else { return .failure(.sourceUnavailable) }
                        let durable = ProjectStore.serializingPackageMutation { source.checkpointForEviction() }
                        guard case .success = durable, source.releaseResidentPixels() else { return .failure(.sourceUnavailable) }
                        var image = VectorImageElement(source: source, transform: video.transform,
                            aspect: video.aspect, stretchAxis: video.stretchAxis, mirrored: video.mirrored)
                        image.animationGroupID = video.animationGroupID
                        elements.append(.image(image))
                        if video.id == firstVideo.id { anyDecodes = true }
                    }
                }
                cel.vector = VectorCanvas(size: canvas.size, elements: elements, transform: canvas.transform)
                cel.transformTracks = [:]; cel.pendingPoseBaselines = [:]
                return .success(cel)
            }
            switch result {
            case .success(let cel): outputs[index] = cel
            case .failure(let failure): return .failure(failure)
            }
        }
        guard anyDecodes else { return .failure(.noDecodableFrames) }
        return .success(PreparedVideoBake(cels: outputs, crop: prepared.crop))
    }
}
