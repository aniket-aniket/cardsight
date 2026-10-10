import CoreImage
import UIKit
import Vision

/// Four corners of the card, normalized 0…1 with the origin at the image's top-left.
struct CardQuad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let fullImage = CardQuad(topLeft: .init(x: 0, y: 0), topRight: .init(x: 1, y: 0),
                                    bottomRight: .init(x: 1, y: 1), bottomLeft: .init(x: 0, y: 1))

    /// A centered card-shaped box, used when edge detection finds nothing.
    static func centeredCard(imageSize: CGSize) -> CardQuad {
        let cardAspect: CGFloat = 63.0 / 88.0
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        var w: CGFloat = 0.84, h: CGFloat = 0.84
        if imageAspect > cardAspect { w = h * cardAspect / imageAspect } else { h = w * imageAspect / cardAspect }
        let x = (1 - w) / 2, y = (1 - h) / 2
        return CardQuad(topLeft: .init(x: x, y: y), topRight: .init(x: x + w, y: y),
                        bottomRight: .init(x: x + w, y: y + h), bottomLeft: .init(x: x, y: y + h))
    }

    var corners: [CGPoint] {
        get { [topLeft, topRight, bottomRight, bottomLeft] }
        set {
            topLeft = newValue[0]; topRight = newValue[1]
            bottomRight = newValue[2]; bottomLeft = newValue[3]
        }
    }
}

enum CardRectifier {
    private static let context = CIContext()

    /// Finds the card's outline with Vision rectangle detection.
    static func detectCard(in image: UIImage) async -> CardQuad? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> CardQuad? in
            let request = VNDetectRectanglesRequest()
            // Pokémon cards are 63 × 88 mm (ratio ≈ 0.716); allow for perspective.
            request.minimumAspectRatio = 0.55
            request.maximumAspectRatio = 0.9
            request.minimumSize = 0.25
            request.quadratureTolerance = 25
            request.minimumConfidence = 0.6
            request.maximumObservations = 1
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            guard (try? handler.perform([request])) != nil,
                  let rect = request.results?.first else { return nil }
            func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
            return CardQuad(topLeft: flip(rect.topLeft), topRight: flip(rect.topRight),
                            bottomRight: flip(rect.bottomRight), bottomLeft: flip(rect.bottomLeft))
        }.value
    }

    /// Crops and straightens the card to a flat, upright rectangle.
    static func extract(_ quad: CardQuad, from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        if quad == .fullImage { return image }

        let input = CIImage(cgImage: cgImage)
        let w = input.extent.width, h = input.extent.height
        // Core Image uses a bottom-left origin in pixels.
        func ci(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: (1 - p.y) * h) }

        let output = input.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": ci(quad.topLeft),
            "inputTopRight": ci(quad.topRight),
            "inputBottomRight": ci(quad.bottomRight),
            "inputBottomLeft": ci(quad.bottomLeft),
        ])
        guard let result = context.createCGImage(output, from: output.extent) else { return nil }
        let flat = UIImage(cgImage: result)
        // Keep the card portrait.
        return flat.size.width > flat.size.height * 1.05 ? flat.rotatedClockwise() : flat
    }
}
