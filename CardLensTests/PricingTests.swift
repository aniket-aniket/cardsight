import XCTest
@testable import CardLens

final class PricingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDecodesRealTCGdexCard() throws {
        let detail = try JSONDecoder().decode(CardDetail.self, from: fixture("card_base1-4"))
        XCTAssertEqual(detail.name, "Charizard")
        XCTAssertEqual(detail.set.name, "Base Set")
        XCTAssertEqual(detail.set.cardCount?.official, 102)
        XCTAssertEqual(detail.rarity, "Rare")

        let tcgplayer = try XCTUnwrap(detail.pricing?.tcgplayer)
        XCTAssertEqual(tcgplayer.unit, "USD")
        XCTAssertNotNil(tcgplayer.updated)
        XCTAssertEqual(tcgplayer.variants["holofoil"]?.marketPrice, 928.32)

        let match = CardMatch(detail: detail)
        XCTAssertEqual(match.numberDisplay, "4/102")
        XCTAssertEqual(match.imageURL?.absoluteString, "https://assets.tcgdex.net/en/base/base1/4/high.webp")
    }

    func testQuoteUsesProviderTimestampsAndPicksHolo() throws {
        let detail = try JSONDecoder().decode(CardDetail.self, from: fixture("card_base1-4"))
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        let quote = try XCTUnwrap(TCGdexPriceService.quote(from: detail, checkedAt: checked))
        XCTAssertEqual(quote.currency, "USD")
        XCTAssertEqual(quote.checkedAt, checked)
        XCTAssertNotNil(quote.sourceUpdated)
        XCTAssertEqual(quote.primaryVariant(rarity: detail.rarity)?.key, "holofoil")
        XCTAssertEqual(quote.primaryVariant(rarity: detail.rarity)?.productURL?.absoluteString,
                       "https://www.tcgplayer.com/product/42382")
    }

    /// No invented prices: a card without TCGplayer data yields no quote.
    func testMissingPricingIsUnavailable() throws {
        let json = """
        {"id":"x-1","localId":"1","name":"Test","set":{"id":"x","name":"X"},"pricing":{"cardmarket":{"unit":"EUR","avg":1.2}}}
        """
        let detail = try JSONDecoder().decode(CardDetail.self, from: Data(json.utf8))
        XCTAssertNil(TCGdexPriceService.quote(from: detail, checkedAt: .now))
    }

    func testNullPricesAreUnavailable() throws {
        let json = """
        {"id":"x-1","localId":"1","name":"Test","set":{"id":"x","name":"X"},
         "pricing":{"tcgplayer":{"unit":"USD","updated":"2026-10-08T22:54:34Z","normal":{"productId":1,"lowPrice":null,"midPrice":null,"highPrice":null,"marketPrice":null}}}}
        """
        let detail = try JSONDecoder().decode(CardDetail.self, from: Data(json.utf8))
        XCTAssertNil(TCGdexPriceService.quote(from: detail, checkedAt: .now))
    }

    func testSummarySetIdAndDigitalFilter() {
        let physical = CardSummary(id: "sv03.5-006", localId: "006", name: "Charizard ex",
                                   image: "https://assets.tcgdex.net/en/sv/sv03.5/006")
        let pocket = CardSummary(id: "A2b-010", localId: "010", name: "Charizard ex",
                                 image: "https://assets.tcgdex.net/en/tcgp/A2b/010")
        XCTAssertEqual(physical.setId, "sv03.5")
        XCTAssertFalse(physical.isDigitalOnly)
        XCTAssertTrue(pocket.isDigitalOnly)
    }
}
