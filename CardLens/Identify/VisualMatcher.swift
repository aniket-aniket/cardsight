import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Compares the scanned card with official card images using Vision feature prints.
/// Separates reprints and alternate arts that share a name and number.
enum VisualMatcher {
    /// Calibrated on card images degraded to look like photos:
    /// same card ≈ 0.65–0.70, identical-art reprint ≈ 0.70–0.72,
    /// same Pokémon with different art ≈ 0.85–0.92, unrelated card ≈ 1.0–1.18.
    static let identicalDistance: Float = 0.55
    static let unrelatedDistance: Float = 1.15

    static func featurePrint(for image: CGImage) async throws -> VNFeaturePrintObservation {
        try Task.checkCancellation()
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw AppError.unreadableImage
        }
        return observation
    }

    /// 0…1, higher means the artwork looks more alike.
    static func similarity(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Double? {
        var distance: Float = 0
        do {
            try a.computeDistance(&distance, to: b)
        } catch {
            return nil
        }
        return similarity(forDistance: distance)
    }

    static func similarity(forDistance distance: Float) -> Double {
        let t = (unrelatedDistance - distance) / (unrelatedDistance - identicalDistance)
        return Double(max(0, min(1, t)))
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
