import UIKit

extension CardIdentifier {
    func identify(_ image: UIImage, progress: @escaping @MainActor (IdentificationStep) -> Void) async throws -> IdentificationResult {
        let prepared = image.normalizedForProcessing()
        guard let photo = prepared.cgImage,
              let ocrImage = prepared.upscaledForTextRecognition().cgImage else {
            throw AppError.unreadableImage
        }
        return try await identify(photo: photo, ocrImage: ocrImage, progress: progress)
    }
}
