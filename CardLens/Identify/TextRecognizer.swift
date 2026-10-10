import CoreGraphics
import Vision

/// On-device text recognition with Vision. No image ever leaves the phone for this step.
enum TextRecognizer {
    static func recognize(in image: CGImage) async throws -> [RecognizedLine] {
        // Not detached: runs off the main actor anyway, and stays cancellable from the caller.
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Pokémon names are invented words, so dictionary correction makes them worse.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let b = observation.boundingBox
            // Vision uses a bottom-left origin; flip to top-left.
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            return RecognizedLine(text: candidate.string, box: box, confidence: candidate.confidence)
        }
    }
}
