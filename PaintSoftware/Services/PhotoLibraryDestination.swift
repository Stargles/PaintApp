import Photos

/// TODO (126) — the Photos library as an export's destination: the file becomes a new asset in the
/// camera roll, and anything that syncs the camera roll (Google Photos) picks it up from there.
///
/// **Add-only access** (`NSPhotoLibraryAddUsageDescription`, `.addOnly`): the app only ever writes to
/// the library, so it never asks to read the artist's photos and the system's prompt says so. A file
/// is *copied* in, not moved — the export stays in `tmp/PaintAppExports` for the share sheet and for
/// Send to Computer.
struct PhotoLibraryDestination: PhotosDestination {

    func save(_ file: URL, as kind: FrameExport.Kind) async -> PhotosSaveResult {
        guard let resource = Self.resourceType(for: kind) else {
            return .failed("Photos cannot hold this kind of file.")
        }
        // Answers at once when the artist has already chosen; prompts only the first time.
        switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
        case .authorized, .limited:
            break
        case .denied, .restricted, .notDetermined:
            return .denied
        @unknown default:
            return .denied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                PHAssetCreationRequest.forAsset().addResource(with: resource, fileURL: file, options: options)
            }
            return .saved
        } catch let error as PHPhotosError where error.code == .accessUserDenied
                                              || error.code == .accessRestricted {
            // The permission was withdrawn between the prompt's answer and the write.
            return .denied
        } catch {
            return .failed("Photos would not take the file: \(error.localizedDescription)")
        }
    }

    /// How Photos files each kind of export: a PNG (or any still) as a photo, a movie as a video.
    /// Nil for a file Photos has no word for.
    static func resourceType(for kind: FrameExport.Kind) -> PHAssetResourceType? {
        switch kind {
        case .image: return .photo
        case .video: return .video
        case .other: return nil
        }
    }
}
