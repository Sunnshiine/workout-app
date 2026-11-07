import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Imports a movie from Photos. No library permission: the picker runs out of the app's process
/// and hands back only what the athlete chose.
struct FormClipPhotosPicker: UIViewControllerRepresentable {
    /// Nil when the athlete cancels. The pick loads off the main actor, since a long movie or an
    /// iCloud one takes time, so the card shows the work rather than the picker holding the screen.
    let onPicked: (NSItemProvider?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (NSItemProvider?) -> Void

        init(onPicked: @escaping (NSItemProvider?) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPicked(results.first?.itemProvider)
        }
    }
}

extension NSItemProvider {
    /// Copies the picked movie out before the provider deletes its own temporary file.
    func loadFormClipMovie() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { file, error in
                guard let file else {
                    continuation.resume(throwing: error ?? FormClipError.notAMovie)
                    return
                }
                do {
                    let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(file.pathExtension)")
                    try FileManager.default.copyItem(at: file, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Films a clip with the system camera, which brings its own controls and its own permission asks.
struct FormClipCamera: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(UTType.movie.identifier)
    }

    /// Nil when the athlete cancels.
    let onFinished: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.mediaTypes = [UTType.movie.identifier]
        camera.cameraCaptureMode = .video
        camera.videoQuality = .typeHigh
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinished: (URL?) -> Void

        init(onFinished: @escaping (URL?) -> Void) {
            self.onFinished = onFinished
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinished(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinished(nil)
        }
    }
}
