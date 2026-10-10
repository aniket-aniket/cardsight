import XCTest
@testable import CardLens

final class ConfidenceScorerTests: XCTestCase {
    func testNumberNormalization() {
        XCTAssertEqual(ConfidenceScorer.normalizeNumber("006"), "6")
        XCTAssertEqual(ConfidenceScorer.normalizeNumber("4"), "4")
        XCTAssertEqual(ConfidenceScorer.normalizeNumber("TG05"), "TG5")
        XCTAssertEqual(ConfidenceScorer.normalizeNumber("swsh050"), "SWSH50")
        XCTAssertEqual(ConfidenceScorer.normalizeNumber("000"), "0")
    }

    func testNameSimilarity() {
        XCTAssertEqual(ConfidenceScorer.nameSimilarity("Charizard eX", "Charizard ex"), 1)
        XCTAssertEqual(ConfidenceScorer.nameSimilarity("Flabébé", "Flabebe"), 1)
        XCTAssertGreaterThanOrEqual(ConfidenceScorer.nameSimilarity("Charizard", "Charizard ex"), 0.85)
        XCTAssertGreaterThan(ConfidenceScorer.nameSimilarity("Charlzard", "Charizard"), 0.85)
        XCTAssertLessThan(ConfidenceScorer.nameSimilarity("Pikachu", "Charizard"), 0.3)
    }

    /// Base Set and Base Set 2 Charizard share artwork and number; the set total tells them apart.
    func testSetTotalSeparatesReprints() {
        let parsed = ParsedCardText(names: ["Charizard"], number: "4", setTotal: "102")
        let baseSet = ConfidenceScorer.textScore(name: "Charizard", number: "4", setOfficialCount: 102, parsed: parsed)
        let baseSet2 = ConfidenceScorer.textScore(name: "Charizard", number: "4", setOfficialCount: 130, parsed: parsed)
        XCTAssertEqual(baseSet, 1, accuracy: 0.001)
        XCTAssertLessThan(baseSet2, baseSet)
    }

    func testMisreadNameStillMatchesOnNumber() {
        let parsed = ParsedCardText(names: ["Xqzt"], number: "136", setTotal: "189")
        let score = ConfidenceScorer.textScore(name: "Furret", number: "136", setOfficialCount: 189, parsed: parsed)
        XCTAssertGreaterThan(score, ConfidenceScorer.minimumTextScore)
    }

    func testWrongCardScoresBelowThreshold() {
        let parsed = ParsedCardText(names: ["Furret"], number: "136", setTotal: "189")
        let score = ConfidenceScorer.textScore(name: "Pikachu", number: "25", setOfficialCount: 102, parsed: parsed)
        XCTAssertLessThan(score, ConfidenceScorer.minimumTextScore)
    }

    func testConfidenceLevels() {
        XCTAssertEqual(ConfidenceScorer.level(best: 0.92, runnerUp: 0.6, numberRead: true), .high)
        // Near tie, e.g. identical artwork in two sets → not high.
        XCTAssertNotEqual(ConfidenceScorer.level(best: 0.92, runnerUp: 0.9, numberRead: true), .high)
        // No collector number read → never high.
        XCTAssertNotEqual(ConfidenceScorer.level(best: 0.95, runnerUp: 0.4, numberRead: false), .high)
        XCTAssertEqual(ConfidenceScorer.level(best: 0.4, runnerUp: nil, numberRead: true), .low)
    }

    func testVisualSimilarityCalibration() {
        XCTAssertGreaterThan(VisualMatcher.similarity(forDistance: 0.67), 0.75)
        XCTAssertLessThan(VisualMatcher.similarity(forDistance: 0.9), 0.5)
        XCTAssertEqual(VisualMatcher.similarity(forDistance: 1.3), 0)
    }
}
