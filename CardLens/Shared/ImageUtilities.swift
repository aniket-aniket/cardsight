import UIKit

extension UIImage {
    /// Applies EXIF orientation and limits size so Vision and Core Image work on predictable pixels.
    func normalizedForProcessing(maxDimension: CGFloat = 2400) -> UIImage {
        let longest = max(size.width, size.height)
        let factor = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        if imageOrientation == .up && factor == 1 && scale == 1 { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Upscales small crops so the tiny collector number is tall enough for text recognition.
    func upscaledForTextRecognition(minHeight: CGFloat = 1400) -> UIImage {
        let height = size.height * scale
        guard height > 0, height < minHeight else { return self }
        let factor = minHeight / height
        let target = CGSize(width: (size.width * scale * factor).rounded(), height: minHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    func rotatedClockwise() -> UIImage {
        let source = normalizedForProcessing()
        let target = CGSize(width: source.size.height, height: source.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: target.width / 2, y: target.height / 2)
            cg.rotate(by: .pi / 2)
            source.draw(in: CGRect(x: -source.size.width / 2, y: -source.size.height / 2,
                                   width: source.size.width, height: source.size.height))
        }
    }

    func thumbnailData(maxDimension: CGFloat = 240) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let factor = min(1, maxDimension / longest)
        let target = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumb = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return thumb.jpegData(compressionQuality: 0.75)
    }
}
