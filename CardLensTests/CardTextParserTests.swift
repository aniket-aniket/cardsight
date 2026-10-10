import XCTest
@testable import CardLens

/// Line layouts mirror real Vision output captured from official card scans.
final class CardTextParserTests: XCTestCase {
    private func line(_ text: String, y: CGFloat, h: CGFloat = 0.03) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: 0.1, y: y, width: 0.5, height: h), confidence: 0.9)
    }

    func testModernExCard() {
        let lines = [
            line("Charizard eX", y: 0.02, h: 0.041),
            line("$330 %", y: 0.02, h: 0.048),
            line("Brave Wing", y: 0.58, h: 0.049),
            line("6 6 Explosive Vortex", y: 0.72),
            line("weakness", y: 0.87),
            line("x 2", y: 0.88),
            line("006/165", y: 0.93, h: 0.02),
            line("is Knocked Out, your opponent takes 2 Prize cards.", y: 0.95, h: 0.02),
        ]
        let parsed = CardTextParser.parse(lines)
        XCTAssertEqual(parsed.names.first, "Charizard eX")
        XCTAssertEqual(parsed.number, "006")
        XCTAssertEqual(parsed.setTotal, "165")
    }

    func testVintageCardWithHP() {
        let lines = [
            line("Charizard", y: 0.04, h: 0.041),
            line("120 HP1", y: 0.04, h: 0.042),
            line("Pokémen Power: Energy Burn", y: 0.58),
            line("unintentionally cause forest fires. LV. 76 #6", y: 0.9),
            line("4/102 *", y: 0.96, h: 0.02),
        ]
        let parsed = CardTextParser.parse(lines)
        XCTAssertEqual(parsed.names.first, "Charizard")
        XCTAssertEqual(parsed.number, "4")
        XCTAssertEqual(parsed.setTotal, "102")
        XCTAssertEqual(parsed.hp, 120)
    }

    func testStageLabelIsNotAName() {
        let lines = [
            line("STAGE 1", y: 0.02, h: 0.02),
            line("Furret", y: 0.03, h: 0.045),
            line("136/189 •", y: 0.93, h: 0.02),
        ]
        let parsed = CardTextParser.parse(lines)
        XCTAssertEqual(parsed.names, ["Furret"])
        XCTAssertEqual(parsed.number, "136")
        XCTAssertEqual(parsed.setTotal, "189")
    }

    func testTrainerGalleryNumber() {
        let lines = [line("Pikachu V", y: 0.03, h: 0.045), line("TG05/TG30", y: 0.94, h: 0.02)]
        let parsed = CardTextParser.parse(lines)
        XCTAssertEqual(parsed.names.first, "Pikachu V")
        XCTAssertEqual(parsed.number, "TG05")
        XCTAssertEqual(parsed.setTotal, "TG30")
    }

    func testPromoNumber() {
        let lines = [line("Pikachu", y: 0.03, h: 0.045), line("SWSH050", y: 0.94, h: 0.02),
                     line("filler", y: 0.5), line("more filler", y: 0.6)]
        XCTAssertEqual(CardTextParser.parse(lines).number, "SWSH050")
    }

    func testDamageFractionInBodyIsIgnored() {
        let lines = [line("Mewtwo", y: 0.03, h: 0.045), line("Heal 30/60 damage", y: 0.4),
                     line("text", y: 0.5), line("text two", y: 0.6)]
        XCTAssertNil(CardTextParser.parse(lines).number)
    }

    func testNothingReadable() {
        let parsed = CardTextParser.parse([line("%% 12", y: 0.03)])
        XCTAssertTrue(parsed.isEmpty)
    }
}
