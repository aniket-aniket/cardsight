import CoreGraphics
import Foundation

/// Border widths of a card photo, as fractions of the card's width (left/right) or height (top/bottom).
struct CenteringResult: Equatable, Sendable {
    let left: Double
    let right: Double
    let top: Double
    let bottom: Double

    /// e.g. (54, 46): share of the horizontal border on the left vs right, in percent.
    var horizontalSplit: (Int, Int) { Self.split(left, right) }
    var verticalSplit: (Int, Int) { Self.split(top, bottom) }

    /// The larger side's share on the worse axis, e.g. 58 for a 58/42 card.
    var worstSide: Double {
        max(Self.share(left, right), Self.share(top, bottom))
    }

    /// Best PSA grade allowed by front centering alone (PSA's published front tolerances).
    var bestPSAGrade: Int? {
        CenteringAnalyzer.psaFrontLimits.first { worstSide <= $0.maxSide + 0.5 }?.grade
    }

    private static func share(_ a: Double, _ b: Double) -> Double {
        let total = a + b
        return total > 0 ? max(a, b) / total * 100 : 50
    }

    private static func split(_ a: Double, _ b: Double) -> (Int, Int) {
        let total = a + b
        guard total > 0 else { return (50, 50) }
        let first = Int((a / total * 100).rounded())
        return (first, 100 - first)
    }
}

/// Measures border centering on a straightened, tightly cropped card image.
///
/// For each edge it samples many scanlines, takes the border colour just inside the edge,
/// and walks inward until the colour clearly changes (the start of the inner frame).
/// The median across scanlines is that edge's border width. If the scanlines disagree
/// (glare, full-art cards with no plain border, loose crop), it returns nil rather than a number.
enum CenteringAnalyzer {
    /// PSA front-centering limits: the larger side may be at most this percent.
    static let psaFrontLimits: [(grade: Int, maxSide: Double)] = [
        (10, 55), (9, 60), (8, 65), (7, 70), (6, 80), (5, 85), (4, 85), (3, 90),
    ]

    private static let workWidth = 500
    private static let cardAspect = 63.0 / 88.0

    static func measure(_ image: CGImage) -> CenteringResult? {
        let aspect = Double(image.width) / Double(max(image.height, 1))
        // Only meaningful when the crop is the card itself.
        guard abs(aspect - cardAspect) < 0.07 else { return nil }

        let width = workWidth
        let height = Int((Double(workWidth) / aspect).rounded())
        guard let pixels = rgba(image, width: width, height: height) else { return nil }

        func pixel(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * width + x) * 4
            return (Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
        }

        guard let left = edge(length: height, depth: width, sample: { along, depth in pixel(depth, along) }),
              let right = edge(length: height, depth: width, sample: { along, depth in pixel(width - 1 - depth, along) }),
              let top = edge(length: width, depth: height, sample: { along, depth in pixel(along, depth) }),
              let bottom = edge(length: width, depth: height, sample: { along, depth in pixel(along, height - 1 - depth) })
        else { return nil }

        return CenteringResult(left: left / Double(width), right: right / Double(width),
                               top: top / Double(height), bottom: bottom / Double(height))
    }

    /// Border width in pixels for one edge, or nil if it can't be measured reliably.
    private static func edge(length: Int, depth: Int,
                             sample: (_ along: Int, _ depth: Int) -> (Double, Double, Double)) -> Double? {
        let start = max(2, Int(Double(depth) * 0.012))        // skip crop slop at the very edge
        let maxDepth = Int(Double(depth) * 0.16)              // borders are never this thick
        let lines = 41
        var widths: [Double] = []

        for i in 0..<lines {
            // Middle 70% of the edge, away from rounded corners.
            let along = Int(Double(length) * (0.15 + 0.7 * Double(i) / Double(lines - 1)))
            let reference = average((start..<(start + 4)).map { sample(along, $0) })
            var run = 0
            for d in (start + 4)..<maxDepth {
                if distance(sample(along, d), reference) > 55 {
                    run += 1
                    if run == 3 { widths.append(Double(d - 2)); break }
                } else {
                    run = 0
                }
            }
        }

        return consensusWidth(widths, scanlines: lines, minimum: Double(depth) * 0.012)
    }

    /// The border's inner edge is a straight line, so most scanlines land on the same width,
    /// while artwork or text touching the border scatters a minority. Take the tightest
    /// cluster (±1 px) and require enough scanlines to agree on it.
    static func consensusWidth(_ widths: [Double], scanlines: Int, minimum: Double) -> Double? {
        guard !widths.isEmpty else { return nil }
        var best: [Double] = []
        for center in Set(widths.map { $0.rounded() }) {
            let cluster = widths.filter { abs($0 - center) <= 1 }
            if cluster.count > best.count { best = cluster }
        }
        guard Double(best.count) >= Double(scanlines) * 0.4 else { return nil }
        let width = best.reduce(0, +) / Double(best.count)
        return width >= minimum ? width : nil
    }

    private static func average(_ colors: [(Double, Double, Double)]) -> (Double, Double, Double) {
        let n = Double(colors.count)
        return (colors.map(\.0).reduce(0, +) / n, colors.map(\.1).reduce(0, +) / n, colors.map(\.2).reduce(0, +) / n)
    }

    private static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }
}
