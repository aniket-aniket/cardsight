import CoreGraphics
import XCTest
@testable import CardLens

final class CenteringAnalyzerTests: XCTestCase {
    /// A 63×88-proportioned card: yellow border with a grey inner frame at the given offsets (px).
    private func card(left: Int, right: Int, top: Int, bottom: Int, plain: Bool = false) -> CGImage {
        let w = 630, h = 880
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.98, green: 0.82, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if !plain {
            ctx.setFillColor(CGColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1))
            // CoreGraphics origin is bottom-left.
            ctx.fill(CGRect(x: left, y: bottom, width: w - left - right, height: h - top - bottom))
        }
        return ctx.makeImage()!
    }

    func testPerfectlyCentered() throws {
        let result = try XCTUnwrap(CenteringAnalyzer.measure(card(left: 30, right: 30, top: 30, bottom: 30)))
        XCTAssertEqual(result.horizontalSplit.0, 50)
        XCTAssertEqual(result.verticalSplit.0, 50)
        XCTAssertEqual(result.bestPSAGrade, 10)
    }

    func testLeftRightOffCentre() throws {
        let result = try XCTUnwrap(CenteringAnalyzer.measure(card(left: 20, right: 40, top: 30, bottom: 30)))
        XCTAssertEqual(result.horizontalSplit.0, 33, accuracy: 1)
        XCTAssertEqual(result.bestPSAGrade, 7)
    }

    func testTopBottomOffCentre() throws {
        let result = try XCTUnwrap(CenteringAnalyzer.measure(card(left: 30, right: 30, top: 36, bottom: 24)))
        XCTAssertEqual(result.verticalSplit.0, 60, accuracy: 1)
        XCTAssertEqual(result.bestPSAGrade, 9)
    }

    func testNoBorderIsNotMeasured() {
        XCTAssertNil(CenteringAnalyzer.measure(card(left: 0, right: 0, top: 0, bottom: 0, plain: true)))
    }

    func testWrongShapeIsNotMeasured() {
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        XCTAssertNil(CenteringAnalyzer.measure(ctx.makeImage()!))
    }

    func testConsensusIgnoresArtworkOutliers() {
        let widths: [Double] = Array(repeating: 19, count: 22) + [12, 12, 13, 13, 14, 14, 15, 15, 27, 28]
        XCTAssertEqual(CenteringAnalyzer.consensusWidth(widths, scanlines: 41, minimum: 5) ?? 0, 19, accuracy: 0.01)
        XCTAssertNil(CenteringAnalyzer.consensusWidth([5, 9, 13, 17, 21, 25], scanlines: 41, minimum: 2))
    }
}
